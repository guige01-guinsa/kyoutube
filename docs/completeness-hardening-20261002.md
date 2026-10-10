# Completeness hardening — 2026-10-02

Source changes are prepared for the next release. They have **not** been applied to the production database, deployed web, Edge Functions, or the v94 AAB. `1.0.1+94` is preserved; a future Android release needs a new version code.

## Completed implementation

- Latin American Spanish: expanded fixed-copy catalog, shared bilingual helpers, literal text widgets, and placeholder-safe dynamic translations. No recipe, transaction, or personal data was sent for translation. The user explicitly approved sending up to 5,000 fixed UI strings to the OpenAI Responses API with the existing key. 3,815 missing phrases were generated; reviewed overrides remain authoritative. The source extractor currently reports 3,952 phrases, zero missing.
- Spanish search uses Spanish relevance and an allowed Latin American/Spanish-speaking region, instead of silently searching in Korean. Recipe generation and repair prompts, video analysis, and purchase review accept the selected language. The legacy public-reference enrichment endpoint also receives an explicit locale.
- AI acceptance checks reject wholly unverified ingredient/step sets, unknown ingredient links, missing source evidence, and predominantly Korean prose for an English/Spanish request. Conservative checks flag direct contradictions in exact-name ingredient quantities and explicit cooking temperature/time; equivalent kg/g, L/mL and C/F conversions are allowed. Ambiguous portions, translated names, absent measurements and inferred estimates are not treated as proven contradictions. Existing repair and incomplete-draft recovery remain in use. These checks do not establish factual cooking accuracy or replace a user's review.
- Quantities, money fields, and conversion factors share one finite-number parser. `1,5` is 1.5, `1,500` retains its prior thousands meaning, and `1.234,5` is 1234.5. Invalid/nonfinite inputs fail. Metric conversions remain dimensional: kg/g and L/mL only; mass/volume and package factors require user input.
- Common Spanish ingredient aliases receive editable categories. Category equivalence never merges two ingredients or invents a package weight. 진간장 and salsa de soya are seasonings.
- Shopping preparation drafts can synchronize per signed-in account. Local pending edits survive connection failures. Compare-and-swap revisions prevent another device's changes being overwritten; users can retry or explicitly discard their local edits and load the cloud copy. Each editor has its own revision. No purchase, stock, or payment is created by saving a draft.
- Administrator connection diagnostics report configuration presence/shape, distinguish setup from successful live verification, require administrator role and MFA, and never return secret values. Spanish operational push notifications are supported.
- Recovery tooling supports password-based portable encryption in addition to Windows-user encryption. Optional bounded Storage capture adds object bytes and a hash/index to the encrypted archive. A restore-test command targets only a newly created, randomly named database in an explicitly named local Supabase container, verifies row counts, and removes that temporary database.
- Signing property variations and service-account file names are ignored by Git. No signing keys, project identity, or product versions changed.

## Database and server rollout

Apply new migrations in order; never edit prior migrations:

1. `0084_shopping_preparation_sync.sql`: owner-only drafts and optimistic revision RPC.
2. `0085_admin_integration_readiness.sql`: administrator/MFA readiness gate.
3. `0086_ops_spanish_language.sql`: Spanish operational notification registration.

Updated server functions: `youtube_search`, `ai_youtube_recipe_assistant`, `ai_youtube_video_assistant`, `ai_recipe_assistant`, `ai_purchase_request_review`, `operations_monitor`. New function: `integration_readiness`. Deploy dependent DB changes before the new client. An older server leaves drafts locally saved with a retry notice; it must not be represented as successful cloud sync.

## Verification evidence

- Required `tools/dev/verify.ps1`: completed successfully, static analysis clean, **824 Flutter tests passed, 4 existing optional skips**. `.artifacts/hardening-verify.log`. After the final catalog and numeric-JSON comparison adjustment, **35 targeted tests passed** in `.artifacts/hardening-followup-final.log`; final static analysis is clean in `.artifacts/hardening-analyze-final.log`.
- Mock server tests: **90 passed**, `.artifacts/hardening-deno-final.log`. All **10 synthetic acceptance-gate scenarios** match the desired result, `.artifacts/hardening-quality-probe.json`. These are injected fixtures, not a live AI success-rate estimate. AI enrichment and readiness entry points pass Deno type checks, `.artifacts/hardening-deno-check.log`.
- Disposable PostgreSQL: preparation access/revision contract 14 checks; administrator/MFA and Spanish device registration 7 checks. No production records used or changed.
- Synthetic recovery tests: portable encryption round-trip, wrong-password/tamper rejection, bounded KDF, Storage metadata/bytes capture, changed-object detection, and incomplete-snapshot rejection passed.
- Additional Spanish narrow/large-text diagnostics, AI locale transport, and ingredient-category checks are recorded in `.artifacts/hardening-ui-final.log`.

## Remaining external verification

The user clarified that credentials were issued but their saved location is unknown. Downloads, Desktop, Documents and the three project folders were checked by file name and JSON structure without printing secrets; 96 small JSON files contained no Google service-account key. Relevant text-file searches returned no candidate. Browser download history could not be inspected because the computer-use runtime failed to initialize.

Required server configuration: Coupang Partners Access/Secret keys; a Google Play service account with Play Console permissions; RTDN audience/service-account email; Firebase messaging service account. An Android `key.properties.txt` is signing configuration and cannot replace these credentials. Existing manually registered affiliate links remain usable. API searches, real purchases/restores/renewals, and actual device push delivery cannot be declared verified until the correct credentials and test accounts are connected.

Google does not permit re-downloading an existing service-account private key. First locate the downloaded JSON; if it is unavailable, use the account's normal key-management process to create a replacement and validate it before retiring a key in use. Do not paste private keys into chat. [Google key documentation](https://docs.cloud.google.com/iam/docs/keys-create-delete).

Production restoration, Storage restoration into a fresh environment, offsite backup destination/schedule, and Android device end-to-end checks remain unverified. Docker Desktop was not running during this turn. A phone is connected but reports v86; only its installed version was read. The user explicitly requested that current changes not be tested against that old installation. Perform device feature testing only after the appropriate new test build is installed. The backup tool does not equate encryption/hash checks with a proven database or object-storage recovery. No production Auth data was exported during this work.

Flutter doctor still reports existing global PATH SDK mismatch, unknown Android license status and incomplete Windows Visual Studio components. All app checks above used the pinned local Flutter 3.44.8. No SDK upgrade or license acceptance was performed.

Spanish support does not automatically change a transaction's currency or enable payment processing in additional countries. Existing KRW/USD contracts remain explicit; no exchange rate or country-specific tax is inferred. New web checkout requires a separately selected and configured payment provider; existing Play entitlements and their server verification are retained.

## Release controls

Keep the v94 AAB immutable. After production rollout is explicitly approved, use the repository release scripts with production defines, a new version code (at least 95, after checking Play), and the same signing identity. Verify deployed source/build hashes, administrator diagnostics, cross-device conflicts, and live service calls separately. Missing external credentials are not a reason to mark those checks successful.
