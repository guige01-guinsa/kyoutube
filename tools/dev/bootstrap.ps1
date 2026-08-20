param(
    [switch]$SkipPubGet
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $projectRoot
. (Join-Path $PSScriptRoot "flutter-toolchain.ps1")

function Require-Tool {
    param([string]$Name, [string]$Hint)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) { throw "Missing tool: $Name. $Hint" }
    return $command.Source
}

function Get-FirstVersionLine {
    param([string]$Executable, [string[]]$Arguments)
    $output = & $Executable @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Failed to execute $Executable $($Arguments -join ' ')." }
    return ($output | Select-Object -First 1)
}

Write-Host "[1/6] Checking project FVM Flutter toolchain..."
$flutter = Get-ProjectFlutter -ProjectRoot $projectRoot
$expectedFlutterVersion = (Get-Content .fvmrc | ConvertFrom-Json).flutter
Write-Host "FVM Flutter version matches .fvmrc: $expectedFlutterVersion"

Write-Host "[2/6] Checking JDK 17..."
$java = Require-Tool -Name "java" -Hint "Install a JDK 17 distribution and add it to PATH."
$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$javaVersionOutput = & $java -version 2>&1
$javaExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorActionPreference
if ($javaExitCode -ne 0) { throw "Failed to run java -version." }
$javaVersionText = $javaVersionOutput -join "`n"
if ($javaVersionText -notmatch '(?:version\s+"|openjdk\s+)(17)(?:[."\s]|$)') { throw "JDK 17 is required by android/app/build.gradle.kts (Java/Kotlin target 17)." }
Write-Host "JDK 17 is available."

Write-Host "[3/6] Checking Android SDK tools..."
$adb = Require-Tool -Name "adb" -Hint "Install Android SDK platform-tools and add them to PATH."
& $adb version | Select-Object -First 1 | Write-Host

Write-Host "[4/6] Checking Node.js, npm, and Supabase CLI availability..."
$node = Require-Tool -Name "node" -Hint "Install Node.js LTS and add it to PATH."
$npm = Require-Tool -Name "npm" -Hint "npm is included with Node.js."
Write-Host "Node: $(Get-FirstVersionLine -Executable $node -Arguments @('--version'))"
Write-Host "npm: $(Get-FirstVersionLine -Executable $npm -Arguments @('--version'))"
if (Get-Command supabase -ErrorAction SilentlyContinue) { & supabase --version | Select-Object -First 1 | Write-Host } else { Write-Warning "Supabase CLI is not globally available. Local commands may use npx supabase@latest." }

Write-Host "[5/6] Checking local-only files without reading values..."
if (-not (Test-Path ".env.local")) { throw "Missing .env.local. Copy .env.example or .env.local.example and provide local values." }
Write-Host "Found .env.local (contents not inspected)."
if (Test-Path "android/key.properties") { Write-Host "Found android/key.properties (contents not inspected)." } else { Write-Warning "android/key.properties is absent. This is expected for debug development; signed releases require it." }

Write-Host "[6/6] Fetching Flutter packages..."
if ($SkipPubGet) { Write-Host "Skipped flutter pub get by request." } else { & $flutter pub get }
Write-Host "Bootstrap completed. Use run-local.ps1 to launch the app."
