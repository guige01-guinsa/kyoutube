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

function Get-EnvValueByAppEnv {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Values,

        [Parameter(Mandatory = $true)]
        [string]$BaseName,

        [Parameter(Mandatory = $true)]
        [ValidateSet("local", "staging", "production")]
        [string]$AppEnv
    )

    $suffix = $AppEnv.ToUpperInvariant()
    $primaryKey = "${BaseName}_${suffix}"

    if ($Values.ContainsKey($primaryKey)) {
        $value = "$($Values[$primaryKey])".Trim()
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }

    if ($Values.ContainsKey($BaseName)) {
        $fallback = "$($Values[$BaseName])".Trim()
        if (-not [string]::IsNullOrWhiteSpace($fallback)) {
            return $fallback
        }
    }

    return ""
}

function Assert-ConfiguredValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $trimmed = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw "Missing $Name in $EnvFile"
    }

    $lower = $trimmed.ToLowerInvariant()
    if ($lower.StartsWith("replace-with") -or $lower.Contains("your-") -or $lower.Contains("example") -or $lower.Contains("placeholder")) {
        throw "$Name is using a placeholder value in $EnvFile. Fill a real value first."
    }
}

function Normalize-BoolValue {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Value
    )

    $normalized = "$Value".Trim().ToLowerInvariant()
    if ($normalized -in @('1', 'true', 'yes', 'y', 'on')) {
        return 'true'
    }

    return 'false'
}

function Is-ConfiguredValue {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Value
    )

    $trimmed = "$Value".Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return $false
    }

    $lower = $trimmed.ToLowerInvariant()
    if ($lower.StartsWith("replace-with") -or $lower.Contains("your-") -or $lower.Contains("example") -or $lower.Contains("placeholder")) {
        return $false
    }

    return $true
}

function Ensure-AdbReverseForLocal {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Port
    )

    if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
        Write-Host "[dev-run] adb not found. Skipping reverse tcp:$Port."
        return
    }

    $deviceList = & adb devices 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $deviceList) {
        Write-Host "[dev-run] adb devices check failed. Skipping reverse tcp:$Port."
        return
    }

    $hasOnlineDevice = $false
    foreach ($line in $deviceList) {
        if ($line -match "\sdevice$") {
            $hasOnlineDevice = $true
            break
        }
    }

    if (-not $hasOnlineDevice) {
        Write-Host "[dev-run] No online Android device detected. Skipping reverse tcp:$Port."
        return
    }

    & adb reverse "tcp:$Port" "tcp:$Port" *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[dev-run] adb reverse tcp:$Port tcp:$Port configured."
        return
    }

    Write-Host "[dev-run] Failed to set adb reverse tcp:$Port. Check USB/debug connection."
}

function Get-LocalYoutubeServeProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $scriptPath = (Join-Path $ProjectRoot 'tools/dev/supabase-native.ps1').ToLowerInvariant()
    $scriptName = 'supabase-native.ps1'
    $servePattern = 'functions serve youtube_search'

    return Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $name = ($_.Name ?? '').ToLowerInvariant()
            if ($name -ne 'pwsh.exe' -and $name -ne 'powershell.exe') {
                return $false
            }

            $cmd = ($_.CommandLine ?? '')
            if ([string]::IsNullOrWhiteSpace($cmd)) {
                return $false
            }

            $cmdLower = $cmd.ToLowerInvariant()
            $targetsSupabaseNative =
                $cmdLower.Contains($scriptPath) -or
                $cmdLower.Contains($scriptName)

            return $targetsSupabaseNative -and $cmdLower.Contains($servePattern)
        }
}

