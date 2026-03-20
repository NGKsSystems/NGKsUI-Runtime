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

function Normalize-Token {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    return [regex]::Replace($Text.Trim(), '\s+', ' ')
}

function Get-LatestPhase45_6ProofPath {
    param([string]$ProofRoot)

    $dirs = @(
        Get-ChildItem -LiteralPath $ProofRoot -Directory |
        Where-Object { $_.Name -like 'phase45_6_certification_baseline_enforcement_coverage_audit_*' } |
        Sort-Object Name
    )
    if ($dirs.Count -eq 0) {
        throw 'No Phase 45.6 proof packet found under _proof.'
    }
    return $dirs[$dirs.Count - 1].FullName
}

function Convert-InventoryLineToCanonicalEntry {
    param([string]$Line)

    $trim = $Line.Trim()
    if ([string]::IsNullOrWhiteSpace($trim)) { return $null }
    if ($trim.StartsWith('file_path |')) { return $null }

    $parts = @($trim -split '\|')
    if ($parts.Count -lt 10) { return $null }

    $vals = @()
    foreach ($p in $parts) {
        $vals += (Normalize-Token -Text $p)
    }

    return [ordered]@{
        file_path = $vals[0]
        function_or_entrypoint = $vals[1]
        role = $vals[2]
        operational_or_dead = $vals[3]
        direct_gate_present = $vals[4]
        transitive_gate_present = $vals[5]
        gate_source_path = $vals[6]
        operation_type = $vals[7]
        coverage_classification = $vals[8]
        notes_on_evidence = $vals[9]
    }
}

function Convert-MapLineToCanonical {
    param([string]$Line)

    $t = Normalize-Token -Text $Line
    if ([string]::IsNullOrWhiteSpace($t)) { return '' }
    if ($t -eq 'CERTIFICATION BASELINE ENFORCEMENT MAP (PHASE 45.6)') { return '' }
    if ($t -eq 'Active operational surface:') { return '' }
    if ($t -eq 'Historical / dead helpers:') { return '' }
    if ($t -match '-> dead / non-operational$') { return '' }

    if ($t -match '^(.+?)\s*->\s*(directly gated|transitively gated|unguarded)\s*->\s*gate_source=(.+)$') {
        $fn = Normalize-Token -Text $Matches[1]
        $cls = Normalize-Token -Text $Matches[2]
        $src = Normalize-Token -Text $Matches[3]
        return ($fn + '|' + $cls + '|' + $src)
    }

    return ''
}

function Get-UnguardedCanonicalData {
    param([string[]]$Lines)

    $count = -1
    $paths = [System.Collections.Generic.List[string]]::new()

    foreach ($line in $Lines) {
        $t = Normalize-Token -Text $line
        if ($t -match '^unguarded_operational_path_count=(\d+)$') {
            $count = [int]$Matches[1]
            continue
        }
        if ($t -like 'status=*' -or $t -like 'missing_direct=*' -or $t -like 'missing_transitive=*' -or $t -eq 'UNGUARDED OPERATIONAL PATH REPORT') {
            continue
        }
        if ($t -match '\|') {
            $paths.Add($t)
        }
    }

    $sortedPaths = @($paths | Sort-Object -Unique)
    return [ordered]@{
        unguarded_operational_path_count = $count
        unguarded_operational_paths = $sortedPaths
    }
}

