create table if not exists public.recipe_youtube_metadata (
  id uuid primary key default gen_random_uuid(),
  recipe_creator_id uuid not null references public.recipes_creator(id) on delete cascade,
  youtube_url text not null,
  youtube_video_id text,
  title text,
  channel_name text,
  author_url text,
  thumbnail_url text,
  provider_name text,
  fetched_at timestamptz not null default now(),
  last_status text not null default 'ok',
  last_error text,
  raw jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(recipe_creator_id)
);

create index if not exists idx_recipe_youtube_metadata_video_id
  on public.recipe_youtube_metadata(youtube_video_id);
create index if not exists idx_recipe_youtube_metadata_fetched_at
  on public.recipe_youtube_metadata(fetched_at desc);

alter table public.recipe_youtube_metadata enable row level security;

create policy "recipe_youtube_metadata_select_own"
on public.recipe_youtube_metadata for select
to authenticated
using (
  exists (
    select 1 from public.recipes_creator rc
    where rc.id = recipe_creator_id
      and rc.author_id = auth.uid()
  )
);

create policy "recipe_youtube_metadata_modify_own"
on public.recipe_youtube_metadata for all
to authenticated
using (
  exists (
    select 1 from public.recipes_creator rc
    where rc.id = recipe_creator_id
      and rc.author_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.recipes_creator rc
    where rc.id = recipe_creator_id
      and rc.author_id = auth.uid()
  )
);

grant select, insert, update, delete on table public.recipe_youtube_metadata to authenticated, service_role;
