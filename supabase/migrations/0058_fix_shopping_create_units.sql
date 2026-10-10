-- Preserve purchase-unit conversions such as 125 g = 0.125 kg.
alter table public.kitchen_shopping_items alter column quantity type numeric(18,6);

-- Fix recipe-to-shopping creation for the units already supported by 0029.
-- Preserve raw recipe text and quantities; never convert cooking units to mass.
-- Existing RLS, managed-field validation, atomic writes and idempotency remain.

create or replace function public.create_kitchen_shopping_list(p_source_recipe_id text, p_items jsonb, p_idempotency_key uuid)
returns table (list_id uuid, status text, created boolean, replayed boolean, completed_at timestamptz, purchased_count integer, skipped_count integer, unavailable_count integer, inventory_change_count integer, idempotency_key uuid)
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_owner_id uuid := auth.uid(); v_list_id uuid; v_result jsonb; v_item jsonb;
  v_normalized_name text; v_unit text; v_quantity numeric;
  v_supported_units constant text[] := array['g','kg','oz','lb','ml','l','tsp','tbsp','cup','fl_oz','pint','quart','gallon',
    'ea','piece','slice','clove','stalk','head','dozen',
    'pack','bag','bottle','jar','can','carton','box','case','bundle','bunch','net',
    'container','sachet','pouch','tube','tray','roll'];
begin
  if v_owner_id is null then raise exception 'authentication required'; end if;
  if p_idempotency_key is null then raise exception 'idempotency key is required'; end if;
  if p_source_recipe_id is null or btrim(p_source_recipe_id) = '' or p_source_recipe_id !~ '^(public|creator|user):.+' then raise exception 'source recipe reference must be a typed non-empty text value'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 100 or octet_length(p_items::text) > 65536 then raise exception 'items must be a non-empty JSON array within the configured limits'; end if;
  perform pg_advisory_xact_lock(hashtextextended('kitchen-create:' || v_owner_id::text || ':' || p_idempotency_key::text, 0));
  select ledger.result into v_result from public.kitchen_shopping_idempotency as ledger where ledger.owner_id=v_owner_id and ledger.operation='create' and ledger.idempotency_key=p_idempotency_key;
  if found then
    return query select (v_result->>'list_id')::uuid,v_result->>'status',false,true,nullif(v_result->>'completed_at','')::timestamptz,coalesce((v_result->>'purchased_count')::integer,0),coalesce((v_result->>'skipped_count')::integer,0),coalesce((v_result->>'unavailable_count')::integer,0),coalesce((v_result->>'inventory_change_count')::integer,0),p_idempotency_key;
    return;
  end if;
  for v_item in select element.value from jsonb_array_elements(p_items) as element(value) loop
    if jsonb_typeof(v_item) <> 'object' or v_item ?| array['id','list_id','owner_id','normalized_name','review_status','reviewed_at','revision','status','is_checked','completed_at','inventory_change_count'] or jsonb_typeof(v_item->'name') <> 'string' or btrim(v_item->>'name')='' or char_length(btrim(v_item->>'name'))>200 or jsonb_typeof(v_item->'ingredient_text') <> 'string' or btrim(v_item->>'ingredient_text')='' or char_length(v_item->>'ingredient_text')>500 then raise exception 'invalid kitchen shopping item payload'; end if;
    v_quantity := case when v_item ? 'quantity' and jsonb_typeof(v_item->'quantity') <> 'null' then (v_item->>'quantity')::numeric else null end;
    v_unit := case lower(btrim(coalesce(v_item->>'unit',''))) when '' then null when '개' then 'ea' else lower(btrim(v_item->>'unit')) end;
    if (v_quantity is null) <> (v_unit is null) or v_quantity is not null and (v_quantity <= 0 or v_quantity <> round(v_quantity,6)) or v_unit is not null and not (v_unit = any(v_supported_units)) then raise exception 'invalid kitchen shopping item quantity or unit'; end if;
  end loop;
  select lower(btrim(element.value->>'name')) into v_normalized_name from jsonb_array_elements(p_items) as element(value) group by lower(btrim(element.value->>'name')) having count(*)>1 limit 1;
  if v_normalized_name is not null then raise exception 'duplicate canonical ingredient name is not allowed'; end if;
  insert into public.kitchen_shopping_lists(owner_id,source_recipe_id,title,status,create_idempotency_key) values(v_owner_id,p_source_recipe_id,'장보기 목록','active',p_idempotency_key) returning id into v_list_id;
  perform set_config('app.kitchen_create_rpc','1',true);
  insert into public.kitchen_shopping_items(list_id,owner_id,name,normalized_name,ingredient_text,quantity,unit,is_checked,status,review_status,reviewed_at,revision)
  select v_list_id,v_owner_id,btrim(element.value->>'name'),lower(btrim(element.value->>'name')),element.value->>'ingredient_text',case when element.value ? 'quantity' and jsonb_typeof(element.value->'quantity')<>'null' then (element.value->>'quantity')::numeric else null end,case lower(btrim(coalesce(element.value->>'unit',''))) when '' then null when '개' then 'ea' else lower(btrim(element.value->>'unit')) end,false,'pending','confirmed',transaction_timestamp(),0 from jsonb_array_elements(p_items) as element(value);
  v_result:=jsonb_build_object('list_id',v_list_id,'status','active','completed_at',null,'purchased_count',0,'skipped_count',0,'unavailable_count',0,'inventory_change_count',0);
  insert into public.kitchen_shopping_idempotency(owner_id,operation,idempotency_key,list_id,result) values(v_owner_id,'create',p_idempotency_key,v_list_id,v_result);
  return query select v_list_id,'active',true,false,null::timestamptz,0,0,0,0,p_idempotency_key;
