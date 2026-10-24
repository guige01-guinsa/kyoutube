-- Korean-only narrated re-edits; archived trilingual jobs stay unchanged.
-- No rows, budgets, source videos, keys or policy grants are changed.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
lock table public.story_jobs in share row exclusive mode;
do $$ begin
 if exists(select 1 from public.story_jobs where status in ('queued','running')) then
  raise exception 'STORY_WAIT_FOR_IDLE_QUEUE';
 end if;
end $$;
create function public.story_render_languages(p jsonb) returns text[]
language plpgsql immutable set search_path=public,pg_temp as $$
declare brief text=coalesce(p->'episode'->>'brief',''); lines text[];
begin
 if position('[ENCYCLOPEDIA_REEDIT' in brief)=0 then return array['ko','en','es']; end if;
 select array_agg(line) into lines from regexp_split_to_table(brief,E'\\r?\\n') as line
  where position('[ENCYCLOPEDIA_REEDIT' in line)>0;
 if cardinality(lines)<>1 or lines[1] !~ '^\[ENCYCLOPEDIA_REEDIT:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:[0-9a-f]{64}\]$'
 then raise exception 'STORY_INVALID'; end if;
 return array['ko'];
end $$;
revoke all on function public.story_render_languages(jsonb) from public,anon,authenticated;
grant execute on function public.story_render_languages(jsonb) to service_role;

create or replace function public.story_studio_work(p_action text,p jsonb default '{}') returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare j public.story_jobs; s public.story_series; r public.story_recipes; e public.story_episodes; v jsonb; lang text; expected_languages text[];
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
  expected_languages=public.story_render_languages(j.snapshot);
  if jsonb_typeof(v->'variants') is distinct from 'object' then raise exception 'STORY_INVALID'; end if;
  if (select count(*) from jsonb_object_keys(v->'variants'))<>cardinality(expected_languages) then raise exception 'STORY_INVALID'; end if;
  foreach lang in array expected_languages loop
   if v->'variants'->lang->>'asset_path' is distinct from j.id::text||'/'||lang||'.mp4' or not coalesce(v->'variants'->lang->>'sha256' ~ '^[0-9a-f]{64}$',false) or v->'variants'->lang->>'youtube_id' is not null then raise exception 'STORY_INVALID'; end if;
  end loop;
  update public.story_episodes set status='preview',variants=v->'variants',asset_path=v->'variants'->'ko'->>'asset_path',asset_sha256=v->'variants'->'ko'->>'sha256',revision=revision+1 where id=j.episode_id;
 else
  if not coalesce(v->>'youtube_id' ~ '^[A-Za-z0-9_-]{11}$',false) or v->>'privacy' is distinct from 'private' then raise exception 'STORY_INVALID'; end if;
  lang=j.snapshot->>'language';
  update public.story_episodes set variants=jsonb_set(variants,array[lang,'youtube_id'],v->'youtube_id'),revision=revision+1 where id=j.episode_id returning * into e;
  update public.story_episodes set status=case when e.variants->'ko'->>'youtube_id' is not null and not exists(select 1 from jsonb_each(e.variants) as variant where variant.value->>'youtube_id' is null) then 'uploaded' else 'preview' end,
   youtube_id=e.variants->'ko'->>'youtube_id' where id=j.episode_id;
 end if;
 update public.story_jobs set status='done',result=v,lease_token=null,lease_until=null where id=j.id;
 return '{}'::jsonb;
end $$;

commit;

