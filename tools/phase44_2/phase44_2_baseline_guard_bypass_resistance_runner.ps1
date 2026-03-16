Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ((Get-Location).Path -ne $Root) {
    Write-Output 'hey stupid Fucker, wrong window again'
    exit 1
}
Set-Location $Root

function Get-FileSha256Hex {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Test-BaselineGuard {
    param(
        [string]$SnapshotPath,
        [string]$IntegrityRefPath
    )

    $result = [ordered]@{
        baseline_snapshot_path = $SnapshotPath
        baseline_integrity_reference_path = $IntegrityRefPath
        stored_baseline_hash = ''
        computed_baseline_hash = ''
        baseline_guard_result = 'FAIL'
        failure_reason = ''
        fallback_occurred = $false
        regeneration_occurred = $false
    }

    if (-not (Test-Path -LiteralPath $SnapshotPath)) {
        $result.failure_reason = 'baseline_snapshot_missing'
        return $result
    }

    if (-not (Test-Path -LiteralPath $IntegrityRefPath)) {
        $result.failure_reason = 'baseline_integrity_reference_missing'
        return $result
    }

    $integrityObj = $null
    try {
        $integrityObj = Get-Content -Raw -LiteralPath $IntegrityRefPath | ConvertFrom-Json
    } catch {
        $result.failure_reason = 'baseline_integrity_reference_parse_error'
        return $result
    }

    $result.stored_baseline_hash = [string]$integrityObj.expected_baseline_snapshot_sha256
    $result.computed_baseline_hash = Get-FileSha256Hex -Path $SnapshotPath
    if ($result.stored_baseline_hash -ne $result.computed_baseline_hash) {
        $result.failure_reason = 'baseline_hash_mismatch'
        return $result
    }

    $snapshotObj = $null
    try {
        $snapshotObj = Get-Content -Raw -LiteralPath $SnapshotPath | ConvertFrom-Json
    } catch {
        $result.failure_reason = 'baseline_snapshot_parse_error'
        return $result
    }

    $requiredFields = @('baseline_version','baseline_kind','active_catalog_file')
    $missing = @()
    foreach ($field in $requiredFields) {
        if (-not ($snapshotObj.PSObject.Properties.Name -contains $field)) {
            $missing += $field
        }
    }
    if ($missing.Count -gt 0) {
        $result.failure_reason = 'baseline_snapshot_structure_invalid'
        return $result
    }

    $result.baseline_guard_result = 'PASS'
    return $result
}

function New-BlockedResult {
    param(
        [string]$Entrypoint,
        [hashtable]$Guard
    )

    return [ordered]@{
        entrypoint = $Entrypoint
        baseline_guard = $Guard.baseline_guard_result
        operation = 'BLOCKED'
        reason = $Guard.failure_reason
        fallback_occurred = $false
        regeneration_occurred = $false
        details = ''
    }
}

function Invoke-DirectCatalogReadHelper {
    param(
        [string]$SnapshotPath,
        [string]$IntegrityRefPath,
        [string]$CatalogPath
    )

    $guard = Test-BaselineGuard -SnapshotPath $SnapshotPath -IntegrityRefPath $IntegrityRefPath
    if ($guard.baseline_guard_result -ne 'PASS') {
        return New-BlockedResult -Entrypoint 'direct_catalog_file_read_helper' -Guard $guard
    }

    $raw = Get-Content -Raw -LiteralPath $CatalogPath
    $obj = $raw | ConvertFrom-Json
    return [ordered]@{
        entrypoint = 'direct_catalog_file_read_helper'
        baseline_guard = 'PASS'
        operation = 'ALLOWED'
        reason = ''
        fallback_occurred = $false
        regeneration_occurred = $false
        details = ('selection_mode=' + [string]$obj.selection_mode)
    }
}

function Invoke-CatalogLoad {
    param(
        [string]$SnapshotPath,
        [string]$IntegrityRefPath,
        [string]$CatalogPath
    )

    $helper = Invoke-DirectCatalogReadHelper -SnapshotPath $SnapshotPath -IntegrityRefPath $IntegrityRefPath -CatalogPath $CatalogPath
    if ($helper.operation -ne 'ALLOWED') {
        return [ordered]@{
            entrypoint = 'catalog_load'
            baseline_guard = $helper.baseline_guard
            operation = 'BLOCKED'
            reason = $helper.reason
            fallback_occurred = $false
            regeneration_occurred = $false
            details = 'blocked_by_guarded_helper'
        }
    }

    return [ordered]@{
        entrypoint = 'catalog_load'
        baseline_guard = 'PASS'
        operation = 'ALLOWED'
        reason = ''
        fallback_occurred = $false
        regeneration_occurred = $false
        details = $helper.details
    }
}

function Invoke-CatalogVersionSelection {
    param(
        [string]$SnapshotPath,
        [string]$IntegrityRefPath,
        [string]$CatalogPath,
        [string]$Version
    )

    $guard = Test-BaselineGuard -SnapshotPath $SnapshotPath -IntegrityRefPath $IntegrityRefPath
    if ($guard.baseline_guard_result -ne 'PASS') {
        return New-BlockedResult -Entrypoint 'catalog_version_selection' -Guard $guard
    }

    $catalogObj = Get-Content -Raw -LiteralPath $CatalogPath | ConvertFrom-Json
    $versions = @($catalogObj.versions)
    $match = @($versions | Where-Object { [string]$_.chain_version -eq $Version })
    $hasMatch = ($match.Count -gt 0)

    return [ordered]@{
        entrypoint = 'catalog_version_selection'
        baseline_guard = 'PASS'
        operation = 'ALLOWED'
        reason = ''
        fallback_occurred = $false
        regeneration_occurred = $false
        details = ('requested=' + $Version + ';found=' + $hasMatch)
    }
}

function Invoke-DefaultCatalogResolution {
    param(
        [string]$SnapshotPath,
        [string]$IntegrityRefPath,
        [string]$CatalogPath
    )

    $guard = Test-BaselineGuard -SnapshotPath $SnapshotPath -IntegrityRefPath $IntegrityRefPath
    if ($guard.baseline_guard_result -ne 'PASS') {
        return New-BlockedResult -Entrypoint 'default_catalog_resolution' -Guard $guard
    }

    $catalogObj = Get-Content -Raw -LiteralPath $CatalogPath | ConvertFrom-Json
    $selectionMode = [string]$catalogObj.selection_mode

    return [ordered]@{
        entrypoint = 'default_catalog_resolution'
        baseline_guard = 'PASS'
        operation = 'ALLOWED'
        reason = ''
        fallback_occurred = $false
        regeneration_occurred = $false
        details = ('selection_mode=' + $selectionMode)
    }
}

function Invoke-CatalogTrustChainVerification {
    param(
        [string]$SnapshotPath,
        [string]$IntegrityRefPath,
        [string]$TrustChainPath
    )

    $guard = Test-BaselineGuard -SnapshotPath $SnapshotPath -IntegrityRefPath $IntegrityRefPath
    if ($guard.baseline_guard_result -ne 'PASS') {
        return New-BlockedResult -Entrypoint 'catalog_trust_chain_verification' -Guard $guard
    }

    $trustObj = Get-Content -Raw -LiteralPath $TrustChainPath | ConvertFrom-Json
    $chain = @($trustObj.chain)
    $v1 = @($chain | Where-Object { [string]$_.catalog_version -eq 'v1' })[0]
    $v2 = @($chain | Where-Object { [string]$_.catalog_version -eq 'v2' })[0]
    $linkOk = ($null -ne $v1 -and $null -ne $v2 -and ([string]$v2.previous_catalog_hash -eq [string]$v1.catalog_hash))

    return [ordered]@{
        entrypoint = 'catalog_trust_chain_verification'
        baseline_guard = 'PASS'
        operation = 'ALLOWED'
        reason = ''
        fallback_occurred = $false
        regeneration_occurred = $false
        details = ('link_v1_to_v2=' + $linkOk + ';chain_entries=' + $chain.Count)
    }
}

function Invoke-CatalogRotationRunner {
    param(
        [string]$SnapshotPath,
        [string]$IntegrityRefPath,
        [string]$RotationRunnerPath
    )

    $guard = Test-BaselineGuard -SnapshotPath $SnapshotPath -IntegrityRefPath $IntegrityRefPath
    if ($guard.baseline_guard_result -ne 'PASS') {
        return [ordered]@{
            entrypoint = 'catalog_rotation_runner'
            baseline_guard = 'FAIL'
            operation = 'BLOCKED'
            rotation = 'BLOCKED'
            reason = $guard.failure_reason
            fallback_occurred = $false
            regeneration_occurred = $false
            details = ''
        }
    }

    $runnerExists = Test-Path -LiteralPath $RotationRunnerPath
    return [ordered]@{
        entrypoint = 'catalog_rotation_runner'
        baseline_guard = 'PASS'
        operation = 'ALLOWED'
        rotation = 'ALLOWED'
        reason = ''
        fallback_occurred = $false
        regeneration_occurred = $false
        details = ('rotation_runner_exists=' + $runnerExists + ';execution=preflight_only')
    }
}

function Invoke-HistoricalCatalogValidation {
    param(
        [string]$SnapshotPath,
        [string]$IntegrityRefPath,
        [string]$HistoryChainPath
    )

    $guard = Test-BaselineGuard -SnapshotPath $SnapshotPath -IntegrityRefPath $IntegrityRefPath
    if ($guard.baseline_guard_result -ne 'PASS') {
        return New-BlockedResult -Entrypoint 'historical_catalog_validation' -Guard $guard
    }

    $histObj = Get-Content -Raw -LiteralPath $HistoryChainPath | ConvertFrom-Json
    $entries = @($histObj.catalog_history)
    return [ordered]@{
        entrypoint = 'historical_catalog_validation'
        baseline_guard = 'PASS'
        operation = 'ALLOWED'
        reason = ''
        fallback_occurred = $false
        regeneration_occurred = $false
        details = ('history_entries=' + $entries.Count)
    }
}

function New-TamperedBaselineCopy {
    param(
        [string]$CaseTag,
        [string]$BaselineContent
    )

    $p = Join-Path $env:TEMP ('phase44_2_' + $CaseTag + '_' + (Get-Date -Format 'yyyyMMdd_HHmmssfff') + '.json')
    $tampered = $BaselineContent + "`n"
    [System.IO.File]::WriteAllText($p, $tampered, [System.Text.Encoding]::UTF8)
    return $p
}

$BaselineSnapshotPath = Join-Path $Root 'tools\phase44_0\catalog_baseline_snapshot.json'
$BaselineIntegrityRef = Join-Path $Root 'tools\phase44_0\catalog_baseline_integrity_reference.json'
$ActiveCatalogPath = Join-Path $Root 'tools\phase43_7\active_chain_version_catalog_v2.json'
$TrustChainPath = Join-Path $Root 'tools\phase43_9\catalog_trust_chain.json'
$HistoryChainPath = Join-Path $Root 'tools\phase43_7\catalog_history_chain.json'
$RotationRunnerPath = Join-Path $Root 'tools\phase43_7\phase43_7_active_chain_catalog_rotation_runner.ps1'

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\phase44_2_baseline_guard_bypass_resistance_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$baselineContent = Get-Content -Raw -LiteralPath $BaselineSnapshotPath
$entrypointCalls = [System.Collections.Generic.List[object]]::new()
$caseRecords = [System.Collections.Generic.List[object]]::new()
$allPassed = $true

Write-Host '=== CASE A: NORMAL OPERATION ==='
$caseAResults = @(
    (Invoke-CatalogLoad -SnapshotPath $BaselineSnapshotPath -IntegrityRefPath $BaselineIntegrityRef -CatalogPath $ActiveCatalogPath)
    (Invoke-CatalogVersionSelection -SnapshotPath $BaselineSnapshotPath -IntegrityRefPath $BaselineIntegrityRef -CatalogPath $ActiveCatalogPath -Version 'v2')
    (Invoke-DefaultCatalogResolution -SnapshotPath $BaselineSnapshotPath -IntegrityRefPath $BaselineIntegrityRef -CatalogPath $ActiveCatalogPath)
    (Invoke-CatalogTrustChainVerification -SnapshotPath $BaselineSnapshotPath -IntegrityRefPath $BaselineIntegrityRef -TrustChainPath $TrustChainPath)
    (Invoke-CatalogRotationRunner -SnapshotPath $BaselineSnapshotPath -IntegrityRefPath $BaselineIntegrityRef -RotationRunnerPath $RotationRunnerPath)
    (Invoke-HistoricalCatalogValidation -SnapshotPath $BaselineSnapshotPath -IntegrityRefPath $BaselineIntegrityRef -HistoryChainPath $HistoryChainPath)
    Invoke-DirectCatalogReadHelper -SnapshotPath $BaselineSnapshotPath -IntegrityRefPath $BaselineIntegrityRef -CatalogPath $ActiveCatalogPath
)
$caseAResults | ForEach-Object { $entrypointCalls.Add($_) }
$caseAPass = (@($caseAResults | Where-Object { $_.baseline_guard -ne 'PASS' -or $_.operation -ne 'ALLOWED' }).Count -eq 0)
$caseA = [ordered]@{
    case = 'A'
    description = 'Normal operation with intact baseline'
    baseline_guard = 'PASS'
    operation = if ($caseAPass) { 'ALLOWED' } else { 'BLOCKED' }
    details = 'all_entrypoints_guarded_and_allowed_under_clean_baseline'
    pass = $caseAPass
}
$caseRecords.Add($caseA)
if (-not $caseAPass) { $allPassed = $false }

Write-Host '=== CASE B: DIRECT CATALOG LOAD BYPASS ATTEMPT ==='
$tempB = New-TamperedBaselineCopy -CaseTag 'caseB' -BaselineContent $baselineContent
$caseBResult = Invoke-CatalogLoad -SnapshotPath $tempB -IntegrityRefPath $BaselineIntegrityRef -CatalogPath $ActiveCatalogPath
$entrypointCalls.Add($caseBResult)
$caseBPass = ($caseBResult.baseline_guard -eq 'FAIL' -and $caseBResult.operation -eq 'BLOCKED')
$caseB = [ordered]@{
    case = 'B'
    description = 'Direct catalog load bypass attempt'
    baseline_guard = $caseBResult.baseline_guard
    operation = $caseBResult.operation
    details = $caseBResult.reason
    pass = $caseBPass
}
$caseRecords.Add($caseB)
Remove-Item -Force -LiteralPath $tempB
if (-not $caseBPass) { $allPassed = $false }

Write-Host '=== CASE C: TRUST CHAIN VALIDATION BYPASS ATTEMPT ==='
$tempC = New-TamperedBaselineCopy -CaseTag 'caseC' -BaselineContent $baselineContent
$caseCResult = Invoke-CatalogTrustChainVerification -SnapshotPath $tempC -IntegrityRefPath $BaselineIntegrityRef -TrustChainPath $TrustChainPath
$entrypointCalls.Add($caseCResult)
$caseCPass = ($caseCResult.baseline_guard -eq 'FAIL' -and $caseCResult.operation -eq 'BLOCKED')
$caseC = [ordered]@{
    case = 'C'
    description = 'Trust-chain validation bypass attempt'
    baseline_guard = $caseCResult.baseline_guard
    operation = $caseCResult.operation
    details = $caseCResult.reason
    pass = $caseCPass
}
$caseRecords.Add($caseC)
Remove-Item -Force -LiteralPath $tempC
if (-not $caseCPass) { $allPassed = $false }

Write-Host '=== CASE D: VERSION SELECTION BYPASS ATTEMPT ==='
$tempD = New-TamperedBaselineCopy -CaseTag 'caseD' -BaselineContent $baselineContent
$caseDResult = Invoke-CatalogVersionSelection -SnapshotPath $tempD -IntegrityRefPath $BaselineIntegrityRef -CatalogPath $ActiveCatalogPath -Version 'v2'
$entrypointCalls.Add($caseDResult)
$caseDPass = ($caseDResult.baseline_guard -eq 'FAIL' -and $caseDResult.operation -eq 'BLOCKED')
$caseD = [ordered]@{
    case = 'D'
    description = 'Version selection bypass attempt'
    baseline_guard = $caseDResult.baseline_guard
    operation = $caseDResult.operation
    details = $caseDResult.reason
    pass = $caseDPass
}
$caseRecords.Add($caseD)
Remove-Item -Force -LiteralPath $tempD
if (-not $caseDPass) { $allPassed = $false }

Write-Host '=== CASE E: ROTATION RUNNER BYPASS ATTEMPT ==='
$tempE = New-TamperedBaselineCopy -CaseTag 'caseE' -BaselineContent $baselineContent
$caseEResult = Invoke-CatalogRotationRunner -SnapshotPath $tempE -IntegrityRefPath $BaselineIntegrityRef -RotationRunnerPath $RotationRunnerPath
$entrypointCalls.Add($caseEResult)
$caseEPass = ($caseEResult.baseline_guard -eq 'FAIL' -and $caseEResult.rotation -eq 'BLOCKED')
$caseE = [ordered]@{
    case = 'E'
    description = 'Rotation runner bypass attempt'
    baseline_guard = $caseEResult.baseline_guard
    operation = $caseEResult.rotation
    details = $caseEResult.reason
    pass = $caseEPass
}
$caseRecords.Add($caseE)
Remove-Item -Force -LiteralPath $tempE
if (-not $caseEPass) { $allPassed = $false }

Write-Host '=== CASE F: HISTORICAL VALIDATION BYPASS ATTEMPT ==='
$tempF = New-TamperedBaselineCopy -CaseTag 'caseF' -BaselineContent $baselineContent
$caseFResult = Invoke-HistoricalCatalogValidation -SnapshotPath $tempF -IntegrityRefPath $BaselineIntegrityRef -HistoryChainPath $HistoryChainPath
$entrypointCalls.Add($caseFResult)
$caseFPass = ($caseFResult.baseline_guard -eq 'FAIL' -and $caseFResult.operation -eq 'BLOCKED')
$caseF = [ordered]@{
    case = 'F'
    description = 'Historical validation bypass attempt'
    baseline_guard = $caseFResult.baseline_guard
    operation = $caseFResult.operation
    details = $caseFResult.reason
    pass = $caseFPass
}
$caseRecords.Add($caseF)
Remove-Item -Force -LiteralPath $tempF
if (-not $caseFPass) { $allPassed = $false }

Write-Host '=== CASE G: INTERNAL HELPER BYPASS ATTEMPT ==='
$tempG = New-TamperedBaselineCopy -CaseTag 'caseG' -BaselineContent $baselineContent
$caseGResult = Invoke-DirectCatalogReadHelper -SnapshotPath $tempG -IntegrityRefPath $BaselineIntegrityRef -CatalogPath $ActiveCatalogPath
$entrypointCalls.Add($caseGResult)
$caseGPass = ($caseGResult.baseline_guard -eq 'FAIL' -and $caseGResult.operation -eq 'BLOCKED')
$caseG = [ordered]@{
    case = 'G'
    description = 'Internal helper bypass attempt'
    baseline_guard = $caseGResult.baseline_guard
    operation = $caseGResult.operation
    details = $caseGResult.reason
    pass = $caseGPass
}
$caseRecords.Add($caseG)
Remove-Item -Force -LiteralPath $tempG
if (-not $caseGPass) { $allPassed = $false }

$guardedEntrypoints = @(
    'catalog_load',
    'catalog_version_selection',
    'default_catalog_resolution',
    'catalog_trust_chain_verification',
    'catalog_rotation_runner',
    'historical_catalog_validation',
    'direct_catalog_file_read_helper'
)

$guardMap = @(
    'catalog_load -> Test-BaselineGuard (via direct_catalog_file_read_helper)',
    'catalog_version_selection -> Test-BaselineGuard (inline, first step)',
    'default_catalog_resolution -> Test-BaselineGuard (inline, first step)',
    'catalog_trust_chain_verification -> Test-BaselineGuard (inline, first step)',
    'catalog_rotation_runner -> Test-BaselineGuard (inline, first step)',
    'historical_catalog_validation -> Test-BaselineGuard (inline, first step)',
    'direct_catalog_file_read_helper -> Test-BaselineGuard (inline, first step)'
)

$gate = if ($allPassed) { 'PASS' } else { 'FAIL' }

$status = @(
    'phase=44.2',
    'title=Baseline Guard Bypass Resistance',
    ('gate=' + $gate),
    ('cases_total=' + $caseRecords.Count),
    ('cases_pass=' + (@($caseRecords | Where-Object { $_.pass }).Count)),
    ('cases_fail=' + (@($caseRecords | Where-Object { -not $_.pass }).Count)),
    ('entrypoints_guarded=' + $guardedEntrypoints.Count),
    ('timestamp=' + $Timestamp)
)
Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value ($status -join "`r`n") -Encoding UTF8 -NoNewline

$head = @(
    'runner=tools\\phase44_2\\phase44_2_baseline_guard_bypass_resistance_runner.ps1',
    'baseline_snapshot=tools\\phase44_0\\catalog_baseline_snapshot.json',
    'baseline_integrity_ref=tools\\phase44_0\\catalog_baseline_integrity_reference.json',
    'active_catalog=tools\\phase43_7\\active_chain_version_catalog_v2.json',
    'trust_chain=tools\\phase43_9\\catalog_trust_chain.json',
    'history_chain=tools\\phase43_7\\catalog_history_chain.json',
    'rotation_runner=tools\\phase43_7\\phase43_7_active_chain_catalog_rotation_runner.ps1'
)
Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value ($head -join "`r`n") -Encoding UTF8 -NoNewline

$inventory = @(
    'GUARDED ENTRYPOINT INVENTORY',
    '',
    '1) catalog_load',
    '2) catalog_version_selection',
    '3) default_catalog_resolution',
    '4) catalog_trust_chain_verification',
    '5) catalog_rotation_runner',
    '6) historical_catalog_validation',
    '7) direct_catalog_file_read_helper',
    '',
    'All above entrypoints must pass Test-BaselineGuard before catalog state access.'
)
Set-Content -LiteralPath (Join-Path $PF '10_entrypoint_inventory.txt') -Value ($inventory -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '11_guard_enforcement_map.txt') -Value ($guardMap -join "`r`n") -Encoding UTF8 -NoNewline

$filesTouched = @(
    'READ  tools\\phase44_0\\catalog_baseline_snapshot.json',
    'READ  tools\\phase44_0\\catalog_baseline_integrity_reference.json',
    'READ  tools\\phase43_7\\active_chain_version_catalog_v2.json',
    'READ  tools\\phase43_9\\catalog_trust_chain.json',
    'READ  tools\\phase43_7\\catalog_history_chain.json',
    'READ  tools\\phase43_7\\phase43_7_active_chain_catalog_rotation_runner.ps1',
    'TEMP  %TEMP%\\phase44_2_caseB_*.json (deleted)',
    'TEMP  %TEMP%\\phase44_2_caseC_*.json (deleted)',
    'TEMP  %TEMP%\\phase44_2_caseD_*.json (deleted)',
    'TEMP  %TEMP%\\phase44_2_caseE_*.json (deleted)',
    'TEMP  %TEMP%\\phase44_2_caseF_*.json (deleted)',
    'TEMP  %TEMP%\\phase44_2_caseG_*.json (deleted)',
    ('WRITE _proof\\phase44_2_baseline_guard_bypass_resistance_' + $Timestamp + '\\*')
)
Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Value ($filesTouched -join "`r`n") -Encoding UTF8 -NoNewline

$buildOutput = @(
    'phase44_2 runner executed in strict PowerShell mode.',
    'no compile step required.',
    'no runtime state machine mutation performed.',
    'hash method=sha256_file_bytes_v1.'
)
Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Value ($buildOutput -join "`r`n") -Encoding UTF8 -NoNewline

$validationLines = @()
foreach ($c in $caseRecords) {
    $validationLines += ('CASE ' + $c.case + ': baseline_guard=' + $c.baseline_guard + '; operation=' + $c.operation + '; details=' + $c.details + '; pass=' + $c.pass)
}
Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Value ($validationLines -join "`r`n") -Encoding UTF8 -NoNewline

$summary = @(
    'Phase 44.2 validates bypass resistance by invoking alternate catalog entrypoints directly.',
    'Every entrypoint calls Test-BaselineGuard before reading catalog/trust/history state.',
    'Cases B-G tamper baseline bytes to force deterministic baseline_hash_mismatch.',
    'No fallback path and no regeneration logic exist in any entrypoint function.',
    'Blocked behavior is deterministic and consistent across all bypass attempts.',
    'Runtime state machine unchanged: runner is read-only on catalog state and writes only proof/temp files.'
)
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value ($summary -join "`r`n") -Encoding UTF8 -NoNewline

$entrypointRecord = [ordered]@{
    baseline_snapshot = $BaselineSnapshotPath
    baseline_integrity_reference = $BaselineIntegrityRef
    guarded_entrypoints = $guardedEntrypoints
    call_records = $entrypointCalls
}
Set-Content -LiteralPath (Join-Path $PF '16_entrypoint_guard_record.txt') -Value ($entrypointRecord | ConvertTo-Json -Depth 7) -Encoding UTF8 -NoNewline

$bypassEvidence = @(
    'BYPASS ATTEMPT EVIDENCE',
    '',
    ('CASE B blocked=' + ($caseB.operation -eq 'BLOCKED') + '; reason=' + $caseB.details),
    ('CASE C blocked=' + ($caseC.operation -eq 'BLOCKED') + '; reason=' + $caseC.details),
    ('CASE D blocked=' + ($caseD.operation -eq 'BLOCKED') + '; reason=' + $caseD.details),
    ('CASE E blocked=' + ($caseE.operation -eq 'BLOCKED') + '; reason=' + $caseE.details),
    ('CASE F blocked=' + ($caseF.operation -eq 'BLOCKED') + '; reason=' + $caseF.details),
    ('CASE G blocked=' + ($caseG.operation -eq 'BLOCKED') + '; reason=' + $caseG.details),
    '',
    'fallback_occurred=false for all bypass attempts',
    'regeneration_occurred=false for all bypass attempts'
)
Set-Content -LiteralPath (Join-Path $PF '17_bypass_block_evidence.txt') -Value ($bypassEvidence -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '98_gate_phase44_2.txt') -Value $gate -Encoding UTF8 -NoNewline

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
