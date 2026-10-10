insert into auth.users(id,email) values
 ('62000000-0000-4000-8000-000000000001','shopping-a@example.invalid'),
 ('62000000-0000-4000-8000-000000000002','shopping-b@example.invalid');
insert into public.profiles(id,role) values
 ('62000000-0000-4000-8000-000000000001','user'),
 ('62000000-0000-4000-8000-000000000002','user') on conflict(id) do nothing;
insert into public.kitchen_shopping_lists(id,owner_id,title) values
 ('62000000-0000-4000-8000-000000000011','62000000-0000-4000-8000-000000000001','Recipe A'),
 ('62000000-0000-4000-8000-000000000012','62000000-0000-4000-8000-000000000001','Recipe B'),
 ('62000000-0000-4000-8000-000000000013','62000000-0000-4000-8000-000000000001','Conflict A'),
 ('62000000-0000-4000-8000-000000000014','62000000-0000-4000-8000-000000000001','Conflict B'),
 ('62000000-0000-4000-8000-000000000015','62000000-0000-4000-8000-000000000001','Precision');
select set_config('app.kitchen_create_rpc','1',true);
insert into public.kitchen_shopping_items(id,list_id,owner_id,name,normalized_name,ingredient_text,quantity,unit,review_status,reviewed_at) values
 ('62000000-0000-4000-8000-000000000021','62000000-0000-4000-8000-000000000011','62000000-0000-4000-8000-000000000001','Tofu','tofu','Original tofu 1 kg',1,'kg','confirmed',now()),
 ('62000000-0000-4000-8000-000000000022','62000000-0000-4000-8000-000000000012','62000000-0000-4000-8000-000000000001','Tofu','tofu','Original tofu 500 g',500,'g','confirmed',now()),
 ('62000000-0000-4000-8000-000000000023','62000000-0000-4000-8000-000000000013','62000000-0000-4000-8000-000000000001','Egg','egg','Original egg 1 ea',1,'ea','confirmed',now()),
 ('62000000-0000-4000-8000-000000000024','62000000-0000-4000-8000-000000000014','62000000-0000-4000-8000-000000000001','Egg','egg','Original egg 1 ea',1,'ea','confirmed',now()),
 ('62000000-0000-4000-8000-000000000025','62000000-0000-4000-8000-000000000015','62000000-0000-4000-8000-000000000001','Tofu','tofu','Tofu 1.23 g',1.23,'g','confirmed',now());
