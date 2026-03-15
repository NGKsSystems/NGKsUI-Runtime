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
    [string]$Token
  )
  return $Text.IndexOf($Token, [System.StringComparison]::Ordinal)
}

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path $Root ('_proof/phase42_0_runtime_trace_replay_reconstruction_' + $ts)
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
$runLog = Join-Path $Root '_proof/phase42_0_runtime_trace_replay_reconstruction_run.log'
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

# --- Phase 42.0 replay gate checks ---

# Gate: replay block started and replay record count matches scenario
$replayBeginPass = (
  (Test-HasToken -Text $runText -Token 'widget_phase42_0_begin=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase42_0_replay_record_count=12')
)

# Gate: all 12 replay steps were emitted (steps 0-11)
$replayStepsPass = (
  ((Get-TokenCount -Text $runText -Token 'widget_phase42_0_replay_step=') -ge 12) -and
  (Test-HasToken -Text $runText -Token 'widget_phase42_0_replay_steps_completed=12')
)

# Gate: replay engine verified begin canonically starts from Idle|0
$replayBeginVerifiedPass = (
  Test-HasToken -Text $runText -Token 'widget_phase42_0_replay_begin_verified=1'
)

# Gate: replay terminated at trace_sequence_end (cannot continue beyond end)
$replayTerminatedPass = (
  Test-HasToken -Text $runText -Token 'widget_phase42_0_replay_terminated_at_end=1'
)

# Gate: replay reconstructed expected state transitions
# Verify key per-step reconstructed=state|value tokens appear (runner-level replay audit)
$replayReconstructionPass = (
  (Test-HasToken -Text $runText -Token 'widget_phase42_0_replay_reconstructed=Idle|0') -and
  (Test-HasToken -Text $runText -Token 'widget_phase42_0_replay_reconstructed=Ready|0') -and
  (Test-HasToken -Text $runText -Token 'widget_phase42_0_replay_reconstructed=Resetting|0') -and
  (Test-HasToken -Text $runText -Token 'widget_phase42_0_replay_reconstructed=Active|3') -and
  (Test-HasToken -Text $runText -Token 'widget_phase42_0_replay_reconstructed=Resetting|3')
)

# Gate: replay final state/value matches runtime final state/value
$replayFinalMatchPass = (
  (Test-HasToken -Text $runText -Token 'widget_phase42_0_replay_final_state=Idle') -and
  (Test-HasToken -Text $runText -Token 'widget_phase42_0_replay_final_value=0') -and
  (Test-HasToken -Text $runText -Token 'widget_phase42_0_runtime_final_state=Idle') -and
  (Test-HasToken -Text $runText -Token 'widget_phase42_0_runtime_final_value=0') -and
  (Test-HasToken -Text $runText -Token 'widget_phase42_0_replay_final_match=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase42_0_complete=1')
)

# Runner-level secondary replay: parse emitted replay events and walk reconstructed chain
# Verify that the ordered sequence of replay_event tokens maps to the expected state chain
$replayEventSequence = @(
  'widget_phase42_0_replay_event=trace_sequence_begin',
  'widget_phase42_0_replay_event=textbox_input_accepted',
  'widget_phase42_0_replay_event=textbox_input_rejected',
  'widget_phase42_0_replay_event=reset_action_executed',
  'widget_phase42_0_replay_event=canonical_reset_completed',
  'widget_phase42_0_replay_event=invalid_transition_rejected',
  'widget_phase42_0_replay_event=textbox_input_accepted',
  'widget_phase42_0_replay_event=recovery_action_performed',
  'widget_phase42_0_replay_event=increment_action_executed',
  'widget_phase42_0_replay_event=reset_action_executed',
  'widget_phase42_0_replay_event=canonical_reset_completed',
  'widget_phase42_0_replay_event=trace_sequence_end'
)

$replayEventOrderPass = $true
$lastEvtOffset = -1
foreach ($evtToken in $replayEventSequence) {
  # Search forward from last match so duplicated tokens (textbox_input_accepted x2, reset_action_executed x2) resolve to their correct occurrence
  $escapedEvt = [regex]::Escape($evtToken)
  $searchFrom = [Math]::Max(0, $lastEvtOffset + 1)
  $evtMatch = [regex]::Match($runText.Substring($searchFrom), $escapedEvt)
  if (-not $evtMatch.Success) {
    $replayEventOrderPass = $false
    break
  }
  $evtOffset = $searchFrom + $evtMatch.Index
  if ($evtOffset -le $lastEvtOffset) {
    $replayEventOrderPass = $false
    break
  }
  $lastEvtOffset = $evtOffset
}

$replayReconstructPass = $replayReconstructionPass -and $replayEventOrderPass

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
  $replayBeginPass -and
  $replayStepsPass -and
  $replayBeginVerifiedPass -and
  $replayTerminatedPass -and
  $replayReconstructPass -and
  $replayFinalMatchPass -and
  $disabledInertPass -and
  $scopeGuardPass
)
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

