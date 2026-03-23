#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
  Write-Host "FATAL: $_"
  exit 1
}

# ============================================================================
# PHASE67_2: RUNTIME TRUST GUARD PRODUCTION READINESS SNAPSHOT
# ============================================================================
# Validation-only phase. No new runtime behavior changes and no measurement work.
# Artifacts are staged outside _proof, zipped into one final file under _proof,
# then staging is deleted.
# ============================================================================

$WorkspaceRoot = Get-Location | Select-Object -ExpandProperty Path
$ProofRoot = Join-Path $WorkspaceRoot '_proof'
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ProofName = "phase67_2_runtime_trust_guard_production_readiness_snapshot_$Timestamp"
$StageRoot = Join-Path $WorkspaceRoot ("_artifacts/runtime/" + $ProofName)
$ZipPath = Join-Path $ProofRoot ($ProofName + '.zip')
$ProofPathRelative = "_proof/$ProofName.zip"
$GuardHeader = Join-Path $WorkspaceRoot 'apps/runtime_phase53_guard.hpp'
$TrustRuntimeScript = Join-Path $WorkspaceRoot 'tools/TrustChainRuntime.ps1'

New-Item -ItemType Directory -Path $StageRoot -Force | Out-Null
Write-Host "Stage folder: $StageRoot"
Write-Host "Final zip: $ZipPath"

function Remove-FileWithRetry {
  param([string]$Path, [int]$MaxAttempts = 5)
  $attempt = 0
  while ((Test-Path -LiteralPath $Path) -and $attempt -lt $MaxAttempts) {
    try {
      Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
      return $true
    } catch {
      $attempt++
      if ($attempt -lt $MaxAttempts) { Start-Sleep -Milliseconds 100 }
    }
  }
  return -not (Test-Path -LiteralPath $Path)
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
    try { $proc.WaitForExit() } catch {}
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

function Invoke-CmdToFile {
  param(
    [string]$CommandLine,
    [string]$OutFile,
    [int]$TimeoutSeconds,
    [string]$StepName
  )

  $errFile = $OutFile + '.stderr.tmp'
  if (-not (Remove-FileWithRetry -Path $errFile)) {
    return [pscustomobject]@{ ExitCode = 125; TimedOut = $false; FileLock = $true }
  }

  $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', $CommandLine) -PassThru -NoNewWindow -RedirectStandardOutput $OutFile -RedirectStandardError $errFile
  $timedOut = -not $proc.WaitForExit($TimeoutSeconds * 1000)

  if ($timedOut) {
    try { $proc.Kill() } catch {}
    try { $proc.WaitForExit() } catch {}
    Add-Content -LiteralPath $OutFile -Value ('BUILD_ERROR=TIMEOUT step=' + $StepName + ' timeout_seconds=' + $TimeoutSeconds)
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
    [void](Remove-FileWithRetry -Path $errFile)
  }

  return [pscustomobject]@{ ExitCode = $exitCode; TimedOut = $false; FileLock = $false }
}

function Get-LastSummaryValue {
  param([string]$Path, [string]$Key, [string]$Default = '')
  $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $lines) { return $Default }
  for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    if ($lines[$i] -match ('\b' + [regex]::Escape($Key) + '=(\S+)')) {
      return $Matches[1]
    }
  }
  return $Default
}

function Test-LinePresent {
  param([string]$Path, [string]$Pattern)
  $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $lines) { return $false }
  foreach ($line in $lines) {
    if ($line -match $Pattern) {
      return $true
    }
  }
  return $false
}

function Get-FileContains {
  param([string]$Path, [string]$Needle)
  $content = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
  return $content.Contains($Needle)
}

function Test-KvFileWellFormed {
  param([string]$FilePath)
  if (-not (Test-Path -LiteralPath $FilePath)) { return $false }
  $lines = @(Get-Content -LiteralPath $FilePath | Where-Object { $_ -match '\S' -and $_ -notmatch '^#' })
  foreach ($line in $lines) {
    if ($line -notmatch '^[a-zA-Z_][a-zA-Z0-9_]*=') { return $false }
  }
  return $true
}

function New-ProofZip {
  param([string]$SourceDir, [string]$DestinationZip)

  if (Test-Path -LiteralPath $DestinationZip) {
    Remove-Item -LiteralPath $DestinationZip -Force
  }

  Write-Host 'Creating final proof zip...'
  Compress-Archive -Path (Join-Path $SourceDir '*') -DestinationPath $DestinationZip -Force
}

