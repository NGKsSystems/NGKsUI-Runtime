#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
  Write-Host "FATAL: $_"
  exit 1
}

$workspaceRoot = Get-Location | Select-Object -ExpandProperty Path
$proofRoot = Join-Path $workspaceRoot '_proof'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName = "phase70_1_trust_guard_policy_rollout_widget_sandbox_execution_pipeline_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

$widgetMain = Join-Path $workspaceRoot 'apps/widget_sandbox/main.cpp'
$guardHeader = Join-Path $workspaceRoot 'apps/runtime_phase53_guard.hpp'
$widgetObj = Join-Path $workspaceRoot 'build/debug/obj/widget_sandbox/apps/widget_sandbox/main.obj'
$widgetExe = Join-Path $workspaceRoot 'build/debug/bin/widget_sandbox.exe'

$planOut = Join-Path $stageRoot '__plan_stdout.txt'
$buildOut = Join-Path $stageRoot '__native_build_stdout.txt'
$cleanOut = Join-Path $stageRoot '__widget_clean_stdout.txt'
$blockedOut = Join-Path $stageRoot '__widget_blocked_stdout.txt'

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

# Enforce single zip for this phase.
Get-ChildItem -LiteralPath $proofRoot -Filter 'phase70_1_trust_guard_policy_rollout_widget_sandbox_execution_pipeline_*.zip' -ErrorAction SilentlyContinue |
  ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }

# Track pre-existing runtime validation proof folders; cleanup new ones later.
$preRuntimeValidationFolders = @{}
Get-ChildItem -LiteralPath $proofRoot -Directory -Filter 'runtime_validation_*' -ErrorAction SilentlyContinue |
  ForEach-Object { $preRuntimeValidationFolders[$_.FullName.ToLowerInvariant()] = $true }

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
    Add-Content -LiteralPath $OutFile -Value ('TIMEOUT step=' + $StepName + ' timeout_seconds=' + $TimeoutSeconds)
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
    Add-Content -LiteralPath $OutFile -Value ('TIMEOUT step=' + $StepName + ' timeout_seconds=' + $TimeoutSeconds)
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

