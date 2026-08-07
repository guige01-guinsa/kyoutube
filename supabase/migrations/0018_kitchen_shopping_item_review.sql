-- Phase 3.5: explicit review state, revision-based concurrency, and guarded
-- shopping-item transitions. This migration is intentionally forward-only.

do $$
begin
  if exists (
    select 1
    from public.kitchen_shopping_items as item
    where item.status = 'purchased'
      and (
        item.quantity is null
        or item.quantity <= 0
        or item.unit is null
        or btrim(item.unit) not in ('g', 'kg', 'ml', 'l', 'ea')
      )
  ) then
    raise exception '0018 cannot apply: existing purchased shopping items violate the canonical quantity/unit invariant';
  end if;
end;
$$;

alter table public.kitchen_shopping_items
  add column review_status text not null default 'required',
  add column reviewed_at timestamptz,
  add column revision bigint not null default 0;

alter table public.kitchen_shopping_items
  add constraint kitchen_shopping_items_review_status_check
    check (review_status in ('required', 'confirmed')),
  add constraint kitchen_shopping_items_revision_check
    check (revision >= 0),
  add constraint kitchen_shopping_items_review_timestamp_check
    check (
      (review_status = 'required' and reviewed_at is null)
      or (review_status = 'confirmed' and reviewed_at is not null)
    ),
  add constraint kitchen_shopping_items_confirmed_quantity_unit_check
    check (
      review_status <> 'confirmed'
      or (
        (quantity is null and unit is null)
        or (quantity > 0 and unit in ('g', 'kg', 'ml', 'l', 'ea'))
      )
    ),
  add constraint kitchen_shopping_items_purchased_review_check
    check (
      status <> 'purchased'
      or (
        review_status = 'confirmed'
        and quantity > 0
        and unit in ('g', 'kg', 'ml', 'l', 'ea')
      )
    );

create index kitchen_shopping_items_owner_list_review_required_idx
  on public.kitchen_shopping_items (owner_id, list_id)
  where review_status = 'required';

create or replace function public.sync_kitchen_shopping_item_legacy_check()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_list_status text;
  v_changed boolean := false;
  v_review_rpc boolean := coalesce(current_setting('app.kitchen_review_rpc', true), '') = '1';
  v_status_rpc boolean := coalesce(current_setting('app.kitchen_status_rpc', true), '') = '1';
  v_create_rpc boolean := coalesce(current_setting('app.kitchen_create_rpc', true), '') = '1';
