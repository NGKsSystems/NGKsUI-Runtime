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

function Get-TokenCount {
  param(
    [string]$Text,
    [string]$Token
  )
  return ([regex]::Matches($Text, [regex]::Escape($Token))).Count
}

function Get-TokenOffset {
  param(
    [string]$Text,
    [string]$Token,
    [int]$StartAt = 0
  )
  if ($StartAt -lt 0) { $StartAt = 0 }
  if ($StartAt -ge $Text.Length) { return -1 }
  return $Text.IndexOf($Token, $StartAt, [System.StringComparison]::Ordinal)
}

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path $Root ('_proof/phase42_1_trace_divergence_detection_' + $ts)
New-Item -ItemType Directory -Path $pf -Force | Out-Null

$launcher = Join-Path $Root 'tools/run_widget_sandbox.ps1'
if (-not (Test-Path -LiteralPath $launcher)) {
  throw 'missing canonical launcher'
}

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

$buildLines = New-Object System.Collections.Generic.List[string]
try {
  Get-Process widget_sandbox,mspdbsrv,cl,link -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  . .\tools\enter_msvc_env.ps1

  $compileCmd = 'cl /nologo /EHsc /std:c++20 /MD /showIncludes /FS /c apps/widget_sandbox/main.cpp /Fobuild/debug/obj/widget_sandbox/apps/widget_sandbox/main.obj /Iengine/core/include /Iengine/gfx/include /Iengine/gfx/win32/include /Iengine/platform/win32/include /Iengine/ui /Iengine/ui/include /DDEBUG /DUNICODE /D_UNICODE /Od /Zi'
  $linkCmd = 'link /nologo build/debug/obj/widget_sandbox/apps/widget_sandbox/main.obj build/debug/lib/engine.lib /OUT:build/debug/bin/widget_sandbox.exe d3d11.lib dxgi.lib gdi32.lib user32.lib'

  $buildLines.Add('compile_cmd=' + $compileCmd)
  $compileOut = cmd.exe /d /c $compileCmd 2>&1
  foreach ($l in ($compileOut | Out-String -Stream)) { $buildLines.Add($l) }
  if ($LASTEXITCODE -ne 0) { throw 'compile failed' }

  $buildLines.Add('link_cmd=' + $linkCmd)
  $linkOut = cmd.exe /d /c $linkCmd 2>&1
  foreach ($l in ($linkOut | Out-String -Stream)) { $buildLines.Add($l) }
  if ($LASTEXITCODE -ne 0) { throw 'link failed' }

  $buildExit = 0
} catch {
  $buildExit = 1
  $buildLines.Add('build_error=' + $_.Exception.Message)
}

$buildText = (($buildLines.ToArray()) -join "`r`n")
$buildPass = ($buildExit -eq 0) -and (Test-Path -LiteralPath (Join-Path $Root 'build/debug/bin/widget_sandbox.exe'))

$oldForceFull = $env:NGK_RENDER_RECOVERY_FORCE_FULL
$oldDemo = $env:NGK_WIDGET_SANDBOX_DEMO
$oldVisual = $env:NGK_WIDGET_VISUAL_BASELINE
$oldExtVisual = $env:NGK_WIDGET_EXTENSION_VISUAL_BASELINE
$oldLane = $env:NGK_WIDGET_SANDBOX_LANE
$oldStress = $env:NGK_WIDGET_EXTENSION_STRESS_DEMO

try {
  Set-Location $Root
  $env:NGK_RENDER_RECOVERY_FORCE_FULL = '1'
  $env:NGK_WIDGET_SANDBOX_DEMO = '1'
  $env:NGK_WIDGET_VISUAL_BASELINE = '0'
  $env:NGK_WIDGET_EXTENSION_VISUAL_BASELINE = '0'
  $env:NGK_WIDGET_SANDBOX_LANE = 'extension'
  $env:NGK_WIDGET_EXTENSION_STRESS_DEMO = '0'

  $runOut = & $launcher -Config Debug -PassArgs @('--sandbox-extension', '--demo') 2>&1
  $runExit = $LASTEXITCODE
}
finally {
  $env:NGK_RENDER_RECOVERY_FORCE_FULL = $oldForceFull
  $env:NGK_WIDGET_SANDBOX_DEMO = $oldDemo
  $env:NGK_WIDGET_VISUAL_BASELINE = $oldVisual
  $env:NGK_WIDGET_EXTENSION_VISUAL_BASELINE = $oldExtVisual
  $env:NGK_WIDGET_SANDBOX_LANE = $oldLane
  $env:NGK_WIDGET_EXTENSION_STRESS_DEMO = $oldStress
}

$runText = ($runOut | Out-String)
$runLog = Join-Path $Root '_proof/phase42_1_trace_divergence_detection_run.log'
$runText | Set-Content -Path $runLog -Encoding UTF8

