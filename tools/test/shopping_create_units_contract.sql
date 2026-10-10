-- Transaction-local fixtures. The runner always rolls back.
insert into auth.users(id,email) values
 ('65000000-0000-4000-8000-000000000001','shopping-create-a@example.invalid'),
 ('65000000-0000-4000-8000-000000000002','shopping-create-b@example.invalid');
insert into public.profiles(id,role) values
 ('65000000-0000-4000-8000-000000000001','user'),
 ('65000000-0000-4000-8000-000000000002','user') on conflict(id) do nothing;
select set_config('request.jwt.claim.sub','65000000-0000-4000-8000-000000000001',true);
set local role authenticated;

do $$
declare
  v_unit text;
  v_units constant text[] := array[
    'g','kg','oz','lb','ml','l','tsp','tbsp','cup','fl_oz','pint','quart','gallon',
    'ea','piece','slice','clove','stalk','head','dozen',
    'pack','bag','bottle','jar','can','carton','box','case','bundle','bunch','net',
    'container','sachet','pouch','tube','tray','roll'];
  v_items jsonb := '[]';
  v_key uuid := gen_random_uuid();
  v_first record;
  v_retry record;
  v_count integer;
  v_precision_item uuid;
  v_purchase_id uuid;
  v_purchase_key uuid := gen_random_uuid();
  v_purchase_payload jsonb;