begin
  if tg_op = 'INSERT' then
    if new.ingredient_text is null then
      new.ingredient_text := new.name;
    end if;
    if new.review_status = 'confirmed' and not v_create_rpc then
      raise exception 'confirmed shopping items must be created by the structured create RPC';
    end if;
    if new.status = 'purchased' then
      new.is_checked := true;
    elsif new.is_checked then
      new.status := 'purchased';
    else
      new.is_checked := false;
    end if;
    if new.status = 'purchased' and (
      new.review_status <> 'confirmed' or new.quantity is null or new.quantity <= 0
      or new.unit not in ('g', 'kg', 'ml', 'l', 'ea')
    ) then
      raise exception 'purchased shopping items require confirmed review and a canonical quantity and unit';
    end if;
    return new;
  end if;

  select list.status into v_list_status
  from public.kitchen_shopping_lists as list
  where list.id = new.list_id and list.owner_id = new.owner_id;
  if v_list_status is distinct from 'active' then
    raise exception 'shopping items can only change while their list is active';
  end if;
  if new.list_id is distinct from old.list_id or new.owner_id is distinct from old.owner_id
    or new.ingredient_text is distinct from old.ingredient_text then
    raise exception 'shopping item ownership, list, and ingredient_text are immutable';
  end if;
  if new.revision is distinct from old.revision then
    raise exception 'shopping item revision is server-managed';
  end if;
  if (new.name is distinct from old.name or new.normalized_name is distinct from old.normalized_name
      or new.quantity is distinct from old.quantity or new.unit is distinct from old.unit
      or new.review_status is distinct from old.review_status or new.reviewed_at is distinct from old.reviewed_at)
     and not v_review_rpc then
    raise exception 'shopping item review fields can only change through the review RPC';
  end if;

  if new.status is distinct from old.status and new.is_checked is not distinct from old.is_checked then
    if not v_status_rpc then
      raise exception 'shopping item status can only change through the status RPC';
    end if;
    new.is_checked := (new.status = 'purchased');
  elsif new.is_checked is distinct from old.is_checked and new.status is not distinct from old.status then
    new.status := case when new.is_checked then 'purchased' else 'pending' end;
  elsif new.status is distinct from old.status and new.is_checked is distinct from old.is_checked
    and new.is_checked <> (new.status = 'purchased') then
    raise exception 'is_checked and status must not contradict each other';
  end if;

  if new.status not in ('pending', 'purchased', 'skipped', 'unavailable') then
    raise exception 'shopping item status is invalid';
  end if;
  if new.review_status = 'confirmed' and not (
    (new.quantity is null and new.unit is null)
    or (new.quantity > 0 and new.unit in ('g', 'kg', 'ml', 'l', 'ea'))
  ) then
    raise exception 'confirmed shopping item quantity and unit are invalid';
  end if;
  if new.status = 'purchased' and (
    new.review_status <> 'confirmed' or new.quantity is null or new.quantity <= 0
    or new.unit not in ('g', 'kg', 'ml', 'l', 'ea')
  ) then
    raise exception 'purchased shopping items require confirmed review and a canonical quantity and unit';
  end if;

  v_changed := new.name is distinct from old.name
    or new.normalized_name is distinct from old.normalized_name
    or new.quantity is distinct from old.quantity
    or new.unit is distinct from old.unit
    or new.status is distinct from old.status
    or new.is_checked is distinct from old.is_checked
    or new.review_status is distinct from old.review_status
    or new.reviewed_at is distinct from old.reviewed_at;
  if v_changed then
    new.revision := old.revision + 1;
    new.updated_at := transaction_timestamp();
  else
    new.updated_at := old.updated_at;
  end if;
  return new;
end;
$$;

drop trigger if exists kitchen_shopping_items_legacy_check_sync on public.kitchen_shopping_items;
create trigger kitchen_shopping_items_legacy_check_sync
before insert or update on public.kitchen_shopping_items
for each row execute function public.sync_kitchen_shopping_item_legacy_check();

create or replace function public.review_kitchen_shopping_item(
  p_item_id uuid,
  p_name text,
  p_quantity numeric,
  p_unit text,
  p_expected_revision bigint
)
returns table (item_id uuid, list_id uuid, status text, review_status text, revision bigint, updated_at timestamptz)
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_owner_id uuid := auth.uid();
  v_list_id uuid;
  v_list_status text;
  v_item public.kitchen_shopping_items%rowtype;
  v_name text := btrim(coalesce(p_name, ''));
  v_normalized_name text;
  v_unit text;
