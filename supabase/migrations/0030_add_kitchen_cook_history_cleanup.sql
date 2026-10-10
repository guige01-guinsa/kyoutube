-- Let kitchen cleanup archive cooking-completion history with the same
-- 30-minute, per-user undo policy as the other kitchen data.

alter table public.kitchen_cleanup_snapshots
  add column if not exists clear_cook_history boolean not null default false,
  add column if not exists cook_session_rows jsonb not null default '[]'::jsonb;

create or replace function public.expire_empty_kitchen_cleanup_snapshot()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if coalesce(jsonb_array_length(new.ingredient_rows), 0) = 0
     and coalesce(jsonb_array_length(new.shopping_list_states), 0) = 0
     and coalesce(jsonb_array_length(new.cook_session_rows), 0) = 0 then
    new.expires_at := transaction_timestamp();
  end if;
  return new;
end;
$$;

drop function if exists public.cleanup_kitchen_workspace(boolean, boolean, boolean, uuid);
create function public.cleanup_kitchen_workspace(
  p_clear_ingredients boolean,
  p_clear_active_shopping boolean,
  p_clear_completed_history boolean,
  p_clear_cook_history boolean,
  p_idempotency_key uuid
)
returns table (
  snapshot_id uuid,
  ingredient_count integer,
  active_list_count integer,
  completed_list_count integer,
  cook_session_count integer,
  open_item_count integer,
  expires_at timestamptz,
  replayed boolean
)
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_owner_id uuid := auth.uid();
  v_existing public.kitchen_cleanup_snapshots%rowtype;
  v_ingredient_rows jsonb := '[]'::jsonb;
  v_list_states jsonb := '[]'::jsonb;
  v_cook_session_rows jsonb := '[]'::jsonb;
  v_ingredient_count integer := 0;
  v_active_list_count integer := 0;
  v_completed_list_count integer := 0;
  v_cook_session_count integer := 0;
  v_open_item_count integer := 0;
  v_expires_at timestamptz := transaction_timestamp() + interval '30 minutes';
begin
  if v_owner_id is null then raise exception 'authentication required'; end if;
  if p_idempotency_key is null then raise exception 'idempotency key is required'; end if;
  if not coalesce(p_clear_ingredients, false)
     and not coalesce(p_clear_active_shopping, false)
     and not coalesce(p_clear_completed_history, false)
     and not coalesce(p_clear_cook_history, false) then
    raise exception 'at least one cleanup option is required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'kitchen-workspace-cleanup:' || v_owner_id::text || ':' || p_idempotency_key::text, 0));
  select * into v_existing from public.kitchen_cleanup_snapshots as snapshot
    where snapshot.owner_id = v_owner_id and snapshot.idempotency_key = p_idempotency_key;
  if found then
    return query select
      v_existing.id,
      jsonb_array_length(v_existing.ingredient_rows),
      (select count(*)::integer from jsonb_array_elements(v_existing.shopping_list_states) as state where state.value->>'status' = 'active'),
      (select count(*)::integer from jsonb_array_elements(v_existing.shopping_list_states) as state where state.value->>'status' = 'completed'),
      jsonb_array_length(v_existing.cook_session_rows),
      coalesce((select sum(coalesce((state.value->>'open_item_count')::integer, 0))::integer from jsonb_array_elements(v_existing.shopping_list_states) as state where state.value->>'status' = 'active'), 0),
      v_existing.expires_at,
      true;
    return;
  end if;

  with snapshots_to_expire as (
    select snapshot.id from public.kitchen_cleanup_snapshots as snapshot
      where snapshot.owner_id = v_owner_id and snapshot.restored_at is null
        and snapshot.expires_at > transaction_timestamp()
      order by snapshot.created_at desc offset 2
  )
  update public.kitchen_cleanup_snapshots as snapshot
    set expires_at = transaction_timestamp()
    from snapshots_to_expire as expired where snapshot.id = expired.id;

  if coalesce(p_clear_ingredients, false) then
    select coalesce(jsonb_agg(to_jsonb(ingredient) order by ingredient.id), '[]'::jsonb), count(*)::integer
      into v_ingredient_rows, v_ingredient_count
      from public.kitchen_ingredients as ingredient where ingredient.owner_id = v_owner_id;
  end if;
  if coalesce(p_clear_active_shopping, false) then
    select count(*)::integer into v_active_list_count from public.kitchen_shopping_lists as list
      where list.owner_id = v_owner_id and list.status = 'active';
    select count(*)::integer into v_open_item_count from public.kitchen_shopping_items as item
      join public.kitchen_shopping_lists as list on list.id = item.list_id and list.owner_id = v_owner_id
      where item.owner_id = v_owner_id and list.status = 'active' and item.is_checked = false;
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', list.id, 'status', list.status,
      'open_item_count', (select count(*)::integer from public.kitchen_shopping_items as item where item.list_id = list.id and item.owner_id = v_owner_id and item.is_checked = false)
    ) order by list.id), '[]'::jsonb) into v_list_states
      from public.kitchen_shopping_lists as list where list.owner_id = v_owner_id and list.status = 'active';
  end if;
  if coalesce(p_clear_completed_history, false) then
    select count(*)::integer into v_completed_list_count from public.kitchen_shopping_lists as list
      where list.owner_id = v_owner_id and list.status = 'completed';
    select v_list_states || coalesce(jsonb_agg(jsonb_build_object('id', list.id, 'status', list.status, 'open_item_count', 0) order by list.id), '[]'::jsonb)
      into v_list_states from public.kitchen_shopping_lists as list
      where list.owner_id = v_owner_id and list.status = 'completed';
  end if;
  if coalesce(p_clear_cook_history, false) then
    select coalesce(jsonb_agg(to_jsonb(session) order by session.created_at desc, session.id), '[]'::jsonb), count(*)::integer
      into v_cook_session_rows, v_cook_session_count
      from public.kitchen_cook_sessions as session where session.owner_id = v_owner_id;
  end if;

  insert into public.kitchen_cleanup_snapshots(
    owner_id, idempotency_key, clear_ingredients, clear_active_shopping,
    clear_completed_history, clear_cook_history, ingredient_rows,
    shopping_list_states, cook_session_rows, expires_at
  ) values (
    v_owner_id, p_idempotency_key, coalesce(p_clear_ingredients, false),
    coalesce(p_clear_active_shopping, false), coalesce(p_clear_completed_history, false),
    coalesce(p_clear_cook_history, false), v_ingredient_rows, v_list_states,
    v_cook_session_rows, v_expires_at
  ) returning id into snapshot_id;

  if coalesce(p_clear_ingredients, false) then delete from public.kitchen_ingredients where owner_id = v_owner_id; end if;
  if coalesce(p_clear_active_shopping, false) then update public.kitchen_shopping_lists set status = 'archived', updated_at = transaction_timestamp() where owner_id = v_owner_id and status = 'active'; end if;
  if coalesce(p_clear_completed_history, false) then update public.kitchen_shopping_lists set status = 'archived', updated_at = transaction_timestamp() where owner_id = v_owner_id and status = 'completed'; end if;
  if coalesce(p_clear_cook_history, false) then delete from public.kitchen_cook_sessions where owner_id = v_owner_id; end if;

  ingredient_count := v_ingredient_count;
  active_list_count := v_active_list_count;
  completed_list_count := v_completed_list_count;
  cook_session_count := v_cook_session_count;
  open_item_count := v_open_item_count;
  expires_at := v_expires_at;
  replayed := false;
  return next;
