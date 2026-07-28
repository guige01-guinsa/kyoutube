$ErrorActionPreference = 'Stop'

$package = 'com.kyoutube.app'
$activity = 'com.kyoutube.app.MainActivity'
$gateFrames = 30
$gateP95 = 50
$gateSlowUi = 3
$allPass = $true

function Get-MetricValue {
  param(
    [string]$Text,
    [string]$Pattern,
    [int]$DefaultValue = -1
  )

  $m = [regex]::Match($Text, $Pattern)
  if ($m.Success) {
    return [int]$m.Groups[1].Value
  }
  return $DefaultValue
}

adb shell input keyevent KEYCODE_WAKEUP | Out-Null
adb shell wm dismiss-keyguard | Out-Null
adb shell cmd statusbar collapse | Out-Null
adb shell settings put system screen_off_timeout 1800000 | Out-Null

Write-Output 'Step 4 manual assisted capture starts.'
Write-Output 'For each run: search tofu -> scroll down/up -> open detail -> back.'

for ($run = 1; $run -le 2; $run++) {
  adb shell am start -n "$package/$activity" | Out-Null
  adb shell dumpsys gfxinfo $package reset | Out-Null

  Write-Output "Run $run is ready. Complete manual flow on device, then press Enter here."
  Read-Host | Out-Null

  $outFile = Join-Path $env:TEMP "step4_manual_assisted_run_$run.txt"
  adb shell dumpsys gfxinfo $package > $outFile
  $txt = Get-Content $outFile -Raw

  $frames = Get-MetricValue -Text $txt -Pattern 'Total frames rendered:\s*(\d+)' -DefaultValue 0
  $p90 = Get-MetricValue -Text $txt -Pattern '90th percentile:\s*(\d+)ms' -DefaultValue 4950
  $p95 = Get-MetricValue -Text $txt -Pattern '95th percentile:\s*(\d+)ms' -DefaultValue 4950
  $p99 = Get-MetricValue -Text $txt -Pattern '99th percentile:\s*(\d+)ms' -DefaultValue 4950
  $slowUi = Get-MetricValue -Text $txt -Pattern 'Number Slow UI thread:\s*(\d+)' -DefaultValue 999
  $slowBmp = Get-MetricValue -Text $txt -Pattern 'Number Slow bitmap uploads:\s*(\d+)' -DefaultValue 999
  $slowDraw = Get-MetricValue -Text $txt -Pattern 'Number Slow issue draw commands:\s*(\d+)' -DefaultValue 999
  $j = [regex]::Match($txt, 'Janky frames:\s*(\d+\s*\([^\)]+\))')
  $jank = if ($j.Success) { $j.Groups[1].Value } else { 'N/A' }

  $pass = ($frames -ge $gateFrames -and $p95 -le $gateP95 -and $slowUi -le $gateSlowUi)
  if (-not $pass) {
    $allPass = $false
  }

  Write-Output ("RUN{0}: frames={1}, jank={2}, p90={3}ms, p95={4}ms, p99={5}ms, slowUi={6}, slowBmp={7}, slowDraw={8}, pass={9}" -f $run, $frames, $jank, $p90, $p95, $p99, $slowUi, $slowBmp, $slowDraw, $pass)
}

Write-Output ("FINAL_PASS={0}" -f $allPass)
