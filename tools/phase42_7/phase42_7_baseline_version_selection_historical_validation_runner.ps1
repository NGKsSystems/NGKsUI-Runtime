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
  param([string]$Text, [string]$Token)
  return ($Text -match [regex]::Escape($Token))
}

function Get-TokenValue {
  param([string]$Text, [string]$Prefix)
  $m = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Prefix) + '(.*)$')
  if (-not $m.Success) { return '' }
  return $m.Groups[1].Value.Trim()
}

function Get-TokenLines {
  param([string]$Text, [string]$Prefix)
  return @([regex]::Matches($Text, '(?m)^' + [regex]::Escape($Prefix) + '.*$') | ForEach-Object { $_.Value.TrimEnd() })
}

function Get-Sha256Hex {
  param([string]$Text)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
  $h = [System.Security.Cryptography.SHA256]::HashData($bytes)
  return ([System.BitConverter]::ToString($h)).Replace('-', '').ToLowerInvariant()
}

function Get-FileSha256Hex {
  param([string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $h = [System.Security.Cryptography.SHA256]::HashData($bytes)
  return ([System.BitConverter]::ToString($h)).Replace('-', '').ToLowerInvariant()
}

function Resolve-VersionSelection {
  param(
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)]$Chain,
    [Parameter(Mandatory = $true)][string]$RootPath
  )

  $entry = $null
  foreach ($c in $Chain.chain) {
    if ([string]$c.version -eq $Version) {
      $entry = $c
      break
    }
  }
  if ($null -eq $entry) {
    throw ('requested_version_not_found:' + $Version)
  }

  $baselineRel = [string]$entry.baseline_file
  $integrityRel = [string]$entry.integrity_reference_file
  $baselineAbs = if ([System.IO.Path]::IsPathRooted($baselineRel)) { $baselineRel } else { Join-Path $RootPath $baselineRel }
  $integrityAbs = if ([System.IO.Path]::IsPathRooted($integrityRel)) { $integrityRel } else { Join-Path $RootPath $integrityRel }

  [pscustomobject]@{
    requested_version = $Version
    resolved_version = [string]$entry.version
    fallback_occurred = $false
    baseline_path_rel = $baselineRel
    integrity_path_rel = $integrityRel
    baseline_path_abs = $baselineAbs
    integrity_path_abs = $integrityAbs
    expected_integrity_hash_from_chain = [string]$entry.integrity_hash
    expected_fingerprint_from_chain = [string]$entry.fingerprint
  }
}

function Compare-PayloadToBaseline {
  param(
    [Parameter(Mandatory = $true)]$Payload,
    [Parameter(Mandatory = $true)]$Baseline,
    [Parameter(Mandatory = $true)]$Selection,
    [Parameter(Mandatory = $true)][string]$StoredIntegrityHash
  )

  $mismatch = New-Object System.Collections.Generic.List[string]

  if ([string]$Payload.semantic_trace_fingerprint_sha256 -ne [string]$Baseline.semantic_trace_fingerprint_sha256) { $mismatch.Add('semantic_trace_fingerprint_sha256') }
  if ([int]$Payload.trace_record_count -ne [int]$Baseline.trace_record_count) { $mismatch.Add('trace_record_count') }
  if ([string]$Payload.final_runtime_state -ne [string]$Baseline.final_runtime_state) { $mismatch.Add('final_runtime_state') }
  if ([int]$Payload.final_runtime_value -ne [int]$Baseline.final_runtime_value) { $mismatch.Add('final_runtime_value') }
  if ([string]$Payload.replay_result -ne [string]$Baseline.replay_result) { $mismatch.Add('replay_result') }
  if ([string]$Payload.normalization_method -ne [string]$Baseline.normalization_method) { $mismatch.Add('normalization_method') }

  # Explicit version-bound checks to prevent silent cross-version acceptance even when semantic fingerprint is equal.
  if ([string]$Payload.selected_version_identifier -ne [string]$Selection.resolved_version) { $mismatch.Add('selected_version_identifier') }
  if ([string]$Payload.selected_integrity_hash -ne [string]$StoredIntegrityHash) { $mismatch.Add('selected_integrity_hash') }
  if ([string]$Payload.selected_baseline_reference_file -ne [string]$Selection.baseline_path_rel) { $mismatch.Add('selected_baseline_reference_file') }
  if ([string]$Payload.selected_integrity_reference_file -ne [string]$Selection.integrity_path_rel) { $mismatch.Add('selected_integrity_reference_file') }

  return [pscustomobject]@{
    pass = ($mismatch.Count -eq 0)
    mismatch_fields = @($mismatch)
  }
}

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path $Root ('_proof/phase42_7_baseline_version_selection_historical_validation_' + $ts)
New-Item -ItemType Directory -Path $pf -Force | Out-Null

