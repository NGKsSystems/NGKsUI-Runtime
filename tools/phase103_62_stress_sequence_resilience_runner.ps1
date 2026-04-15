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
  Write-Host 'wrong workspace for phase103_62 runner'
  exit 1
}

$proofRoot = Join-Path $workspaceRoot '_proof'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName = "phase103_62_stress_sequence_resilience_${timestamp}"
$proofDir = Join-Path $proofRoot $proofName
$zipPath = Join-Path $proofRoot ($proofName + '.zip')

$buildOut = Join-Path $proofDir 'phase103_62_build_output.txt'
$runOut = Join-Path $proofDir 'phase103_62_runtime_output.txt'
$staticOut = Join-Path $proofDir 'phase103_62_static_checks.json'
$markerOut = Join-Path $proofDir 'phase103_62_marker_results.json'
$reportOut = Join-Path $proofDir 'PHASE103_62_VERIFICATION_REPORT.md'

$planPath = Join-Path $workspaceRoot 'build_graph/debug/ngksbuildcore_plan.json'
$exePath = Join-Path $workspaceRoot 'build/debug/bin/desktop_file_tool.exe'
$mainPath = Join-Path $workspaceRoot 'apps/desktop_file_tool/main.cpp'

New-Item -ItemType Directory -Path $proofRoot -Force | Out-Null
New-Item -ItemType Directory -Path $proofDir -Force | Out-Null

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw $Message
  }
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
    throw "[phase103_62] $StepName failed with exit code $LASTEXITCODE"
  }
}

Write-Host '[phase103_62] Static source checks...'
Assert-True (Test-Path -LiteralPath $mainPath) '[phase103_62] main.cpp missing'
$mainText = Get-Content -LiteralPath $mainPath -Raw

$staticChecks = @(
  'BuilderStressSequenceResilienceDiagnostics',
  'stress_sequence_diag',
  'run_phase103_62',
  'run_stress_sequence',
  'doc_structurally_valid',
  'replay_of_identical_sequence_deterministic',
  'phase103_62_long_mixed_sequence_preserves_invariant',
  'phase103_62_no_structure_preview_drift_after_stress',
  'phase103_62_selection_and_bindings_remain_valid_after_stress',
  'phase103_62_undo_redo_history_stable_under_long_sequence',
  'phase103_62_no_stale_references_accumulated',
  'phase103_62_save_load_exact_after_stress',
  'phase103_62_export_exact_after_stress',
  'phase103_62_replay_of_identical_sequence_deterministic',
  'phase103_62_no_false_dirty_or_phantom_mutation_after_stress',
  'phase103_62_final_state_matches_expected_canonical_signature',
  'loop.set_timeout(milliseconds(15700), [&] { run_phase103_62(); });'
)

$staticReport = @()
foreach ($token in $staticChecks) {
  $present = $mainText.Contains($token)
  $staticReport += [pscustomobject]@{ token = $token; present = $present }
  Assert-True $present "[phase103_62] Missing required source token: $token"
}
$staticReport | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $staticOut -Encoding UTF8

Write-Host '[phase103_62] Stopping running desktop_file_tool instances...'
Get-Process desktop_file_tool -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host '[phase103_62] Building desktop_file_tool...'
& (Join-Path $workspaceRoot '.venv/Scripts/python.exe') -m ngksgraph build --profile debug --msvc-auto --target desktop_file_tool *>&1 |
  Out-File -LiteralPath $buildOut -Encoding UTF8
Assert-True ($LASTEXITCODE -eq 0) '[phase103_62] Build-plan generation failed.'

Assert-True (Test-Path -LiteralPath $planPath) '[phase103_62] Build plan missing.'
$planJson = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json

$engineCompileNodes = @($planJson.nodes | Where-Object { $_.desc -like 'Compile engine/* for engine' })
$appCompileNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Compile apps/desktop_file_tool/main.cpp for desktop_file_tool' })[0]
$engineLibNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Link engine' })[0]
$appLinkNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Link desktop_file_tool' })[0]
Assert-True ($engineCompileNodes.Count -gt 0 -and $null -ne $appCompileNode -and $null -ne $engineLibNode -and $null -ne $appLinkNode) '[phase103_62] Required compile/link nodes missing.'

