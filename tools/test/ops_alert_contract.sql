\set ON_ERROR_STOP on
select set_config('request.jwt.claims','{"role":"service_role"}',true);
insert into auth.users(id,email) values
 ('a1400000-0000-4000-8000-000000000001','ops-admin@example.invalid'),
 ('a1400000-0000-4000-8000-000000000002','ops-member@example.invalid');
insert into public.profiles(id,role) values
 ('a1400000-0000-4000-8000-000000000001','admin'),
 ('a1400000-0000-4000-8000-000000000002','user') on conflict(id) do update set role=excluded.role;
insert into auth.sessions(id,user_id) values('a1400000-0000-4000-8000-000000000010','a1400000-0000-4000-8000-000000000001');
select set_config('request.jwt.claim.sub','a1400000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"a1400000-0000-4000-8000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
  begin perform public.admin_ops_inbox(); raise exception 'MEMBER_READ_ALLOWED';
  exception when others then if sqlerrm<>'ADMIN_REQUIRED' then raise; end if; end;
  begin perform public.admin_register_ops_device(repeat('x',30),'ko'); raise exception 'MEMBER_PUSH_ALLOWED';
  exception when others then if sqlerrm<>'ADMIN_REQUIRED' then raise; end if; end;
  if has_table_privilege('authenticated','public.ops_admin_devices','SELECT') then raise exception 'DEVICE_TOKEN_LEAK'; end if;
  if has_function_privilege('authenticated','public.evaluate_ops_alerts()','EXECUTE') then raise exception 'MEMBER_EVALUATION'; end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub','a1400000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"a1400000-0000-4000-8000-000000000001","role":"authenticated","session_id":"a1400000-0000-4000-8000-000000000010"}',true);
set local role authenticated;
select public.admin_register_ops_device(repeat('x',30),'ko');
select public.admin_set_ops_database_budget(8589934592);
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
do $$ declare n bigint; payload jsonb; job jsonb; begin
  perform public.ops_transition('test_capacity','warning','{"percent":71}');
  select count(*) into n from public.ops_alert_events where code='test_capacity';
  perform public.ops_transition('test_capacity','warning','{"percent":72}');
  if (select count(*) from public.ops_alert_events where code='test_capacity')<>n then raise exception 'DUPLICATE_ALERT'; end if;
  perform public.ops_transition('test_capacity',null,'{}');
  if (select severity from public.ops_alert_state where code='test_capacity')<>'warning' then raise exception 'UNKNOWN_RECOVERY'; end if;
  perform public.ops_transition('test_capacity','critical','{"percent":91}');
  perform public.ops_transition('test_capacity','ok','{"percent":50}');
  if (select count(*) from public.ops_alert_events where code='test_capacity')<>3 then raise exception 'TRANSITIONS'; end if;
  payload := public.claim_ops_push();
  if jsonb_array_length(payload)<>3 then raise exception 'DELIVERY_COUNT'; end if;
  if jsonb_array_length(public.claim_ops_push())<>0 then raise exception 'DOUBLE_CLAIM'; end if;
  job := payload->0;
  perform public.finish_ops_push((job->>'id')::bigint,gen_random_uuid(),'sent');
  if (select sent_at from public.ops_alert_deliveries where id=(job->>'id')::bigint) is not null then raise exception 'WRONG_LEASE'; end if;
  perform public.finish_ops_push((job->>'id')::bigint,(job->>'lease')::uuid,'sent');
  if (select sent_at from public.ops_alert_deliveries where id=(job->>'id')::bigint) is null then raise exception 'NOT_FINISHED'; end if;
  perform public.evaluate_ops_alerts();
  if (select last_checked_at from public.ops_monitor_settings) is null then raise exception 'MISSING_HEARTBEAT'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"a1400000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $$ declare inbox jsonb; item bigint; begin
  inbox:=public.admin_ops_inbox(); item:=(inbox->'events'->0->>'id')::bigint;
  if inbox::text like '%xxxxxxxxxx%' then raise exception 'INBOX_TOKEN_LEAK'; end if;
  perform public.admin_read_ops_alert(item);
  if not (public.admin_ops_inbox()->'events'->0->>'is_read')::boolean then raise exception 'READ_NOT_SAVED'; end if;
end $$;
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
update public.profiles set role='user' where id='a1400000-0000-4000-8000-000000000001';
update public.ops_alert_deliveries set next_attempt_at=now()-interval '1 minute' where sent_at is null;
do $$ begin
  if jsonb_array_length(public.claim_ops_push())<>0 then raise exception 'REVOKED_ADMIN_PUSH'; end if;
end $$;
delete from auth.sessions where id='a1400000-0000-4000-8000-000000000010';
do $$ begin
  if exists(select 1 from public.ops_admin_devices where user_id='a1400000-0000-4000-8000-000000000001') then raise exception 'LOGOUT_DEVICE_SURVIVED'; end if;
end $$;
-- Exercise actual evaluator thresholds, minimum sample and hysteresis.
delete from public.ai_usage_reservations;
insert into public.ai_usage_reservations(user_id,endpoint,plan_code,status,model)
  select 'a1400000-0000-4000-8000-000000000002','ai_youtube_recipe_assistant','free','failed','gpt-4o-mini' from generate_series(1,19);
do $$ begin
  perform public.evaluate_ops_alerts();
  if exists(select 1 from public.ops_alert_state where code='ai_success') then raise exception 'SMALL_SAMPLE_ALERT'; end if;
end $$;
insert into public.ai_usage_reservations(user_id,endpoint,plan_code,status,model)
  values('a1400000-0000-4000-8000-000000000002','ai_youtube_recipe_assistant','free','failed','gpt-4o-mini');
do $$ begin
  perform public.evaluate_ops_alerts();
  if (select severity from public.ops_alert_state where code='ai_success')<>'critical' then raise exception 'CRITICAL_NOT_DETECTED'; end if;
end $$;
update public.ai_usage_reservations set status='succeeded';
do $$ begin
  perform public.evaluate_ops_alerts();
  if (select severity from public.ops_alert_state where code='ai_success')<>'ok' then raise exception 'RECOVERY_NOT_DETECTED'; end if;
  if (select severity from public.ops_alert_state where code='cost_data')<>'warning' then raise exception 'MISSING_COST_HEALTHY'; end if;
end $$;
-- Match the production PostgREST safety extension for singleton settings updates.
reset role;
load 'safeupdate';
set local role service_role;
select public.evaluate_ops_alerts();
select public.record_ops_dispatch_status(false);
reset role;
update public.profiles set role='admin' where id='a1400000-0000-4000-8000-000000000001';
select set_config('request.jwt.claim.sub','a1400000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"a1400000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
select public.admin_set_ops_database_budget(17179869184);
reset role;
do $$ begin
  if not exists(select 1 from public.ops_monitor_settings where singleton=true
    and database_budget_bytes=17179869184 and last_checked_at is not null
    and last_dispatch_at is not null and last_dispatch_ok=false) then
    raise exception 'SAFEUPDATE_SETTINGS_FAILED'; end if;
end $$;
select 'OPS_ALERT_CONTRACT_PASSED' as result;
