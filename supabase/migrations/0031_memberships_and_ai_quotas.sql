-- Server-owned membership entitlements and atomic AI quota reservations.
-- Paid state is never accepted from the Flutter client.

create table public.membership_plans (
  code text primary key,
  display_name text not null,
  product_id text unique,
  price_krw integer not null check (price_krw >= 0),
  billing_period text not null check (billing_period in ('none', 'monthly', 'annual')),
  recipe_model text not null check (recipe_model in ('gpt-4o-mini', 'gpt-5.4-mini')),
  daily_ai_limit integer not null check (daily_ai_limit >= 0),
  weekly_ai_limit integer not null check (weekly_ai_limit >= 0),
  monthly_ai_limit integer not null check (monthly_ai_limit >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.membership_plans (
  code, display_name, product_id, price_krw, billing_period, recipe_model,
  daily_ai_limit, weekly_ai_limit, monthly_ai_limit
) values
  ('free', '무료 회원', null, 0, 'none', 'gpt-4o-mini', 1, 5, 10),
  ('paid_monthly', '월간 유료 회원', 'recipe_scout_premium_monthly', 9000,
   'monthly', 'gpt-5.4-mini', 10, 50, 100),
  ('paid_annual', '연간 베이직 회원', 'recipe_scout_basic_annual', 30000,
   'annual', 'gpt-5.4-mini', 3, 15, 30);

create table public.member_entitlements (
  user_id uuid primary key references auth.users(id) on delete cascade,
  plan_code text not null references public.membership_plans(code),
  status text not null check (
    status in ('free', 'pending', 'active', 'grace_period', 'paused',
               'canceled', 'expired', 'revoked')
  ),
  source text not null check (source in ('system', 'google_play', 'admin')),
  product_id text,
  purchase_token text,
  started_at timestamptz,
  valid_until timestamptz,
  auto_renews boolean not null default false,
  last_verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (source = 'google_play' and product_id is not null and purchase_token is not null)
    or source <> 'google_play'
  )
);

create unique index member_entitlements_purchase_token_unique
  on public.member_entitlements(purchase_token)
  where purchase_token is not null;

create table public.membership_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  event_type text not null,
  from_plan text,
  to_plan text,
  source text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index membership_events_user_created_at_idx
  on public.membership_events(user_id, created_at desc);

create table public.ai_usage_reservations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null check (
    endpoint in ('ai_recipe_assistant', 'ai_youtube_recipe_assistant')
  ),
  plan_code text not null references public.membership_plans(code),
  status text not null default 'reserved' check (
    status in ('reserved', 'succeeded', 'failed', 'expired')
  ),
  model text,
  request_tokens integer not null default 0 check (request_tokens >= 0),
  response_tokens integer not null default 0 check (response_tokens >= 0),
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create unique index ai_usage_one_in_flight_per_user_idx
  on public.ai_usage_reservations(user_id)
  where status = 'reserved';

create index ai_usage_reservations_user_created_at_idx
  on public.ai_usage_reservations(user_id, created_at desc);

alter table public.membership_plans enable row level security;
alter table public.member_entitlements enable row level security;
alter table public.membership_events enable row level security;
alter table public.ai_usage_reservations enable row level security;

create policy membership_plans_read
on public.membership_plans for select
to authenticated
using (is_active);

-- Membership and purchase-token tables deliberately have no client policies.
-- Clients use the narrow security-definer RPCs below.
grant select on table public.membership_plans to authenticated, service_role;
grant all on table public.member_entitlements to service_role;
grant all on table public.membership_events to service_role;
grant all on table public.ai_usage_reservations to service_role;
grant usage, select on sequence public.membership_events_id_seq to service_role;

create or replace function public.prevent_profile_role_escalation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' and auth.role() = 'authenticated' and new.role <> 'user' then
    raise exception 'PROFILE_ROLE_SERVER_MANAGED';
  end if;
  if tg_op = 'UPDATE' and auth.role() <> 'service_role'
     and new.role is distinct from old.role then
    raise exception 'PROFILE_ROLE_SERVER_MANAGED';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_prevent_role_escalation on public.profiles;
create trigger profiles_prevent_role_escalation
before insert or update on public.profiles
for each row execute function public.prevent_profile_role_escalation();

create or replace function public.get_my_membership()
returns table (
  plan_code text,
  display_name text,
  status text,
  price_krw integer,
  billing_period text,
  recipe_model text,
  daily_limit integer,
  weekly_limit integer,
  monthly_limit integer,
  daily_used integer,
  weekly_used integer,
  monthly_used integer,
  valid_until timestamptz,
  auto_renews boolean,
  is_admin boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_plan_code text := 'free';
  v_status text := 'free';
  v_valid_until timestamptz;
  v_auto_renews boolean := false;
  v_day_start timestamptz := date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
  v_week_start timestamptz := date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
  v_month_start timestamptz := date_trunc('month', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
begin
  if v_user_id is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select e.plan_code, e.status, e.valid_until, e.auto_renews
  into v_plan_code, v_status, v_valid_until, v_auto_renews
  from public.member_entitlements e
  where e.user_id = v_user_id
    and e.plan_code <> 'free'
    and e.status in ('active', 'grace_period', 'canceled')
    and (e.valid_until is null or e.valid_until > now())
  limit 1;

  if not found then
    v_plan_code := 'free';
    v_status := 'free';
    v_valid_until := null;
    v_auto_renews := false;
  end if;

  return query
  select
    p.code,
    p.display_name,
    v_status,
    p.price_krw,
    p.billing_period,
    p.recipe_model,
    p.daily_ai_limit,
    p.weekly_ai_limit,
    p.monthly_ai_limit,
    count(r.id) filter (where r.created_at >= v_day_start)::integer,
    count(r.id) filter (where r.created_at >= v_week_start)::integer,
    count(r.id) filter (where r.created_at >= v_month_start)::integer,
    v_valid_until,
    v_auto_renews,
    exists (
      select 1 from public.profiles profile
      where profile.id = v_user_id and profile.role = 'admin'
    )
  from public.membership_plans p
  left join public.ai_usage_reservations r
    on r.user_id = v_user_id and r.status = 'succeeded'
  where p.code = v_plan_code
  group by p.code, p.display_name, p.price_krw, p.billing_period,
           p.recipe_model, p.daily_ai_limit, p.weekly_ai_limit,
           p.monthly_ai_limit;
end;
$$;

revoke all on function public.get_my_membership() from public, anon;
grant execute on function public.get_my_membership() to authenticated, service_role;

create or replace function public.begin_ai_recipe_usage(
  p_user_id uuid,
  p_endpoint text
)
returns table (
  reservation_id uuid,
  plan_code text,
  recipe_model text,
  daily_limit integer,
  weekly_limit integer,
  monthly_limit integer,
  daily_remaining integer,
  weekly_remaining integer,
  monthly_remaining integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_plan public.membership_plans%rowtype;
  v_plan_code text := 'free';
  v_reservation_id uuid;
  v_daily integer;
  v_weekly integer;
  v_monthly integer;
  v_recent_starts integer;
  v_day_start timestamptz := date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
  v_week_start timestamptz := date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
  v_month_start timestamptz := date_trunc('month', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
begin
  if auth.role() <> 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED';
  end if;
  if p_user_id is null or p_endpoint not in ('ai_recipe_assistant', 'ai_youtube_recipe_assistant') then
    raise exception 'INVALID_AI_USAGE_REQUEST';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

  update public.ai_usage_reservations
  set status = 'expired', completed_at = now()
  where user_id = p_user_id
    and status = 'reserved'
    and created_at < now() - interval '5 minutes';

  select e.plan_code
  into v_plan_code
  from public.member_entitlements e
  where e.user_id = p_user_id
    and e.plan_code <> 'free'
    and e.status in ('active', 'grace_period', 'canceled')
    and (e.valid_until is null or e.valid_until > now())
  limit 1;

  if not found then
    v_plan_code := 'free';
  end if;

  select * into v_plan
  from public.membership_plans p
  where p.code = v_plan_code and p.is_active;

  if not found then
    raise exception 'MEMBERSHIP_PLAN_UNAVAILABLE';
  end if;

  select count(*)::integer into v_recent_starts
  from public.ai_usage_reservations r
  where r.user_id = p_user_id
    and r.created_at >= now() - interval '10 minutes';
  if v_recent_starts >= 3 then
    raise exception 'AI_RATE_LIMIT';
  end if;

  if exists (
    select 1 from public.ai_usage_reservations r
    where r.user_id = p_user_id and r.status = 'reserved'
  ) then
    raise exception 'AI_IN_FLIGHT';
  end if;

  select
    count(*) filter (where r.created_at >= v_day_start)::integer,
    count(*) filter (where r.created_at >= v_week_start)::integer,
    count(*) filter (where r.created_at >= v_month_start)::integer
  into v_daily, v_weekly, v_monthly
  from public.ai_usage_reservations r
  where r.user_id = p_user_id and r.status in ('reserved', 'succeeded');

  if v_daily >= v_plan.daily_ai_limit then raise exception 'AI_QUOTA_DAILY'; end if;
  if v_weekly >= v_plan.weekly_ai_limit then raise exception 'AI_QUOTA_WEEKLY'; end if;
  if v_monthly >= v_plan.monthly_ai_limit then raise exception 'AI_QUOTA_MONTHLY'; end if;

  insert into public.ai_usage_reservations(user_id, endpoint, plan_code)
  values (p_user_id, p_endpoint, v_plan.code)
  returning id into v_reservation_id;

  return query select
    v_reservation_id,
    v_plan.code,
    v_plan.recipe_model,
    v_plan.daily_ai_limit,
    v_plan.weekly_ai_limit,
    v_plan.monthly_ai_limit,
    greatest(v_plan.daily_ai_limit - v_daily - 1, 0),
    greatest(v_plan.weekly_ai_limit - v_weekly - 1, 0),
    greatest(v_plan.monthly_ai_limit - v_monthly - 1, 0);
end;
$$;

revoke all on function public.begin_ai_recipe_usage(uuid, text) from public, anon, authenticated;
grant execute on function public.begin_ai_recipe_usage(uuid, text) to service_role;

create or replace function public.finish_ai_recipe_usage(
  p_user_id uuid,
  p_reservation_id uuid,
  p_succeeded boolean,
  p_model text,
  p_request_tokens integer default 0,
  p_response_tokens integer default 0
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() <> 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED';
  end if;

  update public.ai_usage_reservations
  set
    status = case when p_succeeded then 'succeeded' else 'failed' end,
    model = left(coalesce(p_model, ''), 80),
    request_tokens = greatest(coalesce(p_request_tokens, 0), 0),
    response_tokens = greatest(coalesce(p_response_tokens, 0), 0),
    completed_at = now()
  where id = p_reservation_id
    and user_id = p_user_id
    and status = 'reserved';

  return found;
end;
$$;

revoke all on function public.finish_ai_recipe_usage(uuid, uuid, boolean, text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.finish_ai_recipe_usage(uuid, uuid, boolean, text, integer, integer)
  to service_role;

create or replace function public.admin_list_memberships()
returns table (
  user_id uuid,
  email text,
  display_name text,
  profile_role text,
  plan_code text,
  membership_status text,
  valid_until timestamptz,
  monthly_used integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  if auth.role() <> 'service_role' and not exists (
    select 1 from public.profiles p where p.id = v_actor and p.role = 'admin'
  ) then
    raise exception 'ADMIN_REQUIRED';
  end if;

  return query
  select
    u.id,
    u.email::text,
    p.display_name,
    coalesce(p.role, 'user'),
    coalesce(e.plan_code, 'free'),
    coalesce(e.status, 'free'),
    e.valid_until,
    count(r.id) filter (
      where r.status = 'succeeded'
        and r.created_at >= date_trunc('month', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'
    )::integer
  from auth.users u
  left join public.profiles p on p.id = u.id
  left join public.member_entitlements e on e.user_id = u.id
  left join public.ai_usage_reservations r on r.user_id = u.id
  group by u.id, u.email, p.display_name, p.role, e.plan_code, e.status, e.valid_until
  order by u.created_at desc;
end;
$$;

revoke all on function public.admin_list_memberships() from public, anon;
grant execute on function public.admin_list_memberships() to authenticated, service_role;

create or replace function public.admin_set_membership(
  p_user_id uuid,
  p_plan_code text,
  p_valid_until timestamptz default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_old_plan text;
  v_status text;
begin
  if auth.role() <> 'service_role' and not exists (
    select 1 from public.profiles p where p.id = v_actor and p.role = 'admin'
  ) then
    raise exception 'ADMIN_REQUIRED';
  end if;
  if not exists (
    select 1 from public.membership_plans p where p.code = p_plan_code and p.is_active
  ) then
    raise exception 'INVALID_MEMBERSHIP_PLAN';
  end if;
  if not exists (select 1 from auth.users u where u.id = p_user_id) then
    raise exception 'MEMBER_NOT_FOUND';
  end if;

  select e.plan_code into v_old_plan
  from public.member_entitlements e where e.user_id = p_user_id;
  v_status := case when p_plan_code = 'free' then 'free' else 'active' end;

  insert into public.member_entitlements(
    user_id, plan_code, status, source, started_at, valid_until,
    auto_renews, last_verified_at, updated_at
  ) values (
    p_user_id, p_plan_code, v_status, 'admin', now(), p_valid_until,
    false, now(), now()
  )
  on conflict (user_id) do update set
    plan_code = excluded.plan_code,
    status = excluded.status,
    source = 'admin',
    product_id = null,
    purchase_token = null,
    started_at = excluded.started_at,
    valid_until = excluded.valid_until,
    auto_renews = false,
    last_verified_at = excluded.last_verified_at,
    updated_at = now();

  insert into public.membership_events(
    user_id, actor_id, event_type, from_plan, to_plan, source
  ) values (
    p_user_id, v_actor, 'admin_plan_changed', coalesce(v_old_plan, 'free'),
    p_plan_code, 'admin'
  );

  return true;
end;
$$;

revoke all on function public.admin_set_membership(uuid, text, timestamptz)
  from public, anon;
grant execute on function public.admin_set_membership(uuid, text, timestamptz)
  to authenticated, service_role;
