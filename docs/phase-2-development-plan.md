# Phase 2 Development Plan

Last update: 2026-07-19

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
- Phase 2 / Operations & Policy Track / Step 1: Play Console internal track upload

## Progress update
- Completed: Feature Track Step 1 (Subscriber recipe MVP)
- Completed: Operations & policy Step 1 (Internal track release validation – signed AAB built, ~56 MB)
- In progress: Operations & policy Step 1 upload (AAB ready, pending Play Console upload)
- Pending: Operations & policy Step 2/3 (Firebase production config, policy package, and Play Data safety completion)
- Next action: upload `build/app/outputs/bundle/release/app-release.aab` → see `docs/play-console-upload-guide.md`
