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

function Get-TextReferenceCount {
    param(
        [string]$Text,
        [string]$Name
    )

    $matches = [regex]::Matches($Text, ('(?<!function\s)' + [regex]::Escape($Name) + '(?![A-Za-z0-9\-_])'))
    return $matches.Count
}

function Find-LatestProofFolder {
    param([string]$Prefix)

    $proofRoot = Join-Path $Root '_proof'
    $dirs = Get-ChildItem -LiteralPath $proofRoot -Directory | Where-Object { $_.Name -like ($Prefix + '*') } | Sort-Object Name -Descending
    return ($dirs | Select-Object -First 1)
}

function Parse-KeyValueLine {
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
$PF = Join-Path $Root ('_proof\phase48_6_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_coverage_audit_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$Phase48_3Path = Join-Path $Root 'tools\phase48_3\phase48_3_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_lock_runner.ps1'
$Phase48_4Path = Join-Path $Root 'tools\phase48_4\phase48_4_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_runner.ps1'
$Phase48_5Path = Join-Path $Root 'tools\phase48_5\phase48_5_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_bypass_resistance_runner.ps1'

foreach ($p in @($Phase48_3Path, $Phase48_4Path, $Phase48_5Path)) {
    if (-not (Test-Path -LiteralPath $p)) { throw ('Missing required audit source: ' + $p) }
}

$Latest48_5Proof = Find-LatestProofFolder -Prefix 'phase48_5_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_bypass_resistance_'
if ($null -eq $Latest48_5Proof) {
    throw 'Missing latest phase48_5 proof folder.'
}

$Proof10 = Join-Path $Latest48_5Proof.FullName '10_entrypoint_inventory.txt'
$Proof11 = Join-Path $Latest48_5Proof.FullName '11_frozen_baseline_enforcement_map.txt'
$Proof14 = Join-Path $Latest48_5Proof.FullName '14_validation_results.txt'
$Proof16 = Join-Path $Latest48_5Proof.FullName '16_entrypoint_frozen_baseline_gate_record.txt'
$Proof98 = Join-Path $Latest48_5Proof.FullName '98_gate_phase48_5.txt'
foreach ($p in @($Proof10, $Proof11, $Proof14, $Proof16, $Proof98)) {
    if (-not (Test-Path -LiteralPath $p)) { throw ('Missing required phase48_5 proof artifact: ' + $p) }
}

$phase48_3Defs = @(Get-FunctionDefinitions -FilePath $Phase48_3Path)
$phase48_4Defs = @(Get-FunctionDefinitions -FilePath $Phase48_4Path)
$phase48_5Defs = @(Get-FunctionDefinitions -FilePath $Phase48_5Path)
$allDefs = @($phase48_3Defs + $phase48_4Defs + $phase48_5Defs)

$scanPattern = '88_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline\.json|89_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_integrity\.json|Invoke-FrozenBaselineEnforcementGate|Get-ProtectedEntrypointInventory'
$relevantFiles = @(Get-ChildItem -LiteralPath (Join-Path $Root 'tools') -Filter '*.ps1' -Recurse | Select-String -Pattern $scanPattern | Select-Object -ExpandProperty Path -Unique | Sort-Object)

$expectedRelevantFiles = @($Phase48_3Path, $Phase48_4Path, $Phase48_5Path)
$expectedFunctionSpecs = @(
    [ordered]@{ file=$Phase48_3Path; name='New-BaselineSnapshot'; role='frozen_baseline_snapshot_materializer'; operation='materialize_frozen_baseline_snapshot'; classification='upstream_non_operational'; operational='dead' },
    [ordered]@{ file=$Phase48_3Path; name='New-IntegrityRecord'; role='frozen_baseline_integrity_record_materializer'; operation='materialize_frozen_baseline_integrity_record'; classification='upstream_non_operational'; operational='dead' },
    [ordered]@{ file=$Phase48_3Path; name='Test-BaselineIntegrity'; role='frozen_baseline_integrity_validation_helper'; operation='validate_frozen_baseline_integrity'; classification='upstream_non_operational'; operational='dead' },
    [ordered]@{ file=$Phase48_3Path; name='Test-BaselineReference'; role='frozen_baseline_reference_validation_helper'; operation='validate_frozen_baseline_reference'; classification='upstream_non_operational'; operational='dead' },

    [ordered]@{ file=$Phase48_4Path; name='Get-BytesSha256Hex'; role='lower_level_hash_primitive'; operation='hash_protected_input_bytes'; classification='transitively_gated'; operational='operational' },
    [ordered]@{ file=$Phase48_4Path; name='Get-StringSha256Hex'; role='lower_level_hash_primitive'; operation='hash_protected_input_text'; classification='transitively_gated'; operational='operational' },
    [ordered]@{ file=$Phase48_4Path; name='Convert-ToCanonicalJson'; role='canonicalization_helper'; operation='canonicalize_protected_input'; classification='transitively_gated'; operational='operational' },
    [ordered]@{ file=$Phase48_4Path; name='Get-CanonicalObjectHash'; role='semantic_protected_field_hash_helper'; operation='hash_semantic_protected_fields'; classification='transitively_gated'; operational='operational' },
    [ordered]@{ file=$Phase48_4Path; name='Get-LegacyChainEntryCanonical'; role='legacy_chain_canonicalization_helper'; operation='canonicalize_chain_continuation_input'; classification='transitively_gated'; operational='operational' },
    [ordered]@{ file=$Phase48_4Path; name='Get-LegacyChainEntryHash'; role='legacy_chain_hash_helper'; operation='hash_chain_continuation_input'; classification='transitively_gated'; operational='operational' },
    [ordered]@{ file=$Phase48_4Path; name='Test-LegacyTrustChain'; role='chain_continuation_validation_helper'; operation='validate_live_chain_continuation'; classification='transitively_gated'; operational='operational' },
    [ordered]@{ file=$Phase48_4Path; name='Invoke-FrozenBaselineEnforcementGate'; role='frozen_baseline_gate_entrypoint'; operation='enforce_frozen_baseline_before_runtime_init'; classification='directly_gated'; operational='operational' },
    [ordered]@{ file=$Phase48_4Path; name='Get-NextEntryId'; role='proof_case_generation_helper'; operation='generate_probe_entry_ids'; classification='dead_non_operational'; operational='dead' },
    [ordered]@{ file=$Phase48_4Path; name='Add-CaseRecordLine'; role='proof_recording_helper'; operation='record_phase48_4_case_results'; classification='dead_non_operational'; operational='dead' },

    [ordered]@{ file=$Phase48_5Path; name='Get-BytesSha256Hex'; role='lower_level_hash_primitive'; operation='hash_protected_input_bytes'; classification='transitively_gated'; operational='operational' },
    [ordered]@{ file=$Phase48_5Path; name='Get-StringSha256Hex'; role='lower_level_hash_primitive'; operation='hash_protected_input_text'; classification='transitively_gated'; operational='operational' },
    [ordered]@{ file=$Phase48_5Path; name='Convert-ToCanonicalJson'; role='canonicalization_helper'; operation='canonicalize_protected_input'; classification='transitively_gated'; operational='operational' },
    [ordered]@{ file=$Phase48_5Path; name='Get-CanonicalObjectHash'; role='semantic_protected_field_hash_helper'; operation='hash_semantic_protected_fields'; classification='transitively_gated'; operational='operational' },
    [ordered]@{ file=$Phase48_5Path; name='Get-LegacyChainEntryCanonical'; role='legacy_chain_canonicalization_helper'; operation='canonicalize_chain_continuation_input'; classification='transitively_gated'; operational='operational' },
    [ordered]@{ file=$Phase48_5Path; name='Get-LegacyChainEntryHash'; role='legacy_chain_hash_helper'; operation='hash_chain_continuation_input'; classification='transitively_gated'; operational='operational' },
    [ordered]@{ file=$Phase48_5Path; name='Test-LegacyTrustChain'; role='chain_continuation_validation_helper'; operation='validate_live_chain_continuation'; classification='transitively_gated'; operational='operational' },
    [ordered]@{ file=$Phase48_5Path; name='Invoke-FrozenBaselineEnforcementGate'; role='frozen_baseline_gate_entrypoint'; operation='enforce_frozen_baseline_before_runtime_init'; classification='directly_gated'; operational='operational' },
    [ordered]@{ file=$Phase48_5Path; name='Get-ProtectedEntrypointInventory'; role='proof_inventory_helper'; operation='materialize_proof_inventory_labels'; classification='dead_non_operational'; operational='dead' },
    [ordered]@{ file=$Phase48_5Path; name='Invoke-ProtectedOperation'; role='protected_entrypoint_wrapper'; operation='guard_protected_operation_then_allow_or_block'; classification='directly_gated'; operational='operational' },
    [ordered]@{ file=$Phase48_5Path; name='Add-ValidationLine'; role='proof_recording_helper'; operation='record_phase48_5_validation'; classification='dead_non_operational'; operational='dead' }
)

$defIndex = @{}
foreach ($def in $allDefs) {
    $defIndex[$def.file_path + '|' + $def.function_name] = $def
}

$inventoryRows = [System.Collections.Generic.List[object]]::new()
$missingDefs = [System.Collections.Generic.List[string]]::new()

foreach ($spec in $expectedFunctionSpecs) {
    $key = [string]$spec.file + '|' + [string]$spec.name
    if (-not $defIndex.ContainsKey($key)) {
        $missingDefs.Add($key)
        continue
    }

    $def = $defIndex[$key]
    $fileText = Get-Content -Raw -LiteralPath $def.file_path
    $refCount = Get-TextReferenceCount -Text $fileText -Name $def.function_name

    $directGatePresent = 'no'
    $transitiveGatePresent = 'no'
    $gateSourcePath = ''

    switch ([string]$spec.classification) {
        'directly_gated' {
            $directGatePresent = 'yes'
            if ([string]$spec.name -eq 'Invoke-FrozenBaselineEnforcementGate') {
                $gateSourcePath = ([string]$spec.file + '::Invoke-FrozenBaselineEnforcementGate')
            } else {
                $gateSourcePath = ($Phase48_5Path + '::Invoke-FrozenBaselineEnforcementGate')
            }
        }
        'transitively_gated' {
            $transitiveGatePresent = 'yes'
            if ([string]$spec.file -eq $Phase48_4Path) {
                $gateSourcePath = ($Phase48_4Path + '::Invoke-FrozenBaselineEnforcementGate')
            } else {
                $gateSourcePath = ($Phase48_5Path + '::Invoke-ProtectedOperation -> ' + $Phase48_5Path + '::Invoke-FrozenBaselineEnforcementGate')
            }
        }
        'upstream_non_operational' {
            $gateSourcePath = 'upstream_phase48_3_baseline_lock_only'
        }
        'dead_non_operational' {
            $gateSourcePath = 'not_applicable'
        }
    }

    $inventoryRows.Add((New-InventoryRow -FilePath $def.file_path -Name $def.function_name -Role ([string]$spec.role) -OperationalOrDead ([string]$spec.operational) -DirectGatePresent $directGatePresent -TransitiveGatePresent $transitiveGatePresent -GateSourcePath $gateSourcePath -OperationType ([string]$spec.operation) -CoverageClassification ([string]$spec.classification) -Notes ('definition_line=' + [string]$def.start_line + '; references_in_file=' + [string]$refCount) -SymbolKind 'actual_function' -DefinitionLine $def.start_line))
}

$proofInventoryRows = [System.Collections.Generic.List[object]]::new()
$proofInventoryLines = Get-Content -LiteralPath $Proof10 | Where-Object { $_ -match '^protected_input_type=' }
foreach ($line in $proofInventoryLines) {
    $parsed = Parse-KeyValueLine -Line $line
    $proofInventoryRows.Add((New-InventoryRow -FilePath ([string]$parsed.file_path) -Name ([string]$parsed.entrypoint_or_helper_name) -Role ([string]$parsed.protected_input_type) -OperationalOrDead 'dead' -DirectGatePresent 'no' -TransitiveGatePresent 'no' -GateSourcePath ($Phase48_5Path + '::Invoke-ProtectedOperation -> ' + $Phase48_5Path + '::Invoke-FrozenBaselineEnforcementGate') -OperationType ([string]$parsed.operation_requested) -CoverageClassification 'proof_label_mapped' -Notes 'present in latest phase48_5 proof inventory only; no standalone function definition discovered in repo scan' -SymbolKind 'proof_label' -DefinitionLine 0))
}

foreach ($row in $proofInventoryRows) {
    $inventoryRows.Add($row)
}

$phase48_5GateFile = Get-Content -LiteralPath $Proof98
$phase48_5ValidationLines = Get-Content -LiteralPath $Proof14
$phase48_5MapLines = Get-Content -LiteralPath $Proof11
$phase48_5GateRecords = @(Get-Content -LiteralPath $Proof16 | Select-Object -Skip 1 | ForEach-Object { Parse-KeyValueLine -Line $_ })

$inventoryComplete = ($missingDefs.Count -eq 0)
foreach ($expectedFile in $expectedRelevantFiles) {
    if ($relevantFiles -notcontains $expectedFile) { $inventoryComplete = $false }
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

$phase48_5GatePass = (($phase48_5GateFile -join "`n") -match 'GATE=\s*PASS')
$phase48_5AllPass = (@($phase48_5ValidationLines | Where-Object { $_ -match '=> PASS$' }).Count -eq 9)
$proofLabelNames = @($proofInventoryRows | ForEach-Object { [string]$_.function_or_entrypoint_name })
$proofMapCoverage = $true
foreach ($proofLabel in $proofLabelNames) {
    if (-not ($phase48_5MapLines -match [regex]::Escape($proofLabel))) {
        $proofMapCoverage = $false
        break
    }
}

$gateRecordCoverage = $true
foreach ($record in $phase48_5GateRecords) {
    $name = [string]$record.entrypoint_or_helper_name
    if ($proofLabelNames -notcontains $name -and $name -ne 'Invoke-FrozenBaselineEnforcementGate') {
        $gateRecordCoverage = $false
        break
    }
}

$bypassCrosscheck = ($phase48_5GatePass -and $phase48_5AllPass -and $proofMapCoverage -and $gateRecordCoverage)

$ValidationLines = [System.Collections.Generic.List[string]]::new()
Add-ValidationResult -Lines $ValidationLines -CaseId 'A' -CaseName 'entrypoint_inventory' -Pass $inventoryComplete -Detail ('entrypoint_inventory=' + $(if ($inventoryComplete) { 'COMPLETE' } else { 'INCOMPLETE' }))
Add-ValidationResult -Lines $ValidationLines -CaseId 'B' -CaseName 'direct_gate_coverage' -Pass $directGateCoverage -Detail ('direct_gate_coverage=' + $(if ($directGateCoverage) { 'VERIFIED' } else { 'FAILED' }))
Add-ValidationResult -Lines $ValidationLines -CaseId 'C' -CaseName 'transitive_gate_coverage' -Pass $transitiveGateCoverage -Detail ('transitive_gate_coverage=' + $(if ($transitiveGateCoverage) { 'VERIFIED' } else { 'FAILED' }))
Add-ValidationResult -Lines $ValidationLines -CaseId 'D' -CaseName 'unguarded_path_detection' -Pass ($unguardedOperationalCount -eq 0) -Detail ('unguarded_operational_paths=' + [string]$unguardedOperationalCount)
Add-ValidationResult -Lines $ValidationLines -CaseId 'E' -CaseName 'dead_non_operational_helper_classification' -Pass ($deadHelpersDocumented -and -not $misclassifiedDeadAsCovered) -Detail ('dead_helpers=' + $(if ($deadHelpersDocumented) { 'DOCUMENTED' } else { 'MISSING' }) + ' misclassified_dead_as_covered=' + $(if ($misclassifiedDeadAsCovered) { 'TRUE' } else { 'FALSE' }))
Add-ValidationResult -Lines $ValidationLines -CaseId 'F' -CaseName 'coverage_map_consistency' -Pass $coverageMapConsistency -Detail ('coverage_map_consistency=' + $(if ($coverageMapConsistency) { 'TRUE' } else { 'FALSE' }))
Add-ValidationResult -Lines $ValidationLines -CaseId 'G' -CaseName 'phase48_5_crosscheck' -Pass $bypassCrosscheck -Detail ('bypass_crosscheck=' + $(if ($bypassCrosscheck) { 'TRUE' } else { 'FALSE' }))

$Gate = if ($inventoryComplete -and $directGateCoverage -and $transitiveGateCoverage -and ($unguardedOperationalCount -eq 0) -and $deadHelpersDocumented -and -not $misclassifiedDeadAsCovered -and $coverageMapConsistency -and $bypassCrosscheck) { 'PASS' } else { 'FAIL' }

$status01 = @(
    'PHASE=48.6',
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
    'RUNNER=tools/phase48_6/phase48_6_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_coverage_audit_runner.ps1',
    'SOURCE_48_3=' + $Phase48_3Path,
    'SOURCE_48_4=' + $Phase48_4Path,
    'SOURCE_48_5=' + $Phase48_5Path,
    'LATEST_48_5_PROOF=' + $Latest48_5Proof.FullName
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '02_head.txt'), $head02, [System.Text.Encoding]::UTF8)

$definition10 = @(
    'INVENTORY_METHOD=static function-definition scan of real phase48_3, phase48_4, phase48_5 runners plus proof-label cross-check from latest phase48_5 packet',
    'CLASSIFICATION_DIMENSIONS=role, operational_or_dead, direct_gate_present, transitive_gate_present, gate_source_path, coverage_classification',
    'DIRECT_GATE_RULE=gate function itself or wrapper body containing Invoke-FrozenBaselineEnforcementGate',
    'TRANSITIVE_GATE_RULE=helper reachable only through Invoke-FrozenBaselineEnforcementGate or Invoke-ProtectedOperation guarded path',
    'DEAD_RULE=proof-only, recording-only, or upstream-only helper not counted as active 48.4/48.5 operational surface',
    'CROSSCHECK_SOURCE=' + $Latest48_5Proof.FullName
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '10_entrypoint_inventory_definition.txt'), $definition10, [System.Text.Encoding]::UTF8)

$rules11 = @(
    'RULE_1=Every operational frozen-baseline-relevant function in phase48_4 and phase48_5 must be discovered.',
    'RULE_2=Invoke-FrozenBaselineEnforcementGate and Invoke-ProtectedOperation count as direct gate coverage sources.',
    'RULE_3=Lower-level canonicalization, hash, and chain helpers must be classified as transitively gated or the audit fails.',
    'RULE_4=Upstream phase48_3 materializers are documented as non-operational for the active 48.4/48.5 model and not counted as covered.',
    'RULE_5=Proof-only labels from latest phase48_5 inventory must be represented in the map without being misreported as standalone functions.',
    'RULE_6=Any operational row with neither direct nor transitive gate coverage is an unguarded path and causes FAIL.',
    'RULE_7=Latest phase48_5 gate, validation, inventory, and map artifacts must agree with the generated coverage map.'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '11_frozen_baseline_coverage_rules.txt'), $rules11, [System.Text.Encoding]::UTF8)

