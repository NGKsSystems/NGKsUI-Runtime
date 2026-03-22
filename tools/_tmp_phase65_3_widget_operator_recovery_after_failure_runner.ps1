Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'

function Remove-FileWithRetry {
  param(
    [string]$Path,
    [int]$MaxAttempts = 5,
    [int]$SleepMs = 120
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return $true
  }

  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    try {
      Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
      return $true
    }
    catch {
      if ($attempt -lt $MaxAttempts) {
        Start-Sleep -Milliseconds $SleepMs
      }
    }
  }

  return (-not (Test-Path -LiteralPath $Path))
}

function Invoke-PwshToFile {
  param(
    [string[]]$ArgumentList,
    [string]$OutFile,
    [int]$TimeoutSeconds,
    [string]$StepName,
    [string]$CommandText
  )

  $errFile = $OutFile + '.stderr.tmp'
  if (-not (Remove-FileWithRetry -Path $errFile)) {
    return [pscustomobject]@{
      ExitCode = 125
      TimedOut = $false
      FileLock = $true
      LockedFile = $errFile
      StepName = $StepName
      CommandText = $CommandText
      OutFile = $OutFile
    }
  }

  $proc = Start-Process -FilePath 'powershell' -ArgumentList $ArgumentList -PassThru -NoNewWindow -RedirectStandardOutput $OutFile -RedirectStandardError $errFile
  $timedOut = -not $proc.WaitForExit($TimeoutSeconds * 1000)

  if ($timedOut) {
    try { $proc.Kill() } catch {}
    Add-Content -LiteralPath $OutFile -Value ('LAUNCH_ERROR=TIMEOUT step=' + $StepName + ' timeout_seconds=' + $TimeoutSeconds)
    if (Test-Path -LiteralPath $errFile) {
      Get-Content -LiteralPath $errFile | Add-Content -LiteralPath $OutFile
      [void](Remove-FileWithRetry -Path $errFile)
    }

    return [pscustomobject]@{
      ExitCode = 124
      TimedOut = $true
      FileLock = $false
      LockedFile = ''
      StepName = $StepName
      CommandText = $CommandText
      OutFile = $OutFile
    }
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
      return [pscustomobject]@{
        ExitCode = 125
        TimedOut = $false
        FileLock = $true
        LockedFile = $errFile
        StepName = $StepName
        CommandText = $CommandText
        OutFile = $OutFile
      }
    }
  }

  return [pscustomobject]@{
    ExitCode = $exitCode
    TimedOut = $false
    FileLock = $false
    LockedFile = ''
    StepName = $StepName
    CommandText = $CommandText
    OutFile = $OutFile
  }
}

$runStart = Get-Date
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pfRel = '_proof/phase65_3_widget_operator_recovery_after_failure_' + $ts
$pf = Join-Path '_proof' ('phase65_3_widget_operator_recovery_after_failure_' + $ts)
New-Item -ItemType Directory -Force -Path $pf | Out-Null

$failureOut = Join-Path $pf '10_failure_blocked_stdout.txt'
$recoveryOut = Join-Path $pf '11_recovery_clean_stdout.txt'
$checksPath = Join-Path $pf '90_recovery_checks.txt'
$contractPath = Join-Path $pf '99_contract_summary.txt'

$blockedCmd = "powershell -NoProfile -ExecutionPolicy Bypass -Command `$env:NGKS_BYPASS_GUARD='1'; try { & 'tools\\run_widget_sandbox.ps1' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }"
$cleanCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File 'tools\\run_widget_sandbox.ps1' -PassArgs '--auto-close-ms=1500'"

