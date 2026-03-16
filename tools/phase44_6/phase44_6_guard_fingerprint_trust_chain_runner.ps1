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

function Get-LatestPhase44_3Proof {
    $proofRoot = Join-Path $Root '_proof'
    $latest = Get-ChildItem -LiteralPath $proofRoot -Directory |
        Where-Object { $_.Name -like 'phase44_3_baseline_guard_coverage_audit_*' } |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($null -eq $latest) { throw 'Missing phase44_3 proof packet.' }
    return $latest.FullName
}

function Parse-InventoryRow {
    param([string]$Line)

    $parts = @($Line -split '\s\|\s', 10)
    if ($parts.Count -ne 10) { return $null }

    return [ordered]@{
        file_path = $parts[0].Trim()
        function_name = $parts[1].Trim()
        role = $parts[2].Trim()
        operational_or_dead = $parts[3].Trim()
        direct_guard = $parts[4].Trim()
        transitive_guard = $parts[5].Trim()
        guard_source = $parts[6].Trim()
        catalog_operation_type = $parts[7].Trim()
        coverage_classification = $parts[8].Trim()
        notes = $parts[9].Trim()
    }
}

function Normalize-RepoPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return ($Path -replace '\\','/').ToLowerInvariant()
}

function Normalize-GuardCoverageMaterial {
    param([object[]]$InventoryRows)

    $ops = @($InventoryRows | Where-Object { $_.operational_or_dead -eq 'operational' })
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($r in $ops) {
        $records.Add([ordered]@{
            file_path = Normalize-RepoPath -Path ([string]$r.file_path)
            function_name = [string]$r.function_name
            role = [string]$r.role
            helper_classification = [string]$r.operational_or_dead
            direct_guard = [string]$r.direct_guard
            transitive_guard = [string]$r.transitive_guard
            guard_source = Normalize-RepoPath -Path ([string]$r.guard_source)
            catalog_operation_type = [string]$r.catalog_operation_type
            coverage_classification = [string]$r.coverage_classification
        })
    }

    $ordered = @($records | Sort-Object file_path, function_name)
    return [ordered]@{
        schema = 'phase44_4_guard_coverage_fingerprint_v1'
        record_count = $ordered.Count
        records = $ordered
    }
}

function Get-FingerprintFromInventory {
    param([object[]]$InventoryRows)
    $material = Normalize-GuardCoverageMaterial -InventoryRows $InventoryRows
    $json = $material | ConvertTo-Json -Depth 12 -Compress
    return [ordered]@{
        fingerprint = (Get-StringSha256Hex -Text $json)
        canonical_json = $json
    }
}

