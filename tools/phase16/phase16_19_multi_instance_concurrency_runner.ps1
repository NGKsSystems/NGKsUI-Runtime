param(
  [int]$Instances = 32,
  [int]$AutoCloseMs = 2000,
  [int]$StartStaggerMs = 50,
  [int]$TimeoutSec = 30
)

$ErrorActionPreference = 'Stop'

Set-Location "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime"
if ((Get-Location).Path -ne "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime") {
  "hey stupid Fucker, wrong window again"
  exit 1
}

$root = (Get-Location).Path
$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File ".\tools\runtime_runner_core.ps1" -phase 16_19 -tag "multi_instance_concurrency"
$pf = $paths[0].Trim()
$zip = $paths[1].Trim()
$proofRoot = "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime\_proof"
$expectedProof = $proofRoot
$logsDir = Join-Path $pf "logs"
$tmpRoot = Join-Path $pf "tmp"

New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null

@(
  "PHASE=16.19",
  "TS=$(Get-Date -Format o)",
  "PWD=$root",
  "Instances=$Instances",
  "AutoCloseMs=$AutoCloseMs",
  "StartStaggerMs=$StartStaggerMs",
  "TimeoutSec=$TimeoutSec"
) | Out-File (Join-Path $pf "00_env.txt") -Encoding utf8

git rev-parse --show-toplevel *> (Join-Path $pf "01_repo_root.txt")
git rev-parse --short HEAD *> (Join-Path $pf "02_head.txt")
git status *> (Join-Path $pf "03_status.txt")

$envLog = Join-Path $pf "10_enter_msvc_env.txt"
"=== ENTER MSVC ENV ===`nTS=$(Get-Date -Format o)" | Set-Content $envLog -Encoding utf8
.\tools\enter_msvc_env.ps1 *>> $envLog

Get-ChildItem -Path $proofRoot -Filter "__ngk_vs*" -File -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 6 |
  Copy-Item -Destination $pf -Force

cmake --preset win-msvc-release *> (Join-Path $pf "20_config.txt")
cmake --build --preset win-msvc-release -v *> (Join-Path $pf "21_build.txt")

$exe = ".\artifacts\build\win-msvc-release\bin\win32_sandbox.exe"
if (-not (Test-Path $exe)) { throw "EXE missing after build: $exe" }
"EXE=$exe" | Out-File (Join-Path $pf "22_exe.txt") -Encoding utf8

