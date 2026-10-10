-- Keep database validation aligned with the purchase units exposed by the app.
-- Package units are inventory quantities in their own right and are only merged
-- with an existing inventory record when the unit is identical.

alter table public.kitchen_shopping_items
  drop constraint if exists kitchen_shopping_items_confirmed_quantity_unit_check,
  drop constraint if exists kitchen_shopping_items_purchased_review_check;

alter table public.kitchen_shopping_items
  add constraint kitchen_shopping_items_confirmed_quantity_unit_check
    check (
      review_status <> 'confirmed'
      or (
        (quantity is null and unit is null)
        or (
          quantity > 0
          and unit = any (array[
            'g', 'kg', 'oz', 'lb',
            'ml', 'l', 'tsp', 'tbsp', 'cup', 'fl_oz', 'pint', 'quart', 'gallon',
            'ea', 'piece', 'slice', 'clove', 'stalk', 'head', 'dozen',
            'pack', 'bag', 'bottle', 'jar', 'can', 'carton', 'box', 'case',
            'bundle', 'bunch', 'net', 'container', 'sachet', 'pouch', 'tube',
            'tray', 'roll'
          ])
        )
      )
    ),
  add constraint kitchen_shopping_items_purchased_review_check
    check (
      status <> 'purchased'
      or (
        review_status = 'confirmed'
        and quantity > 0
        and unit = any (array[
          'g', 'kg', 'oz', 'lb',
          'ml', 'l', 'tsp', 'tbsp', 'cup', 'fl_oz', 'pint', 'quart', 'gallon',
          'ea', 'piece', 'slice', 'clove', 'stalk', 'head', 'dozen',
          'pack', 'bag', 'bottle', 'jar', 'can', 'carton', 'box', 'case',
          'bundle', 'bunch', 'net', 'container', 'sachet', 'pouch', 'tube',
          'tray', 'roll'
        ])
      )
    );

create or replace function public.sync_kitchen_shopping_item_legacy_check()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_supported_units constant text[] := array[
    'g', 'kg', 'oz', 'lb',
    'ml', 'l', 'tsp', 'tbsp', 'cup', 'fl_oz', 'pint', 'quart', 'gallon',
    'ea', 'piece', 'slice', 'clove', 'stalk', 'head', 'dozen',
    'pack', 'bag', 'bottle', 'jar', 'can', 'carton', 'box', 'case',
    'bundle', 'bunch', 'net', 'container', 'sachet', 'pouch', 'tube',
    'tray', 'roll'
  ];
  v_list_status text;
  v_changed boolean := false;
  v_review_rpc boolean := false;
  v_status_rpc boolean := false;
  v_create_rpc boolean := false;
  v_input_status_changed boolean := false;
  v_input_checked_changed boolean := false;
