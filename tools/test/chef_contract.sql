\set ON_ERROR_STOP on
-- Appended to migration 0037 within a local transaction by run_chef_contract.ps1.
do $$ begin
  if exists(select 1 from auth.users where id in
    ('c7ef0000-0000-4000-8000-000000000001','c7ef0000-0000-4000-8000-000000000002')) then
    raise exception 'FIXTURE_IDS_ALREADY_PRESENT'; end if;
end $$;
insert into auth.users(id,email) values
 ('c7ef0000-0000-4000-8000-000000000001','chef-test-one@example.invalid'),
 ('c7ef0000-0000-4000-8000-000000000002','chef-test-two@example.invalid');
insert into public.profiles(id,role) values
 ('c7ef0000-0000-4000-8000-000000000001','creator'),
 ('c7ef0000-0000-4000-8000-000000000002','creator')
 on conflict(id) do nothing;
insert into public.recipes_creator(id,author_id,title) values
 ('c7ef0000-0000-4000-8000-000000000010','c7ef0000-0000-4000-8000-000000000001','Chef contract recipe');
select set_config('request.jwt.claim.sub','c7ef0000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"c7ef0000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $$
declare d jsonb := '{"schema":1,"title":"Carrots","steps":"Trim and cook","notes":"","currency":"KRW",
 "baseServings":4,"targetServings":10,"extraCost":1000,"inputWeight":1000,"outputWeight":750,
 "ingredients":[{"id":"carrots","name":"Carrots","quantity":800,"unit":"g","purchaseQuantity":1,
 "purchaseUnit":"kg","purchasePrice":8000,"yieldPercent":80}]}';
 n bigint; modern jsonb; invalid jsonb; sale_id bigint; totals jsonb;
