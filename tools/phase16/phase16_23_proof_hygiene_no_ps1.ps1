param(
  [switch]$IgnoreOld
)

$ErrorActionPreference = 'Stop'

Set-Location "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime"
if ((Get-Location).Path -ne "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime") {
  "hey stupid Fucker, wrong window again"
  exit 1
}

$root = (Get-Location).Path
$proofRoot = Join-Path $root "_proof"

function Assert-ProofRootLock([string]$rootPath, [string]$proofPath) {
  $expected = "$rootPath\_proof"
  if ($proofPath -ne $expected) {
    throw "HARD_FAIL: proof root mismatch. expected=$expected actual=$proofPath"
  }
  if (-not (Test-Path -LiteralPath $proofPath)) {
    throw "HARD_FAIL: proof root missing: $proofPath"
  }
  if ($proofPath -match [regex]::Escape('${root}_proof')) {
    throw "HARD_FAIL: invalid proof root pattern ${root}_proof detected: $proofPath"
  }
}

function Assert-NoBadProofPattern([string]$value, [string]$label) {
  if (-not $value) { return }
  if ($value -match [regex]::Escape('${root}_proof')) {
    throw "HARD_FAIL: $label contains ${root}_proof pattern: $value"
  }
}

Assert-ProofRootLock -rootPath $root -proofPath $proofRoot

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$pf = Join-Path $proofRoot ("phase16_23_proof_hygiene_no_ps1_" + $ts)
New-Item -ItemType Directory -Path $pf -Force | Out-Null

@(
  "PHASE=16.23.hygiene",
  "TS=$(Get-Date -Format o)",
  "ROOT=$root",
  "PROOF_ROOT=$proofRoot",
  "RULE=no_ps1_under__proof"
) | Set-Content -Path (Join-Path $pf "00_context.txt") -Encoding utf8

git status *> (Join-Path $pf "01_status.txt")
git log -1 *> (Join-Path $pf "02_head.txt")

$ps1Files = @()
if (Test-Path $proofRoot) {
  $ps1Files = @(Get-ChildItem -LiteralPath $proofRoot -Recurse -File -Filter "*.ps1" -ErrorAction SilentlyContinue | Sort-Object FullName)
  if ($IgnoreOld) {
    $oldPrefix = (Join-Path $proofRoot "Old") + "\"
    $ps1Files = @($ps1Files | Where-Object { -not ($_.FullName.StartsWith($oldPrefix, [System.StringComparison]::OrdinalIgnoreCase)) })
  }
}

$findingsPath = Join-Path $pf "20_ps1_offenders_active.txt"
if ($ps1Files.Count -gt 0) {
  $ps1Files.FullName | Set-Content -Path $findingsPath -Encoding utf8
}
else {
  "none" | Set-Content -Path $findingsPath -Encoding utf8
}

$overall = if ($ps1Files.Count -eq 0) { "PASS" } else { "FAIL" }
$reason = if ($ps1Files.Count -eq 0) { "" } else { "ps1_found_under__proof,count=$($ps1Files.Count)" }

@(
  "PHASE=16.23.hygiene",
  "TS=$(Get-Date -Format o)",
  "TotalPs1UnderProofActive=$($ps1Files.Count)",
  "OffendersList=$findingsPath",
  "GATE=$overall",
  "reason=$reason"
) | Set-Content -Path (Join-Path $pf "98_gate_16_23_hygiene.txt") -Encoding utf8

$zip = Join-Path $proofRoot ((Split-Path $pf -Leaf) + ".zip")
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf "*") -DestinationPath $zip -Force

$gatePath = Join-Path $pf "98_gate_16_23_hygiene.txt"
$pfPrint = Split-Path -Parent $gatePath
$zipPrint = Join-Path (Split-Path $pfPrint -Parent) ((Split-Path $pfPrint -Leaf) + ".zip")
$gateTextPrint = Get-Content -Raw -LiteralPath $gatePath -ErrorAction SilentlyContinue
$gatePrint = ([regex]::Match($gateTextPrint, '(?im)^\s*GATE\s*=\s*(PASS|FAIL)\s*$')).Groups[1].Value.Trim()
if (-not $gatePrint) { $gatePrint = $overall }

Assert-NoBadProofPattern -value $pfPrint -label 'PF'
Assert-NoBadProofPattern -value $zipPrint -label 'ZIP'

$rootProofPrefix = "$root\_proof\"
$badPrintedPaths = $false
if (-not ($pfPrint -and $pfPrint.StartsWith($rootProofPrefix, [System.StringComparison]::OrdinalIgnoreCase))) { $badPrintedPaths = $true }
if (-not ($zipPrint -and $zipPrint.StartsWith($rootProofPrefix, [System.StringComparison]::OrdinalIgnoreCase))) { $badPrintedPaths = $true }
if ($badPrintedPaths) {
  @(
    "PHASE=16.23.hygiene",
    "TS=$(Get-Date -Format o)",
    "TotalPs1UnderProofActive=$($ps1Files.Count)",
    "OffendersList=$findingsPath",
    "GATE=FAIL",
    "reason=bad_printed_paths"
  ) | Set-Content -Path $gatePath -Encoding utf8
  $overall = "FAIL"
  $gatePrint = "FAIL"
}

"PF=$pfPrint"
"ZIP=$zipPrint"
"GATE=$gatePrint"

if ($overall -ne "PASS") {
  Get-Content -LiteralPath $gatePath
  Get-Content -LiteralPath $findingsPath -TotalCount 30
  exit 2
}

exit 0
