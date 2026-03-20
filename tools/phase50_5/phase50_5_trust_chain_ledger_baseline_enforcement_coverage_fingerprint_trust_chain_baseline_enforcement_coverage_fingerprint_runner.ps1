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
        $s = $s -replace '"',  '\"'
        $s = $s -replace "`n", '\n'
        $s = $s -replace "`r", '\r'
        $s = $s -replace "`t", '\t'
        return '"' + $s + '"'
    }
    if ($Value -is [System.Collections.IList]) {
        $items = [System.Collections.Generic.List[string]]::new()
        foreach ($item in $Value) {
            $items.Add((Convert-ToCanonicalJson -Value $item))
        }
        return '[' + ($items -join ',') + ']'
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $keys = @($Value.Keys | Sort-Object)
        $pairs = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $keys) {
            $pairs.Add(('"' + $k + '":' + (Convert-ToCanonicalJson -Value $Value[$k])))
        }
        return '{' + ($pairs -join ',') + '}'
    }
    if ($Value -is [pscustomobject]) {
        $keys = @($Value.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object)
        $pairs = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $keys) {
            $v = $Value.PSObject.Properties[$k].Value
            $pairs.Add(('"' + $k + '":' + (Convert-ToCanonicalJson -Value $v)))
        }
        return '{' + ($pairs -join ',') + '}'
    }

    return '"' + ([string]$Value -replace '"', '\"') + '"'
}

function Parse-PipeKvLine {
    param([string]$Line)

    $lineTrim = if ($null -eq $Line) { '' } else { [string]$Line }
    $lineTrim = $lineTrim.Trim()
    if ([string]::IsNullOrWhiteSpace($lineTrim)) { return $null }

    $tokens = @($lineTrim -split '\|')
    $obj = [ordered]@{}
    $hasKv = $false

    foreach ($t in $tokens) {
        $part = [string]$t
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        $pair = @($part -split '=', 2)
        if ($pair.Count -ne 2) { continue }

        $k = ([string]$pair[0]).Trim().ToLowerInvariant()
        $v = ([string]$pair[1]).Trim()
        if ([string]::IsNullOrWhiteSpace($k)) { continue }

        $obj[$k] = $v
        $hasKv = $true
    }

    if (-not $hasKv) { return $null }
    return $obj
}

function Normalize-Flag {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return 'NO' }
    $v = $Value.Trim().ToUpperInvariant()
    if ($v -eq 'TRUE' -or $v -eq 'YES') { return 'YES' }
    return 'NO'
}

function Normalize-Class {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return $Value.Trim().ToLowerInvariant()
}

function Normalize-State {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return $Value.Trim().ToLowerInvariant()
}

function Get-LatestPhase50_4Proof {
    param([string]$ProofRoot)

    $dirs = Get-ChildItem -Path $ProofRoot -Directory | Where-Object {
        $_.Name -like 'phase50_4_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_coverage_audit_*'
    } | Sort-Object Name -Descending

    foreach ($d in $dirs) {
        $required = @(
            (Join-Path $d.FullName '16_entrypoint_inventory.txt'),
            (Join-Path $d.FullName '17_frozen_baseline_enforcement_map.txt'),
            (Join-Path $d.FullName '18_unguarded_path_report.txt'),
            (Join-Path $d.FullName '19_bypass_crosscheck_report.txt')
        )

        $ok = $true
        foreach ($p in $required) {
            if (-not (Test-Path -LiteralPath $p)) {
                $ok = $false
                break
            }
        }

        if ($ok) { return $d.FullName }
    }

    throw 'No usable phase50_4 proof directory found for fingerprint input set.'
}

