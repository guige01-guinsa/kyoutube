-- Post-v53 operational telemetry. No prompts, URLs, tokens, stack traces or emails.
create table public.ops_events (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('request', 'client')),
  source text not null check (source in (
    'ai_recipe_assistant', 'ai_youtube_recipe_assistant', 'recipe_api',
    'youtube_search', 'membership', 'youtube_recipe_context', 'delete-account',
    'flutter', 'platform', 'zone', 'firebase', 'auth', 'startup', 'app')),
  outcome text not null check (outcome in ('succeeded', 'failed', 'rejected')),
  code text not null check (code in (
    'ok', 'http_error', 'exception', 'unauthorized', 'quota', 'invalid_request',
    'incomplete_draft', 'upstream', 'configuration', 'timeout', 'network',
    'format', 'state', 'unknown')),
  http_status integer check (http_status between 100 and 599),
  duration_ms integer check (duration_ms between 0 and 3600000),
  fatal boolean not null default false,
  app_build text not null default 'unknown'
    check (app_build = 'unknown' or app_build ~ '^\d{1,3}\.\d{1,3}\.\d{1,3}\+\d{1,9}$'),
  user_id uuid references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index ops_events_created_idx on public.ops_events(created_at desc);
create index ops_events_user_created_idx on public.ops_events(user_id, created_at desc)
  where kind = 'client';
alter table public.ops_events enable row level security;
revoke all on public.ops_events from public, anon, authenticated;
grant select, insert, delete on public.ops_events to service_role;

-- Monthly billing snapshots, not guessed token pricing or an automatic spend cap.
create table public.ops_monthly_costs (
  month date primary key check (extract(day from month) = 1),
  openai_usd numeric(12,2) check (openai_usd >= 0),
  other_usd numeric(12,2) check (other_usd >= 0),
  budget_usd numeric(12,2) not null check (budget_usd > 0),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);
create table public.ops_cost_audit (
  id bigint generated always as identity primary key,
  month date not null,
  openai_usd numeric(12,2),
  other_usd numeric(12,2),
  budget_usd numeric(12,2) not null,
  actor_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.ops_monthly_costs enable row level security;
alter table public.ops_cost_audit enable row level security;
revoke all on public.ops_monthly_costs, public.ops_cost_audit from public, anon, authenticated;
grant all on public.ops_monthly_costs, public.ops_cost_audit to service_role;
grant usage, select on sequence public.ops_cost_audit_id_seq to service_role;

create function public.assert_ops_admin() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.profiles where id = auth.uid() and role = 'admin'
  ) then raise exception 'ADMIN_REQUIRED'; end if;
end;
$$;
revoke all on function public.assert_ops_admin() from public, anon, authenticated;

create function public.record_app_operational_event(
  p_source text, p_code text, p_fatal boolean, p_app_build text default 'unknown'
) returns boolean language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null or coalesce((auth.jwt()->>'is_anonymous')::boolean, false) then
    raise exception 'AUTH_REQUIRED';
  end if;
  if p_source is null or p_source not in ('flutter','platform','zone','firebase','auth','startup','app')
    or p_code is null or p_code not in ('timeout','network','format','state','unknown') then
    raise exception 'INVALID_EVENT';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user::text, 36));
  if (select count(*) from public.ops_events where user_id = v_user and kind = 'client'
    and created_at >= now() - interval '1 hour') >= 20 then return false; end if;
  insert into public.ops_events(kind,source,outcome,code,fatal,app_build,user_id)
    values ('client',p_source,'failed',p_code,coalesce(p_fatal,false),coalesce(p_app_build,'unknown'),v_user);
  return true;
end;
$$;
revoke all on function public.record_app_operational_event(text,text,boolean,text) from public, anon;
grant execute on function public.record_app_operational_event(text,text,boolean,text) to authenticated;

