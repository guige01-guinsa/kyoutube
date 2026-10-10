-- These RPCs already require a logged-in identity internally; remove unused
-- public/anon invocation rights while preserving authenticated callers.
revoke execute on function public.consume_youtube_search_rate_limit() from public, anon;
grant execute on function public.consume_youtube_search_rate_limit() to authenticated, service_role;
revoke execute on function public.promote_subscriber_recipe_to_creator(uuid,boolean,boolean,boolean,boolean,boolean) from public, anon;
grant execute on function public.promote_subscriber_recipe_to_creator(uuid,boolean,boolean,boolean,boolean,boolean) to authenticated, service_role;
