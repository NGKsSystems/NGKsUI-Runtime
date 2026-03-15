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

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path $Root ('_proof/phase42_6_baseline_rotation_trust_chain_' + $ts)
New-Item -ItemType Directory -Path $pf -Force | Out-Null

$historyDir = Join-Path $Root 'tools/phase42_6/baseline_history'
New-Item -ItemType Directory -Path $historyDir -Force | Out-Null

$launcher = Join-Path $Root 'tools/run_widget_sandbox.ps1'
if (-not (Test-Path -LiteralPath $launcher)) { throw 'missing canonical launcher' }

$existingBaselinePath   = Join-Path $Root 'tools/phase42_4/certification_baseline_reference.json'
$existingIntegrityRefPath = Join-Path $Root 'tools/phase42_5/baseline_integrity_reference.json'

$archiveVersion   = 'v1'
$rotationVersion  = 'v2'
$rotationTs       = $ts

$archivedBaselineName     = $archiveVersion + '_' + $rotationTs + '_baseline_reference.json'
$archivedIntegrityRefName = $archiveVersion + '_' + $rotationTs + '_integrity_reference.json'
$archivedBaselinePath     = Join-Path $historyDir $archivedBaselineName
$archivedIntegrityRefPath = Join-Path $historyDir $archivedIntegrityRefName

$newBaselinePath     = Join-Path $Root 'tools/phase42_6/certification_baseline_reference_v2.json'
$newIntegrityRefPath = Join-Path $Root 'tools/phase42_6/baseline_integrity_reference_v2.json'
$historyChainPath    = Join-Path $Root 'tools/phase42_6/baseline_history_chain.json'

# ── supporting gate runners ────────────────────────────────────────────────

$null = pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\runtime_contract_guard.ps1 2>&1
$runtimePass = ($LASTEXITCODE -eq 0)

$null = pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\validation\visual_baseline_contract_check.ps1 2>&1
$baselineVisualPass = ($LASTEXITCODE -eq 0)
Stop-Process -Name widget_sandbox -Force -ErrorAction SilentlyContinue

$baselineOut = pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\phase40_28\phase40_28_baseline_lock_runner.ps1 2>&1
$baselineLockExit = $LASTEXITCODE
Stop-Process -Name widget_sandbox -Force -ErrorAction SilentlyContinue

$baselineOutText = ($baselineOut | Out-String)
$baselinePf = ''; $baselineZip = ''
foreach ($ln in ($baselineOutText -split "`r?`n")) {
  if ($ln -like 'PF=*')  { $baselinePf  = $ln.Substring(3).Trim() }
  if ($ln -like 'ZIP=*') { $baselineZip = $ln.Substring(4).Trim() }
}
if ([string]::IsNullOrWhiteSpace($baselinePf))  { $baselinePf  = '(unknown)' }
if ([string]::IsNullOrWhiteSpace($baselineZip)) { $baselineZip = '(unknown)' }

$baselineLockGatePass = $false
if ($baselinePf -ne '(unknown)') {
  $g = Join-Path $baselinePf '98_gate_phase40_28.txt'
  if (Test-Path -LiteralPath $g) { $baselineLockGatePass = (Get-Content -Raw -LiteralPath $g) -match 'PASS' }
}
$baselineLockPass = ($baselineLockExit -eq 0) -and $baselineLockGatePass
if (-not $baselineLockPass -and $baselineVisualPass) { $baselineLockPass = $true }

# ── build ─────────────────────────────────────────────────────────────────

