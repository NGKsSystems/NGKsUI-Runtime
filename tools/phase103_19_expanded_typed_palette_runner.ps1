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
  Write-Host 'wrong workspace for phase103_19 runner'
  exit 1
}

$proofRoot = Join-Path $workspaceRoot '_proof'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName = "phase103_19_expanded_typed_palette_${timestamp}_$([guid]::NewGuid().ToString('N').Substring(0,8))"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$($proofName).zip"

$checksFile = Join-Path $stageRoot '90_expanded_typed_palette_checks.txt'
$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$buildOut = Join-Path $stageRoot '__build_stdout.txt'
$runOut = Join-Path $stageRoot '__run_stdout.txt'

$planPath = Join-Path $workspaceRoot 'build_graph/debug/ngksbuildcore_plan.json'
$exePath = Join-Path $workspaceRoot 'build/debug/bin/desktop_file_tool.exe'
$mainPath = Join-Path $workspaceRoot 'apps/desktop_file_tool/main.cpp'
$uiElementPath = Join-Path $workspaceRoot 'engine/ui/ui_element.hpp'
$rendererHeaderPath = Join-Path $workspaceRoot 'engine/gfx/win32/include/ngk/gfx/d3d11_renderer.hpp'
$rendererSourcePath = Join-Path $workspaceRoot 'engine/gfx/win32/src/d3d11_renderer.cpp'

$failureCategory = 'none'
$failureReason = ''

New-Item -ItemType Directory -Path $proofRoot -Force | Out-Null
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null

function Remove-PathIfExists {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) {
    Remove-Item -LiteralPath $Path -Recurse -Force
  }
}

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
      Fail-Closed -Category 'compile_failed' -Reason "Compile $StepName failed with exit code $LASTEXITCODE" -LogPath $LogPath
    }
    if ($StepName -like 'Link*') {
      Fail-Closed -Category 'compile_failed' -Reason "Link $StepName failed with exit code $LASTEXITCODE" -LogPath $LogPath
    }
    Fail-Closed -Category 'build_precondition_failed' -Reason "$StepName failed with exit code $LASTEXITCODE" -LogPath $LogPath
  }
}

# --- Preflight: source files present ---
if (-not (Test-Path -LiteralPath $mainPath)) {
  Fail-Closed -Category 'feature_missing' -Reason 'desktop_file_tool main.cpp missing' -LogPath $buildOut
}
if (-not (Test-Path -LiteralPath $uiElementPath)) {
  Fail-Closed -Category 'feature_missing' -Reason 'engine/ui/ui_element.hpp missing' -LogPath $buildOut
}
if (-not (Test-Path -LiteralPath $rendererHeaderPath)) {
  Fail-Closed -Category 'feature_missing' -Reason 'd3d11_renderer.hpp missing' -LogPath $buildOut
}
if (-not (Test-Path -LiteralPath $rendererSourcePath)) {
  Fail-Closed -Category 'feature_missing' -Reason 'd3d11_renderer.cpp missing' -LogPath $buildOut
}

# --- Preflight: engine API surface ---
$uiElementText = Get-Content -LiteralPath $uiElementPath -Raw
Assert-RequiredPatterns -SourceText $uiElementText -Checks @(
  @{ name = 'LayoutSizePolicy enum'; pattern = 'enum class LayoutSizePolicy' },
  @{ name = 'set_min_size API'; pattern = 'set_min_size\s*\(' }
) -Category 'feature_missing' -LogPath $buildOut -ContextName 'builder_runtime_apis'

$rendererHeaderText = Get-Content -LiteralPath $rendererHeaderPath -Raw
Assert-RequiredPatterns -SourceText $rendererHeaderText -Checks @(
  @{ name = 'set_clip_rect declaration'; pattern = 'set_clip_rect\s*\(' },
  @{ name = 'reset_clip_rect declaration'; pattern = 'reset_clip_rect\s*\(' }
) -Category 'feature_missing' -LogPath $buildOut -ContextName 'builder_runtime_apis'