end;
$$;

-- Keep the deployed API compatible until the Edge Function is updated to send
-- the additional cooking-history flag.
create function public.cleanup_kitchen_workspace(
  p_clear_ingredients boolean,
  p_clear_active_shopping boolean,
  p_clear_completed_history boolean,
  p_idempotency_key uuid
)
returns table (
  snapshot_id uuid,
  ingredient_count integer,
  active_list_count integer,
  completed_list_count integer,
  open_item_count integer,
  expires_at timestamptz,
  replayed boolean
)
language sql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select
    cleanup.snapshot_id,
    cleanup.ingredient_count,
    cleanup.active_list_count,
    cleanup.completed_list_count,
    cleanup.open_item_count,
    cleanup.expires_at,
    cleanup.replayed
  from public.cleanup_kitchen_workspace(
    p_clear_ingredients,
    p_clear_active_shopping,
    p_clear_completed_history,
    false,
    p_idempotency_key
  ) as cleanup;
$$;

drop function if exists public.restore_kitchen_workspace_cleanup(uuid);
create function public.restore_kitchen_workspace_cleanup(p_snapshot_id uuid)
returns table (
  restored_ingredient_count integer,
  restored_active_list_count integer,
  restored_completed_list_count integer,
  restored_cook_session_count integer
)
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_owner_id uuid := auth.uid();
  v_snapshot public.kitchen_cleanup_snapshots%rowtype;
  v_conflicting_name text;