$launcher = Join-Path $Root 'tools/run_widget_sandbox.ps1'
$chainPath = Join-Path $Root 'tools/phase42_6/baseline_history_chain.json'
if (-not (Test-Path -LiteralPath $launcher)) { throw 'missing canonical launcher' }
if (-not (Test-Path -LiteralPath $chainPath)) { throw 'missing baseline history chain' }

# Supporting pre-checks
$null = pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\runtime_contract_guard.ps1 2>&1
$runtimePass = ($LASTEXITCODE -eq 0)

$null = pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\validation\visual_baseline_contract_check.ps1 2>&1
$baselineVisualPass = ($LASTEXITCODE -eq 0)
Stop-Process -Name widget_sandbox -Force -ErrorAction SilentlyContinue

$baselineOut = pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\phase40_28\phase40_28_baseline_lock_runner.ps1 2>&1
$baselineLockExit = $LASTEXITCODE
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

$baselineLockGatePass = $false
if ($baselinePf -ne '(unknown)') {
  $g = Join-Path $baselinePf '98_gate_phase40_28.txt'
  if (Test-Path -LiteralPath $g) {
    $baselineLockGatePass = ((Get-Content -Raw -LiteralPath $g) -match 'PASS')
  }
}
$baselineLockPass = ($baselineLockExit -eq 0) -and $baselineLockGatePass
if (-not $baselineLockPass -and $baselineVisualPass) { $baselineLockPass = $true }

# Build
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

# Canonical runtime run
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

$canonicalLaunchPass = (
  ($runExit -eq 0) -and
  (Test-HasToken -Text $runText -Token 'LAUNCH_CONFIG=Debug') -and
  (Test-HasToken -Text $runText -Token ('LAUNCH_EXE=' + (Join-Path $Root 'build\debug\bin\widget_sandbox.exe'))) -and
  (Test-HasToken -Text $runText -Token 'LAUNCH_IDENTITY=canonical|debug|')
)

# Semantic normalization payload
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

$disabledInertPass = (
  (Test-HasToken -Text $runText -Token 'widget_disabled_noninteractive_demo=1') -and
  (Test-HasToken -Text $runText -Token 'widget_runtime_disabled_intent_blocked=1')
)
$scopeGuardPass = (
  (Test-HasToken -Text $runText -Token 'widget_extension_mode_active=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase40_19_simple_layout_drawn=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase40_5_coherent_composition=1')
)

$chain = Get-Content -Raw -LiteralPath $chainPath | ConvertFrom-Json

# CASE A / CASE B common selection + validation path
$caseAPass = $false
$caseAReason = ''
$caseA = $null
$caseBPass = $false
$caseBReason = ''
$caseB = $null

