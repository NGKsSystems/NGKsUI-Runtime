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
$proofName = "phase100_1_real_application_build_validation_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

$appMain = Join-Path $workspaceRoot 'apps/desktop_file_tool/main.cpp'
$graphToml = Join-Path $workspaceRoot 'ngksgraph.toml'
$appObj = Join-Path $workspaceRoot 'build/debug/obj/desktop_file_tool/apps/desktop_file_tool/main.obj'
$appExe = Join-Path $workspaceRoot 'build/debug/bin/desktop_file_tool.exe'

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase100_1_real_application_build_validation_*.zip' -ErrorAction SilentlyContinue |
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
  param([string]$ExePath,[string[]]$InvocationList,[string]$OutFile,[int]$TimeoutSeconds,[string]$StepName)
  $errFile = $OutFile + '.stderr.tmp'
  [void](Remove-FileWithRetry -Path $errFile)
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
}

function Test-LinePresent { param([string]$Path,[string]$Pattern) $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue; if (-not $lines) { return $false }; foreach ($line in $lines) { if ($line -match $Pattern) { return $true } }; return $false }
function Get-FileContains { param([string]$Path,[string]$Needle) $content = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop; return $content.Contains($Needle) }
function Test-KvFileWellFormed { param([string]$FilePath) if (-not (Test-Path -LiteralPath $FilePath)) { return $false }; $lines = @(Get-Content -LiteralPath $FilePath | Where-Object { $_ -match '\S' -and $_ -notmatch '^#' }); foreach ($line in $lines) { if ($line -notmatch '^[a-zA-Z_][a-zA-Z0-9_]*=') { return $false } }; return $true }
function New-ProofZip { param([string]$SourceDir,[string]$DestinationZip) if (Test-Path -LiteralPath $DestinationZip) { Remove-Item -LiteralPath $DestinationZip -Force }; Compress-Archive -Path (Join-Path $SourceDir '*') -DestinationPath $DestinationZip -Force }
function Test-ZipContainsEntries { param([string]$ZipFile,[string[]]$ExpectedEntries) Add-Type -AssemblyName System.IO.Compression.FileSystem; $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipFile); try { $entryNames = @($archive.Entries | ForEach-Object { $_.FullName }); foreach ($entry in $ExpectedEntries) { if ($entryNames -notcontains $entry) { return $false } }; return $true } finally { $archive.Dispose() } }

$planOut = Join-Path $stageRoot '__plan_stdout.txt'
$buildOut = Join-Path $stageRoot '__native_build_stdout.txt'
$runOut = Join-Path $stageRoot '__app_run_stdout.txt'
$runRepeatOut = Join-Path $stageRoot '__app_run_repeat_stdout.txt'
$packageManifest = Join-Path $stageRoot 'app_package_manifest.txt'
$appPackageZip = Join-Path $stageRoot 'desktop_file_tool_package.zip'

$appContent = if (Test-Path -LiteralPath $appMain) { Get-Content -LiteralPath $appMain -Raw } else { '' }
$graphContent = if (Test-Path -LiteralPath $graphToml) { Get-Content -LiteralPath $graphToml -Raw } else { '' }

$pythonExe = Join-Path $workspaceRoot '.venv/Scripts/python.exe'
$phaseStatus = 'PASS'
$buildBlocked = $false
$buildBlockerReason = 'NONE'

$appRun = [pscustomobject]@{ ExitCode = -1; TimedOut = $false }
$appRunRepeat = [pscustomobject]@{ ExitCode = -1; TimedOut = $false }
$checkResults = [ordered]@{}

if (-not (Test-Path -LiteralPath $pythonExe)) { $buildBlocked = $true; $buildBlockerReason = 'VENV_PYTHON_MISSING' }