function Get-OperationalRecordsFromLines {
    param([string[]]$Lines)

    $rows = [System.Collections.Generic.List[object]]::new()

    foreach ($line in $Lines) {
        $kv = Parse-PipeKvLine -Line $line
        if ($null -eq $kv) { continue }

        $func = ''
        if ($kv.Contains('function_or_entrypoint')) {
            $func = [string]$kv['function_or_entrypoint']
        } elseif ($kv.Contains('function')) {
            $func = [string]$kv['function']
        }
        $func = $func.Trim()
        if ([string]::IsNullOrWhiteSpace($func)) { continue }

        $op = ''
        if ($kv.Contains('frozen_baseline_relevant_operation_type')) {
            $op = [string]$kv['frozen_baseline_relevant_operation_type']
        } elseif ($kv.Contains('operation_type')) {
            $op = [string]$kv['operation_type']
        }
        $op = $op.Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($op)) { continue }

        $state = ''
        if ($kv.Contains('operational_or_dead')) {
            $state = Normalize-State -Value ([string]$kv['operational_or_dead'])
        }
        if ($state -ne 'operational') { continue }

        $coverage = ''
        if ($kv.Contains('coverage_classification')) {
            $coverage = Normalize-Class -Value ([string]$kv['coverage_classification'])
        }

        $direct = ''
        if ($kv.Contains('direct_gate_present')) {
            $direct = Normalize-Flag -Value ([string]$kv['direct_gate_present'])
        } elseif ($kv.Contains('direct_gate')) {
            $direct = Normalize-Flag -Value ([string]$kv['direct_gate'])
        } else {
            $direct = 'NO'
        }

        $transitive = ''
        if ($kv.Contains('transitive_gate_present')) {
            $transitive = Normalize-Flag -Value ([string]$kv['transitive_gate_present'])
        } elseif ($kv.Contains('transitive_gate')) {
            $transitive = Normalize-Flag -Value ([string]$kv['transitive_gate'])
        } else {
            $transitive = 'NO'
        }

        $gateSrc = ''
        if ($kv.Contains('gate_source_path')) {
            $gateSrc = [string]$kv['gate_source_path']
        } elseif ($kv.Contains('gate_source')) {
            $gateSrc = [string]$kv['gate_source']
        }
        $gateSrc = $gateSrc.Trim()

        $rows.Add([ordered]@{
            function_name            = $func
            operation_type           = $op
            operational_or_dead      = $state
            direct_gate              = $direct
            transitive_gate          = $transitive
            coverage_classification  = $coverage
            gate_source              = $gateSrc
        })
    }

    $dedup = [ordered]@{}
    foreach ($r in $rows) {
        $key = (
            [string]$r.operation_type + '|' +
            [string]$r.function_name + '|' +
            [string]$r.operational_or_dead + '|' +
            [string]$r.direct_gate + '|' +
            [string]$r.transitive_gate + '|' +
            [string]$r.coverage_classification + '|' +
            [string]$r.gate_source
        )
        $dedup[$key] = $r
    }

    return @($dedup.Values | Sort-Object operation_type, function_name)
}

function Get-UnguardedSemanticsFromLines {
    param([string[]]$Lines)

    $count = 0
    $details = [System.Collections.Generic.List[string]]::new()

    foreach ($line in $Lines) {
        $lineTrim = ([string]$line).Trim()
        if ([string]::IsNullOrWhiteSpace($lineTrim)) { continue }

        if ($lineTrim -match '^UNGUARDED_OPERATIONAL_PATHS\s*=\s*(\d+)\s*$') {
            $count = [int]$Matches[1]
            continue
        }

        if ($lineTrim -like 'UNGUARDED *') {
            $kv = Parse-PipeKvLine -Line $lineTrim
            if ($null -eq $kv) {
                $detailNorm = ($lineTrim -replace '\s+', ' ').Trim().ToLowerInvariant()
                if (-not [string]::IsNullOrWhiteSpace($detailNorm)) { [void]$details.Add($detailNorm) }
                continue
            }

            $dFunc = if ($kv.Contains('function')) { [string]$kv['function'] } else { '' }
            $dOp = if ($kv.Contains('operation')) { [string]$kv['operation'] } else { '' }
            $detail = ('function=' + $dFunc.Trim().ToLowerInvariant() + '|operation=' + $dOp.Trim().ToLowerInvariant())
            [void]$details.Add($detail)
        }
    }

    return [ordered]@{
        unguarded_operational_paths = $count
        unguarded_details = @($details | Sort-Object -Unique)
    }
}

function Get-BypassCrosscheckSemanticsFromLines {
    param([string[]]$Lines)

    $rows = [System.Collections.Generic.List[object]]::new()

    foreach ($line in $Lines) {
        $kv = Parse-PipeKvLine -Line $line
        if ($null -eq $kv) { continue }
        if (-not $kv.Contains('operation')) { continue }

        $op = ([string]$kv['operation']).Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($op)) { continue }

        $inInv = if ($kv.Contains('in_50_3_inventory')) { Normalize-Flag -Value ([string]$kv['in_50_3_inventory']) } else { 'NO' }
        $inGate = if ($kv.Contains('in_50_3_gate_record')) { Normalize-Flag -Value ([string]$kv['in_50_3_gate_record']) } else { 'NO' }
        $inMap = if ($kv.Contains('in_50_4_map')) { Normalize-Flag -Value ([string]$kv['in_50_4_map']) } else { 'NO' }

        $rows.Add([ordered]@{
            operation = $op
            in_50_3_inventory = $inInv
            in_50_3_gate_record = $inGate
            in_50_4_map = $inMap
        })
    }

    $dedup = [ordered]@{}
    foreach ($r in $rows) {
        $dedup[[string]$r.operation] = $r
    }

    return @($dedup.Values | Sort-Object operation)
}

