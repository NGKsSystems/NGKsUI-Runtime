param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  'hey stupid Fucker, wrong window again'
  exit 1
}

$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File ".\tools\runtime_runner_core.ps1" -phase 22 -tag "internal_mvp"
if (-not $paths -or $paths.Count -lt 2) {
  throw 'runtime_runner_core did not return PF/ZIP'
}

$pf = $paths[0].Trim()
$zip = $paths[1].Trim()
$repo = (Get-Location).Path
$proofRoot = Join-Path $repo '_proof'

$gitStatusFile = Join-Path $pf '01_status.txt'
$gitHeadFile = Join-Path $pf '02_head.txt'
$configLog = Join-Path $pf '20_config.txt'
$buildLog = Join-Path $pf '21_build.txt'
$widgetOut = Join-Path $pf '30_widget_stdout.txt'
$widgetErr = Join-Path $pf '31_widget_stderr.txt'
$portOut = Join-Path $pf '32_port_stdout.txt'
$portErr = Join-Path $pf '33_port_stderr.txt'
$gateFile = Join-Path $pf '98_gate_22.txt'

$implSummary = Join-Path $pf 'IMPLEMENTATION_SUMMARY.txt'
$missingScope = Join-Path $pf 'MISSING_SCOPE.txt'
$runInstructions = Join-Path $pf 'RUN_INSTRUCTIONS.txt'

git status *> $gitStatusFile
git log -1 *> $gitHeadFile

$graphPlan = Join-Path $repo 'build_graph\debug\ngksbuildcore_plan.json'
$graphPlanAlt = Join-Path $repo 'build_graph\debug\ngksgraph_plan.json'

$buildOk = $false
$widgetLaunchOk = $false
$portLaunchOk = $false
$widgetExitCode = -999
$portExitCode = -999
$reason = @()
$firstFailingComponent = ''
$firstFailLog = ''

function Resolve-AppExePath {
  param(
    [string]$RootPath,
    [string]$TargetName,
    [string]$PlanPath,
    [string]$PlanPathAlt,
    [string]$Fallback
  )

  $candidatePaths = @()

  if (Test-Path $PlanPathAlt) {
    try {
      $planAlt = Get-Content -Raw -LiteralPath $PlanPathAlt | ConvertFrom-Json
      if ($planAlt.targets) {
        foreach ($target in $planAlt.targets) {
          if ($target.name -eq $TargetName -and $target.output_path) {
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
              if ($outText -match ("{0}\.exe$" -f [regex]::Escape($TargetName))) {
                $candidatePaths += (Join-Path $RootPath $outText)
              }
            }
          }
        }
      }
    }
    catch {}
  }

  $candidatePaths += (Join-Path $RootPath $Fallback)

  foreach ($candidate in ($candidatePaths | Select-Object -Unique)) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  return (Join-Path $RootPath $Fallback)
}

function Run-App {
  param(
    [string]$ExePath,
    [string]$StdoutPath,
    [string]$StderrPath,
    [int]$TimeoutMs
  )

  $result = [pscustomobject]@{
    launch_ok = $false
    timed_out = $false
    exit_code = -999
  }

  try {
    $proc = Start-Process -FilePath $ExePath -PassThru -NoNewWindow -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
    $result.launch_ok = $true
    $done = $proc.WaitForExit($TimeoutMs)
    if (-not $done) {
      try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
      $result.timed_out = $true
      $result.exit_code = 124
      return $result
    }

    $proc.Refresh()
    $result.exit_code = [int]$proc.ExitCode
    return $result
  }
  catch {
    return $result
  }
}

