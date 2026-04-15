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
    Write-Host 'wrong workspace for phase103_86 runner'
    exit 1
}

$proofRoot  = Join-Path $workspaceRoot '_proof'
$timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName  = "phase103_86_validation_harness_precondition_hardening_${timestamp}"
$proofDir   = Join-Path $proofRoot $proofName
$zipPath    = Join-Path $proofRoot ($proofName + '.zip')

$buildOut   = Join-Path $proofDir 'phase103_86_build_output.txt'
$runOut     = Join-Path $proofDir 'phase103_86_runtime_output.txt'
$staticOut  = Join-Path $proofDir 'phase103_86_static_checks.json'
$markerOut  = Join-Path $proofDir 'phase103_86_marker_results.json'
$reportOut  = Join-Path $proofDir 'PHASE103_86_VERIFICATION_REPORT.md'

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
        throw "[phase103_86] $StepName failed with exit code $LASTEXITCODE"
    }
}

Write-Host '[phase103_86] Static source checks...'
Assert-True (Test-Path -LiteralPath $mainPath) '[phase103_86] main.cpp missing'
$mainText = Get-Content -LiteralPath $mainPath -Raw

$staticChecks = @(
    'BuilderValidationHarnessPreconditionHardeningDiagnostics',
    'ValidationHarnessTargetPreconditionResult',
    'evaluate_validation_harness_target_preconditions',
    'emit_validation_harness_precondition_failure',
    'validation_harness_precondition_failure=',
    'run_phase103_86',
    'phase103_86_every_harness_target_validates_renderability',
    'phase103_86_every_harness_target_validates_viewport_reachability',
    'phase103_86_invalid_targets_rejected_fail_closed',
    'phase103_86_unreachable_targets_rejected_fail_closed',
    'phase103_86_explicit_precondition_failure_marker_emitted',
    'phase103_86_validation_never_runs_on_unreachable_state',
    'phase103_86_no_runtime_behavior_changed',
    'phase103_86_global_invariant_preserved',
    'phase103_86_last_precondition_failure_marker',
    'loop.set_timeout(milliseconds(20500), [&] { run_phase103_86(); });',
    'phase76_block6',
    'viewport_unreachable',
    'not_renderable',
    'invalid_target'
)

$staticReport = @{}
$staticFail   = $false
foreach ($tok in $staticChecks) {
    $found = $mainText.Contains($tok)
    $staticReport[$tok] = $found
    if (-not $found) {
        Write-Host "[phase103_86] MISSING TOKEN: $tok" -ForegroundColor Red
        $staticFail = $true
    }
}
$staticReport | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $staticOut -Encoding UTF8
Assert-True (-not $staticFail) '[phase103_86] Static token check failed.'
Write-Host '[phase103_86] All static tokens present.'

Write-Host '[phase103_86] Stopping running desktop_file_tool instances...'
Get-Process desktop_file_tool -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host '[phase103_86] Building desktop_file_tool...'
& (Join-Path $workspaceRoot '.venv/Scripts/python.exe') -m ngksgraph build --profile debug --msvc-auto --target desktop_file_tool *>&1 |
    Out-File -LiteralPath $buildOut -Encoding UTF8
Assert-True ($LASTEXITCODE -eq 0) '[phase103_86] Build-plan generation failed.'

Assert-True (Test-Path -LiteralPath $planPath) '[phase103_86] Build plan missing.'
$planJson = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json

$engineCompileNodes = @($planJson.nodes | Where-Object { $_.desc -like 'Compile engine/* for engine' })
$appCompileNode     = @($planJson.nodes | Where-Object { $_.desc -eq 'Compile apps/desktop_file_tool/main.cpp for desktop_file_tool' })[0]
$engineLibNode      = @($planJson.nodes | Where-Object { $_.desc -eq 'Link engine' })[0]
$appLinkNode        = @($planJson.nodes | Where-Object { $_.desc -eq 'Link desktop_file_tool' })[0]
Assert-True ($engineCompileNodes.Count -gt 0 -and $null -ne $appCompileNode -and $null -ne $engineLibNode -and $null -ne $appLinkNode) '[phase103_86] Required compile/link nodes missing.'

Initialize-PlanOutputDirectories -PlanJson $planJson
& (Join-Path $workspaceRoot 'tools/enter_msvc_env.ps1') *>&1 | Out-File -LiteralPath $buildOut -Append -Encoding UTF8

