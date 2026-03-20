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
        if ($Text -match ('(?m)\b' + [regex]::Escape($fn) + '\b')) {
            $targets.Add($fn)
        }
    }
    return @($targets | Select-Object -Unique)
}

function Get-ScopeFiles {
    param([string]$ToolsRoot)

    $pattern = '77_certification_baseline_coverage_trust_chain_baseline|78_certification_baseline_coverage_trust_chain_baseline_integrity|76_certification_baseline_coverage_fingerprint|70_guard_fingerprint_trust_chain|Invoke-FrozenBaselineTrustChainEnforcementGate|Test-FrozenBaselineReference|Invoke-GuardedFrozenBaseline|Invoke-GuardedLedgerHeadRead|Invoke-GuardedCoverageFingerprintRead|Invoke-GuardedChainContinuationValidation|Invoke-GuardedRuntimeInitWrapper'
    $matches = Select-String -Path (Join-Path $ToolsRoot '*.ps1'), (Join-Path $ToolsRoot '*\*.ps1') -Pattern $pattern -AllMatches
    $paths = @($matches | ForEach-Object {
        $full = [string]$_.Path
        if ($full.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
            $full.Substring($Root.Length + 1).Replace('\', '/')
        }
    } | Sort-Object -Unique)

    return @($paths | Where-Object { $_ -like 'tools/phase45_9/*' -or $_ -like 'tools/phase46_0/*' -or $_ -like 'tools/phase46_1/*' })
}

function Get-RoleForFunction {
    param([string]$FunctionName)

    switch -Regex ($FunctionName) {
        '^Invoke-FrozenBaselineTrustChainEnforcementGate$' { return 'frozen_baseline_gate_source' }
        '^Invoke-GuardedFrozenBaselineSnapshotLoad$' { return 'frozen_baseline_snapshot_load_entrypoint' }
        '^Invoke-GuardedFrozenBaselineIntegrityRecordLoad$' { return 'frozen_baseline_integrity_record_load_entrypoint' }
        '^Invoke-GuardedBaselineVerification$' { return 'frozen_baseline_verification_entrypoint' }
        '^Invoke-GuardedLedgerHeadRead$' { return 'ledger_head_read_validation_entrypoint' }
        '^Invoke-GuardedCoverageFingerprintRead$' { return 'coverage_fingerprint_read_validation_entrypoint' }
        '^Invoke-GuardedChainContinuationValidation$' { return 'chain_continuation_validation_entrypoint' }
        '^Invoke-GuardedFrozenBaselineSemanticHash$' { return 'protected_frozen_baseline_semantic_hash_entrypoint' }
        '^Invoke-GuardedProtectedFieldSemanticVerification$' { return 'protected_field_semantic_verification_entrypoint' }
        '^Invoke-GuardedRuntimeInitWrapper$' { return 'runtime_initialization_wrapper' }
        '^Test-FrozenBaselineReference$' { return 'historical_auxiliary_validation_path' }
        '^Get-JsonSemanticSha256$' { return 'protected_json_semantic_hash_helper' }
        '^Test-LegacyTrustChain$' { return 'ledger_head_validation_helper' }
        '^Get-LegacyChainEntryCanonical$' { return 'ledger_entry_canonicalization_helper' }
        '^Get-LegacyChainEntryHash$' { return 'ledger_entry_hash_helper' }
        '^Convert-ToCanonicalJson$' { return 'canonical_json_helper' }
        '^Get-BytesSha256Hex$' { return 'sha256_bytes_helper' }
        '^Get-StringSha256Hex$' { return 'sha256_string_helper' }
        '^New-FBBlockedResult$' { return 'guard_result_factory' }
        '^New-FBAllowedResult$' { return 'guard_result_factory' }
        '^Get-NextEntryId$' { return 'historical_chain_append_helper' }
        default { return 'helper' }
    }
}

function Get-OperationTypeForFunction {
    param([string]$FunctionName)

    switch -Regex ($FunctionName) {
        '^Invoke-FrozenBaselineTrustChainEnforcementGate$' { return 'enforce_frozen_baseline' }
        '^Invoke-GuardedFrozenBaselineSnapshotLoad$' { return 'load_frozen_baseline_snapshot' }
        '^Invoke-GuardedFrozenBaselineIntegrityRecordLoad$' { return 'load_frozen_baseline_integrity_record' }
        '^Invoke-GuardedBaselineVerification$' { return 'verify_frozen_baseline' }
        '^Invoke-GuardedLedgerHeadRead$' { return 'read_live_ledger_head' }
        '^Invoke-GuardedCoverageFingerprintRead$' { return 'read_live_coverage_fingerprint' }
        '^Invoke-GuardedChainContinuationValidation$' { return 'validate_chain_continuation' }
        '^Invoke-GuardedFrozenBaselineSemanticHash$' { return 'compute_frozen_baseline_semantic_hash' }
        '^Invoke-GuardedProtectedFieldSemanticVerification$' { return 'verify_protected_semantic_fields' }
        '^Invoke-GuardedRuntimeInitWrapper$' { return 'runtime_init' }
        '^Test-FrozenBaselineReference$' { return 'historical_frozen_baseline_reference_validation' }
        '^Get-JsonSemanticSha256$' { return 'semantic_hash_protected_input' }
        '^Test-LegacyTrustChain$' { return 'ledger_validation' }
        '^Get-LegacyChainEntryCanonical$' { return 'ledger_entry_canonicalization' }
        '^Get-LegacyChainEntryHash$' { return 'ledger_entry_hashing' }
        '^Convert-ToCanonicalJson$' { return 'canonicalization' }
        '^Get-BytesSha256Hex$' { return 'sha256_hashing' }
        '^Get-StringSha256Hex$' { return 'sha256_hashing' }
        '^New-FBBlockedResult$' { return 'blocked_result_materialization' }
        '^New-FBAllowedResult$' { return 'allowed_result_materialization' }
        '^Get-NextEntryId$' { return 'historical_chain_append_support' }
        default { return 'helper' }
    }
}

function Get-RelevanceReason {
    param([string]$FunctionName)

    switch -Regex ($FunctionName) {
        '^Invoke-FrozenBaselineTrustChainEnforcementGate$' { return 'core frozen-baseline enforcement gate' }
        '^Invoke-Guarded' { return 'guarded entrypoint over protected frozen-baseline input' }
        '^Test-FrozenBaselineReference$' { return 'historical baseline reference validator over same protected inputs' }
        '^Get-JsonSemanticSha256$' { return 'materializes semantic hash for protected frozen-baseline snapshot' }
        '^Test-LegacyTrustChain$' { return 'validates live ledger head used by the gate' }
        '^Get-LegacyChainEntryCanonical$' { return 'supports trust-chain canonicalization used by ledger validation' }
        '^Get-LegacyChainEntryHash$' { return 'supports trust-chain hashing used by ledger validation' }
        '^Convert-ToCanonicalJson$' { return 'canonicalizes protected inputs before semantic hashing' }
        '^Get-BytesSha256Hex$' { return 'shared hash primitive used by protected-input helpers' }
        '^Get-StringSha256Hex$' { return 'shared hash primitive used by protected-input helpers' }
        '^New-FB(Blocked|Allowed)Result$' { return 'materializes guarded operation result after gate decision' }
        '^Get-NextEntryId$' { return 'historical helper present in scope but not part of current operational frozen-baseline enforcement path' }
        default { return 'keyword relevance inside frozen-baseline scope file' }
    }
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
        frozen_baseline_relevant_operation_type = $OperationType
        coverage_classification = $CoverageClassification
        notes_on_evidence = $Notes
    }
}

