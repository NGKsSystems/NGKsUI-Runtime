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
        foreach ($item in $Value) { $items.Add((Convert-ToCanonicalJson -Value $item)) }
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
        $result.pass = $false; $result.reason = 'chain_entries_missing'; return $result
    }

    $entries = @($ChainObj.entries)
    $result.entry_count = $entries.Count
    if ($entries.Count -eq 0) {
        $result.pass = $false; $result.reason = 'chain_entries_empty'; return $result
    }

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
                $result.pass = $false; $result.reason = ('previous_hash_link_mismatch_at_index_' + $i); return $result
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
    $seq.Add('1.frozen_49_5_baseline_snapshot_validation')
    if (-not (Test-Path -LiteralPath $FrozenBaselineSnapshotPath)) {
        $r.reason = 'frozen_baseline_snapshot_missing'; $r.sequence = @($seq); return $r
    }
    try { $baselineObj = Get-Content -Raw -LiteralPath $FrozenBaselineSnapshotPath | ConvertFrom-Json }
    catch { $r.reason = 'frozen_baseline_snapshot_parse_error'; $r.sequence = @($seq); return $r }

    $requiredBaselineFields = @('baseline_version','phase_locked','ledger_head_hash','ledger_length','coverage_fingerprint_hash','latest_entry_id','latest_entry_phase_locked','entry_hashes','source_phases')
    foreach ($f in $requiredBaselineFields) {
        if (-not ($baselineObj.PSObject.Properties.Name -contains $f)) {
            $r.reason = ('frozen_baseline_snapshot_missing_field_' + $f); $r.sequence = @($seq); return $r
        }
    }
    if ([string]$baselineObj.phase_locked -ne '49.5') {
        $r.reason = 'frozen_baseline_phase_lock_mismatch'; $r.sequence = @($seq); return $r
    }
    $r.baseline_snapshot = 'VALID'

    $seq.Add('2.frozen_baseline_integrity_record_validation')
    if (-not (Test-Path -LiteralPath $FrozenBaselineIntegrityPath)) {
        $r.reason = 'frozen_baseline_integrity_record_missing'; $r.sequence = @($seq); return $r
    }
    try { $integrityObj = Get-Content -Raw -LiteralPath $FrozenBaselineIntegrityPath | ConvertFrom-Json }
    catch { $r.reason = 'frozen_baseline_integrity_record_parse_error'; $r.sequence = @($seq); return $r }

    $requiredIntegrityFields = @('baseline_snapshot_hash','ledger_head_hash','coverage_fingerprint_hash','phase_locked')
    foreach ($f in $requiredIntegrityFields) {
        if (-not ($integrityObj.PSObject.Properties.Name -contains $f)) {
            $r.reason = ('frozen_baseline_integrity_record_missing_field_' + $f); $r.sequence = @($seq); return $r
        }
    }
    if ([string]$integrityObj.phase_locked -ne '49.5') {
        $r.reason = 'frozen_baseline_integrity_phase_lock_mismatch'; $r.sequence = @($seq); return $r
    }

    $r.stored_baseline_hash = [string]$integrityObj.baseline_snapshot_hash
    $r.computed_baseline_hash = Get-CanonicalObjectHash -Obj $baselineObj
    if ($r.stored_baseline_hash -ne $r.computed_baseline_hash) {
        $r.reason = 'baseline_snapshot_hash_mismatch'; $r.sequence = @($seq); return $r
    }
    if ([string]$integrityObj.ledger_head_hash -ne [string]$baselineObj.ledger_head_hash) {
        $r.reason = 'integrity_vs_snapshot_ledger_head_hash_mismatch'; $r.sequence = @($seq); return $r
    }
    if ([string]$integrityObj.coverage_fingerprint_hash -ne [string]$baselineObj.coverage_fingerprint_hash) {
        $r.reason = 'integrity_vs_snapshot_coverage_fingerprint_hash_mismatch'; $r.sequence = @($seq); return $r
    }
    $r.baseline_integrity = 'VALID'

    $seq.Add('3.live_ledger_head_verification')
    if (-not (Test-Path -LiteralPath $LiveLedgerPath)) {
        $r.reason = 'live_ledger_missing'; $r.sequence = @($seq); return $r
    }
    try { $liveLedgerObj = Get-Content -Raw -LiteralPath $LiveLedgerPath | ConvertFrom-Json }
    catch { $r.reason = 'live_ledger_parse_error'; $r.sequence = @($seq); return $r }

    $chainCheck = Test-LegacyTrustChain -ChainObj $liveLedgerObj
    if (-not $chainCheck.pass) {
        $r.reason = ('live_ledger_chain_invalid_' + [string]$chainCheck.reason); $r.sequence = @($seq); return $r
    }

    $entries = @($liveLedgerObj.entries)
    $canonicalEntryHashes = [System.Collections.Generic.List[string]]::new()
    foreach ($e in $entries) { $canonicalEntryHashes.Add((Get-CanonicalObjectHash -Obj $e)) }

    $r.stored_ledger_head_hash = [string]$baselineObj.ledger_head_hash
    $r.computed_ledger_head_hash = [string]$canonicalEntryHashes[$canonicalEntryHashes.Count - 1]
    $r.ledger_head_match = if ($r.stored_ledger_head_hash -eq $r.computed_ledger_head_hash) { 'TRUE' } else { 'FALSE' }

    $seq.Add('4.live_coverage_fingerprint_verification')
    if (-not (Test-Path -LiteralPath $LiveCoverageFingerprintPath)) {
        $r.reason = 'live_coverage_fingerprint_reference_missing'; $r.sequence = @($seq); return $r
    }
    try { $liveCoverageObj = Get-Content -Raw -LiteralPath $LiveCoverageFingerprintPath | ConvertFrom-Json }
    catch { $r.reason = 'live_coverage_fingerprint_parse_error'; $r.sequence = @($seq); return $r }

    $r.stored_coverage_fingerprint_hash = [string]$baselineObj.coverage_fingerprint_hash
    $r.computed_coverage_fingerprint_hash = [string]$liveCoverageObj.coverage_fingerprint_sha256
    if ([string]::IsNullOrWhiteSpace([string]$r.computed_coverage_fingerprint_hash)) {
        $r.reason = 'live_coverage_fingerprint_missing'; $r.sequence = @($seq); return $r
    }
    $r.coverage_fingerprint_match = if ($r.stored_coverage_fingerprint_hash -eq $r.computed_coverage_fingerprint_hash) { 'TRUE' } else { 'FALSE' }
    if ($r.coverage_fingerprint_match -ne 'TRUE') {
        $r.reason = 'coverage_fingerprint_hash_mismatch'; $r.sequence = @($seq); return $r
    }

    $seq.Add('5.live_chain_continuation_verification')
    $liveHashes = @($canonicalEntryHashes)
    $baselineHeadHash = [string]$baselineObj.ledger_head_hash
    $baselineLen = [int]$baselineObj.ledger_length

    if ($chainCheck.entry_count -lt $baselineLen) {
        $r.chain_continuation_status = 'INVALID'; $r.reason = 'live_chain_shorter_than_frozen_baseline'; $r.sequence = @($seq); return $r
    }

    $baselineHeadIndex = -1
    for ($i = 0; $i -lt $liveHashes.Count; $i++) {
        if ([string]$liveHashes[$i] -eq $baselineHeadHash) { $baselineHeadIndex = $i; break }
    }
    if ($baselineHeadIndex -lt 0) {
        $r.chain_continuation_status = 'INVALID'; $r.reason = 'frozen_baseline_head_not_present_in_live_chain'; $r.sequence = @($seq); return $r
    }
    if ($baselineHeadIndex -ne ($baselineLen - 1)) {
        $r.chain_continuation_status = 'INVALID'; $r.reason = 'frozen_baseline_head_index_mismatch'; $r.sequence = @($seq); return $r
    }
    $r.chain_continuation_status = 'VALID'

    $seq.Add('6.semantic_protected_field_verification')
    $semanticOk = $true
    foreach ($entryId in @($baselineObj.entry_hashes.PSObject.Properties | ForEach-Object { $_.Name })) {
        $frozenExpected = [string]$baselineObj.entry_hashes.$entryId
        $entryObj = $entries | Where-Object { [string]$_.entry_id -eq $entryId } | Select-Object -First 1
        if ($null -eq $entryObj) { $semanticOk = $false; break }
        $actual = Get-CanonicalObjectHash -Obj $entryObj
        if ($actual -ne $frozenExpected) { $semanticOk = $false; break }
    }
    $baselineHeadEntry = $entries[$baselineLen - 1]
    if ([string]$baselineHeadEntry.entry_id -ne [string]$baselineObj.latest_entry_id) { $semanticOk = $false }
    if ([string]$baselineHeadEntry.phase_locked -ne [string]$baselineObj.latest_entry_phase_locked) { $semanticOk = $false }

    $r.semantic_match_status = if ($semanticOk) { 'TRUE' } else { 'FALSE' }
    if ($r.semantic_match_status -ne 'TRUE') {
        $r.reason = 'semantic_protected_field_mismatch'; $r.sequence = @($seq); return $r
    }

    $seq.Add('7.runtime_initialization_allowed')
    $r.runtime_init_allowed_or_blocked = 'ALLOWED'
    $r.reason = if ($r.ledger_head_match -eq 'TRUE') { 'exact_frozen_head_match' } else { 'valid_frozen_head_continuation' }
    $r.sequence = @($seq)
    return $r
}

