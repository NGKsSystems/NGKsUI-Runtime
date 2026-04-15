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
    Write-Host 'wrong workspace for phase103_82 runner'
    exit 1
}

$proofRoot  = Join-Path $workspaceRoot '_proof'
$timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName  = "phase103_82_event_input_throttling_coalescing_${timestamp}"
$proofDir   = Join-Path $proofRoot $proofName
$zipPath    = Join-Path $proofRoot ($proofName + '.zip')

$buildOut   = Join-Path $proofDir 'phase103_82_build_output.txt'
$runOut     = Join-Path $proofDir 'phase103_82_runtime_output.txt'
$staticOut  = Join-Path $proofDir 'phase103_82_static_checks.json'
$markerOut  = Join-Path $proofDir 'phase103_82_marker_results.json'
$reportOut  = Join-Path $proofDir 'PHASE103_82_VERIFICATION_REPORT.md'

$planPath   = Join-Path $workspaceRoot 'build_graph/debug/ngksbuildcore_plan.json'
$exePath    = Join-Path $workspaceRoot 'build/debug/bin/desktop_file_tool.exe'
$mainPath   = Join-Path $workspaceRoot 'apps/desktop_file_tool/main.cpp'
$treePath   = Join-Path $workspaceRoot 'engine/ui/ui_tree.hpp'
$scrollPath = Join-Path $workspaceRoot 'engine/ui/scroll_container.hpp'

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
        throw "[phase103_82] $StepName failed with exit code $LASTEXITCODE"
    }
}

Write-Host '[phase103_82] Static source checks...'
Assert-True (Test-Path -LiteralPath $mainPath) '[phase103_82] main.cpp missing'
Assert-True (Test-Path -LiteralPath $treePath) '[phase103_82] ui_tree.hpp missing'
Assert-True (Test-Path -LiteralPath $scrollPath) '[phase103_82] scroll_container.hpp missing'
$mainText = Get-Content -LiteralPath $mainPath -Raw
$treeText = Get-Content -LiteralPath $treePath -Raw
$scrollText = Get-Content -LiteralPath $scrollPath -Raw

$staticChecks = @(
    @{ Token = 'BuilderEventInputThrottlingCoalescingDiagnostics'; Text = $mainText },
    @{ Token = 'event_input_throttling_diag'; Text = $mainText },
    @{ Token = 'run_phase103_82'; Text = $mainText },
    @{ Token = 'phase103_82_high_frequency_event_work_reduced_vs_phase103_77'; Text = $mainText },
    @{ Token = 'phase103_82_redundant_invalidates_or_refreshes_coalesced_without_behavior_change'; Text = $mainText },
    @{ Token = 'phase103_82_hover_drag_scroll_visible_behavior_identical_to_baseline'; Text = $mainText },
    @{ Token = 'phase103_82_selection_focus_and_viewport_results_identical_after_event_bursts'; Text = $mainText },
    @{ Token = 'phase103_82_drag_preview_and_drop_outcome_identical_to_baseline'; Text = $mainText },
    @{ Token = 'phase103_82_no_stale_ui_state_after_rapid_input_sequences'; Text = $mainText },
    @{ Token = 'phase103_82_no_history_or_dirty_side_effect_from_event_coalescing'; Text = $mainText },
    @{ Token = 'phase103_82_no_correctness_guarantees_were_weakened'; Text = $mainText },
    @{ Token = 'phase103_82_profile_run_terminates_cleanly_with_markers'; Text = $mainText },
    @{ Token = 'phase103_82_global_invariant_preserved'; Text = $mainText },
    @{ Token = 'phase103_82_optimized_event_work_count'; Text = $mainText },
    @{ Token = 'phase103_82_high_frequency_repaint_requests_coalesced'; Text = $mainText },
    @{ Token = 'milliseconds(19700)'; Text = $mainText },
    @{ Token = '!was_dirty'; Text = $treeText },
    @{ Token = 'return scroll_y_ != old_scroll_y;'; Text = $scrollText },
    @{ Token = 'ui_tree_dirty_transition_repaint_coalescing_high_frequency_followup_layout_and_no_op_hover_drag_scroll_suppression'; Text = $mainText }
)

$staticReport = @{}
$staticFail   = $false
foreach ($entry in $staticChecks) {
    $found = $entry.Text.Contains($entry.Token)
    $staticReport[$entry.Token] = $found
    if (-not $found) {
        Write-Host "[phase103_82] MISSING TOKEN: $($entry.Token)" -ForegroundColor Red
        $staticFail = $true
    }
}

$staticReport | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $staticOut -Encoding UTF8
Assert-True (-not $staticFail) '[phase103_82] Static token check failed.'
Write-Host '[phase103_82] All static tokens present.'

