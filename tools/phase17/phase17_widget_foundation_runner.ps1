$ErrorActionPreference = 'Stop'

$expectedRoot = "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime"
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  "hey stupid Fucker, wrong window again"
  exit 1
}

$root = (Get-Location).Path
$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File ".\tools\runtime_runner_core.ps1" -phase 17 -tag "widget_foundation"
$pf = $paths[0].Trim()
$zip = $paths[1].Trim()
$expectedProof = "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime\_proof"

@(
  "PHASE=17",
  "TS=$(Get-Date -Format o)",
  "ROOT=$root"
) | Set-Content -Path (Join-Path $pf "00_context.txt") -Encoding utf8

git status *> (Join-Path $pf "01_status.txt")
git log -1 *> (Join-Path $pf "02_head.txt")

$envLog = Join-Path $pf "10_enter_msvc_env.txt"
"=== ENTER MSVC ENV ===`nTS=$(Get-Date -Format o)" | Set-Content -Path $envLog -Encoding utf8
.\tools\enter_msvc_env.ps1 *>> $envLog

$buildDir = Join-Path $root "artifacts\build\phase17_widget_sandbox"
$configLog = Join-Path $pf "20_config.txt"
$buildLog = Join-Path $pf "21_build.txt"
$runOut = Join-Path $pf "30_run_stdout.txt"
$runErr = Join-Path $pf "31_run_stderr.txt"

$buildOk = $false
$launchOk = $false
$noCrash = $false
$exitCode = -999
$reason = ""

try {
  cmake -S .\apps\widget_sandbox -B $buildDir -G Ninja *> $configLog
  cmake --build $buildDir --config Release *> $buildLog
  $buildOk = $true
} catch {
  $reason = "build_failed"
}

$exe = Join-Path $buildDir "bin\widget_sandbox.exe"
if ($buildOk -and (Test-Path $exe)) {
  try {
    $proc = Start-Process -FilePath $exe -PassThru -NoNewWindow -RedirectStandardOutput $runOut -RedirectStandardError $runErr
    $launchOk = $true

    $done = $proc.WaitForExit(12000)
    if (-not $done) {
      try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
      $exitCode = 124
      $reason = "run_timeout"
    } else {
      $proc.Refresh()
      $exitCode = [int]$proc.ExitCode
    }
  } catch {
    $reason = "launch_failed"
  }
} elseif ($buildOk) {
  $reason = "exe_missing"
}

$combined = ""
if (Test-Path $runOut) { $combined += (Get-Content -Raw -LiteralPath $runOut -ErrorAction SilentlyContinue) + "`n" }
if (Test-Path $runErr) { $combined += (Get-Content -Raw -LiteralPath $runErr -ErrorAction SilentlyContinue) + "`n" }

$crashPattern = [regex]::IsMatch($combined, 'Crash=EXCEPTION|widget_sandbox_exception|access violation|fatal|unhandled', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$noCrash = (-not $crashPattern)

if ([string]::IsNullOrWhiteSpace($reason)) {
  if (-not $buildOk) { $reason = "build_failed" }
  elseif (-not $launchOk) { $reason = "launch_failed" }
  elseif ($exitCode -ne 0) { $reason = "exit_code=$exitCode" }
  elseif (-not $noCrash) { $reason = "crash_detected" }
  else { $reason = "" }
}

$gate = if ($buildOk -and $launchOk -and $noCrash -and $exitCode -eq 0) { "PASS" } else { "FAIL" }

$gatePath = Join-Path $pf "98_gate_17.txt"
@(
  "PHASE=17",
  "TS=$(Get-Date -Format o)",
  "build_ok=$buildOk",
  "launch_ok=$launchOk",
  "no_crash=$noCrash",
  "exit_code=$exitCode",
  "GATE=$gate",
  "reason=$reason"
) | Set-Content -Path $gatePath -Encoding utf8

if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf "*") -DestinationPath $zip -Force

$repo = $root
$proofRoot = Join-Path $repo "_proof"
$gateFile = Get-ChildItem -LiteralPath $proofRoot -Recurse -Force -File |
  Where-Object { $_.Name -eq "98_gate_17.txt" } |
  Sort-Object LastWriteTimeUtc -Descending |
  Select-Object -First 1

if (-not $gateFile) { throw "missing_gate_file" }

$pf = Split-Path $gateFile.FullName -Parent
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

if ($gate -ne "PASS") {
  Get-Content -LiteralPath $gatePath
  exit 2
}

exit 0