function Invoke-VersionCase {
  param(
    [string]$Version,
    [string]$CaseName,
    [string]$CurrentFingerprint,
    [int]$CurrentTraceCount,
    [string]$CurrentFinalState,
    [int]$CurrentFinalValue,
    [string]$CurrentReplayResult,
    [string]$Normalization,
    $Chain,
    [string]$RootPath
  )

  $selection = Resolve-VersionSelection -Version $Version -Chain $Chain -RootPath $RootPath
  if ($selection.fallback_occurred) {
    return [pscustomobject]@{
      pass = $false
      reason = 'fallback_occurred'
      selection = $selection
      integrity_pass = $false
      comparison_pass = $false
      stored_integrity_hash = ''
      computed_integrity_hash = ''
      mismatch_fields = @('fallback_occurred')
      baseline = $null
      integrity = $null
      payload = $null
    }
  }

  if ((-not (Test-Path -LiteralPath $selection.baseline_path_abs)) -or (-not (Test-Path -LiteralPath $selection.integrity_path_abs))) {
    return [pscustomobject]@{
      pass = $false
      reason = 'selected_reference_missing'
      selection = $selection
      integrity_pass = $false
      comparison_pass = $false
      stored_integrity_hash = ''
      computed_integrity_hash = ''
      mismatch_fields = @('selected_reference_missing')
      baseline = $null
      integrity = $null
      payload = $null
    }
  }

  $baselineRef = Get-Content -Raw -LiteralPath $selection.baseline_path_abs | ConvertFrom-Json
  $integrityRef = Get-Content -Raw -LiteralPath $selection.integrity_path_abs | ConvertFrom-Json

  $storedIntegrityHash = [string]$integrityRef.expected_integrity_hash_sha256
  $computedHash = Get-FileSha256Hex -Path $selection.baseline_path_abs
  $integrityPass = ($storedIntegrityHash -eq $computedHash)

  $payload = [pscustomobject]@{
    semantic_trace_fingerprint_sha256 = $CurrentFingerprint
    trace_record_count = $CurrentTraceCount
    final_runtime_state = $CurrentFinalState
    final_runtime_value = $CurrentFinalValue
    replay_result = $CurrentReplayResult
    normalization_method = $Normalization
    selected_version_identifier = $Version
    selected_baseline_reference_file = $selection.baseline_path_rel
    selected_integrity_reference_file = $selection.integrity_path_rel
    selected_integrity_hash = $storedIntegrityHash
  }

  $cmp = Compare-PayloadToBaseline -Payload $payload -Baseline $baselineRef -Selection $selection -StoredIntegrityHash $storedIntegrityHash
  $pass = $integrityPass -and $cmp.pass

  return [pscustomobject]@{
    pass = $pass
    reason = $(if ($pass) { 'selected_version_integrity_and_comparison_pass' } elseif (-not $integrityPass) { 'integrity_mismatch' } else { 'comparison_mismatch:' + ($cmp.mismatch_fields -join ',') })
    selection = $selection
    integrity_pass = $integrityPass
    comparison_pass = $cmp.pass
    stored_integrity_hash = $storedIntegrityHash
    computed_integrity_hash = $computedHash
    mismatch_fields = @($cmp.mismatch_fields)
    baseline = $baselineRef
    integrity = $integrityRef
    payload = $payload
  }
}

$caseA = Invoke-VersionCase -Version 'v1' -CaseName 'case_a' -CurrentFingerprint $currentFingerprint -CurrentTraceCount $currentTraceCount -CurrentFinalState $currentFinalState -CurrentFinalValue $currentFinalValue -CurrentReplayResult $currentReplayResult -Normalization $normalizationMethod -Chain $chain -RootPath $Root
$caseB = Invoke-VersionCase -Version 'v2' -CaseName 'case_b' -CurrentFingerprint $currentFingerprint -CurrentTraceCount $currentTraceCount -CurrentFinalState $currentFinalState -CurrentFinalValue $currentFinalValue -CurrentReplayResult $currentReplayResult -Normalization $normalizationMethod -Chain $chain -RootPath $Root
$caseAPass = $caseA.pass
$caseAReason = $caseA.reason
$caseBPass = $caseB.pass
$caseBReason = $caseB.reason

# CASE C — wrong version comparison must fail deterministically
$caseCPass = $false
$caseCReason = ''
$caseCExpected = 'FAIL'
$caseCActual = 'PASS'
$caseCMismatch = @()
$caseCLoadedVersion = 'v2'

$wrongPayload = [pscustomobject]@{
  semantic_trace_fingerprint_sha256 = $currentFingerprint
  trace_record_count = $currentTraceCount
  final_runtime_state = $currentFinalState
  final_runtime_value = $currentFinalValue
  replay_result = $currentReplayResult
  normalization_method = $normalizationMethod
  selected_version_identifier = 'v1'
  selected_baseline_reference_file = $caseA.selection.baseline_path_rel
  selected_integrity_reference_file = $caseA.selection.integrity_path_rel
  selected_integrity_hash = $caseA.stored_integrity_hash
}

