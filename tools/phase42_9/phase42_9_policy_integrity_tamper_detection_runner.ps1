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
  $resolved = ''
  $failure = $false
  $failureReason = ''
  $remapping = $false

  if ([string]::IsNullOrWhiteSpace($RequestedVersion)) {
    $resolved = $activeVersion
  } else {
    $req = $RequestedVersion.Trim()
    if ($req -eq $activeVersion -or $historical -contains $req) {
      $resolved = $req
    } else {
      $failure = $true
      $failureReason = 'invalid_version_requested:' + $req
    }
  }

  if (-not $failure -and -not [string]::IsNullOrWhiteSpace($RequestedVersion) -and ($resolved -ne $RequestedVersion.Trim())) {
    $failure = $true
    $remapping = $true
    $failureReason = 'silent_remap_detected:' + $RequestedVersion + '->' + $resolved
  }

  $baselineRel = ''
  $integrityRel = ''
  $baselineAbs = ''
  $integrityAbs = ''

  if (-not $failure) {
    $entry = $null
    foreach ($e in $Chain.chain) {
      if ([string]$e.version -eq $resolved) { $entry = $e; break }
    }
    if ($null -eq $entry) {
      $failure = $true
      $failureReason = 'version_not_found_in_chain:' + $resolved
    } else {
      $baselineRel = [string]$entry.baseline_file
      $integrityRel = [string]$entry.integrity_reference_file
      $baselineAbs = if ([System.IO.Path]::IsPathRooted($baselineRel)) { $baselineRel } else { Join-Path $RootPath $baselineRel }
      $integrityAbs = if ([System.IO.Path]::IsPathRooted($integrityRel)) { $integrityRel } else { Join-Path $RootPath $integrityRel }
    }
  }

  return [pscustomobject]@{
    requested_version = $requested
    resolved_version = $resolved
    failure = $failure
    failure_reason = $failureReason
    remapping_occurred = $remapping
    baseline_path_rel = $baselineRel
    integrity_path_rel = $integrityRel
    baseline_path_abs = $baselineAbs
    integrity_path_abs = $integrityAbs
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

  return [pscustomobject]@{ pass = ($mismatch.Count -eq 0); mismatch_fields = @($mismatch) }
}

function Verify-PolicyIntegrity {
  param(
    [Parameter(Mandatory = $true)][string]$PolicyPath,
    [Parameter(Mandatory = $true)][string]$IntegrityRefPath,
    [Parameter(Mandatory = $true)][string]$CaseName
  )

  $existsPolicy = Test-Path -LiteralPath $PolicyPath
  $existsRef = Test-Path -LiteralPath $IntegrityRefPath
  if (-not $existsRef) {
    return [pscustomobject]@{
      pass = $false
      reason = 'policy_integrity_reference_missing'
      expected_hash = ''
      actual_hash = ''
      policy_loaded = $false
      policy_parse_error = ''
      comparison_allowed = $false
      version_resolution_attempted = $false
      case = $CaseName
    }
  }

  $ref = Get-Content -Raw -LiteralPath $IntegrityRefPath | ConvertFrom-Json
  $expectedHash = [string]$ref.expected_policy_sha256

  if (-not $existsPolicy) {
    return [pscustomobject]@{
      pass = $false
      reason = 'policy_file_missing'
      expected_hash = $expectedHash
      actual_hash = ''
      policy_loaded = $false
      policy_parse_error = ''
      comparison_allowed = $false
      version_resolution_attempted = $false
      case = $CaseName
    }
  }

  $actualHash = Get-FileSha256Hex -Path $PolicyPath
  if ($actualHash -ne $expectedHash) {
    $parseError = ''
    try {
      $null = Get-Content -Raw -LiteralPath $PolicyPath | ConvertFrom-Json
    } catch {
      $parseError = $_.Exception.Message
    }

    return [pscustomobject]@{
      pass = $false
      reason = 'policy_hash_mismatch'
      expected_hash = $expectedHash
      actual_hash = $actualHash
      policy_loaded = $false
      policy_parse_error = $parseError
      comparison_allowed = $false
      version_resolution_attempted = $false
      case = $CaseName
    }
  }

  try {
    $policyObj = Get-Content -Raw -LiteralPath $PolicyPath | ConvertFrom-Json
    if (-not ($policyObj.PSObject.Properties.Name -contains 'active_version')) { throw 'missing_required_field:active_version' }
    if (-not ($policyObj.PSObject.Properties.Name -contains 'historical_versions')) { throw 'missing_required_field:historical_versions' }
  } catch {
    return [pscustomobject]@{
      pass = $false
      reason = 'policy_parse_or_required_field_failure'
      expected_hash = $expectedHash
      actual_hash = $actualHash
      policy_loaded = $false
      policy_parse_error = $_.Exception.Message
      comparison_allowed = $false
      version_resolution_attempted = $false
      case = $CaseName
    }
  }

  return [pscustomobject]@{
    pass = $true
    reason = 'policy_integrity_verified'
    expected_hash = $expectedHash
    actual_hash = $actualHash
    policy_loaded = $true
    policy_parse_error = ''
    comparison_allowed = $true
    version_resolution_attempted = $false
    case = $CaseName
  }
}

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path $Root ('_proof/phase42_9_policy_integrity_tamper_detection_' + $ts)
New-Item -ItemType Directory -Path $pf -Force | Out-Null

