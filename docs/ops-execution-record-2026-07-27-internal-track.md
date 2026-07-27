# Ops Execution Record - Internal Track (2026-07-27)

## Build / Distribution
- Source runbook: `docs/internal-track-release-checklist.md`
- CI strict run URL: `https://github.com/guige01-guinsa/kyoutube/actions/runs/30261625170`
- Internal testing release URL: `PENDING_EXTERNAL_PLAY_CONSOLE`
- Tester account: `PENDING_EXTERNAL_TESTER_ASSIGNMENT`
- Device model / OS: SM-G977N / Android 12

## Install evidence
- Installed from Play internal track: NO
- Install timestamp (KST): 2026-07-27 20:48:27 +09:00
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
- resolve-activity: priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=false
com.kyoutube.app/.MainActivity
- UI dump: docs\evidence\internal-track-2026-07-27\kyoutube_ui.xml
