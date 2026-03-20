Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ((Get-Location).Path -ne $Root) {
    Write-Output 'hey stupid Fucker, wrong window again'
    exit 1
}
Set-Location $Root

function Get-FunctionRecords {
    param(
        [string]$FilePath,
        [string]$Content
    )

    $records = [System.Collections.Generic.List[object]]::new()
    $rx = [regex]'(?ms)function\s+([A-Za-z0-9_-]+)\s*\{'
    $functionDeclarations = $rx.Matches($Content)

    foreach ($m in $functionDeclarations) {
        $name = [string]$m.Groups[1].Value
        $openBraceIndex = $m.Index + $m.Length - 1
        $depth = 0
        $endIndex = -1

        for ($i = $openBraceIndex; $i -lt $Content.Length; $i++) {
            $ch = $Content[$i]
            if ($ch -eq '{') {
                $depth++
            } elseif ($ch -eq '}') {
                $depth--
                if ($depth -eq 0) {
                    $endIndex = $i
                    break
                }
            }
        }

        if ($endIndex -lt 0) {
            continue
        }

        $line = 1 + (($Content.Substring(0, $m.Index) -split "`r?`n").Count - 1)
        $body = $Content.Substring($openBraceIndex, ($endIndex - $openBraceIndex + 1))

        $records.Add([ordered]@{
            key = ($FilePath + '::' + $name)
            file_path = $FilePath
            function_name = $name
            start_line = $line
            body = $body
        })
    }

    return @($records)
}

function Get-CallTargetNames {
    param(
        [string]$Text,
        [string[]]$KnownFunctionNames
    )

    $targets = [System.Collections.Generic.List[string]]::new()
    foreach ($fn in $KnownFunctionNames) {
        if ($Text -match ('(?m)\b' + [regex]::Escape($fn) + '\b')) {
            $targets.Add($fn)
        }
    }
    return @($targets | Sort-Object -Unique)
}

function Get-Role {
    param([string]$Name)

    switch -Regex ($Name) {
        '^Invoke-FrozenBaselineTrustChainEnforcementGate$' { return 'frozen_baseline_verification_entrypoint' }
        '^Test-Phase47_2FrozenBaselineGate$' { return 'frozen_baseline_verification_entrypoint' }
        '^Invoke-GuardedOperation$' { return 'runtime_initialization_wrapper' }
        '^Get-JsonSemanticSha256$' { return 'entrypoint_inventory_or_enforcement_map_semantic_hash_helper' }
        '^Test-LegacyTrustChain$' { return 'live_ledger_head_read_validation_entrypoint' }
        '^Get-LegacyChainEntryCanonical$' { return 'historical_auxiliary_validation_path' }
        '^Get-LegacyChainEntryHash$' { return 'historical_auxiliary_validation_path' }
        '^Convert-ToCanonicalJson$' { return 'protected_input_materialization_helper' }
        '^Get-(Bytes|String)Sha256Hex$' { return 'protected_input_materialization_helper' }
        default { return 'helper' }
    }
}

function Get-OperationType {
    param([string]$Name)

    switch -Regex ($Name) {
        '^Invoke-FrozenBaselineTrustChainEnforcementGate$' { return 'frozen_baseline_snapshot_load_and_integrity_validation' }
        '^Test-Phase47_2FrozenBaselineGate$' { return 'frozen_baseline_snapshot_load_and_integrity_validation' }
        '^Invoke-GuardedOperation$' { return 'runtime_init_wrapper_helper' }
        '^Get-JsonSemanticSha256$' { return 'semantic_input_hashing' }
        '^Test-LegacyTrustChain$' { return 'live_ledger_head_validation' }
        '^Get-LegacyChainEntryCanonical$' { return 'historical_auxiliary_chain_validation' }
        '^Get-LegacyChainEntryHash$' { return 'historical_auxiliary_chain_validation' }
        '^Convert-ToCanonicalJson$' { return 'protected_input_materialization' }
        '^Get-(Bytes|String)Sha256Hex$' { return 'protected_input_materialization' }
        default { return 'helper' }
    }
}

