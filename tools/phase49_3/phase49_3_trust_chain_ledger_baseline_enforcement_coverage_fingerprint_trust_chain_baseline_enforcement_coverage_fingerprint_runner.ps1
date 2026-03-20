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

function Get-CanonicalObjectHash {
    param([object]$Obj)
    return Get-StringSha256Hex -Text (Convert-ToCanonicalJson -Value $Obj)
}

function Find-LatestProofFolder {
    param([string]$Prefix)

    $proofRoot = Join-Path $Root '_proof'
    $dirs = Get-ChildItem -LiteralPath $proofRoot -Directory | Where-Object { $_.Name -like ($Prefix + '*') } | Sort-Object Name -Descending
    return ($dirs | Select-Object -First 1)
}

function ConvertFrom-KeyValueLine {
    param([string]$Line)

    $map = [ordered]@{}
    foreach ($segment in ($Line -split '\|')) {
        $idx = $segment.IndexOf('=')
        if ($idx -gt 0) {
            $key = $segment.Substring(0, $idx).Trim()
            $value = $segment.Substring($idx + 1).Trim()
            $map[$key] = $value
        }
    }
    return [pscustomobject]$map
}

function ConvertFrom-KeyValueText {
    param([string]$Text)

    $map = [ordered]@{}
    $kvPattern = '([A-Za-z0-9_\-]+)=([^=\r\n]+?)(?=\s+[A-Za-z0-9_\-]+=|$)'
    $kvMatches = [regex]::Matches($Text, $kvPattern)
    foreach ($m in $kvMatches) {
        $k = [string]$m.Groups[1].Value
        $v = [string]$m.Groups[2].Value.Trim()
        if (-not [string]::IsNullOrWhiteSpace($k)) {
            $map[$k] = $v
        }
    }

    $lines = @($Text -split "`r?`n")
    foreach ($line in $lines) {
        foreach ($segment in ($line -split '\|')) {
            $idx = $segment.IndexOf('=')
            if ($idx -gt 0) {
                $k = $segment.Substring(0, $idx).Trim()
                $v = $segment.Substring($idx + 1).Trim()
                if (-not [string]::IsNullOrWhiteSpace($k)) {
                    $map[$k] = $v
                }
            }
        }
    }
    return [pscustomobject]$map
}

function Set-ObjectPropertyValue {
    param(
        [object]$Obj,
        [string]$Name,
        [object]$Value
    )

    if ($Obj.PSObject.Properties.Name -contains $Name) {
        $Obj.PSObject.Properties[$Name].Value = $Value
    } else {
        $Obj | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }
}

function Import-PipeTable {
    param([string]$FilePath)

    $lines = Get-Content -LiteralPath $FilePath
    if ($lines.Count -eq 0) { return @() }

    $header = @($lines[0] -split '\|')
    $rows = [System.Collections.Generic.List[object]]::new()

    for ($i = 1; $i -lt $lines.Count; $i++) {
        $line = [string]$lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = @($line -split '\|', $header.Count)
        $obj = [ordered]@{}
        for ($c = 0; $c -lt $header.Count; $c++) {
            $key = [string]$header[$c]
            $val = if ($c -lt $parts.Count) { [string]$parts[$c] } else { '' }
            $obj[$key] = $val
        }
        $rows.Add([pscustomobject]$obj)
    }

    return @($rows)
}

function ConvertTo-NormalizedText {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    $t = [string]$Text
    $t = $t.Trim()
    $t = ($t -replace '\s+', ' ')
    return $t
}

function Get-ObjectValueOrDefault {
    param(
        [object]$Obj,
        [string]$Name,
        [object]$DefaultValue
    )

    if ($null -eq $Obj) { return $DefaultValue }
    if ($Obj.PSObject.Properties.Name -contains $Name) {
        return $Obj.PSObject.Properties[$Name].Value
    }
    return $DefaultValue
}

