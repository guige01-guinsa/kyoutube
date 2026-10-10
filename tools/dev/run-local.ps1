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

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$envPath = Join-Path $projectRoot ".env.local"
. (Join-Path $PSScriptRoot "flutter-toolchain.ps1")

if (-not (Test-Path $envPath)) {
    throw "Missing .env.local. Create it using docs/MULTI_PC_DEVELOPMENT_SETUP_KO.md and fill local values first."
}

Set-Location $projectRoot
$flutter = Get-ProjectFlutter -ProjectRoot $projectRoot

if ($StaticWeb) {
    if ($AppEnv -ne 'local') { throw 'Static preview is local-only.' }
    $previewDir = [System.IO.Path]::GetFullPath((Join-Path $projectRoot '.artifacts/web-preview'))
    if (-not $previewDir.StartsWith($projectRoot + [System.IO.Path]::DirectorySeparatorChar)) { throw 'Invalid preview output' }
    & $flutter build web --debug --no-wasm-dry-run --no-web-resources-cdn "--target=$Target" "--output=$previewDir" --dart-define-from-file=.env.local --dart-define=APP_ENV=local 2>&1 | ForEach-Object { ([string]$_) -replace '-D(\w*(?:KEY|TOKEN|SECRET|PASSWORD)\w*)=\S+', '-D$1=[redacted]' }
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $pythonExe = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
    if (-not (Test-Path -LiteralPath $pythonExe)) { $pythonExe = (Get-Command python -ErrorAction Stop).Source }
    & $pythonExe -m http.server $WebPort --bind 127.0.0.1 --directory $previewDir
    exit $LASTEXITCODE
}

$args = @(
    "run",
    "--target=$Target",
    "--dart-define-from-file=.env.local",
    "--dart-define=APP_ENV=$AppEnv"
)

if ($Device) { $args += @('-d', $Device) }
if ($Device -in @('web-server', 'chrome', 'edge')) {
    $args += @('--web-hostname=127.0.0.1', "--web-port=$WebPort")
}

& $flutter @args

