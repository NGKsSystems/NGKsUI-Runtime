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
    Write-Host 'wrong workspace for phase103_84 runner'
    exit 1
}

$proofRoot  = Join-Path $workspaceRoot '_proof'
$timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName  = "phase103_84_system_stability_long_run_validation_${timestamp}"
$proofDir   = Join-Path $proofRoot $proofName
$zipPath    = Join-Path $proofRoot ($proofName + '.zip')

$buildOut   = Join-Path $proofDir 'phase103_84_build_output.txt'
$staticOut  = Join-Path $proofDir 'phase103_84_static_checks.json'
$runSummaryOut = Join-Path $proofDir 'phase103_84_run_summary.json'
$markerOut  = Join-Path $proofDir 'phase103_84_marker_results.json'
$reportOut  = Join-Path $proofDir 'PHASE103_84_VERIFICATION_REPORT.md'

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
        throw "[phase103_84] $StepName failed with exit code $LASTEXITCODE"
    }
}

Write-Host '[phase103_84] Static source checks...'
Assert-True (Test-Path -LiteralPath $mainPath) '[phase103_84] main.cpp missing'
$mainText = Get-Content -LiteralPath $mainPath -Raw

$staticChecks = @(
    'BuilderSystemStabilityLongRunValidationDiagnostics',
    'long_run_validation_stability_diag',
    'run_phase103_84',
    'phase103_84_repeated_runs_produce_identical_final_signatures',
    'phase103_84_no_semantic_drift_across_long_run_sequences',
    'phase103_84_undo_redo_remains_exact_over_extended_cycles',
    'phase103_84_save_load_export_cycles_remain_stable_and_deterministic',
    'phase103_84_filter_viewport_projection_cycles_remain_non_drifting',
    'phase103_84_no_stale_state_accumulates_over_time',
    'phase103_84_no_unbounded_resource_growth_signal_detected',
    'phase103_84_all_runs_terminate_cleanly_with_complete_artifacts',
    'phase103_84_no_correctness_guarantees_were_weakened',
    'phase103_84_global_invariant_preserved',
    'phase103_84_final_canonical_signature',
    'loop.set_timeout(milliseconds(20100), [&] { run_phase103_84(); });'
)

$staticReport = @{}
$staticFail = $false
foreach ($token in $staticChecks) {
    $found = $mainText.Contains($token)
    $staticReport[$token] = $found
    if (-not $found) {
        Write-Host "[phase103_84] MISSING TOKEN: $token" -ForegroundColor Red
        $staticFail = $true
    }
}

$staticReport | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $staticOut -Encoding UTF8
Assert-True (-not $staticFail) '[phase103_84] Static token check failed.'
Write-Host '[phase103_84] All static tokens present.'

Write-Host '[phase103_84] Stopping running desktop_file_tool instances...'
Get-Process desktop_file_tool -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host '[phase103_84] Building desktop_file_tool...'
& (Join-Path $workspaceRoot '.venv/Scripts/python.exe') -m ngksgraph build --profile debug --msvc-auto --target desktop_file_tool *>&1 |
    Out-File -LiteralPath $buildOut -Encoding UTF8
Assert-True ($LASTEXITCODE -eq 0) '[phase103_84] Build-plan generation failed.'

Assert-True (Test-Path -LiteralPath $planPath) '[phase103_84] Build plan missing.'
$planJson = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json

$engineCompileNodes = @($planJson.nodes | Where-Object { $_.desc -like 'Compile engine/* for engine' })
$appCompileNode     = @($planJson.nodes | Where-Object { $_.desc -eq 'Compile apps/desktop_file_tool/main.cpp for desktop_file_tool' })[0]
$engineLibNode      = @($planJson.nodes | Where-Object { $_.desc -eq 'Link engine' })[0]
$appLinkNode        = @($planJson.nodes | Where-Object { $_.desc -eq 'Link desktop_file_tool' })[0]
Assert-True ($engineCompileNodes.Count -gt 0 -and $null -ne $appCompileNode -and $null -ne $engineLibNode -and $null -ne $appLinkNode) '[phase103_84] Required compile/link nodes missing.'

Initialize-PlanOutputDirectories -PlanJson $planJson
& (Join-Path $workspaceRoot 'tools/enter_msvc_env.ps1') *>&1 | Out-File -LiteralPath $buildOut -Append -Encoding UTF8

foreach ($node in $engineCompileNodes) {
    Invoke-CmdChecked -CommandLine $node.cmd -StepName $node.desc
}
Invoke-CmdChecked -CommandLine $appCompileNode.cmd -StepName $appCompileNode.desc
Invoke-CmdChecked -CommandLine $engineLibNode.cmd   -StepName $engineLibNode.desc
Invoke-CmdChecked -CommandLine $appLinkNode.cmd     -StepName $appLinkNode.desc

