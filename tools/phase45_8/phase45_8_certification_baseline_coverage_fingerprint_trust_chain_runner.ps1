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

function Get-LegacyChainEntryCanonical {
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

function Get-LegacyChainEntryHash {
    param([object]$Entry)
    return Get-StringSha256Hex -Text (Get-LegacyChainEntryCanonical -Entry $Entry)
}

function Test-LegacyTrustChain {
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

        $hashes.Add((Get-LegacyChainEntryHash -Entry $entry))
    }

    $result.chain_hashes = @($hashes)
    $result.last_entry_hash = [string]$hashes[$hashes.Count - 1]
    return $result
}

function Test-Phase45_8ArtifactBinding {
    param(
        [object]$ChainObj,
        [string]$FingerprintReferencePath,
        [string]$ExpectedCoverageFingerprint
    )

    $r = [ordered]@{
        pass = $false
        reason = 'not_checked'
        matched_entry_id = ''
        expected_artifact_sha256 = ''
        ledger_artifact_sha256 = ''
        expected_coverage_fingerprint = ''
        ledger_coverage_fingerprint = ''
    }

    if (-not (Test-Path -LiteralPath $FingerprintReferencePath)) {
        $r.reason = 'fingerprint_reference_missing'
        return $r
    }

    $expectedArtifactSha = Get-FileSha256Hex -Path $FingerprintReferencePath
    $r.expected_artifact_sha256 = $expectedArtifactSha
    $r.expected_coverage_fingerprint = $ExpectedCoverageFingerprint

    $entries = @($ChainObj.entries)
    $target = $null
    for ($i = $entries.Count - 1; $i -ge 0; $i--) {
        if ([string]$entries[$i].phase_locked -eq '45.8' -and [string]$entries[$i].artifact -eq 'certification_baseline_coverage_fingerprint') {
            $target = $entries[$i]
            break
        }
    }

    if ($null -eq $target) {
        $r.reason = 'phase45_8_entry_missing'
        return $r
    }

    $r.matched_entry_id = [string]$target.entry_id
    $r.ledger_artifact_sha256 = [string]$target.fingerprint_hash
    $r.ledger_coverage_fingerprint = [string]$target.coverage_fingerprint

    if ($r.ledger_artifact_sha256 -ne $expectedArtifactSha) {
        $r.reason = 'artifact_sha_mismatch'
        return $r
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedCoverageFingerprint) -and $r.ledger_coverage_fingerprint -ne $ExpectedCoverageFingerprint) {
        $r.reason = 'coverage_fingerprint_mismatch'
        return $r
    }

    $r.pass = $true
    $r.reason = 'ok'
    return $r
}

function Get-NextEntryId {
    param([object]$ChainObj)

    $entries = @($ChainObj.entries)
    $max = 0
    foreach ($e in $entries) {
        $id = [string]$e.entry_id
        if ($id -match '^GF-(\d+)$') {
            $n = [int]$Matches[1]
            if ($n -gt $max) { $max = $n }
        }
    }
    return ('GF-' + ($max + 1).ToString('0000'))
}

function New-Phase45_8Entry {
    param(
        [string]$EntryId,
        [string]$ArtifactSha256,
        [string]$CoverageFingerprint,
        [string]$PreviousHash,
        [string]$TimestampUtc
    )

    return [ordered]@{
        entry_id = $EntryId
        artifact = 'certification_baseline_coverage_fingerprint'
        coverage_fingerprint = $CoverageFingerprint
        fingerprint_hash = $ArtifactSha256
        timestamp_utc = $TimestampUtc
        phase_locked = '45.8'
        previous_hash = $PreviousHash
    }
}

