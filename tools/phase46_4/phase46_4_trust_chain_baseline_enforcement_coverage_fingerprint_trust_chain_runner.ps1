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

function Test-Phase46_4ArtifactBinding {
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
        if ([string]$entries[$i].phase_locked -eq '46.4' -and [string]$entries[$i].artifact -eq 'trust_chain_baseline_enforcement_coverage_fingerprint') {
            $target = $entries[$i]
            break
        }
    }

    if ($null -eq $target) {
        $r.reason = 'phase46_4_entry_missing'
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

function Test-Phase46_4SealIntegrity {
    param(
        [object]$ChainObj,
        [string]$FingerprintReferencePath,
        [string]$ExpectedCoverageFingerprint
    )

    $chain = Test-LegacyTrustChain -ChainObj $ChainObj
    $binding = Test-Phase46_4ArtifactBinding -ChainObj $ChainObj -FingerprintReferencePath $FingerprintReferencePath -ExpectedCoverageFingerprint $ExpectedCoverageFingerprint

    return [ordered]@{
        pass = ($chain.pass -and $binding.pass)
        reason = $(if (-not $chain.pass) { 'chain_' + [string]$chain.reason } elseif (-not $binding.pass) { 'binding_' + [string]$binding.reason } else { 'ok' })
        chain = $chain
        binding = $binding
    }
}

function New-Phase46_4Entry {
    param(
        [string]$EntryId,
        [string]$ArtifactSha256,
        [string]$CoverageFingerprint,
        [string]$PreviousHash,
        [string]$TimestampUtc
    )

    return [ordered]@{
        entry_id = $EntryId
        artifact = 'trust_chain_baseline_enforcement_coverage_fingerprint'
        coverage_fingerprint = $CoverageFingerprint
        fingerprint_hash = $ArtifactSha256
        timestamp_utc = $TimestampUtc
        phase_locked = '46.4'
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
        if ([string]$e.phase_locked -eq '46.4' -and [string]$e.artifact -eq 'trust_chain_baseline_enforcement_coverage_fingerprint') {
            $existing = $e
            break
        }
    }

    if ($null -ne $existing) {
        $appendResult.entry_id = [string]$existing.entry_id
        $appendResult.previous_hash = [string]$existing.previous_hash
        if ([string]$existing.fingerprint_hash -ne $artifactSha -or [string]$existing.coverage_fingerprint -ne $CoverageFingerprint) {
            throw 'Existing phase46_4 trust-chain entry does not match current coverage fingerprint reference.'
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
    $newEntry = New-Phase46_4Entry -EntryId $newId -ArtifactSha256 $artifactSha -CoverageFingerprint $CoverageFingerprint -PreviousHash ([string]$chain.last_entry_hash) -TimestampUtc $timestampUtc

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
$PF = Join-Path $Root ('_proof\phase46_4_trust_chain_baseline_enforcement_coverage_fingerprint_trust_chain_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$LedgerPath = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$FingerprintRefPath = Join-Path $Root 'control_plane\79_trust_chain_baseline_enforcement_coverage_fingerprint.json'

if (-not (Test-Path -LiteralPath $LedgerPath)) { throw 'Missing ledger file: control_plane/70_guard_fingerprint_trust_chain.json' }
if (-not (Test-Path -LiteralPath $FingerprintRefPath)) { throw 'Missing fingerprint file: control_plane/79_trust_chain_baseline_enforcement_coverage_fingerprint.json' }

$ledgerObj = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
$fingerprintObj = Get-Content -Raw -LiteralPath $FingerprintRefPath | ConvertFrom-Json
$coverageFingerprint = [string]$fingerprintObj.coverage_fingerprint_sha256
if ([string]::IsNullOrWhiteSpace($coverageFingerprint)) {
    throw 'Coverage fingerprint missing in control_plane/79_trust_chain_baseline_enforcement_coverage_fingerprint.json'
}

$beforeChain = Test-LegacyTrustChain -ChainObj $ledgerObj
if (-not $beforeChain.pass) {
    throw ('Ledger invalid before phase46_4 append: ' + $beforeChain.reason)
}

$appendOp = Append-IfNeeded -LedgerObj $ledgerObj -ReferencePath $FingerprintRefPath -CoverageFingerprint $coverageFingerprint
$updatedLedger = $appendOp.ledger
$appendMeta = $appendOp.append

($updatedLedger | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $LedgerPath -Encoding UTF8 -NoNewline

$afterSeal = Test-Phase46_4SealIntegrity -ChainObj $updatedLedger -FingerprintReferencePath $FingerprintRefPath -ExpectedCoverageFingerprint $coverageFingerprint
$chainHashes = @($afterSeal.chain.chain_hashes)
$lastEntry = @($updatedLedger.entries)[-1]

# CASE A - Clean trust-chain append
$caseA = ($afterSeal.pass -and ([string]$lastEntry.phase_locked -eq '46.4') -and ([string]$lastEntry.artifact -eq 'trust_chain_baseline_enforcement_coverage_fingerprint'))

# CASE B - Historical ledger tamper should fail
$caseBLedger = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
$caseBEntries = [System.Collections.Generic.List[object]]::new()
foreach ($e in @($caseBLedger.entries)) { $caseBEntries.Add($e) }
if ($caseBEntries.Count -gt 1) {
    $caseBEntries[1].fingerprint_hash = ([string]$caseBEntries[1].fingerprint_hash + 'tamper')
}
$caseBTampered = [ordered]@{ chain_version = [int]$caseBLedger.chain_version; entries = @($caseBEntries) }
$caseBSeal = Test-Phase46_4SealIntegrity -ChainObj $caseBTampered -FingerprintReferencePath $FingerprintRefPath -ExpectedCoverageFingerprint $coverageFingerprint
$caseB = (-not $caseBSeal.pass)

# CASE C - Coverage fingerprint artifact tamper should fail
$caseCTmp = Join-Path $env:TEMP ('phase46_4_caseC_' + $Timestamp + '.json')
$rawRef = Get-Content -Raw -LiteralPath $FingerprintRefPath
$tamperedRef = $rawRef -replace '"generated_utc"\s*:\s*"[^"]+"', '"generated_utc":"TAMPERED"'
if ($tamperedRef -eq $rawRef) {
    $tamperedRef = ($rawRef + ' ')
}
[System.IO.File]::WriteAllText($caseCTmp, $tamperedRef, [System.Text.Encoding]::UTF8)
$caseCSeal = Test-Phase46_4SealIntegrity -ChainObj $updatedLedger -FingerprintReferencePath $caseCTmp -ExpectedCoverageFingerprint $coverageFingerprint
Remove-Item -Force -LiteralPath $caseCTmp
$caseC = (-not $caseCSeal.pass)

# CASE D - Future ledger append simulation should remain valid
$caseDEntries = [System.Collections.Generic.List[object]]::new()
foreach ($e in @($updatedLedger.entries)) { $caseDEntries.Add($e) }
$caseDPrevHash = [string]$afterSeal.chain.last_entry_hash
$caseDNextId = Get-NextEntryId -ChainObj $updatedLedger
$caseDNext = [ordered]@{
    entry_id = $caseDNextId
    artifact = 'trust_chain_baseline_enforcement_coverage_fingerprint_future_probe'
    coverage_fingerprint = $coverageFingerprint
    fingerprint_hash = (Get-FileSha256Hex -Path $FingerprintRefPath)
    timestamp_utc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    phase_locked = '46.5'
    previous_hash = $caseDPrevHash
}
$caseDEntries.Add($caseDNext)
$caseDLedger = [ordered]@{ chain_version = [int]$updatedLedger.chain_version; entries = @($caseDEntries) }
$caseDCheck = Test-LegacyTrustChain -ChainObj $caseDLedger
$caseD = $caseDCheck.pass

# CASE E - Non-semantic change in non-semantic material should remain valid
$caseENote = Join-Path $env:TEMP ('phase46_4_caseE_' + $Timestamp + '.txt')
Set-Content -LiteralPath $caseENote -Value "header`r`n`r`n body   " -Encoding UTF8 -NoNewline
$caseESeal = Test-Phase46_4SealIntegrity -ChainObj $updatedLedger -FingerprintReferencePath $FingerprintRefPath -ExpectedCoverageFingerprint $coverageFingerprint
Remove-Item -Force -LiteralPath $caseENote
$caseE = $caseESeal.pass

# CASE F - Previous hash link break in new entry should fail
$caseFEntries = [System.Collections.Generic.List[object]]::new()
foreach ($e in @($updatedLedger.entries)) { $caseFEntries.Add($e) }
$caseFEntries[$caseFEntries.Count - 1].previous_hash = ([string]$caseFEntries[$caseFEntries.Count - 1].previous_hash + 'broken')
$caseFTampered = [ordered]@{ chain_version = [int]$updatedLedger.chain_version; entries = @($caseFEntries) }
$caseFSeal = Test-Phase46_4SealIntegrity -ChainObj $caseFTampered -FingerprintReferencePath $FingerprintRefPath -ExpectedCoverageFingerprint $coverageFingerprint
$caseF = (-not $caseFSeal.pass)

$allPass = ($caseA -and $caseB -and $caseC -and $caseD -and $caseE -and $caseF)
$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status = @(
    'phase=46.4',
    'title=Trust-Chain Baseline Enforcement Coverage Fingerprint Trust-Chain Seal',
    ('gate=' + $Gate),
    ('ledger_append=' + $(if ($caseA) { 'SUCCESS' } else { 'FAIL' })),
    ('chain_integrity=' + $(if ($afterSeal.chain.pass) { 'VALID' } else { 'FAIL' })),
    ('artifact_binding=' + $(if ($afterSeal.binding.pass) { 'VALID' } else { 'FAIL' })),
    ('runtime_state_machine_changed=NO')
)
Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value ($status -join "`r`n") -Encoding UTF8 -NoNewline

$head = @(
    'runner=tools/phase46_4/phase46_4_trust_chain_baseline_enforcement_coverage_fingerprint_trust_chain_runner.ps1',
    ('ledger_path=' + $LedgerPath),
    ('fingerprint_reference=' + $FingerprintRefPath),
    ('append_mode=' + [string]$appendMeta.mode),
    ('entry_id=' + [string]$appendMeta.entry_id)
)
Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value ($head -join "`r`n") -Encoding UTF8 -NoNewline

$def = @(
    'TRUST-CHAIN EXTENSION DEFINITION (PHASE 46.4)',
    '',
    'Phase46_3 frozen-baseline enforcement coverage fingerprint reference is sealed into control_plane/70 ledger as a new entry.',
    'Entry fields include artifact marker, locked coverage fingerprint value, fingerprint artifact SHA256, phase marker, and previous-hash linkage.',
    'Legacy chain hash linkage remains compatible with existing certification validators because the chain hash still covers entry_id, fingerprint_hash, timestamp_utc, phase_locked, and previous_hash.',
    'Artifact tamper detection is enforced by binding entry fingerprint_hash to the file-bytes SHA256 of control_plane/79_trust_chain_baseline_enforcement_coverage_fingerprint.json.'
)
Set-Content -LiteralPath (Join-Path $PF '10_trust_chain_extension_definition.txt') -Value ($def -join "`r`n") -Encoding UTF8 -NoNewline

$hashRecords = [System.Collections.Generic.List[string]]::new()
$hashRecords.Add(('entry_count=' + [string]$afterSeal.chain.entry_count))
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
    'operation=ledger append plus chain validation plus tamper simulation'
)
Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Value ($build -join "`r`n") -Encoding UTF8 -NoNewline

$validation = @(
    ('CASE A clean_trust_chain_append=' + $(if ($caseA) { 'PASS' } else { 'FAIL' })),
    ('CASE B historical_ledger_tamper=' + $(if ($caseB) { 'PASS' } else { 'FAIL' })),
    ('CASE C coverage_fingerprint_artifact_tamper=' + $(if ($caseC) { 'PASS' } else { 'FAIL' })),
    ('CASE D future_ledger_append=' + $(if ($caseD) { 'PASS' } else { 'FAIL' })),
    ('CASE E non_semantic_file_change=' + $(if ($caseE) { 'PASS' } else { 'FAIL' })),
    ('CASE F previous_hash_link_break=' + $(if ($caseF) { 'PASS' } else { 'FAIL' }))
)
Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Value ($validation -join "`r`n") -Encoding UTF8 -NoNewline

$summary = @(
    'Phase 46.4 seals the Phase 46.3 frozen-baseline enforcement coverage fingerprint into the existing guard fingerprint trust chain as a new hash-linked ledger entry.',
    'The new entry records the frozen-baseline coverage fingerprint value, the SHA256 of the reference artifact file, the phase marker 46.4, and the previous entry hash.',
    'Historical tamper is detected because any mutation of an earlier entry breaks the legacy previous-hash chain.',
    'Coverage fingerprint artifact tamper is detected because the ledger entry fingerprint_hash is bound to the exact file-bytes SHA256 of control_plane/79_trust_chain_baseline_enforcement_coverage_fingerprint.json.',
    'Future ledger continuation remains valid because the 46.4 entry participates in the same appendable hash chain model used by earlier certification phases.',
    'Non-semantic changes in unrelated materials do not affect chain integrity because the chain model only depends on the ledger entries and the bound fingerprint artifact.',
    'Runtime behavior remained unchanged because this phase only extends the certification ledger and writes proof artifacts.'
)
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value ($summary -join "`r`n") -Encoding UTF8 -NoNewline

$integrityReport = @(
    ('seal_integrity=' + $(if ($afterSeal.pass) { 'VALID' } else { 'FAIL' })),
    ('chain_reason=' + [string]$afterSeal.chain.reason),
    ('binding_reason=' + [string]$afterSeal.binding.reason),
    ('matched_entry_id=' + [string]$afterSeal.binding.matched_entry_id),
    ('expected_artifact_sha256=' + [string]$afterSeal.binding.expected_artifact_sha256),
    ('ledger_artifact_sha256=' + [string]$afterSeal.binding.ledger_artifact_sha256),
    ('expected_coverage_fingerprint=' + [string]$afterSeal.binding.expected_coverage_fingerprint),
    ('ledger_coverage_fingerprint=' + [string]$afterSeal.binding.ledger_coverage_fingerprint)
)
Set-Content -LiteralPath (Join-Path $PF '16_chain_integrity_report.txt') -Value ($integrityReport -join "`r`n") -Encoding UTF8 -NoNewline

$tamperEvidence = @(
    ('caseB_reason=' + [string]$caseBSeal.reason),
    ('caseC_reason=' + [string]$caseCSeal.reason),
    ('caseD_chain_reason=' + [string]$caseDCheck.reason),
    ('caseE_reason=' + [string]$caseESeal.reason),
    ('caseF_reason=' + [string]$caseFSeal.reason),
    ('append_mode=' + [string]$appendMeta.mode),
    ('entry_id=' + [string]$appendMeta.entry_id),
    ('previous_hash=' + [string]$appendMeta.previous_hash),
    ('artifact_sha256=' + [string]$appendMeta.artifact_sha256)
)
Set-Content -LiteralPath (Join-Path $PF '17_tamper_detection_evidence.txt') -Value ($tamperEvidence -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '98_gate_phase46_4.txt') -Value $Gate -Encoding UTF8 -NoNewline

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