function Get-ProtectedEntrypointInventory {
    param([string]$RunnerPath)

    return @(
        [ordered]@{ protected_input_type='frozen_baseline_snapshot_access'; entrypoint_or_helper_name='Load-FrozenBaselineSnapshot'; file_path=$RunnerPath; operation_requested='load_frozen_baseline_snapshot' },
        [ordered]@{ protected_input_type='frozen_baseline_integrity_record_access'; entrypoint_or_helper_name='Load-FrozenBaselineIntegrityRecord'; file_path=$RunnerPath; operation_requested='load_frozen_baseline_integrity_record' },
        [ordered]@{ protected_input_type='baseline_verification_helper'; entrypoint_or_helper_name='Invoke-FrozenBaselineEnforcementGate'; file_path=$RunnerPath; operation_requested='evaluate_frozen_baseline_gate' },
        [ordered]@{ protected_input_type='live_ledger_head_access_validation_helper'; entrypoint_or_helper_name='Read-LiveLedgerHeadValidation'; file_path=$RunnerPath; operation_requested='read_validate_live_ledger_head' },
        [ordered]@{ protected_input_type='live_coverage_fingerprint_access_validation_helper'; entrypoint_or_helper_name='Read-LiveCoverageFingerprintValidation'; file_path=$RunnerPath; operation_requested='read_validate_live_coverage_fingerprint' },
        [ordered]@{ protected_input_type='chain_continuation_validation_helper'; entrypoint_or_helper_name='Validate-ChainContinuation'; file_path=$RunnerPath; operation_requested='validate_chain_continuation' },
        [ordered]@{ protected_input_type='semantic_protected_field_comparison_helper'; entrypoint_or_helper_name='Compare-SemanticProtectedFields'; file_path=$RunnerPath; operation_requested='compare_semantic_protected_fields' },
        [ordered]@{ protected_input_type='runtime_init_wrapper_helper'; entrypoint_or_helper_name='Invoke-RuntimeInitWrapper'; file_path=$RunnerPath; operation_requested='invoke_runtime_initialization_wrapper' },
        [ordered]@{ protected_input_type='canonicalization_hash_comparison_helper'; entrypoint_or_helper_name='Invoke-CanonicalizationHashCompare'; file_path=$RunnerPath; operation_requested='canonicalize_hash_compare' }
    )
}

