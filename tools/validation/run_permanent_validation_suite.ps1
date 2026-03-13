param(
  [string]$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Set-Location $Root
if ((Get-Location).Path -ne $Root) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$results = [ordered]@{}

pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\runtime_contract_guard.ps1
$results.build_contract_guard = ($LASTEXITCODE -eq 0)
if (-not $results.build_contract_guard) {
  Write-Output 'run_permanent_validation_suite=FAIL'
  exit 1
}

pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\validation\visual_baseline_contract_check.ps1
$results.visual_baseline_contract = ($LASTEXITCODE -eq 0)
if (-not $results.visual_baseline_contract) {
  Write-Output 'run_permanent_validation_suite=FAIL'
  exit 1
}

$baselineOutput = pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\phase40_28\phase40_28_baseline_lock_runner.ps1
$results.baseline_lock = ($LASTEXITCODE -eq 0)
$results.baseline_output = ($baselineOutput | Out-String)
if (-not $results.baseline_lock) {
  Write-Output 'run_permanent_validation_suite=FAIL'
  exit 1
}

Write-Output 'run_permanent_validation_suite=PASS'
Write-Output ('build_contract_guard=' + $results.build_contract_guard)
Write-Output ('visual_baseline_contract=' + $results.visual_baseline_contract)
Write-Output ('baseline_lock=' + $results.baseline_lock)
