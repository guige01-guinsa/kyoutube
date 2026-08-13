-- Empty cleanup actions should not occupy one of the three undo slots.
-- Existing empty snapshots are expired, while future ones are expired by trigger.

create or replace function public.expire_empty_kitchen_cleanup_snapshot()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if coalesce(jsonb_array_length(new.ingredient_rows), 0) = 0
     and coalesce(jsonb_array_length(new.shopping_list_states), 0) = 0 then
    new.expires_at := transaction_timestamp();
  end if;

  return new;
end;
$$;

drop trigger if exists kitchen_cleanup_snapshots_expire_empty
  on public.kitchen_cleanup_snapshots;

create trigger kitchen_cleanup_snapshots_expire_empty
before insert on public.kitchen_cleanup_snapshots
for each row
execute function public.expire_empty_kitchen_cleanup_snapshot();

update public.kitchen_cleanup_snapshots
set expires_at = transaction_timestamp()
where restored_at is null
  and coalesce(jsonb_array_length(ingredient_rows), 0) = 0
  and coalesce(jsonb_array_length(shopping_list_states), 0) = 0;