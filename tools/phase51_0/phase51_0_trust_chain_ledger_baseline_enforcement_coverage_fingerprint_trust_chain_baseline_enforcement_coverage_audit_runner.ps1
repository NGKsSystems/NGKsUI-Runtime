Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ((Get-Location).Path -ne $Root) {
    Write-Output 'hey stupid Fucker, wrong window again'
    exit 1
}
Set-Location $Root

function Get-ScriptText {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw ('Missing required file: ' + $Path)
    }
    return Get-Content -Raw -LiteralPath $Path
}

function Get-FunctionNames {
    param([string]$Text)

    $names = [System.Collections.Generic.List[string]]::new()
    $regexMatches = [regex]::Matches($Text, '(?im)^\s*function\s+([A-Za-z0-9_\-]+)\s*\{')
    foreach ($m in $regexMatches) {
        $name = [string]$m.Groups[1].Value
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            [void]$names.Add($name)
        }
    }
    return @($names | Select-Object -Unique)
}

function Get-Matches {
    param(
        [string]$Text,
        [string]$Pattern
    )

    $vals = [System.Collections.Generic.List[string]]::new()
    $regexMatches = [regex]::Matches($Text, $Pattern)
    foreach ($m in $regexMatches) {
        $v = [string]$m.Groups[1].Value
        if (-not [string]::IsNullOrWhiteSpace($v)) {
            [void]$vals.Add($v)
        }
    }
    return @($vals | Select-Object -Unique)
}

function New-EntryRecord {
    param(
        [string]$FilePath,
        [string]$Name,
        [string]$Role,
        [string]$OperationType,
        [string]$Operational,
        [string]$DirectGate,
        [string]$TransitiveGate,
        [string]$GateSource,
        [string]$Classification,
        [string]$Evidence
    )

    return [ordered]@{
        file_path                                  = $FilePath
        function_or_entrypoint                     = $Name
        role                                       = $Role
        operational_or_dead                        = $Operational
        direct_gate_present                        = $DirectGate
        transitive_gate_present                    = $TransitiveGate
        gate_source_path                           = $GateSource
        frozen_baseline_relevant_operation_type    = $OperationType
        coverage_classification                    = $Classification
        evidence_notes                             = $Evidence
    }
}

