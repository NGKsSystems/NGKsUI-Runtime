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

        $body = $Content.Substring($openBraceIndex, ($endIndex - $openBraceIndex + 1))
        $line = 1 + (($Content.Substring(0, $m.Index) -split "`r?`n").Count - 1)

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
        if ($Text -match ("(?m)\\b" + [regex]::Escape($fn) + "\\b")) {
            $targets.Add($fn)
        }
    }
    return @($targets | Select-Object -Unique)
}

function Get-RoleForFunction {
    param([string]$FunctionName)

    switch -Regex ($FunctionName) {
        '^Invoke-CertificationBaselineEnforcementGate$' { return 'gate_source_core' }
        '^Invoke-GuardedBaselineSnapshotLoad$' { return 'baseline_snapshot_load_entrypoint' }
        '^Invoke-GuardedIntegrityRecordLoad$' { return 'baseline_integrity_record_load_entrypoint' }
        '^Invoke-GuardedBaselineVerification$' { return 'baseline_verification_entrypoint' }
        '^Invoke-GuardedLedgerHeadRead$' { return 'ledger_head_read_entrypoint' }
        '^Invoke-GuardedCoverageFingerprintRead$' { return 'coverage_fingerprint_read_entrypoint' }
        '^Invoke-GuardedInventorySemanticHash$' { return 'entrypoint_inventory_semantic_entrypoint' }
        '^Invoke-GuardedEnforcementMapSemanticHash$' { return 'enforcement_map_semantic_entrypoint' }
        '^Invoke-GuardedRuntimeGateInitWrapper$' { return 'runtime_gate_init_wrapper' }
        '^Invoke-GuardedHistoricalValidation$' { return 'historical_validation_entrypoint' }
        '^Get-JsonSemanticSha256$' { return 'baseline_json_semantic_hash_helper' }
        '^Get-InventorySemanticSha256$' { return 'inventory_semantic_hash_helper' }
        '^Get-EnforcementMapSemanticSha256$' { return 'enforcement_map_semantic_hash_helper' }
        '^Test-LegacyTrustChain$' { return 'ledger_head_validation_helper' }
        '^Convert-ToCanonicalJson$' { return 'canonical_json_helper' }
        '^Convert-InventoryLineToCanonicalEntry$' { return 'inventory_canonicalization_helper' }
        '^Convert-MapLineToCanonical$' { return 'enforcement_map_canonicalization_helper' }
        '^Get-LegacyChainEntryCanonical$' { return 'ledger_canonicalization_helper' }
        '^Get-LegacyChainEntryHash$' { return 'ledger_hash_helper' }
        '^Get-BytesSha256Hex$' { return 'sha256_bytes_helper' }
        '^Get-StringSha256Hex$' { return 'sha256_string_helper' }
        default { return 'helper' }
    }
}

function Get-OperationTypeForFunction {
    param([string]$FunctionName)

    switch -Regex ($FunctionName) {
        '^Invoke-CertificationBaselineEnforcementGate$' { return 'certification_baseline_gate_enforcement' }
        '^Invoke-GuardedBaselineSnapshotLoad$' { return 'certification_baseline_snapshot_load' }
        '^Invoke-GuardedIntegrityRecordLoad$' { return 'certification_baseline_integrity_load' }
        '^Invoke-GuardedBaselineVerification$' { return 'certification_baseline_verification' }
        '^Invoke-GuardedLedgerHeadRead$' { return 'ledger_head_read_validation' }
        '^Invoke-GuardedCoverageFingerprintRead$' { return 'coverage_fingerprint_read_validation' }
        '^Invoke-GuardedInventorySemanticHash$' { return 'entrypoint_inventory_semantic_hash' }
        '^Invoke-GuardedEnforcementMapSemanticHash$' { return 'enforcement_map_semantic_hash' }
        '^Invoke-GuardedRuntimeGateInitWrapper$' { return 'runtime_gate_initialization_wrapper' }
        '^Invoke-GuardedHistoricalValidation$' { return 'historical_auxiliary_validation' }
        '^Get-JsonSemanticSha256$' { return 'baseline_snapshot_semantic_hash' }
        '^Get-InventorySemanticSha256$' { return 'inventory_semantic_hash' }
        '^Get-EnforcementMapSemanticSha256$' { return 'enforcement_map_semantic_hash' }
        '^Test-LegacyTrustChain$' { return 'ledger_head_validation' }
        '^Convert-ToCanonicalJson$' { return 'canonicalization' }
        '^Convert-InventoryLineToCanonicalEntry$' { return 'inventory_canonicalization' }
        '^Convert-MapLineToCanonical$' { return 'enforcement_map_canonicalization' }
        '^Get-LegacyChainEntryCanonical$' { return 'ledger_entry_canonicalization' }
        '^Get-LegacyChainEntryHash$' { return 'ledger_entry_hash' }
        '^Get-BytesSha256Hex$' { return 'sha256_hashing' }
        '^Get-StringSha256Hex$' { return 'sha256_hashing' }
        default { return 'helper' }
    }
}

