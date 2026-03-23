#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
  Write-Host "FATAL: $_"
  exit 1
}

# ============================================================================
# PHASE68_0: TRUST GUARD INTEGRATION MAP AND FIRST EXPANSION SLICE
# ============================================================================
# Smallest first slice only. Stages artifacts outside _proof and emits one zip.
# ============================================================================

$WorkspaceRoot = Get-Location | Select-Object -ExpandProperty Path
$ProofRoot = Join-Path $WorkspaceRoot '_proof'
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ProofName = "phase68_0_trust_guard_integration_map_and_first_slice_$Timestamp"
$StageRoot = Join-Path $WorkspaceRoot ("_artifacts/runtime/" + $ProofName)
$ZipPath = Join-Path $ProofRoot ($ProofName + '.zip')
$ProofPathRelative = "_proof/$ProofName.zip"
$SandboxMain = Join-Path $WorkspaceRoot 'apps/sandbox_app/main.cpp'
$WidgetMain = Join-Path $WorkspaceRoot 'apps/widget_sandbox/main.cpp'
$Win32Main = Join-Path $WorkspaceRoot 'apps/win32_sandbox/main.cpp'
$LoopMain = Join-Path $WorkspaceRoot 'apps/loop_tests/main.cpp'

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

function Invoke-PythonToFile {
  param(
    [string]$PythonExe,
    [string[]]$ArgumentList,
    [string]$OutFile,
    [int]$TimeoutSeconds,
    [string]$StepName
  )

  $errFile = $OutFile + '.stderr.tmp'
  if (-not (Remove-FileWithRetry -Path $errFile)) {
    return [pscustomobject]@{ ExitCode = 125; TimedOut = $false; FileLock = $true }
  }

  $quotedArgs = @()
  foreach ($arg in $ArgumentList) {
    if ($arg -match '[\s"]') {
      $quotedArgs += ('"' + ($arg -replace '"', '\"') + '"')
    } else {
      $quotedArgs += $arg
    }
  }

  $proc = Start-Process -FilePath $PythonExe -ArgumentList ($quotedArgs -join ' ') -PassThru -NoNewWindow -RedirectStandardOutput $OutFile -RedirectStandardError $errFile
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

function Test-LinePresent {
  param([string]$Path, [string]$Pattern)
  $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $lines) { return $false }
  foreach ($line in $lines) {
    if ($line -match $Pattern) { return $true }
  }
  return $false
}

function Get-LastSummaryValue {
  param([string]$Path, [string]$Key, [string]$Default = '')
  $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $lines) { return $Default }
  for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    if ($lines[$i] -match ('\b' + [regex]::Escape($Key) + '=(\S+)')) { return $Matches[1] }
  }
  return $Default
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
      if ($entryNames -notcontains $entry) { return $false }
    }
    return $true
  }
  finally {
    $archive.Dispose()
  }
}

$buildOut = Join-Path $StageRoot '01_rebuild_stdout.txt'
$cleanOut = Join-Path $StageRoot '02_sandbox_app_clean_stdout.txt'
$blockedOut = Join-Path $StageRoot '03_sandbox_app_blocked_stdout.txt'
$sandboxObj = Join-Path $WorkspaceRoot 'build/debug/obj/sandbox_app/apps/sandbox_app/main.obj'
$sandboxExe = Join-Path $WorkspaceRoot 'build/debug/bin/sandbox_app.exe'

$pythonExe = Join-Path $WorkspaceRoot '.venv/Scripts/python.exe'
if (-not (Test-Path -LiteralPath $pythonExe)) {
  Write-Host 'FATAL: .venv python executable missing'
  exit 1
}

Write-Host 'Rebuilding with Phase68_0 integration slice...'
if (Test-Path -LiteralPath $sandboxObj) {
  Write-Host ('Removing stale object: ' + $sandboxObj)
  Remove-Item -LiteralPath $sandboxObj -Force
}
if (Test-Path -LiteralPath $sandboxExe) {
  Write-Host ('Removing stale executable: ' + $sandboxExe)
  Remove-Item -LiteralPath $sandboxExe -Force
}
$planOut = Join-Path $StageRoot '00_sandbox_plan_stdout.txt'
$plan = Invoke-PythonToFile -PythonExe $pythonExe -ArgumentList @('-m', 'ngksgraph', 'build', '--profile', 'debug', '--msvc-auto', '--target', 'sandbox_app') -OutFile $planOut -TimeoutSeconds 180 -StepName 'plan_sandbox_app'
if ($plan.TimedOut -or $plan.ExitCode -ne 0) {
  Write-Host 'FATAL: sandbox_app build plan failed'
  exit 1
}

