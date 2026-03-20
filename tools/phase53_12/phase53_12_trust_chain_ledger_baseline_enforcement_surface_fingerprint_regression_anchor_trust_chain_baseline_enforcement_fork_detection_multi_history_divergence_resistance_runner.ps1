#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Phase 53.12: Fork Detection + Multi-History Divergence Resistance

$Phase = '53.12'
$Title = 'Fork Detection and Multi-History Divergence Resistance'
$PF = Join-Path $PSScriptRoot '..\..\' '_proof' "phase53_12_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_enforcement_fork_detection_multi_history_divergence_resistance_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $PF -Force | Out-Null

$script:CaseMatrix = [System.Collections.Generic.List[object]]::new()
$script:DetectionVectors = [System.Collections.Generic.List[object]]::new()
$script:DivergencePointMap = [System.Collections.Generic.List[string]]::new()
$script:CanonicalLineageMap = [System.Collections.Generic.List[string]]::new()

$script:passCount = 0
$script:failCount = 0
$script:fork_detected_count = 0
$script:divergent_branch_rejected_count = 0
$script:undetected_fork_count = 0
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

function Get-EntryIdNumber {
    param([string]$EntryId)
    if ($EntryId -match '^GF-(\d+)$') { return [int]$Matches[1] }
    return -1
}

function Build-ChainSignature {
    param($Entries)
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in @($Entries)) {
        [void]$parts.Add(([string]$entry.entry_id + '|' + [string]$entry.previous_hash + '|' + [string]$entry.fingerprint_hash))
    }
    return (Get-StringHash -InputString ($parts -join ';'))
}

function Get-DivergencePoint {
    param(
        $CanonicalEntries,
        $CandidateEntries
    )

    $c = @($CanonicalEntries)
    $x = @($CandidateEntries)
    $max = [Math]::Min($c.Count, $x.Count)

    for ($i = 0; $i -lt $max; $i++) {
        $cid = [string]$c[$i].entry_id
        $xid = [string]$x[$i].entry_id
        $cfp = [string]$c[$i].fingerprint_hash
        $xfp = [string]$x[$i].fingerprint_hash
        if ($cid -ne $xid -or $cfp -ne $xfp) {
            return @{
                index = $i
                canonical_entry_id = $cid
                candidate_entry_id = $xid
                reason = 'entry_mismatch'
            }
        }
    }

    if ($c.Count -ne $x.Count) {
        return @{
            index = $max
            canonical_entry_id = if ($max -lt $c.Count) { [string]$c[$max].entry_id } else { 'END' }
            candidate_entry_id = if ($max -lt $x.Count) { [string]$x[$max].entry_id } else { 'END' }
            reason = 'length_mismatch'
        }
    }

    return @{
        index = -1
        canonical_entry_id = 'NONE'
        candidate_entry_id = 'NONE'
        reason = 'identical'
    }
}

function New-ForkedLedger {
    param(
        $CanonicalEntries,
        [int]$ForkIndex,
        [int]$TargetCount,
        [string]$Salt
    )

    $c = @($CanonicalEntries)
    $fork = [System.Collections.ArrayList]::new()

    for ($i = 0; $i -lt $ForkIndex; $i++) {
        [void]$fork.Add((Copy-Deep -Object $c[$i]))
    }

    while ($fork.Count -lt $TargetCount) {
        $idx = $fork.Count
        if ($idx -lt $c.Count) {
            $entryId = [string]$c[$idx].entry_id
            $timestamp = [string]$c[$idx].timestamp_utc
        } else {
            $entryId = 'GF-{0:D4}' -f ($idx + 1)
            $timestamp = (Get-Date).ToUniversalTime().ToString('o')
        }

        $prevHash = if ($fork.Count -gt 0) { [string]$fork[$fork.Count - 1].fingerprint_hash } else { $null }
        $payload = $Salt + '|' + $entryId + '|' + $idx + '|' + $prevHash
        $fp = Get-StringHash -InputString $payload

        $newEntry = @{
            entry_id = $entryId
            timestamp_utc = $timestamp
            phase_locked = '53.12-fork'
            artifact = 'fork_branch'
            fingerprint_hash = $fp
            previous_hash = $prevHash
        }
        [void]$fork.Add($newEntry)
    }

    return @{ entries = @($fork) }
}

