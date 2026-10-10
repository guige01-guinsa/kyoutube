-- Researched businesses are references, never impersonated supplier accounts.
-- Self-contained guard: no assumption about historical optional MFA migrations.
create function public.assert_supplier_directory_admin() returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and role='admin') then
  raise exception 'ADMIN_REQUIRED'; end if;
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then raise exception 'ADMIN_MFA_REQUIRED'; end if;
end; $$;
revoke all on function public.assert_supplier_directory_admin() from public,anon,authenticated;
create function public.supplier_reference_url(v text) returns boolean
language sql immutable set search_path='' as $$
 select coalesce(length(v) between 10 and 2048
  and v !~ '[[:space:][:cntrl:]\\]'
  and v ~ '^https://[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}(:443)?([/?#].*)?$'
  and substring(v from '^https://([^/?#]+)') !~ '\.\.'
  and lower(v) !~ '\.(local|localhost|internal)(:443)?([/?#]|$)',false);
$$;
create function public.supplier_reference_sources(v text[]) returns boolean
language sql immutable set search_path='' as $$
 select cardinality(v) between 1 and 5 and not exists(
  select 1 from unnest(v) x where not public.supplier_reference_url(x));
$$;
create table public.public_supplier_listings (
 id uuid primary key default gen_random_uuid(),
 name text not null check(length(btrim(name)) between 1 and 120),
 website text not null check(public.supplier_reference_url(website)),
 website_host text generated always as (
  regexp_replace(lower(substring(website from '^https://([^/?#:]+)')),'^www\.','')
 ) stored unique,
 phone text not null default '' check(length(phone)<=60),
 products text not null check(length(btrim(products)) between 1 and 500),
 categories text[] not null check(cardinality(categories) between 1 and 6 and
  categories <@ array['produce','seafood','meat','dairy','processed','pantry']::text[] and array_position(categories,null) is null),
 delivery_regions text[] not null check(cardinality(delivery_regions) between 1 and 18 and
  delivery_regions <@ array['전국','서울','경기','인천','부산','대구','대전','광주','울산','세종','강원','충북','충남','전북','전남','경북','경남','제주']::text[] and array_position(delivery_regions,null) is null),
 shipping_note text not null check(length(btrim(shipping_note)) between 1 and 700),
 business_kind text not null check(business_kind in ('store','distributor','marketplace')),
 source_urls text[] not null check(public.supplier_reference_sources(source_urls)),
 checked_on date not null,
 status text not null default 'candidate' check(status in ('candidate','published','hidden')),
 revision bigint not null default 1,
 updated_at timestamptz not null default now()
);
comment on table public.public_supplier_listings is 'Operator-reviewed official public facts, not owner-registered, identity-verified or priced catalog offers. Source photos and reviews are not copied.';
alter table public.public_supplier_listings enable row level security;
revoke all on public.public_supplier_listings from public,anon,authenticated;
grant select on public.public_supplier_listings to authenticated;
grant all on public.public_supplier_listings to service_role;
create policy public_supplier_member_read on public.public_supplier_listings for select to authenticated
 using(status='published' and auth.uid() is not null and coalesce((auth.jwt()->>'is_anonymous')::boolean,false)=false);

create table public.public_supplier_audit (
 id bigint generated always as identity primary key,
 listing_id uuid not null references public.public_supplier_listings(id),
 actor_id uuid references auth.users(id) on delete set null,
 before_data jsonb,
 after_data jsonb not null,
 created_at timestamptz not null default now()
);
alter table public.public_supplier_audit enable row level security;
revoke all on public.public_supplier_audit from public,anon,authenticated;
grant all on public.public_supplier_audit to service_role;
grant usage,select on sequence public.public_supplier_audit_id_seq to service_role;

alter table public.shopping_suppliers add column public_listing_id uuid references public.public_supplier_listings(id) on delete set null;
create unique index shopping_supplier_public_unique on public.shopping_suppliers(owner_id,public_listing_id) where public_listing_id is not null;
-- Preserve the 0059 insert whitelist; new provenance cannot be forged by clients.

create function public.search_public_supplier_listings(p_query text default '',p_category text default '',p_region text default '',p_offset int default 0)
returns setof public.public_supplier_listings language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'AUTH_REQUIRED'; end if;
 if length(coalesce(p_query,''))>120 or p_offset is null or p_offset<0 or p_offset>10000 then raise exception 'INVALID_INPUT'; end if;
 return query select l.* from public.public_supplier_listings l
 where l.status='published'
 and (coalesce(p_query,'')='' or position(lower(btrim(p_query)) in lower(l.name||' '||l.products||' '||l.website||' '||array_to_string(l.delivery_regions,' ')||' '||l.shipping_note))>0)
 and (coalesce(p_category,'')='' or p_category=any(l.categories))
 and (coalesce(p_region,'')='' or p_region=any(l.delivery_regions) or '전국'=any(l.delivery_regions))
 order by exists(select 1 from public.shopping_suppliers s where s.owner_id=auth.uid() and s.public_listing_id=l.id) desc,l.name,l.id
 limit 30 offset p_offset;
