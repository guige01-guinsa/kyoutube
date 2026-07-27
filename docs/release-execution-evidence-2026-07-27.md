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
  - `status=completed`
  - `conclusion=cancelled`

### 1.4 External blocker conclusion (historical)
- Three consecutive strict reruns after remediation stalled at `Setup Flutter` on GitHub-hosted Windows runners.
- This blocker was mitigated by workflow stabilization changes plus ubuntu-runner validation (section 1.6).

### 1.5 Workflow stabilization changes prepared
- File updated: `.github/workflows/internal-track-release-guard.yml`
- Changes:
  - Added workflow dispatch input `runnerLabel` (`windows-latest` or `ubuntu-latest`) for runner experiment.
  - Added workflow dispatch input `flutterVersion` with pinned default `3.44.8`.
  - `Setup Flutter` now uses pinned `flutter-version` and `timeout-minutes: 15` to fail fast on setup stalls.
  - Windows-only Gradle tuning step is gated with `if: runner.os == 'Windows'`.
- Note: these changes are local workspace edits and require branch push + workflow run to validate in GitHub-hosted CI.

### 1.6 Workflow stabilization validation run
- Branch: `fix/public-recipe-sync-worker-guard` (commit includes cross-platform `pwsh` invocation)
- Dispatch inputs used:
  - `runnerLabel=ubuntu-latest`
  - `flutterVersion=3.44.8`
  - `localVerification=false`
  - `skipPublicRecipeSyncSmoke=false`
- Validation run URL: `https://github.com/guige01-guinsa/kyoutube/actions/runs/30261625170`
- Final status: `completed / success` (updated_at `2026-07-27T11:28:03Z`)
- Key step outcomes:
  - `Setup Flutter`: success
  - `Run release guard validation script`: success
  - `Upload AAB artifact`: success

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

### 3.4 Execution status in this session
- Executed automated capture with `tools/release/capture-internal-track-smoke-evidence.ps1` after device connection was established.
- Captured artifacts:
  - `docs/evidence/internal-track-2026-07-27/kyoutube_install.png`
  - `docs/evidence/internal-track-2026-07-27/kyoutube_ops.png`
  - `docs/evidence/internal-track-2026-07-27/kyoutube_import.png`
  - `docs/evidence/internal-track-2026-07-27/kyoutube_ui.xml`
- Device/version evidence written to `docs/ops-execution-record-2026-07-27-internal-track.md`.
- Current gate status: install source check is still `Installed from Play internal track: NO`, so final release closure remains pending Play internal-track installation proof and reviewer sign-off.

### 3.5 Final automation attempts and blocker evidence
- Automation attempted a forced reinstall path on connected device:
  1) `adb uninstall com.kyoutube.app`
  2) open `market://details?id=com.kyoutube.app`
  3) collect Play UI dump/screenshot evidence
- Result after uninstall: Play UI text included `항목을 찾을 수 없습니다.` and `다시 시도` (no install CTA detected).
- Additional probe to canonical URL `https://play.google.com/apps/testing/com.kyoutube.app` opened Samsung Internet web context, not Play app install flow.
- To avoid leaving the test device empty, app was restored from local artifact `.artifacts/app-release-apks/universal.apk`.
- Final installer state remains `installer=null`; therefore Play internal-track install proof (`com.android.vending`) is still not met.

### 3.6 Post-blocker retry (tokenless URL only)
- Re-attempted after explicit operator request:
  - Opened `https://play.google.com/apps/testing/com.kyoutube.app` again and captured `play_testing_retry.xml`.
  - Forced Play handling with `com.android.vending/com.google.android.finsky.activities.MainActivity` and captured `play_testing_vending_main.xml` + screenshot.
- Outcome: UI dumps showed only address-bar level text (`play.google.com`) with no tester enrollment/install CTA.
- Conclusion unchanged: without a tokenized invite URL (or already-enrolled tester context), installer source cannot transition to `com.android.vending` in this environment.

## 4) Local quality/security re-check (post-remediation)
- `flutter analyze`: PASS (`No issues found`)
- `flutter test`: PASS (`+16`)
- Android manifest quick audit:
  - `MainActivity android:exported=true` only for launcher activity (expected).
  - No tracked plaintext OAuth/YouTube secrets found under tracked `supabase/config.toml`; sensitive values remain in local ignored env file.