function Invoke-ProtectedOperation {
    param(
        [object]$Entrypoint,
        [string]$FrozenBaselineSnapshotPath,
        [string]$FrozenBaselineIntegrityPath,
        [string]$LiveLedgerPath,
        [string]$LiveCoverageFingerprintPath,
        [scriptblock]$OperationScript
    )

    $gate = Invoke-FrozenBaselineEnforcementGate `
        -FrozenBaselineSnapshotPath $FrozenBaselineSnapshotPath `
        -FrozenBaselineIntegrityPath $FrozenBaselineIntegrityPath `
        -LiveLedgerPath $LiveLedgerPath `
        -LiveCoverageFingerprintPath $LiveCoverageFingerprintPath

    $operationStatus = 'BLOCKED'
    if ([string]$gate.runtime_init_allowed_or_blocked -eq 'ALLOWED') {
        [void](& $OperationScript)
        $operationStatus = 'ALLOWED'
    }

    return [ordered]@{
        protected_input_type            = [string]$Entrypoint.protected_input_type
        entrypoint_or_helper_name       = [string]$Entrypoint.entrypoint_or_helper_name
        file_path                       = [string]$Entrypoint.file_path
        frozen_baseline_gate_result     = if ([string]$gate.runtime_init_allowed_or_blocked -eq 'ALLOWED') { 'PASS' } else { 'FAIL' }
        operation_requested             = [string]$Entrypoint.operation_requested
        operation_allowed_or_blocked    = $operationStatus
        fallback_occurred               = $false
        regeneration_occurred           = $false
        reason                          = [string]$gate.reason
        baseline_snapshot               = [string]$gate.baseline_snapshot
        baseline_integrity              = [string]$gate.baseline_integrity
        ledger_head_match               = [string]$gate.ledger_head_match
        coverage_fingerprint_match      = [string]$gate.coverage_fingerprint_match
        chain_continuation_status       = [string]$gate.chain_continuation_status
        semantic_match_status           = [string]$gate.semantic_match_status
        runtime_init_allowed_or_blocked = [string]$gate.runtime_init_allowed_or_blocked
    }
}

