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
$proofName = "phase93_1_legacy_removal_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

$loopMain = Join-Path $workspaceRoot 'apps/loop_tests/main.cpp'
$graphToml = Join-Path $workspaceRoot 'ngksgraph.toml'
$loopObj = Join-Path $workspaceRoot 'build/debug/obj/loop_tests/apps/loop_tests/main.obj'
$loopExe = Join-Path $workspaceRoot 'build/debug/bin/loop_tests.exe'
$sandboxMain = Join-Path $workspaceRoot 'apps/sandbox_app/main.cpp'
$win32Main = Join-Path $workspaceRoot 'apps/win32_sandbox/main.cpp'
$widgetMain = Join-Path $workspaceRoot 'apps/widget_sandbox/main.cpp'

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase93_1_legacy_removal_*.zip' -ErrorAction SilentlyContinue |
  ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }

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
  param([string]$PythonExe,[string[]]$ArgumentList,[string]$OutFile,[int]$TimeoutSeconds,[string]$StepName)
  $errFile = $OutFile + '.stderr.tmp'
  [void](Remove-FileWithRetry -Path $errFile)
  $quotedArgs = @()
  foreach ($arg in $ArgumentList) {
    if ($arg -match '[\s"]') { $quotedArgs += ('"' + ($arg -replace '"', '\"') + '"') } else { $quotedArgs += $arg }
  }
  $proc = Start-Process -FilePath $PythonExe -ArgumentList ($quotedArgs -join ' ') -PassThru -NoNewWindow -RedirectStandardOutput $OutFile -RedirectStandardError $errFile
  $timedOut = -not $proc.WaitForExit($TimeoutSeconds * 1000)
  if ($timedOut) {
    try { $proc.Kill() } catch {}
    try { $proc.WaitForExit() } catch {}
    Add-Content -LiteralPath $OutFile -Value ('BUILD_ERROR=TIMEOUT step=' + $StepName + ' timeout_seconds=' + $TimeoutSeconds)
    if (Test-Path -LiteralPath $errFile) { Get-Content -LiteralPath $errFile | Add-Content -LiteralPath $OutFile; [void](Remove-FileWithRetry -Path $errFile) }
    return [pscustomobject]@{ ExitCode = 124; TimedOut = $true }
  }
  $proc.WaitForExit()
  $exitCode = $proc.ExitCode
  try { $proc.Close() } catch {}
  $proc.Dispose()
  if (Test-Path -LiteralPath $errFile) {
    $stderr = Get-Content -LiteralPath $errFile -Raw
    if (-not [string]::IsNullOrWhiteSpace($stderr)) { Add-Content -LiteralPath $OutFile -Value $stderr }
    [void](Remove-FileWithRetry -Path $errFile)
  }
  return [pscustomobject]@{ ExitCode = $exitCode; TimedOut = $false }
}

function Invoke-CmdToFile {
  param([string]$CommandLine,[string]$OutFile,[int]$TimeoutSeconds,[string]$StepName)
  $errFile = $OutFile + '.stderr.tmp'
  [void](Remove-FileWithRetry -Path $errFile)
  $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', $CommandLine) -PassThru -NoNewWindow -RedirectStandardOutput $OutFile -RedirectStandardError $errFile
  $timedOut = -not $proc.WaitForExit($TimeoutSeconds * 1000)
  if ($timedOut) {
    try { $proc.Kill() } catch {}
    try { $proc.WaitForExit() } catch {}
    Add-Content -LiteralPath $OutFile -Value ('BUILD_ERROR=TIMEOUT step=' + $StepName + ' timeout_seconds=' + $TimeoutSeconds)
    if (Test-Path -LiteralPath $errFile) { Get-Content -LiteralPath $errFile | Add-Content -LiteralPath $OutFile; [void](Remove-FileWithRetry -Path $errFile) }
    return [pscustomobject]@{ ExitCode = 124; TimedOut = $true }
  }
  $proc.WaitForExit()
  $exitCode = $proc.ExitCode
  try { $proc.Close() } catch {}
  $proc.Dispose()
  if (Test-Path -LiteralPath $errFile) {
    $stderr = Get-Content -LiteralPath $errFile -Raw
    if (-not [string]::IsNullOrWhiteSpace($stderr)) { Add-Content -LiteralPath $OutFile -Value $stderr }
    [void](Remove-FileWithRetry -Path $errFile)
  }
  return [pscustomobject]@{ ExitCode = $exitCode; TimedOut = $false }
}

