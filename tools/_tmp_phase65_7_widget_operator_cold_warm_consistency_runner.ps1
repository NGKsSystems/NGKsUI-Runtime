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
  $summary = Select-String -Path $Path -Pattern 'LAUNCH_FINAL_SUMMARY.*final_status=RUN_OK.*exit_code=' -ErrorAction SilentlyContinue | Select-Object -Last 1
  $summaryExitCode = -1
  if ($summary -and $summary.Line -match 'exit_code=(\d+)') {
    $summaryExitCode = [int]$Matches[1]
  }

  return [pscustomobject]@{
    RunOk = $runOk
    NoLaunchError = $noLaunchError
    FailClosed = $failClosed
    SummaryExitCode = $summaryExitCode
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

function New-CleanScenarioResult {
  param(
    [string]$Name,
    [string]$OutFile,
    [object]$InvokeResult,
    [object]$ParseResult,
    [datetime]$RunStart
  )

  return [pscustomobject]@{
    Name = $Name
    OutFile = $OutFile
    GeneratedInRun = ((Get-Item -LiteralPath $OutFile).LastWriteTime -ge $RunStart)
    RunOk = $ParseResult.RunOk
    NoLaunchError = $ParseResult.NoLaunchError
    FailClosed = $ParseResult.FailClosed
    SummaryExitCode = $ParseResult.SummaryExitCode
    TimedOut = $InvokeResult.TimedOut
    FileLock = $InvokeResult.FileLock
    ExitCode = $InvokeResult.ExitCode
  }
}

$runStart = Get-Date
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pfRel = '_proof/phase65_7_widget_operator_cold_warm_consistency_validation_' + $ts
$pf = Join-Path '_proof' ('phase65_7_widget_operator_cold_warm_consistency_validation_' + $ts)
New-Item -ItemType Directory -Force -Path $pf | Out-Null

$checksPath = Join-Path $pf '90_cold_warm_checks.txt'
$contractPath = Join-Path $pf '99_contract_summary.txt'

$cleanArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools\run_widget_sandbox.ps1', '-PassArgs', '--auto-close-ms=1500')
$blockedArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '$env:NGKS_BYPASS_GUARD=''1''; try { & ''tools\run_widget_sandbox.ps1'' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }')
$cleanCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File 'tools\\run_widget_sandbox.ps1' -PassArgs '--auto-close-ms=1500'"
$blockedCmd = "powershell -NoProfile -ExecutionPolicy Bypass -Command `$env:NGKS_BYPASS_GUARD='1'; try { & 'tools\\run_widget_sandbox.ps1' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }"

$coldOut = Join-Path $pf '10_cold_start_clean_stdout.txt'
$coldInvoke = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $coldOut -TimeoutSeconds 60 -StepName 'cold_start_clean' -CommandText $cleanCmd
$coldParsed = Parse-CleanOutput -Path $coldOut
$cold = New-CleanScenarioResult -Name 'cold_start_clean' -OutFile $coldOut -InvokeResult $coldInvoke -ParseResult $coldParsed -RunStart $runStart

$warmResults = @()
for ($warmIndex = 1; $warmIndex -le 3; $warmIndex++) {
  $warmOut = Join-Path $pf ('11_warm_start_clean0' + $warmIndex + '_stdout.txt')
  $warmInvoke = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $warmOut -TimeoutSeconds 60 -StepName ('warm_start_clean_' + $warmIndex) -CommandText $cleanCmd
  $warmParsed = Parse-CleanOutput -Path $warmOut
  $warmResults += New-CleanScenarioResult -Name ('warm_start_clean0' + $warmIndex) -OutFile $warmOut -InvokeResult $warmInvoke -ParseResult $warmParsed -RunStart $runStart
  Start-Sleep -Milliseconds 100
}

