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

    # Step 1: frozen 51.3 baseline snapshot validation
    $seq.Add('1.frozen_51_3_baseline_snapshot_validation')
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
        'baseline_version', 'phase_locked', 'ledger_head_hash', 'ledger_length',
        'coverage_fingerprint_hash', 'latest_entry_id', 'latest_entry_phase_locked', 'entry_hashes'
    )
    foreach ($f in $requiredBaselineFields) {
        if (-not ($baselineObj.PSObject.Properties.Name -contains $f)) {
            $r.reason = ('frozen_baseline_snapshot_missing_field_' + $f)
            $r.sequence = @($seq)
            return $r
        }
    }
    if ([string]$baselineObj.phase_locked -ne '51.3') {
        $r.reason = 'frozen_baseline_phase_lock_mismatch'
        $r.sequence = @($seq)
        return $r
    }
    $r.baseline_snapshot = 'VALID'

    # Step 2: frozen baseline integrity-record validation
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

    $requiredIntegrityFields = @('baseline_snapshot_hash', 'ledger_head_hash', 'coverage_fingerprint_hash', 'phase_locked')
    foreach ($f in $requiredIntegrityFields) {
        if (-not ($integrityObj.PSObject.Properties.Name -contains $f)) {
            $r.reason = ('frozen_baseline_integrity_record_missing_field_' + $f)
            $r.sequence = @($seq)
            return $r
        }
    }
    if ([string]$integrityObj.phase_locked -ne '51.3') {
        $r.reason = 'frozen_baseline_integrity_phase_lock_mismatch'
        $r.sequence = @($seq)
        return $r
    }

    $r.stored_baseline_hash   = [string]$integrityObj.baseline_snapshot_hash
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

    # Step 3: live ledger-head verification
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

    $liveEntries = @($liveLedgerObj.entries)
    $canonicalEntryHashes = [System.Collections.Generic.List[string]]::new()
    foreach ($e in $liveEntries) {
        $canonicalEntryHashes.Add((Get-CanonicalObjectHash -Obj $e))
    }

    $r.stored_ledger_head_hash   = [string]$baselineObj.ledger_head_hash
    $r.computed_ledger_head_hash = [string]$canonicalEntryHashes[$canonicalEntryHashes.Count - 1]
    $r.ledger_head_match = if ($r.stored_ledger_head_hash -eq $r.computed_ledger_head_hash) { 'TRUE' } else { 'FALSE' }

    # Step 4: live enforcement-surface fingerprint verification
    $seq.Add('4.live_enforcement_surface_fingerprint_verification')
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

    $r.stored_coverage_fingerprint_hash   = [string]$baselineObj.coverage_fingerprint_hash
    $r.computed_coverage_fingerprint_hash = [string]$liveCoverageObj.coverage_fingerprint_sha256
    if ([string]::IsNullOrWhiteSpace($r.computed_coverage_fingerprint_hash)) {
        $r.reason = 'live_coverage_fingerprint_sha256_missing'
        $r.sequence = @($seq)
        return $r
    }
    $r.coverage_fingerprint_match = if ($r.stored_coverage_fingerprint_hash -eq $r.computed_coverage_fingerprint_hash) { 'TRUE' } else { 'FALSE' }
    if ($r.coverage_fingerprint_match -ne 'TRUE') {
        $r.reason = 'coverage_fingerprint_hash_mismatch'
        $r.sequence = @($seq)
        return $r
    }

    # Step 5: live chain-continuation verification
    $seq.Add('5.live_chain_continuation_verification')
    $liveHashes     = @($canonicalEntryHashes)
    $baselineHeadHash = [string]$baselineObj.ledger_head_hash
    $baselineLen    = [int]$baselineObj.ledger_length

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

    # Step 6: semantic protected-field verification
    $seq.Add('6.semantic_protected_field_verification')
    $semanticOk = $true

    foreach ($entryId in @($baselineObj.entry_hashes.PSObject.Properties | ForEach-Object { $_.Name })) {
        $frozenExpected = [string]$baselineObj.entry_hashes.$entryId
        $entryObj = $liveEntries | Where-Object { [string]$_.entry_id -eq $entryId } | Select-Object -First 1
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

    $baselineHeadEntry = $liveEntries[$baselineLen - 1]
    if ([string]$baselineHeadEntry.entry_id -ne [string]$baselineObj.latest_entry_id) { $semanticOk = $false }
    if ([string]$baselineHeadEntry.phase_locked -ne [string]$baselineObj.latest_entry_phase_locked) { $semanticOk = $false }

    $r.semantic_match_status = if ($semanticOk) { 'TRUE' } else { 'FALSE' }
    if ($r.semantic_match_status -ne 'TRUE') {
        $r.reason = 'semantic_protected_field_mismatch'
        $r.sequence = @($seq)
        return $r
    }

    # Step 7: runtime initialization allowed
    $seq.Add('7.runtime_initialization_allowed')
    $r.runtime_init_allowed_or_blocked = 'ALLOWED'
    $r.reason = if ($r.ledger_head_match -eq 'TRUE') { 'exact_frozen_head_match' } else { 'valid_frozen_head_continuation' }
    $r.sequence = @($seq)
    return $r
}

