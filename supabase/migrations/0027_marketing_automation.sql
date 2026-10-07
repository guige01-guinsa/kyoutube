-- Deliberately independent of profiles.role (which users can currently edit).
create table public.marketing_admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.marketing_admins enable row level security;
revoke all on public.marketing_admins from anon, authenticated;
grant select on public.marketing_admins to authenticated;
create policy marketing_admin_self on public.marketing_admins for select
  to authenticated using (user_id = auth.uid());

create table public.marketing_campaigns (
  id uuid primary key default gen_random_uuid(),
  created_by uuid references auth.users(id) on delete set null,
  topic text not null,
  title text not null check (char_length(title) between 1 and 100),
  description text not null check (char_length(description) <= 4500),
  scenes jsonb not null check (jsonb_typeof(scenes) = 'array' and jsonb_array_length(scenes) = 3),
  status text not null default 'draft' check (status in
    ('draft', 'scheduled', 'publishing', 'published', 'failed', 'needs_review', 'cancelled')),
  scheduled_at timestamptz,
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  claimed_at timestamptz,
  youtube_video_id text,
  error_code text,
  views bigint not null default 0,
  likes bigint not null default 0,
  metrics_at timestamptz,
  created_at timestamptz not null default now()
);
create index marketing_due on public.marketing_campaigns(scheduled_at) where status = 'scheduled';
alter table public.marketing_campaigns enable row level security;
revoke all on public.marketing_campaigns from anon, authenticated;
grant select on public.marketing_campaigns to authenticated;
grant all on public.marketing_admins, public.marketing_campaigns to service_role;
create policy marketing_admin_read on public.marketing_campaigns for select to authenticated
  using (exists (select 1 from public.marketing_admins where user_id = auth.uid()));

-- Reserve before calling AI so failures and concurrent calls also consume the cap.
create table public.marketing_generation_requests (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now()
);
alter table public.marketing_generation_requests enable row level security;
revoke all on public.marketing_generation_requests from anon, authenticated;
create function public.reserve_marketing_generation() returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform pg_advisory_xact_lock(2727001);
  if (select count(*) from public.marketing_generation_requests
      where created_at > now() - interval '1 day') >= 5 then return false; end if;
  delete from public.marketing_generation_requests where created_at < now() - interval '7 days';
  insert into public.marketing_generation_requests default values;
  return true;
end $$;
revoke all on function public.reserve_marketing_generation() from public, anon, authenticated;
grant execute on function public.reserve_marketing_generation() to service_role;

create function public.schedule_marketing_campaign(campaign_id uuid, publish_at timestamptz)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not exists (select 1 from public.marketing_admins where user_id = auth.uid()) then
    raise exception 'marketing_admin_required';
  end if;
  if publish_at is null or publish_at < now() + interval '5 minutes'
     or publish_at > now() + interval '30 days' then raise exception 'invalid_schedule'; end if;
  update public.marketing_campaigns set status = 'scheduled', scheduled_at = publish_at,
    approved_by = auth.uid(), approved_at = now(), error_code = null
    where id = campaign_id and status = 'draft';
  if not found then raise exception 'campaign_not_draft'; end if;
end $$;
revoke all on function public.schedule_marketing_campaign(uuid, timestamptz) from public, anon;
grant execute on function public.schedule_marketing_campaign(uuid, timestamptz) to authenticated;

create function public.cancel_marketing_campaign(campaign_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not exists (select 1 from public.marketing_admins where user_id = auth.uid()) then
    raise exception 'marketing_admin_required';
  end if;
  update public.marketing_campaigns set status = 'cancelled'
    where id = campaign_id and status in ('draft', 'scheduled');
  if not found then raise exception 'campaign_not_cancellable'; end if;
end $$;
revoke all on function public.cancel_marketing_campaign(uuid) from public, anon;
grant execute on function public.cancel_marketing_campaign(uuid) to authenticated;

create function public.claim_marketing_campaign() returns setof public.marketing_campaigns
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  -- An interrupted upload can have succeeded upstream; never upload it again automatically.
  update public.marketing_campaigns set status = 'needs_review', error_code = 'worker_interrupted'
    where status = 'publishing' and claimed_at < now() - interval '30 minutes';
  return query
  update public.marketing_campaigns set status = 'publishing', claimed_at = now()
    where id = (select id from public.marketing_campaigns
      where status = 'scheduled' and scheduled_at <= now() and approved_at is not null
      order by scheduled_at for update skip locked limit 1)
    returning *;
end $$;
revoke all on function public.claim_marketing_campaign() from public, anon, authenticated;
grant execute on function public.claim_marketing_campaign() to service_role;