if (-not $buildBlocked) {
  if (Test-Path -LiteralPath $appObj) { Remove-Item -LiteralPath $appObj -Force }
  if (Test-Path -LiteralPath $appExe) { Remove-Item -LiteralPath $appExe -Force }

  $plan = Invoke-PythonToFile -PythonExe $pythonExe -ArgumentList @('-m', 'ngksgraph', 'build', '--profile', 'debug', '--msvc-auto', '--target', 'desktop_file_tool') -OutFile $planOut -TimeoutSeconds 240 -StepName 'plan_desktop_file_tool'
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
        $compileNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Compile apps/desktop_file_tool/main.cpp for desktop_file_tool' })[0]
        $linkNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Link desktop_file_tool' })[0]
        if ($null -eq $compileNode -or $null -eq $linkNode) { Add-Content -LiteralPath $buildOut -Value 'BUILD_ERROR=PLAN_NODE_MISSING target=desktop_file_tool'; $buildBlocked = $true; $buildBlockerReason = 'PLAN_NODE_MISSING' }

        if (-not $buildBlocked) {
          New-Item -ItemType Directory -Path (Split-Path -Parent $appObj) -Force | Out-Null
          New-Item -ItemType Directory -Path (Split-Path -Parent $appExe) -Force | Out-Null
          $compileTmp = Join-Path $stageRoot '__compile_stdout.txt'
          $linkTmp = Join-Path $stageRoot '__link_stdout.txt'

          Add-Content -LiteralPath $buildOut -Value ('BUILD_STEP=compile command=' + $compileNode.cmd)
          $compile = Invoke-CmdToFile -CommandLine $compileNode.cmd -OutFile $compileTmp -TimeoutSeconds 360 -StepName 'compile_desktop_file_tool'
          if (Test-Path -LiteralPath $compileTmp) { Get-Content -LiteralPath $compileTmp | Add-Content -LiteralPath $buildOut }
          if ($compile.TimedOut) { Add-Content -LiteralPath $buildOut -Value 'BUILD_ERROR=COMPILE_TIMEOUT'; $buildBlocked = $true; $buildBlockerReason = 'COMPILE_TIMEOUT' }
          elseif ($compile.ExitCode -ne 0) { Add-Content -LiteralPath $buildOut -Value ('BUILD_ERROR=COMPILE_FAILED exit_code=' + $compile.ExitCode); $buildBlocked = $true; $buildBlockerReason = 'COMPILE_FAILED_EXIT_' + $compile.ExitCode }

          if (-not $buildBlocked) {
            Add-Content -LiteralPath $buildOut -Value ('BUILD_STEP=link command=' + $linkNode.cmd)
            $link = Invoke-CmdToFile -CommandLine $linkNode.cmd -OutFile $linkTmp -TimeoutSeconds 360 -StepName 'link_desktop_file_tool'
            if (Test-Path -LiteralPath $linkTmp) { Get-Content -LiteralPath $linkTmp | Add-Content -LiteralPath $buildOut }
            if ($link.TimedOut) { Add-Content -LiteralPath $buildOut -Value 'BUILD_ERROR=LINK_TIMEOUT'; $buildBlocked = $true; $buildBlockerReason = 'LINK_TIMEOUT' }
            elseif ($link.ExitCode -ne 0) { Add-Content -LiteralPath $buildOut -Value ('BUILD_ERROR=LINK_FAILED exit_code=' + $link.ExitCode); $buildBlocked = $true; $buildBlockerReason = 'LINK_FAILED_EXIT_' + $link.ExitCode }
            elseif (-not (Test-Path -LiteralPath $appExe)) { Add-Content -LiteralPath $buildOut -Value 'BUILD_ERROR=EXE_MISSING_AFTER_LINK'; $buildBlocked = $true; $buildBlockerReason = 'EXE_MISSING_AFTER_LINK' }
          }

          [void](Remove-FileWithRetry -Path $compileTmp)
          [void](Remove-FileWithRetry -Path $linkTmp)
        }
      }
    }
  }
}

if (-not $buildBlocked) {
  $appRun = Invoke-ExeToFile -ExePath $appExe -InvocationList @('--auto-close-ms=2200') -OutFile $runOut -TimeoutSeconds 240 -StepName 'desktop_file_tool_run'
  $appRunRepeat = Invoke-ExeToFile -ExePath $appExe -InvocationList @('--auto-close-ms=2200') -OutFile $runRepeatOut -TimeoutSeconds 240 -StepName 'desktop_file_tool_run_repeat'
}

$checkResults['check_application_source_present'] = @{ Result = $false; Reason = 'desktop_file_tool application source not found or missing core telemetry markers' }
if ($appContent -match 'app_name=desktop_file_tool' -and $appContent -match 'app_ui_interaction_ok=' -and $appContent -match 'app_hidden_execution_paths_detected=' -and $appContent -match 'app_undefined_state_detected=') {
  $checkResults['check_application_source_present'].Result = $true
  $checkResults['check_application_source_present'].Reason = 'application source is present with explicit runtime telemetry for interaction and state safety'
}

$checkResults['check_build_configuration_present'] = @{ Result = $false; Reason = 'desktop_file_tool target missing from ngksgraph.toml' }
if ($graphContent -match 'name = "desktop_file_tool"' -and $graphContent -match 'apps/desktop_file_tool/\*\*/\*\.cpp') {
  $checkResults['check_build_configuration_present'].Result = $true
  $checkResults['check_build_configuration_present'].Reason = 'desktop_file_tool build target is registered in ngksgraph.toml'
}