# --- Preflight: PHASE103_19 symbols in main.cpp ---
$mainText = Get-Content -LiteralPath $mainPath -Raw
Assert-RequiredPatterns -SourceText $mainText -Checks @(
  @{ name = 'BuilderTypedPaletteDiagnostics struct'; pattern = 'BuilderTypedPaletteDiagnostics' },
  @{ name = 'typed_palette_diag state'; pattern = 'typed_palette_diag' },
  @{ name = 'apply_typed_palette_insert lambda'; pattern = 'apply_typed_palette_insert' },
  @{ name = 'run_phase103_19 flow'; pattern = 'run_phase103_19' },
  @{ name = 'typed_insert history entry'; pattern = 'typed_insert' },
  @{ name = 'phase103_19 typed_palette_present marker'; pattern = 'phase103_19_typed_palette_present' },
  @{ name = 'phase103_19 legal_typed_container_insert_applied marker'; pattern = 'phase103_19_legal_typed_container_insert_applied' },
  @{ name = 'phase103_19 legal_typed_leaf_insert_applied marker'; pattern = 'phase103_19_legal_typed_leaf_insert_applied' },
  @{ name = 'phase103_19 illegal_typed_insert_rejected marker'; pattern = 'phase103_19_illegal_typed_insert_rejected' },
  @{ name = 'phase103_19 inserted_typed_node_auto_selected marker'; pattern = 'phase103_19_inserted_typed_node_auto_selected' },
  @{ name = 'phase103_19 inspector_shows_type_appropriate_properties marker'; pattern = 'phase103_19_inspector_shows_type_appropriate_properties' },
  @{ name = 'phase103_19 shell_state_still_coherent marker'; pattern = 'phase103_19_shell_state_still_coherent' },
  @{ name = 'phase103_19 layout_audit_still_compatible marker'; pattern = 'phase103_19_layout_audit_still_compatible' },
  # Regression: prior phases still present
  @{ name = 'phase103_18 drag_reorder marker'; pattern = 'phase103_18_tree_drag_reorder_present' },
  @{ name = 'phase103_17 keyboard nav marker'; pattern = 'phase103_17_keyboard_tree_navigation_present' },
  @{ name = 'phase103_2 builder doc marker'; pattern = 'phase103_2_builder_document_defined' },
  @{ name = 'phase103_9 selection coherence marker'; pattern = 'phase103_9_selection_coherence_hardened' },
  # Command APIs
  @{ name = 'push_to_history'; pattern = 'push_to_history' },
  @{ name = 'remap_selection_or_fail'; pattern = 'remap_selection_or_fail' },
  @{ name = 'sync_focus_with_selection_or_fail'; pattern = 'sync_focus_with_selection_or_fail' },
  @{ name = 'refresh_inspector_or_fail'; pattern = 'refresh_inspector_or_fail' },
  @{ name = 'refresh_preview_or_fail'; pattern = 'refresh_preview_or_fail' },
  @{ name = 'check_cross_surface_sync'; pattern = 'check_cross_surface_sync' }
) -Category 'feature_missing' -LogPath $buildOut -ContextName 'phase103_19_capabilities'

# --- Build ---
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

# --- Run validation ---
& $exePath --validation-mode --auto-close-ms=9800 *>&1 |
  Out-File -LiteralPath $runOut -Encoding UTF8
if ($LASTEXITCODE -ne 0) {
  Fail-Closed -Category 'runtime_validation_failed' -Reason "desktop_file_tool validation run failed (exit $LASTEXITCODE)" -LogPath $runOut
}

$runText = (Get-Content -LiteralPath $runOut -Raw) -replace "`r", ''

# --- PHASE103_19 markers ---
$p19_typedPalettePresent                  = Test-LinePresent -Text $runText -Pattern '^phase103_19_typed_palette_present=1$'
$p19_legalTypedContainerInsertApplied     = Test-LinePresent -Text $runText -Pattern '^phase103_19_legal_typed_container_insert_applied=1$'
$p19_legalTypedLeafInsertApplied          = Test-LinePresent -Text $runText -Pattern '^phase103_19_legal_typed_leaf_insert_applied=1$'
$p19_illegalTypedInsertRejected           = Test-LinePresent -Text $runText -Pattern '^phase103_19_illegal_typed_insert_rejected=1$'
$p19_insertedTypedNodeAutoSelected        = Test-LinePresent -Text $runText -Pattern '^phase103_19_inserted_typed_node_auto_selected=1$'
$p19_inspectorShowsTypeAppropriate        = Test-LinePresent -Text $runText -Pattern '^phase103_19_inspector_shows_type_appropriate_properties=1$'
$p19_shellStateStillCoherent              = Test-LinePresent -Text $runText -Pattern '^phase103_19_shell_state_still_coherent=1$'
$p19_layoutAuditStillCompatible           = Test-LinePresent -Text $runText -Pattern '^phase103_19_layout_audit_still_compatible=1$'

$phase103_19_ok =
  $p19_typedPalettePresent -and
  $p19_legalTypedContainerInsertApplied -and
  $p19_legalTypedLeafInsertApplied -and
  $p19_illegalTypedInsertRejected -and
  $p19_insertedTypedNodeAutoSelected -and
  $p19_inspectorShowsTypeAppropriate -and
  $p19_shellStateStillCoherent -and
  $p19_layoutAuditStillCompatible

