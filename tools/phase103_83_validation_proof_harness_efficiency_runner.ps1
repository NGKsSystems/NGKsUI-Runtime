#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
    Write-Host "FATAL: $_"
    exit 1
}

$expectedWorkspace = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
$workspaceRoot = (Get-Location).Path
if ($workspaceRoot -ne $expectedWorkspace) {
    Write-Host 'wrong workspace for phase103_83 runner'
    exit 1
}

$proofRoot  = Join-Path $workspaceRoot '_proof'
$timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName  = "phase103_83_validation_proof_harness_efficiency_${timestamp}"
$proofDir   = Join-Path $proofRoot $proofName
$zipPath    = Join-Path $proofRoot ($proofName + '.zip')

$buildOut   = Join-Path $proofDir 'phase103_83_build_output.txt'
$runOut     = Join-Path $proofDir 'phase103_83_runtime_output.txt'
$staticOut  = Join-Path $proofDir 'phase103_83_static_checks.json'
$markerOut  = Join-Path $proofDir 'phase103_83_marker_results.json'
$reportOut  = Join-Path $proofDir 'PHASE103_83_VERIFICATION_REPORT.md'

$planPath   = Join-Path $workspaceRoot 'build_graph/debug/ngksbuildcore_plan.json'
$exePath    = Join-Path $workspaceRoot 'build/debug/bin/desktop_file_tool.exe'
$mainPath   = Join-Path $workspaceRoot 'apps/desktop_file_tool/main.cpp'

New-Item -ItemType Directory -Path $proofRoot -Force | Out-Null
New-Item -ItemType Directory -Path $proofDir  -Force | Out-Null

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Initialize-PlanOutputDirectories {
    param([object]$PlanJson)
    foreach ($node in $PlanJson.nodes) {
        foreach ($output in $node.outputs) {
            if ([string]::IsNullOrWhiteSpace($output)) { continue }
            $dir = Split-Path -Path $output -Parent
            if ([string]::IsNullOrWhiteSpace($dir)) { continue }
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
        }
    }
}

function Invoke-CmdChecked {
    param([string]$CommandLine, [string]$StepName)
    "STEP=$StepName" | Out-File -LiteralPath $buildOut -Append -Encoding UTF8
    cmd /c $CommandLine *>&1 | Out-File -LiteralPath $buildOut -Append -Encoding UTF8
    if ($LASTEXITCODE -ne 0) {
        throw "[phase103_83] $StepName failed with exit code $LASTEXITCODE"
    }
}

Write-Host '[phase103_83] Static source checks...'
Assert-True (Test-Path -LiteralPath $mainPath) '[phase103_83] main.cpp missing'
$mainText = Get-Content -LiteralPath $mainPath -Raw

$staticChecks = @(
    'BuilderValidationProofHarnessEfficiencyDiagnostics',
    'validation_proof_harness_efficiency_diag',
    'run_phase103_83',
    'phase103_83_validation_overhead_reduced_vs_phase103_77',
    'phase103_83_marker_and_proof_semantics_identical',
    'phase103_83_no_runtime_behavior_changed_by_harness_optimization',
    'phase103_83_no_validation_coverage_was_weakened',
    'phase103_83_no_stale_validation_reuse_after_state_change',
    'phase103_83_proof_artifact_generation_remains_complete',
    'phase103_83_profile_run_terminates_cleanly_with_markers',
    'phase103_83_no_partial_or_stalled_proof_artifacts',
    'phase103_83_global_invariant_preserved',
    'cached_validation_doc_signature_reuse_and_one_pass_runner_marker_parse'
)

$staticReport = @{}
$staticFail = $false
foreach ($token in $staticChecks) {
    $found = $mainText.Contains($token)
    $staticReport[$token] = $found
    if (-not $found) {
        Write-Host "[phase103_83] MISSING TOKEN: $token" -ForegroundColor Red
        $staticFail = $true
    }
}

$staticReport | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $staticOut -Encoding UTF8
Assert-True (-not $staticFail) '[phase103_83] Static token check failed.'
Write-Host '[phase103_83] All static tokens present.'

Write-Host '[phase103_83] Stopping running desktop_file_tool instances...'
Get-Process desktop_file_tool -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host '[phase103_83] Building desktop_file_tool...'
& (Join-Path $workspaceRoot '.venv/Scripts/python.exe') -m ngksgraph build --profile debug --msvc-auto --target desktop_file_tool *>&1 |
    Out-File -LiteralPath $buildOut -Encoding UTF8
Assert-True ($LASTEXITCODE -eq 0) '[phase103_83] Build-plan generation failed.'

Assert-True (Test-Path -LiteralPath $planPath) '[phase103_83] Build plan missing.'
$planJson = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json

$engineCompileNodes = @($planJson.nodes | Where-Object { $_.desc -like 'Compile engine/* for engine' })
$appCompileNode     = @($planJson.nodes | Where-Object { $_.desc -eq 'Compile apps/desktop_file_tool/main.cpp for desktop_file_tool' })[0]
$engineLibNode      = @($planJson.nodes | Where-Object { $_.desc -eq 'Link engine' })[0]
$appLinkNode        = @($planJson.nodes | Where-Object { $_.desc -eq 'Link desktop_file_tool' })[0]
Assert-True ($engineCompileNodes.Count -gt 0 -and $null -ne $appCompileNode -and $null -ne $engineLibNode -and $null -ne $appLinkNode) '[phase103_83] Required compile/link nodes missing.'

