# Play Console Internal Track Upload Guide

Last update: 2026-07-28

## Context

The signed release AAB (`build/app/outputs/bundle/release/app-release.aab`, ~56 MB) has been
built successfully.  This document lists every step needed to publish it to the Google Play
**internal testing** track and verify the result.

---

## Step 1 – Locate the AAB

The file is at:
```
<project-root>/build/app/outputs/bundle/release/app-release.aab
```

If you no longer have it, re-run the build script:
```powershell
powershell -ExecutionPolicy Bypass -File tools/release/run-internal-track-validation.ps1 `
  -SupabaseUrlProduction "https://<your-project-ref>.supabase.co" `
  -SupabaseAnonKeyProduction "<YOUR_PRODUCTION_ANON_KEY>" `
  -SkipPublicRecipeSyncSmoke
```

---

## Step 2 – Open Play Console

1. Go to [Google Play Console](https://play.google.com/console) and sign in with your developer
   account.
2. Select the **K-youtube** app (package `com.kyoutube.app`).  
   If the app listing does not exist yet, create it first under **Create app**.

---

## Step 3 – Navigate to Internal Testing

1. In the left sidebar click **Testing → Internal testing**.
2. Click **Create new release** (top-right button).

---

## Step 4 – Upload the AAB

1. In the **App bundles** panel click **Upload**.
2. Select `build/app/outputs/bundle/release/app-release.aab` from your local machine.
3. Wait for the upload and processing to complete.  The bundle version code and name will be
   shown after processing.

---

## Step 5 – Fill in release notes

Add a short note in Korean for internal testers, for example:
```
내부 테스트 빌드 – 공개 레시피 목록, 구독자 레시피, 보이스 가이드, 북마크 포함.
```

---

## Step 6 – Save and roll out

1. Click **Save** to save the draft.
2. Review the summary (no policy warnings should appear for a new internal build).
3. Click **Roll out to internal testing**.
4. Confirm the roll-out dialog.

---

## Step 7 – Add internal testers

1. Go to **Testing → Internal testing → Testers** tab.
2. Add the Google accounts that will install the test build.
3. Copy the **opt-in link** and share it with each tester.

---

## Step 8 – Install and smoke-test on a real device

Once Play Console shows the release as **Available to testers**, open the opt-in link on an
Android device, install the build, and run the smoke checklist:

```
docs/ops-smoke-checklist.md
```

Key flows to verify:
- App launches without startup error.
- Login / logout.
- Public recipe list and detail.
- "내 레시피로 복사" (copy to my recipe).
- Creator recipe create / edit / delete.
- Voice guide start / next / stop.
- Bookmark add / remove.
- Home screen 운영 상태 card shows `production` environment.

---

## Step 9 – Verify FCM on the device

1. Launch the app on a real device.
2. Check that it initialises past the Firebase startup phase without errors.
3. In Firebase Console → **Engage → Messaging** click **Send test message**.
4. Enter the FCM registration token (visible in the debug log or ops card) and send.
5. Confirm the notification arrives on the device.

---

## What comes after this

| # | Task | Reference |
|---|------|-----------|
| 1 | Publish privacy policy URL | `docs/privacy-policy.md` |
| 2 | Publish terms of service URL | `docs/terms-of-service.md` |
| 3 | Complete Play Data safety form | `docs/google-play-data-safety.md` |
| 4 | Fill content-rating questionnaire | Play Console → Policy → App content |
| 5 | Create store assets (icon, screenshots, descriptions) | Play Console → Main store listing |
| 6 | Promote to production when all P1 items close | `docs/staging-uat-checklist.md` |

See `docs/google-play-release-readiness.md` for the full readiness score and blocking gaps.
