param(
    [Parameter(Mandatory = $false)]
    [switch]$LocalVerification,

    [Parameter(Mandatory = $false)]
    [string]$FlutterPath = "C:\Users\ADMIN\tools\flutter\bin\flutter.bat",

    [Parameter(Mandatory = $false)]
    [string]$SupabaseUrlProduction,

    [Parameter(Mandatory = $false)]
    [string]$SupabaseAnonKeyProduction,

    [Parameter(Mandatory = $false)]
    [string]$PublicRecipeSyncFunctionUrl,

    [Parameter(Mandatory = $false)]
    [string]$PublicRecipeSyncWorkerSecret,

    [Parameter(Mandatory = $false)]
    [int]$PublicRecipeSyncSmokeSize = 1,

    [Parameter(Mandatory = $false)]
    [switch]$SkipPublicRecipeSyncSmoke
)

$ErrorActionPreference = "Stop"

function Get-IsCiEnvironment {
    $signals = @(
        $env:CI,
        $env:GITHUB_ACTIONS,
        $env:TF_BUILD,
        $env:BUILD_BUILDID,
        $env:BUILD_ID,
        $env:TEAMCITY_VERSION,
        $env:BITBUCKET_BUILD_NUMBER,
        $env:BUILDKITE,
        $env:JENKINS_URL
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    return $signals.Count -gt 0
}

function Assert-RequiredValue {
    param(
        [string]$Name,
        [string]$Value,
        [string]$Hint
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Missing required value: $Name`nHint: $Hint"
    }
}

function Assert-PathExists {
    param(
        [string]$Path,
        [string]$Hint
    )

    if (-not (Test-Path $Path)) {
        throw "Missing required file: $Path`nHint: $Hint"
    }
}

function Invoke-HttpPostJson {
    param(
        [string]$Uri,
        [hashtable]$Headers = @{},
        [string]$Body = "{}"
    )

    $client = [System.Net.Http.HttpClient]::new()
    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, $Uri)
    $response = $null

    try {
        $request.Content = [System.Net.Http.StringContent]::new(
            $Body,
            [System.Text.Encoding]::UTF8,
            "application/json"
        )

        foreach ($name in $Headers.Keys) {
            [void]$request.Headers.TryAddWithoutValidation($name, [string]$Headers[$name])
        }

        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()

        return @{
            StatusCode = [int]$response.StatusCode
            Body = $content
        }
    }
    finally {
        if ($null -ne $response) {
            $response.Dispose()
        }

        $request.Dispose()
        $client.Dispose()
    }
}

