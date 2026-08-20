-- Forward-only completion correction: inventory matching uses item.name and
-- item.normalized_name only; ingredient_text remains raw provenance.

create or replace function public.complete_kitchen_shopping_list(p_list_id uuid, p_idempotency_key uuid)
returns table (list_id uuid, status text, created boolean, replayed boolean, completed_at timestamptz, purchased_count integer, skipped_count integer, unavailable_count integer, inventory_change_count integer, idempotency_key uuid)
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_owner_id uuid := auth.uid(); v_list_status text; v_completed_at timestamptz;
  v_saved_change_count integer; v_result jsonb; v_item record; v_inventory record;
  v_pending_count integer; v_purchased_count integer; v_skipped_count integer; v_unavailable_count integer;
  v_change_count integer := 0; v_existing_unit text; v_incoming_unit text; v_incoming_quantity numeric;
  v_inventory_match_count integer;
begin
  if v_owner_id is null then raise exception 'authentication required'; end if;
  if p_list_id is null or p_idempotency_key is null then raise exception 'list id and idempotency key are required'; end if;
  perform pg_advisory_xact_lock(hashtextextended('kitchen-complete:' || v_owner_id::text || ':' || p_idempotency_key::text, 0));
  select ledger.result into v_result from public.kitchen_shopping_idempotency as ledger
  where ledger.owner_id=v_owner_id and ledger.operation='complete' and ledger.idempotency_key=p_idempotency_key;
  if found then
    return query select (v_result->>'list_id')::uuid,v_result->>'status',false,true,nullif(v_result->>'completed_at','')::timestamptz,coalesce((v_result->>'purchased_count')::integer,0),coalesce((v_result->>'skipped_count')::integer,0),coalesce((v_result->>'unavailable_count')::integer,0),coalesce((v_result->>'inventory_change_count')::integer,0),p_idempotency_key;
    return;
  end if;
  select list.status,list.completed_at,list.completion_inventory_change_count into v_list_status,v_completed_at,v_saved_change_count
  from public.kitchen_shopping_lists as list where list.id=p_list_id and list.owner_id=v_owner_id for update;
  if not found then raise exception 'shopping list was not found for the authenticated user'; end if;
  select count(*) filter(where item.status='pending'),count(*) filter(where item.status='purchased'),count(*) filter(where item.status='skipped'),count(*) filter(where item.status='unavailable')
  into v_pending_count,v_purchased_count,v_skipped_count,v_unavailable_count
  from public.kitchen_shopping_items as item where item.list_id=p_list_id and item.owner_id=v_owner_id;
  if v_list_status='completed' then
    v_result:=jsonb_build_object('list_id',p_list_id,'status','completed','completed_at',v_completed_at,'purchased_count',v_purchased_count,'skipped_count',v_skipped_count,'unavailable_count',v_unavailable_count,'inventory_change_count',v_saved_change_count);
    insert into public.kitchen_shopping_idempotency(owner_id,operation,idempotency_key,list_id,result) values(v_owner_id,'complete',p_idempotency_key,p_list_id,v_result);
    return query select p_list_id,'completed',false,false,v_completed_at,v_purchased_count,v_skipped_count,v_unavailable_count,v_saved_change_count,p_idempotency_key; return;
  end if;
  if v_list_status<>'active' then raise exception 'only active shopping lists can be completed'; end if;
  if v_pending_count>0 then raise exception 'pending shopping items must be resolved before completion'; end if;
  for v_item in select item.id as item_id,item.name as item_name,item.normalized_name as item_normalized_name,item.quantity as item_quantity,item.unit as item_unit
    from public.kitchen_shopping_items as item where item.list_id=p_list_id and item.owner_id=v_owner_id and item.status='purchased' order by item.id for update
  loop
    if v_item.item_name is null or btrim(v_item.item_name)='' or v_item.item_normalized_name is null or btrim(v_item.item_normalized_name)='' or v_item.item_normalized_name<>lower(btrim(v_item.item_name)) or v_item.item_quantity is null or v_item.item_quantity<=0 or v_item.item_unit is null or btrim(v_item.item_unit)='' then raise exception 'purchased shopping item lacks a valid canonical name, quantity, or unit'; end if;
    select count(*) into v_inventory_match_count from public.kitchen_ingredients as ingredient where ingredient.owner_id=v_owner_id and ingredient.normalized_name=v_item.item_normalized_name;
    if v_inventory_match_count>1 then raise exception 'multiple inventory rows match canonical ingredient name'; end if;
    select ingredient.id as ingredient_id,ingredient.quantity as ingredient_quantity,ingredient.unit as ingredient_unit into v_inventory from public.kitchen_ingredients as ingredient where ingredient.owner_id=v_owner_id and ingredient.normalized_name=v_item.item_normalized_name for update;
    if not found then
      insert into public.kitchen_ingredients(owner_id,name,normalized_name,quantity,unit) values(v_owner_id,v_item.item_name,v_item.item_normalized_name,v_item.item_quantity,v_item.item_unit); v_change_count:=v_change_count+1;
    elsif v_inventory.ingredient_quantity is null or v_inventory.ingredient_unit is null then raise exception 'ambiguous inventory quantity or unit cannot be merged';
    else
      v_existing_unit:=lower(btrim(v_inventory.ingredient_unit)); v_incoming_unit:=lower(btrim(v_item.item_unit)); v_incoming_quantity:=v_item.item_quantity;
      if v_existing_unit=v_incoming_unit then null;
      elsif v_existing_unit='g' and v_incoming_unit='kg' then v_incoming_quantity:=v_incoming_quantity*1000;
      elsif v_existing_unit='kg' and v_incoming_unit='g' then v_incoming_quantity:=v_incoming_quantity/1000;
      elsif v_existing_unit='ml' and v_incoming_unit='l' then v_incoming_quantity:=v_incoming_quantity*1000;
      elsif v_existing_unit='l' and v_incoming_unit='ml' then v_incoming_quantity:=v_incoming_quantity/1000;
      else raise exception 'incompatible inventory units cannot be merged'; end if;
      update public.kitchen_ingredients as ingredient set quantity=v_inventory.ingredient_quantity+v_incoming_quantity,updated_at=now() where ingredient.id=v_inventory.ingredient_id and ingredient.owner_id=v_owner_id; v_change_count:=v_change_count+1;
    end if;
  end loop;
  update public.kitchen_shopping_lists as list set status='completed',completed_at=now(),completion_idempotency_key=p_idempotency_key,completion_inventory_change_count=v_change_count,updated_at=now() where list.id=p_list_id and list.owner_id=v_owner_id returning list.completed_at into v_completed_at;
  v_result:=jsonb_build_object('list_id',p_list_id,'status','completed','completed_at',v_completed_at,'purchased_count',v_purchased_count,'skipped_count',v_skipped_count,'unavailable_count',v_unavailable_count,'inventory_change_count',v_change_count);
  insert into public.kitchen_shopping_idempotency(owner_id,operation,idempotency_key,list_id,result) values(v_owner_id,'complete',p_idempotency_key,p_list_id,v_result);
  return query select p_list_id,'completed',false,false,v_completed_at,v_purchased_count,v_skipped_count,v_unavailable_count,v_change_count,p_idempotency_key;
end;
$$;
revoke all on function public.complete_kitchen_shopping_list(uuid,uuid) from public,anon;
grant execute on function public.complete_kitchen_shopping_list(uuid,uuid) to authenticated;
