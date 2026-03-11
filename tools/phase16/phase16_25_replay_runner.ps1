param(
  [switch]$ForceReplay,
  [int]$FreshWindowMinutes = 90
)

$ErrorActionPreference = 'Stop'

Set-Location "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime"
if ((Get-Location).Path -ne "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime") {
  "hey stupid Fucker, wrong window again"
  exit 1
}

$root = (Get-Location).Path
$proofRoot = "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime\_proof"
$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File ".\tools\runtime_runner_core.ps1" -phase 16_25 -tag "replay"
$pf = $paths[0].Trim()
$zipOut = $paths[1].Trim()
$expectedProof = $proofRoot

function Compute-FileSha256([string]$path) {
  return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-CompositeFolderHash([string]$folder) {
  $items = Get-ChildItem -LiteralPath $folder -Recurse -File | Sort-Object FullName
  $lines = @()
  foreach ($i in $items) {
    $rel = $i.FullName.Substring($folder.Length).TrimStart('\\').Replace('\\','/')
    $h = Compute-FileSha256 $i.FullName
    $lines += ("{0}|{1}" -f $rel, $h)
  }
  $joined = ($lines -join "`n")
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($joined)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($bytes)
    return ([BitConverter]::ToString($hash).Replace('-', '').ToLowerInvariant())
  }
  finally {
    $sha.Dispose()
  }
}

function Normalize-RelPath([string]$p) {
  return ([regex]::Replace($p.Replace('\\','/'), '\d{8}_\d{6}', '<TS>'))
}

function Is-TimestampedFile([string]$path) {
  return [regex]::IsMatch($path, '\d{8}_\d{6}|__ngk_vs|_stage_zip|phase16_\d+_')
}

function Has-TimestampedContent([string]$filePath) {
  try {
    $text = Get-Content -Raw -LiteralPath $filePath -ErrorAction Stop
    return [regex]::IsMatch($text, '\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}|\b\d{8}_\d{6}\b')
  }
  catch {
    return $false
  }
}

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

function Is-VolatileProofFile([string]$relativePath) {
  $p = $relativePath.Replace('\\','/')
  $leaf = Split-Path -Leaf $p
  if ($leaf -eq '00_context.txt') { return $true }
  if ($leaf -eq '10_suite_plan.txt') { return $true }
  if ($leaf -eq '20_build.txt') { return $true }
  if ($leaf -eq '40_subrun_index.csv') { return $true }
  if ($leaf -eq '98_gate_16_24.txt') { return $true }
  if ($leaf -eq '30_replay_stdout.txt') { return $true }
  if ($leaf -eq '31_replay_stderr.txt') { return $true }
  if ($leaf -eq '30_stdout.txt') { return $true }
  if ($leaf -eq '31_stderr.txt') { return $true }
  return $false
}

function Write-ZipFromPf([string]$srcPf, [string]$zipPath) {
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
  if (-not $copied) { throw "Failed to stage proof folder for zip." }

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
  if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
  if (-not $zipped -or -not (Test-Path $zipPath)) { throw "Failed to create replay zip." }
}

function Quote-Arg([string]$value) {
  if ($null -eq $value) { return '""' }
  $escaped = $value.Replace('"', '""')
  return '"' + $escaped + '"'
}

# Context / baseline
$existing24 = Get-ChildItem -Path $proofRoot -Directory -Filter "phase16_24_suite_bundle_*" -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending
$prev24 = $existing24 | Select-Object -First 1

@(
  "PHASE=16.25",
  "TS=$(Get-Date -Format o)",
  "ROOT=$root",
  "PREV24_PF=" + ($(if($prev24){$prev24.FullName}else{"<none>"}))
) | Set-Content -Path (Join-Path $pf "00_context.txt") -Encoding utf8

