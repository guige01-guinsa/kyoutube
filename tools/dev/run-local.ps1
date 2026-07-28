param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("local", "staging", "production")]
    [string]$AppEnv = "local"
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$envPath = Join-Path $projectRoot ".env.local"

if (-not (Test-Path $envPath)) {
    throw "Missing .env.local. Copy .env.local.example and fill values first."
}

Set-Location $projectRoot
$flutter = (Get-Command flutter -ErrorAction Stop).Source

$args = @(
    "run",
    "--dart-define-from-file=.env.local",
    "--dart-define=APP_ENV=$AppEnv"
)

& $flutter @args
