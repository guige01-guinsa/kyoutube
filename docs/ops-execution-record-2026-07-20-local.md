# Ops Execution Record - 2026-07-20 (local)

## Session metadata
- Date: 2026-07-20
- Tester: Copilot assisted run
- Build: Flutter debug run (`flutter run`) on branch `dev/kitchen-v1`
- Device: Not connected at verification time (`adb` returned no devices)
- APP_ENV (`local|staging|production`): `local`
- Supabase target URL: `http://127.0.0.1:54321`

## Precheck
- [x] Docker/Supabase local stack reachable (`npx supabase@latest status`)
- [x] Supabase API URL confirmed (`http://127.0.0.1:54321`)
- [ ] `adb reverse --list` includes `tcp:54321 tcp:54321` (blocked: no connected device/emulator)
- [x] Ops-related code static check passed (`flutter analyze` on ops files)

## Ops dashboard snapshot
- [ ] Open `/ops` in-app and run `연결 다시 확인` (manual device step pending)
- Backend check status: `ok` (terminal substitute via REST and `recipe_api`)
- `env` value: pending in-app capture
- `phase` value: pending in-app capture
- `ready` value: pending in-app capture
- `recent_error_count` value: pending in-app capture
- [ ] Copy standard ops report from app (pending)

### Terminal substitute evidence
- REST probe (`/rest/v1/recipes_public?select=id&limit=1`): success, row returned
- API probe (`/functions/v1/recipe_api?type=public&limit=1&offset=0`): success, `status=ok`

## Smoke result summary
- [ ] Login / logout (pending manual run)
- [ ] Public recipe list / detail (pending manual run)
- [ ] Copy to my recipes (pending manual run)
- [ ] Bookmark add / remove (pending manual run)
- [ ] Creator create / edit / delete (pending manual run)
- [ ] Subscriber note save (pending manual run)
- [ ] Subscriber delete undo (pending manual run)
- [ ] Voice guide controls without crash (pending manual run)
- [ ] FCM token visible on real device (blocked until device connected)

## Defects
- P1: none observed in terminal probes
- P2: none observed in terminal probes
- P3: none observed in terminal probes

## Sign-off
- Decision (`pass|blocked|conditional`): `conditional`
- Notes: Backend endpoints and ops code checks are healthy, but device-dependent checks are pending because no Android device/emulator is currently connected.