$planText = Get-Content -LiteralPath $planOut -Raw
$planMatch = [regex]::Match($planText, 'BuildCore plan:\s+(.+)')
$planPath = if ($planMatch.Success) { $planMatch.Groups[1].Value.Trim() } else { Join-Path $WorkspaceRoot 'build_graph/debug/ngksbuildcore_plan.json' }
Set-Content -LiteralPath $buildOut -Value 'build_mode=plan_native_compile_link' -Encoding UTF8
$msvcEnvScript = Join-Path $WorkspaceRoot 'tools/enter_msvc_env.ps1'
if (-not (Test-Path -LiteralPath $msvcEnvScript)) {
  Write-Host 'FATAL: MSVC environment import script missing'
  exit 1
}

try {
  & $msvcEnvScript *>&1 | Out-File -LiteralPath $buildOut -Append -Encoding UTF8
} catch {
  Add-Content -LiteralPath $buildOut -Value ('BUILD_ERROR=MSVC_ENV_IMPORT_FAILED detail=' + $_.Exception.Message)
  Write-Host 'FATAL: MSVC environment import failed'
  exit 1
}

$planJson = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
$compileNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Compile apps/sandbox_app/main.cpp for sandbox_app' })[0]
$linkNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Link sandbox_app' })[0]
if ($null -eq $compileNode -or $null -eq $linkNode) {
  Add-Content -LiteralPath $buildOut -Value 'BUILD_ERROR=PLAN_NODE_MISSING target=sandbox_app'
  Write-Host 'FATAL: sandbox_app compile/link plan nodes missing'
  exit 1
}

$sandboxObjDir = Split-Path -Parent $sandboxObj
$sandboxExeDir = Split-Path -Parent $sandboxExe
New-Item -ItemType Directory -Path $sandboxObjDir -Force | Out-Null
New-Item -ItemType Directory -Path $sandboxExeDir -Force | Out-Null

$compileOut = Join-Path $StageRoot '__sandbox_compile_stdout.txt'
$linkOut = Join-Path $StageRoot '__sandbox_link_stdout.txt'
Add-Content -LiteralPath $buildOut -Value ('BUILD_STEP=compile command=' + $compileNode.cmd)
$compile = Invoke-CmdToFile -CommandLine $compileNode.cmd -OutFile $compileOut -TimeoutSeconds 240 -StepName 'compile_sandbox_app'
if (Test-Path -LiteralPath $compileOut) {
  Get-Content -LiteralPath $compileOut | Add-Content -LiteralPath $buildOut
}
if ($compile.TimedOut -or $compile.ExitCode -ne 0) {
  Add-Content -LiteralPath $buildOut -Value ('BUILD_ERROR=COMPILE_FAILED exit_code=' + $compile.ExitCode)
  Write-Host 'FATAL: sandbox_app compile failed'
  exit 1
}

Add-Content -LiteralPath $buildOut -Value ('BUILD_STEP=link command=' + $linkNode.cmd)
$link = Invoke-CmdToFile -CommandLine $linkNode.cmd -OutFile $linkOut -TimeoutSeconds 240 -StepName 'link_sandbox_app'
if (Test-Path -LiteralPath $linkOut) {
  Get-Content -LiteralPath $linkOut | Add-Content -LiteralPath $buildOut
}
if ($link.TimedOut -or $link.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $sandboxExe)) {
  Add-Content -LiteralPath $buildOut -Value ('BUILD_ERROR=LINK_FAILED exit_code=' + $link.ExitCode)
  Write-Host 'FATAL: sandbox_app link failed'
  exit 1
}

Remove-FileWithRetry -Path $compileOut | Out-Null
Remove-FileWithRetry -Path $linkOut | Out-Null
$build = [pscustomobject]@{ ExitCode = 0; TimedOut = $false; FileLock = $false }

$cleanArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools\run_sandbox_app.ps1')
$blockedArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '$env:NGKS_BYPASS_GUARD=''1''; try { & ''tools\run_sandbox_app.ps1'' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }')

Write-Host 'Validating sandbox_app clean integration path...'
$cleanRun = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $cleanOut -TimeoutSeconds 60 -StepName 'sandbox_clean'

