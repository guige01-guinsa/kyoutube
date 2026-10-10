-- Local-only fixtures. The harness rolls back the entire transaction.
insert into auth.users(id,email) values
 ('65000000-0000-4000-8000-000000000001','features-a@example.invalid'),
 ('65000000-0000-4000-8000-000000000002','features-b@example.invalid');
select set_config('request.jwt.claim.sub','65000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"65000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $$ declare f jsonb; begin
 f:=public.get_my_membership_features();
 if (f->>'can_manage_costs')::boolean or (f->>'can_manage_sales')::boolean
   or not (f->>'can_share_request_pdf')::boolean or f->>'supplier_limit'<>'200'
   or f->>'request_monthly_limit' is not null or f->>'video_monthly_limit'<>'0'
 then raise exception 'FREE_LEGACY_RIGHTS_CHANGED'; end if;
 if public.has_chef_paid_access() then raise exception 'FREE_FINANCIAL_ACCESS'; end if;
 begin perform public.member_feature_snapshot('65000000-0000-4000-8000-000000000002');
   raise exception 'FOREIGN_SNAPSHOT_EXPOSED'; exception when insufficient_privilege then null; end;
 begin update public.membership_feature_profiles set can_manage_costs=true;
   raise exception 'CLIENT_POLICY_WRITE'; exception when insufficient_privilege then null; end;
 begin perform * from public.membership_offer_drafts;
   raise exception 'DRAFT_OFFERS_EXPOSED'; exception when insufficient_privilege then null; end;
end;$$;
reset role;
insert into public.member_entitlements(user_id,plan_code,status,source,started_at,valid_until)
 values('65000000-0000-4000-8000-000000000001','paid_monthly','active','admin',now()-interval '1 day',now()+interval '1 day');
do $$ declare s text; f jsonb; begin
 foreach s in array array['active','grace_period','canceled'] loop
   update public.member_entitlements set status=s where user_id='65000000-0000-4000-8000-000000000001';
   f:=public.get_my_membership_features();
   if not public.has_chef_paid_access() or f->>'video_monthly_limit'<>'20'
     or not (f->>'can_manage_sales')::boolean then raise exception 'MONTHLY_RIGHTS_LOST:%',s; end if;
 end loop;
 foreach s in array array['pending','paused','expired','revoked','free'] loop
   update public.member_entitlements set status=s where user_id='65000000-0000-4000-8000-000000000001';
   if public.has_chef_paid_access() or public.get_my_membership_features()->>'video_monthly_limit'<>'0'
     then raise exception 'INACTIVE_RIGHTS_GRANTED:%',s; end if;
 end loop;
 update public.member_entitlements set status='active',plan_code='paid_annual'
   where user_id='65000000-0000-4000-8000-000000000001';
 f:=public.get_my_membership_features();
 if not public.has_chef_paid_access() or f->>'video_monthly_limit'<>'0'
   then raise exception 'ANNUAL_LEGACY_RIGHTS_CHANGED'; end if;
 update public.member_entitlements set valid_until=now()-interval '1 second'
   where user_id='65000000-0000-4000-8000-000000000001';
 if public.has_chef_paid_access() then raise exception 'EXPIRED_ACCESS'; end if;
 update public.member_entitlements set valid_until=now()+interval '2 days',started_at=now()+interval '1 day'
   where user_id='65000000-0000-4000-8000-000000000001';
 if public.has_chef_paid_access() then raise exception 'FUTURE_ACCESS'; end if;
 update public.member_entitlements set valid_until=null,started_at=null,plan_code='paid_monthly'
   where user_id='65000000-0000-4000-8000-000000000001';
 if public.has_chef_paid_access() or public.get_my_membership_features()->>'video_monthly_limit'<>'20'
   then raise exception 'UNBOUNDED_LEGACY_RIGHTS_CHANGED'; end if;
 update public.membership_plans set is_active=false where code='paid_monthly';
 if public.has_chef_paid_access() or public.get_my_membership_features()->>'video_monthly_limit'<>'0'
   then raise exception 'INACTIVE_PLAN_GRANTED'; end if;
 update public.membership_plans set is_active=true where code='paid_monthly';
end;$$;
select set_config('request.jwt.claim.sub','65000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"65000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 if public.has_chef_paid_access() or public.get_my_membership_features()->>'video_monthly_limit'<>'0'
 then raise exception 'ACCOUNT_RIGHTS_LEAK'; end if;
end;$$;
reset role;
do $$ begin
 if has_function_privilege('anon','public.get_my_membership_features()','execute')
   or has_function_privilege('authenticated','public.member_feature_snapshot(uuid)','execute')
   then raise exception 'FEATURE_RPC_GRANT'; end if;
 if exists(select 1 from public.membership_feature_profiles where tier_code<>'legacy' and is_active)
   or exists(select 1 from public.membership_plan_feature_profiles where profile_code in ('scout','plus','business'))
   then raise exception 'NEW_POLICY_ACTIVATED'; end if;
 if exists(select 1 from public.membership_offer_drafts where status<>'draft')
   then raise exception 'NEW_OFFER_ACTIVATED'; end if;
 if (select count(*) from public.membership_offer_drafts)<>4 then raise exception 'MISSING_DRAFT_OFFERS'; end if;
end;$$;
select 'MEMBERSHIP_FEATURES_CONTRACT_PASSED' as result;
