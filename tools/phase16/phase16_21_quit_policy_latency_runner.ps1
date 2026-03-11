param(
  [int]$Cycles = 20,
  [int]$AutoCloseMs = 600000,
  [int]$TimeoutSec = 30,
  [int]$FailEvery = 1,
  [int]$MaxConsec = 3,
  [int]$MaxLinesToQuit = 300,
  [int]$MaxLinesToExit = 1200
)

$ErrorActionPreference = 'Stop'

Set-Location "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime"
if ((Get-Location).Path -ne "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime") {
  "hey stupid Fucker, wrong window again"
  exit 1
}

$root = (Get-Location).Path
$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File ".\tools\runtime_runner_core.ps1" -phase 16_21 -tag "quit_policy_latency"
$pf = $paths[0].Trim()
$zip = $paths[1].Trim()
$proofRoot = "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime\_proof"
$expectedProof = $proofRoot

@(
  "PHASE=16.21",
  "TS=$(Get-Date -Format o)",
  "PWD=$root",
  "Cycles=$Cycles",
  "AutoCloseMs=$AutoCloseMs",
  "TimeoutSec=$TimeoutSec",
  "FailEvery=$FailEvery",
  "MaxConsec=$MaxConsec",
  "MaxLinesToQuit=$MaxLinesToQuit",
  "MaxLinesToExit=$MaxLinesToExit"
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

  foreach ($k in @($psi.Environment.Keys)) {
    if ([string]$k -like "NGK_*") {
      $psi.Environment.Remove([string]$k)
    }
  }

  foreach ($k in $envVars.Keys) {
    $psi.Environment[$k] = [string]$envVars[$k]
  }

  $proc = [System.Diagnostics.Process]::new()
  $proc.StartInfo = $psi
  if (-not $proc.Start()) { throw "Failed to start process: $exePath" }

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

  $stdoutText = ""
  $stderrText = ""
  try { if ($null -ne $managed.outTask.Result) { $stdoutText = [string]$managed.outTask.Result } } catch {}
  try { if ($null -ne $managed.errTask.Result) { $stderrText = [string]$managed.errTask.Result } } catch {}

  [System.IO.File]::WriteAllText($managed.stdout_path, $stdoutText, [System.Text.UTF8Encoding]::new($false))
  [System.IO.File]::WriteAllText($managed.stderr_path, $stderrText, [System.Text.UTF8Encoding]::new($false))

  if (-not $ok) {
    return [pscustomobject]@{ exitcode = 998; timedout = $true; stdout = $stdoutText; stderr = $stderrText }
  }

  return [pscustomobject]@{ exitcode = [int]$managed.proc.ExitCode; timedout = $false; stdout = $stdoutText; stderr = $stderrText }
}

function First-LineNo([string]$text, [string]$pattern) {
  if ([string]::IsNullOrEmpty($text)) { return -1 }
  $m = [regex]::Match($text, $pattern)
  if (-not $m.Success) { return -1 }
  return ([regex]::Matches($text.Substring(0, $m.Index), "`r?`n")).Count + 1
}

function Last-LineNo([string]$text, [string]$pattern) {
  if ([string]::IsNullOrEmpty($text)) { return -1 }
  $all = [regex]::Matches($text, $pattern)
  if ($all.Count -eq 0) { return -1 }
  $idx = $all[$all.Count - 1].Index
  return ([regex]::Matches($text.Substring(0, $idx), "`r?`n")).Count + 1
}

$rows = @()
$firstFail = $null