function Invoke-PwshToFile {
  param(
    [string[]]$ArgumentList,
    [string]$OutFile,
    [int]$TimeoutSeconds,
    [string]$StepName
  )

  $errFile = $OutFile + '.stderr.tmp'
  [void](Remove-FileWithRetry -Path $errFile)

  $proc = Start-Process -FilePath 'powershell' -ArgumentList $ArgumentList -PassThru -NoNewWindow -RedirectStandardOutput $OutFile -RedirectStandardError $errFile
  $timedOut = -not $proc.WaitForExit($TimeoutSeconds * 1000)

  if ($timedOut) {
    try { $proc.Kill() } catch {}
    try { $proc.WaitForExit() } catch {}
    Add-Content -LiteralPath $OutFile -Value ('TIMEOUT step=' + $StepName + ' timeout_seconds=' + $TimeoutSeconds)
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

$pythonExe = Join-Path $workspaceRoot '.venv/Scripts/python.exe'
if (-not (Test-Path -LiteralPath $pythonExe)) {
  Write-Host 'FATAL: .venv python executable missing'
  exit 1
}

if (-not (Test-Path -LiteralPath $widgetMain)) {
  Write-Host 'FATAL: widget_sandbox main source missing'
  exit 1
}

# 1) Validate integration was applied.
$integrationPresent = Get-FileContains -Path $widgetMain -Needle 'require_runtime_trust("execution_pipeline")'

# 2) Build with corrected path: plan generation + native compile/link from plan nodes.
$plan = Invoke-PythonToFile -PythonExe $pythonExe -ArgumentList @('-m', 'ngksgraph', 'build', '--profile', 'debug', '--msvc-auto', '--target', 'widget_sandbox') -OutFile $planOut -TimeoutSeconds 240 -StepName 'plan_widget_sandbox'
if ($plan.TimedOut -or $plan.ExitCode -ne 0) {
  Write-Host 'FATAL: widget_sandbox plan generation failed'
  exit 1
}

$planText = Get-Content -LiteralPath $planOut -Raw
$planMatch = [regex]::Match($planText, 'BuildCore plan:\s+(.+)')
$planPath = if ($planMatch.Success) { $planMatch.Groups[1].Value.Trim() } else { Join-Path $workspaceRoot 'build_graph/debug/ngksbuildcore_plan.json' }
$planJson = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
$compileNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Compile apps/widget_sandbox/main.cpp for widget_sandbox' })[0]
$linkNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Link widget_sandbox' })[0]
if ($null -eq $compileNode -or $null -eq $linkNode) {
  Write-Host 'FATAL: widget_sandbox compile/link nodes missing from plan'
  exit 1
}

$msvcEnvScript = Join-Path $workspaceRoot 'tools/enter_msvc_env.ps1'
if (-not (Test-Path -LiteralPath $msvcEnvScript)) {
  Write-Host 'FATAL: MSVC env script missing'
  exit 1
}

if (Test-Path -LiteralPath $widgetObj) { Remove-Item -LiteralPath $widgetObj -Force }
if (Test-Path -LiteralPath $widgetExe) { Remove-Item -LiteralPath $widgetExe -Force }

Set-Content -LiteralPath $buildOut -Value 'build_mode=plan_native_compile_link' -Encoding UTF8
try {
  & $msvcEnvScript *>&1 | Out-File -LiteralPath $buildOut -Append -Encoding UTF8
} catch {
  Add-Content -LiteralPath $buildOut -Value ('BUILD_ERROR=MSVC_ENV_IMPORT_FAILED detail=' + $_.Exception.Message)
  Write-Host 'FATAL: MSVC environment import failed'
  exit 1
}

$compileOut = Join-Path $stageRoot '__compile_stdout.txt'
$linkOut = Join-Path $stageRoot '__link_stdout.txt'

Add-Content -LiteralPath $buildOut -Value ('BUILD_STEP=compile command=' + $compileNode.cmd)
$compile = Invoke-CmdToFile -CommandLine $compileNode.cmd -OutFile $compileOut -TimeoutSeconds 300 -StepName 'compile_widget_sandbox'
if (Test-Path -LiteralPath $compileOut) { Get-Content -LiteralPath $compileOut | Add-Content -LiteralPath $buildOut }
if ($compile.TimedOut -or $compile.ExitCode -ne 0) {
  Write-Host 'FATAL: widget_sandbox compile failed'
  exit 1
}

Add-Content -LiteralPath $buildOut -Value ('BUILD_STEP=link command=' + $linkNode.cmd)
$link = Invoke-CmdToFile -CommandLine $linkNode.cmd -OutFile $linkOut -TimeoutSeconds 300 -StepName 'link_widget_sandbox'
if (Test-Path -LiteralPath $linkOut) { Get-Content -LiteralPath $linkOut | Add-Content -LiteralPath $buildOut }
if ($link.TimedOut -or $link.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $widgetExe)) {
  Write-Host 'FATAL: widget_sandbox link failed'
  exit 1
}

# 3) Validate clean and blocked runs through launcher (preserves output contract).
$cleanCommand = "& 'tools\\run_widget_sandbox.ps1' -PassArgs @('--visual-baseline','--auto-close-ms=250')"
$cleanArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cleanCommand)
$cleanRun = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $cleanOut -TimeoutSeconds 180 -StepName 'widget_clean'

$blockedCommand = '$env:NGKS_BYPASS_GUARD=''1''; try { & ''tools\run_widget_sandbox.ps1'' -PassArgs @(''--visual-baseline'',''--auto-close-ms=250'') } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }'
$blockedArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $blockedCommand)
$blockedRun = Invoke-PwshToFile -ArgumentList $blockedArgs -OutFile $blockedOut -TimeoutSeconds 180 -StepName 'widget_blocked'

