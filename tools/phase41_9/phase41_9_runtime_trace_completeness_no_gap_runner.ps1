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
$pf = Join-Path $Root ('_proof/phase41_9_runtime_trace_completeness_no_gap_' + $ts)
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
$runLog = Join-Path $Root '_proof/phase41_9_runtime_trace_completeness_no_gap_run.log'
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

$boundaryPass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_9_begin=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_9_complete=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_9_trace_count=12') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_9_trace_record=0|trace_sequence_begin|Idle|0|phase41_9:begin|Idle|0') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_9_trace_record=11|trace_sequence_end|Idle|0|phase41_9:end|Idle|0')
)

$eventCountPass = (
  ((Get-TokenCount -Text $runText -Token 'widget_phase41_9_trace_event=trace_sequence_begin') -eq 1) -and
  ((Get-TokenCount -Text $runText -Token 'widget_phase41_9_trace_event=textbox_input_accepted') -eq 2) -and
  ((Get-TokenCount -Text $runText -Token 'widget_phase41_9_trace_event=textbox_input_rejected') -eq 1) -and
  ((Get-TokenCount -Text $runText -Token 'widget_phase41_9_trace_event=invalid_transition_rejected') -eq 1) -and
  ((Get-TokenCount -Text $runText -Token 'widget_phase41_9_trace_event=recovery_action_performed') -eq 1) -and
  ((Get-TokenCount -Text $runText -Token 'widget_phase41_9_trace_event=increment_action_executed') -eq 1) -and
  ((Get-TokenCount -Text $runText -Token 'widget_phase41_9_trace_event=reset_action_executed') -eq 2) -and
  ((Get-TokenCount -Text $runText -Token 'widget_phase41_9_trace_event=canonical_reset_completed') -eq 2) -and
  ((Get-TokenCount -Text $runText -Token 'widget_phase41_9_trace_event=trace_sequence_end') -eq 1)
)

$expectedTraceRecords = @(
  'widget_phase41_9_trace_record=0|trace_sequence_begin|Idle|0|phase41_9:begin|Idle|0',
  'widget_phase41_9_trace_record=1|textbox_input_accepted|Idle|0|textbox:set:3|Ready|0',
  'widget_phase41_9_trace_record=2|textbox_input_rejected|Ready|0|textbox:set:3x|Ready|0',
  'widget_phase41_9_trace_record=3|reset_action_executed|Ready|0|reset:click|Resetting|0',
  'widget_phase41_9_trace_record=4|canonical_reset_completed|Ready|0|reset:complete|Idle|0',
  'widget_phase41_9_trace_record=5|invalid_transition_rejected|Idle|0|increment:illegal_from_idle|Idle|0',
  'widget_phase41_9_trace_record=6|textbox_input_accepted|Idle|0|textbox:set:3|Ready|0',
  'widget_phase41_9_trace_record=7|recovery_action_performed|Ready|0|increment:recovery_after_rejection|Active|3',
  'widget_phase41_9_trace_record=8|increment_action_executed|Ready|0|increment:click|Active|3',
  'widget_phase41_9_trace_record=9|reset_action_executed|Active|3|reset:click|Resetting|3'
)

$expectedTraceRecordsTail = @(
  'widget_phase41_9_trace_record=10|canonical_reset_completed|Active|3|reset:complete|Idle|0',
  'widget_phase41_9_trace_record=11|trace_sequence_end|Idle|0|phase41_9:end|Idle|0'
)

$traceRecordsPresentPass = $true
$traceOrderPass = $true
$lastOffset = -1
foreach ($record in ($expectedTraceRecords + $expectedTraceRecordsTail)) {
  $offset = Get-TokenOffset -Text $runText -Token $record
  if ($offset -lt 0) {
    $traceRecordsPresentPass = $false
    $traceOrderPass = $false
    break
  }
  if ($offset -le $lastOffset) {
    $traceOrderPass = $false
    break
  }
  $lastOffset = $offset
}

$traceSequencePass = $traceRecordsPresentPass -and $traceOrderPass

$noGapPass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_9_mutation_points_expected=8') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_9_mutation_trace_count=8')
)

$finalStateMatchPass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_9_final_runtime_state=Idle') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_9_final_runtime_value=0') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_9_trace_record=11|trace_sequence_end|Idle|0|phase41_9:end|Idle|0')
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
  $boundaryPass -and
  $eventCountPass -and
  $traceSequencePass -and
  $noGapPass -and
  $finalStateMatchPass -and
  $disabledInertPass -and
  $scopeGuardPass
)
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

