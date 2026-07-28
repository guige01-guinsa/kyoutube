# Development Environment Standard

## Goal
Keep local dev, CI, and Play internal-test release output deterministic.

## Required toolchain
- Flutter: 3.44.8 (pin with `.fvmrc`)
- Dart: bundled with Flutter 3.44.8
- Android SDK: 36.0.0
- Java: JDK 21 for Android builds
- Supabase CLI: latest stable

## Local setup
1. Copy `.env.local.example` to `.env.local`.
2. Fill `SUPABASE_*` values for your target environment.
3. Fill `PUBLIC_RECIPE_SYNC_WORKER_SECRET` and keep it aligned with Supabase Edge Function secret.
4. Run `tools/dev/check-dev-env.ps1`.
5. Start app with `run-local.ps1 -AppEnv local` or VS Code launch profile.

## VS Code launch profiles
Use `.vscode/launch.json` profiles:
- `k_youtube (local)`
- `k_youtube (staging)`
- `k_youtube (production)`

All profiles inject:
- `--dart-define-from-file=.env.local`
- explicit `APP_ENV`

## Release source-of-truth
- Internal-track release workflow must run from `main` only.
- Release version comes from `pubspec.yaml`.
- Each Play upload must use a strictly increasing versionCode.

## Release checklist
1. Ensure `pubspec.yaml` versionCode is new.
2. Ensure production `SUPABASE_URL_PRODUCTION` and `SUPABASE_ANON_KEY_PRODUCTION` are real values.
3. Ensure `PUBLIC_RECIPE_SYNC_WORKER_SECRET` is synced between Supabase and local env files.
4. Run `tools/release/run-internal-track-validation.ps1`.
5. Upload `build/app/outputs/bundle/release/app-release.aab` to Play Internal testing.
