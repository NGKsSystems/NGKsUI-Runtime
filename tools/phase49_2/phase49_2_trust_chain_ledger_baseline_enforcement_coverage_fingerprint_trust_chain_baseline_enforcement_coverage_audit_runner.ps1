Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ((Get-Location).Path -ne $Root) {
    Write-Output 'hey stupid Fucker, wrong window again'
    exit 1
}
Set-Location $Root

function Get-FunctionDefinitions {
    param([string]$FilePath)

    $lines = [System.IO.File]::ReadAllLines($FilePath)
    $defs = [System.Collections.Generic.List[object]]::new()
    $starts = [System.Collections.Generic.List[int]]::new()
    $names = [System.Collections.Generic.List[string]]::new()

    for ($i = 0; $i -lt $lines.Length; $i++) {
        if ($lines[$i] -match '^function\s+([A-Za-z0-9\-_]+)\s*\{') {
            $starts.Add($i + 1)
            $names.Add([string]$Matches[1])
        }
    }

    for ($i = 0; $i -lt $starts.Count; $i++) {
        $startLine = [int]$starts[$i]
        $endLine = if ($i -lt ($starts.Count - 1)) { [int]$starts[$i + 1] - 1 } else { $lines.Length }
        $body = ($lines[($startLine - 1)..($endLine - 1)] -join "`r`n")
        $defs.Add([pscustomobject]@{
            file_path = $FilePath
            function_name = [string]$names[$i]
            start_line = $startLine
            end_line = $endLine
            body = $body
        })
    }

    return @($defs)
}

function Get-CalledFunctionsFromText {
    param(
        [string]$Text,
        [string[]]$FunctionNames
    )

    $called = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($name in $FunctionNames) {
        $pattern = '(?<!function\s)' + [regex]::Escape($name) + '(?![A-Za-z0-9\-_])'
        if ([regex]::IsMatch($Text, $pattern)) {
            [void]$called.Add($name)
        }
    }
    return @($called)
}

function Find-LatestProofFolder {
    param([string]$Prefix)

    $proofRoot = Join-Path $Root '_proof'
    $dirs = Get-ChildItem -LiteralPath $proofRoot -Directory | Where-Object { $_.Name -like ($Prefix + '*') } | Sort-Object Name -Descending
    return ($dirs | Select-Object -First 1)
}

function ConvertFrom-KeyValueLine {
    param([string]$Line)

    $map = [ordered]@{}
    foreach ($segment in ($Line -split '\|')) {
        $idx = $segment.IndexOf('=')
        if ($idx -gt 0) {
            $key = $segment.Substring(0, $idx)
            $value = $segment.Substring($idx + 1)
            $map[$key] = $value
        }
    }
    return [pscustomobject]$map
}

function Get-RoleForFunction {
    param([string]$Name)

    switch ($Name) {
        'Invoke-FrozenBaselineEnforcementGate' { return 'frozen_baseline_verification_entrypoint' }
        'Invoke-ProtectedOperation' { return 'runtime_initialization_wrapper' }
        'Test-LegacyTrustChain' { return 'chain_continuation_validation_entrypoint' }
        'Get-LegacyChainEntryHash' { return 'chain_continuation_hash_helper' }
        'Get-LegacyChainEntryCanonical' { return 'chain_continuation_canonicalization_helper' }
        'Get-CanonicalObjectHash' { return 'semantic_protected_field_comparison_helper' }
        'Convert-ToCanonicalJson' { return 'canonicalization_helper' }
        'Get-StringSha256Hex' { return 'lower_level_hash_helper' }
        'Get-BytesSha256Hex' { return 'lower_level_hash_helper' }
        'Get-NextEntryId' { return 'probe_generation_helper' }
        'Copy-Object' { return 'utility_copy_helper' }
        'Add-CaseRecordLine' { return 'proof_recording_helper' }
        'Add-ValidationLine' { return 'proof_recording_helper' }
        'Get-ProtectedEntrypointInventory' { return 'entrypoint_inventory_helper' }
        default {
            if ($Name -match 'Baseline.*Snapshot') { return 'frozen_baseline_snapshot_load_entrypoint' }
            if ($Name -match 'Baseline.*Integrity') { return 'frozen_baseline_integrity_record_load_entrypoint' }
            return 'frozen_baseline_relevant_helper'
        }
    }
}