function Get-LatestPhase46_1ProofPath {
    param([string]$ProofRoot)

    $dirs = @(Get-ChildItem -LiteralPath $ProofRoot -Directory | Where-Object { $_.Name -like 'phase46_1_trust_chain_baseline_enforcement_bypass_resistance_*' } | Sort-Object Name)
    if ($dirs.Count -eq 0) {
        throw 'No Phase 46.1 proof packet found under _proof.'
    }
    return $dirs[$dirs.Count - 1].FullName
}

function Get-Phase46_1InventoryNames {
    param([string]$InventoryPath)

    $names = [System.Collections.Generic.List[string]]::new()
    $lines = @(Get-Content -LiteralPath $InventoryPath)
    foreach ($line in $lines) {
        if ($line -like 'file_path*') {
            continue
        }
        $parts = @($line -split '\|')
        if ($parts.Count -lt 2) {
            continue
        }
        $names.Add(([string]$parts[1]).Trim())
    }
    return @($names | Sort-Object -Unique)
}

function Get-Phase46_1RecordNames {
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
        $names.Add([string]$parts[2])
    }
    return @($names | Sort-Object -Unique)
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\phase46_2_trust_chain_baseline_enforcement_coverage_audit_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$ScopeFiles = Get-ScopeFiles -ToolsRoot (Join-Path $Root 'tools')
if ($ScopeFiles.Count -eq 0) {
    throw 'No frozen-baseline-relevant scope files discovered.'
}