begin
  foreach v_unit in array v_units loop
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'name','ingredient-' || v_unit, 'ingredient_text','Original 0.5 ' || v_unit,
      'quantity',0.5,'unit',v_unit));
  end loop;
  -- Unknown amounts remain allowed; they must not prevent list creation.
  v_items := v_items || '[{"name":"rice","ingredient_text":"[확인 필요] 밥","quantity":null,"unit":null},
    {"name":"egg","ingredient_text":"달걀 1개","quantity":1,"unit":"개"}]'::jsonb;
  select * into v_first from public.create_kitchen_shopping_list('creator:bibimbap', v_items, v_key);
  if not v_first.created or v_first.replayed then raise exception 'CREATE_RESULT'; end if;
  if (select count(*) from public.kitchen_shopping_items where list_id=v_first.list_id) <> cardinality(v_units)+2 then raise exception 'ITEM_COUNT'; end if;
  if exists(select 1 from public.kitchen_shopping_items where list_id=v_first.list_id
    and name like 'ingredient-%' and (quantity<>0.5 or ingredient_text<>'Original 0.5 '||unit)) then raise exception 'AMOUNT_OR_SOURCE_CHANGED'; end if;
  if not exists(select 1 from public.kitchen_shopping_items where list_id=v_first.list_id and name='egg' and unit='ea') then raise exception 'COUNT_ALIAS'; end if;
  select * into v_retry from public.create_kitchen_shopping_list('creator:bibimbap', v_items, v_key);
  if v_retry.created or not v_retry.replayed or v_first.list_id<>v_retry.list_id then raise exception 'RETRY_DUPLICATED_LIST'; end if;
  raise notice 'PASS: all 37 units, unknown quantities, alias, exact amounts and retry';

  -- Reproduce the reported second case: rice/egg excluded, sauces still selected.
  select * into v_first from public.create_kitchen_shopping_list('creator:bibimbap',
    '[{"name":"soy sauce","ingredient_text":"진간장 1/2 작은술","quantity":0.5,"unit":"tsp"},
      {"name":"sesame oil","ingredient_text":"참기름 1 큰술","quantity":1,"unit":"tbsp"}]',gen_random_uuid());
  if (select count(*) from public.kitchen_shopping_items where list_id=v_first.list_id)<>2 then raise exception 'SELECTED_SAUCES_FAILED'; end if;
  raise notice 'PASS: selected sauces create a list without rice or egg';

  select * into v_retry from public.create_kitchen_shopping_list('creator:conversion',
    '[{"name":"conversion","ingredient_text":"Recipe uses 100g","quantity":0.125,"unit":"kg"}]',gen_random_uuid());
  select id into v_precision_item from public.kitchen_shopping_items where list_id=v_retry.list_id;
  if not exists(select 1 from public.kitchen_shopping_items where id=v_precision_item and quantity=0.125) then raise exception 'CONVERTED_QUANTITY_ROUNDED'; end if;
  v_purchase_payload := jsonb_build_object('name','conversion','quantity',0.125,'unit','kg','currency','KRW','paid_amount',1000,'product_name','Test product',
    'items',jsonb_build_array(jsonb_build_object('id',v_precision_item,'revision',0,'quantity',0.125)));
  v_purchase_id := public.record_shopping_purchase(v_purchase_key,v_purchase_payload);
  if public.record_shopping_purchase(v_purchase_key,v_purchase_payload)<>v_purchase_id then raise exception 'PURCHASE_RETRY_DUPLICATED'; end if;
  if not exists(select 1 from public.shopping_purchase_records where id=v_purchase_id and quantity=0.125 and unit='kg') then raise exception 'PURCHASE_QUANTITY_ROUNDED'; end if;
  raise notice 'PASS: 125 g = 0.125 kg persists exactly through creation, purchase and retry';

  -- Cooking completion is a diary record, never an inventory transaction.
  insert into public.kitchen_ingredients(owner_id,name,normalized_name,quantity,unit)
    values(auth.uid(),'rice','rice',1000,'g');
  insert into public.kitchen_cook_sessions(owner_id,recipe_type,recipe_ref_id,recipe_title,consumed_ingredients)
    values(auth.uid(),'creator','bibimbap','Bibimbap','[{"name":"rice","quantity":120,"unit":"g"}]');
  if not exists(select 1 from public.kitchen_ingredients where name='rice' and quantity=1000 and unit='g') then raise exception 'COOKING_DEDUCTED_STOCK'; end if;
  if (select count(*) from public.kitchen_shopping_items where list_id=v_first.list_id and status='pending')<>2 then raise exception 'COOKING_CHANGED_PURCHASES'; end if;
  if not exists(select 1 from public.shopping_purchase_records where id=v_purchase_id and quantity=0.125 and unit='kg') then raise exception 'COOKING_CHANGED_HISTORY'; end if;
  raise notice 'PASS: cooking records do not deduct inventory or alter shopping records';

  select count(*) into v_count from public.kitchen_shopping_lists;
  begin
    perform public.create_kitchen_shopping_list('creator:too-precise',
      '[{"name":"precision","ingredient_text":"original","quantity":0.0000001,"unit":"kg"}]',gen_random_uuid());
    raise exception 'SILENT_ROUNDING_ACCEPTED';
  exception when raise_exception then
    if sqlerrm <> 'invalid kitchen shopping item quantity or unit' then raise; end if;
  end;
  begin
    perform public.create_kitchen_shopping_list('creator:bad',
      '[{"name":"good","ingredient_text":"good 1g","quantity":1,"unit":"g"},
        {"name":"bad","ingredient_text":"bad 1x","quantity":1,"unit":"unsupported"}]',gen_random_uuid());
    raise exception 'INVALID_ACCEPTED';
  exception when raise_exception then
    if sqlerrm <> 'invalid kitchen shopping item quantity or unit' then raise; end if;
  end;
  begin
    perform public.create_kitchen_shopping_list('creator:bad',
      '[{"name":"bad","ingredient_text":"bad","quantity":null,"unit":"tsp"}]',gen_random_uuid());
    raise exception 'UNPAIRED_ACCEPTED';
  exception when raise_exception then
    if sqlerrm <> 'invalid kitchen shopping item quantity or unit' then raise; end if;
  end;
  begin
    perform public.create_kitchen_shopping_list('creator:bad',
      '[{"name":"bad","ingredient_text":"bad","quantity":1,"unit":"tsp","owner_id":"65000000-0000-4000-8000-000000000002"}]',gen_random_uuid());
    raise exception 'MANAGED_FIELD_ACCEPTED';
  exception when raise_exception then
    if sqlerrm <> 'invalid kitchen shopping item payload' then raise; end if;
  end;
  if (select count(*) from public.kitchen_shopping_lists)<>v_count then raise exception 'PARTIAL_WRITE'; end if;
  raise notice 'PASS: invalid units, quantity pairing and owner injection rejected atomically';
end; $$;

reset role;
select set_config('request.jwt.claim.sub','65000000-0000-4000-8000-000000000002',true);
set local role authenticated;
do $$ begin
  if exists(select 1 from public.kitchen_shopping_lists) or exists(select 1 from public.kitchen_shopping_items) then raise exception 'OTHER_OWNER_VISIBLE'; end if;
  if has_function_privilege('anon','public.create_kitchen_shopping_list(text,jsonb,uuid)','execute') then raise exception 'ANON_EXECUTE'; end if;
  raise notice 'PASS: owner isolation and anonymous access restriction';
end; $$;
reset role;
