param(
    [Parameter(Mandatory = $false)]
    [switch]$LocalVerification,

    [Parameter(Mandatory = $false)]
    [string]$FlutterPath = "C:\Users\ADMIN\tools\flutter\bin\flutter.bat",

    [Parameter(Mandatory = $false)]
    [string]$SupabaseUrlProduction,

    [Parameter(Mandatory = $false)]
    [string]$SupabaseAnonKeyProduction
)

$ErrorActionPreference = "Stop"

function Assert-PathExists {
    param(
        [string]$Path,
        [string]$Hint
    )

    if (-not (Test-Path $Path)) {
        throw "Missing required file: $Path`nHint: $Hint"
    }
}

Write-Host "[1/5] Checking Flutter SDK path..."
Assert-PathExists -Path $FlutterPath -Hint "Set -FlutterPath to your flutter.bat location."

Write-Host "[2/5] Checking Android release signing files..."
Assert-PathExists -Path "android/key.properties" -Hint "Copy android/key.properties.example to android/key.properties and fill real values."

# Validate key.properties content basics.
$keyProps = Get-Content "android/key.properties" -Raw
foreach ($field in @("storeFile", "storePassword", "keyAlias", "keyPassword")) {
    if ($keyProps -notmatch "(?m)^\s*$field\s*=") {
        throw "android/key.properties is missing '$field'."
    }
}

if ($keyProps -match "replace-with-keystore-password|replace-with-key-password") {
    throw "android/key.properties still contains placeholder passwords. Replace them with real secret values."
}

# Resolve storeFile path from key.properties.
$storeFileLine = ($keyProps -split "`r?`n") | Where-Object { $_ -match "^\s*storeFile\s*=" } | Select-Object -First 1
$storeFileValue = ($storeFileLine -split "=", 2)[1].Trim()
$keystoreFullPath = if ([System.IO.Path]::IsPathRooted($storeFileValue)) {
    $storeFileValue
} else {
    # Match Gradle file() behavior in app module where storeFile is typically relative to android/app.
    Join-Path "android/app" $storeFileValue
}

Assert-PathExists -Path $keystoreFullPath -Hint "Place the upload keystore at the storeFile path in android/key.properties."

Write-Host "[3/5] Checking Firebase Android config..."
Assert-PathExists -Path "android/app/google-services.json" -Hint "Download from Firebase Console for package name and place under android/app/."

Write-Host "[4/5] Building signed release appbundle..."
$buildArgs = @("build", "appbundle")

if ($LocalVerification.IsPresent) {
    $buildArgs += "-PallowDebugSigningForRelease=true"
    Write-Warning "LocalVerification enabled. This should NOT be used for Play submission."
}

if (-not [string]::IsNullOrWhiteSpace($SupabaseUrlProduction)) {
    $buildArgs += "--dart-define=SUPABASE_URL_PRODUCTION=$SupabaseUrlProduction"
}

if (-not [string]::IsNullOrWhiteSpace($SupabaseAnonKeyProduction)) {
    $buildArgs += "--dart-define=SUPABASE_ANON_KEY_PRODUCTION=$SupabaseAnonKeyProduction"
}

$buildArgs += "--dart-define=APP_ENV=production"

& $FlutterPath @buildArgs
if ($LASTEXITCODE -ne 0) {
    throw "flutter build appbundle failed with exit code $LASTEXITCODE"
}

$aabPath = "build/app/outputs/bundle/release/app-release.aab"
Assert-PathExists -Path $aabPath -Hint "Check the release build output path and fix the build before uploading."

Write-Host "[5/5] Build completed."
Write-Host "Output: $aabPath"
Write-Host "Next: upload this AAB to Play Console Internal testing track."