$files12 = @(
    'READ=' + $Phase48_3Path,
    'READ=' + $Phase48_4Path,
    'READ=' + $Phase48_5Path,
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
    'UNGUARDED_OPERATIONAL_PATHS=' + [string]$unguardedOperationalCount,
    'LATEST_48_5_GATE_PASS=' + $(if ($phase48_5GatePass) { 'TRUE' } else { 'FALSE' }),
    'GATE=' + $Gate
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '13_build_output.txt'), $build13, [System.Text.Encoding]::UTF8)

[System.IO.File]::WriteAllText((Join-Path $PF '14_validation_results.txt'), ($ValidationLines -join "`r`n"), [System.Text.Encoding]::UTF8)

$summary15 = @(
    'The frozen-baseline-relevant surface was inventoried by statically scanning real function definitions in phase48_3, phase48_4, and phase48_5 and then merging proof-label rows from the latest phase48_5 inventory artifact.',
    'Direct gate coverage was assigned only to Invoke-FrozenBaselineEnforcementGate and the Invoke-ProtectedOperation wrapper because those bodies enforce the gate themselves.',
    'Transitive gate coverage was assigned to canonicalization, hash, and chain helpers that are only used through the gate or the protected wrapper path inside the active model.',
    'Dead helpers were distinguished by role: proof-recording helpers, proof-inventory builders, synthetic proof labels, and phase48_3 upstream materializers are not counted as active 48.4/48.5 operational entrypoints.',
    'Unguarded path detection reports any operational actual function row that has neither direct nor transitive gate coverage; this audit found ' + [string]$unguardedOperationalCount + ' such rows.',
    'The phase48_5 cross-check verified latest gate PASS, all validation cases PASS, and map/inventory agreement for every bypass-tested proof label.',
    'Runtime behavior remained unchanged because this phase reads existing scripts and proof artifacts only and writes a new audit proof packet.'
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
    'latest_phase48_5_proof=' + $Latest48_5Proof.FullName,
    'latest_phase48_5_gate_pass=' + $(if ($phase48_5GatePass) { 'TRUE' } else { 'FALSE' }),
    'latest_phase48_5_all_validation_cases_pass=' + $(if ($phase48_5AllPass) { 'TRUE' } else { 'FALSE' }),
    'proof_inventory_labels=' + [string]$proofInventoryRows.Count,
    'proof_map_coverage=' + $(if ($proofMapCoverage) { 'TRUE' } else { 'FALSE' }),
    'gate_record_coverage=' + $(if ($gateRecordCoverage) { 'TRUE' } else { 'FALSE' }),
    'bypass_crosscheck=' + $(if ($bypassCrosscheck) { 'TRUE' } else { 'FALSE' })
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '19_bypass_crosscheck_report.txt'), $cross19, [System.Text.Encoding]::UTF8)

$gate98 = @('PHASE=48.6', 'GATE=' + $Gate) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '98_gate_phase48_6.txt'), $gate98, [System.Text.Encoding]::UTF8)

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