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

function Parse-CleanOutput {
  param([string]$Path)

  $runOk = [bool](Select-String -Path $Path -Pattern 'LAUNCH_FINAL_SUMMARY.*final_status=RUN_OK' -ErrorAction SilentlyContinue)
  $noLaunchError = -not [bool](Select-String -Path $Path -Pattern '^LAUNCH_ERROR=' -ErrorAction SilentlyContinue)
  $failClosed = [bool](Select-String -Path $Path -Pattern '^FAIL_CLOSED=ENABLED' -ErrorAction SilentlyContinue)

  return [pscustomobject]@{
    RunOk = $runOk
    NoLaunchError = $noLaunchError
    FailClosed = $failClosed
  }
}

function Parse-BlockedOutput {
  param([string]$Path)

  $hasError = [bool](Select-String -Path $Path -Pattern '^LAUNCH_ERROR=' -ErrorAction SilentlyContinue)
  $statusBlocked = [bool](Select-String -Path $Path -Pattern 'LAUNCH_FINAL_SUMMARY.*final_status=BLOCKED' -ErrorAction SilentlyContinue)
  $failClosed = [bool](Select-String -Path $Path -Pattern 'FAIL_CLOSED=ENABLED' -ErrorAction SilentlyContinue)
  $reasonCoherent = [bool](Select-String -Path $Path -Pattern 'blocked_reason=TRUST_CHAIN_BLOCKED|REASON=env_injection_detected' -ErrorAction SilentlyContinue)

  $summary = Select-String -Path $Path -Pattern 'LAUNCH_FINAL_SUMMARY.*final_status=BLOCKED.*exit_code=' -ErrorAction SilentlyContinue | Select-Object -Last 1
  $summaryExitCode = -1
  if ($summary -and $summary.Line -match 'exit_code=(\d+)') {
    $summaryExitCode = [int]$Matches[1]
  }

  return [pscustomobject]@{
    HasError = $hasError
    StatusBlocked = $statusBlocked
    FailClosed = $failClosed
    ReasonCoherent = $reasonCoherent
    ProcessExitOk = ($summaryExitCode -gt 0)
    SummaryExitCode = $summaryExitCode
  }
}

$runStart = Get-Date
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pfRel = '_proof/phase65_6_widget_operator_soak_validation_' + $ts
$pf = Join-Path '_proof' ('phase65_6_widget_operator_soak_validation_' + $ts)
New-Item -ItemType Directory -Force -Path $pf | Out-Null

$checksPath = Join-Path $pf '90_soak_checks.txt'
$contractPath = Join-Path $pf '99_contract_summary.txt'

$cleanArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools\run_widget_sandbox.ps1', '-PassArgs', '--auto-close-ms=1500')
$blockedArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '$env:NGKS_BYPASS_GUARD=''1''; try { & ''tools\run_widget_sandbox.ps1'' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }')
$cleanCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File 'tools\\run_widget_sandbox.ps1' -PassArgs '--auto-close-ms=1500'"
$blockedCmd = "powershell -NoProfile -ExecutionPolicy Bypass -Command `$env:NGKS_BYPASS_GUARD='1'; try { & 'tools\\run_widget_sandbox.ps1' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }"

$cleanIterations = 8
$blockedInjectionEvery = 3
$cleanResults = @()
$blockedResults = @()

for ($i = 1; $i -le $cleanIterations; $i++) {
  $cleanOut = Join-Path $pf ('10_clean_soak_run' + $i.ToString('00') + '_stdout.txt')
  $c = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $cleanOut -TimeoutSeconds 60 -StepName ('clean_soak_' + $i) -CommandText $cleanCmd
  $cGenerated = (Get-Item -LiteralPath $cleanOut).LastWriteTime -ge $runStart
  $cp = Parse-CleanOutput -Path $cleanOut

  $cleanResults += [pscustomobject]@{
    Iteration = $i
    OutFile = $cleanOut
    GeneratedInRun = $cGenerated
    RunOk = $cp.RunOk
    NoLaunchError = $cp.NoLaunchError
    FailClosed = $cp.FailClosed
    TimedOut = $c.TimedOut
    FileLock = $c.FileLock
    ExitCode = $c.ExitCode
  }

  if (($i % $blockedInjectionEvery) -eq 0) {
    $blockedIdx = [int]($i / $blockedInjectionEvery)
    $blockedOut = Join-Path $pf ('11_blocked_inject' + $blockedIdx.ToString('00') + '_stdout.txt')
    $b = Invoke-PwshToFile -ArgumentList $blockedArgs -OutFile $blockedOut -TimeoutSeconds 60 -StepName ('blocked_inject_' + $blockedIdx) -CommandText $blockedCmd
    $bGenerated = (Get-Item -LiteralPath $blockedOut).LastWriteTime -ge $runStart
    $bp = Parse-BlockedOutput -Path $blockedOut

    $blockedResults += [pscustomobject]@{
      Injection = $blockedIdx
      OutFile = $blockedOut
      GeneratedInRun = $bGenerated
      HasError = $bp.HasError
      StatusBlocked = $bp.StatusBlocked
      FailClosed = $bp.FailClosed
      ReasonCoherent = $bp.ReasonCoherent
      ProcessExitOk = $bp.ProcessExitOk
      SummaryExitCode = $bp.SummaryExitCode
      TimedOut = $b.TimedOut
      FileLock = $b.FileLock
      WrapperExit = $b.ExitCode
    }
  }

  Start-Sleep -Milliseconds 100
}

