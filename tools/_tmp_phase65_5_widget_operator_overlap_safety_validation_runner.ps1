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

function Start-Launch {
  param(
    [string[]]$ArgumentList,
    [string]$OutFile,
    [string]$StepName,
    [string]$CommandText
  )

  $errFile = $OutFile + '.stderr.tmp'
  if (-not (Remove-FileWithRetry -Path $errFile)) {
    return [pscustomobject]@{
      StartFailed = $true
      ExitCode = 125
      TimedOut = $false
      FileLock = $true
      LockedFile = $errFile
      OutFile = $OutFile
      ErrFile = $errFile
      StepName = $StepName
      CommandText = $CommandText
      Process = $null
    }
  }

  $proc = Start-Process -FilePath 'powershell' -ArgumentList $ArgumentList -PassThru -NoNewWindow -RedirectStandardOutput $OutFile -RedirectStandardError $errFile
  return [pscustomobject]@{
    StartFailed = $false
    ExitCode = 0
    TimedOut = $false
    FileLock = $false
    LockedFile = ''
    OutFile = $OutFile
    ErrFile = $errFile
    StepName = $StepName
    CommandText = $CommandText
    Process = $proc
  }
}

function Finalize-Launch {
  param(
    [pscustomobject]$Launch,
    [int]$TimeoutSeconds
  )

  if ($Launch.StartFailed) {
    return $Launch
  }

  $timedOut = -not $Launch.Process.WaitForExit($TimeoutSeconds * 1000)
  if ($timedOut) {
    try { $Launch.Process.Kill() } catch {}
    Add-Content -LiteralPath $Launch.OutFile -Value ('LAUNCH_ERROR=TIMEOUT step=' + $Launch.StepName + ' timeout_seconds=' + $TimeoutSeconds)
    $Launch.TimedOut = $true
    $Launch.ExitCode = 124
  }
  else {
    $Launch.Process.WaitForExit()
    $Launch.ExitCode = $Launch.Process.ExitCode
  }

  try { $Launch.Process.Close() } catch {}
  try { $Launch.Process.Dispose() } catch {}

  if (Test-Path -LiteralPath $Launch.ErrFile) {
    $stderr = Get-Content -LiteralPath $Launch.ErrFile -Raw
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
      Add-Content -LiteralPath $Launch.OutFile -Value $stderr
    }
    if (-not (Remove-FileWithRetry -Path $Launch.ErrFile)) {
      $Launch.FileLock = $true
      $Launch.LockedFile = $Launch.ErrFile
      if ($Launch.ExitCode -eq 0) {
        $Launch.ExitCode = 125
      }
    }
  }

  return $Launch
}