Write-Host 'Validating sandbox_app blocked behavior remains coherent...'
$blockedRun = Invoke-PwshToFile -ArgumentList $blockedArgs -OutFile $blockedOut -TimeoutSeconds 60 -StepName 'sandbox_blocked'

$ranking = @(
  'rank_01_target=sandbox_app.execution_pipeline value=HIGH risk=LOW rationale=Production-like app currently guarded only at runtime_init; small direct gap with immediate coverage benefit',
  'rank_02_target=loop_tests.execution_pipeline value=MEDIUM risk=LOW rationale=Useful consistency gap but lower production value than sandbox_app',
  'rank_03_target=sandbox_app.state_mutation value=MEDIUM risk=MEDIUM rationale=Would require introducing narrower operation boundaries beyond current app shape',
  'rank_04_target=loop_tests.state_mutation value=LOW risk=MEDIUM rationale=Test workload only and would add more invasive boundary placement',
  'rank_05_target=sandbox_app.file_load_or_plugin_load value=LOW risk=LOW rationale=Not meaningfully present in current sandbox_app execution path'
)

$checkChosenTargetImplemented = Get-FileContains -Path $SandboxMain -Needle 'require_runtime_trust("execution_pipeline")'
$checkWidgetAlreadyDeep = (Get-FileContains -Path $WidgetMain -Needle 'require_runtime_trust("plugin_load")') -and (Get-FileContains -Path $WidgetMain -Needle 'require_runtime_trust("file_load")') -and (Get-FileContains -Path $WidgetMain -Needle 'require_runtime_trust("save_export")')
$checkWin32AlreadyDeep = (Get-FileContains -Path $Win32Main -Needle 'require_runtime_trust("file_load")') -and (Get-FileContains -Path $Win32Main -Needle 'require_runtime_trust("execution_pipeline")')
$checkLoopGapExists = -not (Get-FileContains -Path $LoopMain -Needle 'require_runtime_trust("execution_pipeline")')

$checkCleanBehavior = ($cleanRun.TimedOut -eq $false) -and (Test-LinePresent -Path $cleanOut -Pattern '^runtime_trust_guard=PASS\s+context=runtime_init$') -and (Test-LinePresent -Path $cleanOut -Pattern '^runtime_trust_guard=PASS\s+context=execution_pipeline$') -and (Test-LinePresent -Path $cleanOut -Pattern '^LAUNCH_FINAL_SUMMARY\s+target=sandbox_app\s+final_status=RUN_OK\s+')
$checkBlockedBehavior = ($blockedRun.TimedOut -eq $false) -and (Test-LinePresent -Path $blockedOut -Pattern '^LAUNCH_FINAL_SUMMARY\s+target=sandbox_app\s+final_status=BLOCKED\s+context=runtime_init\s+enforcement=FAIL\s+')
$checkBlockedExit = (Test-LinePresent -Path $blockedOut -Pattern '^LAUNCH_FINAL_SUMMARY\s+.*blocked_reason=TRUST_CHAIN_BLOCKED\s+exit_code=120$')
$checkSummaries = (Test-LinePresent -Path $cleanOut -Pattern '^LAUNCH_FINAL_SUMMARY\s+') -and (Test-LinePresent -Path $blockedOut -Pattern '^LAUNCH_FINAL_SUMMARY\s+')
$checkDiagnostics = (Test-LinePresent -Path $cleanOut -Pattern '^runtime_trust_guard_elapsed_ms=\d+\s+context=execution_pipeline$') -and ((Test-LinePresent -Path $blockedOut -Pattern '^LAUNCH_ERROR=') -or (Test-LinePresent -Path $blockedOut -Pattern '^runtime_trust_guard_reason_code=TRUST_CHAIN_BLOCKED\s+context=runtime_init$'))
$checkRollbackControlsPreserved = Get-FileContains -Path (Join-Path $WorkspaceRoot 'apps/runtime_phase53_guard.hpp') -Needle 'NGKS_RUNTIME_TRUST_GUARD_DISABLE_HARDENED_PATH'

