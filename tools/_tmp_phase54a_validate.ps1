Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $root

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path $root ("_proof\phase54a_runtime_enforcement_validation_" + $stamp)
New-Item -ItemType Directory -Path $pf -Force | Out-Null

$before = @(Get-ChildItem -LiteralPath (Join-Path $root '_proof') -Directory -Filter 'runtime_validation_*' |
    Sort-Object LastWriteTimeUtc |
    Select-Object -ExpandProperty FullName)

$forensic = Join-Path $pf 'forensics_runtime.log'
$env:NGK_FORENSICS_LOG = $forensic
$validOut = & powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_widget_sandbox.ps1 -Config Debug -PassArgs @('--sandbox-extension', '--extension-visual-baseline') 2>&1
$validCode = $LASTEXITCODE
$validOut | Set-Content -LiteralPath (Join-Path $pf '10_valid_launch_output.txt') -Encoding UTF8
Remove-Item Env:NGK_FORENSICS_LOG -ErrorAction SilentlyContinue

$env:NGKS_BYPASS_GUARD = '1'
$invalidOut = & powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_widget_sandbox.ps1 -Config Debug -PassArgs @('--sandbox-extension', '--extension-visual-baseline') 2>&1
$invalidCode = $LASTEXITCODE
$invalidOut | Set-Content -LiteralPath (Join-Path $pf '20_invalid_launch_output.txt') -Encoding UTF8
Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue

$after = @(Get-ChildItem -LiteralPath (Join-Path $root '_proof') -Directory -Filter 'runtime_validation_*' |
    Sort-Object LastWriteTimeUtc |
    Select-Object -ExpandProperty FullName)
$new = @($after | Where-Object { $before -notcontains $_ })
$new | Set-Content -LiteralPath (Join-Path $pf '30_new_runtime_validation_dirs.txt') -Encoding UTF8

foreach ($d in $new) {
    $name = Split-Path $d -Leaf
    $statusPath = Join-Path $d '01_status.txt'
    $vectorsPath = Join-Path $d '04_detection_vectors.txt'
    if (Test-Path -LiteralPath $statusPath) {
        Copy-Item -LiteralPath $statusPath -Destination (Join-Path $pf ($name + '_01_status.txt')) -Force
    }
    if (Test-Path -LiteralPath $vectorsPath) {
        Copy-Item -LiteralPath $vectorsPath -Destination (Join-Path $pf ($name + '_04_detection_vectors.txt')) -Force
    }
}

$summary = @(
    ('VALID_EXIT=' + $validCode),
    ('INVALID_EXIT=' + $invalidCode),
    ('FORENSICS_LOG=' + $forensic),
    ('NEW_RUNTIME_VALIDATION_DIR_COUNT=' + $new.Count),
    '---NEW_DIRS---'
) + $new
$summary | Set-Content -LiteralPath (Join-Path $pf '99_phase54a_summary.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) {
    Remove-Item -LiteralPath $zip -Force
}
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -CompressionLevel Optimal

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('VALID_EXIT=' + $validCode)
Write-Output ('INVALID_EXIT=' + $invalidCode)
