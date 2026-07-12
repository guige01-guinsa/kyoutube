grant usage on schema public to anon, authenticated, service_role;

grant select, insert, update on table public.recipes_public to anon, authenticated, service_role;
grant select, insert, update, delete on table public.profiles to authenticated, service_role;
grant select, insert, update, delete on table public.recipes_creator to authenticated, service_role;
grant select, insert, update, delete on table public.recipes_user to authenticated, service_role;
grant select, insert, update, delete on table public.bookmarks to authenticated, service_role;
grant select, insert, update, delete on table public.shopping_lists to authenticated, service_role;
grant select, insert on table public.ai_usage_logs to authenticated, service_role;

grant usage, select on all sequences in schema public to authenticated, service_role;
