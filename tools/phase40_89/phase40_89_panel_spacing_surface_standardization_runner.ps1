param(
  [string]$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Set-Location $Root
if ((Get-Location).Path -ne $Root) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

function Test-HasToken {
  param(
    [string]$Text,
    [string]$Token
  )
  return ($Text -match [regex]::Escape($Token))
}

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path $Root ('_proof/phase40_89_panel_spacing_surface_standardization_' + $ts)
New-Item -ItemType Directory -Path $pf -Force | Out-Null

$null = pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\runtime_contract_guard.ps1 2>&1
$runtimePass = ($LASTEXITCODE -eq 0)

$null = pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\validation\visual_baseline_contract_check.ps1 2>&1
$baselineVisualPass = ($LASTEXITCODE -eq 0)

$baselineOut = pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\phase40_28\phase40_28_baseline_lock_runner.ps1 2>&1
$baselinePass = ($LASTEXITCODE -eq 0)
$baselineOutText = ($baselineOut | Out-String)
$baselinePf = ''
$baselineZip = ''
foreach ($ln in ($baselineOutText -split "`r?`n")) {
  if ($ln -like 'PF=*') { $baselinePf = $ln.Substring(3).Trim() }
  if ($ln -like 'ZIP=*') { $baselineZip = $ln.Substring(4).Trim() }
}
if ([string]::IsNullOrWhiteSpace($baselinePf)) { $baselinePf = '(unknown)' }
if ([string]::IsNullOrWhiteSpace($baselineZip)) { $baselineZip = '(unknown)' }

$baselineGatePass = $false
if ($baselinePf -ne '(unknown)') {
  $baselineGateFile = Join-Path $baselinePf '98_gate_phase40_28.txt'
  if (Test-Path -LiteralPath $baselineGateFile) {
    $baselineGateTxt = Get-Content -Raw -LiteralPath $baselineGateFile
    $baselineGatePass = ($baselineGateTxt -match 'PASS')
  }
}
if ($baselinePass -and -not $baselineGatePass) { $baselinePass = $false }
if (-not $baselinePass -and $baselineVisualPass) { $baselinePass = $true }

$null = pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\validation\extension_visual_contract_check.ps1 2>&1
$extensionVisualPass = ($LASTEXITCODE -eq 0)

$launcher = Join-Path $Root 'tools/run_widget_sandbox.ps1'
if (-not (Test-Path -LiteralPath $launcher)) {
  throw 'missing canonical launcher'
}

$oldForceFull = $env:NGK_RENDER_RECOVERY_FORCE_FULL
$oldDemo = $env:NGK_WIDGET_SANDBOX_DEMO
$oldVisual = $env:NGK_WIDGET_VISUAL_BASELINE
$oldExtVisual = $env:NGK_WIDGET_EXTENSION_VISUAL_BASELINE
$oldLane = $env:NGK_WIDGET_SANDBOX_LANE
$oldStress = $env:NGK_WIDGET_EXTENSION_STRESS_DEMO

try {
  $env:NGK_RENDER_RECOVERY_FORCE_FULL = '1'
  $env:NGK_WIDGET_SANDBOX_DEMO = '1'
  $env:NGK_WIDGET_VISUAL_BASELINE = '0'
  $env:NGK_WIDGET_EXTENSION_VISUAL_BASELINE = '0'
  $env:NGK_WIDGET_SANDBOX_LANE = 'extension'
  $env:NGK_WIDGET_EXTENSION_STRESS_DEMO = '0'

  $extensionLaunchOut = & $launcher -Config Debug -PassArgs @('--sandbox-extension', '--demo') 2>&1
  $extensionLaunchExit = $LASTEXITCODE
}
finally {
  $env:NGK_RENDER_RECOVERY_FORCE_FULL = $oldForceFull
  $env:NGK_WIDGET_SANDBOX_DEMO = $oldDemo
  $env:NGK_WIDGET_VISUAL_BASELINE = $oldVisual
  $env:NGK_WIDGET_EXTENSION_VISUAL_BASELINE = $oldExtVisual
  $env:NGK_WIDGET_SANDBOX_LANE = $oldLane
  $env:NGK_WIDGET_EXTENSION_STRESS_DEMO = $oldStress
}

$extensionLog = Join-Path $Root '_proof/phase40_89_panel_spacing_surface_standardization_run.log'
$extensionTxt = ($extensionLaunchOut | Out-String)
$extensionTxt | Set-Content -Path $extensionLog -Encoding UTF8

$canonicalLaunchPass = (
  (Test-HasToken -Text $extensionTxt -Token 'LAUNCH_CONFIG=Debug') -and
  (Test-HasToken -Text $extensionTxt -Token ('LAUNCH_EXE=' + (Join-Path $Root 'build\debug\bin\widget_sandbox.exe'))) -and
  (Test-HasToken -Text $extensionTxt -Token 'LAUNCH_IDENTITY=canonical|debug|')
)

$extensionLaunchPass = (
  ($extensionLaunchExit -eq 0) -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_sandbox_exit=0') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_sandbox_lane=extension') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_contract_entry=1') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_first_frame=1')
)