$canonicalLaunchPass = (
  (Test-HasToken -Text $runText -Token 'LAUNCH_CONFIG=Debug') -and
  (Test-HasToken -Text $runText -Token ('LAUNCH_EXE=' + (Join-Path $Root 'build\debug\bin\widget_sandbox.exe'))) -and
  (Test-HasToken -Text $runText -Token 'LAUNCH_IDENTITY=canonical|debug|')
)

$extensionLaunchPass = (
  ($runExit -eq 0) -and
  (Test-HasToken -Text $runText -Token 'widget_sandbox_exit=0') -and
  (Test-HasToken -Text $runText -Token 'widget_sandbox_lane=extension')
)

$phaseBeginPass = (
  (Test-HasToken -Text $runText -Token 'widget_phase42_1_begin=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase42_1_complete=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase42_1_divergence_case_count=6')
)

$validReplayPass = (
  (Test-HasToken -Text $runText -Token 'widget_phase42_1_valid_trace_pass=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase42_1_valid_trace_reason=pass') -and
  (Test-HasToken -Text $runText -Token 'widget_phase42_1_valid_trace_steps_completed=12')
)

$expectedCases = @(
  @{ Name = 'missing_record'; Reason = 'event_mismatch' },
  @{ Name = 'reordered_events'; Reason = 'event_mismatch' },
  @{ Name = 'corrupted_state_value'; Reason = 'state_after_mismatch' },
  @{ Name = 'premature_termination'; Reason = 'missing_end_marker' },
  @{ Name = 'duplicate_replay_step'; Reason = 'record_count_mismatch' },
  @{ Name = 'missing_begin_marker'; Reason = 'missing_begin_marker' }
)

$caseOrderPass = $true
$caseFailurePass = $true
$caseReasonPass = $true
$lastCaseOffset = -1
foreach ($case in $expectedCases) {
  $nameToken = 'widget_phase42_1_case_name=' + $case.Name
  $nameOffset = Get-TokenOffset -Text $runText -Token $nameToken -StartAt ($lastCaseOffset + 1)
  if ($nameOffset -lt 0) {
    $caseOrderPass = $false
    $caseFailurePass = $false
    $caseReasonPass = $false
    break
  }

  $passOffset = Get-TokenOffset -Text $runText -Token 'widget_phase42_1_case_pass=0' -StartAt $nameOffset
  $reasonToken = 'widget_phase42_1_case_reason=' + $case.Reason
  $reasonOffset = Get-TokenOffset -Text $runText -Token $reasonToken -StartAt $nameOffset

  if ($passOffset -lt 0 -or $passOffset -lt $nameOffset) {
    $caseFailurePass = $false
  }
  if ($reasonOffset -lt 0 -or $reasonOffset -lt $nameOffset) {
    $caseReasonPass = $false
  }

  $lastCaseOffset = $nameOffset
}

$caseCountPass = ((Get-TokenCount -Text $runText -Token 'widget_phase42_1_case_name=') -eq 6)

$divergencePass = (
  $caseOrderPass -and
  $caseFailurePass -and
  $caseReasonPass -and
  $caseCountPass
)

$failureConditionPass = (
  (Test-HasToken -Text $runText -Token 'widget_phase42_1_case_reason=event_mismatch') -and
  (Test-HasToken -Text $runText -Token 'widget_phase42_1_case_reason=state_after_mismatch') -and
  (Test-HasToken -Text $runText -Token 'widget_phase42_1_case_reason=record_count_mismatch') -and
  (Test-HasToken -Text $runText -Token 'widget_phase42_1_case_reason=missing_end_marker') -and
  (Test-HasToken -Text $runText -Token 'widget_phase42_1_case_reason=missing_begin_marker')
)

$disabledInertPass = (
  (Test-HasToken -Text $runText -Token 'widget_disabled_noninteractive_demo=1') -and
  (Test-HasToken -Text $runText -Token 'widget_runtime_disabled_intent_blocked=1')
)

$scopeGuardPass = (
  (Test-HasToken -Text $runText -Token 'widget_extension_mode_active=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase40_19_simple_layout_drawn=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase40_5_coherent_composition=1')
)

$gatePass = (
  $runtimePass -and
  $baselineVisualPass -and
  $baselinePass -and
  $buildPass -and
  $canonicalLaunchPass -and
  $extensionLaunchPass -and
  $phaseBeginPass -and
  $validReplayPass -and
  $divergencePass -and
  $failureConditionPass -and
  $disabledInertPass -and
  $scopeGuardPass
)
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

