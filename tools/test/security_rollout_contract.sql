
insert into auth.users(id,email) values('59a00000-0000-4000-8000-000000000001','paid-audit@example.invalid');
insert into public.profiles(id,role) values('59a00000-0000-4000-8000-000000000001','admin') on conflict(id) do update set role='admin';
insert into public.recipes_creator(id,author_id,title) values('59a00000-0000-4000-8000-000000000010','59a00000-0000-4000-8000-000000000001','Security test');
select set_config('request.jwt.claim.sub','59a00000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"59a00000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1"}',true);
set local role authenticated;
do $$ declare d jsonb:='{"schema":2,"title":"Food","steps":"Cook","notes":"","currency":"KRW","baseServings":2,"targetServings":4,"extraCost":0,"legacyExtraCost":0,"costItems":[],"markupPercent":0,"inputWeight":null,"outputWeight":null,"ingredients":[{"id":"one","name":"Food","quantity":100,"unit":"g","purchaseQuantity":null,"purchaseUnit":"g","purchasePrice":null,"yieldPercent":100}]}';begin
 if public.has_chef_paid_access() then raise exception 'FREE_ENTITLED';end if;
 perform public.save_chef_workspace('59a00000-0000-4000-8000-000000000010',d,0,'Free version','');
 if exists(select 1 from public.chef_workspaces) then raise exception 'RAW_FREE_LEAK';end if;
 if (select count(*) from public.get_chef_workspace('59a00000-0000-4000-8000-000000000010'))<>1 then raise exception 'FREE_READ_MISSING';end if;
 begin perform public.save_chef_workspace('59a00000-0000-4000-8000-000000000010',jsonb_set(d,'{ingredients,0,purchasePrice}','100'),1);raise exception 'FREE_COST_WRITE';
 exception when raise_exception then if sqlerrm<>'CHEF_PAID_REQUIRED' then raise;end if;end;
 begin perform public.record_chef_sale('59a00000-0000-4000-8000-000000000010',1,current_date,1,'one');raise exception 'FREE_SALE';
 exception when raise_exception then if sqlerrm<>'CHEF_PAID_REQUIRED' then raise;end if;end;
 begin perform public.admin_list_memberships();raise exception 'AAL1_ADMIN';
 exception when raise_exception then if sqlerrm<>'ADMIN_MFA_REQUIRED' then raise;end if;end;
end;$$;
reset role;
insert into public.member_entitlements(user_id,plan_code,status,source,started_at,valid_until) values('59a00000-0000-4000-8000-000000000001','paid_monthly','active','admin',now(),now()+interval '1 day');
set local role authenticated;
do $$ declare d jsonb;begin
 if not public.has_chef_paid_access() then raise exception 'PAID_DENIED';end if;
 select document into d from public.get_chef_workspace('59a00000-0000-4000-8000-000000000010');
 d:=jsonb_set(jsonb_set(d,'{ingredients,0,purchasePrice}','120'),'{ingredients,0,purchaseQuantity}','100');
 perform public.save_chef_workspace('59a00000-0000-4000-8000-000000000010',d,1,'Paid version','');
 perform public.record_chef_sale('59a00000-0000-4000-8000-000000000010',2,current_date,1,'paid-sale');
end;$$;
reset role;
update public.member_entitlements set valid_until=now()-interval '1 second' where user_id='59a00000-0000-4000-8000-000000000001';
set local role authenticated;
do $$ declare d jsonb; n integer;begin
 if exists(select 1 from public.chef_sales) then raise exception 'EXPIRED_SALES_LEAK';end if;
 if exists(select 1 from public.chef_recipe_versions) then raise exception 'EXPIRED_VERSION_LEAK';end if;
 if exists(select 1 from public.get_chef_versions('59a00000-0000-4000-8000-000000000010') where document#>>'{ingredients,0,purchasePrice}' is not null) then raise exception 'SANITIZED_VERSION_LEAK';end if;
 update public.chef_sales set quantity=99 where request_key='paid-sale';get diagnostics n=row_count;if n<>0 then raise exception 'EXPIRED_SALE_EDIT';end if;
 delete from public.chef_sales where request_key='paid-sale';get diagnostics n=row_count;if n<>0 then raise exception 'EXPIRED_SALE_DELETE';end if;
 select document into d from public.get_chef_workspace('59a00000-0000-4000-8000-000000000010');
 perform public.save_chef_workspace('59a00000-0000-4000-8000-000000000010',jsonb_set(d,'{targetServings}','8'),2,'Free edit','');
end;$$;
reset role;
do $$ begin
 if (select document#>>'{ingredients,0,purchasePrice}' from public.chef_workspaces where recipe_id='59a00000-0000-4000-8000-000000000010')<>'120' then raise exception 'STORED_COST_ERASED';end if;
 if has_function_privilege('authenticated','public.save_chef_workspace_internal(uuid,jsonb,bigint,text,text)','execute') then raise exception 'INTERNAL_BYPASS';end if;
 if exists(select 1 from storage.buckets where id='creator-recipe-images' and public) then raise exception 'PUBLIC_BUCKET';end if;
end;$$;
select set_config('request.jwt.claims','{"sub":"59a00000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}',true);
set local role authenticated;
select count(*) from public.admin_list_memberships();
reset role;
set local role authenticated;
do $$ begin
 begin perform public.chef_sales_totals(current_date,current_date+1,'KRW');raise exception 'EXPIRED_TOTALS';
 exception when raise_exception then if sqlerrm<>'CHEF_PAID_REQUIRED' then raise;end if;end;
end;$$;
reset role;
select 'ROLLOUT_SECURITY_CONTRACT_PASSED' as result;
