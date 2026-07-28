# Development Environment

## Goal
Keep local development reproducible, explicit, and free from hidden backend fallbacks.

## Required tools
- Flutter SDK on PATH
- Dart SDK on PATH
- Node.js and npm
- Supabase CLI
- adb for Android device testing
- Docker Desktop for local Supabase

## Standard local config
Create a user-only file at the repo root named `.env.local` by copying `.env.local.example` and filling in the values you actually use for development.

The app runtime still uses `--dart-define`, but this file keeps the values in one place for the helper scripts.
Only the local Supabase values are required for app startup. The optional values are only needed when you want to validate other flows.

## Check the environment
```powershell
.\tools\dev\check-dev-env.ps1
```

The script verifies:
- required commands are installed
- the local env file exists
- the local Supabase keys are present and not placeholders
- optional keys are reported as warnings instead of blocking local startup
- Android Firebase config exists when you are testing Android

## Run local Flutter
```powershell
.\tools\dev\run-local.ps1
```

This reads `.env.local`, resolves `SUPABASE_URL_LOCAL` / `SUPABASE_ANON_KEY_LOCAL`, and launches Flutter with explicit `APP_ENV=local`.

## Recommended first-time setup flow
1. Install the required tools.
2. Copy `.env.local.example` to `.env.local`.
3. Fill local Supabase values first.
4. Add the optional API and secret values only if you want to test those features locally.
5. Run `tools\dev\check-dev-env.ps1` until it reports local keys ready.
6. Start local Supabase.
7. Run `tools\dev\run-local.ps1`.

## What still needs your help
- Real Supabase local values for `.env.local` if they are not already available.
- Production/staging anon keys only if you want me to validate those environments too.
- Any new provider credentials you want enabled locally, such as OAuth values.