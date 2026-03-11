# _proof\phase16_18_dual_instance_runner.ps1
# Phase 16.18 — Dual Instance Isolation Contract Runner
# Option 4: visible execution + proof artifacts only.

param(
  [int]$Cycles = 25,
  [int]$AutoCloseMs = 1500
)

$ErrorActionPreference = 'Stop'

# =========================
# HARD WINDOW GUARD
# =========================
Set-Location "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime"
if ((Get-Location).Path -ne "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime") {
  "hey stupid Fucker, wrong window again"
  exit 1
}

# =========================
# PROOF FOLDER
# =========================
$root = (Get-Location).Path
$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File ".\tools\runtime_runner_core.ps1" -phase 16_18 -tag "dual_instance"
$pf = $paths[0].Trim()
$zip = $paths[1].Trim()
$proofRoot = "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime\_proof"
$expectedProof = $proofRoot

"PHASE=16.18`nTS=$(Get-Date -Format o)`nPWD=$((Get-Location).Path)`nCycles=$Cycles`nAutoCloseMs=$AutoCloseMs" |
  Out-File (Join-Path $pf "00_env.txt") -Encoding utf8

git rev-parse --show-toplevel *> (Join-Path $pf "01_repo_root.txt")
git rev-parse --short HEAD *> (Join-Path $pf "02_head.txt")
git status *> (Join-Path $pf "03_status.txt")

# =========================
# ENTER MSVC ENV + BUILD ONCE
# =========================
$envLog = Join-Path $pf "10_enter_msvc_env.txt"
"=== ENTER MSVC ENV ===`nTS=$(Get-Date -Format o)" | Set-Content $envLog -Encoding utf8
.\tools\enter_msvc_env.ps1 *>> $envLog

cmake --preset win-msvc-release *> (Join-Path $pf "20_config.txt")
cmake --build --preset win-msvc-release -v *> (Join-Path $pf "21_build.txt")

$exe = ".\artifacts\build\win-msvc-release\bin\win32_sandbox.exe"
if (-not (Test-Path $exe)) { throw "EXE missing after build: $exe" }
"EXE=$exe" | Out-File (Join-Path $pf "22_exe.txt") -Encoding utf8

$exeInfo = Get-Item $exe
$exeLength0 = $exeInfo.Length
$exeWrite0 = $exeInfo.LastWriteTimeUtc