Write-Host '[phase103_82] Stopping running desktop_file_tool instances...'
Get-Process desktop_file_tool -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host '[phase103_82] Building desktop_file_tool...'
& (Join-Path $workspaceRoot '.venv/Scripts/python.exe') -m ngksgraph build --profile debug --msvc-auto --target desktop_file_tool *>&1 |
    Out-File -LiteralPath $buildOut -Encoding UTF8
Assert-True ($LASTEXITCODE -eq 0) '[phase103_82] Build-plan generation failed.'

Assert-True (Test-Path -LiteralPath $planPath) '[phase103_82] Build plan missing.'
$planJson = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json

$engineCompileNodes = @($planJson.nodes | Where-Object { $_.desc -like 'Compile engine/* for engine' })
$appCompileNode     = @($planJson.nodes | Where-Object { $_.desc -eq 'Compile apps/desktop_file_tool/main.cpp for desktop_file_tool' })[0]
$engineLibNode      = @($planJson.nodes | Where-Object { $_.desc -eq 'Link engine' })[0]
$appLinkNode        = @($planJson.nodes | Where-Object { $_.desc -eq 'Link desktop_file_tool' })[0]
Assert-True ($engineCompileNodes.Count -gt 0 -and $null -ne $appCompileNode -and $null -ne $engineLibNode -and $null -ne $appLinkNode) '[phase103_82] Required compile/link nodes missing.'

Initialize-PlanOutputDirectories -PlanJson $planJson
& (Join-Path $workspaceRoot 'tools/enter_msvc_env.ps1') *>&1 | Out-File -LiteralPath $buildOut -Append -Encoding UTF8

foreach ($node in $engineCompileNodes) {
    Invoke-CmdChecked -CommandLine $node.cmd -StepName $node.desc
}
Invoke-CmdChecked -CommandLine $appCompileNode.cmd -StepName $appCompileNode.desc
Invoke-CmdChecked -CommandLine $engineLibNode.cmd   -StepName $engineLibNode.desc
Invoke-CmdChecked -CommandLine $appLinkNode.cmd     -StepName $appLinkNode.desc

Assert-True (Test-Path -LiteralPath $exePath) '[phase103_82] Executable missing after compile/link.'
Write-Host '[phase103_82] Build OK.'

Write-Host '[phase103_82] Running validation mode...'
$exeQuoted = '"' + $exePath + '"'
$runOutQuoted = '"' + $runOut + '"'
cmd /c "$exeQuoted --validation-mode --auto-close-ms=150000 > $runOutQuoted 2>&1"
Assert-True ($LASTEXITCODE -eq 0) '[phase103_82] Validation run failed.'
$runText = (Get-Content -LiteralPath $runOut -Raw) -replace "`r", ''

function MarkerEqualsYes {
    param([string]$Name)
    return [regex]::IsMatch($runText, "(?m)^$([regex]::Escape($Name))=YES$")
}

$requiredYes = @(
    'phase103_82_high_frequency_event_work_reduced_vs_phase103_77',
    'phase103_82_redundant_invalidates_or_refreshes_coalesced_without_behavior_change',
    'phase103_82_hover_drag_scroll_visible_behavior_identical_to_baseline',
    'phase103_82_selection_focus_and_viewport_results_identical_after_event_bursts',
    'phase103_82_drag_preview_and_drop_outcome_identical_to_baseline',
    'phase103_82_no_stale_ui_state_after_rapid_input_sequences',
    'phase103_82_no_history_or_dirty_side_effect_from_event_coalescing',
    'phase103_82_no_correctness_guarantees_were_weakened',
    'phase103_82_profile_run_terminates_cleanly_with_markers',
    'phase103_82_global_invariant_preserved'
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

$profileLines = @([regex]::Matches($runText, '(?m)^phase103_82_[^\n]+$') | ForEach-Object { $_.Value })

$phasePass = $allYes -and $crashFree -and $summaryPass -and ($profileLines.Count -gt 0)

$report  = @()
$report += '# PHASE103_82 Event / Input Throttling & Coalescing Verification Report'
$report += ''
$report += "timestamp=$timestamp"
$report += "phase_status=$(if ($phasePass) { 'PASS' } else { 'FAIL' })"
$report += ''
$report += 'required_markers:'
foreach ($r in $results) {
    $report += "- $($r.marker)=$($r.value)"
}
$report += ''
$report += 'profile_summary:'
foreach ($line in $profileLines) {
    $report += "- $line"
}
$report += ''
$report += 'artifacts:'
$report += '- phase103_82_static_checks.json'
$report += '- phase103_82_build_output.txt'
$report += '- phase103_82_runtime_output.txt'
$report += '- phase103_82_marker_results.json'
$report -join "`r`n" | Set-Content -LiteralPath $reportOut -Encoding UTF8

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $proofDir '*') -DestinationPath $zipPath -Force

if (-not $phasePass) {
    throw '[phase103_82] Marker verification failed.'
}

Write-Host '[phase103_82] PASS'
Write-Host "[phase103_82] Proof directory: $proofDir"
Write-Host "[phase103_82] Proof archive: $zipPath"
