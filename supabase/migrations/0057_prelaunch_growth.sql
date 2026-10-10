-- Consent-based prelaunch intake. All delivery is OFF until configured/approved.
create table public.growth_controls (
 id boolean primary key default true check(id),
 intake_enabled boolean not null default false,
 delivery_enabled boolean not null default false,
 daily_send_limit integer not null default 90 check(daily_send_limit between 0 and 1000),
 monthly_send_limit integer not null default 2500 check(monthly_send_limit between 0 and 30000)
);
insert into public.growth_controls(id) values(true);
create table public.growth_leads (
 id uuid primary key default gen_random_uuid(),
 email text check(email is null or (length(email) between 3 and 254 and email=lower(btrim(email)))),
 email_key text unique not null check(email_key ~ '^[a-f0-9]{64}$'),
 role_code text not null check(role_code in ('chef','owner','catering','home')),
 interest text not null check(interest in ('costs','scaling','purchasing','video')),
 locale text not null check(locale in ('ko','en')),
 newsletter boolean not null,
 consent_version text not null check(consent_version='pro-2026-09-v1'),
 source text not null check(source in ('direct','youtube','kakao','partner','other')),
 campaign text not null check(campaign ~ '^[a-z0-9_-]{0,48}$'),
 state text not null default 'pending' check(state in ('pending','confirmed','withdrawn')),
 token_version uuid not null default gen_random_uuid(),
 created_at timestamptz not null default now(),
 confirmed_at timestamptz,
 withdrawn_at timestamptz,
 expires_at timestamptz not null default now()+interval '180 days',
 check((state='withdrawn' and email is null) or (state<>'withdrawn' and email is not null))
);
create index growth_leads_created_idx on public.growth_leads(created_at desc);
create table public.growth_jobs (
 id uuid primary key default gen_random_uuid(),
 lead_id uuid not null references public.growth_leads(id) on delete cascade,
 kind text not null check(kind in ('confirm','welcome','tip')),
 state text not null default 'pending' check(state in ('pending','leased','sent','failed','cancelled')),
 due_at timestamptz not null default now(),
 created_at timestamptz not null default now(),
 attempts integer not null default 0,
 first_attempt_at timestamptz,
 lease_until timestamptz,
 lease_id uuid,
 sent_at timestamptz,
 error_code text check(error_code in ('timeout','provider','configuration','unknown')),
 unique(lead_id,kind)
);
create index growth_jobs_due_idx on public.growth_jobs(due_at) where state in ('pending','leased');
create table public.growth_send_budget(day date primary key, attempts integer not null default 0 check(attempts>=0));
create table public.growth_intake_budget(hour timestamptz primary key, attempts integer not null default 0 check(attempts>=0));

