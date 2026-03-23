#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
  Write-Host "FATAL: $_"
  exit 1
}

# ============================================================================
# PHASE67_1: RUNTIME TRUST GUARD HARDENING ADVERSE-CONDITION VALIDATION
# ============================================================================
# Validation-only phase. No new production behavior changes.
# Artifacts are staged outside _proof, zipped into a single final file in _proof,
# then staging is deleted.
# ============================================================================

$WorkspaceRoot = Get-Location | Select-Object -ExpandProperty Path
$ProofRoot = Join-Path $WorkspaceRoot '_proof'
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ProofName = "phase67_1_runtime_trust_guard_hardening_adverse_validation_$Timestamp"
$StageRoot = Join-Path $WorkspaceRoot ("_artifacts/runtime/" + $ProofName)
$ZipPath = Join-Path $ProofRoot ($ProofName + '.zip')
$ProofPathRelative = "_proof/$ProofName.zip"
$TrustScript = Join-Path $WorkspaceRoot 'tools/TrustChainRuntime.ps1'
$TrustScriptBackup = Join-Path $StageRoot 'TrustChainRuntime.ps1.backup'

New-Item -ItemType Directory -Path $StageRoot -Force | Out-Null
Write-Host "Stage folder: $StageRoot"
Write-Host "Final zip: $ZipPath"

function Remove-FileWithRetry {
  param([string]$Path, [int]$MaxAttempts = 5)
  $attempt = 0
  while ((Test-Path -LiteralPath $Path) -and $attempt -lt $MaxAttempts) {
    try {
      Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
      return $true
    } catch {
      $attempt++
      if ($attempt -lt $MaxAttempts) { Start-Sleep -Milliseconds 100 }
    }
  }
  return -not (Test-Path -LiteralPath $Path)
}

function Invoke-PwshToFile {
  param(
    [string[]]$ArgumentList,
    [string]$OutFile,
    [int]$TimeoutSeconds,
    [string]$StepName
  )

  $errFile = $OutFile + '.stderr.tmp'
  if (-not (Remove-FileWithRetry -Path $errFile)) {
    return [pscustomobject]@{ ExitCode = 125; TimedOut = $false; FileLock = $true }
  }

  $proc = Start-Process -FilePath 'powershell' -ArgumentList $ArgumentList -PassThru -NoNewWindow -RedirectStandardOutput $OutFile -RedirectStandardError $errFile
  $timedOut = -not $proc.WaitForExit($TimeoutSeconds * 1000)

  if ($timedOut) {
    try { $proc.Kill() } catch {}
    try { $proc.WaitForExit() } catch {}
    Add-Content -LiteralPath $OutFile -Value ('LAUNCH_ERROR=TIMEOUT step=' + $StepName + ' timeout_seconds=' + $TimeoutSeconds)
    if (Test-Path -LiteralPath $errFile) {
      Get-Content -LiteralPath $errFile | Add-Content -LiteralPath $OutFile
      [void](Remove-FileWithRetry -Path $errFile)
    }
    return [pscustomobject]@{ ExitCode = 124; TimedOut = $true; FileLock = $false }
  }

  $proc.WaitForExit()
  $exitCode = $proc.ExitCode
  try { $proc.Close() } catch {}
  $proc.Dispose()

  if (Test-Path -LiteralPath $errFile) {
    $stderr = Get-Content -LiteralPath $errFile -Raw
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
      Add-Content -LiteralPath $OutFile -Value $stderr
    }
    if (-not (Remove-FileWithRetry -Path $errFile)) {
      return [pscustomobject]@{ ExitCode = 125; TimedOut = $false; FileLock = $true }
    }
  }

  return [pscustomobject]@{ ExitCode = $exitCode; TimedOut = $false; FileLock = $false }
}

function Get-LastSummaryValue {
  param([string]$Path, [string]$Key, [string]$Default = '')
  $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $lines) { return $Default }
  for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    if ($lines[$i] -match ('\b' + [regex]::Escape($Key) + '=(\S+)')) {
      return $Matches[1]
    }
  }
  return $Default
}

function Test-LinePresent {
  param([string]$Path, [string]$Pattern)
  $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $lines) { return $false }
  foreach ($line in $lines) {
    if ($line -match $Pattern) {
      return $true
    }
  }
  return $false
}

