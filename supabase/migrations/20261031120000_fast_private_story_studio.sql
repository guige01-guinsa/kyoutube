-- Opt-in single-run recipe render/private upload; preserve every legacy gate.
begin;
set local lock_timeout='5s';
lock table public.story_jobs in share row exclusive mode;
do $$ begin
 if exists(select 1 from public.story_jobs where status in ('queued','running')) then raise exception 'STORY_WAIT_FOR_IDLE_QUEUE'; end if;
end $$;
alter table public.story_studio_config add column fast_recipe_enabled boolean not null default false;
alter table public.story_jobs add column pipeline_parent_id uuid unique references public.story_jobs(id);

-- The deepest existing lease implementation retains its checks and grants.
do $$ declare body text; needle text='select * into j from public.story_jobs where status=''queued'' order by created_at for update skip locked limit 1;';
begin
 select pg_get_functiondef('public.story_studio_work_before_standard(text,jsonb)'::regprocedure) into body;
 if (length(body)-length(replace(body,needle,'')))/length(needle)<>1 then raise exception 'STORY_UNEXPECTED_CLAIM_RULE'; end if;
 execute replace(body,needle,'select * into j from public.story_jobs where status=''queued'' and (nullif(p->>''job_id'','''') is null or id=(p->>''job_id'')::uuid) order by created_at for update skip locked limit 1;');
end $$;

alter function public.story_standard(text,jsonb) rename to story_standard_before_fast;
revoke all on function public.story_standard_before_fast(text,jsonb) from public,anon,authenticated,service_role;
create function public.story_standard(p_action text,p jsonb default '{}') returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare c public.story_studio_config; out jsonb; j public.story_jobs;
begin
 if p_action<>'fast_recipe' then return public.story_standard_before_fast(p_action,p); end if;
 perform public.assert_marketing_access();
 select * into c from public.story_studio_config where singleton for update;
 if not c.fast_recipe_enabled then raise exception 'STORY_FAST_NOT_READY'; end if;
 if p->>'private_upload_confirmed' is distinct from 'true' then raise exception 'STORY_PRIVATE_UPLOAD_CONFIRMATION_REQUIRED'; end if;
 -- Check two job slots up front; recheck the free upload slot at completion.
 if not exists(select 1 from public.story_jobs where id=(p->>'id')::uuid)
  and (select count(*) from public.story_jobs where created_at>now()-interval '1 day')+2>c.daily_jobs then raise exception 'STORY_BUDGET_LIMIT'; end if;
 out=public.story_standard_before_fast('render_recipe',p||jsonb_build_object('auto_private_upload',true,'pipeline_target_ms',180000));
 select * into j from public.story_jobs where id=(out->>'id')::uuid;
 update public.story_standard_projects set source_receipt=coalesce(source_receipt,'{}'::jsonb)||jsonb_build_object('pipeline_started_at',j.created_at)
  where id=(j.snapshot->>'standard_project_id')::uuid;
 return out;
end $$;
revoke all on function public.story_standard(text,jsonb) from public,anon;
grant execute on function public.story_standard(text,jsonb) to authenticated;

alter function public.story_studio_work(text,jsonb) rename to story_studio_work_before_fast;
revoke all on function public.story_studio_work_before_fast(text,jsonb) from public,anon,authenticated,service_role;
create function public.story_studio_work(p_action text,p jsonb default '{}') returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare
 j public.story_jobs; root public.story_jobs; child public.story_jobs;
 x public.story_standard_projects; s public.story_series; c public.story_studio_config;
 out jsonb; metrics jsonb; request jsonb; jid uuid; elapsed bigint; finished timestamptz; reason text;
begin
 if p_action='check' then
  select * into j from public.story_jobs where id=(p->>'id')::uuid;
  if (j.request->>'auto_private_upload'='true' or j.pipeline_parent_id is not null)
    and not exists(select 1 from public.story_studio_config where singleton and fast_recipe_enabled) then raise exception 'STORY_FAST_NOT_READY'; end if;
 end if;
 if p_action='complete' then
  select * into j from public.story_jobs where id=(p->>'id')::uuid;
  -- Lock config before job/project to match the existing reservation lock order.
  if j.request->>'auto_private_upload'='true' or j.pipeline_parent_id is not null then
   perform 1 from public.story_studio_config where singleton for update;
  end if;
 end if;
 out=public.story_studio_work_before_fast(p_action,p);
 if p_action<>'complete' then return out; end if;
 select * into j from public.story_jobs where id=(p->>'id')::uuid;
 if j.snapshot->>'standard_profile' is distinct from 'ko-60-v1' then return out; end if;
 select * into x from public.story_standard_projects where id=(j.snapshot->>'standard_project_id')::uuid;
 if j.snapshot->>'standard_stage'='render' and j.request->>'auto_private_upload'='true' then
  select * into c from public.story_studio_config where singleton;
  if j.request->>'private_upload_confirmed' is distinct from 'true' or j.request->>'voice_use_confirmed' is distinct from 'true'
   or j.request->>'sources_reviewed' is distinct from 'true' then raise exception 'STORY_PRIVATE_UPLOAD_CONFIRMATION_REQUIRED'; end if;
  if x.plan->>'profile' is distinct from 'ko-180-source-v1' or not public.story_standard_plan_valid(x.plan)
   or x.status is distinct from 'preview' or x.preview->>'sha256' is distinct from j.result->>'sha256'
   or x.preview->>'voice_profile' is distinct from 'fictional-girl-8-ko-v1'
   or x.preview->'visuals'->>'profile' is distinct from 'recipe-sketch-v2'
   or x.preview->'visuals'->>'verified_frames' is distinct from jsonb_array_length(x.plan->'scenes')::text
   or x.preview->'visuals'->>'scene_count' is distinct from jsonb_array_length(x.plan->'scenes')::text
   or not coalesce((x.preview->'visuals'->>'min_ink_fraction')::numeric between .003 and .4,false)
   then raise exception 'STORY_VISUAL_REVIEW_REQUIRED'; end if;
  if not coalesce((x.preview->>'seconds')::numeric>0 and (x.preview->>'seconds')::numeric<180,false) then reason='duration_review_required';
  elsif not c.fast_recipe_enabled or not c.enabled or not c.standard_enabled then reason='paused';
  elsif not exists(select 1 from public.marketing_admins where user_id=j.created_by) then reason='administrator_required';
  elsif (select count(*) from public.story_jobs where created_at>now()-interval '1 day')>=c.daily_jobs
    or (select coalesce(sum(reserved_usd),0) from public.story_jobs where created_at>now()-interval '1 day')>c.daily_usd then reason='upload_budget_review_required';
  elsif (select coalesce(sum(reserved_krw),0) from public.story_jobs where date_trunc('month',created_at at time zone 'Asia/Seoul')=date_trunc('month',now() at time zone 'Asia/Seoul'))+c.fixed_krw+c.buffer_krw>c.monthly_krw then reason='upload_budget_review_required';
  end if;
  metrics=jsonb_build_object('pipeline_started_at',j.created_at,'target_ms',180000,'target_met',null,'timing_scope','approved_request_to_private_upload',
   'pipeline_state',coalesce(reason,'upload_queued'));
  update public.story_jobs set result=result||metrics where id=j.id;
  update public.story_standard_projects set preview=preview||metrics where id=x.id;
  if reason is not null then return out||jsonb_build_object('pipeline_state',reason); end if;
  if exists(select 1 from public.story_jobs where kind='upload' and snapshot->>'standard_project_id'=x.id::text) then raise exception 'STORY_PRIOR_UPLOAD_REQUIRES_REVIEW'; end if;
  jid=gen_random_uuid();
  select * into s from public.story_series where id=x.series_id;
  select * into x from public.story_standard_projects where id=x.id;
  request=jsonb_build_object('id',jid,'project_id',x.id,'revision',x.revision,'quote_revision',c.revision,'cost_confirmed',true,
   'automatic_private_approval',true,'private_upload_confirmed',true,'sha256',x.preview->>'sha256',
   'pipeline_parent_id',j.id,'pipeline_target_ms',180000);
  insert into public.story_jobs(id,series_id,kind,snapshot,request,reserved_usd,reserved_krw,created_by,pipeline_parent_id)
   values(jid,x.series_id,'upload',jsonb_build_object('standard_profile','ko-60-v1','standard_stage','upload','standard_project_id',x.id,
    'project',to_jsonb(x),'series',to_jsonb(s),'text_model',c.text_model,'image_model',c.image_model),request,0,0,j.created_by,j.id);
  update public.story_standard_projects set status='upload_queued',revision=revision+1 where id=x.id;
  return out||jsonb_build_object('next_job_id',jid);
 elsif j.snapshot->>'standard_stage'='upload' and j.pipeline_parent_id is not null then
  select * into root from public.story_jobs where id=j.pipeline_parent_id;
  if j.result->>'privacy' is distinct from 'private' or root.request->>'auto_private_upload' is distinct from 'true'
   or j.request->>'private_upload_confirmed' is distinct from 'true' then raise exception 'STORY_PRIVATE_UPLOAD_CONFIRMATION_REQUIRED'; end if;
  finished=clock_timestamp();elapsed=greatest(0,floor(extract(epoch from finished-root.created_at)*1000))::bigint;
  metrics=jsonb_build_object('pipeline_started_at',root.created_at,'pipeline_completed_at',finished,'end_to_end_ms',elapsed,
   'target_ms',180000,'target_met',elapsed<=180000,'timing_scope','approved_request_to_private_upload','pipeline_state','uploaded');
  update public.story_jobs set result=result||metrics where id=j.id;
  update public.story_standard_projects set preview=preview||metrics where id=x.id;
 end if;
 return out;
end $$;
revoke all on function public.story_studio_work(text,jsonb) from public,anon,authenticated;
grant execute on function public.story_studio_work(text,jsonb) to service_role;
commit;
