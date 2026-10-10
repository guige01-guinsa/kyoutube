-- Pre-launch replacement policy. Existing recipe/purchase/audit data is retained.
-- Checkout stays closed until Play configuration is independently verified.
update public.membership_plans set is_active=false where code in ('paid_monthly','paid_annual');
update public.membership_feature_profiles set is_active=(tier_code<>'legacy');
update public.membership_plan_feature_profiles set profile_code='scout' where plan_code='free';
insert into public.membership_plans
 (code,display_name,price_krw,billing_period,recipe_model,daily_ai_limit,weekly_ai_limit,monthly_ai_limit,is_active) values
 ('plus_monthly','Recipe Plus · Monthly',5900,'monthly','gpt-5.4-mini',5,25,50,true),
 ('plus_annual','Recipe Plus · Annual',59000,'annual','gpt-5.4-mini',5,25,50,true),
 ('business_monthly','Chef Business · Monthly',14900,'monthly','gpt-5.4-mini',10,50,100,true),
 ('business_annual','Chef Business · Annual',149000,'annual','gpt-5.4-mini',10,50,100,true);
insert into public.membership_plan_feature_profiles values
 ('plus_monthly','plus'),('plus_annual','plus'),('business_monthly','business'),('business_annual','business');

create table public.membership_billing_offers (
 plan_code text primary key references public.membership_plans(code),
 product_id text not null,
 base_plan_id text not null,
 checkout_enabled boolean not null default false,
 verified_at timestamptz,
 unique(product_id,base_plan_id),
 check (not checkout_enabled or verified_at is not null)
);
-- These are the intended NEW Console IDs, not a claim that products exist.
insert into public.membership_billing_offers(plan_code,product_id,base_plan_id) values
 ('plus_monthly','recipe_scout_plus','monthly'),('plus_annual','recipe_scout_plus','annual'),
 ('business_monthly','recipe_scout_business','monthly'),('business_annual','recipe_scout_business','annual');
alter table public.membership_billing_offers enable row level security;
revoke all on public.membership_billing_offers from public,anon,authenticated;
grant all on public.membership_billing_offers to service_role;
create function public.get_membership_billing_catalog() returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('plan_code',b.plan_code,'product_id',b.product_id,
 'base_plan_id',b.base_plan_id,'checkout_enabled',b.checkout_enabled,'price_krw',p.price_krw)
 order by p.price_krw),'[]'::jsonb)
 from public.membership_billing_offers b join public.membership_plans p on p.code=b.plan_code
 where p.is_active and auth.uid() is not null;
$$;
revoke all on function public.get_membership_billing_catalog() from public,anon;
grant execute on function public.get_membership_billing_catalog() to authenticated;

-- Update existing functions in place, preserving installed MFA/security guards.
do $$ declare fn text; old_text text; definition text; begin
 foreach fn in array array['get_my_membership()','begin_ai_recipe_usage(uuid,text)'] loop
  definition:=pg_get_functiondef(('public.'||fn)::regprocedure);
  old_text:='and (e.valid_until is null or e.valid_until > now())';
  if position(old_text in definition)=0 then raise exception 'UNEXPECTED_MEMBERSHIP_FUNCTION: %',fn; end if;
  definition:=replace(definition,old_text,
   'and e.valid_until > now() and (e.started_at is null or e.started_at<=now()) and exists(select 1 from public.membership_plans active_plan where active_plan.code=e.plan_code and active_plan.is_active)');
  execute definition;
 end loop;
 definition:=pg_get_functiondef('public.member_feature_snapshot(uuid)'::regprocedure);
 execute replace(definition,'(e.valid_until is null or e.valid_until>now())','e.valid_until>now()');
 definition:=pg_get_functiondef('public.admin_update_membership_plan_policy(text,integer,text,integer,integer,integer,boolean)'::regprocedure);
 execute replace(definition,'''free'', ''paid_monthly'', ''paid_annual''',
  '''free'', ''plus_monthly'', ''plus_annual'', ''business_monthly'', ''business_annual''');
end;$$;

-- Stop old promotions and allow new plan codes while preserving admin guards.
update public.subscription_discount_campaigns set is_active=false;
do $$ declare c record; definition text; begin
 for c in select conname from pg_constraint where conrelid='public.subscription_discount_campaigns'::regclass
 and contype='c' and pg_get_constraintdef(oid) like '%plan_code%' loop
  execute format('alter table public.subscription_discount_campaigns drop constraint %I',c.conname);
 end loop;
 definition:=pg_get_functiondef('public.admin_upsert_subscription_discount_campaign(uuid,text,text,text,text,text,timestamp with time zone,timestamp with time zone,boolean)'::regprocedure);
 execute replace(definition,'''paid_monthly'', ''paid_annual''',
  '''plus_monthly'', ''plus_annual'', ''business_monthly'', ''business_annual''');
