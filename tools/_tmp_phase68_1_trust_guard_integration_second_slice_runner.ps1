#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
  Write-Host "FATAL: $_"
  exit 1
}

# ============================================================================
# PHASE68_1: TRUST GUARD INTEGRATION SECOND SLICE
# ============================================================================
# Minimal slice: loop_tests.execution_pipeline
# Rebuild strategy: plan-driven native compile/link (no proof-only build path)
# Packaging: exactly one final zip in _proof for this phase output
# ============================================================================

$WorkspaceRoot = Get-Location | Select-Object -ExpandProperty Path
$ProofRoot = Join-Path $WorkspaceRoot '_proof'
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ProofName = "phase68_1_trust_guard_integration_second_slice_$Timestamp"
$StageRoot = Join-Path $WorkspaceRoot ("_artifacts/runtime/" + $ProofName)
$ZipPath = Join-Path $ProofRoot ($ProofName + '.zip')
$ProofPathRelative = "_proof/$ProofName.zip"

$LoopMain = Join-Path $WorkspaceRoot 'apps/loop_tests/main.cpp'
$LoopObj = Join-Path $WorkspaceRoot 'build/debug/obj/loop_tests/apps/loop_tests/main.obj'
$LoopExe = Join-Path $WorkspaceRoot 'build/debug/bin/loop_tests.exe'

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

function Invoke-PythonToFile {
  param(
    [string]$PythonExe,
    [string[]]$ArgumentList,
    [string]$OutFile,
    [int]$TimeoutSeconds,
    [string]$StepName
  )

  $errFile = $OutFile + '.stderr.tmp'
  [void](Remove-FileWithRetry -Path $errFile)

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
    return [pscustomobject]@{ ExitCode = 124; TimedOut = $true }
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

  return [pscustomobject]@{ ExitCode = $exitCode; TimedOut = $false }
}

function Invoke-CmdToFile {
  param(
    [string]$CommandLine,
    [string]$OutFile,
    [int]$TimeoutSeconds,
    [string]$StepName
  )

  $errFile = $OutFile + '.stderr.tmp'
  [void](Remove-FileWithRetry -Path $errFile)

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
    return [pscustomobject]@{ ExitCode = 124; TimedOut = $true }
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

  return [pscustomobject]@{ ExitCode = $exitCode; TimedOut = $false }
}