function Invoke-ExeToFile {
  param([string]$ExePath,[string[]]$InvocationList,[hashtable]$Env,[string]$OutFile,[int]$TimeoutSeconds,[string]$StepName)
  $errFile = $OutFile + '.stderr.tmp'
  [void](Remove-FileWithRetry -Path $errFile)
  $prev = @{}
  foreach ($k in $Env.Keys) { $prev[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, [string]$Env[$k]) }
  try {
    $proc = Start-Process -FilePath $ExePath -ArgumentList $InvocationList -PassThru -NoNewWindow -RedirectStandardOutput $OutFile -RedirectStandardError $errFile
    $timedOut = -not $proc.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) {
      try { $proc.Kill() } catch {}
      try { $proc.WaitForExit() } catch {}
      Add-Content -LiteralPath $OutFile -Value ('RUN_ERROR=TIMEOUT step=' + $StepName + ' timeout_seconds=' + $TimeoutSeconds)
      if (Test-Path -LiteralPath $errFile) { Get-Content -LiteralPath $errFile | Add-Content -LiteralPath $OutFile; [void](Remove-FileWithRetry -Path $errFile) }
      return [pscustomobject]@{ ExitCode = 124; TimedOut = $true }
    }
    $proc.WaitForExit()
    $exitCode = $proc.ExitCode
    try { $proc.Close() } catch {}
    $proc.Dispose()
    if (Test-Path -LiteralPath $errFile) {
      $stderr = Get-Content -LiteralPath $errFile -Raw
      if (-not [string]::IsNullOrWhiteSpace($stderr)) { Add-Content -LiteralPath $OutFile -Value $stderr }
      [void](Remove-FileWithRetry -Path $errFile)
    }
    return [pscustomobject]@{ ExitCode = $exitCode; TimedOut = $false }
  } finally {
    foreach ($k in $prev.Keys) { [Environment]::SetEnvironmentVariable($k, $prev[$k]) }
  }
}

function Test-LinePresent { param([string]$Path,[string]$Pattern) $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue; if (-not $lines) { return $false }; foreach ($line in $lines) { if ($line -match $Pattern) { return $true } }; return $false }
function Get-FileContains { param([string]$Path,[string]$Needle) $content = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop; return $content.Contains($Needle) }
function Test-KvFileWellFormed { param([string]$FilePath) if (-not (Test-Path -LiteralPath $FilePath)) { return $false }; $lines = @(Get-Content -LiteralPath $FilePath | Where-Object { $_ -match '\S' -and $_ -notmatch '^#' }); foreach ($line in $lines) { if ($line -notmatch '^[a-zA-Z_][a-zA-Z0-9_]*=') { return $false } }; return $true }
function New-ProofZip { param([string]$SourceDir,[string]$DestinationZip) if (Test-Path -LiteralPath $DestinationZip) { Remove-Item -LiteralPath $DestinationZip -Force }; Compress-Archive -Path (Join-Path $SourceDir '*') -DestinationPath $DestinationZip -Force }
function Test-ZipContainsEntries { param([string]$ZipFile,[string[]]$ExpectedEntries) Add-Type -AssemblyName System.IO.Compression.FileSystem; $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipFile); try { $entryNames = @($archive.Entries | ForEach-Object { $_.FullName }); foreach ($entry in $ExpectedEntries) { if ($entryNames -notcontains $entry) { return $false } }; return $true } finally { $archive.Dispose() } }

$planOut = Join-Path $stageRoot '__plan_stdout.txt'
$buildOut = Join-Path $stageRoot '__native_build_stdout.txt'
$defaultOut = Join-Path $stageRoot '__loop_default_stdout.txt'
$legacyFlagsOut = Join-Path $stageRoot '__loop_legacy_flags_stdout.txt'
$sliceOut = Join-Path $stageRoot '__loop_slice_stdout.txt'

$loopContent = if (Test-Path -LiteralPath $loopMain) { Get-Content -LiteralPath $loopMain -Raw } else { '' }
$graphContent = if (Test-Path -LiteralPath $graphToml) { Get-Content -LiteralPath $graphToml -Raw } else { '' }
$sandboxContent = if (Test-Path -LiteralPath $sandboxMain) { Get-Content -LiteralPath $sandboxMain -Raw } else { '' }
$win32Content = if (Test-Path -LiteralPath $win32Main) { Get-Content -LiteralPath $win32Main -Raw } else { '' }
$widgetContent = if (Test-Path -LiteralPath $widgetMain) { Get-Content -LiteralPath $widgetMain -Raw } else { '' }

