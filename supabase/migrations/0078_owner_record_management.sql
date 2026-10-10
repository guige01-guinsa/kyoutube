-- Explicitly approved owner-only erasure and unit rebasing. No data changes at install time.
begin;
create table public.management_deleted_ids (
 entity text not null, id text not null, owner_id uuid not null references auth.users on delete cascade,
 primary key(entity,id)
);
create table public.management_applied_changes (
 owner_id uuid not null references auth.users on delete cascade, token text not null,
 result jsonb not null, primary key(owner_id,token)
);
alter table public.management_deleted_ids enable row level security;
alter table public.management_applied_changes enable row level security;
revoke all on public.management_deleted_ids,public.management_applied_changes from public,anon,authenticated;
create function public.management_reject_deleted_id() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended(tg_table_name||':'||new.id::text,0));
 if exists(select 1 from public.management_deleted_ids where entity=tg_table_name and id=new.id::text) then raise exception 'MANAGEMENT_DELETED'; end if;
 return new;
end; $$;
revoke all on function public.management_reject_deleted_id() from public,anon,authenticated;
do $$ declare t text; begin
 foreach t in array array['business_records','business_suppliers','business_supplier_products','business_menu_templates','business_stock_items','shopping_suppliers','supplier_catalog_products'] loop
  execute format('create trigger management_reject_deleted_id before insert on public.%I for each row execute function public.management_reject_deleted_id()',t);
 end loop;
end; $$;
create table public.management_deleted_sales (
 owner_id uuid not null references auth.users on delete cascade, request_key text not null,
 primary key(owner_id,request_key)
);
alter table public.management_deleted_sales enable row level security;
revoke all on public.management_deleted_sales from public,anon,authenticated;
create function public.management_reject_sale_replay() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended(new.owner_id::text||':sale:'||new.request_key,0));
 if exists(select 1 from public.management_deleted_sales where owner_id=new.owner_id and request_key=new.request_key) then raise exception 'MANAGEMENT_DELETED'; end if;
 return new;
end; $$;
revoke all on function public.management_reject_sale_replay() from public,anon,authenticated;
create trigger management_reject_sale_replay before insert on public.chef_sales for each row execute function public.management_reject_sale_replay();

-- NULL token = preview. A supplied token is compared with the complete locked dependency state.
create function public.owner_record_manage(p_kind text,p_id text,p_workspace uuid default null,p_change jsonb default '{}',p_token text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); tbl text; r jsonb; deps jsonb:='{}'; preview jsonb; token text; cached jsonb;
 events jsonb:='[]'; reservations jsonb:='[]'; defaults jsonb:='[]'; products jsonb:='[]'; linked jsonb:='[]';
 b jsonb; v_factor numeric; v_unit text; replacement uuid; blocked text; title text; parent uuid; sale_key text; counts jsonb:='{}';
