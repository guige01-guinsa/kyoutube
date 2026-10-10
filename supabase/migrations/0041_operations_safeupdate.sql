-- Preserve 0040 history; target the singleton explicitly for PostgREST safeupdate.
create or replace function public.admin_set_ops_database_budget(p_bytes bigint) returns void
language plpgsql security definer set search_path='' as $$
begin
  perform public.assert_ops_admin();
  if p_bytes is null or p_bytes<1073741824 or p_bytes>109951162777600 then raise exception 'INVALID_BUDGET'; end if;
  update public.ops_monitor_settings set database_budget_bytes=p_bytes where singleton = true;
end;
$$;

create or replace function public.evaluate_ops_alerts() returns void
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
  update public.ops_monitor_settings set last_checked_at=now() where singleton = true;
end;
$$;

create or replace function public.record_ops_dispatch_status(p_ok boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
  if auth.role() is distinct from 'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  update public.ops_monitor_settings set last_dispatch_at=now(),last_dispatch_ok=coalesce(p_ok,false) where singleton = true;
end;
$$;
