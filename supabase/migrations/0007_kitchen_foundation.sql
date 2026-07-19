create table if not exists public.kitchen_ingredients (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  normalized_name text not null,
  quantity numeric(12,2),
  unit text,
  storage_location text,
  expires_on date,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.kitchen_shopping_lists (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'active' check (status in ('active','completed','archived')),
  title text not null default 'AI generated shopping list',
  source_recipe_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.kitchen_shopping_items (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null references public.kitchen_shopping_lists(id) on delete cascade,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  normalized_name text not null,
  quantity numeric(12,2),
  unit text,
  is_checked boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.kitchen_cook_sessions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  recipe_type text not null check (recipe_type in ('public','creator','user')),
  recipe_ref_id text not null,
  recipe_title text not null,
  consumed_ingredients jsonb not null default '[]'::jsonb,
  missing_ingredients jsonb not null default '[]'::jsonb,
  rating integer check (rating between 1 and 5),
  liked boolean,
  note text,
  created_at timestamptz not null default now()
);

create unique index if not exists uq_kitchen_ingredients_owner_normalized
  on public.kitchen_ingredients(owner_id, normalized_name);

create index if not exists idx_kitchen_ingredients_owner on public.kitchen_ingredients(owner_id);
create index if not exists idx_kitchen_ingredients_expires_on on public.kitchen_ingredients(owner_id, expires_on);
create index if not exists idx_kitchen_shopping_lists_owner_status on public.kitchen_shopping_lists(owner_id, status);
create index if not exists idx_kitchen_shopping_items_owner_list on public.kitchen_shopping_items(owner_id, list_id);
create index if not exists idx_kitchen_shopping_items_owner_checked on public.kitchen_shopping_items(owner_id, is_checked);
create index if not exists idx_kitchen_cook_sessions_owner_created_at on public.kitchen_cook_sessions(owner_id, created_at desc);

alter table public.kitchen_ingredients enable row level security;
alter table public.kitchen_shopping_lists enable row level security;
alter table public.kitchen_shopping_items enable row level security;
alter table public.kitchen_cook_sessions enable row level security;

create policy "kitchen_ingredients_all_own"
on public.kitchen_ingredients for all
to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

create policy "kitchen_shopping_lists_all_own"
on public.kitchen_shopping_lists for all
to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

create policy "kitchen_shopping_items_all_own"
on public.kitchen_shopping_items for all
to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

create policy "kitchen_cook_sessions_all_own"
on public.kitchen_cook_sessions for all
to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

grant select, insert, update, delete on table public.kitchen_ingredients to authenticated, service_role;
grant select, insert, update, delete on table public.kitchen_shopping_lists to authenticated, service_role;
grant select, insert, update, delete on table public.kitchen_shopping_items to authenticated, service_role;
grant select, insert, update, delete on table public.kitchen_cook_sessions to authenticated, service_role;