foreach ($node in $engineCompileNodes) {
    Invoke-CmdChecked -CommandLine $node.cmd -StepName $node.desc
}
Invoke-CmdChecked -CommandLine $appCompileNode.cmd -StepName $appCompileNode.desc
Invoke-CmdChecked -CommandLine $engineLibNode.cmd   -StepName $engineLibNode.desc
Invoke-CmdChecked -CommandLine $appLinkNode.cmd     -StepName $appLinkNode.desc

Assert-True (Test-Path -LiteralPath $exePath) '[phase103_86] Executable missing after compile/link.'
Write-Host '[phase103_86] Build OK.'

Write-Host '[phase103_86] Running validation mode...'
$exeQuoted = '"' + $exePath + '"'
$runOutQuoted = '"' + $runOut + '"'
cmd /c "$exeQuoted --validation-mode --validation-target-phase=86 --auto-close-ms=30000 > $runOutQuoted 2>&1"
Assert-True ($LASTEXITCODE -eq 0) '[phase103_86] Validation run failed.'
$runText = (Get-Content -LiteralPath $runOut -Raw) -replace "`r", ''

function MarkerEqualsYes {
    param([string]$Name)
    return [regex]::IsMatch($runText, "(?m)^$([regex]::Escape($Name))=YES$")
}

$requiredYes = @(
    'phase103_86_every_harness_target_validates_renderability',
    'phase103_86_every_harness_target_validates_viewport_reachability',
    'phase103_86_invalid_targets_rejected_fail_closed',
    'phase103_86_unreachable_targets_rejected_fail_closed',
    'phase103_86_explicit_precondition_failure_marker_emitted',
    'phase103_86_validation_never_runs_on_unreachable_state',
    'phase103_86_no_runtime_behavior_changed',
    'phase103_86_global_invariant_preserved'
)

$results  = @()
$allYes   = $true
foreach ($m in $requiredYes) {
    $ok = MarkerEqualsYes -Name $m
    if (-not $ok) { $allYes = $false }
    $results += [pscustomobject]@{ marker = $m; value = $(if ($ok) { 'YES' } else { 'NO' }) }
}

$explicitFailureMarkerPresent = [regex]::IsMatch($runText, '(?m)^validation_harness_precondition_failure=phase103_86:')
$phase76GuardMarkerPresent = [regex]::IsMatch($runText, '(?m)^phase103_86_last_precondition_failure_marker=validation_harness_precondition_failure=phase103_86:')
$crashFree   = [regex]::IsMatch($runText, '(?m)^app_runtime_crash_detected=0$')
$summaryPass = [regex]::IsMatch($runText, '(?m)^SUMMARY: PASS$')

$results += [pscustomobject]@{ marker = 'phase103_86_explicit_failure_marker_present'; value = $(if ($explicitFailureMarkerPresent) { 'YES' } else { 'NO' }) }
$results += [pscustomobject]@{ marker = 'phase103_86_last_failure_marker_summary_present'; value = $(if ($phase76GuardMarkerPresent) { 'YES' } else { 'NO' }) }
$results += [pscustomobject]@{ marker = 'app_runtime_crash_detected'; value = $(if ($crashFree) { 0 } else { 1 }) }
$results += [pscustomobject]@{ marker = 'summary_pass_present'; value = $(if ($summaryPass) { 'PASS' } else { 'FAIL' }) }

$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $markerOut -Encoding UTF8

$phasePass = $allYes -and $explicitFailureMarkerPresent -and $phase76GuardMarkerPresent -and $crashFree -and $summaryPass

$report  = @()
$report += '# PHASE103_86 Validation Harness Precondition Hardening Verification Report'
$report += ''
$report += "timestamp=$timestamp"
$report += "phase_status=$(if ($phasePass) { 'PASS' } else { 'FAIL' })"
$report += ''
$report += 'required_markers:'
foreach ($r in $results) {
    $report += "- $($r.marker)=$($r.value)"
}
$report += ''
$report += 'artifacts:'
$report += '- phase103_86_static_checks.json'
$report += '- phase103_86_build_output.txt'
$report += '- phase103_86_runtime_output.txt'
$report += '- phase103_86_marker_results.json'
$report -join "`r`n" | Set-Content -LiteralPath $reportOut -Encoding UTF8

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $proofDir '*') -DestinationPath $zipPath -Force

if (-not $phasePass) {
    throw '[phase103_86] Marker verification failed.'
}

Write-Host '[phase103_86] PASS'
Write-Host "[phase103_86] Proof directory: $proofDir"
Write-Host "[phase103_86] Proof archive: $zipPath"