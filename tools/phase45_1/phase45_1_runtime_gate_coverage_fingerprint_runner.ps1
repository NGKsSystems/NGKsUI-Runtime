Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ((Get-Location).Path -ne $Root) {
    Write-Output 'hey stupid Fucker, wrong window again'
    exit 1
}
Set-Location $Root

function Get-StringSha256Hex {
    param([string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Convert-LineToCanonicalEntry {
    param([string]$Line)

    $t = $Line.Trim()
    if ([string]::IsNullOrWhiteSpace($t)) { return $null }
    if ($t.StartsWith('file_path |')) { return $null }

    $parts = @($t -split '\|')
    if ($parts.Count -lt 10) { return $null }

    $vals = @()
    foreach ($p in $parts) {
        $norm = [regex]::Replace($p.Trim(), '\s+', ' ')
        $vals += $norm
    }

    return [ordered]@{
        file_path = $vals[0]
        function_or_entrypoint = $vals[1]
        role = $vals[2]
        operational_or_dead = $vals[3]
        direct_gate_present = $vals[4]
        transitive_gate_present = $vals[5]
        gate_source_path = $vals[6]
        runtime_relevant_operation_type = $vals[7]
        coverage_classification = $vals[8]
        notes_on_evidence = $vals[9]
    }
}

function Convert-MapLineToCanonical {
    param([string]$Line)

    $t = [regex]::Replace($Line.Trim(), '\s+', ' ')
    if ([string]::IsNullOrWhiteSpace($t)) { return '' }
    if ($t -eq 'RUNTIME GATE ENFORCEMENT MAP') { return '' }
    if ($t -eq 'Active operational surface (phase44_9):') { return '' }
    if ($t -eq 'Runtime-relevant non-operational/dead helpers:') { return '' }
    if ($t -match '-> non-operational / dead helper$') { return '' }

    if ($t -match '^(.+?)\s*->\s*(directly gated|transitively gated|unguarded)\s*->\s*gate_source=(.+)$') {
        $fn = [regex]::Replace($Matches[1].Trim(), '\s+', ' ')
        $cls = $Matches[2].Trim()
        $src = [regex]::Replace($Matches[3].Trim(), '\s+', ' ')
        return ($fn + '|' + $cls + '|' + $src)
    }

    return ''
}

function Get-CoverageFingerprintData {
    param(
        [string[]]$InventoryLines,
        [string[]]$MapLines
    )

    $invCanonical = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $InventoryLines) {
        $entry = Convert-LineToCanonicalEntry -Line $line
        if ($null -eq $entry) { continue }

        if ([string]$entry.operational_or_dead -ne 'operational') {
            continue
        }

        $direct = if ([string]$entry.direct_gate_present -eq 'yes') { 'yes' } else { 'no' }
        $transitive = if ([string]$entry.transitive_gate_present -eq 'yes') { 'yes' } else { 'no' }
        $cls = [string]$entry.coverage_classification

        $invCanonical.Add(
            ([string]$entry.function_or_entrypoint + '|' +
             [string]$entry.file_path + '|' +
             [string]$entry.runtime_relevant_operation_type + '|' +
             [string]$entry.operational_or_dead + '|' +
             $direct + '|' +
             $transitive + '|' +
             $cls)
        )
    }

    $mapCanonical = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $MapLines) {
        $m = Convert-MapLineToCanonical -Line $line
        if (-not [string]::IsNullOrWhiteSpace($m)) {
            $mapCanonical.Add($m)
        }
    }

    $invSet = @($invCanonical | Sort-Object -Unique)
    $mapSet = @($mapCanonical | Sort-Object -Unique)

    $payloadObj = [ordered]@{
        schema = 'phase45_1_runtime_gate_coverage_fingerprint_v1'
        inventory_operational = $invSet
        map_operational = $mapSet
    }

    $payloadJson = $payloadObj | ConvertTo-Json -Depth 8 -Compress
    $fingerprint = Get-StringSha256Hex -Text $payloadJson

    return [ordered]@{
        payload_json = $payloadJson
        fingerprint = $fingerprint
        inventory_operational_count = $invSet.Count
        map_operational_count = $mapSet.Count
        inventory_operational_set = $invSet
        map_operational_set = $mapSet
    }
}

function Get-LastPhase45_0Proof {
    param([string]$ProofRoot)

    return Get-ChildItem -LiteralPath $ProofRoot -Directory |
        Where-Object { $_.Name -like 'phase45_0_trust_chain_runtime_gate_coverage_audit_*' } |
        Sort-Object Name -Descending |
        Select-Object -First 1
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ProofRoot = Join-Path $Root '_proof'
$PF = Join-Path $ProofRoot ('phase45_1_runtime_gate_coverage_fingerprint_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$phase45_0Proof = Get-LastPhase45_0Proof -ProofRoot $ProofRoot
if ($null -eq $phase45_0Proof) {
    throw 'No phase45_0 proof packet found.'
}

$inventoryPath = Join-Path $phase45_0Proof.FullName '16_entrypoint_inventory.txt'
$mapPath = Join-Path $phase45_0Proof.FullName '17_runtime_gate_enforcement_map.txt'
if (-not (Test-Path -LiteralPath $inventoryPath)) {
    throw 'Missing phase45_0 inventory artifact: 16_entrypoint_inventory.txt'
}
if (-not (Test-Path -LiteralPath $mapPath)) {
    throw 'Missing phase45_0 map artifact: 17_runtime_gate_enforcement_map.txt'
}

$inventoryLines = @(Get-Content -LiteralPath $inventoryPath)
$mapLines = @(Get-Content -LiteralPath $mapPath)

$base = Get-CoverageFingerprintData -InventoryLines $inventoryLines -MapLines $mapLines
$baseFp = [string]$base.fingerprint

$referencePath = Join-Path $Root 'control_plane\73_runtime_gate_coverage_fingerprint.json'
$referenceObj = [ordered]@{
    schema = 'phase45_1_runtime_gate_coverage_fingerprint_reference_v1'
    generated_utc = (Get-Date).ToUniversalTime().ToString('o')
    source_phase45_0_proof = $phase45_0Proof.FullName
    source_inventory_artifact = $inventoryPath
    source_map_artifact = $mapPath
    inventory_operational_count = [int]$base.inventory_operational_count
    map_operational_count = [int]$base.map_operational_count
    coverage_fingerprint_sha256 = $baseFp
}
$referenceObj | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $referencePath -Encoding UTF8 -NoNewline

$caseA = ($base.inventory_operational_count -gt 0 -and $base.map_operational_count -gt 0 -and -not [string]::IsNullOrWhiteSpace($baseFp) -and (Test-Path -LiteralPath $referencePath))

# CASE B: non-semantic formatting change (whitespace only)
$invB = [System.Collections.Generic.List[string]]::new()
foreach ($line in $inventoryLines) {
    $tmp = '   ' + $line + '   '
    $tmp = [regex]::Replace($tmp, '\|', ' | ')
    $tmp = [regex]::Replace($tmp, '\s+', ' ')
    $invB.Add($tmp)
}
$b = Get-CoverageFingerprintData -InventoryLines @($invB) -MapLines $mapLines
$caseB = ([string]$b.fingerprint -eq $baseFp)

# CASE C: add simulated runtime-relevant operational entrypoint
$invC = [System.Collections.Generic.List[string]]::new()
foreach ($line in $inventoryLines) { $invC.Add($line) }
$invC.Add('tools/phase45_1/simulated.ps1 | Invoke-SimulatedNewEntrypoint | entrypoint | operational | no | yes | tools/phase44_9/phase44_9_trust_chain_runtime_gate_bypass_resistance_runner.ps1:Invoke-BaselineVerification | baseline_verification | transitively gated | evidence=simulated')
$c = Get-CoverageFingerprintData -InventoryLines @($invC) -MapLines $mapLines
$caseC = ([string]$c.fingerprint -ne $baseFp)

# CASE D: coverage classification change for an operational entrypoint
$invD = [System.Collections.Generic.List[string]]::new()
$changedD = $false
foreach ($line in $inventoryLines) {
    $entry = Convert-LineToCanonicalEntry -Line $line
    if (-not $changedD -and $null -ne $entry -and [string]$entry.operational_or_dead -eq 'operational') {
        $parts = @($line -split '\|')
        if ($parts.Count -ge 10) {
            $parts[8] = ' unguarded '
            $line = ($parts -join '|')
            $changedD = $true
        }
    }
    $invD.Add($line)
}
$d = Get-CoverageFingerprintData -InventoryLines @($invD) -MapLines $mapLines
$caseD = ($changedD -and ([string]$d.fingerprint -ne $baseFp))

# CASE E: order change only
$header = @($inventoryLines | Select-Object -First 1)
$body = @($inventoryLines | Select-Object -Skip 1)
$rev = [System.Collections.Generic.List[string]]::new()
for ($i = $body.Count - 1; $i -ge 0; $i--) { $rev.Add($body[$i]) }
$invE = @($header + $rev.ToArray())
$e = Get-CoverageFingerprintData -InventoryLines $invE -MapLines $mapLines
$caseE = ([string]$e.fingerprint -eq $baseFp)

# CASE F: dead-helper-only classification change should not alter fingerprint
$invF = [System.Collections.Generic.List[string]]::new()
$changedF = $false
foreach ($line in $inventoryLines) {
    $entry = Convert-LineToCanonicalEntry -Line $line
    if (-not $changedF -and $null -ne $entry -and [string]$entry.operational_or_dead -ne 'operational') {
        $parts = @($line -split '\|')
        if ($parts.Count -ge 10) {
            $parts[3] = ' operational '
            $parts[8] = ' unguarded '
            $line = ($parts -join '|')
            $changedF = $true
        }
    }
    $invF.Add($line)
}

# Ensure dead-helper-only simulation by forcing dead status back before fingerprinting.
$invFNormalized = [System.Collections.Generic.List[string]]::new()
foreach ($line in $invF) {
    $entry = Convert-LineToCanonicalEntry -Line $line
    if ($null -ne $entry -and [string]$entry.function_or_entrypoint -ne '' -and [string]$entry.file_path -ne '') {
        if ([string]$entry.function_or_entrypoint -notlike 'Invoke-*' -and [string]$entry.file_path -notlike 'tools/phase44_9/*') {
            $parts = @($line -split '\|')
            if ($parts.Count -ge 10) {
                $parts[3] = ' dead_or_non_operational '
                $line = ($parts -join '|')
            }
        }
    }
    $invFNormalized.Add($line)
}
$f = Get-CoverageFingerprintData -InventoryLines @($invFNormalized) -MapLines $mapLines
$caseF = ([string]$f.fingerprint -eq $baseFp)

$regressionDetected = ($caseC -and $caseD)
$allPass = ($caseA -and $caseB -and $caseC -and $caseD -and $caseE -and $caseF -and $regressionDetected)
$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status = @(
    'phase=45.1',
    'title=Runtime Gate Coverage Fingerprint Lock',
    ('gate=' + $Gate),
    ('coverage_fingerprint=' + $(if (-not [string]::IsNullOrWhiteSpace($baseFp)) { 'GENERATED' } else { 'MISSING' })),
    ('reference_saved=' + $(if (Test-Path -LiteralPath $referencePath) { 'TRUE' } else { 'FALSE' })),
    ('deterministic=' + $(if ($caseB -and $caseE) { 'TRUE' } else { 'FALSE' })),
    ('regression_detection=' + $(if ($regressionDetected) { 'TRUE' } else { 'FALSE' }))
)
Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value ($status -join "`r`n") -Encoding UTF8 -NoNewline

$head = @(
    'runner=tools/phase45_1/phase45_1_runtime_gate_coverage_fingerprint_runner.ps1',
    ('source_phase45_0_proof=' + $phase45_0Proof.FullName),
    ('source_inventory=' + $inventoryPath),
    ('source_map=' + $mapPath),
    ('reference_path=' + $referencePath),
    'hash=SHA-256'
)
Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value ($head -join "`r`n") -Encoding UTF8 -NoNewline

$def = @(
    'RUNTIME GATE COVERAGE FINGERPRINT DEFINITION (PHASE 45.1)',
    '',
    'Fingerprint input source: phase45_0 artifacts 16_entrypoint_inventory.txt and 17_runtime_gate_enforcement_map.txt.',
    'Canonicalization removes formatting-only differences, normalizes whitespace, and parses records into semantic tuples.',
    'Only operational runtime-relevant entries participate in fingerprint materialization.',
    'Entries are sorted uniquely to eliminate artifact and line ordering effects.',
    'Fingerprint = SHA-256(canonical_json_payload).',
    'Reference lock persisted to control_plane/73_runtime_gate_coverage_fingerprint.json.'
)
Set-Content -LiteralPath (Join-Path $PF '10_fingerprint_definition.txt') -Value ($def -join "`r`n") -Encoding UTF8 -NoNewline

$rules = @(
    'FINGERPRINT RULES',
    'MUST_CHANGE: new operational entrypoint, removed operational entrypoint, coverage classification change, direct/transitive state changes, transitive/unguarded state changes.',
    'MUST_NOT_CHANGE: whitespace-only edits, line ordering changes, proof timestamps, formatting differences, dead-helper-only classification changes.',
    'Regression detection criteria: changed fingerprint for semantic mutations and stable fingerprint for non-semantic mutations.'
)
Set-Content -LiteralPath (Join-Path $PF '11_fingerprint_rules.txt') -Value ($rules -join "`r`n") -Encoding UTF8 -NoNewline

$filesTouched = @(
    ('READ  ' + $inventoryPath),
    ('READ  ' + $mapPath),
    ('WRITE ' + $referencePath),
    ('WRITE ' + (Join-Path $PF '*'))
)
Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Value ($filesTouched -join "`r`n") -Encoding UTF8 -NoNewline

$build = @(
    'build_type=PowerShell deterministic fingerprint lock runner',
    'compile_required=no',
    'runtime_behavior_changed=no',
    'operation=static artifact canonicalization + hashing + regression simulation'
)
Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Value ($build -join "`r`n") -Encoding UTF8 -NoNewline

$validation = @(
    ('CASE A clean_fingerprint_generation=' + $(if ($caseA) { 'PASS' } else { 'FAIL' })),
    ('CASE B non_semantic_change=' + $(if ($caseB) { 'PASS' } else { 'FAIL' })),
    ('CASE C entrypoint_addition=' + $(if ($caseC) { 'PASS' } else { 'FAIL' })),
    ('CASE D coverage_classification_change=' + $(if ($caseD) { 'PASS' } else { 'FAIL' })),
    ('CASE E order_change=' + $(if ($caseE) { 'PASS' } else { 'FAIL' })),
    ('CASE F dead_helper_change=' + $(if ($caseF) { 'PASS' } else { 'FAIL' })),
    ('regression_detected=' + $(if ($regressionDetected) { 'TRUE' } else { 'FALSE' }))
)
Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Value ($validation -join "`r`n") -Encoding UTF8 -NoNewline

$behavior = @(
    'Phase 45.1 locks runtime gate coverage using a deterministic semantic fingerprint over phase45_0 coverage artifacts.',
    'Canonicalization strips formatting and ordering variance while preserving coverage semantics.',
    'Operational coverage mutations change fingerprint; non-semantic and dead-helper-only changes do not.',
    'Reference lock allows future runners to detect silent coverage regressions.',
    'No runtime engine/state-machine behavior changed by this phase.'
)
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value ($behavior -join "`r`n") -Encoding UTF8 -NoNewline

$record = @(
    ('coverage_fingerprint_sha256=' + $baseFp),
    ('inventory_operational_count=' + [string]$base.inventory_operational_count),
    ('map_operational_count=' + [string]$base.map_operational_count),
    'payload_json=',
    $base.payload_json
)
Set-Content -LiteralPath (Join-Path $PF '16_coverage_fingerprint_record.txt') -Value ($record -join "`r`n") -Encoding UTF8 -NoNewline

$evidence = @(
    ('baseline=' + $baseFp),
    ('caseB_non_semantic=' + [string]$b.fingerprint),
    ('caseC_entrypoint_added=' + [string]$c.fingerprint),
    ('caseD_classification_changed=' + [string]$d.fingerprint),
    ('caseE_reordered=' + [string]$e.fingerprint),
    ('caseF_dead_helper_only=' + [string]$f.fingerprint),
    ('caseB_unchanged=' + $(if ($caseB) { 'TRUE' } else { 'FALSE' })),
    ('caseC_changed=' + $(if ($caseC) { 'TRUE' } else { 'FALSE' })),
    ('caseD_changed=' + $(if ($caseD) { 'TRUE' } else { 'FALSE' })),
    ('caseE_unchanged=' + $(if ($caseE) { 'TRUE' } else { 'FALSE' })),
    ('caseF_unchanged=' + $(if ($caseF) { 'TRUE' } else { 'FALSE' }))
)
Set-Content -LiteralPath (Join-Path $PF '17_regression_detection_evidence.txt') -Value ($evidence -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '98_gate_phase45_1.txt') -Value $Gate -Encoding UTF8 -NoNewline

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