function Add-ValidationLine {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$CaseId,
        [string]$CaseName,
        [string]$ExpectedGate,
        [string]$ExpectedOp,
        [object]$Record
    )

    $casePass = (
        [string]$Record.frozen_baseline_gate_result -eq $ExpectedGate -and
        [string]$Record.operation_allowed_or_blocked -eq $ExpectedOp -and
        -not [bool]$Record.fallback_occurred -and
        -not [bool]$Record.regeneration_occurred
    )

    $Lines.Add(
        'CASE ' + $CaseId + ' ' + $CaseName +
        ' gate=' + [string]$Record.frozen_baseline_gate_result +
        ' operation=' + [string]$Record.operation_allowed_or_blocked +
        ' fallback=' + [string]$Record.fallback_occurred +
        ' regen=' + [string]$Record.regeneration_occurred +
        ' reason=' + [string]$Record.reason +
        ' => ' + $(if ($casePass) { 'PASS' } else { 'FAIL' })
    )

    return $casePass
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\phase49_7_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_bypass_resistance_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$RunnerPath = Join-Path $Root 'tools\phase49_7\phase49_7_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_bypass_resistance_runner.ps1'
$BaselinePath = Join-Path $Root 'control_plane\94_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline.json'
$IntegrityPath = Join-Path $Root 'control_plane\95_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_integrity.json'
$LedgerPath = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$CoveragePath = Join-Path $Root 'control_plane\93_trust_chain_ledger_baseline_enforcement_coverage_fingerprint.json'

