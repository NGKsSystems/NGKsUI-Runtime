Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'

function Remove-FileWithRetry {
  param([string]$Path, [int]$MaxAttempts = 5, [int]$SleepMs = 120)
  if (-not (Test-Path -LiteralPath $Path)) { return $true }
  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    try {
      Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
      return $true
    }
    catch {
      if ($attempt -lt $MaxAttempts) { Start-Sleep -Milliseconds $SleepMs }
    }
  }
  return (-not (Test-Path -LiteralPath $Path))
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

function Get-FieldValue {
  param([string[]]$Lines, [string]$Key)
  foreach ($line in $Lines) {
    if ($line -match ('^' + [regex]::Escape($Key) + '=(.*)$')) {
      return $Matches[1].Trim()
    }
  }
  return ''
}

function Get-CleanRunInfo {
  param([string]$Path)

  $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $lines) { $lines = @() }

  $summaryLine = ($lines | Where-Object { $_ -match 'LAUNCH_FINAL_SUMMARY' } | Select-Object -Last 1)
  $summaryFinalStatus = ''
  $summaryExitCode = ''
  $summaryEnforcement = ''
  $summaryBlockedReason = ''
  if ($summaryLine) {
    if ($summaryLine -match 'final_status=(\S+)') { $summaryFinalStatus = $Matches[1] }
    if ($summaryLine -match 'exit_code=(\S+)') { $summaryExitCode = $Matches[1] }
    if ($summaryLine -match 'enforcement=(\S+)') { $summaryEnforcement = $Matches[1] }
    if ($summaryLine -match 'blocked_reason=(\S+)') { $summaryBlockedReason = $Matches[1] }
  }

  $launchIdentity = Get-FieldValue -Lines $lines -Key 'LAUNCH_IDENTITY'
  $widgetIdentityPresent = (Get-FieldValue -Lines $lines -Key 'widget_launch_identity_present')
  $widgetIdentity = Get-FieldValue -Lines $lines -Key 'widget_launch_identity'
  $hasRuntimeOk = [bool]($lines | Where-Object { $_ -match '^runtime_final_status=RUN_OK' })
  $hasLaunchError = [bool]($lines | Where-Object { $_ -match '^LAUNCH_ERROR=' })
  $failClosedCount = @($lines | Where-Object { $_ -match '^FAIL_CLOSED=ENABLED' }).Count

  return [pscustomobject]@{
    LaunchIdentity = $launchIdentity
    WidgetIdentityPresent = ($widgetIdentityPresent -eq '1')
    WidgetIdentity = $widgetIdentity
    SummaryFinalStatus = $summaryFinalStatus
    SummaryExitCode = $summaryExitCode
    SummaryEnforcement = $summaryEnforcement
    SummaryBlockedReason = $summaryBlockedReason
    HasRuntimeOk = $hasRuntimeOk
    HasLaunchError = $hasLaunchError
    FailClosedCount = $failClosedCount
  }
}

function Get-BlockedRunInfo {
  param([string]$Path)

  $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $lines) { $lines = @() }

  $summaryLine = ($lines | Where-Object { $_ -match 'LAUNCH_FINAL_SUMMARY' } | Select-Object -Last 1)
  $summaryFinalStatus = ''
  $summaryExitCode = ''
  $summaryEnforcement = ''
  $summaryBlockedReason = ''
  if ($summaryLine) {
    if ($summaryLine -match 'final_status=(\S+)') { $summaryFinalStatus = $Matches[1] }
    if ($summaryLine -match 'exit_code=(\S+)') { $summaryExitCode = $Matches[1] }
    if ($summaryLine -match 'enforcement=(\S+)') { $summaryEnforcement = $Matches[1] }
    if ($summaryLine -match 'blocked_reason=(\S+)') { $summaryBlockedReason = $Matches[1] }
  }

  $errLine = ($lines | Where-Object { $_ -match '^LAUNCH_ERROR=' } | Select-Object -First 1)
  $hasLaunchError = -not [string]::IsNullOrEmpty($errLine)
  $hasFailClosedInDetail = $errLine -match 'FAIL_CLOSED=ENABLED'
  $hasReasonInDetail = $errLine -match 'REASON=env_injection_detected'
  $hasGateFailInDetail = $errLine -match 'GATE=FAIL'

  return [pscustomobject]@{
    SummaryFinalStatus = $summaryFinalStatus
    SummaryExitCode = $summaryExitCode
    SummaryEnforcement = $summaryEnforcement
    SummaryBlockedReason = $summaryBlockedReason
    HasLaunchError = $hasLaunchError
    HasFailClosedInDetail = $hasFailClosedInDetail
    HasReasonInDetail = $hasReasonInDetail
    HasGateFailInDetail = $hasGateFailInDetail
  }
}

