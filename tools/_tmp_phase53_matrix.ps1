$ErrorActionPreference = "Stop"
$runtimeRoot = "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime"
$pf = "C:\Users\suppo\Desktop\NGKsSystems\NGKsDevFabEco\_proof\phase53_2_runtime_seal_finalize_20260320_083532"
$exe = Join-Path $runtimeRoot "build\debug\bin\widget_sandbox.exe"
$launcher = Join-Path $runtimeRoot "tools\run_widget_sandbox.ps1"
$art111 = Join-Path $runtimeRoot "control_plane\111_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline.json"
$bak111 = "$art111.phase53bak"
Set-Location $runtimeRoot

function Write-RunLog {
  param([string]$Path,[string]$Label,[string]$Output,[int]$ExitCode)
  $text = @(
    "LABEL=$Label",
    "UTC=$(Get-Date -AsUTC -Format o)",
    "EXIT=$ExitCode",
    "---OUTPUT---",
    $Output
  ) -join "`r`n"
  Set-Content -LiteralPath $Path -Value $text -Encoding UTF8
}

if (-not (Test-Path -LiteralPath $exe)) { throw "Missing executable: $exe" }

$out = (& $exe "--auto-close-ms=1200" 2>&1 | Out-String)
$code = $LASTEXITCODE
Write-RunLog -Path (Join-Path $pf "10_gate_clean.txt") -Label "direct_native_clean" -Output $out -ExitCode $code

Copy-Item -LiteralPath $art111 -Destination $bak111 -Force
try {
  Add-Content -LiteralPath $art111 -Value "`n " -Encoding UTF8
  $out = (& $exe "--auto-close-ms=1200" 2>&1 | Out-String)
  $code = $LASTEXITCODE
  Write-RunLog -Path (Join-Path $pf "11_gate_tampered.txt") -Label "direct_native_tampered" -Output $out -ExitCode $code
}
finally {
  if (Test-Path -LiteralPath $bak111) { Move-Item -LiteralPath $bak111 -Destination $art111 -Force }
}

$out = (& pwsh -NoProfile -ExecutionPolicy Bypass -File $launcher -Config Debug -PassArgs "--auto-close-ms=1200" 2>&1 | Out-String)
$code = $LASTEXITCODE
Write-RunLog -Path (Join-Path $pf "20_script_clean.txt") -Label "script_clean" -Output $out -ExitCode $code

Copy-Item -LiteralPath $art111 -Destination $bak111 -Force
try {
  Add-Content -LiteralPath $art111 -Value "`n " -Encoding UTF8
  $out = (& pwsh -NoProfile -ExecutionPolicy Bypass -File $launcher -Config Debug -PassArgs "--auto-close-ms=1200" 2>&1 | Out-String)
  $code = $LASTEXITCODE
  Write-RunLog -Path (Join-Path $pf "21_script_tampered.txt") -Label "script_tampered" -Output $out -ExitCode $code
}
finally {
  if (Test-Path -LiteralPath $bak111) { Move-Item -LiteralPath $bak111 -Destination $art111 -Force }
}

Write-Host "RUN_MATRIX_DONE"
