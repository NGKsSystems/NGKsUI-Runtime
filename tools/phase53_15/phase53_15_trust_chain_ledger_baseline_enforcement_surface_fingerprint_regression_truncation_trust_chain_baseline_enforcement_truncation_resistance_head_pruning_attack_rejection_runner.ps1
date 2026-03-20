#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Phase 53.15: Trust-Chain Truncation Resistance + Head-Pruning Attack Rejection

$Phase = '53.15'
$Title = 'Trust-Chain Truncation Resistance and Head-Pruning Attack Rejection'
$PF = Join-Path $PSScriptRoot '..\..\' '_proof' "phase53_15_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_truncation_trust_chain_baseline_enforcement_truncation_resistance_head_pruning_attack_rejection_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $PF -Force | Out-Null

$script:CaseMatrix = [System.Collections.Generic.List[object]]::new()
$script:DetectionVectors = [System.Collections.Generic.List[object]]::new()
$script:TruncationThreatMap = [System.Collections.Generic.List[string]]::new()

$script:passCount = 0
$script:failCount = 0
$script:truncation_rejected_count = 0
$script:head_pruning_rejected_count = 0
$script:undetected_truncation_count = 0
$script:false_positive_count = 0

function Write-ProofFile {
    param([string]$Path, [string[]]$Content)
    Set-Content -Path $Path -Value $Content -Force
}

function Get-StringHash {
    param([string]$InputString)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($InputString)
    $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    return [System.BitConverter]::ToString($hash).Replace('-', '').ToLower()
}

function Get-CanonicalJson {
    param($Object)
    if ($null -eq $Object) { return '{}' }
    return ($Object | ConvertTo-Json -Depth 99 -Compress)
}

function Get-LedgerSnapshotHash {
    param($Ledger)
    return (Get-StringHash -InputString (Get-CanonicalJson -Object $Ledger))
}

function Copy-Deep {
    param($Object)
    return ($Object | ConvertTo-Json -Depth 99 | ConvertFrom-Json)
}

function Build-ChainSignature {
    param($Entries)
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in @($Entries)) {
        [void]$parts.Add(([string]$entry.entry_id + '|' + [string]$entry.previous_hash + '|' + [string]$entry.fingerprint_hash))
    }
    return (Get-StringHash -InputString ($parts -join ';'))
}

function Build-TrustAnchor {
    param(
        [hashtable]$Trusted,
        [int]$RotationCounter,
        [string]$AuthorizedBy,
        [string]$ProofSeed
    )

    $continuity = Get-StringHash -InputString ($Trusted.current_chain_signature + '|' + $Trusted.current_ledger_snapshot_hash)
    $anchorCore = ($Trusted.current_ledger_snapshot_hash + '|' + $Trusted.current_chain_signature + '|' + $Trusted.current_art111_head_hash_anchor + '|' + $Trusted.current_art112_head_hash_anchor + '|' + $RotationCounter)
    $anchorId = Get-StringHash -InputString $anchorCore
    $authProof = Get-StringHash -InputString ($anchorId + '|' + $AuthorizedBy + '|' + $ProofSeed)

    return @{
        anchor_id = $anchorId
        rotation_counter = $RotationCounter
        authorized_by = $AuthorizedBy
        authorization_proof = $authProof
        chain_continuity_hash = $continuity
    }
}

