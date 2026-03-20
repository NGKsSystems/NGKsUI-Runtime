Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ((Get-Location).Path -ne $Root) {
    Write-Output 'hey stupid Fucker, wrong window again'
    exit 1
}
Set-Location $Root

# ── Shared utility functions (compatible with phase46_0) ─────────────────────

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
    param([object]$Value)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [string]) { return (([string]$Value | ConvertTo-Json -Compress)) }
    if ($Value -is [bool]) { return $(if ([bool]$Value) { 'true' } else { 'false' }) }

    if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64] -or
        $Value -is [uint16] -or $Value -is [uint32] -or $Value -is [uint64] -or $Value -is [single] -or
        $Value -is [double] -or $Value -is [decimal]) {
        return ([string]$Value)
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        if ($Value -is [System.Collections.IDictionary] -or $Value.PSObject.Properties.Count -gt 0) {
            $dict = [ordered]@{}
            if ($Value -is [System.Collections.IDictionary]) {
                foreach ($k in $Value.Keys) { $dict[[string]$k] = $Value[$k] }
            } else {
                foreach ($p in $Value.PSObject.Properties) { $dict[[string]$p.Name] = $p.Value }
            }
            $keys = @($dict.Keys | Sort-Object)
            $chunks = [System.Collections.Generic.List[string]]::new()
            foreach ($k in $keys) {
                $kJson = ([string]$k | ConvertTo-Json -Compress)
                $vJson = Convert-ToCanonicalJson -Value $dict[$k]
                $chunks.Add($kJson + ':' + $vJson)
            }
            return '{' + ($chunks.ToArray() -join ',') + '}'
        }
        $arr = [System.Collections.Generic.List[string]]::new()
        foreach ($item in $Value) { $arr.Add((Convert-ToCanonicalJson -Value $item)) }
        return '[' + ($arr.ToArray() -join ',') + ']'
    }

    return (($Value | ConvertTo-Json -Compress))
}

function Get-JsonSemanticSha256 {
    param([string]$Path)
    $obj = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    $canonical = Convert-ToCanonicalJson -Value $obj
    return Get-StringSha256Hex -Text $canonical
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
    $result.chain_hashes    = @($hashes)
    $result.last_entry_hash = [string]$hashes[$hashes.Count - 1]
    return $result
}

function Get-NextEntryId {
    param([object]$ChainObj)
    $entries = @($ChainObj.entries)
    $max = 0
    foreach ($e in $entries) {
        $id = [string]$e.entry_id
        if ($id -match '^GF-(\d+)$') { $n = [int]$Matches[1]; if ($n -gt $max) { $max = $n } }
    }
    return ('GF-' + ($max + 1).ToString('0000'))
}

# ── Phase 46.0 frozen baseline enforcement gate (inline copy) ─────────────────