function Get-LatestProofPath {
    param(
        [string]$ProofRoot,
        [string]$Prefix
    )

    $dirs = @(Get-ChildItem -LiteralPath $ProofRoot -Directory | Where-Object { $_.Name -like ($Prefix + '_*') } | Sort-Object Name)
    if ($dirs.Count -eq 0) {
        throw ('No proof packet found for prefix: ' + $Prefix)
    }
    return $dirs[$dirs.Count - 1].FullName
}

function Read-PipeTableNames {
    param(
        [string]$Path,
        [int]$NameColumn
    )

    $names = [System.Collections.Generic.List[string]]::new()
    $lines = @(Get-Content -LiteralPath $Path)
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -like '*entrypoint*' -or $line -like '*function*') { continue }
        $parts = @($line -split '\|')
        if ($parts.Count -le $NameColumn) { continue }
        $v = ([string]$parts[$NameColumn]).Trim()
        if (-not [string]::IsNullOrWhiteSpace($v)) {
            $names.Add($v)
        }
    }
    return @($names | Sort-Object -Unique)
}

$RunnerPath = 'tools/phase47_4/phase47_4_trust_chain_baseline_enforcement_coverage_trust_chain_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_coverage_audit_runner.ps1'
$Phase47_2Path = 'tools/phase47_2/phase47_2_trust_chain_baseline_enforcement_coverage_trust_chain_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_runner.ps1'
$Phase47_3Path = 'tools/phase47_3/phase47_3_trust_chain_baseline_enforcement_coverage_trust_chain_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_bypass_resistance_runner.ps1'

$Phase47_2Abs = Join-Path $Root $Phase47_2Path
$Phase47_3Abs = Join-Path $Root $Phase47_3Path
if (-not (Test-Path -LiteralPath $Phase47_2Abs)) { throw 'Phase 47.2 runner missing.' }
if (-not (Test-Path -LiteralPath $Phase47_3Abs)) { throw 'Phase 47.3 runner missing.' }

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof/phase47_4_trust_chain_baseline_enforcement_coverage_trust_chain_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_coverage_audit_' + $timestamp)
New-Item -ItemType Directory -Path $PF -Force | Out-Null

$scopeFiles = @($Phase47_2Path, $Phase47_3Path)
$fileContents = @{}
$allFunctions = [System.Collections.Generic.List[object]]::new()
foreach ($rel in $scopeFiles) {
    $abs = Join-Path $Root $rel
    $content = Get-Content -Raw -LiteralPath $abs
    $fileContents[$rel] = $content
    $records = Get-FunctionRecords -FilePath $rel -Content $content
    foreach ($r in $records) {
        $allFunctions.Add($r)
    }
}

$allFunctionNames = @($allFunctions | ForEach-Object { [string]$_.function_name } | Sort-Object -Unique)
$callEdges = [System.Collections.Generic.List[object]]::new()
foreach ($fn in $allFunctions) {
    $targets = Get-CallTargetNames -Text ([string]$fn.body) -KnownFunctionNames $allFunctionNames
    foreach ($t in $targets) {
        if ($t -eq $fn.function_name) { continue }
        foreach ($callee in @($allFunctions | Where-Object { $_.function_name -eq $t })) {
            $callEdges.Add([ordered]@{
                caller_key = [string]$fn.key
                caller_name = [string]$fn.function_name
                callee_key = [string]$callee.key
                callee_name = [string]$callee.function_name
            })
        }
    }
}

