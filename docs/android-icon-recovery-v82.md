# Android icon recovery — 2026-09-24

## Confirmed failure

The v81 AAB contains an empty (0-byte) `base/assets/flutter_assets/FontManifest.json` and empty `NOTICES.Z`. The v77–v80 bundles contain valid font registrations. The connected phone runs the Google Play installation of versionCode 81 and shows the same corrupted icons as the supplied screenshots.

The v81 MaterialIcons font itself contains the affected search, rounded search, menu-book and more icons. Their glyph outlines match the pinned Flutter SDK. Missing icon glyphs from tree shaking was an initial hypothesis, not the confirmed defect. Without the font registration the device falls back to its text fonts.

## Recovery and guard

- Clean all generated Flutter build outputs before rebuilding v82, using Flutter 3.44.8 and JDK 17.
- Preserve the existing package ID and upload signing configuration.
- Include the complete MaterialIcons font in the Android build as a conservative packaging choice.
- Before a release artifact can be copied into `release/`, inspect its actual ZIP contents: parse the font manifest, require MaterialIcons registration, require every registered font file, and reject empty asset manifests or license notices.
- The guard accepts v80 and rejects v81. It runs in the production AAB script before signature and provenance publication.
- Administrator menu translations were completed as part of the full release checks.

## Distribution

The installed app comes from Google Play. Deliver the new AAB through the test/release track and update the phone from Play. This task does not uninstall the installed app or clear user data. Device confirmation after the Play update remains necessary.

Build and signing results are recorded in release-v82.md after completion.
