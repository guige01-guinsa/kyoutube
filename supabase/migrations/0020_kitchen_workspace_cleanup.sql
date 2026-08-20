-- User-facing kitchen workspace cleanup.
--
-- Ingredients are snapshotted and deleted.
-- Shopping lists are archived so their items remain intact and can be restored.
--
-- Undo policy:
-- - Each cleanup can be restored once.
-- - Each cleanup remains eligible for 30 minutes.
-- - Only the three most recent eligible cleanup snapshots remain undoable.

create table if not exists public.kitchen_cleanup_snapshots (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  idempotency_key uuid not null,
  clear_ingredients boolean not null default false,
  clear_active_shopping boolean not null default false,
  clear_completed_history boolean not null default false,
  ingredient_rows jsonb not null default '[]'::jsonb,
  shopping_list_states jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default transaction_timestamp(),
  expires_at timestamptz not null,
  restored_at timestamptz,
  unique (owner_id, idempotency_key)
);

create index if not exists idx_kitchen_cleanup_snapshots_owner_created
  on public.kitchen_cleanup_snapshots(owner_id, created_at desc);

alter table public.kitchen_cleanup_snapshots enable row level security;

create policy "kitchen_cleanup_snapshots_all_own"
on public.kitchen_cleanup_snapshots
for all
to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