# Execute 16.24 replay
$runner24 = Join-Path (Join-Path (Join-Path $root 'tools') 'phase16') 'phase16_24_suite_bundle_runner.ps1'
if (-not (Test-Path $runner24)) {
  $runner24 = Join-Path (Join-Path (Join-Path $root 'tests') 'phase16') 'phase16_24_suite_bundle_runner.ps1'
}
if ($runner24 -and (Is-UnderPath -candidatePath $runner24 -basePath $proofRoot)) {
  throw "HARD_FAIL: runner resolved inside _proof: $runner24"
}
if (-not (Test-Path $runner24)) {
  @(
    "PHASE=16.25",
    "TS=$(Get-Date -Format o)",
    "TotalPlanned=1",
    "TotalExecuted=0",
    "GATE=FAIL",
    "failed_phase=16.24",
    "reason=missing_16_24_runner"
  ) | Set-Content -Path (Join-Path $pf "98_gate_16_25.txt") -Encoding utf8

  Write-ZipFromPf -srcPf $pf -zipPath $zipOut
  "PF=$pf"
  "ZIP=$zipOut"
  "GATE=FAIL"
  Get-Content -LiteralPath (Join-Path $pf "98_gate_16_25.txt")
  exit 2
}

$runOut = Join-Path $pf "30_replay_stdout.txt"
$runErr = Join-Path $pf "31_replay_stderr.txt"
$replayStartUtc = (Get-Date).ToUniversalTime()

$replayPf = ""
$replayZip = ""
$replayGate = ""

$latest24GateBefore = Get-ChildItem -LiteralPath $proofRoot -Recurse -File -Filter '98_gate_16_24.txt' -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTimeUtc -Descending |
  Select-Object -First 1

$reuseRecent24 = $false
if (-not $ForceReplay -and $latest24GateBefore) {
  $ageMin = ((Get-Date).ToUniversalTime() - $latest24GateBefore.LastWriteTimeUtc).TotalMinutes
  if ($ageMin -ge 0 -and $ageMin -le $FreshWindowMinutes) {
    $reuseRecent24 = $true
    $replayPf = Split-Path -Parent $latest24GateBefore.FullName
    $zipName = (Split-Path -Leaf $replayPf) + '.zip'
    $zipObj = Get-ChildItem -LiteralPath $proofRoot -Recurse -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -eq $zipName } |
      Sort-Object LastWriteTimeUtc -Descending |
      Select-Object -First 1
    if ($zipObj) { $replayZip = $zipObj.FullName }

    $gateTail = Get-Content -LiteralPath $latest24GateBefore.FullName -Tail 12 -ErrorAction SilentlyContinue
    $gateLine = $gateTail | Where-Object { $_ -match '^\s*GATE\s*=\s*(PASS|FAIL)\s*$' } | Select-Object -First 1
    if ($gateLine) {
      $replayGate = ([regex]::Match($gateLine, '(?i)GATE\s*=\s*(PASS|FAIL)').Groups[1].Value).ToUpperInvariant()
    }
  }
}

if (-not $reuseRecent24) {
  $replayArgString = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Quote-Arg ([System.IO.Path]::GetFullPath($runner24)))) -join ' '
  Start-Process -FilePath "powershell" -ArgumentList $replayArgString -Wait -PassThru -NoNewWindow -RedirectStandardOutput $runOut -RedirectStandardError $runErr | Out-Null
}

$combined = ""
if (Test-Path $runOut) { $combined += (Get-Content -Raw -LiteralPath $runOut -ErrorAction SilentlyContinue) + "`n" }
if (Test-Path $runErr) { $combined += (Get-Content -Raw -LiteralPath $runErr -ErrorAction SilentlyContinue) + "`n" }

$lineMatches = [regex]::Matches($combined, '(?im)^\s*(PF|ZIP|GATE)\s*=\s*(.+?)\s*$')
foreach ($m in $lineMatches) {
  $k = $m.Groups[1].Value.ToUpperInvariant()
  $v = $m.Groups[2].Value.Trim()
  if ($k -eq 'PF' -and -not $replayPf) { $replayPf = $v; continue }
  if ($k -eq 'ZIP' -and -not $replayZip) { $replayZip = $v; continue }
  if ($k -eq 'GATE' -and -not $replayGate) { $replayGate = $v; continue }
}