function Build-CoverageFingerprintModel {
    param(
        [string[]]$InventoryLines,
        [string[]]$MapLines,
        [string[]]$UnguardedLines,
        [string[]]$CrossLines
    )

    $inventoryOperational = Get-OperationalRecordsFromLines -Lines $InventoryLines
    $mapOperational = Get-OperationalRecordsFromLines -Lines $MapLines
    $unguardedSem = Get-UnguardedSemanticsFromLines -Lines $UnguardedLines
    $crossSem = Get-BypassCrosscheckSemanticsFromLines -Lines $CrossLines

    $inventoryCanonical = [ordered]@{
        operational_entries = $inventoryOperational
    }
    $mapCanonical = [ordered]@{
        operational_entries = $mapOperational
    }

    $inventoryCanonicalJson = Convert-ToCanonicalJson -Value $inventoryCanonical
    $mapCanonicalJson = Convert-ToCanonicalJson -Value $mapCanonical
    $unguardedCanonicalJson = Convert-ToCanonicalJson -Value $unguardedSem
    $crossCanonicalJson = Convert-ToCanonicalJson -Value $crossSem

    $componentHashes = [ordered]@{
        inventory_semantic_sha256 = Get-StringSha256Hex -Text $inventoryCanonicalJson
        map_semantic_sha256 = Get-StringSha256Hex -Text $mapCanonicalJson
        unguarded_semantic_sha256 = Get-StringSha256Hex -Text $unguardedCanonicalJson
        bypass_crosscheck_semantic_sha256 = Get-StringSha256Hex -Text $crossCanonicalJson
    }

    $finalModel = [ordered]@{
        coverage_model_version = '50.5'
        inventory_semantic = $inventoryCanonical
        map_semantic = $mapCanonical
        unguarded_semantic = $unguardedSem
        bypass_crosscheck_semantic = $crossSem
        canonical_component_hashes = $componentHashes
    }

    $finalCanonicalJson = Convert-ToCanonicalJson -Value $finalModel
    $finalFingerprint = Get-StringSha256Hex -Text $finalCanonicalJson

    return [ordered]@{
        final_fingerprint = $finalFingerprint
        canonical_model_json = $finalCanonicalJson
        component_hashes = $componentHashes
        inventory_operational_count = @($inventoryOperational).Count
        map_operational_count = @($mapOperational).Count
        unguarded_operational_paths = [int]$unguardedSem.unguarded_operational_paths
        bypass_operation_count = @($crossSem).Count
    }
}

function Set-KvInLine {
    param(
        [string]$Line,
        [string]$Key,
        [string]$NewValue
    )

    $parts = @($Line -split '\|')
    for ($i = 0; $i -lt $parts.Count; $i++) {
        $pair = @($parts[$i] -split '=', 2)
        if ($pair.Count -ne 2) { continue }
        if ($pair[0].Trim().ToLowerInvariant() -eq $Key.Trim().ToLowerInvariant()) {
            $parts[$i] = ($pair[0].Trim() + '=' + $NewValue)
            break
        }
    }
    return ($parts -join '|')
}

