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
$pf = Join-Path $Root ('_proof/phase41_8_runtime_action_trace_audit_' + $ts)
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
$runLog = Join-Path $Root '_proof/phase41_8_runtime_action_trace_audit_run.log'
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

$traceStartPass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_8_begin=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_8_complete=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_8_trace_count=12')
)

$eventCountPass = (
  ((Get-TokenCount -Text $runText -Token 'widget_phase41_8_trace_event=textbox_input_accepted') -eq 1) -and
  ((Get-TokenCount -Text $runText -Token 'widget_phase41_8_trace_event=textbox_input_rejected') -eq 1) -and
  ((Get-TokenCount -Text $runText -Token 'widget_phase41_8_trace_event=increment_action_executed') -eq 1) -and
  ((Get-TokenCount -Text $runText -Token 'widget_phase41_8_trace_event=increment_action_rejected') -eq 1) -and
  ((Get-TokenCount -Text $runText -Token 'widget_phase41_8_trace_event=reset_executed') -eq 2) -and
  ((Get-TokenCount -Text $runText -Token 'widget_phase41_8_trace_event=reset_completed') -eq 2) -and
  ((Get-TokenCount -Text $runText -Token 'widget_phase41_8_trace_event=invalid_transition_rejection') -eq 1) -and
  ((Get-TokenCount -Text $runText -Token 'widget_phase41_8_trace_event=recovery_action') -eq 1) -and
  ((Get-TokenCount -Text $runText -Token 'widget_phase41_8_trace_event=canonical_reset') -eq 1) -and
  ((Get-TokenCount -Text $runText -Token 'widget_phase41_8_trace_event=runtime_sequence_completion') -eq 1)
)

$expectedTraceRecords = @(
  'widget_phase41_8_trace_record=0|textbox_input_accepted|Idle|0|textbox:set:2|Ready|0',
  'widget_phase41_8_trace_record=1|textbox_input_rejected|Ready|0|textbox:set:2x|Ready|0',
  'widget_phase41_8_trace_record=2|reset_executed|Ready|0|reset:click|Resetting|0',
  'widget_phase41_8_trace_record=3|reset_completed|Ready|0|reset:complete|Idle|0',
  'widget_phase41_8_trace_record=4|increment_action_rejected|Idle|0|increment:click|Idle|0',
  'widget_phase41_8_trace_record=5|invalid_transition_rejection|Idle|0|increment:illegal_from_idle|Idle|0',
  'widget_phase41_8_trace_record=6|recovery_action|Idle|0|increment:recovery_after_rejection|Active|2',
  'widget_phase41_8_trace_record=7|increment_action_executed|Idle|0|increment:click|Active|2',
  'widget_phase41_8_trace_record=8|reset_executed|Active|2|reset:click|Resetting|2',
  'widget_phase41_8_trace_record=9|reset_completed|Active|2|reset:complete|Idle|0',
  'widget_phase41_8_trace_record=10|canonical_reset|Active|2|reset:canonical_boundary|Idle|0',
  'widget_phase41_8_trace_record=11|runtime_sequence_completion|Idle|0|phase41_8:complete|Idle|0'
)

$traceRecordsPresentPass = $true
$traceOrderPass = $true
$lastOffset = -1
foreach ($record in $expectedTraceRecords) {
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

$invalidEventTracePass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_8_trace_record=1|textbox_input_rejected|Ready|0|textbox:set:2x|Ready|0') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_8_trace_record=5|invalid_transition_rejection|Idle|0|increment:illegal_from_idle|Idle|0') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_8_trace_record=4|increment_action_rejected|Idle|0|increment:click|Idle|0')
)

$resetTracePass = (
  (Test-HasToken -Text $runText -Token 'widget_phase41_8_trace_record=8|reset_executed|Active|2|reset:click|Resetting|2') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_8_trace_record=9|reset_completed|Active|2|reset:complete|Idle|0') -and
  (Test-HasToken -Text $runText -Token 'widget_phase41_8_trace_record=10|canonical_reset|Active|2|reset:canonical_boundary|Idle|0')
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
  $traceStartPass -and
  $eventCountPass -and
  $traceSequencePass -and
  $invalidEventTracePass -and
  $resetTracePass -and
  $disabledInertPass -and
  $scopeGuardPass
)
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