function Build-ArtifactsFromLedger {
    param(
        $Ledger,
        $BaselineArt111,
        $BaselineArt112
    )

    $entries = @($Ledger.entries)
    $last = $entries[$entries.Count - 1]
    $head = [string]$last.fingerprint_hash
    $latest = [string]$last.entry_id
    $length = $entries.Count
    $snap = Get-LedgerSnapshotHash -Ledger $Ledger

    $art111 = Copy-Deep -Object $BaselineArt111
    $art111.latest_entry_id = $latest
    $art111.ledger_length = $length
    $art111.ledger_head_hash = $head

    $art112 = Copy-Deep -Object $BaselineArt112
    $art112.ledger_head_hash = $head
    $art112.baseline_snapshot_hash = $snap

    return @{
        art111 = $art111
        art112 = $art112
    }
}

function Test-EntryFormatAndMonotonicity {
    param($Entries)

    $seen = @{}
    for ($i = 0; $i -lt $Entries.Count; $i++) {
        $id = [string]$Entries[$i].entry_id
        $num = Get-EntryIdNumber -EntryId $id
        if ($num -lt 0) { return @{ ok = $false; reason = 'entry_id_format_invalid' } }
        if ($seen.ContainsKey($id)) { return @{ ok = $false; reason = 'entry_id_duplicate' } }
        $seen[$id] = $true

        if ($i -gt 0) {
            $prevNum = Get-EntryIdNumber -EntryId ([string]$Entries[$i - 1].entry_id)
            if ($num -le $prevNum) { return @{ ok = $false; reason = 'entry_id_non_monotonic' } }
            if ($num -ne ($prevNum + 1)) { return @{ ok = $false; reason = 'entry_id_gap_or_reuse' } }
        }
    }

    return @{ ok = $true; reason = 'ok' }
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

    $order = Test-EntryFormatAndMonotonicity -Entries $entries
    if (-not $order.ok) { [void]$vectors.Add($order.reason) }

    $ledgerLen = $entries.Count
    $latest = [string]$entries[$entries.Count - 1].entry_id
    $latestNum = Get-EntryIdNumber -EntryId $latest
    $head = [string]$entries[$entries.Count - 1].fingerprint_hash
    $ledgerHash = Get-LedgerSnapshotHash -Ledger $State.ledger
    $chainSig = Build-ChainSignature -Entries $entries

    $a111Latest = [string]$State.art111.latest_entry_id
    $a111Len = [int]$State.art111.ledger_length
    $a111Head = [string]$State.art111.ledger_head_hash

    $a112Head = [string]$State.art112.ledger_head_hash
    $a112Snap = [string]$State.art112.baseline_snapshot_hash

    # Cross-artifact consistency.
    if ($a111Len -ne $ledgerLen) { [void]$vectors.Add('ledger_length_mismatch') }
    if ($a111Latest -ne $latest) { [void]$vectors.Add('latest_entry_id_mismatch') }
    if ($a111Head -ne $a112Head) { [void]$vectors.Add('head_hash_cross_artifact_mismatch') }

    # Canonical lineage anchors.
    if ($chainSig -ne $Trusted.current_chain_signature) { [void]$vectors.Add('chain_signature_divergence') }
    if ($ledgerHash -ne $Trusted.current_ledger_snapshot_hash) { [void]$vectors.Add('ledger_snapshot_divergence') }
    if ($a111Head -ne $Trusted.current_art111_head_hash_anchor) { [void]$vectors.Add('art111_head_anchor_mismatch') }
    if ($a112Head -ne $Trusted.current_art112_head_hash_anchor) { [void]$vectors.Add('art112_head_anchor_mismatch') }

    # Same-height divergence detection.
    if ($ledgerLen -eq $Trusted.current_ledger_length -and $latest -eq $Trusted.current_latest_entry_id -and $chainSig -ne $Trusted.current_chain_signature) {
        [void]$vectors.Add('same_height_divergence_detected')
    }

    # Different-height fork detection (do not trust length alone).
    if ($ledgerLen -gt $Trusted.current_ledger_length -and $chainSig -ne $Trusted.current_chain_signature) {
        [void]$vectors.Add('non_canonical_longer_branch_detected')
    }

    # Canonical lineage mismatch marker.
    if ($chainSig -ne $Trusted.current_chain_signature) {
        [void]$vectors.Add('canonical_lineage_mismatch')
    }

    if ($latestNum -lt 0) {
        [void]$vectors.Add('latest_entry_id_invalid')
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
        return @{
            blocked = $true
            runtime_executed = $false
            stage = 'pre_runtime'
            vectors = $pre
            reason = ($pre -join ';')
        }
    }

    if ($RuntimeMutation) {
        & $RuntimeMutation -State $State -Trusted $Trusted
    }

    $boundary = Get-ValidationVectors -State $State -Trusted $Trusted
    if ($boundary.Count -gt 0) {
        return @{
            blocked = $true
            runtime_executed = $true
            stage = 'guarded_boundary'
            vectors = $boundary
            reason = ($boundary -join ';')
        }
    }

    return @{
        blocked = $false
        runtime_executed = $true
        stage = 'allow'
        vectors = [System.Collections.Generic.List[string]]::new()
        reason = 'canonical_branch_allow'
    }
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
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'BLOCK') { $script:fork_detected_count++ }
    if (($vectors -contains 'canonical_lineage_mismatch' -or $vectors -contains 'chain_signature_divergence') -and $actual -eq 'BLOCK') { $script:divergent_branch_rejected_count++ }
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'ALLOW') { $script:undetected_fork_count++ }
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

