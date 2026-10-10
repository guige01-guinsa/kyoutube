-- Private purchase links and user-confirmed shopping records. No payment API.
-- Completing a gram purchase into kilogram inventory must preserve small
-- quantities (1.23 g = 0.00123 kg) rather than round them to zero.
alter table public.kitchen_ingredients alter column quantity type numeric(18,6);

create table public.shopping_product_favorites (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  ingredient_name text not null check (char_length(btrim(ingredient_name)) between 1 and 250),
  ingredient_key text generated always as (lower(btrim(ingredient_name))) stored,
  unit text not null check (char_length(unit) <= 30),
  product_name text not null check (char_length(btrim(product_name)) between 1 and 250),
  product_url text not null check (
    char_length(product_url) <= 2048 and product_url ~ '^https://[^/@[:space:]]+\.[^/@[:space:]]+(/|$)'
    and product_url !~ '[[:cntrl:]]'),
  pack_quantity numeric check (pack_quantity > 0 and pack_quantity <= 1e9),
  unique(owner_id, ingredient_key, unit)
);
alter table public.shopping_product_favorites enable row level security;
revoke all on public.shopping_product_favorites from public, anon, authenticated;
grant select, insert, update, delete on public.shopping_product_favorites to authenticated;
create policy shopping_favorite_owner on public.shopping_product_favorites
  for all to authenticated using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create function public.limit_shopping_favorites() returns trigger
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('shopping-favorites:' || new.owner_id::text, 0));
  if tg_op = 'UPDATE' and new.owner_id <> old.owner_id then
    raise exception 'SHOPPING_OWNER_IMMUTABLE';
  end if;
  if tg_op = 'INSERT' and not exists (
    select 1 from public.shopping_product_favorites f where f.owner_id = new.owner_id
      and f.ingredient_key = lower(btrim(new.ingredient_name)) and f.unit = new.unit
  ) and (select count(*) from public.shopping_product_favorites f
    where f.owner_id = new.owner_id) >= 200 then
    raise exception 'SHOPPING_FAVORITE_LIMIT';
  end if;
  return new;
end;
$$;
revoke all on function public.limit_shopping_favorites() from public, anon, authenticated;
create trigger shopping_favorite_limit before insert or update on public.shopping_product_favorites
  for each row execute function public.limit_shopping_favorites();

create table public.shopping_purchase_records (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  request_key uuid not null,
  request_payload jsonb not null,
  ingredient_name text not null check (char_length(btrim(ingredient_name)) between 1 and 250),
  ingredient_key text generated always as (lower(btrim(ingredient_name))) stored,
  quantity numeric not null check (quantity >= 0 and quantity <= 1e9),
  unit text not null,
  paid_amount numeric check (paid_amount >= 0 and paid_amount <= 1e12),
  currency text not null check (currency in ('KRW', 'USD')),
  product_name text not null default '' check (char_length(product_name) <= 250),
  created_at timestamptz not null default now(),
  unique(owner_id, request_key),
  check (quantity > 0 or paid_amount is null)
);
create index shopping_purchase_records_recent on public.shopping_purchase_records(owner_id, created_at desc);
create index shopping_purchase_records_ingredient on public.shopping_purchase_records(owner_id, ingredient_key, created_at desc);
alter table public.shopping_purchase_records enable row level security;
revoke all on public.shopping_purchase_records from public, anon, authenticated;
grant select on public.shopping_purchase_records to authenticated;
-- Quantity/status corrections go through the existing revision-aware shopping UI.
-- Correcting a paid amount must never add stock or repeat purchase confirmation.
grant update(paid_amount, currency) on public.shopping_purchase_records to authenticated;
create policy shopping_record_read on public.shopping_purchase_records
  for select to authenticated using (owner_id = (select auth.uid()));
create policy shopping_record_amount on public.shopping_purchase_records
  for update to authenticated using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create function public.record_shopping_purchase(p_request_key uuid, p_payload jsonb)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, pg_temp as $$
declare
  v_owner uuid := auth.uid();
  v_existing public.shopping_purchase_records%rowtype;
  v_item public.kitchen_shopping_items%rowtype;
  v_entry jsonb;
  v_items jsonb;
  v_list record;
  v_id uuid;
  v_revision bigint;
  v_quantity numeric;
  v_sum numeric := 0;
  v_amount numeric;
  v_name text;
  v_unit text;
  v_currency text;
  v_count integer;
  v_supported constant text[] := array['g','kg','oz','lb','ml','l','tsp','tbsp','cup','fl_oz',
    'pint','quart','gallon','ea','piece','slice','clove','stalk','head','dozen','pack','bag','bottle',
    'jar','can','carton','box','case','bundle','bunch','net','container','sachet','pouch','tube','tray','roll'];
