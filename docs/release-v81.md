> Superseded: do not distribute the v81 Android AAB. Its FontManifest.json and NOTICES.Z are empty; Android icon rendering is broken. See [v82 recovery](android-icon-recovery-v82.md). The previous signature-only checks did not detect this packaging defect.

# Recipe Scout v81 release — 2026-09-24

- Web: https://recipe-scout-workspace.web.app
- Android App Bundle: `release/recipe-scout-v81.aab`
- Package/version: `com.kyoutube.app` / `1.0.1+81`
- AAB SHA-256: `8DDA641BFF656F14B52B6A6A512E435CF602F34CACAEEBA69562FF731BD35C26`

## Included operation changes

- Design refresh across the recipe, business, shopping and supplier workflows.
- Supabase migration `0071_affiliate_catalog_management` only, with catalog audit history and administrator-only actions.
- No affiliate products imported or published; the initial 100 links remain review drafts.

## Verification

- Flutter 3.44.8: `flutter analyze` clean; 616 tests passed and 4 existing conditional tests skipped.
- Web bundle credential scan passed and source maps are absent.
- Public v81 release-info and production response security headers checked.
- AAB manifest version and jarsigner verification passed.

Google Play Console upload was not performed.