function Get-ValidationVectors {
    param(
        [hashtable]$State,
        [hashtable]$Trusted
    )

    $vectors = [System.Collections.Generic.List[string]]::new()
    $entries = @($State.ledger.entries)
    if ($entries.Count -eq 0) {
        [void]$vectors.Add('ledger_empty')
        return ,$vectors
    }

    $ledgerLen = $entries.Count
    $ledgerLatest = [string]$entries[$entries.Count - 1].entry_id
    $ledgerHash = Get-LedgerSnapshotHash -Ledger $State.ledger
    $chainSig = Build-ChainSignature -Entries $entries

    $a111Len = [int]$State.art111.ledger_length
    $a111Latest = [string]$State.art111.latest_entry_id
    $a111Head = [string]$State.art111.ledger_head_hash

    $a112Head = [string]$State.art112.ledger_head_hash

    $trustedLen = [int]$Trusted.current_ledger_length
    $trustedLatest = [string]$Trusted.current_latest_entry_id
    $trustedHeadHash = [string]$Trusted.current_ledger_head_hash

    # Length regression check
    if ($ledgerLen -lt $trustedLen) { [void]$vectors.Add('length_regression') }
    if ($a111Len -lt $trustedLen) { [void]$vectors.Add('length_regression') }
    
    # Head regression check (latest_entry_id changed to earlier value)
    if ([string]$ledgerLatest -ne $trustedLatest) { [void]$vectors.Add('head_regression') }
    if ([string]$a111Latest -ne $trustedLatest) { [void]$vectors.Add('head_regression') }
    
    # Cross-artifact length mismatch
    if ($a111Len -ne $ledgerLen) { [void]$vectors.Add('cross_artifact_mismatch') }
    if ($a111Latest -ne $ledgerLatest) { [void]$vectors.Add('cross_artifact_mismatch') }
    if ($a111Head -ne $a112Head) { [void]$vectors.Add('cross_artifact_mismatch') }
    
    # Ledger hash mismatch (identity break)
    if ($ledgerHash -ne $Trusted.current_ledger_snapshot_hash) { [void]$vectors.Add('lineage_break') }
    
    # Chain continuity check
    if ($chainSig -ne $Trusted.current_chain_signature) { [void]$vectors.Add('continuity_break') }
    
    return ,$vectors
}

function Invoke-GuardedCycle {
    param(
        [hashtable]$State,
        [hashtable]$Trusted,
        [scriptblock]$RuntimeMutation
    )

    $pre = Get-ValidationVectors -State $State -Trusted $Trusted
    if ($pre.Count -gt 0) {
        return @{ blocked = $true; runtime_executed = $false; stage = 'pre_runtime'; vectors = $pre; reason = ($pre -join ';') }
    }

    if ($RuntimeMutation) {
        & $RuntimeMutation -State $State -Trusted $Trusted
    }

    $boundary = Get-ValidationVectors -State $State -Trusted $Trusted
    if ($boundary.Count -gt 0) {
        return @{ blocked = $true; runtime_executed = $true; stage = 'guarded_boundary'; vectors = $boundary; reason = ($boundary -join ';') }
    }

    return @{ blocked = $false; runtime_executed = $true; stage = 'allow'; vectors = [System.Collections.Generic.List[string]]::new(); reason = 'canonical_untruncated_chain_allow' }
}

function Add-CaseResult {
    param(
        [string]$Id,
        [string]$Name,
        [string]$ExpectedResult,
        [hashtable]$CycleResult
    )

    $actual = if ($CycleResult.blocked) { 'BLOCK' } else { 'ALLOW' }
    $passFail = if ($actual -eq $ExpectedResult) { 'PASS' } else { 'FAIL' }

    if ($passFail -eq 'PASS') { $script:passCount++ } else { $script:failCount++ }

    $vectors = @($CycleResult.vectors)
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'BLOCK') { $script:truncation_rejected_count++ }
    if (($vectors -contains 'head_regression' -or $vectors -contains 'length_regression') -and $actual -eq 'BLOCK') { $script:head_pruning_rejected_count++ }
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'ALLOW') { $script:undetected_truncation_count++ }
    if ($ExpectedResult -eq 'ALLOW' -and $actual -eq 'BLOCK') { $script:false_positive_count++ }

    $stepFailed = if ($CycleResult.stage -eq 'pre_runtime') { 2 } elseif ($CycleResult.stage -eq 'guarded_boundary') { 7 } else { 0 }

    [void]$script:CaseMatrix.Add(@{
        case_id = $Id
        name = $Name
        expected_result = $ExpectedResult
        actual_result = $actual
        blocked = $CycleResult.blocked
        allowed = (-not $CycleResult.blocked)
        runtime_executed = $CycleResult.runtime_executed
        step_failed = $stepFailed
        reason = [string]$CycleResult.reason
        pass_fail = $passFail
    })

    [void]$script:DetectionVectors.Add(@{
        case_id = $Id
        stage = $CycleResult.stage
        vectors = $vectors
    })
}

$workspaceRoot = (Split-Path $PSScriptRoot -Parent) | Split-Path -Parent
$controlPlaneDir = Join-Path $workspaceRoot 'control_plane'
$ledgerPath = Join-Path $controlPlaneDir '70_guard_fingerprint_trust_chain.json'
$art111Path = Join-Path $controlPlaneDir '111_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline.json'
$art112Path = Join-Path $controlPlaneDir '112_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_integrity.json'

