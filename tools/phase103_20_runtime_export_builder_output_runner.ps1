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
  Write-Host 'wrong workspace for phase103_20 runner'
  exit 1
}

$proofRoot = Join-Path $workspaceRoot '_proof'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName = "phase103_20_runtime_export_builder_output_${timestamp}_$([guid]::NewGuid().ToString('N').Substring(0,8))"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$($proofName).zip"

$checksFile = Join-Path $stageRoot '90_runtime_export_builder_output_checks.txt'
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
  @{ name = 'BuilderExportDiagnostics struct'; pattern = 'BuilderExportDiagnostics' },
  @{ name = 'builder_export_path definition'; pattern = 'builder_export_path' },
  @{ name = 'apply_export_command lambda'; pattern = 'apply_export_command' },
  @{ name = 'builder_export_button control'; pattern = 'builder_export_button' },
  @{ name = 'run_phase103_20 flow'; pattern = 'run_phase103_20' },
  @{ name = 'phase103_20 export command marker'; pattern = 'phase103_20_export_command_present' },
  @{ name = 'phase103_20 export artifact marker'; pattern = 'phase103_20_export_artifact_created' },
  @{ name = 'phase103_20 deterministic marker'; pattern = 'phase103_20_export_artifact_deterministic' },
  @{ name = 'phase103_20 structure marker'; pattern = 'phase103_20_exported_structure_matches_builder_doc' },
  @{ name = 'phase103_20 invalid marker'; pattern = 'phase103_20_invalid_export_rejected' },
  @{ name = 'phase103_20 shell marker'; pattern = 'phase103_20_shell_state_still_coherent' },
  @{ name = 'phase103_20 audit marker'; pattern = 'phase103_20_layout_audit_still_compatible' },
  @{ name = 'regression phase103_19 marker'; pattern = 'phase103_19_typed_palette_present' },
  @{ name = 'regression phase103_18 marker'; pattern = 'phase103_18_tree_drag_reorder_present' }
) -Category 'feature_missing' -LogPath $buildOut -ContextName 'phase103_20_capabilities'

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

& $exePath --validation-mode --auto-close-ms=9800 *>&1 |
  Out-File -LiteralPath $runOut -Encoding UTF8
if ($LASTEXITCODE -ne 0) {
  Fail-Closed -Category 'runtime_validation_failed' -Reason "desktop_file_tool validation run failed (exit $LASTEXITCODE)" -LogPath $runOut
}

$runText = (Get-Content -LiteralPath $runOut -Raw) -replace "`r", ''

$export_command_present = Test-LinePresent -Text $runText -Pattern '^phase103_20_export_command_present=1$'
$export_artifact_created = Test-LinePresent -Text $runText -Pattern '^phase103_20_export_artifact_created=1$'
$export_artifact_deterministic = Test-LinePresent -Text $runText -Pattern '^phase103_20_export_artifact_deterministic=1$'
$exported_structure_matches_builder_doc = Test-LinePresent -Text $runText -Pattern '^phase103_20_exported_structure_matches_builder_doc=1$'
$invalid_export_rejected = Test-LinePresent -Text $runText -Pattern '^phase103_20_invalid_export_rejected=1$'
$shell_state_still_coherent = Test-LinePresent -Text $runText -Pattern '^phase103_20_shell_state_still_coherent=1$'
$layout_audit_still_compatible = Test-LinePresent -Text $runText -Pattern '^phase103_20_layout_audit_still_compatible=1$'

$artifact_exists_on_disk = Test-Path -LiteralPath $exportArtifactPath
$artifact_text = if ($artifact_exists_on_disk) { Get-Content -LiteralPath $exportArtifactPath -Raw } else { '' }
$artifact_has_expected_structure =
  ($artifact_text -match 'root_node_id=') -and
  ($artifact_text -match 'export-container-a') -and
  ($artifact_text -match 'export-leaf-label') -and
  ($artifact_text -match 'export-leaf-button')