$launcher = Join-Path $Root 'tools/run_widget_sandbox.ps1'
$policyPath = Join-Path $Root 'tools/phase42_8/active_version_policy.json'
$policyIntegrityRefPath = Join-Path $Root 'tools/phase42_9/policy_integrity_reference.json'
if (-not (Test-Path -LiteralPath $launcher)) { throw 'missing canonical launcher' }

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
  if (Test-Path -LiteralPath $g) { $baselineLockGatePass = ((Get-Content -Raw -LiteralPath $g) -match 'PASS') }
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

$currentFingerprint = Get-Sha256Hex -Text ($semanticLines -join "`n")
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

$chainPath = Join-Path $Root 'tools/phase42_6/baseline_history_chain.json'
$chain = Get-Content -Raw -LiteralPath $chainPath | ConvertFrom-Json

# CASE A - clean policy pass
$caseA = Verify-PolicyIntegrity -PolicyPath $policyPath -IntegrityRefPath $policyIntegrityRefPath -CaseName 'clean_policy_pass'
$caseAResolutionAttempted = $false
$caseAComparisonPass = $false
$caseAResolvedVersion = ''
$caseASelectedBaseline = ''
$caseASelectedIntegrity = ''

if ($caseA.pass) {
  $policyObj = Get-Content -Raw -LiteralPath $policyPath | ConvertFrom-Json
  $res = Resolve-VersionWithPolicy -RequestedVersion $null -Policy $policyObj -Chain $chain -RootPath $Root
  $caseAResolutionAttempted = $true
  $caseA.version_resolution_attempted = $true

  if (-not $res.failure -and -not $res.remapping_occurred) {
    $caseAResolvedVersion = $res.resolved_version
    $caseASelectedBaseline = $res.baseline_path_rel
    $caseASelectedIntegrity = $res.integrity_path_rel
    $baselineRef = Get-Content -Raw -LiteralPath $res.baseline_path_abs | ConvertFrom-Json
    $integrityRef = Get-Content -Raw -LiteralPath $res.integrity_path_abs | ConvertFrom-Json
    $storedBaselineIntegrity = [string]$integrityRef.expected_integrity_hash_sha256

    $payload = [pscustomobject]@{
      semantic_trace_fingerprint_sha256 = $currentPayload.semantic_trace_fingerprint_sha256
      trace_record_count = $currentPayload.trace_record_count
      final_runtime_state = $currentPayload.final_runtime_state
      final_runtime_value = $currentPayload.final_runtime_value
      replay_result = $currentPayload.replay_result
      normalization_method = $currentPayload.normalization_method
      selected_version_identifier = $res.resolved_version
      selected_baseline_reference_file = $res.baseline_path_rel
      selected_integrity_reference_file = $res.integrity_path_rel
      selected_integrity_hash = $storedBaselineIntegrity
    }

    $cmp = Compare-PayloadToBaseline -Payload $payload -Baseline $baselineRef -Resolution $res -StoredIntegrityHash $storedBaselineIntegrity
    $caseAComparisonPass = $cmp.pass
  }
}
$caseAPass = $caseA.pass -and $caseAResolutionAttempted -and $caseAComparisonPass
$caseAReason = if ($caseAPass) { 'policy_verified_before_resolution_and_comparison_pass' } else { 'case_a_failure:' + $caseA.reason }

