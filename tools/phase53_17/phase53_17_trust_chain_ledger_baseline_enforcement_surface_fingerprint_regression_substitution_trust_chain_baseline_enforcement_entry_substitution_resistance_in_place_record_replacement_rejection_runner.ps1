#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Phase 53.17: Entry Substitution Resistance + In-Place Record Replacement Rejection

$Phase = '53.17'
$Title = 'Entry Substitution Resistance and In-Place Record Replacement Rejection'
$PF = Join-Path $PSScriptRoot '..\..\' '_proof' "phase53_17_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_substitution_trust_chain_baseline_enforcement_entry_substitution_resistance_in_place_record_replacement_rejection_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $PF -Force | Out-Null

$script:CaseMatrix = [System.Collections.Generic.List[object]]::new()
$script:DetectionVectors = [System.Collections.Generic.List[object]]::new()
$script:SlotIntegrityMap = [System.Collections.Generic.List[string]]::new()

$script:passCount = 0
$script:failCount = 0
$script:substitution_rejected_count = 0
$script:in_place_replacement_rejected_count = 0
$script:undetected_substitution_count = 0
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

function Get-EntrySignature {
    param($Entry)
    return (Get-StringHash -InputString (Get-CanonicalJson -Object $Entry))
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

function New-ForgedSubstitute {
    param(
        [string]$EntryId,
        [string]$PreviousHash,
        [string]$Seed
    )

    return @{
        entry_id = $EntryId
        previous_hash = $PreviousHash
        fingerprint_hash = Get-StringHash -InputString ('FORGED_SUBSTITUTE|' + $EntryId + '|' + $Seed)
        timestamp = (Get-Date -Format 'o')
        substituted = $true
    }
}

function Reseal-Downstream {
    param(
        [array]$Entries,
        [int]$StartIndex,
        [string]$Seed
    )

    for ($i = $StartIndex; $i -lt $Entries.Count; $i++) {
        if ($i -gt 0) {
            $Entries[$i].previous_hash = [string]$Entries[$i - 1].fingerprint_hash
        }
        $entryId = [string]$Entries[$i].entry_id
        $Entries[$i].fingerprint_hash = Get-StringHash -InputString ('RESEALED|' + $entryId + '|' + $i + '|' + $Seed)
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

    if ($ledgerLen -ne $trustedLen) {
        [void]$vectors.Add('length_mismatch')
    }

    $scanLen = [Math]::Min($ledgerLen, $trustedLen)
    for ($i = 0; $i -lt $scanLen; $i++) {
        $curr = $entries[$i]
        $currId = [string]$curr.entry_id
        $trustedId = [string]$Trusted.entry_ids[$i]
        $currSig = Get-EntrySignature -Entry $curr
        $trustedSig = [string]$Trusted.entry_signatures[$i]

        if ($currSig -ne $trustedSig) {
            [void]$vectors.Add('entry_identity_mismatch')
            [void]$vectors.Add('in_place_replacement')

            if ($currId -eq $trustedId) {
                [void]$vectors.Add('same_id_different_content')
            }
            else {
                [void]$vectors.Add('slot_rewrite')
            }

            if ($i -eq ($trustedLen - 1)) {
                [void]$vectors.Add('tail_entry_substitution')
            }
            else {
                [void]$vectors.Add('mid_chain_substitution')
            }
        }
    }

    $a111Len = [int]$State.art111.ledger_length
    $a111Latest = [string]$State.art111.latest_entry_id
    $a111Head = [string]$State.art111.ledger_head_hash
    $a112Head = [string]$State.art112.ledger_head_hash
    $ledgerLatest = [string]$entries[-1].entry_id

    if ($a111Len -ne $ledgerLen) { [void]$vectors.Add('cross_artifact_mismatch') }
    if ($a111Latest -ne $ledgerLatest) { [void]$vectors.Add('cross_artifact_mismatch') }
    if ($a111Head -ne $a112Head) { [void]$vectors.Add('cross_artifact_mismatch') }

    $chainSig = Build-ChainSignature -Entries $entries
    if ($chainSig -ne $Trusted.current_chain_signature) {
        [void]$vectors.Add('continuity_break')
        [void]$vectors.Add('lineage_break')
    }

    $ledgerHash = Get-LedgerSnapshotHash -Ledger $State.ledger
    if ($ledgerHash -ne $Trusted.current_ledger_snapshot_hash) { [void]$vectors.Add('identity_failure') }

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

    return @{ blocked = $false; runtime_executed = $true; stage = 'allow'; vectors = [System.Collections.Generic.List[string]]::new(); reason = 'canonical_chain_allow' }
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
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'BLOCK') { $script:substitution_rejected_count++ }
    if (($vectors -contains 'in_place_replacement') -and $actual -eq 'BLOCK') { $script:in_place_replacement_rejected_count++ }
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'ALLOW') { $script:undetected_substitution_count++ }
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
$trustedLatestId = [string]$entries[-1].entry_id
$trustedHeadHash = Get-LedgerSnapshotHash -Ledger $baselineLedger

$trustedEntryIds = [System.Collections.Generic.List[string]]::new()
$trustedEntrySigs = [System.Collections.Generic.List[string]]::new()
for ($i = 0; $i -lt $entries.Count; $i++) {
    [void]$trustedEntryIds.Add([string]$entries[$i].entry_id)
    [void]$trustedEntrySigs.Add((Get-EntrySignature -Entry $entries[$i]))
}

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
    entry_ids = $trustedEntryIds.ToArray()
    entry_signatures = $trustedEntrySigs.ToArray()
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

[void]$script:SlotIntegrityMap.Add('TRUSTED_CHAIN_LENGTH=' + $trusted.current_ledger_length)
[void]$script:SlotIntegrityMap.Add('TRUSTED_LATEST_ENTRY_ID=' + $trusted.current_latest_entry_id)
[void]$script:SlotIntegrityMap.Add('TRUSTED_LEDGER_HEAD_HASH=' + $trusted.current_ledger_head_hash)
[void]$script:SlotIntegrityMap.Add('SLOT_0001_ENTRY_ID=' + [string]$trusted.entry_ids[0])
[void]$script:SlotIntegrityMap.Add('SLOT_0001_SIGNATURE=' + [string]$trusted.entry_signatures[0])
[void]$script:SlotIntegrityMap.Add('SLOT_LAST_ENTRY_ID=' + [string]$trusted.entry_ids[$trustedLen - 1])
[void]$script:SlotIntegrityMap.Add('SLOT_LAST_SIGNATURE=' + [string]$trusted.entry_signatures[$trustedLen - 1])
[void]$script:SlotIntegrityMap.Add('DETECTION_VECTOR_TAIL_ENTRY_SUBSTITUTION=enabled')
[void]$script:SlotIntegrityMap.Add('DETECTION_VECTOR_MID_CHAIN_SUBSTITUTION=enabled')
[void]$script:SlotIntegrityMap.Add('DETECTION_VECTOR_SAME_ID_DIFFERENT_CONTENT=enabled')
[void]$script:SlotIntegrityMap.Add('DETECTION_VECTOR_IN_PLACE_REPLACEMENT=enabled')
[void]$script:SlotIntegrityMap.Add('DETECTION_VECTOR_CONTINUITY_BREAK=enabled')
[void]$script:SlotIntegrityMap.Add('DETECTION_VECTOR_CROSS_ARTIFACT_MISMATCH=enabled')

# A) Tail entry substitution block
$stateA = New-LiveState
$tailIndex = $stateA.ledger.entries.Count - 1
$origTail = $stateA.ledger.entries[$tailIndex]
$stateA.ledger.entries[$tailIndex] = New-ForgedSubstitute -EntryId ([string]$origTail.entry_id) -PreviousHash ([string]$origTail.previous_hash) -Seed 'TAIL_SUB'
$resultA = Invoke-GuardedCycle -State $stateA -Trusted $trusted
Add-CaseResult -Id 'A' -Name 'tail_entry_substitution_block' -ExpectedResult 'BLOCK' -CycleResult $resultA

# B) Mid-chain entry substitution
$stateB = New-LiveState
$midIndex = [Math]::Floor($stateB.ledger.entries.Count / 2)
$origMid = $stateB.ledger.entries[$midIndex]
$stateB.ledger.entries[$midIndex] = New-ForgedSubstitute -EntryId ([string]$origMid.entry_id) -PreviousHash ([string]$origMid.previous_hash) -Seed 'MID_CHAIN_SUB'
$resultB = Invoke-GuardedCycle -State $stateB -Trusted $trusted
Add-CaseResult -Id 'B' -Name 'mid_chain_entry_substitution' -ExpectedResult 'BLOCK' -CycleResult $resultB

# C) Same-id different-content attack
$stateC = New-LiveState
$idxC = [Math]::Max(1, [Math]::Floor($stateC.ledger.entries.Count / 3))
$entryC = $stateC.ledger.entries[$idxC]
$stateC.ledger.entries[$idxC].entry_id = [string]$entryC.entry_id
$stateC.ledger.entries[$idxC].previous_hash = Get-StringHash -InputString 'ALTERED_PREV_HASH'
$stateC.ledger.entries[$idxC].fingerprint_hash = Get-StringHash -InputString 'ALTERED_FP_HASH'
$resultC = Invoke-GuardedCycle -State $stateC -Trusted $trusted
Add-CaseResult -Id 'C' -Name 'same_id_different_content_attack' -ExpectedResult 'BLOCK' -CycleResult $resultC

# D) Self-consistent resealed substitution
$stateD = New-LiveState
$idxD = [Math]::Max(1, [Math]::Floor($stateD.ledger.entries.Count / 2))
$origD = $stateD.ledger.entries[$idxD]
$stateD.ledger.entries[$idxD] = New-ForgedSubstitute -EntryId ([string]$origD.entry_id) -PreviousHash ([string]$origD.previous_hash) -Seed 'RESEALED_SUB'
Reseal-Downstream -Entries $stateD.ledger.entries -StartIndex $idxD -Seed 'RESEAL_DOWNSTREAM'
$newHeadD = Get-LedgerSnapshotHash -Ledger $stateD.ledger
$stateD.art111.ledger_head_hash = $newHeadD
$stateD.art112.ledger_head_hash = $newHeadD
$resultD = Invoke-GuardedCycle -State $stateD -Trusted $trusted
Add-CaseResult -Id 'D' -Name 'self_consistent_resealed_substitution' -ExpectedResult 'BLOCK' -CycleResult $resultD

# E) Partial substitution mismatch (ledger only)
$stateE = New-LiveState
$idxE = [Math]::Max(1, [Math]::Floor($stateE.ledger.entries.Count / 4))
$origE = $stateE.ledger.entries[$idxE]
$stateE.ledger.entries[$idxE] = New-ForgedSubstitute -EntryId ([string]$origE.entry_id) -PreviousHash ([string]$origE.previous_hash) -Seed 'LEDGER_ONLY_SUB'
$resultE = Invoke-GuardedCycle -State $stateE -Trusted $trusted
Add-CaseResult -Id 'E' -Name 'partial_substitution_mismatch' -ExpectedResult 'BLOCK' -CycleResult $resultE

# F) Canonical slot rewrite
$stateF = New-LiveState
$idxF = [Math]::Max(1, [Math]::Floor($stateF.ledger.entries.Count / 2))
$slotId = [string]$stateF.ledger.entries[$idxF].entry_id
$stateF.ledger.entries[$idxF] = New-ForgedSubstitute -EntryId $slotId -PreviousHash ([string]$stateF.ledger.entries[$idxF].previous_hash) -Seed 'CANONICAL_SLOT_REWRITE'
$resultF = Invoke-GuardedCycle -State $stateF -Trusted $trusted
Add-CaseResult -Id 'F' -Name 'canonical_slot_rewrite' -ExpectedResult 'BLOCK' -CycleResult $resultF

# G) Guarded-boundary substitution swap
$stateG = New-LiveState
$resultG = Invoke-GuardedCycle -State $stateG -Trusted $trusted -RuntimeMutation {
    param([hashtable]$State, [hashtable]$Trusted)
    $idxG = [Math]::Max(1, [Math]::Floor($State.ledger.entries.Count / 2))
    $entryG = $State.ledger.entries[$idxG]
    $State.ledger.entries[$idxG] = New-ForgedSubstitute -EntryId ([string]$entryG.entry_id) -PreviousHash ([string]$entryG.previous_hash) -Seed 'GUARDED_BOUNDARY_SWAP'
}
Add-CaseResult -Id 'G' -Name 'guarded_boundary_substitution_swap' -ExpectedResult 'BLOCK' -CycleResult $resultG

# H) Clean control
$stateH = New-LiveState
$resultH = Invoke-GuardedCycle -State $stateH -Trusted $trusted
Add-CaseResult -Id 'H' -Name 'clean_control' -ExpectedResult 'ALLOW' -CycleResult $resultH

$consistencyPass = $true
if ($script:CaseMatrix.Count -ne 8) { $consistencyPass = $false }
if (($script:passCount + $script:failCount) -ne 8) { $consistencyPass = $false }
if ($script:undetected_substitution_count -ne 0) { $consistencyPass = $false }
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
    'SUBSTITUTION_ATTACK_MATRIX',
    'A: tail_entry_substitution_block => expect BLOCK',
    'B: mid_chain_entry_substitution => expect BLOCK',
    'C: same_id_different_content_attack => expect BLOCK',
    'D: self_consistent_resealed_substitution => expect BLOCK',
    'E: partial_substitution_mismatch => expect BLOCK',
    'F: canonical_slot_rewrite => expect BLOCK',
    'G: guarded_boundary_substitution_swap => expect BLOCK',
    'H: clean_control => expect ALLOW'
)

