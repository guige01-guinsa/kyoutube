begin;
create function public.admin_assert_integration_access() returns boolean
language plpgsql security definer set search_path='' as $$
begin
 perform public.assert_supplier_directory_admin();
 if coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'ADMIN_REQUIRED';end if;
 return true;
end;$$;
revoke all on function public.admin_assert_integration_access() from public,anon;
grant execute on function public.admin_assert_integration_access() to authenticated;
commit;
