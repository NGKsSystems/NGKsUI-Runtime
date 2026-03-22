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
$pfRel = '_proof/phase65_2_widget_operator_resilience_validation_' + $ts
$pf = Join-Path '_proof' ('phase65_2_widget_operator_resilience_validation_' + $ts)
New-Item -ItemType Directory -Force -Path $pf | Out-Null

$checksPath = Join-Path $pf '90_resilience_checks.txt'
$contractPath = Join-Path $pf '99_contract_summary.txt'

$cleanCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File 'tools\\run_widget_sandbox.ps1' -PassArgs '--auto-close-ms=1500'"
$blockedCmd = "powershell -NoProfile -ExecutionPolicy Bypass -Command `$env:NGKS_BYPASS_GUARD='1'; try { & 'tools\\run_widget_sandbox.ps1' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }"

# Scenario 1: forced timeout interruption on clean path
$out1 = Join-Path $pf '10_scenario_timeout_clean_stdout.txt'
$s1 = Invoke-PwshToFile -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools\run_widget_sandbox.ps1', '-PassArgs', '--auto-close-ms=1500') -OutFile $out1 -TimeoutSeconds 1 -StepName 'scenario_timeout_clean' -CommandText $cleanCmd
$s1Generated = (Get-Item -LiteralPath $out1).LastWriteTime -ge $runStart
$s1TimeoutMarker = [bool](Select-String -Path $out1 -Pattern '^LAUNCH_ERROR=TIMEOUT' -ErrorAction SilentlyContinue)

# Scenario 2: post-timeout clean recovery
$out2 = Join-Path $pf '11_scenario_recovery_clean_stdout.txt'
$s2 = Invoke-PwshToFile -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools\run_widget_sandbox.ps1', '-PassArgs', '--auto-close-ms=1500') -OutFile $out2 -TimeoutSeconds 60 -StepName 'scenario_recovery_clean' -CommandText $cleanCmd
$s2Generated = (Get-Item -LiteralPath $out2).LastWriteTime -ge $runStart
$s2RunOk = [bool](Select-String -Path $out2 -Pattern 'LAUNCH_FINAL_SUMMARY.*final_status=RUN_OK' -ErrorAction SilentlyContinue)
$s2FailClosed = [bool](Select-String -Path $out2 -Pattern '^FAIL_CLOSED=ENABLED' -ErrorAction SilentlyContinue)

# Scenario 3: blocked path recovery after interruption
$out3 = Join-Path $pf '12_scenario_recovery_blocked_stdout.txt'
$s3 = Invoke-PwshToFile -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '$env:NGKS_BYPASS_GUARD=''1''; try { & ''tools\run_widget_sandbox.ps1'' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }') -OutFile $out3 -TimeoutSeconds 60 -StepName 'scenario_recovery_blocked' -CommandText $blockedCmd
$s3Generated = (Get-Item -LiteralPath $out3).LastWriteTime -ge $runStart
$s3HasError = [bool](Select-String -Path $out3 -Pattern '^LAUNCH_ERROR=' -ErrorAction SilentlyContinue)
$s3Blocked = [bool](Select-String -Path $out3 -Pattern 'LAUNCH_FINAL_SUMMARY.*final_status=BLOCKED' -ErrorAction SilentlyContinue)
$s3ReasonCoherent = [bool](Select-String -Path $out3 -Pattern 'blocked_reason=TRUST_CHAIN_BLOCKED|REASON=env_injection_detected' -ErrorAction SilentlyContinue)
$s3FailClosed = [bool](Select-String -Path $out3 -Pattern 'FAIL_CLOSED=ENABLED' -ErrorAction SilentlyContinue)
$s3Summary = Select-String -Path $out3 -Pattern 'LAUNCH_FINAL_SUMMARY.*final_status=BLOCKED.*exit_code=' -ErrorAction SilentlyContinue | Select-Object -Last 1
$s3SummaryExitCode = -1
if ($s3Summary -and $s3Summary.Line -match 'exit_code=(\d+)') {
  $s3SummaryExitCode = [int]$Matches[1]
}
$s3ProcessExitOk = ($s3SummaryExitCode -gt 0)

# Cleanup stability check after interruption scenarios
Start-Sleep -Milliseconds 300
$widgetProcCount = @((Get-Process -Name 'widget_sandbox' -ErrorAction SilentlyContinue)).Count
$cleanupStable = ($widgetProcCount -eq 0)

