-- The link belongs to both parents. Account/workspace erasure may cascade through
-- the batch before the meal; do not let that order block the entire account deletion.
begin;
alter table public.business_meal_purchase_links
 drop constraint business_meal_purchase_links_batch_id_fkey,
 add constraint business_meal_purchase_links_batch_id_fkey
 foreign key(batch_id) references public.business_menu_batches(id) on delete cascade;
commit;
