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
      if (-not (Remove-FileWithRetry -Path $errFile)) {
        return [pscustomobject]@{
          ExitCode = 125
          TimedOut = $true
          FileLock = $true
          LockedFile = $errFile
          StepName = $StepName
          CommandText = $CommandText
          OutFile = $OutFile
        }
      }
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
    ExitCode = $proc.ExitCode
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
$pfRel = '_proof/phase65_0_widget_operator_execution_validation_' + $ts
$pf = Join-Path '_proof' ('phase65_0_widget_operator_execution_validation_' + $ts)
New-Item -ItemType Directory -Force -Path $pf | Out-Null

$cleanOut = Join-Path $pf '10_clean_stdout.txt'
$blockedOut = Join-Path $pf '11_blocked_stdout.txt'
$checksPath = Join-Path $pf '90_execution_checks.txt'
$contractPath = Join-Path $pf '99_contract_summary.txt'

$cleanCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File 'tools\\run_widget_sandbox.ps1' -PassArgs '--auto-close-ms=1500'"
$clean = Invoke-PwshToFile -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools\run_widget_sandbox.ps1', '-PassArgs', '--auto-close-ms=1500') -OutFile $cleanOut -TimeoutSeconds 60 -StepName 'clean_widget_launcher' -CommandText $cleanCmd

$blockedCmd = "powershell -NoProfile -ExecutionPolicy Bypass -Command `$env:NGKS_BYPASS_GUARD='1'; try { & 'tools\\run_widget_sandbox.ps1' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }"
$blocked = Invoke-PwshToFile -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '$env:NGKS_BYPASS_GUARD=''1''; try { & ''tools\run_widget_sandbox.ps1'' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }') -OutFile $blockedOut -TimeoutSeconds 60 -StepName 'blocked_widget_launcher' -CommandText $blockedCmd

$cleanGeneratedInRun = (Get-Item -LiteralPath $cleanOut).LastWriteTime -ge $runStart
$blockedGeneratedInRun = (Get-Item -LiteralPath $blockedOut).LastWriteTime -ge $runStart

$cleanRunOk = [bool](Select-String -Path $cleanOut -Pattern 'LAUNCH_FINAL_SUMMARY.*final_status=RUN_OK' -ErrorAction SilentlyContinue)
$blockedHasError = [bool](Select-String -Path $blockedOut -Pattern '^LAUNCH_ERROR=' -ErrorAction SilentlyContinue)
$blockedStatusBlocked = [bool](Select-String -Path $blockedOut -Pattern 'LAUNCH_FINAL_SUMMARY.*final_status=BLOCKED' -ErrorAction SilentlyContinue)
$failClosedActive = [bool](Select-String -Path $cleanOut,$blockedOut -Pattern '^FAIL_CLOSED=ENABLED' -ErrorAction SilentlyContinue)

$noHang = (-not $clean.TimedOut) -and (-not $blocked.TimedOut)
$noFileLock = (-not $clean.FileLock) -and (-not $blocked.FileLock)

$failed = New-Object System.Collections.Generic.List[string]
if (-not $cleanGeneratedInRun) { $failed.Add('check_generated_in_run_clean=NO') }
if (-not $blockedGeneratedInRun) { $failed.Add('check_generated_in_run_blocked=NO') }
if (-not $cleanRunOk) { $failed.Add('check_clean_final_status_run_ok=NO') }
if (-not $blockedHasError) { $failed.Add('check_blocked_launch_error_present=NO') }
if (-not $blockedStatusBlocked) { $failed.Add('check_blocked_final_status_blocked=NO') }
if (-not $failClosedActive) { $failed.Add('check_fail_closed_enforcement_active=NO') }
if (-not $noHang) { $failed.Add('check_no_hang=NO') }
if (-not $noFileLock) { $failed.Add('check_no_file_lock=NO') }

$allOk = ($failed.Count -eq 0)

@(
  'proof_folder=' + $pfRel,
  'evidence_clean_file=' + $pfRel + '/10_clean_stdout.txt',
  'evidence_blocked_file=' + $pfRel + '/11_blocked_stdout.txt',
  'check_generated_in_run_clean=' + $(if ($cleanGeneratedInRun) { 'YES' } else { 'NO' }),
  'check_generated_in_run_blocked=' + $(if ($blockedGeneratedInRun) { 'YES' } else { 'NO' }),
  'check_clean_final_status_run_ok=' + $(if ($cleanRunOk) { 'YES' } else { 'NO' }),
  'check_blocked_launch_error_present=' + $(if ($blockedHasError) { 'YES' } else { 'NO' }),
  'check_blocked_final_status_blocked=' + $(if ($blockedStatusBlocked) { 'YES' } else { 'NO' }),
  'check_fail_closed_enforcement_active=' + $(if ($failClosedActive) { 'YES' } else { 'NO' }),
  'check_no_hang=' + $(if ($noHang) { 'YES' } else { 'NO' }),
  'check_no_file_lock=' + $(if ($noFileLock) { 'YES' } else { 'NO' }),
  'clean_exit=' + $clean.ExitCode,
  'blocked_exit=' + $blocked.ExitCode,
  'failed_check_count=' + $failed.Count,
  'failed_checks=' + $(if ($failed.Count -gt 0) { ($failed -join ';') } else { 'NONE' })
) | Set-Content -LiteralPath $checksPath -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) {
  Remove-Item -LiteralPath $zip -Force
}
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

@(
  'next_phase_selected=PHASE65_0_WIDGET_OPERATOR_EXECUTION_VALIDATION',
  'objective=Execute widget operator launcher end-to-end on clean and blocked guard paths, capture full stdout, and verify runtime fail-closed execution signals in fresh run evidence.',
  'changes_introduced=tools/_tmp_phase65_0_widget_operator_execution_validation_runner.ps1 (execution validation runner only).',
  'runtime_behavior_changes=NONE',
  'new_regressions_detected=' + $(if ($allOk) { 'NO' } else { 'YES' }),
  'phase_status=' + $(if ($allOk) { 'PASS' } else { 'FAIL' }),
  'proof_folder=' + $pfRel
) | Set-Content -LiteralPath $contractPath -Encoding UTF8

Write-Output ('phase65_0_folder=' + $pfRel)
Write-Output ('phase65_0_status=' + $(if ($allOk) { 'PASS' } else { 'FAIL' }))
Write-Output ('phase65_0_zip=' + $pfRel + '.zip')
