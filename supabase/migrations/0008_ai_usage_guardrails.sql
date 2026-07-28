alter table public.ai_usage_logs
  add column if not exists latency_ms integer not null default 0,
  add column if not exists request_chars integer not null default 0,
  add column if not exists response_chars integer not null default 0,
  add column if not exists guardrail_stage text not null default 'normal' check (guardrail_stage in ('normal','warning','high','stop','anonymous')),
  add column if not exists meta jsonb not null default '{}'::jsonb;

create index if not exists idx_ai_usage_logs_user_created_at
  on public.ai_usage_logs(user_id, created_at desc);

create or replace view public.ai_usage_monthly_guardrails as
select
  user_id,
  date_trunc('month', created_at) as month_start,
  count(*)::integer as request_count,
  coalesce(sum(cost_krw), 0)::numeric(12,2) as total_cost_krw,
  coalesce(avg(latency_ms), 0)::numeric(10,2) as avg_latency_ms,
  case
    when coalesce(sum(cost_krw), 0) >= 50000 then 'stop'
    when coalesce(sum(cost_krw), 0) >= 45000 then 'high'
    when coalesce(sum(cost_krw), 0) >= 35000 then 'warning'
    else 'normal'
  end as guardrail_stage
from public.ai_usage_logs
group by user_id, date_trunc('month', created_at);

grant select on table public.ai_usage_monthly_guardrails to authenticated, service_role;