begin
  if tg_op = 'INSERT' then
    v_review_rpc := coalesce(current_setting('app.kitchen_review_rpc', true), '') = '1';
    v_create_rpc := coalesce(current_setting('app.kitchen_create_rpc', true), '') = '1';
    if new.ingredient_text is null then new.ingredient_text := new.name; end if;
    if new.review_status = 'confirmed' and not v_create_rpc then
      raise exception 'confirmed shopping items must be created by the structured create RPC';
    end if;
    if new.status = 'purchased' then new.is_checked := true;
    elsif new.is_checked then new.status := 'purchased';
    else new.is_checked := false;
    end if;
    if new.status = 'purchased' and (
      new.review_status <> 'confirmed' or new.quantity is null or new.quantity <= 0
      or new.unit <> all (v_supported_units)
    ) then
      raise exception 'purchased shopping items require confirmed review and a supported quantity and unit';
    end if;
    return new;
  end if;

  v_input_status_changed := new.status is distinct from old.status;
  v_input_checked_changed := new.is_checked is distinct from old.is_checked;
  v_review_rpc := coalesce(current_setting('app.kitchen_review_rpc', true), '') = '1';
  v_status_rpc := coalesce(current_setting('app.kitchen_status_rpc', true), '') = '1';
  select list.status into v_list_status from public.kitchen_shopping_lists as list
    where list.id = new.list_id and list.owner_id = new.owner_id;
  if v_list_status is distinct from 'active' then raise exception 'shopping items can only change while their list is active'; end if;
  if new.list_id is distinct from old.list_id or new.owner_id is distinct from old.owner_id
    or new.ingredient_text is distinct from old.ingredient_text then
    raise exception 'shopping item ownership, list, and ingredient_text are immutable';
  end if;
  if new.revision is distinct from old.revision then raise exception 'shopping item revision is server-managed'; end if;
  if (new.name is distinct from old.name or new.normalized_name is distinct from old.normalized_name
      or new.quantity is distinct from old.quantity or new.unit is distinct from old.unit
      or new.review_status is distinct from old.review_status or new.reviewed_at is distinct from old.reviewed_at)
     and not v_review_rpc then
    raise exception 'shopping item review fields can only change through the review RPC';
  end if;
  if v_input_status_changed and not v_status_rpc then
    raise exception 'shopping item status can only change through the status RPC';
  elsif not v_input_status_changed and v_input_checked_changed then
    new.status := case when new.is_checked then 'purchased' else 'pending' end;
  elsif v_input_status_changed and v_input_checked_changed then
    if not v_status_rpc then raise exception 'shopping item status can only change through the status RPC'; end if;
    new.is_checked := (new.status = 'purchased');
  elsif v_status_rpc and v_input_status_changed then
    new.is_checked := (new.status = 'purchased');
  end if;
  if new.status not in ('pending', 'purchased', 'skipped', 'unavailable') then raise exception 'shopping item status is invalid'; end if;
  if new.review_status = 'confirmed' and not (
    (new.quantity is null and new.unit is null)
    or (new.quantity > 0 and new.unit = any (v_supported_units))
  ) then
    raise exception 'confirmed shopping item quantity and unit are invalid';
  end if;
  if new.status = 'purchased' and (
    new.review_status <> 'confirmed' or new.quantity is null or new.quantity <= 0
    or new.unit <> all (v_supported_units)
  ) then
    raise exception 'purchased shopping items require confirmed review and a supported quantity and unit';
  end if;
  v_changed := new.name is distinct from old.name
    or new.normalized_name is distinct from old.normalized_name
    or new.quantity is distinct from old.quantity or new.unit is distinct from old.unit
    or new.status is distinct from old.status or new.is_checked is distinct from old.is_checked
    or new.review_status is distinct from old.review_status or new.reviewed_at is distinct from old.reviewed_at;
  if v_changed then
    new.revision := old.revision + 1;
    new.updated_at := transaction_timestamp();
  else
    new.updated_at := old.updated_at;
  end if;
  return new;
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
  v_supported_units constant text[] := array[
    'g', 'kg', 'oz', 'lb',
    'ml', 'l', 'tsp', 'tbsp', 'cup', 'fl_oz', 'pint', 'quart', 'gallon',
    'ea', 'piece', 'slice', 'clove', 'stalk', 'head', 'dozen',
    'pack', 'bag', 'bottle', 'jar', 'can', 'carton', 'box', 'case',
    'bundle', 'bunch', 'net', 'container', 'sachet', 'pouch', 'tube',
    'tray', 'roll'
  ];
  v_owner_id uuid := auth.uid();
  v_list_id uuid;
  v_list_status text;
  v_item public.kitchen_shopping_items%rowtype;
  v_status text := lower(btrim(coalesce(p_status, '')));
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
  if v_item.status = v_status then
    return query select v_item.id, v_item.list_id, v_item.status, v_item.review_status, v_item.revision, v_item.updated_at;
    return;
  end if;
  if v_item.revision <> p_expected_revision then raise exception 'shopping item revision conflict'; end if;
  if v_status = 'purchased' and (
    v_item.review_status <> 'confirmed' or v_item.quantity is null or v_item.quantity <= 0
    or v_item.unit <> all (v_supported_units)
  ) then raise exception 'purchased shopping item is not review-ready'; end if;
  perform set_config('app.kitchen_status_rpc', '1', true);
  update public.kitchen_shopping_items as item set status = v_status where item.id = v_item.id and item.owner_id = v_owner_id
  returning item.id, item.list_id, item.status, item.review_status, item.revision, item.updated_at into item_id, list_id, status, review_status, revision, updated_at;
  return next;
end;
$$;

create or replace function public.complete_kitchen_shopping_list(p_list_id uuid, p_idempotency_key uuid)
returns table (list_id uuid, status text, created boolean, replayed boolean, completed_at timestamptz, purchased_count integer, skipped_count integer, unavailable_count integer, inventory_change_count integer, idempotency_key uuid)
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_supported_units constant text[] := array[
    'g', 'kg', 'oz', 'lb',
    'ml', 'l', 'tsp', 'tbsp', 'cup', 'fl_oz', 'pint', 'quart', 'gallon',
    'ea', 'piece', 'slice', 'clove', 'stalk', 'head', 'dozen',
    'pack', 'bag', 'bottle', 'jar', 'can', 'carton', 'box', 'case',
    'bundle', 'bunch', 'net', 'container', 'sachet', 'pouch', 'tube',
    'tray', 'roll'
  ];
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
    if v_item.item_review_status<>'confirmed' or v_item.item_name is null or btrim(v_item.item_name)='' or v_item.item_normalized_name<>lower(btrim(v_item.item_name)) or v_item.item_quantity is null or v_item.item_quantity<=0 or v_item.item_unit <> all (v_supported_units) then raise exception 'purchased shopping item lacks confirmed supported review'; end if;
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
