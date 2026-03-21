$ErrorActionPreference = 'Stop'
Set-Location "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime"

$pf = "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime\_proof\phase54b_integrity_custody_20260321_111647"
$targets = @('widget_sandbox', 'win32_sandbox', 'sandbox_app', 'loop_tests')

Add-Type -AssemblyName System.IO.Compression.FileSystem

foreach ($t in $targets) {
	$bo = Join-Path $pf ("20_build_output_" + $t + ".txt")
	if (-not (Test-Path -LiteralPath $bo)) { continue }

	$proofLine = Get-Content -LiteralPath $bo | Select-String -Pattern 'PROOF_ZIP=' | Select-Object -Last 1
	$out = @("target=$t")

	if (-not $proofLine) {
		$out += 'PROOF_ZIP_NOT_FOUND'
		$out | Set-Content -LiteralPath (Join-Path $pf ("24_zip_evidence_" + $t + ".txt")) -Encoding UTF8
		continue
	}

	$zipPath = ($proofLine.Line -replace '^.*PROOF_ZIP=', '').Trim()
	$out += ("proof_zip=" + $zipPath)
	if (-not (Test-Path -LiteralPath $zipPath)) {
		$out += 'ZIP_MISSING'
		$out | Set-Content -LiteralPath (Join-Path $pf ("24_zip_evidence_" + $t + ".txt")) -Encoding UTF8
		continue
	}

	$zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
	try {
		foreach ($name in @('stdout.txt', 'stderr.txt', 'RUN_SUMMARY.md', 'command_line.txt')) {
			$entry = $zip.Entries | Where-Object { $_.FullName -eq $name } | Select-Object -First 1
			if ($entry) {
				$out += ("---" + $name + "---")
				$sr = New-Object IO.StreamReader($entry.Open())
				try {
					$out += $sr.ReadToEnd()
				}
				finally {
					$sr.Dispose()
				}
			}
		}
	}
	finally {
		$zip.Dispose()
	}

	$out | Set-Content -LiteralPath (Join-Path $pf ("24_zip_evidence_" + $t + ".txt")) -Encoding UTF8
}

"OK"