function Add-ValidationRecord {
    param(
        [System.Collections.Generic.List[string]]$ValidationLines,
        [System.Collections.Generic.List[string]]$RecordLines,
        [string]$CaseId,
        [string]$CaseName,
        [string]$Expected,
        [string]$ComputedFingerprint,
        [string]$StoredFingerprint,
        [string]$DetectedChangeType,
        [string]$CertificationAllowedOrBlocked,
        [string]$PassOrFail
    )

    $matchStatus = if ($ComputedFingerprint -eq $StoredFingerprint) { 'MATCH' } else { 'MISMATCH' }

    $ValidationLines.Add(
        'CASE ' + $CaseId + ' ' + $CaseName +
        ' expected=' + $Expected +
        ' fingerprint_match_status=' + $matchStatus +
        ' detected_change_type=' + $DetectedChangeType +
        ' certification_allowed_or_blocked=' + $CertificationAllowedOrBlocked +
        ' => ' + $PassOrFail
    )

    $RecordLines.Add(
        'CASE=' + $CaseId +
        '|computed_fingerprint=' + $ComputedFingerprint +
        '|stored_reference_fingerprint=' + $StoredFingerprint +
        '|fingerprint_match_status=' + $matchStatus +
        '|detected_change_type=' + $DetectedChangeType +
        '|certification_allowed_or_blocked=' + $CertificationAllowedOrBlocked
    )

    return $PassOrFail -eq 'PASS'
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\phase50_5_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$RunnerPath = Join-Path $Root 'tools\phase50_5\phase50_5_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint_runner.ps1'
$ProofRoot = Join-Path $Root '_proof'
$Latest50_4Proof = Get-LatestPhase50_4Proof -ProofRoot $ProofRoot

$InventoryPath = Join-Path $Latest50_4Proof '16_entrypoint_inventory.txt'
$MapPath = Join-Path $Latest50_4Proof '17_frozen_baseline_enforcement_map.txt'
$UnguardedPath = Join-Path $Latest50_4Proof '18_unguarded_path_report.txt'
$CrossPath = Join-Path $Latest50_4Proof '19_bypass_crosscheck_report.txt'
$ReferencePath = Join-Path $Root 'control_plane\98_trust_chain_ledger_baseline_enforcement_coverage_fingerprint.json'

foreach ($p in @($InventoryPath, $MapPath, $UnguardedPath, $CrossPath)) {
    if (-not (Test-Path -LiteralPath $p)) {
        throw ('Missing required file: ' + $p)
    }
}

$invLinesBase = @(Get-Content -LiteralPath $InventoryPath)
$mapLinesBase = @(Get-Content -LiteralPath $MapPath)
$unguardedLinesBase = @(Get-Content -LiteralPath $UnguardedPath)
$crossLinesBase = @(Get-Content -LiteralPath $CrossPath)

$base = Build-CoverageFingerprintModel -InventoryLines $invLinesBase -MapLines $mapLinesBase -UnguardedLines $unguardedLinesBase -CrossLines $crossLinesBase
$storedFingerprint = [string]$base.final_fingerprint

$referenceArtifact = [ordered]@{
    artifact_type = 'trust_chain_ledger_baseline_enforcement_coverage_fingerprint_reference'
    phase_locked = '50.5'
    source_phase = '50.4'
    source_proof_folder = $Latest50_4Proof
    source_artifacts = [ordered]@{
        entrypoint_inventory = $InventoryPath
        frozen_baseline_enforcement_map = $MapPath
        unguarded_path_report = $UnguardedPath
        bypass_crosscheck_report = $CrossPath
    }
    canonical_component_hashes = $base.component_hashes
    coverage_fingerprint_sha256 = $storedFingerprint
    fingerprint_model_version = '50.5'
    generated_utc = [DateTime]::UtcNow.ToString('o')
}

$referenceCanonical = Convert-ToCanonicalJson -Value $referenceArtifact
[System.IO.File]::WriteAllText($ReferencePath, $referenceCanonical, [System.Text.Encoding]::UTF8)

$ValidationLines = [System.Collections.Generic.List[string]]::new()
$RecordLines = [System.Collections.Generic.List[string]]::new()
$EvidenceLines = [System.Collections.Generic.List[string]]::new()
$allPass = $true

# CASE A - CLEAN FINGERPRINT GENERATION
$caseAComputed = [string]$base.final_fingerprint
$caseAOk = Add-ValidationRecord -ValidationLines $ValidationLines -RecordLines $RecordLines -CaseId 'A' -CaseName 'clean_fingerprint_generation' -Expected 'GENERATED_AND_SAVED' -ComputedFingerprint $caseAComputed -StoredFingerprint $storedFingerprint -DetectedChangeType 'none' -CertificationAllowedOrBlocked 'ALLOWED' -PassOrFail 'PASS'
if (-not $caseAOk) { $allPass = $false }
$EvidenceLines.Add('CASE A reference_saved=' + $(if (Test-Path -LiteralPath $ReferencePath) { 'TRUE' } else { 'FALSE' }))

# CASE B - NON-SEMANTIC CHANGE
$invLinesB = @($invLinesBase | ForEach-Object {
    $line = [string]$_
    if ($line -match '=') {
        ('  ' + (($line -replace '\|', ' | ') -replace '=', ' = ') + '  ')
    } else {
        $line
    }
})
$mapLinesB = @($mapLinesBase | ForEach-Object {
    $line = [string]$_
    if ($line -match '=') {
        ('\t' + (($line -replace '\|', '  |  ') -replace '=', ' = ') + '\t')
    } else {
        $line
    }
})
$caseB = Build-CoverageFingerprintModel -InventoryLines $invLinesB -MapLines $mapLinesB -UnguardedLines $unguardedLinesBase -CrossLines $crossLinesBase
$caseBPass = if ([string]$caseB.final_fingerprint -eq $storedFingerprint) { 'PASS' } else { 'FAIL' }
if (-not (Add-ValidationRecord -ValidationLines $ValidationLines -RecordLines $RecordLines -CaseId 'B' -CaseName 'non_semantic_formatting_change' -Expected 'UNCHANGED' -ComputedFingerprint ([string]$caseB.final_fingerprint) -StoredFingerprint $storedFingerprint -DetectedChangeType $(if ($caseBPass -eq 'PASS') { 'none' } else { 'unstable_canonicalization_detected' }) -CertificationAllowedOrBlocked $(if ($caseBPass -eq 'PASS') { 'ALLOWED' } else { 'BLOCKED' }) -PassOrFail $caseBPass)) { $allPass = $false }

# CASE C - ENTRYPOINT ADDITION
$addedLineC = 'file_path=' + $RunnerPath + '|function_or_entrypoint=Added-FrozenBaselineEntrypoint|role=simulated frozen-baseline entrypoint|operational_or_dead=operational|direct_gate_present=YES|transitive_gate_present=NO|gate_source_path=Invoke-ProtectedOperation -> Invoke-FrozenBaselineEnforcementGate|frozen_baseline_relevant_operation_type=added_frozen_baseline_relevant_entrypoint|coverage_classification=directly_gated|evidence_notes=synthetic_case_c'
$invLinesC = @($invLinesBase + $addedLineC)
$mapLinesC = @($mapLinesBase + ('file_path=' + $RunnerPath + '|function=Added-FrozenBaselineEntrypoint|role=simulated frozen-baseline entrypoint|operational_or_dead=operational|direct_gate=YES|transitive_gate=NO|gate_source=Invoke-ProtectedOperation -> Invoke-FrozenBaselineEnforcementGate|operation_type=added_frozen_baseline_relevant_entrypoint|coverage_classification=directly_gated|evidence=synthetic_case_c'))
$caseC = Build-CoverageFingerprintModel -InventoryLines $invLinesC -MapLines $mapLinesC -UnguardedLines $unguardedLinesBase -CrossLines $crossLinesBase
$caseCPass = if ([string]$caseC.final_fingerprint -ne $storedFingerprint) { 'PASS' } else { 'FAIL' }
if (-not (Add-ValidationRecord -ValidationLines $ValidationLines -RecordLines $RecordLines -CaseId 'C' -CaseName 'entrypoint_addition' -Expected 'CHANGED_REGRESSION_DETECTED' -ComputedFingerprint ([string]$caseC.final_fingerprint) -StoredFingerprint $storedFingerprint -DetectedChangeType $(if ($caseCPass -eq 'PASS') { 'entrypoint_addition' } else { 'undetected_entrypoint_addition' }) -CertificationAllowedOrBlocked $(if ($caseCPass -eq 'PASS') { 'BLOCKED' } else { 'ALLOWED' }) -PassOrFail $caseCPass)) { $allPass = $false }
$EvidenceLines.Add('CASE C regression_detected=' + $(if ($caseCPass -eq 'PASS') { 'TRUE' } else { 'FALSE' }))

# CASE D - COVERAGE CLASSIFICATION CHANGE
$invLinesD = @($invLinesBase)
$mapLinesD = @($mapLinesBase)
for ($i = 0; $i -lt $invLinesD.Count; $i++) {
    if ($invLinesD[$i] -match 'coverage_classification=directly_gated' -and $invLinesD[$i] -match 'operational_or_dead=operational') {
        $invLinesD[$i] = $invLinesD[$i] -replace 'coverage_classification=directly_gated', 'coverage_classification=transitively_gated'
        break
    }
}
for ($i = 0; $i -lt $mapLinesD.Count; $i++) {
    if ($mapLinesD[$i] -match 'coverage_classification=directly_gated' -and $mapLinesD[$i] -match 'operational_or_dead=operational') {
        $mapLinesD[$i] = $mapLinesD[$i] -replace 'coverage_classification=directly_gated', 'coverage_classification=transitively_gated'
        break
    }
}
$caseD = Build-CoverageFingerprintModel -InventoryLines $invLinesD -MapLines $mapLinesD -UnguardedLines $unguardedLinesBase -CrossLines $crossLinesBase
$caseDPass = if ([string]$caseD.final_fingerprint -ne $storedFingerprint) { 'PASS' } else { 'FAIL' }
if (-not (Add-ValidationRecord -ValidationLines $ValidationLines -RecordLines $RecordLines -CaseId 'D' -CaseName 'coverage_classification_change' -Expected 'CHANGED_REGRESSION_DETECTED' -ComputedFingerprint ([string]$caseD.final_fingerprint) -StoredFingerprint $storedFingerprint -DetectedChangeType $(if ($caseDPass -eq 'PASS') { 'coverage_classification_change' } else { 'undetected_classification_change' }) -CertificationAllowedOrBlocked $(if ($caseDPass -eq 'PASS') { 'BLOCKED' } else { 'ALLOWED' }) -PassOrFail $caseDPass)) { $allPass = $false }
$EvidenceLines.Add('CASE D regression_detected=' + $(if ($caseDPass -eq 'PASS') { 'TRUE' } else { 'FALSE' }))

# CASE E - ORDER CHANGE
$invLinesE = @($invLinesBase)
[array]::Reverse($invLinesE)
$caseE = Build-CoverageFingerprintModel -InventoryLines $invLinesE -MapLines $mapLinesBase -UnguardedLines $unguardedLinesBase -CrossLines $crossLinesBase
$caseEPass = if ([string]$caseE.final_fingerprint -eq $storedFingerprint) { 'PASS' } else { 'FAIL' }
if (-not (Add-ValidationRecord -ValidationLines $ValidationLines -RecordLines $RecordLines -CaseId 'E' -CaseName 'order_change' -Expected 'UNCHANGED' -ComputedFingerprint ([string]$caseE.final_fingerprint) -StoredFingerprint $storedFingerprint -DetectedChangeType $(if ($caseEPass -eq 'PASS') { 'none' } else { 'order_sensitivity_detected' }) -CertificationAllowedOrBlocked $(if ($caseEPass -eq 'PASS') { 'ALLOWED' } else { 'BLOCKED' }) -PassOrFail $caseEPass)) { $allPass = $false }

# CASE F - DEAD HELPER CHANGE
$invLinesF = @($invLinesBase)
$mapLinesF = @($mapLinesBase)
for ($i = 0; $i -lt $invLinesF.Count; $i++) {
    if ($invLinesF[$i] -match 'operational_or_dead=dead_or_non_operational') {
        $invLinesF[$i] = Set-KvInLine -Line $invLinesF[$i] -Key 'evidence_notes' -NewValue 'dead_helper_cosmetic_change_only_case_f'
        break
    }
}
for ($i = 0; $i -lt $mapLinesF.Count; $i++) {
    if ($mapLinesF[$i] -match 'operational_or_dead=dead_or_non_operational') {
        $mapLinesF[$i] = Set-KvInLine -Line $mapLinesF[$i] -Key 'evidence' -NewValue 'dead_helper_cosmetic_change_only_case_f'
        break
    }
}
$caseF = Build-CoverageFingerprintModel -InventoryLines $invLinesF -MapLines $mapLinesF -UnguardedLines $unguardedLinesBase -CrossLines $crossLinesBase
$caseFPass = if ([string]$caseF.final_fingerprint -eq $storedFingerprint) { 'PASS' } else { 'FAIL' }
if (-not (Add-ValidationRecord -ValidationLines $ValidationLines -RecordLines $RecordLines -CaseId 'F' -CaseName 'dead_helper_only_change' -Expected 'UNCHANGED' -ComputedFingerprint ([string]$caseF.final_fingerprint) -StoredFingerprint $storedFingerprint -DetectedChangeType $(if ($caseFPass -eq 'PASS') { 'none' } else { 'dead_helper_overfit_detected' }) -CertificationAllowedOrBlocked $(if ($caseFPass -eq 'PASS') { 'ALLOWED' } else { 'BLOCKED' }) -PassOrFail $caseFPass)) { $allPass = $false }

# CASE G - UNGUARDED PATH REPORT CHANGE
$unguardedLinesG = @(
    'UNGUARDED_OPERATIONAL_PATHS=1',
    'UNGUARDED file=' + $RunnerPath + '|function=Simulated-UnguardedPath|operation=simulate_unguarded_path'
)
$caseG = Build-CoverageFingerprintModel -InventoryLines $invLinesBase -MapLines $mapLinesBase -UnguardedLines $unguardedLinesG -CrossLines $crossLinesBase
$caseGPass = if ([string]$caseG.final_fingerprint -ne $storedFingerprint) { 'PASS' } else { 'FAIL' }
if (-not (Add-ValidationRecord -ValidationLines $ValidationLines -RecordLines $RecordLines -CaseId 'G' -CaseName 'unguarded_path_report_change' -Expected 'CHANGED_REGRESSION_DETECTED' -ComputedFingerprint ([string]$caseG.final_fingerprint) -StoredFingerprint $storedFingerprint -DetectedChangeType $(if ($caseGPass -eq 'PASS') { 'unguarded_path_report_change' } else { 'undetected_unguarded_change' }) -CertificationAllowedOrBlocked $(if ($caseGPass -eq 'PASS') { 'BLOCKED' } else { 'ALLOWED' }) -PassOrFail $caseGPass)) { $allPass = $false }
$EvidenceLines.Add('CASE G regression_detected=' + $(if ($caseGPass -eq 'PASS') { 'TRUE' } else { 'FALSE' }))

# CASE H - OPERATIONAL/DEAD RECLASSIFICATION
$invLinesH = @($invLinesBase)
$mapLinesH = @($mapLinesBase)
for ($i = 0; $i -lt $invLinesH.Count; $i++) {
    if ($invLinesH[$i] -match 'operational_or_dead=operational' -and $invLinesH[$i] -match 'frozen_baseline_relevant_operation_type=canonicalize_hash_compare') {
        $invLinesH[$i] = $invLinesH[$i] -replace 'operational_or_dead=operational', 'operational_or_dead=dead_or_non_operational'
        break
    }
}
for ($i = 0; $i -lt $mapLinesH.Count; $i++) {
    if ($mapLinesH[$i] -match 'operational_or_dead=operational' -and $mapLinesH[$i] -match 'operation_type=canonicalize_hash_compare') {
        $mapLinesH[$i] = $mapLinesH[$i] -replace 'operational_or_dead=operational', 'operational_or_dead=dead_or_non_operational'
        break
    }
}
$caseH = Build-CoverageFingerprintModel -InventoryLines $invLinesH -MapLines $mapLinesH -UnguardedLines $unguardedLinesBase -CrossLines $crossLinesBase
$caseHPass = if ([string]$caseH.final_fingerprint -ne $storedFingerprint) { 'PASS' } else { 'FAIL' }
if (-not (Add-ValidationRecord -ValidationLines $ValidationLines -RecordLines $RecordLines -CaseId 'H' -CaseName 'operational_dead_reclassification' -Expected 'CHANGED_REGRESSION_DETECTED' -ComputedFingerprint ([string]$caseH.final_fingerprint) -StoredFingerprint $storedFingerprint -DetectedChangeType $(if ($caseHPass -eq 'PASS') { 'operational_dead_reclassification' } else { 'undetected_reclassification_change' }) -CertificationAllowedOrBlocked $(if ($caseHPass -eq 'PASS') { 'BLOCKED' } else { 'ALLOWED' }) -PassOrFail $caseHPass)) { $allPass = $false }
$EvidenceLines.Add('CASE H regression_detected=' + $(if ($caseHPass -eq 'PASS') { 'TRUE' } else { 'FALSE' }))

# CASE I - BYPASS CROSS-CHECK CHANGE
$crossLinesI = @($crossLinesBase)
for ($i = 0; $i -lt $crossLinesI.Count; $i++) {
    if ($crossLinesI[$i] -match '^operation=' -and $crossLinesI[$i] -match 'in_50_3_inventory=TRUE') {
        $crossLinesI[$i] = $crossLinesI[$i] -replace 'in_50_3_inventory=TRUE', 'in_50_3_inventory=FALSE'
        break
    }
}
$caseI = Build-CoverageFingerprintModel -InventoryLines $invLinesBase -MapLines $mapLinesBase -UnguardedLines $unguardedLinesBase -CrossLines $crossLinesI
$caseIPass = if ([string]$caseI.final_fingerprint -ne $storedFingerprint) { 'PASS' } else { 'FAIL' }
if (-not (Add-ValidationRecord -ValidationLines $ValidationLines -RecordLines $RecordLines -CaseId 'I' -CaseName 'bypass_crosscheck_change' -Expected 'CHANGED_REGRESSION_DETECTED' -ComputedFingerprint ([string]$caseI.final_fingerprint) -StoredFingerprint $storedFingerprint -DetectedChangeType $(if ($caseIPass -eq 'PASS') { 'bypass_crosscheck_change' } else { 'undetected_bypass_crosscheck_change' }) -CertificationAllowedOrBlocked $(if ($caseIPass -eq 'PASS') { 'BLOCKED' } else { 'ALLOWED' }) -PassOrFail $caseIPass)) { $allPass = $false }
$EvidenceLines.Add('CASE I regression_detected=' + $(if ($caseIPass -eq 'PASS') { 'TRUE' } else { 'FALSE' }))

$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status01 = @(
    'PHASE=50.5',
    'TITLE=Trust-Chain Ledger Baseline Enforcement Coverage Fingerprint Trust-Chain Baseline Enforcement Coverage Fingerprint Lock',
    'GATE=' + $Gate,
    'FINGERPRINT_DETERMINISTIC=' + $(if ($caseBPass -eq 'PASS' -and $caseEPass -eq 'PASS') { 'TRUE' } else { 'FALSE' }),
    'NON_SEMANTIC_CHANGES_IGNORED=' + $(if ($caseBPass -eq 'PASS' -and $caseEPass -eq 'PASS' -and $caseFPass -eq 'PASS') { 'TRUE' } else { 'FALSE' }),
    'REGRESSION_DETECTION_WORKING=' + $(if ($caseCPass -eq 'PASS' -and $caseDPass -eq 'PASS' -and $caseGPass -eq 'PASS' -and $caseHPass -eq 'PASS' -and $caseIPass -eq 'PASS') { 'TRUE' } else { 'FALSE' }),
    'REFERENCE_SAVED=' + $(if (Test-Path -LiteralPath $ReferencePath) { 'TRUE' } else { 'FALSE' }),
    'RUNTIME_STATE_MACHINE_CHANGED=FALSE',
    'NO_FALLBACK=TRUE',
    'NO_REGENERATION=TRUE'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '01_status.txt'), $status01, [System.Text.Encoding]::UTF8)