function Invoke-PublicRecipeSyncSmoke {
    param(
        [string]$FunctionUrl,
        [string]$WorkerSecret,
        [int]$Size
    )

    if ($Size -lt 1 -or $Size -gt 200) {
        throw "PublicRecipeSyncSmokeSize must be between 1 and 200."
    }

    $payload = "{`"size`":$Size}"
    $expectedAuthFailureCode = 401

    Write-Host " - Probe 1/3: request without x-worker-secret should be rejected..."
    $missingHeaderResponse = Invoke-HttpPostJson -Uri $FunctionUrl -Body $payload
    if ($missingHeaderResponse.StatusCode -ne $expectedAuthFailureCode) {
        throw "public_recipe_sync unauthorized check failed (missing secret). Expected $expectedAuthFailureCode, got $($missingHeaderResponse.StatusCode). Body: $($missingHeaderResponse.Body)"
    }

    Write-Host " - Probe 2/3: request with invalid x-worker-secret should be rejected..."
    $invalidHeaderResponse = Invoke-HttpPostJson -Uri $FunctionUrl -Headers @{ "x-worker-secret" = "invalid-secret" } -Body $payload
    if ($invalidHeaderResponse.StatusCode -ne $expectedAuthFailureCode) {
        throw "public_recipe_sync unauthorized check failed (invalid secret). Expected $expectedAuthFailureCode, got $($invalidHeaderResponse.StatusCode). Body: $($invalidHeaderResponse.Body)"
    }

    Write-Host " - Probe 3/3: request with valid x-worker-secret should succeed..."
    $validHeaderResponse = Invoke-HttpPostJson -Uri $FunctionUrl -Headers @{ "x-worker-secret" = $WorkerSecret } -Body $payload
    if ($validHeaderResponse.StatusCode -lt 200 -or $validHeaderResponse.StatusCode -ge 300) {
        throw "public_recipe_sync authorized check failed. Expected 2xx, got $($validHeaderResponse.StatusCode). Body: $($validHeaderResponse.Body)"
    }

    $json = $null
    try {
        $json = $validHeaderResponse.Body | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "public_recipe_sync success response is not valid JSON. Body: $($validHeaderResponse.Body)"
    }

    if ($null -eq $json -or $json.status -ne "ok") {
        throw "public_recipe_sync success response does not contain status=ok. Body: $($validHeaderResponse.Body)"
    }
}

$isCi = Get-IsCiEnvironment

if ($isCi -and $LocalVerification.IsPresent) {
    throw "LocalVerification is not allowed in CI. Remove -LocalVerification and use strict release signing."
}

Assert-RequiredValue -Name "SupabaseUrlProduction" -Value $SupabaseUrlProduction -Hint "Pass -SupabaseUrlProduction https://<your-project-ref>.supabase.co"
Assert-RequiredValue -Name "SupabaseAnonKeyProduction" -Value $SupabaseAnonKeyProduction -Hint "Pass -SupabaseAnonKeyProduction <YOUR_PRODUCTION_ANON_KEY>"

if (-not $SkipPublicRecipeSyncSmoke.IsPresent) {
    Assert-RequiredValue -Name "PublicRecipeSyncFunctionUrl" -Value $PublicRecipeSyncFunctionUrl -Hint "Pass -PublicRecipeSyncFunctionUrl https://<project-ref>.supabase.co/functions/v1/public_recipe_sync"
    Assert-RequiredValue -Name "PublicRecipeSyncWorkerSecret" -Value $PublicRecipeSyncWorkerSecret -Hint "Pass -PublicRecipeSyncWorkerSecret <PUBLIC_RECIPE_SYNC_WORKER_SECRET>"
}

Write-Host "[1/6] Checking Flutter SDK path..."
Assert-PathExists -Path $FlutterPath -Hint "Set -FlutterPath to your flutter.bat location."

Write-Host "[2/6] Checking Android release signing files..."
Assert-PathExists -Path "android/key.properties" -Hint "Copy android/key.properties.example to android/key.properties and fill real values."

# Validate key.properties content basics.
$keyProps = Get-Content "android/key.properties" -Raw
foreach ($field in @("storeFile", "storePassword", "keyAlias", "keyPassword")) {
    if ($keyProps -notmatch "(?m)^\s*$field\s*=") {
        throw "android/key.properties is missing '$field'."
    }
}

if ($keyProps -match "replace-with-keystore-password|replace-with-key-password") {
    throw "android/key.properties still contains placeholder passwords. Replace them with real secret values."
}

# Resolve storeFile path from key.properties.
$storeFileLine = ($keyProps -split "`r?`n") | Where-Object { $_ -match "^\s*storeFile\s*=" } | Select-Object -First 1
$storeFileValue = ($storeFileLine -split "=", 2)[1].Trim()
$keystoreFullPath = if ([System.IO.Path]::IsPathRooted($storeFileValue)) {
    $storeFileValue
} else {
    # Match Gradle file() behavior in app module where storeFile is typically relative to android/app.
    Join-Path "android/app" $storeFileValue
}

Assert-PathExists -Path $keystoreFullPath -Hint "Place the upload keystore at the storeFile path in android/key.properties."

Write-Host "[3/6] Checking Firebase Android config..."
Assert-PathExists -Path "android/app/google-services.json" -Hint "Download from Firebase Console for package name and place under android/app/."

Write-Host "[4/6] Building signed release appbundle..."
$buildArgs = @("build", "appbundle")

if ($LocalVerification.IsPresent) {
    $buildArgs += "-PallowDebugSigningForRelease=true"
    Write-Warning "LocalVerification enabled. This should NOT be used for Play submission."
}

$buildArgs += "--dart-define=SUPABASE_URL_PRODUCTION=$SupabaseUrlProduction"
$buildArgs += "--dart-define=SUPABASE_ANON_KEY_PRODUCTION=$SupabaseAnonKeyProduction"

$buildArgs += "--dart-define=APP_ENV=production"

& $FlutterPath @buildArgs
if ($LASTEXITCODE -ne 0) {
    throw "flutter build appbundle failed with exit code $LASTEXITCODE"
}

if ($SkipPublicRecipeSyncSmoke.IsPresent) {
    Write-Warning "[5/6] Skipping public_recipe_sync smoke check by request (-SkipPublicRecipeSyncSmoke)."
} else {
    Write-Host "[5/6] Running public_recipe_sync x-worker-secret smoke check..."
    Invoke-PublicRecipeSyncSmoke -FunctionUrl $PublicRecipeSyncFunctionUrl -WorkerSecret $PublicRecipeSyncWorkerSecret -Size $PublicRecipeSyncSmokeSize
}

Write-Host "[6/6] Build completed."
Write-Host "Output: build/app/outputs/bundle/release/app-release.aab"
Write-Host "Next: upload this AAB to Play Console Internal testing track."
