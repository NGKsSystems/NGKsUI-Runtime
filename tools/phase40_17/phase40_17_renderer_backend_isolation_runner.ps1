param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File '.\tools\runtime_runner_common.ps1' -phase 40_17 -tag 'renderer_backend_isolation'
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
$f10 = Join-Path $pf '10_backend_modes.txt'
$f11 = Join-Path $pf '11_window_paint_trace.txt'
$f12 = Join-Path $pf '12_files_touched.txt'
$f13 = Join-Path $pf '13_build_output.txt'
$f14 = Join-Path $pf '14_d3d_vs_fallback_observations.txt'
$f15 = Join-Path $pf '15_runtime_observations.txt'
$f16 = Join-Path $pf '16_behavior_summary.txt'
$f98 = Join-Path $pf '98_gate_phase40_17.txt'

git status *> $f1
git log -1 *> $f2
git diff --name-only | Set-Content -Path $f12 -Encoding utf8

@(
  'mode_1=d3d_minimal (NGK_PHASE40_17_BACKEND=d3d)'
  'mode_2=gdi_fallback (NGK_PHASE40_17_BACKEND=gdi)'
  'layout_in_both=left solid + right top/mid/lower solids + gauge placeholder'
  'comparison_focus=flash behavior + resize/minimize/restore + WM_PAINT interactions'
) | Set-Content -Path $f10 -Encoding utf8

@(
  'window_creation_path=engine/platform/win32/src/win32_window.cpp::Win32Window::create'
  'wm_paint_path=engine/platform/win32/src/win32_window.cpp::Win32Window::wnd_proc -> paint_callback_'
  'resize_path=engine/platform/win32/src/win32_window.cpp::Win32Window::wnd_proc WM_SIZE + apps/widget_sandbox/main.cpp::set_resize_callback'
  'minimize_restore_path=engine/platform/win32/src/win32_window.cpp::Win32Window::wnd_proc WM_SIZE + minimized flag in sandbox'
  'd3d_backbuffer_swapchain=engine/gfx/win32/src/d3d11_renderer.cpp::init/create_render_target/resize'
  'd3d_clear_begin_end_present=engine/gfx/win32/src/d3d11_renderer.cpp::begin_frame/clear/end_frame'
  'fallback_draw_path=apps/widget_sandbox/main.cpp::draw_minimal_gdi_layout'
  'frame_ownership_difference=d3d path uses D3D11Renderer queue/present; fallback path uses direct GDI FillRect on HWND DC'
) | Set-Content -Path $f11 -Encoding utf8

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

  .\tools\enter_msvc_env.ps1 *> $f13

  $plan = Get-Content -Raw -LiteralPath $graphPlan | ConvertFrom-Json
  foreach ($node in $plan.nodes) {
    if ($null -eq $node.cmd -or [string]::IsNullOrWhiteSpace([string]$node.cmd)) {
      continue
    }

    "=== NODE: $($node.desc) ===" | Add-Content -Path $f13 -Encoding utf8
    "CMD: $($node.cmd)" | Add-Content -Path $f13 -Encoding utf8

    $cmdOut = cmd.exe /d /c $node.cmd 2>&1
    if ($cmdOut) {
      $cmdOut | Add-Content -Path $f13 -Encoding utf8
    }

    if ($LASTEXITCODE -ne 0) {
      throw "graph_node_failed:$($node.id)"
    }
  }

  $buildOk = $true
}
catch {
  $_ | Out-String | Add-Content -Path $f13 -Encoding utf8
}

$widgetExe = Resolve-WidgetExePath -RootPath $root -PlanPath $graphPlan -PlanPathAlt $graphPlanAlt

