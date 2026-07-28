# Release Security & Stability Audit (2026-07-27)

## Scope
- Platform: Android (Google Play internal track preparation)
- Focus: system stability, security, release readiness
- Environment: local verification on Windows + Android device

## What was validated
1. Quality gates
- `flutter analyze`: PASS
- `flutter test`: PASS (`+16`)

1.1 Release build resilience (post-fix rerun)
- `tools/release/run-internal-track-validation.ps1` rerun after adding `--no-version-check`
- Previous Windows host Flutter git/version-check crash did not recur
- `bundleRelease`: PASS
- Artifact verified: `build/app/outputs/bundle/release/app-release.aab` (`56.3MB`, local timestamp `2026-07-27 08:03:40`)

2. Runtime stability (local)
- Device reverse tunnel (`adb reverse tcp:54321`): verified/recovered
- Local function runtime health checks: added to launcher
- Public recipe search endpoint: healthy (`200`)

3. YouTube error handling resilience
- YouTube API quota exhaustion behavior verified
- `youtube_search` now returns explicit `quota_exceeded` (`429`) instead of generic internal error

4. UI failure-state robustness
- Home error panels adjusted to prevent low-height `RenderFlex overflow`

## Fixes applied during audit
1. `tools/dev/run-local.ps1`
- Added local backend health probes for:
  - `/functions/v1/youtube_search`
  - `/functions/v1/recipe_api?type=public`
- Added auto-recovery flow:
  - restart stale `youtube_search` serve process
  - re-probe health before app launch
- Kept auto `adb reverse` path for Android local runs

2. `supabase/functions/youtube_search/index.ts`
- Map upstream HTTP `429` to `quota_exceeded`
- Handle `Error:`-prefixed messages correctly using `includes(...)`

3. `lib/features/home/presentation/home_page.dart`
- Error-state UI changed to scrollable constrained layout
- Prevents overflow when viewport height is very small (IME/open panels)

## Security findings (priority)

### Critical
1. Local secret file contains real values (must not be committed)
- File: `supabase/functions/.env`
- Observed sensitive values include:
  - `YOUTUBE_DATA_API_KEY`
  - `SUPABASE_AUTH_GOOGLE_SECRET`
- Status: file is ignored by `.gitignore` (good), but values should be rotated if ever exposed.

### High
2. Release signing secret hygiene requires strict CI-only injection
- `android/key.properties` is correctly ignored by `.gitignore`
- Ensure production signing values are only injected via CI secrets for release builds
- Never commit key material or plaintext passwords

### Medium
3. KGP plugin warning in build pipeline
- `file_picker` still applies Kotlin Gradle Plugin pattern that Flutter warns may break in future versions
- Action: track plugin updates and validate migration before final release window

## Release readiness summary
- Stability: 8.5/10
- Security: 8.0/10
- Release automation: 8.0/10
- Overall completion estimate: 85-88%

## Remaining blockers before production rollout
1. YouTube Data API quota
- Current state: `quota_exceeded` (`429`)
- Action: increase quota or rotate to a production key/project with sufficient quota

2. Secret rotation and verification
- Rotate any OAuth/API secrets used during local verification
- Confirm old values are revoked

3. Internal-track strict CI run
- Local verification rerun passes build stage, but production sign-off still requires CI strict mode run (without `-LocalVerification`)
- Confirm signed AAB upload and tester install path

## Recommended next actions
1. Rotate and reissue YouTube/Google OAuth secrets.
2. Run internal-track release guard workflow with production secrets.
3. Capture final smoke evidence (login/search/import/creator CRUD/ops counters).
4. Submit Play Console policy artifacts (Data safety, privacy, terms, store listing assets).
