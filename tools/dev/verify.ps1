$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $projectRoot
. (Join-Path $PSScriptRoot "flutter-toolchain.ps1")
$flutter = Get-ProjectFlutter -ProjectRoot $projectRoot

Write-Host "[1/3] flutter doctor -v"
& $flutter doctor -v
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "[2/3] flutter analyze"
& $flutter analyze
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "[3/3] flutter test"
& $flutter test
exit $LASTEXITCODE
