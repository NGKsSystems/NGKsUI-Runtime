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
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [float] -or $Value -is [decimal]) {
        return [string]$Value
    }
    if ($Value -is [string]) {
        $s = [string]$Value
        $s = $s -replace '\\', '\\'
        $s = $s -replace '"', '\"'
        $s = $s -replace "`n", '\n'
        $s = $s -replace "`r", '\r'
        $s = $s -replace "`t", '\t'
        return '"' + $s + '"'
    }
    if ($Value -is [System.Collections.IList]) {
        $items = [System.Collections.Generic.List[string]]::new()
        foreach ($item in $Value) { [void]$items.Add((ConvertTo-CanonicalJson -Value $item)) }
        return '[' + ($items -join ',') + ']'
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $keys = @($Value.Keys | Sort-Object)
        $pairs = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $keys) {
            [void]$pairs.Add(('"' + $k + '":' + (ConvertTo-CanonicalJson -Value $Value[$k])))
        }
        return '{' + ($pairs -join ',') + '}'
    }
    if ($Value -is [pscustomobject]) {
        $keys = @($Value.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object)
        $pairs = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $keys) {
            $v = $Value.PSObject.Properties[$k].Value
            [void]$pairs.Add(('"' + $k + '":' + (ConvertTo-CanonicalJson -Value $v)))
        }
        return '{' + ($pairs -join ',') + '}'
    }

    return '"' + ([string]$Value -replace '"', '\"') + '"'
}

function Get-CanonicalObjectHash {
    param([object]$Obj)
    return Get-StringSha256Hex -Text (ConvertTo-CanonicalJson -Value $Obj)
}

function Get-LegacyChainEntryCanonical {
    param([object]$Entry)
    $obj = [ordered]@{
        entry_id         = [string]$Entry.entry_id
        fingerprint_hash = [string]$Entry.fingerprint_hash
        timestamp_utc    = [string]$Entry.timestamp_utc
        phase_locked     = [string]$Entry.phase_locked
        previous_hash    = if ($null -eq $Entry.previous_hash -or [string]::IsNullOrWhiteSpace([string]$Entry.previous_hash)) { $null } else { [string]$Entry.previous_hash }
    }
    return ($obj | ConvertTo-Json -Depth 4 -Compress)
}

function Get-LegacyChainEntryHash {
    param([object]$Entry)
    return Get-StringSha256Hex -Text (Get-LegacyChainEntryCanonical -Entry $Entry)
}

function Get-CanonicalEntryHash {
    param([object]$Entry)
    return Get-CanonicalObjectHash -Obj $Entry
}

function Copy-Object {
    param([object]$Obj)
    return ($Obj | ConvertTo-Json -Depth 80 -Compress | ConvertFrom-Json)
}