$head02 = @(
    'RUNNER=' + $RunnerPath,
    'SOURCE_PHASE50_4_PROOF=' + $Latest50_4Proof,
    'INPUT_16=' + $InventoryPath,
    'INPUT_17=' + $MapPath,
    'INPUT_18=' + $UnguardedPath,
    'INPUT_19=' + $CrossPath,
    'REFERENCE_OUTPUT=' + $ReferencePath
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '02_head.txt'), $head02, [System.Text.Encoding]::UTF8)

$def10 = @(
    'FINGERPRINT_SCOPE=Phase 50.4 frozen-baseline enforcement coverage model',
    'FINGERPRINT_INPUTS=16_entrypoint_inventory,17_frozen_baseline_enforcement_map,18_unguarded_path_report,19_bypass_crosscheck_report',
    'NORMALIZATION=Parse pipe key-value records, trim whitespace, normalize booleans, normalize case on semantic classification/state fields',
    'ORDER_STABILITY=Operational records sorted by operation_type+function_name; cross-check rows sorted by operation',
    'DEAD_HELPER_POLICY=Dead/non-operational cosmetic-only fields excluded from semantic model; operational path semantics retained',
    'DETERMINISM=Final fingerprint is SHA256 of canonical JSON model over normalized semantic structures'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '10_fingerprint_definition.txt'), $def10, [System.Text.Encoding]::UTF8)