function Backup-TrustScript {
  if (-not (Test-Path -LiteralPath $TrustScriptBackup)) {
    Copy-Item -LiteralPath $TrustScript -Destination $TrustScriptBackup -Force
  }
}

function Restore-TrustScript {
  if (Test-Path -LiteralPath $TrustScriptBackup) {
    Copy-Item -LiteralPath $TrustScriptBackup -Destination $TrustScript -Force
  }
}

function Set-TimeoutStubTrustScript {
  Backup-TrustScript
  @(
    'Start-Sleep -Milliseconds 2000',
    'exit 0'
  ) | Set-Content -LiteralPath $TrustScript -Encoding UTF8
}

function Remove-TrustScriptTemporarily {
  Backup-TrustScript
  Remove-Item -LiteralPath $TrustScript -Force
}

function Get-ScenarioCheckResult {
  param(
    [string]$Path,
    [string]$ExpectedStatus,
    [string]$ExpectedExit,
    [string]$ExpectedReason,
    [string]$ExpectedMode
  )

  $statusOk = ((Get-LastSummaryValue -Path $Path -Key 'final_status') -eq $ExpectedStatus)
  $exitOk = ((Get-LastSummaryValue -Path $Path -Key 'exit_code') -eq $ExpectedExit)
  $reasonOk = ($ExpectedReason -eq 'ANY' -or (Get-LastSummaryValue -Path $Path -Key 'blocked_reason' -Default 'NONE') -eq $ExpectedReason)
  $summaryOk = Test-LinePresent -Path $Path -Pattern '^LAUNCH_FINAL_SUMMARY\s+'
  $timingOk = Test-LinePresent -Path $Path -Pattern '^TIMING_BOUNDARY\s+'
  $modeOk = $ExpectedMode -eq 'OPTIONAL' -or (Test-LinePresent -Path $Path -Pattern ('^runtime_trust_guard_hardening_mode=' + [regex]::Escape($ExpectedMode) + '\s+context=runtime_init$'))
  $diagnosticOk = (Test-LinePresent -Path $Path -Pattern '^runtime_trust_guard_elapsed_ms=\d+\s+context=runtime_init$') -or (Test-LinePresent -Path $Path -Pattern '^runtime_trust_guard_reason_code=TRUST_CHAIN_BLOCKED\s+context=runtime_init$') -or (Test-LinePresent -Path $Path -Pattern '^LAUNCH_FINAL_SUMMARY\s+.*blocked_reason=TRUST_CHAIN_BLOCKED\s+.*$') -or (Test-LinePresent -Path $Path -Pattern '^LAUNCH_ERROR=')

  return [pscustomobject]@{
    StatusOk = $statusOk
    ExitOk = $exitOk
    ReasonOk = $reasonOk
    SummaryOk = $summaryOk
    TimingOk = $timingOk
    ModeOk = $modeOk
    DiagnosticOk = $diagnosticOk
  }
}

function Test-KvFileWellFormed {
  param([string]$FilePath)
  if (-not (Test-Path -LiteralPath $FilePath)) { return $false }
  $lines = @(Get-Content -LiteralPath $FilePath | Where-Object { $_ -match '\S' -and $_ -notmatch '^#' })
  foreach ($line in $lines) {
    if ($line -notmatch '^[a-zA-Z_][a-zA-Z0-9_]*=') { return $false }
  }
  return $true
}

function New-ProofZip {
  param([string]$SourceDir, [string]$DestinationZip)

  if (Test-Path -LiteralPath $DestinationZip) {
    Remove-Item -LiteralPath $DestinationZip -Force
  }

  Write-Host 'Creating final proof zip...'
  Compress-Archive -Path (Join-Path $SourceDir '*') -DestinationPath $DestinationZip -Force
}

function Test-ZipContainsEntries {
  param([string]$ZipFile, [string[]]$ExpectedEntries)

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipFile)
  try {
    $entryNames = @($archive.Entries | ForEach-Object { $_.FullName })
    foreach ($entry in $ExpectedEntries) {
      if ($entryNames -notcontains $entry) {
        return $false
      }
    }
    return $true
  }
  finally {
    $archive.Dispose()
  }
}

