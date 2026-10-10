-- Let administrators update quota policy without changing product identifiers.
-- Google Play remains authoritative for the price charged at checkout.

create table public.membership_policy_events (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users(id) on delete set null,
  plan_code text not null references public.membership_plans(code),
  previous_policy jsonb not null,
  next_policy jsonb not null,
  created_at timestamptz not null default now()
);

create index membership_policy_events_plan_created_idx
  on public.membership_policy_events(plan_code, created_at desc);

alter table public.membership_policy_events enable row level security;
grant all on table public.membership_policy_events to service_role;
grant usage, select on sequence public.membership_policy_events_id_seq
  to service_role;

create or replace function public.admin_list_membership_plan_policies()
returns table (
  code text,
  display_name text,
  product_id text,
  price_krw integer,
  billing_period text,
  recipe_model text,
  daily_ai_limit integer,
  weekly_ai_limit integer,
  monthly_ai_limit integer,
  is_active boolean,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  if auth.role() <> 'service_role' and not exists (
    select 1 from public.profiles profile
    where profile.id = v_actor and profile.role = 'admin'
  ) then
    raise exception 'ADMIN_REQUIRED';
  end if;

  return query
  select
    plan.code,
    plan.display_name,
    plan.product_id,
    plan.price_krw,
    plan.billing_period,
    plan.recipe_model,
    plan.daily_ai_limit,
    plan.weekly_ai_limit,
    plan.monthly_ai_limit,
    plan.is_active,
    plan.updated_at
  from public.membership_plans plan
  order by case plan.code
    when 'free' then 0
    when 'paid_monthly' then 1
    when 'paid_annual' then 2
    else 3
  end;
end;
$$;

revoke all on function public.admin_list_membership_plan_policies()
  from public, anon;
grant execute on function public.admin_list_membership_plan_policies()
  to authenticated, service_role;

create or replace function public.admin_update_membership_plan_policy(
  p_plan_code text,
  p_price_krw integer,
  p_recipe_model text,
  p_daily_ai_limit integer,
  p_weekly_ai_limit integer,
  p_monthly_ai_limit integer,
  p_is_active boolean
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_previous public.membership_plans%rowtype;
  v_next public.membership_plans%rowtype;
begin
  if auth.role() <> 'service_role' and not exists (
    select 1 from public.profiles profile
    where profile.id = v_actor and profile.role = 'admin'
  ) then
    raise exception 'ADMIN_REQUIRED';
  end if;
  if p_plan_code not in ('free', 'paid_monthly', 'paid_annual')
     or p_recipe_model not in ('gpt-4o-mini', 'gpt-5.4-mini')
     or p_price_krw is null or p_price_krw < 0
     or p_daily_ai_limit is null or p_daily_ai_limit < 0
     or p_weekly_ai_limit is null or p_weekly_ai_limit < p_daily_ai_limit
     or p_monthly_ai_limit is null or p_monthly_ai_limit < p_weekly_ai_limit
     or p_is_active is null
     or (p_plan_code = 'free' and p_price_krw <> 0) then
    raise exception 'INVALID_MEMBERSHIP_POLICY';
  end if;

  select * into v_previous
  from public.membership_plans plan
  where plan.code = p_plan_code
  for update;
  if not found then raise exception 'MEMBERSHIP_PLAN_NOT_FOUND'; end if;

  update public.membership_plans plan
  set
    price_krw = p_price_krw,
    recipe_model = p_recipe_model,
    daily_ai_limit = p_daily_ai_limit,
    weekly_ai_limit = p_weekly_ai_limit,
    monthly_ai_limit = p_monthly_ai_limit,
    is_active = p_is_active,
    updated_at = now()
  where plan.code = p_plan_code
  returning * into v_next;

  insert into public.membership_policy_events(
    actor_id, plan_code, previous_policy, next_policy
  ) values (
    v_actor,
    p_plan_code,
    jsonb_build_object(
      'price_krw', v_previous.price_krw,
      'recipe_model', v_previous.recipe_model,
      'daily_ai_limit', v_previous.daily_ai_limit,
      'weekly_ai_limit', v_previous.weekly_ai_limit,
      'monthly_ai_limit', v_previous.monthly_ai_limit,
      'is_active', v_previous.is_active
    ),
    jsonb_build_object(
      'price_krw', v_next.price_krw,
      'recipe_model', v_next.recipe_model,
      'daily_ai_limit', v_next.daily_ai_limit,
      'weekly_ai_limit', v_next.weekly_ai_limit,
      'monthly_ai_limit', v_next.monthly_ai_limit,
      'is_active', v_next.is_active
    )
  );

  return true;
end;
$$;

revoke all on function public.admin_update_membership_plan_policy(
  text, integer, text, integer, integer, integer, boolean
) from public, anon;
grant execute on function public.admin_update_membership_plan_policy(
  text, integer, text, integer, integer, integer, boolean
) to authenticated, service_role;
