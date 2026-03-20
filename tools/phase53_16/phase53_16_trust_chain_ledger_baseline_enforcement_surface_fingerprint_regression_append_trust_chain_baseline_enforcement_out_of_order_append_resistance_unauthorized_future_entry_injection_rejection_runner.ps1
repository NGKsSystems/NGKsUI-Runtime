#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Phase 53.16: Out-of-Order Append Resistance + Unauthorized Future-Entry Injection Rejection

$Phase = '53.16'
$Title = 'Out-of-Order Append Resistance and Unauthorized Future-Entry Injection Rejection'
$PF = Join-Path $PSScriptRoot '..\..\' '_proof' "phase53_16_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_append_trust_chain_baseline_enforcement_out_of_order_append_resistance_unauthorized_future_entry_injection_rejection_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $PF -Force | Out-Null

$script:CaseMatrix = [System.Collections.Generic.List[object]]::new()
$script:DetectionVectors = [System.Collections.Generic.List[object]]::new()
$script:AppendThreatMap = [System.Collections.Generic.List[string]]::new()

$script:passCount = 0
$script:failCount = 0
$script:unauthorized_append_rejected_count = 0
$script:future_entry_injection_rejected_count = 0
$script:undetected_append_count = 0
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

function New-ForgedEntry {
    param(
        [int]$EntryId,
        [string]$PreviousHash,
        [string]$ForgeSeed
    )
    
    return @{
        entry_id = 'GF-' + [string]$EntryId
        previous_hash = $PreviousHash
        fingerprint_hash = Get-StringHash -InputString ('FORGED_ENTRY_' + $EntryId + '|' + $ForgeSeed)
        timestamp = $(Get-Date -Format 'o')
        unauthorized_append = $true
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
    $trustedLen = [int]$Trusted.current_ledger_length
    
    # Length expansion check
    if ($ledgerLen -gt $trustedLen) { [void]$vectors.Add('length_expansion') }
    
    # Extract canonical portion (up to trusted length)
    $canonicalPortion = @($entries[0..($trustedLen - 1)])
    $appendedPortion = if ($ledgerLen -gt $trustedLen) { @($entries[$trustedLen..($entries.Count - 1)]) } else { @() }
    
    # Verify canonical portion hasn't changed
    $canonicalHash = Get-LedgerSnapshotHash -Ledger @{ entries = $canonicalPortion }
    if ($canonicalHash -ne $Trusted.current_ledger_snapshot_hash) {
        [void]$vectors.Add('canonical_portion_tampered')
    }
    
    # Check for unauthorized appends
    $appendCount = @($appendedPortion).Count
    if ($appendCount -gt 0) {
        [void]$vectors.Add('unauthorized_append')
        [void]$vectors.Add('future_entry_injection')
    }
    
    # Check ID ordering and gaps
    for ($i = 0; $i -lt $entries.Count; $i++) {
        # Only check ordering violations in the appended portion
        if ($i -ge $trustedLen) {
            # For appended entries, check if they're in strict ID order
            if ($i -gt $trustedLen) {
                $prevId = [string]$entries[$i - 1].entry_id
                $currId = [string]$entries[$i].entry_id
                $prevNum = [int]($prevId -replace 'GF-', '')
                $currNum = [int]($currId -replace 'GF-', '')
                if ($currNum -lt $prevNum) {
                    [void]$vectors.Add('out_of_order_append')
                }
                if ($currNum -ne $prevNum + 1) {
                    [void]$vectors.Add('skipped_id_gap')
                }
            }
        }
    }
    
    # Cross-artifact checks
    $a111Len = [int]$State.art111.ledger_length
    $a111Latest = [string]$State.art111.latest_entry_id
    $a111Head = [string]$State.art111.ledger_head_hash

    $a112Head = [string]$State.art112.ledger_head_hash

    if ($a111Len -ne $ledgerLen) { [void]$vectors.Add('cross_artifact_mismatch') }
    if ($a111Latest -ne ([string]$entries[-1].entry_id)) { [void]$vectors.Add('cross_artifact_mismatch') }
    if ($a111Head -ne $a112Head) { [void]$vectors.Add('cross_artifact_mismatch') }
    
    # Full chain signature check (should break with any append)
    $chainSig = Build-ChainSignature -Entries $entries
    if ($chainSig -ne $Trusted.current_chain_signature) { [void]$vectors.Add('continuity_break') }
    
    # Ledger hash mismatch (identity break)
    $fullHash = Get-LedgerSnapshotHash -Ledger $State.ledger
    if ($fullHash -ne $Trusted.current_ledger_snapshot_hash) { [void]$vectors.Add('lineage_break') }
    
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

    return @{ blocked = $false; runtime_executed = $true; stage = 'allow'; vectors = [System.Collections.Generic.List[string]]::new(); reason = 'canonical_chain_no_unauthorized_append_allow' }
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
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'BLOCK') { $script:unauthorized_append_rejected_count++ }
    if (($vectors -contains 'unauthorized_append' -or $vectors -contains 'future_entry_injection') -and $actual -eq 'BLOCK') { $script:future_entry_injection_rejected_count++ }
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'ALLOW') { $script:undetected_append_count++ }
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

