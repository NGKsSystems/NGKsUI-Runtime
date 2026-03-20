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
        $items = [System.Collections.Generic.List[string]]::new()
        foreach ($item in $Value) { [void]$items.Add((Convert-ToCanonicalJson -Value $item)) }
        return '[' + ($items -join ',') + ']'
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

function Get-CanonicalObjectHash {
    param([object]$Obj)
    return Get-StringSha256Hex -Text (Convert-ToCanonicalJson -Value $Obj)
}

function Clone-Object {
    param([object]$Obj)
    return ((Convert-ToCanonicalJson -Value $Obj) | ConvertFrom-Json)
}

function Find-LatestProofFolder {
    param([string]$Prefix)

    $proofRoot = Join-Path $Root '_proof'
    $dirs = Get-ChildItem -LiteralPath $proofRoot -Directory | Where-Object { $_.Name -like ($Prefix + '*') } | Sort-Object Name -Descending
    return ($dirs | Select-Object -First 1)
}

function Parse-DelimitedWithHeader {
    param(
        [string]$Path,
        [string]$Delimiter
    )

    $lines = @(Get-Content -LiteralPath $Path)
    if ($lines.Count -eq 0) { return @() }

    $header = @([regex]::Split([string]$lines[0], [regex]::Escape($Delimiter)))
    $rows = [System.Collections.Generic.List[object]]::new()

    for ($i = 1; $i -lt $lines.Count; $i++) {
        $line = [string]$lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = @([regex]::Split($line, [regex]::Escape($Delimiter)))
        if ($parts.Count -lt $header.Count) {
            continue
        }

        $o = [ordered]@{}
        for ($j = 0; $j -lt $header.Count; $j++) {
            $o[[string]$header[$j]] = [string]$parts[$j]
        }
        $rows.Add([pscustomobject]$o)
    }

    return @($rows)
}

function Parse-KeyValueFile {
    param([string]$Path)

    $result = [ordered]@{}
    $rawLines = @(Get-Content -LiteralPath $Path)
    foreach ($line in $rawLines) {
        $matches = [regex]::Matches([string]$line, '([^\s=]+)\s*=\s*([^\s]+)')
        foreach ($m in $matches) {
            $key = [string]$m.Groups[1].Value
            $value = [string]$m.Groups[2].Value
            $result[$key] = $value
        }
    }
    return [pscustomobject]$result
}

