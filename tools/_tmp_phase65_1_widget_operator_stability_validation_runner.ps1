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
$pfRel = '_proof/phase65_1_widget_operator_stability_validation_' + $ts
$pf = Join-Path '_proof' ('phase65_1_widget_operator_stability_validation_' + $ts)
New-Item -ItemType Directory -Force -Path $pf | Out-Null

$checksPath = Join-Path $pf '90_stability_checks.txt'
$contractPath = Join-Path $pf '99_contract_summary.txt'

$iterations = 3
$cleanResults = @()
$blockedResults = @()

$cleanCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File 'tools\\run_widget_sandbox.ps1' -PassArgs '--auto-close-ms=1500'"
$blockedCmd = "powershell -NoProfile -ExecutionPolicy Bypass -Command `$env:NGKS_BYPASS_GUARD='1'; try { & 'tools\\run_widget_sandbox.ps1' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }"

for ($i = 1; $i -le $iterations; $i++) {
  $cleanOut = Join-Path $pf ('10_clean_run' + $i.ToString('00') + '_stdout.txt')
  $cleanRes = Invoke-PwshToFile -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools\run_widget_sandbox.ps1', '-PassArgs', '--auto-close-ms=1500') -OutFile $cleanOut -TimeoutSeconds 60 -StepName ('clean_run_' + $i) -CommandText $cleanCmd

  $cleanGeneratedInRun = (Get-Item -LiteralPath $cleanOut).LastWriteTime -ge $runStart
  $cleanRunOk = [bool](Select-String -Path $cleanOut -Pattern 'LAUNCH_FINAL_SUMMARY.*final_status=RUN_OK' -ErrorAction SilentlyContinue)
  $cleanFailClosed = [bool](Select-String -Path $cleanOut -Pattern '^FAIL_CLOSED=ENABLED' -ErrorAction SilentlyContinue)

  $cleanResults += [pscustomobject]@{
    Iteration = $i
    OutFile = $cleanOut
    GeneratedInRun = $cleanGeneratedInRun
    RunOk = $cleanRunOk
    FailClosed = $cleanFailClosed
    TimedOut = $cleanRes.TimedOut
    FileLock = $cleanRes.FileLock
    ExitCode = $cleanRes.ExitCode
  }

  $blockedOut = Join-Path $pf ('11_blocked_run' + $i.ToString('00') + '_stdout.txt')
  $blockedRes = Invoke-PwshToFile -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '$env:NGKS_BYPASS_GUARD=''1''; try { & ''tools\run_widget_sandbox.ps1'' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }') -OutFile $blockedOut -TimeoutSeconds 60 -StepName ('blocked_run_' + $i) -CommandText $blockedCmd

  $blockedGeneratedInRun = (Get-Item -LiteralPath $blockedOut).LastWriteTime -ge $runStart
  $blockedHasError = [bool](Select-String -Path $blockedOut -Pattern '^LAUNCH_ERROR=' -ErrorAction SilentlyContinue)
  $blockedStatusBlocked = [bool](Select-String -Path $blockedOut -Pattern 'LAUNCH_FINAL_SUMMARY.*final_status=BLOCKED' -ErrorAction SilentlyContinue)
  $blockedFailClosed = [bool](Select-String -Path $blockedOut -Pattern 'FAIL_CLOSED=ENABLED' -ErrorAction SilentlyContinue)
  $blockedSummaryLine = Select-String -Path $blockedOut -Pattern 'LAUNCH_FINAL_SUMMARY.*final_status=BLOCKED.*exit_code=' -ErrorAction SilentlyContinue | Select-Object -Last 1
  $blockedSummaryExitCode = -1
  if ($blockedSummaryLine -and $blockedSummaryLine.Line -match 'exit_code=(\d+)') {
    $blockedSummaryExitCode = [int]$Matches[1]
  }
  $blockedProcessExitOk = ($blockedSummaryExitCode -gt 0)

  $blockedResults += [pscustomobject]@{
    Iteration = $i
    OutFile = $blockedOut
    GeneratedInRun = $blockedGeneratedInRun
    HasError = $blockedHasError
    StatusBlocked = $blockedStatusBlocked
    FailClosed = $blockedFailClosed
    ProcessExitOk = $blockedProcessExitOk
    SummaryExitCode = $blockedSummaryExitCode
    TimedOut = $blockedRes.TimedOut
    FileLock = $blockedRes.FileLock
    ExitCode = $blockedRes.ExitCode
  }
}

$cleanAllPass = (@($cleanResults | Where-Object { -not ($_.GeneratedInRun -and $_.RunOk -and $_.FailClosed -and (-not $_.TimedOut) -and (-not $_.FileLock) -and ($_.ExitCode -eq 0)) }).Count -eq 0)
$blockedAllPass = (@($blockedResults | Where-Object { -not ($_.GeneratedInRun -and $_.HasError -and $_.StatusBlocked -and $_.FailClosed -and $_.ProcessExitOk -and (-not $_.TimedOut) -and (-not $_.FileLock)) }).Count -eq 0)

$cleanExitSet = @($cleanResults | ForEach-Object { [string]$_.ExitCode } | Select-Object -Unique)
$blockedExitSet = @($blockedResults | ForEach-Object { [string]$_.ExitCode } | Select-Object -Unique)
$cleanExitConsistent = ($cleanExitSet.Count -eq 1)
$blockedExitConsistent = ($blockedExitSet.Count -eq 1)

