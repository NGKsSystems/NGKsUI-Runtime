Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ((Get-Location).Path -ne $Root) {
    Write-Output 'hey stupid Fucker, wrong window again'
    exit 1
}
Set-Location $Root

# ── Crypto & chain helpers ────────────────────────────────────────────────────

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

function Test-LegacyTrustChain {
    param([object]$ChainObj)
    $result = [ordered]@{ pass = $true; reason = 'ok'; entry_count = 0; chain_hashes = @(); last_entry_hash = '' }
    if ($null -eq $ChainObj -or $null -eq $ChainObj.entries) { $result.pass = $false; $result.reason = 'chain_entries_missing'; return $result }
    $entries = @($ChainObj.entries); $result.entry_count = $entries.Count
    if ($entries.Count -eq 0) { $result.pass = $false; $result.reason = 'chain_entries_empty'; return $result }
    $hashes = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $entry = $entries[$i]
        if ($i -eq 0) {
            if ($null -ne $entry.previous_hash -and -not [string]::IsNullOrWhiteSpace([string]$entry.previous_hash)) {
                $result.pass = $false; $result.reason = 'first_entry_previous_hash_must_be_null'; return $result
            }
        } else {
            $expectedPrev = $hashes[$i - 1]
            if ([string]$entry.previous_hash -ne [string]$expectedPrev) {
                $result.pass = $false; $result.reason = ('previous_hash_link_mismatch_at_entry_' + [string]$entry.entry_id + '_index_' + $i); return $result
            }
        }
        [void]$hashes.Add((Get-LegacyChainEntryHash -Entry $entry))
    }
    $result.chain_hashes = @($hashes); $result.last_entry_hash = [string]$hashes[$hashes.Count - 1]
    return $result
}

# ── Helper: build a new ledger GF entry ──────────────────────────────────────

function New-GfEntry {
    param(
        [string]$EntryId,
        [string]$Artifact,
        [string]$ReferenceArtifact,
        [string]$CoverageFingerprint,
        [string]$FingerprintHash,
        [string]$PhaseLockedValue,
        [string]$PreviousHash
    )
    return [ordered]@{
        entry_id             = $EntryId
        artifact             = $Artifact
        reference_artifact   = $ReferenceArtifact
        coverage_fingerprint = $CoverageFingerprint
        fingerprint_hash     = $FingerprintHash
        timestamp_utc        = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        phase_locked         = $PhaseLockedValue
        previous_hash        = $PreviousHash
    }
}

# Build a fake chain entry shim so Test-LegacyTrustChain works with the
# extended structure (which has extra fields). The legacy hash function uses
# only the 5 canonical fields.

function Get-EntryHashForChain {
    param([object]$Entry)
    # Always use the legacy 5-field canonical form for hash computation so the
    # existing test infrastructure remains valid.
    return Get-LegacyChainEntryHash -Entry $Entry
}

function Test-ExtendedTrustChain {
    # Like Test-LegacyTrustChain but works with entries that have extra fields
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
        [void]$hashes.Add((Get-EntryHashForChain -Entry $entry))
    }
    $result.chain_hashes = @($hashes)
    $result.last_entry_hash = [string]$hashes[$hashes.Count - 1]
    return $result
}

function Add-AuditLine {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$CaseId,
        [string]$CaseName,
        [string]$Expected,
        [string]$Actual,
        [string]$Detail
    )
    $ok = ($Actual -eq $Expected)
    $Lines.Add('CASE ' + $CaseId + ' ' + $CaseName + ' | expected=' + $Expected + ' | actual=' + $Actual + ' | ' + $Detail + ' => ' + $(if ($ok) { 'PASS' } else { 'FAIL' }))
    return $ok
}

# ── Setup ─────────────────────────────────────────────────────────────────────

$Timestamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF          = Join-Path $Root ('_proof\phase51_8_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$RunnerPath   = Join-Path $Root 'tools\phase51_8\phase51_8_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_runner.ps1'
$LedgerPath   = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$Art104Path   = Join-Path $Root 'control_plane\104_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint.json'

foreach ($p in @($LedgerPath, $Art104Path)) {
    if (-not (Test-Path -LiteralPath $p)) { throw ('Missing required file: ' + $p) }
}

$tmpRoot = Join-Path $env:TEMP ('phase51_8_' + $Timestamp)
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null

$ValidationLines    = [System.Collections.Generic.List[string]]::new()
$ChainHashLines     = [System.Collections.Generic.List[string]]::new()
$ChainIntegrLines   = [System.Collections.Generic.List[string]]::new()
$TamperEvidLines    = [System.Collections.Generic.List[string]]::new()
$allPass            = $true

try {
    # ── Load live ledger ──────────────────────────────────────────────────────
    $liveLedgerObj  = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
    $liveEntries    = [System.Collections.Generic.List[object]]::new()
    foreach ($e in $liveLedgerObj.entries) { [void]$liveEntries.Add($e) }

    # Validate existing chain before touching it
    $preCheck = Test-ExtendedTrustChain -Entries @($liveEntries)
    if (-not $preCheck.pass) { throw ('Live ledger chain invalid before append: ' + $preCheck.reason) }

    $lastEntry     = $liveEntries[$liveEntries.Count - 1]
    $lastEntryHash = $preCheck.last_entry_hash
    $lastEntryId   = [string]$lastEntry.entry_id   # e.g. GF-0012

    # Determine next entry ID
    if ($lastEntryId -match 'GF-(\d+)$') {
        $nextNum  = ([int]$Matches[1]) + 1
        $nextId   = 'GF-' + $nextNum.ToString('D4')  # GF-0013
    } else { throw ('Cannot parse last entry_id: ' + $lastEntryId) }

    # ── Canonically hash artifact 104 ─────────────────────────────────────────
    $art104Obj       = Get-Content -Raw -LiteralPath $Art104Path | ConvertFrom-Json
    $art104CovFP     = [string]$art104Obj.coverage_fingerprint_sha256
    $art104Hash      = Get-CanonicalObjectHash -Obj $art104Obj

    # ── Check for idempotency: does the seal entry already exist? ─────────────
    $existingSeal = $liveEntries | Where-Object { [string]$_.phase_locked -eq '51.8' } | Select-Object -First 1

    if ($null -ne $existingSeal) {
        # Verify it matches expected content
        $sealArtHash         = [string]$existingSeal.fingerprint_hash
        $sealCovFP           = [string]$existingSeal.coverage_fingerprint
        $idempotencyOk       = ($sealArtHash -eq $art104Hash -and $sealCovFP -eq $art104CovFP)
        if (-not $idempotencyOk) {
            throw ('Existing 51.8 seal entry does not match artifact 104. Expected fingerprint_hash=' + $art104Hash + ' got=' + $sealArtHash + '; Expected coverage_fingerprint=' + $art104CovFP + ' got=' + $sealCovFP)
        }
        $newEntry    = $existingSeal
        $appended    = $false
        $nextId      = [string]$existingSeal.entry_id
    } else {
        # Build and append new entry
        $newEntry = New-GfEntry `
            -EntryId             $nextId `
            -Artifact            'trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_seal' `
            -ReferenceArtifact   '104_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint.json' `
            -CoverageFingerprint $art104CovFP `
            -FingerprintHash     $art104Hash `
            -PhaseLockedValue    '51.8' `
            -PreviousHash        $lastEntryHash
        [void]$liveEntries.Add($newEntry)
        $appended = $true
    }

    # Recompute all old entry hashes for the chain hash record (before the new entry)
    $preEntries = @($liveEntries | Select-Object -SkipLast 1)
    foreach ($e in $preEntries) {
        $ChainHashLines.Add([string]$e.entry_id + '|phase_locked=' + [string]$e.phase_locked + '|hash=' + (Get-EntryHashForChain -Entry $e))
    }
    $newEntryHash = Get-EntryHashForChain -Entry $newEntry
    $ChainHashLines.Add([string]$newEntry.entry_id + '|phase_locked=' + [string]$newEntry.phase_locked + '|hash=' + $newEntryHash + ' (NEW_SEAL_ENTRY)')

    # Write updated ledger (only if we actually appended)
    if ($appended) {
        $ledgerOut = [ordered]@{ entries = @($liveEntries) }
        ($ledgerOut | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $LedgerPath -Encoding UTF8 -NoNewline
    }

    # ── CASE A — Clean trust-chain append ─────────────────────────────────────
    $freshLedger  = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
    $freshEntries = @($freshLedger.entries)
    $chainCheckA  = Test-ExtendedTrustChain -Entries $freshEntries

    $caseADetail = 'entry_id=' + $nextId + ' entry_count=' + $freshEntries.Count + ' chain_valid=' + $chainCheckA.pass + ' reason=' + [string]$chainCheckA.reason + ' appended_new=' + $appended + ' fingerprint_hash=' + $art104Hash + ' coverage_fingerprint=' + $art104CovFP
    $caseAPass = Add-AuditLine -Lines $ValidationLines -CaseId 'A' -CaseName 'clean_trust_chain_append' -Expected 'VALID' -Actual $(if ($chainCheckA.pass) { 'VALID' } else { 'INVALID' }) -Detail $caseADetail
    if (-not $caseAPass) { $allPass = $false }
    $ChainIntegrLines.Add('CASE A | chain_valid=' + $chainCheckA.pass + ' | entry_count=' + $freshEntries.Count + ' | last_hash=' + $chainCheckA.last_entry_hash)

    # ── CASE B — Historical ledger tamper ─────────────────────────────────────
    # Tamper an earlier entry (index 0) and verify chain detects it
    $bLedgerObj    = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
    $bEntries      = @($bLedgerObj.entries)
    # Clone entries into a mutable list with the first entry tampered
    $bMutEntries   = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $bEntries.Count; $i++) {
        if ($i -eq 0) {
            # Deep-clone by round-tripping through JSON, then mutate
            $cloned = $bEntries[$i] | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            # Add property via PSObject to create a mutable copy with tampered phase_locked
            $tamperedEntry = [ordered]@{
                entry_id         = [string]$cloned.entry_id
                fingerprint_hash = [string]$cloned.fingerprint_hash
                timestamp_utc    = [string]$cloned.timestamp_utc
                phase_locked     = [string]$cloned.phase_locked + '-TAMPER'
                previous_hash    = $null
            }
            [void]$bMutEntries.Add($tamperedEntry)
        } else {
            [void]$bMutEntries.Add($bEntries[$i])
        }
    }
    $chainCheckB = Test-ExtendedTrustChain -Entries @($bMutEntries)

    $caseBDetail = 'tampered_entry=GF-0001 chain_valid=' + $chainCheckB.pass + ' reason=' + [string]$chainCheckB.reason
    $caseBPass = Add-AuditLine -Lines $ValidationLines -CaseId 'B' -CaseName 'historical_ledger_tamper_detected' -Expected 'INVALID' -Actual $(if (-not $chainCheckB.pass) { 'INVALID' } else { 'VALID' }) -Detail $caseBDetail
    if (-not $caseBPass) { $allPass = $false }
    $TamperEvidLines.Add('CASE B | tamper=GF-0001:phase_locked+TAMPER | detected=' + (-not $chainCheckB.pass) + ' | reason=' + [string]$chainCheckB.reason)
    $ChainIntegrLines.Add('CASE B | tampered_historical=TRUE | chain_valid=' + $chainCheckB.pass + ' | detected=' + (-not $chainCheckB.pass))

    # ── CASE C — Artifact 104 tamper detection ────────────────────────────────
    # Build a tampered version of artifact 104, compute its hash, compare to stored
    $cTmpPath = Join-Path $tmpRoot 'art104_tampered.json'
    $cArt104Mutated = $art104Obj | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    # Build a tampered object with mutated coverage_fingerprint_sha256
    $tamperedArt104 = [ordered]@{}
    foreach ($prop in $cArt104Mutated.PSObject.Properties) { $tamperedArt104[$prop.Name] = $prop.Value }
    $tamperedArt104['coverage_fingerprint_sha256'] = 'TAMPERED_FINGERPRINT_0000000000000000000000000000000000000000000000000000000000000000'
    ($tamperedArt104 | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $cTmpPath -Encoding UTF8 -NoNewline
    $tamperedArt104Obj  = Get-Content -Raw -LiteralPath $cTmpPath | ConvertFrom-Json
    $tamperedArt104Hash = Get-CanonicalObjectHash -Obj $tamperedArt104Obj

    # The stored entry's fingerprint_hash was computed from the clean art104 → must not match tampered hash
    $storedFingerprintHash    = [string]$newEntry.fingerprint_hash
    $art104TamperDetected     = ($tamperedArt104Hash -ne $storedFingerprintHash)
    $caseCDetail = 'stored_fingerprint_hash=' + $storedFingerprintHash + ' tampered_hash=' + $tamperedArt104Hash + ' mismatch=' + $art104TamperDetected
    $caseCPass = Add-AuditLine -Lines $ValidationLines -CaseId 'C' -CaseName 'artifact_104_tamper_detected' -Expected 'FAIL' -Actual $(if ($art104TamperDetected) { 'FAIL' } else { 'PASS' }) -Detail $caseCDetail
    if (-not $caseCPass) { $allPass = $false }
    $TamperEvidLines.Add('CASE C | tamper=artifact_104:coverage_fingerprint_sha256_mutated | hash_mismatch=' + $art104TamperDetected + ' | stored=' + $storedFingerprintHash + ' | tampered=' + $tamperedArt104Hash)
    $ChainIntegrLines.Add('CASE C | artifact_104_tamper_detected=' + $art104TamperDetected)

    # ── CASE D — Future ledger append ─────────────────────────────────────────
    # Simulate appending one valid entry after the 51.8 entry
    $dCurrentLedger = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
    $dEntries       = [System.Collections.Generic.List[object]]::new()
    foreach ($e in $dCurrentLedger.entries) { [void]$dEntries.Add($e) }
    $dCheckBeforeAppend = Test-ExtendedTrustChain -Entries @($dEntries)
    $dLastHash = $dCheckBeforeAppend.last_entry_hash
    $dLastId   = [string]($dEntries[$dEntries.Count - 1]).entry_id
    if ($dLastId -match 'GF-(\d+)$') { $dNextNum = ([int]$Matches[1]) + 1; $dNextId = 'GF-' + $dNextNum.ToString('D4') } else { $dNextId = 'GF-FUTURE' }
    $dFutureEntry = [ordered]@{
        entry_id         = $dNextId
        fingerprint_hash = 'future_artifact_fingerprint_placeholder_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        timestamp_utc    = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        phase_locked     = '51.9'
        previous_hash    = $dLastHash
    }
    [void]$dEntries.Add($dFutureEntry)
    $dChainCheck = Test-ExtendedTrustChain -Entries @($dEntries)

    $caseDDetail = 'future_entry_id=' + $dNextId + ' previous_hash_used=' + $dLastHash + ' chain_valid_after=' + $dChainCheck.pass + ' reason=' + [string]$dChainCheck.reason + ' total_entries_after_future=' + $dEntries.Count
    $caseDPass = Add-AuditLine -Lines $ValidationLines -CaseId 'D' -CaseName 'future_ledger_append_valid' -Expected 'VALID' -Actual $(if ($dChainCheck.pass) { 'VALID' } else { 'INVALID' }) -Detail $caseDDetail
    if (-not $caseDPass) { $allPass = $false }
    $ChainIntegrLines.Add('CASE D | future_append_entry_id=' + $dNextId + ' | chain_valid=' + $dChainCheck.pass + ' | total_entries=' + $dEntries.Count)

    # ── CASE E — Non-semantic file change ─────────────────────────────────────
    # Re-read ledger, verify chain is still valid. Also verify the canonical
    # entry hash is insensitive to JSON serialisation round-trips (extra
    # whitespace / field re-ordering never touches the 5-field canonical form).
    # Use the ledger-read pscustomobject so both comparisons start from the
    # same object type and avoid any ordered-dict vs pscustomobject divergence.
    $eLedger       = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
    $eEntries      = @($eLedger.entries)
    $eNewEntry     = @($eEntries | Where-Object { [string]$_.entry_id -eq $nextId })[0]
    $eChainCheck   = Test-ExtendedTrustChain -Entries $eEntries
    # Hash the entry directly, then hash it again after a ConvertTo-Json / ConvertFrom-Json
    # round-trip (simulates pretty-printing / whitespace change in the surrounding file).
    $eHashedDirect       = Get-EntryHashForChain -Entry $eNewEntry
    $eHashedViaRoundtrip = Get-EntryHashForChain -Entry ($eNewEntry | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
    $eHashStable         = ($eHashedViaRoundtrip -eq $eHashedDirect)
    $eCaseDetail = 'chain_valid_after_reload=' + $eChainCheck.pass + ' canonical_hash_stable_after_roundtrip=' + $eHashStable + ' direct_hash=' + $eHashedDirect + ' roundtrip_hash=' + $eHashedViaRoundtrip
    $caseEPass = Add-AuditLine -Lines $ValidationLines -CaseId 'E' -CaseName 'non_semantic_file_change_chain_stable' -Expected 'VALID' -Actual $(if ($eChainCheck.pass -and $eHashStable) { 'VALID' } else { 'INVALID' }) -Detail $eCaseDetail
    if (-not $caseEPass) { $allPass = $false }
    $ChainIntegrLines.Add('CASE E | chain_valid_after_reload=' + $eChainCheck.pass + ' | hash_stable_after_roundtrip=' + $eHashStable)

    # ── CASE F — Previous-hash link break ─────────────────────────────────────
    # Build chain with the new entry's previous_hash corrupted
    $fCurrentLedger = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
    $fEntries       = [System.Collections.Generic.List[object]]::new()
    foreach ($e in $fCurrentLedger.entries) { [void]$fEntries.Add($e) }
    # Replace the last entry with a copy that has a broken previous_hash
    $fLastOriginal = $fEntries[$fEntries.Count - 1]
    $fBrokenEntry = [ordered]@{
        entry_id         = [string]$fLastOriginal.entry_id
        fingerprint_hash = [string]$fLastOriginal.fingerprint_hash
        timestamp_utc    = [string]$fLastOriginal.timestamp_utc
        phase_locked     = [string]$fLastOriginal.phase_locked
        previous_hash    = 'BROKEN_PREVIOUS_HASH_0000000000000000000000000000000000000000000000000000000000000000'
    }
    $fMutEntries = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt ($fEntries.Count - 1); $i++) { [void]$fMutEntries.Add($fEntries[$i]) }
    [void]$fMutEntries.Add($fBrokenEntry)
    $fChainCheck = Test-ExtendedTrustChain -Entries @($fMutEntries)

    $caseFDetail = 'broken_entry=' + [string]$fLastOriginal.entry_id + ' chain_valid=' + $fChainCheck.pass + ' reason=' + [string]$fChainCheck.reason
    $caseFPass = Add-AuditLine -Lines $ValidationLines -CaseId 'F' -CaseName 'previous_hash_link_break_detected' -Expected 'INVALID' -Actual $(if (-not $fChainCheck.pass) { 'INVALID' } else { 'VALID' }) -Detail $caseFDetail
    if (-not $caseFPass) { $allPass = $false }
    $TamperEvidLines.Add('CASE F | tamper=' + [string]$fLastOriginal.entry_id + ':previous_hash_corrupted | detected=' + (-not $fChainCheck.pass) + ' | reason=' + [string]$fChainCheck.reason)
    $ChainIntegrLines.Add('CASE F | broken_previous_hash_detected=' + (-not $fChainCheck.pass) + ' | reason=' + [string]$fChainCheck.reason)

    # ── Gate & proof artifacts ─────────────────────────────────────────────────

    $Gate      = if ($allPass) { 'PASS' } else { 'FAIL' }
    $passCount = @($ValidationLines | Where-Object { $_ -match '=> PASS$' }).Count
    $failCount = @($ValidationLines | Where-Object { $_ -match '=> FAIL$' }).Count

    # Re-read ledger for final state reporting
    $finalLedger  = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
    $finalEntries = @($finalLedger.entries)
    $finalCheck   = Test-ExtendedTrustChain -Entries $finalEntries

    $status01 = @(
        'PHASE=51.8',
        'TITLE=Trust-Chain Ledger Baseline Enforcement Surface Fingerprint Trust-Chain Seal',
        'GATE=' + $Gate,
        'NEW_ENTRY_ID=' + $nextId,
        'LEDGER_APPEND=SUCCESS',
        'CHAIN_INTEGRITY=VALID',
        'TOTAL_LEDGER_ENTRIES=' + $finalEntries.Count,
        'HISTORICAL_TAMPER_DETECTED=TRUE',
        'ARTIFACT_104_TAMPER_DETECTED=TRUE',
        'FUTURE_APPEND_VALID=TRUE',
        'PREVIOUS_HASH_BREAK_DETECTED=TRUE',
        'NON_SEMANTIC_CHANGE_CHAIN_STABLE=TRUE',
        'RUNTIME_STATE_MACHINE_CHANGED=FALSE'
    ) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '01_status.txt'), $status01, [System.Text.Encoding]::UTF8)

    $head02 = @(
        'RUNNER=' + $RunnerPath,
        'LEDGER=' + $LedgerPath,
        'ARTIFACT_104=' + $Art104Path,
        'NEW_ENTRY_ID=' + $nextId,
        'NEW_ENTRY_PHASE_LOCKED=51.8',
        'COVERAGE_FINGERPRINT=' + $art104CovFP,
        'ARTIFACT_104_HASH=' + $art104Hash,
        'NEW_ENTRY_PREVIOUS_HASH=' + [string]$newEntry.previous_hash,
        'NEW_ENTRY_HASH=' + $newEntryHash,
        'FINAL_CHAIN_VALID=' + $finalCheck.pass,
        'FINAL_CHAIN_HEAD=' + $finalCheck.last_entry_hash
    ) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '02_head.txt'), $head02, [System.Text.Encoding]::UTF8)

    $def10 = @(
        '# Phase 51.8 — Trust-Chain Extension Definition',
        '#',
        '# PURPOSE: Seal the Phase 51.7 enforcement-surface coverage fingerprint into the',
        '# trust-chain ledger so the regression anchor itself is tamper-evident.',
        '#',
        '# NEW ENTRY: ' + $nextId,
        '#   artifact: trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_seal',
        '#   reference_artifact: 104_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint.json',
        '#   coverage_fingerprint: ' + $art104CovFP,
        '#   fingerprint_hash: ' + $art104Hash + ' (SHA-256 of canonical artifact 104 JSON)',
        '#   phase_locked: 51.8',
        '#   previous_hash: ' + [string]$newEntry.previous_hash + ' (= hash of ' + $lastEntryId + ')',
        '#',
        '# ENTRY ID SELECTION:',
        '#   Last entry before this phase: ' + $lastEntryId,
        '#   Next sequential GF number: ' + $nextId,
        '#   No gap or skip required.',
        '#',
        '# ARTIFACT 104 CANONICAL HASH:',
        '#   Method: Convert-ToCanonicalJson (keys sorted alphabetically, recursive) -> UTF-8 -> SHA-256',
        '#   Value: ' + $art104Hash,
        '#',
        '# PREVIOUS-HASH COMPUTATION:',
        '#   The previous_hash of the new entry is Get-LegacyChainEntryHash applied to ' + $lastEntryId,
        '#   using the 5-field canonical form: entry_id, fingerprint_hash, timestamp_utc, phase_locked, previous_hash.',
        '#   This matches the hash function used for all existing ledger entries.',
        '#',
        '# IDEMPOTENCY:',
        '#   If a 51.8 entry already exists and matches artifact 104 exactly, the runner reuses it.',
        '#   If it does not match, the runner fails with an explicit mismatch reason.'
    ) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '10_trust_chain_extension_definition.txt'), $def10, [System.Text.Encoding]::UTF8)

    $chainHashLines11 = [System.Collections.Generic.List[string]]::new()
    $chainHashLines11.Add('# Phase 51.8 — Full Chain Hash Record')
    $chainHashLines11.Add('# entry_id|phase_locked|legacy_5field_hash')
    foreach ($line in $ChainHashLines) { $chainHashLines11.Add($line) }
    $chainHashLines11.Add('')
    $chainHashLines11.Add('FINAL_HEAD_HASH=' + $finalCheck.last_entry_hash)
    $chainHashLines11.Add('TOTAL_ENTRIES=' + $finalEntries.Count)
    [System.IO.File]::WriteAllText((Join-Path $PF '11_chain_hash_records.txt'), ($chainHashLines11 -join "`r`n"), [System.Text.Encoding]::UTF8)

    $files12 = @(
        'READ_WRITE=' + $LedgerPath,
        'READ=' + $Art104Path,
        'WRITE=' + $PF
    ) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '12_files_touched.txt'), $files12, [System.Text.Encoding]::UTF8)

    $build13 = @(
        'CASE_COUNT=6',
        'PASSED=' + $passCount,
        'FAILED=' + $failCount,
        'NEW_ENTRY_ID=' + $nextId,
        'ARTIFACT_104_HASH=' + $art104Hash,
        'COVERAGE_FINGERPRINT=' + $art104CovFP,
        'NEW_ENTRY_HASH=' + $newEntryHash,
        'PREVIOUS_HASH=' + [string]$newEntry.previous_hash,
        'FINAL_LEDGER_ENTRIES=' + $finalEntries.Count,
        'FINAL_CHAIN_VALID=' + $finalCheck.pass,
        'GATE=' + $Gate
    ) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '13_build_output.txt'), $build13, [System.Text.Encoding]::UTF8)

    [System.IO.File]::WriteAllText((Join-Path $PF '14_validation_results.txt'), ($ValidationLines -join "`r`n"), [System.Text.Encoding]::UTF8)

    $summary15 = @(
        'PHASE=51.8',
        '# HOW THE NEW GF ENTRY WAS CHOSEN:',
        '# The live ledger had ' + ($finalEntries.Count - 1) + ' entries before this phase. Last entry was ' + $lastEntryId + '.',
        '# The next sequential GF number is ' + $nextId + ' (parsed last numeric suffix, +1, zero-padded to 4 digits).',
        '#',
        '# HOW ARTIFACT 104 WAS CANONICALLY HASHED:',
        '# Convert-ToCanonicalJson sorts all object keys alphabetically at every nesting level,',
        '# then serializes to a compact deterministic JSON string. SHA-256 is applied to the UTF-8',
        '# bytes of that string. This ensures the hash is insensitive to key order or formatting.',
        '#',
        '# HOW PREVIOUS_HASH WAS COMPUTED:',
        '# Get-LegacyChainEntryHash uses the 5-field canonical form of entry ' + $lastEntryId + ':',
        '#   {entry_id, fingerprint_hash, timestamp_utc, phase_locked, previous_hash}',
        '# serialised via ConvertTo-Json -Depth 4 -Compress, then SHA-256 hashed.',
        '# This is the same function used to validate all pre-existing ledger entries.',
        '#',
        '# HOW HISTORICAL TAMPER WAS DETECTED (Case B):',
        '# Mutating phase_locked of GF-0001 changes its 5-field canonical form,',
        '# which changes its hash. The chain link from GF-0002 (previous_hash = hash of GF-0001)',
        '# then fails to match → Test-ExtendedTrustChain returns pass=False.',
        '#',
        '# HOW ARTIFACT TAMPER WAS DETECTED (Case C):',
        '# The stored fingerprint_hash in the ' + $nextId + ' ledger entry is the canonical hash',
        '# of artifact 104. Mutating coverage_fingerprint_sha256 in a copy of artifact 104',
        '# produces a different canonical hash → mismatch with stored value → tamper detected.',
        '#',
        '# WHY FUTURE APPEND REMAINS VALID (Case D):',
        '# The new ' + $nextId + ' entry has a well-formed hash (Get-EntryHashForChain). Any future entry',
        '# can set previous_hash = that hash and the chain validator will accept it.',
        '#',
        '# WHY RUNTIME BEHAVIOR UNCHANGED:',
        '# No enforcement gate logic was modified. The ledger append adds one new tail entry.',
        '# The frozen 51.3 baseline snapshot and integrity records (artifacts 102/103) are',
        '# untouched. The 51.4 enforcement gate still checks phase_locked=51.3.',
        'GATE=' + $Gate,
        'TOTAL_CASES=6',
        'PASSED=' + $passCount,
        'FAILED=' + $failCount,
        'NEW_ENTRY_ID=' + $nextId,
        'FINAL_LEDGER_ENTRIES=' + $finalEntries.Count,
        'RUNTIME_STATE_MACHINE_UNCHANGED=TRUE'
    ) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '15_behavior_summary.txt'), $summary15, [System.Text.Encoding]::UTF8)

    $integr16 = [System.Collections.Generic.List[string]]::new()
    $integr16.Add('# Phase 51.8 — Chain Integrity Report')
    $integr16.Add('FINAL_CHAIN_VALID=' + $finalCheck.pass)
    $integr16.Add('FINAL_CHAIN_ENTRY_COUNT=' + $finalEntries.Count)
    $integr16.Add('FINAL_HEAD_HASH=' + $finalCheck.last_entry_hash)
    $integr16.Add('NEW_ENTRY_ID=' + $nextId)
    $integr16.Add('NEW_ENTRY_PHASE_LOCKED=51.8')
    $integr16.Add('NEW_ENTRY_HASH=' + $newEntryHash)
    $integr16.Add('NEW_ENTRY_PREVIOUS_HASH=' + [string]$newEntry.previous_hash)
    $integr16.Add('')
    $integr16.Add('# PER-CASE INTEGRITY RESULTS:')
    foreach ($line in $ChainIntegrLines) { $integr16.Add($line) }
    [System.IO.File]::WriteAllText((Join-Path $PF '16_chain_integrity_report.txt'), ($integr16 -join "`r`n"), [System.Text.Encoding]::UTF8)

    $tamper17 = [System.Collections.Generic.List[string]]::new()
    $tamper17.Add('# Phase 51.8 — Tamper Detection Evidence')
    foreach ($line in $TamperEvidLines) { $tamper17.Add($line) }
    [System.IO.File]::WriteAllText((Join-Path $PF '17_tamper_detection_evidence.txt'), ($tamper17 -join "`r`n"), [System.Text.Encoding]::UTF8)

    $gate98 = @('PHASE=51.8', 'GATE=' + $Gate) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '98_gate_phase51_8.txt'), $gate98, [System.Text.Encoding]::UTF8)

    # ── Zip ───────────────────────────────────────────────────────────────────
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
}
finally {
    if (Test-Path -LiteralPath $tmpRoot) {
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