begin
  n := public.save_chef_workspace('c7ef0000-0000-4000-8000-000000000010',d,0,'Original','First trial');
  if n <> 1 then raise exception 'FIRST_REVISION'; end if;
  n := public.save_chef_workspace('c7ef0000-0000-4000-8000-000000000010',
    jsonb_set(d,'{ingredients,0,purchasePrice}','10000'),1,'New supplier','Price changed');
  if n <> 2 then raise exception 'SECOND_REVISION'; end if;
  if (select document #>> '{ingredients,0,purchasePrice}' from public.chef_recipe_versions
    where recipe_id='c7ef0000-0000-4000-8000-000000000010' and version_number=1) <> '8000' then
    raise exception 'HISTORY_WAS_MUTATED'; end if;
  begin
    perform public.save_chef_workspace('c7ef0000-0000-4000-8000-000000000010',d,1,'Stale','');
    raise exception 'STALE_SAVE_ACCEPTED';
  exception when raise_exception then if sqlerrm <> 'CHEF_REVISION_CONFLICT' then raise; end if; end;
  begin
    perform public.save_chef_workspace('c7ef0000-0000-4000-8000-000000000010',
      jsonb_set(d,'{ingredients,0,yieldPercent}','0'),2,null,'');
    raise exception 'INVALID_YIELD_ACCEPTED';
  exception when raise_exception then if sqlerrm <> 'CHEF_INVALID_DOCUMENT' then raise; end if; end;
  begin
    update public.chef_recipe_versions set label='Changed' where recipe_id='c7ef0000-0000-4000-8000-000000000010';
    raise exception 'VERSION_UPDATE_ALLOWED';
  exception when insufficient_privilege then null; end;
  begin
    delete from public.chef_recipe_versions where recipe_id='c7ef0000-0000-4000-8000-000000000010';
    raise exception 'VERSION_DELETE_ALLOWED';
  exception when insufficient_privilege then null; end;
  n := public.save_chef_workspace('c7ef0000-0000-4000-8000-000000000010',d,2,'Restored','Restore as new version');
  if n <> 3 or (select count(*) from public.chef_recipe_versions) <> 3 then raise exception 'RESTORE_HISTORY'; end if;
  modern := d || '{"schema":2,"legacyExtraCost":1000,"extraCost":1500,
    "costItems":[{"id":"pack","name":"Packaging","amount":500}]}'::jsonb;
  n := public.save_chef_workspace('c7ef0000-0000-4000-8000-000000000010',modern,3,'Item costs','Packaging added');
  if n <> 4 then raise exception 'ITEM_COST_SAVE'; end if;
  begin
    perform public.save_chef_workspace('c7ef0000-0000-4000-8000-000000000010',d,4,null,'');
    raise exception 'OLD_CLIENT_OVERWROTE_ITEMS';
  exception when raise_exception then if sqlerrm <> 'CHEF_UPGRADE_REQUIRED' then raise; end if; end;
  foreach invalid in array array[
    jsonb_set(modern,'{costItems,0,amount}','-1'),
    jsonb_set(modern,'{costItems,0,name}','""'),
    jsonb_set(modern,'{extraCost}','999'),
    jsonb_set(modern,'{markupPercent}','101'),
    jsonb_set(modern,'{costItems}','[{"id":"a","name":"A","amount":250},{"id":"a","name":"B","amount":250}]'),
    modern - 'legacyExtraCost'
  ] loop
    begin
      perform public.save_chef_workspace('c7ef0000-0000-4000-8000-000000000010',invalid,4,null,'');
      raise exception 'INVALID_COST_ACCEPTED';
    exception when raise_exception then if sqlerrm <> 'CHEF_INVALID_DOCUMENT' then raise; end if; end;
  end loop;
  modern := jsonb_set(jsonb_set(modern,'{costItems,0,amount}','800'),'{extraCost}','1800');
  n := public.save_chef_workspace('c7ef0000-0000-4000-8000-000000000010',modern,4,'Updated cost','');
  if n <> 5 or (select document #>> '{costItems,0,amount}' from public.chef_recipe_versions
      where recipe_id='c7ef0000-0000-4000-8000-000000000010' and version_number=4) <> '500' then
    raise exception 'COST_HISTORY_MUTATED'; end if;
  modern := modern || '{"markupPercent":50}'::jsonb;
  n := public.save_chef_workspace('c7ef0000-0000-4000-8000-000000000010',modern,5,null,'');
  sale_id := public.record_chef_sale('c7ef0000-0000-4000-8000-000000000010',6,'2026-09-12',10,'first-sale');
  if public.record_chef_sale('c7ef0000-0000-4000-8000-000000000010',6,'2026-09-12',10,'first-sale') <> sale_id or
    (select count(*) from public.chef_sales) <> 1 then raise exception 'DUPLICATE_SALE'; end if;
  if (select unit_price from public.chef_sales where id=sale_id) <> 3675 or
     (select unit_cost from public.chef_sales where id=sale_id) <> 2450 then raise exception 'SALE_PRICE_CALCULATION'; end if;
  modern := modern || '{"markupPercent":100}'::jsonb;
  n := public.save_chef_workspace('c7ef0000-0000-4000-8000-000000000010',modern,6,null,'');
  begin
    perform public.record_chef_sale('c7ef0000-0000-4000-8000-000000000010',6,'2026-09-13',5,'second-sale');
    raise exception 'STALE_SALE_ACCEPTED';
  exception when raise_exception then if sqlerrm <> 'CHEF_REVISION_CONFLICT' then raise; end if; end;
  perform public.record_chef_sale('c7ef0000-0000-4000-8000-000000000010',7,'2026-09-13',5,'second-sale');
  totals := public.chef_sales_totals('2026-09-12','2026-09-13','KRW');
  if (totals->>'revenue')::numeric <> 36750 or totals->>'quantity' <> '10' or (totals->>'cost')::numeric <> 24500 then
    raise exception 'DAILY_TOTAL'; end if;
  totals := public.chef_sales_totals('2026-09-01','2026-10-01','KRW');
  if (totals->>'revenue')::numeric <> 61250 or (totals->>'cost')::numeric <> 36750 then raise exception 'MONTHLY_TOTAL'; end if;
  if (public.chef_sales_totals('2026-09-01','2026-10-01','USD')->>'revenue')::numeric <> 0 then raise exception 'CURRENCY_MIX'; end if;
  update public.chef_sales set quantity=12 where id=sale_id;
  if (select unit_price from public.chef_sales where id=sale_id) <> 3675 then raise exception 'OLD_PRICE_CHANGED'; end if;
  begin
    update public.chef_sales set unit_price=1 where id=sale_id;
    raise exception 'SALE_PRICE_MUTABLE';
  exception when insufficient_privilege then null; end;
  begin
    update public.chef_sales set quantity=0 where id=sale_id;
    raise exception 'INVALID_SALE_QUANTITY';
  exception when check_violation then null; end;
  modern := jsonb_set(modern,'{ingredients,0,purchasePrice}','null');
  n := public.save_chef_workspace('c7ef0000-0000-4000-8000-000000000010',modern,7,null,'');
  begin
    perform public.record_chef_sale('c7ef0000-0000-4000-8000-000000000010',8,'2026-09-14',1,'unknown-cost');
    raise exception 'UNKNOWN_COST_RECORDED';
  exception when raise_exception then if sqlerrm <> 'CHEF_COST_REQUIRED' then raise; end if; end;
end $$;
reset role;
select set_config('request.jwt.claim.sub','c7ef0000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"c7ef0000-0000-4000-8000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
  if exists(select 1 from public.chef_sales) or
     (public.chef_sales_totals('2026-09-01','2026-10-01','KRW')->>'quantity')::integer <> 0 then
    raise exception 'CROSS_ACCOUNT_SALES'; end if;
  delete from public.chef_sales;
  if exists(select 1 from public.chef_workspaces) or exists(select 1 from public.chef_recipe_versions) then
    raise exception 'CROSS_ACCOUNT_READ'; end if;
  begin
    perform public.save_chef_workspace('c7ef0000-0000-4000-8000-000000000010','{}',3,null,'');
    raise exception 'CROSS_ACCOUNT_WRITE';
  exception when raise_exception then if sqlerrm <> 'CHEF_RECIPE_NOT_OWNED' then raise; end if; end;
end $$;
reset role;
do $$ begin
  if has_function_privilege('anon','public.save_chef_workspace(uuid,jsonb,bigint,text,text)','execute') then
    raise exception 'ANON_ACCESS'; end if;
end $$;
delete from public.recipes_creator where id='c7ef0000-0000-4000-8000-000000000010';
do $$ begin
  if exists(select 1 from public.chef_workspaces) or exists(select 1 from public.chef_recipe_versions) then
    raise exception 'DELETE_CASCADE'; end if;
  if (select count(*) from public.chef_sales where recipe_id is null) <> 2 then
    raise exception 'HISTORICAL_SALES_NOT_PRESERVED'; end if;
end $$;
select 'CHEF_CONTRACT_PASSED' as result;
