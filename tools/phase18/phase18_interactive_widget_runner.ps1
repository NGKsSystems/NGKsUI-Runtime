param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  'hey stupid Fucker, wrong window again'
  exit 1
}

$root = (Get-Location).Path
$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File ".\tools\runtime_runner_core.ps1" -phase 18 -tag "interactive_widget"
$pf = $paths[0].Trim()
$zip = $paths[1].Trim()
$expectedProof = "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime\_proof"
$rootProofPrefix = $expectedProof + "\"

@(
  'PHASE=18',
  "TS=$(Get-Date -Format o)",
  "ROOT=$root"
) | Set-Content -Path (Join-Path $pf '00_context.txt') -Encoding utf8

git status *> (Join-Path $pf '01_status.txt')
git log -1 *> (Join-Path $pf '02_head.txt')

$configLog = Join-Path $pf '20_config.txt'
$buildLog = Join-Path $pf '21_build.txt'
$runOut = Join-Path $pf '30_run_stdout.txt'
$runErr = Join-Path $pf '31_run_stderr.txt'
$gateFile = Join-Path $pf '98_gate_18.txt'

$graphPlan = Join-Path $root 'build_graph\debug\ngksbuildcore_plan.json'
$exe = Join-Path $root 'build\debug\bin\widget_sandbox.exe'

$buildOk = $false
$launchOk = $false
$exitCode = -999
$noCrash = $false
$resizeEvidence = $false
$interactionEvidence = $false
$reason = @()

try {
  @(
    'BUILD_SYSTEM=NGKsDevFabEco graph',
    "PLAN=$graphPlan",
    "EXE_TARGET=$exe"
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

  if (-not (Test-Path $exe)) {
    throw "Graph build completed but EXE missing: $exe"
  }

  $buildOk = $true
}
catch {
  $reason += 'build_failed'
}

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
$resizeEvidence = [regex]::IsMatch($combined, 'widget_resize_path_exercised=1|window_resize_callback', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$interactionEvidence = [regex]::IsMatch($combined, 'button_click=one|button_click=two|button_click=three|widget_click_simulated=', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

if (-not $buildOk) { }
elseif (-not $launchOk) { $reason += 'launch_failed' }
elseif ($exitCode -ne 0) { $reason += "exit_code=$exitCode" }

if (-not $noCrash) { $reason += 'crash_detected' }
if (-not $resizeEvidence) { $reason += 'resize_path_not_exercised' }
if (-not $interactionEvidence) { $reason += 'no_widget_interaction_evidence' }

if (-not $pf.StartsWith($rootProofPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
  $reason += 'bad_proof_path'
}

$gate = if ($reason.Count -eq 0) { 'PASS' } else { 'FAIL' }

@(
  'PHASE=18',
  "TS=$(Get-Date -Format o)",
  "build_ok=$buildOk",
  "launch_ok=$launchOk",
  "exit_code=$exitCode",
  "no_crash=$noCrash",
  "resize_evidence=$resizeEvidence",
  "interaction_evidence=$interactionEvidence",
  "GATE=$gate",
  'reason=' + ($reason -join ',')
) | Set-Content -Path $gateFile -Encoding utf8

$gateFileObj = Get-Item -LiteralPath $gateFile -ErrorAction SilentlyContinue
if (-not $gateFileObj) {
  @(
    'PHASE=18',
    "TS=$(Get-Date -Format o)",
    "build_ok=$buildOk",
    "launch_ok=$launchOk",
    "exit_code=$exitCode",
    "no_crash=$noCrash",
    "resize_evidence=$resizeEvidence",
    "interaction_evidence=$interactionEvidence",
    'GATE=FAIL',
    'reason=bad_printed_paths'
  ) | Set-Content -Path $gateFile -Encoding utf8
  $gate = 'FAIL'
  $gateFileObj = Get-Item -LiteralPath $gateFile
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
    'PHASE=18',
    "TS=$(Get-Date -Format o)",
    "build_ok=$buildOk",
    "launch_ok=$launchOk",
    "exit_code=$exitCode",
    "no_crash=$noCrash",
    "resize_evidence=$resizeEvidence",
    "interaction_evidence=$interactionEvidence",
    'GATE=FAIL',
    'reason=bad_printed_paths'
  ) | Set-Content -Path $gateFile -Encoding utf8
  $gate = 'FAIL'
}

$repo = $root
$proofRoot = Join-Path $repo "_proof"
$gateFileScan = Get-ChildItem -LiteralPath $proofRoot -Recurse -Force -File |
  Where-Object { $_.Name -eq "98_gate_18.txt" } |
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

if ($gate -ne 'PASS') { exit 2 }
exit 0