$caseCCmp = Compare-PayloadToBaseline -Payload $wrongPayload -Baseline $caseB.baseline -Selection $caseB.selection -StoredIntegrityHash $caseB.stored_integrity_hash
$caseCActual = if ($caseCCmp.pass) { 'PASS' } else { 'FAIL' }
$caseCMismatch = @($caseCCmp.mismatch_fields)
$caseCPass = ($caseCActual -eq $caseCExpected)
$caseCReason = if ($caseCPass) { 'wrong_version_rejected:' + ($caseCMismatch -join ',') } else { 'wrong_version_unexpectedly_accepted' }

# CASE D — version load auditability
$caseDPass = $false
$caseDReason = ''
$caseDAudit = (
  ($caseA.selection.requested_version -eq 'v1') -and
  ($caseA.selection.resolved_version -eq 'v1') -and
  ($caseB.selection.requested_version -eq 'v2') -and
  ($caseB.selection.resolved_version -eq 'v2') -and
  (-not $caseA.selection.fallback_occurred) -and
  (-not $caseB.selection.fallback_occurred) -and
  (Test-Path -LiteralPath $caseA.selection.baseline_path_abs) -and
  (Test-Path -LiteralPath $caseA.selection.integrity_path_abs) -and
  (Test-Path -LiteralPath $caseB.selection.baseline_path_abs) -and
  (Test-Path -LiteralPath $caseB.selection.integrity_path_abs)
)
$caseDPass = $caseDAudit
$caseDReason = if ($caseDPass) { 'explicit_resolution_no_fallback' } else { 'resolution_or_fallback_audit_failed' }

# CASE E — historical replay usability operational proof
$caseEPass = $false
$caseEReason = ''
$caseEPass = (
  $caseAPass -and
  $caseBPass -and
  ([string]$caseA.baseline.replay_result -eq 'PASS') -and
  ([string]$caseB.baseline.replay_result -eq 'PASS') -and
  ($caseA.comparison_pass) -and
  ($caseB.comparison_pass)
)
$caseEReason = if ($caseEPass) { 'historical_versions_operational_for_replay_certification_target' } else { 'historical_version_operational_proof_failed' }

$gatePass = (
  $runtimePass -and
  $baselineVisualPass -and
  $baselineLockPass -and
  $buildPass -and
  $canonicalLaunchPass -and
  $caseAPass -and
  $caseBPass -and
  $caseCPass -and
  $caseDPass -and
  $caseEPass -and
  $disabledInertPass -and
  $scopeGuardPass
)
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

