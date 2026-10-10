# Production AAB release runbook

Never use a bare `flutter build appbundle --release` for a Play upload. It omits the production runtime dart-defines and can create an app that fails at launch.

Baseline checked 2026-10-02: signed `1.0.1+94` exists at `release/recipe-scout-v94.aab`.
See [v94 artifact record](release-v94.md). Current source hardening is **not** in v94: see [pending rollout and evidence](completeness-hardening-20261002.md). Preserve prior artifacts and check Play Console before selecting the next version code.
Menu lifecycle and recipe-based purchasing are included; the upload certificate is unchanged.
Google Play upload and physical-device installation checks remain separate.

The guard script now sets `APP_BUILD=<versionName>+<versionCode>` for coarse
operational reports. Builds without that define report `unknown`; do not infer
that the old v53 artifact contains new telemetry.

1. Increase `version:` in `pubspec.yaml`. The number after `+` must be greater than every `release/recipe-scout-v*.aab` file.
2. Keep production values only in ignored `.env.production` with `APP_ENV=production`, `SUPABASE_URL_PRODUCTION`, and `SUPABASE_ANON_KEY_PRODUCTION`.
3. Build only through the guard script:

```powershell
powershell -ExecutionPolicy Bypass -File tools/release/build-production-aab.ps1
```

The script fails before building if the production runtime values, signing configuration, version code, whitespace check, analyzer, or tests are invalid. After building, it verifies the generated manifest version and AAB signature, refuses to overwrite an existing release, and writes `release/recipe-scout-v<versionCode>.aab` plus a non-secret provenance JSON file with its hash.

After uploading, install the exact Play test-track build on a phone and complete the smoke checklist before promoting it. The AAB filename and the provenance JSON must match the uploaded artifact.

Use `-ValidateOnly` to run the preflight checks without creating an AAB.

## Icon and asset integrity gate

The production script invokes verify-aab-assets.ps1 against the actual AAB before publishing the artifact. Empty FontManifest.json, missing registered fonts, empty AssetManifest.bin or empty NOTICES.Z fail the release. See [v82 icon recovery](android-icon-recovery-v82.md).

## R8 optimization gate (v85 onward)

Keep release minification/resource shrinking enabled and preserve Flutter/plugin consumer rules. The production build script invokes verify-aab-optimization.ps1 before copying the AAB to release/. Missing/invalid/empty R8 JSON, missing/empty mapping, or missing/empty DEX fail the release. Archive the mapping and R8 metadata with each released version for crash analysis. The signed AAB embeds both. Do not equate metadata presence with achieving Play score thresholds or passing on-device tests.

If the device's installed Play certificate differs from the upload certificate, do not uninstall the app to sideload a locally signed build. Upload the AAB to a Play test track and update through Play, preserving user data. See [Android R8 optimization](android-r8-optimization.md).

## Packaged manifest verification (v85 onward)

Optimization can change AGP's intermediate manifest task path. Do not trust an old build/app/intermediates/bundle_manifest output: during v85 it still reported84 while the actual AAB correctly reported85. verify-aab-manifest.ps1 reads the **final AAB** with official bundletool and checks package ID, version code, and version name. Regression checks cover actual84/85 and deliberate version mismatches.

Prerequisite: official [bundletool1.18.3](https://github.com/google/bundletool/releases/tag/1.18.3), saved as .artifacts/tools/bundletool-all-1.18.3.jar (or pass -BundletoolPath). Download URL: https://github.com/google/bundletool/releases/download/1.18.3/bundletool-all-1.18.3.jar . SHA-256: `a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29`. The downloaded file was checked against the official GitHub release asset digest. Do not upgrade Android Gradle/Flutter just to obtain this standalone verification tool.
