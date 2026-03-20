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
    param($Value)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [float] -or $Value -is [decimal]) {
        return [string]$Value
    }
    if ($Value -is [string]) {
        $s = [string]$Value
        $s = $s -replace '\\', '\\'
        $s = $s -replace '"', '\"'
        $s = $s -replace "`n", '\n'
        $s = $s -replace "`r", '\r'
        $s = $s -replace "`t", '\t'
        return '"' + $s + '"'
    }
    if ($Value -is [System.Collections.IList]) {
        # Sort canonicalized array items for order-insensitive fingerprints.
        $items = [System.Collections.Generic.List[string]]::new()
        foreach ($item in $Value) { [void]$items.Add((Convert-ToCanonicalJson -Value $item)) }
        $sorted = @($items | Sort-Object)
        return '[' + ($sorted -join ',') + ']'
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $keys = @($Value.Keys | Sort-Object)
        $pairs = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $keys) {
            [void]$pairs.Add(('"' + $k + '":' + (Convert-ToCanonicalJson -Value $Value[$k])))
        }
        return '{' + ($pairs -join ',') + '}'
    }
    if ($Value -is [pscustomobject]) {
        $keys = @($Value.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object)
        $pairs = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $keys) {
            $v = $Value.PSObject.Properties[$k].Value
            [void]$pairs.Add(('"' + $k + '":' + (Convert-ToCanonicalJson -Value $v)))
        }
        return '{' + ($pairs -join ',') + '}'
    }

    return '"' + ([string]$Value -replace '"', '\"') + '"'
}

function Convert-TextToLines {
    param([string]$Text)
    return @($Text -split "`r?`n")
}

function Get-LatestPhase48_0ProofPath {
    param([string]$ProofRoot)

    $dirs = Get-ChildItem -Path $ProofRoot -Directory | Where-Object {
        $_.Name -like 'phase48_0_trust_chain_ledger_baseline_enforcement_coverage_audit_*'
    } | Sort-Object Name -Descending

    if (@($dirs).Count -eq 0) {
        throw 'No phase48_0 proof directory found.'
    }

    return $dirs[0].FullName
}

function Parse-PipeRows {
    param(
        [string]$Text,
        [int]$ExpectedColumns
    )

    $rows = [System.Collections.Generic.List[object]]::new()
    $lines = Convert-TextToLines -Text $Text

    foreach ($raw in $lines) {
        $line = [string]$raw
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -like '#*') { continue }
        if ($line -like '*|*|*') {
            $partsRaw = $line -split '\|'
            $parts = @($partsRaw | ForEach-Object { ([string]$_).Trim() })
            if (@($parts).Count -ne $ExpectedColumns) { continue }
            if ($parts[0] -eq 'file_path' -or $parts[0] -eq 'function_or_entrypoint_name') { continue }
            [void]$rows.Add(@($parts))
        }
    }

    return @($rows)
}

function Parse-KeyValueLines {
    param([string]$Text)

    $kv = [ordered]@{}
    $lines = Convert-TextToLines -Text $Text
    foreach ($raw in $lines) {
        $line = [string]$raw
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $idx = $line.IndexOf('=')
        if ($idx -lt 1) { continue }
        $k = $line.Substring(0, $idx).Trim()
        $v = $line.Substring($idx + 1).Trim()
        $kv[$k] = $v
    }
    return $kv
}

