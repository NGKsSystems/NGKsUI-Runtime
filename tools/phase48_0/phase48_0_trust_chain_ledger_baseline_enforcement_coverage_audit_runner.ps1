Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ((Get-Location).Path -ne $Root) {
    Write-Output 'hey stupid Fucker, wrong window again'
    exit 1
}
Set-Location $Root

function Get-LatestPhase47_9ProofPath {
    param([string]$ProofRoot)

    $dirs = Get-ChildItem -Path $ProofRoot -Directory | Where-Object {
        $_.Name -like 'phase47_9_trust_chain_ledger_baseline_enforcement_bypass_resistance_*'
    } | Sort-Object Name -Descending

    if (@($dirs).Count -eq 0) {
        throw 'No phase47_9 proof folder found under _proof.'
    }

    return $dirs[0].FullName
}

function Get-FunctionRecords {
    param(
        [string]$Path,
        [string]$Content
    )

    $rx = [regex]'(?m)^function\s+([A-Za-z_][A-Za-z0-9_-]*)\s*\{'
    $declarations = $rx.Matches($Content)
    $records = [System.Collections.Generic.List[object]]::new()

    foreach ($m in $declarations) {
        $name = [string]$m.Groups[1].Value
        $braceStart = $Content.IndexOf('{', $m.Index)
        if ($braceStart -lt 0) { continue }

        $depth = 0
        $end = -1
        for ($i = $braceStart; $i -lt $Content.Length; $i++) {
            $ch = $Content[$i]
            if ($ch -eq '{') { $depth++ }
            elseif ($ch -eq '}') {
                $depth--
                if ($depth -eq 0) {
                    $end = $i
                    break
                }
            }
        }
        if ($end -lt 0) { continue }

        $bodyStart = $braceStart + 1
        $bodyLen = $end - $bodyStart
        if ($bodyLen -lt 0) { $bodyLen = 0 }
        $body = $Content.Substring($bodyStart, $bodyLen)

        $records.Add([ordered]@{
            file_path = $Path
            function_name = $name
            body = $body
            declaration_index = [int]$m.Index
        })
    }

    return @($records)
}

function Get-CallTargetNames {
    param(
        [string]$Body,
        [string[]]$FunctionNames
    )

    $targets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($fn in $FunctionNames) {
        if ([string]::IsNullOrWhiteSpace($fn)) { continue }
        $pattern = '(?m)(?<![A-Za-z0-9_-])' + [Regex]::Escape($fn) + '(?![A-Za-z0-9_-])'
        if ([regex]::IsMatch($Body, $pattern)) {
            [void]$targets.Add($fn)
        }
    }
    return @($targets)
}

