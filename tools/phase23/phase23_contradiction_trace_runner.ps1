param()

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path '.').Path
$expected = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ($root -ne $expected) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$proof = Join-Path $root '_proof'
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path $proof ('phase23_contradiction_trace_' + $ts)
New-Item -ItemType Directory -Force -Path $pf | Out-Null

$zip = "$pf.zip"

$f1 = Join-Path $pf '01_status.txt'
$f2 = Join-Path $pf '02_head.txt'
$f10 = Join-Path $pf '10_literal_command_values.txt'
$f11 = Join-Path $pf '11_runtime_values_before_runner.txt'
$f12 = Join-Path $pf '12_runner_return_values.txt'
$f13 = Join-Path $pf '13_exact_print_site.txt'
$f14 = Join-Path $pf '14_contradiction_verdict.txt'
$f98 = Join-Path $pf '98_gate_phase23_contradiction_trace.txt'

git status *> $f1
git log -1 *> $f2

@(
  "root=$root"
  "proof=$proof"
  "pf=$pf"
  "zip=$zip"
) | Set-Content -Path $f10 -Encoding utf8

$proofExpected = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime\_proof'
$proofEqualsExpected = ($proof -eq $proofExpected)
$badProofToken = (Split-Path -Leaf $root) + '_proof'
$pfContainsBadProofToken = $pf -like ("*" + $badProofToken + "*")
$zipContainsBadProofToken = $zip -like ("*" + $badProofToken + "*")

@(
  "proof_equals_expected=$proofEqualsExpected"
  "proof_expected=$proofExpected"
  "bad_proof_token=$badProofToken"
  "pf_contains_bad_proof_token=$pfContainsBadProofToken"
  "zip_contains_bad_proof_token=$zipContainsBadProofToken"
) | Set-Content -Path $f11 -Encoding utf8

$runOut = pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\phase23\phase23_window_create_debug_runner.ps1 2>&1

$runnerPfLine = $runOut | Where-Object { $_ -like 'PF=*' } | Select-Object -Last 1
$runnerZipLine = $runOut | Where-Object { $_ -like 'ZIP=*' } | Select-Object -Last 1
$runnerGateLine = $runOut | Where-Object { $_ -like 'GATE=*' } | Select-Object -Last 1

$runnerPf = if ($runnerPfLine) { $runnerPfLine.Substring(3).Trim() } else { '' }
$runnerZip = if ($runnerZipLine) { $runnerZipLine.Substring(4).Trim() } else { '' }
$runnerGate = if ($runnerGateLine) { $runnerGateLine.Substring(5).Trim() } else { '' }

@(
  "runner_pf_line=$runnerPfLine"
  "runner_zip_line=$runnerZipLine"
  "runner_gate_line=$runnerGateLine"
  "runner_pf=$runnerPf"
  "runner_zip=$runnerZip"
  "runner_gate=$runnerGate"
) | Set-Content -Path $f12 -Encoding utf8

$printHits = Select-String -Path '.\tools\phase23\phase23_window_create_debug_runner.ps1' -Pattern 'Write-Output\s+"PF=|Write-Output\s+"ZIP=|Write-Output\s+"GATE=' -AllMatches
$helperHits = Select-String -Path '.\tools\runtime_runner_common.ps1' -Pattern '\$pfResolved;\s*\$zip' -AllMatches

'runner_print_sites:' | Set-Content -Path $f13 -Encoding utf8
if ($printHits) {
  $printHits | ForEach-Object { "{0}:{1}:{2}" -f $_.Path, $_.LineNumber, $_.Line.Trim() } | Add-Content -Path $f13 -Encoding utf8
} else {
  'none' | Add-Content -Path $f13 -Encoding utf8
}

'' | Add-Content -Path $f13 -Encoding utf8
'helper_sites:' | Add-Content -Path $f13 -Encoding utf8
if ($helperHits) {
  $helperHits | ForEach-Object { "{0}:{1}:{2}" -f $_.Path, $_.LineNumber, $_.Line.Trim() } | Add-Content -Path $f13 -Encoding utf8
} else {
  'none' | Add-Content -Path $f13 -Encoding utf8
}

$legalPrefix = $proof + [System.IO.Path]::DirectorySeparatorChar

$runnerPfStartsLegal = $false
if ($runnerPf) {
  $runnerPfStartsLegal = $runnerPf.StartsWith($legalPrefix, [System.StringComparison]::OrdinalIgnoreCase)
}