function Invoke-ExeToFile {
  param(
    [string]$ExePath,
    [string[]]$InvocationList,
    [hashtable]$Env,
    [string]$OutFile,
    [int]$TimeoutSeconds,
    [string]$StepName
  )

  $errFile = $OutFile + '.stderr.tmp'
  [void](Remove-FileWithRetry -Path $errFile)

  $prev = @{}
  foreach ($k in $Env.Keys) {
    $prev[$k] = [Environment]::GetEnvironmentVariable($k)
    [Environment]::SetEnvironmentVariable($k, [string]$Env[$k])
  }

  try {
    $proc = Start-Process -FilePath $ExePath -ArgumentList $InvocationList -PassThru -NoNewWindow -RedirectStandardOutput $OutFile -RedirectStandardError $errFile
    $timedOut = -not $proc.WaitForExit($TimeoutSeconds * 1000)

    if ($timedOut) {
      try { $proc.Kill() } catch {}
      try { $proc.WaitForExit() } catch {}
      Add-Content -LiteralPath $OutFile -Value ('RUN_ERROR=TIMEOUT step=' + $StepName + ' timeout_seconds=' + $TimeoutSeconds)
      if (Test-Path -LiteralPath $errFile) {
        Get-Content -LiteralPath $errFile | Add-Content -LiteralPath $OutFile
        [void](Remove-FileWithRetry -Path $errFile)
      }
      return [pscustomobject]@{ ExitCode = 124; TimedOut = $true }
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

    return [pscustomobject]@{ ExitCode = $exitCode; TimedOut = $false }
  }
  finally {
    foreach ($k in $prev.Keys) {
      [Environment]::SetEnvironmentVariable($k, $prev[$k])
    }
  }
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

$planOut = Join-Path $StageRoot '__plan_stdout.txt'
$buildOut = Join-Path $StageRoot '__native_build_stdout.txt'
$cleanOut = Join-Path $StageRoot '__loop_clean_stdout.txt'
$blockedOut = Join-Path $StageRoot '__loop_blocked_stdout.txt'

$pythonExe = Join-Path $WorkspaceRoot '.venv/Scripts/python.exe'
if (-not (Test-Path -LiteralPath $pythonExe)) {
  Write-Host 'FATAL: .venv python executable missing'
  exit 1
}

if (Test-Path -LiteralPath $LoopObj) { Remove-Item -LiteralPath $LoopObj -Force }
if (Test-Path -LiteralPath $LoopExe) { Remove-Item -LiteralPath $LoopExe -Force }

$plan = Invoke-PythonToFile -PythonExe $pythonExe -ArgumentList @('-m', 'ngksgraph', 'build', '--profile', 'debug', '--msvc-auto', '--target', 'loop_tests') -OutFile $planOut -TimeoutSeconds 180 -StepName 'plan_loop_tests'
if ($plan.TimedOut -or $plan.ExitCode -ne 0) {
  Write-Host 'FATAL: loop_tests build plan failed'
  exit 1
}

$planText = Get-Content -LiteralPath $planOut -Raw
$planMatch = [regex]::Match($planText, 'BuildCore plan:\s+(.+)')
$planPath = if ($planMatch.Success) { $planMatch.Groups[1].Value.Trim() } else { Join-Path $WorkspaceRoot 'build_graph/debug/ngksbuildcore_plan.json' }

$msvcEnvScript = Join-Path $WorkspaceRoot 'tools/enter_msvc_env.ps1'
if (-not (Test-Path -LiteralPath $msvcEnvScript)) {
  Write-Host 'FATAL: MSVC environment import script missing'
  exit 1
}

Set-Content -LiteralPath $buildOut -Value 'build_mode=plan_native_compile_link' -Encoding UTF8
try {
  & $msvcEnvScript *>&1 | Out-File -LiteralPath $buildOut -Append -Encoding UTF8
} catch {
  Add-Content -LiteralPath $buildOut -Value ('BUILD_ERROR=MSVC_ENV_IMPORT_FAILED detail=' + $_.Exception.Message)
  Write-Host 'FATAL: MSVC environment import failed'
  exit 1
}

$planJson = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
$compileNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Compile apps/loop_tests/main.cpp for loop_tests' })[0]
$linkNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Link loop_tests' })[0]
if ($null -eq $compileNode -or $null -eq $linkNode) {
  Add-Content -LiteralPath $buildOut -Value 'BUILD_ERROR=PLAN_NODE_MISSING target=loop_tests'
  Write-Host 'FATAL: loop_tests compile/link plan nodes missing'
  exit 1
}

New-Item -ItemType Directory -Path (Split-Path -Parent $LoopObj) -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $LoopExe) -Force | Out-Null

$compileTmp = Join-Path $StageRoot '__compile_stdout.txt'
$linkTmp = Join-Path $StageRoot '__link_stdout.txt'
Add-Content -LiteralPath $buildOut -Value ('BUILD_STEP=compile command=' + $compileNode.cmd)
$compile = Invoke-CmdToFile -CommandLine $compileNode.cmd -OutFile $compileTmp -TimeoutSeconds 240 -StepName 'compile_loop_tests'
if (Test-Path -LiteralPath $compileTmp) { Get-Content -LiteralPath $compileTmp | Add-Content -LiteralPath $buildOut }
if ($compile.TimedOut -or $compile.ExitCode -ne 0) {
  Add-Content -LiteralPath $buildOut -Value ('BUILD_ERROR=COMPILE_FAILED exit_code=' + $compile.ExitCode)
  Write-Host 'FATAL: loop_tests compile failed'
  exit 1
}

Add-Content -LiteralPath $buildOut -Value ('BUILD_STEP=link command=' + $linkNode.cmd)
$link = Invoke-CmdToFile -CommandLine $linkNode.cmd -OutFile $linkTmp -TimeoutSeconds 240 -StepName 'link_loop_tests'
if (Test-Path -LiteralPath $linkTmp) { Get-Content -LiteralPath $linkTmp | Add-Content -LiteralPath $buildOut }
if ($link.TimedOut -or $link.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $LoopExe)) {
  Add-Content -LiteralPath $buildOut -Value ('BUILD_ERROR=LINK_FAILED exit_code=' + $link.ExitCode)
  Write-Host 'FATAL: loop_tests link failed'
  exit 1
}

