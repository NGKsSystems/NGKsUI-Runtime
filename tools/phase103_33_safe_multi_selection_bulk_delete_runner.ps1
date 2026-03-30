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
  Write-Host 'wrong workspace for phase103_33 runner'
  exit 1
}

$proofRoot = Join-Path $workspaceRoot '_proof'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName = "phase103_33_safe_multi_selection_bulk_delete_${timestamp}"
$proofDir = Join-Path $proofRoot $proofName
$zipPath = Join-Path $proofRoot ($proofName + '.zip')

$buildOut = Join-Path $proofDir 'phase103_33_build_output.txt'
$runOut = Join-Path $proofDir 'phase103_33_runtime_output.txt'
$staticOut = Join-Path $proofDir 'phase103_33_static_checks.json'
$markerOut = Join-Path $proofDir 'phase103_33_marker_results.json'
$reportOut = Join-Path $proofDir 'PHASE103_33_VERIFICATION_REPORT.md'

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

function Ensure-PlanOutputDirectories {
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
    throw "[phase103_33] $StepName failed with exit code $LASTEXITCODE"
  }
}

Write-Host '[phase103_33] Static source checks...'
Assert-True (Test-Path -LiteralPath $mainPath) '[phase103_33] main.cpp missing'
$mainText = Get-Content -LiteralPath $mainPath -Raw

$staticChecks = @(
  'BuilderBulkDeleteDiagnostics',
  'bulk_delete_diag',
  'before_multi_selected_ids',
  'after_multi_selected_ids',
  'last_bulk_delete_status_code',
  'last_bulk_delete_reason',
  'apply_bulk_delete_selected_nodes_command',
  'apply_delete_command_for_current_selection',
  'run_phase103_33',
  'phase103_33_bulk_delete_present',
  'phase103_33_eligible_selected_nodes_deleted',
  'phase103_33_protected_or_invalid_bulk_delete_rejected',
  'phase103_33_post_delete_selection_deterministic',
  'phase103_33_undo_restores_bulk_delete_correctly',
  'phase103_33_shell_state_still_coherent',
  'phase103_33_preview_remains_parity_safe',
  'phase103_33_layout_audit_still_compatible',
  'loop.set_timeout(milliseconds(9900), [&] { run_phase103_33(); });'
)

$staticReport = @()
foreach ($token in $staticChecks) {
  $present = $mainText.Contains($token)
  $staticReport += [pscustomobject]@{ token = $token; present = $present }
  Assert-True $present "[phase103_33] Missing required source token: $token"
}
$staticReport | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $staticOut -Encoding UTF8

Write-Host '[phase103_33] Building desktop_file_tool...'
& (Join-Path $workspaceRoot '.venv/Scripts/python.exe') -m ngksgraph build --profile debug --msvc-auto --target desktop_file_tool *>&1 |
  Out-File -LiteralPath $buildOut -Encoding UTF8
Assert-True ($LASTEXITCODE -eq 0) '[phase103_33] Build-plan generation failed.'

Assert-True (Test-Path -LiteralPath $planPath) '[phase103_33] Build plan missing.'
$planJson = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json

$engineCompileNodes = @($planJson.nodes | Where-Object { $_.desc -like 'Compile engine/* for engine' })
$appCompileNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Compile apps/desktop_file_tool/main.cpp for desktop_file_tool' })[0]
$engineLibNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Link engine' })[0]
$appLinkNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Link desktop_file_tool' })[0]
Assert-True ($engineCompileNodes.Count -gt 0 -and $null -ne $appCompileNode -and $null -ne $engineLibNode -and $null -ne $appLinkNode) '[phase103_33] Required compile/link nodes missing.'

Ensure-PlanOutputDirectories -PlanJson $planJson
& (Join-Path $workspaceRoot 'tools/enter_msvc_env.ps1') *>&1 | Out-File -LiteralPath $buildOut -Append -Encoding UTF8

foreach ($node in $engineCompileNodes) {
  Invoke-CmdChecked -CommandLine $node.cmd -StepName $node.desc
}
Invoke-CmdChecked -CommandLine $appCompileNode.cmd -StepName $appCompileNode.desc
Invoke-CmdChecked -CommandLine $engineLibNode.cmd -StepName $engineLibNode.desc
Invoke-CmdChecked -CommandLine $appLinkNode.cmd -StepName $appLinkNode.desc

Assert-True (Test-Path -LiteralPath $exePath) '[phase103_33] Executable missing after compile/link.'

Write-Host '[phase103_33] Running validation mode...'
& $exePath --validation-mode --auto-close-ms=13000 *>&1 | Out-File -LiteralPath $runOut -Encoding UTF8
Assert-True ($LASTEXITCODE -eq 0) '[phase103_33] Validation run failed.'
$runText = (Get-Content -LiteralPath $runOut -Raw) -replace "`r", ''

function MarkerEqualsOne {
  param([string]$Name)
  return [regex]::IsMatch($runText, "(?m)^$([regex]::Escape($Name))=1$")
}

$requiredOne = @(
  'phase103_33_bulk_delete_present',
  'phase103_33_eligible_selected_nodes_deleted',
  'phase103_33_protected_or_invalid_bulk_delete_rejected',
  'phase103_33_post_delete_selection_deterministic',
  'phase103_33_undo_restores_bulk_delete_correctly',
  'phase103_33_shell_state_still_coherent',
  'phase103_33_preview_remains_parity_safe',
  'phase103_33_layout_audit_still_compatible',
  'phase103_32_shell_state_still_coherent',
  'phase103_32_preview_remains_parity_safe'
)

$results = @()
$allOnes = $true
foreach ($m in $requiredOne) {
  $ok = MarkerEqualsOne -Name $m
  if (-not $ok) { $allOnes = $false }
  $results += [pscustomobject]@{ marker = $m; value = $(if ($ok) { 1 } else { 0 }) }
}

$crashFree = [regex]::IsMatch($runText, '(?m)^app_runtime_crash_detected=0$')
$summaryPass = [regex]::IsMatch($runText, '(?m)^SUMMARY: PASS$')
$results += [pscustomobject]@{ marker = 'app_runtime_crash_detected'; value = $(if ($crashFree) { 0 } else { 1 }) }
$results += [pscustomobject]@{ marker = 'summary_pass_present'; value = $(if ($summaryPass) { 1 } else { 0 }) }

$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $markerOut -Encoding UTF8

$phasePass = $allOnes -and $crashFree -and $summaryPass

$report = @()
$report += '# PHASE103_33 Safe Multi-Selection Bulk Delete Verification Report'
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
$report += '- phase103_33_static_checks.json'
$report += '- phase103_33_build_output.txt'
$report += '- phase103_33_runtime_output.txt'
$report += '- phase103_33_marker_results.json'
$report -join "`r`n" | Set-Content -LiteralPath $reportOut -Encoding UTF8

if (Test-Path -LiteralPath $zipPath) {
  Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $proofDir '*') -DestinationPath $zipPath -Force

if (-not $phasePass) {
  throw '[phase103_33] Marker verification failed.'
}

Write-Host '[phase103_33] PASS'
Write-Host "[phase103_33] Proof directory: $proofDir"
Write-Host "[phase103_33] Proof archive: $zipPath"