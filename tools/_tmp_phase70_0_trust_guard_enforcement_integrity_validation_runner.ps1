#!/usr/bin/env pwsh
param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$workspace = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
$proofDir = Join-Path $workspace '_proof'
$artifactRoot = Join-Path $workspace '_artifacts\runtime'
$phaseName = 'phase70_0_trust_guard_enforcement_integrity_validation'
$runId = Get-Date -Format 'yyyyMMdd_HHmmss'
$stageDir = Join-Path $artifactRoot ("${phaseName}_${runId}")
$zipName = "${phaseName}_${runId}.zip"
$zipPath = Join-Path $proofDir $zipName

# Enforce single-zip output for this phase.
Get-ChildItem $proofDir -Filter 'phase70_0_*' -ErrorAction SilentlyContinue | Remove-Item -Force

New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

$targets = @(
  @{ name = 'sandbox_app'; exe = (Join-Path $workspace 'build\debug\bin\sandbox_app.exe') },
  @{ name = 'loop_tests'; exe = (Join-Path $workspace 'build\debug\bin\loop_tests.exe') },
  @{ name = 'win32_sandbox'; exe = (Join-Path $workspace 'build\debug\bin\win32_sandbox.exe') }
)

# Track pre-existing runtime validation folders so we can clean new ones created by this phase.
$preRuntimeProofFolders = @{}
Get-ChildItem $proofDir -Directory -Filter 'runtime_validation_*' -ErrorAction SilentlyContinue |
  ForEach-Object { $preRuntimeProofFolders[$_.FullName.ToLowerInvariant()] = $true }

$allPass = $true
$regressions = [System.Collections.Generic.List[string]]::new()
$checks = [System.Collections.Generic.List[string]]::new()

$checks.Add('scope=trust_guard_enforcement_integrity_validation')
$checks.Add('phase=70_0')
$checks.Add('validation_mode=blocked_enforcement_only')
$checks.Add('')