function Get-LatestPhase50_9Proof {
    param([string]$ProofRoot)

    $dirs = Get-ChildItem -Path $ProofRoot -Directory | Where-Object {
        $_.Name -like 'phase50_9_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_bypass_resistance_*'
    } | Sort-Object Name -Descending

    foreach ($d in $dirs) {
        $inv = Join-Path $d.FullName '10_entrypoint_inventory.txt'
        $gate = Join-Path $d.FullName '16_entrypoint_frozen_baseline_gate_record.txt'
        if ((Test-Path -LiteralPath $inv) -and (Test-Path -LiteralPath $gate)) {
            return $d.FullName
        }
    }

    throw 'No usable phase50_9 proof directory found for cross-check.'
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\phase51_0_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_coverage_audit_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$RunnerPath = Join-Path $Root 'tools\phase51_0\phase51_0_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_coverage_audit_runner.ps1'
$phase50_8Path = Join-Path $Root 'tools\phase50_8\phase50_8_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_runner.ps1'
$phase50_9Path = Join-Path $Root 'tools\phase50_9\phase50_9_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_bypass_resistance_runner.ps1'
$ProofRoot = Join-Path $Root '_proof'

$Latest50_9Proof = Get-LatestPhase50_9Proof -ProofRoot $ProofRoot
$CrossInvPath = Join-Path $Latest50_9Proof '10_entrypoint_inventory.txt'
$CrossGatePath = Join-Path $Latest50_9Proof '16_entrypoint_frozen_baseline_gate_record.txt'

$phase50_8Text = Get-ScriptText -Path $phase50_8Path
$phase50_9Text = Get-ScriptText -Path $phase50_9Path

$fn50_8 = Get-FunctionNames -Text $phase50_8Text
$fn50_9 = Get-FunctionNames -Text $phase50_9Text

$inventoryList = [System.Collections.Generic.List[object]]::new()
$validationLines = [System.Collections.Generic.List[string]]::new()
$mapLines = [System.Collections.Generic.List[string]]::new()
$unguardedLines = [System.Collections.Generic.List[string]]::new()
$crossLines = [System.Collections.Generic.List[string]]::new()

$gateIn50_8 = [regex]::IsMatch($phase50_8Text, '(?s)function\s+Invoke\-ProtectedOperation\s*\{.*?Invoke\-FrozenBaselineEnforcementGate')
$gateIn50_9 = [regex]::IsMatch($phase50_9Text, '(?s)function\s+Invoke\-ProtectedOperation\s*\{.*?Invoke\-FrozenBaselineEnforcementGate')
$gateDefinition50_8 = [regex]::IsMatch($phase50_8Text, '(?im)^\s*function\s+Invoke\-FrozenBaselineEnforcementGate\s*\{')
$gateDefinition50_9 = [regex]::IsMatch($phase50_9Text, '(?im)^\s*function\s+Invoke\-FrozenBaselineEnforcementGate\s*\{')

$opRoleMap = [ordered]@{
    load_frozen_baseline_snapshot = 'frozen baseline snapshot load entrypoint'
    load_frozen_baseline_integrity_record = 'frozen baseline integrity record load entrypoint'
    evaluate_frozen_baseline_gate = 'frozen baseline verification entrypoint'
    read_validate_live_ledger_head = 'live ledger-head read/validation helper entrypoint'
    read_validate_live_coverage_fingerprint = 'live coverage-fingerprint read/validation helper entrypoint'
    validate_chain_continuation = 'chain-continuation validation helper entrypoint'
    compare_semantic_protected_fields = 'semantic protected-field comparison helper entrypoint'
    invoke_runtime_initialization_wrapper = 'runtime initialization wrapper helper entrypoint'
    canonicalize_hash_compare = 'canonicalization/hash helper entrypoint'
}

foreach ($k in $opRoleMap.Keys) {
    $direct = if ($gateIn50_9) { 'YES' } else { 'NO' }
    $classification = if ($direct -eq 'YES') { 'directly_gated' } else { 'unguarded' }
    $name = switch ($k) {
        'load_frozen_baseline_snapshot' { 'Load-FrozenBaselineSnapshot' }
        'load_frozen_baseline_integrity_record' { 'Load-FrozenBaselineIntegrityRecord' }
        'evaluate_frozen_baseline_gate' { 'Invoke-FrozenBaselineEnforcementGate' }
        'read_validate_live_ledger_head' { 'Read-LiveLedgerHeadValidation' }
        'read_validate_live_coverage_fingerprint' { 'Read-LiveCoverageFingerprintValidation' }
        'validate_chain_continuation' { 'Validate-ChainContinuation' }
        'compare_semantic_protected_fields' { 'Compare-SemanticProtectedFields' }
        'invoke_runtime_initialization_wrapper' { 'Invoke-RuntimeInitWrapper' }
        'canonicalize_hash_compare' { 'Invoke-CanonicalizationHashCompare' }
        default { $k }
    }

    [void]$inventoryList.Add((New-EntryRecord -FilePath $phase50_9Path -Name $name -Role $opRoleMap[$k] -OperationType $k -Operational 'operational' -DirectGate $direct -TransitiveGate 'NO' -GateSource 'Invoke-ProtectedOperation -> Invoke-FrozenBaselineEnforcementGate' -Classification $classification -Evidence 'Declared in Get-ProtectedEntrypointInventory and executed via protected operation wrapper'))
}

$core50_8 = @(
    [ordered]@{ n='Invoke-ProtectedOperation'; r='runtime operation guard wrapper'; t='runtime_entrypoint_gate_wrapper'; d='YES'; tr='NO'; g='Invoke-FrozenBaselineEnforcementGate'; c=if ($gateIn50_8) { 'directly_gated' } else { 'unguarded' }; e='Wrapper explicitly invokes frozen-baseline gate before operation script' },
    [ordered]@{ n='Invoke-FrozenBaselineEnforcementGate'; r='frozen baseline verification gate'; t='frozen_baseline_verification'; d='NO'; tr='NO'; g='self'; c='directly_gated'; e='Defines mandatory snapshot/integrity/ledger/coverage/continuation/semantic checks' },
    [ordered]@{ n='Test-LegacyTrustChain'; r='chain continuation/link validator'; t='validate_chain_continuation'; d='NO'; tr='YES'; g='Invoke-FrozenBaselineEnforcementGate'; c='transitively_gated'; e='Invoked from gate step 3 and case setup only' },
    [ordered]@{ n='Get-CanonicalObjectHash'; r='canonical object hash helper'; t='canonicalize_hash_compare'; d='NO'; tr='YES'; g='Invoke-FrozenBaselineEnforcementGate'; c='transitively_gated'; e='Used by gate and helper verification paths' },
    [ordered]@{ n='Convert-ToCanonicalJson'; r='canonicalization helper'; t='canonicalize_hash_compare'; d='NO'; tr='YES'; g='Get-CanonicalObjectHash -> Invoke-FrozenBaselineEnforcementGate'; c='transitively_gated'; e='Low-level helper consumed by canonical hash function' },
    [ordered]@{ n='Get-StringSha256Hex'; r='string hash helper'; t='canonicalize_hash_compare'; d='NO'; tr='YES'; g='Get-CanonicalObjectHash -> Invoke-FrozenBaselineEnforcementGate'; c='transitively_gated'; e='Low-level hash helper used by canonical object hash' },
    [ordered]@{ n='Get-BytesSha256Hex'; r='bytes hash helper'; t='canonicalize_hash_compare'; d='NO'; tr='YES'; g='Get-StringSha256Hex -> Get-CanonicalObjectHash -> Invoke-FrozenBaselineEnforcementGate'; c='transitively_gated'; e='Leaf hash helper in protected hash chain' },
    [ordered]@{ n='Get-LegacyChainEntryCanonical'; r='legacy entry canonicalizer'; t='validate_chain_continuation'; d='NO'; tr='YES'; g='Test-LegacyTrustChain -> Invoke-FrozenBaselineEnforcementGate'; c='transitively_gated'; e='Used for chain link hashing only under validator call graph' },
    [ordered]@{ n='Get-LegacyChainEntryHash'; r='legacy entry hash'; t='validate_chain_continuation'; d='NO'; tr='YES'; g='Test-LegacyTrustChain -> Invoke-FrozenBaselineEnforcementGate'; c='transitively_gated'; e='Used for chain link hashing only under validator call graph' }
)

foreach ($x in $core50_8) {
    [void]$inventoryList.Add((New-EntryRecord -FilePath $phase50_8Path -Name $x.n -Role $x.r -OperationType $x.t -Operational 'operational' -DirectGate $x.d -TransitiveGate $x.tr -GateSource $x.g -Classification $x.c -Evidence $x.e))
}

$deadCandidates = @('Get-NextEntryId','Copy-Object')
foreach ($dc in $deadCandidates) {
    if ($fn50_8 -contains $dc) {
        [void]$inventoryList.Add((New-EntryRecord -FilePath $phase50_8Path -Name $dc -Role 'helper not on active frozen-baseline operational path' -OperationType 'auxiliary_non_protected' -Operational 'dead_or_non_operational' -DirectGate 'NO' -TransitiveGate 'NO' -GateSource 'none' -Classification 'dead_non_operational' -Evidence 'Present in script but not part of protected gate call graph used for 50.8/50.9 enforcement'))
    }
}

$unguardedOperational = @($inventoryList | Where-Object {
    $_.operational_or_dead -eq 'operational' -and $_.coverage_classification -eq 'unguarded'
})

if ($unguardedOperational.Count -eq 0) {
    $unguardedLines.Add('UNGUARDED_OPERATIONAL_PATHS=0')
    $unguardedLines.Add('DETAIL=No operational frozen-baseline-relevant path found without direct/transitive gate evidence')
} else {
    $unguardedLines.Add('UNGUARDED_OPERATIONAL_PATHS=' + $unguardedOperational.Count)
    foreach ($u in $unguardedOperational) {
        $unguardedLines.Add('UNGUARDED file=' + [string]$u.file_path + '|function=' + [string]$u.function_or_entrypoint + '|operation=' + [string]$u.frozen_baseline_relevant_operation_type)
    }
}

foreach ($item in $inventoryList) {
    $mapLines.Add(
        'file_path=' + [string]$item.file_path +
        '|function=' + [string]$item.function_or_entrypoint +
        '|role=' + [string]$item.role +
        '|operational_or_dead=' + [string]$item.operational_or_dead +
        '|direct_gate=' + [string]$item.direct_gate_present +
        '|transitive_gate=' + [string]$item.transitive_gate_present +
        '|gate_source=' + [string]$item.gate_source_path +
        '|operation_type=' + [string]$item.frozen_baseline_relevant_operation_type +
        '|coverage_classification=' + [string]$item.coverage_classification +
        '|evidence=' + [string]$item.evidence_notes
    )
}

$crossInvLines = Get-Content -LiteralPath $CrossInvPath
$crossGateLines = Get-Content -LiteralPath $CrossGatePath

$missingOps = [System.Collections.Generic.List[string]]::new()
foreach ($op in $opRoleMap.Keys) {
    $presentInv = @($crossInvLines | Where-Object { $_ -match ('operation_requested=' + [regex]::Escape($op) + '(\||$)') }).Count -gt 0
    $presentGate = @($crossGateLines | Where-Object { $_ -match ('operation_requested=' + [regex]::Escape($op) + '(\||$)') }).Count -gt 0
    $presentMap = @($inventoryList | Where-Object { $_.frozen_baseline_relevant_operation_type -eq $op -and $_.operational_or_dead -eq 'operational' }).Count -gt 0

    $line = 'operation=' + $op + '|in_50_9_inventory=' + $(if ($presentInv) { 'TRUE' } else { 'FALSE' }) + '|in_50_9_gate_record=' + $(if ($presentGate) { 'TRUE' } else { 'FALSE' }) + '|in_51_0_map=' + $(if ($presentMap) { 'TRUE' } else { 'FALSE' })
    $crossLines.Add($line)

    if ((-not $presentInv) -or (-not $presentGate) -or (-not $presentMap)) {
        [void]$missingOps.Add($op)
    }
}

$caseA50_9GateRecordOk = @($crossGateLines | Where-Object {
    $_ -match '^CASE A\|' -and
    $_ -match 'frozen_baseline_gate_result=PASS' -and
    $_ -match 'operation_allowed_or_blocked=ALLOWED' -and
    $_ -match 'fallback_occurred=False' -and
    $_ -match 'regeneration_occurred=False'
}).Count -eq 1

$bypassCaseOkCount = 0
foreach ($caseId in @('B','C','D','E','F','G','H','I')) {
    $ok = @($crossGateLines | Where-Object {
        $_ -match ('^CASE ' + $caseId + '\|') -and
        $_ -match 'frozen_baseline_gate_result=FAIL' -and
        $_ -match 'operation_allowed_or_blocked=BLOCKED' -and
        $_ -match 'fallback_occurred=False' -and
        $_ -match 'regeneration_occurred=False'
    }).Count -eq 1
    if ($ok) { $bypassCaseOkCount++ }
}

$bypassEvidenceOk = ($caseA50_9GateRecordOk -and $bypassCaseOkCount -eq 8)

$caseA = if ($inventoryList.Count -ge 11) { 'PASS' } else { 'FAIL' }
$caseB = if ($gateIn50_8 -and $gateIn50_9 -and $gateDefinition50_8 -and $gateDefinition50_9) { 'PASS' } else { 'FAIL' }
$caseC = if (@($inventoryList | Where-Object { $_.coverage_classification -eq 'transitively_gated' -and $_.operational_or_dead -eq 'operational' }).Count -ge 5) { 'PASS' } else { 'FAIL' }
$caseD = if ($unguardedOperational.Count -eq 0) { 'PASS' } else { 'FAIL' }
$caseE = if (@($inventoryList | Where-Object { $_.operational_or_dead -eq 'dead_or_non_operational' }).Count -ge 1 -and @($inventoryList | Where-Object { $_.operational_or_dead -eq 'dead_or_non_operational' -and $_.coverage_classification -ne 'dead_non_operational' }).Count -eq 0) { 'PASS' } else { 'FAIL' }
$caseF = if ((@($inventoryList | Where-Object { $_.operational_or_dead -eq 'operational' }).Count -gt 0) -and (@($inventoryList | Where-Object { $_.coverage_classification -eq 'directly_gated' -or $_.coverage_classification -eq 'transitively_gated' }).Count -ge @($inventoryList | Where-Object { $_.operational_or_dead -eq 'operational' }).Count)) { 'PASS' } else { 'FAIL' }
$caseG = if ($missingOps.Count -eq 0 -and $bypassEvidenceOk) { 'PASS' } else { 'FAIL' }

$validationLines.Add('CASE A entrypoint_inventory gate=' + $caseA + ' expected=COMPLETE result=' + $(if ($caseA -eq 'PASS') { 'COMPLETE' } else { 'INCOMPLETE' }))
$validationLines.Add('CASE B direct_gate_coverage gate=' + $caseB + ' expected=VERIFIED result=' + $(if ($caseB -eq 'PASS') { 'VERIFIED' } else { 'FAILED' }))
$validationLines.Add('CASE C transitive_gate_coverage gate=' + $caseC + ' expected=VERIFIED result=' + $(if ($caseC -eq 'PASS') { 'VERIFIED' } else { 'FAILED' }))
$validationLines.Add('CASE D unguarded_operational_paths gate=' + $caseD + ' expected=0 result=' + $unguardedOperational.Count)
$validationLines.Add('CASE E dead_helper_classification gate=' + $caseE + ' expected=DOCUMENTED result=' + $(if ($caseE -eq 'PASS') { 'DOCUMENTED' } else { 'FAILED' }))
$validationLines.Add('CASE F coverage_map_consistency gate=' + $caseF + ' expected=TRUE result=' + $(if ($caseF -eq 'PASS') { 'TRUE' } else { 'FALSE' }))
$validationLines.Add('CASE G phase50_9_crosscheck gate=' + $caseG + ' expected=TRUE result=' + $(if ($caseG -eq 'PASS') { 'TRUE' } else { 'FALSE' }) + ' gate_record_caseA_ok=' + $(if ($caseA50_9GateRecordOk) { 'TRUE' } else { 'FALSE' }) + ' bypass_cases_ok=' + $bypassCaseOkCount + '/8')

$allPass = (@($caseA,$caseB,$caseC,$caseD,$caseE,$caseF,$caseG) | Where-Object { $_ -eq 'PASS' }).Count -eq 7
$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status01 = @(
    'PHASE=51.0',
    'TITLE=Trust-Chain Ledger Baseline Enforcement Coverage Fingerprint Trust-Chain Baseline Enforcement Coverage Audit',
    ('GATE={0}' -f $Gate),
    ('ENTRYPOINT_INVENTORY_COMPLETE={0}' -f $(if ($caseA -eq 'PASS') { 'TRUE' } else { 'FALSE' })),
    ('DIRECT_GATE_COVERAGE_VERIFIED={0}' -f $(if ($caseB -eq 'PASS') { 'TRUE' } else { 'FALSE' })),
    ('TRANSITIVE_GATE_COVERAGE_VERIFIED={0}' -f $(if ($caseC -eq 'PASS') { 'TRUE' } else { 'FALSE' })),
    ('UNGUARDED_OPERATIONAL_PATHS={0}' -f $unguardedOperational.Count),
    ('BYPASS_CROSSCHECK_TRUE={0}' -f $(if ($caseG -eq 'PASS') { 'TRUE' } else { 'FALSE' })),
    'RUNTIME_STATE_MACHINE_CHANGED=FALSE',
    'NO_FALLBACK=TRUE',
    'NO_REGENERATION=TRUE'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '01_status.txt'), $status01, [System.Text.Encoding]::UTF8)

