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
    Write-Host 'wrong workspace for phase103_85 runner'
    exit 1
}

$proofRoot  = Join-Path $workspaceRoot '_proof'
$timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName  = "phase103_85_production_readiness_hardening_gate_${timestamp}"
$proofDir   = Join-Path $proofRoot $proofName
$zipPath    = Join-Path $proofRoot ($proofName + '.zip')

$buildOut   = Join-Path $proofDir 'phase103_85_build_output.txt'
$staticOut  = Join-Path $proofDir 'phase103_85_static_checks.json'
$runOut     = Join-Path $proofDir 'phase103_85_runtime_output.txt'
$errOut     = Join-Path $proofDir 'phase103_85_runtime_stderr.txt'
$markerOut  = Join-Path $proofDir 'phase103_85_marker_results.json'
$reportOut  = Join-Path $proofDir 'PHASE103_85_VERIFICATION_REPORT.md'

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
        throw "[phase103_85] $StepName failed with exit code $LASTEXITCODE"
    }
}

Write-Host '[phase103_85] Static source checks...'
Assert-True (Test-Path -LiteralPath $mainPath) '[phase103_85] main.cpp missing'
$mainText = Get-Content -LiteralPath $mainPath -Raw

$staticChecks = @(
    'BuilderProductionReadinessHardeningGateDiagnostics',
    'production_readiness_hardening_diag',
    'fail_closed_traversal_guard_hits_total',
    'run_phase103_85',
    'phase103_85_invalid_inputs_fail_closed_without_state_corruption',
    'phase103_85_no_null_or_invalid_reference_paths_exist',
    'phase103_85_history_operations_safe_at_all_boundaries',
    'phase103_85_selection_and_mapping_remain_valid_under_all_inputs',
    'phase103_85_serialization_and_import_paths_are_guarded',
    'phase103_85_no_partial_mutation_on_failure_paths',
    'phase103_85_no_silent_state_corruption_detected',
    'phase103_85_all_edge_case_sequences_remain_deterministic',
    'phase103_85_all_runs_terminate_cleanly_with_complete_artifacts',
    'phase103_85_global_invariant_preserved',
    'phase103_85_final_canonical_signature',
    'loop.set_timeout(milliseconds(20300), [&] { run_phase103_85(); });'
)

$staticReport = @{}
$staticFail = $false
foreach ($token in $staticChecks) {
    $found = $mainText.Contains($token)
    $staticReport[$token] = $found
    if (-not $found) {
        Write-Host "[phase103_85] MISSING TOKEN: $token" -ForegroundColor Red
        $staticFail = $true
    }
}

$staticReport | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $staticOut -Encoding UTF8
Assert-True (-not $staticFail) '[phase103_85] Static token check failed.'
Write-Host '[phase103_85] All static tokens present.'

Write-Host '[phase103_85] Stopping running desktop_file_tool instances...'
Get-Process desktop_file_tool -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host '[phase103_85] Building desktop_file_tool...'
& (Join-Path $workspaceRoot '.venv/Scripts/python.exe') -m ngksgraph build --profile debug --msvc-auto --target desktop_file_tool *>&1 |
    Out-File -LiteralPath $buildOut -Encoding UTF8
Assert-True ($LASTEXITCODE -eq 0) '[phase103_85] Build-plan generation failed.'

Assert-True (Test-Path -LiteralPath $planPath) '[phase103_85] Build plan missing.'
$planJson = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json

$engineCompileNodes = @($planJson.nodes | Where-Object { $_.desc -like 'Compile engine/* for engine' })
$appCompileNode     = @($planJson.nodes | Where-Object { $_.desc -eq 'Compile apps/desktop_file_tool/main.cpp for desktop_file_tool' })[0]
$engineLibNode      = @($planJson.nodes | Where-Object { $_.desc -eq 'Link engine' })[0]
$appLinkNode        = @($planJson.nodes | Where-Object { $_.desc -eq 'Link desktop_file_tool' })[0]
Assert-True ($engineCompileNodes.Count -gt 0 -and $null -ne $appCompileNode -and $null -ne $engineLibNode -and $null -ne $appLinkNode) '[phase103_85] Required compile/link nodes missing.'

Initialize-PlanOutputDirectories -PlanJson $planJson
& (Join-Path $workspaceRoot 'tools/enter_msvc_env.ps1') *>&1 | Out-File -LiteralPath $buildOut -Append -Encoding UTF8

foreach ($node in $engineCompileNodes) {
    Invoke-CmdChecked -CommandLine $node.cmd -StepName $node.desc
}
Invoke-CmdChecked -CommandLine $appCompileNode.cmd -StepName $appCompileNode.desc
Invoke-CmdChecked -CommandLine $engineLibNode.cmd   -StepName $engineLibNode.desc
Invoke-CmdChecked -CommandLine $appLinkNode.cmd     -StepName $appLinkNode.desc

Assert-True (Test-Path -LiteralPath $exePath) '[phase103_85] Executable missing after compile/link.'
Write-Host '[phase103_85] Build OK.'

