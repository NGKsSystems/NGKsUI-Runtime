#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Phase 53.26: Concurrent Stale/Fork Mix Resistance + Cross-Timeline Convergence Rejection

$Phase = '53.26'
$Title = 'Concurrent Stale/Fork Mix Resistance and Cross-Timeline Convergence Rejection'
$PF = Join-Path $PSScriptRoot '..\..\' '_proof' "phase53_26_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_concurrent_stale_fork_mix_cross_timeline_convergence_rejection_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $PF -Force | Out-Null

$script:CaseMatrix = [System.Collections.Generic.List[object]]::new()
$script:DetectionVectors = [System.Collections.Generic.List[object]]::new()
$script:CanonicalTimelineFreshnessLineageMap = [System.Collections.Generic.List[string]]::new()

$script:passCount = 0
$script:failCount = 0
$script:cross_timeline_rejected_count = 0
$script:ambiguous_timeline_rejected_count = 0
$script:undetected_cross_timeline_acceptance_count = 0
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
            $phaseLocked = [string]$c[$idx].phase_locked
        }
        else {
            $entryId = 'GF-{0:D4}' -f ($idx + 1)
            $timestamp = [string]$c[$c.Count - 1].timestamp_utc
            $phaseLocked = '53.26-fork'
        }

        $prevHash = if ($fork.Count -gt 0) { [string]$fork[$fork.Count - 1].fingerprint_hash } else { $null }
        $payload = $Salt + '|' + $entryId + '|' + $idx + '|' + $prevHash
        $fp = Get-StringHash -InputString $payload

        $newEntry = @{
            entry_id = $entryId
            timestamp_utc = $timestamp
            phase_locked = $phaseLocked
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
        $BaselineArt112,
        [string]$TimestampUtc
    )

    $entries = @($Ledger.entries)
    $last = $entries[$entries.Count - 1]
    $head = [string]$last.fingerprint_hash
    $latest = [string]$last.entry_id
    $length = $entries.Count
    $snap = Get-LedgerSnapshotHash -Ledger $Ledger
    $stamp = if ([string]::IsNullOrWhiteSpace($TimestampUtc)) { [string]$last.timestamp_utc } else { $TimestampUtc }

    $art111 = Copy-Deep -Object $BaselineArt111
    $art111.latest_entry_id = $latest
    $art111.latest_entry_phase_locked = [string]$last.phase_locked
    $art111.ledger_length = $length
    $art111.ledger_head_hash = $head
    $art111.timestamp_utc = $stamp

    $art112 = Copy-Deep -Object $BaselineArt112
    $art112.ledger_head_hash = $head
    $art112.baseline_snapshot_hash = $snap
    $art112.timestamp_utc = $stamp

    return @{
        art111 = $art111
        art112 = $art112
    }
}

function Get-ContextTimelineProof {
    param(
        $Ledger,
        $Art111,
        $Art112
    )

    $entries = @($Ledger.entries)
    if ($entries.Count -eq 0) { return '' }

    $latest = $entries[$entries.Count - 1]
    $parts = @(
        ('ledger_hash=' + (Get-LedgerSnapshotHash -Ledger $Ledger)),
        ('chain_signature=' + (Build-ChainSignature -Entries $entries)),
        ('ledger_length=' + $entries.Count),
        ('latest_entry_id=' + [string]$latest.entry_id),
        ('latest_entry_timestamp_utc=' + [string]$latest.timestamp_utc),
        ('ledger_head_hash=' + [string]$latest.fingerprint_hash),
        ('art111_latest_entry_id=' + [string]$Art111.latest_entry_id),
        ('art111_ledger_length=' + [int]$Art111.ledger_length),
        ('art111_ledger_head_hash=' + [string]$Art111.ledger_head_hash),
        ('art111_timestamp_utc=' + [string]$Art111.timestamp_utc),
        ('art112_baseline_snapshot_hash=' + [string]$Art112.baseline_snapshot_hash),
        ('art112_ledger_head_hash=' + [string]$Art112.ledger_head_hash),
        ('art112_timestamp_utc=' + [string]$Art112.timestamp_utc)
    )

    return (Get-StringHash -InputString ($parts -join '|'))
}

function Set-StateTimelineIdentity {
    param([hashtable]$State)

    $derived = Get-ContextTimelineProof -Ledger $State.ledger -Art111 $State.art111 -Art112 $State.art112
    $State.timeline_uniqueness_proof = $derived
    $State.timeline_candidates = @($derived)
    return $derived
}