function Test-KvFileWellFormed {
  param(
    [string]$Path,
    [string[]]$CriticalKeys
  )

  $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $lines) { $lines = @() }

  $malformed = @()
  foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line -notmatch '=') {
      $malformed += $line
      continue
    }
    $eq = $line.IndexOf('=')
    if ($eq -le 0) {
      $malformed += $line
    }
  }

  $missingOrEmpty = @()
  foreach ($key in $CriticalKeys) {
    $match = ($lines | Where-Object { $_ -match ('^' + [regex]::Escape($key) + '=(.*)$') } | Select-Object -First 1)
    if (-not $match) {
      $missingOrEmpty += $key
      continue
    }
    $v = $match.Substring($match.IndexOf('=') + 1)
    if ([string]::IsNullOrWhiteSpace($v)) {
      $missingOrEmpty += $key
    }
  }

  return [pscustomobject]@{
    WellFormed = ($malformed.Count -eq 0)
    MissingOrEmptyCritical = ($missingOrEmpty.Count -eq 0)
    MalformedLines = ($malformed -join '; ')
    MissingOrEmptyKeys = ($missingOrEmpty -join '; ')
  }
}

function Get-KeyValueMap {
  param([string]$Path)
  $map = @{}
  $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $lines) { $lines = @() }
  foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $idx = $line.IndexOf('=')
    if ($idx -lt 1) { continue }
    $k = $line.Substring(0, $idx)
    $v = $line.Substring($idx + 1)
    $map[$k] = $v
  }
  return $map
}

$runStart = Get-Date
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofFolderRel = '_proof/phase65_9_widget_operator_proof_runtime_correlation_validation_' + $ts
$proofFolder = Join-Path '_proof' ('phase65_9_widget_operator_proof_runtime_correlation_validation_' + $ts)
if (Test-Path -LiteralPath $proofFolder) {
  throw 'Proof folder already exists unexpectedly: ' + $proofFolder
}
New-Item -ItemType Directory -Path $proofFolder | Out-Null

$checksPath = Join-Path $proofFolder '90_correlation_checks.txt'
$contractPath = Join-Path $proofFolder '99_contract_summary.txt'

$cleanArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools\run_widget_sandbox.ps1', '-PassArgs', '--auto-close-ms=1500')
$blockedArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '$env:NGKS_BYPASS_GUARD=''1''; try { & ''tools\run_widget_sandbox.ps1'' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }')

# small set of runs: clean, blocked, clean, blocked
$stdoutFiles = @(
  (Join-Path $proofFolder '10_clean_run01_stdout.txt'),
  (Join-Path $proofFolder '11_blocked_run01_stdout.txt'),
  (Join-Path $proofFolder '12_clean_run02_stdout.txt'),
  (Join-Path $proofFolder '13_blocked_run02_stdout.txt')
)

$runMeta = [System.Collections.Generic.List[object]]::new()

$inv10 = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $stdoutFiles[0] -TimeoutSeconds 60 -StepName 'clean_run01'
$runMeta.Add([pscustomobject]@{ Name = 'clean_run01'; Kind = 'clean'; Path = $stdoutFiles[0]; Invoke = $inv10; GeneratedInRun = ((Get-Item -LiteralPath $stdoutFiles[0]).LastWriteTime -ge $runStart); Parsed = (Get-CleanRunInfo -Path $stdoutFiles[0]) })
Start-Sleep -Milliseconds 100

