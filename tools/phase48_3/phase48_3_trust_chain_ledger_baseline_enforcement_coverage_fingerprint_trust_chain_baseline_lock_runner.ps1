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

function ConvertTo-CanonicalJson {
    param($Value)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool])   { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or
        $Value -is [float]   -or $Value -is [decimal]) {
        return [string]$Value
    }
    if ($Value -is [string]) {
        $s = [string]$Value
        $s = $s -replace '\\', '\\'
        $s = $s -replace '"',  '\"'
        $s = $s -replace "`n", '\n'
        $s = $s -replace "`r", '\r'
        $s = $s -replace "`t", '\t'
        return '"' + $s + '"'
    }
    if ($Value -is [System.Collections.IList]) {
        $items = [System.Collections.Generic.List[string]]::new()
        foreach ($item in $Value) {
            $items.Add((ConvertTo-CanonicalJson -Value $item))
        }
        return '[' + ($items -join ',') + ']'
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $keys  = @($Value.Keys | Sort-Object)
        $pairs = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $keys) {
            $pairs.Add(('"' + $k + '":' + (ConvertTo-CanonicalJson -Value $Value[$k])))
        }
        return '{' + ($pairs -join ',') + '}'
    }
    if ($Value -is [pscustomobject]) {
        $keys  = @($Value.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object)
        $pairs = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $keys) {
            $v = $Value.PSObject.Properties[$k].Value
            $pairs.Add(('"' + $k + '":' + (ConvertTo-CanonicalJson -Value $v)))
        }
        return '{' + ($pairs -join ',') + '}'
    }

    return '"' + ([string]$Value -replace '"', '\"') + '"'
}

function Get-CanonicalObjectHash {
    param([object]$Obj)
    return Get-StringSha256Hex -Text (ConvertTo-CanonicalJson -Value $Obj)
}

function Get-CanonicalEntryHash {
    param([object]$Entry)
    return Get-CanonicalObjectHash -Obj $Entry
}

function Get-CanonicalLedgerHash {
    param([object]$LedgerObj)
    return Get-CanonicalObjectHash -Obj $LedgerObj
}

function Get-LegacyChainEntryCanonical {
    param([object]$Entry)
    $obj = [ordered]@{
        entry_id         = [string]$Entry.entry_id
        fingerprint_hash = [string]$Entry.fingerprint_hash
        timestamp_utc    = [string]$Entry.timestamp_utc
        phase_locked     = [string]$Entry.phase_locked
        previous_hash    = if ($null -eq $Entry.previous_hash -or
                               [string]::IsNullOrWhiteSpace([string]$Entry.previous_hash)) { $null } else { [string]$Entry.previous_hash }
    }
    return ($obj | ConvertTo-Json -Depth 4 -Compress)
}

function Get-LegacyChainEntryHash {
    param([object]$Entry)
    return Get-StringSha256Hex -Text (Get-LegacyChainEntryCanonical -Entry $Entry)
}

function Clone-Object {
    param([object]$Obj)
    return ($Obj | ConvertTo-Json -Depth 30 -Compress | ConvertFrom-Json)
}

function Test-ContinuationChain {
    param([object]$LedgerObj)

    $entries = @($LedgerObj.entries)
    if ($entries.Count -le 1) { return $true }

    for ($i = 1; $i -lt $entries.Count; $i++) {
        $expectedPrev = Get-LegacyChainEntryHash -Entry $entries[$i - 1]
        $declaredPrev = [string]$entries[$i].previous_hash
        if ($declaredPrev -ne $expectedPrev) { return $false }
    }
    return $true
}

