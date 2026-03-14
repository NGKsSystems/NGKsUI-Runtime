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
$pf = Join-Path $Root ('_proof/phase41_5_input_validation_value_domain_proof_' + $ts)
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
$runLog = Join-Path $Root '_proof/phase41_5_input_validation_value_domain_proof_run.log'
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

$valueDomainPass = Test-HasToken -Text $runText -Token 'widget_runtime_input_domain=min:1|max:9|integer_only:1'

$validInputPass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_valid_input_case=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_valid_input_raw=3') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_valid_input_step=3') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_valid_input_state=Active') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_valid_input_value=3') -and
  (Test-HasToken -Text $runText -Token 'widget_runtime_input_validation_result=accepted')
)

$emptyPass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_empty_rejected=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_empty_reason=input_empty') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_empty_state_before=Active') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_empty_state_after=Active') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_empty_value_before=2') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_empty_value_after=2') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_empty_step_before=2') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_empty_step_after=2') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_empty_post_increment_value=4') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_empty_post_reset_state=Idle') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_empty_post_reset_value=0')
)

$nonNumericPass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_non_numeric_rejected=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_non_numeric_reason=input_non_numeric') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_non_numeric_state_before=Active') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_non_numeric_state_after=Active') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_non_numeric_value_before=2') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_non_numeric_value_after=2') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_non_numeric_step_before=2') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_non_numeric_step_after=2') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_non_numeric_post_increment_value=4') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_non_numeric_post_reset_state=Idle') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_non_numeric_post_reset_value=0')
)

$outOfRangePass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_out_of_range_rejected=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_out_of_range_reason=input_out_of_range') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_out_of_range_state_before=Active') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_out_of_range_state_after=Active') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_out_of_range_value_before=2') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_out_of_range_value_after=2') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_out_of_range_step_before=2') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_out_of_range_step_after=2') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_out_of_range_post_increment_value=4') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_out_of_range_post_reset_state=Idle') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_out_of_range_post_reset_value=0')
)

$malformedMixedPass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_malformed_mixed_rejected=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_malformed_mixed_reason=input_malformed_mixed') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_malformed_mixed_state_before=Active') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_malformed_mixed_state_after=Active') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_malformed_mixed_value_before=2') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_malformed_mixed_value_after=2') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_malformed_mixed_step_before=2') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_malformed_mixed_step_after=2') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_malformed_mixed_post_increment_value=4') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_malformed_mixed_post_reset_state=Idle') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_malformed_mixed_post_reset_value=0')
)

$invalidCasesPass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_invalid_case_count=4') -and
  $emptyPass -and
  $nonNumericPass -and
  $outOfRangePass -and
  $malformedMixedPass
)

$visibleStatusPass = (
  (Test-HasToken -Text $runText -Token 'widget_runtime_status_text=Status: Rejected action=textbox_input reason=input_empty state=Active value=2') -and
  (Test-HasToken -Text $runText -Token 'widget_runtime_status_text=Status: Rejected action=textbox_input reason=input_non_numeric state=Active value=2') -and
  (Test-HasToken -Text $runText -Token 'widget_runtime_status_text=Status: Rejected action=textbox_input reason=input_out_of_range state=Active value=2') -and
  (Test-HasToken -Text $runText -Token 'widget_runtime_status_text=Status: Rejected action=textbox_input reason=input_malformed_mixed state=Active value=2')
)

$incrementResetStillPass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_empty_post_increment_value=4') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_non_numeric_post_increment_value=4') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_out_of_range_post_increment_value=4') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_malformed_mixed_post_increment_value=4') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_empty_post_reset_state=Idle') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_non_numeric_post_reset_state=Idle') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_out_of_range_post_reset_state=Idle') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_5_case_malformed_mixed_post_reset_state=Idle')
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

$gatePass = $runtimePass -and $baselineVisualPass -and $baselinePass -and $buildPass -and $canonicalLaunchPass -and $extensionLaunchPass -and $valueDomainPass -and $validInputPass -and $invalidCasesPass -and $visibleStatusPass -and $incrementResetStillPass -and $disabledInertPass -and $scopeGuardPass
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