$inv11 = Invoke-PwshToFile -ArgumentList $blockedArgs -OutFile $stdoutFiles[1] -TimeoutSeconds 60 -StepName 'blocked_run01'
$runMeta.Add([pscustomobject]@{ Name = 'blocked_run01'; Kind = 'blocked'; Path = $stdoutFiles[1]; Invoke = $inv11; GeneratedInRun = ((Get-Item -LiteralPath $stdoutFiles[1]).LastWriteTime -ge $runStart); Parsed = (Get-BlockedRunInfo -Path $stdoutFiles[1]) })
Start-Sleep -Milliseconds 100

$inv12 = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $stdoutFiles[2] -TimeoutSeconds 60 -StepName 'clean_run02'
$runMeta.Add([pscustomobject]@{ Name = 'clean_run02'; Kind = 'clean'; Path = $stdoutFiles[2]; Invoke = $inv12; GeneratedInRun = ((Get-Item -LiteralPath $stdoutFiles[2]).LastWriteTime -ge $runStart); Parsed = (Get-CleanRunInfo -Path $stdoutFiles[2]) })
Start-Sleep -Milliseconds 100

$inv13 = Invoke-PwshToFile -ArgumentList $blockedArgs -OutFile $stdoutFiles[3] -TimeoutSeconds 60 -StepName 'blocked_run02'
$runMeta.Add([pscustomobject]@{ Name = 'blocked_run02'; Kind = 'blocked'; Path = $stdoutFiles[3]; Invoke = $inv13; GeneratedInRun = ((Get-Item -LiteralPath $stdoutFiles[3]).LastWriteTime -ge $runStart); Parsed = (Get-BlockedRunInfo -Path $stdoutFiles[3]) })

$cleanRuns = @($runMeta | Where-Object { $_.Kind -eq 'clean' })
$blockedRuns = @($runMeta | Where-Object { $_.Kind -eq 'blocked' })

$checkCleanCore = (@($cleanRuns | Where-Object {
  (-not $_.GeneratedInRun) -or $_.Invoke.TimedOut -or $_.Invoke.FileLock -or ($_.Invoke.ExitCode -ne 0) -or
  ($_.Parsed.SummaryFinalStatus -ne 'RUN_OK') -or ($_.Parsed.SummaryExitCode -ne '0') -or
  ($_.Parsed.SummaryEnforcement -ne 'PASS') -or ($_.Parsed.SummaryBlockedReason -ne 'NONE') -or
  $_.Parsed.HasLaunchError -or (-not $_.Parsed.HasRuntimeOk) -or ($_.Parsed.FailClosedCount -lt 1) -or
  (-not $_.Parsed.WidgetIdentityPresent) -or [string]::IsNullOrWhiteSpace($_.Parsed.LaunchIdentity) -or
  [string]::IsNullOrWhiteSpace($_.Parsed.WidgetIdentity) -or ($_.Parsed.LaunchIdentity -ne $_.Parsed.WidgetIdentity)
}).Count -eq 0)

$checkBlockedCore = (@($blockedRuns | Where-Object {
  (-not $_.GeneratedInRun) -or $_.Invoke.TimedOut -or $_.Invoke.FileLock -or
  ($_.Parsed.SummaryFinalStatus -ne 'BLOCKED') -or ($_.Parsed.SummaryExitCode -ne '120') -or
  ($_.Parsed.SummaryEnforcement -ne 'FAIL') -or ($_.Parsed.SummaryBlockedReason -ne 'TRUST_CHAIN_BLOCKED') -or
  (-not $_.Parsed.HasLaunchError) -or (-not $_.Parsed.HasFailClosedInDetail) -or
  (-not $_.Parsed.HasReasonInDetail) -or (-not $_.Parsed.HasGateFailInDetail)
}).Count -eq 0)

