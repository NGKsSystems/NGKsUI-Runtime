#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Phase 53.11: Rollback Attack Resistance + Stale Snapshot Rejection
# Objective: block rollback and stale snapshot states before init or at guarded boundary.

$Phase = '53.11'
$Title = 'Rollback Attack Resistance and Stale Snapshot Rejection'
$PF = Join-Path $PSScriptRoot '..\..\' '_proof' "phase53_11_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_enforcement_rollback_attack_resistance_stale_snapshot_rejection_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $PF -Force | Out-Null

$script:CaseMatrix = [System.Collections.Generic.List[object]]::new()
$script:DetectionVectors = [System.Collections.Generic.List[object]]::new()
$script:staleCurrentMap = [System.Collections.Generic.List[string]]::new()
$script:passCount = 0
$script:failCount = 0
$script:rollback_detected_count = 0
$script:stale_snapshot_rejected_count = 0
$script:undetected_rollback_count = 0
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

function Get-HeadHash {
    param($Ledger)
    $entries = @($Ledger.entries)
    if ($entries.Count -eq 0) { return '' }
    return [string]$entries[$entries.Count - 1].fingerprint_hash
}

function Build-ChainSignature {
    param($Entries)
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in @($Entries)) {
        [void]$parts.Add(([string]$entry.entry_id + '|' + [string]$entry.previous_hash + '|' + [string]$entry.fingerprint_hash))
    }
    return (Get-StringHash -InputString ($parts -join ';'))
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

    $ledgerLength = $entries.Count
    $ledgerLatest = [string]$entries[$entries.Count - 1].entry_id
    $ledgerLatestNum = Get-EntryIdNumber -EntryId $ledgerLatest
    $ledgerHead = Get-HeadHash -Ledger $State.ledger
    $ledgerHash = Get-LedgerSnapshotHash -Ledger $State.ledger

    $art111Latest = [string]$State.art111.latest_entry_id
    $art111LatestNum = Get-EntryIdNumber -EntryId $art111Latest
    $art111Length = [int]$State.art111.ledger_length
    $art111Head = [string]$State.art111.ledger_head_hash

    $art112Head = [string]$State.art112.ledger_head_hash
    $art112Baseline = [string]$State.art112.baseline_snapshot_hash

    # Cross-artifact consistency checks.
    if ($art111Length -ne $ledgerLength) { [void]$vectors.Add('ledger_length_mismatch') }
    if ($art111Latest -ne $ledgerLatest) { [void]$vectors.Add('latest_entry_id_mismatch') }
    if ($art111Head -ne $art112Head) { [void]$vectors.Add('head_hash_cross_artifact_mismatch') }
    if ($art111Head -ne $Trusted.current_art111_head_hash_anchor) { [void]$vectors.Add('art111_head_hash_mismatch_current_anchor') }
    if ($art112Head -ne $Trusted.current_art112_head_hash_anchor) { [void]$vectors.Add('art112_head_hash_mismatch_current_anchor') }
    if ($art112Baseline -ne $Trusted.current_art112_baseline_snapshot_hash) { [void]$vectors.Add('art112_snapshot_hash_mismatch') }
    if ($ledgerHash -ne $Trusted.current_ledger_snapshot_hash) { [void]$vectors.Add('ledger_snapshot_hash_mismatch') }

    # Current-vs-stale regression checks.
    if ($ledgerLength -lt $Trusted.current_ledger_length) { [void]$vectors.Add('ledger_length_regression') }
    if ($art111Length -lt $Trusted.current_ledger_length) { [void]$vectors.Add('art111_length_regression') }
    if ($ledgerLatestNum -ge 0 -and $ledgerLatestNum -lt $Trusted.current_latest_entry_num) { [void]$vectors.Add('latest_entry_id_regression') }
    if ($art111LatestNum -ge 0 -and $art111LatestNum -lt $Trusted.current_latest_entry_num) { [void]$vectors.Add('art111_latest_id_regression') }

    # Chain continuity using attested signature. This flags internally-consistent old states too.
    $currentChainSig = Build-ChainSignature -Entries $entries
    if ($currentChainSig -ne $Trusted.current_chain_signature) { [void]$vectors.Add('chain_signature_regression_or_divergence') }

    # Stale snapshot classifier: state is older but may look self-consistent locally.
    $isLocallyConsistent = ($art111Length -eq $ledgerLength) -and ($art111Latest -eq $ledgerLatest) -and ($art111Head -eq $art112Head)
    $isOlder = ($ledgerLength -lt $Trusted.current_ledger_length) -or (($ledgerLatestNum -ge 0) -and ($ledgerLatestNum -lt $Trusted.current_latest_entry_num))
    if ($isLocallyConsistent -and $isOlder) {
        [void]$vectors.Add('stale_snapshot_detected')
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
        reason = 'clean_control_allow'
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
    $isRollbackCase = $ExpectedResult -eq 'BLOCK'
    $hasStaleVector = $vectors -contains 'stale_snapshot_detected'

    if ($isRollbackCase -and $actual -eq 'BLOCK') { $script:rollback_detected_count++ }
    if ($hasStaleVector -and $actual -eq 'BLOCK') { $script:stale_snapshot_rejected_count++ }
    if ($isRollbackCase -and $actual -eq 'ALLOW') { $script:undetected_rollback_count++ }
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

$baselineEntries = @($baselineLedger.entries)
$currentLength = $baselineEntries.Count
$currentLatest = [string]$baselineEntries[$currentLength - 1].entry_id
$currentLatestNum = Get-EntryIdNumber -EntryId $currentLatest
$currentLedgerHash = Get-LedgerSnapshotHash -Ledger $baselineLedger
$currentChainSig = Build-ChainSignature -Entries $baselineEntries

$trusted = @{
    current_ledger_snapshot_hash = $currentLedgerHash
    current_art112_baseline_snapshot_hash = [string]$baselineArt112.baseline_snapshot_hash
    current_latest_entry_id = $currentLatest
    current_latest_entry_num = $currentLatestNum
    current_ledger_length = $currentLength
    current_art111_head_hash_anchor = [string]$baselineArt111.ledger_head_hash
    current_art112_head_hash_anchor = [string]$baselineArt112.ledger_head_hash
    current_chain_signature = $currentChainSig
}

function New-LiveState {
    return @{
        ledger = Copy-Deep -Object $baselineLedger
        art111 = Copy-Deep -Object $baselineArt111
        art112 = Copy-Deep -Object $baselineArt112
    }
}

# Construct previously valid older set (prefix rollback) and internally consistent old metadata.
$oldCount = $currentLength - 2
$oldEntries = @($baselineEntries[0..($oldCount - 1)])
$oldLedger = @{ entries = $oldEntries }
$oldHead = [string]$oldEntries[$oldEntries.Count - 1].fingerprint_hash
$oldLatest = [string]$oldEntries[$oldEntries.Count - 1].entry_id
$oldLedgerHash = Get-LedgerSnapshotHash -Ledger $oldLedger

$oldArt111 = Copy-Deep -Object $baselineArt111
$oldArt111.latest_entry_id = $oldLatest
$oldArt111.ledger_length = $oldEntries.Count
$oldArt111.ledger_head_hash = $oldHead

$oldArt112 = Copy-Deep -Object $baselineArt112
$oldArt112.ledger_head_hash = $oldHead
$oldArt112.baseline_snapshot_hash = $oldLedgerHash

[void]$script:staleCurrentMap.Add('CURRENT: latest=' + $trusted.current_latest_entry_id + ';length=' + $trusted.current_ledger_length + ';art111_head=' + $trusted.current_art111_head_hash_anchor + ';art112_head=' + $trusted.current_art112_head_hash_anchor)
[void]$script:staleCurrentMap.Add('STALE: latest=' + $oldLatest + ';length=' + $oldEntries.Count + ';head=' + $oldHead)
[void]$script:staleCurrentMap.Add('CURRENT_LEDGER_HASH=' + $trusted.current_ledger_snapshot_hash)
[void]$script:staleCurrentMap.Add('STALE_LEDGER_HASH=' + $oldLedgerHash)

# A) Full rollback block: replace all with older trio.
$stateA = New-LiveState
$stateA.ledger = Copy-Deep -Object $oldLedger
$stateA.art111 = Copy-Deep -Object $oldArt111
$stateA.art112 = Copy-Deep -Object $oldArt112
$resultA = Invoke-GuardedCycle -State $stateA -Trusted $trusted
Add-CaseResult -Id 'A' -Name 'ledger_rollback_full_trio' -ExpectedResult 'BLOCK' -CycleResult $resultA

# B) Partial rollback block: rollback ledger only.
$stateB = New-LiveState
$stateB.ledger = Copy-Deep -Object $oldLedger
$resultB = Invoke-GuardedCycle -State $stateB -Trusted $trusted
Add-CaseResult -Id 'B' -Name 'partial_rollback_ledger_only' -ExpectedResult 'BLOCK' -CycleResult $resultB

# C) Stale snapshot rejection: inject previously valid baseline snapshot from earlier run.
$stateC = New-LiveState
$stateC.ledger = Copy-Deep -Object $oldLedger
$stateC.art111 = Copy-Deep -Object $oldArt111
$stateC.art112 = Copy-Deep -Object $oldArt112
$resultC = Invoke-GuardedCycle -State $stateC -Trusted $trusted
Add-CaseResult -Id 'C' -Name 'stale_snapshot_rejection' -ExpectedResult 'BLOCK' -CycleResult $resultC

# D) Head regression detection: move latest/id/length/head backward while keeping current ledger.
$stateD = New-LiveState
$stateD.art111.latest_entry_id = $oldLatest
$stateD.art111.ledger_length = $oldEntries.Count
$stateD.art111.ledger_head_hash = $oldHead
$stateD.art112.ledger_head_hash = $oldHead
$resultD = Invoke-GuardedCycle -State $stateD -Trusted $trusted
Add-CaseResult -Id 'D' -Name 'head_regression_detection' -ExpectedResult 'BLOCK' -CycleResult $resultD

# E) Valid-looking old state: internally consistent old trio.
$stateE = New-LiveState
$stateE.ledger = Copy-Deep -Object $oldLedger
$stateE.art111 = Copy-Deep -Object $oldArt111
$stateE.art112 = Copy-Deep -Object $oldArt112
$resultE = Invoke-GuardedCycle -State $stateE -Trusted $trusted
Add-CaseResult -Id 'E' -Name 'valid_looking_old_state' -ExpectedResult 'BLOCK' -CycleResult $resultE

# F) Mixed current/old fork: current ledger with old art111/art112.
$stateF = New-LiveState
$stateF.art111 = Copy-Deep -Object $oldArt111
$stateF.art112 = Copy-Deep -Object $oldArt112
$resultF = Invoke-GuardedCycle -State $stateF -Trusted $trusted
Add-CaseResult -Id 'F' -Name 'mixed_current_old_fork' -ExpectedResult 'BLOCK' -CycleResult $resultF

# G) Guarded boundary recheck: clean init, then swap stale artifacts before next guard.
$stateG = New-LiveState
$resultG = Invoke-GuardedCycle -State $stateG -Trusted $trusted -RuntimeMutation {
    param([hashtable]$State, [hashtable]$Trusted)
    $State.ledger = Copy-Deep -Object $oldLedger
    $State.art111 = Copy-Deep -Object $oldArt111
    $State.art112 = Copy-Deep -Object $oldArt112
}
Add-CaseResult -Id 'G' -Name 'guarded_boundary_recheck_stale_swap' -ExpectedResult 'BLOCK' -CycleResult $resultG

# H) Clean control.
$stateH = New-LiveState
$resultH = Invoke-GuardedCycle -State $stateH -Trusted $trusted
Add-CaseResult -Id 'H' -Name 'clean_control' -ExpectedResult 'ALLOW' -CycleResult $resultH

$consistencyPass = $true
if ($script:CaseMatrix.Count -ne 8) { $consistencyPass = $false }
if (($script:passCount + $script:failCount) -ne 8) { $consistencyPass = $false }
if ($script:undetected_rollback_count -ne 0) { $consistencyPass = $false }
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
    'ROLLBACK_TEST_MATRIX',
    'A: ledger_rollback_full_trio => expect BLOCK',
    'B: partial_rollback_ledger_only => expect BLOCK',
    'C: stale_snapshot_rejection => expect BLOCK',
    'D: head_regression_detection => expect BLOCK',
    'E: valid_looking_old_state => expect BLOCK',
    'F: mixed_current_old_fork => expect BLOCK',
    'G: guarded_boundary_recheck_stale_swap => expect BLOCK',
    'H: clean_control => expect ALLOW'
)