$pythonExe = Join-Path $workspaceRoot '.venv/Scripts/python.exe'
$phaseStatus = 'PASS'
$buildBlocked = $false
$buildBlockerReason = 'NONE'

$defaultRun = [pscustomobject]@{ ExitCode = -1; TimedOut = $false }
$legacyFlagsRun = [pscustomobject]@{ ExitCode = -1; TimedOut = $false }
$sliceRun = [pscustomobject]@{ ExitCode = -1; TimedOut = $false }
$checkResults = [ordered]@{}

if (-not (Test-Path -LiteralPath $pythonExe)) { $buildBlocked = $true; $buildBlockerReason = 'VENV_PYTHON_MISSING' }

if (-not $buildBlocked) {
  if (Test-Path -LiteralPath $loopObj) { Remove-Item -LiteralPath $loopObj -Force }
  if (Test-Path -LiteralPath $loopExe) { Remove-Item -LiteralPath $loopExe -Force }

  $plan = Invoke-PythonToFile -PythonExe $pythonExe -ArgumentList @('-m', 'ngksgraph', 'build', '--profile', 'debug', '--msvc-auto', '--target', 'loop_tests') -OutFile $planOut -TimeoutSeconds 240 -StepName 'plan_loop_tests'
  if ($plan.TimedOut) { $buildBlocked = $true; $buildBlockerReason = 'PLAN_TIMEOUT' }
  elseif ($plan.ExitCode -ne 0) { $buildBlocked = $true; $buildBlockerReason = 'PLAN_FAILED_EXIT_' + $plan.ExitCode }

  if (-not $buildBlocked) {
    $planText = Get-Content -LiteralPath $planOut -Raw
    $planMatch = [regex]::Match($planText, 'BuildCore plan:\s+(.+)')
    $planPath = if ($planMatch.Success) { $planMatch.Groups[1].Value.Trim() } else { Join-Path $workspaceRoot 'build_graph/debug/ngksbuildcore_plan.json' }
    if (-not (Test-Path -LiteralPath $planPath)) { $buildBlocked = $true; $buildBlockerReason = 'PLAN_PATH_MISSING' }

    if (-not $buildBlocked) {
      $msvcEnvScript = Join-Path $workspaceRoot 'tools/enter_msvc_env.ps1'
      if (-not (Test-Path -LiteralPath $msvcEnvScript)) { $buildBlocked = $true; $buildBlockerReason = 'MSVC_ENV_SCRIPT_MISSING' }
      Set-Content -LiteralPath $buildOut -Value 'build_mode=plan_native_compile_link' -Encoding UTF8
      if (-not $buildBlocked) {
        try { & $msvcEnvScript *>&1 | Out-File -LiteralPath $buildOut -Append -Encoding UTF8 }
        catch { Add-Content -LiteralPath $buildOut -Value ('BUILD_ERROR=MSVC_ENV_IMPORT_FAILED detail=' + $_.Exception.Message); $buildBlocked = $true; $buildBlockerReason = 'MSVC_ENV_IMPORT_FAILED' }
      }

      if (-not $buildBlocked) {
        $planJson = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
        $compileNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Compile apps/loop_tests/main.cpp for loop_tests' })[0]
        $linkNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Link loop_tests' })[0]
        if ($null -eq $compileNode -or $null -eq $linkNode) { Add-Content -LiteralPath $buildOut -Value 'BUILD_ERROR=PLAN_NODE_MISSING target=loop_tests'; $buildBlocked = $true; $buildBlockerReason = 'PLAN_NODE_MISSING' }

        if (-not $buildBlocked) {
          New-Item -ItemType Directory -Path (Split-Path -Parent $loopObj) -Force | Out-Null
          New-Item -ItemType Directory -Path (Split-Path -Parent $loopExe) -Force | Out-Null
          $compileTmp = Join-Path $stageRoot '__compile_stdout.txt'
          $linkTmp = Join-Path $stageRoot '__link_stdout.txt'

          Add-Content -LiteralPath $buildOut -Value ('BUILD_STEP=compile command=' + $compileNode.cmd)
          $compile = Invoke-CmdToFile -CommandLine $compileNode.cmd -OutFile $compileTmp -TimeoutSeconds 360 -StepName 'compile_loop_tests'
          if (Test-Path -LiteralPath $compileTmp) { Get-Content -LiteralPath $compileTmp | Add-Content -LiteralPath $buildOut }
          if ($compile.TimedOut) { Add-Content -LiteralPath $buildOut -Value 'BUILD_ERROR=COMPILE_TIMEOUT'; $buildBlocked = $true; $buildBlockerReason = 'COMPILE_TIMEOUT' }
          elseif ($compile.ExitCode -ne 0) { Add-Content -LiteralPath $buildOut -Value ('BUILD_ERROR=COMPILE_FAILED exit_code=' + $compile.ExitCode); $buildBlocked = $true; $buildBlockerReason = 'COMPILE_FAILED_EXIT_' + $compile.ExitCode }

          if (-not $buildBlocked) {
            Add-Content -LiteralPath $buildOut -Value ('BUILD_STEP=link command=' + $linkNode.cmd)
            $link = Invoke-CmdToFile -CommandLine $linkNode.cmd -OutFile $linkTmp -TimeoutSeconds 360 -StepName 'link_loop_tests'
            if (Test-Path -LiteralPath $linkTmp) { Get-Content -LiteralPath $linkTmp | Add-Content -LiteralPath $buildOut }
            if ($link.TimedOut) { Add-Content -LiteralPath $buildOut -Value 'BUILD_ERROR=LINK_TIMEOUT'; $buildBlocked = $true; $buildBlockerReason = 'LINK_TIMEOUT' }
            elseif ($link.ExitCode -ne 0) { Add-Content -LiteralPath $buildOut -Value ('BUILD_ERROR=LINK_FAILED exit_code=' + $link.ExitCode); $buildBlocked = $true; $buildBlockerReason = 'LINK_FAILED_EXIT_' + $link.ExitCode }
            elseif (-not (Test-Path -LiteralPath $loopExe)) { Add-Content -LiteralPath $buildOut -Value 'BUILD_ERROR=EXE_MISSING_AFTER_LINK'; $buildBlocked = $true; $buildBlockerReason = 'EXE_MISSING_AFTER_LINK' }
          }

          [void](Remove-FileWithRetry -Path $compileTmp)
          [void](Remove-FileWithRetry -Path $linkTmp)
        }
      }
    }
  }
}