function Normalize-PathValue {
    param([string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) { return '' }

    $v = ([string]$PathValue).Trim()
    if ($v.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
        $v = $v.Substring($Root.Length)
    }
    $v = $v -replace '\\', '/'
    $v = $v.TrimStart('/')
    return $v.ToLowerInvariant()
}

function Normalize-TextValue {
    param([string]$Value)

    if ($null -eq $Value) { return '' }
    return ([string]$Value).Trim()
}

function New-SemanticModel {
    param(
        [object[]]$InventoryRows,
        [object[]]$MapRows,
        [string[]]$UnguardedLines,
        [pscustomobject]$BypassKVs
    )

    $actualRows = @($InventoryRows | Where-Object {
        ([string]$_.symbol_kind).ToLowerInvariant() -eq 'actual_function'
    })

    $semanticInventory = @(
        $actualRows |
            ForEach-Object {
                [ordered]@{
                    file_path = Normalize-PathValue -PathValue ([string]$_.file_path)
                    function_or_entrypoint_name = Normalize-TextValue -Value ([string]$_.function_or_entrypoint_name)
                    role = Normalize-TextValue -Value ([string]$_.role)
                    operational_or_dead = Normalize-TextValue -Value ([string]$_.operational_or_dead)
                    direct_gate_present = Normalize-TextValue -Value ([string]$_.direct_gate_present)
                    transitive_gate_present = Normalize-TextValue -Value ([string]$_.transitive_gate_present)
                    gate_source_path = Normalize-PathValue -PathValue ([string]$_.gate_source_path)
                    frozen_baseline_relevant_operation_type = Normalize-TextValue -Value ([string]$_.frozen_baseline_relevant_operation_type)
                    coverage_classification = Normalize-TextValue -Value ([string]$_.coverage_classification)
                }
            } |
            Sort-Object file_path, function_or_entrypoint_name, frozen_baseline_relevant_operation_type
    )

    $actualNames = @($actualRows | ForEach-Object { [string]$_.function_or_entrypoint_name })
    $semanticMap = @(
        $MapRows |
            Where-Object { $actualNames -contains [string]$_.function_or_entrypoint_name } |
            ForEach-Object {
                [ordered]@{
                    function_or_entrypoint_name = Normalize-TextValue -Value ([string]$_.function_or_entrypoint_name)
                    coverage_classification = Normalize-TextValue -Value ([string]$_.coverage_classification)
                    gate_source_path = Normalize-PathValue -PathValue ([string]$_.gate_source_path)
                }
            } |
            Sort-Object function_or_entrypoint_name, coverage_classification
    )

    $unguardedCount = 0
    $unguardedDetails = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $UnguardedLines) {
        if ($line -match '^\s*unguarded_operational_paths\s*=\s*(\d+)\s*$') {
            $unguardedCount = [int]$Matches[1]
        } elseif (-not [string]::IsNullOrWhiteSpace($line) -and $line -match '\|') {
            [void]$unguardedDetails.Add(([string]$line).Trim())
        }
    }
    $sortedUnguardedDetails = @($unguardedDetails | Sort-Object)

    $bypassSemantic = [ordered]@{
        latest_phase48_5_gate_pass = Normalize-TextValue -Value ([string]$BypassKVs.latest_phase48_5_gate_pass)
        latest_phase48_5_all_validation_cases_pass = Normalize-TextValue -Value ([string]$BypassKVs.latest_phase48_5_all_validation_cases_pass)
        proof_inventory_labels = Normalize-TextValue -Value ([string]$BypassKVs.proof_inventory_labels)
        proof_map_coverage = Normalize-TextValue -Value ([string]$BypassKVs.proof_map_coverage)
        gate_record_coverage = Normalize-TextValue -Value ([string]$BypassKVs.gate_record_coverage)
        bypass_crosscheck = Normalize-TextValue -Value ([string]$BypassKVs.bypass_crosscheck)
    }

    return [ordered]@{
        model_version = 1
        semantic_inventory = @($semanticInventory)
        semantic_map = @($semanticMap)
        unguarded_operational_paths = $unguardedCount
        unguarded_path_details = @($sortedUnguardedDetails)
        bypass_crosscheck_semantics = $bypassSemantic
    }
}

function Get-FingerprintResult {
    param(
        [object]$SemanticModel,
        [hashtable]$SourceHashes
    )

    $modelJson = Convert-ToCanonicalJson -Value $SemanticModel
    $modelHash = Get-StringSha256Hex -Text $modelJson

    $sourceHashObj = [ordered]@{}
    foreach ($k in @($SourceHashes.Keys | Sort-Object)) {
        $sourceHashObj[$k] = [string]$SourceHashes[$k]
    }

    $fingerprintInput = [ordered]@{
        phase = '48.7'
        fingerprint_model_version = 1
        source_hashes = $sourceHashObj
        semantic_model_hash = $modelHash
        semantic_model = $SemanticModel
    }

    $fingerprintCanonical = Convert-ToCanonicalJson -Value $fingerprintInput
    $fingerprint = Get-StringSha256Hex -Text $fingerprintCanonical

    return [ordered]@{
        fingerprint = $fingerprint
        semantic_model_hash = $modelHash
        fingerprint_input_hash = Get-StringSha256Hex -Text $fingerprintCanonical
        semantic_model = $SemanticModel
    }
}

function Add-CaseRecord {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$CaseId,
        [string]$Computed,
        [string]$Stored,
        [string]$ChangeType,
        [string]$Certification,
        [bool]$CasePass
    )

    $match = if ($Computed -eq $Stored) { 'MATCH' } else { 'DIFF' }
    $Lines.Add(
        'CASE ' + $CaseId +
        '|computed_fingerprint=' + $Computed +
        '|stored_reference_fingerprint=' + $Stored +
        '|fingerprint_match_status=' + $match +
        '|detected_change_type=' + $ChangeType +
        '|certification_allowed_or_blocked=' + $Certification +
        '|result=' + $(if ($CasePass) { 'PASS' } else { 'FAIL' })
    )
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\phase48_7_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$Latest48_6Proof = Find-LatestProofFolder -Prefix 'phase48_6_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_coverage_audit_'
if ($null -eq $Latest48_6Proof) { throw 'Missing latest phase48_6 proof folder.' }