Initialize-PlanOutputDirectories -PlanJson $planJson
& (Join-Path $workspaceRoot 'tools/enter_msvc_env.ps1') *>&1 | Out-File -LiteralPath $buildOut -Append -Encoding UTF8

foreach ($node in $engineCompileNodes) {
    Invoke-CmdChecked -CommandLine $node.cmd -StepName $node.desc
}
Invoke-CmdChecked -CommandLine $appCompileNode.cmd -StepName $appCompileNode.desc
Invoke-CmdChecked -CommandLine $engineLibNode.cmd   -StepName $engineLibNode.desc
Invoke-CmdChecked -CommandLine $appLinkNode.cmd     -StepName $appLinkNode.desc

Assert-True (Test-Path -LiteralPath $exePath) '[phase103_83] Executable missing after compile/link.'
Write-Host '[phase103_83] Build OK.'

Write-Host '[phase103_83] Running validation mode...'
$exeQuoted = '"' + $exePath + '"'
$runOutQuoted = '"' + $runOut + '"'
cmd /c "$exeQuoted --validation-mode --auto-close-ms=150000 > $runOutQuoted 2>&1"
Assert-True ($LASTEXITCODE -eq 0) '[phase103_83] Validation run failed.'

$requiredYes = @(
    'phase103_83_validation_overhead_reduced_vs_phase103_77',
    'phase103_83_marker_and_proof_semantics_identical',
    'phase103_83_no_runtime_behavior_changed_by_harness_optimization',
    'phase103_83_no_validation_coverage_was_weakened',
    'phase103_83_no_stale_validation_reuse_after_state_change',
    'phase103_83_proof_artifact_generation_remains_complete',
    'phase103_83_profile_run_terminates_cleanly_with_markers',
    'phase103_83_no_partial_or_stalled_proof_artifacts',
    'phase103_83_global_invariant_preserved'
)

$markerMap = @{}
$profileLines = New-Object System.Collections.Generic.List[string]
$summaryPass = $false
foreach ($rawLine in Get-Content -LiteralPath $runOut) {
    $line = $rawLine -replace "`r", ''
    if ([string]::IsNullOrWhiteSpace($line)) {
        continue
    }
    if ($line -like 'phase103_83_*') {
        $profileLines.Add($line)
    }
    if ($line -eq 'SUMMARY: PASS') {
        $summaryPass = $true
    }
    if ($line -match '^([^=]+)=(.*)$') {
        $markerMap[$matches[1]] = $matches[2]
    }
}

$results = @()
$allYes = $true
foreach ($marker in $requiredYes) {
    $value = if ($markerMap.ContainsKey($marker)) { $markerMap[$marker] } else { 'NO' }
    $ok = ($value -eq 'YES')
    if (-not $ok) { $allYes = $false }
    $results += [pscustomobject]@{ marker = $marker; value = $(if ($ok) { 'YES' } else { 'NO' }) }
}

$crashValue = if ($markerMap.ContainsKey('app_runtime_crash_detected')) { $markerMap['app_runtime_crash_detected'] } else { '1' }
$crashFree = ($crashValue -eq '0')
$results += [pscustomobject]@{ marker = 'app_runtime_crash_detected'; value = $(if ($crashFree) { 0 } else { 1 }) }
$results += [pscustomobject]@{ marker = 'summary_pass_present'; value = $(if ($summaryPass) { 'PASS' } else { 'FAIL' }) }

$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $markerOut -Encoding UTF8

$artifactPaths = @($staticOut, $buildOut, $runOut, $markerOut, $reportOut)
$phasePass = $allYes -and $crashFree -and $summaryPass -and ($profileLines.Count -gt 0)

$report = @()
$report += '# PHASE103_83 Validation / Proof Harness Efficiency Verification Report'
$report += ''
$report += "timestamp=$timestamp"
$report += "phase_status=$(if ($phasePass) { 'PASS' } else { 'FAIL' })"
$report += 'runner_marker_parse_strategy=single_pass_line_scan'
$report += 'runner_legacy_marker_scan_count=12'
$report += 'runner_optimized_marker_scan_count=1'
$report += 'artifact_manifest_expected_count=5'
$report += ''
$report += 'required_markers:'
foreach ($result in $results) {
    $report += "- $($result.marker)=$($result.value)"
}
$report += ''
$report += 'profile_summary:'
foreach ($line in $profileLines) {
    $report += "- $line"
}
$report += ''
$report += 'artifacts:'
$report += '- phase103_83_static_checks.json'
$report += '- phase103_83_build_output.txt'
$report += '- phase103_83_runtime_output.txt'
$report += '- phase103_83_marker_results.json'
$report += '- PHASE103_83_VERIFICATION_REPORT.md'
$report -join "`r`n" | Set-Content -LiteralPath $reportOut -Encoding UTF8

$artifactComplete = (@($artifactPaths | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 5)
Assert-True $artifactComplete '[phase103_83] Proof artifact generation incomplete.'

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $proofDir '*') -DestinationPath $zipPath -Force

if (-not $phasePass) {
    throw '[phase103_83] Marker verification failed.'
}

Write-Host '[phase103_83] PASS'
Write-Host "[phase103_83] Proof directory: $proofDir"
Write-Host "[phase103_83] Proof archive: $zipPath"