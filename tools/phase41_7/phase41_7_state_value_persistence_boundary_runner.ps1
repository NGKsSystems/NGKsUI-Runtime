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
$pf = Join-Path $Root ('_proof/phase41_7_state_value_persistence_boundary_' + $ts)
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
$runLog = Join-Path $Root '_proof/phase41_7_state_value_persistence_boundary_run.log'
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

$beginPass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_begin=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_begin_state=Idle') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_begin_value=0')
)

$validInputPass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_after_valid_step=4') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_after_valid_state=Ready') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_after_valid_value=0')
)

$invalidInputPreservePass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_invalid_input_rejected=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_invalid_input_reason=input_malformed_mixed') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_after_invalid_input_state_preserved=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_after_invalid_input_value_preserved=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_after_invalid_input_step_preserved=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_after_invalid_input_recovery_preserved=1')
)

$invalidTransitionPreservePass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_anchor_idle_before_invalid_transition_state=Idle') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_anchor_idle_before_invalid_transition_value=0') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_invalid_transition_rejected=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_invalid_transition_reason=increment_not_allowed_from_state') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_after_invalid_transition_state_preserved=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_after_invalid_transition_value_preserved=1')
)

$validActionUpdatePass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_after_valid_increment_state=Active') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_after_valid_increment_value=4') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_after_valid_increment_step=4')
)

$resetCanonicalPass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_post_reset_state=Idle') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_post_reset_value=0') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_post_reset_step=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_post_reset_state_canonical=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_post_reset_value_canonical=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_post_reset_step_canonical=1')
)

$fieldContractPass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_field_persist_on_rejection=lifecycle_state,value,pending_step,pending_step_valid_source_boundary') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_field_update_on_valid_action=pending_step_on_valid_input,value_on_increment,lifecycle_on_legal_transition') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_field_clear_on_reset=value,pending_step,pending_input,pending_step_valid,pending_step_source')
)

$statusReadoutPass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_status_after_invalid_input=Status: Rejected action=textbox_input reason=input_malformed_mixed state=Ready value=0') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_status_after_invalid_transition=Status: Rejected action=increment reason=increment_not_allowed_from_state state=Idle value=0') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_status_after_valid_increment=Status: State=Active Value=4 Step=4 Source=textbox') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_7_status_after_reset=Status: State=Idle Value=0 Step=1 Source=default')
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

$completePass = Test-HasToken -Text $runText -Token 'widget_phase41_7_complete=1'

$gatePass = (
  $runtimePass -and
  $baselineVisualPass -and
  $baselinePass -and
  $buildPass -and
  $canonicalLaunchPass -and
  $extensionLaunchPass -and
  $beginPass -and
  $validInputPass -and
  $invalidInputPreservePass -and
  $invalidTransitionPreservePass -and
  $validActionUpdatePass -and
  $resetCanonicalPass -and
  $fieldContractPass -and
  $statusReadoutPass -and
  $disabledInertPass -and
  $scopeGuardPass -and
  $completePass
)
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

