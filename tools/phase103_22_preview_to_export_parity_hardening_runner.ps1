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
  Write-Host 'wrong workspace for phase103_22 runner'
  exit 1
}

$proofRoot = Join-Path $workspaceRoot '_proof'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName = "phase103_22_preview_to_export_parity_hardening_${timestamp}_$([guid]::NewGuid().ToString('N').Substring(0,8))"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$($proofName).zip"

$checksFile = Join-Path $stageRoot '90_preview_to_export_parity_hardening_checks.txt'
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
  @{ name = 'BuilderPreviewExportParityDiagnostics struct'; pattern = 'BuilderPreviewExportParityDiagnostics' },
  @{ name = 'PreviewExportParityEntry struct'; pattern = 'PreviewExportParityEntry' },
  @{ name = 'preview parity scope constant'; pattern = 'kPreviewExportParityScope' },
  @{ name = 'preview parity status state'; pattern = 'last_preview_export_parity_status_code' },
  @{ name = 'preview surface parity scope'; pattern = 'parity_scope=' },
  @{ name = 'validate_preview_export_parity lambda'; pattern = 'validate_preview_export_parity' },
  @{ name = 'run_phase103_22 flow'; pattern = 'run_phase103_22' },
  @{ name = 'phase103_22 parity scope marker'; pattern = 'phase103_22_parity_scope_defined' },
  @{ name = 'phase103_22 parity validation marker'; pattern = 'phase103_22_preview_export_parity_validation_present' },
  @{ name = 'phase103_22 valid document marker'; pattern = 'phase103_22_parity_passes_for_valid_document' },
  @{ name = 'phase103_22 mismatch reason marker'; pattern = 'phase103_22_parity_mismatch_rejected_with_reason' },
  @{ name = 'phase103_22 shell marker'; pattern = 'phase103_22_export_shell_state_still_coherent' },
  @{ name = 'phase103_22 audit marker'; pattern = 'phase103_22_layout_audit_still_compatible' },
  @{ name = 'regression phase103_21 marker'; pattern = 'phase103_21_export_status_visible' },
  @{ name = 'regression phase103_20 marker'; pattern = 'phase103_20_export_command_present' }
) -Category 'feature_missing' -LogPath $buildOut -ContextName 'phase103_22_capabilities'

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

& $exePath --validation-mode --auto-close-ms=10200 *>&1 |
  Out-File -LiteralPath $runOut -Encoding UTF8
if ($LASTEXITCODE -ne 0) {
  Fail-Closed -Category 'runtime_validation_failed' -Reason "desktop_file_tool validation run failed (exit $LASTEXITCODE)" -LogPath $runOut
}

$runText = (Get-Content -LiteralPath $runOut -Raw) -replace "`r", ''

$parity_scope_defined = Test-LinePresent -Text $runText -Pattern '^phase103_22_parity_scope_defined=1$'
$preview_export_parity_validation_present = Test-LinePresent -Text $runText -Pattern '^phase103_22_preview_export_parity_validation_present=1$'
$parity_passes_for_valid_document = Test-LinePresent -Text $runText -Pattern '^phase103_22_parity_passes_for_valid_document=1$'
$parity_mismatch_rejected_with_reason = Test-LinePresent -Text $runText -Pattern '^phase103_22_parity_mismatch_rejected_with_reason=1$'
$export_shell_state_still_coherent = Test-LinePresent -Text $runText -Pattern '^phase103_22_export_shell_state_still_coherent=1$'
$layout_audit_still_compatible = Test-LinePresent -Text $runText -Pattern '^phase103_22_layout_audit_still_compatible=1$'

$artifact_exists_on_disk = Test-Path -LiteralPath $exportArtifactPath
$artifactText = if ($artifact_exists_on_disk) { Get-Content -LiteralPath $exportArtifactPath -Raw } else { '' }
$artifact_has_expected_structure =
  ($artifactText -match 'root_node_id=') -and
  ($artifactText -match 'parity22-container-a') -and
  ($artifactText -match 'parity22-leaf-label') -and
  ($artifactText -match 'parity22-leaf-button') -and
  ($artifactText -match 'Parity Label')

$phase103_22_ok =
  $parity_scope_defined -and
  $preview_export_parity_validation_present -and
  $parity_passes_for_valid_document -and
  $parity_mismatch_rejected_with_reason -and
  $export_shell_state_still_coherent -and
  $layout_audit_still_compatible -and
  $artifact_exists_on_disk -and
  $artifact_has_expected_structure