$checkBuildPath = (Get-FileContains -Path $buildOut -Needle 'build_mode=plan_native_compile_link') -and (Get-FileContains -Path $buildOut -Needle 'BUILD_STEP=compile') -and (Get-FileContains -Path $buildOut -Needle 'BUILD_STEP=link')
$checkIntegrationPresent = $integrationPresent
$checkCleanRun = ($cleanRun.TimedOut -eq $false) -and ($cleanRun.ExitCode -eq 0) -and (Test-LinePresent -Path $cleanOut -Pattern '^runtime_trust_guard=PASS\s+context=runtime_init$') -and (Test-LinePresent -Path $cleanOut -Pattern '^runtime_trust_guard=PASS\s+context=execution_pipeline$') -and (Test-LinePresent -Path $cleanOut -Pattern '^LAUNCH_FINAL_SUMMARY\s+target=widget_sandbox\s+final_status=RUN_OK\s+')
$checkBlockedRun = ($blockedRun.TimedOut -eq $false) -and (Test-LinePresent -Path $blockedOut -Pattern '^LAUNCH_ERROR=runtime_trust_guard_failed\s+exit=') -and (Test-LinePresent -Path $blockedOut -Pattern '^LAUNCH_FINAL_SUMMARY\s+target=widget_sandbox\s+final_status=BLOCKED\s+.*blocked_reason=TRUST_CHAIN_BLOCKED\s+exit_code=120$')
$checkSummariesPreserved = (Test-LinePresent -Path $cleanOut -Pattern '^LAUNCH_FINAL_SUMMARY\s+') -and (Test-LinePresent -Path $blockedOut -Pattern '^LAUNCH_FINAL_SUMMARY\s+')
$checkDiagnosticsPreserved = (Test-LinePresent -Path $cleanOut -Pattern '^runtime_trust_guard_elapsed_ms=\d+\s+context=execution_pipeline$') -and (Test-LinePresent -Path $blockedOut -Pattern '^TIMING_BOUNDARY\s+name=runtime_init_guard_start_timestamp\s+ts_utc=unavailable\s+source=missing_boundary\s+quality=unavailable$')
$checkRollbackControls = Get-FileContains -Path $guardHeader -Needle 'NGKS_RUNTIME_TRUST_GUARD_DISABLE_HARDENED_PATH'

$rows = @()
$rows += ('check_build_materialization_path=' + $(if ($checkBuildPath) { 'YES' } else { 'NO' }))
$rows += ('check_policy_rollout_applied=' + $(if ($checkIntegrationPresent) { 'YES' } else { 'NO' }))
$rows += ('check_clean_run=' + $(if ($checkCleanRun) { 'YES' } else { 'NO' }))
$rows += ('check_blocked_run=' + $(if ($checkBlockedRun) { 'YES' } else { 'NO' }))
$rows += ('check_summaries_preserved=' + $(if ($checkSummariesPreserved) { 'YES' } else { 'NO' }))
$rows += ('check_diagnostics_preserved=' + $(if ($checkDiagnosticsPreserved) { 'YES' } else { 'NO' }))
$rows += ('check_rollback_controls_preserved=' + $(if ($checkRollbackControls) { 'YES' } else { 'NO' }))

$failedCount = (@($rows | Where-Object { $_ -match '=NO$' })).Count
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_rollout_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE70_1_TRUST_GUARD_POLICY_ROLLOUT_WIDGET_SANDBOX_EXECUTION_PIPELINE'
$checkLines += 'target=widget_sandbox.execution_pipeline'
$checkLines += 'scope=minimal_policy_rollout_slice'
$checkLines += ('clean_exit_code=' + $cleanRun.ExitCode)
$checkLines += ('blocked_exit_code=' + $blockedRun.ExitCode)
$checkLines += ('clean_stdout_file=' + (Split-Path -Leaf $cleanOut))
$checkLines += ('blocked_stdout_file=' + (Split-Path -Leaf $blockedOut))
$checkLines += $rows
$checkLines += ('failed_check_count=' + $failedCount)
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE70_1_TRUST_GUARD_POLICY_ROLLOUT_WIDGET_SANDBOX_EXECUTION_PIPELINE'
$contract += 'objective=Roll out execution_pipeline trust guard into widget_sandbox startup path using corrected plan-native build/materialization validation'
$contract += 'changes_introduced=Added require_runtime_trust("execution_pipeline") to widget_sandbox startup path immediately after runtime_init startup summary'
$contract += 'runtime_behavior_changes=widget_sandbox now enforces execution_pipeline trust at startup and blocks fail-closed when trust chain is denied'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_rollout_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

# Keep only required output artifacts in final zip.
[void](Remove-FileWithRetry -Path $planOut)
[void](Remove-FileWithRetry -Path $buildOut)
[void](Remove-FileWithRetry -Path $cleanOut)
[void](Remove-FileWithRetry -Path $blockedOut)
[void](Remove-FileWithRetry -Path $compileOut)
[void](Remove-FileWithRetry -Path $linkOut)

$expectedEntries = @('90_rollout_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

# Cleanup runtime validation folders created during this run.
Get-ChildItem -LiteralPath $proofRoot -Directory -Filter 'runtime_validation_*' -ErrorAction SilentlyContinue |
  ForEach-Object {
    $key = $_.FullName.ToLowerInvariant()
    if (-not $preRuntimeValidationFolders.ContainsKey($key)) {
      Remove-Item -LiteralPath $_.FullName -Recurse -Force
    }
  }

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase70_1_trust_guard_policy_rollout_widget_sandbox_execution_pipeline_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase70_1_status=' + $phaseStatus)
exit 0