begin
  if v_owner_id is null then raise exception 'authentication required'; end if;
  if p_item_id is null or p_expected_revision is null or p_expected_revision < 0 then raise exception 'invalid shopping item review request'; end if;
  select item.list_id into v_list_id from public.kitchen_shopping_items as item where item.id = p_item_id;
  if v_list_id is null then raise exception 'shopping item not found'; end if;
  select list.status into v_list_status from public.kitchen_shopping_lists as list
    where list.id = v_list_id and list.owner_id = v_owner_id for update;
  if not found then raise exception 'shopping item not found'; end if;
  if v_list_status <> 'active' then raise exception 'shopping list is not active'; end if;
  select * into v_item from public.kitchen_shopping_items as item
    where item.id = p_item_id and item.list_id = v_list_id and item.owner_id = v_owner_id for update;
  if not found then raise exception 'shopping item not found'; end if;
  v_unit := case lower(btrim(coalesce(p_unit, '')))
    when '' then null when 'g' then 'g' when 'kg' then 'kg' when 'ml' then 'ml'
    when 'l' then 'l' when 'ea' then 'ea' when '개' then 'ea' else '__invalid__' end;
  if v_name = '' or ((p_quantity is null) <> (v_unit is null)) or p_quantity is not null and p_quantity <= 0 or v_unit = '__invalid__' then
    raise exception 'shopping item review values are invalid';
  end if;
  v_normalized_name := lower(v_name);
  if exists (select 1 from public.kitchen_shopping_items as item where item.list_id = v_list_id and item.id <> p_item_id and item.normalized_name = v_normalized_name) then
    raise exception 'duplicate canonical shopping item name';
  end if;
  if v_item.review_status = 'confirmed' and v_item.name = v_name and v_item.quantity is not distinct from p_quantity and v_item.unit is not distinct from v_unit then
    return query select v_item.id, v_item.list_id, v_item.status, v_item.review_status, v_item.revision, v_item.updated_at;
    return;
  end if;
  if v_item.revision <> p_expected_revision then raise exception 'shopping item revision conflict'; end if;
  perform set_config('app.kitchen_review_rpc', '1', true);
  update public.kitchen_shopping_items as item set
    name = v_name, normalized_name = v_normalized_name, quantity = p_quantity, unit = v_unit,
    review_status = 'confirmed', reviewed_at = transaction_timestamp()
  where item.id = v_item.id and item.owner_id = v_owner_id
  returning item.id, item.list_id, item.status, item.review_status, item.revision, item.updated_at
  into item_id, list_id, status, review_status, revision, updated_at;
  return next;
end;
$$;

create or replace function public.set_kitchen_shopping_item_status(
  p_item_id uuid,
  p_status text,
  p_expected_revision bigint
)
returns table (item_id uuid, list_id uuid, status text, review_status text, revision bigint, updated_at timestamptz)
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_owner_id uuid := auth.uid(); v_list_id uuid; v_list_status text;
  v_item public.kitchen_shopping_items%rowtype; v_status text := lower(btrim(coalesce(p_status, '')));
begin
  if v_owner_id is null then raise exception 'authentication required'; end if;
  if p_item_id is null or p_expected_revision is null or p_expected_revision < 0 or v_status not in ('pending','purchased','skipped','unavailable') then raise exception 'invalid shopping item status request'; end if;
  select item.list_id into v_list_id from public.kitchen_shopping_items as item where item.id = p_item_id;
  if v_list_id is null then raise exception 'shopping item not found'; end if;
  select list.status into v_list_status from public.kitchen_shopping_lists as list where list.id = v_list_id and list.owner_id = v_owner_id for update;
  if not found then raise exception 'shopping item not found'; end if;
  if v_list_status <> 'active' then raise exception 'shopping list is not active'; end if;
  select * into v_item from public.kitchen_shopping_items as item where item.id = p_item_id and item.list_id = v_list_id and item.owner_id = v_owner_id for update;
  if not found then raise exception 'shopping item not found'; end if;
  if v_item.status = v_status then return query select v_item.id, v_item.list_id, v_item.status, v_item.review_status, v_item.revision, v_item.updated_at; return; end if;
  if v_item.revision <> p_expected_revision then raise exception 'shopping item revision conflict'; end if;
  if v_status = 'purchased' and (v_item.review_status <> 'confirmed' or v_item.quantity is null or v_item.quantity <= 0 or v_item.unit not in ('g','kg','ml','l','ea')) then raise exception 'purchased shopping item is not review-ready'; end if;
  perform set_config('app.kitchen_status_rpc', '1', true);
  update public.kitchen_shopping_items as item set status = v_status where item.id = v_item.id and item.owner_id = v_owner_id
  returning item.id, item.list_id, item.status, item.review_status, item.revision, item.updated_at into item_id, list_id, status, review_status, revision, updated_at;
  return next;
end;
$$;

create or replace function public.create_kitchen_shopping_list(p_source_recipe_id text, p_items jsonb, p_idempotency_key uuid)
returns table (list_id uuid, status text, created boolean, replayed boolean, completed_at timestamptz, purchased_count integer, skipped_count integer, unavailable_count integer, inventory_change_count integer, idempotency_key uuid)
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_owner_id uuid := auth.uid(); v_list_id uuid; v_result jsonb; v_item jsonb;
  v_normalized_name text; v_unit text; v_quantity numeric;