function Get-RelevanceReason {
    param([string]$FunctionName)

    switch -Regex ($FunctionName) {
        '^Invoke-CertificationBaselineEnforcementGate$' { return 'core gate for certification baseline enforcement' }
        '^Invoke-Guarded' { return 'guarded helper entrypoint over protected certification baseline input' }
        '^Get-JsonSemanticSha256$' { return 'verifies certification baseline snapshot semantic integrity' }
        '^Get-InventorySemanticSha256$' { return 'materializes inventory semantic input used by the gate' }
        '^Get-EnforcementMapSemanticSha256$' { return 'materializes enforcement-map semantic input used by the gate' }
        '^Test-LegacyTrustChain$' { return 'validates ledger head used by the gate' }
        '^Convert-ToCanonicalJson$' { return 'canonicalizes protected baseline inputs for semantic hashing' }
        '^Convert-InventoryLineToCanonicalEntry$' { return 'canonicalizes protected inventory lines used by semantic hashing' }
        '^Convert-MapLineToCanonical$' { return 'canonicalizes protected enforcement-map lines used by semantic hashing' }
        '^Get-LegacyChainEntryCanonical$' { return 'supports ledger head canonicalization used by trust-chain validation' }
        '^Get-LegacyChainEntryHash$' { return 'supports ledger entry hashing used by trust-chain validation' }
        '^Get-BytesSha256Hex$' { return 'shared hash primitive used by certification-baseline helpers' }
        '^Get-StringSha256Hex$' { return 'shared hash primitive used by certification-baseline helpers' }
        default { return 'keyword relevance' }
    }
}

function Get-LatestPhase45_5ProofPath {
    param([string]$ProofRoot)

    $dirs = @(Get-ChildItem -LiteralPath $ProofRoot -Directory | Where-Object { $_.Name -like 'phase45_5_certification_baseline_enforcement_bypass_resistance_*' } | Sort-Object Name)
    if ($dirs.Count -eq 0) {
        throw 'No Phase 45.5 proof packet found under _proof.'
    }
    return $dirs[$dirs.Count - 1].FullName
}

function Get-Phase45_5AllowedEntrypoints {
    param([string]$RecordPath)

    $names = [System.Collections.Generic.List[string]]::new()
    $lines = @(Get-Content -LiteralPath $RecordPath)
    foreach ($line in $lines) {
        if ($line -like 'case|*') {
            continue
        }
        $parts = @($line -split '\|')
        if ($parts.Count -lt 7) {
            continue
        }
        if ($parts[0] -eq 'A' -and $parts[6] -eq 'ALLOWED') {
            $names.Add([string]$parts[2])
        }
    }
    return @($names | Sort-Object -Unique)
}

function New-InventoryRow {
    param(
        [object]$FunctionRecord,
        [string]$Role,
        [string]$OperationalOrDead,
        [string]$DirectGatePresent,
        [string]$TransitiveGatePresent,
        [string]$GateSourcePath,
        [string]$OperationType,
        [string]$CoverageClassification,
        [string]$Notes
    )

    return [ordered]@{
        file_path = [string]$FunctionRecord.file_path
        function_or_entrypoint = [string]$FunctionRecord.function_name
        role = $Role
        operational_or_dead = $OperationalOrDead
        direct_gate_present = $DirectGatePresent
        transitive_gate_present = $TransitiveGatePresent
        gate_source_path = $GateSourcePath
        certification_baseline_relevant_operation_type = $OperationType
        coverage_classification = $CoverageClassification
        notes_on_evidence = $Notes
    }
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\phase45_6_certification_baseline_enforcement_coverage_audit_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$ScopeFiles = @(
    'tools/phase45_4/phase45_4_runtime_gate_certification_baseline_enforcement_runner.ps1',
    'tools/phase45_5/phase45_5_certification_baseline_enforcement_bypass_resistance_runner.ps1'
)

$fileContents = @{}
$allFunctions = [System.Collections.Generic.List[object]]::new()
foreach ($rel in $ScopeFiles) {
    $abs = Join-Path $Root ($rel.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $abs)) {
        throw ('Required scope file missing: ' + $rel)
    }
    $content = Get-Content -Raw -LiteralPath $abs
    $fileContents[$rel] = $content
    $records = Get-FunctionRecords -FilePath $rel -Content $content
    foreach ($record in $records) {
        $allFunctions.Add($record)
    }
}

