-- Preserve the source recipe and actual narration length, without padding to 150s.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
lock table public.story_jobs in share row exclusive mode;
do $$
declare body text; old_rule text='then (v->>''seconds'')::numeric between 150 and 180 else';
begin
 if exists(select 1 from public.story_jobs where status in ('queued','running')) then
  raise exception 'STORY_WAIT_FOR_IDLE_QUEUE';
 end if;
 select pg_get_functiondef('public.story_studio_work(text,jsonb)'::regprocedure) into body;
 if (length(body)-length(replace(body,old_rule,'')))/length(old_rule)<>1 then
  raise exception 'STORY_UNEXPECTED_DURATION_RULE';
 end if;
 -- CREATE OR REPLACE retains the existing service-role-only grants and all
 -- authorization, lease, source-revision, path, hash and upload checks.
 execute replace(body,old_rule,'then (v->>''seconds'')::numeric between 30 and 180 else');
end $$;
commit;
