param(
  [string]$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Set-Location $Root

$reportPath = Join-Path $Root 'tools/validation/visual_baseline_contract.txt'
$logPath = Join-Path $Root '_proof/phase40_30_visual_baseline_run.log'
$launcher = Join-Path $Root 'tools/run_widget_sandbox.ps1'
if (-not (Test-Path -LiteralPath $launcher)) {
  throw "Missing canonical launcher: $launcher"
}

$oldForceFull = $env:NGK_RENDER_RECOVERY_FORCE_FULL
$oldDemo = $env:NGK_WIDGET_SANDBOX_DEMO
$oldVisual = $env:NGK_WIDGET_VISUAL_BASELINE

try {
  $env:NGK_RENDER_RECOVERY_FORCE_FULL = '1'
  $env:NGK_WIDGET_SANDBOX_DEMO = '0'
  $env:NGK_WIDGET_VISUAL_BASELINE = '1'

  $out = & $launcher -Config Debug -PassArgs @('--visual-baseline') 2>&1
  $txt = ($out | Out-String)
  $exitCode = $LASTEXITCODE
  $txt | Set-Content -Path $logPath -Encoding UTF8

  $widgetExe = '(unknown)'
  foreach ($line in ($txt -split "`r?`n")) {
    if ($line -like 'LAUNCH_EXE=*') {
      $widgetExe = $line.Substring(11).Trim()
      break
    }
  }

  function HasToken([string]$token) {
    return $txt -match [regex]::Escape($token)
  }

  $checks = [ordered]@{
    background_present = (HasToken 'widget_visual_contract_background_present=1')
    title_present = (HasToken 'widget_visual_contract_title_present=1')
    status_present = (HasToken 'widget_visual_contract_status_present=1')
    textbox_present = (HasToken 'widget_visual_contract_textbox_present=1')
    button1_present = (HasToken 'widget_visual_contract_button1_present=1')
    button2_present = (HasToken 'widget_visual_contract_button2_present=1')
    window_size_captured = (HasToken 'widget_visual_window_size=960x640')
    title_text_fixed = (HasToken 'widget_visual_title_text=Phase 40: Runtime Update Loop Scheduler')
    status_text_fixed = (HasToken 'widget_visual_status_text=status: ready')
    button1_text_fixed = (HasToken 'widget_visual_button1_text=Increment')
    button2_text_fixed = (HasToken 'widget_visual_button2_text=Reset')
    bounds_dump_present = (HasToken 'widget_visual_bounds_title=') -and (HasToken 'widget_visual_bounds_status=') -and (HasToken 'widget_visual_bounds_textbox=') -and (HasToken 'widget_visual_bounds_button1=') -and (HasToken 'widget_visual_bounds_button2=')
    capture_completed = (HasToken 'widget_visual_baseline_capture_done=1')
    sandbox_clean_exit = (($exitCode -eq 0) -and (HasToken 'widget_sandbox_exit=0'))
    first_frame = (HasToken 'widget_first_frame=1')
  }

  $pass = $true
  foreach ($entry in $checks.GetEnumerator()) {
    if (-not [bool]$entry.Value) {
      $pass = $false
      break
    }
  }

  @(
    'PHASE 40.30 visual baseline contract',
    "timestamp=$(Get-Date -Format o)",
    "widget_exe=$widgetExe",
    'mode=--visual-baseline + NGK_WIDGET_VISUAL_BASELINE=1',
    "render_artifact_log=$logPath",
    "gate=$(if ($pass) { 'PASS' } else { 'FAIL' })",
    '--- checks ---'
  ) + ($checks.GetEnumerator() | ForEach-Object { "$_" }) | Set-Content -Path $reportPath -Encoding UTF8

  if (-not $pass) {
    Write-Output 'visual_baseline_contract=FAIL'
    exit 1
  }

  Write-Output 'visual_baseline_contract=PASS'
  Write-Output "report=$reportPath"
  exit 0
}
finally {
  $env:NGK_RENDER_RECOVERY_FORCE_FULL = $oldForceFull
  $env:NGK_WIDGET_SANDBOX_DEMO = $oldDemo
  $env:NGK_WIDGET_VISUAL_BASELINE = $oldVisual
}
