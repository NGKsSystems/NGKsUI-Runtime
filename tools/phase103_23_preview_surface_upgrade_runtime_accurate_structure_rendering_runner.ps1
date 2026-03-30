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
  Write-Host 'wrong workspace for phase103_23 runner'
  exit 1
}

$proofRoot = Join-Path $workspaceRoot '_proof'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName = "phase103_23_preview_surface_upgrade_runtime_accurate_structure_rendering_${timestamp}_$([guid]::NewGuid().ToString('N').Substring(0,8))"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$($proofName).zip"

$checksFile = Join-Path $stageRoot '90_preview_surface_upgrade_checks.txt'
$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$buildOut = Join-Path $stageRoot '__build_stdout.txt'
$runOut = Join-Path $stageRoot '__run_stdout.txt'

$planPath = Join-Path $workspaceRoot 'build_graph/debug/ngksbuildcore_plan.json'
$exePath = Join-Path $workspaceRoot 'build/debug/bin/desktop_file_tool.exe'
$mainPath = Join-Path $workspaceRoot 'apps/desktop_file_tool/main.cpp'
$exportArtifactPath = Join-Path $workspaceRoot '_artifacts/runtime/phase103_20_builder_export.ngkbdoc'

$failureCategory = 'none'
$failureReason = ''

New-Item -ItemType Directory -Path $proofRoot -Force | Out-Null
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null

function Test-LinePresent {
  param([string]$Text, [string]$Pattern)
  return [regex]::IsMatch($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
}

function Fail-Closed {
  param([string]$Category, [string]$Reason, [string]$LogPath = '')
  $script:failureCategory = $Category
  $script:failureReason = $Reason
  if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
    Add-Content -LiteralPath $LogPath -Value ("failure_category=$Category")
    Add-Content -LiteralPath $LogPath -Value ("failure_reason=$Reason")
  }
  Write-Host "failure_category=$Category"
  Write-Host "failure_reason=$Reason"
  throw $Reason
}

function Assert-RequiredPatterns {
  param(
    [string]$SourceText,
    [array]$Checks,
    [string]$Category,
    [string]$LogPath,
    [string]$ContextName
  )

  $missing = @()
  foreach ($check in $Checks) {
    if ($SourceText -notmatch $check.pattern) {
      $missing += $check.name
    }
  }

  if ($missing.Count -gt 0) {
    $missingSummary = ($missing -join ', ')
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
      Add-Content -LiteralPath $LogPath -Value ("missing_$ContextName=$missingSummary")
    }
    Fail-Closed -Category $Category -Reason ("missing required ${ContextName}: $missingSummary") -LogPath $LogPath
  }
}

function Ensure-PlanOutputDirectories {
  param([object]$PlanJson, [string]$LogPath)

  $created = 0
  foreach ($node in $PlanJson.nodes) {
    foreach ($output in $node.outputs) {
      if ([string]::IsNullOrWhiteSpace($output)) { continue }
      $dir = Split-Path -Path $output -Parent
      if ([string]::IsNullOrWhiteSpace($dir)) { continue }
      if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $created += 1
      }
    }
  }

  Add-Content -LiteralPath $LogPath -Value ("precreated_output_directories=$created")
}

function Invoke-CmdChecked {
  param([string]$CommandLine, [string]$LogPath, [string]$StepName)
  Add-Content -LiteralPath $LogPath -Value ("STEP=$StepName")
  cmd /c $CommandLine *>&1 | Out-File -LiteralPath $LogPath -Append -Encoding UTF8
  if ($LASTEXITCODE -ne 0) {
    if ($StepName -like 'Compile*') {
      Fail-Closed -Category 'compile_failed' -Reason "$StepName failed with exit code $LASTEXITCODE" -LogPath $LogPath
    }
    if ($StepName -like 'Link*') {
      Fail-Closed -Category 'compile_failed' -Reason "$StepName failed with exit code $LASTEXITCODE" -LogPath $LogPath
    }
    Fail-Closed -Category 'build_precondition_failed' -Reason "$StepName failed with exit code $LASTEXITCODE" -LogPath $LogPath
  }
}

if (-not (Test-Path -LiteralPath $mainPath)) {
  Fail-Closed -Category 'feature_missing' -Reason 'desktop_file_tool main.cpp missing' -LogPath $buildOut
}

