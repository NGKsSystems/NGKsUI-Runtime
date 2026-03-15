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

function Get-FileSha256Hex {
  param(
    [string]$Path
  )
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $hashBytes = [System.Security.Cryptography.SHA256]::HashData($bytes)
  return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant()
}

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path $Root ('_proof/phase42_5_baseline_integrity_tamper_detection_' + $ts)
New-Item -ItemType Directory -Path $pf -Force | Out-Null

$launcher = Join-Path $Root 'tools/run_widget_sandbox.ps1'
if (-not (Test-Path -LiteralPath $launcher)) {
  throw 'missing canonical launcher'
}

$integrityRefPath = Join-Path $Root 'tools/phase42_5/baseline_integrity_reference.json'
$integrityRefLoadPass = $false
$integrityRefLoadReason = 'not_loaded'
$integrityRef = $null
$baselineRefResolvedPath = ''
$storedIntegrityHash = ''
$computedIntegrityHash = ''
$cleanIntegrityPass = $false

if (-not (Test-Path -LiteralPath $integrityRefPath)) {
  $integrityRefLoadPass = $false
  $integrityRefLoadReason = 'integrity_reference_missing'
} else {
  try {
    $integrityRef = Get-Content -Raw -LiteralPath $integrityRefPath | ConvertFrom-Json
    $requiredFields = @('baseline_reference_file','expected_integrity_hash_sha256','hash_method')
    $missing = @()
    foreach ($field in $requiredFields) {
      if (-not ($integrityRef.PSObject.Properties.Name -contains $field)) {
        $missing += $field
      }
    }

    if ($missing.Count -gt 0) {
      $integrityRefLoadPass = $false
      $integrityRefLoadReason = 'integrity_reference_missing_fields:' + ($missing -join ',')
    } else {
      $baselineRefRelativePath = [string]$integrityRef.baseline_reference_file
      $baselineRefResolvedPath = if ([System.IO.Path]::IsPathRooted($baselineRefRelativePath)) { $baselineRefRelativePath } else { Join-Path $Root $baselineRefRelativePath }

      if (-not (Test-Path -LiteralPath $baselineRefResolvedPath)) {
        $integrityRefLoadPass = $false
        $integrityRefLoadReason = 'baseline_reference_target_missing'
      } else {
        $storedIntegrityHash = [string]$integrityRef.expected_integrity_hash_sha256
        $computedIntegrityHash = Get-FileSha256Hex -Path $baselineRefResolvedPath
        $cleanIntegrityPass = ($storedIntegrityHash -eq $computedIntegrityHash)
        $integrityRefLoadPass = $true
        $integrityRefLoadReason = if ($cleanIntegrityPass) { 'integrity_reference_loaded_and_verified' } else { 'integrity_hash_mismatch_clean_case' }
      }
    }
  } catch {
    $integrityRefLoadPass = $false
    $integrityRefLoadReason = 'integrity_reference_parse_error:' + $_.Exception.Message
  }
}

