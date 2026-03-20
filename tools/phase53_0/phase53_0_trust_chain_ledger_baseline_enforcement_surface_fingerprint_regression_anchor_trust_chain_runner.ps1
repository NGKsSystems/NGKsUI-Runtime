Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ((Get-Location).Path -ne $Root) {
    Write-Output 'wrong working directory'
    exit 1
}
Set-Location $Root

function Write-ProofFile {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.Encoding]::UTF8)
}

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
        foreach ($k in $keys) {
            [void]$pairs.Add(('"' + $k + '":' + (Convert-ToCanonicalJson -Value $Value[$k])))
        }
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
    $canonical = Convert-ToCanonicalJson -Value $Obj
    return Get-StringSha256Hex -Text $canonical
}

# Frozen trust-chain hash scheme: exactly these 5 fields
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

    $result = [ordered]@{
        pass = $true
        reason = 'ok'
        entry_count = $Entries.Count
        chain_hashes = @()
        last_entry_hash = ''
    }

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

function Copy-Entries {
    param([object[]]$Entries)
    $copy = [System.Collections.Generic.List[object]]::new()
    foreach ($e in $Entries) {
        $copy.Add(($e | ConvertTo-Json -Depth 20 | ConvertFrom-Json))
    }
    return @($copy)
}

function Test-Phase530Seal {
    param(
        [object[]]$Entries,
        [object]$Artifact110Obj,
        [string]$SealArtifact,
        [string]$ReferenceArtifact
    )

    $r = [ordered]@{
        pass = $true
        reason = 'ok'
        chain_ok = $false
        chain_reason = ''
        seal_entry_id = ''
        seal_index = -1
        expected_artifact110_hash = ''
        expected_coverage_fp = ''
        observed_fingerprint_hash = ''
        observed_coverage_fp = ''
        checks = @()
        chain_last_hash = ''
    }

    $chain = Test-ExtendedTrustChain -Entries $Entries
    $r.chain_ok = [bool]$chain.pass
    $r.chain_reason = [string]$chain.reason
    $r.chain_last_hash = [string]$chain.last_entry_hash
    if (-not $chain.pass) {
        $r.pass = $false
        $r.reason = 'chain_integrity_fail:' + [string]$chain.reason
        return $r
    }

    $sealMatches = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $Entries.Count; $i++) {
        $e = $Entries[$i]
        if ([string]$e.phase_locked -eq '53.0' -and [string]$e.artifact -eq $SealArtifact) {
            [void]$sealMatches.Add([pscustomobject]@{ index = $i; entry = $e })
        }
    }

    if ($sealMatches.Count -eq 0) {
        $r.pass = $false
        $r.reason = 'missing_phase53_0_seal_entry'
        return $r
    }
    if ($sealMatches.Count -gt 1) {
        $r.pass = $false
        $r.reason = 'duplicate_phase53_0_seal_entries:' + $sealMatches.Count
        return $r
    }

    $seal = $sealMatches[0].entry
    $idx = [int]$sealMatches[0].index
    $r.seal_entry_id = [string]$seal.entry_id
    $r.seal_index = $idx

    $expectedFpHash = Get-CanonicalObjectHash -Obj $Artifact110Obj
    $expectedCovFp = [string]$Artifact110Obj.coverage_fingerprint

    $r.expected_artifact110_hash = $expectedFpHash
    $r.expected_coverage_fp = $expectedCovFp
    $r.observed_fingerprint_hash = [string]$seal.fingerprint_hash
    $r.observed_coverage_fp = [string]$seal.coverage_fingerprint

    $checkList = [System.Collections.Generic.List[string]]::new()

    $c1 = ([string]$seal.reference_artifact -eq $ReferenceArtifact)
    [void]$checkList.Add('reference_artifact=' + $c1)

    $c2 = ([string]$seal.coverage_fingerprint -eq $expectedCovFp)
    [void]$checkList.Add('coverage_fingerprint=' + $c2)

    $c3 = ([string]$seal.fingerprint_hash -eq $expectedFpHash)
    [void]$checkList.Add('fingerprint_hash=' + $c3)

    $c4 = ([string]$seal.phase_locked -eq '53.0')
    [void]$checkList.Add('phase_locked=' + $c4)

    $expectedPrev = $null
    if ($idx -eq 0) {
        $expectedPrev = $null
    } else {
        $expectedPrev = Get-LegacyChainEntryHash -Entry $Entries[$idx - 1]
    }
    $c5 = ([string]$seal.previous_hash -eq [string]$expectedPrev)
    [void]$checkList.Add('previous_hash=' + $c5)

    $r.checks = @($checkList)

    if (-not ($c1 -and $c2 -and $c3 -and $c4 -and $c5)) {
        $reasons = [System.Collections.Generic.List[string]]::new()
        if (-not $c1) { [void]$reasons.Add('reference_artifact_mismatch') }
        if (-not $c2) { [void]$reasons.Add('coverage_fingerprint_mismatch') }
        if (-not $c3) { [void]$reasons.Add('fingerprint_hash_mismatch') }
        if (-not $c4) { [void]$reasons.Add('phase_locked_mismatch') }
        if (-not $c5) { [void]$reasons.Add('previous_hash_mismatch') }
        $r.pass = $false
        $r.reason = ($reasons -join ',')
        return $r
    }

    return $r
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunnerPath = Join-Path $Root 'tools\phase53_0\phase53_0_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_runner.ps1'
$LedgerPath = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$Art110Name = '110_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint_regression_anchor.json'
$Art110Path = Join-Path $Root ('control_plane\' + $Art110Name)
$SealArtifact = 'trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_seal'
$PF = Join-Path $Root ('_proof\phase53_0_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_' + $Timestamp)

New-Item -ItemType Directory -Path $PF | Out-Null

foreach ($p in @($LedgerPath, $Art110Path)) {
    if (-not (Test-Path -LiteralPath $p)) {
        throw 'Missing required file: ' + $p
    }
}

$ledgerObj = Get-Content -LiteralPath $LedgerPath -Raw | ConvertFrom-Json
$entries = @($ledgerObj.entries)
$artifact110Obj = Get-Content -LiteralPath $Art110Path -Raw | ConvertFrom-Json

$preChain = Test-ExtendedTrustChain -Entries $entries
if (-not $preChain.pass) {
    throw 'Live ledger integrity invalid before append: ' + [string]$preChain.reason
}

$artifact110CanonicalHash = Get-CanonicalObjectHash -Obj $artifact110Obj
$artifact110CoverageFP = [string]$artifact110Obj.coverage_fingerprint

# Idempotent append logic
$phase53Matches = [System.Collections.Generic.List[object]]::new()
for ($i = 0; $i -lt $entries.Count; $i++) {
    $e = $entries[$i]
    if ([string]$e.phase_locked -eq '53.0' -and [string]$e.artifact -eq $SealArtifact) {
        [void]$phase53Matches.Add([pscustomobject]@{ index = $i; entry = $e })
    }
}

$appendMode = 'appended_new'
$idempotencyStatus = 'not_checked'
$idempotencyReason = 'n/a'
$sealEntryId = ''

if ($phase53Matches.Count -gt 1) {
    throw 'Idempotency failure: multiple phase 53.0 seal entries found count=' + $phase53Matches.Count
}

if ($phase53Matches.Count -eq 1) {
    $appendMode = 'reused_existing'
    $match = $phase53Matches[0]
    $seal = $match.entry
    $idx = [int]$match.index
    $sealEntryId = [string]$seal.entry_id

    $mismatches = [System.Collections.Generic.List[string]]::new()

    if ([string]$seal.reference_artifact -ne $Art110Name) {
        [void]$mismatches.Add('reference_artifact expected=' + $Art110Name + ' actual=' + [string]$seal.reference_artifact)
    }
    if ([string]$seal.coverage_fingerprint -ne $artifact110CoverageFP) {
        [void]$mismatches.Add('coverage_fingerprint expected=' + $artifact110CoverageFP + ' actual=' + [string]$seal.coverage_fingerprint)
    }
    if ([string]$seal.fingerprint_hash -ne $artifact110CanonicalHash) {
        [void]$mismatches.Add('fingerprint_hash expected=' + $artifact110CanonicalHash + ' actual=' + [string]$seal.fingerprint_hash)
    }
    if ([string]$seal.phase_locked -ne '53.0') {
        [void]$mismatches.Add('phase_locked expected=53.0 actual=' + [string]$seal.phase_locked)
    }
    if ($idx -eq 0) {
        [void]$mismatches.Add('phase53_0_entry_cannot_be_first_entry')
    } else {
        $expectedPrev = Get-LegacyChainEntryHash -Entry $entries[$idx - 1]
        if ([string]$seal.previous_hash -ne [string]$expectedPrev) {
            [void]$mismatches.Add('previous_hash expected=' + [string]$expectedPrev + ' actual=' + [string]$seal.previous_hash)
        }
    }

    if ($mismatches.Count -gt 0) {
        throw 'Idempotency mismatch for existing phase 53.0 seal: ' + ($mismatches -join ' ; ')
    }

    $idempotencyStatus = 'reused'
    $idempotencyReason = 'existing_phase53_0_seal_matches_artifact110_exactly'
} else {
    $nextId = 'GF-{0:D4}' -f ($entries.Count + 1)
    $prevHash = [string]$preChain.last_entry_hash

    $newEntry = [ordered]@{
        entry_id = $nextId
        artifact = $SealArtifact
        reference_artifact = $Art110Name
        coverage_fingerprint = $artifact110CoverageFP
        fingerprint_hash = $artifact110CanonicalHash
        timestamp_utc = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        phase_locked = '53.0'
        previous_hash = $prevHash
    }

    $newEntries = [System.Collections.Generic.List[object]]::new()
    foreach ($e in $entries) { [void]$newEntries.Add($e) }
    [void]$newEntries.Add([pscustomobject]$newEntry)

    $postAppendCheck = Test-ExtendedTrustChain -Entries @($newEntries)
    if (-not $postAppendCheck.pass) {
        throw 'Append produced invalid chain: ' + [string]$postAppendCheck.reason
    }

    $ledgerObj.entries = @($newEntries)
    ($ledgerObj | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $LedgerPath -Encoding UTF8 -NoNewline

    $entries = @((Get-Content -LiteralPath $LedgerPath -Raw | ConvertFrom-Json).entries)
    $sealEntryId = $nextId
    $idempotencyStatus = 'appended'
    $idempotencyReason = 'no_existing_phase53_0_seal_found'
}

# Cases A-F
$Validation = [System.Collections.Generic.List[string]]::new()
$TamperEvidence = [System.Collections.Generic.List[string]]::new()
$allPass = $true

function Add-Case {
    param([string]$Id, [string]$Name, [bool]$Pass, [string]$Detail)
    $line = 'CASE ' + $Id + ' ' + $Name + ' | ' + $Detail + ' => ' + $(if ($Pass) { 'PASS' } else { 'FAIL' })
    [void]$Validation.Add($line)
    if (-not $Pass) { $script:allPass = $false }
}

# A. clean trust-chain append -> VALID
$caseA = Test-Phase530Seal -Entries $entries -Artifact110Obj $artifact110Obj -SealArtifact $SealArtifact -ReferenceArtifact $Art110Name
$caseAOk = [bool]$caseA.pass
Add-Case -Id 'A' -Name 'clean_trust_chain_append_valid' -Pass $caseAOk -Detail ('mode=' + $appendMode + ' seal_entry=' + $caseA.seal_entry_id + ' reason=' + $caseA.reason)

# B. historical ledger tamper -> FAIL
$bEntries = Copy-Entries -Entries $entries
$bEntries[0] | Add-Member -MemberType NoteProperty -Name fingerprint_hash -Value ([string]$bEntries[0].fingerprint_hash + 'ff') -Force
$caseB = Test-Phase530Seal -Entries $bEntries -Artifact110Obj $artifact110Obj -SealArtifact $SealArtifact -ReferenceArtifact $Art110Name
$caseBOk = (-not [bool]$caseB.pass)
Add-Case -Id 'B' -Name 'historical_ledger_tamper_detected' -Pass $caseBOk -Detail ('validation_pass=' + $caseB.pass + ' reason=' + $caseB.reason)
[void]$TamperEvidence.Add('CASE B | reason=' + $caseB.reason)

# C. artifact 110 tamper -> FAIL
$cArt = $artifact110Obj | ConvertTo-Json -Depth 20 | ConvertFrom-Json
$cArt | Add-Member -MemberType NoteProperty -Name coverage_fingerprint -Value (([string]$cArt.coverage_fingerprint) + '0') -Force
$caseC = Test-Phase530Seal -Entries $entries -Artifact110Obj $cArt -SealArtifact $SealArtifact -ReferenceArtifact $Art110Name
$caseCOk = (-not [bool]$caseC.pass)
Add-Case -Id 'C' -Name 'artifact110_tamper_detected' -Pass $caseCOk -Detail ('validation_pass=' + $caseC.pass + ' reason=' + $caseC.reason)
[void]$TamperEvidence.Add('CASE C | reason=' + $caseC.reason)

# D. future append remains valid -> VALID
$dEntries = Copy-Entries -Entries $entries
$dChain = Test-ExtendedTrustChain -Entries $dEntries
$dPrev = [string]$dChain.last_entry_hash
$dFuture = [ordered]@{
    entry_id = ('GF-{0:D4}' -f ($dEntries.Count + 1))
    artifact = 'phase53_0_future_simulated_entry'
    reference_artifact = 'N/A'
    coverage_fingerprint = 'simulated_future_coverage_fp'
    fingerprint_hash = 'simulated_future_fingerprint_hash'
    timestamp_utc = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    phase_locked = '53.1_future'
    previous_hash = $dPrev
}
$dEntries = @($dEntries + ([pscustomobject]$dFuture))
$caseD = Test-Phase530Seal -Entries $dEntries -Artifact110Obj $artifact110Obj -SealArtifact $SealArtifact -ReferenceArtifact $Art110Name
$caseDOk = [bool]$caseD.pass
Add-Case -Id 'D' -Name 'future_valid_append_remains_valid' -Pass $caseDOk -Detail ('validation_pass=' + $caseD.pass + ' reason=' + $caseD.reason)

# E. whitespace/non-semantic change -> VALID
$eTmp = Join-Path $PF 'case_e_art110_pretty.json'
($artifact110Obj | ConvertTo-Json -Depth 40) | Set-Content -LiteralPath $eTmp -Encoding UTF8 -NoNewline
$eArtReload = Get-Content -LiteralPath $eTmp -Raw | ConvertFrom-Json
$caseE = Test-Phase530Seal -Entries $entries -Artifact110Obj $eArtReload -SealArtifact $SealArtifact -ReferenceArtifact $Art110Name
$caseEOk = [bool]$caseE.pass
Add-Case -Id 'E' -Name 'non_semantic_serialization_stable' -Pass $caseEOk -Detail ('validation_pass=' + $caseE.pass + ' reason=' + $caseE.reason)

# F. previous_hash break on new entry -> FAIL
$fEntries = Copy-Entries -Entries $entries
$fFuture = [ordered]@{
    entry_id = ('GF-{0:D4}' -f ($fEntries.Count + 1))
    artifact = 'phase53_0_future_bad_prevhash'
    reference_artifact = 'N/A'
    coverage_fingerprint = 'simulated_future_coverage_fp'
    fingerprint_hash = 'simulated_future_fingerprint_hash'
    timestamp_utc = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    phase_locked = '53.1_future'
    previous_hash = '0000000000000000000000000000000000000000000000000000000000000000'
}
$fEntries = @($fEntries + ([pscustomobject]$fFuture))
$caseF = Test-Phase530Seal -Entries $fEntries -Artifact110Obj $artifact110Obj -SealArtifact $SealArtifact -ReferenceArtifact $Art110Name
$caseFOk = (-not [bool]$caseF.pass)
Add-Case -Id 'F' -Name 'previous_hash_break_detected' -Pass $caseFOk -Detail ('validation_pass=' + $caseF.pass + ' reason=' + $caseF.reason)
[void]$TamperEvidence.Add('CASE F | reason=' + $caseF.reason)

$passCount = @($Validation | Where-Object { $_ -match '=> PASS$' }).Count
$failCount = @($Validation | Where-Object { $_ -match '=> FAIL$' }).Count
$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$chainReport = Test-Phase530Seal -Entries $entries -Artifact110Obj $artifact110Obj -SealArtifact $SealArtifact -ReferenceArtifact $Art110Name

# Proof files
Write-ProofFile (Join-Path $PF '01_status.txt') (@(
    'PHASE=53.0',
    'TITLE=Trust-Chain Ledger Baseline Enforcement Surface Fingerprint Regression Anchor Trust-Chain Seal',
    'GATE=' + $Gate,
    'PASS_COUNT=' + $passCount + '/6',
    'FAIL_COUNT=' + $failCount,
    'APPEND_MODE=' + $appendMode,
    'IDEMPOTENCY_STATUS=' + $idempotencyStatus,
    'IDEMPOTENCY_REASON=' + $idempotencyReason,
    'SEAL_ENTRY_ID=' + $sealEntryId,
    'COVERAGE_FINGERPRINT_SHA256=' + $artifact110CoverageFP,
    'ARTIFACT110_CANONICAL_SHA256=' + $artifact110CanonicalHash,
    'REFERENCE_ARTIFACT=' + $Art110Name
) -join "`r`n")

Write-ProofFile (Join-Path $PF '02_head.txt') (@(
    'RUNNER=' + $RunnerPath,
    'LEDGER=' + $LedgerPath,
    'ARTIFACT110=' + $Art110Path,
    'SEAL_ARTIFACT=' + $SealArtifact,
    'PHASE_LOCKED=53.0',
    'CHAIN_HASH_METHOD=legacy_5field_canonical_sha256',
    'ARTIFACT_HASH_METHOD=sorted_key_canonical_json_sha256'
) -join "`r`n")

$def10 = [System.Collections.Generic.List[string]]::new()
[void]$def10.Add('# Phase 53.0 extension definition')
[void]$def10.Add('artifact=' + $SealArtifact)
[void]$def10.Add('reference_artifact=' + $Art110Name)
[void]$def10.Add('coverage_fingerprint=' + $artifact110CoverageFP)
[void]$def10.Add('fingerprint_hash=' + $artifact110CanonicalHash)
[void]$def10.Add('phase_locked=53.0')
[void]$def10.Add('previous_hash=hash_of_prior_GF_entry')
[void]$def10.Add('idempotency=enabled')
Write-ProofFile (Join-Path $PF '10_trust_chain_extension_definition.txt') ($def10 -join "`r`n")

$rec11 = [System.Collections.Generic.List[string]]::new()
[void]$rec11.Add('# chain hash records')
$liveChain = Test-ExtendedTrustChain -Entries $entries
for ($i = 0; $i -lt $entries.Count; $i++) {
    $e = $entries[$i]
    $h = Get-LegacyChainEntryHash -Entry $e
    $prevExpected = if ($i -eq 0) { 'null' } else { [string]$liveChain.chain_hashes[$i - 1] }
    [void]$rec11.Add('index=' + $i + ' entry_id=' + [string]$e.entry_id + ' phase=' + [string]$e.phase_locked + ' previous_hash=' + [string]$e.previous_hash + ' expected_previous_hash=' + $prevExpected + ' entry_hash=' + $h)
}
Write-ProofFile (Join-Path $PF '11_chain_hash_records.txt') ($rec11 -join "`r`n")

Write-ProofFile (Join-Path $PF '12_files_touched.txt') (@(
    'READ=' + $LedgerPath,
    'READ=' + $Art110Path,
    'WRITE=' + $LedgerPath,
    'WRITE_PROOF=' + $PF,
    'NO_FALLBACK=TRUE',
    'NO_REGENERATION=TRUE'
) -join "`r`n")

Write-ProofFile (Join-Path $PF '13_build_output.txt') (@(
    'APPEND_MODE=' + $appendMode,
    'IDEMPOTENCY_STATUS=' + $idempotencyStatus,
    'ENTRY_COUNT=' + $entries.Count,
    'SEAL_ENTRY=' + $sealEntryId,
    'PASS_COUNT=' + $passCount,
    'FAIL_COUNT=' + $failCount,
    'GATE=' + $Gate
) -join "`r`n")

Write-ProofFile (Join-Path $PF '14_validation_results.txt') ($Validation -join "`r`n")

Write-ProofFile (Join-Path $PF '15_behavior_summary.txt') (@(
    'A_clean_append_valid=' + $caseAOk,
    'B_historical_tamper_detected=' + $caseBOk,
    'C_artifact110_tamper_detected=' + $caseCOk,
    'D_future_append_valid=' + $caseDOk,
    'E_non_semantic_change_valid=' + $caseEOk,
    'F_previous_hash_break_detected=' + $caseFOk,
    'CHAIN_INTEGRITY=' + $chainReport.chain_ok,
    'SEAL_VALID=' + $chainReport.pass
) -join "`r`n")

Write-ProofFile (Join-Path $PF '16_chain_integrity_report.txt') (@(
    'chain_ok=' + $chainReport.chain_ok,
    'chain_reason=' + $chainReport.chain_reason,
    'seal_validation_pass=' + $chainReport.pass,
    'seal_validation_reason=' + $chainReport.reason,
    'seal_entry_id=' + $chainReport.seal_entry_id,
    'seal_index=' + $chainReport.seal_index,
    'expected_artifact110_hash=' + $chainReport.expected_artifact110_hash,
    'observed_fingerprint_hash=' + $chainReport.observed_fingerprint_hash,
    'expected_coverage_fp=' + $chainReport.expected_coverage_fp,
    'observed_coverage_fp=' + $chainReport.observed_coverage_fp,
    'checks=' + ($chainReport.checks -join ',')
) -join "`r`n")

Write-ProofFile (Join-Path $PF '17_tamper_detection_evidence.txt') ($TamperEvidence -join "`r`n")

Write-ProofFile (Join-Path $PF '98_gate_phase53_0.txt') (@(
    'GATE=' + $Gate,
    'PHASE=53.0',
    'COVERAGE_FINGERPRINT_SHA256=' + $artifact110CoverageFP,
    'FINGERPRINT_MATCH_STATUS=' + $(if ($chainReport.pass) { 'MATCH' } else { 'MISMATCH' }),
    'REGRESSION_DETECTED=' + $(if ($allPass) { 'false' } else { 'true' })
) -join "`r`n")

# Zip proof
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