function Invoke-TargetRun {
  param(
    [string]$exePath,
    [hashtable]$envOverrides
  )

  $envNames = @('NGKS_BYPASS_GUARD', 'NGKS_RUNTIME_ROOT', 'NGKS_RUNTIME_TRUST_GUARD_DISABLE_HARDENED_PATH', 'NGKS_RUNTIME_TRUST_GUARD_EXECUTION_PIPELINE_AVAILABLE')
  $saved = @{}
  foreach ($name in $envNames) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
  }

  try {
    foreach ($name in $envNames) {
      [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
    foreach ($kv in $envOverrides.GetEnumerator()) {
      [Environment]::SetEnvironmentVariable([string]$kv.Key, [string]$kv.Value, 'Process')
    }

    $output = @()
    & $exePath 2>&1 | Tee-Object -Variable output | Out-Null
    $exitCode = $LASTEXITCODE
    return [pscustomobject]@{
      ExitCode = $exitCode
      Output = @($output | ForEach-Object { [string]$_ })
    }
  }
  finally {
    foreach ($name in $envNames) {
      [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process')
    }
  }
}

foreach ($target in $targets) {
  $name = $target.name
  $exe = $target.exe

  $checks.Add("=== target=${name} ===")
  $checks.Add("exe_path=${exe}")

  if (-not (Test-Path $exe)) {
    $checks.Add('exe_exists=NO')
    $checks.Add('blocked_exit_nonzero=NO')
    $checks.Add('blocked_signal_present=NO')
    $checks.Add('trust_chain_blocked_signal_present=NO')
    $checks.Add('enforcement_status=FAIL')
    $checks.Add('')
    $regressions.Add("${name}: binary missing")
    $allPass = $false
    continue
  }

  $checks.Add('exe_exists=YES')

  # Baseline run without forced block.
  $clean = Invoke-TargetRun -exePath $exe -envOverrides @{}
  $checks.Add("clean_exit_code=$($clean.ExitCode)")

  # Forced blocked run: NGKS_BYPASS_GUARD is intentionally forbidden by TrustChainRuntime and should fail closed.
  $blocked = Invoke-TargetRun -exePath $exe -envOverrides @{ NGKS_BYPASS_GUARD = '1' }
  $blockedText = ($blocked.Output -join "`n")

  $blockedExitNonZero = ($blocked.ExitCode -ne 0)
  $blockedSignal = ($blockedText -match 'BLOCKED')
  $trustChainBlockedSignal = ($blockedText -match 'TRUST_CHAIN_BLOCKED')
  $coherentSignals = ($blockedSignal -and $trustChainBlockedSignal)

  $checks.Add("blocked_exit_code=$($blocked.ExitCode)")
  $checks.Add("blocked_exit_nonzero=$(if ($blockedExitNonZero) { 'YES' } else { 'NO' })")
  $checks.Add("blocked_signal_present=$(if ($blockedSignal) { 'YES' } else { 'NO' })")
  $checks.Add("trust_chain_blocked_signal_present=$(if ($trustChainBlockedSignal) { 'YES' } else { 'NO' })")
  $checks.Add("blocked_signals_coherent=$(if ($coherentSignals) { 'YES' } else { 'NO' })")

  if ($blockedExitNonZero -and $coherentSignals) {
    $checks.Add('enforcement_status=PASS')
  } else {
    $checks.Add('enforcement_status=FAIL')
    $allPass = $false
    $regressions.Add("${name}: blocked enforcement incomplete (exit=$($blocked.ExitCode), blocked=$blockedSignal, trust_chain_blocked=$trustChainBlockedSignal)")
  }

  $checks.Add('')
}

$checks.Add('=== enforcement_summary ===')
$checks.Add("targets_tested=$($targets.Count)")
$checks.Add("paths_with_enforcement_gaps=$($regressions.Count)")
if ($regressions.Count -gt 0) {
  foreach ($r in $regressions) {
    $checks.Add("gap=$r")
  }
}
$checks.Add("no_partial_success_masking=$(if ($allPass) { 'YES' } else { 'NO' })")
$checks.Add("failed_check_count=$(if ($allPass) { '0' } else { [string]$regressions.Count })")
$checks.Add("phase_status=$(if ($allPass) { 'PASS' } else { 'FAIL' })")

Set-Content -Path (Join-Path $stageDir '90_enforcement_checks.txt') -Value ($checks -join "`n") -NoNewline

$changesIntroduced = 'None'
$runtimeBehaviorChanges = 'None'
if (-not $allPass) {
  $changesIntroduced = 'None (validation identified enforcement gaps requiring follow-up patch)'
}

$newRegressionsDetected = if ($regressions.Count -gt 0) { 'Yes' } else { 'No' }
$phaseStatus = if ($allPass) { 'PASS' } else { 'FAIL' }

$contract = @(
  'next_phase_selected=PHASE70_0_TRUST_GUARD_ENFORCEMENT_INTEGRITY_VALIDATION',
  'objective=Validate blocked trust conditions emit non-zero exit plus coherent BLOCKED/TRUST_CHAIN_BLOCKED signals across sandbox_app, loop_tests, and win32_sandbox',
  ('changes_introduced=' + $changesIntroduced),
  ('runtime_behavior_changes=' + $runtimeBehaviorChanges),
  ('new_regressions_detected=' + $newRegressionsDetected),
  ('phase_status=' + $phaseStatus),
  ('proof_folder=_proof/' + $zipName)
)
Set-Content -Path (Join-Path $stageDir '99_contract_summary.txt') -Value ($contract -join "`n") -NoNewline

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
  foreach ($name in @('90_enforcement_checks.txt', '99_contract_summary.txt')) {
    $src = Join-Path $stageDir $name
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $src, $name) | Out-Null
  }
}
finally {
  $zip.Dispose()
}

# Remove stage folder to avoid loose artifacts.
Remove-Item -Recurse -Force $stageDir

# Remove any runtime validation proof folders created by this run so _proof contains only the phase zip output delta.
Get-ChildItem $proofDir -Directory -Filter 'runtime_validation_*' -ErrorAction SilentlyContinue |
  ForEach-Object {
    $key = $_.FullName.ToLowerInvariant()
    if (-not $preRuntimeProofFolders.ContainsKey($key)) {
      Remove-Item -Recurse -Force $_.FullName
    }
  }

Write-Host "PF=_proof/$zipName"
Write-Host "GATE=$(if ($allPass) { 'PASS' } else { 'FAIL' })"
Write-Host "phase70_0_status=$(if ($allPass) { 'PASS' } else { 'FAIL' })"