-- Supplier-owned catalog. Private buyer directories and request quotas stay intact.
create table public.supplier_businesses (
 id uuid primary key, owner_id uuid not null unique references auth.users(id) on delete cascade,
 name text not null check(length(btrim(name)) between 1 and 120),
 contact text not null check(length(btrim(contact)) between 1 and 120),
 phone text not null check(length(btrim(phone)) between 3 and 60),
 region text not null check(length(btrim(region)) between 1 and 80),
 delivery_regions text[] not null check(cardinality(delivery_regions) between 1 and 30 and array_to_string(delivery_regions,',')<>'' and length(array_to_string(delivery_regions,','))<=1500),
 address text not null default '' check(length(address)<=500),
 website text not null default '' check(website='' or (length(website)<=2048
  and website !~ '[[:space:][:cntrl:]\\]'
  and website ~ '^https://[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}(:443)?([/?#].*)?$'
  and substring(website from '^https://([^/?#]+)') !~ '\.\.'
  and lower(website) !~ '\.(local|localhost|internal)(:443)?([/?#]|$)')),
 description text not null default '' check(length(description)<=2000),
 currency text not null default 'KRW' check(currency in ('KRW','USD')),
 shipping_fee numeric check(shipping_fee between 0 and 1e12),
 free_shipping_from numeric check(free_shipping_from between 0 and 1e12),
 minimum_order numeric not null default 0 check(minimum_order between 0 and 1e12),
 published boolean not null default false, verified boolean not null default false,
 revision bigint not null default 1, updated_at timestamptz not null default now()
);
create table public.supplier_catalog_products (
 id uuid primary key,supplier_id uuid not null references public.supplier_businesses(id) on delete cascade,
 name text not null check(length(btrim(name)) between 1 and 250),
 category text not null,subcategory text not null,
 aliases text not null default '' check(length(aliases)<=500),brand text not null default '' check(length(brand)<=120),
 origin text not null check(origin in ('domestic','imported','mixed','unknown')),
 country text not null default '' check(length(country)<=120),
 storage text not null default 'ambient' check(storage in ('ambient','chilled','frozen')),
 description text not null default '' check(length(description)<=2000),
 image_path text not null default '' check(length(image_path)<=250),
 sale_unit text not null check(length(btrim(sale_unit)) between 1 and 30 and sale_unit not in ('tsp','tbsp','cup')),
 content_quantity numeric not null check(content_quantity>0 and content_quantity<=1e9 and round(content_quantity,6)=content_quantity),
 content_unit text not null check(length(btrim(content_unit)) between 1 and 30 and content_unit not in ('tsp','tbsp','cup')),
 minimum_packs int not null default 1 check(minimum_packs between 1 and 1000000),
 price numeric check(price between 0 and 1e12),price_valid_until date,
 tax text not null default 'included' check(tax in ('included','exempt','unknown')),
 active boolean not null default true,revision bigint not null default 1,updated_at timestamptz not null default now(),
 check(price is null or price_valid_until is not null),
 check((category='produce' and subcategory in ('vegetables','fruit','grains','mushrooms')) or
 (category='seafood' and subcategory in ('fish','shellfish','seaweed','dried_seafood')) or
 (category='meat' and subcategory in ('beef','pork','poultry','other_meat')) or
 (category='dairy' and subcategory in ('eggs','milk','cheese')) or
 (category='processed' and subcategory in ('frozen','noodles','tofu','prepared')) or
 (category='pantry' and subcategory in ('sauces','oils','spices','other')))
);
create index supplier_catalog_products_category on public.supplier_catalog_products(category,subcategory) where active;
create index supplier_catalog_products_supplier on public.supplier_catalog_products(supplier_id);
alter table public.supplier_businesses enable row level security;
alter table public.supplier_catalog_products enable row level security;
revoke all on public.supplier_businesses,public.supplier_catalog_products from public,anon,authenticated;
grant select on public.supplier_businesses,public.supplier_catalog_products to authenticated;
grant all on public.supplier_businesses,public.supplier_catalog_products to service_role;
create policy supplier_business_read on public.supplier_businesses for select to authenticated using(published or owner_id=(select auth.uid()));
create policy supplier_product_read on public.supplier_catalog_products for select to authenticated using(exists(
 select 1 from public.supplier_businesses b where b.id=supplier_id and (b.owner_id=(select auth.uid()) or (b.published and active))));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('supplier-products','supplier-products',false,5242880,array['image/jpeg','image/png','image/webp']);
create function public.can_upload_supplier_image(p_path text) returns boolean
language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
 select auth.uid() is not null and split_part(p_path,'/',1)=auth.uid()::text
 and p_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp)$'
 and exists(select 1 from public.supplier_businesses b where b.id::text=split_part(p_path,'/',2) and b.owner_id=auth.uid())
 and (select count(*) from storage.objects where bucket_id='supplier-products' and split_part(name,'/',1)=auth.uid()::text)<600;
