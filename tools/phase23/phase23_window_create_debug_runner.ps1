param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  'hey stupid Fucker, wrong window again'
  exit 1
}

$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File ".\tools\runtime_runner_common.ps1" -phase 23 -tag "window_create_debug"
if (-not $paths -or $paths.Count -lt 2) {
  throw 'runtime_runner_common did not return PF/ZIP'
}

$repo = (Get-Location).Path
$proofRoot = Join-Path $repo '_proof'
$pf = $paths[0].Trim()
$zip = $paths[1].Trim()

$proofRootResolved = (Resolve-Path -LiteralPath $proofRoot).Path
$pfResolved = ''
if (Test-Path -LiteralPath $pf) {
  $pfResolved = (Resolve-Path -LiteralPath $pf).Path
}

$legalProofPrefix = $proofRootResolved + [System.IO.Path]::DirectorySeparatorChar
$pfUnderLegalRoot = $false
if ($pfResolved) {
  $pfUnderLegalRoot = $pfResolved.StartsWith($legalProofPrefix, [System.StringComparison]::OrdinalIgnoreCase)
}
$zipCanonical = [System.IO.Path]::GetFullPath($zip)
$zipUnderLegalRoot = $zipCanonical.StartsWith($legalProofPrefix, [System.StringComparison]::OrdinalIgnoreCase)

$buildLog = Join-Path $pf '21_build.txt'
$stdoutFile = Join-Path $pf '30_widget_stdout.txt'
$stderrFile = Join-Path $pf '31_widget_stderr.txt'
$gateFile = Join-Path $pf '98_gate_23.txt'

$reasons = New-Object System.Collections.Generic.List[string]
$buildOk = $false
$runLaunchOk = $false
$runTimedOut = $false
$exitCode = -999

if (-not (Test-Path -LiteralPath $pf) -or -not $pfUnderLegalRoot) {
  $reasons.Add('bad_proof_path')
}
if (-not $zipUnderLegalRoot) {
  $reasons.Add('bad_zip_path')
}

$graphPlan = Join-Path $repo 'build_graph\debug\ngksbuildcore_plan.json'
$graphPlanAlt = Join-Path $repo 'build_graph\debug\ngksgraph_plan.json'

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

try {
  if (-not (Test-Path $graphPlan)) {
    throw "graph_plan_missing:$graphPlan"
  }

  .\tools\enter_msvc_env.ps1 *> $buildLog

  $plan = Get-Content -Raw -LiteralPath $graphPlan | ConvertFrom-Json
  foreach ($node in $plan.nodes) {
    if ($null -eq $node.cmd -or [string]::IsNullOrWhiteSpace([string]$node.cmd)) {
      continue
    }

    "=== NODE: $($node.desc) ===" | Add-Content -Path $buildLog -Encoding utf8
    "CMD: $($node.cmd)" | Add-Content -Path $buildLog -Encoding utf8

    $cmdOut = cmd.exe /d /c $node.cmd 2>&1
    if ($cmdOut) {
      $cmdOut | Add-Content -Path $buildLog -Encoding utf8
    }

    if ($LASTEXITCODE -ne 0) {
      throw "graph_node_failed:$($node.id)"
    }
  }

  $buildOk = $true
}
catch {
  $reasons.Add('build_failed')
  $_ | Out-String | Add-Content -Path $buildLog -Encoding utf8
}

$widgetExe = Resolve-WidgetExePath -RootPath $repo -PlanPath $graphPlan -PlanPathAlt $graphPlanAlt
if (-not $widgetExe) {
  $reasons.Add('widget_exe_missing')
}

if ($buildOk -and $widgetExe) {
  try {
    $proc = Start-Process -FilePath $widgetExe -PassThru -NoNewWindow -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
    $runLaunchOk = $true

    $done = $proc.WaitForExit(20000)
    if (-not $done) {
      try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
      $runTimedOut = $true
      $exitCode = 124
    } else {
      $proc.Refresh()
      $exitCode = [int]$proc.ExitCode
    }
  }
  catch {
    $reasons.Add('widget_launch_failed')
  }
}

if (-not $runLaunchOk -and $buildOk -and $widgetExe) {
  $reasons.Add('widget_launch_failed')
}
if ($runTimedOut) {
  $reasons.Add('widget_run_timeout')
}

$stdoutText = if (Test-Path $stdoutFile) { Get-Content -Raw -LiteralPath $stdoutFile } else { '' }
$stderrText = if (Test-Path $stderrFile) { Get-Content -Raw -LiteralPath $stderrFile } else { '' }
$combined = $stdoutText + "`n" + $stderrText

$milestones = @(
  'window_create_begin',
  'before_class_registration',
  'after_class_registration',
  'before_CreateWindowExW',
  'after_CreateWindowExW',
  'before_userdata_bind',
  'after_userdata_bind',
  'before_show_window',
  'after_show_window',
  'window_create_end'
)

