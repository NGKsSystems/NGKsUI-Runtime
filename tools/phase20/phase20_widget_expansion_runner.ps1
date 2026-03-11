param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  'hey stupid Fucker, wrong window again'
  exit 1
}

$root = (Get-Location).Path
$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File ".\tools\runtime_runner_core.ps1" -phase 20 -tag "widget_expansion"
$pf = $paths[0].Trim()
$zip = $paths[1].Trim()
$expectedProof = "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime\_proof"
$rootProofPrefix = $expectedProof + '\'

@(
  'PHASE=20',
  "TS=$(Get-Date -Format o)",
  "ROOT=$root"
) | Set-Content -Path (Join-Path $pf '00_context.txt') -Encoding utf8

git status *> (Join-Path $pf '01_status.txt')
git log -1 *> (Join-Path $pf '02_head.txt')

$configLog = Join-Path $pf '20_config.txt'
$buildLog = Join-Path $pf '21_build.txt'
$runOut = Join-Path $pf '30_run_stdout.txt'
$runErr = Join-Path $pf '31_run_stderr.txt'
$gateFile = Join-Path $pf '98_gate_20.txt'

$graphPlan = Join-Path $root 'build_graph\debug\ngksbuildcore_plan.json'
$graphPlanAlt = Join-Path $root 'build_graph\debug\ngksgraph_plan.json'

$buildOk = $false
$launchOk = $false
$exitCode = -999
$noCrash = $false
$setupEvidence = $false
$textboxEvidence = $false
$listEvidence = $false
$scrollEvidence = $false
$buttonEvidence = $false
$reason = @()

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
    catch {
    }
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
    catch {
    }
  }

  $candidatePaths += (Join-Path $RootPath 'build\debug\bin\widget_sandbox.exe')
  $candidatePaths += (Join-Path $RootPath 'build\release\bin\widget_sandbox.exe')

  foreach ($candidate in ($candidatePaths | Select-Object -Unique)) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  return (Join-Path $RootPath 'build\debug\bin\widget_sandbox.exe')
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
        $outputPath = Join-Path $root ([string]$output)
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

  $buildOk = $true
}
catch {
  $reason += 'build_failed'
}

$exe = Resolve-WidgetExePath -RootPath $root -PlanPath $graphPlan -PlanPathAlt $graphPlanAlt
"EXE_RESOLVED=$exe" | Add-Content -Path $configLog -Encoding utf8

if ($buildOk) {
  if (-not (Test-Path $exe)) {
    $reason += 'exe_missing'
  }
  else {
    try {
      $proc = Start-Process -FilePath $exe -PassThru -NoNewWindow -RedirectStandardOutput $runOut -RedirectStandardError $runErr
      $launchOk = $true
      $done = $proc.WaitForExit(15000)
      if (-not $done) {
        try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
        $exitCode = 124
        $reason += 'run_timeout'
      }
      else {
        $proc.Refresh()
        $exitCode = [int]$proc.ExitCode
      }
    }
    catch {
      $reason += 'launch_failed'
    }
  }
}

$combined = ''
if (Test-Path $runOut) { $combined += (Get-Content -Raw -LiteralPath $runOut -ErrorAction SilentlyContinue) + "`n" }
if (Test-Path $runErr) { $combined += (Get-Content -Raw -LiteralPath $runErr -ErrorAction SilentlyContinue) + "`n" }