create function public.admin_set_ops_monthly_costs(
  p_month date, p_openai_usd numeric, p_other_usd numeric, p_budget_usd numeric
) returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.assert_ops_admin();
  if p_month is null or extract(day from p_month) <> 1 or p_budget_usd is null
    or p_budget_usd <= 0 or p_budget_usd > 9999999999
    or p_openai_usd < 0 or p_other_usd < 0
    or p_openai_usd > 9999999999 or p_other_usd > 9999999999
    or p_budget_usd::text in ('NaN','Infinity','-Infinity')
    or p_openai_usd::text in ('NaN','Infinity','-Infinity')
    or p_other_usd::text in ('NaN','Infinity','-Infinity') then
    raise exception 'INVALID_COST';
  end if;
  insert into public.ops_monthly_costs(month,openai_usd,other_usd,budget_usd,updated_by)
    values(p_month,p_openai_usd,p_other_usd,p_budget_usd,auth.uid())
    on conflict(month) do update set openai_usd=excluded.openai_usd,other_usd=excluded.other_usd,
      budget_usd=excluded.budget_usd,updated_by=excluded.updated_by,updated_at=now();
  insert into public.ops_cost_audit(month,openai_usd,other_usd,budget_usd,actor_id)
    values(p_month,p_openai_usd,p_other_usd,p_budget_usd,auth.uid());
end;
$$;
revoke all on function public.admin_set_ops_monthly_costs(date,numeric,numeric,numeric) from public, anon;
grant execute on function public.admin_set_ops_monthly_costs(date,numeric,numeric,numeric) to authenticated;

create function public.admin_get_ops_overview(p_days integer default 7)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_since timestamptz;
  v_month date := date_trunc('month', now() at time zone 'UTC')::date;
  v_requests jsonb; v_failures jsonb; v_ai jsonb; v_cost jsonb;
begin
  perform public.assert_ops_admin();
  if p_days is null or p_days not in (1,7,30) then raise exception 'INVALID_RANGE'; end if;
  v_since := now() - make_interval(days => p_days);
  select jsonb_build_object(
    'total',count(*) filter(where kind='request'),
    'failed',count(*) filter(where kind='request' and outcome='failed'),
    'rejected',count(*) filter(where kind='request' and outcome='rejected'),
    'client_errors',count(*) filter(where kind='client'),
    'fatal_errors',count(*) filter(where kind='client' and fatal),
    'last_event_at',max(created_at),
    'ai_attempts',count(*) filter(where kind='request' and source in ('ai_recipe_assistant','ai_youtube_recipe_assistant') and outcome <> 'rejected'),
    'ai_successes',count(*) filter(where kind='request' and source in ('ai_recipe_assistant','ai_youtube_recipe_assistant') and outcome='succeeded'),
    'ai_p95_ms',percentile_cont(0.95) within group(order by duration_ms)
      filter(where kind='request' and source in ('ai_recipe_assistant','ai_youtube_recipe_assistant') and outcome <> 'rejected')
  ) into v_requests from public.ops_events where created_at >= v_since;

  select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) into v_failures from (
    select kind,source,code,count(*) as count,max(created_at) as last_seen
    from public.ops_events where created_at >= v_since and outcome='failed'
    group by kind,source,code order by count(*) desc, max(created_at) desc limit 15
  ) t;
  -- Ledger covers both successful and failed generations, including recorded repair tokens.
  -- Zero-token and unfinished rows are exposed as unknown, never as free API calls.
  select jsonb_build_object(
    'month',v_month,'reservations',count(*),
    'input_tokens',coalesce(sum(request_tokens),0),
    'output_tokens',coalesce(sum(response_tokens),0),
    'unknown_usage',count(*) filter(where request_tokens=0 and response_tokens=0),
    'stale_reservations',count(*) filter(where status='reserved' and created_at < now()-interval '15 minutes'),
    'last_completed_at',max(completed_at)
  ) into v_ai from public.ai_usage_reservations
    where created_at >= (v_month::timestamp at time zone 'UTC');
  select to_jsonb(c) - 'updated_by' into v_cost from public.ops_monthly_costs c where month=v_month;
  return jsonb_build_object('generated_at',now(),'days',p_days,'requests',v_requests,
    'failures',v_failures,'usage',v_ai,'costs',v_cost);
end;
$$;
revoke all on function public.admin_get_ops_overview(integer) from public, anon;
grant execute on function public.admin_get_ops_overview(integer) to authenticated;

-- Explicit, bounded retention maintenance. Run daily from an approved scheduler.
create function public.purge_ops_events() returns integer
language plpgsql security definer set search_path = '' as $$
declare n integer;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  delete from public.ops_events where id in (
    select id from public.ops_events where created_at < now()-interval '90 days' order by created_at limit 10000
  );
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function public.purge_ops_events() from public, anon, authenticated;
grant execute on function public.purge_ops_events() to service_role;