begin
  if v_owner_id is null then raise exception 'authentication required'; end if;
  if p_snapshot_id is null then raise exception 'snapshot id is required'; end if;
  select * into v_snapshot from public.kitchen_cleanup_snapshots as snapshot
    where snapshot.id = p_snapshot_id and snapshot.owner_id = v_owner_id for update;
  if not found then raise exception 'cleanup snapshot not found'; end if;
  if v_snapshot.restored_at is not null then raise exception 'cleanup snapshot has already been restored'; end if;
  if transaction_timestamp() > v_snapshot.expires_at then raise exception 'cleanup undo window has expired'; end if;
  select existing.normalized_name into v_conflicting_name from public.kitchen_ingredients as existing
    join jsonb_to_recordset(v_snapshot.ingredient_rows) as saved(normalized_name text)
      on saved.normalized_name = existing.normalized_name
    where existing.owner_id = v_owner_id limit 1;
  if v_conflicting_name is not null then raise exception 'cannot restore cleanup because ingredient "%" was added after cleanup', v_conflicting_name; end if;

  insert into public.kitchen_ingredients(id, owner_id, name, normalized_name, quantity, unit, storage_location, expires_on, note, created_at, updated_at)
  select saved.id, saved.owner_id, saved.name, saved.normalized_name, saved.quantity, saved.unit, saved.storage_location, saved.expires_on, saved.note, saved.created_at, saved.updated_at
  from jsonb_to_recordset(v_snapshot.ingredient_rows) as saved(id uuid, owner_id uuid, name text, normalized_name text, quantity numeric, unit text, storage_location text, expires_on date, note text, created_at timestamptz, updated_at timestamptz);
  update public.kitchen_shopping_lists as list set status = saved.status, updated_at = transaction_timestamp()
    from jsonb_to_recordset(v_snapshot.shopping_list_states) as saved(id uuid, status text, open_item_count integer)
    where list.id = saved.id and list.owner_id = v_owner_id and list.status = 'archived';
  insert into public.kitchen_cook_sessions(id, owner_id, recipe_type, recipe_ref_id, recipe_title, consumed_ingredients, missing_ingredients, rating, liked, note, created_at)
  select saved.id, saved.owner_id, saved.recipe_type, saved.recipe_ref_id, saved.recipe_title, saved.consumed_ingredients, saved.missing_ingredients, saved.rating, saved.liked, saved.note, saved.created_at
  from jsonb_to_recordset(v_snapshot.cook_session_rows) as saved(id uuid, owner_id uuid, recipe_type text, recipe_ref_id text, recipe_title text, consumed_ingredients jsonb, missing_ingredients jsonb, rating integer, liked boolean, note text, created_at timestamptz);
  update public.kitchen_cleanup_snapshots set restored_at = transaction_timestamp() where id = v_snapshot.id;

  restored_ingredient_count := jsonb_array_length(v_snapshot.ingredient_rows);
  select count(*)::integer into restored_active_list_count from jsonb_array_elements(v_snapshot.shopping_list_states) as state where state.value->>'status' = 'active';
  select count(*)::integer into restored_completed_list_count from jsonb_array_elements(v_snapshot.shopping_list_states) as state where state.value->>'status' = 'completed';
  restored_cook_session_count := jsonb_array_length(v_snapshot.cook_session_rows);
  return next;
end;
$$;

drop function if exists public.list_kitchen_workspace_cleanup_snapshots();
create function public.list_kitchen_workspace_cleanup_snapshots()
returns table (
  snapshot_id uuid,
  ingredient_count integer,
  active_list_count integer,
  completed_list_count integer,
  cook_session_count integer,
  open_item_count integer,
  created_at timestamptz,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare v_owner_id uuid := auth.uid();
begin
  if v_owner_id is null then raise exception 'authentication required'; end if;
  return query select snapshot.id, jsonb_array_length(snapshot.ingredient_rows),
    (select count(*)::integer from jsonb_array_elements(snapshot.shopping_list_states) as state where state.value->>'status' = 'active'),
    (select count(*)::integer from jsonb_array_elements(snapshot.shopping_list_states) as state where state.value->>'status' = 'completed'),
    jsonb_array_length(snapshot.cook_session_rows),
    coalesce((select sum(coalesce((state.value->>'open_item_count')::integer, 0))::integer from jsonb_array_elements(snapshot.shopping_list_states) as state where state.value->>'status' = 'active'), 0),
    snapshot.created_at, snapshot.expires_at
  from public.kitchen_cleanup_snapshots as snapshot
  where snapshot.owner_id = v_owner_id and snapshot.restored_at is null and snapshot.expires_at > transaction_timestamp()
  order by snapshot.created_at desc limit 3;
end;
$$;

revoke all on function public.cleanup_kitchen_workspace(boolean, boolean, boolean, boolean, uuid) from public, anon;
revoke all on function public.cleanup_kitchen_workspace(boolean, boolean, boolean, uuid) from public, anon;
revoke all on function public.restore_kitchen_workspace_cleanup(uuid) from public, anon;
revoke all on function public.list_kitchen_workspace_cleanup_snapshots() from public, anon;
grant execute on function public.cleanup_kitchen_workspace(boolean, boolean, boolean, boolean, uuid) to authenticated;
grant execute on function public.cleanup_kitchen_workspace(boolean, boolean, boolean, uuid) to authenticated;
grant execute on function public.restore_kitchen_workspace_cleanup(uuid) to authenticated;
grant execute on function public.list_kitchen_workspace_cleanup_snapshots() to authenticated;