$mainText = Get-Content -LiteralPath $mainPath -Raw
Assert-RequiredPatterns -SourceText $mainText -Checks @(
  @{ name = 'BuilderPreviewSurfaceUpgradeDiagnostics struct'; pattern = 'BuilderPreviewSurfaceUpgradeDiagnostics' },
  @{ name = 'preview identity role helper'; pattern = 'preview_identity_role' },
  @{ name = 'runtime outline helper'; pattern = 'build_preview_runtime_outline' },
  @{ name = 'runtime outline text'; pattern = 'runtime_outline:' },
  @{ name = 'run_phase103_23 flow'; pattern = 'run_phase103_23' },
  @{ name = 'phase103_23 structure marker'; pattern = 'phase103_23_preview_structure_visualized' },
  @{ name = 'phase103_23 selection marker'; pattern = 'phase103_23_selected_node_highlight_visible' },
  @{ name = 'phase103_23 identity marker'; pattern = 'phase103_23_component_identity_visually_distinct' },
  @{ name = 'phase103_23 parity safety marker'; pattern = 'phase103_23_preview_remains_parity_safe' },
  @{ name = 'phase103_23 parity pass marker'; pattern = 'phase103_23_parity_still_passes' },
  @{ name = 'phase103_23 shell marker'; pattern = 'phase103_23_shell_state_still_coherent' },
  @{ name = 'phase103_23 audit marker'; pattern = 'phase103_23_layout_audit_still_compatible' },
  @{ name = 'regression phase103_22 marker'; pattern = 'phase103_22_parity_scope_defined' },
  @{ name = 'regression phase103_21 marker'; pattern = 'phase103_21_export_status_visible' }
) -Category 'feature_missing' -LogPath $buildOut -ContextName 'phase103_23_capabilities'

& (Join-Path $workspaceRoot '.venv/Scripts/python.exe') -m ngksgraph build --profile debug --msvc-auto --target desktop_file_tool *>&1 |
  Out-File -LiteralPath $buildOut -Encoding UTF8
if ($LASTEXITCODE -ne 0) {
  Fail-Closed -Category 'build_precondition_failed' -Reason 'desktop_file_tool build-plan generation failed' -LogPath $buildOut
}

if (-not (Test-Path -LiteralPath $planPath)) {
  Fail-Closed -Category 'build_precondition_failed' -Reason 'desktop_file_tool build plan missing' -LogPath $buildOut
}

$planJson = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
$engineCompileNodes = @($planJson.nodes | Where-Object { $_.desc -like 'Compile engine/* for engine' })
$appCompileNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Compile apps/desktop_file_tool/main.cpp for desktop_file_tool' })[0]
$engineLibNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Link engine' })[0]
$appLinkNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Link desktop_file_tool' })[0]

if ($engineCompileNodes.Count -eq 0 -or $null -eq $appCompileNode -or $null -eq $engineLibNode -or $null -eq $appLinkNode) {
  Fail-Closed -Category 'build_precondition_failed' -Reason 'required compile/link nodes missing from build plan' -LogPath $buildOut
}

Ensure-PlanOutputDirectories -PlanJson $planJson -LogPath $buildOut

& (Join-Path $workspaceRoot 'tools/enter_msvc_env.ps1') *>&1 |
  Out-File -LiteralPath $buildOut -Append -Encoding UTF8

foreach ($node in $engineCompileNodes) {
  Invoke-CmdChecked -CommandLine $node.cmd -LogPath $buildOut -StepName $node.desc
}
Invoke-CmdChecked -CommandLine $appCompileNode.cmd -LogPath $buildOut -StepName $appCompileNode.desc
Invoke-CmdChecked -CommandLine $engineLibNode.cmd -LogPath $buildOut -StepName $engineLibNode.desc
Invoke-CmdChecked -CommandLine $appLinkNode.cmd -LogPath $buildOut -StepName $appLinkNode.desc

if (-not (Test-Path -LiteralPath $exePath)) {
  Fail-Closed -Category 'compile_failed' -Reason 'desktop_file_tool executable missing after compile/link' -LogPath $buildOut
}

if (Test-Path -LiteralPath $exportArtifactPath) {
  Remove-Item -LiteralPath $exportArtifactPath -Force
}

& $exePath --validation-mode --auto-close-ms=10600 *>&1 |
  Out-File -LiteralPath $runOut -Encoding UTF8
if ($LASTEXITCODE -ne 0) {
  Fail-Closed -Category 'runtime_validation_failed' -Reason "desktop_file_tool validation run failed (exit $LASTEXITCODE)" -LogPath $runOut
}

$runText = (Get-Content -LiteralPath $runOut -Raw) -replace "`r", ''

$preview_structure_visualized = Test-LinePresent -Text $runText -Pattern '^phase103_23_preview_structure_visualized=1$'
$selected_node_highlight_visible = Test-LinePresent -Text $runText -Pattern '^phase103_23_selected_node_highlight_visible=1$'
$component_identity_visually_distinct = Test-LinePresent -Text $runText -Pattern '^phase103_23_component_identity_visually_distinct=1$'
$preview_remains_parity_safe = Test-LinePresent -Text $runText -Pattern '^phase103_23_preview_remains_parity_safe=1$'
$parity_still_passes = Test-LinePresent -Text $runText -Pattern '^phase103_23_parity_still_passes=1$'
$shell_state_still_coherent = Test-LinePresent -Text $runText -Pattern '^phase103_23_shell_state_still_coherent=1$'
$layout_audit_still_compatible = Test-LinePresent -Text $runText -Pattern '^phase103_23_layout_audit_still_compatible=1$'