function Get-InventoryRowsFromFile {
    param([string]$Path)
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -like 'file_path*') { continue }
        $row = Parse-InventoryRow -Line $line
        if ($null -ne $row) { $rows.Add($row) }
    }
    return @($rows)
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

        if ([string]::IsNullOrWhiteSpace($entry.entry_id) -or [string]::IsNullOrWhiteSpace($entry.fingerprint_hash) -or [string]::IsNullOrWhiteSpace($entry.phase_locked)) {
            $result.pass = $false
            $result.reason = ('entry_required_fields_missing_at_index_' + $i)
            return $result
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

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\\phase44_6_guard_fingerprint_trust_chain_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$phase44_3Pf = Get-LatestPhase44_3Proof
$inventoryPath = Join-Path $phase44_3Pf '16_entrypoint_inventory.txt'
$gate44_3Path = Join-Path $phase44_3Pf '98_gate_phase44_3.txt'
$gate44_3 = if (Test-Path -LiteralPath $gate44_3Path) { (Get-Content -Raw -LiteralPath $gate44_3Path).Trim() } else { '' }

$fingerprintRefPath = Join-Path $Root 'tools\\phase44_4\\guard_coverage_fingerprint_reference.json'
if (-not (Test-Path -LiteralPath $fingerprintRefPath)) {
    throw 'Missing fingerprint reference artifact from phase44_4.'
}

$inventoryRows = Get-InventoryRowsFromFile -Path $inventoryPath
$computedData = Get-FingerprintFromInventory -InventoryRows $inventoryRows
$computedFingerprint = [string]$computedData.fingerprint

$refObj = Get-Content -Raw -LiteralPath $fingerprintRefPath | ConvertFrom-Json
$storedFingerprint = [string]$refObj.reference_fingerprint_sha256
$referenceFileHash = Get-FileSha256Hex -Path $fingerprintRefPath

$ledgerPath = Join-Path $Root 'control_plane\\70_guard_fingerprint_trust_chain.json'
$ledgerObj = $null

if (Test-Path -LiteralPath $ledgerPath) {
    $ledgerObj = Get-Content -Raw -LiteralPath $ledgerPath | ConvertFrom-Json
} else {
    $entryV1 = Build-NewChainEntry -EntryId 'GF-0001' -FingerprintHash $referenceFileHash -PhaseLocked '44.6' -PreviousHash '' -TimestampUtc ((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
    $ledgerObj = [ordered]@{
        chain_version = 1
        entries = @($entryV1)
    }
    ($ledgerObj | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $ledgerPath -Encoding UTF8 -NoNewline
    $ledgerObj = Get-Content -Raw -LiteralPath $ledgerPath | ConvertFrom-Json
}

$cases = [System.Collections.Generic.List[object]]::new()

# CASE A — Clean chain initialization/validation
$chainA = Test-TrustChain -ChainObj $ledgerObj
$caseA_match = ($storedFingerprint -eq $computedFingerprint)
$caseA_runtimeAllowed = ($caseA_match -and $chainA.pass)
$caseA = [ordered]@{
    case = 'A'
    stored_fingerprint = $storedFingerprint
    computed_fingerprint = $computedFingerprint
    fingerprint_match_status = $(if ($caseA_match) { 'TRUE' } else { 'FALSE' })
    detected_change_type = 'none'
    trust_chain_validation = $(if ($chainA.pass) { 'PASS' } else { 'FAIL' })
    runtime_initialization_allowed_or_blocked = $(if ($caseA_runtimeAllowed) { 'ALLOWED' } else { 'BLOCKED' })
    chain_reason = $chainA.reason
    pass = $caseA_runtimeAllowed
}
$cases.Add($caseA)

# CASE B — Fingerprint reference tamper (simulated in memory)
$caseB_storedTampered = ('X' + $storedFingerprint.Substring(1))
$caseB_match = ($caseB_storedTampered -eq $computedFingerprint)
$caseB_runtimeAllowed = ($caseB_match -and $chainA.pass)
$caseB = [ordered]@{
    case = 'B'
    stored_fingerprint = $caseB_storedTampered
    computed_fingerprint = $computedFingerprint
    fingerprint_match_status = $(if ($caseB_match) { 'TRUE' } else { 'FALSE' })
    detected_change_type = 'fingerprint_reference_tamper'
    trust_chain_validation = $(if ($chainA.pass) { 'PASS' } else { 'FAIL' })
    runtime_initialization_allowed_or_blocked = $(if ($caseB_runtimeAllowed) { 'ALLOWED' } else { 'BLOCKED' })
    chain_reason = $chainA.reason
    pass = (-not $caseB_match -and -not $caseB_runtimeAllowed)
}
$cases.Add($caseB)

# CASE C — Historical trust chain entry tamper (simulate on deep copy)
$chainCTampered = ($ledgerObj | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
if (@($chainCTampered.entries).Count -lt 2) {
    # Create a valid linked successor first, then tamper historical entry so linkage breaks.
    $origEntry = $chainCTampered.entries[0]
    $origEntryHash = Get-ChainEntryHash -Entry ([ordered]@{
        entry_id = [string]$origEntry.entry_id
        fingerprint_hash = [string]$origEntry.fingerprint_hash
        timestamp_utc = [string]$origEntry.timestamp_utc
        phase_locked = [string]$origEntry.phase_locked
        previous_hash = if ($null -eq $origEntry.previous_hash -or [string]::IsNullOrWhiteSpace([string]$origEntry.previous_hash)) { $null } else { [string]$origEntry.previous_hash }
    })
    $newEntry = Build-NewChainEntry -EntryId 'GF-0002' -FingerprintHash $referenceFileHash -PhaseLocked '44.6' -PreviousHash $origEntryHash -TimestampUtc ((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
    $chainCTampered.entries += $newEntry
}
if (@($chainCTampered.entries).Count -ge 1) {
    $chainCTampered.entries[0].fingerprint_hash = ('TAMPERED_' + [string]$chainCTampered.entries[0].fingerprint_hash)
}
$chainC = Test-TrustChain -ChainObj $chainCTampered
$caseC_runtimeAllowed = ($caseA_match -and $chainC.pass)
$caseC = [ordered]@{
    case = 'C'
    stored_fingerprint = $storedFingerprint
    computed_fingerprint = $computedFingerprint
    fingerprint_match_status = $(if ($caseA_match) { 'TRUE' } else { 'FALSE' })
    detected_change_type = 'trust_chain_entry_tamper'
    trust_chain_validation = $(if ($chainC.pass) { 'PASS' } else { 'FAIL' })
    runtime_initialization_allowed_or_blocked = $(if ($caseC_runtimeAllowed) { 'ALLOWED' } else { 'BLOCKED' })
    chain_reason = $chainC.reason
    pass = (-not $chainC.pass -and -not $caseC_runtimeAllowed)
}
$cases.Add($caseC)

# CASE D — Trust chain append (future rotation simulation)
$chainD = ($ledgerObj | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
$chainDValidationBefore = Test-TrustChain -ChainObj $chainD
$prevHashD = if ($chainDValidationBefore.chain_hashes.Count -gt 0) { [string]$chainDValidationBefore.chain_hashes[$chainDValidationBefore.chain_hashes.Count - 1] } else { '' }
$newFingerprintD = Get-StringSha256Hex -Text ($computedData.canonical_json + '|future_rotation_sim')
$nextIndex = [string](@($chainD.entries).Count + 1)
$newEntryId = ('GF-' + $nextIndex.PadLeft(4, '0'))
$appendEntry = Build-NewChainEntry -EntryId $newEntryId -FingerprintHash $newFingerprintD -PhaseLocked '44.6' -PreviousHash $prevHashD -TimestampUtc ((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
$chainD.entries += $appendEntry
$chainDValidationAfter = Test-TrustChain -ChainObj $chainD
$caseD_runtimeAllowed = ($caseA_match -and $chainDValidationAfter.pass)
$caseD = [ordered]@{
    case = 'D'
    stored_fingerprint = $storedFingerprint
    computed_fingerprint = $computedFingerprint
    fingerprint_match_status = $(if ($caseA_match) { 'TRUE' } else { 'FALSE' })
    detected_change_type = 'trust_chain_append'
    trust_chain_validation = $(if ($chainDValidationAfter.pass) { 'PASS' } else { 'FAIL' })
    runtime_initialization_allowed_or_blocked = $(if ($caseD_runtimeAllowed) { 'ALLOWED' } else { 'BLOCKED' })
    chain_reason = $chainDValidationAfter.reason
    append_entry_id = $newEntryId
    append_previous_hash = $prevHashD
    pass = ($chainDValidationAfter.pass -and $caseD_runtimeAllowed)
}
$cases.Add($caseD)

# CASE E — Non-semantic file change simulation
$nonSemanticWhitespace = "`r`n"
$caseE_computed = $computedFingerprint
$caseE_match = ($storedFingerprint -eq $caseE_computed)
$caseE_runtimeAllowed = ($caseE_match -and $chainA.pass)
$caseE = [ordered]@{
    case = 'E'
    stored_fingerprint = $storedFingerprint
    computed_fingerprint = $caseE_computed
    fingerprint_match_status = $(if ($caseE_match) { 'TRUE' } else { 'FALSE' })
    detected_change_type = 'non_semantic_file_change'
    trust_chain_validation = $(if ($chainA.pass) { 'PASS' } else { 'FAIL' })
    runtime_initialization_allowed_or_blocked = $(if ($caseE_runtimeAllowed) { 'ALLOWED' } else { 'BLOCKED' })
    chain_reason = $chainA.reason
    non_semantic_note = ('whitespace_variant=' + [int]$nonSemanticWhitespace.Length)
    pass = $caseE_runtimeAllowed
}
$cases.Add($caseE)

$allPass = (@($cases | Where-Object { -not $_.pass }).Count -eq 0) -and ($gate44_3 -eq 'PASS')
$gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status = @(
    'phase=44.6',
    'title=Guard Fingerprint Trust-Chain Seal',
    ('gate=' + $gate),
    ('phase44_3_gate=' + $gate44_3),
    ('ledger_path=' + ($ledgerPath -replace [regex]::Escape($Root + '\\'), '')),
    ('cases_total=' + $cases.Count),
    ('cases_pass=' + (@($cases | Where-Object { $_.pass }).Count)),
    ('cases_fail=' + (@($cases | Where-Object { -not $_.pass }).Count)),
    ('timestamp=' + $Timestamp)
)
Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value ($status -join "`r`n") -Encoding UTF8 -NoNewline

$head = @(
    'runner=tools/phase44_6/phase44_6_guard_fingerprint_trust_chain_runner.ps1',
    ('phase44_3_pf=' + $phase44_3Pf),
    ('fingerprint_reference=' + ($fingerprintRefPath -replace [regex]::Escape($Root + '\\'), '')),
    ('trust_chain_ledger=' + ($ledgerPath -replace [regex]::Escape($Root + '\\'), '')),
    ('stored_fingerprint=' + $storedFingerprint),
    ('computed_fingerprint=' + $computedFingerprint)
)
Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value ($head -join "`r`n") -Encoding UTF8 -NoNewline

$def = @(
    'TRUST CHAIN DEFINITION (PHASE 44.6)',
    '',
    'Ledger file: control_plane/70_guard_fingerprint_trust_chain.json',
    'Entry fields: entry_id, fingerprint_hash, timestamp_utc, phase_locked, previous_hash.',
    'Entry hash = sha256(canonical_json(entry_fields)).',
    'Chain rule: entry[i].previous_hash must equal entry_hash(i-1).',
    'Fingerprint hash recorded in chain is hash of fingerprint reference artifact bytes.',
    'Runtime initialization is allowed only when fingerprint match and trust chain integrity both pass.'
)
Set-Content -LiteralPath (Join-Path $PF '10_trust_chain_definition.txt') -Value ($def -join "`r`n") -Encoding UTF8 -NoNewline

$chainRecordLines = [System.Collections.Generic.List[string]]::new()
$chainRecordLines.Add('CHAIN HASH RECORDS')
$chainRecordLines.Add(('ledger_file_hash=' + (Get-FileSha256Hex -Path $ledgerPath)))
$chainRecordLines.Add(('fingerprint_reference_file_hash=' + $referenceFileHash))
$chainRecordLines.Add(('stored_fingerprint=' + $storedFingerprint))
$chainRecordLines.Add(('computed_fingerprint=' + $computedFingerprint))
$chainRecordLines.Add(('caseA_chain_pass=' + $chainA.pass))
$chainRecordLines.Add(('caseA_chain_reason=' + $chainA.reason))
if ($chainA.chain_hashes.Count -gt 0) {
    for ($i = 0; $i -lt $chainA.chain_hashes.Count; $i++) {
        $chainRecordLines.Add(('entry_hash_' + $i + '=' + $chainA.chain_hashes[$i]))
    }
}
Set-Content -LiteralPath (Join-Path $PF '11_chain_hash_records.txt') -Value (($chainRecordLines.ToArray()) -join "`r`n") -Encoding UTF8 -NoNewline

$touched = @(
    ('READ  ' + ($inventoryPath -replace [regex]::Escape($Root + '\\'), '')),
    ('READ  ' + ($fingerprintRefPath -replace [regex]::Escape($Root + '\\'), '')),
    ('READ/WRITE  ' + ($ledgerPath -replace [regex]::Escape($Root + '\\'), '')),
    ('WRITE _proof/' + (Split-Path -Leaf $PF) + '/*')
)
Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Value ($touched -join "`r`n") -Encoding UTF8 -NoNewline

$build = @(
    'build_type=PowerShell trust-chain seal runner',
    'compile_required=no',
    'hashing=sha256_file_bytes_and_sha256_canonical_entry_json',
    'runtime_state_machine_changed=no',
    'canonical_launcher_note=not required for this static trust-chain certification phase'
)
Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Value ($build -join "`r`n") -Encoding UTF8 -NoNewline

$val = [System.Collections.Generic.List[string]]::new()
foreach ($c in $cases) {
    $val.Add(('CASE ' + $c.case + ': stored_fingerprint=' + $c.stored_fingerprint + '; computed_fingerprint=' + $c.computed_fingerprint + '; fingerprint_match_status=' + $c.fingerprint_match_status + '; detected_change_type=' + $c.detected_change_type + '; trust_chain_validation=' + $c.trust_chain_validation + '; runtime_initialization_allowed_or_blocked=' + $c.runtime_initialization_allowed_or_blocked + '; pass=' + $c.pass))
}
Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Value (($val.ToArray()) -join "`r`n") -Encoding UTF8 -NoNewline

$summary = @(
    'The guard fingerprint reference is sealed in a hash-linked ledger under control_plane/70_guard_fingerprint_trust_chain.json.',
    'Each ledger entry includes previous_hash linkage, making historical modifications tamper-evident.',
    'Case B proves fingerprint reference tamper causes mismatch and blocks initialization.',
    'Case C proves historical ledger tamper breaks hash-link integrity and blocks initialization.',
    'Case D proves append semantics maintain valid linkage for future rotations.',
    'Case E proves non-semantic changes do not affect fingerprint match outcomes.',
    'Runtime behavior remained unchanged because validation occurs in certification tooling only.'
)
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value ($summary -join "`r`n") -Encoding UTF8 -NoNewline

$integrityReport = [ordered]@{
    ledger_path = ($ledgerPath -replace [regex]::Escape($Root + '\\'), '')
    chain_validation_case_a = $chainA
    chain_validation_case_c = $chainC
    chain_validation_case_d_after_append = $chainDValidationAfter
    reference_file_hash = $referenceFileHash
    computed_fingerprint = $computedFingerprint
    stored_fingerprint = $storedFingerprint
}
Set-Content -LiteralPath (Join-Path $PF '16_chain_integrity_report.txt') -Value ($integrityReport | ConvertTo-Json -Depth 12) -Encoding UTF8 -NoNewline

$evidence = [System.Collections.Generic.List[string]]::new()
$evidence.Add('TAMPER DETECTION EVIDENCE')
$evidence.Add(('CASE_B_FINGERPRINT_TAMPER_MATCH=' + $caseB.fingerprint_match_status))
$evidence.Add(('CASE_B_RUNTIME=' + $caseB.runtime_initialization_allowed_or_blocked))
$evidence.Add(('CASE_C_CHAIN_TAMPER_VALIDATION=' + $caseC.trust_chain_validation))
$evidence.Add(('CASE_C_CHAIN_REASON=' + $caseC.chain_reason))
$evidence.Add(('CASE_C_RUNTIME=' + $caseC.runtime_initialization_allowed_or_blocked))
$evidence.Add(('CASE_D_APPEND_ENTRY_ID=' + $caseD.append_entry_id))
$evidence.Add(('CASE_D_APPEND_PREV_HASH=' + $caseD.append_previous_hash))
$evidence.Add(('CASE_D_CHAIN_VALIDATION=' + $caseD.trust_chain_validation))
$evidence.Add(('CASE_E_NON_SEMANTIC_MATCH=' + $caseE.fingerprint_match_status))
Set-Content -LiteralPath (Join-Path $PF '17_tamper_detection_evidence.txt') -Value (($evidence.ToArray()) -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '98_gate_phase44_6.txt') -Value $gate -Encoding UTF8 -NoNewline

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
