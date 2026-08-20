function Get-ProjectFlutter {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $fvmConfigPath = Join-Path $ProjectRoot ".fvmrc"
    if (-not (Test-Path -LiteralPath $fvmConfigPath)) {
        throw "Missing .fvmrc. The project Flutter version cannot be resolved."
    }

    $expectedVersion = (Get-Content -LiteralPath $fvmConfigPath -Raw | ConvertFrom-Json).flutter
    if ([string]::IsNullOrWhiteSpace($expectedVersion)) {
        throw "The .fvmrc Flutter version is empty."
    }

    $fvmFlutter = Join-Path $ProjectRoot ".fvm/flutter_sdk/bin/flutter.bat"
    if (-not (Test-Path -LiteralPath $fvmFlutter)) {
        $globalFlutter = Get-Command flutter -ErrorAction SilentlyContinue
        $globalHint = if ($globalFlutter) {
            $globalVersionOutput = & $globalFlutter.Source --version 2>&1
            $globalVersionLine = if ($LASTEXITCODE -eq 0) {
                $globalVersionOutput | Select-Object -First 1
            } else {
                "version check failed"
            }
            " Global Flutter reports '$globalVersionLine' and will not be used."
        } else {
            " No global Flutter executable was found."
        }

        throw (
            "Project FVM SDK is missing: $fvmFlutter. " +
            "If the 'fvm' command is unavailable, install it with 'dart pub global activate fvm' and add the Dart Pub cache bin directory to PATH. " +
            "Then run 'fvm install $expectedVersion' from the repository root. " +
            "The project requires Flutter $expectedVersion from .fvmrc.$globalHint"
        )
    }

    $versionOutput = & $fvmFlutter --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to run the project FVM Flutter SDK at $fvmFlutter. Reinstall it with 'fvm install $expectedVersion'."
    }

    $versionLine = $versionOutput | Select-Object -First 1
    if ($versionLine -notmatch "Flutter\s+$([regex]::Escape($expectedVersion))\b") {
        throw "Project FVM Flutter must be $expectedVersion according to .fvmrc, but reports: $versionLine"
    }

    return $fvmFlutter
}