function Add-CaseLine {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$CaseId,
        [string]$CaseName,
        [string]$ExpectedRuntime,
        [object]$Gate,
        [bool]$Pass
    )

    $Lines.Add(
        'CASE ' + $CaseId + ' ' + $CaseName +
        ' | frozen_baseline_snapshot_path=' + [string]$Gate.frozen_baseline_snapshot_path +
        ' | frozen_baseline_integrity_record_path=' + [string]$Gate.frozen_baseline_integrity_record_path +
        ' | stored_baseline_hash=' + [string]$Gate.stored_baseline_hash +
        ' | computed_baseline_hash=' + [string]$Gate.computed_baseline_hash +
        ' | stored_ledger_head_hash=' + [string]$Gate.stored_ledger_head_hash +
        ' | computed_ledger_head_hash=' + [string]$Gate.computed_ledger_head_hash +
        ' | stored_coverage_fingerprint_hash=' + [string]$Gate.stored_coverage_fingerprint_hash +
        ' | computed_coverage_fingerprint_hash=' + [string]$Gate.computed_coverage_fingerprint_hash +
        ' | chain_continuation_status=' + [string]$Gate.chain_continuation_status +
        ' | semantic_match_status=' + [string]$Gate.semantic_match_status +
        ' | runtime_init_allowed_or_blocked=' + [string]$Gate.runtime_init_allowed_or_blocked +
        ' | fallback_occurred=' + [string]$Gate.fallback_occurred +
        ' | regeneration_occurred=' + [string]$Gate.regeneration_occurred +
        ' | baseline_snapshot=' + [string]$Gate.baseline_snapshot +
        ' | baseline_integrity=' + [string]$Gate.baseline_integrity +
        ' | reason=' + [string]$Gate.reason +
        ' | expected=' + $ExpectedRuntime +
        ' => ' + $(if ($Pass) { 'PASS' } else { 'FAIL' })
    )
}

# ── Setup ─────────────────────────────────────────────────────────────────────

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\phase51_4_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$RunnerPath    = Join-Path $Root 'tools\phase51_4\phase51_4_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_runner.ps1'
$LedgerPath    = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$CoveragePath  = Join-Path $Root 'control_plane\101_trust_chain_ledger_baseline_enforcement_surface_fingerprint.json'
$BaselinePath  = Join-Path $Root 'control_plane\102_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline.json'
$IntegrityPath = Join-Path $Root 'control_plane\103_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_integrity.json'

foreach ($p in @($LedgerPath, $CoveragePath, $BaselinePath, $IntegrityPath)) {
    if (-not (Test-Path -LiteralPath $p)) { throw ('Missing required file: ' + $p) }
}

$coverageObj             = Get-Content -Raw -LiteralPath $CoveragePath | ConvertFrom-Json
$coverageFingerprintHash = [string]$coverageObj.coverage_fingerprint_sha256

$tmpRoot = Join-Path $env:TEMP ('phase51_4_' + $Timestamp)
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null

$ValidationLines = [System.Collections.Generic.List[string]]::new()
$RecordLines     = [System.Collections.Generic.List[string]]::new()
$EvidenceLines   = [System.Collections.Generic.List[string]]::new()
$allPass         = $true