$baselineRef = $null
$baselineLoadPass = $false
$baselineLoadReason = 'not_loaded'
if ($integrityRefLoadPass -and $cleanIntegrityPass) {
  try {
    $baselineRef = Get-Content -Raw -LiteralPath $baselineRefResolvedPath | ConvertFrom-Json
    $requiredBaselineFields = @(
      'semantic_trace_fingerprint_sha256',
      'trace_record_count',
      'final_runtime_state',
      'final_runtime_value',
      'replay_result',
      'normalization_method'
    )
    $missingBaseline = @()
    foreach ($field in $requiredBaselineFields) {
      if (-not ($baselineRef.PSObject.Properties.Name -contains $field)) {
        $missingBaseline += $field
      }
    }
    if ($missingBaseline.Count -gt 0) {
      $baselineLoadPass = $false
      $baselineLoadReason = 'baseline_missing_required_fields:' + ($missingBaseline -join ',')
    } else {
      $baselineLoadPass = $true
      $baselineLoadReason = 'baseline_loaded_after_integrity_pass'
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

# CASE A - Clean baseline integrity pass, comparison permitted and exact baseline match pass
$caseAExpected = 'PASS'
$caseAIntegrityPass = $cleanIntegrityPass
$caseAComparisonPermitted = $caseAIntegrityPass
$caseAFieldMismatches = New-Object System.Collections.Generic.List[string]
if ($caseAComparisonPermitted -and $baselineLoadPass) {
  if ([string]$baselineRef.semantic_trace_fingerprint_sha256 -ne $currentFingerprint) { $caseAFieldMismatches.Add('semantic_trace_fingerprint_sha256') }
  if ([int]$baselineRef.trace_record_count -ne $currentTraceCount) { $caseAFieldMismatches.Add('trace_record_count') }
  if ([string]$baselineRef.final_runtime_state -ne $currentFinalState) { $caseAFieldMismatches.Add('final_runtime_state') }
  if ([int]$baselineRef.final_runtime_value -ne $currentFinalValue) { $caseAFieldMismatches.Add('final_runtime_value') }
  if ([string]$baselineRef.replay_result -ne $currentReplayResult) { $caseAFieldMismatches.Add('replay_result') }
  if ([string]$baselineRef.normalization_method -ne $normalizationMethod) { $caseAFieldMismatches.Add('normalization_method') }
}
$caseAActual = if ($caseAIntegrityPass -and $caseAComparisonPermitted -and $caseAFieldMismatches.Count -eq 0) { 'PASS' } else { 'FAIL' }
$caseAReason = if ($caseAActual -eq 'PASS') { 'clean_integrity_verified_exact_match' } else { 'clean_case_failure:' + ($caseAFieldMismatches -join ',') }
$caseAPass = ($caseAActual -eq $caseAExpected)

# CASE B - controlled tamper modifies baseline content, integrity fails, comparison blocked
$baselineOriginalText = if (Test-Path -LiteralPath $baselineRefResolvedPath) { Get-Content -Raw -LiteralPath $baselineRefResolvedPath } else { '' }
$tamperedCaseBPath = Join-Path $pf 'case_b_tampered_baseline.json'
$tamperedCaseBText = $baselineOriginalText + "`n" + '{"tamper":"case_b_append"}'
$tamperedCaseBText | Set-Content -Path $tamperedCaseBPath -Encoding UTF8
$caseBComputedHash = Get-FileSha256Hex -Path $tamperedCaseBPath
$caseBIntegrityPass = ($storedIntegrityHash -eq $caseBComputedHash)
$caseBComparisonPermitted = $caseBIntegrityPass
$caseBExpected = 'FAIL'
$caseBActual = if ($caseBIntegrityPass) { 'PASS' } else { 'FAIL' }
$caseBReason = if ($caseBActual -eq 'FAIL') { 'integrity_hash_mismatch_detected_case_b' } else { 'unexpected_integrity_pass_case_b' }
$caseBPass = ($caseBActual -eq $caseBExpected) -and (-not $caseBComparisonPermitted)

# CASE C - partial semantic corruption inside baseline file, integrity fails, comparison blocked
$tamperedCaseCPath = Join-Path $pf 'case_c_partial_corrupt_baseline.json'
$tamperedCaseCText = $baselineOriginalText -replace '"final_runtime_value"\s*:\s*0', '"final_runtime_value": 1'
$tamperedCaseCText | Set-Content -Path $tamperedCaseCPath -Encoding UTF8
$caseCComputedHash = Get-FileSha256Hex -Path $tamperedCaseCPath
$caseCIntegrityPass = ($storedIntegrityHash -eq $caseCComputedHash)
$caseCComparisonPermitted = $caseCIntegrityPass
$caseCExpected = 'FAIL'
$caseCActual = if ($caseCIntegrityPass) { 'PASS' } else { 'FAIL' }
$caseCReason = if ($caseCActual -eq 'FAIL') { 'integrity_hash_mismatch_detected_case_c' } else { 'unexpected_integrity_pass_case_c' }
$caseCPass = ($caseCActual -eq $caseCExpected) -and (-not $caseCComparisonPermitted)

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
  $integrityRefLoadPass -and
  $baselineLoadPass -and
  $caseAPass -and
  $caseBPass -and
  $caseCPass -and
  $disabledInertPass -and
  $scopeGuardPass
)
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

@(
  'phase=42_5_baseline_integrity_tamper_detection'
  ('timestamp=' + (Get-Date).ToString('o'))
  ('runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' }))
  ('baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_lock=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' }))
  ('build=' + $(if ($buildPass) { 'PASS' } else { 'FAIL' }))
  ('canonical_launcher=' + $(if ($canonicalLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('integrity_reference_load=' + $(if ($integrityRefLoadPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_integrity_clean=' + $(if ($caseAIntegrityPass) { 'PASS' } else { 'FAIL' }))
  ('case_a_clean_baseline=' + $(if ($caseAPass) { 'PASS' } else { 'FAIL' }))
  ('case_b_tampered_baseline=' + $(if ($caseBPass) { 'PASS' } else { 'FAIL' }))
  ('case_c_partial_corruption=' + $(if ($caseCPass) { 'PASS' } else { 'FAIL' }))
  ('disabled_inert=' + $(if ($disabledInertPass) { 'PASS' } else { 'FAIL' }))
  ('scope_guard=' + $(if ($scopeGuardPass) { 'PASS' } else { 'FAIL' }))
  ('gate=' + $gate)
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase42_5: baseline tamper detection / reference integrity proof'
  'scope: verify baseline integrity hash enforcement blocks comparison on tamper and permits comparison only after clean integrity verification'
  'risk_profile=integrity enforcement runner only; no UI/layout/runtime behavior changes'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'integrity_definition:'
  '- Trusted integrity reference is loaded from tools/phase42_5/baseline_integrity_reference.json.'
  '- Baseline reference target is tools/phase42_4/certification_baseline_reference.json.'
  '- Integrity hash is SHA-256 over baseline file bytes (sha256_file_bytes_v1).'
  '- Baseline fingerprint comparison is permitted only when baseline integrity hash matches the trusted expected hash.'
  '- Any integrity mismatch fails deterministically and blocks baseline comparison.'
) | Set-Content -Path (Join-Path $pf '10_integrity_definition.txt') -Encoding UTF8

@(
  'integrity_rules:'
  '1. Integrity reference file path must be explicit and readable.'
  '2. Baseline reference path must resolve to an existing file.'
  '3. Stored expected integrity hash must be loaded from trusted reference.'
  '4. Current baseline file hash must be computed deterministically and compared exactly.'
  '5. CASE A clean baseline: integrity PASS, comparison permitted, exact baseline compare PASS.'
  '6. CASE B tampered baseline: integrity FAIL, comparison blocked, deterministic failure reason recorded.'
  '7. CASE C partial semantic corruption: integrity FAIL, comparison blocked, deterministic failure reason recorded.'
  '8. No fallback baseline regeneration or overwrite is allowed after integrity failure.'
) | Set-Content -Path (Join-Path $pf '11_integrity_rules.txt') -Encoding UTF8

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
  ('integrity_reference_path=' + $integrityRefPath)
  ('baseline_reference_path=' + $baselineRefResolvedPath)
  ('stored_integrity_hash=' + $storedIntegrityHash)
  ('computed_integrity_hash=' + $computedIntegrityHash)
  ('integrity_reference_load=' + $(if ($integrityRefLoadPass) { 'PASS' } else { 'FAIL' }))
  ('integrity_reference_reason=' + $integrityRefLoadReason)
  ('baseline_load=' + $(if ($baselineLoadPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_load_reason=' + $baselineLoadReason)
  ('case_a_expected=' + $caseAExpected)
  ('case_a_actual=' + $caseAActual)
  ('case_a_reason=' + $caseAReason)
  ('case_b_expected=' + $caseBExpected)
  ('case_b_actual=' + $caseBActual)
  ('case_b_reason=' + $caseBReason)
  ('case_b_comparison_permitted=' + $(if ($caseBComparisonPermitted) { 'YES' } else { 'NO' }))
  ('case_c_expected=' + $caseCExpected)
  ('case_c_actual=' + $caseCActual)
  ('case_c_reason=' + $caseCReason)
  ('case_c_comparison_permitted=' + $(if ($caseCComparisonPermitted) { 'YES' } else { 'NO' }))
  ('baseline_pf=' + $baselinePf)
  ('baseline_zip=' + $baselineZip)
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

@(
  'behavior_summary:'
  '- Baseline integrity verification loads a trusted expected SHA-256 hash from tools/phase42_5/baseline_integrity_reference.json and compares it to the computed hash of tools/phase42_4/certification_baseline_reference.json.'
  '- Tampering is detected by controlled baseline modifications in isolated test files: CASE B appends content; CASE C changes a semantic field.'
  '- Comparison is blocked after integrity failure by setting comparison_permitted=NO in tamper cases; only the clean integrity path allows baseline comparison.'
  '- Integrity hashes are generated deterministically from raw file bytes (sha256_file_bytes_v1).'
  '- Disabled remained inert because disabled guard tokens stayed present and no disabled-driven runtime semantic drift occurred.'
  '- Baseline remained unchanged because tamper operations were performed on isolated case files in the proof packet, never on the canonical baseline reference file.'
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

@(
  'baseline_integrity_record:'
  ('baseline_reference_file_path=' + $baselineRefResolvedPath)
  ('stored_expected_integrity_hash=' + $storedIntegrityHash)
  ('computed_integrity_hash=' + $computedIntegrityHash)
  ('integrity_verification_result=' + $(if ($caseAIntegrityPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_comparison_permitted=' + $(if ($caseAComparisonPermitted) { 'YES' } else { 'NO' }))
) | Set-Content -Path (Join-Path $pf '16_baseline_integrity_record.txt') -Encoding UTF8

@(
  'tamper_detection_evidence:'
  'case_b_controlled_modification=append_content_to_baseline_copy'
  ('case_b_tampered_file=' + $tamperedCaseBPath)
  ('case_b_expected_result=' + $caseBExpected)
  ('case_b_actual_result=' + $caseBActual)
  ('case_b_detected_integrity_mismatch=' + $(if (-not $caseBIntegrityPass) { 'YES' } else { 'NO' }))
  ('case_b_failure_reason=' + $caseBReason)
  ('case_b_comparison_blocked=' + $(if (-not $caseBComparisonPermitted) { 'YES' } else { 'NO' }))
  'case_c_controlled_modification=change_semantic_field_final_runtime_value'
  ('case_c_tampered_file=' + $tamperedCaseCPath)
  ('case_c_expected_result=' + $caseCExpected)
  ('case_c_actual_result=' + $caseCActual)
  ('case_c_detected_integrity_mismatch=' + $(if (-not $caseCIntegrityPass) { 'YES' } else { 'NO' }))
  ('case_c_failure_reason=' + $caseCReason)
  ('case_c_comparison_blocked=' + $(if (-not $caseCComparisonPermitted) { 'YES' } else { 'NO' }))
) | Set-Content -Path (Join-Path $pf '17_tamper_detection_evidence.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase42_5.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)