begin
  if v_owner_id is null then raise exception 'authentication required'; end if;
  if p_idempotency_key is null then raise exception 'idempotency key is required'; end if;
  if p_source_recipe_id is null or btrim(p_source_recipe_id) = '' or p_source_recipe_id !~ '^(public|creator|user):.+' then raise exception 'source recipe reference must be a typed non-empty text value'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 100 or octet_length(p_items::text) > 65536 then raise exception 'items must be a non-empty JSON array within the configured limits'; end if;
  perform pg_advisory_xact_lock(hashtextextended('kitchen-create:' || v_owner_id::text || ':' || p_idempotency_key::text, 0));
  select ledger.result into v_result from public.kitchen_shopping_idempotency as ledger where ledger.owner_id=v_owner_id and ledger.operation='create' and ledger.idempotency_key=p_idempotency_key;
  if found then
    return query select (v_result->>'list_id')::uuid,v_result->>'status',false,true,nullif(v_result->>'completed_at','')::timestamptz,coalesce((v_result->>'purchased_count')::integer,0),coalesce((v_result->>'skipped_count')::integer,0),coalesce((v_result->>'unavailable_count')::integer,0),coalesce((v_result->>'inventory_change_count')::integer,0),p_idempotency_key;
    return;
  end if;
  for v_item in select element.value from jsonb_array_elements(p_items) as element(value) loop
    if jsonb_typeof(v_item) <> 'object' or v_item ?| array['id','list_id','owner_id','normalized_name','review_status','reviewed_at','revision','status','is_checked','completed_at','inventory_change_count'] or jsonb_typeof(v_item->'name') <> 'string' or btrim(v_item->>'name')='' or char_length(btrim(v_item->>'name'))>200 or jsonb_typeof(v_item->'ingredient_text') <> 'string' or btrim(v_item->>'ingredient_text')='' or char_length(v_item->>'ingredient_text')>500 then raise exception 'invalid kitchen shopping item payload'; end if;
    v_quantity := case when v_item ? 'quantity' and jsonb_typeof(v_item->'quantity') <> 'null' then (v_item->>'quantity')::numeric else null end;
    v_unit := case lower(btrim(coalesce(v_item->>'unit',''))) when '' then null when 'g' then 'g' when 'kg' then 'kg' when 'ml' then 'ml' when 'l' then 'l' when 'ea' then 'ea' when '개' then 'ea' else '__invalid__' end;
    if (v_quantity is null) <> (v_unit is null) or v_quantity is not null and v_quantity <= 0 or v_unit='__invalid__' then raise exception 'invalid kitchen shopping item quantity or unit'; end if;
  end loop;
  select lower(btrim(element.value->>'name')) into v_normalized_name from jsonb_array_elements(p_items) as element(value) group by lower(btrim(element.value->>'name')) having count(*)>1 limit 1;
  if v_normalized_name is not null then raise exception 'duplicate canonical ingredient name is not allowed'; end if;
  insert into public.kitchen_shopping_lists(owner_id,source_recipe_id,title,status,create_idempotency_key) values(v_owner_id,p_source_recipe_id,'장보기 목록','active',p_idempotency_key) returning id into v_list_id;
  perform set_config('app.kitchen_create_rpc','1',true);
  insert into public.kitchen_shopping_items(list_id,owner_id,name,normalized_name,ingredient_text,quantity,unit,is_checked,status,review_status,reviewed_at,revision)
  select v_list_id,v_owner_id,btrim(element.value->>'name'),lower(btrim(element.value->>'name')),element.value->>'ingredient_text',case when element.value ? 'quantity' and jsonb_typeof(element.value->'quantity')<>'null' then (element.value->>'quantity')::numeric else null end,case lower(btrim(coalesce(element.value->>'unit',''))) when '' then null when '개' then 'ea' else lower(btrim(element.value->>'unit')) end,false,'pending','confirmed',transaction_timestamp(),0 from jsonb_array_elements(p_items) as element(value);
  v_result:=jsonb_build_object('list_id',v_list_id,'status','active','completed_at',null,'purchased_count',0,'skipped_count',0,'unavailable_count',0,'inventory_change_count',0);
  insert into public.kitchen_shopping_idempotency(owner_id,operation,idempotency_key,list_id,result) values(v_owner_id,'create',p_idempotency_key,v_list_id,v_result);
  return query select v_list_id,'active',true,false,null::timestamptz,0,0,0,0,p_idempotency_key;
