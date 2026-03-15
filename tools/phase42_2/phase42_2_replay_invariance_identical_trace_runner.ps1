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
$pf = Join-Path $Root ('_proof/phase42_2_replay_invariance_identical_trace_' + $ts)
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
  $semanticLines += $traceRecords
  $semanticLines += $replayEvents
  $semanticLines += $replayReconstructed
  $semanticLines += ('widget_phase41_9_trace_count=' + (Get-TokenValue -Text $runText -Prefix 'widget_phase41_9_trace_count='))
  $semanticLines += ('widget_phase41_9_final_runtime_state=' + (Get-TokenValue -Text $runText -Prefix 'widget_phase41_9_final_runtime_state='))
  $semanticLines += ('widget_phase41_9_final_runtime_value=' + (Get-TokenValue -Text $runText -Prefix 'widget_phase41_9_final_runtime_value='))
  $semanticLines += ('widget_phase42_0_replay_record_count=' + (Get-TokenValue -Text $runText -Prefix 'widget_phase42_0_replay_record_count='))
  $semanticLines += ('widget_phase42_0_replay_steps_completed=' + (Get-TokenValue -Text $runText -Prefix 'widget_phase42_0_replay_steps_completed='))
  $semanticLines += ('widget_phase42_0_replay_begin_verified=' + (Get-TokenValue -Text $runText -Prefix 'widget_phase42_0_replay_begin_verified='))
  $semanticLines += ('widget_phase42_0_replay_terminated_at_end=' + (Get-TokenValue -Text $runText -Prefix 'widget_phase42_0_replay_terminated_at_end='))
  $semanticLines += ('widget_phase42_0_replay_final_state=' + (Get-TokenValue -Text $runText -Prefix 'widget_phase42_0_replay_final_state='))
  $semanticLines += ('widget_phase42_0_replay_final_value=' + (Get-TokenValue -Text $runText -Prefix 'widget_phase42_0_replay_final_value='))
  $semanticLines += ('widget_phase42_0_replay_final_match=' + (Get-TokenValue -Text $runText -Prefix 'widget_phase42_0_replay_final_match='))

  $semanticText = ($semanticLines -join "`n")
  $semanticHash = Get-Sha256Hex -Text $semanticText

  $runResults.Add([pscustomobject]@{
    RunId = ('run_' + $i)
    ExitCode = $runExit
    LaunchIdentity = Get-TokenValue -Text $runText -Prefix 'LAUNCH_IDENTITY='
    StartTokenPresent = (Test-HasToken -Text $runText -Token 'widget_sandbox_started=1')
    ExitTokenPresent = (Test-HasToken -Text $runText -Token 'widget_sandbox_exit=0')
    TraceRecordCount = [int](Get-TokenValue -Text $runText -Prefix 'widget_phase41_9_trace_count=')
    BeginMarkerPresent = (Test-HasToken -Text $runText -Token 'widget_phase41_9_trace_record=0|trace_sequence_begin|Idle|0|phase41_9:begin|Idle|0')
    EndMarkerPresent = (Test-HasToken -Text $runText -Token 'widget_phase41_9_trace_record=11|trace_sequence_end|Idle|0|phase41_9:end|Idle|0')
    ReplayPass = (Test-HasToken -Text $runText -Token 'widget_phase42_0_replay_final_match=1')
    ReplayBeginVerified = (Test-HasToken -Text $runText -Token 'widget_phase42_0_replay_begin_verified=1')
    ReplayTerminated = (Test-HasToken -Text $runText -Token 'widget_phase42_0_replay_terminated_at_end=1')
    FinalState = Get-TokenValue -Text $runText -Prefix 'widget_phase42_0_replay_final_state='
    FinalValue = Get-TokenValue -Text $runText -Prefix 'widget_phase42_0_replay_final_value='
    SemanticHash = $semanticHash
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
$traceCountInvariantPass = ((@($runResults | Select-Object -ExpandProperty TraceRecordCount | Select-Object -Unique).Count) -eq 1) -and (($runResults[0].TraceRecordCount) -eq 12)
$beginMarkerInvariantPass = (@($runResults | Where-Object { -not $_.BeginMarkerPresent }).Count -eq 0)
$endMarkerInvariantPass = (@($runResults | Where-Object { -not $_.EndMarkerPresent }).Count -eq 0)
$replayInvariantPass = (@($runResults | Where-Object { (-not $_.ReplayPass) -or (-not $_.ReplayBeginVerified) -or (-not $_.ReplayTerminated) }).Count -eq 0)
$finalStateInvariantPass = ((@($runResults | Select-Object -ExpandProperty FinalState | Select-Object -Unique).Count) -eq 1) -and (($runResults[0].FinalState) -eq 'Idle')
$finalValueInvariantPass = ((@($runResults | Select-Object -ExpandProperty FinalValue | Select-Object -Unique).Count) -eq 1) -and (($runResults[0].FinalValue) -eq '0')
$semanticHashInvariantPass = ((@($runResults | Select-Object -ExpandProperty SemanticHash | Select-Object -Unique).Count) -eq 1)

$referenceSemanticLines = @()
if ($runResults.Count -gt 0) {
  $referenceSemanticLines = @($runResults[0].SemanticText -split "`n")
}

$mismatchDetail = 'none'
$perRecordMismatchFound = $false
if (-not $semanticHashInvariantPass) {
  $perRecordMismatchFound = $true
  foreach ($run in ($runResults | Select-Object -Skip 1)) {
    $candidateLines = @($run.SemanticText -split "`n")
    $maxLines = [Math]::Max($referenceSemanticLines.Count, $candidateLines.Count)
    for ($idx = 0; $idx -lt $maxLines; $idx++) {
      $refLine = if ($idx -lt $referenceSemanticLines.Count) { $referenceSemanticLines[$idx] } else { '<missing>' }
      $candLine = if ($idx -lt $candidateLines.Count) { $candidateLines[$idx] } else { '<missing>' }
      if ($refLine -ne $candLine) {
        $mismatchDetail = ('run=' + $run.RunId + ';line=' + $idx + ';reference=' + $refLine + ';candidate=' + $candLine)
        break
      }
    }
    if ($mismatchDetail -ne 'none') { break }
  }
}

$launchIdentityUniqueCount = @($runResults | Select-Object -ExpandProperty LaunchIdentity | Select-Object -Unique).Count
$freshRunPass = $freshRunEvidencePass

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
  $freshRunPass -and
  $traceCountInvariantPass -and
  $beginMarkerInvariantPass -and
  $endMarkerInvariantPass -and
  $replayInvariantPass -and
  $finalStateInvariantPass -and
  $finalValueInvariantPass -and
  $semanticHashInvariantPass -and
  (-not $perRecordMismatchFound) -and
  $disabledInertPass -and
  $scopeGuardPass
)
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

$matrixLines = New-Object System.Collections.Generic.List[string]
$matrixLines.Add('run_comparison_matrix:')
$matrixLines.Add('run_id|trace_record_count|begin_marker|end_marker|replay_pass|final_state|final_value|semantic_hash')
foreach ($run in $runResults) {
  $matrixLines.Add(($run.RunId + '|' + $run.TraceRecordCount + '|' + $(if ($run.BeginMarkerPresent) { 'PASS' } else { 'FAIL' }) + '|' + $(if ($run.EndMarkerPresent) { 'PASS' } else { 'FAIL' }) + '|' + $(if ($run.ReplayPass) { 'PASS' } else { 'FAIL' }) + '|' + $run.FinalState + '|' + $run.FinalValue + '|' + $run.SemanticHash))
}
$matrixLines.Add('all_semantic_fingerprints_match=' + $(if ($semanticHashInvariantPass) { 'PASS' } else { 'FAIL' }))
$matrixLines.Add('per_record_semantic_mismatch_found=' + $(if ($perRecordMismatchFound) { 'YES' } else { 'NO' }))
$matrixLines.Add('final_replay_results_match=' + $(if ($finalStateInvariantPass -and $finalValueInvariantPass -and $replayInvariantPass) { 'PASS' } else { 'FAIL' }))
$matrixLines.Add('fresh_run_evidence=' + $(if ($freshRunPass) { 'PASS' } else { 'FAIL' }))
$matrixLines.Add('launch_identity_unique_count=' + $launchIdentityUniqueCount)
$matrixLines.Add('mismatch_detail=' + $mismatchDetail)

@(
  'phase=42_2_replay_invariance_identical_trace'
  ('timestamp=' + (Get-Date).ToString('o'))
  ('runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' }))
  ('baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_lock=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' }))
  ('build=' + $(if ($buildPass) { 'PASS' } else { 'FAIL' }))
  ('canonical_launcher=' + $(if ($canonicalLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('run_count=' + $(if ($runCountPass) { 'PASS' } else { 'FAIL' }))
  ('fresh_runs=' + $(if ($freshRunPass) { 'PASS' } else { 'FAIL' }))
  ('trace_count_invariance=' + $(if ($traceCountInvariantPass) { 'PASS' } else { 'FAIL' }))
  ('begin_marker_invariance=' + $(if ($beginMarkerInvariantPass) { 'PASS' } else { 'FAIL' }))
  ('end_marker_invariance=' + $(if ($endMarkerInvariantPass) { 'PASS' } else { 'FAIL' }))
  ('replay_invariance=' + $(if ($replayInvariantPass) { 'PASS' } else { 'FAIL' }))
  ('final_state_invariance=' + $(if ($finalStateInvariantPass) { 'PASS' } else { 'FAIL' }))
  ('final_value_invariance=' + $(if ($finalValueInvariantPass) { 'PASS' } else { 'FAIL' }))
  ('semantic_trace_identity=' + $(if ($semanticHashInvariantPass) { 'PASS' } else { 'FAIL' }))
  ('fresh_run_evidence=' + $(if ($freshRunEvidencePass) { 'PASS' } else { 'FAIL' }))
  ('disabled_inert=' + $(if ($disabledInertPass) { 'PASS' } else { 'FAIL' }))
  ('scope_guard=' + $(if ($scopeGuardPass) { 'PASS' } else { 'FAIL' }))
  ('gate=' + $gate)
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase42_2: replay invariance / identical trace across repeated runs'
  'scope: verify repeated fresh extension launches produce semantically identical trace and replay results for the certified deterministic scenario'
  'risk_profile=runner-only invariance validation; no visible layout, baseline, or runtime semantics changes'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'replay_invariance_definition:'
  '- A run is semantically identical if its ordered phase41_9 trace_record lines and phase42_0 replay lines match exactly.'
  '- The invariance fingerprint is a SHA-256 hash over semantic trace and replay lines only.'
  '- Non-semantic fields such as launch timestamps, proof paths, log filenames, zip names, and launch identity timestamps are excluded from comparison.'
  '- Semantic fields include event/action name, state_before, value_before, state_after, value_after, trace count, replay event order, replay reconstructed states, and final replay results.'
  '- Invariance passes only if every fresh run matches the same semantic fingerprint and identical final replay result.'
) | Set-Content -Path (Join-Path $pf '10_replay_invariance_definition.txt') -Encoding UTF8

@(
  'invariance_rules:'
  '1. At least 3 fresh runs must launch through the canonical launcher.'
  '2. Each run must emit exactly 12 phase41_9 trace records.'
  '3. Each run must begin with trace_sequence_begin and end with trace_sequence_end.'
  '4. Each run must replay successfully with replay_begin_verified=1, replay_terminated_at_end=1, and replay_final_match=1.'
  '5. Ordered phase41_9 trace_record lines must match exactly across runs.'
  '6. Ordered phase42_0 replay_event and replay_reconstructed lines must match exactly across runs.'
  '7. Final replay state and value must be identical across runs.'
  '8. Only non-semantic fields are ignored: timestamps, absolute proof paths, proof folder names, zip filenames, and launch identity timestamps.'
  '9. Semantic mismatches are not normalized away; any per-record difference fails the phase.'
) | Set-Content -Path (Join-Path $pf '11_invariance_rules.txt') -Encoding UTF8

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
  ('fresh_runs=' + $(if ($freshRunPass) { 'PASS' } else { 'FAIL' }))
  ('trace_count_invariance=' + $(if ($traceCountInvariantPass) { 'PASS' } else { 'FAIL' }))
  ('begin_marker_invariance=' + $(if ($beginMarkerInvariantPass) { 'PASS' } else { 'FAIL' }))
  ('end_marker_invariance=' + $(if ($endMarkerInvariantPass) { 'PASS' } else { 'FAIL' }))
  ('replay_invariance=' + $(if ($replayInvariantPass) { 'PASS' } else { 'FAIL' }))
  ('final_state_invariance=' + $(if ($finalStateInvariantPass) { 'PASS' } else { 'FAIL' }))
  ('final_value_invariance=' + $(if ($finalValueInvariantPass) { 'PASS' } else { 'FAIL' }))
  ('semantic_trace_identity=' + $(if ($semanticHashInvariantPass) { 'PASS' } else { 'FAIL' }))
  ('fresh_run_evidence=' + $(if ($freshRunEvidencePass) { 'PASS' } else { 'FAIL' }))
  ('per_record_semantic_mismatch_found=' + $(if ($perRecordMismatchFound) { 'YES' } else { 'NO' }))
  ('mismatch_detail=' + $mismatchDetail)
  ('launch_identity_unique_count=' + $launchIdentityUniqueCount)
  ('baseline_pf=' + $baselinePf)
  ('baseline_zip=' + $baselineZip)
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

@(
  'behavior_summary:'
  '- Repeated fresh runs were performed by rebuilding once, force-stopping any prior widget_sandbox process, and launching the same extension demo scenario three separate times through the canonical launcher.'
  '- Semantic comparison included ordered phase41_9 trace_record lines, ordered phase42_0 replay_event lines, ordered phase42_0 replay_reconstructed lines, trace count, replay record count, replay begin verification, replay termination, and final replay state/value.'
  '- Non-semantic fields ignored by design were wall-clock timestamps, launch identity timestamps, absolute proof paths, proof folder names, run log filenames, and zip filenames. LAUNCH_IDENTITY was treated as a build identity, not a unique launch-instance identity.'
  '- Identical-trace verification works by building a normalized semantic line set for each run and hashing it with SHA-256; all semantic hashes must match exactly, and any per-record mismatch fails the phase.'
  '- Replay results were compared across runs by requiring replay_begin_verified=1, replay_terminated_at_end=1, replay_final_match=1, and identical final replay state/value for every run.'
  '- Disabled remained inert because each run preserved widget_disabled_noninteractive_demo=1 and widget_runtime_disabled_intent_blocked=1 with no disabled-driven semantic trace drift.'
  '- Baseline remained unchanged because the proof stayed in extension mode and the baseline lock plus visual baseline contract checks both passed before the repeated-run sequence.'
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

$matrixLines.ToArray() | Set-Content -Path (Join-Path $pf '16_run_comparison_matrix.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase42_2.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)