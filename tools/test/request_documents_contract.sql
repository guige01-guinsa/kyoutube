insert into auth.users(id,email) values
 ('61000000-0000-4000-8000-000000000001','document-a@example.test'),
 ('61000000-0000-4000-8000-000000000002','document-b@example.test');
create function pg_temp.doc_login(u text,anonymous boolean default false) returns void language plpgsql as $$ begin
 perform set_config('request.jwt.claim.sub',u,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated','is_anonymous',anonymous)::text,true);
end; $$;
select pg_temp.doc_login('61000000-0000-4000-8000-000000000001');
-- Emulate the Storage API transaction flag for synthetic metadata only; rolled back.
select set_config('storage.allow_delete_query','true',true);
set local role authenticated;
insert into public.shopping_suppliers(id,name) values('61000000-0000-4000-8000-000000000003','Document supplier');
insert into storage.objects(bucket_id,name,metadata) values
 ('purchase-business-documents','61000000-0000-4000-8000-000000000001/61000000-0000-4000-8000-000000000010.png','{"mimetype":"image/png","size":1000}');
create function pg_temp.document_data() returns jsonb language sql as $$ select '{"supplier":{"id":"61000000-0000-4000-8000-000000000003","name":"Document supplier","contact":"","phone":"","products":""},"buyer":"Example kitchen","phone":"","address":"","delivery_date":"","delivery_window":"","notes":"","currency":"KRW","business_registrations":{"buyer":{"number":"123-45-67890","image_path":"61000000-0000-4000-8000-000000000001/61000000-0000-4000-8000-000000000010.png"},"supplier":{"number":"234-56-78901","image_path":""}},"lines":[{"id":"61000000-0000-4000-8000-000000000020","name":"Tofu","quantity":2,"unit":"pack","spec":"","price":2500,"source_ids":[]},{"id":"61000000-0000-4000-8000-000000000021","name":"Onion","quantity":1,"unit":"kg","spec":"","price":null,"source_ids":[]}]}'::jsonb; $$;
do $$ declare p jsonb:=pg_temp.document_data();r jsonb; j jsonb;n int;begin
 r:=public.save_supplier_purchase_request('61000000-0000-4000-8000-000000000011',0,p,'draft');
 perform public.save_supplier_purchase_request('61000000-0000-4000-8000-000000000011',0,p,'draft');
 if (select count(*) from public.supplier_request_events)<>1 then raise exception 'IDEMPOTENCE_EVENT';end if;
 begin perform public.save_supplier_purchase_request('61000000-0000-4000-8000-000000000011',1,jsonb_set(p,'{business_registrations,buyer,number}','"invalid"'),'draft');raise exception 'BAD_NUMBER_ACCEPTED';exception when raise_exception then if sqlerrm<>'REQUEST_BUSINESS_INVALID' then raise;end if;end;
 begin perform public.save_supplier_purchase_request('61000000-0000-4000-8000-000000000011',1,jsonb_set(p,'{business_registrations,buyer,image_path}','"61000000-0000-4000-8000-000000000002/61000000-0000-4000-8000-000000000010.png"'),'draft');raise exception 'FOREIGN_IMAGE_ACCEPTED';exception when raise_exception then if sqlerrm<>'REQUEST_BUSINESS_IMAGE_INVALID' then raise;end if;end;
 begin perform public.save_supplier_purchase_request('61000000-0000-4000-8000-000000000011',1,jsonb_set(p,'{business_registrations,buyer,image_path}','"61000000-0000-4000-8000-000000000001/61000000-0000-4000-8000-000000000099.png"'),'draft');raise exception 'MISSING_IMAGE_ACCEPTED';exception when raise_exception then if sqlerrm<>'REQUEST_BUSINESS_IMAGE_INVALID' then raise;end if;end;
 delete from storage.objects where bucket_id='purchase-business-documents';get diagnostics n=row_count;
 if n<>0 then raise exception 'REFERENCED_IMAGE_DELETED';end if;
 update storage.objects set metadata='{}' where bucket_id='purchase-business-documents';get diagnostics n=row_count;
 if n<>0 then raise exception 'IMAGE_OVERWRITTEN';end if;
 p:=jsonb_set(p,'{notes}','"edited"');
 perform public.save_supplier_purchase_request('61000000-0000-4000-8000-000000000011',1,p,'draft');
 perform public.save_supplier_purchase_request('61000000-0000-4000-8000-000000000011',2,p,'sent');
 if (select count(*) from public.supplier_request_events)<>3 then raise exception 'EVENTS_MISSING';end if;
 begin perform public.save_supplier_purchase_request('61000000-0000-4000-8000-000000000011',3,jsonb_set(p,'{business_registrations,buyer,image_path}','""'),'sent');raise exception 'SENT_CERT_CHANGED';exception when raise_exception then if sqlerrm<>'SUPPLIER_FROZEN' then raise;end if;end;
 j:=public.search_purchase_request_ledger(p_query=>'Document supplier');
 if (j->>'total_count')::int<>1 or (j#>>'{totals,0,priced_total}')::numeric<>5000 or (j#>>'{totals,0,unpriced_count}')::int<>1 then raise exception 'LEDGER_TOTALS_INVALID %',j;end if;
 if jsonb_array_length(public.search_purchase_request_ledger(p_offset=>1)->'rows')<>0 then raise exception 'PAGINATION_FAILED';end if;
 if (public.search_purchase_request_ledger(p_status=>'received')->>'total_count')::int<>0 then raise exception 'STATUS_FILTER_FAILED';end if;
 if (public.search_purchase_request_ledger(p_before=>now()-interval '1 day')->>'total_count')::int<>0 then raise exception 'DATE_FILTER_FAILED';end if;
 if (public.search_purchase_request_ledger(p_query=>'%')->>'total_count')::int<>0 then raise exception 'QUERY_WILDCARD_EXPANDED';end if;
 perform public.save_supplier_purchase_request('61000000-0000-4000-8000-000000000011',3,p,'cancelled');
 j:=public.search_purchase_request_ledger();
 if (j#>>'{totals,0,priced_total}')::numeric<>0 or (j#>>'{totals,0,cancelled_count}')::int<>1 then raise exception 'CANCELLED_INCLUDED';end if;
 begin update public.supplier_request_events set event='created';raise exception 'AUDIT_TAMPERED';exception when insufficient_privilege then null;end;
end; $$;
reset role;
-- Separate currencies and exact decimal multiplication, using a second request.
select public.save_supplier_purchase_request('61000000-0000-4000-8000-000000000012',0,
 jsonb_set(jsonb_set(jsonb_set(pg_temp.document_data(),'{currency}','"USD"'),'{lines,0,quantity}','3'),'{lines,0,price}','0.335'),'draft')->>'status' as status;
set local role authenticated;
do $$ declare j jsonb:=public.search_purchase_request_ledger(); begin
 if jsonb_array_length(j->'totals')<>2 or (j#>>'{totals,1,priced_total}')::numeric<>1.01 then raise exception 'CURRENCY_OR_ROUNDING_FAILED %',j;end if;
end; $$;
reset role;
select pg_temp.doc_login('61000000-0000-4000-8000-000000000002');
set local role authenticated;
do $$ begin
 if (public.search_purchase_request_ledger()->>'total_count')::int<>0 or exists(select 1 from public.supplier_request_events) then raise exception 'FOREIGN_LEDGER_VISIBLE';end if;
 if exists(select 1 from storage.objects where bucket_id='purchase-business-documents') then raise exception 'FOREIGN_CERT_VISIBLE';end if;
 begin insert into storage.objects(bucket_id,name) values('purchase-business-documents','61000000-0000-4000-8000-000000000001/61000000-0000-4000-8000-000000000098.png');raise exception 'FOREIGN_UPLOAD';exception when insufficient_privilege then null;end;
end; $$;
reset role;
select pg_temp.doc_login('61000000-0000-4000-8000-000000000001',true);
set local role authenticated;
do $$ begin
 begin perform public.search_purchase_request_ledger();raise exception 'ANON_LEDGER';exception when raise_exception then if sqlerrm<>'AUTH_REQUIRED' then raise;end if;end;
 if exists(select 1 from public.supplier_request_events) or exists(select 1 from storage.objects where bucket_id='purchase-business-documents') then raise exception 'ANON_CERT_VISIBLE';end if;
end; $$;
reset role;
select pg_temp.doc_login('61000000-0000-4000-8000-000000000001');
set local role authenticated;
delete from public.supplier_purchase_requests where id in ('61000000-0000-4000-8000-000000000011','61000000-0000-4000-8000-000000000012');
do $$ begin
 if exists(select 1 from public.supplier_request_events) then raise exception 'EVENT_DELETE_LEAK';end if;
 if not public.purchase_document_unused('61000000-0000-4000-8000-000000000001/61000000-0000-4000-8000-000000000010.png') then raise exception 'UNUSED_NOT_RELEASED';end if;
end; $$;
reset role;
select 'REQUEST_DOCUMENTS_LEDGER_CONTRACT_PASSED' as result;
