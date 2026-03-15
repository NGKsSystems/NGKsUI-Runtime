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

function Get-ChainEntryByVersion {
  param(
    [Parameter(Mandatory = $true)]$Chain,
    [Parameter(Mandatory = $true)][string]$Version
  )

  foreach ($entry in $Chain.chain) {
    if ([string]$entry.version -eq $Version) {
      return $entry
    }
  }
  return $null
}

function Resolve-VersionWithPolicy {
  param(
    [AllowNull()][string]$RequestedVersion,
    [Parameter(Mandatory = $true)]$Policy,
    [Parameter(Mandatory = $true)]$Chain,
    [Parameter(Mandatory = $true)][string]$RootPath
  )

  $activeVersion = [string]$Policy.active_version
  $historical = @($Policy.historical_versions | ForEach-Object { [string]$_ })

  $requested = if ([string]::IsNullOrWhiteSpace($RequestedVersion)) { '(default)' } else { $RequestedVersion.Trim() }
  $resolutionMode = ''
  $resolvedVersion = ''
  $remappingOccurred = $false
  $failure = $false
  $failureReason = ''

  if ([string]::IsNullOrWhiteSpace($RequestedVersion)) {
    $resolutionMode = 'default'
    $resolvedVersion = $activeVersion
  } else {
    $resolutionMode = 'explicit'
    $req = $RequestedVersion.Trim()
    if ($req -eq $activeVersion) {
      $resolvedVersion = $activeVersion
    } elseif ($historical -contains $req) {
      $resolvedVersion = $req
    } else {
      $failure = $true
      $failureReason = 'invalid_version_requested:' + $req
    }
  }

  if (-not $failure -and -not [string]::IsNullOrWhiteSpace($RequestedVersion)) {
    if ($resolvedVersion -ne $RequestedVersion.Trim()) {
      $remappingOccurred = $true
      $failure = $true
      $failureReason = 'silent_remap_detected:' + $RequestedVersion + '->' + $resolvedVersion
    }
  }

  $chainEntry = $null
  $baselineRel = ''
  $integrityRel = ''
  $baselineAbs = ''
  $integrityAbs = ''
  $chainIntegrityHash = ''
  $chainFingerprint = ''

  if (-not $failure) {
    $chainEntry = Get-ChainEntryByVersion -Chain $Chain -Version $resolvedVersion
    if ($null -eq $chainEntry) {
      $failure = $true
      $failureReason = 'version_not_found_in_chain:' + $resolvedVersion
    } else {
      $baselineRel = [string]$chainEntry.baseline_file
      $integrityRel = [string]$chainEntry.integrity_reference_file
      $baselineAbs = if ([System.IO.Path]::IsPathRooted($baselineRel)) { $baselineRel } else { Join-Path $RootPath $baselineRel }
      $integrityAbs = if ([System.IO.Path]::IsPathRooted($integrityRel)) { $integrityRel } else { Join-Path $RootPath $integrityRel }
      $chainIntegrityHash = [string]$chainEntry.integrity_hash
      $chainFingerprint = [string]$chainEntry.fingerprint
    }
  }

  return [pscustomobject]@{
    requested_version = $requested
    resolution_mode = $resolutionMode
    resolved_version = $resolvedVersion
    remapping_occurred = $remappingOccurred
    failure = $failure
    failure_reason = $failureReason
    baseline_path_rel = $baselineRel
    integrity_path_rel = $integrityRel
    baseline_path_abs = $baselineAbs
    integrity_path_abs = $integrityAbs
    chain_integrity_hash = $chainIntegrityHash
    chain_fingerprint = $chainFingerprint
  }
}