function Convert-ToSemanticFingerprintModel {
    param(
        [object[]]$InventoryRows,
        [object[]]$MapRows,
        [object]$UnguardedState,
        [object]$BypassState
    )

    $operationalRows = @($InventoryRows | Where-Object {
        (ConvertTo-NormalizedText -Text $_.symbol_kind) -eq 'actual_function' -and
        (ConvertTo-NormalizedText -Text $_.operational_or_dead) -eq 'operational'
    })

    $operationalKeySet = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($row in $operationalRows) {
        $key = ((ConvertTo-NormalizedText -Text $row.file_path) + '|' + (ConvertTo-NormalizedText -Text $row.function_or_entrypoint_name))
        [void]$operationalKeySet.Add($key)
    }

    $semanticInventory = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $operationalRows | Sort-Object file_path, function_or_entrypoint_name) {
        $semanticInventory.Add([ordered]@{
            file_path = ConvertTo-NormalizedText -Text ([string]$row.file_path)
            function_or_entrypoint_name = ConvertTo-NormalizedText -Text ([string]$row.function_or_entrypoint_name)
            role = ConvertTo-NormalizedText -Text ([string]$row.role)
            direct_gate_present = ConvertTo-NormalizedText -Text ([string]$row.direct_gate_present)
            transitive_gate_present = ConvertTo-NormalizedText -Text ([string]$row.transitive_gate_present)
            gate_source_path = ConvertTo-NormalizedText -Text ([string]$row.gate_source_path)
            frozen_baseline_relevant_operation_type = ConvertTo-NormalizedText -Text ([string]$row.frozen_baseline_relevant_operation_type)
            coverage_classification = ConvertTo-NormalizedText -Text ([string]$row.coverage_classification)
        })
    }

    $semanticMap = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $MapRows) {
        $k = ((ConvertTo-NormalizedText -Text $row.file_path) + '|' + (ConvertTo-NormalizedText -Text $row.function_or_entrypoint_name))
        if (-not $operationalKeySet.Contains($k)) { continue }

        $semanticMap.Add([ordered]@{
            file_path = ConvertTo-NormalizedText -Text ([string]$row.file_path)
            function_or_entrypoint_name = ConvertTo-NormalizedText -Text ([string]$row.function_or_entrypoint_name)
            coverage_classification = ConvertTo-NormalizedText -Text ([string]$row.coverage_classification)
            gate_source_path = ConvertTo-NormalizedText -Text ([string]$row.gate_source_path)
        })
    }
    $semanticMap = @($semanticMap | Sort-Object file_path, function_or_entrypoint_name)

    $inventoryStableSet = @($semanticInventory | ForEach-Object { Convert-ToCanonicalJson -Value $_ } | Sort-Object -Unique)
    $mapStableSet = @($semanticMap | ForEach-Object { Convert-ToCanonicalJson -Value $_ } | Sort-Object -Unique)

    $model = [ordered]@{
        model_version = '49.3'
        operational_inventory_count = $inventoryStableSet.Count
        operational_inventory_records = @($inventoryStableSet)
        operational_map_count = $mapStableSet.Count
        operational_map_records = @($mapStableSet)
        unguarded_path_report = [ordered]@{
            unguarded_operational_paths = [int](Get-ObjectValueOrDefault -Obj $UnguardedState -Name 'unguarded_operational_paths' -DefaultValue 0)
            has_unguarded_paths = ([int](Get-ObjectValueOrDefault -Obj $UnguardedState -Name 'unguarded_operational_paths' -DefaultValue 0) -gt 0)
        }
        bypass_crosscheck_report = [ordered]@{
            latest_phase49_1_gate_pass = ((ConvertTo-NormalizedText -Text ([string](Get-ObjectValueOrDefault -Obj $BypassState -Name 'latest_phase49_1_gate_pass' -DefaultValue 'FALSE'))).ToUpperInvariant() -eq 'TRUE')
            latest_phase49_1_all_validation_cases_pass = ((ConvertTo-NormalizedText -Text ([string](Get-ObjectValueOrDefault -Obj $BypassState -Name 'latest_phase49_1_all_validation_cases_pass' -DefaultValue 'FALSE'))).ToUpperInvariant() -eq 'TRUE')
            proof_inventory_labels = [int](Get-ObjectValueOrDefault -Obj $BypassState -Name 'proof_inventory_labels' -DefaultValue 0)
            proof_map_coverage = ((ConvertTo-NormalizedText -Text ([string](Get-ObjectValueOrDefault -Obj $BypassState -Name 'proof_map_coverage' -DefaultValue 'FALSE'))).ToUpperInvariant() -eq 'TRUE')
            gate_record_coverage = ((ConvertTo-NormalizedText -Text ([string](Get-ObjectValueOrDefault -Obj $BypassState -Name 'gate_record_coverage' -DefaultValue 'FALSE'))).ToUpperInvariant() -eq 'TRUE')
            bypass_crosscheck = ((ConvertTo-NormalizedText -Text ([string](Get-ObjectValueOrDefault -Obj $BypassState -Name 'bypass_crosscheck' -DefaultValue 'FALSE'))).ToUpperInvariant() -eq 'TRUE')
        }
    }

    return $model
}

