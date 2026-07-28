$ErrorActionPreference = "Stop"

function Assert-Tool {
    param(
        [string]$Name,
        [string]$Hint
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Missing tool: $Name. $Hint"
    }
}

Write-Host "[1/5] Checking required tools..."
Assert-Tool -Name "flutter" -Hint "Install Flutter SDK and add it to PATH."
Assert-Tool -Name "dart" -Hint "Dart is bundled with Flutter SDK."
Assert-Tool -Name "adb" -Hint "Install Android SDK platform-tools."

Write-Host "[2/5] Checking local env files..."
if (-not (Test-Path ".env.local")) {
    throw "Missing .env.local. Copy .env.local.example and fill values."
}

Write-Host "[3/5] Checking release signing prerequisites..."
if (-not (Test-Path "android/key.properties")) {
    Write-Warning "android/key.properties not found. Release build will fail until signing config is set."
}

Write-Host "[4/5] Running Flutter doctor..."
flutter doctor -v

Write-Host "[5/5] Environment check completed."