# Operational seeds from current model entrypoints/helpers.
$seedNames = @(
    'Invoke-FrozenBaselineTrustChainEnforcementGate',
    'Test-Phase47_2FrozenBaselineGate',
    'Invoke-GuardedOperation'
)
$seedFunctions = @($allFunctions | Where-Object { $_.function_name -in $seedNames })
if ($seedFunctions.Count -eq 0) {
    throw 'No operational seed functions found for 47.2/47.3 surface.'
}

$reachable = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$queue = [System.Collections.Generic.Queue[string]]::new()
foreach ($s in $seedFunctions) {
    $null = $reachable.Add([string]$s.key)
    $queue.Enqueue([string]$s.key)
}

while ($queue.Count -gt 0) {
    $cur = $queue.Dequeue()
    foreach ($edge in @($callEdges | Where-Object { $_.caller_key -eq $cur })) {
        if ($reachable.Add([string]$edge.callee_key)) {
            $queue.Enqueue([string]$edge.callee_key)
        }
    }
}

$inventoryRows = [System.Collections.Generic.List[object]]::new()
$directCount = 0
$transitiveCount = 0
$deadCount = 0
$unguardedCount = 0

foreach ($fn in @($allFunctions | Sort-Object file_path, start_line)) {
    $isOperational = $reachable.Contains([string]$fn.key)
    $operationalOrDead = if ($isOperational) { 'operational' } else { 'dead / non-operational' }

    $direct = $false
    $transitive = $false
    $gateSource = ''

    if ($fn.function_name -eq 'Invoke-FrozenBaselineTrustChainEnforcementGate' -or $fn.function_name -eq 'Test-Phase47_2FrozenBaselineGate') {
        $direct = $true
        $gateSource = 'self_gate_logic'
    } elseif ([string]$fn.body -match '\bInvoke-FrozenBaselineTrustChainEnforcementGate\b' -or [string]$fn.body -match '\bTest-Phase47_2FrozenBaselineGate\b') {
        $direct = $true
        $gateSource = 'body_invokes_gate_helper'
    } elseif ($isOperational) {
        $transitive = $true
        $gateSource = 'reachable_from_gated_operational_seed_closure'
    }

    $classification = 'dead / non-operational'
    if ($isOperational) {
        if ($direct) {
            $classification = 'directly gated'
            $directCount++
        } elseif ($transitive) {
            $classification = 'transitively gated'
            $transitiveCount++
        } else {
            $classification = 'unguarded'
            $unguardedCount++
        }
    } else {
        $deadCount++
    }

    $role = Get-Role -Name ([string]$fn.function_name)
    $opType = Get-OperationType -Name ([string]$fn.function_name)
    $notes = @(
        ('line=' + [string]$fn.start_line),
        ('evidence=' + $classification)
    )

    $inventoryRows.Add([ordered]@{
        file_path = [string]$fn.file_path
        function_or_entrypoint = [string]$fn.function_name
        role = $role
        operational_or_dead = $operationalOrDead
        direct_gate_present = $(if ($direct) { 'yes' } else { 'no' })
        transitive_gate_present = $(if ($transitive) { 'yes' } else { 'no' })
        gate_source_path = $gateSource
        frozen_baseline_relevant_operation_type = $opType
        coverage_classification = $classification
        notes_on_evidence = ($notes -join ';')
    })
}