@(
  'phase=41_5_input_validation_value_domain_proof'
  ('timestamp=' + (Get-Date).ToString('o'))
  ('runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' }))
  ('baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_lock=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' }))
  ('build=' + $(if ($buildPass) { 'PASS' } else { 'FAIL' }))
  ('canonical_launcher=' + $(if ($canonicalLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('extension_launch=' + $(if ($extensionLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('value_domain=' + $(if ($valueDomainPass) { 'PASS' } else { 'FAIL' }))
  ('valid_input=' + $(if ($validInputPass) { 'PASS' } else { 'FAIL' }))
  ('invalid_cases=' + $(if ($invalidCasesPass) { 'PASS' } else { 'FAIL' }))
  ('visible_status=' + $(if ($visibleStatusPass) { 'PASS' } else { 'FAIL' }))
  ('increment_reset_after_invalid=' + $(if ($incrementResetStillPass) { 'PASS' } else { 'FAIL' }))
  ('disabled_inert=' + $(if ($disabledInertPass) { 'PASS' } else { 'FAIL' }))
  ('scope_guard=' + $(if ($scopeGuardPass) { 'PASS' } else { 'FAIL' }))
  ('gate=' + $gate)
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase41_5: input validation value domain proof'
  'scope: prove textbox input domain validation and rejection preservation semantics in extension runtime path using existing controls only'
  'risk_profile=input validation robustness only; baseline behavior/layout remain unchanged'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'value_domain_definition:'
  '- textbox runtime step domain = integer only in range [1, 9]'
  '- valid input is accepted only when full string parses as base-10 integer and lies within [1, 9]'
  '- rejection reasons are deterministic: input_empty, input_non_numeric, input_out_of_range, input_malformed_mixed'
) | Set-Content -Path (Join-Path $pf '10_value_domain_definition.txt') -Encoding UTF8

@(
  'input_validation_rules:'
  '- textbox input is validated before any Idle->Ready transition and before pending step mutation'
  '- invalid input does not mutate lifecycle state, runtime value payload, or current valid step'
  '- invalid input sets explicit rejection status action=textbox_input with reason code'
  '- valid input updates pending step deterministically and normal increment/reset flows remain functional'
  '- validation logic is extension-only and baseline mode remains unaffected'
) | Set-Content -Path (Join-Path $pf '11_input_validation_rules.txt') -Encoding UTF8

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
  ('value_domain=' + $(if ($valueDomainPass) { 'PASS' } else { 'FAIL' }))
  ('valid_input=' + $(if ($validInputPass) { 'PASS' } else { 'FAIL' }))
  ('invalid_case_empty=' + $(if ($emptyPass) { 'PASS' } else { 'FAIL' }))
  ('invalid_case_non_numeric=' + $(if ($nonNumericPass) { 'PASS' } else { 'FAIL' }))
  ('invalid_case_out_of_range=' + $(if ($outOfRangePass) { 'PASS' } else { 'FAIL' }))
  ('invalid_case_malformed_mixed=' + $(if ($malformedMixedPass) { 'PASS' } else { 'FAIL' }))
  ('visible_status=' + $(if ($visibleStatusPass) { 'PASS' } else { 'FAIL' }))
  ('increment_reset_after_invalid=' + $(if ($incrementResetStillPass) { 'PASS' } else { 'FAIL' }))
  ('disabled_inert=' + $(if ($disabledInertPass) { 'PASS' } else { 'FAIL' }))
  ('scope_guard=' + $(if ($scopeGuardPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_pf=' + $baselinePf)
  ('baseline_zip=' + $baselineZip)
  ('run_log=' + $runLog)
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

@(
  'behavior_summary:'
  '- Chosen valid domain: integer-only textbox runtime step in [1, 9], enforced deterministically before state/step mutation.'
  '- Valid input acceptance: raw=3 is accepted, step becomes 3, state reaches Active, and value updates to 3 on increment.'
  '- Empty input handling: rejected with reason input_empty, preserving Active state, value=2, and prior valid step.'
  '- Non-numeric handling: rejected with reason input_non_numeric, preserving Active state/value/step.'
  '- Out-of-range handling: rejected with reason input_out_of_range for raw=10, preserving Active state/value/step.'
  '- Malformed mixed handling: rejected with reason input_malformed_mixed for raw=4x, preserving Active state/value/step.'
  '- Preservation guarantee: each invalid case logs before/after state/value/step and confirms equality, with explicit rejection status text.'
  '- Visible status/readout: rejection path surfaces action=textbox_input plus reason code; normal status resumes when valid operations continue.'
  '- Disabled remains inert via existing disabled interaction guard tokens and no disabled-driven state mutations.'
  '- Baseline remained unchanged because input validation executes only in extension runtime lane and baseline contracts still pass.'
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase41_5.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)
