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
      StepName = $StepName
      CommandText = $CommandText
      OutFile = $OutFile
      FileLock = $true
      LockedFile = $errFile
    }
  }

  $proc = Start-Process -FilePath 'powershell' -ArgumentList $ArgumentList -PassThru -NoNewWindow -RedirectStandardOutput $OutFile -RedirectStandardError $errFile
  $timedOut = -not $proc.WaitForExit($TimeoutSeconds * 1000)
  if ($timedOut) {
    try {
      $proc.Kill()
    } catch {
    }
    Add-Content -LiteralPath $OutFile -Value ('LAUNCH_ERROR=TIMEOUT step=' + $StepName + ' timeout_seconds=' + $TimeoutSeconds)
    if (Test-Path -LiteralPath $errFile) {
      Get-Content -LiteralPath $errFile | Add-Content -LiteralPath $OutFile
      $cleanupOk = Remove-FileWithRetry -Path $errFile
      if (-not $cleanupOk) {
        return [pscustomobject]@{
          ExitCode = 125
          TimedOut = $true
          StepName = $StepName
          CommandText = $CommandText
          OutFile = $OutFile
          FileLock = $true
          LockedFile = $errFile
        }
      }
    }
    return [pscustomobject]@{
      ExitCode = 124
      TimedOut = $true
      StepName = $StepName
      CommandText = $CommandText
      OutFile = $OutFile
      FileLock = $false
      LockedFile = ''
    }
  }

  # Ensure redirected output/error streams are fully flushed and underlying handles can be released.
  $proc.WaitForExit()
  try {
    $proc.Close()
  }
  catch {
  }
  $proc.Dispose()

  if (Test-Path -LiteralPath $errFile) {
    $stderr = Get-Content -LiteralPath $errFile -Raw
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
      Add-Content -LiteralPath $OutFile -Value $stderr
    }
    $cleanupOk = Remove-FileWithRetry -Path $errFile
    if (-not $cleanupOk) {
      return [pscustomobject]@{
        ExitCode = 125
        TimedOut = $false
        StepName = $StepName
        CommandText = $CommandText
        OutFile = $OutFile
        FileLock = $true
        LockedFile = $errFile
      }
    }
  }

  return [pscustomobject]@{
    ExitCode = $proc.ExitCode
    TimedOut = $false
    StepName = $StepName
    CommandText = $CommandText
    OutFile = $OutFile
    FileLock = $false
    LockedFile = ''
  }
}

$runStart = Get-Date
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path '_proof' ('phase63_1_operator_summary_integrity_isolated_' + $ts)
New-Item -ItemType Directory -Force -Path $pf | Out-Null

$cleanOut = Join-Path $pf '10_widget_clean_stdout.txt'
$blockedOut = Join-Path $pf '11_widget_blocked_stdout.txt'

$cleanCommandText = "powershell -NoProfile -ExecutionPolicy Bypass -File 'tools\\run_widget_sandbox.ps1' -PassArgs '--auto-close-ms=1500'"
$cleanResult = Invoke-PwshToFile -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools\run_widget_sandbox.ps1', '-PassArgs', '--auto-close-ms=1500') -OutFile $cleanOut -TimeoutSeconds 45 -StepName 'clean_widget_launcher' -CommandText $cleanCommandText
$cleanExit = $cleanResult.ExitCode

$blockedCommandText = "powershell -NoProfile -ExecutionPolicy Bypass -Command `$env:NGKS_BYPASS_GUARD='1'; try { & 'tools\\run_widget_sandbox.ps1' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }"
$blockedResult = Invoke-PwshToFile -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '$env:NGKS_BYPASS_GUARD=''1''; try { & ''tools\run_widget_sandbox.ps1'' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }') -OutFile $blockedOut -TimeoutSeconds 45 -StepName 'blocked_widget_launcher' -CommandText $blockedCommandText
$blockedExit = $blockedResult.ExitCode

$cleanHasSummary = [bool](Select-String -Path $cleanOut -Pattern 'LAUNCH_FINAL_SUMMARY.*final_status=RUN_OK' -ErrorAction SilentlyContinue)
$blockedHasError = [bool](Select-String -Path $blockedOut -Pattern '^LAUNCH_ERROR=' -ErrorAction SilentlyContinue)
$blockedHasSummary = [bool](Select-String -Path $blockedOut -Pattern 'LAUNCH_FINAL_SUMMARY.*final_status=BLOCKED' -ErrorAction SilentlyContinue)