$regression_phase103_21_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase103_21_export_status_visible=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_21_export_artifact_path_visible=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_21_export_overwrite_or_version_rule_enforced=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_21_export_state_tracking_present=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_21_invalid_export_rejected_with_reason=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_21_shell_state_still_coherent=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_21_layout_audit_still_compatible=1$')

$regression_phase103_20_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase103_20_export_command_present=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_20_export_artifact_created=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_20_export_artifact_deterministic=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_20_exported_structure_matches_builder_doc=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_20_invalid_export_rejected=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_20_shell_state_still_coherent=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_20_layout_audit_still_compatible=1$')

$summary_pass = Test-LinePresent -Text $runText -Pattern '^SUMMARY: PASS$'
$new_regressions_detected = (-not $regression_phase103_21_ok) -or (-not $regression_phase103_20_ok) -or (-not $summary_pass)

@"
parity_scope_defined=$( if ($parity_scope_defined) { 'YES' } else { 'NO' })
preview_export_parity_validation_present=$( if ($preview_export_parity_validation_present) { 'YES' } else { 'NO' })
parity_passes_for_valid_document=$( if ($parity_passes_for_valid_document -and $artifact_has_expected_structure) { 'YES' } else { 'NO' })
parity_mismatch_rejected_with_reason=$( if ($parity_mismatch_rejected_with_reason) { 'YES' } else { 'NO' })
export_shell_state_still_coherent=$( if ($export_shell_state_still_coherent) { 'YES' } else { 'NO' })
layout_audit_still_compatible=$( if ($layout_audit_still_compatible) { 'YES' } else { 'NO' })
new_regressions_detected=$( if ($new_regressions_detected) { 'Yes' } else { 'No' })
"@ | Set-Content -LiteralPath $checksFile -Encoding UTF8

$phase_status = if ($phase103_22_ok -and -not $new_regressions_detected) { 'PASS' } else { 'FAIL' }

@"
phase=PHASE103_22
task=Preview-to-Export Parity Hardening
parity_scope_defined=$( if ($parity_scope_defined) { 'YES' } else { 'NO' })
preview_export_parity_validation_present=$( if ($preview_export_parity_validation_present) { 'YES' } else { 'NO' })
parity_passes_for_valid_document=$( if ($parity_passes_for_valid_document -and $artifact_has_expected_structure) { 'YES' } else { 'NO' })
parity_mismatch_rejected_with_reason=$( if ($parity_mismatch_rejected_with_reason) { 'YES' } else { 'NO' })
export_shell_state_still_coherent=$( if ($export_shell_state_still_coherent) { 'YES' } else { 'NO' })
layout_audit_still_compatible=$( if ($layout_audit_still_compatible) { 'YES' } else { 'NO' })
new_regressions_detected=$( if ($new_regressions_detected) { 'Yes' } else { 'No' })
phase_status=$phase_status
failure_category=$failureCategory
failure_reason=$failureReason
"@ | Set-Content -LiteralPath $contractFile -Encoding UTF8

Compress-Archive -Path (Join-Path $stageRoot '*') -DestinationPath $zipPath -Force

Write-Host "parity_scope_defined=$( if ($parity_scope_defined) { 'YES' } else { 'NO' })"
Write-Host "preview_export_parity_validation_present=$( if ($preview_export_parity_validation_present) { 'YES' } else { 'NO' })"
Write-Host "parity_passes_for_valid_document=$( if ($parity_passes_for_valid_document -and $artifact_has_expected_structure) { 'YES' } else { 'NO' })"
Write-Host "parity_mismatch_rejected_with_reason=$( if ($parity_mismatch_rejected_with_reason) { 'YES' } else { 'NO' })"
Write-Host "export_shell_state_still_coherent=$( if ($export_shell_state_still_coherent) { 'YES' } else { 'NO' })"
Write-Host "layout_audit_still_compatible=$( if ($layout_audit_still_compatible) { 'YES' } else { 'NO' })"
Write-Host "new_regressions_detected=$( if ($new_regressions_detected) { 'Yes' } else { 'No' })"
Write-Host "phase_status=$phase_status"
Write-Host "proof_folder=$proofPathRelative"

if ($phase_status -ne 'PASS') {
  exit 1
}