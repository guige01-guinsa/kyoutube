-- Additive transition foundation. No users, purchase tokens, existing prices,
-- AI quotas or shopping records are migrated. New tiers are deliberately dormant.
create table public.membership_feature_profiles (
 code text primary key,
 tier_code text not null check (tier_code in ('legacy','scout','plus','business')),
 is_active boolean not null default false,
 can_manage_costs boolean not null default false,
 can_manage_sales boolean not null default false,
 can_share_request_pdf boolean not null default false,
 supplier_limit integer not null check (supplier_limit between 0 and 200),
 request_monthly_limit integer check (request_monthly_limit between 0 and 1000),
 video_monthly_limit integer not null check (video_monthly_limit between 0 and 20),
 -- Existing financial RPCs share one access boundary until a later migration.
 check (can_manage_sales = can_manage_costs)
);

create table public.membership_plan_feature_profiles (
 plan_code text primary key references public.membership_plans(code),
 profile_code text not null references public.membership_feature_profiles(code)
);

-- Draft offers cannot be sold by the existing membership endpoint or app.
-- A separate reviewed billing migration must install product/base-plan mappings,
-- quota enforcement and lifecycle handling before introducing these offers.
create table public.membership_offer_drafts (
 code text primary key,
 profile_code text not null references public.membership_feature_profiles(code),
 billing_period text not null check (billing_period in ('monthly','annual')),
 proposed_price_krw integer not null check (proposed_price_krw >= 0),
 proposed_ai_monthly_limit integer not null check (proposed_ai_monthly_limit >= 0),
 status text not null default 'draft' check (status = 'draft'),
 unique(profile_code,billing_period)
);

insert into public.membership_feature_profiles values
 ('legacy_free','legacy',true,false,false,true,200,null,0),
 ('legacy_monthly','legacy',true,true,true,true,200,null,20),
 ('legacy_annual','legacy',true,true,true,true,200,null,0),
 ('scout','scout',false,false,false,false,3,3,0),
 ('plus','plus',false,false,false,true,30,30,5),
 ('business','business',false,true,true,true,200,null,20);

insert into public.membership_plan_feature_profiles values
 ('free','legacy_free'),('paid_monthly','legacy_monthly'),('paid_annual','legacy_annual');

insert into public.membership_offer_drafts
 (code,profile_code,billing_period,proposed_price_krw,proposed_ai_monthly_limit) values
 ('plus_monthly','plus','monthly',5900,50),
 ('plus_annual','plus','annual',59000,50),
 ('business_monthly','business','monthly',14900,100),
 ('business_annual','business','annual',149000,100);

alter table public.membership_feature_profiles enable row level security;
alter table public.membership_plan_feature_profiles enable row level security;
alter table public.membership_offer_drafts enable row level security;
revoke all on public.membership_feature_profiles,public.membership_plan_feature_profiles,
 public.membership_offer_drafts from public,anon,authenticated;
grant select,insert,update,delete on public.membership_feature_profiles,
 public.membership_plan_feature_profiles,public.membership_offer_drafts to service_role;

create function public.member_feature_snapshot(p_user_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare f public.membership_feature_profiles; r record; bounded_term boolean:=false;
begin
 if p_user_id is null then raise exception 'AUTH_REQUIRED'; end if;
 select fp as profile,e.valid_until>now() as bounded into r
 from public.member_entitlements e
 join public.membership_plans p on p.code=e.plan_code and p.is_active
 join public.membership_plan_feature_profiles m on m.plan_code=p.code
 join public.membership_feature_profiles fp on fp.code=m.profile_code and fp.is_active
 where e.user_id=p_user_id and e.plan_code<>'free'
 and e.status in ('active','grace_period','canceled')
 and (e.valid_until is null or e.valid_until>now())
 and (e.started_at is null or e.started_at<=now());
 if found then
   f:=r.profile;
   bounded_term:=r.bounded;
 else
   select fp.* into f from public.membership_feature_profiles fp
   join public.membership_plan_feature_profiles m on m.profile_code=fp.code
   where m.plan_code='free' and fp.is_active;
 end if;
 if f.code is null then raise exception 'FEATURE_POLICY_UNAVAILABLE'; end if;
 return jsonb_build_object(
   'schema_version',1,
   'can_manage_costs',f.can_manage_costs and coalesce(bounded_term,false),
   'can_manage_sales',f.can_manage_sales and coalesce(bounded_term,false),
   'can_share_request_pdf',f.can_share_request_pdf,
   'supplier_limit',f.supplier_limit,
   'request_monthly_limit',f.request_monthly_limit,
   'video_monthly_limit',f.video_monthly_limit);
end;$$;
revoke all on function public.member_feature_snapshot(uuid) from public,anon,authenticated;
grant execute on function public.member_feature_snapshot(uuid) to service_role;

create function public.get_my_membership_features() returns jsonb
language sql stable security definer set search_path='' as $$
 select public.member_feature_snapshot(auth.uid());
$$;
revoke all on function public.get_my_membership_features() from public,anon;
grant execute on function public.get_my_membership_features() to authenticated;

-- Preserve the existing RLS/RPC interface and the strict finite-term financial
-- check from 0046. Both old and new clients continue using the same boundary.
create or replace function public.has_chef_paid_access() returns boolean
language sql stable security definer set search_path='' as $$
 select case when auth.uid() is null then false else
   coalesce((public.member_feature_snapshot(auth.uid())->>'can_manage_costs')::boolean,false)
 end;
$$;
revoke all on function public.has_chef_paid_access() from public,anon;
grant execute on function public.has_chef_paid_access() to authenticated;
