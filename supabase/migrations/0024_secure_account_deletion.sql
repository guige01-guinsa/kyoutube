-- Account deletion must go through the delete-account Edge Function.
--
-- The old RPC deletes auth.users directly and would bypass:
-- - Storage image cleanup
-- - AI feedback deletion
-- - AI usage log deletion
--
-- Keep the function definition for backward compatibility, but remove public
-- client execution privileges so authenticated clients cannot bypass cleanup.

revoke all on function public.delete_account() from public;
revoke all on function public.delete_account() from anon;
revoke all on function public.delete_account() from authenticated;