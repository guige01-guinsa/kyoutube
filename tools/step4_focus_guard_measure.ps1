$ErrorActionPreference = 'Stop'

$gateFrames = 30
$gateP95 = 50
$gateSlowUi = 3
$ok = $true

adb shell input keyevent KEYCODE_WAKEUP | Out-Null
adb shell wm dismiss-keyguard | Out-Null
adb shell cmd statusbar collapse | Out-Null
adb shell settings put system screen_off_timeout 1800000 | Out-Null

for ($i = 1; $i -le 2; $i++) {
  adb shell am force-stop com.kyoutube.kyoutube | Out-Null
  adb shell am start -n com.kyoutube.kyoutube/com.kyoutube.kyoutube.MainActivity | Out-Null

  $focus = (adb shell dumpsys window | Select-String 'mCurrentFocus').ToString()
  if ($focus -notmatch 'com.kyoutube.kyoutube') {
    adb shell cmd statusbar collapse | Out-Null
    adb shell am start -n com.kyoutube.kyoutube/com.kyoutube.kyoutube.MainActivity | Out-Null
  }

  adb shell dumpsys gfxinfo com.kyoutube.kyoutube reset | Out-Null

  adb shell input tap 720 520
  adb shell input keyevent 67
  adb shell input keyevent 67
  adb shell input keyevent 67
  adb shell input keyevent 67
  adb shell input text "tofu"
  adb shell input keyevent 66
  adb shell input keyevent 4
  adb shell input swipe 720 2450 720 1250 380
  adb shell input swipe 720 1250 720 2450 380
  adb shell input tap 720 1280
  adb shell input keyevent 4

  $focus2 = (adb shell dumpsys window | Select-String 'mCurrentFocus').ToString()
  if ($focus2 -notmatch 'com.kyoutube.kyoutube') {
    adb shell cmd statusbar collapse | Out-Null
    adb shell am start -n com.kyoutube.kyoutube/com.kyoutube.kyoutube.MainActivity | Out-Null
  }

  $outFile = Join-Path $env:TEMP "step4_focus_guard_run_$i.txt"
  adb shell dumpsys gfxinfo com.kyoutube.kyoutube > $outFile
  $txt = Get-Content $outFile -Raw

  $frames = [int]([regex]::Match($txt, 'Total frames rendered:\s*(\d+)').Groups[1].Value)
  $jank = [regex]::Match($txt, 'Janky frames:\s*(\d+\s*\([^\)]+\))').Groups[1].Value
  $p90 = [int]([regex]::Match($txt, '90th percentile:\s*(\d+)ms').Groups[1].Value)
  $p95 = [int]([regex]::Match($txt, '95th percentile:\s*(\d+)ms').Groups[1].Value)
  $p99 = [int]([regex]::Match($txt, '99th percentile:\s*(\d+)ms').Groups[1].Value)
  $slow = [int]([regex]::Match($txt, 'Number Slow UI thread:\s*(\d+)').Groups[1].Value)
  $slowBmp = [int]([regex]::Match($txt, 'Number Slow bitmap uploads:\s*(\d+)').Groups[1].Value)
  $slowDraw = [int]([regex]::Match($txt, 'Number Slow issue draw commands:\s*(\d+)').Groups[1].Value)

  $pass = ($frames -ge $gateFrames -and $p95 -le $gateP95 -and $slow -le $gateSlowUi)
  if (-not $pass) { $ok = $false }

  Write-Output ("RUN{0}: frames={1}, jank={2}, p90={3}ms, p95={4}ms, p99={5}ms, slowUi={6}, slowBmp={7}, slowDraw={8}, pass={9}" -f $i, $frames, $jank, $p90, $p95, $p99, $slow, $slowBmp, $slowDraw, $pass)
}

Write-Output ("FINAL_PASS={0}" -f $ok)