function Ensure-LocalYoutubeFunctionServe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $existing = Get-LocalYoutubeServeProcess -ProjectRoot $ProjectRoot
    if ($existing) {
        Write-Host "[dev-run] youtube_search serve already running. pid=$($existing[0].ProcessId)"
        return
    }

    $supabaseScript = Join-Path $ProjectRoot 'tools/dev/supabase-native.ps1'
    if (-not (Test-Path $supabaseScript)) {
        Write-Host "[dev-run] Cannot auto-start youtube_search serve. Missing $supabaseScript"
        return
    }

    $functionEnvPath = Join-Path $ProjectRoot 'supabase/functions/.env'
    if (-not (Test-Path $functionEnvPath)) {
        Write-Host "[dev-run] Cannot auto-start youtube_search serve. Missing $functionEnvPath"
        return
    }

    $logDir = Join-Path $ProjectRoot 'build/dev-logs'
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    $stdoutLog = Join-Path $logDir 'youtube_search-serve.out.log'
    $stderrLog = Join-Path $logDir 'youtube_search-serve.err.log'

    $serveArgs = @(
        '-NoProfile',
        '-File',
        $supabaseScript,
        'functions',
        'serve',
        'youtube_search',
        '--env-file',
        $functionEnvPath
    )

    $process = Start-Process -FilePath 'pwsh' -ArgumentList $serveArgs -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog
    Write-Host "[dev-run] Started youtube_search serve in background. pid=$($process.Id)"
    Write-Host "[dev-run] Serve logs: $stdoutLog"
}

function Test-LocalFunctionEndpoint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$ApiKey
    )

    try {
        $response = Invoke-WebRequest -Uri $Url -Headers @{ apikey = $ApiKey } -Method Get -TimeoutSec 10 -SkipHttpErrorCheck
        return [int]$response.StatusCode
    } catch {
        return -1
    }
}

function Test-LocalSearchEndpointsHealthy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SupabaseUrl,

        [Parameter(Mandatory = $true)]
        [string]$SupabaseAnonKey
    )

    $youtubeUrl = "$SupabaseUrl/functions/v1/youtube_search?q=%EB%91%90%EB%B6%80&limit=1"
    $publicUrl = "$SupabaseUrl/functions/v1/recipe_api?type=public&limit=1&offset=0&search=%EB%91%90%EB%B6%80"

    $youtubeStatus = Test-LocalFunctionEndpoint -Url $youtubeUrl -ApiKey $SupabaseAnonKey
    $publicStatus = Test-LocalFunctionEndpoint -Url $publicUrl -ApiKey $SupabaseAnonKey

    $youtubeHealthy = ($youtubeStatus -eq 200 -or $youtubeStatus -eq 429)
    $publicHealthy = ($publicStatus -eq 200)

    return @{
        Healthy = ($youtubeHealthy -and $publicHealthy)
        YoutubeStatus = $youtubeStatus
        PublicStatus = $publicStatus
    }
}

function Restart-LocalYoutubeFunctionServe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $existing = Get-LocalYoutubeServeProcess -ProjectRoot $ProjectRoot
    foreach ($proc in $existing) {
        try {
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
            Write-Host "[dev-run] Stopped stale youtube_search serve. pid=$($proc.ProcessId)"
        } catch {
            Write-Host "[dev-run] Failed to stop serve pid=$($proc.ProcessId): $($_.Exception.Message)"
        }
    }

    Ensure-LocalYoutubeFunctionServe -ProjectRoot $ProjectRoot
}

function Ensure-LocalSearchBackendHealthy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,

        [Parameter(Mandatory = $true)]
        [string]$SupabaseUrl,

        [Parameter(Mandatory = $true)]
        [string]$SupabaseAnonKey
    )

    $probe = Test-LocalSearchEndpointsHealthy -SupabaseUrl $SupabaseUrl -SupabaseAnonKey $SupabaseAnonKey
    if ($probe.Healthy) {
        Write-Host "[dev-run] Local search backend healthy. youtube=$($probe.YoutubeStatus), public=$($probe.PublicStatus)"
        return
    }

    Write-Host "[dev-run] Local search backend unhealthy. youtube=$($probe.YoutubeStatus), public=$($probe.PublicStatus). Restarting serve..."
    Restart-LocalYoutubeFunctionServe -ProjectRoot $ProjectRoot

    for ($attempt = 1; $attempt -le 6; $attempt++) {
        $retryProbe = Test-LocalSearchEndpointsHealthy -SupabaseUrl $SupabaseUrl -SupabaseAnonKey $SupabaseAnonKey
        if ($retryProbe.Healthy) {
            Write-Host "[dev-run] Local search backend recovered on probe attempt $attempt."
            return
        }

        if ($attempt -eq 6) {
            Write-Host "[dev-run] Backend still unhealthy after restart. youtube=$($retryProbe.YoutubeStatus), public=$($retryProbe.PublicStatus)"
        }
    }
}