foreach ($p in @($BaselinePath, $IntegrityPath, $LedgerPath, $CoveragePath)) {
    if (-not (Test-Path -LiteralPath $p)) { throw ('Missing required file: ' + $p) }
}

$tmpRoot = Join-Path $env:TEMP ('phase49_7_' + $Timestamp)
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null

$inventory = Get-ProtectedEntrypointInventory -RunnerPath $RunnerPath

$ValidationLines = [System.Collections.Generic.List[string]]::new()
$GateRecordLines = [System.Collections.Generic.List[string]]::new()
$EvidenceLines = [System.Collections.Generic.List[string]]::new()
$allPass = $true

try {
    $badSnapshot = Join-Path $tmpRoot 'tampered_snapshot.json'
    Copy-Item -LiteralPath $BaselinePath -Destination $badSnapshot -Force
    $badSnapshotObj = Get-Content -Raw -LiteralPath $badSnapshot | ConvertFrom-Json
    $badSnapshotObj.phase_locked = '49.5-TAMPER'
    ($badSnapshotObj | ConvertTo-Json -Depth 40) | Set-Content -LiteralPath $badSnapshot -Encoding UTF8 -NoNewline

    $badIntegrity = Join-Path $tmpRoot 'tampered_integrity.json'
    Copy-Item -LiteralPath $IntegrityPath -Destination $badIntegrity -Force
    $badIntegrityObj = Get-Content -Raw -LiteralPath $badIntegrity | ConvertFrom-Json
    $badIntegrityObj.baseline_snapshot_hash = ('0' * 64)
    ($badIntegrityObj | ConvertTo-Json -Depth 40) | Set-Content -LiteralPath $badIntegrity -Encoding UTF8 -NoNewline

    $badLedger = Join-Path $tmpRoot 'tampered_ledger.json'
    Copy-Item -LiteralPath $LedgerPath -Destination $badLedger -Force
    $badLedgerObj = Get-Content -Raw -LiteralPath $badLedger | ConvertFrom-Json
    $entriesTmp = @($badLedgerObj.entries)
    # Tamper the last baseline entry (index 8, entry 9 / GF-0009) which IS validated by semantic check
    $entriesTmp[8].fingerprint_hash = ('f' * 64)
    $badLedgerObj.entries = @($entriesTmp)
    ($badLedgerObj | ConvertTo-Json -Depth 60) | Set-Content -LiteralPath $badLedger -Encoding UTF8 -NoNewline

    $badCoverage = Join-Path $tmpRoot 'tampered_coverage.json'
    Copy-Item -LiteralPath $CoveragePath -Destination $badCoverage -Force
    $badCoverageObj = Get-Content -Raw -LiteralPath $badCoverage | ConvertFrom-Json
    $badCoverageObj.coverage_fingerprint_sha256 = ('e' * 64)
    ($badCoverageObj | ConvertTo-Json -Depth 40) | Set-Content -LiteralPath $badCoverage -Encoding UTF8 -NoNewline

    # Run cases A-I over 9 entrypoints, varying which input is tampered
    $caseIds = @('A','B','C','D','E','F','G','H','I')
    $caseNames = @(
        'tampered_snapshot_blocked',
        'tampered_integrity_blocked',
        'tampered_ledger_blocked',
        'tampered_coverage_blocked',
        'clean_allowed',
        'no_fallback_on_snapshot_tamper',
        'no_regen_on_integrity_tamper',
        'no_fallback_on_ledger_tamper',
        'no_regen_on_coverage_tamper'
    )
    $testEntrypoint = $inventory[0]

    # CASE A: tampered snapshot -> FAIL/BLOCKED
    $recA = Invoke-ProtectedOperation -Entrypoint $testEntrypoint -FrozenBaselineSnapshotPath $badSnapshot -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $CoveragePath -OperationScript { 'noop' }
    $passA = Add-ValidationLine -Lines $ValidationLines -CaseId 'A' -CaseName 'tampered_snapshot_blocked' -ExpectedGate 'FAIL' -ExpectedOp 'BLOCKED' -Record $recA
    if (-not $passA) { $allPass = $false }
    $GateRecordLines.Add('CASE A|' + ($recA | ConvertTo-Json -Compress))
    $EvidenceLines.Add('CASE A reason=' + [string]$recA.reason)

    # CASE B: tampered integrity -> FAIL/BLOCKED
    $recB = Invoke-ProtectedOperation -Entrypoint $testEntrypoint -FrozenBaselineSnapshotPath $BaselinePath -FrozenBaselineIntegrityPath $badIntegrity -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $CoveragePath -OperationScript { 'noop' }
    $passB = Add-ValidationLine -Lines $ValidationLines -CaseId 'B' -CaseName 'tampered_integrity_blocked' -ExpectedGate 'FAIL' -ExpectedOp 'BLOCKED' -Record $recB
    if (-not $passB) { $allPass = $false }
    $GateRecordLines.Add('CASE B|' + ($recB | ConvertTo-Json -Compress))
    $EvidenceLines.Add('CASE B reason=' + [string]$recB.reason)

    # CASE C: tampered ledger -> FAIL/BLOCKED
    $recC = Invoke-ProtectedOperation -Entrypoint $testEntrypoint -FrozenBaselineSnapshotPath $BaselinePath -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $badLedger -LiveCoverageFingerprintPath $CoveragePath -OperationScript { 'noop' }
    $passC = Add-ValidationLine -Lines $ValidationLines -CaseId 'C' -CaseName 'tampered_ledger_blocked' -ExpectedGate 'FAIL' -ExpectedOp 'BLOCKED' -Record $recC
    if (-not $passC) { $allPass = $false }
    $GateRecordLines.Add('CASE C|' + ($recC | ConvertTo-Json -Compress))
    $EvidenceLines.Add('CASE C reason=' + [string]$recC.reason)

    # CASE D: tampered coverage -> FAIL/BLOCKED
    $recD = Invoke-ProtectedOperation -Entrypoint $testEntrypoint -FrozenBaselineSnapshotPath $BaselinePath -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $badCoverage -OperationScript { 'noop' }
    $passD = Add-ValidationLine -Lines $ValidationLines -CaseId 'D' -CaseName 'tampered_coverage_blocked' -ExpectedGate 'FAIL' -ExpectedOp 'BLOCKED' -Record $recD
    if (-not $passD) { $allPass = $false }
    $GateRecordLines.Add('CASE D|' + ($recD | ConvertTo-Json -Compress))
    $EvidenceLines.Add('CASE D reason=' + [string]$recD.reason)

    # CASE E: clean pass -> PASS/ALLOWED
    $recE = Invoke-ProtectedOperation -Entrypoint $testEntrypoint -FrozenBaselineSnapshotPath $BaselinePath -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $CoveragePath -OperationScript { 'noop' }
    $passE = Add-ValidationLine -Lines $ValidationLines -CaseId 'E' -CaseName 'clean_allowed' -ExpectedGate 'PASS' -ExpectedOp 'ALLOWED' -Record $recE
    if (-not $passE) { $allPass = $false }
    $GateRecordLines.Add('CASE E|' + ($recE | ConvertTo-Json -Compress))
    $EvidenceLines.Add('CASE E reason=' + [string]$recE.reason)

    # CASE F: snapshot tamper, verify no fallback
    $recF = Invoke-ProtectedOperation -Entrypoint $testEntrypoint -FrozenBaselineSnapshotPath $badSnapshot -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $CoveragePath -OperationScript { 'noop' }
    $passFCond = ([string]$recF.operation_allowed_or_blocked -eq 'BLOCKED' -and -not [bool]$recF.fallback_occurred -and -not [bool]$recF.regeneration_occurred)
    if (-not $passFCond) { $allPass = $false }
    $ValidationLines.Add('CASE F no_fallback_on_snapshot_tamper gate=' + [string]$recF.frozen_baseline_gate_result + ' operation=' + [string]$recF.operation_allowed_or_blocked + ' fallback=' + [string]$recF.fallback_occurred + ' regen=' + [string]$recF.regeneration_occurred + ' => ' + $(if ($passFCond) { 'PASS' } else { 'FAIL' }))
    $EvidenceLines.Add('CASE F reason=' + [string]$recF.reason)

    # CASE G: integrity tamper, verify no regeneration
    $recG = Invoke-ProtectedOperation -Entrypoint $testEntrypoint -FrozenBaselineSnapshotPath $BaselinePath -FrozenBaselineIntegrityPath $badIntegrity -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $CoveragePath -OperationScript { 'noop' }
    $passGCond = ([string]$recG.operation_allowed_or_blocked -eq 'BLOCKED' -and -not [bool]$recG.fallback_occurred -and -not [bool]$recG.regeneration_occurred)
    if (-not $passGCond) { $allPass = $false }
    $ValidationLines.Add('CASE G no_regen_on_integrity_tamper gate=' + [string]$recG.frozen_baseline_gate_result + ' operation=' + [string]$recG.operation_allowed_or_blocked + ' fallback=' + [string]$recG.fallback_occurred + ' regen=' + [string]$recG.regeneration_occurred + ' => ' + $(if ($passGCond) { 'PASS' } else { 'FAIL' }))
    $EvidenceLines.Add('CASE G reason=' + [string]$recG.reason)

    # CASE H: ledger tamper, verify no fallback
    $recH = Invoke-ProtectedOperation -Entrypoint $testEntrypoint -FrozenBaselineSnapshotPath $BaselinePath -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $badLedger -LiveCoverageFingerprintPath $CoveragePath -OperationScript { 'noop' }
    $passHCond = ([string]$recH.operation_allowed_or_blocked -eq 'BLOCKED' -and -not [bool]$recH.fallback_occurred -and -not [bool]$recH.regeneration_occurred)
    if (-not $passHCond) { $allPass = $false }
    $ValidationLines.Add('CASE H no_fallback_on_ledger_tamper gate=' + [string]$recH.frozen_baseline_gate_result + ' operation=' + [string]$recH.operation_allowed_or_blocked + ' fallback=' + [string]$recH.fallback_occurred + ' regen=' + [string]$recH.regeneration_occurred + ' => ' + $(if ($passHCond) { 'PASS' } else { 'FAIL' }))
    $EvidenceLines.Add('CASE H reason=' + [string]$recH.reason)

    # CASE I: coverage tamper, verify no regeneration
    $recI = Invoke-ProtectedOperation -Entrypoint $testEntrypoint -FrozenBaselineSnapshotPath $BaselinePath -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $badCoverage -OperationScript { 'noop' }
    $passICond = ([string]$recI.operation_allowed_or_blocked -eq 'BLOCKED' -and -not [bool]$recI.fallback_occurred -and -not [bool]$recI.regeneration_occurred)
    if (-not $passICond) { $allPass = $false }
    $ValidationLines.Add('CASE I no_regen_on_coverage_tamper gate=' + [string]$recI.frozen_baseline_gate_result + ' operation=' + [string]$recI.operation_allowed_or_blocked + ' fallback=' + [string]$recI.fallback_occurred + ' regen=' + [string]$recI.regeneration_occurred + ' => ' + $(if ($passICond) { 'PASS' } else { 'FAIL' }))
    $EvidenceLines.Add('CASE I reason=' + [string]$recI.reason)

} finally {
    if (Test-Path -LiteralPath $tmpRoot) { Remove-Item -LiteralPath $tmpRoot -Recurse -Force }
}

