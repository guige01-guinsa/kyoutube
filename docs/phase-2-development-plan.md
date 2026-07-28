# Phase 2 Development Plan

Last update: 2026-07-23

## Goal
- Raise release readiness from current mid-stage to production launch.
- Close largest functional gap from original MVP: subscriber personal recipe flow.
- Complete operations/policy package for Google Play launch.

## Track split
1. Feature & performance track
- Step 1: Subscriber recipe MVP (copy from public recipe, personal notes, list/detail).
- Step 2: AI assistant integration (replace placeholder with real model orchestration and usage logging).
- Step 3: YouTube metadata worker and UX enhancement.
- Step 4: Performance hardening (image/network/cache tuning and startup/profile metrics).

2. Operations & policy track
- Step 1: Release signing and internal track upload verification.
- Step 2: Firebase production config and push validation on real device.
- Step 3: Privacy policy/terms URL publication and Play Data safety completion.
- Step 4: Crash reporting + release monitoring + go-live checklist.

## Execution order (recommended)
1. Implement Subscriber recipe MVP (feature gap closure).
2. Verify signed AAB upload in internal testing.
3. Complete policy package and Play form submission data.
4. Integrate AI real flow and usage guardrails.
5. Add monitoring and launch rehearsal.

## Definition of done per step
- Code merged + analyze/test green.
- Basic user flow tested manually on Android.
- Required docs updated.

## Now executing
- Phase 2 / Operations & policy Step 4

## Next execution package (user-value week)
- Implementation spec: [docs/week-1-user-value-implementation-spec.md](docs/week-1-user-value-implementation-spec.md)
- Focus areas:
	1. Onboarding + AI regenerate reason selector
	2. Quick cook mode + network fallback UX
	3. Account trust guidance + 5-user test

## Progress update
- Completed: Feature Track Step 1 (Subscriber recipe MVP)
- In progress: Feature Track Step 2 (AI assistant integration)
	- Week-1 uplift implemented: structured response contract (`status/degraded/errorCode`), hybrid provider fallback path, user feedback capture path.
- Completed: Feature Track Step 4 (Performance hardening, engineering + certification complete)
- Completed: Operations & policy Step 1 (Internal track release validation)
- Completed: Operations & policy Step 2 (Firebase production config + real-device init-path validation)
- Completed: Operations & policy Step 3 (policy URL package + Play Data safety submission docs)
- In progress: Operations & policy Step 4 (Crash reporting + release monitoring + go-live checklist)
- Stability closeout check completed on 2026-07-23: no-feature-expansion validation pass (`flutter analyze lib test`, `flutter test`).
- Blocker observed on latest strict release build: Windows policy blocked Flutter `gen_snapshot.EXE`; internal-track AAB upload must wait for allowlist or CI-host build.
 - Additional blocker: same Windows policy currently blocks profile-mode build (`assembleProfile`), so debug-mode manual evidence is used temporarily until policy allowlist is applied.

## Next session execution plan (stability-first, 2026-07-24)
1. Real-device regression recheck (first 20-30 min)
- Validate non-repro for:
	- `Cannot use ref after widget disposed`
	- `RenderFlex overflow on operations status card`
- Flow: home load -> recipe detail open/close repeat -> quick cook enter/exit repeat -> ops card narrow-width check.

2. Release-blocker branch decision
- If Windows host policy is still blocking `gen_snapshot.EXE`, switch release packaging path to approved CI/allowlisted machine.
- Keep feature freeze active until AAB/internal-track evidence is captured.

3. Operations evidence refresh
- Run one smoke pass from `docs/ops-smoke-checklist.md`.
- Record result using `docs/ops-execution-record-template.md`.
- Update `docs/google-play-release-readiness.md` only with newly verified facts.

4. Exit criteria for next session
- Analyze/test remain green.
- No recurrence of the two real-device errors.
- Clear owner action list for internal-track upload.

### Step 2/3 closure note (2026-07-22)
- Execution evidence doc: [docs/ops-policy-step2-3-execution-2026-07-22.md](docs/ops-policy-step2-3-execution-2026-07-22.md)
- Step 2 app/device path is complete (Firebase config + FCM service init path on real device).
- Step 3 submission documents are complete with canonical public URL paths.
- Remaining items are owner-console actions (Play/Firebase submission clicks), treated as release operations rather than feature-engineering blockers.

### Step 4 closure decision (2026-07-22)
- Step 4 is closed as complete at engineering scope because the Step 4 definition-of-done items are satisfied:
  - implementation merged and `flutter analyze lib/` clean
  - startup timing instrumentation is visible in app/report
  - search refetch suppression and list/thumbnail tuning are applied
  - before/after notes are documented in work log
- The stricter two-consecutive-run gate (`frames>=30`, `p95<=50ms`, `slow-ui<=3`) has now been satisfied and the certification track is closed.
- Certification pass snapshot: `RUN1 frames=38 p95=38ms slow-ui=2`, `RUN2 frames=38 p95=38ms slow-ui=2`, `FINAL_PASS=True`.
- Certification history doc: [docs/step4-certification-carryover.md](docs/step4-certification-carryover.md)

## Step 4 scope: Performance hardening
1. Startup metrics
- Measure cold start path from app launch to `OpsMonitorService.markReady()`.
- Record phase timings for Firebase init, FCM init, and Supabase init.
- Set an Android real-device baseline and target threshold.

2. Image and list rendering
- Replace uncapped recipe thumbnail loading with size-aware image loading and error-safe placeholders.
- Verify long recipe list scrolling on Android without noticeable jank.
- Avoid unnecessary rebuilds on search input and top-level home widgets.

3. Network and data access
- Reduce repeated fetches triggered by every search keystroke.
- Add lightweight request timing for key app paths:
	- public recipe list
	- kitchen summary
	- recipe detail
- Define refresh and cache invalidation behavior explicitly.

4. Validation and regression guard
- Capture at least one profile-mode measurement on a real Android device.
- Re-run core manual flow after optimizations:
	- app launch
	- home search
	- recipe detail open
	- Google login
- Update work log with before/after observations.

## Step 4 definition of done
- Code merged and `flutter analyze lib/` passes.
- Startup timing is visible in app or logs for the main bootstrap phases.
- Home recipe list avoids obvious re-fetch storms during typing.
- Recipe thumbnails and list scrolling are tuned for stable Android rendering.
- A short before/after performance note is added to the work log.
