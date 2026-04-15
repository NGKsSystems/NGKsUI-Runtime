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
    Write-Host 'wrong workspace for phase103_87 runner'
    exit 1
}

$proofRoot  = Join-Path $workspaceRoot '_proof'
$timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName  = "phase103_87_final_system_validation_release_gate_${timestamp}"
$proofDir   = Join-Path $proofRoot $proofName
$zipPath    = Join-Path $proofRoot ($proofName + '.zip')

$buildOut   = Join-Path $proofDir 'phase103_87_build_output.txt'
$staticOut  = Join-Path $proofDir 'phase103_87_static_checks.json'
$runOut     = Join-Path $proofDir 'phase103_87_runtime_output.txt'
$errOut     = Join-Path $proofDir 'phase103_87_runtime_stderr.txt'
$markerOut  = Join-Path $proofDir 'phase103_87_marker_results.json'
$reportOut  = Join-Path $proofDir 'PHASE103_87_VERIFICATION_REPORT.md'

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
        throw "[phase103_87] $StepName failed with exit code $LASTEXITCODE"
    }
}

Write-Host '[phase103_87] Static source checks...'
Assert-True (Test-Path -LiteralPath $mainPath) '[phase103_87] main.cpp missing'
$mainText = Get-Content -LiteralPath $mainPath -Raw

$staticChecks = @(
    'BuilderFinalSystemValidationReleaseGateDiagnostics',
    'final_release_gate_diag',
    'run_phase103_87',
    'phase103_87_full_integrated_validation_passes',
    'phase103_87_release_gate_verdict',
    'phase103_87_final_canonical_signature',
    'loop.set_timeout(milliseconds(20700), [&] { run_phase103_87(); });'
)

$staticReport = @{}
$staticFail = $false
foreach ($token in $staticChecks) {
    $found = $mainText.Contains($token)
    $staticReport[$token] = $found
    if (-not $found) {
        Write-Host "[phase103_87] MISSING TOKEN: $token" -ForegroundColor Red
        $staticFail = $true
    }
}

$staticReport | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $staticOut -Encoding UTF8
Assert-True (-not $staticFail) '[phase103_87] Static token check failed.'
Write-Host '[phase103_87] All static tokens present.'

Write-Host '[phase103_87] Stopping running desktop_file_tool instances...'
Get-Process desktop_file_tool -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host '[phase103_87] Building desktop_file_tool...'
& (Join-Path $workspaceRoot '.venv/Scripts/python.exe') -m ngksgraph build --profile debug --msvc-auto --target desktop_file_tool *>&1 |
    Out-File -LiteralPath $buildOut -Encoding UTF8
Assert-True ($LASTEXITCODE -eq 0) '[phase103_87] Build-plan generation failed.'

Assert-True (Test-Path -LiteralPath $planPath) '[phase103_87] Build plan missing.'
$planJson = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json

$engineCompileNodes = @($planJson.nodes | Where-Object { $_.desc -like 'Compile engine/* for engine' })
$appCompileNode     = @($planJson.nodes | Where-Object { $_.desc -eq 'Compile apps/desktop_file_tool/main.cpp for desktop_file_tool' })[0]
$engineLibNode      = @($planJson.nodes | Where-Object { $_.desc -eq 'Link engine' })[0]
$appLinkNode        = @($planJson.nodes | Where-Object { $_.desc -eq 'Link desktop_file_tool' })[0]
Assert-True ($engineCompileNodes.Count -gt 0 -and $null -ne $appCompileNode -and $null -ne $engineLibNode -and $null -ne $appLinkNode) '[phase103_87] Required compile/link nodes missing.'

Initialize-PlanOutputDirectories -PlanJson $planJson
& (Join-Path $workspaceRoot 'tools/enter_msvc_env.ps1') *>&1 | Out-File -LiteralPath $buildOut -Append -Encoding UTF8

