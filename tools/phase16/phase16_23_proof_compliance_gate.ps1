param(
  [string]$PhaseGlob = "phase16*.ps1",
  [int]$QuickRun = 3,
  [string]$AllowList = "phase16_19_multi_instance_concurrency_runner.ps1;phase16_20_present_fail_matrix_runner.ps1;phase16_21_quit_policy_latency_runner.ps1"
)

$ErrorActionPreference = 'Stop'

Set-Location "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime"
if ((Get-Location).Path -ne "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime") {
  "hey stupid Fucker, wrong window again"
  exit 1
}

$root = (Get-Location).Path
$proofRoot = Join-Path $root "_proof"
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$pf = Join-Path $proofRoot ("phase16_23_proof_compliance_" + $ts)
New-Item -ItemType Directory -Path $pf -Force | Out-Null

$auditFile = Join-Path $pf "00_static_audit.txt"
$planFile = Join-Path $pf "10_quickrun_plan.txt"
$runsCsv = Join-Path $pf "90_runs.csv"
$gateFile = Join-Path $pf "98_gate_16_23.txt"

$runnerFiles = @(Get-ChildItem -Path $proofRoot -Recurse -File -Filter $PhaseGlob -ErrorAction SilentlyContinue)
if ($runnerFiles.Count -eq 0) {
  $runnerFiles = @(Get-ChildItem -Path $proofRoot -Recurse -File -Filter "phase16*.ps1" -ErrorAction SilentlyContinue)
}

$badRootRegex = '\$root\s*\+\s*"_proof"|"\$\{root\}_proof"|"\$root_proof"'
$offenders = @()

foreach ($f in $runnerFiles) {
  if ($f.Name -ieq "phase16_23_proof_compliance_gate.ps1") { continue }
  $text = Get-Content -Raw -LiteralPath $f.FullName -ErrorAction SilentlyContinue
  if ($null -eq $text) { $text = "" }

  $badMatches = [regex]::Matches($text, $badRootRegex)
  foreach ($m in $badMatches) {
    $lineNo = ([regex]::Matches($text.Substring(0, $m.Index), "`r?`n")).Count + 1
    $line = (Get-Content -LiteralPath $f.FullName -ErrorAction SilentlyContinue | Select-Object -Index ($lineNo - 1))
    $offenders += [pscustomobject]@{ file = $f.FullName; line = $lineNo; reason = "bad_proof_root_pattern"; text = $line }
  }

  $hasPFPrint = $text -match '"PF='
  $hasZIPPrint = $text -match '"ZIP='
  $hasProofUsage = $text -match '_proof'
  if (($hasPFPrint -or $hasZIPPrint) -and (-not $hasProofUsage)) {
    $offenders += [pscustomobject]@{ file = $f.FullName; line = 0; reason = "pf_zip_print_without__proof_reference"; text = "" }
  }
}

@(
  "PHASE=16.23",
  "TS=$(Get-Date -Format o)",
  "ROOT=$root",
  "PhaseGlob=$PhaseGlob",
  "RunnerCount=$($runnerFiles.Count)",
  "OffenderCount=$($offenders.Count)",
  "PATTERN=$badRootRegex",
  ""
) | Set-Content -Path $auditFile -Encoding utf8

if ($offenders.Count -gt 0) {
  $offenders | ForEach-Object {
    @(
      "FILE=$($_.file)",
      "LINE=$($_.line)",
      "REASON=$($_.reason)",
      "TEXT=$($_.text)",
      "---"
    )
  } | Add-Content -Path $auditFile -Encoding utf8
} else {
  "No static offenders found." | Add-Content -Path $auditFile -Encoding utf8
}