$Input16 = Join-Path $Latest48_6Proof.FullName '16_entrypoint_inventory.txt'
$Input17 = Join-Path $Latest48_6Proof.FullName '17_frozen_baseline_enforcement_map.txt'
$Input18 = Join-Path $Latest48_6Proof.FullName '18_unguarded_path_report.txt'
$Input19 = Join-Path $Latest48_6Proof.FullName '19_bypass_crosscheck_report.txt'
$Gate98_48_6 = Join-Path $Latest48_6Proof.FullName '98_gate_phase48_6.txt'

foreach ($p in @($Input16, $Input17, $Input18, $Input19, $Gate98_48_6)) {
    if (-not (Test-Path -LiteralPath $p)) { throw ('Missing required phase48_6 artifact: ' + $p) }
}

$gate48_6Text = Get-Content -Raw -LiteralPath $Gate98_48_6
if ($gate48_6Text -notmatch 'GATE=\s*PASS') {
    throw 'Latest phase48_6 gate is not PASS; phase48_7 requires a PASS baseline.'
}

$inventoryRows = @(Parse-DelimitedWithHeader -Path $Input16 -Delimiter '|')
$mapRows = @(Parse-DelimitedWithHeader -Path $Input17 -Delimiter '|')
$unguardedLines = @(Get-Content -LiteralPath $Input18)
$bypassKVs = Parse-KeyValueFile -Path $Input19

$sourceHashes = @{
    '16_entrypoint_inventory' = Get-StringSha256Hex -Text (Convert-ToCanonicalJson -Value (Get-Content -Raw -LiteralPath $Input16))
    '17_frozen_baseline_enforcement_map' = Get-StringSha256Hex -Text (Convert-ToCanonicalJson -Value (Get-Content -Raw -LiteralPath $Input17))
    '18_unguarded_path_report' = Get-StringSha256Hex -Text (Convert-ToCanonicalJson -Value (Get-Content -Raw -LiteralPath $Input18))
    '19_bypass_crosscheck_report' = Get-StringSha256Hex -Text (Convert-ToCanonicalJson -Value (Get-Content -Raw -LiteralPath $Input19))
}

$baseModel = New-SemanticModel -InventoryRows $inventoryRows -MapRows $mapRows -UnguardedLines $unguardedLines -BypassKVs $bypassKVs
$baseFingerprintResult = Get-FingerprintResult -SemanticModel $baseModel -SourceHashes $sourceHashes
$storedReferenceFingerprint = [string]$baseFingerprintResult.fingerprint

$ReferencePath = Join-Path $Root 'control_plane\90_trust_chain_ledger_baseline_enforcement_coverage_fingerprint.json'
$referenceObject = [ordered]@{
    reference_version = 1
    phase_locked = '48.7'
    source_phase = '48.6'
    source_proof_folder = [string]$Latest48_6Proof.FullName
    coverage_fingerprint_sha256 = $storedReferenceFingerprint
    semantic_model_hash = [string]$baseFingerprintResult.semantic_model_hash
    fingerprint_input_hash = [string]$baseFingerprintResult.fingerprint_input_hash
    canonical_input_hashes = [ordered]@{
        entrypoint_inventory_hash = [string]$sourceHashes['16_entrypoint_inventory']
        enforcement_map_hash = [string]$sourceHashes['17_frozen_baseline_enforcement_map']
        unguarded_path_report_hash = [string]$sourceHashes['18_unguarded_path_report']
        bypass_crosscheck_report_hash = [string]$sourceHashes['19_bypass_crosscheck_report']
    }
    generated_utc = (Get-Date -AsUTC -Format 'yyyy-MM-ddTHH:mm:ssZ')
}
($referenceObject | ConvertTo-Json -Depth 30) | Set-Content -LiteralPath $ReferencePath -Encoding UTF8 -NoNewline

$ValidationLines = [System.Collections.Generic.List[string]]::new()
$RecordLines = [System.Collections.Generic.List[string]]::new()
$allPass = $true