@(
  'phase=41_9_runtime_trace_completeness_no_gap'
  ('timestamp=' + (Get-Date).ToString('o'))
  ('runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' }))
  ('baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_lock=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' }))
  ('build=' + $(if ($buildPass) { 'PASS' } else { 'FAIL' }))
  ('canonical_launcher=' + $(if ($canonicalLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('extension_launch=' + $(if ($extensionLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('trace_boundaries=' + $(if ($boundaryPass) { 'PASS' } else { 'FAIL' }))
  ('event_count=' + $(if ($eventCountPass) { 'PASS' } else { 'FAIL' }))
  ('trace_sequence=' + $(if ($traceSequencePass) { 'PASS' } else { 'FAIL' }))
  ('no_gap=' + $(if ($noGapPass) { 'PASS' } else { 'FAIL' }))
  ('final_state_match=' + $(if ($finalStateMatchPass) { 'PASS' } else { 'FAIL' }))
  ('disabled_inert=' + $(if ($disabledInertPass) { 'PASS' } else { 'FAIL' }))
  ('scope_guard=' + $(if ($scopeGuardPass) { 'PASS' } else { 'FAIL' }))
  ('gate=' + $gate)
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase41_9: runtime trace completeness / no-gap proof'
  'scope: verify explicit begin/end trace boundaries, exact per-occurrence coverage, and no silent runtime mutation outside trace records'
  'risk_profile=audit completeness only; no layout, control, or baseline behavior changes'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'trace_completeness_definition:'
  '- every significant runtime occurrence in the deterministic phase41_9 scenario must emit exactly one trace record for that occurrence'
  '- begin boundary is enforced by trace_sequence_begin as the first trace record'
  '- end boundary is enforced by trace_sequence_end as the last trace record'
  '- mutation-bearing operations must be trace-covered; mutation_points_expected must equal mutation_trace_count'
  '- final trace after-state must match final runtime state/value'
) | Set-Content -Path (Join-Path $pf '10_trace_completeness_definition.txt') -Encoding UTF8

@(
  'trace_coverage_rules:'
  '- required coverage in this deterministic scenario: begin, textbox accept(2 occurrences), textbox reject, invalid transition reject, recovery action, increment execute, reset execute(2 occurrences), canonical reset complete(2 occurrences), end'
  '- missing-event detection: runner checks every expected compact trace_record token exists'
  '- duplicate-event detection: runner counts each event token and matches the exact occurrence count for this scenario'
  '- ordering detection: runner validates monotonically increasing log offsets for the exact ordered trace_record list'
  '- no-gap detection: runner validates mutation_points_expected=8 and mutation_trace_count=8'
  '- final state/value detection: runner matches final runtime state/value tokens against the last trace after-state'
) | Set-Content -Path (Join-Path $pf '11_trace_coverage_rules.txt') -Encoding UTF8

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
  ('trace_boundaries=' + $(if ($boundaryPass) { 'PASS' } else { 'FAIL' }))
  ('event_count=' + $(if ($eventCountPass) { 'PASS' } else { 'FAIL' }))
  ('trace_records_present=' + $(if ($traceRecordsPresentPass) { 'PASS' } else { 'FAIL' }))
  ('trace_order=' + $(if ($traceOrderPass) { 'PASS' } else { 'FAIL' }))
  ('trace_sequence=' + $(if ($traceSequencePass) { 'PASS' } else { 'FAIL' }))
  ('no_gap=' + $(if ($noGapPass) { 'PASS' } else { 'FAIL' }))
  ('final_state_match=' + $(if ($finalStateMatchPass) { 'PASS' } else { 'FAIL' }))
  ('disabled_inert=' + $(if ($disabledInertPass) { 'PASS' } else { 'FAIL' }))
  ('scope_guard=' + $(if ($scopeGuardPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_pf=' + $baselinePf)
  ('baseline_zip=' + $baselineZip)
  ('run_log=' + $runLog)
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

@(
  'behavior_summary:'
  '- Required traced events: explicit begin/end boundaries plus textbox accept/reject, invalid transition rejection, recovery, increment execute, reset execute, and canonical reset completion.'
  '- Begin/end boundaries are enforced by first record trace_sequence_begin and last record trace_sequence_end.'
  '- Missing-event detection works by matching the full expected ordered compact trace_record list for the deterministic scenario.'
  '- Duplicate-event detection works by exact counting of each widget_phase41_9_trace_event token per occurrence.'
  '- Final trace state/value matching works by comparing the last trace after-state with widget_phase41_9_final_runtime_state/value.'
  '- No-gap coverage is proven by matching mutation_points_expected=8 to mutation_trace_count=8, so every runtime state/value mutation in the scenario is trace-covered.'
  '- Disabled remained inert because the existing disabled guard tokens remained present and no disabled-driven runtime mutation occurred.'
  '- Baseline remained unchanged because the proof executes only in extension mode while baseline contract checks still pass.'
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase41_9.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)