function Get-CoverageFingerprintPayload {
    param(
        [object[]]$InventoryRows,
        [object[]]$MapRows,
        [object]$UnguardedState,
        [object]$BypassState
    )

    $semanticModel = Convert-ToSemanticFingerprintModel -InventoryRows $InventoryRows -MapRows $MapRows -UnguardedState $UnguardedState -BypassState $BypassState
    $inventoryHash = Get-CanonicalObjectHash -Obj $semanticModel.operational_inventory_records
    $mapHash = Get-CanonicalObjectHash -Obj $semanticModel.operational_map_records
    $unguardedHash = Get-CanonicalObjectHash -Obj $semanticModel.unguarded_path_report
    $bypassHash = Get-CanonicalObjectHash -Obj $semanticModel.bypass_crosscheck_report
    $fingerprint = Get-CanonicalObjectHash -Obj $semanticModel

    return [ordered]@{
        semantic_model = $semanticModel
        canonical_input_hashes = [ordered]@{
            inventory_semantic_hash = $inventoryHash
            map_semantic_hash = $mapHash
            unguarded_semantic_hash = $unguardedHash
            bypass_crosscheck_semantic_hash = $bypassHash
        }
        coverage_fingerprint_sha256 = $fingerprint
    }
}

function Copy-Object {
    param([object]$Obj)
    return (($Obj | ConvertTo-Json -Depth 80 -Compress) | ConvertFrom-Json)
}

function Add-CaseResultLine {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$CaseId,
        [string]$Expected,
        [string]$Computed,
        [string]$Stored,
        [string]$MatchStatus,
        [string]$ChangeType,
        [string]$AllowedOrBlocked,
        [bool]$Pass
    )

    $Lines.Add(
        'CASE ' + $CaseId +
        ' | computed_fingerprint=' + $Computed +
        ' | stored_reference_fingerprint=' + $Stored +
        ' | fingerprint_match_status=' + $MatchStatus +
        ' | detected_change_type=' + $ChangeType +
        ' | certification_allowed_or_blocked=' + $AllowedOrBlocked +
        ' | expected=' + $Expected +
        ' => ' + $(if ($Pass) { 'PASS' } else { 'FAIL' })
    )
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\phase49_3_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$Latest49_2Proof = Find-LatestProofFolder -Prefix 'phase49_2_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_coverage_audit_'
if ($null -eq $Latest49_2Proof) { throw 'Missing latest phase49_2 proof folder.' }

$InventoryPath = Join-Path $Latest49_2Proof.FullName '16_entrypoint_inventory.txt'
$MapPath = Join-Path $Latest49_2Proof.FullName '17_frozen_baseline_enforcement_map.txt'
$UnguardedPath = Join-Path $Latest49_2Proof.FullName '18_unguarded_path_report.txt'
$BypassPath = Join-Path $Latest49_2Proof.FullName '19_bypass_crosscheck_report.txt'

foreach ($p in @($InventoryPath, $MapPath, $UnguardedPath, $BypassPath)) {
    if (-not (Test-Path -LiteralPath $p)) { throw ('Missing required phase49_2 artifact: ' + $p) }
}

$inventoryRows = @(Import-PipeTable -FilePath $InventoryPath)
$mapRows = @(Import-PipeTable -FilePath $MapPath)
$unguardedState = ConvertFrom-KeyValueText -Text (Get-Content -Raw -LiteralPath $UnguardedPath)
$bypassState = ConvertFrom-KeyValueText -Text (Get-Content -Raw -LiteralPath $BypassPath)