if (-not (Test-Path $ledgerPath)) { throw "Missing ledger: $ledgerPath" }
if (-not (Test-Path $art111Path)) { throw "Missing art111: $art111Path" }
if (-not (Test-Path $art112Path)) { throw "Missing art112: $art112Path" }

$baselineLedger = Get-Content $ledgerPath -Raw | ConvertFrom-Json
$baselineArt111 = Get-Content $art111Path -Raw | ConvertFrom-Json
$baselineArt112 = Get-Content $art112Path -Raw | ConvertFrom-Json

$entries = @($baselineLedger.entries)
$trustedLen = $entries.Count
$trustedLatestEntry = $entries[$entries.Count - 1]
$trustedLatestId = [string]$trustedLatestEntry.entry_id
$trustedHeadHash = Get-LedgerSnapshotHash -Ledger $baselineLedger
$trustedChainSig = Build-ChainSignature -Entries $entries

$trusted = @{
    current_ledger_length = $trustedLen
    current_latest_entry_id = $trustedLatestId
    current_ledger_head_hash = $trustedHeadHash
    current_ledger_snapshot_hash = Get-LedgerSnapshotHash -Ledger $baselineLedger
    current_chain_signature = Build-ChainSignature -Entries $entries
    current_art111_head_hash_anchor = [string]$baselineArt111.ledger_head_hash
    current_art112_head_hash_anchor = [string]$baselineArt112.ledger_head_hash
    current_art111_phase_locked = [string]$baselineArt111.phase_locked
    current_art112_phase_locked = [string]$baselineArt112.phase_locked
    current_art112_source_artifact = [string]$baselineArt112.source_artifact
}

$trusted.anchor = Build-TrustAnchor -Trusted $trusted -RotationCounter 0 -AuthorizedBy 'CANONICAL_CHAIN' -ProofSeed 'ROOT_AUTH'

function New-LiveState {
    return @{
        ledger = Copy-Deep -Object $baselineLedger
        art111 = Copy-Deep -Object $baselineArt111
        art112 = Copy-Deep -Object $baselineArt112
        anchor = Copy-Deep -Object $trusted.anchor
    }
}

# Setup truncation test states

# A) Tail truncation block - remove most recent entry
$stateTailTruncation = New-LiveState
$tailTruncatedEntries = @($stateTailTruncation.ledger.entries[0..($stateTailTruncation.ledger.entries.Count - 2)])
$stateTailTruncation.ledger.entries = $tailTruncatedEntries
$stateTailTruncation.art111.ledger_length = $tailTruncatedEntries.Count
$stateTailTruncation.art111.latest_entry_id = $tailTruncatedEntries[-1].entry_id
$resultA = Invoke-GuardedCycle -State $stateTailTruncation -Trusted $trusted
Add-CaseResult -Id 'A' -Name 'tail_truncation_block' -ExpectedResult 'BLOCK' -CycleResult $resultA

# B) Head-pruning / length regression
$stateHeadPruning = New-LiveState
$pruned = @($stateHeadPruning.ledger.entries[0..($stateHeadPruning.ledger.entries.Count - 3)])
$stateHeadPruning.ledger.entries = $pruned
$stateHeadPruning.art111.ledger_length = $pruned.Count
$stateHeadPruning.art111.latest_entry_id = [string]$pruned[-1].entry_id
$resultB = Invoke-GuardedCycle -State $stateHeadPruning -Trusted $trusted
Add-CaseResult -Id 'B' -Name 'head_pruning_length_regression' -ExpectedResult 'BLOCK' -CycleResult $resultB

# C) Self-consistent shortened state - truncate and recompute metadata so it's internally consistent but doesn't match trusted
$stateSelfConsistent = New-LiveState
$shortened = @($stateSelfConsistent.ledger.entries[0..($stateSelfConsistent.ledger.entries.Count - 2)])
$stateSelfConsistent.ledger.entries = $shortened
$stateSelfConsistent.art111.ledger_length = $shortened.Count
$stateSelfConsistent.art111.latest_entry_id = [string]$shortened[-1].entry_id
$newHeadHash = Get-LedgerSnapshotHash -Ledger $stateSelfConsistent.ledger
$stateSelfConsistent.art111.ledger_head_hash = $newHeadHash
$stateSelfConsistent.art112.ledger_head_hash = $newHeadHash
# Self-consistency alone must NOT pass - we detect because length is less than trusted
$resultC = Invoke-GuardedCycle -State $stateSelfConsistent -Trusted $trusted
Add-CaseResult -Id 'C' -Name 'self_consistent_shortened_state' -ExpectedResult 'BLOCK' -CycleResult $resultC

