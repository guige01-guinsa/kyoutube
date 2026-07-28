param(
    [Parameter(Mandatory = $false)]
    [string]$EnvFile = ".env.local"
)

$ErrorActionPreference = "Stop"

function Test-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Read-KeyValueFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $values = @{}
    if (-not (Test-Path $Path)) {
        return $values
    }

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

$requiredCommands = @('flutter', 'dart', 'node', 'npm', 'adb')

$missingCommands = @()
foreach ($command in $requiredCommands) {
    if (-not (Test-Command -Name $command)) {
        $missingCommands += $command
    }
}

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$envPath = Join-Path $projectRoot $EnvFile
$envValues = Read-KeyValueFile -Path $envPath

$requiredKeys = @(
    'SUPABASE_URL_LOCAL',
    'SUPABASE_ANON_KEY_LOCAL'
)

$optionalKeys = @(
    'SUPABASE_URL_STAGING',
    'SUPABASE_ANON_KEY_STAGING',
    'SUPABASE_URL_PRODUCTION',
    'SUPABASE_ANON_KEY_PRODUCTION',
    'FOOD_API_KEY',
    'FOOD_API_BASE_URL',
    'FOOD_API_URL_TEMPLATE',
    'PUBLIC_RECIPE_SYNC_WORKER_SECRET'
)

$missingKeys = @()
foreach ($key in $requiredKeys) {
    if (-not $envValues.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($envValues[$key]) -or $envValues[$key] -match 'replace-with|your-|REPLACE_WITH') {
        $missingKeys += $key
    }
}

$missingOptionalKeys = @()
foreach ($key in $optionalKeys) {
    if (-not $envValues.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($envValues[$key]) -or $envValues[$key] -match 'replace-with|your-|REPLACE_WITH') {
        $missingOptionalKeys += $key
    }
}

Write-Host "[dev-env] Project root: $projectRoot"
Write-Host "[dev-env] Env file: $envPath"

if ($missingCommands.Count -gt 0) {
    Write-Host "[dev-env] Missing commands: $($missingCommands -join ', ')"
} else {
    Write-Host "[dev-env] Required commands: OK"
}

if ($missingKeys.Count -gt 0) {
    Write-Host "[dev-env] Missing local keys: $($missingKeys -join ', ')"
} else {
    Write-Host "[dev-env] Local keys: OK"
}

if ($missingOptionalKeys.Count -gt 0) {
    Write-Host "[dev-env] Optional keys not set yet: $($missingOptionalKeys -join ', ')"
}

if (Test-Path (Join-Path $projectRoot 'android/app/google-services.json')) {
    Write-Host "[dev-env] Android Firebase config: OK"
} else {
    Write-Host "[dev-env] Android Firebase config: missing"
}

if ($missingCommands.Count -gt 0 -or $missingKeys.Count -gt 0) {
    exit 1
}

Write-Host "[dev-env] Ready"