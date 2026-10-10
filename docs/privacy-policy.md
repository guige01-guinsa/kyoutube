# Privacy Policy Draft

Last update: 2026-09-15

This draft is intended to be published as the app's privacy policy page for Google Play submission. Replace placeholders before publishing.

## What the app collects
- Account information: email address used for login and authentication.
- User content: recipe notes, created recipes, search exclusions, and saved preferences.
- Shopping assistant (prepared, not yet released): saved ingredient/product names, purchase links and pack quantities; user-confirmed purchase quantities, optional paid amounts/currency, source-list references and dates. These are stored under the signed-in account in Supabase.
- Supplier requests (prepared, not yet released): manually entered supplier/contact names and phone numbers, usual ingredients, buyer/business name, reply phone, delivery address and schedule, requested items/quantities/units/specifications, optional unit prices, notes and user-confirmed request status. These are private to the signed-in account in Supabase. Phone contacts are not accessed.
- Supplier catalog (prepared, not yet deployed): supplier-provided business/contact details, delivery regions, product descriptions, user-selected product photos, selling units, optional prices and trading conditions. A supplier explicitly chooses whether to publish these details to other signed-in users. Selecting a public supplier saves a private personal-directory link. Buyer ratings tied to user-confirmed received requests are stored privately and exposed only as an average and count.
- App/device signals: Firebase Cloud Messaging token on supported devices, basic runtime/app diagnostics, and local preference values used for cooking guidance.
- Support data: information you send through feedback or support channels, if added later.

## What the app does not intentionally collect
- Card numbers, bank credentials, or external-store payment authorization. The shopping assistant can store an amount and purchase history entered by the user; it does not process the store payment.
- Precise location data.
- The device address book. Contact details manually entered for supplier requests may be stored.
- Photos or media outside of user-chosen recipe or supplier-product images.

## How data is used
- To authenticate users and keep them signed in.
- To store and sync recipes, search exclusions, and notes.
- To remember shopping links and purchase records, update inventory after shopping-list completion, and import a selected purchase cost into the paid Chef Studio editor.
- To deliver push notifications on supported devices.
- To improve reliability, diagnose errors, and support app operations.

## Sharing
- Data is shared with backend providers required to operate the service, including Supabase and Firebase.
- AI generation sends the recipe/video context needed for the requested draft to OpenAI. This is separate from operational telemetry.
- Data is not sold.
- When the user shares a supplier request, the selected messaging or file-sharing app receives the text/PDF shown in the preview, including any buyer/contact/address information entered. The user chooses the recipient and sends it in that app. PDFs are generated locally; OS sharing may create temporary cached files. Deleting a request or account does not recall copies already sent externally.
- Opening a shopping search sends the ingredient search term to the selected search provider. Opening a saved product link navigates to that store in the external browser/app. Recipe Scout does not send its account token, entire recipe, address or payment details with these links. The destination's own privacy policy applies there; an external page may redirect or require its own sign-in.

## Operational collection with v57

The operational database and seven server observers were deployed on 2026-09-13.
v57 includes the administrator inbox and optional administrator device registration.
This repository draft has not been published to the public policy page.

The new collection stores server outcome categories, HTTP status and duration,
and signed-in app error categories, fatal flag and app build. The backend links
app reports to the authenticated account for rate limiting and account deletion.
It does not receive error messages, stack traces, recipe text, URLs, email or
authentication tokens in these telemetry records. Only administrators can read
aggregates. Usage token counts and manually recorded supplier costs support
budget review. Event cleanup targets records older than 90 days and requires
the daily maintenance job to be enabled. Account-linked app reports are deleted
with the account. Supplier platform logs and cost audit records are separate.

Administrator notification registration stores an FCM token, account/session link,
language and expiration in Supabase. Registration is optional and restricted to
current administrators. Devices expire after 30 days unless renewed; session or
account deletion removes linked registrations. Alert events are cleaned after
90 days by the monitor. Push text contains a generic status-change notice only.
Firebase server sender configuration and device delivery verification are pending.

## Retention
- Unpublishing hides the supplier catalog from other users. Previously shared messages and buyer request snapshots are not recalled. Account deletion removes the supplier's catalog, catalog photos (including abandoned uploads) and that account's buyer ratings; existing buyers retain their private supplier/request snapshots.
- Supplier directory entries and request snapshots can be deleted separately in the app and are removed with the account. Deleting a supplier does not modify the supplier snapshot on an existing request.
- User content remains until the user deletes it or requests account deletion, unless a longer retention period is required for legal or operational reasons.
- Diagnostics and operational logs may be retained for a limited period to support debugging and release monitoring.

## User controls
- You can add, edit, search, favorite and delete personal stores/suppliers, including manually entered website, contact, address and private notes. Directory notes, store addresses, website links and favorite settings are excluded from purchase-request snapshots and shared request documents. A request's delivery address is entered separately by the user.
- You can log out from the app.
- You can delete personal recipes and notes from the app.
- You can edit/remove saved shopping links and correct a purchase record's amount/currency. Purchase quantity snapshots remain until account deletion; editing an amount does not modify inventory or automatically overwrite saved Chef Studio costs.
- You can disable notifications through device settings.

## Contact
- Privacy contact URL: <YOUR_PRIVACY_POLICY_URL>
- Support email: <YOUR_SUPPORT_EMAIL>

## Finalization checklist
- [ ] Replace placeholders.
- [ ] Publish to a stable public URL.
- [ ] Match Google Play Data safety answers to this policy.
- [ ] Review with legal or policy owner if required.
