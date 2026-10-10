-- Requires 0036. No schedule or external push is enabled by this migration.
create table public.ops_monitor_settings (
  singleton boolean primary key default true check(singleton),
  database_budget_bytes bigint not null default 8589934592 check(database_budget_bytes > 0),
  last_checked_at timestamptz,
  last_dispatch_at timestamptz,
  last_dispatch_ok boolean
);
insert into public.ops_monitor_settings(singleton) values(true);
create table public.ops_alert_state (
  code text primary key,
  severity text not null check(severity in ('ok','warning','critical')),
  last_checked_at timestamptz not null default now(),
  detail jsonb not null default '{}'
);
create table public.ops_alert_events (
  id bigint generated always as identity primary key,
  code text not null,
  severity text not null check(severity in ('warning','critical','recovered')),
  detail jsonb not null,
  created_at timestamptz not null default now()
);
create table public.ops_admin_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null references auth.sessions(id) on delete cascade,
  token text not null unique check(length(token) between 20 and 4096),
  language text not null check(language in ('ko','en')),
  expires_at timestamptz not null default now()+interval '30 days'
);
create index ops_admin_devices_user_idx on public.ops_admin_devices(user_id);
create table public.ops_alert_reads (
  event_id bigint not null references public.ops_alert_events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  primary key(event_id,user_id)
);
create table public.ops_alert_deliveries (
  id bigint generated always as identity primary key,
  event_id bigint not null references public.ops_alert_events(id) on delete cascade,
  device_id uuid not null references public.ops_admin_devices(id) on delete cascade,
  attempts integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  lease uuid,
  sent_at timestamptz,
  last_error text,
  unique(event_id,device_id)
);
create index ops_alert_delivery_pending_idx on public.ops_alert_deliveries(next_attempt_at)
  where sent_at is null and attempts < 5;
alter table public.ops_monitor_settings enable row level security;
alter table public.ops_alert_state enable row level security;
alter table public.ops_alert_events enable row level security;
alter table public.ops_admin_devices enable row level security;
alter table public.ops_alert_reads enable row level security;
alter table public.ops_alert_deliveries enable row level security;
revoke all on public.ops_monitor_settings,public.ops_alert_state,public.ops_alert_events,
  public.ops_admin_devices,public.ops_alert_reads,public.ops_alert_deliveries from public,anon,authenticated;
grant all on public.ops_monitor_settings,public.ops_alert_state,public.ops_alert_events,
  public.ops_admin_devices,public.ops_alert_reads,public.ops_alert_deliveries to service_role;
grant usage,select on sequence public.ops_alert_events_id_seq,public.ops_alert_deliveries_id_seq to service_role;

create function public.admin_register_ops_device(p_token text,p_language text) returns void
language plpgsql security definer set search_path='' as $$
declare sid uuid := (auth.jwt()->>'session_id')::uuid;
begin
  perform public.assert_ops_admin();
  if not exists(select 1 from auth.sessions where id=sid and user_id=auth.uid()
    and (not_after is null or not_after>now())) then raise exception 'SESSION_REQUIRED'; end if;
  if p_token is null or length(p_token) not between 20 and 4096 or
    p_language is null or p_language not in ('ko','en') then raise exception 'INVALID_DEVICE'; end if;
  delete from public.ops_admin_devices where expires_at<now();
  if not exists(select 1 from public.ops_admin_devices where token=p_token)
    and (select count(*) from public.ops_admin_devices where user_id=auth.uid())>=10 then
    raise exception 'DEVICE_LIMIT'; end if;
  insert into public.ops_admin_devices(user_id,session_id,token,language)
  values(auth.uid(),sid,p_token,p_language) on conflict(token) do update
    set user_id=excluded.user_id,session_id=excluded.session_id,language=excluded.language,
      expires_at=now()+interval '30 days';
end;
$$;
create function public.unregister_ops_device(p_token text) returns void
language sql security definer set search_path='' as $$
  delete from public.ops_admin_devices where token=p_token and user_id=auth.uid();
$$;
create function public.admin_read_ops_alert(p_id bigint) returns void
language plpgsql security definer set search_path='' as $$
begin
  perform public.assert_ops_admin();
  insert into public.ops_alert_reads(event_id,user_id)
    select id,auth.uid() from public.ops_alert_events where id=p_id on conflict do nothing;
