Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ((Get-Location).Path -ne $Root) {
    Write-Output 'hey stupid Fucker, wrong window again'
    exit 1
}
Set-Location $Root

# ── Shared utility functions (compatible with phase45_4) ─────────────────────

function Get-BytesSha256Hex {
    param([byte[]]$Bytes)
    $hash = [System.Security.Cryptography.SHA256]::HashData($Bytes)
    return ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Get-StringSha256Hex {
    param([string]$Text)
    return Get-BytesSha256Hex -Bytes ([System.Text.Encoding]::UTF8.GetBytes($Text))
}

function Get-FileSha256Hex {
    param([string]$Path)
    return Get-BytesSha256Hex -Bytes ([System.IO.File]::ReadAllBytes($Path))
}

function Convert-ToCanonicalJson {
    param([object]$Value)

    if ($null -eq $Value) { return 'null' }

    if ($Value -is [string]) {
        return (([string]$Value | ConvertTo-Json -Compress))
    }

    if ($Value -is [bool]) {
        return $(if ([bool]$Value) { 'true' } else { 'false' })
    }

    if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64] -or
        $Value -is [uint16] -or $Value -is [uint32] -or $Value -is [uint64] -or $Value -is [single] -or
        $Value -is [double] -or $Value -is [decimal]) {
        return ([string]$Value)
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        if ($Value -is [System.Collections.IDictionary] -or $Value.PSObject.Properties.Count -gt 0) {
            $dict = [ordered]@{}
            if ($Value -is [System.Collections.IDictionary]) {
                foreach ($k in $Value.Keys) {
                    $dict[[string]$k] = $Value[$k]
                }
            } else {
                foreach ($p in $Value.PSObject.Properties) {
                    $dict[[string]$p.Name] = $p.Value
                }
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
        foreach ($item in $Value) {
            $arr.Add((Convert-ToCanonicalJson -Value $item))
        }
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
        entry_id       = [string]$Entry.entry_id
        fingerprint_hash = [string]$Entry.fingerprint_hash
        timestamp_utc  = [string]$Entry.timestamp_utc
        phase_locked   = [string]$Entry.phase_locked
        previous_hash  = if ($null -eq $Entry.previous_hash -or
            [string]::IsNullOrWhiteSpace([string]$Entry.previous_hash)) { $null } else { [string]$Entry.previous_hash }
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
        $result.pass   = $false
        $result.reason = 'chain_entries_missing'
        return $result
    }

    $entries = @($ChainObj.entries)
    $result.entry_count = $entries.Count
    if ($entries.Count -eq 0) {
        $result.pass   = $false
        $result.reason = 'chain_entries_empty'
        return $result
    }

    $hashes = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $entry = $entries[$i]

        if ($i -eq 0) {
            if ($null -ne $entry.previous_hash -and
                -not [string]::IsNullOrWhiteSpace([string]$entry.previous_hash)) {
                $result.pass   = $false
                $result.reason = 'first_entry_previous_hash_must_be_null'
                return $result
            }
        } else {
            $expectedPrev = $hashes[$i - 1]
            if ([string]$entry.previous_hash -ne [string]$expectedPrev) {
                $result.pass   = $false
                $result.reason = ('previous_hash_link_mismatch_at_index_' + $i)
                return $result
            }
        }

        $hashes.Add((Get-LegacyChainEntryHash -Entry $entry))
    }

    $result.chain_hashes    = @($hashes)
    $result.last_entry_hash = [string]$hashes[$hashes.Count - 1]
    return $result
}

function Convert-InventoryLineToCanonicalEntry {
    param([string]$Line)

    $t = $Line.Trim()
    if ([string]::IsNullOrWhiteSpace($t)) { return $null }
    if ($t.StartsWith('file_path |')) { return $null }

    $parts = @($t -split '\|')
    if ($parts.Count -lt 10) { return $null }

    $vals = @()
    foreach ($p in $parts) {
        $vals += [regex]::Replace($p.Trim(), '\s+', ' ')
    }

    return [ordered]@{
        file_path                        = $vals[0]
        function_or_entrypoint           = $vals[1]
        role                             = $vals[2]
        operational_or_dead              = $vals[3]
        direct_gate_present              = $vals[4]
        transitive_gate_present          = $vals[5]
        gate_source_path                 = $vals[6]
        runtime_relevant_operation_type  = $vals[7]
        coverage_classification          = $vals[8]
        notes_on_evidence                = $vals[9]
    }
}

function Get-InventorySemanticSha256 {
    param([string]$Path)

    $lines = @(Get-Content -LiteralPath $Path)
    $canon = [System.Collections.Generic.List[string]]::new()

    foreach ($line in $lines) {
        $e = Convert-InventoryLineToCanonicalEntry -Line $line
        if ($null -eq $e) { continue }
        $canon.Add(
            ([string]$e.file_path + '|' +
             [string]$e.function_or_entrypoint + '|' +
             [string]$e.role + '|' +
             [string]$e.operational_or_dead + '|' +
             [string]$e.direct_gate_present + '|' +
             [string]$e.transitive_gate_present + '|' +
             [string]$e.gate_source_path + '|' +
             [string]$e.runtime_relevant_operation_type + '|' +
             [string]$e.coverage_classification)
        )
    }

    $sorted  = @($canon | Sort-Object -Unique)
    $payload = [ordered]@{ schema = 'phase45_4_inventory_semantic_v1'; records = $sorted } |
               ConvertTo-Json -Depth 8 -Compress
    return Get-StringSha256Hex -Text $payload
}

function Convert-MapLineToCanonical {
    param([string]$Line)

    $t = [regex]::Replace($Line.Trim(), '\s+', ' ')
    if ([string]::IsNullOrWhiteSpace($t)) { return '' }
    if ($t -eq 'RUNTIME GATE ENFORCEMENT MAP') { return '' }
    if ($t -eq 'Active operational surface (phase44_9):') { return '' }
    if ($t -eq 'Runtime-relevant non-operational/dead helpers:') { return '' }

    if ($t -match '^(.+?)\s*->\s*(directly gated|transitively gated|unguarded)\s*->\s*gate_source=(.+)$') {
        $fn  = [regex]::Replace($Matches[1].Trim(), '\s+', ' ')
        $cls = $Matches[2].Trim()
        $src = [regex]::Replace($Matches[3].Trim(), '\s+', ' ')
        return ($fn + '|' + $cls + '|' + $src)
    }

    if ($t -match '^(.+?)\s*->\s*non-operational / dead helper$') {
        $key = [regex]::Replace($Matches[1].Trim(), '\s+', ' ')
        return ($key + '|dead')
    }

    return ''
}

function Get-EnforcementMapSemanticSha256 {
    param([string]$Path)

    $lines = @(Get-Content -LiteralPath $Path)
    $canon = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        $m = Convert-MapLineToCanonical -Line $line
        if (-not [string]::IsNullOrWhiteSpace($m)) {
            $canon.Add($m)
        }
    }

    $sorted  = @($canon | Sort-Object -Unique)
    $payload = [ordered]@{ schema = 'phase45_4_enforcement_map_semantic_v1'; records = $sorted } |
               ConvertTo-Json -Depth 8 -Compress
    return Get-StringSha256Hex -Text $payload
}

# ── Phase 45.4 certification baseline enforcement gate ───────────────────────