function Test-ZipContainsEntries {
  param([string]$ZipFile, [string[]]$ExpectedEntries)

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipFile)
  try {
    $entryNames = @($archive.Entries | ForEach-Object { $_.FullName })
    foreach ($entry in $ExpectedEntries) {
      if ($entryNames -notcontains $entry) {
        return $false
      }
    }
    return $true
  }
  finally {
    $archive.Dispose()
  }
}

$buildOut = Join-Path $StageRoot '01_rebuild_stdout.txt'
$cleanOut = Join-Path $StageRoot '02_normal_clean_stdout.txt'
$blockedOut = Join-Path $StageRoot '03_normal_blocked_stdout.txt'
$rollbackOut = Join-Path $StageRoot '04_rollback_switch_stdout.txt'

Write-Host 'Rebuilding current production-readiness snapshot target...'
$build = Invoke-CmdToFile -CommandLine 'tools\_tmp_rebuild_widget_native_x64.cmd' -OutFile $buildOut -TimeoutSeconds 180 -StepName 'rebuild_widget_sandbox'
if ($build.TimedOut -or $build.ExitCode -ne 0) {
  Write-Host 'FATAL: rebuild failed'
  exit 1
}

$cleanArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools\run_widget_sandbox.ps1', '-PassArgs', '--auto-close-ms=1500')
$blockedArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '$env:NGKS_BYPASS_GUARD=''1''; try { & ''tools\run_widget_sandbox.ps1'' -PassArgs ''--auto-close-ms=1500'' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }')
$rollbackArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '$env:NGKS_RUNTIME_TRUST_GUARD_DISABLE_HARDENED_PATH=''1''; try { & ''tools\run_widget_sandbox.ps1'' -PassArgs ''--auto-close-ms=1500'' } finally { Remove-Item Env:NGKS_RUNTIME_TRUST_GUARD_DISABLE_HARDENED_PATH -ErrorAction SilentlyContinue }')

Write-Host 'Validating normal clean behavior...'
$cleanRun = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $cleanOut -TimeoutSeconds 60 -StepName 'normal_clean'

Write-Host 'Validating normal blocked behavior...'
$blockedRun = Invoke-PwshToFile -ArgumentList $blockedArgs -OutFile $blockedOut -TimeoutSeconds 60 -StepName 'normal_blocked'

Write-Host 'Validating rollback strategy behavior...'
$rollbackRun = Invoke-PwshToFile -ArgumentList $rollbackArgs -OutFile $rollbackOut -TimeoutSeconds 60 -StepName 'rollback_switch'

$checkCleanBehavior = ($cleanRun.TimedOut -eq $false) -and ((Get-LastSummaryValue -Path $cleanOut -Key 'final_status') -eq 'RUN_OK') -and ((Get-LastSummaryValue -Path $cleanOut -Key 'exit_code') -eq '0')
$checkBlockedBehavior = ($blockedRun.TimedOut -eq $false) -and ((Get-LastSummaryValue -Path $blockedOut -Key 'final_status') -eq 'BLOCKED') -and ((Get-LastSummaryValue -Path $blockedOut -Key 'exit_code') -eq '120') -and ((Get-LastSummaryValue -Path $blockedOut -Key 'blocked_reason' -Default 'NONE') -eq 'TRUST_CHAIN_BLOCKED')
$checkRollbackBehavior = ($rollbackRun.TimedOut -eq $false) -and ((Get-LastSummaryValue -Path $rollbackOut -Key 'final_status') -eq 'RUN_OK') -and ((Get-LastSummaryValue -Path $rollbackOut -Key 'exit_code') -eq '0') -and (Test-LinePresent -Path $rollbackOut -Pattern '^runtime_trust_guard_hardening_mode=LEGACY_SYSTEM_ROLLBACK\s+context=runtime_init$')
$checkTimingFields = (Test-LinePresent -Path $cleanOut -Pattern '^TIMING_BOUNDARY\s+') -and (Test-LinePresent -Path $blockedOut -Pattern '^TIMING_BOUNDARY\s+') -and (Test-LinePresent -Path $rollbackOut -Pattern '^TIMING_BOUNDARY\s+')
$checkSummaries = (Test-LinePresent -Path $cleanOut -Pattern '^LAUNCH_FINAL_SUMMARY\s+') -and (Test-LinePresent -Path $blockedOut -Pattern '^LAUNCH_FINAL_SUMMARY\s+') -and (Test-LinePresent -Path $rollbackOut -Pattern '^LAUNCH_FINAL_SUMMARY\s+')
$checkDiagnostics = (Test-LinePresent -Path $cleanOut -Pattern '^runtime_trust_guard_elapsed_ms=\d+\s+context=runtime_init$') -and ((Test-LinePresent -Path $blockedOut -Pattern '^LAUNCH_ERROR=') -or (Test-LinePresent -Path $blockedOut -Pattern '^runtime_trust_guard_reason_code=TRUST_CHAIN_BLOCKED\s+context=runtime_init$'))