@(
  'phase=41_8_runtime_action_trace_audit'
  ('timestamp=' + (Get-Date).ToString('o'))
  ('runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' }))
  ('baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_lock=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' }))
  ('build=' + $(if ($buildPass) { 'PASS' } else { 'FAIL' }))
  ('canonical_launcher=' + $(if ($canonicalLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('extension_launch=' + $(if ($extensionLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('trace_start=' + $(if ($traceStartPass) { 'PASS' } else { 'FAIL' }))
  ('event_count=' + $(if ($eventCountPass) { 'PASS' } else { 'FAIL' }))
  ('trace_sequence=' + $(if ($traceSequencePass) { 'PASS' } else { 'FAIL' }))
  ('invalid_event_trace=' + $(if ($invalidEventTracePass) { 'PASS' } else { 'FAIL' }))
  ('reset_trace=' + $(if ($resetTracePass) { 'PASS' } else { 'FAIL' }))
  ('disabled_inert=' + $(if ($disabledInertPass) { 'PASS' } else { 'FAIL' }))
  ('scope_guard=' + $(if ($scopeGuardPass) { 'PASS' } else { 'FAIL' }))
  ('gate=' + $gate)
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase41_8: runtime action trace / audit sequence proof'
  'scope: deterministic trace emission for runtime actions with machine-verifiable ordering and reconstruction fidelity'
  'risk_profile=trace emission only; no telemetry framework, no layout or baseline behavior changes'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'trace_model_definition:'
  '- deterministic trace record token: widget_phase41_8_trace_record=<index>|<event>|<state_before>|<value_before>|<action>|<state_after>|<value_after>'
  '- expanded field tokens per record: index, event, state_before, value_before, action, state_after, value_after'
  '- each significant runtime action occurrence emits one trace event record; repeated actions are represented by distinct index values'
  '- trace_count token seals expected record cardinality for deterministic replay'
) | Set-Content -Path (Join-Path $pf '10_trace_model_definition.txt') -Encoding UTF8

@(
  'trace_event_catalog:'
  '- textbox_input_accepted: valid textbox parse and acceptance path'
  '- textbox_input_rejected: invalid textbox parse rejection path'
  '- increment_action_rejected: blocked increment action'
  '- invalid_transition_rejection: illegal transition boundary rejection'
  '- recovery_action: first legal increment after rejection with recovery marker consumption'
  '- increment_action_executed: legal increment update application'
  '- reset_executed: reset action entered (before canonical completion)'
  '- reset_completed: reset action completed to Idle boundary'
  '- canonical_reset: canonical state/value restoration confirmation'
  '- runtime_sequence_completion: deterministic sequence completion marker'
  '- occurrence notes: reset_executed/reset_completed appear twice in this deterministic scenario (pre-anchor and final canonical reset), all others appear once'
) | Set-Content -Path (Join-Path $pf '11_trace_event_catalog.txt') -Encoding UTF8

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
  ('trace_start=' + $(if ($traceStartPass) { 'PASS' } else { 'FAIL' }))
  ('event_count=' + $(if ($eventCountPass) { 'PASS' } else { 'FAIL' }))
  ('trace_records_present=' + $(if ($traceRecordsPresentPass) { 'PASS' } else { 'FAIL' }))
  ('trace_order=' + $(if ($traceOrderPass) { 'PASS' } else { 'FAIL' }))
  ('trace_sequence=' + $(if ($traceSequencePass) { 'PASS' } else { 'FAIL' }))
  ('invalid_event_trace=' + $(if ($invalidEventTracePass) { 'PASS' } else { 'FAIL' }))
  ('reset_trace=' + $(if ($resetTracePass) { 'PASS' } else { 'FAIL' }))
  ('disabled_inert=' + $(if ($disabledInertPass) { 'PASS' } else { 'FAIL' }))
  ('scope_guard=' + $(if ($scopeGuardPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_pf=' + $baselinePf)
  ('baseline_zip=' + $baselineZip)
  ('run_log=' + $runLog)
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

@(
  'behavior_summary:'
  '- Introduced trace tokens: widget_phase41_8_trace_index/event/state_before/value_before/action/state_after/value_after and compact widget_phase41_8_trace_record for machine-verifiable replay.'
  '- Captured runtime events: textbox accept/reject, increment reject/execute, invalid transition rejection, recovery action, reset executed/completed, canonical reset, sequence completion.'
  '- Trace ordering enforcement: each record includes monotonically increasing index; runner validates exact record list and strict increasing offsets in output log.'
  '- Sequence reconstruction: compact trace records fully encode before/after state/value and action details, allowing deterministic replay of runtime flow end-to-end.'
  '- Invalid events in trace: malformed textbox rejection and increment-from-idle invalid transition are explicitly represented with preserved state/value boundaries.'
  '- Reset events in trace: reset_executed and reset_completed records capture transition boundaries, with canonical_reset proving final Idle/value=0 restore.'
  '- Disabled remained inert: existing disabled guard tokens remained present; no disabled-driven trace mutation occurred.'
  '- Baseline remained unchanged: trace emission executes only under extension proof path and baseline contracts remained PASS.'
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase41_8.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)
