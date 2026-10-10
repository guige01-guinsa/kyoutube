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
    [string]$DartDefineFile,

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

Add-Type -AssemblyName System.Net.Http

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

function Assert-ConfiguredValue {
    param(
        [string]$Name,
        [string]$Value,
        [string]$Hint
    )

    Assert-RequiredValue -Name $Name -Value $Value -Hint $Hint

    $normalized = $Value.Trim().ToLowerInvariant()
    if ($normalized.StartsWith("replace-with") -or
        $normalized.Contains("your-") -or
        $normalized.Contains("placeholder") -or
        $normalized.Contains("example")) {
        throw "Invalid placeholder value: $Name`nHint: $Hint"
    }
}

function Assert-HttpsUrl {
    param(
        [string]$Name,
        [string]$Value
    )

    $uri = $null
    if (-not $Value.StartsWith("https://") -or
        -not [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne "https" -or
        [string]::IsNullOrWhiteSpace($uri.Host)) {
        throw "Invalid HTTPS URL: $Name"
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

function Get-DartDefineFileValues {
    param(
        [string]$Path
    )

    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) {
            continue
        }

        if ($trimmed -notmatch "^([A-Za-z_][A-Za-z0-9_]*)=(.*)$") {
            throw "Invalid dart-define entry in $Path. Use KEY=value format."
        }

        $values[$Matches[1]] = $Matches[2]
    }

    return $values
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

if (-not [string]::IsNullOrWhiteSpace($DartDefineFile)) {
    Assert-PathExists -Path $DartDefineFile -Hint "Create an ignored .env.production file with production runtime values."
    $dartDefines = Get-DartDefineFileValues -Path $DartDefineFile
    Assert-ConfiguredValue -Name "SUPABASE_URL_PRODUCTION" -Value $dartDefines["SUPABASE_URL_PRODUCTION"] -Hint "Set a real production Supabase URL in $DartDefineFile."
    Assert-ConfiguredValue -Name "SUPABASE_ANON_KEY_PRODUCTION" -Value $dartDefines["SUPABASE_ANON_KEY_PRODUCTION"] -Hint "Set a real production Supabase anon key in $DartDefineFile."
    Assert-HttpsUrl -Name "SUPABASE_URL_PRODUCTION" -Value $dartDefines["SUPABASE_URL_PRODUCTION"]
    if ($dartDefines["APP_ENV"] -ne "production") {
        throw "APP_ENV in $DartDefineFile must be production for a Play release."
    }
} else {
    Assert-ConfiguredValue -Name "SupabaseUrlProduction" -Value $SupabaseUrlProduction -Hint "Pass a real production Supabase URL."
    Assert-ConfiguredValue -Name "SupabaseAnonKeyProduction" -Value $SupabaseAnonKeyProduction -Hint "Pass a real production Supabase anon key."
    Assert-HttpsUrl -Name "SupabaseUrlProduction" -Value $SupabaseUrlProduction
}

if (-not $SkipPublicRecipeSyncSmoke.IsPresent) {
    Assert-ConfiguredValue -Name "PublicRecipeSyncFunctionUrl" -Value $PublicRecipeSyncFunctionUrl -Hint "Pass the public_recipe_sync production function URL."
    Assert-ConfiguredValue -Name "PublicRecipeSyncWorkerSecret" -Value $PublicRecipeSyncWorkerSecret -Hint "Pass a real public_recipe_sync worker secret."
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
$firebaseConfig = Get-Content "android/app/google-services.json" -Raw | ConvertFrom-Json
$firebaseClients = @($firebaseConfig.client)
$androidOAuthClients = @(
    $firebaseClients.client_info.android_client_info.package_name |
        Where-Object { $_ -eq "com.kyoutube.app" }
)
$oauthClientTypes = @(
    $firebaseClients.oauth_client.client_type |
        Where-Object { $null -ne $_ }
)

if ($androidOAuthClients.Count -eq 0) {
    throw "Firebase Android config does not contain package com.kyoutube.app. Download the correct google-services.json."
}

if (1 -notin $oauthClientTypes -or 3 -notin $oauthClientTypes) {
    throw "Firebase Android config is missing Android or Web OAuth clients required for Google Sign-In. Download it again after registering both app signing certificates."
}

Write-Host "[4/6] Building signed release appbundle..."
$buildArgs = @("build", "appbundle")

# Prevent intermittent Windows host failures from Flutter engine version git checks.
$buildArgs += "--no-version-check"

if ($LocalVerification.IsPresent) {
    $buildArgs += "-PallowDebugSigningForRelease=true"
    Write-Warning "LocalVerification enabled. This should NOT be used for Play submission."
}

if (-not [string]::IsNullOrWhiteSpace($DartDefineFile)) {
    $buildArgs += "--dart-define-from-file=$DartDefineFile"
} else {
    $buildArgs += "--dart-define=SUPABASE_URL_PRODUCTION=$SupabaseUrlProduction"
    $buildArgs += "--dart-define=SUPABASE_ANON_KEY_PRODUCTION=$SupabaseAnonKeyProduction"
    $buildArgs += "--dart-define=APP_ENV=production"
}

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