$checkResults['check_application_built_successfully'] = @{ Result = $false; Reason = 'application build did not complete cleanly' }
if (-not $buildBlocked -and (Test-Path -LiteralPath $appExe) -and (Get-FileContains -Path $buildOut -Needle 'BUILD_STEP=compile') -and (Get-FileContains -Path $buildOut -Needle 'BUILD_STEP=link')) {
  $checkResults['check_application_built_successfully'].Result = $true
  $checkResults['check_application_built_successfully'].Reason = 'compile and link completed and desktop_file_tool.exe was produced'
} elseif ($buildBlocked) { $checkResults['check_application_built_successfully'].Reason = 'blocked_by_build_materialization=' + $buildBlockerReason }

$checkResults['check_application_runs_clean'] = @{ Result = $false; Reason = 'application run failed, timed out, or did not report healthy runtime guard summaries' }
if (-not $buildBlocked -and ($appRun.ExitCode -eq 0) -and ($appRun.TimedOut -eq $false) -and (Test-LinePresent -Path $runOut -Pattern '^app_name=desktop_file_tool$') -and (Test-LinePresent -Path $runOut -Pattern '^SUMMARY: PASS$') -and (Test-LinePresent -Path $runOut -Pattern '^runtime_process_summary\s+phase=startup\s+target=desktop_file_tool\s+context=runtime_init\s+enforcement=PASS\s+') -and (Test-LinePresent -Path $runOut -Pattern '^runtime_process_summary\s+phase=termination\s+target=desktop_file_tool\s+context=runtime_init\s+enforcement=PASS\s+') -and (Test-LinePresent -Path $runOut -Pattern '^runtime_final_status=RUN_OK$')) {
  $checkResults['check_application_runs_clean'].Result = $true
  $checkResults['check_application_runs_clean'].Reason = 'application run completed with PASS summary and runtime guard startup/termination status'
} elseif ($buildBlocked) { $checkResults['check_application_runs_clean'].Reason = 'blocked_by_build_materialization=' + $buildBlockerReason }

$checkResults['check_ui_interaction_works'] = @{ Result = $false; Reason = 'synthetic UI interactions did not execute successfully' }
if (-not $buildBlocked -and ($appRun.ExitCode -eq 0) -and (Test-LinePresent -Path $runOut -Pattern '^app_ui_interaction_ok=1$') -and (Test-LinePresent -Path $runOut -Pattern '^app_refresh_count=[1-9][0-9]*$') -and (Test-LinePresent -Path $runOut -Pattern '^app_next_count=[1-9][0-9]*$') -and (Test-LinePresent -Path $runOut -Pattern '^app_prev_count=[1-9][0-9]*$') -and (Test-LinePresent -Path $runOut -Pattern '^app_apply_filter_count=[1-9][0-9]*$')) {
  $checkResults['check_ui_interaction_works'].Result = $true
  $checkResults['check_ui_interaction_works'].Reason = 'refresh/next/prev/filter interactions all executed at least once'
} elseif ($buildBlocked) { $checkResults['check_ui_interaction_works'].Reason = 'blocked_by_build_materialization=' + $buildBlockerReason }

$checkResults['check_reproducible_execution'] = @{ Result = $false; Reason = 'second run did not reproduce deterministic startup and stability markers' }
if (-not $buildBlocked -and ($appRun.ExitCode -eq 0) -and ($appRunRepeat.ExitCode -eq 0) -and ($appRunRepeat.TimedOut -eq $false) -and (Test-LinePresent -Path $runOut -Pattern '^app_startup_state=deterministic_native_startup$') -and (Test-LinePresent -Path $runRepeatOut -Pattern '^app_startup_state=deterministic_native_startup$') -and (Test-LinePresent -Path $runOut -Pattern '^app_hidden_execution_paths_detected=0$') -and (Test-LinePresent -Path $runRepeatOut -Pattern '^app_hidden_execution_paths_detected=0$') -and (Test-LinePresent -Path $runOut -Pattern '^app_undefined_state_detected=0$') -and (Test-LinePresent -Path $runRepeatOut -Pattern '^app_undefined_state_detected=0$') -and (Test-LinePresent -Path $runOut -Pattern '^app_runtime_crash_detected=0$') -and (Test-LinePresent -Path $runRepeatOut -Pattern '^app_runtime_crash_detected=0$')) {
  $checkResults['check_reproducible_execution'].Result = $true
  $checkResults['check_reproducible_execution'].Reason = 'both runs reported deterministic startup with no hidden paths, undefined states, or crash signals'
} elseif ($buildBlocked) { $checkResults['check_reproducible_execution'].Reason = 'blocked_by_build_materialization=' + $buildBlockerReason }

