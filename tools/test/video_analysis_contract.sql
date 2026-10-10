reset role;
select set_config('request.jwt.claims','{"sub":"59a00000-0000-4000-8000-000000000001","role":"service_role"}',true);
do $$
declare uid uuid:='59a00000-0000-4000-8000-000000000001';r record;p text;
begin
 foreach p in array array['free','paid_annual'] loop
  update public.member_entitlements set plan_code=p,status='active',valid_until=now()+interval '1 day' where user_id=uid;
  begin perform public.begin_ai_video_usage(uid);raise exception 'NON_MONTHLY_ALLOWED';
  exception when raise_exception then if sqlerrm<>'MONTHLY_PREMIUM_REQUIRED' then raise;end if;end;
 end loop;
 update public.member_entitlements set plan_code='paid_monthly',valid_until=now()-interval '1 second' where user_id=uid;
 begin perform public.begin_ai_video_usage(uid);raise exception 'EXPIRED_ALLOWED';
 exception when raise_exception then if sqlerrm<>'MONTHLY_PREMIUM_REQUIRED' then raise;end if;end;
 update public.member_entitlements set status='active',valid_until=now()+interval '1 day' where user_id=uid;
 select * into r from public.begin_ai_video_usage(uid);
 if r.plan_code<>'paid_monthly' then raise exception 'WRONG_PLAN';end if;
 begin perform public.begin_ai_video_usage(uid);raise exception 'DOUBLE_RESERVATION';
 exception when raise_exception then if sqlerrm<>'AI_IN_FLIGHT' then raise;end if;end;
 begin perform public.start_ai_video_provider(uid,r.reservation_id,1201);raise exception 'LONG_VIDEO';
 exception when raise_exception then if sqlerrm<>'VIDEO_TOO_LONG' then raise;end if;end;
 if not public.start_ai_video_provider(uid,r.reservation_id,1200) then raise exception 'START_FAILED';end if;
 if public.start_ai_video_provider(uid,r.reservation_id,1200) then raise exception 'DUPLICATE_PROVIDER';end if;
 perform public.finish_ai_recipe_usage(uid,r.reservation_id,false,'gemini-2.5-flash',1000,100);
 -- Provider work can cost money even if the final draft is incomplete.
 insert into public.ai_usage_reservations(user_id,endpoint,plan_code,status,video_analysis,video_provider_started,created_at)
 select uid,'ai_youtube_recipe_assistant','paid_monthly','failed',true,true,now()-interval '11 minutes' from generate_series(1,19);
 begin perform public.begin_ai_video_usage(uid);raise exception 'MONTHLY_CAP_BYPASSED';
 exception when raise_exception then if sqlerrm<>'VIDEO_QUOTA_MONTHLY' then raise;end if;end;
 if has_function_privilege('authenticated','public.begin_ai_video_usage(uuid)','execute') or
 has_function_privilege('anon','public.start_ai_video_provider(uuid,uuid,integer)','execute') then raise exception 'PUBLIC_QUOTA_BYPASS';end if;
end;$$;
select set_config('request.jwt.claims','{"sub":"59a00000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 if (select monthly_used from public.get_my_video_analysis_usage())<>20 then raise exception 'USAGE_COUNT_MISMATCH';end if;
 if has_table_privilege('authenticated','public.ai_usage_reservations','select') then raise exception 'RAW_USAGE_EXPOSED';end if;
end;$$;
reset role;
select 'VIDEO_ANALYSIS_CONTRACT_PASSED' as result;