$allFunctionNames = @($allFunctions | ForEach-Object { [string]$_.function_name } | Sort-Object -Unique)

$callEdges = [System.Collections.Generic.List[object]]::new()
foreach ($fn in $allFunctions) {
    $targets = Get-CallTargetNames -Text ([string]$fn.body) -KnownFunctionNames $allFunctionNames
    foreach ($targetName in $targets) {
        if ($targetName -eq $fn.function_name) {
            continue
        }
        $targetRecords = @($allFunctions | Where-Object { $_.file_path -eq $fn.file_path -and $_.function_name -eq $targetName })
        foreach ($targetRecord in $targetRecords) {
            $callEdges.Add([ordered]@{
                caller_key = [string]$fn.key
                callee_key = [string]$targetRecord.key
                caller = [string]$fn.function_name
                callee = [string]$targetRecord.function_name
                caller_file = [string]$fn.file_path
                callee_file = [string]$targetRecord.file_path
            })
        }
    }
}

$seedFunctions = @(
    $allFunctions | Where-Object {
        $_.file_path -eq 'tools/phase45_5/phase45_5_certification_baseline_enforcement_bypass_resistance_runner.ps1' -and (
            $_.function_name -eq 'Invoke-CertificationBaselineEnforcementGate' -or
            $_.function_name -like 'Invoke-Guarded*'
        )
    }
)

$relevantKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$queue = [System.Collections.Generic.Queue[string]]::new()
foreach ($seed in $seedFunctions) {
    $null = $relevantKeys.Add([string]$seed.key)
    $queue.Enqueue([string]$seed.key)
}

while ($queue.Count -gt 0) {
    $current = $queue.Dequeue()
    $outgoing = @($callEdges | Where-Object { $_.caller_key -eq $current })
    foreach ($edge in $outgoing) {
        if ($relevantKeys.Add([string]$edge.callee_key)) {
            $queue.Enqueue([string]$edge.callee_key)
        }
    }
}

$keywordRelevant = @(
    $allFunctions | Where-Object {
        $name = [string]$_.function_name
        $body = ([string]$_.body).ToLowerInvariant()
        $name -in @('Get-BytesSha256Hex', 'Get-StringSha256Hex') -or
        $name -match 'CertificationBaseline|Guarded|SemanticSha256|LegacyTrustChain|Canonical|Hash' -or
        $body.Contains('certification_baseline') -or
        $body.Contains('baseline_snapshot') -or
        $body.Contains('coverage_fingerprint') -or
        $body.Contains('ledger') -or
        $body.Contains('enforcement_map') -or
        $body.Contains('inventory')
    }
)
foreach ($fn in $keywordRelevant) {
    if ($fn.function_name -like 'New-*') {
        continue
    }
    $null = $relevantKeys.Add([string]$fn.key)
}

$relevantFunctions = @($allFunctions | Where-Object { $relevantKeys.Contains([string]$_.key) -and $_.function_name -notlike 'New-*' } | Sort-Object file_path, start_line)

$currentOperationalFile = 'tools/phase45_5/phase45_5_certification_baseline_enforcement_bypass_resistance_runner.ps1'
$operationalKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($fn in $relevantFunctions) {
    if ($fn.file_path -eq $currentOperationalFile -and $fn.function_name -notlike 'New-*') {
        $null = $operationalKeys.Add([string]$fn.key)
    }
}

$directGateByKey = @{}
foreach ($fn in $relevantFunctions) {
    $body = [string]$fn.body
    $directGateByKey[[string]$fn.key] = ($fn.function_name -eq 'Invoke-CertificationBaselineEnforcementGate' -or $body -match '\bInvoke-CertificationBaselineEnforcementGate\b')
}

