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
  Write-Host 'wrong workspace for phase103_25 runner'
  exit 1
}

$proofRoot = Join-Path $workspaceRoot '_proof'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName = "phase103_25_inspector_ux_upgrade_typed_editing_clarity_${timestamp}_$([guid]::NewGuid().ToString('N').Substring(0,8))"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$($proofName).zip"

$checksFile = Join-Path $stageRoot '90_inspector_ux_typed_editing_checks.txt'
$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$buildOut = Join-Path $stageRoot '__build_stdout.txt'
$runOut = Join-Path $stageRoot '__run_stdout.txt'

$planPath = Join-Path $workspaceRoot 'build_graph/debug/ngksbuildcore_plan.json'
$exePath = Join-Path $workspaceRoot 'build/debug/bin/desktop_file_tool.exe'
$mainPath = Join-Path $workspaceRoot 'apps/desktop_file_tool/main.cpp'

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
  @{ name = 'BuilderInspectorTypedEditingDiagnostics struct'; pattern = 'BuilderInspectorTypedEditingDiagnostics' },
  @{ name = 'typed inspector region header'; pattern = 'INSPECTOR REGION \(Typed Editing Surface\)' },
  @{ name = 'explicit selected type identity'; pattern = 'TYPE:' },
  @{ name = 'explicit selected id identity'; pattern = 'ID:' },
  @{ name = 'identity section'; pattern = '\[IDENTITY\]' },
  @{ name = 'content section'; pattern = '\[CONTENT\]' },
  @{ name = 'layout section'; pattern = '\[LAYOUT\]' },
  @{ name = 'state section'; pattern = '\[STATE\]' },
  @{ name = 'editable marker'; pattern = '\(editable\)' },
  @{ name = 'readonly marker'; pattern = '\(readonly\)' },
  @{ name = 'deterministic edit result line'; pattern = 'EDIT_RESULT:' },
  @{ name = 'inspector edit command'; pattern = 'apply_inspector_text_edit_command' },
  @{ name = 'run_phase103_25 flow'; pattern = 'run_phase103_25' },
  @{ name = 'phase103_25 grouped marker'; pattern = 'phase103_25_inspector_sections_typed_and_grouped' },
  @{ name = 'phase103_25 type marker'; pattern = 'phase103_25_selected_node_type_clearly_visible' },
  @{ name = 'phase103_25 rwro marker'; pattern = 'phase103_25_editable_vs_readonly_state_clear' },
  @{ name = 'phase103_25 type-specific marker'; pattern = 'phase103_25_type_specific_fields_correct' },
  @{ name = 'phase103_25 legal edit marker'; pattern = 'phase103_25_legal_typed_edit_applied' },
  @{ name = 'phase103_25 invalid edit marker'; pattern = 'phase103_25_invalid_edit_rejected_with_reason' },
  @{ name = 'phase103_25 shell marker'; pattern = 'phase103_25_shell_state_still_coherent' },
  @{ name = 'phase103_25 parity marker'; pattern = 'phase103_25_preview_remains_parity_safe' },
  @{ name = 'phase103_25 audit marker'; pattern = 'phase103_25_layout_audit_still_compatible' },
  @{ name = 'regression phase103_24 marker'; pattern = 'phase103_24_hover_visual_present' },
  @{ name = 'regression phase103_23 marker'; pattern = 'phase103_23_preview_structure_visualized' }
) -Category 'feature_missing' -LogPath $buildOut -ContextName 'phase103_25_capabilities'

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

& $exePath --validation-mode --auto-close-ms=11000 *>&1 |
  Out-File -LiteralPath $runOut -Encoding UTF8
if ($LASTEXITCODE -ne 0) {
  Fail-Closed -Category 'runtime_validation_failed' -Reason "desktop_file_tool validation run failed (exit $LASTEXITCODE)" -LogPath $runOut
}

$runText = (Get-Content -LiteralPath $runOut -Raw) -replace "`r", ''

$inspector_sections_typed_and_grouped = Test-LinePresent -Text $runText -Pattern '^phase103_25_inspector_sections_typed_and_grouped=1$'
$selected_node_type_clearly_visible = Test-LinePresent -Text $runText -Pattern '^phase103_25_selected_node_type_clearly_visible=1$'
$editable_vs_readonly_state_clear = Test-LinePresent -Text $runText -Pattern '^phase103_25_editable_vs_readonly_state_clear=1$'
$type_specific_fields_correct = Test-LinePresent -Text $runText -Pattern '^phase103_25_type_specific_fields_correct=1$'
$legal_typed_edit_applied = Test-LinePresent -Text $runText -Pattern '^phase103_25_legal_typed_edit_applied=1$'
$invalid_edit_rejected_with_reason = Test-LinePresent -Text $runText -Pattern '^phase103_25_invalid_edit_rejected_with_reason=1$'
$shell_state_still_coherent = Test-LinePresent -Text $runText -Pattern '^phase103_25_shell_state_still_coherent=1$'
$preview_remains_parity_safe = Test-LinePresent -Text $runText -Pattern '^phase103_25_preview_remains_parity_safe=1$'
$layout_audit_still_compatible = Test-LinePresent -Text $runText -Pattern '^phase103_25_layout_audit_still_compatible=1$'

$regression_phase103_24_ok = (
  (Test-LinePresent -Text $runText -Pattern '^phase103_24_hover_visual_present=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_24_drag_target_preview_present=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_24_illegal_drop_feedback_present=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_24_preview_remains_parity_safe=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_24_shell_state_still_coherent=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_24_layout_audit_still_compatible=1$')
)