end;
$$;

revoke all on function public.create_kitchen_shopping_list(text,jsonb,uuid) from public, anon;
grant execute on function public.create_kitchen_shopping_list(text,jsonb,uuid) to authenticated;

-- Quantity precision only; payment, idempotency and owner checks remain.
create or replace function public.record_shopping_purchase(p_request_key uuid, p_payload jsonb)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, pg_temp as $$
declare
  v_owner uuid := auth.uid();
  v_existing public.shopping_purchase_records%rowtype;
  v_item public.kitchen_shopping_items%rowtype;
  v_entry jsonb;
  v_items jsonb;
  v_list record;
  v_id uuid;
  v_revision bigint;
  v_quantity numeric;
  v_sum numeric := 0;
  v_amount numeric;
  v_name text;
  v_unit text;
  v_currency text;
  v_count integer;
  v_supported constant text[] := array['g','kg','oz','lb','ml','l','tsp','tbsp','cup','fl_oz',
    'pint','quart','gallon','ea','piece','slice','clove','stalk','head','dozen','pack','bag','bottle',
    'jar','can','carton','box','case','bundle','bunch','net','container','sachet','pouch','tube','tray','roll'];
begin
  if v_owner is null then raise exception 'SHOPPING_AUTH_REQUIRED'; end if;
  if p_request_key is null or p_payload is null or jsonb_typeof(p_payload) <> 'object'
    or octet_length(p_payload::text) > 65536 then raise exception 'SHOPPING_INVALID'; end if;
  perform pg_advisory_xact_lock(hashtextextended('shopping-purchase:' || v_owner::text || ':' || p_request_key::text, 0));
  select * into v_existing from public.shopping_purchase_records r
    where r.owner_id = v_owner and r.request_key = p_request_key;
  if found then
    if v_existing.request_payload <> p_payload then raise exception 'SHOPPING_REQUEST_CONFLICT'; end if;
    return v_existing.id;
  end if;
  v_items := p_payload->'items';
  if jsonb_typeof(v_items) is distinct from 'array' then raise exception 'SHOPPING_INVALID'; end if;
  v_count := jsonb_array_length(v_items);
  v_name := btrim(p_payload->>'name');
  v_unit := p_payload->>'unit';
  v_currency := p_payload->>'currency';
  if v_count not between 1 and 100 or v_name is null or char_length(v_name) not between 1 and 250
    or v_unit is null or v_unit <> all(v_supported) or v_currency is null or v_currency not in ('KRW','USD')
    or jsonb_typeof(p_payload->'quantity') is distinct from 'number'
    or jsonb_typeof(p_payload->'product_name') is distinct from 'string'
    or char_length(p_payload->>'product_name') > 250 then raise exception 'SHOPPING_INVALID'; end if;
  v_quantity := (p_payload->>'quantity')::numeric;
  if v_quantity < 0 or v_quantity > 1e9 or v_quantity <> round(v_quantity, 6) then raise exception 'SHOPPING_INVALID'; end if;
  if p_payload->'paid_amount' is not null and p_payload->'paid_amount' <> 'null'::jsonb then
    if jsonb_typeof(p_payload->'paid_amount') <> 'number' then raise exception 'SHOPPING_INVALID'; end if;
    v_amount := (p_payload->>'paid_amount')::numeric;
    if v_amount < 0 or v_amount > 1e12 or v_quantity = 0 then raise exception 'SHOPPING_INVALID'; end if;
  end if;
  if (select count(distinct e->>'id') from jsonb_array_elements(v_items) e) <> v_count then
    raise exception 'SHOPPING_DUPLICATE_ITEMS';
  end if;
  -- Lock parent lists before items, in stable order, like the completion RPC.
  for v_list in select distinct l.id, l.status from public.kitchen_shopping_lists l
      join public.kitchen_shopping_items i on i.list_id = l.id and i.owner_id = v_owner
      where l.owner_id = v_owner and i.id in (select (e->>'id')::uuid from jsonb_array_elements(v_items) e)
      order by l.id loop
    perform 1 from public.kitchen_shopping_lists l where l.id = v_list.id for update;
    if (select l.status from public.kitchen_shopping_lists l where l.id = v_list.id) <> 'active' then
      raise exception 'SHOPPING_STALE';
    end if;
  end loop;
  for v_entry in select e from jsonb_array_elements(v_items) e order by e->>'id' loop
    if jsonb_typeof(v_entry->'revision') is distinct from 'number'
      or jsonb_typeof(v_entry->'quantity') is distinct from 'number' then raise exception 'SHOPPING_INVALID'; end if;
    select * into v_item from public.kitchen_shopping_items i
      where i.id = (v_entry->>'id')::uuid and i.owner_id = v_owner for update;
    if not found then raise exception 'SHOPPING_NOT_FOUND'; end if;
    if v_item.status <> 'pending' or v_item.revision <> (v_entry->>'revision')::bigint
      or lower(btrim(v_item.name)) <> lower(v_name) then raise exception 'SHOPPING_STALE'; end if;
    if (v_entry->>'quantity')::numeric < 0 or (v_entry->>'quantity')::numeric > 1e9
      or (v_entry->>'quantity')::numeric <> round((v_entry->>'quantity')::numeric, 6) then
      raise exception 'SHOPPING_INVALID';
    end if;
    v_sum := v_sum + (v_entry->>'quantity')::numeric;
  end loop;
  if v_sum <> v_quantity then raise exception 'SHOPPING_ALLOCATION_MISMATCH'; end if;
  for v_entry in select e from jsonb_array_elements(v_items) e order by e->>'id' loop
    if (v_entry->>'quantity')::numeric > 0 then
      select r.revision into v_revision from public.review_kitchen_shopping_item(
        (v_entry->>'id')::uuid, v_name, (v_entry->>'quantity')::numeric,
        v_unit, (v_entry->>'revision')::bigint) r;
      perform public.set_kitchen_shopping_item_status((v_entry->>'id')::uuid, 'purchased', v_revision);
    else
      perform public.set_kitchen_shopping_item_status((v_entry->>'id')::uuid, 'skipped', (v_entry->>'revision')::bigint);
    end if;
  end loop;
  insert into public.shopping_purchase_records(owner_id,request_key,request_payload,ingredient_name,
    quantity,unit,paid_amount,currency,product_name)
    values(v_owner,p_request_key,p_payload,v_name,v_quantity,v_unit,v_amount,v_currency,p_payload->>'product_name')
    returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.record_shopping_purchase(uuid,jsonb) from public, anon;
grant execute on function public.record_shopping_purchase(uuid,jsonb) to authenticated;
