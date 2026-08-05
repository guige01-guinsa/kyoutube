-- Forward-only create-RPC contract correction: name is canonical, while
-- ingredient_text is the untouched source expression retained for review.

create or replace function public.create_kitchen_shopping_list(
  p_source_recipe_id text,
  p_items jsonb,
  p_idempotency_key uuid
)
returns table (
  list_id uuid, status text, created boolean, replayed boolean,
  completed_at timestamptz, purchased_count integer, skipped_count integer,
  unavailable_count integer, inventory_change_count integer, idempotency_key uuid
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
  if v_owner_id is null then raise exception 'authentication required'; end if;
  if p_idempotency_key is null then raise exception 'idempotency key is required'; end if;
  if p_source_recipe_id is null or btrim(p_source_recipe_id) = ''
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
      coalesce((v_result ->> 'inventory_change_count')::integer, 0), p_idempotency_key;
    return;
  end if;

  for v_item in select element.value from jsonb_array_elements(p_items) as element(value)
  loop
    if jsonb_typeof(v_item) <> 'object'
       or v_item ?| array['id','list_id','owner_id','normalized_name','status','is_checked','completed_at','inventory_change_count']
       or jsonb_typeof(v_item -> 'name') <> 'string'
       or btrim(v_item ->> 'name') = ''
       or char_length(btrim(v_item ->> 'name')) > 200
       or jsonb_typeof(v_item -> 'ingredient_text') <> 'string'
       or btrim(v_item ->> 'ingredient_text') = ''
       or char_length(v_item ->> 'ingredient_text') > 500
       or (v_item ? 'quantity' and jsonb_typeof(v_item -> 'quantity') <> 'null'
           and (jsonb_typeof(v_item -> 'quantity') <> 'number' or (v_item ->> 'quantity')::numeric <= 0))
       or (v_item ? 'unit' and jsonb_typeof(v_item -> 'unit') <> 'null'
           and (jsonb_typeof(v_item -> 'unit') <> 'string' or btrim(v_item ->> 'unit') = ''
             or char_length(btrim(v_item ->> 'unit')) > 32)) then
      raise exception 'invalid kitchen shopping item payload';
    end if;
  end loop;

  select lower(btrim(element.value ->> 'name')) into v_normalized_name
  from jsonb_array_elements(p_items) as element(value)
  group by lower(btrim(element.value ->> 'name'))
  having count(*) > 1
  limit 1;
  if v_normalized_name is not null then
    raise exception 'duplicate canonical ingredient name is not allowed';
  end if;

  insert into public.kitchen_shopping_lists (
    owner_id, source_recipe_id, title, status, create_idempotency_key
  ) values (v_owner_id, p_source_recipe_id, '장보기 목록', 'active', p_idempotency_key)
  returning public.kitchen_shopping_lists.id into v_list_id;

  insert into public.kitchen_shopping_items (
    list_id, owner_id, name, normalized_name, ingredient_text, quantity, unit, is_checked, status
  )
  select
    v_list_id,
    v_owner_id,
    btrim(element.value ->> 'name'),
    lower(btrim(element.value ->> 'name')),
    element.value ->> 'ingredient_text',
    case when element.value ? 'quantity' and jsonb_typeof(element.value -> 'quantity') <> 'null'
      then (element.value ->> 'quantity')::numeric else null end,
    case when element.value ? 'unit' and jsonb_typeof(element.value -> 'unit') <> 'null'
      then btrim(element.value ->> 'unit') else null end,
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

revoke all on function public.create_kitchen_shopping_list(text, jsonb, uuid) from public, anon;
grant execute on function public.create_kitchen_shopping_list(text, jsonb, uuid) to authenticated;