# Scenario 1: forced blocked failure path first
$s1 = Invoke-PwshToFile -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '$env:NGKS_BYPASS_GUARD=''1''; try { & ''tools\run_widget_sandbox.ps1'' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }') -OutFile $failureOut -TimeoutSeconds 60 -StepName 'failure_blocked' -CommandText $blockedCmd
$s1Generated = (Get-Item -LiteralPath $failureOut).LastWriteTime -ge $runStart
$s1Error = [bool](Select-String -Path $failureOut -Pattern '^LAUNCH_ERROR=' -ErrorAction SilentlyContinue)
$s1Blocked = [bool](Select-String -Path $failureOut -Pattern 'LAUNCH_FINAL_SUMMARY.*final_status=BLOCKED' -ErrorAction SilentlyContinue)
$s1FailClosed = [bool](Select-String -Path $failureOut -Pattern 'FAIL_CLOSED=ENABLED' -ErrorAction SilentlyContinue)
$s1Reason = [bool](Select-String -Path $failureOut -Pattern 'blocked_reason=TRUST_CHAIN_BLOCKED|REASON=env_injection_detected' -ErrorAction SilentlyContinue)
$s1Summary = Select-String -Path $failureOut -Pattern 'LAUNCH_FINAL_SUMMARY.*final_status=BLOCKED.*exit_code=' -ErrorAction SilentlyContinue | Select-Object -Last 1
$s1SummaryExit = -1
if ($s1Summary -and $s1Summary.Line -match 'exit_code=(\d+)') {
  $s1SummaryExit = [int]$Matches[1]
}
$s1ProcessExitOk = ($s1SummaryExit -gt 0)

# Scenario 2: immediate clean recovery
$s2 = Invoke-PwshToFile -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools\run_widget_sandbox.ps1', '-PassArgs', '--auto-close-ms=1500') -OutFile $recoveryOut -TimeoutSeconds 60 -StepName 'recovery_clean' -CommandText $cleanCmd
$s2Generated = (Get-Item -LiteralPath $recoveryOut).LastWriteTime -ge $runStart
$s2RunOk = [bool](Select-String -Path $recoveryOut -Pattern 'LAUNCH_FINAL_SUMMARY.*final_status=RUN_OK' -ErrorAction SilentlyContinue)
$s2NoLaunchError = -not [bool](Select-String -Path $recoveryOut -Pattern '^LAUNCH_ERROR=' -ErrorAction SilentlyContinue)
$s2FailClosed = [bool](Select-String -Path $recoveryOut -Pattern '^FAIL_CLOSED=ENABLED' -ErrorAction SilentlyContinue)
$s2PoisonedState = [bool](Select-String -Path $recoveryOut -Pattern 'final_status=BLOCKED|blocked_reason=TRUST_CHAIN_BLOCKED|runtime_trust_guard_failed' -ErrorAction SilentlyContinue)
$s2ExitOk = ($s2.ExitCode -eq 0)

Start-Sleep -Milliseconds 300
$widgetProcCount = @((Get-Process -Name 'widget_sandbox' -ErrorAction SilentlyContinue)).Count
$cleanupStable = ($widgetProcCount -eq 0)

$failed = New-Object System.Collections.Generic.List[string]
if (-not $s1Generated) { $failed.Add('check_s1_generated_in_run=NO') }
if (-not $s1Error) { $failed.Add('check_s1_launch_error_present=NO') }
if (-not $s1Blocked) { $failed.Add('check_s1_final_status_blocked=NO') }
if (-not $s1FailClosed) { $failed.Add('check_s1_fail_closed=NO') }
if (-not $s1Reason) { $failed.Add('check_s1_reason_coherent=NO') }
if (-not $s1ProcessExitOk) { $failed.Add('check_s1_process_exit_ok=NO') }
if ($s1.TimedOut) { $failed.Add('check_s1_no_hang=NO') }
if ($s1.FileLock) { $failed.Add('check_s1_no_file_lock=NO') }
if (-not $s2Generated) { $failed.Add('check_s2_generated_in_run=NO') }
if (-not $s2RunOk) { $failed.Add('check_s2_final_status_run_ok=NO') }
if (-not $s2NoLaunchError) { $failed.Add('check_s2_no_launch_error=NO') }
if (-not $s2FailClosed) { $failed.Add('check_s2_fail_closed=NO') }
if ($s2PoisonedState) { $failed.Add('check_s2_no_poisoned_state=NO') }
if (-not $s2ExitOk) { $failed.Add('check_s2_exit_ok=NO') }
if ($s2.TimedOut) { $failed.Add('check_s2_no_hang=NO') }
if ($s2.FileLock) { $failed.Add('check_s2_no_file_lock=NO') }
if (-not $cleanupStable) { $failed.Add('check_cleanup_exit_stable=NO') }