$canonicalEntries = @($baselineLedger.entries)
$currentLength = $canonicalEntries.Count
$currentLatest = [string]$canonicalEntries[$currentLength - 1].entry_id
$currentLedgerHash = Get-LedgerSnapshotHash -Ledger $baselineLedger
$currentChainSig = Build-ChainSignature -Entries $canonicalEntries

$trusted = @{
    current_ledger_snapshot_hash = $currentLedgerHash
    current_chain_signature = $currentChainSig
    current_ledger_length = $currentLength
    current_latest_entry_id = $currentLatest
    current_art111_head_hash_anchor = [string]$baselineArt111.ledger_head_hash
    current_art112_head_hash_anchor = [string]$baselineArt112.ledger_head_hash
}

function New-LiveState {
    return @{
        ledger = Copy-Deep -Object $baselineLedger
        art111 = Copy-Deep -Object $baselineArt111
        art112 = Copy-Deep -Object $baselineArt112
    }
}

# Build alternate branches from common fork point.
$forkPoint = [Math]::Max(3, $currentLength - 4)
$branchSameHeight = New-ForkedLedger -CanonicalEntries $canonicalEntries -ForkIndex $forkPoint -TargetCount $currentLength -Salt 'branch_same_height'
$branchLonger = New-ForkedLedger -CanonicalEntries $canonicalEntries -ForkIndex $forkPoint -TargetCount ($currentLength + 2) -Salt 'branch_longer'
$branchHashConsistent = New-ForkedLedger -CanonicalEntries $canonicalEntries -ForkIndex $forkPoint -TargetCount $currentLength -Salt 'branch_hash_consistent'

$branchSameMeta = Build-ArtifactsFromLedger -Ledger $branchSameHeight -BaselineArt111 $baselineArt111 -BaselineArt112 $baselineArt112
$branchLongMeta = Build-ArtifactsFromLedger -Ledger $branchLonger -BaselineArt111 $baselineArt111 -BaselineArt112 $baselineArt112
$branchHashMeta = Build-ArtifactsFromLedger -Ledger $branchHashConsistent -BaselineArt111 $baselineArt111 -BaselineArt112 $baselineArt112

$dpSame = Get-DivergencePoint -CanonicalEntries $canonicalEntries -CandidateEntries $branchSameHeight.entries
$dpLong = Get-DivergencePoint -CanonicalEntries $canonicalEntries -CandidateEntries $branchLonger.entries
$dpHash = Get-DivergencePoint -CanonicalEntries $canonicalEntries -CandidateEntries $branchHashConsistent.entries

