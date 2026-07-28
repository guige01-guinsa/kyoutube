$ErrorActionPreference = 'Stop'

$package = 'com.kyoutube.app'
$activity = 'com.kyoutube.app.MainActivity'
$gateFrames = 30
$gateP95 = 50
$gateSlowUi = 3
$allPass = $true

function Set-AppFocus {
  $focus = (adb shell dumpsys window | Select-String 'mCurrentFocus').ToString()
  if ($focus -notmatch $package) {
    adb shell cmd statusbar collapse | Out-Null
    adb shell input keyevent KEYCODE_WAKEUP | Out-Null
    adb shell wm dismiss-keyguard | Out-Null
    adb shell am start -n "$package/$activity" | Out-Null
  }
}

function Get-MetricValue {
  param([string]$text, [string]$pattern, [int]$defaultValue)
  $m = [regex]::Match($text, $pattern)
  if ($m.Success) { return [int]$m.Groups[1].Value }
  return $defaultValue
}

adb shell settings put secure screensaver_enabled 0 | Out-Null
adb shell settings put system screen_off_timeout 1800000 | Out-Null
adb shell input keyevent KEYCODE_WAKEUP | Out-Null
adb shell wm dismiss-keyguard | Out-Null
adb shell cmd statusbar collapse | Out-Null

for ($run = 1; $run -le 2; $run++) {
  adb shell am force-stop $package | Out-Null
  adb shell am start -n "$package/$activity" | Out-Null
  Set-AppFocus
  adb shell dumpsys gfxinfo $package reset | Out-Null

  Set-AppFocus; adb shell input tap 720 520
  Set-AppFocus; adb shell input keyevent 67
  Set-AppFocus; adb shell input keyevent 67
  Set-AppFocus; adb shell input keyevent 67
  Set-AppFocus; adb shell input keyevent 67
  Set-AppFocus; adb shell input text "tofu"
  Set-AppFocus; adb shell input keyevent 66
  Set-AppFocus; adb shell input keyevent 4

  Set-AppFocus; adb shell input swipe 720 2450 720 1200 360
  Set-AppFocus; adb shell input swipe 720 1200 720 2450 360
  Set-AppFocus; adb shell input tap 720 1280
  Set-AppFocus; adb shell input keyevent 4
  Set-AppFocus; adb shell input swipe 720 2450 720 1200 360

  Set-AppFocus
  $outFile = Join-Path $env:TEMP "step4_auto_focus_strict_run_$run.txt"
  adb shell dumpsys gfxinfo $package > $outFile
  $txt = Get-Content $outFile -Raw

  $frames = Get-MetricValue $txt 'Total frames rendered:\s*(\d+)' 0
  $p90 = Get-MetricValue $txt '90th percentile:\s*(\d+)ms' 4950
  $p95 = Get-MetricValue $txt '95th percentile:\s*(\d+)ms' 4950
  $p99 = Get-MetricValue $txt '99th percentile:\s*(\d+)ms' 4950
  $slowUi = Get-MetricValue $txt 'Number Slow UI thread:\s*(\d+)' 999
  $slowBmp = Get-MetricValue $txt 'Number Slow bitmap uploads:\s*(\d+)' 999
  $slowDraw = Get-MetricValue $txt 'Number Slow issue draw commands:\s*(\d+)' 999
  $j = [regex]::Match($txt, 'Janky frames:\s*(\d+\s*\([^\)]+\))')
  $jank = if ($j.Success) { $j.Groups[1].Value } else { 'N/A' }

  $pass = ($frames -ge $gateFrames -and $p95 -le $gateP95 -and $slowUi -le $gateSlowUi)
  if (-not $pass) { $allPass = $false }

  Write-Output ("RUN{0}: frames={1}, jank={2}, p90={3}ms, p95={4}ms, p99={5}ms, slowUi={6}, slowBmp={7}, slowDraw={8}, pass={9}" -f $run, $frames, $jank, $p90, $p95, $p99, $slowUi, $slowBmp, $slowDraw, $pass)
}

Write-Output ("FINAL_PASS={0}" -f $allPass)