function Get-CoverageFingerprintData {
    param(
        [string[]]$InventoryLines,
        [string[]]$MapLines,
        [string[]]$UnguardedLines
    )

    $inventoryOperational = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $InventoryLines) {
        $entry = Convert-InventoryLineToCanonicalEntry -Line $line
        if ($null -eq $entry) { continue }

        # Dead/non-operational rows are intentionally excluded from fingerprint lock.
        if ([string]$entry.operational_or_dead -ne 'operational') {
            continue
        }

        $direct = if ([string]$entry.direct_gate_present -eq 'yes') { 'yes' } else { 'no' }
        $transitive = if ([string]$entry.transitive_gate_present -eq 'yes') { 'yes' } else { 'no' }

        $inventoryOperational.Add(
            ([string]$entry.function_or_entrypoint + '|' +
             [string]$entry.file_path + '|' +
             [string]$entry.role + '|' +
             [string]$entry.operation_type + '|' +
             [string]$entry.operational_or_dead + '|' +
             $direct + '|' +
             $transitive + '|' +
             [string]$entry.coverage_classification)
        )
    }

    $mapOperational = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $MapLines) {
        $m = Convert-MapLineToCanonical -Line $line
        if (-not [string]::IsNullOrWhiteSpace($m)) {
            $mapOperational.Add($m)
        }
    }

    $invSet = @($inventoryOperational | Sort-Object -Unique)
    $mapSet = @($mapOperational | Sort-Object -Unique)
    $unguardedObj = Get-UnguardedCanonicalData -Lines $UnguardedLines

    $payloadObj = [ordered]@{
        schema = 'phase45_7_certification_baseline_coverage_fingerprint_v1'
        inventory_operational = $invSet
        enforcement_map_operational = $mapSet
        unguarded = $unguardedObj
    }

    $payloadJson = $payloadObj | ConvertTo-Json -Depth 10 -Compress
    $fingerprint = Get-StringSha256Hex -Text $payloadJson

    return [ordered]@{
        payload_json = $payloadJson
        fingerprint = $fingerprint
        inventory_operational_count = $invSet.Count
        map_operational_count = $mapSet.Count
        unguarded_count = [int]$unguardedObj.unguarded_operational_path_count
    }
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ProofRoot = Join-Path $Root '_proof'
$PF = Join-Path $ProofRoot ('phase45_7_certification_baseline_coverage_fingerprint_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$phase45_6Proof = Get-LatestPhase45_6ProofPath -ProofRoot $ProofRoot
$inventoryPath = Join-Path $phase45_6Proof '16_entrypoint_inventory.txt'
$mapPath = Join-Path $phase45_6Proof '17_certification_baseline_enforcement_map.txt'
$unguardedPath = Join-Path $phase45_6Proof '18_unguarded_path_report.txt'

if (-not (Test-Path -LiteralPath $inventoryPath)) { throw 'Missing Phase 45.6 artifact: 16_entrypoint_inventory.txt' }
if (-not (Test-Path -LiteralPath $mapPath)) { throw 'Missing Phase 45.6 artifact: 17_certification_baseline_enforcement_map.txt' }
if (-not (Test-Path -LiteralPath $unguardedPath)) { throw 'Missing Phase 45.6 artifact: 18_unguarded_path_report.txt' }

$inventoryLines = @(Get-Content -LiteralPath $inventoryPath)
$mapLines = @(Get-Content -LiteralPath $mapPath)
$unguardedLines = @(Get-Content -LiteralPath $unguardedPath)

$base = Get-CoverageFingerprintData -InventoryLines $inventoryLines -MapLines $mapLines -UnguardedLines $unguardedLines
$baseFp = [string]$base.fingerprint

$referencePath = Join-Path $Root 'control_plane\76_certification_baseline_coverage_fingerprint.json'
$referenceObj = [ordered]@{
    schema = 'phase45_7_certification_baseline_coverage_fingerprint_reference_v1'
    generated_utc = (Get-Date).ToUniversalTime().ToString('o')
    source_phase45_6_proof = $phase45_6Proof
    source_inventory_artifact = $inventoryPath
    source_enforcement_map_artifact = $mapPath
    source_unguarded_report_artifact = $unguardedPath
    inventory_operational_count = [int]$base.inventory_operational_count
    map_operational_count = [int]$base.map_operational_count
    unguarded_operational_path_count = [int]$base.unguarded_count
    coverage_fingerprint_sha256 = $baseFp
}
$referenceObj | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $referencePath -Encoding UTF8 -NoNewline

$referenceRead = Get-Content -Raw -LiteralPath $referencePath | ConvertFrom-Json
$storedReferenceFp = [string]$referenceRead.coverage_fingerprint_sha256

$records = [System.Collections.Generic.List[object]]::new()

# CASE A — clean generation
$caseA = ($base.inventory_operational_count -gt 0 -and $base.map_operational_count -gt 0 -and (Test-Path -LiteralPath $referencePath) -and ($baseFp -eq $storedReferenceFp))
$records.Add([ordered]@{
    case = 'A'
    computed_fingerprint = $baseFp
    stored_reference_fingerprint = $storedReferenceFp
    fingerprint_match_status = $(if ($baseFp -eq $storedReferenceFp) { 'MATCH' } else { 'MISMATCH' })
    detected_change_type = 'clean_generation'
    certification_allowed_or_blocked = $(if ($caseA) { 'ALLOWED' } else { 'BLOCKED' })
})

# CASE B — non-semantic formatting-only change
$invB = [System.Collections.Generic.List[string]]::new()
foreach ($line in $inventoryLines) {
    $x = '  ' + $line + '  '
    $x = [regex]::Replace($x, '\|', ' | ')
    $x = [regex]::Replace($x, '\s+', ' ')
    $invB.Add($x)
}
$mapB = [System.Collections.Generic.List[string]]::new()
foreach ($line in $mapLines) {
    $mapB.Add([regex]::Replace(('   ' + $line + '   '), '\s+', ' '))
}
$uB = [System.Collections.Generic.List[string]]::new()
foreach ($line in $unguardedLines) {
    $uB.Add([regex]::Replace(('  ' + $line + '  '), '\s+', ' '))
}
$b = Get-CoverageFingerprintData -InventoryLines @($invB) -MapLines @($mapB) -UnguardedLines @($uB)
$caseB = ([string]$b.fingerprint -eq $baseFp)
$records.Add([ordered]@{
    case = 'B'
    computed_fingerprint = [string]$b.fingerprint
    stored_reference_fingerprint = $storedReferenceFp
    fingerprint_match_status = $(if ([string]$b.fingerprint -eq $storedReferenceFp) { 'MATCH' } else { 'MISMATCH' })
    detected_change_type = 'non_semantic_formatting_only'
    certification_allowed_or_blocked = $(if ($caseB) { 'ALLOWED' } else { 'BLOCKED' })
})

# CASE C — entrypoint addition (operational)
$invC = [System.Collections.Generic.List[string]]::new()
foreach ($line in $inventoryLines) { $invC.Add($line) }
$invC.Add('tools/phase45_7/simulated.ps1 | Invoke-GuardedSimulatedNewPath | runtime_gate_init_wrapper | operational | yes | no | Invoke-CertificationBaselineEnforcementGate | runtime_gate_initialization_wrapper | directly gated | evidence=simulated_entrypoint_addition')
$c = Get-CoverageFingerprintData -InventoryLines @($invC) -MapLines $mapLines -UnguardedLines $unguardedLines
$caseC = ([string]$c.fingerprint -ne $baseFp)
$records.Add([ordered]@{
    case = 'C'
    computed_fingerprint = [string]$c.fingerprint
    stored_reference_fingerprint = $storedReferenceFp
    fingerprint_match_status = $(if ([string]$c.fingerprint -eq $storedReferenceFp) { 'MATCH' } else { 'MISMATCH' })
    detected_change_type = 'operational_entrypoint_addition'
    certification_allowed_or_blocked = $(if ($caseC) { 'BLOCKED' } else { 'ALLOWED' })
})

# CASE D — coverage classification change on protected operational entrypoint
$invD = [System.Collections.Generic.List[string]]::new()
$changedD = $false
foreach ($line in $inventoryLines) {
    $entry = Convert-InventoryLineToCanonicalEntry -Line $line
    if (-not $changedD -and $null -ne $entry -and [string]$entry.operational_or_dead -eq 'operational' -and [string]$entry.coverage_classification -ne 'unguarded') {
        $parts = @($line -split '\|')
        if ($parts.Count -ge 10) {
            $parts[8] = ' unguarded '
            $line = ($parts -join '|')
            $changedD = $true
        }
    }
    $invD.Add($line)
}
$d = Get-CoverageFingerprintData -InventoryLines @($invD) -MapLines $mapLines -UnguardedLines $unguardedLines
$caseD = ($changedD -and ([string]$d.fingerprint -ne $baseFp))
$records.Add([ordered]@{
    case = 'D'
    computed_fingerprint = [string]$d.fingerprint
    stored_reference_fingerprint = $storedReferenceFp
    fingerprint_match_status = $(if ([string]$d.fingerprint -eq $storedReferenceFp) { 'MATCH' } else { 'MISMATCH' })
    detected_change_type = 'coverage_classification_change'
    certification_allowed_or_blocked = $(if ($caseD) { 'BLOCKED' } else { 'ALLOWED' })
})

# CASE E — order-only change
$header = @($inventoryLines | Select-Object -First 1)
$body = @($inventoryLines | Select-Object -Skip 1)
$rev = [System.Collections.Generic.List[string]]::new()
for ($i = $body.Count - 1; $i -ge 0; $i--) {
    $rev.Add($body[$i])
}
$invE = @($header + $rev.ToArray())
$e = Get-CoverageFingerprintData -InventoryLines $invE -MapLines $mapLines -UnguardedLines $unguardedLines
$caseE = ([string]$e.fingerprint -eq $baseFp)
$records.Add([ordered]@{
    case = 'E'
    computed_fingerprint = [string]$e.fingerprint
    stored_reference_fingerprint = $storedReferenceFp
    fingerprint_match_status = $(if ([string]$e.fingerprint -eq $storedReferenceFp) { 'MATCH' } else { 'MISMATCH' })
    detected_change_type = 'order_only_change'
    certification_allowed_or_blocked = $(if ($caseE) { 'ALLOWED' } else { 'BLOCKED' })
})

# CASE F — dead-helper-only change (must not alter fingerprint)
$invF = [System.Collections.Generic.List[string]]::new()
$changedF = $false
foreach ($line in $inventoryLines) {
    $entry = Convert-InventoryLineToCanonicalEntry -Line $line
    if (-not $changedF -and $null -ne $entry -and [string]$entry.operational_or_dead -ne 'operational') {
        $parts = @($line -split '\|')
        if ($parts.Count -ge 10) {
            $parts[8] = ' directly gated '
            $parts[9] = ' evidence=dead_helper_simulated_change '
            $line = ($parts -join '|')
            $changedF = $true
        }
    }
    $invF.Add($line)
}
$f = Get-CoverageFingerprintData -InventoryLines @($invF) -MapLines $mapLines -UnguardedLines $unguardedLines
$caseF = ($changedF -and ([string]$f.fingerprint -eq $baseFp))
$records.Add([ordered]@{
    case = 'F'
    computed_fingerprint = [string]$f.fingerprint
    stored_reference_fingerprint = $storedReferenceFp
    fingerprint_match_status = $(if ([string]$f.fingerprint -eq $storedReferenceFp) { 'MATCH' } else { 'MISMATCH' })
    detected_change_type = 'dead_helper_only_change'
    certification_allowed_or_blocked = $(if ($caseF) { 'ALLOWED' } else { 'BLOCKED' })
})

# CASE G — unguarded report change (simulated regression)
$uG = [System.Collections.Generic.List[string]]::new()
$countChanged = $false
foreach ($line in $unguardedLines) {
    $t = Normalize-Token -Text $line
    if (-not $countChanged -and $t -match '^unguarded_operational_path_count=\d+$') {
        $uG.Add('unguarded_operational_path_count=1')
        $countChanged = $true
        continue
    }
    $uG.Add($line)
}
if (-not $countChanged) {
    $uG.Add('unguarded_operational_path_count=1')
}
$uG.Add('tools/phase45_5/phase45_5_certification_baseline_enforcement_bypass_resistance_runner.ps1 | Invoke-GuardedRuntimeGateInitWrapper | runtime_gate_init_wrapper | evidence=simulated_unguarded_path')
$g = Get-CoverageFingerprintData -InventoryLines $inventoryLines -MapLines $mapLines -UnguardedLines @($uG)
$caseG = ([string]$g.fingerprint -ne $baseFp)
$records.Add([ordered]@{
    case = 'G'
    computed_fingerprint = [string]$g.fingerprint
    stored_reference_fingerprint = $storedReferenceFp
    fingerprint_match_status = $(if ([string]$g.fingerprint -eq $storedReferenceFp) { 'MATCH' } else { 'MISMATCH' })
    detected_change_type = 'unguarded_report_regression'
    certification_allowed_or_blocked = $(if ($caseG) { 'BLOCKED' } else { 'ALLOWED' })
})

$regressionDetected = ($caseC -and $caseD -and $caseG)
$allPass = ($caseA -and $caseB -and $caseC -and $caseD -and $caseE -and $caseF -and $caseG -and $regressionDetected)
$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status = @(
    'phase=45.7',
    'title=Certification Baseline Enforcement Coverage Fingerprint Lock',
    ('gate=' + $Gate),
    ('coverage_fingerprint_generated=' + $(if ($caseA) { 'TRUE' } else { 'FALSE' })),
    ('regression_detection_active=' + $(if ($regressionDetected) { 'TRUE' } else { 'FALSE' })),
    'runtime_state_machine_changed=FALSE'
)
Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value ($status -join "`r`n") -Encoding UTF8 -NoNewline

$head = @(
    'runner=tools/phase45_7/phase45_7_certification_baseline_coverage_fingerprint_runner.ps1',
    ('source_phase45_6_proof=' + $phase45_6Proof),
    ('inventory_artifact=' + $inventoryPath),
    ('enforcement_map_artifact=' + $mapPath),
    ('unguarded_report_artifact=' + $unguardedPath),
    ('reference_output=' + $referencePath)
)
Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value ($head -join "`r`n") -Encoding UTF8 -NoNewline

$def = @(
    'FINGERPRINT DEFINITION (PHASE 45.7)',
    '',
    'Fingerprint source model is semantic and operational-surface focused.',
    'Input artifacts: 16_entrypoint_inventory.txt, 17_certification_baseline_enforcement_map.txt, 18_unguarded_path_report.txt from latest phase45_6 proof.',
    'Canonicalized inventory includes only operational rows and retains role, operation type, operational/dead flag, direct/transitive flags, and coverage classification.',
    'Canonicalized map includes only operational mapping rows.',
    'Canonicalized unguarded report includes explicit unguarded count and normalized path records.',
    'All canonical record sets are sorted/unique before hashing; payload schema is fixed.',
    'Fingerprint algorithm: SHA-256(payload_json_utf8).'
)
Set-Content -LiteralPath (Join-Path $PF '10_fingerprint_definition.txt') -Value ($def -join "`r`n") -Encoding UTF8 -NoNewline

$rules = @(
    'FINGERPRINT RULES',
    '1) Deterministic for equivalent semantic coverage state.',
    '2) Ignore whitespace/formatting-only changes.',
    '3) Ignore ordering changes via sorted canonical sets.',
    '4) Ignore dead-helper-only changes by excluding dead/non-operational inventory rows from lock payload.',
    '5) Detect operational entrypoint additions/removals.',
    '6) Detect coverage classification and gate-directness/transitivity changes for operational entries.',
    '7) Detect unguarded path regressions via unguarded report canonical fields.',
    '8) Fail certification if expected regression deltas are not detected or if non-semantic changes alter fingerprint.'
)
Set-Content -LiteralPath (Join-Path $PF '11_fingerprint_rules.txt') -Value ($rules -join "`r`n") -Encoding UTF8 -NoNewline

$filesTouched = @(
    ('READ  ' + $inventoryPath),
    ('READ  ' + $mapPath),
    ('READ  ' + $unguardedPath),
    ('WRITE ' + $referencePath),
    ('WRITE ' + (Join-Path $PF '*'))
)
Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Value ($filesTouched -join "`r`n") -Encoding UTF8 -NoNewline

$build = @(
    'build_type=PowerShell semantic coverage fingerprint lock',
    'compile_required=no',
    ('base_fingerprint=' + $baseFp),
    ('inventory_operational_count=' + $base.inventory_operational_count),
    ('map_operational_count=' + $base.map_operational_count),
    ('unguarded_operational_path_count=' + $base.unguarded_count),
    'runtime_state_machine_changed=no'
)
Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Value ($build -join "`r`n") -Encoding UTF8 -NoNewline

$validation = @(
    ('CASE A clean_fingerprint_generation=' + $(if ($caseA) { 'PASS' } else { 'FAIL' })),
    ('CASE B non_semantic_change=' + $(if ($caseB) { 'PASS' } else { 'FAIL' })),
    ('CASE C entrypoint_addition=' + $(if ($caseC) { 'PASS' } else { 'FAIL' })),
    ('CASE D coverage_classification_change=' + $(if ($caseD) { 'PASS' } else { 'FAIL' })),
    ('CASE E order_change=' + $(if ($caseE) { 'PASS' } else { 'FAIL' })),
    ('CASE F dead_helper_change=' + $(if ($caseF) { 'PASS' } else { 'FAIL' })),
    ('CASE G unguarded_path_report_change=' + $(if ($caseG) { 'PASS' } else { 'FAIL' }))
)
Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Value ($validation -join "`r`n") -Encoding UTF8 -NoNewline

$summary = @(
    'Phase 45.7 locks the Phase 45.6 certification-baseline enforcement coverage model into a deterministic SHA-256 fingerprint reference.',
    'Fingerprint canonicalization is semantic and ordering-insensitive; formatting-only changes and dead-helper-only edits do not move the lock.',
    'Operational surface regressions (entrypoint addition, coverage classification drift, unguarded report drift) change fingerprint and are detected as certification blocks.',
    'The reference fingerprint is stored in control_plane/76_certification_baseline_coverage_fingerprint.json for future comparison/seal phases.',
    'Runtime behavior is unchanged because this phase only reads proof artifacts and writes certification metadata.'
)
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value ($summary -join "`r`n") -Encoding UTF8 -NoNewline

$recordLines = [System.Collections.Generic.List[string]]::new()
$recordLines.Add('case|computed_fingerprint|stored_reference_fingerprint|fingerprint_match_status|detected_change_type|certification_allowed_or_blocked')
foreach ($r in $records) {
    $recordLines.Add(
        [string]$r.case + '|' +
        [string]$r.computed_fingerprint + '|' +
        [string]$r.stored_reference_fingerprint + '|' +
        [string]$r.fingerprint_match_status + '|' +
        [string]$r.detected_change_type + '|' +
        [string]$r.certification_allowed_or_blocked
    )
}
Set-Content -LiteralPath (Join-Path $PF '16_coverage_fingerprint_record.txt') -Value (($recordLines.ToArray()) -join "`r`n") -Encoding UTF8 -NoNewline

$evidence = @(
    ('base_fingerprint=' + $baseFp),
    ('caseB_fingerprint=' + [string]$b.fingerprint),
    ('caseC_fingerprint=' + [string]$c.fingerprint),
    ('caseD_fingerprint=' + [string]$d.fingerprint),
    ('caseE_fingerprint=' + [string]$e.fingerprint),
    ('caseF_fingerprint=' + [string]$f.fingerprint),
    ('caseG_fingerprint=' + [string]$g.fingerprint),
    ('regression_detected=' + $(if ($regressionDetected) { 'TRUE' } else { 'FALSE' })),
    ('caseB_unchanged=' + $(if ($caseB) { 'TRUE' } else { 'FALSE' })),
    ('caseE_unchanged=' + $(if ($caseE) { 'TRUE' } else { 'FALSE' })),
    ('caseF_unchanged=' + $(if ($caseF) { 'TRUE' } else { 'FALSE' })),
    ('caseC_changed=' + $(if ($caseC) { 'TRUE' } else { 'FALSE' })),
    ('caseD_changed=' + $(if ($caseD) { 'TRUE' } else { 'FALSE' })),
    ('caseG_changed=' + $(if ($caseG) { 'TRUE' } else { 'FALSE' }))
)
Set-Content -LiteralPath (Join-Path $PF '17_regression_detection_evidence.txt') -Value ($evidence -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '98_gate_phase45_7.txt') -Value $Gate -Encoding UTF8 -NoNewline

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