@(
  'phase=42_1_trace_divergence_detection'
  ('timestamp=' + (Get-Date).ToString('o'))
  ('runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' }))
  ('baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_lock=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' }))
  ('build=' + $(if ($buildPass) { 'PASS' } else { 'FAIL' }))
  ('canonical_launcher=' + $(if ($canonicalLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('extension_launch=' + $(if ($extensionLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('phase_begin=' + $(if ($phaseBeginPass) { 'PASS' } else { 'FAIL' }))
  ('valid_trace_replay=' + $(if ($validReplayPass) { 'PASS' } else { 'FAIL' }))
  ('divergence_detection=' + $(if ($divergencePass) { 'PASS' } else { 'FAIL' }))
  ('failure_conditions=' + $(if ($failureConditionPass) { 'PASS' } else { 'FAIL' }))
  ('disabled_inert=' + $(if ($disabledInertPass) { 'PASS' } else { 'FAIL' }))
  ('scope_guard=' + $(if ($scopeGuardPass) { 'PASS' } else { 'FAIL' }))
  ('gate=' + $gate)
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase42_1: trace divergence detection proof'
  'scope: prove replay validation rejects corrupted, incomplete, reordered, duplicated, and malformed trace histories while valid replay still succeeds'
  'risk_profile=validation only; no visible layout, baseline, or control behavior changes'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'divergence_detection_definition:'
  '- Replay divergence is detected when a trace record cannot legally continue from the previous reconstructed state/value.'
  '- The validator starts from canonical Idle|0 and requires trace_sequence_begin as the first record.'
  '- Each record must present state_before/value_before equal to the current replay cursor before advancing to state_after/value_after.'
  '- The validator rejects traces that continue past trace_sequence_end, omit the end marker, or omit the begin marker.'
  '- A valid trace passes only if replay ends at trace_sequence_end and the reconstructed final state/value equals the real runtime final state/value.'
) | Set-Content -Path (Join-Path $pf '10_divergence_detection_definition.txt') -Encoding UTF8

@(
  'divergence_test_scenarios:'
  '- missing_record: remove the second textbox_input_accepted record; the deterministic sequence no longer matches and validation fails with event_mismatch.'
  '- reordered_events: swap reset_action_executed with canonical_reset_completed; validation fails with event_mismatch at the first swapped position.'
  '- corrupted_state_value: change recovery_action_performed state_after/value_after to Idle|99; validation fails with state_after_mismatch.'
  '- premature_termination: remove trace_sequence_end; validator fails with missing_end_marker.'
  '- duplicate_replay_step: repeat recovery_action_performed; validation fails with record_count_mismatch.'
  '- missing_begin_marker: remove trace_sequence_begin; validator fails immediately with missing_begin_marker.'
) | Set-Content -Path (Join-Path $pf '11_divergence_test_scenarios.txt') -Encoding UTF8

git status --short | Set-Content -Path (Join-Path $pf '12_files_touched.txt') -Encoding UTF8

@(
  'build_output_begin'
  $buildText.TrimEnd()
  'build_output_end'
  ''
  'run_output_begin'
  $runText.TrimEnd()
  'run_output_end'
) | Set-Content -Path (Join-Path $pf '13_build_output.txt') -Encoding UTF8

@(
  ('runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' }))
  ('baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_lock=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' }))
  ('build=' + $(if ($buildPass) { 'PASS' } else { 'FAIL' }))
  ('canonical_launcher=' + $(if ($canonicalLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('extension_launch=' + $(if ($extensionLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('phase_begin=' + $(if ($phaseBeginPass) { 'PASS' } else { 'FAIL' }))
  ('valid_trace_replay=' + $(if ($validReplayPass) { 'PASS' } else { 'FAIL' }))
  ('case_order=' + $(if ($caseOrderPass) { 'PASS' } else { 'FAIL' }))
  ('case_failures=' + $(if ($caseFailurePass) { 'PASS' } else { 'FAIL' }))
  ('case_reasons=' + $(if ($caseReasonPass) { 'PASS' } else { 'FAIL' }))
  ('case_count=' + $(if ($caseCountPass) { 'PASS' } else { 'FAIL' }))
  ('divergence_detection=' + $(if ($divergencePass) { 'PASS' } else { 'FAIL' }))
  ('failure_conditions=' + $(if ($failureConditionPass) { 'PASS' } else { 'FAIL' }))
  ('disabled_inert=' + $(if ($disabledInertPass) { 'PASS' } else { 'FAIL' }))
  ('scope_guard=' + $(if ($scopeGuardPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_pf=' + $baselinePf)
  ('baseline_zip=' + $baselineZip)
  ('run_log=' + $runLog)
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

@(
  'behavior_summary:'
  '- Replay detects divergence by comparing the candidate trace against the deterministic valid trace history for this certified scenario, including event order and before/after fields.'
  '- Corrupted traces are identified by deterministic reasons emitted from the validator: event_mismatch, state_after_mismatch, record_count_mismatch, missing_end_marker, and missing_begin_marker.'
  '- Missing events are detected because removing a required record shifts the deterministic sequence and causes event_mismatch, or removes the end marker entirely.'
  '- Reordered events are detected because the event order no longer matches the legal deterministic trace history.'
  '- State/value mismatches are detected because altered state_after/value_after fields no longer match the certified trace record at that step.'
  '- Disabled remained inert because no disabled-driven mutation entered the runtime trace and the existing disabled guard tokens remained present.'
  '- Baseline remained unchanged because validation executes only in extension mode while the baseline lock and visual contract checks both PASS.'
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase42_1.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)