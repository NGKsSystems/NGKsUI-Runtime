#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Phase 53.19: Baseline-Gap Replay Resistance + Removed-Record Resurrection Rejection

$Phase = '53.19'
$Title = 'Baseline-Gap Replay Resistance and Removed-Record Resurrection Rejection'
$PF = Join-Path $PSScriptRoot '..\..\' '_proof' "phase53_19_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_baseline_gap_replay_removed_record_resurrection_rejection_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $PF -Force | Out-Null

$script:CaseMatrix = [System.Collections.Generic.List[object]]::new()
$script:DetectionVectors = [System.Collections.Generic.List[object]]::new()
$script:HistoricalReuseMap = [System.Collections.Generic.List[string]]::new()

$script:passCount = 0
$script:failCount = 0
$script:resurrection_rejected_count = 0
$script:removed_record_reinsertion_rejected_count = 0
$script:undetected_resurrection_count = 0
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

function New-HistoricalRecord {
    param(
        [string]$RecordId,
        [string]$PreviousHash,
        [string]$Seed
    )

    return @{
        entry_id = $RecordId
        previous_hash = $PreviousHash
        fingerprint_hash = Get-StringHash -InputString ('HISTORICAL_VALID_RECORD|' + $RecordId + '|' + $Seed)
        timestamp = (Get-Date).AddDays(-30).ToString('o')
        lineage_state = 'historical_valid_removed_from_current_baseline'
        canonical_membership = 'removed'
    }
}

function Clone-Entry {
    param($Entry)
    return (Copy-Deep -Object $Entry)
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
        $Entries[$i].fingerprint_hash = Get-StringHash -InputString ('RESEALED_RESURRECTION|' + $entryId + '|' + $i + '|' + $Seed)
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

    for ($i = 0; $i -lt $entries.Count; $i++) {
        $entry = $entries[$i]
        $entryId = [string]$entry.entry_id
        $sig = Get-EntrySignature -Entry $entry

        if ($Trusted.historical_removed_ids.ContainsKey($entryId)) {
            Add-Vector -Vectors $vectors -Value 'removed_record_resurrection'
            Add-Vector -Vectors $vectors -Value 'removed_record_reinsertion'
            Add-Vector -Vectors $vectors -Value 'canonical_membership_failure'
            if ($i -lt ($entries.Count - 1)) {
                Add-Vector -Vectors $vectors -Value 'historical_gap_replay'
            }
        }

        if ($Trusted.historical_removed_signatures.ContainsKey($sig)) {
            Add-Vector -Vectors $vectors -Value 'old_valid_now_invalid_reuse'
            Add-Vector -Vectors $vectors -Value 'canonical_membership_failure'
            $historicalIndex = [int]$Trusted.historical_removed_signatures[$sig]
            if ($historicalIndex -ne $i) {
                Add-Vector -Vectors $vectors -Value 'historical_gap_replay'
            }
        }

        if (-not $Trusted.current_entry_ids.ContainsKey($entryId) -and -not $Trusted.historical_removed_ids.ContainsKey($entryId)) {
            Add-Vector -Vectors $vectors -Value 'noncanonical_identity'
        }
    }

    $scanLen = [Math]::Min($entries.Count, $Trusted.current_entry_signatures.Count)
    for ($i = 0; $i -lt $scanLen; $i++) {
        $currSig = Get-EntrySignature -Entry $entries[$i]
        $trustedSig = [string]$Trusted.current_entry_signatures[$i]
        if ($currSig -ne $trustedSig) {
            Add-Vector -Vectors $vectors -Value 'canonical_membership_failure'
            if ($i -lt ($Trusted.current_ledger_length - 1)) {
                Add-Vector -Vectors $vectors -Value 'historical_gap_replay'
            }
        }
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
        Add-Vector -Vectors $vectors -Value 'continuity_break'
        Add-Vector -Vectors $vectors -Value 'lineage_break'
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
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'BLOCK') { $script:resurrection_rejected_count++ }
    if (($vectors -contains 'removed_record_reinsertion') -and $actual -eq 'BLOCK') { $script:removed_record_reinsertion_rejected_count++ }
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'ALLOW') { $script:undetected_resurrection_count++ }
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
$currentEntrySignatures = [System.Collections.Generic.List[string]]::new()
for ($i = 0; $i -lt $entries.Count; $i++) {
    $eid = [string]$entries[$i].entry_id
    $sig = Get-EntrySignature -Entry $entries[$i]
    $currentEntryIds[$eid] = $true
    [void]$currentEntrySignatures.Add($sig)
}