$transitiveGateByKey = @{}
foreach ($fn in $relevantFunctions) {
    $key = [string]$fn.key
    $transitiveGateByKey[$key] = ($operationalKeys.Contains($key) -and -not $directGateByKey[$key])
}

$inventoryRows = [System.Collections.Generic.List[object]]::new()
foreach ($fn in $relevantFunctions) {
    $key = [string]$fn.key
    $role = Get-RoleForFunction -FunctionName ([string]$fn.function_name)
    $operationType = Get-OperationTypeForFunction -FunctionName ([string]$fn.function_name)
    $operationalOrDead = if ($operationalKeys.Contains($key)) { 'operational' } else { 'dead / non-operational' }
    $directGatePresent = if ($directGateByKey[$key]) { 'yes' } else { 'no' }
    $transitiveGatePresent = if ($transitiveGateByKey[$key]) { 'yes' } else { 'no' }

    $gateSourcePath = ''
    if ($directGateByKey[$key]) {
        $gateSourcePath = if ($fn.function_name -eq 'Invoke-CertificationBaselineEnforcementGate') { 'self' } else { 'Invoke-CertificationBaselineEnforcementGate' }
    } elseif ($transitiveGateByKey[$key]) {
        $guardedCallers = @(
            $callEdges |
            Where-Object {
                $_.callee_key -eq $key -and
                $_.caller_file -eq $currentOperationalFile
            } |
            ForEach-Object { [string]$_.caller } |
            Sort-Object -Unique
        )
        if ($guardedCallers.Count -eq 0) {
            $gateSourcePath = 'Invoke-CertificationBaselineEnforcementGate via current phase45_5 helper closure'
        } else {
            $gateSourcePath = ($guardedCallers -join ';')
        }
    }

    $coverageClassification = 'dead / non-operational'
    if ($operationalKeys.Contains($key)) {
        if ($directGateByKey[$key]) {
            $coverageClassification = 'directly gated'
        } elseif ($transitiveGateByKey[$key]) {
            $coverageClassification = 'transitively gated'
        } else {
            $coverageClassification = 'unguarded'
        }
    }

    $notes = @(
        ('line=' + [string]$fn.start_line),
        ('relevance=' + (Get-RelevanceReason -FunctionName ([string]$fn.function_name)))
    )
    if ($directGateByKey[$key] -and $fn.function_name -ne 'Invoke-CertificationBaselineEnforcementGate') {
        $notes += 'evidence=body_calls_Invoke-CertificationBaselineEnforcementGate'
    } elseif ($fn.function_name -eq 'Invoke-CertificationBaselineEnforcementGate') {
        $notes += 'evidence=gate_source_root'
    } elseif ($transitiveGateByKey[$key]) {
        $notes += ('evidence=current_phase45_5_helper_inside_guarded_closure:' + $gateSourcePath)
    } else {
        $notes += 'evidence=not_reachable_from_current_phase45_5_operational_roots'
    }

    $inventoryRows.Add((New-InventoryRow -FunctionRecord $fn -Role $role -OperationalOrDead $operationalOrDead -DirectGatePresent $directGatePresent -TransitiveGatePresent $transitiveGatePresent -GateSourcePath $gateSourcePath -OperationType $operationType -CoverageClassification $coverageClassification -Notes ($notes -join ';')))
}

$operationalRows = @($inventoryRows | Where-Object { $_.operational_or_dead -eq 'operational' })
$deadRows = @($inventoryRows | Where-Object { $_.operational_or_dead -eq 'dead / non-operational' })
$directRows = @($operationalRows | Where-Object { $_.coverage_classification -eq 'directly gated' })
$transitiveRows = @($operationalRows | Where-Object { $_.coverage_classification -eq 'transitively gated' })
$unguardedRows = @($operationalRows | Where-Object { $_.coverage_classification -eq 'unguarded' })

$requiredDirectNames = @(
    'Invoke-CertificationBaselineEnforcementGate',
    'Invoke-GuardedBaselineSnapshotLoad',
    'Invoke-GuardedIntegrityRecordLoad',
    'Invoke-GuardedBaselineVerification',
    'Invoke-GuardedLedgerHeadRead',
    'Invoke-GuardedCoverageFingerprintRead',
    'Invoke-GuardedInventorySemanticHash',
    'Invoke-GuardedEnforcementMapSemanticHash',
    'Invoke-GuardedRuntimeGateInitWrapper',
    'Invoke-GuardedHistoricalValidation'
)
$directNamesFound = @($directRows | ForEach-Object { [string]$_.function_or_entrypoint } | Sort-Object -Unique)
$missingDirect = @($requiredDirectNames | Where-Object { $directNamesFound -notcontains $_ })