Assert-True (Test-Path -LiteralPath $exePath) '[phase103_84] Executable missing after compile/link.'
Write-Host '[phase103_84] Build OK.'

$requiredYes = @(
    'phase103_84_repeated_runs_produce_identical_final_signatures',
    'phase103_84_no_semantic_drift_across_long_run_sequences',
    'phase103_84_undo_redo_remains_exact_over_extended_cycles',
    'phase103_84_save_load_export_cycles_remain_stable_and_deterministic',
    'phase103_84_filter_viewport_projection_cycles_remain_non_drifting',
    'phase103_84_no_stale_state_accumulates_over_time',
    'phase103_84_no_unbounded_resource_growth_signal_detected',
    'phase103_84_all_runs_terminate_cleanly_with_complete_artifacts',
    'phase103_84_no_correctness_guarantees_were_weakened',
    'phase103_84_global_invariant_preserved'
)

$runResults = New-Object System.Collections.Generic.List[object]
$finalSignatures = New-Object System.Collections.Generic.List[string]
$workingSetPeaks = New-Object System.Collections.Generic.List[long]
$handlePeaks = New-Object System.Collections.Generic.List[int]

for ($runIndex = 1; $runIndex -le 3; $runIndex++) {
    Write-Host "[phase103_84] Running validation cycle $runIndex/3..."
    $runOut = Join-Path $proofDir ('phase103_84_runtime_run{0:D2}.txt' -f $runIndex)
    $errOut = Join-Path $proofDir ('phase103_84_runtime_run{0:D2}_stderr.txt' -f $runIndex)
    $proc = Start-Process -FilePath $exePath -ArgumentList @('--validation-mode', '--auto-close-ms=150000') -PassThru -WindowStyle Hidden -RedirectStandardOutput $runOut -RedirectStandardError $errOut
    $peakWorkingSet = 0L
    $peakHandles = 0
    while (-not $proc.HasExited) {
        try {
            $sample = Get-Process -Id $proc.Id -ErrorAction Stop
            if ($sample.WorkingSet64 -gt $peakWorkingSet) { $peakWorkingSet = $sample.WorkingSet64 }
            if ($sample.HandleCount -gt $peakHandles) { $peakHandles = $sample.HandleCount }
        } catch {
        }
        Wait-Process -Id $proc.Id -Timeout 1 -ErrorAction SilentlyContinue | Out-Null
        $proc.Refresh()
    }

    if (Test-Path -LiteralPath $errOut) {
        $stderrText = Get-Content -LiteralPath $errOut -Raw
        if (-not [string]::IsNullOrWhiteSpace($stderrText)) {
            Add-Content -LiteralPath $runOut -Value $stderrText
        }
    }

    Assert-True ($proc.ExitCode -eq 0) ("[phase103_84] Validation run {0} failed with exit code {1}" -f $runIndex, $proc.ExitCode)
    $runText = (Get-Content -LiteralPath $runOut -Raw) -replace "`r", ''
    $markerMap = @{}
    foreach ($line in ($runText -split "`n")) {
        if ($line -match '^([^=]+)=(.*)$') {
            $markerMap[$matches[1]] = $matches[2]
        }
    }

    foreach ($marker in $requiredYes) {
        Assert-True ($markerMap.ContainsKey($marker) -and $markerMap[$marker] -eq 'YES') ("[phase103_84] Run {0} missing or failed marker {1}" -f $runIndex, $marker)
    }
    Assert-True ($markerMap.ContainsKey('app_runtime_crash_detected') -and $markerMap['app_runtime_crash_detected'] -eq '0') ("[phase103_84] Run {0} reported a runtime crash" -f $runIndex)
    Assert-True (($runText -split "`n") -contains 'SUMMARY: PASS') ("[phase103_84] Run {0} missing SUMMARY: PASS" -f $runIndex)
    Assert-True ($markerMap.ContainsKey('phase103_84_final_canonical_signature') -and -not [string]::IsNullOrWhiteSpace($markerMap['phase103_84_final_canonical_signature'])) ("[phase103_84] Run {0} missing final canonical signature" -f $runIndex)

    $finalSignatures.Add($markerMap['phase103_84_final_canonical_signature'])
    $workingSetPeaks.Add($peakWorkingSet)
    $handlePeaks.Add($peakHandles)
    $runResults.Add([pscustomobject]@{
        run = $runIndex
        exit_code = $proc.ExitCode
        final_signature = $markerMap['phase103_84_final_canonical_signature']
        repeated_run_count = $markerMap['phase103_84_internal_repeated_run_count']
        mixed_cycle_count = $markerMap['phase103_84_internal_mixed_cycle_count']
        undo_redo_cycle_count = $markerMap['phase103_84_internal_undo_redo_cycle_count']
        save_load_export_cycle_count = $markerMap['phase103_84_internal_save_load_export_cycle_count']
        filter_projection_cycle_count = $markerMap['phase103_84_internal_filter_projection_cycle_count']
        peak_working_set = $peakWorkingSet
        peak_handle_count = $peakHandles
    })
}

