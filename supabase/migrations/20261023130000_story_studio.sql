-- Opt-in studio. Existing campaigns and the existing publisher are untouched.
create table public.story_studio_config (
 singleton boolean primary key default true check(singleton),
 enabled boolean not null default false,
 revision bigint not null default 1,
 text_model text, image_model text,
 draft_usd numeric(10,4), render_usd numeric(10,4), improve_usd numeric(10,4),
 daily_usd numeric(10,4) not null default 1 check(daily_usd between 0 and 100),
 daily_jobs integer not null default 5 check(daily_jobs between 1 and 50),
 monthly_krw integer not null default 300000 check(monthly_krw between 1 and 300000),
 fixed_krw integer not null default 50000 check(fixed_krw >= 0),
 buffer_krw integer not null default 50000 check(buffer_krw >= 0),
 usd_krw numeric(10,2),
 worker_seen_at timestamptz,
 check(fixed_krw+buffer_krw < monthly_krw),
 check(usd_krw > 0),
 check(draft_usd >= 0 and render_usd >= 0 and improve_usd >= 0)
);
insert into public.story_studio_config(singleton) values(true);
create table public.story_series (
 id uuid primary key,
 title text not null check(char_length(title) between 1 and 60),
 language text not null check(language in ('ko','en','es')),
 bible text not null check(char_length(bible) between 1 and 10000),
 active_recipe uuid,
 revision bigint not null default 1,
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now()
);
create table public.story_recipes (
 id uuid primary key default gen_random_uuid(),
 series_id uuid not null references public.story_series(id),
 version integer not null,
 settings jsonb not null,
 instructions text not null check(char_length(instructions) <= 3000),
 feedback text not null default '' check(char_length(feedback) <= 3000),
 reason text not null default '' check(char_length(reason) <= 2000),
 created_at timestamptz not null default now(),
 unique(series_id,version)
);
alter table public.story_series add foreign key(active_recipe) references public.story_recipes(id);
create table public.story_episodes (
 id uuid primary key,
 series_id uuid not null references public.story_series(id),
 number integer not null check(number between 1 and 1000),
 recipe_id uuid not null references public.story_recipes(id),
 brief text not null check(char_length(brief) between 1 and 3000),
 draft jsonb,
 status text not null check(status in ('draft_queued','drafting','draft','render_queued','rendering','preview','upload_queued','uploading','uploaded','failed','needs_review','cancelled')),
 revision bigint not null default 1,
 asset_path text, asset_sha256 text, youtube_id text,
 variants jsonb,
 error_code text,
 created_at timestamptz not null default now()
);
create unique index story_episode_number on public.story_episodes(series_id,number) where status <> 'cancelled';
create table public.story_jobs (
 id uuid primary key,
 series_id uuid not null references public.story_series(id),
 episode_id uuid references public.story_episodes(id),
 kind text not null check(kind in ('draft','improve','render','upload')),
 status text not null default 'queued' check(status in ('queued','running','done','failed','needs_review','cancelled')),
 snapshot jsonb not null,
 request jsonb not null,
 reserved_usd numeric(10,4) not null check(reserved_usd >= 0),
 reserved_krw integer not null check(reserved_krw >= 0),
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 lease_token uuid, lease_until timestamptz,
 error_code text, result jsonb
);
create index story_jobs_queue on public.story_jobs(created_at) where status='queued';
create table public.story_recipe_changes (
 id bigint generated always as identity primary key,
 series_id uuid not null references public.story_series(id),
 recipe_id uuid not null references public.story_recipes(id),
 changed_by uuid references auth.users(id) on delete set null,
 changed_at timestamptz not null default now()
);

alter table public.story_studio_config enable row level security;
alter table public.story_series enable row level security;
alter table public.story_recipes enable row level security;
alter table public.story_episodes enable row level security;
alter table public.story_jobs enable row level security;
alter table public.story_recipe_changes enable row level security;
revoke all on public.story_studio_config,public.story_series,public.story_recipes,
 public.story_episodes,public.story_jobs,public.story_recipe_changes from anon,authenticated;
grant all on public.story_studio_config,public.story_series,public.story_recipes,
 public.story_episodes,public.story_jobs,public.story_recipe_changes to service_role;

