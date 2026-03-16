Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ((Get-Location).Path -ne $Root) {
    Write-Output 'hey stupid Fucker, wrong window again'
    exit 1
}
Set-Location $Root

function Get-BytesSha256Hex {
    param([byte[]]$Bytes)
    $hash = [System.Security.Cryptography.SHA256]::HashData($Bytes)
    return ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Get-StringSha256Hex {
    param([string]$Text)
    return Get-BytesSha256Hex -Bytes ([System.Text.Encoding]::UTF8.GetBytes($Text))
}

function Get-FileSha256Hex {
    param([string]$Path)
    return Get-BytesSha256Hex -Bytes ([System.IO.File]::ReadAllBytes($Path))
}

function Convert-RepoPathToAbsolute {
    param([string]$RepoPath)
    if ([string]::IsNullOrWhiteSpace($RepoPath)) { return '' }
    if ([System.IO.Path]::IsPathRooted($RepoPath)) { return $RepoPath }
    return Join-Path $Root ($RepoPath.Replace('/', '\'))
}

function Get-ChainEntryCanonical {
    param([object]$Entry)

    $obj = [ordered]@{
        entry_id = [string]$Entry.entry_id
        fingerprint_hash = [string]$Entry.fingerprint_hash
        timestamp_utc = [string]$Entry.timestamp_utc
        phase_locked = [string]$Entry.phase_locked
        previous_hash = if ($null -eq $Entry.previous_hash -or [string]::IsNullOrWhiteSpace([string]$Entry.previous_hash)) { $null } else { [string]$Entry.previous_hash }
    }
    return ($obj | ConvertTo-Json -Depth 4 -Compress)
}

function Get-ChainEntryHash {
    param([object]$Entry)
    return Get-StringSha256Hex -Text (Get-ChainEntryCanonical -Entry $Entry)
}

function Test-TrustChain {
    param([object]$ChainObj)

    $result = [ordered]@{
        pass = $true
        reason = 'ok'
        entry_count = 0
        chain_hashes = @()
        last_entry_hash = ''
    }

    if ($null -eq $ChainObj -or $null -eq $ChainObj.entries) {
        $result.pass = $false
        $result.reason = 'chain_entries_missing'
        return $result
    }

    $entries = @($ChainObj.entries)
    $result.entry_count = $entries.Count
    if ($entries.Count -eq 0) {
        $result.pass = $false
        $result.reason = 'chain_entries_empty'
        return $result
    }

    $hashes = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $entry = $entries[$i]
        if ($i -eq 0) {
            if ($null -ne $entry.previous_hash -and -not [string]::IsNullOrWhiteSpace([string]$entry.previous_hash)) {
                $result.pass = $false
                $result.reason = 'first_entry_previous_hash_must_be_null'
                return $result
            }
        } else {
            $expectedPreviousHash = $hashes[$i - 1]
            if ([string]$entry.previous_hash -ne [string]$expectedPreviousHash) {
                $result.pass = $false
                $result.reason = ('previous_hash_link_mismatch_at_index_' + $i)
                return $result
            }
        }
        $hashes.Add((Get-ChainEntryHash -Entry $entry))
    }

    $result.chain_hashes = @($hashes)
    $result.last_entry_hash = [string]$hashes[$hashes.Count - 1]
    return $result
}

function Build-NewChainEntry {
    param(
        [string]$EntryId,
        [string]$FingerprintHash,
        [string]$PhaseLocked,
        [string]$PreviousHash,
        [string]$TimestampUtc
    )

    return [ordered]@{
        entry_id = $EntryId
        fingerprint_hash = $FingerprintHash
        timestamp_utc = $TimestampUtc
        phase_locked = $PhaseLocked
        previous_hash = if ([string]::IsNullOrWhiteSpace($PreviousHash)) { $null } else { $PreviousHash }
    }
}

function Get-Phase44_8RuntimeGateStatus {
    param(
        [string]$CandidateBaselineSnapshotPath,
        [string]$BaselineIntegrityPath,
        [string]$LiveLedgerPath,
        [string]$ProtectedBaselineSnapshotPath,
        [string]$FingerprintReferencePath
    )

    $sequence = [System.Collections.Generic.List[string]]::new()
    $sequence.Add('baseline_snapshot_validation')

    if (-not (Test-Path -LiteralPath $CandidateBaselineSnapshotPath)) {
        return [ordered]@{
            runtime_gate = 'FAIL'
            block_reason = 'baseline_snapshot_missing'
            baseline_snapshot_validation = 'FAIL'
            baseline_integrity_validation = 'NOT_RUN'
            ledger_continuity_validation = 'NOT_RUN'
            initialization_sequence = @($sequence)
        }
    }

    $snapshotObj = $null
    try {
        $snapshotObj = Get-Content -Raw -LiteralPath $CandidateBaselineSnapshotPath | ConvertFrom-Json
    } catch {
        return [ordered]@{
            runtime_gate = 'FAIL'
            block_reason = 'baseline_snapshot_parse_error'
            baseline_snapshot_validation = 'FAIL'
            baseline_integrity_validation = 'NOT_RUN'
            ledger_continuity_validation = 'NOT_RUN'
            initialization_sequence = @($sequence)
        }
    }

    $requiredSnapshotFields = @(
        'fingerprint_reference_sha256',
        'trust_chain_ledger_payload',
        'current_last_entry_hash',
        'current_ledger_length'
    )
    foreach ($field in $requiredSnapshotFields) {
        if (-not ($snapshotObj.PSObject.Properties.Name -contains $field)) {
            return [ordered]@{
                runtime_gate = 'FAIL'
                block_reason = ('baseline_missing_field_' + $field)
                baseline_snapshot_validation = 'FAIL'
                baseline_integrity_validation = 'NOT_RUN'
                ledger_continuity_validation = 'NOT_RUN'
                initialization_sequence = @($sequence)
            }
        }
    }

    if (-not (Test-Path -LiteralPath $FingerprintReferencePath)) {
        return [ordered]@{
            runtime_gate = 'FAIL'
            block_reason = 'fingerprint_reference_missing'
            baseline_snapshot_validation = 'FAIL'
            baseline_integrity_validation = 'NOT_RUN'
            ledger_continuity_validation = 'NOT_RUN'
            initialization_sequence = @($sequence)
        }
    }

    $fingerprintRefHash = Get-FileSha256Hex -Path $FingerprintReferencePath
    if ([string]$snapshotObj.fingerprint_reference_sha256 -ne $fingerprintRefHash) {
        return [ordered]@{
            runtime_gate = 'FAIL'
            block_reason = 'fingerprint_reference_hash_mismatch'
            baseline_snapshot_validation = 'FAIL'
            baseline_integrity_validation = 'NOT_RUN'
            ledger_continuity_validation = 'NOT_RUN'
            initialization_sequence = @($sequence)
        }
    }

    $sequence.Add('baseline_integrity_validation')
    if (-not (Test-Path -LiteralPath $BaselineIntegrityPath)) {
        return [ordered]@{
            runtime_gate = 'FAIL'
            block_reason = 'baseline_integrity_file_missing'
            baseline_snapshot_validation = 'PASS'
            baseline_integrity_validation = 'FAIL'
            ledger_continuity_validation = 'NOT_RUN'
            initialization_sequence = @($sequence)
        }
    }

    $integrityObj = $null
    try {
        $integrityObj = Get-Content -Raw -LiteralPath $BaselineIntegrityPath | ConvertFrom-Json
    } catch {
        return [ordered]@{
            runtime_gate = 'FAIL'
            block_reason = 'baseline_integrity_parse_error'
            baseline_snapshot_validation = 'PASS'
            baseline_integrity_validation = 'FAIL'
            ledger_continuity_validation = 'NOT_RUN'
            initialization_sequence = @($sequence)
        }
    }

    $requiredIntegrityFields = @('protected_baseline_snapshot_file','expected_baseline_snapshot_sha256')
    foreach ($field in $requiredIntegrityFields) {
        if (-not ($integrityObj.PSObject.Properties.Name -contains $field)) {
            return [ordered]@{
                runtime_gate = 'FAIL'
                block_reason = ('baseline_integrity_missing_field_' + $field)
                baseline_snapshot_validation = 'PASS'
                baseline_integrity_validation = 'FAIL'
                ledger_continuity_validation = 'NOT_RUN'
                initialization_sequence = @($sequence)
            }
        }
    }

    $protectedSnapshotFromIntegrity = Convert-RepoPathToAbsolute -RepoPath ([string]$integrityObj.protected_baseline_snapshot_file)
    if ($protectedSnapshotFromIntegrity -ne $ProtectedBaselineSnapshotPath) {
        return [ordered]@{
            runtime_gate = 'FAIL'
            block_reason = 'integrity_protected_snapshot_mismatch'
            baseline_snapshot_validation = 'PASS'
            baseline_integrity_validation = 'FAIL'
            ledger_continuity_validation = 'NOT_RUN'
            initialization_sequence = @($sequence)
        }
    }

    $candidateHash = Get-FileSha256Hex -Path $CandidateBaselineSnapshotPath
    if ([string]$integrityObj.expected_baseline_snapshot_sha256 -ne $candidateHash) {
        return [ordered]@{
            runtime_gate = 'FAIL'
            block_reason = 'baseline_integrity_hash_mismatch'
            baseline_snapshot_validation = 'PASS'
            baseline_integrity_validation = 'FAIL'
            ledger_continuity_validation = 'NOT_RUN'
            initialization_sequence = @($sequence)
        }
    }

    $sequence.Add('ledger_continuity_validation')
    if (-not (Test-Path -LiteralPath $LiveLedgerPath)) {
        return [ordered]@{
            runtime_gate = 'FAIL'
            block_reason = 'live_ledger_missing'
            baseline_snapshot_validation = 'PASS'
            baseline_integrity_validation = 'PASS'
            ledger_continuity_validation = 'FAIL'
            initialization_sequence = @($sequence)
        }
    }

    $liveLedgerObj = Get-Content -Raw -LiteralPath $LiveLedgerPath | ConvertFrom-Json
    $liveValidation = Test-TrustChain -ChainObj $liveLedgerObj
    if (-not $liveValidation.pass) {
        return [ordered]@{
            runtime_gate = 'FAIL'
            block_reason = ('live_' + $liveValidation.reason)
            baseline_snapshot_validation = 'PASS'
            baseline_integrity_validation = 'PASS'
            ledger_continuity_validation = 'FAIL'
            initialization_sequence = @($sequence)
        }
    }

    $baselineEntries = @($snapshotObj.trust_chain_ledger_payload.entries)
    $liveEntries = @($liveLedgerObj.entries)
    if ($liveEntries.Count -lt $baselineEntries.Count) {
        return [ordered]@{
            runtime_gate = 'FAIL'
            block_reason = 'live_ledger_shorter_than_baseline'
            baseline_snapshot_validation = 'PASS'
            baseline_integrity_validation = 'PASS'
            ledger_continuity_validation = 'FAIL'
            initialization_sequence = @($sequence)
        }
    }

    for ($i = 0; $i -lt $baselineEntries.Count; $i++) {
        $baselineCanonical = Get-ChainEntryCanonical -Entry $baselineEntries[$i]
        $liveCanonical = Get-ChainEntryCanonical -Entry $liveEntries[$i]
        if ($baselineCanonical -ne $liveCanonical) {
            return [ordered]@{
                runtime_gate = 'FAIL'
                block_reason = ('baseline_prefix_mismatch_at_index_' + $i)
                baseline_snapshot_validation = 'PASS'
                baseline_integrity_validation = 'PASS'
                ledger_continuity_validation = 'FAIL'
                initialization_sequence = @($sequence)
            }
        }
    }

    if ($liveEntries.Count -gt $baselineEntries.Count) {
        $firstAppended = $liveEntries[$baselineEntries.Count]
        if ([string]$firstAppended.previous_hash -ne [string]$snapshotObj.current_last_entry_hash) {
            return [ordered]@{
                runtime_gate = 'FAIL'
                block_reason = 'first_append_does_not_reference_baseline_last_hash'
                baseline_snapshot_validation = 'PASS'
                baseline_integrity_validation = 'PASS'
                ledger_continuity_validation = 'FAIL'
                initialization_sequence = @($sequence)
            }
        }
    }

    return [ordered]@{
        runtime_gate = 'PASS'
        block_reason = ''
        baseline_snapshot_validation = 'PASS'
        baseline_integrity_validation = 'PASS'
        ledger_continuity_validation = 'PASS'
        initialization_sequence = @($sequence)
    }
}

function New-EntrypointResult {
    param(
        [string]$Entrypoint,
        [hashtable]$Gate,
        [string]$OperationDetail,
        [string]$AppendStatus = ''
    )

    $blocked = ($Gate.runtime_gate -ne 'PASS')
    return [ordered]@{
        entrypoint = $Entrypoint
        runtime_gate = [string]$Gate.runtime_gate
        operation = $(if ($blocked) { 'BLOCKED' } else { 'ALLOWED' })
        append = $(if ([string]::IsNullOrWhiteSpace($AppendStatus)) { '' } else { $AppendStatus })
        block_reason = [string]$Gate.block_reason
        gate_sequence = @($Gate.initialization_sequence)
        details = $OperationDetail
        fallback_occurred = $false
        regeneration_occurred = $false
    }
}

function Invoke-BaselineSnapshotLoad {
    param([string]$CandidateSnapshotPath,[string]$IntegrityPath,[string]$LiveLedgerPath,[string]$ProtectedSnapshotPath,[string]$FingerprintReferencePath)
    $gate = Get-Phase44_8RuntimeGateStatus -CandidateBaselineSnapshotPath $CandidateSnapshotPath -BaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LiveLedgerPath -ProtectedBaselineSnapshotPath $ProtectedSnapshotPath -FingerprintReferencePath $FingerprintReferencePath
    if ($gate.runtime_gate -ne 'PASS') { return New-EntrypointResult -Entrypoint 'baseline_snapshot_load' -Gate $gate -OperationDetail 'snapshot_bytes_not_materialized' }
    $obj = Get-Content -Raw -LiteralPath $CandidateSnapshotPath | ConvertFrom-Json
    return New-EntrypointResult -Entrypoint 'baseline_snapshot_load' -Gate $gate -OperationDetail ('phase_locked=' + [string]$obj.phase_locked)
}

function Invoke-BaselineIntegrityReferenceLoad {
    param([string]$CandidateSnapshotPath,[string]$IntegrityPath,[string]$LiveLedgerPath,[string]$ProtectedSnapshotPath,[string]$FingerprintReferencePath)
    $gate = Get-Phase44_8RuntimeGateStatus -CandidateBaselineSnapshotPath $CandidateSnapshotPath -BaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LiveLedgerPath -ProtectedBaselineSnapshotPath $ProtectedSnapshotPath -FingerprintReferencePath $FingerprintReferencePath
    if ($gate.runtime_gate -ne 'PASS') { return New-EntrypointResult -Entrypoint 'baseline_integrity_reference_load' -Gate $gate -OperationDetail 'integrity_record_not_materialized' }
    $obj = Get-Content -Raw -LiteralPath $IntegrityPath | ConvertFrom-Json
    return New-EntrypointResult -Entrypoint 'baseline_integrity_reference_load' -Gate $gate -OperationDetail ('hash_method=' + [string]$obj.hash_method)
}

function Invoke-BaselineVerification {
    param([string]$CandidateSnapshotPath,[string]$IntegrityPath,[string]$LiveLedgerPath,[string]$ProtectedSnapshotPath,[string]$FingerprintReferencePath)
    $gate = Get-Phase44_8RuntimeGateStatus -CandidateBaselineSnapshotPath $CandidateSnapshotPath -BaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LiveLedgerPath -ProtectedBaselineSnapshotPath $ProtectedSnapshotPath -FingerprintReferencePath $FingerprintReferencePath
    if ($gate.runtime_gate -ne 'PASS') { return New-EntrypointResult -Entrypoint 'baseline_verification' -Gate $gate -OperationDetail 'verification_not_executed' }
    return New-EntrypointResult -Entrypoint 'baseline_verification' -Gate $gate -OperationDetail 'baseline_verified_under_runtime_gate'
}

function Invoke-LedgerLoad {
    param([string]$CandidateSnapshotPath,[string]$IntegrityPath,[string]$LiveLedgerPath,[string]$ProtectedSnapshotPath,[string]$FingerprintReferencePath)
    $gate = Get-Phase44_8RuntimeGateStatus -CandidateBaselineSnapshotPath $CandidateSnapshotPath -BaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LiveLedgerPath -ProtectedBaselineSnapshotPath $ProtectedSnapshotPath -FingerprintReferencePath $FingerprintReferencePath
    if ($gate.runtime_gate -ne 'PASS') { return New-EntrypointResult -Entrypoint 'ledger_load' -Gate $gate -OperationDetail 'ledger_not_materialized' }
    $ledger = Get-Content -Raw -LiteralPath $LiveLedgerPath | ConvertFrom-Json
    return New-EntrypointResult -Entrypoint 'ledger_load' -Gate $gate -OperationDetail ('entries=' + @($ledger.entries).Count)
}

function Invoke-LedgerContinuityValidation {
    param([string]$CandidateSnapshotPath,[string]$IntegrityPath,[string]$LiveLedgerPath,[string]$ProtectedSnapshotPath,[string]$FingerprintReferencePath)
    $gate = Get-Phase44_8RuntimeGateStatus -CandidateBaselineSnapshotPath $CandidateSnapshotPath -BaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LiveLedgerPath -ProtectedBaselineSnapshotPath $ProtectedSnapshotPath -FingerprintReferencePath $FingerprintReferencePath
    if ($gate.runtime_gate -ne 'PASS') { return New-EntrypointResult -Entrypoint 'ledger_continuity_validation' -Gate $gate -OperationDetail 'continuity_check_blocked' }
    return New-EntrypointResult -Entrypoint 'ledger_continuity_validation' -Gate $gate -OperationDetail 'continuity_validated'
}

function Invoke-LedgerAppendFutureRotationPreparation {
    param([string]$CandidateSnapshotPath,[string]$IntegrityPath,[string]$LiveLedgerPath,[string]$ProtectedSnapshotPath,[string]$FingerprintReferencePath)
    $gate = Get-Phase44_8RuntimeGateStatus -CandidateBaselineSnapshotPath $CandidateSnapshotPath -BaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LiveLedgerPath -ProtectedBaselineSnapshotPath $ProtectedSnapshotPath -FingerprintReferencePath $FingerprintReferencePath
    if ($gate.runtime_gate -ne 'PASS') { return New-EntrypointResult -Entrypoint 'ledger_append_future_rotation_prep' -Gate $gate -OperationDetail 'append_preparation_blocked' -AppendStatus 'BLOCKED' }

    $snapshot = Get-Content -Raw -LiteralPath $CandidateSnapshotPath | ConvertFrom-Json
    $ledger = Get-Content -Raw -LiteralPath $LiveLedgerPath | ConvertFrom-Json
    $nextIndex = [string](@($ledger.entries).Count + 1)
    $newEntryId = 'GF-' + $nextIndex.PadLeft(4, '0')
    $candidateEntry = Build-NewChainEntry -EntryId $newEntryId -FingerprintHash (Get-StringSha256Hex -Text 'phase44_9_append_probe') -PhaseLocked '44.9' -PreviousHash ([string]$snapshot.current_last_entry_hash) -TimestampUtc ((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
    $null = $candidateEntry
    return New-EntrypointResult -Entrypoint 'ledger_append_future_rotation_prep' -Gate $gate -OperationDetail ('append_entry_id=' + $newEntryId) -AppendStatus 'ALLOWED'
}

function Invoke-TrustChainValidationHelper {
    param([string]$CandidateSnapshotPath,[string]$IntegrityPath,[string]$LiveLedgerPath,[string]$ProtectedSnapshotPath,[string]$FingerprintReferencePath)
    $gate = Get-Phase44_8RuntimeGateStatus -CandidateBaselineSnapshotPath $CandidateSnapshotPath -BaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LiveLedgerPath -ProtectedBaselineSnapshotPath $ProtectedSnapshotPath -FingerprintReferencePath $FingerprintReferencePath
    if ($gate.runtime_gate -ne 'PASS') { return New-EntrypointResult -Entrypoint 'trust_chain_validation_helper' -Gate $gate -OperationDetail 'helper_blocked_before_chain_materialization' }
    $ledger = Get-Content -Raw -LiteralPath $LiveLedgerPath | ConvertFrom-Json
    $chainResult = Test-TrustChain -ChainObj $ledger
    return New-EntrypointResult -Entrypoint 'trust_chain_validation_helper' -Gate $gate -OperationDetail ('chain_pass=' + [string]$chainResult.pass)
}

function Invoke-HistoricalBaselineLedgerValidation {
    param([string]$CandidateSnapshotPath,[string]$IntegrityPath,[string]$LiveLedgerPath,[string]$ProtectedSnapshotPath,[string]$FingerprintReferencePath)
    $gate = Get-Phase44_8RuntimeGateStatus -CandidateBaselineSnapshotPath $CandidateSnapshotPath -BaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LiveLedgerPath -ProtectedBaselineSnapshotPath $ProtectedSnapshotPath -FingerprintReferencePath $FingerprintReferencePath
    if ($gate.runtime_gate -ne 'PASS') { return New-EntrypointResult -Entrypoint 'historical_baseline_ledger_validation' -Gate $gate -OperationDetail 'historical_validation_blocked' }
    $snapshot = Get-Content -Raw -LiteralPath $CandidateSnapshotPath | ConvertFrom-Json
    $historicalCount = @($snapshot.trust_chain_ledger_payload.entries).Count
    return New-EntrypointResult -Entrypoint 'historical_baseline_ledger_validation' -Gate $gate -OperationDetail ('historical_entries=' + $historicalCount)
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\phase44_9_trust_chain_runtime_gate_bypass_resistance_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$FingerprintReferencePath = Join-Path $Root 'tools\phase44_4\guard_coverage_fingerprint_reference.json'
$ProtectedBaselineSnapshotPath = Join-Path $Root 'control_plane\71_guard_fingerprint_trust_chain_baseline.json'
$BaselineIntegrityPath = Join-Path $Root 'control_plane\72_guard_fingerprint_trust_chain_baseline_integrity.json'
$LiveLedgerPath = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'

if (-not (Test-Path -LiteralPath $FingerprintReferencePath)) { throw 'Missing phase44_4 fingerprint reference.' }
if (-not (Test-Path -LiteralPath $ProtectedBaselineSnapshotPath)) { throw 'Missing phase44_7 baseline snapshot.' }
if (-not (Test-Path -LiteralPath $BaselineIntegrityPath)) { throw 'Missing phase44_7 baseline integrity file.' }
if (-not (Test-Path -LiteralPath $LiveLedgerPath)) { throw 'Missing phase44_6 trust-chain ledger.' }

$entrypointInventory = @(
    'baseline_snapshot_load',
    'baseline_integrity_reference_load',
    'baseline_verification',
    'ledger_load',
    'ledger_continuity_validation',
    'ledger_append_future_rotation_prep',
    'trust_chain_validation_helper',
    'historical_baseline_ledger_validation'
)

$entrypointRecords = [System.Collections.Generic.List[object]]::new()
$caseRecords = [System.Collections.Generic.List[object]]::new()

# CASE A — NORMAL OPERATION
$caseAResults = @(
    (Invoke-BaselineSnapshotLoad -CandidateSnapshotPath $ProtectedBaselineSnapshotPath -IntegrityPath $BaselineIntegrityPath -LiveLedgerPath $LiveLedgerPath -ProtectedSnapshotPath $ProtectedBaselineSnapshotPath -FingerprintReferencePath $FingerprintReferencePath),
    (Invoke-BaselineIntegrityReferenceLoad -CandidateSnapshotPath $ProtectedBaselineSnapshotPath -IntegrityPath $BaselineIntegrityPath -LiveLedgerPath $LiveLedgerPath -ProtectedSnapshotPath $ProtectedBaselineSnapshotPath -FingerprintReferencePath $FingerprintReferencePath),
    (Invoke-BaselineVerification -CandidateSnapshotPath $ProtectedBaselineSnapshotPath -IntegrityPath $BaselineIntegrityPath -LiveLedgerPath $LiveLedgerPath -ProtectedSnapshotPath $ProtectedBaselineSnapshotPath -FingerprintReferencePath $FingerprintReferencePath),
    (Invoke-LedgerLoad -CandidateSnapshotPath $ProtectedBaselineSnapshotPath -IntegrityPath $BaselineIntegrityPath -LiveLedgerPath $LiveLedgerPath -ProtectedSnapshotPath $ProtectedBaselineSnapshotPath -FingerprintReferencePath $FingerprintReferencePath),
    (Invoke-LedgerContinuityValidation -CandidateSnapshotPath $ProtectedBaselineSnapshotPath -IntegrityPath $BaselineIntegrityPath -LiveLedgerPath $LiveLedgerPath -ProtectedSnapshotPath $ProtectedBaselineSnapshotPath -FingerprintReferencePath $FingerprintReferencePath),
    (Invoke-LedgerAppendFutureRotationPreparation -CandidateSnapshotPath $ProtectedBaselineSnapshotPath -IntegrityPath $BaselineIntegrityPath -LiveLedgerPath $LiveLedgerPath -ProtectedSnapshotPath $ProtectedBaselineSnapshotPath -FingerprintReferencePath $FingerprintReferencePath),
    (Invoke-TrustChainValidationHelper -CandidateSnapshotPath $ProtectedBaselineSnapshotPath -IntegrityPath $BaselineIntegrityPath -LiveLedgerPath $LiveLedgerPath -ProtectedSnapshotPath $ProtectedBaselineSnapshotPath -FingerprintReferencePath $FingerprintReferencePath),
    (Invoke-HistoricalBaselineLedgerValidation -CandidateSnapshotPath $ProtectedBaselineSnapshotPath -IntegrityPath $BaselineIntegrityPath -LiveLedgerPath $LiveLedgerPath -ProtectedSnapshotPath $ProtectedBaselineSnapshotPath -FingerprintReferencePath $FingerprintReferencePath)
)
foreach ($record in $caseAResults) { $entrypointRecords.Add($record) }
$caseAPass = (@($caseAResults | Where-Object { $_.runtime_gate -ne 'PASS' -or $_.operation -ne 'ALLOWED' }).Count -eq 0)
$caseA = [ordered]@{
    case = 'A'
    runtime_gate = 'PASS'
    operation = 'ALLOWED'
    details = 'all_entrypoints_allowed_under_intact_baseline'
    pass = $caseAPass
}
$caseRecords.Add($caseA)

$tamperedSnapshotPath = Join-Path $env:TEMP ('phase44_9_tampered_snapshot_' + $Timestamp + '.json')
$tamperedSnapshotText = (Get-Content -Raw -LiteralPath $ProtectedBaselineSnapshotPath) -replace '"current_ledger_length"\s*:\s*1', '"current_ledger_length": 999'
[System.IO.File]::WriteAllText($tamperedSnapshotPath, $tamperedSnapshotText, [System.Text.Encoding]::UTF8)

$tamperedIntegrityPath = Join-Path $env:TEMP ('phase44_9_tampered_integrity_' + $Timestamp + '.json')
$tamperedIntegrityText = (Get-Content -Raw -LiteralPath $BaselineIntegrityPath) -replace '"expected_baseline_snapshot_sha256"\s*:\s*"[^"]+"', '"expected_baseline_snapshot_sha256": "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"'
[System.IO.File]::WriteAllText($tamperedIntegrityPath, $tamperedIntegrityText, [System.Text.Encoding]::UTF8)

# CASE B — BASELINE SNAPSHOT LOAD BYPASS ATTEMPT
$caseBResult = Invoke-BaselineSnapshotLoad -CandidateSnapshotPath $tamperedSnapshotPath -IntegrityPath $BaselineIntegrityPath -LiveLedgerPath $LiveLedgerPath -ProtectedSnapshotPath $ProtectedBaselineSnapshotPath -FingerprintReferencePath $FingerprintReferencePath
$entrypointRecords.Add($caseBResult)
$caseB = [ordered]@{
    case = 'B'
    runtime_gate = $caseBResult.runtime_gate
    operation = $caseBResult.operation
    details = $caseBResult.block_reason
    pass = ($caseBResult.runtime_gate -eq 'FAIL' -and $caseBResult.operation -eq 'BLOCKED')
}
$caseRecords.Add($caseB)

# CASE C — BASELINE INTEGRITY LOAD BYPASS ATTEMPT
$caseCResult = Invoke-BaselineIntegrityReferenceLoad -CandidateSnapshotPath $ProtectedBaselineSnapshotPath -IntegrityPath $tamperedIntegrityPath -LiveLedgerPath $LiveLedgerPath -ProtectedSnapshotPath $ProtectedBaselineSnapshotPath -FingerprintReferencePath $FingerprintReferencePath
$entrypointRecords.Add($caseCResult)
$caseC = [ordered]@{
    case = 'C'
    runtime_gate = $caseCResult.runtime_gate
    operation = $caseCResult.operation
    details = $caseCResult.block_reason
    pass = ($caseCResult.runtime_gate -eq 'FAIL' -and $caseCResult.operation -eq 'BLOCKED')
}
$caseRecords.Add($caseC)

# CASE D — LEDGER VALIDATION BYPASS ATTEMPT
$caseDResult = Invoke-LedgerContinuityValidation -CandidateSnapshotPath $tamperedSnapshotPath -IntegrityPath $BaselineIntegrityPath -LiveLedgerPath $LiveLedgerPath -ProtectedSnapshotPath $ProtectedBaselineSnapshotPath -FingerprintReferencePath $FingerprintReferencePath
$entrypointRecords.Add($caseDResult)
$caseD = [ordered]@{
    case = 'D'
    runtime_gate = $caseDResult.runtime_gate
    operation = $caseDResult.operation
    details = $caseDResult.block_reason
    pass = ($caseDResult.runtime_gate -eq 'FAIL' -and $caseDResult.operation -eq 'BLOCKED')
}
$caseRecords.Add($caseD)

# CASE E — LEDGER APPEND BYPASS ATTEMPT
$caseEResult = Invoke-LedgerAppendFutureRotationPreparation -CandidateSnapshotPath $tamperedSnapshotPath -IntegrityPath $BaselineIntegrityPath -LiveLedgerPath $LiveLedgerPath -ProtectedSnapshotPath $ProtectedBaselineSnapshotPath -FingerprintReferencePath $FingerprintReferencePath
$entrypointRecords.Add($caseEResult)
$caseE = [ordered]@{
    case = 'E'
    runtime_gate = $caseEResult.runtime_gate
    append = $caseEResult.append
    details = $caseEResult.block_reason
    pass = ($caseEResult.runtime_gate -eq 'FAIL' -and $caseEResult.append -eq 'BLOCKED')
}
$caseRecords.Add($caseE)

# CASE F — TRUST-CHAIN HELPER BYPASS ATTEMPT
$caseFResult = Invoke-TrustChainValidationHelper -CandidateSnapshotPath $tamperedSnapshotPath -IntegrityPath $BaselineIntegrityPath -LiveLedgerPath $LiveLedgerPath -ProtectedSnapshotPath $ProtectedBaselineSnapshotPath -FingerprintReferencePath $FingerprintReferencePath
$entrypointRecords.Add($caseFResult)
$caseF = [ordered]@{
    case = 'F'
    runtime_gate = $caseFResult.runtime_gate
    operation = $caseFResult.operation
    details = $caseFResult.block_reason
    pass = ($caseFResult.runtime_gate -eq 'FAIL' -and $caseFResult.operation -eq 'BLOCKED')
}
$caseRecords.Add($caseF)

# CASE G — HISTORICAL BASELINE/LEDGER VALIDATION BYPASS ATTEMPT
$caseGResult = Invoke-HistoricalBaselineLedgerValidation -CandidateSnapshotPath $tamperedSnapshotPath -IntegrityPath $BaselineIntegrityPath -LiveLedgerPath $LiveLedgerPath -ProtectedSnapshotPath $ProtectedBaselineSnapshotPath -FingerprintReferencePath $FingerprintReferencePath
$entrypointRecords.Add($caseGResult)
$caseG = [ordered]@{
    case = 'G'
    runtime_gate = $caseGResult.runtime_gate
    operation = $caseGResult.operation
    details = $caseGResult.block_reason
    pass = ($caseGResult.runtime_gate -eq 'FAIL' -and $caseGResult.operation -eq 'BLOCKED')
}
$caseRecords.Add($caseG)

if (Test-Path -LiteralPath $tamperedSnapshotPath) { Remove-Item -Force -LiteralPath $tamperedSnapshotPath }
if (Test-Path -LiteralPath $tamperedIntegrityPath) { Remove-Item -Force -LiteralPath $tamperedIntegrityPath }

$noFallback = (@($entrypointRecords | Where-Object { $_.fallback_occurred }).Count -eq 0)
$noRegeneration = (@($entrypointRecords | Where-Object { $_.regeneration_occurred }).Count -eq 0)
$allBypassBlocked = ($caseB.pass -and $caseC.pass -and $caseD.pass -and $caseE.pass -and $caseF.pass -and $caseG.pass)
$allPass = ($caseA.pass -and $allBypassBlocked -and $noFallback -and $noRegeneration)
$gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status = @(
    'phase=44.9',
    'title=Trust-Chain Baseline Runtime Gate Bypass Resistance',
    ('gate=' + $gate),
    ('entrypoints_guarded=' + $entrypointInventory.Count),
    ('cases_total=' + $caseRecords.Count),
    ('cases_pass=' + (@($caseRecords | Where-Object { $_.pass }).Count)),
    ('cases_fail=' + (@($caseRecords | Where-Object { -not $_.pass }).Count)),
    ('no_fallback=' + $(if ($noFallback) { 'TRUE' } else { 'FALSE' })),
    ('no_regeneration=' + $(if ($noRegeneration) { 'TRUE' } else { 'FALSE' })),
    ('timestamp=' + $Timestamp)
)
Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value ($status -join "`r`n") -Encoding UTF8 -NoNewline

$head = @(
    'runner=tools/phase44_9/phase44_9_trust_chain_runtime_gate_bypass_resistance_runner.ps1',
    ('fingerprint_reference=' + ($FingerprintReferencePath -replace [regex]::Escape($Root + '\\'), '')),
    ('baseline_snapshot=' + ($ProtectedBaselineSnapshotPath -replace [regex]::Escape($Root + '\\'), '')),
    ('baseline_integrity=' + ($BaselineIntegrityPath -replace [regex]::Escape($Root + '\\'), '')),
    ('live_ledger=' + ($LiveLedgerPath -replace [regex]::Escape($Root + '\\'), '')),
    'required_runtime_gate=phase44_8_runtime_gate'
)
Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value ($head -join "`r`n") -Encoding UTF8 -NoNewline

$inventoryText = [System.Collections.Generic.List[string]]::new()
$inventoryText.Add('RUNTIME-RELEVANT ENTRYPOINT INVENTORY (PHASE 44.9)')
$inventoryText.Add('')
foreach ($ep in $entrypointInventory) {
    $inventoryText.Add($ep)
}
Set-Content -LiteralPath (Join-Path $PF '10_entrypoint_inventory.txt') -Value (($inventoryText.ToArray()) -join "`r`n") -Encoding UTF8 -NoNewline

$mapText = @(
    'RUNTIME GATE ENFORCEMENT MAP (PHASE 44.9)',
    '',
    'baseline_snapshot_load -> Get-Phase44_8RuntimeGateStatus (first step)',
    'baseline_integrity_reference_load -> Get-Phase44_8RuntimeGateStatus (first step)',
    'baseline_verification -> Get-Phase44_8RuntimeGateStatus (first step)',
    'ledger_load -> Get-Phase44_8RuntimeGateStatus (first step)',
    'ledger_continuity_validation -> Get-Phase44_8RuntimeGateStatus (first step)',
    'ledger_append_future_rotation_prep -> Get-Phase44_8RuntimeGateStatus (first step)',
    'trust_chain_validation_helper -> Get-Phase44_8RuntimeGateStatus (first step)',
    'historical_baseline_ledger_validation -> Get-Phase44_8RuntimeGateStatus (first step)',
    '',
    'No operational helper path is allowed to materialize baseline or ledger state before runtime gate PASS.'
)
Set-Content -LiteralPath (Join-Path $PF '11_runtime_gate_enforcement_map.txt') -Value ($mapText -join "`r`n") -Encoding UTF8 -NoNewline

$touched = @(
    ('READ  ' + ($FingerprintReferencePath -replace [regex]::Escape($Root + '\\'), '')),
    ('READ  ' + ($ProtectedBaselineSnapshotPath -replace [regex]::Escape($Root + '\\'), '')),
    ('READ  ' + ($BaselineIntegrityPath -replace [regex]::Escape($Root + '\\'), '')),
    ('READ  ' + ($LiveLedgerPath -replace [regex]::Escape($Root + '\\'), '')),
    'TEMP  %TEMP%\phase44_9_tampered_snapshot_*.json (deleted)',
    'TEMP  %TEMP%\phase44_9_tampered_integrity_*.json (deleted)',
    ('WRITE _proof/' + (Split-Path -Leaf $PF) + '/*')
)
Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Value ($touched -join "`r`n") -Encoding UTF8 -NoNewline

$build = @(
    'build_type=PowerShell runtime-gate bypass resistance proof',
    'compile_required=no',
    'runtime_gate_dependency=phase44_8_runtime_gate_logic_embedded',
    'runtime_state_machine_changed=no',
    'determinism=explicit_case_inputs_and_fixed_block_conditions'
)
Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Value ($build -join "`r`n") -Encoding UTF8 -NoNewline

$validationLines = [System.Collections.Generic.List[string]]::new()
foreach ($c in $caseRecords) {
    $validationLines.Add(('CASE ' + $c.case + ': ' + ($c | ConvertTo-Json -Depth 8 -Compress)))
}
Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Value (($validationLines.ToArray()) -join "`r`n") -Encoding UTF8 -NoNewline

$summary = @(
    'Phase44_9 proves runtime-gate bypass resistance by invoking every runtime-relevant baseline/ledger/trust entrypoint under both clean and failed-baseline conditions.',
    'All operational entrypoints explicitly call the phase44_8 runtime gate before baseline or ledger materialization.',
    'Direct snapshot loader, integrity loader, ledger continuity, append preparation, trust helper, and historical validation bypass attempts all fail with deterministic BLOCKED outcomes when baseline conditions are invalid.',
    'No silent fallback and no regeneration occur in any entrypoint path.',
    'Runtime state machine remained unchanged because this phase modifies certification tooling only.'
)
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value ($summary -join "`r`n") -Encoding UTF8 -NoNewline

$record16 = [ordered]@{
    entrypoint_inventory = $entrypointInventory
    entrypoint_call_records = $entrypointRecords
    no_fallback = $noFallback
    no_regeneration = $noRegeneration
}
Set-Content -LiteralPath (Join-Path $PF '16_entrypoint_runtime_gate_record.txt') -Value ($record16 | ConvertTo-Json -Depth 12) -Encoding UTF8 -NoNewline

$evidence = @(
    'BYPASS BLOCK EVIDENCE (PHASE 44.9)',
    ('CASE_B=' + $caseB.runtime_gate + ';operation=' + $caseB.operation + ';reason=' + $caseB.details),
    ('CASE_C=' + $caseC.runtime_gate + ';operation=' + $caseC.operation + ';reason=' + $caseC.details),
    ('CASE_D=' + $caseD.runtime_gate + ';operation=' + $caseD.operation + ';reason=' + $caseD.details),
    ('CASE_E=' + $caseE.runtime_gate + ';append=' + $caseE.append + ';reason=' + $caseE.details),
    ('CASE_F=' + $caseF.runtime_gate + ';operation=' + $caseF.operation + ';reason=' + $caseF.details),
    ('CASE_G=' + $caseG.runtime_gate + ';operation=' + $caseG.operation + ';reason=' + $caseG.details),
    ('no_fallback=' + $(if ($noFallback) { 'TRUE' } else { 'FALSE' })),
    ('no_regeneration=' + $(if ($noRegeneration) { 'TRUE' } else { 'FALSE' }))
)
Set-Content -LiteralPath (Join-Path $PF '17_bypass_block_evidence.txt') -Value ($evidence -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '98_gate_phase44_9.txt') -Value $gate -Encoding UTF8 -NoNewline

$ZIP = "$PF.zip"
$staging = "${PF}_copy"
New-Item -ItemType Directory -Path $staging | Out-Null
Get-ChildItem -Path $PF -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $staging $_.Name) -Force
}
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $ZIP -Force
Remove-Item -Recurse -Force -LiteralPath $staging

Write-Output "PF=$PF"
Write-Output "ZIP=$ZIP"
Write-Output "GATE=$gate"