$artifact_exists_on_disk = Test-Path -LiteralPath $exportArtifactPath
$artifactText = if ($artifact_exists_on_disk) { Get-Content -LiteralPath $exportArtifactPath -Raw } else { '' }
$artifact_has_expected_structure =
  ($artifactText -match 'root_node_id=') -and
  ($artifactText -match 'preview23-container-a') -and
  ($artifactText -match 'preview23-leaf-label') -and
  ($artifactText -match 'preview23-leaf-button') -and
  ($artifactText -match 'Preview Label')

$phase103_23_ok =
  $preview_structure_visualized -and
  $selected_node_highlight_visible -and
  $component_identity_visually_distinct -and
  $preview_remains_parity_safe -and
  $parity_still_passes -and
  $shell_state_still_coherent -and
  $layout_audit_still_compatible -and
  $artifact_exists_on_disk -and
  $artifact_has_expected_structure

$regression_phase103_22_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase103_22_parity_scope_defined=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_22_preview_export_parity_validation_present=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_22_parity_passes_for_valid_document=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_22_parity_mismatch_rejected_with_reason=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_22_export_shell_state_still_coherent=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_22_layout_audit_still_compatible=1$')

$regression_phase103_21_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase103_21_export_status_visible=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_21_export_artifact_path_visible=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_21_export_overwrite_or_version_rule_enforced=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_21_export_state_tracking_present=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_21_invalid_export_rejected_with_reason=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_21_shell_state_still_coherent=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_21_layout_audit_still_compatible=1$')

$summary_pass = Test-LinePresent -Text $runText -Pattern '^SUMMARY: PASS$'
$new_regressions_detected = (-not $regression_phase103_22_ok) -or (-not $regression_phase103_21_ok) -or (-not $summary_pass)

@"
preview_structure_visualized=$( if ($preview_structure_visualized) { 'YES' } else { 'NO' })
selected_node_highlight_visible=$( if ($selected_node_highlight_visible) { 'YES' } else { 'NO' })
component_identity_visually_distinct=$( if ($component_identity_visually_distinct) { 'YES' } else { 'NO' })
preview_remains_parity_safe=$( if ($preview_remains_parity_safe) { 'YES' } else { 'NO' })
parity_still_passes=$( if ($parity_still_passes -and $artifact_has_expected_structure) { 'YES' } else { 'NO' })
shell_state_still_coherent=$( if ($shell_state_still_coherent) { 'YES' } else { 'NO' })
layout_audit_still_compatible=$( if ($layout_audit_still_compatible) { 'YES' } else { 'NO' })
new_regressions_detected=$( if ($new_regressions_detected) { 'Yes' } else { 'No' })
"@ | Set-Content -LiteralPath $checksFile -Encoding UTF8

$phase_status = if ($phase103_23_ok -and -not $new_regressions_detected) { 'PASS' } else { 'FAIL' }

@"
phase=PHASE103_23
task=Preview Surface Upgrade (Runtime-Accurate Structure Rendering)
preview_structure_visualized=$( if ($preview_structure_visualized) { 'YES' } else { 'NO' })
selected_node_highlight_visible=$( if ($selected_node_highlight_visible) { 'YES' } else { 'NO' })
component_identity_visually_distinct=$( if ($component_identity_visually_distinct) { 'YES' } else { 'NO' })
preview_remains_parity_safe=$( if ($preview_remains_parity_safe) { 'YES' } else { 'NO' })
parity_still_passes=$( if ($parity_still_passes -and $artifact_has_expected_structure) { 'YES' } else { 'NO' })
shell_state_still_coherent=$( if ($shell_state_still_coherent) { 'YES' } else { 'NO' })
layout_audit_still_compatible=$( if ($layout_audit_still_compatible) { 'YES' } else { 'NO' })
new_regressions_detected=$( if ($new_regressions_detected) { 'Yes' } else { 'No' })
phase_status=$phase_status
failure_category=$failureCategory
failure_reason=$failureReason
"@ | Set-Content -LiteralPath $contractFile -Encoding UTF8

Compress-Archive -Path (Join-Path $stageRoot '*') -DestinationPath $zipPath -Force

Write-Host "preview_structure_visualized=$( if ($preview_structure_visualized) { 'YES' } else { 'NO' })"
Write-Host "selected_node_highlight_visible=$( if ($selected_node_highlight_visible) { 'YES' } else { 'NO' })"
Write-Host "component_identity_visually_distinct=$( if ($component_identity_visually_distinct) { 'YES' } else { 'NO' })"
Write-Host "preview_remains_parity_safe=$( if ($preview_remains_parity_safe) { 'YES' } else { 'NO' })"
Write-Host "parity_still_passes=$( if ($parity_still_passes -and $artifact_has_expected_structure) { 'YES' } else { 'NO' })"
Write-Host "shell_state_still_coherent=$( if ($shell_state_still_coherent) { 'YES' } else { 'NO' })"
Write-Host "layout_audit_still_compatible=$( if ($layout_audit_still_compatible) { 'YES' } else { 'NO' })"
Write-Host "new_regressions_detected=$( if ($new_regressions_detected) { 'Yes' } else { 'No' })"
Write-Host "phase_status=$phase_status"
Write-Host "proof_folder=$proofPathRelative"

if ($phase_status -ne 'PASS') {
  exit 1
}