end;
$$;

create or replace function public.complete_kitchen_shopping_list(p_list_id uuid, p_idempotency_key uuid)
returns table (list_id uuid, status text, created boolean, replayed boolean, completed_at timestamptz, purchased_count integer, skipped_count integer, unavailable_count integer, inventory_change_count integer, idempotency_key uuid)
language plpgsql security definer set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_owner_id uuid:=auth.uid(); v_list_status text; v_completed_at timestamptz; v_saved_change_count integer; v_result jsonb; v_item record; v_inventory record; v_pending_count integer; v_purchased_count integer; v_skipped_count integer; v_unavailable_count integer; v_change_count integer:=0; v_existing_unit text; v_incoming_unit text; v_incoming_quantity numeric; v_inventory_match_count integer;
begin
  if v_owner_id is null then raise exception 'authentication required'; end if;
  if p_list_id is null or p_idempotency_key is null then raise exception 'list id and idempotency key are required'; end if;
  perform pg_advisory_xact_lock(hashtextextended('kitchen-complete:'||v_owner_id::text||':'||p_idempotency_key::text,0));
  select ledger.result into v_result from public.kitchen_shopping_idempotency as ledger where ledger.owner_id=v_owner_id and ledger.operation='complete' and ledger.idempotency_key=p_idempotency_key;
  if found then return query select (v_result->>'list_id')::uuid,v_result->>'status',false,true,nullif(v_result->>'completed_at','')::timestamptz,coalesce((v_result->>'purchased_count')::integer,0),coalesce((v_result->>'skipped_count')::integer,0),coalesce((v_result->>'unavailable_count')::integer,0),coalesce((v_result->>'inventory_change_count')::integer,0),p_idempotency_key; return; end if;
  select list.status,list.completed_at,list.completion_inventory_change_count into v_list_status,v_completed_at,v_saved_change_count from public.kitchen_shopping_lists as list where list.id=p_list_id and list.owner_id=v_owner_id for update;
  if not found then raise exception 'shopping list was not found for the authenticated user'; end if;
  select count(*) filter(where item.status='pending'),count(*) filter(where item.status='purchased'),count(*) filter(where item.status='skipped'),count(*) filter(where item.status='unavailable') into v_pending_count,v_purchased_count,v_skipped_count,v_unavailable_count from public.kitchen_shopping_items as item where item.list_id=p_list_id and item.owner_id=v_owner_id;
  if v_list_status='completed' then v_result:=jsonb_build_object('list_id',p_list_id,'status','completed','completed_at',v_completed_at,'purchased_count',v_purchased_count,'skipped_count',v_skipped_count,'unavailable_count',v_unavailable_count,'inventory_change_count',v_saved_change_count); insert into public.kitchen_shopping_idempotency(owner_id,operation,idempotency_key,list_id,result) values(v_owner_id,'complete',p_idempotency_key,p_list_id,v_result); return query select p_list_id,'completed',false,false,v_completed_at,v_purchased_count,v_skipped_count,v_unavailable_count,v_saved_change_count,p_idempotency_key; return; end if;
  if v_list_status<>'active' then raise exception 'only active shopping lists can be completed'; end if;
  if v_pending_count>0 then raise exception 'pending shopping items must be resolved before completion'; end if;
  for v_item in select item.id as item_id,item.name as item_name,item.normalized_name as item_normalized_name,item.quantity as item_quantity,item.unit as item_unit,item.review_status as item_review_status from public.kitchen_shopping_items as item where item.list_id=p_list_id and item.owner_id=v_owner_id and item.status='purchased' order by item.id for update loop
    if v_item.item_review_status<>'confirmed' or v_item.item_name is null or btrim(v_item.item_name)='' or v_item.item_normalized_name<>lower(btrim(v_item.item_name)) or v_item.item_quantity is null or v_item.item_quantity<=0 or v_item.item_unit not in ('g','kg','ml','l','ea') then raise exception 'purchased shopping item lacks confirmed canonical review'; end if;
    select count(*) into v_inventory_match_count from public.kitchen_ingredients as ingredient where ingredient.owner_id=v_owner_id and ingredient.normalized_name=v_item.item_normalized_name;
    if v_inventory_match_count>1 then raise exception 'multiple inventory rows match canonical ingredient name'; end if;
    select ingredient.id as ingredient_id,ingredient.quantity as ingredient_quantity,ingredient.unit as ingredient_unit into v_inventory from public.kitchen_ingredients as ingredient where ingredient.owner_id=v_owner_id and ingredient.normalized_name=v_item.item_normalized_name for update;
    if not found then insert into public.kitchen_ingredients(owner_id,name,normalized_name,quantity,unit) values(v_owner_id,v_item.item_name,v_item.item_normalized_name,v_item.item_quantity,v_item.item_unit); v_change_count:=v_change_count+1;
    elsif v_inventory.ingredient_quantity is null or v_inventory.ingredient_unit is null then raise exception 'ambiguous inventory quantity or unit cannot be merged';
    else v_existing_unit:=lower(btrim(v_inventory.ingredient_unit)); v_incoming_unit:=v_item.item_unit; v_incoming_quantity:=v_item.item_quantity; if v_existing_unit=v_incoming_unit then null; elsif v_existing_unit='g' and v_incoming_unit='kg' then v_incoming_quantity:=v_incoming_quantity*1000; elsif v_existing_unit='kg' and v_incoming_unit='g' then v_incoming_quantity:=v_incoming_quantity/1000; elsif v_existing_unit='ml' and v_incoming_unit='l' then v_incoming_quantity:=v_incoming_quantity*1000; elsif v_existing_unit='l' and v_incoming_unit='ml' then v_incoming_quantity:=v_incoming_quantity/1000; else raise exception 'incompatible inventory units cannot be merged'; end if; update public.kitchen_ingredients as ingredient set quantity=v_inventory.ingredient_quantity+v_incoming_quantity,updated_at=now() where ingredient.id=v_inventory.ingredient_id and ingredient.owner_id=v_owner_id; v_change_count:=v_change_count+1; end if;
  end loop;
  update public.kitchen_shopping_lists as list set status='completed',completed_at=now(),completion_idempotency_key=p_idempotency_key,completion_inventory_change_count=v_change_count,updated_at=now() where list.id=p_list_id and list.owner_id=v_owner_id returning list.completed_at into v_completed_at;
  v_result:=jsonb_build_object('list_id',p_list_id,'status','completed','completed_at',v_completed_at,'purchased_count',v_purchased_count,'skipped_count',v_skipped_count,'unavailable_count',v_unavailable_count,'inventory_change_count',v_change_count); insert into public.kitchen_shopping_idempotency(owner_id,operation,idempotency_key,list_id,result) values(v_owner_id,'complete',p_idempotency_key,p_list_id,v_result); return query select p_list_id,'completed',false,false,v_completed_at,v_purchased_count,v_skipped_count,v_unavailable_count,v_change_count,p_idempotency_key;
end;
$$;

revoke all on function public.create_kitchen_shopping_list(text,jsonb,uuid) from public, anon;
revoke all on function public.complete_kitchen_shopping_list(uuid,uuid) from public, anon;
grant execute on function public.create_kitchen_shopping_list(text,jsonb,uuid) to authenticated;
grant execute on function public.complete_kitchen_shopping_list(uuid,uuid) to authenticated;

revoke all on function public.review_kitchen_shopping_item(uuid, text, numeric, text, bigint) from public, anon;
revoke all on function public.set_kitchen_shopping_item_status(uuid, text, bigint) from public, anon;
grant execute on function public.review_kitchen_shopping_item(uuid, text, numeric, text, bigint) to authenticated;
grant execute on function public.set_kitchen_shopping_item_status(uuid, text, bigint) to authenticated;
