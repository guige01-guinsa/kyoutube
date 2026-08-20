-- Atomic, owner-scoped shopping-list creation and completion.
-- This migration intentionally retains is_checked for the Flutter/Edge compatibility
-- window. New callers must use item.status; is_checked is derived for old clients.

do $$
begin
  if exists (
    select 1
    from public.kitchen_shopping_items as item
    join public.kitchen_shopping_lists as list on list.id = item.list_id
    where item.owner_id is distinct from list.owner_id
  ) then
    raise exception 'kitchen shopping owner mismatch must be repaired before 0014';
  end if;
end;
$$;

alter table public.kitchen_shopping_lists
  drop constraint if exists kitchen_shopping_lists_status_check;

alter table public.kitchen_shopping_lists
  add constraint kitchen_shopping_lists_status_check
    check (status in ('active', 'completed', 'cancelled', 'archived'));

alter table public.kitchen_shopping_lists
  add column if not exists completed_at timestamptz,
  add column if not exists cancelled_at timestamptz,
  add column if not exists create_idempotency_key uuid,
  add column if not exists completion_idempotency_key uuid,
  add column if not exists completion_inventory_change_count integer not null default 0;

alter table public.kitchen_shopping_items
  add column if not exists ingredient_text text,
  add column if not exists status text;

-- Existing completed/archived unchecked rows have no explicit historical outcome.
-- Map them to skipped so completed lists never contain a pending item. Existing
-- active unchecked rows remain pending; checked rows are purchased candidates.
update public.kitchen_shopping_items as item
set ingredient_text = item.name
where item.ingredient_text is null;

update public.kitchen_shopping_items as item
set status = case
  when item.is_checked then 'purchased'
  when list.status in ('completed', 'archived') then 'skipped'
  else 'pending'
end
from public.kitchen_shopping_lists as list
where list.id = item.list_id
  and item.status is null;

alter table public.kitchen_shopping_items
  alter column ingredient_text set not null,
  alter column status set default 'pending',
  alter column status set not null;

alter table public.kitchen_shopping_items
  drop constraint if exists kitchen_shopping_items_status_check;

alter table public.kitchen_shopping_items
  add constraint kitchen_shopping_items_status_check
    check (status in ('pending', 'purchased', 'skipped', 'unavailable'));

-- Compatibility window for clients that still toggle is_checked. New status-aware
-- clients own status; an old is_checked-only update maps true->purchased and
-- false->pending. A caller may not submit contradictory values for both fields.
create or replace function public.sync_kitchen_shopping_item_legacy_check()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_list_status text;
begin
  if tg_op = 'INSERT' then
    if new.ingredient_text is null then
      new.ingredient_text := new.name;
    end if;
    if new.status = 'purchased' then
      new.is_checked := true;
    elsif new.is_checked then
      new.status := 'purchased';
    else
      new.is_checked := false;
    end if;
    return new;
  end if;

  if new.status is distinct from old.status or new.is_checked is distinct from old.is_checked then
    select status into v_list_status
    from public.kitchen_shopping_lists
    where id = new.list_id and owner_id = new.owner_id;
    if v_list_status is distinct from 'active' then
      raise exception 'shopping item state can only change while its list is active';
    end if;
  end if;

  if new.status is distinct from old.status and new.is_checked is not distinct from old.is_checked then
    new.is_checked := (new.status = 'purchased');
  elsif new.is_checked is distinct from old.is_checked and new.status is not distinct from old.status then
    new.status := case when new.is_checked then 'purchased' else 'pending' end;
  elsif new.status is distinct from old.status and new.is_checked is distinct from old.is_checked
    and new.is_checked <> (new.status = 'purchased') then
    raise exception 'is_checked and status must not contradict each other';
  end if;
  return new;
end;
$$;

create trigger kitchen_shopping_items_legacy_check_sync
before insert or update of is_checked, status on public.kitchen_shopping_items
for each row execute function public.sync_kitchen_shopping_item_legacy_check();

alter table public.kitchen_shopping_lists
  add constraint kitchen_shopping_lists_id_owner_key unique (id, owner_id);

alter table public.kitchen_shopping_items
  add constraint kitchen_shopping_items_list_owner_fkey
    foreign key (list_id, owner_id)
    references public.kitchen_shopping_lists (id, owner_id);

