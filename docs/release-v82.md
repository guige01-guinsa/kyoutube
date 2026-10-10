# Recipe Scout v82 release — 2026-09-24

- Web: https://recipe-scout-workspace.web.app
- Android package/version: `com.kyoutube.app` / `1.0.1+82`
- AAB: [recipe-scout-v82.aab](../release/recipe-scout-v82.aab), 76.9 MB as reported by Flutter.
- SHA-256: `66E8EE857E82FCEA60B42B32C4CA6439EE4696CB0B3AC9055034E7E856865163`
- Build provenance: [JSON](../release/recipe-scout-v82.aab.provenance.json).

## Android icon recovery

The v81 bundle contained an empty FontManifest.json and NOTICES.Z. The installed Google Play v81 app displayed fallback characters instead of icons. The actual icon glyphs existed; icon tree shaking was not the confirmed cause. See [investigation and recovery](android-icon-recovery-v82.md).

A clean build with Flutter 3.44.8 / JDK 17 restored the font registrations. The production build now rejects missing or empty font registrations, registered font assets, asset manifests and license notices before publishing a release artifact. It includes the full MaterialIcons font as a conservative packaging choice.

Final v82 ZIP inspection:

- FontManifest.json: 168 bytes; registers MaterialIcons and RecipeScoutKR.
- MaterialIcons-Regular.otf: 1,645,184 bytes; SHA-256 identical to the pinned SDK font.
- NanumGothic-Regular.ttf: 2,054,744 bytes.
- AssetManifest.bin: 670 bytes; NOTICES.Z: 115,850 bytes.
- Manifest version, jarsigner verification and upload certificate continuity with v81 passed.
- Regression guard accepts v80 and rejects the defective v81 bundle.
- Full Flutter analysis: no issues. Full Flutter tests: 617 passed, 4 existing conditional skips.

The connected phone still runs Google Play v81. No Play Console upload, device replacement install, uninstall or data clearing was performed. Upload v82 to the appropriate Play track and update through Play; verify icons on the device after that update. Release text: [Korean notes](release-notes-v82-ko.md).

## Administrator entry points and web

Administrator accounts can open **관리자 홈** from **더보기/내 정보** and account management. Existing membership, route and server authorization remain enforced. Administrator home links to member, affiliate catalog and service management. The AAB also includes the completed English administrator-menu translations.

The prior web v82 deployment was verified with release-info, security headers, source-map absence and privileged credential scanning. Workspace role tests: 23 passed. Deployed main bundle SHA-256: `90564d926ee2cef9c546c179ba0123237277fb138c00a20935f00bf061a105ad`. That web build predates the final three English administrator-menu translations; it was not rebuilt during the Android recovery.

## Affiliate catalog import

The user-authorized 100-row CSV was imported into the production DB as review drafts on 2026-09-24 at 06:18 UTC. Before: 0 matching records. Inserted: 100. After: 100 matching records, 0 published, 0 deleted. Existing records were not changed. Duplicate links were checked; this import is insert-only and transactional. Database audit triggers remained enabled. All imported entries are unverified, unpublished, and unavailable on web/mobile until reviewed.

- Source: `tools/data/affiliate-catalog/initial-100-drafts.csv`.
- Source SHA-256: `0221eae69621569d566da5e3680e608a17597fd3e985961debb0121843ea002c`.
- Operational result: `.artifacts/release-v82/catalog-import-applied.json`.
- User location: **관리자 홈 → 제휴 상품 관리**.

Public release of products remains incomplete: titles/specifications need confirmation. A normal request to the supplied sample affiliate link followed its redirect to Coupang but returned HTTP 403, preventing product-page verification. No access restriction was bypassed and no unverified product was marked reviewed or published.

Migration 0071 was applied during v81; this recovery/import added no schema migration or Edge Function deployment.
