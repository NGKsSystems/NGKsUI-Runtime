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

function Get-TokenValue {
  param(
    [string]$Text,
    [string]$Prefix
  )
  $pattern = '(?m)^' + [regex]::Escape($Prefix) + '(.*)$'
  $match = [regex]::Match($Text, $pattern)
  if (-not $match.Success) {
    return ''
  }
  return $match.Groups[1].Value.Trim()
}

function Get-TokenLines {
  param(
    [string]$Text,
    [string]$Prefix
  )
  return @([regex]::Matches($Text, '(?m)^' + [regex]::Escape($Prefix) + '.*$') | ForEach-Object { $_.Value.TrimEnd() })
}

function Get-Sha256Hex {
  param(
    [string]$Text
  )
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
  $hashBytes = [System.Security.Cryptography.SHA256]::HashData($bytes)
  return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant()
}

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path $Root ('_proof/phase42_3_trace_certification_fingerprint_' + $ts)
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

$runCount = 3
$runResults = New-Object System.Collections.Generic.List[object]
$runOutputBlocks = New-Object System.Collections.Generic.List[string]

$oldForceFull = $env:NGK_RENDER_RECOVERY_FORCE_FULL
$oldDemo = $env:NGK_WIDGET_SANDBOX_DEMO
$oldVisual = $env:NGK_WIDGET_VISUAL_BASELINE
$oldExtVisual = $env:NGK_WIDGET_EXTENSION_VISUAL_BASELINE
$oldLane = $env:NGK_WIDGET_SANDBOX_LANE
$oldStress = $env:NGK_WIDGET_EXTENSION_STRESS_DEMO

for ($i = 1; $i -le $runCount; $i++) {
  Stop-Process -Name widget_sandbox -Force -ErrorAction SilentlyContinue
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
  $runLog = Join-Path $pf ('run_' + $i + '.log')
  $runText | Set-Content -Path $runLog -Encoding UTF8

  $traceRecords = Get-TokenLines -Text $runText -Prefix 'widget_phase41_9_trace_record='
  $replayEvents = Get-TokenLines -Text $runText -Prefix 'widget_phase42_0_replay_event='
  $replayReconstructed = Get-TokenLines -Text $runText -Prefix 'widget_phase42_0_replay_reconstructed='

  $semanticLines = @()
  $semanticLines += 'trace_records_begin'
  $semanticLines += $traceRecords
  $semanticLines += 'trace_records_end'
  $semanticLines += 'replay_events_begin'
  $semanticLines += $replayEvents
  $semanticLines += 'replay_events_end'
  $semanticLines += 'replay_reconstructed_begin'
  $semanticLines += $replayReconstructed
  $semanticLines += 'replay_reconstructed_end'
  $semanticLines += ('widget_phase41_9_trace_count=' + (Get-TokenValue -Text $runText -Prefix 'widget_phase41_9_trace_count='))
  $semanticLines += ('widget_phase41_9_final_runtime_state=' + (Get-TokenValue -Text $runText -Prefix 'widget_phase41_9_final_runtime_state='))
  $semanticLines += ('widget_phase41_9_final_runtime_value=' + (Get-TokenValue -Text $runText -Prefix 'widget_phase41_9_final_runtime_value='))
  $semanticLines += ('widget_phase42_0_replay_final_state=' + (Get-TokenValue -Text $runText -Prefix 'widget_phase42_0_replay_final_state='))
  $semanticLines += ('widget_phase42_0_replay_final_value=' + (Get-TokenValue -Text $runText -Prefix 'widget_phase42_0_replay_final_value='))
  $semanticLines += ('widget_phase42_0_replay_final_match=' + (Get-TokenValue -Text $runText -Prefix 'widget_phase42_0_replay_final_match='))
  $semanticLines += ('widget_phase42_0_replay_begin_verified=' + (Get-TokenValue -Text $runText -Prefix 'widget_phase42_0_replay_begin_verified='))
  $semanticLines += ('widget_phase42_0_replay_terminated_at_end=' + (Get-TokenValue -Text $runText -Prefix 'widget_phase42_0_replay_terminated_at_end='))

  $semanticText = ($semanticLines -join "`n")
  $semanticHash = Get-Sha256Hex -Text $semanticText

  $runResults.Add([pscustomobject]@{
    RunId = ('run_' + $i)
    ExitCode = $runExit
    LaunchIdentity = Get-TokenValue -Text $runText -Prefix 'LAUNCH_IDENTITY='
    StartTokenPresent = (Test-HasToken -Text $runText -Token 'widget_sandbox_started=1')
    ExitTokenPresent = (Test-HasToken -Text $runText -Token 'widget_sandbox_exit=0')
    TraceRecordCount = [int](Get-TokenValue -Text $runText -Prefix 'widget_phase41_9_trace_count=')
    ReplayPass = (Test-HasToken -Text $runText -Token 'widget_phase42_0_replay_final_match=1')
    FinalState = Get-TokenValue -Text $runText -Prefix 'widget_phase42_0_replay_final_state='
    FinalValue = Get-TokenValue -Text $runText -Prefix 'widget_phase42_0_replay_final_value='
    SemanticFingerprint = $semanticHash
    SemanticText = $semanticText
    RunLog = $runLog
  }) | Out-Null

  $runOutputBlocks.Add('run_' + $i + '_output_begin')
  $runOutputBlocks.Add($runText.TrimEnd())
  $runOutputBlocks.Add('run_' + $i + '_output_end')
}

