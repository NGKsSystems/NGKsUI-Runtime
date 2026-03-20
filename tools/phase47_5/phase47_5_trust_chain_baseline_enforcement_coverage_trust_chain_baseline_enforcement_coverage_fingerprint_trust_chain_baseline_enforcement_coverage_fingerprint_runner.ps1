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

    if ($Value -is [System.Collections.IDictionary] -or $Value -is [pscustomobject]) {
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

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $items = [System.Collections.Generic.List[string]]::new()
        foreach ($item in $Value) {
            $items.Add((Convert-ToCanonicalJson -Value $item))
        }
        $sorted = @($items.ToArray() | Sort-Object)
        return '[' + ($sorted -join ',') + ']'
    }

    return (($Value | ConvertTo-Json -Compress))
}

function Convert-TextToLines {
    param([string]$Text)
    if ($null -eq $Text) { return @() }
    return @($Text -split "`r?`n")
}

function Get-LatestPhase47_4ProofPath {
    param([string]$ProofRoot)

    $dirs = @(Get-ChildItem -LiteralPath $ProofRoot -Directory | Where-Object {
        $_.Name -like 'phase47_4_trust_chain_baseline_enforcement_coverage_trust_chain_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_coverage_audit_*'
    } | Sort-Object Name)

    if ($dirs.Count -eq 0) {
        throw 'No Phase 47.4 proof packet found under _proof.'
    }

    return $dirs[$dirs.Count - 1].FullName
}