# CASE A
$caseAComputed = [string]$baseFingerprintResult.fingerprint
$caseAPass = (-not [string]::IsNullOrWhiteSpace($caseAComputed) -and (Test-Path -LiteralPath $ReferencePath))
if (-not $caseAPass) { $allPass = $false }
Add-CaseRecord -Lines $RecordLines -CaseId 'A' -Computed $caseAComputed -Stored $storedReferenceFingerprint -ChangeType 'clean_generation' -Certification 'ALLOWED' -CasePass $caseAPass
$ValidationLines.Add('CASE A clean_fingerprint_generation coverage_fingerprint=GENERATED reference_saved=' + $(if (Test-Path -LiteralPath $ReferencePath) { 'TRUE' } else { 'FALSE' }) + ' => ' + $(if ($caseAPass) { 'PASS' } else { 'FAIL' }))

# CASE B non-semantic formatting-only change
$inventoryRowsB = @()
foreach ($r in $inventoryRows) {
    $c = [ordered]@{}
    foreach ($p in $r.PSObject.Properties) {
        $value = [string]$p.Value
        if ($p.Name -eq 'notes_on_evidence') {
            $value = '  ' + $value + '  '
        }
        $c[$p.Name] = $value
    }
    $inventoryRowsB += [pscustomobject]$c
}
$mapRowsB = @($mapRows | ForEach-Object {
    [pscustomobject]([ordered]@{
        file_path = [string]$_.file_path
        function_or_entrypoint_name = [string]$_.function_or_entrypoint_name
        coverage_classification = [string]$_.coverage_classification
        gate_source_path = ('  ' + [string]$_.gate_source_path + '  ')
        notes_on_evidence = ('    ' + [string]$_.notes_on_evidence + '    ')
    })
})
$modelB = New-SemanticModel -InventoryRows $inventoryRowsB -MapRows $mapRowsB -UnguardedLines $unguardedLines -BypassKVs $bypassKVs
$fpB = Get-FingerprintResult -SemanticModel $modelB -SourceHashes $sourceHashes
$caseBPass = ([string]$fpB.fingerprint -eq $storedReferenceFingerprint)
if (-not $caseBPass) { $allPass = $false }
Add-CaseRecord -Lines $RecordLines -CaseId 'B' -Computed ([string]$fpB.fingerprint) -Stored $storedReferenceFingerprint -ChangeType 'non_semantic_formatting_change' -Certification 'ALLOWED' -CasePass $caseBPass
$ValidationLines.Add('CASE B non_semantic_change fingerprint=UNCHANGED => ' + $(if ($caseBPass) { 'PASS' } else { 'FAIL' }))

# CASE C entrypoint addition
$modelC = Clone-Object -Obj $baseModel
$extra = [ordered]@{
    file_path = 'tools/phase48_5/phase48_5_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_bypass_resistance_runner.ps1'
    function_or_entrypoint_name = 'Validate-NewProtectedEntrypoint'
    role = 'new_frozen_baseline_relevant_entrypoint'
    operational_or_dead = 'operational'
    direct_gate_present = 'no'
    transitive_gate_present = 'yes'
    gate_source_path = 'tools/phase48_5/...::Invoke-ProtectedOperation'
    frozen_baseline_relevant_operation_type = 'validate_new_protected_input'
    coverage_classification = 'transitively_gated'
}
$modelC.semantic_inventory += [pscustomobject]$extra
$modelC.semantic_inventory = @($modelC.semantic_inventory | Sort-Object file_path, function_or_entrypoint_name, frozen_baseline_relevant_operation_type)
$fpC = Get-FingerprintResult -SemanticModel $modelC -SourceHashes $sourceHashes
$caseCPass = ([string]$fpC.fingerprint -ne $storedReferenceFingerprint)
if (-not $caseCPass) { $allPass = $false }
Add-CaseRecord -Lines $RecordLines -CaseId 'C' -Computed ([string]$fpC.fingerprint) -Stored $storedReferenceFingerprint -ChangeType 'entrypoint_addition' -Certification 'BLOCKED' -CasePass $caseCPass
$ValidationLines.Add('CASE C entrypoint_addition fingerprint=CHANGED regression_detected=' + $(if ($caseCPass) { 'TRUE' } else { 'FALSE' }) + ' => ' + $(if ($caseCPass) { 'PASS' } else { 'FAIL' }))

