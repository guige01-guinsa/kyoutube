-- Opt-in Korean pilot workflow. No budgets, users or existing assets are changed.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
lock table public.story_jobs in share row exclusive mode;
do $$ begin
 if exists(select 1 from public.story_jobs where status in ('queued','running')) then
  raise exception 'STORY_WAIT_FOR_IDLE_QUEUE'; end if;
end $$;
alter table public.story_studio_config add column standard_enabled boolean not null default false;
alter table public.story_studio_config add column standard_worker_seen_at timestamptz;
alter table public.story_studio_config add column standard_capture_ready boolean not null default false;
alter table public.story_studio_config add column sample_usd numeric(10,4) check(sample_usd>=0);

create table public.story_standard_projects(
 id uuid primary key, series_id uuid not null references public.story_series(id),
 food text not null check(char_length(btrim(food)) between 1 and 30),
 presenter text not null check(char_length(btrim(presenter)) between 1 and 500),
 plan jsonb, revision bigint not null default 1, plan_revision bigint not null default 0,
 status text not null default 'planning' check(status in
 ('planning','draft_queued','drafting','draft','sample_queued','sampling','sample_review',
 'sample_approved','render_queued','rendering','preview','upload_queued','uploading','uploaded','needs_review')),
 sample jsonb, preview jsonb, sample_approved_by uuid references auth.users(id),
 sample_approved_at timestamptz, created_by uuid references auth.users(id),
 created_at timestamptz not null default now()
);
alter table public.story_standard_projects enable row level security;
revoke all on public.story_standard_projects from public,anon,authenticated;
grant all on public.story_standard_projects to service_role;