try {
  @(
    'BUILD_SYSTEM=NGKsDevFabEco graph',
    "PLAN=$graphPlan",
    "PLAN_ALT=$graphPlanAlt"
  ) | Set-Content -Path $configLog -Encoding utf8

  if (-not (Test-Path $graphPlan)) {
    throw "Graph plan missing: $graphPlan"
  }

  .\tools\enter_msvc_env.ps1 *>> $buildLog

  $plan = Get-Content -Raw -LiteralPath $graphPlan | ConvertFrom-Json
  foreach ($node in $plan.nodes) {
    if ($null -eq $node.cmd -or [string]::IsNullOrWhiteSpace([string]$node.cmd)) {
      continue
    }

    if ($null -ne $node.outputs) {
      foreach ($output in $node.outputs) {
        if ([string]::IsNullOrWhiteSpace([string]$output)) {
          continue
        }
        $outputPath = Join-Path $repo ([string]$output)
        $outputDir = Split-Path -Parent $outputPath
        if ($outputDir -and -not (Test-Path $outputDir)) {
          New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
      }
    }

    "=== NODE: $($node.desc) ===" | Add-Content -Path $buildLog -Encoding utf8
    "CMD: $($node.cmd)" | Add-Content -Path $buildLog -Encoding utf8

    $cmdOut = cmd.exe /d /c $node.cmd 2>&1
    if ($cmdOut) {
      $cmdOut | Add-Content -Path $buildLog -Encoding utf8
    }

    if ($LASTEXITCODE -ne 0) {
      throw "Graph node failed: $($node.id)"
    }
  }

  $engineLib = Join-Path $repo 'build\debug\lib\engine.lib'
  if (-not (Test-Path $engineLib)) {
    throw "Engine library missing: $engineLib"
  }

  $portObjDir = Join-Path $repo 'build\debug\obj\port_probe\apps\port_probe'
  if (-not (Test-Path $portObjDir)) {
    New-Item -ItemType Directory -Path $portObjDir -Force | Out-Null
  }

  $compileCmd = 'cl /nologo /EHsc /std:c++20 /MD /showIncludes /c apps/port_probe/main.cpp /Fobuild/debug/obj/port_probe/apps/port_probe/main.obj /Iengine/core/include /Iengine/gfx/include /Iengine/gfx/win32/include /Iengine/platform/win32/include /Iengine/ui /Iengine/ui/include /DDEBUG /DUNICODE /D_UNICODE /Od /Zi'
  "=== PORT_PROBE COMPILE ===" | Add-Content -Path $buildLog -Encoding utf8
  "CMD: $compileCmd" | Add-Content -Path $buildLog -Encoding utf8
  $compileOut = cmd.exe /d /c $compileCmd 2>&1
  if ($compileOut) { $compileOut | Add-Content -Path $buildLog -Encoding utf8 }
  if ($LASTEXITCODE -ne 0) { throw 'port_probe_compile_failed' }

  $linkCmd = 'link /nologo build/debug/obj/port_probe/apps/port_probe/main.obj build/debug/lib/engine.lib /OUT:build/debug/bin/port_probe.exe d3d11.lib dxgi.lib gdi32.lib user32.lib'
  "=== PORT_PROBE LINK ===" | Add-Content -Path $buildLog -Encoding utf8
  "CMD: $linkCmd" | Add-Content -Path $buildLog -Encoding utf8
  $linkOut = cmd.exe /d /c $linkCmd 2>&1
  if ($linkOut) { $linkOut | Add-Content -Path $buildLog -Encoding utf8 }
  if ($LASTEXITCODE -ne 0) { throw 'port_probe_link_failed' }

  $buildOk = $true
}
catch {
  $reason += 'build_failed'
  $firstFailingComponent = 'build'
  $firstFailLog = $buildLog
}

$widgetExe = Resolve-AppExePath -RootPath $repo -TargetName 'widget_sandbox' -PlanPath $graphPlan -PlanPathAlt $graphPlanAlt -Fallback 'build\debug\bin\widget_sandbox.exe'
$portExe = Resolve-AppExePath -RootPath $repo -TargetName 'port_probe' -PlanPath $graphPlan -PlanPathAlt $graphPlanAlt -Fallback 'build\debug\bin\port_probe.exe'
"WIDGET_EXE=$widgetExe" | Add-Content -Path $configLog -Encoding utf8
"PORT_EXE=$portExe" | Add-Content -Path $configLog -Encoding utf8

if ($buildOk) {
  if (-not (Test-Path $widgetExe)) {
    $reason += 'widget_exe_missing'
    if (-not $firstFailingComponent) {
      $firstFailingComponent = 'widget_sandbox'
      $firstFailLog = $buildLog
    }
  }
  else {
    $widgetRun = Run-App -ExePath $widgetExe -StdoutPath $widgetOut -StderrPath $widgetErr -TimeoutMs 15000
    $widgetLaunchOk = $widgetRun.launch_ok
    $widgetExitCode = $widgetRun.exit_code
    if (-not $widgetLaunchOk) {
      $reason += 'widget_launch_failed'
      if (-not $firstFailingComponent) {
        $firstFailingComponent = 'widget_sandbox'
        $firstFailLog = $widgetErr
      }
    }
    elseif ($widgetRun.timed_out) {
      $reason += 'widget_run_timeout'
      if (-not $firstFailingComponent) {
        $firstFailingComponent = 'widget_sandbox'
        $firstFailLog = $widgetOut
      }
    }
    elseif ($widgetExitCode -ne 0) {
      $reason += "widget_exit_code=$widgetExitCode"
      if (-not $firstFailingComponent) {
        $firstFailingComponent = 'widget_sandbox'
        $firstFailLog = $widgetOut
      }
    }
  }

  if (-not (Test-Path $portExe)) {
    $reason += 'port_exe_missing'
    if (-not $firstFailingComponent) {
      $firstFailingComponent = 'port_probe'
      $firstFailLog = $buildLog
    }
  }
  else {
    $portRun = Run-App -ExePath $portExe -StdoutPath $portOut -StderrPath $portErr -TimeoutMs 15000
    $portLaunchOk = $portRun.launch_ok
    $portExitCode = $portRun.exit_code
    if (-not $portLaunchOk) {
      $reason += 'port_launch_failed'
      if (-not $firstFailingComponent) {
        $firstFailingComponent = 'port_probe'
        $firstFailLog = $portErr
      }
    }
    elseif ($portRun.timed_out) {
      $reason += 'port_run_timeout'
      if (-not $firstFailingComponent) {
        $firstFailingComponent = 'port_probe'
        $firstFailLog = $portOut
      }
    }
    elseif ($portExitCode -ne 0) {
      $reason += "port_exit_code=$portExitCode"
      if (-not $firstFailingComponent) {
        $firstFailingComponent = 'port_probe'
        $firstFailLog = $portOut
      }
    }
  }
}

$widgetCombined = ''
if (Test-Path $widgetOut) { $widgetCombined += (Get-Content -Raw -LiteralPath $widgetOut -ErrorAction SilentlyContinue) + "`n" }
if (Test-Path $widgetErr) { $widgetCombined += (Get-Content -Raw -LiteralPath $widgetErr -ErrorAction SilentlyContinue) + "`n" }

$portCombined = ''
if (Test-Path $portOut) { $portCombined += (Get-Content -Raw -LiteralPath $portOut -ErrorAction SilentlyContinue) + "`n" }
if (Test-Path $portErr) { $portCombined += (Get-Content -Raw -LiteralPath $portErr -ErrorAction SilentlyContinue) + "`n" }

$widgetNoCrash = -not [regex]::IsMatch($widgetCombined, 'widget_sandbox_exception|access violation|fatal|unhandled|terminate', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$widgetStartup = [regex]::IsMatch($widgetCombined, 'widget_sandbox_started=1', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$widgetExit = [regex]::IsMatch($widgetCombined, 'widget_sandbox_exit=0', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$widgetText = [regex]::IsMatch($widgetCombined, 'widget_textbox_value=', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$widgetList = [regex]::IsMatch($widgetCombined, 'widget_list_selection=', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$widgetScroll = [regex]::IsMatch($widgetCombined, 'widget_scroll_offset=', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$widgetButtons = [regex]::IsMatch($widgetCombined, 'button_click=one|button_click=two|button_click=three', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$widgetCheckbox = [regex]::IsMatch($widgetCombined, 'widget_checkbox_toggle=', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$widgetStatus = [regex]::IsMatch($widgetCombined, 'widget_statusbar_text=', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

$portNoCrash = -not [regex]::IsMatch($portCombined, 'port_probe_exception|access violation|fatal|unhandled|terminate', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$portStartup = [regex]::IsMatch($portCombined, 'port_probe_startup=1', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$portInput = [regex]::IsMatch($portCombined, 'port_probe_input value=', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$portAdd = [regex]::IsMatch($portCombined, 'port_probe_add item=', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$portSelect = [regex]::IsMatch($portCombined, 'port_probe_select index=', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$portRemove = [regex]::IsMatch($portCombined, 'port_probe_remove item=', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$portStatus = [regex]::IsMatch($portCombined, 'port_probe_status=', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$portCheckbox = [regex]::IsMatch($portCombined, 'port_probe_checkbox checked=', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$portExit = [regex]::IsMatch($portCombined, 'port_probe_exit=clean', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

if (-not $widgetNoCrash) { $reason += 'widget_crash_detected' }
if (-not $widgetStartup) { $reason += 'widget_startup_evidence_missing' }
if (-not $widgetExit) { $reason += 'widget_exit_evidence_missing' }
if (-not $widgetText) { $reason += 'widget_text_evidence_missing' }
if (-not $widgetList) { $reason += 'widget_list_evidence_missing' }
if (-not $widgetScroll) { $reason += 'widget_scroll_evidence_missing' }
if (-not $widgetButtons) { $reason += 'widget_button_evidence_missing' }
if (-not $widgetCheckbox) { $reason += 'widget_checkbox_evidence_missing' }
if (-not $widgetStatus) { $reason += 'widget_status_evidence_missing' }

if (-not $portNoCrash) { $reason += 'port_crash_detected' }
if (-not $portStartup) { $reason += 'port_startup_evidence_missing' }
if (-not $portInput) { $reason += 'port_input_evidence_missing' }
if (-not $portAdd) { $reason += 'port_add_evidence_missing' }
if (-not $portSelect) { $reason += 'port_select_evidence_missing' }
if (-not $portRemove) { $reason += 'port_remove_evidence_missing' }
if (-not $portStatus) { $reason += 'port_status_evidence_missing' }
if (-not $portCheckbox) { $reason += 'port_checkbox_evidence_missing' }
if (-not $portExit) { $reason += 'port_exit_evidence_missing' }

if ($reason.Count -gt 0 -and -not $firstFailingComponent) {
  if ($reason -match 'widget_') {
    $firstFailingComponent = 'widget_sandbox'
    $firstFailLog = $widgetOut
  }
  else {
    $firstFailingComponent = 'port_probe'
    $firstFailLog = $portOut
  }
}

$gate = if ($reason.Count -eq 0) { 'PASS' } else { 'FAIL' }

@(
  'Runtime MVP implementation',
  'Delivered: shared runner discipline through runtime_runner_core',
  'Delivered: widget layer includes Panel, VerticalLayout, Label, Button, InputBox, ListPanel, ScrollContainer, FocusManager, Checkbox, Toolbar, StatusBar',
  'Delivered: apps/widget_sandbox interaction coverage and deterministic logs',
  'Delivered: apps/port_probe app-like slice with add/select/remove/status/filter behavior',
  "Gate: $gate"
) | Set-Content -Path $implSummary -Encoding utf8

@(
  'Missing scope toward full Qt replacement:',
  '- Real text shaping and glyph rasterization pipeline',
  '- Advanced layout systems (flex/grid, docking with persistence)',
  '- Rich control set (tables, trees, menus, dialogs)',
  '- Accessibility, IME, internationalization, theme system depth',
  '- Cross-platform backend parity beyond Win32/D3D11'
) | Set-Content -Path $missingScope -Encoding utf8

@(
  'Run instructions:',
  '1) pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\phase22\phase22_internal_mvp_runner.ps1',
  '2) Inspect 98_gate_22.txt in PF',
  '3) Review widget and port stdout/stderr logs for evidence markers',
  '4) Use ZIP artifact for handoff'
) | Set-Content -Path $runInstructions -Encoding utf8

@(
  'PHASE=22',
  "TS=$(Get-Date -Format o)",
  "build_ok=$buildOk",
  "widget_launch_ok=$widgetLaunchOk",
  "widget_exit_code=$widgetExitCode",
  "port_launch_ok=$portLaunchOk",
  "port_exit_code=$portExitCode",
  "widget_no_crash=$widgetNoCrash",
  "widget_startup_evidence=$widgetStartup",
  "widget_exit_evidence=$widgetExit",
  "widget_text_evidence=$widgetText",
  "widget_list_evidence=$widgetList",
  "widget_scroll_evidence=$widgetScroll",
  "widget_button_evidence=$widgetButtons",
  "widget_checkbox_evidence=$widgetCheckbox",
  "widget_status_evidence=$widgetStatus",
  "port_no_crash=$portNoCrash",
  "port_startup_evidence=$portStartup",
  "port_input_evidence=$portInput",
  "port_add_evidence=$portAdd",
  "port_select_evidence=$portSelect",
  "port_remove_evidence=$portRemove",
  "port_status_evidence=$portStatus",
  "port_checkbox_evidence=$portCheckbox",
  "port_exit_evidence=$portExit",
  "GATE=$gate",
  'reason=' + ($reason -join ','),
  'first_failing_component=' + $firstFailingComponent
) | Set-Content -Path $gateFile -Encoding utf8

if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

$gateFileScan = Get-ChildItem -LiteralPath $proofRoot -Recurse -Force -File |
  Where-Object { $_.Name -eq '98_gate_22.txt' } |
  Sort-Object LastWriteTimeUtc -Descending |
  Select-Object -First 1

if (-not $gateFileScan) { throw 'missing_gate_file' }

$pf = Split-Path $gateFileScan.FullName -Parent
$zip = Join-Path $proofRoot ((Split-Path $pf -Leaf) + '.zip')

if (-not (Test-Path -LiteralPath $pf))  { throw 'bad_printed_paths:pf_missing' }
if (-not (Test-Path -LiteralPath $zip)) { throw 'bad_printed_paths:zip_missing' }

$pfResolved = (Resolve-Path -LiteralPath $pf).Path
$zipResolved = (Resolve-Path -LiteralPath $zip).Path
$proofResolved = (Resolve-Path -LiteralPath $proofRoot).Path

if (-not $pfResolved.StartsWith($proofResolved + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'bad_printed_paths:pf_outside_proof'
}
if (-not $zipResolved.StartsWith($proofResolved + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'bad_printed_paths:zip_outside_proof'
}

${badProofPattern} = ('Runtime' + '_proof')
if ($pfResolved -match [regex]::Escape(${badProofPattern}) -or $zipResolved -match [regex]::Escape(${badProofPattern})) {
  throw 'bad_printed_paths:forbidden_suffix_detected'
}

Write-Output "PF=$pfResolved"
Write-Output "ZIP=$zipResolved"
Write-Output "GATE=$gate"

if ($gate -ne 'PASS') {
  Get-Content -LiteralPath $gateFile
  if ($firstFailingComponent) {
    Write-Output "FIRST_FAILING_COMPONENT=$firstFailingComponent"
  }

  if ($firstFailLog -and (Test-Path $firstFailLog)) {
    Write-Output "--- LOG TAIL ($firstFailLog) ---"
    Get-Content -LiteralPath $firstFailLog -Tail 200
  }

  if (Test-Path $widgetOut) {
    Write-Output '--- WIDGET STDOUT TAIL ---'
    Get-Content -LiteralPath $widgetOut -Tail 200
  }
  if (Test-Path $widgetErr) {
    Write-Output '--- WIDGET STDERR TAIL ---'
    Get-Content -LiteralPath $widgetErr -Tail 200
  }
  if (Test-Path $portOut) {
    Write-Output '--- PORT STDOUT TAIL ---'
    Get-Content -LiteralPath $portOut -Tail 200
  }
  if (Test-Path $portErr) {
    Write-Output '--- PORT STDERR TAIL ---'
    Get-Content -LiteralPath $portErr -Tail 200
  }

  exit 2
}

exit 0
