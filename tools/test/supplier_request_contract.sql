-- Run after shopping_assistant_contract.sql inside the same local transaction.
select set_config('request.jwt.claim.sub','62000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
insert into public.shopping_suppliers(id,name,contact,phone,products) values
 ('63000000-0000-4000-8000-000000000001','Test supplier','Contact','000','Tofu');
update public.shopping_suppliers set products='Tofu, onions' where id='63000000-0000-4000-8000-000000000001';
do $$ declare p jsonb; r jsonb; r2 jsonb; before_stock numeric; before_records int;begin
 p:='{"supplier":{"id":"63000000-0000-4000-8000-000000000001","name":"Test supplier","contact":"Contact","phone":"000","products":"Tofu"},"buyer":"Test kitchen","phone":"000","address":"Test address","delivery_date":"2026-09-15","delivery_window":"morning","notes":"","currency":"KRW","lines":[{"id":"63000000-0000-4000-8000-000000000021","name":"Tofu","quantity":2,"unit":"pack","spec":"500 g","price":2500,"source_ids":["62000000-0000-4000-8000-000000000021"]}]}';
 select sum(quantity) into before_stock from public.kitchen_ingredients;
 select count(*) into before_records from public.shopping_purchase_records;
 r:=public.save_supplier_purchase_request('63000000-0000-4000-8000-000000000011',0,p,'draft');
 r2:=public.save_supplier_purchase_request('63000000-0000-4000-8000-000000000011',0,p,'draft');
 if r<>r2 or (r->>'revision')::int<>1 then raise exception 'DUPLICATE_REQUEST';end if;
 if (select count(*) from public.supplier_purchase_requests)<>1 then raise exception 'DUPLICATE_ROW';end if;
 begin perform public.save_supplier_purchase_request('63000000-0000-4000-8000-000000000011',0,jsonb_set(p,'{notes}','"stale"'),'draft');raise exception 'STALE_ACCEPTED';
 exception when raise_exception then if sqlerrm<>'SUPPLIER_STALE' then raise;end if;end;
 begin perform public.save_supplier_purchase_request('63000000-0000-4000-8000-000000000012',0,jsonb_set(p,'{lines,0,quantity}','0'),'draft');raise exception 'ZERO_ACCEPTED';
 exception when raise_exception then if sqlerrm<>'SUPPLIER_INVALID' then raise;end if;end;
 begin perform public.save_supplier_purchase_request('63000000-0000-4000-8000-000000000012',0,jsonb_set(p,'{lines,0,source_ids}','["62000000-0000-4000-8000-000000000099"]'),'draft');raise exception 'FOREIGN_SOURCE_ACCEPTED';
 exception when raise_exception then if sqlerrm<>'SUPPLIER_SOURCE_NOT_FOUND' then raise;end if;end;
 begin perform public.save_supplier_purchase_request('63000000-0000-4000-8000-000000000011',1,p,'received');raise exception 'SKIPPED_STATE';
 exception when raise_exception then if sqlerrm<>'SUPPLIER_INVALID_TRANSITION' then raise;end if;end;
 r:=public.save_supplier_purchase_request('63000000-0000-4000-8000-000000000011',1,p,'sent');
 r2:=public.save_supplier_purchase_request('63000000-0000-4000-8000-000000000011',1,p,'sent');
 if r<>r2 then raise exception 'STATUS_REPLAY_CHANGED';end if;
 begin perform public.save_supplier_purchase_request('63000000-0000-4000-8000-000000000011',2,jsonb_set(p,'{notes}','"changed after sending"'),'sent');raise exception 'FROZEN_CHANGED';
 exception when raise_exception then if sqlerrm<>'SUPPLIER_FROZEN' then raise;end if;end;
 perform public.save_supplier_purchase_request('63000000-0000-4000-8000-000000000011',2,p,'accepted');
 perform public.save_supplier_purchase_request('63000000-0000-4000-8000-000000000011',3,p,'received');
 if (select sum(quantity) from public.kitchen_ingredients)<>before_stock then raise exception 'REQUEST_CHANGED_STOCK';end if;
 if (select count(*) from public.shopping_purchase_records)<>before_records then raise exception 'REQUEST_CHARGED';end if;
 begin update public.supplier_purchase_requests set status='draft';raise exception 'DIRECT_STATUS_WRITE';
 exception when insufficient_privilege then null;end;
 begin update public.shopping_suppliers set owner_id='62000000-0000-4000-8000-000000000002';raise exception 'OWNER_MUTABLE';
 exception when insufficient_privilege then null;end;
end;$$;
reset role;
select set_config('request.jwt.claim.sub','62000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$ declare n int;begin
 if exists(select 1 from public.shopping_suppliers) or exists(select 1 from public.supplier_purchase_requests) then raise exception 'SUPPLIER_PRIVACY_LEAK';end if;
 delete from public.supplier_purchase_requests;get diagnostics n=row_count;
 if n<>0 then raise exception 'FOREIGN_DELETE';end if;
 begin insert into public.shopping_suppliers(id,owner_id,name) values('63000000-0000-4000-8000-000000000099','62000000-0000-4000-8000-000000000001','Spoof');raise exception 'SUPPLIER_OWNER_SPOOF';
 exception when insufficient_privilege then null;end;
end;$$;
reset role;
do $$ begin
 if has_function_privilege('anon','public.save_supplier_purchase_request(uuid,bigint,jsonb,text)','execute') then raise exception 'SUPPLIER_ANON_RPC';end if;
 if has_table_privilege('anon','public.shopping_suppliers','select') then raise exception 'SUPPLIER_ANON_TABLE';end if;
 if has_table_privilege('authenticated','public.supplier_purchase_requests','insert') then raise exception 'SUPPLIER_DIRECT_INSERT';end if;
end;$$;
-- Account deletion cascades both new tables; only local fixtures are removed.
delete from auth.users where id='62000000-0000-4000-8000-000000000001';
do $$ begin
 if exists(select 1 from public.shopping_suppliers) or exists(select 1 from public.supplier_purchase_requests) then raise exception 'SUPPLIER_DELETE_LEAK';end if;
end;$$;
select 'SUPPLIER_REQUEST_CONTRACT_PASSED' as result;
