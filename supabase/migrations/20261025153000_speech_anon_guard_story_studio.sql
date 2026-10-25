-- Anonymous reads must not evaluate the administrator table, which anon cannot read.
-- Keep speech inaccessible without changing other buckets' existing policies.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
alter policy story_speech_read_guard on storage.objects to authenticated;
create policy story_speech_anon_read_guard on storage.objects as restrictive for select to anon
 using(bucket_id<>'story-speech-cache');
commit;
