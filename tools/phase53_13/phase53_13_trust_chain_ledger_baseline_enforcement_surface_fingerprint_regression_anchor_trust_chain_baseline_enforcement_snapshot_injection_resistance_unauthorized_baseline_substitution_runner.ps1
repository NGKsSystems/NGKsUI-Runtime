#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Phase 53.13: Snapshot Injection Resistance + Unauthorized Baseline Substitution

$Phase = '53.13'
$Title = 'Snapshot Injection Resistance and Unauthorized Baseline Substitution'
$PF = Join-Path $PSScriptRoot '..\..\' '_proof' "phase53_13_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_enforcement_snapshot_injection_resistance_unauthorized_baseline_substitution_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $PF -Force | Out-Null

$script:CaseMatrix = [System.Collections.Generic.List[object]]::new()
$script:DetectionVectors = [System.Collections.Generic.List[object]]::new()
$script:ProvenanceIdentityMap = [System.Collections.Generic.List[string]]::new()

$script:passCount = 0
$script:failCount = 0
$script:injected_snapshot_rejected_count = 0
$script:unauthorized_baseline_substitution_count = 0
$script:undetected_injection_count = 0
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

function Get-EntryIdNumber {
    param([string]$EntryId)
    if ($EntryId -match '^GF-(\d+)$') { return [int]$Matches[1] }
    return -1
}

function New-InjectedLedger {
    param(
        $CanonicalEntries,
        [int]$ForkIndex,
        [int]$TargetCount,
        [string]$Salt
    )

    $c = @($CanonicalEntries)
    $out = [System.Collections.ArrayList]::new()

    for ($i = 0; $i -lt $ForkIndex; $i++) {
        [void]$out.Add((Copy-Deep -Object $c[$i]))
    }

    while ($out.Count -lt $TargetCount) {
        $idx = $out.Count
        if ($idx -lt $c.Count) {
            $entryId = [string]$c[$idx].entry_id
            $timestamp = [string]$c[$idx].timestamp_utc
        } else {
            $entryId = 'GF-{0:D4}' -f ($idx + 1)
            $timestamp = (Get-Date).ToUniversalTime().ToString('o')
        }

        $prevHash = if ($out.Count -gt 0) { [string]$out[$out.Count - 1].fingerprint_hash } else { $null }
        $fp = Get-StringHash -InputString ($Salt + '|' + $entryId + '|' + $idx + '|' + $prevHash)

        $newEntry = @{
            entry_id = $entryId
            timestamp_utc = $timestamp
            phase_locked = '53.13-injected'
            artifact = 'injected_snapshot'
            fingerprint_hash = $fp
            previous_hash = $prevHash
        }
        [void]$out.Add($newEntry)
    }

    return @{ entries = @($out) }
}

