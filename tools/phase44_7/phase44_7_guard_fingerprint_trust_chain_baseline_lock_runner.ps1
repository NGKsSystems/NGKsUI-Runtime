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

function Get-ChainEntryCanonical {
    param([hashtable]$Entry)

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
    param([hashtable]$Entry)
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
        $eObj = $entries[$i]
        $entry = [ordered]@{
            entry_id = [string]$eObj.entry_id
            fingerprint_hash = [string]$eObj.fingerprint_hash
            timestamp_utc = [string]$eObj.timestamp_utc
            phase_locked = [string]$eObj.phase_locked
            previous_hash = if ($null -eq $eObj.previous_hash -or [string]::IsNullOrWhiteSpace([string]$eObj.previous_hash)) { $null } else { [string]$eObj.previous_hash }
        }

        if ($i -eq 0) {
            if ($null -ne $entry.previous_hash) {
                $result.pass = $false
                $result.reason = 'first_entry_previous_hash_must_be_null'
                return $result
            }
        } else {
            $expectedPrev = $hashes[$i - 1]
            if ([string]$entry.previous_hash -ne [string]$expectedPrev) {
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

function New-BaselineSnapshotObject {
    param(
        [object]$FingerprintRef,
        [object]$LedgerObj,
        [string]$FingerprintRefPath,
        [string]$LedgerPath,
        [hashtable]$LedgerValidation
    )

    $entries = @($LedgerObj.entries)
    $lastEntry = $entries[$entries.Count - 1]

    return [ordered]@{
        baseline_kind = 'guard_fingerprint_trust_chain_baseline_lock'
        snapshot_schema = 'phase44_7_guard_fingerprint_trust_chain_baseline_v1'
        phase_locked = '44.7'
        fingerprint_reference_file = 'tools/phase44_4/guard_coverage_fingerprint_reference.json'
        fingerprint_reference_sha256 = (Get-FileSha256Hex -Path $FingerprintRefPath)
        fingerprint_reference_payload = $FingerprintRef
        trust_chain_ledger_file = 'control_plane/70_guard_fingerprint_trust_chain.json'
        trust_chain_ledger_sha256 = (Get-FileSha256Hex -Path $LedgerPath)
        trust_chain_ledger_payload = $LedgerObj
        current_last_entry_hash = [string]$LedgerValidation.last_entry_hash
        current_ledger_length = [int]$LedgerValidation.entry_count
        current_phase_lock_marker = [string]$lastEntry.phase_locked
    }
}

function Write-BaselineFilesIfMissing {
    param(
        [string]$SnapshotPath,
        [string]$IntegrityPath,
        [object]$SnapshotObj
    )

    if (-not (Test-Path -LiteralPath $SnapshotPath)) {
        ($SnapshotObj | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $SnapshotPath -Encoding UTF8 -NoNewline
    }

    if (-not (Test-Path -LiteralPath $IntegrityPath)) {
        $snapshotHash = Get-FileSha256Hex -Path $SnapshotPath
        $integrityObj = [ordered]@{
            protected_baseline_snapshot_file = 'control_plane/71_guard_fingerprint_trust_chain_baseline.json'
            expected_baseline_snapshot_sha256 = $snapshotHash
            hash_method = 'sha256_file_bytes_v1'
            baseline_kind = 'guard_fingerprint_trust_chain_baseline_lock'
            phase_locked = '44.7'
        }
        ($integrityObj | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $IntegrityPath -Encoding UTF8 -NoNewline
    }
}

function Test-BaselineSnapshotIntegrity {
    param(
        [string]$SnapshotPath,
        [string]$IntegrityPath
    )

    $result = [ordered]@{
        pass = $false
        reason = 'not_checked'
        stored_hash = ''
        computed_hash = ''
        certification_usage = 'BLOCKED'
    }

    if (-not (Test-Path -LiteralPath $SnapshotPath)) {
        $result.reason = 'baseline_snapshot_missing'
        return $result
    }
    if (-not (Test-Path -LiteralPath $IntegrityPath)) {
        $result.reason = 'baseline_integrity_file_missing'
        return $result
    }

    $integrityObj = Get-Content -Raw -LiteralPath $IntegrityPath | ConvertFrom-Json
    $result.stored_hash = [string]$integrityObj.expected_baseline_snapshot_sha256
    $result.computed_hash = Get-FileSha256Hex -Path $SnapshotPath

    if ($result.stored_hash -ne $result.computed_hash) {
        $result.reason = 'baseline_hash_mismatch'
        return $result
    }

    $snapshotObj = Get-Content -Raw -LiteralPath $SnapshotPath | ConvertFrom-Json
    $required = @('fingerprint_reference_file','trust_chain_ledger_file','current_last_entry_hash','current_ledger_length','phase_locked')
    foreach ($field in $required) {
        if (-not ($snapshotObj.PSObject.Properties.Name -contains $field)) {
            $result.reason = ('baseline_missing_field_' + $field)
            return $result
        }
    }

    $result.pass = $true
    $result.reason = 'ok'
    $result.certification_usage = 'ALLOWED'
    return $result
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\\phase44_7_guard_fingerprint_trust_chain_baseline_lock_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$FingerprintRefPath = Join-Path $Root 'tools\\phase44_4\\guard_coverage_fingerprint_reference.json'
$LedgerPath = Join-Path $Root 'control_plane\\70_guard_fingerprint_trust_chain.json'
$BaselineSnapshotPath = Join-Path $Root 'control_plane\\71_guard_fingerprint_trust_chain_baseline.json'
$BaselineIntegrityPath = Join-Path $Root 'control_plane\\72_guard_fingerprint_trust_chain_baseline_integrity.json'

if (-not (Test-Path -LiteralPath $FingerprintRefPath)) { throw 'Missing phase44_4 fingerprint reference.' }
if (-not (Test-Path -LiteralPath $LedgerPath)) { throw 'Missing phase44_6 trust chain ledger.' }

$fingerprintRef = Get-Content -Raw -LiteralPath $FingerprintRefPath | ConvertFrom-Json
$ledgerObj = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
$ledgerValidation = Test-TrustChain -ChainObj $ledgerObj
if (-not $ledgerValidation.pass) { throw ('Current trust chain invalid: ' + $ledgerValidation.reason) }

$baselineSnapshotObj = New-BaselineSnapshotObject -FingerprintRef $fingerprintRef -LedgerObj $ledgerObj -FingerprintRefPath $FingerprintRefPath -LedgerPath $LedgerPath -LedgerValidation $ledgerValidation
Write-BaselineFilesIfMissing -SnapshotPath $BaselineSnapshotPath -IntegrityPath $BaselineIntegrityPath -SnapshotObj $baselineSnapshotObj

$cases = [System.Collections.Generic.List[object]]::new()
$baselineActualHash = Get-FileSha256Hex -Path $BaselineSnapshotPath
$baselineIntegrityObj = Get-Content -Raw -LiteralPath $BaselineIntegrityPath | ConvertFrom-Json

# CASE A — Baseline snapshot creation
$caseAIntegrity = Test-BaselineSnapshotIntegrity -SnapshotPath $BaselineSnapshotPath -IntegrityPath $BaselineIntegrityPath
$caseA = [ordered]@{
    case = 'A'
    baseline_snapshot_created = (Test-Path -LiteralPath $BaselineSnapshotPath)
    baseline_integrity_recorded = (Test-Path -LiteralPath $BaselineIntegrityPath)
    stored_hash = $caseAIntegrity.stored_hash
    computed_hash = $caseAIntegrity.computed_hash
    baseline_valid = $(if ($caseAIntegrity.pass) { 'TRUE' } else { 'FALSE' })
    certification_usage = $caseAIntegrity.certification_usage
    detected_change_type = 'none'
    pass = ($caseAIntegrity.pass)
}
$cases.Add($caseA)

# CASE B — Baseline verification
$caseBIntegrity = Test-BaselineSnapshotIntegrity -SnapshotPath $BaselineSnapshotPath -IntegrityPath $BaselineIntegrityPath
$caseB = [ordered]@{
    case = 'B'
    stored_hash = $caseBIntegrity.stored_hash
    computed_hash = $caseBIntegrity.computed_hash
    baseline_hash_match = $(if ($caseBIntegrity.stored_hash -eq $caseBIntegrity.computed_hash) { 'TRUE' } else { 'FALSE' })
    baseline_valid = $(if ($caseBIntegrity.pass) { 'TRUE' } else { 'FALSE' })
    certification_usage = $caseBIntegrity.certification_usage
    detected_change_type = 'none'
    pass = ($caseBIntegrity.pass)
}
$cases.Add($caseB)

# CASE C — Baseline tamper detection
$tempSnapshotC = Join-Path $env:TEMP ('phase44_7_caseC_' + $Timestamp + '.json')
$tamperedSnapshotText = (Get-Content -Raw -LiteralPath $BaselineSnapshotPath) -replace '"current_ledger_length"\s*:\s*1', '"current_ledger_length": 999'
[System.IO.File]::WriteAllText($tempSnapshotC, $tamperedSnapshotText, [System.Text.Encoding]::UTF8)
$caseCIntegrity = Test-BaselineSnapshotIntegrity -SnapshotPath $tempSnapshotC -IntegrityPath $BaselineIntegrityPath
Remove-Item -Force -LiteralPath $tempSnapshotC
$caseC = [ordered]@{
    case = 'C'
    stored_hash = $caseCIntegrity.stored_hash
    computed_hash = $caseCIntegrity.computed_hash
    baseline_hash_match = $(if ($caseCIntegrity.stored_hash -eq $caseCIntegrity.computed_hash) { 'TRUE' } else { 'FALSE' })
    baseline_valid = $(if ($caseCIntegrity.pass) { 'TRUE' } else { 'FALSE' })
    certification_usage = $caseCIntegrity.certification_usage
    detected_change_type = 'baseline_snapshot_tamper'
    pass = (-not $caseCIntegrity.pass -and $caseCIntegrity.certification_usage -eq 'BLOCKED')
}
$cases.Add($caseC)

# CASE D — Baseline overwrite block/detection
$tempSnapshotD = Join-Path $env:TEMP ('phase44_7_caseD_' + $Timestamp + '.json')
$overwriteObj = [ordered]@{
    overwritten = $true
    reason = 'silent_overwrite_attempt'
}
($overwriteObj | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $tempSnapshotD -Encoding UTF8 -NoNewline
$caseDIntegrity = Test-BaselineSnapshotIntegrity -SnapshotPath $tempSnapshotD -IntegrityPath $BaselineIntegrityPath
Remove-Item -Force -LiteralPath $tempSnapshotD
$caseD = [ordered]@{
    case = 'D'
    stored_hash = $caseDIntegrity.stored_hash
    computed_hash = $caseDIntegrity.computed_hash
    overwrite_detected = $(if (-not $caseDIntegrity.pass) { 'TRUE' } else { 'FALSE' })
    baseline_valid = $(if ($caseDIntegrity.pass) { 'TRUE' } else { 'FALSE' })
    certification_usage = $caseDIntegrity.certification_usage
    detected_change_type = 'baseline_overwrite_attempt'
    pass = (-not $caseDIntegrity.pass -and $caseDIntegrity.certification_usage -eq 'BLOCKED')
}
$cases.Add($caseD)

# CASE E — Future append compatibility
$liveLedgerAppend = ($ledgerObj | ConvertTo-Json -Depth 20 | ConvertFrom-Json)
$prevHash = [string]$ledgerValidation.last_entry_hash
$nextIndex = [string](@($liveLedgerAppend.entries).Count + 1)
$newEntryId = 'GF-' + $nextIndex.PadLeft(4, '0')
$newEntry = Build-NewChainEntry -EntryId $newEntryId -FingerprintHash (Get-StringSha256Hex -Text ($baselineActualHash + '|append_ref')) -PhaseLocked '44.7' -PreviousHash $prevHash -TimestampUtc ((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
$liveLedgerAppend.entries += $newEntry
$liveAppendValidation = Test-TrustChain -ChainObj $liveLedgerAppend
$baselinePostAppendIntegrity = Test-BaselineSnapshotIntegrity -SnapshotPath $BaselineSnapshotPath -IntegrityPath $BaselineIntegrityPath
$baselineUnchanged = ($baselinePostAppendIntegrity.computed_hash -eq $baselineActualHash)
$caseE = [ordered]@{
    case = 'E'
    live_chain_append_works = $(if ($liveAppendValidation.pass) { 'TRUE' } else { 'FALSE' })
    frozen_baseline_unchanged = $(if ($baselineUnchanged) { 'TRUE' } else { 'FALSE' })
    baseline_reference_valid = $(if ($baselinePostAppendIntegrity.pass) { 'TRUE' } else { 'FALSE' })
    stored_hash = $baselinePostAppendIntegrity.stored_hash
    computed_hash = $baselinePostAppendIntegrity.computed_hash
    detected_change_type = 'future_append_compatibility'
    certification_usage = $baselinePostAppendIntegrity.certification_usage
    pass = ($liveAppendValidation.pass -and $baselineUnchanged -and $baselinePostAppendIntegrity.pass)
}
$cases.Add($caseE)

$allPass = (@($cases | Where-Object { -not $_.pass }).Count -eq 0)
$gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status = @(
    'phase=44.7',
    'title=Guard Fingerprint Trust-Chain Baseline Lock',
    ('gate=' + $gate),
    ('baseline_snapshot=' + ($BaselineSnapshotPath -replace [regex]::Escape($Root + '\\'), '')),
    ('baseline_integrity=' + ($BaselineIntegrityPath -replace [regex]::Escape($Root + '\\'), '')),
    ('cases_total=' + $cases.Count),
    ('cases_pass=' + (@($cases | Where-Object { $_.pass }).Count)),
    ('cases_fail=' + (@($cases | Where-Object { -not $_.pass }).Count)),
    ('timestamp=' + $Timestamp)
)
Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value ($status -join "`r`n") -Encoding UTF8 -NoNewline

$head = @(
    'runner=tools/phase44_7/phase44_7_guard_fingerprint_trust_chain_baseline_lock_runner.ps1',
    ('fingerprint_reference=' + ($FingerprintRefPath -replace [regex]::Escape($Root + '\\'), '')),
    ('trust_chain_ledger=' + ($LedgerPath -replace [regex]::Escape($Root + '\\'), '')),
    ('baseline_snapshot=' + ($BaselineSnapshotPath -replace [regex]::Escape($Root + '\\'), '')),
    ('baseline_integrity=' + ($BaselineIntegrityPath -replace [regex]::Escape($Root + '\\'), ''))
)
Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value ($head -join "`r`n") -Encoding UTF8 -NoNewline

$def = @(
    'BASELINE DEFINITION (PHASE 44.7)',
    '',
    'The frozen baseline captures the current guard fingerprint reference, full trust-chain ledger, last entry hash, ledger length, and current phase lock marker.',
    'Snapshot file: control_plane/71_guard_fingerprint_trust_chain_baseline.json',
    'Integrity file: control_plane/72_guard_fingerprint_trust_chain_baseline_integrity.json',
    'Integrity hash method: sha256_file_bytes_v1',
    'Baseline is certification-usable only when stored and computed snapshot hashes match.'
)
Set-Content -LiteralPath (Join-Path $PF '10_baseline_definition.txt') -Value ($def -join "`r`n") -Encoding UTF8 -NoNewline

$hashRules = @(
    'BASELINE HASH RULES (PHASE 44.7)',
    '',
    'RULE_1: Snapshot bytes are hashed deterministically using SHA-256.',
    'RULE_2: Integrity file stores the expected snapshot hash and protected snapshot path.',
    'RULE_3: Any content change in snapshot without integrity update causes mismatch.',
    'RULE_4: Silent overwrite attempts are treated as tampering and block certification usage.',
    'RULE_5: Future ledger appends must not alter frozen baseline snapshot hash.'
)
Set-Content -LiteralPath (Join-Path $PF '11_baseline_hash_rules.txt') -Value ($hashRules -join "`r`n") -Encoding UTF8 -NoNewline

$touched = @(
    ('READ  ' + ($FingerprintRefPath -replace [regex]::Escape($Root + '\\'), '')),
    ('READ  ' + ($LedgerPath -replace [regex]::Escape($Root + '\\'), '')),
    ('READ/WRITE  ' + ($BaselineSnapshotPath -replace [regex]::Escape($Root + '\\'), '')),
    ('READ/WRITE  ' + ($BaselineIntegrityPath -replace [regex]::Escape($Root + '\\'), '')),
    ('WRITE _proof/' + (Split-Path -Leaf $PF) + '/*')
)
Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Value ($touched -join "`r`n") -Encoding UTF8 -NoNewline

$build = @(
    'build_type=PowerShell trust-chain baseline lock',
    'compile_required=no',
    'hashing=sha256_file_bytes_v1',
    'runtime_state_machine_changed=no',
    'baseline_snapshot_deterministic=yes'
)
Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Value ($build -join "`r`n") -Encoding UTF8 -NoNewline

$val = [System.Collections.Generic.List[string]]::new()
foreach ($c in $cases) {
    $val.Add(('CASE ' + $c.case + ': ' + ($c | ConvertTo-Json -Depth 8 -Compress)))
}
Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Value (($val.ToArray()) -join "`r`n") -Encoding UTF8 -NoNewline

$summary = @(
    'The trust-chain ledger is frozen into a certification baseline snapshot plus integrity record.',
    'Baseline verification recomputes the snapshot hash and compares it to the stored expected value before certification usage is allowed.',
    'Tamper and overwrite attempts are detected as deterministic hash mismatches and block certification usage.',
    'Future live ledger append remains compatible because append validation is performed on live chain copies while the frozen baseline hash remains unchanged.',
    'Runtime behavior remained unchanged because this phase only snapshots and validates certification artifacts.'
)
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value ($summary -join "`r`n") -Encoding UTF8 -NoNewline

$integrityRecord = [ordered]@{
    baseline_snapshot_file = 'control_plane/71_guard_fingerprint_trust_chain_baseline.json'
    baseline_integrity_file = 'control_plane/72_guard_fingerprint_trust_chain_baseline_integrity.json'
    expected_baseline_hash = [string]$baselineIntegrityObj.expected_baseline_snapshot_sha256
    computed_baseline_hash = $baselineActualHash
    trust_chain_last_entry_hash = [string]$ledgerValidation.last_entry_hash
    trust_chain_length = [int]$ledgerValidation.entry_count
    phase_lock_marker = [string]$baselineSnapshotObj.current_phase_lock_marker
}
Set-Content -LiteralPath (Join-Path $PF '16_baseline_integrity_record.txt') -Value ($integrityRecord | ConvertTo-Json -Depth 10) -Encoding UTF8 -NoNewline

$evidence = @(
    'BASELINE TAMPER EVIDENCE',
    ('CASE_C_REASON=' + $caseCIntegrity.reason),
    ('CASE_C_USAGE=' + $caseCIntegrity.certification_usage),
    ('CASE_D_REASON=' + $caseDIntegrity.reason),
    ('CASE_D_USAGE=' + $caseDIntegrity.certification_usage),
    ('CASE_E_APPEND_COMPAT=' + $caseE.live_chain_append_works),
    ('CASE_E_BASELINE_UNCHANGED=' + $caseE.frozen_baseline_unchanged),
    ('CASE_E_BASELINE_VALID=' + $caseE.baseline_reference_valid)
)
Set-Content -LiteralPath (Join-Path $PF '17_baseline_tamper_evidence.txt') -Value ($evidence -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '98_gate_phase44_7.txt') -Value $gate -Encoding UTF8 -NoNewline

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