$allOk = ($failed.Count -eq 0)

@(
  'proof_folder=' + $pfRel,
  'scenario_failure_file=' + ($pfRel + '/10_failure_blocked_stdout.txt'),
  'scenario_recovery_file=' + ($pfRel + '/11_recovery_clean_stdout.txt'),
  'check_s1_generated_in_run=' + $(if ($s1Generated) { 'YES' } else { 'NO' }),
  'check_s1_launch_error_present=' + $(if ($s1Error) { 'YES' } else { 'NO' }),
  'check_s1_final_status_blocked=' + $(if ($s1Blocked) { 'YES' } else { 'NO' }),
  'check_s1_fail_closed=' + $(if ($s1FailClosed) { 'YES' } else { 'NO' }),
  'check_s1_reason_coherent=' + $(if ($s1Reason) { 'YES' } else { 'NO' }),
  'check_s1_process_exit_ok=' + $(if ($s1ProcessExitOk) { 'YES' } else { 'NO' }),
  'check_s2_generated_in_run=' + $(if ($s2Generated) { 'YES' } else { 'NO' }),
  'check_s2_final_status_run_ok=' + $(if ($s2RunOk) { 'YES' } else { 'NO' }),
  'check_s2_no_launch_error=' + $(if ($s2NoLaunchError) { 'YES' } else { 'NO' }),
  'check_s2_fail_closed=' + $(if ($s2FailClosed) { 'YES' } else { 'NO' }),
  'check_s2_no_poisoned_state=' + $(if (-not $s2PoisonedState) { 'YES' } else { 'NO' }),
  'check_s2_exit_ok=' + $(if ($s2ExitOk) { 'YES' } else { 'NO' }),
  'check_cleanup_exit_stable=' + $(if ($cleanupStable) { 'YES' } else { 'NO' }),
  'scenario1_wrapper_exit=' + $s1.ExitCode,
  'scenario1_summary_exit_code=' + $s1SummaryExit,
  'scenario2_wrapper_exit=' + $s2.ExitCode,
  'widget_process_count_after_scenarios=' + $widgetProcCount,
  'failed_check_count=' + $failed.Count,
  'failed_checks=' + $(if ($failed.Count -gt 0) { ($failed -join ';') } else { 'NONE' })
) | Set-Content -LiteralPath $checksPath -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) {
  Remove-Item -LiteralPath $zip -Force
}
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

@(
  'next_phase_selected=PHASE65_3_WIDGET_OPERATOR_RECOVERY_AFTER_FAILURE_VALIDATION',
  'objective=Validate operator-path recovery after a forced blocked failure scenario by confirming immediate clean-path recovery without poisoned state carryover in fresh evidence.',
  'changes_introduced=tools/_tmp_phase65_3_widget_operator_recovery_after_failure_runner.ps1 (execution recovery validation runner only).',
  'runtime_behavior_changes=NONE',
  'new_regressions_detected=' + $(if ($allOk) { 'NO' } else { 'YES' }),
  'phase_status=' + $(if ($allOk) { 'PASS' } else { 'FAIL' }),
  'proof_folder=' + $pfRel
) | Set-Content -LiteralPath $contractPath -Encoding UTF8

Write-Output ('phase65_3_folder=' + $pfRel)
Write-Output ('phase65_3_status=' + $(if ($allOk) { 'PASS' } else { 'FAIL' }))
Write-Output ('phase65_3_zip=' + $pfRel + '.zip')