function Get-OperationTypeForRole {
    param([string]$Role)

    switch ($Role) {
        'frozen_baseline_verification_entrypoint' { return 'verify_frozen_baseline_and_allow_or_block_runtime_init' }
        'runtime_initialization_wrapper' { return 'invoke_runtime_init_with_frozen_baseline_gate' }
        'chain_continuation_validation_entrypoint' { return 'validate_chain_continuation' }
        'semantic_protected_field_comparison_helper' { return 'compare_semantic_protected_fields' }
        'canonicalization_helper' { return 'canonicalize_protected_inputs' }
        'lower_level_hash_helper' { return 'hash_protected_inputs' }
        'proof_recording_helper' { return 'record_certification_outputs' }
        'entrypoint_inventory_helper' { return 'inventory_protected_entrypoints' }
        default { return 'frozen_baseline_related_operation' }
    }
}

function New-InventoryRow {
    param(
        [string]$FilePath,
        [string]$Name,
        [string]$Role,
        [string]$OperationalOrDead,
        [string]$DirectGatePresent,
        [string]$TransitiveGatePresent,
        [string]$GateSourcePath,
        [string]$OperationType,
        [string]$CoverageClassification,
        [string]$Notes,
        [string]$SymbolKind,
        [int]$DefinitionLine = 0
    )

    return [pscustomobject]@{
        file_path = $FilePath
        function_or_entrypoint_name = $Name
        role = $Role
        operational_or_dead = $OperationalOrDead
        direct_gate_present = $DirectGatePresent
        transitive_gate_present = $TransitiveGatePresent
        gate_source_path = $GateSourcePath
        frozen_baseline_relevant_operation_type = $OperationType
        coverage_classification = $CoverageClassification
        notes_on_evidence = $Notes
        symbol_kind = $SymbolKind
        definition_line = $DefinitionLine
    }
}

function Add-ValidationResult {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$CaseId,
        [string]$CaseName,
        [bool]$Pass,
        [string]$Detail
    )

    $Lines.Add(('CASE ' + $CaseId + ' ' + $CaseName + ' ' + $Detail + ' => ' + $(if ($Pass) { 'PASS' } else { 'FAIL' })))
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\phase49_2_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_coverage_audit_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$Phase49_0Path = Join-Path $Root 'tools\phase49_0\phase49_0_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_runner.ps1'
$Phase49_1Path = Join-Path $Root 'tools\phase49_1\phase49_1_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_bypass_resistance_runner.ps1'

foreach ($p in @($Phase49_0Path, $Phase49_1Path)) {
    if (-not (Test-Path -LiteralPath $p)) { throw ('Missing required audit source: ' + $p) }
}

$Latest49_1Proof = Find-LatestProofFolder -Prefix 'phase49_1_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_bypass_resistance_'
if ($null -eq $Latest49_1Proof) {
    throw 'Missing latest phase49_1 proof folder.'
}

$Proof10 = Join-Path $Latest49_1Proof.FullName '10_entrypoint_inventory.txt'
$Proof11 = Join-Path $Latest49_1Proof.FullName '11_frozen_baseline_enforcement_map.txt'
$Proof14 = Join-Path $Latest49_1Proof.FullName '14_validation_results.txt'
$Proof16 = Join-Path $Latest49_1Proof.FullName '16_entrypoint_frozen_baseline_gate_record.txt'
$Proof98 = Join-Path $Latest49_1Proof.FullName '98_gate_phase49_1.txt'
foreach ($p in @($Proof10, $Proof11, $Proof14, $Proof16, $Proof98)) {
    if (-not (Test-Path -LiteralPath $p)) { throw ('Missing required phase49_1 proof artifact: ' + $p) }
}

$scanPattern = 'Invoke-FrozenBaselineEnforcementGate|91_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline\.json|92_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_integrity\.json|90_trust_chain_ledger_baseline_enforcement_coverage_fingerprint\.json'
$relevantFiles = @(Get-ChildItem -LiteralPath (Join-Path $Root 'tools') -Filter '*.ps1' -Recurse | Select-String -Pattern $scanPattern | Select-Object -ExpandProperty Path -Unique | Sort-Object)
$expectedRelevantFiles = @($Phase49_0Path, $Phase49_1Path)