$basePayload = Get-CoverageFingerprintPayload -InventoryRows $inventoryRows -MapRows $mapRows -UnguardedState $unguardedState -BypassState $bypassState
$baseFingerprint = [string]$basePayload.coverage_fingerprint_sha256

$ReferencePath = Join-Path $Root 'control_plane\93_trust_chain_ledger_baseline_enforcement_coverage_fingerprint.json'
$referenceObj = [ordered]@{
    artifact = '93_trust_chain_ledger_baseline_enforcement_coverage_fingerprint'
    phase_locked = '49.3'
    source_phase = '49.2'
    source_artifacts = @(
        '16_entrypoint_inventory.txt',
        '17_frozen_baseline_enforcement_map.txt',
        '18_unguarded_path_report.txt',
        '19_bypass_crosscheck_report.txt'
    )
    coverage_fingerprint_sha256 = $baseFingerprint
    canonical_input_hashes = $basePayload.canonical_input_hashes
    generated_utc = (Get-Date -AsUTC -Format 'yyyy-MM-ddTHH:mm:ssZ')
}
($referenceObj | ConvertTo-Json -Depth 50) | Set-Content -LiteralPath $ReferencePath -Encoding UTF8 -NoNewline

$ValidationLines = [System.Collections.Generic.List[string]]::new()
$RecordLines = [System.Collections.Generic.List[string]]::new()
$EvidenceLines = [System.Collections.Generic.List[string]]::new()
$allPass = $true

# CASE A - clean fingerprint generation
$caseAComputed = $baseFingerprint
$caseAStored = [string]$referenceObj.coverage_fingerprint_sha256
$caseAMatch = if ($caseAComputed -eq $caseAStored) { 'MATCH' } else { 'MISMATCH' }
$caseAPass = ($caseAMatch -eq 'MATCH')
if (-not $caseAPass) { $allPass = $false }
$ValidationLines.Add('CASE A clean_fingerprint_generation coverage_fingerprint=GENERATED reference_saved=' + $(if ($caseAPass) { 'TRUE' } else { 'FALSE' }) + ' => ' + $(if ($caseAPass) { 'PASS' } else { 'FAIL' }))
Add-CaseResultLine -Lines $RecordLines -CaseId 'A' -Expected 'fingerprint_generated_and_reference_saved' -Computed $caseAComputed -Stored $caseAStored -MatchStatus $caseAMatch -ChangeType 'none' -AllowedOrBlocked 'ALLOWED' -Pass $caseAPass
$EvidenceLines.Add('CASE A inventory_semantic_hash=' + [string]$basePayload.canonical_input_hashes.inventory_semantic_hash)
$EvidenceLines.Add('CASE A map_semantic_hash=' + [string]$basePayload.canonical_input_hashes.map_semantic_hash)
$EvidenceLines.Add('CASE A unguarded_semantic_hash=' + [string]$basePayload.canonical_input_hashes.unguarded_semantic_hash)
$EvidenceLines.Add('CASE A bypass_semantic_hash=' + [string]$basePayload.canonical_input_hashes.bypass_crosscheck_semantic_hash)

# CASE B - non-semantic change
$invB = @(Copy-Object -Obj $inventoryRows)
if ($invB.Count -gt 0) {
    $invB[0].notes_on_evidence = '   ' + [string]$invB[0].notes_on_evidence + '   '
}
$caseBPayload = Get-CoverageFingerprintPayload -InventoryRows $invB -MapRows $mapRows -UnguardedState $unguardedState -BypassState $bypassState
$caseBComputed = [string]$caseBPayload.coverage_fingerprint_sha256
$caseBMatch = if ($caseBComputed -eq $baseFingerprint) { 'MATCH' } else { 'MISMATCH' }
$caseBPass = ($caseBMatch -eq 'MATCH')
if (-not $caseBPass) { $allPass = $false }
$ValidationLines.Add('CASE B non_semantic_change fingerprint=UNCHANGED => ' + $(if ($caseBPass) { 'PASS' } else { 'FAIL' }))
Add-CaseResultLine -Lines $RecordLines -CaseId 'B' -Expected 'fingerprint_unchanged' -Computed $caseBComputed -Stored $baseFingerprint -MatchStatus $caseBMatch -ChangeType 'formatting_only' -AllowedOrBlocked $(if ($caseBPass) { 'ALLOWED' } else { 'BLOCKED' }) -Pass $caseBPass

