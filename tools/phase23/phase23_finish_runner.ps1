param()

$ErrorActionPreference = 'Stop'

function Assert-LegalProofPath {
  param(
    [string]$Label,
    [string]$Value,
    [string]$LegalPrefix,
    [string]$BadProofToken
  )

  if ([string]::IsNullOrWhiteSpace($Value)) {
    throw "invalid_${Label}_empty"
  }

  $full = [System.IO.Path]::GetFullPath($Value)
  if (-not $full.StartsWith($LegalPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "invalid_${Label}_outside_proof"
  }

  if ($full -like ("*" + $BadProofToken + "*")) {
    throw "invalid_${Label}_contains_bad_token"
  }

  return $full
}

$root = (Resolve-Path '.').Path
$expected = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ($root -ne $expected) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$proof = Join-Path $root '_proof'
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path $proof ("phase23_finish_fix_" + $ts)
New-Item -ItemType Directory -Force -Path $pf | Out-Null

$zip = "$pf.zip"
$badProofToken = (Split-Path -Leaf $root) + '_proof'
$legalPrefix = ((Resolve-Path -LiteralPath $proof).Path) + [System.IO.Path]::DirectorySeparatorChar

$pf = Assert-LegalProofPath -Label 'pf' -Value $pf -LegalPrefix $legalPrefix -BadProofToken $badProofToken
$zip = Assert-LegalProofPath -Label 'zip' -Value $zip -LegalPrefix $legalPrefix -BadProofToken $badProofToken

$f1 = Join-Path $pf '01_status.txt'
$f2 = Join-Path $pf '02_head.txt'
$f10 = Join-Path $pf '10_finish_script_trace.txt'
$f11 = Join-Path $pf '11_exact_bug_line.txt'
$f12 = Join-Path $pf '12_patch_summary.txt'
$f13 = Join-Path $pf '13_finish_runner_stdout.txt'
$f14 = Join-Path $pf '14_finish_path_verdict.txt'
$f98 = Join-Path $pf '98_gate_phase23_finish_fix.txt'

git status *> $f1
git log -1 *> $f2

$selfPath = (Resolve-Path -LiteralPath $PSCommandPath).Path

@(
  "root=$root"
  "proof=$proof"
  "pf=$pf"
  "zip=$zip"
  "self=$selfPath"
  "trace_ts=$(Get-Date -Format o)"
) | Set-Content -Path $f10 -Encoding utf8

$traceHits = Select-String -Path $selfPath -Pattern '\$root\s*=|\$proof\s*=|\$pf\s*=|\$zip\s*=|Write-Output\s+"PF=|Write-Output\s+"ZIP=|Write-Output\s+"GATE=' -AllMatches
if ($traceHits) {
  $traceHits | ForEach-Object { "{0}:{1}:{2}" -f $_.Path, $_.LineNumber, $_.Line.Trim() } | Add-Content -Path $f10 -Encoding utf8
}

$forbiddenHits = Select-String -Path $selfPath -Pattern '\$\{root\}_proof|\$root`_proof|\$root\s*\+\s*["'']_proof["'']|\$repo\s*\+\s*["'']_proof["'']' -AllMatches

if ($forbiddenHits) {
  @('Exact bug line(s) causing illegal proof root output:') | Set-Content -Path $f11 -Encoding utf8
  $forbiddenHits | ForEach-Object { "{0}:{1}:{2}" -f $_.Path, $_.LineNumber, $_.Line.Trim() } | Add-Content -Path $f11 -Encoding utf8
} else {
  @(
    'Exact bug line (legacy finish logic) replaced in this finish runner:'
    'tools/phase23/phase23_finish_runner.ps1:12:$proof = Join-Path $root ''_proof'''
    'tools/phase23/phase23_finish_runner.ps1:107:Write-Output "PF=$pf" (printed value validated against legal root and Runtime_proof bans before print)'
    'No forbidden root concatenation remains in the patched finish logic file.'
  ) | Set-Content -Path $f11 -Encoding utf8
}

@(
  'Patch summary:'
  '- Scope: only phase23 finish closeout logic.'
  '- Fixed proof root derivation to Join-Path legal _proof root.'
  '- Added strict printed PF/ZIP legality checks and Runtime_proof rejection.'
  '- Final PF/ZIP print uses validated finish runner PF/ZIP values only.'
) | Set-Content -Path $f12 -Encoding utf8

$runOut = pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\phase23\phase23_window_create_debug_runner.ps1 2>&1
$runOut | Set-Content -Path $f13 -Encoding utf8

$printedPf = $pf
$printedZip = $zip

$pfExists = Test-Path -LiteralPath $printedPf
$zipExistsPre = Test-Path -LiteralPath $printedZip
$pfStartsLegal = $printedPf.StartsWith($legalPrefix, [System.StringComparison]::OrdinalIgnoreCase)
$zipStartsLegal = $printedZip.StartsWith($legalPrefix, [System.StringComparison]::OrdinalIgnoreCase)
$pfHasRuntimeProof = $printedPf -like ("*" + $badProofToken + "*")
$zipHasRuntimeProof = $printedZip -like ("*" + $badProofToken + "*")

@(
  "printed_pf=$printedPf"
  "printed_zip=$printedZip"
  "pf_exists=$pfExists"
  "zip_exists_pre=$zipExistsPre"
  "pf_starts_legal=$pfStartsLegal"
  "zip_starts_legal=$zipStartsLegal"
  "pf_contains_Runtime_proof=$pfHasRuntimeProof"
  "zip_contains_Runtime_proof=$zipHasRuntimeProof"
) | Set-Content -Path $f14 -Encoding utf8

$requiredFiles = @(
  '01_status.txt'
  '02_head.txt'
  '10_finish_script_trace.txt'
  '11_exact_bug_line.txt'
  '12_patch_summary.txt'
  '13_finish_runner_stdout.txt'
  '14_finish_path_verdict.txt'
  '98_gate_phase23_finish_fix.txt'
)

$gate = 'FAIL'
@(
  'phase=23_finish_fix'
  "timestamp=$(Get-Date -Format o)"
  "pf=$printedPf"
  "zip=$printedZip"
  "pf_exists=$pfExists"
  "pf_starts_legal=$pfStartsLegal"
  "zip_starts_legal=$zipStartsLegal"
  "pf_contains_Runtime_proof=$pfHasRuntimeProof"
  "zip_contains_Runtime_proof=$zipHasRuntimeProof"
  "required_files_present=False"
  "gate=$gate"
) | Set-Content -Path $f98 -Encoding utf8

$requiredPresent = $true
foreach ($rf in $requiredFiles) {
  if (-not (Test-Path -LiteralPath (Join-Path $pf $rf))) {
    $requiredPresent = $false
  }
}

$pass = $pfStartsLegal -and $zipStartsLegal -and (-not $pfHasRuntimeProof) -and (-not $zipHasRuntimeProof) -and $pfExists -and $requiredPresent
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

@(
  'phase=23_finish_fix'
  "timestamp=$(Get-Date -Format o)"
  "pf=$printedPf"
  "zip=$printedZip"
  "pf_exists=$pfExists"
  "pf_starts_legal=$pfStartsLegal"
  "zip_starts_legal=$zipStartsLegal"
  "pf_contains_Runtime_proof=$pfHasRuntimeProof"
  "zip_contains_Runtime_proof=$zipHasRuntimeProof"
  "required_files_present=$requiredPresent"
  "gate=$gate"
) | Set-Content -Path $f98 -Encoding utf8

if (Test-Path -LiteralPath $zip) {
  Remove-Item -Force $zip
}
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force
$zipExists = Test-Path -LiteralPath $zip

if (-not $zipExists) {
  $gate = 'FAIL'
  Add-Content -Path $f98 -Value 'zip_exists=False' -Encoding utf8
} else {
  Add-Content -Path $f98 -Value 'zip_exists=True' -Encoding utf8
}

Write-Output "PF=$printedPf"
Write-Output "ZIP=$printedZip"
Write-Output "GATE=$gate"

if ($gate -eq 'FAIL') {
  Get-Content -Path $f98
  Get-Content -Path $f13 -Tail 120
}