$historicalRemovedRecords = [System.Collections.Generic.List[object]]::new()
$historicalRemovedById = @{}
$historicalRemovedBySignature = @{}

$historicalSeeds = @(
    @{ id = 'GH-0004'; prev = 'HIST-PREV-0003'; seed = 'OLD_VALID_REMOVED_1'; index = 3 },
    @{ id = 'GH-0007'; prev = 'HIST-PREV-0006'; seed = 'OLD_VALID_REMOVED_2'; index = 6 },
    @{ id = 'GH-0011'; prev = 'HIST-PREV-0010'; seed = 'OLD_VALID_REMOVED_3'; index = 10 }
)

foreach ($item in $historicalSeeds) {
    $record = New-HistoricalRecord -RecordId $item.id -PreviousHash $item.prev -Seed $item.seed
    $sig = Get-EntrySignature -Entry $record
    [void]$historicalRemovedRecords.Add($record)
    $historicalRemovedById[[string]$item.id] = $true
    $historicalRemovedBySignature[$sig] = [int]$item.index
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
    current_entry_signatures = $currentEntrySignatures.ToArray()
    historical_removed_ids = $historicalRemovedById
    historical_removed_signatures = $historicalRemovedBySignature
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

[void]$script:HistoricalReuseMap.Add('TRUSTED_CHAIN_LENGTH=' + $trusted.current_ledger_length)
[void]$script:HistoricalReuseMap.Add('TRUSTED_LATEST_ENTRY_ID=' + $trusted.current_latest_entry_id)
[void]$script:HistoricalReuseMap.Add('TRUSTED_LEDGER_HEAD_HASH=' + $trusted.current_ledger_head_hash)
[void]$script:HistoricalReuseMap.Add('CANONICAL_MEMBERSHIP_RULE=current_chain_only_records_allowed')
[void]$script:HistoricalReuseMap.Add('HISTORICAL_REMOVED_RECORD_01=GH-0004')
[void]$script:HistoricalReuseMap.Add('HISTORICAL_REMOVED_RECORD_02=GH-0007')
[void]$script:HistoricalReuseMap.Add('HISTORICAL_REMOVED_RECORD_03=GH-0011')
[void]$script:HistoricalReuseMap.Add('DETECTION_VECTOR_REMOVED_RECORD_RESURRECTION=enabled')
[void]$script:HistoricalReuseMap.Add('DETECTION_VECTOR_HISTORICAL_GAP_REPLAY=enabled')
[void]$script:HistoricalReuseMap.Add('DETECTION_VECTOR_OLD_VALID_NOW_INVALID_REUSE=enabled')
[void]$script:HistoricalReuseMap.Add('DETECTION_VECTOR_CANONICAL_MEMBERSHIP_FAILURE=enabled')
[void]$script:HistoricalReuseMap.Add('DETECTION_VECTOR_CROSS_ARTIFACT_MISMATCH=enabled')

# A) Removed-record resurrection block
$stateA = New-LiveState
$recordA = Clone-Entry -Entry $historicalRemovedRecords[0]
$stateA.ledger.entries = @($stateA.ledger.entries) + @($recordA)
$stateA.art111.ledger_length = $stateA.ledger.entries.Count
$stateA.art111.latest_entry_id = [string]$recordA.entry_id
$headA = Get-LedgerSnapshotHash -Ledger $stateA.ledger
$stateA.art111.ledger_head_hash = $headA
$stateA.art112.ledger_head_hash = $headA
$resultA = Invoke-GuardedCycle -State $stateA -Trusted $trusted
Add-CaseResult -Id 'A' -Name 'removed_record_resurrection_block' -ExpectedResult 'BLOCK' -CycleResult $resultA

# B) Historical-gap replay
$stateB = New-LiveState
$recordB = Clone-Entry -Entry $historicalRemovedRecords[1]
$insertAtB = 7
$beforeB = @($stateB.ledger.entries[0..($insertAtB - 1)])
$afterB = @($stateB.ledger.entries[$insertAtB..($stateB.ledger.entries.Count - 1)])
$stateB.ledger.entries = $beforeB + @($recordB) + $afterB
$stateB.art111.ledger_length = $stateB.ledger.entries.Count
$stateB.art111.latest_entry_id = [string]$stateB.ledger.entries[-1].entry_id
$headB = Get-LedgerSnapshotHash -Ledger $stateB.ledger
$stateB.art111.ledger_head_hash = $headB
$stateB.art112.ledger_head_hash = $headB
$resultB = Invoke-GuardedCycle -State $stateB -Trusted $trusted
Add-CaseResult -Id 'B' -Name 'historical_gap_replay' -ExpectedResult 'BLOCK' -CycleResult $resultB

# C) Old-valid / now-invalid record reuse
$stateC = New-LiveState
$recordC = Clone-Entry -Entry $historicalRemovedRecords[2]
$replaceIndexC = 9
$stateC.ledger.entries[$replaceIndexC] = $recordC
$resultC = Invoke-GuardedCycle -State $stateC -Trusted $trusted
Add-CaseResult -Id 'C' -Name 'old_valid_now_invalid_record_reuse' -ExpectedResult 'BLOCK' -CycleResult $resultC

# D) Self-consistent resurrected state
$stateD = New-LiveState
$recordD = Clone-Entry -Entry $historicalRemovedRecords[0]
$insertAtD = 5
$beforeD = @($stateD.ledger.entries[0..($insertAtD - 1)])
$afterD = @($stateD.ledger.entries[$insertAtD..($stateD.ledger.entries.Count - 1)])
$stateD.ledger.entries = $beforeD + @($recordD) + $afterD
Reseal-Downstream -Entries $stateD.ledger.entries -StartIndex $insertAtD -Seed 'RESURRECTION_RESEAL'
$stateD.art111.ledger_length = $stateD.ledger.entries.Count
$stateD.art111.latest_entry_id = [string]$stateD.ledger.entries[-1].entry_id
$headD = Get-LedgerSnapshotHash -Ledger $stateD.ledger
$stateD.art111.ledger_head_hash = $headD
$stateD.art112.ledger_head_hash = $headD
$resultD = Invoke-GuardedCycle -State $stateD -Trusted $trusted
Add-CaseResult -Id 'D' -Name 'self_consistent_resurrected_state' -ExpectedResult 'BLOCK' -CycleResult $resultD

# E) Partial resurrection mismatch
$stateE = New-LiveState
$recordE = Clone-Entry -Entry $historicalRemovedRecords[1]
$stateE.ledger.entries = @($stateE.ledger.entries) + @($recordE)
# art111/art112 intentionally untouched
$resultE = Invoke-GuardedCycle -State $stateE -Trusted $trusted
Add-CaseResult -Id 'E' -Name 'partial_resurrection_mismatch' -ExpectedResult 'BLOCK' -CycleResult $resultE

# F) Multi-record resurrection
$stateF = New-LiveState
$recordF1 = Clone-Entry -Entry $historicalRemovedRecords[0]
$recordF2 = Clone-Entry -Entry $historicalRemovedRecords[2]
$stateF.ledger.entries = @($stateF.ledger.entries[0..4]) + @($recordF1, $recordF2) + @($stateF.ledger.entries[5..($stateF.ledger.entries.Count - 1)])
$stateF.art111.ledger_length = $stateF.ledger.entries.Count
$stateF.art111.latest_entry_id = [string]$stateF.ledger.entries[-1].entry_id
$headF = Get-LedgerSnapshotHash -Ledger $stateF.ledger
$stateF.art111.ledger_head_hash = $headF
$stateF.art112.ledger_head_hash = $headF
$resultF = Invoke-GuardedCycle -State $stateF -Trusted $trusted
Add-CaseResult -Id 'F' -Name 'multi_record_resurrection' -ExpectedResult 'BLOCK' -CycleResult $resultF

# G) Guarded-boundary resurrection swap
$stateG = New-LiveState
$resultG = Invoke-GuardedCycle -State $stateG -Trusted $trusted -RuntimeMutation {
    param([hashtable]$State, [hashtable]$Trusted)
    $recordG = Clone-Entry -Entry $historicalRemovedRecords[0]
    $State.ledger.entries = @($State.ledger.entries) + @($recordG)
    $State.art111.ledger_length = $State.ledger.entries.Count
    $State.art111.latest_entry_id = [string]$recordG.entry_id
}
Add-CaseResult -Id 'G' -Name 'guarded_boundary_resurrection_swap' -ExpectedResult 'BLOCK' -CycleResult $resultG

# H) Clean control
$stateH = New-LiveState
$resultH = Invoke-GuardedCycle -State $stateH -Trusted $trusted
Add-CaseResult -Id 'H' -Name 'clean_control' -ExpectedResult 'ALLOW' -CycleResult $resultH

$consistencyPass = $true
if ($script:CaseMatrix.Count -ne 8) { $consistencyPass = $false }
if (($script:passCount + $script:failCount) -ne 8) { $consistencyPass = $false }
if ($script:undetected_resurrection_count -ne 0) { $consistencyPass = $false }
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

$resurrectionMatrix = @(
    'RESURRECTION_ATTACK_MATRIX',
    'A: removed_record_resurrection_block => expect BLOCK',
    'B: historical_gap_replay => expect BLOCK',
    'C: old_valid_now_invalid_record_reuse => expect BLOCK',
    'D: self_consistent_resurrected_state => expect BLOCK',
    'E: partial_resurrection_mismatch => expect BLOCK',
    'F: multi_record_resurrection => expect BLOCK',
    'G: guarded_boundary_resurrection_swap => expect BLOCK',
    'H: clean_control => expect ALLOW'
)

Write-ProofFile -Path (Join-Path $PF '01_status.txt') -Content @(
    'PHASE=53.19',
    'TITLE=' + $Title,
    'GATE=' + $gate,
    'PASS_COUNT=' + $script:passCount + '/8',
    'FAIL_COUNT=' + $script:failCount,
    'resurrection_rejected_count=' + $script:resurrection_rejected_count,
    'removed_record_reinsertion_rejected_count=' + $script:removed_record_reinsertion_rejected_count,
    'undetected_resurrection_count=' + $script:undetected_resurrection_count,
    'false_positive_count=' + $script:false_positive_count,
    'consistency_check=' + $(if ($consistencyPass) { 'PASS' } else { 'FAIL' }),
    'FAIL_CLOSED=TRUE',
    'NO_FALLBACK=TRUE',
    'NO_SILENT_ACCEPTANCE=TRUE'
)

Write-ProofFile -Path (Join-Path $PF '14_validation_results.txt') -Content $matrixLines
Write-ProofFile -Path (Join-Path $PF '15_resurrection_attack_matrix.txt') -Content $resurrectionMatrix
Write-ProofFile -Path (Join-Path $PF '15_canonical_membership_historical_reuse_map.txt') -Content $script:HistoricalReuseMap.ToArray()
Write-ProofFile -Path (Join-Path $PF '15_detection_vectors.txt') -Content $vectorLines

Write-ProofFile -Path (Join-Path $PF '98_gate_phase53_19.txt') -Content @(
    'GATE=' + $gate,
    'PASS_COUNT=' + $script:passCount + '/8',
    'FAIL_COUNT=' + $script:failCount,
    'resurrection_rejected_count=' + $script:resurrection_rejected_count,
    'removed_record_reinsertion_rejected_count=' + $script:removed_record_reinsertion_rejected_count,
    'undetected_resurrection_count=' + $script:undetected_resurrection_count,
    'false_positive_count=' + $script:false_positive_count
)

$zipPath = $PF + '.zip'
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path $PF -DestinationPath $zipPath -Force

Write-Output ('PF=' + $PF)
Write-Output ('ZIP=' + $zipPath)
Write-Output ('GATE=' + $gate)
