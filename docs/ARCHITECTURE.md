# Architecture

## Business meal planning (source complete, deployment pending, 2026-09-25)

The `/business-workspaces/:workspace/meals` calendar uses `BusinessMealRepository` and dedicated `business_meal_plans` / history tables from migration 0072. Recipe and menu references are resolved server-side into immutable recipe revisions and ingredient requirements. Draft editing uses `recipes.write`, confirmation reuses `menus.approve`, and purchasing retains existing purchasing permissions. Confirmed meal sources flow through menu fast purchasing, supplier mappings and stock reservation logic; a unique meal-to-batch link prevents duplicate procurement even across different retry tokens. Period copies create drafts atomically and never overwrite existing dates/services. Legacy generic meal records remain accessible. See [business-meal-planning.md](business-meal-planning.md).

## Business workspaces (v74 production release, 2026-09-19)

Professional home/navigation preferences now distinguish purchasing, culinary,
and management duties. They do not authorize data access. The opt-in
`lib/features/business/` feature uses separate shared records and server-enforced
membership/permissions under migration `0062_business_workspaces.sql`.
Owners invite verified-email staff, assign individual read/write/approval grants,
and review access history. Recipe/meal, purchase approval/receipt and cost/sales
flows retain separate cooking and purchase quantities. Personal tables are not
migrated or shared automatically. DB 0062 and the v74 web client are deployed;
the signed Android 1.0.1+74 AAB is generated (Play upload is separate). See
[release-v74.md](release-v74.md) for release evidence and
[business-workspaces.md](business-workspaces.md) for the permission matrix,
validation, limitations and rollout order. Older sections below describe prior
implementation milestones.


## Integrated web workspace (v65 source, 2026-09-15)

The Flutter client now has a browser entry point (`web/`) and a responsive workspace shell. Mobile and web use the same repositories, Supabase Auth, RLS, membership and quota RPCs. Wide screens add a persistent navigation rail, recipe columns and a chef ingredient table with cost summary. Browser-specific OAuth callbacks and request-document downloads are isolated behind platform adapters. Saved records are shared; unsaved edits and shopping preparation drafts remain device-local. Web checkout, offline mode and web push are not implemented. See [web-workspace.md](web-workspace.md) for verification and publication prerequisites. This is local development; the deployed Android artifact remains v65.


## Flutter client

`lib/main.dart` creates the Flutter binding, initializes `OpsMonitorService`, installs Flutter/platform/zone error capture, validates runtime environment values, and mounts a Riverpod `ProviderScope`. `lib/app.dart` then initializes Supabase, followed by optional Firebase and messaging initialization with bounded waits, before rendering the routed application.

`lib/core/config/env.dart` selects Supabase runtime values from `APP_ENV` (`local`, `staging`, `production`) and the corresponding `SUPABASE_URL_*`/`SUPABASE_ANON_KEY_*` defines. `tools/dev/run-local.ps1` supplies these with `.env.local` through `--dart-define-from-file`.

## Navigation and state

The mobile app has four top-level destinations: Search (`/`), My recipes
(`/my-recipes`), Shopping (`/kitchen?tab=shopping`), and Chef (`/chef`). The web starts
at `/workspace` and adds a desktop sidebar for recipes, chef work, shopping, stores,
purchase requests and sales. The Chef hub selects an owned creator recipe before
opening the existing `/chef/:id` editor. Existing server membership RPCs decide
feature access on both platforms. Web checkout is not implemented, and actual
Google Play billing activation remains separate from this web expansion. See
[web-workspace.md](web-workspace.md) for the current validation and publication boundary.

`lib/core/router/app_router.dart` owns the static `GoRouter` route table for home, login, search exclusions, recipe detail, creator, subscriber recipe, membership, and kitchen paths. Route changes belong there rather than in individual widgets.

Feature code is grouped under `lib/features/`. Riverpod providers coordinate UI, application services, and repositories (for example recipe and kitchen providers). Data repositories use the Supabase Flutter client or Edge Function APIs; presentation widgets consume provider state rather than constructing backend clients.