foreach ($node in $engineCompileNodes) {
    Invoke-CmdChecked -CommandLine $node.cmd -StepName $node.desc
}
Invoke-CmdChecked -CommandLine $appCompileNode.cmd -StepName $appCompileNode.desc
Invoke-CmdChecked -CommandLine $engineLibNode.cmd   -StepName $engineLibNode.desc
Invoke-CmdChecked -CommandLine $appLinkNode.cmd     -StepName $appLinkNode.desc

Assert-True (Test-Path -LiteralPath $exePath) '[phase103_87] Executable missing after compile/link.'
Write-Host '[phase103_87] Build OK.'

$requiredYes = @(
    'phase103_87_full_integrated_validation_passes',
    'phase103_87_harness_preconditions_block_invalid_targets_fail_closed',
    'phase103_87_all_locked_guarantees_remain_green_together',
    'phase103_87_final_canonical_signature_stable',
    'phase103_87_no_ui_desync_or_stale_state_detected',
    'phase103_87_no_partial_or_incomplete_proof_artifacts',
    'phase103_87_validation_terminates_cleanly',
    'phase103_87_release_gate_verdict_emitted',
    'phase103_87_release_ready_verdict_supported_by_evidence',
    'phase103_87_global_invariant_preserved'
)

Write-Host '[phase103_87] Running integrated validation gate...'
$proc = Start-Process -FilePath $exePath -ArgumentList @('--validation-mode', '--auto-close-ms=180000') -PassThru -WindowStyle Hidden -RedirectStandardOutput $runOut -RedirectStandardError $errOut
$proc.WaitForExit()

if (Test-Path -LiteralPath $errOut) {
    $stderrText = Get-Content -LiteralPath $errOut -Raw
    if (-not [string]::IsNullOrWhiteSpace($stderrText)) {
        Add-Content -LiteralPath $runOut -Value $stderrText
    }
}

$runExitCode = $proc.ExitCode
$runText = (Get-Content -LiteralPath $runOut -Raw) -replace "`r", ''
$markerMap = @{}
foreach ($line in ($runText -split "`n")) {
    if ($line -match '^([^=]+)=(.*)$') {
        $markerMap[$matches[1]] = $matches[2]
    }
}

$validationFailures = @()
foreach ($marker in $requiredYes) {
    if (-not ($markerMap.ContainsKey($marker) -and $markerMap[$marker] -eq 'YES')) {
        $validationFailures += "missing_or_failed_marker:$marker"
    }
}
if (-not ($markerMap.ContainsKey('phase103_87_release_gate_verdict') -and $markerMap['phase103_87_release_gate_verdict'] -eq 'RELEASE_READY')) {
    $validationFailures += 'release_verdict_not_release_ready'
}
if (-not ($markerMap.ContainsKey('phase103_87_final_canonical_signature') -and -not [string]::IsNullOrWhiteSpace($markerMap['phase103_87_final_canonical_signature']))) {
    $validationFailures += 'missing_final_canonical_signature'
}
if (-not ($markerMap.ContainsKey('app_runtime_crash_detected') -and $markerMap['app_runtime_crash_detected'] -eq '0')) {
    $validationFailures += 'runtime_crash_detected'
}
if (-not (($runText -split "`n") -contains 'SUMMARY: PASS')) {
    $validationFailures += 'missing_summary_pass'
}
if ($runExitCode -ne 0) {
    $validationFailures += ("validation_exit_code={0}" -f $runExitCode)
}

$lateBooleanMatches = [regex]::Matches($runText, '(?m)^(phase103_(6[3-9]|7[0-9]|8[0-7])_[^=]+)=(YES|NO)$')
$failedLateBooleanMarkers = @()
foreach ($match in $lateBooleanMatches) {
    if ($match.Groups[3].Value -eq 'NO') {
        $failedLateBooleanMarkers += $match.Groups[1].Value
    }
}
foreach ($failedMarker in $failedLateBooleanMarkers) {
    $validationFailures += ('late_boolean_marker_no:' + $failedMarker)
}

