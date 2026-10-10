param(
    [Parameter(Mandatory = $true)][string]$ExpectedCommit,
    [string]$DartDefineFile = '.env.production',
    [switch]$ValidateOnly
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $projectRoot
. (Join-Path $projectRoot 'tools/dev/flutter-toolchain.ps1')
$flutter = Get-ProjectFlutter -ProjectRoot $projectRoot
$pythonExe = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
if (-not (Test-Path -LiteralPath $pythonExe)) { $pythonExe = (Get-Command python -ErrorAction Stop).Source }
& $pythonExe tools/release/web_release_guard.py source --expected-commit $ExpectedCommit
if ($LASTEXITCODE -ne 0) { throw 'Source verification failed.' }
& $pythonExe tools/release/verify_web_release.py --defines $DartDefineFile --preflight
if ($LASTEXITCODE -ne 0) { throw 'Production web input verification failed.' }
if ($ValidateOnly) { exit 0 }
& powershell -ExecutionPolicy Bypass -File tools/dev/verify.ps1
if ($LASTEXITCODE -ne 0) { throw 'Quality checks failed; release blocked.' }
& $pythonExe tools/release/web_release_guard.py record-quality --expected-commit $ExpectedCommit
if ($LASTEXITCODE -ne 0) { throw 'Quality receipt failed.' }
$version = [regex]::Match((Get-Content -LiteralPath 'pubspec.yaml' -Raw), '(?m)^version:\s*(\S+)').Groups[1].Value
if (-not $version) { throw 'App version is missing.' }
$webBuild = $version + '-web-' + [DateTime]::UtcNow.ToString('yyyyMMdd')
& $flutter build web --release --csp --no-source-maps --no-wasm-dry-run --no-web-resources-cdn --output=build/web-production "--dart-define-from-file=$DartDefineFile" --dart-define=APP_ENV=production "--dart-define=APP_BUILD=$webBuild" 2>&1 | ForEach-Object {
    ([string]$_) -replace '-D(\w*(?:KEY|TOKEN|SECRET|PASSWORD)\w*)=\S+', '-D$1=[redacted]'
}
if ($LASTEXITCODE -ne 0) { throw 'Production web build failed.' }
& $pythonExe tools/release/verify_web_release.py --defines $DartDefineFile
if ($LASTEXITCODE -ne 0) { throw 'Production web output verification failed.' }

& $pythonExe tools/release/web_release_guard.py seal --expected-commit $ExpectedCommit
if ($LASTEXITCODE -ne 0) { throw 'Web sealing failed.' }