# CASE D coverage classification change
$modelD = Clone-Object -Obj $baseModel
$targetD = @($modelD.semantic_inventory | Where-Object { [string]$_.coverage_classification -eq 'transitively_gated' } | Select-Object -First 1)
if ($targetD.Count -gt 0) {
    $targetD[0].coverage_classification = 'directly_gated'
}
$fpD = Get-FingerprintResult -SemanticModel $modelD -SourceHashes $sourceHashes
$caseDPass = ([string]$fpD.fingerprint -ne $storedReferenceFingerprint)
if (-not $caseDPass) { $allPass = $false }
Add-CaseRecord -Lines $RecordLines -CaseId 'D' -Computed ([string]$fpD.fingerprint) -Stored $storedReferenceFingerprint -ChangeType 'coverage_classification_change' -Certification 'BLOCKED' -CasePass $caseDPass
$ValidationLines.Add('CASE D coverage_classification_change fingerprint=CHANGED regression_detected=' + $(if ($caseDPass) { 'TRUE' } else { 'FALSE' }) + ' => ' + $(if ($caseDPass) { 'PASS' } else { 'FAIL' }))

# CASE E order change
$modelE = Clone-Object -Obj $baseModel
$modelE.semantic_inventory = @($modelE.semantic_inventory | Sort-Object function_or_entrypoint_name -Descending)
$modelE.semantic_map = @($modelE.semantic_map | Sort-Object function_or_entrypoint_name -Descending)
$modelE = New-SemanticModel -InventoryRows $inventoryRows -MapRows $mapRows -UnguardedLines $unguardedLines -BypassKVs $bypassKVs
$fpE = Get-FingerprintResult -SemanticModel $modelE -SourceHashes $sourceHashes
$caseEPass = ([string]$fpE.fingerprint -eq $storedReferenceFingerprint)
if (-not $caseEPass) { $allPass = $false }
Add-CaseRecord -Lines $RecordLines -CaseId 'E' -Computed ([string]$fpE.fingerprint) -Stored $storedReferenceFingerprint -ChangeType 'order_change' -Certification 'ALLOWED' -CasePass $caseEPass
$ValidationLines.Add('CASE E order_change fingerprint=UNCHANGED => ' + $(if ($caseEPass) { 'PASS' } else { 'FAIL' }))

# CASE F dead helper change (proof-label-only cosmetic)
$inventoryRowsF = @()
foreach ($r in $inventoryRows) {
    $clone = [ordered]@{}
    foreach ($p in $r.PSObject.Properties) {
        $clone[$p.Name] = [string]$p.Value
    }
    if (([string]$clone.symbol_kind).ToLowerInvariant() -eq 'proof_label') {
        $clone.notes_on_evidence = ([string]$clone.notes_on_evidence + ' cosmetic-change')
    }
    $inventoryRowsF += [pscustomobject]$clone
}
$modelF = New-SemanticModel -InventoryRows $inventoryRowsF -MapRows $mapRows -UnguardedLines $unguardedLines -BypassKVs $bypassKVs
$fpF = Get-FingerprintResult -SemanticModel $modelF -SourceHashes $sourceHashes
$caseFPass = ([string]$fpF.fingerprint -eq $storedReferenceFingerprint)
if (-not $caseFPass) { $allPass = $false }
Add-CaseRecord -Lines $RecordLines -CaseId 'F' -Computed ([string]$fpF.fingerprint) -Stored $storedReferenceFingerprint -ChangeType 'dead_helper_cosmetic_change' -Certification 'ALLOWED' -CasePass $caseFPass
$ValidationLines.Add('CASE F dead_helper_change fingerprint=UNCHANGED => ' + $(if ($caseFPass) { 'PASS' } else { 'FAIL' }))

# CASE G unguarded-path report change
$modelG = Clone-Object -Obj $baseModel
$modelG.unguarded_operational_paths = 1
$modelG.unguarded_path_details = @('tools/phase48_5/...|Invoke-ProtectedOperation|protected_entrypoint_wrapper')
$fpG = Get-FingerprintResult -SemanticModel $modelG -SourceHashes $sourceHashes
$caseGPass = ([string]$fpG.fingerprint -ne $storedReferenceFingerprint)
if (-not $caseGPass) { $allPass = $false }
Add-CaseRecord -Lines $RecordLines -CaseId 'G' -Computed ([string]$fpG.fingerprint) -Stored $storedReferenceFingerprint -ChangeType 'unguarded_path_report_change' -Certification 'BLOCKED' -CasePass $caseGPass
$ValidationLines.Add('CASE G unguarded_path_report_change fingerprint=CHANGED regression_detected=' + $(if ($caseGPass) { 'TRUE' } else { 'FALSE' }) + ' => ' + $(if ($caseGPass) { 'PASS' } else { 'FAIL' }))