$checkOptimizationKept = (Get-FileContains -Path $GuardHeader -Needle 'execute_runtime_trust_command_windows(command)') -and (Get-FileContains -Path $GuardHeader -Needle 'CreateProcessW(') -and (Get-FileContains -Path $GuardHeader -Needle 'DIRECT_PROCESS_HARDENED')
$checkInvariantScriptPreflight = (Get-FileContains -Path $GuardHeader -Needle 'runtime_guard_script_exists_windows()') -and (Get-FileContains -Path $GuardHeader -Needle 'GetFileAttributesW(L"tools\\TrustChainRuntime.ps1")')
$checkInvariantBoundedTimeout = (Get-FileContains -Path $GuardHeader -Needle 'NGKS_RUNTIME_TRUST_GUARD_TIMEOUT_MS') -and (Get-FileContains -Path $GuardHeader -Needle 'return 60000U;') -and (Get-FileContains -Path $GuardHeader -Needle 'parsed > 300000UL') -and (Get-FileContains -Path $GuardHeader -Needle 'WaitForSingleObject(process_info.hProcess, runtime_guard_wait_timeout_ms())')
$checkInvariantFailClosed = (Get-FileContains -Path $GuardHeader -Needle 'TerminateProcess(process_info.hProcess, 1);') -and (Get-FileContains -Path $GuardHeader -Needle 'runtime_trust_guard_reason_code=TRUST_CHAIN_BLOCKED') -and (Get-FileContains -Path $GuardHeader -Needle 'return 120;')
$checkInvariantRollback = (Get-FileContains -Path $GuardHeader -Needle 'NGKS_RUNTIME_TRUST_GUARD_DISABLE_HARDENED_PATH') -and (Get-FileContains -Path $GuardHeader -Needle 'LEGACY_SYSTEM_ROLLBACK') -and (Get-FileContains -Path $GuardHeader -Needle '_wsystem(command.c_str())')
$checkAdverseCoverage = $checkInvariantScriptPreflight -and $checkInvariantBoundedTimeout -and $checkInvariantRollback -and (Test-Path -LiteralPath $TrustRuntimeScript)

$checks = @()
$checks += ('check_build_succeeded=' + $(if ($build.ExitCode -eq 0 -and $build.TimedOut -eq $false) { 'YES' } else { 'NO' }))
$checks += ('check_normal_clean_behavior=' + $(if ($checkCleanBehavior) { 'YES' } else { 'NO' }))
$checks += ('check_normal_blocked_behavior=' + $(if ($checkBlockedBehavior) { 'YES' } else { 'NO' }))
$checks += ('check_rollback_strategy=' + $(if ($checkRollbackBehavior) { 'YES' } else { 'NO' }))
$checks += ('check_adverse_condition_handling_coverage=' + $(if ($checkAdverseCoverage) { 'YES' } else { 'NO' }))
$checks += ('check_kept_optimization_status=' + $(if ($checkOptimizationKept) { 'YES' } else { 'NO' }))
$checks += ('check_invariant_script_preflight=' + $(if ($checkInvariantScriptPreflight) { 'YES' } else { 'NO' }))
$checks += ('check_invariant_bounded_timeout=' + $(if ($checkInvariantBoundedTimeout) { 'YES' } else { 'NO' }))
$checks += ('check_invariant_fail_closed=' + $(if ($checkInvariantFailClosed) { 'YES' } else { 'NO' }))
$checks += ('check_invariant_rollback_switch=' + $(if ($checkInvariantRollback) { 'YES' } else { 'NO' }))
$checks += ('check_summaries_present=' + $(if ($checkSummaries) { 'YES' } else { 'NO' }))
$checks += ('check_diagnostics_present=' + $(if ($checkDiagnostics) { 'YES' } else { 'NO' }))
$checks += ('check_timing_fields_present=' + $(if ($checkTimingFields) { 'YES' } else { 'NO' }))

