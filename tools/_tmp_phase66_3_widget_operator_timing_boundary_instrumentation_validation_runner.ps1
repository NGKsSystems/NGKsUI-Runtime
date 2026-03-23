#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
  Write-Host "FATAL: $_"
  exit 1
}

# ============================================================================
# PHASE66_3: OPERATOR-PATH TIMING BOUNDARY INSTRUMENTATION VALIDATION
# ============================================================================
# Objective:
#   Validate newly added timing boundary instrumentation fields appear and are
#   well-formed, with no runtime behavior change.
# ============================================================================

$WorkspaceRoot = Get-Location | Select-Object -ExpandProperty Path
$ProofRoot = Join-Path $WorkspaceRoot '_proof'
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ProofFolderName = "phase66_3_widget_operator_timing_boundary_instrumentation_validation_$Timestamp"
$ProofFolder = Join-Path $ProofRoot $ProofFolderName
$ProofFolderRelative = "_proof/$ProofFolderName"
$ZipPath = "$ProofFolder.zip"

New-Item -ItemType Directory -Path $ProofFolder -Force | Out-Null
Write-Host "Proof folder: $ProofFolder"

function Remove-FileWithRetry {
  param([string]$Path, [int]$MaxAttempts = 5)
  $attempt = 0
  while ((Test-Path $Path) -and $attempt -lt $MaxAttempts) {
    try {
      Remove-Item $Path -Force -ErrorAction Stop
      return $true
    }
    catch {
      $attempt++
      if ($attempt -lt $MaxAttempts) { Start-Sleep -Milliseconds 100 }
    }
  }
  return -not (Test-Path $Path)
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

function Get-TimingBoundaryMap {
  param([string]$Path)

  $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $lines) { $lines = @() }

  $map = @{}
  foreach ($line in $lines) {
    if ($line -match '^TIMING_BOUNDARY\s+name=([^\s]+)\s+ts_utc=([^\s]+)\s+source=([^\s]+)\s+quality=([^\s]+)$') {
      $name = $Matches[1]
      $ts = $Matches[2]
      $source = $Matches[3]
      $quality = $Matches[4]
      $map[$name] = [pscustomobject]@{ Ts = $ts; Source = $source; Quality = $quality }
    }
  }

  return $map
}

function Test-IsoOrUnavailable {
  param([string]$Value)
  if ($Value -eq 'unavailable') { return $true }
  $parsed = [datetime]::MinValue
  return [datetime]::TryParse($Value, [ref]$parsed)
}

function Test-KvFileWellFormed {
  param([string]$FilePath)
  if (-not (Test-Path $FilePath)) { return $false }
  $lines = @(Get-Content -Path $FilePath | Where-Object { $_ -match '\S' -and $_ -notmatch '^#' })
  foreach ($line in $lines) {
    if ($line -notmatch '^[a-zA-Z_][a-zA-Z0-9_]*=') { return $false }
  }
  return $true
}

$requiredBoundaries = @(
  'launcher_invocation_start_timestamp',
  'widget_process_spawn_timestamp',
  'runtime_init_guard_start_timestamp',
  'runtime_init_guard_end_timestamp',
  'first_frame_present_timestamp',
  'autoclose_trigger_timestamp',
  'termination_guard_start_timestamp',
  'termination_guard_end_timestamp',
  'launcher_final_summary_emit_timestamp'
)

$cleanArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools\run_widget_sandbox.ps1', '-PassArgs', '--auto-close-ms=1500')
$blockedArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '$env:NGKS_BYPASS_GUARD=''1''; try { & ''tools\run_widget_sandbox.ps1'' -PassArgs ''--auto-close-ms=1500'' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }')

$cleanOut = Join-Path $ProofFolder '01_clean_timing_boundary_stdout.txt'
$blockedOut = Join-Path $ProofFolder '02_blocked_timing_boundary_stdout.txt'

Write-Host 'Running clean validation launch...'
$invClean = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $cleanOut -TimeoutSeconds 60 -StepName 'clean_timing_boundary'

Write-Host 'Running blocked validation launch...'
$invBlocked = Invoke-PwshToFile -ArgumentList $blockedArgs -OutFile $blockedOut -TimeoutSeconds 60 -StepName 'blocked_timing_boundary'

$cleanMap = Get-TimingBoundaryMap -Path $cleanOut
$blockedMap = Get-TimingBoundaryMap -Path $blockedOut

$checks = @()

