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
    Write-Host 'wrong workspace for phase103_63 runner'
    exit 1
}

$proofRoot  = Join-Path $workspaceRoot '_proof'
$timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName  = "phase103_63_manual_text_entry_integrity_${timestamp}"
$proofDir   = Join-Path $proofRoot $proofName
$zipPath    = Join-Path $proofRoot ($proofName + '.zip')

$buildOut   = Join-Path $proofDir 'phase103_63_build_output.txt'
$runOut     = Join-Path $proofDir 'phase103_63_runtime_output.txt'
$staticOut  = Join-Path $proofDir 'phase103_63_static_checks.json'
$markerOut  = Join-Path $proofDir 'phase103_63_marker_results.json'
$reportOut  = Join-Path $proofDir 'PHASE103_63_VERIFICATION_REPORT.md'

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
        throw "[phase103_63] $StepName failed with exit code $LASTEXITCODE"
    }
}

# ── Static token checks ────────────────────────────────────────────────────────
Write-Host '[phase103_63] Static source checks...'
Assert-True (Test-Path -LiteralPath $mainPath) '[phase103_63] main.cpp missing'
$mainText = Get-Content -LiteralPath $mainPath -Raw

$staticChecks = @(
    'BuilderManualTextEntryIntegrityDiagnostics',
    'manual_text_diag',
    'run_phase103_63',
    'inline_edit_buffer_not_committed_until_commit',
    'cancelled_edit_leaves_document_unchanged',
    'committed_edit_creates_exact_history_entry',
    'undo_redo_exact_for_committed_text_edit',
    'selection_or_target_change_during_edit_resolved_deterministically',
    'no_stale_inline_edit_target_after_delete_move_load',
    'transient_edit_buffer_never_leaks_into_save_or_export',
    'rapid_edit_commit_cancel_sequences_stable',
    'no_history_entry_created_for_cancelled_edit',
    'global_invariant_preserved_through_manual_text_entry',
    'milliseconds(15900)',
    'P63_BUFFERED_ONLY',
    'P63_CANCELLED_TEXT',
    'P63_COMMITTED',
    'P63_TARGET_INVARIANT',
    'P63_DELETE_TARGET',
    'P63_STALE_BEFORE_LOAD',
    'P63_BUFFER_NOT_SAVED',
    'P63_RAPID_FINAL',
    'FP1 fix'
)

$staticReport = @{}
$staticFail   = $false
foreach ($tok in $staticChecks) {
    $found = $mainText.Contains($tok)
    $staticReport[$tok] = $found
    if (-not $found) {
        Write-Host "[phase103_63] MISSING TOKEN: $tok" -ForegroundColor Red
        $staticFail = $true
    }
}
$staticReport | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $staticOut -Encoding UTF8
Assert-True (-not $staticFail) '[phase103_63] Static token check failed.'
Write-Host '[phase103_63] All static tokens present.'

# ── Kill stale instances ───────────────────────────────────────────────────────
Write-Host '[phase103_63] Stopping running desktop_file_tool instances...'
Get-Process desktop_file_tool -ErrorAction SilentlyContinue | Stop-Process -Force

# ── Build ──────────────────────────────────────────────────────────────────────
Write-Host '[phase103_63] Building desktop_file_tool...'
& (Join-Path $workspaceRoot '.venv/Scripts/python.exe') -m ngksgraph build --profile debug --msvc-auto --target desktop_file_tool *>&1 |
    Out-File -LiteralPath $buildOut -Encoding UTF8
Assert-True ($LASTEXITCODE -eq 0) '[phase103_63] Build-plan generation failed.'

Assert-True (Test-Path -LiteralPath $planPath) '[phase103_63] Build plan missing.'
$planJson = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json

$engineCompileNodes = @($planJson.nodes | Where-Object { $_.desc -like 'Compile engine/* for engine' })
$appCompileNode     = @($planJson.nodes | Where-Object { $_.desc -eq 'Compile apps/desktop_file_tool/main.cpp for desktop_file_tool' })[0]
$engineLibNode      = @($planJson.nodes | Where-Object { $_.desc -eq 'Link engine' })[0]
$appLinkNode        = @($planJson.nodes | Where-Object { $_.desc -eq 'Link desktop_file_tool' })[0]
Assert-True ($engineCompileNodes.Count -gt 0 -and $null -ne $appCompileNode -and $null -ne $engineLibNode -and $null -ne $appLinkNode) '[phase103_63] Required compile/link nodes missing.'

Initialize-PlanOutputDirectories -PlanJson $planJson
& (Join-Path $workspaceRoot 'tools/enter_msvc_env.ps1') *>&1 | Out-File -LiteralPath $buildOut -Append -Encoding UTF8

foreach ($node in $engineCompileNodes) {
    Invoke-CmdChecked -CommandLine $node.cmd -StepName $node.desc
}
Invoke-CmdChecked -CommandLine $appCompileNode.cmd -StepName $appCompileNode.desc
Invoke-CmdChecked -CommandLine $engineLibNode.cmd   -StepName $engineLibNode.desc
Invoke-CmdChecked -CommandLine $appLinkNode.cmd     -StepName $appLinkNode.desc

Assert-True (Test-Path -LiteralPath $exePath) '[phase103_63] Executable missing after compile/link.'
Write-Host '[phase103_63] Build OK.'

# ── Run ────────────────────────────────────────────────────────────────────────
Write-Host '[phase103_63] Running validation mode...'
& $exePath --validation-mode --auto-close-ms=40000 *>&1 | Out-File -LiteralPath $runOut -Encoding UTF8
Assert-True ($LASTEXITCODE -eq 0) '[phase103_63] Validation run failed.'
$runText = (Get-Content -LiteralPath $runOut -Raw) -replace "`r", ''

function MarkerEqualsYes {
    param([string]$Name)
    return [regex]::IsMatch($runText, "(?m)^$([regex]::Escape($Name))=YES$")
}

# ── Marker verification ────────────────────────────────────────────────────────
$requiredYes = @(
    'phase103_63_inline_edit_buffer_not_committed_until_commit',
    'phase103_63_cancelled_edit_leaves_document_unchanged',
    'phase103_63_committed_edit_creates_exact_history_entry',
    'phase103_63_undo_redo_exact_for_committed_text_edit',
    'phase103_63_selection_or_target_change_during_edit_resolved_deterministically',
    'phase103_63_no_stale_inline_edit_target_after_delete_move_load',
    'phase103_63_transient_edit_buffer_never_leaks_into_save_or_export',
    'phase103_63_rapid_edit_commit_cancel_sequences_stable',
    'phase103_63_no_history_entry_created_for_cancelled_edit',
    'phase103_63_global_invariant_preserved_through_manual_text_entry'
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

# ── Report ─────────────────────────────────────────────────────────────────────
$report  = @()
$report += '# PHASE103_63 Manual Text Entry / Inline Edit Integrity Verification Report'
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
$report += '- phase103_63_static_checks.json'
$report += '- phase103_63_build_output.txt'
$report += '- phase103_63_runtime_output.txt'
$report += '- phase103_63_marker_results.json'
$report -join "`r`n" | Set-Content -LiteralPath $reportOut -Encoding UTF8

# ── Archive ────────────────────────────────────────────────────────────────────
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $proofDir '*') -DestinationPath $zipPath -Force

if (-not $phasePass) {
    throw '[phase103_63] Marker verification failed.'
}

Write-Host '[phase103_63] PASS'
Write-Host "[phase103_63] Proof directory: $proofDir"
Write-Host "[phase103_63] Proof archive: $zipPath"