Write-ProofFile -Path (Join-Path $PF '01_status.txt') -Content @(
    'PHASE=53.17',
    'TITLE=' + $Title,
    'GATE=' + $gate,
    'PASS_COUNT=' + $script:passCount + '/8',
    'FAIL_COUNT=' + $script:failCount,
    'substitution_rejected_count=' + $script:substitution_rejected_count,
    'in_place_replacement_rejected_count=' + $script:in_place_replacement_rejected_count,
    'undetected_substitution_count=' + $script:undetected_substitution_count,
    'false_positive_count=' + $script:false_positive_count,
    'consistency_check=' + $(if ($consistencyPass) { 'PASS' } else { 'FAIL' }),
    'FAIL_CLOSED=TRUE',
    'NO_FALLBACK=TRUE',
    'NO_SILENT_ACCEPTANCE=TRUE'
)

Write-ProofFile -Path (Join-Path $PF '14_validation_results.txt') -Content $matrixLines
Write-ProofFile -Path (Join-Path $PF '15_substitution_attack_matrix.txt') -Content $testMatrix
Write-ProofFile -Path (Join-Path $PF '15_entry_identity_slot_integrity_map.txt') -Content $script:SlotIntegrityMap.ToArray()
Write-ProofFile -Path (Join-Path $PF '15_detection_vectors.txt') -Content $vectorLines

Write-ProofFile -Path (Join-Path $PF '98_gate_phase53_17.txt') -Content @(
    'GATE=' + $gate,
    'PASS_COUNT=' + $script:passCount + '/8',
    'FAIL_COUNT=' + $script:failCount,
    'substitution_rejected_count=' + $script:substitution_rejected_count,
    'in_place_replacement_rejected_count=' + $script:in_place_replacement_rejected_count,
    'undetected_substitution_count=' + $script:undetected_substitution_count,
    'false_positive_count=' + $script:false_positive_count
)

$zipPath = $PF + '.zip'
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path $PF -DestinationPath $zipPath -Force

Write-Output ('PF=' + $PF)
Write-Output ('ZIP=' + $zipPath)
Write-Output ('GATE=' + $gate)
