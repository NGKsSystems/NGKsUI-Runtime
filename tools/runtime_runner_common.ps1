param([string]$phase,[string]$tag)

$repo = (Resolve-Path ".").Path
if ($repo -ne 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime') { 'hey stupid Fucker, wrong window again'; exit 1 }

$proof = Join-Path $repo "_proof"
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$pf = Join-Path $proof ("phase$phase" + "_" + $tag + "_" + $ts)

New-Item -ItemType Directory -Force -Path $pf | Out-Null

$proofResolved = (Resolve-Path -LiteralPath $proof).Path
$pfResolved = (Resolve-Path -LiteralPath $pf).Path
$legalPrefix = $proofResolved + [System.IO.Path]::DirectorySeparatorChar
if (-not $pfResolved.StartsWith($legalPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
	throw 'invalid_proof_root'
}

$zip = "$pfResolved.zip"

$pfResolved; $zipFD