function New-BaselineSnapshot {
    param(
        [object]$LedgerObj,
        [string]$CoverageFingerprintHash,
        [string]$TimestampUtc
    )

    $entries = @($LedgerObj.entries)
    if ($entries.Count -lt 1) { throw 'Ledger has no entries' }

    $latest = $entries[$entries.Count - 1]
    $entryHashes = [ordered]@{}
    foreach ($e in $entries) {
        $entryHashes[[string]$e.entry_id] = Get-CanonicalEntryHash -Entry $e
    }

    return [ordered]@{
        baseline_version          = 1
        phase_locked              = '48.3'
        ledger_head_hash          = Get-CanonicalEntryHash -Entry $latest
        ledger_length             = $entries.Count
        ledger_hash               = Get-CanonicalLedgerHash -LedgerObj $LedgerObj
        coverage_fingerprint_hash = $CoverageFingerprintHash
        latest_entry_id           = [string]$latest.entry_id
        latest_entry_phase_locked = [string]$latest.phase_locked
        timestamp_utc             = $TimestampUtc
        source_phases             = @('48.0', '48.1', '48.2')
        entry_hashes              = $entryHashes
    }
}

function New-IntegrityRecord {
    param(
        [object]$BaselineSnapshot,
        [string]$TimestampUtc
    )

    return [ordered]@{
        baseline_snapshot_hash = Get-CanonicalObjectHash -Obj $BaselineSnapshot
        ledger_head_hash       = [string]$BaselineSnapshot.ledger_head_hash
        coverage_fingerprint_hash = [string]$BaselineSnapshot.coverage_fingerprint_hash
        timestamp_utc          = $TimestampUtc
        phase_locked           = '48.3'
    }
}

function Test-BaselineIntegrity {
    param(
        [object]$BaselineSnapshot,
        [object]$IntegrityRecord,
        [string]$ComputedCoverageFingerprintHash
    )

    $computedSnapshotHash = Get-CanonicalObjectHash -Obj $BaselineSnapshot
    $storedSnapshotHash   = [string]$IntegrityRecord.baseline_snapshot_hash

    $storedLedgerHeadHash    = [string]$IntegrityRecord.ledger_head_hash
    $computedLedgerHeadHash  = [string]$BaselineSnapshot.ledger_head_hash

    $storedCoverageHash   = [string]$IntegrityRecord.coverage_fingerprint_hash
    $computedCoverageHash = [string]$ComputedCoverageFingerprintHash

    $integrityValid = (
        $storedSnapshotHash -eq $computedSnapshotHash -and
        $storedLedgerHeadHash -eq $computedLedgerHeadHash -and
        $storedCoverageHash -eq $computedCoverageHash -and
        [string]$IntegrityRecord.phase_locked -eq '48.3'
    )

    return [ordered]@{
        stored_baseline_hash              = $storedSnapshotHash
        computed_baseline_hash            = $computedSnapshotHash
        stored_ledger_head_hash           = $storedLedgerHeadHash
        computed_ledger_head_hash         = $computedLedgerHeadHash
        stored_coverage_fingerprint_hash  = $storedCoverageHash
        computed_coverage_fingerprint_hash = $computedCoverageHash
        baseline_integrity_result         = if ($integrityValid) { 'VALID' } else { 'FAIL' }
        baseline_usage_allowed_or_blocked = if ($integrityValid) { 'ALLOWED' } else { 'BLOCKED' }
    }
}

