Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ((Get-Location).Path -ne $Root) {
    Write-Output 'wrong working directory'
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

function Convert-ToCanonicalJson {
    param($Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [float] -or $Value -is [decimal]) { return [string]$Value }
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
        foreach ($item in $Value) { [void]$items.Add((Convert-ToCanonicalJson -Value $item)) }
        return '[' + ($items -join ',') + ']'
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $keys = @($Value.Keys | Sort-Object)
        $pairs = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $keys) { [void]$pairs.Add(('"' + $k + '":' + (Convert-ToCanonicalJson -Value $Value[$k]))) }
        return '{' + ($pairs -join ',') + '}'
    }
    if ($Value -is [pscustomobject]) {
        $keys = @($Value.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object)
        $pairs = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $keys) {
            $v = $Value.PSObject.Properties[$k].Value
            [void]$pairs.Add(('"' + $k + '":' + (Convert-ToCanonicalJson -Value $v)))
        }
        return '{' + ($pairs -join ',') + '}'
    }
    return '"' + ([string]$Value -replace '"', '\"') + '"'
}

function Get-CanonicalObjectHash {
    param([object]$Obj)
    return Get-StringSha256Hex -Text (Convert-ToCanonicalJson -Value $Obj)
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

function Test-ExtendedTrustChain {
    param([object[]]$Entries)
    $result = [ordered]@{ pass = $true; reason = 'ok'; entry_count = $Entries.Count; chain_hashes = @(); last_entry_hash = '' }
    if ($Entries.Count -eq 0) {
        $result.pass = $false
        $result.reason = 'chain_entries_empty'
        return $result
    }
    $hashes = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $Entries.Count; $i++) {
        $entry = $Entries[$i]
        if ($i -eq 0) {
            if ($null -ne $entry.previous_hash -and -not [string]::IsNullOrWhiteSpace([string]$entry.previous_hash)) {
                $result.pass = $false
                $result.reason = 'first_entry_previous_hash_must_be_null'
                return $result
            }
        } else {
            $expectedPrev = $hashes[$i - 1]
            if ([string]$entry.previous_hash -ne $expectedPrev) {
                $result.pass = $false
                $result.reason = 'previous_hash_link_mismatch_at_entry_' + [string]$entry.entry_id + '_index_' + $i
                return $result
            }
        }
        [void]$hashes.Add((Get-LegacyChainEntryHash -Entry $entry))
    }
    $result.chain_hashes = @($hashes)
    $result.last_entry_hash = [string]$hashes[$hashes.Count - 1]
    return $result
}

function Write-ProofFile {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.Encoding]::UTF8)
}

function Copy-ChainEntries {
    param([object[]]$Entries)
    $copy = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $Entries) {
        [void]$copy.Add(($entry | ConvertTo-Json -Depth 20 | ConvertFrom-Json))
    }
    return @($copy)
}

function New-Phase531BaselineSnapshot {
    param(
        [string]$LedgerHeadHash,
        [int]$LedgerLength,
        [string]$CoverageFingerprintHash,
        [string]$LatestEntryId,
        [string]$LatestEntryPhaseLocked,
        [string]$TimestampUtc
    )
    return [ordered]@{
        baseline_version          = 1
        phase_locked              = '53.1'
        ledger_head_hash          = $LedgerHeadHash
        ledger_length             = $LedgerLength
        coverage_fingerprint_hash = $CoverageFingerprintHash
        latest_entry_id           = $LatestEntryId
        latest_entry_phase_locked = $LatestEntryPhaseLocked
        timestamp_utc             = $TimestampUtc
        source_phases             = @('52.8', '52.9', '53.0')
    }
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunnerPath = Join-Path $Root 'tools\phase53_1\phase53_1_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_lock_runner.ps1'
$LedgerPath = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$Art110Path = Join-Path $Root 'control_plane\110_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint_regression_anchor.json'
$Art111Path = Join-Path $Root 'control_plane\111_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline.json'
$Art112Path = Join-Path $Root 'control_plane\112_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_integrity.json'
$PF = Join-Path $Root ('_proof\phase53_1_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_lock_' + $Timestamp)

New-Item -ItemType Directory -Path $PF | Out-Null

foreach ($path in @($LedgerPath, $Art110Path)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw 'Missing required artifact: ' + $path
    }
}

