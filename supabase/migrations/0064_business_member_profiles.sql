-- Owner-managed staff profiles. Existing membership/RLS and access grants stay authoritative.
alter table public.business_members
 add column job_title text not null default '' check(length(job_title)<=80),
 add column work_contact text not null default '' check(length(work_contact)<=120),
 add column profile_revision bigint not null default 1 check(profile_revision>0);

-- Also detects names changed by an invitation acceptance while a profile editor is open.
create function public.business_member_profile_revision() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if row(new.display_name,new.job_title,new.work_contact)
    is distinct from row(old.display_name,old.job_title,old.work_contact) then
  new.profile_revision:=old.profile_revision+1;
 else
  new.profile_revision:=old.profile_revision;
 end if;
 return new;
end;$$;
create trigger business_member_profile_revision before update on public.business_members
 for each row execute function public.business_member_profile_revision();

create function public.business_member_profile_update(
 p_workspace uuid,p_user uuid,p_display_name text,p_job_title text,
 p_work_contact text,p_revision bigint
) returns void language plpgsql security definer set search_path='' as $$
declare m public.business_members;
begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if not coalesce(public.business_owner(p_workspace),false) then raise exception 'BUSINESS_DENIED';end if;
 if p_display_name is null or length(btrim(p_display_name)) not between 1 and 120
 or p_job_title is null or length(btrim(p_job_title))>80
 or p_work_contact is null or length(btrim(p_work_contact))>120
 or p_display_name ~ '[[:cntrl:]]' or p_job_title ~ '[[:cntrl:]]' or p_work_contact ~ '[[:cntrl:]]'
 or p_revision is null or p_revision<1 then raise exception 'BUSINESS_PROFILE_INVALID';end if;
 select * into m from public.business_members where workspace_id=p_workspace and user_id=p_user for update;
 if not found then raise exception 'BUSINESS_NOT_FOUND';end if;
 if m.profile_revision<>p_revision then raise exception 'BUSINESS_STALE';end if;
 if row(m.display_name,m.job_title,m.work_contact)
    is not distinct from row(btrim(p_display_name),btrim(p_job_title),btrim(p_work_contact)) then return;end if;
 update public.business_members
 set display_name=btrim(p_display_name),job_title=btrim(p_job_title),
     work_contact=btrim(p_work_contact),updated_at=now()
 where workspace_id=p_workspace and user_id=p_user;
 insert into public.business_access_events(workspace_id,actor_id,subject_id,action)
 values(p_workspace,auth.uid(),p_user,'profile');
end;$$;

-- Profiles are visible only to the owner and the member under existing table RLS.
-- No profile field can change permissions, active status, ownership or paid entitlement.
revoke all on function public.business_member_profile_revision() from public,anon,authenticated;
revoke all on function public.business_member_profile_update(uuid,uuid,text,text,text,bigint) from public,anon;
grant execute on function public.business_member_profile_update(uuid,uuid,text,text,text,bigint) to authenticated;