function Build-ArtifactsFromLedger {
    param(
        $Ledger,
        $BaseArt111,
        $BaseArt112,
        [string]$PhaseLocked
    )

    $entries = @($Ledger.entries)
    $head = [string]$entries[$entries.Count - 1].fingerprint_hash
    $latest = [string]$entries[$entries.Count - 1].entry_id
    $len = $entries.Count
    $snap = Get-LedgerSnapshotHash -Ledger $Ledger

    $art111 = Copy-Deep -Object $BaseArt111
    $art111.latest_entry_id = $latest
    $art111.ledger_length = $len
    $art111.ledger_head_hash = $head
    $art111.phase_locked = $PhaseLocked

    $art112 = Copy-Deep -Object $BaseArt112
    $art112.ledger_head_hash = $head
    $art112.baseline_snapshot_hash = $snap
    $art112.phase_locked = $PhaseLocked

    return @{ art111 = $art111; art112 = $art112 }
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
    $ledgerHead = [string]$entries[$entries.Count - 1].fingerprint_hash
    $ledgerHash = Get-LedgerSnapshotHash -Ledger $State.ledger
    $chainSig = Build-ChainSignature -Entries $entries

    $a111Len = [int]$State.art111.ledger_length
    $a111Latest = [string]$State.art111.latest_entry_id
    $a111Head = [string]$State.art111.ledger_head_hash
    $a111Phase = [string]$State.art111.phase_locked

    $a112Head = [string]$State.art112.ledger_head_hash
    $a112Snap = [string]$State.art112.baseline_snapshot_hash
    $a112Phase = [string]$State.art112.phase_locked

    # Cross-artifact mismatch vectors.
    if ($a111Len -ne $ledgerLen) { [void]$vectors.Add('cross_artifact_length_mismatch') }
    if ($a111Latest -ne $ledgerLatest) { [void]$vectors.Add('cross_artifact_latest_id_mismatch') }
    if ($a111Head -ne $a112Head) { [void]$vectors.Add('cross_artifact_head_mismatch') }

    # Identity mismatch vectors.
    if ($ledgerHash -ne $Trusted.current_ledger_snapshot_hash) { [void]$vectors.Add('identity_mismatch_ledger_snapshot') }
    if ($chainSig -ne $Trusted.current_chain_signature) { [void]$vectors.Add('lineage_mismatch_chain_signature') }
    if ($a111Head -ne $Trusted.current_art111_head_hash_anchor) { [void]$vectors.Add('identity_mismatch_art111_head_anchor') }
    if ($a112Head -ne $Trusted.current_art112_head_hash_anchor) { [void]$vectors.Add('identity_mismatch_art112_head_anchor') }

    # Provenance mismatch vectors.
    if ($a111Phase -ne $Trusted.current_art111_phase_locked) { [void]$vectors.Add('provenance_mismatch_art111_phase') }
    if ($a112Phase -ne $Trusted.current_art112_phase_locked) { [void]$vectors.Add('provenance_mismatch_art112_phase') }

    # Same-shape attack marker: same shape fields, different lineage/content.
    $sameShape = ($a111Len -eq $Trusted.current_ledger_length) -and ($a111Latest -eq $Trusted.current_latest_entry_id)
    $differentContent = ($ledgerHash -ne $Trusted.current_ledger_snapshot_hash) -or ($chainSig -ne $Trusted.current_chain_signature)
    if ($sameShape -and $differentContent) {
        [void]$vectors.Add('same_shape_attack_detected')
    }

    if ((Get-EntryIdNumber -EntryId $ledgerLatest) -lt 0) {
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
        return @{ blocked = $true; runtime_executed = $false; stage = 'pre_runtime'; vectors = $pre; reason = ($pre -join ';') }
    }

    if ($RuntimeMutation) {
        & $RuntimeMutation -State $State -Trusted $Trusted
    }

    $boundary = Get-ValidationVectors -State $State -Trusted $Trusted
    if ($boundary.Count -gt 0) {
        return @{ blocked = $true; runtime_executed = $true; stage = 'guarded_boundary'; vectors = $boundary; reason = ($boundary -join ';') }
    }

    return @{ blocked = $false; runtime_executed = $true; stage = 'allow'; vectors = [System.Collections.Generic.List[string]]::new(); reason = 'authorized_baseline_allow' }
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
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'BLOCK') { $script:injected_snapshot_rejected_count++ }
    if (($vectors -contains 'provenance_mismatch_art111_phase' -or $vectors -contains 'provenance_mismatch_art112_phase' -or $vectors -contains 'identity_mismatch_ledger_snapshot') -and $actual -eq 'BLOCK') {
        $script:unauthorized_baseline_substitution_count++
    }
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'ALLOW') { $script:undetected_injection_count++ }
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
$trusted = @{
    current_ledger_snapshot_hash = Get-LedgerSnapshotHash -Ledger $baselineLedger
    current_chain_signature = Build-ChainSignature -Entries $canonicalEntries
    current_ledger_length = $canonicalEntries.Count
    current_latest_entry_id = [string]$canonicalEntries[$canonicalEntries.Count - 1].entry_id
    current_art111_head_hash_anchor = [string]$baselineArt111.ledger_head_hash
    current_art112_head_hash_anchor = [string]$baselineArt112.ledger_head_hash
    current_art111_phase_locked = [string]$baselineArt111.phase_locked
    current_art112_phase_locked = [string]$baselineArt112.phase_locked
}

function New-LiveState {
    return @{ ledger = Copy-Deep -Object $baselineLedger; art111 = Copy-Deep -Object $baselineArt111; art112 = Copy-Deep -Object $baselineArt112 }
}

# Build injected sets.
$forkIndex = [Math]::Max(3, $canonicalEntries.Count - 4)
$foreignLedger = New-InjectedLedger -CanonicalEntries $canonicalEntries -ForkIndex $forkIndex -TargetCount $canonicalEntries.Count -Salt 'foreign_source'
$foreignMeta = Build-ArtifactsFromLedger -Ledger $foreignLedger -BaseArt111 $baselineArt111 -BaseArt112 $baselineArt112 -PhaseLocked 'FOREIGN.99'

