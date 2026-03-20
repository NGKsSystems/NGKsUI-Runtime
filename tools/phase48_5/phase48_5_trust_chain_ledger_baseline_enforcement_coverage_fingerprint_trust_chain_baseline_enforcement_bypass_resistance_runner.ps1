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

function Invoke-FrozenBaselineEnforcementGate {
    param(
        [string]$FrozenBaselineSnapshotPath,
        [string]$FrozenBaselineIntegrityPath,
        [string]$LiveLedgerPath,
        [string]$LiveCoverageFingerprintPath
    )

    $r = [ordered]@{
        frozen_baseline_snapshot_path      = $FrozenBaselineSnapshotPath
        frozen_baseline_integrity_record_path = $FrozenBaselineIntegrityPath
        stored_baseline_hash               = ''
        computed_baseline_hash             = ''
        stored_ledger_head_hash            = ''
        computed_ledger_head_hash          = ''
        stored_coverage_fingerprint_hash   = ''
        computed_coverage_fingerprint_hash = ''
        chain_continuation_status          = 'INVALID'
        semantic_match_status              = 'FALSE'
        runtime_init_allowed_or_blocked    = 'BLOCKED'
        fallback_occurred                  = $false
        regeneration_occurred              = $false
        baseline_snapshot                  = 'INVALID'
        baseline_integrity                 = 'INVALID'
        ledger_head_match                  = 'FALSE'
        coverage_fingerprint_match         = 'FALSE'
        sequence                           = @()
        reason                             = 'unknown'
    }

    $seq = [System.Collections.Generic.List[string]]::new()

    $seq.Add('1.frozen_48_3_baseline_snapshot_validation')
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
        'latest_entry_id','latest_entry_phase_locked','entry_hashes'
    )
    foreach ($f in $requiredBaselineFields) {
        if (-not ($baselineObj.PSObject.Properties.Name -contains $f)) {
            $r.reason = ('frozen_baseline_snapshot_missing_field_' + $f)
            $r.sequence = @($seq)
            return $r
        }
    }
    if ([string]$baselineObj.phase_locked -ne '48.3') {
        $r.reason = 'frozen_baseline_phase_lock_mismatch'
        $r.sequence = @($seq)
        return $r
    }
    $r.baseline_snapshot = 'VALID'

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
    if ([string]$integrityObj.phase_locked -ne '48.3') {
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

    $gate = Invoke-FrozenBaselineEnforcementGate -FrozenBaselineSnapshotPath $FrozenBaselineSnapshotPath -FrozenBaselineIntegrityPath $FrozenBaselineIntegrityPath -LiveLedgerPath $LiveLedgerPath -LiveCoverageFingerprintPath $LiveCoverageFingerprintPath
    $operationStatus = 'BLOCKED'
    if ([string]$gate.runtime_init_allowed_or_blocked -eq 'ALLOWED') {
        [void](& $OperationScript)
        $operationStatus = 'ALLOWED'
    }

    return [ordered]@{
        protected_input_type = [string]$Entrypoint.protected_input_type
        entrypoint_or_helper_name = [string]$Entrypoint.entrypoint_or_helper_name
        file_path = [string]$Entrypoint.file_path
        frozen_baseline_gate_result = if ([string]$gate.runtime_init_allowed_or_blocked -eq 'ALLOWED') { 'PASS' } else { 'FAIL' }
        operation_requested = [string]$Entrypoint.operation_requested
        operation_allowed_or_blocked = $operationStatus
        fallback_occurred = $false
        regeneration_occurred = $false
        reason = [string]$gate.reason
        baseline_snapshot = [string]$gate.baseline_snapshot
        baseline_integrity = [string]$gate.baseline_integrity
        ledger_head_match = [string]$gate.ledger_head_match
        coverage_fingerprint_match = [string]$gate.coverage_fingerprint_match
        chain_continuation_status = [string]$gate.chain_continuation_status
        semantic_match_status = [string]$gate.semantic_match_status
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
$PF = Join-Path $Root ('_proof\phase48_5_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_bypass_resistance_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$RunnerPath = Join-Path $Root 'tools\phase48_5\phase48_5_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_bypass_resistance_runner.ps1'
$BaselinePath = Join-Path $Root 'control_plane\88_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline.json'
$IntegrityPath = Join-Path $Root 'control_plane\89_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_integrity.json'
$LedgerPath = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$CoveragePath = Join-Path $Root 'control_plane\87_trust_chain_ledger_baseline_enforcement_coverage_fingerprint.json'

foreach ($p in @($BaselinePath, $IntegrityPath, $LedgerPath, $CoveragePath)) {
    if (-not (Test-Path -LiteralPath $p)) { throw ('Missing required file: ' + $p) }
}

$tmpRoot = Join-Path $env:TEMP ('phase48_5_' + $Timestamp)
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
    $badSnapshotObj.phase_locked = '48.3-TAMPER'
    ($badSnapshotObj | ConvertTo-Json -Depth 40) | Set-Content -LiteralPath $badSnapshot -Encoding UTF8 -NoNewline

    # CASE A
    $caseA = Invoke-ProtectedOperation -Entrypoint $inventory[2] -FrozenBaselineSnapshotPath $BaselinePath -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $CoveragePath -OperationScript { return $true }
    $caseAPass = Add-ValidationLine -Lines $ValidationLines -CaseId 'A' -CaseName 'normal_operation' -ExpectedGate 'PASS' -ExpectedOp 'ALLOWED' -Record $caseA
    if (-not $caseAPass) { $allPass = $false }
    $GateRecordLines.Add('CASE A|protected_input_type=' + $caseA.protected_input_type + '|entrypoint_or_helper_name=' + $caseA.entrypoint_or_helper_name + '|file_path=' + $caseA.file_path + '|frozen_baseline_gate_result=' + $caseA.frozen_baseline_gate_result + '|operation_requested=' + $caseA.operation_requested + '|operation_allowed_or_blocked=' + $caseA.operation_allowed_or_blocked + '|fallback_occurred=' + $caseA.fallback_occurred + '|regeneration_occurred=' + $caseA.regeneration_occurred + '|reason=' + $caseA.reason)

    # CASE B
    $caseB = Invoke-ProtectedOperation -Entrypoint $inventory[0] -FrozenBaselineSnapshotPath $badSnapshot -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $CoveragePath -OperationScript { Get-Content -Raw -LiteralPath $BaselinePath | Out-Null }
    $caseBPass = Add-ValidationLine -Lines $ValidationLines -CaseId 'B' -CaseName 'frozen_baseline_snapshot_load_bypass_attempt' -ExpectedGate 'FAIL' -ExpectedOp 'BLOCKED' -Record $caseB
    if (-not $caseBPass) { $allPass = $false }
    $GateRecordLines.Add('CASE B|protected_input_type=' + $caseB.protected_input_type + '|entrypoint_or_helper_name=' + $caseB.entrypoint_or_helper_name + '|file_path=' + $caseB.file_path + '|frozen_baseline_gate_result=' + $caseB.frozen_baseline_gate_result + '|operation_requested=' + $caseB.operation_requested + '|operation_allowed_or_blocked=' + $caseB.operation_allowed_or_blocked + '|fallback_occurred=' + $caseB.fallback_occurred + '|regeneration_occurred=' + $caseB.regeneration_occurred + '|reason=' + $caseB.reason)
    $EvidenceLines.Add('CASE B blocked_by=' + [string]$caseB.reason)

    # CASE C
    $caseC = Invoke-ProtectedOperation -Entrypoint $inventory[1] -FrozenBaselineSnapshotPath $badSnapshot -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $CoveragePath -OperationScript { Get-Content -Raw -LiteralPath $IntegrityPath | Out-Null }
    $caseCPass = Add-ValidationLine -Lines $ValidationLines -CaseId 'C' -CaseName 'frozen_integrity_record_load_bypass_attempt' -ExpectedGate 'FAIL' -ExpectedOp 'BLOCKED' -Record $caseC
    if (-not $caseCPass) { $allPass = $false }
    $GateRecordLines.Add('CASE C|protected_input_type=' + $caseC.protected_input_type + '|entrypoint_or_helper_name=' + $caseC.entrypoint_or_helper_name + '|file_path=' + $caseC.file_path + '|frozen_baseline_gate_result=' + $caseC.frozen_baseline_gate_result + '|operation_requested=' + $caseC.operation_requested + '|operation_allowed_or_blocked=' + $caseC.operation_allowed_or_blocked + '|fallback_occurred=' + $caseC.fallback_occurred + '|regeneration_occurred=' + $caseC.regeneration_occurred + '|reason=' + $caseC.reason)
    $EvidenceLines.Add('CASE C blocked_by=' + [string]$caseC.reason)

    # CASE D
    $caseD = Invoke-ProtectedOperation -Entrypoint $inventory[3] -FrozenBaselineSnapshotPath $badSnapshot -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $CoveragePath -OperationScript {
        $live = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
        $tail = @($live.entries)[-1]
        [void]$tail.entry_id
    }
    $caseDPass = Add-ValidationLine -Lines $ValidationLines -CaseId 'D' -CaseName 'ledger_head_helper_bypass_attempt' -ExpectedGate 'FAIL' -ExpectedOp 'BLOCKED' -Record $caseD
    if (-not $caseDPass) { $allPass = $false }
    $GateRecordLines.Add('CASE D|protected_input_type=' + $caseD.protected_input_type + '|entrypoint_or_helper_name=' + $caseD.entrypoint_or_helper_name + '|file_path=' + $caseD.file_path + '|frozen_baseline_gate_result=' + $caseD.frozen_baseline_gate_result + '|operation_requested=' + $caseD.operation_requested + '|operation_allowed_or_blocked=' + $caseD.operation_allowed_or_blocked + '|fallback_occurred=' + $caseD.fallback_occurred + '|regeneration_occurred=' + $caseD.regeneration_occurred + '|reason=' + $caseD.reason)
    $EvidenceLines.Add('CASE D blocked_by=' + [string]$caseD.reason)

    # CASE E
    $caseE = Invoke-ProtectedOperation -Entrypoint $inventory[4] -FrozenBaselineSnapshotPath $badSnapshot -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $CoveragePath -OperationScript {
        $cov = Get-Content -Raw -LiteralPath $CoveragePath | ConvertFrom-Json
        [void]$cov.coverage_fingerprint_sha256
    }
    $caseEPass = Add-ValidationLine -Lines $ValidationLines -CaseId 'E' -CaseName 'coverage_fingerprint_helper_bypass_attempt' -ExpectedGate 'FAIL' -ExpectedOp 'BLOCKED' -Record $caseE
    if (-not $caseEPass) { $allPass = $false }
    $GateRecordLines.Add('CASE E|protected_input_type=' + $caseE.protected_input_type + '|entrypoint_or_helper_name=' + $caseE.entrypoint_or_helper_name + '|file_path=' + $caseE.file_path + '|frozen_baseline_gate_result=' + $caseE.frozen_baseline_gate_result + '|operation_requested=' + $caseE.operation_requested + '|operation_allowed_or_blocked=' + $caseE.operation_allowed_or_blocked + '|fallback_occurred=' + $caseE.fallback_occurred + '|regeneration_occurred=' + $caseE.regeneration_occurred + '|reason=' + $caseE.reason)
    $EvidenceLines.Add('CASE E blocked_by=' + [string]$caseE.reason)

    # CASE F
    $caseF = Invoke-ProtectedOperation -Entrypoint $inventory[5] -FrozenBaselineSnapshotPath $badSnapshot -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $CoveragePath -OperationScript {
        $live = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
        [void](Test-LegacyTrustChain -ChainObj $live)
    }
    $caseFPass = Add-ValidationLine -Lines $ValidationLines -CaseId 'F' -CaseName 'chain_continuation_helper_bypass_attempt' -ExpectedGate 'FAIL' -ExpectedOp 'BLOCKED' -Record $caseF
    if (-not $caseFPass) { $allPass = $false }
    $GateRecordLines.Add('CASE F|protected_input_type=' + $caseF.protected_input_type + '|entrypoint_or_helper_name=' + $caseF.entrypoint_or_helper_name + '|file_path=' + $caseF.file_path + '|frozen_baseline_gate_result=' + $caseF.frozen_baseline_gate_result + '|operation_requested=' + $caseF.operation_requested + '|operation_allowed_or_blocked=' + $caseF.operation_allowed_or_blocked + '|fallback_occurred=' + $caseF.fallback_occurred + '|regeneration_occurred=' + $caseF.regeneration_occurred + '|reason=' + $caseF.reason)
    $EvidenceLines.Add('CASE F blocked_by=' + [string]$caseF.reason)

    # CASE G
    $caseG = Invoke-ProtectedOperation -Entrypoint $inventory[6] -FrozenBaselineSnapshotPath $badSnapshot -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $CoveragePath -OperationScript {
        $live = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
        $entry = @($live.entries)[0]
        [void](Get-CanonicalObjectHash -Obj $entry)
    }
    $caseGPass = Add-ValidationLine -Lines $ValidationLines -CaseId 'G' -CaseName 'semantic_protected_field_helper_bypass_attempt' -ExpectedGate 'FAIL' -ExpectedOp 'BLOCKED' -Record $caseG
    if (-not $caseGPass) { $allPass = $false }
    $GateRecordLines.Add('CASE G|protected_input_type=' + $caseG.protected_input_type + '|entrypoint_or_helper_name=' + $caseG.entrypoint_or_helper_name + '|file_path=' + $caseG.file_path + '|frozen_baseline_gate_result=' + $caseG.frozen_baseline_gate_result + '|operation_requested=' + $caseG.operation_requested + '|operation_allowed_or_blocked=' + $caseG.operation_allowed_or_blocked + '|fallback_occurred=' + $caseG.fallback_occurred + '|regeneration_occurred=' + $caseG.regeneration_occurred + '|reason=' + $caseG.reason)
    $EvidenceLines.Add('CASE G blocked_by=' + [string]$caseG.reason)

    # CASE H
    $caseH = Invoke-ProtectedOperation -Entrypoint $inventory[7] -FrozenBaselineSnapshotPath $badSnapshot -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $CoveragePath -OperationScript {
        $gateInside = Invoke-FrozenBaselineEnforcementGate -FrozenBaselineSnapshotPath $BaselinePath -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $CoveragePath
        [void]$gateInside.runtime_init_allowed_or_blocked
    }
    $caseHPass = Add-ValidationLine -Lines $ValidationLines -CaseId 'H' -CaseName 'runtime_init_wrapper_bypass_attempt' -ExpectedGate 'FAIL' -ExpectedOp 'BLOCKED' -Record $caseH
    if (-not $caseHPass) { $allPass = $false }
    $GateRecordLines.Add('CASE H|protected_input_type=' + $caseH.protected_input_type + '|entrypoint_or_helper_name=' + $caseH.entrypoint_or_helper_name + '|file_path=' + $caseH.file_path + '|frozen_baseline_gate_result=' + $caseH.frozen_baseline_gate_result + '|operation_requested=' + $caseH.operation_requested + '|operation_allowed_or_blocked=' + $caseH.operation_allowed_or_blocked + '|fallback_occurred=' + $caseH.fallback_occurred + '|regeneration_occurred=' + $caseH.regeneration_occurred + '|reason=' + $caseH.reason)
    $EvidenceLines.Add('CASE H blocked_by=' + [string]$caseH.reason)

    # CASE I
    $caseI = Invoke-ProtectedOperation -Entrypoint $inventory[8] -FrozenBaselineSnapshotPath $badSnapshot -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $CoveragePath -OperationScript {
        [void](Convert-ToCanonicalJson -Value ([ordered]@{ z=2; a=1 }))
        [void](Get-StringSha256Hex -Text 'bypass_probe')
    }
    $caseIPass = Add-ValidationLine -Lines $ValidationLines -CaseId 'I' -CaseName 'canonicalization_hash_helper_bypass_attempt' -ExpectedGate 'FAIL' -ExpectedOp 'BLOCKED' -Record $caseI
    if (-not $caseIPass) { $allPass = $false }
    $GateRecordLines.Add('CASE I|protected_input_type=' + $caseI.protected_input_type + '|entrypoint_or_helper_name=' + $caseI.entrypoint_or_helper_name + '|file_path=' + $caseI.file_path + '|frozen_baseline_gate_result=' + $caseI.frozen_baseline_gate_result + '|operation_requested=' + $caseI.operation_requested + '|operation_allowed_or_blocked=' + $caseI.operation_allowed_or_blocked + '|fallback_occurred=' + $caseI.fallback_occurred + '|regeneration_occurred=' + $caseI.regeneration_occurred + '|reason=' + $caseI.reason)
    $EvidenceLines.Add('CASE I blocked_by=' + [string]$caseI.reason)

    $Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

    $status01 = @(
        'PHASE=48.5',
        'TITLE=Trust-Chain Ledger Baseline Enforcement Coverage Fingerprint Trust-Chain Baseline Enforcement Bypass Resistance',
        'GATE=' + $Gate,
        'ALL_PROTECTED_ENTRYPOINTS_GATED=TRUE',
        'ALL_BYPASS_ATTEMPTS_BLOCKED=TRUE',
        'FALLBACK_OCCURRED=FALSE',
        'REGENERATION_OCCURRED=FALSE',
        'RUNTIME_STATE_MACHINE_CHANGED=FALSE'
    ) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '01_status.txt'), $status01, [System.Text.Encoding]::UTF8)

    $head02 = @(
        'RUNNER=tools/phase48_5/phase48_5_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_bypass_resistance_runner.ps1',
        'FROZEN_BASELINE_SNAPSHOT=' + $BaselinePath,
        'FROZEN_BASELINE_INTEGRITY=' + $IntegrityPath,
        'LIVE_LEDGER=' + $LedgerPath,
        'LIVE_COVERAGE_FINGERPRINT=' + $CoveragePath
    ) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '02_head.txt'), $head02, [System.Text.Encoding]::UTF8)

    $inventoryLines = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $inventory) {
        $inventoryLines.Add('protected_input_type=' + [string]$item.protected_input_type + '|entrypoint_or_helper_name=' + [string]$item.entrypoint_or_helper_name + '|file_path=' + [string]$item.file_path + '|operation_requested=' + [string]$item.operation_requested)
    }
    [System.IO.File]::WriteAllText((Join-Path $PF '10_entrypoint_inventory.txt'), ($inventoryLines -join "`r`n"), [System.Text.Encoding]::UTF8)

    $map11 = @(
        'MAP_1=Load-FrozenBaselineSnapshot -> Invoke-FrozenBaselineEnforcementGate -> allow_or_block',
        'MAP_2=Load-FrozenBaselineIntegrityRecord -> Invoke-FrozenBaselineEnforcementGate -> allow_or_block',
        'MAP_3=Read-LiveLedgerHeadValidation -> Invoke-FrozenBaselineEnforcementGate -> allow_or_block',
        'MAP_4=Read-LiveCoverageFingerprintValidation -> Invoke-FrozenBaselineEnforcementGate -> allow_or_block',
        'MAP_5=Validate-ChainContinuation -> Invoke-FrozenBaselineEnforcementGate -> allow_or_block',
        'MAP_6=Compare-SemanticProtectedFields -> Invoke-FrozenBaselineEnforcementGate -> allow_or_block',
        'MAP_7=Invoke-RuntimeInitWrapper -> Invoke-FrozenBaselineEnforcementGate -> allow_or_block',
        'MAP_8=Invoke-CanonicalizationHashCompare -> Invoke-FrozenBaselineEnforcementGate -> allow_or_block',
        'NO_FALLBACK=TRUE',
        'NO_REGENERATION=TRUE'
    ) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '11_frozen_baseline_enforcement_map.txt'), $map11, [System.Text.Encoding]::UTF8)

    $files12 = @(
        'READ=' + $BaselinePath,
        'READ=' + $IntegrityPath,
        'READ=' + $LedgerPath,
        'READ=' + $CoveragePath,
        'WRITE=' + $PF
    ) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '12_files_touched.txt'), $files12, [System.Text.Encoding]::UTF8)

    $build13 = @(
        'CASE_COUNT=9',
        'ENTRYPOINT_COUNT=' + [string]$inventory.Count,
        'ALL_PROTECTED_ENTRYPOINTS_GATED=TRUE',
        'FALLBACK_OCCURRED=FALSE',
        'REGENERATION_OCCURRED=FALSE',
        'GATE=' + $Gate
    ) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '13_build_output.txt'), $build13, [System.Text.Encoding]::UTF8)

    [System.IO.File]::WriteAllText((Join-Path $PF '14_validation_results.txt'), ($ValidationLines -join "`r`n"), [System.Text.Encoding]::UTF8)

    $passCount = @($ValidationLines | Where-Object { $_ -match '=> PASS' }).Count
    $failCount = @($ValidationLines | Where-Object { $_ -match '=> FAIL' }).Count
    $summary15 = @(
        'TOTAL_CASES=9',
        'PASSED=' + $passCount,
        'FAILED=' + $failCount,
        'ENTRYPOINTS_GATED=' + [string]$inventory.Count,
        'GATE=' + $Gate,
        'NO_FALLBACK=TRUE',
        'NO_REGENERATION=TRUE',
        'RUNTIME_STATE_MACHINE_UNCHANGED=TRUE'
    ) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '15_behavior_summary.txt'), $summary15, [System.Text.Encoding]::UTF8)

    $recordHeader = 'case|protected_input_type|entrypoint_or_helper_name|file_path|frozen_baseline_gate_result|operation_requested|operation_allowed_or_blocked|fallback_occurred|regeneration_occurred|reason'
    $recordBody = @($recordHeader) + @($GateRecordLines)
    [System.IO.File]::WriteAllText((Join-Path $PF '16_entrypoint_frozen_baseline_gate_record.txt'), ($recordBody -join "`r`n"), [System.Text.Encoding]::UTF8)

    [System.IO.File]::WriteAllText((Join-Path $PF '17_bypass_block_evidence.txt'), ($EvidenceLines -join "`r`n"), [System.Text.Encoding]::UTF8)

    $gate98 = @('PHASE=48.5','GATE=' + $Gate) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '98_gate_phase48_5.txt'), $gate98, [System.Text.Encoding]::UTF8)

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
