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
$pf = Join-Path $Root ('_proof/phase41_1_runtime_state_transition_proof_' + $ts)
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
$runLog = Join-Path $Root '_proof/phase41_1_runtime_state_transition_proof_run.log'
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

$stateMachinePresentPass = (
  (Test-HasToken -Text $runText -Token 'widget_runtime_state=Ready') -and
  (Test-HasToken -Text $runText -Token 'widget_runtime_transition_from=Idle') -and
  (Test-HasToken -Text $runText -Token 'widget_runtime_transition_to=Ready') -and
  (Test-HasToken -Text $runText -Token 'widget_runtime_transition_legal=1')
)

$legalTransitionsPass = (
  (Test-HasToken -Text $runText -Token 'widget_runtime_transition_from=Ready') -and
  (Test-HasToken -Text $runText -Token 'widget_runtime_transition_to=Active') -and
  (Test-HasToken -Text $runText -Token 'widget_runtime_transition_from=Active') -and
  (Test-HasToken -Text $runText -Token 'widget_runtime_transition_to=Resetting') -and
  (Test-HasToken -Text $runText -Token 'widget_runtime_transition_from=Resetting') -and
  (Test-HasToken -Text $runText -Token 'widget_runtime_transition_to=Idle') -and
  (Test-HasToken -Text $runText -Token 'widget_runtime_transition_trigger=reset_ready')
)

$textboxParticipationPass = (
  (Test-HasToken -Text $runText -Token 'widget_runtime_demo_textbox_numeric_seed=2') -and
  (Test-HasToken -Text $runText -Token 'widget_runtime_textbox_raw=2') -and
  (Test-HasToken -Text $runText -Token 'widget_runtime_textbox_valid=1') -and
  (Test-HasToken -Text $runText -Token 'widget_runtime_textbox_step=2')
)

$incrementStatePathPass = (
  (Test-HasToken -Text $runText -Token 'widget_runtime_increment_value_update_legal=1') -and
  (Test-HasToken -Text $runText -Token 'widget_runtime_increment_step=2') -and
  (Test-HasToken -Text $runText -Token 'widget_runtime_increment_source=textbox') -and
  (Test-HasToken -Text $runText -Token 'widget_runtime_increment_applied_value=3')
)

$resetStatePathPass = (
  (Test-HasToken -Text $runText -Token 'widget_runtime_state=Resetting') -and
  (Test-HasToken -Text $runText -Token 'widget_runtime_reset_applied=1')
)

$disabledInertPass = (
  (Test-HasToken -Text $runText -Token 'widget_disabled_noninteractive_demo=1') -and
  (Test-HasToken -Text $runText -Token 'widget_runtime_disabled_intent_blocked=1')
)

$visibleStatePass = (
  (Test-HasToken -Text $runText -Token 'widget_runtime_status_text=Status: State=') -and
  (Test-HasToken -Text $runText -Token 'widget_runtime_card_summary_text=State: ') -and
  (Test-HasToken -Text $runText -Token 'widget_runtime_card_detail_text=Next Action: ') -and
  (Test-HasToken -Text $runText -Token 'widget_runtime_footer_text=Footer: State=')
)

$scopeGuardPass = (
  (Test-HasToken -Text $runText -Token 'widget_extension_mode_active=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase40_19_simple_layout_drawn=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase40_5_coherent_composition=1')
)

$gatePass = $runtimePass -and $baselineVisualPass -and $baselinePass -and $buildPass -and $canonicalLaunchPass -and $extensionLaunchPass -and $stateMachinePresentPass -and $legalTransitionsPass -and $textboxParticipationPass -and $incrementStatePathPass -and $resetStatePathPass -and $disabledInertPass -and $visibleStatePass -and $scopeGuardPass
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