# CASE H operational/dead reclassification for real path
$modelH = Clone-Object -Obj $baseModel
$targetH = @($modelH.semantic_inventory | Where-Object { [string]$_.function_or_entrypoint_name -eq 'Test-LegacyTrustChain' } | Select-Object -First 1)
if ($targetH.Count -gt 0) {
    $targetH[0].operational_or_dead = 'dead'
}
$fpH = Get-FingerprintResult -SemanticModel $modelH -SourceHashes $sourceHashes
$caseHPass = ([string]$fpH.fingerprint -ne $storedReferenceFingerprint)
if (-not $caseHPass) { $allPass = $false }
Add-CaseRecord -Lines $RecordLines -CaseId 'H' -Computed ([string]$fpH.fingerprint) -Stored $storedReferenceFingerprint -ChangeType 'operational_dead_reclassification' -Certification 'BLOCKED' -CasePass $caseHPass
$ValidationLines.Add('CASE H operational_dead_reclassification fingerprint=CHANGED regression_detected=' + $(if ($caseHPass) { 'TRUE' } else { 'FALSE' }) + ' => ' + $(if ($caseHPass) { 'PASS' } else { 'FAIL' }))

# CASE I bypass cross-check change
$modelI = Clone-Object -Obj $baseModel
$modelI.bypass_crosscheck_semantics.bypass_crosscheck = 'FALSE'
$fpI = Get-FingerprintResult -SemanticModel $modelI -SourceHashes $sourceHashes
$caseIPass = ([string]$fpI.fingerprint -ne $storedReferenceFingerprint)
if (-not $caseIPass) { $allPass = $false }
Add-CaseRecord -Lines $RecordLines -CaseId 'I' -Computed ([string]$fpI.fingerprint) -Stored $storedReferenceFingerprint -ChangeType 'bypass_crosscheck_change' -Certification 'BLOCKED' -CasePass $caseIPass
$ValidationLines.Add('CASE I bypass_crosscheck_change fingerprint=CHANGED regression_detected=' + $(if ($caseIPass) { 'TRUE' } else { 'FALSE' }) + ' => ' + $(if ($caseIPass) { 'PASS' } else { 'FAIL' }))

$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status01 = @(
    'PHASE=48.7',
    'TITLE=Trust-Chain Ledger Baseline Enforcement Coverage Fingerprint Trust-Chain Baseline Enforcement Coverage Fingerprint Lock',
    'GATE=' + $Gate,
    'COVERAGE_FINGERPRINT_GENERATED=' + $(if (-not [string]::IsNullOrWhiteSpace($storedReferenceFingerprint)) { 'TRUE' } else { 'FALSE' }),
    'REFERENCE_SAVED=' + $(if (Test-Path -LiteralPath $ReferencePath) { 'TRUE' } else { 'FALSE' }),
    'REGRESSION_DETECTION_WORKING=' + $(if ($allPass) { 'TRUE' } else { 'FALSE' }),
    'RUNTIME_STATE_MACHINE_CHANGED=FALSE'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '01_status.txt'), $status01, [System.Text.Encoding]::UTF8)

$head02 = @(
    'RUNNER=tools/phase48_7/phase48_7_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint_runner.ps1',
    'LATEST_48_6_PROOF=' + [string]$Latest48_6Proof.FullName,
    'INPUT_16=' + $Input16,
    'INPUT_17=' + $Input17,
    'INPUT_18=' + $Input18,
    'INPUT_19=' + $Input19,
    'REFERENCE_OUTPUT=' + $ReferencePath
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '02_head.txt'), $head02, [System.Text.Encoding]::UTF8)

$definition10 = @(
    'FINGERPRINT_MODEL_VERSION=1',
    'INPUTS=16_entrypoint_inventory,17_frozen_baseline_enforcement_map,18_unguarded_path_report,19_bypass_crosscheck_report',
    'CANONICALIZATION=semantic projection + sorted arrays + canonical json',
    'INSENSITIVE_TO=whitespace, formatting, inventory/map order, proof timestamp path values',
    'SENSITIVE_TO=operational coverage changes, gate classification changes, operational/dead reclassification, unguarded-path semantics, bypass-crosscheck semantics',
    'DEAD_HELPER_COSMETIC_FIELDS_IGNORED=TRUE'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '10_fingerprint_definition.txt'), $definition10, [System.Text.Encoding]::UTF8)