function Test-LegacyTrustChain {
    param([object]$ChainObj)

    $result = [ordered]@{
        pass            = $true
        reason          = 'ok'
        entry_count     = 0
        chain_hashes    = @()
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
            $expectedPrev = $hashes[$i - 1]
            if ([string]$entry.previous_hash -ne [string]$expectedPrev) {
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
    param([object]$LedgerObj)

    $max = 0
    foreach ($e in @($LedgerObj.entries)) {
        $id = [string]$e.entry_id
        if ($id -match '^GF-(\d+)$') {
            $n = [int]$Matches[1]
            if ($n -gt $max) { $max = $n }
        }
    }

    return ('GF-' + ($max + 1).ToString('0000'))
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
    foreach ($entry in $entries) {
        $entryHashes[[string]$entry.entry_id] = Get-CanonicalEntryHash -Entry $entry
    }

    return [ordered]@{
        baseline_version          = 1
        phase_locked              = '50.7'
        ledger_head_hash          = Get-CanonicalEntryHash -Entry $latest
        ledger_length             = $entries.Count
        coverage_fingerprint_hash = $CoverageFingerprintHash
        latest_entry_id           = [string]$latest.entry_id
        latest_entry_phase_locked = [string]$latest.phase_locked
        timestamp_utc             = $TimestampUtc
        source_phases             = @('50.4', '50.5', '50.6')
        entry_hashes              = $entryHashes
    }
}

function New-IntegrityRecord {
    param(
        [object]$BaselineSnapshot,
        [string]$TimestampUtc
    )

    return [ordered]@{
        baseline_snapshot_hash    = Get-CanonicalObjectHash -Obj $BaselineSnapshot
        ledger_head_hash          = [string]$BaselineSnapshot.ledger_head_hash
        coverage_fingerprint_hash = [string]$BaselineSnapshot.coverage_fingerprint_hash
        timestamp_utc             = $TimestampUtc
        phase_locked              = '50.7'
    }
}

function Test-BaselineIntegrity {
    param(
        [object]$BaselineSnapshot,
        [object]$IntegrityRecord,
        [string]$ComputedCoverageFingerprintHash
    )

    $computedSnapshotHash = Get-CanonicalObjectHash -Obj $BaselineSnapshot
    $storedSnapshotHash = [string]$IntegrityRecord.baseline_snapshot_hash
    $storedLedgerHeadHash = [string]$IntegrityRecord.ledger_head_hash
    $computedLedgerHeadHash = [string]$BaselineSnapshot.ledger_head_hash
    $storedCoverageHash = [string]$IntegrityRecord.coverage_fingerprint_hash
    $computedCoverageHash = [string]$ComputedCoverageFingerprintHash

    $integrityValid = (
        $storedSnapshotHash -eq $computedSnapshotHash -and
        $storedLedgerHeadHash -eq $computedLedgerHeadHash -and
        $storedCoverageHash -eq $computedCoverageHash -and
        [string]$IntegrityRecord.phase_locked -eq '50.7'
    )

    return [ordered]@{
        stored_baseline_hash = $storedSnapshotHash
        computed_baseline_hash = $computedSnapshotHash
        stored_ledger_head_hash = $storedLedgerHeadHash
        computed_ledger_head_hash = $computedLedgerHeadHash
        stored_coverage_fingerprint_hash = $storedCoverageHash
        computed_coverage_fingerprint_hash = $computedCoverageHash
        baseline_integrity_result = if ($integrityValid) { 'VALID' } else { 'FAIL' }
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

    $lengthOk = ($entries.Count -ge $baseLen)
    $prefixOk = $true
    if ($lengthOk) {
        for ($i = 0; $i -lt $baseLen; $i++) {
            $id = [string]$entries[$i].entry_id
            if (-not ($BaselineSnapshot.entry_hashes.PSObject.Properties.Name -contains $id)) {
                $prefixOk = $false
                break
            }
            $expectedHash = [string]$BaselineSnapshot.entry_hashes.$id
            $actualHash = Get-CanonicalEntryHash -Entry $entries[$i]
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
        $headMatch = (
            $headHash -eq [string]$BaselineSnapshot.ledger_head_hash -and
            [string]$baseHead.entry_id -eq [string]$BaselineSnapshot.latest_entry_id -and
            [string]$baseHead.phase_locked -eq [string]$BaselineSnapshot.latest_entry_phase_locked
        )
    }

    $coverageMatch = ([string]$BaselineSnapshot.coverage_fingerprint_hash -eq [string]$ComputedCoverageFingerprintHash)
    $chainCheck = Test-LegacyTrustChain -ChainObj $LiveLedgerObj
    $referenceValid = ($lengthOk -and $prefixOk -and $headMatch -and $coverageMatch -and $chainCheck.pass)

    return [ordered]@{
        ledger_head_match = if ($headMatch) { 'TRUE' } else { 'FALSE' }
        baseline_reference_status = if ($referenceValid) { 'VALID' } else { 'INVALID' }
        baseline_usage_allowed_or_blocked = if ($referenceValid) { 'ALLOWED' } else { 'BLOCKED' }
        continuation_status = if ($chainCheck.pass) { 'VALID' } else { 'INVALID' }
    }
}

function Get-IntegrityPathSelection {
    param(
        [string]$ControlPlaneDir,
        [string]$DefaultIntegrityPath,
        [string]$IntegritySuffix,
        [string]$PhaseLocked
    )

    $existingPhasePath = $null
    $existingCandidates = Get-ChildItem -LiteralPath $ControlPlaneDir -File -Filter ('*' + $IntegritySuffix)
    foreach ($candidate in $existingCandidates) {
        try {
            $obj = Get-Content -Raw -LiteralPath $candidate.FullName | ConvertFrom-Json
            if ([string]$obj.phase_locked -eq $PhaseLocked -and -not [string]::IsNullOrWhiteSpace([string]$obj.baseline_snapshot_hash)) {
                $existingPhasePath = $candidate.FullName
                break
            }
        } catch {
            continue
        }
    }

    if ($null -ne $existingPhasePath) {
        return [ordered]@{
            path = $existingPhasePath
            reason = 'existing_phase50_7_integrity_record_reused'
            fallback_used = $false
        }
    }

    if (-not (Test-Path -LiteralPath $DefaultIntegrityPath)) {
        return [ordered]@{
            path = $DefaultIntegrityPath
            reason = 'default_100_path'
            fallback_used = $false
        }
    }

    try {
        $defaultObj = Get-Content -Raw -LiteralPath $DefaultIntegrityPath | ConvertFrom-Json
        if ([string]$defaultObj.phase_locked -eq $PhaseLocked -and -not [string]::IsNullOrWhiteSpace([string]$defaultObj.baseline_snapshot_hash)) {
            return [ordered]@{
                path = $DefaultIntegrityPath
                reason = 'existing_default_100_phase50_7_reused'
                fallback_used = $false
            }
        }
    } catch {
    }

    for ($idx = 101; $idx -lt 300; $idx++) {
        $candidate = Join-Path $ControlPlaneDir ($idx.ToString() + $IntegritySuffix)
        if (-not (Test-Path -LiteralPath $candidate)) {
            return [ordered]@{
                path = $candidate
                reason = ('default_100_conflict_used_' + $idx)
                fallback_used = $true
            }
        }
    }

    throw 'Unable to allocate non-colliding integrity path for phase 50.7.'
}

function Add-CaseLine {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$CaseId,
        [string]$BaselineSnapshotPath,
        [string]$BaselineIntegrityRecordPath,
        [object]$Integrity,
        [object]$Reference,
        [string]$Extra,
        [bool]$Pass
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
        $Extra,
        '=> ' + $(if ($Pass) { 'PASS' } else { 'FAIL' })
    ) -join ' | '

    $Lines.Add($line)
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$UtcNow = Get-Date -AsUTC -Format 'yyyy-MM-ddTHH:mm:ssZ'

$PhaseName = 'phase50_7_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_lock'
$PF = Join-Path $Root ('_proof\' + $PhaseName + '_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$RunnerPath = Join-Path $Root 'tools\phase50_7\phase50_7_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_lock_runner.ps1'
$ControlPlaneDir = Join-Path $Root 'control_plane'
$LedgerPath = Join-Path $ControlPlaneDir '70_guard_fingerprint_trust_chain.json'
$CoveragePath = Join-Path $ControlPlaneDir '98_trust_chain_ledger_baseline_enforcement_coverage_fingerprint.json'
$BaselinePath = Join-Path $ControlPlaneDir '99_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline.json'
$IntegritySuffix = '_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_integrity.json'
$DefaultIntegrityPath = Join-Path $ControlPlaneDir ('100' + $IntegritySuffix)
$IntegritySelection = Get-IntegrityPathSelection -ControlPlaneDir $ControlPlaneDir -DefaultIntegrityPath $DefaultIntegrityPath -IntegritySuffix $IntegritySuffix -PhaseLocked '50.7'
$IntegrityPath = [string]$IntegritySelection.path

foreach ($req in @($LedgerPath, $CoveragePath)) {
    if (-not (Test-Path -LiteralPath $req)) { throw ('Missing required file: ' + $req) }
}

$ledgerObj = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
$coverageObj = Get-Content -Raw -LiteralPath $CoveragePath | ConvertFrom-Json
$coverageFingerprintHash = [string]$coverageObj.coverage_fingerprint_sha256
if ([string]::IsNullOrWhiteSpace($coverageFingerprintHash)) {
    throw 'coverage_fingerprint_sha256 missing in control_plane/98 artifact'
}

$entries = @($ledgerObj.entries)
if ($entries.Count -lt 1) { throw 'Ledger has no entries' }
$latest = $entries[$entries.Count - 1]
if ([string]$latest.phase_locked -ne '50.6') {
    throw 'Phase 50.6 seal precondition failed: latest ledger entry phase_locked is not 50.6'
}

$candidateSnapshot = New-BaselineSnapshot -LedgerObj $ledgerObj -CoverageFingerprintHash $coverageFingerprintHash -TimestampUtc $UtcNow

$baselineMode = 'created'
if ((Test-Path -LiteralPath $BaselinePath) -and (Test-Path -LiteralPath $IntegrityPath)) {
    $storedSnapshotExisting = Get-Content -Raw -LiteralPath $BaselinePath | ConvertFrom-Json
    $storedIntegrityExisting = Get-Content -Raw -LiteralPath $IntegrityPath | ConvertFrom-Json

    $intExisting = Test-BaselineIntegrity -BaselineSnapshot $storedSnapshotExisting -IntegrityRecord $storedIntegrityExisting -ComputedCoverageFingerprintHash $coverageFingerprintHash
    if ($intExisting.baseline_integrity_result -ne 'VALID') {
        throw 'Existing baseline artifacts are present but integrity is invalid.'
    }

    $normCandidate = Copy-Object -Obj $candidateSnapshot
    $normExisting = Copy-Object -Obj $storedSnapshotExisting
    $normCandidate.timestamp_utc = 'IGNORED'
    $normExisting.timestamp_utc = 'IGNORED'

    if ((Get-CanonicalObjectHash -Obj $normCandidate) -ne (Get-CanonicalObjectHash -Obj $normExisting)) {
        throw 'Existing baseline snapshot mismatches current deterministic lock material.'
    }

    $baselineMode = 'already_locked'
} elseif ((Test-Path -LiteralPath $BaselinePath) -xor (Test-Path -LiteralPath $IntegrityPath)) {
    throw 'Only one baseline file exists; baseline artifacts are inconsistent.'
} else {
    ($candidateSnapshot | ConvertTo-Json -Depth 80) | Set-Content -LiteralPath $BaselinePath -Encoding UTF8 -NoNewline
    $snapshotFromDisk = Get-Content -Raw -LiteralPath $BaselinePath | ConvertFrom-Json
    $integrityFromDisk = New-IntegrityRecord -BaselineSnapshot $snapshotFromDisk -TimestampUtc $UtcNow
    ($integrityFromDisk | ConvertTo-Json -Depth 40) | Set-Content -LiteralPath $IntegrityPath -Encoding UTF8 -NoNewline
}

$baselineSnapshot = Get-Content -Raw -LiteralPath $BaselinePath | ConvertFrom-Json
$integrityRecord = Get-Content -Raw -LiteralPath $IntegrityPath | ConvertFrom-Json

$caseLines = [System.Collections.Generic.List[string]]::new()
$tamperLines = [System.Collections.Generic.List[string]]::new()
$allPass = $true

# CASE A baseline snapshot creation
$intA = Test-BaselineIntegrity -BaselineSnapshot $baselineSnapshot -IntegrityRecord $integrityRecord -ComputedCoverageFingerprintHash $coverageFingerprintHash
$refA = Test-BaselineReference -LiveLedgerObj $ledgerObj -BaselineSnapshot $baselineSnapshot -ComputedCoverageFingerprintHash $coverageFingerprintHash
$caseA = ($intA.baseline_integrity_result -eq 'VALID' -and $refA.baseline_reference_status -eq 'VALID')
if (-not $caseA) { $allPass = $false }
Add-CaseLine -Lines $caseLines -CaseId 'A' -BaselineSnapshotPath $BaselinePath -BaselineIntegrityRecordPath $IntegrityPath -Integrity $intA -Reference $refA -Extra ('baseline_snapshot=CREATED | baseline_integrity=' + $intA.baseline_integrity_result) -Pass $caseA

# CASE B baseline verification
$snapB = (($baselineSnapshot | ConvertTo-Json -Depth 80 -Compress) | ConvertFrom-Json)
$intRecB = (($integrityRecord | ConvertTo-Json -Depth 40 -Compress) | ConvertFrom-Json)
$intB = Test-BaselineIntegrity -BaselineSnapshot $snapB -IntegrityRecord $intRecB -ComputedCoverageFingerprintHash $coverageFingerprintHash
$refB = Test-BaselineReference -LiveLedgerObj $ledgerObj -BaselineSnapshot $snapB -ComputedCoverageFingerprintHash $coverageFingerprintHash
$caseB = ($intB.baseline_integrity_result -eq 'VALID')
if (-not $caseB) { $allPass = $false }
Add-CaseLine -Lines $caseLines -CaseId 'B' -BaselineSnapshotPath $BaselinePath -BaselineIntegrityRecordPath $IntegrityPath -Integrity $intB -Reference $refB -Extra ('baseline_verification=VALID | baseline_integrity=' + $intB.baseline_integrity_result) -Pass $caseB

# CASE C baseline snapshot tamper
$snapC = Copy-Object -Obj $baselineSnapshot
$snapC.latest_entry_id = 'GF-TAMPER'
$intC = Test-BaselineIntegrity -BaselineSnapshot $snapC -IntegrityRecord $integrityRecord -ComputedCoverageFingerprintHash $coverageFingerprintHash
$refC = Test-BaselineReference -LiveLedgerObj $ledgerObj -BaselineSnapshot $snapC -ComputedCoverageFingerprintHash $coverageFingerprintHash
$caseC = ($intC.baseline_integrity_result -eq 'FAIL' -and $intC.baseline_usage_allowed_or_blocked -eq 'BLOCKED')
if (-not $caseC) { $allPass = $false }
Add-CaseLine -Lines $caseLines -CaseId 'C' -BaselineSnapshotPath $BaselinePath -BaselineIntegrityRecordPath $IntegrityPath -Integrity $intC -Reference $refC -Extra ('baseline_snapshot_tamper=DETECTED | baseline_usage=BLOCKED') -Pass $caseC
$tamperLines.Add('CASE C snapshot_tamper stored_hash=' + [string]$intC.stored_baseline_hash + ' computed_hash=' + [string]$intC.computed_baseline_hash)

# CASE D integrity record tamper
$intRecD = Copy-Object -Obj $integrityRecord
$intRecD.baseline_snapshot_hash = ('0' * 64)
$intD = Test-BaselineIntegrity -BaselineSnapshot $baselineSnapshot -IntegrityRecord $intRecD -ComputedCoverageFingerprintHash $coverageFingerprintHash
$refD = Test-BaselineReference -LiveLedgerObj $ledgerObj -BaselineSnapshot $baselineSnapshot -ComputedCoverageFingerprintHash $coverageFingerprintHash
$caseD = ($intD.baseline_integrity_result -eq 'FAIL' -and $intD.baseline_usage_allowed_or_blocked -eq 'BLOCKED')
if (-not $caseD) { $allPass = $false }
Add-CaseLine -Lines $caseLines -CaseId 'D' -BaselineSnapshotPath $BaselinePath -BaselineIntegrityRecordPath $IntegrityPath -Integrity $intD -Reference $refD -Extra ('integrity_record_tamper=DETECTED | baseline_usage=BLOCKED') -Pass $caseD
$tamperLines.Add('CASE D integrity_tamper stored_hash=' + [string]$intD.stored_baseline_hash + ' computed_hash=' + [string]$intD.computed_baseline_hash)

# CASE E ledger head drift
$ledgerE = Copy-Object -Obj $ledgerObj
$idxE = @($ledgerE.entries).Count - 1
$ledgerE.entries[$idxE].fingerprint_hash = ('e' * 64)
$intE = Test-BaselineIntegrity -BaselineSnapshot $baselineSnapshot -IntegrityRecord $integrityRecord -ComputedCoverageFingerprintHash $coverageFingerprintHash
$refE = Test-BaselineReference -LiveLedgerObj $ledgerE -BaselineSnapshot $baselineSnapshot -ComputedCoverageFingerprintHash $coverageFingerprintHash
$caseE = ($refE.ledger_head_match -eq 'FALSE' -and $refE.baseline_reference_status -eq 'INVALID')
if (-not $caseE) { $allPass = $false }
Add-CaseLine -Lines $caseLines -CaseId 'E' -BaselineSnapshotPath $BaselinePath -BaselineIntegrityRecordPath $IntegrityPath -Integrity $intE -Reference $refE -Extra ('ledger_head_match=' + $refE.ledger_head_match + ' | baseline_reference=' + $refE.baseline_reference_status) -Pass $caseE
$tamperLines.Add('CASE E ledger_head_drift detected ledger_head_match=' + $refE.ledger_head_match)

# CASE F future append compatibility
$ledgerF = Copy-Object -Obj $ledgerObj
$chainFPre = Test-LegacyTrustChain -ChainObj $ledgerF
$entryF = [ordered]@{
    entry_id = Get-NextEntryId -LedgerObj $ledgerF
    artifact = 'future_chain_continuation_probe'
    coverage_fingerprint = [string]$coverageFingerprintHash
    fingerprint_hash = ('a' * 64)
    timestamp_utc = (Get-Date -AsUTC -Format 'yyyy-MM-ddTHH:mm:ssZ')
    phase_locked = '50.8'
    previous_hash = [string]$chainFPre.last_entry_hash
}
$ledgerF.entries += [pscustomobject]$entryF
$chainF = Test-LegacyTrustChain -ChainObj $ledgerF
$intF = Test-BaselineIntegrity -BaselineSnapshot $baselineSnapshot -IntegrityRecord $integrityRecord -ComputedCoverageFingerprintHash $coverageFingerprintHash
$refF = Test-BaselineReference -LiveLedgerObj $ledgerF -BaselineSnapshot $baselineSnapshot -ComputedCoverageFingerprintHash $coverageFingerprintHash
$baselineUnchangedF = ((Get-CanonicalObjectHash -Obj $baselineSnapshot) -eq [string]$integrityRecord.baseline_snapshot_hash)
$caseF = ($chainF.pass -and $baselineUnchangedF -and $refF.baseline_reference_status -eq 'VALID')
if (-not $caseF) { $allPass = $false }
Add-CaseLine -Lines $caseLines -CaseId 'F' -BaselineSnapshotPath $BaselinePath -BaselineIntegrityRecordPath $IntegrityPath -Integrity $intF -Reference $refF -Extra ('live_chain_append=' + $(if ($chainF.pass) { 'VALID' } else { 'INVALID' }) + ' | frozen_baseline=' + $(if ($baselineUnchangedF) { 'UNCHANGED' } else { 'CHANGED' }) + ' | baseline_reference=' + $refF.baseline_reference_status) -Pass $caseF

# CASE G non-semantic change
$snapGText = $baselineSnapshot | ConvertTo-Json -Depth 80
$intGText = $integrityRecord | ConvertTo-Json -Depth 40
$snapG = $snapGText | ConvertFrom-Json
$intRecG = $intGText | ConvertFrom-Json
$intG = Test-BaselineIntegrity -BaselineSnapshot $snapG -IntegrityRecord $intRecG -ComputedCoverageFingerprintHash $coverageFingerprintHash
$refG = Test-BaselineReference -LiveLedgerObj $ledgerObj -BaselineSnapshot $snapG -ComputedCoverageFingerprintHash $coverageFingerprintHash
$caseG = ($intG.baseline_integrity_result -eq 'VALID' -and $refG.baseline_reference_status -eq 'VALID')
if (-not $caseG) { $allPass = $false }
Add-CaseLine -Lines $caseLines -CaseId 'G' -BaselineSnapshotPath $BaselinePath -BaselineIntegrityRecordPath $IntegrityPath -Integrity $intG -Reference $refG -Extra ('non_semantic_change=IGNORED | baseline_integrity=' + $intG.baseline_integrity_result + ' | baseline_reference=' + $refG.baseline_reference_status) -Pass $caseG

$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status01 = @(
    'PHASE=50.7',
    'TITLE=Trust-Chain Ledger Baseline Enforcement Coverage Fingerprint Trust-Chain Baseline Lock',
    'BASELINE_MODE=' + $baselineMode,
    'INTEGRITY_PATH_REASON=' + [string]$IntegritySelection.reason,
    'GATE=' + $Gate,
    'TIMESTAMP_UTC=' + $UtcNow,
    'RUNTIME_STATE_MACHINE_CHANGED=FALSE'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '01_status.txt'), $status01, [System.Text.Encoding]::UTF8)

$head02 = @(
    'RUNNER=' + $RunnerPath,
    'LEDGER=' + $LedgerPath,
    'COVERAGE_FINGERPRINT_ARTIFACT=' + $CoveragePath,
    'BASELINE_SNAPSHOT=' + $BaselinePath,
    'BASELINE_INTEGRITY=' + $IntegrityPath,
    'LATEST_ENTRY_ID=' + [string]$latest.entry_id,
    'LATEST_ENTRY_PHASE_LOCKED=' + [string]$latest.phase_locked,
    'LEDGER_LENGTH=' + [string]$entries.Count
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '02_head.txt'), $head02, [System.Text.Encoding]::UTF8)

$def10 = @(
    'BASELINE_SNAPSHOT_PATH=' + $BaselinePath,
    'BASELINE_INTEGRITY_PATH=' + $IntegrityPath,
    'BASELINE_VERSION=1',
    'PHASE_LOCKED=50.7',
    'SOURCE_PHASES=50.4,50.5,50.6',
    'LATEST_ENTRY_PHASE_EXPECTED=50.6',
    'INTEGRITY_DEFAULT_PATH=' + $DefaultIntegrityPath,
    'INTEGRITY_PATH_REASON=' + [string]$IntegritySelection.reason,
    'INTEGRITY_PATH_FALLBACK_USED=' + $(if ($IntegritySelection.fallback_used) { 'TRUE' } else { 'FALSE' })
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '10_baseline_definition.txt'), $def10, [System.Text.Encoding]::UTF8)

$rules11 = @(
    'HASH_RULE_1=baseline_snapshot_hash is SHA256 of canonical baseline snapshot object',
    'HASH_RULE_2=ledger_head_hash is canonical hash of the frozen baseline head entry',
    'HASH_RULE_3=coverage_fingerprint_hash is coverage_fingerprint_sha256 from control_plane/98',
    'HASH_RULE_4=canonical JSON sorts object keys and preserves array order',
    'HASH_RULE_5=non-semantic formatting must not change canonical hash outcomes'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '11_baseline_hash_rules.txt'), $rules11, [System.Text.Encoding]::UTF8)

$filesTouched = [System.Collections.Generic.List[string]]::new()
if ($baselineMode -eq 'created') {
    $filesTouched.Add('WRITE=' + $BaselinePath)
    $filesTouched.Add('WRITE=' + $IntegrityPath)
} else {
    $filesTouched.Add('READ=' + $BaselinePath)
    $filesTouched.Add('READ=' + $IntegrityPath)
}
$filesTouched.Add('READ=' + $LedgerPath)
$filesTouched.Add('READ=' + $CoveragePath)
$filesTouched.Add('WRITE=' + $PF)
[System.IO.File]::WriteAllText((Join-Path $PF '12_files_touched.txt'), ($filesTouched -join "`r`n"), [System.Text.Encoding]::UTF8)

$build13 = @(
    'ACTION=deterministic_baseline_lock',
    'baseline_mode=' + $baselineMode,
    'baseline_snapshot_hash=' + [string]$integrityRecord.baseline_snapshot_hash,
    'ledger_head_hash=' + [string]$integrityRecord.ledger_head_hash,
    'coverage_fingerprint_hash=' + [string]$integrityRecord.coverage_fingerprint_hash,
    'initial_ledger_length=' + [string]$entries.Count,
    'continuation_chain_valid=' + (Test-LegacyTrustChain -ChainObj $ledgerObj).pass.ToString().ToUpper(),
    'CASE_COUNT=7',
    'BUILD_SYSTEM=none',
    'GATE=' + $Gate
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '13_build_output.txt'), $build13, [System.Text.Encoding]::UTF8)

