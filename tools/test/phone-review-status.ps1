param([string]$DeviceSerial)
$ErrorActionPreference = 'Stop'
$adbPath = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adbPath)) { throw 'Android platform-tools adb is not installed.' }
$deviceLines = @(& $adbPath devices)
if ($LASTEXITCODE -ne 0) { throw 'ADB device discovery failed.' }
$devices = @($deviceLines | Where-Object { $_ -match '^\S+\s+(device|unauthorized|offline)\s*$' } | ForEach-Object {
    $parts = $_ -split '\s+'
    [PSCustomObject]@{Serial=$parts[0]; State=$parts[1]}
})
if ($devices.Count -eq 0) {
    [PSCustomObject]@{Status='not_detected'; NextStep='Unlock phone, use a data-capable USB cable, select file transfer, enable USB debugging and accept the computer authorization.'} | ConvertTo-Json
    exit 2
}
if ($DeviceSerial) { $devices = @($devices | Where-Object Serial -EQ $DeviceSerial) }
if ($devices.Count -ne 1) { throw 'Select exactly one device with -DeviceSerial.' }
$device = $devices[0]
if ($device.State -ne 'device') {
    [PSCustomObject]@{Status=$device.State; NextStep='Unlock the phone and accept the USB debugging authorization.'} | ConvertTo-Json
    exit 2
}
$model = (& $adbPath -s $device.Serial shell getprop ro.product.model).Trim()
$android = (& $adbPath -s $device.Serial shell getprop ro.build.version.release).Trim()
$packageLines = @(& $adbPath -s $device.Serial shell dumpsys package com.kyoutube.app)
$codeLine = $packageLines | Where-Object { $_ -match 'versionCode=(\d+)' } | Select-Object -First 1
$nameLine = $packageLines | Where-Object { $_ -match 'versionName=(\S+)' } | Select-Object -First 1
$versionCode = if ($codeLine -match 'versionCode=(\d+)') {$Matches[1]} else {$null}
$versionName = if ($nameLine -match 'versionName=(\S+)') {$Matches[1]} else {$null}
[PSCustomObject]@{
    Status = if ($versionCode) {'ready_for_manual_app_review'} else {'app_not_installed'}
    Model=$model; Android=$android; Package='com.kyoutube.app'; VersionName=$versionName; VersionCode=$versionCode
    Login='Verify in the app; authentication tokens are not read.'
    DataChanges='None. No installation, data clearing, account change or permission changes.'
} | ConvertTo-Json
