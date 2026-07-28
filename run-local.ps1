param(
    [Parameter(Mandatory = $false)]
    [string]$EnvFile = ".env.local",

    [Parameter(Mandatory = $false)]
    [ValidateSet("local", "staging", "production")]
    [string]$AppEnv = "local",

    [Parameter(Mandatory = $false)]
    [string]$DeviceId
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

$targetScript = Join-Path $PSScriptRoot "tools/dev/run-local.ps1"

if (-not (Test-Path $targetScript)) {
    throw "Cannot find target script: $targetScript"
}

if ($AppEnv -eq "local") {
    Assert-DockerReady
}

if ([string]::IsNullOrWhiteSpace($DeviceId)) {
    & $targetScript -EnvFile $EnvFile -AppEnv $AppEnv
} else {
    & $targetScript -EnvFile $EnvFile -AppEnv $AppEnv -DeviceId $DeviceId
}