if ($replayPf) {
  $m = [regex]::Match($replayPf, '(?i)[A-Z]:\\.+')
  if ($m.Success) { $replayPf = $m.Value.Trim() }
  $replayPf = ($replayPf -replace "[`r`n]", "").Trim()
}
if ($replayZip) {
  $m = [regex]::Match($replayZip, '(?i)[A-Z]:\\.+')
  if ($m.Success) { $replayZip = $m.Value.Trim() }
  $replayZip = ($replayZip -replace "[`r`n]", "").Trim()
}

if (-not $replayPf) {
  $m = [regex]::Match($combined, '(?im)PF\s*=\s*([A-Z]:\\[^\r\n]+)')
  if ($m.Success) { $replayPf = $m.Groups[1].Value.Trim() }
}
if (-not $replayZip) {
  $m = [regex]::Match($combined, '(?im)ZIP\s*=\s*([A-Z]:\\[^\r\n]+)')
  if ($m.Success) { $replayZip = $m.Groups[1].Value.Trim() }
}
if ($replayGate) { $replayGate = $replayGate.Trim().ToUpperInvariant() }
if (-not $replayGate) { $replayGate = "UNKNOWN" }

# Prefer authoritative on-disk gate artifacts over wrapped console output parsing.
$latest24Gate = Get-ChildItem -LiteralPath $proofRoot -Recurse -File -Filter '98_gate_16_24.txt' -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTimeUtc -Descending |
  Select-Object -First 1

if ($latest24Gate -and $latest24Gate.LastWriteTimeUtc -ge $replayStartUtc.AddMinutes(-5)) {
  $replayPf = Split-Path -Parent $latest24Gate.FullName
  $zipName = (Split-Path -Leaf $replayPf) + '.zip'
  $zipObj = Get-ChildItem -LiteralPath $proofRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq $zipName } |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
  if ($zipObj) { $replayZip = $zipObj.FullName }

  $gateTail = Get-Content -LiteralPath $latest24Gate.FullName -Tail 12 -ErrorAction SilentlyContinue
  $gateLine = $gateTail | Where-Object { $_ -match '^\s*GATE\s*=\s*(PASS|FAIL)\s*$' } | Select-Object -First 1
  if ($gateLine) {
    $replayGate = ([regex]::Match($gateLine, '(?i)GATE\s*=\s*(PASS|FAIL)').Groups[1].Value).ToUpperInvariant()
  }
}

$reasons = @()

$expectedSubruns = 10
$gate24Path = ""
if ($latest24Gate -and (Test-Path $latest24Gate.FullName)) {
  $gate24Path = $latest24Gate.FullName
}
elseif ($replayPf -and (Test-Path $replayPf)) {
  $gateCandidate = Join-Path $replayPf '98_gate_16_24.txt'
  if (Test-Path $gateCandidate) { $gate24Path = $gateCandidate }
}
if ($gate24Path) {
  try {
    $gate24Text = Get-Content -Raw -LiteralPath $gate24Path -ErrorAction Stop
    $mPlanned = [regex]::Match($gate24Text, '(?im)^\s*TotalPlanned\s*=\s*(\d+)\s*$')
    if ($mPlanned.Success) {
      $expectedSubruns = [int]$mPlanned.Groups[1].Value
    }
  }
  catch {
  }
}

