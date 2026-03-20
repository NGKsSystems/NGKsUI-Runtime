#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Phase 53.20: Canonical-Order Permutation Resistance + Record Shuffling Rejection

$Phase = '53.20'
$Title = 'Canonical-Order Permutation Resistance and Record Shuffling Rejection'
$PF = Join-Path $PSScriptRoot '..\..\' '_proof' "phase53_20_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_canonical_order_permutation_record_shuffling_rejection_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $PF -Force | Out-Null

$script:CaseMatrix = [System.Collections.Generic.List[object]]::new()
$script:DetectionVectors = [System.Collections.Generic.List[object]]::new()
$script:CanonicalOrderMap = [System.Collections.Generic.List[string]]::new()

$script:passCount = 0
$script:failCount = 0
$script:permutation_rejected_count = 0
$script:record_shuffle_rejected_count = 0
$script:undetected_permutation_count = 0
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

function Add-Vector {
    param([System.Collections.Generic.List[string]]$Vectors, [string]$Value)
    if (-not ($Vectors -contains $Value)) {
        [void]$Vectors.Add($Value)
    }
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
        $Entries[$i].fingerprint_hash = Get-StringHash -InputString ('RESEALED_SHUFFLE|' + $entryId + '|' + $i + '|' + $Seed)
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
        Add-Vector -Vectors $vectors -Value 'ledger_empty'
        return ,$vectors
    }

    $ledgerLen = $entries.Count
    $trustedLen = [int]$Trusted.current_ledger_length
    if ($ledgerLen -ne $trustedLen) {
        Add-Vector -Vectors $vectors -Value 'length_mismatch'
    }

    $seenIds = @{}
    $setMismatch = $false
    $mismatchIndices = [System.Collections.Generic.List[int]]::new()

    for ($i = 0; $i -lt $entries.Count; $i++) {
        $entry = $entries[$i]
        $entryId = [string]$entry.entry_id

        if (-not $Trusted.current_entry_ids.ContainsKey($entryId)) {
            $setMismatch = $true
            Add-Vector -Vectors $vectors -Value 'membership_mismatch'
        }

        if ($seenIds.ContainsKey($entryId)) {
            $setMismatch = $true
            Add-Vector -Vectors $vectors -Value 'membership_mismatch'
        }
        else {
            $seenIds[$entryId] = $true
        }

        $trustedIdForSlot = if ($i -lt $Trusted.current_entry_ids_in_order.Count) { [string]$Trusted.current_entry_ids_in_order[$i] } else { '' }
        $trustedSigForSlot = if ($i -lt $Trusted.current_entry_signatures.Count) { [string]$Trusted.current_entry_signatures[$i] } else { '' }
        $currSig = Get-EntrySignature -Entry $entry

        if ($entryId -ne $trustedIdForSlot) {
            [void]$mismatchIndices.Add($i)
            Add-Vector -Vectors $vectors -Value 'canonical_order_violation'
            Add-Vector -Vectors $vectors -Value 'record_shuffle'
        }

        if ($currSig -ne $trustedSigForSlot) {
            Add-Vector -Vectors $vectors -Value 'slot_integrity_failure'
        }
    }

    if ($seenIds.Keys.Count -ne $Trusted.current_entry_ids.Count) {
        $setMismatch = $true
        Add-Vector -Vectors $vectors -Value 'membership_mismatch'
    }

    if (-not $setMismatch) {
        $currentIdOrder = @($entries | ForEach-Object { [string]$_.entry_id })
        if (($currentIdOrder -join '|') -ne ($Trusted.current_entry_ids_in_order -join '|')) {
            Add-Vector -Vectors $vectors -Value 'same_set_permutation'
            Add-Vector -Vectors $vectors -Value 'record_shuffle'
        }
    }

    if ($mismatchIndices.Count -eq 2) {
        $first = [int]$mismatchIndices[0]
        $second = [int]$mismatchIndices[1]
        if (($second -eq ($first + 1)) -and
            ([string]$entries[$first].entry_id -eq [string]$Trusted.current_entry_ids_in_order[$second]) -and
            ([string]$entries[$second].entry_id -eq [string]$Trusted.current_entry_ids_in_order[$first])) {
            Add-Vector -Vectors $vectors -Value 'adjacent_swap'
        }
        else {
            Add-Vector -Vectors $vectors -Value 'non_adjacent_shuffle'
        }
    }
    elseif ($mismatchIndices.Count -gt 0) {
        Add-Vector -Vectors $vectors -Value 'non_adjacent_shuffle'
    }

    $a111Len = [int]$State.art111.ledger_length
    $a111Latest = [string]$State.art111.latest_entry_id
    $a111Head = [string]$State.art111.ledger_head_hash
    $a112Head = [string]$State.art112.ledger_head_hash
    $ledgerLatest = [string]$entries[-1].entry_id

    if ($a111Len -ne $ledgerLen) { Add-Vector -Vectors $vectors -Value 'cross_artifact_mismatch' }
    if ($a111Latest -ne $ledgerLatest) { Add-Vector -Vectors $vectors -Value 'cross_artifact_mismatch' }
    if ($a111Head -ne $a112Head) { Add-Vector -Vectors $vectors -Value 'cross_artifact_mismatch' }

    $chainSig = Build-ChainSignature -Entries $entries
    if ($chainSig -ne $Trusted.current_chain_signature) {
        Add-Vector -Vectors $vectors -Value 'lineage_break'
        Add-Vector -Vectors $vectors -Value 'continuity_break'
    }

    $ledgerHash = Get-LedgerSnapshotHash -Ledger $State.ledger
    if ($ledgerHash -ne $Trusted.current_ledger_snapshot_hash) {
        Add-Vector -Vectors $vectors -Value 'identity_failure'
    }

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
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'BLOCK') { $script:permutation_rejected_count++ }
    if (($vectors -contains 'record_shuffle' -or $vectors -contains 'same_set_permutation') -and $actual -eq 'BLOCK') { $script:record_shuffle_rejected_count++ }
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'ALLOW') { $script:undetected_permutation_count++ }
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

