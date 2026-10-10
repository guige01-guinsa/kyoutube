# Recipe Scout brand artwork

The approved mark is the peeking chef: an oversized tilted hat covering one eye,
one bright visible eye, peach cheeks, and a playful smile.

- Source artwork: `recipe-scout-icon-v5-peek.png`.
- App asset and 1024 px master: `recipe-scout-icon.png`.
- Store upload: `../../store-assets/recipe-scout-play-icon-512.png`.
- Source generation details: `recipe-scout-icon-v5-peek-prompt.md`.
- Earlier numbered concepts are retained as design history, not bundled in the app.

Run `powershell -ExecutionPolicy Bypass -File tools/dev/export-brand-icons.ps1`
from the repository root to export the same approved pixels for Android launchers,
Android and iOS launch screens, the iOS app icon catalog, Flutter, and Google Play.
The exporter uses Windows System.Drawing and does not regenerate the artwork.
Outputs are opaque PNGs. Native launch backgrounds match the source corner color.

Android adaptive foregrounds are 108 dp with the original image centered in a
72 dp viewport. The mascot fits the 66 dp safe circle. Android 12 and later use
the same adaptive icon on their system splash screen, including dark mode.

References: [Android adaptive icons](https://developer.android.com/codelabs/basic-android-kotlin-compose-training-change-app-icon)
and [Google Play preview assets](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en).
