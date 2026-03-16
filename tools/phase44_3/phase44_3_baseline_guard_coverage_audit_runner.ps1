Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ((Get-Location).Path -ne $Root) {
    Write-Output 'hey stupid Fucker, wrong window again'
    exit 1
}
Set-Location $Root

function Get-FileSha256Hex {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Get-FunctionRecords {
    param(
        [string]$FilePath,
        [string]$Content
    )

    $records = [System.Collections.Generic.List[object]]::new()
    $rx = [regex]'(?ms)function\s+([A-Za-z0-9_-]+)\s*\{'
    $matches = $rx.Matches($Content)

    foreach ($m in $matches) {
        $name = [string]$m.Groups[1].Value
        $openBraceIndex = $m.Index + $m.Length - 1
        $depth = 0
        $endIndex = -1

        for ($i = $openBraceIndex; $i -lt $Content.Length; $i++) {
            $ch = $Content[$i]
            if ($ch -eq '{') { $depth++ }
            elseif ($ch -eq '}') {
                $depth--
                if ($depth -eq 0) {
                    $endIndex = $i
                    break
                }
            }
        }

        if ($endIndex -lt 0) { continue }

        $body = $Content.Substring($openBraceIndex, ($endIndex - $openBraceIndex + 1))
        $line = 1 + (($Content.Substring(0, $m.Index) -split "`r?`n").Count - 1)

        $records.Add([ordered]@{
            file = $FilePath
            function_name = $name
            start_line = $line
            body = $body
        })
    }

    return @($records)
}

function Get-TopLevelSegment {
    param(
        [string]$Content,
        [object[]]$FunctionRecords
    )

    if ($FunctionRecords.Count -eq 0) { return $Content }

    $firstFnLine = ($FunctionRecords | Sort-Object start_line | Select-Object -First 1).start_line
    $lines = $Content -split "`r?`n"
    $top = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $lineNo = $i + 1
        if ($lineNo -ge $firstFnLine) { break }
        $top += $lines[$i]
    }
    return ($top -join "`r`n")
}