# A) Unauthorized future append block
$stateUnauthorizedAppend = New-LiveState
$forgedEntry1 = New-ForgedEntry -EntryId ($trustedLen + 1) -PreviousHash $trustedLatestEntry.fingerprint_hash -ForgeSeed 'UNAUTHORIZED_APPEND_SEED'
$stateUnauthorizedAppend.ledger.entries += $forgedEntry1
$stateUnauthorizedAppend.art111.ledger_length = $trustedLen + 1
$stateUnauthorizedAppend.art111.latest_entry_id = $forgedEntry1.entry_id
$stateUnauthorizedAppend.art111.ledger_head_hash = Get-LedgerSnapshotHash -Ledger $stateUnauthorizedAppend.ledger
$resultA = Invoke-GuardedCycle -State $stateUnauthorizedAppend -Trusted $trusted
Add-CaseResult -Id 'A' -Name 'unauthorized_future_append_block' -ExpectedResult 'BLOCK' -CycleResult $resultA

# B) Out-of-order append
$stateOutOfOrder = New-LiveState
$forgedOutOfOrderEntry = New-ForgedEntry -EntryId ($trustedLen + 2) -PreviousHash $trustedLatestEntry.fingerprint_hash -ForgeSeed 'OUT_OF_ORDER'
$stateOutOfOrder.ledger.entries += $forgedOutOfOrderEntry
$forgedEarlyEntry = New-ForgedEntry -EntryId ($trustedLen + 1) -PreviousHash $trustedLatestEntry.fingerprint_hash -ForgeSeed 'EARLY_ENTRY'
$stateOutOfOrder.ledger.entries += $forgedEarlyEntry
$stateOutOfOrder.art111.ledger_length = $trustedLen + 2
$stateOutOfOrder.art111.latest_entry_id = $forgedEarlyEntry.entry_id
$resultB = Invoke-GuardedCycle -State $stateOutOfOrder -Trusted $trusted
Add-CaseResult -Id 'B' -Name 'out_of_order_append' -ExpectedResult 'BLOCK' -CycleResult $resultB

# C) Skipped-ID append (gap creation)
$stateSkippedId = New-LiveState
$forgedGappyEntry = New-ForgedEntry -EntryId ($trustedLen + 3) -PreviousHash $trustedLatestEntry.fingerprint_hash -ForgeSeed 'SKIPPED_ID'
$stateSkippedId.ledger.entries += $forgedGappyEntry
$stateSkippedId.art111.ledger_length = $trustedLen + 1
$stateSkippedId.art111.latest_entry_id = $forgedGappyEntry.entry_id
$resultC = Invoke-GuardedCycle -State $stateSkippedId -Trusted $trusted
Add-CaseResult -Id 'C' -Name 'skipped_id_append_gap' -ExpectedResult 'BLOCK' -CycleResult $resultC