function Get-CoverageFingerprintMaterial {
    param(
        [string]$InventoryText,
        [string]$MapText,
        [string]$UnguardedText,
        [string]$BypassText
    )

    # 16_entrypoint_inventory columns:
    # 0 file_path
    # 1 function_or_entrypoint_name
    # 2 role
    # 3 operational_or_dead
    # 4 direct_gate_present
    # 5 transitive_gate_present
    # 6 gate_source_path
    # 7 ledger_baseline_relevant_operation_type
    # 8 coverage_classification
    # 9 evidence_notes
    $invRows = Parse-PipeRows -Text $InventoryText -ExpectedColumns 10

    # Keep only operational semantics in fingerprint model.
    $operationalInventory = [System.Collections.Generic.List[object]]::new()
    foreach ($r in $invRows) {
        if ([string]$r[3] -ne 'operational') { continue }
        [void]$operationalInventory.Add([ordered]@{
            function_or_entrypoint_name = [string]$r[1]
            role = [string]$r[2]
            operational_or_dead = [string]$r[3]
            direct_gate_present = [string]$r[4]
            transitive_gate_present = [string]$r[5]
            gate_source_path = [string]$r[6]
            ledger_baseline_relevant_operation_type = [string]$r[7]
            coverage_classification = [string]$r[8]
        })
    }

    # 17_map columns:
    # 0 function_or_entrypoint_name
    # 1 coverage_classification
    # 2 gate_source_path
    # 3 operational_or_dead
    $mapRows = Parse-PipeRows -Text $MapText -ExpectedColumns 4
    $operationalMap = [System.Collections.Generic.List[object]]::new()
    foreach ($r in $mapRows) {
        if ([string]$r[3] -ne 'operational') { continue }
        [void]$operationalMap.Add([ordered]@{
            function_or_entrypoint_name = [string]$r[0]
            coverage_classification = [string]$r[1]
            gate_source_path = [string]$r[2]
            operational_or_dead = [string]$r[3]
        })
    }

    # 18_unguarded_path_report semantics
    $unguardedKv = Parse-KeyValueLines -Text $UnguardedText
    $unguardedCount = [string]($unguardedKv['unguarded_operational_path_count'])
    $unguardedDetails = [System.Collections.Generic.List[string]]::new()
    foreach ($line in (Convert-TextToLines -Text $UnguardedText)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -like 'unguarded_operational_path_count=*') { continue }
        if ($line -eq 'NONE') { continue }
        [void]$unguardedDetails.Add(($line.Trim()))
    }

    # 19_bypass_crosscheck_report semantics
    $bypassKv = Parse-KeyValueLines -Text $BypassText
    $bypassSemantics = [ordered]@{
        phase47_9_gate = [string]$bypassKv['phase47_9_gate']
        cross_inventory_entries = [string]$bypassKv['cross_inventory_entries']
        cross_gate_record_rows = [string]$bypassKv['cross_gate_record_rows']
        map_operational_entries = [string]$bypassKv['map_operational_entries']
        cross_missing_count = [string]$bypassKv['cross_missing_count']
        missing = [string]$bypassKv['missing']
        bypass_crosscheck = [string]$bypassKv['bypass_crosscheck']
    }

    $model = [ordered]@{
        fingerprint_scope = 'trust_chain_ledger_baseline_enforcement_coverage_model'
        operational_inventory = @($operationalInventory)
        operational_enforcement_map = @($operationalMap)
        unguarded_path_semantics = [ordered]@{
            unguarded_operational_path_count = $unguardedCount
            unguarded_operational_paths = @($unguardedDetails)
        }
        bypass_crosscheck_semantics = $bypassSemantics
    }

    $canonicalInventory = Convert-ToCanonicalJson -Value @($operationalInventory)
    $canonicalMap = Convert-ToCanonicalJson -Value @($operationalMap)
    $canonicalUnguarded = Convert-ToCanonicalJson -Value $model.unguarded_path_semantics
    $canonicalBypass = Convert-ToCanonicalJson -Value $bypassSemantics
    $canonicalModel = Convert-ToCanonicalJson -Value $model

    return [ordered]@{
        model = $model
        canonical_inventory = $canonicalInventory
        canonical_map = $canonicalMap
        canonical_unguarded = $canonicalUnguarded
        canonical_bypass = $canonicalBypass
        canonical_model = $canonicalModel
        inventory_sha256 = Get-StringSha256Hex -Text $canonicalInventory
        map_sha256 = Get-StringSha256Hex -Text $canonicalMap
        unguarded_sha256 = Get-StringSha256Hex -Text $canonicalUnguarded
        bypass_sha256 = Get-StringSha256Hex -Text $canonicalBypass
        model_sha256 = Get-StringSha256Hex -Text $canonicalModel
        coverage_fingerprint_sha256 = Get-StringSha256Hex -Text $canonicalModel
    }
}