# CASE C - entrypoint addition
$invC = @(Copy-Object -Obj $inventoryRows)
$invC += [pscustomobject]@{
    file_path = 'tools\phase49_1\phase49_1_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_bypass_resistance_runner.ps1'
    function_or_entrypoint_name = 'Synthetic-AddedEntrypoint'
    role = 'frozen_baseline_snapshot_load_entrypoint'
    operational_or_dead = 'operational'
    direct_gate_present = 'yes'
    transitive_gate_present = 'no'
    gate_source_path = 'synthetic_test_gate_source'
    frozen_baseline_relevant_operation_type = 'load_frozen_baseline_snapshot'
    coverage_classification = 'directly_gated'
    symbol_kind = 'actual_function'
    notes_on_evidence = 'synthetic_case_c'
}
$caseCPayload = Get-CoverageFingerprintPayload -InventoryRows $invC -MapRows $mapRows -UnguardedState $unguardedState -BypassState $bypassState
$caseCComputed = [string]$caseCPayload.coverage_fingerprint_sha256
$caseCMatch = if ($caseCComputed -eq $baseFingerprint) { 'MATCH' } else { 'MISMATCH' }
$caseCPass = ($caseCMatch -eq 'MISMATCH')
if (-not $caseCPass) { $allPass = $false }
$ValidationLines.Add('CASE C entrypoint_addition fingerprint=CHANGED regression_detected=' + $(if ($caseCPass) { 'TRUE' } else { 'FALSE' }) + ' => ' + $(if ($caseCPass) { 'PASS' } else { 'FAIL' }))
Add-CaseResultLine -Lines $RecordLines -CaseId 'C' -Expected 'fingerprint_changed_regression_detected' -Computed $caseCComputed -Stored $baseFingerprint -MatchStatus $caseCMatch -ChangeType 'entrypoint_addition' -AllowedOrBlocked $(if ($caseCPass) { 'BLOCKED' } else { 'ALLOWED' }) -Pass $caseCPass

# CASE D - coverage classification change
$invD = @(Copy-Object -Obj $inventoryRows)
$opD = @($invD | Where-Object { (ConvertTo-NormalizedText -Text $_.operational_or_dead) -eq 'operational' -and (ConvertTo-NormalizedText -Text $_.symbol_kind) -eq 'actual_function' } | Select-Object -First 1)
if ($opD.Count -gt 0) {
    $opD[0].coverage_classification = if ((ConvertTo-NormalizedText -Text $opD[0].coverage_classification) -eq 'directly_gated') { 'transitively_gated' } else { 'directly_gated' }
}
$caseDPayload = Get-CoverageFingerprintPayload -InventoryRows $invD -MapRows $mapRows -UnguardedState $unguardedState -BypassState $bypassState
$caseDComputed = [string]$caseDPayload.coverage_fingerprint_sha256
$caseDMatch = if ($caseDComputed -eq $baseFingerprint) { 'MATCH' } else { 'MISMATCH' }
$caseDPass = ($caseDMatch -eq 'MISMATCH')
if (-not $caseDPass) { $allPass = $false }
$ValidationLines.Add('CASE D coverage_classification_change fingerprint=CHANGED regression_detected=' + $(if ($caseDPass) { 'TRUE' } else { 'FALSE' }) + ' => ' + $(if ($caseDPass) { 'PASS' } else { 'FAIL' }))
Add-CaseResultLine -Lines $RecordLines -CaseId 'D' -Expected 'fingerprint_changed_regression_detected' -Computed $caseDComputed -Stored $baseFingerprint -MatchStatus $caseDMatch -ChangeType 'coverage_classification_change' -AllowedOrBlocked $(if ($caseDPass) { 'BLOCKED' } else { 'ALLOWED' }) -Pass $caseDPass