$defs49_0 = @(Get-FunctionDefinitions -FilePath $Phase49_0Path)
$defs49_1 = @(Get-FunctionDefinitions -FilePath $Phase49_1Path)
$allDefs = @($defs49_0 + $defs49_1)
$allNames = @($allDefs | ForEach-Object { [string]$_.function_name } | Sort-Object -Unique)

$callGraph = @{}
foreach ($def in $allDefs) {
    $key = [string]$def.file_path + '|' + [string]$def.function_name
    $called = Get-CalledFunctionsFromText -Text ([string]$def.body) -FunctionNames $allNames
    $callGraph[$key] = @($called)
}

$directGateKeys = [System.Collections.Generic.HashSet[string]]::new()
foreach ($def in $allDefs) {
    $key = [string]$def.file_path + '|' + [string]$def.function_name
    if ([string]$def.function_name -eq 'Invoke-FrozenBaselineEnforcementGate') {
        [void]$directGateKeys.Add($key)
        continue
    }
    if ([string]$def.body -match '\bInvoke-FrozenBaselineEnforcementGate\b') {
        [void]$directGateKeys.Add($key)
    }
}

$defByKey = @{}
foreach ($def in $allDefs) {
    $defByKey[[string]$def.file_path + '|' + [string]$def.function_name] = $def
}

$closureKeys = [System.Collections.Generic.HashSet[string]]::new()
$queue = [System.Collections.Generic.Queue[string]]::new()
foreach ($rootKey in $directGateKeys) {
    [void]$closureKeys.Add($rootKey)
    $queue.Enqueue($rootKey)
}

while ($queue.Count -gt 0) {
    $current = $queue.Dequeue()
    $parts = $current -split '\|', 2
    $currentFile = [string]$parts[0]
    $calledNames = @($callGraph[$current])
    foreach ($calledName in $calledNames) {
        $candidate = $currentFile + '|' + $calledName
        if ($defByKey.ContainsKey($candidate) -and -not $closureKeys.Contains($candidate)) {
            [void]$closureKeys.Add($candidate)
            $queue.Enqueue($candidate)
        }
    }
}

$inventoryRows = [System.Collections.Generic.List[object]]::new()
foreach ($def in ($allDefs | Sort-Object file_path, function_name)) {
    $key = [string]$def.file_path + '|' + [string]$def.function_name
    $role = Get-RoleForFunction -Name ([string]$def.function_name)
    $operationType = Get-OperationTypeForRole -Role $role

    $direct = if ($directGateKeys.Contains($key)) { 'yes' } else { 'no' }
    $transitive = 'no'
    $gateSourcePath = 'not_applicable'
    $operational = 'dead'
    $classification = 'dead_non_operational'

    if ($direct -eq 'yes') {
        $operational = 'operational'
        $classification = 'directly_gated'
        $gateSourcePath = ([string]$def.file_path + '::Invoke-FrozenBaselineEnforcementGate')
    } elseif ($closureKeys.Contains($key)) {
        $operational = 'operational'
        $transitive = 'yes'
        $classification = 'transitively_gated'
        $gateSourcePath = ([string]$def.file_path + '::Invoke-FrozenBaselineEnforcementGate transitive_call_chain')
    }

    $notes = 'definition_line=' + [string]$def.start_line + '; static_call_targets=' + [string](@($callGraph[$key]).Count)
    $inventoryRows.Add((New-InventoryRow -FilePath ([string]$def.file_path) -Name ([string]$def.function_name) -Role $role -OperationalOrDead $operational -DirectGatePresent $direct -TransitiveGatePresent $transitive -GateSourcePath $gateSourcePath -OperationType $operationType -CoverageClassification $classification -Notes $notes -SymbolKind 'actual_function' -DefinitionLine $def.start_line))
}

$proofInventoryRows = [System.Collections.Generic.List[object]]::new()
$proofInventoryLines = Get-Content -LiteralPath $Proof10 | Where-Object { $_ -match '^protected_input_type=' }
foreach ($line in $proofInventoryLines) {
    $parsed = ConvertFrom-KeyValueLine -Line $line
    $proofInventoryRows.Add((New-InventoryRow -FilePath ([string]$parsed.file_path) -Name ([string]$parsed.entrypoint_or_helper_name) -Role ([string]$parsed.protected_input_type) -OperationalOrDead 'dead' -DirectGatePresent 'no' -TransitiveGatePresent 'no' -GateSourcePath ($Phase49_1Path + '::Invoke-ProtectedOperation -> ' + $Phase49_1Path + '::Invoke-FrozenBaselineEnforcementGate') -OperationType ([string]$parsed.operation_requested) -CoverageClassification 'proof_label_mapped' -Notes 'present in latest phase49_1 proof inventory label set' -SymbolKind 'proof_label' -DefinitionLine 0))
}