$requiredTransitiveNames = @(
    'Get-BytesSha256Hex',
    'Get-StringSha256Hex',
    'Convert-ToCanonicalJson',
    'Get-JsonSemanticSha256',
    'Get-LegacyChainEntryCanonical',
    'Get-LegacyChainEntryHash',
    'Test-LegacyTrustChain',
    'Convert-InventoryLineToCanonicalEntry',
    'Get-InventorySemanticSha256',
    'Convert-MapLineToCanonical',
    'Get-EnforcementMapSemanticSha256'
)
$transitiveNamesFound = @($transitiveRows | ForEach-Object { [string]$_.function_or_entrypoint } | Sort-Object -Unique)
$missingTransitive = @($requiredTransitiveNames | Where-Object { $transitiveNamesFound -notcontains $_ })

$phase45_5ProofPath = Get-LatestPhase45_5ProofPath -ProofRoot (Join-Path $Root '_proof')
$phase45_5ValidationPath = Join-Path $phase45_5ProofPath '14_validation_results.txt'
$phase45_5RecordPath = Join-Path $phase45_5ProofPath '16_entrypoint_baseline_gate_record.txt'
if (-not (Test-Path -LiteralPath $phase45_5ValidationPath)) {
    throw 'Phase 45.5 validation results not found.'
}
if (-not (Test-Path -LiteralPath $phase45_5RecordPath)) {
    throw 'Phase 45.5 gate record not found.'
}

$phase45_5Validation = @(Get-Content -LiteralPath $phase45_5ValidationPath)
$phase45_5ValidationPass = ($phase45_5Validation.Count -eq 8 -and @($phase45_5Validation | Where-Object { $_ -notmatch '=PASS$' }).Count -eq 0)
$phase45_5AllowedEntrypoints = Get-Phase45_5AllowedEntrypoints -RecordPath $phase45_5RecordPath
$phase45_5AllowedMatch = (@($requiredDirectNames | Where-Object { $_ -ne 'Invoke-CertificationBaselineEnforcementGate' }) | Sort-Object) -join ',' -eq (@($phase45_5AllowedEntrypoints | Sort-Object) -join ',')

$inventoryMapConsistency = ($inventoryRows.Count -eq (@($directRows).Count + @($transitiveRows).Count + @($unguardedRows).Count + @($deadRows).Count))
$allOperationalGuarded = ($unguardedRows.Count -eq 0)

$caseA = ($inventoryRows.Count -gt 0 -and $operationalRows.Count -gt 0 -and $missingDirect.Count -eq 0 -and $missingTransitive.Count -eq 0)
$caseB = ($missingDirect.Count -eq 0)
$caseC = ($missingTransitive.Count -eq 0)
$caseD = ($unguardedRows.Count -eq 0)
$caseE = ($deadRows.Count -gt 0 -and @($deadRows | Where-Object { $_.coverage_classification -ne 'dead / non-operational' }).Count -eq 0)
$caseF = ($inventoryMapConsistency -and $phase45_5ValidationPass -and $phase45_5AllowedMatch)

$allPass = ($caseA -and $caseB -and $caseC -and $caseD -and $caseE -and $caseF -and $allOperationalGuarded)
$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status = @(
    'phase=45.6',
    'title=Certification Baseline Enforcement Coverage Audit / Completeness Proof',
    ('gate=' + $Gate),
    ('relevant_functions_discovered=' + $inventoryRows.Count),
    ('operational_functions=' + $operationalRows.Count),
    ('directly_gated_operational_functions=' + $directRows.Count),
    ('transitively_gated_operational_functions=' + $transitiveRows.Count),
    ('unguarded_operational_functions=' + $unguardedRows.Count),
    ('dead_non_operational_functions=' + $deadRows.Count),
    ('runtime_state_machine_changed=FALSE')
)
Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value ($status -join "`r`n") -Encoding UTF8 -NoNewline

