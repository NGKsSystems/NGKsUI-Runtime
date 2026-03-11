param(
  [Parameter(Mandatory=$true)][string]$PhaseTag,   # e.g. "16_24" or "16_20"
  [string]$ProofSubdir = "_proof"
)

$ErrorActionPreference="Stop"
$root = (Get-Location).Path
$proof = Join-Path $root $ProofSubdir

# Accept "16.24" or "16_24"
$norm = $PhaseTag.Replace(".","_")
$gateName = "98_gate_$norm.txt"

$gate = Get-ChildItem -LiteralPath $proof -Recurse -Force -File |
  Where-Object { $_.Name -eq $gateName } |
  Sort-Object LastWriteTimeUtc -Descending |
  Select-Object -First 1

if (-not $gate) { throw "No $gateName found under $proof" }

$pf = Split-Path $gate.FullName -Parent
$zip = (Get-ChildItem -LiteralPath $proof -Recurse -Force -File |
  Where-Object { $_.Name -eq ((Split-Path $pf -Leaf) + ".zip") } |
  Sort-Object LastWriteTimeUtc -Descending |
  Select-Object -First 1).FullName

"PF=$pf"
if ($zip) { "ZIP=$zip" } else { "ZIP=<not found>" }
Get-Content -LiteralPath $gate.FullName -Tail 8