function Append-IfNeeded {
    param(
        [object]$LedgerObj,
        [string]$ReferencePath,
        [string]$CoverageFingerprint
    )

    $appendResult = [ordered]@{
        appended = $false
        entry_id = ''
        previous_hash = ''
        artifact_sha256 = ''
        mode = 'unknown'
    }

    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($e in @($LedgerObj.entries)) { $entries.Add($e) }

    $artifactSha = Get-FileSha256Hex -Path $ReferencePath
    $appendResult.artifact_sha256 = $artifactSha

    $existing = $null
    foreach ($e in @($entries)) {
        if ([string]$e.phase_locked -eq '45.8' -and [string]$e.artifact -eq 'certification_baseline_coverage_fingerprint') {
            $existing = $e
            break
        }
    }

    if ($null -ne $existing) {
        $appendResult.entry_id = [string]$existing.entry_id
        $appendResult.previous_hash = [string]$existing.previous_hash
        if ([string]$existing.fingerprint_hash -ne $artifactSha -or [string]$existing.coverage_fingerprint -ne $CoverageFingerprint) {
            throw 'Existing phase45_8 trust-chain entry does not match current coverage fingerprint reference.'
        }
        $appendResult.mode = 'already_sealed'
        return [ordered]@{ ledger = $LedgerObj; append = $appendResult }
    }

    $chain = Test-LegacyTrustChain -ChainObj $LedgerObj
    if (-not $chain.pass) {
        throw ('Cannot append to invalid chain: ' + $chain.reason)
    }

    $newId = Get-NextEntryId -ChainObj $LedgerObj
    $timestampUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $newEntry = New-Phase45_8Entry -EntryId $newId -ArtifactSha256 $artifactSha -CoverageFingerprint $CoverageFingerprint -PreviousHash ([string]$chain.last_entry_hash) -TimestampUtc $timestampUtc

    $entries.Add($newEntry)
    $newLedger = [ordered]@{
        chain_version = [int]$LedgerObj.chain_version
        entries = @($entries)
    }

    $appendResult.appended = $true
    $appendResult.entry_id = $newId
    $appendResult.previous_hash = [string]$chain.last_entry_hash
    $appendResult.mode = 'appended'

    return [ordered]@{ ledger = $newLedger; append = $appendResult }
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\phase45_8_certification_baseline_coverage_fingerprint_trust_chain_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$LedgerPath = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$FingerprintRefPath = Join-Path $Root 'control_plane\76_certification_baseline_coverage_fingerprint.json'

if (-not (Test-Path -LiteralPath $LedgerPath)) { throw 'Missing ledger file: control_plane/70_guard_fingerprint_trust_chain.json' }
if (-not (Test-Path -LiteralPath $FingerprintRefPath)) { throw 'Missing fingerprint file: control_plane/76_certification_baseline_coverage_fingerprint.json' }

$ledgerObj = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
$fingerprintObj = Get-Content -Raw -LiteralPath $FingerprintRefPath | ConvertFrom-Json
$coverageFingerprint = [string]$fingerprintObj.coverage_fingerprint_sha256
if ([string]::IsNullOrWhiteSpace($coverageFingerprint)) {
    throw 'Coverage fingerprint missing in control_plane/76_certification_baseline_coverage_fingerprint.json'
}

$beforeChain = Test-LegacyTrustChain -ChainObj $ledgerObj
if (-not $beforeChain.pass) {
    throw ('Ledger invalid before phase45_8 append: ' + $beforeChain.reason)
}

$appendOp = Append-IfNeeded -LedgerObj $ledgerObj -ReferencePath $FingerprintRefPath -CoverageFingerprint $coverageFingerprint
$updatedLedger = $appendOp.ledger
$appendMeta = $appendOp.append

($updatedLedger | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $LedgerPath -Encoding UTF8 -NoNewline

$afterChain = Test-LegacyTrustChain -ChainObj $updatedLedger
$afterBinding = Test-Phase45_8ArtifactBinding -ChainObj $updatedLedger -FingerprintReferencePath $FingerprintRefPath -ExpectedCoverageFingerprint $coverageFingerprint

$chainHashes = @($afterChain.chain_hashes)
$lastEntry = @($updatedLedger.entries)[-1]

# CASE A - Clean trust-chain append
$caseA = ($afterChain.pass -and $afterBinding.pass -and ([string]$lastEntry.phase_locked -eq '45.8') -and ([string]$lastEntry.artifact -eq 'certification_baseline_coverage_fingerprint'))

# CASE B - Historical ledger tamper should fail
$caseBLedger = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
$caseBEntries = [System.Collections.Generic.List[object]]::new()
foreach ($e in @($caseBLedger.entries)) { $caseBEntries.Add($e) }
if ($caseBEntries.Count -gt 0) {
    $caseBEntries[0].fingerprint_hash = ([string]$caseBEntries[0].fingerprint_hash + 'tamper')
}
$caseBTampered = [ordered]@{ chain_version = [int]$caseBLedger.chain_version; entries = @($caseBEntries) }
$caseBCheck = Test-LegacyTrustChain -ChainObj $caseBTampered
$caseB = (-not $caseBCheck.pass)

# CASE C - Coverage fingerprint artifact tamper should fail
$caseCTmp = Join-Path $env:TEMP ('phase45_8_caseC_' + $Timestamp + '.json')
$rawRef = Get-Content -Raw -LiteralPath $FingerprintRefPath
$tamperedRef = $rawRef -replace '"generated_utc"\s*:\s*"[^"]+"', '"generated_utc":"TAMPERED"'
if ($tamperedRef -eq $rawRef) {
    $tamperedRef = ($rawRef + ' ')
}
[System.IO.File]::WriteAllText($caseCTmp, $tamperedRef, [System.Text.Encoding]::UTF8)
$caseCBinding = Test-Phase45_8ArtifactBinding -ChainObj $updatedLedger -FingerprintReferencePath $caseCTmp -ExpectedCoverageFingerprint $coverageFingerprint
Remove-Item -Force -LiteralPath $caseCTmp
$caseC = (-not $caseCBinding.pass)

# CASE D - Future ledger append simulation should remain valid
$caseDEntries = [System.Collections.Generic.List[object]]::new()
foreach ($e in @($updatedLedger.entries)) { $caseDEntries.Add($e) }
$caseDPrevHash = [string]$afterChain.last_entry_hash
$caseDNextId = Get-NextEntryId -ChainObj $updatedLedger
$caseDNext = [ordered]@{
    entry_id = $caseDNextId
    artifact = 'certification_baseline_coverage_fingerprint_future_probe'
    coverage_fingerprint = $coverageFingerprint
    fingerprint_hash = (Get-FileSha256Hex -Path $FingerprintRefPath)
    timestamp_utc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    phase_locked = '45.9'
    previous_hash = $caseDPrevHash
}
$caseDEntries.Add($caseDNext)
$caseDLedger = [ordered]@{ chain_version = [int]$updatedLedger.chain_version; entries = @($caseDEntries) }
$caseDCheck = Test-LegacyTrustChain -ChainObj $caseDLedger
$caseD = $caseDCheck.pass

# CASE E - Non-semantic formatting change should remain valid
$ledgerPretty = $updatedLedger | ConvertTo-Json -Depth 20
$ledgerRoundTrip = $ledgerPretty | ConvertFrom-Json
$caseECheck = Test-LegacyTrustChain -ChainObj $ledgerRoundTrip
$caseEBinding = Test-Phase45_8ArtifactBinding -ChainObj $ledgerRoundTrip -FingerprintReferencePath $FingerprintRefPath -ExpectedCoverageFingerprint $coverageFingerprint
$caseE = ($caseECheck.pass -and $caseEBinding.pass)

# CASE F - Previous hash link break in new entry should fail
$caseFEntries = [System.Collections.Generic.List[object]]::new()
foreach ($e in @($updatedLedger.entries)) { $caseFEntries.Add($e) }
$caseFEntries[$caseFEntries.Count - 1].previous_hash = ([string]$caseFEntries[$caseFEntries.Count - 1].previous_hash + 'broken')
$caseFTampered = [ordered]@{ chain_version = [int]$updatedLedger.chain_version; entries = @($caseFEntries) }
$caseFCheck = Test-LegacyTrustChain -ChainObj $caseFTampered
$caseF = (-not $caseFCheck.pass)

$allPass = ($caseA -and $caseB -and $caseC -and $caseD -and $caseE -and $caseF)
$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status = @(
    'phase=45.8',
    'title=Certification Baseline Enforcement Coverage Fingerprint Trust-Chain Seal',
    ('gate=' + $Gate),
    ('ledger_append=' + $(if ($caseA) { 'SUCCESS' } else { 'FAIL' })),
    ('chain_integrity=' + $(if ($afterChain.pass) { 'VALID' } else { 'FAIL' })),
    ('artifact_binding=' + $(if ($afterBinding.pass) { 'VALID' } else { 'FAIL' })),
    ('runtime_state_machine_changed=NO')
)
Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value ($status -join "`r`n") -Encoding UTF8 -NoNewline

$head = @(
    'runner=tools/phase45_8/phase45_8_certification_baseline_coverage_fingerprint_trust_chain_runner.ps1',
    ('ledger_path=' + $LedgerPath),
    ('fingerprint_reference=' + $FingerprintRefPath),
    ('append_mode=' + [string]$appendMeta.mode),
    ('entry_id=' + [string]$appendMeta.entry_id)
)
Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value ($head -join "`r`n") -Encoding UTF8 -NoNewline

$def = @(
    'TRUST-CHAIN EXTENSION DEFINITION (PHASE 45.8)',
    '',
    'Phase45_7 certification-baseline coverage fingerprint reference is sealed into control_plane/70 ledger as a new entry.',
    'Entry fields include artifact marker, coverage fingerprint, fingerprint artifact SHA256, phase marker, and previous hash linkage.',
    'Legacy chain hash linkage remains compatible with existing certification validators.',
    'Artifact tamper detection is enforced by binding entry fingerprint_hash to file-bytes SHA256 of control_plane/76_certification_baseline_coverage_fingerprint.json.'
)
Set-Content -LiteralPath (Join-Path $PF '10_trust_chain_extension_definition.txt') -Value ($def -join "`r`n") -Encoding UTF8 -NoNewline

$hashRecords = [System.Collections.Generic.List[string]]::new()
$hashRecords.Add(('entry_count=' + [string]$afterChain.entry_count))
for ($i = 0; $i -lt $chainHashes.Count; $i++) {
    $entry = @($updatedLedger.entries)[$i]
    $hashRecords.Add(([string]$entry.entry_id + ' hash=' + [string]$chainHashes[$i] + ' prev=' + [string]$entry.previous_hash))
}
$hashRecords.Add(('last_entry_id=' + [string]$lastEntry.entry_id))
$hashRecords.Add(('last_entry_phase=' + [string]$lastEntry.phase_locked))
$hashRecords.Add(('last_entry_artifact=' + [string]$lastEntry.artifact))
$hashRecords.Add(('last_entry_coverage_fingerprint=' + [string]$lastEntry.coverage_fingerprint))
$hashRecords.Add(('last_entry_fingerprint_hash=' + [string]$lastEntry.fingerprint_hash))
Set-Content -LiteralPath (Join-Path $PF '11_chain_hash_records.txt') -Value ($hashRecords -join "`r`n") -Encoding UTF8 -NoNewline

$filesTouched = @(
    ('READ  ' + $LedgerPath),
    ('READ  ' + $FingerprintRefPath),
    ('WRITE ' + $LedgerPath),
    ('WRITE ' + (Join-Path $PF '*'))
)
Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Value ($filesTouched -join "`r`n") -Encoding UTF8 -NoNewline

$build = @(
    'build_type=PowerShell trust-chain append and validation runner',
    'compile_required=no',
    'runtime_behavior_changed=no',
    'operation=ledger append + chain validation + tamper simulation'
)
Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Value ($build -join "`r`n") -Encoding UTF8 -NoNewline

$validation = @(
    ('CASE A clean_trust_chain_append=' + $(if ($caseA) { 'PASS' } else { 'FAIL' })),
    ('CASE B historical_ledger_tamper=' + $(if ($caseB) { 'PASS' } else { 'FAIL' })),
    ('CASE C_coverage_fingerprint_artifact_tamper=' + $(if ($caseC) { 'PASS' } else { 'FAIL' })),
    ('CASE D future_ledger_append=' + $(if ($caseD) { 'PASS' } else { 'FAIL' })),
    ('CASE E non_semantic_change=' + $(if ($caseE) { 'PASS' } else { 'FAIL' })),
    ('CASE F previous_hash_link_break=' + $(if ($caseF) { 'PASS' } else { 'FAIL' }))
)
Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Value ($validation -join "`r`n") -Encoding UTF8 -NoNewline

$summary = @(
    'Phase 45.8 seals the Phase45_7 certification-baseline coverage fingerprint into the tamper-evident trust chain ledger.',
    'Ledger linkage remains valid through previous_hash continuity and deterministic per-entry hashing.',
    'Historical ledger tamper is detected via chain-link mismatch.',
    'Coverage fingerprint artifact tamper is detected via SHA256 mismatch against sealed fingerprint_hash.',
    'Future append simulation confirms chain extensibility.',
    'Formatting-only ledger changes do not affect validity.',
    'Corrupting the new entry previous_hash is detected as a chain integrity failure.',
    'No runtime state-machine behavior was modified.'
)
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value ($summary -join "`r`n") -Encoding UTF8 -NoNewline

$integrity = @(
    ('ledger_chain_valid=' + $(if ($afterChain.pass) { 'TRUE' } else { 'FALSE' })),
    ('ledger_chain_reason=' + [string]$afterChain.reason),
    ('artifact_binding_valid=' + $(if ($afterBinding.pass) { 'TRUE' } else { 'FALSE' })),
    ('artifact_binding_reason=' + [string]$afterBinding.reason),
    ('matched_entry_id=' + [string]$afterBinding.matched_entry_id),
    ('expected_artifact_sha256=' + [string]$afterBinding.expected_artifact_sha256),
    ('ledger_artifact_sha256=' + [string]$afterBinding.ledger_artifact_sha256),
    ('expected_coverage_fingerprint=' + [string]$afterBinding.expected_coverage_fingerprint),
    ('ledger_coverage_fingerprint=' + [string]$afterBinding.ledger_coverage_fingerprint)
)
Set-Content -LiteralPath (Join-Path $PF '16_chain_integrity_report.txt') -Value ($integrity -join "`r`n") -Encoding UTF8 -NoNewline

$tamperEvidence = @(
    ('caseB_chain_valid=' + $(if ($caseBCheck.pass) { 'TRUE' } else { 'FALSE' })),
    ('caseB_reason=' + [string]$caseBCheck.reason),
    ('caseC_binding_valid=' + $(if ($caseCBinding.pass) { 'TRUE' } else { 'FALSE' })),
    ('caseC_reason=' + [string]$caseCBinding.reason),
    ('caseD_chain_valid=' + $(if ($caseDCheck.pass) { 'TRUE' } else { 'FALSE' })),
    ('caseD_reason=' + [string]$caseDCheck.reason),
    ('caseE_chain_valid=' + $(if ($caseECheck.pass) { 'TRUE' } else { 'FALSE' })),
    ('caseE_binding_valid=' + $(if ($caseEBinding.pass) { 'TRUE' } else { 'FALSE' })),
    ('caseF_chain_valid=' + $(if ($caseFCheck.pass) { 'TRUE' } else { 'FALSE' })),
    ('caseF_reason=' + [string]$caseFCheck.reason)
)
Set-Content -LiteralPath (Join-Path $PF '17_tamper_detection_evidence.txt') -Value ($tamperEvidence -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '98_gate_phase45_8.txt') -Value $Gate -Encoding UTF8 -NoNewline

$ZIP = "$PF.zip"
$staging = "${PF}_copy"
if (Test-Path -LiteralPath $staging) {
    Remove-Item -Recurse -Force -LiteralPath $staging
}
New-Item -ItemType Directory -Path $staging | Out-Null
Get-ChildItem -Path $PF -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $staging $_.Name) -Force
}
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $ZIP -Force
Remove-Item -Recurse -Force -LiteralPath $staging

Write-Output "PF=$PF"
Write-Output "ZIP=$ZIP"
Write-Output "GATE=$Gate"