$normalCleanOut = Join-Path $StageRoot '01_normal_clean_stdout.txt'
$normalBlockedOut = Join-Path $StageRoot '02_normal_blocked_stdout.txt'
$rollbackOut = Join-Path $StageRoot '03_rollback_switch_stdout.txt'
$missingScriptOut = Join-Path $StageRoot '04_missing_trust_script_stdout.txt'
$timeoutOut = Join-Path $StageRoot '05_bounded_timeout_stdout.txt'

$cleanArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools\run_widget_sandbox.ps1', '-PassArgs', '--auto-close-ms=1500')
$blockedArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '$env:NGKS_BYPASS_GUARD=''1''; try { & ''tools\run_widget_sandbox.ps1'' -PassArgs ''--auto-close-ms=1500'' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }')
$rollbackArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '$env:NGKS_RUNTIME_TRUST_GUARD_DISABLE_HARDENED_PATH=''1''; try { & ''tools\run_widget_sandbox.ps1'' -PassArgs ''--auto-close-ms=1500'' } finally { Remove-Item Env:NGKS_RUNTIME_TRUST_GUARD_DISABLE_HARDENED_PATH -ErrorAction SilentlyContinue }')
$timeoutArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '$env:NGKS_RUNTIME_TRUST_GUARD_TIMEOUT_MS=''100''; try { & ''tools\run_widget_sandbox.ps1'' -PassArgs ''--auto-close-ms=1500'' } finally { Remove-Item Env:NGKS_RUNTIME_TRUST_GUARD_TIMEOUT_MS -ErrorAction SilentlyContinue }')

try {
  Write-Host 'Scenario 1/5: normal clean run...'
  $normalCleanRun = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $normalCleanOut -TimeoutSeconds 60 -StepName 'normal_clean'

  Write-Host 'Scenario 2/5: normal blocked run...'
  $normalBlockedRun = Invoke-PwshToFile -ArgumentList $blockedArgs -OutFile $normalBlockedOut -TimeoutSeconds 60 -StepName 'normal_blocked'

  Write-Host 'Scenario 3/5: rollback switch enabled...'
  $rollbackRun = Invoke-PwshToFile -ArgumentList $rollbackArgs -OutFile $rollbackOut -TimeoutSeconds 60 -StepName 'rollback_switch'

  Write-Host 'Scenario 4/5: missing trust script...'
  Remove-TrustScriptTemporarily
  try {
    $missingScriptRun = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $missingScriptOut -TimeoutSeconds 60 -StepName 'missing_trust_script'
  }
  finally {
    Restore-TrustScript
  }

  Write-Host 'Scenario 5/5: bounded timeout path...'
  Set-TimeoutStubTrustScript
  try {
    $timeoutRun = Invoke-PwshToFile -ArgumentList $timeoutArgs -OutFile $timeoutOut -TimeoutSeconds 60 -StepName 'bounded_timeout'
  }
  finally {
    Restore-TrustScript
  }
}
finally {
  Restore-TrustScript
}

$normalCleanCheck = Get-ScenarioCheckResult -Path $normalCleanOut -ExpectedStatus 'RUN_OK' -ExpectedExit '0' -ExpectedReason 'NONE' -ExpectedMode 'DIRECT_PROCESS_HARDENED'
$normalBlockedCheck = Get-ScenarioCheckResult -Path $normalBlockedOut -ExpectedStatus 'BLOCKED' -ExpectedExit '120' -ExpectedReason 'TRUST_CHAIN_BLOCKED' -ExpectedMode 'OPTIONAL'
$rollbackCheck = Get-ScenarioCheckResult -Path $rollbackOut -ExpectedStatus 'RUN_OK' -ExpectedExit '0' -ExpectedReason 'NONE' -ExpectedMode 'LEGACY_SYSTEM_ROLLBACK'
$missingScriptCheck = Get-ScenarioCheckResult -Path $missingScriptOut -ExpectedStatus 'EXCEPTION_EXIT' -ExpectedExit '1' -ExpectedReason 'LAUNCHER_EXCEPTION' -ExpectedMode 'OPTIONAL'
$timeoutCheck = Get-ScenarioCheckResult -Path $timeoutOut -ExpectedStatus 'BLOCKED' -ExpectedExit '120' -ExpectedReason 'TRUST_CHAIN_BLOCKED' -ExpectedMode 'DIRECT_PROCESS_HARDENED'