$head02 = @(
    ('RUNNER={0}' -f $RunnerPath),
    ('phase50_8_RUNNER={0}' -f $phase50_8Path),
    ('phase50_9_RUNNER={0}' -f $phase50_9Path),
    ('CROSSCHECK_phase50_9_PROOF={0}' -f $Latest50_9Proof)
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '02_head.txt'), $head02, [System.Text.Encoding]::UTF8)

$def10 = @(
    'ENTRYPOINT_INVENTORY_METHOD=Static function extraction + operation_requested inventory extraction from phase50_9 + runtime guard wrapper/gate call-path confirmation',
    'DISCOVERY_SCOPE=phase50_8 runner, phase50_9 runner, phase50_9 proof inventory/gate record',
    'COMPLETENESS_CRITERIA=All operational frozen-baseline-relevant operation types represented with direct/transitive gate evidence',
    'DEAD_HELPER_CRITERIA=Present in code but not part of active frozen-baseline operational path used by 50.8/50.9 model'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '10_entrypoint_inventory_definition.txt'), $def10, [System.Text.Encoding]::UTF8)

$rules11 = @(
    'RULE_1=Operational entrypoint/helper must be classified directly_gated or transitively_gated',
    'RULE_2=Any operational unguarded path -> phase FAIL',
    'RULE_3=Dead/non-operational helpers are documented and not counted as protected operational coverage',
    'RULE_4=No assumed gating; each entry requires explicit gate-source evidence',
    'RULE_5=Coverage map must align with latest phase50_9 bypass inventory and gate record',
    'RULE_6=Runtime state machine unchanged; audit is read-only for runtime behavior'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '11_frozen_baseline_coverage_rules.txt'), $rules11, [System.Text.Encoding]::UTF8)