Write-ProofFile -Path (Join-Path $PF '01_status.txt') -Content @(
    'PHASE=53.11',
    'TITLE=' + $Title,
    'GATE=' + $gate,
    'PASS_COUNT=' + $script:passCount + '/8',
    'FAIL_COUNT=' + $script:failCount,
    'rollback_detected_count=' + $script:rollback_detected_count,
    'stale_snapshot_rejected_count=' + $script:stale_snapshot_rejected_count,
    'undetected_rollback_count=' + $script:undetected_rollback_count,
    'false_positive_count=' + $script:false_positive_count,
    'consistency_check=' + $(if ($consistencyPass) { 'PASS' } else { 'FAIL' }),
    'FAIL_CLOSED=TRUE',
    'NO_FALLBACK=TRUE',
    'NO_SILENT_ACCEPTANCE=TRUE'
)

Write-ProofFile -Path (Join-Path $PF '14_validation_results.txt') -Content $matrixLines
Write-ProofFile -Path (Join-Path $PF '15_rollback_test_matrix.txt') -Content $testMatrix
Write-ProofFile -Path (Join-Path $PF '15_detection_vectors.txt') -Content $vectorLines
Write-ProofFile -Path (Join-Path $PF '15_stale_current_comparison_map.txt') -Content $script:staleCurrentMap.ToArray()

Write-ProofFile -Path (Join-Path $PF '98_gate_phase53_11.txt') -Content @(
    'GATE=' + $gate,
    'PASS_COUNT=' + $script:passCount + '/8',
    'FAIL_COUNT=' + $script:failCount,
    'rollback_detected_count=' + $script:rollback_detected_count,
    'stale_snapshot_rejected_count=' + $script:stale_snapshot_rejected_count,
    'undetected_rollback_count=' + $script:undetected_rollback_count,
    'false_positive_count=' + $script:false_positive_count
)

$zipPath = $PF + '.zip'
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path $PF -DestinationPath $zipPath -Force

Write-Output ('PF=' + $PF)
Write-Output ('ZIP=' + $zipPath)
Write-Output ('GATE=' + $gate)