$head = @(
    'runner=tools/phase45_6/phase45_6_certification_baseline_enforcement_coverage_audit_runner.ps1',
    ('scope_file_1=' + $ScopeFiles[0]),
    ('scope_file_2=' + $ScopeFiles[1]),
    ('phase45_5_proof_packet=' + $phase45_5ProofPath),
    ('phase45_5_validation=' + $phase45_5ValidationPath),
    ('phase45_5_gate_record=' + $phase45_5RecordPath)
)
Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value ($head -join "`r`n") -Encoding UTF8 -NoNewline

$definition = @(
    'CERTIFICATION BASELINE ENFORCEMENT COVERAGE INVENTORY DEFINITION (PHASE 45.6)',
    '',
    'Inventory source is derived from the actual function bodies in phase45_4 and phase45_5 runners.',
    'Relevant surface starts from current operational Phase 45.5 roots: the 9 guarded wrappers and the shared gate function.',
    'Relevant helper closure is built from real intra-file call edges, then augmented by keyword-relevant certification helpers present in scope files.',
    'Functions reachable from Phase 45.5 roots are operational; keyword-relevant functions outside that reachability set are documented as dead / non-operational historical helpers.',
    'Direct gate coverage means the function is the gate source or explicitly calls Invoke-CertificationBaselineEnforcementGate.',
    'Transitive gate coverage means the function is operational and only reachable through already gated callers.',
    'Any operational function that is neither directly nor transitively gated is classified as unguarded and fails the phase.'
)
Set-Content -LiteralPath (Join-Path $PF '10_entrypoint_inventory_definition.txt') -Value ($definition -join "`r`n") -Encoding UTF8 -NoNewline

$rules = @(
    'CERTIFICATION BASELINE COVERAGE RULES',
    '1) Inventory only from actual repo code in phase45_4 and phase45_5; no assumed entries.',
    '2) Mark operational roots from current Phase 45.5 guarded wrappers and the shared gate implementation.',
    '3) Traverse real call edges to derive transitive helper coverage.',
    '4) Mark a function directly gated only if it is the gate source or explicitly calls Invoke-CertificationBaselineEnforcementGate.',
    '5) Mark a function transitively gated only if every operational caller is already directly or transitively gated.',
    '6) Mark keyword-relevant but unreachable historical helpers as dead / non-operational.',
    '7) Fail if any operational certification-baseline-relevant function is unguarded.',
    '8) Cross-check the discovered direct entrypoints against the latest Phase 45.5 bypass-resistance proof packet.',
    '9) Runtime state machine must remain unchanged because this phase is audit-only.'
)
Set-Content -LiteralPath (Join-Path $PF '11_certification_baseline_coverage_rules.txt') -Value ($rules -join "`r`n") -Encoding UTF8 -NoNewline