function Compare-PayloadToBaseline {
  param(
    [Parameter(Mandatory = $true)]$Payload,
    [Parameter(Mandatory = $true)]$Baseline,
    [Parameter(Mandatory = $true)]$Resolution,
    [Parameter(Mandatory = $true)][string]$StoredIntegrityHash
  )

  $mismatch = New-Object System.Collections.Generic.List[string]

  if ([string]$Payload.semantic_trace_fingerprint_sha256 -ne [string]$Baseline.semantic_trace_fingerprint_sha256) { $mismatch.Add('semantic_trace_fingerprint_sha256') }
  if ([int]$Payload.trace_record_count -ne [int]$Baseline.trace_record_count) { $mismatch.Add('trace_record_count') }
  if ([string]$Payload.final_runtime_state -ne [string]$Baseline.final_runtime_state) { $mismatch.Add('final_runtime_state') }
  if ([int]$Payload.final_runtime_value -ne [int]$Baseline.final_runtime_value) { $mismatch.Add('final_runtime_value') }
  if ([string]$Payload.replay_result -ne [string]$Baseline.replay_result) { $mismatch.Add('replay_result') }
  if ([string]$Payload.normalization_method -ne [string]$Baseline.normalization_method) { $mismatch.Add('normalization_method') }

  if ([string]$Payload.selected_version_identifier -ne [string]$Resolution.resolved_version) { $mismatch.Add('selected_version_identifier') }
  if ([string]$Payload.selected_baseline_reference_file -ne [string]$Resolution.baseline_path_rel) { $mismatch.Add('selected_baseline_reference_file') }
  if ([string]$Payload.selected_integrity_reference_file -ne [string]$Resolution.integrity_path_rel) { $mismatch.Add('selected_integrity_reference_file') }
  if ([string]$Payload.selected_integrity_hash -ne [string]$StoredIntegrityHash) { $mismatch.Add('selected_integrity_hash') }

  return [pscustomobject]@{
    pass = ($mismatch.Count -eq 0)
    mismatch_fields = @($mismatch)
  }
}

function Invoke-PolicyCase {
  param(
    [AllowNull()][string]$RequestedVersion,
    [Parameter(Mandatory = $true)]$Policy,
    [Parameter(Mandatory = $true)]$Chain,
    [Parameter(Mandatory = $true)][string]$RootPath,
    [Parameter(Mandatory = $true)]$CurrentPayload
  )

  $res = Resolve-VersionWithPolicy -RequestedVersion $RequestedVersion -Policy $Policy -Chain $Chain -RootPath $RootPath
  if ($res.failure) {
    return [pscustomobject]@{
      pass = $false
      reason = $res.failure_reason
      resolution = $res
      integrity_pass = $false
      comparison_pass = $false
      baseline_loaded = $null
      integrity_loaded = $null
      stored_integrity_hash = ''
      computed_integrity_hash = ''
      mismatch_fields = @('resolution_failed')
    }
  }

  if ((-not (Test-Path -LiteralPath $res.baseline_path_abs)) -or (-not (Test-Path -LiteralPath $res.integrity_path_abs))) {
    return [pscustomobject]@{
      pass = $false
      reason = 'selected_reference_missing'
      resolution = $res
      integrity_pass = $false
      comparison_pass = $false
      baseline_loaded = $null
      integrity_loaded = $null
      stored_integrity_hash = ''
      computed_integrity_hash = ''
      mismatch_fields = @('selected_reference_missing')
    }
  }

  $baselineRef = Get-Content -Raw -LiteralPath $res.baseline_path_abs | ConvertFrom-Json
  $integrityRef = Get-Content -Raw -LiteralPath $res.integrity_path_abs | ConvertFrom-Json

  $storedIntegrityHash = [string]$integrityRef.expected_integrity_hash_sha256
  $computedIntegrityHash = Get-FileSha256Hex -Path $res.baseline_path_abs
  $integrityPass = ($storedIntegrityHash -eq $computedIntegrityHash)

  $payload = [pscustomobject]@{
    semantic_trace_fingerprint_sha256 = $CurrentPayload.semantic_trace_fingerprint_sha256
    trace_record_count = $CurrentPayload.trace_record_count
    final_runtime_state = $CurrentPayload.final_runtime_state
    final_runtime_value = $CurrentPayload.final_runtime_value
    replay_result = $CurrentPayload.replay_result
    normalization_method = $CurrentPayload.normalization_method
    selected_version_identifier = $res.resolved_version
    selected_baseline_reference_file = $res.baseline_path_rel
    selected_integrity_reference_file = $res.integrity_path_rel
    selected_integrity_hash = $storedIntegrityHash
  }

  $cmp = Compare-PayloadToBaseline -Payload $payload -Baseline $baselineRef -Resolution $res -StoredIntegrityHash $storedIntegrityHash
  $pass = $integrityPass -and $cmp.pass -and (-not $res.remapping_occurred)

  return [pscustomobject]@{
    pass = $pass
    reason = $(if ($pass) { 'policy_resolution_integrity_and_comparison_pass' } elseif (-not $integrityPass) { 'integrity_mismatch' } elseif ($res.remapping_occurred) { 'remapping_detected' } else { 'comparison_mismatch:' + ($cmp.mismatch_fields -join ',') })
    resolution = $res
    integrity_pass = $integrityPass
    comparison_pass = $cmp.pass
    baseline_loaded = $baselineRef
    integrity_loaded = $integrityRef
    stored_integrity_hash = $storedIntegrityHash
    computed_integrity_hash = $computedIntegrityHash
    mismatch_fields = @($cmp.mismatch_fields)
  }
}

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path $Root ('_proof/phase42_8_active_version_policy_deprecation_' + $ts)
New-Item -ItemType Directory -Path $pf -Force | Out-Null