$cleanGeneratedInRun = (Get-Item -LiteralPath $cleanOut).LastWriteTime -ge $runStart
$blockedGeneratedInRun = (Get-Item -LiteralPath $blockedOut).LastWriteTime -ge $runStart

$checksPath = Join-Path $pf '90_phase63_1_operator_summary_checks.txt'
@(
  'proof_folder=' + $pf,
  'evidence_clean_file=' + $cleanOut,
  'evidence_blocked_file=' + $blockedOut,
  'generated_in_run_clean=' + $(if($cleanGeneratedInRun){'YES'}else{'NO'}),
  'generated_in_run_blocked=' + $(if($blockedGeneratedInRun){'YES'}else{'NO'}),
  'check_widget_clean_summary=' + $(if($cleanHasSummary){'YES'}else{'NO'}),
  'check_widget_blocked_error=' + $(if($blockedHasError){'YES'}else{'NO'}),
  'check_widget_blocked_summary=' + $(if($blockedHasSummary){'YES'}else{'NO'}),
  'clean_file_lock=' + $(if($cleanResult.FileLock){'YES'}else{'NO'}),
  'blocked_file_lock=' + $(if($blockedResult.FileLock){'YES'}else{'NO'}),
  'clean_timed_out=' + $(if($cleanResult.TimedOut){'YES'}else{'NO'}),
  'blocked_timed_out=' + $(if($blockedResult.TimedOut){'YES'}else{'NO'}),
  'widget_clean_exit=' + $cleanExit,
  'widget_blocked_exit=' + $blockedExit
) | Set-Content -LiteralPath $checksPath -Encoding UTF8

$allOk = $cleanGeneratedInRun -and $blockedGeneratedInRun -and $cleanHasSummary -and $blockedHasError -and $blockedHasSummary -and (-not $cleanResult.FileLock) -and (-not $blockedResult.FileLock)

$blockingStep = 'NONE'
$blockingCommand = 'NONE'
$blockingFile = 'NONE'
if (-not $allOk) {
  if ($cleanResult.FileLock) {
    $blockingStep = 'file_lock'
    $blockingCommand = 'Remove-Item -LiteralPath $errFile -Force (retry exhausted)'
    $blockingFile = $cleanResult.LockedFile
  } elseif ($blockedResult.FileLock) {
    $blockingStep = 'file_lock'
    $blockingCommand = 'Remove-Item -LiteralPath $errFile -Force (retry exhausted)'
    $blockingFile = $blockedResult.LockedFile
  } elseif ($cleanResult.TimedOut) {
    $blockingStep = $cleanResult.StepName
    $blockingCommand = $cleanResult.CommandText
    $blockingFile = $cleanResult.OutFile
  } elseif ($blockedResult.TimedOut) {
    $blockingStep = $blockedResult.StepName
    $blockingCommand = $blockedResult.CommandText
    $blockingFile = $blockedResult.OutFile
  } elseif (-not $cleanHasSummary) {
    $blockingStep = 'clean_summary_check'
    $blockingCommand = $cleanCommandText
    $blockingFile = $cleanOut
  } elseif (-not $blockedHasError) {
    $blockingStep = 'blocked_error_check'
    $blockingCommand = $blockedCommandText
    $blockingFile = $blockedOut
  } elseif (-not $blockedHasSummary) {
    $blockingStep = 'blocked_summary_check'
    $blockingCommand = $blockedCommandText
    $blockingFile = $blockedOut
  }
}

$contractPath = Join-Path $pf '99_phase63_1_contract_summary.txt'
@(
  'next_phase_selected=PHASE63_1_OPERATOR_SUMMARY_INTEGRITY_ISOLATED',
  'objective=Run fresh isolated operator summary integrity validation for widget launcher clean and blocked paths with in-run evidence provenance.',
  'changes_introduced=NONE',
  'runtime_behavior_changes=NONE',
  'new_regressions_detected=' + $(if($allOk){'NO'}else{'YES'}),
  'phase_status=' + $(if($allOk){'PASS'}else{'FAIL'}),
  'proof_folder=' + $pf,
  'blocking_step=' + $blockingStep,
  'blocking_command=' + $blockingCommand,
  'blocking_file=' + $blockingFile
) | Set-Content -LiteralPath $contractPath -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) {
  Remove-Item -LiteralPath $zip -Force
}
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('phase63_1_folder=' + $pf)
Write-Output ('phase63_1_status=' + $(if($allOk){'PASS'}else{'FAIL'}))
Write-Output ('phase63_1_zip=' + $zip)
