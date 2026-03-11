# _proof\phase16_13_lifecycle_runner.ps1
# Phase 16.13 — Lifecycle Stability / N-cycle Contract Runner
# Option 4: visible execution + proof artifacts only.

param(
  [int]$Cycles = 10,
  [int]$AutoCloseMs = 1500,
  [switch]$NoSecretScan
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
$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File ".\tools\runtime_runner_core.ps1" -phase 16_13 -tag "lifecycle"
$pf = $paths[0].Trim()
$zip = $paths[1].Trim()
$expectedProof = "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime\_proof"

# =========================
# PROOF FOLDER
# =========================

"PHASE=16.13`nTS=$(Get-Date -Format o)`nPWD=$((Get-Location).Path)`nCycles=$Cycles`nAutoCloseMs=$AutoCloseMs" |
  Out-File (Join-Path $pf "00_env.txt") -Encoding utf8
git rev-parse --show-toplevel *> (Join-Path $pf "01_repo_root.txt")
git rev-parse --short HEAD *> (Join-Path $pf "02_head.txt")
git status *> (Join-Path $pf "03_status.txt")

# =========================
# BUILD ONCE
# =========================
. .\tools\enter_msvc_env.ps1 | Out-Null
cmake --preset win-msvc-release *> (Join-Path $pf "30_config.txt")
cmake --build --preset win-msvc-release -v *> (Join-Path $pf "31_build.txt")

$exe = ".\artifacts\build\win-msvc-release\bin\win32_sandbox.exe"
if (-not (Test-Path $exe)) { throw "EXE missing after build: $exe" }
"EXE=$exe" | Out-File (Join-Path $pf "32_exe.txt") -Encoding utf8

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

function Run-Cycle([int]$i) {
  $name = ("cycle_" + ($i.ToString("00")))
  $log = Join-Path $pf ("run_" + $name + ".txt")
  $exitf = Join-Path $pf ("exit_" + $name + ".txt")

  Clear-NGKEnv

  # Stress shutdown + ordering invariants (same spirit as 16.8/16.12)
  Set-Item Env:\NGK_AUTOCLOSE_MS ([string]$AutoCloseMs)
  Set-Item Env:\NGK_CORE_EVENT_BURST "200"
  Set-Item Env:\NGK_CORE_EVENT_BG_ENABLE "1"
  Set-Item Env:\NGK_CORE_EVENT_BG_COUNT "300"
  Set-Item Env:\NGK_CORE_EVENT_BG_SPACING_MS "1"

  & $exe *>> $log
  "EXITCODE=$LASTEXITCODE" | Out-File $exitf -Encoding utf8

  # Markers (ENTER is informational only; your existing 16.12 gate already reports enter=-1 and passes)
  $nEnter    = Last-LineNo $log "NGK_CORE_LOOP_ENTER"
  $nExit     = Last-LineNo $log "NGK_CORE_LOOP_EXIT"
  $nReject   = Last-LineNo $log "NGK_CORE_EVENT_REJECTED"
  $nDispatch = Last-LineNo $log "NGK_CORE_EVENT_DISPATCHED"
  $nTask     = Last-LineNo $log "NGK_CORE_TASK_RAN"

  $reasons = @()

  if (-not (Get-Content $exitf | Select-String "EXITCODE=0" -ErrorAction SilentlyContinue)) { $reasons += "exit!=0" }
  if ($nExit  -lt 0) { $reasons += "exit_marker_missing" }

  # Ordering invariant you care about: REJECTED must be after LOOP_EXIT (if REJECTED exists)
  if ($nReject -ge 0 -and $nExit -ge 0 -and $nReject -lt $nExit) { $reasons += "reject_not_after_exit" }

  # No work after exit
  if ($nDispatch -ge 0 -and $nExit -ge 0 -and $nDispatch -gt $nExit) { $reasons += "dispatch_after_exit" }
  if ($nTask -ge 0 -and $nExit -ge 0 -and $nTask -gt $nExit) { $reasons += "task_after_exit" }

  $verdict = if ($reasons.Count -eq 0) { "PASS" } else { "FAIL" }

  [pscustomobject]@{
    cycle=$i
    verdict=$verdict
    exitcode=(Get-Content $exitf | Select-Object -First 1)
    enter=$nEnter
    exit=$nExit
    reject=$nReject
    dispatch=$nDispatch
    task=$nTask
    reasons=($reasons -join ",")
    log=$log
    exitf=$exitf
  }
}

function Secret-Scan([string]$rootPath) {
  $patterns = @(
    "AKIA[0-9A-Z]{16}",
    "-----BEGIN (RSA|EC|OPENSSH) ",
    "Bearer\s+[A-Za-z0-9\-\._~\+\/]+=*",
    "refresh_token", "access_token",
    "client_secret", "api_key", "secret="
  )

  $hits = @()
  $files = Get-ChildItem -Path $rootPath -Recurse -File -ErrorAction SilentlyContinue |
           Where-Object { $_.Extension -in @(".txt",".log",".json",".jsonl",".md") }

  foreach ($f in $files) {
    foreach ($p in $patterns) {
      $m = Select-String -Path $f.FullName -Pattern $p -AllMatches -ErrorAction SilentlyContinue
      if ($m) {
        $hits += [pscustomobject]@{ file=$f.FullName; pattern=$p; line=$m[0].LineNumber }
        break
      }
    }
  }
  return $hits
}

# =========================
# RUN N CYCLES
# =========================
$results = @()
for ($i=1; $i -le $Cycles; $i++) {
  $results += (Run-Cycle $i)
}

# Audit-friendly outputs
$results | Select-Object cycle,verdict,exitcode,enter,exit,reject,dispatch,task,reasons |
  Export-Csv -Path (Join-Path $pf "90_cycles.csv") -NoTypeInformation -Encoding utf8

# Determine gate
$fail = $results | Where-Object { $_.verdict -ne "PASS" } | Select-Object -First 1

# Secret scan (unless disabled)
$secretHits = @()
if (-not $NoSecretScan) {
  $secretHits = @(Secret-Scan $pf)
  $secretHits | Export-Csv -Path (Join-Path $pf "91_secret_scan_hits.csv") -NoTypeInformation -Encoding utf8
} else {
  "SecretScan=SKIPPED" | Out-File (Join-Path $pf "91_secret_scan_hits.csv") -Encoding utf8
}

$secretHitCount = @($secretHits).Count

$reasonsOverall = @()
if ($fail) { $reasonsOverall += ("cycle_" + $fail.cycle.ToString("00") + ":" + $fail.reasons) }
if ($secretHitCount -gt 0) { $reasonsOverall += "secrets_detected" }

$overall = if ($reasonsOverall.Count -eq 0) { "PASS" } else { "FAIL" }

$gateFile = Join-Path $pf "98_gate_16_13.txt"
@(
  "PHASE=16.13",
  "TS=$(Get-Date -Format o)",
  "Cycles=$Cycles",
  "AutoCloseMs=$AutoCloseMs",
  "GATE=$overall",
  "reasons=" + ($reasonsOverall -join ","),
  "failed_cycle=" + ($(if($fail){$fail.cycle}else{"none"})),
  "secret_hits=$secretHitCount"
) | Out-File $gateFile -Encoding utf8

# Zip proof
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf "*") -DestinationPath $zip -Force

$repo = $root
$proofRoot = Join-Path $repo "_proof"
$gateFileScan = Get-ChildItem -LiteralPath $proofRoot -Recurse -Force -File |
  Where-Object { $_.Name -eq "98_gate_16_13.txt" } |
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

if ($overall -ne "PASS") { exit 2 }
exit 0