create unique index kitchen_shopping_lists_owner_create_idempotency_key_idx
  on public.kitchen_shopping_lists (owner_id, create_idempotency_key)
  where create_idempotency_key is not null;

create table public.kitchen_shopping_idempotency (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  operation text not null check (operation in ('create', 'complete')),
  idempotency_key uuid not null,
  list_id uuid not null,
  result jsonb not null,
  created_at timestamptz not null default now(),
  primary key (owner_id, operation, idempotency_key),
  foreign key (list_id, owner_id)
    references public.kitchen_shopping_lists (id, owner_id)
);

alter table public.kitchen_shopping_idempotency enable row level security;

revoke all on table public.kitchen_shopping_idempotency from public, anon;

create policy "Users can read their kitchen idempotency results"
  on public.kitchen_shopping_idempotency
  for select to authenticated
  using (owner_id = auth.uid());

create or replace function public.create_kitchen_shopping_list(
  p_source_recipe_id text,
  p_items jsonb,
  p_idempotency_key uuid
)
returns table (
  list_id uuid,
  status text,
  created boolean,
  replayed boolean,
  completed_at timestamptz,
  purchased_count integer,
  skipped_count integer,
  unavailable_count integer,
  inventory_change_count integer,
  idempotency_key uuid
)
language plpgsql
-- SECURITY DEFINER is necessary because the private idempotency ledger has no
-- client write grant. auth.uid() is checked before every access and every
-- relation below is schema-qualified.
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_owner_id uuid := auth.uid();
  v_list_id uuid;
  v_result jsonb;
  v_item jsonb;
  v_normalized_name text;
begin
  if v_owner_id is null then
    raise exception 'authentication required';
  end if;
  if p_idempotency_key is null then
    raise exception 'idempotency key is required';
  end if;
  if p_source_recipe_id is null
     or btrim(p_source_recipe_id) = ''
     or p_source_recipe_id !~ '^(public|creator|user):.+' then
    raise exception 'source recipe reference must be a typed non-empty text value';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 100
     or octet_length(p_items::text) > 65536 then
    raise exception 'items must be a non-empty JSON array within the configured limits';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'kitchen-create:' || v_owner_id::text || ':' || p_idempotency_key::text, 0));

  select result into v_result
  from public.kitchen_shopping_idempotency
  where owner_id = v_owner_id
    and operation = 'create'
    and idempotency_key = p_idempotency_key;
  if found then
    return query select
      (v_result ->> 'list_id')::uuid, v_result ->> 'status', false, true,
      nullif(v_result ->> 'completed_at', '')::timestamptz,
      coalesce((v_result ->> 'purchased_count')::integer, 0),
      coalesce((v_result ->> 'skipped_count')::integer, 0),
      coalesce((v_result ->> 'unavailable_count')::integer, 0),
      coalesce((v_result ->> 'inventory_change_count')::integer, 0),
      p_idempotency_key;
    return;
  end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    if jsonb_typeof(v_item) <> 'object'
       or v_item ?| array['id', 'list_id', 'owner_id', 'status', 'is_checked', 'completed_at', 'inventory_change_count']
       or jsonb_typeof(v_item -> 'ingredient_text') <> 'string'
       or btrim(v_item ->> 'ingredient_text') = ''
       or (v_item ? 'quantity' and (jsonb_typeof(v_item -> 'quantity') <> 'number'
            or (v_item ->> 'quantity')::numeric <= 0))
       or (v_item ? 'unit' and (jsonb_typeof(v_item -> 'unit') <> 'string'
            or btrim(v_item ->> 'unit') = '')) then
      raise exception 'invalid kitchen shopping item payload';
    end if;
  end loop;

  select lower(btrim(value ->> 'ingredient_text')) into v_normalized_name
  from jsonb_array_elements(p_items)
  group by lower(btrim(value ->> 'ingredient_text'))
  having count(*) > 1
  limit 1;
  if v_normalized_name is not null then
    raise exception 'duplicate ingredient text is not allowed';
  end if;

  insert into public.kitchen_shopping_lists (
    owner_id, source_recipe_id, title, status, create_idempotency_key
  ) values (
    v_owner_id, p_source_recipe_id, '장보기 목록', 'active', p_idempotency_key
  ) returning id into v_list_id;

  insert into public.kitchen_shopping_items (
    list_id, owner_id, name, ingredient_text, quantity, unit, is_checked, status
  )
  select
    v_list_id,
    v_owner_id,
    btrim(value ->> 'ingredient_text'),
    btrim(value ->> 'ingredient_text'),
    case when value ? 'quantity' then (value ->> 'quantity')::numeric else null end,
    case when value ? 'unit' then btrim(value ->> 'unit') else null end,
    false,
    'pending'
  from jsonb_array_elements(p_items);

  v_result := jsonb_build_object(
    'list_id', v_list_id, 'status', 'active', 'completed_at', null,
    'purchased_count', 0, 'skipped_count', 0, 'unavailable_count', 0,
    'inventory_change_count', 0
  );
  insert into public.kitchen_shopping_idempotency (
    owner_id, operation, idempotency_key, list_id, result
  ) values (v_owner_id, 'create', p_idempotency_key, v_list_id, v_result);

  return query select v_list_id, 'active', true, false, null::timestamptz,
    0, 0, 0, 0, p_idempotency_key;