Initialize-PlanOutputDirectories -PlanJson $planJson
& (Join-Path $workspaceRoot 'tools/enter_msvc_env.ps1') *>&1 | Out-File -LiteralPath $buildOut -Append -Encoding UTF8

foreach ($node in $engineCompileNodes) {
  Invoke-CmdChecked -CommandLine $node.cmd -StepName $node.desc
}
Invoke-CmdChecked -CommandLine $appCompileNode.cmd -StepName $appCompileNode.desc
Invoke-CmdChecked -CommandLine $engineLibNode.cmd -StepName $engineLibNode.desc
Invoke-CmdChecked -CommandLine $appLinkNode.cmd -StepName $appLinkNode.desc

Assert-True (Test-Path -LiteralPath $exePath) '[phase103_62] Executable missing after compile/link.'

Write-Host '[phase103_62] Running validation mode...'
& $exePath --validation-mode --auto-close-ms=38000 *>&1 | Out-File -LiteralPath $runOut -Encoding UTF8
Assert-True ($LASTEXITCODE -eq 0) '[phase103_62] Validation run failed.'
$runText = (Get-Content -LiteralPath $runOut -Raw) -replace "`r", ''

function MarkerEqualsYes {
  param([string]$Name)
  return [regex]::IsMatch($runText, "(?m)^$([regex]::Escape($Name))=YES$")
}

$requiredYes = @(
  'phase103_62_long_mixed_sequence_preserves_invariant',
  'phase103_62_no_structure_preview_drift_after_stress',
  'phase103_62_selection_and_bindings_remain_valid_after_stress',
  'phase103_62_undo_redo_history_stable_under_long_sequence',
  'phase103_62_no_stale_references_accumulated',
  'phase103_62_save_load_exact_after_stress',
  'phase103_62_export_exact_after_stress',
  'phase103_62_replay_of_identical_sequence_deterministic',
  'phase103_62_no_false_dirty_or_phantom_mutation_after_stress',
  'phase103_62_final_state_matches_expected_canonical_signature'
)

$results = @()
$allYes = $true
foreach ($m in $requiredYes) {
  $ok = MarkerEqualsYes -Name $m
  if (-not $ok) { $allYes = $false }
  $results += [pscustomobject]@{ marker = $m; value = $(if ($ok) { 'YES' } else { 'NO' }) }
}

$crashFree = [regex]::IsMatch($runText, '(?m)^app_runtime_crash_detected=0$')
$summaryPass = [regex]::IsMatch($runText, '(?m)^SUMMARY: PASS$')
$results += [pscustomobject]@{ marker = 'app_runtime_crash_detected'; value = $(if ($crashFree) { 0 } else { 1 }) }
$results += [pscustomobject]@{ marker = 'summary_pass_present'; value = $(if ($summaryPass) { 'PASS' } else { 'FAIL' }) }

$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $markerOut -Encoding UTF8

$phasePass = $allYes -and $crashFree -and $summaryPass

$report = @()
$report += '# PHASE103_62 Stress / Sequence Resilience Hardening Verification Report'
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
$report += '- phase103_62_static_checks.json'
$report += '- phase103_62_build_output.txt'
$report += '- phase103_62_runtime_output.txt'
$report += '- phase103_62_marker_results.json'
$report -join "`r`n" | Set-Content -LiteralPath $reportOut -Encoding UTF8

if (Test-Path -LiteralPath $zipPath) {
  Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $proofDir '*') -DestinationPath $zipPath -Force

if (-not $phasePass) {
  throw '[phase103_62] Marker verification failed.'
}

Write-Host '[phase103_62] PASS'
Write-Host "[phase103_62] Proof directory: $proofDir"
Write-Host "[phase103_62] Proof archive: $zipPath"
