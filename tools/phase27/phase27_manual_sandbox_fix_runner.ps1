param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File '.\tools\runtime_runner_common.ps1' -phase 27 -tag 'manual_sandbox_fix'
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
$f10 = Join-Path $pf '10_bug_trace.txt'
$f11 = Join-Path $pf '11_files_touched.txt'
$f12 = Join-Path $pf '12_build_output.txt'
$f13 = Join-Path $pf '13_manual_launch_output.txt'
$f14 = Join-Path $pf '14_behavior_summary.txt'
$f98 = Join-Path $pf '98_gate_phase27_manual_fix.txt'

Set-Content -Path $f13 -Value '' -Encoding utf8

git status *> $f1
git log -1 *> $f2

@(
  'issue=widget_sandbox_auto_closes_before_manual_testing'
  'cause=scripted_demo_timers_were_always_enabled_in_default_path'
  'fix=default_mode_manual_only_and_scripted_demo_requires_explicit_opt_in'
  'manual_expectation=window_stays_open_until_user_close'
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

$manualLaunchOk = $false
$staysOpen = $false
$closeOnlyByUserExpected = $false
$keyboardHooksPresent = $false
$focusHooksPresent = $false
$textboxPresent = $false
$runText = ''
$demoText = ''
$widgetExe = Resolve-WidgetExePath -RootPath $root -PlanPath $graphPlan -PlanPathAlt $graphPlanAlt

if ($buildOk -and $widgetExe) {
  $stdoutPath = Join-Path $pf '__manual_stdout.txt'
  if (Test-Path -LiteralPath $stdoutPath) {
    Remove-Item -Force $stdoutPath
  }

  $process = $null
  try {
    $process = Start-Process -FilePath $widgetExe -WorkingDirectory $root -RedirectStandardOutput $stdoutPath -PassThru
    Start-Sleep -Milliseconds 2500

    if (-not $process.HasExited) {
      $staysOpen = $true
      $manualLaunchOk = $true
      Stop-Process -Id $process.Id -Force
      Start-Sleep -Milliseconds 300
    }
  }
  catch {
    $_ | Out-String | Add-Content -Path $f13 -Encoding utf8
  }

  @(
    "manual_launch_used_default_mode=1"
    "manual_launch_process_started=$($null -ne $process)"
    "manual_launch_stays_open=$staysOpen"
  ) | Add-Content -Path $f13 -Encoding utf8

  if (Test-Path -LiteralPath $stdoutPath) {
    $runText = Get-Content -Raw -LiteralPath $stdoutPath
    if (-not [string]::IsNullOrEmpty($runText)) {
      "--- manual_stdout ---" | Add-Content -Path $f13 -Encoding utf8
      $runText | Add-Content -Path $f13 -Encoding utf8
    }
    Remove-Item -Force $stdoutPath
  }

  try {
    "--- demo_run_begin ---" | Add-Content -Path $f13 -Encoding utf8
    $demoOut = & $widgetExe '--demo' 2>&1
    $demoOut | Add-Content -Path $f13 -Encoding utf8
    "--- demo_run_end ---" | Add-Content -Path $f13 -Encoding utf8
    $demoText = ($demoOut | Out-String)
  }
  catch {
    $_ | Out-String | Add-Content -Path $f13 -Encoding utf8
  }

  $keyboardHooksPresent = ($demoText -match 'widget_keyboard_routed_central=1') -and ($demoText -match 'widget_input_routed_via_router=1')
  $focusHooksPresent = ($demoText -match 'widget_focus_navigation_tab=') -and ($demoText -match 'widget_focus_navigation_shift_tab=1')
  $textboxPresent = ($demoText -match 'widget_textbox_present=1') -and ($demoText -match 'widget_textbox_value=')

  $demoOptInWorks = ($demoText -match 'widget_demo_mode=1') -and ($demoText -match 'widget_keyboard_only_demo=1') -and ($demoText -match 'widget_smoke_timeout=1')
  $closeOnlyByUserExpected = $staysOpen -and $demoOptInWorks
} else {
  @(
    "build_ok=$buildOk"
    "widget_exe=$widgetExe"
    'manual_launch_skipped=1'
  ) | Set-Content -Path $f13 -Encoding utf8
}

@(
  'Default sandbox launch is now manual mode: no scripted key/mouse simulation and no auto-exit timer are registered.'
  'Scripted behavior remains available only with explicit opt-in (--demo or NGK_WIDGET_SANDBOX_DEMO=1) for proof runners.'
  'Manual mode keeps central input routing active so Tab/Shift+Tab, Enter/Space, and textbox typing/backspace are available for user-driven testing.'
  "build_ok=$buildOk"
  "manual_launch_ok=$manualLaunchOk"
  "stays_open_without_auto_close=$staysOpen"
  "keyboard_hooks_present=$keyboardHooksPresent"
  "focus_hooks_present=$focusHooksPresent"
  "textbox_present=$textboxPresent"
  "close_only_by_user_expected=$closeOnlyByUserExpected"
) | Set-Content -Path $f14 -Encoding utf8

$requiredFiles = @(
  '01_status.txt',
  '02_head.txt',
  '10_bug_trace.txt',
  '11_files_touched.txt',
  '12_build_output.txt',
  '13_manual_launch_output.txt',
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

$pass = $buildOk -and $manualLaunchOk -and $staysOpen -and $keyboardHooksPresent -and $focusHooksPresent -and $textboxPresent -and $closeOnlyByUserExpected -and $requiredPresent -and $pfUnderLegal -and $zipUnderLegal
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

@(
  'phase=27_manual_sandbox_fix'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "build_ok=$buildOk"
  "manual_launch_ok=$manualLaunchOk"
  "stays_open_without_auto_close=$staysOpen"
  "keyboard_hooks_present=$keyboardHooksPresent"
  "focus_hooks_present=$focusHooksPresent"
  "textbox_present=$textboxPresent"
  "close_only_by_user_expected=$closeOnlyByUserExpected"
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
    Get-Content -Path $f13 -Tail 120
  }
}