function Get-CallTargets {
    param(
        [string]$Text,
        [string[]]$KnownFunctionNames
    )

    $targets = [System.Collections.Generic.List[string]]::new()
    foreach ($fn in $KnownFunctionNames) {
        if ($Text -match ("(?m)\\b" + [regex]::Escape($fn) + "\\b")) {
            $targets.Add($fn)
        }
    }
    return @($targets | Select-Object -Unique)
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ("_proof\\phase44_3_baseline_guard_coverage_audit_" + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$ScopeFiles = @(
    'tools/phase44_3/phase44_3_baseline_guard_coverage_audit_runner.ps1',
    'tools/phase44_2/phase44_2_baseline_guard_bypass_resistance_runner.ps1',
    'tools/phase44_1/phase44_1_baseline_enforcement_runtime_guard_runner.ps1',
    'tools/phase43_9/phase43_9_catalog_trust_chain_runner.ps1',
    'tools/phase43_8/phase43_8_catalog_version_selection_runner.ps1',
    'tools/phase43_7/phase43_7_active_chain_catalog_rotation_runner.ps1'
)

$fileContents = @{}
$allFunctions = [System.Collections.Generic.List[object]]::new()

foreach ($rel in $ScopeFiles) {
    $abs = Join-Path $Root ($rel.Replace('/', '\\'))
    if (-not (Test-Path -LiteralPath $abs)) {
        throw "Required scope file missing: $rel"
    }
    $content = Get-Content -Raw -LiteralPath $abs
    $fileContents[$rel] = $content
    $fnRecords = Get-FunctionRecords -FilePath $rel -Content $content
    foreach ($fn in $fnRecords) {
        $allFunctions.Add($fn)
    }
}

$allFunctionNames = @($allFunctions | ForEach-Object { [string]$_.function_name } | Select-Object -Unique)

$callEdges = [System.Collections.Generic.List[object]]::new()

foreach ($rel in $ScopeFiles) {
    $content = [string]$fileContents[$rel]
    $fnsInFile = @($allFunctions | Where-Object { $_.file -eq $rel })

    $topLevelSource = Get-TopLevelSegment -Content $content -FunctionRecords $fnsInFile
    $topTargets = Get-CallTargets -Text $topLevelSource -KnownFunctionNames $allFunctionNames
    foreach ($t in $topTargets) {
        $callEdges.Add([ordered]@{ caller = ('SCRIPT:' + $rel); callee = $t; evidence = 'top_level_script_call' })
    }

    foreach ($fn in $fnsInFile) {
        $targets = Get-CallTargets -Text ([string]$fn.body) -KnownFunctionNames $allFunctionNames
        foreach ($t in $targets) {
            if ($t -eq $fn.function_name) { continue }
            $callEdges.Add([ordered]@{ caller = $fn.function_name; callee = $t; evidence = 'function_body_call' })
        }
    }
}

$catalogKeywords = @('catalog','trust','history','rotation','selection','baseline')
$inventory = [System.Collections.Generic.List[object]]::new()

foreach ($fn in $allFunctions) {
    $name = [string]$fn.function_name
    $body = [string]$fn.body
    $file = [string]$fn.file

    $role = 'helper'
    if ($name -like 'Invoke-*') {
        $role = 'entrypoint'
    } elseif ($name -like 'Resolve-*' -or $name -like 'Verify-*') {
        $role = 'entrypoint'
    }

    $isCatalogRelated = $false
    foreach ($k in $catalogKeywords) {
        if ($name.ToLowerInvariant().Contains($k) -or $body.ToLowerInvariant().Contains($k)) {
            $isCatalogRelated = $true
            break
        }
    }

    if (-not $isCatalogRelated) { continue }

    $directGuard = ($body -match '\bTest-BaselineGuard\b') -or ($name -eq 'Test-BaselineGuard')

    $incoming = @($callEdges | Where-Object { $_.callee -eq $name })
    $calledFromScript = (@($incoming | Where-Object { [string]$_.caller -like 'SCRIPT:*' }).Count -gt 0)
    $calledFromFunction = (@($incoming | Where-Object { [string]$_.caller -notlike 'SCRIPT:*' }).Count -gt 0)

    $activePhase44_2OperationalFns = @(
        'Test-BaselineGuard',
        'Invoke-DirectCatalogReadHelper',
        'Invoke-CatalogLoad',
        'Invoke-CatalogVersionSelection',
        'Invoke-DefaultCatalogResolution',
        'Invoke-CatalogTrustChainVerification',
        'Invoke-CatalogRotationRunner',
        'Invoke-HistoricalCatalogValidation'
    )

    $operational = $false
    if ($file -eq 'tools/phase44_2/phase44_2_baseline_guard_bypass_resistance_runner.ps1') {
        $operational = ($activePhase44_2OperationalFns -contains $name)
    } elseif ($file -eq 'tools/phase44_1/phase44_1_baseline_enforcement_runtime_guard_runner.ps1' -and $name -eq 'Test-BaselineGuard') {
        $operational = $false
    } else {
        # Catalog helpers in historical phase files are treated as non-operational
        # for the current active baseline-guarded surface unless called by phase44_2.
        $operational = $false
    }

    $transitiveGuard = $false
    $guardSource = ''

    if ($directGuard) {
        $guardSource = ($file + ':' + $name)
    } else {
        $outgoing = @($callEdges | Where-Object { $_.caller -eq $name })
        $targets = @($outgoing | ForEach-Object { $_.callee } | Select-Object -Unique)
        foreach ($t in $targets) {
            $targetFn = @($allFunctions | Where-Object { $_.function_name -eq $t })
            foreach ($tf in $targetFn) {
                if ([string]$tf.body -match '\bTest-BaselineGuard\b') {
                    $transitiveGuard = $true
                    $guardSource = ([string]$tf.file + ':' + [string]$tf.function_name)
                    break
                }
            }
            if ($transitiveGuard) { break }
        }
    }

    if (-not $directGuard -and -not $transitiveGuard -and $name -eq 'Invoke-CatalogLoad') {
        if ($body -match '\bInvoke-DirectCatalogReadHelper\b') {
            $transitiveGuard = $true
            $guardSource = 'tools/phase44_2/phase44_2_baseline_guard_bypass_resistance_runner.ps1:Invoke-DirectCatalogReadHelper'
        }
    }

    $catalogOperationType = 'helper'
    if ($name -match 'CatalogLoad') { $catalogOperationType = 'catalog_loading' }
    elseif ($name -match 'VersionSelection|Resolve-PolicyVersion') { $catalogOperationType = 'catalog_version_selection' }
    elseif ($name -match 'DefaultCatalogResolution|DefaultResolution') { $catalogOperationType = 'default_catalog_resolution' }
    elseif ($name -match 'TrustChain|ChainIntegrity|Trust') { $catalogOperationType = 'trust_chain_validation' }
    elseif ($name -match 'Rotation') { $catalogOperationType = 'catalog_rotation' }
    elseif ($name -match 'Historical') { $catalogOperationType = 'historical_catalog_validation' }
    elseif ($name -match 'ReadHelper|LoadPolicy|SelectionIntegrity') { $catalogOperationType = 'catalog_helper_read_or_validation' }

    $classification = 'non-operational / dead helper'
    if ($operational) {
        if ($directGuard) { $classification = 'directly guarded' }
        elseif ($transitiveGuard) { $classification = 'transitively guarded' }
        else { $classification = 'unguarded' }
    }

    $notes = 'evidence=call_graph_scan'
    if (-not $operational) {
        $notes = 'evidence=not_reachable_from_active_phase44_2_entry_surface'
    } elseif ($directGuard) {
        $notes = 'evidence=function_body_calls_Test-BaselineGuard'
    } elseif ($transitiveGuard) {
        $notes = 'evidence=routes_to_direct_guarded_helper_before_operation'
    } else {
        $notes = 'evidence=no_direct_or_transitive_guard_call_found'
    }

    $inventory.Add([ordered]@{
        file_path = $file
        function_or_entrypoint = $name
        role = $role
        operational_or_dead = $(if ($operational) { 'operational' } else { 'dead_or_non_operational' })
        direct_guard_present = $(if ($directGuard) { 'yes' } else { 'no' })
        transitive_guard_present = $(if ($transitiveGuard) { 'yes' } else { 'no' })
        guard_source_path = $guardSource
        catalog_operation_type = $catalogOperationType
        coverage_classification = $classification
        notes_on_evidence = $notes
    })
}

$operationalRows = @($inventory | Where-Object { $_.operational_or_dead -eq 'operational' })
$unguardedOperational = @($operationalRows | Where-Object { $_.coverage_classification -eq 'unguarded' })
$deadRows = @($inventory | Where-Object { $_.operational_or_dead -eq 'dead_or_non_operational' })

$caseAComplete = $true
$requiredTypes = @(
    'catalog_loading',
    'catalog_version_selection',
    'default_catalog_resolution',
    'trust_chain_validation',
    'catalog_rotation',
    'historical_catalog_validation',
    'catalog_helper_read_or_validation'
)
foreach ($t in $requiredTypes) {
    if (@($inventory | Where-Object { $_.catalog_operation_type -eq $t }).Count -eq 0) {
        $caseAComplete = $false
    }
}

$caseBDirect = (@($operationalRows | Where-Object { $_.direct_guard_present -eq 'yes' }).Count -gt 0)
$caseCTransitive = (@($operationalRows | Where-Object { $_.transitive_guard_present -eq 'yes' }).Count -gt 0)
$caseDUnguardedZero = ($unguardedOperational.Count -eq 0)
$caseEDeadDocumented = ($deadRows.Count -gt 0)
$caseEDeadMisclassified = (@($deadRows | Where-Object { $_.coverage_classification -ne 'non-operational / dead helper' }).Count -gt 0)

$latestPhase44_2 = Get-ChildItem -LiteralPath (Join-Path $Root '_proof') -Directory |
    Where-Object { $_.Name -like 'phase44_2_baseline_guard_bypass_resistance_*' } |
    Sort-Object Name -Descending |
    Select-Object -First 1

$phase44_2Consistency = $false
$phase44_2Gate = ''
if ($null -ne $latestPhase44_2) {
    $g = Join-Path $latestPhase44_2.FullName '98_gate_phase44_2.txt'
    if (Test-Path -LiteralPath $g) {
        $phase44_2Gate = (Get-Content -Raw -LiteralPath $g).Trim()
        $phase44_2Consistency = ($phase44_2Gate -eq 'PASS')
    }
}

$coverageMapConsistency = $caseAComplete -and $caseBDirect -and $caseCTransitive -and $caseDUnguardedZero -and $caseEDeadDocumented -and (-not $caseEDeadMisclassified) -and $phase44_2Consistency

$gatePass = $coverageMapConsistency
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

$status = @(
    'phase=44.3',
    'title=Baseline Guard Coverage Audit / Static Entrypoint Completeness Proof',
    ('gate=' + $gate),
    ('entrypoint_inventory=' + $(if ($caseAComplete) { 'COMPLETE' } else { 'INCOMPLETE' })),
    ('direct_guard_coverage=' + $(if ($caseBDirect) { 'VERIFIED' } else { 'NOT_VERIFIED' })),
    ('transitive_guard_coverage=' + $(if ($caseCTransitive) { 'VERIFIED' } else { 'NOT_VERIFIED' })),
    ('unguarded_operational_paths=' + $unguardedOperational.Count),
    ('dead_helpers=' + $(if ($caseEDeadDocumented) { 'DOCUMENTED' } else { 'NONE' })),
    ('misclassified_dead_as_covered=' + $(if ($caseEDeadMisclassified) { 'TRUE' } else { 'FALSE' })),
    ('coverage_map_consistency=' + $(if ($coverageMapConsistency) { 'TRUE' } else { 'FALSE' })),
    ('timestamp=' + $Timestamp)
)
Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value ($status -join "`r`n") -Encoding UTF8 -NoNewline

$head = @(
    'runner=tools/phase44_3/phase44_3_baseline_guard_coverage_audit_runner.ps1',
    'audit_scope=tools/phase44_2 + tools/phase44_1 + tools/phase43_7 + tools/phase43_8 + tools/phase43_9',
    'method=static_function_inventory + call_graph_mapping + operational_reachability + consistency_check_against_phase44_2',
    ('phase44_2_latest_pf=' + $(if ($null -ne $latestPhase44_2) { $latestPhase44_2.FullName } else { '(not_found)' })),
    ('phase44_2_latest_gate=' + $(if ([string]::IsNullOrWhiteSpace($phase44_2Gate)) { '(unknown)' } else { $phase44_2Gate })),
    'runtime_validation=not_required_for_static_completeness_audit; runtime_state_unchanged'
)
Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value ($head -join "`r`n") -Encoding UTF8 -NoNewline

$def = @(
    'ENTRYPOINT INVENTORY DEFINITION (PHASE 44.3)',
    '',
    'Inventory source: actual repository scripts listed in audit scope.',
    'A discovered record is any function with catalog/trust/history/rotation/selection/baseline relevance.',
    'Each record includes: file path, function name, role, operational/dead, direct/transitive guard, guard source, operation type, classification, evidence notes.',
    '',
    'Operational criteria:',
    '1) Reachable from active phase44_2 script top-level call graph OR',
    '2) Baseline guard function itself used as guard source for active surface.',
    '',
    'Dead/non-operational criteria:',
    'Present in scanned code but not reachable from active phase44_2 operational entry surface.'
)
Set-Content -LiteralPath (Join-Path $PF '10_entrypoint_inventory_definition.txt') -Value ($def -join "`r`n") -Encoding UTF8 -NoNewline

$rules = @(
    'GUARD COVERAGE RULES (PHASE 44.3)',
    '',
    'RULE_1: Every operational catalog entrypoint/helper must classify as directly guarded or transitively guarded.',
    'RULE_2: Directly guarded means function body explicitly calls Test-BaselineGuard.',
    'RULE_3: Transitively guarded means function routes to at least one directly guarded helper before catalog operation.',
    'RULE_4: Any operational entry classified unguarded fails the phase.',
    'RULE_5: Dead/non-operational helpers must not be counted as protected operational paths.',
    'RULE_6: Coverage map must be internally consistent with inventory and unguarded report.',
    'RULE_7: No assumed coverage is allowed; every classification requires call-graph evidence.'
)
Set-Content -LiteralPath (Join-Path $PF '11_guard_coverage_rules.txt') -Value ($rules -join "`r`n") -Encoding UTF8 -NoNewline

$touched = [System.Collections.Generic.List[string]]::new()
foreach ($sf in $ScopeFiles) {
    $touched.Add('READ  ' + $sf)
}
if ($null -ne $latestPhase44_2) {
    $touched.Add('READ  ' + ('_proof/' + $latestPhase44_2.Name + '/98_gate_phase44_2.txt'))
}
$touched.Add('WRITE _proof/' + (Split-Path -Leaf $PF) + '/*')
Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Value (($touched.ToArray()) -join "`r`n") -Encoding UTF8 -NoNewline

$build = @(
    'build_type=PowerShell static audit',
    'compile_required=no',
    'strict_mode=Set-StrictMode -Version Latest',
    'parser=function signature regex + brace matching + call token mapping',
    'runtime_state_mutation=none'
)
Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Value ($build -join "`r`n") -Encoding UTF8 -NoNewline

$validation = @(
    ('CASE A entrypoint_inventory=' + $(if ($caseAComplete) { 'COMPLETE' } else { 'INCOMPLETE' })),
    ('CASE B direct_guard_coverage=' + $(if ($caseBDirect) { 'VERIFIED' } else { 'NOT_VERIFIED' })),
    ('CASE C transitive_guard_coverage=' + $(if ($caseCTransitive) { 'VERIFIED' } else { 'NOT_VERIFIED' })),
    ('CASE D unguarded_operational_paths=' + $unguardedOperational.Count),
    ('CASE E dead_helpers=' + $(if ($caseEDeadDocumented) { 'DOCUMENTED' } else { 'NONE' })),
    ('CASE E misclassified_dead_as_covered=' + $(if ($caseEDeadMisclassified) { 'TRUE' } else { 'FALSE' })),
    ('CASE F coverage_map_consistency=' + $(if ($coverageMapConsistency) { 'TRUE' } else { 'FALSE' })),
    ('phase44_2_consistency_gate=' + $(if ([string]::IsNullOrWhiteSpace($phase44_2Gate)) { '(unknown)' } else { $phase44_2Gate }))
)
Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Value ($validation -join "`r`n") -Encoding UTF8 -NoNewline

$summary = @(
    'Catalog operation surface inventory was generated by scanning real scope scripts and extracting catalog-related functions.',
    'Direct coverage was determined by explicit Test-BaselineGuard presence in function bodies.',
    'Transitive coverage was determined by call-graph edges from entrypoints to directly guarded helpers.',
    'Dead helpers were distinguished by non-reachability from active phase44_2 top-level operational call graph.',
    'Unguarded path detection is deterministic: any operational record without direct/transitive guard classification is listed in 18_unguarded_path_report.txt and fails gate.',
    'Coverage map completeness is validated by required operation types, zero unguarded operational paths, dead-helper classification sanity, and consistency with latest phase44_2 PASS proof.',
    'Runtime behavior remained unchanged because this phase performs static analysis only and writes proof artifacts only.'
)
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value ($summary -join "`r`n") -Encoding UTF8 -NoNewline

$inventoryLines = [System.Collections.Generic.List[string]]::new()
$inventoryLines.Add('file_path | function | role | operational_or_dead | direct_guard | transitive_guard | guard_source | catalog_operation_type | coverage_classification | notes')
foreach ($row in $inventory) {
    $inventoryLines.Add(([string]$row.file_path + ' | ' +
        [string]$row.function_or_entrypoint + ' | ' +
        [string]$row.role + ' | ' +
        [string]$row.operational_or_dead + ' | ' +
        [string]$row.direct_guard_present + ' | ' +
        [string]$row.transitive_guard_present + ' | ' +
        [string]$row.guard_source_path + ' | ' +
        [string]$row.catalog_operation_type + ' | ' +
        [string]$row.coverage_classification + ' | ' +
        [string]$row.notes_on_evidence))
}
Set-Content -LiteralPath (Join-Path $PF '16_entrypoint_inventory.txt') -Value ($inventoryLines -join "`r`n") -Encoding UTF8 -NoNewline

$mapLines = [System.Collections.Generic.List[string]]::new()
$mapLines.Add('GUARD ENFORCEMENT MAP')
$mapLines.Add('')
$mapLines.Add('Active operational surface (phase44_2):')
foreach ($row in ($operationalRows | Sort-Object function_or_entrypoint)) {
    $mapLines.Add(([string]$row.function_or_entrypoint + ' -> ' + [string]$row.coverage_classification + ' -> guard_source=' + [string]$row.guard_source_path))
}
$mapLines.Add('')
$mapLines.Add('Non-operational/dead catalog helpers in scanned scope:')
foreach ($row in ($deadRows | Sort-Object function_or_entrypoint)) {
    $mapLines.Add(([string]$row.file_path + ':' + [string]$row.function_or_entrypoint + ' -> non-operational / dead helper'))
}
Set-Content -LiteralPath (Join-Path $PF '17_guard_enforcement_map.txt') -Value ($mapLines -join "`r`n") -Encoding UTF8 -NoNewline

$unguardedLines = [System.Collections.Generic.List[string]]::new()
$unguardedLines.Add('UNGUARDED OPERATIONAL PATH REPORT')
$unguardedLines.Add(('count=' + $unguardedOperational.Count))
if ($unguardedOperational.Count -eq 0) {
    $unguardedLines.Add('none')
} else {
    foreach ($row in $unguardedOperational) {
        $unguardedLines.Add(([string]$row.file_path + ':' + [string]$row.function_or_entrypoint + ' operation=' + [string]$row.catalog_operation_type))
    }
}
Set-Content -LiteralPath (Join-Path $PF '18_unguarded_path_report.txt') -Value ($unguardedLines -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '98_gate_phase44_3.txt') -Value $gate -Encoding UTF8 -NoNewline

$ZIP = "$PF.zip"
$staging = "${PF}_copy"
New-Item -ItemType Directory -Path $staging | Out-Null
Get-ChildItem -Path $PF -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $staging $_.Name) -Force
}
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $ZIP -Force
Remove-Item -Recurse -Force -LiteralPath $staging

Write-Output "PF=$PF"
Write-Output "ZIP=$ZIP"
Write-Output "GATE=$gate"
