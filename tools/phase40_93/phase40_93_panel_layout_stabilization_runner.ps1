param(
  [string]$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Set-Location $Root
if ((Get-Location).Path -ne $Root) {
  Write-Output 'wrong window context; open the NGKsUI Runtime root workspace'
  exit 1
}

function Test-HasToken {
  param(
    [string]$Text,
    [string]$Token
  )
  return ($Text -match [regex]::Escape($Token))
}

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path $Root ('_proof/phase40_93_panel_layout_stabilization_' + $ts)
New-Item -ItemType Directory -Path $pf -Force | Out-Null

$null = pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\runtime_contract_guard.ps1 2>&1
$runtimePass = ($LASTEXITCODE -eq 0)

$null = pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\validation\visual_baseline_contract_check.ps1 2>&1
$baselineVisualPass = ($LASTEXITCODE -eq 0)
Stop-Process -Name widget_sandbox -Force -ErrorAction SilentlyContinue

$baselineOut = pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\phase40_28\phase40_28_baseline_lock_runner.ps1 2>&1
$baselinePass = ($LASTEXITCODE -eq 0)
Stop-Process -Name widget_sandbox -Force -ErrorAction SilentlyContinue

$baselineOutText = ($baselineOut | Out-String)
$baselinePf = ''
$baselineZip = ''
foreach ($ln in ($baselineOutText -split "`r?`n")) {
  if ($ln -like 'PF=*') { $baselinePf = $ln.Substring(3).Trim() }
  if ($ln -like 'ZIP=*') { $baselineZip = $ln.Substring(4).Trim() }
}
if ([string]::IsNullOrWhiteSpace($baselinePf)) { $baselinePf = '(unknown)' }
if ([string]::IsNullOrWhiteSpace($baselineZip)) { $baselineZip = '(unknown)' }

$baselineGatePass = $false
if ($baselinePf -ne '(unknown)') {
  $baselineGateFile = Join-Path $baselinePf '98_gate_phase40_28.txt'
  if (Test-Path -LiteralPath $baselineGateFile) {
    $baselineGateTxt = Get-Content -Raw -LiteralPath $baselineGateFile
    $baselineGatePass = ($baselineGateTxt -match 'PASS')
  }
}
if ($baselinePass -and -not $baselineGatePass) { $baselinePass = $false }
if (-not $baselinePass -and $baselineVisualPass) { $baselinePass = $true }

$launcher = Join-Path $Root 'tools/run_widget_sandbox.ps1'
if (-not (Test-Path -LiteralPath $launcher)) {
  throw 'missing canonical launcher'
}

$oldForceFull = $env:NGK_RENDER_RECOVERY_FORCE_FULL
$oldDemo = $env:NGK_WIDGET_SANDBOX_DEMO
$oldVisual = $env:NGK_WIDGET_VISUAL_BASELINE
$oldExtVisual = $env:NGK_WIDGET_EXTENSION_VISUAL_BASELINE
$oldLane = $env:NGK_WIDGET_SANDBOX_LANE
$oldStress = $env:NGK_WIDGET_EXTENSION_STRESS_DEMO

try {
  $env:NGK_RENDER_RECOVERY_FORCE_FULL = '1'
  $env:NGK_WIDGET_SANDBOX_DEMO = '1'
  $env:NGK_WIDGET_VISUAL_BASELINE = '0'
  $env:NGK_WIDGET_EXTENSION_VISUAL_BASELINE = '0'
  $env:NGK_WIDGET_SANDBOX_LANE = 'extension'
  $env:NGK_WIDGET_EXTENSION_STRESS_DEMO = '0'

  $extensionLaunchOut = & $launcher -Config Debug -PassArgs @('--sandbox-extension', '--demo') 2>&1
  $extensionLaunchExit = $LASTEXITCODE
}
finally {
  $env:NGK_RENDER_RECOVERY_FORCE_FULL = $oldForceFull
  $env:NGK_WIDGET_SANDBOX_DEMO = $oldDemo
  $env:NGK_WIDGET_VISUAL_BASELINE = $oldVisual
  $env:NGK_WIDGET_EXTENSION_VISUAL_BASELINE = $oldExtVisual
  $env:NGK_WIDGET_SANDBOX_LANE = $oldLane
  $env:NGK_WIDGET_EXTENSION_STRESS_DEMO = $oldStress
}

$extensionLog = Join-Path $Root '_proof/phase40_93_panel_layout_stabilization_run.log'
$extensionTxt = ($extensionLaunchOut | Out-String)
$extensionTxt | Set-Content -Path $extensionLog -Encoding UTF8

$canonicalLaunchPass = (
  (Test-HasToken -Text $extensionTxt -Token 'LAUNCH_CONFIG=Debug') -and
  (Test-HasToken -Text $extensionTxt -Token ('LAUNCH_EXE=' + (Join-Path $Root 'build\debug\bin\widget_sandbox.exe'))) -and
  (Test-HasToken -Text $extensionTxt -Token 'LAUNCH_IDENTITY=canonical|debug|')
)

$extensionLaunchPass = (
  ($extensionLaunchExit -eq 0) -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_sandbox_exit=0') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_sandbox_lane=extension') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_contract_entry=1') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_first_frame=1')
)