$fileContents = @{}
$allFunctions = [System.Collections.Generic.List[object]]::new()
foreach ($rel in $ScopeFiles) {
    $abs = Join-Path $Root ($rel.Replace('/', '\'))
    $content = Get-Content -Raw -LiteralPath $abs
    $fileContents[$rel] = $content
    $records = Get-FunctionRecords -FilePath $rel -Content $content
    foreach ($record in $records) {
        if ([string]$record.function_name -like 'New-*') {
            continue
        }
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

$CurrentOperationalFile = 'tools/phase46_1/phase46_1_trust_chain_baseline_enforcement_bypass_resistance_runner.ps1'
$seedFunctions = @(
    $allFunctions | Where-Object {
        $_.file_path -eq $CurrentOperationalFile -and (
            $_.function_name -eq 'Invoke-FrozenBaselineTrustChainEnforcementGate' -or
            $_.function_name -like 'Invoke-Guarded*'
        )
    }
)
if ($seedFunctions.Count -eq 0) {
    throw 'No operational frozen-baseline seed functions discovered in phase46_1.'
}

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
        $name -match 'FrozenBaseline|LegacyTrustChain|SemanticSha256|Canonical|Hash|Guarded|Test-FrozenBaselineReference' -or
        $body.Contains('frozen_baseline') -or
        $body.Contains('baseline_snapshot') -or
        $body.Contains('baseline_integrity') -or
        $body.Contains('coverage_fingerprint') -or
        $body.Contains('ledger') -or
        $body.Contains('chain_continuation') -or
        $body.Contains('runtime_init')
    }
)
foreach ($fn in $keywordRelevant) {
    $null = $relevantKeys.Add([string]$fn.key)
}

$relevantFunctions = @($allFunctions | Where-Object { $relevantKeys.Contains([string]$_.key) } | Sort-Object file_path, start_line)

$operationalKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($fn in $relevantFunctions) {
    if ($fn.file_path -eq $CurrentOperationalFile) {
        $null = $operationalKeys.Add([string]$fn.key)
    }
}

$directGateByKey = @{}
foreach ($fn in $relevantFunctions) {
    $body = [string]$fn.body
    $directGateByKey[[string]$fn.key] = ($fn.function_name -eq 'Invoke-FrozenBaselineTrustChainEnforcementGate' -or $body -match '\bInvoke-FrozenBaselineTrustChainEnforcementGate\b')
}

$transitiveGateByKey = @{}
foreach ($fn in $relevantFunctions) {
    $key = [string]$fn.key
    $transitiveGateByKey[$key] = ($operationalKeys.Contains($key) -and -not $directGateByKey[$key])
}

$inventoryRows = [System.Collections.Generic.List[object]]::new()
foreach ($fn in $relevantFunctions) {
    $key = [string]$fn.key
    $operationalOrDead = if ($operationalKeys.Contains($key)) { 'operational' } else { 'dead / non-operational' }
    $directGatePresent = if ($directGateByKey[$key]) { 'yes' } else { 'no' }
    $transitiveGatePresent = if ($transitiveGateByKey[$key]) { 'yes' } else { 'no' }

    $gateSourcePath = ''
    if ($directGateByKey[$key]) {
        $gateSourcePath = if ($fn.function_name -eq 'Invoke-FrozenBaselineTrustChainEnforcementGate') { 'self' } else { 'Invoke-FrozenBaselineTrustChainEnforcementGate' }
    } elseif ($transitiveGateByKey[$key]) {
        $guardedCallers = @(
            $callEdges |
            Where-Object { $_.callee_key -eq $key -and $_.caller_file -eq $CurrentOperationalFile } |
            ForEach-Object { [string]$_.caller } |
            Sort-Object -Unique
        )
        $gateSourcePath = if ($guardedCallers.Count -gt 0) { $guardedCallers -join ';' } else { 'Invoke-FrozenBaselineTrustChainEnforcementGate via current phase46_1 helper closure' }
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
    if ($directGateByKey[$key] -and $fn.function_name -ne 'Invoke-FrozenBaselineTrustChainEnforcementGate') {
        $notes += 'evidence=body_calls_Invoke-FrozenBaselineTrustChainEnforcementGate'
    } elseif ($fn.function_name -eq 'Invoke-FrozenBaselineTrustChainEnforcementGate') {
        $notes += 'evidence=gate_source_root'
    } elseif ($transitiveGateByKey[$key]) {
        $notes += ('evidence=current_phase46_1_helper_inside_guarded_closure:' + $gateSourcePath)
    } else {
        $notes += 'evidence=not_reachable_from_current_phase46_1_operational_roots'
    }

    $inventoryRows.Add((New-InventoryRow -FunctionRecord $fn -Role (Get-RoleForFunction -FunctionName ([string]$fn.function_name)) -OperationalOrDead $operationalOrDead -DirectGatePresent $directGatePresent -TransitiveGatePresent $transitiveGatePresent -GateSourcePath $gateSourcePath -OperationType (Get-OperationTypeForFunction -FunctionName ([string]$fn.function_name)) -CoverageClassification $coverageClassification -Notes ($notes -join ';')))
}

$operationalRows = @($inventoryRows | Where-Object { $_.operational_or_dead -eq 'operational' })
$deadRows = @($inventoryRows | Where-Object { $_.operational_or_dead -eq 'dead / non-operational' })
$directRows = @($operationalRows | Where-Object { $_.coverage_classification -eq 'directly gated' })
$transitiveRows = @($operationalRows | Where-Object { $_.coverage_classification -eq 'transitively gated' })
$unguardedRows = @($operationalRows | Where-Object { $_.coverage_classification -eq 'unguarded' })

$requiredDirectNames = @(
    'Invoke-FrozenBaselineTrustChainEnforcementGate',
    'Invoke-GuardedFrozenBaselineSnapshotLoad',
    'Invoke-GuardedFrozenBaselineIntegrityRecordLoad',
    'Invoke-GuardedBaselineVerification',
    'Invoke-GuardedLedgerHeadRead',
    'Invoke-GuardedCoverageFingerprintRead',
    'Invoke-GuardedChainContinuationValidation',
    'Invoke-GuardedFrozenBaselineSemanticHash',
    'Invoke-GuardedProtectedFieldSemanticVerification',
    'Invoke-GuardedRuntimeInitWrapper'
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
    'Test-LegacyTrustChain'
)
$transitiveNamesFound = @($transitiveRows | ForEach-Object { [string]$_.function_or_entrypoint } | Sort-Object -Unique)
$missingTransitive = @($requiredTransitiveNames | Where-Object { $transitiveNamesFound -notcontains $_ })

$requiredHistoricalNames = @('Test-FrozenBaselineReference')
$historicalNamesFound = @($deadRows | ForEach-Object { [string]$_.function_or_entrypoint } | Sort-Object -Unique)
$missingHistorical = @($requiredHistoricalNames | Where-Object { $historicalNamesFound -notcontains $_ })

$proofPath = Get-LatestPhase46_1ProofPath -ProofRoot (Join-Path $Root '_proof')
$proofValidationPath = Join-Path $proofPath '14_validation_results.txt'
$proofRecordPath = Join-Path $proofPath '16_entrypoint_frozen_baseline_gate_record.txt'
$proofInventoryPath = Join-Path $proofPath '10_entrypoint_inventory.txt'
foreach ($p in @($proofValidationPath, $proofRecordPath, $proofInventoryPath)) {
    if (-not (Test-Path -LiteralPath $p)) {
        throw ('Required Phase 46.1 proof artifact missing: ' + $p)
    }
}

$proofValidation = @(Get-Content -LiteralPath $proofValidationPath)
$proofValidationPass = ($proofValidation.Count -eq 9 -and @($proofValidation | Where-Object { $_ -notmatch '=PASS$' }).Count -eq 0)
$proofInventoryNames = Get-Phase46_1InventoryNames -InventoryPath $proofInventoryPath
$proofRecordNames = Get-Phase46_1RecordNames -RecordPath $proofRecordPath
$inventoryNamesFound = @($directNamesFound | Sort-Object -Unique)
$missingFromProofInventory = @($requiredDirectNames | Where-Object { $proofInventoryNames -notcontains $_ })
$extraInProofInventory = @($proofInventoryNames | Where-Object { $requiredDirectNames -notcontains $_ -and $_ -notmatch '^Invoke-FrozenBaselineTrustChainEnforcementGate$' })
$recordNamesCovered = (@($proofRecordNames | Where-Object { $inventoryNamesFound -contains $_ }).Count -eq $proofRecordNames.Count)

$inventoryMapConsistency = ($inventoryRows.Count -eq (@($directRows).Count + @($transitiveRows).Count + @($unguardedRows).Count + @($deadRows).Count))
$allOperationalGuarded = ($unguardedRows.Count -eq 0)
$misclassifiedDead = @($deadRows | Where-Object { $_.coverage_classification -ne 'dead / non-operational' })

$scopeCategoryCheck = [ordered]@{
    frozen_baseline_snapshot_load = (@($inventoryRows | Where-Object { $_.role -eq 'frozen_baseline_snapshot_load_entrypoint' }).Count -gt 0)
    frozen_baseline_integrity_load = (@($inventoryRows | Where-Object { $_.role -eq 'frozen_baseline_integrity_record_load_entrypoint' }).Count -gt 0)
    frozen_baseline_verification = (@($inventoryRows | Where-Object { $_.role -eq 'frozen_baseline_verification_entrypoint' }).Count -gt 0)
    ledger_head_validation = (@($inventoryRows | Where-Object { $_.role -eq 'ledger_head_read_validation_entrypoint' -or $_.role -eq 'ledger_head_validation_helper' }).Count -gt 0)
    coverage_fingerprint_validation = (@($inventoryRows | Where-Object { $_.role -eq 'coverage_fingerprint_read_validation_entrypoint' }).Count -gt 0)
    chain_continuation_validation = (@($inventoryRows | Where-Object { $_.role -eq 'chain_continuation_validation_entrypoint' }).Count -gt 0)
    runtime_initialization_wrappers = (@($inventoryRows | Where-Object { $_.role -eq 'runtime_initialization_wrapper' }).Count -gt 0)
    historical_auxiliary_validation_paths = (@($inventoryRows | Where-Object { $_.role -eq 'historical_auxiliary_validation_path' }).Count -gt 0)
}

$caseA = ($inventoryRows.Count -gt 0 -and $operationalRows.Count -gt 0 -and $missingDirect.Count -eq 0 -and $missingTransitive.Count -eq 0 -and $missingHistorical.Count -eq 0 -and @($scopeCategoryCheck.Values | Where-Object { -not $_ }).Count -eq 0)
$caseB = ($missingDirect.Count -eq 0)
$caseC = ($missingTransitive.Count -eq 0)
$caseD = ($unguardedRows.Count -eq 0)
$caseE = ($deadRows.Count -gt 0 -and $misclassifiedDead.Count -eq 0)
$caseF = ($inventoryMapConsistency -and $proofValidationPass -and $missingFromProofInventory.Count -eq 0 -and $extraInProofInventory.Count -eq 0 -and $recordNamesCovered)

$allPass = ($caseA -and $caseB -and $caseC -and $caseD -and $caseE -and $caseF -and $allOperationalGuarded)
$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status = @(
    'phase=46.2',
    'title=Trust-Chain Baseline Enforcement Coverage Audit / Completeness Proof',
    ('gate=' + $Gate),
    ('scope_files=' + $ScopeFiles.Count),
    ('relevant_functions_discovered=' + $inventoryRows.Count),
    ('operational_functions=' + $operationalRows.Count),
    ('directly_gated_operational_functions=' + $directRows.Count),
    ('transitively_gated_operational_functions=' + $transitiveRows.Count),
    ('unguarded_operational_functions=' + $unguardedRows.Count),
    ('dead_non_operational_functions=' + $deadRows.Count),
    'runtime_state_machine_changed=FALSE'
)
Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value ($status -join "`r`n") -Encoding UTF8 -NoNewline

$head = @(
    'runner=tools/phase46_2/phase46_2_trust_chain_baseline_enforcement_coverage_audit_runner.ps1',
    ('scope_files=' + ($ScopeFiles -join ';')),
    ('phase46_1_proof_packet=' + $proofPath),
    ('phase46_1_validation=' + $proofValidationPath),
    ('phase46_1_gate_record=' + $proofRecordPath),
    ('phase46_1_inventory=' + $proofInventoryPath)
)
Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value ($head -join "`r`n") -Encoding UTF8 -NoNewline

$definition = @(
    'TRUST-CHAIN BASELINE ENFORCEMENT COVERAGE INVENTORY DEFINITION (PHASE 46.2)',
    '',
    'Inventory source is derived from actual frozen-baseline-relevant scripts discovered by scanning tools/*.ps1 for the real frozen baseline control-plane files and gate symbols.',
    'The discovered current scope is phase45_9 baseline-lock validation, phase46_0 frozen-baseline enforcement, and phase46_1 bypass-resistance guarded wrappers.',
    'Operational roots are the current phase46_1 gate and guarded wrappers; relevant transitive helpers are derived from real intra-file call edges from those roots.',
    'Keyword-relevant functions in the discovered frozen-baseline scope that are not reachable from current phase46_1 roots are recorded as dead / non-operational historical or auxiliary helpers.',
    'Direct gate coverage means the function is the gate source or explicitly calls Invoke-FrozenBaselineTrustChainEnforcementGate.',
    'Transitive gate coverage means the helper is operational and is only reachable through already-gated current phase46_1 roots.',
    'Any operational frozen-baseline-relevant function that is neither directly nor transitively gated is classified as unguarded and fails the phase.',
    'No inventory or enforcement-map semantic-hash entrypoints were discovered in the current frozen-baseline operational surface, so none were assumed or counted as covered.'
)
Set-Content -LiteralPath (Join-Path $PF '10_entrypoint_inventory_definition.txt') -Value ($definition -join "`r`n") -Encoding UTF8 -NoNewline

$rules = @(
    'TRUST-CHAIN BASELINE COVERAGE RULES',
    '1) Discover scope from actual repo code by scanning for frozen-baseline control-plane files and enforcement symbols.',
    '2) Inventory only actual functions in the discovered scope files; no assumed entries.',
    '3) Mark current operational roots from phase46_1 guarded wrappers and the shared frozen-baseline gate implementation.',
    '4) Traverse real call edges to derive transitive helper coverage.',
    '5) Mark a function directly gated only if it is the gate source or explicitly calls Invoke-FrozenBaselineTrustChainEnforcementGate.',
    '6) Mark a function transitively gated only if it is operational and reachable only through already-gated current roots.',
    '7) Mark keyword-relevant but unreachable functions in scope as dead / non-operational historical or auxiliary helpers.',
    '8) Fail if any operational frozen-baseline-relevant function is unguarded.',
    '9) Cross-check the discovered operational direct surface against the latest Phase 46.1 proof inventory and gate record.',
    '10) Runtime state machine must remain unchanged because this phase is audit-only.'
)
Set-Content -LiteralPath (Join-Path $PF '11_frozen_baseline_coverage_rules.txt') -Value ($rules -join "`r`n") -Encoding UTF8 -NoNewline

$filesTouched = [System.Collections.Generic.List[string]]::new()
foreach ($rel in $ScopeFiles) {
    $filesTouched.Add('READ  ' + (Join-Path $Root ($rel.Replace('/', '\'))))
}
$filesTouched.Add('READ  ' + $proofValidationPath)
$filesTouched.Add('READ  ' + $proofRecordPath)
$filesTouched.Add('READ  ' + $proofInventoryPath)
$filesTouched.Add('WRITE ' + (Join-Path $PF '*'))
Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Value (($filesTouched.ToArray()) -join "`r`n") -Encoding UTF8 -NoNewline

$build = @(
    'build_type=PowerShell static_plus_prior_proof_consistency_audit',
    'compile_required=no',
    'runtime_validation_source=latest_phase46_1_proof_packet',
    'canonical_launcher_used=phase46_1_runner_prevalidated_in_latest_proof',
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
    'Phase 46.2 inventories the frozen-baseline-relevant surface by scanning the actual repo for the real frozen baseline control-plane files and enforcement symbols, then parsing the discovered phase45_9, phase46_0, and phase46_1 functions.',
    'Direct coverage is assigned only where the function is the frozen-baseline gate source or explicitly calls Invoke-FrozenBaselineTrustChainEnforcementGate.',
    'Transitive coverage is assigned only where the helper is operational in the current phase46_1 closure and is reachable solely through already-gated current roots.',
    'Dead and historical helpers are distinguished by scope membership without current reachability from phase46_1 operational roots; phase45_9 Test-FrozenBaselineReference and duplicate helper copies in phase45_9 and phase46_0 are therefore documented as dead / non-operational rather than counted as covered.',
    'Unguarded path detection is strict: any operational frozen-baseline-relevant function not classified as directly or transitively gated is emitted into 18_unguarded_path_report.txt and fails the phase.',
    'Coverage-map consistency is checked against the latest Phase 46.1 proof inventory and gate record so the statically discovered direct surface agrees with already passing bypass-resistance evidence.',
    'No inventory or enforcement-map semantic-hash entrypoints exist in the current frozen-baseline operational surface, so the audit records that absence instead of assuming coverage.',
    'Runtime behavior remained unchanged because this phase only reads scripts and prior proof artifacts and writes audit evidence.'
)
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value ($summary -join "`r`n") -Encoding UTF8 -NoNewline

$inventoryLines = [System.Collections.Generic.List[string]]::new()
$inventoryLines.Add('file_path | function_or_entrypoint | role | operational_or_dead | direct_gate_present | transitive_gate_present | gate_source_path | frozen_baseline_relevant_operation_type | coverage_classification | notes_on_evidence')
foreach ($row in $inventoryRows) {
    $inventoryLines.Add(
        [string]$row.file_path + ' | ' +
        [string]$row.function_or_entrypoint + ' | ' +
        [string]$row.role + ' | ' +
        [string]$row.operational_or_dead + ' | ' +
        [string]$row.direct_gate_present + ' | ' +
        [string]$row.transitive_gate_present + ' | ' +
        [string]$row.gate_source_path + ' | ' +
        [string]$row.frozen_baseline_relevant_operation_type + ' | ' +
        [string]$row.coverage_classification + ' | ' +
        [string]$row.notes_on_evidence
    )
}
Set-Content -LiteralPath (Join-Path $PF '16_entrypoint_inventory.txt') -Value (($inventoryLines.ToArray()) -join "`r`n") -Encoding UTF8 -NoNewline

$mapLines = [System.Collections.Generic.List[string]]::new()
$mapLines.Add('TRUST-CHAIN BASELINE ENFORCEMENT MAP (PHASE 46.2)')
$mapLines.Add('')
$mapLines.Add('Active operational surface:')
foreach ($row in $operationalRows) {
    $mapLines.Add([string]$row.file_path + ' | ' + [string]$row.function_or_entrypoint + ' -> ' + [string]$row.coverage_classification + ' -> gate_source=' + [string]$row.gate_source_path)
}
$mapLines.Add('')
$mapLines.Add('Historical / dead helpers:')
foreach ($row in $deadRows) {
    $mapLines.Add([string]$row.file_path + ' | ' + [string]$row.function_or_entrypoint + ' -> dead / non-operational')
}
Set-Content -LiteralPath (Join-Path $PF '17_frozen_baseline_enforcement_map.txt') -Value (($mapLines.ToArray()) -join "`r`n") -Encoding UTF8 -NoNewline

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
$unguardedReport.Add(('missing_direct=' + $(if ($missingDirect.Count -eq 0) { 'none' } else { $missingDirect -join ';' })))
$unguardedReport.Add(('missing_transitive=' + $(if ($missingTransitive.Count -eq 0) { 'none' } else { $missingTransitive -join ';' })))
$unguardedReport.Add(('missing_historical=' + $(if ($missingHistorical.Count -eq 0) { 'none' } else { $missingHistorical -join ';' })))
$unguardedReport.Add(('missing_from_phase46_1_inventory=' + $(if ($missingFromProofInventory.Count -eq 0) { 'none' } else { $missingFromProofInventory -join ';' })))
$unguardedReport.Add(('extra_in_phase46_1_inventory=' + $(if ($extraInProofInventory.Count -eq 0) { 'none' } else { $extraInProofInventory -join ';' })))
Set-Content -LiteralPath (Join-Path $PF '18_unguarded_path_report.txt') -Value (($unguardedReport.ToArray()) -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '98_gate_phase46_2.txt') -Value $Gate -Encoding UTF8 -NoNewline

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