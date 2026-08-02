# K-youtube contributor guide

## Purpose and architecture

K-youtube is an Android-first AI cooking platform. The Flutter app uses Riverpod for application state, `go_router` for declarative routes, Supabase for authentication, PostgreSQL, Storage and Edge Functions, and Firebase for mobile messaging. See `docs/ARCHITECTURE.md` for the code-backed component map.

## Repository map

- `lib/` — Flutter application, organised into `core/` and feature folders.
- `test/` — Flutter unit and widget tests.
- `supabase/migrations/` — immutable, ordered database migrations.
- `supabase/functions/` — Deno/TypeScript Edge Functions.
- `android/`, `ios/` — platform projects.
- `tools/dev/` — reproducible local-development scripts.
- `docs/` — developer, architecture, security, and planning documentation.

## Toolchain and routine

- Flutter **3.44.8** is pinned in `.fvmrc`. Use that version; do not silently upgrade it.
- The Android project targets JVM 17. Install and select JDK 17 for Android/Gradle work.
- First-run environment check: `powershell -ExecutionPolicy Bypass -File tools/dev/bootstrap.ps1`.
- Run the app only through `powershell -ExecutionPolicy Bypass -File run-local.ps1 -AppEnv local`.
- Validate a change with `powershell -ExecutionPolicy Bypass -File tools/dev/verify.ps1`, which runs `flutter doctor -v`, `flutter analyze`, and `flutter test`.
- Use `flutter pub get` after dependency or lockfile changes.

## Flutter conventions

- Preserve the existing feature-first layout and the current Riverpod provider patterns. Keep business logic outside presentation widgets.
- Add routes centrally in `lib/core/router/app_router.dart`; use `go_router` navigation instead of ad-hoc route stacks.
- Make the smallest compatible change, preserve existing code style, and add or update tests with behaviour changes.
- Do not commit generated code, `build/`, `.dart_tool/`, or `.flutter-plugins-dependencies`.

## Supabase and Edge Functions

- Start the local stack with `npx supabase@latest start -x studio,logflare,imgproxy`; inspect it with `npx supabase@latest status`.
- Never edit an existing file in `supabase/migrations/`. Add a new ordered migration for every schema/policy change.
- Edge Functions use TypeScript/Deno. Keep secrets in local ignored files or platform secrets; do not place them in source, examples, logs, or commits.
- Test Edge Functions locally before proposing a deployment. Do not deploy functions, push migrations, or reset a database without explicit user approval.

## Safety gates

- Never print, commit, or copy values from `.env*`, keystores, `key.properties`, `local.properties`, certificates, or credentials.
- Never run `supabase db reset`, `supabase db push`, a production migration, a release build, or a deployment without explicit user approval.
- Do not change Android signing keys, Firebase/Supabase project configuration, package versions, or product behaviour unless the task requires it.
- After changes, run `flutter analyze` and `flutter test`; report failures rather than making unrelated product-code fixes.
