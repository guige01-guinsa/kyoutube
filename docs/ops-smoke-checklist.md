# Operations Smoke Checklist

Last update: 2026-07-19

## Goal
Validate the highest-risk user journeys before release or after any backend/config change.

## Must pass
- App launches without startup error on Android and iOS targets.
- Login and logout work.
- Public recipe list loads.
- Public recipe detail loads.
- "내 레시피로 복사" works for a logged-in user.
- Bookmark add/remove works.
- Creator recipe create/update/delete works.
- Subscriber note save works.
- Subscriber delete undo works.
- Voice guide start/next/previous/stop works.
- FCM debug panel shows a token on a real device.

## Release monitoring checks
- Open the home screen and confirm the 운영 상태 card shows the current environment.
- Confirm recent errors are empty after a clean launch.
- Copy the ops report from the 운영 상태 card before internal testing.
- If startup fails, capture the displayed phase and error text.

## Failure triage
- P1: app cannot launch, auth is broken, copy/delete fails broadly, or publish/CRUD is blocked.
- P2: a feature works but has a serious recovery issue, incorrect state, or repeated user confusion.
- P3: cosmetic issues, wording, or non-blocking layout defects.

## Recommended run order
1. Clean launch check.
2. Login and recipe browse.
3. CRUD and bookmark check.
4. Voice guide and notifications.
5. Capture ops report and sign off.
