param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File '.\tools\runtime_runner_common.ps1' -phase 33 -tag '35_interaction_maturity'
if (-not $paths -or $paths.Count -lt 2) {
  throw 'runtime_runner_common did not return PF/ZIP'
}

$root = (Get-Location).Path
$pfInitial = ([string]$paths[0]).Trim()
$zipInitial = ([string]$paths[1]).Trim()
$proofRoot = Join-Path $root '_proof'
$proofResolved = (Resolve-Path -LiteralPath $proofRoot).Path
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path $proofResolved ("phase33_35_interaction_maturity_{0}" -f $timestamp)
$zip = "$pf.zip"

if (Test-Path -LiteralPath $pfInitial) {
  Remove-Item -Recurse -Force $pfInitial
}
if (Test-Path -LiteralPath $zipInitial) {
  Remove-Item -Force $zipInitial
}

New-Item -ItemType Directory -Path $pf | Out-Null
$legalPrefix = $proofResolved + [System.IO.Path]::DirectorySeparatorChar

$f1 = Join-Path $pf '01_status.txt'
$f2 = Join-Path $pf '02_head.txt'
$f10 = Join-Path $pf '10_plan.txt'
$f11 = Join-Path $pf '11_files_touched.txt'
$f12 = Join-Path $pf '12_build_output.txt'
$f13 = Join-Path $pf '13_widget_sandbox_run.txt'
$f14 = Join-Path $pf '14_behavior_summary.txt'
$f98 = Join-Path $pf '98_gate_phase33_35.txt'

git status *> $f1
git log -1 *> $f2

@(
  'phase=33_35_interaction_maturity'
  'goal_1=selection_polish_and_manual_text_ux'
  'goal_2=mouse_drag_selection_and_interaction_stability'
  'goal_3=default_cancel_and_generic_widget_semantics'
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

$runOk = $false
$runExitCode = -999
$widgetExe = Resolve-WidgetExePath -RootPath $root -PlanPath $graphPlan -PlanPathAlt $graphPlanAlt
if ($buildOk -and $widgetExe) {
  try {
    $runOut = & $widgetExe '--demo' 2>&1
    $runOut | Set-Content -Path $f13 -Encoding utf8
    $runExitCode = $LASTEXITCODE
    $runOk = ($runExitCode -eq 0)
  }
  catch {
    $_ | Out-String | Set-Content -Path $f13 -Encoding utf8
  }
} else {
  @(
    "build_ok=$buildOk"
    "widget_exe=$widgetExe"
    'run_skipped=1'
  ) | Set-Content -Path $f13 -Encoding utf8
}

$runText = if (Test-Path -LiteralPath $f13) { Get-Content -Raw -LiteralPath $f13 } else { '' }

$caretClick = $runText -match 'widget_phase32_textbox_refocus=1'
$dragSelection = $runText -match 'widget_textbox_drag_selection_demo=1'
$ctrlA = $runText -match 'widget_textbox_ctrl_a_demo=1'
$doubleClickWord = $runText -match 'widget_textbox_double_click_word_demo=1'
$selectionVisible = $runText -match 'widget_selection_highlight_visible=1'
$clipboardStable = ($runText -match 'widget_clipboard_copy_demo=1') -and ($runText -match 'widget_clipboard_cut_demo=1') -and ($runText -match 'widget_clipboard_paste_demo=1')
$typingReplace = $runText -match 'widget_textbox_replace_selection_demo=1'
$defaultEnter = $runText -match 'widget_textbox_enter_default_button='
$cancelEsc = $runText -match 'widget_cancel_key_activate=escape'
$disabledSafe = ($runText -match 'widget_disabled_mouse_blocked=1') -and ($runText -match 'widget_disabled_keyboard_blocked=1')
$noRegression = ($runText -match 'widget_text_backspace=1') -and ($runText -match 'widget_textbox_left_right_demo=1') -and ($runText -match 'widget_textbox_home_end_demo=home') -and ($runText -match 'widget_textbox_home_end_demo=end')
$cleanExit = ($runExitCode -eq 0) -and ($runText -match 'widget_sandbox_exit=0')

@(
  'Caret placement uses textbox-local x-to-index mapping and updates anchor/caret deterministically.'
  'Selection model remains anchor+caret; click/arrow collapse rules and shift expansion are handled in InputBox key/mouse paths.'
  'Double-click word selection uses deterministic word-boundary detection over alnum/underscore classes.'
  'Drag selection sets anchor on mouse-down, updates caret during move, and finalizes on mouse-up including out-of-bounds clamping.'
  'Ctrl+A/C/X/V are centrally routed by InputRouter into InputBox clipboard/select commands.'
  'Default/cancel semantics are in UITree with reusable widget contracts via primary action invocation, not sandbox-only logic.'
  'Sandbox demonstrates generic widget behavior with visible highlight/caret/focus/hover states and default/cancel activation.'
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "run_exit_code=$runExitCode"
  "caret_click_signal=$caretClick"
  "drag_selection_signal=$dragSelection"
  "ctrl_a_signal=$ctrlA"
  "double_click_word_signal=$doubleClickWord"
  "selection_visible_signal=$selectionVisible"
  "clipboard_signal=$clipboardStable"
  "typing_replace_signal=$typingReplace"
  "default_enter_signal=$defaultEnter"
  "cancel_esc_signal=$cancelEsc"
  "disabled_safe_signal=$disabledSafe"
  "no_regression_signal=$noRegression"
  "clean_exit=$cleanExit"
) | Set-Content -Path $f14 -Encoding utf8

$requiredFiles = @(
  '01_status.txt',
  '02_head.txt',
  '10_plan.txt',
  '11_files_touched.txt',
  '12_build_output.txt',
  '13_widget_sandbox_run.txt',
  '14_behavior_summary.txt'
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

$pass = $buildOk -and $runOk -and $cleanExit -and $caretClick -and $dragSelection -and $ctrlA -and $doubleClickWord -and $selectionVisible -and $clipboardStable -and $typingReplace -and $defaultEnter -and $cancelEsc -and $disabledSafe -and $noRegression -and $requiredPresent -and $pfUnderLegal -and $zipUnderLegal
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

@(
  'phase=33_35_interaction_maturity'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "clean_exit=$cleanExit"
  "caret_click_signal=$caretClick"
  "drag_selection_signal=$dragSelection"
  "ctrl_a_signal=$ctrlA"
  "double_click_word_signal=$doubleClickWord"
  "selection_visible_signal=$selectionVisible"
  "clipboard_signal=$clipboardStable"
  "typing_replace_signal=$typingReplace"
  "default_enter_signal=$defaultEnter"
  "cancel_esc_signal=$cancelEsc"
  "disabled_safe_signal=$disabledSafe"
  "no_regression_signal=$noRegression"
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
    Get-Content -Path $f12 -Tail 120
  }
  if (Test-Path -LiteralPath $f13) {
    Get-Content -Path $f13 -Tail 260
  }
}
