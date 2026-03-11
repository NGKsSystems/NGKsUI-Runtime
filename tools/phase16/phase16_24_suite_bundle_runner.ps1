param()

$ErrorActionPreference = 'Stop'

Set-Location "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime"
if ((Get-Location).Path -ne "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime") {
  "hey stupid Fucker, wrong window again"
  exit 1
}

$root = (Get-Location).Path
$proofRoot = "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime\_proof"
$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File ".\tools\runtime_runner_core.ps1" -phase 16_24 -tag "suite_bundle"
$masterPf = $paths[0].Trim()
$masterZip = $paths[1].Trim()
$expectedProof = $proofRoot
New-Item -ItemType Directory -Path (Join-Path $masterPf "subruns") -Force | Out-Null

$rootProofPrefix = $expectedProof + "\"

function Is-UnderPath([string]$candidatePath, [string]$basePath) {
  if (-not $candidatePath -or -not $basePath) { return $false }
  try {
    $cand = [System.IO.Path]::GetFullPath($candidatePath).TrimEnd('\','/')
    $base = [System.IO.Path]::GetFullPath($basePath).TrimEnd('\','/')
    return $cand.StartsWith($base + '\', [System.StringComparison]::OrdinalIgnoreCase) -or
           $cand.Equals($base, [System.StringComparison]::OrdinalIgnoreCase)
  }
  catch {
    return $false
  }
}

function Resolve-RunnerPath([string]$fileName) {
  $p1 = Join-Path (Join-Path (Join-Path $root "tools") "phase16") $fileName
  if (Test-Path $p1) { return [System.IO.Path]::GetFullPath($p1) }

  $p2 = Join-Path (Join-Path (Join-Path $root "tests") "phase16") $fileName
  if (Test-Path $p2) { return [System.IO.Path]::GetFullPath($p2) }

  return $null
}

function Parse-Triplet([string]$text) {
  $pf = ([regex]::Match($text, 'PF=(.+)')).Groups[1].Value.Trim()
  $zip = ([regex]::Match($text, 'ZIP=(.+)')).Groups[1].Value.Trim()
  $gate = ([regex]::Match($text, 'GATE=(PASS|FAIL)')).Groups[1].Value.Trim()
  if (-not $gate) { $gate = "UNKNOWN" }
  return [pscustomobject]@{ PF = $pf; ZIP = $zip; GATE = $gate }
}

function Get-LatestPhasePf([string]$phaseTag, [datetime]$runStart, [string]$excludePf) {
  $pattern = "phase{0}_*" -f $phaseTag
  $cand = Get-ChildItem -Path $proofRoot -Directory -Filter $pattern -ErrorAction SilentlyContinue |
    Where-Object {
      $_.FullName -ne $excludePf -and
      $_.Name -notlike "*__stage_zip*" -and
      $_.LastWriteTime -ge $runStart.AddMinutes(-2)
    } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($cand) { return $cand.FullName }
  return ""
}

function Get-GateFromPf([string]$pfPath) {
  if (-not $pfPath -or -not (Test-Path $pfPath)) { return "UNKNOWN" }
  $gateFile = Get-ChildItem -Path $pfPath -File -Filter "98_gate_*.txt" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if (-not $gateFile) { return "UNKNOWN" }
  $txt = Get-Content -Raw -LiteralPath $gateFile.FullName -ErrorAction SilentlyContinue
  $g = ([regex]::Match($txt, 'GATE=(PASS|FAIL)')).Groups[1].Value.Trim()
  if (-not $g) { return "UNKNOWN" }
  return $g
}

function Ensure-SubrunZip([string]$pfPath) {
  if (-not $pfPath -or -not (Test-Path $pfPath)) { return "" }
  $zipPath = Join-Path $proofRoot ((Split-Path $pfPath -Leaf) + ".zip")
  if (Test-Path $zipPath) { return $zipPath }

  $stage = $pfPath + "__stage_zip_recover"
  if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
  New-Item -ItemType Directory -Path $stage -Force | Out-Null

  $copied = $false
  for ($attempt = 1; $attempt -le 10; $attempt++) {
    try {
      Copy-Item -Path (Join-Path $pfPath "*") -Destination $stage -Recurse -Force
      $copied = $true
      break
    }
    catch {
      Start-Sleep -Milliseconds (150 * $attempt)
    }
  }
  if (-not $copied) {
    if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
    return ""
  }

  $zipped = $false
  for ($attempt = 1; $attempt -le 10; $attempt++) {
    try {
      Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zipPath -Force
      $zipped = $true
      break
    }
    catch {
      Start-Sleep -Milliseconds (200 * $attempt)
    }
  }

  if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
  if ($zipped -and (Test-Path $zipPath)) { return $zipPath }
  return ""
}

function Try-ZipMaster([string]$srcPf, [string]$zipPath) {
  if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
  $stage = $srcPf + "__stage_zip"
  if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
  New-Item -ItemType Directory -Path $stage -Force | Out-Null

  $copied = $false
  for ($attempt = 1; $attempt -le 12; $attempt++) {
    try {
      Copy-Item -Path (Join-Path $srcPf "*") -Destination $stage -Recurse -Force
      $copied = $true
      break
    }
    catch {
      Start-Sleep -Milliseconds (150 * $attempt)
    }
  }
  if (-not $copied) { throw "Failed staging master PF for zip." }

  $zipped = $false
  for ($attempt = 1; $attempt -le 12; $attempt++) {
    try {
      Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zipPath -Force
      $zipped = $true
      break
    }
    catch {
      Start-Sleep -Milliseconds (200 * $attempt)
    }
  }
  Remove-Item -Recurse -Force $stage
  if (-not $zipped -or -not (Test-Path $zipPath)) { throw "Failed creating master zip." }
}

function Quote-Arg([string]$value) {
  if ($null -eq $value) { return '""' }
  $escaped = $value.Replace('"', '""')
  return '"' + $escaped + '"'
}

function Append-TextWithRetry([string]$path, [string]$value) {
  for ($attempt = 1; $attempt -le 8; $attempt++) {
    try {
      Add-Content -LiteralPath $path -Encoding utf8 -Value $value
      return
    }
    catch {
      if ($attempt -eq 8) { throw }
      Start-Sleep -Milliseconds (125 * $attempt)
    }
  }
}

$suite = @(
  [pscustomobject]@{ phase = "16.23.hygiene"; file = "phase16_23_proof_hygiene_no_ps1.ps1"; args = @('-IgnoreOld'); timeoutSec = 60 },
  [pscustomobject]@{ phase = "16.13"; file = "phase16_13_lifecycle_runner.ps1"; args = @('-Cycles','20','-AutoCloseMs','1500'); timeoutSec = 120 },
  [pscustomobject]@{ phase = "16.14"; file = "phase16_14_lifecycle_stressor_runner.ps1"; args = @('-Cycles','10','-AutoCloseMs','1500'); timeoutSec = 600 },
  [pscustomobject]@{ phase = "16.15"; file = "phase16_15_coldstart_contract_runner.ps1"; args = @('-Runs','20'); timeoutSec = 240 },
  [pscustomobject]@{ phase = "16.16"; file = "phase16_16_restart_contract_runner.ps1"; args = @('-Iters','10','-AutoCloseMs','1500'); timeoutSec = 180 },
  [pscustomobject]@{ phase = "16.17"; file = "phase16_17_sustained_restart_runner.ps1"; args = @('-Cycles','75','-AutoCloseMs','1500'); timeoutSec = 600 },
  [pscustomobject]@{ phase = "16.18"; file = "phase16_18_dual_instance_runner.ps1"; args = @('-Cycles','25','-AutoCloseMs','1500'); timeoutSec = 420 },
  [pscustomobject]@{ phase = "16.19"; file = "phase16_19_multi_instance_concurrency_runner.ps1"; args = @('-Instances','32','-AutoCloseMs','2000','-StartStaggerMs','50','-TimeoutSec','30'); timeoutSec = 900 },
  [pscustomobject]@{ phase = "16.20"; file = "phase16_20_present_fail_matrix_runner.ps1"; args = @('-Policies','0,1,2','-FailEvery','10','-CyclesPerPolicy','20','-AutoCloseMs','1500','-TimeoutSec','30'); timeoutSec = 900 },
  [pscustomobject]@{ phase = "16.21"; file = "phase16_21_quit_policy_latency_runner.ps1"; args = @(); timeoutSec = 300 },
  [pscustomobject]@{ phase = "16.23"; file = "phase16_23_proof_compliance_gate.ps1"; args = @(); timeoutSec = 120 }
)

@(
  "PHASE=16.24",
  "TS=$(Get-Date -Format o)",
  "ROOT=$root",
  "MASTER_PF=$masterPf",
  "SUITE_COUNT=$($suite.Count)"
) | Set-Content -Path (Join-Path $masterPf "00_context.txt") -Encoding utf8

git status *> (Join-Path $masterPf "01_status.txt")
git log -1 *> (Join-Path $masterPf "02_head.txt")

$planLines = @("TS=$(Get-Date -Format o)")
foreach ($s in $suite) {
  $planLines += ("PHASE={0} FILE={1} ARGS={2}" -f $s.phase, $s.file, ($s.args -join ' '))
}
$planLines | Set-Content -Path (Join-Path $masterPf "10_suite_plan.txt") -Encoding utf8

$buildLog = Join-Path $masterPf "20_build.txt"
"=== ENTER MSVC ENV ===`nTS=$(Get-Date -Format o)" | Set-Content -Path $buildLog -Encoding utf8
.\tools\enter_msvc_env.ps1 *>> $buildLog
Get-ChildItem -Path $proofRoot -Filter "__ngk_vs*" -File -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 6 |
  Copy-Item -Destination $masterPf -Force

Append-TextWithRetry -path $buildLog -value "=== CMAKE CONFIGURE ==="
cmake --preset win-msvc-release *>> $buildLog
Append-TextWithRetry -path $buildLog -value "=== CMAKE BUILD ==="
cmake --build --preset win-msvc-release -v *>> $buildLog

$results = @()
$failedPhase = "none"
$failReason = ""
$firstFailStdoutLog = ""

foreach ($s in $suite) {
  $phaseKey = ("phase_" + $s.phase.Replace('.','_'))
  $subDir = Join-Path (Join-Path $masterPf "subruns") $phaseKey
  New-Item -ItemType Directory -Path $subDir -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $subDir "copied_pf") -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $subDir "copied_zip") -Force | Out-Null

  $stdoutLog = Join-Path $subDir "30_stdout.txt"
  $stderrLog = Join-Path $subDir "31_stderr.txt"

  $runnerPath = Resolve-RunnerPath $s.file
  if (-not $runnerPath) {
    $failedPhase = $s.phase
    $failReason = "runner_missing:$($s.file)"
    $firstFailStdoutLog = $stdoutLog
    "runner_missing=$($s.file)" | Set-Content -Path $stdoutLog -Encoding utf8
    $results += [pscustomobject]@{
      phase=$s.phase; gate="FAIL"; pf=""; zip=""; pf_in_proof=0; zip_in_proof=0; exists_pf=0; exists_zip=0; notes=$failReason
    }
    break
  }

  if ($runnerPath -and (Is-UnderPath -candidatePath $runnerPath -basePath $proofRoot)) {
    throw "HARD_FAIL: runner resolved inside _proof: $runnerPath"
  }

  $runStart = Get-Date
  $argParts = @('-NoProfile','-ExecutionPolicy','Bypass','-File', (Quote-Arg $runnerPath))
  foreach ($a in $s.args) {
    $argParts += (Quote-Arg ([string]$a))
  }
  $argString = ($argParts -join ' ')
  $p = Start-Process -FilePath "powershell" -ArgumentList $argString -PassThru -NoNewWindow -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog

  $timedOut = $false
  $deadline = (Get-Date).AddSeconds([int]$s.timeoutSec)
  while (-not $p.HasExited) {
    Start-Sleep -Seconds 2
    if ((Get-Date) -ge $deadline) {
      $timedOut = $true
      try {
        Get-CimInstance Win32_Process -Filter "ParentProcessId=$($p.Id)" -ErrorAction SilentlyContinue |
          ForEach-Object {
            try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
          }
      } catch {}
      try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
      try {
        Add-Content -LiteralPath $stderrLog -Encoding utf8 -Value "TIMEOUT: phase $($s.phase) exceeded $($s.timeoutSec)s"
      }
      catch {
        Set-Content -LiteralPath (Join-Path $subDir "32_timeout_note.txt") -Encoding utf8 -Value "TIMEOUT: phase $($s.phase) exceeded $($s.timeoutSec)s"
      }
      break
    }
  }

  if (-not $timedOut -and -not $p.HasExited) {
    $p.WaitForExit()
  }

  $allText = ""
  if (Test-Path $stdoutLog) { $allText += (Get-Content -Raw -LiteralPath $stdoutLog -ErrorAction SilentlyContinue) + "`n" }
  if (Test-Path $stderrLog) { $allText += (Get-Content -Raw -LiteralPath $stderrLog -ErrorAction SilentlyContinue) + "`n" }

  $triplet = Parse-Triplet $allText
  $pfOut = $triplet.PF
  $zipOut = $triplet.ZIP
  $gateOut = $triplet.GATE

  if ($timedOut) {
    $gateOut = "FAIL"
  }

  if (-not $pfOut) {
    $pfOut = Get-LatestPhasePf -phaseTag ($s.phase.Replace('.','_')) -runStart $runStart -excludePf $masterPf
  }
  if (($gateOut -eq "UNKNOWN") -and $pfOut) {
    $gateOut = Get-GateFromPf -pfPath $pfOut
  }
  if (-not $zipOut -and $pfOut) {
    $zipOut = Ensure-SubrunZip -pfPath $pfOut
  }
  elseif ($zipOut -and -not (Test-Path $zipOut) -and $pfOut) {
    $zipOut = Ensure-SubrunZip -pfPath $pfOut
  }

  $pfInProof = [int]($pfOut -and $pfOut.StartsWith($rootProofPrefix, [System.StringComparison]::OrdinalIgnoreCase))
  $zipInProof = [int]($zipOut -and $zipOut.StartsWith($rootProofPrefix, [System.StringComparison]::OrdinalIgnoreCase))
  $existsPf = [int]($pfOut -and (Test-Path $pfOut))
  $existsZip = [int]($zipOut -and (Test-Path $zipOut))

  $notes = @()
  if ($gateOut -ne "PASS") { $notes += "subrun_gate=$gateOut" }
  if ($pfInProof -ne 1) { $notes += "pf_not_under__proof" }
  if ($zipInProof -ne 1) { $notes += "zip_not_under__proof" }
  if ($existsPf -ne 1) { $notes += "pf_missing" }
  if ($existsZip -ne 1) { $notes += "zip_missing" }

  if ($existsPf -eq 1) {
    Copy-Item -Path $pfOut -Destination (Join-Path $subDir "copied_pf") -Recurse -Force
  }
  if ($existsZip -eq 1) {
    Copy-Item -Path $zipOut -Destination (Join-Path $subDir "copied_zip") -Force
  }

  $results += [pscustomobject]@{
    phase=$s.phase
    gate=$gateOut
    pf=$pfOut
    zip=$zipOut
    pf_in_proof=$pfInProof
    zip_in_proof=$zipInProof
    exists_pf=$existsPf
    exists_zip=$existsZip
    notes=($notes -join ',')
  }

  if ($notes.Count -gt 0) {
    $failedPhase = $s.phase
    $failReason = ($notes -join ',')
    $firstFailStdoutLog = $stdoutLog
    break
  }
}

$results | Select-Object phase,gate,pf,zip,pf_in_proof,zip_in_proof,exists_pf,exists_zip,notes |
  Export-Csv -Path (Join-Path $masterPf "40_subrun_index.csv") -NoTypeInformation -Encoding utf8

$totalPlanned = $suite.Count
$totalExecuted = $results.Count
$overall = if (($failedPhase -eq "none") -and ($totalExecuted -eq $totalPlanned)) { "PASS" } else { "FAIL" }

@(
  "PHASE=16.24",
  "TS=$(Get-Date -Format o)",
  "TotalPlanned=$totalPlanned",
  "TotalExecuted=$totalExecuted",
  "GATE=$overall",
  "failed_phase=$failedPhase",
  "reason=$failReason"
) | Set-Content -Path (Join-Path $masterPf "98_gate_16_24.txt") -Encoding utf8

Try-ZipMaster -srcPf $masterPf -zipPath $masterZip

$gate24Path = Join-Path $masterPf "98_gate_16_24.txt"
$gateFileScan = Get-ChildItem -LiteralPath $proofRoot -Recurse -Force -File |
  Where-Object { $_.Name -eq "98_gate_16_24.txt" } |
  Sort-Object LastWriteTimeUtc -Descending |
  Select-Object -First 1

if (-not $gateFileScan) { throw "missing_gate_file" }

$pfPrint = Split-Path $gateFileScan.FullName -Parent
$zipPrint = Join-Path $proofRoot ((Split-Path $pfPrint -Leaf) + ".zip")
$gateTextPrint = Get-Content -Raw -LiteralPath $gate24Path -ErrorAction SilentlyContinue
$gatePrint = ([regex]::Match($gateTextPrint, '(?im)^\s*GATE\s*=\s*(PASS|FAIL)\s*$')).Groups[1].Value.Trim()
if (-not $gatePrint) { $gatePrint = $overall }

$badPrintedPaths = $false
if (-not ($pfPrint -and $pfPrint.StartsWith($rootProofPrefix, [System.StringComparison]::OrdinalIgnoreCase))) { $badPrintedPaths = $true }
if (-not ($zipPrint -and $zipPrint.StartsWith($rootProofPrefix, [System.StringComparison]::OrdinalIgnoreCase))) { $badPrintedPaths = $true }
if ($badPrintedPaths) {
  @(
    "PHASE=16.24",
    "TS=$(Get-Date -Format o)",
    "TotalPlanned=$totalPlanned",
    "TotalExecuted=$totalExecuted",
    "GATE=FAIL",
    "failed_phase=path_validation",
    "reason=bad_printed_paths"
  ) | Set-Content -Path $gate24Path -Encoding utf8
  $overall = "FAIL"
  $gatePrint = "FAIL"
}

if (-not (Test-Path -LiteralPath $pfPrint))  { throw "bad_printed_paths:pf_missing" }
if (-not (Test-Path -LiteralPath $zipPrint)) { throw "bad_printed_paths:zip_missing" }

$pfResolved = (Resolve-Path -LiteralPath $pfPrint).Path
$zipResolved = (Resolve-Path -LiteralPath $zipPrint).Path
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
Write-Output "GATE=$gatePrint"

if ($overall -ne "PASS") {
  Get-Content -LiteralPath (Join-Path $masterPf "98_gate_16_24.txt")
  if ($firstFailStdoutLog -and (Test-Path $firstFailStdoutLog)) {
    Get-Content -LiteralPath $firstFailStdoutLog -Tail 200
  }
  exit 2
}

exit 0
