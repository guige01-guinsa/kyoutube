alter table public.recipes_creator
  add column if not exists source_type text not null default 'manual';

alter table public.recipes_creator
  drop constraint if exists recipes_creator_source_type_check;

alter table public.recipes_creator
  add constraint recipes_creator_source_type_check
  check (
    source_type in (
      'manual',
      'youtube_import',
      'creator_copy'
    )
  );

create index if not exists idx_recipes_creator_source_type
  on public.recipes_creator(source_type);