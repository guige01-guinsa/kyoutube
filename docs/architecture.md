# Architecture

## MVP flows
1. Public recipes: synced from government API, read-only in app.
2. Creator recipes: author-managed CRUD with ownership policies.
3. Subscriber recipes: personal copy, notes, visibility control.

## Components
- Flutter app
- Supabase Auth/Postgres/Storage/Edge Functions
- Government recipe API sync function
- OpenAI orchestration function
- YouTube metadata fetch worker

## Data boundaries
- Mobile app uses anon key only.
- Service role key remains server-only.
- All write paths go through RLS-safe tables/functions.
- Diagnostics and shareable operational reports must redact tokens, keys, and bearer credentials.
- User-input validation should reject obviously invalid or oversized content before it reaches backend writes.