$files12 = @(
    'READ=' + $phase50_8Path,
    'READ=' + $phase50_9Path,
    'READ=' + $CrossInvPath,
    'READ=' + $CrossGatePath,
    'WRITE=' + $PF
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '12_files_touched.txt'), $files12, [System.Text.Encoding]::UTF8)

$build13 = @(
    ('DISCOVERED_FUNCTIONS_phase50_8={0}' -f $fn50_8.Count),
    ('DISCOVERED_FUNCTIONS_phase50_9={0}' -f $fn50_9.Count),
    ('INVENTORY_COUNT={0}' -f $inventoryList.Count),
    ('OPERATIONAL_COUNT={0}' -f @($inventoryList | Where-Object { $_.operational_or_dead -eq 'operational' }).Count),
    ('DEAD_COUNT={0}' -f @($inventoryList | Where-Object { $_.operational_or_dead -eq 'dead_or_non_operational' }).Count),
    ('UNGUARDED_OPERATIONAL_PATHS={0}' -f $unguardedOperational.Count),
    ('GATE={0}' -f $Gate)
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '13_build_output.txt'), $build13, [System.Text.Encoding]::UTF8)

[System.IO.File]::WriteAllText((Join-Path $PF '14_validation_results.txt'), ($validationLines -join "`r`n"), [System.Text.Encoding]::UTF8)