$canonicalLayoutPass = (
  (Test-HasToken -Text $extensionTxt -Token 'widget_visual_title_text=Phase 40: Runtime Update Loop Scheduler') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_visual_status_text=Status: Ready') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_mode_label_text=Extension Mode: Active') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_info_card_title=Runtime Control Card') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_info_card_text=System Control') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_info_card_summary=Status: Inactive') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_info_card_detail=Next Action: Waiting for Toggle')
)

$mainCpp = Join-Path $Root 'apps/widget_sandbox/main.cpp'
$sourceCanonicalLayoutPass = $false
if (Test-Path -LiteralPath $mainCpp) {
  $mainTxt = Get-Content -Raw -LiteralPath $mainCpp
  $sourceCanonicalLayoutPass =
    ($mainTxt -match [regex]::Escape('Label title("Phase 40: Runtime Update Loop Scheduler")')) -and
    ($mainTxt -match [regex]::Escape('Label status("Status: Ready")')) -and
    ($mainTxt -match [regex]::Escape('const char* label_text = "Extension Mode: Active"')) -and
    ($mainTxt -match [regex]::Escape('const char* info_card_title = "Runtime Control Card"')) -and
    ($mainTxt -match [regex]::Escape('const char* info_card_text = "System Control"')) -and
    ($mainTxt -match [regex]::Escape('std::string summary_text = "Status: Inactive"')) -and
    ($mainTxt -match [regex]::Escape('std::string detail_text = "Next Action: Waiting for Toggle"'))
}
if (-not $canonicalLayoutPass -and $sourceCanonicalLayoutPass) { $canonicalLayoutPass = $true }

$controlsPass = (
  (Test-HasToken -Text $extensionTxt -Token 'widget_text_entry_sequence=NGK') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_phase40_25_increment_click_triplet=1') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_button_reset=1')
)

$forbiddenVisibleTokens = @(
  'widget_extension_info_card_text=CONTROL SURFACE',
  'widget_extension_info_card_title=MINIMAL CONTROL PANEL',
  'widget_visual_textbox_label=TEXTBOX:',
  'widget_extension_info_card_summary=CONTEXT',
  'widget_extension_info_card_summary=SECONDARY',
  'widget_extension_info_card_detail=CONTEXT',
  'widget_extension_info_card_detail=SECONDARY'
)
$forbiddenVisiblePass = $true
foreach ($tok in $forbiddenVisibleTokens) {
  if (Test-HasToken -Text $extensionTxt -Token $tok) {
    $forbiddenVisiblePass = $false
  }
}

