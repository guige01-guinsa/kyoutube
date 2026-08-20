$ErrorActionPreference = 'Stop'

$package = 'com.kyoutube.kyoutube'
$activity = 'com.kyoutube.kyoutube.MainActivity'
$maxRuns = 12
$gateFrames = 30
$gateP95 = 50
$gateSlowUi = 3
$streak = 0

function Get-MetricValue {
  param([string]$Text, [string]$Pattern, [int]$DefaultValue)
  $m = [regex]::Match($Text, $Pattern)
  if ($m.Success) { return [int]$m.Groups[1].Value }
  return $DefaultValue
}

adb shell input keyevent KEYCODE_WAKEUP | Out-Null
adb shell wm dismiss-keyguard | Out-Null
adb shell cmd statusbar collapse | Out-Null
adb shell settings put system screen_off_timeout 1800000 | Out-Null
adb shell am start -n "$package/$activity" | Out-Null

for ($run = 1; $run -le $maxRuns; $run++) {
  adb shell dumpsys gfxinfo $package reset | Out-Null
  adb shell input tap 720 520
  adb shell input text "tofu"
  adb shell input keyevent 66
  adb shell input swipe 720 2500 720 1100 280
  adb shell input swipe 720 1100 720 2500 280
  adb shell input tap 720 1280
  adb shell input keyevent 4

  $outFile = Join-Path $env:TEMP "step4_hunt_run_$run.txt"
  adb shell dumpsys gfxinfo $package > $outFile
  $txt = Get-Content $outFile -Raw

  $frames = Get-MetricValue $txt 'Total frames rendered:\s*(\d+)' 0
  $p95 = Get-MetricValue $txt '95th percentile:\s*(\d+)ms' 4950
  $slowUi = Get-MetricValue $txt 'Number Slow UI thread:\s*(\d+)' 999
  $j = [regex]::Match($txt, 'Janky frames:\s*(\d+\s*\([^\)]+\))')
  $jank = if ($j.Success) { $j.Groups[1].Value } else { 'N/A' }

  $pass = ($frames -ge $gateFrames -and $p95 -le $gateP95 -and $slowUi -le $gateSlowUi)
  if ($pass) { $streak++ } else { $streak = 0 }

  Write-Output ("RUN{0}: frames={1}, p95={2}ms, slowUi={3}, jank={4}, pass={5}, streak={6}" -f $run, $frames, $p95, $slowUi, $jank, $pass, $streak)
  if ($streak -ge 2) { break }
}

Write-Output ("FINAL_STREAK={0}" -f $streak)