function ConvertFrom-PipeTableText {
    param([string]$Text)

    $lines = Convert-TextToLines -Text $Text
    $content = @($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($content.Count -eq 0) {
        throw 'Pipe table text is empty.'
    }

    $header = @($content[0] -split '\|' | ForEach-Object { $_.Trim() })
    $rows = [System.Collections.Generic.List[object]]::new()

    for ($i = 1; $i -lt $content.Count; $i++) {
        $line = [string]$content[$i]
        $parts = @($line -split '\|')
        if ($parts.Count -lt $header.Count) {
            continue
        }

        $obj = [ordered]@{}
        for ($c = 0; $c -lt $header.Count; $c++) {
            $obj[$header[$c]] = ([string]$parts[$c]).Trim()
        }
        $rows.Add($obj)
    }

    return [ordered]@{
        header = $header
        rows = @($rows)
    }
}

function Get-CoverageFingerprintMaterial {
    param(
        [string]$InventoryText,
        [string]$MapText,
        [string]$UnguardedText,
        [string]$BypassCrosscheckText
    )

    $invTable = ConvertFrom-PipeTableText -Text $InventoryText
    $mapTable = ConvertFrom-PipeTableText -Text $MapText
    $ungTable = ConvertFrom-PipeTableText -Text $UnguardedText

    $invRows = @($invTable.rows)
    $mapRows = @($mapTable.rows)
    $ungRows = @($ungTable.rows)

    $operationalInventory = [System.Collections.Generic.List[object]]::new()
    foreach ($r in $invRows) {
        if ([string]$r.operational_or_dead -ne 'operational') {
            continue
        }

        $operationalInventory.Add([ordered]@{
            file_path = [string]$r.file_path
            function_or_entrypoint = [string]$r.function_or_entrypoint
            role = [string]$r.role
            operational_or_dead = [string]$r.operational_or_dead
            direct_gate_present = [string]$r.direct_gate_present
            transitive_gate_present = [string]$r.transitive_gate_present
            gate_source_path = [string]$r.gate_source_path
            operation_type = [string]$r.frozen_baseline_relevant_operation_type
            coverage_classification = [string]$r.coverage_classification
        })
    }

    $operationalMap = [System.Collections.Generic.List[object]]::new()
    foreach ($r in $mapRows) {
        if ([string]$r.operational_or_dead -ne 'operational') {
            continue
        }

        $operationalMap.Add([ordered]@{
            function_or_entrypoint = [string]$r.function_or_entrypoint
            coverage_classification = [string]$r.coverage_classification
            gate_source_path = [string]$r.gate_source_path
            role = [string]$r.role
            operational_or_dead = [string]$r.operational_or_dead
        })
    }

    $unguardedSemantics = [ordered]@{
        has_unguarded_operational_path = $false
        unguarded_paths = @()
    }

    if ($ungRows.Count -eq 1 -and [string]$ungRows[0].function_or_entrypoint -eq 'NONE') {
        $unguardedSemantics.has_unguarded_operational_path = $false
        $unguardedSemantics.unguarded_paths = @()
    } else {
        $paths = [System.Collections.Generic.List[object]]::new()
        foreach ($r in $ungRows) {
            $paths.Add([ordered]@{
                file_path = [string]$r.file_path
                function_or_entrypoint = [string]$r.function_or_entrypoint
                role = [string]$r.role
                operation_type = [string]$r.operation_type
            })
        }
        $unguardedSemantics.has_unguarded_operational_path = ($paths.Count -gt 0)
        $unguardedSemantics.unguarded_paths = @($paths)
    }

    $crossKeyValues = [ordered]@{}
    $missingEntries = [System.Collections.Generic.List[string]]::new()
    $inMissingSection = $false

    foreach ($lineRaw in (Convert-TextToLines -Text $BypassCrosscheckText)) {
        $line = [string]$lineRaw
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $trim = $line.Trim()

        if ($trim -eq 'missing_entries:') {
            $inMissingSection = $true
            continue
        }

        if ($inMissingSection) {
            if ($trim -like '*=*') {
                $inMissingSection = $false
            } else {
                $missingEntries.Add($trim)
                continue
            }
        }

        if ($trim -like '*=*') {
            $parts = @($trim -split '=', 2)
            $k = $parts[0].Trim()
            $v = $parts[1].Trim()
            switch ($k) {
                'phase47_3_gate' { $crossKeyValues[$k] = $v }
                'phase47_3_inventory_count' { $crossKeyValues[$k] = $v }
                'phase47_3_gate_record_count' { $crossKeyValues[$k] = $v }
                'crosscheck_union_count' { $crossKeyValues[$k] = $v }
                'missing_in_phase47_4_map' { $crossKeyValues[$k] = $v }
                'bypass_rows_with_allowed_in_B_to_J' { $crossKeyValues[$k] = $v }
                'normal_rows_blocked_in_A' { $crossKeyValues[$k] = $v }
                'bypass_crosscheck' { $crossKeyValues[$k] = $v }
            }
        }
    }

    $bypassSemantics = [ordered]@{
        key_values = $crossKeyValues
        missing_entries = @($missingEntries | Sort-Object -Unique)
    }

    $model = [ordered]@{
        model_version = 'phase47_5_coverage_fingerprint_v1'
        operational_inventory = @($operationalInventory)
        operational_enforcement_map = @($operationalMap)
        unguarded_path_semantics = $unguardedSemantics
        bypass_crosscheck_semantics = $bypassSemantics
    }

    $invCanonical = Convert-ToCanonicalJson -Value $model.operational_inventory
    $mapCanonical = Convert-ToCanonicalJson -Value $model.operational_enforcement_map
    $ungCanonical = Convert-ToCanonicalJson -Value $model.unguarded_path_semantics
    $crossCanonical = Convert-ToCanonicalJson -Value $model.bypass_crosscheck_semantics
    $modelCanonical = Convert-ToCanonicalJson -Value $model

    return [ordered]@{
        model = $model
        canonical = [ordered]@{
            inventory = $invCanonical
            enforcement_map = $mapCanonical
            unguarded = $ungCanonical
            bypass_crosscheck = $crossCanonical
            model = $modelCanonical
        }
        hashes = [ordered]@{
            inventory_sha256 = Get-StringSha256Hex -Text $invCanonical
            enforcement_map_sha256 = Get-StringSha256Hex -Text $mapCanonical
            unguarded_sha256 = Get-StringSha256Hex -Text $ungCanonical
            bypass_crosscheck_sha256 = Get-StringSha256Hex -Text $crossCanonical
            model_sha256 = Get-StringSha256Hex -Text $modelCanonical
        }
        fingerprint = Get-StringSha256Hex -Text $modelCanonical
    }
}

function Set-ReferenceArtifact {
    param(
        [string]$ReferencePath,
        [string]$SourceProofPath,
        [object]$Material
    )

    $obj = [ordered]@{
        phase_locked = '47.5'
        source_phase = '47.4'
        fingerprint_type = 'trust_chain_baseline_enforcement_coverage_fingerprint'
        coverage_fingerprint_sha256 = [string]$Material.fingerprint
        canonical_input_hashes = [ordered]@{
            inventory_sha256 = [string]$Material.hashes.inventory_sha256
            enforcement_map_sha256 = [string]$Material.hashes.enforcement_map_sha256
            unguarded_sha256 = [string]$Material.hashes.unguarded_sha256
            bypass_crosscheck_sha256 = [string]$Material.hashes.bypass_crosscheck_sha256
            model_sha256 = [string]$Material.hashes.model_sha256
        }
        source_proof_path = $SourceProofPath
        source_artifacts = @(
            '16_entrypoint_inventory.txt',
            '17_frozen_baseline_enforcement_map.txt',
            '18_unguarded_path_report.txt',
            '19_bypass_crosscheck_report.txt'
        )
        generated_utc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }

    ($obj | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $ReferencePath -Encoding UTF8 -NoNewline
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof/phase47_5_trust_chain_baseline_enforcement_coverage_trust_chain_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint_' + $Timestamp)
New-Item -ItemType Directory -Path $PF -Force | Out-Null

$Phase47_4Proof = Get-LatestPhase47_4ProofPath -ProofRoot (Join-Path $Root '_proof')
$InvPath = Join-Path $Phase47_4Proof '16_entrypoint_inventory.txt'
$MapPath = Join-Path $Phase47_4Proof '17_frozen_baseline_enforcement_map.txt'
$UngPath = Join-Path $Phase47_4Proof '18_unguarded_path_report.txt'
$CrossPath = Join-Path $Phase47_4Proof '19_bypass_crosscheck_report.txt'

foreach ($p in @($InvPath, $MapPath, $UngPath, $CrossPath)) {
    if (-not (Test-Path -LiteralPath $p)) {
        throw ('Required Phase 47.4 artifact missing: ' + $p)
    }
}

$invText = Get-Content -Raw -LiteralPath $InvPath
$mapText = Get-Content -Raw -LiteralPath $MapPath
$ungText = Get-Content -Raw -LiteralPath $UngPath
$crossText = Get-Content -Raw -LiteralPath $CrossPath

$base1 = Get-CoverageFingerprintMaterial -InventoryText $invText -MapText $mapText -UnguardedText $ungText -BypassCrosscheckText $crossText
$base2 = Get-CoverageFingerprintMaterial -InventoryText $invText -MapText $mapText -UnguardedText $ungText -BypassCrosscheckText $crossText
if ([string]$base1.fingerprint -ne [string]$base2.fingerprint) {
    throw 'Determinism check failed: repeated clean generation mismatch.'
}

$ReferencePath = Join-Path $Root 'control_plane/85_trust_chain_baseline_enforcement_coverage_trust_chain_baseline_enforcement_coverage_fingerprint.json'
Set-ReferenceArtifact -ReferencePath $ReferencePath -SourceProofPath $Phase47_4Proof -Material $base1
$storedRef = Get-Content -Raw -LiteralPath $ReferencePath | ConvertFrom-Json
$storedFingerprint = [string]$storedRef.coverage_fingerprint_sha256

$results = [System.Collections.Generic.List[object]]::new()

function Add-CaseResult {
    param(
        [string]$CaseId,
        [string]$CaseName,
        [string]$ComputedFingerprint,
        [string]$StoredFingerprint,
        [string]$DetectedChangeType,
        [bool]$ExpectChanged,
        [bool]$ReferenceSaved
    )

    $isChanged = ([string]$ComputedFingerprint -ne [string]$StoredFingerprint)
    $matchStatus = if ($isChanged) { 'MISMATCH' } else { 'MATCH' }
    $expectedStatus = if ($ExpectChanged) { 'CHANGED' } else { 'UNCHANGED' }
    $actualStatus = if ($isChanged) { 'CHANGED' } else { 'UNCHANGED' }
    $ok = ($expectedStatus -eq $actualStatus)

    $results.Add([ordered]@{
        case_id = $CaseId
        case_name = $CaseName
        computed_fingerprint = $ComputedFingerprint
        stored_reference_fingerprint = $StoredFingerprint
        fingerprint_match_status = $matchStatus
        detected_change_type = $DetectedChangeType
        expected_status = $expectedStatus
        actual_status = $actualStatus
        reference_saved = $(if ($ReferenceSaved) { 'TRUE' } else { 'FALSE' })
        regression_detected = $(if ($isChanged) { 'TRUE' } else { 'FALSE' })
        certification_allowed_or_blocked = $(if ($ok) { 'ALLOWED' } else { 'BLOCKED' })
    })
}

# CASE A
Add-CaseResult -CaseId 'A' -CaseName 'CLEAN FINGERPRINT GENERATION' -ComputedFingerprint $base1.fingerprint -StoredFingerprint $storedFingerprint -DetectedChangeType 'clean_generation' -ExpectChanged $false -ReferenceSaved $true

# CASE B: non-semantic formatting changes
$invTextB = "`n  " + ($invText -replace '\|', ' | ') + "`n"
$mapTextB = "`n" + ($mapText -replace '\|', '  |  ') + "`n"
$b = Get-CoverageFingerprintMaterial -InventoryText $invTextB -MapText $mapTextB -UnguardedText $ungText -BypassCrosscheckText $crossText
Add-CaseResult -CaseId 'B' -CaseName 'NON-SEMANTIC CHANGE' -ComputedFingerprint $b.fingerprint -StoredFingerprint $storedFingerprint -DetectedChangeType 'formatting_only' -ExpectChanged $false -ReferenceSaved $false

# CASE C: entrypoint addition
$invTextC = $invText.TrimEnd() + "`r`ntools/phase47_3/phase47_3_trust_chain_baseline_enforcement_coverage_trust_chain_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_bypass_resistance_runner.ps1|Invoke-GuardedSyntheticEntrypoint|runtime_initialization_wrapper|operational|yes|no|Test-Phase47_2FrozenBaselineGate via Invoke-GuardedOperation model|runtime_init_wrapper|directly gated|synthetic_case_c_addition"
$mapTextC = $mapText.TrimEnd() + "`r`nInvoke-GuardedSyntheticEntrypoint|directly gated|Test-Phase47_2FrozenBaselineGate via Invoke-GuardedOperation model|runtime_initialization_wrapper|operational"
$c = Get-CoverageFingerprintMaterial -InventoryText $invTextC -MapText $mapTextC -UnguardedText $ungText -BypassCrosscheckText $crossText
Add-CaseResult -CaseId 'C' -CaseName 'ENTRYPOINT ADDITION' -ComputedFingerprint $c.fingerprint -StoredFingerprint $storedFingerprint -DetectedChangeType 'entrypoint_addition' -ExpectChanged $true -ReferenceSaved $false

# CASE D: coverage classification change
$invTextD = $invText -replace '\|directly gated\|', '|transitively gated|'
$d = Get-CoverageFingerprintMaterial -InventoryText $invTextD -MapText $mapText -UnguardedText $ungText -BypassCrosscheckText $crossText
Add-CaseResult -CaseId 'D' -CaseName 'COVERAGE CLASSIFICATION CHANGE' -ComputedFingerprint $d.fingerprint -StoredFingerprint $storedFingerprint -DetectedChangeType 'coverage_classification_change' -ExpectChanged $true -ReferenceSaved $false

# CASE E: order change
$invLinesE = Convert-TextToLines -Text $invText
$headerE = $invLinesE[0]
$dataE = @($invLinesE | Select-Object -Skip 1 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
[array]::Reverse($dataE)
$invTextE = $headerE + "`r`n" + ($dataE -join "`r`n")
$e = Get-CoverageFingerprintMaterial -InventoryText $invTextE -MapText $mapText -UnguardedText $ungText -BypassCrosscheckText $crossText
Add-CaseResult -CaseId 'E' -CaseName 'ORDER CHANGE' -ComputedFingerprint $e.fingerprint -StoredFingerprint $storedFingerprint -DetectedChangeType 'row_order_only' -ExpectChanged $false -ReferenceSaved $false

# CASE F: dead helper cosmetic change only
$invTextF = $invText -replace 'Get-NextEntryId\|helper\|dead / non-operational', 'Get-NextEntryId|helper_cosmetic|dead / non-operational'
$f = Get-CoverageFingerprintMaterial -InventoryText $invTextF -MapText $mapText -UnguardedText $ungText -BypassCrosscheckText $crossText
Add-CaseResult -CaseId 'F' -CaseName 'DEAD HELPER CHANGE' -ComputedFingerprint $f.fingerprint -StoredFingerprint $storedFingerprint -DetectedChangeType 'dead_helper_cosmetic_only' -ExpectChanged $false -ReferenceSaved $false

# CASE G: unguarded-path report semantic change
$ungTextG = "file_path|function_or_entrypoint|role|operation_type|notes`r`ntools/phase47_3/phase47_3_trust_chain_baseline_enforcement_coverage_trust_chain_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_bypass_resistance_runner.ps1|Invoke-GuardedRuntimeInitWrapper|runtime_initialization_wrapper|runtime_init_wrapper|simulated_unguarded_path"
$g = Get-CoverageFingerprintMaterial -InventoryText $invText -MapText $mapText -UnguardedText $ungTextG -BypassCrosscheckText $crossText
Add-CaseResult -CaseId 'G' -CaseName 'UNGUARDED PATH REPORT CHANGE' -ComputedFingerprint $g.fingerprint -StoredFingerprint $storedFingerprint -DetectedChangeType 'unguarded_path_semantic_change' -ExpectChanged $true -ReferenceSaved $false

# CASE H: operational/dead reclassification
$invTextH = $invText -replace '\|Invoke-GuardedRuntimeInitWrapper\|runtime_initialization_wrapper\|operational\|', '|Invoke-GuardedRuntimeInitWrapper|runtime_initialization_wrapper|dead / non-operational|'
$h = Get-CoverageFingerprintMaterial -InventoryText $invTextH -MapText $mapText -UnguardedText $ungText -BypassCrosscheckText $crossText
Add-CaseResult -CaseId 'H' -CaseName 'OPERATIONAL/DEAD RECLASSIFICATION' -ComputedFingerprint $h.fingerprint -StoredFingerprint $storedFingerprint -DetectedChangeType 'operational_dead_reclassification' -ExpectChanged $true -ReferenceSaved $false

# CASE I: bypass cross-check semantic change
$crossTextI = $crossText -replace 'missing_in_phase47_4_map=0', 'missing_in_phase47_4_map=1'
$i = Get-CoverageFingerprintMaterial -InventoryText $invText -MapText $mapText -UnguardedText $ungText -BypassCrosscheckText $crossTextI
Add-CaseResult -CaseId 'I' -CaseName 'BYPASS CROSS-CHECK CHANGE' -ComputedFingerprint $i.fingerprint -StoredFingerprint $storedFingerprint -DetectedChangeType 'bypass_crosscheck_semantic_change' -ExpectChanged $true -ReferenceSaved $false

$failedCases = @($results | Where-Object { $_.certification_allowed_or_blocked -ne 'ALLOWED' })
$gateOverall = if ($failedCases.Count -eq 0) { 'PASS' } else { 'FAIL' }

$head = 'UNKNOWN'
try {
    $head = (git rev-parse HEAD).Trim()
} catch {
    $head = 'UNKNOWN'
}

@(
    'phase=47.5',
    'title=Trust-Chain Baseline Enforcement Coverage Trust-Chain Baseline Enforcement Coverage Fingerprint Trust-Chain Baseline Enforcement Coverage Fingerprint Lock',
    ('gate=' + $gateOverall),
    ('coverage_fingerprint=' + [string]$base1.fingerprint),
    'reference_saved=TRUE',
    'runtime_state_machine_changed=FALSE'
) | Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Encoding UTF8

@(
    ('HEAD=' + $head),
    ('runner=tools/phase47_5/phase47_5_trust_chain_baseline_enforcement_coverage_trust_chain_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint_runner.ps1'),
    ('phase47_4_proof=' + $Phase47_4Proof),
    ('reference_artifact=' + $ReferencePath)
) | Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Encoding UTF8

@(
    'definition=Deterministic semantic fingerprint over 47.4 operational coverage model',
    'input_artifacts=16_entrypoint_inventory.txt|17_frozen_baseline_enforcement_map.txt|18_unguarded_path_report.txt|19_bypass_crosscheck_report.txt',
    'canonicalization=pipe-table parse + trim + semantic projection + canonical json with sorted keys/items',
    'dead_helper_policy=dead/non-operational rows excluded from operational fingerprint core'
) | Set-Content -LiteralPath (Join-Path $PF '10_fingerprint_definition.txt') -Encoding UTF8

@(
    'rule_1=Whitespace/formatting/order-only changes do not change fingerprint',
    'rule_2=Operational entrypoint additions/removals change fingerprint',
    'rule_3=Coverage classification changes on protected operational paths change fingerprint',
    'rule_4=Operational/dead reclassification of real path changes fingerprint',
    'rule_5=Unguarded-path semantic change changes fingerprint',
    'rule_6=Bypass cross-check semantic change changes fingerprint'
) | Set-Content -LiteralPath (Join-Path $PF '11_fingerprint_rules.txt') -Encoding UTF8

@(
    'tools/phase47_5/phase47_5_trust_chain_baseline_enforcement_coverage_trust_chain_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint_runner.ps1',
    $InvPath,
    $MapPath,
    $UngPath,
    $CrossPath,
    $ReferencePath
) | Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Encoding UTF8

@(
    ('pwsh_version=' + $PSVersionTable.PSVersion.ToString()),
    ('determinism_check=' + $(if ($base1.fingerprint -eq $base2.fingerprint) { 'PASS' } else { 'FAIL' })),
    ('base_fingerprint=' + [string]$base1.fingerprint),
    ('inventory_sha256=' + [string]$base1.hashes.inventory_sha256),
    ('enforcement_map_sha256=' + [string]$base1.hashes.enforcement_map_sha256),
    ('unguarded_sha256=' + [string]$base1.hashes.unguarded_sha256),
    ('bypass_crosscheck_sha256=' + [string]$base1.hashes.bypass_crosscheck_sha256),
    ('case_count=' + $results.Count),
    ('failed_case_count=' + $failedCases.Count)
) | Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Encoding UTF8

$val = @('case_id|case_name|computed_fingerprint|stored_reference_fingerprint|fingerprint_match_status|detected_change_type|expected_status|actual_status|reference_saved|regression_detected|certification_allowed_or_blocked')
$val += $results | ForEach-Object {
    '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}' -f $_.case_id, $_.case_name, $_.computed_fingerprint, $_.stored_reference_fingerprint, $_.fingerprint_match_status, $_.detected_change_type, $_.expected_status, $_.actual_status, $_.reference_saved, $_.regression_detected, $_.certification_allowed_or_blocked
}
$val | Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Encoding UTF8

@(
    ('overall_gate=' + $gateOverall),
    'inventory_source=latest phase47.4 proof artifacts (16/17/18/19)',
    'semantic_model=operational inventory + operational map + unguarded semantics + bypass cross-check semantics',
    'direct_vs_transitive_signal=preserved via coverage_classification and gate flags in canonical inventory/map projections',
    'dead_helper_handling=excluded from operational fingerprint core to avoid cosmetic-only dead helper churn',
    'regression_detection=enabled via changed fingerprint on semantic mutations (C,D,G,H,I)',
    'stability=verified via unchanged fingerprint for formatting/order/dead-helper-cosmetic mutations (B,E,F)',
    'runtime_behavior_unchanged=TRUE (fingerprint lock only; no runtime gate wiring modified)'
) | Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Encoding UTF8

@(
    ('coverage_fingerprint_sha256=' + [string]$base1.fingerprint),
    ('stored_reference_fingerprint=' + $storedFingerprint),
    ('inventory_sha256=' + [string]$base1.hashes.inventory_sha256),
    ('enforcement_map_sha256=' + [string]$base1.hashes.enforcement_map_sha256),
    ('unguarded_sha256=' + [string]$base1.hashes.unguarded_sha256),
    ('bypass_crosscheck_sha256=' + [string]$base1.hashes.bypass_crosscheck_sha256),
    ('model_sha256=' + [string]$base1.hashes.model_sha256)
) | Set-Content -LiteralPath (Join-Path $PF '16_coverage_fingerprint_record.txt') -Encoding UTF8

$evidence = @('case_id|detected_change_type|expected_status|actual_status|regression_detected|certification_allowed_or_blocked')
$evidence += $results | ForEach-Object {
    '{0}|{1}|{2}|{3}|{4}|{5}' -f $_.case_id, $_.detected_change_type, $_.expected_status, $_.actual_status, $_.regression_detected, $_.certification_allowed_or_blocked
}
$evidence | Set-Content -LiteralPath (Join-Path $PF '17_regression_detection_evidence.txt') -Encoding UTF8

@($gateOverall) | Set-Content -LiteralPath (Join-Path $PF '98_gate_phase47_5.txt') -Encoding UTF8

$zipPath = $PF + '.zip'
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $PF '*') -DestinationPath $zipPath -Force

Write-Output ('PF=' + $PF)
Write-Output ('ZIP=' + $zipPath)
Write-Output ('GATE=' + $gateOverall)