$regression_phase103_23_ok = (
  (Test-LinePresent -Text $runText -Pattern '^phase103_23_preview_structure_visualized=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_23_selected_node_highlight_visible=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_23_component_identity_visually_distinct=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_23_preview_remains_parity_safe=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_23_parity_still_passes=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_23_shell_state_still_coherent=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_23_layout_audit_still_compatible=1$')
)

$summary_pass = Test-LinePresent -Text $runText -Pattern '^SUMMARY: PASS$'
$new_regressions = -not $regression_phase103_24_ok -or -not $regression_phase103_23_ok -or -not $summary_pass

$checksContent = @"
phase103_25_checks
==================
inspector_sections_typed_and_grouped=$( if ($inspector_sections_typed_and_grouped) { 'YES' } else { 'NO' } )
selected_node_type_clearly_visible=$( if ($selected_node_type_clearly_visible) { 'YES' } else { 'NO' } )
editable_vs_readonly_state_clear=$( if ($editable_vs_readonly_state_clear) { 'YES' } else { 'NO' } )
type_specific_fields_correct=$( if ($type_specific_fields_correct) { 'YES' } else { 'NO' } )
legal_typed_edit_applied=$( if ($legal_typed_edit_applied) { 'YES' } else { 'NO' } )
invalid_edit_rejected_with_reason=$( if ($invalid_edit_rejected_with_reason) { 'YES' } else { 'NO' } )
shell_state_still_coherent=$( if ($shell_state_still_coherent) { 'YES' } else { 'NO' } )
preview_remains_parity_safe=$( if ($preview_remains_parity_safe) { 'YES' } else { 'NO' } )
layout_audit_still_compatible=$( if ($layout_audit_still_compatible) { 'YES' } else { 'NO' } )
regression_phase103_24=$( if ($regression_phase103_24_ok) { 'No' } else { 'REGRESSION' } )
regression_phase103_23=$( if ($regression_phase103_23_ok) { 'No' } else { 'REGRESSION' } )
new_regressions_detected=$( if ($new_regressions) { 'Yes' } else { 'No' } )
"@
Set-Content -LiteralPath $checksFile -Value $checksContent -Encoding UTF8

$allChecksOk =
  $inspector_sections_typed_and_grouped -and
  $selected_node_type_clearly_visible -and
  $editable_vs_readonly_state_clear -and
  $type_specific_fields_correct -and
  $legal_typed_edit_applied -and
  $invalid_edit_rejected_with_reason -and
  $shell_state_still_coherent -and
  $preview_remains_parity_safe -and
  $layout_audit_still_compatible -and
  -not $new_regressions

$phaseStatus = if ($allChecksOk) { 'PASS' } else { 'FAIL' }

$contractContent = @"
phase=PHASE103_25
task=Inspector UX Upgrade + Typed Editing Clarity
phase_status=$phaseStatus
inspector_sections_typed_and_grouped=$( if ($inspector_sections_typed_and_grouped) { 'YES' } else { 'NO' } )
selected_node_type_clearly_visible=$( if ($selected_node_type_clearly_visible) { 'YES' } else { 'NO' } )
editable_vs_readonly_state_clear=$( if ($editable_vs_readonly_state_clear) { 'YES' } else { 'NO' } )
type_specific_fields_correct=$( if ($type_specific_fields_correct) { 'YES' } else { 'NO' } )
legal_typed_edit_applied=$( if ($legal_typed_edit_applied) { 'YES' } else { 'NO' } )
invalid_edit_rejected_with_reason=$( if ($invalid_edit_rejected_with_reason) { 'YES' } else { 'NO' } )
shell_state_still_coherent=$( if ($shell_state_still_coherent) { 'YES' } else { 'NO' } )
preview_remains_parity_safe=$( if ($preview_remains_parity_safe) { 'YES' } else { 'NO' } )
layout_audit_still_compatible=$( if ($layout_audit_still_compatible) { 'YES' } else { 'NO' } )
new_regressions_detected=$( if ($new_regressions) { 'Yes' } else { 'No' } )
proof_folder=$proofPathRelative
"@
Set-Content -LiteralPath $contractFile -Value $contractContent -Encoding UTF8

if (Test-Path -LiteralPath $zipPath) {
  Remove-Item -LiteralPath $zipPath -Force
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stageRoot, $zipPath)

Write-Host "inspector_sections_typed_and_grouped=$( if ($inspector_sections_typed_and_grouped) { 'YES' } else { 'NO' } )"
Write-Host "selected_node_type_clearly_visible=$( if ($selected_node_type_clearly_visible) { 'YES' } else { 'NO' } )"
Write-Host "editable_vs_readonly_state_clear=$( if ($editable_vs_readonly_state_clear) { 'YES' } else { 'NO' } )"
Write-Host "type_specific_fields_correct=$( if ($type_specific_fields_correct) { 'YES' } else { 'NO' } )"
Write-Host "legal_typed_edit_applied=$( if ($legal_typed_edit_applied) { 'YES' } else { 'NO' } )"
Write-Host "invalid_edit_rejected_with_reason=$( if ($invalid_edit_rejected_with_reason) { 'YES' } else { 'NO' } )"
Write-Host "shell_state_still_coherent=$( if ($shell_state_still_coherent) { 'YES' } else { 'NO' } )"
Write-Host "preview_remains_parity_safe=$( if ($preview_remains_parity_safe) { 'YES' } else { 'NO' } )"
Write-Host "layout_audit_still_compatible=$( if ($layout_audit_still_compatible) { 'YES' } else { 'NO' } )"
Write-Host "new_regressions_detected=$( if ($new_regressions) { 'Yes' } else { 'No' } )"
Write-Host "phase_status=$phaseStatus"
Write-Host "proof_folder=$proofPathRelative"

if (-not $allChecksOk) {
  exit 1
}
