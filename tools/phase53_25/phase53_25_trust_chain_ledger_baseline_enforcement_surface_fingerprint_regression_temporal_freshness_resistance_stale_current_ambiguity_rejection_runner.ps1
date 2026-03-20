#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Phase 53.25: Temporal Freshness Resistance + Stale-Current Ambiguity Rejection

$Phase = '53.25'
$Title = 'Temporal Freshness Resistance and Stale-Current Ambiguity Rejection'
$PF = Join-Path $PSScriptRoot '..\..\' '_proof' "phase53_25_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_temporal_freshness_resistance_stale_current_ambiguity_rejection_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $PF -Force | Out-Null

$script:CaseMatrix = [System.Collections.Generic.List[object]]::new()
$script:DetectionVectors = [System.Collections.Generic.List[object]]::new()
$script:CurrentnessFreshnessMap = [System.Collections.Generic.List[string]]::new()

$script:passCount = 0
$script:failCount = 0
$script:stale_state_rejected_count = 0
$script:temporal_ambiguity_rejected_count = 0
$script:undetected_stale_acceptance_count = 0
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

function Add-Vector {
    param([System.Collections.Generic.List[string]]$Vectors, [string]$Value)
    if (-not ($Vectors -contains $Value)) {
        [void]$Vectors.Add($Value)
    }
}

function Get-EntryIdNumber {
    param([string]$EntryId)
    if ($EntryId -match '^GF-(\d+)$') { return [int]$Matches[1] }
    return -1
}

function Get-UtcDateTime {
    param([string]$Timestamp)
    try {
        return ([datetime]::Parse($Timestamp, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal))
    }
    catch {
        return $null
    }
}

