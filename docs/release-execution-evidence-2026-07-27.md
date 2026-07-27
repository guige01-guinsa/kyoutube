# Release Execution Evidence (2026-07-27)

## 1) CI strict validation (without LocalVerification)

### 1.1 Local strict-equivalent dry run result
- Command: `tools/release/run-internal-track-validation.ps1` without `-LocalVerification`
- Result: `bundleRelease` succeeded and AAB was built.
- Result: smoke check failed at step 5/6 because production URL value resolved to placeholder domain (`your-production-project-ref.supabase.co`).
- Exit marker: `STRICT_VALIDATION_EXIT:1`
- Interpretation: build path is healthy; strict smoke requires real production Supabase URL/keys.

### 1.2 CI workflow run (authoritative)
- Workflow: `.github/workflows/internal-track-release-guard.yml`
- Dispatch inputs:
  - `localVerification=false`
  - `skipPublicRecipeSyncSmoke=false`
  - `publicRecipeSyncSmokeSize=1`
- Run URL: `https://github.com/guige01-guinsa/kyoutube/actions/runs/30259337635`
- Final status: `failure`
- Failure step: `Run release guard validation script`
- Root cause from CI log:
  - `public_recipe_sync` probe with valid `x-worker-secret` returned `401 Invalid worker secret`
  - Build itself succeeded (`app-release.aab` generated), but strict smoke failed on auth check mismatch.

### 1.3 CI rerun after remediation
- Remediation applied:
  - Updated repository secret `PUBLIC_RECIPE_SYNC_FUNCTION_URL` to align with deployed worker-secret target:
    - `https://dfczeudklykypysiseck.supabase.co/functions/v1/public_recipe_sync`
- Rerun #1 URL: `https://github.com/guige01-guinsa/kyoutube/actions/runs/30260274963`
- Rerun #1 tracking note: long-running `in_progress` state; cancellation requested to unblock final verification.
- Rerun #2 URL (active strict run): `https://github.com/guige01-guinsa/kyoutube/actions/runs/30260782913`
- Rerun #2 tracking note: long-running `in_progress` state; cancellation requested to unblock final verification.
- Rerun #3 URL (active strict run): `https://github.com/guige01-guinsa/kyoutube/actions/runs/30261074832`
- Rerun #3 tracking note: long-running `in_progress` state; cancellation requested to unblock final verification.
- Rerun #4 URL: `https://github.com/guige01-guinsa/kyoutube/actions/runs/30261177761`
- Rerun #4 final result: `completed / cancelled` (updated_at `2026-07-27T11:17:33Z`)
- API snapshot evidence:
  - `status=in_progress`
  - `run_started_at=2026-07-27T11:08:27Z`
- Note: this is an external GitHub Actions runtime wait condition; final pass/fail can only be confirmed when the run exits from `in_progress`.

### 1.4 External blocker conclusion (current)
- Three consecutive strict reruns after remediation are stalling at `Setup Flutter` on GitHub-hosted Windows runners.
- Because the workflow run does not reach step 9 (`Run release guard validation script`), final strict pass/fail is currently blocked by external CI runtime behavior rather than repository code changes.

### 1.5 Workflow stabilization changes prepared
- File updated: `.github/workflows/internal-track-release-guard.yml`
- Changes:
  - Added workflow dispatch input `runnerLabel` (`windows-latest` or `ubuntu-latest`) for runner experiment.
  - Added workflow dispatch input `flutterVersion` with pinned default `3.44.8`.
  - `Setup Flutter` now uses pinned `flutter-version` and `timeout-minutes: 15` to fail fast on setup stalls.
  - Windows-only Gradle tuning step is gated with `if: runner.os == 'Windows'`.
- Note: these changes are local workspace edits and require branch push + workflow run to validate in GitHub-hosted CI.

## 2) YouTube/Google OAuth key rotation + old key revoke evidence

### 2.1 Completed automatically in this session
- Rotated GitHub Actions secret: `PUBLIC_RECIPE_SYNC_WORKER_SECRET`
- Non-sensitive proof: `ROTATED_PUBLIC_RECIPE_SYNC_WORKER_SECRET_SHA256_PREFIX=E4B3BAEB066760B4`
- Rollout workflow: `.github/workflows/deploy-public-recipe-sync.yml`
- Run URL: `https://github.com/guige01-guinsa/kyoutube/actions/runs/30259412692`
- Result: `success` (Configure worker secret + Deploy function both completed)

### 2.1.1 Worker secret rollout consistency note
- Initial strict CI run failed because smoke target URL and rotated secret target were inconsistent.
- After URL secret alignment, strict CI rerun was started (section 1.3).

### 2.2 Requires cloud-console owner action (cannot be safely auto-rotated from repo)
- `YOUTUBE_DATA_API_KEY`: rotate in Google Cloud Console (API key regenerate or create new key + restriction policy), then revoke old key.
- `SUPABASE_AUTH_GOOGLE_SECRET` (OAuth client secret): rotate in Google OAuth Client console, update Supabase Auth provider config, then revoke old secret.

### 2.3 Required revoke evidence to attach
- Google Cloud API key page screenshot or audit log showing old key disabled/deleted.
- OAuth client secret rotation log/screenshot showing new secret issuance and old secret invalidation.
- Post-rotation smoke output proving:
  - YouTube search no longer returns old-key failures.
  - Google login completes successfully.

## 3) Play internal tester install + final smoke evidence

### 3.1 Automation boundary
- Internal tester install itself must be performed by Play Console owner/tester account in Google Play (external system, no local API credentials in this workspace).

### 3.2 Ready-to-run capture checklist (execute after Play processing completes)
1. Install app from Internal testing link on tester device.
2. Record installed version on device:
   - `adb shell dumpsys package com.kyoutube.app | findstr versionName`
   - `adb shell dumpsys package com.kyoutube.app | findstr versionCode`
3. Execute smoke flow:
   - Login
   - Public recipe list/detail
   - YouTube search/import/save
   - Creator recipe create/edit/delete
   - Shopping creation from recipe
4. Capture `/ops` counters screenshot and include event deltas.
5. Save evidence into `docs/ops-execution-record-2026-07-27-internal-track.md`.

### 3.3 Final gate
- Release can be marked complete only after sections 2.3 and 3.2 artifacts are attached.

## 4) Local quality/security re-check (post-remediation)
- `flutter analyze`: PASS (`No issues found`)
- `flutter test`: PASS (`+16`)
- Android manifest quick audit:
  - `MainActivity android:exported=true` only for launcher activity (expected).
  - No tracked plaintext OAuth/YouTube secrets found under tracked `supabase/config.toml`; sensitive values remain in local ignored env file.
