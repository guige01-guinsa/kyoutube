-- Forward-only correction for 0014: fully qualify every relation column in
-- the two RPCs so OUT parameters cannot shadow ledger or table columns.

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

  select ledger.result into v_result
  from public.kitchen_shopping_idempotency as ledger
  where ledger.owner_id = v_owner_id
    and ledger.operation = 'create'
    and ledger.idempotency_key = p_idempotency_key;
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

  for v_item in select element.value from jsonb_array_elements(p_items) as element(value)
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

  select lower(btrim(element.value ->> 'ingredient_text')) into v_normalized_name
  from jsonb_array_elements(p_items) as element(value)
  group by lower(btrim(element.value ->> 'ingredient_text'))
  having count(*) > 1
  limit 1;
  if v_normalized_name is not null then
    raise exception 'duplicate ingredient text is not allowed';
  end if;

  insert into public.kitchen_shopping_lists (
    owner_id, source_recipe_id, title, status, create_idempotency_key
  ) values (
    v_owner_id, p_source_recipe_id, '장보기 목록', 'active', p_idempotency_key
  ) returning public.kitchen_shopping_lists.id into v_list_id;

  insert into public.kitchen_shopping_items (
    list_id, owner_id, name, ingredient_text, quantity, unit, is_checked, status
  )
  select
    v_list_id,
    v_owner_id,
    btrim(element.value ->> 'ingredient_text'),
    btrim(element.value ->> 'ingredient_text'),
    case when element.value ? 'quantity' then (element.value ->> 'quantity')::numeric else null end,
    case when element.value ? 'unit' then btrim(element.value ->> 'unit') else null end,
    false,
    'pending'
  from jsonb_array_elements(p_items) as element(value);

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
  v_list_status text;
  v_list_completed_at timestamptz;
  v_list_inventory_change_count integer;
  v_item record;
  v_inventory record;
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
  select ledger.result into v_result
  from public.kitchen_shopping_idempotency as ledger
  where ledger.owner_id = v_owner_id
    and ledger.operation = 'complete'
    and ledger.idempotency_key = p_idempotency_key;
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

  select
    list.status,
    list.completed_at,
    list.completion_inventory_change_count
  into v_list_status, v_list_completed_at, v_list_inventory_change_count
  from public.kitchen_shopping_lists as list
  where list.id = p_list_id and list.owner_id = v_owner_id
  for update;
  if not found then
    raise exception 'shopping list was not found for the authenticated user';
  end if;

  select
    count(*) filter (where item.status = 'pending'),
    count(*) filter (where item.status = 'purchased'),
    count(*) filter (where item.status = 'skipped'),
    count(*) filter (where item.status = 'unavailable')
  into v_pending_count, v_purchased_count, v_skipped_count, v_unavailable_count
  from public.kitchen_shopping_items as item
  where item.list_id = p_list_id and item.owner_id = v_owner_id;

  if v_list_status = 'completed' then
    v_result := jsonb_build_object(
      'list_id', p_list_id, 'status', 'completed', 'completed_at', v_list_completed_at,
      'purchased_count', v_purchased_count, 'skipped_count', v_skipped_count,
      'unavailable_count', v_unavailable_count,
      'inventory_change_count', v_list_inventory_change_count
    );
    insert into public.kitchen_shopping_idempotency (
      owner_id, operation, idempotency_key, list_id, result
    ) values (v_owner_id, 'complete', p_idempotency_key, p_list_id, v_result);
    return query select p_list_id, 'completed', false, false, v_list_completed_at,
      v_purchased_count, v_skipped_count, v_unavailable_count,
      v_list_inventory_change_count, p_idempotency_key;
    return;
  end if;
  if v_list_status <> 'active' then
    raise exception 'only active shopping lists can be completed';
  end if;
  if v_pending_count > 0 then
    raise exception 'pending shopping items must be resolved before completion';
  end if;

  for v_item in
    select item.id as item_id, item.ingredient_text, item.quantity, item.unit
    from public.kitchen_shopping_items as item
    where item.list_id = p_list_id
      and item.owner_id = v_owner_id
      and item.status = 'purchased'
    order by item.id
    for update
  loop
    if v_item.quantity is null then
      raise exception 'purchased shopping items require an explicit positive quantity';
    end if;
    select ingredient.id as ingredient_id, ingredient.quantity, ingredient.unit
    into v_inventory
    from public.kitchen_ingredients as ingredient
    where ingredient.owner_id = v_owner_id
      and ingredient.normalized_name = lower(btrim(v_item.ingredient_text))
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
      null;
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
      update public.kitchen_ingredients as ingredient
      set quantity = v_inventory.quantity + v_incoming_quantity,
          updated_at = now()
      where ingredient.id = v_inventory.ingredient_id
        and ingredient.owner_id = v_owner_id;
      v_inventory_change_count := v_inventory_change_count + 1;
    end if;
  end loop;

  update public.kitchen_shopping_lists as list
  set status = 'completed',
      completed_at = now(),
      completion_idempotency_key = p_idempotency_key,
      completion_inventory_change_count = v_inventory_change_count,
      updated_at = now()
  where list.id = p_list_id and list.owner_id = v_owner_id
  returning list.completed_at into v_list_completed_at;

  v_result := jsonb_build_object(
    'list_id', p_list_id, 'status', 'completed', 'completed_at', v_list_completed_at,
    'purchased_count', v_purchased_count, 'skipped_count', v_skipped_count,
    'unavailable_count', v_unavailable_count,
    'inventory_change_count', v_inventory_change_count
  );
  insert into public.kitchen_shopping_idempotency (
    owner_id, operation, idempotency_key, list_id, result
  ) values (v_owner_id, 'complete', p_idempotency_key, p_list_id, v_result);

  return query select p_list_id, 'completed', false, false, v_list_completed_at,
    v_purchased_count, v_skipped_count, v_unavailable_count,
    v_inventory_change_count, p_idempotency_key;
end;
$$;

revoke all on function public.create_kitchen_shopping_list(text, jsonb, uuid) from public, anon;
revoke all on function public.complete_kitchen_shopping_list(uuid, uuid) from public, anon;
grant execute on function public.create_kitchen_shopping_list(text, jsonb, uuid) to authenticated;
grant execute on function public.complete_kitchen_shopping_list(uuid, uuid) to authenticated;