function Parse-CleanOutput {
  param([string]$Path)

  $runOk = [bool](Select-String -Path $Path -Pattern 'LAUNCH_FINAL_SUMMARY.*final_status=RUN_OK' -ErrorAction SilentlyContinue)
  $noLaunchError = -not [bool](Select-String -Path $Path -Pattern '^LAUNCH_ERROR=' -ErrorAction SilentlyContinue)
  $failClosed = [bool](Select-String -Path $Path -Pattern '^FAIL_CLOSED=ENABLED' -ErrorAction SilentlyContinue)
  $poisoned = [bool](Select-String -Path $Path -Pattern 'final_status=BLOCKED|blocked_reason=TRUST_CHAIN_BLOCKED|runtime_trust_guard_failed' -ErrorAction SilentlyContinue)

  return [pscustomobject]@{
    RunOk = $runOk
    NoLaunchError = $noLaunchError
    FailClosed = $failClosed
    NoPoisonedState = (-not $poisoned)
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
$pfRel = '_proof/phase65_5_widget_operator_overlap_safety_validation_' + $ts
$pf = Join-Path '_proof' ('phase65_5_widget_operator_overlap_safety_validation_' + $ts)
New-Item -ItemType Directory -Force -Path $pf | Out-Null

$checksPath = Join-Path $pf '90_overlap_checks.txt'
$contractPath = Join-Path $pf '99_contract_summary.txt'

$cleanArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools\run_widget_sandbox.ps1', '-PassArgs', '--auto-close-ms=1500')
$blockedArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '$env:NGKS_BYPASS_GUARD=''1''; try { & ''tools\run_widget_sandbox.ps1'' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }')
$cleanCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File 'tools\\run_widget_sandbox.ps1' -PassArgs '--auto-close-ms=1500'"
$blockedCmd = "powershell -NoProfile -ExecutionPolicy Bypass -Command `$env:NGKS_BYPASS_GUARD='1'; try { & 'tools\\run_widget_sandbox.ps1' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }"

$scenarioResults = New-Object System.Collections.Generic.List[object]

function Run-OverlapScenario {
  param(
    [string]$Name,
    [pscustomobject[]]$LaunchSpecs,
    [int]$TimeoutSeconds
  )

  $started = @()
  foreach ($spec in $LaunchSpecs) {
    $started += Start-Launch -ArgumentList $spec.Args -OutFile $spec.OutFile -StepName $spec.StepName -CommandText $spec.CommandText
  }

  $finalized = @()
  foreach ($l in $started) {
    $finalized += Finalize-Launch -Launch $l -TimeoutSeconds $TimeoutSeconds
  }

  return [pscustomobject]@{
    Name = $Name
    Launches = $finalized
  }
}

# Scenario 1: clean + clean overlap
$s1a = Join-Path $pf '10_s1_clean_a_stdout.txt'
$s1b = Join-Path $pf '11_s1_clean_b_stdout.txt'
$scenarioResults.Add((Run-OverlapScenario -Name 's1_clean_clean_overlap' -LaunchSpecs @(
  [pscustomobject]@{ Args = $cleanArgs; OutFile = $s1a; StepName = 's1_clean_a'; CommandText = $cleanCmd },
  [pscustomobject]@{ Args = $cleanArgs; OutFile = $s1b; StepName = 's1_clean_b'; CommandText = $cleanCmd }
) -TimeoutSeconds 60))

# Scenario 2: blocked + clean overlap
$s2a = Join-Path $pf '12_s2_blocked_stdout.txt'
$s2b = Join-Path $pf '13_s2_clean_stdout.txt'
$scenarioResults.Add((Run-OverlapScenario -Name 's2_blocked_clean_overlap' -LaunchSpecs @(
  [pscustomobject]@{ Args = $blockedArgs; OutFile = $s2a; StepName = 's2_blocked'; CommandText = $blockedCmd },
  [pscustomobject]@{ Args = $cleanArgs; OutFile = $s2b; StepName = 's2_clean'; CommandText = $cleanCmd }
) -TimeoutSeconds 60))

# Scenario 3: blocked + blocked overlap
$s3a = Join-Path $pf '14_s3_blocked_a_stdout.txt'
$s3b = Join-Path $pf '15_s3_blocked_b_stdout.txt'
$scenarioResults.Add((Run-OverlapScenario -Name 's3_blocked_blocked_overlap' -LaunchSpecs @(
  [pscustomobject]@{ Args = $blockedArgs; OutFile = $s3a; StepName = 's3_blocked_a'; CommandText = $blockedCmd },
  [pscustomobject]@{ Args = $blockedArgs; OutFile = $s3b; StepName = 's3_blocked_b'; CommandText = $blockedCmd }
) -TimeoutSeconds 60))

# Scenario 4: post-overlap clean verification
$s4 = Join-Path $pf '16_s4_post_overlap_clean_stdout.txt'
$s4Launch = Start-Launch -ArgumentList $cleanArgs -OutFile $s4 -StepName 's4_post_overlap_clean' -CommandText $cleanCmd
$s4Final = Finalize-Launch -Launch $s4Launch -TimeoutSeconds 60

$failed = New-Object System.Collections.Generic.List[string]
$rows = New-Object System.Collections.Generic.List[string]
$rows.Add('proof_folder=' + $pfRel)

foreach ($scenario in $scenarioResults) {
  foreach ($launch in $scenario.Launches) {
    $fileName = [System.IO.Path]::GetFileName($launch.OutFile)
    $prefix = $fileName.Replace('.txt', '')

    $generatedInRun = (Get-Item -LiteralPath $launch.OutFile).LastWriteTime -ge $runStart
    $noHang = (-not $launch.TimedOut)
    $noFileLock = (-not $launch.FileLock)

    $rows.Add($prefix + '_file=' + ($pfRel + '/' + $fileName))
    $rows.Add($prefix + '_generated_in_run=' + $(if ($generatedInRun) { 'YES' } else { 'NO' }))
    $rows.Add($prefix + '_no_hang=' + $(if ($noHang) { 'YES' } else { 'NO' }))
    $rows.Add($prefix + '_no_file_lock=' + $(if ($noFileLock) { 'YES' } else { 'NO' }))

    if (-not $generatedInRun) { $failed.Add('check_' + $prefix + '_generated_in_run=NO') }
    if (-not $noHang) { $failed.Add('check_' + $prefix + '_no_hang=NO') }
    if (-not $noFileLock) { $failed.Add('check_' + $prefix + '_no_file_lock=NO') }

    $isBlockedScenario = $prefix -match 'blocked'
    if ($isBlockedScenario) {
      $parsed = Parse-BlockedOutput -Path $launch.OutFile
      $rows.Add($prefix + '_launch_error_present=' + $(if ($parsed.HasError) { 'YES' } else { 'NO' }))
      $rows.Add($prefix + '_final_status_blocked=' + $(if ($parsed.StatusBlocked) { 'YES' } else { 'NO' }))
      $rows.Add($prefix + '_fail_closed=' + $(if ($parsed.FailClosed) { 'YES' } else { 'NO' }))
      $rows.Add($prefix + '_reason_coherent=' + $(if ($parsed.ReasonCoherent) { 'YES' } else { 'NO' }))
      $rows.Add($prefix + '_process_exit_ok=' + $(if ($parsed.ProcessExitOk) { 'YES' } else { 'NO' }))
      $rows.Add($prefix + '_summary_exit_code=' + $parsed.SummaryExitCode)

      if (-not $parsed.HasError) { $failed.Add('check_' + $prefix + '_launch_error_present=NO') }
      if (-not $parsed.StatusBlocked) { $failed.Add('check_' + $prefix + '_final_status_blocked=NO') }
      if (-not $parsed.FailClosed) { $failed.Add('check_' + $prefix + '_fail_closed=NO') }
      if (-not $parsed.ReasonCoherent) { $failed.Add('check_' + $prefix + '_reason_coherent=NO') }
      if (-not $parsed.ProcessExitOk) { $failed.Add('check_' + $prefix + '_process_exit_ok=NO') }
    }
    else {
      $parsed = Parse-CleanOutput -Path $launch.OutFile
      $rows.Add($prefix + '_final_status_run_ok=' + $(if ($parsed.RunOk) { 'YES' } else { 'NO' }))
      $rows.Add($prefix + '_no_launch_error=' + $(if ($parsed.NoLaunchError) { 'YES' } else { 'NO' }))
      $rows.Add($prefix + '_fail_closed=' + $(if ($parsed.FailClosed) { 'YES' } else { 'NO' }))
      $rows.Add($prefix + '_no_poisoned_state=' + $(if ($parsed.NoPoisonedState) { 'YES' } else { 'NO' }))
      $rows.Add($prefix + '_wrapper_exit=' + $launch.ExitCode)

      if (-not $parsed.RunOk) { $failed.Add('check_' + $prefix + '_final_status_run_ok=NO') }
      if (-not $parsed.NoLaunchError) { $failed.Add('check_' + $prefix + '_no_launch_error=NO') }
      if (-not $parsed.FailClosed) { $failed.Add('check_' + $prefix + '_fail_closed=NO') }
      if (-not $parsed.NoPoisonedState) { $failed.Add('check_' + $prefix + '_no_poisoned_state=NO') }
      if ($launch.ExitCode -ne 0) { $failed.Add('check_' + $prefix + '_wrapper_exit=NONZERO') }
    }
  }
}

# Explicit post-overlap clean check to ensure no poisoned state accumulation after all overlaps.
$s4Prefix = '16_s4_post_overlap_clean_stdout'
$s4Generated = (Get-Item -LiteralPath $s4Final.OutFile).LastWriteTime -ge $runStart
$s4Parsed = Parse-CleanOutput -Path $s4Final.OutFile
$rows.Add($s4Prefix + '_file=' + ($pfRel + '/' + [System.IO.Path]::GetFileName($s4Final.OutFile)))
$rows.Add($s4Prefix + '_generated_in_run=' + $(if ($s4Generated) { 'YES' } else { 'NO' }))
$rows.Add($s4Prefix + '_final_status_run_ok=' + $(if ($s4Parsed.RunOk) { 'YES' } else { 'NO' }))
$rows.Add($s4Prefix + '_no_launch_error=' + $(if ($s4Parsed.NoLaunchError) { 'YES' } else { 'NO' }))
$rows.Add($s4Prefix + '_fail_closed=' + $(if ($s4Parsed.FailClosed) { 'YES' } else { 'NO' }))
$rows.Add($s4Prefix + '_no_poisoned_state=' + $(if ($s4Parsed.NoPoisonedState) { 'YES' } else { 'NO' }))
$rows.Add($s4Prefix + '_no_hang=' + $(if (-not $s4Final.TimedOut) { 'YES' } else { 'NO' }))
$rows.Add($s4Prefix + '_wrapper_exit=' + $s4Final.ExitCode)

if (-not $s4Generated) { $failed.Add('check_s4_generated_in_run=NO') }
if (-not $s4Parsed.RunOk) { $failed.Add('check_s4_final_status_run_ok=NO') }
if (-not $s4Parsed.NoLaunchError) { $failed.Add('check_s4_no_launch_error=NO') }
if (-not $s4Parsed.FailClosed) { $failed.Add('check_s4_fail_closed=NO') }
if (-not $s4Parsed.NoPoisonedState) { $failed.Add('check_s4_no_poisoned_state=NO') }
if ($s4Final.TimedOut) { $failed.Add('check_s4_no_hang=NO') }
if ($s4Final.ExitCode -ne 0) { $failed.Add('check_s4_wrapper_exit=NONZERO') }
if ($s4Final.FileLock) { $failed.Add('check_s4_no_file_lock=NO') }

Start-Sleep -Milliseconds 300
$widgetProcCount = @((Get-Process -Name 'widget_sandbox' -ErrorAction SilentlyContinue)).Count
$cleanupStable = ($widgetProcCount -eq 0)
$rows.Add('check_cleanup_exit_stable=' + $(if ($cleanupStable) { 'YES' } else { 'NO' }))
$rows.Add('widget_process_count_after_scenarios=' + $widgetProcCount)
if (-not $cleanupStable) { $failed.Add('check_cleanup_exit_stable=NO') }

$allOk = ($failed.Count -eq 0)
$rows.Add('failed_check_count=' + $failed.Count)
$rows.Add('failed_checks=' + $(if ($failed.Count -gt 0) { ($failed -join ';') } else { 'NONE' }))
$rows | Set-Content -LiteralPath $checksPath -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) {
  Remove-Item -LiteralPath $zip -Force
}
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

@(
  'next_phase_selected=PHASE65_5_WIDGET_OPERATOR_CONCURRENCY_OVERLAP_SAFETY_VALIDATION',
  'objective=Validate operator-path overlap safety by executing clean+clean, blocked+clean, and blocked+blocked overlapping launches, then confirming post-overlap clean health with no poisoned state.',
  'changes_introduced=tools/_tmp_phase65_5_widget_operator_overlap_safety_validation_runner.ps1 (execution overlap safety runner only).',
  'runtime_behavior_changes=NONE',
  'new_regressions_detected=' + $(if ($allOk) { 'NO' } else { 'YES' }),
  'phase_status=' + $(if ($allOk) { 'PASS' } else { 'FAIL' }),
  'proof_folder=' + $pfRel
) | Set-Content -LiteralPath $contractPath -Encoding UTF8

Write-Output ('phase65_5_folder=' + $pfRel)
Write-Output ('phase65_5_status=' + $(if ($allOk) { 'PASS' } else { 'FAIL' }))
Write-Output ('phase65_5_zip=' + $pfRel + '.zip')