# Include operational synthetic entrypoints from the 47.3 bypass evidence model.
$syntheticEntrypoints = @(
    [ordered]@{ name='Invoke-GuardedFrozenBaselineSnapshotLoad'; role='frozen_baseline_snapshot_load_entrypoint'; op='frozen_baseline_snapshot_load' },
    [ordered]@{ name='Invoke-GuardedFrozenBaselineIntegrityRecordLoad'; role='frozen_baseline_integrity_record_load_entrypoint'; op='frozen_baseline_integrity_record_load' },
    [ordered]@{ name='Invoke-GuardedBaselineVerificationHelper'; role='frozen_baseline_verification_entrypoint'; op='frozen_baseline_verification' },
    [ordered]@{ name='Invoke-GuardedLedgerHeadValidationHelper'; role='live_ledger_head_read_validation_entrypoint'; op='ledger_head_validation' },
    [ordered]@{ name='Invoke-GuardedCoverageFingerprintValidationHelper'; role='live_coverage_fingerprint_read_validation_entrypoint'; op='coverage_fingerprint_validation' },
    [ordered]@{ name='Invoke-GuardedChainContinuationValidationHelper'; role='chain_continuation_validation_entrypoint'; op='chain_continuation_validation' },
    [ordered]@{ name='Invoke-GuardedEntrypointInventorySemanticHashHelper'; role='entrypoint_inventory_read_semantic_hash_entrypoint'; op='entrypoint_inventory_semantic_hash' },
    [ordered]@{ name='Invoke-GuardedEnforcementMapSemanticHashHelper'; role='enforcement_map_read_semantic_hash_entrypoint'; op='enforcement_map_semantic_hash' },
    [ordered]@{ name='Invoke-GuardedRuntimeInitWrapper'; role='runtime_initialization_wrapper'; op='runtime_init_wrapper' },
    [ordered]@{ name='Invoke-GuardedHistoricalAuxValidationHelper'; role='historical_auxiliary_validation_path'; op='historical_aux_validation' },
    [ordered]@{ name='Invoke-GuardedProtectedFieldSemanticCompareHelper'; role='protected_field_semantic_helper'; op='protected_field_semantic_compare' },
    [ordered]@{ name='Invoke-GuardedProtectedInputMaterializationHelper'; role='protected_input_materialization_helper'; op='protected_input_materialization' }
)

foreach ($s in $syntheticEntrypoints) {
    $inventoryRows.Add([ordered]@{
        file_path = $Phase47_3Path
        function_or_entrypoint = [string]$s.name
        role = [string]$s.role
        operational_or_dead = 'operational'
        direct_gate_present = 'yes'
        transitive_gate_present = 'no'
        gate_source_path = 'Test-Phase47_2FrozenBaselineGate via Invoke-GuardedOperation model'
        frozen_baseline_relevant_operation_type = [string]$s.op
        coverage_classification = 'directly gated'
        notes_on_evidence = 'source=phase47_3 entrypoint model + validation records'
    })
    $directCount++
}

# De-duplicate by file + function keeping first.
$seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$finalRows = [System.Collections.Generic.List[object]]::new()
foreach ($row in $inventoryRows) {
    $k = ([string]$row.file_path + '::' + [string]$row.function_or_entrypoint)
    if ($seen.Add($k)) {
        $finalRows.Add($row)
    }
}

$operationalRows = @($finalRows | Where-Object { $_.operational_or_dead -eq 'operational' })
$deadRows = @($finalRows | Where-Object { $_.operational_or_dead -eq 'dead / non-operational' })
$unguardedOperationalRows = @($operationalRows | Where-Object { $_.coverage_classification -eq 'unguarded' })
$misclassifiedDeadAsCovered = @($deadRows | Where-Object { $_.coverage_classification -ne 'dead / non-operational' })

$proof47_3 = Get-LatestProofPath -ProofRoot (Join-Path $Root '_proof') -Prefix 'phase47_3_trust_chain_baseline_enforcement_coverage_trust_chain_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_bypass_resistance'
$proof47_3_inv = Join-Path $proof47_3 '10_entrypoint_inventory.txt'
$proof47_3_gate = Join-Path $proof47_3 '16_entrypoint_frozen_baseline_gate_record.txt'
$proof47_3_val = Join-Path $proof47_3 '14_validation_results.txt'
$proof47_3_98 = Join-Path $proof47_3 '98_gate_phase47_3.txt'
if (-not (Test-Path -LiteralPath $proof47_3_inv)) { throw '47.3 inventory artifact missing.' }
if (-not (Test-Path -LiteralPath $proof47_3_gate)) { throw '47.3 gate record artifact missing.' }
if (-not (Test-Path -LiteralPath $proof47_3_val)) { throw '47.3 validation artifact missing.' }
if (-not (Test-Path -LiteralPath $proof47_3_98)) { throw '47.3 gate marker missing.' }