if (-not $buildBlocked) {
  $baseEnv = @{ NGK_LOOP_TESTS_MIGRATION_SLICE = $null; NGK_LOOP_TESTS_LEGACY_FALLBACK = $null; NGK_LOOP_TESTS_LEGACY_FALLBACK_OVERRIDE = $null; NGK_LOOP_TESTS_DISABLE_LEGACY_FALLBACK = $null; NGK_LOOP_TESTS_LEGACY_PATH_REENABLED = $null }
  $defaultRun = Invoke-ExeToFile -ExePath $loopExe -InvocationList @() -Env $baseEnv -OutFile $defaultOut -TimeoutSeconds 180 -StepName 'loop_default'
  $legacyFlagsRun = Invoke-ExeToFile -ExePath $loopExe -InvocationList @('--legacy-fallback', '--legacy-fallback-override', '--legacy-path-reenabled') -Env $baseEnv -OutFile $legacyFlagsOut -TimeoutSeconds 180 -StepName 'loop_legacy_flags'
  $sliceRun = Invoke-ExeToFile -ExePath $loopExe -InvocationList @('--migration-slice') -Env $baseEnv -OutFile $sliceOut -TimeoutSeconds 180 -StepName 'loop_slice'
}

$checkResults['check_scope_stays_in_loop_tests_only'] = @{ Result = $false; Reason = 'phase93_1 evidence appears outside apps/loop_tests' }
if ($loopContent -match 'phase93_1_legacy_removal_available=1' -and $sandboxContent -notmatch 'phase93_1_' -and $win32Content -notmatch 'phase93_1_' -and $widgetContent -notmatch 'phase93_1_') {
  $checkResults['check_scope_stays_in_loop_tests_only'].Result = $true
  $checkResults['check_scope_stays_in_loop_tests_only'].Reason = 'phase93_1 changes stay confined to apps/loop_tests and loop_tests build graph target'
}