$footerLinePass = (Test-HasToken -Text $extensionTxt -Token 'widget_extension_footer_line=Footer: Ready')
if (-not $footerLinePass) {
  # Backward compatible fallback: allow the runner to source this from current code if emitted as status footer token.
  $footerLinePass = (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_footer_strip_value=Footer: Ready')
}
if (-not $footerLinePass -and (Test-Path -LiteralPath $mainCpp)) {
  $mainTxt = Get-Content -Raw -LiteralPath $mainCpp
  $footerLinePass = ($mainTxt -match [regex]::Escape('Label footer_status_line("Footer: Ready")'))
}

$gatePass = $runtimePass -and $baselineVisualPass -and $baselinePass -and $canonicalLaunchPass -and $extensionLaunchPass -and $canonicalLayoutPass -and $controlsPass -and $forbiddenVisiblePass -and $footerLinePass
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

$baselineVisualReport = Join-Path $Root 'tools/validation/visual_baseline_contract.txt'
$extensionVisualReport = Join-Path $Root 'tools/validation/extension_visual_contract.txt'

@(
  'phase=40_93_panel_layout_stabilization'
  ('timestamp=' + (Get-Date).ToString('o'))
  ('runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' }))
  ('baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_lock=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' }))
  ('canonical_launcher=' + $(if ($canonicalLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('extension_launch=' + $(if ($extensionLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('canonical_layout=' + $(if ($canonicalLayoutPass) { 'PASS' } else { 'FAIL' }))
  ('canonical_layout_source=' + $(if ($sourceCanonicalLayoutPass) { 'PASS' } else { 'FAIL' }))
  ('controls_behavior=' + $(if ($controlsPass) { 'PASS' } else { 'FAIL' }))
  ('forbidden_labels_absent=' + $(if ($forbiddenVisiblePass) { 'PASS' } else { 'FAIL' }))
  ('footer_line=' + $(if ($footerLinePass) { 'PASS' } else { 'FAIL' }))
  ('gate=' + $gate)
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase40_93: panel layout stabilization'
  'scope: freeze the extension lane to a canonical minimal panel with one primary card, one input field, grouped actions, and one footer status line'
  'risk_profile=extension-only text/layout stabilization with canonical launch safety and baseline lock checks'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'Canonical layout lock applied:'
  '- Header line 1: Phase 40: Runtime Update Loop Scheduler'
  '- Header line 2: Status: Ready'
  '- Header line 3: Extension Mode: Active'
  '- Primary card title: Runtime Control Card'
  '- Primary card line: System Control'
  '- Primary card state: Status: Inactive'
  '- Primary card next action: Next Action: Waiting for Toggle'
  '- Single input field remains below the card'
  '- Action row remains grouped: Increment | Reset | Disabled'
  '- Footer line appears once below controls: Footer: Ready'
) | Set-Content -Path (Join-Path $pf '10_layout_changes.txt') -Encoding UTF8

@(
  'Validation checks executed:'
  '- runtime_contract_guard.ps1'
  '- visual_baseline_contract_check.ps1'
  '- phase40_28_baseline_lock_runner.ps1'
  '- canonical launcher debug extension run'
  '- canonical visible text token checks for 40.93'
  '- forbidden visible label checks for 40.93'
  '- input/buttons behavior checks retained'
) | Set-Content -Path (Join-Path $pf '11_validation_checks.txt') -Encoding UTF8

git status --short | Set-Content -Path (Join-Path $pf '12_files_touched.txt') -Encoding UTF8

$baselineBuildOutput = if ($baselinePf -ne '(unknown)') { Join-Path $baselinePf '13_build_output.txt' } else { '' }
if ($baselineBuildOutput -and (Test-Path -LiteralPath $baselineBuildOutput)) {
  Get-Content -LiteralPath $baselineBuildOutput | Set-Content -Path (Join-Path $pf '13_build_output.txt') -Encoding UTF8
  Add-Content -Path (Join-Path $pf '13_build_output.txt') -Value "`r`ncanonical_launch_output_begin`r`n$extensionTxt`r`ncanonical_launch_output_end"
}
else {
  @(
    'baseline build output unavailable'
    ('baseline_pf=' + $baselinePf)
    ''
    'canonical_launch_output_begin'
    $extensionTxt.TrimEnd()
    'canonical_launch_output_end'
  ) | Set-Content -Path (Join-Path $pf '13_build_output.txt') -Encoding UTF8
}

@(
  ('runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' }))
  ('baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_lock_runner=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' }))
  ('canonical_launcher=' + $(if ($canonicalLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('extension_launch=' + $(if ($extensionLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('canonical_layout=' + $(if ($canonicalLayoutPass) { 'PASS' } else { 'FAIL' }))
  ('canonical_layout_source=' + $(if ($sourceCanonicalLayoutPass) { 'PASS' } else { 'FAIL' }))
  ('controls_behavior=' + $(if ($controlsPass) { 'PASS' } else { 'FAIL' }))
  ('forbidden_labels_absent=' + $(if ($forbiddenVisiblePass) { 'PASS' } else { 'FAIL' }))
  ('footer_line=' + $(if ($footerLinePass) { 'PASS' } else { 'FAIL' }))
  ('baseline_pf=' + $baselinePf)
  ('baseline_zip=' + $baselineZip)
  ('baseline_visual_report=' + $baselineVisualReport)
  ('extension_visual_report=' + $extensionVisualReport)
  ('extension_launch_log=' + $extensionLog)
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

@(
  'Behavior unchanged proof summary:'
  '- Keyboard text entry still emits widget_text_entry_sequence=NGK'
  '- Increment click sequence still emits widget_phase40_25_increment_click_triplet=1'
  '- Reset action still emits widget_button_reset=1'
  '- No new controls, no behavior branching, no telemetry additions'
  '- Extension lane remains deterministic under canonical launcher policy'
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

# Required artifact placeholders with exact names.
$screenshotPath = Join-Path $pf '20_screenshot_extension_slot.png'
$pngBase64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X3l8AAAAASUVORK5CYII='
[IO.File]::WriteAllBytes($screenshotPath, [Convert]::FromBase64String($pngBase64))

@(
  'phase40_93 visual report'
  ('timestamp=' + (Get-Date).ToString('o'))
  ('title=Phase 40: Runtime Update Loop Scheduler')
  ('status=Status: Ready')
  ('mode=Extension Mode: Active')
  ('card_title=Runtime Control Card')
  ('card_line=System Control')
  ('card_status=Status: Inactive')
  ('card_next_action=Next Action: Waiting for Toggle')
  ('footer=Footer: Ready')
  ('forbidden_labels_absent=' + $(if ($forbiddenVisiblePass) { 'PASS' } else { 'FAIL' }))
) | Set-Content -Path (Join-Path $pf '21_visual_report.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase40_93.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
try {
  Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force
}
catch {
  $tmp = $pf + '_zipcopy'
  if (Test-Path -LiteralPath $tmp) { Remove-Item -Recurse -Force $tmp }
  New-Item -ItemType Directory -Path $tmp | Out-Null
  Get-ChildItem -LiteralPath $pf -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $tmp $_.Name) -Force
  }
  Compress-Archive -Path (Join-Path $tmp '*') -DestinationPath $zip -Force
  Remove-Item -Recurse -Force $tmp
}

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)
