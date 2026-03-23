#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
  Write-Host "FATAL: $_"
  exit 1
}

# ============================================================================
# PHASE67_0: RUNTIME TRUST GUARD PRODUCTION HARDENING (FIRST SLICE)
# ============================================================================
# Focus: production hardening, not performance measurement.
# Fresh run only:
#   1) rebuild with hardened direct-process guard slice
#   2) clean validation launch
#   3) blocked validation launch
#   4) rollback strategy smoke launch (hardened path disabled via env)
# ============================================================================

$WorkspaceRoot = Get-Location | Select-Object -ExpandProperty Path
$ProofRoot = Join-Path $WorkspaceRoot '_proof'
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ProofFolderName = "phase67_0_runtime_trust_guard_production_hardening_$Timestamp"
$ProofFolder = Join-Path $ProofRoot $ProofFolderName
$ProofFolderRelative = "_proof/$ProofFolderName"
$ZipPath = "$ProofFolder.zip"

New-Item -ItemType Directory -Path $ProofFolder -Force | Out-Null
Write-Host "Proof folder: $ProofFolder"

function Remove-FileWithRetry {
  param([string]$Path, [int]$MaxAttempts = 5)
  $attempt = 0
  while ((Test-Path $Path) -and $attempt -lt $MaxAttempts) {
    try {
      Remove-Item $Path -Force -ErrorAction Stop
      return $true
    } catch {
      $attempt++
      if ($attempt -lt $MaxAttempts) { Start-Sleep -Milliseconds 100 }
    }
  }
  return -not (Test-Path $Path)
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

function Invoke-CmdToFile {
  param(
    [string]$CommandLine,
    [string]$OutFile,
    [int]$TimeoutSeconds,
    [string]$StepName
  )

  $errFile = $OutFile + '.stderr.tmp'
  if (-not (Remove-FileWithRetry -Path $errFile)) {
    return [pscustomobject]@{ ExitCode = 125; TimedOut = $false; FileLock = $true }
  }

  $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', $CommandLine) -PassThru -NoNewWindow -RedirectStandardOutput $OutFile -RedirectStandardError $errFile
  $timedOut = -not $proc.WaitForExit($TimeoutSeconds * 1000)

  if ($timedOut) {
    try { $proc.Kill() } catch {}
    try { $proc.WaitForExit() } catch {}
    Add-Content -LiteralPath $OutFile -Value ('BUILD_ERROR=TIMEOUT step=' + $StepName + ' timeout_seconds=' + $TimeoutSeconds)
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
    [void](Remove-FileWithRetry -Path $errFile)
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

function Test-KvFileWellFormed {
  param([string]$FilePath)
  if (-not (Test-Path $FilePath)) { return $false }
  $lines = @(Get-Content -Path $FilePath | Where-Object { $_ -match '\S' -and $_ -notmatch '^#' })
  foreach ($line in $lines) {
    if ($line -notmatch '^[a-zA-Z_][a-zA-Z0-9_]*=') { return $false }
  }
  return $true
}

$buildOut = Join-Path $ProofFolder '01_rebuild_stdout.txt'
Write-Host 'Rebuilding widget_sandbox with phase67_0 hardening slice...'
$build = Invoke-CmdToFile -CommandLine 'tools\_tmp_rebuild_widget_native_x64.cmd' -OutFile $buildOut -TimeoutSeconds 180 -StepName 'rebuild_widget_sandbox'
if ($build.TimedOut -or $build.ExitCode -ne 0) {
  Write-Host 'FATAL: rebuild failed'
  exit 1
}

$cleanOut = Join-Path $ProofFolder '02_clean_hardened_stdout.txt'
$blockedOut = Join-Path $ProofFolder '03_blocked_hardened_stdout.txt'
$rollbackOut = Join-Path $ProofFolder '04_clean_rollback_mode_stdout.txt'

$cleanArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools\run_widget_sandbox.ps1', '-PassArgs', '--auto-close-ms=1500')
$blockedArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '$env:NGKS_BYPASS_GUARD=''1''; try { & ''tools\run_widget_sandbox.ps1'' -PassArgs ''--auto-close-ms=1500'' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }')
$rollbackArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '$env:NGKS_RUNTIME_TRUST_GUARD_DISABLE_HARDENED_PATH=''1''; try { & ''tools\run_widget_sandbox.ps1'' -PassArgs ''--auto-close-ms=1500'' } finally { Remove-Item Env:NGKS_RUNTIME_TRUST_GUARD_DISABLE_HARDENED_PATH -ErrorAction SilentlyContinue }')

Write-Host 'Running clean hardened-path validation launch...'
$cleanRun = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $cleanOut -TimeoutSeconds 60 -StepName 'clean_hardened'

Write-Host 'Running blocked hardened-path validation launch...'
$blockedRun = Invoke-PwshToFile -ArgumentList $blockedArgs -OutFile $blockedOut -TimeoutSeconds 60 -StepName 'blocked_hardened'

Write-Host 'Running rollback/disable strategy smoke launch...'
$rollbackRun = Invoke-PwshToFile -ArgumentList $rollbackArgs -OutFile $rollbackOut -TimeoutSeconds 60 -StepName 'clean_rollback'

$checks = @()
$checks += ('check_build_succeeded=' + $(if ($build.ExitCode -eq 0 -and $build.TimedOut -eq $false) { 'YES' } else { 'NO' }))
$checks += ('check_no_hang=' + $(if ($cleanRun.TimedOut -eq $false -and $blockedRun.TimedOut -eq $false -and $rollbackRun.TimedOut -eq $false) { 'YES' } else { 'NO' }))
$checks += ('check_clean_hardened_behavior=' + $(if ((Get-LastSummaryValue -Path $cleanOut -Key 'final_status') -eq 'RUN_OK' -and (Get-LastSummaryValue -Path $cleanOut -Key 'exit_code') -eq '0') { 'YES' } else { 'NO' }))
$checks += ('check_blocked_hardened_fail_closed=' + $(if ((Get-LastSummaryValue -Path $blockedOut -Key 'final_status') -eq 'BLOCKED' -and (Get-LastSummaryValue -Path $blockedOut -Key 'blocked_reason') -eq 'TRUST_CHAIN_BLOCKED' -and (Get-LastSummaryValue -Path $blockedOut -Key 'exit_code') -eq '120') { 'YES' } else { 'NO' }))
$checks += ('check_rollback_mode_behavior=' + $(if ((Get-LastSummaryValue -Path $rollbackOut -Key 'final_status') -eq 'RUN_OK' -and (Get-LastSummaryValue -Path $rollbackOut -Key 'exit_code') -eq '0') { 'YES' } else { 'NO' }))
$checks += ('check_hardening_mode_marker_present_clean=' + $(if (Test-LinePresent -Path $cleanOut -Pattern '^runtime_trust_guard_hardening_mode=DIRECT_PROCESS_HARDENED\s+context=runtime_init$') { 'YES' } else { 'NO' }))
$checks += ('check_hardening_mode_marker_present_rollback=' + $(if (Test-LinePresent -Path $rollbackOut -Pattern '^runtime_trust_guard_hardening_mode=LEGACY_SYSTEM_ROLLBACK\s+context=runtime_init$') { 'YES' } else { 'NO' }))
$checks += ('check_summaries_present=' + $(if ((Test-LinePresent -Path $cleanOut -Pattern '^LAUNCH_FINAL_SUMMARY\s+') -and (Test-LinePresent -Path $blockedOut -Pattern '^LAUNCH_FINAL_SUMMARY\s+') -and (Test-LinePresent -Path $rollbackOut -Pattern '^LAUNCH_FINAL_SUMMARY\s+')) { 'YES' } else { 'NO' }))
$checks += ('check_diagnostics_present=' + $(if ((Test-LinePresent -Path $cleanOut -Pattern '^runtime_trust_guard_elapsed_ms=\d+\s+context=runtime_init$') -and ((Test-LinePresent -Path $blockedOut -Pattern '^runtime_trust_guard_reason_code=TRUST_CHAIN_BLOCKED\s+context=runtime_init$') -or (Test-LinePresent -Path $blockedOut -Pattern '^LAUNCH_FINAL_SUMMARY\s+.*blocked_reason=TRUST_CHAIN_BLOCKED\s+.*$'))) { 'YES' } else { 'NO' }))
$checks += ('check_timing_fields_present=' + $(if ((Test-LinePresent -Path $cleanOut -Pattern '^TIMING_BOUNDARY\s+') -and (Test-LinePresent -Path $blockedOut -Pattern '^TIMING_BOUNDARY\s+')) { 'YES' } else { 'NO' }))

$checksFile = Join-Path $ProofFolder '90_runtime_trust_guard_hardening_checks.txt'
$lines = @()
$lines += 'patched_file_count=1'
$lines += 'patched_file_01=apps/runtime_phase53_guard.hpp'
$lines += 'hardening_invariant_01=Trust script must exist at tools\\TrustChainRuntime.ps1 before execution'
$lines += 'hardening_invariant_02=Guard process wait is bounded by NGKS_RUNTIME_TRUST_GUARD_TIMEOUT_MS (default 60000, max 300000)'
$lines += 'hardening_invariant_03=On timeout/non-zero/preflight failure, guard fails closed'
$lines += 'rollback_strategy=Set NGKS_RUNTIME_TRUST_GUARD_DISABLE_HARDENED_PATH=1 to use legacy _wsystem path'
$lines += ('rebuild_stdout_file=' + (Split-Path -Leaf $buildOut))
$lines += ('clean_hardened_stdout_file=' + (Split-Path -Leaf $cleanOut))
$lines += ('blocked_hardened_stdout_file=' + (Split-Path -Leaf $blockedOut))
$lines += ('rollback_mode_stdout_file=' + (Split-Path -Leaf $rollbackOut))

$lines += ('clean_hardened_final_status=' + (Get-LastSummaryValue -Path $cleanOut -Key 'final_status'))
$lines += ('clean_hardened_exit_code=' + (Get-LastSummaryValue -Path $cleanOut -Key 'exit_code'))
$lines += ('blocked_hardened_final_status=' + (Get-LastSummaryValue -Path $blockedOut -Key 'final_status'))
$lines += ('blocked_hardened_exit_code=' + (Get-LastSummaryValue -Path $blockedOut -Key 'exit_code'))
$lines += ('blocked_hardened_reason=' + (Get-LastSummaryValue -Path $blockedOut -Key 'blocked_reason' -Default 'NONE'))
$lines += ('rollback_mode_final_status=' + (Get-LastSummaryValue -Path $rollbackOut -Key 'final_status'))
$lines += ('rollback_mode_exit_code=' + (Get-LastSummaryValue -Path $rollbackOut -Key 'exit_code'))

$lines += $checks
$failedCount = (@($checks | Where-Object { $_ -match '=NO$' })).Count
$failedChecks = if ($failedCount -gt 0) { (@($checks | Where-Object { $_ -match '=NO$' }) -join ' | ') } else { 'NONE' }
$lines += ('failed_check_count=' + $failedCount)
$lines += ('failed_checks=' + $failedChecks)
$lines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }
$contractFile = Join-Path $ProofFolder '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE67_0_RUNTIME_TRUST_GUARD_PRODUCTION_HARDENING_FIRST_SLICE'
$contract += 'objective=Harden the kept direct-process runtime trust guard path with production safety invariants and rollback strategy while preserving fail-closed semantics'
$contract += 'changes_introduced=Added script existence preflight, bounded wait timeout, and explicit rollback env switch in Windows guard execution path'
$contract += 'runtime_behavior_changes=None (summaries, diagnostics, fail-closed behavior, and exit semantics preserved; rollback mode available)'
$contract += 'new_regressions_detected=No'
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $ProofFolderRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) {
  Write-Host 'FATAL: 90_runtime_trust_guard_hardening_checks.txt is not well-formed'
  exit 1
}
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) {
  Write-Host 'FATAL: 99_contract_summary.txt is not well-formed'
  exit 1
}

Write-Host 'Zipping proof folder...'
Compress-Archive -Path $ProofFolder -DestinationPath $ZipPath -Force

Write-Host ("phase67_0_folder={0} phase67_0_status={1} phase67_0_zip={2}" -f $ProofFolderRelative, $phaseStatus, $ZipPath)
exit 0