$proofBaseFull = [System.IO.Path]::GetFullPath($proofRoot).TrimEnd('\','/')
$proofPrefix = $proofBaseFull + '\'

$replayPfUnderProof = $false
if ($replayPf) {
  try {
    $rp = [System.IO.Path]::GetFullPath($replayPf).TrimEnd('\','/')
    $replayPfUnderProof = $rp.Equals($proofBaseFull, [System.StringComparison]::OrdinalIgnoreCase) -or
                          $rp.StartsWith($proofPrefix, [System.StringComparison]::OrdinalIgnoreCase)
  }
  catch {
    $replayPfUnderProof = $false
  }
}

$replayZipUnderProof = $false
if ($replayZip) {
  try {
    $rz = [System.IO.Path]::GetFullPath($replayZip).TrimEnd('\','/')
    $replayZipUnderProof = $rz.Equals($proofBaseFull, [System.StringComparison]::OrdinalIgnoreCase) -or
                           $rz.StartsWith($proofPrefix, [System.StringComparison]::OrdinalIgnoreCase)
  }
  catch {
    $replayZipUnderProof = $false
  }
}

if (-not $replayPf -or -not (Test-Path $replayPf)) { $reasons += "missing_replay_pf" }
if (-not $replayZip -or -not (Test-Path $replayZip)) { $reasons += "missing_replay_zip" }
if ($replayGate -ne "PASS") { $reasons += "replay_gate=$replayGate" }
if ($replayPf -and -not $replayPfUnderProof) { $reasons += "replay_pf_outside__proof" }
if ($replayZip -and -not $replayZipUnderProof) { $reasons += "replay_zip_outside__proof" }

$subrunCount = 0
$subFailCount = 0
if ($replayPf -and (Test-Path $replayPf)) {
  $idx = Join-Path $replayPf "40_subrun_index.csv"
  if (Test-Path $idx) {
    $rows = Import-Csv -LiteralPath $idx
    $subrunCount = $rows.Count
    $subFailCount = @($rows | Where-Object { $_.gate -ne 'PASS' }).Count
  }
}
if ($subrunCount -ne $expectedSubruns) {
  $reasons += "subrun_count=$subrunCount"
  $reasons += "expected_subrun_count=$expectedSubruns"
}
if ($subFailCount -ne 0) { $reasons += "subrun_fail_count=$subFailCount" }

# Hash generation + compare
$replayFolderComposite = ""
$replayZipHash = ""
$prevFolderComposite = ""
$prevZipHash = ""

if ($replayPf -and (Test-Path $replayPf)) {
  $replayFolderComposite = Get-CompositeFolderHash $replayPf
}
if ($replayZip -and (Test-Path $replayZip)) {
  $replayZipHash = Compute-FileSha256 $replayZip
}

$prevZip = ""
if ($prev24) {
  $prevZipCandidate = Join-Path $proofRoot ((Split-Path $prev24.FullName -Leaf) + ".zip")
  if (Test-Path $prevZipCandidate) { $prevZip = $prevZipCandidate }
}

if ($prev24) {
  $prevFolderComposite = Get-CompositeFolderHash $prev24.FullName
}
if ($prevZip) {
  $prevZipHash = Compute-FileSha256 $prevZip
}

@(
  "TS=$(Get-Date -Format o)",
  "REPLAY_PF=$replayPf",
  "REPLAY_PF_UNDER_PROOF=$replayPfUnderProof",
  "REPLAY_FOLDER_COMPOSITE_SHA256=$replayFolderComposite",
  "REPLAY_ZIP=$replayZip",
  "REPLAY_ZIP_UNDER_PROOF=$replayZipUnderProof",
  "REPLAY_ZIP_SHA256=$replayZipHash"
) | Set-Content -Path (Join-Path $pf "10_replay_hashes.txt") -Encoding utf8

@(
  "TS=$(Get-Date -Format o)",
  "PREV_PF=" + ($(if($prev24){$prev24.FullName}else{"<none>"})),
  "PREV_FOLDER_COMPOSITE_SHA256=$prevFolderComposite",
  "PREV_ZIP=$prevZip",
  "PREV_ZIP_SHA256=$prevZipHash"
) | Set-Content -Path (Join-Path $pf "20_prev_hashes.txt") -Encoding utf8

$timestampMismatchOnly = $true
if ($prev24 -and $replayPf -and (Test-Path $prev24.FullName) -and (Test-Path $replayPf)) {
  $prevFiles = Get-ChildItem -LiteralPath $prev24.FullName -Recurse -File
  $newFiles = Get-ChildItem -LiteralPath $replayPf -Recurse -File

  $prevMap = @{}
  foreach ($f in $prevFiles) {
    $rel = $f.FullName.Substring($prev24.FullName.Length).TrimStart('\\')
    $key = Normalize-RelPath $rel
    if (-not $prevMap.ContainsKey($key)) { $prevMap[$key] = $f.FullName }
  }
  $newMap = @{}
  foreach ($f in $newFiles) {
    $rel = $f.FullName.Substring($replayPf.Length).TrimStart('\\')
    $key = Normalize-RelPath $rel
    if (-not $newMap.ContainsKey($key)) { $newMap[$key] = $f.FullName }
  }

  $allKeys = @($prevMap.Keys + $newMap.Keys | Sort-Object -Unique)
  foreach ($k in $allKeys) {
    if (-not $prevMap.ContainsKey($k) -or -not $newMap.ContainsKey($k)) {
      if (-not (Is-TimestampedFile $k)) {
        $reasons += "structural_mismatch:$k"
        $timestampMismatchOnly = $false
      }
      continue
    }

    $ph = Compute-FileSha256 $prevMap[$k]
    $nh = Compute-FileSha256 $newMap[$k]
    if ($ph -ne $nh) {
      $allowed = (Is-TimestampedFile $k) -or
                 (Is-VolatileProofFile $k) -or
                 (Has-TimestampedContent $prevMap[$k]) -or
                 (Has-TimestampedContent $newMap[$k])
      if (-not $allowed) {
        $reasons += "non_timestamp_hash_mismatch:$k"
        $timestampMismatchOnly = $false
      }
    }
  }
}

if (-not $timestampMismatchOnly) {
  if (-not ($reasons -contains "determinism_violation")) { $reasons += "determinism_violation" }
}

$overall = if ($reasons.Count -eq 0) { "PASS" } else { "FAIL" }

@(
  "PHASE=16.25",
  "TS=$(Get-Date -Format o)",
  "TotalPlanned=1",
  "TotalExecuted=1",
  "GATE=$overall",
  "failed_phase=" + ($(if($overall -eq 'FAIL'){'16.24'}else{'none'})),
  "reason=" + ($(if($reasons.Count -gt 0){($reasons -join ',')}else{''}))
) | Set-Content -Path (Join-Path $pf "98_gate_16_25.txt") -Encoding utf8

Write-ZipFromPf -srcPf $pf -zipPath $zipOut

$gate25Path = Join-Path $pf "98_gate_16_25.txt"
$gateFileScan = Get-ChildItem -LiteralPath $proofRoot -Recurse -Force -File |
  Where-Object { $_.Name -eq "98_gate_16_25.txt" } |
  Sort-Object LastWriteTimeUtc -Descending |
  Select-Object -First 1

if (-not $gateFileScan) { throw "missing_gate_file" }

$pfPrint = Split-Path $gateFileScan.FullName -Parent
$zipPrint = Join-Path $proofRoot ((Split-Path $pfPrint -Leaf) + ".zip")
$gateTextPrint = Get-Content -Raw -LiteralPath $gate25Path -ErrorAction SilentlyContinue
$gatePrint = ([regex]::Match($gateTextPrint, '(?im)^\s*GATE\s*=\s*(PASS|FAIL)\s*$')).Groups[1].Value.Trim()
if (-not $gatePrint) { $gatePrint = $overall }

$rootProofPrefix = $expectedProof + "\"
$badPrintedPaths = $false
if (-not ($pfPrint -and $pfPrint.StartsWith($rootProofPrefix, [System.StringComparison]::OrdinalIgnoreCase))) { $badPrintedPaths = $true }
if (-not ($zipPrint -and $zipPrint.StartsWith($rootProofPrefix, [System.StringComparison]::OrdinalIgnoreCase))) { $badPrintedPaths = $true }
if ($badPrintedPaths) {
  @(
    "PHASE=16.25",
    "TS=$(Get-Date -Format o)",
    "TotalPlanned=1",
    "TotalExecuted=1",
    "GATE=FAIL",
    "failed_phase=16.24",
    "reason=bad_printed_paths"
  ) | Set-Content -Path $gate25Path -Encoding utf8
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
  Get-Content -LiteralPath $gate25Path
  exit 2
}

exit 0