function New-Context {
    param($Ledger, $Art111, $Art112)
    return @{
        ledger = Copy-Deep -Object $Ledger
        art111 = Copy-Deep -Object $Art111
        art112 = Copy-Deep -Object $Art112
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
        Add-Vector -Vectors $vectors -Value 'ambiguous_timeline_identity'
    }
    if ($null -ne $ledgerLatestTs -and $null -ne $art112Ts -and $art112Ts -lt $ledgerLatestTs) {
        Add-Vector -Vectors $vectors -Value 'art112_precedes_live_ledger_timestamp'
        Add-Vector -Vectors $vectors -Value 'ambiguous_timeline_identity'
    }
    if ($null -ne $art111Ts -and $null -ne $art112Ts -and $art111Ts -ne $art112Ts) {
        Add-Vector -Vectors $vectors -Value 'artifact_timestamp_ambiguity'
        Add-Vector -Vectors $vectors -Value 'ambiguous_timeline_identity'
    }

    $derivedTimelineProof = Get-ContextTimelineProof -Ledger $State.ledger -Art111 $State.art111 -Art112 $State.art112
    $actualTimelineProof = [string]$State.timeline_uniqueness_proof
    if ([string]::IsNullOrWhiteSpace($actualTimelineProof)) {
        Add-Vector -Vectors $vectors -Value 'timeline_uniqueness_proof_missing'
        Add-Vector -Vectors $vectors -Value 'ambiguous_timeline_identity'
    }
    elseif ($actualTimelineProof -ne $derivedTimelineProof) {
        Add-Vector -Vectors $vectors -Value 'timeline_uniqueness_proof_invalid'
        Add-Vector -Vectors $vectors -Value 'ambiguous_timeline_identity'
    }

    if ($derivedTimelineProof -ne $Trusted.current_timeline_proof) {
        Add-Vector -Vectors $vectors -Value 'non_canonical_timeline_identity'
        Add-Vector -Vectors $vectors -Value 'cross_timeline_state_detected'
    }

    $candidates = @($State.timeline_candidates)
    $candidateValues = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) {
            [void]$candidateValues.Add([string]$candidate)
        }
    }

    $distinctCandidates = @($candidateValues | Select-Object -Unique)
    if ($distinctCandidates.Count -ne 1) {
        Add-Vector -Vectors $vectors -Value 'ambiguous_timeline_identity'
    }
    elseif ($distinctCandidates[0] -ne $derivedTimelineProof) {
        Add-Vector -Vectors $vectors -Value 'timeline_candidate_mismatch'
        Add-Vector -Vectors $vectors -Value 'ambiguous_timeline_identity'
    }

    if ($distinctCandidates.Count -eq 1 -and $distinctCandidates[0] -ne $Trusted.current_timeline_proof) {
        Add-Vector -Vectors $vectors -Value 'cross_timeline_state_detected'
    }

    $hasCurrentComponent = ($ledgerHash -eq $Trusted.current_ledger_snapshot_hash) -or ($art111Head -eq $Trusted.current_art111_head_hash_anchor) -or ($art112Head -eq $Trusted.current_art112_head_hash_anchor) -or ($art112Baseline -eq $Trusted.current_art112_baseline_snapshot_hash)
    $hasNonCurrentComponent = ($ledgerHash -ne $Trusted.current_ledger_snapshot_hash) -or ($art111Head -ne $Trusted.current_art111_head_hash_anchor) -or ($art112Head -ne $Trusted.current_art112_head_hash_anchor) -or ($art112Baseline -ne $Trusted.current_art112_baseline_snapshot_hash)
    if ($hasCurrentComponent -and $hasNonCurrentComponent) {
        Add-Vector -Vectors $vectors -Value 'cross_timeline_artifact_set'
    }

    $appearsRecent =
        (($null -ne $ledgerLatestTs) -and ($ledgerLatestTs -ge $Trusted.current_latest_entry_timestamp)) -and
        (($null -eq $art111Ts) -or ($art111Ts -ge $Trusted.current_art111_timestamp)) -and
        (($null -eq $art112Ts) -or ($art112Ts -ge $Trusted.current_art112_timestamp))
    if ($ledgerChainSig -ne $Trusted.current_chain_signature -and $appearsRecent) {
        Add-Vector -Vectors $vectors -Value 'fork_freshness_convergence_detected'
        Add-Vector -Vectors $vectors -Value 'cross_timeline_state_detected'
    }

    $concurrentProofs = [System.Collections.Generic.List[string]]::new()
    foreach ($ctx in @($State.concurrent_contexts)) {
        $ctxProof = Get-ContextTimelineProof -Ledger $ctx.ledger -Art111 $ctx.art111 -Art112 $ctx.art112
        if (-not [string]::IsNullOrWhiteSpace($ctxProof)) {
            [void]$concurrentProofs.Add($ctxProof)
        }
    }

    if ($concurrentProofs.Count -gt 0) {
        [void]$concurrentProofs.Add($derivedTimelineProof)
        $distinctConcurrent = @($concurrentProofs | Select-Object -Unique)
        if ($distinctConcurrent.Count -gt 1) {
            Add-Vector -Vectors $vectors -Value 'concurrent_timeline_mix_detected'
            Add-Vector -Vectors $vectors -Value 'ambiguous_timeline_identity'
        }

        $hasCurrentTimeline = $false
        $hasOtherTimeline = $false
        foreach ($proof in $distinctConcurrent) {
            if ($proof -eq $Trusted.current_timeline_proof) {
                $hasCurrentTimeline = $true
            }
            else {
                $hasOtherTimeline = $true
            }
        }

        if ($hasCurrentTimeline -and $hasOtherTimeline) {
            Add-Vector -Vectors $vectors -Value 'stale_current_concurrent_mix'
            Add-Vector -Vectors $vectors -Value 'cross_timeline_state_detected'
        }
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

    return @{ blocked = $false; runtime_executed = $true; stage = 'allow'; vectors = [System.Collections.Generic.List[string]]::new(); reason = 'canonical_single_timeline_allow' }
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
    $crossSignals = @(
        'cross_timeline_state_detected',
        'cross_timeline_artifact_set',
        'non_canonical_timeline_identity',
        'fork_freshness_convergence_detected',
        'concurrent_timeline_mix_detected',
        'stale_current_concurrent_mix'
    )
    $ambiguitySignals = @(
        'ambiguous_timeline_identity',
        'timeline_uniqueness_proof_missing',
        'timeline_uniqueness_proof_invalid',
        'timeline_candidate_mismatch',
        'concurrent_timeline_mix_detected'
    )

    $hasCrossSignal = $false
    foreach ($signal in $crossSignals) {
        if ($vectors -contains $signal) { $hasCrossSignal = $true; break }
    }

    $hasAmbiguousSignal = $false
    foreach ($signal in $ambiguitySignals) {
        if ($vectors -contains $signal) { $hasAmbiguousSignal = $true; break }
    }

    if ($hasCrossSignal -and $actual -eq 'BLOCK') { $script:cross_timeline_rejected_count++ }
    if ($hasAmbiguousSignal -and $actual -eq 'BLOCK') { $script:ambiguous_timeline_rejected_count++ }
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'ALLOW') { $script:undetected_cross_timeline_acceptance_count++ }
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
if ($canonicalEntries.Count -lt 4) { throw 'Baseline ledger must contain at least 4 entries for concurrent cross-timeline validation.' }

