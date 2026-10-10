insert into auth.users(id,email) values
 ('66000000-0000-4000-8000-000000000001','launch-a@example.invalid'),
 ('66000000-0000-4000-8000-000000000002','launch-b@example.invalid');
select set_config('request.jwt.claim.sub','66000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"66000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $$ declare f jsonb; begin
 f:=public.get_my_membership_features();
 if f->>'supplier_limit'<>'3' or f->>'request_monthly_limit'<>'3' or (f->>'can_share_request_pdf')::boolean
 or public.has_chef_paid_access() then raise exception 'FREE_POLICY'; end if;
 if exists(select 1 from jsonb_array_elements(public.get_membership_billing_catalog()) o where (o->>'checkout_enabled')::boolean)
 then raise exception 'CHECKOUT_ENABLED_WITHOUT_PLAY_SETUP'; end if;
 begin perform public.assert_request_pdf_access(); raise exception 'FREE_PDF';
 exception when raise_exception then if sqlerrm<>'PDF_MEMBERSHIP_REQUIRED' then raise; end if; end;
 begin perform public.begin_billing_verification(); raise exception 'CLIENT_BILLING_MUTATION';
 exception when insufficient_privilege then null; end;
end;$$;
insert into public.shopping_suppliers(id,name) select gen_random_uuid(),'store'||n from generate_series(1,3) n;
do $$ begin
 begin insert into public.shopping_suppliers(id,name) values(gen_random_uuid(),'fourth'); raise exception 'FREE_SUPPLIER_OVERFLOW';
 exception when raise_exception then if sqlerrm<>'SUPPLIER_LIMIT' then raise; end if; end;
end;$$;
reset role;
do $$
begin
 if (select price_krw from public.membership_plans where code='plus_monthly')<>9900
    or (select price_krw from public.membership_plans where code='plus_annual')<>99000
    or (select price_krw from public.membership_plans where code='business_monthly')<>19000
    or (select price_krw from public.membership_plans where code='business_annual')<>189000
    or (select proposed_price_krw from public.membership_offer_drafts where code='plus_monthly')<>9900
    or (select proposed_price_krw from public.membership_offer_drafts where code='plus_annual')<>99000
    or (select proposed_price_krw from public.membership_offer_drafts where code='business_monthly')<>19000
    or (select proposed_price_krw from public.membership_offer_drafts where code='business_annual')<>189000
 then raise exception 'CONFIRMED_PRICE_POLICY_NOT_APPLIED'; end if;
end;
$$;
insert into public.member_entitlements(user_id,plan_code,status,source,started_at,valid_until)
 values('66000000-0000-4000-8000-000000000001','plus_monthly','active','admin',now()-interval '1 day',now()+interval '1 day');
do $$ declare plan text; f jsonb; lim integer; begin
 foreach plan in array array['plus_monthly','plus_annual','business_monthly','business_annual'] loop
  update public.member_entitlements set plan_code=plan where user_id='66000000-0000-4000-8000-000000000001';
  f:=public.get_my_membership_features();
  lim:=case when plan like 'plus_%' then 5 else 20 end;
  if (f->>'video_monthly_limit')::integer<>lim or public.has_chef_paid_access()<>(plan like 'business_%')
  or not (f->>'can_share_request_pdf')::boolean then raise exception 'TIER_ACCESS:%',plan; end if;
  if (select monthly_limit from public.get_my_membership())<>(case when plan like 'plus_%' then 50 else 100 end)
  then raise exception 'AI_TIER_LIMIT'; end if;
 end loop;
 update public.member_entitlements set plan_code='paid_monthly' where user_id='66000000-0000-4000-8000-000000000001';
 if (select plan_code from public.get_my_membership())<>'free' or public.has_chef_paid_access() then raise exception 'RETIRED_PLAN_ACCESS'; end if;
 update public.member_entitlements set plan_code='business_monthly',started_at=now()+interval '1 hour' where user_id='66000000-0000-4000-8000-000000000001';
 if (select plan_code from public.get_my_membership())<>'free' or public.has_chef_paid_access() then raise exception 'FUTURE_ACCESS'; end if;
end;$$;
-- Insert-only monthly quota. Updating and deleting saved documents remain possible.
update public.member_entitlements set plan_code='free' where user_id='66000000-0000-4000-8000-000000000001';
insert into public.supplier_purchase_requests(id,owner_id,data)
 select gen_random_uuid(),'66000000-0000-4000-8000-000000000001','{}' from generate_series(1,3);
update public.supplier_purchase_requests set revision=revision+1 where owner_id='66000000-0000-4000-8000-000000000001';
delete from public.supplier_purchase_requests where owner_id='66000000-0000-4000-8000-000000000001';
do $$ begin
 begin insert into public.supplier_purchase_requests(id,owner_id,data) values(gen_random_uuid(),'66000000-0000-4000-8000-000000000001','{}');
 raise exception 'DELETION_RESTORED_QUOTA'; exception when raise_exception then if sqlerrm<>'SUPPLIER_REQUEST_MONTHLY_LIMIT' then raise; end if; end;
end;$$;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
do $$ declare u uuid:='66000000-0000-4000-8000-000000000001'; until_time timestamptz:=now()+interval '1 month'; events integer; applied boolean; begin
 applied:=public.apply_verified_membership(u,repeat('token-a',5),repeat('a',64),null,10,'plus_monthly','recipe_scout_plus','monthly','active',now()-interval '1 day',until_time,true);
 if not applied then raise exception 'PURCHASE_NOT_APPLIED'; end if;
 select count(*) into events from public.membership_events where user_id=u;
 perform public.apply_verified_membership(u,repeat('token-a',5),repeat('a',64),null,11,'plus_monthly','recipe_scout_plus','monthly','active',now()-interval '1 day',until_time,true);
 if (select count(*) from public.membership_events where user_id=u)<>events then raise exception 'DUPLICATE_EVENT'; end if;
 applied:=public.apply_verified_membership(u,repeat('token-a',5),repeat('a',64),null,9,'plus_monthly','recipe_scout_plus','monthly','expired',now()-interval '1 day',now()-interval '1 hour',false);
 if applied or (select plan_code from public.member_entitlements where user_id=u)<>'plus_monthly' then raise exception 'OLD_RESPONSE_APPLIED'; end if;
 perform public.apply_verified_membership(u,repeat('token-b',5),repeat('b',64),repeat('a',64),12,'business_annual','recipe_scout_business','annual','active',now()-interval '1 day',until_time,true);
 applied:=public.apply_verified_membership(u,repeat('token-a',5),repeat('a',64),null,13,'plus_monthly','recipe_scout_plus','monthly','active',now()-interval '1 day',until_time,true);
 if applied or (select plan_code from public.member_entitlements where user_id=u)<>'business_annual' then raise exception 'SUPERSEDED_TOKEN_APPLIED'; end if;
 begin perform public.apply_verified_membership('66000000-0000-4000-8000-000000000002',repeat('token-b',5),repeat('b',64),null,14,'business_annual','recipe_scout_business','annual','active',now()-interval '1 day',until_time,true);
 raise exception 'TOKEN_CLAIM_STOLEN'; exception when raise_exception then if sqlerrm<>'PURCHASE_ACCOUNT_MISMATCH' then raise; end if; end;
 perform public.apply_verified_membership(u,repeat('token-b',5),repeat('b',64),null,15,'business_annual','recipe_scout_business','annual','canceled',now()-interval '1 day',until_time,false);
 if not public.has_chef_paid_access() then raise exception 'CANCELED_VALID_ACCESS'; end if;
 perform public.apply_verified_membership(u,repeat('token-b',5),repeat('b',64),null,16,'business_annual','recipe_scout_business','annual','paused',now()-interval '1 day',until_time,false);
 if public.has_chef_paid_access() then raise exception 'HOLD_ACCESS'; end if;
end;$$;
update public.member_entitlements set plan_code='plus_annual',status='active',started_at=now()-interval '1 day',valid_until=now()+interval '1 month'
 where user_id='66000000-0000-4000-8000-000000000001';
insert into public.ai_usage_reservations(user_id,endpoint,plan_code,status,video_analysis,video_provider_started,created_at)
 select '66000000-0000-4000-8000-000000000001','ai_youtube_recipe_assistant','plus_annual','failed',true,true,now()-interval '1 hour'
 from generate_series(1,5);
do $$ declare r record; begin
 begin perform public.begin_ai_video_usage('66000000-0000-4000-8000-000000000001'); raise exception 'PLUS_VIDEO_LIMIT_BYPASSED';
 exception when raise_exception then if sqlerrm<>'VIDEO_QUOTA_MONTHLY' then raise; end if; end;
 update public.member_entitlements set plan_code='business_annual' where user_id='66000000-0000-4000-8000-000000000001';
 select * into r from public.begin_ai_video_usage('66000000-0000-4000-8000-000000000001');
 if r.plan_code<>'business_annual' then raise exception 'ANNUAL_VIDEO_RESERVATION'; end if;
 update public.member_entitlements set plan_code='free' where user_id='66000000-0000-4000-8000-000000000001';
 begin perform public.begin_ai_video_usage('66000000-0000-4000-8000-000000000001'); raise exception 'FREE_VIDEO_ALLOWED';
 exception when raise_exception then if sqlerrm<>'VIDEO_MEMBERSHIP_REQUIRED' then raise; end if; end;
 if has_function_privilege('authenticated','public.apply_verified_membership(uuid,text,text,text,bigint,text,text,text,text,timestamptz,timestamptz,boolean)','execute')
 or has_table_privilege('authenticated','public.verified_billing_tokens','select')
 or has_table_privilege('authenticated','public.supplier_request_creation_usage','insert')
 then raise exception 'BILLING_SERVICE_BOUNDARY'; end if;
end;$$;
select 'LAUNCH_BILLING_CONTRACT_PASSED' as result;
