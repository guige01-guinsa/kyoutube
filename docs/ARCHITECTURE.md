# Architecture

## Flutter client

`lib/main.dart` creates the Flutter binding, initializes `OpsMonitorService`, installs Flutter/platform/zone error capture, validates runtime environment values, and mounts a Riverpod `ProviderScope`. `lib/app.dart` then initializes Firebase Messaging followed by Supabase before rendering the routed application.

`lib/core/config/env.dart` selects Supabase runtime values from `APP_ENV` (`local`, `staging`, `production`) and the corresponding `SUPABASE_URL_*`/`SUPABASE_ANON_KEY_*` defines. `tools/dev/run-local.ps1` supplies these with `.env.local` through `--dart-define-from-file`.

## Navigation and state

`lib/core/router/app_router.dart` owns the static `GoRouter` route table for home, login, bookmarks, recipe detail, creator, subscriber recipe, and kitchen paths. Route changes belong there rather than in individual widgets.

Feature code is grouped under `lib/features/`. Riverpod providers coordinate UI, application services, and repositories (for example recipe and kitchen providers). Data repositories use the Supabase Flutter client or Edge Function APIs; presentation widgets consume provider state rather than constructing backend clients.

## Backend services

Supabase migrations in `supabase/migrations/` define PostgreSQL schema, RLS, grants, storage, profiles, public recipe seed data, and kitchen foundations. They are chronological artifacts: never edit an existing migration; append a new migration for a change.

The following Deno Edge Functions are present:

- `recipe_api` handles public recipe reads, authenticated creator operations, and kitchen requests through HTTP/Supabase APIs.
- `ai_recipe_assistant` currently returns a placeholder recipe summary; it has no visible production AI provider integration or function-level tests.
- `public_recipe_sync` accepts a worker-secret protected POST, optionally fetches the public food API, and upserts `recipes_public` through a service-role server path. It requires local secret configuration to exercise non-fallback/upsert paths.

## Firebase

`FirebaseBootstrap` initializes Firebase on Android/iOS only. `FirebaseMessagingService` registers background/foreground messaging, permission handling, and diagnostic state. Platform Firebase configuration files are intentionally ignored and must remain local/CI secrets.

## Boundaries

The Flutter client holds only runtime Supabase publishable/anon configuration. Privileged public-recipe synchronization stays inside the Edge Function with server-side credentials. CI quality checks do not connect to Supabase or Firebase and do not deploy services.
