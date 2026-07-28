# Google Play Data Safety Submission Package

Last update: 2026-07-19

Use this as the source of truth while completing the Google Play Data safety form.

## Collected data categories
- Account information: email address.
- App activity and user content: recipes, notes, bookmarks, and usage state that helps the app resume cooking progress.
- App info and performance: crash/diagnostic and startup state used for release monitoring.
- Device or other identifiers: Firebase Cloud Messaging token on supported devices.

## Purposes
- App functionality.
- Account management.
- Analytics or diagnostics, if enabled later.
- Communications, for push notifications.

## Shared data
- Supabase backend services for authentication and app data storage.
- Firebase services for push notifications and app initialization.

## Data handling
- Data is used to provide the core app experience and is not sold.
- Some data may be retained until account deletion or manual cleanup.
- Logs and diagnostics are retained for operational support only.

## Notes for Play form
- Confirm whether diagnostics are "collected" in the exact release build.
- Confirm whether crash reporting is enabled before marking it in the form.
- Align the final form with the public privacy policy.
- Canonical policy URLs:
	- Privacy: https://github.com/guige01-guinsa/kyoutube/blob/main/docs/privacy-policy.md
	- Terms: https://github.com/guige01-guinsa/kyoutube/blob/main/docs/terms-of-service.md

## Finalization checklist
- [x] Decide final public URLs.
- [x] Fill the Play Data safety answers package with release-specific declarations.
- [x] Re-check permissions against actual app behavior.