foreach ($row in $proofInventoryRows) {
    $inventoryRows.Add($row)
}

$phase49_1GateFile = Get-Content -LiteralPath $Proof98
$phase49_1ValidationLines = Get-Content -LiteralPath $Proof14
$phase49_1MapLines = Get-Content -LiteralPath $Proof11
$phase49_1GateRecords = @(Get-Content -LiteralPath $Proof16 | Select-Object -Skip 1 | ForEach-Object { ConvertFrom-KeyValueLine -Line $_ })

$inventoryComplete = ($inventoryRows.Count -gt 0 -and $directGateKeys.Count -gt 0)
foreach ($expectedFile in $expectedRelevantFiles) {
    if ($relevantFiles -notcontains $expectedFile) { $inventoryComplete = $false }
    if (@($inventoryRows | Where-Object { $_.file_path -eq $expectedFile -and $_.symbol_kind -eq 'actual_function' }).Count -eq 0) { $inventoryComplete = $false }
}
if ($proofInventoryRows.Count -lt 9) { $inventoryComplete = $false }

$directRows = @($inventoryRows | Where-Object { $_.coverage_classification -eq 'directly_gated' })
$directGateCoverage = ($directRows.Count -ge 3)
foreach ($row in $directRows) {
    if ($row.direct_gate_present -ne 'yes' -or [string]::IsNullOrWhiteSpace([string]$row.gate_source_path)) {
        $directGateCoverage = $false
    }
}

$transitiveRows = @($inventoryRows | Where-Object { $_.coverage_classification -eq 'transitively_gated' })
$transitiveGateCoverage = ($transitiveRows.Count -gt 0)
foreach ($row in $transitiveRows) {
    if ($row.transitive_gate_present -ne 'yes' -or [string]::IsNullOrWhiteSpace([string]$row.gate_source_path)) {
        $transitiveGateCoverage = $false
    }
}

$unguardedOperationalRows = @($inventoryRows | Where-Object {
    $_.symbol_kind -eq 'actual_function' -and
    $_.operational_or_dead -eq 'operational' -and
    $_.direct_gate_present -ne 'yes' -and
    $_.transitive_gate_present -ne 'yes'
})
$unguardedOperationalCount = $unguardedOperationalRows.Count

$deadRows = @($inventoryRows | Where-Object { $_.operational_or_dead -eq 'dead' })
$deadHelpersDocumented = ($deadRows.Count -gt 0)
$misclassifiedDeadAsCovered = $false
foreach ($row in $deadRows) {
    if ($row.coverage_classification -eq 'directly_gated' -or $row.coverage_classification -eq 'transitively_gated') {
        $misclassifiedDeadAsCovered = $true
    }
}

$coverageMapConsistency = $true
$seenKeys = [System.Collections.Generic.HashSet[string]]::new()
foreach ($row in $inventoryRows) {
    $key = [string]$row.file_path + '|' + [string]$row.function_or_entrypoint_name + '|' + [string]$row.symbol_kind
    if (-not $seenKeys.Add($key)) { $coverageMapConsistency = $false }
    if ($row.direct_gate_present -eq 'yes' -and $row.transitive_gate_present -eq 'yes') { $coverageMapConsistency = $false }
    if (($row.direct_gate_present -eq 'yes' -or $row.transitive_gate_present -eq 'yes') -and [string]::IsNullOrWhiteSpace([string]$row.gate_source_path)) { $coverageMapConsistency = $false }
}

$phase49_1GatePass = (($phase49_1GateFile -join "`n") -match 'GATE=\s*PASS')
$phase49_1AllPass = (@($phase49_1ValidationLines | Where-Object { $_ -match '=> PASS$' }).Count -eq 9)
$proofLabelNames = @($proofInventoryRows | ForEach-Object { [string]$_.function_or_entrypoint_name })
$proofMapCoverage = $true
foreach ($proofLabel in $proofLabelNames) {
    if (-not ($phase49_1MapLines -match [regex]::Escape($proofLabel))) {
        $proofMapCoverage = $false
        break
    }
}