The home catalog is an app-bundled editorial selection in
`lib/features/home/domain/korean_classics.dart`. Its fifteen dishes each have separate Korean and English video sources; the
locale-matched links and labels are independent of auth and public recipe search. `/classics/:id` shows
source links and cooking focus; `/classics/:id/draft` checks auth before mounting
the existing AI enrichment flow. Public recipes remain available via search.
See `docs/korean-classics.md` for source verification and update procedures.

## Backend services

Supabase migrations in `supabase/migrations/` define PostgreSQL schema, RLS, grants, storage, profiles, public recipe seed data, and kitchen foundations. They are chronological artifacts: never edit an existing migration; append a new migration for a change.

Membership state is server-owned. Migration `0031` defines the Free, Monthly
Premium, and Annual Basic plans, Google Play entitlements, administration
audit events, and atomic AI usage reservations. The `membership` Edge Function
verifies purchase tokens with Google Play before granting access, while both AI
recipe functions reserve and finalize quota on the server.

The following Deno Edge Functions are present:

- `recipe_api` handles public recipe reads, authenticated creator operations, and kitchen requests through HTTP/Supabase APIs.
- `ai_recipe_assistant` and `ai_youtube_recipe_assistant` generate server-side recipe drafts with `gpt-5.4-mini` by default. The YouTube flow can fall back to `gpt-4o-mini` only when the primary model is unavailable. Both functions reject any configured recipe model outside those two aliases. The YouTube flow returns structured servings, cooking times, ingredient quantities, step-to-ingredient links, and evidence status while keeping the existing editable string fields compatible with the Flutter client.
- `public_recipe_sync` accepts a worker-secret protected POST, optionally fetches the public food API, and upserts `recipes_public` through a service-role server path. It requires local secret configuration to exercise non-fallback/upsert paths.

## Firebase

`FirebaseBootstrap` initializes Firebase on Android/iOS only. `FirebaseMessagingService` registers background/foreground messaging, permission handling, and diagnostic state. Platform Firebase configuration files are intentionally ignored and must remain local/CI secrets.

## Operations (deployed with v57, 2026-09-13)

`lib/core/ops/ops_telemetry.dart` reports allowlisted error categories after
authenticated Supabase initialization. It never forwards the local diagnostic
message, stack, recipe or URL. `0036_operations_observability.sql` rate-limits
client reports and restricts overview/cost RPCs to profile administrators.
`lib/features/operations/` provides the bilingual dashboard at
`/membership/admin/operations`, reached through membership administration.

`supabase/functions/_shared/operations.ts` observes seven HTTP handlers and
persists safe outcome/status/duration fields with bounded background delivery.
The overview aggregates observations and existing AI usage reservations; manual
monthly billing snapshots and an audit table track actual costs without guessing
token prices. Migration 0040 adds an administrator-only inbox, session-bound FCM devices, state transitions and leased push retries. A Vault-authenticated operations_monitor runs every five minutes. Firebase sender credentials and real-device delivery remain pending. No automatic resizing or spend cutoff is provided.
Event retention needs the separately registered daily purge job. See
[OPERATIONS_RUNBOOK.md](OPERATIONS_RUNBOOK.md) for coverage and deployment order.

## Client/server boundaries

The Flutter client holds only runtime Supabase publishable/anon configuration. Privileged public-recipe synchronization stays inside the Edge Function with server-side credentials. CI quality checks do not connect to Supabase or Firebase and do not deploy services.

## Security review (source changes, 2026-09-13)

Account-scoped Riverpod providers observe the active user ID; logout returns to
home to dispose private editing screens. New creator saves and copied recipes
use a private default. The metadata function verifies a signed-in, non-anonymous
Supabase user before calling YouTube. Shared HTTP helpers bound external calls,
and API 5xx responses omit upstream details.

Migrations 0042–0046 and the five affected functions are deployed. Personal
creator rows and their image bucket are private. Raw chef financial documents
require active paid membership; free scaling and version reads use redacted RPC
projections. The daily telemetry purge uses an explicit service-role context.
Migrations 0047–0048 wait for administrator TOTP enrollment before server MFA
enforcement. Google billing/FCM credentials, plan-limited breached-password
protection and full Auth recovery remain pending. See
[the rollout record](security-rollout-2026-09-13.md) for actual deployment and
verification evidence. These client changes target v59, not the previous v58 AAB.
