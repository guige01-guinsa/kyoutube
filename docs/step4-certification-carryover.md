# Step 4 Performance Certification Carry-over

Last update: 2026-07-22

## Why this exists
Step 4 engineering work is complete, but unattended Android sampling on the current device/session is unstable due to foreground focus drift (`NotificationShade`, `Dozing`, `Bouncer`) and Windows host policy limits for profile build.

## Scope split
- Engineering closure: complete
- Certification closure: complete

## Pending certification gate
- Two consecutive runs must satisfy all:
  - `Total frames rendered >= 30`
  - `95th percentile <= 50ms`
  - `Number Slow UI thread <= 3`

## Known blockers
1. Device focus state can stay on `NotificationShade` despite ADB recovery loops.
2. Device may enter `Dozing`/`Bouncer`, invalidating unattended runs.
3. Windows policy blocks profile build (`gen_snapshot.EXE`) on this host.

## Fastest execution path when device is ready
1. Physically ensure app is foreground and lock screen is cleared.
2. Run one of:
   - `powershell -ExecutionPolicy Bypass -File .\tools\step4_manual_assisted_capture.ps1`
  - `powershell -ExecutionPolicy Bypass -File .\\tools\\step4_certify_or_report.ps1`
3. Execute manual flow at each script prompt:
   - home search (`tofu`) -> list scroll down/up -> detail open -> back
4. Collect `RUN1`, `RUN2`, `FINAL_PASS` output and append to work log.

## Latest automated evidence
- Latest report file: `docs/step4-certification-latest-report.md`
- Hunt script for repeated unattended attempts: `tools/step4_certify_hunt.ps1`
- Stay-awake retry evidence:
  - with `svc power stayon true`, first runs became non-zero but still failed gate (`frames=2~4`, `p95=81~150ms`), then reverted to invalid zero-frame samples.

## Final certification pass
- Successful run captured via `tools/step4_certify_or_report.ps1`.
- Results:
  - Run 1: `frames=38`, `p95=38ms`, `slowUi=2`, `pass=true`
  - Run 2: `frames=38`, `p95=38ms`, `slowUi=2`, `pass=true`
  - Final: `FINAL_PASS=True`
- Decision: performance certification gate is closed.

## Completion update procedure
- If `FINAL_PASS=True`:
  - add certification pass note to `docs/work-log-2026-07-22.md`
  - mark certification as complete in this file
- If `FINAL_PASS=False`:
  - keep Step 4 engineering closed
  - open a dedicated performance tuning task under the next phase backlog
