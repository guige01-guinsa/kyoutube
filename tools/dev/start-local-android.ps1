$ErrorActionPreference = 'Stop'

Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..\..'))

Write-Host "`n[1/6] Google OAuth local 환경변수 준비..." -ForegroundColor Cyan

$envLines = Get-Content .\.env.local

function Get-LocalEnvValue([string]$name) {
    $line = $envLines |
        Where-Object { $_ -match "^$name=" } |
        Select-Object -First 1

    if (-not $line) {
        return ''
    }

    return ($line -split '=', 2)[1].Trim().Trim('"').Trim("'")
}

$googleClientId = Get-LocalEnvValue 'SUPABASE_AUTH_GOOGLE_CLIENT_ID_LOCAL'
$googleSecret = Get-LocalEnvValue 'SUPABASE_AUTH_GOOGLE_SECRET_LOCAL'

if ([string]::IsNullOrWhiteSpace($googleClientId)) {
    throw 'SUPABASE_AUTH_GOOGLE_CLIENT_ID_LOCAL is missing in .env.local.'
}

if ([string]::IsNullOrWhiteSpace($googleSecret)) {
    throw 'SUPABASE_AUTH_GOOGLE_SECRET_LOCAL is missing in .env.local.'
}

$env:AUTH_GOOGLE_CLIENT_ID = $googleClientId
$env:AUTH_GOOGLE_SECRET = $googleSecret

Write-Host "Google OAuth 환경변수 준비 완료"

Write-Host "`n[2/6] Local Supabase 상태 확인..." -ForegroundColor Cyan

$edgeRuntime = docker ps --format "{{.Names}}" |
    Where-Object { $_ -eq 'supabase_edge_runtime_k-youtube' }

if (-not $edgeRuntime) {
    Write-Host "Local Supabase를 시작합니다..."
    npx.cmd supabase@latest start -x studio,logflare,imgproxy
} else {
    Write-Host "Local Supabase가 이미 실행 중입니다."
}

Write-Host "`n[3/6] Local anon key 동기화..." -ForegroundColor Cyan

$currentAnon = (& docker exec supabase_edge_runtime_k-youtube `
    printenv SUPABASE_ANON_KEY).Trim()

if ([string]::IsNullOrWhiteSpace($currentAnon)) {
    throw 'Could not read local SUPABASE_ANON_KEY.'
}

$envPath = ".\.env.local"
$lines = Get-Content $envPath

if ($lines -match '^SUPABASE_ANON_KEY_LOCAL=') {
    $lines = $lines | ForEach-Object {
        if ($_ -match '^SUPABASE_ANON_KEY_LOCAL=') {
            "SUPABASE_ANON_KEY_LOCAL=$currentAnon"
        } else {
            $_
        }
    }
} else {
    $lines += "SUPABASE_ANON_KEY_LOCAL=$currentAnon"
}

$encoding = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines(
    (Resolve-Path $envPath).Path,
    $lines,
    $encoding
)

Write-Host "Local anon key 동기화 완료"

Write-Host "`n[4/6] YouTube Edge Function serve 준비..." -ForegroundColor Cyan

Get-CimInstance Win32_Process |
    Where-Object {
        $_.CommandLine -like '*functions serve youtube_search*'
    } |
    ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force
    }

$logDir = Join-Path (Get-Location) 'build\dev-logs'
New-Item -ItemType Directory -Force $logDir | Out-Null

$helperScript = (Resolve-Path .\tools\dev\supabase-native.ps1).Path
$functionEnv = (Resolve-Path .\supabase\functions\.env).Path

Start-Process `
    -FilePath 'pwsh' `
    -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $helperScript,
        'functions',
        'serve',
        'youtube_search',
        '--env-file', $functionEnv
    ) `
    -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $logDir 'youtube_search-serve.out.log') `
    -RedirectStandardError (Join-Path $logDir 'youtube_search-serve.err.log')

Start-Sleep -Seconds 5

Write-Host "Edge Function serve 시작 완료"

Write-Host "`n[5/6] Android USB reverse 설정..." -ForegroundColor Cyan

adb reverse tcp:54321 tcp:54321

Write-Host "Android reverse 설정 완료"

Write-Host "`n[6/6] Flutter 앱 실행..." -ForegroundColor Cyan

powershell -ExecutionPolicy Bypass -File .\run-local.ps1 -AppEnv local