function Clear-NGKEnv {
  Get-ChildItem Env: |
    Where-Object { $_.Name -like "NGK_*" } |
    ForEach-Object { Remove-Item -Path ("Env:\" + $_.Name) -ErrorAction SilentlyContinue }
}

function Count-Marker([string]$text, [string]$pattern) {
  if ([string]::IsNullOrEmpty($text)) { return 0 }
  return ([regex]::Matches($text, $pattern)).Count
}

function Contains-Marker([string]$text, [string]$pattern) {
  if ([string]::IsNullOrEmpty($text)) { return $false }
  return [regex]::IsMatch($text, $pattern)
}

function Last-LineNo([string]$path, [string]$pattern) {
  if (-not (Test-Path $path)) { return -1 }
  $m = Select-String -Path $path -Pattern $pattern -ErrorAction SilentlyContinue | Select-Object -Last 1
  if (-not $m) { return -1 }
  return [int]$m.LineNumber
}

function Start-ManagedProcess(
  [string]$exePath,
  [string]$workingDir,
  [string]$stdoutPath,
  [string]$stderrPath,
  [hashtable]$envVars,
  [int]$timeoutMs
) {
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $exePath
  $psi.WorkingDirectory = $workingDir
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $true

  foreach ($k in $envVars.Keys) {
    $psi.Environment[$k] = [string]$envVars[$k]
  }

  $proc = [System.Diagnostics.Process]::new()
  $proc.StartInfo = $psi

  $started = $proc.Start()
  if (-not $started) {
    throw "Failed to start process: $exePath"
  }

  $outTask = $proc.StandardOutput.ReadToEndAsync()
  $errTask = $proc.StandardError.ReadToEndAsync()

  return [pscustomobject]@{
    proc = $proc
    pid = $proc.Id
    timeoutMs = $timeoutMs
    stdout_path = $stdoutPath
    stderr_path = $stderrPath
    outTask = $outTask
    errTask = $errTask
  }
}

function Complete-ManagedProcess([object]$managed) {
  $ok = $managed.proc.WaitForExit($managed.timeoutMs)
  if (-not $ok) {
    try { $managed.proc.Kill() } catch {}
  }

  try { $managed.outTask.Wait(5000) } catch {}
  try { $managed.errTask.Wait(5000) } catch {}

  try { $managed.proc.WaitForExit() } catch {}
  $managed.proc.Refresh()

  $stdoutText = ""
  $stderrText = ""
  try { if ($null -ne $managed.outTask.Result) { $stdoutText = [string]$managed.outTask.Result } } catch {}
  try { if ($null -ne $managed.errTask.Result) { $stderrText = [string]$managed.errTask.Result } } catch {}

  [System.IO.File]::WriteAllText($managed.stdout_path, $stdoutText, [System.Text.UTF8Encoding]::new($false))
  [System.IO.File]::WriteAllText($managed.stderr_path, $stderrText, [System.Text.UTF8Encoding]::new($false))

  if (-not $ok) {
    return [pscustomobject]@{ exitcode = 998; timedout = $true }
  }

  return [pscustomobject]@{ exitcode = [int]$managed.proc.ExitCode; timedout = $false }
}

$procs = @()

for ($i = 1; $i -le $Instances; $i++) {
  $instTag = ("inst_{0:D2}" -f $i)
  $instTmp = Join-Path $tmpRoot $instTag
  $stdoutPath = Join-Path $logsDir ("{0}_stdout.txt" -f $instTag)
  $stderrPath = Join-Path $logsDir ("{0}_stderr.txt" -f $instTag)

  New-Item -ItemType Directory -Path $instTmp -Force | Out-Null

  Clear-NGKEnv
  $envVars = @{
    NGK_AUTOCLOSE_MS = [string]$AutoCloseMs
    TEMP = $instTmp
    TMP = $instTmp
  }

  $managed = Start-ManagedProcess -exePath $exe -workingDir $root -stdoutPath $stdoutPath -stderrPath $stderrPath -envVars $envVars -timeoutMs ([int]($TimeoutSec * 1000))

  $procs += [pscustomobject]@{
    inst = $i
    instTag = $instTag
    proc = $managed.proc
    managed = $managed
    pid = $managed.pid
    exitcode = 999
    stdout_path = $stdoutPath
    stderr_path = $stderrPath
    timedout = $false
  }

  if ($i -lt $Instances -and $StartStaggerMs -gt 0) {
    Start-Sleep -Milliseconds $StartStaggerMs
  }
}

foreach ($r in $procs) {
  $done = Complete-ManagedProcess -managed $r.managed
  $r.timedout = $done.timedout
  $r.exitcode = $done.exitcode
}

$rows = @()
$firstFail = $null

foreach ($r in $procs) {
  $stdoutText = if (Test-Path $r.stdout_path) { Get-Content -Raw -LiteralPath $r.stdout_path -ErrorAction SilentlyContinue } else { "" }
  $stderrText = if (Test-Path $r.stderr_path) { Get-Content -Raw -LiteralPath $r.stderr_path -ErrorAction SilentlyContinue } else { "" }
  if ($null -eq $stdoutText) { $stdoutText = "" }
  if ($null -eq $stderrText) { $stderrText = "" }

  $windowCount = Count-Marker $stdoutText "window_created=1"
  $shutdownOk = Contains-Marker $stdoutText "shutdown_ok=1"
  $autocloseFired = Contains-Marker $stdoutText "autoclose_fired=1"
  $closeRequested = Contains-Marker $stdoutText "close_requested=1"
  $quitRequested = Contains-Marker $stdoutText "quit_requested=1"

  $loopExitLine = Last-LineNo $r.stdout_path "NGK_CORE_LOOP_EXIT"
  $rejectLine = Last-LineNo $r.stdout_path "NGK_CORE_EVENT_REJECTED"

  $stderrBad = [regex]::IsMatch($stderrText, "assert|exception|access violation|stack trace|fatal|terminate|unhandled", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

  $reasons = @()
  $hardFailReasons = @()

  if ($r.timedout) { $hardFailReasons += "timeout" }
  if ($r.exitcode -eq 999) { $hardFailReasons += "exitcode_unknown" }
  elseif ($r.exitcode -ne 0) { $hardFailReasons += "exit!=0" }
  if ($windowCount -ne 1) { $hardFailReasons += "window_created_count=$windowCount" }
  if (-not $shutdownOk) { $hardFailReasons += "shutdown_ok_missing" }
  if (-not $autocloseFired) { $hardFailReasons += "autoclose_fired_missing" }
  if (-not $quitRequested) { $hardFailReasons += "quit_requested_missing" }
  if (-not $closeRequested) { $hardFailReasons += "close_requested_missing" }
  if ($stderrBad) { $hardFailReasons += "stderr_bad_pattern" }

  if ($rejectLine -ge 0) {
    if ($loopExitLine -ge 0) {
      if ($rejectLine -lt $loopExitLine) {
        $hardFailReasons += "reject_before_loop_exit"
      }
    }
    else {
      $reasons += "marker_missing:NGK_CORE_LOOP_EXIT"
    }
  }

  $reasons += $hardFailReasons
  $pass = ($hardFailReasons.Count -eq 0)

  $row = [pscustomobject]@{
    inst = $r.inst
    pid = $r.pid
    exitcode = $r.exitcode
    window_created_count = $windowCount
    shutdown_ok = [int]$shutdownOk
    autoclose_fired = [int]$autocloseFired
    close_requested = [int]$closeRequested
    quit_requested = [int]$quitRequested
    stderr_bad = [int]$stderrBad
    reasons = ($reasons -join ",")
    stdout_path = $r.stdout_path
    stderr_path = $r.stderr_path
  }

  $rows += $row

  if ((-not $pass) -and (-not $firstFail)) {
    $firstFail = $row
  }
}

$rows |
  Select-Object inst, pid, exitcode, window_created_count, shutdown_ok, autoclose_fired, close_requested, quit_requested, stderr_bad, reasons, stdout_path, stderr_path |
  Export-Csv -Path (Join-Path $pf "90_instances.csv") -NoTypeInformation -Encoding utf8

$anyTimeout = @($procs | Where-Object { $_.timedout }).Count -gt 0
$overall = if ((-not $firstFail) -and (-not $anyTimeout)) { "PASS" } else { "FAIL" }

$failedInst = if ($firstFail) { [string]$firstFail.inst } else { "none" }
$failedReason = if ($firstFail) { $firstFail.reasons } elseif ($anyTimeout) { "timeout" } else { "" }

@(
  "PHASE=16.19",
  "TS=$(Get-Date -Format o)",
  "Instances=$Instances",
  "AutoCloseMs=$AutoCloseMs",
  "StartStaggerMs=$StartStaggerMs",
  "TimeoutSec=$TimeoutSec",
  "TotalPlanned=$Instances",
  "TotalExecuted=$($rows.Count)",
  "GATE=$overall",
  "failed_inst=$failedInst",
  "reason=$failedReason"
) | Out-File (Join-Path $pf "98_gate_16_19.txt") -Encoding utf8

if (Test-Path $zip) { Remove-Item -Force $zip }

$stage = $pf + "__stage_zip"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Path $stage -Force | Out-Null

$copied = $false
for ($attempt = 1; $attempt -le 10; $attempt++) {
  try {
    Copy-Item -Path (Join-Path $pf "*") -Destination $stage -Recurse -Force
    $copied = $true
    break
  }
  catch {
    Start-Sleep -Milliseconds (150 * $attempt)
  }
}
if (-not $copied) { throw "Failed to stage PF files for zip after retries." }

$zipped = $false
for ($attempt = 1; $attempt -le 10; $attempt++) {
  try {
    Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip -Force
    $zipped = $true
    break
  }
  catch {
    Start-Sleep -Milliseconds (200 * $attempt)
  }
}
if (-not $zipped) { throw "Failed to create zip after retries." }

Remove-Item -Recurse -Force $stage

$repo = $root
$proofRoot = Join-Path $repo "_proof"
$gateFileScan = Get-ChildItem -LiteralPath $proofRoot -Recurse -Force -File |
  Where-Object { $_.Name -eq "98_gate_16_19.txt" } |
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
Write-Output "GATE=$overall"

if ($overall -ne "PASS") {
  $gatePath = Join-Path $pf "98_gate_16_19.txt"
  Get-Content -LiteralPath $gatePath

  if ($firstFail) {
    if (Test-Path $firstFail.stderr_path) {
      "--- STDERR tail (80) inst=$($firstFail.inst) ---"
      Get-Content -LiteralPath $firstFail.stderr_path -Tail 80
    }
    if (Test-Path $firstFail.stdout_path) {
      "--- STDOUT tail (80) inst=$($firstFail.inst) ---"
      Get-Content -LiteralPath $firstFail.stdout_path -Tail 80
    }
  }

  exit 2
}

exit 0