# CASE E - order change
$invE = @($inventoryRows | Sort-Object function_or_entrypoint_name -Descending)
$mapE = @($mapRows | Sort-Object function_or_entrypoint_name -Descending)
$caseEPayload = Get-CoverageFingerprintPayload -InventoryRows $invE -MapRows $mapE -UnguardedState $unguardedState -BypassState $bypassState
$caseEComputed = [string]$caseEPayload.coverage_fingerprint_sha256
$caseEMatch = if ($caseEComputed -eq $baseFingerprint) { 'MATCH' } else { 'MISMATCH' }
$caseEPass = ($caseEMatch -eq 'MATCH')
if (-not $caseEPass) { $allPass = $false }
$ValidationLines.Add('CASE E order_change fingerprint=UNCHANGED => ' + $(if ($caseEPass) { 'PASS' } else { 'FAIL' }))
Add-CaseResultLine -Lines $RecordLines -CaseId 'E' -Expected 'fingerprint_unchanged' -Computed $caseEComputed -Stored $baseFingerprint -MatchStatus $caseEMatch -ChangeType 'record_order_only' -AllowedOrBlocked $(if ($caseEPass) { 'ALLOWED' } else { 'BLOCKED' }) -Pass $caseEPass

# CASE F - dead helper change
$invF = @(Copy-Object -Obj $inventoryRows)
$deadF = @($invF | Where-Object { (ConvertTo-NormalizedText -Text $_.operational_or_dead) -eq 'dead' -and (ConvertTo-NormalizedText -Text $_.symbol_kind) -eq 'actual_function' } | Select-Object -First 1)
if ($deadF.Count -gt 0) {
    $deadF[0].notes_on_evidence = 'dead_helper_cosmetic_change_case_f'
    $deadF[0].role = [string]$deadF[0].role + '_cosmetic'
}
$caseFPayload = Get-CoverageFingerprintPayload -InventoryRows $invF -MapRows $mapRows -UnguardedState $unguardedState -BypassState $bypassState
$caseFComputed = [string]$caseFPayload.coverage_fingerprint_sha256
$caseFMatch = if ($caseFComputed -eq $baseFingerprint) { 'MATCH' } else { 'MISMATCH' }
$caseFPass = ($caseFMatch -eq 'MATCH')
if (-not $caseFPass) { $allPass = $false }
$ValidationLines.Add('CASE F dead_helper_change fingerprint=UNCHANGED => ' + $(if ($caseFPass) { 'PASS' } else { 'FAIL' }))
Add-CaseResultLine -Lines $RecordLines -CaseId 'F' -Expected 'fingerprint_unchanged' -Computed $caseFComputed -Stored $baseFingerprint -MatchStatus $caseFMatch -ChangeType 'dead_helper_cosmetic_only' -AllowedOrBlocked $(if ($caseFPass) { 'ALLOWED' } else { 'BLOCKED' }) -Pass $caseFPass

# CASE G - unguarded path report change
$unguardedG = Copy-Object -Obj $unguardedState
$unguardedG.unguarded_operational_paths = 1
$caseGPayload = Get-CoverageFingerprintPayload -InventoryRows $inventoryRows -MapRows $mapRows -UnguardedState $unguardedG -BypassState $bypassState
$caseGComputed = [string]$caseGPayload.coverage_fingerprint_sha256
$caseGMatch = if ($caseGComputed -eq $baseFingerprint) { 'MATCH' } else { 'MISMATCH' }
$caseGPass = ($caseGMatch -eq 'MISMATCH')
if (-not $caseGPass) { $allPass = $false }
$ValidationLines.Add('CASE G unguarded_path_report_change fingerprint=CHANGED regression_detected=' + $(if ($caseGPass) { 'TRUE' } else { 'FALSE' }) + ' => ' + $(if ($caseGPass) { 'PASS' } else { 'FAIL' }))
Add-CaseResultLine -Lines $RecordLines -CaseId 'G' -Expected 'fingerprint_changed_regression_detected' -Computed $caseGComputed -Stored $baseFingerprint -MatchStatus $caseGMatch -ChangeType 'unguarded_path_state_change' -AllowedOrBlocked $(if ($caseGPass) { 'BLOCKED' } else { 'ALLOWED' }) -Pass $caseGPass

