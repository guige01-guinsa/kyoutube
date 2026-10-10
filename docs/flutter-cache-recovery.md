# Flutter cache access on Windows

The project uses `.fvm/flutter_sdk/bin/flutter.bat` (Flutter 3.44.8).
The junction resolves to `C:\Users\ADMIN\fvm\versions\3.44.8`.

## Cause and working execution mode

The SDK belongs to the Windows `ADMIN` account. Codex's restricted shell
can run as `CodexSandboxOffline`, with read-only inherited access to much
of the SDK. Flutter writes cache lock files, engine metadata and artifact
stamps even when running `--version` or `analyze`. The batch launcher can
silently loop while it cannot open its cache lock file.

Run Flutter validation and release commands with the SDK owner's account.
In Codex, request elevated execution for the specific Flutter/verification
command. This avoids granting the sandbox account persistent write access
to the entire SDK. Do not switch to the global Flutter installation.

From a terminal running as the SDK owner, in this repository:

```powershell
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
& .fvm/flutter_sdk/bin/flutter.bat --version --suppress-analytics
powershell -ExecutionPolicy Bypass -File tools/dev/verify.ps1
```

After validation and an explicit release request:

```powershell
powershell -ExecutionPolicy Bypass -File tools/release/build-production-aab.ps1
```

Do not delete active lock files or terminate unrelated command shells.
Do not change signing keys or production configuration to fix SDK access.
SDK-owner execution also avoids the Git ownership mismatch and telemetry
file access failures seen in the restricted shell.

## Recovery verification

SDK-owner execution returned Flutter 3.44.8 / Dart 3.12.2 successfully.
Dependency resolution and static analysis subsequently ran without cache
access errors. Analysis reported no issues after fixing the incomplete
localization changes (runtime values inside a const list, missing Material
localization delegates, and localized application title resolution).
Flutter 3.44.8's localization package requires `intl` 0.20.2.

Language widget tests use the device's locale list, and find the back button
by widget type so its translated tooltip does not break navigation tests.
All 12 tests in `test/widget_test.dart` passed after these corrections.
The final full test rerun passed all 139 tests.
Local verification logs (ignored by Git):

- `.artifacts/cache-recovery-verify.log`: initial full validation and analyzer result.
- `.artifacts/cache-recovery-widget-test.log`: successful focused rerun.
- `.artifacts/cache-recovery-all-tests.log`: final full test rerun.

The version 45 localization work is still partial: the home shell and
navigation are localized, while other feature screens still contain Korean
UI strings. Passing toolchain validation does not imply complete English UI
coverage or creation of a version 45 release artifact.