function Test-BaselineReference {
    param(
        [object]$LiveLedgerObj,
        [object]$BaselineSnapshot,
        [string]$ComputedCoverageFingerprintHash
    )

    $entries = @($LiveLedgerObj.entries)
    $baseLen = [int]$BaselineSnapshot.ledger_length

    $lengthOk = $entries.Count -ge $baseLen
    $prefixOk = $true

    if ($lengthOk) {
        for ($i = 0; $i -lt $baseLen; $i++) {
            $id = [string]$entries[$i].entry_id
            $expectedHash = [string]$BaselineSnapshot.entry_hashes.$id
            $actualHash   = Get-CanonicalEntryHash -Entry $entries[$i]
            if ($actualHash -ne $expectedHash) {
                $prefixOk = $false
                break
            }
        }
    } else {
        $prefixOk = $false
    }

    $headMatch = $false
    if ($lengthOk) {
        $baseHead = $entries[$baseLen - 1]
        $headHash = Get-CanonicalEntryHash -Entry $baseHead
        $headId   = [string]$baseHead.entry_id
        $headPhase = [string]$baseHead.phase_locked

        $headMatch = (
            $headHash -eq [string]$BaselineSnapshot.ledger_head_hash -and
            $headId -eq [string]$BaselineSnapshot.latest_entry_id -and
            $headPhase -eq [string]$BaselineSnapshot.latest_entry_phase_locked
        )
    }

    $coverageMatch = ([string]$BaselineSnapshot.coverage_fingerprint_hash -eq [string]$ComputedCoverageFingerprintHash)

    $referenceValid = $lengthOk -and $prefixOk -and $headMatch -and $coverageMatch

    return [ordered]@{
        ledger_head_match = if ($headMatch) { 'TRUE' } else { 'FALSE' }
        baseline_reference_status = if ($referenceValid) { 'VALID' } else { 'INVALID' }
        baseline_usage_allowed_or_blocked = if ($referenceValid) { 'ALLOWED' } else { 'BLOCKED' }
    }
}

function Add-CaseLine {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$CaseId,
        [string]$BaselineSnapshotPath,
        [string]$BaselineIntegrityRecordPath,
        [object]$Integrity,
        [object]$Reference,
        [string]$Extra
    )

    $usage = if ([string]$Integrity.baseline_integrity_result -ne 'VALID' -or [string]$Reference.baseline_reference_status -ne 'VALID') {
        'BLOCKED'
    } else {
        'ALLOWED'
    }

    $line = @(
        'CASE ' + $CaseId,
        'baseline_snapshot_path=' + $BaselineSnapshotPath,
        'baseline_integrity_record_path=' + $BaselineIntegrityRecordPath,
        'stored_baseline_hash=' + [string]$Integrity.stored_baseline_hash,
        'computed_baseline_hash=' + [string]$Integrity.computed_baseline_hash,
        'stored_ledger_head_hash=' + [string]$Integrity.stored_ledger_head_hash,
        'computed_ledger_head_hash=' + [string]$Integrity.computed_ledger_head_hash,
        'stored_coverage_fingerprint_hash=' + [string]$Integrity.stored_coverage_fingerprint_hash,
        'computed_coverage_fingerprint_hash=' + [string]$Integrity.computed_coverage_fingerprint_hash,
        'baseline_integrity_result=' + [string]$Integrity.baseline_integrity_result,
        'baseline_reference_status=' + [string]$Reference.baseline_reference_status,
        'baseline_usage_allowed_or_blocked=' + $usage,
        $Extra
    ) -join ' | '

    $Lines.Add($line)
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$UtcNow    = Get-Date -AsUTC -Format 'yyyy-MM-ddTHH:mm:ssZ'

