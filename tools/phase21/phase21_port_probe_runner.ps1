param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  'hey stupid Fucker, wrong window again'
  exit 1
}

$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File ".\tools\runtime_runner_core.ps1" -phase 21 -tag "port_probe"
if (-not $paths -or $paths.Count -lt 2) {
  throw 'runtime_runner_core did not return PF/ZIP'
}

$pf = ([string]$paths[0]).Trim()
$zip = ([string]$paths[1]).Trim()

$root = (Get-Location).Path
$expectedProof = "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime\_proof"
$rootProofPrefix = $expectedProof + '\'

$gitStatusFile = Join-Path $pf '01_status.txt'
$gitHeadFile = Join-Path $pf '02_head.txt'
$configLog = Join-Path $pf '20_config.txt'
$buildLog = Join-Path $pf '21_build.txt'
$runOut = Join-Path $pf '30_run_stdout.txt'
$runErr = Join-Path $pf '31_run_stderr.txt'
$gateFile = Join-Path $pf '98_gate_21.txt'

git status *> $gitStatusFile
git log -1 *> $gitHeadFile

$graphPlan = Join-Path $root 'build_graph\debug\ngksbuildcore_plan.json'
$graphPlanAlt = Join-Path $root 'build_graph\debug\ngksgraph_plan.json'

$buildOk = $false
$launchOk = $false
$exitCode = -999
$noCrash = $false
$startupEvidence = $false
$inputEvidence = $false
$addEvidence = $false
$selectEvidence = $false
$removeEvidence = $false
$statusEvidence = $false
$cleanExitEvidence = $false
$reason = @()

function Resolve-PortProbeExePath {
  param(
    [string]$RootPath,
    [string]$PlanPath,
    [string]$PlanPathAlt
  )

  $candidate = @()

  if (Test-Path $PlanPathAlt) {
    try {
      $alt = Get-Content -Raw -LiteralPath $PlanPathAlt | ConvertFrom-Json
      if ($alt.targets) {
        foreach ($target in $alt.targets) {
          if ($target.name -eq 'port_probe' -and $target.output_path) {
            $candidate += (Join-Path $RootPath ([string]$target.output_path))
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
              if ($outText -match 'port_probe\.exe$') {
                $candidate += (Join-Path $RootPath $outText)
              }
            }
          }
        }
      }
    }
    catch {
    }
  }

  $candidate += (Join-Path $RootPath 'build\debug\bin\port_probe.exe')

  foreach ($path in ($candidate | Select-Object -Unique)) {
    if (Test-Path $path) {
      return $path
    }
  }

  return (Join-Path $RootPath 'build\debug\bin\port_probe.exe')
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

  $engineLib = Join-Path $root 'build\debug\lib\engine.lib'
  if (-not (Test-Path $engineLib)) {
    throw "Engine library missing: $engineLib"
  }

  $portObjDir = Join-Path $root 'build\debug\obj\port_probe\apps\port_probe'
  $portObj = Join-Path $portObjDir 'main.obj'
  $portExe = Join-Path $root 'build\debug\bin\port_probe.exe'

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

  if (-not (Test-Path $portExe)) {
    throw "port_probe exe missing: $portExe"
  }

  $buildOk = $true
}
catch {
  $reason += 'build_failed'
}

$exe = Resolve-PortProbeExePath -RootPath $root -PlanPath $graphPlan -PlanPathAlt $graphPlanAlt
if (-not (Test-Path $exe)) {
  $exe = Join-Path $root 'build\debug\bin\port_probe.exe'
}
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

$noCrash = -not [regex]::IsMatch($combined, 'port_probe_exception|access violation|fatal|unhandled|terminate', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$startupEvidence = [regex]::IsMatch($combined, 'port_probe_startup=1', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$inputEvidence = [regex]::IsMatch($combined, 'port_probe_input value=', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$addEvidence = [regex]::IsMatch($combined, 'port_probe_add item=', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$selectEvidence = [regex]::IsMatch($combined, 'port_probe_select index=', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$removeEvidence = [regex]::IsMatch($combined, 'port_probe_remove item=', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$statusEvidence = [regex]::IsMatch($combined, 'port_probe_status=', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$cleanExitEvidence = [regex]::IsMatch($combined, 'port_probe_exit=clean', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

if (-not $buildOk) { }
elseif (-not $launchOk) { $reason += 'launch_failed' }
elseif ($exitCode -ne 0) { $reason += "exit_code=$exitCode" }

if (-not $noCrash) { $reason += 'crash_detected' }
if (-not $startupEvidence) { $reason += 'startup_evidence_missing' }
if (-not $inputEvidence) { $reason += 'input_evidence_missing' }
if (-not $addEvidence) { $reason += 'add_evidence_missing' }
if (-not $selectEvidence) { $reason += 'select_evidence_missing' }
if (-not $removeEvidence) { $reason += 'remove_evidence_missing' }
if (-not $statusEvidence) { $reason += 'status_evidence_missing' }
if (-not $cleanExitEvidence) { $reason += 'clean_exit_evidence_missing' }

if (
  (-not (Test-Path $pf)) -or
  (-not $pf.StartsWith($rootProofPrefix, [System.StringComparison]::OrdinalIgnoreCase)) -or
  (-not $zip.StartsWith($rootProofPrefix, [System.StringComparison]::OrdinalIgnoreCase))
) {
  $reason += 'bad_proof_path'
}

$gate = if ($reason.Count -eq 0) { 'PASS' } else { 'FAIL' }

@(
  'PHASE=21',
  "TS=$(Get-Date -Format o)",
  "build_ok=$buildOk",
  "launch_ok=$launchOk",
  "exit_code=$exitCode",
  "no_crash=$noCrash",
  "startup_evidence=$startupEvidence",
  "input_evidence=$inputEvidence",
  "add_evidence=$addEvidence",
  "select_evidence=$selectEvidence",
  "remove_evidence=$removeEvidence",
  "status_evidence=$statusEvidence",
  "clean_exit_evidence=$cleanExitEvidence",
  "GATE=$gate",
  'reason=' + ($reason -join ',')
) | Set-Content -Path $gateFile -Encoding utf8

if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

if (
  (-not (Test-Path $zip)) -or
  (-not $zip.StartsWith($rootProofPrefix, [System.StringComparison]::OrdinalIgnoreCase))
) {
  @(
    'PHASE=21',
    "TS=$(Get-Date -Format o)",
    "build_ok=$buildOk",
    "launch_ok=$launchOk",
    "exit_code=$exitCode",
    "no_crash=$noCrash",
    "startup_evidence=$startupEvidence",
    "input_evidence=$inputEvidence",
    "add_evidence=$addEvidence",
    "select_evidence=$selectEvidence",
    "remove_evidence=$removeEvidence",
    "status_evidence=$statusEvidence",
    "clean_exit_evidence=$cleanExitEvidence",
    'GATE=FAIL',
    'reason=bad_proof_path'
  ) | Set-Content -Path $gateFile -Encoding utf8
  $gate = 'FAIL'
}

$repo = $root
$proofRoot = Join-Path $repo "_proof"
$gateFileScan = Get-ChildItem -LiteralPath $proofRoot -Recurse -Force -File |
  Where-Object { $_.Name -eq "98_gate_21.txt" } |
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