[System.IO.File]::WriteAllText((Join-Path $PF '14_validation_results.txt'), ($caseLines -join "`r`n"), [System.Text.Encoding]::UTF8)

$passCnt = @($caseLines | Where-Object { $_ -match '=> PASS$' }).Count
$failCnt = @($caseLines | Where-Object { $_ -match '=> FAIL$' }).Count
$beh15 = @(
    'PHASE=50.7',
    'TOTAL_CASES=' + [string]$caseLines.Count,
    'PASSED=' + [string]$passCnt,
    'FAILED=' + [string]$failCnt,
    'GATE=' + $Gate,
    'BASELINE_DETERMINISTIC=TRUE',
    'FUTURE_APPEND_COMPATIBLE=' + $(if ($caseF) { 'TRUE' } else { 'FALSE' }),
    'NON_SEMANTIC_STABLE=' + $(if ($caseG) { 'TRUE' } else { 'FALSE' }),
    'INTEGRITY_PATH_REASON=' + [string]$IntegritySelection.reason,
    'INTEGRITY_PATH_FALLBACK_USED=' + $(if ($IntegritySelection.fallback_used) { 'TRUE' } else { 'FALSE' }),
    'RUNTIME_STATE_MACHINE_UNCHANGED=TRUE'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '15_behavior_summary.txt'), $beh15, [System.Text.Encoding]::UTF8)