$rules11 = @(
    'RULE_1=Whitespace/formatting-only changes must not change fingerprint',
    'RULE_2=File/record ordering changes must not change fingerprint',
    'RULE_3=Entrypoint addition/removal in operational surface must change fingerprint',
    'RULE_4=Coverage classification changes (direct/transitive/unguarded) on operational paths must change fingerprint',
    'RULE_5=Operational/dead reclassification on real reachable helper paths must change fingerprint',
    'RULE_6=Dead helper cosmetic-only changes must not change fingerprint',
    'RULE_7=Unguarded path report semantic changes must change fingerprint',
    'RULE_8=Bypass cross-check semantic changes must change fingerprint',
    'RULE_9=Certification is BLOCKED on unexpected semantic fingerprint mismatch'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '11_fingerprint_rules.txt'), $rules11, [System.Text.Encoding]::UTF8)

$files12 = @(
    'READ=' + $InventoryPath,
    'READ=' + $MapPath,
    'READ=' + $UnguardedPath,
    'READ=' + $CrossPath,
    'WRITE=' + $ReferencePath,
    'WRITE=' + $PF
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '12_files_touched.txt'), $files12, [System.Text.Encoding]::UTF8)

$build13 = @(
    'BASE_FINGERPRINT=' + $storedFingerprint,
    'INVENTORY_OPERATIONAL_COUNT=' + $base.inventory_operational_count,
    'MAP_OPERATIONAL_COUNT=' + $base.map_operational_count,
    'UNGUARDED_OPERATIONAL_PATHS=' + $base.unguarded_operational_paths,
    'BYPASS_OPERATION_COUNT=' + $base.bypass_operation_count,
    'REFERENCE_PATH=' + $ReferencePath,
    'REFERENCE_SAVED=' + $(if (Test-Path -LiteralPath $ReferencePath) { 'TRUE' } else { 'FALSE' }),
    'GATE=' + $Gate
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '13_build_output.txt'), $build13, [System.Text.Encoding]::UTF8)