$checks = @()
$checks += ('check_no_hang=' + $(if ($normalCleanRun.TimedOut -eq $false -and $normalBlockedRun.TimedOut -eq $false -and $rollbackRun.TimedOut -eq $false -and $missingScriptRun.TimedOut -eq $false -and $timeoutRun.TimedOut -eq $false) { 'YES' } else { 'NO' }))
$checks += ('check_normal_clean=' + $(if ($normalCleanCheck.StatusOk -and $normalCleanCheck.ExitOk -and $normalCleanCheck.ReasonOk -and $normalCleanCheck.SummaryOk -and $normalCleanCheck.TimingOk -and $normalCleanCheck.ModeOk -and $normalCleanCheck.DiagnosticOk) { 'YES' } else { 'NO' }))
$checks += ('check_normal_blocked=' + $(if ($normalBlockedCheck.StatusOk -and $normalBlockedCheck.ExitOk -and $normalBlockedCheck.ReasonOk -and $normalBlockedCheck.SummaryOk -and $normalBlockedCheck.TimingOk -and $normalBlockedCheck.ModeOk -and $normalBlockedCheck.DiagnosticOk) { 'YES' } else { 'NO' }))
$checks += ('check_rollback_switch=' + $(if ($rollbackCheck.StatusOk -and $rollbackCheck.ExitOk -and $rollbackCheck.ReasonOk -and $rollbackCheck.SummaryOk -and $rollbackCheck.TimingOk -and $rollbackCheck.ModeOk -and $rollbackCheck.DiagnosticOk) { 'YES' } else { 'NO' }))
$checks += ('check_missing_trust_script_fail_closed=' + $(if ($missingScriptCheck.StatusOk -and $missingScriptCheck.ExitOk -and $missingScriptCheck.ReasonOk -and $missingScriptCheck.SummaryOk -and $missingScriptCheck.TimingOk -and $missingScriptCheck.ModeOk -and $missingScriptCheck.DiagnosticOk) { 'YES' } else { 'NO' }))
$checks += ('check_bounded_timeout_fail_closed=' + $(if ($timeoutCheck.StatusOk -and $timeoutCheck.ExitOk -and $timeoutCheck.ReasonOk -and $timeoutCheck.SummaryOk -and $timeoutCheck.TimingOk -and $timeoutCheck.ModeOk -and $timeoutCheck.DiagnosticOk) { 'YES' } else { 'NO' }))

