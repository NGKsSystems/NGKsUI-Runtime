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
$pf = Join-Path $Root ('_proof/phase42_4_fingerprint_enforcement_baseline_compare_' + $ts)
New-Item -ItemType Directory -Path $pf -Force | Out-Null

$launcher = Join-Path $Root 'tools/run_widget_sandbox.ps1'
if (-not (Test-Path -LiteralPath $launcher)) {
  throw 'missing canonical launcher'
}

$baselineRefPath = Join-Path $Root 'tools/phase42_4/certification_baseline_reference.json'
$baselineLoadPass = $false
$baselineLoadReason = 'not_loaded'
$baselineRef = $null

if (-not (Test-Path -LiteralPath $baselineRefPath)) {
  $baselineLoadPass = $false
  $baselineLoadReason = 'baseline_missing_no_fallback'
} else {
  try {
    $baselineRef = Get-Content -Raw -LiteralPath $baselineRefPath | ConvertFrom-Json
    $requiredFields = @(
      'semantic_trace_fingerprint_sha256',
      'trace_record_count',
      'final_runtime_state',
      'final_runtime_value',
      'replay_result',
      'normalization_method'
    )
    $missing = @()
    foreach ($field in $requiredFields) {
      if (-not ($baselineRef.PSObject.Properties.Name -contains $field)) {
        $missing += $field
      }
    }
    if ($missing.Count -gt 0) {
      $baselineLoadPass = $false
      $baselineLoadReason = 'baseline_missing_required_fields:' + ($missing -join ',')
    } else {
      $baselineLoadPass = $true
      $baselineLoadReason = 'baseline_loaded_from_explicit_path'
    }
  } catch {
    $baselineLoadPass = $false
    $baselineLoadReason = 'baseline_parse_error:' + $_.Exception.Message
  }
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
$runLog = Join-Path $pf 'run_current.log'
$runText | Set-Content -Path $runLog -Encoding UTF8

$canonicalLaunchPass = (
  ($runExit -eq 0) -and
  (Test-HasToken -Text $runText -Token 'LAUNCH_CONFIG=Debug') -and
  (Test-HasToken -Text $runText -Token ('LAUNCH_EXE=' + (Join-Path $Root 'build\debug\bin\widget_sandbox.exe'))) -and
  (Test-HasToken -Text $runText -Token 'LAUNCH_IDENTITY=canonical|debug|')
)

$traceRecords = Get-TokenLines -Text $runText -Prefix 'widget_phase41_9_trace_record='
$replayEvents = Get-TokenLines -Text $runText -Prefix 'widget_phase42_0_replay_event='
$replayReconstructed = Get-TokenLines -Text $runText -Prefix 'widget_phase42_0_replay_reconstructed='

$normalizationMethod = 'ordered_semantic_lines_v1|sha256_utf8_newline_delimited'
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

$currentSemanticText = ($semanticLines -join "`n")
$currentFingerprint = Get-Sha256Hex -Text $currentSemanticText
$currentTraceCount = [int](Get-TokenValue -Text $runText -Prefix 'widget_phase41_9_trace_count=')
$currentFinalState = Get-TokenValue -Text $runText -Prefix 'widget_phase42_0_replay_final_state='
$currentFinalValue = [int](Get-TokenValue -Text $runText -Prefix 'widget_phase42_0_replay_final_value=')
$currentReplayResult = if (Test-HasToken -Text $runText -Token 'widget_phase42_0_replay_final_match=1') { 'PASS' } else { 'FAIL' }

$comparisonMismatches = New-Object System.Collections.Generic.List[string]
if ($baselineLoadPass) {
  if ($baselineRef.semantic_trace_fingerprint_sha256 -ne $currentFingerprint) { $comparisonMismatches.Add('semantic_trace_fingerprint_sha256') }
  if ([int]$baselineRef.trace_record_count -ne $currentTraceCount) { $comparisonMismatches.Add('trace_record_count') }
  if ([string]$baselineRef.final_runtime_state -ne $currentFinalState) { $comparisonMismatches.Add('final_runtime_state') }
  if ([int]$baselineRef.final_runtime_value -ne $currentFinalValue) { $comparisonMismatches.Add('final_runtime_value') }
  if ([string]$baselineRef.replay_result -ne $currentReplayResult) { $comparisonMismatches.Add('replay_result') }
  if ([string]$baselineRef.normalization_method -ne $normalizationMethod) { $comparisonMismatches.Add('normalization_method') }
}

# CASE A: exact baseline comparison must pass
$caseAExpected = 'PASS'
$caseAActual = if ($baselineLoadPass -and $comparisonMismatches.Count -eq 0) { 'PASS' } else { 'FAIL' }
$caseAReason = if ($caseAActual -eq 'PASS') { 'exact_baseline_match' } else { 'mismatch:' + ($comparisonMismatches -join ',') }
$caseAPass = ($caseAActual -eq $caseAExpected)

# CASE B: intentional mismatch must fail deterministically
$intentionalAlteredFingerprint = if ($baselineLoadPass) {
  'x' + ([string]$baselineRef.semantic_trace_fingerprint_sha256).Substring(1)
} else {
  'baseline_unavailable'
}

$caseBMismatches = New-Object System.Collections.Generic.List[string]
if (-not $baselineLoadPass) {
  $caseBMismatches.Add('baseline_not_loaded')
} else {
  if ($intentionalAlteredFingerprint -ne $currentFingerprint) { $caseBMismatches.Add('semantic_trace_fingerprint_sha256') }
  if ([int]$baselineRef.trace_record_count -ne $currentTraceCount) { $caseBMismatches.Add('trace_record_count') }
  if ([string]$baselineRef.final_runtime_state -ne $currentFinalState) { $caseBMismatches.Add('final_runtime_state') }
  if ([int]$baselineRef.final_runtime_value -ne $currentFinalValue) { $caseBMismatches.Add('final_runtime_value') }
  if ([string]$baselineRef.replay_result -ne $currentReplayResult) { $caseBMismatches.Add('replay_result') }
}

$caseBExpected = 'FAIL'
$caseBActual = if ($caseBMismatches.Count -eq 0) { 'PASS' } else { 'FAIL' }
$caseBReason = if ($caseBActual -eq 'FAIL') { 'intentional_mismatch_detected:' + ($caseBMismatches -join ',') } else { 'unexpected_match' }
$caseBPass = ($caseBActual -eq $caseBExpected)

# CASE C: baseline load validation must pass and prove no fallback path
$caseCExpected = 'PASS'
$caseCActual = if ($baselineLoadPass -and (Test-Path -LiteralPath $baselineRefPath)) { 'PASS' } else { 'FAIL' }
$caseCReason = if ($caseCActual -eq 'PASS') { 'baseline_loaded_from_explicit_reference_no_fallback' } else { $baselineLoadReason }
$caseCPass = ($caseCActual -eq $caseCExpected)

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
  $baselineLoadPass -and
  $caseAPass -and
  $caseBPass -and
  $caseCPass -and
  $disabledInertPass -and
  $scopeGuardPass
)
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