$checkResults['check_removed_paths_have_no_references'] = @{ Result = $false; Reason = 'removed legacy execution path references still present in source' }
if ($loopContent -notmatch 'int run_legacy_loop_tests\(' -and $loopContent -notmatch 'run_legacy_loop_tests\(') {
  $checkResults['check_removed_paths_have_no_references'].Result = $true
  $checkResults['check_removed_paths_have_no_references'].Reason = 'legacy runtime entrypoint function and call sites are absent from source'
}

$checkResults['check_phase93_1_source_markers_present'] = @{ Result = $false; Reason = 'phase93_1 legacy removal markers missing from loop_tests source' }
if ($loopContent -match 'phase93_1_legacy_removal_contract=inactive_legacy_execution_paths_removed_from_runtime_and_loop_tests_build_configuration_native_only_execution_enforced' -and $loopContent -match 'phase93_1_legacy_path_removed' -and $loopContent -match 'phase93_1_runtime_mode=native_only') {
  $checkResults['check_phase93_1_source_markers_present'].Result = $true
  $checkResults['check_phase93_1_source_markers_present'].Reason = 'phase93_1 markers and native-only runtime mode telemetry are present'
}

$checkResults['check_build_configuration_updated'] = @{ Result = $false; Reason = 'loop_tests build configuration does not encode legacy removal state' }
if ($graphContent -match 'name = "loop_tests"' -and $graphContent -match 'NGK_LOOP_TESTS_LEGACY_REMOVED') {
  $checkResults['check_build_configuration_updated'].Result = $true
  $checkResults['check_build_configuration_updated'].Reason = 'loop_tests target defines now include NGK_LOOP_TESTS_LEGACY_REMOVED in ngksgraph.toml'
}

$checkResults['check_build_materialized'] = @{ Result = $false; Reason = 'build did not materialize' }
if (-not $buildBlocked -and (Test-Path -LiteralPath $loopExe) -and (Get-FileContains -Path $buildOut -Needle 'BUILD_STEP=compile') -and (Get-FileContains -Path $buildOut -Needle 'BUILD_STEP=link')) {
  $checkResults['check_build_materialized'].Result = $true
  $checkResults['check_build_materialized'].Reason = 'real build materialized for loop_tests via compile/link plan nodes'
} elseif ($buildBlocked) { $checkResults['check_build_materialized'].Reason = 'blocked_by_build_materialization=' + $buildBlockerReason }

$checkResults['check_runtime_behavior_unchanged_native'] = @{ Result = $false; Reason = 'runtime does not remain native-only under default, legacy-flags, and slice invocations' }
if (-not $buildBlocked -and ($defaultRun.ExitCode -eq 0) -and ($legacyFlagsRun.ExitCode -eq 0) -and ($sliceRun.ExitCode -eq 0) -and ($defaultRun.TimedOut -eq $false) -and ($legacyFlagsRun.TimedOut -eq $false) -and ($sliceRun.TimedOut -eq $false) -and (Test-LinePresent -Path $defaultOut -Pattern '^phase89_2_policy_mode_selected=native_default$') -and (Test-LinePresent -Path $legacyFlagsOut -Pattern '^phase89_2_policy_mode_selected=native_default$') -and (Test-LinePresent -Path $sliceOut -Pattern '^phase89_2_policy_mode_selected=native_default$') -and (Test-LinePresent -Path $defaultOut -Pattern '^phase90_2_legacy_fallback_usage_observed=0$') -and (Test-LinePresent -Path $legacyFlagsOut -Pattern '^phase90_2_legacy_fallback_usage_observed=0$') -and (Test-LinePresent -Path $sliceOut -Pattern '^phase90_2_legacy_fallback_usage_observed=0$') -and (Test-LinePresent -Path $defaultOut -Pattern '^phase93_1_legacy_path_removed=1$') -and (Test-LinePresent -Path $legacyFlagsOut -Pattern '^phase93_1_legacy_path_removed=1$') -and (Test-LinePresent -Path $sliceOut -Pattern '^phase93_1_legacy_path_removed=1$') -and (Test-LinePresent -Path $defaultOut -Pattern '^phase93_1_runtime_mode=native_only$') -and (Test-LinePresent -Path $legacyFlagsOut -Pattern '^phase93_1_runtime_mode=native_only$') -and (Test-LinePresent -Path $sliceOut -Pattern '^phase93_1_runtime_mode=native_only$')) {
  $checkResults['check_runtime_behavior_unchanged_native'].Result = $true
  $checkResults['check_runtime_behavior_unchanged_native'].Reason = 'all invocations continue to execute native path only with PASS summary'
} elseif ($buildBlocked) { $checkResults['check_runtime_behavior_unchanged_native'].Reason = 'blocked_by_build_materialization=' + $buildBlockerReason }

