-- This view is an internal cost/guardrail report.  It must never expose
-- another user's aggregate AI usage to a signed-in client.
alter view public.ai_usage_monthly_guardrails
  set (security_invoker = true);

revoke all on table public.ai_usage_monthly_guardrails from anon, authenticated;
grant select on table public.ai_usage_monthly_guardrails to service_role;
