-- Admin-approved marketing queue. Workers never select unapproved drafts.
begin;
create table public.marketing_video_campaigns (
 id uuid primary key,
 topic text not null check(length(btrim(topic)) between 3 and 200),
 draft jsonb,
 status text not null default 'generating' check(status in
 ('generating','draft','scheduled','rendering','uploading','uploaded','failed','needs_review','cancelled')),
 revision bigint not null default 0,
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 approved_by uuid references auth.users(id) on delete set null, approved_at timestamptz,
 scheduled_at timestamptz, worker_token uuid, lease_until timestamptz,
 attempts integer not null default 0,
 asset_path text, upload_session_url text, youtube_id text check(youtube_id ~ '^[A-Za-z0-9_-]{11}$'),
 last_error text check(last_error in ('draft_failed','render_failed','upload_uncertain','worker_interrupted','private_check_failed')),
 check(status not in ('scheduled','rendering','uploading','uploaded') or (approved_at is not null and scheduled_at is not null)),
 check(status <> 'uploaded' or youtube_id is not null)
);
create index marketing_video_due on public.marketing_video_campaigns(scheduled_at)
 where status in ('scheduled','rendering','uploading');
create table public.marketing_video_worker_state (
 singleton boolean primary key default true check(singleton),
 ready boolean not null default false, seen_at timestamptz, channel_id text
);
insert into public.marketing_video_worker_state(singleton) values(true);
alter table public.marketing_video_campaigns enable row level security;
alter table public.marketing_video_worker_state enable row level security;
revoke all on public.marketing_video_campaigns,public.marketing_video_worker_state from public,anon,authenticated;
grant all on public.marketing_video_campaigns,public.marketing_video_worker_state to service_role;

create function public.marketing_video_draft_valid(p jsonb) returns boolean
language plpgsql immutable set search_path='' as $$
declare scene jsonb; total integer:=0;
begin
 if jsonb_typeof(p) is distinct from 'object' or jsonb_typeof(p->'title') is distinct from 'string'
 or jsonb_typeof(p->'description') is distinct from 'string' or jsonb_typeof(p->'scenes') is distinct from 'array' then return false;end if;
 if length(btrim(p->>'title')) not between 3 and 80 or length(btrim(p->>'description')) not between 10 and 2000
 or jsonb_array_length(p->'scenes') not between 3 and 6 then return false;end if;
 for scene in select value from jsonb_array_elements(p->'scenes') loop
  if jsonb_typeof(scene) is distinct from 'object' or jsonb_typeof(scene->'screen_text') is distinct from 'string'
  or jsonb_typeof(scene->'narration') is distinct from 'string'
  or length(btrim(scene->>'screen_text')) not between 2 and 90
  or length(btrim(scene->>'narration')) not between 5 and 180 then return false;end if;
  total:=total+length(scene->>'narration');
 end loop;
 return total<=600;
end;$$;
revoke all on function public.marketing_video_draft_valid(jsonb) from public,anon,authenticated;

create function public.admin_marketing_overview() returns jsonb
language plpgsql security definer set search_path='' as $$
declare rows jsonb; worker jsonb;
begin
 perform public.assert_admin_mfa();
 -- Recover abandoned draft requests visibly; never approve or enqueue them.
 update public.marketing_video_campaigns set status='failed',last_error='draft_failed',updated_at=now(),revision=revision+1
 where status='generating' and created_at<now()-interval '5 minutes';
 select coalesce(jsonb_agg(to_jsonb(c)-'worker_token'-'upload_session_url'-'lease_until' order by c.created_at desc),'[]'::jsonb)
 into rows from (select * from public.marketing_video_campaigns order by created_at desc limit 100) c;
 select jsonb_build_object('ready',ready and seen_at>now()-interval '1 hour','seen_at',seen_at,'channel_id',channel_id)
 into worker from public.marketing_video_worker_state where singleton=true;
 return jsonb_build_object('campaigns',rows,'worker',worker);
end;$$;