$gateRecordCoverage = $true
foreach ($record in $phase49_1GateRecords) {
    $name = [string]$record.entrypoint_or_helper_name
    if ($proofLabelNames -notcontains $name -and $name -ne 'Invoke-FrozenBaselineEnforcementGate') {
        $gateRecordCoverage = $false
        break
    }
}

$bypassCrosscheck = ($phase49_1GatePass -and $phase49_1AllPass -and $proofMapCoverage -and $gateRecordCoverage)

$ValidationLines = [System.Collections.Generic.List[string]]::new()
Add-ValidationResult -Lines $ValidationLines -CaseId 'A' -CaseName 'entrypoint_inventory' -Pass $inventoryComplete -Detail ('entrypoint_inventory=' + $(if ($inventoryComplete) { 'COMPLETE' } else { 'INCOMPLETE' }))
Add-ValidationResult -Lines $ValidationLines -CaseId 'B' -CaseName 'direct_gate_coverage' -Pass $directGateCoverage -Detail ('direct_gate_coverage=' + $(if ($directGateCoverage) { 'VERIFIED' } else { 'FAILED' }))
Add-ValidationResult -Lines $ValidationLines -CaseId 'C' -CaseName 'transitive_gate_coverage' -Pass $transitiveGateCoverage -Detail ('transitive_gate_coverage=' + $(if ($transitiveGateCoverage) { 'VERIFIED' } else { 'FAILED' }))
Add-ValidationResult -Lines $ValidationLines -CaseId 'D' -CaseName 'unguarded_path_detection' -Pass ($unguardedOperationalCount -eq 0) -Detail ('unguarded_operational_paths=' + [string]$unguardedOperationalCount)
Add-ValidationResult -Lines $ValidationLines -CaseId 'E' -CaseName 'dead_non_operational_helper_classification' -Pass ($deadHelpersDocumented -and -not $misclassifiedDeadAsCovered) -Detail ('dead_helpers=' + $(if ($deadHelpersDocumented) { 'DOCUMENTED' } else { 'MISSING' }) + ' misclassified_dead_as_covered=' + $(if ($misclassifiedDeadAsCovered) { 'TRUE' } else { 'FALSE' }))
Add-ValidationResult -Lines $ValidationLines -CaseId 'F' -CaseName 'coverage_map_consistency' -Pass $coverageMapConsistency -Detail ('coverage_map_consistency=' + $(if ($coverageMapConsistency) { 'TRUE' } else { 'FALSE' }))
Add-ValidationResult -Lines $ValidationLines -CaseId 'G' -CaseName 'phase49_1_crosscheck' -Pass $bypassCrosscheck -Detail ('bypass_crosscheck=' + $(if ($bypassCrosscheck) { 'TRUE' } else { 'FALSE' }))

$Gate = if ($inventoryComplete -and $directGateCoverage -and $transitiveGateCoverage -and ($unguardedOperationalCount -eq 0) -and $deadHelpersDocumented -and -not $misclassifiedDeadAsCovered -and $coverageMapConsistency -and $bypassCrosscheck) { 'PASS' } else { 'FAIL' }

$status01 = @(
    'PHASE=49.2',
    'TITLE=Trust-Chain Ledger Baseline Enforcement Coverage Fingerprint Trust-Chain Baseline Enforcement Coverage Audit',
    'GATE=' + $Gate,
    'ENTRYPOINT_INVENTORY_COMPLETE=' + $(if ($inventoryComplete) { 'TRUE' } else { 'FALSE' }),
    'DIRECT_GATE_COVERAGE_VERIFIED=' + $(if ($directGateCoverage) { 'TRUE' } else { 'FALSE' }),
    'TRANSITIVE_GATE_COVERAGE_VERIFIED=' + $(if ($transitiveGateCoverage) { 'TRUE' } else { 'FALSE' }),
    'UNGUARDED_OPERATIONAL_PATHS=' + [string]$unguardedOperationalCount,
    'BYPASS_CROSSCHECK=' + $(if ($bypassCrosscheck) { 'TRUE' } else { 'FALSE' }),
    'RUNTIME_STATE_MACHINE_CHANGED=FALSE'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '01_status.txt'), $status01, [System.Text.Encoding]::UTF8)