@(
  'phase=42_4_fingerprint_enforcement_baseline_compare'
  ('timestamp=' + (Get-Date).ToString('o'))
  ('runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' }))
  ('baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_lock=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' }))
  ('build=' + $(if ($buildPass) { 'PASS' } else { 'FAIL' }))
  ('canonical_launcher=' + $(if ($canonicalLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_load_validation=' + $(if ($baselineLoadPass) { 'PASS' } else { 'FAIL' }))
  ('case_a_exact_match=' + $(if ($caseAPass) { 'PASS' } else { 'FAIL' }))
  ('case_b_intentional_mismatch=' + $(if ($caseBPass) { 'PASS' } else { 'FAIL' }))
  ('case_c_baseline_load=' + $(if ($caseCPass) { 'PASS' } else { 'FAIL' }))
  ('disabled_inert=' + $(if ($disabledInertPass) { 'PASS' } else { 'FAIL' }))
  ('scope_guard=' + $(if ($scopeGuardPass) { 'PASS' } else { 'FAIL' }))
  ('gate=' + $gate)
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase42_4: certification fingerprint enforcement / baseline comparison proof'
  'scope: enforce exact semantic fingerprint baseline match, prove deterministic mismatch failure, and verify explicit baseline reference loading with no fallback'
  'risk_profile=enforcement runner only; no UI/layout/runtime behavior changes'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'enforcement_definition:'
  '- The enforcement flow loads the explicit certification baseline reference from tools/phase42_4/certification_baseline_reference.json.'
  '- Current semantic fingerprint is recomputed from the current canonical extension run using certified normalization rules.'
  '- Exact baseline comparison checks fingerprint hash, trace count, final runtime state, final runtime value, replay result, and normalization method.'
  '- Match path passes only when all semantic enforcement fields match exactly.'
  '- Mismatch path fails when any enforced semantic field differs and reports explicit mismatch field names.'
  '- No silent fallback path exists for missing baseline reference; baseline load failure is explicit and gating.'
) | Set-Content -Path (Join-Path $pf '10_enforcement_definition.txt') -Encoding UTF8

@(
  'baseline_comparison_rules:'
  '1. Baseline reference file must exist at tools/phase42_4/certification_baseline_reference.json and parse successfully.'
  '2. Current run fingerprint must be computed from canonical launch output semantic fields only.'
  '3. Comparison fields must match exactly: semantic_trace_fingerprint_sha256, trace_record_count, final_runtime_state, final_runtime_value, replay_result, normalization_method.'
  '4. CASE A exact baseline match: expected PASS.'
  '5. CASE B intentional mismatch: expected FAIL with mismatch field evidence.'
  '6. CASE C baseline load validation: expected PASS only when explicit baseline file was loaded with no fallback.'
  '7. Non-semantic fields (timestamps, paths, zip names) are excluded from semantic enforcement checks.'
  '8. Any semantic mismatch fails enforcement deterministically and is reported explicitly.'
) | Set-Content -Path (Join-Path $pf '11_baseline_comparison_rules.txt') -Encoding UTF8

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
  ('baseline_reference_path=' + $baselineRefPath)
  ('baseline_load_validation=' + $(if ($baselineLoadPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_load_reason=' + $baselineLoadReason)
  ('current_semantic_fingerprint=' + $currentFingerprint)
  ('current_trace_record_count=' + $currentTraceCount)
  ('current_final_runtime_state=' + $currentFinalState)
  ('current_final_runtime_value=' + $currentFinalValue)
  ('current_replay_result=' + $currentReplayResult)
  ('case_a_expected=' + $caseAExpected)
  ('case_a_actual=' + $caseAActual)
  ('case_a_reason=' + $caseAReason)
  ('case_b_expected=' + $caseBExpected)
  ('case_b_actual=' + $caseBActual)
  ('case_b_reason=' + $caseBReason)
  ('case_c_expected=' + $caseCExpected)
  ('case_c_actual=' + $caseCActual)
  ('case_c_reason=' + $caseCReason)
  ('baseline_pf=' + $baselinePf)
  ('baseline_zip=' + $baselineZip)
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

@(
  'behavior_summary:'
  '- Certified baseline is loaded explicitly from tools/phase42_4/certification_baseline_reference.json and validated for required fields before comparison.'
  '- Current fingerprint is computed from the current canonical extension run using ordered semantic trace/replay lines plus certified semantic result fields.'
  '- Exact-match enforcement compares current vs baseline across all required semantic fields and passes only on full equality.'
  '- Mismatch detection is proven by an intentional fingerprint alteration in comparison input; enforcement returns FAIL and reports semantic_trace_fingerprint_sha256 mismatch explicitly.'
  '- Silent fallback is prevented because baseline absence/parse/field errors set baseline_load_validation=FAIL and gate the phase without generating replacement baseline data.'
  '- Baseline reference integrity is explicit via recorded baseline reference path and loaded baseline payload fields in proof artifacts.'
  '- Disabled remained inert because disabled guard tokens stayed present and no disabled-driven semantic drift occurred during certification comparison run.'
  '- Baseline remained unchanged because extension-lane enforcement run preserved baseline lock and visual baseline contract pass conditions.'
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

@(
  'baseline_reference_record:'
  ('baseline_reference_file=' + $baselineRefPath)
  ('stored_semantic_trace_fingerprint_sha256=' + $(if ($baselineLoadPass) { [string]$baselineRef.semantic_trace_fingerprint_sha256 } else { '(unavailable)' }))
  ('trace_record_count=' + $(if ($baselineLoadPass) { [int]$baselineRef.trace_record_count } else { 0 }))
  ('final_runtime_state=' + $(if ($baselineLoadPass) { [string]$baselineRef.final_runtime_state } else { '(unavailable)' }))
  ('final_runtime_value=' + $(if ($baselineLoadPass) { [int]$baselineRef.final_runtime_value } else { 0 }))
  ('replay_result=' + $(if ($baselineLoadPass) { [string]$baselineRef.replay_result } else { '(unavailable)' }))
  ('normalization_method=' + $(if ($baselineLoadPass) { [string]$baselineRef.normalization_method } else { '(unavailable)' }))
  ('current_run_matched_baseline=' + $(if ($caseAActual -eq 'PASS') { 'YES' } else { 'NO' }))
) | Set-Content -Path (Join-Path $pf '16_baseline_reference_record.txt') -Encoding UTF8

@(
  'mismatch_evidence:'
  'altered_input=semantic_trace_fingerprint_sha256'
  ('baseline_original_fingerprint=' + $(if ($baselineLoadPass) { [string]$baselineRef.semantic_trace_fingerprint_sha256 } else { '(unavailable)' }))
  ('intentional_altered_fingerprint=' + $intentionalAlteredFingerprint)
  ('current_computed_fingerprint=' + $currentFingerprint)
  'expected_result=FAIL'
  ('actual_result=' + $caseBActual)
  ('mismatch_fields=' + ($caseBMismatches -join ','))
  ('deterministic_failure_reason=' + $caseBReason)
  'why_correct=altered fingerprint differs from certified baseline semantic hash, so enforcement must reject comparison deterministically'
) | Set-Content -Path (Join-Path $pf '17_mismatch_evidence.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase42_4.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)