$currentLength = $canonicalEntries.Count
$currentLatestEntry = $canonicalEntries[$currentLength - 1]
$currentLatest = [string]$currentLatestEntry.entry_id
$currentLatestNum = Get-EntryIdNumber -EntryId $currentLatest
$currentLedgerHash = Get-LedgerSnapshotHash -Ledger $baselineLedger
$currentChainSig = Build-ChainSignature -Entries $canonicalEntries
$currentLedgerHead = [string]$currentLatestEntry.fingerprint_hash
$currentLatestTimestamp = Get-UtcDateTime -Timestamp ([string]$currentLatestEntry.timestamp_utc)
$currentArt111Timestamp = Get-UtcDateTime -Timestamp ([string]$baselineArt111.timestamp_utc)
$currentArt112Timestamp = Get-UtcDateTime -Timestamp ([string]$baselineArt112.timestamp_utc)

if ($null -eq $currentLatestTimestamp) { throw 'Current latest ledger timestamp is invalid.' }
if ($null -eq $currentArt111Timestamp) { throw 'Current art111 timestamp is invalid.' }
if ($null -eq $currentArt112Timestamp) { throw 'Current art112 timestamp is invalid.' }

$trusted = @{
    current_ledger_snapshot_hash = $currentLedgerHash
    current_chain_signature = $currentChainSig
    current_ledger_head_hash = $currentLedgerHead
    current_art111_head_hash_anchor = [string]$baselineArt111.ledger_head_hash
    current_art112_head_hash_anchor = [string]$baselineArt112.ledger_head_hash
    current_art112_baseline_snapshot_hash = [string]$baselineArt112.baseline_snapshot_hash
    current_ledger_length = $currentLength
    current_latest_entry_id = $currentLatest
    current_latest_entry_num = $currentLatestNum
    current_latest_entry_timestamp = $currentLatestTimestamp
    current_art111_timestamp = $currentArt111Timestamp
    current_art112_timestamp = $currentArt112Timestamp
}

