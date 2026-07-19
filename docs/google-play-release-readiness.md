# Google Play Release Readiness

Last update: 2026-07-19

## Current estimate
- Overall readiness: 66%

## Scoring model
- Product stability (30%): 22/30
- Release engineering (25%): 15/25
- Store policy and legal (20%): 10/20
- Security and operations (15%): 9/15
- QA and observability (10%): 9/10

## Done
- Flutter analyze and tests are green.
- Supabase environment separation exists (`local`, `staging`, `production`).
- Android release signing now fails by default when release keystore is not configured.
- Android Firebase config file `android/app/google-services.json` is now present in workspace.
- Voice guidance state and persistence flows are implemented.
- Startup bootstrap now surfaces environment and initialization failures to users.
- Home screen includes an 운영 상태 card for recent errors and report export.
- Smoke and staging UAT checklists are documented in `docs/ops-smoke-checklist.md` and `docs/staging-uat-checklist.md`.
- Privacy, terms, and Data safety drafts are documented in `docs/privacy-policy.md`, `docs/terms-of-service.md`, and `docs/google-play-data-safety.md`.

## Blocking gaps before production rollout
- Configure real upload keystore and validate signed AAB in Play Console internal testing.
- Resolve Windows application control block for Flutter release AOT (`gen_snapshot.EXE`), or run release build on an approved CI/host.
- Add `GoogleService-Info.plist` for iOS Firebase project if iOS release path remains in scope.
- Verify FCM behavior on real device using production Firebase project.
- Prepare privacy policy URL and app terms URL from the drafts in `docs/privacy-policy.md` and `docs/terms-of-service.md`.
- Complete Google Play Data safety form based on `docs/google-play-data-safety.md` and the actual release build.
- Create Play Store assets: icon, feature graphic, screenshots, short/full description.

## Recommended execution plan
1. Release gate validation (today)
- Create `android/key.properties` with real keystore values.
- Build AAB without debug-signing override.
- Upload to internal testing track.
- Verify the script `tools/release/run-internal-track-validation.ps1` produces `build/app/outputs/bundle/release/app-release.aab`.

2. Policy package (next)
- Publish the privacy policy page and terms page using the draft docs.
- Fill Data safety and content rating questionnaires.
- Verify permission declarations match app behavior.

3. Production hardening (next)
- Review the 운영 상태 card and recent error log after each internal build.
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