# D) Self-consistent future state (append and recompute metadata)
$stateSelfConsistentAppend = New-LiveState
$forgedAppendEntry = New-ForgedEntry -EntryId ($trustedLen + 1) -PreviousHash $trustedLatestEntry.fingerprint_hash -ForgeSeed 'SELF_CONSISTENT'
$stateSelfConsistentAppend.ledger.entries += $forgedAppendEntry
$newLen = $stateSelfConsistentAppend.ledger.entries.Count
$newLatestId = $forgedAppendEntry.entry_id
$newHeadHash = Get-LedgerSnapshotHash -Ledger $stateSelfConsistentAppend.ledger
$stateSelfConsistentAppend.art111.ledger_length = $newLen
$stateSelfConsistentAppend.art111.latest_entry_id = $newLatestId
$stateSelfConsistentAppend.art111.ledger_head_hash = $newHeadHash
$stateSelfConsistentAppend.art112.ledger_head_hash = $newHeadHash
# Self-consistency alone must NOT pass - we detect because full chain sig broke
$resultD = Invoke-GuardedCycle -State $stateSelfConsistentAppend -Trusted $trusted
Add-CaseResult -Id 'D' -Name 'self_consistent_future_state' -ExpectedResult 'BLOCK' -CycleResult $resultD

# E) Partial future injection (cross-artifact mismatch)
$statePartialAppend = New-LiveState
$forgedPartialEntry = New-ForgedEntry -EntryId ($trustedLen + 1) -PreviousHash $trustedLatestEntry.fingerprint_hash -ForgeSeed 'PARTIAL_INJECT'
$statePartialAppend.ledger.entries += $forgedPartialEntry
# Don't update art111/art112, creating cross-artifact mismatch
$resultE = Invoke-GuardedCycle -State $statePartialAppend -Trusted $trusted
Add-CaseResult -Id 'E' -Name 'partial_future_injection_mismatch' -ExpectedResult 'BLOCK' -CycleResult $resultE

# F) Middle insert / non-tail append
$stateMiddleInsert = New-LiveState
$insertMidEntry = New-ForgedEntry -EntryId 999 -PreviousHash 'FORGED_LINK' -ForgeSeed 'MIDDLE_INSERT'
# Insert in the middle (between position 5 and 6)
$before = @($stateMiddleInsert.ledger.entries[0..4])
$after = @($stateMiddleInsert.ledger.entries[5..($stateMiddleInsert.ledger.entries.Count - 1)])
$stateMiddleInsert.ledger.entries = $before + @($insertMidEntry) + $after
$stateMiddleInsert.art111.ledger_length = $stateMiddleInsert.ledger.entries.Count
$stateMiddleInsert.art111.latest_entry_id = [string]$stateMiddleInsert.ledger.entries[-1].entry_id
$resultF = Invoke-GuardedCycle -State $stateMiddleInsert -Trusted $trusted
Add-CaseResult -Id 'F' -Name 'middle_insert_non_tail_append' -ExpectedResult 'BLOCK' -CycleResult $resultF

# G) Guarded-boundary future swap (runtime mutation)
$stateGuardedFuture = New-LiveState
$resultG = Invoke-GuardedCycle -State $stateGuardedFuture -Trusted $trusted -RuntimeMutation {
    param([hashtable]$State, [hashtable]$Trusted)
    $forgedRuntimeEntry = New-ForgedEntry -EntryId ($Trusted.current_ledger_length + 1) -PreviousHash ([string]$State.ledger.entries[-1].fingerprint_hash) -ForgeSeed 'RUNTIME_FUTURE'
    $State.ledger.entries += $forgedRuntimeEntry
    $State.art111.ledger_length += 1
    $State.art111.latest_entry_id = $forgedRuntimeEntry.entry_id
}
Add-CaseResult -Id 'G' -Name 'guarded_boundary_future_swap' -ExpectedResult 'BLOCK' -CycleResult $resultG

# H) Clean control - no unauthorized append
$stateClean = New-LiveState
$resultH = Invoke-GuardedCycle -State $stateClean -Trusted $trusted
Add-CaseResult -Id 'H' -Name 'clean_control_canonical_chain' -ExpectedResult 'ALLOW' -CycleResult $resultH