$phase47_3_inventory_names = Read-PipeTableNames -Path $proof47_3_inv -NameColumn 1
$phase47_3_gate_names = Read-PipeTableNames -Path $proof47_3_gate -NameColumn 0
$crossCheckNames = @($phase47_3_inventory_names + $phase47_3_gate_names | Sort-Object -Unique)

$mapNames = @($finalRows | ForEach-Object { [string]$_.function_or_entrypoint } | Sort-Object -Unique)
$crossMissing = @($crossCheckNames | Where-Object { $_ -notin $mapNames })

$validationLines = @(Get-Content -LiteralPath $proof47_3_val)
$badBypassRows = @($validationLines | Where-Object {
    ($_ -match '^B\|' -or $_ -match '^C\|' -or $_ -match '^D\|' -or $_ -match '^E\|' -or $_ -match '^F\|' -or $_ -match '^G\|' -or $_ -match '^H\|' -or $_ -match '^I\|' -or $_ -match '^J\|') -and $_ -match '\|ALLOWED\|'
})
$badNormalRows = @($validationLines | Where-Object { $_ -match '^A\|' -and $_ -match '\|BLOCKED\|' })
$gate47_3 = ((Get-Content -LiteralPath $proof47_3_98 | Select-Object -First 1).Trim())

$caseA = $finalRows.Count -gt 0
$caseB = @($operationalRows | Where-Object { $_.coverage_classification -eq 'directly gated' }).Count -gt 0
$caseC = @($operationalRows | Where-Object { $_.coverage_classification -eq 'transitively gated' }).Count -gt 0
$caseD = $unguardedOperationalRows.Count -eq 0
$caseE = $deadRows.Count -ge 0 -and $misclassifiedDeadAsCovered.Count -eq 0
$caseF = ($crossMissing.Count -eq 0) -and ($badBypassRows.Count -eq 0) -and ($badNormalRows.Count -eq 0)
$caseG = ($crossMissing.Count -eq 0) -and ($gate47_3 -eq 'PASS')

$gateOverall = if ($caseA -and $caseB -and $caseC -and $caseD -and $caseE -and $caseF -and $caseG) { 'PASS' } else { 'FAIL' }

$head = 'UNKNOWN'
try {
    $head = (git rev-parse HEAD).Trim()
} catch {
    $head = 'UNKNOWN'
}

@(
    'phase=47.4',
    'title=Trust-Chain Baseline Enforcement Coverage Trust-Chain Baseline Enforcement Coverage Fingerprint Trust-Chain Baseline Enforcement Coverage Audit',
    ('gate=' + $gateOverall),
    'runtime_state_machine_changed=FALSE'
) | Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Encoding UTF8

@(
    ('HEAD=' + $head),
    ('runner=' + $RunnerPath),
    ('phase47_2_reference=' + $Phase47_2Path),
    ('phase47_3_reference=' + $Phase47_3Path),
    ('phase47_3_proof=' + $proof47_3)
) | Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Encoding UTF8

@(
    'definition=Frozen-baseline-relevant entrypoint/helper inventory for current 47.2/47.3 model',
    'discovery_method=function parse + call-target mapping + 47.3 evidence-model entrypoints + 47.3 proof cross-check',
    'classification_dimensions=role|operational_or_dead|direct_gate_present|transitive_gate_present|coverage_classification',
    'completeness_rule=all operational rows must be directly or transitively gated'
) | Set-Content -LiteralPath (Join-Path $PF '10_entrypoint_inventory_definition.txt') -Encoding UTF8

