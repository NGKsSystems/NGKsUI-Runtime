# _proof\phase16_16_restart_contract_runner.ps1
# Phase 16.16 — Restart Contract (warm restart determinism)
# Option 4: visible execution + proof artifacts only.

param(
  [int]$Iters = 10,
  [int]$AutoCloseMs = 1500
)

$ErrorActionPreference='Stop'

# =========================
# HARD WINDOW GUARD
# =========================
Set-Location "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime"
if ((Get-Location).Path -ne "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime") {
  "hey stupid Fucker, wrong window again"
  exit 1
}

$root = (Get-Location).Path
$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File ".\tools\runtime_runner_core.ps1" -phase 16_16 -tag "restart_contract"
$pf = $paths[0].Trim()
$zip = $paths[1].Trim()
$expectedProof = "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime\_proof"

# =========================
# PROOF FOLDER
# =========================

"PHASE=16.16`nTS=$(Get-Date -Format o)`nPWD=$((Get-Location).Path)`nIters=$Iters`nAutoCloseMs=$AutoCloseMs" |
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

function Resolve-ExitMarker([string]$path) {
  $candidates = @(
    "NGK_CORE_LOOP_EXIT"
  )

  foreach ($marker in $candidates) {
    if (Count-Marker $path $marker -gt 0) {
      return $marker
    }
  }

  return "NGK_CORE_LOOP_EXIT"
}

function Run-One([int]$iter,[string]$runTag) {
  $iterTag = $iter.ToString("00")
  $log = Join-Path $pf ("run_iter_" + $iterTag + "_" + $runTag + ".txt")

  Clear-NGKEnv
  Remove-Item Env:\NGK_AUTOCLOSE_MS -ErrorAction SilentlyContinue
  Set-Item Env:\NGK_AUTOCLOSE_MS ([string]$AutoCloseMs)

  "=== RUN iter=$iterTag run=$runTag TS=$(Get-Date -Format o) ===" | Out-File -FilePath $log -Encoding utf8

  $prevErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    & $exe 2>&1 | ForEach-Object {
      $_ | Out-File -FilePath $log -Append -Encoding utf8
      $_
    }
  }
  finally {
    $ErrorActionPreference = $prevErrorActionPreference
  }

  $exitCode = $LASTEXITCODE
  "EXITCODE=$exitCode" | Out-File -FilePath $log -Append -Encoding utf8

  $windowCreatedCount = Count-Marker $log "window_created=1"
  $exitMarker = Resolve-ExitMarker $log
  $loopExitCount = Count-Marker $log $exitMarker

  $nExit = Last-LineNo $log $exitMarker
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

  $verdict = if ($reasons.Count -eq 0) { "PASS" } else { "FAIL" }

  return [pscustomobject]@{
    iter=$iter
    run=$runTag
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

function Finalize-And-Exit([string]$gate,[object]$firstFail,[int]$executedRuns) {
  $gateFile = Join-Path $pf "98_gate_16_16.txt"
  $totalPlanned = $Iters * 2

  @(
    "PHASE=16.16",
    "TS=$(Get-Date -Format o)",
    "Iters=$Iters",
    "AutoCloseMs=$AutoCloseMs",
    "TotalPlannedRuns=$totalPlanned",
    "TotalExecutedRuns=$executedRuns",
    "GATE=$gate",
    "failed_iter=" + ($(if($firstFail){$firstFail.iter}else{"none"})),
    "failed_run=" + ($(if($firstFail){$firstFail.run}else{"none"})),
    "reason=" + ($(if($firstFail){$firstFail.reasons}else{""}))
  ) | Out-File $gateFile -Encoding utf8

  # Stage-copy zip to avoid file-lock races
  if (Test-Path $zip) { Remove-Item -Force $zip }

  $stage = ($pf + "__stage_zip")
  if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
  New-Item -ItemType Directory -Force $stage | Out-Null

  Copy-Item -Path (Join-Path $pf "*") -Destination $stage -Recurse -Force
  Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip -Force
  Remove-Item -Recurse -Force $stage

  $repo = $root
  $proofRoot = Join-Path $repo "_proof"
  $gateFileScan = Get-ChildItem -LiteralPath $proofRoot -Recurse -Force -File |
    Where-Object { $_.Name -eq "98_gate_16_16.txt" } |
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

  if ($gate -ne "PASS") { exit 2 }
  exit 0
}

# =========================
# RUN ITERATIONS (A then B, fail-fast)
# =========================
$results = @()
$firstFail = $null
$executed = 0

for ($i=1; $i -le $Iters; $i++) {
  foreach ($r in @("A","B")) {
    $executed++
    $res = Run-One -iter $i -runTag $r
    $results += $res

    if ($res.verdict -ne "PASS") {
      $firstFail = $res
      break
    }
  }

  if ($firstFail) { break }
}

$results | Select-Object iter,run,verdict,exitcode,window_created_count,loop_exit_count,reject_line,exit_line,dispatch_line,task_line,reasons,log |
  Export-Csv -Path (Join-Path $pf "90_iters.csv") -NoTypeInformation -Encoding utf8

$overall = if ($firstFail) { "FAIL" } else { "PASS" }
Finalize-And-Exit -gate $overall -firstFail $firstFail -executedRuns $executed
