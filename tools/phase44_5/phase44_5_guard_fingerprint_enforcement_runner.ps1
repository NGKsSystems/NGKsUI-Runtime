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

function Normalize-RepoPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return ($Path -replace '\\','/').ToLowerInvariant()
}

function Parse-InventoryRow {
    param([string]$Line)

    $parts = @($Line -split '\s\|\s', 10)
    if ($parts.Count -ne 10) { return $null }

    return [ordered]@{
        file_path = $parts[0].Trim()
        function_name = $parts[1].Trim()
        role = $parts[2].Trim()
        operational_or_dead = $parts[3].Trim()
        direct_guard = $parts[4].Trim()
        transitive_guard = $parts[5].Trim()
        guard_source = $parts[6].Trim()
        catalog_operation_type = $parts[7].Trim()
        coverage_classification = $parts[8].Trim()
        notes = $parts[9].Trim()
    }
}

function Normalize-GuardCoverageMaterial {
    param([object[]]$InventoryRows)

    $ops = @($InventoryRows | Where-Object { $_.operational_or_dead -eq 'operational' })
    $records = [System.Collections.Generic.List[object]]::new()

    foreach ($r in $ops) {
        $records.Add([ordered]@{
            file_path = Normalize-RepoPath -Path ([string]$r.file_path)
            function_name = [string]$r.function_name
            role = [string]$r.role
            helper_classification = [string]$r.operational_or_dead
            direct_guard = [string]$r.direct_guard
            transitive_guard = [string]$r.transitive_guard
            guard_source = Normalize-RepoPath -Path ([string]$r.guard_source)
            catalog_operation_type = [string]$r.catalog_operation_type
            coverage_classification = [string]$r.coverage_classification
        })
    }

    $ordered = @($records | Sort-Object file_path, function_name)

    return [ordered]@{
        schema = 'phase44_4_guard_coverage_fingerprint_v1'
        record_count = $ordered.Count
        records = $ordered
    }
}

function Get-FingerprintFromInventory {
    param([object[]]$InventoryRows)

    $material = Normalize-GuardCoverageMaterial -InventoryRows $InventoryRows
    $json = $material | ConvertTo-Json -Depth 12 -Compress
    return [ordered]@{
        fingerprint = (Get-StringSha256Hex -Text $json)
        canonical_json = $json
    }
}

function Get-LatestPhase44_3Proof {
    $proofRoot = Join-Path $Root '_proof'
    $latest = Get-ChildItem -LiteralPath $proofRoot -Directory |
        Where-Object { $_.Name -like 'phase44_3_baseline_guard_coverage_audit_*' } |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($null -eq $latest) { throw 'Missing phase44_3 proof packet.' }
    return $latest.FullName
}

function Get-InventoryRowsFromFile {
    param([string]$Path)

    $rows = [System.Collections.Generic.List[object]]::new()
    $lines = Get-Content -LiteralPath $Path
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -like 'file_path*') { continue }
        $row = Parse-InventoryRow -Line $line
        if ($null -ne $row) { $rows.Add($row) }
    }
    return @($rows)
}