do $$ declare t text; begin
 foreach t in array array['growth_controls','growth_leads','growth_jobs','growth_send_budget','growth_intake_budget'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select,insert,update,delete on public.%I to service_role',t);
 end loop;
end;$$;

create function public.growth_assert_service() returns void
language plpgsql security definer set search_path='' as $$ begin
 if auth.role() is distinct from 'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
end;$$;

create function public.growth_register(p_email text,p_email_key text,p_role text,p_interest text,p_locale text,
 p_newsletter boolean,p_source text,p_campaign text) returns void
language plpgsql security definer set search_path='' as $$
declare lead uuid; n integer;
begin
 perform public.growth_assert_service();
 if not (select intake_enabled from public.growth_controls where id) then raise exception 'GROWTH_PAUSED'; end if;
 if p_email is null or p_email_key is null or p_newsletter is null then raise exception 'INVALID_REQUEST'; end if;
 perform pg_advisory_xact_lock(hashtextextended('growth-intake',0));
 -- Count all valid CAPTCHA attempts, including duplicates, without storing IPs.
 select attempts into n from public.growth_intake_budget where hour=date_trunc('hour',now());
 if coalesce(n,0)>=100 or (select coalesce(sum(attempts),0) from public.growth_intake_budget where hour>=now()-interval '24 hours')>=500
  or (select count(*) from public.growth_leads)>=10000 then raise exception 'GROWTH_CAPACITY'; end if;
 insert into public.growth_intake_budget values(date_trunc('hour',now()),1)
 on conflict(hour) do update set attempts=public.growth_intake_budget.attempts+1;
 insert into public.growth_leads(email,email_key,role_code,interest,locale,newsletter,consent_version,source,campaign)
 values(p_email,p_email_key,p_role,p_interest,p_locale,p_newsletter,'pro-2026-09-v1',p_source,p_campaign)
 on conflict(email_key) do nothing returning id into lead;
 -- Re-submission never changes consent, resets a token or sends duplicate mail.
 if lead is not null then insert into public.growth_jobs(lead_id,kind) values(lead,'confirm'); end if;
end;$$;

create function public.growth_confirm(p_id uuid,p_version uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare lead public.growth_leads;
begin
 perform public.growth_assert_service();
 select * into lead from public.growth_leads where id=p_id and token_version=p_version for update;
 if not found or lead.state='withdrawn' or lead.expires_at<=now() or lead.created_at<now()-interval '7 days' then return false; end if;
 if lead.state='confirmed' then return true; end if;
 update public.growth_leads set state='confirmed',confirmed_at=now() where id=p_id;
 insert into public.growth_jobs(lead_id,kind) values(p_id,'welcome') on conflict do nothing;
 if lead.newsletter then
  insert into public.growth_jobs(lead_id,kind,due_at) values(p_id,'tip',now()+interval '3 days') on conflict do nothing;
 end if;
 update public.growth_jobs set state='cancelled' where lead_id=p_id and kind='confirm' and state in ('pending','leased');
 return true;
end;$$;

create function public.growth_withdraw(p_id uuid,p_version uuid) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 perform public.growth_assert_service();
 update public.growth_leads set state='withdrawn',email=null,newsletter=false,withdrawn_at=coalesce(withdrawn_at,now()),
  expires_at=least(expires_at,now()+interval '30 days') where id=p_id and token_version=p_version;
 if not found then return false; end if;
 update public.growth_jobs set state='cancelled' where lead_id=p_id and state in ('pending','leased','failed');
 return true;
end;$$;

create function public.growth_maintain() returns void
language plpgsql security definer set search_path='' as $$ begin
 perform public.growth_assert_service();
 delete from public.growth_leads where expires_at<=now() or (state='pending' and created_at<now()-interval '7 days');
 delete from public.growth_intake_budget where hour<now()-interval '2 days';
 delete from public.growth_send_budget where day<current_date-62;
 update public.growth_jobs set state='failed',error_code='timeout' where state in ('pending','leased')
  and (lease_until is null or lease_until<now()) and first_attempt_at<now()-interval '20 hours';
end;$$;

create function public.growth_claim_job() returns jsonb
language plpgsql security definer set search_path='' as $$
declare job public.growth_jobs; lead public.growth_leads; cfg public.growth_controls; lease uuid:=gen_random_uuid(); today date:=(now() at time zone 'UTC')::date;
begin
 perform public.growth_assert_service();
 perform pg_advisory_xact_lock(hashtextextended('growth-mail-budget',0));
 select * into cfg from public.growth_controls where id;
 if not cfg.delivery_enabled then return null; end if;
 if (select coalesce(sum(attempts),0) from public.growth_send_budget where day=today)>=cfg.daily_send_limit
  or (select coalesce(sum(attempts),0) from public.growth_send_budget where day>=date_trunc('month',today)::date)>=cfg.monthly_send_limit then return null; end if;
 select j.* into job from public.growth_jobs j join public.growth_leads l on l.id=j.lead_id
 where ((j.state='pending' and j.due_at<=now()) or (j.state='leased' and j.lease_until<now()))
  and j.attempts<5 and (j.first_attempt_at is null or j.first_attempt_at>now()-interval '20 hours')
  and l.expires_at>now() and l.email is not null
  and ((j.kind='confirm' and l.state='pending' and l.created_at>now()-interval '7 days')
    or (j.kind in ('welcome','tip') and l.state='confirmed' and (j.kind<>'tip' or l.newsletter)))
 order by j.due_at,j.id for update of j skip locked limit 1;
 if not found then return null; end if;
 select * into lead from public.growth_leads where id=job.lead_id;
 update public.growth_jobs set state='leased',attempts=attempts+1,lease_id=lease,lease_until=now()+interval '5 minutes',first_attempt_at=coalesce(first_attempt_at,now()) where id=job.id;
 insert into public.growth_send_budget values(today,1) on conflict(day) do update set attempts=public.growth_send_budget.attempts+1;
 return jsonb_build_object('id',job.id,'lease_id',lease,'lead_id',lead.id,'version',lead.token_version,'email',lead.email,
  'kind',job.kind,'locale',lead.locale,'created_at',lead.created_at,'expires_at',lead.expires_at,'newsletter',lead.newsletter);
end;$$;

create function public.growth_job_deliverable(p_id uuid,p_lease uuid) returns boolean
language plpgsql stable security definer set search_path='' as $$ begin
 perform public.growth_assert_service();
 return exists(select 1 from public.growth_jobs j join public.growth_leads l on l.id=j.lead_id
 where j.id=p_id and j.lease_id=p_lease and j.state='leased' and j.lease_until>now()
 and l.email is not null and l.state<>'withdrawn' and l.expires_at>now()
 and (j.kind<>'tip' or l.newsletter) and (select delivery_enabled from public.growth_controls where id));
end;$$;

create function public.growth_finish_job(p_id uuid,p_lease uuid,p_sent boolean,p_code text) returns boolean
language plpgsql security definer set search_path='' as $$ begin
 perform public.growth_assert_service();
 if p_sent is null or p_code not in ('timeout','provider','configuration','unknown') then raise exception 'INVALID_RESULT'; end if;
 update public.growth_jobs set state=case when p_sent then 'sent' when attempts>=5 then 'failed' else 'pending' end,
  sent_at=case when p_sent then now() else null end,error_code=case when p_sent then null else p_code end,
  due_at=now()+interval '5 minutes'*greatest(attempts,1),lease_until=null
 where id=p_id and lease_id=p_lease and state='leased';
 return found;
end;$$;

create function public.admin_growth_overview() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 perform public.assert_ops_admin();
 select jsonb_build_object('schema_version',1,'intake_enabled',c.intake_enabled,'delivery_enabled',c.delivery_enabled,
 'daily_limit',c.daily_send_limit,'monthly_limit',c.monthly_send_limit,
 'pending',(select count(*) from public.growth_leads where state='pending'),
 'confirmed',(select count(*) from public.growth_leads where state='confirmed'),
 'withdrawn',(select count(*) from public.growth_leads where state='withdrawn'),
 'confirmed_7d',(select count(*) from public.growth_leads where state='confirmed' and confirmed_at>=now()-interval '7 days'),
 'queued',(select count(*) from public.growth_jobs where state in ('pending','leased')),
 'failed',(select count(*) from public.growth_jobs where state='failed'),
 'sent',(select count(*) from public.growth_jobs where state='sent'),
 'attempts_today',(select coalesce(sum(attempts),0) from public.growth_send_budget where day=(now() at time zone 'UTC')::date),
 'channels',coalesce((select jsonb_agg(r) from (select source,count(*) filter(where state<>'withdrawn') as applications,count(*) filter(where state='confirmed') as confirmed from public.growth_leads group by source order by source) r),'[]'::jsonb),
 'roles',coalesce((select jsonb_agg(r) from (select role_code,count(*) as confirmed from public.growth_leads where state='confirmed' group by role_code order by role_code) r),'[]'::jsonb))
 into result from public.growth_controls c where id;
 return result;
end;$$;

do $$ declare f record; begin
 for f in select oid::regprocedure as signature from pg_proc where pronamespace='public'::regnamespace and proname like 'growth\_%' escape '\' loop
  execute format('revoke all on function %s from public,anon,authenticated',f.signature);
  execute format('grant execute on function %s to service_role',f.signature);
 end loop;
end;$$;
revoke all on function public.admin_growth_overview() from public,anon;
grant execute on function public.admin_growth_overview() to authenticated;