$currentEntryIds = @{}
$currentEntryIdsInOrder = [System.Collections.Generic.List[string]]::new()
$currentEntrySignatures = [System.Collections.Generic.List[string]]::new()
for ($i = 0; $i -lt $entries.Count; $i++) {
    $eid = [string]$entries[$i].entry_id
    $sig = Get-EntrySignature -Entry $entries[$i]
    $currentEntryIds[$eid] = $true
    [void]$currentEntryIdsInOrder.Add($eid)
    [void]$currentEntrySignatures.Add($sig)
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
    current_entry_ids = $currentEntryIds
    current_entry_ids_in_order = $currentEntryIdsInOrder.ToArray()
    current_entry_signatures = $currentEntrySignatures.ToArray()
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

[void]$script:CanonicalOrderMap.Add('TRUSTED_CHAIN_LENGTH=' + $trusted.current_ledger_length)
[void]$script:CanonicalOrderMap.Add('TRUSTED_LATEST_ENTRY_ID=' + $trusted.current_latest_entry_id)
[void]$script:CanonicalOrderMap.Add('TRUSTED_LEDGER_HEAD_HASH=' + $trusted.current_ledger_head_hash)
[void]$script:CanonicalOrderMap.Add('CANONICAL_ORDER_RULE=record_membership_and_slot_order_must_match')
[void]$script:CanonicalOrderMap.Add('SLOT_0001=' + [string]$trusted.current_entry_ids_in_order[0])
[void]$script:CanonicalOrderMap.Add('SLOT_0002=' + [string]$trusted.current_entry_ids_in_order[1])
[void]$script:CanonicalOrderMap.Add('SLOT_LAST=' + [string]$trusted.current_entry_ids_in_order[$trusted.current_ledger_length - 1])
[void]$script:CanonicalOrderMap.Add('DETECTION_VECTOR_SAME_SET_PERMUTATION=enabled')
[void]$script:CanonicalOrderMap.Add('DETECTION_VECTOR_ADJACENT_SWAP=enabled')
[void]$script:CanonicalOrderMap.Add('DETECTION_VECTOR_NON_ADJACENT_SHUFFLE=enabled')
[void]$script:CanonicalOrderMap.Add('DETECTION_VECTOR_RECORD_SHUFFLE=enabled')
[void]$script:CanonicalOrderMap.Add('DETECTION_VECTOR_CROSS_ARTIFACT_MISMATCH=enabled')

# A) Full-chain permutation block
$stateA = New-LiveState
$stateA.ledger.entries = @($stateA.ledger.entries | Sort-Object { [string]$_.entry_id } -Descending)
$stateA.art111.latest_entry_id = [string]$stateA.ledger.entries[-1].entry_id
$headA = Get-LedgerSnapshotHash -Ledger $stateA.ledger
$stateA.art111.ledger_head_hash = $headA
$stateA.art112.ledger_head_hash = $headA
$resultA = Invoke-GuardedCycle -State $stateA -Trusted $trusted
Add-CaseResult -Id 'A' -Name 'full_chain_permutation_block' -ExpectedResult 'BLOCK' -CycleResult $resultA

# B) Adjacent swap detection
$stateB = New-LiveState
$tmpB = $stateB.ledger.entries[5]
$stateB.ledger.entries[5] = $stateB.ledger.entries[6]
$stateB.ledger.entries[6] = $tmpB
$resultB = Invoke-GuardedCycle -State $stateB -Trusted $trusted
Add-CaseResult -Id 'B' -Name 'adjacent_swap_detection' -ExpectedResult 'BLOCK' -CycleResult $resultB

# C) Non-adjacent shuffle
$stateC = New-LiveState
$movedC = $stateC.ledger.entries[2]
$remainingC = @($stateC.ledger.entries[0..1]) + @($stateC.ledger.entries[3..($stateC.ledger.entries.Count - 1)])
$stateC.ledger.entries = @($remainingC[0..8]) + @($movedC) + @($remainingC[9..($remainingC.Count - 1)])
$resultC = Invoke-GuardedCycle -State $stateC -Trusted $trusted
Add-CaseResult -Id 'C' -Name 'non_adjacent_shuffle' -ExpectedResult 'BLOCK' -CycleResult $resultC

# D) Same-set self-consistent resealed shuffle
$stateD = New-LiveState
$tmpD = $stateD.ledger.entries[3]
$stateD.ledger.entries[3] = $stateD.ledger.entries[9]
$stateD.ledger.entries[9] = $tmpD
Reseal-Downstream -Entries $stateD.ledger.entries -StartIndex 3 -Seed 'SELF_CONSISTENT_SHUFFLE'
$stateD.art111.latest_entry_id = [string]$stateD.ledger.entries[-1].entry_id
$headD = Get-LedgerSnapshotHash -Ledger $stateD.ledger
$stateD.art111.ledger_head_hash = $headD
$stateD.art112.ledger_head_hash = $headD
$resultD = Invoke-GuardedCycle -State $stateD -Trusted $trusted
Add-CaseResult -Id 'D' -Name 'same_set_self_consistent_resealed_shuffle' -ExpectedResult 'BLOCK' -CycleResult $resultD

# E) Partial permutation mismatch
$stateE = New-LiveState
$tmpE = $stateE.ledger.entries[1]
$stateE.ledger.entries[1] = $stateE.ledger.entries[2]
$stateE.ledger.entries[2] = $tmpE
# art111/art112 intentionally untouched
$resultE = Invoke-GuardedCycle -State $stateE -Trusted $trusted
Add-CaseResult -Id 'E' -Name 'partial_permutation_mismatch' -ExpectedResult 'BLOCK' -CycleResult $resultE

# F) Multi-entry shuffle
$stateF = New-LiveState
    $reorderedF = @(
    $stateF.ledger.entries[0],
    $stateF.ledger.entries[4],
    $stateF.ledger.entries[2],
    $stateF.ledger.entries[7],
    $stateF.ledger.entries[1],
    $stateF.ledger.entries[5],
        $stateF.ledger.entries[3],
        $stateF.ledger.entries[6]
) + @($stateF.ledger.entries[8..($stateF.ledger.entries.Count - 1)])
$stateF.ledger.entries = $reorderedF
$resultF = Invoke-GuardedCycle -State $stateF -Trusted $trusted
Add-CaseResult -Id 'F' -Name 'multi_entry_shuffle' -ExpectedResult 'BLOCK' -CycleResult $resultF

# G) Guarded-boundary shuffle swap
$stateG = New-LiveState
$resultG = Invoke-GuardedCycle -State $stateG -Trusted $trusted -RuntimeMutation {
    param([hashtable]$State, [hashtable]$Trusted)
    $tmpG = $State.ledger.entries[10]
    $State.ledger.entries[10] = $State.ledger.entries[11]
    $State.ledger.entries[11] = $tmpG
}
Add-CaseResult -Id 'G' -Name 'guarded_boundary_shuffle_swap' -ExpectedResult 'BLOCK' -CycleResult $resultG

# H) Clean control
$stateH = New-LiveState
$resultH = Invoke-GuardedCycle -State $stateH -Trusted $trusted
Add-CaseResult -Id 'H' -Name 'clean_control' -ExpectedResult 'ALLOW' -CycleResult $resultH

$consistencyPass = $true
if ($script:CaseMatrix.Count -ne 8) { $consistencyPass = $false }
if (($script:passCount + $script:failCount) -ne 8) { $consistencyPass = $false }
if ($script:undetected_permutation_count -ne 0) { $consistencyPass = $false }
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

$permutationMatrix = @(
    'PERMUTATION_ATTACK_MATRIX',
    'A: full_chain_permutation_block => expect BLOCK',
    'B: adjacent_swap_detection => expect BLOCK',
    'C: non_adjacent_shuffle => expect BLOCK',
    'D: same_set_self_consistent_resealed_shuffle => expect BLOCK',
    'E: partial_permutation_mismatch => expect BLOCK',
    'F: multi_entry_shuffle => expect BLOCK',
    'G: guarded_boundary_shuffle_swap => expect BLOCK',
    'H: clean_control => expect ALLOW'
)

Write-ProofFile -Path (Join-Path $PF '01_status.txt') -Content @(
    'PHASE=53.20',
    'TITLE=' + $Title,
    'GATE=' + $gate,
    'PASS_COUNT=' + $script:passCount + '/8',
    'FAIL_COUNT=' + $script:failCount,
    'permutation_rejected_count=' + $script:permutation_rejected_count,
    'record_shuffle_rejected_count=' + $script:record_shuffle_rejected_count,
    'undetected_permutation_count=' + $script:undetected_permutation_count,
    'false_positive_count=' + $script:false_positive_count,
    'consistency_check=' + $(if ($consistencyPass) { 'PASS' } else { 'FAIL' }),
    'FAIL_CLOSED=TRUE',
    'NO_FALLBACK=TRUE',
    'NO_SILENT_ACCEPTANCE=TRUE'
)

Write-ProofFile -Path (Join-Path $PF '14_validation_results.txt') -Content $matrixLines
Write-ProofFile -Path (Join-Path $PF '15_permutation_attack_matrix.txt') -Content $permutationMatrix
Write-ProofFile -Path (Join-Path $PF '15_canonical_order_slot_integrity_map.txt') -Content $script:CanonicalOrderMap.ToArray()
Write-ProofFile -Path (Join-Path $PF '15_detection_vectors.txt') -Content $vectorLines

Write-ProofFile -Path (Join-Path $PF '98_gate_phase53_20.txt') -Content @(
    'GATE=' + $gate,
    'PASS_COUNT=' + $script:passCount + '/8',
    'FAIL_COUNT=' + $script:failCount,
    'permutation_rejected_count=' + $script:permutation_rejected_count,
    'record_shuffle_rejected_count=' + $script:record_shuffle_rejected_count,
    'undetected_permutation_count=' + $script:undetected_permutation_count,
    'false_positive_count=' + $script:false_positive_count
)

$zipPath = $PF + '.zip'
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path $PF -DestinationPath $zipPath -Force

Write-Output ('PF=' + $PF)
Write-Output ('ZIP=' + $zipPath)
Write-Output ('GATE=' + $gate)