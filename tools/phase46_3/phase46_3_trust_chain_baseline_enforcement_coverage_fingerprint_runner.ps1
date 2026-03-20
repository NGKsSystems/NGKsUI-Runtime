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

function Get-LatestPhase46_2ProofPath {
    param([string]$ProofRoot)

    $dirs = @(
        Get-ChildItem -LiteralPath $ProofRoot -Directory |
        Where-Object { $_.Name -like 'phase46_2_trust_chain_baseline_enforcement_coverage_audit_*' } |
        Sort-Object Name
    )
    if ($dirs.Count -eq 0) {
        throw 'No Phase 46.2 proof packet found under _proof.'
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

function Convert-MapLineToCanonicalEntry {
    param([string]$Line)

    $t = Normalize-Token -Text $Line
    if ([string]::IsNullOrWhiteSpace($t)) { return $null }
    if ($t -eq 'TRUST-CHAIN BASELINE ENFORCEMENT MAP (PHASE 46.2)') { return $null }
    if ($t -eq 'Active operational surface:') { return $null }
    if ($t -eq 'Historical / dead helpers:') { return $null }

    if ($t -match '^(.+?)\|\s*(.+?)\s*->\s*(directly gated|transitively gated|unguarded)\s*->\s*gate_source=(.+)$') {
        return [ordered]@{
            file_path = Normalize-Token -Text $Matches[1]
            function_or_entrypoint = Normalize-Token -Text $Matches[2]
            coverage_classification = Normalize-Token -Text $Matches[3]
            gate_source_path = Normalize-Token -Text $Matches[4]
        }
    }

    if ($t -match '^(.+?)\|\s*(.+?)\s*->\s*dead / non-operational$') {
        return [ordered]@{
            file_path = Normalize-Token -Text $Matches[1]
            function_or_entrypoint = Normalize-Token -Text $Matches[2]
            coverage_classification = 'dead / non-operational'
            gate_source_path = ''
        }
    }

    return $null
}

function Get-UnguardedCanonicalData {
    param([string[]]$Lines)

    $count = -1
    $paths = [System.Collections.Generic.List[string]]::new()
    $extras = [System.Collections.Generic.List[string]]::new()

    foreach ($line in $Lines) {
        $t = Normalize-Token -Text $line
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        if ($t -eq 'UNGUARDED OPERATIONAL PATH REPORT') { continue }
        if ($t -match '^unguarded_operational_path_count=(\d+)$') {
            $count = [int]$Matches[1]
            continue
        }
        if ($t -like 'status=*' -or $t -like 'missing_direct=*' -or $t -like 'missing_transitive=*' -or $t -like 'missing_historical=*' -or $t -like 'missing_from_phase46_1_inventory=*' -or $t -like 'extra_in_phase46_1_inventory=*') {
            $extras.Add($t)
            continue
        }
        if ($t -match '\|') {
            $paths.Add($t)
        }
    }

    return [ordered]@{
        unguarded_operational_path_count = $count
        unguarded_operational_paths = @($paths | Sort-Object -Unique)
        report_semantic_state = @($extras | Sort-Object -Unique)
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

        if ([string]$entry.operational_or_dead -ne 'operational') {
            continue
        }

        $inventoryOperational.Add(
            ([string]$entry.file_path + '|' +
             [string]$entry.function_or_entrypoint + '|' +
             [string]$entry.role + '|' +
             [string]$entry.operation_type + '|' +
             [string]$entry.operational_or_dead + '|' +
             [string]$entry.direct_gate_present + '|' +
             [string]$entry.transitive_gate_present + '|' +
             [string]$entry.gate_source_path + '|' +
             [string]$entry.coverage_classification)
        )
    }

    $mapOperational = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $MapLines) {
        $entry = Convert-MapLineToCanonicalEntry -Line $line
        if ($null -eq $entry) { continue }
        if ([string]$entry.coverage_classification -eq 'dead / non-operational') {
            continue
        }
        $mapOperational.Add(
            ([string]$entry.file_path + '|' +
             [string]$entry.function_or_entrypoint + '|' +
             [string]$entry.coverage_classification + '|' +
             [string]$entry.gate_source_path)
        )
    }

    $invSet = @($inventoryOperational | Sort-Object -Unique)
    $mapSet = @($mapOperational | Sort-Object -Unique)
    $unguardedObj = Get-UnguardedCanonicalData -Lines $UnguardedLines

    $payloadObj = [ordered]@{
        schema = 'phase46_3_trust_chain_baseline_enforcement_coverage_fingerprint_v1'
        inventory_operational = $invSet
        enforcement_map_operational = $mapSet
        unguarded = $unguardedObj
    }

    $payloadJson = $payloadObj | ConvertTo-Json -Depth 12 -Compress
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
$PF = Join-Path $ProofRoot ('phase46_3_trust_chain_baseline_enforcement_coverage_fingerprint_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$phase46_2Proof = Get-LatestPhase46_2ProofPath -ProofRoot $ProofRoot
$inventoryPath = Join-Path $phase46_2Proof '16_entrypoint_inventory.txt'
$mapPath = Join-Path $phase46_2Proof '17_frozen_baseline_enforcement_map.txt'
$unguardedPath = Join-Path $phase46_2Proof '18_unguarded_path_report.txt'

if (-not (Test-Path -LiteralPath $inventoryPath)) { throw 'Missing Phase 46.2 artifact: 16_entrypoint_inventory.txt' }
if (-not (Test-Path -LiteralPath $mapPath)) { throw 'Missing Phase 46.2 artifact: 17_frozen_baseline_enforcement_map.txt' }
if (-not (Test-Path -LiteralPath $unguardedPath)) { throw 'Missing Phase 46.2 artifact: 18_unguarded_path_report.txt' }

$inventoryLines = @(Get-Content -LiteralPath $inventoryPath)
$mapLines = @(Get-Content -LiteralPath $mapPath)
$unguardedLines = @(Get-Content -LiteralPath $unguardedPath)

$base = Get-CoverageFingerprintData -InventoryLines $inventoryLines -MapLines $mapLines -UnguardedLines $unguardedLines
$baseFp = [string]$base.fingerprint

$referencePath = Join-Path $Root 'control_plane\79_trust_chain_baseline_enforcement_coverage_fingerprint.json'
$referenceObj = [ordered]@{
    schema = 'phase46_3_trust_chain_baseline_enforcement_coverage_fingerprint_reference_v1'
    generated_utc = (Get-Date).ToUniversalTime().ToString('o')
    source_phase46_2_proof = $phase46_2Proof
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

# CASE A — clean fingerprint generation
$caseA = ($base.inventory_operational_count -gt 0 -and $base.map_operational_count -gt 0 -and (Test-Path -LiteralPath $referencePath) -and ($baseFp -eq $storedReferenceFp))
$records.Add([ordered]@{
    case = 'A'
    computed_fingerprint = $baseFp
    stored_reference_fingerprint = $storedReferenceFp
    fingerprint_match_status = $(if ($baseFp -eq $storedReferenceFp) { 'MATCH' } else { 'MISMATCH' })
    detected_change_type = 'clean_generation'
    certification_allowed_or_blocked = $(if ($caseA) { 'ALLOWED' } else { 'BLOCKED' })
})

# CASE B — non-semantic change
$invB = [System.Collections.Generic.List[string]]::new()
foreach ($line in $inventoryLines) {
    $x = '  ' + $line + '  '
    $x = [regex]::Replace($x, '\|', ' | ')
    $x = [regex]::Replace($x, '\s+', ' ')
    $invB.Add($x)
}
$mapB = [System.Collections.Generic.List[string]]::new()
foreach ($line in $mapLines) {
    $x = [regex]::Replace(('   ' + $line + '   '), '\s+', ' ')
    $mapB.Add($x)
}
$uB = [System.Collections.Generic.List[string]]::new()
foreach ($line in $unguardedLines) {
    $x = [regex]::Replace(('  ' + $line + '  '), '\s+', ' ')
    $uB.Add($x)
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

# CASE C — entrypoint addition
$invC = [System.Collections.Generic.List[string]]::new()
foreach ($line in $inventoryLines) { $invC.Add($line) }
$invC.Add('tools/phase46_1/simulated.ps1 | Invoke-GuardedSimulatedFrozenBaselinePath | frozen_baseline_snapshot_load_entrypoint | operational | yes | no | Invoke-FrozenBaselineTrustChainEnforcementGate | load_frozen_baseline_snapshot | directly gated | evidence=simulated_entrypoint_addition')
$mapC = [System.Collections.Generic.List[string]]::new()
foreach ($line in $mapLines) { $mapC.Add($line) }
$mapC.Insert(2, 'tools/phase46_1/simulated.ps1 | Invoke-GuardedSimulatedFrozenBaselinePath -> directly gated -> gate_source=Invoke-FrozenBaselineTrustChainEnforcementGate')
$c = Get-CoverageFingerprintData -InventoryLines @($invC) -MapLines @($mapC) -UnguardedLines $unguardedLines
$caseC = ([string]$c.fingerprint -ne $baseFp)
$records.Add([ordered]@{
    case = 'C'
    computed_fingerprint = [string]$c.fingerprint
    stored_reference_fingerprint = $storedReferenceFp
    fingerprint_match_status = $(if ([string]$c.fingerprint -eq $storedReferenceFp) { 'MATCH' } else { 'MISMATCH' })
    detected_change_type = 'operational_entrypoint_addition'
    certification_allowed_or_blocked = $(if ($caseC) { 'BLOCKED' } else { 'ALLOWED' })
})

# CASE D — coverage classification change
$invD = [System.Collections.Generic.List[string]]::new()
$mapD = [System.Collections.Generic.List[string]]::new()
$changedD = $false
foreach ($line in $inventoryLines) {
    $entry = Convert-InventoryLineToCanonicalEntry -Line $line
    if (-not $changedD -and $null -ne $entry -and [string]$entry.operational_or_dead -eq 'operational' -and [string]$entry.coverage_classification -eq 'directly gated') {
        $parts = @($line -split '\|')
        if ($parts.Count -ge 10) {
            $parts[4] = ' no '
            $parts[5] = ' yes '
            $parts[8] = ' transitively gated '
            $line = ($parts -join '|')
            $changedD = $true
        }
    }
    $invD.Add($line)
}
foreach ($line in $mapLines) {
    if ($changedD -or $line -notmatch '-> directly gated ->') {
        $mapD.Add($line)
        continue
    }
    $mapD.Add(($line -replace '-> directly gated ->', '-> transitively gated ->'))
    $changedD = $true
}
$d = Get-CoverageFingerprintData -InventoryLines @($invD) -MapLines @($mapD) -UnguardedLines $unguardedLines
$caseD = ([string]$d.fingerprint -ne $baseFp)
$records.Add([ordered]@{
    case = 'D'
    computed_fingerprint = [string]$d.fingerprint
    stored_reference_fingerprint = $storedReferenceFp
    fingerprint_match_status = $(if ([string]$d.fingerprint -eq $storedReferenceFp) { 'MATCH' } else { 'MISMATCH' })
    detected_change_type = 'coverage_classification_change'
    certification_allowed_or_blocked = $(if ($caseD) { 'BLOCKED' } else { 'ALLOWED' })
})

# CASE E — order change
$headerInv = @($inventoryLines | Select-Object -First 1)
$bodyInv = @($inventoryLines | Select-Object -Skip 1)
$revInv = [System.Collections.Generic.List[string]]::new()
for ($i = $bodyInv.Count - 1; $i -ge 0; $i--) { $revInv.Add($bodyInv[$i]) }
$invE = @($headerInv + $revInv.ToArray())

$mapHeader = @($mapLines | Select-Object -First 3)
$mapBody = @($mapLines | Select-Object -Skip 3)
$revMap = [System.Collections.Generic.List[string]]::new()
for ($i = $mapBody.Count - 1; $i -ge 0; $i--) { $revMap.Add($mapBody[$i]) }
$mapE = @($mapHeader + $revMap.ToArray())

$e = Get-CoverageFingerprintData -InventoryLines $invE -MapLines $mapE -UnguardedLines $unguardedLines
$caseE = ([string]$e.fingerprint -eq $baseFp)
$records.Add([ordered]@{
    case = 'E'
    computed_fingerprint = [string]$e.fingerprint
    stored_reference_fingerprint = $storedReferenceFp
    fingerprint_match_status = $(if ([string]$e.fingerprint -eq $storedReferenceFp) { 'MATCH' } else { 'MISMATCH' })
    detected_change_type = 'order_only_change'
    certification_allowed_or_blocked = $(if ($caseE) { 'ALLOWED' } else { 'BLOCKED' })
})

# CASE F — dead helper change only
$invF = [System.Collections.Generic.List[string]]::new()
$changedF = $false
foreach ($line in $inventoryLines) {
    $entry = Convert-InventoryLineToCanonicalEntry -Line $line
    if (-not $changedF -and $null -ne $entry -and [string]$entry.operational_or_dead -ne 'operational') {
        $parts = @($line -split '\|')
        if ($parts.Count -ge 10) {
            $parts[8] = ' directly gated '
            $parts[9] = ' evidence=dead_helper_cosmetic_change '
            $line = ($parts -join '|')
            $changedF = $true
        }
    }
    $invF.Add($line)
}
$mapF = [System.Collections.Generic.List[string]]::new()
$mapChangedF = $false
foreach ($line in $mapLines) {
    if (-not $mapChangedF -and $line -match '-> dead / non-operational$') {
        $mapF.Add(($line + '   '))
        $mapChangedF = $true
    } else {
        $mapF.Add($line)
    }
}
$f = Get-CoverageFingerprintData -InventoryLines @($invF) -MapLines @($mapF) -UnguardedLines $unguardedLines
$caseF = ([string]$f.fingerprint -eq $baseFp)
$records.Add([ordered]@{
    case = 'F'
    computed_fingerprint = [string]$f.fingerprint
    stored_reference_fingerprint = $storedReferenceFp
    fingerprint_match_status = $(if ([string]$f.fingerprint -eq $storedReferenceFp) { 'MATCH' } else { 'MISMATCH' })
    detected_change_type = 'dead_helper_only_change'
    certification_allowed_or_blocked = $(if ($caseF) { 'ALLOWED' } else { 'BLOCKED' })
})

# CASE G — unguarded path report change
$uG = [System.Collections.Generic.List[string]]::new()
$countChangedG = $false
foreach ($line in $unguardedLines) {
    $t = Normalize-Token -Text $line
    if (-not $countChangedG -and $t -match '^unguarded_operational_path_count=\d+$') {
        $uG.Add('unguarded_operational_path_count=1')
        $countChangedG = $true
        continue
    }
    $uG.Add($line)
}
$uG.Add('tools/phase46_1/phase46_1_trust_chain_baseline_enforcement_bypass_resistance_runner.ps1 | Invoke-GuardedRuntimeInitWrapper | runtime_initialization_wrapper | evidence=simulated_unguarded_path')
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

# CASE H — operational/dead reclassification
$invH = [System.Collections.Generic.List[string]]::new()
$changedH = $false
foreach ($line in $inventoryLines) {
    $entry = Convert-InventoryLineToCanonicalEntry -Line $line
    if (-not $changedH -and $null -ne $entry -and [string]$entry.function_or_entrypoint -eq 'Test-LegacyTrustChain' -and [string]$entry.file_path -eq 'tools/phase46_1/phase46_1_trust_chain_baseline_enforcement_bypass_resistance_runner.ps1') {
        $parts = @($line -split '\|')
        if ($parts.Count -ge 10) {
            $parts[3] = ' dead / non-operational '
            $parts[4] = ' no '
            $parts[5] = ' no '
            $parts[6] = '  '
            $parts[8] = ' dead / non-operational '
            $line = ($parts -join '|')
            $changedH = $true
        }
    }
    $invH.Add($line)
}
$mapH = [System.Collections.Generic.List[string]]::new()
foreach ($line in $mapLines) {
    if ($line -match '^tools/phase46_1/phase46_1_trust_chain_baseline_enforcement_bypass_resistance_runner\.ps1 \| Test-LegacyTrustChain -> transitively gated -> gate_source=') {
        $mapH.Add('tools/phase46_1/phase46_1_trust_chain_baseline_enforcement_bypass_resistance_runner.ps1 | Test-LegacyTrustChain -> dead / non-operational')
    } else {
        $mapH.Add($line)
    }
}
$h = Get-CoverageFingerprintData -InventoryLines @($invH) -MapLines @($mapH) -UnguardedLines $unguardedLines
$caseH = ($changedH -and ([string]$h.fingerprint -ne $baseFp))
$records.Add([ordered]@{
    case = 'H'
    computed_fingerprint = [string]$h.fingerprint
    stored_reference_fingerprint = $storedReferenceFp
    fingerprint_match_status = $(if ([string]$h.fingerprint -eq $storedReferenceFp) { 'MATCH' } else { 'MISMATCH' })
    detected_change_type = 'operational_dead_reclassification'
    certification_allowed_or_blocked = $(if ($caseH) { 'BLOCKED' } else { 'ALLOWED' })
})

$regressionDetected = ($caseC -and $caseD -and $caseG -and $caseH)
$allPass = ($caseA -and $caseB -and $caseC -and $caseD -and $caseE -and $caseF -and $caseG -and $caseH -and $regressionDetected)
$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status = @(
    'phase=46.3',
    'title=Trust-Chain Baseline Enforcement Coverage Fingerprint Lock',
    ('gate=' + $Gate),
    ('coverage_fingerprint_generated=' + $(if ($caseA) { 'TRUE' } else { 'FALSE' })),
    ('reference_saved=' + $(if (Test-Path -LiteralPath $referencePath) { 'TRUE' } else { 'FALSE' })),
    ('regression_detection_active=' + $(if ($regressionDetected) { 'TRUE' } else { 'FALSE' })),
    'runtime_state_machine_changed=FALSE'
)
Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value ($status -join "`r`n") -Encoding UTF8 -NoNewline

$head = @(
    'runner=tools/phase46_3/phase46_3_trust_chain_baseline_enforcement_coverage_fingerprint_runner.ps1',
    ('source_phase46_2_proof=' + $phase46_2Proof),
    ('inventory_artifact=' + $inventoryPath),
    ('enforcement_map_artifact=' + $mapPath),
    ('unguarded_report_artifact=' + $unguardedPath),
    ('reference_output=' + $referencePath)
)
Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value ($head -join "`r`n") -Encoding UTF8 -NoNewline

$def = @(
    'FINGERPRINT DEFINITION (PHASE 46.3)',
    '',
    'Fingerprint source model is semantic and operational-surface focused.',
    'Input artifacts: 16_entrypoint_inventory.txt, 17_frozen_baseline_enforcement_map.txt, and 18_unguarded_path_report.txt from the latest Phase 46.2 proof packet.',
    'Canonicalized inventory includes only operational rows and retains file path, function name, role, operation type, operational/dead state, direct/transitive flags, gate source, and coverage classification.',
    'Canonicalized enforcement map includes only operational mapping rows and retains file path, function name, coverage classification, and gate source.',
    'Canonicalized unguarded report includes explicit unguarded count, sorted unguarded path records, and normalized semantic status lines.',
    'Dead or historical helper rows are intentionally excluded from the lock payload so dead-helper-only cosmetic changes do not alter the fingerprint.',
    'All canonical record sets are sorted and deduplicated before hashing; payload schema is fixed.',
    'Fingerprint algorithm: SHA-256(payload_json_utf8).'
)
Set-Content -LiteralPath (Join-Path $PF '10_fingerprint_definition.txt') -Value ($def -join "`r`n") -Encoding UTF8 -NoNewline

$rules = @(
    'FINGERPRINT RULES',
    '1) Deterministic for equivalent semantic coverage state.',
    '2) Ignore whitespace and formatting-only changes.',
    '3) Ignore ordering changes via sorted canonical sets.',
    '4) Ignore dead-helper-only cosmetic changes by excluding dead / non-operational rows from the lock payload.',
    '5) Detect operational entrypoint additions and removals.',
    '6) Detect coverage classification and gate-directness/transitivity changes for operational entries.',
    '7) Detect operational-to-dead or dead-to-operational reclassification of real reachable helpers because operational membership changes the locked payload.',
    '8) Detect unguarded path regressions via the canonical unguarded report state.',
    '9) Certification fails whenever a real coverage regression changes the computed fingerprint unexpectedly.',
    '10) Runtime behavior must remain unchanged because this phase only reads proof artifacts and writes a certification reference.'
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
    'build_type=PowerShell deterministic_coverage_fingerprint_lock',
    'compile_required=no',
    'runtime_validation_used=no_additional_runtime_execution_required',
    'canonical_input_source=latest_phase46_2_proof_artifacts',
    'runtime_state_machine_changed=no',
    ('inventory_operational_count=' + $base.inventory_operational_count),
    ('map_operational_count=' + $base.map_operational_count),
    ('unguarded_operational_path_count=' + $base.unguarded_count)
)
Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Value ($build -join "`r`n") -Encoding UTF8 -NoNewline

$validation = @(
    ('CASE A clean_fingerprint_generation=' + $(if ($caseA) { 'PASS' } else { 'FAIL' })),
    ('CASE B non_semantic_change=' + $(if ($caseB) { 'PASS' } else { 'FAIL' })),
    ('CASE C entrypoint_addition=' + $(if ($caseC) { 'PASS' } else { 'FAIL' })),
    ('CASE D coverage_classification_change=' + $(if ($caseD) { 'PASS' } else { 'FAIL' })),
    ('CASE E order_change=' + $(if ($caseE) { 'PASS' } else { 'FAIL' })),
    ('CASE F dead_helper_change=' + $(if ($caseF) { 'PASS' } else { 'FAIL' })),
    ('CASE G unguarded_path_report_change=' + $(if ($caseG) { 'PASS' } else { 'FAIL' })),
    ('CASE H operational_dead_reclassification=' + $(if ($caseH) { 'PASS' } else { 'FAIL' }))
)
Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Value ($validation -join "`r`n") -Encoding UTF8 -NoNewline

$summary = @(
    'Phase 46.3 locks the Phase 46.2 completeness proof into a deterministic coverage fingerprint derived from the operational entrypoint inventory, operational enforcement map, and semantic unguarded-path state.',
    'The fingerprint ignores whitespace, formatting, ordering, proof-folder timestamps, and dead-helper-only cosmetic changes by canonicalizing tokens, sorting record sets, and excluding dead or historical rows from the lock payload.',
    'The fingerprint remains sensitive to real frozen-baseline enforcement regressions, including operational entrypoint additions, coverage classification drift, unguarded-path regressions, and operational or dead reclassification of real reachable helpers.',
    'The stored certification reference is written to control_plane/79_trust_chain_baseline_enforcement_coverage_fingerprint.json and can be used by later phases to detect structural regressions in the frozen-baseline enforcement surface.',
    'Regression detection works because any semantic change to the operational coverage model alters the canonical payload and therefore changes the SHA-256 fingerprint.',
    'Runtime behavior remained unchanged because the runner only reads completed Phase 46.2 proof artifacts and writes a new reference artifact plus proof evidence.'
)
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value ($summary -join "`r`n") -Encoding UTF8 -NoNewline

$recordLines = [System.Collections.Generic.List[string]]::new()
$recordLines.Add('case|computed_fingerprint|stored_reference_fingerprint|fingerprint_match_status|detected_change_type|certification_allowed_or_blocked')
foreach ($record in $records) {
    $recordLines.Add(
        [string]$record.case + '|' +
        [string]$record.computed_fingerprint + '|' +
        [string]$record.stored_reference_fingerprint + '|' +
        [string]$record.fingerprint_match_status + '|' +
        [string]$record.detected_change_type + '|' +
        [string]$record.certification_allowed_or_blocked
    )
}
Set-Content -LiteralPath (Join-Path $PF '16_coverage_fingerprint_record.txt') -Value (($recordLines.ToArray()) -join "`r`n") -Encoding UTF8 -NoNewline

$evidence = @(
    ('base_fingerprint=' + $baseFp),
    ('stored_reference_fingerprint=' + $storedReferenceFp),
    ('caseB_non_semantic_unchanged=' + $(if ($caseB) { 'TRUE' } else { 'FALSE' })),
    ('caseC_entrypoint_addition_changed=' + $(if ($caseC) { 'TRUE' } else { 'FALSE' })),
    ('caseD_coverage_classification_changed=' + $(if ($caseD) { 'TRUE' } else { 'FALSE' })),
    ('caseE_order_only_unchanged=' + $(if ($caseE) { 'TRUE' } else { 'FALSE' })),
    ('caseF_dead_helper_only_unchanged=' + $(if ($caseF) { 'TRUE' } else { 'FALSE' })),
    ('caseG_unguarded_report_changed=' + $(if ($caseG) { 'TRUE' } else { 'FALSE' })),
    ('caseH_operational_dead_reclassification_changed=' + $(if ($caseH) { 'TRUE' } else { 'FALSE' })),
    ('regression_detected=' + $(if ($regressionDetected) { 'TRUE' } else { 'FALSE' }))
)
Set-Content -LiteralPath (Join-Path $PF '17_regression_detection_evidence.txt') -Value ($evidence -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '98_gate_phase46_3.txt') -Value $Gate -Encoding UTF8 -NoNewline

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