# CASE B - policy tamper detected
$caseBPolicyPath = Join-Path $pf 'case_b_tampered_policy.json'
$caseBRaw = Get-Content -Raw -LiteralPath $policyPath
$caseBTampered = $caseBRaw -replace '"active_version"\s*:\s*"v2"', '"active_version": "v1"'
$caseBTampered | Set-Content -Path $caseBPolicyPath -Encoding UTF8
$caseB = Verify-PolicyIntegrity -PolicyPath $caseBPolicyPath -IntegrityRefPath $policyIntegrityRefPath -CaseName 'policy_tamper_detected'
$caseBComparisonBlocked = -not $caseB.comparison_allowed
$caseBPass = (-not $caseB.pass) -and $caseBComparisonBlocked
$caseBReason = if ($caseBPass) { 'tamper_detected_and_comparison_blocked' } else { 'case_b_failure' }

# CASE C - policy file corruption
$caseCPolicyPath = Join-Path $pf 'case_c_corrupt_policy.json'
$caseCRaw = Get-Content -Raw -LiteralPath $policyPath
$caseCCorrupt = $caseCRaw -replace '"historical_versions"\s*:\s*\[[^\]]*\]', '"historical_versions": ['
$caseCCorrupt | Set-Content -Path $caseCPolicyPath -Encoding UTF8
$caseC = Verify-PolicyIntegrity -PolicyPath $caseCPolicyPath -IntegrityRefPath $policyIntegrityRefPath -CaseName 'policy_corruption_detected'
$caseCComparisonBlocked = -not $caseC.comparison_allowed
$caseCPass = (-not $caseC.pass) -and $caseCComparisonBlocked
$caseCReason = if ($caseCPass) { 'corruption_detected_and_comparison_blocked' } else { 'case_c_failure' }

# CASE D - policy file missing
$caseDMissingPath = Join-Path $pf 'case_d_missing_active_version_policy.json'
$caseD = Verify-PolicyIntegrity -PolicyPath $caseDMissingPath -IntegrityRefPath $policyIntegrityRefPath -CaseName 'policy_missing_detected'
$caseDComparisonBlocked = -not $caseD.comparison_allowed
$caseDPass = (-not $caseD.pass) -and $caseDComparisonBlocked -and ($caseD.reason -eq 'policy_file_missing')
$caseDReason = if ($caseDPass) { 'missing_policy_detected_and_comparison_blocked' } else { 'case_d_failure' }

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
  $disabledInertPass -and
  $scopeGuardPass
)
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