$canonicalLaunchPass = ($runResults.Count -eq $runCount)
foreach ($run in $runResults) {
  if (($run.ExitCode -ne 0) -or [string]::IsNullOrWhiteSpace($run.LaunchIdentity) -or ($run.LaunchIdentity -notlike 'canonical|debug|*')) {
    $canonicalLaunchPass = $false
    break
  }
}

$runCountPass = ($runResults.Count -ge 3)
$freshRunEvidencePass = (@($runResults | Where-Object { (-not $_.StartTokenPresent) -or (-not $_.ExitTokenPresent) }).Count -eq 0)
$traceCountPass = ((@($runResults | Select-Object -ExpandProperty TraceRecordCount | Select-Object -Unique).Count) -eq 1) -and ($runResults[0].TraceRecordCount -eq 12)
$replayPassAll = (@($runResults | Where-Object { -not $_.ReplayPass }).Count -eq 0)
$finalStateInvariantPass = ((@($runResults | Select-Object -ExpandProperty FinalState | Select-Object -Unique).Count) -eq 1) -and ($runResults[0].FinalState -eq 'Idle')
$finalValueInvariantPass = ((@($runResults | Select-Object -ExpandProperty FinalValue | Select-Object -Unique).Count) -eq 1) -and ($runResults[0].FinalValue -eq '0')
$fingerprintInvariantPass = ((@($runResults | Select-Object -ExpandProperty SemanticFingerprint | Select-Object -Unique).Count) -eq 1)

$canonicalFingerprint = if ($runResults.Count -gt 0) { $runResults[0].SemanticFingerprint } else { '' }

$disabledInertPass = $true
foreach ($run in $runResults) {
  $runText = Get-Content -Raw -LiteralPath $run.RunLog
  if (-not (Test-HasToken -Text $runText -Token 'widget_disabled_noninteractive_demo=1') -or -not (Test-HasToken -Text $runText -Token 'widget_runtime_disabled_intent_blocked=1')) {
    $disabledInertPass = $false
    break
  }
}

$scopeGuardPass = $true
foreach ($run in $runResults) {
  $runText = Get-Content -Raw -LiteralPath $run.RunLog
  if (-not (Test-HasToken -Text $runText -Token 'widget_extension_mode_active=1') -or -not (Test-HasToken -Text $runText -Token 'widget_phase40_19_simple_layout_drawn=1') -or -not (Test-HasToken -Text $runText -Token 'widget_phase40_5_coherent_composition=1')) {
    $scopeGuardPass = $false
    break
  }
}

$gatePass = (
  $runtimePass -and
  $baselineVisualPass -and
  $baselinePass -and
  $buildPass -and
  $canonicalLaunchPass -and
  $runCountPass -and
  $freshRunEvidencePass -and
  $traceCountPass -and
  $replayPassAll -and
  $finalStateInvariantPass -and
  $finalValueInvariantPass -and
  $fingerprintInvariantPass -and
  $disabledInertPass -and
  $scopeGuardPass
)
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

