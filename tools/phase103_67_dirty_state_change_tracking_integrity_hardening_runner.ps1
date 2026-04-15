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
    Write-Host 'wrong workspace for phase103_67 runner'
    exit 1
}

$proofRoot  = Join-Path $workspaceRoot '_proof'
$timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName  = "phase103_67_dirty_state_change_tracking_integrity_hardening_${timestamp}"
$proofDir   = Join-Path $proofRoot $proofName
$zipPath    = Join-Path $proofRoot ($proofName + '.zip')

$buildOut   = Join-Path $proofDir 'phase103_67_build_output.txt'
$runOut     = Join-Path $proofDir 'phase103_67_runtime_output.txt'
$staticOut  = Join-Path $proofDir 'phase103_67_static_checks.json'
$markerOut  = Join-Path $proofDir 'phase103_67_marker_results.json'
$reportOut  = Join-Path $proofDir 'PHASE103_67_VERIFICATION_REPORT.md'

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
        throw "[phase103_67] $StepName failed with exit code $LASTEXITCODE"
    }
}

Write-Host '[phase103_67] Static source checks...'
Assert-True (Test-Path -LiteralPath $mainPath) '[phase103_67] main.cpp missing'
$mainText = Get-Content -LiteralPath $mainPath -Raw

$staticChecks = @(
    'BuilderDirtyStateChangeTrackingIntegrityHardeningDiagnostics',
    'dirty_tracking_integrity_diag',
    'has_clean_builder_baseline_signature',
    'clean_builder_baseline_signature',
    'run_phase103_67',
    'phase103_67_real_mutations_mark_dirty_exactly',
    'phase103_67_read_only_operations_do_not_mark_dirty',
    'phase103_67_undo_back_to_clean_clears_dirty',
    'phase103_67_redo_away_from_clean_sets_dirty',
    'phase103_67_save_sets_new_clean_baseline_exactly',
    'phase103_67_load_sets_new_clean_baseline_exactly',
    'phase103_67_failed_save_load_or_blocked_mutation_do_not_corrupt_dirty_state',
    'phase103_67_export_does_not_affect_dirty_state',
    'phase103_67_dirty_tracking_uses_canonical_document_signature',
    'phase103_67_stress_sequence_dirty_transitions_remain_exact',
    'milliseconds(16700)'
)

$staticReport = @{}
$staticFail   = $false
foreach ($tok in $staticChecks) {
    $found = $mainText.Contains($tok)
    $staticReport[$tok] = $found
    if (-not $found) {
        Write-Host "[phase103_67] MISSING TOKEN: $tok" -ForegroundColor Red
        $staticFail = $true
    }
}
$staticReport | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $staticOut -Encoding UTF8
Assert-True (-not $staticFail) '[phase103_67] Static token check failed.'
Write-Host '[phase103_67] All static tokens present.'

Write-Host '[phase103_67] Stopping running desktop_file_tool instances...'
Get-Process desktop_file_tool -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host '[phase103_67] Building desktop_file_tool...'
& (Join-Path $workspaceRoot '.venv/Scripts/python.exe') -m ngksgraph build --profile debug --msvc-auto --target desktop_file_tool *>&1 |
    Out-File -LiteralPath $buildOut -Encoding UTF8
Assert-True ($LASTEXITCODE -eq 0) '[phase103_67] Build-plan generation failed.'

Assert-True (Test-Path -LiteralPath $planPath) '[phase103_67] Build plan missing.'
$planJson = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json

$engineCompileNodes = @($planJson.nodes | Where-Object { $_.desc -like 'Compile engine/* for engine' })
$appCompileNode     = @($planJson.nodes | Where-Object { $_.desc -eq 'Compile apps/desktop_file_tool/main.cpp for desktop_file_tool' })[0]
$engineLibNode      = @($planJson.nodes | Where-Object { $_.desc -eq 'Link engine' })[0]
$appLinkNode        = @($planJson.nodes | Where-Object { $_.desc -eq 'Link desktop_file_tool' })[0]
Assert-True ($engineCompileNodes.Count -gt 0 -and $null -ne $appCompileNode -and $null -ne $engineLibNode -and $null -ne $appLinkNode) '[phase103_67] Required compile/link nodes missing.'

