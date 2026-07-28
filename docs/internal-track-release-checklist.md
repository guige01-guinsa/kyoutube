# Internal Track Release Checklist

Last update: 2026-07-28

## Scope
- Phase 2 / Operations & Policy Track / Step 1
- Goal: produce a signed AAB and upload to Google Play internal testing

## Current status (workspace scan)
- `android/key.properties`: present ✅
- upload keystore file: present ✅
- `android/app/google-services.json`: present ✅
- `ios/Runner/GoogleService-Info.plist`: missing (iOS not in current scope)
- Strict release build result: ✅ AAB built successfully (~56 MB)
- AAB location: `build/app/outputs/bundle/release/app-release.aab`
- **Next action: upload AAB to Play Console internal testing track** → see `docs/play-console-upload-guide.md`

## Step-by-step
1. ✅ Create release signing config
- Copy `android/key.properties.example` to `android/key.properties`.
- Fill all values: `storeFile`, `storePassword`, `keyAlias`, `keyPassword`.
- Place the keystore file at the `storeFile` location.

2. ✅ Add Firebase Android config
- Download `google-services.json` from Firebase Console for package `com.kyoutube.app`.
- Place it at `android/app/google-services.json`.

3. Add Firebase iOS config (skip if iOS is out of scope)
- Download `GoogleService-Info.plist` from Firebase Console for the iOS app.
- Place it at `ios/Runner/GoogleService-Info.plist`.
- Open Runner in Xcode and ensure the plist is added to the Runner target resources.

4. ✅ Build production-like signed AAB
```powershell
powershell -ExecutionPolicy Bypass -File tools/release/run-internal-track-validation.ps1 `
  -SupabaseUrlProduction "https://<your-project-ref>.supabase.co" `
  -SupabaseAnonKeyProduction "<YOUR_PRODUCTION_ANON_KEY>"
```

AAB output: `build/app/outputs/bundle/release/app-release.aab` (~56 MB)

5. ⬜ **Upload to Play Console Internal testing**  ← current step
- Follow the detailed guide in `docs/play-console-upload-guide.md`.
- Upload `build/app/outputs/bundle/release/app-release.aab`.
- Confirm track processing succeeds and tester opt-in link is available.

6. ⬜ Smoke test on internal build
- Login
- Public recipe browse/detail
- Copy to my recipe
- My recipe notes save
- Creator recipe create/edit/delete
- Voice guide start/next/auto mode

7. Verify FCM token and notification delivery
- Run on a real Android device.
- Confirm app launches past Firebase initialization.
- Retrieve an FCM registration token in the future messaging implementation or from a local debug helper.
- Send a test notification from Firebase Console.

## Notes
- Do not use `-LocalVerification` for production submission.
- `-LocalVerification` is only for local build validation.