for ($cycle = 1; $cycle -le $Cycles; $cycle++) {
  $tag = "{0:D2}" -f $cycle
  $stdoutPath = Join-Path $pf ("stdout_cycle_{0}.txt" -f $tag)
  $stderrPath = Join-Path $pf ("stderr_cycle_{0}.txt" -f $tag)
  $runLog = Join-Path $pf ("run_cycle_{0}.txt" -f $tag)
  $runTmp = Join-Path $pf ("tmp_cycle_{0}" -f $tag)
  New-Item -ItemType Directory -Path $runTmp -Force | Out-Null

  Clear-NGKEnv

  $envVars = @{
    NGK_PRESENT_FAIL_POLICY = "0"
    NGK_PRESENT_FAIL_EVERY = [string]$FailEvery
    NGK_PRESENT_FAIL_MAX_CONSEC = [string]$MaxConsec
    NGK_AUTOCLOSE_MS = [string]$AutoCloseMs
    TEMP = $runTmp
    TMP = $runTmp
  }

  $managed = Start-ManagedProcess -exePath $exe -workingDir $root -stdoutPath $stdoutPath -stderrPath $stderrPath -envVars $envVars -timeoutMs ([int]($TimeoutSec * 1000))
  $done = Complete-ManagedProcess -managed $managed

  $stdoutText = if ($null -eq $done.stdout) { "" } else { [string]$done.stdout }
  $stderrText = if ($null -eq $done.stderr) { "" } else { [string]$done.stderr }
  $combined = $stdoutText + "`n" + $stderrText

  $triggerLine = First-LineNo $combined "PRESENT_FAIL_POLICY_QUIT_TRIGGERED=1"
  $quitLine = First-LineNo $combined "quit_requested=1"
  $exitLine = First-LineNo $combined "NGK_CORE_LOOP_EXIT"
  $shutdownLine = First-LineNo $combined "shutdown_ok=1"
  $rejectLine = Last-LineNo $combined "NGK_CORE_EVENT_REJECTED"
  $dispatchLine = Last-LineNo $combined "NGK_CORE_EVENT_DISPATCHED"
  $taskLine = Last-LineNo $combined "NGK_CORE_TASK_RAN"

  $reasons = @()
  if ($done.timedout) { $reasons += "timeout" }
  if ($triggerLine -lt 0) { $reasons += "trigger_missing" }
  if ($quitLine -lt 0) { $reasons += "quit_missing" }
  if ($exitLine -lt 0) { $reasons += "loop_exit_missing" }
  if ($shutdownLine -lt 0) { $reasons += "shutdown_ok_missing" }

  if ($triggerLine -ge 0 -and $quitLine -ge 0) {
    $quitGap = $quitLine - $triggerLine
    if ($quitGap -lt 0) { $reasons += "quit_before_trigger" }
    elseif ($quitGap -gt $MaxLinesToQuit) { $reasons += "quit_gap_too_large=$quitGap" }
  }

  if ($triggerLine -ge 0 -and $exitLine -ge 0) {
    $exitGap = $exitLine - $triggerLine
    if ($exitGap -lt 0) { $reasons += "exit_before_trigger" }
    elseif ($exitGap -gt $MaxLinesToExit) { $reasons += "exit_gap_too_large=$exitGap" }
  }

  if ($rejectLine -ge 0 -and $exitLine -ge 0 -and $rejectLine -lt $exitLine) { $reasons += "reject_before_exit" }
  if ($dispatchLine -ge 0 -and $exitLine -ge 0 -and $dispatchLine -gt $exitLine) { $reasons += "dispatch_after_exit" }
  if ($taskLine -ge 0 -and $exitLine -ge 0 -and $taskLine -gt $exitLine) { $reasons += "task_after_exit" }

  $stderrBad = [regex]::IsMatch($stderrText, "assert|exception|access violation|unhandled|fatal|terminate", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  if ($stderrBad) { $reasons += "stderr_bad_pattern" }

  @(
    "=== RUN cycle=$tag TS=$(Get-Date -Format o) ===",
    "PID=$($managed.pid)",
    "EXITCODE=$($done.exitcode)",
    "=== STDOUT ===",
    $stdoutText,
    "=== STDERR ===",
    $stderrText
  ) | Out-File -FilePath $runLog -Encoding utf8

  $row = [pscustomobject]@{
    cycle = $cycle
    exitcode = $done.exitcode
    trigger_line = $triggerLine
    quit_line = $quitLine
    exit_line = $exitLine
    shutdown_ok_line = $shutdownLine
    reasons = ($reasons -join ',')
    log = $runLog
  }

  $rows += $row
  if (($reasons.Count -gt 0) -and (-not $firstFail)) {
    $firstFail = $row
  }
}

$rows | Select-Object cycle,exitcode,trigger_line,quit_line,exit_line,shutdown_ok_line,reasons,log |
  Export-Csv -Path (Join-Path $pf "90_cycles.csv") -NoTypeInformation -Encoding utf8

$overall = if ($firstFail) { "FAIL" } else { "PASS" }
@(
  "PHASE=16.21",
  "TS=$(Get-Date -Format o)",
  "Cycles=$Cycles",
  "AutoCloseMs=$AutoCloseMs",
  "TimeoutSec=$TimeoutSec",
  "FailEvery=$FailEvery",
  "MaxConsec=$MaxConsec",
  "MaxLinesToQuit=$MaxLinesToQuit",
  "MaxLinesToExit=$MaxLinesToExit",
  "TotalPlanned=$Cycles",
  "TotalExecuted=$($rows.Count)",
  "GATE=$overall",
  "failed_cycle=" + ($(if($firstFail){$firstFail.cycle}else{"none"})),
  "reason=" + ($(if($firstFail){$firstFail.reasons}else{""})),
  "failed_log=" + ($(if($firstFail){$firstFail.log}else{""}))
) | Out-File (Join-Path $pf "98_gate_16_21.txt") -Encoding utf8

if (Test-Path $zip) { Remove-Item -Force $zip }

$stage = $pf + "__stage_zip"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Path $stage -Force | Out-Null

$copied = $false
for ($attempt = 1; $attempt -le 12; $attempt++) {
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
for ($attempt = 1; $attempt -le 12; $attempt++) {
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

if (-not (Test-Path $zip)) { throw "Zip missing after creation: $zip" }

$repo = $root
$proofRoot = Join-Path $repo "_proof"
$gateFileScan = Get-ChildItem -LiteralPath $proofRoot -Recurse -Force -File |
  Where-Object { $_.Name -eq "98_gate_16_21.txt" } |
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
  $gatePath = Join-Path $pf "98_gate_16_21.txt"
  Get-Content -LiteralPath $gatePath
  if ($firstFail -and (Test-Path $firstFail.log)) {
    Get-Content -LiteralPath $firstFail.log -Tail 160
  }
  exit 2
}

exit 0