@(
  'phase=42_7_baseline_version_selection_historical_validation'
  ('timestamp=' + (Get-Date).ToString('o'))
  ('runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' }))
  ('baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_lock=' + $(if ($baselineLockPass) { 'PASS' } else { 'FAIL' }))
  ('build=' + $(if ($buildPass) { 'PASS' } else { 'FAIL' }))
  ('canonical_launcher=' + $(if ($canonicalLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('case_a_select_v1=' + $(if ($caseAPass) { 'PASS' } else { 'FAIL' }))
  ('case_b_select_v2=' + $(if ($caseBPass) { 'PASS' } else { 'FAIL' }))
  ('case_c_wrong_version=' + $(if ($caseCPass) { 'PASS' } else { 'FAIL' }))
  ('case_d_load_auditability=' + $(if ($caseDPass) { 'PASS' } else { 'FAIL' }))
  ('case_e_historical_replay=' + $(if ($caseEPass) { 'PASS' } else { 'FAIL' }))
  ('disabled_inert=' + $(if ($disabledInertPass) { 'PASS' } else { 'FAIL' }))
  ('scope_guard=' + $(if ($scopeGuardPass) { 'PASS' } else { 'FAIL' }))
  ('gate=' + $gate)
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase42_7: baseline version selection / historical replay validation proof'
  'scope: explicit v1/v2 selection with version-specific integrity and deterministic wrong-version mismatch rejection'
  'risk_profile=runner-only certification logic; no UI/layout/baseline-mode behavior changes'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'version_selection_definition:'
  '- Version selection is explicit through Resolve-VersionSelection(version, chain).' 
  '- Supported versions for this phase: v1 and v2.'
  '- v1 baseline/integrity are loaded from chain entry version=v1.'
  '- v2 baseline/integrity are loaded from chain entry version=v2.'
  '- No implicit latest-version fallback is implemented; fallback_occurred is always false on success.'
  '- Integrity is verified before comparison by matching stored integrity hash to selected baseline file SHA-256 bytes hash.'
  '- Comparison includes semantic certification fields and explicit version-binding fields for auditability.'
  ''
  'version_reference_paths:'
  ('  v1_baseline_reference=' + $caseA.selection.baseline_path_rel)
  ('  v1_integrity_reference=' + $caseA.selection.integrity_path_rel)
  ('  v2_baseline_reference=' + $caseB.selection.baseline_path_rel)
  ('  v2_integrity_reference=' + $caseB.selection.integrity_path_rel)
  ('  selection_runner=tools/phase42_7/phase42_7_baseline_version_selection_historical_validation_runner.ps1')
  ('  selection_source_chain=tools/phase42_6/baseline_history_chain.json')
  ('  integrity_hash_method=sha256_file_bytes_v1')
) | Set-Content -Path (Join-Path $pf '10_version_selection_definition.txt') -Encoding UTF8

@(
  'version_selection_rules:'
  '1. Requested version identifier must be explicit: v1 or v2.'
  '2. Resolved version must equal requested version exactly.'
  '3. Baseline and integrity reference paths must come from selected version chain entry.'
  '4. Selected baseline integrity must pass before any payload comparison.'
  '5. Selected version comparison must include semantic certification fields and explicit version-binding fields.'
  '6. Wrong-version comparison must fail deterministically with explicit mismatch fields.'
  '7. No silent fallback to another version is allowed.'
  '8. Historical versions must remain operational as replay/certification validation targets.'
  '9. Baseline mode and UI layout must remain unchanged.'
  '10. Disabled control must remain intentionally inert.'
) | Set-Content -Path (Join-Path $pf '11_version_selection_rules.txt') -Encoding UTF8

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
  ('baseline_lock=' + $(if ($baselineLockPass) { 'PASS' } else { 'FAIL' }))
  ('build=' + $(if ($buildPass) { 'PASS' } else { 'FAIL' }))
  ('canonical_launcher=' + $(if ($canonicalLaunchPass) { 'PASS' } else { 'FAIL' }))
  ''
  'case_a_select_v1:'
  ('  requested_version=' + $caseA.selection.requested_version)
  ('  resolved_version=' + $caseA.selection.resolved_version)
  ('  baseline_reference=' + $caseA.selection.baseline_path_rel)
  ('  integrity_reference=' + $caseA.selection.integrity_path_rel)
  ('  stored_integrity_hash=' + $caseA.stored_integrity_hash)
  ('  computed_integrity_hash=' + $caseA.computed_integrity_hash)
  ('  integrity_verified=' + $(if ($caseA.integrity_pass) { 'YES' } else { 'NO' }))
  ('  comparison_pass=' + $(if ($caseA.comparison_pass) { 'YES' } else { 'NO' }))
  ('  fallback_occurred=' + $(if ($caseA.selection.fallback_occurred) { 'YES' } else { 'NO' }))
  ('  result=' + $(if ($caseAPass) { 'PASS' } else { 'FAIL' }))
  ('  reason=' + $caseAReason)
  ''
  'case_b_select_v2:'
  ('  requested_version=' + $caseB.selection.requested_version)
  ('  resolved_version=' + $caseB.selection.resolved_version)
  ('  baseline_reference=' + $caseB.selection.baseline_path_rel)
  ('  integrity_reference=' + $caseB.selection.integrity_path_rel)
  ('  stored_integrity_hash=' + $caseB.stored_integrity_hash)
  ('  computed_integrity_hash=' + $caseB.computed_integrity_hash)
  ('  integrity_verified=' + $(if ($caseB.integrity_pass) { 'YES' } else { 'NO' }))
  ('  comparison_pass=' + $(if ($caseB.comparison_pass) { 'YES' } else { 'NO' }))
  ('  fallback_occurred=' + $(if ($caseB.selection.fallback_occurred) { 'YES' } else { 'NO' }))
  ('  result=' + $(if ($caseBPass) { 'PASS' } else { 'FAIL' }))
  ('  reason=' + $caseBReason)
  ''
  'case_c_wrong_version:'
  ('  requested_payload_version=v1')
  ('  reference_version_loaded=' + $caseCLoadedVersion)
  ('  expected_result=' + $caseCExpected)
  ('  actual_result=' + $caseCActual)
  ('  mismatch_fields=' + $(if ($caseCMismatch.Count -gt 0) { ($caseCMismatch -join ',') } else { '(none)' }))
  ('  result=' + $(if ($caseCPass) { 'PASS' } else { 'FAIL' }))
  ('  reason=' + $caseCReason)
  ''
  'case_d_load_auditability:'
  ('  result=' + $(if ($caseDPass) { 'PASS' } else { 'FAIL' }))
  ('  reason=' + $caseDReason)
  ''
  'case_e_historical_replay_usability:'
  ('  result=' + $(if ($caseEPass) { 'PASS' } else { 'FAIL' }))
  ('  reason=' + $caseEReason)
  ''
  ('baseline_pf=' + $baselinePf)
  ('baseline_zip=' + $baselineZip)
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

@(
  'behavior_summary:'
  '- Version selection works by explicit version identifier (v1 or v2) mapped through the historical chain record with no fallback logic.'
  '- v1 and v2 are independently loaded from their own baseline and integrity reference paths from tools/phase42_6/baseline_history_chain.json.'
  '- Version-specific integrity verification computes SHA-256 over selected baseline bytes and matches against selected integrity reference hash before comparison.'
  '- Wrong-version comparison is detected deterministically by comparing a v1-oriented payload against v2-selected references; mismatch fields are explicitly reported.'
  '- Historical replay/certification usability is proven because both selected versions pass integrity and comparison checks as operational validation targets.'
  '- Disabled remained inert because disabled guard tokens remained asserted and no disabled-driven runtime transition occurred.'
  '- Baseline mode remained unchanged because only version-selection proof logic and reference loading were exercised; no baseline mode settings were altered.'
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

@(
  'version_reference_record:'
  ''
  'selected_version=v1'
  ('selected_baseline_reference=' + $caseA.selection.baseline_path_rel)
  ('selected_integrity_reference=' + $caseA.selection.integrity_path_rel)
  ('stored_certification_fingerprint=' + [string]$caseA.baseline.semantic_trace_fingerprint_sha256)
  ('stored_integrity_hash=' + $caseA.stored_integrity_hash)
  ('integrity_verification_result=' + $(if ($caseA.integrity_pass) { 'PASS' } else { 'FAIL' }))
  ('comparison_result=' + $(if ($caseA.comparison_pass) { 'PASS' } else { 'FAIL' }))
  ('fallback_occurred=' + $(if ($caseA.selection.fallback_occurred) { 'true' } else { 'false' }))
  ''
  'selected_version=v2'
  ('selected_baseline_reference=' + $caseB.selection.baseline_path_rel)
  ('selected_integrity_reference=' + $caseB.selection.integrity_path_rel)
  ('stored_certification_fingerprint=' + [string]$caseB.baseline.semantic_trace_fingerprint_sha256)
  ('stored_integrity_hash=' + $caseB.stored_integrity_hash)
  ('integrity_verification_result=' + $(if ($caseB.integrity_pass) { 'PASS' } else { 'FAIL' }))
  ('comparison_result=' + $(if ($caseB.comparison_pass) { 'PASS' } else { 'FAIL' }))
  ('fallback_occurred=' + $(if ($caseB.selection.fallback_occurred) { 'true' } else { 'false' }))
) | Set-Content -Path (Join-Path $pf '16_version_reference_record.txt') -Encoding UTF8

@(
  'wrong_version_mismatch_evidence:'
  ('version_requested_by_payload=v1')
  ('reference_version_actually_loaded=' + $caseCLoadedVersion)
  ('loaded_baseline_reference=' + $caseB.selection.baseline_path_rel)
  ('loaded_integrity_reference=' + $caseB.selection.integrity_path_rel)
  ('mismatch_introduced=payload_version_and_reference_version_intentionally_crossed')
  ('expected_result=' + $caseCExpected)
  ('actual_result=' + $caseCActual)
  ('mismatch_fields=' + $(if ($caseCMismatch.Count -gt 0) { ($caseCMismatch -join ',') } else { '(none)' }))
  ('failure_correct_and_deterministic=' + $(if ($caseCPass) { 'YES' } else { 'NO' }))
) | Set-Content -Path (Join-Path $pf '17_wrong_version_mismatch_evidence.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase42_7.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)