# Final post-soak clean health check
$finalCleanOut = Join-Path $pf '12_post_soak_clean_stdout.txt'
$fc = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $finalCleanOut -TimeoutSeconds 60 -StepName 'post_soak_clean' -CommandText $cleanCmd
$fcGenerated = (Get-Item -LiteralPath $finalCleanOut).LastWriteTime -ge $runStart
$fcp = Parse-CleanOutput -Path $finalCleanOut

$earlyClean = @($cleanResults | Where-Object { $_.Iteration -le [math]::Floor($cleanIterations / 2) })
$lateClean = @($cleanResults | Where-Object { $_.Iteration -gt [math]::Floor($cleanIterations / 2) })
$earlyAllRunOk = (@($earlyClean | Where-Object { -not $_.RunOk }).Count -eq 0)
$lateAllRunOk = (@($lateClean | Where-Object { -not $_.RunOk }).Count -eq 0)
$noLateDegradation = $earlyAllRunOk -and $lateAllRunOk

$cleanAllPass = (@($cleanResults | Where-Object { -not ($_.GeneratedInRun -and $_.RunOk -and $_.NoLaunchError -and $_.FailClosed -and (-not $_.TimedOut) -and (-not $_.FileLock) -and ($_.ExitCode -eq 0)) }).Count -eq 0)
$blockedAllPass = (@($blockedResults | Where-Object { -not ($_.GeneratedInRun -and $_.HasError -and $_.StatusBlocked -and $_.FailClosed -and $_.ReasonCoherent -and $_.ProcessExitOk -and (-not $_.TimedOut) -and (-not $_.FileLock)) }).Count -eq 0)

$cleanExitSet = @($cleanResults | ForEach-Object { [string]$_.ExitCode } | Select-Object -Unique)
$blockedExitSet = @($blockedResults | ForEach-Object { [string]$_.SummaryExitCode } | Select-Object -Unique)
$cleanExitConsistent = ($cleanExitSet.Count -eq 1)
$blockedExitConsistent = ($blockedExitSet.Count -eq 1)

Start-Sleep -Milliseconds 300
$widgetProcCount = @((Get-Process -Name 'widget_sandbox' -ErrorAction SilentlyContinue)).Count
$cleanupStable = ($widgetProcCount -eq 0)

$failed = New-Object System.Collections.Generic.List[string]
if (-not $cleanAllPass) { $failed.Add('check_clean_soak_all_pass=NO') }
if (-not $blockedAllPass) { $failed.Add('check_blocked_injections_all_pass=NO') }
if (-not $noLateDegradation) { $failed.Add('check_no_late_degradation=NO') }
if (-not $fcGenerated) { $failed.Add('check_final_clean_generated_in_run=NO') }
if (-not $fcp.RunOk) { $failed.Add('check_final_clean_run_ok=NO') }
if (-not $fcp.NoLaunchError) { $failed.Add('check_final_clean_no_launch_error=NO') }
if (-not $fcp.FailClosed) { $failed.Add('check_final_clean_fail_closed=NO') }
if ($fc.TimedOut) { $failed.Add('check_final_clean_no_hang=NO') }
if ($fc.FileLock) { $failed.Add('check_final_clean_no_file_lock=NO') }
if ($fc.ExitCode -ne 0) { $failed.Add('check_final_clean_exit_ok=NO') }
if (-not $cleanExitConsistent) { $failed.Add('check_clean_exit_consistency=NO') }
if (-not $blockedExitConsistent) { $failed.Add('check_blocked_summary_exit_consistency=NO') }
if (-not $cleanupStable) { $failed.Add('check_cleanup_exit_stable=NO') }

$allOk = ($failed.Count -eq 0)
$regressionsValue = if ($allOk) { 'NO' } else { 'YES' }
$phaseStatusValue = if ($allOk) { 'PASS' } else { 'FAIL' }

$rows = New-Object System.Collections.Generic.List[string]
$rows.Add('proof_folder=' + $pfRel)
$rows.Add('clean_iterations=' + $cleanIterations)
$rows.Add('blocked_injections=' + $blockedResults.Count)

foreach ($c in $cleanResults) {
  $prefix = 'clean_soak_run' + $c.Iteration.ToString('00')
  $rows.Add($prefix + '_file=' + ($pfRel + '/' + [System.IO.Path]::GetFileName($c.OutFile)))
  $rows.Add($prefix + '_generated_in_run=' + $(if ($c.GeneratedInRun) { 'YES' } else { 'NO' }))
  $rows.Add($prefix + '_final_status_run_ok=' + $(if ($c.RunOk) { 'YES' } else { 'NO' }))
  $rows.Add($prefix + '_no_launch_error=' + $(if ($c.NoLaunchError) { 'YES' } else { 'NO' }))
  $rows.Add($prefix + '_fail_closed=' + $(if ($c.FailClosed) { 'YES' } else { 'NO' }))
  $rows.Add($prefix + '_no_hang=' + $(if (-not $c.TimedOut) { 'YES' } else { 'NO' }))
  $rows.Add($prefix + '_exit=' + $c.ExitCode)
}