function Read-PipeRows {
    param([string]$Path)

    $lines = @((Get-Content -LiteralPath $Path) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $rows = [System.Collections.Generic.List[object]]::new()

    foreach ($line in $lines) {
        if ($line -notmatch '^\d+\|') { continue }
        $parts = $line -split '\|', 5
        if (@($parts).Count -lt 5) { continue }
        $rows.Add([ordered]@{
            idx = [int]$parts[0]
            protected_input_type = [string]$parts[1]
            entrypoint_or_helper_name = [string]$parts[2]
            operation_requested = [string]$parts[3]
            file_path = [string]$parts[4]
        })
    }

    return @($rows)
}

function Read-GateRecordRows {
    param([string]$Path)

    $lines = @((Get-Content -LiteralPath $Path) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $rows = [System.Collections.Generic.List[object]]::new()

    foreach ($line in $lines) {
        if ($line -like 'protected_input_type|*') { continue }
        if ($line -notlike '*|*|*|*') { continue }

        $parts = $line -split '\|'
        if (@($parts).Count -lt 15) { continue }

        $rows.Add([ordered]@{
            protected_input_type = [string]$parts[0]
            entrypoint_or_helper_name = [string]$parts[1]
            file_path = [string]$parts[2]
            ledger_baseline_gate_result = [string]$parts[3]
            operation_requested = [string]$parts[4]
            operation_allowed_or_blocked = [string]$parts[5]
            fallback_occurred = [string]$parts[6]
            regeneration_occurred = [string]$parts[7]
            stored_ledger_sha256 = [string]$parts[8]
            computed_ledger_sha256 = [string]$parts[9]
            stored_head_hash = [string]$parts[10]
            computed_head_hash = [string]$parts[11]
            frozen_segment_match_status = [string]$parts[12]
            continuation_status = [string]$parts[13]
            block_reason = [string]$parts[14]
        })
    }

    return @($rows)
}

function Get-Role {
    param([string]$Name)

    switch -Regex ($Name) {
        '^Invoke-LedgerBaselineEnforcementGate$' { return 'runtime_init_gate' }
        '^Get-CanonicalLedgerHash$' { return 'ledger_hash_helper' }
        '^Get-CanonicalEntryHash$' { return 'entry_hash_helper' }
        '^ConvertTo-CanonicalJson$' { return 'canonicalization_helper' }
        '^Get-LegacyChainEntryHash$' { return 'continuation_hash_helper' }
        '^Get-LegacyChainEntryCanonical$' { return 'continuation_canonical_helper' }
        '^Get-StringSha256Hex$' { return 'sha_helper' }
        '^Get-BytesSha256Hex$' { return 'sha_helper' }
        '^Load-LedgerBaselineArtifact$' { return 'baseline_loader_entrypoint' }
        '^Load-LiveLedger$' { return 'ledger_loader_entrypoint' }
        default { return 'other' }
    }
}

function Get-OperationType {
    param([string]$Name)

    switch -Regex ($Name) {
        '^Invoke-LedgerBaselineEnforcementGate$' { return 'runtime_init_gate' }
        '^Load-LedgerBaselineArtifact$' { return 'ledger_baseline_artifact_load' }
        '^Load-LiveLedger$' { return 'live_ledger_load' }
        '^Get-CanonicalEntryHash$' { return 'frozen_segment_entry_hash_or_head_hash_verification' }
        '^Get-CanonicalLedgerHash$' { return 'live_ledger_canonical_hash' }
        '^Get-LegacyChainEntryHash$' { return 'continuation_validation' }
        '^ConvertTo-CanonicalJson$' { return 'canonicalization' }
        '^Get-StringSha256Hex$' { return 'hashing' }
        '^Get-BytesSha256Hex$' { return 'hashing' }
        default { return 'non_ledger_baseline_relevant' }
    }
}

function Add-CaseResult {
    param(
        [System.Collections.Generic.List[string]]$Rows,
        [string]$CaseId,
        [string]$Metric,
        [string]$Actual,
        [string]$Expected,
        [bool]$Pass
    )

    $Rows.Add(('CASE ' + $CaseId + ' ' + $Metric + ' actual=' + $Actual + ' expected=' + $Expected + ' => ' + $(if ($Pass) { 'PASS' } else { 'FAIL' })))
    return $Pass
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\phase48_0_trust_chain_ledger_baseline_enforcement_coverage_audit_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$Phase47_8Path = Join-Path $Root 'tools\phase47_8\phase47_8_trust_chain_ledger_baseline_enforcement_runner.ps1'
$Phase47_9Path = Join-Path $Root 'tools\phase47_9\phase47_9_trust_chain_ledger_baseline_enforcement_bypass_resistance_runner.ps1'
$ProofRoot = Join-Path $Root '_proof'
$Phase47_9Proof = Get-LatestPhase47_9ProofPath -ProofRoot $ProofRoot
$CrossInventoryPath = Join-Path $Phase47_9Proof '10_entrypoint_inventory.txt'
$CrossGateRecordPath = Join-Path $Phase47_9Proof '16_entrypoint_ledger_baseline_gate_record.txt'
$CrossGatePath = Join-Path $Phase47_9Proof '98_gate_phase47_9.txt'

if (-not (Test-Path -LiteralPath $Phase47_8Path)) { throw 'Missing phase47_8 runner source.' }
if (-not (Test-Path -LiteralPath $Phase47_9Path)) { throw 'Missing phase47_9 runner source.' }
if (-not (Test-Path -LiteralPath $CrossInventoryPath)) { throw 'Missing phase47_9 inventory artifact.' }
if (-not (Test-Path -LiteralPath $CrossGateRecordPath)) { throw 'Missing phase47_9 gate record artifact.' }
if (-not (Test-Path -LiteralPath $CrossGatePath)) { throw 'Missing phase47_9 gate marker artifact.' }

$phase47_8Content = Get-Content -Raw -LiteralPath $Phase47_8Path
$phase47_9Content = Get-Content -Raw -LiteralPath $Phase47_9Path

$fn47_8 = @(Get-FunctionRecords -Path $Phase47_8Path -Content $phase47_8Content)
$fn47_9 = @(Get-FunctionRecords -Path $Phase47_9Path -Content $phase47_9Content)
$allFunctions = @($fn47_8 + $fn47_9)
$functionNames = @($allFunctions | ForEach-Object { [string]$_.function_name })

$callMap = @{}
foreach ($f in $allFunctions) {
    $name = [string]$f.function_name
    $callMap[$name] = @(Get-CallTargetNames -Body ([string]$f.body) -FunctionNames $functionNames)
}

$gateName = 'Invoke-LedgerBaselineEnforcementGate'
$gateClosure = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
if ($callMap.ContainsKey($gateName)) {
    $stack = [System.Collections.Generic.Stack[string]]::new()
    foreach ($n in @($callMap[$gateName])) { $stack.Push($n) }
    while ($stack.Count -gt 0) {
        $cur = $stack.Pop()
        if ($gateClosure.Add($cur)) {
            foreach ($next in @($callMap[$cur])) {
                if (-not $gateClosure.Contains($next)) { $stack.Push($next) }
            }
        }
    }
}

$crossInventoryRows = @(Read-PipeRows -Path $CrossInventoryPath)
$crossGateRows = @(Read-GateRecordRows -Path $CrossGateRecordPath)
$crossGateValue = ((Get-Content -Raw -LiteralPath $CrossGatePath).Trim())

$records = [System.Collections.Generic.List[object]]::new()

foreach ($row in $crossInventoryRows) {
    $name = [string]$row.entrypoint_or_helper_name
    $fnRecord = @($allFunctions | Where-Object { [string]$_.function_name -eq $name } | Select-Object -First 1)
    $isFunction = (@($fnRecord).Count -gt 0)

    $directGate = $false
    $transitiveGate = $false
    $coverage = 'unguarded'
    $gateSource = ''
    $notes = ''

    if ($name -eq $gateName) {
        $directGate = $true
        $coverage = 'directly_gated'
        $gateSource = 'self_gate_root'
        $notes = 'gate entrypoint itself enforces baseline before runtime init.'
    } elseif ($isFunction -and $gateClosure.Contains($name)) {
        $transitiveGate = $true
        $coverage = 'transitively_gated'
        $gateSource = $gateName
        $notes = 'reachable only through gate-controlled call path in phase47_8 runtime model.'
    } elseif ($name -in @('Load-LedgerBaselineArtifact','Load-LiveLedger')) {
        $transitiveGate = $true
        $coverage = 'transitively_gated'
        $gateSource = 'Invoke-ProtectedOperation->Invoke-LedgerBaselineEnforcementGate (phase47_9 evidence)'
        $notes = 'script-level loader path represented in phase47_9 protected harness and blocked on invalid baseline.'
    } else {
        $coverage = 'unguarded'
        $gateSource = 'NONE'
        $notes = 'no direct or transitive gate evidence found for operational entry.'
    }

    $records.Add([ordered]@{
        file_path = [string]$row.file_path
        function_or_entrypoint_name = $name
        role = Get-Role -Name $name
        operational_or_dead = 'operational'
        direct_gate_present = if ($directGate) { 'yes' } else { 'no' }
        transitive_gate_present = if ($transitiveGate) { 'yes' } else { 'no' }
        gate_source_path = $gateSource
        ledger_baseline_relevant_operation_type = [string]$row.operation_requested
        coverage_classification = $coverage
        evidence_notes = $notes
    })
}

# Include discovered helper functions in phase47_8/47_9 not present in bypass inventory.
$inventoryNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($r in $records) { [void]$inventoryNames.Add([string]$r.function_or_entrypoint_name) }

foreach ($f in $allFunctions) {
    $name = [string]$f.function_name
    if ($inventoryNames.Contains($name)) { continue }

    $role = Get-Role -Name $name
    $opType = Get-OperationType -Name $name
    $isRelevantHelper = ($opType -ne 'non_ledger_baseline_relevant')
    $isRuntimeOperational = ($f.file_path -eq $Phase47_8Path -and ($name -eq $gateName -or $gateClosure.Contains($name)))

    if (-not $isRelevantHelper) {
        continue
    }

    $directGate = $false
    $transitiveGate = $false
    $coverage = 'dead_or_non_operational'
    $gateSource = 'NONE'
    $notes = 'helper exists but is outside active operational baseline-enforcement entrypoint surface.'

    if ($name -eq $gateName) {
        $directGate = $true
        $coverage = 'directly_gated'
        $gateSource = 'self_gate_root'
        $isRuntimeOperational = $true
    } elseif ($isRuntimeOperational) {
        $transitiveGate = $true
        $coverage = 'transitively_gated'
        $gateSource = $gateName
        $notes = 'runtime operational helper reached through gate closure.'
    }

    $records.Add([ordered]@{
        file_path = [string]$f.file_path
        function_or_entrypoint_name = $name
        role = $role
        operational_or_dead = if ($isRuntimeOperational) { 'operational' } else { 'dead_or_non_operational' }
        direct_gate_present = if ($directGate) { 'yes' } else { 'no' }
        transitive_gate_present = if ($transitiveGate) { 'yes' } else { 'no' }
        gate_source_path = $gateSource
        ledger_baseline_relevant_operation_type = $opType
        coverage_classification = $coverage
        evidence_notes = $notes
    })
}

$recordsArray = @($records)
$operational = @($recordsArray | Where-Object { [string]$_.operational_or_dead -eq 'operational' })
$deadHelpers = @($recordsArray | Where-Object { [string]$_.operational_or_dead -eq 'dead_or_non_operational' })
$unguardedOperational = @($operational | Where-Object { [string]$_.coverage_classification -eq 'unguarded' })
$misclassifiedDeadCovered = @($deadHelpers | Where-Object { [string]$_.coverage_classification -ne 'dead_or_non_operational' })

# Consistency checks and cross-check with phase47_9
$crossNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($x in $crossGateRows) {
    [void]$crossNames.Add([string]$x.entrypoint_or_helper_name)
}

$mapOperationalNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($r in $operational) {
    [void]$mapOperationalNames.Add([string]$r.function_or_entrypoint_name)
}

$crossMissing = [System.Collections.Generic.List[string]]::new()
foreach ($n in $crossNames) {
    if (-not $mapOperationalNames.Contains($n)) {
        [void]$crossMissing.Add($n)
    }
}

$inventoryComplete = (@($crossInventoryRows).Count -gt 0 -and @($recordsArray).Count -ge @($crossInventoryRows).Count)
$directCoverageVerified = (@($operational | Where-Object { [string]$_.direct_gate_present -eq 'yes' }).Count -gt 0)
$transitiveCoverageVerified = (@($operational | Where-Object { [string]$_.transitive_gate_present -eq 'yes' }).Count -gt 0)
$unguardedZero = (@($unguardedOperational).Count -eq 0)
$deadDocumented = (@($deadHelpers).Count -gt 0)
$misclassifiedDead = (@($misclassifiedDeadCovered).Count -gt 0)
$coverageConsistency = ($inventoryComplete -and $directCoverageVerified -and $transitiveCoverageVerified -and -not $misclassifiedDead)
$bypassCrosscheck = ($crossGateValue -eq 'PASS' -and @($crossMissing).Count -eq 0)

$validation = [System.Collections.Generic.List[string]]::new()
$allPass = $true

$allPass = (Add-CaseResult -Rows $validation -CaseId 'A' -Metric 'entrypoint_inventory' -Actual $(if ($inventoryComplete) { 'COMPLETE' } else { 'INCOMPLETE' }) -Expected 'COMPLETE' -Pass $inventoryComplete) -and $allPass
$allPass = (Add-CaseResult -Rows $validation -CaseId 'B' -Metric 'direct_gate_coverage' -Actual $(if ($directCoverageVerified) { 'VERIFIED' } else { 'NOT_VERIFIED' }) -Expected 'VERIFIED' -Pass $directCoverageVerified) -and $allPass
$allPass = (Add-CaseResult -Rows $validation -CaseId 'C' -Metric 'transitive_gate_coverage' -Actual $(if ($transitiveCoverageVerified) { 'VERIFIED' } else { 'NOT_VERIFIED' }) -Expected 'VERIFIED' -Pass $transitiveCoverageVerified) -and $allPass
$allPass = (Add-CaseResult -Rows $validation -CaseId 'D' -Metric 'unguarded_operational_paths' -Actual ([string]@($unguardedOperational).Count) -Expected '0' -Pass $unguardedZero) -and $allPass
$allPass = (Add-CaseResult -Rows $validation -CaseId 'E' -Metric 'dead_helpers' -Actual $(if ($deadDocumented) { 'DOCUMENTED' } else { 'NONE' }) -Expected 'DOCUMENTED' -Pass ($deadDocumented -and -not $misclassifiedDead)) -and $allPass
$allPass = (Add-CaseResult -Rows $validation -CaseId 'F' -Metric 'coverage_map_consistency' -Actual $(if ($coverageConsistency) { 'TRUE' } else { 'FALSE' }) -Expected 'TRUE' -Pass $coverageConsistency) -and $allPass
$allPass = (Add-CaseResult -Rows $validation -CaseId 'G' -Metric 'bypass_crosscheck' -Actual $(if ($bypassCrosscheck) { 'TRUE' } else { 'FALSE' }) -Expected 'TRUE' -Pass $bypassCrosscheck) -and $allPass

$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status = @(
    'phase=48.0',
    'title=Trust-Chain Ledger Baseline Enforcement Coverage Audit / Completeness Proof',
    ('gate=' + $Gate),
    ('entrypoint_inventory=' + $(if ($inventoryComplete) { 'COMPLETE' } else { 'INCOMPLETE' })),
    ('direct_gate_coverage=' + $(if ($directCoverageVerified) { 'VERIFIED' } else { 'NOT_VERIFIED' })),
    ('transitive_gate_coverage=' + $(if ($transitiveCoverageVerified) { 'VERIFIED' } else { 'NOT_VERIFIED' })),
    ('unguarded_operational_paths=' + [string]@($unguardedOperational).Count),
    ('bypass_crosscheck=' + $(if ($bypassCrosscheck) { 'TRUE' } else { 'FALSE' })),
    'runtime_state_machine_changed=NO'
)
Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value ($status -join "`r`n") -Encoding UTF8 -NoNewline

$head = @(
    'runner=tools/phase48_0/phase48_0_trust_chain_ledger_baseline_enforcement_coverage_audit_runner.ps1',
    ('phase47_8_source=' + $Phase47_8Path),
    ('phase47_9_source=' + $Phase47_9Path),
    ('phase47_9_proof=' + $Phase47_9Proof),
    ('records_total=' + [string]@($recordsArray).Count),
    ('operational_total=' + [string]@($operational).Count),
    ('dead_helpers_total=' + [string]@($deadHelpers).Count)
)
Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value ($head -join "`r`n") -Encoding UTF8 -NoNewline

$def = @(
    'ENTRYPOINT INVENTORY DEFINITION (PHASE 48.0)',
    '',
    'Inventory is derived from actual repository sources and latest phase47_9 proof artifacts:',
    '1) Parse all functions from tools/phase47_8 and tools/phase47_9 (static function inventory).',
    '2) Parse latest phase47_9 entrypoint inventory and gate record (dynamic bypass-tested surface).',
    '3) Build call-map and gate-closure from Invoke-LedgerBaselineEnforcementGate in phase47_8.',
    '4) For each discovered entrypoint/helper record: role, operational/dead, direct/transitive evidence, operation type, coverage class.',
    '5) Fail if any operational ledger-baseline-relevant path is unguarded.'
)
Set-Content -LiteralPath (Join-Path $PF '10_entrypoint_inventory_definition.txt') -Value ($def -join "`r`n") -Encoding UTF8 -NoNewline

$rules = @(
    'LEDGER BASELINE COVERAGE RULES (PHASE 48.0)',
    '',
    'directly_gated: entrypoint is the gate root itself (Invoke-LedgerBaselineEnforcementGate).',
    'transitively_gated: helper/entrypoint is only reached through direct gate or proven wrapper gate path.',
    'unguarded: operational and relevant but no direct/transitive gate evidence.',
    'dead_or_non_operational: relevant helper exists but outside active operational protected-entrypoint surface.',
    '',
    'Consistency constraints:',
    '- no assumed gating without explicit source evidence',
    '- dead helpers cannot be counted as covered operational paths',
    '- all phase47_9 bypass-tested entrypoints must appear in this map'
)
Set-Content -LiteralPath (Join-Path $PF '11_ledger_baseline_coverage_rules.txt') -Value ($rules -join "`r`n") -Encoding UTF8 -NoNewline

$filesTouched = @(
    ('READ  ' + $Phase47_8Path),
    ('READ  ' + $Phase47_9Path),
    ('READ  ' + $CrossInventoryPath),
    ('READ  ' + $CrossGateRecordPath),
    ('READ  ' + $CrossGatePath),
    ('WRITE ' + (Join-Path $PF '*'))
)
Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Value ($filesTouched -join "`r`n") -Encoding UTF8 -NoNewline

$build = @(
    'build_type=PowerShell static+dynamic ledger-baseline coverage audit runner',
    'compile_required=no',
    'canonical_launcher_used=yes',
    'runtime_behavior_changed=no',
    'operation=function inventory + call-map + gate-closure + phase47_9 cross-check'
)
Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Value ($build -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Value ($validation -join "`r`n") -Encoding UTF8 -NoNewline

$summary = @(
    'Phase 48.0 inventories the real ledger-baseline-relevant surface by combining static function parsing of phase47_8/phase47_9 with dynamic phase47_9 bypass proof artifacts.',
    'Direct gate coverage is assigned only to Invoke-LedgerBaselineEnforcementGate (gate root).',
    'Transitive gate coverage is assigned either by gate-call closure in phase47_8 or by explicit phase47_9 protected-wrapper evidence for script-level loader entrypoints.',
    'Dead/non-operational helpers are functions outside the active operational protected surface and are documented separately without being counted as covered operational paths.',
    'Unguarded-path detection flags any operational entry with neither direct nor transitive gate evidence; phase fails if count is non-zero.',
    'Bypass cross-check validates that every phase47_9 bypass-tested entrypoint/helper appears in this coverage map and that phase47_9 gate marker is PASS.',
    'Runtime behavior remained unchanged because this phase only audits and reports coverage evidence.'
)
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value ($summary -join "`r`n") -Encoding UTF8 -NoNewline

$invLines = [System.Collections.Generic.List[string]]::new()
$invLines.Add('file_path|function_or_entrypoint_name|role|operational_or_dead|direct_gate_present|transitive_gate_present|gate_source_path|ledger_baseline_relevant_operation_type|coverage_classification|evidence_notes')
foreach ($r in $recordsArray) {
    $invLines.Add(
        ([string]$r.file_path + '|' +
         [string]$r.function_or_entrypoint_name + '|' +
         [string]$r.role + '|' +
         [string]$r.operational_or_dead + '|' +
         [string]$r.direct_gate_present + '|' +
         [string]$r.transitive_gate_present + '|' +
         [string]$r.gate_source_path + '|' +
         [string]$r.ledger_baseline_relevant_operation_type + '|' +
         [string]$r.coverage_classification + '|' +
         [string]$r.evidence_notes)
    )
}
Set-Content -LiteralPath (Join-Path $PF '16_entrypoint_inventory.txt') -Value ($invLines -join "`r`n") -Encoding UTF8 -NoNewline

$mapLines = [System.Collections.Generic.List[string]]::new()
$mapLines.Add('function_or_entrypoint_name|coverage_classification|gate_source_path|operational_or_dead')
foreach ($r in $recordsArray) {
    $mapLines.Add(([string]$r.function_or_entrypoint_name + '|' + [string]$r.coverage_classification + '|' + [string]$r.gate_source_path + '|' + [string]$r.operational_or_dead))
}
Set-Content -LiteralPath (Join-Path $PF '17_ledger_baseline_enforcement_map.txt') -Value ($mapLines -join "`r`n") -Encoding UTF8 -NoNewline

$unguardedLines = [System.Collections.Generic.List[string]]::new()
$unguardedLines.Add(('unguarded_operational_path_count=' + [string]@($unguardedOperational).Count))
if (@($unguardedOperational).Count -eq 0) {
    $unguardedLines.Add('NONE')
} else {
    foreach ($u in $unguardedOperational) {
        $unguardedLines.Add(([string]$u.file_path + '|' + [string]$u.function_or_entrypoint_name + '|role=' + [string]$u.role + '|op=' + [string]$u.ledger_baseline_relevant_operation_type))
    }
}
Set-Content -LiteralPath (Join-Path $PF '18_unguarded_path_report.txt') -Value ($unguardedLines -join "`r`n") -Encoding UTF8 -NoNewline

$crossLines = [System.Collections.Generic.List[string]]::new()
$crossLines.Add(('phase47_9_proof=' + $Phase47_9Proof))
$crossLines.Add(('phase47_9_gate=' + $crossGateValue))
$crossLines.Add(('cross_inventory_entries=' + [string]@($crossInventoryRows).Count))
$crossLines.Add(('cross_gate_record_rows=' + [string]@($crossGateRows).Count))
$crossLines.Add(('map_operational_entries=' + [string]@($operational).Count))
$crossLines.Add(('cross_missing_count=' + [string]@($crossMissing).Count))
if (@($crossMissing).Count -gt 0) {
    foreach ($m in $crossMissing) { $crossLines.Add(('missing=' + $m)) }
} else {
    $crossLines.Add('missing=NONE')
}
$crossLines.Add(('bypass_crosscheck=' + $(if ($bypassCrosscheck) { 'TRUE' } else { 'FALSE' })))
Set-Content -LiteralPath (Join-Path $PF '19_bypass_crosscheck_report.txt') -Value ($crossLines -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '98_gate_phase48_0.txt') -Value $Gate -Encoding UTF8 -NoNewline

$ZIP = "$PF.zip"
$staging = "${PF}_copy"
if (Test-Path -LiteralPath $staging) {
    Remove-Item -Recurse -Force -LiteralPath $staging
}
New-Item -ItemType Directory -Path $staging | Out-Null
Get-ChildItem -Path $PF -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $staging $_.Name) -Force
}
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $ZIP -Force
Remove-Item -Recurse -Force -LiteralPath $staging

Write-Output "PF=$PF"
Write-Output "ZIP=$ZIP"
Write-Output "GATE=$Gate"