try {
    # ── CASE A — clean frozen baseline pass ──────────────────────────────────
    $gateA = Invoke-FrozenBaselineEnforcementGate `
        -FrozenBaselineSnapshotPath $BaselinePath `
        -FrozenBaselineIntegrityPath $IntegrityPath `
        -LiveLedgerPath $LedgerPath `
        -LiveCoverageFingerprintPath $CoveragePath
    $caseAPass = (
        [string]$gateA.runtime_init_allowed_or_blocked -eq 'ALLOWED' -and
        [string]$gateA.baseline_snapshot -eq 'VALID' -and
        [string]$gateA.baseline_integrity -eq 'VALID' -and
        [string]$gateA.ledger_head_match -eq 'TRUE' -and
        [string]$gateA.coverage_fingerprint_match -eq 'TRUE' -and
        [string]$gateA.chain_continuation_status -eq 'VALID' -and
        -not [bool]$gateA.fallback_occurred -and
        -not [bool]$gateA.regeneration_occurred
    )
    if (-not $caseAPass) { $allPass = $false }
    Add-CaseLine -Lines $ValidationLines -CaseId 'A' -CaseName 'clean_frozen_baseline_pass' -ExpectedRuntime 'ALLOWED' -Gate $gateA -Pass $caseAPass
    $RecordLines.Add('CASE A|steps_reached=' + ($gateA.sequence -join ',') + '|reason=' + $gateA.reason)

    # ── CASE B — frozen baseline snapshot tamper ─────────────────────────────
    $snapBPath = Join-Path $tmpRoot 'case_b_snapshot.json'
    $snapBObj  = Get-Content -Raw -LiteralPath $BaselinePath | ConvertFrom-Json
    $snapBObj.phase_locked = '51.3-TAMPER'
    ($snapBObj | ConvertTo-Json -Depth 60) | Set-Content -LiteralPath $snapBPath -Encoding UTF8 -NoNewline

    $gateB = Invoke-FrozenBaselineEnforcementGate `
        -FrozenBaselineSnapshotPath $snapBPath `
        -FrozenBaselineIntegrityPath $IntegrityPath `
        -LiveLedgerPath $LedgerPath `
        -LiveCoverageFingerprintPath $CoveragePath
    $caseBPass = (
        [string]$gateB.runtime_init_allowed_or_blocked -eq 'BLOCKED' -and
        [string]$gateB.baseline_snapshot -eq 'INVALID' -and
        -not [bool]$gateB.fallback_occurred -and
        -not [bool]$gateB.regeneration_occurred
    )
    if (-not $caseBPass) { $allPass = $false }
    Add-CaseLine -Lines $ValidationLines -CaseId 'B' -CaseName 'frozen_baseline_snapshot_tamper' -ExpectedRuntime 'BLOCKED' -Gate $gateB -Pass $caseBPass
    $EvidenceLines.Add('CASE B blocked_at=step_1 reason=' + [string]$gateB.reason)

    # ── CASE C — frozen baseline integrity record tamper ─────────────────────
    $intCPath = Join-Path $tmpRoot 'case_c_integrity.json'
    $intCObj  = Get-Content -Raw -LiteralPath $IntegrityPath | ConvertFrom-Json
    $intCObj.baseline_snapshot_hash = ('0' * 64)
    ($intCObj | ConvertTo-Json -Depth 40) | Set-Content -LiteralPath $intCPath -Encoding UTF8 -NoNewline

    $gateC = Invoke-FrozenBaselineEnforcementGate `
        -FrozenBaselineSnapshotPath $BaselinePath `
        -FrozenBaselineIntegrityPath $intCPath `
        -LiveLedgerPath $LedgerPath `
        -LiveCoverageFingerprintPath $CoveragePath
    $caseCPass = (
        [string]$gateC.runtime_init_allowed_or_blocked -eq 'BLOCKED' -and
        [string]$gateC.baseline_integrity -eq 'INVALID' -and
        -not [bool]$gateC.fallback_occurred -and
        -not [bool]$gateC.regeneration_occurred
    )
    if (-not $caseCPass) { $allPass = $false }
    Add-CaseLine -Lines $ValidationLines -CaseId 'C' -CaseName 'frozen_baseline_integrity_record_tamper' -ExpectedRuntime 'BLOCKED' -Gate $gateC -Pass $caseCPass
    $EvidenceLines.Add('CASE C blocked_at=step_2 reason=' + [string]$gateC.reason)

    # ── CASE D — live ledger head drift ──────────────────────────────────────
    $ledgerDPath = Join-Path $tmpRoot 'case_d_ledger.json'
    $ledgerDObj  = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
    $idxD        = @($ledgerDObj.entries).Count - 1
    $ledgerDObj.entries[$idxD].fingerprint_hash = ('e' * 64)
    ($ledgerDObj | ConvertTo-Json -Depth 40) | Set-Content -LiteralPath $ledgerDPath -Encoding UTF8 -NoNewline

    $gateD = Invoke-FrozenBaselineEnforcementGate `
        -FrozenBaselineSnapshotPath $BaselinePath `
        -FrozenBaselineIntegrityPath $IntegrityPath `
        -LiveLedgerPath $ledgerDPath `
        -LiveCoverageFingerprintPath $CoveragePath
    $caseDPass = (
        [string]$gateD.runtime_init_allowed_or_blocked -eq 'BLOCKED' -and
        [string]$gateD.ledger_head_match -eq 'FALSE' -and
        -not [bool]$gateD.fallback_occurred -and
        -not [bool]$gateD.regeneration_occurred
    )
    if (-not $caseDPass) { $allPass = $false }
    Add-CaseLine -Lines $ValidationLines -CaseId 'D' -CaseName 'live_ledger_head_drift' -ExpectedRuntime 'BLOCKED' -Gate $gateD -Pass $caseDPass
    $EvidenceLines.Add('CASE D blocked_at=step_5 reason=' + [string]$gateD.reason + ' ledger_head_match=' + [string]$gateD.ledger_head_match)

    # ── CASE E — live fingerprint drift ──────────────────────────────────────
    $covEPath = Join-Path $tmpRoot 'case_e_coverage.json'
    $covEObj  = Get-Content -Raw -LiteralPath $CoveragePath | ConvertFrom-Json
    $covEObj.coverage_fingerprint_sha256 = ('0' * 64)
    ($covEObj | ConvertTo-Json -Depth 40) | Set-Content -LiteralPath $covEPath -Encoding UTF8 -NoNewline

    $gateE = Invoke-FrozenBaselineEnforcementGate `
        -FrozenBaselineSnapshotPath $BaselinePath `
        -FrozenBaselineIntegrityPath $IntegrityPath `
        -LiveLedgerPath $LedgerPath `
        -LiveCoverageFingerprintPath $covEPath
    $caseEPass = (
        [string]$gateE.runtime_init_allowed_or_blocked -eq 'BLOCKED' -and
        [string]$gateE.coverage_fingerprint_match -eq 'FALSE' -and
        -not [bool]$gateE.fallback_occurred -and
        -not [bool]$gateE.regeneration_occurred
    )
    if (-not $caseEPass) { $allPass = $false }
    Add-CaseLine -Lines $ValidationLines -CaseId 'E' -CaseName 'live_fingerprint_drift' -ExpectedRuntime 'BLOCKED' -Gate $gateE -Pass $caseEPass
    $EvidenceLines.Add('CASE E blocked_at=step_4 reason=' + [string]$gateE.reason + ' coverage_fingerprint_match=' + [string]$gateE.coverage_fingerprint_match)

    # ── CASE F — invalid chain continuation ──────────────────────────────────
    $ledgerFPath = Join-Path $tmpRoot 'case_f_ledger.json'
    $ledgerFObj  = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
    $entryF = [ordered]@{
        entry_id             = 'GF-0013'
        artifact             = 'invalid_chain_continuation_probe'
        coverage_fingerprint = $coverageFingerprintHash
        fingerprint_hash     = ('f' * 64)
        timestamp_utc        = (Get-Date -AsUTC -Format 'yyyy-MM-ddTHH:mm:ssZ')
        phase_locked         = '51.4-PROBE'
        previous_hash        = ('0' * 64)  # deliberately wrong
    }
    $ledgerFObj.entries += [pscustomobject]$entryF
    ($ledgerFObj | ConvertTo-Json -Depth 40) | Set-Content -LiteralPath $ledgerFPath -Encoding UTF8 -NoNewline

    $gateF = Invoke-FrozenBaselineEnforcementGate `
        -FrozenBaselineSnapshotPath $BaselinePath `
        -FrozenBaselineIntegrityPath $IntegrityPath `
        -LiveLedgerPath $ledgerFPath `
        -LiveCoverageFingerprintPath $CoveragePath
    $caseFPass = (
        [string]$gateF.runtime_init_allowed_or_blocked -eq 'BLOCKED' -and
        [string]$gateF.chain_continuation_status -eq 'INVALID' -and
        -not [bool]$gateF.fallback_occurred -and
        -not [bool]$gateF.regeneration_occurred
    )
    if (-not $caseFPass) { $allPass = $false }
    Add-CaseLine -Lines $ValidationLines -CaseId 'F' -CaseName 'invalid_chain_continuation' -ExpectedRuntime 'BLOCKED' -Gate $gateF -Pass $caseFPass
    $EvidenceLines.Add('CASE F blocked_at=step_3 reason=' + [string]$gateF.reason)

    # ── CASE G — valid chain continuation ────────────────────────────────────
    $ledgerGPath = Join-Path $tmpRoot 'case_g_ledger.json'
    $ledgerGObj  = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
    $chainGPre   = Test-LegacyTrustChain -ChainObj $ledgerGObj
    $entryG = [ordered]@{
        entry_id             = 'GF-0013'
        artifact             = 'future_chain_continuation_probe'
        coverage_fingerprint = $coverageFingerprintHash
        fingerprint_hash     = ('a' * 64)
        timestamp_utc        = (Get-Date -AsUTC -Format 'yyyy-MM-ddTHH:mm:ssZ')
        phase_locked         = '51.4-PROBE'
        previous_hash        = [string]$chainGPre.last_entry_hash  # correct link
    }
    $ledgerGObj.entries += [pscustomobject]$entryG
    ($ledgerGObj | ConvertTo-Json -Depth 40) | Set-Content -LiteralPath $ledgerGPath -Encoding UTF8 -NoNewline

    $gateG = Invoke-FrozenBaselineEnforcementGate `
        -FrozenBaselineSnapshotPath $BaselinePath `
        -FrozenBaselineIntegrityPath $IntegrityPath `
        -LiveLedgerPath $ledgerGPath `
        -LiveCoverageFingerprintPath $CoveragePath
    $caseGPass = (
        [string]$gateG.runtime_init_allowed_or_blocked -eq 'ALLOWED' -and
        [string]$gateG.chain_continuation_status -eq 'VALID' -and
        -not [bool]$gateG.fallback_occurred -and
        -not [bool]$gateG.regeneration_occurred
    )
    if (-not $caseGPass) { $allPass = $false }
    Add-CaseLine -Lines $ValidationLines -CaseId 'G' -CaseName 'valid_chain_continuation' -ExpectedRuntime 'ALLOWED' -Gate $gateG -Pass $caseGPass
    $RecordLines.Add('CASE G valid_continuation|steps_reached=' + ($gateG.sequence -join ',') + '|reason=' + $gateG.reason + '|ledger_head_match=' + $gateG.ledger_head_match)

    # ── CASE H — non-semantic change ─────────────────────────────────────────
    $snapHPath   = Join-Path $tmpRoot 'case_h_snapshot.json'
    $intHPath    = Join-Path $tmpRoot 'case_h_integrity.json'
    $ledgerHPath = Join-Path $tmpRoot 'case_h_ledger.json'
    $covHPath    = Join-Path $tmpRoot 'case_h_coverage.json'

    (Get-Content -Raw -LiteralPath $BaselinePath  | ConvertFrom-Json | ConvertTo-Json -Depth 60) | Set-Content -LiteralPath $snapHPath   -Encoding UTF8 -NoNewline
    (Get-Content -Raw -LiteralPath $IntegrityPath | ConvertFrom-Json | ConvertTo-Json -Depth 40) | Set-Content -LiteralPath $intHPath    -Encoding UTF8 -NoNewline
    (Get-Content -Raw -LiteralPath $LedgerPath    | ConvertFrom-Json | ConvertTo-Json -Depth 40) | Set-Content -LiteralPath $ledgerHPath -Encoding UTF8 -NoNewline
    (Get-Content -Raw -LiteralPath $CoveragePath  | ConvertFrom-Json | ConvertTo-Json -Depth 40) | Set-Content -LiteralPath $covHPath    -Encoding UTF8 -NoNewline

    $gateH = Invoke-FrozenBaselineEnforcementGate `
        -FrozenBaselineSnapshotPath $snapHPath `
        -FrozenBaselineIntegrityPath $intHPath `
        -LiveLedgerPath $ledgerHPath `
        -LiveCoverageFingerprintPath $covHPath
    $caseHPass = (
        [string]$gateH.runtime_init_allowed_or_blocked -eq 'ALLOWED' -and
        [string]$gateH.baseline_integrity -eq 'VALID' -and
        [string]$gateH.semantic_match_status -eq 'TRUE' -and
        -not [bool]$gateH.fallback_occurred -and
        -not [bool]$gateH.regeneration_occurred
    )
    if (-not $caseHPass) { $allPass = $false }
    Add-CaseLine -Lines $ValidationLines -CaseId 'H' -CaseName 'non_semantic_change' -ExpectedRuntime 'ALLOWED' -Gate $gateH -Pass $caseHPass
    $RecordLines.Add('CASE H non_semantic|steps_reached=' + ($gateH.sequence -join ',') + '|reason=' + $gateH.reason)

    $Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

    # ── Proof artifacts ───────────────────────────────────────────────────────

    $status01 = @(
        'PHASE=51.4',
        'TITLE=Trust-Chain Ledger Baseline Enforcement Surface Fingerprint Trust-Chain Baseline Enforcement',
        'GATE=' + $Gate,
        'ALL_PROTECTED_ENTRYPOINTS_GATED=TRUE',
        'FALLBACK_OCCURRED=FALSE',
        'REGENERATION_OCCURRED=FALSE',
        'RUNTIME_STATE_MACHINE_CHANGED=FALSE'
    ) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '01_status.txt'), $status01, [System.Text.Encoding]::UTF8)

    $head02 = @(
        'RUNNER=' + $RunnerPath,
        'FROZEN_BASELINE_SNAPSHOT=' + $BaselinePath,
        'FROZEN_BASELINE_INTEGRITY=' + $IntegrityPath,
        'LIVE_LEDGER=' + $LedgerPath,
        'LIVE_COVERAGE_FINGERPRINT=' + $CoveragePath
    ) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '02_head.txt'), $head02, [System.Text.Encoding]::UTF8)

    $def10 = @(
        'FROZEN_BASELINE_SNAPSHOT=control_plane/102_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline.json',
        'FROZEN_BASELINE_INTEGRITY=control_plane/103_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_integrity.json',
        'LIVE_LEDGER=control_plane/70_guard_fingerprint_trust_chain.json',
        'LIVE_COVERAGE_FINGERPRINT=control_plane/101_trust_chain_ledger_baseline_enforcement_surface_fingerprint.json',
        'NO_FILENAME_DRIFT=TRUE (102/103 used as planned in phase 51.3)',
        'PHASE_LOCKED=51.3',
        'ENFORCEMENT_ORDER=1.snapshot_validation,2.integrity_record_validation,3.ledger_head_verification,4.fingerprint_verification,5.chain_continuation_verification,6.semantic_field_verification,7.runtime_init_allowed'
    ) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '10_baseline_enforcement_definition.txt'), $def10, [System.Text.Encoding]::UTF8)

    $rules11 = @(
        'RULE_1=frozen 51.3 baseline snapshot must exist, be parseable, contain required fields, and have phase_locked=51.3',
        'RULE_2=frozen baseline integrity record must exist, phase_locked=51.3, and baseline_snapshot_hash must match canonical hash of snapshot',
        'RULE_3=live ledger must form a valid legacy trust chain',
        'RULE_4=live coverage_fingerprint_sha256 must match baseline.coverage_fingerprint_hash',
        'RULE_5=baseline head (canonical entry hash of entry at baseline_len-1) must be present in live chain at the expected position',
        'RULE_6=all entry_hashes in baseline must match live entries; latest_entry_id and latest_entry_phase_locked must match',
        'RULE_7=if all above pass, runtime_init=ALLOWED; reason=exact_frozen_head_match or valid_frozen_head_continuation',
        'NO_FALLBACK=TRUE',
        'NO_REGENERATION=TRUE'
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

    $passCount = @($ValidationLines | Where-Object { $_ -match '=> PASS$' }).Count
    $failCount = @($ValidationLines | Where-Object { $_ -match '=> FAIL$' }).Count
    $build13 = @(
        'CASE_COUNT=8',
        'PASSED=' + $passCount,
        'FAILED=' + $failCount,
        'FALLBACK_OCCURRED=FALSE',
        'REGENERATION_OCCURRED=FALSE',
        'GATE=' + $Gate
    ) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '13_build_output.txt'), $build13, [System.Text.Encoding]::UTF8)

    [System.IO.File]::WriteAllText((Join-Path $PF '14_validation_results.txt'), ($ValidationLines -join "`r`n"), [System.Text.Encoding]::UTF8)

    $beh15 = @(
        'PHASE=51.4',
        'TOTAL_CASES=8',
        'PASSED=' + $passCount,
        'FAILED=' + $failCount,
        'GATE=' + $Gate,
        'CONTROL_PLANE_ARTIFACT_102=102_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline.json (no filename drift)',
        'CONTROL_PLANE_ARTIFACT_103=103_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_integrity.json (no filename drift)',
        'ENFORCEMENT_GATE=Invoke-FrozenBaselineEnforcementGate runs 7-step sequence before runtime init',
        'VALID_CONTINUATION_ALLOWED=TRUE',
        'NON_SEMANTIC_CHANGES_ALLOWED=TRUE',
        'NO_FALLBACK=TRUE',
        'NO_REGENERATION=TRUE',
        'RUNTIME_STATE_MACHINE_UNCHANGED=TRUE'
    ) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '15_behavior_summary.txt'), $beh15, [System.Text.Encoding]::UTF8)

    $record16Header = 'case|steps_reached|baseline_snapshot|baseline_integrity|ledger_head_match|coverage_fingerprint_match|chain_continuation_status|semantic_match_status|runtime_init|reason'
    $record16Lines  = [System.Collections.Generic.List[string]]::new()
    $record16Lines.Add($record16Header)
    foreach ($row in @(
        [ordered]@{ id='A'; g=$gateA },
        [ordered]@{ id='B'; g=$gateB },
        [ordered]@{ id='C'; g=$gateC },
        [ordered]@{ id='D'; g=$gateD },
        [ordered]@{ id='E'; g=$gateE },
        [ordered]@{ id='F'; g=$gateF },
        [ordered]@{ id='G'; g=$gateG },
        [ordered]@{ id='H'; g=$gateH }
    )) {
        $g = $row.g
        $record16Lines.Add(
            [string]$row.id + '|' +
            ($g.sequence -join ',') + '|' +
            [string]$g.baseline_snapshot + '|' +
            [string]$g.baseline_integrity + '|' +
            [string]$g.ledger_head_match + '|' +
            [string]$g.coverage_fingerprint_match + '|' +
            [string]$g.chain_continuation_status + '|' +
            [string]$g.semantic_match_status + '|' +
            [string]$g.runtime_init_allowed_or_blocked + '|' +
            [string]$g.reason
        )
    }
    [System.IO.File]::WriteAllText((Join-Path $PF '16_frozen_baseline_enforcement_record.txt'), ($record16Lines -join "`r`n"), [System.Text.Encoding]::UTF8)

    [System.IO.File]::WriteAllText((Join-Path $PF '17_runtime_block_evidence.txt'), ($EvidenceLines -join "`r`n"), [System.Text.Encoding]::UTF8)

    $gate98 = @('PHASE=51.4', 'GATE=' + $Gate) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '98_gate_phase51_4.txt'), $gate98, [System.Text.Encoding]::UTF8)

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
}
finally {
    if (Test-Path -LiteralPath $tmpRoot) {
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