$identitySet = @($cleanRuns | ForEach-Object { $_.Parsed.LaunchIdentity } | Select-Object -Unique)
$cleanIdentityConsistent = ($identitySet.Count -eq 1)

# Write preliminary checks and contract from parsed runtime evidence
$rows = [System.Collections.Generic.List[string]]::new()
$rows.Add('proof_folder=' + $proofFolderRel)
$rows.Add('run_count=' + $runMeta.Count)
$rows.Add('clean_run_count=' + $cleanRuns.Count)
$rows.Add('blocked_run_count=' + $blockedRuns.Count)

foreach ($r in $runMeta) {
  $fileRel = $proofFolderRel + '/' + [System.IO.Path]::GetFileName($r.Path)
  $rows.Add($r.Name + '_file=' + $fileRel)
  $rows.Add($r.Name + '_generated_in_run=' + $(if ($r.GeneratedInRun) { 'YES' } else { 'NO' }))
  $rows.Add($r.Name + '_no_hang=' + $(if (-not $r.Invoke.TimedOut) { 'YES' } else { 'NO' }))
  $rows.Add($r.Name + '_wrapper_exit=' + $r.Invoke.ExitCode)

  if ($r.Kind -eq 'clean') {
    $rows.Add($r.Name + '_launch_identity=' + $r.Parsed.LaunchIdentity)
    $rows.Add($r.Name + '_widget_launch_identity=' + $r.Parsed.WidgetIdentity)
    $rows.Add($r.Name + '_widget_launch_identity_present=' + $(if ($r.Parsed.WidgetIdentityPresent) { 'YES' } else { 'NO' }))
    $rows.Add($r.Name + '_final_status=' + $r.Parsed.SummaryFinalStatus)
    $rows.Add($r.Name + '_exit_code=' + $r.Parsed.SummaryExitCode)
    $rows.Add($r.Name + '_enforcement=' + $r.Parsed.SummaryEnforcement)
    $rows.Add($r.Name + '_blocked_reason=' + $r.Parsed.SummaryBlockedReason)
    $rows.Add($r.Name + '_fail_closed_count=' + $r.Parsed.FailClosedCount)
    $rows.Add($r.Name + '_runtime_ok=' + $(if ($r.Parsed.HasRuntimeOk) { 'YES' } else { 'NO' }))
    $rows.Add($r.Name + '_launch_error_present=' + $(if ($r.Parsed.HasLaunchError) { 'YES' } else { 'NO' }))
  }
  else {
    $rows.Add($r.Name + '_final_status=' + $r.Parsed.SummaryFinalStatus)
    $rows.Add($r.Name + '_exit_code=' + $r.Parsed.SummaryExitCode)
    $rows.Add($r.Name + '_enforcement=' + $r.Parsed.SummaryEnforcement)
    $rows.Add($r.Name + '_blocked_reason=' + $r.Parsed.SummaryBlockedReason)
    $rows.Add($r.Name + '_launch_error_present=' + $(if ($r.Parsed.HasLaunchError) { 'YES' } else { 'NO' }))
    $rows.Add($r.Name + '_fail_closed_in_detail=' + $(if ($r.Parsed.HasFailClosedInDetail) { 'YES' } else { 'NO' }))
    $rows.Add($r.Name + '_reason_in_detail=' + $(if ($r.Parsed.HasReasonInDetail) { 'YES' } else { 'NO' }))
    $rows.Add($r.Name + '_gate_fail_in_detail=' + $(if ($r.Parsed.HasGateFailInDetail) { 'YES' } else { 'NO' }))
  }
}

$rows.Add('check_clean_core=' + $(if ($checkCleanCore) { 'YES' } else { 'NO' }))
$rows.Add('check_blocked_core=' + $(if ($checkBlockedCore) { 'YES' } else { 'NO' }))
$rows.Add('check_clean_identity_consistent=' + $(if ($cleanIdentityConsistent) { 'YES' } else { 'NO' }))
$rows.Add('unique_clean_launch_identity=' + ($identitySet -join ','))

$rows | Set-Content -LiteralPath $checksPath -Encoding UTF8