create function public.story_settings_valid(p jsonb) returns boolean
language sql immutable set search_path=public,pg_temp as $$
 select coalesce(jsonb_typeof(p)='object' and
   (p->>'font_size')::int between 32 and 48 and
   (p->>'scene_seconds')::int = 10 and
   (p->>'music_gain')::numeric between 0.2 and 1.5,false)
$$;
create function public.story_edition_valid(p jsonb) returns boolean
language plpgsql immutable set search_path=public,pg_temp as $$
declare v jsonb;
begin
 if p is null or jsonb_typeof(p)<>'object' then return false; end if;
 if jsonb_typeof(p->'title') is distinct from 'string' or not coalesce(char_length(p->>'title') between 1 and 45,false) then return false; end if;
 if jsonb_typeof(p->'chapters') is distinct from 'array' or jsonb_typeof(p->'captions') is distinct from 'array' then return false; end if;
 if jsonb_array_length(p->'chapters') not between 3 and 8 or jsonb_array_length(p->'captions')<>6 then return false; end if;
 for v in select value from jsonb_array_elements(p->'chapters') loop
  if jsonb_typeof(v)<>'string' or char_length(v#>>'{}') not between 1 and 1500 then return false; end if;
 end loop;
 for v in select value from jsonb_array_elements(p->'captions') loop
  if jsonb_typeof(v)<>'string' or char_length(v#>>'{}') not between 1 and 60 then return false; end if;
 end loop;
 return true;
end $$;
create function public.story_draft_valid(p jsonb) returns boolean
language plpgsql immutable set search_path=public,pg_temp as $$
declare v jsonb;
begin
 if not public.story_edition_valid(p) or not public.story_edition_valid(p->'translations'->'en') or not public.story_edition_valid(p->'translations'->'es') then return false; end if;
 if jsonb_typeof(p->'summary') is distinct from 'string' or jsonb_typeof(p->'image_prompt') is distinct from 'string' or not coalesce(char_length(p->>'summary') between 1 and 1500 and char_length(p->>'image_prompt') between 1 and 3000,false) then return false; end if;
 if jsonb_typeof(p->'panels') is distinct from 'array' then return false; end if;
 if jsonb_array_length(p->'panels')<>6 then return false; end if;
 for v in select value from jsonb_array_elements(p->'panels') loop
  if jsonb_typeof(v)<>'string' or char_length(v#>>'{}') not between 1 and 1500 then return false; end if;
 end loop;
 return true;
end $$;

-- All client reads and writes require the existing allowlist AND AAL2.
create function public.story_studio(p_action text,p jsonb default '{}') returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare s public.story_series; e public.story_episodes; r public.story_recipes;
 c public.story_studio_config; j public.story_jobs; snap jsonb; cost numeric; n integer; jid uuid; lang text; amount integer;
begin
 perform public.assert_marketing_access();
 if p_action='overview' then
  return jsonb_build_object(
   'config',(select to_jsonb(x) from public.story_studio_config x where singleton),
   'month_reserved_krw',(select coalesce(sum(reserved_krw),0) from public.story_jobs where date_trunc('month',created_at at time zone 'Asia/Seoul')=date_trunc('month',now() at time zone 'Asia/Seoul')),
   'series',coalesce((select jsonb_agg(to_jsonb(x) order by created_at desc) from public.story_series x),'[]'),
   'recipes',coalesce((select jsonb_agg(to_jsonb(x) order by version desc) from public.story_recipes x),'[]'),
   'episodes',coalesce((select jsonb_agg(to_jsonb(x) order by number) from public.story_episodes x),'[]'),
   'jobs',coalesce((select jsonb_agg(jsonb_build_object('id',id,'series_id',series_id,'episode_id',episode_id,'kind',kind,'status',status,'reserved_usd',reserved_usd,'error_code',error_code,'created_at',created_at) order by created_at desc) from public.story_jobs),'[]'));
 end if;
 if p_action='create_series' then
  insert into public.story_series(id,title,language,bible,created_by)
   values((p->>'id')::uuid,btrim(p->>'title'),p->>'language',btrim(p->>'bible'),auth.uid())
   on conflict(id) do nothing;
  select * into s from public.story_series where id=(p->>'id')::uuid for update;
  if s.title<>btrim(p->>'title') or s.bible<>btrim(p->>'bible') or s.language<>p->>'language' then raise exception 'STORY_CONFLICT'; end if;
  if s.active_recipe is null then
   insert into public.story_recipes(series_id,version,settings,instructions)
    values(s.id,1,'{"font_size":40,"scene_seconds":10,"music_gain":1}', 'Keep continuity, clear captions and factual app promotion. Six webtoon panels, 60 seconds, Korean with English and Spanish editions.') returning * into r;
   update public.story_series set active_recipe=r.id where id=s.id;
  end if;
  return jsonb_build_object('id',s.id);
 end if;
 select * into s from public.story_series where id=(p->>'series_id')::uuid for update;
 if not found then raise exception 'STORY_NOT_FOUND'; end if;
 if p_action='apply_recipe' then
  select * into r from public.story_recipes where id=(p->>'recipe_id')::uuid and series_id=s.id;
  if not found or s.revision is distinct from (p->>'revision')::bigint then raise exception 'STORY_CONFLICT'; end if;
  update public.story_series set active_recipe=r.id,revision=revision+1 where id=s.id;
  insert into public.story_recipe_changes(series_id,recipe_id,changed_by) values(s.id,r.id,auth.uid());
  return '{}'::jsonb;
 end if;
 if p_action='save_draft' then
  if not public.story_draft_valid(p->'draft') then raise exception 'STORY_INVALID'; end if;
  update public.story_episodes set draft=p->'draft',revision=revision+1
   where id=(p->>'episode_id')::uuid and series_id=s.id and status='draft' and revision=(p->>'revision')::bigint;
  if not found then raise exception 'STORY_CONFLICT'; end if;
  return '{}'::jsonb;
 end if;
 if p_action='cancel' then
  select * into e from public.story_episodes where id=(p->>'episode_id')::uuid and series_id=s.id for update;
  if not found or e.revision is distinct from (p->>'revision')::bigint or e.status not in ('draft','draft_queued','render_queued','failed') then raise exception 'STORY_CONFLICT'; end if;
  update public.story_jobs set status='cancelled' where episode_id=e.id and status='queued';
  update public.story_episodes set status='cancelled',revision=revision+1 where id=e.id;
  return '{}'::jsonb;
 end if;
 if p_action not in ('draft','improve','render','upload') then raise exception 'STORY_INVALID'; end if;
 jid=(p->>'id')::uuid;
 select * into j from public.story_jobs where id=jid;
 if found then
  if j.request<>p or j.kind<>p_action then raise exception 'STORY_CONFLICT'; end if;
  return jsonb_build_object('id',jid); -- A lost response never reserves/calls twice.
 end if;
 select * into c from public.story_studio_config where singleton for update;
 if not c.enabled or c.worker_seen_at is null or c.worker_seen_at<now()-interval '20 minutes' then raise exception 'STORY_NOT_READY'; end if;
 if c.revision is distinct from (p->>'quote_revision')::bigint then raise exception 'STORY_QUOTE_CHANGED'; end if;
 if (p->>'cost_confirmed')::boolean is distinct from true then raise exception 'STORY_COST_CONFIRMATION_REQUIRED'; end if;
 cost=case p_action when 'draft' then c.draft_usd when 'render' then c.render_usd when 'improve' then c.improve_usd else 0 end;
 if cost is null or c.text_model is null or c.image_model is null or c.usd_krw is null then raise exception 'STORY_NOT_READY'; end if;
 amount=ceil(cost*c.usd_krw);
 if (select coalesce(sum(reserved_krw),0) from public.story_jobs where date_trunc('month',created_at at time zone 'Asia/Seoul')=date_trunc('month',now() at time zone 'Asia/Seoul'))+amount+c.fixed_krw+c.buffer_krw>c.monthly_krw then raise exception 'STORY_MONTHLY_LIMIT'; end if;
 if (select count(*) from public.story_jobs where created_at>now()-interval '1 day')>=c.daily_jobs or
  (select coalesce(sum(reserved_usd),0) from public.story_jobs where created_at>now()-interval '1 day')+cost>c.daily_usd then raise exception 'STORY_BUDGET_LIMIT'; end if;
 select * into r from public.story_recipes where id=s.active_recipe;
 snap=jsonb_build_object('series',to_jsonb(s),'recipe',to_jsonb(r),'text_model',c.text_model,'image_model',c.image_model);
 if p_action='draft' then
  if s.revision is distinct from (p->>'revision')::bigint or not coalesce(char_length(btrim(p->>'brief')) between 1 and 3000,false) then raise exception 'STORY_CONFLICT'; end if;
  select * into e from public.story_episodes where series_id=s.id and status<>'cancelled' order by number desc limit 1;
  if found and e.status not in ('preview','uploaded') then raise exception 'STORY_FINISH_PREVIOUS'; end if;
  n=coalesce(e.number,0)+1;
  snap=snap||jsonb_build_object('history',coalesce((select jsonb_agg(jsonb_build_object('number',number,'title',draft->>'title','summary',draft->>'summary') order by number) from public.story_episodes where series_id=s.id and status in ('preview','uploaded') and number>n-11),'[]'),'brief',p->>'brief','number',n);
  insert into public.story_episodes(id,series_id,number,recipe_id,brief,status)
   values(jid,s.id,n,r.id,p->>'brief','draft_queued') returning * into e;
 elsif p_action='improve' then
  if not coalesce(char_length(btrim(p->>'feedback')) between 1 and 3000,false) then raise exception 'STORY_INVALID'; end if;
  snap=snap||jsonb_build_object('feedback',p->>'feedback');
 else
  select * into e from public.story_episodes where id=(p->>'episode_id')::uuid and series_id=s.id for update;
  if not found or e.revision is distinct from (p->>'revision')::bigint then raise exception 'STORY_CONFLICT'; end if;
  select * into r from public.story_recipes where id=e.recipe_id;
  if p_action='render' then
   if e.status<>'draft' or not public.story_draft_valid(e.draft) then raise exception 'STORY_CONFLICT'; end if;
   if (p->>'sources_reviewed')::boolean is distinct from true then raise exception 'STORY_SOURCES_REQUIRED'; end if;
  else
   lang=p->>'language';
   if lang is null or lang not in ('ko','en','es') or e.status<>'preview' or e.variants->lang->>'sha256' is distinct from p->>'asset_sha256' or (p->>'preview_reviewed')::boolean is distinct from true or e.variants->lang->>'youtube_id' is not null then raise exception 'STORY_PREVIEW_REQUIRED'; end if;
  end if;
  snap=snap||jsonb_build_object('episode',to_jsonb(e),'recipe',to_jsonb(r),'language',lang);
  update public.story_episodes set status=p_action||'_queued',revision=revision+1 where id=e.id;
 end if;
 insert into public.story_jobs(id,series_id,episode_id,kind,snapshot,request,reserved_usd,reserved_krw,created_by)
  values(jid,s.id,case when p_action='improve' then null else e.id end,p_action,snap,p,cost,amount,auth.uid());
 return jsonb_build_object('id',jid);
end $$;

create function public.story_studio_work(p_action text,p jsonb default '{}') returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare j public.story_jobs; s public.story_series; r public.story_recipes; e public.story_episodes; v jsonb; lang text;
begin
 if p_action='heartbeat' then
  update public.story_studio_config set worker_seen_at=now() where singleton and text_model=p->>'text_model' and image_model=p->>'image_model';
  return '{}'::jsonb;
 end if;
 if p_action='claim' then
  -- Reservations cannot silently carry paid work into another billing month.
  with expired as (update public.story_jobs set status='needs_review',error_code='budget_period_changed'
    where status='queued' and date_trunc('month',created_at at time zone 'Asia/Seoul')<>date_trunc('month',now() at time zone 'Asia/Seoul') returning episode_id)
   update public.story_episodes set status='needs_review',error_code='budget_period_changed',revision=revision+1 where id in(select episode_id from expired);
  -- Unknown remote outcomes are held for a human; there is no automatic retry.
  with stale as (update public.story_jobs set status='needs_review',error_code='worker_interrupted'
    where status='running' and lease_until<now() returning episode_id)
   update public.story_episodes set status='needs_review',error_code='worker_interrupted',revision=revision+1 where id in(select episode_id from stale);
  if not exists(select 1 from public.story_studio_config where singleton and enabled) then return null; end if;
  select * into j from public.story_jobs where status='queued' order by created_at for update skip locked limit 1;
  if not found then return null; end if;
  update public.story_jobs set status='running',lease_token=gen_random_uuid(),lease_until=now()+interval '20 minutes' where id=j.id returning * into j;
  update public.story_episodes set status=case j.kind when 'draft' then 'drafting' when 'render' then 'rendering' else 'uploading' end,revision=revision+1 where id=j.episode_id;
  return to_jsonb(j);
 end if;
 select * into j from public.story_jobs where id=(p->>'id')::uuid for update;
 if not found or j.status<>'running' or j.lease_token is distinct from (p->>'token')::uuid or j.lease_until<now() then raise exception 'STORY_LEASE_LOST'; end if;
 if p_action='check' then
  if not exists(select 1 from public.story_studio_config where singleton and enabled)
   or not exists(select 1 from public.marketing_admins where user_id=j.created_by) then raise exception 'STORY_NOT_READY'; end if;
  return '{}'::jsonb;
 end if;
 if p_action='fail' then
  update public.story_jobs set status='needs_review',error_code='worker_failed' where id=j.id;
  update public.story_episodes set status='needs_review',error_code='worker_failed',revision=revision+1 where id=j.episode_id;
  return '{}'::jsonb;
 end if;
 if p_action<>'complete' then raise exception 'STORY_INVALID'; end if;
 v=p->'result';
 if j.kind='draft' then
  if not public.story_draft_valid(v) then raise exception 'STORY_INVALID'; end if;
  update public.story_episodes set draft=v,status='draft',revision=revision+1 where id=j.episode_id;
 elsif j.kind='improve' then
  if not public.story_settings_valid(v->'settings') or not coalesce(char_length(v->>'instructions') between 1 and 3000 and char_length(v->>'reason') between 1 and 2000,false) then raise exception 'STORY_INVALID'; end if;
  select * into s from public.story_series where id=j.series_id for update;
  insert into public.story_recipes(series_id,version,settings,instructions,feedback,reason)
   values(s.id,(select max(version)+1 from public.story_recipes where series_id=s.id),v->'settings',v->>'instructions',j.snapshot->>'feedback',v->>'reason');
 elsif j.kind='render' then
  foreach lang in array array['ko','en','es'] loop
   if v->'variants'->lang->>'asset_path' is distinct from j.id::text||'/'||lang||'.mp4' or not coalesce(v->'variants'->lang->>'sha256' ~ '^[0-9a-f]{64}$',false) or v->'variants'->lang->>'youtube_id' is not null then raise exception 'STORY_INVALID'; end if;
  end loop;
  update public.story_episodes set status='preview',variants=v->'variants',asset_path=v->'variants'->'ko'->>'asset_path',asset_sha256=v->'variants'->'ko'->>'sha256',revision=revision+1 where id=j.episode_id;
 else
  if not coalesce(v->>'youtube_id' ~ '^[A-Za-z0-9_-]{11}$',false) or v->>'privacy' is distinct from 'private' then raise exception 'STORY_INVALID'; end if;
  lang=j.snapshot->>'language';
  update public.story_episodes set variants=jsonb_set(variants,array[lang,'youtube_id'],v->'youtube_id'),revision=revision+1 where id=j.episode_id returning * into e;
  update public.story_episodes set status=case when e.variants->'ko'->>'youtube_id' is not null and e.variants->'en'->>'youtube_id' is not null and e.variants->'es'->>'youtube_id' is not null then 'uploaded' else 'preview' end,
   youtube_id=e.variants->'ko'->>'youtube_id' where id=j.episode_id;
 end if;
 update public.story_jobs set status='done',result=v,lease_token=null,lease_until=null where id=j.id;
 return '{}'::jsonb;
end $$;

revoke all on function public.story_settings_valid(jsonb),public.story_draft_valid(jsonb) from public,anon,authenticated;
revoke all on function public.story_edition_valid(jsonb) from public,anon,authenticated;
revoke all on function public.story_studio(text,jsonb) from public,anon;
grant execute on function public.story_studio(text,jsonb) to authenticated;
revoke all on function public.story_studio_work(text,jsonb) from public,anon,authenticated;
grant execute on function public.story_studio_work(text,jsonb) to service_role;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('story-previews','story-previews',false,104857600,array['video/mp4']) on conflict(id) do nothing;
do $$ begin
 if exists(select 1 from storage.buckets where id='story-previews' and public) then
  raise exception 'STORY_PREVIEW_BUCKET_MUST_BE_PRIVATE';
 end if;
end $$;
create policy story_preview_admin_read on storage.objects for select to authenticated
 using(bucket_id='story-previews' and coalesce(auth.jwt()->>'aal','aal1')='aal2'
 and exists(select 1 from public.marketing_admins where user_id=auth.uid()));
