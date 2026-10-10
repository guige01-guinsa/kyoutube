param([Parameter(Mandatory = $true)][string]$ExpectedCommit)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $projectRoot
$pythonExe = (Get-Command python -ErrorAction Stop).Source
& $pythonExe tools/release/web_release_guard.py check --expected-commit $ExpectedCommit
if ($LASTEXITCODE -ne 0) { throw 'Web release guard rejected this build.' }
$config = Get-Content firebase.web.json -Raw | ConvertFrom-Json
if ($config.hosting.site -ne 'recipe-scout-workspace' -or $config.hosting.public -ne 'build/web-production') { throw 'Unexpected hosting target.' }
& firebase deploy --only hosting --config firebase.web.json --project korea-01 --non-interactive
if ($LASTEXITCODE -ne 0) { throw 'Hosting deployment failed.' }
& $pythonExe tools/release/web_release_guard.py remote --expected-commit $ExpectedCommit
if ($LASTEXITCODE -ne 0) { throw 'Published files differ. Stop and investigate.' }
