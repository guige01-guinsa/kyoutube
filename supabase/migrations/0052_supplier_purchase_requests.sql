-- Private supplier directory and user-confirmed request lifecycle.
-- This migration never sends a message, charges a card or updates inventory.
create table public.shopping_suppliers (
  id uuid primary key,
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 120),
  contact text not null default '' check (char_length(contact) <= 120),
  phone text not null default '' check (char_length(phone) <= 60),
  products text not null default '' check (char_length(products) <= 500),
  created_at timestamptz not null default now()
);
alter table public.shopping_suppliers enable row level security;
revoke all on public.shopping_suppliers from public, anon, authenticated;
grant select, insert, delete on public.shopping_suppliers to authenticated;
grant update(name, contact, phone, products) on public.shopping_suppliers to authenticated;
create policy shopping_suppliers_owner on public.shopping_suppliers for all to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create index shopping_suppliers_owner_idx on public.shopping_suppliers(owner_id, name);

create function public.limit_shopping_suppliers() returns trigger
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('shopping-suppliers:' || new.owner_id::text, 0));
  if not exists (select 1 from public.shopping_suppliers where id = new.id and owner_id = new.owner_id)
    and (select count(*) from public.shopping_suppliers where owner_id = new.owner_id) >= 200 then
    raise exception 'SUPPLIER_LIMIT';
  end if;
  return new;
end;
$$;
revoke all on function public.limit_shopping_suppliers() from public, anon, authenticated;
create trigger shopping_suppliers_limit before insert on public.shopping_suppliers
  for each row execute function public.limit_shopping_suppliers();

