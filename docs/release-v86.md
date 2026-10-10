# Recipe Scout Android v86 (1.0.1+86)

## Scope

User requested a new signed AAB containing the mobile layout and Android exit confirmation changes. Production web and database are outside this release-build request.

- Home import/create actions share a row; smaller mobile title and spacing reveal more content. Large text switches actions to a vertical arrangement, while the narrowest normal-text screens omit icons to keep labels intact.
- Bottom navigation uses `내 레시피` / `My recipes`; recipe ownership, screen titles and stored data remain unchanged.
- Android back first delegates to GoRouter history and existing editor exit guards. At the app root it offers continue, keep login and exit, or sign out and exit. Guests see their signed-out state and continue/exit choices. Sign-out failures keep the activity open.
- Android framework back handling prevents predictive back from bypassing the exit confirmation. Web and iOS retain their existing dispatcher.
- R8 optimization/shrinking/obfuscation from v85 stays enabled. Package ID, upload signing configuration and bundled icon/Korean fonts are preserved.

## Validation

Implementation checks before release: analyzer clean, Flutter 658 passed / 4 existing conditional skips. Includes 10 new exit-flow tests and Korean/English 200% text cases. Real Flutter mobile layout renders are in `.artifacts/mobile-home-compact/`.

The release build runs `tools/release/build-production-aab.ps1` using pinned Flutter 3.44.8 and JDK17. The guarded build completed successfully; the release-time analyzer and all 658 Flutter tests passed (4 existing skips). Gradle bundleRelease completed in 282 seconds. Final AAB package/version/signature, R8 metadata and mapping, fonts/assets and official bundletool validation passed. All 16 required Android/plugin entrypoints remain in optimized DEX. Upload certificate, icon/Korean fonts and 9 native dependency libraries match v85. All 271 recorded application inputs remained unchanged during the build.

- Size: 78,250,454 bytes.
- SHA-256: `6cac3cc632e2c4424fe2d9eadac9e277be7011e2bc5ef2e3b0adecaaf37dadd7`.
- Uncompressed DEX: 1,544,840 bytes, unchanged from v85; optimization/shrinking/obfuscation remain enabled. This is not a claim about Play Console's eventual displayed score.

## Artifacts

- `release/recipe-scout-v86.aab`
- `release/recipe-scout-v86-release-notes.txt`
- Release logs and final verification: `.artifacts/release-v86/`

## Remaining device validation

AAB generation does not upload or release it on Google Play. Install the exact Play test-track v86 update and check home buttons, navigation labels and Android back behavior. Confirm that detail back preserves navigation and editing guards, cancel keeps the app open, keep-login exit preserves the session, and explicit logout exits then requires login on reopening. Physical-device v86 validation has not yet been performed. Do not uninstall the user's existing Play app to sideload an upload-key-signed build.
