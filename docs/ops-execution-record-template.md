# Ops Execution Record Template

Last update: 2026-07-20

## Session metadata
- Date:
- Tester:
- Build:
- Device:
- APP_ENV (`local|staging|production`):
- Supabase target URL:

## Precheck
- [ ] Docker Desktop running (local only)
- [ ] `npx supabase@latest status` is healthy (local only)
- [ ] `adb reverse --list` includes `tcp:54321 tcp:54321` (Android local only)
- [ ] App clean launch completed

## Ops dashboard snapshot
- [ ] Open `/ops`
- [ ] Run `연결 다시 확인`
- Backend check status (`ok|failed`):
- `env` value:
- `phase` value:
- `ready` value:
- `recent_error_count` value:
- [ ] Copy standard ops report and paste below

### Pasted standard ops report
```text
(paste from app)
```

KPI evidence check (YouTube MVP):
- [ ] `kpi.youtube.search.success` line present
- [ ] `kpi.youtube.search.failed_total` line present
- [ ] `kpi.youtube.import.completed` line present

## Smoke result summary
- [ ] Login / logout
- [ ] Public recipe list / detail
- [ ] Copy to my recipes
- [ ] Bookmark add / remove
- [ ] Creator create / edit / delete
- [ ] Subscriber note save
- [ ] Subscriber delete undo
- [ ] Voice guide controls without crash (no-op runtime allowed)
- [ ] FCM token visible on real device

## Defects
- P1:
- P2:
- P3:

## Sign-off
- Decision (`pass|blocked|conditional`):
- Notes: