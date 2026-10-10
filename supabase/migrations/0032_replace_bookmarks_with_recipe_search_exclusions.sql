-- Replace the pre-release bookmark feature with per-user search exclusions.
-- Existing bookmark rows are intentionally discarded before public launch.

drop table if exists public.bookmarks;

create table public.recipe_search_exclusions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  source_type text not null check (source_type in ('youtube', 'public')),
  source_id text not null check (length(trim(source_id)) > 0),
  title text not null check (length(trim(title)) > 0),
  summary text,
  ingredients jsonb not null default '[]'::jsonb,
  steps jsonb not null default '[]'::jsonb,
  image_url text,
  youtube_url text,
  reason_codes jsonb not null default '[]'::jsonb,
  status text not null default 'hidden'
    check (status in ('hidden', 'needs_edit', 'resolved')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, source_type, source_id),
  check (jsonb_typeof(ingredients) = 'array'),
  check (jsonb_typeof(steps) = 'array'),
  check (jsonb_typeof(reason_codes) = 'array')
);

create index recipe_search_exclusions_user_status_created_idx
  on public.recipe_search_exclusions(user_id, status, created_at desc);

alter table public.recipe_search_exclusions enable row level security;

create policy recipe_search_exclusions_select_own
on public.recipe_search_exclusions for select
to authenticated
using (user_id = auth.uid());

create policy recipe_search_exclusions_insert_own
on public.recipe_search_exclusions for insert
to authenticated
with check (user_id = auth.uid());

create policy recipe_search_exclusions_update_own
on public.recipe_search_exclusions for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy recipe_search_exclusions_delete_own
on public.recipe_search_exclusions for delete
to authenticated
using (user_id = auth.uid());

grant select, insert, update, delete
  on table public.recipe_search_exclusions to authenticated, service_role;