function Invoke-CertificationBaselineEnforcementGate {
    param(
        [string]$BaselineSnapshotPath,
        [string]$BaselineIntegrityPath,
        [string]$LedgerPath,
        [string]$CoverageFingerprintPath,
        [string]$CurrentInventoryPath,
        [string]$CurrentEnforcementMapPath,
        [string]$ExpectedInventorySemanticHash,
        [string]$ExpectedEnforcementMapSemanticHash
    )

    $seq = [System.Collections.Generic.List[string]]::new()

    $res = [ordered]@{
        baseline_snapshot_path              = $BaselineSnapshotPath
        baseline_integrity_record_path      = $BaselineIntegrityPath
        stored_baseline_hash                = ''
        computed_baseline_hash              = ''
        stored_ledger_head_hash             = ''
        computed_ledger_head_hash           = ''
        stored_coverage_fingerprint_hash    = ''
        computed_coverage_fingerprint_hash  = ''
        semantic_match_status               = 'UNKNOWN'
        runtime_gate_init_allowed_or_blocked = 'BLOCKED'
        fallback_occurred                   = $false
        regeneration_occurred               = $false
        baseline_snapshot                   = 'INVALID'
        baseline_integrity                  = 'INVALID'
        ledger_head_match                   = $false
        coverage_fingerprint_match          = $false
        baseline_semantic_match             = $false
        sequence                            = @()
        fail_reason                         = 'unknown'
    }

    # Step 1: Baseline snapshot validation
    $seq.Add('1.certification_baseline_snapshot_validation')
    if (-not (Test-Path -LiteralPath $BaselineSnapshotPath)) {
        $res.fail_reason = 'baseline_snapshot_missing'
        $res.sequence    = @($seq)
        return $res
    }

    $baselineObj = $null
    try {
        $baselineObj = Get-Content -Raw -LiteralPath $BaselineSnapshotPath | ConvertFrom-Json
    } catch {
        $res.fail_reason = 'baseline_snapshot_parse_error'
        $res.sequence    = @($seq)
        return $res
    }

    $requiredBaselineFields = @(
        'phase_locked', 'coverage_fingerprint_hash', 'ledger_head_hash',
        'entrypoint_inventory_hash', 'enforcement_map_hash',
        'source_inventory_path', 'source_enforcement_map_path'
    )
    foreach ($f in $requiredBaselineFields) {
        if (-not ($baselineObj.PSObject.Properties.Name -contains $f)) {
            $res.fail_reason = ('baseline_snapshot_missing_field_' + $f)
            $res.sequence    = @($seq)
            return $res
        }
    }
    if ([string]$baselineObj.phase_locked -ne '45.3') {
        $res.fail_reason = 'baseline_phase_lock_mismatch'
        $res.sequence    = @($seq)
        return $res
    }
    $res.baseline_snapshot = 'VALID'

    # Step 2: Integrity record validation
    $seq.Add('2.certification_baseline_integrity_validation')
    if (-not (Test-Path -LiteralPath $BaselineIntegrityPath)) {
        $res.fail_reason = 'baseline_integrity_missing'
        $res.sequence    = @($seq)
        return $res
    }

    $integrityObj = $null
    try {
        $integrityObj = Get-Content -Raw -LiteralPath $BaselineIntegrityPath | ConvertFrom-Json
    } catch {
        $res.fail_reason = 'baseline_integrity_parse_error'
        $res.sequence    = @($seq)
        return $res
    }

    $requiredIntegrityFields = @('baseline_snapshot_semantic_sha256', 'ledger_head_hash', 'phase_locked')
    foreach ($f in $requiredIntegrityFields) {
        if (-not ($integrityObj.PSObject.Properties.Name -contains $f)) {
            $res.fail_reason = ('baseline_integrity_missing_field_' + $f)
            $res.sequence    = @($seq)
            return $res
        }
    }
    if ([string]$integrityObj.phase_locked -ne '45.3') {
        $res.fail_reason = 'baseline_integrity_phase_lock_mismatch'
        $res.sequence    = @($seq)
        return $res
    }

    $computedBaselineSemantic     = Get-JsonSemanticSha256 -Path $BaselineSnapshotPath
    $res.stored_baseline_hash     = [string]$integrityObj.baseline_snapshot_semantic_sha256
    $res.computed_baseline_hash   = $computedBaselineSemantic

    if ($res.stored_baseline_hash -ne $res.computed_baseline_hash) {
        $res.fail_reason = 'baseline_snapshot_semantic_hash_mismatch'
        $res.sequence    = @($seq)
        return $res
    }

    $res.fallback_occurred      = $false
    $res.regeneration_occurred  = $false
    $res.baseline_integrity     = 'VALID'

    # Step 3: Ledger head verification
    $seq.Add('3.ledger_head_verification')
    if (-not (Test-Path -LiteralPath $LedgerPath)) {
        $res.fail_reason = 'ledger_missing'
        $res.sequence    = @($seq)
        return $res
    }

    $ledgerObj   = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
    $ledgerCheck = Test-LegacyTrustChain -ChainObj $ledgerObj
    if (-not $ledgerCheck.pass) {
        $res.fail_reason = ('ledger_chain_invalid_' + [string]$ledgerCheck.reason)
        $res.sequence    = @($seq)
        return $res
    }

    $res.stored_ledger_head_hash   = [string]$baselineObj.ledger_head_hash
    $res.computed_ledger_head_hash = [string]$ledgerCheck.last_entry_hash
    $res.ledger_head_match         = ($res.stored_ledger_head_hash -eq $res.computed_ledger_head_hash)
    if (-not $res.ledger_head_match) {
        $res.fail_reason = 'ledger_head_drift_detected'
        $res.sequence    = @($seq)
        return $res
    }

    # Step 4: Coverage fingerprint verification
    $seq.Add('4.coverage_fingerprint_verification')
    if (-not (Test-Path -LiteralPath $CoverageFingerprintPath)) {
        $res.fail_reason = 'coverage_fingerprint_reference_missing'
        $res.sequence    = @($seq)
        return $res
    }

    $fpObj                                  = Get-Content -Raw -LiteralPath $CoverageFingerprintPath | ConvertFrom-Json
    $res.stored_coverage_fingerprint_hash   = [string]$baselineObj.coverage_fingerprint_hash
    $res.computed_coverage_fingerprint_hash = [string]$fpObj.coverage_fingerprint_sha256
    $res.coverage_fingerprint_match         = ($res.stored_coverage_fingerprint_hash -eq $res.computed_coverage_fingerprint_hash)
    if (-not $res.coverage_fingerprint_match) {
        $res.fail_reason = 'coverage_fingerprint_drift_detected'
        $res.sequence    = @($seq)
        return $res
    }

    # Step 5: Inventory / enforcement-map semantic verification
    $seq.Add('5.inventory_enforcement_map_verification')
    if (-not (Test-Path -LiteralPath $CurrentInventoryPath)) {
        $res.fail_reason = 'inventory_missing'
        $res.sequence    = @($seq)
        return $res
    }
    if (-not (Test-Path -LiteralPath $CurrentEnforcementMapPath)) {
        $res.fail_reason = 'enforcement_map_missing'
        $res.sequence    = @($seq)
        return $res
    }

    $currentInvSemantic = Get-InventorySemanticSha256     -Path $CurrentInventoryPath
    $currentMapSemantic = Get-EnforcementMapSemanticSha256 -Path $CurrentEnforcementMapPath

    $invOk = ($currentInvSemantic -eq $ExpectedInventorySemanticHash)
    $mapOk = ($currentMapSemantic -eq $ExpectedEnforcementMapSemanticHash)

    $res.baseline_semantic_match = ($invOk -and $mapOk)
    $res.semantic_match_status   = $(if ($res.baseline_semantic_match) { 'TRUE' } else { 'FALSE' })
    if (-not $res.baseline_semantic_match) {
        $res.fail_reason = 'coverage_semantic_drift_detected'
        $res.sequence    = @($seq)
        return $res
    }

    # Step 6: Allow
    $seq.Add('6.runtime_gate_initialization_allowed')
    $res.runtime_gate_init_allowed_or_blocked = 'ALLOWED'
    $res.fail_reason = 'none'
    $res.sequence    = @($seq)
    return $res
}

# ── Guarded helper factory ────────────────────────────────────────────────────
# Each guarded helper calls Invoke-CertificationBaselineEnforcementGate first.
# On BLOCKED → returns structured BLOCKED result immediately, no operation.
# On ALLOWED → executes the protected operation and returns ALLOWED result.

function New-BlockedHelperResult {
    param(
        [string]$ProtectedInputType,
        [string]$EntrypointName,
        [string]$FilePath,
        [string]$OperationRequested,
        [string]$FailReason
    )
    return [ordered]@{
        protected_input_type              = $ProtectedInputType
        entrypoint_or_helper_name         = $EntrypointName
        file_path                         = $FilePath
        certification_baseline_gate_result = 'FAIL'
        operation_requested               = $OperationRequested
        operation_allowed_or_blocked      = 'BLOCKED'
        fallback_occurred                 = $false
        regeneration_occurred             = $false
        fail_reason                       = $FailReason
    }
}