end;$$;
alter table public.subscription_discount_campaigns add constraint launch_campaign_plan
 check (not is_active or plan_code in ('plus_monthly','plus_annual','business_monthly','business_annual'));

create or replace function public.begin_ai_video_usage(p_user_id uuid)
returns table(reservation_id uuid,plan_code text,recipe_model text)
language plpgsql security definer set search_path='' as $$
declare r record; quota integer;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
 if p_user_id is null then raise exception 'INVALID_AI_USAGE_REQUEST'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_user_id::text,0));
 quota:=(public.member_feature_snapshot(p_user_id)->>'video_monthly_limit')::integer;
 if quota<=0 then raise exception 'VIDEO_MEMBERSHIP_REQUIRED'; end if;
 if (select count(*) from public.ai_usage_reservations a where a.user_id=p_user_id and a.video_analysis
  and a.created_at>=date_trunc('month',now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'
  and (a.video_provider_started or (a.status='reserved' and a.created_at>now()-interval '5 minutes')))>=quota
 then raise exception 'VIDEO_QUOTA_MONTHLY'; end if;
 select * into r from public.begin_ai_recipe_usage(p_user_id,'ai_youtube_recipe_assistant');
 update public.ai_usage_reservations set video_analysis=true where id=r.reservation_id;
 return query select r.reservation_id::uuid,r.plan_code::text,r.recipe_model::text;
end;$$;
create or replace function public.get_my_video_analysis_usage()
returns table(monthly_limit integer,monthly_used integer)
language sql stable security definer set search_path='' as $$
 select (public.member_feature_snapshot(auth.uid())->>'video_monthly_limit')::integer,count(*)::integer
 from public.ai_usage_reservations a where a.user_id=auth.uid() and a.video_analysis and a.video_provider_started
 and a.created_at>=date_trunc('month',now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
$$;

create or replace function public.limit_shopping_suppliers() returns trigger
language plpgsql security definer set search_path='' as $$
declare quota integer; begin
 perform pg_advisory_xact_lock(hashtextextended('shopping-suppliers:'||new.owner_id::text,0));
 quota:=(public.member_feature_snapshot(new.owner_id)->>'supplier_limit')::integer;
 if not exists(select 1 from public.shopping_suppliers where id=new.id)
 and (select count(*) from public.shopping_suppliers where owner_id=new.owner_id)>=quota
 then raise exception 'SUPPLIER_LIMIT'; end if;
 return new;
end;$$;

-- Durable creation ledger: deleting a request cannot restore monthly quota.
create table public.supplier_request_creation_usage (
 request_id uuid primary key,
 user_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now()
);
create index on public.supplier_request_creation_usage(user_id,created_at);
alter table public.supplier_request_creation_usage enable row level security;
revoke all on public.supplier_request_creation_usage from public,anon,authenticated;
grant all on public.supplier_request_creation_usage to service_role;
create function public.enforce_supplier_request_quota() returns trigger
language plpgsql security definer set search_path='' as $$
declare quota integer; begin
 perform pg_advisory_xact_lock(hashtextextended('request-quota:'||new.owner_id::text,0));
 if exists(select 1 from public.supplier_request_creation_usage where request_id=new.id) then
  raise exception 'REQUEST_ID_REUSED';
 end if;
 quota:=(public.member_feature_snapshot(new.owner_id)->>'request_monthly_limit')::integer;
 if quota is not null and (select count(*) from public.supplier_request_creation_usage
  where user_id=new.owner_id and created_at>=date_trunc('month',now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul')>=quota
 then raise exception 'SUPPLIER_REQUEST_MONTHLY_LIMIT'; end if;
 insert into public.supplier_request_creation_usage(request_id,user_id) values(new.id,new.owner_id);
 return new;
end;$$;
revoke all on function public.enforce_supplier_request_quota() from public,anon,authenticated;
create trigger supplier_request_quota before insert on public.supplier_purchase_requests
 for each row execute function public.enforce_supplier_request_quota();

create function public.assert_request_pdf_access() returns void
language plpgsql stable security definer set search_path='' as $$
begin
 if not (public.member_feature_snapshot(auth.uid())->>'can_share_request_pdf')::boolean
 then raise exception 'PDF_MEMBERSHIP_REQUIRED'; end if;
end;$$;
revoke all on function public.assert_request_pdf_access() from public,anon;
grant execute on function public.assert_request_pdf_access() to authenticated;