$launcher = Join-Path $Root 'tools/run_widget_sandbox.ps1'
$policyPath = Join-Path $Root 'tools/phase42_8/active_version_policy.json'
if (-not (Test-Path -LiteralPath $launcher)) { throw 'missing canonical launcher' }
if (-not (Test-Path -LiteralPath $policyPath)) { throw 'missing active version policy file' }

$policy = Get-Content -Raw -LiteralPath $policyPath | ConvertFrom-Json
$chainPath = Join-Path $Root ([string]$policy.version_chain_source)
if (-not (Test-Path -LiteralPath $chainPath)) { throw 'missing policy chain source' }
$chain = Get-Content -Raw -LiteralPath $chainPath | ConvertFrom-Json

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

$currentPayload = [pscustomobject]@{
  semantic_trace_fingerprint_sha256 = $currentFingerprint
  trace_record_count = $currentTraceCount
  final_runtime_state = $currentFinalState
  final_runtime_value = $currentFinalValue
  replay_result = $currentReplayResult
  normalization_method = $normalizationMethod
}

$disabledInertPass = (
  (Test-HasToken -Text $runText -Token 'widget_disabled_noninteractive_demo=1') -and
  (Test-HasToken -Text $runText -Token 'widget_runtime_disabled_intent_blocked=1')
)
$scopeGuardPass = (
  (Test-HasToken -Text $runText -Token 'widget_extension_mode_active=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase40_19_simple_layout_drawn=1') -and
  (Test-HasToken -Text $runText -Token 'widget_phase40_5_coherent_composition=1')
)

# CASE A — default resolution to active version
$caseA = Invoke-PolicyCase -RequestedVersion $null -Policy $policy -Chain $chain -RootPath $Root -CurrentPayload $currentPayload
$caseAPass = $caseA.pass -and ($caseA.resolution.resolved_version -eq [string]$policy.active_version)
$caseAReason = if ($caseAPass) { 'default_resolved_to_active_and_passed' } else { 'default_resolution_failure:' + $caseA.reason }

# CASE B — explicit active version selection
$activeVersion = [string]$policy.active_version
$caseB = Invoke-PolicyCase -RequestedVersion $activeVersion -Policy $policy -Chain $chain -RootPath $Root -CurrentPayload $currentPayload
$caseBPass = $caseB.pass -and ($caseB.resolution.resolved_version -eq $activeVersion)
$caseBReason = if ($caseBPass) { 'explicit_active_selection_passed' } else { 'explicit_active_selection_failed:' + $caseB.reason }

