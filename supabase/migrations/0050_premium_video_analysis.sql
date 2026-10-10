-- Video analysis is a monthly-premium-only, separately bounded AI operation.
alter table public.ai_usage_reservations
 add column video_analysis boolean not null default false,
 add column video_provider_started boolean not null default false,
 add column video_seconds integer check (video_seconds between 1 and 1200),
 add column video_usage_metadata jsonb;

create function public.begin_ai_video_usage(p_user_id uuid)
returns table(reservation_id uuid,plan_code text,recipe_model text)
language plpgsql security definer set search_path='' as $$
declare r record;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
 if p_user_id is null then raise exception 'INVALID_AI_USAGE_REQUEST'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_user_id::text,0));
 if not exists(select 1 from public.member_entitlements e join public.membership_plans p on p.code=e.plan_code
  where e.user_id=p_user_id and e.plan_code='paid_monthly' and p.is_active
  and e.status in ('active','grace_period','canceled') and (e.valid_until is null or e.valid_until>now()))
 then raise exception 'MONTHLY_PREMIUM_REQUIRED'; end if;
 if (select count(*) from public.ai_usage_reservations a where a.user_id=p_user_id and a.video_analysis
  and a.created_at >= date_trunc('month',now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'
  and (a.video_provider_started or (a.status='reserved' and a.created_at>now()-interval '5 minutes'))) >= 20
 then raise exception 'VIDEO_QUOTA_MONTHLY'; end if;
 select * into r from public.begin_ai_recipe_usage(p_user_id,'ai_youtube_recipe_assistant');
 update public.ai_usage_reservations set video_analysis=true where id=r.reservation_id;
 return query select r.reservation_id::uuid,r.plan_code::text,r.recipe_model::text;
end;$$;
revoke all on function public.begin_ai_video_usage(uuid) from public,anon,authenticated;
grant execute on function public.begin_ai_video_usage(uuid) to service_role;

create function public.start_ai_video_provider(p_user_id uuid,p_reservation_id uuid,p_seconds integer)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
 if p_seconds is null or p_seconds not between 1 and 1200 then raise exception 'VIDEO_TOO_LONG'; end if;
 update public.ai_usage_reservations set video_provider_started=true,video_seconds=p_seconds
 where id=p_reservation_id and user_id=p_user_id and video_analysis and status='reserved' and not video_provider_started;
 return found;
end;$$;
revoke all on function public.start_ai_video_provider(uuid,uuid,integer) from public,anon,authenticated;
grant execute on function public.start_ai_video_provider(uuid,uuid,integer) to service_role;

create function public.get_my_video_analysis_usage()
returns table(monthly_limit integer,monthly_used integer)
language sql stable security definer set search_path='' as $$
 select 20,count(*)::integer from public.ai_usage_reservations a
 where a.user_id=auth.uid() and a.video_analysis and a.video_provider_started
 and a.created_at >= date_trunc('month',now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
$$;
revoke all on function public.get_my_video_analysis_usage() from public,anon;
grant execute on function public.get_my_video_analysis_usage() to authenticated;