select set_config('request.jwt.claim.sub','62000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
insert into public.shopping_product_favorites(ingredient_name,unit,product_name,product_url,pack_quantity)
 values('Tofu','g','Tofu 300 g','https://shop.example.com/tofu',300);
-- User A's own update/upsert should preserve one favorite.
insert into public.shopping_product_favorites(ingredient_name,unit,product_name,product_url,pack_quantity)
 values(' tofu ','g','Tofu 400 g','https://shop.example.com/tofu',400)
 on conflict(owner_id,ingredient_key,unit) do update set pack_quantity=excluded.pack_quantity;
do $$ declare p jsonb; id1 uuid; id2 uuid; extra_list uuid; extra_item uuid;begin
 if (select count(*) from public.shopping_product_favorites)<>1 then raise exception 'FAVORITE_DUPLICATE';end if;
 p:='{"name":"Tofu","quantity":500,"unit":"g","currency":"KRW","paid_amount":4000,"product_name":"Tofu pack","items":[{"id":"62000000-0000-4000-8000-000000000021","revision":0,"quantity":300},{"id":"62000000-0000-4000-8000-000000000022","revision":0,"quantity":200}]}';
 id1:=public.record_shopping_purchase('62000000-0000-4000-8000-000000000031',p);
 id2:=public.record_shopping_purchase('62000000-0000-4000-8000-000000000031',p);
 if id1<>id2 or (select count(*) from public.shopping_purchase_records)<>1 then raise exception 'DUPLICATE_PURCHASE';end if;
 if exists(select 1 from public.kitchen_ingredients) then raise exception 'PREMATURE_STOCK';end if;
 if (select sum(quantity) from public.kitchen_shopping_items where status='purchased')<>500 then raise exception 'WRONG_ALLOCATION';end if;
 if (select ingredient_text from public.kitchen_shopping_items where id='62000000-0000-4000-8000-000000000021')<>'Original tofu 1 kg' then raise exception 'ORIGINAL_CHANGED';end if;
 begin perform public.record_shopping_purchase('62000000-0000-4000-8000-000000000031',jsonb_set(p,'{paid_amount}','5000'));raise exception 'PAYLOAD_REUSE';
 exception when raise_exception then if sqlerrm<>'SHOPPING_REQUEST_CONFLICT' then raise;end if;end;
 begin perform public.record_shopping_purchase('62000000-0000-4000-8000-000000000032',p);raise exception 'REBOUGHT';
 exception when raise_exception then if sqlerrm<>'SHOPPING_STALE' then raise;end if;end;
 update public.shopping_purchase_records set paid_amount=4500 where id=id1;
 if (select paid_amount from public.shopping_purchase_records where id=id1)<>4500 then raise exception 'AMOUNT_EDIT';end if;
 begin update public.shopping_purchase_records set quantity=999 where id=id1;raise exception 'QUANTITY_BYPASS';
 exception when insufficient_privilege then null;end;
 perform public.complete_kitchen_shopping_list('62000000-0000-4000-8000-000000000011','62000000-0000-4000-8000-000000000041');
 perform public.complete_kitchen_shopping_list('62000000-0000-4000-8000-000000000012','62000000-0000-4000-8000-000000000042');
 perform public.complete_kitchen_shopping_list('62000000-0000-4000-8000-000000000011','62000000-0000-4000-8000-000000000041');
 if (select sum(quantity) from public.kitchen_ingredients)<>500 then raise exception 'DOUBLE_STOCK';end if;
 -- Existing kilogram inventory must retain small gram purchases exactly.
 update public.kitchen_ingredients set quantity=0.5,unit='kg' where normalized_name='tofu';
 extra_list:='62000000-0000-4000-8000-000000000015';
 extra_item:='62000000-0000-4000-8000-000000000025';
 perform public.record_shopping_purchase('62000000-0000-4000-8000-000000000044',jsonb_build_object(
   'name','Tofu','quantity',1.23,'unit','g','currency','KRW','paid_amount',10,'product_name','Small pack',
   'items',jsonb_build_array(jsonb_build_object('id',extra_item,'revision',0,'quantity',1.23))));
 perform public.complete_kitchen_shopping_list(extra_list,'62000000-0000-4000-8000-000000000045');
 if (select quantity from public.kitchen_ingredients where normalized_name='tofu')<>0.50123 then raise exception 'METRIC_STOCK_ROUNDING';end if;
 p:='{"name":"Egg","quantity":1,"unit":"ea","currency":"USD","paid_amount":2,"product_name":"Eggs","items":[{"id":"62000000-0000-4000-8000-000000000023","revision":0,"quantity":0.5},{"id":"62000000-0000-4000-8000-000000000024","revision":999,"quantity":0.5}]}';
 begin perform public.record_shopping_purchase('62000000-0000-4000-8000-000000000033',p);raise exception 'STALE_ACCEPTED';
 exception when raise_exception then if sqlerrm<>'SHOPPING_STALE' then raise;end if;end;
 if exists(select 1 from public.kitchen_shopping_items where name='Egg' and status<>'pending') then raise exception 'PARTIAL_WRITE';end if;
 p:=jsonb_set(p,'{items,1,revision}','0');
 begin perform public.record_shopping_purchase('62000000-0000-4000-8000-000000000034',jsonb_set(p,'{quantity}','1.1'));raise exception 'SUM_ACCEPTED';
 exception when raise_exception then if sqlerrm<>'SHOPPING_ALLOCATION_MISMATCH' then raise;end if;end;
 perform public.record_shopping_purchase('62000000-0000-4000-8000-000000000034',p);
end;$$;
reset role;
select set_config('request.jwt.claim.sub','62000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"62000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$ declare n integer;begin
 if exists(select 1 from public.shopping_product_favorites) or exists(select 1 from public.shopping_purchase_records) then raise exception 'CROSS_ACCOUNT_LEAK';end if;
 update public.shopping_purchase_records set paid_amount=1;get diagnostics n=row_count;
 if n<>0 then raise exception 'CROSS_ACCOUNT_WRITE';end if;
 begin insert into public.shopping_product_favorites(owner_id,ingredient_name,unit,product_name,product_url)
 values('62000000-0000-4000-8000-000000000001','Bad','g','Bad','https://shop.example.com/bad');raise exception 'OWNER_SPOOF';
 exception when insufficient_privilege then null;end;
 begin perform public.record_shopping_purchase('62000000-0000-4000-8000-000000000031',
 '{"name":"Tofu","quantity":1,"unit":"g","currency":"KRW","paid_amount":1,"product_name":"","items":[{"id":"62000000-0000-4000-8000-000000000021","revision":0,"quantity":1}]}');raise exception 'FOREIGN_PURCHASE';
 exception when raise_exception then if sqlerrm<>'SHOPPING_NOT_FOUND' then raise;end if;end;
end;$$;
reset role;
do $$ begin
 if has_function_privilege('anon','public.record_shopping_purchase(uuid,jsonb)','execute') then raise exception 'ANON_RPC';end if;
 if has_table_privilege('authenticated','public.shopping_purchase_records','insert') then raise exception 'DIRECT_RECORD_INSERT';end if;
 if has_table_privilege('anon','public.shopping_product_favorites','select') then raise exception 'ANON_READ';end if;
end;$$;
select 'SHOPPING_ASSISTANT_CONTRACT_PASSED' as result;