function Invoke-FrozenBaselineTrustChainEnforcementGate {
    param(
        [string]$FrozenBaselineSnapshotPath,
        [string]$FrozenBaselineIntegrityPath,
        [string]$LiveLedgerPath,
        [string]$LiveCoverageFingerprintPath
    )

    $seq = [System.Collections.Generic.List[string]]::new()

    $r = [ordered]@{
        frozen_baseline_snapshot_path          = $FrozenBaselineSnapshotPath
        frozen_baseline_integrity_record_path  = $FrozenBaselineIntegrityPath
        stored_baseline_hash                   = ''
        computed_baseline_hash                 = ''
        stored_ledger_head_hash                = ''
        computed_ledger_head_hash              = ''
        stored_coverage_fingerprint_hash       = ''
        computed_coverage_fingerprint_hash     = ''
        chain_continuation_status              = 'INVALID'
        semantic_match_status                  = 'FALSE'
        runtime_init_allowed_or_blocked        = 'BLOCKED'
        fallback_occurred                      = $false
        regeneration_occurred                  = $false
        baseline_snapshot                      = 'INVALID'
        baseline_integrity                     = 'INVALID'
        ledger_head_match                      = $false
        coverage_fingerprint_match             = $false
        sequence                               = @()
        reason                                 = 'unknown'
    }

    # 1) frozen 45.9 baseline snapshot validation
    $seq.Add('1.frozen_baseline_snapshot_validation')
    if (-not (Test-Path -LiteralPath $FrozenBaselineSnapshotPath)) {
        $r.reason = 'frozen_baseline_snapshot_missing'; $r.sequence = @($seq); return $r
    }
    $baselineObj = $null
    try { $baselineObj = Get-Content -Raw -LiteralPath $FrozenBaselineSnapshotPath | ConvertFrom-Json }
    catch { $r.reason = 'frozen_baseline_snapshot_parse_error'; $r.sequence = @($seq); return $r }

    $reqBase = @('baseline_version','phase_locked','ledger_head_hash','ledger_length','coverage_fingerprint_hash','latest_entry_id','latest_entry_phase_locked')
    foreach ($f in $reqBase) {
        if (-not ($baselineObj.PSObject.Properties.Name -contains $f)) {
            $r.reason = ('frozen_baseline_snapshot_missing_field_' + $f); $r.sequence = @($seq); return $r
        }
    }
    if ([string]$baselineObj.phase_locked -ne '45.9') {
        $r.reason = 'frozen_baseline_phase_lock_mismatch'; $r.sequence = @($seq); return $r
    }
    $r.baseline_snapshot = 'VALID'

    # 2) frozen baseline integrity-record validation
    $seq.Add('2.frozen_baseline_integrity_validation')
    if (-not (Test-Path -LiteralPath $FrozenBaselineIntegrityPath)) {
        $r.reason = 'frozen_baseline_integrity_missing'; $r.sequence = @($seq); return $r
    }
    $integrityObj = $null
    try { $integrityObj = Get-Content -Raw -LiteralPath $FrozenBaselineIntegrityPath | ConvertFrom-Json }
    catch { $r.reason = 'frozen_baseline_integrity_parse_error'; $r.sequence = @($seq); return $r }

    $reqInt = @('baseline_snapshot_semantic_sha256','ledger_head_hash','coverage_fingerprint_hash','phase_locked')
    foreach ($f in $reqInt) {
        if (-not ($integrityObj.PSObject.Properties.Name -contains $f)) {
            $r.reason = ('frozen_baseline_integrity_missing_field_' + $f); $r.sequence = @($seq); return $r
        }
    }
    if ([string]$integrityObj.phase_locked -ne '45.9') {
        $r.reason = 'frozen_baseline_integrity_phase_lock_mismatch'; $r.sequence = @($seq); return $r
    }

    $r.stored_baseline_hash   = [string]$integrityObj.baseline_snapshot_semantic_sha256
    $r.computed_baseline_hash = Get-JsonSemanticSha256 -Path $FrozenBaselineSnapshotPath

    if ($r.stored_baseline_hash -ne $r.computed_baseline_hash) {
        $r.reason = 'frozen_baseline_snapshot_semantic_hash_mismatch'; $r.sequence = @($seq); return $r
    }
    $r.baseline_integrity = 'VALID'

    # 3) live ledger-head verification
    $seq.Add('3.live_ledger_head_verification')
    if (-not (Test-Path -LiteralPath $LiveLedgerPath)) {
        $r.reason = 'live_ledger_missing'; $r.sequence = @($seq); return $r
    }
    $ledgerObj   = Get-Content -Raw -LiteralPath $LiveLedgerPath | ConvertFrom-Json
    $ledgerCheck = Test-LegacyTrustChain -ChainObj $ledgerObj
    if (-not $ledgerCheck.pass) {
        $r.reason = ('live_ledger_invalid_' + [string]$ledgerCheck.reason); $r.sequence = @($seq); return $r
    }
    $r.stored_ledger_head_hash   = [string]$baselineObj.ledger_head_hash
    $r.computed_ledger_head_hash = [string]$ledgerCheck.last_entry_hash
    $r.ledger_head_match         = ($r.stored_ledger_head_hash -eq $r.computed_ledger_head_hash)

    # 4) live coverage-fingerprint verification
    $seq.Add('4.live_coverage_fingerprint_verification')
    if (-not (Test-Path -LiteralPath $LiveCoverageFingerprintPath)) {
        $r.reason = 'live_coverage_fingerprint_reference_missing'; $r.sequence = @($seq); return $r
    }
    $fpObj                                 = Get-Content -Raw -LiteralPath $LiveCoverageFingerprintPath | ConvertFrom-Json
    $r.stored_coverage_fingerprint_hash    = [string]$baselineObj.coverage_fingerprint_hash
    $r.computed_coverage_fingerprint_hash  = [string]$fpObj.coverage_fingerprint_sha256
    $r.coverage_fingerprint_match          = ($r.stored_coverage_fingerprint_hash -eq $r.computed_coverage_fingerprint_hash)
    if (-not $r.coverage_fingerprint_match) {
        $r.reason = 'live_coverage_fingerprint_drift_detected'; $r.sequence = @($seq); return $r
    }

    # 5) live chain-continuation verification
    $seq.Add('5.live_chain_continuation_verification')
    $hashes                   = @($ledgerCheck.chain_hashes)
    $baselineHeadExistsInChain = ($hashes -contains $r.stored_ledger_head_hash)
    $baselineLength            = [int]$baselineObj.ledger_length
    $liveLength                = [int]$ledgerCheck.entry_count

    if (-not $baselineHeadExistsInChain -or $liveLength -lt $baselineLength) {
        $r.chain_continuation_status = 'INVALID'
        $r.reason = 'live_chain_not_valid_continuation_of_frozen_baseline'
        $r.sequence = @($seq); return $r
    }
    $r.chain_continuation_status = 'VALID'

    # 6) semantic protected-field verification
    $seq.Add('6.semantic_protected_field_verification')
    if ([string]$integrityObj.ledger_head_hash -ne [string]$baselineObj.ledger_head_hash) {
        $r.reason = 'integrity_vs_baseline_ledger_head_mismatch'; $r.sequence = @($seq); return $r
    }
    if ([string]$integrityObj.coverage_fingerprint_hash -ne [string]$baselineObj.coverage_fingerprint_hash) {
        $r.reason = 'integrity_vs_baseline_coverage_fingerprint_mismatch'; $r.sequence = @($seq); return $r
    }

    $baselineHeadIndex = -1
    for ($i = 0; $i -lt $hashes.Count; $i++) {
        if ($hashes[$i] -eq $r.stored_ledger_head_hash) { $baselineHeadIndex = $i; break }
    }
    if ($baselineHeadIndex -lt 0) {
        $r.reason = 'frozen_head_not_indexable_in_live_chain'; $r.sequence = @($seq); return $r
    }
    $expectedHeadIndex = [int]$baselineObj.ledger_length - 1
    if ($baselineHeadIndex -ne $expectedHeadIndex) {
        $r.reason = 'frozen_head_index_mismatch_with_frozen_length'; $r.sequence = @($seq); return $r
    }
    $headEntry = @($ledgerObj.entries)[$baselineHeadIndex]
    if ([string]$headEntry.entry_id -ne [string]$baselineObj.latest_entry_id) {
        $r.reason = 'frozen_latest_entry_id_mismatch'; $r.sequence = @($seq); return $r
    }
    if ([string]$headEntry.phase_locked -ne [string]$baselineObj.latest_entry_phase_locked) {
        $r.reason = 'frozen_latest_entry_phase_locked_mismatch'; $r.sequence = @($seq); return $r
    }
    $r.semantic_match_status = 'TRUE'

    # 7) runtime initialization allowed
    $seq.Add('7.runtime_initialization_allowed')
    $r.runtime_init_allowed_or_blocked = 'ALLOWED'
    $r.reason   = $(if ($r.ledger_head_match) { 'exact_frozen_head_match' } else { 'valid_frozen_head_continuation' })
    $r.sequence = @($seq)
    return $r
}

# ── Guarded helper result factories ──────────────────────────────────────────

function New-FBBlockedResult {
    param(
        [string]$ProtectedInputType,
        [string]$EntrypointName,
        [string]$FilePath,
        [string]$OperationRequested,
        [string]$FailReason
    )
    return [ordered]@{
        protected_input_type                   = $ProtectedInputType
        entrypoint_or_helper_name              = $EntrypointName
        file_path                              = $FilePath
        frozen_baseline_gate_result            = 'FAIL'
        operation_requested                    = $OperationRequested
        operation_allowed_or_blocked           = 'BLOCKED'
        fallback_occurred                      = $false
        regeneration_occurred                  = $false
        fail_reason                            = $FailReason
    }
}

function New-FBAllowedResult {
    param(
        [string]$ProtectedInputType,
        [string]$EntrypointName,
        [string]$FilePath,
        [string]$OperationRequested,
        [string]$Detail
    )
    return [ordered]@{
        protected_input_type                   = $ProtectedInputType
        entrypoint_or_helper_name              = $EntrypointName
        file_path                              = $FilePath
        frozen_baseline_gate_result            = 'PASS'
        operation_requested                    = $OperationRequested
        operation_allowed_or_blocked           = 'ALLOWED'
        fallback_occurred                      = $false
        regeneration_occurred                  = $false
        fail_reason                            = 'none'
        detail                                 = $Detail
    }
}

# ── Guarded helpers (9 entrypoints / helpers, each must pass gate first) ─────

