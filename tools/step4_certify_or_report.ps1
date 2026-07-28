$ErrorActionPreference = 'Stop'

$package = 'com.kyoutube.app'
$activity = 'com.kyoutube.app.MainActivity'
$maxPolls = 40
$gateFrames = 30
$gateP95 = 50
$gateSlowUi = 3
$reportDir = 'docs'
$reportPath = Join-Path $reportDir 'step4-certification-latest-report.md'

function Get-FocusLine {
  $lines = adb shell dumpsys window | Select-String 'mCurrentFocus'
  ($lines | ForEach-Object { $_.ToString().Trim() }) -join ' | '
}

function Get-WakeLine {
  $lines = adb shell dumpsys power | Select-String 'mWakefulness'
  ($lines | ForEach-Object { $_.ToString().Trim() }) -join ' | '
}

function Get-MetricValue {
  param([string]$Text, [string]$Pattern, [int]$DefaultValue)
  $m = [regex]::Match($Text, $Pattern)
  if ($m.Success) { return [int]$m.Groups[1].Value }
  return $DefaultValue
}

function Write-Report {
  param(
    [string]$Status,
    [string[]]$BodyLines
  )

  $lines = @(
    '# Step 4 Certification Latest Report',
    '',
    "- Generated at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')",
    "- Status: $Status",
    ''
  ) + $BodyLines

  Set-Content -Path $reportPath -Value $lines -Encoding UTF8
  Write-Output "REPORT_WRITTEN: $reportPath"
}

adb shell input keyevent KEYCODE_WAKEUP | Out-Null
adb shell wm dismiss-keyguard | Out-Null
adb shell cmd statusbar collapse | Out-Null
adb shell settings put system screen_off_timeout 1800000 | Out-Null
adb shell am start -n "$package/$activity" | Out-Null

$ready = $false
$poll = 0
while ($poll -lt $maxPolls) {
  $focus = Get-FocusLine
  $wake = Get-WakeLine
  if ($focus -match $package -and $wake -match 'Awake') {
    $ready = $true
    break
  }
  $poll++
}

if (-not $ready) {
  $focus = Get-FocusLine
  $wake = Get-WakeLine
  Write-Report -Status 'blocked' -BodyLines @(
    '## Blocker',
    '- Device is not in a measurement-ready state.',
    "- Focus: $focus",
    "- Wakefulness: $wake",
    '',
    '## Required one-time action',
    '- Physically unlock the phone and close notification shade so app is foreground.',
    '- Re-run this script after foreground is restored.'
  )
  Write-Output 'CERTIFICATION_BLOCKED'
  exit 2
}

$results = @()
$allPass = $true
for ($run = 1; $run -le 2; $run++) {
  adb shell dumpsys gfxinfo $package reset | Out-Null
  adb shell input tap 720 520
  adb shell input text "tofu"
  adb shell input keyevent 66
  adb shell input swipe 720 2500 720 1100 280
  adb shell input swipe 720 1100 720 2500 280
  adb shell input tap 720 1280
  adb shell input keyevent 4

  $outFile = Join-Path $env:TEMP "step4_certify_run_$run.txt"
  adb shell dumpsys gfxinfo $package > $outFile
  $txt = Get-Content $outFile -Raw

  $frames = Get-MetricValue $txt 'Total frames rendered:\s*(\d+)' 0
  $p95 = Get-MetricValue $txt '95th percentile:\s*(\d+)ms' 4950
  $slow = Get-MetricValue $txt 'Number Slow UI thread:\s*(\d+)' 999
  $j = [regex]::Match($txt, 'Janky frames:\s*(\d+\s*\([^\)]+\))')
  $jank = if ($j.Success) { $j.Groups[1].Value } else { 'N/A' }
  $pass = ($frames -ge $gateFrames -and $p95 -le $gateP95 -and $slow -le $gateSlowUi)
  if (-not $pass) { $allPass = $false }

  $results += ('- Run {0}: frames={1}, p95={2}ms, slowUi={3}, jank={4}, pass={5}' -f $run, $frames, $p95, $slow, $jank, $pass)
  Write-Output ('RUN{0}: frames={1}, p95={2}ms, slowUi={3}, jank={4}, pass={5}' -f $run, $frames, $p95, $slow, $jank, $pass)
}

$status = if ($allPass) { 'pass' } else { 'fail' }
Write-Report -Status $status -BodyLines @(
  '## Results',
  $results,
  '',
  ('- Final pass: {0}' -f $allPass),
  ('- Gate: frames>={0}, p95<={1}ms, slowUi<={2}' -f $gateFrames, $gateP95, $gateSlowUi)
)

Write-Output ("FINAL_PASS={0}" -f $allPass)