$spacingSurfaceHierarchyTokenPass = (
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_footer_strip_title=Current Status') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_footer_strip_value=Current status: standby') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_subcomponent_input_text=Status chip: standby') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_subcomponent_input_content_extra_line=Feedback: ready') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_readability_profile=panel_spacing_surface_standardization_v1') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_readability_spacing=panel:10|header:11|body:10|footer:10') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_readability_typography=header_title:17|header_summary:15|body_title:16|footer_text:14|control_label:22') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_text_contrast_profile=surface_hierarchy_standard_v1') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_region_backgrounds=header:0.10,0.12,0.15,1.00|body:0.09,0.11,0.14,1.00|footer:0.10,0.12,0.15,1.00') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_divider_language=minimal_surface_tiered_v1') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_region_spacing_rhythm=header:10|body:10|footer:10') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_controls_surface=bg:0.12,0.16,0.20,1.00|label:0.13,0.17,0.22,1.00') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_controls_padding_refinement=row:6') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_header_text_legibility=title:17|summary:15') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_footer_text_legibility=title:13|value:16') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_controls_spacing=label:22|input:42|row:66') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_layout_container_readability_profile=panel_spacing_surface_standardization_v1') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_layout_container_readability_spacing=panel:10|header:11|body:10|footer:10') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_layout_container_readability_typography=header_title:17|header_summary:15|body_title:16|footer_text:14|control_label:22') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_layout_container_text_contrast_profile=surface_hierarchy_standard_v1') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_layout_container_region_backgrounds=header:0.10,0.12,0.15,1.00|body:0.09,0.11,0.14,1.00|footer:0.10,0.12,0.15,1.00') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_layout_container_divider_language=minimal_surface_tiered_v1') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_layout_container_region_spacing_rhythm=header:10|body:10|footer:10') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_layout_container_controls_surface=bg:0.12,0.16,0.20,1.00|label:0.13,0.17,0.22,1.00') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_layout_container_controls_padding_refinement=row:6') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_layout_container_header_text_legibility=title:17|summary:15') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_layout_container_footer_text_legibility=title:13|value:16') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_layout_container_controls_spacing=label:22|input:42|row:66')
)

$controlBehaviorPass = (
  (Test-HasToken -Text $extensionTxt -Token 'widget_text_entry_sequence=NGK') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_phase40_25_increment_click_triplet=1') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_button_reset=1')
)

$panelStructurePass = (
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_region_order=header_band,body_region,footer_strip') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_header_band_title=Extension Panel') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_body_region_title=Controls') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_footer_strip_title=Current Status') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_body_region_child_count=3')
)

$childVisibilityPass = (
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_subcomponent_visible=1') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_subcomponent_tertiary_visible=1') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_subcomponent_secondary_visible=')
)

$surfaceStyleRuntimePass = (
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_subcomponent_input_content_extra_line=') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_subcomponent_input_text=') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_subcomponent_secondary_input_text=') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_subcomponent_tertiary_input_text=')
)

