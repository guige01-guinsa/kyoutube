# Google Play Data Safety Draft

Last update: 2026-09-13

Use this draft with the exact deployed app/backend behavior while completing
the Google Play form. It is not a submitted declaration.

## Release distinction

The signed v53 AAB predates the new central app-error reporter. v57
sends fixed error categories, fatal flag and app build after sign-in; the
backend associates the authenticated user ID. These are diagnostics linked to
an account, even though no error message or recipe text is in the event.
Seven updated server functions record outcome/status/duration in production as of
2026-09-13. v57 adds optional administrator FCM token registration, stored with an
account/session link and language. Tokens renew for 30 days; expired registrations
and old alert events are cleaned by the monitor. Server sender credentials and
real-device push verification remain pending.
Declare the active backend collection as well as the exact client build.
Do not describe collection as anonymous. Aggregates are administrator-only.
The 90-day event cleanup requires the daily job in OPERATIONS_RUNBOOK.md; account
deletion removes associated client reports. Publish notices before enabling it.

## Collected data categories
- Prepared supplier requests / migration 0052: optional manually entered names, phone numbers, delivery addresses, supplier details and purchase-request contents/status, linked to the account for app functionality. Review name/address/phone and user-content/purchase categories before release. No device address-book access is requested. The user explicitly shares selected request contents through another app; assess the user-initiated sharing exception against the current Play form when publishing.
- Prepared shopping assistant / migration 0051: optional user-entered purchase history (ingredient/product, quantity, amount/currency and date), plus saved product links and pack quantities, linked to the account for app functionality. Update the purchase-history/financial-information declaration and public policy before releasing this feature. No card or bank credentials are collected by this feature, and no store checkout is processed in the app.
- Account information: email address.
- App activity and user content: recipes, notes, search exclusions, and usage state that helps the app resume cooking progress.
- App info and performance: crash/diagnostic and startup state used for release monitoring.
- Device or other identifiers: Firebase Cloud Messaging token on supported devices.

## Purposes
- App functionality.
- Account management.
- Reliability diagnostics according to the deployed collection described above.
- Communications, for push notifications.

## Shared data
- Supabase backend services for authentication and app data storage.
- Firebase services for push notifications and app initialization.
- OpenAI receives requested AI recipe/video context for draft generation; this
  content is separate from the minimal operations event payload.

## Data handling
- Data is used to provide the core app experience and is not sold.
- Some data may be retained until account deletion or manual cleanup.
- Logs and diagnostics are retained for operational support only.

## Notes for Play form
- Pending DB 0053 adds user-entered store websites, addresses, private notes and favorite settings to the private supplier directory. Review these with the existing DB 0052 contact/address and user-content declarations before publishing. No contact-book permission is introduced; private directory notes are excluded from shared requests.
- Confirm whether diagnostics are "collected" in the exact release build.
- Confirm whether crash reporting is enabled before marking it in the form.
- Align the final form with the public privacy policy.

## Finalization checklist
- [ ] Decide final public URLs.
- [ ] Fill the Play Data safety form with release-specific answers.
- [ ] Re-check permissions against actual app behavior.