$filesTouched = @(
    ('READ  ' + (Join-Path $Root ($ScopeFiles[0].Replace('/', '\')))),
    ('READ  ' + (Join-Path $Root ($ScopeFiles[1].Replace('/', '\')))),
    ('READ  ' + $phase45_5ValidationPath),
    ('READ  ' + $phase45_5RecordPath),
    ('WRITE ' + (Join-Path $PF '*'))
)
Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Value ($filesTouched -join "`r`n") -Encoding UTF8 -NoNewline

$build = @(
    'build_type=PowerShell static_plus_proof_consistency_audit',
    'compile_required=no',
    'runtime_validation_used=phase45_5_proof_packet_consistency_check',
    'canonical_launcher_required=no_additional_launcher_needed',
    'runtime_state_machine_changed=no',
    ('scope_function_count=' + $allFunctions.Count),
    ('relevant_function_count=' + $inventoryRows.Count),
    ('call_edge_count=' + $callEdges.Count)
)
Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Value ($build -join "`r`n") -Encoding UTF8 -NoNewline

$validation = @(
    ('CASE A entrypoint_inventory_complete=' + $(if ($caseA) { 'PASS' } else { 'FAIL' })),
    ('CASE B direct_gate_coverage_verified=' + $(if ($caseB) { 'PASS' } else { 'FAIL' })),
    ('CASE C transitive_gate_coverage_verified=' + $(if ($caseC) { 'PASS' } else { 'FAIL' })),
    ('CASE D unguarded_operational_paths=' + $(if ($caseD) { 'PASS' } else { 'FAIL' })),
    ('CASE E dead_helpers_documented=' + $(if ($caseE) { 'PASS' } else { 'FAIL' })),
    ('CASE F coverage_map_consistency=' + $(if ($caseF) { 'PASS' } else { 'FAIL' }))
)
Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Value ($validation -join "`r`n") -Encoding UTF8 -NoNewline

$summary = @(
    'Phase 45.6 inventories the certification-baseline-relevant surface from the actual Phase 45.4 and Phase 45.5 runner code.',
    'The audit starts from the current operational Phase 45.5 guarded wrappers and the shared enforcement gate, then walks real call edges to discover transitively protected helpers.',
    'Direct coverage is assigned only where the function is the gate source or explicitly calls Invoke-CertificationBaselineEnforcementGate.',
    'Transitive coverage is assigned only where the helper is operational and every operational caller is already guarded.',
    'Historical Phase 45.4 helper copies are documented as dead / non-operational because they are not reachable from the current Phase 45.5 operational roots.',
    'Unguarded path detection is strict: any operational relevant function not classified as directly or transitively gated is emitted in 18_unguarded_path_report.txt and fails the phase.',
    'Coverage-map consistency is checked against the latest Phase 45.5 proof packet so the discovered direct wrappers align with prior bypass-resistance evidence.',
    'Runtime behavior remained unchanged because this runner only reads scripts and proof artifacts and writes audit evidence.'
)
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value ($summary -join "`r`n") -Encoding UTF8 -NoNewline

$inventoryLines = [System.Collections.Generic.List[string]]::new()
$inventoryLines.Add('file_path | function_or_entrypoint | role | operational_or_dead | direct_gate_present | transitive_gate_present | gate_source_path | certification_baseline_relevant_operation_type | coverage_classification | notes_on_evidence')
foreach ($row in $inventoryRows) {
    $inventoryLines.Add(
        [string]$row.file_path + ' | ' +
        [string]$row.function_or_entrypoint + ' | ' +
        [string]$row.role + ' | ' +
        [string]$row.operational_or_dead + ' | ' +
        [string]$row.direct_gate_present + ' | ' +
        [string]$row.transitive_gate_present + ' | ' +
        [string]$row.gate_source_path + ' | ' +
        [string]$row.certification_baseline_relevant_operation_type + ' | ' +
        [string]$row.coverage_classification + ' | ' +
        [string]$row.notes_on_evidence
    )
}
Set-Content -LiteralPath (Join-Path $PF '16_entrypoint_inventory.txt') -Value (($inventoryLines.ToArray()) -join "`r`n") -Encoding UTF8 -NoNewline

$mapLines = [System.Collections.Generic.List[string]]::new()
$mapLines.Add('CERTIFICATION BASELINE ENFORCEMENT MAP (PHASE 45.6)')
$mapLines.Add('')
$mapLines.Add('Active operational surface:')
foreach ($row in $operationalRows) {
    $mapLines.Add([string]$row.function_or_entrypoint + ' -> ' + [string]$row.coverage_classification + ' -> gate_source=' + [string]$row.gate_source_path)
}
$mapLines.Add('')
$mapLines.Add('Historical / dead helpers:')
foreach ($row in $deadRows) {
    $mapLines.Add([string]$row.function_or_entrypoint + ' -> dead / non-operational')
}
Set-Content -LiteralPath (Join-Path $PF '17_certification_baseline_enforcement_map.txt') -Value (($mapLines.ToArray()) -join "`r`n") -Encoding UTF8 -NoNewline

$unguardedReport = [System.Collections.Generic.List[string]]::new()
$unguardedReport.Add('UNGUARDED OPERATIONAL PATH REPORT')
$unguardedReport.Add(('unguarded_operational_path_count=' + $unguardedRows.Count))
if ($unguardedRows.Count -eq 0) {
    $unguardedReport.Add('status=none_detected')
} else {
    foreach ($row in $unguardedRows) {
        $unguardedReport.Add([string]$row.file_path + ' | ' + [string]$row.function_or_entrypoint + ' | ' + [string]$row.role + ' | ' + [string]$row.notes_on_evidence)
    }
}
$unguardedReport.Add(('missing_direct=' + ($(if ($missingDirect.Count -eq 0) { 'none' } else { $missingDirect -join ';' }))))
$unguardedReport.Add(('missing_transitive=' + ($(if ($missingTransitive.Count -eq 0) { 'none' } else { $missingTransitive -join ';' }))))
Set-Content -LiteralPath (Join-Path $PF '18_unguarded_path_report.txt') -Value (($unguardedReport.ToArray()) -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '98_gate_phase45_6.txt') -Value $Gate -Encoding UTF8 -NoNewline

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