$runResults | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $runSummaryOut -Encoding UTF8

$uniqueFinalSignatures = @($finalSignatures | Select-Object -Unique)
$signatureStable = $uniqueFinalSignatures.Count -eq 1
$workingSetStats = $workingSetPeaks | Measure-Object -Minimum -Maximum
$handleStats = $handlePeaks | Measure-Object -Minimum -Maximum
$resourceStable = (($workingSetStats.Maximum - $workingSetStats.Minimum) -le 134217728) -and (($handleStats.Maximum - $handleStats.Minimum) -le 256)

$results = @(
    [pscustomobject]@{ marker = 'phase103_84_repeated_runs_produce_identical_final_signatures'; value = $(if ($signatureStable) { 'YES' } else { 'NO' }) },
    [pscustomobject]@{ marker = 'phase103_84_no_semantic_drift_across_long_run_sequences'; value = $(if ($signatureStable) { 'YES' } else { 'NO' }) },
    [pscustomobject]@{ marker = 'phase103_84_undo_redo_remains_exact_over_extended_cycles'; value = 'YES' },
    [pscustomobject]@{ marker = 'phase103_84_save_load_export_cycles_remain_stable_and_deterministic'; value = 'YES' },
    [pscustomobject]@{ marker = 'phase103_84_filter_viewport_projection_cycles_remain_non_drifting'; value = 'YES' },
    [pscustomobject]@{ marker = 'phase103_84_no_stale_state_accumulates_over_time'; value = 'YES' },
    [pscustomobject]@{ marker = 'phase103_84_no_unbounded_resource_growth_signal_detected'; value = $(if ($resourceStable) { 'YES' } else { 'NO' }) },
    [pscustomobject]@{ marker = 'phase103_84_all_runs_terminate_cleanly_with_complete_artifacts'; value = 'YES' },
    [pscustomobject]@{ marker = 'phase103_84_no_correctness_guarantees_were_weakened'; value = 'YES' },
    [pscustomobject]@{ marker = 'phase103_84_global_invariant_preserved'; value = 'YES' },
    [pscustomobject]@{ marker = 'app_runtime_crash_detected'; value = 0 },
    [pscustomobject]@{ marker = 'summary_pass_present'; value = 'PASS' }
)

$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $markerOut -Encoding UTF8

$artifactPaths = @($staticOut, $buildOut, $runSummaryOut, $markerOut, $reportOut)
$phasePass = $signatureStable -and $resourceStable

$report = @()
$report += '# PHASE103_84 System Stability / Long-Run Validation Report'
$report += ''
$report += "timestamp=$timestamp"
$report += "phase_status=$(if ($phasePass) { 'PASS' } else { 'FAIL' })"
$report += 'representative_scenarios=filter_clear_cycles,undo_redo_cycles,save_load_export_cycles,repeated_full_validation_runs'
$report += 'repeated_process_runs=3'
$report += ''
$report += 'required_markers:'
foreach ($result in $results) {
    $report += "- $($result.marker)=$($result.value)"
}
$report += ''
$report += 'signature_comparison:'
foreach ($run in $runResults) {
    $report += "- run_$($run.run)_final_signature=$($run.final_signature)"
}
$report += ''
$report += 'resource_observations:'
foreach ($run in $runResults) {
    $report += "- run_$($run.run)_peak_working_set=$($run.peak_working_set)"
    $report += "- run_$($run.run)_peak_handle_count=$($run.peak_handle_count)"
}
$report += "- working_set_peak_delta=$($workingSetStats.Maximum - $workingSetStats.Minimum)"
$report += "- handle_peak_delta=$($handleStats.Maximum - $handleStats.Minimum)"
$report += ''
$report += 'artifacts:'
$report += '- phase103_84_static_checks.json'
$report += '- phase103_84_build_output.txt'
$report += '- phase103_84_runtime_run01.txt'
$report += '- phase103_84_runtime_run02.txt'
$report += '- phase103_84_runtime_run03.txt'
$report += '- phase103_84_run_summary.json'
$report += '- phase103_84_marker_results.json'
$report += '- PHASE103_84_VERIFICATION_REPORT.md'
$report -join "`r`n" | Set-Content -LiteralPath $reportOut -Encoding UTF8

$artifactComplete = (@($artifactPaths | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 5)
Assert-True $artifactComplete '[phase103_84] Proof artifact generation incomplete.'

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $proofDir '*') -DestinationPath $zipPath -Force

if (-not $phasePass) {
    throw '[phase103_84] Marker verification failed.'
}

Write-Host '[phase103_84] PASS'
Write-Host "[phase103_84] Proof directory: $proofDir"
Write-Host "[phase103_84] Proof archive: $zipPath"