# D) Partial truncation mismatch - truncate ledger but not art111/art112
$statePartialMismatch = New-LiveState
$partialTrunc = @($statePartialMismatch.ledger.entries[0..($statePartialMismatch.ledger.entries.Count - 2)])
$statePartialMismatch.ledger.entries = $partialTrunc
# art111/art112 still have old length, creating cross-artifact mismatch
$resultD = Invoke-GuardedCycle -State $statePartialMismatch -Trusted $trusted
Add-CaseResult -Id 'D' -Name 'partial_truncation_mismatch' -ExpectedResult 'BLOCK' -CycleResult $resultD

# E) Middle-segment drop - remove entries from interior (not head/tail)
$stateMiddleDrop = New-LiveState
if ($stateMiddleDrop.ledger.entries.Count -gt 4) {
    $before = @($stateMiddleDrop.ledger.entries[0..1])
    $after = @($stateMiddleDrop.ledger.entries[($stateMiddleDrop.ledger.entries.Count - 2)..($stateMiddleDrop.ledger.entries.Count - 1)])
    $stateMiddleDrop.ledger.entries = $before + $after
    $stateMiddleDrop.art111.ledger_length = $before.Count + $after.Count
    $stateMiddleDrop.art111.latest_entry_id = [string]$after[-1].entry_id
}
$resultE = Invoke-GuardedCycle -State $stateMiddleDrop -Trusted $trusted
Add-CaseResult -Id 'E' -Name 'middle_segment_drop' -ExpectedResult 'BLOCK' -CycleResult $resultE

# F) Guarded-boundary truncation swap (pre-runtime phase)
$stateGuardedPre = New-LiveState
$truncForF = @($stateGuardedPre.ledger.entries[0..($stateGuardedPre.ledger.entries.Count - 2)])
$stateGuardedPre.ledger.entries = $truncForF
$stateGuardedPre.art111.ledger_length = $truncForF.Count
$stateGuardedPre.art111.latest_entry_id = [string]$truncForF[-1].entry_id
$resultF = Invoke-GuardedCycle -State $stateGuardedPre -Trusted $trusted
Add-CaseResult -Id 'F' -Name 'guarded_boundary_truncation_pre_runtime' -ExpectedResult 'BLOCK' -CycleResult $resultF

# G) Guarded-boundary truncation swap (runtime mutation)
$stateGuardedRuntime = New-LiveState
$resultG = Invoke-GuardedCycle -State $stateGuardedRuntime -Trusted $trusted -RuntimeMutation {
    param([hashtable]$State, [hashtable]$Trusted)
    $truncForRuntime = @($State.ledger.entries[0..($State.ledger.entries.Count - 2)])
    $State.ledger.entries = $truncForRuntime
    $State.art111.ledger_length = $truncForRuntime.Count
    $State.art111.latest_entry_id = [string]$truncForRuntime[-1].entry_id
}
Add-CaseResult -Id 'G' -Name 'guarded_boundary_truncation_runtime' -ExpectedResult 'BLOCK' -CycleResult $resultG

# H) Clean control - untruncated canonical chain
$stateClean = New-LiveState
$resultH = Invoke-GuardedCycle -State $stateClean -Trusted $trusted
Add-CaseResult -Id 'H' -Name 'clean_control_untruncated' -ExpectedResult 'ALLOW' -CycleResult $resultH

$consistencyPass = $true
if ($script:CaseMatrix.Count -ne 8) { $consistencyPass = $false }
if (($script:passCount + $script:failCount) -ne 8) { $consistencyPass = $false }
if ($script:undetected_truncation_count -ne 0) { $consistencyPass = $false }
if ($script:false_positive_count -ne 0) { $consistencyPass = $false }

$gate = if ($script:passCount -eq 8 -and $script:failCount -eq 0 -and $consistencyPass) { 'PASS' } else { 'FAIL' }

