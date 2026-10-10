-- Local fixture only; the runner wraps all setup and assertions in ROLLBACK.
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
do $$ declare t text; begin
 foreach t in array array['growth_controls','growth_leads','growth_jobs','growth_send_budget','growth_intake_budget'] loop
  if not (select relrowsecurity from pg_class where oid=('public.'||t)::regclass) or has_table_privilege('anon','public.'||t,'select,insert,update,delete') or has_table_privilege('authenticated','public.'||t,'select,insert,update,delete') then raise exception 'PRIVATE_GROWTH_DATA_EXPOSED'; end if;
 end loop;
 if has_function_privilege('authenticated','public.growth_claim_job()','execute') or has_function_privilege('anon','public.admin_growth_overview()','execute') then raise exception 'RPC_GRANTS'; end if;
 begin perform public.growth_register('chef@example.test',repeat('a',64),'chef','costs','ko',false,'youtube','cost01'); raise exception 'PAUSED_ACCEPTED'; exception when others then if sqlerrm<>'GROWTH_PAUSED' then raise; end if; end;
end;$$;
update public.growth_controls set intake_enabled=true;
select public.growth_register('chef@example.test',repeat('a',64),'chef','costs','ko',false,'youtube','cost01');
select public.growth_register('chef@example.test',repeat('a',64),'owner','video','en',true,'kakao','changed');
select public.growth_register('owner@example.test',repeat('b',64),'owner','purchasing','en',true,'kakao','requests');
do $$ declare a public.growth_leads; b public.growth_leads; begin
 select * into a from public.growth_leads where email_key=repeat('a',64); select * into b from public.growth_leads where email_key=repeat('b',64);
 if (select count(*) from public.growth_leads)<>2 or a.newsletter or a.role_code<>'chef' or a.source<>'youtube' or (select count(*) from public.growth_jobs)<>2 then raise exception 'DUPLICATE_CHANGED_CONSENT'; end if;
 if public.growth_claim_job() is not null then raise exception 'DELIVERY_DEFAULT_ON'; end if;
 if public.growth_confirm(a.id,gen_random_uuid()) then raise exception 'WRONG_VERSION_ACCEPTED'; end if;
 perform public.growth_confirm(a.id,a.token_version); perform public.growth_confirm(a.id,a.token_version); perform public.growth_confirm(b.id,b.token_version);
 if (select count(*) from public.growth_jobs where kind='welcome')<>2 or (select count(*) from public.growth_jobs where kind='tip')<>1 or exists(select 1 from public.growth_jobs where lead_id=a.id and kind='tip') then raise exception 'CONSENT_SEQUENCE_FAILED'; end if;
end;$$;
update public.growth_controls set delivery_enabled=true,daily_send_limit=2;
do $$ declare a jsonb; b jsonb; v uuid; begin
 a:=public.growth_claim_job(); b:=public.growth_claim_job();
 if a is null or b is null or a->>'id'=b->>'id' or public.growth_claim_job() is not null then raise exception 'LEASE_OR_BUDGET_FAILED'; end if;
 if public.growth_finish_job((a->>'id')::uuid,gen_random_uuid(),true,'unknown') then raise exception 'STALE_LEASE_ACCEPTED'; end if;
 if not public.growth_finish_job((a->>'id')::uuid,(a->>'lease_id')::uuid,true,'unknown') then raise exception 'ACK_FAILED'; end if;
 if public.growth_finish_job((a->>'id')::uuid,(a->>'lease_id')::uuid,true,'unknown') then raise exception 'DUPLICATE_ACK'; end if;
 select token_version into v from public.growth_leads where id=(b->>'lead_id')::uuid;
 perform public.growth_withdraw((b->>'lead_id')::uuid,v);
 if public.growth_job_deliverable((b->>'id')::uuid,(b->>'lease_id')::uuid) or exists(select 1 from public.growth_leads where id=(b->>'lead_id')::uuid and email is not null) then raise exception 'WITHDRAWAL_FAILED'; end if;
 perform public.growth_register('withdrawn@example.test',(select email_key from public.growth_leads where id=(b->>'lead_id')::uuid),'chef','costs','ko',true,'direct','');
 if exists(select 1 from public.growth_leads where id=(b->>'lead_id')::uuid and state<>'withdrawn') then raise exception 'WITHDRAWAL_OVERRIDDEN'; end if;
end;$$;
select public.growth_register('expired@example.test',repeat('c',64),'chef','costs','ko',false,'direct','');
update public.growth_leads set created_at=now()-interval '8 days' where email_key=repeat('c',64);
select public.growth_maintain();
do $$ begin if exists(select 1 from public.growth_leads where email_key=repeat('c',64)) then raise exception 'PENDING_RETENTION_FAILED'; end if; end;$$;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"77777777-7777-4777-8777-777777777777"}',true);
do $$ begin
 begin perform public.admin_growth_overview(); raise exception 'NONADMIN_OVERVIEW_ALLOWED'; exception when others then if sqlerrm not in ('ADMIN_REQUIRED','ADMIN_MFA_REQUIRED') then raise; end if; end;
 begin perform public.growth_claim_job(); raise exception 'CLIENT_WORKER_ALLOWED'; exception when others then if sqlerrm<>'SERVICE_ROLE_REQUIRED' then raise; end if; end;
end;$$;
select 'PRELAUNCH_GROWTH_CONTRACT_PASSED' as result;
