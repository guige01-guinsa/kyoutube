# Google Play Release Readiness

Last update: 2026-07-23

## Current estimate
- Overall readiness: 85%

## Scoring model
- Product stability (30%): 27/30
- Release engineering (25%): 17/25
- Store policy and legal (20%): 17/20
- Security and operations (15%): 14/15
- QA and observability (10%): 10/10

## Done
- Flutter analyze and tests are green.
- Stability closeout on 2026-07-23 completed with no feature expansion: `flutter analyze lib test` pass and `flutter test` pass after test-harness-only fix.
- Supabase environment separation exists (`local`, `staging`, `production`).
- Android release signing now fails by default when release keystore is not configured.
- Android Firebase config file `android/app/google-services.json` is now present in workspace.
- Voice guidance state and persistence flows are implemented (current release candidate uses silent fallback runtime to avoid native build instability).
- Startup bootstrap now surfaces environment and initialization failures to users.
- Home screen includes an 운영 상태 card for recent errors and report export.
- Dedicated 운영 대시보드 (`/ops`) exists for env/startup/FCM/Supabase connectivity checks.
- Smoke and staging UAT checklists are documented in `docs/ops-smoke-checklist.md` and `docs/staging-uat-checklist.md`.
- Privacy, terms, and Data safety drafts are documented in `docs/privacy-policy.md`, `docs/terms-of-service.md`, and `docs/google-play-data-safety.md`.
- Step 2/3 execution evidence is documented in `docs/ops-policy-step2-3-execution-2026-07-22.md`.
- Step 4 performance certification gate is passed (`FINAL_PASS=True`) and closed.
- Account management UX for release user-path is strengthened (`/profile`: profile edit, logout, identity link/unlink, lifecycle-based refresh).
- Login path now clearly handles Kakao non-production state (disabled with guidance when `KAKAO_OAUTH_ENABLED=false`).

## Blocking gaps before production rollout
- Configure real upload keystore and validate signed AAB in Play Console internal testing.
- Resolve Windows application control block for Flutter release AOT (`gen_snapshot.EXE`), or run release build on an approved CI/host.
- Add `GoogleService-Info.plist` for iOS Firebase project if iOS release path remains in scope.
- Execute final Firebase Console production push send/receive validation against the release app id.
- Submit Play Console Data safety form using the finalized package in `docs/google-play-data-safety.md`.
- Create Play Store assets: icon, feature graphic, screenshots, short/full description.

## Pre-release key rotation checks (required)
- Rotate provider/client secrets used during local validation before production rollout (Google OAuth secret, worker secrets, and any leaked legacy values).
- Verify rotated values are only referenced via environment variables (`env(...)` style) in tracked config files.
- Confirm old secret values are revoked in provider consoles and cannot authenticate anymore.
- Re-run `tools/release/run-internal-track-validation.ps1` with production values after rotation.
- For CI, run `.github/workflows/internal-track-release-guard.yml` and confirm both guardrails pass:
  - CI blocks `-LocalVerification`.
  - required production secrets and `PUBLIC_RECIPE_SYNC_WORKER_SECRET` are present.

## Recommended execution plan
1. Release gate validation (today)
- Create `android/key.properties` with real keystore values.
- Build AAB without debug-signing override.
- Upload to internal testing track.
- Verify the script `tools/release/run-internal-track-validation.ps1` produces `build/app/outputs/bundle/release/app-release.aab`.
- Verify `public_recipe_sync` smoke automation passes (401 without/invalid `x-worker-secret`, 2xx with valid `x-worker-secret`).

2. Policy package (next)
- Publish the privacy policy page and terms page using the draft docs.
- Fill Data safety and content rating questionnaires.
- Verify permission declarations match app behavior.

3. Production hardening (next)
- Review the 운영 상태 card and recent error log after each internal build.
- Run Supabase connectivity check from 운영 대시보드 (`/ops`) on each internal build.
- Use the smoke checklist for login, recipe browse, creator CRUD, and voice-guide controls.
- Run staging UAT and close all P1 issues before promotion.

## Runbook commands
```powershell
# strict production-like build (must have key.properties)
flutter build appbundle \
  --dart-define=APP_ENV=production \
  --dart-define=SUPABASE_URL_PRODUCTION=https://<your-project-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY_PRODUCTION=<YOUR_PRODUCTION_ANON_KEY>

# local verification only (explicit debug-signing override)
flutter build appbundle \
  -PallowDebugSigningForRelease=true \
  --dart-define=APP_ENV=production \
  --dart-define=SUPABASE_URL_PRODUCTION=https://<your-project-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY_PRODUCTION=<YOUR_PRODUCTION_ANON_KEY>
```