$lastSeenIndex = -1
$firstMissingIndex = -1
$milestoneLines = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $milestones.Count; $i++) {
  $marker = $milestones[$i]
  $seen = ($combined -match [regex]::Escape($marker))
  $milestoneLines.Add("$marker=$seen")
  if ($seen) {
    $lastSeenIndex = $i
  } elseif ($firstMissingIndex -lt 0) {
    $firstMissingIndex = $i
  }
}

$lastSeen = ''
$nextMissing = ''
if ($lastSeenIndex -ge 0) {
  $lastSeen = $milestones[$lastSeenIndex]
}
if ($firstMissingIndex -ge 0) {
  $nextMissing = $milestones[$firstMissingIndex]
}

$cleanExit = ($exitCode -eq 0) -and ($combined -match 'widget_sandbox_exit=0')
$hasCrashSignal =
  ($exitCode -ne 0) -or
  $runTimedOut -or
  ($combined -match 'widget_sandbox_exception=') -or
  ($combined -match 'unhandled_exception') -or
  ($combined -match 'access violation') -or
  ($combined -match 'fatal')

$isolatedBoundary = $false
if ($hasCrashSignal -and $lastSeen -and $nextMissing) {
  $isolatedBoundary = $true
}

if (-not $cleanExit -and -not $isolatedBoundary -and -not ($reasons -contains 'widget_launch_failed') -and -not ($reasons -contains 'build_failed')) {
  $reasons.Add('no_useful_isolation_evidence')
}

$pass = $cleanExit -or $isolatedBoundary
if ($reasons -contains 'bad_proof_path') {
  $pass = $false
}
if ($reasons -contains 'bad_zip_path') {
  $pass = $false
}
if ($reasons.Count -gt 0 -and -not $cleanExit -and -not $isolatedBoundary) {
  $pass = $false
}

$gate = if ($pass) { 'PASS' } else { 'FAIL' }

$wmNccreateSeen = ($combined -match 'wndproc_message=WM_NCCREATE')
$wmCreateSeen = ($combined -match 'wndproc_message=WM_CREATE')
$firstGetSeen = ($combined -match 'wndproc_first_get_userdata')
$firstSetSeen = ($combined -match 'wndproc_first_set_userdata')
$nullSafePathSeen = ($combined -match 'wndproc_null_userdata_safe_path')

@(
  "phase=23_window_create_debug",
  "timestamp=$(Get-Date -Format o)",
  "pf=$pf",
  "pf_resolved=$pfResolved",
  "proof_root_resolved=$proofRootResolved",
  "pf_under_legal_root=$pfUnderLegalRoot",
  "zip_canonical=$zipCanonical",
  "zip_under_legal_root=$zipUnderLegalRoot",
  "widget_exe=$widgetExe",
  "build_ok=$buildOk",
  "run_launch_ok=$runLaunchOk",
  "run_timed_out=$runTimedOut",
  "exit_code=$exitCode",
  "clean_exit=$cleanExit",
  "has_crash_signal=$hasCrashSignal",
  "isolated_boundary=$isolatedBoundary",
  "last_seen_milestone=$lastSeen",
  "next_missing_milestone=$nextMissing",
  "wm_nccreate_seen=$wmNccreateSeen",
  "wm_create_seen=$wmCreateSeen",
  "first_get_userdata_seen=$firstGetSeen",
  "first_set_userdata_seen=$firstSetSeen",
  "null_userdata_safe_path_seen=$nullSafePathSeen",
  "reasons=$($reasons -join ',')",
  "gate=$gate"
) + $milestoneLines | Set-Content -Path $gateFile -Encoding utf8

if (Test-Path $zip) {
  Remove-Item -Force $zip
}
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

$zipResolved = $zipCanonical
if (Test-Path -LiteralPath $zip) {
  $zipResolved = (Resolve-Path -LiteralPath $zip).Path
}

$pfPrint = $pf
if ($pfResolved) {
  $pfPrint = $pfResolved
}

$badProofToken = (Split-Path -Leaf $repo) + '_proof'
$pfHasBadProofToken = $pfPrint -like ("*" + $badProofToken + "*")
$zipHasBadProofToken = $zipResolved -like ("*" + $badProofToken + "*")
if ($pfHasBadProofToken) {
  $reasons.Add('bad_pf_token')
}
if ($zipHasBadProofToken) {
  $reasons.Add('bad_zip_token')
}
if ($pfHasBadProofToken -or $zipHasBadProofToken) {
  $gate = 'FAIL'
}

Write-Output "PF=$pfPrint"
Write-Output "ZIP=$zipResolved"
Write-Output "GATE=$gate"

if ($gate -eq 'FAIL') {
  Get-Content -Path $gateFile
  if (Test-Path $stdoutFile) {
    Get-Content -Path $stdoutFile -Tail 100
  }
  if (Test-Path $stderrFile) {
    Get-Content -Path $stderrFile -Tail 100
  }
}
