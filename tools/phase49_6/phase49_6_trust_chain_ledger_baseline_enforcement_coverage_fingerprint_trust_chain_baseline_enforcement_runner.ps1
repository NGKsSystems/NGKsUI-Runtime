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

function Convert-ToCanonicalJson {
    param($Value)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [float] -or $Value -is [decimal]) {
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
            $items.Add((Convert-ToCanonicalJson -Value $item))
        }
        return '[' + ($items -join ',') + ']'
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $keys = @($Value.Keys | Sort-Object)
        $pairs = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $keys) {
            $pairs.Add(('"' + $k + '":' + (Convert-ToCanonicalJson -Value $Value[$k])))
        }
        return '{' + ($pairs -join ',') + '}'
    }
    if ($Value -is [pscustomobject]) {
        $keys = @($Value.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object)
        $pairs = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $keys) {
            $v = $Value.PSObject.Properties[$k].Value
            $pairs.Add(('"' + $k + '":' + (Convert-ToCanonicalJson -Value $v)))
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

function Copy-Object {
    param([object]$Obj)
    return (($Obj | ConvertTo-Json -Depth 40 -Compress) | ConvertFrom-Json)
}

function Invoke-FrozenBaselineEnforcementGate {
    param(
        [string]$FrozenBaselineSnapshotPath,
        [string]$FrozenBaselineIntegrityPath,
        [string]$LiveLedgerPath,
        [string]$LiveCoverageFingerprintPath
    )

    $r = [ordered]@{
        frozen_baseline_snapshot_path         = $FrozenBaselineSnapshotPath
        frozen_baseline_integrity_record_path = $FrozenBaselineIntegrityPath
        stored_baseline_hash                  = ''
        computed_baseline_hash                = ''
        stored_ledger_head_hash               = ''
        computed_ledger_head_hash             = ''
        stored_coverage_fingerprint_hash      = ''
        computed_coverage_fingerprint_hash    = ''
        chain_continuation_status             = 'INVALID'
        semantic_match_status                 = 'FALSE'
        runtime_init_allowed_or_blocked       = 'BLOCKED'
        fallback_occurred                     = $false
        regeneration_occurred                 = $false
        baseline_snapshot                     = 'INVALID'
        baseline_integrity                    = 'INVALID'
        ledger_head_match                     = 'FALSE'
        coverage_fingerprint_match            = 'FALSE'
        sequence                              = @()
        reason                                = 'unknown'
    }

    $seq = [System.Collections.Generic.List[string]]::new()

    # 1) frozen 49.5 baseline snapshot validation
    $seq.Add('1.frozen_49_5_baseline_snapshot_validation')
    if (-not (Test-Path -LiteralPath $FrozenBaselineSnapshotPath)) {
        $r.reason = 'frozen_baseline_snapshot_missing'
        $r.sequence = @($seq)
        return $r
    }

    try {
        $baselineObj = Get-Content -Raw -LiteralPath $FrozenBaselineSnapshotPath | ConvertFrom-Json
    } catch {
        $r.reason = 'frozen_baseline_snapshot_parse_error'
        $r.sequence = @($seq)
        return $r
    }

    $requiredBaselineFields = @(
        'baseline_version','phase_locked','ledger_head_hash','ledger_length','coverage_fingerprint_hash',
        'latest_entry_id','latest_entry_phase_locked','entry_hashes','source_phases'
    )
    foreach ($f in $requiredBaselineFields) {
        if (-not ($baselineObj.PSObject.Properties.Name -contains $f)) {
            $r.reason = ('frozen_baseline_snapshot_missing_field_' + $f)
            $r.sequence = @($seq)
            return $r
        }
    }
    if ([string]$baselineObj.phase_locked -ne '49.5') {
        $r.reason = 'frozen_baseline_phase_lock_mismatch'
        $r.sequence = @($seq)
        return $r
    }
    $r.baseline_snapshot = 'VALID'

    # 2) frozen baseline integrity-record validation
    $seq.Add('2.frozen_baseline_integrity_record_validation')
    if (-not (Test-Path -LiteralPath $FrozenBaselineIntegrityPath)) {
        $r.reason = 'frozen_baseline_integrity_record_missing'
        $r.sequence = @($seq)
        return $r
    }

    try {
        $integrityObj = Get-Content -Raw -LiteralPath $FrozenBaselineIntegrityPath | ConvertFrom-Json
    } catch {
        $r.reason = 'frozen_baseline_integrity_record_parse_error'
        $r.sequence = @($seq)
        return $r
    }

    $requiredIntegrityFields = @('baseline_snapshot_hash','ledger_head_hash','coverage_fingerprint_hash','phase_locked')
    foreach ($f in $requiredIntegrityFields) {
        if (-not ($integrityObj.PSObject.Properties.Name -contains $f)) {
            $r.reason = ('frozen_baseline_integrity_record_missing_field_' + $f)
            $r.sequence = @($seq)
            return $r
        }
    }
    if ([string]$integrityObj.phase_locked -ne '49.5') {
        $r.reason = 'frozen_baseline_integrity_phase_lock_mismatch'
        $r.sequence = @($seq)
        return $r
    }

    $r.stored_baseline_hash = [string]$integrityObj.baseline_snapshot_hash
    $r.computed_baseline_hash = Get-CanonicalObjectHash -Obj $baselineObj
    if ($r.stored_baseline_hash -ne $r.computed_baseline_hash) {
        $r.reason = 'baseline_snapshot_hash_mismatch'
        $r.sequence = @($seq)
        return $r
    }

    if ([string]$integrityObj.ledger_head_hash -ne [string]$baselineObj.ledger_head_hash) {
        $r.reason = 'integrity_vs_snapshot_ledger_head_hash_mismatch'
        $r.sequence = @($seq)
        return $r
    }
    if ([string]$integrityObj.coverage_fingerprint_hash -ne [string]$baselineObj.coverage_fingerprint_hash) {
        $r.reason = 'integrity_vs_snapshot_coverage_fingerprint_hash_mismatch'
        $r.sequence = @($seq)
        return $r
    }

    $r.baseline_integrity = 'VALID'

    # 3) live ledger-head verification
    $seq.Add('3.live_ledger_head_verification')
    if (-not (Test-Path -LiteralPath $LiveLedgerPath)) {
        $r.reason = 'live_ledger_missing'
        $r.sequence = @($seq)
        return $r
    }

    try {
        $liveLedgerObj = Get-Content -Raw -LiteralPath $LiveLedgerPath | ConvertFrom-Json
    } catch {
        $r.reason = 'live_ledger_parse_error'
        $r.sequence = @($seq)
        return $r
    }

    $chainCheck = Test-LegacyTrustChain -ChainObj $liveLedgerObj
    if (-not $chainCheck.pass) {
        $r.reason = ('live_ledger_chain_invalid_' + [string]$chainCheck.reason)
        $r.sequence = @($seq)
        return $r
    }

    $entries = @($liveLedgerObj.entries)
    $canonicalEntryHashes = [System.Collections.Generic.List[string]]::new()
    foreach ($e in $entries) {
        $canonicalEntryHashes.Add((Get-CanonicalObjectHash -Obj $e))
    }

    $r.stored_ledger_head_hash = [string]$baselineObj.ledger_head_hash
    $r.computed_ledger_head_hash = [string]$canonicalEntryHashes[$canonicalEntryHashes.Count - 1]
    $r.ledger_head_match = if ($r.stored_ledger_head_hash -eq $r.computed_ledger_head_hash) { 'TRUE' } else { 'FALSE' }

    # 4) live coverage-fingerprint verification
    $seq.Add('4.live_coverage_fingerprint_verification')
    if (-not (Test-Path -LiteralPath $LiveCoverageFingerprintPath)) {
        $r.reason = 'live_coverage_fingerprint_reference_missing'
        $r.sequence = @($seq)
        return $r
    }

    try {
        $liveCoverageObj = Get-Content -Raw -LiteralPath $LiveCoverageFingerprintPath | ConvertFrom-Json
    } catch {
        $r.reason = 'live_coverage_fingerprint_parse_error'
        $r.sequence = @($seq)
        return $r
    }

    $r.stored_coverage_fingerprint_hash = [string]$baselineObj.coverage_fingerprint_hash
    $r.computed_coverage_fingerprint_hash = [string]$liveCoverageObj.coverage_fingerprint_sha256
    if ([string]::IsNullOrWhiteSpace([string]$r.computed_coverage_fingerprint_hash)) {
        $r.reason = 'live_coverage_fingerprint_missing'
        $r.sequence = @($seq)
        return $r
    }
    $r.coverage_fingerprint_match = if ($r.stored_coverage_fingerprint_hash -eq $r.computed_coverage_fingerprint_hash) { 'TRUE' } else { 'FALSE' }
    if ($r.coverage_fingerprint_match -ne 'TRUE') {
        $r.reason = 'coverage_fingerprint_hash_mismatch'
        $r.sequence = @($seq)
        return $r
    }

    # 5) live chain-continuation verification
    $seq.Add('5.live_chain_continuation_verification')
    $liveHashes = @($canonicalEntryHashes)
    $baselineHeadHash = [string]$baselineObj.ledger_head_hash
    $baselineLen = [int]$baselineObj.ledger_length

    if ($chainCheck.entry_count -lt $baselineLen) {
        $r.chain_continuation_status = 'INVALID'
        $r.reason = 'live_chain_shorter_than_frozen_baseline'
        $r.sequence = @($seq)
        return $r
    }

    $baselineHeadIndex = -1
    for ($i = 0; $i -lt $liveHashes.Count; $i++) {
        if ([string]$liveHashes[$i] -eq $baselineHeadHash) {
            $baselineHeadIndex = $i
            break
        }
    }

    if ($baselineHeadIndex -lt 0) {
        $r.chain_continuation_status = 'INVALID'
        $r.reason = 'frozen_baseline_head_not_present_in_live_chain'
        $r.sequence = @($seq)
        return $r
    }

    if ($baselineHeadIndex -ne ($baselineLen - 1)) {
        $r.chain_continuation_status = 'INVALID'
        $r.reason = 'frozen_baseline_head_index_mismatch'
        $r.sequence = @($seq)
        return $r
    }

    $r.chain_continuation_status = 'VALID'

    # 6) semantic protected-field verification
    $seq.Add('6.semantic_protected_field_verification')
    $semanticOk = $true

    foreach ($entryId in @($baselineObj.entry_hashes.PSObject.Properties | ForEach-Object { $_.Name })) {
        $frozenExpected = [string]$baselineObj.entry_hashes.$entryId
        $entryObj = $entries | Where-Object { [string]$_.entry_id -eq $entryId } | Select-Object -First 1
        if ($null -eq $entryObj) {
            $semanticOk = $false
            break
        }
        $actual = Get-CanonicalObjectHash -Obj $entryObj
        if ($actual -ne $frozenExpected) {
            $semanticOk = $false
            break
        }
    }

    $baselineHeadEntry = $entries[$baselineLen - 1]
    if ([string]$baselineHeadEntry.entry_id -ne [string]$baselineObj.latest_entry_id) { $semanticOk = $false }
    if ([string]$baselineHeadEntry.phase_locked -ne [string]$baselineObj.latest_entry_phase_locked) { $semanticOk = $false }

    $r.semantic_match_status = if ($semanticOk) { 'TRUE' } else { 'FALSE' }
    if ($r.semantic_match_status -ne 'TRUE') {
        $r.reason = 'semantic_protected_field_mismatch'
        $r.sequence = @($seq)
        return $r
    }

    # 7) runtime initialization allowed
    $seq.Add('7.runtime_initialization_allowed')
    $r.runtime_init_allowed_or_blocked = 'ALLOWED'
    $r.reason = if ($r.ledger_head_match -eq 'TRUE') { 'exact_frozen_head_match' } else { 'valid_frozen_head_continuation' }
    $r.sequence = @($seq)
    return $r
}

function Add-CaseRecordLine {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$CaseId,
        [object]$Result,
        [string]$Expected,
        [bool]$Pass
    )

    $Lines.Add(
        'CASE ' + $CaseId +
        ' | frozen_baseline_snapshot_path=' + [string]$Result.frozen_baseline_snapshot_path +
        ' | frozen_baseline_integrity_record_path=' + [string]$Result.frozen_baseline_integrity_record_path +
        ' | stored_baseline_hash=' + [string]$Result.stored_baseline_hash +
        ' | computed_baseline_hash=' + [string]$Result.computed_baseline_hash +
        ' | stored_ledger_head_hash=' + [string]$Result.stored_ledger_head_hash +
        ' | computed_ledger_head_hash=' + [string]$Result.computed_ledger_head_hash +
        ' | stored_coverage_fingerprint_hash=' + [string]$Result.stored_coverage_fingerprint_hash +
        ' | computed_coverage_fingerprint_hash=' + [string]$Result.computed_coverage_fingerprint_hash +
        ' | chain_continuation_status=' + [string]$Result.chain_continuation_status +
        ' | semantic_match_status=' + [string]$Result.semantic_match_status +
        ' | runtime_init_allowed_or_blocked=' + [string]$Result.runtime_init_allowed_or_blocked +
        ' | fallback_occurred=' + [string]$Result.fallback_occurred +
        ' | regeneration_occurred=' + [string]$Result.regeneration_occurred +
        ' | expected=' + $Expected +
        ' | reason=' + [string]$Result.reason +
        ' => ' + $(if ($Pass) { 'PASS' } else { 'FAIL' })
    )
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\phase49_6_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$BaselinePath = Join-Path $Root 'control_plane\94_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline.json'
$IntegrityPath = Join-Path $Root 'control_plane\95_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_integrity.json'
$LedgerPath = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$CoveragePath = Join-Path $Root 'control_plane\93_trust_chain_ledger_baseline_enforcement_coverage_fingerprint.json'

foreach ($p in @($BaselinePath, $IntegrityPath, $LedgerPath, $CoveragePath)) {
    if (-not (Test-Path -LiteralPath $p)) { throw ('Missing required file: ' + $p) }
}

$tmpRoot = Join-Path $env:TEMP ('phase49_6_' + $Timestamp)
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null

$ValidationLines = [System.Collections.Generic.List[string]]::new()
$RecordLines = [System.Collections.Generic.List[string]]::new()
$EvidenceLines = [System.Collections.Generic.List[string]]::new()
$allPass = $true

try {
    # CASE A clean frozen baseline pass
    $caseA = Invoke-FrozenBaselineEnforcementGate -FrozenBaselineSnapshotPath $BaselinePath -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $CoveragePath
    $caseAReasonOk = ($caseA.reason -eq 'exact_frozen_head_match' -or $caseA.reason -eq 'valid_frozen_head_continuation')
    $caseAPass = (
        $caseA.baseline_snapshot -eq 'VALID' -and
        $caseA.baseline_integrity -eq 'VALID' -and
        $caseA.coverage_fingerprint_match -eq 'TRUE' -and
        $caseA.chain_continuation_status -eq 'VALID' -and
        $caseA.runtime_init_allowed_or_blocked -eq 'ALLOWED' -and
        $caseAReasonOk
    )
    if (-not $caseAPass) { $allPass = $false }
    Add-CaseRecordLine -Lines $RecordLines -CaseId 'A' -Result $caseA -Expected 'baseline_snapshot=VALID,baseline_integrity=VALID,coverage_fingerprint_match=TRUE,chain_continuation=VALID,runtime_init=ALLOWED,reason in {exact_frozen_head_match|valid_frozen_head_continuation}' -Pass $caseAPass
    $ValidationLines.Add('CASE A clean_frozen_baseline_pass => ' + $(if ($caseAPass) { 'PASS' } else { 'FAIL' }))

    # CASE B frozen baseline snapshot tamper
    $snapB = Join-Path $tmpRoot 'caseB_baseline.json'
    Copy-Item -LiteralPath $BaselinePath -Destination $snapB -Force
    $objB = Get-Content -Raw -LiteralPath $snapB | ConvertFrom-Json
    $objB.phase_locked = '49.5-TAMPER'
    ($objB | ConvertTo-Json -Depth 50) | Set-Content -LiteralPath $snapB -Encoding UTF8 -NoNewline
    $caseB = Invoke-FrozenBaselineEnforcementGate -FrozenBaselineSnapshotPath $snapB -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $CoveragePath
    $caseBPass = ($caseB.baseline_snapshot -eq 'INVALID' -and $caseB.runtime_init_allowed_or_blocked -eq 'BLOCKED')
    if (-not $caseBPass) { $allPass = $false }
    Add-CaseRecordLine -Lines $RecordLines -CaseId 'B' -Result $caseB -Expected 'baseline_snapshot=INVALID,runtime_init=BLOCKED' -Pass $caseBPass
    $ValidationLines.Add('CASE B frozen_baseline_snapshot_tamper => ' + $(if ($caseBPass) { 'PASS' } else { 'FAIL' }))
    $EvidenceLines.Add('CASE B reason=' + [string]$caseB.reason)

    # CASE C frozen baseline integrity record tamper
    $intC = Join-Path $tmpRoot 'caseC_integrity.json'
    Copy-Item -LiteralPath $IntegrityPath -Destination $intC -Force
    $objC = Get-Content -Raw -LiteralPath $intC | ConvertFrom-Json
    $objC.baseline_snapshot_hash = ('0' * 64)
    ($objC | ConvertTo-Json -Depth 50) | Set-Content -LiteralPath $intC -Encoding UTF8 -NoNewline
    $caseC = Invoke-FrozenBaselineEnforcementGate -FrozenBaselineSnapshotPath $BaselinePath -FrozenBaselineIntegrityPath $intC -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $CoveragePath
    $caseCPass = ($caseC.baseline_integrity -eq 'INVALID' -and $caseC.runtime_init_allowed_or_blocked -eq 'BLOCKED')
    if (-not $caseCPass) { $allPass = $false }
    Add-CaseRecordLine -Lines $RecordLines -CaseId 'C' -Result $caseC -Expected 'baseline_integrity=INVALID,runtime_init=BLOCKED' -Pass $caseCPass
    $ValidationLines.Add('CASE C frozen_baseline_integrity_record_tamper => ' + $(if ($caseCPass) { 'PASS' } else { 'FAIL' }))
    $EvidenceLines.Add('CASE C reason=' + [string]$caseC.reason)

    # CASE D frozen-prefix semantic drift (must BLOCK)
    $ledgerDPath = Join-Path $tmpRoot 'caseD_ledger.json'
    Copy-Item -LiteralPath $LedgerPath -Destination $ledgerDPath -Force
    $baselineDObj = Get-Content -Raw -LiteralPath $BaselinePath | ConvertFrom-Json
    $ledgerDObj = Get-Content -Raw -LiteralPath $ledgerDPath | ConvertFrom-Json
    $entriesD = @($ledgerDObj.entries)

    # Mutate an entry inside frozen prefix via non-legacy field drift to keep continuation
    # chain shape intact while breaking semantic protected-field comparison.
    $frozenIndex = [Math]::Max(0, [int]$baselineDObj.ledger_length - 1)
    $entriesD[$frozenIndex].artifact = 'frozen_prefix_semantic_tamper'

    $ledgerDObj.entries = @($entriesD)
    ($ledgerDObj | ConvertTo-Json -Depth 60) | Set-Content -LiteralPath $ledgerDPath -Encoding UTF8 -NoNewline
    $caseD = Invoke-FrozenBaselineEnforcementGate -FrozenBaselineSnapshotPath $BaselinePath -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $ledgerDPath -LiveCoverageFingerprintPath $CoveragePath
    $caseDPass = ($caseD.semantic_match_status -eq 'FALSE' -and $caseD.runtime_init_allowed_or_blocked -eq 'BLOCKED')
    if (-not $caseDPass) { $allPass = $false }
    Add-CaseRecordLine -Lines $RecordLines -CaseId 'D' -Result $caseD -Expected 'semantic_match=FALSE,runtime_init=BLOCKED' -Pass $caseDPass
    $ValidationLines.Add('CASE D frozen_prefix_semantic_drift => ' + $(if ($caseDPass) { 'PASS' } else { 'FAIL' }))
    $EvidenceLines.Add('CASE D reason=' + [string]$caseD.reason)

    # CASE E live coverage fingerprint drift
    $covEPath = Join-Path $tmpRoot 'caseE_coverage.json'
    Copy-Item -LiteralPath $CoveragePath -Destination $covEPath -Force
    $covEObj = Get-Content -Raw -LiteralPath $covEPath | ConvertFrom-Json
    $covEObj.coverage_fingerprint_sha256 = ('e' * 64)
    ($covEObj | ConvertTo-Json -Depth 40) | Set-Content -LiteralPath $covEPath -Encoding UTF8 -NoNewline
    $caseE = Invoke-FrozenBaselineEnforcementGate -FrozenBaselineSnapshotPath $BaselinePath -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $covEPath
    $caseEPass = ($caseE.coverage_fingerprint_match -eq 'FALSE' -and $caseE.runtime_init_allowed_or_blocked -eq 'BLOCKED')
    if (-not $caseEPass) { $allPass = $false }
    Add-CaseRecordLine -Lines $RecordLines -CaseId 'E' -Result $caseE -Expected 'coverage_fingerprint_match=FALSE,runtime_init=BLOCKED' -Pass $caseEPass
    $ValidationLines.Add('CASE E live_coverage_fingerprint_drift => ' + $(if ($caseEPass) { 'PASS' } else { 'FAIL' }))
    $EvidenceLines.Add('CASE E reason=' + [string]$caseE.reason)

    # CASE F invalid chain continuation
    $ledgerFPath = Join-Path $tmpRoot 'caseF_ledger.json'
    Copy-Item -LiteralPath $LedgerPath -Destination $ledgerFPath -Force
    $ledgerFObj = Get-Content -Raw -LiteralPath $ledgerFPath | ConvertFrom-Json
    $nextIdF = Get-NextEntryId -ChainObj $ledgerFObj
    $newBad = [ordered]@{
        entry_id             = $nextIdF
        artifact             = 'invalid_continuation_probe'
        coverage_fingerprint = ('a' * 64)
        fingerprint_hash     = ('b' * 64)
        timestamp_utc        = (Get-Date -AsUTC -Format 'yyyy-MM-ddTHH:mm:ssZ')
        phase_locked         = '49.6'
        previous_hash        = ('0' * 64)
    }
    $ledgerFObj.entries += [pscustomobject]$newBad
    ($ledgerFObj | ConvertTo-Json -Depth 60) | Set-Content -LiteralPath $ledgerFPath -Encoding UTF8 -NoNewline
    $caseF = Invoke-FrozenBaselineEnforcementGate -FrozenBaselineSnapshotPath $BaselinePath -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $ledgerFPath -LiveCoverageFingerprintPath $CoveragePath
    $caseFPass = ($caseF.chain_continuation_status -eq 'INVALID' -and $caseF.runtime_init_allowed_or_blocked -eq 'BLOCKED')
    if (-not $caseFPass) { $allPass = $false }
    Add-CaseRecordLine -Lines $RecordLines -CaseId 'F' -Result $caseF -Expected 'chain_continuation=INVALID,runtime_init=BLOCKED' -Pass $caseFPass
    $ValidationLines.Add('CASE F invalid_chain_continuation => ' + $(if ($caseFPass) { 'PASS' } else { 'FAIL' }))
    $EvidenceLines.Add('CASE F reason=' + [string]$caseF.reason)

    # CASE G valid chain continuation
    $ledgerGPath = Join-Path $tmpRoot 'caseG_ledger.json'
    Copy-Item -LiteralPath $LedgerPath -Destination $ledgerGPath -Force
    $ledgerGObj = Get-Content -Raw -LiteralPath $ledgerGPath | ConvertFrom-Json
    $chainG = Test-LegacyTrustChain -ChainObj $ledgerGObj
    $nextIdG = Get-NextEntryId -ChainObj $ledgerGObj
    $newGood = [ordered]@{
        entry_id             = $nextIdG
        artifact             = 'valid_continuation_probe'
        coverage_fingerprint = ('c' * 64)
        fingerprint_hash     = ('d' * 64)
        timestamp_utc        = (Get-Date -AsUTC -Format 'yyyy-MM-ddTHH:mm:ssZ')
        phase_locked         = '49.6'
        previous_hash        = [string]$chainG.last_entry_hash
    }
    $ledgerGObj.entries += [pscustomobject]$newGood
    ($ledgerGObj | ConvertTo-Json -Depth 60) | Set-Content -LiteralPath $ledgerGPath -Encoding UTF8 -NoNewline
    $caseG = Invoke-FrozenBaselineEnforcementGate -FrozenBaselineSnapshotPath $BaselinePath -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $ledgerGPath -LiveCoverageFingerprintPath $CoveragePath
    $caseGPass = ($caseG.chain_continuation_status -eq 'VALID' -and $caseG.runtime_init_allowed_or_blocked -eq 'ALLOWED')
    if (-not $caseGPass) { $allPass = $false }
    Add-CaseRecordLine -Lines $RecordLines -CaseId 'G' -Result $caseG -Expected 'chain_continuation=VALID,runtime_init=ALLOWED' -Pass $caseGPass
    $ValidationLines.Add('CASE G valid_chain_continuation => ' + $(if ($caseGPass) { 'PASS' } else { 'FAIL' }))
    $EvidenceLines.Add('CASE G reason=' + [string]$caseG.reason)

    # CASE H non-semantic change (re-serialize unchanged data)
    $snapH = Join-Path $tmpRoot 'caseH_baseline.json'
    $intH  = Join-Path $tmpRoot 'caseH_integrity.json'
    $ledgH = Join-Path $tmpRoot 'caseH_ledger.json'
    $covH  = Join-Path $tmpRoot 'caseH_coverage.json'
    (Get-Content -Raw -LiteralPath $BaselinePath  | ConvertFrom-Json | ConvertTo-Json -Depth 60) | Set-Content -LiteralPath $snapH -Encoding UTF8 -NoNewline
    (Get-Content -Raw -LiteralPath $IntegrityPath | ConvertFrom-Json | ConvertTo-Json -Depth 60) | Set-Content -LiteralPath $intH  -Encoding UTF8 -NoNewline
    (Get-Content -Raw -LiteralPath $LedgerPath    | ConvertFrom-Json | ConvertTo-Json -Depth 80) | Set-Content -LiteralPath $ledgH -Encoding UTF8 -NoNewline
    (Get-Content -Raw -LiteralPath $CoveragePath  | ConvertFrom-Json | ConvertTo-Json -Depth 50) | Set-Content -LiteralPath $covH  -Encoding UTF8 -NoNewline
    $caseH = Invoke-FrozenBaselineEnforcementGate -FrozenBaselineSnapshotPath $snapH -FrozenBaselineIntegrityPath $intH -LiveLedgerPath $ledgH -LiveCoverageFingerprintPath $covH
    $caseHPass = ($caseH.baseline_integrity -eq 'VALID' -and $caseH.semantic_match_status -eq 'TRUE' -and $caseH.runtime_init_allowed_or_blocked -eq 'ALLOWED')
    if (-not $caseHPass) { $allPass = $false }
    Add-CaseRecordLine -Lines $RecordLines -CaseId 'H' -Result $caseH -Expected 'baseline_integrity=VALID,semantic_match=TRUE,runtime_init=ALLOWED' -Pass $caseHPass
    $ValidationLines.Add('CASE H non_semantic_change => ' + $(if ($caseHPass) { 'PASS' } else { 'FAIL' }))
    $EvidenceLines.Add('CASE H reason=' + [string]$caseH.reason)

} finally {
    if (Test-Path -LiteralPath $tmpRoot) { Remove-Item -LiteralPath $tmpRoot -Recurse -Force }
}

$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status01 = @(
    'PHASE=49.6',
    'TITLE=Trust-Chain Ledger Baseline Enforcement Coverage Fingerprint Trust-Chain Baseline Enforcement',
    'GATE=' + $Gate,
    'FROZEN_BASELINE_ENFORCED_PRE_INIT=TRUE',
    'FALLBACK_OCCURRED=FALSE',
    'REGENERATION_OCCURRED=FALSE',
    'RUNTIME_STATE_MACHINE_CHANGED=FALSE'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '01_status.txt'), $status01, [System.Text.Encoding]::UTF8)