function Resolve-FlutterExecutable {
    $cmd = Get-Command flutter -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $fallback = 'C:\Users\ADMIN\tools\flutter\bin\flutter.bat'
    if (Test-Path $fallback) {
        return $fallback
    }

    throw 'flutter executable not found. Install Flutter or add it to PATH.'
}

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$envPath = Join-Path $projectRoot $EnvFile

if (-not (Test-Path $envPath)) {
    throw "Missing $EnvFile. Copy .env.example to .env.local and fill in the values first."
}

$values = Read-KeyValueFile -Path $envPath

$supabaseUrl = Get-EnvValueByAppEnv -Values $values -BaseName 'SUPABASE_URL' -AppEnv $AppEnv
$supabaseAnonKey = Get-EnvValueByAppEnv -Values $values -BaseName 'SUPABASE_ANON_KEY' -AppEnv $AppEnv
$googleOAuthEnabledRaw = Get-EnvValueByAppEnv -Values $values -BaseName 'GOOGLE_OAUTH_ENABLED' -AppEnv $AppEnv
$kakaoOAuthEnabledRaw = Get-EnvValueByAppEnv -Values $values -BaseName 'KAKAO_OAUTH_ENABLED' -AppEnv $AppEnv
$googleOAuthClientIdRaw = Get-EnvValueByAppEnv -Values $values -BaseName 'SUPABASE_AUTH_GOOGLE_CLIENT_ID' -AppEnv $AppEnv
$googleOAuthSecretRaw = Get-EnvValueByAppEnv -Values $values -BaseName 'SUPABASE_AUTH_GOOGLE_SECRET' -AppEnv $AppEnv
$googleOAuthEnabled = Normalize-BoolValue -Value $googleOAuthEnabledRaw
$kakaoOAuthEnabled = Normalize-BoolValue -Value $kakaoOAuthEnabledRaw
$googleOAuthConfigured = 'true'

if ($AppEnv -eq 'local' -and $googleOAuthEnabled -eq 'true') {
    $hasClientId = Is-ConfiguredValue -Value $googleOAuthClientIdRaw
    $hasSecret = Is-ConfiguredValue -Value $googleOAuthSecretRaw
    if (-not ($hasClientId -and $hasSecret)) {
        $googleOAuthConfigured = 'false'
        Write-Host '[dev-run] Google OAuth local config incomplete. Set SUPABASE_AUTH_GOOGLE_CLIENT_ID_LOCAL and SUPABASE_AUTH_GOOGLE_SECRET_LOCAL.'
    }
}

$envUpper = $AppEnv.ToUpperInvariant()
Assert-ConfiguredValue -Name "SUPABASE_URL_$envUpper" -Value $supabaseUrl
Assert-ConfiguredValue -Name "SUPABASE_ANON_KEY_$envUpper" -Value $supabaseAnonKey

Write-Host "[dev-run] Using APP_ENV=$AppEnv"
Write-Host "[dev-run] Using Supabase URL=$supabaseUrl"

if ($AppEnv -eq "local") {
    Ensure-AdbReverseForLocal -Port 54321
    Ensure-LocalYoutubeFunctionServe -ProjectRoot $projectRoot
    Ensure-LocalSearchBackendHealthy -ProjectRoot $projectRoot -SupabaseUrl $supabaseUrl -SupabaseAnonKey $supabaseAnonKey
}

Set-Location $projectRoot
$flutterArgs = @(
    "run",
    "--no-dds",
    "--dart-define=APP_ENV=$AppEnv",
    "--dart-define=SUPABASE_URL=$supabaseUrl",
    "--dart-define=SUPABASE_ANON_KEY=$supabaseAnonKey",
    "--dart-define=GOOGLE_OAUTH_ENABLED=$googleOAuthEnabled",
    "--dart-define=GOOGLE_OAUTH_CONFIGURED=$googleOAuthConfigured",
    "--dart-define=KAKAO_OAUTH_ENABLED=$kakaoOAuthEnabled"
)

if (-not [string]::IsNullOrWhiteSpace($DeviceId)) {
    $flutterArgs += @("-d", $DeviceId)
}

$flutter = Resolve-FlutterExecutable
& $flutter @flutterArgs