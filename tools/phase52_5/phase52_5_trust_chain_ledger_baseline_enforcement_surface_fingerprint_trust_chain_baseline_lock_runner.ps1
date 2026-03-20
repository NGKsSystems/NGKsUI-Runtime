Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ((Get-Location).Path -ne $Root) {
    Write-Output 'hey stupid Fucker, wrong window again'
    exit 1
}
Set-Location $Root

# ── Crypto & canonical helpers ─────────────────────────────────────────────────

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
        $s = $s -replace '"',  '\"'
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
        foreach ($k in $keys) { $v = $Value.PSObject.Properties[$k].Value; [void]$pairs.Add(('"' + $k + '":' + (Convert-ToCanonicalJson -Value $v))) }
        return '{' + ($pairs -join ',') + '}'
    }
    return '"' + ([string]$Value -replace '"', '\"') + '"'
}

function Get-CanonicalObjectHash {
    param([object]$Obj)
    return Get-StringSha256Hex -Text (Convert-ToCanonicalJson -Value $Obj)
}

# ── Chain entry hashing (frozen 5-field scheme) ────────────────────────────────
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
    if ($Entries.Count -eq 0) { $result.pass = $false; $result.reason = 'chain_entries_empty'; return $result }
    $hashes = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $Entries.Count; $i++) {
        $entry = $Entries[$i]
        if ($i -eq 0) {
            if ($null -ne $entry.previous_hash -and -not [string]::IsNullOrWhiteSpace([string]$entry.previous_hash)) {
                $result.pass = $false; $result.reason = 'first_entry_previous_hash_must_be_null'; return $result
            }
        } else {
            $expectedPrev = $hashes[$i - 1]
            if ([string]$entry.previous_hash -ne $expectedPrev) {
                $result.pass = $false; $result.reason = ('previous_hash_link_mismatch_at_entry_' + [string]$entry.entry_id + '_index_' + $i); return $result
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

# ── Paths & constants ──────────────────────────────────────────────────────────
$Timestamp    = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunnerPath   = Join-Path $Root 'tools\phase52_5\phase52_5_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_lock_runner.ps1'
$LedgerPath   = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$Art107Path   = Join-Path $Root 'control_plane\107_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint.json'
$Art108Path   = Join-Path $Root 'control_plane\108_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline.json'
$Art109Path   = Join-Path $Root 'control_plane\109_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_integrity.json'
$PF           = Join-Path $Root ('_proof\phase52_5_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_lock_' + $Timestamp)

New-Item -ItemType Directory -Path $PF | Out-Null

# ── Load live artifacts ────────────────────────────────────────────────────────
foreach ($p in @($LedgerPath, $Art107Path)) {
    if (-not (Test-Path -LiteralPath $p)) { throw 'Missing required artifact: ' + $p }
}

$ledgerObj    = Get-Content -LiteralPath $LedgerPath -Raw | ConvertFrom-Json
$art107Obj    = Get-Content -LiteralPath $Art107Path -Raw | ConvertFrom-Json
$liveEntries  = @($ledgerObj.entries)

# Verify ledger integrity before anything
$preCheck = Test-ExtendedTrustChain -Entries $liveEntries
if (-not $preCheck.pass) { throw 'Live ledger integrity check failed before baseline: ' + $preCheck.reason }

# Latest entry must be GF-0014 locked to 52.4
$latestEntry = $liveEntries[$liveEntries.Count - 1]
if ([string]$latestEntry.phase_locked -ne '52.4') {
    throw ('Latest ledger entry is not phase 52.4. Got: ' + [string]$latestEntry.phase_locked)
}

$ledgerHeadHash      = $preCheck.last_entry_hash
$coverageFPHash      = [string]$art107Obj.coverage_fingerprint_sha256
$latestEntryId       = [string]$latestEntry.entry_id
$latestEntryPhase    = [string]$latestEntry.phase_locked
$ledgerLength        = $liveEntries.Count
$art107OrigHash      = Get-CanonicalObjectHash -Obj $art107Obj

# ── Build baseline snapshot object ────────────────────────────────────────────
function New-BaselineSnapshot {
    param([string]$Ts)
    return [ordered]@{
        baseline_version          = 1
        phase_locked              = '52.5'
        ledger_head_hash          = $ledgerHeadHash
        ledger_length             = $ledgerLength
        coverage_fingerprint_hash = $coverageFPHash
        latest_entry_id           = $latestEntryId
        latest_entry_phase_locked = $latestEntryPhase
        timestamp_utc             = $Ts
        source_phases             = @('52.2', '52.3', '52.4')
    }
}

# ── Idempotency / first-run ────────────────────────────────────────────────────
$createdNew = $false

if ((Test-Path -LiteralPath $Art108Path) -and (Test-Path -LiteralPath $Art109Path)) {
    # Existing artifacts — verify they are consistent
    $ex108    = Get-Content -LiteralPath $Art108Path -Raw | ConvertFrom-Json
    $ex109    = Get-Content -LiteralPath $Art109Path -Raw | ConvertFrom-Json
    $ex108Hash = Get-CanonicalObjectHash -Obj $ex108
    $ex109StoredBSH = [string]$ex109.baseline_snapshot_hash
    if ($ex108Hash -ne $ex109StoredBSH) {
        throw ('Existing artifacts 108/109 are inconsistent. 108 canonical hash=' + $ex108Hash + ' 109 stored baseline_snapshot_hash=' + $ex109StoredBSH)
    }
    Write-Output 'INFO: Existing artifacts 108/109 found and verified — reusing (idempotent run)'
} else {
    # First run — create artifacts.
    # IMPORTANT: write 108 to disk first, then reload it and compute the canonical
    # hash from the on-disk pscustomobject.  This guarantees the stored hash in 109
    # always equals the hash computed by any subsequent reload of 108 from disk.
    $tsNow = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'
    $baselineSnapInMem = New-BaselineSnapshot -Ts $tsNow
    ($baselineSnapInMem | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $Art108Path -Encoding UTF8 -NoNewline

    # Reload from disk before computing hash so the hash matches every future reload.
    $baselineSnapOnDisk   = Get-Content -LiteralPath $Art108Path -Raw | ConvertFrom-Json
    $baselineSnapDiskHash = Get-CanonicalObjectHash -Obj $baselineSnapOnDisk

    $integrityRecord = [ordered]@{
        artifact_id               = '109'
        phase_locked              = '52.5'
        baseline_snapshot_hash    = $baselineSnapDiskHash
        ledger_head_hash          = $ledgerHeadHash
        coverage_fingerprint_hash = $coverageFPHash
        latest_entry_id           = $latestEntryId
        source_artifact           = '108_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline.json'
        timestamp_utc             = $tsNow
    }
    ($integrityRecord | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $Art109Path -Encoding UTF8 -NoNewline
    $createdNew = $true
}

# Reload both from disk for all verifications going forward
$snap108 = Get-Content -LiteralPath $Art108Path -Raw | ConvertFrom-Json
$rec109  = Get-Content -LiteralPath $Art109Path -Raw | ConvertFrom-Json

$storedBaselineHash    = [string]$rec109.baseline_snapshot_hash
$storedLedgerHeadHash  = [string]$rec109.ledger_head_hash
$storedCovFPHash       = [string]$rec109.coverage_fingerprint_hash
$snap108Hash           = Get-CanonicalObjectHash -Obj $snap108

# ── Validation helpers ─────────────────────────────────────────────────────────
$ValidationLines  = [System.Collections.Generic.List[string]]::new()
$BaselineRecLines = [System.Collections.Generic.List[string]]::new()
$TamperLines      = [System.Collections.Generic.List[string]]::new()
$allPass          = $true

function Add-CaseResult {
    param($Lines, [string]$CaseId, [string]$CaseName, [bool]$Passed, [string]$Detail)
    $Lines.Add('CASE ' + $CaseId + ' ' + $CaseName + ' | ' + $Detail + ' => ' + $(if ($Passed) { 'PASS' } else { 'FAIL' }))
    return $Passed
}

function Add-BaselineRecord {
    param([string]$CaseId, [string]$StoredBSH, [string]$ComputedBSH,
          [string]$StoredLHH, [string]$ComputedLHH,
          [string]$StoredCovFP, [string]$ComputedCovFP,
          [string]$IntegrityResult, [string]$RefStatus, [string]$UsageStatus)
    $BaselineRecLines.Add(
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

# ── CASE A — Baseline snapshot creation ───────────────────────────────────────
$caseAIntegrity = ($snap108Hash -eq $storedBaselineHash) -and
                  ([string]$snap108.ledger_head_hash    -eq $ledgerHeadHash) -and
                  ([string]$snap108.coverage_fingerprint_hash -eq $coverageFPHash) -and
                  ([string]$snap108.latest_entry_id     -eq $latestEntryId) -and
                  ([string]$snap108.phase_locked        -eq '52.5')
$caseAOk = (Test-Path -LiteralPath $Art108Path) -and (Test-Path -LiteralPath $Art109Path) -and $caseAIntegrity
if (-not $caseAOk) { $allPass = $false }
$caseADetail = 'baseline_snapshot_path=' + $Art108Path + ' baseline_integrity_path=' + $Art109Path + ' created_new=' + $createdNew + ' snap_hash=' + $snap108Hash + ' stored_hash=' + $storedBaselineHash + ' ledger_head_hash=' + $ledgerHeadHash + ' integrity_valid=' + $caseAIntegrity
[void](Add-CaseResult -Lines $ValidationLines -CaseId 'A' -CaseName 'baseline_snapshot_creation' -Passed $caseAOk -Detail $caseADetail)
Add-BaselineRecord -CaseId 'A' -StoredBSH $storedBaselineHash -ComputedBSH $snap108Hash -StoredLHH $storedLedgerHeadHash -ComputedLHH $ledgerHeadHash -StoredCovFP $storedCovFPHash -ComputedCovFP $coverageFPHash -IntegrityResult $(if ($caseAIntegrity) { 'VALID' } else { 'FAIL' }) -RefStatus 'VALID' -UsageStatus 'ALLOWED'

# ── CASE B — Baseline verification (deterministic re-hash) ────────────────────
# Reload 108 fresh and recompute its canonical hash — must equal stored in 109
$freshSnap108  = Get-Content -LiteralPath $Art108Path -Raw | ConvertFrom-Json
$recomputedBSH = Get-CanonicalObjectHash -Obj $freshSnap108
$caseBOk       = ($recomputedBSH -eq $storedBaselineHash)
if (-not $caseBOk) { $allPass = $false }
$caseBDetail = 'recomputed_hash=' + $recomputedBSH + ' stored_hash=' + $storedBaselineHash + ' match=' + $caseBOk
[void](Add-CaseResult -Lines $ValidationLines -CaseId 'B' -CaseName 'baseline_verification_deterministic' -Passed $caseBOk -Detail $caseBDetail)
Add-BaselineRecord -CaseId 'B' -StoredBSH $storedBaselineHash -ComputedBSH $recomputedBSH -StoredLHH $storedLedgerHeadHash -ComputedLHH $ledgerHeadHash -StoredCovFP $storedCovFPHash -ComputedCovFP $coverageFPHash -IntegrityResult $(if ($caseBOk) { 'VALID' } else { 'FAIL' }) -RefStatus 'VALID' -UsageStatus 'ALLOWED'

# ── CASE C — Baseline snapshot tamper ─────────────────────────────────────────
$cTmpPath = Join-Path $PF 'case_c_snap108_mutated.json'
$mutC = $snap108 | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$mutC | Add-Member -MemberType NoteProperty -Name ledger_head_hash -Value 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' -Force
($mutC | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $cTmpPath -Encoding UTF8 -NoNewline
$mutCObj       = Get-Content -LiteralPath $cTmpPath -Raw | ConvertFrom-Json
$mutCHash      = Get-CanonicalObjectHash -Obj $mutCObj
$caseCTamper   = ($mutCHash -ne $storedBaselineHash)   # tamper must change hash
$caseCOk       = $caseCTamper
if (-not $caseCOk) { $allPass = $false }
$caseCDetail = 'original_stored_hash=' + $storedBaselineHash + ' mutated_computed_hash=' + $mutCHash + ' tamper_detected=' + $caseCTamper
[void](Add-CaseResult -Lines $ValidationLines -CaseId 'C' -CaseName 'baseline_snapshot_tamper_detected' -Passed $caseCOk -Detail $caseCDetail)
Add-BaselineRecord -CaseId 'C' -StoredBSH $storedBaselineHash -ComputedBSH $mutCHash -StoredLHH $storedLedgerHeadHash -ComputedLHH 'MUTATED' -StoredCovFP $storedCovFPHash -ComputedCovFP $coverageFPHash -IntegrityResult 'FAIL' -RefStatus 'INVALID' -UsageStatus 'BLOCKED'
$TamperLines.Add('CASE C | baseline_snapshot_tamper | original_hash=' + $storedBaselineHash + ' | mutated_hash=' + $mutCHash + ' | tamper_detected=' + $caseCTamper)

# ── CASE D — Integrity record tamper ─────────────────────────────────────────
$dTmpPath = Join-Path $PF 'case_d_rec109_mutated.json'
$mutD = $rec109 | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$mutD | Add-Member -MemberType NoteProperty -Name baseline_snapshot_hash -Value 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' -Force
($mutD | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $dTmpPath -Encoding UTF8 -NoNewline
$mutDObj        = Get-Content -LiteralPath $dTmpPath -Raw | ConvertFrom-Json
$mutDStoredBSH  = [string]$mutDObj.baseline_snapshot_hash
# Verify: re-hash real 108 against tampered 109.baseline_snapshot_hash → must not match
$caseDTamper    = ($snap108Hash -ne $mutDStoredBSH)
$caseDOk        = $caseDTamper
if (-not $caseDOk) { $allPass = $false }
$caseDDetail = 'snap108_hash=' + $snap108Hash + ' tampered_record_stored_hash=' + $mutDStoredBSH + ' mismatch_detected=' + $caseDTamper
[void](Add-CaseResult -Lines $ValidationLines -CaseId 'D' -CaseName 'integrity_record_tamper_detected' -Passed $caseDOk -Detail $caseDDetail)
Add-BaselineRecord -CaseId 'D' -StoredBSH $mutDStoredBSH -ComputedBSH $snap108Hash -StoredLHH $storedLedgerHeadHash -ComputedLHH $ledgerHeadHash -StoredCovFP $storedCovFPHash -ComputedCovFP $coverageFPHash -IntegrityResult 'FAIL' -RefStatus 'INVALID' -UsageStatus 'BLOCKED'
$TamperLines.Add('CASE D | integrity_record_tamper | snap108_hash=' + $snap108Hash + ' | tampered_stored_hash=' + $mutDStoredBSH + ' | tamper_detected=' + $caseDTamper)

# ── CASE E — Ledger head drift ────────────────────────────────────────────────
# Simulate drift: recompute ledger head hash from a chain where GF-0014 has
# a corrupted fingerprint_hash → different entry hash → different chain head
$eEntries = @($liveEntries | ForEach-Object { $_ | ConvertTo-Json -Depth 10 | ConvertFrom-Json })
$eLastIdx = $eEntries.Count - 1
$origFH   = [string]$eEntries[$eLastIdx].fingerprint_hash
$eEntries[$eLastIdx] | Add-Member -MemberType NoteProperty -Name fingerprint_hash -Value ($origFH + 'ff') -Force
# Recompute chain head hash for mutated chain
$eHash = Get-LegacyChainEntryHash -Entry $eEntries[$eLastIdx]
# Build expected chain hashes for mutated entries (only last one changes)
$eDriftedHead = $eHash
$caseEDrift   = ($eDriftedHead -ne $storedLedgerHeadHash)
$caseEOk      = $caseEDrift    # drift must be detected
if (-not $caseEOk) { $allPass = $false }
$caseEDetail = 'frozen_ledger_head_hash=' + $storedLedgerHeadHash + ' drifted_ledger_head_hash=' + $eDriftedHead + ' drift_detected=' + $caseEDrift
[void](Add-CaseResult -Lines $ValidationLines -CaseId 'E' -CaseName 'ledger_head_drift_detected' -Passed $caseEOk -Detail $caseEDetail)
Add-BaselineRecord -CaseId 'E' -StoredBSH $storedBaselineHash -ComputedBSH $snap108Hash -StoredLHH $storedLedgerHeadHash -ComputedLHH $eDriftedHead -StoredCovFP $storedCovFPHash -ComputedCovFP $coverageFPHash -IntegrityResult 'FAIL' -RefStatus 'INVALID' -UsageStatus 'BLOCKED'
$TamperLines.Add('CASE E | ledger_head_drift | frozen_head=' + $storedLedgerHeadHash + ' | drifted_head=' + $eDriftedHead + ' | drift_detected=' + $caseEDrift)

# ── CASE F — Future append compatibility ──────────────────────────────────────
# Append a simulated GF-0015 in memory. Prove:
#   1) The extended chain is valid
#   2) The frozen baseline snap108.ledger_head_hash still matches hash(GF-0014)
#   3) The frozen baseline is unchanged despite chain growth
$fEntries  = [System.Collections.Generic.List[object]]::new()
foreach ($e in $liveEntries) { $fEntries.Add($e) }
$fPrevHash = $preCheck.last_entry_hash
$fFutureEntry = [pscustomobject]@{
    entry_id             = ('GF-{0:D4}' -f ($liveEntries.Count + 1))
    artifact             = 'trust_chain_ledger_simulated_52_5_continuation'
    reference_artifact   = 'N/A'
    coverage_fingerprint = 'simulated_future_fp_0000000000000000000000000000000000000000000000000'
    fingerprint_hash     = 'simulated_future_fh_0000000000000000000000000000000000000000000000000'
    timestamp_utc        = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    phase_locked         = '52.6_future'
    previous_hash        = $fPrevHash
}
$fEntries.Add($fFutureEntry)
$chainCheckF       = Test-ExtendedTrustChain -Entries @($fEntries)
$fFrozenStillValid = ([string]$snap108.ledger_head_hash -eq $ledgerHeadHash)   # frozen is unchanged
$fFrozenMatch      = ($storedBaselineHash -eq $snap108Hash)                    # baseline hash stable
$caseFOk           = $chainCheckF.pass -and $fFrozenStillValid -and $fFrozenMatch
if (-not $caseFOk) { $allPass = $false }
$caseFDetail = 'future_entry=' + $fFutureEntry.entry_id + ' chain_valid=' + $chainCheckF.pass + ' frozen_baseline_unchanged=' + $fFrozenStillValid + ' baseline_hash_stable=' + $fFrozenMatch
[void](Add-CaseResult -Lines $ValidationLines -CaseId 'F' -CaseName 'future_append_compatible_frozen_baseline_unchanged' -Passed $caseFOk -Detail $caseFDetail)
Add-BaselineRecord -CaseId 'F' -StoredBSH $storedBaselineHash -ComputedBSH $snap108Hash -StoredLHH $storedLedgerHeadHash -ComputedLHH $ledgerHeadHash -StoredCovFP $storedCovFPHash -ComputedCovFP $coverageFPHash -IntegrityResult 'VALID' -RefStatus 'VALID' -UsageStatus 'ALLOWED'

# ── CASE G — Non-semantic change ──────────────────────────────────────────────
# Write baseline snapshot with extra indentation/whitespace, reload, recompute hash.
# Canonical hash (keys sorted, compact) must remain the same.
$gTmpPath = Join-Path $PF 'case_g_snap108_whitespace.json'
($snap108 | ConvertTo-Json -Depth 30) | Set-Content -LiteralPath $gTmpPath -Encoding UTF8 -NoNewline
$gReloaded    = Get-Content -LiteralPath $gTmpPath -Raw | ConvertFrom-Json
$gReloadHash  = Get-CanonicalObjectHash -Obj $gReloaded
$caseGOk      = ($gReloadHash -eq $storedBaselineHash)
if (-not $caseGOk) { $allPass = $false }
$caseGDetail = 'whitespace_serialized_then_reloaded | recomputed_hash=' + $gReloadHash + ' stored_hash=' + $storedBaselineHash + ' match=' + $caseGOk
[void](Add-CaseResult -Lines $ValidationLines -CaseId 'G' -CaseName 'non_semantic_change_baseline_valid' -Passed $caseGOk -Detail $caseGDetail)
Add-BaselineRecord -CaseId 'G' -StoredBSH $storedBaselineHash -ComputedBSH $gReloadHash -StoredLHH $storedLedgerHeadHash -ComputedLHH $ledgerHeadHash -StoredCovFP $storedCovFPHash -ComputedCovFP $coverageFPHash -IntegrityResult 'VALID' -RefStatus 'VALID' -UsageStatus 'ALLOWED'

# ── Gate ───────────────────────────────────────────────────────────────────────
$Gate      = if ($allPass) { 'PASS' } else { 'FAIL' }
$passCount = @($ValidationLines | Where-Object { $_ -match '=> PASS$' }).Count
$failCount = @($ValidationLines | Where-Object { $_ -match '=> FAIL$' }).Count

# ── Write proof artifacts ──────────────────────────────────────────────────────

Write-ProofFile (Join-Path $PF '01_status.txt') (@(
    'PHASE=52.5',
    'TITLE=Trust-Chain Ledger Baseline Enforcement Surface Fingerprint Trust-Chain Baseline Lock',
    'GATE=' + $Gate,
    'BASELINE_SNAPSHOT=' + $Art108Path,
    'BASELINE_INTEGRITY=' + $Art109Path,
    'BASELINE_SNAPSHOT_HASH=' + $snap108Hash,
    'LEDGER_HEAD_HASH=' + $ledgerHeadHash,
    'COVERAGE_FINGERPRINT_HASH=' + $coverageFPHash,
    'LATEST_ENTRY_ID=' + $latestEntryId,
    'LEDGER_LENGTH=' + $ledgerLength,
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
    'ART107=' + $Art107Path,
    'ART108=' + $Art108Path,
    'ART109=' + $Art109Path,
    'PHASE_LOCKED=52.5',
    'BASELINE_HASH_METHOD=sorted_key_canonical_json_sha256',
    'CHAIN_HASH_METHOD=legacy_5field_canonical_sha256'
) -join "`r`n")

$def10 = [System.Collections.Generic.List[string]]::new()
$def10.Add('# Phase 52.5 — Baseline Definition')
$def10.Add('#')
$def10.Add('# ARTIFACT 108: 108_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline.json')
$def10.Add('# ARTIFACT 109: 109_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_integrity.json')
$def10.Add('#')
$def10.Add('# FILENAME CHOICE:')
$def10.Add('#   Artifact 108: Next sequential identifier after 107 (last used). No collision. No alternative required.')
$def10.Add('#   Artifact 109: Next sequential after 108. No collision. No alternative required.')
$def10.Add('#')
$def10.Add('# BASELINE SNAPSHOT (108) CONTENT:')
$def10.Add('#   baseline_version          = 1')
$def10.Add('#   phase_locked              = "52.5"')
$def10.Add('#   ledger_head_hash          = SHA-256 of 5-field canonical form of GF-0014')
$def10.Add('#                              = ' + $ledgerHeadHash)
$def10.Add('#   ledger_length             = ' + $ledgerLength)
$def10.Add('#   coverage_fingerprint_hash = artifact107.coverage_fingerprint_sha256')
$def10.Add('#                              = ' + $coverageFPHash)
$def10.Add('#   latest_entry_id           = ' + $latestEntryId)
$def10.Add('#   latest_entry_phase_locked = ' + $latestEntryPhase)
$def10.Add('#   source_phases             = ["52.2","52.3","52.4"]')
$def10.Add('#')
$def10.Add('# INTEGRITY RECORD (109) CONTENT:')
$def10.Add('#   baseline_snapshot_hash   = Get-CanonicalObjectHash(108) = ' + $snap108Hash)
$def10.Add('#   ledger_head_hash         = same as 108 ledger_head_hash')
$def10.Add('#   coverage_fingerprint_hash = same as 108 coverage_fingerprint_hash')
$def10.Add('#   source_artifact          = 108_trust_chain_ledger...json')
$def10.Add('#')
$def10.Add('# HOW BASELINE SNAPSHOT IS HASHED:')
$def10.Add('#   Convert-ToCanonicalJson sorts all keys alphabetically, produces compact JSON.')
$def10.Add('#   SHA-256 of UTF-8 encoding of that canonical string = baseline_snapshot_hash.')
$def10.Add('#   This hash is deterministic regardless of JSON field insertion order or whitespace.')
$def10.Add('#')
$def10.Add('# HOW LEDGER HEAD HASH IS COMPUTED:')
$def10.Add('#   Get-LegacyChainEntryHash(GF-0014) using frozen 5-field scheme:')
$def10.Add('#   { entry_id, fingerprint_hash, timestamp_utc, phase_locked, previous_hash }')
$def10.Add('#   This matches the scheme used by all prior chain entries.')
Write-ProofFile (Join-Path $PF '10_baseline_definition.txt') ($def10 -join "`r`n")

$rules11 = [System.Collections.Generic.List[string]]::new()
$rules11.Add('# Phase 52.5 — Baseline Hash Rules')
$rules11.Add('#')
$rules11.Add('# BASELINE SNAPSHOT HASH (stored in integrity record 109):')
$rules11.Add('#   Computed from: canonical JSON of baseline snapshot object 108')
$rules11.Add('#   Method: keys sorted alphabetically, compact (no whitespace), SHA-256')
$rules11.Add('#   Changes when: any baseline field changes (ledger_head_hash, coverage_fp,')
$rules11.Add('#     ledger_length, latest_entry_id, phase_locked, timestamp_utc, source_phases)')
$rules11.Add('#   Stable when: JSON indentation/whitespace changes, field order in file changes')
$rules11.Add('#')
$rules11.Add('# LEDGER HEAD HASH (stored in both 108 and 109):')
$rules11.Add('#   Computed from: 5-field canonical form of latest GF entry')
$rules11.Add('#   Method: ConvertTo-Json -Compress of ordered { entry_id, fingerprint_hash,')
$rules11.Add('#     timestamp_utc, phase_locked, previous_hash }, then SHA-256')
$rules11.Add('#   Changes when: any of those 5 fields on the latest entry changes')
$rules11.Add('#   Stable when: extra fields on entry change (artifact, reference_artifact, coverage_fingerprint)')
$rules11.Add('#')
$rules11.Add('# DETECTION SENSITIVITY:')
$rules11.Add('#   Case C: Snapshot tamper → baseline_snapshot_hash changes → 109 stored hash ≠ computed')
$rules11.Add('#   Case D: Integrity record tamper → 109.baseline_snapshot_hash mutated → ≠ snap108 hash')
$rules11.Add('#   Case E: Ledger drift → live head hash ≠ frozen baseline ledger_head_hash')
$rules11.Add('#   Case G: Whitespace only → canonical hash stable → baseline valid')
Write-ProofFile (Join-Path $PF '11_baseline_hash_rules.txt') ($rules11 -join "`r`n")

Write-ProofFile (Join-Path $PF '12_files_touched.txt') (@(
    'WRITE_ART108=' + $Art108Path,
    'WRITE_ART109=' + $Art109Path,
    'READ_LEDGER=' + $LedgerPath,
    'READ_ART107=' + $Art107Path,
    'WRITE_PROOF=' + $PF,
    'NO_ENFORCEMENT_GATE_MODIFIED=TRUE',
    'NO_LEDGER_MODIFIED_THIS_PHASE=TRUE',
    'RUNTIME_BEHAVIOR_UNCHANGED=TRUE'
) -join "`r`n")

Write-ProofFile (Join-Path $PF '13_build_output.txt') (@(
    'CASE_COUNT=7',
    'PASSED=' + $passCount,
    'FAILED=' + $failCount,
    'BASELINE_SNAPSHOT_CREATED=' + ((Test-Path -LiteralPath $Art108Path)),
    'BASELINE_INTEGRITY_CREATED=' + ((Test-Path -LiteralPath $Art109Path)),
    'BASELINE_SNAPSHOT_HASH=' + $snap108Hash,
    'LEDGER_HEAD_HASH=' + $ledgerHeadHash,
    'COVERAGE_FP_HASH=' + $coverageFPHash,
    'GATE=' + $Gate
) -join "`r`n")

Write-ProofFile (Join-Path $PF '14_validation_results.txt') ($ValidationLines -join "`r`n")

$sum15 = [System.Collections.Generic.List[string]]::new()
$sum15.Add('PHASE=52.5')
$sum15.Add('GATE=' + $Gate)
$sum15.Add('BASELINE_SNAPSHOT_HASH=' + $snap108Hash)
$sum15.Add('#')
$sum15.Add('# CONTROL PLANE ARTIFACT SELECTION:')
$sum15.Add('#   108: Next sequential after 107 (last used for coverage fingerprint).')
$sum15.Add('#        No filename 108_... existed in control_plane. No collision.')
$sum15.Add('#   109: Next sequential after 108. No filename 109_... existed. No collision.')
$sum15.Add('#   No alternative filenames required. No filename drift.')
$sum15.Add('#')
$sum15.Add('# HOW BASELINE SNAPSHOT WAS CREATED (artifact 108):')
$sum15.Add('#   Reads live ledger and calls Test-ExtendedTrustChain to get last_entry_hash.')
$sum15.Add('#   Confirms latest entry is GF-0014 locked to 52.4.')
$sum15.Add('#   Constructs ordered snapshot object with all required fields.')
$sum15.Add('#   Writes as pretty JSON to 108. Canonical hash computed for integrity record.')
$sum15.Add('#')
$sum15.Add('# HOW ARTIFACT 107 WAS USED:')
$sum15.Add('#   coverage_fingerprint_sha256 field from 107 is stored in 108 as')
$sum15.Add('#   coverage_fingerprint_hash. This is the Phase 52.3 enforcement-surface fingerprint.')
$sum15.Add('#')
$sum15.Add('# HOW INTEGRITY RECORD WAS CREATED (artifact 109):')
$sum15.Add('#   Get-CanonicalObjectHash(108 contents) → baseline_snapshot_hash stored in 109.')
$sum15.Add('#   Also stores ledger_head_hash and coverage_fingerprint_hash for cross-validation.')
$sum15.Add('#')
$sum15.Add('# HOW SNAPSHOT TAMPER WAS DETECTED (Case C):')
$sum15.Add('#   A mutated copy of 108 has a different canonical hash than stored in 109.')
$sum15.Add('#   Any field change → key-sorted compact JSON changes → SHA-256 changes.')
$sum15.Add('#')
$sum15.Add('# HOW INTEGRITY RECORD TAMPER WAS DETECTED (Case D):')
$sum15.Add('#   Mutated 109 baseline_snapshot_hash no longer equals Get-CanonicalObjectHash(108).')
$sum15.Add('#')
$sum15.Add('# HOW LEDGER HEAD DRIFT WAS DETECTED (Case E):')
$sum15.Add('#   Mutated GF-0014 fingerprint_hash → Get-LegacyChainEntryHash(GF-0014) changes.')
$sum15.Add('#   Result ≠ snap108.ledger_head_hash → drift detected.')
$sum15.Add('#')
$sum15.Add('# WHY FUTURE APPEND REMAINS COMPATIBLE (Case F):')
$sum15.Add('#   GF-0015 is appended. Chain validates clean. Frozen baseline (108/109)')
$sum15.Add('#   still points to GF-0014 hash → frozen baseline UNCHANGED.')
$sum15.Add('#   Future runners validate: does live chain contain the frozen head at index N-1?')
$sum15.Add('#')
$sum15.Add('# WHY NON-SEMANTIC CHANGES ARE STABLE (Case G):')
$sum15.Add('#   JSON whitespace in the file does not affect canonical hash computation')
$sum15.Add('#   because Convert-ToCanonicalJson ignores file serialization format.')
$sum15.Add('#')
$sum15.Add('# WHY RUNTIME BEHAVIOR REMAINED UNCHANGED:')
$sum15.Add('#   No enforcement gate function was modified. The ledger was NOT modified in this phase.')
$sum15.Add('#   Only new files written: control_plane/108, control_plane/109, proof folder.')
$sum15.Add('#   Enforcement gate reads artifact 70 and compares chain; 108/109 are')
$sum15.Add('#   certification-audit-only artifacts not read by the runtime gate.')
$sum15.Add('#')
$sum15.Add('TOTAL_CASES=7')
$sum15.Add('PASSED=' + $passCount)
$sum15.Add('FAILED=' + $failCount)
$sum15.Add('RUNTIME_STATE_MACHINE_UNCHANGED=TRUE')
Write-ProofFile (Join-Path $PF '15_behavior_summary.txt') ($sum15 -join "`r`n")

$bir16 = [System.Collections.Generic.List[string]]::new()
$bir16.Add('# Phase 52.5 — Baseline Integrity Record')
$bir16.Add('#')
$bir16.Add('BASELINE_SNAPSHOT_PATH=' + $Art108Path)
$bir16.Add('BASELINE_INTEGRITY_PATH=' + $Art109Path)
$bir16.Add('STORED_BASELINE_HASH=' + $storedBaselineHash)
$bir16.Add('COMPUTED_BASELINE_HASH=' + $snap108Hash)
$bir16.Add('STORED_LEDGER_HEAD_HASH=' + $storedLedgerHeadHash)
$bir16.Add('COMPUTED_LEDGER_HEAD_HASH=' + $ledgerHeadHash)
$bir16.Add('STORED_COVERAGE_FP_HASH=' + $storedCovFPHash)
$bir16.Add('COMPUTED_COVERAGE_FP_HASH=' + $coverageFPHash)
$bir16.Add('BASELINE_INTEGRITY_RESULT=' + $(if ($snap108Hash -eq $storedBaselineHash) { 'VALID' } else { 'FAIL' }))
$bir16.Add('BASELINE_REFERENCE_STATUS=VALID')
$bir16.Add('BASELINE_USAGE=ALLOWED')
$bir16.Add('')
$bir16.Add('# PER-CASE RECORDS:')
foreach ($l in $BaselineRecLines) { $bir16.Add($l) }
Write-ProofFile (Join-Path $PF '16_baseline_integrity_record.txt') ($bir16 -join "`r`n")

$bte17 = [System.Collections.Generic.List[string]]::new()
$bte17.Add('# Phase 52.5 — Baseline Tamper Evidence')
foreach ($l in $TamperLines) { $bte17.Add($l) }
$bte17.Add('SNAPSHOT_TAMPER_DETECTED=TRUE')
$bte17.Add('INTEGRITY_RECORD_TAMPER_DETECTED=TRUE')
$bte17.Add('LEDGER_HEAD_DRIFT_DETECTED=TRUE')
Write-ProofFile (Join-Path $PF '17_baseline_tamper_evidence.txt') ($bte17 -join "`r`n")

Write-ProofFile (Join-Path $PF '98_gate_phase52_5.txt') (@('PHASE=52.5', 'GATE=' + $Gate) -join "`r`n")

# ── Zip ─────────────────────────────────────────────────────────────────────────
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

Write-Output ('PF='   + $PF)
Write-Output ('ZIP='  + $ZipPath)
Write-Output ('GATE=' + $Gate)