create or replace function public.cleanup_kitchen_workspace(
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
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_owner_id uuid := auth.uid();
  v_existing public.kitchen_cleanup_snapshots%rowtype;
  v_ingredient_rows jsonb := '[]'::jsonb;
  v_list_states jsonb := '[]'::jsonb;
  v_ingredient_count integer := 0;
  v_active_list_count integer := 0;
  v_completed_list_count integer := 0;
  v_open_item_count integer := 0;
  v_expires_at timestamptz := transaction_timestamp() + interval '30 minutes';
begin
  if v_owner_id is null then
    raise exception 'authentication required';
  end if;

  if p_idempotency_key is null then
    raise exception 'idempotency key is required';
  end if;

  if not coalesce(p_clear_ingredients, false)
     and not coalesce(p_clear_active_shopping, false)
     and not coalesce(p_clear_completed_history, false) then
    raise exception 'at least one cleanup option is required';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'kitchen-workspace-cleanup:' || v_owner_id::text || ':' || p_idempotency_key::text,
      0
    )
  );

  select *
  into v_existing
  from public.kitchen_cleanup_snapshots as snapshot
  where snapshot.owner_id = v_owner_id
    and snapshot.idempotency_key = p_idempotency_key;

  if found then
    return query
    select
      v_existing.id,
      jsonb_array_length(v_existing.ingredient_rows),
      (
        select count(*)::integer
        from jsonb_array_elements(v_existing.shopping_list_states) as state
        where state.value->>'status' = 'active'
      ),
      (
        select count(*)::integer
        from jsonb_array_elements(v_existing.shopping_list_states) as state
        where state.value->>'status' = 'completed'
      ),
      coalesce(
        (
          select sum(
            coalesce((state.value->>'open_item_count')::integer, 0)
          )::integer
          from jsonb_array_elements(v_existing.shopping_list_states) as state
          where state.value->>'status' = 'active'
        ),
        0
      ),
      v_existing.expires_at,
      true;
    return;
  end if;

  -- Retain only the two newest active undo snapshots before creating a new one.
  -- The new snapshot becomes the third eligible undo record.
  with snapshots_to_expire as (
    select snapshot.id
    from public.kitchen_cleanup_snapshots as snapshot
    where snapshot.owner_id = v_owner_id
      and snapshot.restored_at is null
      and snapshot.expires_at > transaction_timestamp()
    order by snapshot.created_at desc
    offset 2
  )
  update public.kitchen_cleanup_snapshots as snapshot
  set expires_at = transaction_timestamp()
  from snapshots_to_expire as expired
  where snapshot.id = expired.id;

  if coalesce(p_clear_ingredients, false) then
    select
      coalesce(jsonb_agg(to_jsonb(ingredient) order by ingredient.id), '[]'::jsonb),
      count(*)::integer
    into v_ingredient_rows, v_ingredient_count
    from public.kitchen_ingredients as ingredient
    where ingredient.owner_id = v_owner_id;
  end if;

  if coalesce(p_clear_active_shopping, false) then
    select count(*)::integer
    into v_active_list_count
    from public.kitchen_shopping_lists as list
    where list.owner_id = v_owner_id
      and list.status = 'active';

    select count(*)::integer
    into v_open_item_count
    from public.kitchen_shopping_items as item
    join public.kitchen_shopping_lists as list
      on list.id = item.list_id
     and list.owner_id = v_owner_id
    where item.owner_id = v_owner_id
      and list.status = 'active'
      and item.is_checked = false;

    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', list.id,
          'status', list.status,
          'open_item_count', (
            select count(*)::integer
            from public.kitchen_shopping_items as item
            where item.list_id = list.id
              and item.owner_id = v_owner_id
              and item.is_checked = false
          )
        )
        order by list.id
      ),
      '[]'::jsonb
    )
    into v_list_states
    from public.kitchen_shopping_lists as list
    where list.owner_id = v_owner_id
      and list.status = 'active';
  end if;

  if coalesce(p_clear_completed_history, false) then
    select count(*)::integer
    into v_completed_list_count
    from public.kitchen_shopping_lists as list
    where list.owner_id = v_owner_id
      and list.status = 'completed';

    select
      v_list_states || coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', list.id,
            'status', list.status,
            'open_item_count', 0
          )
          order by list.id
        ),
        '[]'::jsonb
      )
    into v_list_states
    from public.kitchen_shopping_lists as list
    where list.owner_id = v_owner_id
      and list.status = 'completed';
  end if;

  insert into public.kitchen_cleanup_snapshots(
    owner_id,
    idempotency_key,
    clear_ingredients,
    clear_active_shopping,
    clear_completed_history,
    ingredient_rows,
    shopping_list_states,
    expires_at
  )
  values (
    v_owner_id,
    p_idempotency_key,
    coalesce(p_clear_ingredients, false),
    coalesce(p_clear_active_shopping, false),
    coalesce(p_clear_completed_history, false),
    v_ingredient_rows,
    v_list_states,
    v_expires_at
  )
  returning id into snapshot_id;

  if coalesce(p_clear_ingredients, false) then
    delete from public.kitchen_ingredients
    where owner_id = v_owner_id;
  end if;

  if coalesce(p_clear_active_shopping, false) then
    update public.kitchen_shopping_lists
    set status = 'archived',
        updated_at = transaction_timestamp()
    where owner_id = v_owner_id
      and status = 'active';
  end if;

  if coalesce(p_clear_completed_history, false) then
    update public.kitchen_shopping_lists
    set status = 'archived',
        updated_at = transaction_timestamp()
    where owner_id = v_owner_id
      and status = 'completed';
  end if;

  ingredient_count := v_ingredient_count;
  active_list_count := v_active_list_count;
  completed_list_count := v_completed_list_count;
  open_item_count := v_open_item_count;
  expires_at := v_expires_at;
  replayed := false;

  return next;
end;
$$;

