param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("local", "staging", "production")]
    [string]$AppEnv = "local"
)

$ErrorActionPreference = "Stop"
$targetScript = Join-Path $PSScriptRoot "tools/dev/run-local.ps1"

if (-not (Test-Path $targetScript)) {
    throw "Cannot find target script: $targetScript"
}

& $targetScript -AppEnv $AppEnv