[void]$script:DivergencePointMap.Add('branch_same_height: index=' + $dpSame.index + ';canonical=' + $dpSame.canonical_entry_id + ';candidate=' + $dpSame.candidate_entry_id + ';reason=' + $dpSame.reason)
[void]$script:DivergencePointMap.Add('branch_longer: index=' + $dpLong.index + ';canonical=' + $dpLong.canonical_entry_id + ';candidate=' + $dpLong.candidate_entry_id + ';reason=' + $dpLong.reason)
[void]$script:DivergencePointMap.Add('branch_hash_consistent: index=' + $dpHash.index + ';canonical=' + $dpHash.canonical_entry_id + ';candidate=' + $dpHash.candidate_entry_id + ';reason=' + $dpHash.reason)

[void]$script:CanonicalLineageMap.Add('canonical_chain_signature=' + $trusted.current_chain_signature)
[void]$script:CanonicalLineageMap.Add('canonical_head_art111=' + $trusted.current_art111_head_hash_anchor)
[void]$script:CanonicalLineageMap.Add('canonical_head_art112=' + $trusted.current_art112_head_hash_anchor)
[void]$script:CanonicalLineageMap.Add('canonical_length=' + $trusted.current_ledger_length)
[void]$script:CanonicalLineageMap.Add('canonical_latest=' + $trusted.current_latest_entry_id)
[void]$script:CanonicalLineageMap.Add('branch_same_height_signature=' + (Build-ChainSignature -Entries $branchSameHeight.entries))
[void]$script:CanonicalLineageMap.Add('branch_longer_signature=' + (Build-ChainSignature -Entries $branchLonger.entries))
[void]$script:CanonicalLineageMap.Add('branch_hash_consistent_signature=' + (Build-ChainSignature -Entries $branchHashConsistent.entries))

# A) Forked ledger block: alternate branch artifacts.
$stateA = New-LiveState
$stateA.ledger = Copy-Deep -Object $branchSameHeight
$stateA.art111 = Copy-Deep -Object $branchSameMeta.art111
$stateA.art112 = Copy-Deep -Object $branchSameMeta.art112
$resultA = Invoke-GuardedCycle -State $stateA -Trusted $trusted
Add-CaseResult -Id 'A' -Name 'forked_ledger_block' -ExpectedResult 'BLOCK' -CycleResult $resultA

# B) Same-height divergence.
$stateB = New-LiveState
$stateB.ledger = Copy-Deep -Object $branchHashConsistent
$stateB.art111 = Copy-Deep -Object $branchHashMeta.art111
$stateB.art112 = Copy-Deep -Object $branchHashMeta.art112
$resultB = Invoke-GuardedCycle -State $stateB -Trusted $trusted
Add-CaseResult -Id 'B' -Name 'same_height_divergence' -ExpectedResult 'BLOCK' -CycleResult $resultB

# C) Different-height fork (longer non-canonical).
$stateC = New-LiveState
$stateC.ledger = Copy-Deep -Object $branchLonger
$stateC.art111 = Copy-Deep -Object $branchLongMeta.art111
$stateC.art112 = Copy-Deep -Object $branchLongMeta.art112
$resultC = Invoke-GuardedCycle -State $stateC -Trusted $trusted
Add-CaseResult -Id 'C' -Name 'different_height_fork_non_canonical_longer' -ExpectedResult 'BLOCK' -CycleResult $resultC

# D) Hash-consistent alternate history.
$stateD = New-LiveState
$stateD.ledger = Copy-Deep -Object $branchHashConsistent
$stateD.art111 = Copy-Deep -Object $branchHashMeta.art111
$stateD.art112 = Copy-Deep -Object $branchHashMeta.art112
$resultD = Invoke-GuardedCycle -State $stateD -Trusted $trusted
Add-CaseResult -Id 'D' -Name 'hash_consistent_alt_history' -ExpectedResult 'BLOCK' -CycleResult $resultD

# E) Mixed-fork artifacts: ledger branch A with canonical metadata.
$stateE = New-LiveState
$stateE.ledger = Copy-Deep -Object $branchSameHeight
$resultE = Invoke-GuardedCycle -State $stateE -Trusted $trusted
Add-CaseResult -Id 'E' -Name 'mixed_fork_artifacts_ledger_alt_metadata_canonical' -ExpectedResult 'BLOCK' -CycleResult $resultE