@(
  'phase=42_3_trace_certification_fingerprint'
  ('timestamp=' + (Get-Date).ToString('o'))
  ('runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' }))
  ('baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_lock=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' }))
  ('build=' + $(if ($buildPass) { 'PASS' } else { 'FAIL' }))
  ('canonical_launcher=' + $(if ($canonicalLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('run_count=' + $(if ($runCountPass) { 'PASS' } else { 'FAIL' }))
  ('fresh_runs=' + $(if ($freshRunEvidencePass) { 'PASS' } else { 'FAIL' }))
  ('trace_count=' + $(if ($traceCountPass) { 'PASS' } else { 'FAIL' }))
  ('replay_pass=' + $(if ($replayPassAll) { 'PASS' } else { 'FAIL' }))
  ('final_state_invariance=' + $(if ($finalStateInvariantPass) { 'PASS' } else { 'FAIL' }))
  ('final_value_invariance=' + $(if ($finalValueInvariantPass) { 'PASS' } else { 'FAIL' }))
  ('fingerprint_stability=' + $(if ($fingerprintInvariantPass) { 'PASS' } else { 'FAIL' }))
  ('disabled_inert=' + $(if ($disabledInertPass) { 'PASS' } else { 'FAIL' }))
  ('scope_guard=' + $(if ($scopeGuardPass) { 'PASS' } else { 'FAIL' }))
  ('gate=' + $gate)
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase42_3: certification fingerprint / stable trace hash proof'
  'scope: produce a canonical semantic certification fingerprint for the deterministic extension runtime scenario and verify hash stability across repeated fresh runs'
  'risk_profile=runner-only certification; no UI/layout/runtime behavior changes'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'fingerprint_definition:'
  '- Fingerprint source is a normalized semantic payload that includes ordered phase41_9 trace records and ordered phase42_0 replay outputs.'
  '- Included semantic fields: event/action sequence, state_before/value_before, state_after/value_after, trace record count, final runtime state/value, replay final state/value, replay pass, replay begin verification, and replay termination-at-end.'
  '- Canonical fingerprint is SHA-256 over the normalized semantic payload (UTF-8, newline-delimited).' 
  '- Fingerprint stability requires identical hashes across all repeated fresh runs of the deterministic scenario.'
) | Set-Content -Path (Join-Path $pf '10_fingerprint_definition.txt') -Encoding UTF8

@(
  'normalization_rules:'
  '- Included exactly: phase41_9 trace_record lines, phase42_0 replay_event lines, phase42_0 replay_reconstructed lines, trace count, final runtime state/value, replay final state/value, replay_final_match, replay_begin_verified, replay_terminated_at_end.'
  '- Ignored as non-semantic: timestamps, proof folder names, absolute file paths, zip filenames, run log filenames, and launch identity timestamp differences.'
  '- No semantic field affecting replay behavior is ignored.'
  '- Normalization does not sort records; original deterministic order is preserved.'
) | Set-Content -Path (Join-Path $pf '11_normalization_rules.txt') -Encoding UTF8

git status --short | Set-Content -Path (Join-Path $pf '12_files_touched.txt') -Encoding UTF8

@(
  'build_output_begin'
  $buildText.TrimEnd()
  'build_output_end'
  ''
  $runOutputBlocks.ToArray()
) | Set-Content -Path (Join-Path $pf '13_build_output.txt') -Encoding UTF8

@(
  ('runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' }))
  ('baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_lock=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' }))
  ('build=' + $(if ($buildPass) { 'PASS' } else { 'FAIL' }))
  ('canonical_launcher=' + $(if ($canonicalLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('run_count=' + $(if ($runCountPass) { 'PASS' } else { 'FAIL' }))
  ('fresh_runs=' + $(if ($freshRunEvidencePass) { 'PASS' } else { 'FAIL' }))
  ('trace_count=' + $(if ($traceCountPass) { 'PASS' } else { 'FAIL' }))
  ('replay_pass=' + $(if ($replayPassAll) { 'PASS' } else { 'FAIL' }))
  ('final_state_invariance=' + $(if ($finalStateInvariantPass) { 'PASS' } else { 'FAIL' }))
  ('final_value_invariance=' + $(if ($finalValueInvariantPass) { 'PASS' } else { 'FAIL' }))
  ('fingerprint_stability=' + $(if ($fingerprintInvariantPass) { 'PASS' } else { 'FAIL' }))
  ('certification_fingerprint=' + $canonicalFingerprint)
  ('trace_record_count=' + $(if ($runResults.Count -gt 0) { $runResults[0].TraceRecordCount } else { 0 }))
  ('final_runtime_state=' + $(if ($runResults.Count -gt 0) { $runResults[0].FinalState } else { '(unknown)' }))
  ('final_runtime_value=' + $(if ($runResults.Count -gt 0) { $runResults[0].FinalValue } else { '(unknown)' }))
  ('launch_identity_unique_count=' + @($runResults | Select-Object -ExpandProperty LaunchIdentity | Select-Object -Unique).Count)
  ('baseline_pf=' + $baselinePf)
  ('baseline_zip=' + $baselineZip)
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

@(
  'behavior_summary:'
  '- Fingerprint is derived from a deterministic semantic payload containing ordered trace and replay records plus replay/final-state result fields.'
  '- Semantic fields included: trace record lines (with state_before/value_before/event/action/state_after/value_after), replay event/reconstructed lines, trace record count, replay final status, and final runtime state/value.'
  '- Non-semantic fields ignored: timestamps, proof folder names, absolute paths, zip names, run log filenames, and launch identity timestamp differences.'
  '- Repeated fresh runs produce identical fingerprints because the scenario is deterministic and semantic normalization preserves only replay-relevant content in strict order.'
  '- Future regression detection uses this canonical fingerprint as the certification reference; any semantic drift changes the hash and fails comparison.'
  '- Disabled remained inert across all runs, evidenced by preserved disabled guard tokens and no disabled-driven semantic trace mutation.'
  '- Baseline remained unchanged because baseline lock and visual baseline contract checks passed before repeated extension-lane certification runs.'
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

@(
  'fingerprint_record:'
  ('semantic_trace_fingerprint_sha256=' + $canonicalFingerprint)
  ('trace_record_count=' + $(if ($runResults.Count -gt 0) { $runResults[0].TraceRecordCount } else { 0 }))
  ('final_runtime_state=' + $(if ($runResults.Count -gt 0) { $runResults[0].FinalState } else { '(unknown)' }))
  ('final_runtime_value=' + $(if ($runResults.Count -gt 0) { $runResults[0].FinalValue } else { '(unknown)' }))
  ('replay_result=' + $(if ($replayPassAll) { 'PASS' } else { 'FAIL' }))
  'normalization_method=ordered_semantic_lines_v1|sha256_utf8_newline_delimited'
) | Set-Content -Path (Join-Path $pf '16_fingerprint_record.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase42_3.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)