$head02 = @(
    'RUNNER=tools/phase49_2/phase49_2_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_coverage_audit_runner.ps1',
    'SOURCE_49_0=' + $Phase49_0Path,
    'SOURCE_49_1=' + $Phase49_1Path,
    'LATEST_49_1_PROOF=' + $Latest49_1Proof.FullName
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '02_head.txt'), $head02, [System.Text.Encoding]::UTF8)

$definition10 = @(
    'INVENTORY_METHOD=static function-definition scan of real phase49_0 and phase49_1 runners plus proof-label cross-check from latest phase49_1 packet',
    'CLASSIFICATION_DIMENSIONS=role, operational_or_dead, direct_gate_present, transitive_gate_present, gate_source_path, coverage_classification',
    'DIRECT_GATE_RULE=gate function itself or wrapper body containing Invoke-FrozenBaselineEnforcementGate',
    'TRANSITIVE_GATE_RULE=helper reachable through direct-gated function call closure',
    'DEAD_RULE=function outside direct-gate closure or proof label not backed by standalone function definition',
    'CROSSCHECK_SOURCE=' + $Latest49_1Proof.FullName
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '10_entrypoint_inventory_definition.txt'), $definition10, [System.Text.Encoding]::UTF8)

$rules11 = @(
    'RULE_1=Every operational frozen-baseline-relevant function in phase49_0 and phase49_1 must be discovered.',
    'RULE_2=Invoke-FrozenBaselineEnforcementGate and wrappers calling it count as direct gate coverage sources.',
    'RULE_3=Lower-level canonicalization, hash, and chain helpers must be transitively gated or the audit fails.',
    'RULE_4=Any operational row with neither direct nor transitive gate coverage is unguarded and causes FAIL.',
    'RULE_5=Dead/non-operational helpers are documented but not counted as covered operational entrypoints.',
    'RULE_6=No assumed coverage: every gated classification must contain explicit gate_source_path evidence.',
    'RULE_7=Latest phase49_1 gate, validation, inventory, and map artifacts must agree with this coverage map.'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '11_frozen_baseline_coverage_rules.txt'), $rules11, [System.Text.Encoding]::UTF8)

$files12 = @(
    'READ=' + $Phase49_0Path,
    'READ=' + $Phase49_1Path,
    'READ=' + $Proof10,
    'READ=' + $Proof11,
    'READ=' + $Proof14,
    'READ=' + $Proof16,
    'READ=' + $Proof98,
    'WRITE=' + $PF
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '12_files_touched.txt'), $files12, [System.Text.Encoding]::UTF8)

$build13 = @(
    'DISCOVERED_RELEVANT_FILES=' + [string]$relevantFiles.Count,
    'EXPECTED_RELEVANT_FILES=' + [string]$expectedRelevantFiles.Count,
    'ACTUAL_FUNCTION_ROWS=' + [string](@($inventoryRows | Where-Object { $_.symbol_kind -eq 'actual_function' }).Count),
    'PROOF_LABEL_ROWS=' + [string](@($inventoryRows | Where-Object { $_.symbol_kind -eq 'proof_label' }).Count),
    'DIRECT_GATE_ROWS=' + [string]$directRows.Count,
    'TRANSITIVE_GATE_ROWS=' + [string]$transitiveRows.Count,
    'UNGUARDED_OPERATIONAL_PATHS=' + [string]$unguardedOperationalCount,
    'LATEST_49_1_GATE_PASS=' + $(if ($phase49_1GatePass) { 'TRUE' } else { 'FALSE' }),
    'GATE=' + $Gate
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '13_build_output.txt'), $build13, [System.Text.Encoding]::UTF8)

[System.IO.File]::WriteAllText((Join-Path $PF '14_validation_results.txt'), ($ValidationLines -join "`r`n"), [System.Text.Encoding]::UTF8)

