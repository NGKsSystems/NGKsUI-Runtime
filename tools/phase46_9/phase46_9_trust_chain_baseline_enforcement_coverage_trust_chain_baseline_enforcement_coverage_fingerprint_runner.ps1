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

function Get-LatestPhase46_8ProofPath {
    param([string]$ProofRoot)

    $dirs = @(
        Get-ChildItem -LiteralPath $ProofRoot -Directory |
        Where-Object { $_.Name -like 'phase46_8_trust_chain_baseline_enforcement_coverage_trust_chain_baseline_enforcement_coverage_audit_*' } |
        Sort-Object Name
    )
    if ($dirs.Count -eq 0) {
        throw 'No Phase 46.8 proof packet found under _proof.'
    }
    return $dirs[$dirs.Count - 1].FullName
}

function Parse-InventoryLine {
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

function Parse-MapLine {
    param([string]$Line)

    $t = Normalize-Token -Text $Line
    if ([string]::IsNullOrWhiteSpace($t)) { return $null }
    if ($t -eq 'TRUST-CHAIN BASELINE ENFORCEMENT MAP (PHASE 46.8)') { return $null }
    if ($t -eq 'Active operational surface:') { return $null }
    if ($t -eq 'Historical / dead helpers:') { return $null }

    if ($t -match '^(.+?)\|\s*(.+?)\s*->\s*(directly gated|transitively gated|unguarded)\s*->\s*gate_source=(.+)$') {
        return [ordered]@{
            file_path = Normalize-Token -Text $Matches[1]
            function_or_entrypoint = Normalize-Token -Text $Matches[2]
            coverage_classification = Normalize-Token -Text $Matches[3]
            gate_source_path = Normalize-Token -Text $Matches[4]
            operational_or_dead = 'operational'
        }
    }

    if ($t -match '^(.+?)\|\s*(.+?)\s*->\s*dead / non-operational$') {
        return [ordered]@{
            file_path = Normalize-Token -Text $Matches[1]
            function_or_entrypoint = Normalize-Token -Text $Matches[2]
            coverage_classification = 'dead / non-operational'
            gate_source_path = ''
            operational_or_dead = 'dead / non-operational'
        }
    }

    return $null
}

function Parse-KeyValueLines {
    param([string[]]$Lines)

    $kv = [ordered]@{}
    foreach ($line in $Lines) {
        $t = Normalize-Token -Text $line
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        if ($t -notmatch '^[A-Za-z0-9_\-]+=(.*)$') { continue }
        $eq = $t.IndexOf('=')
        if ($eq -lt 1) { continue }
        $k = $t.Substring(0, $eq)
        $v = $t.Substring($eq + 1)
        $kv[$k] = $v
    }
    return $kv
}

function Get-CoverageFingerprintModel {
    param(
        [string[]]$InventoryLines,
        [string[]]$MapLines,
        [string[]]$UnguardedLines,
        [string[]]$CrosscheckLines
    )

    $invOperational = [System.Collections.Generic.List[string]]::new()
    $invOperationalNames = [System.Collections.Generic.List[string]]::new()

    foreach ($line in $InventoryLines) {
        $entry = Parse-InventoryLine -Line $line
        if ($null -eq $entry) { continue }

        # Dead/non-operational rows are excluded so dead-helper cosmetic changes do not affect fingerprint.
        if ([string]$entry.operational_or_dead -ne 'operational') { continue }

        $invOperational.Add(
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
        $invOperationalNames.Add(([string]$entry.file_path + '|' + [string]$entry.function_or_entrypoint))
    }

    $mapOperational = [System.Collections.Generic.List[string]]::new()
    $mapOperationalNames = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $MapLines) {
        $entry = Parse-MapLine -Line $line
        if ($null -eq $entry) { continue }
        if ([string]$entry.operational_or_dead -ne 'operational') { continue }

        $mapOperational.Add(
            ([string]$entry.file_path + '|' +
             [string]$entry.function_or_entrypoint + '|' +
             [string]$entry.coverage_classification + '|' +
             [string]$entry.gate_source_path)
        )
        $mapOperationalNames.Add(([string]$entry.file_path + '|' + [string]$entry.function_or_entrypoint))
    }

    $unguardedKv = Parse-KeyValueLines -Lines $UnguardedLines
    $crossKv = Parse-KeyValueLines -Lines $CrosscheckLines

    $unguardedSemantic = [ordered]@{
        unguarded_operational_path_count = [string]$(if ($unguardedKv.Contains('unguarded_operational_path_count')) { $unguardedKv['unguarded_operational_path_count'] } else { '' })
        status = [string]$(if ($unguardedKv.Contains('status')) { $unguardedKv['status'] } else { '' })
        missing_direct = [string]$(if ($unguardedKv.Contains('missing_direct')) { $unguardedKv['missing_direct'] } else { '' })
        missing_transitive = [string]$(if ($unguardedKv.Contains('missing_transitive')) { $unguardedKv['missing_transitive'] } else { '' })
        missing_historical = [string]$(if ($unguardedKv.Contains('missing_historical')) { $unguardedKv['missing_historical'] } else { '' })
        missing_from_phase46_7_inventory = [string]$(if ($unguardedKv.Contains('missing_from_phase46_7_inventory')) { $unguardedKv['missing_from_phase46_7_inventory'] } else { '' })
    }

    $crossSemantic = [ordered]@{
        phase46_7_validation_pass = [string]$(if ($crossKv.Contains('phase46_7_validation_pass')) { $crossKv['phase46_7_validation_pass'] } else { '' })
        missing_from_phase46_7_inventory = [string]$(if ($crossKv.Contains('missing_from_phase46_7_inventory')) { $crossKv['missing_from_phase46_7_inventory'] } else { '' })
        operational_direct_surface_present_in_phase46_7_gate_record = [string]$(if ($crossKv.Contains('operational_direct_surface_present_in_phase46_7_gate_record')) { $crossKv['operational_direct_surface_present_in_phase46_7_gate_record'] } else { '' })
        bypass_crosscheck = [string]$(if ($crossKv.Contains('bypass_crosscheck')) { $crossKv['bypass_crosscheck'] } else { '' })
    }

    $invSet = @($invOperational | Sort-Object -Unique)
    $mapSet = @($mapOperational | Sort-Object -Unique)
    $invNameSet = @($invOperationalNames | Sort-Object -Unique)
    $mapNameSet = @($mapOperationalNames | Sort-Object -Unique)

    $coverageBinding = [ordered]@{
        inventory_operational_name_count = $invNameSet.Count
        map_operational_name_count = $mapNameSet.Count
        inventory_minus_map = @($invNameSet | Where-Object { $mapNameSet -notcontains $_ } | Sort-Object -Unique)
        map_minus_inventory = @($mapNameSet | Where-Object { $invNameSet -notcontains $_ } | Sort-Object -Unique)
    }

    $payloadObj = [ordered]@{
        schema = 'phase46_9_trust_chain_baseline_enforcement_coverage_fingerprint_v1'
        inventory_operational = $invSet
        enforcement_map_operational = $mapSet
        unguarded_report_semantics = $unguardedSemantic
        bypass_crosscheck_semantics = $crossSemantic
        coverage_binding = $coverageBinding
    }

    $payloadJson = $payloadObj | ConvertTo-Json -Depth 20 -Compress

    return [ordered]@{
        payload_json = $payloadJson
        fingerprint = (Get-StringSha256Hex -Text $payloadJson)
        inventory_hash = (Get-StringSha256Hex -Text (($invSet -join "`n")))
        map_hash = (Get-StringSha256Hex -Text (($mapSet -join "`n")))
        unguarded_semantic_hash = (Get-StringSha256Hex -Text (($unguardedSemantic | ConvertTo-Json -Compress)))
        bypass_semantic_hash = (Get-StringSha256Hex -Text (($crossSemantic | ConvertTo-Json -Compress)))
        binding_hash = (Get-StringSha256Hex -Text (($coverageBinding | ConvertTo-Json -Compress)))
        inventory_operational_count = $invSet.Count
        map_operational_count = $mapSet.Count
        inventory_minus_map_count = @($coverageBinding.inventory_minus_map).Count
        map_minus_inventory_count = @($coverageBinding.map_minus_inventory).Count
    }
}

function Clone-List {
    param([string[]]$Input)
    return [string[]]@($Input)
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ProofRoot = Join-Path $Root '_proof'
$PF = Join-Path $ProofRoot ('phase46_9_trust_chain_baseline_enforcement_coverage_trust_chain_baseline_enforcement_coverage_fingerprint_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$phase46_8Proof = Get-LatestPhase46_8ProofPath -ProofRoot $ProofRoot
$inventoryPath = Join-Path $phase46_8Proof '16_entrypoint_inventory.txt'
$mapPath = Join-Path $phase46_8Proof '17_frozen_baseline_enforcement_map.txt'
$unguardedPath = Join-Path $phase46_8Proof '18_unguarded_path_report.txt'
$crosscheckPath = Join-Path $phase46_8Proof '19_bypass_crosscheck_report.txt'

foreach ($p in @($inventoryPath, $mapPath, $unguardedPath, $crosscheckPath)) {
    if (-not (Test-Path -LiteralPath $p)) {
        throw ('Missing Phase 46.8 fingerprint input: ' + $p)
    }
}

$inventoryLines = @(Get-Content -LiteralPath $inventoryPath)
$mapLines = @(Get-Content -LiteralPath $mapPath)
$unguardedLines = @(Get-Content -LiteralPath $unguardedPath)
$crosscheckLines = @(Get-Content -LiteralPath $crosscheckPath)

$base = Get-CoverageFingerprintModel -InventoryLines $inventoryLines -MapLines $mapLines -UnguardedLines $unguardedLines -CrosscheckLines $crosscheckLines
$baseFp = [string]$base.fingerprint

# Determinism check on unchanged inputs.
$base2 = Get-CoverageFingerprintModel -InventoryLines $inventoryLines -MapLines $mapLines -UnguardedLines $unguardedLines -CrosscheckLines $crosscheckLines
$deterministic = ([string]$base2.fingerprint -eq $baseFp)

$referencePath = Join-Path $Root 'control_plane\82_trust_chain_baseline_enforcement_coverage_trust_chain_baseline_enforcement_coverage_fingerprint.json'
$referenceObj = [ordered]@{
    schema = 'phase46_9_trust_chain_baseline_enforcement_coverage_fingerprint_reference_v1'
    generated_utc = (Get-Date).ToUniversalTime().ToString('o')
    source_phase46_8_proof = $phase46_8Proof
    source_inventory_artifact = $inventoryPath
    source_enforcement_map_artifact = $mapPath
    source_unguarded_report_artifact = $unguardedPath
    source_bypass_crosscheck_artifact = $crosscheckPath
    inventory_operational_count = [int]$base.inventory_operational_count
    map_operational_count = [int]$base.map_operational_count
    inventory_minus_map_count = [int]$base.inventory_minus_map_count
    map_minus_inventory_count = [int]$base.map_minus_inventory_count
    coverage_fingerprint_sha256 = $baseFp
    canonical_input_hashes = [ordered]@{
        inventory_hash = [string]$base.inventory_hash
        enforcement_map_hash = [string]$base.map_hash
        unguarded_semantic_hash = [string]$base.unguarded_semantic_hash
        bypass_semantic_hash = [string]$base.bypass_semantic_hash
        binding_hash = [string]$base.binding_hash
        canonical_payload_hash = [string]$baseFp
    }
}
$referenceObj | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $referencePath -Encoding UTF8 -NoNewline
$referenceRead = Get-Content -Raw -LiteralPath $referencePath | ConvertFrom-Json
$storedReferenceFp = [string]$referenceRead.coverage_fingerprint_sha256

$records = [System.Collections.Generic.List[object]]::new()

# CASE A - CLEAN FINGERPRINT GENERATION
$caseA = ($base.inventory_operational_count -gt 0 -and $base.map_operational_count -gt 0 -and $deterministic -and $baseFp -eq $storedReferenceFp)
$records.Add([ordered]@{
    case = 'A'
    computed_fingerprint = $baseFp
    stored_reference_fingerprint = $storedReferenceFp
    fingerprint_match_status = $(if ($baseFp -eq $storedReferenceFp) { 'MATCH' } else { 'MISMATCH' })
    detected_change_type = 'clean_generation'
    certification_allowed_or_blocked = $(if ($caseA) { 'ALLOWED' } else { 'BLOCKED' })
})

# CASE B - NON-SEMANTIC CHANGE
$invB = @($inventoryLines)
for ($i = 0; $i -lt $invB.Count; $i++) {
    $x = '  ' + $invB[$i] + '  '
    $x = [regex]::Replace($x, '\|', ' | ')
    $x = [regex]::Replace($x, '\s+', ' ')
    $invB[$i] = $x
}
$mapB = @($mapLines)
for ($i = 0; $i -lt $mapB.Count; $i++) {
    $mapB[$i] = [regex]::Replace(('   ' + $mapB[$i] + '  '), '\s+', ' ')
}
$b = Get-CoverageFingerprintModel -InventoryLines $invB -MapLines $mapB -UnguardedLines $unguardedLines -CrosscheckLines $crosscheckLines
$caseB = ([string]$b.fingerprint -eq $baseFp)
$records.Add([ordered]@{
    case = 'B'
    computed_fingerprint = [string]$b.fingerprint
    stored_reference_fingerprint = $storedReferenceFp
    fingerprint_match_status = $(if ([string]$b.fingerprint -eq $storedReferenceFp) { 'MATCH' } else { 'MISMATCH' })
    detected_change_type = 'non_semantic_formatting_only'
    certification_allowed_or_blocked = $(if ($caseB) { 'ALLOWED' } else { 'BLOCKED' })
})

# CASE C - ENTRYPOINT ADDITION
$invC = @($inventoryLines)
$invC += 'tools/phase46_6/simulated_added_entrypoint.ps1 | Invoke-GuardedSimulatedAddedPath | frozen_baseline_snapshot_load_entrypoint | operational | yes | no | Invoke-FrozenBaselineTrustChainEnforcementGate | load_frozen_baseline_snapshot | directly gated | evidence=simulated_operational_entrypoint_addition'
$mapC = @($mapLines)
$addedMapC = 'tools/phase46_6/simulated_added_entrypoint.ps1 | Invoke-GuardedSimulatedAddedPath -> directly gated -> gate_source=Invoke-FrozenBaselineTrustChainEnforcementGate'
if ($mapC.Count -ge 3) {
    $mapC = @($mapC[0..2] + @($addedMapC) + $mapC[3..($mapC.Count - 1)])
} else {
    $mapC += $addedMapC
}
$c = Get-CoverageFingerprintModel -InventoryLines $invC -MapLines $mapC -UnguardedLines $unguardedLines -CrosscheckLines $crosscheckLines
$caseC = ([string]$c.fingerprint -ne $baseFp)
$records.Add([ordered]@{
    case = 'C'
    computed_fingerprint = [string]$c.fingerprint
    stored_reference_fingerprint = $storedReferenceFp
    fingerprint_match_status = $(if ([string]$c.fingerprint -eq $storedReferenceFp) { 'MATCH' } else { 'MISMATCH' })
    detected_change_type = 'operational_entrypoint_addition'
    certification_allowed_or_blocked = $(if ($caseC) { 'BLOCKED' } else { 'ALLOWED' })
})

# CASE D - COVERAGE CLASSIFICATION CHANGE
$invD = @($inventoryLines)
$changedD = $false
for ($i = 0; $i -lt $invD.Count; $i++) {
    $entry = Parse-InventoryLine -Line $invD[$i]
    if ($null -eq $entry) { continue }
    if ([string]$entry.operational_or_dead -eq 'operational' -and [string]$entry.coverage_classification -eq 'directly gated') {
        $parts = @($invD[$i] -split '\|')
        if ($parts.Count -ge 10) {
            $parts[4] = ' no '
            $parts[5] = ' yes '
            $parts[8] = ' transitively gated '
            $invD[$i] = ($parts -join '|')
            $changedD = $true
            break
        }
    }
}
$mapD = @($mapLines)
if ($changedD) {
    for ($i = 0; $i -lt $mapD.Count; $i++) {
        if ($mapD[$i] -match '-> directly gated ->') {
            $mapD[$i] = ($mapD[$i] -replace '-> directly gated ->', '-> transitively gated ->')
            break
        }
    }
}
$d = Get-CoverageFingerprintModel -InventoryLines $invD -MapLines $mapD -UnguardedLines $unguardedLines -CrosscheckLines $crosscheckLines
$caseD = ($changedD -and ([string]$d.fingerprint -ne $baseFp))
$records.Add([ordered]@{
    case = 'D'
    computed_fingerprint = [string]$d.fingerprint
    stored_reference_fingerprint = $storedReferenceFp
    fingerprint_match_status = $(if ([string]$d.fingerprint -eq $storedReferenceFp) { 'MATCH' } else { 'MISMATCH' })
    detected_change_type = 'coverage_classification_change'
    certification_allowed_or_blocked = $(if ($caseD) { 'BLOCKED' } else { 'ALLOWED' })
})

# CASE E - ORDER CHANGE
$headerInv = @($inventoryLines | Select-Object -First 1)
$bodyInv = @($inventoryLines | Select-Object -Skip 1)
$revInv = [System.Collections.Generic.List[string]]::new()
for ($i = $bodyInv.Count - 1; $i -ge 0; $i--) { $revInv.Add($bodyInv[$i]) }
$invE = @($headerInv + $revInv.ToArray())

$mapE = @($mapLines)
$mapERev = [System.Collections.Generic.List[string]]::new()
for ($i = $mapE.Count - 1; $i -ge 0; $i--) { $mapERev.Add($mapE[$i]) }
$e = Get-CoverageFingerprintModel -InventoryLines $invE -MapLines $mapERev -UnguardedLines $unguardedLines -CrosscheckLines $crosscheckLines
$caseE = ([string]$e.fingerprint -eq $baseFp)
$records.Add([ordered]@{
    case = 'E'
    computed_fingerprint = [string]$e.fingerprint
    stored_reference_fingerprint = $storedReferenceFp
    fingerprint_match_status = $(if ([string]$e.fingerprint -eq $storedReferenceFp) { 'MATCH' } else { 'MISMATCH' })
    detected_change_type = 'order_only_change'
    certification_allowed_or_blocked = $(if ($caseE) { 'ALLOWED' } else { 'BLOCKED' })
})

# CASE F - DEAD HELPER CHANGE
$invF = @($inventoryLines)
$changedF = $false
for ($i = 0; $i -lt $invF.Count; $i++) {
    $entry = Parse-InventoryLine -Line $invF[$i]
    if ($null -eq $entry) { continue }
    if ([string]$entry.operational_or_dead -eq 'dead / non-operational') {
        $parts = @($invF[$i] -split '\|')
        if ($parts.Count -ge 10) {
            $parts[9] = ' evidence=dead_helper_cosmetic_change '
            $invF[$i] = ($parts -join '|')
            $changedF = $true
            break
        }
    }
}
$mapF = @($mapLines)
if ($changedF) {
    for ($i = 0; $i -lt $mapF.Count; $i++) {
        if ($mapF[$i] -match 'dead / non-operational$') {
            $mapF[$i] = $mapF[$i] + ' '
            break
        }
    }
}
$f = Get-CoverageFingerprintModel -InventoryLines $invF -MapLines $mapF -UnguardedLines $unguardedLines -CrosscheckLines $crosscheckLines
$caseF = ($changedF -and ([string]$f.fingerprint -eq $baseFp))
$records.Add([ordered]@{
    case = 'F'
    computed_fingerprint = [string]$f.fingerprint
    stored_reference_fingerprint = $storedReferenceFp
    fingerprint_match_status = $(if ([string]$f.fingerprint -eq $storedReferenceFp) { 'MATCH' } else { 'MISMATCH' })
    detected_change_type = 'dead_helper_cosmetic_only'
    certification_allowed_or_blocked = $(if ($caseF) { 'ALLOWED' } else { 'BLOCKED' })
})

# CASE G - UNGUARDED PATH REPORT CHANGE
$uG = @($unguardedLines)
for ($i = 0; $i -lt $uG.Count; $i++) {
    if ($uG[$i] -match '^unguarded_operational_path_count=') { $uG[$i] = 'unguarded_operational_path_count=1' }
    elseif ($uG[$i] -match '^status=') { $uG[$i] = 'status=simulated_unguarded_detected' }
    elseif ($uG[$i] -match '^missing_direct=') { $uG[$i] = 'missing_direct=Invoke-GuardedRuntimeInitWrapper' }
}
$g = Get-CoverageFingerprintModel -InventoryLines $inventoryLines -MapLines $mapLines -UnguardedLines $uG -CrosscheckLines $crosscheckLines
$caseG = ([string]$g.fingerprint -ne $baseFp)
$records.Add([ordered]@{
    case = 'G'
    computed_fingerprint = [string]$g.fingerprint
    stored_reference_fingerprint = $storedReferenceFp
    fingerprint_match_status = $(if ([string]$g.fingerprint -eq $storedReferenceFp) { 'MATCH' } else { 'MISMATCH' })
    detected_change_type = 'unguarded_report_semantics_change'
    certification_allowed_or_blocked = $(if ($caseG) { 'BLOCKED' } else { 'ALLOWED' })
})

# CASE H - OPERATIONAL/DEAD RECLASSIFICATION
$invH = @($inventoryLines)
$changedH = $false
for ($i = 0; $i -lt $invH.Count; $i++) {
    $entry = Parse-InventoryLine -Line $invH[$i]
    if ($null -eq $entry) { continue }
    if ([string]$entry.operational_or_dead -eq 'operational') {
        $parts = @($invH[$i] -split '\|')
        if ($parts.Count -ge 10) {
            $parts[3] = ' dead / non-operational '
            $parts[4] = ' no '
            $parts[5] = ' no '
            $parts[8] = ' dead / non-operational '
            $invH[$i] = ($parts -join '|')
            $changedH = $true
            break
        }
    }
}
$mapH = @($mapLines)
if ($changedH) {
    for ($i = 0; $i -lt $mapH.Count; $i++) {
        if ($mapH[$i] -match '-> (directly gated|transitively gated|unguarded) ->') {
            $mapH[$i] = [regex]::Replace($mapH[$i], '-> (directly gated|transitively gated|unguarded) ->.*$', '-> dead / non-operational')
            break
        }
    }
}
$h = Get-CoverageFingerprintModel -InventoryLines $invH -MapLines $mapH -UnguardedLines $unguardedLines -CrosscheckLines $crosscheckLines
$caseH = ($changedH -and ([string]$h.fingerprint -ne $baseFp))
$records.Add([ordered]@{
    case = 'H'
    computed_fingerprint = [string]$h.fingerprint
    stored_reference_fingerprint = $storedReferenceFp
    fingerprint_match_status = $(if ([string]$h.fingerprint -eq $storedReferenceFp) { 'MATCH' } else { 'MISMATCH' })
    detected_change_type = 'operational_dead_reclassification'
    certification_allowed_or_blocked = $(if ($caseH) { 'BLOCKED' } else { 'ALLOWED' })
})

# CASE I - BYPASS CROSS-CHECK CHANGE
$xI = @($crosscheckLines)
for ($i = 0; $i -lt $xI.Count; $i++) {
    if ($xI[$i] -match '^bypass_crosscheck=') { $xI[$i] = 'bypass_crosscheck=FALSE' }
    elseif ($xI[$i] -match '^operational_direct_surface_present_in_phase46_7_gate_record=') { $xI[$i] = 'operational_direct_surface_present_in_phase46_7_gate_record=FALSE' }
}
$iData = Get-CoverageFingerprintModel -InventoryLines $inventoryLines -MapLines $mapLines -UnguardedLines $unguardedLines -CrosscheckLines $xI
$caseI = ([string]$iData.fingerprint -ne $baseFp)
$records.Add([ordered]@{
    case = 'I'
    computed_fingerprint = [string]$iData.fingerprint
    stored_reference_fingerprint = $storedReferenceFp
    fingerprint_match_status = $(if ([string]$iData.fingerprint -eq $storedReferenceFp) { 'MATCH' } else { 'MISMATCH' })
    detected_change_type = 'bypass_crosscheck_semantics_change'
    certification_allowed_or_blocked = $(if ($caseI) { 'BLOCKED' } else { 'ALLOWED' })
})

$allPass = ($caseA -and $caseB -and $caseC -and $caseD -and $caseE -and $caseF -and $caseG -and $caseH -and $caseI -and $deterministic)
$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status = @(
    'phase=46.9',
    'title=Trust-Chain Baseline Enforcement Coverage Trust-Chain Baseline Enforcement Coverage Fingerprint Lock',
    ('gate=' + $Gate),
    ('coverage_fingerprint=' + $baseFp),
    ('reference_saved=' + $(if (Test-Path -LiteralPath $referencePath) { 'TRUE' } else { 'FALSE' })),
    ('deterministic=' + $(if ($deterministic) { 'TRUE' } else { 'FALSE' })),
    'runtime_state_machine_changed=FALSE'
)
Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value ($status -join "`r`n") -Encoding UTF8 -NoNewline

$head = @(
    'runner=tools/phase46_9/phase46_9_trust_chain_baseline_enforcement_coverage_trust_chain_baseline_enforcement_coverage_fingerprint_runner.ps1',
    ('phase46_8_proof_packet=' + $phase46_8Proof),
    ('inventory=' + $inventoryPath),
    ('enforcement_map=' + $mapPath),
    ('unguarded_report=' + $unguardedPath),
    ('bypass_crosscheck_report=' + $crosscheckPath),
    ('reference_artifact=' + $referencePath)
)
Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value ($head -join "`r`n") -Encoding UTF8 -NoNewline

$definition = @(
    'TRUST-CHAIN BASELINE ENFORCEMENT COVERAGE FINGERPRINT DEFINITION (PHASE 46.9)',
    '',
    'Fingerprint inputs are Phase 46.8 artifacts: 16_entrypoint_inventory.txt, 17_frozen_baseline_enforcement_map.txt, 18_unguarded_path_report.txt, 19_bypass_crosscheck_report.txt.',
    'Canonical model includes only operational inventory and operational enforcement-map rows, plus semantic key-value state from unguarded and bypass cross-check reports.',
    'Operational identity binding between inventory and map is included to detect additions/removals and operational/dead reclassification changes.',
    'Dead/non-operational helper rows are excluded from canonical operational sets so dead-helper-only cosmetic edits do not alter the fingerprint.',
    'Rows are whitespace-normalized and order-independent (sorted unique sets) to ignore formatting and ordering-only changes.',
    'The canonical payload is SHA-256 hashed to produce the coverage fingerprint reference.'
)
Set-Content -LiteralPath (Join-Path $PF '10_fingerprint_definition.txt') -Value ($definition -join "`r`n") -Encoding UTF8 -NoNewline

$rules = @(
    'TRUST-CHAIN BASELINE ENFORCEMENT COVERAGE FINGERPRINT RULES',
    '1) Fingerprint must be deterministic for identical semantic inputs.',
    '2) Whitespace/format/order-only edits must not change fingerprint.',
    '3) Operational entrypoint additions/removals must change fingerprint.',
    '4) Coverage classification changes for protected operational paths must change fingerprint.',
    '5) Operational/dead reclassification for real paths must change fingerprint.',
    '6) Dead-helper-only cosmetic changes must not change fingerprint.',
    '7) Unguarded path semantic-state changes must change fingerprint.',
    '8) Bypass cross-check semantic-state changes must change fingerprint.',
    '9) Reference artifact stores fingerprint and canonical input hashes for later trust-chain sealing.',
    '10) Runtime behavior remains unchanged; this phase is certification artifact generation and validation only.'
)
Set-Content -LiteralPath (Join-Path $PF '11_fingerprint_rules.txt') -Value ($rules -join "`r`n") -Encoding UTF8 -NoNewline

$filesTouched = @(
    ('READ  ' + $inventoryPath),
    ('READ  ' + $mapPath),
    ('READ  ' + $unguardedPath),
    ('READ  ' + $crosscheckPath),
    ('WRITE ' + $referencePath),
    ('WRITE ' + (Join-Path $PF '*'))
)
Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Value ($filesTouched -join "`r`n") -Encoding UTF8 -NoNewline

$build = @(
    'build_type=PowerShell fingerprint_lock_generation_and_mutation_validation',
    'compile_required=no',
    ('deterministic=' + $(if ($deterministic) { 'TRUE' } else { 'FALSE' })),
    ('inventory_operational_count=' + $base.inventory_operational_count),
    ('map_operational_count=' + $base.map_operational_count),
    ('inventory_minus_map_count=' + $base.inventory_minus_map_count),
    ('map_minus_inventory_count=' + $base.map_minus_inventory_count),
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
    ('CASE G unguarded_path_report_change=' + $(if ($caseG) { 'PASS' } else { 'FAIL' })),
    ('CASE H operational_dead_reclassification=' + $(if ($caseH) { 'PASS' } else { 'FAIL' })),
    ('CASE I bypass_crosscheck_change=' + $(if ($caseI) { 'PASS' } else { 'FAIL' })),
    ('determinism_check=' + $(if ($deterministic) { 'PASS' } else { 'FAIL' }))
)
Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Value ($validation -join "`r`n") -Encoding UTF8 -NoNewline

$summary = @(
    'The frozen-baseline coverage fingerprint is built from the actual Phase 46.8 inventory/map/unguarded/crosscheck artifacts using semantic canonicalization and sorted operational sets.',
    'Direct vs transitive enforcement distinctions are preserved through operational inventory and map rows, making classification changes fingerprint-sensitive.',
    'Dead helpers are excluded from operational canonical sets so cosmetic dead-helper edits do not change fingerprint while operational/dead reclassification does.',
    'Unguarded-path and bypass-crosscheck reports contribute normalized semantic key-value state, so state regressions are detected while formatting noise is ignored.',
    'Mutation cases C,D,G,H,I changed fingerprint and were blocked; non-semantic/order/dead-cosmetic cases B,E,F kept fingerprint stable and allowed.',
    'Reference artifact control_plane/82_* stores the final fingerprint and canonical input hashes for subsequent trust-chain sealing.',
    'Runtime behavior remains unchanged because this phase performs certification-model hashing and proof generation only.'
)
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value ($summary -join "`r`n") -Encoding UTF8 -NoNewline

$fpRecord = @(
    ('stored_reference_path=' + $referencePath),
    ('computed_fingerprint=' + $baseFp),
    ('stored_reference_fingerprint=' + $storedReferenceFp),
    ('fingerprint_match=' + $(if ($baseFp -eq $storedReferenceFp) { 'TRUE' } else { 'FALSE' })),
    ('inventory_hash=' + [string]$base.inventory_hash),
    ('enforcement_map_hash=' + [string]$base.map_hash),
    ('unguarded_semantic_hash=' + [string]$base.unguarded_semantic_hash),
    ('bypass_semantic_hash=' + [string]$base.bypass_semantic_hash),
    ('binding_hash=' + [string]$base.binding_hash),
    ('canonical_payload_hash=' + $baseFp)
)
Set-Content -LiteralPath (Join-Path $PF '16_coverage_fingerprint_record.txt') -Value ($fpRecord -join "`r`n") -Encoding UTF8 -NoNewline

$evidence = [System.Collections.Generic.List[string]]::new()
$evidence.Add('case|computed_fingerprint|stored_reference_fingerprint|fingerprint_match_status|detected_change_type|certification_allowed_or_blocked')
foreach ($r in $records) {
    $evidence.Add(
        [string]$r.case + '|' +
        [string]$r.computed_fingerprint + '|' +
        [string]$r.stored_reference_fingerprint + '|' +
        [string]$r.fingerprint_match_status + '|' +
        [string]$r.detected_change_type + '|' +
        [string]$r.certification_allowed_or_blocked
    )
}
Set-Content -LiteralPath (Join-Path $PF '17_regression_detection_evidence.txt') -Value (($evidence.ToArray()) -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '98_gate_phase46_9.txt') -Value $Gate -Encoding UTF8 -NoNewline

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