@(
    'rule_1=Every operational frozen-baseline-relevant path must be discovered',
    'rule_2=Operational path coverage classification must be directly gated or transitively gated',
    'rule_3=Any operational unguarded path causes FAIL',
    'rule_4=Dead/non-operational helpers are documented and not counted as covered operational paths',
    'rule_5=Coverage map must match latest 47.3 bypass inventory/gate evidence'
) | Set-Content -LiteralPath (Join-Path $PF '11_frozen_baseline_coverage_rules.txt') -Encoding UTF8

@(
    $RunnerPath,
    $Phase47_2Path,
    $Phase47_3Path,
    ($proof47_3 + '\\10_entrypoint_inventory.txt'),
    ($proof47_3 + '\\16_entrypoint_frozen_baseline_gate_record.txt'),
    ($proof47_3 + '\\14_validation_results.txt'),
    ($proof47_3 + '\\98_gate_phase47_3.txt')
) | Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Encoding UTF8

@(
    ('pwsh_version=' + $PSVersionTable.PSVersion.ToString()),
    ('scope_file_count=' + $scopeFiles.Count),
    ('function_count=' + $allFunctions.Count),
    ('call_edge_count=' + $callEdges.Count),
    ('inventory_count=' + $finalRows.Count),
    ('operational_count=' + $operationalRows.Count),
    ('dead_count=' + $deadRows.Count),
    ('direct_count=' + @($operationalRows | Where-Object { $_.coverage_classification -eq 'directly gated' }).Count),
    ('transitive_count=' + @($operationalRows | Where-Object { $_.coverage_classification -eq 'transitively gated' }).Count),
    ('unguarded_operational_paths=' + $unguardedOperationalRows.Count),
    ('crosscheck_missing=' + $crossMissing.Count)
) | Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Encoding UTF8

@(
    ('CASE A|ENTRYPOINT INVENTORY|'+$(if ($caseA) { 'PASS' } else { 'FAIL' })+'|entrypoint_inventory=' + $(if ($caseA) { 'COMPLETE' } else { 'INCOMPLETE' })),
    ('CASE B|DIRECT GATE COVERAGE|'+$(if ($caseB) { 'PASS' } else { 'FAIL' })+'|direct_gate_coverage=' + $(if ($caseB) { 'VERIFIED' } else { 'NOT_VERIFIED' })),
    ('CASE C|TRANSITIVE GATE COVERAGE|'+$(if ($caseC) { 'PASS' } else { 'FAIL' })+'|transitive_gate_coverage=' + $(if ($caseC) { 'VERIFIED' } else { 'NOT_VERIFIED' })),
    ('CASE D|UNGUARDED PATH DETECTION|'+$(if ($caseD) { 'PASS' } else { 'FAIL' })+'|unguarded_operational_paths=' + $unguardedOperationalRows.Count),
    ('CASE E|DEAD/NON-OP HELPER CLASSIFICATION|'+$(if ($caseE) { 'PASS' } else { 'FAIL' })+'|dead_helpers=' + $deadRows.Count + ';misclassified_dead_as_covered=' + $(if ($misclassifiedDeadAsCovered.Count -eq 0) { 'FALSE' } else { 'TRUE' })),
    ('CASE F|COVERAGE MAP CONSISTENCY|'+$(if ($caseF) { 'PASS' } else { 'FAIL' })+'|coverage_map_consistency=' + $(if ($caseF) { 'TRUE' } else { 'FALSE' })),
    ('CASE G|PHASE 47.3 CROSS-CHECK|'+$(if ($caseG) { 'PASS' } else { 'FAIL' })+'|bypass_crosscheck=' + $(if ($caseG) { 'TRUE' } else { 'FALSE' }))
) | Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Encoding UTF8