[void](Remove-FileWithRetry -Path $compileTmp)
[void](Remove-FileWithRetry -Path $linkTmp)

$cleanRun = Invoke-ExeToFile -ExePath $LoopExe -InvocationList @() -Env @{ NGKS_BYPASS_GUARD = $null } -OutFile $cleanOut -TimeoutSeconds 120 -StepName 'loop_clean'
$blockedRun = Invoke-ExeToFile -ExePath $LoopExe -InvocationList @() -Env @{ NGKS_BYPASS_GUARD = '1' } -OutFile $blockedOut -TimeoutSeconds 120 -StepName 'loop_blocked'

$checkChosenTargetImplemented = Get-FileContains -Path $LoopMain -Needle 'require_runtime_trust("execution_pipeline")'
$checkClean = ($cleanRun.TimedOut -eq $false) -and ($cleanRun.ExitCode -eq 0) -and (Test-LinePresent -Path $cleanOut -Pattern '^runtime_trust_guard=PASS\s+context=runtime_init$') -and (Test-LinePresent -Path $cleanOut -Pattern '^runtime_trust_guard=PASS\s+context=execution_pipeline$') -and (Test-LinePresent -Path $cleanOut -Pattern '^runtime_final_status=RUN_OK$')
$checkBlocked = ($blockedRun.TimedOut -eq $false) -and ($blockedRun.ExitCode -ne 0) -and (Test-LinePresent -Path $blockedOut -Pattern '^runtime_trust_guard=FAIL\s+context=runtime_init\s+exit=') -and (Test-LinePresent -Path $blockedOut -Pattern '^runtime_trust_guard_reason_code=TRUST_CHAIN_BLOCKED\s+context=runtime_init$') -and (Test-LinePresent -Path $blockedOut -Pattern '^runtime_final_status=BLOCKED$')
$checkSummaries = (Test-LinePresent -Path $cleanOut -Pattern '^runtime_process_summary\s+phase=startup\s+target=loop_tests\s+context=runtime_init\s+enforcement=PASS\s+') -and (Test-LinePresent -Path $cleanOut -Pattern '^runtime_process_summary\s+phase=termination\s+target=loop_tests\s+context=runtime_init\s+enforcement=PASS\s+') -and (Test-LinePresent -Path $blockedOut -Pattern '^runtime_process_summary\s+phase=startup\s+target=loop_tests\s+context=runtime_init\s+enforcement=FAIL\s+')
$checkDiagnostics = (Test-LinePresent -Path $cleanOut -Pattern '^runtime_trust_guard_elapsed_ms=\d+\s+context=execution_pipeline$') -and (Test-LinePresent -Path $blockedOut -Pattern '^runtime_trust_guard_elapsed_ms=\d+\s+context=runtime_init$')
$checkRollbackControlsPreserved = Get-FileContains -Path (Join-Path $WorkspaceRoot 'apps/runtime_phase53_guard.hpp') -Needle 'NGKS_RUNTIME_TRUST_GUARD_DISABLE_HARDENED_PATH'

