alter table public.recipes_user
add column if not exists source_type text not null default 'manual';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'recipes_user_source_type_check'
      and conrelid = 'public.recipes_user'::regclass
  ) then
    alter table public.recipes_user
      add constraint recipes_user_source_type_check
      check (source_type in ('manual', 'public_import', 'youtube_import', 'creator_copy'));
  end if;
end $$;

update public.recipes_user
set source_type = 'manual'
where source_type is null or btrim(source_type) = '';