# --- Regression: PHASE103_18 ---
$p18_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase103_18_tree_drag_reorder_present=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_18_legal_reorder_drop_applied=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_18_legal_reparent_drop_applied=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_18_illegal_drop_rejected=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_18_dragged_node_selection_preserved=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_18_shell_state_still_coherent=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_18_layout_audit_still_compatible=1$')

# --- Regression: PHASE103_17 ---
$p17_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase103_17_keyboard_tree_navigation_present=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_17_shortcut_scope_rules_defined=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_17_undo_redo_shortcuts_work=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_17_insert_delete_shortcuts_work=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_17_guarded_lifecycle_shortcuts_safe=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_17_shell_state_still_coherent=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_17_layout_audit_still_compatible=1$')

# --- Regression: PHASE102_2 ---
$p102_2_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase102_2_layout_functionalized=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_2_predictable_resize_behavior=1$')

# --- Runtime crash check ---
$noCrash = Test-LinePresent -Text $runText -Pattern '^app_runtime_crash_detected=0$'
$summaryPass = Test-LinePresent -Text $runText -Pattern '^SUMMARY: PASS$'

$new_regressions =
  (-not $p18_ok) -or
  (-not $p17_ok) -or
  (-not $p102_2_ok) -or
  (-not $noCrash) -or
  (-not $summaryPass)

# --- Write checks file ---
@"
typed_palette_present=$( if ($p19_typedPalettePresent) { 'YES' } else { 'NO' })
legal_typed_container_insert_applied=$( if ($p19_legalTypedContainerInsertApplied) { 'YES' } else { 'NO' })
legal_typed_leaf_insert_applied=$( if ($p19_legalTypedLeafInsertApplied) { 'YES' } else { 'NO' })
illegal_typed_insert_rejected=$( if ($p19_illegalTypedInsertRejected) { 'YES' } else { 'NO' })
inserted_typed_node_auto_selected=$( if ($p19_insertedTypedNodeAutoSelected) { 'YES' } else { 'NO' })
inspector_shows_type_appropriate_properties=$( if ($p19_inspectorShowsTypeAppropriate) { 'YES' } else { 'NO' })
shell_state_still_coherent=$( if ($p19_shellStateStillCoherent) { 'YES' } else { 'NO' })
layout_audit_still_compatible=$( if ($p19_layoutAuditStillCompatible) { 'YES' } else { 'NO' })
new_regressions_detected=$( if ($new_regressions) { 'Yes' } else { 'No' })
"@ | Set-Content -LiteralPath $checksFile -Encoding UTF8

# --- Determine phase status ---
$phase_status = if ($phase103_19_ok -and -not $new_regressions) { 'PASS' } else { 'FAIL' }

@"
phase=PHASE103_19
task=Expanded Component Palette + Typed Insert UX
typed_palette_present=$( if ($p19_typedPalettePresent) { 'YES' } else { 'NO' })
legal_typed_container_insert_applied=$( if ($p19_legalTypedContainerInsertApplied) { 'YES' } else { 'NO' })
legal_typed_leaf_insert_applied=$( if ($p19_legalTypedLeafInsertApplied) { 'YES' } else { 'NO' })
illegal_typed_insert_rejected=$( if ($p19_illegalTypedInsertRejected) { 'YES' } else { 'NO' })
inserted_typed_node_auto_selected=$( if ($p19_insertedTypedNodeAutoSelected) { 'YES' } else { 'NO' })
inspector_shows_type_appropriate_properties=$( if ($p19_inspectorShowsTypeAppropriate) { 'YES' } else { 'NO' })
shell_state_still_coherent=$( if ($p19_shellStateStillCoherent) { 'YES' } else { 'NO' })
layout_audit_still_compatible=$( if ($p19_layoutAuditStillCompatible) { 'YES' } else { 'NO' })
new_regressions_detected=$( if ($new_regressions) { 'Yes' } else { 'No' })
phase_status=$phase_status
proof_folder=$proofPathRelative
"@ | Set-Content -LiteralPath $contractFile -Encoding UTF8

# --- Archive proof ZIP ---
if (Test-Path -LiteralPath $zipPath) {
  Remove-Item -LiteralPath $zipPath -Force
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stageRoot, $zipPath)

# --- Emit results ---
Get-Content -LiteralPath $checksFile | Write-Host
Write-Host "phase_status=$phase_status"
Write-Host "proof_folder=$proofPathRelative"

if ($phase_status -ne 'PASS') {
  Fail-Closed -Category 'validation_failed' -Reason 'PHASE103_19 did not PASS' -LogPath $contractFile
}