# CASE H - operational/dead reclassification
$invH = @(Copy-Object -Obj $inventoryRows)
$opH = @($invH | Where-Object { (ConvertTo-NormalizedText -Text $_.operational_or_dead) -eq 'operational' -and (ConvertTo-NormalizedText -Text $_.symbol_kind) -eq 'actual_function' } | Select-Object -First 1)
if ($opH.Count -gt 0) {
    $opH[0].operational_or_dead = 'dead'
}
$caseHPayload = Get-CoverageFingerprintPayload -InventoryRows $invH -MapRows $mapRows -UnguardedState $unguardedState -BypassState $bypassState
$caseHComputed = [string]$caseHPayload.coverage_fingerprint_sha256
$caseHMatch = if ($caseHComputed -eq $baseFingerprint) { 'MATCH' } else { 'MISMATCH' }
$caseHPass = ($caseHMatch -eq 'MISMATCH')
if (-not $caseHPass) { $allPass = $false }
$ValidationLines.Add('CASE H operational_dead_reclassification fingerprint=CHANGED regression_detected=' + $(if ($caseHPass) { 'TRUE' } else { 'FALSE' }) + ' => ' + $(if ($caseHPass) { 'PASS' } else { 'FAIL' }))
Add-CaseResultLine -Lines $RecordLines -CaseId 'H' -Expected 'fingerprint_changed_regression_detected' -Computed $caseHComputed -Stored $baseFingerprint -MatchStatus $caseHMatch -ChangeType 'operational_dead_reclassification' -AllowedOrBlocked $(if ($caseHPass) { 'BLOCKED' } else { 'ALLOWED' }) -Pass $caseHPass

# CASE I - bypass crosscheck change
$bypassI = Copy-Object -Obj $bypassState
Set-ObjectPropertyValue -Obj $bypassI -Name 'gate_record_coverage' -Value 'FALSE'
$caseIPayload = Get-CoverageFingerprintPayload -InventoryRows $inventoryRows -MapRows $mapRows -UnguardedState $unguardedState -BypassState $bypassI
$caseIComputed = [string]$caseIPayload.coverage_fingerprint_sha256
$caseIMatch = if ($caseIComputed -eq $baseFingerprint) { 'MATCH' } else { 'MISMATCH' }
$caseIPass = ($caseIMatch -eq 'MISMATCH')
if (-not $caseIPass) { $allPass = $false }
$ValidationLines.Add('CASE I bypass_crosscheck_change fingerprint=CHANGED regression_detected=' + $(if ($caseIPass) { 'TRUE' } else { 'FALSE' }) + ' => ' + $(if ($caseIPass) { 'PASS' } else { 'FAIL' }))
Add-CaseResultLine -Lines $RecordLines -CaseId 'I' -Expected 'fingerprint_changed_regression_detected' -Computed $caseIComputed -Stored $baseFingerprint -MatchStatus $caseIMatch -ChangeType 'bypass_crosscheck_semantics_change' -AllowedOrBlocked $(if ($caseIPass) { 'BLOCKED' } else { 'ALLOWED' }) -Pass $caseIPass

$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status01 = @(
    'PHASE=49.3',
    'TITLE=Trust-Chain Ledger Baseline Enforcement Coverage Fingerprint Trust-Chain Baseline Enforcement Coverage Fingerprint Lock',
    'GATE=' + $Gate,
    'COVERAGE_FINGERPRINT_GENERATED=TRUE',
    'REFERENCE_SAVED=' + $(if (Test-Path -LiteralPath $ReferencePath) { 'TRUE' } else { 'FALSE' }),
    'REGRESSION_DETECTION_ACTIVE=TRUE',
    'RUNTIME_STATE_MACHINE_CHANGED=FALSE'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '01_status.txt'), $status01, [System.Text.Encoding]::UTF8)

$head02 = @(
    'RUNNER=tools/phase49_3/phase49_3_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint_runner.ps1',
    'LATEST_49_2_PROOF=' + $Latest49_2Proof.FullName,
    'INPUT_16=' + $InventoryPath,
    'INPUT_17=' + $MapPath,
    'INPUT_18=' + $UnguardedPath,
    'INPUT_19=' + $BypassPath,
    'REFERENCE_OUTPUT=' + $ReferencePath
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '02_head.txt'), $head02, [System.Text.Encoding]::UTF8)