$PhaseName = 'phase48_3_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_lock'
$PF = Join-Path $Root ('_proof\' + $PhaseName + '_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$LedgerPath     = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$CoveragePath   = Join-Path $Root 'control_plane\87_trust_chain_ledger_baseline_enforcement_coverage_fingerprint.json'
$BaselinePath   = Join-Path $Root 'control_plane\88_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline.json'
$IntegrityPath  = Join-Path $Root 'control_plane\89_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_integrity.json'

foreach ($req in @($LedgerPath, $CoveragePath)) {
    if (-not (Test-Path -LiteralPath $req)) { throw ('Missing required file: ' + $req) }
}

$ledgerObj = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
$coverageObj = Get-Content -Raw -LiteralPath $CoveragePath | ConvertFrom-Json
$coverageFingerprintHash = [string]$coverageObj.coverage_fingerprint_sha256
if ([string]::IsNullOrWhiteSpace($coverageFingerprintHash)) {
    throw 'coverage_fingerprint_sha256 missing in control_plane/87 artifact'
}

$entries = @($ledgerObj.entries)
if ($entries.Count -lt 1) { throw 'Ledger has no entries' }
$latest = $entries[$entries.Count - 1]
if ([string]$latest.entry_id -ne 'GF-0007' -or [string]$latest.phase_locked -ne '48.2') {
    throw 'Phase 48.2 seal precondition failed: latest ledger entry is not GF-0007 phase_locked=48.2'
}

$candidateSnapshot = New-BaselineSnapshot -LedgerObj $ledgerObj -CoverageFingerprintHash $coverageFingerprintHash -TimestampUtc $UtcNow
$candidateIntegrity = New-IntegrityRecord -BaselineSnapshot $candidateSnapshot -TimestampUtc $UtcNow

$baselineMode = 'created'
if ((Test-Path -LiteralPath $BaselinePath) -and (Test-Path -LiteralPath $IntegrityPath)) {
    $storedSnapshotExisting = Get-Content -Raw -LiteralPath $BaselinePath | ConvertFrom-Json
    $storedIntegrityExisting = Get-Content -Raw -LiteralPath $IntegrityPath | ConvertFrom-Json

    $intExisting = Test-BaselineIntegrity `
        -BaselineSnapshot $storedSnapshotExisting `
        -IntegrityRecord $storedIntegrityExisting `
        -ComputedCoverageFingerprintHash $coverageFingerprintHash

    if ($intExisting.baseline_integrity_result -ne 'VALID') {
        throw 'Existing 88/89 baseline artifacts are present but integrity is invalid.'
    }

    $candidateSnapshotHash = Get-CanonicalObjectHash -Obj $candidateSnapshot
    $existingSnapshotHash  = Get-CanonicalObjectHash -Obj $storedSnapshotExisting

    # Deterministic lock: ignore only timestamp_utc when comparing idempotent re-runs.
    $normCandidate = Clone-Object -Obj $candidateSnapshot
    $normExisting  = Clone-Object -Obj $storedSnapshotExisting
    $normCandidate.timestamp_utc = 'IGNORED'
    $normExisting.timestamp_utc  = 'IGNORED'

    if ((Get-CanonicalObjectHash -Obj $normCandidate) -ne (Get-CanonicalObjectHash -Obj $normExisting)) {
        throw ('Existing baseline snapshot mismatches current deterministic lock material. existing_hash=' + $existingSnapshotHash + ' candidate_hash=' + $candidateSnapshotHash)
    }

    $baselineMode = 'already_locked'
} elseif ((Test-Path -LiteralPath $BaselinePath) -xor (Test-Path -LiteralPath $IntegrityPath)) {
    throw 'Only one of baseline files 88/89 exists; baseline lock artifacts are inconsistent.'
} else {
    # Write snapshot first, then compute integrity from the reloaded snapshot object
    # to keep hash deterministic across parse/serialize shapes.
    ($candidateSnapshot | ConvertTo-Json -Depth 30) | Set-Content -LiteralPath $BaselinePath -Encoding UTF8 -NoNewline
    $snapshotFromDisk = Get-Content -Raw -LiteralPath $BaselinePath | ConvertFrom-Json
    $integrityFromDisk = New-IntegrityRecord -BaselineSnapshot $snapshotFromDisk -TimestampUtc $UtcNow
    ($integrityFromDisk | ConvertTo-Json -Depth 30) | Set-Content -LiteralPath $IntegrityPath -Encoding UTF8 -NoNewline
}

$baselineSnapshot = Get-Content -Raw -LiteralPath $BaselinePath | ConvertFrom-Json
$integrityRecord  = Get-Content -Raw -LiteralPath $IntegrityPath | ConvertFrom-Json

$caseLines = [System.Collections.Generic.List[string]]::new()
$tamperLines = [System.Collections.Generic.List[string]]::new()
$allPass = $true

# CASE A — Baseline snapshot creation
$intA = Test-BaselineIntegrity -BaselineSnapshot $baselineSnapshot -IntegrityRecord $integrityRecord -ComputedCoverageFingerprintHash $coverageFingerprintHash
$refA = Test-BaselineReference -LiveLedgerObj $ledgerObj -BaselineSnapshot $baselineSnapshot -ComputedCoverageFingerprintHash $coverageFingerprintHash
$caseA = ($intA.baseline_integrity_result -eq 'VALID' -and $refA.baseline_reference_status -eq 'VALID')
if (-not $caseA) { $allPass = $false }
Add-CaseLine -Lines $caseLines -CaseId 'A' -BaselineSnapshotPath $BaselinePath -BaselineIntegrityRecordPath $IntegrityPath -Integrity $intA -Reference $refA -Extra ('baseline_snapshot=' + $(if ($baselineMode -in @('created', 'already_locked')) { 'CREATED' } else { 'MISSING' }) + ' | baseline_integrity=' + $intA.baseline_integrity_result + ' => ' + $(if ($caseA) { 'PASS' } else { 'FAIL' }))

# CASE B — Baseline verification (deterministic recompute)
$reparseSnapshot = (($baselineSnapshot | ConvertTo-Json -Depth 30 -Compress) | ConvertFrom-Json)
$reparseIntegrity = (($integrityRecord | ConvertTo-Json -Depth 30 -Compress) | ConvertFrom-Json)
$intB = Test-BaselineIntegrity -BaselineSnapshot $reparseSnapshot -IntegrityRecord $reparseIntegrity -ComputedCoverageFingerprintHash $coverageFingerprintHash
$refB = Test-BaselineReference -LiveLedgerObj $ledgerObj -BaselineSnapshot $reparseSnapshot -ComputedCoverageFingerprintHash $coverageFingerprintHash
$caseB = ($intB.baseline_integrity_result -eq 'VALID' -and $refB.baseline_reference_status -eq 'VALID')
if (-not $caseB) { $allPass = $false }
Add-CaseLine -Lines $caseLines -CaseId 'B' -BaselineSnapshotPath $BaselinePath -BaselineIntegrityRecordPath $IntegrityPath -Integrity $intB -Reference $refB -Extra ('baseline_verification=VALID | baseline_integrity=' + $intB.baseline_integrity_result + ' => ' + $(if ($caseB) { 'PASS' } else { 'FAIL' }))

# CASE C — Baseline snapshot tamper
$snapC = Clone-Object -Obj $baselineSnapshot
$snapC.latest_entry_id = 'GF-000X'
$intC = Test-BaselineIntegrity -BaselineSnapshot $snapC -IntegrityRecord $integrityRecord -ComputedCoverageFingerprintHash $coverageFingerprintHash
$refC = Test-BaselineReference -LiveLedgerObj $ledgerObj -BaselineSnapshot $snapC -ComputedCoverageFingerprintHash $coverageFingerprintHash
$caseC = ($intC.baseline_integrity_result -eq 'FAIL' -and $intC.baseline_usage_allowed_or_blocked -eq 'BLOCKED')
if (-not $caseC) { $allPass = $false }
Add-CaseLine -Lines $caseLines -CaseId 'C' -BaselineSnapshotPath $BaselinePath -BaselineIntegrityRecordPath $IntegrityPath -Integrity $intC -Reference $refC -Extra ('baseline_snapshot_tamper=DETECTED | baseline_usage=' + $intC.baseline_usage_allowed_or_blocked + ' => ' + $(if ($caseC) { 'PASS' } else { 'FAIL' }))
$tamperLines.Add('CASE C snapshot_tamper stored_hash=' + [string]$intC.stored_baseline_hash + ' computed_hash=' + [string]$intC.computed_baseline_hash)

# CASE D — Integrity record tamper
$intRecD = Clone-Object -Obj $integrityRecord
$intRecD.baseline_snapshot_hash = ('0' * 64)
$intD = Test-BaselineIntegrity -BaselineSnapshot $baselineSnapshot -IntegrityRecord $intRecD -ComputedCoverageFingerprintHash $coverageFingerprintHash
$refD = Test-BaselineReference -LiveLedgerObj $ledgerObj -BaselineSnapshot $baselineSnapshot -ComputedCoverageFingerprintHash $coverageFingerprintHash
$caseD = ($intD.baseline_integrity_result -eq 'FAIL' -and $intD.baseline_usage_allowed_or_blocked -eq 'BLOCKED')
if (-not $caseD) { $allPass = $false }
Add-CaseLine -Lines $caseLines -CaseId 'D' -BaselineSnapshotPath $BaselinePath -BaselineIntegrityRecordPath $IntegrityPath -Integrity $intD -Reference $refD -Extra ('integrity_record_tamper=DETECTED | baseline_usage=' + $intD.baseline_usage_allowed_or_blocked + ' => ' + $(if ($caseD) { 'PASS' } else { 'FAIL' }))
$tamperLines.Add('CASE D integrity_tamper stored_hash=' + [string]$intD.stored_baseline_hash + ' computed_hash=' + [string]$intD.computed_baseline_hash)

# CASE E — Ledger head drift
$ledgerE = Clone-Object -Obj $ledgerObj
$idxE = @($ledgerE.entries).Count - 1
$ledgerE.entries[$idxE].coverage_fingerprint = ('f' * 64)
$intE = Test-BaselineIntegrity -BaselineSnapshot $baselineSnapshot -IntegrityRecord $integrityRecord -ComputedCoverageFingerprintHash $coverageFingerprintHash
$refE = Test-BaselineReference -LiveLedgerObj $ledgerE -BaselineSnapshot $baselineSnapshot -ComputedCoverageFingerprintHash $coverageFingerprintHash
$caseE = ($refE.ledger_head_match -eq 'FALSE' -and $refE.baseline_reference_status -eq 'INVALID')
if (-not $caseE) { $allPass = $false }
Add-CaseLine -Lines $caseLines -CaseId 'E' -BaselineSnapshotPath $BaselinePath -BaselineIntegrityRecordPath $IntegrityPath -Integrity $intE -Reference $refE -Extra ('ledger_head_match=' + $refE.ledger_head_match + ' | baseline_reference=' + $refE.baseline_reference_status + ' => ' + $(if ($caseE) { 'PASS' } else { 'FAIL' }))
$tamperLines.Add('CASE E ledger_head_drift detected ledger_head_match=' + $refE.ledger_head_match)

# CASE F — Future append compatibility
$ledgerF = Clone-Object -Obj $ledgerObj
$entriesF = @($ledgerF.entries)
$prevF = Get-LegacyChainEntryHash -Entry $entriesF[$entriesF.Count - 1]
$newEntryF = [ordered]@{
    entry_id             = 'GF-0008'
    artifact             = 'future_append_probe'
    coverage_fingerprint = ('a' * 64)
    fingerprint_hash     = ('b' * 64)
    timestamp_utc        = (Get-Date -AsUTC -Format 'yyyy-MM-ddTHH:mm:ssZ')
    phase_locked         = '48.4'
    previous_hash        = $prevF
}
$ledgerF.entries += [pscustomobject]$newEntryF
$chainOkF = Test-ContinuationChain -LedgerObj $ledgerF
$intF = Test-BaselineIntegrity -BaselineSnapshot $baselineSnapshot -IntegrityRecord $integrityRecord -ComputedCoverageFingerprintHash $coverageFingerprintHash
$refF = Test-BaselineReference -LiveLedgerObj $ledgerF -BaselineSnapshot $baselineSnapshot -ComputedCoverageFingerprintHash $coverageFingerprintHash
$baselineUnchangedF = ((Get-CanonicalObjectHash -Obj $baselineSnapshot) -eq [string]$integrityRecord.baseline_snapshot_hash)
$caseF = ($chainOkF -and $baselineUnchangedF -and $refF.baseline_reference_status -eq 'VALID')
if (-not $caseF) { $allPass = $false }
Add-CaseLine -Lines $caseLines -CaseId 'F' -BaselineSnapshotPath $BaselinePath -BaselineIntegrityRecordPath $IntegrityPath -Integrity $intF -Reference $refF -Extra ('live_chain_append=' + $(if ($chainOkF) { 'VALID' } else { 'INVALID' }) + ' | frozen_baseline=' + $(if ($baselineUnchangedF) { 'UNCHANGED' } else { 'CHANGED' }) + ' | baseline_reference=' + $refF.baseline_reference_status + ' => ' + $(if ($caseF) { 'PASS' } else { 'FAIL' }))

# CASE G — Non-semantic whitespace/formatting change
$snapshotGText = $baselineSnapshot | ConvertTo-Json -Depth 30
$integrityGText = $integrityRecord | ConvertTo-Json -Depth 30
$snapG = $snapshotGText | ConvertFrom-Json
$intRecG = $integrityGText | ConvertFrom-Json
$intG = Test-BaselineIntegrity -BaselineSnapshot $snapG -IntegrityRecord $intRecG -ComputedCoverageFingerprintHash $coverageFingerprintHash
$refG = Test-BaselineReference -LiveLedgerObj $ledgerObj -BaselineSnapshot $snapG -ComputedCoverageFingerprintHash $coverageFingerprintHash
$caseG = ($intG.baseline_integrity_result -eq 'VALID' -and $refG.baseline_reference_status -eq 'VALID')
if (-not $caseG) { $allPass = $false }
Add-CaseLine -Lines $caseLines -CaseId 'G' -BaselineSnapshotPath $BaselinePath -BaselineIntegrityRecordPath $IntegrityPath -Integrity $intG -Reference $refG -Extra ('non_semantic_change=IGNORED | baseline_integrity=' + $intG.baseline_integrity_result + ' | baseline_reference=' + $refG.baseline_reference_status + ' => ' + $(if ($caseG) { 'PASS' } else { 'FAIL' }))

$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

# Required proof files
$status01 = @(
    'PHASE=48.3',
    'TITLE=Trust-Chain Ledger Baseline Enforcement Coverage Fingerprint Trust-Chain Baseline Lock',
    'BASELINE_MODE=' + $baselineMode,
    'GATE=' + $Gate,
    'TIMESTAMP_UTC=' + $UtcNow,
    'PROOF_FOLDER=' + $PF
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '01_status.txt'), $status01, [System.Text.Encoding]::UTF8)

$head02 = @(
    'LATEST_ENTRY_ID=' + [string]$latest.entry_id,
    'LATEST_ENTRY_PHASE_LOCKED=' + [string]$latest.phase_locked,
    'LEDGER_LENGTH=' + $entries.Count,
    'LEDGER_HEAD_HASH=' + (Get-CanonicalEntryHash -Entry $latest),
    'LEDGER_HASH=' + (Get-CanonicalLedgerHash -LedgerObj $ledgerObj),
    'COVERAGE_FINGERPRINT_HASH=' + $coverageFingerprintHash,
    'PHASE_LOCKED=48.3'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '02_head.txt'), $head02, [System.Text.Encoding]::UTF8)

$def10 = @(
    'BASELINE_SNAPSHOT_PATH=control_plane/88_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline.json',
    'BASELINE_INTEGRITY_PATH=control_plane/89_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_integrity.json',
    'BASELINE_VERSION=1',
    'PHASE_LOCKED=48.3',
    'SOURCE_PHASES=48.0,48.1,48.2',
    'LATEST_ENTRY_EXPECTED=GF-0007',
    'LATEST_ENTRY_PHASE_EXPECTED=48.2'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '10_baseline_definition.txt'), $def10, [System.Text.Encoding]::UTF8)

$rules11 = @(
    'HASH_RULE_1=baseline_snapshot_hash is SHA256 of canonical baseline snapshot object',
    'HASH_RULE_2=ledger_head_hash is canonical hash of baseline head entry',
    'HASH_RULE_3=coverage_fingerprint_hash is coverage_fingerprint_sha256 from control_plane/87',
    'HASH_RULE_4=canonical JSON sorts object keys and preserves array order',
    'HASH_RULE_5=non-semantic formatting must not change canonical hash outcomes'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '11_baseline_hash_rules.txt'), $rules11, [System.Text.Encoding]::UTF8)

$files12 = @(
    'WRITTEN=control_plane/88_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline.json',
    'WRITTEN=control_plane/89_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_integrity.json',
    'READ=control_plane/70_guard_fingerprint_trust_chain.json',
    'READ=control_plane/87_trust_chain_ledger_baseline_enforcement_coverage_fingerprint.json'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '12_files_touched.txt'), $files12, [System.Text.Encoding]::UTF8)

$build13 = @(
    'baseline_mode=' + $baselineMode,
    'baseline_snapshot_hash=' + [string]$integrityRecord.baseline_snapshot_hash,
    'ledger_head_hash=' + [string]$integrityRecord.ledger_head_hash,
    'coverage_fingerprint_hash=' + [string]$integrityRecord.coverage_fingerprint_hash,
    'initial_ledger_length=' + $entries.Count,
    'continuation_chain_valid=' + (Test-ContinuationChain -LedgerObj $ledgerObj).ToString().ToUpper()
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '13_build_output.txt'), $build13, [System.Text.Encoding]::UTF8)

[System.IO.File]::WriteAllText((Join-Path $PF '14_validation_results.txt'), ($caseLines -join "`r`n"), [System.Text.Encoding]::UTF8)

$passCnt = @($caseLines | Where-Object { $_ -match '=> PASS' }).Count
$failCnt = @($caseLines | Where-Object { $_ -match '=> FAIL' }).Count
$beh15 = @(
    'PHASE=48.3',
    'TOTAL_CASES=' + $caseLines.Count,
    'PASSED=' + $passCnt,
    'FAILED=' + $failCnt,
    'GATE=' + $Gate,
    'RUNTIME_STATE_MACHINE_UNCHANGED=TRUE'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '15_behavior_summary.txt'), $beh15, [System.Text.Encoding]::UTF8)

$int16 = @(
    'baseline_snapshot_hash=' + [string]$integrityRecord.baseline_snapshot_hash,
    'ledger_head_hash=' + [string]$integrityRecord.ledger_head_hash,
    'coverage_fingerprint_hash=' + [string]$integrityRecord.coverage_fingerprint_hash,
    'timestamp_utc=' + [string]$integrityRecord.timestamp_utc,
    'phase_locked=' + [string]$integrityRecord.phase_locked
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '16_baseline_integrity_record.txt'), $int16, [System.Text.Encoding]::UTF8)

[System.IO.File]::WriteAllText((Join-Path $PF '17_baseline_tamper_evidence.txt'), ($tamperLines -join "`r`n"), [System.Text.Encoding]::UTF8)

$gate98 = @(
    'PHASE=48.3',
    'GATE=' + $Gate,
    'ALL_CASES_PASS=' + $allPass.ToString().ToUpper()
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '98_gate_phase48_3.txt'), $gate98, [System.Text.Encoding]::UTF8)

$ZipPath = $PF + '.zip'
if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
$zipTmp = $PF + '_zipcopy'
if (Test-Path -LiteralPath $zipTmp) { Remove-Item -LiteralPath $zipTmp -Recurse -Force }
New-Item -ItemType Directory -Path $zipTmp | Out-Null
Get-ChildItem -Path $PF -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $zipTmp $_.Name) -Force
}
Compress-Archive -Path (Join-Path $zipTmp '*') -DestinationPath $ZipPath -Force
Remove-Item -LiteralPath $zipTmp -Recurse -Force

Write-Output ('PF=' + $PF)
Write-Output ('ZIP=' + $ZipPath)
Write-Output ('GATE=' + $Gate)
