param(
  [string]$Policies = "0,1,2",
  [int]$FailEvery = 10,
  [int]$CyclesPerPolicy = 20,
  [int]$AutoCloseMs = 1500,
  [int]$TimeoutSec = 30
)

$ErrorActionPreference = 'Stop'

Set-Location "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime"
if ((Get-Location).Path -ne "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime") {
  "hey stupid Fucker, wrong window again"
  exit 1
}

$root = (Get-Location).Path
$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File ".\tools\runtime_runner_core.ps1" -phase 16_20 -tag "present_fail_matrix"
$pf = $paths[0].Trim()
$zip = $paths[1].Trim()
$proofRoot = "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime\_proof"
$expectedProof = $proofRoot

New-Item -ItemType Directory -Path $pf -Force | Out-Null

@(
  "PHASE=16.20",
  "TS=$(Get-Date -Format o)",
  "PWD=$root",
  "Policies=$Policies",
  "FailEvery=$FailEvery",
  "CyclesPerPolicy=$CyclesPerPolicy",
  "AutoCloseMs=$AutoCloseMs",
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

function Parse-Policies([string]$text) {
  return @($text.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' } | ForEach-Object { [int]$_ })
}

function Count-Marker([string]$text, [string]$pattern) {
  if ([string]::IsNullOrEmpty($text)) { return 0 }
  return ([regex]::Matches($text, $pattern)).Count
}

function Has-Marker([string]$text, [string]$pattern) {
  if ([string]::IsNullOrEmpty($text)) { return $false }
  return [regex]::IsMatch($text, $pattern)
}

function Last-LineNo([string]$text, [string]$pattern) {
  if ([string]::IsNullOrEmpty($text)) { return -1 }
  $all = [regex]::Matches($text, $pattern)
  if ($all.Count -eq 0) { return -1 }
  $idx = $all[$all.Count - 1].Index
  return ([regex]::Matches($text.Substring(0, $idx), "`r?`n")).Count + 1
}

function First-LineNo([string]$text, [string]$pattern) {
  if ([string]::IsNullOrEmpty($text)) { return -1 }
  $m = [regex]::Match($text, $pattern)
  if (-not $m.Success) { return -1 }
  return ([regex]::Matches($text.Substring(0, $m.Index), "`r?`n")).Count + 1
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
    return [pscustomobject]@{ exitcode = 998; timedout = $true; stdout = $stdoutText; stderr = $stderrText }
  }

  return [pscustomobject]@{ exitcode = [int]$managed.proc.ExitCode; timedout = $false; stdout = $stdoutText; stderr = $stderrText }
}

$policyList = Parse-Policies $Policies
$rows = @()
$firstFail = $null
$policy0QuitGapMax = 120

foreach ($policy in $policyList) {
  for ($cycle = 1; $cycle -le $CyclesPerPolicy; $cycle++) {
    $cycleTag = "{0:D2}" -f $cycle
    $stdoutPath = Join-Path $pf ("stdout_policy_{0}_cycle_{1}.txt" -f $policy, $cycleTag)
    $stderrPath = Join-Path $pf ("stderr_policy_{0}_cycle_{1}.txt" -f $policy, $cycleTag)
    $runLog = Join-Path $pf ("run_policy_{0}_cycle_{1}.txt" -f $policy, $cycleTag)
    $runTmp = Join-Path $pf ("tmp_policy_{0}_cycle_{1}" -f $policy, $cycleTag)
    New-Item -ItemType Directory -Path $runTmp -Force | Out-Null

    $policyAutoCloseMs = if ($policy -eq 0) { 600000 } else { $AutoCloseMs }
    $policyFailEvery = if ($policy -eq 0) { 1 } else { $FailEvery }

    $envVars = @{
      NGK_AUTOCLOSE_MS = [string]$policyAutoCloseMs
      NGK_PRESENT_FAIL_EVERY = [string]$policyFailEvery
      NGK_PRESENT_FAIL_POLICY = [string]$policy
      NGK_PRESENT_FAIL_MAX_CONSEC = "3"
      TEMP = $runTmp
      TMP = $runTmp
    }

    $managed = Start-ManagedProcess -exePath $exe -workingDir $root -stdoutPath $stdoutPath -stderrPath $stderrPath -envVars $envVars -timeoutMs ([int]($TimeoutSec * 1000))
    $done = Complete-ManagedProcess -managed $managed

    $stdoutText = if ($null -eq $done.stdout) { "" } else { [string]$done.stdout }
    $stderrText = if ($null -eq $done.stderr) { "" } else { [string]$done.stderr }

    $windowCount = Count-Marker $stdoutText "window_created=1"
    $loopExitCount = Count-Marker $stdoutText "NGK_CORE_LOOP_EXIT"
    $shutdownOk = Has-Marker $stdoutText "shutdown_ok=1"
    $vehRemoved = Has-Marker $stdoutText "crash_capture_veh_removed=1"
    $combinedText = $stdoutText + "`n" + $stderrText
    $presentFailSeen = Has-Marker $combinedText "INJECT_PRESENT_FAIL|present_failed_hr"

    $rejectLine = Last-LineNo $stdoutText "NGK_CORE_EVENT_REJECTED"
    $exitLine = Last-LineNo $stdoutText "NGK_CORE_LOOP_EXIT"
    $dispatchLine = Last-LineNo $stdoutText "NGK_CORE_EVENT_DISPATCHED"
    $taskLine = Last-LineNo $stdoutText "NGK_CORE_TASK_RAN"
    $quitLine = First-LineNo $combinedText "quit_requested=1"
    $firstPresentFailLine = First-LineNo $combinedText "INJECT_PRESENT_FAIL|present_failed_hr"
    $autocloseFired = Has-Marker $combinedText "autoclose_fired=1"

    $reasons = @()
    if ($done.timedout) { $reasons += "timeout" }

    if ($policy -eq 0) {
      if (-not $presentFailSeen) { $reasons += "present_fail_missing" }
      if ($autocloseFired) { $reasons += "autoclose_fired_present" }
      if ($quitLine -lt 0) { $reasons += "quit_requested_missing" }
      if ($loopExitCount -lt 1) { $reasons += "loop_exit_missing" }
      if (-not $shutdownOk) { $reasons += "shutdown_ok_missing" }
      if (-not $vehRemoved) { $reasons += "veh_removed_missing" }
      if ($quitLine -ge 0 -and $firstPresentFailLine -ge 0) {
        if ($quitLine -lt $firstPresentFailLine) {
          $reasons += "quit_before_present_fail"
        }
        elseif (($quitLine - $firstPresentFailLine) -gt $policy0QuitGapMax) {
          $reasons += "quit_not_soon_after_present_fail"
        }
      }
      elseif ($presentFailSeen -and $quitLine -ge 0 -and $firstPresentFailLine -lt 0) {
        $reasons += "present_fail_line_missing"
      }
      if ($dispatchLine -ge 0 -and $exitLine -ge 0 -and $dispatchLine -gt $exitLine) { $reasons += "dispatch_after_exit" }
      if ($taskLine -ge 0 -and $exitLine -ge 0 -and $taskLine -gt $exitLine) { $reasons += "task_after_exit" }
    }
    elseif (($policy -eq 1) -or ($policy -eq 2)) {
      if ($done.exitcode -ne 0) { $reasons += "exit!=0" }
      if ($windowCount -ne 1) { $reasons += "window_created_count=$windowCount" }
      if ($loopExitCount -ne 1) { $reasons += "loop_exit_count=$loopExitCount" }
      if (-not $shutdownOk) { $reasons += "shutdown_ok_missing" }
      if ($dispatchLine -ge 0 -and $exitLine -ge 0 -and $dispatchLine -gt $exitLine) { $reasons += "dispatch_after_exit" }
      if ($taskLine -ge 0 -and $exitLine -ge 0 -and $taskLine -gt $exitLine) { $reasons += "task_after_exit" }
      if ($rejectLine -ge 0 -and $exitLine -ge 0 -and $rejectLine -lt $exitLine) { $reasons += "reject_before_exit" }
    }
    else {
      $reasons += "unsupported_policy=$policy"
    }

    @(
      "=== RUN policy=$policy cycle=$cycleTag TS=$(Get-Date -Format o) ===",
      "PID=$($managed.pid)",
      "EXITCODE=$($done.exitcode)",
      "=== STDOUT ===",
      $stdoutText,
      "=== STDERR ===",
      $stderrText
    ) | Out-File -FilePath $runLog -Encoding utf8

    $row = [pscustomobject]@{
      policy = $policy
      cycle = $cycle
      exitcode = $done.exitcode
      window_created_count = $windowCount
      loop_exit_count = $loopExitCount
      shutdown_ok = [int]$shutdownOk
      present_fail_seen = [int]$presentFailSeen
      reject_line = $rejectLine
      exit_line = $exitLine
      dispatch_line = $dispatchLine
      task_line = $taskLine
      reasons = ($reasons -join ',')
      log = $runLog
    }

    $rows += $row

    if (($reasons.Count -gt 0) -and (-not $firstFail)) {
      $firstFail = $row
    }
  }
}

$rows |
  Select-Object policy,cycle,exitcode,window_created_count,loop_exit_count,shutdown_ok,present_fail_seen,reject_line,exit_line,dispatch_line,task_line,reasons,log |
  Export-Csv -Path (Join-Path $pf "90_matrix.csv") -NoTypeInformation -Encoding utf8

$totalPlanned = $policyList.Count * $CyclesPerPolicy
$totalExecuted = $rows.Count
$overall = if ($firstFail) { "FAIL" } else { "PASS" }

@(
  "PHASE=16.20",
  "TS=$(Get-Date -Format o)",
  "Policies=$Policies",
  "FailEvery=$FailEvery",
  "CyclesPerPolicy=$CyclesPerPolicy",
  "AutoCloseMs=$AutoCloseMs",
  "TimeoutSec=$TimeoutSec",
  "TotalPlanned=$totalPlanned",
  "TotalExecuted=$totalExecuted",
  "GATE=$overall",
  "failed_policy=" + ($(if($firstFail){$firstFail.policy}else{"none"})),
  "failed_cycle=" + ($(if($firstFail){$firstFail.cycle}else{"none"})),
  "reason=" + ($(if($firstFail){$firstFail.reasons}else{""})),
  "failed_log=" + ($(if($firstFail){$firstFail.log}else{""}))
) | Out-File (Join-Path $pf "98_gate_16_20.txt") -Encoding utf8

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
  Where-Object { $_.Name -eq "98_gate_16_20.txt" } |
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
  $gatePath = Join-Path $pf "98_gate_16_20.txt"
  Get-Content -LiteralPath $gatePath
  if ($firstFail -and (Test-Path $firstFail.log)) {
    Get-Content -LiteralPath $firstFail.log -Tail 120
  }
  exit 2
}

exit 0
