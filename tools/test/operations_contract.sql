\set ON_ERROR_STOP on
begin;
insert into auth.users(id) values('11111111-1111-4111-8111-111111111111'),('22222222-2222-4222-8222-222222222222');
insert into public.profiles values('11111111-1111-4111-8111-111111111111','admin'),('22222222-2222-4222-8222-222222222222','user');

set local role anon;
do $$ begin
  begin perform public.admin_get_ops_overview(7); raise exception 'ANON_READ_ALLOWED';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
do $$ begin
  begin perform public.admin_get_ops_overview(7); raise exception 'USER_READ_ALLOWED';
  exception when others then if sqlerrm <> 'ADMIN_REQUIRED' then raise; end if; end;
  begin perform public.admin_set_ops_monthly_costs(current_date,0,0,700); raise exception 'USER_WRITE_ALLOWED';
  exception when others then if sqlerrm <> 'ADMIN_REQUIRED' then raise; end if; end;
  begin perform count(*) from public.ops_events; raise exception 'RAW_TABLE_READ_ALLOWED';
  exception when insufficient_privilege then null; end;
  begin perform public.record_app_operational_event('secret-content','unknown',false); raise exception 'ARBITRARY_EVENT_ALLOWED';
  exception when others then if sqlerrm <> 'INVALID_EVENT' then raise; end if; end;
  for i in 1..20 loop
    if not public.record_app_operational_event('flutter','unknown',false) then raise exception 'EARLY_LIMIT'; end if;
  end loop;
  if public.record_app_operational_event('flutter','unknown',false) then raise exception 'RATE_LIMIT_FAILED'; end if;
end $$;
reset role;

insert into public.ops_events(kind,source,outcome,code,http_status,duration_ms) values
 ('request','ai_youtube_recipe_assistant','succeeded','ok',200,1000),
 ('request','ai_youtube_recipe_assistant','failed','incomplete_draft',422,3000),
 ('request','ai_youtube_recipe_assistant','rejected','quota',429,10),
 ('request','recipe_api','failed','http_error',500,100);
insert into public.ops_events(kind,source,outcome,code,created_at) values
 ('request','ai_recipe_assistant','failed','timeout',now()-interval '100 days');
insert into public.ai_usage_reservations(user_id,status,request_tokens,response_tokens,created_at,completed_at) values
 ('11111111-1111-4111-8111-111111111111','succeeded',100,25,now(),now()),
 ('11111111-1111-4111-8111-111111111111','failed',80,40,now(),now()),
 ('11111111-1111-4111-8111-111111111111','reserved',0,0,now()-interval '20 minutes',null);

set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
do $$ declare v jsonb; m date := date_trunc('month',now() at time zone 'UTC')::date;
begin
  v := public.admin_get_ops_overview(7);
  if v->'costs' <> 'null'::jsonb then raise exception 'UNKNOWN_COST_NOT_NULL'; end if;
  if (v#>>'{requests,ai_attempts}')::integer <> 2 or (v#>>'{requests,ai_successes}')::integer <> 1
    or (v#>>'{requests,rejected}')::integer <> 1 then raise exception 'AI_DENOMINATOR_WRONG'; end if;
  if (v#>>'{usage,input_tokens}')::integer <> 180 or (v#>>'{usage,output_tokens}')::integer <> 65
    or (v#>>'{usage,unknown_usage}')::integer <> 1 then raise exception 'FAILED_COST_USAGE_LOST'; end if;
  perform public.admin_set_ops_monthly_costs(m,100,null,700);
  v:=public.admin_get_ops_overview(7);
  if v#>'{costs,other_usd}' <> 'null'::jsonb then raise exception 'PARTIAL_COST_NOT_NULL'; end if;
  perform public.admin_set_ops_monthly_costs(m,100,0,700);
  v:=public.admin_get_ops_overview(7);
  if (v#>>'{costs,other_usd}')::numeric <> 0 then raise exception 'REAL_ZERO_LOST'; end if;
  if v->'costs' ? 'updated_by' then raise exception 'ACTOR_EXPOSED'; end if;
  begin perform public.admin_set_ops_monthly_costs(m,-1,0,700); raise exception 'NEGATIVE_COST_ALLOWED';
  exception when others then if sqlerrm <> 'INVALID_COST' then raise; end if; end;
  begin perform public.admin_set_ops_monthly_costs(m,0,0,'NaN'::numeric); raise exception 'NAN_ALLOWED';
  exception when others then if sqlerrm <> 'INVALID_COST' then raise; end if; end;
  begin perform public.admin_get_ops_overview(365); raise exception 'INVALID_WINDOW_ALLOWED';
  exception when others then if sqlerrm <> 'INVALID_RANGE' then raise; end if; end;
end $$;
reset role;
do $$ begin if (select count(*) from public.ops_cost_audit) <> 2 then raise exception 'COST_AUDIT_FAILED'; end if; end $$;

set local role service_role;
select set_config('request.jwt.claim.role','service_role',true);
do $$ begin if public.purge_ops_events() <> 1 then raise exception 'RETENTION_FAILED'; end if; end $$;
reset role;
delete from auth.users where id='22222222-2222-4222-8222-222222222222';
do $$ begin
  if exists(select 1 from public.ops_events where kind='client') then raise exception 'ACCOUNT_CLEANUP_FAILED'; end if;
end $$;
rollback;