function New-LiveState {
    $state = @{
        ledger = Copy-Deep -Object $baselineLedger
        art111 = Copy-Deep -Object $baselineArt111
        art112 = Copy-Deep -Object $baselineArt112
        timeline_uniqueness_proof = ''
        timeline_candidates = @()
        concurrent_contexts = @()
    }
    [void](Set-StateTimelineIdentity -State $state)
    return $state
}

$trusted.current_timeline_proof = (New-LiveState).timeline_uniqueness_proof

$oldCount = $currentLength - 2
$oldEntries = @($canonicalEntries[0..($oldCount - 1)])
$oldLedger = @{ entries = $oldEntries }
$oldArtifacts = Build-ArtifactsFromLedger -Ledger $oldLedger -BaselineArt111 $baselineArt111 -BaselineArt112 $baselineArt112 -TimestampUtc ([string]$oldEntries[$oldEntries.Count - 1].timestamp_utc)

$forkPoint = [Math]::Max(3, $currentLength - 4)
$forkLedger = New-ForkedLedger -CanonicalEntries $canonicalEntries -ForkIndex $forkPoint -TargetCount $currentLength -Salt 'cross_timeline_fork'
$forkRecentArtifacts = Build-ArtifactsFromLedger -Ledger $forkLedger -BaselineArt111 $baselineArt111 -BaselineArt112 $baselineArt112 -TimestampUtc ([string]$currentLatestEntry.timestamp_utc)

$forkRecentState = @{
    ledger = Copy-Deep -Object $forkLedger
    art111 = Copy-Deep -Object $forkRecentArtifacts.art111
    art112 = Copy-Deep -Object $forkRecentArtifacts.art112
}
$forkTimelineProof = Get-ContextTimelineProof -Ledger $forkRecentState.ledger -Art111 $forkRecentState.art111 -Art112 $forkRecentState.art112

$oldTimelineProof = Get-ContextTimelineProof -Ledger $oldLedger -Art111 $oldArtifacts.art111 -Art112 $oldArtifacts.art112

[void]$script:CanonicalTimelineFreshnessLineageMap.Add('CANONICAL_TIMELINE_PROOF=' + $trusted.current_timeline_proof)
[void]$script:CanonicalTimelineFreshnessLineageMap.Add('CANONICAL_CHAIN_SIGNATURE=' + $trusted.current_chain_signature)
[void]$script:CanonicalTimelineFreshnessLineageMap.Add('CANONICAL_LEDGER_HASH=' + $trusted.current_ledger_snapshot_hash)
[void]$script:CanonicalTimelineFreshnessLineageMap.Add('CANONICAL_LATEST=' + $trusted.current_latest_entry_id)
[void]$script:CanonicalTimelineFreshnessLineageMap.Add('CANONICAL_TIMESTAMPS=ledger_latest:' + [string]$currentLatestEntry.timestamp_utc + ';art111:' + [string]$baselineArt111.timestamp_utc + ';art112:' + [string]$baselineArt112.timestamp_utc)
[void]$script:CanonicalTimelineFreshnessLineageMap.Add('STALE_TIMELINE_PROOF=' + $oldTimelineProof)
[void]$script:CanonicalTimelineFreshnessLineageMap.Add('FORK_TIMELINE_PROOF=' + $forkTimelineProof)
[void]$script:CanonicalTimelineFreshnessLineageMap.Add('TIMELINE_UNIQUENESS_RULE=accepted_state_must_map_to_exactly_one_canonical_current_timeline')
[void]$script:CanonicalTimelineFreshnessLineageMap.Add('CONCURRENT_CONTEXT_RULE=no_concurrent_context_may_observe_a_different_timeline')
[void]$script:CanonicalTimelineFreshnessLineageMap.Add('CROSS_TIMELINE_RULE=ledger_and_metadata_must_belong_to_single_current_timeline')