$allowNames = @($AllowList.Split(';') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
$selected = @()
foreach ($name in $allowNames) {
  $match = $runnerFiles | Where-Object { $_.Name -ieq $name } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($match) {
    $selected += $match
  }
}

if ($QuickRun -gt 0) {
  $selected = @($selected | Select-Object -First $QuickRun)
}

@(
  "TS=$(Get-Date -Format o)",
  "QuickRun=$QuickRun",
  "AllowList=$AllowList",
  "SelectedCount=$($selected.Count)"
) | Set-Content -Path $planFile -Encoding utf8

foreach ($s in $selected) {
  "RUNNER=$($s.FullName)" | Add-Content -Path $planFile -Encoding utf8
}

Add-Type -AssemblyName System.IO.Compression.FileSystem

$runResults = @()
$firstFailLog = ""

foreach ($s in $selected) {
  $label = [System.IO.Path]::GetFileNameWithoutExtension($s.Name)
  $log = Join-Path $pf ("20_quickrun_logs_{0}.txt" -f $label)

  $cmd = $null
  switch -Regex ($s.Name) {
    '^phase16_19_multi_instance_concurrency_runner\.ps1$' {
      $cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$($s.FullName)`" -Instances 7 -AutoCloseMs 2000 -StartStaggerMs 50 -TimeoutSec 30"
      break
    }
    '^phase16_20_present_fail_matrix_runner\.ps1$' {
      $cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$($s.FullName)`" -Policies `"0,1,2`" -FailEvery 10 -CyclesPerPolicy 2 -AutoCloseMs 1500 -TimeoutSec 30"
      break
    }
    '^phase16_21_quit_policy_latency_runner\.ps1$' {
      $cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$($s.FullName)`" -Cycles 5 -AutoCloseMs 600000 -TimeoutSec 30 -FailEvery 1 -MaxConsec 3 -MaxLinesToQuit 300 -MaxLinesToExit 1200"
      break
    }
    default {
      $cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$($s.FullName)`""
    }
  }

  $raw = Invoke-Expression $cmd 2>&1
  $txt = ($raw | Out-String)
  $txt | Set-Content -Path $log -Encoding utf8

  $pfOut = ([regex]::Match($txt, 'PF=(.+)')).Groups[1].Value.Trim()
  $zipOut = ([regex]::Match($txt, 'ZIP=(.+)')).Groups[1].Value.Trim()
  $gateOut = ([regex]::Match($txt, 'GATE=(PASS|FAIL)')).Groups[1].Value.Trim()
  if (-not $gateOut) { $gateOut = "UNKNOWN" }

  $pfOk = $false
  $zipOk = $false
  $zipExists = $false
  $zipHasGate = $false
  $reasons = @()

  if ($pfOut -and $pfOut.StartsWith((Join-Path $root "_proof") + "\")) { $pfOk = $true } else { $reasons += "pf_outside__proof" }
  if ($zipOut -and $zipOut.StartsWith((Join-Path $root "_proof") + "\")) { $zipOk = $true } else { $reasons += "zip_outside__proof" }

  if ($zipOut -and (Test-Path $zipOut)) {
    $zipExists = $true
    try {
      $z = [System.IO.Compression.ZipFile]::OpenRead($zipOut)
      try {
        $zipHasGate = @($z.Entries | Where-Object { $_.FullName -match '98_gate_.*\.txt$' }).Count -gt 0
      }
      finally {
        $z.Dispose()
      }
      if (-not $zipHasGate) { $reasons += "zip_missing_gate_file" }
    }
    catch {
      $reasons += "zip_read_error"
    }
  } else {
    $reasons += "zip_missing"
  }

  $passed = ($pfOk -and $zipOk -and $zipExists -and $zipHasGate)
  if (-not $passed -and -not $firstFailLog) {
    $firstFailLog = $log
  }

  $runResults += [pscustomobject]@{
    runner = $s.Name
    pf = $pfOut
    zip = $zipOut
    gate = $gateOut
    pf_under_proof = [int]$pfOk
    zip_under_proof = [int]$zipOk
    zip_exists = [int]$zipExists
    zip_contains_gate = [int]$zipHasGate
    reasons = ($reasons -join ',')
    log = $log
  }
}

$runResults | Export-Csv -Path $runsCsv -NoTypeInformation -Encoding utf8

$failingRun = $runResults | Where-Object { ($_.pf_under_proof -ne 1) -or ($_.zip_under_proof -ne 1) -or ($_.zip_exists -ne 1) -or ($_.zip_contains_gate -ne 1) } | Select-Object -First 1
$overall = if (($offenders.Count -eq 0) -and (-not $failingRun)) { "PASS" } else { "FAIL" }

@(
  "PHASE=16.23",
  "TS=$(Get-Date -Format o)",
  "GATE=$overall",
  "offender_count=$($offenders.Count)",
  "failing_runner=" + ($(if($failingRun){$failingRun.runner}else{"none"})),
  "reason=" + ($(if($failingRun){$failingRun.reasons}else{""})),
  "failing_log=" + ($(if($failingRun){$failingRun.log}else{""}))
) | Set-Content -Path $gateFile -Encoding utf8

$zip = Join-Path $proofRoot ((Split-Path $pf -Leaf) + ".zip")
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
if (-not $copied) { throw "Failed to stage files for zip." }

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

if (-not (Test-Path $zip)) { throw "Zip missing after creation." }

"PF=$pf"
"ZIP=$zip"
"GATE=$overall"

if ($overall -ne "PASS") {
  Get-Content -LiteralPath $gateFile
  if ($firstFailLog -and (Test-Path $firstFailLog)) {
    Get-Content -LiteralPath $firstFailLog -Tail 120
  }
  exit 2
}

exit 0
