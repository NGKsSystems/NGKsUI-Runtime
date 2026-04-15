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
    Write-Host 'wrong workspace for phase103_70 runner'
    exit 1
}

$proofRoot  = Join-Path $workspaceRoot '_proof'
$timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName  = "phase103_70_selection_anchor_focus_navigation_integrity_hardening_${timestamp}"
$proofDir   = Join-Path $proofRoot $proofName
$zipPath    = Join-Path $proofRoot ($proofName + '.zip')

$buildOut   = Join-Path $proofDir 'phase103_70_build_output.txt'
$runOut     = Join-Path $proofDir 'phase103_70_runtime_output.txt'
$staticOut  = Join-Path $proofDir 'phase103_70_static_checks.json'
$markerOut  = Join-Path $proofDir 'phase103_70_marker_results.json'
$reportOut  = Join-Path $proofDir 'PHASE103_70_VERIFICATION_REPORT.md'

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
        throw "[phase103_70] $StepName failed with exit code $LASTEXITCODE"
    }
}

Write-Host '[phase103_70] Static source checks...'
Assert-True (Test-Path -LiteralPath $mainPath) '[phase103_70] main.cpp missing'
$mainText = Get-Content -LiteralPath $mainPath -Raw

$staticChecks = @(
    'BuilderSelectionAnchorFocusNavigationIntegrityHardeningDiagnostics',
    'selection_anchor_focus_navigation_integrity_diag',
    'builder_selection_anchor_node_id',
    'build_authoritative_selection_range',
    'run_phase103_70',
    'phase103_70_authoritative_order_navigation_matches_document_structure',
    'phase103_70_selection_anchor_establishes_deterministic_range_extent',
    'phase103_70_focus_only_navigation_does_not_mutate_selection_or_document',
    'phase103_70_stale_anchor_and_focus_are_scrubbed_fail_closed',
    'phase103_70_selection_focus_coherence_restored_after_filter_and_lifecycle_changes',
    'phase103_70_navigation_only_changes_create_no_history_or_dirty_side_effect',
    'phase103_70_parent_child_navigation_respects_authoritative_current_state',
    'phase103_70_range_extension_shrinks_and_grows_deterministically_from_same_anchor',
    'phase103_70_filtered_and_unfiltered_navigation_resolve_same_underlying_targets',
    'phase103_70_global_invariant_preserved_through_anchor_focus_navigation_cycles',
    'milliseconds(17300)'
)

$staticReport = @{}
$staticFail   = $false
foreach ($tok in $staticChecks) {
    $found = $mainText.Contains($tok)
    $staticReport[$tok] = $found
    if (-not $found) {
        Write-Host "[phase103_70] MISSING TOKEN: $tok" -ForegroundColor Red
        $staticFail = $true
    }
}
$staticReport | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $staticOut -Encoding UTF8
Assert-True (-not $staticFail) '[phase103_70] Static token check failed.'
Write-Host '[phase103_70] All static tokens present.'

Write-Host '[phase103_70] Stopping running desktop_file_tool instances...'
Get-Process desktop_file_tool -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host '[phase103_70] Building desktop_file_tool...'
& (Join-Path $workspaceRoot '.venv/Scripts/python.exe') -m ngksgraph build --profile debug --msvc-auto --target desktop_file_tool *>&1 |
    Out-File -LiteralPath $buildOut -Encoding UTF8
Assert-True ($LASTEXITCODE -eq 0) '[phase103_70] Build-plan generation failed.'

Assert-True (Test-Path -LiteralPath $planPath) '[phase103_70] Build plan missing.'
$planJson = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json

$engineCompileNodes = @($planJson.nodes | Where-Object { $_.desc -like 'Compile engine/* for engine' })
$appCompileNode     = @($planJson.nodes | Where-Object { $_.desc -eq 'Compile apps/desktop_file_tool/main.cpp for desktop_file_tool' })[0]
$engineLibNode      = @($planJson.nodes | Where-Object { $_.desc -eq 'Link engine' })[0]
$appLinkNode        = @($planJson.nodes | Where-Object { $_.desc -eq 'Link desktop_file_tool' })[0]
Assert-True ($engineCompileNodes.Count -gt 0 -and $null -ne $appCompileNode -and $null -ne $engineLibNode -and $null -ne $appLinkNode) '[phase103_70] Required compile/link nodes missing.'

Initialize-PlanOutputDirectories -PlanJson $planJson
& (Join-Path $workspaceRoot 'tools/enter_msvc_env.ps1') *>&1 | Out-File -LiteralPath $buildOut -Append -Encoding UTF8

foreach ($node in $engineCompileNodes) {
    Invoke-CmdChecked -CommandLine $node.cmd -StepName $node.desc
}
Invoke-CmdChecked -CommandLine $appCompileNode.cmd -StepName $appCompileNode.desc
Invoke-CmdChecked -CommandLine $engineLibNode.cmd   -StepName $engineLibNode.desc
Invoke-CmdChecked -CommandLine $appLinkNode.cmd     -StepName $appLinkNode.desc

Assert-True (Test-Path -LiteralPath $exePath) '[phase103_70] Executable missing after compile/link.'
Write-Host '[phase103_70] Build OK.'

Write-Host '[phase103_70] Running validation mode...'
& $exePath --validation-mode --auto-close-ms=47000 *>&1 | Out-File -LiteralPath $runOut -Encoding UTF8
Assert-True ($LASTEXITCODE -eq 0) '[phase103_70] Validation run failed.'
$runText = (Get-Content -LiteralPath $runOut -Raw) -replace "`r", ''

function MarkerEqualsYes {
    param([string]$Name)
    return [regex]::IsMatch($runText, "(?m)^$([regex]::Escape($Name))=YES$")
}

$requiredYes = @(
    'phase103_70_authoritative_order_navigation_matches_document_structure',
    'phase103_70_selection_anchor_establishes_deterministic_range_extent',
    'phase103_70_focus_only_navigation_does_not_mutate_selection_or_document',
    'phase103_70_stale_anchor_and_focus_are_scrubbed_fail_closed',
    'phase103_70_selection_focus_coherence_restored_after_filter_and_lifecycle_changes',
    'phase103_70_navigation_only_changes_create_no_history_or_dirty_side_effect',
    'phase103_70_parent_child_navigation_respects_authoritative_current_state',
    'phase103_70_range_extension_shrinks_and_grows_deterministically_from_same_anchor',
    'phase103_70_filtered_and_unfiltered_navigation_resolve_same_underlying_targets',
    'phase103_70_global_invariant_preserved_through_anchor_focus_navigation_cycles'
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
$report += '# PHASE103_70 Selection Anchor / Focus Navigation Integrity Hardening Verification Report'
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
$report += '- phase103_70_static_checks.json'
$report += '- phase103_70_build_output.txt'
$report += '- phase103_70_runtime_output.txt'
$report += '- phase103_70_marker_results.json'
$report -join "`r`n" | Set-Content -LiteralPath $reportOut -Encoding UTF8

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $proofDir '*') -DestinationPath $zipPath -Force

if (-not $phasePass) {
    throw '[phase103_70] Marker verification failed.'
}

Write-Host '[phase103_70] PASS'
Write-Host "[phase103_70] Proof directory: $proofDir"
Write-Host "[phase103_70] Proof archive: $zipPath"
