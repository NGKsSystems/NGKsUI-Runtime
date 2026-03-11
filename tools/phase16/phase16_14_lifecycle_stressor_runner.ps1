# _proof\phase16_14_lifecycle_stressor_runner.ps1
# Phase 16.14 — Multi-Stressor Lifecycle Contract Runner
# Option 4: visible execution + proof artifacts only.

param(
  [int]$Cycles = 10,
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
$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File ".\tools\runtime_runner_core.ps1" -phase 16_14 -tag "lifecycle_stressor"
$pf = $paths[0].Trim()
$zip = $paths[1].Trim()
$expectedProof = "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime\_proof"

# =========================
# PROOF FOLDER
# =========================

"PHASE=16.14`nTS=$(Get-Date -Format o)`nPWD=$((Get-Location).Path)`nCycles=$Cycles`nAutoCloseMs=$AutoCloseMs" |
  Out-File (Join-Path $pf "00_env.txt") -Encoding utf8
git rev-parse --show-toplevel *> (Join-Path $pf "01_repo_root.txt")
git rev-parse --short HEAD *> (Join-Path $pf "02_head.txt")
git status *> (Join-Path $pf "03_status.txt")

# =========================
# ENTER MSVC ENV (hardened) + BUILD ONCE
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
  foreach ($k in @(
    "NGK_AUTOCLOSE_MS",
    "NGK_CORE_EVENT_BURST",
    "NGK_CORE_EVENT_BG_ENABLE","NGK_CORE_EVENT_BG_COUNT","NGK_CORE_EVENT_BG_SPACING_MS",
    "NGK_WIN32_MSG_BURST",
    "NGK_PRESENT_FAIL_EVERY","NGK_PRESENT_FAIL_POLICY","NGK_PRESENT_FAIL_MAX_CONSEC"
  )) {
    Remove-Item ("Env:\$k") -ErrorAction SilentlyContinue
  }
}

function Last-LineNo($path,$pattern) {
  if (-not (Test-Path $path)) { return -1 }
  $m = Select-String -Path $path -Pattern $pattern -ErrorAction SilentlyContinue | Select-Object -Last 1
  if (-not $m) { return -1 }
  return [int]$m.LineNumber
}

function Run-One([string]$variantName, [hashtable]$variantEnv, [int]$cycleIdx) {
  $cycleTag = $cycleIdx.ToString("00")
  $log = Join-Path $pf ("run_cycle_" + $cycleTag + "__" + $variantName + ".txt")

  Clear-NGKEnv

  # Always set autoclose
  Set-Item Env:\NGK_AUTOCLOSE_MS ([string]$AutoCloseMs)

  # Apply variant env
  foreach ($k in $variantEnv.Keys) {
    Set-Item ("Env:\$k") ([string]$variantEnv[$k])
  }

  # Robust capture (fix): capture stdout+stderr into log
  "=== RUN $variantName cycle=$cycleTag TS=$(Get-Date -Format o) ===" | Out-File -FilePath $log -Encoding utf8
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
  "EXITCODE=$LASTEXITCODE" | Out-File -FilePath $log -Append -Encoding utf8

  $nExit     = Last-LineNo $log "NGK_CORE_LOOP_EXIT"
  $nReject   = Last-LineNo $log "NGK_CORE_EVENT_REJECTED"
  $nDispatch = Last-LineNo $log "NGK_CORE_EVENT_DISPATCHED"
  $nTask     = Last-LineNo $log "NGK_CORE_TASK_RAN"

  $reasons = @()
  if ($LASTEXITCODE -ne 0) { $reasons += "exit!=0" }
  if ($nExit -lt 0) { $reasons += "exit_marker_missing" }
  if ($nReject -ge 0 -and $nExit -ge 0 -and $nReject -lt $nExit) { $reasons += "reject_not_after_exit" }
  if ($nDispatch -ge 0 -and $nExit -ge 0 -and $nDispatch -gt $nExit) { $reasons += "dispatch_after_exit" }
  if ($nTask -ge 0 -and $nExit -ge 0 -and $nTask -gt $nExit) { $reasons += "task_after_exit" }

  $verdict = if ($reasons.Count -eq 0) { "PASS" } else { "FAIL" }

  return [pscustomobject]@{
    variant=$variantName
    cycle=$cycleIdx
    verdict=$verdict
    exitcode=$LASTEXITCODE
    exit=$nExit
    reject=$nReject
    dispatch=$nDispatch
    task=$nTask
    reasons=($reasons -join ",")
    log=$log
  }
}

