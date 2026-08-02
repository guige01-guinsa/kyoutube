<#
.SYNOPSIS
    GitHub Secrets를 한 번에 등록하는 스크립트입니다.
    이 스크립트를 실행하면 출시 빌드에 필요한 모든 설정이 자동으로 완료됩니다.

.PREREQUISITES
    - GitHub CLI (gh) 설치 필요: https://cli.github.com
    - gh auth login 으로 로그인 완료 상태

.USAGE
    PowerShell을 관리자 권한으로 열고 프로젝트 루트에서 실행:
    .\tools\setup\setup-github-secrets.ps1
#>

$ErrorActionPreference = "Stop"

# ──────────────────────────────────────────────────────────────────────────────
# 0. 사전 검사
# ──────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "  kyoutube GitHub Secrets 자동 설정 스크립트" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""

# gh CLI 설치 확인
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "❌ GitHub CLI(gh)가 설치되어 있지 않습니다." -ForegroundColor Red
    Write-Host "   다음 주소에서 설치 후 다시 실행하세요: https://cli.github.com" -ForegroundColor Yellow
    exit 1
}

# gh 로그인 확인
$authStatus = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ GitHub CLI에 로그인되어 있지 않습니다." -ForegroundColor Red
    Write-Host "   다음 명령을 실행한 후 다시 시도하세요: gh auth login" -ForegroundColor Yellow
    exit 1
}

Write-Host "✅ GitHub CLI 확인 완료" -ForegroundColor Green

# .env 파일 확인
$envFile = Join-Path $PSScriptRoot "..\..\\.env"
if (-not (Test-Path $envFile)) {
    Write-Host "❌ .env 파일을 찾을 수 없습니다: $envFile" -ForegroundColor Red
    Write-Host "   프로젝트 루트에 .env 파일이 있는지 확인하세요." -ForegroundColor Yellow
    exit 1
}
Write-Host "✅ .env 파일 확인 완료" -ForegroundColor Green

# google-services.json 확인
$googleServicesFile = Join-Path $PSScriptRoot "..\..\android\app\google-services.json"
if (-not (Test-Path $googleServicesFile)) {
    Write-Host "❌ google-services.json을 찾을 수 없습니다: $googleServicesFile" -ForegroundColor Red
    Write-Host "   Firebase Console에서 다운로드 후 android/app/ 폴더에 저장하세요." -ForegroundColor Yellow
    exit 1
}
Write-Host "✅ google-services.json 확인 완료" -ForegroundColor Green

# ──────────────────────────────────────────────────────────────────────────────
# 1. .env 파일에서 값 읽기
# ──────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "📖 .env 파일에서 값을 읽는 중..." -ForegroundColor Cyan

$envVars = @{}
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
        $envVars[$matches[1].Trim()] = $matches[2].Trim()
    }
}

$supabaseUrl = $envVars["SUPABASE_URL_PRODUCTION"]
$supabaseAnonKey = $envVars["SUPABASE_ANON_KEY_PRODUCTION"]

if ([string]::IsNullOrWhiteSpace($supabaseUrl) -or [string]::IsNullOrWhiteSpace($supabaseAnonKey)) {
    Write-Host "❌ .env 파일에서 SUPABASE_URL_PRODUCTION 또는 SUPABASE_ANON_KEY_PRODUCTION 값을 찾을 수 없습니다." -ForegroundColor Red
    Write-Host "   .env 파일에 두 값이 올바르게 입력되어 있는지 확인하세요." -ForegroundColor Yellow
    exit 1
}
Write-Host "✅ Supabase 설정값 확인 완료" -ForegroundColor Green

# Supabase project ref 추출 (URL에서 자동 파싱)
# 예: https://abcdefgh.supabase.co → abcdefgh
$supabaseRef = ""
if ($supabaseUrl -match "https://([^.]+)\.supabase\.co") {
    $supabaseRef = $matches[1]
    Write-Host "✅ Supabase Project Ref: $supabaseRef" -ForegroundColor Green
} else {
    Write-Host "⚠️  Supabase URL에서 Project Ref를 자동 파싱할 수 없습니다." -ForegroundColor Yellow
    Write-Host "   PUBLIC_RECIPE_SYNC_FUNCTION_URL은 수동으로 입력합니다." -ForegroundColor Yellow
}

$publicRecipeSyncFunctionUrl = if ($supabaseRef) {
    "https://$supabaseRef.supabase.co/functions/v1/public_recipe_sync"
} else {
    Read-Host "PUBLIC_RECIPE_SYNC_FUNCTION_URL을 직접 입력하세요"
}

# ──────────────────────────────────────────────────────────────────────────────
# 2. 미리 생성된 값들 (스크립트에 내장)
# ──────────────────────────────────────────────────────────────────────────────
$keystoreBase64 = "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"

$keyProperties = @"
storePassword=2TOK4UwwWur807PwB40hinNtWlvyX
keyPassword=2TOK4UwwWur807PwB40hinNtWlvyX
keyAlias=upload
storeFile=../upload-keystore.jks
"@

$workerSecret = "cMjwI2bEcpAl4diyNTj210eVLdr01DPKOnfuSNQm"

# google-services.json 파일 내용 읽기
$googleServicesJson = Get-Content $googleServicesFile -Raw

# ──────────────────────────────────────────────────────────────────────────────
# 3. GitHub Secrets 일괄 등록
# ──────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "🔐 GitHub Secrets를 등록하는 중..." -ForegroundColor Cyan
Write-Host ""

$repo = "guige01-guinsa/kyoutube"

$secrets = @(
    @{ Name = "SUPABASE_URL_PRODUCTION";             Value = $supabaseUrl },
    @{ Name = "SUPABASE_ANON_KEY_PRODUCTION";        Value = $supabaseAnonKey },
    @{ Name = "ANDROID_UPLOAD_KEYSTORE_BASE64";      Value = $keystoreBase64 },
    @{ Name = "ANDROID_KEY_PROPERTIES";              Value = $keyProperties },
    @{ Name = "ANDROID_GOOGLE_SERVICES_JSON";        Value = $googleServicesJson },
    @{ Name = "PUBLIC_RECIPE_SYNC_WORKER_SECRET";    Value = $workerSecret },
    @{ Name = "PUBLIC_RECIPE_SYNC_FUNCTION_URL";     Value = $publicRecipeSyncFunctionUrl }
)

$successCount = 0
foreach ($secret in $secrets) {
    Write-Host "  → $($secret.Name) 등록 중..." -NoNewline
    $secret.Value | gh secret set $secret.Name --repo $repo 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host " ✅" -ForegroundColor Green
        $successCount++
    } else {
        Write-Host " ❌ 실패" -ForegroundColor Red
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# 4. 결과 출력
# ──────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
if ($successCount -eq $secrets.Count) {
    Write-Host "  🎉 완료! $successCount/$($secrets.Count) 개의 Secret이 등록되었습니다." -ForegroundColor Green
    Write-Host ""
    Write-Host "  다음 단계:" -ForegroundColor White
    Write-Host "  1. 아래 URL을 열어 워크플로우를 실행하세요:" -ForegroundColor White
    Write-Host "     https://github.com/$repo/actions/workflows/internal-track-release-guard.yml" -ForegroundColor Yellow
    Write-Host "  2. 'Run workflow' 버튼 클릭" -ForegroundColor White
    Write-Host "  3. 빌드 완료 후 Artifacts에서 .aab 파일 다운로드" -ForegroundColor White
} else {
    Write-Host "  ⚠️  $successCount/$($secrets.Count) 개 등록됨. 실패한 항목을 확인하세요." -ForegroundColor Yellow
}
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""
