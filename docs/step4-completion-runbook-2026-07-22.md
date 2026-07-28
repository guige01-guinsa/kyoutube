# Step 4 Completion Runbook (2026-07-22)

## Purpose
Stabilize final Step 4 sign-off with two consecutive valid manual runs on the same Android device.

## Preconditions
- Device connected: `adb devices`
- App running in current local config (debug run is acceptable when profile mode is blocked by policy)
- Supabase local tunnel active: `adb reverse tcp:54321 tcp:54321`

## Validity gate per run
- `Total frames rendered >= 30`

## Target band per run
- `95th percentile <= 50ms`
- `Number Slow UI thread <= 3`

## Manual flow (exact)
1. Launch app to home.
2. Search `tofu` in home search input and submit.
3. Scroll list down and up at normal speed.
4. Open one recipe detail.
5. Return to home.

## Capture command (run after each manual flow)
```powershell
adb shell dumpsys gfxinfo com.kyoutube.app | Select-String "Total frames rendered|Janky frames|90th percentile|95th percentile|99th percentile|Number Slow UI thread|Number Slow bitmap uploads|Number Slow issue draw commands|Number Frame deadline missed"
```

## Assisted capture script (recommended)
Use the helper script to drive reset and collection while the operator only performs the device flow:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\step4_manual_assisted_capture.ps1
```

Script behavior:
- prepares awake/unlocked state
- resets `gfxinfo` before each run
- waits for Enter after manual flow
- prints `RUN1`, `RUN2`, and `FINAL_PASS`

## Reset command (before each manual flow)
```powershell
adb shell dumpsys gfxinfo com.kyoutube.app reset
```

## Completion decision
- Mark Step 4 as `Complete` only if BOTH Run 1 and Run 2 satisfy:
  - validity gate (`frames >= 30`)
  - target band (`p95 <= 50ms`, `slow-ui <= 3`)

## Logging requirements
- Append raw metrics for Run 1 and Run 2 to:
  - `docs/work-log-2026-07-22.md`
- Update status line in:
  - `docs/phase-2-development-plan.md`
  - set Feature Track Step 4 from in-progress to complete with date and measured values.

## Known blocker
- Profile mode collection is currently blocked on this Windows host by policy denying `gen_snapshot.EXE` execution.
- If policy is removed, repeat the same two-run process in profile mode and replace debug-based evidence.