Initialize-PlanOutputDirectories -PlanJson $planJson
& (Join-Path $workspaceRoot 'tools/enter_msvc_env.ps1') *>&1 | Out-File -LiteralPath $buildOut -Append -Encoding UTF8

foreach ($node in $engineCompileNodes) {
    Invoke-CmdChecked -CommandLine $node.cmd -StepName $node.desc
}
Invoke-CmdChecked -CommandLine $appCompileNode.cmd -StepName $appCompileNode.desc
Invoke-CmdChecked -CommandLine $engineLibNode.cmd   -StepName $engineLibNode.desc
Invoke-CmdChecked -CommandLine $appLinkNode.cmd     -StepName $appLinkNode.desc

Assert-True (Test-Path -LiteralPath $exePath) '[phase103_67] Executable missing after compile/link.'
Write-Host '[phase103_67] Build OK.'

Write-Host '[phase103_67] Running validation mode...'
& $exePath --validation-mode --auto-close-ms=46000 *>&1 | Out-File -LiteralPath $runOut -Encoding UTF8
Assert-True ($LASTEXITCODE -eq 0) '[phase103_67] Validation run failed.'
$runText = (Get-Content -LiteralPath $runOut -Raw) -replace "`r", ''

function MarkerEqualsYes {
    param([string]$Name)
    return [regex]::IsMatch($runText, "(?m)^$([regex]::Escape($Name))=YES$")
}

$requiredYes = @(
    'phase103_67_real_mutations_mark_dirty_exactly',
    'phase103_67_read_only_operations_do_not_mark_dirty',
    'phase103_67_undo_back_to_clean_clears_dirty',
    'phase103_67_redo_away_from_clean_sets_dirty',
    'phase103_67_save_sets_new_clean_baseline_exactly',
    'phase103_67_load_sets_new_clean_baseline_exactly',
    'phase103_67_failed_save_load_or_blocked_mutation_do_not_corrupt_dirty_state',
    'phase103_67_export_does_not_affect_dirty_state',
    'phase103_67_dirty_tracking_uses_canonical_document_signature',
    'phase103_67_stress_sequence_dirty_transitions_remain_exact'
)

$results  = @()
$allYes   = $true
foreach ($m in $requiredYes) {
    $ok = MarkerEqualsYes -Name $m
    if (-not $ok) { $allYes = $false }
    $results += [pscustomobject]@{ marker = $m; value = $(if ($ok) { 'YES' } else { 'NO' }) }
}

$crashFree   = [regex]::IsMatch($runText, '(?m)^app_runtime_crash_detected=0$')
$summaryPass = [regex]::IsMatch($runText, '(?m)^SUMMARY: PASS$')
$results += [pscustomobject]@{ marker = 'app_runtime_crash_detected'; value = $(if ($crashFree) { 0 } else { 1 }) }
$results += [pscustomobject]@{ marker = 'summary_pass_present';       value = $(if ($summaryPass) { 'PASS' } else { 'FAIL' }) }

$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $markerOut -Encoding UTF8

$phasePass = $allYes -and $crashFree -and $summaryPass

$report  = @()
$report += '# PHASE103_67 Dirty State / Change Tracking Integrity Hardening Verification Report'
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
$report += '- phase103_67_static_checks.json'
$report += '- phase103_67_build_output.txt'
$report += '- phase103_67_runtime_output.txt'
$report += '- phase103_67_marker_results.json'
$report -join "`r`n" | Set-Content -LiteralPath $reportOut -Encoding UTF8

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $proofDir '*') -DestinationPath $zipPath -Force

if (-not $phasePass) {
    throw '[phase103_67] Marker verification failed.'
}

Write-Host '[phase103_67] PASS'
Write-Host "[phase103_67] Proof directory: $proofDir"
Write-Host "[phase103_67] Proof archive: $zipPath"