end;
$$;

create or replace function public.complete_kitchen_shopping_list(
  p_list_id uuid,
  p_idempotency_key uuid
)
returns table (
  list_id uuid,
  status text,
  created boolean,
  replayed boolean,
  completed_at timestamptz,
  purchased_count integer,
  skipped_count integer,
  unavailable_count integer,
  inventory_change_count integer,
  idempotency_key uuid
)
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_owner_id uuid := auth.uid();
  v_list public.kitchen_shopping_lists%rowtype;
  v_item public.kitchen_shopping_items%rowtype;
  v_inventory public.kitchen_ingredients%rowtype;
  v_result jsonb;
  v_purchased_count integer;
  v_skipped_count integer;
  v_unavailable_count integer;
  v_pending_count integer;
  v_inventory_change_count integer := 0;
  v_existing_unit text;
  v_incoming_unit text;
  v_incoming_quantity numeric;
begin
  if v_owner_id is null then
    raise exception 'authentication required';
  end if;
  if p_list_id is null or p_idempotency_key is null then
    raise exception 'list id and idempotency key are required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'kitchen-complete:' || v_owner_id::text || ':' || p_idempotency_key::text, 0));
  select result into v_result
  from public.kitchen_shopping_idempotency
  where owner_id = v_owner_id and operation = 'complete'
    and idempotency_key = p_idempotency_key;
  if found then
    return query select
      (v_result ->> 'list_id')::uuid, v_result ->> 'status', false, true,
      nullif(v_result ->> 'completed_at', '')::timestamptz,
      coalesce((v_result ->> 'purchased_count')::integer, 0),
      coalesce((v_result ->> 'skipped_count')::integer, 0),
      coalesce((v_result ->> 'unavailable_count')::integer, 0),
      coalesce((v_result ->> 'inventory_change_count')::integer, 0),
      p_idempotency_key;
    return;
  end if;

  select * into v_list
  from public.kitchen_shopping_lists
  where id = p_list_id and owner_id = v_owner_id
  for update;
  if not found then
    raise exception 'shopping list was not found for the authenticated user';
  end if;

  select
    count(*) filter (where status = 'pending'),
    count(*) filter (where status = 'purchased'),
    count(*) filter (where status = 'skipped'),
    count(*) filter (where status = 'unavailable')
  into v_pending_count, v_purchased_count, v_skipped_count, v_unavailable_count
  from public.kitchen_shopping_items
  where list_id = v_list.id and owner_id = v_owner_id;

  if v_list.status = 'completed' then
    v_result := jsonb_build_object(
      'list_id', v_list.id, 'status', 'completed', 'completed_at', v_list.completed_at,
      'purchased_count', v_purchased_count, 'skipped_count', v_skipped_count,
      'unavailable_count', v_unavailable_count,
      'inventory_change_count', v_list.completion_inventory_change_count
    );
    insert into public.kitchen_shopping_idempotency (
      owner_id, operation, idempotency_key, list_id, result
    ) values (v_owner_id, 'complete', p_idempotency_key, v_list.id, v_result);
    return query select v_list.id, 'completed', false, false, v_list.completed_at,
      v_purchased_count, v_skipped_count, v_unavailable_count,
      v_list.completion_inventory_change_count, p_idempotency_key;
    return;
  end if;
  if v_list.status <> 'active' then
    raise exception 'only active shopping lists can be completed';
  end if;
  if v_pending_count > 0 then
    raise exception 'pending shopping items must be resolved before completion';
  end if;

  for v_item in
    select * from public.kitchen_shopping_items
    where list_id = v_list.id and owner_id = v_owner_id and status = 'purchased'
    order by id
    for update
  loop
    select * into v_inventory
    from public.kitchen_ingredients
    where owner_id = v_owner_id
      and normalized_name = lower(btrim(v_item.ingredient_text))
    for update;

    if not found then
      insert into public.kitchen_ingredients (
        owner_id, name, normalized_name, quantity, unit
      ) values (
        v_owner_id, v_item.ingredient_text, lower(btrim(v_item.ingredient_text)),
        v_item.quantity, v_item.unit
      );
      v_inventory_change_count := v_inventory_change_count + 1;
    elsif v_inventory.quantity is null and v_item.quantity is null
      and coalesce(lower(btrim(v_inventory.unit)), '') = coalesce(lower(btrim(v_item.unit)), '') then
      null; -- No numeric quantity exists to merge; preserve the existing inventory row.
    elsif v_inventory.quantity is null or v_item.quantity is null
      or v_inventory.unit is null or v_item.unit is null then
      raise exception 'ambiguous inventory quantity or unit cannot be merged';
    else
      v_existing_unit := lower(btrim(v_inventory.unit));
      v_incoming_unit := lower(btrim(v_item.unit));
      v_incoming_quantity := v_item.quantity;
      if v_existing_unit = v_incoming_unit then
        null;
      elsif v_existing_unit = 'g' and v_incoming_unit = 'kg' then
        v_incoming_quantity := v_incoming_quantity * 1000;
      elsif v_existing_unit = 'kg' and v_incoming_unit = 'g' then
        v_incoming_quantity := v_incoming_quantity / 1000;
      elsif v_existing_unit = 'ml' and v_incoming_unit = 'l' then
        v_incoming_quantity := v_incoming_quantity * 1000;
      elsif v_existing_unit = 'l' and v_incoming_unit = 'ml' then
        v_incoming_quantity := v_incoming_quantity / 1000;
      else
        raise exception 'incompatible inventory units cannot be merged';
      end if;
      update public.kitchen_ingredients
      set quantity = v_inventory.quantity + v_incoming_quantity,
          updated_at = now()
      where id = v_inventory.id and owner_id = v_owner_id;
      v_inventory_change_count := v_inventory_change_count + 1;
    end if;
  end loop;

  update public.kitchen_shopping_lists
  set status = 'completed',
      completed_at = now(),
      completion_idempotency_key = p_idempotency_key,
      completion_inventory_change_count = v_inventory_change_count,
      updated_at = now()
  where id = v_list.id and owner_id = v_owner_id
  returning completed_at into v_list.completed_at;

  v_result := jsonb_build_object(
    'list_id', v_list.id, 'status', 'completed', 'completed_at', v_list.completed_at,
    'purchased_count', v_purchased_count, 'skipped_count', v_skipped_count,
    'unavailable_count', v_unavailable_count,
    'inventory_change_count', v_inventory_change_count
  );
  insert into public.kitchen_shopping_idempotency (
    owner_id, operation, idempotency_key, list_id, result
  ) values (v_owner_id, 'complete', p_idempotency_key, v_list.id, v_result);

  return query select v_list.id, 'completed', false, false, v_list.completed_at,
    v_purchased_count, v_skipped_count, v_unavailable_count,
    v_inventory_change_count, p_idempotency_key;
end;
$$;

revoke all on function public.create_kitchen_shopping_list(text, jsonb, uuid) from public, anon;
revoke all on function public.complete_kitchen_shopping_list(uuid, uuid) from public, anon;
grant execute on function public.create_kitchen_shopping_list(text, jsonb, uuid) to authenticated;
grant execute on function public.complete_kitchen_shopping_list(uuid, uuid) to authenticated;