create function public.admin_begin_marketing_draft(p_id uuid,p_topic text) returns boolean
language plpgsql security definer set search_path='' as $$
declare c public.marketing_video_campaigns;
begin
 perform public.assert_admin_mfa();
 if p_id is null or p_topic is null or length(btrim(p_topic)) not between 3 and 200 then raise exception 'MARKETING_INVALID';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,90));
 select * into c from public.marketing_video_campaigns where id=p_id;
 if found then
  if c.topic<>btrim(p_topic) or c.created_by is distinct from auth.uid() then raise exception 'MARKETING_CONFLICT';end if;
  return false;
 end if;
 if (select count(*) from public.marketing_video_campaigns where created_by=auth.uid() and created_at>now()-interval '1 hour')>=10
 then raise exception 'MARKETING_RATE_LIMIT';end if;
 insert into public.marketing_video_campaigns(id,topic,created_by) values(p_id,btrim(p_topic),auth.uid());
 return true;
end;$$;

create function public.admin_complete_marketing_draft(p_id uuid,p_draft jsonb) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform public.assert_admin_mfa();
 if p_draft is not null and not public.marketing_video_draft_valid(p_draft) then raise exception 'MARKETING_INVALID';end if;
 update public.marketing_video_campaigns set draft=p_draft,status=case when p_draft is null then 'failed' else 'draft' end,
 last_error=case when p_draft is null then 'draft_failed' else null end,revision=revision+1,updated_at=now()
 where id=p_id and status='generating' and created_by=auth.uid();
 if not found then raise exception 'MARKETING_STALE';end if;
end;$$;

create function public.admin_save_marketing_draft(p_id uuid,p_revision bigint,p_draft jsonb) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform public.assert_admin_mfa();
 if not public.marketing_video_draft_valid(p_draft) then raise exception 'MARKETING_INVALID';end if;
 update public.marketing_video_campaigns set draft=p_draft,status='draft',approved_by=null,approved_at=null,scheduled_at=null,
 last_error=null,revision=revision+1,updated_at=now()
 where id=p_id and revision=p_revision and status in ('draft','cancelled','failed') and draft is not null;
 if not found then raise exception 'MARKETING_STALE';end if;
end;$$;

create function public.admin_schedule_marketing_video(p_id uuid,p_revision bigint,p_at timestamptz) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform public.assert_admin_mfa();
 if p_at is null or p_at<=now()+interval '1 minute' or p_at>now()+interval '180 days' then raise exception 'MARKETING_TIME';end if;
 if not exists(select 1 from public.marketing_video_worker_state where singleton=true and ready and seen_at>now()-interval '1 hour')
 then raise exception 'MARKETING_WORKER_NOT_READY';end if;
 update public.marketing_video_campaigns set status='scheduled',scheduled_at=p_at,approved_at=now(),approved_by=auth.uid(),
 revision=revision+1,updated_at=now() where id=p_id and revision=p_revision and status='draft' and public.marketing_video_draft_valid(draft);
 if not found then raise exception 'MARKETING_STALE';end if;
end;$$;

create function public.admin_cancel_marketing_video(p_id uuid,p_revision bigint) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform public.assert_admin_mfa();
 update public.marketing_video_campaigns set status='cancelled',approved_at=null,approved_by=null,scheduled_at=null,
 revision=revision+1,updated_at=now() where id=p_id and revision=p_revision and status in ('draft','scheduled','generating','failed');
 if not found then raise exception 'MARKETING_STALE';end if;
end;$$;

