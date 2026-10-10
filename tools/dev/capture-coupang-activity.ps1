param([string]$Device = '')

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$packageName = 'com.kyoutube.app'
$adb = (Get-Command adb -ErrorAction Stop).Source
$deviceLines = & $adb devices
if ($LASTEXITCODE -ne 0) { throw 'Cannot list Android devices.' }
$connected = @($deviceLines | ForEach-Object {
    if ($_ -match '^(\S+)\s+device$') { $Matches[1] }
})
if (-not $Device) {
    if ($connected.Count -ne 1) { throw 'Connect exactly one authorized Android device, or specify -Device.' }
    $Device = $connected[0]
}
if ($Device -notin $connected) { throw 'The selected device is not connected and authorized.' }
$activity = & $adb -s $Device shell dumpsys activity activities
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the foreground app.' }
$resumed = @($activity | Where-Object { $_ -match '(mResumedActivity|topResumedActivity)' }) -join "`n"
if ($resumed -notmatch ('\b' + [regex]::Escape($packageName) + '/')) {
    throw 'Open Recipe Scout and its affiliate product screen on the phone first.'
}
$evidenceDir = Join-Path $projectRoot '.artifacts/coupang-activity'
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$remote = "/sdcard/coupang-activity-$stamp.png"
$local = Join-Path $evidenceDir "coupang-activity-$stamp.png"
& $adb -s $Device shell screencap -p $remote
if ($LASTEXITCODE -ne 0) { throw 'Android screenshot capture failed.' }
& $adb -s $Device pull $remote $local
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $local)) { throw 'Screenshot transfer failed.' }
Write-Output "Saved original screenshot: $local"
Write-Output 'Review the image for the actual affiliate product, disclosure and purchase button before submission. Nothing was uploaded.'
