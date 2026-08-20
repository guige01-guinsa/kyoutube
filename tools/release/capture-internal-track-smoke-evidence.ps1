param(
    [Parameter(Mandatory = $false)]
    [string]$PackageName = "com.kyoutube.kyoutube",

    [Parameter(Mandatory = $false)]
    [string]$OutputFile = "docs/ops-execution-record-2026-07-27-internal-track.md",

    [Parameter(Mandatory = $false)]
    [string]$EvidenceDir = "docs/evidence/internal-track-2026-07-27"
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

function Set-MarkdownLine {
    param(
        [string]$Text,
        [string]$Label,
        [string]$Value
    )

    $updated = [regex]::Replace(
        $Text,
        "(?m)^- $([regex]::Escape($Label)):\s*.*$",
        "- $($Label): $Value"
    )

    $plainLabel = $Label.Replace([string][char]96, "")
    if ($plainLabel -ne $Label) {
        $updated = [regex]::Replace(
            $updated,
            "(?m)^- $([regex]::Escape($plainLabel)):\s*.*$",
            "- $($plainLabel): $Value"
        )
    }

    return $updated
}

Assert-CommandExists -Name "adb"

$devices = adb devices | Select-String -Pattern "\tdevice$"
if ($devices.Count -eq 0) {
    throw "No connected Android device found. Connect a tester device first."
}

$packageCheck = adb shell pm list packages | Select-String -Pattern $PackageName
if ($null -eq $packageCheck) {
    throw "Package '$PackageName' is not installed on connected device."
}

$deviceModel = (adb shell getprop ro.product.model).Trim()
$deviceOs = (adb shell getprop ro.build.version.release).Trim()
$installer = (adb shell cmd package resolve-activity --brief $PackageName 2>$null | Out-String).Trim()
$installerPackage = (adb shell dumpsys package $PackageName | Select-String -Pattern "installerPackageName=" | Select-Object -First 1)

$versionNameLine = Get-AdbValue -Package $PackageName -Pattern "versionName="
$versionCodeLine = Get-AdbValue -Package $PackageName -Pattern "versionCode="
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss K"

if (-not (Test-Path $EvidenceDir)) {
    New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
}

$screen1Device = "/sdcard/kyoutube_install.png"
$screen2Device = "/sdcard/kyoutube_ops.png"
$screen3Device = "/sdcard/kyoutube_import.png"

$screen1Host = Join-Path $EvidenceDir "kyoutube_install.png"
$screen2Host = Join-Path $EvidenceDir "kyoutube_ops.png"
$screen3Host = Join-Path $EvidenceDir "kyoutube_import.png"

adb shell screencap -p $screen1Device | Out-Null
adb shell screencap -p $screen2Device | Out-Null
adb shell screencap -p $screen3Device | Out-Null

adb pull $screen1Device $screen1Host | Out-Null
adb pull $screen2Device $screen2Host | Out-Null
adb pull $screen3Device $screen3Host | Out-Null

$uiDumpDevice = "/sdcard/kyoutube_ui.xml"
$uiDumpHost = Join-Path $EvidenceDir "kyoutube_ui.xml"
$uiDumpHostNormalized = $uiDumpHost -replace "\\", "/"
adb shell uiautomator dump $uiDumpDevice | Out-Null
adb pull $uiDumpDevice $uiDumpHost | Out-Null

if (-not (Test-Path $OutputFile)) {
    throw "Output record file not found: $OutputFile"
}

$content = Get-Content $OutputFile -Raw
$installedFromPlay = "NO"
if ($installerPackage -and $installerPackage.Line -match "com.android.vending") {
    $installedFromPlay = "YES"
}

$fmtInstalledFromPlay = $installedFromPlay
$fmtTimestamp = $timestamp
$fmtVersionName = $versionNameLine
$fmtVersionCode = $versionCodeLine
$fmtDevice = "$deviceModel / Android $deviceOs"
$fmtScreen1 = $screen1Host
$fmtScreen2 = $screen2Host
$fmtScreen3 = $screen3Host

$content = Set-MarkdownLine -Text $content -Label "Installed from Play internal track" -Value $fmtInstalledFromPlay
$content = Set-MarkdownLine -Text $content -Label "Install timestamp (KST)" -Value $fmtTimestamp
$content = Set-MarkdownLine -Text $content -Label "versionName" -Value $fmtVersionName
$content = Set-MarkdownLine -Text $content -Label "versionCode" -Value $fmtVersionCode
$content = Set-MarkdownLine -Text $content -Label "Device model / OS" -Value $fmtDevice
$content = Set-MarkdownLine -Text $content -Label "Screenshot 1 (Play install success)" -Value $fmtScreen1
$content = Set-MarkdownLine -Text $content -Label "Screenshot 2 (ops dashboard counters)" -Value $fmtScreen2
$content = Set-MarkdownLine -Text $content -Label "Screenshot 3 (YouTube import result)" -Value $fmtScreen3

if ($content -notmatch "Installer evidence") {
    $installerLine = if ($installerPackage) { $installerPackage.Line.Trim() } else { "<not-found>" }
    $content += "`r`n`r`n## Installer evidence`r`n- installerPackageName: $installerLine`r`n- resolve-activity: $installer`r`n- UI dump: $uiDumpHostNormalized`r`n"
}

Set-Content -Path $OutputFile -Value $content -NoNewline

Write-Host "Captured install evidence into $OutputFile"
Write-Host "versionName => $versionNameLine"
Write-Host "versionCode => $versionCodeLine"
Write-Host "installedFromPlay => $installedFromPlay"
Write-Host "evidenceDir => $EvidenceDir"