end; $$;
create function public.import_public_supplier_listing(p_id uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare l public.public_supplier_listings%rowtype; s public.shopping_suppliers%rowtype; u uuid:=auth.uid();
begin
 if u is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'AUTH_REQUIRED'; end if;
 select * into l from public.public_supplier_listings where id=p_id and status='published';
 if l.id is null then raise exception 'LISTING_NOT_FOUND'; end if;
 perform pg_advisory_xact_lock(hashtextextended('shopping-suppliers:'||u::text,0));
 select * into s from public.shopping_suppliers where owner_id=u and public_listing_id=p_id;
 if s.id is null then
  insert into public.shopping_suppliers(id,owner_id,name,phone,products,website,public_listing_id)
   values(gen_random_uuid(),u,l.name,l.phone,l.products,l.website,l.id) returning * into s;
 else
  update public.shopping_suppliers set name=l.name,phone=l.phone,products=l.products,website=l.website
   where id=s.id returning * into s;
 end if;
 return to_jsonb(s);
end; $$;

create function public.admin_search_public_suppliers(p_query text default '',p_status text default '',p_offset int default 0)
returns setof public.public_supplier_listings language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 perform public.assert_supplier_directory_admin();
 if length(coalesce(p_query,''))>120 or p_offset is null or p_offset<0 or p_offset>10000 then raise exception 'INVALID_INPUT'; end if;
 return query select l.* from public.public_supplier_listings l
 where (coalesce(p_query,'')='' or position(lower(btrim(p_query)) in lower(l.name||' '||l.products||' '||l.website||' '||array_to_string(l.delivery_regions,' ')||' '||l.shipping_note))>0)
 and (coalesce(p_status,'')='' or l.status=p_status)
 order by l.updated_at desc,l.id limit 30 offset p_offset;
end; $$;

create function public.admin_save_public_supplier(p_data jsonb,p_revision bigint,p_confirmed boolean default false) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare before_row public.public_supplier_listings%rowtype; after_row public.public_supplier_listings%rowtype;
 v_id uuid; v_status text; v_date date; today date:=(now() at time zone 'Asia/Seoul')::date;
begin
 perform public.assert_supplier_directory_admin();
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>16000 or p_revision is null or p_revision<0 then raise exception 'INVALID_INPUT'; end if;
 v_id:=coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid());
 v_status:=coalesce(p_data->>'status','candidate'); v_date:=(p_data->>'checked_on')::date;
 if v_date is null or v_date>today or v_date<date '2020-01-01' then raise exception 'INVALID_CHECK_DATE'; end if;
 if v_status='published' and (not coalesce(p_confirmed,false) or v_date<today-90) then raise exception 'SOURCE_REVIEW_REQUIRED'; end if;
 select * into before_row from public.public_supplier_listings where id=v_id for update;
 if (before_row.id is null and p_revision<>0) or (before_row.id is not null and before_row.revision<>p_revision) then raise exception 'LISTING_CONFLICT'; end if;
 if before_row.id is null then
  insert into public.public_supplier_listings(id,name,website,phone,products,categories,delivery_regions,shipping_note,business_kind,source_urls,checked_on,status)
  values(v_id,btrim(p_data->>'name'),btrim(p_data->>'website'),btrim(coalesce(p_data->>'phone','')),btrim(p_data->>'products'),
   array(select jsonb_array_elements_text(p_data->'categories')),array(select jsonb_array_elements_text(p_data->'delivery_regions')),
   btrim(p_data->>'shipping_note'),p_data->>'business_kind',array(select jsonb_array_elements_text(p_data->'source_urls')),v_date,v_status)
  returning * into after_row;
 else
  update public.public_supplier_listings set name=btrim(p_data->>'name'),website=btrim(p_data->>'website'),phone=btrim(coalesce(p_data->>'phone','')),
   products=btrim(p_data->>'products'),categories=array(select jsonb_array_elements_text(p_data->'categories')),
   delivery_regions=array(select jsonb_array_elements_text(p_data->'delivery_regions')),shipping_note=btrim(p_data->>'shipping_note'),
   business_kind=p_data->>'business_kind',source_urls=array(select jsonb_array_elements_text(p_data->'source_urls')),
   checked_on=v_date,status=v_status,revision=revision+1,updated_at=now() where id=v_id returning * into after_row;
 end if;
 insert into public.public_supplier_audit(listing_id,actor_id,before_data,after_data) values(v_id,auth.uid(),case when before_row.id is null then null else to_jsonb(before_row) end,to_jsonb(after_row));
 return to_jsonb(after_row);
