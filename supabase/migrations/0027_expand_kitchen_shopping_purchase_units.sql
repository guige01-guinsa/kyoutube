-- Shopping quantities describe what a user buys, not a converted recipe amount.
-- Keep the original cooking wording in kitchen_shopping_items.ingredient_text.
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
    when '' then null
    when 'g' then 'g' when 'kg' then 'kg' when 'oz' then 'oz' when 'lb' then 'lb'
    when 'ml' then 'ml' when 'l' then 'l' when 'tsp' then 'tsp' when 'tbsp' then 'tbsp'
    when 'cup' then 'cup' when 'fl_oz' then 'fl_oz' when 'pint' then 'pint'
    when 'quart' then 'quart' when 'gallon' then 'gallon'
    when 'ea' then 'ea' when '개' then 'ea' when 'piece' then 'piece' when 'slice' then 'slice'
    when 'clove' then 'clove' when 'stalk' then 'stalk' when 'head' then 'head' when 'dozen' then 'dozen'
    when 'pack' then 'pack' when 'bag' then 'bag' when 'bottle' then 'bottle' when 'jar' then 'jar'
    when 'can' then 'can' when 'carton' then 'carton' when 'box' then 'box' when 'case' then 'case'
    when 'bundle' then 'bundle' when 'bunch' then 'bunch' when 'net' then 'net'
    when 'container' then 'container' when 'sachet' then 'sachet' when 'pouch' then 'pouch' when 'tube' then 'tube'
    when 'tray' then 'tray' when 'roll' then 'roll'
    else '__invalid__'
  end;
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
