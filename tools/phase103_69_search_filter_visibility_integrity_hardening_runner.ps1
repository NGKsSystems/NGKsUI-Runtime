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
    Write-Host 'wrong workspace for phase103_69 runner'
    exit 1
}

$proofRoot  = Join-Path $workspaceRoot '_proof'
$timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName  = "phase103_69_search_filter_visibility_integrity_hardening_${timestamp}"
$proofDir   = Join-Path $proofRoot $proofName
$zipPath    = Join-Path $proofRoot ($proofName + '.zip')

$buildOut   = Join-Path $proofDir 'phase103_69_build_output.txt'
$runOut     = Join-Path $proofDir 'phase103_69_runtime_output.txt'
$staticOut  = Join-Path $proofDir 'phase103_69_static_checks.json'
$markerOut  = Join-Path $proofDir 'phase103_69_marker_results.json'
$reportOut  = Join-Path $proofDir 'PHASE103_69_VERIFICATION_REPORT.md'

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
        throw "[phase103_69] $StepName failed with exit code $LASTEXITCODE"
    }
}

Write-Host '[phase103_69] Static source checks...'
Assert-True (Test-Path -LiteralPath $mainPath) '[phase103_69] main.cpp missing'
$mainText = Get-Content -LiteralPath $mainPath -Raw

$staticChecks = @(
    'BuilderSearchFilterVisibilityIntegrityHardeningDiagnostics',
    'search_filter_visibility_integrity_diag',
    'builder_projection_filter_query',
    'builder_node_matches_projection_query',
    'run_phase103_69',
    'phase103_69_search_filter_read_only_no_document_mutation',
    'phase103_69_filtered_order_matches_authoritative_structure_order',
    'phase103_69_selection_mapping_remains_deterministic_under_filter_changes',
    'phase103_69_no_stale_deleted_or_moved_nodes_in_results',
    'phase103_69_actions_from_filtered_view_resolve_against_authoritative_current_state',
    'phase103_69_clear_and_reapply_filter_restores_coherent_visible_state',
    'phase103_69_search_filter_creates_no_history_or_dirty_side_effect',
    'phase103_69_preview_and_bindings_remain_coherent_under_filtered_view',
    'phase103_69_filtered_and_unfiltered_action_results_match_for_same_underlying_state',
    'phase103_69_global_invariant_preserved_through_search_filter_cycles',
    'milliseconds(17100)'
)

$staticReport = @{}
$staticFail   = $false
foreach ($tok in $staticChecks) {
    $found = $mainText.Contains($tok)
    $staticReport[$tok] = $found
    if (-not $found) {
        Write-Host "[phase103_69] MISSING TOKEN: $tok" -ForegroundColor Red
        $staticFail = $true
    }
}
$staticReport | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $staticOut -Encoding UTF8
Assert-True (-not $staticFail) '[phase103_69] Static token check failed.'
Write-Host '[phase103_69] All static tokens present.'

Write-Host '[phase103_69] Stopping running desktop_file_tool instances...'
Get-Process desktop_file_tool -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host '[phase103_69] Building desktop_file_tool...'
& (Join-Path $workspaceRoot '.venv/Scripts/python.exe') -m ngksgraph build --profile debug --msvc-auto --target desktop_file_tool *>&1 |
    Out-File -LiteralPath $buildOut -Encoding UTF8
Assert-True ($LASTEXITCODE -eq 0) '[phase103_69] Build-plan generation failed.'

Assert-True (Test-Path -LiteralPath $planPath) '[phase103_69] Build plan missing.'
$planJson = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json

$engineCompileNodes = @($planJson.nodes | Where-Object { $_.desc -like 'Compile engine/* for engine' })
$appCompileNode     = @($planJson.nodes | Where-Object { $_.desc -eq 'Compile apps/desktop_file_tool/main.cpp for desktop_file_tool' })[0]
$engineLibNode      = @($planJson.nodes | Where-Object { $_.desc -eq 'Link engine' })[0]
$appLinkNode        = @($planJson.nodes | Where-Object { $_.desc -eq 'Link desktop_file_tool' })[0]
Assert-True ($engineCompileNodes.Count -gt 0 -and $null -ne $appCompileNode -and $null -ne $engineLibNode -and $null -ne $appLinkNode) '[phase103_69] Required compile/link nodes missing.'

Initialize-PlanOutputDirectories -PlanJson $planJson
& (Join-Path $workspaceRoot 'tools/enter_msvc_env.ps1') *>&1 | Out-File -LiteralPath $buildOut -Append -Encoding UTF8

foreach ($node in $engineCompileNodes) {
    Invoke-CmdChecked -CommandLine $node.cmd -StepName $node.desc
}
Invoke-CmdChecked -CommandLine $appCompileNode.cmd -StepName $appCompileNode.desc
Invoke-CmdChecked -CommandLine $engineLibNode.cmd   -StepName $engineLibNode.desc
Invoke-CmdChecked -CommandLine $appLinkNode.cmd     -StepName $appLinkNode.desc

Assert-True (Test-Path -LiteralPath $exePath) '[phase103_69] Executable missing after compile/link.'
Write-Host '[phase103_69] Build OK.'

Write-Host '[phase103_69] Running validation mode...'
& $exePath --validation-mode --auto-close-ms=47000 *>&1 | Out-File -LiteralPath $runOut -Encoding UTF8
Assert-True ($LASTEXITCODE -eq 0) '[phase103_69] Validation run failed.'
$runText = (Get-Content -LiteralPath $runOut -Raw) -replace "`r", ''

function MarkerEqualsYes {
    param([string]$Name)
    return [regex]::IsMatch($runText, "(?m)^$([regex]::Escape($Name))=YES$")
}

$requiredYes = @(
    'phase103_69_search_filter_read_only_no_document_mutation',
    'phase103_69_filtered_order_matches_authoritative_structure_order',
    'phase103_69_selection_mapping_remains_deterministic_under_filter_changes',
    'phase103_69_no_stale_deleted_or_moved_nodes_in_results',
    'phase103_69_actions_from_filtered_view_resolve_against_authoritative_current_state',
    'phase103_69_clear_and_reapply_filter_restores_coherent_visible_state',
    'phase103_69_search_filter_creates_no_history_or_dirty_side_effect',
    'phase103_69_preview_and_bindings_remain_coherent_under_filtered_view',
    'phase103_69_filtered_and_unfiltered_action_results_match_for_same_underlying_state',
    'phase103_69_global_invariant_preserved_through_search_filter_cycles'
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
$report += '# PHASE103_69 Search / Filter / Visibility Integrity Hardening Verification Report'
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
$report += '- phase103_69_static_checks.json'
$report += '- phase103_69_build_output.txt'
$report += '- phase103_69_runtime_output.txt'
$report += '- phase103_69_marker_results.json'
$report -join "`r`n" | Set-Content -LiteralPath $reportOut -Encoding UTF8

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $proofDir '*') -DestinationPath $zipPath -Force

if (-not $phasePass) {
    throw '[phase103_69] Marker verification failed.'
}

Write-Host '[phase103_69] PASS'
Write-Host "[phase103_69] Proof directory: $proofDir"
Write-Host "[phase103_69] Proof archive: $zipPath"
