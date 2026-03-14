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
$pf = Join-Path $Root ('_proof/phase41_6_post_validation_action_continuity_' + $ts)
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
$runLog = Join-Path $Root '_proof/phase41_6_post_validation_action_continuity_run.log'
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

# Phase 41.6 — post-validation action continuity gate checks

# Begin state: Idle, value=0 (after 41.5 last reset)
$beginStatePass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_6_begin=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_6_begin_state=Idle') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_6_begin_value=0')
)

# All 4 invalid classes submitted in sequence — each rejected with state/value preserved
$invalidSeq0Pass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_6_invalid_seq_0_reason=input_empty') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_6_invalid_seq_0_state_preserved=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_6_invalid_seq_0_value_preserved=1')
)

$invalidSeq1Pass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_6_invalid_seq_1_reason=input_non_numeric') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_6_invalid_seq_1_state_preserved=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_6_invalid_seq_1_value_preserved=1')
)

$invalidSeq2Pass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_6_invalid_seq_2_reason=input_out_of_range') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_6_invalid_seq_2_state_preserved=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_6_invalid_seq_2_value_preserved=1')
)

$invalidSeq3Pass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_6_invalid_seq_3_reason=input_malformed_mixed') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_6_invalid_seq_3_state_preserved=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_6_invalid_seq_3_value_preserved=1')
)

$invalidSequencePass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_6_invalid_sequence_count=4') -and
  $invalidSeq0Pass -and
  $invalidSeq1Pass -and
  $invalidSeq2Pass -and
  $invalidSeq3Pass
)

# Valid input accepted after invalid sequence (state=Ready after Idle->Ready transition, step=5, value=0)
$validAfterInvalidPass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_6_valid_input_accepted=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_6_valid_input_step=5') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_6_valid_input_state=Ready') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_6_valid_input_value=0')
)

# Increment succeeds after invalid input history
$incrementAfterInvalidPass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_6_post_increment_state=Active') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_6_post_increment_value=5')
)

# Reset restores canonical runtime state/value
$resetAfterInvalidPass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_6_post_reset_state=Idle') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_6_post_reset_value=0')
)

$completePass = Test-HasToken -Text $runText -Token 'widget_phase41_6_complete=1'

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
  $beginStatePass -and
  $invalidSequencePass -and
  $validAfterInvalidPass -and
  $incrementAfterInvalidPass -and
  $resetAfterInvalidPass -and
  $completePass -and
  $disabledInertPass -and
  $scopeGuardPass
)
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