create function public.story_standard_plan_valid(v jsonb) returns boolean
language plpgsql immutable set search_path=public,pg_temp as $$
declare scene jsonb; src jsonb; ref jsonb; ids text[]='{}'; roles text[]=array['greeting','food_fact','ingredients','cooking','app_demo','closing']; n int=0;
begin
 if jsonb_typeof(v) is distinct from 'object' or v->>'profile' is distinct from 'ko-60-v1'
  or v->>'language' is distinct from 'ko' or not coalesce(char_length(btrim(v->>'food')) between 1 and 30
  and char_length(btrim(v->>'title')) between 1 and 45 and char_length(btrim(v->>'presenter')) between 1 and 500,false)
  or jsonb_typeof(v->'sources') is distinct from 'array' or jsonb_typeof(v->'scenes') is distinct from 'array' then return false; end if;
 if (select count(*) from jsonb_object_keys(v))<>7 or exists(
  select 1 from jsonb_each(v) where key in ('profile','language','food','title','presenter')
  and (jsonb_typeof(value)<>'string' or (value#>>'{}') ~ '[[:cntrl:]]')) then return false; end if;
 if jsonb_array_length(v->'sources') not between 2 and 8 or jsonb_array_length(v->'scenes')<>6 then return false; end if;
 for src in select value from jsonb_array_elements(v->'sources') loop
  if jsonb_typeof(src) is distinct from 'object' then return false; end if;
  if (select count(*) from jsonb_object_keys(src))<>4 or exists(select 1 from jsonb_each(src)
   where jsonb_typeof(value)<>'string' or char_length(btrim(value#>>'{}'))=0 or (value#>>'{}') ~ '[[:cntrl:]]') then return false; end if;
  if not coalesce(src->>'id' ~ '^[a-z0-9-]{1,60}$' and char_length(src->>'title') between 1 and 200
    and char_length(src->>'note') between 1 and 1000 and src->>'url' ~ '^https://[^/@[:space:]]+/'
    and char_length(src->>'url')<=1000,false) or (src->>'id')=any(ids) then return false; end if;
  ids=array_append(ids,src->>'id');
 end loop;
 for scene in select value from jsonb_array_elements(v->'scenes') loop
  n=n+1;
  if jsonb_typeof(scene) is distinct from 'object' then return false; end if;
  if (select count(*) from jsonb_object_keys(scene))<>5 or exists(select 1 from jsonb_each(scene)
   where key in ('role','spoken','caption','visual') and (jsonb_typeof(value)<>'string' or (value#>>'{}') ~ '[[:cntrl:]]'))
   or not coalesce(scene->>'spoken' ~ '[가-힣]',false) then return false; end if;
  if scene->>'role' is distinct from roles[n] or not coalesce(char_length(btrim(scene->>'spoken')) between 1 and 50
   and char_length(btrim(scene->>'caption')) between 1 and 60 and char_length(btrim(scene->>'visual')) between 1 and 1000,false)
   or jsonb_typeof(scene->'source_ids') is distinct from 'array' then return false; end if;
  if jsonb_array_length(scene->'source_ids')<>(select count(distinct value) from jsonb_array_elements(scene->'source_ids')) then return false; end if;
  if n between 2 and 4 and jsonb_array_length(scene->'source_ids')=0 then return false; end if;
  for ref in select value from jsonb_array_elements(scene->'source_ids') loop
   if jsonb_typeof(ref)<>'string' or not (ref#>>'{}')=any(ids) then return false; end if;
  end loop;
 end loop;
 return true;
end $$;
revoke all on function public.story_standard_plan_valid(jsonb) from public,anon,authenticated;
grant execute on function public.story_standard_plan_valid(jsonb) to service_role;

create function public.story_standard(p_action text,p jsonb default '{}') returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare x public.story_standard_projects; c public.story_studio_config; s public.story_series;
 j public.story_jobs; cost numeric; amount int; kind text; snap jsonb; jid uuid;
begin
 perform public.assert_marketing_access();
 if p_action='overview' then
  return jsonb_build_object('config',(select to_jsonb(t) from public.story_studio_config t where singleton),
   'series',coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title) order by created_at desc) from public.story_series where language='ko'),'[]'),
   'projects',coalesce((select jsonb_agg(to_jsonb(t) order by created_at desc) from public.story_standard_projects t),'[]'),
   'jobs',coalesce((select jsonb_agg(jsonb_build_object('id',id,'status',status,'stage',snapshot->>'standard_stage',
     'project_id',snapshot->>'standard_project_id','error_code',error_code,'reserved_usd',reserved_usd) order by created_at desc)
     from public.story_jobs where snapshot->>'standard_profile'='ko-60-v1'),'[]'));
 end if;
 if p_action='create' then
  select * into s from public.story_series where id=(p->>'series_id')::uuid and language='ko';
  if not found then raise exception 'STORY_NOT_FOUND'; end if;
  insert into public.story_standard_projects(id,series_id,food,presenter,created_by)
   values((p->>'id')::uuid,s.id,btrim(p->>'food'),btrim(p->>'presenter'),auth.uid()) on conflict(id) do nothing;
  select * into x from public.story_standard_projects where id=(p->>'id')::uuid;
  if x.series_id<>s.id or x.food is distinct from btrim(p->>'food') or x.presenter is distinct from btrim(p->>'presenter') then raise exception 'STORY_CONFLICT'; end if;
  return to_jsonb(x);
 end if;
 -- Same global config-row lock as the old workflow: all reservations share totals.
 select * into c from public.story_studio_config where singleton for update;
 select * into x from public.story_standard_projects where id=(p->>'project_id')::uuid for update;
 if not found then raise exception 'STORY_NOT_FOUND'; end if;
 if p_action in ('draft','sample','render','upload') then
  jid=(p->>'id')::uuid;
  select * into j from public.story_jobs where id=jid;
  if found then
   if j.request<>p or j.snapshot->>'standard_stage'<>p_action or j.snapshot->>'standard_project_id'<>x.id::text then raise exception 'STORY_CONFLICT'; end if;
   return jsonb_build_object('id',jid);
  end if;
 end if;
 if x.revision is distinct from (p->>'revision')::bigint then raise exception 'STORY_CONFLICT'; end if;
 if exists(select 1 from public.story_jobs where snapshot->>'standard_project_id'=x.id::text and status in ('queued','running')) then raise exception 'STORY_CONFLICT'; end if;
 if p_action='save_plan' then
  if x.status not in ('planning','draft','sample_review','sample_approved','needs_review')
   or not public.story_standard_plan_valid(p->'plan') or p->'plan'->>'food' is distinct from x.food then raise exception 'STORY_INVALID'; end if;
  update public.story_standard_projects set plan=p->'plan',plan_revision=plan_revision+1,revision=revision+1,
   status='draft',sample=null,sample_approved_by=null,sample_approved_at=null where id=x.id;
  return '{}'::jsonb;
 end if;
 if p_action='approve_sample' then
  if x.status<>'sample_review' or x.sample->>'sha256' is distinct from p->>'sha256'
   or p->>'listened' is distinct from 'true' then raise exception 'STORY_SAMPLE_REQUIRED'; end if;
  update public.story_standard_projects set status='sample_approved',revision=revision+1,
   sample_approved_by=auth.uid(),sample_approved_at=now() where id=x.id;
  return '{}'::jsonb;
 end if;
 if p_action not in ('draft','sample','render','upload') then raise exception 'STORY_INVALID'; end if;
 if not c.enabled or not c.standard_enabled or c.standard_worker_seen_at is null
  or c.standard_worker_seen_at<now()-interval '20 minutes' then raise exception 'STORY_NOT_READY'; end if;
 if c.revision is distinct from (p->>'quote_revision')::bigint then raise exception 'STORY_QUOTE_CHANGED'; end if;
 if p->>'cost_confirmed' is distinct from 'true' then raise exception 'STORY_COST_CONFIRMATION_REQUIRED'; end if;
 cost=case p_action when 'draft' then c.draft_usd when 'sample' then c.sample_usd when 'render' then c.render_usd else 0 end;
 if cost is null or c.usd_krw is null or c.text_model is null or c.image_model is null then raise exception 'STORY_NOT_READY'; end if;
 amount=ceil(cost*c.usd_krw);
 if (select coalesce(sum(reserved_krw),0) from public.story_jobs where date_trunc('month',created_at at time zone 'Asia/Seoul')=date_trunc('month',now() at time zone 'Asia/Seoul'))+amount+c.fixed_krw+c.buffer_krw>c.monthly_krw then raise exception 'STORY_MONTHLY_LIMIT'; end if;
 if (select count(*) from public.story_jobs where created_at>now()-interval '1 day')>=c.daily_jobs
  or (select coalesce(sum(reserved_usd),0) from public.story_jobs where created_at>now()-interval '1 day')+cost>c.daily_usd then raise exception 'STORY_BUDGET_LIMIT'; end if;
 if p_action='draft' and x.status<>'planning' then raise exception 'STORY_CONFLICT'; end if;
 if p_action in ('sample','render') and (not public.story_standard_plan_valid(x.plan)
  or p->>'sources_reviewed' is distinct from 'true') then raise exception 'STORY_SOURCES_REQUIRED'; end if;
 if p_action='sample' and x.status<>'draft' then raise exception 'STORY_CONFLICT'; end if;
 if p_action='render' and (x.status<>'sample_approved' or x.sample_approved_by is null) then raise exception 'STORY_SAMPLE_REQUIRED'; end if;
 if p_action='render' and not c.standard_capture_ready then raise exception 'STORY_DEMO_REQUIRED'; end if;
 if p_action='upload' and (x.status<>'preview' or p->>'preview_reviewed' is distinct from 'true'
  or x.preview->>'sha256' is distinct from p->>'sha256' or x.preview->>'youtube_id' is not null) then raise exception 'STORY_PREVIEW_REQUIRED'; end if;
 select * into s from public.story_series where id=x.series_id;
 kind=case when p_action='sample' then 'render' else p_action end;
 snap=jsonb_build_object('standard_profile','ko-60-v1','standard_stage',p_action,'standard_project_id',x.id,
  'project',to_jsonb(x),'series',to_jsonb(s),'text_model',c.text_model,'image_model',c.image_model);
 insert into public.story_jobs(id,series_id,kind,snapshot,request,reserved_usd,reserved_krw,created_by)
  values(jid,x.series_id,kind,snap,p,cost,amount,auth.uid());
 update public.story_standard_projects set status=p_action||'_queued',revision=revision+1 where id=x.id;
 return jsonb_build_object('id',jid);
end $$;
revoke all on function public.story_standard(text,jsonb) from public,anon;
grant execute on function public.story_standard(text,jsonb) to authenticated;

-- Preserve the legacy worker implementation and permissions; only dispatch opt-in jobs.
alter function public.story_studio_work(text,jsonb) rename to story_studio_work_before_standard;
revoke all on function public.story_studio_work_before_standard(text,jsonb) from public,anon,authenticated,service_role;
create function public.story_studio_work(p_action text,p jsonb default '{}') returns jsonb
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
  update public.story_standard_projects set plan=v->'plan',plan_revision=plan_revision+1,status='draft',revision=revision+1 where id=x.id;
 elsif stage='sample' then
  if not coalesce(v->>'sha256' ~ '^[0-9a-f]{64}$' and (v->>'seconds')::numeric between .5 and 9.5,false)
   or v->>'path' is distinct from j.id::text||'/sample.wav' then raise exception 'STORY_INVALID'; end if;
  update public.story_standard_projects set sample=v,status='sample_review',revision=revision+1 where id=x.id;
 elsif stage='render' then
  if v->>'path' is distinct from j.id::text||'/ko.mp4' or not coalesce(v->>'sha256' ~ '^[0-9a-f]{64}$'
   and (v->>'seconds')::numeric between 59.9 and 60,false) or v->>'language' is distinct from 'ko' then raise exception 'STORY_INVALID'; end if;
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

-- First samples have their own private bucket. Clients can read only with MFA;
-- all writes are server-only. Size limit allows one <=9.5s WAV with headroom.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('story-standard-samples','story-standard-samples',false,2000000,array['audio/wav']);
create policy story_standard_sample_read on storage.objects for select to authenticated
 using(bucket_id='story-standard-samples' and auth.jwt()->>'aal'='aal2' and exists(select 1 from public.marketing_admins where user_id=auth.uid()));
create policy story_standard_sample_read_guard on storage.objects as restrictive for select to anon,authenticated
 using(bucket_id<>'story-standard-samples' or (auth.uid() is not null and coalesce(auth.jwt()->>'aal','')='aal2' and exists(select 1 from public.marketing_admins where user_id=auth.uid())));
create policy story_standard_sample_insert_guard on storage.objects as restrictive for insert to anon,authenticated with check(bucket_id<>'story-standard-samples');
create policy story_standard_sample_update_guard on storage.objects as restrictive for update to anon,authenticated using(bucket_id<>'story-standard-samples') with check(bucket_id<>'story-standard-samples');
create policy story_standard_sample_delete_guard on storage.objects as restrictive for delete to anon,authenticated using(bucket_id<>'story-standard-samples');

create table public.story_standard_audio_cache(
 project_id uuid not null references public.story_standard_projects(id), cache_key text not null check(cache_key ~ '^[0-9a-f]{64}$'),
 path text not null unique, owner_job uuid not null references public.story_jobs(id),
 status text not null default 'pending' check(status in ('pending','ready')),
 bytes bigint not null default 2000000 check(bytes between 1000 and 2000000), sha256 text check(sha256 ~ '^[0-9a-f]{64}$'),
 primary key(project_id,cache_key), check(status<>'ready' or sha256 is not null)
);
alter table public.story_standard_audio_cache enable row level security;
revoke all on public.story_standard_audio_cache from public,anon,authenticated;
grant all on public.story_standard_audio_cache to service_role;
create function public.story_standard_checkpoint(p_action text,p jsonb) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare j public.story_jobs; x public.story_standard_projects; c public.story_standard_audio_cache;
 k text=p->>'key'; fresh boolean=false; n bigint;
begin
 perform pg_advisory_xact_lock(87251,2);
 perform public.story_studio_work('check',p);
 select * into j from public.story_jobs where id=(p->>'id')::uuid;
 if j.snapshot->>'standard_profile' is distinct from 'ko-60-v1' or j.snapshot->>'standard_stage' not in ('sample','render')
  or k is null or k !~ '^[0-9a-f]{64}$' then raise exception 'STORY_INVALID'; end if;
 select * into x from public.story_standard_projects where id=(j.snapshot->>'standard_project_id')::uuid;
 select * into c from public.story_standard_audio_cache where project_id=x.id and cache_key=k for update;
 if p_action='reserve' then
  if not found then
   if (select coalesce(sum(bytes),0)+2000000 from public.story_standard_audio_cache)>96000000
    or (select count(*) from public.story_standard_audio_cache where project_id=x.id)>=20 then raise exception 'STORY_SPEECH_CAPACITY'; end if;
   insert into public.story_standard_audio_cache(project_id,cache_key,path,owner_job)
    values(x.id,k,x.series_id::text||'/'||x.id::text||'/'||k||'.wav',j.id) returning * into c;
   fresh=true;
  elsif c.status='pending' and c.owner_job<>j.id then
   if exists(select 1 from public.story_jobs where id=c.owner_job and status in ('queued','running')) then raise exception 'STORY_SPEECH_BUSY'; end if;
   update public.story_standard_audio_cache set owner_job=j.id where project_id=x.id and cache_key=k returning * into c;
   fresh=true;
  end if;
 elsif p_action='commit' then
  n=(p->>'bytes')::bigint;
  if c.project_id is null or c.status<>'pending' or c.owner_job<>j.id or n is null or n not between 1000 and 2000000
   or not coalesce(p->>'sha256' ~ '^[0-9a-f]{64}$',false)
   or not exists(select 1 from storage.objects where bucket_id='story-standard-samples' and name=c.path and (metadata->>'size')::bigint=n)
   then raise exception 'STORY_INVALID'; end if;
  update public.story_standard_audio_cache set status='ready',sha256=p->>'sha256',bytes=n
   where project_id=x.id and cache_key=k returning * into c;
 else raise exception 'STORY_INVALID'; end if;
 return jsonb_build_object('path',c.path,'status',c.status,'bytes',c.bytes,'sha256',c.sha256,'can_generate',fresh);
end $$;
revoke all on function public.story_standard_checkpoint(text,jsonb) from public,anon,authenticated;
grant execute on function public.story_standard_checkpoint(text,jsonb) to service_role;
commit;
