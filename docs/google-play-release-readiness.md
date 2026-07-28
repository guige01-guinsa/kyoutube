# Google Play Release Readiness

Last update: 2026-07-28

## Current estimate
- Overall readiness: 70%

## Scoring model
- Product stability (30%): 22/30
- Release engineering (25%): 20/25
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
- **Signed release AAB built successfully (~56 MB)** – `build/app/outputs/bundle/release/app-release.aab`.
- **Play Console upload guide documented** – `docs/play-console-upload-guide.md`.

## Blocking gaps before production rollout
- ⬜ **Upload AAB to Play Console internal testing and confirm tester install** ← next action
- Verify FCM behavior on real device using production Firebase project.
- Prepare privacy policy URL and app terms URL from the drafts in `docs/privacy-policy.md` and `docs/terms-of-service.md`.
- Complete Google Play Data safety form based on `docs/google-play-data-safety.md` and the actual release build.
- Create Play Store assets: icon, feature graphic, screenshots, short/full description.

## Recommended execution plan
1. **Play Console upload (now)** – see `docs/play-console-upload-guide.md`
   - Upload `build/app/outputs/bundle/release/app-release.aab` to internal testing track.
   - Add internal testers via opt-in link.
   - Run smoke checklist on a real Android device (`docs/ops-smoke-checklist.md`).

2. Firebase production validation (next)
   - Verify FCM token and notification delivery on a real Android device.
   - Add `GoogleService-Info.plist` if iOS is in scope.

3. Policy package (after FCM)
   - Publish the privacy policy page and terms page using the draft docs.
   - Fill Data safety and content rating questionnaires.
   - Verify permission declarations match app behavior.

4. Store listing assets
   - App icon (512×512 px), feature graphic (1024×500 px).
   - At least two phone screenshots (320–3840 px on the longest side).
   - Short description (80 chars) and full description (4000 chars).

5. Production hardening (final gate)
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
