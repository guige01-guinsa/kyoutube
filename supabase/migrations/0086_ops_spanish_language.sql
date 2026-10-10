-- Preserve administrator/MFA/session checks while supporting Spanish devices.
begin;
alter table public.ops_admin_devices drop constraint ops_admin_devices_language_check;
alter table public.ops_admin_devices add constraint ops_admin_devices_language_check
  check(language in ('ko','en','es'));

create or replace function public.admin_register_ops_device(p_token text,p_language text) returns void
language plpgsql security definer set search_path='' as $$
declare sid uuid := (auth.jwt()->>'session_id')::uuid;
begin
  perform public.assert_ops_admin();
  if not exists(select 1 from auth.sessions where id=sid and user_id=auth.uid()
    and (not_after is null or not_after>now())) then raise exception 'SESSION_REQUIRED'; end if;
  if p_token is null or length(p_token) not between 20 and 4096 or
    p_language is null or p_language not in ('ko','en','es') then raise exception 'INVALID_DEVICE'; end if;
  delete from public.ops_admin_devices where expires_at<now();
  if not exists(select 1 from public.ops_admin_devices where token=p_token)
    and (select count(*) from public.ops_admin_devices where user_id=auth.uid())>=10 then
    raise exception 'DEVICE_LIMIT'; end if;
  insert into public.ops_admin_devices(user_id,session_id,token,language)
  values(auth.uid(),sid,p_token,p_language) on conflict(token) do update
    set user_id=excluded.user_id,session_id=excluded.session_id,language=excluded.language,
      expires_at=now()+interval '30 days';
end;
$$;
commit;
