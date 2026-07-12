alter table public.profiles enable row level security;
alter table public.recipes_public enable row level security;
alter table public.recipes_creator enable row level security;
alter table public.recipes_user enable row level security;
alter table public.bookmarks enable row level security;
alter table public.shopping_lists enable row level security;
alter table public.ai_usage_logs enable row level security;

create policy "profiles_select_own"
on public.profiles for select
to authenticated
using (auth.uid() = id);

create policy "profiles_update_own"
on public.profiles for update
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

create policy "public_recipes_read"
on public.recipes_public for select
to anon, authenticated
using (true);

create policy "creator_recipes_read_published"
on public.recipes_creator for select
to anon, authenticated
using (is_published = true or auth.uid() = author_id);

create policy "creator_recipes_insert_own"
on public.recipes_creator for insert
to authenticated
with check (auth.uid() = author_id);

create policy "creator_recipes_update_own"
on public.recipes_creator for update
to authenticated
using (auth.uid() = author_id)
with check (auth.uid() = author_id);

create policy "creator_recipes_delete_own"
on public.recipes_creator for delete
to authenticated
using (auth.uid() = author_id);

create policy "user_recipes_read_own_or_public"
on public.recipes_user for select
to authenticated
using (owner_id = auth.uid() or visibility = 'public');

create policy "user_recipes_insert_own"
on public.recipes_user for insert
to authenticated
with check (owner_id = auth.uid());

create policy "user_recipes_update_own"
on public.recipes_user for update
to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

create policy "user_recipes_delete_own"
on public.recipes_user for delete
to authenticated
using (owner_id = auth.uid());

create policy "bookmarks_all_own"
on public.bookmarks for all
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "shopping_lists_all_own"
on public.shopping_lists for all
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "ai_logs_insert_authenticated"
on public.ai_usage_logs for insert
to authenticated
with check (user_id = auth.uid());

create policy "ai_logs_select_own"
on public.ai_usage_logs for select
to authenticated
using (user_id = auth.uid());
