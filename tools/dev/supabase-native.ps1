param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

$ErrorActionPreference = "Stop"

function Assert-DockerReady {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "Docker CLI가 PATH에 없습니다. Docker Desktop 설치/실행 후 다시 시도해 주세요."
    }

    docker version *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker daemon 연결 실패입니다. Docker Desktop을 먼저 실행한 뒤 다시 시도해 주세요."
    }
}

function Resolve-SupabaseNativePath {
    $preferred = "C:\Users\ADMIN\tools\supabase\supabase.exe"
    if (Test-Path $preferred) {
        return $preferred
    }

    $cmd = Get-Command supabase -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "supabase CLI를 찾을 수 없습니다. native supabase.exe를 설치해 주세요."
    }

    $source = "$($cmd.Source)"
    if ($source -like "*supabase-docker*" -or $source -like "*.cmd") {
        throw "현재 supabase 명령은 docker-wrapper($source)입니다. native supabase.exe 경로를 설정해 주세요."
    }

    return $source
}

function Read-KeyValueFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $values = @{}
    foreach ($line in Get-Content $Path) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) {
            continue
        }

        $parts = $trimmed.Split('=', 2)
        if ($parts.Count -ne 2) {
            continue
        }

        $values[$parts[0].Trim()] = $parts[1].Trim()
    }

    return $values
}

function Get-FirstNonEmptyValue {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Values,

        [Parameter(Mandatory = $true)]
        [string[]]$Keys
    )

    foreach ($key in $Keys) {
        if (-not $Values.ContainsKey($key)) {
            continue
        }

        $candidate = "$($Values[$key])".Trim()
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            return $candidate
        }
    }

    return ''
}

function Export-OptionalAuthSecretsFromEnvFile {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $envFilePath = Join-Path $ProjectRoot '.env.local'
    if (-not (Test-Path $envFilePath)) {
        return
    }

    $values = Read-KeyValueFile -Path $envFilePath
    $googleSecret = Get-FirstNonEmptyValue -Values $values -Keys @(
        'AUTH_GOOGLE_SECRET_LOCAL',
        'AUTH_GOOGLE_SECRET',
        'SUPABASE_AUTH_GOOGLE_SECRET_LOCAL',
        'SUPABASE_AUTH_GOOGLE_SECRET'
    )
    $googleClientId = Get-FirstNonEmptyValue -Values $values -Keys @(
        'AUTH_GOOGLE_CLIENT_ID_LOCAL',
        'AUTH_GOOGLE_CLIENT_ID',
        'SUPABASE_AUTH_GOOGLE_CLIENT_ID_LOCAL',
        'SUPABASE_AUTH_GOOGLE_CLIENT_ID'
    )
    $kakaoSecret = Get-FirstNonEmptyValue -Values $values -Keys @(
        'AUTH_KAKAO_SECRET_LOCAL',
        'AUTH_KAKAO_SECRET',
        'SUPABASE_AUTH_KAKAO_SECRET_LOCAL',
        'SUPABASE_AUTH_KAKAO_SECRET'
    )

    if (-not [string]::IsNullOrWhiteSpace($googleSecret)) {
        $env:AUTH_GOOGLE_SECRET = $googleSecret
    }

    if (-not [string]::IsNullOrWhiteSpace($googleClientId)) {
        $env:AUTH_GOOGLE_CLIENT_ID = $googleClientId
    }

    if (-not [string]::IsNullOrWhiteSpace($kakaoSecret)) {
        $env:AUTH_KAKAO_SECRET = $kakaoSecret
    }
}

Assert-DockerReady
$nativeSupabase = Resolve-SupabaseNativePath
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Export-OptionalAuthSecretsFromEnvFile -ProjectRoot $projectRoot

Write-Host "[supabase-native] Using: $nativeSupabase"
& $nativeSupabase @Args