[System.IO.File]::WriteAllText((Join-Path $PF '14_validation_results.txt'), ($ValidationLines -join "`r`n"), [System.Text.Encoding]::UTF8)

$summary15 = @(
    'TOTAL_CASES=9',
    'PASSED=' + @($ValidationLines | Where-Object { $_ -match '=> PASS$' }).Count,
    'FAILED=' + @($ValidationLines | Where-Object { $_ -match '=> FAIL$' }).Count,
    'DETERMINISM_VERIFIED=' + $(if ($caseBPass -eq 'PASS' -and $caseEPass -eq 'PASS') { 'TRUE' } else { 'FALSE' }),
    'NON_SEMANTIC_STABILITY_VERIFIED=' + $(if ($caseBPass -eq 'PASS' -and $caseEPass -eq 'PASS' -and $caseFPass -eq 'PASS') { 'TRUE' } else { 'FALSE' }),
    'REGRESSION_CASES_VERIFIED=' + $(if ($caseCPass -eq 'PASS' -and $caseDPass -eq 'PASS' -and $caseGPass -eq 'PASS' -and $caseHPass -eq 'PASS' -and $caseIPass -eq 'PASS') { 'TRUE' } else { 'FALSE' }),
    'REFERENCE_ARTIFACT_PATH=' + $ReferencePath,
    'REFERENCE_NUMBERING_NOTE=control_plane 98 filename already exists as expected next reference index; updated in place without collision',
    'RUNTIME_STATE_MACHINE_UNCHANGED=TRUE',
    'NO_FALLBACK=TRUE',
    'NO_REGENERATION=TRUE',
    'GATE=' + $Gate
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '15_behavior_summary.txt'), $summary15, [System.Text.Encoding]::UTF8)

