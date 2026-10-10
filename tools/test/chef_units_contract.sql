reset role;
update public.member_entitlements set valid_until=now()+interval '1 day' where user_id='59a00000-0000-4000-8000-000000000001';
insert into public.recipes_creator(id,author_id,title) values('59a00000-0000-4000-8000-000000000011','59a00000-0000-4000-8000-000000000001','Unit contract');
do $$
declare d jsonb := '{"schema":2,"unitFormat":1,"title":"Tofu","steps":"Cook","notes":"","currency":"KRW","baseServings":2,"targetServings":4,"extraCost":0,"legacyExtraCost":0,"costItems":[],"markupPercent":50,"inputWeight":null,"outputWeight":null,"ingredients":[{"id":"i","name":"Tofu","quantity":300,"unit":"g","purchaseQuantity":2,"purchaseUnit":"pack","purchasePrice":6000,"yieldPercent":75,"purchaseUnitInUsageUnits":400}]}';
 bad jsonb;
begin
 if not public.chef_document_valid(d) then raise exception 'UNIT_DOCUMENT_REJECTED'; end if;
 if public.chef_cost_per_serving(d)<>1500 then raise exception 'MANUAL_CONVERSION_COST'; end if;
 bad:=jsonb_set(d,'{ingredients,0,purchaseUnitInUsageUnits}','null');
 if public.chef_cost_per_serving(bad) is not null then raise exception 'UNKNOWN_CONVERSION_GUESSED'; end if;
 bad:=jsonb_set(d,'{ingredients,0,purchaseUnitInUsageUnits}','0');
 if public.chef_document_valid(bad) then raise exception 'ZERO_CONVERSION_ACCEPTED'; end if;
 bad:=jsonb_set(jsonb_set(d,'{ingredients,0,unit}','"custom:국자"'),'{ingredients,0,purchaseUnit}','"custom:국자"');
 if not public.chef_document_valid(bad) then raise exception 'CUSTOM_REJECTED'; end if;
 if public.chef_cost_per_serving(bad)<>600000 then raise exception 'SAME_UNIT_CONVERSION_WRONG'; end if;
 if public.chef_unit_valid('custom:') or public.chef_unit_valid('custom: ') or public.chef_unit_valid('custom:'||repeat('x',21)) or public.chef_unit_valid(E'custom:a\nb') then raise exception 'INVALID_CUSTOM_ACCEPTED'; end if;
 if public.chef_document_valid(d-'unitFormat') then raise exception 'MISSING_UNIT_FORMAT'; end if;
 perform set_config('role','authenticated',true);
 perform public.save_chef_workspace('59a00000-0000-4000-8000-000000000011',d,0,'Pack cost','');
 perform public.record_chef_sale('59a00000-0000-4000-8000-000000000011',1,current_date,2,'unit-sale');
 if not exists(select 1 from public.chef_sales where request_key='unit-sale' and unit_cost=1500 and unit_price=2250) then raise exception 'SALES_CONVERSION_MISMATCH'; end if;
 if (select document#>>'{ingredients,0,purchaseUnitInUsageUnits}' from public.get_chef_versions('59a00000-0000-4000-8000-000000000011'))<>'400' then raise exception 'VERSION_CONVERSION_LOST'; end if;
 begin
  perform public.save_chef_workspace('59a00000-0000-4000-8000-000000000011',d-'unitFormat',1);
  raise exception 'OLD_APP_OVERWRITE_ALLOWED';
 exception when raise_exception then if sqlerrm<>'CHEF_UPGRADE_REQUIRED' then raise; end if; end;
 perform set_config('role','postgres',true);
 if has_function_privilege('authenticated','public.save_chef_workspace_pre_units(uuid,jsonb,bigint,text,text)','execute') then raise exception 'UNIT_GUARD_BYPASS'; end if;
end;$$;
select 'CHEF_UNITS_CONTRACT_PASSED' as result;