$$;
revoke all on function public.can_upload_supplier_image(text) from public,anon;
grant execute on function public.can_upload_supplier_image(text) to authenticated;
create policy supplier_image_upload on storage.objects for insert to authenticated with check(bucket_id='supplier-products' and public.can_upload_supplier_image(name));
create policy supplier_image_read on storage.objects for select to authenticated using(bucket_id='supplier-products' and (
 split_part(name,'/',1)=(select auth.uid())::text or exists(select 1 from public.supplier_catalog_products p
 join public.supplier_businesses b on b.id=p.supplier_id where p.image_path=storage.objects.name and p.active and b.published)));
create policy supplier_image_delete on storage.objects for delete to authenticated using(bucket_id='supplier-products'
 and split_part(name,'/',1)=(select auth.uid())::text and not exists(select 1 from public.supplier_catalog_products p where p.image_path=storage.objects.name));

create function public.save_supplier_business(p_data jsonb,p_revision bigint) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare v public.supplier_businesses%rowtype; d public.supplier_businesses%rowtype; u uuid:=auth.uid();
begin
 if u is null then raise exception 'CATALOG_AUTH_REQUIRED'; end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>16384 or p_revision is null or p_revision<0 then raise exception 'CATALOG_INVALID'; end if;
 d:=jsonb_populate_record(null::public.supplier_businesses,p_data);
 perform pg_advisory_xact_lock(hashtextextended('supplier-business:'||u::text,0));
 select * into v from public.supplier_businesses where owner_id=u for update;
 if v.id is not null and (v.id<>d.id or v.revision<>p_revision) then raise exception 'CATALOG_STALE'; end if;
 if v.id is null and p_revision<>0 then raise exception 'CATALOG_STALE'; end if;
 if v.id is not null and v.currency<>d.currency and exists(select 1 from public.supplier_catalog_products where supplier_id=v.id and price is not null)
 then raise exception 'CATALOG_CURRENCY_WITH_PRICES'; end if;
 if d.published and not exists(select 1 from public.supplier_catalog_products p join storage.objects o
  on o.bucket_id='supplier-products' and o.name=p.image_path where p.supplier_id=d.id and p.active)
 then raise exception 'CATALOG_PRODUCT_IMAGE_REQUIRED'; end if;
 if d.published and exists(select 1 from public.supplier_catalog_products p where p.supplier_id=d.id and p.active
  and not exists(select 1 from storage.objects o where o.bucket_id='supplier-products' and o.name=p.image_path))
 then raise exception 'CATALOG_PRODUCT_IMAGE_REQUIRED'; end if;
 if v.id is null then
  insert into public.supplier_businesses(id,owner_id,name,contact,phone,region,delivery_regions,address,website,description,currency,shipping_fee,free_shipping_from,minimum_order,published)
  values(d.id,u,d.name,d.contact,d.phone,d.region,d.delivery_regions,coalesce(d.address,''),coalesce(d.website,''),coalesce(d.description,''),d.currency,d.shipping_fee,d.free_shipping_from,d.minimum_order,coalesce(d.published,false)) returning * into v;
 else
  update public.supplier_businesses set name=d.name,contact=d.contact,phone=d.phone,region=d.region,delivery_regions=d.delivery_regions,address=d.address,website=d.website,description=d.description,currency=d.currency,shipping_fee=d.shipping_fee,free_shipping_from=d.free_shipping_from,minimum_order=d.minimum_order,published=d.published,revision=revision+1,updated_at=now() where id=v.id returning * into v;
 end if;
 return to_jsonb(v);
end; $$;