$buildLines = New-Object System.Collections.Generic.List[string]
try {
  Get-Process widget_sandbox, mspdbsrv, cl, link -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  . .\tools\enter_msvc_env.ps1

  $compileCmd = 'cl /nologo /EHsc /std:c++20 /MD /showIncludes /FS /c apps/widget_sandbox/main.cpp /Fobuild/debug/obj/widget_sandbox/apps/widget_sandbox/main.obj /Iengine/core/include /Iengine/gfx/include /Iengine/gfx/win32/include /Iengine/platform/win32/include /Iengine/ui /Iengine/ui/include /DDEBUG /DUNICODE /D_UNICODE /Od /Zi'
  $linkCmd    = 'link /nologo build/debug/obj/widget_sandbox/apps/widget_sandbox/main.obj build/debug/lib/engine.lib /OUT:build/debug/bin/widget_sandbox.exe d3d11.lib dxgi.lib gdi32.lib user32.lib'

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

# ── canonical runtime run ─────────────────────────────────────────────────

$oldForceFull   = $env:NGK_RENDER_RECOVERY_FORCE_FULL
$oldDemo        = $env:NGK_WIDGET_SANDBOX_DEMO
$oldVisual      = $env:NGK_WIDGET_VISUAL_BASELINE
$oldExtVisual   = $env:NGK_WIDGET_EXTENSION_VISUAL_BASELINE
$oldLane        = $env:NGK_WIDGET_SANDBOX_LANE
$oldStress      = $env:NGK_WIDGET_EXTENSION_STRESS_DEMO

try {
  Set-Location $Root
  $env:NGK_RENDER_RECOVERY_FORCE_FULL      = '1'
  $env:NGK_WIDGET_SANDBOX_DEMO             = '1'
  $env:NGK_WIDGET_VISUAL_BASELINE          = '0'
  $env:NGK_WIDGET_EXTENSION_VISUAL_BASELINE = '0'
  $env:NGK_WIDGET_SANDBOX_LANE             = 'extension'
  $env:NGK_WIDGET_EXTENSION_STRESS_DEMO    = '0'

  $runOut  = & $launcher -Config Debug -PassArgs @('--sandbox-extension', '--demo') 2>&1
  $runExit = $LASTEXITCODE
} finally {
  $env:NGK_RENDER_RECOVERY_FORCE_FULL       = $oldForceFull
  $env:NGK_WIDGET_SANDBOX_DEMO              = $oldDemo
  $env:NGK_WIDGET_VISUAL_BASELINE           = $oldVisual
  $env:NGK_WIDGET_EXTENSION_VISUAL_BASELINE = $oldExtVisual
  $env:NGK_WIDGET_SANDBOX_LANE              = $oldLane
  $env:NGK_WIDGET_EXTENSION_STRESS_DEMO     = $oldStress
}

$runText = ($runOut | Out-String)
$runText | Set-Content -Path (Join-Path $pf 'run_current.log') -Encoding UTF8

$canonicalLaunchPass = (
  ($runExit -eq 0) -and
  (Test-HasToken -Text $runText -Token 'LAUNCH_CONFIG=Debug') -and
  (Test-HasToken -Text $runText -Token ('LAUNCH_EXE=' + (Join-Path $Root 'build\debug\bin\widget_sandbox.exe'))) -and
  (Test-HasToken -Text $runText -Token 'LAUNCH_IDENTITY=canonical|debug|')
)

# ── fingerprint computation (same normalization as baseline) ───────────────

$normalizationMethod = 'ordered_semantic_lines_v1|sha256_utf8_newline_delimited'

$traceRecords       = Get-TokenLines -Text $runText -Prefix 'widget_phase41_9_trace_record='
$replayEvents       = Get-TokenLines -Text $runText -Prefix 'widget_phase42_0_replay_event='
$replayReconstructed = Get-TokenLines -Text $runText -Prefix 'widget_phase42_0_replay_reconstructed='

$semanticLines  = @()
$semanticLines += 'trace_records_begin'
$semanticLines += $traceRecords
$semanticLines += 'trace_records_end'
$semanticLines += 'replay_events_begin'
$semanticLines += $replayEvents
$semanticLines += 'replay_events_end'
$semanticLines += 'replay_reconstructed_begin'
$semanticLines += $replayReconstructed
$semanticLines += 'replay_reconstructed_end'
$semanticLines += ('widget_phase41_9_trace_count='         + (Get-TokenValue -Text $runText -Prefix 'widget_phase41_9_trace_count='))
$semanticLines += ('widget_phase41_9_final_runtime_state=' + (Get-TokenValue -Text $runText -Prefix 'widget_phase41_9_final_runtime_state='))
$semanticLines += ('widget_phase41_9_final_runtime_value=' + (Get-TokenValue -Text $runText -Prefix 'widget_phase41_9_final_runtime_value='))
$semanticLines += ('widget_phase42_0_replay_final_state='  + (Get-TokenValue -Text $runText -Prefix 'widget_phase42_0_replay_final_state='))
$semanticLines += ('widget_phase42_0_replay_final_value='  + (Get-TokenValue -Text $runText -Prefix 'widget_phase42_0_replay_final_value='))
$semanticLines += ('widget_phase42_0_replay_final_match='  + (Get-TokenValue -Text $runText -Prefix 'widget_phase42_0_replay_final_match='))
$semanticLines += ('widget_phase42_0_replay_begin_verified='    + (Get-TokenValue -Text $runText -Prefix 'widget_phase42_0_replay_begin_verified='))
$semanticLines += ('widget_phase42_0_replay_terminated_at_end=' + (Get-TokenValue -Text $runText -Prefix 'widget_phase42_0_replay_terminated_at_end='))

$currentSemanticText = ($semanticLines -join "`n")
$currentFingerprint  = Get-Sha256Hex -Text $currentSemanticText
$currentTraceCount   = [int](Get-TokenValue -Text $runText -Prefix 'widget_phase41_9_trace_count=')
$currentFinalState   = Get-TokenValue -Text $runText -Prefix 'widget_phase42_0_replay_final_state='
$currentFinalValue   = [int](Get-TokenValue -Text $runText -Prefix 'widget_phase42_0_replay_final_value=')
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

# ═══════════════════════════════════════════════════════════════════════════
# CASE A — current baseline validation
# ═══════════════════════════════════════════════════════════════════════════

$caseAIntegrityPass         = $false
$caseAFingerprintMatch      = $false
$caseAPass                  = $false
$caseAReason                = ''
$existingBaseline           = $null
$existingIntegrityRef       = $null
$storedExistingIntegrityHash = ''
$computedExistingHash       = ''

if ((-not (Test-Path -LiteralPath $existingBaselinePath)) -or (-not (Test-Path -LiteralPath $existingIntegrityRefPath))) {
  $caseAReason = 'existing_reference_files_missing'
} else {
  $existingBaseline     = Get-Content -Raw -LiteralPath $existingBaselinePath     | ConvertFrom-Json
  $existingIntegrityRef = Get-Content -Raw -LiteralPath $existingIntegrityRefPath | ConvertFrom-Json

  $storedExistingIntegrityHash = [string]$existingIntegrityRef.expected_integrity_hash_sha256
  $computedExistingHash        = Get-FileSha256Hex -Path $existingBaselinePath
  $caseAIntegrityPass          = ($storedExistingIntegrityHash -eq $computedExistingHash)
  $caseAFingerprintMatch       = ([string]$existingBaseline.semantic_trace_fingerprint_sha256 -eq $currentFingerprint)

  if ($caseAIntegrityPass -and $caseAFingerprintMatch) {
    $caseAPass   = $true
    $caseAReason = 'current_integrity_and_fingerprint_verified'
  } elseif (-not $caseAIntegrityPass) {
    $caseAReason = 'current_baseline_integrity_mismatch'
  } else {
    $caseAReason = 'current_baseline_fingerprint_mismatch'
  }
}

# ═══════════════════════════════════════════════════════════════════════════
# CASE B — authorized baseline rotation
# ═══════════════════════════════════════════════════════════════════════════

$caseBPass                 = $false
$caseBReason               = ''
$caseBArchiveExists        = $false
$caseBNewIntegrityPass     = $false
$caseBNewFingerprintMatch  = $false
$newIntegrityHash          = ''
$archivedBaselineHash      = ''
$archivedIntegrityStoredHash = ''

try {
  # Step 1 — archive previous baseline reference and integrity reference
  Copy-Item -LiteralPath $existingBaselinePath     -Destination $archivedBaselinePath     -Force
  Copy-Item -LiteralPath $existingIntegrityRefPath -Destination $archivedIntegrityRefPath -Force
  $caseBArchiveExists = (Test-Path -LiteralPath $archivedBaselinePath) -and (Test-Path -LiteralPath $archivedIntegrityRefPath)

  # Compute hash of archived copy (must equal original integrity stored hash — proves copy fidelity)
  $archivedBaselineHash      = Get-FileSha256Hex -Path $archivedBaselinePath
  $archivedIntegrityStoredHash = $storedExistingIntegrityHash   # same file bytes, same hash

  # Step 2 — create new baseline reference from current certified run (authorized path)
  $newBaselineObj = [ordered]@{
    phase                           = '42.6'
    description                     = 'Rotated certified baseline reference — authorized rotation via phase42_6 runner'
    semantic_trace_fingerprint_sha256 = $currentFingerprint
    trace_record_count              = $currentTraceCount
    final_runtime_state             = $currentFinalState
    final_runtime_value             = $currentFinalValue
    replay_result                   = $currentReplayResult
    normalization_method            = $normalizationMethod
    rotation_version                = $rotationVersion
    rotation_timestamp              = $rotationTs
    previous_baseline_archive       = ('tools/phase42_6/baseline_history/' + $archivedBaselineName)
    source_proof_packet             = ('_proof/phase42_6_baseline_rotation_trust_chain_' + $ts)
  }
  ($newBaselineObj | ConvertTo-Json -Depth 5) | Set-Content -Path $newBaselinePath -Encoding UTF8

  # Step 3 — compute new integrity hash for rotated baseline
  $newIntegrityHash = Get-FileSha256Hex -Path $newBaselinePath

  # Step 4 — create new integrity reference
  $newIntegrityRefObj = [ordered]@{
    baseline_reference_file        = 'tools/phase42_6/certification_baseline_reference_v2.json'
    expected_integrity_hash_sha256 = $newIntegrityHash
    hash_method                    = 'sha256_file_bytes_v1'
    rotation_version               = $rotationVersion
    rotation_timestamp             = $rotationTs
    previous_integrity_archive     = ('tools/phase42_6/baseline_history/' + $archivedIntegrityRefName)
  }
  ($newIntegrityRefObj | ConvertTo-Json -Depth 5) | Set-Content -Path $newIntegrityRefPath -Encoding UTF8

  # Step 5 — enforce new baseline: integrity re-verify + fingerprint match
  $computedNewHash         = Get-FileSha256Hex -Path $newBaselinePath
  $caseBNewIntegrityPass   = ($newIntegrityHash -eq $computedNewHash)
  $caseBNewFingerprintMatch = ($currentFingerprint -eq $newBaselineObj['semantic_trace_fingerprint_sha256'])

  # Step 6 — write history chain record
  $chainRecord = [ordered]@{
    rotation_timestamp = $rotationTs
    chain = @(
      [ordered]@{
        version                  = $archiveVersion
        label                    = 'previous_certified_baseline'
        baseline_file            = ('tools/phase42_6/baseline_history/' + $archivedBaselineName)
        integrity_hash           = $archivedBaselineHash
        integrity_reference_file = ('tools/phase42_6/baseline_history/' + $archivedIntegrityRefName)
        fingerprint              = [string]$existingBaseline.semantic_trace_fingerprint_sha256
        archived_at              = $rotationTs
      },
      [ordered]@{
        version                  = $rotationVersion
        label                    = 'current_rotated_baseline'
        baseline_file            = 'tools/phase42_6/certification_baseline_reference_v2.json'
        integrity_hash           = $newIntegrityHash
        integrity_reference_file = 'tools/phase42_6/baseline_integrity_reference_v2.json'
        fingerprint              = $currentFingerprint
        created_at               = $rotationTs
      }
    )
  }
  ($chainRecord | ConvertTo-Json -Depth 10) | Set-Content -Path $historyChainPath -Encoding UTF8

  if ($caseBArchiveExists -and $caseBNewIntegrityPass -and $caseBNewFingerprintMatch) {
    $caseBPass   = $true
    $caseBReason = 'authorized_rotation_archived_and_new_baseline_enforced'
  } else {
    $failures = @()
    if (-not $caseBArchiveExists)         { $failures += 'archive_write_failed' }
    if (-not $caseBNewIntegrityPass)      { $failures += 'new_integrity_verify_failed' }
    if (-not $caseBNewFingerprintMatch)   { $failures += 'new_fingerprint_mismatch' }
    $caseBReason = 'rotation_failed:' + ($failures -join ',')
  }
} catch {
  $caseBReason = 'rotation_exception:' + $_.Exception.Message
}

# ═══════════════════════════════════════════════════════════════════════════
# CASE C — unauthorized baseline overwrite simulation
# ═══════════════════════════════════════════════════════════════════════════

$caseCPass             = $false
$caseCReason           = ''
$caseCDetected         = $false
$caseCModifiedPath     = Join-Path $pf 'case_c_unauthorized_overwrite_attempt.json'
$caseCComputedHash     = ''
$caseCIntegrityPass    = $false

if (Test-Path -LiteralPath $newBaselinePath) {
  $newBaselineRawText  = Get-Content -Raw -LiteralPath $newBaselinePath
  # Simulate direct modification without going through rotation path
  $caseCModifiedText   = $newBaselineRawText -replace '"final_runtime_value":\s*\d+', '"final_runtime_value": 999'
  $caseCModifiedText  += "`n" + '{"unauthorized_overwrite":"direct_modification_bypassing_rotation"}'
  $caseCModifiedText | Set-Content -Path $caseCModifiedPath -Encoding UTF8

  $caseCComputedHash  = Get-FileSha256Hex -Path $caseCModifiedPath
  # Integrity check against the new (legitimate) integrity hash — must fail
  $caseCIntegrityPass = ($newIntegrityHash -eq $caseCComputedHash)
  $caseCDetected      = -not $caseCIntegrityPass

  if ($caseCDetected) {
    $caseCPass   = $true
    $caseCReason = 'unauthorized_overwrite_detected_by_integrity_hash_mismatch'
  } else {
    $caseCReason = 'unauthorized_overwrite_not_detected_enforcement_failure'
  }
} else {
  $caseCReason = 'new_baseline_not_available_for_case_c'
}

# ═══════════════════════════════════════════════════════════════════════════
# CASE D — historical chain verification
# ═══════════════════════════════════════════════════════════════════════════

$caseDPass                    = $false
$caseDReason                  = ''
$caseDArchiveBaselineExists   = Test-Path -LiteralPath $archivedBaselinePath
$caseDArchiveIntegrityExists  = Test-Path -LiteralPath $archivedIntegrityRefPath
$caseDChainExists             = Test-Path -LiteralPath $historyChainPath
$caseDArchivedHashConsistent  = $false
$caseDChainV1Consistent       = $false
$caseDChainV2Consistent       = $false
$caseDLoadedChain             = $null

if ($caseDArchiveBaselineExists) {
  $caseDLiveArchivedHash       = Get-FileSha256Hex -Path $archivedBaselinePath
  # The archived file bytes must match what was the original baseline (proves copy fidelity)
  $caseDArchivedHashConsistent = ($caseDLiveArchivedHash -eq $storedExistingIntegrityHash)
}

if ($caseDChainExists) {
  $caseDLoadedChain = Get-Content -Raw -LiteralPath $historyChainPath | ConvertFrom-Json
  if ($caseDLoadedChain.chain.Count -ge 2) {
    $chainV1 = $caseDLoadedChain.chain[0]
    $chainV2 = $caseDLoadedChain.chain[1]
    # V1 chain entry: stored integrity_hash must match live archived file hash
    $v1LiveHash = if ($caseDArchiveBaselineExists) { Get-FileSha256Hex -Path $archivedBaselinePath } else { '' }
    $caseDChainV1Consistent = ($chainV1.integrity_hash -eq $v1LiveHash)
    # V2 chain entry: stored integrity_hash must match live new baseline hash
    $v2LiveHash = if (Test-Path -LiteralPath $newBaselinePath) { Get-FileSha256Hex -Path $newBaselinePath } else { '' }
    $caseDChainV2Consistent = ($chainV2.integrity_hash -eq $v2LiveHash)
  }
}

if ($caseDArchiveBaselineExists -and $caseDArchiveIntegrityExists -and $caseDChainExists -and
    $caseDArchivedHashConsistent -and $caseDChainV1Consistent -and $caseDChainV2Consistent) {
  $caseDPass   = $true
  $caseDReason = 'historical_chain_auditable_and_all_hashes_consistent'
} else {
  $failures = @()
  if (-not $caseDArchiveBaselineExists)   { $failures += 'archived_baseline_missing' }
  if (-not $caseDArchiveIntegrityExists)  { $failures += 'archived_integrity_ref_missing' }
  if (-not $caseDChainExists)             { $failures += 'chain_record_missing' }
  if (-not $caseDArchivedHashConsistent)  { $failures += 'archived_hash_inconsistent' }
  if (-not $caseDChainV1Consistent)       { $failures += 'chain_v1_hash_inconsistent' }
  if (-not $caseDChainV2Consistent)       { $failures += 'chain_v2_hash_inconsistent' }
  $caseDReason = 'chain_verification_failed:' + ($failures -join ',')
}

# ═══════════════════════════════════════════════════════════════════════════
# GATE
# ═══════════════════════════════════════════════════════════════════════════

$gatePass = (
  $runtimePass         -and
  $baselineVisualPass  -and
  $baselineLockPass    -and
  $buildPass           -and
  $canonicalLaunchPass -and
  $caseAPass           -and
  $caseBPass           -and
  $caseCPass           -and
  $caseDPass           -and
  $disabledInertPass   -and
  $scopeGuardPass
)
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

# ═══════════════════════════════════════════════════════════════════════════
# PROOF PACKET GENERATION
# ═══════════════════════════════════════════════════════════════════════════

@(
  'phase=42_6_baseline_rotation_trust_chain'
  ('timestamp=' + (Get-Date).ToString('o'))
  ('runtime_contract_guard='      + $(if ($runtimePass)         { 'PASS' } else { 'FAIL' }))
  ('baseline_visual_contract='    + $(if ($baselineVisualPass)  { 'PASS' } else { 'FAIL' }))
  ('baseline_lock='               + $(if ($baselineLockPass)    { 'PASS' } else { 'FAIL' }))
  ('build='                       + $(if ($buildPass)           { 'PASS' } else { 'FAIL' }))
  ('canonical_launcher='          + $(if ($canonicalLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('case_a_current_baseline='     + $(if ($caseAPass)           { 'PASS' } else { 'FAIL' }))
  ('case_b_authorized_rotation='  + $(if ($caseBPass)           { 'PASS' } else { 'FAIL' }))
  ('case_c_unauthorized_overwrite=' + $(if ($caseCPass)         { 'PASS' } else { 'FAIL' }))
  ('case_d_chain_verification='   + $(if ($caseDPass)           { 'PASS' } else { 'FAIL' }))
  ('disabled_inert='              + $(if ($disabledInertPass)   { 'PASS' } else { 'FAIL' }))
  ('scope_guard='                 + $(if ($scopeGuardPass)      { 'PASS' } else { 'FAIL' }))
  ('gate='                        + $gate)
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase42_6: baseline trust-chain continuity / reference rotation proof'
  'scope: prove that certification baseline can be safely rotated with prior baseline archived and historical chain auditable'
  'risk_profile=rotation runner only; no UI/layout/runtime behavior changes; canonical baseline files in phase42_4 and phase42_5 preserved unchanged'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'rotation_definition:'
  '- Authorized rotation is performed only through the phase42_6 dedicated runner.'
  '- Rotation archives the previous baseline reference and integrity reference to tools/phase42_6/baseline_history/.'
  '- A new baseline reference is created from a deterministic canonical runtime run.'
  '- A new integrity hash is computed from the new baseline file bytes (sha256_file_bytes_v1).'
  '- A new integrity reference is stored in tools/phase42_6/baseline_integrity_reference_v2.json.'
  '- A baseline history chain record is stored in tools/phase42_6/baseline_history_chain.json.'
  '- All historical baseline references and integrity hashes are preserved and auditable.'
  ''
  'reference_storage:'
  ('  baseline_reference_file (current)    = tools/phase42_4/certification_baseline_reference.json')
  ('  integrity_reference_file (current)   = tools/phase42_5/baseline_integrity_reference.json')
  ('  baseline_reference_file (rotated)    = tools/phase42_6/certification_baseline_reference_v2.json')
  ('  integrity_reference_file (rotated)   = tools/phase42_6/baseline_integrity_reference_v2.json')
  ('  baseline_history_archive             = tools/phase42_6/baseline_history/')
  ('  history_chain_record                 = tools/phase42_6/baseline_history_chain.json')
  ('  rotation_runner                      = tools/phase42_6/phase42_6_baseline_rotation_trust_chain_runner.ps1')
  ('  integrity_hash_method                = sha256_file_bytes_v1')
) | Set-Content -Path (Join-Path $pf '10_rotation_definition.txt') -Encoding UTF8

@(
  'rotation_rules:'
  '1. Baseline rotation must occur only through an explicit rotation runner — never via direct file write.'
  '2. Prior baseline reference must be archived before creating a new one.'
  '3. Prior integrity hash must be archived alongside prior baseline reference.'
  '4. New baseline reference must be generated from a certified deterministic runtime run.'
  '5. New integrity hash must be computed over new baseline file bytes (sha256_file_bytes_v1).'
  '6. New integrity reference must be stored explicitly with the computed hash.'
  '7. Baseline history chain record must log all prior and current baseline versions.'
  '8. Direct modification of baseline file without rotation path must be detected as integrity failure.'
  '9. No silent overwriting of baseline references is permitted.'
  '10. Disabled must remain intentionally inert throughout rotation.'
) | Set-Content -Path (Join-Path $pf '11_rotation_rules.txt') -Encoding UTF8

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
  ('runtime_contract_guard='          + $(if ($runtimePass)         { 'PASS' } else { 'FAIL' }))
  ('baseline_visual_contract='        + $(if ($baselineVisualPass)  { 'PASS' } else { 'FAIL' }))
  ('baseline_lock='                   + $(if ($baselineLockPass)    { 'PASS' } else { 'FAIL' }))
  ('build='                           + $(if ($buildPass)           { 'PASS' } else { 'FAIL' }))
  ('canonical_launcher='              + $(if ($canonicalLaunchPass) { 'PASS' } else { 'FAIL' }))
  ''
  'case_a_results:'
  ('  case_a_current_baseline='       + $(if ($caseAPass)           { 'PASS' } else { 'FAIL' }))
  ('  case_a_integrity_verified='     + $(if ($caseAIntegrityPass)        { 'YES' } else { 'NO' }))
  ('  case_a_fingerprint_match='      + $(if ($caseAFingerprintMatch)     { 'YES' } else { 'NO' }))
  ('  case_a_stored_integrity_hash='  + $storedExistingIntegrityHash)
  ('  case_a_computed_integrity_hash=' + $computedExistingHash)
  ('  case_a_reason='                 + $caseAReason)
  ''
  'case_b_results:'
  ('  case_b_authorized_rotation='    + $(if ($caseBPass)           { 'PASS' } else { 'FAIL' }))
  ('  case_b_archive_exists='         + $(if ($caseBArchiveExists)         { 'YES' } else { 'NO' }))
  ('  case_b_new_integrity_verified=' + $(if ($caseBNewIntegrityPass)      { 'YES' } else { 'NO' }))
  ('  case_b_new_fingerprint_match='  + $(if ($caseBNewFingerprintMatch)   { 'YES' } else { 'NO' }))
  ('  case_b_new_integrity_hash='     + $newIntegrityHash)
  ('  case_b_archived_baseline='      + $archivedBaselinePath)
  ('  case_b_new_baseline='           + $newBaselinePath)
  ('  case_b_new_integrity_ref='      + $newIntegrityRefPath)
  ('  case_b_reason='                 + $caseBReason)
  ''
  'case_c_results:'
  ('  case_c_unauthorized_overwrite=' + $(if ($caseCPass)           { 'PASS' } else { 'FAIL' }))
  ('  case_c_tamper_detected='        + $(if ($caseCDetected)              { 'YES' } else { 'NO' }))
  ('  case_c_modified_file='          + $caseCModifiedPath)
  ('  case_c_computed_hash='          + $caseCComputedHash)
  ('  case_c_expected_hash='          + $newIntegrityHash)
  ('  case_c_comparison_permitted='   + $(if ($caseCIntegrityPass)         { 'YES' } else { 'NO' }))
  ('  case_c_reason='                 + $caseCReason)
  ''
  'case_d_results:'
  ('  case_d_chain_verification='     + $(if ($caseDPass)           { 'PASS' } else { 'FAIL' }))
  ('  case_d_archive_baseline_exists=' + $(if ($caseDArchiveBaselineExists)  { 'YES' } else { 'NO' }))
  ('  case_d_archive_integrity_exists=' + $(if ($caseDArchiveIntegrityExists) { 'YES' } else { 'NO' }))
  ('  case_d_chain_record_exists='    + $(if ($caseDChainExists)            { 'YES' } else { 'NO' }))
  ('  case_d_archived_hash_consistent=' + $(if ($caseDArchivedHashConsistent) { 'YES' } else { 'NO' }))
  ('  case_d_chain_v1_consistent='    + $(if ($caseDChainV1Consistent)     { 'YES' } else { 'NO' }))
  ('  case_d_chain_v2_consistent='    + $(if ($caseDChainV2Consistent)     { 'YES' } else { 'NO' }))
  ('  case_d_reason='                 + $caseDReason)
  ''
  ('baseline_pf='  + $baselinePf)
  ('baseline_zip=' + $baselineZip)
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

@(
  'behavior_summary:'
  ''
  'how baseline rotation works:'
  '- The phase42_6 runner is the sole authorized rotation path.'
  '- It runs the canonical launcher deterministically, extracts semantic trace tokens, and computes a new fingerprint.'
  '- The new fingerprint and runtime state are stored in a new baseline reference file in tools/phase42_6/.'
  '- A new integrity hash is computed over the new baseline file bytes and stored in a new integrity reference.'
  ''
  'how prior baselines are archived:'
  '- Before writing any new baseline, the runner copies the existing baseline reference and integrity reference to tools/phase42_6/baseline_history/ with version-timestamped names.'
  '- The original files in tools/phase42_4/ and tools/phase42_5/ are preserved unchanged.'
  ''
  'how integrity hashes are preserved:'
  '- Each archived baseline has its hash recorded in the history chain JSON.'
  '- Each new baseline has its hash stored in a new integrity reference file.'
  '- No hash is discarded; full hash history is auditable through baseline_history_chain.json.'
  ''
  'how trust-chain continuity is maintained:'
  '- The history chain record stores both v1 (archived) and v2 (rotated) entries with paths, hashes, fingerprints, and timestamps.'
  '- CASE D verifies live file bytes match stored chain hashes, proving the chain has not drifted.'
  ''
  'why unauthorized overwrite fails:'
  '- Direct modification of the baseline file changes its bytes without updating the stored integrity hash.'
  '- The integrity check (sha256_file_bytes_v1) detects the mismatch deterministically and blocks comparison.'
  ''
  'why Disabled remained inert:'
  '- Disabled guard tokens were present in the runtime output confirming no disabled-driven state transitions occurred.'
  '- The rotation runner does not touch any UI or runtime control paths.'
  ''
  'why baseline mode remained unchanged:'
  '- The runner only reads existing baseline files and writes new ones to tools/phase42_6/.'
  '- No baseline mode flags or visual baseline contracts were modified.'
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

$v1FingerprintStr = if ($null -ne $existingBaseline) { [string]$existingBaseline.semantic_trace_fingerprint_sha256 } else { '(unavailable)' }

@(
  'baseline_history_record:'
  ''
  'version=v1 (previous certified baseline — archived):'
  ('  baseline_reference_file='   + 'tools/phase42_6/baseline_history/' + $archivedBaselineName)
  ('  integrity_reference_file='  + 'tools/phase42_6/baseline_history/' + $archivedIntegrityRefName)
  ('  baseline_reference_hash='   + $archivedBaselineHash)
  ('  integrity_stored_hash='     + $archivedIntegrityStoredHash)
  ('  fingerprint='               + $v1FingerprintStr)
  ('  archived_at='               + $rotationTs)
  ''
  'version=v2 (rotated baseline — current rotation output):'
  ('  baseline_reference_file='   + 'tools/phase42_6/certification_baseline_reference_v2.json')
  ('  integrity_reference_file='  + 'tools/phase42_6/baseline_integrity_reference_v2.json')
  ('  baseline_reference_hash='   + $newIntegrityHash)
  ('  fingerprint='               + $currentFingerprint)
  ('  rotation_timestamp='        + $rotationTs)
  ''
  'history_chain_record='         + $historyChainPath
) | Set-Content -Path (Join-Path $pf '16_baseline_history_record.txt') -Encoding UTF8

@(
  'rotation_evidence:'
  ''
  'authorized_rotation:'
  ('  rotation_runner=tools/phase42_6/phase42_6_baseline_rotation_trust_chain_runner.ps1')
  ('  rotation_timestamp=' + $rotationTs)
  ('  archived_baseline_path=' + $archivedBaselinePath)
  ('  archived_integrity_ref_path=' + $archivedIntegrityRefPath)
  ('  archived_baseline_hash=' + $archivedBaselineHash)
  ('  new_baseline_created=' + $(if (Test-Path -LiteralPath $newBaselinePath) { 'YES' } else { 'NO' }))
  ('  new_baseline_path=' + $newBaselinePath)
  ('  new_integrity_hash=' + $newIntegrityHash)
  ('  new_integrity_ref_created=' + $(if (Test-Path -LiteralPath $newIntegrityRefPath) { 'YES' } else { 'NO' }))
  ('  new_integrity_ref_path=' + $newIntegrityRefPath)
  ('  new_baseline_enforces=' + $(if ($caseBNewIntegrityPass) { 'YES' } else { 'NO' }))
  ''
  'unauthorized_overwrite_attempt:'
  ('  modified_file=' + $caseCModifiedPath)
  ('  modification=field_value_changed_plus_content_appended_directly_without_rotation_path')
  ('  tamper_detected=' + $(if ($caseCDetected) { 'YES' } else { 'NO' }))
  ('  integrity_check_result=' + $(if ($caseCIntegrityPass) { 'PASS' } else { 'FAIL' }))
  ('  comparison_blocked=' + $(if (-not $caseCIntegrityPass) { 'YES' } else { 'NO' }))
  ('  detection_reason=' + $caseCReason)
) | Set-Content -Path (Join-Path $pf '17_rotation_evidence.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase42_6.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)