create table public.supplier_purchase_requests (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  data jsonb not null check (octet_length(data::text) <= 131072),
  status text not null default 'draft' check (status in ('draft','sent','accepted','received','cancelled')),
  revision bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index supplier_requests_recent on public.supplier_purchase_requests(owner_id, created_at desc);
alter table public.supplier_purchase_requests enable row level security;
revoke all on public.supplier_purchase_requests from public, anon, authenticated;
grant select, delete on public.supplier_purchase_requests to authenticated;
create policy supplier_requests_read on public.supplier_purchase_requests for select to authenticated
  using (owner_id = (select auth.uid()));
create policy supplier_requests_delete on public.supplier_purchase_requests for delete to authenticated
  using (owner_id = (select auth.uid()));

create function public.save_supplier_purchase_request(p_id uuid, p_revision bigint,
  p_data jsonb, p_status text default 'draft') returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare
  v_owner uuid := auth.uid();
  v_row public.supplier_purchase_requests%rowtype;
  v_line jsonb; v_key text; v_limit int; v_supplier jsonb; v_id uuid;
begin
  if v_owner is null then raise exception 'SUPPLIER_AUTH_REQUIRED'; end if;
  if p_id is null or p_revision is null or p_revision < 0 or p_status is null
    or p_status not in ('draft','sent','accepted','received','cancelled')
    or p_data is null or jsonb_typeof(p_data) <> 'object'
    or octet_length(p_data::text) > 131072 then raise exception 'SUPPLIER_INVALID'; end if;
  for v_key, v_limit in select * from (values ('buyer',120),('phone',60),('address',500),
    ('delivery_date',10),('delivery_window',120),('notes',1000),('currency',3)) as f(k,l) loop
    if jsonb_typeof(p_data->v_key) is distinct from 'string'
      or char_length(p_data->>v_key) > v_limit then raise exception 'SUPPLIER_INVALID'; end if;
  end loop;
  if btrim(p_data->>'buyer') = '' or p_data->>'currency' not in ('KRW','USD') then
    raise exception 'SUPPLIER_INVALID'; end if;
  if p_data->>'delivery_date' <> '' then
    if p_data->>'delivery_date' !~ '^\d{4}-\d{2}-\d{2}$'
      or to_char((p_data->>'delivery_date')::date,'YYYY-MM-DD') <> p_data->>'delivery_date' then
      raise exception 'SUPPLIER_INVALID_DATE'; end if;
  end if;
  v_supplier := p_data->'supplier';
  if jsonb_typeof(v_supplier) is distinct from 'object' then raise exception 'SUPPLIER_INVALID'; end if;
  for v_key, v_limit in select * from (values ('id',36),('name',120),('contact',120),
    ('phone',60),('products',500)) as f(k,l) loop
    if jsonb_typeof(v_supplier->v_key) is distinct from 'string'
      or char_length(v_supplier->>v_key) > v_limit then raise exception 'SUPPLIER_INVALID'; end if;
  end loop;
  if btrim(v_supplier->>'name') = '' then raise exception 'SUPPLIER_INVALID'; end if;
  v_id := (v_supplier->>'id')::uuid;
  if v_id is null then raise exception 'SUPPLIER_INVALID'; end if;
  if jsonb_typeof(p_data->'lines') is distinct from 'array' then raise exception 'SUPPLIER_INVALID'; end if;
  if jsonb_array_length(p_data->'lines') not between 1 and 100 then raise exception 'SUPPLIER_INVALID'; end if;
  if (select count(distinct l->>'id') from jsonb_array_elements(p_data->'lines') l)
    <> jsonb_array_length(p_data->'lines') then raise exception 'SUPPLIER_DUPLICATE_LINE'; end if;
  for v_line in select value from jsonb_array_elements(p_data->'lines') loop
    for v_key, v_limit in select * from (values ('id',36),('name',250),('unit',30),('spec',300)) as f(k,l) loop
      if jsonb_typeof(v_line->v_key) is distinct from 'string'
        or char_length(v_line->>v_key) > v_limit then raise exception 'SUPPLIER_INVALID'; end if;
    end loop;
    if (v_line->>'id')::uuid is null or btrim(v_line->>'name') = '' or btrim(v_line->>'unit') = ''
      or jsonb_typeof(v_line->'quantity') is distinct from 'number' then raise exception 'SUPPLIER_INVALID'; end if;
    if (v_line->>'quantity')::numeric <= 0 or (v_line->>'quantity')::numeric > 1e9
      or round((v_line->>'quantity')::numeric,6) <> (v_line->>'quantity')::numeric then
      raise exception 'SUPPLIER_INVALID'; end if;
    if jsonb_typeof(v_line->'price') is distinct from 'null' then
      if jsonb_typeof(v_line->'price') is distinct from 'number' then raise exception 'SUPPLIER_INVALID'; end if;
      if (v_line->>'price')::numeric < 0 or (v_line->>'price')::numeric > 1e12 then raise exception 'SUPPLIER_INVALID'; end if;
    end if;
    if jsonb_typeof(v_line->'source_ids') is distinct from 'array' then raise exception 'SUPPLIER_INVALID'; end if;
    if jsonb_array_length(v_line->'source_ids') > 100 then raise exception 'SUPPLIER_INVALID'; end if;
    for v_key in select jsonb_array_elements_text(v_line->'source_ids') loop
      if v_key::uuid is null then raise exception 'SUPPLIER_INVALID'; end if;
    end loop;
  end loop;

  perform pg_advisory_xact_lock(hashtextextended('supplier-request:' || p_id::text, 0));
  select * into v_row from public.supplier_purchase_requests where id = p_id for update;
  if v_row.id is not null and v_row.owner_id <> v_owner then raise exception 'SUPPLIER_NOT_FOUND'; end if;
  if v_row.data is distinct from p_data then
    for v_line in select value from jsonb_array_elements(p_data->'lines') loop
      for v_key in select jsonb_array_elements_text(v_line->'source_ids') loop
        if not exists (select 1 from public.kitchen_shopping_items
          where id = v_key::uuid and owner_id = v_owner) then
          raise exception 'SUPPLIER_SOURCE_NOT_FOUND';
        end if;
      end loop;
    end loop;
  end if;
  if v_row.id is not null then
    if v_row.owner_id <> v_owner then raise exception 'SUPPLIER_NOT_FOUND'; end if;
    -- An uncertain response may safely replay precisely the same snapshot/status.
    if v_row.data = p_data and v_row.status = p_status then return to_jsonb(v_row); end if;
    if v_row.revision <> p_revision then raise exception 'SUPPLIER_STALE'; end if;
    if v_row.status <> 'draft' and v_row.data <> p_data then raise exception 'SUPPLIER_FROZEN'; end if;
    if v_row.status <> p_status and not (
      (v_row.status = 'draft' and p_status in ('sent','cancelled')) or
      (v_row.status = 'sent' and p_status in ('accepted','cancelled')) or
      (v_row.status = 'accepted' and p_status in ('received','cancelled'))
    ) then raise exception 'SUPPLIER_INVALID_TRANSITION'; end if;
    update public.supplier_purchase_requests set data = p_data, status = p_status,
      revision = revision + 1, updated_at = now() where id = p_id returning * into v_row;
  else
    if p_revision <> 0 or p_status <> 'draft' then raise exception 'SUPPLIER_STALE'; end if;
    if not exists (select 1 from public.shopping_suppliers where id = v_id and owner_id = v_owner) then
      raise exception 'SUPPLIER_NOT_FOUND'; end if;
    perform pg_advisory_xact_lock(hashtextextended('supplier-request-limit:' || v_owner::text, 0));
    if (select count(*) from public.supplier_purchase_requests where owner_id = v_owner) >= 1000 then
      raise exception 'SUPPLIER_REQUEST_LIMIT'; end if;
    insert into public.supplier_purchase_requests(id, owner_id, data)
      values (p_id, v_owner, p_data) returning * into v_row;
  end if;
  return to_jsonb(v_row);
end;
$$;
revoke all on function public.save_supplier_purchase_request(uuid,bigint,jsonb,text) from public, anon;
grant execute on function public.save_supplier_purchase_request(uuid,bigint,jsonb,text) to authenticated;
