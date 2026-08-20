param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("local", "staging", "production")]
    [string]$AppEnv = "local"
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$envPath = Join-Path $projectRoot ".env.local"
. (Join-Path $PSScriptRoot "flutter-toolchain.ps1")

if (-not (Test-Path $envPath)) {
    throw "Missing .env.local. Copy .env.local.example and fill values first."
}

Set-Location $projectRoot
$flutter = Get-ProjectFlutter -ProjectRoot $projectRoot

$args = @(
    "run",
    "--dart-define-from-file=.env.local",
    "--dart-define=APP_ENV=$AppEnv"
)

& $flutter @args
