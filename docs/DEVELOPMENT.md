# Development workflow

## Supported Windows environment

Use PowerShell from the repository root. Flutter 3.44.8 is pinned by `.fvmrc`. The Android project uses AGP 9.0.1, Gradle 9.1.0, `JavaVersion.VERSION_17`, and Kotlin `JVM_17`; therefore JDK 17 is the supported development JDK. Do not change Gradle or Android tool versions merely to match a globally installed JDK.

## First use and daily loop

```powershell
powershell -ExecutionPolicy Bypass -File tools/dev/bootstrap.ps1
powershell -ExecutionPolicy Bypass -File run-local.ps1 -AppEnv local
powershell -ExecutionPolicy Bypass -File tools/dev/verify.ps1
```

`bootstrap.ps1` validates tools and runs `flutter pub get`. Use `-SkipPubGet` only when dependencies are already present. `verify.ps1` runs `flutter doctor -v`, `flutter analyze`, and `flutter test`; it is intentionally non-deploying.

## Local configuration

Keep runtime defines in `.env.local`, copied from `.env.local.example` or `.env.example`. The runner passes it through `--dart-define-from-file` and selects `APP_ENV`. Do not place API keys, tokens, Firebase files, signing files, or Supabase credentials in source control. The scripts only test file presence and never echo contents.

For an Android device using local Supabase, run `adb reverse tcp:54321 tcp:54321` before `run-local.ps1`. Firebase is initialized on Android/iOS; keep the platform configuration files local and ignored.

## Supabase local work

Start the local stack with:

```powershell
npx supabase@latest start -x studio,logflare,imgproxy
npx supabase@latest status
```

Do not run `supabase db reset`, `supabase db push`, or deployment commands as part of routine development. Existing SQL migrations are immutable. A database change requires a new, ordered file under `supabase/migrations/`, review, and explicit approval before any remote action.

Edge Functions live under `supabase/functions/` and use Deno TypeScript imports. Test request validation, authentication, and error paths locally. `public_recipe_sync` needs local function secrets for its worker/API paths; never commit them or invoke production endpoints from normal development commands.

## Change and review checklist

1. Keep Flutter changes scoped to the feature and existing Riverpod/go_router patterns.
2. Add or update a test for observable behaviour where practical.
3. Run `flutter analyze` and `flutter test`.
4. Review `git diff --check`, `git diff`, and `git status` without displaying ignored secret contents.
5. Do not commit generated build files or machine-specific IDE state.

## CI

`flutter-quality.yml` runs on normal pushes and pull requests without secrets: pinned Flutter setup, dependency resolution, analysis, and tests. Deployment and migration workflows remain manual and separate.