$requiredYes = @(
    'phase103_85_invalid_inputs_fail_closed_without_state_corruption',
    'phase103_85_no_null_or_invalid_reference_paths_exist',
    'phase103_85_history_operations_safe_at_all_boundaries',
    'phase103_85_selection_and_mapping_remain_valid_under_all_inputs',
    'phase103_85_serialization_and_import_paths_are_guarded',
    'phase103_85_no_partial_mutation_on_failure_paths',
    'phase103_85_no_silent_state_corruption_detected',
    'phase103_85_all_edge_case_sequences_remain_deterministic',
    'phase103_85_all_runs_terminate_cleanly_with_complete_artifacts',
    'phase103_85_global_invariant_preserved'
)

Write-Host '[phase103_85] Running validation gate...'
$proc = Start-Process -FilePath $exePath -ArgumentList @('--validation-mode', '--auto-close-ms=160000') -PassThru -WindowStyle Hidden -RedirectStandardOutput $runOut -RedirectStandardError $errOut
$proc.WaitForExit()

if (Test-Path -LiteralPath $errOut) {
    $stderrText = Get-Content -LiteralPath $errOut -Raw
    if (-not [string]::IsNullOrWhiteSpace($stderrText)) {
        Add-Content -LiteralPath $runOut -Value $stderrText
    }
}

Assert-True ($proc.ExitCode -eq 0) ("[phase103_85] Validation run failed with exit code {0}" -f $proc.ExitCode)
$runText = (Get-Content -LiteralPath $runOut -Raw) -replace "`r", ''
$markerMap = @{}
foreach ($line in ($runText -split "`n")) {
    if ($line -match '^([^=]+)=(.*)$') {
        $markerMap[$matches[1]] = $matches[2]
    }
}

foreach ($marker in $requiredYes) {
    Assert-True ($markerMap.ContainsKey($marker) -and $markerMap[$marker] -eq 'YES') ("[phase103_85] Missing or failed marker {0}" -f $marker)
}
Assert-True ($markerMap.ContainsKey('app_runtime_crash_detected') -and $markerMap['app_runtime_crash_detected'] -eq '0') '[phase103_85] Validation reported a runtime crash.'
Assert-True (($runText -split "`n") -contains 'SUMMARY: PASS') '[phase103_85] Missing SUMMARY: PASS.'
Assert-True ($markerMap.ContainsKey('phase103_85_final_canonical_signature') -and -not [string]::IsNullOrWhiteSpace($markerMap['phase103_85_final_canonical_signature'])) '[phase103_85] Missing final canonical signature.'

$results = @()
foreach ($marker in $requiredYes) {
    $results += [pscustomobject]@{ marker = $marker; value = $markerMap[$marker] }
}
$results += [pscustomobject]@{ marker = 'app_runtime_crash_detected'; value = $markerMap['app_runtime_crash_detected'] }
$results += [pscustomobject]@{ marker = 'summary_pass_present'; value = 'PASS' }
$results += [pscustomobject]@{ marker = 'phase103_85_invalid_sequence_count'; value = $markerMap['phase103_85_invalid_sequence_count'] }
$results += [pscustomobject]@{ marker = 'phase103_85_fail_closed_traversal_guard_hits'; value = $markerMap['phase103_85_fail_closed_traversal_guard_hits'] }
$results += [pscustomobject]@{ marker = 'phase103_85_artifact_file_count_observed'; value = $markerMap['phase103_85_artifact_file_count_observed'] }
$results += [pscustomobject]@{ marker = 'phase103_85_final_canonical_signature'; value = $markerMap['phase103_85_final_canonical_signature'] }

$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $markerOut -Encoding UTF8

$phasePass = $true
$report = @()
$report += '# PHASE103_85 Production Readiness / Hardening Gate Report'
$report += ''
$report += "timestamp=$timestamp"
$report += "phase_status=$(if ($phasePass) { 'PASS' } else { 'FAIL' })"
$report += 'representative_scenarios=invalid_selection_recovery,history_boundary_guards,serialization_import_rejection,rejected_inspector_mutations,deterministic_invalid_sequences'
$report += ''
$report += 'required_markers:'
foreach ($result in $results) {
    $report += "- $($result.marker)=$($result.value)"
}
$report += ''
$report += 'artifacts:'
$report += '- phase103_85_static_checks.json'
$report += '- phase103_85_build_output.txt'
$report += '- phase103_85_runtime_output.txt'
$report += '- phase103_85_marker_results.json'
$report += '- PHASE103_85_VERIFICATION_REPORT.md'
$report -join "`r`n" | Set-Content -LiteralPath $reportOut -Encoding UTF8

$artifactPaths = @($staticOut, $buildOut, $runOut, $markerOut, $reportOut)
$artifactComplete = (@($artifactPaths | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 5)
Assert-True $artifactComplete '[phase103_85] Proof artifact generation incomplete.'

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $proofDir '*') -DestinationPath $zipPath -Force

Write-Host '[phase103_85] PASS'
Write-Host "[phase103_85] Proof directory: $proofDir"
Write-Host "[phase103_85] Proof archive: $zipPath"