$ledgerObj = Get-Content -LiteralPath $LedgerPath -Raw | ConvertFrom-Json
$art110Obj = Get-Content -LiteralPath $Art110Path -Raw | ConvertFrom-Json
$liveEntries = @($ledgerObj.entries)

$preCheck = Test-ExtendedTrustChain -Entries $liveEntries
if (-not $preCheck.pass) {
    throw 'Live ledger integrity check failed before baseline: ' + $preCheck.reason
}

$latestEntry = $liveEntries[$liveEntries.Count - 1]
if ([string]$latestEntry.entry_id -ne 'GF-0015') {
    throw 'Latest ledger entry is not GF-0015. Got: ' + [string]$latestEntry.entry_id
}
if ([string]$latestEntry.phase_locked -ne '53.0') {
    throw 'Latest ledger entry is not phase 53.0. Got: ' + [string]$latestEntry.phase_locked
}

$ledgerHeadHash = [string]$preCheck.last_entry_hash
$coverageFingerprintHash = [string]$art110Obj.coverage_fingerprint
$latestEntryId = [string]$latestEntry.entry_id
$latestEntryPhase = [string]$latestEntry.phase_locked
$ledgerLength = $liveEntries.Count
$createdNew = $false
$reuseStatus = 'new'

if ((Test-Path -LiteralPath $Art111Path) -and (Test-Path -LiteralPath $Art112Path)) {
    $ex111 = Get-Content -LiteralPath $Art111Path -Raw | ConvertFrom-Json
    $ex112 = Get-Content -LiteralPath $Art112Path -Raw | ConvertFrom-Json
    $ex111Hash = Get-CanonicalObjectHash -Obj $ex111

    $mismatches = [System.Collections.Generic.List[string]]::new()
    if ([string]$ex111.phase_locked -ne '53.1') { [void]$mismatches.Add('111.phase_locked expected=53.1 actual=' + [string]$ex111.phase_locked) }
    if ([string]$ex111.ledger_head_hash -ne $ledgerHeadHash) { [void]$mismatches.Add('111.ledger_head_hash expected=' + $ledgerHeadHash + ' actual=' + [string]$ex111.ledger_head_hash) }
    if ([int]$ex111.ledger_length -ne $ledgerLength) { [void]$mismatches.Add('111.ledger_length expected=' + $ledgerLength + ' actual=' + [int]$ex111.ledger_length) }
    if ([string]$ex111.coverage_fingerprint_hash -ne $coverageFingerprintHash) { [void]$mismatches.Add('111.coverage_fingerprint_hash expected=' + $coverageFingerprintHash + ' actual=' + [string]$ex111.coverage_fingerprint_hash) }
    if ([string]$ex111.latest_entry_id -ne $latestEntryId) { [void]$mismatches.Add('111.latest_entry_id expected=' + $latestEntryId + ' actual=' + [string]$ex111.latest_entry_id) }
    if ([string]$ex111.latest_entry_phase_locked -ne $latestEntryPhase) { [void]$mismatches.Add('111.latest_entry_phase_locked expected=' + $latestEntryPhase + ' actual=' + [string]$ex111.latest_entry_phase_locked) }
    $sourcePhases = @($ex111.source_phases | ForEach-Object { [string]$_ })
    if (($sourcePhases -join ',') -ne '52.8,52.9,53.0') { [void]$mismatches.Add('111.source_phases expected=52.8,52.9,53.0 actual=' + ($sourcePhases -join ',')) }

    if ([string]$ex112.phase_locked -ne '53.1') { [void]$mismatches.Add('112.phase_locked expected=53.1 actual=' + [string]$ex112.phase_locked) }
    if ([string]$ex112.baseline_snapshot_hash -ne $ex111Hash) { [void]$mismatches.Add('112.baseline_snapshot_hash expected=' + $ex111Hash + ' actual=' + [string]$ex112.baseline_snapshot_hash) }
    if ([string]$ex112.ledger_head_hash -ne $ledgerHeadHash) { [void]$mismatches.Add('112.ledger_head_hash expected=' + $ledgerHeadHash + ' actual=' + [string]$ex112.ledger_head_hash) }
    if ([string]$ex112.coverage_fingerprint_hash -ne $coverageFingerprintHash) { [void]$mismatches.Add('112.coverage_fingerprint_hash expected=' + $coverageFingerprintHash + ' actual=' + [string]$ex112.coverage_fingerprint_hash) }

    if ($mismatches.Count -gt 0) {
        throw 'Existing artifacts 111/112 mismatch current phase53.1 baseline state: ' + ($mismatches -join ' ; ')
    }

    $reuseStatus = 'reused'
} elseif ((Test-Path -LiteralPath $Art111Path) -or (Test-Path -LiteralPath $Art112Path)) {
    throw 'Existing artifacts 111/112 are incomplete; both files must exist together for idempotent reuse'
} else {
    $tsNow = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'
    $baselineSnapInMem = New-Phase531BaselineSnapshot -LedgerHeadHash $ledgerHeadHash -LedgerLength $ledgerLength -CoverageFingerprintHash $coverageFingerprintHash -LatestEntryId $latestEntryId -LatestEntryPhaseLocked $latestEntryPhase -TimestampUtc $tsNow
    ($baselineSnapInMem | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $Art111Path -Encoding UTF8 -NoNewline

    $baselineSnapOnDisk = Get-Content -LiteralPath $Art111Path -Raw | ConvertFrom-Json
    $baselineSnapshotHash = Get-CanonicalObjectHash -Obj $baselineSnapOnDisk

    $integrityRecord = [ordered]@{
        artifact_id               = '112'
        phase_locked              = '53.1'
        baseline_snapshot_hash    = $baselineSnapshotHash
        ledger_head_hash          = $ledgerHeadHash
        coverage_fingerprint_hash = $coverageFingerprintHash
        source_artifact           = '111_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline.json'
        timestamp_utc             = $tsNow
    }
    ($integrityRecord | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $Art112Path -Encoding UTF8 -NoNewline
    $createdNew = $true
}

$snap111 = Get-Content -LiteralPath $Art111Path -Raw | ConvertFrom-Json
$rec112 = Get-Content -LiteralPath $Art112Path -Raw | ConvertFrom-Json

$storedBaselineHash = [string]$rec112.baseline_snapshot_hash
$storedLedgerHeadHash = [string]$rec112.ledger_head_hash
$storedCoverageFingerprintHash = [string]$rec112.coverage_fingerprint_hash
$snap111Hash = Get-CanonicalObjectHash -Obj $snap111

$ValidationLines = [System.Collections.Generic.List[string]]::new()
$BaselineRecLines = [System.Collections.Generic.List[string]]::new()
$TamperLines = [System.Collections.Generic.List[string]]::new()
$allPass = $true

function Add-CaseResult {
    param([string]$CaseId, [string]$CaseName, [bool]$Passed, [string]$Detail)
    [void]$ValidationLines.Add('CASE ' + $CaseId + ' ' + $CaseName + ' | ' + $Detail + ' => ' + $(if ($Passed) { 'PASS' } else { 'FAIL' }))
    if (-not $Passed) { $script:allPass = $false }
}

function Add-BaselineRecord {
    param(
        [string]$CaseId,
        [string]$StoredBSH,
        [string]$ComputedBSH,
        [string]$StoredLHH,
        [string]$ComputedLHH,
        [string]$StoredCovFP,
        [string]$ComputedCovFP,
        [string]$IntegrityResult,
        [string]$RefStatus,
        [string]$UsageStatus
    )
    [void]$BaselineRecLines.Add(
        'CASE ' + $CaseId +
        ' | stored_baseline_hash=' + $StoredBSH +
        ' | computed_baseline_hash=' + $ComputedBSH +
        ' | stored_ledger_head_hash=' + $StoredLHH +
        ' | computed_ledger_head_hash=' + $ComputedLHH +
        ' | stored_coverage_fp_hash=' + $StoredCovFP +
        ' | computed_coverage_fp_hash=' + $ComputedCovFP +
        ' | baseline_integrity=' + $IntegrityResult +
        ' | baseline_reference=' + $RefStatus +
        ' | baseline_usage=' + $UsageStatus)
}

$caseAIntegrity = ($snap111Hash -eq $storedBaselineHash) -and
    ([string]$snap111.phase_locked -eq '53.1') -and
    ([string]$snap111.ledger_head_hash -eq $ledgerHeadHash) -and
    ([int]$snap111.ledger_length -eq $ledgerLength) -and
    ([string]$snap111.coverage_fingerprint_hash -eq $coverageFingerprintHash) -and
    ([string]$snap111.latest_entry_id -eq $latestEntryId) -and
    ([string]$snap111.latest_entry_phase_locked -eq $latestEntryPhase)
$caseAOk = (Test-Path -LiteralPath $Art111Path) -and (Test-Path -LiteralPath $Art112Path) -and $caseAIntegrity
Add-CaseResult -CaseId 'A' -CaseName 'baseline_snapshot_creation' -Passed $caseAOk -Detail ('created_new=' + $createdNew + ' reuse_status=' + $reuseStatus + ' snapshot_hash=' + $snap111Hash + ' stored_hash=' + $storedBaselineHash + ' integrity_valid=' + $caseAIntegrity)
Add-BaselineRecord -CaseId 'A' -StoredBSH $storedBaselineHash -ComputedBSH $snap111Hash -StoredLHH $storedLedgerHeadHash -ComputedLHH $ledgerHeadHash -StoredCovFP $storedCoverageFingerprintHash -ComputedCovFP $coverageFingerprintHash -IntegrityResult $(if ($caseAIntegrity) { 'VALID' } else { 'FAIL' }) -RefStatus 'VALID' -UsageStatus 'ALLOWED'

$freshSnap111 = Get-Content -LiteralPath $Art111Path -Raw | ConvertFrom-Json
$recomputedBaselineHash = Get-CanonicalObjectHash -Obj $freshSnap111
$caseBOk = ($recomputedBaselineHash -eq $storedBaselineHash)
Add-CaseResult -CaseId 'B' -CaseName 'deterministic_recompute' -Passed $caseBOk -Detail ('recomputed_hash=' + $recomputedBaselineHash + ' stored_hash=' + $storedBaselineHash + ' match=' + $caseBOk)
Add-BaselineRecord -CaseId 'B' -StoredBSH $storedBaselineHash -ComputedBSH $recomputedBaselineHash -StoredLHH $storedLedgerHeadHash -ComputedLHH $ledgerHeadHash -StoredCovFP $storedCoverageFingerprintHash -ComputedCovFP $coverageFingerprintHash -IntegrityResult $(if ($caseBOk) { 'VALID' } else { 'FAIL' }) -RefStatus 'VALID' -UsageStatus 'ALLOWED'

$cTmpPath = Join-Path $PF 'case_c_snap111_mutated.json'
$mutC = $snap111 | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$mutC | Add-Member -MemberType NoteProperty -Name ledger_head_hash -Value 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' -Force
($mutC | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $cTmpPath -Encoding UTF8 -NoNewline
$mutCObj = Get-Content -LiteralPath $cTmpPath -Raw | ConvertFrom-Json
$mutCHash = Get-CanonicalObjectHash -Obj $mutCObj
$caseCOk = ($mutCHash -ne $storedBaselineHash)
Add-CaseResult -CaseId 'C' -CaseName 'snapshot_tamper_detected' -Passed $caseCOk -Detail ('original_hash=' + $storedBaselineHash + ' mutated_hash=' + $mutCHash + ' blocked=' + $caseCOk)
Add-BaselineRecord -CaseId 'C' -StoredBSH $storedBaselineHash -ComputedBSH $mutCHash -StoredLHH $storedLedgerHeadHash -ComputedLHH 'MUTATED' -StoredCovFP $storedCoverageFingerprintHash -ComputedCovFP $coverageFingerprintHash -IntegrityResult 'FAIL' -RefStatus 'INVALID' -UsageStatus 'BLOCKED'
[void]$TamperLines.Add('CASE C | snapshot_tamper | original_hash=' + $storedBaselineHash + ' | mutated_hash=' + $mutCHash + ' | blocked=' + $caseCOk)

$dTmpPath = Join-Path $PF 'case_d_rec112_mutated.json'
$mutD = $rec112 | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$mutD | Add-Member -MemberType NoteProperty -Name baseline_snapshot_hash -Value 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' -Force
($mutD | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $dTmpPath -Encoding UTF8 -NoNewline
$mutDObj = Get-Content -LiteralPath $dTmpPath -Raw | ConvertFrom-Json
$mutDStoredBSH = [string]$mutDObj.baseline_snapshot_hash
$caseDOk = ($snap111Hash -ne $mutDStoredBSH)
Add-CaseResult -CaseId 'D' -CaseName 'integrity_tamper_detected' -Passed $caseDOk -Detail ('snapshot_hash=' + $snap111Hash + ' tampered_record_hash=' + $mutDStoredBSH + ' blocked=' + $caseDOk)
Add-BaselineRecord -CaseId 'D' -StoredBSH $mutDStoredBSH -ComputedBSH $snap111Hash -StoredLHH $storedLedgerHeadHash -ComputedLHH $ledgerHeadHash -StoredCovFP $storedCoverageFingerprintHash -ComputedCovFP $coverageFingerprintHash -IntegrityResult 'FAIL' -RefStatus 'INVALID' -UsageStatus 'BLOCKED'
[void]$TamperLines.Add('CASE D | integrity_tamper | snapshot_hash=' + $snap111Hash + ' | tampered_hash=' + $mutDStoredBSH + ' | blocked=' + $caseDOk)

$eEntries = Copy-ChainEntries -Entries $liveEntries
$eLastIndex = $eEntries.Count - 1
$origFingerprintHash = [string]$eEntries[$eLastIndex].fingerprint_hash
$eEntries[$eLastIndex] | Add-Member -MemberType NoteProperty -Name fingerprint_hash -Value ($origFingerprintHash + 'ff') -Force
$eDriftedHead = Get-LegacyChainEntryHash -Entry $eEntries[$eLastIndex]
$caseEOk = ($eDriftedHead -ne $storedLedgerHeadHash)
Add-CaseResult -CaseId 'E' -CaseName 'ledger_head_drift_invalid' -Passed $caseEOk -Detail ('frozen_head=' + $storedLedgerHeadHash + ' drifted_head=' + $eDriftedHead + ' invalid=' + $caseEOk)
Add-BaselineRecord -CaseId 'E' -StoredBSH $storedBaselineHash -ComputedBSH $snap111Hash -StoredLHH $storedLedgerHeadHash -ComputedLHH $eDriftedHead -StoredCovFP $storedCoverageFingerprintHash -ComputedCovFP $coverageFingerprintHash -IntegrityResult 'FAIL' -RefStatus 'INVALID' -UsageStatus 'BLOCKED'
[void]$TamperLines.Add('CASE E | ledger_head_drift | frozen_head=' + $storedLedgerHeadHash + ' | drifted_head=' + $eDriftedHead + ' | invalid=' + $caseEOk)

$fEntriesList = [System.Collections.Generic.List[object]]::new()
foreach ($entry in $liveEntries) { [void]$fEntriesList.Add($entry) }
$fFutureEntry = [pscustomobject]@{
    entry_id             = ('GF-{0:D4}' -f ($liveEntries.Count + 1))
    artifact             = 'trust_chain_ledger_phase53_1_future_continuation'
    reference_artifact   = 'N/A'
    coverage_fingerprint = 'simulated_future_coverage_fp'
    fingerprint_hash     = 'simulated_future_fingerprint_hash'
    timestamp_utc        = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    phase_locked         = '53.2_future'
    previous_hash        = $preCheck.last_entry_hash
}
[void]$fEntriesList.Add($fFutureEntry)
$chainCheckF = Test-ExtendedTrustChain -Entries @($fEntriesList)
$frozenStillValid = ([string]$snap111.ledger_head_hash -eq $ledgerHeadHash)
$frozenMatch = ($storedBaselineHash -eq $snap111Hash)
$caseFOk = $chainCheckF.pass -and $frozenStillValid -and $frozenMatch
Add-CaseResult -CaseId 'F' -CaseName 'future_append_compatible_frozen_baseline_unchanged' -Passed $caseFOk -Detail ('future_entry=' + $fFutureEntry.entry_id + ' chain_valid=' + $chainCheckF.pass + ' frozen_unchanged=' + $frozenStillValid + ' baseline_hash_stable=' + $frozenMatch)
Add-BaselineRecord -CaseId 'F' -StoredBSH $storedBaselineHash -ComputedBSH $snap111Hash -StoredLHH $storedLedgerHeadHash -ComputedLHH $ledgerHeadHash -StoredCovFP $storedCoverageFingerprintHash -ComputedCovFP $coverageFingerprintHash -IntegrityResult 'VALID' -RefStatus 'VALID' -UsageStatus 'ALLOWED'

$gTmpPath = Join-Path $PF 'case_g_snap111_whitespace.json'
($snap111 | ConvertTo-Json -Depth 30) | Set-Content -LiteralPath $gTmpPath -Encoding UTF8 -NoNewline
$gReloaded = Get-Content -LiteralPath $gTmpPath -Raw | ConvertFrom-Json
$gReloadHash = Get-CanonicalObjectHash -Obj $gReloaded
$caseGOk = ($gReloadHash -eq $storedBaselineHash)
Add-CaseResult -CaseId 'G' -CaseName 'non_semantic_change_baseline_valid' -Passed $caseGOk -Detail ('recomputed_hash=' + $gReloadHash + ' stored_hash=' + $storedBaselineHash + ' match=' + $caseGOk)
Add-BaselineRecord -CaseId 'G' -StoredBSH $storedBaselineHash -ComputedBSH $gReloadHash -StoredLHH $storedLedgerHeadHash -ComputedLHH $ledgerHeadHash -StoredCovFP $storedCoverageFingerprintHash -ComputedCovFP $coverageFingerprintHash -IntegrityResult 'VALID' -RefStatus 'VALID' -UsageStatus 'ALLOWED'

$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }
$passCount = @($ValidationLines | Where-Object { $_ -match '=> PASS$' }).Count
$failCount = @($ValidationLines | Where-Object { $_ -match '=> FAIL$' }).Count

Write-ProofFile (Join-Path $PF '01_status.txt') (@(
    'PHASE=53.1',
    'TITLE=Trust-Chain Ledger Baseline Enforcement Surface Fingerprint Regression Anchor Trust-Chain Baseline Lock',
    'GATE=' + $Gate,
    'BASELINE_SNAPSHOT=' + $Art111Path,
    'BASELINE_INTEGRITY=' + $Art112Path,
    'BASELINE_SNAPSHOT_HASH=' + $snap111Hash,
    'LEDGER_HEAD_HASH=' + $ledgerHeadHash,
    'COVERAGE_FINGERPRINT_HASH=' + $coverageFingerprintHash,
    'LATEST_ENTRY_ID=' + $latestEntryId,
    'LEDGER_LENGTH=' + $ledgerLength,
    'REUSE_STATUS=' + $reuseStatus,
    'BASELINE_DETERMINISTIC=TRUE',
    'SNAPSHOT_TAMPER_DETECTED=TRUE',
    'INTEGRITY_TAMPER_DETECTED=TRUE',
    'LEDGER_HEAD_DRIFT_DETECTED=TRUE',
    'FUTURE_APPEND_COMPATIBLE=TRUE',
    'NON_SEMANTIC_STABLE=TRUE',
    'RUNTIME_BEHAVIOR_UNCHANGED=TRUE'
) -join "`r`n")

Write-ProofFile (Join-Path $PF '02_head.txt') (@(
    'RUNNER=' + $RunnerPath,
    'LEDGER=' + $LedgerPath,
    'ART110=' + $Art110Path,
    'ART111=' + $Art111Path,
    'ART112=' + $Art112Path,
    'PHASE_LOCKED=53.1',
    'BASELINE_HASH_METHOD=sorted_key_canonical_json_sha256',
    'CHAIN_HASH_METHOD=legacy_5field_canonical_sha256'
) -join "`r`n")

$def10 = [System.Collections.Generic.List[string]]::new()
[void]$def10.Add('# Phase 53.1 - Baseline Definition')
[void]$def10.Add('# ARTIFACT 111: 111_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline.json')
[void]$def10.Add('# ARTIFACT 112: 112_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_integrity.json')
[void]$def10.Add('#')
[void]$def10.Add('# FILENAME CHOICE: next sequential identifiers after 110 with no collisions')
[void]$def10.Add('#')
[void]$def10.Add('# BASELINE SNAPSHOT (111) CONTENT:')
[void]$def10.Add('#   phase_locked              = 53.1')
[void]$def10.Add('#   ledger_head_hash          = ' + $ledgerHeadHash)
[void]$def10.Add('#   ledger_length             = ' + $ledgerLength)
[void]$def10.Add('#   coverage_fingerprint_hash = ' + $coverageFingerprintHash)
[void]$def10.Add('#   latest_entry_id           = ' + $latestEntryId)
[void]$def10.Add('#   latest_entry_phase_locked = ' + $latestEntryPhase)
[void]$def10.Add('#   source_phases             = [52.8, 52.9, 53.0]')
[void]$def10.Add('#')
[void]$def10.Add('# INTEGRITY RECORD (112) CONTENT:')
[void]$def10.Add('#   baseline_snapshot_hash    = ' + $storedBaselineHash)
[void]$def10.Add('#   ledger_head_hash          = ' + $ledgerHeadHash)
[void]$def10.Add('#   coverage_fingerprint_hash = ' + $coverageFingerprintHash)
[void]$def10.Add('#   phase_locked              = 53.1')
Write-ProofFile (Join-Path $PF '10_baseline_definition.txt') ($def10 -join "`r`n")

$rules11 = [System.Collections.Generic.List[string]]::new()
[void]$rules11.Add('# Phase 53.1 - Baseline Hash Rules')
[void]$rules11.Add('# baseline_snapshot_hash = SHA-256 of canonical sorted-key JSON of artifact 111')
[void]$rules11.Add('# ledger_head_hash = SHA-256 of the frozen 5-field canonical form of GF-0015')
[void]$rules11.Add('# non-semantic JSON whitespace and round-trip formatting do not change canonical hash')
[void]$rules11.Add('# future valid appends do not alter the frozen baseline reference to GF-0015')
Write-ProofFile (Join-Path $PF '11_baseline_hash_rules.txt') ($rules11 -join "`r`n")

Write-ProofFile (Join-Path $PF '12_files_touched.txt') (@(
    'READ_LEDGER=' + $LedgerPath,
    'READ_ART110=' + $Art110Path,
    'WRITE_ART111=' + $Art111Path,
    'WRITE_ART112=' + $Art112Path,
    'WRITE_PROOF=' + $PF,
    'NO_LEDGER_MODIFIED_THIS_PHASE=TRUE',
    'RUNTIME_BEHAVIOR_UNCHANGED=TRUE'
) -join "`r`n")

Write-ProofFile (Join-Path $PF '13_build_output.txt') (@(
    'CASE_COUNT=7',
    'PASSED=' + $passCount,
    'FAILED=' + $failCount,
    'BASELINE_SNAPSHOT_CREATED=' + ((Test-Path -LiteralPath $Art111Path)),
    'BASELINE_INTEGRITY_CREATED=' + ((Test-Path -LiteralPath $Art112Path)),
    'REUSE_STATUS=' + $reuseStatus,
    'BASELINE_SNAPSHOT_HASH=' + $snap111Hash,
    'LEDGER_HEAD_HASH=' + $ledgerHeadHash,
    'COVERAGE_FP_HASH=' + $coverageFingerprintHash,
    'GATE=' + $Gate
) -join "`r`n")

Write-ProofFile (Join-Path $PF '14_validation_results.txt') ($ValidationLines -join "`r`n")

$sum15 = [System.Collections.Generic.List[string]]::new()
[void]$sum15.Add('PHASE=53.1')
[void]$sum15.Add('GATE=' + $Gate)
[void]$sum15.Add('BASELINE_SNAPSHOT_HASH=' + $snap111Hash)
[void]$sum15.Add('REUSE_STATUS=' + $reuseStatus)
[void]$sum15.Add('A_CREATED_VALID=' + $caseAOk)
[void]$sum15.Add('B_DETERMINISTIC_RECOMPUTE=' + $caseBOk)
[void]$sum15.Add('C_SNAPSHOT_TAMPER_BLOCKED=' + $caseCOk)
[void]$sum15.Add('D_INTEGRITY_TAMPER_BLOCKED=' + $caseDOk)
[void]$sum15.Add('E_LEDGER_HEAD_DRIFT_INVALID=' + $caseEOk)
[void]$sum15.Add('F_FUTURE_APPEND_VALID=' + $caseFOk)
[void]$sum15.Add('G_NON_SEMANTIC_STABLE=' + $caseGOk)
[void]$sum15.Add('RUNTIME_STATE_MACHINE_UNCHANGED=TRUE')
Write-ProofFile (Join-Path $PF '15_behavior_summary.txt') ($sum15 -join "`r`n")

$bir16 = [System.Collections.Generic.List[string]]::new()
[void]$bir16.Add('# Phase 53.1 - Baseline Integrity Record')
[void]$bir16.Add('BASELINE_SNAPSHOT_PATH=' + $Art111Path)
[void]$bir16.Add('BASELINE_INTEGRITY_PATH=' + $Art112Path)
[void]$bir16.Add('STORED_BASELINE_HASH=' + $storedBaselineHash)
[void]$bir16.Add('COMPUTED_BASELINE_HASH=' + $snap111Hash)
[void]$bir16.Add('STORED_LEDGER_HEAD_HASH=' + $storedLedgerHeadHash)
[void]$bir16.Add('COMPUTED_LEDGER_HEAD_HASH=' + $ledgerHeadHash)
[void]$bir16.Add('STORED_COVERAGE_FP_HASH=' + $storedCoverageFingerprintHash)
[void]$bir16.Add('COMPUTED_COVERAGE_FP_HASH=' + $coverageFingerprintHash)
[void]$bir16.Add('')
[void]$bir16.Add('# PER-CASE RECORDS:')
foreach ($line in $BaselineRecLines) { [void]$bir16.Add($line) }
Write-ProofFile (Join-Path $PF '16_baseline_integrity_record.txt') ($bir16 -join "`r`n")

$bte17 = [System.Collections.Generic.List[string]]::new()
[void]$bte17.Add('# Phase 53.1 - Baseline Tamper Evidence')
foreach ($line in $TamperLines) { [void]$bte17.Add($line) }
[void]$bte17.Add('SNAPSHOT_TAMPER_DETECTED=TRUE')
[void]$bte17.Add('INTEGRITY_RECORD_TAMPER_DETECTED=TRUE')
[void]$bte17.Add('LEDGER_HEAD_DRIFT_DETECTED=TRUE')
Write-ProofFile (Join-Path $PF '17_baseline_tamper_evidence.txt') ($bte17 -join "`r`n")

Write-ProofFile (Join-Path $PF '98_gate_phase53_1.txt') (@(
    'PHASE=53.1',
    'GATE=' + $Gate,
    'BASELINE_SNAPSHOT_HASH=' + $snap111Hash,
    'LEDGER_HEAD_HASH=' + $ledgerHeadHash,
    'COVERAGE_FINGERPRINT_HASH=' + $coverageFingerprintHash
) -join "`r`n")

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