# A) Stale + current concurrent mix block.
$stateA = New-LiveState
$stateA.concurrent_contexts = @(
    (New-Context -Ledger $baselineLedger -Art111 $baselineArt111 -Art112 $baselineArt112),
    (New-Context -Ledger $oldLedger -Art111 $oldArtifacts.art111 -Art112 $oldArtifacts.art112)
)
$resultA = Invoke-GuardedCycle -State $stateA -Trusted $trusted
Add-CaseResult -Id 'A' -Name 'stale_current_concurrent_mix_block' -ExpectedResult 'BLOCK' -CycleResult $resultA

# B) Fork + freshness convergence attack.
$stateB = New-LiveState
$stateB.ledger = Copy-Deep -Object $forkLedger
$stateB.art111 = Copy-Deep -Object $forkRecentArtifacts.art111
$stateB.art112 = Copy-Deep -Object $forkRecentArtifacts.art112
$stateB.timeline_uniqueness_proof = $forkTimelineProof
$stateB.timeline_candidates = @($forkTimelineProof)
$resultB = Invoke-GuardedCycle -State $stateB -Trusted $trusted
Add-CaseResult -Id 'B' -Name 'fork_freshness_convergence_attack' -ExpectedResult 'BLOCK' -CycleResult $resultB

# C) Cross-timeline artifact set.
$stateC = New-LiveState
$stateC.ledger = Copy-Deep -Object $oldLedger
$stateC.art111 = Copy-Deep -Object $baselineArt111
$stateC.art112 = Copy-Deep -Object $oldArtifacts.art112
[void](Set-StateTimelineIdentity -State $stateC)
$resultC = Invoke-GuardedCycle -State $stateC -Trusted $trusted
Add-CaseResult -Id 'C' -Name 'cross_timeline_artifact_set' -ExpectedResult 'BLOCK' -CycleResult $resultC

# D) Same-content different-timeline attack.
$stateD = New-LiveState
$stateD.ledger = Copy-Deep -Object $oldLedger
$stateD.art111 = Copy-Deep -Object $oldArtifacts.art111
$stateD.art112 = Copy-Deep -Object $oldArtifacts.art112
$stateD.art111.timestamp_utc = [string]$baselineArt111.timestamp_utc
$stateD.art112.timestamp_utc = [string]$baselineArt112.timestamp_utc
$stateD.timeline_uniqueness_proof = ''
$stateD.timeline_candidates = @($trusted.current_timeline_proof, $oldTimelineProof)
$resultD = Invoke-GuardedCycle -State $stateD -Trusted $trusted
Add-CaseResult -Id 'D' -Name 'same_content_different_timeline_attack' -ExpectedResult 'BLOCK' -CycleResult $resultD

# E) Resealed cross-timeline state.
$stateE = New-LiveState
$stateE.ledger = Copy-Deep -Object $forkLedger
$stateE.art111 = Copy-Deep -Object $forkRecentArtifacts.art111
$stateE.art112 = Copy-Deep -Object $oldArtifacts.art112
[void](Set-StateTimelineIdentity -State $stateE)
$resultE = Invoke-GuardedCycle -State $stateE -Trusted $trusted
Add-CaseResult -Id 'E' -Name 'resealed_cross_timeline_state' -ExpectedResult 'BLOCK' -CycleResult $resultE

# F) Concurrent guarded-boundary timeline swap.
$stateF = New-LiveState
$resultF = Invoke-GuardedCycle -State $stateF -Trusted $trusted -RuntimeMutation {
    param([hashtable]$State, [hashtable]$Trusted)
    $State.concurrent_contexts = @(
        (New-Context -Ledger $baselineLedger -Art111 $baselineArt111 -Art112 $baselineArt112),
        (New-Context -Ledger $forkLedger -Art111 $forkRecentArtifacts.art111 -Art112 $forkRecentArtifacts.art112)
    )
    $State.ledger = Copy-Deep -Object $forkLedger
    $State.art111 = Copy-Deep -Object $forkRecentArtifacts.art111
    $State.art112 = Copy-Deep -Object $forkRecentArtifacts.art112
    [void](Set-StateTimelineIdentity -State $State)
}
Add-CaseResult -Id 'F' -Name 'concurrent_guarded_boundary_timeline_swap' -ExpectedResult 'BLOCK' -CycleResult $resultF