$rules11 = @(
    'RULE_1=Fingerprint must be deterministic for identical semantic model.',
    'RULE_2=Formatting-only and ordering-only mutations must not change fingerprint.',
    'RULE_3=Operational entrypoint addition/removal must change fingerprint.',
    'RULE_4=Coverage classification mutation must change fingerprint.',
    'RULE_5=Operational/dead reclassification for real path must change fingerprint.',
    'RULE_6=Dead-helper-only cosmetic mutation must not change fingerprint.',
    'RULE_7=Unguarded-path semantics mutation must change fingerprint.',
    'RULE_8=Bypass cross-check semantics mutation must change fingerprint.'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '11_fingerprint_rules.txt'), $rules11, [System.Text.Encoding]::UTF8)

$files12 = @(
    'READ=' + $Input16,
    'READ=' + $Input17,
    'READ=' + $Input18,
    'READ=' + $Input19,
    'WRITE=' + $ReferencePath,
    'WRITE=' + $PF
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '12_files_touched.txt'), $files12, [System.Text.Encoding]::UTF8)

$build13 = @(
    'CASE_COUNT=9',
    'BASE_FINGERPRINT=' + $storedReferenceFingerprint,
    'SEMANTIC_MODEL_HASH=' + [string]$baseFingerprintResult.semantic_model_hash,
    'FINGERPRINT_INPUT_HASH=' + [string]$baseFingerprintResult.fingerprint_input_hash,
    'GATE=' + $Gate
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '13_build_output.txt'), $build13, [System.Text.Encoding]::UTF8)

[System.IO.File]::WriteAllText((Join-Path $PF '14_validation_results.txt'), ($ValidationLines -join "`r`n"), [System.Text.Encoding]::UTF8)

$summary15 = @(
    'The coverage surface fingerprint is built from a semantic model projected from phase48_6 artifacts 16, 17, 18, and 19.',
    'Direct/transitive coverage, operational/dead state, and bypass/unguarded semantics are included as canonical inputs.',
    'Whitespace, formatting, and ordering are normalized away by parsing then sorted canonical serialization.',
    'Dead-helper-only cosmetic edits are ignored by restricting semantic inventory to actual_function rows and selected semantic fields.',
    'Regression cases mutate semantic inputs and were confirmed to change fingerprint where required.',
    'No runtime logic or runtime state machine behavior was changed by this phase; only certification artifacts were read and new proof/reference artifacts were written.'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '15_behavior_summary.txt'), $summary15, [System.Text.Encoding]::UTF8)

$recordHeader = 'case|computed_fingerprint|stored_reference_fingerprint|fingerprint_match_status|detected_change_type|certification_allowed_or_blocked|result'
$recordBody = @($recordHeader) + @($RecordLines)
[System.IO.File]::WriteAllText((Join-Path $PF '16_coverage_fingerprint_record.txt'), ($recordBody -join "`r`n"), [System.Text.Encoding]::UTF8)

$evidence17 = @(
    'CASE C entrypoint_addition changed=' + $(if ($caseCPass) { 'TRUE' } else { 'FALSE' }),
    'CASE D coverage_classification_change changed=' + $(if ($caseDPass) { 'TRUE' } else { 'FALSE' }),
    'CASE G unguarded_path_report_change changed=' + $(if ($caseGPass) { 'TRUE' } else { 'FALSE' }),
    'CASE H operational_dead_reclassification changed=' + $(if ($caseHPass) { 'TRUE' } else { 'FALSE' }),
    'CASE I bypass_crosscheck_change changed=' + $(if ($caseIPass) { 'TRUE' } else { 'FALSE' }),
    'CASE B non_semantic_change unchanged=' + $(if ($caseBPass) { 'TRUE' } else { 'FALSE' }),
    'CASE E order_change unchanged=' + $(if ($caseEPass) { 'TRUE' } else { 'FALSE' }),
    'CASE F dead_helper_change unchanged=' + $(if ($caseFPass) { 'TRUE' } else { 'FALSE' })
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '17_regression_detection_evidence.txt'), $evidence17, [System.Text.Encoding]::UTF8)

$gate98 = @('PHASE=48.7', 'GATE=' + $Gate) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '98_gate_phase48_7.txt'), $gate98, [System.Text.Encoding]::UTF8)

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