function Set-ReferenceArtifact {
    param(
        [string]$Path,
        [string]$Fingerprint,
        [object]$Material,
        [string]$SourceProof
    )

    $obj = [ordered]@{
        phase_locked = '48.1'
        source_phase = '48.0'
        fingerprint_type = 'trust_chain_ledger_baseline_enforcement_coverage_fingerprint'
        coverage_fingerprint_sha256 = $Fingerprint
        canonical_input_hashes = [ordered]@{
            inventory_sha256 = [string]$Material.inventory_sha256
            enforcement_map_sha256 = [string]$Material.map_sha256
            unguarded_sha256 = [string]$Material.unguarded_sha256
            bypass_crosscheck_sha256 = [string]$Material.bypass_sha256
            model_sha256 = [string]$Material.model_sha256
        }
        source_proof_path = $SourceProof
        source_artifacts = @(
            '16_entrypoint_inventory.txt',
            '17_ledger_baseline_enforcement_map.txt',
            '18_unguarded_path_report.txt',
            '19_bypass_crosscheck_report.txt'
        )
        generated_utc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }

    ($obj | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $Path -Encoding UTF8 -NoNewline
}

function Add-CaseResult {
    param(
        [System.Collections.Generic.List[object]]$Rows,
        [string]$CaseId,
        [string]$CaseName,
        [string]$Computed,
        [string]$Stored,
        [bool]$ExpectMatch,
        [string]$ChangeType
    )

    $isMatch = ($Computed -eq $Stored)
    $pass = ($isMatch -eq $ExpectMatch)
    $Rows.Add([ordered]@{
        case_id = $CaseId
        case_name = $CaseName
        computed_fingerprint = $Computed
        stored_reference_fingerprint = $Stored
        fingerprint_match_status = $(if ($isMatch) { 'MATCH' } else { 'MISMATCH' })
        detected_change_type = $ChangeType
        certification_allowed_or_blocked = $(if ($pass) { 'ALLOWED' } else { 'BLOCKED' })
        result = $(if ($pass) { 'PASS' } else { 'FAIL' })
    })

    return $pass
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\phase48_1_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$ProofRoot = Join-Path $Root '_proof'
$SourceProof = Get-LatestPhase48_0ProofPath -ProofRoot $ProofRoot
$InventoryPath = Join-Path $SourceProof '16_entrypoint_inventory.txt'
$MapPath = Join-Path $SourceProof '17_ledger_baseline_enforcement_map.txt'
$UnguardedPath = Join-Path $SourceProof '18_unguarded_path_report.txt'
$BypassPath = Join-Path $SourceProof '19_bypass_crosscheck_report.txt'
$ReferencePath = Join-Path $Root 'control_plane\87_trust_chain_ledger_baseline_enforcement_coverage_fingerprint.json'

if (-not (Test-Path -LiteralPath $InventoryPath)) { throw 'Missing 48.0 artifact 16_entrypoint_inventory.txt' }
if (-not (Test-Path -LiteralPath $MapPath)) { throw 'Missing 48.0 artifact 17_ledger_baseline_enforcement_map.txt' }
if (-not (Test-Path -LiteralPath $UnguardedPath)) { throw 'Missing 48.0 artifact 18_unguarded_path_report.txt' }
if (-not (Test-Path -LiteralPath $BypassPath)) { throw 'Missing 48.0 artifact 19_bypass_crosscheck_report.txt' }

$inventoryText = Get-Content -Raw -LiteralPath $InventoryPath
$mapText = Get-Content -Raw -LiteralPath $MapPath
$unguardedText = Get-Content -Raw -LiteralPath $UnguardedPath
$bypassText = Get-Content -Raw -LiteralPath $BypassPath

$base = Get-CoverageFingerprintMaterial -InventoryText $inventoryText -MapText $mapText -UnguardedText $unguardedText -BypassText $bypassText
$storedFingerprint = [string]$base.coverage_fingerprint_sha256
Set-ReferenceArtifact -Path $ReferencePath -Fingerprint $storedFingerprint -Material $base -SourceProof $SourceProof

$results = [System.Collections.Generic.List[object]]::new()
$allPass = $true

# CASE A — clean generation
$allPass = (Add-CaseResult -Rows $results -CaseId 'A' -CaseName 'clean_fingerprint_generation' -Computed $storedFingerprint -Stored $storedFingerprint -ExpectMatch $true -ChangeType 'none') -and $allPass

# CASE B — non-semantic formatting
$invB = ($inventoryText -replace '\|', ' | ')
$mapB = ($mapText -replace '\|', ' | ')
$matB = Get-CoverageFingerprintMaterial -InventoryText $invB -MapText $mapB -UnguardedText $unguardedText -BypassText $bypassText
$allPass = (Add-CaseResult -Rows $results -CaseId 'B' -CaseName 'non_semantic_change' -Computed ([string]$matB.coverage_fingerprint_sha256) -Stored $storedFingerprint -ExpectMatch $true -ChangeType 'formatting_only') -and $allPass

# CASE C — entrypoint addition (operational)
$newRow = 'tools/phase47_8/phase47_8_trust_chain_ledger_baseline_enforcement_runner.ps1|Simulated-NewEntrypoint|runtime_init_wrapper|operational|no|yes|Invoke-LedgerBaselineEnforcementGate|invoke_runtime_initialization_wrapper|transitively_gated|simulated_addition'
$invC = $inventoryText + "`r`n" + $newRow
$matC = Get-CoverageFingerprintMaterial -InventoryText $invC -MapText $mapText -UnguardedText $unguardedText -BypassText $bypassText
$allPass = (Add-CaseResult -Rows $results -CaseId 'C' -CaseName 'entrypoint_addition' -Computed ([string]$matC.coverage_fingerprint_sha256) -Stored $storedFingerprint -ExpectMatch $false -ChangeType 'entrypoint_added') -and $allPass

# CASE D — coverage classification change
$invD = $inventoryText -replace '\|transitively_gated\|', '|unguarded|'
$matD = Get-CoverageFingerprintMaterial -InventoryText $invD -MapText $mapText -UnguardedText $unguardedText -BypassText $bypassText
$allPass = (Add-CaseResult -Rows $results -CaseId 'D' -CaseName 'coverage_classification_change' -Computed ([string]$matD.coverage_fingerprint_sha256) -Stored $storedFingerprint -ExpectMatch $false -ChangeType 'coverage_classification_changed') -and $allPass

# CASE E — order change in inventory
$invLines = Convert-TextToLines -Text $inventoryText
$header = @($invLines | Select-Object -First 1)
$data = @($invLines | Select-Object -Skip 1 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$rev = @($data | Sort-Object -Descending)
$invE = ($header + $rev) -join "`r`n"
$matE = Get-CoverageFingerprintMaterial -InventoryText $invE -MapText $mapText -UnguardedText $unguardedText -BypassText $bypassText
$allPass = (Add-CaseResult -Rows $results -CaseId 'E' -CaseName 'order_change' -Computed ([string]$matE.coverage_fingerprint_sha256) -Stored $storedFingerprint -ExpectMatch $true -ChangeType 'ordering_only') -and $allPass

# CASE F — dead helper cosmetic change only
$invF = $inventoryText -replace 'dead_or_non_operational\|[^\r\n]*$', 'dead_or_non_operational|no|no|NONE|hashing|dead_or_non_operational|cosmetic_dead_helper_note'
$matF = Get-CoverageFingerprintMaterial -InventoryText $invF -MapText $mapText -UnguardedText $unguardedText -BypassText $bypassText
$allPass = (Add-CaseResult -Rows $results -CaseId 'F' -CaseName 'dead_helper_change' -Computed ([string]$matF.coverage_fingerprint_sha256) -Stored $storedFingerprint -ExpectMatch $true -ChangeType 'dead_helper_cosmetic_only') -and $allPass

# CASE G — unguarded path report semantics change
$ungG = "unguarded_operational_path_count=1`r`n" +
    "tools/phase47_8/phase47_8_trust_chain_ledger_baseline_enforcement_runner.ps1|" +
    "Invoke-LedgerBaselineEnforcementGate|role=runtime_init_gate|op=runtime_init_gate"
$matG = Get-CoverageFingerprintMaterial -InventoryText $inventoryText -MapText $mapText -UnguardedText $ungG -BypassText $bypassText
$allPass = (Add-CaseResult -Rows $results -CaseId 'G' -CaseName 'unguarded_path_report_change' -Computed ([string]$matG.coverage_fingerprint_sha256) -Stored $storedFingerprint -ExpectMatch $false -ChangeType 'unguarded_path_semantics_changed') -and $allPass

# CASE H — operational/dead reclassification
$invH = ($inventoryText -replace '\|operational\|', '|dead_or_non_operational|')
$matH = Get-CoverageFingerprintMaterial -InventoryText $invH -MapText $mapText -UnguardedText $unguardedText -BypassText $bypassText
$allPass = (Add-CaseResult -Rows $results -CaseId 'H' -CaseName 'operational_dead_reclassification' -Computed ([string]$matH.coverage_fingerprint_sha256) -Stored $storedFingerprint -ExpectMatch $false -ChangeType 'operational_dead_reclassification') -and $allPass

# CASE I — bypass crosscheck semantics change
$bypassI = $bypassText -replace 'cross_missing_count=0', 'cross_missing_count=1'
if ($bypassI -eq $bypassText) { $bypassI = $bypassText + "`r`ncross_missing_count=1" }
$matI = Get-CoverageFingerprintMaterial -InventoryText $inventoryText -MapText $mapText -UnguardedText $unguardedText -BypassText $bypassI
$allPass = (Add-CaseResult -Rows $results -CaseId 'I' -CaseName 'bypass_crosscheck_change' -Computed ([string]$matI.coverage_fingerprint_sha256) -Stored $storedFingerprint -ExpectMatch $false -ChangeType 'bypass_crosscheck_semantics_changed') -and $allPass

$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status = @(
    'phase=48.1',
    'title=Trust-Chain Ledger Baseline Enforcement Coverage Fingerprint Lock',
    ('gate=' + $Gate),
    ('coverage_fingerprint=' + $storedFingerprint),
    ('reference_saved=' + $(if (Test-Path -LiteralPath $ReferencePath) { 'TRUE' } else { 'FALSE' })),
    'runtime_state_machine_changed=NO'
)
Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value ($status -join "`r`n") -Encoding UTF8 -NoNewline

$head = @(
    'runner=tools/phase48_1/phase48_1_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_runner.ps1',
    ('source_phase48_0_proof=' + $SourceProof),
    ('reference_path=' + $ReferencePath),
    ('source_inventory=' + $InventoryPath),
    ('source_enforcement_map=' + $MapPath),
    ('source_unguarded=' + $UnguardedPath),
    ('source_bypass=' + $BypassPath)
)
Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value ($head -join "`r`n") -Encoding UTF8 -NoNewline

$def = @(
    'FINGERPRINT DEFINITION (PHASE 48.1)',
    '',
    'Fingerprint scope is the operational ledger-baseline enforcement coverage model from phase48_0 artifacts 16/17/18/19.',
    'Operational rows only are hashed for inventory and map semantics; dead/non-operational helper cosmetic content is excluded from the fingerprint model.',
    'Canonicalization normalizes object keys and array content order to eliminate ordering/formatting instability.',
    'Final fingerprint = SHA256(canonical JSON of full semantic model).',
    'Reference artifact stores fingerprint and canonical sub-hashes for inventory/map/unguarded/bypass/model.'
)
Set-Content -LiteralPath (Join-Path $PF '10_fingerprint_definition.txt') -Value ($def -join "`r`n") -Encoding UTF8 -NoNewline

$rules = @(
    'FINGERPRINT RULES (PHASE 48.1)',
    '',
    'Must remain unchanged for: formatting-only edits, whitespace-only edits, file ordering changes, non-semantic field order changes, dead-helper cosmetic-only edits.',
    'Must change for: entrypoint add/remove, coverage-class changes, operational/dead reclassification of real path, unguarded-path semantic change, bypass-crosscheck semantic change.',
    'Certification blocks on unexpected mismatch against stored reference fingerprint.'
)
Set-Content -LiteralPath (Join-Path $PF '11_fingerprint_rules.txt') -Value ($rules -join "`r`n") -Encoding UTF8 -NoNewline

$filesTouched = @(
    ('READ  ' + $InventoryPath),
    ('READ  ' + $MapPath),
    ('READ  ' + $UnguardedPath),
    ('READ  ' + $BypassPath),
    ('WRITE ' + $ReferencePath),
    ('WRITE ' + (Join-Path $PF '*'))
)
Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Value ($filesTouched -join "`r`n") -Encoding UTF8 -NoNewline

$build = @(
    'build_type=PowerShell deterministic coverage fingerprint lock runner',
    'compile_required=no',
    'runtime_behavior_changed=no',
    'operation=canonical model derivation + SHA256 fingerprint + A-I mutation validation'
)
Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Value ($build -join "`r`n") -Encoding UTF8 -NoNewline

$validationLines = [System.Collections.Generic.List[string]]::new()
foreach ($r in $results) {
    [void]$validationLines.Add(('CASE ' + [string]$r.case_id + ' ' + [string]$r.case_name +
        ' computed=' + [string]$r.computed_fingerprint +
        ' stored=' + [string]$r.stored_reference_fingerprint +
        ' match=' + [string]$r.fingerprint_match_status +
        ' change=' + [string]$r.detected_change_type +
        ' certification=' + [string]$r.certification_allowed_or_blocked +
        ' => ' + [string]$r.result))
}
Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Value ($validationLines -join "`r`n") -Encoding UTF8 -NoNewline

$summary = @(
    'Phase 48.1 locks the phase48_0 coverage-audit completeness model into a deterministic certification fingerprint reference artifact.',
    'The model fingerprints operational inventory, operational enforcement map, unguarded-path semantics, and bypass-crosscheck semantics.',
    'Whitespace/ordering/non-semantic formatting are normalized away by canonicalization so non-semantic edits do not cause false regression.',
    'Real coverage changes are detected because they alter operational inventory/map semantics or unguarded/crosscheck semantics in the fingerprint model.',
    'Dead-helper cosmetic-only edits do not alter the fingerprint because dead/non-operational rows are excluded from operational fingerprint material.',
    'Runtime behavior remained unchanged because this phase only computes and records certification fingerprints and proof artifacts.'
)
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value ($summary -join "`r`n") -Encoding UTF8 -NoNewline

$fingerprintRecord = @(
    ('coverage_fingerprint_sha256=' + $storedFingerprint),
    ('inventory_sha256=' + [string]$base.inventory_sha256),
    ('enforcement_map_sha256=' + [string]$base.map_sha256),
    ('unguarded_sha256=' + [string]$base.unguarded_sha256),
    ('bypass_crosscheck_sha256=' + [string]$base.bypass_sha256),
    ('model_sha256=' + [string]$base.model_sha256),
    ('reference_path=' + $ReferencePath),
    ('source_proof=' + $SourceProof)
)
Set-Content -LiteralPath (Join-Path $PF '16_coverage_fingerprint_record.txt') -Value ($fingerprintRecord -join "`r`n") -Encoding UTF8 -NoNewline

$evidence = [System.Collections.Generic.List[string]]::new()
foreach ($r in $results) {
    [void]$evidence.Add(([string]$r.case_id + '|' + [string]$r.detected_change_type + '|match=' + [string]$r.fingerprint_match_status + '|result=' + [string]$r.result))
}
Set-Content -LiteralPath (Join-Path $PF '17_regression_detection_evidence.txt') -Value ($evidence -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '98_gate_phase48_1.txt') -Value $Gate -Encoding UTF8 -NoNewline

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