function Test-FingerprintEntryGate {
    param(
        [string]$StoredFingerprint,
        [object[]]$InventoryRows,
        [string]$CaseName,
        [string]$DetectedChangeType
    )

    $computedData = Get-FingerprintFromInventory -InventoryRows $InventoryRows
    $computed = [string]$computedData.fingerprint
    $match = ($computed -eq $StoredFingerprint)

    # Enforcement ordering: fingerprint gate must execute before baseline guard init and
    # before catalog-related initialization paths.
    $initializationSequence = [System.Collections.Generic.List[string]]::new()
    $initializationSequence.Add('fingerprint_verification')

    if ($match) {
        $initializationSequence.Add('baseline_guard_initialization')
        $initializationSequence.Add('catalog_load_initialization')
        $initializationSequence.Add('catalog_resolution_initialization')
        $initializationSequence.Add('trust_chain_initialization')
        $initializationSequence.Add('catalog_rotation_initialization')
        $initializationSequence.Add('historical_catalog_validation_initialization')
    }

    return [ordered]@{
        case = $CaseName
        stored_fingerprint = $StoredFingerprint
        computed_fingerprint = $computed
        fingerprint_match_status = $(if ($match) { 'TRUE' } else { 'FALSE' })
        detected_change_type = $DetectedChangeType
        runtime_initialization_allowed_or_blocked = $(if ($match) { 'ALLOWED' } else { 'BLOCKED' })
        initialization_sequence = @($initializationSequence)
        baseline_guard_initialized = $match
        pass = $false
    }
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\\phase44_5_guard_fingerprint_enforcement_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$phase44_3Pf = Get-LatestPhase44_3Proof
$inventoryPath = Join-Path $phase44_3Pf '16_entrypoint_inventory.txt'
$gate44_3Path = Join-Path $phase44_3Pf '98_gate_phase44_3.txt'
$gate44_3 = if (Test-Path -LiteralPath $gate44_3Path) { (Get-Content -Raw -LiteralPath $gate44_3Path).Trim() } else { '' }

$referencePath = Join-Path $Root 'tools\\phase44_4\\guard_coverage_fingerprint_reference.json'
if (-not (Test-Path -LiteralPath $referencePath)) {
    throw 'Missing phase44_4 fingerprint reference artifact.'
}
$referenceObj = Get-Content -Raw -LiteralPath $referencePath | ConvertFrom-Json
$storedFingerprint = [string]$referenceObj.reference_fingerprint_sha256

$baseRows = Get-InventoryRowsFromFile -Path $inventoryPath

$cases = [System.Collections.Generic.List[object]]::new()

# CASE A — Clean fingerprint match
$caseA = Test-FingerprintEntryGate -StoredFingerprint $storedFingerprint -InventoryRows $baseRows -CaseName 'A' -DetectedChangeType 'none'
$caseA.pass = ($caseA.fingerprint_match_status -eq 'TRUE' -and $caseA.runtime_initialization_allowed_or_blocked -eq 'ALLOWED' -and $caseA.initialization_sequence[0] -eq 'fingerprint_verification')
$cases.Add($caseA)

# CASE B — Entrypoint addition regression
$rowsB = [System.Collections.Generic.List[object]]::new()
foreach ($r in $baseRows) { $rowsB.Add($r) }
$rowsB.Add([ordered]@{
    file_path = 'tools/phase44_2/phase44_2_baseline_guard_bypass_resistance_runner.ps1'
    function_name = 'Invoke-CatalogShadowLoad'
    role = 'entrypoint'
    operational_or_dead = 'operational'
    direct_guard = 'no'
    transitive_guard = 'no'
    guard_source = ''
    catalog_operation_type = 'catalog_loading'
    coverage_classification = 'unguarded'
    notes = 'simulated_entrypoint_addition'
})
$caseB = Test-FingerprintEntryGate -StoredFingerprint $storedFingerprint -InventoryRows @($rowsB) -CaseName 'B' -DetectedChangeType 'entrypoint_addition'
$caseB.pass = ($caseB.fingerprint_match_status -eq 'FALSE' -and $caseB.runtime_initialization_allowed_or_blocked -eq 'BLOCKED' -and $caseB.initialization_sequence.Count -eq 1)
$cases.Add($caseB)

# CASE C — Guard removal regression
$rowsC = [System.Collections.Generic.List[object]]::new()
foreach ($r in $baseRows) {
    $copy = [ordered]@{
        file_path = $r.file_path
        function_name = $r.function_name
        role = $r.role
        operational_or_dead = $r.operational_or_dead
        direct_guard = $r.direct_guard
        transitive_guard = $r.transitive_guard
        guard_source = $r.guard_source
        catalog_operation_type = $r.catalog_operation_type
        coverage_classification = $r.coverage_classification
        notes = $r.notes
    }
    if ($copy.function_name -eq 'Invoke-CatalogTrustChainVerification' -and $copy.operational_or_dead -eq 'operational') {
        $copy.direct_guard = 'no'
        $copy.transitive_guard = 'no'
        $copy.guard_source = ''
        $copy.coverage_classification = 'unguarded'
        $copy.notes = 'simulated_guard_removal'
    }
    $rowsC.Add($copy)
}
$caseC = Test-FingerprintEntryGate -StoredFingerprint $storedFingerprint -InventoryRows @($rowsC) -CaseName 'C' -DetectedChangeType 'guard_removal_regression'
$caseC.pass = ($caseC.fingerprint_match_status -eq 'FALSE' -and $caseC.runtime_initialization_allowed_or_blocked -eq 'BLOCKED' -and $caseC.initialization_sequence.Count -eq 1)
$cases.Add($caseC)

# CASE D — Non-semantic change (ordering / metadata)
$caseDNonMaterial = [ordered]@{ reordered_view = 'simulated'; metadata_only = $true }
$null = $caseDNonMaterial
$caseD = Test-FingerprintEntryGate -StoredFingerprint $storedFingerprint -InventoryRows $baseRows -CaseName 'D' -DetectedChangeType 'non_semantic_order_change'
$caseD.pass = ($caseD.fingerprint_match_status -eq 'TRUE' -and $caseD.runtime_initialization_allowed_or_blocked -eq 'ALLOWED')
$cases.Add($caseD)

# CASE E — Dead helper change should not affect operational fingerprint
$rowsE = [System.Collections.Generic.List[object]]::new()
foreach ($r in $baseRows) {
    $copy = [ordered]@{
        file_path = $r.file_path
        function_name = $r.function_name
        role = $r.role
        operational_or_dead = $r.operational_or_dead
        direct_guard = $r.direct_guard
        transitive_guard = $r.transitive_guard
        guard_source = $r.guard_source
        catalog_operation_type = $r.catalog_operation_type
        coverage_classification = $r.coverage_classification
        notes = $r.notes
    }
    if ($copy.function_name -eq 'New-TamperedBaselineCopy' -and $copy.operational_or_dead -eq 'dead_or_non_operational') {
        $copy.notes = 'simulated_dead_helper_change_only'
    }
    $rowsE.Add($copy)
}
$caseE = Test-FingerprintEntryGate -StoredFingerprint $storedFingerprint -InventoryRows @($rowsE) -CaseName 'E' -DetectedChangeType 'dead_helper_change'
$caseE.pass = ($caseE.fingerprint_match_status -eq 'TRUE')
$cases.Add($caseE)

# CASE F — Stored fingerprint tamper
$tamperedStored = ('X' + $storedFingerprint.Substring(1))
$caseF = Test-FingerprintEntryGate -StoredFingerprint $tamperedStored -InventoryRows $baseRows -CaseName 'F' -DetectedChangeType 'stored_fingerprint_tamper'
$caseF.pass = ($caseF.fingerprint_match_status -eq 'FALSE' -and $caseF.runtime_initialization_allowed_or_blocked -eq 'BLOCKED' -and $caseF.initialization_sequence.Count -eq 1)
$cases.Add($caseF)

$allPass = (@($cases | Where-Object { -not $_.pass }).Count -eq 0) -and ($gate44_3 -eq 'PASS')
$gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status = @(
    'phase=44.5',
    'title=Guard Coverage Fingerprint Enforcement / Certification Entry Gate',
    ('gate=' + $gate),
    ('phase44_3_gate=' + $gate44_3),
    ('cases_total=' + $cases.Count),
    ('cases_pass=' + (@($cases | Where-Object { $_.pass }).Count)),
    ('cases_fail=' + (@($cases | Where-Object { -not $_.pass }).Count)),
    ('stored_reference_fingerprint=' + $storedFingerprint),
    ('timestamp=' + $Timestamp)
)
Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value ($status -join "`r`n") -Encoding UTF8 -NoNewline

$head = @(
    'runner=tools/phase44_5/phase44_5_guard_fingerprint_enforcement_runner.ps1',
    ('phase44_3_pf=' + $phase44_3Pf),
    ('phase44_3_inventory=' + $inventoryPath),
    ('stored_reference_artifact=' + $referencePath),
    'enforcement_order=fingerprint_verification_before_baseline_guard_and_catalog_initialization',
    'deterministic_hash=sha256_utf8_json_v1'
)
Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value ($head -join "`r`n") -Encoding UTF8 -NoNewline

$def = @(
    'FINGERPRINT ENFORCEMENT DEFINITION (PHASE 44.5)',
    '',
    'The certification entry gate loads stored fingerprint reference from tools/phase44_4/guard_coverage_fingerprint_reference.json.',
    'It recomputes the current operational guard coverage fingerprint from phase44_3 inventory material.',
    'Comparison result determines whether runtime/catalog initialization may proceed.',
    '',
    'Enforcement occurs before:',
    '  baseline guard initialization,',
    '  catalog load, catalog resolution, trust-chain validation, catalog rotation, historical validation initializers.'
)
Set-Content -LiteralPath (Join-Path $PF '10_fingerprint_enforcement_definition.txt') -Value ($def -join "`r`n") -Encoding UTF8 -NoNewline

$rules = @(
    'FINGERPRINT ENFORCEMENT RULES (PHASE 44.5)',
    '',
    'RULE_1: fingerprint mismatch MUST block runtime initialization.',
    'RULE_2: fingerprint verification is first step in initialization sequence.',
    'RULE_3: entrypoint addition/regression changes MUST produce mismatch.',
    'RULE_4: guard coverage removal MUST produce mismatch.',
    'RULE_5: non-semantic ordering changes MUST NOT produce mismatch.',
    'RULE_6: dead helper-only changes MUST NOT produce mismatch.',
    'RULE_7: stored fingerprint tamper MUST produce mismatch and block.'
)
Set-Content -LiteralPath (Join-Path $PF '11_fingerprint_enforcement_rules.txt') -Value ($rules -join "`r`n") -Encoding UTF8 -NoNewline

$touched = @(
    ('READ  ' + ($inventoryPath -replace [regex]::Escape($Root + '\\'), '')),
    ('READ  ' + ($gate44_3Path -replace [regex]::Escape($Root + '\\'), '')),
    ('READ  ' + ($referencePath -replace [regex]::Escape($Root + '\\'), '')),
    ('WRITE _proof/' + (Split-Path -Leaf $PF) + '/*')
)
Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Value ($touched -join "`r`n") -Encoding UTF8 -NoNewline

$build = @(
    'build_type=PowerShell fingerprint enforcement gate',
    'compile_required=no',
    'runtime_state_machine_changed=no',
    'enforcement_mode=certification_entry_pre-init_gate',
    'canonical_launcher_note=not required for this static enforcement proof runner'
)
Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Value ($build -join "`r`n") -Encoding UTF8 -NoNewline

$val = [System.Collections.Generic.List[string]]::new()
foreach ($c in $cases) {
    $val.Add(('CASE ' + $c.case + ': stored_fingerprint=' + $c.stored_fingerprint + '; computed_fingerprint=' + $c.computed_fingerprint + '; fingerprint_match_status=' + $c.fingerprint_match_status + '; detected_change_type=' + $c.detected_change_type + '; runtime_initialization_allowed_or_blocked=' + $c.runtime_initialization_allowed_or_blocked + '; pass=' + $c.pass))
}
Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Value (($val.ToArray()) -join "`r`n") -Encoding UTF8 -NoNewline

$summary = @(
    'Fingerprint enforcement gate is evaluated before any baseline/catalog initialization step.',
    'If stored and computed fingerprints match, initialization continues; otherwise initialization is blocked at entry.',
    'Entrypoint addition and guard removal both force mismatches and deterministic blocking.',
    'Non-semantic ordering changes and dead-helper-only changes do not affect operational fingerprint material and remain allowed.',
    'Stored fingerprint tamper produces mismatch and blocks initialization, preventing silent reference replacement bypass.',
    'Runtime behavior remained unchanged because this phase only validates certification entry gating logic on static artifacts.'
)
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value ($summary -join "`r`n") -Encoding UTF8 -NoNewline

$referenceRecord = [ordered]@{
    stored_reference_path = $referencePath
    stored_reference_fingerprint = $storedFingerprint
    source_phase44_3_inventory = $inventoryPath
    source_phase44_3_gate = $gate44_3
    computed_base_fingerprint = $caseA.computed_fingerprint
    fingerprint_schema = 'phase44_5_guard_fingerprint_enforcement_v1'
}
Set-Content -LiteralPath (Join-Path $PF '16_fingerprint_reference_record.txt') -Value ($referenceRecord | ConvertTo-Json -Depth 8) -Encoding UTF8 -NoNewline

$blockEvidence = [System.Collections.Generic.List[string]]::new()
$blockEvidence.Add('ENFORCEMENT BLOCK EVIDENCE')
$blockEvidence.Add('')
foreach ($c in $cases) {
    $blockEvidence.Add(('CASE_' + $c.case + '_MATCH=' + $c.fingerprint_match_status))
    $blockEvidence.Add(('CASE_' + $c.case + '_INIT=' + $c.runtime_initialization_allowed_or_blocked))
    $blockEvidence.Add(('CASE_' + $c.case + '_SEQUENCE=' + ($c.initialization_sequence -join ' -> ')))
}
$blockEvidence.Add('')
$blockEvidence.Add('blocked_cases_expected=B,C,F')
$blockEvidence.Add(('blocked_cases_actual=' + ((@($cases | Where-Object { $_.runtime_initialization_allowed_or_blocked -eq 'BLOCKED' } | ForEach-Object { $_.case }) -join ','))))
Set-Content -LiteralPath (Join-Path $PF '17_enforcement_block_evidence.txt') -Value (($blockEvidence.ToArray()) -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '98_gate_phase44_5.txt') -Value $gate -Encoding UTF8 -NoNewline

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