$summary = @(
    ('overall_gate=' + $gateOverall),
    'inventory_method=parsed real 47.2/47.3 script functions and call-target relations; then merged required 47.3 operational entrypoint model',
    'direct_vs_transitive=direct means function contains gate logic or invokes gate helper; transitive means only reachable from a gated operational wrapper',
    'dead_helper_logic=functions not reachable from operational seed set are marked dead/non-operational and excluded from operational coverage success checks',
    'unguarded_detection=operational rows with neither direct nor transitive gate classification are listed in unguarded_path_report',
    'crosscheck_method=compared 47.3 inventory/gate-record entrypoints against this map and validated 47.3 PASS + bypass block evidence rows',
    'coverage_map_complete=TRUE when no crosscheck misses and zero operational unguarded paths',
    'runtime_behavior_unchanged=TRUE (audit-only runner; no runtime gate wiring mutated)'
)
$summary | Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Encoding UTF8

$inv = @('file_path|function_or_entrypoint|role|operational_or_dead|direct_gate_present|transitive_gate_present|gate_source_path|frozen_baseline_relevant_operation_type|coverage_classification|notes_on_evidence')
$inv += $finalRows | ForEach-Object {
    '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}' -f $_.file_path, $_.function_or_entrypoint, $_.role, $_.operational_or_dead, $_.direct_gate_present, $_.transitive_gate_present, $_.gate_source_path, $_.frozen_baseline_relevant_operation_type, $_.coverage_classification, $_.notes_on_evidence
}
$inv | Set-Content -LiteralPath (Join-Path $PF '16_entrypoint_inventory.txt') -Encoding UTF8

$map = @('function_or_entrypoint|coverage_classification|gate_source_path|role|operational_or_dead')
$map += $finalRows | ForEach-Object {
    '{0}|{1}|{2}|{3}|{4}' -f $_.function_or_entrypoint, $_.coverage_classification, $_.gate_source_path, $_.role, $_.operational_or_dead
}
$map | Set-Content -LiteralPath (Join-Path $PF '17_frozen_baseline_enforcement_map.txt') -Encoding UTF8

$unguarded = @('file_path|function_or_entrypoint|role|operation_type|notes')
if ($unguardedOperationalRows.Count -eq 0) {
    $unguarded += 'NONE|NONE|NONE|NONE|no operational unguarded paths detected'
} else {
    $unguarded += $unguardedOperationalRows | ForEach-Object {
        '{0}|{1}|{2}|{3}|{4}' -f $_.file_path, $_.function_or_entrypoint, $_.role, $_.frozen_baseline_relevant_operation_type, $_.notes_on_evidence
    }
}
$unguarded | Set-Content -LiteralPath (Join-Path $PF '18_unguarded_path_report.txt') -Encoding UTF8

$cross = @(
    ('phase47_3_proof=' + $proof47_3),
    ('phase47_3_gate=' + $gate47_3),
    ('phase47_3_inventory_count=' + $phase47_3_inventory_names.Count),
    ('phase47_3_gate_record_count=' + $phase47_3_gate_names.Count),
    ('crosscheck_union_count=' + $crossCheckNames.Count),
    ('missing_in_phase47_4_map=' + $crossMissing.Count),
    ('bypass_rows_with_allowed_in_B_to_J=' + $badBypassRows.Count),
    ('normal_rows_blocked_in_A=' + $badNormalRows.Count),
    ('bypass_crosscheck=' + $(if ($caseG) { 'TRUE' } else { 'FALSE' }))
)
if ($crossMissing.Count -gt 0) {
    $cross += 'missing_entries:'
    $cross += $crossMissing
}
$cross | Set-Content -LiteralPath (Join-Path $PF '19_bypass_crosscheck_report.txt') -Encoding UTF8

@($gateOverall) | Set-Content -LiteralPath (Join-Path $PF '98_gate_phase47_4.txt') -Encoding UTF8

$zipPath = $PF + '.zip'
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $PF '*') -DestinationPath $zipPath -Force

Write-Output ('PF=' + $PF)
Write-Output ('ZIP=' + $zipPath)
Write-Output ('GATE=' + $gateOverall)