$runnerZipStartsLegal = $false
if ($runnerZip) {
  $runnerZipStartsLegal = $runnerZip.StartsWith($legalPrefix, [System.StringComparison]::OrdinalIgnoreCase)
}

$runnerPfIllegal = $runnerPf -like ("*" + $badProofToken + "*")
$runnerZipIllegal = $runnerZip -like ("*" + $badProofToken + "*")

$pfPrintSite = if ($printHits) { $printHits | Where-Object { $_.Line -match 'PF=' } | Select-Object -First 1 } else { $null }
$zipPrintSite = if ($printHits) { $printHits | Where-Object { $_.Line -match 'ZIP=' } | Select-Object -First 1 } else { $null }

$hasRunnerReturned = [bool]$runnerPfLine -and [bool]$runnerZipLine
$hasExactFileLine = ($null -ne $pfPrintSite) -and ($null -ne $zipPrintSite)
$contradictionExplained = $hasRunnerReturned -and $hasExactFileLine

$illegalPath = 'none_detected'
if ($runnerPfIllegal) {
  $illegalPath = $runnerPf
} elseif ($runnerZipIllegal) {
  $illegalPath = $runnerZip
}

$whereIllegalTransformationOccurs = if ($runnerPfIllegal -or $runnerZipIllegal) {
  if ($pfPrintSite) {
    "printed at {0}:{1}" -f $pfPrintSite.Path, $pfPrintSite.LineNumber
  } else {
    'unknown_print_site'
  }
} else {
  if ($pfPrintSite) {
    "no illegal transform observed in this run; final PF/ZIP print site at {0}:{1}" -f $pfPrintSite.Path, $pfPrintSite.LineNumber
  } else {
    'no_print_site_found'
  }
}

@(
  "shell_created_pf=$pf"
  "runner_created_pf=$runnerPf"
  "final_printed_pf=$runnerPf"
  "shell_created_zip=$zip"
  "runner_created_zip=$runnerZip"
  "final_printed_zip=$runnerZip"
  "illegal_path=$illegalPath"
  "where_illegal_transformation_occurs=$whereIllegalTransformationOccurs"
  ("pf_print_site_file_line={0}:{1}" -f $(if ($pfPrintSite) { $pfPrintSite.Path } else { 'none' }), $(if ($pfPrintSite) { $pfPrintSite.LineNumber } else { 0 }))
  ("zip_print_site_file_line={0}:{1}" -f $(if ($zipPrintSite) { $zipPrintSite.Path } else { 'none' }), $(if ($zipPrintSite) { $zipPrintSite.LineNumber } else { 0 }))
  "runner_pf_starts_legal=$runnerPfStartsLegal"
  "runner_zip_starts_legal=$runnerZipStartsLegal"
) | Set-Content -Path $f14 -Encoding utf8

$required = @(
  '01_status.txt'
  '02_head.txt'
  '10_literal_command_values.txt'
  '11_runtime_values_before_runner.txt'
  '12_runner_return_values.txt'
  '13_exact_print_site.txt'
  '14_contradiction_verdict.txt'
  '98_gate_phase23_contradiction_trace.txt'
)

$requiredPresent = $true
foreach ($rf in $required) {
  if (-not (Test-Path -LiteralPath (Join-Path $pf $rf))) {
    $requiredPresent = $false
  }
}

$pass = $contradictionExplained -and $runnerPfStartsLegal -and $runnerZipStartsLegal
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

$finalPf = $runnerPf
$finalZip = $runnerZip

@(
  'phase=23_contradiction_trace'
  "timestamp=$(Get-Date -Format o)"
  "trace_pf=$pf"
  "trace_zip=$zip"
  "runner_pf=$runnerPf"
  "runner_zip=$runnerZip"
  "runner_gate=$runnerGate"
  "contradiction_explained=$contradictionExplained"
  "required_files_present=$requiredPresent"
  "runner_pf_starts_legal=$runnerPfStartsLegal"
  "runner_zip_starts_legal=$runnerZipStartsLegal"
  "gate=$gate"
) | Set-Content -Path $f98 -Encoding utf8

if (Test-Path $zip) {
  Remove-Item -Force $zip
}
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output "PF=$finalPf"
Write-Output "ZIP=$finalZip"
Write-Output "GATE=$gate"

if ($gate -eq 'FAIL') {
  Get-Content -Path $f98
  $runOut | Select-Object -Last 120
}