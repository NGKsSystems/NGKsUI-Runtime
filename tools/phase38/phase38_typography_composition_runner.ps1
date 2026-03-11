param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File '.\tools\runtime_runner_common.ps1' -phase 38 -tag 'typography_composition'
if (-not $paths -or $paths.Count -lt 2) {
  throw 'runtime_runner_common did not return PF/ZIP'
}

$root = (Get-Location).Path
$pf = ([string]$paths[0]).Trim()
$zip = ([string]$paths[1]).Trim()
$proofRoot = Join-Path $root '_proof'
$proofResolved = (Resolve-Path -LiteralPath $proofRoot).Path
$legalPrefix = $proofResolved + [System.IO.Path]::DirectorySeparatorChar

$f1 = Join-Path $pf '01_status.txt'
$f2 = Join-Path $pf '02_head.txt'
$f10 = Join-Path $pf '10_plan.txt'
$f11 = Join-Path $pf '11_files_touched.txt'
$f12 = Join-Path $pf '12_build_output.txt'
$f13 = Join-Path $pf '13_demo_layout_notes.txt'
$f14 = Join-Path $pf '14_typography_roles.txt'
$f98 = Join-Path $pf '98_gate_phase38.txt'

git status *> $f1
git log -1 *> $f2

@(
  'phase=38_typography_composition'
  'goal_1=enforce_structured_section_composition_on_sandbox_surface'
  'goal_2=apply_typography_roles_title_label_body_status_numeric'
  'goal_3=preserve_textbox_button_behavior_without_regressions'
) | Set-Content -Path $f10 -Encoding utf8

git diff --name-only | Set-Content -Path $f11 -Encoding utf8

$graphPlan = Join-Path $root 'build_graph\debug\ngksbuildcore_plan.json'
$graphPlanAlt = Join-Path $root 'build_graph\debug\ngksgraph_plan.json'

function Resolve-WidgetExePath {
  param(
    [string]$RootPath,
    [string]$PlanPath,
    [string]$PlanPathAlt
  )

  $candidatePaths = @()

  if (Test-Path $PlanPathAlt) {
    try {
      $planAlt = Get-Content -Raw -LiteralPath $PlanPathAlt | ConvertFrom-Json
      if ($planAlt.targets) {
        foreach ($target in $planAlt.targets) {
          if ($target.name -eq 'widget_sandbox' -and $target.output_path) {
            $candidatePaths += (Join-Path $RootPath ([string]$target.output_path))
          }
        }
      }
    }
    catch {}
  }

  if (Test-Path $PlanPath) {
    try {
      $plan = Get-Content -Raw -LiteralPath $PlanPath | ConvertFrom-Json
      if ($plan.nodes) {
        foreach ($node in $plan.nodes) {
          if ($node.outputs) {
            foreach ($out in $node.outputs) {
              $outText = [string]$out
              if ($outText -match 'widget_sandbox\.exe$') {
                $candidatePaths += (Join-Path $RootPath $outText)
              }
            }
          }
        }
      }
    }
    catch {}
  }

  $candidatePaths += (Join-Path $RootPath 'build\debug\bin\widget_sandbox.exe')

  foreach ($candidate in ($candidatePaths | Select-Object -Unique)) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  return $null
}

$buildOk = $false
$runText = ''
$runOk = $false
$runExitCode = -999
try {
  if (-not (Test-Path -LiteralPath $graphPlan)) {
    throw "graph_plan_missing:$graphPlan"
  }

  .\tools\enter_msvc_env.ps1 *> $f12

  $plan = Get-Content -Raw -LiteralPath $graphPlan | ConvertFrom-Json
  foreach ($node in $plan.nodes) {
    if ($null -eq $node.cmd -or [string]::IsNullOrWhiteSpace([string]$node.cmd)) {
      continue
    }

    "=== NODE: $($node.desc) ===" | Add-Content -Path $f12 -Encoding utf8
    "CMD: $($node.cmd)" | Add-Content -Path $f12 -Encoding utf8

    $cmdOut = cmd.exe /d /c $node.cmd 2>&1
    if ($cmdOut) {
      $cmdOut | Add-Content -Path $f12 -Encoding utf8
    }

    if ($LASTEXITCODE -ne 0) {
      throw "graph_node_failed:$($node.id)"
    }
  }

  $buildOk = $true
}
catch {
  $_ | Out-String | Add-Content -Path $f12 -Encoding utf8
}

$widgetExe = Resolve-WidgetExePath -RootPath $root -PlanPath $graphPlan -PlanPathAlt $graphPlanAlt
if ($buildOk -and $widgetExe) {
  try {
    $runOut = & $widgetExe '--demo' 2>&1
    $runText = ($runOut | Out-String)
    $runExitCode = $LASTEXITCODE
    $runOk = ($runExitCode -eq 0)
    "=== WIDGET DEMO OUTPUT ===" | Add-Content -Path $f12 -Encoding utf8
    $runOut | Add-Content -Path $f12 -Encoding utf8
  }
  catch {
    $runText = ($_ | Out-String)
    $runText | Add-Content -Path $f12 -Encoding utf8
  }
} else {
  @(
    "build_ok=$buildOk"
    "widget_exe=$widgetExe"
    'run_skipped=1'
  ) | Add-Content -Path $f12 -Encoding utf8
}

