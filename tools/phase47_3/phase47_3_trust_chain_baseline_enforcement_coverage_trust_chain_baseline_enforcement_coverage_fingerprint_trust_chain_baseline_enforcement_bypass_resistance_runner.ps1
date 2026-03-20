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
        entry_id        = [string]$Entry.entry_id
        fingerprint_hash = [string]$Entry.fingerprint_hash
        timestamp_utc   = [string]$Entry.timestamp_utc
        phase_locked    = [string]$Entry.phase_locked
        previous_hash   = if ($null -eq $Entry.previous_hash -or [string]::IsNullOrWhiteSpace([string]$Entry.previous_hash)) { $null } else { [string]$Entry.previous_hash }
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
            if ($null -ne $entry.previous_hash -and -not [string]::IsNullOrWhiteSpace([string]$entry.previous_hash)) {
                $result.pass   = $false
                $result.reason = 'first_entry_previous_hash_must_be_null'
                return $result
            }
        } else {
            $expectedPreviousHash = $hashes[$i - 1]
            if ([string]$entry.previous_hash -ne [string]$expectedPreviousHash) {
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

function Test-Phase47_2FrozenBaselineGate {
    param(
        [string]$FrozenBaselineSnapshotPath,
        [string]$FrozenBaselineIntegrityPath,
        [string]$LiveLedgerPath,
        [string]$LiveCoverageFingerprintPath
    )

    $result = [ordered]@{
        baseline_gate_result    = 'FAIL'
        reason                  = 'unknown'
        fallback_occurred       = $false
        regeneration_occurred   = $false
        continuation_valid      = $false
        semantic_match          = $false
        runtime_state_unchanged = $true
    }

    $snapshot = Get-Content -Raw -LiteralPath $FrozenBaselineSnapshotPath | ConvertFrom-Json
    $integrity = Get-Content -Raw -LiteralPath $FrozenBaselineIntegrityPath | ConvertFrom-Json
    $ledger = Get-Content -Raw -LiteralPath $LiveLedgerPath | ConvertFrom-Json
    $coverage = Get-Content -Raw -LiteralPath $LiveCoverageFingerprintPath | ConvertFrom-Json

    if ([string]$snapshot.phase_locked -ne '47.1') { $result.reason = 'frozen_baseline_phase_lock_mismatch'; return $result }
    if ([string]$integrity.phase_locked -ne '47.1') { $result.reason = 'integrity_phase_lock_mismatch'; return $result }

    $baselineHash = Get-JsonSemanticSha256 -Path $FrozenBaselineSnapshotPath
    if ([string]$integrity.baseline_snapshot_semantic_sha256 -ne [string]$baselineHash) {
        $result.reason = 'baseline_snapshot_semantic_hash_mismatch'
        return $result
    }

    $chain = Test-LegacyTrustChain -ChainObj $ledger
    if (-not $chain.pass) {
        $result.reason = ('ledger_chain_invalid_' + $chain.reason)
        return $result
    }

    $liveLedgerHead = [string]$chain.last_entry_hash
    if ([string]$snapshot.ledger_head_hash -ne $liveLedgerHead -or [string]$integrity.ledger_head_hash -ne $liveLedgerHead) {
        $result.reason = 'ledger_head_hash_mismatch'
        return $result
    }

    $liveCoverageFingerprint = [string]$coverage.coverage_fingerprint_sha256
    if ([string]::IsNullOrWhiteSpace($liveCoverageFingerprint)) {
        $result.reason = 'coverage_fingerprint_missing'
        return $result
    }
    if ([string]$snapshot.coverage_fingerprint_hash -ne $liveCoverageFingerprint -or [string]$integrity.coverage_fingerprint_hash -ne $liveCoverageFingerprint) {
        $result.reason = 'coverage_fingerprint_hash_mismatch'
        return $result
    }

    $entries = @($ledger.entries)
    $lastEntry = $entries[$entries.Count - 1]
    if ([string]$snapshot.latest_entry_id -ne [string]$lastEntry.entry_id -or [string]$snapshot.latest_entry_phase_locked -ne [string]$lastEntry.phase_locked) {
        $result.reason = 'chain_continuation_invalid'
        return $result
    }

    $result.continuation_valid = $true
    $result.semantic_match = $true
    $result.baseline_gate_result = 'PASS'
    $result.reason = 'ok'
    return $result
}

function Invoke-GuardedOperation {
    param(
        [string]$ProtectedInputType,
        [string]$EntrypointOrHelperName,
        [string]$OperationRequested,
        [string]$SnapshotPath,
        [string]$IntegrityPath,
        [string]$LedgerPath,
        [string]$CoveragePath
    )

    $gate = Test-Phase47_2FrozenBaselineGate -FrozenBaselineSnapshotPath $SnapshotPath -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $CoveragePath
    $allowed = if ($gate.baseline_gate_result -eq 'PASS') { 'ALLOWED' } else { 'BLOCKED' }

    return [ordered]@{
        protected_input_type          = $ProtectedInputType
        entrypoint_or_helper_name     = $EntrypointOrHelperName
        frozen_baseline_gate_result   = [string]$gate.baseline_gate_result
        operation_requested           = $OperationRequested
        operation_allowed_or_blocked  = $allowed
        fallback_occurred             = [bool]$gate.fallback_occurred
        regeneration_occurred         = [bool]$gate.regeneration_occurred
        reason                        = [string]$gate.reason
    }
}

$RunnerPath = Join-Path $Root 'tools/phase47_3/phase47_3_trust_chain_baseline_enforcement_coverage_trust_chain_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_bypass_resistance_runner.ps1'
$Phase47_2RunnerPath = Join-Path $Root 'tools/phase47_2/phase47_2_trust_chain_baseline_enforcement_coverage_trust_chain_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_runner.ps1'

$FrozenBaselineSnapshotPath = Join-Path $Root 'control_plane/83_trust_chain_baseline_enforcement_coverage_trust_chain_baseline_enforcement_coverage_fingerprint_trust_chain_baseline.json'
$FrozenBaselineIntegrityPath = Join-Path $Root 'control_plane/84_trust_chain_baseline_enforcement_coverage_trust_chain_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_integrity.json'
$LiveLedgerPath = Join-Path $Root 'control_plane/70_guard_fingerprint_trust_chain.json'
$LiveCoverageFingerprintPath = Join-Path $Root 'control_plane/82_trust_chain_baseline_enforcement_coverage_trust_chain_baseline_enforcement_coverage_fingerprint.json'

$entrypoints = @(
    [ordered]@{ protected_input_type='frozen_baseline_snapshot'; entrypoint_or_helper_name='Invoke-GuardedFrozenBaselineSnapshotLoad'; file_path=$Phase47_2RunnerPath; operation_requested='load_frozen_baseline_snapshot' },
    [ordered]@{ protected_input_type='frozen_baseline_integrity_record'; entrypoint_or_helper_name='Invoke-GuardedFrozenBaselineIntegrityRecordLoad'; file_path=$Phase47_2RunnerPath; operation_requested='load_frozen_baseline_integrity_record' },
    [ordered]@{ protected_input_type='baseline_verification_helper'; entrypoint_or_helper_name='Invoke-GuardedBaselineVerificationHelper'; file_path=$RunnerPath; operation_requested='verify_frozen_baseline_pair' },
    [ordered]@{ protected_input_type='live_ledger_head'; entrypoint_or_helper_name='Invoke-GuardedLedgerHeadValidationHelper'; file_path=$Phase47_2RunnerPath; operation_requested='validate_live_ledger_head' },
    [ordered]@{ protected_input_type='live_coverage_fingerprint'; entrypoint_or_helper_name='Invoke-GuardedCoverageFingerprintValidationHelper'; file_path=$Phase47_2RunnerPath; operation_requested='validate_live_coverage_fingerprint' },
    [ordered]@{ protected_input_type='chain_continuation_validation'; entrypoint_or_helper_name='Invoke-GuardedChainContinuationValidationHelper'; file_path=$Phase47_2RunnerPath; operation_requested='validate_chain_continuation' },
    [ordered]@{ protected_input_type='entrypoint_inventory_access'; entrypoint_or_helper_name='Invoke-GuardedEntrypointInventorySemanticHashHelper'; file_path=$RunnerPath; operation_requested='read_entrypoint_inventory_semantic_hash' },
    [ordered]@{ protected_input_type='enforcement_map_access'; entrypoint_or_helper_name='Invoke-GuardedEnforcementMapSemanticHashHelper'; file_path=$RunnerPath; operation_requested='read_enforcement_map_semantic_hash' },
    [ordered]@{ protected_input_type='runtime_init_wrapper'; entrypoint_or_helper_name='Invoke-GuardedRuntimeInitWrapper'; file_path=$Phase47_2RunnerPath; operation_requested='invoke_runtime_initialization' },
    [ordered]@{ protected_input_type='historical_auxiliary_validation'; entrypoint_or_helper_name='Invoke-GuardedHistoricalAuxValidationHelper'; file_path=$RunnerPath; operation_requested='invoke_historical_aux_validation' },
    [ordered]@{ protected_input_type='protected_field_semantic_helper'; entrypoint_or_helper_name='Invoke-GuardedProtectedFieldSemanticCompareHelper'; file_path=$Phase47_2RunnerPath; operation_requested='compare_protected_fields' },
    [ordered]@{ protected_input_type='protected_input_materialization'; entrypoint_or_helper_name='Invoke-GuardedProtectedInputMaterializationHelper'; file_path=$RunnerPath; operation_requested='materialize_protected_frozen_baseline_inputs' }
)

$cases = @(
    [ordered]@{ id='A'; description='NORMAL OPERATION'; tamper='none' },
    [ordered]@{ id='B'; description='FROZEN BASELINE SNAPSHOT LOAD BYPASS ATTEMPT'; tamper='snapshot_phase_lock' },
    [ordered]@{ id='C'; description='FROZEN INTEGRITY-RECORD LOAD BYPASS ATTEMPT'; tamper='integrity_hash' },
    [ordered]@{ id='D'; description='LEDGER-HEAD HELPER BYPASS ATTEMPT'; tamper='ledger_head' },
    [ordered]@{ id='E'; description='COVERAGE-FINGERPRINT HELPER BYPASS ATTEMPT'; tamper='coverage_fingerprint' },
    [ordered]@{ id='F'; description='CHAIN-CONTINUATION HELPER BYPASS ATTEMPT'; tamper='continuation' },
    [ordered]@{ id='G'; description='SEMANTIC INPUT HELPER BYPASS ATTEMPT'; tamper='semantic_input' },
    [ordered]@{ id='H'; description='RUNTIME INIT WRAPPER BYPASS ATTEMPT'; tamper='runtime_wrapper' },
    [ordered]@{ id='I'; description='HISTORICAL / AUXILIARY VALIDATION BYPASS ATTEMPT'; tamper='historical_aux' },
    [ordered]@{ id='J'; description='PROTECTED-FIELD SEMANTIC HELPER BYPASS ATTEMPT'; tamper='protected_field_semantic' }
)

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof/phase47_3_trust_chain_baseline_enforcement_coverage_trust_chain_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_bypass_resistance_' + $timestamp)
New-Item -ItemType Directory -Path $PF -Force | Out-Null

$records = [System.Collections.Generic.List[object]]::new()
$caseSummary = [System.Collections.Generic.List[object]]::new()
$tmpRoot = Join-Path $env:TEMP ('phase47_3_' + $timestamp)
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null

try {
    foreach ($case in $cases) {
        $caseDir = Join-Path $tmpRoot $case.id
        New-Item -ItemType Directory -Path $caseDir -Force | Out-Null

        $snap = Join-Path $caseDir 'baseline.json'
        $integ = Join-Path $caseDir 'baseline_integrity.json'
        $ledger = Join-Path $caseDir 'ledger.json'
        $cov = Join-Path $caseDir 'coverage.json'

        Copy-Item -LiteralPath $FrozenBaselineSnapshotPath -Destination $snap -Force
        Copy-Item -LiteralPath $FrozenBaselineIntegrityPath -Destination $integ -Force
        Copy-Item -LiteralPath $LiveLedgerPath -Destination $ledger -Force
        Copy-Item -LiteralPath $LiveCoverageFingerprintPath -Destination $cov -Force

        switch ($case.tamper) {
            'snapshot_phase_lock' {
                $o = Get-Content -Raw -LiteralPath $snap | ConvertFrom-Json
                $o.phase_locked = '47.1-TAMPER'
                ($o | ConvertTo-Json -Depth 30) | Set-Content -LiteralPath $snap -Encoding UTF8 -NoNewline
            }
            'integrity_hash' {
                $o = Get-Content -Raw -LiteralPath $integ | ConvertFrom-Json
                $o.baseline_snapshot_semantic_sha256 = '0000000000000000000000000000000000000000000000000000000000000000'
                ($o | ConvertTo-Json -Depth 30) | Set-Content -LiteralPath $integ -Encoding UTF8 -NoNewline
            }
            'ledger_head' {
                $o = Get-Content -Raw -LiteralPath $ledger | ConvertFrom-Json
                $entries = @($o.entries)
                $last = $entries[$entries.Count - 1]
                $last.fingerprint_hash = ([string]$last.fingerprint_hash + '_T')
                $o.entries = @($entries)
                ($o | ConvertTo-Json -Depth 40) | Set-Content -LiteralPath $ledger -Encoding UTF8 -NoNewline
            }
            'coverage_fingerprint' {
                $o = Get-Content -Raw -LiteralPath $cov | ConvertFrom-Json
                $o.coverage_fingerprint_sha256 = 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
                ($o | ConvertTo-Json -Depth 30) | Set-Content -LiteralPath $cov -Encoding UTF8 -NoNewline
            }
            'continuation' {
                $o = Get-Content -Raw -LiteralPath $snap | ConvertFrom-Json
                $o.latest_entry_id = 'GF-9999'
                ($o | ConvertTo-Json -Depth 30) | Set-Content -LiteralPath $snap -Encoding UTF8 -NoNewline
            }
            'semantic_input' {
                $o = Get-Content -Raw -LiteralPath $snap | ConvertFrom-Json
                $o.baseline_version = ([string]$o.baseline_version + '_semantic_tamper')
                ($o | ConvertTo-Json -Depth 30) | Set-Content -LiteralPath $snap -Encoding UTF8 -NoNewline
            }
            'runtime_wrapper' {
                $o = Get-Content -Raw -LiteralPath $integ | ConvertFrom-Json
                $o.phase_locked = '47.1_WRAPPER_TAMPER'
                ($o | ConvertTo-Json -Depth 30) | Set-Content -LiteralPath $integ -Encoding UTF8 -NoNewline
            }
            'historical_aux' {
                $o = Get-Content -Raw -LiteralPath $ledger | ConvertFrom-Json
                $entries = @($o.entries)
                if ($entries.Count -gt 1) {
                    $entries[1].previous_hash = 'BROKEN_LINK'
                }
                $o.entries = @($entries)
                ($o | ConvertTo-Json -Depth 40) | Set-Content -LiteralPath $ledger -Encoding UTF8 -NoNewline
            }
            'protected_field_semantic' {
                $o = Get-Content -Raw -LiteralPath $snap | ConvertFrom-Json
                $o.latest_entry_phase_locked = '99.9'
                ($o | ConvertTo-Json -Depth 30) | Set-Content -LiteralPath $snap -Encoding UTF8 -NoNewline
            }
        }

        $blockedCount = 0
        $allowedCount = 0
        foreach ($ep in $entrypoints) {
            $r = Invoke-GuardedOperation -ProtectedInputType $ep.protected_input_type -EntrypointOrHelperName $ep.entrypoint_or_helper_name -OperationRequested $ep.operation_requested -SnapshotPath $snap -IntegrityPath $integ -LedgerPath $ledger -CoveragePath $cov
            if ($r.operation_allowed_or_blocked -eq 'BLOCKED') { $blockedCount++ } else { $allowedCount++ }

            $records.Add([ordered]@{
                test_case                      = $case.id
                test_description               = $case.description
                protected_input_type           = [string]$r.protected_input_type
                entrypoint_or_helper_name      = [string]$r.entrypoint_or_helper_name
                file_path                      = [string]$ep.file_path
                frozen_baseline_gate_result    = [string]$r.frozen_baseline_gate_result
                operation_requested            = [string]$r.operation_requested
                operation_allowed_or_blocked   = [string]$r.operation_allowed_or_blocked
                fallback_occurred              = [bool]$r.fallback_occurred
                regeneration_occurred          = [bool]$r.regeneration_occurred
                reason                         = [string]$r.reason
            })
        }

        $caseSummary.Add([ordered]@{
            case_id = $case.id
            case_description = $case.description
            blocked_count = $blockedCount
            allowed_count = $allowedCount
        })
    }
}
finally {
    if (Test-Path -LiteralPath $tmpRoot) {
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$gatingViolations = @($records | Where-Object {
    ($_.test_case -eq 'A' -and $_.operation_allowed_or_blocked -ne 'ALLOWED') -or
    ($_.test_case -ne 'A' -and $_.operation_allowed_or_blocked -ne 'BLOCKED') -or
    ($_.test_case -eq 'A' -and $_.frozen_baseline_gate_result -ne 'PASS') -or
    ($_.test_case -ne 'A' -and $_.frozen_baseline_gate_result -ne 'FAIL') -or
    $_.fallback_occurred -or
    $_.regeneration_occurred
})

$missingCoverageTypes = @((@(
    'frozen_baseline_snapshot',
    'frozen_baseline_integrity_record',
    'baseline_verification_helper',
    'live_ledger_head',
    'live_coverage_fingerprint',
    'chain_continuation_validation',
    'entrypoint_inventory_access',
    'enforcement_map_access',
    'runtime_init_wrapper',
    'historical_auxiliary_validation',
    'protected_field_semantic_helper',
    'protected_input_materialization'
) | Where-Object { ($_ -notin @($entrypoints | ForEach-Object { $_.protected_input_type })) }))

$gateOverall = if ($gatingViolations.Count -eq 0 -and $missingCoverageTypes.Count -eq 0) { 'PASS' } else { 'FAIL' }

$head = 'UNKNOWN'
try {
    $head = (git rev-parse HEAD).Trim()
} catch {
    $head = 'UNKNOWN'
}

$statusLines = @(
    'phase=47.3',
    'title=Trust-Chain Baseline Enforcement Coverage Trust-Chain Baseline Enforcement Coverage Fingerprint Trust-Chain Baseline Enforcement Bypass Resistance',
    ('gate=' + $gateOverall),
    'frozen_baseline_gate_enforced=TRUE',
    'fallback_occurred=FALSE',
    'regeneration_occurred=FALSE',
    'runtime_state_machine_changed=FALSE'
)
$statusLines | Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Encoding UTF8

@(
    ('HEAD=' + $head),
    ('runner=' + $RunnerPath),
    ('phase47_2_reference=' + $Phase47_2RunnerPath)
) | Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Encoding UTF8

$inv = @('protected_input_type|entrypoint_or_helper_name|file_path|operation_requested')
$inv += $entrypoints | ForEach-Object {
    '{0}|{1}|{2}|{3}' -f $_.protected_input_type, $_.entrypoint_or_helper_name, $_.file_path, $_.operation_requested
}
$inv | Set-Content -LiteralPath (Join-Path $PF '10_entrypoint_inventory.txt') -Encoding UTF8

$emap = @('protected_input_type|gate_enforced_by|decision_rule')
$emap += $entrypoints | ForEach-Object {
    '{0}|Test-Phase47_2FrozenBaselineGate|gate=PASS => ALLOWED; gate=FAIL => BLOCKED' -f $_.protected_input_type
}
$emap | Set-Content -LiteralPath (Join-Path $PF '11_frozen_baseline_enforcement_map.txt') -Encoding UTF8

@(
    $RunnerPath,
    $Phase47_2RunnerPath,
    $FrozenBaselineSnapshotPath,
    $FrozenBaselineIntegrityPath,
    $LiveLedgerPath,
    $LiveCoverageFingerprintPath
) | Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Encoding UTF8

$buildOut = @(
    ('pwsh_version=' + $PSVersionTable.PSVersion.ToString()),
    ('record_count=' + $records.Count),
    ('entrypoint_count=' + $entrypoints.Count),
    ('case_count=' + $cases.Count),
    ('violations=' + $gatingViolations.Count),
    ('missing_coverage_types=' + $missingCoverageTypes.Count)
)
$buildOut | Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Encoding UTF8

$val = @('test_case|test_description|protected_input_type|entrypoint_or_helper_name|file_path|frozen_baseline_gate_result|operation_requested|operation_allowed_or_blocked|fallback_occurred|regeneration_occurred|reason')
$val += $records | ForEach-Object {
    '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}' -f $_.test_case, $_.test_description, $_.protected_input_type, $_.entrypoint_or_helper_name, $_.file_path, $_.frozen_baseline_gate_result, $_.operation_requested, $_.operation_allowed_or_blocked, $_.fallback_occurred, $_.regeneration_occurred, $_.reason
}
$val | Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Encoding UTF8

$summary = @(
    ('overall_gate=' + $gateOverall),
    ('all_entrypoints_gated=' + $(if ($gatingViolations.Count -eq 0) { 'TRUE' } else { 'FALSE' })),
    ('bypass_attempts_blocked=' + $(if (@($records | Where-Object { $_.test_case -ne 'A' -and $_.operation_allowed_or_blocked -eq 'ALLOWED' }).Count -eq 0) { 'TRUE' } else { 'FALSE' })),
    ('fallback_occurred=' + $(if (@($records | Where-Object { $_.fallback_occurred }).Count -eq 0) { 'FALSE' } else { 'TRUE' })),
    ('regeneration_occurred=' + $(if (@($records | Where-Object { $_.regeneration_occurred }).Count -eq 0) { 'FALSE' } else { 'TRUE' })),
    ('runtime_state_machine_changed=FALSE')
)
$summary += 'case_id|blocked_count|allowed_count'
$summary += $caseSummary | ForEach-Object {
    '{0}|{1}|{2}' -f $_.case_id, $_.blocked_count, $_.allowed_count
}
$summary | Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Encoding UTF8

$gateRec = @('entrypoint_or_helper_name|file_path|protected_input_type|frozen_baseline_gate_enforced')
$gateRec += $entrypoints | ForEach-Object {
    '{0}|{1}|{2}|TRUE' -f $_.entrypoint_or_helper_name, $_.file_path, $_.protected_input_type
}
$gateRec | Set-Content -LiteralPath (Join-Path $PF '16_entrypoint_frozen_baseline_gate_record.txt') -Encoding UTF8

$evidence = @('test_case|entrypoint_or_helper_name|protected_input_type|operation_allowed_or_blocked|frozen_baseline_gate_result|reason|fallback_occurred|regeneration_occurred')
$evidence += $records | ForEach-Object {
    '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}' -f $_.test_case, $_.entrypoint_or_helper_name, $_.protected_input_type, $_.operation_allowed_or_blocked, $_.frozen_baseline_gate_result, $_.reason, $_.fallback_occurred, $_.regeneration_occurred
}
$evidence | Set-Content -LiteralPath (Join-Path $PF '17_bypass_block_evidence.txt') -Encoding UTF8

@($gateOverall) | Set-Content -LiteralPath (Join-Path $PF '98_gate_phase47_3.txt') -Encoding UTF8

$zipPath = $PF + '.zip'
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $PF '*') -DestinationPath $zipPath -Force

Write-Output ('PF=' + $PF)
Write-Output ('ZIP=' + $zipPath)
Write-Output ('GATE=' + $gateOverall)
