param(
    [Parameter(Mandatory = $false)]
    [string]$PackageName = "com.kyoutube.app",

    [Parameter(Mandatory = $false)]
    [string]$OutputFile = "docs/ops-execution-record-2026-07-27-internal-track.md"
)

$ErrorActionPreference = "Stop"

function Assert-CommandExists {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Name"
    }
}

function Get-AdbValue {
    param(
        [string]$Package,
        [string]$Pattern
    )

    $line = adb shell dumpsys package $Package | Select-String -Pattern $Pattern | Select-Object -First 1
    if ($null -eq $line) {
        return "<not-found>"
    }

    return $line.Line.Trim()
}

Assert-CommandExists -Name "adb"

$devices = adb devices | Select-String -Pattern "\tdevice$"
if ($devices.Count -eq 0) {
    throw "No connected Android device found. Connect a tester device first."
}

$versionNameLine = Get-AdbValue -Package $PackageName -Pattern "versionName="
$versionCodeLine = Get-AdbValue -Package $PackageName -Pattern "versionCode="
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss K"

if (-not (Test-Path $OutputFile)) {
    throw "Output record file not found: $OutputFile"
}

$content = Get-Content $OutputFile -Raw
$content = $content -replace "<timestamp>", $timestamp
$content = [regex]::Replace($content, "(?m)^- `versionName`:\s*.*$", "- `versionName`: $versionNameLine")
$content = [regex]::Replace($content, "(?m)^- `versionCode`:\s*.*$", "- `versionCode`: $versionCodeLine")

Set-Content -Path $OutputFile -Value $content -NoNewline

Write-Host "Captured install evidence into $OutputFile"
Write-Host "versionName => $versionNameLine"
Write-Host "versionCode => $versionCodeLine"
