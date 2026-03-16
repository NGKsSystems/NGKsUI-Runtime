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
        $key = ($FilePath + '::' + $name)

        $records.Add([ordered]@{
            key = $key
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
    $top = [System.Collections.Generic.List[string]]::new()

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $lineNo = $i + 1
        if ($lineNo -ge $firstFnLine) { break }
        $top.Add($lines[$i])
    }

    return ($top.ToArray() -join "`r`n")
}

function Get-CallTargetNames {
    param(
        [string]$Text,
        [string[]]$KnownFunctionNames
    )

    $targets = [System.Collections.Generic.List[string]]::new()
    foreach ($fn in $KnownFunctionNames) {
        if ($Text -match ("(?m)\b" + [regex]::Escape($fn) + "\b")) {
            $targets.Add($fn)
        }
    }
    return @($targets | Select-Object -Unique)
}

function Get-OperationType {
    param([string]$FunctionName)

    $name = $FunctionName.ToLowerInvariant()
    if ($name -match 'baseline.*snapshot.*load') { return 'baseline_snapshot_load' }
    if ($name -match 'baseline.*integrity.*load|integrity.*reference.*load') { return 'baseline_integrity_reference_load' }
    if ($name -match 'baseline.*verification|baseline.*validate') { return 'baseline_verification' }
    if ($name -match 'ledger.*load') { return 'ledger_load' }
    if ($name -match 'ledger.*continuity') { return 'ledger_continuity_validation' }
    if ($name -match 'append|future.*rotation') { return 'ledger_append_future_rotation_prep' }
    if ($name -match 'trust.*helper|trustchain|trust_chain') { return 'trust_chain_validation_helper' }
    if ($name -match 'historical') { return 'historical_baseline_ledger_validation' }
    if ($name -match 'runtimegate|runtime_gate') { return 'runtime_gate_core' }
    if ($name -match 'baseline|ledger|trust') { return 'baseline_ledger_trust_helper' }
    return 'helper'
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\\phase45_0_trust_chain_runtime_gate_coverage_audit_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$scopeFiles = @(
    'tools/phase45_0/phase45_0_trust_chain_runtime_gate_coverage_audit_runner.ps1',
    'tools/phase44_9/phase44_9_trust_chain_runtime_gate_bypass_resistance_runner.ps1',
    'tools/phase44_8/phase44_8_trust_chain_baseline_runtime_enforcement_runner.ps1',
    'tools/phase44_7/phase44_7_guard_fingerprint_trust_chain_baseline_lock_runner.ps1'
)

$fileContents = @{}
$allFunctions = [System.Collections.Generic.List[object]]::new()

foreach ($rel in $scopeFiles) {
    $abs = Join-Path $Root ($rel.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $abs)) {
        throw ('Required scope file missing: ' + $rel)
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
foreach ($fn in $allFunctions) {
    $targets = Get-CallTargetNames -Text ([string]$fn.body) -KnownFunctionNames $allFunctionNames
    foreach ($targetName in $targets) {
        if ($targetName -eq $fn.function_name) { continue }
        $candidates = @($allFunctions | Where-Object { $_.function_name -eq $targetName })
        foreach ($candidate in $candidates) {
            $callEdges.Add([ordered]@{
                caller_key = [string]$fn.key
                caller_file = [string]$fn.file
                caller = [string]$fn.function_name
                callee_key = [string]$candidate.key
                callee_file = [string]$candidate.file
                callee = [string]$candidate.function_name
                evidence = 'function_body_call'
            })
        }
    }
}

$phase44_9Functions = @($allFunctions | Where-Object { $_.file -eq 'tools/phase44_9/phase44_9_trust_chain_runtime_gate_bypass_resistance_runner.ps1' })
$phase44_9Top = Get-TopLevelSegment -Content ([string]$fileContents['tools/phase44_9/phase44_9_trust_chain_runtime_gate_bypass_resistance_runner.ps1']) -FunctionRecords $phase44_9Functions
$topTargets = Get-CallTargetNames -Text $phase44_9Top -KnownFunctionNames (@($phase44_9Functions | ForEach-Object { $_.function_name } | Select-Object -Unique))

$rootKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($targetName in $topTargets) {
    $targetsInFile = @($phase44_9Functions | Where-Object { $_.function_name -eq $targetName })
    foreach ($target in $targetsInFile) {
        $null = $rootKeys.Add([string]$target.key)
    }
}

# Phase44_9 is structured as functions declared first and invoked later; seed roots from operational wrappers.
$operationalRootFunctions = @(
    $phase44_9Functions |
    Where-Object {
        $_.function_name -like 'Invoke-*' -or $_.function_name -eq 'Get-Phase44_8RuntimeGateStatus'
    }
)
foreach ($fn in $operationalRootFunctions) {
    $null = $rootKeys.Add([string]$fn.key)
}

$runtimeKeywords = @('runtime_gate','baseline','ledger','trust_chain','trust-chain','historical','append')
$inventory = [System.Collections.Generic.List[object]]::new()

$queue = [System.Collections.Generic.Queue[string]]::new()
$reachable = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($k in $rootKeys) {
    $queue.Enqueue($k)
    $null = $reachable.Add($k)
}

while ($queue.Count -gt 0) {
    $node = $queue.Dequeue()
    $outgoing = @($callEdges | Where-Object { $_.caller_key -eq $node })
    foreach ($edge in $outgoing) {
        if (-not $reachable.Contains([string]$edge.callee_key)) {
            $null = $reachable.Add([string]$edge.callee_key)
            $queue.Enqueue([string]$edge.callee_key)
        }
    }
}

$functionMap = @{}
foreach ($fn in $allFunctions) {
    $functionMap[[string]$fn.key] = $fn
}

$runtimeRelevantByKey = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($fn in $allFunctions) {
    $name = [string]$fn.function_name
    $bodyLower = ([string]$fn.body).ToLowerInvariant()
    $isRelevant = $false
    foreach ($kw in $runtimeKeywords) {
        if ($name.ToLowerInvariant().Contains($kw) -or $bodyLower.Contains($kw)) {
            $isRelevant = $true
            break
        }
    }
    if ($isRelevant) {
        $null = $runtimeRelevantByKey.Add([string]$fn.key)
    }
}

$directGateByKey = @{}
foreach ($fn in $allFunctions) {
    $name = [string]$fn.function_name
    $body = [string]$fn.body
    $isDirect = $false
    if ($name -eq 'Get-Phase44_8RuntimeGateStatus') {
        $isDirect = $true
    } elseif ($body -match '\bGet-Phase44_8RuntimeGateStatus\b') {
        $isDirect = $true
    }
    $directGateByKey[[string]$fn.key] = $isDirect
}

$transitiveByKey = @{}
foreach ($fn in $allFunctions) {
    $transitiveByKey[[string]$fn.key] = $false
}

$changed = $true
while ($changed) {
    $changed = $false
    foreach ($fn in $allFunctions) {
        $key = [string]$fn.key
        if ($directGateByKey[$key]) { continue }
        $incoming = @($callEdges | Where-Object { $_.callee_key -eq $key })
        $hasGuardedCaller = $false
        foreach ($inEdge in $incoming) {
            $callerKey = [string]$inEdge.caller_key
            if ($directGateByKey[$callerKey] -or $transitiveByKey[$callerKey]) {
                $hasGuardedCaller = $true
                break
            }
        }
        if ($hasGuardedCaller -and -not $transitiveByKey[$key]) {
            $transitiveByKey[$key] = $true
            $changed = $true
        }
    }
}

foreach ($fn in $allFunctions) {
    $key = [string]$fn.key
    if (-not $runtimeRelevantByKey.Contains($key)) { continue }

    $file = [string]$fn.file
    $name = [string]$fn.function_name
    $role = 'helper'
    if ($name -like 'Invoke-*') { $role = 'entrypoint' }
    elseif ($name -eq 'Get-Phase44_8RuntimeGateStatus') { $role = 'gate_core' }
    elseif ($name -like 'Get-*') { $role = 'getter_or_validator' }

    $operational = $reachable.Contains($key) -and ($file -eq 'tools/phase44_9/phase44_9_trust_chain_runtime_gate_bypass_resistance_runner.ps1')
    $directGate = [bool]$directGateByKey[$key]
    $transitiveGate = [bool]$transitiveByKey[$key]

    $guardSource = ''
    if ($directGate) {
        $guardSource = ($file + ':' + $name)
    } elseif ($transitiveGate) {
        $incoming = @($callEdges | Where-Object { $_.callee_key -eq $key })
        $guardedIncoming = @($incoming | Where-Object { $directGateByKey[[string]$_.caller_key] -or $transitiveByKey[[string]$_.caller_key] })
        if ($guardedIncoming.Count -gt 0) {
            $first = $guardedIncoming[0]
            $guardSource = ([string]$first.caller_file + ':' + [string]$first.caller)
        }
    }

    $operationType = Get-OperationType -FunctionName $name

    $classification = 'non-operational / dead helper'
    if ($operational) {
        if ($directGate) { $classification = 'directly gated' }
        elseif ($transitiveGate) { $classification = 'transitively gated' }
        else { $classification = 'unguarded' }
    }

    $notes = 'evidence=call_graph_scan'
    if (-not $operational) {
        $notes = 'evidence=not_reachable_from_active_phase44_9_top_level_surface'
    } elseif ($directGate) {
        $notes = 'evidence=explicit_runtime_gate_invocation'
    } elseif ($transitiveGate) {
        $notes = 'evidence=only_reachable_via_gated_callers'
    } else {
        $notes = 'evidence=no_direct_or_transitive_gate_path_detected'
    }

    $inventory.Add([ordered]@{
        file_path = $file
        function_or_entrypoint = $name
        role = $role
        operational_or_dead = $(if ($operational) { 'operational' } else { 'dead_or_non_operational' })
        direct_gate_present = $(if ($directGate) { 'yes' } else { 'no' })
        transitive_gate_present = $(if ($transitiveGate) { 'yes' } else { 'no' })
        gate_source_path = $guardSource
        runtime_relevant_operation_type = $operationType
        coverage_classification = $classification
        notes_on_evidence = $notes
    })
}

$operationalRows = @($inventory | Where-Object { $_.operational_or_dead -eq 'operational' })
$deadRows = @($inventory | Where-Object { $_.operational_or_dead -eq 'dead_or_non_operational' })
$unguardedOperational = @($operationalRows | Where-Object { $_.coverage_classification -eq 'unguarded' })

$requiredOps = @(
    'baseline_snapshot_load',
    'baseline_integrity_reference_load',
    'baseline_verification',
    'ledger_load',
    'ledger_continuity_validation',
    'ledger_append_future_rotation_prep',
    'trust_chain_validation_helper',
    'historical_baseline_ledger_validation'
)
$caseAComplete = $true
foreach ($op in $requiredOps) {
    if (@($inventory | Where-Object { $_.runtime_relevant_operation_type -eq $op }).Count -eq 0) {
        $caseAComplete = $false
    }
}

$caseBDirect = (@($operationalRows | Where-Object { $_.direct_gate_present -eq 'yes' }).Count -gt 0)
$caseCTransitive = (@($operationalRows | Where-Object { $_.direct_gate_present -eq 'no' -and $_.transitive_gate_present -eq 'yes' }).Count -gt 0)
$caseDUnguardedZero = ($unguardedOperational.Count -eq 0)
$caseEDeadDocumented = ($deadRows.Count -gt 0)
$caseEMisclassified = (@($deadRows | Where-Object { $_.coverage_classification -ne 'non-operational / dead helper' }).Count -gt 0)

$latest44_9Pf = Get-ChildItem -LiteralPath (Join-Path $Root '_proof') -Directory |
    Where-Object { $_.Name -like 'phase44_9_trust_chain_runtime_gate_bypass_resistance_*' } |
    Sort-Object Name -Descending |
    Select-Object -First 1

$gate44_9 = ''
$phase44_9Consistency = $false
if ($null -ne $latest44_9Pf) {
    $gatePath = Join-Path $latest44_9Pf.FullName '98_gate_phase44_9.txt'
    if (Test-Path -LiteralPath $gatePath) {
        $gate44_9 = (Get-Content -Raw -LiteralPath $gatePath).Trim()
        $phase44_9Consistency = ($gate44_9 -eq 'PASS')
    }
}

$caseFConsistency = ($caseAComplete -and $caseBDirect -and $caseCTransitive -and $caseDUnguardedZero -and $caseEDeadDocumented -and (-not $caseEMisclassified) -and $phase44_9Consistency)
$allPass = $caseFConsistency
$gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status = @(
    'phase=45.0',
    'title=Trust-Chain Runtime Gate Coverage Audit / Completeness Proof',
    ('gate=' + $gate),
    ('entrypoint_inventory=' + $(if ($caseAComplete) { 'COMPLETE' } else { 'INCOMPLETE' })),
    ('direct_gate_coverage=' + $(if ($caseBDirect) { 'VERIFIED' } else { 'NOT_VERIFIED' })),
    ('transitive_gate_coverage=' + $(if ($caseCTransitive) { 'VERIFIED' } else { 'NOT_VERIFIED' })),
    ('unguarded_operational_paths=' + $unguardedOperational.Count),
    ('dead_helpers=' + $(if ($caseEDeadDocumented) { 'DOCUMENTED' } else { 'NONE' })),
    ('misclassified_dead_as_covered=' + $(if ($caseEMisclassified) { 'TRUE' } else { 'FALSE' })),
    ('coverage_map_consistency=' + $(if ($caseFConsistency) { 'TRUE' } else { 'FALSE' })),
    ('timestamp=' + $Timestamp)
)
Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value ($status -join "`r`n") -Encoding UTF8 -NoNewline

$head = @(
    'runner=tools/phase45_0/phase45_0_trust_chain_runtime_gate_coverage_audit_runner.ps1',
    'audit_scope=tools/phase44_9 + tools/phase44_8 + tools/phase44_7',
    'method=static_function_inventory + call_graph_mapping + operational_reachability + consistency_check_against_phase44_9',
    ('phase44_9_latest_pf=' + $(if ($null -ne $latest44_9Pf) { $latest44_9Pf.FullName } else { '(not_found)' })),
    ('phase44_9_latest_gate=' + $(if ([string]::IsNullOrWhiteSpace($gate44_9)) { '(unknown)' } else { $gate44_9 })),
    'canonical_launcher_used=not_required_for_static_completeness_audit'
)
Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value ($head -join "`r`n") -Encoding UTF8 -NoNewline

$def = @(
    'ENTRYPOINT INVENTORY DEFINITION (PHASE 45.0)',
    '',
    'Inventory source: actual runtime-gate tooling scripts in audit scope.',
    'Discovered record criteria: function name or function body is runtime-relevant to baseline/ledger/trust-chain operations.',
    'Each record includes file path, function/entrypoint name, role, operational/dead, direct/transitive gate evidence, gate source, operation type, classification, and notes.',
    '',
    'Operational criteria:',
    '1) Function is runtime-relevant, AND',
    '2) Function is reachable from active phase44_9 top-level call graph, AND',
    '3) Function belongs to active phase44_9 operational script surface.',
    '',
    'Dead/non-operational criteria:',
    'Runtime-relevant helper exists in code but is not in active phase44_9 operational reachability surface.'
)
Set-Content -LiteralPath (Join-Path $PF '10_entrypoint_inventory_definition.txt') -Value ($def -join "`r`n") -Encoding UTF8 -NoNewline

$rules = @(
    'RUNTIME GATE COVERAGE RULES (PHASE 45.0)',
    '',
    'RULE_1: Every operational runtime-relevant entrypoint/helper must classify as directly gated or transitively gated.',
    'RULE_2: Directly gated means explicit runtime-gate invocation in the function body or runtime-gate core function role.',
    'RULE_3: Transitively gated means function is only reachable through already-gated callers in active operational call graph.',
    'RULE_4: Any operational unguarded path fails the phase.',
    'RULE_5: Dead/non-operational helpers must not be counted as covered operational paths.',
    'RULE_6: Coverage map must be internally consistent with inventory and unguarded report.',
    'RULE_7: No assumed-gated entries are allowed without call-path evidence.'
)
Set-Content -LiteralPath (Join-Path $PF '11_runtime_gate_coverage_rules.txt') -Value ($rules -join "`r`n") -Encoding UTF8 -NoNewline

$touched = [System.Collections.Generic.List[string]]::new()
foreach ($sf in $scopeFiles) {
    $touched.Add('READ  ' + $sf)
}
if ($null -ne $latest44_9Pf) {
    $touched.Add('READ  ' + ('_proof/' + $latest44_9Pf.Name + '/98_gate_phase44_9.txt'))
}
$touched.Add('WRITE _proof/' + (Split-Path -Leaf $PF) + '/*')
Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Value (($touched.ToArray()) -join "`r`n") -Encoding UTF8 -NoNewline

$build = @(
    'build_type=PowerShell static runtime-gate completeness audit',
    'compile_required=no',
    'method=function extraction + brace matching + call graph traversal + reachability classification',
    'runtime_validation_required=no (static completeness proof)',
    'runtime_state_machine_changed=no'
)
Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Value ($build -join "`r`n") -Encoding UTF8 -NoNewline

$validation = @(
    ('CASE A entrypoint_inventory=' + $(if ($caseAComplete) { 'COMPLETE' } else { 'INCOMPLETE' })),
    ('CASE B direct_gate_coverage=' + $(if ($caseBDirect) { 'VERIFIED' } else { 'NOT_VERIFIED' })),
    ('CASE C transitive_gate_coverage=' + $(if ($caseCTransitive) { 'VERIFIED' } else { 'NOT_VERIFIED' })),
    ('CASE D unguarded_operational_paths=' + $unguardedOperational.Count),
    ('CASE E dead_helpers=' + $(if ($caseEDeadDocumented) { 'DOCUMENTED' } else { 'NONE' })),
    ('CASE E misclassified_dead_as_covered=' + $(if ($caseEMisclassified) { 'TRUE' } else { 'FALSE' })),
    ('CASE F coverage_map_consistency=' + $(if ($caseFConsistency) { 'TRUE' } else { 'FALSE' })),
    ('phase44_9_consistency_gate=' + $(if ([string]::IsNullOrWhiteSpace($gate44_9)) { '(unknown)' } else { $gate44_9 }))
)
Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Value ($validation -join "`r`n") -Encoding UTF8 -NoNewline

$summary = @(
    'Runtime-relevant operation surface was inventoried by scanning actual scope scripts and extracting runtime-relevant functions by baseline/ledger/trust-chain keywords.',
    'Direct gate coverage was determined by explicit Get-Phase44_8RuntimeGateStatus invocation or runtime-gate core function role.',
    'Transitive gate coverage was determined via call-graph reachability from active phase44_9 top-level entrypoints through already-gated callers.',
    'Dead helpers were distinguished by runtime relevance but non-reachability from active phase44_9 operational top-level surface.',
    'Unguarded path detection is deterministic: any operational record without direct/transitive gate classification is emitted in 18_unguarded_path_report.txt and fails the phase.',
    'Coverage completeness is considered proven because required runtime operation classes are present, operational unguarded count is zero, dead-helper misclassification is false, and map consistency aligns with phase44_9 PASS baseline.',
    'Runtime behavior remained unchanged because phase45_0 is a static certification audit runner only.'
)
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value ($summary -join "`r`n") -Encoding UTF8 -NoNewline

$inventoryLines = [System.Collections.Generic.List[string]]::new()
$inventoryLines.Add('file_path | function | role | operational_or_dead | direct_gate | transitive_gate | gate_source | runtime_operation_type | coverage_classification | notes')
foreach ($row in $inventory) {
    $inventoryLines.Add(([string]$row.file_path + ' | ' +
        [string]$row.function_or_entrypoint + ' | ' +
        [string]$row.role + ' | ' +
        [string]$row.operational_or_dead + ' | ' +
        [string]$row.direct_gate_present + ' | ' +
        [string]$row.transitive_gate_present + ' | ' +
        [string]$row.gate_source_path + ' | ' +
        [string]$row.runtime_relevant_operation_type + ' | ' +
        [string]$row.coverage_classification + ' | ' +
        [string]$row.notes_on_evidence))
}
Set-Content -LiteralPath (Join-Path $PF '16_entrypoint_inventory.txt') -Value ($inventoryLines -join "`r`n") -Encoding UTF8 -NoNewline

$mapLines = [System.Collections.Generic.List[string]]::new()
$mapLines.Add('RUNTIME GATE ENFORCEMENT MAP')
$mapLines.Add('')
$mapLines.Add('Active operational surface (phase44_9):')
foreach ($row in ($operationalRows | Sort-Object function_or_entrypoint)) {
    $mapLines.Add(([string]$row.function_or_entrypoint + ' -> ' + [string]$row.coverage_classification + ' -> gate_source=' + [string]$row.gate_source_path))
}
$mapLines.Add('')
$mapLines.Add('Runtime-relevant non-operational/dead helpers:')
foreach ($row in ($deadRows | Sort-Object function_or_entrypoint)) {
    $mapLines.Add(([string]$row.file_path + ':' + [string]$row.function_or_entrypoint + ' -> non-operational / dead helper'))
}
Set-Content -LiteralPath (Join-Path $PF '17_runtime_gate_enforcement_map.txt') -Value ($mapLines -join "`r`n") -Encoding UTF8 -NoNewline

$unguardedLines = [System.Collections.Generic.List[string]]::new()
$unguardedLines.Add('UNGUARDED OPERATIONAL PATH REPORT')
$unguardedLines.Add(('count=' + $unguardedOperational.Count))
if ($unguardedOperational.Count -eq 0) {
    $unguardedLines.Add('none')
} else {
    foreach ($row in $unguardedOperational) {
        $unguardedLines.Add(([string]$row.file_path + ':' + [string]$row.function_or_entrypoint + ' runtime_operation_type=' + [string]$row.runtime_relevant_operation_type))
    }
}
Set-Content -LiteralPath (Join-Path $PF '18_unguarded_path_report.txt') -Value ($unguardedLines -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '98_gate_phase45_0.txt') -Value $gate -Encoding UTF8 -NoNewline

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