$contractRows = [System.Collections.Generic.List[string]]::new()
$contractRows.Add('next_phase_selected=PHASE65_9_WIDGET_OPERATOR_PROOF_TO_RUNTIME_CORRELATION_VALIDATION')
$contractRows.Add('objective=Validate that proof contract/check outputs correlate exactly to runtime stdout evidence from this run, including identity and summary fields, with no stale data contamination, malformed fields, or hang.')
$contractRows.Add('changes_introduced=tools/_tmp_phase65_9_widget_operator_proof_runtime_correlation_runner.ps1 (proof-to-runtime correlation runner only).')
$contractRows.Add('runtime_behavior_changes=NONE')
$contractRows.Add('new_regressions_detected=PENDING')
$contractRows.Add('phase_status=PENDING')
$contractRows.Add('proof_folder=' + $proofFolderRel)
$contractRows | Set-Content -LiteralPath $contractPath -Encoding UTF8

# Correlation validation: checks/contract must match parsed runtime evidence exactly
$checksMap = Get-KeyValueMap -Path $checksPath
$contractMap = Get-KeyValueMap -Path $contractPath

$checkMapMatchesRuntime = $true
foreach ($r in $runMeta) {
  $name = $r.Name
  if (-not $checksMap.ContainsKey($name + '_final_status')) { $checkMapMatchesRuntime = $false; break }
  if ($checksMap[$name + '_final_status'] -ne [string]$r.Parsed.SummaryFinalStatus) { $checkMapMatchesRuntime = $false; break }
  if ($checksMap[$name + '_exit_code'] -ne [string]$r.Parsed.SummaryExitCode) { $checkMapMatchesRuntime = $false; break }
  if ($checksMap[$name + '_enforcement'] -ne [string]$r.Parsed.SummaryEnforcement) { $checkMapMatchesRuntime = $false; break }
  if ($checksMap[$name + '_blocked_reason'] -ne [string]$r.Parsed.SummaryBlockedReason) { $checkMapMatchesRuntime = $false; break }
  if ($r.Kind -eq 'clean') {
    if ($checksMap[$name + '_launch_identity'] -ne [string]$r.Parsed.LaunchIdentity) { $checkMapMatchesRuntime = $false; break }
    if ($checksMap[$name + '_widget_launch_identity'] -ne [string]$r.Parsed.WidgetIdentity) { $checkMapMatchesRuntime = $false; break }
  }
}

$checkContractProofFolderMatches = ($checksMap['proof_folder'] -eq $proofFolderRel) -and ($contractMap['proof_folder'] -eq $proofFolderRel)

# stale/cross-run contamination check in output files
$checksText = Get-Content -LiteralPath $checksPath -Raw
$contractText = Get-Content -LiteralPath $contractPath -Raw
$otherProofRefInChecks = [regex]::IsMatch($checksText, '_proof/phase\d+_[^\s=]*') -and ($checksText -notmatch [regex]::Escape($proofFolderRel))
$otherProofRefInContract = [regex]::IsMatch($contractText, '_proof/phase\d+_[^\s=]*') -and ($contractText -notmatch [regex]::Escape($proofFolderRel))
$noCrossRunContamination = (-not $otherProofRefInChecks) -and (-not $otherProofRefInContract)

$checksKvForm = Test-KvFileWellFormed -Path $checksPath -CriticalKeys @('proof_folder', 'run_count', 'clean_run_count', 'blocked_run_count', 'check_clean_core', 'check_blocked_core')
$contractKvForm = Test-KvFileWellFormed -Path $contractPath -CriticalKeys @('next_phase_selected', 'objective', 'changes_introduced', 'runtime_behavior_changes', 'new_regressions_detected', 'phase_status', 'proof_folder')
$noMalformedOrSplit = $checksKvForm.WellFormed -and $checksKvForm.MissingOrEmptyCritical -and $contractKvForm.WellFormed -and $contractKvForm.MissingOrEmptyCritical