begin
 if u is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'MANAGEMENT_DENIED'; end if;
 if p_id is null or p_kind is null or p_change is null or jsonb_typeof(p_change)<>'object' then raise exception 'MANAGEMENT_INVALID'; end if;
 if p_workspace is not null then
  perform 1 from public.business_workspaces where id=p_workspace and owner_id=u for update;
  if not found or not public.business_can(p_workspace,case when p_kind='sale' then 'finance.write' else 'purchasing.write' end) then raise exception 'MANAGEMENT_DENIED'; end if;
  tbl:=case p_kind when 'supplier' then 'business_suppliers' when 'product' then 'business_supplier_products' when 'template' then 'business_menu_templates'
   when 'purchase' then 'business_records' when 'sale' then 'business_records' when 'stock' then 'business_stock_items' when 'stock_unit' then 'business_stock_items' end;
 else
  tbl:=case p_kind when 'request' then 'supplier_purchase_requests' when 'supplier' then 'shopping_suppliers' when 'sale' then 'chef_sales' when 'product' then 'supplier_catalog_products' end;
  if p_kind='sale' and not public.has_chef_paid_access() then raise exception 'MANAGEMENT_DENIED'; end if;
  if p_kind='request' then perform pg_advisory_xact_lock(hashtextextended('supplier-request:'||p_id,0)); end if;
  if p_kind='supplier' then perform pg_advisory_xact_lock(hashtextextended('shopping-suppliers:'||u::text,0)); end if;
  if p_kind='product' then perform pg_advisory_xact_lock(hashtextextended('supplier-business:'||u::text,0)); end if;
 end if;
 if tbl is null or (p_kind<>'stock_unit' and p_change<>'{}') then raise exception 'MANAGEMENT_INVALID'; end if;
 if tbl='chef_sales' then
  select request_key into sale_key from public.chef_sales where id=p_id::bigint and owner_id=u;
  -- Lock before the row, matching INSERT replay protection and avoiding unique-key waits.
  if sale_key is not null then perform pg_advisory_xact_lock(hashtextextended(u::text||':sale:'||sale_key,0)); end if;
 end if;
 perform pg_advisory_xact_lock(hashtextextended(tbl||':'||p_id,0));
 -- Return a completed request only to its original owner, with the same scope and proposed change.
 select result into cached from public.management_applied_changes where owner_id=u and management_applied_changes.token=p_token;
 if cached is not null then
  if cached->>'kind'=p_kind and cached->>'id'=p_id and cached->>'workspace' is not distinct from p_workspace::text and cached->'change'=p_change then return cached; end if;
  raise exception 'MANAGEMENT_STALE';
 end if;
 if p_workspace is not null then
  execute format('select to_jsonb(t) from public.%I t where workspace_id=$1 and id=$2::uuid for update',tbl) into r using p_workspace,p_id;
 elsif p_kind='product' then
  select p.supplier_id into parent from public.supplier_catalog_products p join public.supplier_businesses s on s.id=p.supplier_id where p.id=p_id::uuid and s.owner_id=u;
  perform 1 from public.supplier_businesses where id=parent for update;
  select to_jsonb(p) into r from public.supplier_catalog_products p where id=p_id::uuid and supplier_id=parent for update;
 else
  execute format('select to_jsonb(t) from public.%I t where owner_id=$1 and id=$2::%s for update',tbl,case when p_kind='sale' then 'bigint' else 'uuid' end) into r using u,p_id;
 end if;
 if r is null then raise exception 'MANAGEMENT_STALE'; end if;
 if tbl='business_records' and r->>'kind'<>p_kind then raise exception 'MANAGEMENT_DENIED'; end if;
 title:=coalesce(r->>'title',r->>'name',r->>'recipe_title',r->'data'->>'name',r->'data'->'supplier'->>'name',p_id);
 if tbl='supplier_purchase_requests' then
  perform 1 from public.supplier_request_events where request_id=p_id::uuid for update;
  perform 1 from public.supplier_buyer_reviews where request_id=p_id::uuid for update;
  deps:=jsonb_build_object('history',(select coalesce(jsonb_agg(to_jsonb(e) order by e.id),'[]') from public.supplier_request_events e where request_id=p_id::uuid),
   'reviews',(select coalesce(jsonb_agg(to_jsonb(e) order by e.buyer_id),'[]') from public.supplier_buyer_reviews e where request_id=p_id::uuid));
  counts:=jsonb_build_object('history',jsonb_array_length(deps->'history'),'reviews',jsonb_array_length(deps->'reviews'));
 elsif tbl='chef_sales' then
  deps:=jsonb_build_object('history',(select coalesce(jsonb_agg(to_jsonb(e) order by e.id),'[]') from public.chef_sale_events e where sale_id=p_id::bigint and owner_id=u));
  counts:=jsonb_build_object('history',jsonb_array_length(deps->'history'));
 elsif tbl='business_records' then
  deps:=jsonb_build_object('versions',(select coalesce(jsonb_agg(to_jsonb(v) order by v.revision),'[]') from public.business_record_versions v where record_id=p_id::uuid),
   'basis',(select to_jsonb(x) from public.business_purchase_bases x where request_id=p_id::uuid),
   'supplier',(select to_jsonb(x) from public.business_purchase_supplier_snapshots x where request_id=p_id::uuid),
   'closure',(select to_jsonb(x) from public.business_receiving_closures x where request_id=p_id::uuid),
   'events',(select coalesce(jsonb_agg(to_jsonb(e) order by e.id),'[]') from public.business_stock_events e where request_id=p_id::uuid),
   'batches',(select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') from public.business_menu_batches x where workspace_id=p_workspace and result->'requests' @> jsonb_build_array(jsonb_build_object('id',p_id))));
  counts:=jsonb_build_object('history',jsonb_array_length(deps->'versions'),'retained_receipts',jsonb_array_length(deps->'events'),'linked_batches',jsonb_array_length(deps->'batches'));
 elsif tbl in ('business_suppliers','business_supplier_products') then
  select coalesce(jsonb_agg(to_jsonb(d) order by d.ingredient_key),'[]') into defaults from public.business_ingredient_defaults d where workspace_id=p_workspace and
   (case when p_kind='supplier' then supplier_id=p_id::uuid else product_id=p_id::uuid end);
  if p_kind='supplier' then select coalesce(jsonb_agg(to_jsonb(p) order by p.id),'[]') into products from public.business_supplier_products p where workspace_id=p_workspace and supplier_id=p_id::uuid; end if;
  deps:=jsonb_build_object('defaults',defaults,'products',products);
  counts:=jsonb_build_object('defaults',jsonb_array_length(defaults),'products',jsonb_array_length(products));
 elsif tbl='supplier_catalog_products' then
  deps:=jsonb_build_object('business',(select to_jsonb(s) from public.supplier_businesses s where id=parent),
   'products',(select jsonb_agg(to_jsonb(p) order by p.id) from public.supplier_catalog_products p where supplier_id=parent));
  counts:=jsonb_build_object('products',1);
 elsif tbl='business_stock_items' then
  select coalesce(jsonb_agg(to_jsonb(e) order by e.id),'[]') into events from public.business_stock_events e where workspace_id=p_workspace and item_id=p_id::uuid;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into reservations from public.business_stock_reservations x where workspace_id=p_workspace and item_id=p_id::uuid;
  select coalesce(jsonb_agg(to_jsonb(d) order by d.ingredient_key),'[]') into defaults from public.business_ingredient_defaults d where workspace_id=p_workspace and stock_id=p_id::uuid;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into linked from public.business_menu_batches x where workspace_id=p_workspace and result->'reservations' @> jsonb_build_array(jsonb_build_object('item',p_id));
  b:=public.business_stock_balance(p_workspace,p_id::uuid);
  deps:=jsonb_build_object('events',events,'reservations',reservations,'defaults',defaults,'batches',linked);
  counts:=jsonb_build_object('movements',jsonb_array_length(events),'reservations',jsonb_array_length(reservations),'defaults',jsonb_array_length(defaults));
  if p_kind='stock' then
   if exists(select 1 from jsonb_array_elements(reservations) x where (x->>'remaining')::numeric>0) then blocked:='MANAGEMENT_RESERVED';
   elsif exists(select 1 from jsonb_array_elements(events) x where x->>'request_id' is not null) then blocked:='MANAGEMENT_RECEIPTS'; end if;
  else
   if exists(select 1 from jsonb_object_keys(p_change) x where x not in ('unit','factor')) or jsonb_typeof(p_change->'unit') is distinct from 'string'
    or jsonb_typeof(p_change->'factor') is distinct from 'number' then raise exception 'MANAGEMENT_INVALID'; end if;
   v_unit:=btrim(p_change->>'unit'); v_factor:=(p_change->>'factor')::numeric;
   if length(v_unit) not between 1 and 30 or v_unit~'[[:cntrl:]]' or lower(v_unit)=lower(btrim(r->>'unit')) or v_factor<=0 or v_factor>1e9 then raise exception 'MANAGEMENT_INVALID'; end if;
   if exists(select 1 from public.business_stock_items where workspace_id=p_workspace and lower(btrim(name))=lower(btrim(r->>'name')) and lower(btrim(spec))=lower(btrim(r->>'spec')) and lower(btrim(business_stock_items.unit))=lower(v_unit)) then blocked:='MANAGEMENT_DUPLICATE'; end if;
   if exists(select 1 from jsonb_array_elements(events) x where abs((x->>'delta')::numeric*v_factor)>1e9 or round((x->>'delta')::numeric*v_factor,6)<>(x->>'delta')::numeric*v_factor
    or abs((x->>'reserved_delta')::numeric*v_factor)>1e9 or round((x->>'reserved_delta')::numeric*v_factor,6)<>(x->>'reserved_delta')::numeric*v_factor
    or (x->>'factor' is not null and ((x->>'factor')::numeric*v_factor not between 0.000001 and 1e9 or round((x->>'factor')::numeric*v_factor,6)<>(x->>'factor')::numeric*v_factor)))
    or exists(select 1 from jsonb_array_elements(reservations) x where (x->>'quantity')::numeric*v_factor>1e9 or round((x->>'quantity')::numeric*v_factor,6)<>(x->>'quantity')::numeric*v_factor or round((x->>'remaining')::numeric*v_factor,6)<>(x->>'remaining')::numeric*v_factor)
    or abs((b->>'on_hand')::numeric*v_factor)>1e9 or (b->>'reserved')::numeric*v_factor>1e9 then blocked:='MANAGEMENT_PRECISION'; end if;
  end if;
 end if;
 token:=encode(extensions.digest(jsonb_build_array(u,p_workspace,p_kind,p_id,p_change,r,deps)::text,'sha256'),'hex');
 preview:=jsonb_build_object('kind',p_kind,'id',p_id,'workspace',p_workspace,'change',p_change,'title',title,'token',token,'counts',counts,'blocked',blocked,
  'unit',r->>'unit','balance',b,'after',case when p_kind='stock_unit' then jsonb_build_object('on_hand',(b->>'on_hand')::numeric*v_factor,'reserved',(b->>'reserved')::numeric*v_factor,'available',(b->>'available')::numeric*v_factor) end);
 if p_token is null then return preview; end if;
 if p_token<>token then raise exception 'MANAGEMENT_STALE'; end if;
 if blocked is not null then raise exception '%',blocked; end if;
 if p_kind='stock_unit' then
  replacement:=gen_random_uuid();
  insert into public.business_stock_items(id,workspace_id,name,spec,unit,management_note,management_revision)
   values(replacement,p_workspace,r->>'name',r->>'spec',v_unit,r->>'management_note',(r->>'management_revision')::bigint+1);
  update public.business_stock_events set item_id=replacement,delta=delta*v_factor,reserved_delta=reserved_delta*v_factor,
   factor=business_stock_events.factor*(p_change->>'factor')::numeric,
   snapshot=case when snapshot ? 'item_unit' then snapshot||jsonb_build_object('item_unit',v_unit) else snapshot end where workspace_id=p_workspace and item_id=p_id::uuid;
  update public.business_stock_reservations set item_id=replacement,quantity=quantity*v_factor,remaining=remaining*v_factor,revision=revision+1 where workspace_id=p_workspace and item_id=p_id::uuid;
  update public.business_ingredient_defaults set stock_id=null,revision=revision+1,updated_at=now(),updated_by=u where workspace_id=p_workspace and stock_id=p_id::uuid;
  -- Cached preparation results retain their request IDs but point at the converted stock identity.
  update public.business_menu_batches set result=jsonb_set(result,'{reservations}',
   (select coalesce(jsonb_agg(case when x->>'item'=p_id then x||jsonb_build_object('item',replacement,'quantity',(x->>'quantity')::numeric*v_factor) else x end order by n),'[]') from jsonb_array_elements(result->'reservations') with ordinality a(x,n)))
   where workspace_id=p_workspace and id in (select (x->>'id')::uuid from jsonb_array_elements(linked) x);
  insert into public.management_deleted_ids values(tbl,p_id,u);
  delete from public.business_stock_items where workspace_id=p_workspace and id=p_id::uuid;
  preview:=preview||jsonb_build_object('replacement',replacement);
 elsif tbl='supplier_purchase_requests' then
  insert into public.deleted_purchase_drafts(id,owner_id,revision) values(p_id::uuid,u,(r->>'revision')::bigint);
  delete from public.supplier_purchase_requests where id=p_id::uuid and owner_id=u;
 elsif tbl='chef_sales' then
  perform pg_advisory_xact_lock(hashtextextended(u::text||':sale:'||(r->>'request_key'),0));
  insert into public.management_deleted_sales values(u,r->>'request_key');
  delete from public.chef_sales where id=p_id::bigint and owner_id=u;
  delete from public.chef_sale_events where owner_id=u and sale_id=p_id::bigint;
 else
  if tbl='business_suppliers' then
   insert into public.management_deleted_ids select 'business_supplier_products',x->>'id',u from jsonb_array_elements(products) x;
  elsif tbl='business_stock_items' then
   update public.business_ingredient_defaults set stock_id=null,revision=revision+1,updated_at=now(),updated_by=u where workspace_id=p_workspace and stock_id=p_id::uuid;
   delete from public.business_stock_events where workspace_id=p_workspace and item_id=p_id::uuid and kind='return';
  elsif tbl='business_records' and p_kind='purchase' then
   update public.business_menu_batches set result=jsonb_set(result,'{requests}',
    (select coalesce(jsonb_agg(case when x->>'id'=p_id then x||'{"deleted":true}'::jsonb else x end order by n),'[]') from jsonb_array_elements(result->'requests') with ordinality a(x,n)))
    where workspace_id=p_workspace and result->'requests' @> jsonb_build_array(jsonb_build_object('id',p_id));
  end if;
  insert into public.management_deleted_ids values(tbl,p_id,u);
  execute format('delete from public.%I where id=$1::uuid',tbl) using p_id;
  if tbl='supplier_catalog_products' and not exists(select 1 from public.supplier_catalog_products where supplier_id=parent and active and image_path<>'') then
   update public.supplier_businesses set published=false,revision=revision+1,updated_at=now() where id=parent and published;
  end if;
 end if;
 preview:=preview||jsonb_build_object('applied',true);
 insert into public.management_applied_changes values(u,token,preview);
 return preview;
end; $$;
revoke all on function public.owner_record_manage(text,text,uuid,jsonb,text) from public,anon;
grant execute on function public.owner_record_manage(text,text,uuid,jsonb,text) to authenticated;
notify pgrst,'reload schema';
commit;
