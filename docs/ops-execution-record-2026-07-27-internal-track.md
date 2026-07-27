# Ops Execution Record - Internal Track (2026-07-27)

## Build / Distribution
- Source runbook: `docs/internal-track-release-checklist.md`
- CI strict run URL: `https://github.com/guige01-guinsa/kyoutube/actions/runs/30261625170`
- Internal testing release URL: `PENDING_EXTERNAL_PLAY_CONSOLE`
- Tester account: `PENDING_EXTERNAL_TESTER_ASSIGNMENT`
- Device model / OS: SM-G977N / Android 12

## Install evidence
- Installed from Play internal track: NO
- Install timestamp (KST): 2026-07-27 23:38:21 +09:00
- `versionName`: versionName=0.1.0
- `versionCode`: versionCode=1 minSdk=24 targetSdk=36

Capture helper command:
```powershell
powershell -ExecutionPolicy Bypass -File tools/release/capture-internal-track-smoke-evidence.ps1
```

## Smoke checklist
- Login: `PENDING_EXTERNAL`
- Public recipe list/detail: `PENDING_EXTERNAL`
- YouTube search: `PENDING_EXTERNAL`
- YouTube import/save: `PENDING_EXTERNAL`
- Creator create/edit/delete: `PENDING_EXTERNAL`
- Shopping from recipe: `PENDING_EXTERNAL`
- Ops counters increase verified: `PENDING_EXTERNAL`

## Evidence attachments
- Screenshot 1 (Play install success): docs\evidence\internal-track-2026-07-27\kyoutube_install.png
- Screenshot 2 (ops dashboard counters): docs\evidence\internal-track-2026-07-27\kyoutube_ops.png
- Screenshot 3 (YouTube import result): docs\evidence\internal-track-2026-07-27\kyoutube_import.png

## Notes / defects
- CI strict run #30259337635 failed due to worker-secret mismatch (resolved by URL secret alignment).
- CI strict rerun #30260274963 stayed in long-running in-progress state and cancellation was requested.
- CI strict rerun #30260782913 stayed in long-running in-progress state and cancellation was requested.
- CI strict rerun #30261074832 stayed in long-running in-progress state and cancellation was requested.
- CI strict rerun #30261177761 completed with conclusion `cancelled` after repeated setup stall.
- CI strict rerun #30261573553 was canceled to validate latest workflow patch revision.
- CI strict rerun #30261625170 (ubuntu-latest + flutterVersion=3.44.8 + pwsh invocation) completed with conclusion `success`.
- CI blocker status: resolved for the stabilized ubuntu workflow path.
- Local quality gates after remediation: `flutter analyze` PASS, `flutter test` PASS (+16).
- Worker secret rotation rollout run #30259412692 completed successfully.
- Connected-device evidence capture executed successfully on `SM-G977N` via `tools/release/capture-internal-track-smoke-evidence.ps1`.
- Install source check result was `Installed from Play internal track: NO` (installer package not resolved to `com.android.vending`), so Play internal install proof remains pending.
- Re-check after opening Play detail page and rerunning capture at `2026-07-27 20:52:39 +09:00` still shows `installer=null`.
- Forced reinstall attempt sequence executed: uninstall app -> open `market://details?id=com.kyoutube.app` -> Play UI dump/screenshot capture.
- After uninstall, Play UI showed no install CTA and text evidence included `??™©??Ï∞æÏùÑ ???ÜÏäµ?àÎã§.` / `?§Ïãú ?úÎèÑ`.
- Canonical web URL probe (`https://play.google.com/apps/testing/com.kyoutube.app`) opened Samsung Internet (not Play app), requiring external tester enrollment/link context.
- Device app was restored from local artifact (`.artifacts/app-release-apks/universal.apk`) to avoid leaving tester device empty; installer remains `null`.
- Additional retry executed after permission confirmation:
	- `https://play.google.com/apps/testing/com.kyoutube.app` reopened and captured (`play_testing_retry.xml`)
	- Forced Play route via `com.android.vending/com.google.android.finsky.activities.MainActivity` captured (`play_testing_vending_main.xml`)
	- Both dumps only exposed address-bar text (`play.google.com`) and no install/enroll CTA.
- Device intent history confirms only tokenless URL was available (`.../apps/testing/com.kyoutube.app`), with no tokenized invite URL present in local context.

## Sign-off
- Operator: `GitHub Copilot (automated evidence prep)`
- Reviewer: `PENDING_EXTERNAL_REVIEWER`
- Decision: `HOLD_PENDING_EXTERNAL_INTERNAL_TEST`
- Decision rationale: strict CI validation is now passing and device evidence capture succeeded, but closure remains blocked until Play internal-track installation proof and tester smoke checklist are completed.

## Record close status
- This record is finalized for automation scope.
- External close conditions remain: Play internal install evidence (`Installed from Play internal track: YES`) + tester smoke checklist + reviewer sign-off.


## Installer evidence
- installerPackageName: <not-found>
- pm list packages -i result: installer=null
- resolve-activity: priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=false
com.kyoutube.app/.MainActivity
- UI dump: docs\evidence\internal-track-2026-07-27\kyoutube_ui.xml
- Play uninstall state screenshot: docs\evidence\internal-track-2026-07-27\play_after_uninstall.png
- Play uninstall state UI dump: docs\evidence\internal-track-2026-07-27\play_after_uninstall.xml
- Canonical testing URL screenshot: docs\evidence\internal-track-2026-07-27\play_testing_url.png
- Canonical testing URL UI dump: docs\evidence\internal-track-2026-07-27\play_testing_url.xml
- Retry testing URL UI dump: docs\evidence\internal-track-2026-07-27\play_testing_retry.xml
- Forced Play main-activity screenshot: docs\evidence\internal-track-2026-07-27\play_testing_vending_main.png
- Forced Play main-activity UI dump: docs\evidence\internal-track-2026-07-27\play_testing_vending_main.xml