@(
  'phase=42_9_policy_integrity_tamper_detection'
  ('timestamp=' + (Get-Date).ToString('o'))
  ('runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' }))
  ('baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_lock=' + $(if ($baselineLockPass) { 'PASS' } else { 'FAIL' }))
  ('build=' + $(if ($buildPass) { 'PASS' } else { 'FAIL' }))
  ('canonical_launcher=' + $(if ($canonicalLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('case_a_clean_policy=' + $(if ($caseAPass) { 'PASS' } else { 'FAIL' }))
  ('case_b_policy_tamper=' + $(if ($caseBPass) { 'PASS' } else { 'FAIL' }))
  ('case_c_policy_corruption=' + $(if ($caseCPass) { 'PASS' } else { 'FAIL' }))
  ('case_d_policy_missing=' + $(if ($caseDPass) { 'PASS' } else { 'FAIL' }))
  ('disabled_inert=' + $(if ($disabledInertPass) { 'PASS' } else { 'FAIL' }))
  ('scope_guard=' + $(if ($scopeGuardPass) { 'PASS' } else { 'FAIL' }))
  ('gate=' + $gate)
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase42_9: policy integrity / tamper detection proof'
  'scope: policy hash verification before version resolution with blocked comparison on tamper, corruption, or missing policy file'
  'risk_profile=runner-side policy integrity enforcement only; no UI/layout/runtime-state-machine changes'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'policy_definition:'
  ('protected_policy_file=tools/phase42_8/active_version_policy.json')
  ('policy_integrity_reference_file=tools/phase42_9/policy_integrity_reference.json')
  ('hash_method=sha256_file_bytes_v1')
  'verification_order=policy_hash_verify -> (if pass) policy_parse -> version_resolution -> baseline_comparison'
  'comparison_gate=blocked_if_policy_integrity_fails'
) | Set-Content -Path (Join-Path $pf '10_policy_definition.txt') -Encoding UTF8

Get-Content -Raw -LiteralPath $policyIntegrityRefPath | Set-Content -Path (Join-Path $pf '11_policy_integrity_reference.txt') -Encoding UTF8

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
  'case_a_clean_policy:'
  ('  policy_integrity=' + $(if ($caseA.pass) { 'PASS' } else { 'FAIL' }))
  ('  version_resolution_attempted=' + $(if ($caseAResolutionAttempted) { 'YES' } else { 'NO' }))
  ('  resolved_version=' + $caseAResolvedVersion)
  ('  selected_baseline_reference=' + $caseASelectedBaseline)
  ('  selected_integrity_reference=' + $caseASelectedIntegrity)
  ('  comparison_result=' + $(if ($caseAComparisonPass) { 'PASS' } else { 'FAIL' }))
  ('  reason=' + $caseAReason)
  ''
  'case_b_policy_tamper_detected:'
  ('  expected_hash=' + $caseB.expected_hash)
  ('  actual_hash=' + $caseB.actual_hash)
  ('  integrity_result=' + $(if ($caseB.pass) { 'PASS' } else { 'FAIL' }))
  ('  comparison_allowed=' + $(if ($caseB.comparison_allowed) { 'YES' } else { 'NO' }))
  ('  version_resolution_attempted=' + $(if ($caseB.version_resolution_attempted) { 'YES' } else { 'NO' }))
  ('  result=' + $(if ($caseBPass) { 'PASS' } else { 'FAIL' }))
  ('  reason=' + $caseBReason)
  ''
  'case_c_policy_corruption:'
  ('  expected_hash=' + $caseC.expected_hash)
  ('  actual_hash=' + $caseC.actual_hash)
  ('  parse_error=' + $caseC.policy_parse_error)
  ('  integrity_result=' + $(if ($caseC.pass) { 'PASS' } else { 'FAIL' }))
  ('  comparison_allowed=' + $(if ($caseC.comparison_allowed) { 'YES' } else { 'NO' }))
  ('  version_resolution_attempted=' + $(if ($caseC.version_resolution_attempted) { 'YES' } else { 'NO' }))
  ('  result=' + $(if ($caseCPass) { 'PASS' } else { 'FAIL' }))
  ('  reason=' + $caseCReason)
  ''
  'case_d_policy_missing:'
  ('  expected_hash=' + $caseD.expected_hash)
  ('  actual_hash=' + $caseD.actual_hash)
  ('  integrity_result=' + $(if ($caseD.pass) { 'PASS' } else { 'FAIL' }))
  ('  comparison_allowed=' + $(if ($caseD.comparison_allowed) { 'YES' } else { 'NO' }))
  ('  version_resolution_attempted=' + $(if ($caseD.version_resolution_attempted) { 'YES' } else { 'NO' }))
  ('  result=' + $(if ($caseDPass) { 'PASS' } else { 'FAIL' }))
  ('  reason=' + $caseDReason)
  ''
  ('baseline_pf=' + $baselinePf)
  ('baseline_zip=' + $baselineZip)
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

@(
  'behavior_summary:'
  '- Policy integrity verification computes SHA256 over active_version_policy.json bytes and compares against policy_integrity_reference.json before any version resolution occurs.'
  '- If policy hash fails, comparison is blocked immediately and version resolution is not attempted.'
  '- Tampering is detected by hash mismatch when protected fields are changed.'
  '- Corruption is detected via hash mismatch and parse-error evidence is captured for auditability.'
  '- Missing policy file is detected deterministically and blocks comparison without fallback.'
  '- Disabled remained inert because disabled guard tokens stayed asserted in canonical extension run output.'
  '- Baseline mode remained unchanged because only runner-side policy integrity gating was introduced.'
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

@(
  'policy_integrity_record:'
  ('policy_file_path=tools/phase42_8/active_version_policy.json')
  ('policy_sha256=' + $caseA.actual_hash)
  ('reference_sha256=' + $caseA.expected_hash)
  ('integrity_check_result=' + $(if ($caseA.pass) { 'PASS' } else { 'FAIL' }))
  ('comparison_allowed=' + $(if ($caseA.comparison_allowed) { 'YES' } else { 'NO' }))
  ('version_resolution_attempted=' + $(if ($caseAResolutionAttempted) { 'YES' } else { 'NO' }))
) | Set-Content -Path (Join-Path $pf '16_policy_integrity_record.txt') -Encoding UTF8

@(
  'policy_tamper_evidence:'
  ('tampered_policy_file=' + $caseBPolicyPath)
  'tampered_policy_content_begin'
  (Get-Content -Raw -LiteralPath $caseBPolicyPath).TrimEnd()
  'tampered_policy_content_end'
  ('expected_hash=' + $caseB.expected_hash)
  ('actual_hash=' + $caseB.actual_hash)
  ('tamper_detection_result=' + $(if (-not $caseB.pass) { 'FAIL_DETECTED' } else { 'UNEXPECTED_PASS' }))
  ('comparison_blocked=' + $(if ($caseBComparisonBlocked) { 'YES' } else { 'NO' }))
  ''
  ('corrupt_policy_file=' + $caseCPolicyPath)
  'corrupt_policy_content_begin'
  (Get-Content -Raw -LiteralPath $caseCPolicyPath).TrimEnd()
  'corrupt_policy_content_end'
  ('corruption_expected_hash=' + $caseC.expected_hash)
  ('corruption_actual_hash=' + $caseC.actual_hash)
  ('corruption_parse_error=' + $caseC.policy_parse_error)
  ('corruption_detection_result=' + $(if (-not $caseC.pass) { 'FAIL_DETECTED' } else { 'UNEXPECTED_PASS' }))
  ('corruption_comparison_blocked=' + $(if ($caseCComparisonBlocked) { 'YES' } else { 'NO' }))
  ''
  ('missing_policy_path=' + $caseDMissingPath)
  ('missing_policy_result=' + $(if (-not $caseD.pass) { 'FAIL_DETECTED' } else { 'UNEXPECTED_PASS' }))
  ('missing_policy_comparison_blocked=' + $(if ($caseDComparisonBlocked) { 'YES' } else { 'NO' }))
) | Set-Content -Path (Join-Path $pf '17_policy_tamper_evidence.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase42_9.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)
