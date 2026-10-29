-- Source-first, opt-in recipe profile; no budget, key, job or asset changes.
begin;
set local lock_timeout='5s';
lock table public.story_jobs in share row exclusive mode;
do $$ begin
 if exists(select 1 from public.story_jobs where status in ('queued','running')) then
  raise exception 'STORY_WAIT_FOR_IDLE_QUEUE'; end if;
end $$;

alter table public.story_standard_projects add column source_video_url text
 check(source_video_url ~ '^https://www[.]youtube[.]com/watch[?]v=[A-Za-z0-9_-]{11}$');
alter table public.story_standard_projects add column source_receipt jsonb;
create table public.story_recipe_sources(
 video_id text primary key check(video_id ~ '^[A-Za-z0-9_-]{11}$'),
 source jsonb not null check(jsonb_typeof(source)='object' and octet_length(source::text)<=60000),
 fetched_at timestamptz not null default now()
);
alter table public.story_recipe_sources enable row level security;
revoke all on public.story_recipe_sources from public,anon,authenticated;
grant all on public.story_recipe_sources to service_role;

create function public.story_recipe_plan(food text,presenter text,r jsonb,intro text,outro text) returns jsonb
language plpgsql immutable set search_path=public,pg_temp as $$
declare scenes jsonb; items text[]; steps text[]; line text; i int; src jsonb;
begin
 if jsonb_typeof(r) is distinct from 'object' then raise exception 'STORY_INVALID'; end if;
 if (select count(*) from jsonb_object_keys(r))<>6 or not coalesce(
  r->>'url' ~ '^https://www[.]youtube[.]com/watch[?]v=[A-Za-z0-9_-]{11}$'
  and char_length(food) between 1 and 30 and char_length(presenter) between 1 and 500
  and char_length(intro) between 1 and 50 and char_length(outro) between 1 and 80
  and char_length(r->>'title') between 1 and 150 and char_length(r->>'channel') between 1 and 80
  and char_length(r->>'servings') between 1 and 60,false)
  or jsonb_typeof(r->'ingredients') is distinct from 'array' or jsonb_typeof(r->'steps') is distinct from 'array'
  then raise exception 'STORY_INVALID'; end if;
 if exists(select 1 from jsonb_each(r) where key not in ('ingredients','steps') and
  (jsonb_typeof(value)<>'string' or value#>>'{}'<>btrim(value#>>'{}') or value#>>'{}' ~ '[[:cntrl:]]'))
  or intro<>btrim(intro) or outro<>btrim(outro) or (food||presenter||intro||outro) ~ '[[:cntrl:]]'
  or jsonb_array_length(r->'ingredients') not between 2 and 24 or jsonb_array_length(r->'steps') not between 1 and 12
  then raise exception 'STORY_INVALID'; end if;
 if exists(select 1 from jsonb_array_elements(r->'ingredients') where jsonb_typeof(value)<>'string'
  or char_length(value#>>'{}') not between 1 and 100 or value#>>'{}'<>btrim(value#>>'{}') or value#>>'{}' ~ '[[:cntrl:]]')
  or exists(select 1 from jsonb_array_elements(r->'steps') where jsonb_typeof(value)<>'string'
  or char_length(value#>>'{}') not between 1 and 160 or value#>>'{}'<>btrim(value#>>'{}') or value#>>'{}' ~ '[[:cntrl:]]')
  then raise exception 'STORY_INVALID'; end if;
 select array_agg(value order by n) into items from jsonb_array_elements_text(r->'ingredients') with ordinality as t(value,n);
 select array_agg(value order by n) into steps from jsonb_array_elements_text(r->'steps') with ordinality as t(value,n);
 scenes=jsonb_build_array(jsonb_build_object('role','greeting','spoken',intro,'caption','원본 영상 레시피 · '||(r->>'servings'),'visual','source_recipe_card','source_ids',jsonb_build_array('original-video')));
 for i in 1..array_length(items,1) by 3 loop
  scenes=scenes||jsonb_build_array(jsonb_build_object('role','ingredients','spoken',array_to_string(items[i:i+2],'. ')||'.','caption',array_to_string(items[i:i+2],' / '),'visual','source_recipe_card','source_ids',jsonb_build_array('original-video')));
 end loop;
 for i in 1..array_length(steps,1) loop
  scenes=scenes||jsonb_build_array(jsonb_build_object('role','cooking','spoken',steps[i],'caption',i||'. '||steps[i],'visual','source_recipe_card','source_ids',jsonb_build_array('original-video')));
 end loop;
 scenes=scenes||jsonb_build_array(
  jsonb_build_object('role','source','spoken',(r->>'channel')||'의 원본 영상을 함께 확인해 주세요.','caption',(r->>'title')||' / '||(r->>'url'),'visual','source_recipe_card','source_ids',jsonb_build_array('original-video')),
  jsonb_build_object('role','closing','spoken',outro,'caption','레시피 스카우트 · 원본과 대조한 레시피','visual','source_recipe_card','source_ids',jsonb_build_array('original-video')));
 if jsonb_array_length(scenes)>20 or exists(select 1 from jsonb_array_elements(scenes) where char_length(value->>'spoken')>180) then raise exception 'STORY_INVALID'; end if;
 src=jsonb_build_array(jsonb_build_object('id','original-video','title',r->>'title','url',r->>'url','note','관리자가 원본의 재료·분량·단위·선택 사항·조리 순서를 직접 대조한 뒤 제작합니다.'));
 return jsonb_build_object('profile','ko-180-source-v1','language','ko','food',food,'title',food||' · 원본 레시피','presenter',presenter,'sources',src,'recipe',r,'scenes',scenes);
end $$;
revoke all on function public.story_recipe_plan(text,text,jsonb,text,text) from public,anon,authenticated;
grant execute on function public.story_recipe_plan(text,text,jsonb,text,text) to service_role;

alter function public.story_standard_plan_valid(jsonb) rename to story_standard_plan_valid_v1;
create function public.story_standard_plan_valid(v jsonb) returns boolean
language plpgsql immutable set search_path=public,pg_temp as $$
begin
 if v->>'profile'='ko-180-source-v1' then
  return v=public.story_recipe_plan(v->>'food',v->>'presenter',v->'recipe',v->'scenes'->0->>'spoken',v->'scenes'->-1->>'spoken');
 end if;
 return public.story_standard_plan_valid_v1(v);
exception when others then return false;
end $$;
revoke all on function public.story_standard_plan_valid(jsonb) from public,anon,authenticated;
grant execute on function public.story_standard_plan_valid(jsonb) to service_role;

alter function public.story_standard(text,jsonb) rename to story_standard_before_recipe;
revoke all on function public.story_standard_before_recipe(text,jsonb) from public,anon,authenticated;
create function public.story_standard(p_action text,p jsonb default '{}') returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare plan jsonb; x public.story_standard_projects; existing public.story_jobs; request jsonb;
begin
 perform public.assert_marketing_access();
 if p_action not in ('create_source','import_recipe','update_recipe','render_recipe') then return public.story_standard_before_recipe(p_action,p); end if;
 perform 1 from public.story_studio_config where singleton for update;
 if p_action='render_recipe' then
  request=p||jsonb_build_object('revision',(p->>'revision')::bigint+1);
  select * into existing from public.story_jobs where id=(p->>'id')::uuid;
  if found then
   if existing.request=request and existing.snapshot->>'standard_stage'='render' then return jsonb_build_object('id',existing.id); end if;
   raise exception 'STORY_CONFLICT';
  end if;
  select * into x from public.story_standard_projects where id=(p->>'project_id')::uuid for update;
  if not found or x.revision is distinct from (p->>'revision')::bigint or x.status<>'draft'
   or x.plan->>'profile' is distinct from 'ko-180-source-v1' then raise exception 'STORY_CONFLICT'; end if;
  if p->>'voice_use_confirmed' is distinct from 'true' or p->>'sources_reviewed' is distinct from 'true' then raise exception 'STORY_SOURCES_REQUIRED'; end if;
  -- Explicit permission to use the configured voice; NOT a claim of listening.
  -- Existing render RPC still enforces quote, cost consent, quota, lease and idempotency.
  update public.story_standard_projects set status='sample_approved',revision=revision+1,
   sample_approved_by=auth.uid(),sample_approved_at=now(),
   sample=jsonb_build_object('review_mode','existing_voice_without_sample','listened',false)
   where id=x.id;
  return public.story_standard_before_recipe('render',request);
 end if;
 if p_action='create_source' then
  if not coalesce(p->>'source_url' ~ '^https://www[.]youtube[.]com/watch[?]v=[A-Za-z0-9_-]{11}$',false) then raise exception 'STORY_INVALID'; end if;
  perform public.story_standard_before_recipe('create',p);
  select * into x from public.story_standard_projects where id=(p->>'id')::uuid for update;
  if x.source_video_url is not null then
   if x.source_video_url=p->>'source_url' then return to_jsonb(x); end if;
   raise exception 'STORY_CONFLICT';
  end if;
  if x.plan is not null then raise exception 'STORY_CONFLICT'; end if;
  update public.story_standard_projects set source_video_url=p->>'source_url' where id=x.id returning * into x;
  return to_jsonb(x);
 end if;
 if p->>'source_verified' is distinct from 'true' then raise exception 'STORY_SOURCES_REQUIRED'; end if;
 plan=public.story_recipe_plan(p->>'food',p->>'presenter',p->'recipe',p->>'intro',p->>'outro');
 if p_action='update_recipe' then
  return public.story_standard_before_recipe('save_plan',jsonb_build_object('project_id',p->>'project_id','revision',p->'revision','plan',plan));
 end if;
 perform public.story_standard_before_recipe('create',p);
 select * into x from public.story_standard_projects where id=(p->>'id')::uuid for update;
 if x.plan is not null then
  if x.plan=plan then return to_jsonb(x); end if;
  raise exception 'STORY_CONFLICT';
 end if;
 perform public.story_standard_before_recipe('save_plan',jsonb_build_object('project_id',x.id,'revision',x.revision,'plan',plan));
 return jsonb_build_object('id',x.id);
end $$;
revoke all on function public.story_standard(text,jsonb) from public,anon;
grant execute on function public.story_standard(text,jsonb) to authenticated;

-- Existing authorization, lease and completion behavior preserved.
create or replace function public.story_studio_work(p_action text,p jsonb default '{}') returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare j public.story_jobs; x public.story_standard_projects; v jsonb; out jsonb; stage text;
begin
 if p_action='heartbeat' then
  if p->>'standard_profile'='ko-60-v1' then
   update public.story_studio_config set standard_worker_seen_at=now(),standard_capture_ready=coalesce(p->>'standard_capture_ready'='true',false) where singleton and text_model=p->>'text_model' and image_model=p->>'image_model';
  end if;
  return public.story_studio_work_before_standard(p_action,p);
 end if;
 if p_action='claim' then
  out=public.story_studio_work_before_standard(p_action,p);
  if out->'snapshot'->>'standard_profile'='ko-60-v1' then
   stage=out->'snapshot'->>'standard_stage';
   update public.story_standard_projects set status=case stage when 'draft' then 'drafting' when 'sample' then 'sampling' when 'render' then 'rendering' else 'uploading' end,revision=revision+1
    where id=(out->'snapshot'->>'standard_project_id')::uuid;
  end if;
  -- Mirror expired/uncertain jobs into the administrator view without requeueing.
  update public.story_standard_projects q set status='needs_review',revision=revision+1
   where q.status in ('draft_queued','drafting','sample_queued','sampling','render_queued','rendering','upload_queued','uploading')
   and exists(select 1 from public.story_jobs t where t.snapshot->>'standard_project_id'=q.id::text and t.status='needs_review')
   and not exists(select 1 from public.story_jobs t where t.snapshot->>'standard_project_id'=q.id::text and t.status in ('queued','running'));
  return out;
 end if;
 select * into j from public.story_jobs where id=(p->>'id')::uuid;
 if j.snapshot->>'standard_profile' is distinct from 'ko-60-v1' then return public.story_studio_work_before_standard(p_action,p); end if;
 perform public.story_studio_work_before_standard('check',p);
 if not exists(select 1 from public.story_studio_config where singleton and standard_enabled) then raise exception 'STORY_NOT_READY'; end if;
 select * into x from public.story_standard_projects where id=(j.snapshot->>'standard_project_id')::uuid for update;
 if x.plan_revision is distinct from (j.snapshot->'project'->>'plan_revision')::bigint then raise exception 'STORY_CONFLICT'; end if;
 stage=j.snapshot->>'standard_stage';
 if p_action='check' then return '{}'::jsonb; end if;
 if p_action='fail' then
  update public.story_standard_projects set status='needs_review',revision=revision+1 where id=x.id;
  return public.story_studio_work_before_standard('fail',p);
 end if;
 if p_action<>'complete' then raise exception 'STORY_INVALID'; end if;
 v=p->'result';
 if stage='draft' then
  if not public.story_standard_plan_valid(v->'plan') or v->'plan'->>'food' is distinct from x.food then raise exception 'STORY_INVALID'; end if;
  update public.story_standard_projects set plan=v->'plan',source_receipt=v->'source_receipt',plan_revision=plan_revision+1,status='draft',revision=revision+1 where id=x.id;
 elsif stage='sample' then
  if not coalesce(v->>'sha256' ~ '^[0-9a-f]{64}$' and (v->>'seconds')::numeric between .5 and 9.5,false)
   or v->>'path' is distinct from j.id::text||'/sample.wav' then raise exception 'STORY_INVALID'; end if;
  update public.story_standard_projects set sample=v,status='sample_review',revision=revision+1 where id=x.id;
 elsif stage='render' then
  if v->>'path' is distinct from j.id::text||'/ko.mp4' or not coalesce(v->>'sha256' ~ '^[0-9a-f]{64}$'
   and (case when x.plan->>'profile'='ko-180-source-v1' then (v->>'seconds')::numeric between 150 and 180 else (v->>'seconds')::numeric between 59.9 and 60 end),false) or v->>'language' is distinct from 'ko' then raise exception 'STORY_INVALID'; end if;
  update public.story_standard_projects set preview=v,status='preview',revision=revision+1 where id=x.id;
 else
  if v->>'privacy' is distinct from 'private' or not coalesce(v->>'youtube_id' ~ '^[A-Za-z0-9_-]{11}$',false) then raise exception 'STORY_INVALID'; end if;
  update public.story_standard_projects set preview=preview||v,status='uploaded',revision=revision+1 where id=x.id;
 end if;
 update public.story_jobs set status='done',result=v,lease_token=null,lease_until=null where id=j.id;
 return '{}'::jsonb;
end $$;
revoke all on function public.story_studio_work(text,jsonb) from public,anon,authenticated;
grant execute on function public.story_studio_work(text,jsonb) to service_role;


alter table public.story_jobs add column dispatch_requested_at timestamptz;
create function public.story_request_dispatch(p_job_id uuid) returns boolean
language plpgsql security definer set search_path=public,pg_temp as $$
declare changed int;
begin
 perform public.assert_marketing_access();
 if not exists(select 1 from public.story_studio_config where singleton and enabled and standard_enabled) then return false; end if;
 update public.story_jobs set dispatch_requested_at=now()
 where id=p_job_id and created_by=auth.uid() and status='queued'
  and snapshot->>'standard_profile'='ko-60-v1' and dispatch_requested_at is null;
 get diagnostics changed=row_count;
 return changed=1;
end $$;
revoke all on function public.story_request_dispatch(uuid) from public,anon;
grant execute on function public.story_request_dispatch(uuid) to authenticated;
commit;