# =========================
# HELPERS
# =========================
function Clear-NGKEnv {
  Get-ChildItem Env: |
    Where-Object { $_.Name -like "NGK_*" } |
    ForEach-Object { Remove-Item -Path ("Env:\" + $_.Name) -ErrorAction SilentlyContinue }
}

function Count-Marker([string]$path,[string]$pattern) {
  if (-not (Test-Path $path)) { return 0 }
  return @((Select-String -Path $path -Pattern $pattern -ErrorAction SilentlyContinue)).Count
}

function Last-LineNo([string]$path,[string]$pattern) {
  if (-not (Test-Path $path)) { return -1 }
  $m = Select-String -Path $path -Pattern $pattern -ErrorAction SilentlyContinue | Select-Object -Last 1
  if (-not $m) { return -1 }
  return [int]$m.LineNumber
}

function Read-ContentSafe([string]$path) {
  if (-not (Test-Path $path)) { return @() }
  for ($attempt = 1; $attempt -le 12; $attempt++) {
    try {
      return @(Get-Content -LiteralPath $path -ErrorAction Stop)
    }
    catch {
      Start-Sleep -Milliseconds (50 * $attempt)
    }
  }
  return @()
}

function Append-LinesSafe([string]$path, [string[]]$lines) {
  for ($attempt = 1; $attempt -le 12; $attempt++) {
    try {
      $lines | Add-Content -LiteralPath $path -Encoding utf8 -ErrorAction Stop
      return
    }
    catch {
      Start-Sleep -Milliseconds (50 * $attempt)
    }
  }
  throw "Failed to append to $path after retries."
}

function Validate-Instance([int]$cycle, [string]$instance, [string]$log, [int]$exitCode, [int]$selfPid, [int]$peerPid) {
  $windowCreatedCount = Count-Marker $log "window_created=1"
  $loopExitCount = Count-Marker $log "NGK_CORE_LOOP_EXIT"

  $nExit = Last-LineNo $log "NGK_CORE_LOOP_EXIT"
  $nReject = Last-LineNo $log "NGK_CORE_EVENT_REJECTED"
  $nDispatch = Last-LineNo $log "NGK_CORE_EVENT_DISPATCHED"
  $nTask = Last-LineNo $log "NGK_CORE_TASK_RAN"

  $reasons = @()

  if ($exitCode -ne 0) { $reasons += "exit!=0" }
  if ($windowCreatedCount -ne 1) { $reasons += "window_created_count=$windowCreatedCount" }
  if ($loopExitCount -ne 1) { $reasons += "loop_exit_count=$loopExitCount" }
  if ($nReject -ge 0 -and $nExit -ge 0 -and $nReject -lt $nExit) { $reasons += "reject_before_exit" }
  if ($nDispatch -ge 0 -and $nExit -ge 0 -and $nDispatch -gt $nExit) { $reasons += "dispatch_after_exit" }
  if ($nTask -ge 0 -and $nExit -ge 0 -and $nTask -gt $nExit) { $reasons += "task_after_exit" }

  # Isolation: reject signs of cross-instance contamination / shared resource collisions
  $peerPidHits = @((Select-String -Path $log -Pattern ("\b" + [regex]::Escape([string]$peerPid) + "\b") -ErrorAction SilentlyContinue)).Count
  if ($peerPidHits -gt 0) { $reasons += "peer_pid_found_in_log=$peerPidHits" }

  $collisionHits = @((Select-String -Path $log -Pattern "sharing violation|already exists|file in use|ERROR_SHARING_VIOLATION|mutex" -ErrorAction SilentlyContinue)).Count
  if ($collisionHits -gt 0) { $reasons += "resource_collision_markers=$collisionHits" }

  $verdict = if ($reasons.Count -eq 0) { "PASS" } else { "FAIL" }

  return [pscustomobject]@{
    cycle=$cycle
    instance=$instance
    verdict=$verdict
    exitcode=$exitCode
    window_created_count=$windowCreatedCount
    loop_exit_count=$loopExitCount
    reject_line=$nReject
    exit_line=$nExit
    dispatch_line=$nDispatch
    task_line=$nTask
    reasons=($reasons -join ",")
    log=$log
  }
}

function Finalize-And-Exit([string]$gate, [object]$firstFail, [int]$executedRuns) {
  $gateFile = Join-Path $pf "98_gate_16_18.txt"
  $totalPlanned = $Cycles * 2

  @(
    "PHASE=16.18",
    "TS=$(Get-Date -Format o)",
    "Cycles=$Cycles",
    "AutoCloseMs=$AutoCloseMs",
    "TotalPlannedRuns=$totalPlanned",
    "TotalExecutedRuns=$executedRuns",
    "GATE=$gate",
    "failed_cycle=" + ($(if($firstFail){$firstFail.cycle}else{"none"})),
    "failed_run=" + ($(if($firstFail){$firstFail.instance}else{"none"})),
    "reason=" + ($(if($firstFail){$firstFail.reasons}else{""})),
    "failed_log=" + ($(if($firstFail){$firstFail.log}else{""}))
  ) | Out-File $gateFile -Encoding utf8

  Get-ChildItem -Path $proofRoot -Filter "__ngk_vs*" -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 6 |
    Copy-Item -Destination $pf -Force

  if (Test-Path $zip) { Remove-Item -Force $zip }

  $stage = ($pf + "__stage_zip")
  if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
  New-Item -ItemType Directory -Force $stage | Out-Null

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
  if (-not $copied) {
    throw "Failed to stage proof files for zipping after retries."
  }

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
  if (-not $zipped) {
    throw "Failed to create zip after retries."
  }
  Remove-Item -Recurse -Force $stage

  $repo = $root
  $proofRoot = Join-Path $repo "_proof"
  $gateFileScan = Get-ChildItem -LiteralPath $proofRoot -Recurse -Force -File |
    Where-Object { $_.Name -eq "98_gate_16_18.txt" } |
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

  if ($gate -ne "PASS") {
    Get-Content $gateFile
    if ($firstFail -and (Test-Path $firstFail.log)) {
      Get-Content $firstFail.log -Tail 200
    }
    exit 2
  }

  exit 0
}

# =========================
# RUN CYCLES (DUAL INSTANCE, FAIL-FAST)
# =========================
$results = @()
$firstFail = $null
$executed = 0

for ($i=1; $i -le $Cycles; $i++) {
  $tag = $i.ToString("00")

  Clear-NGKEnv
  Set-Item Env:\NGK_AUTOCLOSE_MS ([string]$AutoCloseMs)

  function Start-Instance([string]$inst) {
    $log = Join-Path $pf ("run_cycle_{0}_{1}.txt" -f $tag, $inst)
    $out = Join-Path $pf ("stdout_cycle_{0}_{1}.txt" -f $tag, $inst)
    $err = Join-Path $pf ("stderr_cycle_{0}_{1}.txt" -f $tag, $inst)

    $tmpRoot = Join-Path $pf ("tmp_cycle_{0}_{1}" -f $tag, $inst)
    New-Item -ItemType Directory -Force $tmpRoot | Out-Null

    "=== RUN cycle=$tag instance=$inst TS=$(Get-Date -Format o) ===" | Set-Content $log -Encoding utf8

    $psi = @{
      FilePath = $exe
      NoNewWindow = $true
      PassThru = $true
      RedirectStandardOutput = $out
      RedirectStandardError  = $err
    }

    $oldTEMP = $env:TEMP
    $oldTMP = $env:TMP
    $env:TEMP = $tmpRoot
    $env:TMP = $tmpRoot
    try {
      $p = Start-Process @psi
    }
    finally {
      $env:TEMP = $oldTEMP
      $env:TMP = $oldTMP
    }

    "LAUNCH_PID_$inst=$($p.Id)" | Add-Content $log -Encoding utf8
    return [pscustomobject]@{ inst=$inst; p=$p; log=$log; out=$out; err=$err }
  }

  $a = Start-Instance "A"
  $b = Start-Instance "B"

  Wait-Process -Id @($a.p.Id, $b.p.Id)

  $a.p.Refresh()
  $b.p.Refresh()

  foreach ($x in @($a, $b)) {
    Append-LinesSafe -path $x.log -lines @("=== STDOUT ===")
    $outLines = Read-ContentSafe -path $x.out
    if ($outLines.Count -gt 0) { Append-LinesSafe -path $x.log -lines $outLines }
    Append-LinesSafe -path $x.log -lines @("=== STDERR ===")
    $errLines = Read-ContentSafe -path $x.err
    if ($errLines.Count -gt 0) { Append-LinesSafe -path $x.log -lines $errLines }
    Append-LinesSafe -path $x.log -lines @("EXITCODE=$($x.p.ExitCode)")
  }

  $logA = $a.log
  $logB = $b.log

  # Isolation: build artifact must not mutate mid-run
  $exeInfoNow = Get-Item $exe
  $artifactReasons = @()
  if ($exeInfoNow.Length -ne $exeLength0) { $artifactReasons += "exe_length_changed" }
  if ($exeInfoNow.LastWriteTimeUtc -ne $exeWrite0) { $artifactReasons += "exe_timestamp_changed" }

  $resA = Validate-Instance -cycle $i -instance "A" -log $logA -exitCode $a.p.ExitCode -selfPid $a.p.Id -peerPid $b.p.Id
  $resB = Validate-Instance -cycle $i -instance "B" -log $logB -exitCode $b.p.ExitCode -selfPid $b.p.Id -peerPid $a.p.Id

  if ($artifactReasons.Count -gt 0) {
    if ($resA.reasons) { $resA.reasons += "," }
    if ($resB.reasons) { $resB.reasons += "," }
    $resA.reasons += ($artifactReasons -join ",")
    $resB.reasons += ($artifactReasons -join ",")
    $resA.verdict = "FAIL"
    $resB.verdict = "FAIL"
  }

  $results += $resA
  $results += $resB
  $executed += 2

  if ($resA.verdict -ne "PASS") { $firstFail = $resA; break }
  if ($resB.verdict -ne "PASS") { $firstFail = $resB; break }
}

$results | Select-Object @{Name='cycle';Expression={$_.cycle}},
                           @{Name='run';Expression={$_.instance}},
                           @{Name='verdict';Expression={$_.verdict}},
                           @{Name='exitcode';Expression={$_.exitcode}},
                           @{Name='window_created_count';Expression={$_.window_created_count}},
                           @{Name='loop_exit_count';Expression={$_.loop_exit_count}},
                           @{Name='reject_line';Expression={$_.reject_line}},
                           @{Name='exit_line';Expression={$_.exit_line}},
                           @{Name='dispatch_line';Expression={$_.dispatch_line}},
                           @{Name='task_line';Expression={$_.task_line}},
                           @{Name='reasons';Expression={$_.reasons}},
                           @{Name='log';Expression={$_.log}} |
  Export-Csv -Path (Join-Path $pf "90_cycles.csv") -NoTypeInformation -Encoding utf8

$overall = if ($firstFail) { "FAIL" } else { "PASS" }
Finalize-And-Exit -gate $overall -firstFail $firstFail -executedRuns $executed