$failed = New-Object System.Collections.Generic.List[string]
if (-not $cleanAllPass) { $failed.Add('check_clean_all_iterations=NO') }
if (-not $blockedAllPass) { $failed.Add('check_blocked_all_iterations=NO') }
if (-not $cleanExitConsistent) { $failed.Add('check_clean_exit_consistency=NO') }
if (-not $blockedExitConsistent) { $failed.Add('check_blocked_exit_consistency=NO') }

$allOk = ($failed.Count -eq 0)

$rows = New-Object System.Collections.Generic.List[string]
$rows.Add('proof_folder=' + $pfRel)
$rows.Add('iterations=' + $iterations)
for ($i = 0; $i -lt $iterations; $i++) {
  $c = $cleanResults[$i]
  $rows.Add(('clean_run' + $c.Iteration.ToString('00') + '_file=' + ($pfRel + '/' + [System.IO.Path]::GetFileName($c.OutFile))))
  $rows.Add(('clean_run' + $c.Iteration.ToString('00') + '_generated_in_run=' + $(if ($c.GeneratedInRun) { 'YES' } else { 'NO' })))
  $rows.Add(('clean_run' + $c.Iteration.ToString('00') + '_final_status_run_ok=' + $(if ($c.RunOk) { 'YES' } else { 'NO' })))
  $rows.Add(('clean_run' + $c.Iteration.ToString('00') + '_fail_closed=' + $(if ($c.FailClosed) { 'YES' } else { 'NO' })))
  $rows.Add(('clean_run' + $c.Iteration.ToString('00') + '_no_hang=' + $(if (-not $c.TimedOut) { 'YES' } else { 'NO' })))
  $rows.Add(('clean_run' + $c.Iteration.ToString('00') + '_exit=' + $c.ExitCode))

  $b = $blockedResults[$i]
  $rows.Add(('blocked_run' + $b.Iteration.ToString('00') + '_file=' + ($pfRel + '/' + [System.IO.Path]::GetFileName($b.OutFile))))
  $rows.Add(('blocked_run' + $b.Iteration.ToString('00') + '_generated_in_run=' + $(if ($b.GeneratedInRun) { 'YES' } else { 'NO' })))
  $rows.Add(('blocked_run' + $b.Iteration.ToString('00') + '_launch_error_present=' + $(if ($b.HasError) { 'YES' } else { 'NO' })))
  $rows.Add(('blocked_run' + $b.Iteration.ToString('00') + '_final_status_blocked=' + $(if ($b.StatusBlocked) { 'YES' } else { 'NO' })))
  $rows.Add(('blocked_run' + $b.Iteration.ToString('00') + '_fail_closed=' + $(if ($b.FailClosed) { 'YES' } else { 'NO' })))
  $rows.Add(('blocked_run' + $b.Iteration.ToString('00') + '_process_exit_ok=' + $(if ($b.ProcessExitOk) { 'YES' } else { 'NO' })))
  $rows.Add(('blocked_run' + $b.Iteration.ToString('00') + '_summary_exit_code=' + $b.SummaryExitCode))
  $rows.Add(('blocked_run' + $b.Iteration.ToString('00') + '_no_hang=' + $(if (-not $b.TimedOut) { 'YES' } else { 'NO' })))
  $rows.Add(('blocked_run' + $b.Iteration.ToString('00') + '_wrapper_exit=' + $b.ExitCode))
}

$rows.Add('check_clean_all_iterations=' + $(if ($cleanAllPass) { 'YES' } else { 'NO' }))
$rows.Add('check_blocked_all_iterations=' + $(if ($blockedAllPass) { 'YES' } else { 'NO' }))
$rows.Add('check_clean_exit_consistency=' + $(if ($cleanExitConsistent) { 'YES' } else { 'NO' }))
$rows.Add('check_blocked_exit_consistency=' + $(if ($blockedExitConsistent) { 'YES' } else { 'NO' }))
$rows.Add('clean_unique_exits=' + ($cleanExitSet -join ','))
$rows.Add('blocked_unique_exits=' + ($blockedExitSet -join ','))
$rows.Add('failed_check_count=' + $failed.Count)
$rows.Add('failed_checks=' + $(if ($failed.Count -gt 0) { ($failed -join ';') } else { 'NONE' }))
$rows | Set-Content -LiteralPath $checksPath -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) {
  Remove-Item -LiteralPath $zip -Force
}
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

@(
  'next_phase_selected=PHASE65_1_WIDGET_OPERATOR_STABILITY_VALIDATION',
  'objective=Validate repeated end-to-end operator launcher stability by running clean and blocked guard paths across multiple iterations with per-run evidence and consistency checks.',
  'changes_introduced=tools/_tmp_phase65_1_widget_operator_stability_validation_runner.ps1 (execution stability validation runner only).',
  'runtime_behavior_changes=NONE',
  'new_regressions_detected=' + $(if ($allOk) { 'NO' } else { 'YES' }),
  'phase_status=' + $(if ($allOk) { 'PASS' } else { 'FAIL' }),
  'proof_folder=' + $pfRel
) | Set-Content -LiteralPath $contractPath -Encoding UTF8

Write-Output ('phase65_1_folder=' + $pfRel)
Write-Output ('phase65_1_status=' + $(if ($allOk) { 'PASS' } else { 'FAIL' }))
Write-Output ('phase65_1_zip=' + $pfRel + '.zip')