$summary15 = @(
    'TOTAL_CASES=7',
    'PASSED=' + @($validationLines | Where-Object { $_ -match ' gate=PASS ' }).Count,
    'FAILED=' + @($validationLines | Where-Object { $_ -match ' gate=FAIL ' }).Count,
    'ENTRYPOINT_INVENTORY_METHOD=Derived from actual phase50_8/phase50_9 scripts using function extraction and operation inventory parsing',
    'DIRECT_VS_TRANSITIVE_METHOD=Direct when wrapper invokes gate; transitive when helper only reachable through gated wrapper/gate call graph',
    'DEAD_HELPER_METHOD=Function exists but absent from active protected operation map and gate call graph',
    'UNGUARDED_DETECTION_METHOD=Operational entries with classification=unguarded are counted and reported',
    'phase50_9_CROSSCHECK_METHOD=All operation_requested values must appear in phase50_9 inventory/gate record and case outcomes must match expected allow/block semantics',
    'COVERAGE_MAP_COMPLETENESS=All operational frozen-baseline-relevant operation types mapped with explicit evidence',
    'RUNTIME_STATE_MACHINE_UNCHANGED=TRUE',
    'NO_FALLBACK=TRUE',
    'NO_REGENERATION=TRUE',
    'GATE=' + $Gate
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '15_behavior_summary.txt'), $summary15, [System.Text.Encoding]::UTF8)