$panelTop = $runText -match 'widget_phase38_panel_top=1'
$panelInput = $runText -match 'widget_phase38_panel_input=1'
$panelControl = $runText -match 'widget_phase38_panel_control=1'
$panelPrimitive = $runText -match 'widget_phase38_panel_primitive=1'
$roleTitle = $runText -match 'widget_phase38_typography_title=1'
$roleLabel = $runText -match 'widget_phase38_typography_label=1'
$roleBody = $runText -match 'widget_phase38_typography_body=1'
$roleStatus = $runText -match 'widget_phase38_typography_status=1'
$roleNumeric = $runText -match 'widget_phase38_typography_numeric=1'
$renderOrder = $runText -match 'widget_phase38_render_order=1'

$noRegressionTextbox = ($runText -match 'widget_textbox_drag_selection_demo=1') -and ($runText -match 'widget_textbox_ctrl_a_demo=1') -and ($runText -match 'widget_textbox_enter_default_button=')
$noRegressionButtons = ($runText -match 'widget_button_key_activate=enter_increment') -and ($runText -match 'widget_cancel_key_activate=escape') -and ($runText -match 'widget_disabled_mouse_blocked=1')
$cleanExit = ($runExitCode -eq 0) -and ($runText -match 'widget_sandbox_exit=0')

@(
  'section_top=top panel introduces visual hierarchy and title role.'
  'section_input=input panel groups textbox semantics and selection telemetry.'
  'section_control=control panel groups primary/cancel button semantics.'
  'section_primitive=primitive panel isolates visual indicators and gauge elements.'
  "panel_top_signal=$panelTop"
  "panel_input_signal=$panelInput"
  "panel_control_signal=$panelControl"
  "panel_primitive_signal=$panelPrimitive"
  "render_order_signal=$renderOrder"
) | Set-Content -Path $f13 -Encoding utf8

@(
  'title=draw_text_title used for section headline emphasis'
  'label=draw_text_label used for section captions'
  'body=draw_text_body used for descriptive copy'
  'status=draw_text_status used for positive status line'
  'numeric=draw_text_numeric used for metric counter emphasis'
  "role_title_signal=$roleTitle"
  "role_label_signal=$roleLabel"
  "role_body_signal=$roleBody"
  "role_status_signal=$roleStatus"
  "role_numeric_signal=$roleNumeric"
  "textbox_regression_safe=$noRegressionTextbox"
  "button_regression_safe=$noRegressionButtons"
  "clean_exit=$cleanExit"
) | Set-Content -Path $f14 -Encoding utf8

$requiredFiles = @(
  '01_status.txt',
  '02_head.txt',
  '10_plan.txt',
  '11_files_touched.txt',
  '12_build_output.txt',
  '13_demo_layout_notes.txt',
  '14_typography_roles.txt'
)

$requiredPresent = $true
foreach ($rf in $requiredFiles) {
  if (-not (Test-Path -LiteralPath (Join-Path $pf $rf))) {
    $requiredPresent = $false
  }
}

$pfResolved = (Resolve-Path -LiteralPath $pf).Path
$zipCanonical = [System.IO.Path]::GetFullPath($zip)
$pfUnderLegal = $pfResolved.StartsWith($legalPrefix, [System.StringComparison]::OrdinalIgnoreCase)
$zipUnderLegal = $zipCanonical.StartsWith($legalPrefix, [System.StringComparison]::OrdinalIgnoreCase)

$pass = $buildOk -and $runOk -and $cleanExit -and $panelTop -and $panelInput -and $panelControl -and $panelPrimitive -and $roleTitle -and $roleLabel -and $roleBody -and $roleStatus -and $roleNumeric -and $renderOrder -and $noRegressionTextbox -and $noRegressionButtons -and $requiredPresent -and $pfUnderLegal -and $zipUnderLegal
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

@(
  'phase=38_typography_composition'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "clean_exit=$cleanExit"
  "panel_top_signal=$panelTop"
  "panel_input_signal=$panelInput"
  "panel_control_signal=$panelControl"
  "panel_primitive_signal=$panelPrimitive"
  "role_title_signal=$roleTitle"
  "role_label_signal=$roleLabel"
  "role_body_signal=$roleBody"
  "role_status_signal=$roleStatus"
  "role_numeric_signal=$roleNumeric"
  "render_order_signal=$renderOrder"
  "textbox_regression_safe=$noRegressionTextbox"
  "button_regression_safe=$noRegressionButtons"
  "required_files_present=$requiredPresent"
  "pf_under_legal_root=$pfUnderLegal"
  "zip_under_legal_root=$zipUnderLegal"
  "gate=$gate"
) | Set-Content -Path $f98 -Encoding utf8

if (Test-Path -LiteralPath $zipCanonical) {
  Remove-Item -Force $zipCanonical
}
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zipCanonical -Force

Write-Output "PF=$pfResolved"
Write-Output "ZIP=$zipCanonical"
Write-Output "GATE=$gate"

if ($gate -eq 'FAIL') {
  Get-Content -Path $f98
  if (Test-Path -LiteralPath $f12) {
    Get-Content -Path $f12 -Tail 180
  }
}