$blockedOut = Join-Path $pf '12_blocked_after_warm_stdout.txt'
$blockedInvoke = Invoke-PwshToFile -ArgumentList $blockedArgs -OutFile $blockedOut -TimeoutSeconds 60 -StepName 'blocked_after_warm' -CommandText $blockedCmd
$blockedParsed = Parse-BlockedOutput -Path $blockedOut
$blocked = [pscustomobject]@{
  Name = 'blocked_after_warm'
  OutFile = $blockedOut
  GeneratedInRun = ((Get-Item -LiteralPath $blockedOut).LastWriteTime -ge $runStart)
  HasError = $blockedParsed.HasError
  StatusBlocked = $blockedParsed.StatusBlocked
  FailClosed = $blockedParsed.FailClosed
  ReasonCoherent = $blockedParsed.ReasonCoherent
  ProcessExitOk = $blockedParsed.ProcessExitOk
  SummaryExitCode = $blockedParsed.SummaryExitCode
  TimedOut = $blockedInvoke.TimedOut
  FileLock = $blockedInvoke.FileLock
  ExitCode = $blockedInvoke.ExitCode
}

$finalOut = Join-Path $pf '13_final_clean_recovery_stdout.txt'
$finalInvoke = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $finalOut -TimeoutSeconds 60 -StepName 'final_clean_recovery' -CommandText $cleanCmd
$finalParsed = Parse-CleanOutput -Path $finalOut
$final = New-CleanScenarioResult -Name 'final_clean_recovery' -OutFile $finalOut -InvokeResult $finalInvoke -ParseResult $finalParsed -RunStart $runStart

$allCleanScenarios = @($cold) + @($warmResults) + @($final)
$cleanAllPass = (@($allCleanScenarios | Where-Object { -not ($_.GeneratedInRun -and $_.RunOk -and $_.NoLaunchError -and $_.FailClosed -and (-not $_.TimedOut) -and (-not $_.FileLock) -and ($_.ExitCode -eq 0)) }).Count -eq 0)
$warmAllPass = (@($warmResults | Where-Object { -not ($_.RunOk -and $_.NoLaunchError -and $_.FailClosed -and ($_.ExitCode -eq 0)) }).Count -eq 0)
$blockedPass = ($blocked.GeneratedInRun -and $blocked.HasError -and $blocked.StatusBlocked -and $blocked.FailClosed -and $blocked.ReasonCoherent -and $blocked.ProcessExitOk -and (-not $blocked.TimedOut) -and (-not $blocked.FileLock))

$warmExitSet = @($warmResults | ForEach-Object { [string]$_.ExitCode } | Select-Object -Unique)
$warmSummaryExitSet = @($warmResults | ForEach-Object { [string]$_.SummaryExitCode } | Select-Object -Unique)
$cleanSummaryExitSet = @($allCleanScenarios | ForEach-Object { [string]$_.SummaryExitCode } | Select-Object -Unique)
$noCorrectnessDifference = (
  $cold.RunOk -and
  $cold.NoLaunchError -and
  $cold.FailClosed -and
  ($cold.ExitCode -eq 0) -and
  $warmAllPass -and
  ($warmExitSet.Count -eq 1) -and
  ($warmSummaryExitSet.Count -eq 1) -and
  ($cleanSummaryExitSet.Count -eq 1) -and
  ($cold.SummaryExitCode -eq $warmResults[0].SummaryExitCode) -and
  ($final.SummaryExitCode -eq $cold.SummaryExitCode)
)

Start-Sleep -Milliseconds 300
$widgetProcCount = @((Get-Process -Name 'widget_sandbox' -ErrorAction SilentlyContinue)).Count
$cleanupStable = ($widgetProcCount -eq 0)