create or replace function public.restore_kitchen_workspace_cleanup(
  p_snapshot_id uuid
)
returns table (
  restored_ingredient_count integer,
  restored_active_list_count integer,
  restored_completed_list_count integer
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
  if v_owner_id is null then
    raise exception 'authentication required';
  end if;

  if p_snapshot_id is null then
    raise exception 'snapshot id is required';
  end if;

  select *
  into v_snapshot
  from public.kitchen_cleanup_snapshots as snapshot
  where snapshot.id = p_snapshot_id
    and snapshot.owner_id = v_owner_id
  for update;

  if not found then
    raise exception 'cleanup snapshot not found';
  end if;

  if v_snapshot.restored_at is not null then
    raise exception 'cleanup snapshot has already been restored';
  end if;

  if transaction_timestamp() > v_snapshot.expires_at then
    raise exception 'cleanup undo window has expired';
  end if;

  select existing.normalized_name
  into v_conflicting_name
  from public.kitchen_ingredients as existing
  join jsonb_to_recordset(v_snapshot.ingredient_rows) as saved(
    normalized_name text
  )
    on saved.normalized_name = existing.normalized_name
  where existing.owner_id = v_owner_id
  limit 1;

  if v_conflicting_name is not null then
    raise exception
      'cannot restore cleanup because ingredient "%" was added after cleanup',
      v_conflicting_name;
  end if;

  insert into public.kitchen_ingredients(
    id,
    owner_id,
    name,
    normalized_name,
    quantity,
    unit,
    storage_location,
    expires_on,
    note,
    created_at,
    updated_at
  )
  select
    saved.id,
    saved.owner_id,
    saved.name,
    saved.normalized_name,
    saved.quantity,
    saved.unit,
    saved.storage_location,
    saved.expires_on,
    saved.note,
    saved.created_at,
    saved.updated_at
  from jsonb_to_recordset(v_snapshot.ingredient_rows) as saved(
    id uuid,
    owner_id uuid,
    name text,
    normalized_name text,
    quantity numeric,
    unit text,
    storage_location text,
    expires_on date,
    note text,
    created_at timestamptz,
    updated_at timestamptz
  );

  update public.kitchen_shopping_lists as list
  set status = saved.status,
      updated_at = transaction_timestamp()
  from jsonb_to_recordset(v_snapshot.shopping_list_states) as saved(
    id uuid,
    status text,
    open_item_count integer
  )
  where list.id = saved.id
    and list.owner_id = v_owner_id
    and list.status = 'archived';

  update public.kitchen_cleanup_snapshots
  set restored_at = transaction_timestamp()
  where id = v_snapshot.id;

  restored_ingredient_count := jsonb_array_length(v_snapshot.ingredient_rows);

  select count(*)::integer
  into restored_active_list_count
  from jsonb_array_elements(v_snapshot.shopping_list_states) as state
  where state.value->>'status' = 'active';

  select count(*)::integer
  into restored_completed_list_count
  from jsonb_array_elements(v_snapshot.shopping_list_states) as state
  where state.value->>'status' = 'completed';

  return next;
end;
$$;

revoke all on function public.cleanup_kitchen_workspace(boolean, boolean, boolean, uuid)
  from public, anon;

revoke all on function public.restore_kitchen_workspace_cleanup(uuid)
  from public, anon;

grant execute on function public.cleanup_kitchen_workspace(boolean, boolean, boolean, uuid)
  to authenticated;

grant execute on function public.restore_kitchen_workspace_cleanup(uuid)
  to authenticated;

create or replace function public.list_kitchen_workspace_cleanup_snapshots()
returns table (
  snapshot_id uuid,
  ingredient_count integer,
  active_list_count integer,
  completed_list_count integer,
  open_item_count integer,
  created_at timestamptz,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_owner_id uuid := auth.uid();
begin
  if v_owner_id is null then
    raise exception 'authentication required';
  end if;

  return query
  select
    snapshot.id,
    jsonb_array_length(snapshot.ingredient_rows)::integer,
    (
      select count(*)::integer
      from jsonb_array_elements(snapshot.shopping_list_states) as state
      where state.value->>'status' = 'active'
    ),
    (
      select count(*)::integer
      from jsonb_array_elements(snapshot.shopping_list_states) as state
      where state.value->>'status' = 'completed'
    ),
    coalesce(
      (
        select sum(
          coalesce((state.value->>'open_item_count')::integer, 0)
        )::integer
        from jsonb_array_elements(snapshot.shopping_list_states) as state
        where state.value->>'status' = 'active'
      ),
      0
    ),
    snapshot.created_at,
    snapshot.expires_at
  from public.kitchen_cleanup_snapshots as snapshot
  where snapshot.owner_id = v_owner_id
    and snapshot.restored_at is null
    and snapshot.expires_at > transaction_timestamp()
  order by snapshot.created_at desc
  limit 3;
end;
$$;

revoke all on function public.list_kitchen_workspace_cleanup_snapshots()
  from public, anon;

grant execute on function public.list_kitchen_workspace_cleanup_snapshots()
  to authenticated;