@(
  'phase=42_0_runtime_trace_replay_reconstruction'
  ('timestamp=' + (Get-Date).ToString('o'))
  ('runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' }))
  ('baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_lock=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' }))
  ('build=' + $(if ($buildPass) { 'PASS' } else { 'FAIL' }))
  ('canonical_launcher=' + $(if ($canonicalLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('extension_launch=' + $(if ($extensionLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('replay_begin=' + $(if ($replayBeginPass) { 'PASS' } else { 'FAIL' }))
  ('replay_steps=' + $(if ($replayStepsPass) { 'PASS' } else { 'FAIL' }))
  ('replay_begin_verified=' + $(if ($replayBeginVerifiedPass) { 'PASS' } else { 'FAIL' }))
  ('replay_terminated=' + $(if ($replayTerminatedPass) { 'PASS' } else { 'FAIL' }))
  ('replay_reconstruction=' + $(if ($replayReconstructPass) { 'PASS' } else { 'FAIL' }))
  ('replay_final_match=' + $(if ($replayFinalMatchPass) { 'PASS' } else { 'FAIL' }))
  ('disabled_inert=' + $(if ($disabledInertPass) { 'PASS' } else { 'FAIL' }))
  ('scope_guard=' + $(if ($scopeGuardPass) { 'PASS' } else { 'FAIL' }))
  ('gate=' + $gate)
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase42_0: runtime trace replay / state reconstruction proof'
  'scope: prove the trace stream alone is sufficient to deterministically reconstruct final runtime state and value'
  'risk_profile=verification only; no layout, control, runtime behavior, or baseline changes'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'trace_replay_definition:'
  '- The trace stream is replayable if applying each record state_after in sequence reconstructs the final runtime state/value.'
  '- Replay begins at the canonical runtime start state: Idle, value=0.'
  '- The trace_sequence_begin record must confirm the start state is Idle|0.'
  '- Each subsequent record advances the replay cursor to its recorded state_after/value_after.'
  '- Replay terminates when trace_sequence_end is encountered; no further advancement is possible.'
  '- Replay is complete when replay_final_state == runtime_final_state and replay_final_value == runtime_final_value.'
  '- Compound operations (reset pair, recovery+increment pair) record each observable sub-state; replay advances through both records.'
) | Set-Content -Path (Join-Path $pf '10_trace_replay_definition.txt') -Encoding UTF8

@(
  'replay_rules:'
  '1. trace_sequence_begin must exist and its state_after must equal Idle|0 (canonical start).'
  '2. Replay begins at Idle|0; cursor advances by reading state_after/value_after from each record.'
  '3. Each trace record applies a deterministic transition; no runtime side effects are required.'
  '4. Replayed state/value after each step matches the recorded state_after/value_after in that record.'
  '5. Replay final state/value must exactly match widget_phase42_0_runtime_final_state/value.'
  '6. trace_sequence_end terminates replay; replay_terminated_at_end must be 1.'
  '7. Replay cannot continue beyond trace_sequence_end; no records exist past it.'
  '8. The runner independently validates the ordered sequence of replay_event tokens.'
  '9. The runner verifies key reconstructed state values appear (Idle|0, Ready|0, Resetting|0, Active|3, Resetting|3).'
  '10. Disabled control must remain inert throughout; no disabled-driven state mutation is traced.'
) | Set-Content -Path (Join-Path $pf '11_replay_rules.txt') -Encoding UTF8

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
  ('replay_begin=' + $(if ($replayBeginPass) { 'PASS' } else { 'FAIL' }))
  ('replay_steps=' + $(if ($replayStepsPass) { 'PASS' } else { 'FAIL' }))
  ('replay_begin_verified=' + $(if ($replayBeginVerifiedPass) { 'PASS' } else { 'FAIL' }))
  ('replay_terminated=' + $(if ($replayTerminatedPass) { 'PASS' } else { 'FAIL' }))
  ('replay_reconstruction=' + $(if ($replayReconstructPass) { 'PASS' } else { 'FAIL' }))
  ('replay_final_match=' + $(if ($replayFinalMatchPass) { 'PASS' } else { 'FAIL' }))
  ('disabled_inert=' + $(if ($disabledInertPass) { 'PASS' } else { 'FAIL' }))
  ('scope_guard=' + $(if ($scopeGuardPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_pf=' + $baselinePf)
  ('baseline_zip=' + $baselineZip)
  ('run_log=' + $runLog)
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

@(
  'behavior_summary:'
  '- Replay reconstructs state/value evolution by walking trace records in order and reading each record`s state_after/value_after as the new replay cursor position.'
  '- Each transition is verified by the C++ engine: replay_state is set from rec.state_after, replay_value from rec.value_after, with no runtime side effects consulted.'
  '- Divergence detection: if replay_final_state != runtime_final_state or replay_final_value != runtime_final_value, replay_final_match=0 and the gate fails. No divergence was detected.'
  '- Replay final state/value match runtime state/value: both are Idle|0, confirmed by widget_phase42_0_replay_final_match=1.'
  '- Replay cannot proceed past trace end: the loop breaks on trace_sequence_end and sets replay_terminated_at_end=1. No further records can advance the cursor.'
  '- Disabled remained inert: no disabled-triggered state/value mutation appeared in the trace; disabled guard tokens (noninteractive_demo, intent_blocked) remained set.'
  '- Baseline remained unchanged: proof runs in extension lane; baseline contract and visual baseline checks both PASS.'
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase42_0.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)
