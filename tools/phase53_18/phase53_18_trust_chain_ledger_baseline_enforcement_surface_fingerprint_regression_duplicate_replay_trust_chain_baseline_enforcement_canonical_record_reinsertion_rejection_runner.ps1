#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Phase 53.18: Duplicate-Entry Replay Resistance + Canonical Record Re-Insertion Rejection

$Phase = '53.18'
$Title = 'Duplicate-Entry Replay Resistance and Canonical Record Re-Insertion Rejection'
$PF = Join-Path $PSScriptRoot '..\..\' '_proof' "phase53_18_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_duplicate_replay_trust_chain_baseline_enforcement_canonical_record_reinsertion_rejection_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $PF -Force | Out-Null

$script:CaseMatrix = [System.Collections.Generic.List[object]]::new()
$script:DetectionVectors = [System.Collections.Generic.List[object]]::new()
$script:EntryReuseMap = [System.Collections.Generic.List[string]]::new()

$script:passCount = 0
$script:failCount = 0
$script:duplicate_replay_rejected_count = 0
$script:canonical_reinsertion_rejected_count = 0
$script:undetected_duplicate_replay_count = 0
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
        $eid = [string]$Entries[$i].entry_id
        $Entries[$i].fingerprint_hash = Get-StringHash -InputString ('RESEALED_DUP|' + $eid + '|' + $i + '|' + $Seed)
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

    $idToSigs = @{}
    $sigToIndices = @{}

    for ($i = 0; $i -lt $entries.Count; $i++) {
        $entry = $entries[$i]
        $entryId = [string]$entry.entry_id
        $sig = Get-EntrySignature -Entry $entry

        if (-not $idToSigs.ContainsKey($entryId)) {
            $idToSigs[$entryId] = [System.Collections.Generic.List[string]]::new()
        }
        [void]$idToSigs[$entryId].Add($sig)

        if (-not $sigToIndices.ContainsKey($sig)) {
            $sigToIndices[$sig] = [System.Collections.Generic.List[int]]::new()
        }
        [void]$sigToIndices[$sig].Add($i)

        if ($Trusted.signature_to_index.ContainsKey($sig)) {
            $trustedIndex = [int]$Trusted.signature_to_index[$sig]
            if ($trustedIndex -ne $i) {
                Add-Vector -Vectors $vectors -Value 'canonical_record_reinsertion'
            }
        }
    }

    foreach ($id in $idToSigs.Keys) {
        $sigs = @($idToSigs[$id])
        if ($sigs.Count -gt 1) {
            Add-Vector -Vectors $vectors -Value 'entry_id_reuse'
            Add-Vector -Vectors $vectors -Value 'canonical_record_reinsertion'

            $uniq = @{}
            foreach ($s in $sigs) { $uniq[$s] = $true }
            if ($uniq.Keys.Count -eq 1) {
                Add-Vector -Vectors $vectors -Value 'same_id_replay_same_content'
            }
            else {
                Add-Vector -Vectors $vectors -Value 'same_id_replay_modified_content'
            }
        }
    }

    foreach ($sig in $sigToIndices.Keys) {
        $idx = @($sigToIndices[$sig])
        if ($idx.Count -gt 1) {
            Add-Vector -Vectors $vectors -Value 'duplicate_identity_reuse'
            Add-Vector -Vectors $vectors -Value 'canonical_record_reinsertion'
        }
    }

    $scanLen = [Math]::Min($entries.Count, $Trusted.entry_signatures.Count)
    for ($i = 0; $i -lt $scanLen; $i++) {
        $currSig = Get-EntrySignature -Entry $entries[$i]
        $trustedSig = [string]$Trusted.entry_signatures[$i]
        if ($currSig -ne $trustedSig) {
            if ($i -eq ($Trusted.current_ledger_length - 1)) {
                Add-Vector -Vectors $vectors -Value 'tail_duplicate_replay'
            }
            else {
                Add-Vector -Vectors $vectors -Value 'mid_chain_duplicate_insert'
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
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'BLOCK') { $script:duplicate_replay_rejected_count++ }
    if (($vectors -contains 'canonical_record_reinsertion') -and $actual -eq 'BLOCK') { $script:canonical_reinsertion_rejected_count++ }
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'ALLOW') { $script:undetected_duplicate_replay_count++ }
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
$signatureToIndex = @{}
for ($i = 0; $i -lt $entries.Count; $i++) {
    $eid = [string]$entries[$i].entry_id
    $sig = Get-EntrySignature -Entry $entries[$i]
    [void]$trustedEntryIds.Add($eid)
    [void]$trustedEntrySigs.Add($sig)
    if (-not $signatureToIndex.ContainsKey($sig)) {
        $signatureToIndex[$sig] = $i
    }
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
    signature_to_index = $signatureToIndex
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

[void]$script:EntryReuseMap.Add('TRUSTED_CHAIN_LENGTH=' + $trusted.current_ledger_length)
[void]$script:EntryReuseMap.Add('TRUSTED_LATEST_ENTRY_ID=' + $trusted.current_latest_entry_id)
[void]$script:EntryReuseMap.Add('TRUSTED_LEDGER_HEAD_HASH=' + $trusted.current_ledger_head_hash)
[void]$script:EntryReuseMap.Add('ENTRY_UNIQUENESS_CONSTRAINT=entry_id_unique_and_slot_bound')
[void]$script:EntryReuseMap.Add('DETECTION_VECTOR_DUPLICATE_IDENTITY_REUSE=enabled')
[void]$script:EntryReuseMap.Add('DETECTION_VECTOR_CANONICAL_RECORD_REINSERTION=enabled')
[void]$script:EntryReuseMap.Add('DETECTION_VECTOR_SAME_ID_REPLAY_SAME_CONTENT=enabled')
[void]$script:EntryReuseMap.Add('DETECTION_VECTOR_SAME_ID_REPLAY_MODIFIED_CONTENT=enabled')
[void]$script:EntryReuseMap.Add('DETECTION_VECTOR_CROSS_ARTIFACT_MISMATCH=enabled')
[void]$script:EntryReuseMap.Add('DETECTION_VECTOR_CONTINUITY_BREAK=enabled')

# A) Tail duplicate replay block
$stateA = New-LiveState
$dupA = Clone-Entry -Entry $stateA.ledger.entries[3]
$stateA.ledger.entries = @($stateA.ledger.entries) + @($dupA)
$stateA.art111.ledger_length = $stateA.ledger.entries.Count
$stateA.art111.latest_entry_id = [string]$dupA.entry_id
$headA = Get-LedgerSnapshotHash -Ledger $stateA.ledger
$stateA.art111.ledger_head_hash = $headA
$stateA.art112.ledger_head_hash = $headA
$resultA = Invoke-GuardedCycle -State $stateA -Trusted $trusted
Add-CaseResult -Id 'A' -Name 'tail_duplicate_replay_block' -ExpectedResult 'BLOCK' -CycleResult $resultA

# B) Mid-chain duplicate insert
$stateB = New-LiveState
$dupB = Clone-Entry -Entry $stateB.ledger.entries[2]
$insertAtB = 8
$beforeB = @($stateB.ledger.entries[0..($insertAtB - 1)])
$afterB = @($stateB.ledger.entries[$insertAtB..($stateB.ledger.entries.Count - 1)])
$stateB.ledger.entries = $beforeB + @($dupB) + $afterB
$stateB.art111.ledger_length = $stateB.ledger.entries.Count
$stateB.art111.latest_entry_id = [string]$stateB.ledger.entries[-1].entry_id
$headB = Get-LedgerSnapshotHash -Ledger $stateB.ledger
$stateB.art111.ledger_head_hash = $headB
$stateB.art112.ledger_head_hash = $headB
$resultB = Invoke-GuardedCycle -State $stateB -Trusted $trusted
Add-CaseResult -Id 'B' -Name 'mid_chain_duplicate_insert' -ExpectedResult 'BLOCK' -CycleResult $resultB

# C) Same-ID replay with same content
$stateC = New-LiveState
$dupC = Clone-Entry -Entry $stateC.ledger.entries[1]
$stateC.ledger.entries = @($stateC.ledger.entries) + @($dupC)
$stateC.art111.ledger_length = $stateC.ledger.entries.Count
$stateC.art111.latest_entry_id = [string]$dupC.entry_id
$headC = Get-LedgerSnapshotHash -Ledger $stateC.ledger
$stateC.art111.ledger_head_hash = $headC
$stateC.art112.ledger_head_hash = $headC
$resultC = Invoke-GuardedCycle -State $stateC -Trusted $trusted
Add-CaseResult -Id 'C' -Name 'same_id_replay_same_content' -ExpectedResult 'BLOCK' -CycleResult $resultC

# D) Same-ID replay with modified content
$stateD = New-LiveState
$dupD = Clone-Entry -Entry $stateD.ledger.entries[1]
$dupD.fingerprint_hash = Get-StringHash -InputString ('MODIFIED_REPLAY|' + [string]$dupD.entry_id)
$dupD.previous_hash = Get-StringHash -InputString 'MODIFIED_PREVIOUS_HASH'
$stateD.ledger.entries = @($stateD.ledger.entries) + @($dupD)
$stateD.art111.ledger_length = $stateD.ledger.entries.Count
$stateD.art111.latest_entry_id = [string]$dupD.entry_id
$headD = Get-LedgerSnapshotHash -Ledger $stateD.ledger
$stateD.art111.ledger_head_hash = $headD
$stateD.art112.ledger_head_hash = $headD
$resultD = Invoke-GuardedCycle -State $stateD -Trusted $trusted
Add-CaseResult -Id 'D' -Name 'same_id_replay_modified_content' -ExpectedResult 'BLOCK' -CycleResult $resultD

# E) Self-consistent duplicate resealed state
$stateE = New-LiveState
$dupE = Clone-Entry -Entry $stateE.ledger.entries[4]
$insertAtE = 6
$beforeE = @($stateE.ledger.entries[0..($insertAtE - 1)])
$afterE = @($stateE.ledger.entries[$insertAtE..($stateE.ledger.entries.Count - 1)])
$stateE.ledger.entries = $beforeE + @($dupE) + $afterE
Reseal-Downstream -Entries $stateE.ledger.entries -StartIndex $insertAtE -Seed 'DUPLICATE_RESEAL'
$stateE.art111.ledger_length = $stateE.ledger.entries.Count
$stateE.art111.latest_entry_id = [string]$stateE.ledger.entries[-1].entry_id
$headE = Get-LedgerSnapshotHash -Ledger $stateE.ledger
$stateE.art111.ledger_head_hash = $headE
$stateE.art112.ledger_head_hash = $headE
$resultE = Invoke-GuardedCycle -State $stateE -Trusted $trusted
Add-CaseResult -Id 'E' -Name 'self_consistent_duplicate_resealed_state' -ExpectedResult 'BLOCK' -CycleResult $resultE

# F) Partial duplicate injection mismatch (ledger only)
$stateF = New-LiveState
$dupF = Clone-Entry -Entry $stateF.ledger.entries[3]
$stateF.ledger.entries = @($stateF.ledger.entries) + @($dupF)
# art111/art112 untouched intentionally
$resultF = Invoke-GuardedCycle -State $stateF -Trusted $trusted
Add-CaseResult -Id 'F' -Name 'partial_duplicate_injection_mismatch' -ExpectedResult 'BLOCK' -CycleResult $resultF

# G) Guarded-boundary duplicate swap
$stateG = New-LiveState
$resultG = Invoke-GuardedCycle -State $stateG -Trusted $trusted -RuntimeMutation {
    param([hashtable]$State, [hashtable]$Trusted)
    $dupG = Clone-Entry -Entry $State.ledger.entries[2]
    $State.ledger.entries = @($State.ledger.entries) + @($dupG)
    $State.art111.ledger_length = $State.ledger.entries.Count
    $State.art111.latest_entry_id = [string]$dupG.entry_id
}
Add-CaseResult -Id 'G' -Name 'guarded_boundary_duplicate_swap' -ExpectedResult 'BLOCK' -CycleResult $resultG

# H) Clean control
$stateH = New-LiveState
$resultH = Invoke-GuardedCycle -State $stateH -Trusted $trusted
Add-CaseResult -Id 'H' -Name 'clean_control' -ExpectedResult 'ALLOW' -CycleResult $resultH

$consistencyPass = $true
if ($script:CaseMatrix.Count -ne 8) { $consistencyPass = $false }
if (($script:passCount + $script:failCount) -ne 8) { $consistencyPass = $false }
if ($script:undetected_duplicate_replay_count -ne 0) { $consistencyPass = $false }
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

$replayMatrix = @(
    'DUPLICATE_REPLAY_MATRIX',
    'A: tail_duplicate_replay_block => expect BLOCK',
    'B: mid_chain_duplicate_insert => expect BLOCK',
    'C: same_id_replay_same_content => expect BLOCK',
    'D: same_id_replay_modified_content => expect BLOCK',
    'E: self_consistent_duplicate_resealed_state => expect BLOCK',
    'F: partial_duplicate_injection_mismatch => expect BLOCK',
    'G: guarded_boundary_duplicate_swap => expect BLOCK',
    'H: clean_control => expect ALLOW'
)

Write-ProofFile -Path (Join-Path $PF '01_status.txt') -Content @(
    'PHASE=53.18',
    'TITLE=' + $Title,
    'GATE=' + $gate,
    'PASS_COUNT=' + $script:passCount + '/8',
    'FAIL_COUNT=' + $script:failCount,
    'duplicate_replay_rejected_count=' + $script:duplicate_replay_rejected_count,
    'canonical_reinsertion_rejected_count=' + $script:canonical_reinsertion_rejected_count,
    'undetected_duplicate_replay_count=' + $script:undetected_duplicate_replay_count,
    'false_positive_count=' + $script:false_positive_count,
    'consistency_check=' + $(if ($consistencyPass) { 'PASS' } else { 'FAIL' }),
    'FAIL_CLOSED=TRUE',
    'NO_FALLBACK=TRUE',
    'NO_SILENT_ACCEPTANCE=TRUE'
)

Write-ProofFile -Path (Join-Path $PF '14_validation_results.txt') -Content $matrixLines
Write-ProofFile -Path (Join-Path $PF '15_duplicate_replay_matrix.txt') -Content $replayMatrix
Write-ProofFile -Path (Join-Path $PF '15_entry_uniqueness_reuse_map.txt') -Content $script:EntryReuseMap.ToArray()
Write-ProofFile -Path (Join-Path $PF '15_detection_vectors.txt') -Content $vectorLines

Write-ProofFile -Path (Join-Path $PF '98_gate_phase53_18.txt') -Content @(
    'GATE=' + $gate,
    'PASS_COUNT=' + $script:passCount + '/8',
    'FAIL_COUNT=' + $script:failCount,
    'duplicate_replay_rejected_count=' + $script:duplicate_replay_rejected_count,
    'canonical_reinsertion_rejected_count=' + $script:canonical_reinsertion_rejected_count,
    'undetected_duplicate_replay_count=' + $script:undetected_duplicate_replay_count,
    'false_positive_count=' + $script:false_positive_count
)

$zipPath = $PF + '.zip'
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path $PF -DestinationPath $zipPath -Force

Write-Output ('PF=' + $PF)
Write-Output ('ZIP=' + $zipPath)
Write-Output ('GATE=' + $gate)