function Invoke-BackendRun {
  param(
    [string]$exePath,
    [string]$backendMode
  )

  $result = [ordered]@{
    backend = $backendMode
    run_ok = $false
    exit_code = -999
    clean_exit = $false
    text = ''
  }

  try {
    $oldRecovery = $env:NGK_WIDGET_RECOVERY_MODE
    $oldForceFull = $env:NGK_RENDER_RECOVERY_FORCE_FULL
    $oldDemo = $env:NGK_WIDGET_SANDBOX_DEMO
    $oldBackend = $env:NGK_PHASE40_17_BACKEND

    $env:NGK_WIDGET_RECOVERY_MODE = '1'
    $env:NGK_RENDER_RECOVERY_FORCE_FULL = '1'
    $env:NGK_WIDGET_SANDBOX_DEMO = '1'
    $env:NGK_PHASE40_17_BACKEND = $backendMode

    $runOut = & $exePath '--demo' 2>&1
    $text = ($runOut | Out-String)
    $exitCode = $LASTEXITCODE

    $result.text = $text
    $result.exit_code = $exitCode
    $result.run_ok = ($exitCode -eq 0)
    $result.clean_exit = (($exitCode -eq 0) -and ($text -match 'widget_sandbox_exit=0'))

    $env:NGK_WIDGET_RECOVERY_MODE = $oldRecovery
    $env:NGK_RENDER_RECOVERY_FORCE_FULL = $oldForceFull
    $env:NGK_WIDGET_SANDBOX_DEMO = $oldDemo
    $env:NGK_PHASE40_17_BACKEND = $oldBackend
  }
  catch {
    $result.text = ($_ | Out-String)
  }

  return [PSCustomObject]$result
}

$d3dRun = $null
$gdiRun = $null
if ($buildOk -and $widgetExe) {
  $d3dRun = Invoke-BackendRun -exePath $widgetExe -backendMode 'd3d'
  $gdiRun = Invoke-BackendRun -exePath $widgetExe -backendMode 'gdi'
}

$d3dText = if ($d3dRun) { [string]$d3dRun.text } else { '' }
$gdiText = if ($gdiRun) { [string]$gdiRun.text } else { '' }

@(
  '=== D3D MODE OUTPUT ==='
  $d3dText
  '=== GDI MODE OUTPUT ==='
  $gdiText
) | Set-Content -Path $f15 -Encoding utf8

$d3dBackendSignal = $d3dText -match 'widget_phase40_17_backend=d3d'
$gdiBackendSignal = $gdiText -match 'widget_phase40_17_backend=gdi'
$d3dLeft = $d3dText -match 'widget_phase40_12_left=1'
$d3dRight = $d3dText -match 'widget_phase40_12_right=1'
$gdiLeft = $gdiText -match 'widget_phase40_12_left=1'
$gdiRight = $gdiText -match 'widget_phase40_12_right=1'
$d3dMinimal = $d3dText -match 'widget_phase40_16_minimal_pipeline=1'
$gdiMinimal = $gdiText -match 'widget_phase40_16_minimal_pipeline=1'

$d3dVisual = $env:NGK_PHASE40_17_D3D_STABLE
$gdiVisual = $env:NGK_PHASE40_17_GDI_STABLE
$d3dVisualKnown = $d3dVisual -eq '0' -or $d3dVisual -eq '1'
$gdiVisualKnown = $gdiVisual -eq '0' -or $gdiVisual -eq '1'
$d3dStable = $d3dVisual -eq '1'
$gdiStable = $gdiVisual -eq '1'

$narrowed = $false
$suspect = 'unknown'
$basis = ''

if ($d3dRun -and $gdiRun) {
  if ($d3dRun.run_ok -and -not $gdiRun.run_ok) {
    $narrowed = $true
    $suspect = 'platform_or_fallback_path'
    $basis = 'd3d runs while gdi fallback fails to run'
  } elseif (-not $d3dRun.run_ok -and $gdiRun.run_ok) {
    $narrowed = $true
    $suspect = 'd3d_renderer_path'
    $basis = 'gdi fallback runs while d3d mode fails to run'
  } elseif ($d3dRun.run_ok -and $gdiRun.run_ok -and $d3dVisualKnown -and $gdiVisualKnown) {
    if ($d3dStable -and -not $gdiStable) {
      $narrowed = $true
      $suspect = 'platform_or_fallback_path'
      $basis = 'manual visual check: d3d stable, gdi unstable'
    } elseif (-not $d3dStable -and $gdiStable) {
      $narrowed = $true
      $suspect = 'd3d_renderer_path'
      $basis = 'manual visual check: d3d unstable, gdi stable'
    } elseif (-not $d3dStable -and -not $gdiStable) {
      $narrowed = $true
      $suspect = 'platform_window_pump_or_shared_presentation_path'
      $basis = 'manual visual check: both unstable under isolated backends'
    } elseif ($d3dStable -and $gdiStable) {
      $narrowed = $true
      $suspect = 'issue_not_reproduced_after_isolation'
      $basis = 'manual visual check: both stable after backend isolation'
    }
  }
}

