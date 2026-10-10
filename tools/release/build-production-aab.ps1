param(
    [string]$DartDefineFile = ".env.production",
    [string]$FlutterPath = ".fvm\flutter_sdk\bin\flutter.bat",
    [string]$OutputDirectory = "release",
    [string]$BundletoolPath = ".artifacts/tools/bundletool-all-1.18.3.jar",
    [switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"

function Assert-PathExists {
    param([string]$Path, [string]$Hint)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing required file: $Path`nHint: $Hint"
    }
}

function Get-DartDefines {
    param([string]$Path)
    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith("#")) { continue }
        if ($trimmed -notmatch "^([A-Za-z_][A-Za-z0-9_]*)=(.*)$") {
            throw "Invalid dart-define entry in $Path. Use KEY=value format."
        }
        $values[$Matches[1]] = $Matches[2]
    }
    return $values
}

function Assert-ConfiguredValue {
    param([string]$Name, [string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Missing required production dart-define: $Name"
    }
    $normalized = $Value.Trim().ToLowerInvariant()
    if ($normalized.StartsWith("replace-with") -or $normalized.Contains("your-") -or
        $normalized.Contains("placeholder") -or $normalized.Contains("example")) {
        throw "Production dart-define is a placeholder: $Name"
    }
}

Assert-PathExists -Path $BundletoolPath -Hint "Download the official pinned bundletool (see docs/AAB_RELEASE_RUNBOOK.md)."
Assert-PathExists -Path $FlutterPath -Hint "Use the repository's pinned Flutter SDK."
Assert-PathExists -Path $DartDefineFile -Hint "Create ignored .env.production with production Supabase values."
Assert-PathExists -Path "android\key.properties" -Hint "Configure the release upload keystore."

$dartDefines = Get-DartDefines -Path $DartDefineFile
if ($dartDefines["APP_ENV"] -ne "production") {
    throw "APP_ENV in $DartDefineFile must be production."
}
Assert-ConfiguredValue -Name "SUPABASE_URL_PRODUCTION" -Value $dartDefines["SUPABASE_URL_PRODUCTION"]
Assert-ConfiguredValue -Name "SUPABASE_ANON_KEY_PRODUCTION" -Value $dartDefines["SUPABASE_ANON_KEY_PRODUCTION"]
if (-not $dartDefines["SUPABASE_URL_PRODUCTION"].Trim().StartsWith("https://")) {
    throw "SUPABASE_URL_PRODUCTION must use https://."
}

$pubspec = Get-Content -LiteralPath "pubspec.yaml" -Raw
if ($pubspec -notmatch "(?m)^version:\s*([^\s+]+)\+(\d+)\s*$") {
    throw "pubspec.yaml must contain version: <versionName>+<versionCode>."
}
$versionName = $Matches[1]
$versionCode = [int]$Matches[2]

$highestReleasedCode = -1
if (Test-Path -LiteralPath $OutputDirectory) {
    Get-ChildItem -LiteralPath $OutputDirectory -File -Filter "recipe-scout-v*.aab" | ForEach-Object {
        if ($_.Name -match "^recipe-scout-v(\d+)\.aab$") {
            $highestReleasedCode = [Math]::Max($highestReleasedCode, [int]$Matches[1])
        }
    }
}
if ($versionCode -le $highestReleasedCode) {
    throw "versionCode $versionCode is not newer than the latest release artifact v$highestReleasedCode. Increment pubspec.yaml first."
}

$targetAab = Join-Path $OutputDirectory "recipe-scout-v$versionCode.aab"
if (Test-Path -LiteralPath $targetAab) {
    throw "Release target already exists: $targetAab. Refusing to overwrite it."
}

Write-Host "Validated production runtime defines, release signing configuration, and version $versionName+$versionCode."
if ($ValidateOnly.IsPresent) {
    Write-Host "Validation completed; no AAB was built."
    exit 0
}

Write-Host "Running release quality gates (format check, analyze, and tests)..."
& git diff --check
if ($LASTEXITCODE -ne 0) {
    throw "git diff --check failed. Fix whitespace errors before creating a release."
}
& $FlutterPath analyze
if ($LASTEXITCODE -ne 0) {
    throw "flutter analyze failed. Fix analyzer errors before creating a release."
}
& $FlutterPath test
if ($LASTEXITCODE -ne 0) {
    throw "flutter test failed. Fix test failures before creating a release."
}

& $FlutterPath build appbundle --release --no-tree-shake-icons "--dart-define-from-file=$DartDefineFile" "--dart-define=APP_BUILD=$versionName+$versionCode"
if ($LASTEXITCODE -ne 0) {
    throw "flutter build appbundle failed with exit code $LASTEXITCODE"
}

$builtAab = "build\app\outputs\bundle\release\app-release.aab"
Assert-PathExists -Path $builtAab -Hint "The release build did not produce an AAB."
& (Join-Path $PSScriptRoot 'verify-aab-assets.ps1') -BundlePath $builtAab
& (Join-Path $PSScriptRoot 'verify-aab-optimization.ps1') -BundlePath $builtAab
& (Join-Path $PSScriptRoot 'verify-aab-manifest.ps1') -BundlePath $builtAab -VersionCode $versionCode -VersionName $versionName -BundletoolPath $BundletoolPath

$verification = & jarsigner -verify $builtAab 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "AAB signing verification failed. $verification"
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
Copy-Item -LiteralPath $builtAab -Destination $targetAab
# Windows PowerShell 5 normally provides Get-FileHash, but some restricted
# release shells do not expose it.  Use the .NET implementation so the
# release record is still produced on both hosts.
$sha256 = [System.Security.Cryptography.SHA256]::Create()
try {
    $stream = [System.IO.File]::OpenRead((Resolve-Path -LiteralPath $targetAab))
    try {
        $hash = ([System.BitConverter]::ToString($sha256.ComputeHash($stream))).Replace('-', '')
    }
    finally {
        $stream.Dispose()
    }
}
finally {
    $sha256.Dispose()
}
$provenance = [ordered]@{
    packageId = "com.kyoutube.app"
    versionName = $versionName
    versionCode = $versionCode
    appEnv = "production"
    artifact = (Split-Path -Leaf $targetAab)
    sha256 = $hash
    verifiedAtUtc = [DateTime]::UtcNow.ToString("o")
}
$provenance | ConvertTo-Json | Set-Content -LiteralPath "$targetAab.provenance.json" -Encoding utf8
Write-Host "Created: $targetAab"
Write-Host "Verified: package manifest version $versionName+$versionCode; SHA-256 $hash"
Write-Host "Created release provenance: $targetAab.provenance.json"