$failed = New-Object System.Collections.Generic.List[string]
if (-not $cold.GeneratedInRun) { $failed.Add('check_cold_clean_generated_in_run=NO') }
if (-not $cold.RunOk) { $failed.Add('check_cold_clean_run_ok=NO') }
if (-not $cold.NoLaunchError) { $failed.Add('check_cold_clean_no_launch_error=NO') }
if (-not $cold.FailClosed) { $failed.Add('check_cold_clean_fail_closed=NO') }
if ($cold.TimedOut) { $failed.Add('check_cold_clean_no_hang=NO') }
if ($cold.FileLock) { $failed.Add('check_cold_clean_no_file_lock=NO') }
if ($cold.ExitCode -ne 0) { $failed.Add('check_cold_clean_exit_ok=NO') }
if (-not $warmAllPass) { $failed.Add('check_warm_cleans_all_pass=NO') }
if (-not $blockedPass) { $failed.Add('check_blocked_after_warm_pass=NO') }
if (-not $final.GeneratedInRun) { $failed.Add('check_final_clean_generated_in_run=NO') }
if (-not $final.RunOk) { $failed.Add('check_final_clean_run_ok=NO') }
if (-not $final.NoLaunchError) { $failed.Add('check_final_clean_no_launch_error=NO') }
if (-not $final.FailClosed) { $failed.Add('check_final_clean_fail_closed=NO') }
if ($final.TimedOut) { $failed.Add('check_final_clean_no_hang=NO') }
if ($final.FileLock) { $failed.Add('check_final_clean_no_file_lock=NO') }
if ($final.ExitCode -ne 0) { $failed.Add('check_final_clean_exit_ok=NO') }
if (-not $cleanAllPass) { $failed.Add('check_all_clean_scenarios_pass=NO') }
if (-not $noCorrectnessDifference) { $failed.Add('check_no_material_cold_warm_correctness_difference=NO') }
if (-not $cleanupStable) { $failed.Add('check_cleanup_exit_stable=NO') }

$allOk = ($failed.Count -eq 0)
$regressionsValue = if ($allOk) { 'NO' } else { 'YES' }
$phaseStatusValue = if ($allOk) { 'PASS' } else { 'FAIL' }

$rows = New-Object System.Collections.Generic.List[string]
$rows.Add('proof_folder=' + $pfRel)
$rows.Add('warm_clean_count=' + $warmResults.Count)

$rows.Add('cold_start_clean_file=' + ($pfRel + '/' + [System.IO.Path]::GetFileName($cold.OutFile)))
$rows.Add('cold_start_clean_generated_in_run=' + $(if ($cold.GeneratedInRun) { 'YES' } else { 'NO' }))
$rows.Add('cold_start_clean_final_status_run_ok=' + $(if ($cold.RunOk) { 'YES' } else { 'NO' }))
$rows.Add('cold_start_clean_no_launch_error=' + $(if ($cold.NoLaunchError) { 'YES' } else { 'NO' }))
$rows.Add('cold_start_clean_fail_closed=' + $(if ($cold.FailClosed) { 'YES' } else { 'NO' }))
$rows.Add('cold_start_clean_no_hang=' + $(if (-not $cold.TimedOut) { 'YES' } else { 'NO' }))
$rows.Add('cold_start_clean_exit=' + $cold.ExitCode)
$rows.Add('cold_start_clean_summary_exit_code=' + $cold.SummaryExitCode)

foreach ($warm in $warmResults) {
  $prefix = $warm.Name
  $rows.Add($prefix + '_file=' + ($pfRel + '/' + [System.IO.Path]::GetFileName($warm.OutFile)))
  $rows.Add($prefix + '_generated_in_run=' + $(if ($warm.GeneratedInRun) { 'YES' } else { 'NO' }))
  $rows.Add($prefix + '_final_status_run_ok=' + $(if ($warm.RunOk) { 'YES' } else { 'NO' }))
  $rows.Add($prefix + '_no_launch_error=' + $(if ($warm.NoLaunchError) { 'YES' } else { 'NO' }))
  $rows.Add($prefix + '_fail_closed=' + $(if ($warm.FailClosed) { 'YES' } else { 'NO' }))
  $rows.Add($prefix + '_no_hang=' + $(if (-not $warm.TimedOut) { 'YES' } else { 'NO' }))
  $rows.Add($prefix + '_exit=' + $warm.ExitCode)
  $rows.Add($prefix + '_summary_exit_code=' + $warm.SummaryExitCode)
}