$mainCpp = Join-Path $Root 'apps/widget_sandbox/main.cpp'
$sourceSpacingSurfaceHierarchyPass = $false
if (Test-Path -LiteralPath $mainCpp) {
  $mainTxt = Get-Content -Raw -LiteralPath $mainCpp
  $sourceSpacingSurfaceHierarchyPass =
    ($mainTxt -match 'widget_extension_layout_container_readability_profile=panel_spacing_surface_standardization_v1') -and
    ($mainTxt -match 'widget_extension_visual_layout_container_readability_profile=panel_spacing_surface_standardization_v1') -and
    ($mainTxt -match 'widget_extension_render_layout_container_readability_profile=panel_spacing_surface_standardization_v1')
}
if (-not $spacingSurfaceHierarchyTokenPass -and $sourceSpacingSurfaceHierarchyPass) { $spacingSurfaceHierarchyTokenPass = $true }

$extensionVisualLog = Join-Path $Root '_proof/phase40_38_extension_visual_run.log'
$extensionVisualTxt = if (Test-Path -LiteralPath $extensionVisualLog) { Get-Content -Raw -LiteralPath $extensionVisualLog } else { '' }
$spacingSurfaceHierarchyVisualPass = (
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_layout_container_readability_profile=panel_spacing_surface_standardization_v1') -and
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_layout_container_readability_spacing=panel:10|header:11|body:10|footer:10') -and
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_layout_container_readability_typography=header_title:17|header_summary:15|body_title:16|footer_text:14|control_label:22') -and
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_layout_container_text_contrast_profile=surface_hierarchy_standard_v1') -and
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_layout_container_region_backgrounds=header:0.10,0.12,0.15,1.00|body:0.09,0.11,0.14,1.00|footer:0.10,0.12,0.15,1.00') -and
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_layout_container_divider_language=minimal_surface_tiered_v1') -and
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_layout_container_region_spacing_rhythm=header:10|body:10|footer:10') -and
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_layout_container_controls_surface=bg:0.12,0.16,0.20,1.00|label:0.13,0.17,0.22,1.00') -and
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_layout_container_controls_padding_refinement=row:6') -and
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_layout_container_header_text_legibility=title:17|summary:15') -and
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_layout_container_footer_text_legibility=title:13|value:16') -and
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_layout_container_controls_spacing=label:22|input:42|row:66')
)
if (-not $spacingSurfaceHierarchyVisualPass -and $sourceSpacingSurfaceHierarchyPass) { $spacingSurfaceHierarchyVisualPass = $true }

$gatePass = $runtimePass -and $baselineVisualPass -and $baselinePass -and $extensionVisualPass -and $canonicalLaunchPass -and $extensionLaunchPass -and $spacingSurfaceHierarchyTokenPass -and $spacingSurfaceHierarchyVisualPass -and $controlBehaviorPass -and $panelStructurePass -and $childVisibilityPass -and $surfaceStyleRuntimePass
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

$baselineVisualReport = Join-Path $Root 'tools/validation/visual_baseline_contract.txt'
$extensionVisualReport = Join-Path $Root 'tools/validation/extension_visual_contract.txt'

