BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '30s';

with metrics as (
  select
    count(*) as total_items,
    count(*) filter (where list.status = 'active') as active_items,
    count(*) filter (where list.status = 'completed') as completed_items,
    count(*) filter (where list.status = 'cancelled') as cancelled_items,
    count(*) filter (where list.status = 'archived') as archived_items,
    count(*) filter (where item.status = 'pending') as pending_items,
    count(*) filter (where item.status = 'purchased') as purchased_items,
    count(*) filter (where item.status = 'skipped') as skipped_items,
    count(*) filter (where item.status = 'unavailable') as unavailable_items,
    count(*) filter (where item.quantity is null and item.unit is not null) as quantity_null_unit_present,
    count(*) filter (where item.quantity is not null and item.unit is null) as quantity_present_unit_null,
    count(*) filter (where item.quantity <= 0) as quantity_nonpositive,
    count(*) filter (where item.unit is not null and btrim(item.unit) not in ('g','kg','ml','l','ea')) as noncanonical_unit,
    count(*) filter (where item.status = 'purchased' and (btrim(coalesce(item.name,'')) = '' or btrim(coalesce(item.normalized_name,'')) = '' or item.quantity is null or item.quantity <= 0 or item.unit is null or btrim(item.unit) not in ('g','kg','ml','l','ea'))) as purchased_review_invariant_violation,
    count(*) filter (where item.updated_at is null) as updated_at_null,
    count(*) filter (where item.is_checked is distinct from (item.status = 'purchased')) as status_is_checked_mismatch,
    count(*) filter (where btrim(coalesce(item.name,'')) = '') as name_blank,
    count(*) filter (where btrim(coalesce(item.normalized_name,'')) = '') as normalized_name_blank,
    count(*) filter (where btrim(coalesce(item.ingredient_text,'')) = '') as ingredient_text_blank
  from public.kitchen_shopping_items as item
  join public.kitchen_shopping_lists as list on list.id = item.list_id
), duplicates as (
  select count(*) as active_normalized_name_duplicate_groups
  from (
    select item.list_id, item.normalized_name
    from public.kitchen_shopping_items as item
    join public.kitchen_shopping_lists as list on list.id = item.list_id
    where list.status = 'active'
    group by item.list_id, item.normalized_name
    having count(*) > 1
  ) as grouped
), mismatches as (
  select count(*) as owner_list_owner_mismatch
  from public.kitchen_shopping_items as item
  join public.kitchen_shopping_lists as list on list.id = item.list_id
  where item.owner_id is distinct from list.owner_id
)
select 'total_items=' || total_items from metrics
union all select 'active_items=' || active_items from metrics
union all select 'completed_items=' || completed_items from metrics
union all select 'cancelled_items=' || cancelled_items from metrics
union all select 'archived_items=' || archived_items from metrics
union all select 'pending_items=' || pending_items from metrics
union all select 'purchased_items=' || purchased_items from metrics
union all select 'skipped_items=' || skipped_items from metrics
union all select 'unavailable_items=' || unavailable_items from metrics
union all select 'quantity_null_unit_present=' || quantity_null_unit_present from metrics
union all select 'quantity_present_unit_null=' || quantity_present_unit_null from metrics
union all select 'quantity_nonpositive=' || quantity_nonpositive from metrics
union all select 'noncanonical_unit=' || noncanonical_unit from metrics
union all select 'purchased_review_invariant_violation=' || purchased_review_invariant_violation from metrics
union all select 'active_normalized_name_duplicate_groups=' || active_normalized_name_duplicate_groups from duplicates
union all select 'owner_list_owner_mismatch=' || owner_list_owner_mismatch from mismatches
union all select 'updated_at_null=' || updated_at_null from metrics
union all select 'status_is_checked_mismatch=' || status_is_checked_mismatch from metrics
union all select 'name_blank=' || name_blank from metrics
union all select 'normalized_name_blank=' || normalized_name_blank from metrics
union all select 'ingredient_text_blank=' || ingredient_text_blank from metrics;

ROLLBACK;