function Format-UtcTicks {
    param($DateTimeValue)
    if ($null -eq $DateTimeValue) { return '' }
    return ([string]([datetime]$DateTimeValue).Ticks)
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
        $eid = [string]$entry.entry_id
        $prev = [string]$entry.previous_hash
        $fp = [string]$entry.fingerprint_hash
        [void]$parts.Add(($eid + '|' + $prev + '|' + $fp))
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

function Test-LedgerTimestampMonotonicity {
    param($Entries)

    $prev = $null
    foreach ($entry in @($Entries)) {
        $parsed = Get-UtcDateTime -Timestamp ([string]$entry.timestamp_utc)
        if ($null -eq $parsed) {
            return @{ ok = $false; reason = 'ledger_timestamp_invalid' }
        }

        if ($null -ne $prev -and $parsed -lt $prev) {
            return @{ ok = $false; reason = 'ledger_timestamp_non_monotonic' }
        }

        $prev = $parsed
    }

    return @{ ok = $true; reason = 'ok' }
}

function Get-TemporalContextProof {
    param([hashtable]$State)

    $entries = @($State.ledger.entries)
    if ($entries.Count -eq 0) { return '' }

    $latest = $entries[$entries.Count - 1]
    $parts = @(
        ('ledger_hash=' + (Get-LedgerSnapshotHash -Ledger $State.ledger)),
        ('ledger_length=' + $entries.Count),
        ('latest_entry_id=' + [string]$latest.entry_id),
        ('latest_entry_timestamp_utc=' + [string]$latest.timestamp_utc),
        ('ledger_head_hash=' + [string]$latest.fingerprint_hash),
        ('art111_latest_entry_id=' + [string]$State.art111.latest_entry_id),
        ('art111_ledger_length=' + [int]$State.art111.ledger_length),
        ('art111_ledger_head_hash=' + [string]$State.art111.ledger_head_hash),
        ('art111_timestamp_utc=' + [string]$State.art111.timestamp_utc),
        ('art112_baseline_snapshot_hash=' + [string]$State.art112.baseline_snapshot_hash),
        ('art112_ledger_head_hash=' + [string]$State.art112.ledger_head_hash),
        ('art112_timestamp_utc=' + [string]$State.art112.timestamp_utc)
    )

    return (Get-StringHash -InputString ($parts -join '|'))
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

    $entryOrder = Test-EntryFormatAndMonotonicity -Entries $entries
    if (-not $entryOrder.ok) {
        Add-Vector -Vectors $vectors -Value $entryOrder.reason
    }

    $timeOrder = Test-LedgerTimestampMonotonicity -Entries $entries
    if (-not $timeOrder.ok) {
        Add-Vector -Vectors $vectors -Value $timeOrder.reason
    }

    $ledgerLength = $entries.Count
    $latestEntry = $entries[$entries.Count - 1]
    $ledgerLatest = [string]$latestEntry.entry_id
    $ledgerLatestNum = Get-EntryIdNumber -EntryId $ledgerLatest
    $ledgerHead = [string]$latestEntry.fingerprint_hash
    $ledgerHash = Get-LedgerSnapshotHash -Ledger $State.ledger
    $ledgerChainSig = Build-ChainSignature -Entries $entries

    $ledgerLatestTs = Get-UtcDateTime -Timestamp ([string]$latestEntry.timestamp_utc)
    $art111Ts = Get-UtcDateTime -Timestamp ([string]$State.art111.timestamp_utc)
    $art112Ts = Get-UtcDateTime -Timestamp ([string]$State.art112.timestamp_utc)

    if ($null -eq $ledgerLatestTs) { Add-Vector -Vectors $vectors -Value 'ledger_latest_timestamp_invalid' }
    if ($null -eq $art111Ts) { Add-Vector -Vectors $vectors -Value 'art111_timestamp_invalid' }
    if ($null -eq $art112Ts) { Add-Vector -Vectors $vectors -Value 'art112_timestamp_invalid' }

    $art111Latest = [string]$State.art111.latest_entry_id
    $art111LatestNum = Get-EntryIdNumber -EntryId $art111Latest
    $art111Length = [int]$State.art111.ledger_length
    $art111Head = [string]$State.art111.ledger_head_hash

    $art112Head = [string]$State.art112.ledger_head_hash
    $art112Baseline = [string]$State.art112.baseline_snapshot_hash

    if ($art111Length -ne $ledgerLength) { Add-Vector -Vectors $vectors -Value 'ledger_length_mismatch' }
    if ($art111Latest -ne $ledgerLatest) { Add-Vector -Vectors $vectors -Value 'latest_entry_id_mismatch' }
    if ($art111Head -ne $art112Head) { Add-Vector -Vectors $vectors -Value 'head_hash_cross_artifact_mismatch' }

    if ($ledgerHash -ne $Trusted.current_ledger_snapshot_hash) { Add-Vector -Vectors $vectors -Value 'ledger_snapshot_hash_mismatch_current' }
    if ($ledgerHead -ne $Trusted.current_ledger_head_hash) { Add-Vector -Vectors $vectors -Value 'ledger_head_hash_regression_or_divergence' }
    if ($art111Head -ne $Trusted.current_art111_head_hash_anchor) { Add-Vector -Vectors $vectors -Value 'art111_head_hash_mismatch_current_anchor' }
    if ($art112Head -ne $Trusted.current_art112_head_hash_anchor) { Add-Vector -Vectors $vectors -Value 'art112_head_hash_mismatch_current_anchor' }
    if ($art112Baseline -ne $Trusted.current_art112_baseline_snapshot_hash) { Add-Vector -Vectors $vectors -Value 'art112_baseline_hash_mismatch_current_anchor' }
    if ($ledgerChainSig -ne $Trusted.current_chain_signature) { Add-Vector -Vectors $vectors -Value 'chain_signature_regression_or_divergence' }

    if ($ledgerLength -lt $Trusted.current_ledger_length) { Add-Vector -Vectors $vectors -Value 'ledger_length_regression' }
    if ($art111Length -lt $Trusted.current_ledger_length) { Add-Vector -Vectors $vectors -Value 'art111_length_regression' }
    if ($ledgerLatestNum -ge 0 -and $ledgerLatestNum -lt $Trusted.current_latest_entry_num) { Add-Vector -Vectors $vectors -Value 'latest_entry_id_regression' }
    if ($art111LatestNum -ge 0 -and $art111LatestNum -lt $Trusted.current_latest_entry_num) { Add-Vector -Vectors $vectors -Value 'art111_latest_id_regression' }

    if ($null -ne $ledgerLatestTs -and $ledgerLatestTs -lt $Trusted.current_latest_entry_timestamp) {
        Add-Vector -Vectors $vectors -Value 'latest_timestamp_regression'
    }
    if ($null -ne $art111Ts -and $art111Ts -lt $Trusted.current_art111_timestamp) {
        Add-Vector -Vectors $vectors -Value 'art111_timestamp_regression'
    }
    if ($null -ne $art112Ts -and $art112Ts -lt $Trusted.current_art112_timestamp) {
        Add-Vector -Vectors $vectors -Value 'art112_timestamp_regression'
    }

    if ($null -ne $ledgerLatestTs -and $null -ne $art111Ts -and $art111Ts -lt $ledgerLatestTs) {
        Add-Vector -Vectors $vectors -Value 'art111_precedes_live_ledger_timestamp'
        Add-Vector -Vectors $vectors -Value 'temporal_currentness_ambiguity'
    }
    if ($null -ne $ledgerLatestTs -and $null -ne $art112Ts -and $art112Ts -lt $ledgerLatestTs) {
        Add-Vector -Vectors $vectors -Value 'art112_precedes_live_ledger_timestamp'
        Add-Vector -Vectors $vectors -Value 'temporal_currentness_ambiguity'
    }
    if ($null -ne $art111Ts -and $null -ne $art112Ts -and $art111Ts -ne $art112Ts) {
        Add-Vector -Vectors $vectors -Value 'artifact_timestamp_ambiguity'
        Add-Vector -Vectors $vectors -Value 'temporal_currentness_ambiguity'
    }

    $proofActual = [string]$State.temporal_context_proof
    $proofDerived = Get-TemporalContextProof -State $State
    if ([string]::IsNullOrWhiteSpace($proofActual)) {
        Add-Vector -Vectors $vectors -Value 'currentness_proof_missing'
        Add-Vector -Vectors $vectors -Value 'temporal_currentness_ambiguity'
    }
    elseif ($proofActual -ne $proofDerived) {
        Add-Vector -Vectors $vectors -Value 'currentness_proof_invalid'
        Add-Vector -Vectors $vectors -Value 'temporal_currentness_ambiguity'
    }

    if ($proofDerived -ne $Trusted.current_temporal_context_proof) {
        Add-Vector -Vectors $vectors -Value 'stale_or_noncurrent_temporal_context'
    }

    $isLocallyConsistent =
        ($art111Length -eq $ledgerLength) -and
        ($art111Latest -eq $ledgerLatest) -and
        ($art111Head -eq $ledgerHead) -and
        ($art112Head -eq $ledgerHead) -and
        ($art112Baseline -eq $ledgerHash)

    $isOlder =
        ($ledgerLength -lt $Trusted.current_ledger_length) -or
        (($ledgerLatestNum -ge 0) -and ($ledgerLatestNum -lt $Trusted.current_latest_entry_num)) -or
        (($null -ne $ledgerLatestTs) -and ($ledgerLatestTs -lt $Trusted.current_latest_entry_timestamp))

    if ($isLocallyConsistent -and $isOlder) {
        Add-Vector -Vectors $vectors -Value 'stale_state_detected'
    }

    $partialStaleness =
        (($ledgerHash -eq $Trusted.current_ledger_snapshot_hash) -and (($art111Head -ne $Trusted.current_art111_head_hash_anchor) -or ($art112Head -ne $Trusted.current_art112_head_hash_anchor))) -or
        (($ledgerHash -ne $Trusted.current_ledger_snapshot_hash) -and (($art111Head -eq $Trusted.current_art111_head_hash_anchor) -or ($art112Head -eq $Trusted.current_art112_head_hash_anchor)))

    if ($partialStaleness) {
        Add-Vector -Vectors $vectors -Value 'partial_staleness_mix'
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

    return @{ blocked = $false; runtime_executed = $true; stage = 'allow'; vectors = [System.Collections.Generic.List[string]]::new(); reason = 'current_temporal_context_allow' }
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
    $staleSignals = @(
        'stale_state_detected',
        'stale_or_noncurrent_temporal_context',
        'partial_staleness_mix',
        'latest_entry_id_regression',
        'latest_timestamp_regression'
    )
    $ambiguitySignals = @(
        'temporal_currentness_ambiguity',
        'artifact_timestamp_ambiguity',
        'currentness_proof_missing',
        'currentness_proof_invalid'
    )

    $hasStaleSignal = $false
    foreach ($signal in $staleSignals) {
        if ($vectors -contains $signal) { $hasStaleSignal = $true; break }
    }

    $hasAmbiguitySignal = $false
    foreach ($signal in $ambiguitySignals) {
        if ($vectors -contains $signal) { $hasAmbiguitySignal = $true; break }
    }

    if ($hasStaleSignal -and $actual -eq 'BLOCK') { $script:stale_state_rejected_count++ }
    if ($hasAmbiguitySignal -and $actual -eq 'BLOCK') { $script:temporal_ambiguity_rejected_count++ }
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'ALLOW') { $script:undetected_stale_acceptance_count++ }
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
if ($baselineEntries.Count -lt 3) { throw 'Baseline ledger must contain at least 3 entries for stale/current temporal regression validation.' }

$currentLength = $baselineEntries.Count
$currentLatestEntry = $baselineEntries[$currentLength - 1]
$currentLatest = [string]$currentLatestEntry.entry_id
$currentLatestNum = Get-EntryIdNumber -EntryId $currentLatest
$currentLedgerHash = Get-LedgerSnapshotHash -Ledger $baselineLedger
$currentChainSig = Build-ChainSignature -Entries $baselineEntries
$currentLedgerHead = [string]$currentLatestEntry.fingerprint_hash
$currentLatestTimestamp = Get-UtcDateTime -Timestamp ([string]$currentLatestEntry.timestamp_utc)
$currentArt111Timestamp = Get-UtcDateTime -Timestamp ([string]$baselineArt111.timestamp_utc)
$currentArt112Timestamp = Get-UtcDateTime -Timestamp ([string]$baselineArt112.timestamp_utc)

if ($null -eq $currentLatestTimestamp) { throw 'Current latest ledger timestamp is invalid.' }
if ($null -eq $currentArt111Timestamp) { throw 'Current art111 timestamp is invalid.' }
if ($null -eq $currentArt112Timestamp) { throw 'Current art112 timestamp is invalid.' }

$trusted = @{
    current_ledger_snapshot_hash = $currentLedgerHash
    current_ledger_head_hash = $currentLedgerHead
    current_art112_baseline_snapshot_hash = [string]$baselineArt112.baseline_snapshot_hash
    current_latest_entry_id = $currentLatest
    current_latest_entry_num = $currentLatestNum
    current_latest_entry_timestamp = $currentLatestTimestamp
    current_ledger_length = $currentLength
    current_art111_head_hash_anchor = [string]$baselineArt111.ledger_head_hash
    current_art112_head_hash_anchor = [string]$baselineArt112.ledger_head_hash
    current_art111_timestamp = $currentArt111Timestamp
    current_art112_timestamp = $currentArt112Timestamp
    current_chain_signature = $currentChainSig
}

function New-LiveState {
    $state = @{
        ledger = Copy-Deep -Object $baselineLedger
        art111 = Copy-Deep -Object $baselineArt111
        art112 = Copy-Deep -Object $baselineArt112
        temporal_context_proof = ''
    }
    $state.temporal_context_proof = Get-TemporalContextProof -State $state
    return $state
}

$trusted.current_temporal_context_proof = (New-LiveState).temporal_context_proof

$oldCount = $currentLength - 2
$oldEntries = @($baselineEntries[0..($oldCount - 1)])
$oldLedger = @{ entries = $oldEntries }
$oldHead = [string]$oldEntries[$oldEntries.Count - 1].fingerprint_hash
$oldLatest = [string]$oldEntries[$oldEntries.Count - 1].entry_id
$oldLatestNum = Get-EntryIdNumber -EntryId $oldLatest
$oldLatestTimestamp = Get-UtcDateTime -Timestamp ([string]$oldEntries[$oldEntries.Count - 1].timestamp_utc)
$oldLedgerHash = Get-LedgerSnapshotHash -Ledger $oldLedger

$oldArt111 = Copy-Deep -Object $baselineArt111
$oldArt111.latest_entry_id = $oldLatest
$oldArt111.latest_entry_phase_locked = [string]$oldEntries[$oldEntries.Count - 1].phase_locked
$oldArt111.ledger_length = $oldEntries.Count
$oldArt111.ledger_head_hash = $oldHead
$oldArt111.timestamp_utc = ([string]$oldEntries[$oldEntries.Count - 1].timestamp_utc)

$oldArt112 = Copy-Deep -Object $baselineArt112
$oldArt112.ledger_head_hash = $oldHead
$oldArt112.baseline_snapshot_hash = $oldLedgerHash
$oldArt112.timestamp_utc = ([string]$oldEntries[$oldEntries.Count - 1].timestamp_utc)

[void]$script:CurrentnessFreshnessMap.Add('CURRENT: latest=' + $trusted.current_latest_entry_id + ';length=' + $trusted.current_ledger_length + ';ledger_head=' + $trusted.current_ledger_head_hash)
[void]$script:CurrentnessFreshnessMap.Add('CURRENT_TIMESTAMPS: ledger_latest=' + [string]$currentLatestEntry.timestamp_utc + ';art111=' + [string]$baselineArt111.timestamp_utc + ';art112=' + [string]$baselineArt112.timestamp_utc)
[void]$script:CurrentnessFreshnessMap.Add('CURRENT_LEDGER_HASH=' + $trusted.current_ledger_snapshot_hash)
[void]$script:CurrentnessFreshnessMap.Add('CURRENT_TEMPORAL_CONTEXT_PROOF=' + $trusted.current_temporal_context_proof)
[void]$script:CurrentnessFreshnessMap.Add('STALE: latest=' + $oldLatest + ';length=' + $oldEntries.Count + ';ledger_head=' + $oldHead)
[void]$script:CurrentnessFreshnessMap.Add('STALE_TIMESTAMPS: ledger_latest=' + [string]$oldEntries[$oldEntries.Count - 1].timestamp_utc + ';art111=' + [string]$oldArt111.timestamp_utc + ';art112=' + [string]$oldArt112.timestamp_utc)
[void]$script:CurrentnessFreshnessMap.Add('STALE_LEDGER_HASH=' + $oldLedgerHash)
[void]$script:CurrentnessFreshnessMap.Add('STALE_CURRENTNESS_RULE=exact_current_temporal_context_proof_required')
[void]$script:CurrentnessFreshnessMap.Add('AMBIGUITY_RULE=artifact_timestamps_and_currentness_proof_must_be_unambiguous')
[void]$script:CurrentnessFreshnessMap.Add('TEMPORAL_MONOTONICITY_RULE=ledger_timestamps_and_current_markers_must_not_regress')

# A) Stale-as-current block: present old trio as if it were current.
$stateA = New-LiveState
$stateA.ledger = Copy-Deep -Object $oldLedger
$stateA.art111 = Copy-Deep -Object $oldArt111
$stateA.art112 = Copy-Deep -Object $oldArt112
$stateA.art111.timestamp_utc = [string]$baselineArt111.timestamp_utc
$stateA.art112.timestamp_utc = [string]$baselineArt112.timestamp_utc
$stateA.temporal_context_proof = $trusted.current_temporal_context_proof
$resultA = Invoke-GuardedCycle -State $stateA -Trusted $trusted
Add-CaseResult -Id 'A' -Name 'stale_as_current_block' -ExpectedResult 'BLOCK' -CycleResult $resultA

# B) Current/stale ambiguity: current content but ambiguous freshness timestamps.
$stateB = New-LiveState
$stateB.art112.timestamp_utc = [string]$oldArt112.timestamp_utc
$stateB.temporal_context_proof = $trusted.current_temporal_context_proof
$resultB = Invoke-GuardedCycle -State $stateB -Trusted $trusted
Add-CaseResult -Id 'B' -Name 'current_stale_ambiguity' -ExpectedResult 'BLOCK' -CycleResult $resultB

# C) Same content, different temporal context: older accepted content reused without currentness proof.
$stateC = New-LiveState
$stateC.ledger = Copy-Deep -Object $oldLedger
$stateC.art111 = Copy-Deep -Object $oldArt111
$stateC.art112 = Copy-Deep -Object $oldArt112
$stateC.art111.timestamp_utc = [string]$baselineArt111.timestamp_utc
$stateC.art112.timestamp_utc = [string]$baselineArt112.timestamp_utc
$stateC.temporal_context_proof = ''
$resultC = Invoke-GuardedCycle -State $stateC -Trusted $trusted
Add-CaseResult -Id 'C' -Name 'same_content_different_temporal_context' -ExpectedResult 'BLOCK' -CycleResult $resultC

# D) Partial staleness mix: current ledger with stale art111/art112 metadata.
$stateD = New-LiveState
$stateD.art111 = Copy-Deep -Object $oldArt111
$stateD.art112 = Copy-Deep -Object $oldArt112
$stateD.temporal_context_proof = Get-TemporalContextProof -State $stateD
$resultD = Invoke-GuardedCycle -State $stateD -Trusted $trusted
Add-CaseResult -Id 'D' -Name 'partial_staleness_mix' -ExpectedResult 'BLOCK' -CycleResult $resultD

# E) Resealed stale state: stale trio recomputed into an internally coherent but non-current proof.
$stateE = New-LiveState
$stateE.ledger = Copy-Deep -Object $oldLedger
$stateE.art111 = Copy-Deep -Object $oldArt111
$stateE.art112 = Copy-Deep -Object $oldArt112
$stateE.temporal_context_proof = Get-TemporalContextProof -State $stateE
$resultE = Invoke-GuardedCycle -State $stateE -Trusted $trusted
Add-CaseResult -Id 'E' -Name 'resealed_stale_state' -ExpectedResult 'BLOCK' -CycleResult $resultE

# F) Time-order regression: move the newest ledger timestamp backward.
$stateF = New-LiveState
$previousTimestamp = [string]$baselineEntries[$baselineEntries.Count - 2].timestamp_utc
$stateF.ledger.entries[$stateF.ledger.entries.Count - 1].timestamp_utc = $previousTimestamp
$stateF.temporal_context_proof = Get-TemporalContextProof -State $stateF
$resultF = Invoke-GuardedCycle -State $stateF -Trusted $trusted
Add-CaseResult -Id 'F' -Name 'time_order_regression' -ExpectedResult 'BLOCK' -CycleResult $resultF

# G) Guarded-boundary stale swap: clean init, stale swap before next validation.
$stateG = New-LiveState
$resultG = Invoke-GuardedCycle -State $stateG -Trusted $trusted -RuntimeMutation {
    param([hashtable]$State, [hashtable]$Trusted)
    $State.ledger = Copy-Deep -Object $oldLedger
    $State.art111 = Copy-Deep -Object $oldArt111
    $State.art112 = Copy-Deep -Object $oldArt112
    $State.temporal_context_proof = Get-TemporalContextProof -State $State
}
Add-CaseResult -Id 'G' -Name 'guarded_boundary_stale_swap' -ExpectedResult 'BLOCK' -CycleResult $resultG

# H) Clean control.
$stateH = New-LiveState
$resultH = Invoke-GuardedCycle -State $stateH -Trusted $trusted
Add-CaseResult -Id 'H' -Name 'clean_control' -ExpectedResult 'ALLOW' -CycleResult $resultH

$consistencyPass = $true
if ($script:CaseMatrix.Count -ne 8) { $consistencyPass = $false }
if (($script:passCount + $script:failCount) -ne 8) { $consistencyPass = $false }
if ($script:undetected_stale_acceptance_count -ne 0) { $consistencyPass = $false }
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

$temporalFreshnessMatrix = @(
    'TEMPORAL_FRESHNESS_MATRIX',
    'A: stale_as_current_block => expect BLOCK',
    'B: current_stale_ambiguity => expect BLOCK',
    'C: same_content_different_temporal_context => expect BLOCK',
    'D: partial_staleness_mix => expect BLOCK',
    'E: resealed_stale_state => expect BLOCK',
    'F: time_order_regression => expect BLOCK',
    'G: guarded_boundary_stale_swap => expect BLOCK',
    'H: clean_control => expect ALLOW'
)

Write-ProofFile -Path (Join-Path $PF '01_status.txt') -Content @(
    'PHASE=53.25',
    ('TITLE={0}' -f $Title),
    ('GATE={0}' -f $gate),
    ('PASS_COUNT={0}/8' -f $script:passCount),
    ('FAIL_COUNT={0}' -f $script:failCount),
    ('stale_state_rejected_count={0}' -f $script:stale_state_rejected_count),
    ('temporal_ambiguity_rejected_count={0}' -f $script:temporal_ambiguity_rejected_count),
    ('undetected_stale_acceptance_count={0}' -f $script:undetected_stale_acceptance_count),
    ('false_positive_count={0}' -f $script:false_positive_count),
    ('consistency_check={0}' -f $(if ($consistencyPass) { 'PASS' } else { 'FAIL' })),
    'FAIL_CLOSED=TRUE',
    'NO_FALLBACK=TRUE',
    'NO_SILENT_ACCEPTANCE=TRUE'
)

Write-ProofFile -Path (Join-Path $PF '14_validation_results.txt') -Content $matrixLines
Write-ProofFile -Path (Join-Path $PF '15_temporal_freshness_matrix.txt') -Content $temporalFreshnessMatrix
Write-ProofFile -Path (Join-Path $PF '15_currentness_freshness_map.txt') -Content $script:CurrentnessFreshnessMap.ToArray()
Write-ProofFile -Path (Join-Path $PF '15_detection_vectors.txt') -Content $vectorLines

Write-ProofFile -Path (Join-Path $PF '98_gate_phase53_25.txt') -Content @(
    ('GATE={0}' -f $gate),
    ('PASS_COUNT={0}/8' -f $script:passCount),
    ('FAIL_COUNT={0}' -f $script:failCount),
    ('stale_state_rejected_count={0}' -f $script:stale_state_rejected_count),
    ('temporal_ambiguity_rejected_count={0}' -f $script:temporal_ambiguity_rejected_count),
    ('undetected_stale_acceptance_count={0}' -f $script:undetected_stale_acceptance_count),
    ('false_positive_count={0}' -f $script:false_positive_count)
)

$zipPath = $PF + '.zip'
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path $PF -DestinationPath $zipPath -Force

Write-Output ('PF=' + $PF)
Write-Output ('ZIP=' + $zipPath)
Write-Output ('GATE=' + $gate)