# F) Guarded-boundary fork swap.
$stateF = New-LiveState
$resultF = Invoke-GuardedCycle -State $stateF -Trusted $trusted -RuntimeMutation {
    param([hashtable]$State, [hashtable]$Trusted)
    $State.ledger = Copy-Deep -Object $branchLonger
    $State.art111 = Copy-Deep -Object $branchLongMeta.art111
    $State.art112 = Copy-Deep -Object $branchLongMeta.art112
}
Add-CaseResult -Id 'F' -Name 'guarded_boundary_fork_swap' -ExpectedResult 'BLOCK' -CycleResult $resultF

# G) Canonical branch control.
$stateG = New-LiveState
$resultG = Invoke-GuardedCycle -State $stateG -Trusted $trusted
Add-CaseResult -Id 'G' -Name 'canonical_branch_control' -ExpectedResult 'ALLOW' -CycleResult $resultG

# H) Mixed-fork artifacts inverse: canonical ledger with branch metadata.
$stateH = New-LiveState
$stateH.art111 = Copy-Deep -Object $branchSameMeta.art111
$stateH.art112 = Copy-Deep -Object $branchSameMeta.art112
$resultH = Invoke-GuardedCycle -State $stateH -Trusted $trusted
Add-CaseResult -Id 'H' -Name 'mixed_fork_artifacts_metadata_alt_ledger_canonical' -ExpectedResult 'BLOCK' -CycleResult $resultH

$consistencyPass = $true
if ($script:CaseMatrix.Count -ne 8) { $consistencyPass = $false }
if (($script:passCount + $script:failCount) -ne 8) { $consistencyPass = $false }
if ($script:undetected_fork_count -ne 0) { $consistencyPass = $false }
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
    'FORK_TEST_MATRIX',
    'A: forked_ledger_block => expect BLOCK',
    'B: same_height_divergence => expect BLOCK',
    'C: different_height_fork_non_canonical_longer => expect BLOCK',
    'D: hash_consistent_alt_history => expect BLOCK',
    'E: mixed_fork_artifacts_ledger_alt_metadata_canonical => expect BLOCK',
    'F: guarded_boundary_fork_swap => expect BLOCK',
    'G: canonical_branch_control => expect ALLOW',
    'H: mixed_fork_artifacts_metadata_alt_ledger_canonical => expect BLOCK'
)

Write-ProofFile -Path (Join-Path $PF '01_status.txt') -Content @(
    'PHASE=53.12',
    'TITLE=' + $Title,
    'GATE=' + $gate,
    'PASS_COUNT=' + $script:passCount + '/8',
    'FAIL_COUNT=' + $script:failCount,
    'fork_detected_count=' + $script:fork_detected_count,
    'divergent_branch_rejected_count=' + $script:divergent_branch_rejected_count,
    'undetected_fork_count=' + $script:undetected_fork_count,
    'false_positive_count=' + $script:false_positive_count,
    'consistency_check=' + $(if ($consistencyPass) { 'PASS' } else { 'FAIL' }),
    'FAIL_CLOSED=TRUE',
    'NO_FALLBACK=TRUE',
    'NO_SILENT_ACCEPTANCE=TRUE'
)

Write-ProofFile -Path (Join-Path $PF '14_validation_results.txt') -Content $matrixLines
Write-ProofFile -Path (Join-Path $PF '15_fork_test_matrix.txt') -Content $testMatrix
Write-ProofFile -Path (Join-Path $PF '15_detection_vectors.txt') -Content $vectorLines
Write-ProofFile -Path (Join-Path $PF '15_divergence_point_map.txt') -Content $script:DivergencePointMap.ToArray()
Write-ProofFile -Path (Join-Path $PF '15_canonical_lineage_map.txt') -Content $script:CanonicalLineageMap.ToArray()

Write-ProofFile -Path (Join-Path $PF '98_gate_phase53_12.txt') -Content @(
    'GATE=' + $gate,
    'PASS_COUNT=' + $script:passCount + '/8',
    'FAIL_COUNT=' + $script:failCount,
    'fork_detected_count=' + $script:fork_detected_count,
    'divergent_branch_rejected_count=' + $script:divergent_branch_rejected_count,
    'undetected_fork_count=' + $script:undetected_fork_count,
    'false_positive_count=' + $script:false_positive_count
)

$zipPath = $PF + '.zip'
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path $PF -DestinationPath $zipPath -Force

Write-Output ('PF=' + $PF)
Write-Output ('ZIP=' + $zipPath)
Write-Output ('GATE=' + $gate)
