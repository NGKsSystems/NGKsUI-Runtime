[CmdletBinding()]
param(
	[string]$ProofFolder,
	[int]$NumeratorEvery,
	[int]$DenominatorEvery,
	[string]$WorkspaceRoot = "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime"
)

$ErrorActionPreference = 'Stop'

Set-Location $WorkspaceRoot
if ((Get-Location).Path -ne $WorkspaceRoot) {
	"hey stupid Fucker, wrong window again"
	exit 1
}

if ([string]::IsNullOrWhiteSpace($ProofFolder)) {
	$ProofFolder = Get-ChildItem .\_proof -Directory -Filter "phase*" -ErrorAction SilentlyContinue |
		Sort-Object LastWriteTime -Descending |
		Where-Object {
			(Test-Path (Join-Path $_.FullName '98_gate.txt')) -and
			((Get-ChildItem $_.FullName -File -Filter 'run_p1_every*_max*_*.txt' -ErrorAction SilentlyContinue | Select-Object -First 1) -ne $null) -and
			((Get-ChildItem $_.FullName -File -Filter 'run_p2_every*_max*_*.txt' -ErrorAction SilentlyContinue | Select-Object -First 1) -ne $null)
		} |
		Select-Object -First 1 -ExpandProperty FullName
}

if ([string]::IsNullOrWhiteSpace($ProofFolder)) {
	throw "No proof folder provided/found."
}

if (-not (Test-Path $ProofFolder)) {
	throw "Proof folder not found: $ProofFolder"
}

function Count-Matches([string]$Path, [string]$Pattern) {
	if (-not (Test-Path $Path)) { return 0 }
	return @((Select-String -Path $Path -Pattern $Pattern -ErrorAction SilentlyContinue)).Count
}

$runLogs = Get-ChildItem $ProofFolder -File -Filter "run_*.txt" |
	Where-Object { $_.Name -match '^run_(p[12])_every(\d+)_max\d+_.*\.txt$' }

if (-not $runLogs -or $runLogs.Count -eq 0) {
	throw "No cadence run logs found in $ProofFolder"
}

$entries = foreach ($file in $runLogs) {
	$null = $file.Name -match '^run_(p[12])_every(\d+)_max\d+_.*\.txt$'
	[pscustomobject]@{
		policy = $Matches[1]
		every = [int]$Matches[2]
		count = Count-Matches $file.FullName 'INJECT_PRESENT_FAIL'
		log = $file.FullName
	}
}

$allCadences = $entries.every | Sort-Object -Unique
if ($allCadences.Count -lt 2) {
	throw "Need at least two cadence values to compare. Found: $($allCadences -join ',')"
}

if (-not $PSBoundParameters.ContainsKey('NumeratorEvery')) {
	$NumeratorEvery = ($allCadences | Sort-Object | Select-Object -First 1)
}
if (-not $PSBoundParameters.ContainsKey('DenominatorEvery')) {
	$DenominatorEvery = ($allCadences | Sort-Object -Descending | Select-Object -First 1)
}

if ($NumeratorEvery -eq $DenominatorEvery) {
	throw "NumeratorEvery and DenominatorEvery must differ."
}

$phaseTag = (Split-Path $ProofFolder -Leaf)
if ($phaseTag -match '^(phase\d+_\d+)') {
	$compareTag = "$($Matches[1])_compare"
} else {
	$compareTag = 'phase_compare'
}

$policies = @('p1', 'p2')
$rows = @()
foreach ($p in $policies) {
	$num = $entries | Where-Object { $_.policy -eq $p -and $_.every -eq $NumeratorEvery } | Select-Object -First 1
	$den = $entries | Where-Object { $_.policy -eq $p -and $_.every -eq $DenominatorEvery } | Select-Object -First 1
	if ($null -eq $num -or $null -eq $den) {
		throw "Missing cadence pair for $p (every$NumeratorEvery/every$DenominatorEvery)."
	}
	if ($den.count -le 0) {
		throw "Invalid denominator injection count for $p every$DenominatorEvery."
	}
	$observed = [math]::Round(($num.count / [double]$den.count), 4)
	$expected = [math]::Round(($DenominatorEvery / [double]$NumeratorEvery), 4)
	$deltaPct = [math]::Round((100.0 * (($observed - $expected) / $expected)), 2)

	$rows += [pscustomobject]@{
		policy = $p
		numerator_every = $NumeratorEvery
		denominator_every = $DenominatorEvery
		numerator_inject = $num.count
		denominator_inject = $den.count
		observed_ratio = $observed
		expected_ratio = $expected
		delta_pct = $deltaPct
	}
}

$txtPath = Join-Path $ProofFolder ($compareTag + '.txt')
$jsonPath = Join-Path $ProofFolder ($compareTag + '.json')

@(
	"PHASE=$compareTag",
	"TS=$(Get-Date -Format o)",
	"PF=$ProofFolder",
	"",
	"[PAIR]",
	"numerator_every=$NumeratorEvery",
	"denominator_every=$DenominatorEvery",
	"expected_ratio_every$NumeratorEvery_over_every$DenominatorEvery=$([math]::Round(($DenominatorEvery/[double]$NumeratorEvery),4))",
	"",
	"[COUNTS]",
	"p1_every$NumeratorEvery=$(($rows | Where-Object policy -eq 'p1').numerator_inject)",
	"p1_every$DenominatorEvery=$(($rows | Where-Object policy -eq 'p1').denominator_inject)",
	"p2_every$NumeratorEvery=$(($rows | Where-Object policy -eq 'p2').numerator_inject)",
	"p2_every$DenominatorEvery=$(($rows | Where-Object policy -eq 'p2').denominator_inject)",
	"",
	"[RATIOS]",
	"p1_observed_ratio=$(($rows | Where-Object policy -eq 'p1').observed_ratio)",
	"p2_observed_ratio=$(($rows | Where-Object policy -eq 'p2').observed_ratio)",
	"p1_delta_vs_expected_pct=$(($rows | Where-Object policy -eq 'p1').delta_pct)",
	"p2_delta_vs_expected_pct=$(($rows | Where-Object policy -eq 'p2').delta_pct)"
) | Out-File $txtPath -Encoding utf8

([pscustomobject]@{
	phase = $compareTag
	ts = (Get-Date -Format o)
	proof_folder = $ProofFolder
	numerator_every = $NumeratorEvery
	denominator_every = $DenominatorEvery
	results = $rows
} | ConvertTo-Json -Depth 6) | Out-File $jsonPath -Encoding utf8

$zip = Join-Path (Split-Path $ProofFolder -Parent) ((Split-Path $ProofFolder -Leaf) + '_with_compare.zip')
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $ProofFolder '*') -DestinationPath $zip
$zipPointer = Join-Path $ProofFolder '92_zip_with_compare_path.txt'
"ZIP_WITH_COMPARE=$zip" | Out-File $zipPointer -Encoding utf8

"PROOF_FOLDER=$ProofFolder"
"COMPARE_TXT=$txtPath"
"COMPARE_JSON=$jsonPath"
"ZIP_WITH_COMPARE=$zip"
