-- Runs only inside the local test transaction. No production data or accounts.
insert into auth.users(id,email) values
 ('98000000-0000-4000-8000-000000000001','catalog-seller-a@example.test'),
 ('98000000-0000-4000-8000-000000000002','catalog-seller-b@example.test'),
 ('98000000-0000-4000-8000-000000000003','catalog-buyer@example.test'),
 ('98000000-0000-4000-8000-000000000004','catalog-other@example.test');
insert into public.member_entitlements(user_id,plan_code,status,source,started_at,valid_until)
 values('98000000-0000-4000-8000-000000000003','business_monthly','active','admin',now(),now()+interval '1 day')
 on conflict(user_id) do update set plan_code='business_monthly',status='active',valid_until=excluded.valid_until;
create function pg_temp.login_as(u text) returns void language plpgsql as $$ begin
 perform set_config('request.jwt.claim.sub',u,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
end; $$;
select pg_temp.login_as('98000000-0000-4000-8000-000000000001');
set local role authenticated;
select public.save_supplier_business('{"id":"98100000-0000-4000-8000-000000000001","name":"Z Supplier","contact":"A","phone":"01000000000","region":"서울","delivery_regions":["서울"],"address":"","website":"","description":"","currency":"KRW","shipping_fee":1000,"minimum_order":0,"published":false,"verified":true}',0)->>'revision';
do $$ begin
 if (select verified from public.supplier_businesses where id='98100000-0000-4000-8000-000000000001') then raise exception 'SELF_VERIFIED'; end if;
 begin update public.supplier_businesses set verified=true; raise exception 'DIRECT_WRITE_ALLOWED'; exception when insufficient_privilege then null; end;
 begin perform public.save_supplier_business((select to_jsonb(b)||'{"published":true}' from public.supplier_businesses b where owner_id=auth.uid()),1); raise exception 'PUBLISHED_WITHOUT_IMAGE'; exception when raise_exception then if sqlerrm<>'CATALOG_PRODUCT_IMAGE_REQUIRED' then raise;end if;end;
end; $$;
reset role;
insert into storage.objects(bucket_id,name) values('supplier-products','98000000-0000-4000-8000-000000000001/98100000-0000-4000-8000-000000000001/98200000-0000-4000-8000-000000000001.jpg');
set local role authenticated;
select public.save_supplier_catalog_product('{"id":"98300000-0000-4000-8000-000000000001","supplier_id":"98100000-0000-4000-8000-000000000001","name":"Onion","category":"produce","subcategory":"vegetables","aliases":"양파","brand":"Test","origin":"domestic","country":"KR","storage":"ambient","description":"","image_path":"98000000-0000-4000-8000-000000000001/98100000-0000-4000-8000-000000000001/98200000-0000-4000-8000-000000000001.jpg","sale_unit":"box","content_quantity":5,"content_unit":"kg","minimum_packs":1,"price":10000,"price_valid_until":"2099-01-01","tax":"included","active":true}',0)->>'revision';
do $$ begin
 begin perform public.save_supplier_catalog_product((select to_jsonb(p)||'{"content_quantity":0}' from public.supplier_catalog_products p where supplier_id='98100000-0000-4000-8000-000000000001'),1);raise exception 'ZERO_CONTENT';exception when check_violation then null;end;
 begin perform public.save_supplier_catalog_product((select to_jsonb(p)||'{"price_valid_until":null}' from public.supplier_catalog_products p where supplier_id='98100000-0000-4000-8000-000000000001'),1);raise exception 'UNDATED_PRICE';exception when check_violation then null;end;
 begin perform public.save_supplier_business((select to_jsonb(b)||'{"currency":"USD"}' from public.supplier_businesses b where owner_id=auth.uid()),1);raise exception 'PRICE_CURRENCY_REINTERPRETED';exception when raise_exception then if sqlerrm<>'CATALOG_CURRENCY_WITH_PRICES' then raise;end if;end;
end; $$;
reset role;
select pg_temp.login_as('98000000-0000-4000-8000-000000000003');
set local role authenticated;
do $$ begin
 if jsonb_array_length(public.search_supplier_catalog())<>0 then raise exception 'DRAFT_LEAK';end if;
 if exists(select 1 from storage.objects where bucket_id='supplier-products') then raise exception 'PRIVATE_IMAGE_LEAK';end if;
 begin perform public.save_supplier_catalog_product('{"id":"98300000-0000-4000-8000-000000000001","supplier_id":"98100000-0000-4000-8000-000000000001"}',1);raise exception 'FOREIGN_PRODUCT_EDIT';exception when raise_exception then if sqlerrm<>'CATALOG_NOT_FOUND' then raise;end if;end;
end; $$;
reset role;
select pg_temp.login_as('98000000-0000-4000-8000-000000000001');
set local role authenticated;
select public.save_supplier_business((select to_jsonb(b)||'{"published":true}' from public.supplier_businesses b where owner_id=auth.uid()),1)->>'revision';
do $$ begin
 begin perform public.save_supplier_business((select to_jsonb(b) from public.supplier_businesses b where owner_id=auth.uid()),1);raise exception 'STALE_WRITE';exception when raise_exception then if sqlerrm<>'CATALOG_STALE' then raise;end if;end;
end; $$;
reset role;
insert into public.supplier_businesses(id,owner_id,name,contact,phone,region,delivery_regions,published)
 values('98100000-0000-4000-8000-000000000002','98000000-0000-4000-8000-000000000002','A Supplier','B','01000000001','부산',array['전국'],true);
insert into public.supplier_catalog_products(id,supplier_id,name,category,subcategory,origin,image_path,sale_unit,content_quantity,content_unit)
 values('98300000-0000-4000-8000-000000000002','98100000-0000-4000-8000-000000000002','Onion','produce','vegetables','imported','fixture-b.jpg','box',10,'kg');
select pg_temp.login_as('98000000-0000-4000-8000-000000000003');
set local role authenticated;
do $$ declare a jsonb;b jsonb;r jsonb;payload jsonb; begin
 a:=public.import_catalog_supplier('98100000-0000-4000-8000-000000000001');
 b:=public.import_catalog_supplier('98100000-0000-4000-8000-000000000001');
 if a->>'id'<>b->>'id' then raise exception 'DUPLICATE_PERSONAL_SUPPLIER';end if;
 begin insert into public.shopping_suppliers(id,name,catalog_supplier_id) values(gen_random_uuid(),'Forged','98100000-0000-4000-8000-000000000002');raise exception 'FORGED_CATALOG_LINK';exception when insufficient_privilege then null;end;
 update public.shopping_suppliers set memo='Private note',is_favorite=true where id=(a->>'id')::uuid;
 b:=public.import_catalog_supplier('98100000-0000-4000-8000-000000000001');
 if b->>'memo'<>'Private note' or (b->>'is_favorite')::boolean is not true then raise exception 'PRIVATE_PREFERENCES_LOST';end if;
 if public.search_supplier_catalog(p_query=>'Onion')->0->'supplier'->>'id'<>'98100000-0000-4000-8000-000000000001' then raise exception 'MY_SUPPLIER_NOT_FIRST';end if;
 if jsonb_array_length(public.search_supplier_catalog(p_query=>'양파',p_category=>'produce',p_region=>'서울',p_origin=>'domestic',p_filters=>'{"priced":true}'))<>1 then raise exception 'FILTERS_FAILED';end if;
 if jsonb_array_length(public.search_supplier_catalog(p_query=>'양파',p_region=>'부산'))<>0 then raise exception 'DELIVERY_REGION_IGNORED';end if;
 if jsonb_array_length(public.search_supplier_catalog(p_filters=>'{"verified":true}'))<>0 then raise exception 'VERIFICATION_FILTER';end if;
 if jsonb_array_length(public.get_supplier_catalog_offers(array['98300000-0000-4000-8000-000000000001'::uuid]))<>1 then raise exception 'FRESH_OFFERS_FAILED';end if;
 payload:=jsonb_build_object('supplier',jsonb_build_object('id',a->>'id','name',a->>'name','contact',a->>'contact','phone',a->>'phone','products',''),'buyer','Test buyer','phone','','address','','delivery_date','','delivery_window','','notes','','currency','KRW','lines','[{"id":"98400000-0000-4000-8000-000000000001","name":"Onion","quantity":1,"unit":"box","spec":"5 kg","price":10000,"source_ids":[]}]'::jsonb);
 r:=public.save_supplier_purchase_request('98500000-0000-4000-8000-000000000001',0,payload,'draft');
 if r->>'catalog_supplier_id'<>'98100000-0000-4000-8000-000000000001' then raise exception 'REQUEST_NOT_LINKED';end if;
 begin perform public.rate_catalog_supplier('98500000-0000-4000-8000-000000000001',5);raise exception 'UNRECEIVED_REVIEW';exception when raise_exception then if sqlerrm<>'CATALOG_RECEIPT_REQUIRED' then raise;end if;end;
 r:=public.save_supplier_purchase_request((r->>'id')::uuid,(r->>'revision')::bigint,payload,'sent');
 delete from public.shopping_suppliers where id=(a->>'id')::uuid;
 r:=public.save_supplier_purchase_request((r->>'id')::uuid,(r->>'revision')::bigint,payload,'accepted');
 if r->>'catalog_supplier_id' is distinct from '98100000-0000-4000-8000-000000000001' then raise exception 'HISTORY_CATALOG_LINK_LOST';end if;
 r:=public.save_supplier_purchase_request((r->>'id')::uuid,(r->>'revision')::bigint,payload,'received');
 perform public.rate_catalog_supplier((r->>'id')::uuid,5);
 perform public.rate_catalog_supplier((r->>'id')::uuid,4);
 if public.catalog_supplier_rating('98100000-0000-4000-8000-000000000001')->>'review_count'<>'1' then raise exception 'DUPLICATE_REVIEW';end if;
 if (public.catalog_supplier_rating('98100000-0000-4000-8000-000000000001')->>'rating')::numeric<>4 then raise exception 'RATING_NOT_UPDATED';end if;
 if jsonb_array_length(public.search_supplier_catalog(p_filters=>'{"rated":true}'))<>1 then raise exception 'RATING_FILTER';end if;
end; $$;
reset role;
select pg_temp.login_as('98000000-0000-4000-8000-000000000004');
set local role authenticated;
do $$ begin
 if jsonb_array_length(public.search_supplier_catalog())<>2 then raise exception 'FREE_MEMBER_CANNOT_FIND_PUBLIC_SUPPLIERS';end if;
 if (select count(*) from public.supplier_businesses where published)<>2 then raise exception 'FREE_MEMBER_CANNOT_READ_PUBLIC_BUSINESSES';end if;
 if (select count(*) from public.supplier_catalog_products)<>2 then raise exception 'FREE_MEMBER_CANNOT_READ_PUBLIC_PRODUCTS';end if;
 if not exists(select 1 from storage.objects where bucket_id='supplier-products' and name='98000000-0000-4000-8000-000000000001/98100000-0000-4000-8000-000000000001/98200000-0000-4000-8000-000000000001.jpg') then raise exception 'FREE_MEMBER_CANNOT_READ_PUBLIC_IMAGE';end if;
 begin perform public.save_supplier_catalog_product('{"id":"98300000-0000-4000-8000-000000000001","supplier_id":"98100000-0000-4000-8000-000000000001"}',1);raise exception 'FOREIGN_PUBLIC_PRODUCT_EDIT';exception when raise_exception then if sqlerrm<>'CATALOG_NOT_FOUND' then raise;end if;end;
 if exists(select 1 from public.shopping_suppliers) or exists(select 1 from public.supplier_purchase_requests) then raise exception 'BUYER_DATA_LEAK';end if;
 begin perform public.rate_catalog_supplier('98500000-0000-4000-8000-000000000001',1);raise exception 'FOREIGN_REVIEW';exception when raise_exception then if sqlerrm<>'CATALOG_RECEIPT_REQUIRED' then raise;end if;end;
end; $$;
reset role;
do $$ begin
 if has_table_privilege('anon','public.supplier_businesses','select') or has_function_privilege('anon','public.search_supplier_catalog(text,text,text,text,text,text,int,int,jsonb)','execute') then raise exception 'ANON_ACCESS';end if;
 if has_table_privilege('authenticated','public.supplier_buyer_reviews','insert') then raise exception 'DIRECT_REVIEW_WRITE';end if;
end; $$;
select 'SUPPLIER_CATALOG_CONTRACT_PASSED' as result;