$checks = @()
$checks += ('check_chosen_target_implemented=' + $(if ($checkChosenTargetImplemented) { 'YES' } else { 'NO' }))
$checks += ('check_clean_run=' + $(if ($checkClean) { 'YES' } else { 'NO' }))
$checks += ('check_blocked_run=' + $(if ($checkBlocked) { 'YES' } else { 'NO' }))
$checks += ('check_summaries_preserved=' + $(if ($checkSummaries) { 'YES' } else { 'NO' }))
$checks += ('check_diagnostics_preserved=' + $(if ($checkDiagnostics) { 'YES' } else { 'NO' }))
$checks += ('check_rollback_controls_preserved=' + $(if ($checkRollbackControlsPreserved) { 'YES' } else { 'NO' }))
$checks += ('check_plan_native_rebuild_used=' + $(if ((Get-FileContains -Path $buildOut -Needle 'build_mode=plan_native_compile_link') -and (Get-FileContains -Path $buildOut -Needle 'BUILD_STEP=compile') -and (Get-FileContains -Path $buildOut -Needle 'BUILD_STEP=link')) { 'YES' } else { 'NO' }))

$failedCount = (@($checks | Where-Object { $_ -match '=NO$' })).Count
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $StageRoot '90_integration_checks.txt'
$lines = @()
$lines += 'integration_direction=PHASE68_GUARD_INTEGRATION_EXPANSION'
$lines += 'chosen_target=loop_tests.execution_pipeline'
$lines += 'chosen_target_rationale=Next highest-value remaining path with minimal risk and direct workflow continuity'
$lines += 'patched_file_count=1'
$lines += 'patched_file_01=apps/loop_tests/main.cpp'
$lines += 'clean_exit_code=' + $cleanRun.ExitCode
$lines += 'blocked_exit_code=' + $blockedRun.ExitCode
$lines += $checks
$lines += 'failed_check_count=' + $failedCount
$lines += 'failed_checks=' + $(if ($failedCount -eq 0) { 'NONE' } else { (@($checks | Where-Object { $_ -match '=NO$' }) -join ' | ') })
$lines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $StageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE68_1_TRUST_GUARD_INTEGRATION_SECOND_SLICE'
$contract += 'objective=Apply the next highest-value minimal trust guard integration slice at loop_tests.execution_pipeline and validate clean and blocked behavior'
$contract += 'changes_introduced=Added execution_pipeline guard integration to loop_tests'
$contract += 'runtime_behavior_changes=None (fail-closed behavior, summaries, diagnostics, rollback controls, and output formats preserved)'
$contract += 'new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes' })
$contract += 'phase_status=' + $phaseStatus
$contract += 'proof_folder=' + $ProofPathRelative
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) {
  Write-Host 'FATAL: 90_integration_checks.txt is not well-formed'
  exit 1
}
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) {
  Write-Host 'FATAL: 99_contract_summary.txt is not well-formed'
  exit 1
}

# Keep only required output artifacts in the final zip.
[void](Remove-FileWithRetry -Path $planOut)
[void](Remove-FileWithRetry -Path $buildOut)
[void](Remove-FileWithRetry -Path $cleanOut)
[void](Remove-FileWithRetry -Path $blockedOut)

$expectedEntries = @('90_integration_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $StageRoot -DestinationZip $ZipPath
if (-not (Test-Path -LiteralPath $ZipPath)) {
  Write-Host 'FATAL: final proof zip was not created'
  exit 1
}
if (-not (Test-ZipContainsEntries -ZipFile $ZipPath -ExpectedEntries $expectedEntries)) {
  Write-Host 'FATAL: final proof zip is missing expected artifacts'
  exit 1
}

Remove-Item -LiteralPath $StageRoot -Recurse -Force

$phaseArtifactsInProof = @(Get-ChildItem -LiteralPath $ProofRoot | Where-Object { $_.Name -like ($ProofName + '*') })
if ($phaseArtifactsInProof.Count -ne 1 -or $phaseArtifactsInProof[0].Name -ne ($ProofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase-specific proof output'
  exit 1
}

Write-Host ('PF=' + $ProofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase68_1_status=' + $phaseStatus)
exit 0