$checkResults['check_simple_package_flow'] = @{ Result = $false; Reason = 'build-run-package flow could not be completed simply' }
if (-not $buildBlocked -and ($appRun.ExitCode -eq 0) -and (Test-Path -LiteralPath $appExe)) {
  New-Item -ItemType Directory -Path (Join-Path $stageRoot 'package') -Force | Out-Null
  Copy-Item -LiteralPath $appExe -Destination (Join-Path $stageRoot 'package/desktop_file_tool.exe') -Force
  @(
    'package_target=desktop_file_tool',
    'package_method=single_exe_copy_and_zip',
    'package_result=OK'
  ) | Out-File -FilePath $packageManifest -Encoding UTF8 -Force
  Compress-Archive -Path (Join-Path $stageRoot 'package/*') -DestinationPath $appPackageZip -Force
  if ((Test-Path -LiteralPath $appPackageZip) -and (Test-Path -LiteralPath $packageManifest)) {
    $checkResults['check_simple_package_flow'].Result = $true
    $checkResults['check_simple_package_flow'].Reason = 'application was packaged via straightforward exe copy and zip'
  }
} elseif ($buildBlocked) { $checkResults['check_simple_package_flow'].Reason = 'blocked_by_build_materialization=' + $buildBlockerReason }

$failedChecks = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result })
if ($failedChecks.Count -gt 0) { $phaseStatus = 'FAIL' }

$applicationBuilt = if ($checkResults['check_application_built_successfully'].Result) { 'YES' } else { 'NO' }
$runtimeGaps = 'No native file dialog integration; no virtualized large-list widget; no rich text/preview component for file content'
$developerFriction = 'Manual absolute positioning instead of declarative layout constraints; synthetic input validation needed due no UI automation harness; sparse diagnostic categories in runtime logs'
$missingFeatures = 'Scrollable list widget; file icon + metadata table widget; user-visible notification/toast system; packaging helper command for one-step desktop app bundles'
$stabilityResult = if (($checkResults['check_application_runs_clean'].Result) -and ($checkResults['check_reproducible_execution'].Result)) { 'PASS' } else { 'FAIL' }
$nextImprovements = 'Add list-view and scroll container primitives; add native file dialog bridge; add declarative layout helpers; add built-in app packaging command; add structured log levels/categories'

$checksFile = Join-Path $stageRoot '100_real_application_build_validation_checks.txt'
$checkLines = @()
$checkLines += 'phase=phase100_1_real_application_build_validation'
$checkLines += 'target=apps/desktop_file_tool'
$checkLines += 'build_blocked=' + $(if ($buildBlocked) { 'YES' } else { 'NO' })
$checkLines += 'build_blocker_reason=' + $buildBlockerReason
$checkLines += 'run_exit_code=' + $appRun.ExitCode
$checkLines += 'run_repeat_exit_code=' + $appRunRepeat.ExitCode
$checkLines += 'total_checks=' + $checkResults.Count
$checkLines += 'passed_checks=' + ($checkResults.Count - $failedChecks.Count)
$checkLines += 'failed_checks=' + $failedChecks.Count
$checkLines += 'phase_status=' + $phaseStatus
$checkLines += ''
$checkLines += '# Real app validation checks'
foreach ($checkName in $checkResults.Keys) {
  $result = if ($checkResults[$checkName].Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $checkResults[$checkName].Reason)
}
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$outputFile = Join-Path $stageRoot '100_real_application_output.txt'
$outputLines = @(
  ('application_built=' + $applicationBuilt),
  ('runtime_gaps_found=' + $runtimeGaps),
  ('developer_friction_points=' + $developerFriction),
  ('missing_features=' + $missingFeatures),
  ('stability_result=' + $stabilityResult),
  ('next_required_improvements=' + $nextImprovements)
)
$outputLines | Out-File -FilePath $outputFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 100_real_application_build_validation_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $outputFile)) { Write-Host 'FATAL: 100_real_application_output.txt malformed'; exit 1 }

[void](Remove-FileWithRetry -Path $planOut)
[void](Remove-FileWithRetry -Path $buildOut)
[void](Remove-FileWithRetry -Path $runOut)
[void](Remove-FileWithRetry -Path $runRepeatOut)

$expectedEntries = @('100_real_application_build_validation_checks.txt', '100_real_application_output.txt')
if (Test-Path -LiteralPath $packageManifest) { $expectedEntries += 'app_package_manifest.txt' }
if (Test-Path -LiteralPath $appPackageZip) { $expectedEntries += 'desktop_file_tool_package.zip' }
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase100_1_real_application_build_validation_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host ('GATE=' + $(if ($phaseStatus -eq 'PASS') { 'PASS' } else { 'FAIL' }))
Write-Host ('phase100_1_status=' + $phaseStatus)
Write-Host ('application_built=' + $applicationBuilt)
Write-Host ('runtime_gaps_found=' + $runtimeGaps)
Write-Host ('developer_friction_points=' + $developerFriction)
Write-Host ('missing_features=' + $missingFeatures)
Write-Host ('stability_result=' + $stabilityResult)
Write-Host ('next_required_improvements=' + $nextImprovements)
if ($buildBlocked) { Write-Host ('build_blocker_reason=' + $buildBlockerReason) }
exit 0