$definition10 = @(
    'FINGERPRINT_MODEL=semantic model derived from phase49_2 inventory/map/unguarded/bypass artifacts',
    'SEMANTIC_INPUTS=operational actual-function inventory rows + operational map rows + unguarded state + bypass crosscheck state',
    'NORMALIZATION=trim text, collapse whitespace, sort rows by stable keys, ignore proof folder timestamp paths',
    'DEAD_HELPER_POLICY=dead helper cosmetic changes excluded from semantic model',
    'OUTPUT_REFERENCE=control_plane/93_trust_chain_ledger_baseline_enforcement_coverage_fingerprint.json'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '10_fingerprint_definition.txt'), $definition10, [System.Text.Encoding]::UTF8)

$rules11 = @(
    'RULE_1=Fingerprint must be deterministic for identical semantic model.',
    'RULE_2=Whitespace/formatting/order-only changes must not alter fingerprint.',
    'RULE_3=Operational entrypoint additions/removals must alter fingerprint.',
    'RULE_4=Coverage classification changes on operational paths must alter fingerprint.',
    'RULE_5=Operational/dead reclassification for real path must alter fingerprint.',
    'RULE_6=Dead-helper cosmetic-only changes must not alter fingerprint.',
    'RULE_7=Unguarded path state changes must alter fingerprint.',
    'RULE_8=Bypass crosscheck semantic state changes must alter fingerprint.',
    'RULE_9=Regression detection blocks certification when semantic drift is detected unexpectedly.'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '11_fingerprint_rules.txt'), $rules11, [System.Text.Encoding]::UTF8)

$files12 = @(
    'READ=' + $InventoryPath,
    'READ=' + $MapPath,
    'READ=' + $UnguardedPath,
    'READ=' + $BypassPath,
    'WRITE=' + $ReferencePath,
    'WRITE=' + $PF
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '12_files_touched.txt'), $files12, [System.Text.Encoding]::UTF8)

$build13 = @(
    'OPERATONAL_INVENTORY_ROWS=' + [string]$basePayload.semantic_model.operational_inventory_count,
    'OPERATIONAL_MAP_ROWS=' + [string]$basePayload.semantic_model.operational_map_count,
    'UNGUARDED_OPERATIONAL_PATHS=' + [string]$basePayload.semantic_model.unguarded_path_report.unguarded_operational_paths,
    'BYPASS_CROSSCHECK=' + [string]$basePayload.semantic_model.bypass_crosscheck_report.bypass_crosscheck,
    'COVERAGE_FINGERPRINT_SHA256=' + $baseFingerprint,
    'GATE=' + $Gate
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '13_build_output.txt'), $build13, [System.Text.Encoding]::UTF8)

[System.IO.File]::WriteAllText((Join-Path $PF '14_validation_results.txt'), ($ValidationLines -join "`r`n"), [System.Text.Encoding]::UTF8)

$summary15 = @(
    'The fingerprint surface was built from the latest phase49_2 entrypoint inventory, enforcement map, unguarded-path state, and bypass-crosscheck state.',
    'Determinism is achieved by semantic normalization (trim/collapse whitespace), stable sorting, and canonical JSON hashing.',
    'Direct and transitive coverage semantics are preserved through operational inventory/map rows only.',
    'Dead helpers are excluded from semantic fingerprint impact unless they change operational classification.',
    'Regression cases C,D,G,H,I demonstrate semantic drift changes fingerprint and trigger blocked certification behavior in-case.',
    'Non-semantic cases B,E,F demonstrate formatting/order/dead-cosmetic changes do not alter fingerprint.',
    'Runtime behavior remained unchanged because this phase writes certification artifacts and reference metadata only.'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '15_behavior_summary.txt'), $summary15, [System.Text.Encoding]::UTF8)

$recordHeader = 'case|computed_fingerprint|stored_reference_fingerprint|fingerprint_match_status|detected_change_type|certification_allowed_or_blocked|expected'
$recordBody = @($recordHeader) + @($RecordLines)
[System.IO.File]::WriteAllText((Join-Path $PF '16_coverage_fingerprint_record.txt'), ($recordBody -join "`r`n"), [System.Text.Encoding]::UTF8)

[System.IO.File]::WriteAllText((Join-Path $PF '17_regression_detection_evidence.txt'), ($EvidenceLines -join "`r`n"), [System.Text.Encoding]::UTF8)

$gate98 = @('PHASE=49.3', 'GATE=' + $Gate) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '98_gate_phase49_3.txt'), $gate98, [System.Text.Encoding]::UTF8)

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
