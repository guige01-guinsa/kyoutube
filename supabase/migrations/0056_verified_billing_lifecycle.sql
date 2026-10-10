-- Only the server may apply authoritative Google Play responses.
create sequence public.billing_verification_serial;
revoke all on sequence public.billing_verification_serial from public,anon,authenticated;
grant usage on sequence public.billing_verification_serial to service_role;
create function public.begin_billing_verification() returns bigint
language plpgsql security definer set search_path='' as $$ begin
 if auth.role() is distinct from 'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
 return nextval('public.billing_verification_serial');
end;$$;
revoke all on function public.begin_billing_verification() from public,anon,authenticated;
grant execute on function public.begin_billing_verification() to service_role;

create table public.verified_billing_tokens (
 token_hash text primary key check(token_hash ~ '^[a-f0-9]{64}$'),
 user_id uuid not null references auth.users(id) on delete cascade,
 replaced_by text,
 verified_at timestamptz not null default now()
);
create table public.member_billing_state (
 user_id uuid primary key references auth.users(id) on delete cascade,
 token_hash text not null references public.verified_billing_tokens(token_hash),
 applied_serial bigint not null
);
alter table public.verified_billing_tokens enable row level security;
alter table public.member_billing_state enable row level security;
revoke all on public.verified_billing_tokens,public.member_billing_state from public,anon,authenticated;
grant all on public.verified_billing_tokens,public.member_billing_state to service_role;

create function public.apply_verified_membership(
 p_user_id uuid,p_token text,p_token_hash text,p_linked_hash text,p_serial bigint,
 p_plan_code text,p_product_id text,p_base_plan_id text,p_status text,
 p_started_at timestamptz,p_valid_until timestamptz,p_auto_renews boolean
) returns boolean language plpgsql security definer set search_path='' as $$
declare current_state public.member_billing_state; previous public.member_entitlements;
 target_plan text; claimed public.verified_billing_tokens; changed boolean;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
 if p_user_id is null or length(p_token) not between 20 and 4096
 or p_token_hash is null or p_token_hash !~ '^[a-f0-9]{64}$'
 or p_serial is null or p_serial<=0 or p_status is null
 or p_status not in ('active','grace_period','canceled','paused','pending','expired','revoked')
 or p_valid_until is null or p_started_at is null or p_auto_renews is null
 or p_linked_hash=p_token_hash then raise exception 'INVALID_VERIFICATION'; end if;
 if not exists(select 1 from public.membership_billing_offers b join public.membership_plans p on p.code=b.plan_code
  where b.plan_code=p_plan_code and b.product_id=p_product_id and b.base_plan_id=p_base_plan_id and p.is_active)
 then raise exception 'UNKNOWN_BILLING_OFFER'; end if;
 if p_status='pending' then return false; end if;
 perform pg_advisory_xact_lock(hashtextextended('billing:'||p_user_id::text,0));
 insert into public.verified_billing_tokens(token_hash,user_id) values(p_token_hash,p_user_id) on conflict do nothing;
 select * into claimed from public.verified_billing_tokens where token_hash=p_token_hash for update;
 if claimed.user_id<>p_user_id then raise exception 'PURCHASE_ACCOUNT_MISMATCH'; end if;
 if claimed.replaced_by is not null then return false; end if;
 select * into current_state from public.member_billing_state where user_id=p_user_id;
 if current_state.applied_serial>=p_serial then return false; end if;
 if p_linked_hash is not null then
  insert into public.verified_billing_tokens(token_hash,user_id,replaced_by)
   values(p_linked_hash,p_user_id,p_token_hash) on conflict do nothing;
  select * into claimed from public.verified_billing_tokens where token_hash=p_linked_hash for update;
  if claimed.user_id<>p_user_id then raise exception 'PURCHASE_ACCOUNT_MISMATCH'; end if;
  if claimed.replaced_by is not null and claimed.replaced_by<>p_token_hash then raise exception 'PURCHASE_CHAIN_CONFLICT'; end if;
  update public.verified_billing_tokens set replaced_by=p_token_hash where token_hash=p_linked_hash;
 end if;
 select * into previous from public.member_entitlements where user_id=p_user_id for update;
 if current_state.token_hash is not null and current_state.token_hash<>p_token_hash
 and current_state.token_hash is distinct from p_linked_hash
 and previous.status in ('active','grace_period','canceled') and previous.valid_until>now()
 then raise exception 'OTHER_SUBSCRIPTION_ACTIVE'; end if;
 target_plan:=case when p_status in ('active','grace_period','canceled')
 and p_valid_until>now() and p_started_at<=now() then p_plan_code else 'free' end;
 changed:=previous.user_id is null or row(previous.plan_code,previous.status,previous.valid_until,previous.auto_renews,previous.purchase_token)
  is distinct from row(target_plan,p_status,p_valid_until,p_auto_renews,p_token);
 insert into public.member_entitlements(user_id,plan_code,status,source,product_id,purchase_token,
  started_at,valid_until,auto_renews,last_verified_at,updated_at)
 values(p_user_id,target_plan,p_status,'google_play',p_product_id,p_token,p_started_at,p_valid_until,p_auto_renews,now(),now())
 on conflict(user_id) do update set plan_code=excluded.plan_code,status=excluded.status,source=excluded.source,
 product_id=excluded.product_id,purchase_token=excluded.purchase_token,started_at=excluded.started_at,
 valid_until=excluded.valid_until,auto_renews=excluded.auto_renews,last_verified_at=now(),updated_at=now();
 insert into public.member_billing_state values(p_user_id,p_token_hash,p_serial)
 on conflict(user_id) do update set token_hash=excluded.token_hash,applied_serial=excluded.applied_serial;
 if changed then
  insert into public.membership_events(user_id,event_type,from_plan,to_plan,source,metadata)
  values(p_user_id,'google_play_verified',coalesce(previous.plan_code,'free'),target_plan,'google_play',
   jsonb_build_object('product_id',p_product_id,'base_plan_id',p_base_plan_id,'status',p_status));
 end if;
 return true;
end;$$;
revoke all on function public.apply_verified_membership(uuid,text,text,text,bigint,text,text,text,text,timestamptz,timestamptz,boolean) from public,anon,authenticated;
grant execute on function public.apply_verified_membership(uuid,text,text,text,bigint,text,text,text,text,timestamptz,timestamptz,boolean) to service_role;