$selfConsistentLedger = New-InjectedLedger -CanonicalEntries $canonicalEntries -ForkIndex $forkIndex -TargetCount $canonicalEntries.Count -Salt 'self_consistent_sub'
$selfConsistentMeta = Build-ArtifactsFromLedger -Ledger $selfConsistentLedger -BaseArt111 $baselineArt111 -BaseArt112 $baselineArt112 -PhaseLocked 'INJECTED.88'

$sameShapeLedger = New-InjectedLedger -CanonicalEntries $canonicalEntries -ForkIndex $forkIndex -TargetCount $canonicalEntries.Count -Salt 'same_shape_payload'
$sameShapeMeta = Build-ArtifactsFromLedger -Ledger $sameShapeLedger -BaseArt111 $baselineArt111 -BaseArt112 $baselineArt112 -PhaseLocked ([string]$baselineArt111.phase_locked)
# Force same visible shape fields as current.
$sameShapeMeta.art111.ledger_length = $trusted.current_ledger_length
$sameShapeMeta.art111.latest_entry_id = $trusted.current_latest_entry_id
$sameShapeMeta.art112.phase_locked = [string]$baselineArt112.phase_locked

[void]$script:ProvenanceIdentityMap.Add('AUTHORIZED: ledger_snapshot_hash=' + $trusted.current_ledger_snapshot_hash)
[void]$script:ProvenanceIdentityMap.Add('AUTHORIZED: chain_signature=' + $trusted.current_chain_signature)
[void]$script:ProvenanceIdentityMap.Add('AUTHORIZED: art111_phase_locked=' + $trusted.current_art111_phase_locked)
[void]$script:ProvenanceIdentityMap.Add('AUTHORIZED: art112_phase_locked=' + $trusted.current_art112_phase_locked)
[void]$script:ProvenanceIdentityMap.Add('INJECTED_FOREIGN: ledger_snapshot_hash=' + (Get-LedgerSnapshotHash -Ledger $foreignLedger))
[void]$script:ProvenanceIdentityMap.Add('INJECTED_SELF_CONSISTENT: ledger_snapshot_hash=' + (Get-LedgerSnapshotHash -Ledger $selfConsistentLedger))
[void]$script:ProvenanceIdentityMap.Add('INJECTED_SAME_SHAPE: ledger_snapshot_hash=' + (Get-LedgerSnapshotHash -Ledger $sameShapeLedger))

# A) Foreign snapshot block.
$stateA = New-LiveState
$stateA.ledger = Copy-Deep -Object $foreignLedger
$stateA.art111 = Copy-Deep -Object $foreignMeta.art111
$stateA.art112 = Copy-Deep -Object $foreignMeta.art112
$resultA = Invoke-GuardedCycle -State $stateA -Trusted $trusted
Add-CaseResult -Id 'A' -Name 'foreign_snapshot_block' -ExpectedResult 'BLOCK' -CycleResult $resultA

# B) Self-consistent snapshot substitution.
$stateB = New-LiveState
$stateB.ledger = Copy-Deep -Object $selfConsistentLedger
$stateB.art111 = Copy-Deep -Object $selfConsistentMeta.art111
$stateB.art112 = Copy-Deep -Object $selfConsistentMeta.art112
$resultB = Invoke-GuardedCycle -State $stateB -Trusted $trusted
Add-CaseResult -Id 'B' -Name 'self_consistent_snapshot_substitution' -ExpectedResult 'BLOCK' -CycleResult $resultB

# C) Partial snapshot injection: ledger only.
$stateC = New-LiveState
$stateC.ledger = Copy-Deep -Object $foreignLedger
$resultC = Invoke-GuardedCycle -State $stateC -Trusted $trusted
Add-CaseResult -Id 'C' -Name 'partial_snapshot_injection_ledger_only' -ExpectedResult 'BLOCK' -CycleResult $resultC

# D) Partial snapshot injection: art111 only.
$stateD = New-LiveState
$stateD.art111 = Copy-Deep -Object $foreignMeta.art111
$resultD = Invoke-GuardedCycle -State $stateD -Trusted $trusted
Add-CaseResult -Id 'D' -Name 'partial_snapshot_injection_art111_only' -ExpectedResult 'BLOCK' -CycleResult $resultD

# E) Partial snapshot injection: art112 only.
$stateE = New-LiveState
$stateE.art112 = Copy-Deep -Object $foreignMeta.art112
$resultE = Invoke-GuardedCycle -State $stateE -Trusted $trusted
Add-CaseResult -Id 'E' -Name 'partial_snapshot_injection_art112_only' -ExpectedResult 'BLOCK' -CycleResult $resultE

