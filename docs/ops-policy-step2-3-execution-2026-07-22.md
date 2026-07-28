# Operations & Policy Step 2/3 Execution Record

Last update: 2026-07-22

## Scope
- Phase 2 / Operations & policy / Step 2
  - Firebase production config and push validation on real device
- Phase 2 / Operations & policy / Step 3
  - Privacy policy / terms URL publication path and Play Data safety package completion

## Step 2 execution evidence
- Android Firebase config file verified:
  - path: `android/app/google-services.json`
  - project_id: `korea-01`
  - package_name: `com.kyoutube.app`
- Real device connectivity verified:
  - `adb devices`: `R3CM501SB2D device`
  - `adb reverse --list`: includes `tcp:54321 tcp:54321`
- Runtime startup metrics confirm Firebase/FCM bootstrap path executes:
  - `ops.startup_phase_durations_ms` includes `Firebase 초기화`, `FCM 초기화`, `Supabase 초기화`
  - latest `ops.startup_total_ms`: `1611`
- FCM service runtime signal observed:
  - `FLTFireMsgService: FlutterFirebaseMessagingBackgroundService started!`

### Step 2 decision
- App-side Firebase/FCM integration and real-device initialization path: complete.
- Remaining external action (non-code): send/receive production Firebase Console test push in release account context.

## Step 3 execution evidence
- Policy documents finalized as publication candidates:
  - `docs/privacy-policy.md`
  - `docs/terms-of-service.md`
- Canonical public URL path defined for store submission:
  - Privacy policy URL: `https://github.com/guige01-guinsa/kyoutube/blob/main/docs/privacy-policy.md`
  - Terms URL: `https://github.com/guige01-guinsa/kyoutube/blob/main/docs/terms-of-service.md`
- Play Data safety package finalized at document level:
  - `docs/google-play-data-safety.md`
  - Collected categories, purposes, sharing, retention, and declaration template fixed.

### Step 3 decision
- Policy/Data safety package: complete at submission-document level.
- Remaining external action (non-code): owner submits final answers in Play Console.

## Residual blockers (outside Step 2/3 engineering scope)
1. Windows policy blocks Flutter profile/release AOT binary (`gen_snapshot.EXE`) on this host.
2. Play Console / Firebase Console owner actions are still required for final publication and push send verification.

## Final status
- Step 2: complete (engineering and device initialization path), with one console-side validation action pending.
- Step 3: complete (documentation and URL publication path), with one console-side submission action pending.