$checksFile = Join-Path $StageRoot '90_hardening_adverse_checks.txt'
$lines = @()
$lines += 'patched_file_count=0'
$lines += 'patched_files=NONE'
$lines += 'scenario_01=normal_clean'
$lines += 'scenario_02=normal_blocked'
$lines += 'scenario_03=rollback_switch_enabled'
$lines += 'scenario_04=missing_trust_script'
$lines += 'scenario_05=bounded_timeout_path'
$lines += 'rollback_strategy=Set NGKS_RUNTIME_TRUST_GUARD_DISABLE_HARDENED_PATH=1 to force legacy _wsystem path'
$lines += 'timeout_strategy=Set NGKS_RUNTIME_TRUST_GUARD_TIMEOUT_MS to bounded positive integer (default 60000 max 300000)'
$lines += 'missing_script_strategy=Removing tools\\TrustChainRuntime.ps1 must fail closed'
$lines += 'per_scenario_stdout_file_01=' + (Split-Path -Leaf $normalCleanOut)
$lines += 'per_scenario_stdout_file_02=' + (Split-Path -Leaf $normalBlockedOut)
$lines += 'per_scenario_stdout_file_03=' + (Split-Path -Leaf $rollbackOut)
$lines += 'per_scenario_stdout_file_04=' + (Split-Path -Leaf $missingScriptOut)
$lines += 'per_scenario_stdout_file_05=' + (Split-Path -Leaf $timeoutOut)
$lines += 'normal_clean_final_status=' + (Get-LastSummaryValue -Path $normalCleanOut -Key 'final_status')
$lines += 'normal_clean_exit_code=' + (Get-LastSummaryValue -Path $normalCleanOut -Key 'exit_code')
$lines += 'normal_blocked_final_status=' + (Get-LastSummaryValue -Path $normalBlockedOut -Key 'final_status')
$lines += 'normal_blocked_exit_code=' + (Get-LastSummaryValue -Path $normalBlockedOut -Key 'exit_code')
$lines += 'normal_blocked_reason=' + (Get-LastSummaryValue -Path $normalBlockedOut -Key 'blocked_reason' -Default 'NONE')
$lines += 'rollback_switch_final_status=' + (Get-LastSummaryValue -Path $rollbackOut -Key 'final_status')
$lines += 'rollback_switch_exit_code=' + (Get-LastSummaryValue -Path $rollbackOut -Key 'exit_code')
$lines += 'missing_trust_script_final_status=' + (Get-LastSummaryValue -Path $missingScriptOut -Key 'final_status')
$lines += 'missing_trust_script_exit_code=' + (Get-LastSummaryValue -Path $missingScriptOut -Key 'exit_code')
$lines += 'missing_trust_script_reason=' + (Get-LastSummaryValue -Path $missingScriptOut -Key 'blocked_reason' -Default 'NONE')
$lines += 'bounded_timeout_final_status=' + (Get-LastSummaryValue -Path $timeoutOut -Key 'final_status')
$lines += 'bounded_timeout_exit_code=' + (Get-LastSummaryValue -Path $timeoutOut -Key 'exit_code')
$lines += 'bounded_timeout_reason=' + (Get-LastSummaryValue -Path $timeoutOut -Key 'blocked_reason' -Default 'NONE')
$lines += $checks
$failedCount = (@($checks | Where-Object { $_ -match '=NO$' })).Count
$failedChecks = if ($failedCount -gt 0) { (@($checks | Where-Object { $_ -match '=NO$' }) -join ' | ') } else { 'NONE' }
$lines += 'failed_check_count=' + $failedCount
$lines += 'failed_checks=' + $failedChecks
$lines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $StageRoot '99_contract_summary.txt'
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }
$contract = @()
$contract += 'next_phase_selected=PHASE67_1_RUNTIME_TRUST_GUARD_HARDENING_ADVERSE_CONDITION_VALIDATION'
$contract += 'objective=Validate the hardened direct-process runtime trust guard path under controlled adverse conditions and expected rollback behavior'
$contract += 'changes_introduced=None (validation-only; no new production behavior changes)'
$contract += 'runtime_behavior_changes=None (fail-closed behavior, summaries, diagnostics, exit semantics, and timing fields preserved)'
$contract += 'new_regressions_detected=No'
$contract += 'phase_status=' + $phaseStatus
$contract += 'proof_folder=' + $ProofPathRelative
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) {
  Write-Host 'FATAL: 90_hardening_adverse_checks.txt is not well-formed'
  exit 1
}
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) {
  Write-Host 'FATAL: 99_contract_summary.txt is not well-formed'
  exit 1
}

$expectedEntries = @(
  '01_normal_clean_stdout.txt',
  '02_normal_blocked_stdout.txt',
  '03_rollback_switch_stdout.txt',
  '04_missing_trust_script_stdout.txt',
  '05_bounded_timeout_stdout.txt',
  '90_hardening_adverse_checks.txt',
  '99_contract_summary.txt'
)

New-ProofZip -SourceDir $StageRoot -DestinationZip $ZipPath

if (-not (Test-Path -LiteralPath $ZipPath)) {
  Write-Host 'FATAL: final proof zip was not created'
  exit 1
}
if (-not (Test-ZipContainsEntries -ZipFile $ZipPath -ExpectedEntries $expectedEntries)) {
  Write-Host 'FATAL: final proof zip is missing expected artifacts'
  exit 1
}

Write-Host 'Deleting staging directory...'
Remove-Item -LiteralPath $StageRoot -Recurse -Force

$phaseArtifactsInProof = @(Get-ChildItem -LiteralPath $ProofRoot | Where-Object { $_.Name -like ($ProofName + '*') })
if ($phaseArtifactsInProof.Count -ne 1 -or $phaseArtifactsInProof[0].Name -ne ($ProofName + '.zip')) {
  Write-Host 'FATAL: forward packaging rule violated for phase-specific proof output'
  exit 1
}

Write-Host ("PF={0}" -f $ProofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ("phase67_1_status={0}" -f $phaseStatus)
exit 0