create function public.save_supplier_catalog_product(p_data jsonb,p_revision bigint) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare v public.supplier_catalog_products%rowtype; d public.supplier_catalog_products%rowtype; u uuid:=auth.uid(); b public.supplier_businesses%rowtype;
begin
 if u is null then raise exception 'CATALOG_AUTH_REQUIRED'; end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>16384 or p_revision is null or p_revision<0 then raise exception 'CATALOG_INVALID'; end if;
 d:=jsonb_populate_record(null::public.supplier_catalog_products,p_data);
 select * into b from public.supplier_businesses where id=d.supplier_id and owner_id=u for update;
 if b.id is null then raise exception 'CATALOG_NOT_FOUND'; end if;
 select * into v from public.supplier_catalog_products where id=d.id for update;
 if v.id is not null and (v.supplier_id<>b.id or v.revision<>p_revision) then raise exception 'CATALOG_STALE'; end if;
 if v.id is null and p_revision<>0 then raise exception 'CATALOG_STALE'; end if;
 if d.image_path<>'' and (split_part(d.image_path,'/',1)<>u::text or split_part(d.image_path,'/',2)<>b.id::text or
 not exists(select 1 from storage.objects o where o.bucket_id='supplier-products' and o.name=d.image_path)) then raise exception 'CATALOG_IMAGE_INVALID'; end if;
 if b.published and d.active and coalesce(d.image_path,'')='' then raise exception 'CATALOG_PRODUCT_IMAGE_REQUIRED'; end if;
 if v.id is null and (select count(*) from public.supplier_catalog_products where supplier_id=b.id)>=300 then raise exception 'CATALOG_PRODUCT_LIMIT'; end if;
 if v.id is null then
  insert into public.supplier_catalog_products(id,supplier_id,name,category,subcategory,aliases,brand,origin,country,storage,description,image_path,sale_unit,content_quantity,content_unit,minimum_packs,price,price_valid_until,tax,active)
  values(d.id,b.id,d.name,d.category,d.subcategory,d.aliases,d.brand,d.origin,d.country,d.storage,d.description,d.image_path,d.sale_unit,d.content_quantity,d.content_unit,d.minimum_packs,d.price,d.price_valid_until,d.tax,d.active) returning * into v;
 else
  update public.supplier_catalog_products set name=d.name,category=d.category,subcategory=d.subcategory,aliases=d.aliases,brand=d.brand,origin=d.origin,country=d.country,storage=d.storage,description=d.description,image_path=d.image_path,sale_unit=d.sale_unit,content_quantity=d.content_quantity,content_unit=d.content_unit,minimum_packs=d.minimum_packs,price=d.price,price_valid_until=d.price_valid_until,tax=d.tax,active=d.active,revision=revision+1,updated_at=now() where id=v.id returning * into v;
 end if;
 return to_jsonb(v);
end; $$;

alter table public.shopping_suppliers add column catalog_supplier_id uuid references public.supplier_businesses(id) on delete set null;
-- Only the validated import RPC can create a public-catalog link.
revoke insert on public.shopping_suppliers from authenticated;
grant insert(id,owner_id,name,contact,phone,products,website,address,memo,is_favorite) on public.shopping_suppliers to authenticated;
create unique index shopping_suppliers_catalog_unique on public.shopping_suppliers(owner_id,catalog_supplier_id) where catalog_supplier_id is not null;
alter table public.supplier_purchase_requests add column catalog_supplier_id uuid references public.supplier_businesses(id) on delete set null;
create function public.link_request_catalog_supplier() returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 if tg_op='UPDATE' and new.data->'supplier'->>'id' is not distinct from old.data->'supplier'->>'id' then return new; end if;
 select catalog_supplier_id into new.catalog_supplier_id from public.shopping_suppliers where id=(new.data->'supplier'->>'id')::uuid and owner_id=new.owner_id;
 return new;