$consistencyPass = $true
if ($script:CaseMatrix.Count -ne 8) { $consistencyPass = $false }
if (($script:passCount + $script:failCount) -ne 8) { $consistencyPass = $false }
if ($script:undetected_append_count -ne 0) { $consistencyPass = $false }
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
    'APPEND_ATTACK_MATRIX',
    'A: unauthorized_future_append_block => expect BLOCK',
    'B: out_of_order_append => expect BLOCK',
    'C: skipped_id_append_gap => expect BLOCK',
    'D: self_consistent_future_state => expect BLOCK',
    'E: partial_future_injection_mismatch => expect BLOCK',
    'F: middle_insert_non_tail_append => expect BLOCK',
    'G: guarded_boundary_future_swap => expect BLOCK',
    'H: clean_control_canonical_chain => expect ALLOW'
)

$orderingMap = @(
    'TRUSTED_CHAIN_LENGTH=' + $trusted.current_ledger_length,
    'TRUSTED_LATEST_ENTRY_ID=' + $trusted.current_latest_entry_id,
    'TRUSTED_LEDGER_HEAD_HASH=' + $trusted.current_ledger_head_hash,
    'ID_PROGRESSION_PATTERN=GF-001..GF-NNN_monotonic',
    'DETECTION_VECTOR_UNAUTHORIZED_APPEND=enabled',
    'DETECTION_VECTOR_FUTURE_ENTRY_INJECTION=enabled',
    'DETECTION_VECTOR_OUT_OF_ORDER_APPEND=enabled',
    'DETECTION_VECTOR_SKIPPED_ID_GAP=enabled',
    'DETECTION_VECTOR_LINEAGE_BREAK=enabled',
    'DETECTION_VECTOR_CONTINUITY_BREAK=enabled',
    'DETECTION_VECTOR_CROSS_ARTIFACT_MISMATCH=enabled'
)

Write-ProofFile -Path (Join-Path $PF '01_status.txt') -Content @(
    'PHASE=53.16',
    'TITLE=' + $Title,
    'GATE=' + $gate,
    'PASS_COUNT=' + $script:passCount + '/8',
    'FAIL_COUNT=' + $script:failCount,
    'unauthorized_append_rejected_count=' + $script:unauthorized_append_rejected_count,
    'future_entry_injection_rejected_count=' + $script:future_entry_injection_rejected_count,
    'undetected_append_count=' + $script:undetected_append_count,
    'false_positive_count=' + $script:false_positive_count,
    'consistency_check=' + $(if ($consistencyPass) { 'PASS' } else { 'FAIL' }),
    'FAIL_CLOSED=TRUE',
    'NO_FALLBACK=TRUE',
    'NO_SILENT_ACCEPTANCE=TRUE'
)

Write-ProofFile -Path (Join-Path $PF '14_validation_results.txt') -Content $matrixLines
Write-ProofFile -Path (Join-Path $PF '15_append_attack_matrix.txt') -Content $testMatrix
Write-ProofFile -Path (Join-Path $PF '15_ordering_id_progression_map.txt') -Content $orderingMap
Write-ProofFile -Path (Join-Path $PF '15_detection_vectors.txt') -Content $vectorLines

Write-ProofFile -Path (Join-Path $PF '98_gate_phase53_16.txt') -Content @(
    'GATE=' + $gate,
    'PASS_COUNT=' + $script:passCount + '/8',
    'FAIL_COUNT=' + $script:failCount,
    'unauthorized_append_rejected_count=' + $script:unauthorized_append_rejected_count,
    'future_entry_injection_rejected_count=' + $script:future_entry_injection_rejected_count,
    'undetected_append_count=' + $script:undetected_append_count,
    'false_positive_count=' + $script:false_positive_count
)

$zipPath = $PF + '.zip'
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path $PF -DestinationPath $zipPath -Force

Write-Output ('PF=' + $PF)
Write-Output ('ZIP=' + $zipPath)
Write-Output ('GATE=' + $gate)