$checkResults['check_no_build_or_run_regression'] = @{ Result = $false; Reason = 'build or runtime regression detected while applying phase93_1' }
if (-not $buildBlocked -and ($defaultRun.ExitCode -eq 0) -and ($legacyFlagsRun.ExitCode -eq 0) -and ($sliceRun.ExitCode -eq 0) -and (Test-LinePresent -Path $defaultOut -Pattern '^runtime_process_summary\s+phase=termination\s+target=loop_tests\s+context=runtime_init\s+enforcement=PASS\s+') -and (Test-LinePresent -Path $legacyFlagsOut -Pattern '^runtime_process_summary\s+phase=termination\s+target=loop_tests\s+context=runtime_init\s+enforcement=PASS\s+') -and (Test-LinePresent -Path $sliceOut -Pattern '^runtime_process_summary\s+phase=termination\s+target=loop_tests\s+context=runtime_init\s+enforcement=PASS\s+')) {
  $checkResults['check_no_build_or_run_regression'].Result = $true
  $checkResults['check_no_build_or_run_regression'].Reason = 'build and runtime termination guard remain healthy across all test invocations'
} elseif ($buildBlocked) { $checkResults['check_no_build_or_run_regression'].Reason = 'blocked_by_build_materialization=' + $buildBlockerReason }

$failedChecks = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result })
if ($failedChecks.Count -gt 0) { $phaseStatus = 'FAIL' }

$checksFile = Join-Path $stageRoot '93_legacy_removal_checks.txt'
$checkLines = @()
$checkLines += 'phase=phase93_1_legacy_removal'
$checkLines += 'target=apps/loop_tests'
$checkLines += 'scope=remove_inactive_legacy_execution_paths_from_runtime_and_loop_tests_build_graph_while_preserving_native_execution'
$checkLines += 'build_blocked=' + $(if ($buildBlocked) { 'YES' } else { 'NO' })
$checkLines += 'build_blocker_reason=' + $buildBlockerReason
$checkLines += 'default_exit_code=' + $defaultRun.ExitCode
$checkLines += 'legacy_flags_exit_code=' + $legacyFlagsRun.ExitCode
$checkLines += 'slice_exit_code=' + $sliceRun.ExitCode
$checkLines += 'total_checks=' + $checkResults.Count
$checkLines += 'passed_checks=' + ($checkResults.Count - $failedChecks.Count)
$checkLines += 'failed_checks=' + $failedChecks.Count
$checkLines += 'phase_status=' + $phaseStatus
$checkLines += ''
$checkLines += '# Legacy removal checks'
foreach ($checkName in $checkResults.Keys) {
  $result = if ($checkResults[$checkName].Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $checkResults[$checkName].Reason)
}
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=phase93_1_legacy_removal'
$contract += 'objective=Remove_inactive_legacy_execution_paths_from_runtime_and_loop_tests_build_configuration_without_affecting_native_execution'
$contract += 'changes_introduced=Removed_run_legacy_loop_tests_runtime_path_added_phase93_1_native_only_markers_and_updated_loop_tests_build_defines_with_NGK_LOOP_TESTS_LEGACY_REMOVED'
$contract += 'runtime_behavior_changes=Runtime_now_enforces_native_only_execution_even_when_legacy_flags_are_supplied_with_telemetry_indicating_legacy_path_removed'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_or_blocked_see_93_legacy_removal_checks' }))
$contract += 'phase_status=' + $phaseStatus
$contract += 'proof_folder=' + $proofPathRelative
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 93_legacy_removal_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

[void](Remove-FileWithRetry -Path $planOut)
[void](Remove-FileWithRetry -Path $buildOut)
[void](Remove-FileWithRetry -Path $defaultOut)
[void](Remove-FileWithRetry -Path $legacyFlagsOut)
[void](Remove-FileWithRetry -Path $sliceOut)

$expectedEntries = @('93_legacy_removal_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase93_1_legacy_removal_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host ('GATE=' + $(if ($phaseStatus -eq 'PASS') { 'PASS' } else { 'FAIL' }))
Write-Host ('phase93_1_status=' + $phaseStatus)
if ($buildBlocked) { Write-Host ('build_blocker_reason=' + $buildBlockerReason) }
exit 0
