# Internal Track Release Checklist

Last update: 2026-07-26

## Scope
- Phase 2 / Operations & Policy Track / Step 1
- Goal: produce a signed AAB and upload to Google Play internal testing

## Current status (workspace scan)
- `android/key.properties`: present
- upload keystore file: verify against `storeFile` path in `android/key.properties`
- `android/app/google-services.json`: present
- `ios/Runner/GoogleService-Info.plist`: missing
- Strict release build result: blocked by Windows application control policy (`gen_snapshot.exe` execution blocked during release AOT)

## Step-by-step
1. Create release signing config
- Copy `android/key.properties.example` to `android/key.properties`.
- Fill all values: `storeFile`, `storePassword`, `keyAlias`, `keyPassword`.
- Place the keystore file at the `storeFile` location.

2. Add Firebase Android config
- Download `google-services.json` from Firebase Console for package `com.kyoutube.kyoutube`.
- Place it at `android/app/google-services.json`.

3. Add Firebase iOS config
- Download `GoogleService-Info.plist` from Firebase Console for the iOS app.
- Place it at `ios/Runner/GoogleService-Info.plist`.
- Open Runner in Xcode and ensure the plist is added to the Runner target resources.

4. Build production-like signed AAB
```powershell
powershell -ExecutionPolicy Bypass -File tools/release/run-internal-track-validation.ps1 \
  -SupabaseUrlProduction "https://<your-project-ref>.supabase.co" \
  -SupabaseAnonKeyProduction "<YOUR_PRODUCTION_ANON_KEY>" \
  -PublicRecipeSyncFunctionUrl "https://<your-project-ref>.supabase.co/functions/v1/public_recipe_sync" \
  -PublicRecipeSyncWorkerSecret "<PUBLIC_RECIPE_SYNC_WORKER_SECRET>"
```

Guardrails:
- `-SupabaseUrlProduction` and `-SupabaseAnonKeyProduction` are required. Missing values now fail fast.
- `-LocalVerification` is blocked in CI environments and should only be used on local machines.
- `public_recipe_sync` smoke check runs by default and validates `x-worker-secret` behavior.
- Use `-SkipPublicRecipeSyncSmoke` only for emergency debugging runs.

If build fails with `gen_snapshot.EXE` blocked on Windows:
- Ask IT/security to allowlist: `C:\Users\ADMIN\tools\flutter\bin\cache\artifacts\engine\android-arm-release\windows-x64\gen_snapshot.EXE`
- Re-run step 4 after policy update.
- Alternative: run the same command on a trusted CI agent or another workstation without the block policy.

5. Upload to Play Console Internal testing
- Upload `build/app/outputs/bundle/release/app-release.aab`.
- Confirm track processing succeeds and tester install is available.

6. Smoke test on internal build
- Login
- Public recipe browse/detail
- Home YouTube source search shows loading and result/error states correctly
- `YouTube 열기` launches external app/browser successfully
- YouTube import flow (edit sheet -> save) creates a recipe with `youtubeUrl`
- Copy to my recipe
- My recipe notes save
- Creator recipe create/edit/delete
- Voice guide start/next/auto mode
- `public_recipe_sync` guard automation (script default):
  - Missing `x-worker-secret` returns `401`
  - Invalid `x-worker-secret` returns `401`
  - Valid `x-worker-secret` returns `2xx` and `status=ok`
- If `LOCAL_SYNC_BETA_ENABLED=true`, verify `내 요리 노트` shows the sync beta status card.
- In the sync beta status card, verify `상태 새로고침` works and the status chip/timestamps update.
- In the sync beta status card, verify `프리뷰 실행` shows loading state, disables repeat taps, and refreshes the latest result.
- After file/text import and after creating a personal recipe, verify the sync beta status card refreshes local counts when the flag is enabled.
- After YouTube search/import actions, open `/ops` dashboard and verify related event counters increased (`search.submitted.youtube`, `youtube.search.success` or `youtube.search.failed.{code}`, `youtube.import.completed` or `youtube.import.failed`).

CI run option:
- Run `.github/workflows/internal-track-release-guard.yml` from GitHub Actions workflow_dispatch.
- Keep `localVerification=false`.
- Provide required repository secrets for keystore/firebase/supabase/worker secret.

7. Verify FCM token and notification delivery
- Run on a real Android device.
- Confirm app launches past Firebase initialization.
- Retrieve an FCM registration token in the future messaging implementation or from a local debug helper.
- Send a test notification from Firebase Console.

## Notes
- Do not use `-LocalVerification` for production submission.
- `-LocalVerification` is only for local build validation.