end; $$;

create function public.admin_match_public_suppliers(p_websites text[])
returns setof public.public_supplier_listings language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 perform public.assert_supplier_directory_admin();
 if p_websites is null or cardinality(p_websites) not between 1 and 5 or
 exists(select 1 from unnest(p_websites) w where not public.supplier_reference_url(w)) then raise exception 'INVALID_INPUT';end if;
 return query select l.* from public.public_supplier_listings l where l.website_host in
 (select regexp_replace(lower(substring(w from '^https://([^/?#:]+)')),'^www\.','') from unnest(p_websites) w);
end; $$;
revoke all on function public.admin_match_public_suppliers(text[]) from public,anon,authenticated;
grant execute on function public.admin_match_public_suppliers(text[]) to authenticated;

-- One atomic, revision-checked publish action for the operator's selected rows.
create function public.admin_publish_public_suppliers(p_selected jsonb,p_confirmed boolean) returns int
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare x jsonb; l public.public_supplier_listings%rowtype; n int:=0;
begin
 perform public.assert_supplier_directory_admin();
 if not coalesce(p_confirmed,false) or p_selected is null or jsonb_typeof(p_selected)<>'array' then raise exception 'SOURCE_REVIEW_REQUIRED'; end if;
 if jsonb_array_length(p_selected) not between 1 and 20 then raise exception 'INVALID_INPUT'; end if;
 for x in select value from jsonb_array_elements(p_selected) order by value->>'id' loop
  if (x->>'revision')::bigint=0 then
   perform public.admin_save_public_supplier(x||jsonb_build_object('status','published'),0,true);
   n:=n+1;
   continue;
  end if;
  select * into l from public.public_supplier_listings where id=(x->>'id')::uuid for update;
  if l.id is null or l.revision is distinct from (x->>'revision')::bigint then raise exception 'LISTING_CONFLICT'; end if;
  perform public.admin_save_public_supplier(to_jsonb(l)||jsonb_build_object('status','published'),l.revision,true);
  n:=n+1;
 end loop;
 return n;
end; $$;

revoke all on function public.supplier_reference_url(text),public.supplier_reference_sources(text[]),public.search_public_supplier_listings(text,text,text,int),public.import_public_supplier_listing(uuid),public.admin_search_public_suppliers(text,text,int),public.admin_save_public_supplier(jsonb,bigint,boolean),public.admin_publish_public_suppliers(jsonb,boolean) from public,anon,authenticated;
grant execute on function public.supplier_reference_url(text),public.supplier_reference_sources(text[]) to authenticated,service_role;
grant execute on function public.search_public_supplier_listings(text,text,text,int),public.import_public_supplier_listing(uuid),public.admin_search_public_suppliers(text,text,int),public.admin_save_public_supplier(jsonb,bigint,boolean),public.admin_publish_public_suppliers(jsonb,boolean) to authenticated;
notify pgrst,'reload schema';

-- Paid discovery is administrator-only; failed attempts also consume the cap.
create table public.supplier_discovery_runs (
 id uuid primary key default gen_random_uuid(),
 actor_id uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 outcome text not null default 'started' check(outcome in ('started','succeeded','failed')),
 input_tokens int not null default 0 check(input_tokens>=0),
 output_tokens int not null default 0 check(output_tokens>=0),
 web_calls int not null default 0 check(web_calls between 0 and 2)
);
create index supplier_discovery_recent on public.supplier_discovery_runs(created_at,actor_id);
alter table public.supplier_discovery_runs enable row level security;
revoke all on public.supplier_discovery_runs from public,anon,authenticated;
grant all on public.supplier_discovery_runs to service_role;
create function public.admin_reserve_supplier_search() returns uuid
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare v_id uuid; day_start timestamptz:=date_trunc('day',now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
begin
 perform public.assert_supplier_directory_admin();
 perform pg_advisory_xact_lock(hashtextextended('supplier-discovery-global',0));
 if exists(select 1 from public.supplier_discovery_runs where actor_id=auth.uid() and created_at>now()-interval '20 seconds')
 or (select count(*) from public.supplier_discovery_runs where actor_id=auth.uid() and created_at>=day_start)>=20
 or (select count(*) from public.supplier_discovery_runs where created_at>=day_start)>=50 then raise exception 'SEARCH_QUOTA'; end if;
 delete from public.supplier_discovery_runs where created_at<now()-interval '90 days';
 insert into public.supplier_discovery_runs(actor_id) values(auth.uid()) returning id into v_id;
 return v_id;
end; $$;
revoke all on function public.admin_reserve_supplier_search() from public,anon,authenticated;
grant execute on function public.admin_reserve_supplier_search() to authenticated;