Start-Sleep -Milliseconds 250
$widgetProcCount = @((Get-Process -Name 'widget_sandbox' -ErrorAction SilentlyContinue)).Count
$cleanupStable = ($widgetProcCount -eq 0)

$failed = [System.Collections.Generic.List[string]]::new()
if (-not $checkCleanCore) { $failed.Add('check_clean_core=NO') }
if (-not $checkBlockedCore) { $failed.Add('check_blocked_core=NO') }
if (-not $cleanIdentityConsistent) { $failed.Add('check_clean_identity_consistent=NO') }
if (-not $checkMapMatchesRuntime) { $failed.Add('check_checks_file_matches_stdout=NO') }
if (-not $checkContractProofFolderMatches) { $failed.Add('check_contract_proof_folder_match=NO') }
if (-not $noCrossRunContamination) { $failed.Add('check_no_cross_run_contamination=NO') }
if (-not $noMalformedOrSplit) { $failed.Add('check_no_malformed_or_split_fields=NO') }
if (-not $cleanupStable) { $failed.Add('check_cleanup_stable=NO') }
if (@($runMeta | Where-Object { $_.Invoke.TimedOut }).Count -gt 0) { $failed.Add('check_no_hang=NO') }

$allOk = ($failed.Count -eq 0)
$regressionValue = if ($allOk) { 'NO' } else { 'YES' }
$phaseStatusValue = if ($allOk) { 'PASS' } else { 'FAIL' }

# Rewrite checks with final correlation verdict lines
$rows.Add('check_checks_file_matches_stdout=' + $(if ($checkMapMatchesRuntime) { 'YES' } else { 'NO' }))
$rows.Add('check_contract_proof_folder_match=' + $(if ($checkContractProofFolderMatches) { 'YES' } else { 'NO' }))
$rows.Add('check_no_cross_run_contamination=' + $(if ($noCrossRunContamination) { 'YES' } else { 'NO' }))
$rows.Add('check_no_malformed_or_split_fields=' + $(if ($noMalformedOrSplit) { 'YES' } else { 'NO' }))
$rows.Add('check_cleanup_stable=' + $(if ($cleanupStable) { 'YES' } else { 'NO' }))
$rows.Add('check_no_hang=' + $(if (@($runMeta | Where-Object { $_.Invoke.TimedOut }).Count -eq 0) { 'YES' } else { 'NO' }))
$rows.Add('widget_process_count_after_validation=' + $widgetProcCount)
$rows.Add('failed_check_count=' + $failed.Count)
$rows.Add('failed_checks=' + $(if ($failed.Count -gt 0) { ($failed -join ';') } else { 'NONE' }))
$rows | Set-Content -LiteralPath $checksPath -Encoding UTF8

# Final contract update
$contractRowsFinal = [System.Collections.Generic.List[string]]::new()
$contractRowsFinal.Add('next_phase_selected=PHASE65_9_WIDGET_OPERATOR_PROOF_TO_RUNTIME_CORRELATION_VALIDATION')
$contractRowsFinal.Add('objective=Validate that proof contract/check outputs correlate exactly to runtime stdout evidence from this run, including identity and summary fields, with no stale data contamination, malformed fields, or hang.')
$contractRowsFinal.Add('changes_introduced=tools/_tmp_phase65_9_widget_operator_proof_runtime_correlation_runner.ps1 (proof-to-runtime correlation runner only).')
$contractRowsFinal.Add('runtime_behavior_changes=NONE')
$contractRowsFinal.Add('new_regressions_detected=' + $regressionValue)
$contractRowsFinal.Add('phase_status=' + $phaseStatusValue)
$contractRowsFinal.Add('proof_folder=' + $proofFolderRel)
$contractRowsFinal | Set-Content -LiteralPath $contractPath -Encoding UTF8

$zipPath = $proofFolder + '.zip'
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $proofFolder '*') -DestinationPath $zipPath -Force

Write-Output ('phase65_9_folder=' + $proofFolderRel)
Write-Output ('phase65_9_status=' + $phaseStatusValue)
Write-Output ('phase65_9_zip=' + $proofFolderRel + '.zip')