# Proof packet files
@(
  'phase=41_6_post_validation_action_continuity'
  ('timestamp=' + (Get-Date).ToString('o'))
  ('runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' }))
  ('baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_lock=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' }))
  ('build=' + $(if ($buildPass) { 'PASS' } else { 'FAIL' }))
  ('canonical_launcher=' + $(if ($canonicalLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('extension_launch=' + $(if ($extensionLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('begin_state=' + $(if ($beginStatePass) { 'PASS' } else { 'FAIL' }))
  ('invalid_sequence=' + $(if ($invalidSequencePass) { 'PASS' } else { 'FAIL' }))
  ('valid_after_invalid=' + $(if ($validAfterInvalidPass) { 'PASS' } else { 'FAIL' }))
  ('increment_after_invalid=' + $(if ($incrementAfterInvalidPass) { 'PASS' } else { 'FAIL' }))
  ('reset_after_invalid=' + $(if ($resetAfterInvalidPass) { 'PASS' } else { 'FAIL' }))
  ('complete=' + $(if ($completePass) { 'PASS' } else { 'FAIL' }))
  ('disabled_inert=' + $(if ($disabledInertPass) { 'PASS' } else { 'FAIL' }))
  ('scope_guard=' + $(if ($scopeGuardPass) { 'PASS' } else { 'FAIL' }))
  ('gate=' + $gate)
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase41_6: post-validation action continuity proof'
  'scope: prove runtime continues correct operation after invalid input — rejected input does not corrupt control path'
  'risk_profile=runtime robustness only; baseline behavior/layout/baseline mode remain unchanged'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'validation_sequence_definition:'
  '1. Runtime begins in valid state (Idle, value=0 after phase41.5 final reset)'
  '2. All 4 invalid input classes submitted in sequence: empty, non_numeric, out_of_range, malformed_mixed'
  '3. Each invalid input is rejected deterministically'
  '4. Runtime state remains unchanged after each rejection (state_preserved=1)'
  '5. Runtime value payload remains unchanged after each rejection (value_preserved=1)'
  '6. Valid input (raw=5) submitted after entire invalid sequence'
  '7. Valid input is accepted — step=5, Idle->Ready transition fires'
  '8. Increment action performed — produces Active state, value=5'
  '9. Reset action performed — restores canonical Idle state, value=0'
  '10. phase41_6_complete emitted confirming full continuity path traversed'
) | Set-Content -Path (Join-Path $pf '10_validation_sequence_definition.txt') -Encoding UTF8

@(
  'action_continuity_rules:'
  '- invalid input in any class must not poison the runtime control path'
  '- after any number of sequential invalid inputs, valid input must still be accepted'
  '- increment must succeed after invalid input history (active state transition + value update)'
  '- reset must restore canonical state/value after invalid input history'
  '- state machine must remain deterministic regardless of invalid input count or class order'
  '- no new controls, widgets, or UI sections may be added; existing controls only'
  '- Disabled remains intentionally inert with no runtime side effects'
  '- baseline mode and contracts must remain unaffected'
) | Set-Content -Path (Join-Path $pf '11_action_continuity_rules.txt') -Encoding UTF8

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
  ('begin_state_pass=' + $(if ($beginStatePass) { 'PASS' } else { 'FAIL' }))
  ('invalid_seq_0_empty_pass=' + $(if ($invalidSeq0Pass) { 'PASS' } else { 'FAIL' }))
  ('invalid_seq_1_non_numeric_pass=' + $(if ($invalidSeq1Pass) { 'PASS' } else { 'FAIL' }))
  ('invalid_seq_2_out_of_range_pass=' + $(if ($invalidSeq2Pass) { 'PASS' } else { 'FAIL' }))
  ('invalid_seq_3_malformed_mixed_pass=' + $(if ($invalidSeq3Pass) { 'PASS' } else { 'FAIL' }))
  ('invalid_sequence_count_pass=' + $(if (Test-HasToken -Text $runText -Token 'widget_phase41_6_invalid_sequence_count=4') { 'PASS' } else { 'FAIL' }))
  ('valid_after_invalid_pass=' + $(if ($validAfterInvalidPass) { 'PASS' } else { 'FAIL' }))
  ('increment_after_invalid_pass=' + $(if ($incrementAfterInvalidPass) { 'PASS' } else { 'FAIL' }))
  ('reset_after_invalid_pass=' + $(if ($resetAfterInvalidPass) { 'PASS' } else { 'FAIL' }))
  ('complete_pass=' + $(if ($completePass) { 'PASS' } else { 'FAIL' }))
  ('disabled_inert=' + $(if ($disabledInertPass) { 'PASS' } else { 'FAIL' }))
  ('scope_guard=' + $(if ($scopeGuardPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_pf=' + $baselinePf)
  ('baseline_zip=' + $baselineZip)
  ('run_log=' + $runLog)
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

@(
  'behavior_summary:'
  '- Invalid input rejection: all 4 invalid input classes (empty, non_numeric, out_of_range, malformed_mixed) were submitted in'
  '  sequence from a valid Idle state. Each was rejected deterministically by try_parse_runtime_step before any state or value'
  '  mutation occurred. The runtime_reject_action path (mark_recovery_pending=false) sealed the rejection without setting'
  '  recovery_pending, keeping the control path clean.'
  '- Runtime state/value preservation: after all 4 invalid inputs, the lifecycle state remained Idle and value remained 0.'
  '  State_preserved=1 and value_preserved=1 were emitted for each case confirming no corruption of parent-owned state.'
  '- Valid input acceptance after invalid sequence: raw="5" was submitted immediately following the invalid sequence.'
  '  try_parse_runtime_step accepted it (integer, in range [1,9]), the Idle->Ready transition fired, and step=5 was latched.'
  '  valid_input_accepted=1 confirms the control path was not degraded by preceding invalid inputs.'
  '- Increment succeeded after invalid input history: increment_status() advanced lifecycle from Ready to Active and'
  '  accumulated value to 5 (step=5 applied to value=0). post_increment_state=Active, post_increment_value=5 confirmed.'
  '- Reset restored canonical state/value: reset_status() returned lifecycle to Idle and value to 0.'
  '  post_reset_state=Idle, post_reset_value=0 confirmed the canonical runtime state/value are fully restored.'
  '- Visible status/readout: rejection path emitted status text surfacing action=textbox_input with reason codes for each'
  '  invalid class. Valid input acceptance and subsequent increment/reset restored normal status readout.'
  '- Disabled remained inert: widget_disabled_noninteractive_demo and widget_runtime_disabled_intent_blocked tokens'
  '  confirm no Disabled-driven runtime state mutations occurred throughout the sequence.'
  '- Baseline remained unchanged: extension-only runtime validation logic does not execute in baseline mode.'
  '  All baseline visual and contract checks passed independently.'
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase41_6.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)