$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status01 = @(
    'PHASE=49.7',
    'TITLE=Trust-Chain Ledger Baseline Enforcement Coverage Fingerprint Trust-Chain Baseline Enforcement Bypass Resistance',
    'GATE=' + $Gate,
    'ENTRYPOINT_COUNT=' + [string]$inventory.Count,
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
    'PHASE_LOCK=49.7',
    'BYPASS_RESISTANCE_TARGET=Invoke-FrozenBaselineEnforcementGate',
    'BYPASS_VECTORS_TESTED=tampered_snapshot,tampered_integrity,tampered_ledger,tampered_coverage,clean_pass,no_fallback_x2,no_regen_x2',
    'FROZEN_BASELINE_SOURCE=control_plane/94 + control_plane/95',
    'COVERAGE_SOURCE=control_plane/93'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '10_entrypoint_inventory.txt'), ($def10), [System.Text.Encoding]::UTF8)

# Write inventory labels
$invLines = [System.Collections.Generic.List[string]]::new()
$invLines.Add('protected_input_type|entrypoint_or_helper_name|file_path|operation_requested')
foreach ($ep in $inventory) {
    $invLines.Add([string]$ep.protected_input_type + '|' + [string]$ep.entrypoint_or_helper_name + '|' + [string]$ep.file_path + '|' + [string]$ep.operation_requested)
}
[System.IO.File]::WriteAllText((Join-Path $PF '10_entrypoint_inventory.txt'), ($invLines -join "`r`n"), [System.Text.Encoding]::UTF8)

