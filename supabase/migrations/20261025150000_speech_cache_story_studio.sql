-- Private per-episode voice checkpoints. No paid work, budget changes or deletion.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
lock table public.story_jobs in share row exclusive mode;
do $$ begin
 if exists(select 1 from public.story_jobs where status in ('queued','running')) then
  raise exception 'STORY_WAIT_FOR_IDLE_QUEUE';
 end if;
end $$;

create table public.story_speech_cache (
 episode_id uuid not null references public.story_episodes(id),
 series_id uuid not null references public.story_series(id),
 cache_key text not null check(cache_key ~ '^[0-9a-f]{64}$'),
 path text not null unique,
 status text not null default 'pending' check(status in ('pending','ready')),
 owner_job uuid not null references public.story_jobs(id),
 sha256 text check(sha256 ~ '^[0-9a-f]{64}$'),
 bytes bigint not null default 12000000 check(bytes between 1000 and 12000000),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 primary key(episode_id,cache_key),
 check(path=series_id::text||'/'||episode_id::text||'/'||cache_key||'.wav'),
 check(status<>'ready' or sha256 is not null)
);
alter table public.story_speech_cache enable row level security;
revoke all on public.story_speech_cache from public,anon,authenticated;
grant select,insert,update on public.story_speech_cache to service_role;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('story-speech-cache','story-speech-cache',false,12000000,array['audio/wav']);
create policy story_speech_admin_read on storage.objects for select to authenticated
 using(bucket_id='story-speech-cache' and auth.jwt()->>'aal'='aal2'
 and exists(select 1 from public.marketing_admins where user_id=auth.uid()));
-- Also constrain any older broad permissive policies. Clients can never modify audio.
create policy story_speech_read_guard on storage.objects as restrictive for select to anon,authenticated
 using(bucket_id<>'story-speech-cache' or (auth.jwt()->>'aal'='aal2'
 and exists(select 1 from public.marketing_admins where user_id=auth.uid())));
create policy story_speech_insert_guard on storage.objects as restrictive for insert to anon,authenticated
 with check(bucket_id<>'story-speech-cache');
create policy story_speech_update_guard on storage.objects as restrictive for update to anon,authenticated
 using(bucket_id<>'story-speech-cache') with check(bucket_id<>'story-speech-cache');
create policy story_speech_delete_guard on storage.objects as restrictive for delete to anon,authenticated
 using(bucket_id<>'story-speech-cache');

create function public.story_speech_checkpoint(p_action text,p jsonb) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare j public.story_jobs; c public.story_speech_cache; k text=p->>'key'; fresh boolean=false; n bigint;
begin
 -- Serialize quota accounting and ownership transfer; no network work under this lock.
 perform pg_advisory_xact_lock(87251,1);
 perform public.story_studio_work('check',p);
 select * into j from public.story_jobs where id=(p->>'id')::uuid;
 if j.kind<>'render' or public.story_render_languages(j.snapshot)<>array['ko']
  or j.request->>'sources_reviewed' is distinct from 'true'
  or j.snapshot->'episode'->>'id' is distinct from j.episode_id::text
  or j.snapshot->'series'->>'id' is distinct from j.series_id::text
  or k is null or k !~ '^[0-9a-f]{64}$' then raise exception 'STORY_INVALID'; end if;
 select * into c from public.story_speech_cache where episode_id=j.episode_id and cache_key=k for update;
 if p_action='reserve' then
  if not found then
   -- 192 MB total including 12 MB for each unfinished chunk. No silent eviction.
   if (select coalesce(sum(bytes),0)+12000000 from public.story_speech_cache)>192000000 then
    raise exception 'STORY_SPEECH_CAPACITY'; end if;
   insert into public.story_speech_cache(episode_id,series_id,cache_key,path,owner_job)
    values(j.episode_id,j.series_id,k,j.series_id::text||'/'||j.episode_id::text||'/'||k||'.wav',j.id) returning * into c;
   fresh=true;
  elsif c.status='pending' and c.owner_job<>j.id then
   if exists(select 1 from public.story_jobs where id=c.owner_job and status in ('queued','running')) then
    raise exception 'STORY_SPEECH_BUSY'; end if;
   update public.story_speech_cache set owner_job=j.id,updated_at=now()
    where episode_id=j.episode_id and cache_key=k returning * into c;
   fresh=true;
  end if;
 elsif p_action='commit' then
  if c.episode_id is null or c.status<>'pending' or c.owner_job<>j.id then raise exception 'STORY_INVALID'; end if;
  n=(p->>'bytes')::bigint;
  if n is null or n not between 1000 and 12000000 or not coalesce(p->>'sha256' ~ '^[0-9a-f]{64}$',false)
   or not exists(select 1 from storage.objects where bucket_id='story-speech-cache' and name=c.path
    and (metadata->>'size')::bigint=n) then raise exception 'STORY_INVALID'; end if;
  update public.story_speech_cache set status='ready',bytes=n,sha256=p->>'sha256',updated_at=now()
   where episode_id=j.episode_id and cache_key=k returning * into c;
 else raise exception 'STORY_INVALID'; end if;
 return jsonb_build_object('path',c.path,'status',c.status,'sha256',c.sha256,'bytes',c.bytes,'can_generate',fresh);
end $$;
revoke all on function public.story_speech_checkpoint(text,jsonb) from public,anon,authenticated;
grant execute on function public.story_speech_checkpoint(text,jsonb) to service_role;
commit;