# F) Same-shape attack.
$stateF = New-LiveState
$stateF.ledger = Copy-Deep -Object $sameShapeLedger
$stateF.art111 = Copy-Deep -Object $sameShapeMeta.art111
$stateF.art112 = Copy-Deep -Object $sameShapeMeta.art112
$resultF = Invoke-GuardedCycle -State $stateF -Trusted $trusted
Add-CaseResult -Id 'F' -Name 'same_shape_attack' -ExpectedResult 'BLOCK' -CycleResult $resultF

# G) Guarded-boundary snapshot swap.
$stateG = New-LiveState
$resultG = Invoke-GuardedCycle -State $stateG -Trusted $trusted -RuntimeMutation {
    param([hashtable]$State, [hashtable]$Trusted)
    $State.ledger = Copy-Deep -Object $selfConsistentLedger
    $State.art111 = Copy-Deep -Object $selfConsistentMeta.art111
    $State.art112 = Copy-Deep -Object $selfConsistentMeta.art112
}
Add-CaseResult -Id 'G' -Name 'guarded_boundary_snapshot_swap' -ExpectedResult 'BLOCK' -CycleResult $resultG

# H) Clean control.
$stateH = New-LiveState
$resultH = Invoke-GuardedCycle -State $stateH -Trusted $trusted
Add-CaseResult -Id 'H' -Name 'clean_control' -ExpectedResult 'ALLOW' -CycleResult $resultH

$consistencyPass = $true
if ($script:CaseMatrix.Count -ne 8) { $consistencyPass = $false }
if (($script:passCount + $script:failCount) -ne 8) { $consistencyPass = $false }
if ($script:undetected_injection_count -ne 0) { $consistencyPass = $false }
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
    'SNAPSHOT_INJECTION_MATRIX',
    'A: foreign_snapshot_block => expect BLOCK',
    'B: self_consistent_snapshot_substitution => expect BLOCK',
    'C: partial_snapshot_injection_ledger_only => expect BLOCK',
    'D: partial_snapshot_injection_art111_only => expect BLOCK',
    'E: partial_snapshot_injection_art112_only => expect BLOCK',
    'F: same_shape_attack => expect BLOCK',
    'G: guarded_boundary_snapshot_swap => expect BLOCK',
    'H: clean_control => expect ALLOW'
)

Write-ProofFile -Path (Join-Path $PF '01_status.txt') -Content @(
    'PHASE=53.13',
    'TITLE=' + $Title,
    'GATE=' + $gate,
    'PASS_COUNT=' + $script:passCount + '/8',
    'FAIL_COUNT=' + $script:failCount,
    'injected_snapshot_rejected_count=' + $script:injected_snapshot_rejected_count,
    'unauthorized_baseline_substitution_count=' + $script:unauthorized_baseline_substitution_count,
    'undetected_injection_count=' + $script:undetected_injection_count,
    'false_positive_count=' + $script:false_positive_count,
    'consistency_check=' + $(if ($consistencyPass) { 'PASS' } else { 'FAIL' }),
    'FAIL_CLOSED=TRUE',
    'NO_FALLBACK=TRUE',
    'NO_SILENT_ACCEPTANCE=TRUE'
)

Write-ProofFile -Path (Join-Path $PF '14_validation_results.txt') -Content $matrixLines
Write-ProofFile -Path (Join-Path $PF '15_snapshot_injection_matrix.txt') -Content $testMatrix
Write-ProofFile -Path (Join-Path $PF '15_provenance_identity_map.txt') -Content $script:ProvenanceIdentityMap.ToArray()
Write-ProofFile -Path (Join-Path $PF '15_detection_vectors.txt') -Content $vectorLines

Write-ProofFile -Path (Join-Path $PF '98_gate_phase53_13.txt') -Content @(
    'GATE=' + $gate,
    'PASS_COUNT=' + $script:passCount + '/8',
    'FAIL_COUNT=' + $script:failCount,
    'injected_snapshot_rejected_count=' + $script:injected_snapshot_rejected_count,
    'unauthorized_baseline_substitution_count=' + $script:unauthorized_baseline_substitution_count,
    'undetected_injection_count=' + $script:undetected_injection_count,
    'false_positive_count=' + $script:false_positive_count
)

$zipPath = $PF + '.zip'
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path $PF -DestinationPath $zipPath -Force

Write-Output ('PF=' + $PF)
Write-Output ('ZIP=' + $zipPath)
Write-Output ('GATE=' + $gate)