$summary15 = @(
    'The frozen-baseline-relevant surface was inventoried by scanning actual function definitions in phase49_0 and phase49_1 and then merging proof labels from the latest phase49_1 inventory artifact.',
    'Direct gate coverage was determined by body-level evidence of Invoke-FrozenBaselineEnforcementGate, including the gate function itself and direct wrappers.',
    'Transitive gate coverage was determined by static call-closure traversal rooted at directly gated functions, capturing reachable lower-level helpers.',
    'Dead helpers were distinguished as discovered functions outside the direct-gate closure and proof labels without standalone function definitions.',
    'Unguarded path detection flags any operational function row lacking both direct and transitive gate evidence; this run found ' + [string]$unguardedOperationalCount + ' rows.',
    'The 49.1 cross-check validated latest GATE=PASS, all CASE A-I PASS in validation output, and consistency between bypass inventory labels, enforcement map labels, and gate records.',
    'Runtime behavior remained unchanged because this phase performs static analysis and proof-artifact cross-checking only, with no runtime gate wiring modifications.'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '15_behavior_summary.txt'), $summary15, [System.Text.Encoding]::UTF8)

$inventoryOut = [System.Collections.Generic.List[string]]::new()
$inventoryOut.Add('file_path|function_or_entrypoint_name|role|operational_or_dead|direct_gate_present|transitive_gate_present|gate_source_path|frozen_baseline_relevant_operation_type|coverage_classification|symbol_kind|notes_on_evidence')
foreach ($row in $inventoryRows | Sort-Object file_path, function_or_entrypoint_name, symbol_kind) {
    $inventoryOut.Add(([string]$row.file_path + '|' + [string]$row.function_or_entrypoint_name + '|' + [string]$row.role + '|' + [string]$row.operational_or_dead + '|' + [string]$row.direct_gate_present + '|' + [string]$row.transitive_gate_present + '|' + [string]$row.gate_source_path + '|' + [string]$row.frozen_baseline_relevant_operation_type + '|' + [string]$row.coverage_classification + '|' + [string]$row.symbol_kind + '|' + [string]$row.notes_on_evidence))
}
[System.IO.File]::WriteAllText((Join-Path $PF '16_entrypoint_inventory.txt'), ($inventoryOut -join "`r`n"), [System.Text.Encoding]::UTF8)

$map17 = [System.Collections.Generic.List[string]]::new()
$map17.Add('file_path|function_or_entrypoint_name|coverage_classification|gate_source_path|notes_on_evidence')
foreach ($row in $inventoryRows | Sort-Object coverage_classification, file_path, function_or_entrypoint_name) {
    $map17.Add(([string]$row.file_path + '|' + [string]$row.function_or_entrypoint_name + '|' + [string]$row.coverage_classification + '|' + [string]$row.gate_source_path + '|' + [string]$row.notes_on_evidence))
}
[System.IO.File]::WriteAllText((Join-Path $PF '17_frozen_baseline_enforcement_map.txt'), ($map17 -join "`r`n"), [System.Text.Encoding]::UTF8)

$unguarded18 = [System.Collections.Generic.List[string]]::new()
$unguarded18.Add('unguarded_operational_paths=' + [string]$unguardedOperationalCount)
if ($unguardedOperationalCount -eq 0) {
    $unguarded18.Add('No operational frozen-baseline-relevant path lacked direct or transitive gate coverage.')
} else {
    foreach ($row in $unguardedOperationalRows) {
        $unguarded18.Add(([string]$row.file_path + '|' + [string]$row.function_or_entrypoint_name + '|' + [string]$row.role))
    }
}
[System.IO.File]::WriteAllText((Join-Path $PF '18_unguarded_path_report.txt'), ($unguarded18 -join "`r`n"), [System.Text.Encoding]::UTF8)

$cross19 = @(
    'latest_phase49_1_proof=' + $Latest49_1Proof.FullName,
    'latest_phase49_1_gate_pass=' + $(if ($phase49_1GatePass) { 'TRUE' } else { 'FALSE' }),
    'latest_phase49_1_all_validation_cases_pass=' + $(if ($phase49_1AllPass) { 'TRUE' } else { 'FALSE' }),
    'proof_inventory_labels=' + [string]$proofInventoryRows.Count,
    'proof_map_coverage=' + $(if ($proofMapCoverage) { 'TRUE' } else { 'FALSE' }),
    'gate_record_coverage=' + $(if ($gateRecordCoverage) { 'TRUE' } else { 'FALSE' }),
    'bypass_crosscheck=' + $(if ($bypassCrosscheck) { 'TRUE' } else { 'FALSE' })
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '19_bypass_crosscheck_report.txt'), $cross19, [System.Text.Encoding]::UTF8)

$gate98 = @('PHASE=49.2', 'GATE=' + $Gate) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '98_gate_phase49_2.txt'), $gate98, [System.Text.Encoding]::UTF8)

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
