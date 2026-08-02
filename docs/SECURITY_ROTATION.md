# Security rotation guidance

## Scope

The root `.env` was previously Git-tracked and is now ignored and removed from the Git index. No history rewrite has been performed. Treat any credential variable that may have appeared there as potentially exposed and rotate it in the owning provider before using it again.

## Variables requiring owner review

- `SUPABASE_URL_PRODUCTION`
- `SUPABASE_ANON_KEY_PRODUCTION`
- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_DB_PASSWORD`
- `FIREBASE_PROJECT_ID`
- `OPENAI_API_KEY`
- `FOOD_API_KEY`

Also review the local-only variables used by app and worker workflows: `SUPABASE_URL_LOCAL`, `SUPABASE_ANON_KEY_LOCAL`, `SUPABASE_URL_STAGING`, `SUPABASE_ANON_KEY_STAGING`, and `PUBLIC_RECIPE_SYNC_WORKER_SECRET`.

## Rotation procedure

1. Identify the credential owner and current production dependency without copying a value into tickets, chat, or Git.
2. Create a replacement in the provider, update the approved secret store/local ignored file, and deploy only through the approved release process.
3. Verify the dependent app/function with a least-privileged smoke test.
4. Revoke the old credential after the replacement is confirmed.
5. Record the completion date and owner in the security system, not in this repository.

Do not rewrite Git history as part of this repository cleanup without a separately approved incident response plan.