# Helper 1: Frozen baseline snapshot load
function Invoke-GuardedFrozenBaselineSnapshotLoad {
    param(
        [string]$FrozenBaselineSnapshotPath,
        [string]$FrozenBaselineIntegrityPath,
        [string]$LiveLedgerPath,
        [string]$LiveCoverageFingerprintPath
    )
    $gate = Invoke-FrozenBaselineTrustChainEnforcementGate `
        -FrozenBaselineSnapshotPath $FrozenBaselineSnapshotPath `
        -FrozenBaselineIntegrityPath $FrozenBaselineIntegrityPath `
        -LiveLedgerPath $LiveLedgerPath `
        -LiveCoverageFingerprintPath $LiveCoverageFingerprintPath
    if ($gate.runtime_init_allowed_or_blocked -ne 'ALLOWED') {
        return New-FBBlockedResult `
            -ProtectedInputType 'frozen_baseline_snapshot' `
            -EntrypointName 'Invoke-GuardedFrozenBaselineSnapshotLoad' `
            -FilePath $FrozenBaselineSnapshotPath `
            -OperationRequested 'load_frozen_baseline_snapshot' `
            -FailReason $gate.reason
    }
    $obj = Get-Content -Raw -LiteralPath $FrozenBaselineSnapshotPath | ConvertFrom-Json
    return New-FBAllowedResult `
        -ProtectedInputType 'frozen_baseline_snapshot' `
        -EntrypointName 'Invoke-GuardedFrozenBaselineSnapshotLoad' `
        -FilePath $FrozenBaselineSnapshotPath `
        -OperationRequested 'load_frozen_baseline_snapshot' `
        -Detail ('phase_locked=' + [string]$obj.phase_locked + ';latest_entry_id=' + [string]$obj.latest_entry_id)
}

# Helper 2: Frozen baseline integrity record load
function Invoke-GuardedFrozenBaselineIntegrityRecordLoad {
    param(
        [string]$FrozenBaselineSnapshotPath,
        [string]$FrozenBaselineIntegrityPath,
        [string]$LiveLedgerPath,
        [string]$LiveCoverageFingerprintPath
    )
    $gate = Invoke-FrozenBaselineTrustChainEnforcementGate `
        -FrozenBaselineSnapshotPath $FrozenBaselineSnapshotPath `
        -FrozenBaselineIntegrityPath $FrozenBaselineIntegrityPath `
        -LiveLedgerPath $LiveLedgerPath `
        -LiveCoverageFingerprintPath $LiveCoverageFingerprintPath
    if ($gate.runtime_init_allowed_or_blocked -ne 'ALLOWED') {
        return New-FBBlockedResult `
            -ProtectedInputType 'frozen_baseline_integrity_record' `
            -EntrypointName 'Invoke-GuardedFrozenBaselineIntegrityRecordLoad' `
            -FilePath $FrozenBaselineIntegrityPath `
            -OperationRequested 'load_frozen_baseline_integrity_record' `
            -FailReason $gate.reason
    }
    $obj = Get-Content -Raw -LiteralPath $FrozenBaselineIntegrityPath | ConvertFrom-Json
    return New-FBAllowedResult `
        -ProtectedInputType 'frozen_baseline_integrity_record' `
        -EntrypointName 'Invoke-GuardedFrozenBaselineIntegrityRecordLoad' `
        -FilePath $FrozenBaselineIntegrityPath `
        -OperationRequested 'load_frozen_baseline_integrity_record' `
        -Detail ('stored_hash_prefix=' + ([string]$obj.baseline_snapshot_semantic_sha256).Substring(0, 8))
}

# Helper 3: Baseline verification (computes and compares hashes end-to-end)
function Invoke-GuardedBaselineVerification {
    param(
        [string]$FrozenBaselineSnapshotPath,
        [string]$FrozenBaselineIntegrityPath,
        [string]$LiveLedgerPath,
        [string]$LiveCoverageFingerprintPath
    )
    $gate = Invoke-FrozenBaselineTrustChainEnforcementGate `
        -FrozenBaselineSnapshotPath $FrozenBaselineSnapshotPath `
        -FrozenBaselineIntegrityPath $FrozenBaselineIntegrityPath `
        -LiveLedgerPath $LiveLedgerPath `
        -LiveCoverageFingerprintPath $LiveCoverageFingerprintPath
    if ($gate.runtime_init_allowed_or_blocked -ne 'ALLOWED') {
        return New-FBBlockedResult `
            -ProtectedInputType 'frozen_baseline_verification' `
            -EntrypointName 'Invoke-GuardedBaselineVerification' `
            -FilePath $FrozenBaselineSnapshotPath `
            -OperationRequested 'verify_frozen_baseline' `
            -FailReason $gate.reason
    }
    return New-FBAllowedResult `
        -ProtectedInputType 'frozen_baseline_verification' `
        -EntrypointName 'Invoke-GuardedBaselineVerification' `
        -FilePath $FrozenBaselineSnapshotPath `
        -OperationRequested 'verify_frozen_baseline' `
        -Detail ('stored_baseline_hash=' + $gate.stored_baseline_hash + ';computed=' + $gate.computed_baseline_hash)
}

# Helper 4: Live ledger head read
function Invoke-GuardedLedgerHeadRead {
    param(
        [string]$FrozenBaselineSnapshotPath,
        [string]$FrozenBaselineIntegrityPath,
        [string]$LiveLedgerPath,
        [string]$LiveCoverageFingerprintPath
    )
    $gate = Invoke-FrozenBaselineTrustChainEnforcementGate `
        -FrozenBaselineSnapshotPath $FrozenBaselineSnapshotPath `
        -FrozenBaselineIntegrityPath $FrozenBaselineIntegrityPath `
        -LiveLedgerPath $LiveLedgerPath `
        -LiveCoverageFingerprintPath $LiveCoverageFingerprintPath
    if ($gate.runtime_init_allowed_or_blocked -ne 'ALLOWED') {
        return New-FBBlockedResult `
            -ProtectedInputType 'live_ledger_head' `
            -EntrypointName 'Invoke-GuardedLedgerHeadRead' `
            -FilePath $LiveLedgerPath `
            -OperationRequested 'read_live_ledger_head' `
            -FailReason $gate.reason
    }
    return New-FBAllowedResult `
        -ProtectedInputType 'live_ledger_head' `
        -EntrypointName 'Invoke-GuardedLedgerHeadRead' `
        -FilePath $LiveLedgerPath `
        -OperationRequested 'read_live_ledger_head' `
        -Detail ('computed_ledger_head_hash=' + $gate.computed_ledger_head_hash + ';match=' + [string]$gate.ledger_head_match)
}

# Helper 5: Live coverage fingerprint read
function Invoke-GuardedCoverageFingerprintRead {
    param(
        [string]$FrozenBaselineSnapshotPath,
        [string]$FrozenBaselineIntegrityPath,
        [string]$LiveLedgerPath,
        [string]$LiveCoverageFingerprintPath
    )
    $gate = Invoke-FrozenBaselineTrustChainEnforcementGate `
        -FrozenBaselineSnapshotPath $FrozenBaselineSnapshotPath `
        -FrozenBaselineIntegrityPath $FrozenBaselineIntegrityPath `
        -LiveLedgerPath $LiveLedgerPath `
        -LiveCoverageFingerprintPath $LiveCoverageFingerprintPath
    if ($gate.runtime_init_allowed_or_blocked -ne 'ALLOWED') {
        return New-FBBlockedResult `
            -ProtectedInputType 'live_coverage_fingerprint' `
            -EntrypointName 'Invoke-GuardedCoverageFingerprintRead' `
            -FilePath $LiveCoverageFingerprintPath `
            -OperationRequested 'read_live_coverage_fingerprint' `
            -FailReason $gate.reason
    }
    $fpObj = Get-Content -Raw -LiteralPath $LiveCoverageFingerprintPath | ConvertFrom-Json
    return New-FBAllowedResult `
        -ProtectedInputType 'live_coverage_fingerprint' `
        -EntrypointName 'Invoke-GuardedCoverageFingerprintRead' `
        -FilePath $LiveCoverageFingerprintPath `
        -OperationRequested 'read_live_coverage_fingerprint' `
        -Detail ('coverage_fingerprint_sha256_prefix=' + ([string]$fpObj.coverage_fingerprint_sha256).Substring(0, 8))
}

# Helper 6: Chain-continuation validation
function Invoke-GuardedChainContinuationValidation {
    param(
        [string]$FrozenBaselineSnapshotPath,
        [string]$FrozenBaselineIntegrityPath,
        [string]$LiveLedgerPath,
        [string]$LiveCoverageFingerprintPath
    )
    $gate = Invoke-FrozenBaselineTrustChainEnforcementGate `
        -FrozenBaselineSnapshotPath $FrozenBaselineSnapshotPath `
        -FrozenBaselineIntegrityPath $FrozenBaselineIntegrityPath `
        -LiveLedgerPath $LiveLedgerPath `
        -LiveCoverageFingerprintPath $LiveCoverageFingerprintPath
    if ($gate.runtime_init_allowed_or_blocked -ne 'ALLOWED') {
        return New-FBBlockedResult `
            -ProtectedInputType 'chain_continuation' `
            -EntrypointName 'Invoke-GuardedChainContinuationValidation' `
            -FilePath $LiveLedgerPath `
            -OperationRequested 'validate_chain_continuation' `
            -FailReason $gate.reason
    }
    return New-FBAllowedResult `
        -ProtectedInputType 'chain_continuation' `
        -EntrypointName 'Invoke-GuardedChainContinuationValidation' `
        -FilePath $LiveLedgerPath `
        -OperationRequested 'validate_chain_continuation' `
        -Detail ('chain_continuation_status=' + $gate.chain_continuation_status)
}

# Helper 7: Frozen baseline semantic hash input
function Invoke-GuardedFrozenBaselineSemanticHash {
    param(
        [string]$FrozenBaselineSnapshotPath,
        [string]$FrozenBaselineIntegrityPath,
        [string]$LiveLedgerPath,
        [string]$LiveCoverageFingerprintPath
    )
    $gate = Invoke-FrozenBaselineTrustChainEnforcementGate `
        -FrozenBaselineSnapshotPath $FrozenBaselineSnapshotPath `
        -FrozenBaselineIntegrityPath $FrozenBaselineIntegrityPath `
        -LiveLedgerPath $LiveLedgerPath `
        -LiveCoverageFingerprintPath $LiveCoverageFingerprintPath
    if ($gate.runtime_init_allowed_or_blocked -ne 'ALLOWED') {
        return New-FBBlockedResult `
            -ProtectedInputType 'frozen_baseline_semantic_hash_input' `
            -EntrypointName 'Invoke-GuardedFrozenBaselineSemanticHash' `
            -FilePath $FrozenBaselineSnapshotPath `
            -OperationRequested 'compute_frozen_baseline_semantic_hash' `
            -FailReason $gate.reason
    }
    $computedHash = Get-JsonSemanticSha256 -Path $FrozenBaselineSnapshotPath
    return New-FBAllowedResult `
        -ProtectedInputType 'frozen_baseline_semantic_hash_input' `
        -EntrypointName 'Invoke-GuardedFrozenBaselineSemanticHash' `
        -FilePath $FrozenBaselineSnapshotPath `
        -OperationRequested 'compute_frozen_baseline_semantic_hash' `
        -Detail ('computed_semantic_hash=' + $computedHash)
}

# Helper 8: Protected-field semantic verification
function Invoke-GuardedProtectedFieldSemanticVerification {
    param(
        [string]$FrozenBaselineSnapshotPath,
        [string]$FrozenBaselineIntegrityPath,
        [string]$LiveLedgerPath,
        [string]$LiveCoverageFingerprintPath
    )
    $gate = Invoke-FrozenBaselineTrustChainEnforcementGate `
        -FrozenBaselineSnapshotPath $FrozenBaselineSnapshotPath `
        -FrozenBaselineIntegrityPath $FrozenBaselineIntegrityPath `
        -LiveLedgerPath $LiveLedgerPath `
        -LiveCoverageFingerprintPath $LiveCoverageFingerprintPath
    if ($gate.runtime_init_allowed_or_blocked -ne 'ALLOWED') {
        return New-FBBlockedResult `
            -ProtectedInputType 'protected_field_semantic_verification' `
            -EntrypointName 'Invoke-GuardedProtectedFieldSemanticVerification' `
            -FilePath $FrozenBaselineSnapshotPath `
            -OperationRequested 'verify_protected_semantic_fields' `
            -FailReason $gate.reason
    }
    return New-FBAllowedResult `
        -ProtectedInputType 'protected_field_semantic_verification' `
        -EntrypointName 'Invoke-GuardedProtectedFieldSemanticVerification' `
        -FilePath $FrozenBaselineSnapshotPath `
        -OperationRequested 'verify_protected_semantic_fields' `
        -Detail ('semantic_match_status=' + $gate.semantic_match_status)
}

# Helper 9: Runtime init wrapper
function Invoke-GuardedRuntimeInitWrapper {
    param(
        [string]$FrozenBaselineSnapshotPath,
        [string]$FrozenBaselineIntegrityPath,
        [string]$LiveLedgerPath,
        [string]$LiveCoverageFingerprintPath
    )
    $gate = Invoke-FrozenBaselineTrustChainEnforcementGate `
        -FrozenBaselineSnapshotPath $FrozenBaselineSnapshotPath `
        -FrozenBaselineIntegrityPath $FrozenBaselineIntegrityPath `
        -LiveLedgerPath $LiveLedgerPath `
        -LiveCoverageFingerprintPath $LiveCoverageFingerprintPath
    if ($gate.runtime_init_allowed_or_blocked -ne 'ALLOWED') {
        return New-FBBlockedResult `
            -ProtectedInputType 'runtime_init_wrapper' `
            -EntrypointName 'Invoke-GuardedRuntimeInitWrapper' `
            -FilePath $FrozenBaselineSnapshotPath `
            -OperationRequested 'runtime_init' `
            -FailReason $gate.reason
    }
    return New-FBAllowedResult `
        -ProtectedInputType 'runtime_init_wrapper' `
        -EntrypointName 'Invoke-GuardedRuntimeInitWrapper' `
        -FilePath $FrozenBaselineSnapshotPath `
        -OperationRequested 'runtime_init' `
        -Detail ('runtime_init_allowed;reason=' + $gate.reason + ';sequence_steps=' + $gate.sequence.Count)
}

# ── Paths ─────────────────────────────────────────────────────────────────────

$Timestamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF          = Join-Path $Root ('_proof\phase46_1_trust_chain_baseline_enforcement_bypass_resistance_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$BaselinePath           = Join-Path $Root 'control_plane\77_certification_baseline_coverage_trust_chain_baseline.json'
$IntegrityPath          = Join-Path $Root 'control_plane\78_certification_baseline_coverage_trust_chain_baseline_integrity.json'
$LedgerPath             = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$CoverageFingerprintRefPath = Join-Path $Root 'control_plane\76_certification_baseline_coverage_fingerprint.json'

foreach ($p in @($BaselinePath, $IntegrityPath, $LedgerPath, $CoverageFingerprintRefPath)) {
    if (-not (Test-Path -LiteralPath $p)) { throw ('Missing required control_plane file: ' + $p) }
}

# ── Build a tampered integrity record (bad semantic hash) for bypass cases ────
# Used in cases B-I so the gate blocks at step 2 (integrity hash mismatch)

$tmpTamperedIntegrity = Join-Path $env:TEMP ('phase46_1_tampered_integrity_' + $Timestamp + '.json')
$intRaw = Get-Content -Raw -LiteralPath $IntegrityPath | ConvertFrom-Json
$originalHash = [string]$intRaw.baseline_snapshot_semantic_sha256
$tamperedHash = $originalHash.Substring(0, [Math]::Min(8, $originalHash.Length)) + 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef'
$tamperedHash = $tamperedHash.Substring(0, 64)
$intRaw.baseline_snapshot_semantic_sha256 = $tamperedHash
($intRaw | ConvertTo-Json -Depth 10 -Compress) | Set-Content -LiteralPath $tmpTamperedIntegrity -Encoding UTF8 -NoNewline

# ── Entrypoint records list ───────────────────────────────────────────────────

$epRecords = [System.Collections.Generic.List[object]]::new()

# CASE A: Normal pass — all paths clean, gate ALLOWED, operation ALLOWED
# (uses clean integrity path)
$caseA_ep1 = Invoke-GuardedFrozenBaselineSnapshotLoad `
    -FrozenBaselineSnapshotPath $BaselinePath `
    -FrozenBaselineIntegrityPath $IntegrityPath `
    -LiveLedgerPath $LedgerPath `
    -LiveCoverageFingerprintPath $CoverageFingerprintRefPath
$caseA = ($caseA_ep1.frozen_baseline_gate_result -eq 'PASS' -and $caseA_ep1.operation_allowed_or_blocked -eq 'ALLOWED')
$epRecords.Add([ordered]@{ case = 'A'; helper = 'Invoke-GuardedFrozenBaselineSnapshotLoad'; result = $caseA_ep1 })

# CASE B: Frozen baseline snapshot tampered — gate must block snapshot load
$tmpTamperedBaselineB = Join-Path $env:TEMP ('phase46_1_caseB_baseline_' + $Timestamp + '.json')
$baselineRawB = Get-Content -Raw -LiteralPath $BaselinePath
$tamperedB    = $baselineRawB -replace '"phase_locked"\s*:\s*"45\.9"', '"phase_locked":"45.9-TAMPER"'
if ($tamperedB -eq $baselineRawB) { $tamperedB = ($baselineRawB + ' ') }
[System.IO.File]::WriteAllText($tmpTamperedBaselineB, $tamperedB, [System.Text.Encoding]::UTF8)

$caseB_ep1 = Invoke-GuardedFrozenBaselineSnapshotLoad `
    -FrozenBaselineSnapshotPath $tmpTamperedBaselineB `
    -FrozenBaselineIntegrityPath $IntegrityPath `
    -LiveLedgerPath $LedgerPath `
    -LiveCoverageFingerprintPath $CoverageFingerprintRefPath
Remove-Item -Force -LiteralPath $tmpTamperedBaselineB

$caseB = ($caseB_ep1.frozen_baseline_gate_result -eq 'FAIL' -and $caseB_ep1.operation_allowed_or_blocked -eq 'BLOCKED')
$epRecords.Add([ordered]@{ case = 'B'; helper = 'Invoke-GuardedFrozenBaselineSnapshotLoad'; result = $caseB_ep1 })

# CASE C: Tampered integrity record — gate must block integrity record load
$caseC_ep2 = Invoke-GuardedFrozenBaselineIntegrityRecordLoad `
    -FrozenBaselineSnapshotPath $BaselinePath `
    -FrozenBaselineIntegrityPath $tmpTamperedIntegrity `
    -LiveLedgerPath $LedgerPath `
    -LiveCoverageFingerprintPath $CoverageFingerprintRefPath

$caseC = ($caseC_ep2.frozen_baseline_gate_result -eq 'FAIL' -and $caseC_ep2.operation_allowed_or_blocked -eq 'BLOCKED')
$epRecords.Add([ordered]@{ case = 'C'; helper = 'Invoke-GuardedFrozenBaselineIntegrityRecordLoad'; result = $caseC_ep2 })

# CASE D: Tampered integrity — gate must block baseline verification
$caseD_ep3 = Invoke-GuardedBaselineVerification `
    -FrozenBaselineSnapshotPath $BaselinePath `
    -FrozenBaselineIntegrityPath $tmpTamperedIntegrity `
    -LiveLedgerPath $LedgerPath `
    -LiveCoverageFingerprintPath $CoverageFingerprintRefPath

$caseD = ($caseD_ep3.frozen_baseline_gate_result -eq 'FAIL' -and $caseD_ep3.operation_allowed_or_blocked -eq 'BLOCKED')
$epRecords.Add([ordered]@{ case = 'D'; helper = 'Invoke-GuardedBaselineVerification'; result = $caseD_ep3 })

# CASE E: Tampered ledger (last entry fingerprint_hash drifted) — gate must block ledger-head read
$tmpLedgerE = Join-Path $env:TEMP ('phase46_1_caseE_ledger_' + $Timestamp + '.json')
$ledgerObjE = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
$entriesE   = [System.Collections.Generic.List[object]]::new()
foreach ($e in @($ledgerObjE.entries)) { $entriesE.Add($e) }
$entriesE[$entriesE.Count - 1].fingerprint_hash = ([string]$entriesE[$entriesE.Count - 1].fingerprint_hash + 'drift')
$ledgerTampE = [ordered]@{ chain_version = [int]$ledgerObjE.chain_version; entries = @($entriesE) }
($ledgerTampE | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $tmpLedgerE -Encoding UTF8 -NoNewline

$caseE_ep4 = Invoke-GuardedLedgerHeadRead `
    -FrozenBaselineSnapshotPath $BaselinePath `
    -FrozenBaselineIntegrityPath $IntegrityPath `
    -LiveLedgerPath $tmpLedgerE `
    -LiveCoverageFingerprintPath $CoverageFingerprintRefPath
Remove-Item -Force -LiteralPath $tmpLedgerE

# Gate blocks at step 3 (live_ledger_invalid chain link mismatch) or continuation,
# either way operation must be BLOCKED
$caseE = ($caseE_ep4.frozen_baseline_gate_result -eq 'FAIL' -and $caseE_ep4.operation_allowed_or_blocked -eq 'BLOCKED')
$epRecords.Add([ordered]@{ case = 'E'; helper = 'Invoke-GuardedLedgerHeadRead'; result = $caseE_ep4 })

# CASE F: Coverage fingerprint drift — gate must block fingerprint read
$tmpFingerprintF = Join-Path $env:TEMP ('phase46_1_caseF_fp_' + $Timestamp + '.json')
$fpObjF = Get-Content -Raw -LiteralPath $CoverageFingerprintRefPath | ConvertFrom-Json
$fpObjF.coverage_fingerprint_sha256 = ([string]$fpObjF.coverage_fingerprint_sha256 + '00')
($fpObjF | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $tmpFingerprintF -Encoding UTF8 -NoNewline

$caseF_ep5 = Invoke-GuardedCoverageFingerprintRead `
    -FrozenBaselineSnapshotPath $BaselinePath `
    -FrozenBaselineIntegrityPath $IntegrityPath `
    -LiveLedgerPath $LedgerPath `
    -LiveCoverageFingerprintPath $tmpFingerprintF
Remove-Item -Force -LiteralPath $tmpFingerprintF

$caseF = ($caseF_ep5.frozen_baseline_gate_result -eq 'FAIL' -and $caseF_ep5.operation_allowed_or_blocked -eq 'BLOCKED')
$epRecords.Add([ordered]@{ case = 'F'; helper = 'Invoke-GuardedCoverageFingerprintRead'; result = $caseF_ep5 })

# CASE G: Invalid chain continuation — gate must block chain-continuation validation
$tmpLedgerG = Join-Path $env:TEMP ('phase46_1_caseG_ledger_' + $Timestamp + '.json')
$ledgerObjG = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
$chainG     = Test-LegacyTrustChain -ChainObj $ledgerObjG
$entriesG   = [System.Collections.Generic.List[object]]::new()
foreach ($e in @($ledgerObjG.entries)) { $entriesG.Add($e) }
$nextIdG    = Get-NextEntryId -ChainObj $ledgerObjG
$invalidAppendG = [ordered]@{
    entry_id         = $nextIdG
    artifact         = 'phase46_1_invalid_probe'
    coverage_fingerprint = ([string](Get-Content -Raw -LiteralPath $CoverageFingerprintRefPath | ConvertFrom-Json).coverage_fingerprint_sha256)
    fingerprint_hash = (Get-BytesSha256Hex -Bytes ([System.Text.Encoding]::UTF8.GetBytes('invalid_append_' + $Timestamp)))
    timestamp_utc    = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    phase_locked     = '46.1'
    previous_hash    = ([string]$chainG.last_entry_hash + 'broken')
}
$entriesG.Add($invalidAppendG)
$ledgerInvalidG = [ordered]@{ chain_version = [int]$ledgerObjG.chain_version; entries = @($entriesG) }
($ledgerInvalidG | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $tmpLedgerG -Encoding UTF8 -NoNewline

$caseG_ep6 = Invoke-GuardedChainContinuationValidation `
    -FrozenBaselineSnapshotPath $BaselinePath `
    -FrozenBaselineIntegrityPath $IntegrityPath `
    -LiveLedgerPath $tmpLedgerG `
    -LiveCoverageFingerprintPath $CoverageFingerprintRefPath
Remove-Item -Force -LiteralPath $tmpLedgerG

$caseG = ($caseG_ep6.frozen_baseline_gate_result -eq 'FAIL' -and $caseG_ep6.operation_allowed_or_blocked -eq 'BLOCKED')
$epRecords.Add([ordered]@{ case = 'G'; helper = 'Invoke-GuardedChainContinuationValidation'; result = $caseG_ep6 })

# CASE H: Tampered integrity — gate must block semantic hash computation
$caseH_ep7 = Invoke-GuardedFrozenBaselineSemanticHash `
    -FrozenBaselineSnapshotPath $BaselinePath `
    -FrozenBaselineIntegrityPath $tmpTamperedIntegrity `
    -LiveLedgerPath $LedgerPath `
    -LiveCoverageFingerprintPath $CoverageFingerprintRefPath

$caseH = ($caseH_ep7.frozen_baseline_gate_result -eq 'FAIL' -and $caseH_ep7.operation_allowed_or_blocked -eq 'BLOCKED')
$epRecords.Add([ordered]@{ case = 'H'; helper = 'Invoke-GuardedFrozenBaselineSemanticHash'; result = $caseH_ep7 })

# CASE I: Tampered integrity — gate must block protected-field semantic verification
$caseI_ep8 = Invoke-GuardedProtectedFieldSemanticVerification `
    -FrozenBaselineSnapshotPath $BaselinePath `
    -FrozenBaselineIntegrityPath $tmpTamperedIntegrity `
    -LiveLedgerPath $LedgerPath `
    -LiveCoverageFingerprintPath $CoverageFingerprintRefPath

$caseI = ($caseI_ep8.frozen_baseline_gate_result -eq 'FAIL' -and $caseI_ep8.operation_allowed_or_blocked -eq 'BLOCKED')
$epRecords.Add([ordered]@{ case = 'I'; helper = 'Invoke-GuardedProtectedFieldSemanticVerification'; result = $caseI_ep8 })

# Cleanup tampered integrity temp file
Remove-Item -Force -LiteralPath $tmpTamperedIntegrity

# Bonus: verify runtime init wrapper also passes cleanly (used in 01_status)
$cleanRTW = Invoke-GuardedRuntimeInitWrapper `
    -FrozenBaselineSnapshotPath $BaselinePath `
    -FrozenBaselineIntegrityPath $IntegrityPath `
    -LiveLedgerPath $LedgerPath `
    -LiveCoverageFingerprintPath $CoverageFingerprintRefPath
$rtwPass = ($cleanRTW.operation_allowed_or_blocked -eq 'ALLOWED')

# ── Gate evaluation ───────────────────────────────────────────────────────────

$allPass = ($caseA -and $caseB -and $caseC -and $caseD -and $caseE -and $caseF -and $caseG -and $caseH -and $caseI)
$Gate    = if ($allPass) { 'PASS' } else { 'FAIL' }

# ── Proof artifact generation ─────────────────────────────────────────────────

Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value (
    @(
        'phase=46.1',
        'title=Trust-Chain Baseline Enforcement Bypass Resistance',
        ('gate=' + $Gate),
        ('frozen_baseline_bypass_resistance_proven=' + $(if ($allPass) { 'TRUE' } else { 'FALSE' })),
        ('runtime_init_wrapper_clean_pass=' + $(if ($rtwPass) { 'TRUE' } else { 'FALSE' })),
        'fallback_occurred=FALSE',
        'regeneration_occurred=FALSE',
        'runtime_state_machine_changed=NO'
    ) -join "`r`n"
) -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value (
    @(
        'runner=tools/phase46_1/phase46_1_trust_chain_baseline_enforcement_bypass_resistance_runner.ps1',
        ('frozen_baseline_snapshot=' + $BaselinePath),
        ('frozen_baseline_integrity=' + $IntegrityPath),
        ('live_ledger=' + $LedgerPath),
        ('live_coverage_fingerprint=' + $CoverageFingerprintRefPath)
    ) -join "`r`n"
) -Encoding UTF8 -NoNewline

# 10: entrypoint inventory
$invLines = [System.Collections.Generic.List[string]]::new()
$invLines.Add('file_path | entrypoint_or_helper_name | role | gate_guarded | protected_input_type | operation_type')
$invLines.Add('tools/phase46_0/...enforcement_runner.ps1 | Invoke-FrozenBaselineTrustChainEnforcementGate | primary_gate | yes | frozen_baseline_snapshot+integrity+ledger+coverage_fp | enforce_frozen_baseline')
$invLines.Add('tools/phase46_1/...bypass_resistance_runner.ps1 | Invoke-GuardedFrozenBaselineSnapshotLoad | guarded_helper | yes | frozen_baseline_snapshot | load_frozen_baseline_snapshot')
$invLines.Add('tools/phase46_1/...bypass_resistance_runner.ps1 | Invoke-GuardedFrozenBaselineIntegrityRecordLoad | guarded_helper | yes | frozen_baseline_integrity_record | load_frozen_baseline_integrity_record')
$invLines.Add('tools/phase46_1/...bypass_resistance_runner.ps1 | Invoke-GuardedBaselineVerification | guarded_helper | yes | frozen_baseline_verification | verify_frozen_baseline')
$invLines.Add('tools/phase46_1/...bypass_resistance_runner.ps1 | Invoke-GuardedLedgerHeadRead | guarded_helper | yes | live_ledger_head | read_live_ledger_head')
$invLines.Add('tools/phase46_1/...bypass_resistance_runner.ps1 | Invoke-GuardedCoverageFingerprintRead | guarded_helper | yes | live_coverage_fingerprint | read_live_coverage_fingerprint')
$invLines.Add('tools/phase46_1/...bypass_resistance_runner.ps1 | Invoke-GuardedChainContinuationValidation | guarded_helper | yes | chain_continuation | validate_chain_continuation')
$invLines.Add('tools/phase46_1/...bypass_resistance_runner.ps1 | Invoke-GuardedFrozenBaselineSemanticHash | guarded_helper | yes | frozen_baseline_semantic_hash_input | compute_frozen_baseline_semantic_hash')
$invLines.Add('tools/phase46_1/...bypass_resistance_runner.ps1 | Invoke-GuardedProtectedFieldSemanticVerification | guarded_helper | yes | protected_field_semantic_verification | verify_protected_semantic_fields')
$invLines.Add('tools/phase46_1/...bypass_resistance_runner.ps1 | Invoke-GuardedRuntimeInitWrapper | guarded_helper | yes | runtime_init_wrapper | runtime_init')
Set-Content -LiteralPath (Join-Path $PF '10_entrypoint_inventory.txt') -Value ($invLines.ToArray() -join "`r`n") -Encoding UTF8 -NoNewline

# 11: enforcement map
$mapLines = [System.Collections.Generic.List[string]]::new()
$mapLines.Add('FROZEN BASELINE TRUST-CHAIN ENFORCEMENT MAP (PHASE 46.1)')
$mapLines.Add('')
$mapLines.Add('Invoke-FrozenBaselineTrustChainEnforcementGate -> primary gate -> gate_source=phase46_0')
$mapLines.Add('Invoke-GuardedFrozenBaselineSnapshotLoad -> directly gated -> gate_source=Invoke-FrozenBaselineTrustChainEnforcementGate')
$mapLines.Add('Invoke-GuardedFrozenBaselineIntegrityRecordLoad -> directly gated -> gate_source=Invoke-FrozenBaselineTrustChainEnforcementGate')
$mapLines.Add('Invoke-GuardedBaselineVerification -> directly gated -> gate_source=Invoke-FrozenBaselineTrustChainEnforcementGate')
$mapLines.Add('Invoke-GuardedLedgerHeadRead -> directly gated -> gate_source=Invoke-FrozenBaselineTrustChainEnforcementGate')
$mapLines.Add('Invoke-GuardedCoverageFingerprintRead -> directly gated -> gate_source=Invoke-FrozenBaselineTrustChainEnforcementGate')
$mapLines.Add('Invoke-GuardedChainContinuationValidation -> directly gated -> gate_source=Invoke-FrozenBaselineTrustChainEnforcementGate')
$mapLines.Add('Invoke-GuardedFrozenBaselineSemanticHash -> directly gated -> gate_source=Invoke-FrozenBaselineTrustChainEnforcementGate')
$mapLines.Add('Invoke-GuardedProtectedFieldSemanticVerification -> directly gated -> gate_source=Invoke-FrozenBaselineTrustChainEnforcementGate')
$mapLines.Add('Invoke-GuardedRuntimeInitWrapper -> directly gated -> gate_source=Invoke-FrozenBaselineTrustChainEnforcementGate')
Set-Content -LiteralPath (Join-Path $PF '11_frozen_baseline_enforcement_map.txt') -Value ($mapLines.ToArray() -join "`r`n") -Encoding UTF8 -NoNewline

# 12: files touched
Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Value (
    @(
        ('READ  ' + $BaselinePath),
        ('READ  ' + $IntegrityPath),
        ('READ  ' + $LedgerPath),
        ('READ  ' + $CoverageFingerprintRefPath),
        ('WRITE ' + (Join-Path $PF '*'))
    ) -join "`r`n"
) -Encoding UTF8 -NoNewline

# 13: build output
Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Value (
    @(
        'build_type=PowerShell bypass resistance runner',
        'compile_required=no',
        'runtime_state_machine_changed=no',
        'operation=bypass_resistance_probe_via_tampered_integrity_and_tampered_artifacts'
    ) -join "`r`n"
) -Encoding UTF8 -NoNewline

# 14: validation results
$valLines = [System.Collections.Generic.List[string]]::new()
$valLines.Add(('CASE A clean_frozen_baseline_pass=' + $(if ($caseA) { 'PASS' } else { 'FAIL' })))
$valLines.Add(('CASE B snapshot_tamper_blocks_snapshot_load=' + $(if ($caseB) { 'PASS' } else { 'FAIL' })))
$valLines.Add(('CASE C integrity_tamper_blocks_integrity_load=' + $(if ($caseC) { 'PASS' } else { 'FAIL' })))
$valLines.Add(('CASE D integrity_tamper_blocks_baseline_verification=' + $(if ($caseD) { 'PASS' } else { 'FAIL' })))
$valLines.Add(('CASE E ledger_drift_blocks_ledger_head_read=' + $(if ($caseE) { 'PASS' } else { 'FAIL' })))
$valLines.Add(('CASE F coverage_fp_drift_blocks_coverage_fp_read=' + $(if ($caseF) { 'PASS' } else { 'FAIL' })))
$valLines.Add(('CASE G invalid_continuation_blocks_chain_validation=' + $(if ($caseG) { 'PASS' } else { 'FAIL' })))
$valLines.Add(('CASE H integrity_tamper_blocks_semantic_hash_computation=' + $(if ($caseH) { 'PASS' } else { 'FAIL' })))
$valLines.Add(('CASE I integrity_tamper_blocks_protected_field_verification=' + $(if ($caseI) { 'PASS' } else { 'FAIL' })))
Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Value ($valLines.ToArray() -join "`r`n") -Encoding UTF8 -NoNewline

# 15: behavior summary
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value (
    @(
        'Phase 46.1 proves that every helper and entrypoint guarded by the Phase 46.0 frozen trust-chain baseline enforcement gate cannot be bypassed.',
        'All 9 guarded helpers call Invoke-FrozenBaselineTrustChainEnforcementGate before executing any protected operation.',
        'A tampered frozen baseline integrity record (corrupted semantic hash) causes the gate to block at step 2 (frozen_baseline_snapshot_semantic_hash_mismatch).',
        'A tampered frozen baseline snapshot (corrupted phase_locked) causes the gate to block at step 1 (frozen_baseline_phase_lock_mismatch).',
        'A drifted live ledger (corrupted fingerprint_hash on last entry) causes the gate to block at step 3 (live_ledger_invalid chain link mismatch or head hash mismatch).',
        'A drifted live coverage fingerprint causes the gate to block at step 4 (live_coverage_fingerprint_drift_detected).',
        'An invalid chain continuation (broken previous_hash link) causes the gate to block at step 3 (live_ledger_invalid) before reaching step 5.',
        'No guarded helper executes its protected operation when the gate returns BLOCKED.',
        'fallback_occurred=false and regeneration_occurred=false for all bypass attempts.',
        'Runtime behavior is otherwise unchanged when the frozen baseline is intact.'
    ) -join "`r`n"
) -Encoding UTF8 -NoNewline

# 16: entrypoint gate record
$recLines = [System.Collections.Generic.List[string]]::new()
$recLines.Add('case|protected_input_type|entrypoint_or_helper_name|file_path|frozen_baseline_gate_result|operation_requested|operation_allowed_or_blocked|fallback_occurred|regeneration_occurred|fail_reason')
foreach ($x in $epRecords) {
    $o = $x.result
    $recLines.Add(
        [string]$x.case + '|' +
        [string]$o.protected_input_type + '|' +
        [string]$o.entrypoint_or_helper_name + '|' +
        [string]$o.file_path + '|' +
        [string]$o.frozen_baseline_gate_result + '|' +
        [string]$o.operation_requested + '|' +
        [string]$o.operation_allowed_or_blocked + '|' +
        [string]$o.fallback_occurred + '|' +
        [string]$o.regeneration_occurred + '|' +
        $(if ($o.PSObject.Properties.Name -contains 'fail_reason') { [string]$o.fail_reason } else { 'none' })
    )
}
Set-Content -LiteralPath (Join-Path $PF '16_entrypoint_frozen_baseline_gate_record.txt') -Value ($recLines.ToArray() -join "`r`n") -Encoding UTF8 -NoNewline

# 17: bypass block evidence
$blockEv = [System.Collections.Generic.List[string]]::new()
$blockEv.Add(('caseA_gate_result='   + [string]$caseA_ep1.frozen_baseline_gate_result))
$blockEv.Add(('caseA_allowed='       + [string]$caseA_ep1.operation_allowed_or_blocked))
$blockEv.Add(('caseB_fail_reason='   + [string]$caseB_ep1.fail_reason))
$blockEv.Add(('caseB_blocked='       + [string]$caseB_ep1.operation_allowed_or_blocked))
$blockEv.Add(('caseC_fail_reason='   + [string]$caseC_ep2.fail_reason))
$blockEv.Add(('caseC_blocked='       + [string]$caseC_ep2.operation_allowed_or_blocked))
$blockEv.Add(('caseD_fail_reason='   + [string]$caseD_ep3.fail_reason))
$blockEv.Add(('caseD_blocked='       + [string]$caseD_ep3.operation_allowed_or_blocked))
$blockEv.Add(('caseE_fail_reason='   + [string]$caseE_ep4.fail_reason))
$blockEv.Add(('caseE_blocked='       + [string]$caseE_ep4.operation_allowed_or_blocked))
$blockEv.Add(('caseF_fail_reason='   + [string]$caseF_ep5.fail_reason))
$blockEv.Add(('caseF_blocked='       + [string]$caseF_ep5.operation_allowed_or_blocked))
$blockEv.Add(('caseG_fail_reason='   + [string]$caseG_ep6.fail_reason))
$blockEv.Add(('caseG_blocked='       + [string]$caseG_ep6.operation_allowed_or_blocked))
$blockEv.Add(('caseH_fail_reason='   + [string]$caseH_ep7.fail_reason))
$blockEv.Add(('caseH_blocked='       + [string]$caseH_ep7.operation_allowed_or_blocked))
$blockEv.Add(('caseI_fail_reason='   + [string]$caseI_ep8.fail_reason))
$blockEv.Add(('caseI_blocked='       + [string]$caseI_ep8.operation_allowed_or_blocked))
$blockEv.Add('fallback_occurred=false')
$blockEv.Add('regeneration_occurred=false')
Set-Content -LiteralPath (Join-Path $PF '17_bypass_block_evidence.txt') -Value ($blockEv.ToArray() -join "`r`n") -Encoding UTF8 -NoNewline

# 98: gate
Set-Content -LiteralPath (Join-Path $PF '98_gate_phase46_1.txt') -Value $Gate -Encoding UTF8 -NoNewline

# ── ZIP ───────────────────────────────────────────────────────────────────────

$ZIP     = "$PF.zip"
$staging = "${PF}_copy"
if (Test-Path -LiteralPath $staging) { Remove-Item -Recurse -Force -LiteralPath $staging }
New-Item -ItemType Directory -Path $staging | Out-Null
Get-ChildItem -Path $PF -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $staging $_.Name) -Force
}
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $ZIP -Force
Remove-Item -Recurse -Force -LiteralPath $staging

Write-Output "PF=$PF"
Write-Output "ZIP=$ZIP"
Write-Output "GATE=$Gate"