end;
$$;
create function public.admin_ops_inbox(p_before bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare events jsonb; checked timestamptz;
begin
  perform public.assert_ops_admin();
  select last_checked_at into checked from public.ops_monitor_settings;
  select coalesce(jsonb_agg(to_jsonb(t) order by t.id desc),'[]') into events from (
    select e.*,exists(select 1 from public.ops_alert_reads r where r.event_id=e.id and r.user_id=auth.uid()) as is_read
    from public.ops_alert_events e where p_before is null or e.id<p_before order by e.id desc limit 50
  ) t;
  return jsonb_build_object('events',events,'last_checked_at',checked,
    'last_dispatch_at',(select last_dispatch_at from public.ops_monitor_settings),
    'last_dispatch_ok',(select last_dispatch_ok from public.ops_monitor_settings),
    'database_budget_bytes',(select database_budget_bytes from public.ops_monitor_settings),
    'pending_push',(select count(*) from public.ops_alert_deliveries where sent_at is null and attempts<5),
    'failed_push',(select count(*) from public.ops_alert_deliveries where sent_at is null and attempts>=5));
end;
$$;
create function public.admin_set_ops_database_budget(p_bytes bigint) returns void
language plpgsql security definer set search_path='' as $$
begin
  perform public.assert_ops_admin();
  if p_bytes is null or p_bytes<1073741824 or p_bytes>109951162777600 then raise exception 'INVALID_BUDGET'; end if;
  update public.ops_monitor_settings set database_budget_bytes=p_bytes;
end;
$$;

-- Called only by the evaluator; a stable severity produces no additional event.
create function public.ops_transition(p_code text,p_severity text,p_detail jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare previous text; event bigint;
begin
  if p_severity is null then return; end if; -- missing evidence is not recovery
  select severity into previous from public.ops_alert_state where code=p_code;
  insert into public.ops_alert_state(code,severity,detail) values(p_code,p_severity,p_detail)
  on conflict(code) do update set severity=excluded.severity,detail=excluded.detail,last_checked_at=now();
  if previous is not distinct from p_severity or (previous is null and p_severity='ok') then return; end if;
  insert into public.ops_alert_events(code,severity,detail)
    values(p_code,case when p_severity='ok' then 'recovered' else p_severity end,p_detail) returning id into event;
  insert into public.ops_alert_deliveries(event_id,device_id)
    select event,d.id from public.ops_admin_devices d join public.profiles p on p.id=d.user_id
    join auth.sessions s on s.id=d.session_id and s.user_id=d.user_id
    where p.role='admin' and d.expires_at>now() and (s.not_after is null or s.not_after>now());
end;
$$;

create function public.evaluate_ops_alerts() returns void
language plpgsql security definer set search_path='' as $$
declare total bigint; failures bigint; pct numeric; latency numeric; budget bigint; size bigint;
  costs public.ops_monthly_costs%rowtype; latest timestamptz;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  perform pg_advisory_xact_lock(4040);
  select count(*),count(*) filter(where status='failed') into total,failures
    from public.ai_usage_reservations where created_at>=now()-interval '1 hour' and status in ('succeeded','failed');
  pct := case when total>=20 then 100.0*(total-failures)/total end;
  perform public.ops_transition('ai_success',case when pct is null then null when pct<80 then 'critical' when pct<90 then 'warning' when pct>=93 then 'ok' else null end,
    jsonb_build_object('success_percent',pct,'attempts',total,'window_minutes',60));
  select count(*),count(*) filter(where outcome='failed'),
    percentile_cont(0.95) within group(order by duration_ms) filter(where source in ('ai_recipe_assistant','ai_youtube_recipe_assistant') and outcome<>'rejected')
    into total,failures,latency from public.ops_events where kind='request' and created_at>=now()-interval '1 hour';
  pct := case when total>=20 then 100.0*failures/total end;
  perform public.ops_transition('server_errors',case when pct is null then null when pct>=10 then 'critical' when pct>=5 then 'warning' when pct<3 then 'ok' else null end,
    jsonb_build_object('failure_percent',pct,'requests',total,'window_minutes',60));
  select count(*) into total from public.ops_events where kind='request' and source in ('ai_recipe_assistant','ai_youtube_recipe_assistant') and outcome<>'rejected' and created_at>=now()-interval '1 hour';
  perform public.ops_transition('ai_latency',case when total<20 or latency is null then null when latency>=90000 then 'critical' when latency>=60000 then 'warning' when latency<45000 then 'ok' else null end,
    jsonb_build_object('p95_seconds',latency/1000,'attempts',total));
  select max(created_at) into latest from public.ops_events where kind='request';
  perform public.ops_transition('telemetry_missing',case when latest is null then 'warning'
    when latest<now()-interval '30 minutes' and exists(select 1 from public.ai_usage_reservations where created_at>=now()-interval '30 minutes') then 'warning' else 'ok' end,
    jsonb_build_object('last_event_at',latest));
  select database_budget_bytes into budget from public.ops_monitor_settings;
  size := pg_database_size(current_database()); pct := 100.0*size/budget;
  perform public.ops_transition('database_budget',case when pct>=85 then 'critical' when pct>=70 then 'warning' when pct<65 then 'ok' else null end,
    jsonb_build_object('bytes',size,'budget_bytes',budget,'percent',round(pct,1)));
  select count(*) into total from pg_stat_activity where backend_type='client backend';
  pct := 100.0*total/current_setting('max_connections')::integer;
  perform public.ops_transition('database_connections',case when pct>=85 then 'critical' when pct>=70 then 'warning' when pct<60 then 'ok' else null end,
    jsonb_build_object('connections',total,'percent',round(pct,1)));
  select * into costs from public.ops_monthly_costs where month=date_trunc('month',now() at time zone 'UTC')::date;
  if not found or costs.openai_usd is null or costs.other_usd is null or costs.updated_at<now()-interval '1 day' then
    perform public.ops_transition('cost_data', 'warning',jsonb_build_object('updated_at',costs.updated_at));
  else
    perform public.ops_transition('cost_data','ok',jsonb_build_object('updated_at',costs.updated_at));
    pct := 100.0*(costs.openai_usd+costs.other_usd)/costs.budget_usd;
    perform public.ops_transition('monthly_cost',case when pct>=95 then 'critical' when pct>=70 then 'warning' when pct<65 then 'ok' else null end,
      jsonb_build_object('total_usd',costs.openai_usd+costs.other_usd,'budget_usd',costs.budget_usd,'percent',pct,'updated_at',costs.updated_at));
  end if;
  -- Keep alert history bounded, while preserving the latest state for deduplication.
  delete from public.ops_alert_events where id in (select id from public.ops_alert_events where created_at<now()-interval '90 days' limit 1000);
  delete from public.ops_admin_devices d where expires_at<now() or
    not exists(select 1 from public.profiles p where p.id=d.user_id and p.role='admin');
  update public.ops_alert_deliveries q set attempts=5,last_error='expired' where sent_at is null and attempts<5
    and exists(select 1 from public.ops_alert_events e where e.id=q.event_id and e.created_at<=now()-interval '1 day');
  update public.ops_monitor_settings set last_checked_at=now();
end;
$$;

create function public.claim_ops_push() returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; claim uuid := gen_random_uuid();
begin
  if auth.role() is distinct from 'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  with candidates as (
    select q.id from public.ops_alert_deliveries q join public.ops_admin_devices d on d.id=q.device_id
    join public.profiles p on p.id=d.user_id join auth.sessions s on s.id=d.session_id and s.user_id=d.user_id
    join public.ops_alert_events e on e.id=q.event_id
    where q.sent_at is null and q.attempts<5 and q.next_attempt_at<=now() and p.role='admin'
      and d.expires_at>now() and (s.not_after is null or s.not_after>now()) and e.created_at>now()-interval '1 day'
    order by q.id limit 10 for update of q skip locked
  ), leased as (
    update public.ops_alert_deliveries q set lease=claim,attempts=attempts+1,next_attempt_at=now()+interval '10 minutes'
    from candidates c where q.id=c.id returning q.*
  ) select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'lease',q.lease,'event_id',q.event_id,
    'token',d.token,'language',d.language)),'[]') into result from leased q join public.ops_admin_devices d on d.id=q.device_id;
  return result;