$noCrash = -not [regex]::IsMatch($combined, 'Crash=EXCEPTION|widget_sandbox_exception|access violation|fatal|unhandled|terminate', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$setupEvidence = [regex]::IsMatch($combined, 'widget_label_text=.+|widget_textbox_setup=1', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$textboxEvidence = [regex]::IsMatch($combined, 'widget_textbox_value=.*caret=\d+|widget_textbox_focus=', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$listEvidence = [regex]::IsMatch($combined, 'widget_list_selection=\d+\s+text=', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$scrollEvidence = [regex]::IsMatch($combined, 'widget_scroll_offset=\d+\s+delta=', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$buttonEvidence = [regex]::IsMatch($combined, 'button_click=one|button_click=two|button_click=three', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

if (-not $buildOk) { }
elseif (-not $launchOk) { $reason += 'launch_failed' }
elseif ($exitCode -ne 0) { $reason += "exit_code=$exitCode" }

if (-not $noCrash) { $reason += 'crash_detected' }
if (-not $setupEvidence) { $reason += 'setup_evidence_missing' }
if (-not $textboxEvidence) { $reason += 'textbox_evidence_missing' }
if (-not $listEvidence) { $reason += 'list_evidence_missing' }
if (-not $scrollEvidence) { $reason += 'scroll_evidence_missing' }
if (-not $buttonEvidence) { $reason += 'button_evidence_missing' }

if (-not $pf.StartsWith($rootProofPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
  $reason += 'bad_proof_path'
}

$gate = if ($reason.Count -eq 0) { 'PASS' } else { 'FAIL' }

@(
  'PHASE=20',
  "TS=$(Get-Date -Format o)",
  "build_ok=$buildOk",
  "launch_ok=$launchOk",
  "exit_code=$exitCode",
  "no_crash=$noCrash",
  "setup_evidence=$setupEvidence",
  "textbox_evidence=$textboxEvidence",
  "list_evidence=$listEvidence",
  "scroll_evidence=$scrollEvidence",
  "button_evidence=$buttonEvidence",
  "GATE=$gate",
  'reason=' + ($reason -join ',')
) | Set-Content -Path $gateFile -Encoding utf8

$gateFileObj = Get-Item -LiteralPath $gateFile -ErrorAction SilentlyContinue
if (-not $gateFileObj) {
  throw 'Gate file missing after write.'
}

if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

if (
  (-not (Test-Path $pf)) -or
  (-not (Test-Path $zip)) -or
  (-not $pf.StartsWith($rootProofPrefix, [System.StringComparison]::OrdinalIgnoreCase)) -or
  (-not $zip.StartsWith($rootProofPrefix, [System.StringComparison]::OrdinalIgnoreCase))
) {
  @(
    'PHASE=20',
    "TS=$(Get-Date -Format o)",
    "build_ok=$buildOk",
    "launch_ok=$launchOk",
    "exit_code=$exitCode",
    "no_crash=$noCrash",
    "setup_evidence=$setupEvidence",
    "textbox_evidence=$textboxEvidence",
    "list_evidence=$listEvidence",
    "scroll_evidence=$scrollEvidence",
    "button_evidence=$buttonEvidence",
    'GATE=FAIL',
    'reason=bad_printed_paths'
  ) | Set-Content -Path $gateFile -Encoding utf8
  $gate = 'FAIL'
}

$repo = $root
$proofRoot = Join-Path $repo "_proof"
$gateFileScan = Get-ChildItem -LiteralPath $proofRoot -Recurse -Force -File |
  Where-Object { $_.Name -eq "98_gate_20.txt" } |
  Sort-Object LastWriteTimeUtc -Descending |
  Select-Object -First 1

if (-not $gateFileScan) { throw "missing_gate_file" }

$pf = Split-Path $gateFileScan.FullName -Parent
$zip = Join-Path $proofRoot ((Split-Path $pf -Leaf) + ".zip")

if (-not (Test-Path -LiteralPath $pf))  { throw "bad_printed_paths:pf_missing" }
if (-not (Test-Path -LiteralPath $zip)) { throw "bad_printed_paths:zip_missing" }

$pfResolved = (Resolve-Path -LiteralPath $pf).Path
$zipResolved = (Resolve-Path -LiteralPath $zip).Path
$proofResolved = (Resolve-Path -LiteralPath $proofRoot).Path

if (-not $pfResolved.StartsWith($proofResolved + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "bad_printed_paths:pf_outside_proof"
}
if (-not $zipResolved.StartsWith($proofResolved + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "bad_printed_paths:zip_outside_proof"
}
${badProofPattern} = ('Runtime' + '_proof')
if ($pfResolved -match [regex]::Escape(${badProofPattern}) -or $zipResolved -match [regex]::Escape(${badProofPattern})) {
  throw "bad_printed_paths:forbidden_suffix_detected"
}

Write-Output "PF=$pfResolved"
Write-Output "ZIP=$zipResolved"
Write-Output "GATE=$gate"

if ($gate -ne 'PASS') {
  Get-Content -LiteralPath $gateFile
  exit 2
}

exit 0