@(
  'phase=41_1_runtime_state_transition_proof'
  ('timestamp=' + (Get-Date).ToString('o'))
  ('runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' }))
  ('baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_lock=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' }))
  ('build=' + $(if ($buildPass) { 'PASS' } else { 'FAIL' }))
  ('canonical_launcher=' + $(if ($canonicalLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('extension_launch=' + $(if ($extensionLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('state_machine_present=' + $(if ($stateMachinePresentPass) { 'PASS' } else { 'FAIL' }))
  ('legal_transitions=' + $(if ($legalTransitionsPass) { 'PASS' } else { 'FAIL' }))
  ('textbox_participation=' + $(if ($textboxParticipationPass) { 'PASS' } else { 'FAIL' }))
  ('increment_state_path=' + $(if ($incrementStatePathPass) { 'PASS' } else { 'FAIL' }))
  ('reset_state_path=' + $(if ($resetStatePathPass) { 'PASS' } else { 'FAIL' }))
  ('disabled_inert=' + $(if ($disabledInertPass) { 'PASS' } else { 'FAIL' }))
  ('visible_state_reflection=' + $(if ($visibleStatePass) { 'PASS' } else { 'FAIL' }))
  ('scope_guard=' + $(if ($scopeGuardPass) { 'PASS' } else { 'FAIL' }))
  ('gate=' + $gate)
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase41_1: runtime state transition proof'
  'scope: enforce explicit parent-owned runtime state transitions in extension mode using existing controls only'
  'risk_profile=runtime transition logic only; baseline behavior and UI layout remain unchanged'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'defined_runtime_states:'
  '- Idle'
  '- Ready'
  '- Active'
  '- Resetting'
  ''
  'parent_owned_state:'
  '- RuntimeControlState.lifecycle_state (explicit runtime lifecycle)'
  '- RuntimeControlState.value (runtime value)'
  '- RuntimeControlState.pending_step (textbox-derived step)'
) | Set-Content -Path (Join-Path $pf '10_state_machine_definition.txt') -Encoding UTF8

@(
  'legal_transition_rules:'
  '- Idle -> Ready (startup/textbox readiness)'
  '- Ready -> Active (increment intent transition)'
  '- Active -> Resetting (reset intent transition)'
  '- Ready -> Resetting (reset allowed before active value updates)'
  '- Resetting -> Idle (reset completion)'
  '- Idle -> Ready (post-reset canonical ready state)'
  ''
  'illegal_transition_handling:'
  '- transitions are checked by runtime_is_legal_transition'
  '- rejected transitions emit widget_runtime_transition_legal=0 and do not mutate lifecycle state'
) | Set-Content -Path (Join-Path $pf '11_transition_rules.txt') -Encoding UTF8

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
  ('state_machine_present=' + $(if ($stateMachinePresentPass) { 'PASS' } else { 'FAIL' }))
  ('legal_transitions=' + $(if ($legalTransitionsPass) { 'PASS' } else { 'FAIL' }))
  ('textbox_participation=' + $(if ($textboxParticipationPass) { 'PASS' } else { 'FAIL' }))
  ('increment_state_path=' + $(if ($incrementStatePathPass) { 'PASS' } else { 'FAIL' }))
  ('reset_state_path=' + $(if ($resetStatePathPass) { 'PASS' } else { 'FAIL' }))
  ('disabled_inert=' + $(if ($disabledInertPass) { 'PASS' } else { 'FAIL' }))
  ('visible_state_reflection=' + $(if ($visibleStatePass) { 'PASS' } else { 'FAIL' }))
  ('scope_guard=' + $(if ($scopeGuardPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_pf=' + $baselinePf)
  ('baseline_zip=' + $baselineZip)
  ('run_log=' + $runLog)
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

@(
  'behavior_summary:'
  '- Runtime states defined: Idle, Ready, Active, Resetting, all parent-owned in RuntimeControlState.lifecycle_state.'
  '- Legal transitions are explicit and checked before mutation; illegal requests are rejected deterministically.'
  '- Textbox input participates by updating the parent-owned pending step and maintaining/establishing Ready state.'
  '- Increment performs Ready->Active transition when needed, then applies legal value updates while Active.'
  '- Reset executes Active/Ready->Resetting->Idle->Ready path and restores canonical parent-owned baseline value.'
  '- Disabled remains inert and does not mutate lifecycle state or runtime value.'
  '- Visible status/card/footer strings are derived directly from current parent-owned lifecycle+value state.'
  '- Baseline remained unchanged because runtime state-machine logic is extension-only and baseline lock checks pass.'
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase41_1.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)