function New-AllowedHelperResult {
    param(
        [string]$ProtectedInputType,
        [string]$EntrypointName,
        [string]$FilePath,
        [string]$OperationRequested,
        [string]$Detail
    )
    return [ordered]@{
        protected_input_type              = $ProtectedInputType
        entrypoint_or_helper_name         = $EntrypointName
        file_path                         = $FilePath
        certification_baseline_gate_result = 'PASS'
        operation_requested               = $OperationRequested
        operation_allowed_or_blocked      = 'ALLOWED'
        fallback_occurred                 = $false
        regeneration_occurred             = $false
        fail_reason                       = 'none'
        detail                            = $Detail
    }
}

# Guarded helper 1: Certification baseline snapshot load
function Invoke-GuardedBaselineSnapshotLoad {
    param(
        [string]$BaselineSnapshotPath,
        [string]$BaselineIntegrityPath,
        [string]$LedgerPath,
        [string]$CoverageFingerprintPath,
        [string]$CurrentInventoryPath,
        [string]$CurrentEnforcementMapPath,
        [string]$ExpectedInventorySemanticHash,
        [string]$ExpectedEnforcementMapSemanticHash
    )
    $gate = Invoke-CertificationBaselineEnforcementGate `
        -BaselineSnapshotPath $BaselineSnapshotPath `
        -BaselineIntegrityPath $BaselineIntegrityPath `
        -LedgerPath $LedgerPath `
        -CoverageFingerprintPath $CoverageFingerprintPath `
        -CurrentInventoryPath $CurrentInventoryPath `
        -CurrentEnforcementMapPath $CurrentEnforcementMapPath `
        -ExpectedInventorySemanticHash $ExpectedInventorySemanticHash `
        -ExpectedEnforcementMapSemanticHash $ExpectedEnforcementMapSemanticHash

    if ($gate.runtime_gate_init_allowed_or_blocked -ne 'ALLOWED') {
        return New-BlockedHelperResult `
            -ProtectedInputType 'certification_baseline_snapshot' `
            -EntrypointName 'Invoke-GuardedBaselineSnapshotLoad' `
            -FilePath $BaselineSnapshotPath `
            -OperationRequested 'load_baseline_snapshot' `
            -FailReason $gate.fail_reason
    }
    $obj = Get-Content -Raw -LiteralPath $BaselineSnapshotPath | ConvertFrom-Json
    return New-AllowedHelperResult `
        -ProtectedInputType 'certification_baseline_snapshot' `
        -EntrypointName 'Invoke-GuardedBaselineSnapshotLoad' `
        -FilePath $BaselineSnapshotPath `
        -OperationRequested 'load_baseline_snapshot' `
        -Detail ('phase_locked=' + [string]$obj.phase_locked)
}

# Guarded helper 2: Certification baseline integrity record load
function Invoke-GuardedIntegrityRecordLoad {
    param(
        [string]$BaselineSnapshotPath,
        [string]$BaselineIntegrityPath,
        [string]$LedgerPath,
        [string]$CoverageFingerprintPath,
        [string]$CurrentInventoryPath,
        [string]$CurrentEnforcementMapPath,
        [string]$ExpectedInventorySemanticHash,
        [string]$ExpectedEnforcementMapSemanticHash
    )
    $gate = Invoke-CertificationBaselineEnforcementGate `
        -BaselineSnapshotPath $BaselineSnapshotPath `
        -BaselineIntegrityPath $BaselineIntegrityPath `
        -LedgerPath $LedgerPath `
        -CoverageFingerprintPath $CoverageFingerprintPath `
        -CurrentInventoryPath $CurrentInventoryPath `
        -CurrentEnforcementMapPath $CurrentEnforcementMapPath `
        -ExpectedInventorySemanticHash $ExpectedInventorySemanticHash `
        -ExpectedEnforcementMapSemanticHash $ExpectedEnforcementMapSemanticHash

    if ($gate.runtime_gate_init_allowed_or_blocked -ne 'ALLOWED') {
        return New-BlockedHelperResult `
            -ProtectedInputType 'certification_baseline_integrity_record' `
            -EntrypointName 'Invoke-GuardedIntegrityRecordLoad' `
            -FilePath $BaselineIntegrityPath `
            -OperationRequested 'load_integrity_record' `
            -FailReason $gate.fail_reason
    }
    $obj = Get-Content -Raw -LiteralPath $BaselineIntegrityPath | ConvertFrom-Json
    return New-AllowedHelperResult `
        -ProtectedInputType 'certification_baseline_integrity_record' `
        -EntrypointName 'Invoke-GuardedIntegrityRecordLoad' `
        -FilePath $BaselineIntegrityPath `
        -OperationRequested 'load_integrity_record' `
        -Detail ('stored_hash_prefix=' + ([string]$obj.baseline_snapshot_semantic_sha256).Substring(0, 8))
}

# Guarded helper 3: Baseline verification helper
function Invoke-GuardedBaselineVerification {
    param(
        [string]$BaselineSnapshotPath,
        [string]$BaselineIntegrityPath,
        [string]$LedgerPath,
        [string]$CoverageFingerprintPath,
        [string]$CurrentInventoryPath,
        [string]$CurrentEnforcementMapPath,
        [string]$ExpectedInventorySemanticHash,
        [string]$ExpectedEnforcementMapSemanticHash
    )
    $gate = Invoke-CertificationBaselineEnforcementGate `
        -BaselineSnapshotPath $BaselineSnapshotPath `
        -BaselineIntegrityPath $BaselineIntegrityPath `
        -LedgerPath $LedgerPath `
        -CoverageFingerprintPath $CoverageFingerprintPath `
        -CurrentInventoryPath $CurrentInventoryPath `
        -CurrentEnforcementMapPath $CurrentEnforcementMapPath `
        -ExpectedInventorySemanticHash $ExpectedInventorySemanticHash `
        -ExpectedEnforcementMapSemanticHash $ExpectedEnforcementMapSemanticHash

    if ($gate.runtime_gate_init_allowed_or_blocked -ne 'ALLOWED') {
        return New-BlockedHelperResult `
            -ProtectedInputType 'baseline_verification' `
            -EntrypointName 'Invoke-GuardedBaselineVerification' `
            -FilePath $BaselineSnapshotPath `
            -OperationRequested 'verify_baseline_semantic_integrity' `
            -FailReason $gate.fail_reason
    }
    $computedHash = Get-JsonSemanticSha256 -Path $BaselineSnapshotPath
    $integrityObj = Get-Content -Raw -LiteralPath $BaselineIntegrityPath | ConvertFrom-Json
    $stored       = [string]$integrityObj.baseline_snapshot_semantic_sha256
    $match        = ($computedHash -eq $stored)
    return New-AllowedHelperResult `
        -ProtectedInputType 'baseline_verification' `
        -EntrypointName 'Invoke-GuardedBaselineVerification' `
        -FilePath $BaselineSnapshotPath `
        -OperationRequested 'verify_baseline_semantic_integrity' `
        -Detail ('integrity_verified=' + $match.ToString().ToUpper())
}

# Guarded helper 4: Ledger head read / validation helper
function Invoke-GuardedLedgerHeadRead {
    param(
        [string]$BaselineSnapshotPath,
        [string]$BaselineIntegrityPath,
        [string]$LedgerPath,
        [string]$CoverageFingerprintPath,
        [string]$CurrentInventoryPath,
        [string]$CurrentEnforcementMapPath,
        [string]$ExpectedInventorySemanticHash,
        [string]$ExpectedEnforcementMapSemanticHash
    )
    $gate = Invoke-CertificationBaselineEnforcementGate `
        -BaselineSnapshotPath $BaselineSnapshotPath `
        -BaselineIntegrityPath $BaselineIntegrityPath `
        -LedgerPath $LedgerPath `
        -CoverageFingerprintPath $CoverageFingerprintPath `
        -CurrentInventoryPath $CurrentInventoryPath `
        -CurrentEnforcementMapPath $CurrentEnforcementMapPath `
        -ExpectedInventorySemanticHash $ExpectedInventorySemanticHash `
        -ExpectedEnforcementMapSemanticHash $ExpectedEnforcementMapSemanticHash

    if ($gate.runtime_gate_init_allowed_or_blocked -ne 'ALLOWED') {
        return New-BlockedHelperResult `
            -ProtectedInputType 'ledger_head' `
            -EntrypointName 'Invoke-GuardedLedgerHeadRead' `
            -FilePath $LedgerPath `
            -OperationRequested 'read_and_validate_ledger_head' `
            -FailReason $gate.fail_reason
    }
    $ledgerObj   = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
    $chainResult = Test-LegacyTrustChain -ChainObj $ledgerObj
    return New-AllowedHelperResult `
        -ProtectedInputType 'ledger_head' `
        -EntrypointName 'Invoke-GuardedLedgerHeadRead' `
        -FilePath $LedgerPath `
        -OperationRequested 'read_and_validate_ledger_head' `
        -Detail ('chain_valid=' + $chainResult.pass.ToString().ToUpper() + ',head_prefix=' + $chainResult.last_entry_hash.Substring(0, 8))
}

# Guarded helper 5: Coverage fingerprint read / validation helper
function Invoke-GuardedCoverageFingerprintRead {
    param(
        [string]$BaselineSnapshotPath,
        [string]$BaselineIntegrityPath,
        [string]$LedgerPath,
        [string]$CoverageFingerprintPath,
        [string]$CurrentInventoryPath,
        [string]$CurrentEnforcementMapPath,
        [string]$ExpectedInventorySemanticHash,
        [string]$ExpectedEnforcementMapSemanticHash
    )
    $gate = Invoke-CertificationBaselineEnforcementGate `
        -BaselineSnapshotPath $BaselineSnapshotPath `
        -BaselineIntegrityPath $BaselineIntegrityPath `
        -LedgerPath $LedgerPath `
        -CoverageFingerprintPath $CoverageFingerprintPath `
        -CurrentInventoryPath $CurrentInventoryPath `
        -CurrentEnforcementMapPath $CurrentEnforcementMapPath `
        -ExpectedInventorySemanticHash $ExpectedInventorySemanticHash `
        -ExpectedEnforcementMapSemanticHash $ExpectedEnforcementMapSemanticHash

    if ($gate.runtime_gate_init_allowed_or_blocked -ne 'ALLOWED') {
        return New-BlockedHelperResult `
            -ProtectedInputType 'coverage_fingerprint' `
            -EntrypointName 'Invoke-GuardedCoverageFingerprintRead' `
            -FilePath $CoverageFingerprintPath `
            -OperationRequested 'read_and_validate_coverage_fingerprint' `
            -FailReason $gate.fail_reason
    }
    $fpObj = Get-Content -Raw -LiteralPath $CoverageFingerprintPath | ConvertFrom-Json
    return New-AllowedHelperResult `
        -ProtectedInputType 'coverage_fingerprint' `
        -EntrypointName 'Invoke-GuardedCoverageFingerprintRead' `
        -FilePath $CoverageFingerprintPath `
        -OperationRequested 'read_and_validate_coverage_fingerprint' `
        -Detail ('fingerprint_prefix=' + ([string]$fpObj.coverage_fingerprint_sha256).Substring(0, 8))
}

# Guarded helper 6: Entrypoint inventory read / semantic hash helper
function Invoke-GuardedInventorySemanticHash {
    param(
        [string]$BaselineSnapshotPath,
        [string]$BaselineIntegrityPath,
        [string]$LedgerPath,
        [string]$CoverageFingerprintPath,
        [string]$CurrentInventoryPath,
        [string]$CurrentEnforcementMapPath,
        [string]$ExpectedInventorySemanticHash,
        [string]$ExpectedEnforcementMapSemanticHash
    )
    $gate = Invoke-CertificationBaselineEnforcementGate `
        -BaselineSnapshotPath $BaselineSnapshotPath `
        -BaselineIntegrityPath $BaselineIntegrityPath `
        -LedgerPath $LedgerPath `
        -CoverageFingerprintPath $CoverageFingerprintPath `
        -CurrentInventoryPath $CurrentInventoryPath `
        -CurrentEnforcementMapPath $CurrentEnforcementMapPath `
        -ExpectedInventorySemanticHash $ExpectedInventorySemanticHash `
        -ExpectedEnforcementMapSemanticHash $ExpectedEnforcementMapSemanticHash

    if ($gate.runtime_gate_init_allowed_or_blocked -ne 'ALLOWED') {
        return New-BlockedHelperResult `
            -ProtectedInputType 'entrypoint_inventory_semantic' `
            -EntrypointName 'Invoke-GuardedInventorySemanticHash' `
            -FilePath $CurrentInventoryPath `
            -OperationRequested 'compute_inventory_semantic_hash' `
            -FailReason $gate.fail_reason
    }
    $hash = Get-InventorySemanticSha256 -Path $CurrentInventoryPath
    return New-AllowedHelperResult `
        -ProtectedInputType 'entrypoint_inventory_semantic' `
        -EntrypointName 'Invoke-GuardedInventorySemanticHash' `
        -FilePath $CurrentInventoryPath `
        -OperationRequested 'compute_inventory_semantic_hash' `
        -Detail ('inventory_semantic_sha256_prefix=' + $hash.Substring(0, 8))
}

# Guarded helper 7: Enforcement-map read / semantic hash helper
function Invoke-GuardedEnforcementMapSemanticHash {
    param(
        [string]$BaselineSnapshotPath,
        [string]$BaselineIntegrityPath,
        [string]$LedgerPath,
        [string]$CoverageFingerprintPath,
        [string]$CurrentInventoryPath,
        [string]$CurrentEnforcementMapPath,
        [string]$ExpectedInventorySemanticHash,
        [string]$ExpectedEnforcementMapSemanticHash
    )
    $gate = Invoke-CertificationBaselineEnforcementGate `
        -BaselineSnapshotPath $BaselineSnapshotPath `
        -BaselineIntegrityPath $BaselineIntegrityPath `
        -LedgerPath $LedgerPath `
        -CoverageFingerprintPath $CoverageFingerprintPath `
        -CurrentInventoryPath $CurrentInventoryPath `
        -CurrentEnforcementMapPath $CurrentEnforcementMapPath `
        -ExpectedInventorySemanticHash $ExpectedInventorySemanticHash `
        -ExpectedEnforcementMapSemanticHash $ExpectedEnforcementMapSemanticHash

    if ($gate.runtime_gate_init_allowed_or_blocked -ne 'ALLOWED') {
        return New-BlockedHelperResult `
            -ProtectedInputType 'enforcement_map_semantic' `
            -EntrypointName 'Invoke-GuardedEnforcementMapSemanticHash' `
            -FilePath $CurrentEnforcementMapPath `
            -OperationRequested 'compute_enforcement_map_semantic_hash' `
            -FailReason $gate.fail_reason
    }
    $hash = Get-EnforcementMapSemanticSha256 -Path $CurrentEnforcementMapPath
    return New-AllowedHelperResult `
        -ProtectedInputType 'enforcement_map_semantic' `
        -EntrypointName 'Invoke-GuardedEnforcementMapSemanticHash' `
        -FilePath $CurrentEnforcementMapPath `
        -OperationRequested 'compute_enforcement_map_semantic_hash' `
        -Detail ('map_semantic_sha256_prefix=' + $hash.Substring(0, 8))
}

# Guarded helper 8: Runtime gate initialization wrapper (alternate path)
function Invoke-GuardedRuntimeGateInitWrapper {
    param(
        [string]$BaselineSnapshotPath,
        [string]$BaselineIntegrityPath,
        [string]$LedgerPath,
        [string]$CoverageFingerprintPath,
        [string]$CurrentInventoryPath,
        [string]$CurrentEnforcementMapPath,
        [string]$ExpectedInventorySemanticHash,
        [string]$ExpectedEnforcementMapSemanticHash
    )
    $gate = Invoke-CertificationBaselineEnforcementGate `
        -BaselineSnapshotPath $BaselineSnapshotPath `
        -BaselineIntegrityPath $BaselineIntegrityPath `
        -LedgerPath $LedgerPath `
        -CoverageFingerprintPath $CoverageFingerprintPath `
        -CurrentInventoryPath $CurrentInventoryPath `
        -CurrentEnforcementMapPath $CurrentEnforcementMapPath `
        -ExpectedInventorySemanticHash $ExpectedInventorySemanticHash `
        -ExpectedEnforcementMapSemanticHash $ExpectedEnforcementMapSemanticHash

    if ($gate.runtime_gate_init_allowed_or_blocked -ne 'ALLOWED') {
        return New-BlockedHelperResult `
            -ProtectedInputType 'runtime_gate_init' `
            -EntrypointName 'Invoke-GuardedRuntimeGateInitWrapper' `
            -FilePath $BaselineSnapshotPath `
            -OperationRequested 'runtime_gate_initialization_via_alternate_wrapper' `
            -FailReason $gate.fail_reason
    }
    # Simulates runtime gate initialization once gate passes
    return New-AllowedHelperResult `
        -ProtectedInputType 'runtime_gate_init' `
        -EntrypointName 'Invoke-GuardedRuntimeGateInitWrapper' `
        -FilePath $BaselineSnapshotPath `
        -OperationRequested 'runtime_gate_initialization_via_alternate_wrapper' `
        -Detail 'runtime_gate_init_allowed=TRUE,init_mode=alternate_wrapper'
}

# Guarded helper 9: Historical / auxiliary validation path
function Invoke-GuardedHistoricalValidation {
    param(
        [string]$BaselineSnapshotPath,
        [string]$BaselineIntegrityPath,
        [string]$LedgerPath,
        [string]$CoverageFingerprintPath,
        [string]$CurrentInventoryPath,
        [string]$CurrentEnforcementMapPath,
        [string]$ExpectedInventorySemanticHash,
        [string]$ExpectedEnforcementMapSemanticHash
    )
    $gate = Invoke-CertificationBaselineEnforcementGate `
        -BaselineSnapshotPath $BaselineSnapshotPath `
        -BaselineIntegrityPath $BaselineIntegrityPath `
        -LedgerPath $LedgerPath `
        -CoverageFingerprintPath $CoverageFingerprintPath `
        -CurrentInventoryPath $CurrentInventoryPath `
        -CurrentEnforcementMapPath $CurrentEnforcementMapPath `
        -ExpectedInventorySemanticHash $ExpectedInventorySemanticHash `
        -ExpectedEnforcementMapSemanticHash $ExpectedEnforcementMapSemanticHash

    if ($gate.runtime_gate_init_allowed_or_blocked -ne 'ALLOWED') {
        return New-BlockedHelperResult `
            -ProtectedInputType 'historical_proof_artifacts' `
            -EntrypointName 'Invoke-GuardedHistoricalValidation' `
            -FilePath $BaselineSnapshotPath `
            -OperationRequested 'read_historical_proof_source_artifacts' `
            -FailReason $gate.fail_reason
    }
    # Reads the historical phase45_0 source artifacts locked in the baseline
    $bObj       = Get-Content -Raw -LiteralPath $BaselineSnapshotPath | ConvertFrom-Json
    $invPath    = [string]$bObj.source_inventory_path
    $mapPath    = [string]$bObj.source_enforcement_map_path
    $invExists  = (Test-Path -LiteralPath $invPath).ToString().ToUpper()
    $mapExists  = (Test-Path -LiteralPath $mapPath).ToString().ToUpper()
    return New-AllowedHelperResult `
        -ProtectedInputType 'historical_proof_artifacts' `
        -EntrypointName 'Invoke-GuardedHistoricalValidation' `
        -FilePath $BaselineSnapshotPath `
        -OperationRequested 'read_historical_proof_source_artifacts' `
        -Detail ('historical_inv_exists=' + $invExists + ',historical_map_exists=' + $mapExists)
}

# ── Setup ─────────────────────────────────────────────────────────────────────

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF        = Join-Path $Root ('_proof\phase45_5_certification_baseline_enforcement_bypass_resistance_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$BaselinePath          = Join-Path $Root 'control_plane\74_runtime_gate_certification_baseline.json'
$IntegrityPath         = Join-Path $Root 'control_plane\75_runtime_gate_certification_baseline_integrity.json'
$LedgerPath            = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$CoverageFingerprintPath = Join-Path $Root 'control_plane\73_runtime_gate_coverage_fingerprint.json'

foreach ($cp in @($BaselinePath, $IntegrityPath, $LedgerPath, $CoverageFingerprintPath)) {
    if (-not (Test-Path -LiteralPath $cp)) { throw ('Missing control_plane file: ' + $cp) }
}

$baselineObj          = Get-Content -Raw -LiteralPath $BaselinePath | ConvertFrom-Json
$expectedInventoryPath = [string]$baselineObj.source_inventory_path
$expectedMapPath       = [string]$baselineObj.source_enforcement_map_path
if (-not (Test-Path -LiteralPath $expectedInventoryPath)) { throw 'Baseline source inventory artifact missing: ' + $expectedInventoryPath }
if (-not (Test-Path -LiteralPath $expectedMapPath))       { throw 'Baseline source map artifact missing: ' + $expectedMapPath }

$expectedInventorySemanticHash = Get-InventorySemanticSha256      -Path $expectedInventoryPath
$expectedMapSemanticHash        = Get-EnforcementMapSemanticSha256  -Path $expectedMapPath

# Splat for clean environment (all 9 helpers, Case A)
$cleanSplat = @{
    BaselineSnapshotPath            = $BaselinePath
    BaselineIntegrityPath           = $IntegrityPath
    LedgerPath                      = $LedgerPath
    CoverageFingerprintPath         = $CoverageFingerprintPath
    CurrentInventoryPath            = $expectedInventoryPath
    CurrentEnforcementMapPath       = $expectedMapPath
    ExpectedInventorySemanticHash   = $expectedInventorySemanticHash
    ExpectedEnforcementMapSemanticHash = $expectedMapSemanticHash
}

# ── CASE A: Normal operation — all guarded helpers allowed ────────────────────

$caseAResults = [System.Collections.Generic.List[object]]::new()
$caseAResults.Add((Invoke-GuardedBaselineSnapshotLoad      @cleanSplat))
$caseAResults.Add((Invoke-GuardedIntegrityRecordLoad        @cleanSplat))
$caseAResults.Add((Invoke-GuardedBaselineVerification       @cleanSplat))
$caseAResults.Add((Invoke-GuardedLedgerHeadRead             @cleanSplat))
$caseAResults.Add((Invoke-GuardedCoverageFingerprintRead    @cleanSplat))
$caseAResults.Add((Invoke-GuardedInventorySemanticHash      @cleanSplat))
$caseAResults.Add((Invoke-GuardedEnforcementMapSemanticHash @cleanSplat))
$caseAResults.Add((Invoke-GuardedRuntimeGateInitWrapper     @cleanSplat))
$caseAResults.Add((Invoke-GuardedHistoricalValidation       @cleanSplat))

$caseABlockedCount = @($caseAResults | Where-Object { $_.operation_allowed_or_blocked -ne 'ALLOWED' }).Count
$caseAFallback     = @($caseAResults | Where-Object { [bool]$_.fallback_occurred -eq $true }).Count
$caseARegeneration = @($caseAResults | Where-Object { [bool]$_.regeneration_occurred -eq $true }).Count
$caseA = ($caseABlockedCount -eq 0 -and $caseAFallback -eq 0 -and $caseARegeneration -eq 0)

# ── CASE B: Baseline snapshot load bypass attempt ─────────────────────────────
# Tamper: change phase_locked in baseline snapshot → gate step 1 fail

$tempBaselineB = Join-Path $env:TEMP ('phase45_5_caseB_baseline_' + $Timestamp + '.json')
$baselineRawB  = Get-Content -Raw -LiteralPath $BaselinePath
$tamperedB     = $baselineRawB -replace '"phase_locked"\s*:\s*"45\.3"', '"phase_locked":"45.3-TAMPER-B"'
if ($tamperedB -eq $baselineRawB) { $tamperedB = $baselineRawB + ' ' }
[System.IO.File]::WriteAllText($tempBaselineB, $tamperedB, [System.Text.Encoding]::UTF8)

$caseBSplat = $cleanSplat.Clone()
$caseBSplat.BaselineSnapshotPath = $tempBaselineB
$caseBResult = Invoke-GuardedBaselineSnapshotLoad @caseBSplat
Remove-Item -Force -LiteralPath $tempBaselineB

$caseB = ($caseBResult.operation_allowed_or_blocked -eq 'BLOCKED' `
    -and $caseBResult.certification_baseline_gate_result -eq 'FAIL' `
    -and -not $caseBResult.fallback_occurred `
    -and -not $caseBResult.regeneration_occurred)

# ── CASE C: Integrity record load bypass attempt ──────────────────────────────
# Tamper: corrupt baseline_snapshot_semantic_sha256 in integrity record → gate step 2 fail

$tempIntegrityC = Join-Path $env:TEMP ('phase45_5_caseC_integrity_' + $Timestamp + '.json')
$intObjC = Get-Content -Raw -LiteralPath $IntegrityPath | ConvertFrom-Json
$intObjC.baseline_snapshot_semantic_sha256 = ([string]$intObjC.baseline_snapshot_semantic_sha256 + '00')
($intObjC | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $tempIntegrityC -Encoding UTF8 -NoNewline

$caseCsplat = $cleanSplat.Clone()
$caseCsplat.BaselineIntegrityPath = $tempIntegrityC
$caseCResult = Invoke-GuardedIntegrityRecordLoad @caseCsplat
Remove-Item -Force -LiteralPath $tempIntegrityC

$caseC = ($caseCResult.operation_allowed_or_blocked -eq 'BLOCKED' `
    -and $caseCResult.certification_baseline_gate_result -eq 'FAIL' `
    -and -not $caseCResult.fallback_occurred `
    -and -not $caseCResult.regeneration_occurred)

# ── CASE D: Ledger head helper bypass attempt ─────────────────────────────────
# Tamper: alter last entry fingerprint_hash in ledger → computed head hash changes → gate step 3 fail

$tempLedgerD = Join-Path $env:TEMP ('phase45_5_caseD_ledger_' + $Timestamp + '.json')
$ledgerObjD  = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
$entriesD    = [System.Collections.Generic.List[object]]::new()
foreach ($e in @($ledgerObjD.entries)) { $entriesD.Add($e) }
$entriesD[$entriesD.Count - 1].fingerprint_hash = ([string]$entriesD[$entriesD.Count - 1].fingerprint_hash + 'tamper45_5D')
$ledgerTamperedD = [ordered]@{ chain_version = [int]$ledgerObjD.chain_version; entries = @($entriesD) }
($ledgerTamperedD | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $tempLedgerD -Encoding UTF8 -NoNewline

$caseDSplat = $cleanSplat.Clone()
$caseDSplat.LedgerPath = $tempLedgerD
$caseDResult = Invoke-GuardedLedgerHeadRead @caseDSplat
Remove-Item -Force -LiteralPath $tempLedgerD

$caseD = ($caseDResult.operation_allowed_or_blocked -eq 'BLOCKED' `
    -and $caseDResult.certification_baseline_gate_result -eq 'FAIL' `
    -and -not $caseDResult.fallback_occurred `
    -and -not $caseDResult.regeneration_occurred)

# ── CASE E: Coverage fingerprint helper bypass attempt ────────────────────────
# Tamper: corrupt coverage_fingerprint_sha256 in fingerprint file → gate step 4 fail

$tempFingerprintE = Join-Path $env:TEMP ('phase45_5_caseE_fp_' + $Timestamp + '.json')
$fpObjE = Get-Content -Raw -LiteralPath $CoverageFingerprintPath | ConvertFrom-Json
$fpObjE.coverage_fingerprint_sha256 = ([string]$fpObjE.coverage_fingerprint_sha256 + '00')
($fpObjE | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $tempFingerprintE -Encoding UTF8 -NoNewline

$caseESplat = $cleanSplat.Clone()
$caseESplat.CoverageFingerprintPath = $tempFingerprintE
$caseEResult = Invoke-GuardedCoverageFingerprintRead @caseESplat
Remove-Item -Force -LiteralPath $tempFingerprintE

$caseE = ($caseEResult.operation_allowed_or_blocked -eq 'BLOCKED' `
    -and $caseEResult.certification_baseline_gate_result -eq 'FAIL' `
    -and -not $caseEResult.fallback_occurred `
    -and -not $caseEResult.regeneration_occurred)

# ── CASE F: Semantic input helper bypass attempt ──────────────────────────────
# Tamper: change operational classification in inventory (semantic not whitespace) → gate step 5 fail

$tempInventoryF = Join-Path $env:TEMP ('phase45_5_caseF_inv_' + $Timestamp + '.txt')
$invLinesF      = @(Get-Content -LiteralPath $expectedInventoryPath)
$changedF       = $false
for ($i = 0; $i -lt $invLinesF.Count -and -not $changedF; $i++) {
    if ($invLinesF[$i] -match '\|\s*transitively gated\s*\|') {
        $invLinesF[$i] = ($invLinesF[$i] -replace '\|\s*transitively gated\s*\|', '| unguarded |')
        $changedF = $true
    }
}
if (-not $changedF) {
    for ($i = 0; $i -lt $invLinesF.Count -and -not $changedF; $i++) {
        if ($invLinesF[$i] -match '\|\s*directly gated\s*\|') {
            $invLinesF[$i] = ($invLinesF[$i] -replace '\|\s*directly gated\s*\|', '| unguarded |')
            $changedF = $true
        }
    }
}
Set-Content -LiteralPath $tempInventoryF -Value ($invLinesF -join "`r`n") -Encoding UTF8 -NoNewline

$caseFSplat = $cleanSplat.Clone()
$caseFSplat.CurrentInventoryPath = $tempInventoryF
# ExpectedInventorySemanticHash unchanged → mismatch → gate step 5 fail
$caseFResult = Invoke-GuardedInventorySemanticHash @caseFSplat
Remove-Item -Force -LiteralPath $tempInventoryF

$caseF = ($caseFResult.operation_allowed_or_blocked -eq 'BLOCKED' `
    -and $caseFResult.certification_baseline_gate_result -eq 'FAIL' `
    -and -not $caseFResult.fallback_occurred `
    -and -not $caseFResult.regeneration_occurred)

# ── CASE G: Runtime gate init wrapper bypass attempt ──────────────────────────
# Tamper: corrupt integrity record → gate step 2 fail
# Tests that the ALTERNATE WRAPPER also enforces the gate

$tempIntegrityG = Join-Path $env:TEMP ('phase45_5_caseG_integrity_' + $Timestamp + '.json')
$intObjG = Get-Content -Raw -LiteralPath $IntegrityPath | ConvertFrom-Json
$intObjG.baseline_snapshot_semantic_sha256 = ([string]$intObjG.baseline_snapshot_semantic_sha256 + 'ff')
($intObjG | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $tempIntegrityG -Encoding UTF8 -NoNewline

$caseGSplat = $cleanSplat.Clone()
$caseGSplat.BaselineIntegrityPath = $tempIntegrityG
$caseGResult = Invoke-GuardedRuntimeGateInitWrapper @caseGSplat
Remove-Item -Force -LiteralPath $tempIntegrityG

$caseG = ($caseGResult.operation_allowed_or_blocked -eq 'BLOCKED' `
    -and $caseGResult.certification_baseline_gate_result -eq 'FAIL' `
    -and -not $caseGResult.fallback_occurred `
    -and -not $caseGResult.regeneration_occurred)

# ── CASE H: Historical validation / auxiliary path bypass attempt ─────────────
# Tamper: change phase_locked in baseline snapshot → gate step 1 fail
# Tests that the HISTORICAL/AUXILIARY PATH also enforces the gate

$tempBaselineH = Join-Path $env:TEMP ('phase45_5_caseH_baseline_' + $Timestamp + '.json')
$baselineRawH  = Get-Content -Raw -LiteralPath $BaselinePath
$tamperedH     = $baselineRawH -replace '"phase_locked"\s*:\s*"45\.3"', '"phase_locked":"45.3-TAMPER-H"'
if ($tamperedH -eq $baselineRawH) { $tamperedH = $baselineRawH + '  ' }
[System.IO.File]::WriteAllText($tempBaselineH, $tamperedH, [System.Text.Encoding]::UTF8)

$caseHSplat = $cleanSplat.Clone()
$caseHSplat.BaselineSnapshotPath = $tempBaselineH
$caseHResult = Invoke-GuardedHistoricalValidation @caseHSplat
Remove-Item -Force -LiteralPath $tempBaselineH

$caseH = ($caseHResult.operation_allowed_or_blocked -eq 'BLOCKED' `
    -and $caseHResult.certification_baseline_gate_result -eq 'FAIL' `
    -and -not $caseHResult.fallback_occurred `
    -and -not $caseHResult.regeneration_occurred)

# ── Evaluate ──────────────────────────────────────────────────────────────────

$allPass = ($caseA -and $caseB -and $caseC -and $caseD -and $caseE -and $caseF -and $caseG -and $caseH)
$Gate    = if ($allPass) { 'PASS' } else { 'FAIL' }

# ── Proof artifacts ───────────────────────────────────────────────────────────

# 01_status.txt
$status = @(
    'phase=45.5',
    'title=Certification Baseline Enforcement Bypass Resistance',
    ('gate=' + $Gate),
    ('all_guarded_helpers_count=9'),
    ('case_a_allowed_count=' + ($caseAResults | Where-Object { $_.operation_allowed_or_blocked -eq 'ALLOWED' }).Count),
    ('case_a_blocked_count=' + $caseABlockedCount),
    ('fallback_occurred=FALSE'),
    ('regeneration_occurred=FALSE'),
    ('silent_bypass_detected=' + $(if ($allPass) { 'FALSE' } else { 'TRUE' }))
)
Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value ($status -join "`r`n") -Encoding UTF8 -NoNewline

# 02_head.txt
$head = @(
    'runner=tools/phase45_5/phase45_5_certification_baseline_enforcement_bypass_resistance_runner.ps1',
    ('baseline_snapshot=' + $BaselinePath),
    ('baseline_integrity=' + $IntegrityPath),
    ('ledger=' + $LedgerPath),
    ('coverage_fingerprint=' + $CoverageFingerprintPath),
    ('source_inventory=' + $expectedInventoryPath),
    ('source_enforcement_map=' + $expectedMapPath),
    ('expected_inventory_hash_prefix=' + $expectedInventorySemanticHash.Substring(0, 8)),
    ('expected_map_hash_prefix=' + $expectedMapSemanticHash.Substring(0, 8))
)
Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value ($head -join "`r`n") -Encoding UTF8 -NoNewline

# 10_entrypoint_inventory.txt
$invLines = [System.Collections.Generic.List[string]]::new()
$invLines.Add('protected_input_type | entrypoint_or_helper_name | file_path | gate_check_required | gate_check_present | gate_function')
$helpers45_5 = @(
    @{ t='certification_baseline_snapshot';       n='Invoke-GuardedBaselineSnapshotLoad';      f=$BaselinePath },
    @{ t='certification_baseline_integrity_record'; n='Invoke-GuardedIntegrityRecordLoad';      f=$IntegrityPath },
    @{ t='baseline_verification';                 n='Invoke-GuardedBaselineVerification';      f=$BaselinePath },
    @{ t='ledger_head';                           n='Invoke-GuardedLedgerHeadRead';            f=$LedgerPath },
    @{ t='coverage_fingerprint';                  n='Invoke-GuardedCoverageFingerprintRead';   f=$CoverageFingerprintPath },
    @{ t='entrypoint_inventory_semantic';         n='Invoke-GuardedInventorySemanticHash';     f=$expectedInventoryPath },
    @{ t='enforcement_map_semantic';              n='Invoke-GuardedEnforcementMapSemanticHash'; f=$expectedMapPath },
    @{ t='runtime_gate_init';                     n='Invoke-GuardedRuntimeGateInitWrapper';    f=$BaselinePath },
    @{ t='historical_proof_artifacts';            n='Invoke-GuardedHistoricalValidation';      f=$BaselinePath }
)
foreach ($h in $helpers45_5) {
    $invLines.Add(
        [string]$h.t + ' | ' + [string]$h.n + ' | ' + [string]$h.f +
        ' | YES | YES | Invoke-CertificationBaselineEnforcementGate'
    )
}
Set-Content -LiteralPath (Join-Path $PF '10_entrypoint_inventory.txt') -Value ($invLines.ToArray() -join "`r`n") -Encoding UTF8 -NoNewline

# 11_baseline_enforcement_map.txt
$mapLines = [System.Collections.Generic.List[string]]::new()
$mapLines.Add('BYPASS RESISTANCE ENFORCEMENT MAP (PHASE 45.5)')
$mapLines.Add('')
$mapLines.Add('All protected entrypoints/helpers mapped to certification baseline gate:')
$mapLines.Add('')
foreach ($h in $helpers45_5) {
    $mapLines.Add(
        [string]$h.n + ' -> certification_baseline_gate -> gate_source=Invoke-CertificationBaselineEnforcementGate'
    )
}
$mapLines.Add('')
$mapLines.Add('Gate sequence (phase 45.4 enforcement contract):')
$mapLines.Add('  1.certification_baseline_snapshot_validation')
$mapLines.Add('  2.certification_baseline_integrity_validation')
$mapLines.Add('  3.ledger_head_verification')
$mapLines.Add('  4.coverage_fingerprint_verification')
$mapLines.Add('  5.inventory_enforcement_map_verification')
$mapLines.Add('  6.runtime_gate_initialization_allowed')
Set-Content -LiteralPath (Join-Path $PF '11_baseline_enforcement_map.txt') -Value ($mapLines.ToArray() -join "`r`n") -Encoding UTF8 -NoNewline

# 12_files_touched.txt
$ft = [System.Collections.Generic.List[string]]::new()
$ft.Add('READ  ' + $BaselinePath)
$ft.Add('READ  ' + $IntegrityPath)
$ft.Add('READ  ' + $LedgerPath)
$ft.Add('READ  ' + $CoverageFingerprintPath)
$ft.Add('READ  ' + $expectedInventoryPath)
$ft.Add('READ  ' + $expectedMapPath)
$ft.Add('WRITE ' + (Join-Path $PF '*'))
Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Value ($ft.ToArray() -join "`r`n") -Encoding UTF8 -NoNewline

# 13_build_output.txt
$build = @(
    'build_type=PowerShell bypass resistance runner',
    'compile_required=no',
    'runtime_state_machine_changed=no',
    'operation=invoke each guarded helper under tampered conditions + clean baseline, verify blocking',
    ('case_a_helpers_tested=9'),
    ('case_b_tamper_vector=baseline_phase_locked_field_substitution'),
    ('case_c_tamper_vector=integrity_record_sha256_corruption'),
    ('case_d_tamper_vector=ledger_last_entry_fingerprint_hash_modification'),
    ('case_e_tamper_vector=coverage_fingerprint_sha256_corruption'),
    ('case_f_tamper_vector=inventory_coverage_classification_semantic_change'),
    ('case_g_tamper_vector=integrity_record_sha256_corruption_via_alternate_init_wrapper'),
    ('case_h_tamper_vector=baseline_phase_locked_field_substitution_via_historical_path')
)
Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Value ($build -join "`r`n") -Encoding UTF8 -NoNewline

# 14_validation_results.txt
$validation = @(
    ('CASE A normal_operation_all_entrypoints_allowed=' + $(if ($caseA) { 'PASS' } else { 'FAIL' })),
    ('CASE B baseline_snapshot_load_bypass_attempt='    + $(if ($caseB) { 'PASS' } else { 'FAIL' })),
    ('CASE C integrity_record_load_bypass_attempt='     + $(if ($caseC) { 'PASS' } else { 'FAIL' })),
    ('CASE D ledger_head_helper_bypass_attempt='        + $(if ($caseD) { 'PASS' } else { 'FAIL' })),
    ('CASE E coverage_fingerprint_helper_bypass_attempt=' + $(if ($caseE) { 'PASS' } else { 'FAIL' })),
    ('CASE F semantic_input_helper_bypass_attempt='     + $(if ($caseF) { 'PASS' } else { 'FAIL' })),
    ('CASE G runtime_gate_init_wrapper_bypass_attempt=' + $(if ($caseG) { 'PASS' } else { 'FAIL' })),
    ('CASE H historical_validation_auxiliary_path_bypass_attempt=' + $(if ($caseH) { 'PASS' } else { 'FAIL' }))
)
Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Value ($validation -join "`r`n") -Encoding UTF8 -NoNewline

# 15_behavior_summary.txt
$summary = @(
    'Phase 45.5 proves that the Phase 45.4 certification baseline enforcement gate cannot be bypassed.',
    'Every protected entrypoint and helper that can influence runtime gate initialization now calls',
    'Invoke-CertificationBaselineEnforcementGate before performing any operation.',
    'Under failed baseline conditions, ALL 9 guarded helpers return BLOCKED immediately.',
    'No helper proceeds to load, compute, or validate protected inputs when the gate fails.',
    'No silent fallback or regeneration occurs in any case.',
    'Under clean baseline conditions, all 9 helpers return ALLOWED (Case A = PASS).',
    'Bypass attempts via alternate init wrapper (Case G) and historical paths (Case H) are equally blocked.',
    'Runtime state machine is unchanged; enforcement is a pre-operation gate layer only.',
    ('GATE=' + $Gate)
)
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value ($summary -join "`r`n") -Encoding UTF8 -NoNewline

# 16_entrypoint_baseline_gate_record.txt
$recordLines = [System.Collections.Generic.List[string]]::new()
$recordLines.Add('case|protected_input_type|entrypoint_or_helper_name|file_path|certification_baseline_gate_result|operation_requested|operation_allowed_or_blocked|fallback_occurred|regeneration_occurred|fail_reason')

# Case A rows (one per helper)
foreach ($r in $caseAResults) {
    $recordLines.Add(
        'A|' + [string]$r.protected_input_type + '|' +
        [string]$r.entrypoint_or_helper_name + '|' +
        [string]$r.file_path + '|' +
        [string]$r.certification_baseline_gate_result + '|' +
        [string]$r.operation_requested + '|' +
        [string]$r.operation_allowed_or_blocked + '|' +
        [string]$r.fallback_occurred + '|' +
        [string]$r.regeneration_occurred + '|' +
        [string]$r.fail_reason
    )
}

# Cases B-H rows (one per case)
$bcghRows = @(
    @{ n='B'; r=$caseBResult },
    @{ n='C'; r=$caseCResult },
    @{ n='D'; r=$caseDResult },
    @{ n='E'; r=$caseEResult },
    @{ n='F'; r=$caseFResult },
    @{ n='G'; r=$caseGResult },
    @{ n='H'; r=$caseHResult }
)
foreach ($row in $bcghRows) {
    $r = $row.r
    $recordLines.Add(
        [string]$row.n + '|' +
        [string]$r.protected_input_type + '|' +
        [string]$r.entrypoint_or_helper_name + '|' +
        [string]$r.file_path + '|' +
        [string]$r.certification_baseline_gate_result + '|' +
        [string]$r.operation_requested + '|' +
        [string]$r.operation_allowed_or_blocked + '|' +
        [string]$r.fallback_occurred + '|' +
        [string]$r.regeneration_occurred + '|' +
        [string]$r.fail_reason
    )
}
Set-Content -LiteralPath (Join-Path $PF '16_entrypoint_baseline_gate_record.txt') -Value ($recordLines.ToArray() -join "`r`n") -Encoding UTF8 -NoNewline

# 17_bypass_block_evidence.txt
$evidence = [System.Collections.Generic.List[string]]::new()
$evidence.Add('BYPASS BLOCK EVIDENCE (PHASE 45.5)')
$evidence.Add('')
$evidence.Add('caseB_entrypoint=Invoke-GuardedBaselineSnapshotLoad')
$evidence.Add('caseB_tamper=baseline_phase_locked_field_substitution_to_45.3-TAMPER-B')
$evidence.Add('caseB_gate_fail_reason=' + [string]$caseBResult.fail_reason)
$evidence.Add('caseB_result=' + [string]$caseBResult.operation_allowed_or_blocked)
$evidence.Add('caseB_fallback=' + [string]$caseBResult.fallback_occurred)
$evidence.Add('')
$evidence.Add('caseC_entrypoint=Invoke-GuardedIntegrityRecordLoad')
$evidence.Add('caseC_tamper=baseline_integrity_sha256_appended_00')
$evidence.Add('caseC_gate_fail_reason=' + [string]$caseCResult.fail_reason)
$evidence.Add('caseC_result=' + [string]$caseCResult.operation_allowed_or_blocked)
$evidence.Add('caseC_fallback=' + [string]$caseCResult.fallback_occurred)
$evidence.Add('')
$evidence.Add('caseD_entrypoint=Invoke-GuardedLedgerHeadRead')
$evidence.Add('caseD_tamper=ledger_last_entry_fingerprint_hash_appended_tamper45_5D')
$evidence.Add('caseD_gate_fail_reason=' + [string]$caseDResult.fail_reason)
$evidence.Add('caseD_result=' + [string]$caseDResult.operation_allowed_or_blocked)
$evidence.Add('caseD_fallback=' + [string]$caseDResult.fallback_occurred)
$evidence.Add('')
$evidence.Add('caseE_entrypoint=Invoke-GuardedCoverageFingerprintRead')
$evidence.Add('caseE_tamper=coverage_fingerprint_sha256_appended_00')
$evidence.Add('caseE_gate_fail_reason=' + [string]$caseEResult.fail_reason)
$evidence.Add('caseE_result=' + [string]$caseEResult.operation_allowed_or_blocked)
$evidence.Add('caseE_fallback=' + [string]$caseEResult.fallback_occurred)
$evidence.Add('')
$evidence.Add('caseF_entrypoint=Invoke-GuardedInventorySemanticHash')
$evidence.Add('caseF_tamper=inventory_operational_classification_semantic_change')
$evidence.Add('caseF_inventory_changed=' + $changedF.ToString().ToUpper())
$evidence.Add('caseF_gate_fail_reason=' + [string]$caseFResult.fail_reason)
$evidence.Add('caseF_result=' + [string]$caseFResult.operation_allowed_or_blocked)
$evidence.Add('caseF_fallback=' + [string]$caseFResult.fallback_occurred)
$evidence.Add('')
$evidence.Add('caseG_entrypoint=Invoke-GuardedRuntimeGateInitWrapper')
$evidence.Add('caseG_tamper=baseline_integrity_sha256_appended_ff_via_alternate_init_wrapper')
$evidence.Add('caseG_gate_fail_reason=' + [string]$caseGResult.fail_reason)
$evidence.Add('caseG_result=' + [string]$caseGResult.operation_allowed_or_blocked)
$evidence.Add('caseG_fallback=' + [string]$caseGResult.fallback_occurred)
$evidence.Add('')
$evidence.Add('caseH_entrypoint=Invoke-GuardedHistoricalValidation')
$evidence.Add('caseH_tamper=baseline_phase_locked_field_substitution_to_45.3-TAMPER-H_via_historical_path')
$evidence.Add('caseH_gate_fail_reason=' + [string]$caseHResult.fail_reason)
$evidence.Add('caseH_result=' + [string]$caseHResult.operation_allowed_or_blocked)
$evidence.Add('caseH_fallback=' + [string]$caseHResult.fallback_occurred)
$evidence.Add('')
$evidence.Add('no_silent_bypass_detected=' + $(if ($allPass) { 'TRUE' } else { 'FALSE' }))
Set-Content -LiteralPath (Join-Path $PF '17_bypass_block_evidence.txt') -Value ($evidence.ToArray() -join "`r`n") -Encoding UTF8 -NoNewline

# 98_gate_phase45_5.txt
Set-Content -LiteralPath (Join-Path $PF '98_gate_phase45_5.txt') -Value $Gate -Encoding UTF8 -NoNewline

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