foreach ($b in $blockedResults) {
  $prefix = 'blocked_inject' + $b.Injection.ToString('00')
  $rows.Add($prefix + '_file=' + ($pfRel + '/' + [System.IO.Path]::GetFileName($b.OutFile)))
  $rows.Add($prefix + '_generated_in_run=' + $(if ($b.GeneratedInRun) { 'YES' } else { 'NO' }))
  $rows.Add($prefix + '_launch_error_present=' + $(if ($b.HasError) { 'YES' } else { 'NO' }))
  $rows.Add($prefix + '_final_status_blocked=' + $(if ($b.StatusBlocked) { 'YES' } else { 'NO' }))
  $rows.Add($prefix + '_fail_closed=' + $(if ($b.FailClosed) { 'YES' } else { 'NO' }))
  $rows.Add($prefix + '_reason_coherent=' + $(if ($b.ReasonCoherent) { 'YES' } else { 'NO' }))
  $rows.Add($prefix + '_process_exit_ok=' + $(if ($b.ProcessExitOk) { 'YES' } else { 'NO' }))
  $rows.Add($prefix + '_summary_exit_code=' + $b.SummaryExitCode)
  $rows.Add($prefix + '_no_hang=' + $(if (-not $b.TimedOut) { 'YES' } else { 'NO' }))
}

$rows.Add('post_soak_clean_file=' + ($pfRel + '/' + [System.IO.Path]::GetFileName($finalCleanOut)))
$rows.Add('check_clean_soak_all_pass=' + $(if ($cleanAllPass) { 'YES' } else { 'NO' }))
$rows.Add('check_blocked_injections_all_pass=' + $(if ($blockedAllPass) { 'YES' } else { 'NO' }))
$rows.Add('check_no_late_degradation=' + $(if ($noLateDegradation) { 'YES' } else { 'NO' }))
$rows.Add('check_final_clean_generated_in_run=' + $(if ($fcGenerated) { 'YES' } else { 'NO' }))
$rows.Add('check_final_clean_run_ok=' + $(if ($fcp.RunOk) { 'YES' } else { 'NO' }))
$rows.Add('check_final_clean_no_launch_error=' + $(if ($fcp.NoLaunchError) { 'YES' } else { 'NO' }))
$rows.Add('check_final_clean_fail_closed=' + $(if ($fcp.FailClosed) { 'YES' } else { 'NO' }))
$rows.Add('check_final_clean_no_hang=' + $(if (-not $fc.TimedOut) { 'YES' } else { 'NO' }))
$rows.Add('check_final_clean_exit_ok=' + $(if ($fc.ExitCode -eq 0) { 'YES' } else { 'NO' }))
$rows.Add('check_clean_exit_consistency=' + $(if ($cleanExitConsistent) { 'YES' } else { 'NO' }))
$rows.Add('check_blocked_summary_exit_consistency=' + $(if ($blockedExitConsistent) { 'YES' } else { 'NO' }))
$rows.Add('check_cleanup_exit_stable=' + $(if ($cleanupStable) { 'YES' } else { 'NO' }))
$rows.Add('clean_unique_exits=' + ($cleanExitSet -join ','))
$rows.Add('blocked_unique_summary_exit_codes=' + ($blockedExitSet -join ','))
$rows.Add('widget_process_count_after_soak=' + $widgetProcCount)
$rows.Add('failed_check_count=' + $failed.Count)
$rows.Add('failed_checks=' + $(if ($failed.Count -gt 0) { ($failed -join ';') } else { 'NONE' }))
$rows | Set-Content -LiteralPath $checksPath -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) {
  Remove-Item -LiteralPath $zip -Force
}
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

$contractRows = New-Object System.Collections.Generic.List[string]
$contractRows.Add('next_phase_selected=PHASE65_6_WIDGET_OPERATOR_LONG_RUN_SOAK_VALIDATION')
$contractRows.Add('objective=Validate long-run operator-path stability by executing extended clean soak with interval blocked injections, checking late-run behavior and final post-soak clean health.')
$contractRows.Add('changes_introduced=tools/_tmp_phase65_6_widget_operator_soak_validation_runner.ps1 (execution long-run soak validation runner only).')
$contractRows.Add('runtime_behavior_changes=NONE')
$contractRows.Add('new_regressions_detected=' + $regressionsValue)
$contractRows.Add('phase_status=' + $phaseStatusValue)
$contractRows.Add('proof_folder=' + $pfRel)
$contractRows | Set-Content -LiteralPath $contractPath -Encoding UTF8

Write-Output ('phase65_6_folder=' + $pfRel)
Write-Output ('phase65_6_status=' + $(if ($allOk) { 'PASS' } else { 'FAIL' }))
Write-Output ('phase65_6_zip=' + $pfRel + '.zip')