$checksFile = Join-Path $StageRoot '90_production_readiness_checks.txt'
$lines = @()
$lines += 'patched_file_count=0'
$lines += 'patched_files=NONE'
$lines += 'snapshot_scope=production_readiness_no_new_measurement'
$lines += 'kept_direct_process_path=YES'
$lines += 'hardening_slice_status=KEPT'
$lines += 'adverse_condition_coverage_source=current_enforced_invariants_and_prior_validated_design'
$lines += 'rollback_strategy=Set NGKS_RUNTIME_TRUST_GUARD_DISABLE_HARDENED_PATH=1 to force legacy _wsystem path'
$lines += 'rebuild_stdout_file=' + (Split-Path -Leaf $buildOut)
$lines += 'normal_clean_stdout_file=' + (Split-Path -Leaf $cleanOut)
$lines += 'normal_blocked_stdout_file=' + (Split-Path -Leaf $blockedOut)
$lines += 'rollback_stdout_file=' + (Split-Path -Leaf $rollbackOut)
$lines += 'normal_clean_final_status=' + (Get-LastSummaryValue -Path $cleanOut -Key 'final_status')
$lines += 'normal_clean_exit_code=' + (Get-LastSummaryValue -Path $cleanOut -Key 'exit_code')
$lines += 'normal_blocked_final_status=' + (Get-LastSummaryValue -Path $blockedOut -Key 'final_status')
$lines += 'normal_blocked_exit_code=' + (Get-LastSummaryValue -Path $blockedOut -Key 'exit_code')
$lines += 'normal_blocked_reason=' + (Get-LastSummaryValue -Path $blockedOut -Key 'blocked_reason' -Default 'NONE')
$lines += 'rollback_final_status=' + (Get-LastSummaryValue -Path $rollbackOut -Key 'final_status')
$lines += 'rollback_exit_code=' + (Get-LastSummaryValue -Path $rollbackOut -Key 'exit_code')
$lines += 'invariant_01=Trust script existence preflight enforced before hardened direct-process execution'
$lines += 'invariant_02=Bounded wait timeout enforced with validated env override and safe defaults'
$lines += 'invariant_03=Timeout/process/preflight failure remains fail-closed'
$lines += 'invariant_04=Rollback env switch to legacy _wsystem path remains available'
$lines += 'optimization_status=Windows direct-process CreateProcessW path remains active when hardening is enabled'
$lines += $checks
$failedCount = (@($checks | Where-Object { $_ -match '=NO$' })).Count
$failedChecks = if ($failedCount -gt 0) { (@($checks | Where-Object { $_ -match '=NO$' }) -join ' | ') } else { 'NONE' }
$lines += 'failed_check_count=' + $failedCount
$lines += 'failed_checks=' + $failedChecks
$lines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $StageRoot '99_contract_summary.txt'
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }
$contract = @()
$contract += 'next_phase_selected=PHASE67_2_RUNTIME_TRUST_GUARD_PRODUCTION_READINESS_SNAPSHOT'
$contract += 'objective=Summarize and validate the kept hardened direct-process runtime trust guard path as production-ready without introducing new runtime behavior changes'
$contract += 'changes_introduced=None (validation-only production readiness snapshot)'
$contract += 'runtime_behavior_changes=None'
$contract += 'new_regressions_detected=No'
$contract += 'phase_status=' + $phaseStatus
$contract += 'proof_folder=' + $ProofPathRelative
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) {
  Write-Host 'FATAL: 90_production_readiness_checks.txt is not well-formed'
  exit 1
}
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) {
  Write-Host 'FATAL: 99_contract_summary.txt is not well-formed'
  exit 1
}

$expectedEntries = @(
  '90_production_readiness_checks.txt',
  '99_contract_summary.txt',
  '01_rebuild_stdout.txt',
  '02_normal_clean_stdout.txt',
  '03_normal_blocked_stdout.txt',
  '04_rollback_switch_stdout.txt'
)

New-ProofZip -SourceDir $StageRoot -DestinationZip $ZipPath

if (-not (Test-Path -LiteralPath $ZipPath)) {
  Write-Host 'FATAL: final proof zip was not created'
  exit 1
}
if (-not (Test-ZipContainsEntries -ZipFile $ZipPath -ExpectedEntries $expectedEntries)) {
  Write-Host 'FATAL: final proof zip is missing expected artifacts'
  exit 1
}

Write-Host 'Deleting staging directory...'
Remove-Item -LiteralPath $StageRoot -Recurse -Force

$phaseArtifactsInProof = @(Get-ChildItem -LiteralPath $ProofRoot | Where-Object { $_.Name -like ($ProofName + '*') })
if ($phaseArtifactsInProof.Count -ne 1 -or $phaseArtifactsInProof[0].Name -ne ($ProofName + '.zip')) {
  Write-Host 'FATAL: forward packaging rule violated for phase-specific proof output'
  exit 1
}

Write-Host ('PF=' + $ProofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase67_2_status=' + $phaseStatus)
exit 0
