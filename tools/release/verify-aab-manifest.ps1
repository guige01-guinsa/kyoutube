param(
    [Parameter(Mandatory = $true)][string]$BundlePath,
    [Parameter(Mandatory = $true)][int]$VersionCode,
    [Parameter(Mandatory = $true)][string]$VersionName,
    [string]$BundletoolPath = ".artifacts/tools/bundletool-all-1.18.3.jar"
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $BundletoolPath)) {
    throw 'Install the official bundletool-all-1.18.3.jar in .artifacts/tools before release verification.'
}
# Read the packaged manifest, not a stale AGP intermediate from an unoptimized build.
foreach ($check in @(
    @{ XPath = '/manifest/@android:versionCode'; Expected = [string]$VersionCode },
    @{ XPath = '/manifest/@android:versionName'; Expected = $VersionName },
    @{ XPath = '/manifest/@package'; Expected = 'com.kyoutube.app' }
)) {
    $actual = & java -jar $BundletoolPath dump manifest "--bundle=$BundlePath" "--xpath=$($check.XPath)"
    if ($LASTEXITCODE -ne 0 -or (($actual -join "`n").Trim() -cne $check.Expected)) {
        throw "Packaged AAB manifest does not match the expected release: $($check.XPath)."
    }
}
Write-Host "Packaged AAB identity verified: com.kyoutube.app $VersionName+$VersionCode."
