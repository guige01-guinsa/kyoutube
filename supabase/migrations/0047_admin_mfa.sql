create function public.assert_admin_mfa() returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and role='admin') then
 raise exception 'ADMIN_REQUIRED'; end if;
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then raise exception 'ADMIN_MFA_REQUIRED'; end if;
end;
$$;
revoke all on function public.assert_admin_mfa() from public,anon,authenticated;
DO $migration$
declare f record; definition text;
begin
 for f in select p.oid,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 join pg_language l on l.oid=p.prolang where n.nspname='public' and p.proname like 'admin\_%' escape '\'
 and l.lanname='plpgsql' loop
 definition:=pg_get_functiondef(f.oid);
 if position('assert_admin_mfa()' in definition)=0 then
 definition:=regexp_replace(definition,'\mbegin\M','BEGIN PERFORM public.assert_admin_mfa();','i');
 if position('PERFORM public.assert_admin_mfa();' in definition)=0 then raise exception 'Admin guard insertion failed'; end if;
 execute definition;
 end if;
 end loop;
end;
$migration$;