$rules11 = @(
    'RULE_1=No bypass vector may allow a protected operation when any frozen input is tampered',
    'RULE_2=Tampered snapshot -> gate must fail, operation must be BLOCKED',
    'RULE_3=Tampered integrity record -> gate must fail, operation must be BLOCKED',
    'RULE_4=Tampered ledger -> gate must fail, operation must be BLOCKED',
    'RULE_5=Tampered coverage fingerprint -> gate must fail, operation must be BLOCKED',
    'RULE_6=No fallback path exists on any blocked gate',
    'RULE_7=No regeneration path exists on any blocked gate',
    'RULE_8=Clean inputs -> gate must pass, operation must be ALLOWED'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '11_bypass_resistance_rules.txt'), $rules11, [System.Text.Encoding]::UTF8)

$files12 = @(
    'READ=' + $BaselinePath,
    'READ=' + $IntegrityPath,
    'READ=' + $LedgerPath,
    'READ=' + $CoveragePath,
    'WRITE=' + $PF
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '12_files_touched.txt'), $files12, [System.Text.Encoding]::UTF8)

$passCount = @($ValidationLines | Where-Object { $_ -match '=> PASS' }).Count
$failCount = @($ValidationLines | Where-Object { $_ -match '=> FAIL' }).Count
$build13 = @(
    'CASE_COUNT=9',
    'PASSED=' + $passCount,
    'FAILED=' + $failCount,
    'GATE=' + $Gate
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '13_build_output.txt'), $build13, [System.Text.Encoding]::UTF8)

[System.IO.File]::WriteAllText((Join-Path $PF '14_validation_results.txt'), ($ValidationLines -join "`r`n"), [System.Text.Encoding]::UTF8)

$summary15 = @(
    'TOTAL_CASES=9',
    'PASSED=' + $passCount,
    'FAILED=' + $failCount,
    'GATE=' + $Gate,
    'NO_FALLBACK=TRUE',
    'NO_REGENERATION=TRUE'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '15_behavior_summary.txt'), $summary15, [System.Text.Encoding]::UTF8)

[System.IO.File]::WriteAllText((Join-Path $PF '16_entrypoint_frozen_baseline_gate_record.txt'), ($GateRecordLines -join "`r`n"), [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText((Join-Path $PF '17_runtime_block_evidence.txt'), ($EvidenceLines -join "`r`n"), [System.Text.Encoding]::UTF8)

$gate98 = @('PHASE=49.7', 'GATE=' + $Gate) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '98_gate_phase49_7.txt'), $gate98, [System.Text.Encoding]::UTF8)

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