end; $$;
revoke all on function public.link_request_catalog_supplier() from public,anon,authenticated;
create trigger request_catalog_link before insert or update of data on public.supplier_purchase_requests for each row execute function public.link_request_catalog_supplier();
create function public.import_catalog_supplier(p_id uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare b public.supplier_businesses%rowtype; v public.shopping_suppliers%rowtype; u uuid:=auth.uid();
begin
 if u is null then raise exception 'CATALOG_AUTH_REQUIRED'; end if;
 select * into b from public.supplier_businesses where id=p_id and published;
 if b.id is null then raise exception 'CATALOG_NOT_FOUND'; end if;
 perform pg_advisory_xact_lock(hashtextextended('shopping-suppliers:'||u::text,0));
 select * into v from public.shopping_suppliers where owner_id=u and catalog_supplier_id=p_id;
 if v.id is null then
  insert into public.shopping_suppliers(id,owner_id,name,contact,phone,products,address,website,catalog_supplier_id)
  values(gen_random_uuid(),u,b.name,b.contact,b.phone,'',b.address,b.website,b.id) returning * into v;
 else
  -- Re-selection refreshes public contact details; private notes/preferences stay.
  update public.shopping_suppliers set name=b.name,contact=b.contact,phone=b.phone,address=b.address,website=b.website
   where id=v.id returning * into v;
 end if;
 return to_jsonb(v);
end; $$;

create table public.supplier_buyer_reviews (
 supplier_id uuid not null references public.supplier_businesses(id) on delete cascade,
 buyer_id uuid not null references auth.users(id) on delete cascade,
 request_id uuid not null references public.supplier_purchase_requests(id) on delete cascade,
 stars int not null check(stars between 1 and 5),note text not null check(length(note)<=500),updated_at timestamptz not null default now(),
 primary key(supplier_id,buyer_id)
);
alter table public.supplier_buyer_reviews enable row level security;
revoke all on public.supplier_buyer_reviews from public,anon,authenticated;
grant all on public.supplier_buyer_reviews to service_role;
create function public.rate_catalog_supplier(p_request_id uuid,p_stars int,p_note text default '') returns void
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare r public.supplier_purchase_requests%rowtype; u uuid:=auth.uid();
begin
 if u is null then raise exception 'CATALOG_AUTH_REQUIRED'; end if;
 select * into r from public.supplier_purchase_requests where id=p_request_id and owner_id=u and status='received' for share;
 if r.catalog_supplier_id is null or exists(select 1 from public.supplier_businesses where id=r.catalog_supplier_id and owner_id=u) then raise exception 'CATALOG_RECEIPT_REQUIRED'; end if;
 insert into public.supplier_buyer_reviews(supplier_id,buyer_id,request_id,stars,note) values(r.catalog_supplier_id,u,r.id,p_stars,p_note)
 on conflict(supplier_id,buyer_id) do update set request_id=excluded.request_id,stars=excluded.stars,note=excluded.note,updated_at=now();
end; $$;
create function public.catalog_supplier_rating(p_id uuid) returns jsonb
language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
 select jsonb_build_object('rating',round(avg(v.stars),2),'review_count',count(*))
 from public.supplier_buyer_reviews v join public.supplier_purchase_requests r on r.id=v.request_id
 where auth.uid() is not null and v.supplier_id=p_id and r.status='received';
$$;
create function public.search_supplier_catalog(p_query text default '',p_category text default '',p_subcategory text default '',
 p_region text default '',p_origin text default '',p_brand text default '',p_offset int default 0,p_limit int default 30,p_filters jsonb default '{}')
returns jsonb language sql stable security invoker set search_path=pg_catalog,public,pg_temp as $$
 select coalesce(jsonb_agg(row_data),'[]'::jsonb) from (
 select jsonb_build_object('supplier',(to_jsonb(b)-'owner_id')||public.catalog_supplier_rating(b.id),'product',to_jsonb(p)) row_data
 from public.supplier_catalog_products p join public.supplier_businesses b on b.id=p.supplier_id
 where b.published and p.active and p.image_path<>''
 and (coalesce(p_query,'')='' or strpos(lower(p.name||' '||p.aliases||' '||b.name),lower(left(p_query,120)))>0)
 and (coalesce(p_category,'')='' or p.category=p_category) and (coalesce(p_subcategory,'')='' or p.subcategory=p_subcategory)
 and (coalesce(p_region,'')='' or p_region=any(b.delivery_regions) or '전국'=any(b.delivery_regions))
 and (coalesce(p_origin,'')='' or p.origin=p_origin) and (coalesce(p_brand,'')='' or strpos(lower(p.brand),lower(left(p_brand,120)))>0)
 and (not coalesce((p_filters->>'priced')::boolean,false) or (p.price is not null and p.price_valid_until>=current_date and p.tax<>'unknown'))
 and (not coalesce((p_filters->>'verified')::boolean,false) or b.verified)
 and (not coalesce((p_filters->>'rated')::boolean,false) or (public.catalog_supplier_rating(b.id)->>'rating')::numeric>=4)
 order by exists(select 1 from public.shopping_suppliers s where s.owner_id=(select auth.uid()) and s.catalog_supplier_id=b.id) desc,
 p.name,p.id limit greatest(1,least(coalesce(p_limit,30),60)) offset greatest(0,least(coalesce(p_offset,0),10000))) catalog_rows;
$$;
create function public.get_supplier_catalog_offers(p_ids uuid[]) returns jsonb
language sql stable security invoker set search_path=pg_catalog,public,pg_temp as $$
 select coalesce(jsonb_agg(jsonb_build_object('supplier',(to_jsonb(b)-'owner_id')||public.catalog_supplier_rating(b.id),'product',to_jsonb(p))),'[]'::jsonb)
 from public.supplier_catalog_products p join public.supplier_businesses b on b.id=p.supplier_id
 where cardinality(p_ids) between 1 and 300 and p.id=any(p_ids) and b.published and p.active and p.image_path<>'';
$$;
revoke all on function public.save_supplier_business(jsonb,bigint),public.save_supplier_catalog_product(jsonb,bigint),public.import_catalog_supplier(uuid),public.rate_catalog_supplier(uuid,int,text),public.catalog_supplier_rating(uuid),public.search_supplier_catalog(text,text,text,text,text,text,int,int,jsonb),public.get_supplier_catalog_offers(uuid[]) from public,anon;
grant execute on function public.save_supplier_business(jsonb,bigint),public.save_supplier_catalog_product(jsonb,bigint),public.import_catalog_supplier(uuid),public.rate_catalog_supplier(uuid,int,text),public.catalog_supplier_rating(uuid),public.search_supplier_catalog(text,text,text,text,text,text,int,int,jsonb),public.get_supplier_catalog_offers(uuid[]) to authenticated;