function Finalize-And-Exit([string]$gate, [string]$failedVariant, [int]$failedCycle, [string]$reason, [int]$executedRuns) {
  $gateFile = Join-Path $pf "98_gate_16_14.txt"
  $variantsCount = 4
  $totalPlanned = $variantsCount * $Cycles

  @(
    "PHASE=16.14",
    "TS=$(Get-Date -Format o)",
    "Cycles=$Cycles",
    "Variants=$variantsCount",
    "TotalPlannedRuns=$totalPlanned",
    "TotalExecutedRuns=$executedRuns",
    "AutoCloseMs=$AutoCloseMs",
    "GATE=$gate",
    "failed_variant=$failedVariant",
    "failed_cycle=$failedCycle",
    "reason=$reason"
  ) | Out-File $gateFile -Encoding utf8

  $csv = Join-Path $pf "90_cycles.csv"
  if (-not (Test-Path $csv)) {
    "variant,cycle,verdict,exitcode,exit,reject,dispatch,task,reasons,log" | Out-File $csv -Encoding utf8
  }

  if (Test-Path $zip) { Remove-Item -Force $zip }
  Compress-Archive -Path (Join-Path $pf "*") -DestinationPath $zip -Force

  $repo = $root
  $proofRoot = Join-Path $repo "_proof"
  $gateFileScan = Get-ChildItem -LiteralPath $proofRoot -Recurse -Force -File |
    Where-Object { $_.Name -eq "98_gate_16_14.txt" } |
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
# VARIANTS (A/B/C/D)
# =========================
$variants = @(
  @{ name="A_baseline"; env=@{
      "NGK_CORE_EVENT_BURST"="200"
      "NGK_CORE_EVENT_BG_ENABLE"="1"
      "NGK_CORE_EVENT_BG_COUNT"="300"
      "NGK_CORE_EVENT_BG_SPACING_MS"="1"
    } },
  @{ name="B_heavy_events"; env=@{
      "NGK_CORE_EVENT_BURST"="600"
      "NGK_CORE_EVENT_BG_ENABLE"="1"
      "NGK_CORE_EVENT_BG_COUNT"="1200"
      "NGK_CORE_EVENT_BG_SPACING_MS"="0"
    } },
  @{ name="C_present_fail_recover"; env=@{
      "NGK_PRESENT_FAIL_EVERY"="1"
      "NGK_PRESENT_FAIL_POLICY"="2"
      "NGK_PRESENT_FAIL_MAX_CONSEC"="5"
      "NGK_CORE_EVENT_BURST"="200"
      "NGK_CORE_EVENT_BG_ENABLE"="1"
      "NGK_CORE_EVENT_BG_COUNT"="300"
      "NGK_CORE_EVENT_BG_SPACING_MS"="1"
    } },
  @{ name="D_win32_msg_burst"; env=@{
      "NGK_WIN32_MSG_BURST"="2000"
      "NGK_CORE_EVENT_BURST"="200"
      "NGK_CORE_EVENT_BG_ENABLE"="1"
      "NGK_CORE_EVENT_BG_COUNT"="300"
      "NGK_CORE_EVENT_BG_SPACING_MS"="1"
    } }
)

# =========================
# RUN (FAIL-FAST)
# =========================
$csv = Join-Path $pf "90_cycles.csv"
"variant,cycle,verdict,exitcode,exit,reject,dispatch,task,reasons,log" | Out-File $csv -Encoding utf8

$executed = 0

foreach ($v in $variants) {
  $vn = $v.name
  $ve = $v.env

  for ($i=1; $i -le $Cycles; $i++) {
    $executed++
    $r = Run-One $vn $ve $i

    # Append result row
    ($r.variant + "," + $r.cycle + "," + $r.verdict + "," + $r.exitcode + "," + $r.exit + "," + $r.reject + "," + $r.dispatch + "," + $r.task + "," + '"' + $r.reasons + '"' + "," + '"' + $r.log + '"') |
      Add-Content $csv

    if ($r.verdict -ne "PASS") {
      Finalize-And-Exit "FAIL" $vn $i $r.reasons $executed
    }
  }
}

Finalize-And-Exit "PASS" "" 0 "" $executed
