-- Phase 3.5 follow-up: reject direct status injection while preserving the
-- legacy is_checked-only compatibility path. This migration is forward-only.

create or replace function public.sync_kitchen_shopping_item_legacy_check()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $migration_0019$
declare
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

  -- Capture client input before deriving legacy status or synchronizing RPC state.
  v_input_status_changed := new.status is distinct from old.status;
  v_input_checked_changed := new.is_checked is distinct from old.is_checked;
  v_review_rpc := coalesce(current_setting('app.kitchen_review_rpc', true), '') = '1';
  v_status_rpc := coalesce(current_setting('app.kitchen_status_rpc', true), '') = '1';

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

  if v_input_status_changed and not v_status_rpc then
    raise exception 'shopping item status can only change through the status RPC';
  elsif not v_input_status_changed and v_input_checked_changed then
    new.status := case when new.is_checked then 'purchased' else 'pending' end;
  elsif v_input_status_changed and v_input_checked_changed then
    if not v_status_rpc then
      raise exception 'shopping item status can only change through the status RPC';
    end if;
    new.is_checked := (new.status = 'purchased');
  elsif v_status_rpc and v_input_status_changed then
    new.is_checked := (new.status = 'purchased');
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
$migration_0019$;

drop trigger if exists kitchen_shopping_items_legacy_check_sync on public.kitchen_shopping_items;
create trigger kitchen_shopping_items_legacy_check_sync
before insert or update on public.kitchen_shopping_items
for each row execute function public.sync_kitchen_shopping_item_legacy_check();
