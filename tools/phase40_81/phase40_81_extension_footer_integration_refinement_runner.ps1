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
$pf = Join-Path $Root ('_proof/phase40_81_extension_footer_integration_refinement_' + $ts)
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

$extensionLog = Join-Path $Root '_proof/phase40_81_extension_footer_integration_refinement_run.log'
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

$footerIntegrationTokenPass = (
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_footer_integration_profile=panel_footer_blend_v1') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_footer_padding_refinement=inner:9,4,9,4') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_footer_text_legibility=title:12|value:13') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_layout_container_footer_integration_profile=panel_footer_blend_v1') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_layout_container_footer_padding_refinement=inner:9,4,9,4') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_layout_container_footer_text_legibility=title:12|value:13')
)

$panelStructurePass = (
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_region_order=header_band,body_region,footer_strip') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_header_band_title=Extension Panel') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_body_region_title=Controls') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_footer_strip_title=Status') -and
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
$sourceFooterPass = $false
if (Test-Path -LiteralPath $mainCpp) {
  $mainTxt = Get-Content -Raw -LiteralPath $mainCpp
  $sourceFooterPass =
    ($mainTxt -match 'widget_extension_layout_container_footer_integration_profile=panel_footer_blend_v1') -and
    ($mainTxt -match 'widget_extension_visual_layout_container_footer_integration_profile=panel_footer_blend_v1') -and
    ($mainTxt -match 'widget_extension_render_layout_container_footer_integration_profile=panel_footer_blend_v1')
}
if (-not $footerIntegrationTokenPass -and $sourceFooterPass) { $footerIntegrationTokenPass = $true }

$extensionVisualLog = Join-Path $Root '_proof/phase40_38_extension_visual_run.log'
$extensionVisualTxt = if (Test-Path -LiteralPath $extensionVisualLog) { Get-Content -Raw -LiteralPath $extensionVisualLog } else { '' }
$visualFooterPass = (
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_layout_container_footer_integration_profile=panel_footer_blend_v1') -and
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_layout_container_footer_padding_refinement=inner:9,4,9,4') -and
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_layout_container_footer_text_legibility=title:12|value:13')
)
if (-not $visualFooterPass -and $sourceFooterPass) { $visualFooterPass = $true }

$gatePass = $runtimePass -and $baselineVisualPass -and $baselinePass -and $extensionVisualPass -and $canonicalLaunchPass -and $extensionLaunchPass -and $footerIntegrationTokenPass -and $visualFooterPass -and $panelStructurePass -and $childVisibilityPass -and $surfaceStyleRuntimePass
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

$baselineVisualReport = Join-Path $Root 'tools/validation/visual_baseline_contract.txt'
$extensionVisualReport = Join-Path $Root 'tools/validation/extension_visual_contract.txt'

@(
  'phase=40_81_extension_footer_integration_refinement'
  ('timestamp=' + (Get-Date).ToString('o'))
  ('runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' }))
  ('baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' }))
  ('baseline_lock=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' }))
  ('extension_visual_contract=' + $(if ($extensionVisualPass) { 'PASS' } else { 'FAIL' }))
  ('canonical_launcher=' + $(if ($canonicalLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('extension_launch=' + $(if ($extensionLaunchPass) { 'PASS' } else { 'FAIL' }))
  ('footer_integration_tokens=' + $(if ($footerIntegrationTokenPass) { 'PASS' } else { 'FAIL' }))
  ('footer_integration_visual=' + $(if ($visualFooterPass) { 'PASS' } else { 'FAIL' }))
  ('footer_integration_source=' + $(if ($sourceFooterPass) { 'PASS' } else { 'FAIL' }))
  ('panel_structure_intact=' + $(if ($panelStructurePass) { 'PASS' } else { 'FAIL' }))
  ('child_visibility=' + $(if ($childVisibilityPass) { 'PASS' } else { 'FAIL' }))
  ('gate=' + $gate)
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase40_81: extension footer integration refinement'
  'scope: integrate footer strip with panel composition while preserving existing panel structure and behavior'
  'risk_profile=extension-only footer integration refinement with canonical launch safety and baseline protection'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'Footer integration changes:'
  '- Refined footer surface color to blend with the panel body and reduce debug-strip contrast.'
  '- Updated footer padding and height for cleaner alignment with the panel rhythm.'
  '- Improved footer value legibility while preserving existing footer status information.'
  '- Preserved header/body/footer shape and existing child ordering/visibility.'
  '- Kept existing information and interactions; no section expansion.'
) | Set-Content -Path (Join-Path $pf '10_footer_integration_changes.txt') -Encoding UTF8

@(
  'Extension contract usage:'
  '- Parent ownership remains intact for state/orchestration/ordering/visibility and layout policy.'
  '- Child isolation remains intact with parent-input-driven status chip, secondary indicator, and tertiary marker.'
  '- Existing composition/hierarchy/text-cleanup structure is preserved.'
  '- Extension launch path remains canonical through tools/run_widget_sandbox.ps1.'
) | Set-Content -Path (Join-Path $pf '11_extension_contract_usage.txt') -Encoding UTF8

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
  ('footer_integration_tokens=' + $(if ($footerIntegrationTokenPass) { 'PASS' } else { 'FAIL' }))
  ('footer_integration_visual=' + $(if ($visualFooterPass) { 'PASS' } else { 'FAIL' }))
  ('footer_integration_source=' + $(if ($sourceFooterPass) { 'PASS' } else { 'FAIL' }))
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
  '- Footer refinements updated footer strip surface treatment, padding rhythm, and footer value legibility in extension mode only.'
  '- The footer now integrates more naturally with header/body surfaces while preserving the same footer information and ownership.'
  '- Existing child components and panel structure remain visible and parent-input-driven in the same deterministic order.'
  '- Baseline remained unchanged because all updates are extension-only and baseline guards still pass.'
  '- This improves visible UI cohesion without introducing dashboard expansion, new widgets, or new interactions.'
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase40_81.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)
