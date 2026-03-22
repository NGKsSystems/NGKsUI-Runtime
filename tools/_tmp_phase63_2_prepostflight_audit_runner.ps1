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
    }
    catch {
    }

    Add-Content -LiteralPath $OutFile -Value ('LAUNCH_ERROR=TIMEOUT step=' + $StepName + ' timeout_seconds=' + $TimeoutSeconds)
    if (Test-Path -LiteralPath $errFile) {
      Get-Content -LiteralPath $errFile | Add-Content -LiteralPath $OutFile
      if (-not (Remove-FileWithRetry -Path $errFile)) {
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

function Write-HashReport {
  param(
    [string[]]$Files,
    [string]$OutFile
  )

  $rows = New-Object System.Collections.Generic.List[string]
  foreach ($f in $Files) {
    if (Test-Path -LiteralPath $f) {
      $h = Get-FileHash -LiteralPath $f -Algorithm SHA256
      $rows.Add(($f + '|sha256=' + $h.Hash))
    }
    else {
      $rows.Add(($f + '|sha256=MISSING'))
    }
  }

  $rows | Set-Content -LiteralPath $OutFile -Encoding UTF8
}

$runStart = Get-Date
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path '_proof' ('phase63_2_operator_prepostflight_audit_' + $ts)
New-Item -ItemType Directory -Force -Path $pf | Out-Null

$cleanOut = Join-Path $pf '10_widget_clean_stdout.txt'
$blockedOut = Join-Path $pf '11_widget_blocked_stdout.txt'
$preflightPath = Join-Path $pf '00_preflight_snapshot.txt'
$preflightHashPath = Join-Path $pf '01_preflight_hashes.txt'
$postflightHashPath = Join-Path $pf '91_postflight_hashes.txt'
$postflightPath = Join-Path $pf '92_postflight_snapshot.txt'
$checksPath = Join-Path $pf '90_phase63_2_operator_prepostflight_checks.txt'
$contractPath = Join-Path $pf '99_phase63_2_contract_summary.txt'

$auditFiles = @(
  'tools\run_widget_sandbox.ps1',
  'tools\run_sandbox_app.ps1',
  'tools\widget_sandbox_launch_common.ps1'
)

@(
  'phase=PHASE63_2_OPERATOR_PREPOSTFLIGHT_AUDIT',
  'run_start_utc=' + (Get-Date).ToUniversalTime().ToString('o'),
  'cwd=' + (Get-Location).Path,
  'proof_folder=' + $pf
) | Set-Content -LiteralPath $preflightPath -Encoding UTF8

Write-HashReport -Files $auditFiles -OutFile $preflightHashPath

$cleanCommandText = "powershell -NoProfile -ExecutionPolicy Bypass -File 'tools\\run_widget_sandbox.ps1' -PassArgs '--auto-close-ms=1500'"
$cleanResult = Invoke-PwshToFile -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools\run_widget_sandbox.ps1', '-PassArgs', '--auto-close-ms=1500') -OutFile $cleanOut -TimeoutSeconds 45 -StepName 'clean_widget_launcher' -CommandText $cleanCommandText

$blockedCommandText = "powershell -NoProfile -ExecutionPolicy Bypass -Command `$env:NGKS_BYPASS_GUARD='1'; try { & 'tools\\run_widget_sandbox.ps1' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }"
$blockedResult = Invoke-PwshToFile -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '$env:NGKS_BYPASS_GUARD=''1''; try { & ''tools\run_widget_sandbox.ps1'' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }') -OutFile $blockedOut -TimeoutSeconds 45 -StepName 'blocked_widget_launcher' -CommandText $blockedCommandText

Write-HashReport -Files $auditFiles -OutFile $postflightHashPath
@(
  'run_end_utc=' + (Get-Date).ToUniversalTime().ToString('o'),
  'proof_folder=' + $pf
) | Set-Content -LiteralPath $postflightPath -Encoding UTF8

$cleanHasSummary = [bool](Select-String -Path $cleanOut -Pattern 'LAUNCH_FINAL_SUMMARY.*final_status=RUN_OK' -ErrorAction SilentlyContinue)
$blockedHasError = [bool](Select-String -Path $blockedOut -Pattern '^LAUNCH_ERROR=' -ErrorAction SilentlyContinue)
$blockedHasSummary = [bool](Select-String -Path $blockedOut -Pattern 'LAUNCH_FINAL_SUMMARY.*final_status=BLOCKED' -ErrorAction SilentlyContinue)
$preflightExists = Test-Path -LiteralPath $preflightPath
$postflightExists = Test-Path -LiteralPath $postflightPath

$preHashes = @()
$postHashes = @()
if (Test-Path -LiteralPath $preflightHashPath) {
  $preHashes = Get-Content -LiteralPath $preflightHashPath
}
if (Test-Path -LiteralPath $postflightHashPath) {
  $postHashes = Get-Content -LiteralPath $postflightHashPath
}
$hashesStable = (($preHashes -join "`n") -eq ($postHashes -join "`n"))

$cleanGeneratedInRun = (Get-Item -LiteralPath $cleanOut).LastWriteTime -ge $runStart
$blockedGeneratedInRun = (Get-Item -LiteralPath $blockedOut).LastWriteTime -ge $runStart

@(
  'proof_folder=' + $pf,
  'evidence_clean_file=' + $cleanOut,
  'evidence_blocked_file=' + $blockedOut,
  'generated_in_run_clean=' + $(if ($cleanGeneratedInRun) { 'YES' } else { 'NO' }),
  'generated_in_run_blocked=' + $(if ($blockedGeneratedInRun) { 'YES' } else { 'NO' }),
  'check_widget_clean_summary=' + $(if ($cleanHasSummary) { 'YES' } else { 'NO' }),
  'check_widget_blocked_error=' + $(if ($blockedHasError) { 'YES' } else { 'NO' }),
  'check_widget_blocked_summary=' + $(if ($blockedHasSummary) { 'YES' } else { 'NO' }),
  'check_preflight_exists=' + $(if ($preflightExists) { 'YES' } else { 'NO' }),
  'check_postflight_exists=' + $(if ($postflightExists) { 'YES' } else { 'NO' }),
  'check_hashes_stable=' + $(if ($hashesStable) { 'YES' } else { 'NO' }),
  'clean_file_lock=' + $(if ($cleanResult.FileLock) { 'YES' } else { 'NO' }),
  'blocked_file_lock=' + $(if ($blockedResult.FileLock) { 'YES' } else { 'NO' }),
  'clean_timed_out=' + $(if ($cleanResult.TimedOut) { 'YES' } else { 'NO' }),
  'blocked_timed_out=' + $(if ($blockedResult.TimedOut) { 'YES' } else { 'NO' }),
  'widget_clean_exit=' + $cleanResult.ExitCode,
  'widget_blocked_exit=' + $blockedResult.ExitCode
) | Set-Content -LiteralPath $checksPath -Encoding UTF8

$allOk = $cleanGeneratedInRun -and $blockedGeneratedInRun -and $cleanHasSummary -and $blockedHasError -and $blockedHasSummary -and $preflightExists -and $postflightExists -and $hashesStable -and (-not $cleanResult.FileLock) -and (-not $blockedResult.FileLock)

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) {
  Remove-Item -LiteralPath $zip -Force
}
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

@(
  'next_phase_selected=PHASE63_2_OPERATOR_PREPOSTFLIGHT_AUDIT',
  'objective=Add deterministic preflight and postflight provenance evidence around operator-path launcher summary checks without runtime semantics changes.',
  'changes_introduced=tools/_tmp_phase63_2_prepostflight_audit_runner.ps1 (new audit-only phase runner with preflight/postflight snapshots and hash-stability checks).',
  'runtime_behavior_changes=NONE',
  'new_regressions_detected=' + $(if ($allOk) { 'NO' } else { 'YES' }),
  'phase_status=' + $(if ($allOk) { 'PASS' } else { 'FAIL' }),
  'proof_folder=' + $pf
) | Set-Content -LiteralPath $contractPath -Encoding UTF8

Write-Output ('phase63_2_folder=' + $pf)
Write-Output ('phase63_2_status=' + $(if ($allOk) { 'PASS' } else { 'FAIL' }))
Write-Output ('phase63_2_zip=' + $zip)