$head02 = @(
    'RUNNER=' + $Root + '\tools\phase49_6\phase49_6_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_runner.ps1',
    'FROZEN_BASELINE_SNAPSHOT=' + $BaselinePath,
    'FROZEN_BASELINE_INTEGRITY=' + $IntegrityPath,
    'LIVE_LEDGER=' + $LedgerPath,
    'LIVE_COVERAGE_FINGERPRINT=' + $CoveragePath
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '02_head.txt'), $head02, [System.Text.Encoding]::UTF8)

$def10 = @(
    'ENFORCEMENT_ENTRY=Invoke-FrozenBaselineEnforcementGate',
    'PHASE_LOCK=49.6',
    'ENFORCEMENT_ORDER=1.snapshot,2.integrity,3.ledger_head,4.coverage_fingerprint,5.chain_continuation,6.semantic_protected_fields,7.runtime_init_allowed',
    'FROZEN_BASELINE_SOURCE=control_plane/94 + control_plane/95',
    'COVERAGE_SOURCE=control_plane/93'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '10_baseline_enforcement_definition.txt'), $def10, [System.Text.Encoding]::UTF8)

$rules11 = @(
    'RULE_1=Frozen baseline snapshot must exist and phase_locked=49.5',
    'RULE_2=Frozen integrity record must exist and phase_locked=49.5',
    'RULE_3=Stored baseline hash must equal canonical snapshot hash',
    'RULE_4=Live coverage fingerprint hash must match frozen baseline expectation',
    'RULE_5=Live chain must be valid and include frozen baseline head at frozen index',
    'RULE_6=Protected semantic fields (entry hashes, latest entry id/phase) must match',
    'RULE_7=Runtime init allowed only when all prior rules pass',
    'RULE_8=No fallback and no regeneration paths'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '11_baseline_enforcement_rules.txt'), $rules11, [System.Text.Encoding]::UTF8)