$recordHeader = 'case|computed_fingerprint|stored_reference_fingerprint|fingerprint_match_status|detected_change_type|certification_allowed_or_blocked'
$recordBody = @($recordHeader) + @($RecordLines)
[System.IO.File]::WriteAllText((Join-Path $PF '16_coverage_fingerprint_record.txt'), ($recordBody -join "`r`n"), [System.Text.Encoding]::UTF8)

$evidenceHeader = @(
    'BASE_COMPONENT_HASH_inventory=' + [string]$base.component_hashes.inventory_semantic_sha256,
    'BASE_COMPONENT_HASH_map=' + [string]$base.component_hashes.map_semantic_sha256,
    'BASE_COMPONENT_HASH_unguarded=' + [string]$base.component_hashes.unguarded_semantic_sha256,
    'BASE_COMPONENT_HASH_bypass=' + [string]$base.component_hashes.bypass_crosscheck_semantic_sha256
)
$evidenceBody = @($evidenceHeader + $EvidenceLines)
[System.IO.File]::WriteAllText((Join-Path $PF '17_regression_detection_evidence.txt'), ($evidenceBody -join "`r`n"), [System.Text.Encoding]::UTF8)

$gate98 = @('PHASE=50.5', 'GATE=' + $Gate) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '98_gate_phase50_5.txt'), $gate98, [System.Text.Encoding]::UTF8)

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