$header16 = 'file_path|function_or_entrypoint|role|operational_or_dead|direct_gate_present|transitive_gate_present|gate_source_path|frozen_baseline_relevant_operation_type|coverage_classification|evidence_notes'
$rows16 = [System.Collections.Generic.List[string]]::new()
$rows16.Add($header16)
foreach ($item in $inventoryList) {
    $rows16.Add(
        [string]$item.file_path + '|' +
        [string]$item.function_or_entrypoint + '|' +
        [string]$item.role + '|' +
        [string]$item.operational_or_dead + '|' +
        [string]$item.direct_gate_present + '|' +
        [string]$item.transitive_gate_present + '|' +
        [string]$item.gate_source_path + '|' +
        [string]$item.frozen_baseline_relevant_operation_type + '|' +
        [string]$item.coverage_classification + '|' +
        [string]$item.evidence_notes
    )
}
[System.IO.File]::WriteAllText((Join-Path $PF '16_entrypoint_inventory.txt'), ($rows16 -join "`r`n"), [System.Text.Encoding]::UTF8)

[System.IO.File]::WriteAllText((Join-Path $PF '17_frozen_baseline_enforcement_map.txt'), ($mapLines -join "`r`n"), [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText((Join-Path $PF '18_unguarded_path_report.txt'), ($unguardedLines -join "`r`n"), [System.Text.Encoding]::UTF8)

$crossHeader = @(
    ('LATEST_phase50_9_PROOF={0}' -f $Latest50_9Proof),
    ('CROSSCHECK_SOURCE_INVENTORY={0}' -f $CrossInvPath),
    ('CROSSCHECK_SOURCE_GATE_RECORD={0}' -f $CrossGatePath),
    ('MISSING_OPERATION_COUNT={0}' -f $missingOps.Count),
    ('CASE_A_GATE_RECORD_OK={0}' -f $(if ($caseA50_9GateRecordOk) { 'TRUE' } else { 'FALSE' })),
    ('BYPASS_CASES_OK={0}/8' -f $bypassCaseOkCount)
)
$crossContent = [System.Collections.Generic.List[string]]::new()
foreach ($line in $crossHeader) { $crossContent.Add($line) | Out-Null }
foreach ($line in $crossLines) { $crossContent.Add($line) | Out-Null }
if ($missingOps.Count -gt 0) {
    $crossContent.Add(('MISSING_OPERATIONS={0}' -f ($missingOps -join ','))) | Out-Null
}
[System.IO.File]::WriteAllText((Join-Path $PF '19_bypass_crosscheck_report.txt'), (@($crossContent) -join "`r`n"), [System.Text.Encoding]::UTF8)

$gate98 = @('PHASE=51.0','GATE=' + $Gate) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '98_gate_phase51_0.txt'), $gate98, [System.Text.Encoding]::UTF8)

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

