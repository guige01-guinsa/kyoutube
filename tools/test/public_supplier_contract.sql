-- All accounts, seeds and schema changes are rolled back by the runner.
insert into auth.users(id,email) values
 ('99000000-0000-4000-8000-000000000001','public-admin@example.test'),
 ('99000000-0000-4000-8000-000000000002','public-buyer@example.test');
insert into public.profiles(id,role) values('99000000-0000-4000-8000-000000000001','admin')
 on conflict(id) do update set role='admin';
create function pg_temp.login_ref(u text,aal text default 'aal1') returns void language plpgsql as $$ begin
 perform set_config('request.jwt.claim.sub',u,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated','aal',aal)::text,true);
end; $$;
create function pg_temp.ref_data(host text default 'supplier-test.example.com') returns jsonb language sql as $$
 select jsonb_build_object('name','Test Supplier','website','https://'||host||'/','phone','',
 'products','Onion','categories',jsonb_build_array('produce'),'delivery_regions',jsonb_build_array('전국'),
 'shipping_note','Parcel delivery; confirm island exclusions','business_kind','store',
 'source_urls',jsonb_build_array('https://supplier-test.example.com/delivery'),
 'checked_on',((now() at time zone 'Asia/Seoul')::date)::text,'status','candidate'); $$;
select pg_temp.login_ref('99000000-0000-4000-8000-000000000002');
set local role authenticated;
do $$ begin
 if (select count(*) from public.search_public_supplier_listings())<>20 then raise exception 'SEED_NOT_VISIBLE';end if;
 if exists(select 1 from public.search_public_supplier_listings('','meat') where not 'meat'=any(categories)) then raise exception 'CATEGORY_FILTER';end if;
 if (select count(*) from public.search_public_supplier_listings('미트박스'))<>1 then raise exception 'SEARCH_FAILED';end if;
 if (select count(*) from public.search_public_supplier_listings('전국'))<>20 then raise exception 'DELIVERY_TEXT_SEARCH';end if;
 begin perform public.admin_search_public_suppliers();raise exception 'ADMIN_READ_ALLOWED';exception when raise_exception then if sqlerrm<>'ADMIN_REQUIRED' then raise;end if;end;
 begin perform public.admin_save_public_supplier(pg_temp.ref_data(),0);raise exception 'ADMIN_WRITE_ALLOWED';exception when raise_exception then if sqlerrm<>'ADMIN_REQUIRED' then raise;end if;end;
 begin perform public.admin_reserve_supplier_search();raise exception 'ADMIN_SEARCH_ALLOWED';exception when raise_exception then if sqlerrm<>'ADMIN_REQUIRED' then raise;end if;end;
 begin update public.public_supplier_listings set name='Hijack';raise exception 'DIRECT_WRITE_ALLOWED';exception when insufficient_privilege then null;end;
 begin insert into public.shopping_suppliers(id,owner_id,name,public_listing_id) values(gen_random_uuid(),auth.uid(),'Fake',(select id from public.public_supplier_listings limit 1));raise exception 'FORGED_PROVENANCE';exception when insufficient_privilege then null;end;
 begin perform count(*) from public.public_supplier_audit;raise exception 'AUDIT_EXPOSED';exception when insufficient_privilege then null;end;
end; $$;
reset role;
set local role anon;
do $$ begin
 begin perform count(*) from public.public_supplier_listings;raise exception 'ANON_READ';exception when insufficient_privilege then null;end;
 begin perform public.search_public_supplier_listings();raise exception 'ANON_RPC';exception when insufficient_privilege then null;end;
end; $$;
reset role;
select pg_temp.login_ref('99000000-0000-4000-8000-000000000001');
set local role authenticated;
do $$ begin
 begin perform public.admin_search_public_suppliers();raise exception 'MFA_BYPASS';exception when raise_exception then if sqlerrm<>'ADMIN_MFA_REQUIRED' then raise;end if;end;
end; $$;
reset role;
select pg_temp.login_ref('99000000-0000-4000-8000-000000000001','aal2');
set local role authenticated;
select public.admin_save_public_supplier(pg_temp.ref_data()||'{"id":"99100000-0000-4000-8000-000000000001"}',0)->>'status';
do $$ declare l jsonb; begin
 if (select count(*) from public.admin_search_public_suppliers('Test','candidate'))<>1 then raise exception 'CANDIDATE_MISSING';end if;
 if (select count(*) from public.admin_match_public_suppliers(array['https://www.supplier-test.example.com/path']))<>1 then raise exception 'EXISTING_DOMAIN_NOT_MATCHED';end if;
 if exists(select 1 from public.public_supplier_listings where name='Test Supplier') then raise exception 'CANDIDATE_PUBLIC';end if;
 select to_jsonb(x) into l from public.admin_search_public_suppliers('Test') x;
 begin perform public.admin_save_public_supplier(l||'{"status":"published"}',1,false);raise exception 'UNREVIEWED_PUBLIC';exception when raise_exception then if sqlerrm<>'SOURCE_REVIEW_REQUIRED' then raise;end if;end;
 begin perform public.admin_save_public_supplier(l||jsonb_build_object('status','published','checked_on',(current_date-100)::text),1,true);raise exception 'STALE_SOURCE';exception when raise_exception then if sqlerrm<>'SOURCE_REVIEW_REQUIRED' then raise;end if;end;
 begin perform public.admin_save_public_supplier(l,0);raise exception 'LOST_UPDATE';exception when raise_exception then if sqlerrm<>'LISTING_CONFLICT' then raise;end if;end;
 begin perform public.admin_save_public_supplier(pg_temp.ref_data('www.supplier-test.example.com'),0);raise exception 'DUPLICATE_HOST';exception when unique_violation then null;end;
 begin perform public.admin_save_public_supplier(pg_temp.ref_data('private.internal'),0);raise exception 'PRIVATE_URL';exception when check_violation then null;end;
 begin perform public.admin_save_public_supplier(pg_temp.ref_data()||'{"id":"99100000-0000-4000-8000-000000000003","website":"https://user:password@example.com"}',0);raise exception 'URL_CREDENTIALS';exception when check_violation then null;end;
 perform public.admin_publish_public_suppliers(jsonb_build_array(jsonb_build_object('id',l->>'id','revision',1)),true);
 begin perform public.admin_publish_public_suppliers(jsonb_build_array(jsonb_build_object('id',l->>'id','revision',2),jsonb_build_object('id',l->>'id','revision',2)),true);raise exception 'NONATOMIC_PUBLISH';exception when raise_exception then if sqlerrm<>'LISTING_CONFLICT' then raise;end if;end;
 if (select revision from public.admin_search_public_suppliers('Test'))<>2 then raise exception 'PARTIAL_BATCH';end if;
 perform public.admin_reserve_supplier_search();
 begin perform public.admin_reserve_supplier_search();raise exception 'UNBOUNDED_SEARCH';exception when raise_exception then if sqlerrm<>'SEARCH_QUOTA' then raise;end if;end;
end; $$;
reset role;
select pg_temp.login_ref('99000000-0000-4000-8000-000000000002');
set local role authenticated;
do $$ declare a jsonb; b jsonb; begin
 a:=public.import_public_supplier_listing('99100000-0000-4000-8000-000000000001');
 update public.shopping_suppliers set memo='Private note',is_favorite=true where id=(a->>'id')::uuid;
 b:=public.import_public_supplier_listing('99100000-0000-4000-8000-000000000001');
 if a->>'id'<>b->>'id' or b->>'memo'<>'Private note' or b->>'is_favorite'<>'true' then raise exception 'IMPORT_NOT_IDEMPOTENT';end if;
 if b->>'catalog_supplier_id' is not null then raise exception 'REFERENCE_BECAME_OFFER';end if;
 if (select id from public.search_public_supplier_listings() limit 1)<>'99100000-0000-4000-8000-000000000001' then raise exception 'MY_SUPPLIER_PRIORITY';end if;
end; $$;
reset role;
select pg_temp.login_ref('99000000-0000-4000-8000-000000000001','aal2');
set local role authenticated;
select public.admin_save_public_supplier((select to_jsonb(x)||'{"status":"hidden"}' from public.admin_search_public_suppliers('Test') x),2)->>'status';
reset role;
select pg_temp.login_ref('99000000-0000-4000-8000-000000000002');
set local role authenticated;
do $$ begin
 if exists(select 1 from public.search_public_supplier_listings('Test')) then raise exception 'HIDDEN_LEAK';end if;
 begin perform public.import_public_supplier_listing('99100000-0000-4000-8000-000000000001');raise exception 'HIDDEN_IMPORTED';exception when raise_exception then if sqlerrm<>'LISTING_NOT_FOUND' then raise;end if;end;
 if not exists(select 1 from public.shopping_suppliers where name='Test Supplier') then raise exception 'PRIVATE_HISTORY_DELETED';end if;
end; $$;
reset role;
do $$ begin
 if (select count(*) from public.public_supplier_audit where listing_id='99100000-0000-4000-8000-000000000001')<>3 then raise exception 'MISSING_AUDIT';end if;
end; $$;
select 'Public supplier contract passed: visibility, admin MFA, URL checks, duplicates, atomic publish, concurrency, quota, private import and audit.';