-- Service-only worker API. The lease token fences stale runners.
create function public.marketing_worker_heartbeat(p_ready boolean,p_channel text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'SERVICE_ROLE_REQUIRED';end if;
 if p_ready and (p_channel is null or p_channel !~ '^UC[A-Za-z0-9_-]{22}$') then raise exception 'MARKETING_CHANNEL';end if;
 update public.marketing_video_worker_state set ready=coalesce(p_ready,false),channel_id=p_channel,seen_at=now() where singleton=true;
end;$$;

create function public.marketing_claim_video() returns jsonb
language plpgsql security definer set search_path='' as $$
declare c public.marketing_video_campaigns;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'SERVICE_ROLE_REQUIRED';end if;
 if not exists(select 1 from public.marketing_video_worker_state where singleton=true and ready and seen_at>now()-interval '1 hour') then return null;end if;
 -- A lost final upload response must be reconciled with the SAME resumable session.
 update public.marketing_video_campaigns set status='needs_review',last_error='upload_uncertain',worker_token=null,lease_until=null,
 revision=revision+1,updated_at=now() where status='uploading' and lease_until<now() and upload_session_url is null;
 update public.marketing_video_campaigns set status='failed',last_error='worker_interrupted',worker_token=null,lease_until=null,
 revision=revision+1,updated_at=now() where status='rendering' and lease_until<now() and attempts>=3;
 select * into c from public.marketing_video_campaigns
 where approved_at is not null and public.marketing_video_draft_valid(draft)
 and ((status='scheduled' and scheduled_at<=now()) or (status in ('rendering','uploading') and lease_until<now() and attempts<3))
 order by scheduled_at for update skip locked limit 1;
 if not found then return null;end if;
 update public.marketing_video_campaigns set status=case when c.status='uploading' then 'uploading' else 'rendering' end,
 worker_token=gen_random_uuid(),lease_until=now()+interval '30 minutes',attempts=attempts+1,revision=revision+1,updated_at=now()
 where id=c.id returning * into c;
 return to_jsonb(c);
end;$$;

create function public.marketing_worker_update(p_id uuid,p_token uuid,p_action text,p_value text default null) returns void
language plpgsql security definer set search_path='' as $$
declare c public.marketing_video_campaigns;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'SERVICE_ROLE_REQUIRED';end if;
 select * into c from public.marketing_video_campaigns where id=p_id for update;
 if not found or c.worker_token is distinct from p_token or p_token is null or c.lease_until<=now() then raise exception 'MARKETING_LEASE';end if;
 if p_action='asset' and c.status='rendering' and p_value=c.id::text||'/video.mp4' then
  update public.marketing_video_campaigns set asset_path=p_value,status='uploading' where id=p_id;
 elsif p_action='session' and c.status='uploading' and c.upload_session_url is null
 and p_value ~ '^https://(www\.)?googleapis\.com/upload/youtube/' and length(p_value)<4096 then
  update public.marketing_video_campaigns set upload_session_url=p_value where id=p_id;
 elsif p_action='uploaded' and c.status='uploading' and p_value ~ '^[A-Za-z0-9_-]{11}$' then
  update public.marketing_video_campaigns set youtube_id=p_value,status='uploaded',last_error=null,worker_token=null,lease_until=null,
  upload_session_url=null where id=p_id;
 elsif p_action='render_failed' and c.status='rendering' then
  update public.marketing_video_campaigns set status='failed',last_error='render_failed',worker_token=null,lease_until=null where id=p_id;
 elsif p_action in ('upload_uncertain','private_check_failed') and c.status='uploading' then
  update public.marketing_video_campaigns set status='needs_review',last_error=p_action,worker_token=null,lease_until=null where id=p_id;
 else raise exception 'MARKETING_TRANSITION';end if;
 update public.marketing_video_campaigns set revision=revision+1,updated_at=now() where id=p_id;
end;$$;

-- Explicit grants; no browser can claim jobs or inspect upload-session URLs.
revoke all on function public.admin_marketing_overview(),public.admin_begin_marketing_draft(uuid,text),
 public.admin_complete_marketing_draft(uuid,jsonb),public.admin_save_marketing_draft(uuid,bigint,jsonb),
 public.admin_schedule_marketing_video(uuid,bigint,timestamptz),public.admin_cancel_marketing_video(uuid,bigint) from public,anon;
grant execute on function public.admin_marketing_overview(),public.admin_begin_marketing_draft(uuid,text),
 public.admin_complete_marketing_draft(uuid,jsonb),public.admin_save_marketing_draft(uuid,bigint,jsonb),
 public.admin_schedule_marketing_video(uuid,bigint,timestamptz),public.admin_cancel_marketing_video(uuid,bigint) to authenticated;
revoke all on function public.marketing_worker_heartbeat(boolean,text),public.marketing_claim_video(),
 public.marketing_worker_update(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.marketing_worker_heartbeat(boolean,text),public.marketing_claim_video(),
 public.marketing_worker_update(uuid,uuid,text,text) to service_role;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('marketing-videos','marketing-videos',false,104857600,array['video/mp4']) on conflict(id) do nothing;
create policy marketing_video_admin_read on storage.objects for select to authenticated
 using(bucket_id='marketing-videos' and exists(select 1 from public.profiles where id=auth.uid() and role='admin')
 and coalesce(auth.jwt()->>'aal','aal1')='aal2');
notify pgrst,'reload schema';
commit;