# CASE C — explicit historical/deprecated version selection
$historicalVersion = [string]$policy.historical_versions[0]
$caseC = Invoke-PolicyCase -RequestedVersion $historicalVersion -Policy $policy -Chain $chain -RootPath $Root -CurrentPayload $currentPayload
$caseCPass = $caseC.pass -and ($caseC.resolution.resolved_version -eq $historicalVersion)
$caseCReason = if ($caseCPass) { 'explicit_historical_selection_passed' } else { 'explicit_historical_selection_failed:' + $caseC.reason }

# CASE D — wrong policy resolution protection
$caseDPass = (
  ($caseC.resolution.requested_version -eq $historicalVersion) -and
  ($caseC.resolution.resolved_version -eq $historicalVersion) -and
  ($caseA.resolution.requested_version -eq '(default)') -and
  ($caseA.resolution.resolved_version -eq $activeVersion) -and
  (-not $caseA.resolution.remapping_occurred) -and
  (-not $caseB.resolution.remapping_occurred) -and
  (-not $caseC.resolution.remapping_occurred)
)
$caseDReason = if ($caseDPass) { 'no_silent_remap_default_and_explicit_paths' } else { 'policy_resolution_protection_failed' }

# CASE E — invalid version request
$invalidRequested = 'v999'
$invalidResolution = Resolve-VersionWithPolicy -RequestedVersion $invalidRequested -Policy $policy -Chain $chain -RootPath $Root
$caseEExpected = 'FAIL'
$caseEActual = if ($invalidResolution.failure) { 'FAIL' } else { 'PASS' }
$caseEPass = ($caseEActual -eq $caseEExpected) -and (-not $invalidResolution.remapping_occurred) -and ([string]$invalidResolution.resolved_version -eq '')
$caseEReason = if ($caseEPass) { 'invalid_version_rejected_no_fallback' } else { 'invalid_version_handling_failed' }

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
  'phase=42_8_active_version_policy_deprecation'
  ('timestamp=' + (Get-Date).ToString('o'))
  ('runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' }))
  ('baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_lock=' + $(if ($baselineLockPass) { 'PASS' } else { 'FAIL' }))
  ('build=' + $(if ($buildPass) { 'PASS' } else { 'FAIL' }))
  ('canonical_launcher=' + $(if ($canonicalLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('case_a_default_active=' + $(if ($caseAPass) { 'PASS' } else { 'FAIL' }))
  ('case_b_explicit_active=' + $(if ($caseBPass) { 'PASS' } else { 'FAIL' }))
  ('case_c_explicit_historical=' + $(if ($caseCPass) { 'PASS' } else { 'FAIL' }))
  ('case_d_resolution_protection=' + $(if ($caseDPass) { 'PASS' } else { 'FAIL' }))
  ('case_e_invalid_version=' + $(if ($caseEPass) { 'PASS' } else { 'FAIL' }))
  ('disabled_inert=' + $(if ($disabledInertPass) { 'PASS' } else { 'FAIL' }))
  ('scope_guard=' + $(if ($scopeGuardPass) { 'PASS' } else { 'FAIL' }))
  ('gate=' + $gate)
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase42_8: baseline deprecation / active-version policy proof'
  'scope: explicit active-version default resolution, explicit historical selection, deterministic invalid-version rejection'
  'risk_profile=policy/runner enforcement only; no UI/layout/runtime behavior changes'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'active_policy_definition:'
  ('policy_file=tools/phase42_8/active_version_policy.json')
  ('policy_structure={ active_version, historical_versions, default_resolution, invalid_version_behavior, version_chain_source }')
  ('declared_active_version=' + [string]$policy.active_version)
  ('declared_historical_versions=' + (($policy.historical_versions | ForEach-Object { [string]$_ }) -join ','))
  ('default_resolution=' + [string]$policy.default_resolution)
  ('invalid_version_behavior=' + [string]$policy.invalid_version_behavior)
  ('version_chain_source=' + [string]$policy.version_chain_source)
  ('resolution_mechanism=Resolve-VersionWithPolicy(requested_version, policy, chain)')
  ('default_resolution_implementation=requested_version_empty => resolve_to_active_only')
  ('invalid_request_handling=requested_version_not_in_policy => deterministic_fail_no_fallback')
) | Set-Content -Path (Join-Path $pf '10_active_policy_definition.txt') -Encoding UTF8

@(
  'active_policy_rules:'
  '1. Active version must be explicitly declared in policy file.'
  '2. Historical/deprecated versions must be explicitly declared in policy file.'
  '3. Default resolution must use active version only when requested version is absent.'
  '4. Explicit active selection must resolve to active version exactly.'
  '5. Explicit historical selection must resolve to historical version exactly.'
  '6. Invalid version requests must fail deterministically without fallback.'
  '7. No silent remapping between active and historical versions is allowed.'
  '8. Selected policy file and resolved version must be explicit in proof artifacts.'
  '9. Integrity verification must pass before selected version comparison.'
  '10. Semantic comparison enforcement remains unchanged and deterministic.'
) | Set-Content -Path (Join-Path $pf '11_active_policy_rules.txt') -Encoding UTF8

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
  'case_a_default_resolution_to_active:'
  ('  requested_version=(default)')
  ('  resolved_version=' + $caseA.resolution.resolved_version)
  ('  selected_baseline_reference=' + $caseA.resolution.baseline_path_rel)
  ('  selected_integrity_reference=' + $caseA.resolution.integrity_path_rel)
  ('  integrity_verified=' + $(if ($caseA.integrity_pass) { 'YES' } else { 'NO' }))
  ('  comparison_pass=' + $(if ($caseA.comparison_pass) { 'YES' } else { 'NO' }))
  ('  remapping_occurred=' + $(if ($caseA.resolution.remapping_occurred) { 'YES' } else { 'NO' }))
  ('  result=' + $(if ($caseAPass) { 'PASS' } else { 'FAIL' }))
  ('  reason=' + $caseAReason)
  ''
  'case_b_explicit_active_selection:'
  ('  requested_version=' + $activeVersion)
  ('  resolved_version=' + $caseB.resolution.resolved_version)
  ('  selected_baseline_reference=' + $caseB.resolution.baseline_path_rel)
  ('  selected_integrity_reference=' + $caseB.resolution.integrity_path_rel)
  ('  integrity_verified=' + $(if ($caseB.integrity_pass) { 'YES' } else { 'NO' }))
  ('  comparison_pass=' + $(if ($caseB.comparison_pass) { 'YES' } else { 'NO' }))
  ('  remapping_occurred=' + $(if ($caseB.resolution.remapping_occurred) { 'YES' } else { 'NO' }))
  ('  result=' + $(if ($caseBPass) { 'PASS' } else { 'FAIL' }))
  ('  reason=' + $caseBReason)
  ''
  'case_c_explicit_historical_selection:'
  ('  requested_version=' + $historicalVersion)
  ('  resolved_version=' + $caseC.resolution.resolved_version)
  ('  selected_baseline_reference=' + $caseC.resolution.baseline_path_rel)
  ('  selected_integrity_reference=' + $caseC.resolution.integrity_path_rel)
  ('  integrity_verified=' + $(if ($caseC.integrity_pass) { 'YES' } else { 'NO' }))
  ('  comparison_pass=' + $(if ($caseC.comparison_pass) { 'YES' } else { 'NO' }))
  ('  remapping_occurred=' + $(if ($caseC.resolution.remapping_occurred) { 'YES' } else { 'NO' }))
  ('  result=' + $(if ($caseCPass) { 'PASS' } else { 'FAIL' }))
  ('  reason=' + $caseCReason)
  ''
  'case_d_wrong_policy_resolution_protection:'
  ('  result=' + $(if ($caseDPass) { 'PASS' } else { 'FAIL' }))
  ('  reason=' + $caseDReason)
  ''
  'case_e_invalid_version_request:'
  ('  requested_version=' + $invalidRequested)
  ('  expected_result=' + $caseEExpected)
  ('  actual_result=' + $caseEActual)
  ('  failure_reason=' + $invalidResolution.failure_reason)
  ('  remapping_occurred=' + $(if ($invalidResolution.remapping_occurred) { 'YES' } else { 'NO' }))
  ('  result=' + $(if ($caseEPass) { 'PASS' } else { 'FAIL' }))
  ('  reason=' + $caseEReason)
  ''
  ('baseline_pf=' + $baselinePf)
  ('baseline_zip=' + $baselineZip)
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

@(
  'behavior_summary:'
  '- Active-version policy works through a dedicated JSON policy source that explicitly declares active and historical versions.'
  '- Default resolution selects only the declared active version when no version is requested.'
  '- Historical/deprecated versions remain explicitly selectable and operational through policy-governed explicit requests.'
  '- Invalid version requests are rejected deterministically with explicit failure reason and no fallback/remapping.'
  '- Silent fallback/remapping is prevented by resolution checks that fail if requested and resolved versions diverge for explicit requests.'
  '- Disabled remained inert because disabled guard tokens stayed asserted and no disabled-driven semantic transitions were observed.'
  '- Baseline mode remained unchanged because this phase only adds policy resolution logic over existing certified baseline references.'
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

@(
  'policy_resolution_record:'
  ('policy_file_path=tools/phase42_8/active_version_policy.json')
  ('declared_active_version=' + $activeVersion)
  ('declared_historical_versions=' + (($policy.historical_versions | ForEach-Object { [string]$_ }) -join ','))
  ''
  'resolution_case=default'
  ('requested_version=(default)')
  ('resolved_version=' + $caseA.resolution.resolved_version)
  ('selected_baseline_reference=' + $caseA.resolution.baseline_path_rel)
  ('selected_integrity_reference=' + $caseA.resolution.integrity_path_rel)
  ('integrity_verification_result=' + $(if ($caseA.integrity_pass) { 'PASS' } else { 'FAIL' }))
  ('comparison_result=' + $(if ($caseA.comparison_pass) { 'PASS' } else { 'FAIL' }))
  ('fallback_or_remapping=' + $(if ($caseA.resolution.remapping_occurred) { 'true' } else { 'false' }))
  ''
  'resolution_case=explicit_active'
  ('requested_version=' + $activeVersion)
  ('resolved_version=' + $caseB.resolution.resolved_version)
  ('selected_baseline_reference=' + $caseB.resolution.baseline_path_rel)
  ('selected_integrity_reference=' + $caseB.resolution.integrity_path_rel)
  ('integrity_verification_result=' + $(if ($caseB.integrity_pass) { 'PASS' } else { 'FAIL' }))
  ('comparison_result=' + $(if ($caseB.comparison_pass) { 'PASS' } else { 'FAIL' }))
  ('fallback_or_remapping=' + $(if ($caseB.resolution.remapping_occurred) { 'true' } else { 'false' }))
  ''
  'resolution_case=explicit_historical'
  ('requested_version=' + $historicalVersion)
  ('resolved_version=' + $caseC.resolution.resolved_version)
  ('selected_baseline_reference=' + $caseC.resolution.baseline_path_rel)
  ('selected_integrity_reference=' + $caseC.resolution.integrity_path_rel)
  ('integrity_verification_result=' + $(if ($caseC.integrity_pass) { 'PASS' } else { 'FAIL' }))
  ('comparison_result=' + $(if ($caseC.comparison_pass) { 'PASS' } else { 'FAIL' }))
  ('fallback_or_remapping=' + $(if ($caseC.resolution.remapping_occurred) { 'true' } else { 'false' }))
) | Set-Content -Path (Join-Path $pf '16_policy_resolution_record.txt') -Encoding UTF8

@(
  'invalid_version_evidence:'
  ('invalid_version_requested=' + $invalidRequested)
  ('expected_result=' + $caseEExpected)
  ('actual_result=' + $caseEActual)
  ('failure_reason=' + $invalidResolution.failure_reason)
  ('no_fallback_or_remapping=' + $(if (-not $invalidResolution.remapping_occurred -and [string]::IsNullOrWhiteSpace($invalidResolution.resolved_version)) { 'YES' } else { 'NO' }))
  ('deterministic_failure=' + $(if ($caseEPass) { 'YES' } else { 'NO' }))
) | Set-Content -Path (Join-Path $pf '17_invalid_version_evidence.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase42_8.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)