# G) Timeline uniqueness proof ambiguity.
$stateG = New-LiveState
$stateG.timeline_uniqueness_proof = $trusted.current_timeline_proof
$stateG.timeline_candidates = @($trusted.current_timeline_proof, $forkTimelineProof)
$resultG = Invoke-GuardedCycle -State $stateG -Trusted $trusted
Add-CaseResult -Id 'G' -Name 'timeline_uniqueness_proof_ambiguity' -ExpectedResult 'BLOCK' -CycleResult $resultG

# H) Clean control.
$stateH = New-LiveState
$resultH = Invoke-GuardedCycle -State $stateH -Trusted $trusted
Add-CaseResult -Id 'H' -Name 'clean_control' -ExpectedResult 'ALLOW' -CycleResult $resultH

$consistencyPass = $true
if ($script:CaseMatrix.Count -ne 8) { $consistencyPass = $false }
if (($script:passCount + $script:failCount) -ne 8) { $consistencyPass = $false }
if ($script:undetected_cross_timeline_acceptance_count -ne 0) { $consistencyPass = $false }
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

$attackMatrix = @(
    'CROSS_TIMELINE_ATTACK_MATRIX',
    'A: stale_current_concurrent_mix_block => expect BLOCK',
    'B: fork_freshness_convergence_attack => expect BLOCK',
    'C: cross_timeline_artifact_set => expect BLOCK',
    'D: same_content_different_timeline_attack => expect BLOCK',
    'E: resealed_cross_timeline_state => expect BLOCK',
    'F: concurrent_guarded_boundary_timeline_swap => expect BLOCK',
    'G: timeline_uniqueness_proof_ambiguity => expect BLOCK',
    'H: clean_control => expect ALLOW'
)

Write-ProofFile -Path (Join-Path $PF '01_status.txt') -Content @(
    'PHASE=53.26',
    ('TITLE={0}' -f $Title),
    ('GATE={0}' -f $gate),
    ('PASS_COUNT={0}/8' -f $script:passCount),
    ('FAIL_COUNT={0}' -f $script:failCount),
    ('cross_timeline_rejected_count={0}' -f $script:cross_timeline_rejected_count),
    ('ambiguous_timeline_rejected_count={0}' -f $script:ambiguous_timeline_rejected_count),
    ('undetected_cross_timeline_acceptance_count={0}' -f $script:undetected_cross_timeline_acceptance_count),
    ('false_positive_count={0}' -f $script:false_positive_count),
    ('consistency_check={0}' -f $(if ($consistencyPass) { 'PASS' } else { 'FAIL' })),
    'FAIL_CLOSED=TRUE',
    'NO_FALLBACK=TRUE',
    'NO_SILENT_ACCEPTANCE=TRUE'
)

Write-ProofFile -Path (Join-Path $PF '14_validation_results.txt') -Content $matrixLines
Write-ProofFile -Path (Join-Path $PF '15_cross_timeline_attack_matrix.txt') -Content $attackMatrix
Write-ProofFile -Path (Join-Path $PF '15_canonical_timeline_freshness_lineage_map.txt') -Content $script:CanonicalTimelineFreshnessLineageMap.ToArray()
Write-ProofFile -Path (Join-Path $PF '15_detection_vectors.txt') -Content $vectorLines

Write-ProofFile -Path (Join-Path $PF '98_gate_phase53_26.txt') -Content @(
    ('GATE={0}' -f $gate),
    ('PASS_COUNT={0}/8' -f $script:passCount),
    ('FAIL_COUNT={0}' -f $script:failCount),
    ('cross_timeline_rejected_count={0}' -f $script:cross_timeline_rejected_count),
    ('ambiguous_timeline_rejected_count={0}' -f $script:ambiguous_timeline_rejected_count),
    ('undetected_cross_timeline_acceptance_count={0}' -f $script:undetected_cross_timeline_acceptance_count),
    ('false_positive_count={0}' -f $script:false_positive_count)
)

$zipPath = $PF + '.zip'
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path $PF -DestinationPath $zipPath -Force

Write-Output ('PF=' + $PF)
Write-Output ('ZIP=' + $zipPath)
Write-Output ('GATE=' + $gate)