$failed = New-Object System.Collections.Generic.List[string]
if (-not $s1Generated) { $failed.Add('check_s1_generated_in_run=NO') }
if (-not $s1.TimedOut) { $failed.Add('check_s1_timeout_triggered=NO') }
if (-not $s1TimeoutMarker) { $failed.Add('check_s1_timeout_marker_present=NO') }
if ($s1.FileLock) { $failed.Add('check_s1_file_lock=NO') }
if (-not $s2Generated) { $failed.Add('check_s2_generated_in_run=NO') }
if (-not $s2RunOk) { $failed.Add('check_s2_final_status_run_ok=NO') }
if (-not $s2FailClosed) { $failed.Add('check_s2_fail_closed=NO') }
if ($s2.TimedOut) { $failed.Add('check_s2_no_hang=NO') }
if ($s2.FileLock) { $failed.Add('check_s2_no_file_lock=NO') }
if (-not $s3Generated) { $failed.Add('check_s3_generated_in_run=NO') }
if (-not $s3HasError) { $failed.Add('check_s3_launch_error_present=NO') }
if (-not $s3Blocked) { $failed.Add('check_s3_final_status_blocked=NO') }
if (-not $s3ReasonCoherent) { $failed.Add('check_s3_reason_coherent=NO') }
if (-not $s3FailClosed) { $failed.Add('check_s3_fail_closed=NO') }
if (-not $s3ProcessExitOk) { $failed.Add('check_s3_process_exit_ok=NO') }
if ($s3.TimedOut) { $failed.Add('check_s3_no_hang=NO') }
if ($s3.FileLock) { $failed.Add('check_s3_no_file_lock=NO') }
if (-not $cleanupStable) { $failed.Add('check_cleanup_exit_stable=NO') }

$allOk = ($failed.Count -eq 0)

@(
  'proof_folder=' + $pfRel,
  'scenario1_file=' + ($pfRel + '/10_scenario_timeout_clean_stdout.txt'),
  'scenario2_file=' + ($pfRel + '/11_scenario_recovery_clean_stdout.txt'),
  'scenario3_file=' + ($pfRel + '/12_scenario_recovery_blocked_stdout.txt'),
  'check_s1_generated_in_run=' + $(if ($s1Generated) { 'YES' } else { 'NO' }),
  'check_s1_timeout_triggered=' + $(if ($s1.TimedOut) { 'YES' } else { 'NO' }),
  'check_s1_timeout_marker_present=' + $(if ($s1TimeoutMarker) { 'YES' } else { 'NO' }),
  'check_s2_generated_in_run=' + $(if ($s2Generated) { 'YES' } else { 'NO' }),
  'check_s2_final_status_run_ok=' + $(if ($s2RunOk) { 'YES' } else { 'NO' }),
  'check_s2_fail_closed=' + $(if ($s2FailClosed) { 'YES' } else { 'NO' }),
  'check_s3_generated_in_run=' + $(if ($s3Generated) { 'YES' } else { 'NO' }),
  'check_s3_launch_error_present=' + $(if ($s3HasError) { 'YES' } else { 'NO' }),
  'check_s3_final_status_blocked=' + $(if ($s3Blocked) { 'YES' } else { 'NO' }),
  'check_s3_reason_coherent=' + $(if ($s3ReasonCoherent) { 'YES' } else { 'NO' }),
  'check_s3_fail_closed=' + $(if ($s3FailClosed) { 'YES' } else { 'NO' }),
  'check_s3_process_exit_ok=' + $(if ($s3ProcessExitOk) { 'YES' } else { 'NO' }),
  'check_cleanup_exit_stable=' + $(if ($cleanupStable) { 'YES' } else { 'NO' }),
  'scenario1_wrapper_exit=' + $s1.ExitCode,
  'scenario2_wrapper_exit=' + $s2.ExitCode,
  'scenario3_wrapper_exit=' + $s3.ExitCode,
  'scenario3_summary_exit_code=' + $s3SummaryExitCode,
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
  'next_phase_selected=PHASE65_2_WIDGET_OPERATOR_RESILIENCE_VALIDATION',
  'objective=Validate operator launcher timeout/interruption resilience by forcing timeout interruption and verifying coherent recovery behavior across clean and blocked paths in fresh evidence.',
  'changes_introduced=tools/_tmp_phase65_2_widget_operator_resilience_validation_runner.ps1 (execution resilience runner only).',
  'runtime_behavior_changes=NONE',
  'new_regressions_detected=' + $(if ($allOk) { 'NO' } else { 'YES' }),
  'phase_status=' + $(if ($allOk) { 'PASS' } else { 'FAIL' }),
  'proof_folder=' + $pfRel
) | Set-Content -LiteralPath $contractPath -Encoding UTF8

Write-Output ('phase65_2_folder=' + $pfRel)
Write-Output ('phase65_2_status=' + $(if ($allOk) { 'PASS' } else { 'FAIL' }))
Write-Output ('phase65_2_zip=' + $pfRel + '.zip')