begin
  if v_owner is null then raise exception 'SHOPPING_AUTH_REQUIRED'; end if;
  if p_request_key is null or p_payload is null or jsonb_typeof(p_payload) <> 'object'
    or octet_length(p_payload::text) > 65536 then raise exception 'SHOPPING_INVALID'; end if;
  perform pg_advisory_xact_lock(hashtextextended('shopping-purchase:' || v_owner::text || ':' || p_request_key::text, 0));
  select * into v_existing from public.shopping_purchase_records r
    where r.owner_id = v_owner and r.request_key = p_request_key;
  if found then
    if v_existing.request_payload <> p_payload then raise exception 'SHOPPING_REQUEST_CONFLICT'; end if;
    return v_existing.id;
  end if;
  v_items := p_payload->'items';
  if jsonb_typeof(v_items) is distinct from 'array' then raise exception 'SHOPPING_INVALID'; end if;
  v_count := jsonb_array_length(v_items);
  v_name := btrim(p_payload->>'name');
  v_unit := p_payload->>'unit';
  v_currency := p_payload->>'currency';
  if v_count not between 1 and 100 or v_name is null or char_length(v_name) not between 1 and 250
    or v_unit is null or v_unit <> all(v_supported) or v_currency is null or v_currency not in ('KRW','USD')
    or jsonb_typeof(p_payload->'quantity') is distinct from 'number'
    or jsonb_typeof(p_payload->'product_name') is distinct from 'string'
    or char_length(p_payload->>'product_name') > 250 then raise exception 'SHOPPING_INVALID'; end if;
  v_quantity := (p_payload->>'quantity')::numeric;
  if v_quantity < 0 or v_quantity > 1e9 or v_quantity <> round(v_quantity, 2) then raise exception 'SHOPPING_INVALID'; end if;
  if p_payload->'paid_amount' is not null and p_payload->'paid_amount' <> 'null'::jsonb then
    if jsonb_typeof(p_payload->'paid_amount') <> 'number' then raise exception 'SHOPPING_INVALID'; end if;
    v_amount := (p_payload->>'paid_amount')::numeric;
    if v_amount < 0 or v_amount > 1e12 or v_quantity = 0 then raise exception 'SHOPPING_INVALID'; end if;
  end if;
  if (select count(distinct e->>'id') from jsonb_array_elements(v_items) e) <> v_count then
    raise exception 'SHOPPING_DUPLICATE_ITEMS';
  end if;
  -- Lock parent lists before items, in stable order, like the completion RPC.
  for v_list in select distinct l.id, l.status from public.kitchen_shopping_lists l
      join public.kitchen_shopping_items i on i.list_id = l.id and i.owner_id = v_owner
      where l.owner_id = v_owner and i.id in (select (e->>'id')::uuid from jsonb_array_elements(v_items) e)
      order by l.id loop
    perform 1 from public.kitchen_shopping_lists l where l.id = v_list.id for update;
    if (select l.status from public.kitchen_shopping_lists l where l.id = v_list.id) <> 'active' then
      raise exception 'SHOPPING_STALE';
    end if;
  end loop;
  for v_entry in select e from jsonb_array_elements(v_items) e order by e->>'id' loop
    if jsonb_typeof(v_entry->'revision') is distinct from 'number'
      or jsonb_typeof(v_entry->'quantity') is distinct from 'number' then raise exception 'SHOPPING_INVALID'; end if;
    select * into v_item from public.kitchen_shopping_items i
      where i.id = (v_entry->>'id')::uuid and i.owner_id = v_owner for update;
    if not found then raise exception 'SHOPPING_NOT_FOUND'; end if;
    if v_item.status <> 'pending' or v_item.revision <> (v_entry->>'revision')::bigint
      or lower(btrim(v_item.name)) <> lower(v_name) then raise exception 'SHOPPING_STALE'; end if;
    if (v_entry->>'quantity')::numeric < 0 or (v_entry->>'quantity')::numeric > 1e9
      or (v_entry->>'quantity')::numeric <> round((v_entry->>'quantity')::numeric, 2) then
      raise exception 'SHOPPING_INVALID';
    end if;
    v_sum := v_sum + (v_entry->>'quantity')::numeric;
  end loop;
  if v_sum <> v_quantity then raise exception 'SHOPPING_ALLOCATION_MISMATCH'; end if;
  for v_entry in select e from jsonb_array_elements(v_items) e order by e->>'id' loop
    if (v_entry->>'quantity')::numeric > 0 then
      select r.revision into v_revision from public.review_kitchen_shopping_item(
        (v_entry->>'id')::uuid, v_name, (v_entry->>'quantity')::numeric,
        v_unit, (v_entry->>'revision')::bigint) r;
      perform public.set_kitchen_shopping_item_status((v_entry->>'id')::uuid, 'purchased', v_revision);
    else
      perform public.set_kitchen_shopping_item_status((v_entry->>'id')::uuid, 'skipped', (v_entry->>'revision')::bigint);
    end if;
  end loop;
  insert into public.shopping_purchase_records(owner_id,request_key,request_payload,ingredient_name,
    quantity,unit,paid_amount,currency,product_name)
    values(v_owner,p_request_key,p_payload,v_name,v_quantity,v_unit,v_amount,v_currency,p_payload->>'product_name')
    returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.record_shopping_purchase(uuid,jsonb) from public, anon;
grant execute on function public.record_shopping_purchase(uuid,jsonb) to authenticated;
