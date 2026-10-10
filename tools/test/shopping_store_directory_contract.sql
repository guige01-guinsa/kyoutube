-- Local fixtures created by shopping_assistant_contract.sql; transaction rolls back.
select set_config('request.jwt.claim.sub','62000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
insert into public.shopping_suppliers(id,name,website,address,memo,is_favorite)
  values('64000000-0000-4000-8000-000000000001','Personal store','https://example.com?next=../catalog','Local address','Private notes',true);
update public.shopping_suppliers set website='https://shop.example.com:443/groceries', memo='Updated private notes', is_favorite=false
  where id='64000000-0000-4000-8000-000000000001';
do $$ declare v text; begin
  if not exists(select 1 from public.shopping_suppliers where memo='Updated private notes' and not is_favorite and address='Local address') then
    raise exception 'DIRECTORY_EDIT_FAILED'; end if;
  foreach v in array array['http://example.com','javascript:alert(1)','https://a@shop.example.com','https://example.com:8443',
    'https://127.0.0.1','https://shop.local','https://a..example.com','https://example.com/a b',E'https://example.com/\\bad'] loop
    begin update public.shopping_suppliers set website=v; raise exception 'DIRECTORY_INVALID_LINK_ACCEPTED';
    exception when check_violation then null; end;
  end loop;
  begin update public.shopping_suppliers set memo=repeat('a',1001); raise exception 'DIRECTORY_LONG_MEMO_ACCEPTED';
  exception when check_violation then null; end;
end;$$;
reset role;
select set_config('request.jwt.claim.sub','62000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$ declare n int; begin
  if exists(select 1 from public.shopping_suppliers) then raise exception 'DIRECTORY_PRIVATE_NOTES_LEAK'; end if;
  update public.shopping_suppliers set memo='Foreign edit'; get diagnostics n=row_count;
  if n<>0 then raise exception 'DIRECTORY_FOREIGN_EDIT'; end if;
  delete from public.shopping_suppliers; get diagnostics n=row_count;
  if n<>0 then raise exception 'DIRECTORY_FOREIGN_DELETE'; end if;
end;$$;
reset role;
do $$ begin
  if has_column_privilege('anon','public.shopping_suppliers','memo','select') then raise exception 'DIRECTORY_ANON_NOTES'; end if;
  if has_column_privilege('authenticated','public.shopping_suppliers','owner_id','update') then raise exception 'DIRECTORY_OWNER_CHANGE'; end if;
end;$$;
select set_config('request.jwt.claim.sub','62000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
delete from public.shopping_suppliers where id='64000000-0000-4000-8000-000000000001';
do $$ begin if exists(select 1 from public.shopping_suppliers) then raise exception 'DIRECTORY_DELETE_FAILED'; end if; end;$$;
reset role;
select 'SHOPPING_STORE_DIRECTORY_CONTRACT_PASSED' as result;