$rows.Add('blocked_after_warm_file=' + ($pfRel + '/' + [System.IO.Path]::GetFileName($blocked.OutFile)))
$rows.Add('blocked_after_warm_generated_in_run=' + $(if ($blocked.GeneratedInRun) { 'YES' } else { 'NO' }))
$rows.Add('blocked_after_warm_launch_error_present=' + $(if ($blocked.HasError) { 'YES' } else { 'NO' }))
$rows.Add('blocked_after_warm_final_status_blocked=' + $(if ($blocked.StatusBlocked) { 'YES' } else { 'NO' }))
$rows.Add('blocked_after_warm_fail_closed=' + $(if ($blocked.FailClosed) { 'YES' } else { 'NO' }))
$rows.Add('blocked_after_warm_reason_coherent=' + $(if ($blocked.ReasonCoherent) { 'YES' } else { 'NO' }))
$rows.Add('blocked_after_warm_process_exit_ok=' + $(if ($blocked.ProcessExitOk) { 'YES' } else { 'NO' }))
$rows.Add('blocked_after_warm_summary_exit_code=' + $blocked.SummaryExitCode)
$rows.Add('blocked_after_warm_no_hang=' + $(if (-not $blocked.TimedOut) { 'YES' } else { 'NO' }))

$rows.Add('final_clean_recovery_file=' + ($pfRel + '/' + [System.IO.Path]::GetFileName($final.OutFile)))
$rows.Add('final_clean_recovery_generated_in_run=' + $(if ($final.GeneratedInRun) { 'YES' } else { 'NO' }))
$rows.Add('final_clean_recovery_final_status_run_ok=' + $(if ($final.RunOk) { 'YES' } else { 'NO' }))
$rows.Add('final_clean_recovery_no_launch_error=' + $(if ($final.NoLaunchError) { 'YES' } else { 'NO' }))
$rows.Add('final_clean_recovery_fail_closed=' + $(if ($final.FailClosed) { 'YES' } else { 'NO' }))
$rows.Add('final_clean_recovery_no_hang=' + $(if (-not $final.TimedOut) { 'YES' } else { 'NO' }))
$rows.Add('final_clean_recovery_exit=' + $final.ExitCode)
$rows.Add('final_clean_recovery_summary_exit_code=' + $final.SummaryExitCode)

$rows.Add('check_all_clean_scenarios_pass=' + $(if ($cleanAllPass) { 'YES' } else { 'NO' }))
$rows.Add('check_warm_cleans_all_pass=' + $(if ($warmAllPass) { 'YES' } else { 'NO' }))
$rows.Add('check_blocked_after_warm_pass=' + $(if ($blockedPass) { 'YES' } else { 'NO' }))
$rows.Add('check_no_material_cold_warm_correctness_difference=' + $(if ($noCorrectnessDifference) { 'YES' } else { 'NO' }))
$rows.Add('check_cleanup_exit_stable=' + $(if ($cleanupStable) { 'YES' } else { 'NO' }))
$rows.Add('clean_summary_exit_codes=' + ($cleanSummaryExitSet -join ','))
$rows.Add('warm_wrapper_exit_codes=' + ($warmExitSet -join ','))
$rows.Add('warm_summary_exit_codes=' + ($warmSummaryExitSet -join ','))
$rows.Add('widget_process_count_after_validation=' + $widgetProcCount)
$rows.Add('failed_check_count=' + $failed.Count)
$rows.Add('failed_checks=' + $(if ($failed.Count -gt 0) { ($failed -join ';') } else { 'NONE' }))
$rows | Set-Content -LiteralPath $checksPath -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) {
  Remove-Item -LiteralPath $zip -Force
}
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

$contractRows = New-Object System.Collections.Generic.List[string]
$contractRows.Add('next_phase_selected=PHASE65_7_WIDGET_OPERATOR_COLD_START_VS_WARM_START_CONSISTENCY_VALIDATION')
$contractRows.Add('objective=Validate operator-path correctness consistency across cold-start clean launch, subsequent warm-start clean launches, blocked launch after warm activity, and final clean recovery after blocked warm path.')
$contractRows.Add('changes_introduced=tools/_tmp_phase65_7_widget_operator_cold_warm_consistency_runner.ps1 (execution cold-start vs warm-start consistency runner only).')
$contractRows.Add('runtime_behavior_changes=NONE')
$contractRows.Add('new_regressions_detected=' + $regressionsValue)
$contractRows.Add('phase_status=' + $phaseStatusValue)
$contractRows.Add('proof_folder=' + $pfRel)
$contractRows | Set-Content -LiteralPath $contractPath -Encoding UTF8

Write-Output ('phase65_7_folder=' + $pfRel)
Write-Output ('phase65_7_status=' + $phaseStatusValue)
Write-Output ('phase65_7_zip=' + $pfRel + '.zip')