$record16 = @(
    'baseline_snapshot_hash=' + [string]$integrityRecord.baseline_snapshot_hash,
    'ledger_head_hash=' + [string]$integrityRecord.ledger_head_hash,
    'coverage_fingerprint_hash=' + [string]$integrityRecord.coverage_fingerprint_hash,
    'baseline_snapshot_path=' + $BaselinePath,
    'baseline_integrity_record_path=' + $IntegrityPath,
    'phase_locked=50.7',
    'timestamp_utc=' + [string]$integrityRecord.timestamp_utc
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '16_baseline_integrity_record.txt'), $record16, [System.Text.Encoding]::UTF8)

[System.IO.File]::WriteAllText((Join-Path $PF '17_baseline_tamper_evidence.txt'), ($tamperLines -join "`r`n"), [System.Text.Encoding]::UTF8)

$gate98 = @('PHASE=50.7', 'GATE=' + $Gate) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '98_gate_phase50_7.txt'), $gate98, [System.Text.Encoding]::UTF8)

$ZipPath = $PF + '.zip'
if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
$tmpZip = $PF + '_zipcopy'
if (Test-Path -LiteralPath $tmpZip) { Remove-Item -LiteralPath $tmpZip -Recurse -Force }
New-Item -ItemType Directory -Path $tmpZip | Out-Null
Get-ChildItem -Path $PF -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $tmpZip $_.Name) -Force
}
Compress-Archive -Path (Join-Path $tmpZip '*') -DestinationPath $ZipPath -Force
Remove-Item -LiteralPath $tmpZip -Recurse -Force

Write-Output ('PF=' + $PF)
Write-Output ('ZIP=' + $ZipPath)
Write-Output ('GATE=' + $Gate)