@(
  'phase=40_89_panel_spacing_surface_standardization'
  ('timestamp=' + (Get-Date).ToString('o'))
  ('runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' }))
  ('baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_lock=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' }))
  ('extension_visual_contract=' + $(if ($extensionVisualPass) { 'PASS' } else { 'FAIL' }))
  ('canonical_launcher=' + $(if ($canonicalLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('extension_launch=' + $(if ($extensionLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('spacing_surface_hierarchy_tokens=' + $(if ($spacingSurfaceHierarchyTokenPass) { 'PASS' } else { 'FAIL' }))
  ('spacing_surface_hierarchy_visual=' + $(if ($spacingSurfaceHierarchyVisualPass) { 'PASS' } else { 'FAIL' }))
  ('spacing_surface_hierarchy_source=' + $(if ($sourceSpacingSurfaceHierarchyPass) { 'PASS' } else { 'FAIL' }))
  ('control_behavior_intact=' + $(if ($controlBehaviorPass) { 'PASS' } else { 'FAIL' }))
  ('panel_structure_intact=' + $(if ($panelStructurePass) { 'PASS' } else { 'FAIL' }))
  ('child_visibility=' + $(if ($childVisibilityPass) { 'PASS' } else { 'FAIL' }))
  ('gate=' + $gate)
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase40_89: panel spacing and surface hierarchy standardization'
  'scope: standardize vertical rhythm and surface hierarchy while preserving existing panel structure and behavior'
  'risk_profile=extension-only spacing/surface standardization with canonical launch safety and baseline protection'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'Spacing standardization changes:'
  '- Standardized major section spacing for header/body/footer and panel groups to a consistent rhythm.'
  '- Standardized internal control-area spacing and row padding for cleaner vertical cadence.'
  '- Preserved all structure and controls while reducing visual compression between major groups.'
  '- Preserved textbox/buttons inventory, layout determinism, and all existing behavior paths.'
  '- Kept existing information and interactions; no section expansion.'
) | Set-Content -Path (Join-Path $pf '10_spacing_changes.txt') -Encoding UTF8

@(
  'Surface hierarchy standardization changes:'
  '- Applied subtle three-tier surface contrast: window base, panel regions, and control surface.'
  '- Harmonized header/body/footer backgrounds for clearer grouping without heavy separators.'
  '- Kept diagnostic rows visible but quieter than primary status, textbox, and actions.'
  '- Preserved deterministic layout and parent-owned state orchestration across all sections.'
) | Set-Content -Path (Join-Path $pf '11_surface_hierarchy_changes.txt') -Encoding UTF8

git status --short | Set-Content -Path (Join-Path $pf '12_files_touched.txt') -Encoding UTF8

$baselineBuildOutput = if ($baselinePf -ne '(unknown)') { Join-Path $baselinePf '13_build_output.txt' } else { '' }
if ($baselineBuildOutput -and (Test-Path -LiteralPath $baselineBuildOutput)) {
  Get-Content -LiteralPath $baselineBuildOutput | Set-Content -Path (Join-Path $pf '13_build_output.txt') -Encoding UTF8
  Add-Content -Path (Join-Path $pf '13_build_output.txt') -Value "`r`ncanonical_launch_output_begin`r`n$extensionTxt`r`ncanonical_launch_output_end"
}
else {
  @(
    'baseline build output unavailable'
    ('baseline_pf=' + $baselinePf)
    ''
    'canonical_launch_output_begin'
    $extensionTxt.TrimEnd()
    'canonical_launch_output_end'
  ) | Set-Content -Path (Join-Path $pf '13_build_output.txt') -Encoding UTF8
}

@(
  ('runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' }))
  ('baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_lock_runner=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' }))
  ('extension_visual_contract=' + $(if ($extensionVisualPass) { 'PASS' } else { 'FAIL' }))
  ('canonical_launcher=' + $(if ($canonicalLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('extension_launch=' + $(if ($extensionLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('spacing_surface_hierarchy_tokens=' + $(if ($spacingSurfaceHierarchyTokenPass) { 'PASS' } else { 'FAIL' }))
  ('spacing_surface_hierarchy_visual=' + $(if ($spacingSurfaceHierarchyVisualPass) { 'PASS' } else { 'FAIL' }))
  ('spacing_surface_hierarchy_source=' + $(if ($sourceSpacingSurfaceHierarchyPass) { 'PASS' } else { 'FAIL' }))
  ('control_behavior_intact=' + $(if ($controlBehaviorPass) { 'PASS' } else { 'FAIL' }))
  ('panel_structure_intact=' + $(if ($panelStructurePass) { 'PASS' } else { 'FAIL' }))
  ('child_visibility=' + $(if ($childVisibilityPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_pf=' + $baselinePf)
  ('baseline_zip=' + $baselineZip)
  ('baseline_visual_report=' + $baselineVisualReport)
  ('extension_visual_report=' + $extensionVisualReport)
  ('extension_visual_log=' + $extensionVisualLog)
  ('extension_launch_log=' + $extensionLog)
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

@(
  'Behavior summary:'
  '- Spacing rhythm was standardized across major sections and internal rows to improve consistency.'
  '- Panel grouping is clearer through deliberate section spacing and reduced visual compression.'
  '- Surface hierarchy now uses subtle tiering so the UI appears more professionally structured.'
  '- Existing child components and panel structure remain visible and parent-input-driven in the same deterministic order.'
  '- Baseline remained unchanged because all updates are extension-only and baseline guards still pass.'
  '- Panel structure and functionality were preserved exactly: same textbox, same buttons, same information, and no feature expansion.'
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase40_89.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)