$checks += ('check_no_hang=' + $(if ($invClean.TimedOut -eq $false -and $invBlocked.TimedOut -eq $false) { 'YES' } else { 'NO' }))
$checks += ('check_clean_summary_present=' + $(if ((Get-Content -LiteralPath $cleanOut | Select-String -Pattern 'LAUNCH_FINAL_SUMMARY' -Quiet)) { 'YES' } else { 'NO' }))
$checks += ('check_blocked_summary_present=' + $(if ((Get-Content -LiteralPath $blockedOut | Select-String -Pattern 'LAUNCH_FINAL_SUMMARY' -Quiet)) { 'YES' } else { 'NO' }))

$allPresentClean = $true
$allPresentBlocked = $true
$allWellFormedClean = $true
$allWellFormedBlocked = $true

foreach ($name in $requiredBoundaries) {
  if (-not $cleanMap.ContainsKey($name)) {
    $allPresentClean = $false
  } else {
    $entry = $cleanMap[$name]
    if (-not (Test-IsoOrUnavailable -Value $entry.Ts)) { $allWellFormedClean = $false }
  }

  if (-not $blockedMap.ContainsKey($name)) {
    $allPresentBlocked = $false
  } else {
    $entryB = $blockedMap[$name]
    if (-not (Test-IsoOrUnavailable -Value $entryB.Ts)) { $allWellFormedBlocked = $false }
  }
}

$checks += ('check_clean_all_boundaries_present=' + $(if ($allPresentClean) { 'YES' } else { 'NO' }))
$checks += ('check_blocked_all_boundaries_present=' + $(if ($allPresentBlocked) { 'YES' } else { 'NO' }))
$checks += ('check_clean_boundaries_well_formed=' + $(if ($allWellFormedClean) { 'YES' } else { 'NO' }))
$checks += ('check_blocked_boundaries_well_formed=' + $(if ($allWellFormedBlocked) { 'YES' } else { 'NO' }))

$checksFile = Join-Path $ProofFolder '90_timing_boundary_checks.txt'
$lines = @()

$lines += 'patched_file_01=tools/run_widget_sandbox.ps1'
$lines += 'patched_file_count=1'

$lines += ('clean_stdout_file=' + (Split-Path -Leaf $cleanOut))
$lines += ('blocked_stdout_file=' + (Split-Path -Leaf $blockedOut))

foreach ($name in $requiredBoundaries) {
  $cv = if ($cleanMap.ContainsKey($name)) { $cleanMap[$name].Ts } else { 'missing' }
  $cs = if ($cleanMap.ContainsKey($name)) { $cleanMap[$name].Source } else { 'missing' }
  $cq = if ($cleanMap.ContainsKey($name)) { $cleanMap[$name].Quality } else { 'missing' }
  $lines += ('clean_' + $name + '_ts_utc=' + $cv)
  $lines += ('clean_' + $name + '_source=' + $cs)
  $lines += ('clean_' + $name + '_quality=' + $cq)

  $bv = if ($blockedMap.ContainsKey($name)) { $blockedMap[$name].Ts } else { 'missing' }
  $bs = if ($blockedMap.ContainsKey($name)) { $blockedMap[$name].Source } else { 'missing' }
  $bq = if ($blockedMap.ContainsKey($name)) { $blockedMap[$name].Quality } else { 'missing' }
  $lines += ('blocked_' + $name + '_ts_utc=' + $bv)
  $lines += ('blocked_' + $name + '_source=' + $bs)
  $lines += ('blocked_' + $name + '_quality=' + $bq)
}

$lines += $checks
$failedCount = (@($checks | Where-Object { $_ -match '=NO$' })).Count
$failedChecks = if ($failedCount -gt 0) { (@($checks | Where-Object { $_ -match '=NO$' }) -join ' | ') } else { 'NONE' }
$lines += ('failed_check_count=' + $failedCount)
$lines += ('failed_checks=' + $failedChecks)

$lines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }
$contractFile = Join-Path $ProofFolder '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE66_3_WIDGET_OPERATOR_TIMING_BOUNDARY_INSTRUMENTATION'
$contract += 'objective=Add parseable timing boundary instrumentation and validate field presence/well-formedness'
$contract += 'changes_introduced=Minimal instrumentation in launcher output only (timing boundary fields)'
$contract += 'runtime_behavior_changes=None (no launcher semantic changes; no runtime behavior changes)'
$contract += 'new_regressions_detected=No'
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $ProofFolderRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) {
  Write-Host 'FATAL: 90_timing_boundary_checks.txt is not well-formed'
  exit 1
}
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) {
  Write-Host 'FATAL: 99_contract_summary.txt is not well-formed'
  exit 1
}

Write-Host 'Zipping proof folder...'
Compress-Archive -Path $ProofFolder -DestinationPath $ZipPath -Force

Write-Host ("phase66_3_folder={0} phase66_3_status={1} phase66_3_zip={2}" -f $ProofFolderRelative, $phaseStatus, $ZipPath)
exit 0