$phase103_20_ok =
  $export_command_present -and
  $export_artifact_created -and
  $export_artifact_deterministic -and
  $exported_structure_matches_builder_doc -and
  $invalid_export_rejected -and
  $shell_state_still_coherent -and
  $layout_audit_still_compatible -and
  $artifact_exists_on_disk -and
  $artifact_has_expected_structure

$regression_phase103_19_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase103_19_typed_palette_present=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_19_legal_typed_container_insert_applied=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_19_legal_typed_leaf_insert_applied=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_19_illegal_typed_insert_rejected=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_19_inserted_typed_node_auto_selected=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_19_inspector_shows_type_appropriate_properties=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_19_shell_state_still_coherent=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_19_layout_audit_still_compatible=1$')

$regression_phase103_18_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase103_18_tree_drag_reorder_present=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_18_legal_reorder_drop_applied=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_18_legal_reparent_drop_applied=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_18_illegal_drop_rejected=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_18_dragged_node_selection_preserved=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_18_shell_state_still_coherent=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_18_layout_audit_still_compatible=1$')

$summary_pass = Test-LinePresent -Text $runText -Pattern '^SUMMARY: PASS$'
$new_regressions_detected = (-not $regression_phase103_19_ok) -or (-not $regression_phase103_18_ok) -or (-not $summary_pass)

@"
export_command_present=$( if ($export_command_present) { 'YES' } else { 'NO' })
export_artifact_created=$( if ($export_artifact_created -and $artifact_exists_on_disk) { 'YES' } else { 'NO' })
export_artifact_deterministic=$( if ($export_artifact_deterministic) { 'YES' } else { 'NO' })
exported_structure_matches_builder_doc=$( if ($exported_structure_matches_builder_doc -and $artifact_has_expected_structure) { 'YES' } else { 'NO' })
invalid_export_rejected=$( if ($invalid_export_rejected) { 'YES' } else { 'NO' })
shell_state_still_coherent=$( if ($shell_state_still_coherent) { 'YES' } else { 'NO' })
layout_audit_still_compatible=$( if ($layout_audit_still_compatible) { 'YES' } else { 'NO' })
new_regressions_detected=$( if ($new_regressions_detected) { 'Yes' } else { 'No' })
"@ | Set-Content -LiteralPath $checksFile -Encoding UTF8

$phase_status = if ($phase103_20_ok -and -not $new_regressions_detected) { 'PASS' } else { 'FAIL' }

@"
phase=PHASE103_20
task=Runtime Export / Builder-to-App Output Path
export_command_present=$( if ($export_command_present) { 'YES' } else { 'NO' })
export_artifact_created=$( if ($export_artifact_created -and $artifact_exists_on_disk) { 'YES' } else { 'NO' })
export_artifact_deterministic=$( if ($export_artifact_deterministic) { 'YES' } else { 'NO' })
exported_structure_matches_builder_doc=$( if ($exported_structure_matches_builder_doc -and $artifact_has_expected_structure) { 'YES' } else { 'NO' })
invalid_export_rejected=$( if ($invalid_export_rejected) { 'YES' } else { 'NO' })
shell_state_still_coherent=$( if ($shell_state_still_coherent) { 'YES' } else { 'NO' })
layout_audit_still_compatible=$( if ($layout_audit_still_compatible) { 'YES' } else { 'NO' })
new_regressions_detected=$( if ($new_regressions_detected) { 'Yes' } else { 'No' })
phase_status=$phase_status
proof_folder=$proofPathRelative
"@ | Set-Content -LiteralPath $contractFile -Encoding UTF8

if (Test-Path -LiteralPath $zipPath) {
  Remove-Item -LiteralPath $zipPath -Force
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stageRoot, $zipPath)

Get-Content -LiteralPath $checksFile | Write-Host
Write-Host "phase_status=$phase_status"
Write-Host "proof_folder=$proofPathRelative"

if ($phase_status -ne 'PASS') {
  Fail-Closed -Category 'validation_failed' -Reason 'PHASE103_20 did not PASS' -LogPath $contractFile
}