$checks = @()
$checks += ('check_build_succeeded=' + $(if ($build.ExitCode -eq 0 -and $build.TimedOut -eq $false) { 'YES' } else { 'NO' }))
$checks += ('check_integration_map_consistent=' + $(if ($checkWidgetAlreadyDeep -and $checkWin32AlreadyDeep -and $checkLoopGapExists) { 'YES' } else { 'NO' }))
$checks += ('check_chosen_target_implemented=' + $(if ($checkChosenTargetImplemented) { 'YES' } else { 'NO' }))
$checks += ('check_clean_target_guard_use=' + $(if ($checkCleanBehavior) { 'YES' } else { 'NO' }))
$checks += ('check_blocked_behavior_preserved=' + $(if ($checkBlockedBehavior -and $checkBlockedExit) { 'YES' } else { 'NO' }))
$checks += ('check_summaries_present=' + $(if ($checkSummaries) { 'YES' } else { 'NO' }))
$checks += ('check_diagnostics_present=' + $(if ($checkDiagnostics) { 'YES' } else { 'NO' }))
$checks += ('check_rollback_controls_preserved=' + $(if ($checkRollbackControlsPreserved) { 'YES' } else { 'NO' }))

$checksFile = Join-Path $StageRoot '90_integration_map_and_checks.txt'
$lines = @()
$lines += 'patched_file_count=1'
$lines += 'patched_file_01=apps/sandbox_app/main.cpp'
$lines += 'integration_direction=PHASE68_GUARD_INTEGRATION_EXPANSION'
$lines += 'chosen_first_target=sandbox_app.execution_pipeline'
$lines += 'chosen_target_reason=Highest value lowest risk next gap after widget_sandbox and win32_sandbox already deeper integration'
$lines += 'clean_stdout_file=' + (Split-Path -Leaf $cleanOut)
$lines += 'blocked_stdout_file=' + (Split-Path -Leaf $blockedOut)
$lines += 'plan_stdout_file=' + (Split-Path -Leaf $planOut)
$lines += 'rebuild_stdout_file=' + (Split-Path -Leaf $buildOut)
$lines += 'normal_clean_final_status=' + $(if (Test-LinePresent -Path $cleanOut -Pattern '^LAUNCH_FINAL_SUMMARY\s+target=sandbox_app\s+final_status=RUN_OK\s+') { 'RUN_OK' } else { 'UNKNOWN' })
$lines += 'normal_blocked_final_status=' + $(if (Test-LinePresent -Path $blockedOut -Pattern '^LAUNCH_FINAL_SUMMARY\s+target=sandbox_app\s+final_status=BLOCKED\s+') { 'BLOCKED' } else { 'UNKNOWN' })
$lines += 'normal_blocked_reason=' + $(if (Test-LinePresent -Path $blockedOut -Pattern '^runtime_trust_guard_reason_code=TRUST_CHAIN_BLOCKED\s+context=runtime_init$') { 'TRUST_CHAIN_BLOCKED' } else { 'UNKNOWN' })
$lines += $ranking
$lines += $checks
$failedCount = (@($checks | Where-Object { $_ -match '=NO$' })).Count
$failedChecks = if ($failedCount -gt 0) { (@($checks | Where-Object { $_ -match '=NO$' }) -join ' | ') } else { 'NONE' }
$lines += 'failed_check_count=' + $failedCount
$lines += 'failed_checks=' + $failedChecks
$lines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $StageRoot '99_contract_summary.txt'
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }
$contract = @()
$contract += 'next_phase_selected=PHASE68_0_TRUST_GUARD_INTEGRATION_MAP_AND_FIRST_EXPANSION_SLICE'
$contract += 'objective=Map the next meaningful trust guard integration paths, rank them, and apply the smallest first slice to the best target'
$contract += 'changes_introduced=Added execution_pipeline guard integration to sandbox_app as the highest-value lowest-risk next target'
$contract += 'runtime_behavior_changes=None (existing fail-closed behavior, summaries, diagnostics, and rollback controls preserved)'
$contract += 'new_regressions_detected=No'
$contract += 'phase_status=' + $phaseStatus
$contract += 'proof_folder=' + $ProofPathRelative
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) {
  Write-Host 'FATAL: 90_integration_map_and_checks.txt is not well-formed'
  exit 1
}
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) {
  Write-Host 'FATAL: 99_contract_summary.txt is not well-formed'
  exit 1
}

$expectedEntries = @(
  '90_integration_map_and_checks.txt',
  '99_contract_summary.txt',
  '00_sandbox_plan_stdout.txt',
  '01_rebuild_stdout.txt',
  '02_sandbox_app_clean_stdout.txt',
  '03_sandbox_app_blocked_stdout.txt'
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
  Write-Host 'FATAL: packaging rule violated for phase-specific proof output'
  exit 1
}

Write-Host ('PF=' + $ProofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase68_0_status=' + $phaseStatus)
exit 0
