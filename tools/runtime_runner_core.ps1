param([string]$phase,[string]$tag)

$repo = (Get-Location).Path
$expected = "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime"

if ($repo -ne $expected) {
	"hey stupid Fucker, wrong window again"
	exit 1
}

$proofRoot = Join-Path $repo "_proof"
if (-not (Test-Path -LiteralPath $proofRoot)) {
	throw "missing_proof_root"
}

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$pf = Join-Path $proofRoot ("phase$phase" + "_" + $tag + "_" + $ts)
New-Item -ItemType Directory -Force -Path $pf | Out-Null

$zip = $pf + ".zip"

$pfResolved = (Resolve-Path -LiteralPath $pf).Path
$proofResolved = (Resolve-Path -LiteralPath $proofRoot).Path

if (-not $pfResolved.StartsWith($proofResolved + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
	throw "invalid_proof_root"
}

$pfResolved
$zip
