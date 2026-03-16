Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$script:Phase44_8ProofDir = ''
trap {
    if (-not [string]::IsNullOrWhiteSpace($script:Phase44_8ProofDir)) {
        $errorPath = Join-Path $script:Phase44_8ProofDir '00_error.txt'
        $errorLines = @(
            ('message=' + $_.Exception.Message),
            $_.InvocationInfo.PositionMessage,
            $_.ScriptStackTrace
        )
        Set-Content -LiteralPath $errorPath -Value ($errorLines -join "`r`n") -Encoding UTF8 -NoNewline
    }
    Write-Output ('ERROR=' + $_.Exception.Message)
    break
}

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

function ConvertTo-CanonicalJsonFromElement {
    param([System.Text.Json.JsonElement]$Element)

    switch ($Element.ValueKind) {
        'Object' {
            $properties = [System.Collections.Generic.List[object]]::new()
            foreach ($property in $Element.EnumerateObject()) {
                $properties.Add([ordered]@{
                    Name = $property.Name
                    Value = (ConvertTo-CanonicalJsonFromElement -Element $property.Value)
                })
            }

            $segments = [System.Collections.Generic.List[string]]::new()
            foreach ($property in ($properties | Sort-Object Name)) {
                $segments.Add((([string]$property.Name | ConvertTo-Json -Compress)) + ':' + [string]$property.Value)
            }

            return '{' + ($segments -join ',') + '}'
        }
        'Array' {
            $items = [System.Collections.Generic.List[string]]::new()
            foreach ($item in $Element.EnumerateArray()) {
                $items.Add((ConvertTo-CanonicalJsonFromElement -Element $item))
            }
            return '[' + ($items -join ',') + ']'
        }
        'String' {
            return ($Element.GetString() | ConvertTo-Json -Compress)
        }
        'Number' {
            return $Element.GetRawText()
        }
        'True' {
            return 'true'
        }
        'False' {
            return 'false'
        }
        'Null' {
            return 'null'
        }
        default {
            return $Element.GetRawText()
        }
    }
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

function Get-BaselineSemanticHash {
    param([string]$BaselinePath)

    $rawJson = Get-Content -Raw -LiteralPath $BaselinePath
    $jsonDocument = [System.Text.Json.JsonDocument]::Parse($rawJson)
    try {
        $canonicalJson = ConvertTo-CanonicalJsonFromElement -Element $jsonDocument.RootElement
        return Get-StringSha256Hex -Text $canonicalJson
    } finally {
        $jsonDocument.Dispose()
    }
}

function Get-BaselineSnapshotValidation {
    param(
        [string]$SnapshotPath,
        [string]$FingerprintReferencePath
    )

    $result = [ordered]@{
        valid = $false
        reason = 'not_checked'
        semantic_hash = ''
        ledger_length = 0
        last_entry_hash = ''
        phase_lock_marker = ''
        fingerprint_reference_match = 'FALSE'
    }

    if (-not (Test-Path -LiteralPath $SnapshotPath)) {
        $result.reason = 'baseline_snapshot_missing'
        return $result
    }

    $snapshotObject = $null
    try {
        $snapshotObject = Get-Content -Raw -LiteralPath $SnapshotPath | ConvertFrom-Json
    } catch {
        $result.reason = 'baseline_snapshot_parse_error'
        return $result
    }

    $requiredFields = @(
        'baseline_kind',
        'snapshot_schema',
        'phase_locked',
        'fingerprint_reference_file',
        'fingerprint_reference_sha256',
        'trust_chain_ledger_file',
        'trust_chain_ledger_payload',
        'current_last_entry_hash',
        'current_ledger_length',
        'current_phase_lock_marker'
    )
    foreach ($field in $requiredFields) {
        if (-not ($snapshotObject.PSObject.Properties.Name -contains $field)) {
            $result.reason = ('baseline_missing_field_' + $field)
            return $result
        }
    }

    if (-not (Test-Path -LiteralPath $FingerprintReferencePath)) {
        $result.reason = 'fingerprint_reference_missing'
        return $result
    }

    $actualFingerprintReferenceHash = Get-FileSha256Hex -Path $FingerprintReferencePath
    if ([string]$snapshotObject.fingerprint_reference_sha256 -ne $actualFingerprintReferenceHash) {
        $result.reason = 'fingerprint_reference_hash_mismatch'
        return $result
    }

    $embeddedLedgerValidation = Test-TrustChain -ChainObj $snapshotObject.trust_chain_ledger_payload
    if (-not $embeddedLedgerValidation.pass) {
        $result.reason = ('embedded_' + $embeddedLedgerValidation.reason)
        return $result
    }

    if ([int]$snapshotObject.current_ledger_length -ne [int]$embeddedLedgerValidation.entry_count) {
        $result.reason = 'baseline_ledger_length_mismatch'
        return $result
    }

    if ([string]$snapshotObject.current_last_entry_hash -ne [string]$embeddedLedgerValidation.last_entry_hash) {
        $result.reason = 'baseline_last_entry_hash_mismatch'
        return $result
    }

    $embeddedEntries = @($snapshotObject.trust_chain_ledger_payload.entries)
    $embeddedLastEntry = $embeddedEntries[$embeddedEntries.Count - 1]
    if ([string]$snapshotObject.current_phase_lock_marker -ne [string]$embeddedLastEntry.phase_locked) {
        $result.reason = 'baseline_phase_lock_marker_mismatch'
        return $result
    }

    $result.semantic_hash = Get-BaselineSemanticHash -BaselinePath $SnapshotPath
    $result.ledger_length = [int]$embeddedLedgerValidation.entry_count
    $result.last_entry_hash = [string]$embeddedLedgerValidation.last_entry_hash
    $result.phase_lock_marker = [string]$embeddedLastEntry.phase_locked
    $result.fingerprint_reference_match = 'TRUE'
    $result.valid = $true
    $result.reason = 'ok'
    return $result
}

function Get-BaselineIntegrityValidation {
    param(
        [string]$CandidateSnapshotPath,
        [string]$IntegrityPath,
        [string]$ProtectedSnapshotPath,
        [string]$FingerprintReferencePath
    )

    $result = [ordered]@{
        valid = $false
        reason = 'not_checked'
        stored_hash = ''
        computed_protected_hash = ''
        candidate_semantic_hash = ''
        protected_semantic_hash = ''
    }

    if (-not (Test-Path -LiteralPath $IntegrityPath)) {
        $result.reason = 'baseline_integrity_file_missing'
        return $result
    }

    $integrityObject = $null
    try {
        $integrityObject = Get-Content -Raw -LiteralPath $IntegrityPath | ConvertFrom-Json
    } catch {
        $result.reason = 'baseline_integrity_parse_error'
        return $result
    }

    $requiredFields = @('protected_baseline_snapshot_file','expected_baseline_snapshot_sha256','hash_method','baseline_kind','phase_locked')
    foreach ($field in $requiredFields) {
        if (-not ($integrityObject.PSObject.Properties.Name -contains $field)) {
            $result.reason = ('baseline_integrity_missing_field_' + $field)
            return $result
        }
    }

    $expectedProtectedPath = Convert-RepoPathToAbsolute -RepoPath ([string]$integrityObject.protected_baseline_snapshot_file)
    if ($expectedProtectedPath -ne $ProtectedSnapshotPath) {
        $result.reason = 'baseline_integrity_protected_path_mismatch'
        return $result
    }

    if (-not (Test-Path -LiteralPath $ProtectedSnapshotPath)) {
        $result.reason = 'protected_baseline_snapshot_missing'
        return $result
    }

    $result.stored_hash = [string]$integrityObject.expected_baseline_snapshot_sha256
    $result.computed_protected_hash = Get-FileSha256Hex -Path $ProtectedSnapshotPath
    if ($result.stored_hash -ne $result.computed_protected_hash) {
        $result.reason = 'baseline_integrity_hash_mismatch'
        return $result
    }

    $candidateValidation = Get-BaselineSnapshotValidation -SnapshotPath $CandidateSnapshotPath -FingerprintReferencePath $FingerprintReferencePath
    if (-not $candidateValidation.valid) {
        $result.reason = $candidateValidation.reason
        return $result
    }

    $protectedValidation = Get-BaselineSnapshotValidation -SnapshotPath $ProtectedSnapshotPath -FingerprintReferencePath $FingerprintReferencePath
    if (-not $protectedValidation.valid) {
        $result.reason = ('protected_' + $protectedValidation.reason)
        return $result
    }

    $result.candidate_semantic_hash = [string]$candidateValidation.semantic_hash
    $result.protected_semantic_hash = [string]$protectedValidation.semantic_hash
    if ($result.candidate_semantic_hash -ne $result.protected_semantic_hash) {
        $result.reason = 'baseline_semantic_mismatch'
        return $result
    }

    $result.valid = $true
    $result.reason = 'ok'
    return $result
}

function Get-LedgerContinuityValidation {
    param(
        [string]$BaselineSnapshotPath,
        [string]$LiveLedgerPath,
        [string]$FingerprintReferencePath
    )

    $result = [ordered]@{
        valid = $false
        reason = 'not_checked'
        live_ledger_length = 0
        baseline_ledger_length = 0
        append_mode = 'NONE'
    }

    if (-not (Test-Path -LiteralPath $LiveLedgerPath)) {
        $result.reason = 'live_ledger_missing'
        return $result
    }

    $baselineValidation = Get-BaselineSnapshotValidation -SnapshotPath $BaselineSnapshotPath -FingerprintReferencePath $FingerprintReferencePath
    if (-not $baselineValidation.valid) {
        $result.reason = ('baseline_' + $baselineValidation.reason)
        return $result
    }

    $baselineSnapshotObject = Get-Content -Raw -LiteralPath $BaselineSnapshotPath | ConvertFrom-Json
    $baselineEntries = @($baselineSnapshotObject.trust_chain_ledger_payload.entries)
    $liveLedgerObject = Get-Content -Raw -LiteralPath $LiveLedgerPath | ConvertFrom-Json
    $liveValidation = Test-TrustChain -ChainObj $liveLedgerObject
    if (-not $liveValidation.pass) {
        $result.reason = ('live_' + $liveValidation.reason)
        return $result
    }

    $liveEntries = @($liveLedgerObject.entries)
    $result.live_ledger_length = $liveEntries.Count
    $result.baseline_ledger_length = $baselineEntries.Count

    if ($liveEntries.Count -lt $baselineEntries.Count) {
        $result.reason = 'live_ledger_shorter_than_baseline'
        return $result
    }

    for ($i = 0; $i -lt $baselineEntries.Count; $i++) {
        $baselineEntryCanonical = Get-ChainEntryCanonical -Entry $baselineEntries[$i]
        $liveEntryCanonical = Get-ChainEntryCanonical -Entry $liveEntries[$i]
        if ($baselineEntryCanonical -ne $liveEntryCanonical) {
            $result.reason = ('baseline_prefix_mismatch_at_index_' + $i)
            return $result
        }
    }

    if ($liveEntries.Count -eq $baselineEntries.Count) {
        $result.append_mode = 'NONE'
        $result.valid = $true
        $result.reason = 'ok'
        return $result
    }

    $result.append_mode = 'APPEND'
    $firstAppendedEntry = $liveEntries[$baselineEntries.Count]
    if ([string]$firstAppendedEntry.previous_hash -ne [string]$baselineSnapshotObject.current_last_entry_hash) {
        $result.reason = 'first_append_does_not_reference_baseline_last_hash'
        return $result
    }

    $result.valid = $true
    $result.reason = 'ok'
    return $result
}

function Invoke-RuntimeEntryGate {
    param(
        [string]$CandidateBaselineSnapshotPath,
        [string]$BaselineIntegrityPath,
        [string]$LiveLedgerPath,
        [string]$ProtectedBaselineSnapshotPath,
        [string]$FingerprintReferencePath
    )

    $sequence = [System.Collections.Generic.List[string]]::new()
    $sequence.Add('baseline_snapshot_validation')

    $snapshotValidation = Get-BaselineSnapshotValidation -SnapshotPath $CandidateBaselineSnapshotPath -FingerprintReferencePath $FingerprintReferencePath
    $baselineSnapshotStatus = if ($snapshotValidation.valid) { 'VALID' } else { 'INVALID' }
    if (-not $snapshotValidation.valid) {
        return [ordered]@{
            baseline_snapshot = $baselineSnapshotStatus
            baseline_integrity = 'INVALID'
            ledger_continuity = 'INVALID'
            runtime_initialization = 'BLOCKED'
            block_reason = $snapshotValidation.reason
            initialization_sequence = @($sequence)
            pass = $false
        }
    }

    $sequence.Add('baseline_integrity_validation')
    $integrityValidation = Get-BaselineIntegrityValidation -CandidateSnapshotPath $CandidateBaselineSnapshotPath -IntegrityPath $BaselineIntegrityPath -ProtectedSnapshotPath $ProtectedBaselineSnapshotPath -FingerprintReferencePath $FingerprintReferencePath
    $baselineIntegrityStatus = if ($integrityValidation.valid) { 'VALID' } else { 'INVALID' }
    if (-not $integrityValidation.valid) {
        return [ordered]@{
            baseline_snapshot = $baselineSnapshotStatus
            baseline_integrity = $baselineIntegrityStatus
            ledger_continuity = 'INVALID'
            runtime_initialization = 'BLOCKED'
            block_reason = $integrityValidation.reason
            initialization_sequence = @($sequence)
            pass = $false
        }
    }

    $sequence.Add('ledger_continuity_validation')
    $ledgerValidation = Get-LedgerContinuityValidation -BaselineSnapshotPath $ProtectedBaselineSnapshotPath -LiveLedgerPath $LiveLedgerPath -FingerprintReferencePath $FingerprintReferencePath
    $ledgerContinuityStatus = if ($ledgerValidation.valid) { 'VALID' } else { 'INVALID' }
    if (-not $ledgerValidation.valid) {
        return [ordered]@{
            baseline_snapshot = $baselineSnapshotStatus
            baseline_integrity = $baselineIntegrityStatus
            ledger_continuity = $ledgerContinuityStatus
            runtime_initialization = 'BLOCKED'
            block_reason = $ledgerValidation.reason
            initialization_sequence = @($sequence)
            pass = $false
        }
    }

    $sequence.Add('guard_fingerprint_enforcement')
    $sequence.Add('catalog_load')
    $sequence.Add('catalog_resolution')
    $sequence.Add('policy_chain_validation')
    $sequence.Add('runtime_initialization')

    return [ordered]@{
        baseline_snapshot = $baselineSnapshotStatus
        baseline_integrity = $baselineIntegrityStatus
        ledger_continuity = $ledgerContinuityStatus
        runtime_initialization = 'ALLOWED'
        block_reason = ''
        initialization_sequence = @($sequence)
        pass = $true
    }
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\phase44_8_trust_chain_baseline_runtime_enforcement_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null
$script:Phase44_8ProofDir = $PF
Set-Content -LiteralPath (Join-Path $PF '00_stage.txt') -Value 'stage=proof_dir_created' -Encoding UTF8 -NoNewline

$FingerprintReferencePath = Join-Path $Root 'tools\phase44_4\guard_coverage_fingerprint_reference.json'
$ProtectedBaselineSnapshotPath = Join-Path $Root 'control_plane\71_guard_fingerprint_trust_chain_baseline.json'
$BaselineIntegrityPath = Join-Path $Root 'control_plane\72_guard_fingerprint_trust_chain_baseline_integrity.json'
$LiveLedgerPath = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'

if (-not (Test-Path -LiteralPath $FingerprintReferencePath)) { throw 'Missing phase44_4 fingerprint reference.' }
if (-not (Test-Path -LiteralPath $ProtectedBaselineSnapshotPath)) { throw 'Missing phase44_7 baseline snapshot.' }
if (-not (Test-Path -LiteralPath $BaselineIntegrityPath)) { throw 'Missing phase44_7 baseline integrity file.' }
if (-not (Test-Path -LiteralPath $LiveLedgerPath)) { throw 'Missing phase44_6 trust-chain ledger.' }

$baselineSnapshotObject = Get-Content -Raw -LiteralPath $ProtectedBaselineSnapshotPath | ConvertFrom-Json
$baselineIntegrityObject = Get-Content -Raw -LiteralPath $BaselineIntegrityPath | ConvertFrom-Json
$baselineValidationRecord = [System.Collections.Generic.List[object]]::new()
$cases = [System.Collections.Generic.List[object]]::new()
Set-Content -LiteralPath (Join-Path $PF '00_stage.txt') -Value 'stage=inputs_loaded' -Encoding UTF8 -NoNewline

# CASE A — CLEAN BASELINE VALIDATION
$caseAResult = Invoke-RuntimeEntryGate -CandidateBaselineSnapshotPath $ProtectedBaselineSnapshotPath -BaselineIntegrityPath $BaselineIntegrityPath -LiveLedgerPath $LiveLedgerPath -ProtectedBaselineSnapshotPath $ProtectedBaselineSnapshotPath -FingerprintReferencePath $FingerprintReferencePath
$caseA = [ordered]@{
    case = 'A'
    baseline_integrity = $caseAResult.baseline_integrity
    ledger_continuity = $caseAResult.ledger_continuity
    runtime_initialization = $caseAResult.runtime_initialization
    initialization_sequence = @($caseAResult.initialization_sequence)
    block_reason = $caseAResult.block_reason
    pass = ($caseAResult.baseline_integrity -eq 'VALID' -and $caseAResult.ledger_continuity -eq 'VALID' -and $caseAResult.runtime_initialization -eq 'ALLOWED')
}
$cases.Add($caseA)
$baselineValidationRecord.Add($caseA)
Set-Content -LiteralPath (Join-Path $PF '00_stage.txt') -Value 'stage=case_a_complete' -Encoding UTF8 -NoNewline

# CASE B — BASELINE SNAPSHOT TAMPER
$tempSnapshotB = Join-Path $env:TEMP ('phase44_8_caseB_' + $Timestamp + '.json')
$tamperedSnapshotText = (Get-Content -Raw -LiteralPath $ProtectedBaselineSnapshotPath) -replace '"current_ledger_length"\s*:\s*1', '"current_ledger_length": 999'
[System.IO.File]::WriteAllText($tempSnapshotB, $tamperedSnapshotText, [System.Text.Encoding]::UTF8)
$caseBResult = Invoke-RuntimeEntryGate -CandidateBaselineSnapshotPath $tempSnapshotB -BaselineIntegrityPath $BaselineIntegrityPath -LiveLedgerPath $LiveLedgerPath -ProtectedBaselineSnapshotPath $ProtectedBaselineSnapshotPath -FingerprintReferencePath $FingerprintReferencePath
Remove-Item -Force -LiteralPath $tempSnapshotB
$caseB = [ordered]@{
    case = 'B'
    baseline_integrity = $caseBResult.baseline_integrity
    ledger_continuity = $caseBResult.ledger_continuity
    runtime_initialization = $caseBResult.runtime_initialization
    initialization_sequence = @($caseBResult.initialization_sequence)
    block_reason = $caseBResult.block_reason
    pass = ($caseBResult.baseline_integrity -eq 'INVALID' -and $caseBResult.runtime_initialization -eq 'BLOCKED')
}
$cases.Add($caseB)
$baselineValidationRecord.Add($caseB)

# CASE C — BASELINE INTEGRITY RECORD TAMPER
$tempIntegrityC = Join-Path $env:TEMP ('phase44_8_caseC_' + $Timestamp + '.json')
$tamperedIntegrityText = (Get-Content -Raw -LiteralPath $BaselineIntegrityPath) -replace '"expected_baseline_snapshot_sha256"\s*:\s*"[^"]+"', '"expected_baseline_snapshot_sha256": "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"'
[System.IO.File]::WriteAllText($tempIntegrityC, $tamperedIntegrityText, [System.Text.Encoding]::UTF8)
$caseCResult = Invoke-RuntimeEntryGate -CandidateBaselineSnapshotPath $ProtectedBaselineSnapshotPath -BaselineIntegrityPath $tempIntegrityC -LiveLedgerPath $LiveLedgerPath -ProtectedBaselineSnapshotPath $ProtectedBaselineSnapshotPath -FingerprintReferencePath $FingerprintReferencePath
Remove-Item -Force -LiteralPath $tempIntegrityC
$caseC = [ordered]@{
    case = 'C'
    baseline_integrity = $caseCResult.baseline_integrity
    ledger_continuity = $caseCResult.ledger_continuity
    runtime_initialization = $caseCResult.runtime_initialization
    initialization_sequence = @($caseCResult.initialization_sequence)
    block_reason = $caseCResult.block_reason
    pass = ($caseCResult.baseline_integrity -eq 'INVALID' -and $caseCResult.runtime_initialization -eq 'BLOCKED')
}
$cases.Add($caseC)
$baselineValidationRecord.Add($caseC)

# CASE D — LEDGER BREAK
$tempLedgerD = Join-Path $env:TEMP ('phase44_8_caseD_' + $Timestamp + '.json')
$ledgerAppendBreak = Get-Content -Raw -LiteralPath $LiveLedgerPath | ConvertFrom-Json
$brokenEntry = Build-NewChainEntry -EntryId 'GF-0002' -FingerprintHash (Get-StringSha256Hex -Text 'broken_append') -PhaseLocked '44.8' -PreviousHash 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff' -TimestampUtc ((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
$ledgerAppendBreak.entries += $brokenEntry
($ledgerAppendBreak | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $tempLedgerD -Encoding UTF8 -NoNewline
$caseDResult = Invoke-RuntimeEntryGate -CandidateBaselineSnapshotPath $ProtectedBaselineSnapshotPath -BaselineIntegrityPath $BaselineIntegrityPath -LiveLedgerPath $tempLedgerD -ProtectedBaselineSnapshotPath $ProtectedBaselineSnapshotPath -FingerprintReferencePath $FingerprintReferencePath
Remove-Item -Force -LiteralPath $tempLedgerD
$caseD = [ordered]@{
    case = 'D'
    baseline_integrity = $caseDResult.baseline_integrity
    ledger_continuity = $caseDResult.ledger_continuity
    runtime_initialization = $caseDResult.runtime_initialization
    initialization_sequence = @($caseDResult.initialization_sequence)
    block_reason = $caseDResult.block_reason
    pass = ($caseDResult.ledger_continuity -eq 'INVALID' -and $caseDResult.runtime_initialization -eq 'BLOCKED')
}
$cases.Add($caseD)
$baselineValidationRecord.Add($caseD)

# CASE E — VALID LEDGER APPEND
$tempLedgerE = Join-Path $env:TEMP ('phase44_8_caseE_' + $Timestamp + '.json')
$ledgerAppendValid = Get-Content -Raw -LiteralPath $LiveLedgerPath | ConvertFrom-Json
$firstAppendPreviousHash = [string]$baselineSnapshotObject.current_last_entry_hash
$validEntry = Build-NewChainEntry -EntryId 'GF-0002' -FingerprintHash (Get-StringSha256Hex -Text 'valid_append') -PhaseLocked '44.8' -PreviousHash $firstAppendPreviousHash -TimestampUtc ((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
$ledgerAppendValid.entries += $validEntry
($ledgerAppendValid | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $tempLedgerE -Encoding UTF8 -NoNewline
$caseEResult = Invoke-RuntimeEntryGate -CandidateBaselineSnapshotPath $ProtectedBaselineSnapshotPath -BaselineIntegrityPath $BaselineIntegrityPath -LiveLedgerPath $tempLedgerE -ProtectedBaselineSnapshotPath $ProtectedBaselineSnapshotPath -FingerprintReferencePath $FingerprintReferencePath
Remove-Item -Force -LiteralPath $tempLedgerE
$caseE = [ordered]@{
    case = 'E'
    baseline_integrity = $caseEResult.baseline_integrity
    ledger_continuity = $caseEResult.ledger_continuity
    runtime_initialization = $caseEResult.runtime_initialization
    initialization_sequence = @($caseEResult.initialization_sequence)
    block_reason = $caseEResult.block_reason
    pass = ($caseEResult.ledger_continuity -eq 'VALID' -and $caseEResult.runtime_initialization -eq 'ALLOWED')
}
$cases.Add($caseE)
$baselineValidationRecord.Add($caseE)

# CASE F — NON-SEMANTIC FILE CHANGE
$tempSnapshotF = Join-Path $env:TEMP ('phase44_8_caseF_' + $Timestamp + '.json')
$snapshotObjectF = Get-Content -Raw -LiteralPath $ProtectedBaselineSnapshotPath | ConvertFrom-Json
$prettyPrintedSnapshot = $snapshotObjectF | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText($tempSnapshotF, $prettyPrintedSnapshot, [System.Text.Encoding]::UTF8)
$caseFResult = Invoke-RuntimeEntryGate -CandidateBaselineSnapshotPath $tempSnapshotF -BaselineIntegrityPath $BaselineIntegrityPath -LiveLedgerPath $LiveLedgerPath -ProtectedBaselineSnapshotPath $ProtectedBaselineSnapshotPath -FingerprintReferencePath $FingerprintReferencePath
Remove-Item -Force -LiteralPath $tempSnapshotF
$caseF = [ordered]@{
    case = 'F'
    baseline_integrity = $caseFResult.baseline_integrity
    ledger_continuity = $caseFResult.ledger_continuity
    runtime_initialization = $caseFResult.runtime_initialization
    initialization_sequence = @($caseFResult.initialization_sequence)
    block_reason = $caseFResult.block_reason
    pass = ($caseFResult.baseline_integrity -eq 'VALID' -and $caseFResult.runtime_initialization -eq 'ALLOWED')
}
$cases.Add($caseF)
$baselineValidationRecord.Add($caseF)

$allPass = (@($cases | Where-Object { -not $_.pass }).Count -eq 0)
$gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status = @(
    'phase=44.8',
    'title=Trust-Chain Baseline Enforcement Runtime Gate',
    ('gate=' + $gate),
    ('baseline_snapshot=' + ($ProtectedBaselineSnapshotPath -replace [regex]::Escape($Root + '\\'), '')),
    ('baseline_integrity=' + ($BaselineIntegrityPath -replace [regex]::Escape($Root + '\\'), '')),
    ('live_ledger=' + ($LiveLedgerPath -replace [regex]::Escape($Root + '\\'), '')),
    ('cases_total=' + $cases.Count),
    ('cases_pass=' + (@($cases | Where-Object { $_.pass }).Count)),
    ('cases_fail=' + (@($cases | Where-Object { -not $_.pass }).Count)),
    ('timestamp=' + $Timestamp)
)
Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value ($status -join "`r`n") -Encoding UTF8 -NoNewline

$head = @(
    'runner=tools/phase44_8/phase44_8_trust_chain_baseline_runtime_enforcement_runner.ps1',
    ('fingerprint_reference=' + ($FingerprintReferencePath -replace [regex]::Escape($Root + '\\'), '')),
    ('baseline_snapshot=' + ($ProtectedBaselineSnapshotPath -replace [regex]::Escape($Root + '\\'), '')),
    ('baseline_integrity=' + ($BaselineIntegrityPath -replace [regex]::Escape($Root + '\\'), '')),
    ('live_ledger=' + ($LiveLedgerPath -replace [regex]::Escape($Root + '\\'), '')),
    'enforcement_order=baseline_snapshot_validation -> baseline_integrity_validation -> ledger_continuity_validation -> guard_fingerprint_enforcement -> catalog_load -> catalog_resolution -> policy_chain_validation -> runtime_initialization'
)
Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value ($head -join "`r`n") -Encoding UTF8 -NoNewline

$definition = @(
    'RUNTIME ENFORCEMENT DEFINITION (PHASE 44.8)',
    '',
    'The runtime entry gate verifies the frozen trust-chain baseline before any downstream runtime stage is allowed.',
    'Validation order is fixed and deterministic: baseline snapshot validation, baseline integrity validation, ledger continuity validation, then downstream runtime stages.',
    'Baseline snapshot validation is semantic and verifies embedded baseline ledger metadata plus fingerprint reference binding.',
    'Baseline integrity validation verifies the protected frozen snapshot file bytes against the stored integrity record and then verifies the candidate baseline is semantically equal to the protected frozen baseline.',
    'Ledger continuity validation requires the live ledger to preserve the frozen baseline prefix and, if appended, the first appended entry must reference the baseline last-entry hash.'
)
Set-Content -LiteralPath (Join-Path $PF '10_runtime_enforcement_definition.txt') -Value ($definition -join "`r`n") -Encoding UTF8 -NoNewline

$rules = @(
    'VERIFICATION RULES (PHASE 44.8)',
    '',
    'RULE_1: Baseline snapshot validation runs first and must pass before integrity validation starts.',
    'RULE_2: Baseline integrity validation verifies the integrity record against the protected frozen baseline file bytes.',
    'RULE_3: Baseline integrity validation also requires semantic equivalence between the candidate baseline and the protected frozen baseline.',
    'RULE_4: Ledger continuity validation requires the live ledger to match the frozen baseline prefix exactly.',
    'RULE_5: If the live ledger has appended entries, the first appended entry previous_hash must equal the frozen baseline current_last_entry_hash.',
    'RULE_6: Any failure blocks guard fingerprint enforcement, catalog load, catalog resolution, policy chain validation, and runtime initialization.',
    'RULE_7: Whitespace-only or formatting-only baseline snapshot changes are non-semantic and remain valid when semantics are unchanged.'
)
Set-Content -LiteralPath (Join-Path $PF '11_verification_rules.txt') -Value ($rules -join "`r`n") -Encoding UTF8 -NoNewline

$touched = @(
    ('READ  ' + ($FingerprintReferencePath -replace [regex]::Escape($Root + '\\'), '')),
    ('READ  ' + ($ProtectedBaselineSnapshotPath -replace [regex]::Escape($Root + '\\'), '')),
    ('READ  ' + ($BaselineIntegrityPath -replace [regex]::Escape($Root + '\\'), '')),
    ('READ  ' + ($LiveLedgerPath -replace [regex]::Escape($Root + '\\'), '')),
    'TEMP  %TEMP%\phase44_8_caseB_*.json (deleted)',
    'TEMP  %TEMP%\phase44_8_caseC_*.json (deleted)',
    'TEMP  %TEMP%\phase44_8_caseD_*.json (deleted)',
    'TEMP  %TEMP%\phase44_8_caseE_*.json (deleted)',
    'TEMP  %TEMP%\phase44_8_caseF_*.json (deleted)',
    ('WRITE _proof/' + (Split-Path -Leaf $PF) + '/*')
)
Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Value ($touched -join "`r`n") -Encoding UTF8 -NoNewline

$build = @(
    'build_type=PowerShell runtime entry gate proof',
    'compile_required=no',
    'hashing=sha256_file_bytes_v1 + sha256_canonical_json_semantic_v1',
    'runtime_state_machine_changed=no',
    'enforcement_layer=certification_runtime_pre-init_gate'
)
Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Value ($build -join "`r`n") -Encoding UTF8 -NoNewline

$validationLines = [System.Collections.Generic.List[string]]::new()
foreach ($caseRecord in $cases) {
    $validationLines.Add(('CASE ' + $caseRecord.case + ': ' + ($caseRecord | ConvertTo-Json -Depth 8 -Compress)))
}
Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Value (($validationLines.ToArray()) -join "`r`n") -Encoding UTF8 -NoNewline

$behaviorSummary = @(
    'The phase44_8 runtime gate enforces baseline snapshot validation, baseline integrity validation, and ledger continuity validation before any downstream runtime stage is allowed.',
    'Semantic baseline comparison allows non-semantic whitespace or formatting changes while still blocking actual baseline content tamper.',
    'The integrity record remains byte-verified against the protected frozen baseline snapshot, so integrity-record tamper is still detected deterministically.',
    'Ledger continuity is satisfied for the clean ledger and for valid append-only evolution that references the frozen baseline last hash.',
    'Broken ledger evolution blocks runtime immediately and prevents guard fingerprint enforcement and all later initialization stages from starting.',
    'Runtime state machine remained unchanged because the phase is implemented entirely as certification enforcement tooling.'
)
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value ($behaviorSummary -join "`r`n") -Encoding UTF8 -NoNewline

$record16 = [ordered]@{
    protected_baseline_snapshot_file = 'control_plane/71_guard_fingerprint_trust_chain_baseline.json'
    baseline_integrity_file = 'control_plane/72_guard_fingerprint_trust_chain_baseline_integrity.json'
    live_ledger_file = 'control_plane/70_guard_fingerprint_trust_chain.json'
    expected_baseline_snapshot_sha256 = [string]$baselineIntegrityObject.expected_baseline_snapshot_sha256
    protected_baseline_snapshot_sha256 = (Get-FileSha256Hex -Path $ProtectedBaselineSnapshotPath)
    protected_baseline_semantic_hash = (Get-BaselineSemanticHash -BaselinePath $ProtectedBaselineSnapshotPath)
    current_last_entry_hash = [string]$baselineSnapshotObject.current_last_entry_hash
    current_ledger_length = [int]$baselineSnapshotObject.current_ledger_length
    current_phase_lock_marker = [string]$baselineSnapshotObject.current_phase_lock_marker
    case_records = $baselineValidationRecord
}
Set-Content -LiteralPath (Join-Path $PF '16_baseline_validation_record.txt') -Value ($record16 | ConvertTo-Json -Depth 12) -Encoding UTF8 -NoNewline

$blockEvidence = @(
    'RUNTIME BLOCK EVIDENCE',
    ('CASE_B_BLOCK_REASON=' + $caseB.block_reason),
    ('CASE_B_SEQUENCE=' + ($caseB.initialization_sequence -join ' -> ')),
    ('CASE_C_BLOCK_REASON=' + $caseC.block_reason),
    ('CASE_C_SEQUENCE=' + ($caseC.initialization_sequence -join ' -> ')),
    ('CASE_D_BLOCK_REASON=' + $caseD.block_reason),
    ('CASE_D_SEQUENCE=' + ($caseD.initialization_sequence -join ' -> ')),
    ('CASE_E_SEQUENCE=' + ($caseE.initialization_sequence -join ' -> ')),
    ('CASE_F_SEQUENCE=' + ($caseF.initialization_sequence -join ' -> '))
)
Set-Content -LiteralPath (Join-Path $PF '17_runtime_block_evidence.txt') -Value ($blockEvidence -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '98_gate_phase44_8.txt') -Value $gate -Encoding UTF8 -NoNewline

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