$matrixLines = @('case|expected_result|actual_result|blocked|allowed|runtime_executed|step_failed|reason|pass_fail')
foreach ($row in $script:CaseMatrix) {
    $matrixLines += ($row.case_id + '|' + $row.expected_result + '|' + $row.actual_result + '|' + $row.blocked + '|' + $row.allowed + '|' + $row.runtime_executed + '|' + $row.step_failed + '|' + $row.reason + '|' + $row.pass_fail)
}

$vectorLines = @('case|stage|vectors')
foreach ($v in $script:DetectionVectors) {
    $joined = if ($v.vectors.Count -gt 0) { ($v.vectors -join ';') } else { 'none' }
    $vectorLines += ($v.case_id + '|' + $v.stage + '|' + $joined)
}

$testMatrix = @(
    'TRUNCATION_ATTACK_MATRIX',
    'A: tail_truncation_block => expect BLOCK',
    'B: head_pruning_length_regression => expect BLOCK',
    'C: self_consistent_shortened_state => expect BLOCK',
    'D: partial_truncation_mismatch => expect BLOCK',
    'E: middle_segment_drop => expect BLOCK',
    'F: guarded_boundary_truncation_pre_runtime => expect BLOCK',
    'G: guarded_boundary_truncation_runtime => expect BLOCK',
    'H: clean_control_untruncated => expect ALLOW'
)

$regressionMap = @(
    'TRUSTED_CHAIN_LENGTH=' + $trusted.current_ledger_length,
    'TRUSTED_LATEST_ENTRY_ID=' + $trusted.current_latest_entry_id,
    'TRUSTED_LEDGER_HEAD_HASH=' + $trusted.current_ledger_head_hash,
    'DETECTION_VECTOR_HEAD_REGRESSION=head_regression_detection_enabled',
    'DETECTION_VECTOR_LENGTH_REGRESSION=length_regression_detection_enabled',
    'DETECTION_VECTOR_LINEAGE_BREAK=lineage_break_detection_enabled',
    'DETECTION_VECTOR_CONTINUITY_BREAK=continuity_break_detection_enabled',
    'DETECTION_VECTOR_CROSS_ARTIFACT_MISMATCH=cross_artifact_mismatch_detection_enabled'
)

Write-ProofFile -Path (Join-Path $PF '01_status.txt') -Content @(
    'PHASE=53.15',
    'TITLE=' + $Title,
    'GATE=' + $gate,
    'PASS_COUNT=' + $script:passCount + '/8',
    'FAIL_COUNT=' + $script:failCount,
    'truncation_rejected_count=' + $script:truncation_rejected_count,
    'head_pruning_rejected_count=' + $script:head_pruning_rejected_count,
    'undetected_truncation_count=' + $script:undetected_truncation_count,
    'false_positive_count=' + $script:false_positive_count,
    'consistency_check=' + $(if ($consistencyPass) { 'PASS' } else { 'FAIL' }),
    'FAIL_CLOSED=TRUE',
    'NO_FALLBACK=TRUE',
    'NO_SILENT_ACCEPTANCE=TRUE'
)

Write-ProofFile -Path (Join-Path $PF '14_validation_results.txt') -Content $matrixLines
Write-ProofFile -Path (Join-Path $PF '15_truncation_attack_matrix.txt') -Content $testMatrix
Write-ProofFile -Path (Join-Path $PF '15_chain_length_head_regression_map.txt') -Content $regressionMap
Write-ProofFile -Path (Join-Path $PF '15_detection_vectors.txt') -Content $vectorLines

Write-ProofFile -Path (Join-Path $PF '98_gate_phase53_15.txt') -Content @(
    'GATE=' + $gate,
    'PASS_COUNT=' + $script:passCount + '/8',
    'FAIL_COUNT=' + $script:failCount,
    'truncation_rejected_count=' + $script:truncation_rejected_count,
    'head_pruning_rejected_count=' + $script:head_pruning_rejected_count,
    'undetected_truncation_count=' + $script:undetected_truncation_count,
    'false_positive_count=' + $script:false_positive_count
)

$zipPath = $PF + '.zip'
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path $PF -DestinationPath $zipPath -Force

Write-Output ('PF=' + $PF)
Write-Output ('ZIP=' + $zipPath)
Write-Output ('GATE=' + $gate)
