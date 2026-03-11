# _proof\phase16_4_exhaustive_secrets_runner.ps1
# Phase 16.4 — Exhaustive Secret-Absence Contract Runner
# Option 4: visible execution + proof artifacts only.

param(
  [switch]$IncludeRepoScan,          # also scan repo source files (can be noisy)
  [switch]$IncludeThirdParty,        # include ThirdParty/ if present
  [switch]$NoBuild,                  # skip build step
  [switch]$NoRuns,                   # skip runtime runners (scan only)
  [int]$Cycles = 5,                  # if running sandbox directly
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
$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File ".\tools\runtime_runner_core.ps1" -phase 16_4 -tag "exhaustive_secrets"
$pf = $paths[0].Trim()
$zip = $paths[1].Trim()
$expectedProof = "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime\_proof"

# =========================
# PROOF FOLDER
# =========================

"PHASE=16.4`nTS=$(Get-Date -Format o)`nPWD=$((Get-Location).Path)`nIncludeRepoScan=$IncludeRepoScan`nIncludeThirdParty=$IncludeThirdParty`nNoBuild=$NoBuild`nNoRuns=$NoRuns" |
  Out-File (Join-Path $pf "00_env.txt") -Encoding utf8
git rev-parse --show-toplevel *> (Join-Path $pf "01_repo_root.txt")
git rev-parse --short HEAD *> (Join-Path $pf "02_head.txt")
git status *> (Join-Path $pf "03_status.txt")

# =========================
# ENTER MSVC ENV (hardened)
# =========================
$envLog = Join-Path $pf "10_enter_msvc_env.txt"
"=== ENTER MSVC ENV ===`nTS=$(Get-Date -Format o)" | Set-Content $envLog -Encoding utf8
.\tools\enter_msvc_env.ps1 *>> $envLog

# =========================
# BUILD (optional)
# =========================
if (-not $NoBuild) {
  $cfgLog = Join-Path $pf "20_config_win_msvc_release.txt"
  $bldLog = Join-Path $pf "21_build_win_msvc_release.txt"
  "=== CONFIGURE ===`nTS=$(Get-Date -Format o)" | Set-Content $cfgLog -Encoding utf8
  cmake --preset win-msvc-release *>> $cfgLog
  "=== BUILD ===`nTS=$(Get-Date -Format o)" | Set-Content $bldLog -Encoding utf8
  cmake --build --preset win-msvc-release -v *>> $bldLog
}

# =========================
# RUNTIME (optional, bounded)
# - If you already have a preferred runner, call it here instead.
# =========================
$exe = ".\artifacts\build\win-msvc-release\bin\win32_sandbox.exe"
if (-not $NoRuns) {
  if (-not (Test-Path $exe)) {
    throw "EXE missing: $exe (build or adjust path)"
  }

  # Clear env vars that might carry secrets, keep only test knobs
  foreach ($k in @(
    "NGK_AUTOCLOSE_MS","NGK_CORE_EVENT_BURST",
    "NGK_CORE_EVENT_BG_ENABLE","NGK_CORE_EVENT_BG_COUNT","NGK_CORE_EVENT_BG_SPACING_MS"
  )) { Remove-Item ("Env:\$k") -ErrorAction SilentlyContinue }

  Set-Item Env:\NGK_AUTOCLOSE_MS ([string]$AutoCloseMs)
  Set-Item Env:\NGK_CORE_EVENT_BURST "200"
  Set-Item Env:\NGK_CORE_EVENT_BG_ENABLE "1"
  Set-Item Env:\NGK_CORE_EVENT_BG_COUNT "200"
  Set-Item Env:\NGK_CORE_EVENT_BG_SPACING_MS "1"

  for ($i=1; $i -le $Cycles; $i++) {
    $log = Join-Path $pf ("30_run_cycle_" + $i.ToString("00") + ".txt")
    & $exe *>> $log
    "EXITCODE=$LASTEXITCODE" | Add-Content $log
    if ($LASTEXITCODE -ne 0) { break }
  }
}

# =========================
# EXHAUSTIVE SCAN
# =========================
# Root sets to scan (only if exist)
$roots = @()
foreach ($p in @(".\_proof",".\artifacts",".\build",".\out",".\logs")) {
  if (Test-Path $p) { $roots += (Resolve-Path $p).Path }
}
if ($IncludeRepoScan) { $roots += (Resolve-Path ".").Path }

# Build ignore rules
$ignoreDirs = @("\.git\", "\node_modules\")
if (-not $IncludeThirdParty) { $ignoreDirs += "\ThirdParty\" }

# File extensions to scan
$exts = @(
  ".txt",".log",".json",".jsonl",".md",".ini",".cfg",".yaml",".yml",".xml",".csv",".tsv",
  ".ps1",".cmd",".bat",".cmake",".hpp",".h",".cpp"
)

# Patterns (regex)
$patterns = @(
  "AKIA[0-9A-Z]{16}",
  "-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----",
  "(?i)\b(access_token|refresh_token|id_token)\b",
  "(?i)\bclient_secret\b",
  "(?i)\bapp_secret\b",
  "(?i)\bapi[_-]?key\b",
  "(?i)\bx-api-key\b",
  "(?i)\bsecret\s*=",
  "(?i)\bBearer\s+[A-Za-z0-9\-\._~\+\/]+=*",
  "sk-[A-Za-z0-9]{20,}",     # OpenAI-style
  "AIza[0-9A-Za-z\-_]{30,}"  # Google API key-ish
)

$hits = @()

function ShouldIgnorePath([string]$full) {
  foreach ($d in $ignoreDirs) {
    if ($full -like "*$d*") { return $true }
  }
  return $false
}

# Scan using Select-String (works everywhere)
foreach ($r in $roots | Select-Object -Unique) {
  $files = Get-ChildItem -Path $r -Recurse -File -ErrorAction SilentlyContinue |
           Where-Object { $exts -contains $_.Extension } |
           Where-Object { -not (ShouldIgnorePath $_.FullName) } |
           Where-Object {
             # Critical: don't scan runner/tool scripts inside _proof (they contain pattern literals by design).
             if ($_.FullName -like "*\_proof\*" -and ($_.Extension -in @(".ps1",".cmd",".bat"))) { return $false }
             # Avoid recursive self-poisoning from prior scan reports that quote matched patterns/snippets.
             if ($_.FullName -like "*\_proof\*" -and $_.Name -eq "91_secret_scan_hits.csv") { return $false }
             return $true
           }

  foreach ($f in $files) {
    foreach ($p in $patterns) {
      $m = Select-String -Path $f.FullName -Pattern $p -AllMatches -ErrorAction SilentlyContinue
      if ($m) {
        foreach ($mm in $m) {
          $hits += [pscustomobject]@{
            file=$f.FullName
            line=$mm.LineNumber
            pattern=$p
            snippet=$mm.Line.Trim()
          }
        }
        break
      }
    }
  }
}

$hitCsv = Join-Path $pf "91_secret_scan_hits.csv"
$hits | Export-Csv -Path $hitCsv -NoTypeInformation -Encoding utf8

$gate = if (@($hits).Count -eq 0) { "PASS" } else { "FAIL" }

$gateFile = Join-Path $pf "98_gate_16_4.txt"
@(
  "PHASE=16.4",
  "TS=$(Get-Date -Format o)",
  "roots_scanned=" + (($roots | Select-Object -Unique) -join ";"),
  "hit_count=" + (@($hits).Count),
  "GATE=$gate"
) | Out-File $gateFile -Encoding utf8

# Zip proof folder
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf "*") -DestinationPath $zip -Force

$repo = $root
$proofRoot = Join-Path $repo "_proof"
$gateFileScan = Get-ChildItem -LiteralPath $proofRoot -Recurse -Force -File |
  Where-Object { $_.Name -eq "98_gate_16_4.txt" } |
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