end;
$$;
create function public.finish_ops_push(p_id bigint,p_lease uuid,p_result text) returns void
language plpgsql security definer set search_path='' as $$
declare device uuid;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  if p_result is null or p_result not in ('sent','retry','invalid_token') then raise exception 'INVALID_RESULT'; end if;
  update public.ops_alert_deliveries set sent_at=case when p_result='sent' then now() else null end,
    last_error=case when p_result='sent' then null else p_result end,lease=null
    where id=p_id and lease=p_lease and sent_at is null returning device_id into device;
  if p_result='invalid_token' and device is not null then delete from public.ops_admin_devices where id=device; end if;
end;
$$;
create function public.record_ops_dispatch_status(p_ok boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
  if auth.role() is distinct from 'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  update public.ops_monitor_settings set last_dispatch_at=now(),last_dispatch_ok=coalesce(p_ok,false);
end;
$$;
revoke all on function public.record_ops_dispatch_status(boolean) from public,anon,authenticated;
grant execute on function public.record_ops_dispatch_status(boolean) to service_role;
revoke all on function public.ops_transition(text,text,jsonb),public.evaluate_ops_alerts(),public.claim_ops_push(),public.finish_ops_push(bigint,uuid,text) from public,anon,authenticated;
grant execute on function public.evaluate_ops_alerts(),public.claim_ops_push(),public.finish_ops_push(bigint,uuid,text) to service_role;
revoke all on function public.admin_register_ops_device(text,text),public.unregister_ops_device(text),public.admin_read_ops_alert(bigint),public.admin_ops_inbox(bigint),public.admin_set_ops_database_budget(bigint) from public,anon;
grant execute on function public.admin_register_ops_device(text,text),public.unregister_ops_device(text),public.admin_read_ops_alert(bigint),public.admin_ops_inbox(bigint),public.admin_set_ops_database_budget(bigint) to authenticated;