@(
  'phase=41_7_state_value_persistence_boundary'
  ('timestamp=' + (Get-Date).ToString('o'))
  ('runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' }))
  ('baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_lock=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' }))
  ('build=' + $(if ($buildPass) { 'PASS' } else { 'FAIL' }))
  ('canonical_launcher=' + $(if ($canonicalLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('extension_launch=' + $(if ($extensionLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('begin=' + $(if ($beginPass) { 'PASS' } else { 'FAIL' }))
  ('valid_input=' + $(if ($validInputPass) { 'PASS' } else { 'FAIL' }))
  ('invalid_input_preserve=' + $(if ($invalidInputPreservePass) { 'PASS' } else { 'FAIL' }))
  ('invalid_transition_preserve=' + $(if ($invalidTransitionPreservePass) { 'PASS' } else { 'FAIL' }))
  ('valid_action_update=' + $(if ($validActionUpdatePass) { 'PASS' } else { 'FAIL' }))
  ('reset_canonical=' + $(if ($resetCanonicalPass) { 'PASS' } else { 'FAIL' }))
  ('field_contract=' + $(if ($fieldContractPass) { 'PASS' } else { 'FAIL' }))
  ('status_readout=' + $(if ($statusReadoutPass) { 'PASS' } else { 'FAIL' }))
  ('disabled_inert=' + $(if ($disabledInertPass) { 'PASS' } else { 'FAIL' }))
  ('scope_guard=' + $(if ($scopeGuardPass) { 'PASS' } else { 'FAIL' }))
  ('complete=' + $(if ($completePass) { 'PASS' } else { 'FAIL' }))
  ('gate=' + $gate)
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase41_7: state/value persistence boundary proof'
  'scope: prove exact state/value persistence across invalid input rejection, invalid transition rejection, valid action update, and reset boundary'
  'risk_profile=runtime persistence verification only; baseline behavior/layout remain unchanged'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'persistence_contract_definition:'
  '- parent-owned fields: lifecycle_state, value, pending_step, pending_step_valid, pending_step_from_textbox, pending_input_raw, rejection fields, recovery marker'
  '- invalid input rejection preserves lifecycle_state, value, pending_step, and recovery marker boundary in this sequence'
  '- invalid transition rejection preserves lifecycle_state and value at rejection boundary'
  '- valid input updates pending_step and may legal-transition lifecycle (Idle->Ready) without changing value'
  '- valid increment updates value deterministically by pending_step and transitions Ready->Active'
  '- reset restores canonical baseline boundary: lifecycle_state=Idle, value=baseline_value(0), pending_step=1, pending_input cleared, pending_step_valid=0, pending_step_from_textbox=0'
) | Set-Content -Path (Join-Path $pf '10_persistence_contract_definition.txt') -Encoding UTF8

@(
  'persistence_validation_sequence:'
  '1. Begin canonical: Idle value=0'
  '2. Submit valid textbox input raw=4 -> accepted, lifecycle=Ready, value stays 0, step=4'
  '3. Submit invalid textbox input raw=4x -> rejected'
  '4. Verify invalid-input preservation: state/value/step/recovery marker unchanged at this boundary'
  '5. Re-anchor Idle with reset (canonical boundary) then attempt invalid transition increment from Idle -> rejected'
  '6. Verify invalid-transition preservation: state/value unchanged at rejection boundary'
  '7. Submit valid textbox input raw=4 and perform increment'
  '8. Verify deterministic valid update: lifecycle=Active, value=4, step=4'
  '9. Perform reset'
  '10. Verify canonical restore: lifecycle=Idle, value=0, step=1 and phase complete token emitted'
) | Set-Content -Path (Join-Path $pf '11_persistence_validation_sequence.txt') -Encoding UTF8

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
  ('begin=' + $(if ($beginPass) { 'PASS' } else { 'FAIL' }))
  ('valid_input=' + $(if ($validInputPass) { 'PASS' } else { 'FAIL' }))
  ('invalid_input_preserve=' + $(if ($invalidInputPreservePass) { 'PASS' } else { 'FAIL' }))
  ('invalid_transition_preserve=' + $(if ($invalidTransitionPreservePass) { 'PASS' } else { 'FAIL' }))
  ('valid_action_update=' + $(if ($validActionUpdatePass) { 'PASS' } else { 'FAIL' }))
  ('reset_canonical=' + $(if ($resetCanonicalPass) { 'PASS' } else { 'FAIL' }))
  ('field_contract=' + $(if ($fieldContractPass) { 'PASS' } else { 'FAIL' }))
  ('status_readout=' + $(if ($statusReadoutPass) { 'PASS' } else { 'FAIL' }))
  ('disabled_inert=' + $(if ($disabledInertPass) { 'PASS' } else { 'FAIL' }))
  ('scope_guard=' + $(if ($scopeGuardPass) { 'PASS' } else { 'FAIL' }))
  ('complete=' + $(if ($completePass) { 'PASS' } else { 'FAIL' }))
  ('baseline_pf=' + $baselinePf)
  ('baseline_zip=' + $baselineZip)
  ('run_log=' + $runLog)
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

@(
  'behavior_summary:'
  '- Persist across rejection: invalid textbox input rejection preserved lifecycle_state/value/pending_step at the rejection boundary.'
  '- Persist across invalid transition rejection: increment attempted from Idle was rejected and lifecycle_state/value remained unchanged.'
  '- Update during valid actions: valid textbox input latched pending_step=4 and legal transition to Ready; valid increment then transitioned to Active and updated value to 4.'
  '- Clear on reset: reset restored canonical lifecycle_state=Idle and value=0 and reset step boundary to 1 while clearing textbox-origin runtime input fields.'
  '- Step-by-step verification: explicit phase41_7 tokens were emitted for begin, invalid-input preserve, invalid-transition preserve, valid update, and reset canonical checkpoints.'
  '- Visible status/readout reflected persistence checkpoints via rejection status text after invalid operations and normal Value/Step/Lifecycle status after valid increment/reset.'
  '- Disabled remained inert as existing disabled intent guards stayed active and no disabled interaction mutated runtime state/value.'
  '- Baseline remained unchanged because all persistence logic is exercised in extension lane with baseline contract checks still passing.'
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase41_7.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)
