param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("local", "staging", "production")]
    [string]$AppEnv = "local",
    [string]$Device = "",
    [int]$WebPort = 8766,
    [string]$Target = "lib/main.dart",
    [switch]$StaticWeb
)

$ErrorActionPreference = "Stop"
$targetScript = Join-Path $PSScriptRoot "tools/dev/run-local.ps1"

if (-not (Test-Path $targetScript)) {
    throw "Cannot find target script: $targetScript"
}

& $targetScript -AppEnv $AppEnv -Device $Device -WebPort $WebPort -Target $Target -StaticWeb:$StaticWeb

exit $LASTEXITCODE