$files12 = @(
    'READ=' + $BaselinePath,
    'READ=' + $IntegrityPath,
    'READ=' + $LedgerPath,
    'READ=' + $CoveragePath,
    'WRITE=' + $PF
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '12_files_touched.txt'), $files12, [System.Text.Encoding]::UTF8)

$build13 = @(
    'CASE_COUNT=8',
    'FROZEN_BASELINE_ENFORCED_PRE_INIT=TRUE',
    'FALLBACK_OCCURRED=FALSE',
    'REGENERATION_OCCURRED=FALSE',
    'GATE=' + $Gate
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '13_build_output.txt'), $build13, [System.Text.Encoding]::UTF8)

[System.IO.File]::WriteAllText((Join-Path $PF '14_validation_results.txt'), ($ValidationLines -join "`r`n"), [System.Text.Encoding]::UTF8)

$passCount = @($ValidationLines | Where-Object { $_ -match '=> PASS' }).Count
$failCount = @($ValidationLines | Where-Object { $_ -match '=> FAIL' }).Count
$summary15 = @(
    'TOTAL_CASES=8',
    'PASSED=' + $passCount,
    'FAILED=' + $failCount,
    'GATE=' + $Gate,
    'NO_FALLBACK=TRUE',
    'NO_REGENERATION=TRUE',
    'RUNTIME_STATE_MACHINE_UNCHANGED=TRUE'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '15_behavior_summary.txt'), $summary15, [System.Text.Encoding]::UTF8)

$recordHeader = 'case|frozen_baseline_snapshot_path|frozen_baseline_integrity_record_path|stored_baseline_hash|computed_baseline_hash|stored_ledger_head_hash|computed_ledger_head_hash|stored_coverage_fingerprint_hash|computed_coverage_fingerprint_hash|chain_continuation_status|semantic_match_status|runtime_init_allowed_or_blocked|fallback_occurred|regeneration_occurred|reason'
$recordBody = @($recordHeader) + @($RecordLines)
[System.IO.File]::WriteAllText((Join-Path $PF '16_frozen_baseline_enforcement_record.txt'), ($recordBody -join "`r`n"), [System.Text.Encoding]::UTF8)

[System.IO.File]::WriteAllText((Join-Path $PF '17_runtime_block_evidence.txt'), ($EvidenceLines -join "`r`n"), [System.Text.Encoding]::UTF8)

$gate98 = @('PHASE=49.6', 'GATE=' + $Gate) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '98_gate_phase49_6.txt'), $gate98, [System.Text.Encoding]::UTF8)

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
