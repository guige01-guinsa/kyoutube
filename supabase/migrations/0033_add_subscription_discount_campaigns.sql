-- Schedule Google Play subscription offers without letting the app invent prices.
-- The offer itself must already exist and be active in Play Console.

create table public.subscription_discount_campaigns (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 80),
  headline_ko text not null check (length(trim(headline_ko)) between 1 and 120),
  headline_en text not null check (length(trim(headline_en)) between 1 and 120),
  plan_code text not null references public.membership_plans(code),
  google_play_offer_id text not null
    check (length(trim(google_play_offer_id)) between 1 and 80),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at),
  check (plan_code in ('paid_monthly', 'paid_annual'))
);

create index subscription_discount_campaigns_active_window_idx
  on public.subscription_discount_campaigns(is_active, starts_at, ends_at);

alter table public.subscription_discount_campaigns enable row level security;

-- Clients use the narrow functions below. Direct table access stays closed.
grant all on table public.subscription_discount_campaigns to service_role;

create or replace function public.get_active_subscription_discount_campaigns()
returns table (
  id uuid,
  name text,
  headline_ko text,
  headline_en text,
  plan_code text,
  google_play_offer_id text,
  starts_at timestamptz,
  ends_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    campaign.id,
    campaign.name,
    campaign.headline_ko,
    campaign.headline_en,
    campaign.plan_code,
    campaign.google_play_offer_id,
    campaign.starts_at,
    campaign.ends_at
  from public.subscription_discount_campaigns campaign
  where campaign.is_active
    and campaign.starts_at <= now()
    and campaign.ends_at > now()
  order by campaign.starts_at desc;
$$;

revoke all on function public.get_active_subscription_discount_campaigns()
  from public, anon;
grant execute on function public.get_active_subscription_discount_campaigns()
  to authenticated, service_role;

create or replace function public.admin_list_subscription_discount_campaigns()
returns table (
  id uuid,
  name text,
  headline_ko text,
  headline_en text,
  plan_code text,
  google_play_offer_id text,
  starts_at timestamptz,
  ends_at timestamptz,
  is_active boolean,
  created_at timestamptz
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
    campaign.id,
    campaign.name,
    campaign.headline_ko,
    campaign.headline_en,
    campaign.plan_code,
    campaign.google_play_offer_id,
    campaign.starts_at,
    campaign.ends_at,
    campaign.is_active,
    campaign.created_at
  from public.subscription_discount_campaigns campaign
  order by campaign.starts_at desc, campaign.created_at desc;
end;
$$;

revoke all on function public.admin_list_subscription_discount_campaigns()
  from public, anon;
grant execute on function public.admin_list_subscription_discount_campaigns()
  to authenticated, service_role;

create or replace function public.admin_upsert_subscription_discount_campaign(
  p_id uuid,
  p_name text,
  p_headline_ko text,
  p_headline_en text,
  p_plan_code text,
  p_google_play_offer_id text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_is_active boolean
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
begin
  if auth.role() <> 'service_role' and not exists (
    select 1 from public.profiles profile
    where profile.id = v_actor and profile.role = 'admin'
  ) then
    raise exception 'ADMIN_REQUIRED';
  end if;
  if trim(coalesce(p_name, '')) = ''
     or trim(coalesce(p_headline_ko, '')) = ''
     or trim(coalesce(p_headline_en, '')) = ''
     or trim(coalesce(p_google_play_offer_id, '')) = ''
     or p_plan_code not in ('paid_monthly', 'paid_annual')
     or p_starts_at is null
     or p_ends_at is null
     or p_ends_at <= p_starts_at then
    raise exception 'INVALID_DISCOUNT_CAMPAIGN';
  end if;

  if p_id is null then
    insert into public.subscription_discount_campaigns(
      name, headline_ko, headline_en, plan_code, google_play_offer_id,
      starts_at, ends_at, is_active, created_by
    ) values (
      trim(p_name), trim(p_headline_ko), trim(p_headline_en), p_plan_code,
      trim(p_google_play_offer_id), p_starts_at, p_ends_at,
      coalesce(p_is_active, true), v_actor
    ) returning id into v_id;
  else
    update public.subscription_discount_campaigns campaign
    set
      name = trim(p_name),
      headline_ko = trim(p_headline_ko),
      headline_en = trim(p_headline_en),
      plan_code = p_plan_code,
      google_play_offer_id = trim(p_google_play_offer_id),
      starts_at = p_starts_at,
      ends_at = p_ends_at,
      is_active = coalesce(p_is_active, true),
      updated_at = now()
    where campaign.id = p_id
    returning campaign.id into v_id;

    if v_id is null then
      raise exception 'DISCOUNT_CAMPAIGN_NOT_FOUND';
    end if;
  end if;

  return v_id;
end;
$$;

revoke all on function public.admin_upsert_subscription_discount_campaign(
  uuid, text, text, text, text, text, timestamptz, timestamptz, boolean
) from public, anon;
grant execute on function public.admin_upsert_subscription_discount_campaign(
  uuid, text, text, text, text, text, timestamptz, timestamptz, boolean
) to authenticated, service_role;

create or replace function public.admin_delete_subscription_discount_campaign(
  p_id uuid
)
returns boolean
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

  delete from public.subscription_discount_campaigns campaign
  where campaign.id = p_id;
  return found;
end;
$$;

revoke all on function public.admin_delete_subscription_discount_campaign(uuid)
  from public, anon;
grant execute on function public.admin_delete_subscription_discount_campaign(uuid)
  to authenticated, service_role;