@(
  "d3d_run_ok=$($d3dRun -and $d3dRun.run_ok)"
  "gdi_run_ok=$($gdiRun -and $gdiRun.run_ok)"
  "d3d_clean_exit=$($d3dRun -and $d3dRun.clean_exit)"
  "gdi_clean_exit=$($gdiRun -and $gdiRun.clean_exit)"
  "d3d_backend_signal=$d3dBackendSignal"
  "gdi_backend_signal=$gdiBackendSignal"
  "d3d_minimal_signals_left_right=$d3dLeft/$d3dRight"
  "gdi_minimal_signals_left_right=$gdiLeft/$gdiRight"
  "d3d_minimal_pipeline_signal=$d3dMinimal"
  "gdi_minimal_pipeline_signal=$gdiMinimal"
  "d3d_visual_known=$d3dVisualKnown"
  "gdi_visual_known=$gdiVisualKnown"
  "d3d_visual_stable=$d3dStable"
  "gdi_visual_stable=$gdiStable"
) | Set-Content -Path $f14 -Encoding utf8

@(
  "minimal_d3d_flashes=$(if ($d3dVisualKnown) { if ($d3dStable) { 'no' } else { 'yes' } } else { 'unknown' })"
  "fallback_gdi_flashes=$(if ($gdiVisualKnown) { if ($gdiStable) { 'no' } else { 'yes' } } else { 'unknown' })"
  "instability_scope=$(if ($narrowed) { $suspect } else { 'not_narrowed' })"
  "primary_suspect=$suspect"
  "decision_basis=$basis"
  'next_repair_direction='
  "  $(if ($suspect -eq 'd3d_renderer_path') { 'inspect swapchain/present/backbuffer ownership and overlay flush ordering' } elseif ($suspect -eq 'platform_window_pump_or_shared_presentation_path') { 'inspect WM_PAINT invalidation and frame ownership in win32 pump' } elseif ($suspect -eq 'platform_or_fallback_path') { 'inspect fallback path and shared window invalidation behavior' } elseif ($suspect -eq 'issue_not_reproduced_after_isolation') { 'reintroduce features in controlled order to find regression layer' } else { 'collect manual visual stability per backend to complete isolation verdict' })"
) | Set-Content -Path $f16 -Encoding utf8

$requiredFiles = @(
  '01_status.txt',
  '02_head.txt',
  '10_backend_modes.txt',
  '11_window_paint_trace.txt',
  '12_files_touched.txt',
  '13_build_output.txt',
  '14_d3d_vs_fallback_observations.txt',
  '15_runtime_observations.txt',
  '16_behavior_summary.txt'
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

$signalsOk = $buildOk -and $d3dRun -and $gdiRun -and $d3dRun.clean_exit -and $gdiRun.clean_exit -and $d3dBackendSignal -and $gdiBackendSignal -and $d3dMinimal -and $gdiMinimal -and $requiredPresent -and $pfUnderLegal -and $zipUnderLegal
$gate = if ($signalsOk -and $narrowed) { 'PASS' } else { 'FAIL' }
$failReason = ''
if (-not $signalsOk) {
  $failReason = 'backend runs/signals incomplete; isolation evidence insufficient'
} elseif (-not $narrowed) {
  $failReason = 'both backends executed but fault domain not narrowed (manual per-backend visual stability signals missing or identical without interpretation)'
}

@(
  'phase=40_17_renderer_backend_isolation'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "build_ok=$buildOk"
  "signals_ok=$signalsOk"
  "fault_domain_narrowed=$narrowed"
  "primary_suspect=$suspect"
  "decision_basis=$basis"
  "fail_reason=$failReason"
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
  Write-Output "backend_isolation_not_narrowed_reason=$failReason"
}
