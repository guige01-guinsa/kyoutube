# Operations Smoke Checklist

Last update: 2026-07-26

## Goal
Validate the highest-risk user journeys before release or after any backend/config change.

Use the execution record template for every run: `docs/ops-execution-record-template.md`.

## Account consistency preflight (required before release/config work)
- Confirm the GitHub web account in the active browser profile matches the repository owner context used for this task.
- Confirm the Supabase dashboard account and organization shown at top-right match the intended production project.
- Confirm local Git identity: `git config user.name` and `git config user.email`.
- Confirm GitHub CLI active account: `gh auth status`.
- Confirm remote target: `git remote -v` points to `guige01-guinsa/kyoutube` for fetch and push.
- If any of the above do not match, stop and switch account/profile first; do not continue with deploy, OAuth, or dashboard edits.

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
- Voice guide controls can be toggled without crash (current build uses silent fallback/no-op voice runtime).
- FCM debug panel shows a token on a real device.

## Release monitoring checks
- Open the home screen and confirm the 운영 상태 card shows the current environment.
- Open `/ops` (운영 대시보드) and run "연결 다시 확인". Confirm Supabase check returns `status: ok`.
- Confirm recent errors are empty after a clean launch.
- Copy the ops report from the 운영 상태 card before internal testing.
- If startup fails, capture the displayed phase and error text.

## Local sync beta card checks (when `LOCAL_SYNC_BETA_ENABLED=true`)
- Open "내 요리 노트" and verify the "동기화 베타 상태" card is visible.
- Tap "상태 새로고침" and verify counts and status chip update without crash.
- Tap "프리뷰 실행" and verify success snackbar appears and card shows latest timestamp.
- Trigger an import (overwrite/append) and verify the card refreshes to latest local counts.
- If preview fails, verify the card shows 실패 chip and a recent error message.

## YouTube search MVP checks
- On Home, switch source to `YouTube` and search with a non-empty query.
- Verify loading state appears and then results or an error message is shown without UI freeze.
- Open one result with `YouTube 열기` and verify external launch succeeds.
- Import one result via `내 요리 노트로 가져오기`, edit fields, and save.
- Open imported recipe detail and verify `youtubeUrl` is preserved.
- Open `/ops` dashboard event counters and verify these keys increased during the flow:
	- `search.submitted.youtube`
	- `youtube.search.success` or `youtube.search.failed.{code}`
	- `youtube.result.open.clicked`
	- `youtube.import.clicked`
	- `youtube.import.completed` (or `youtube.import.failed`)
- Copy the ops report and verify `kpi.youtube.*` lines are present for evidence attachment.

## Local real-device precheck (required for APP_ENV=local)
- Confirm Docker Desktop is running.
- Confirm local Supabase status is healthy.
- Confirm USB reverse port forwarding exists: `adb reverse --list` should include `tcp:54321 tcp:54321`.

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