$results = @()
foreach ($marker in $requiredYes) {
    $results += [pscustomobject]@{ marker = $marker; value = $(if ($markerMap.ContainsKey($marker)) { $markerMap[$marker] } else { 'MISSING' }) }
}
$results += [pscustomobject]@{ marker = 'phase103_87_release_gate_verdict'; value = $(if ($markerMap.ContainsKey('phase103_87_release_gate_verdict')) { $markerMap['phase103_87_release_gate_verdict'] } else { 'MISSING' }) }
$results += [pscustomobject]@{ marker = 'phase103_87_final_canonical_signature'; value = $(if ($markerMap.ContainsKey('phase103_87_final_canonical_signature')) { $markerMap['phase103_87_final_canonical_signature'] } else { 'MISSING' }) }
$results += [pscustomobject]@{ marker = 'app_runtime_crash_detected'; value = $(if ($markerMap.ContainsKey('app_runtime_crash_detected')) { $markerMap['app_runtime_crash_detected'] } else { 'MISSING' }) }
$results += [pscustomobject]@{ marker = 'summary_pass_present'; value = $(if (($runText -split "`n") -contains 'SUMMARY: PASS') { 'PASS' } else { 'MISSING' }) }
$results += [pscustomobject]@{ marker = 'validation_exit_code'; value = [string]$runExitCode }
$results += [pscustomobject]@{ marker = 'late_boolean_marker_count'; value = [string]$lateBooleanMatches.Count }
$results += [pscustomobject]@{ marker = 'late_boolean_marker_failures'; value = [string]$failedLateBooleanMarkers.Count }

$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $markerOut -Encoding UTF8

$runnerCommand = 'pwsh -NoProfile -ExecutionPolicy Bypass -File tools/phase103_87_final_system_validation_release_gate_runner.ps1'
$phasePass = ($validationFailures.Count -eq 0)
$report = @()
$report += '# PHASE103_87 Final System Validation / Release Gate Report'
$report += ''
$report += "timestamp=$timestamp"
$report += "phase_status=$(if ($phasePass) { 'PASS' } else { 'FAIL' })"
$report += 'validation_scope=full_integrated_release_gate'
$report += "runner_command=$runnerCommand"
$report += "release_verdict=$(if ($markerMap.ContainsKey('phase103_87_release_gate_verdict')) { $markerMap['phase103_87_release_gate_verdict'] } else { 'MISSING' })"
$report += "final_canonical_signature=$(if ($markerMap.ContainsKey('phase103_87_final_canonical_signature')) { $markerMap['phase103_87_final_canonical_signature'] } else { 'MISSING' })"
$report += "validation_exit_code=$runExitCode"
$report += ''
$report += 'validation_failures:'
if ($validationFailures.Count -eq 0) {
    $report += '- none'
} else {
    foreach ($failure in $validationFailures) {
        $report += "- $failure"
    }
}
$report += ''
$report += 'required_markers:'
foreach ($result in $results) {
    $report += "- $($result.marker)=$($result.value)"
}
$report += ''
$report += 'artifacts:'
$report += '- phase103_87_static_checks.json'
$report += '- phase103_87_build_output.txt'
$report += '- phase103_87_runtime_output.txt'
$report += '- phase103_87_marker_results.json'
$report += '- PHASE103_87_VERIFICATION_REPORT.md'
$report -join "`r`n" | Set-Content -LiteralPath $reportOut -Encoding UTF8

$artifactPaths = @($staticOut, $buildOut, $runOut, $markerOut, $reportOut)
$artifactComplete = (@($artifactPaths | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 5)
Assert-True $artifactComplete '[phase103_87] Proof artifact generation incomplete.'

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $proofDir '*') -DestinationPath $zipPath -Force

if ($phasePass) {
    Write-Host '[phase103_87] PASS'
} else {
    Write-Host '[phase103_87] FAIL'
}
Write-Host "[phase103_87] Proof directory: $proofDir"
Write-Host "[phase103_87] Proof archive: $zipPath"

if (-not $phasePass) {
    exit 1
}