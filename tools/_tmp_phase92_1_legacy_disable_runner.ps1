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
$proofName = "phase92_1_legacy_disable_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

$loopMain = Join-Path $workspaceRoot 'apps/loop_tests/main.cpp'
$loopObj = Join-Path $workspaceRoot 'build/debug/obj/loop_tests/apps/loop_tests/main.obj'
$loopExe = Join-Path $workspaceRoot 'build/debug/bin/loop_tests.exe'
$sandboxMain = Join-Path $workspaceRoot 'apps/sandbox_app/main.cpp'
$win32Main = Join-Path $workspaceRoot 'apps/win32_sandbox/main.cpp'
$widgetMain = Join-Path $workspaceRoot 'apps/widget_sandbox/main.cpp'

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase92_1_legacy_disable_*.zip' -ErrorAction SilentlyContinue |
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

$planOut     = Join-Path $stageRoot '__plan_stdout.txt'
$buildOut    = Join-Path $stageRoot '__native_build_stdout.txt'
$defaultOut  = Join-Path $stageRoot '__loop_default_stdout.txt'
$overrideOut = Join-Path $stageRoot '__loop_override_only_stdout.txt'
$reenabledOut = Join-Path $stageRoot '__loop_reenabled_stdout.txt'
$sliceOut    = Join-Path $stageRoot '__loop_reenabled_slice_wins_stdout.txt'
$disableOut  = Join-Path $stageRoot '__loop_reenabled_disable_wins_stdout.txt'

$loopContent   = if (Test-Path -LiteralPath $loopMain)    { Get-Content -LiteralPath $loopMain    -Raw } else { '' }
$sandboxContent = if (Test-Path -LiteralPath $sandboxMain) { Get-Content -LiteralPath $sandboxMain -Raw } else { '' }
$win32Content   = if (Test-Path -LiteralPath $win32Main)   { Get-Content -LiteralPath $win32Main   -Raw } else { '' }
$widgetContent  = if (Test-Path -LiteralPath $widgetMain)  { Get-Content -LiteralPath $widgetMain  -Raw } else { '' }

$pythonExe = Join-Path $workspaceRoot '.venv/Scripts/python.exe'
$phaseStatus = 'PASS'
$buildBlocked = $false
$buildBlockerReason = 'NONE'

$defaultRun   = [pscustomobject]@{ ExitCode = -1; TimedOut = $false }
$overrideRun  = [pscustomobject]@{ ExitCode = -1; TimedOut = $false }
$reenabledRun = [pscustomobject]@{ ExitCode = -1; TimedOut = $false }
$sliceRun     = [pscustomobject]@{ ExitCode = -1; TimedOut = $false }
$disableRun   = [pscustomobject]@{ ExitCode = -1; TimedOut = $false }
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
        $linkNode    = @($planJson.nodes | Where-Object { $_.desc -eq 'Link loop_tests' })[0]
        if ($null -eq $compileNode -or $null -eq $linkNode) { Add-Content -LiteralPath $buildOut -Value 'BUILD_ERROR=PLAN_NODE_MISSING target=loop_tests'; $buildBlocked = $true; $buildBlockerReason = 'PLAN_NODE_MISSING' }

        if (-not $buildBlocked) {
          New-Item -ItemType Directory -Path (Split-Path -Parent $loopObj) -Force | Out-Null
          New-Item -ItemType Directory -Path (Split-Path -Parent $loopExe) -Force | Out-Null
          $compileTmp = Join-Path $stageRoot '__compile_stdout.txt'
          $linkTmp    = Join-Path $stageRoot '__link_stdout.txt'

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

# --- Run all five execution modes ---
if (-not $buildBlocked) {
  $baseEnv = @{
    NGK_LOOP_TESTS_LEGACY_FALLBACK          = $null
    NGK_LOOP_TESTS_MIGRATION_SLICE          = $null
    NGK_LOOP_TESTS_DISABLE_LEGACY_FALLBACK  = $null
    NGK_LOOP_TESTS_LEGACY_FALLBACK_OVERRIDE = $null
    NGK_LOOP_TESTS_LEGACY_PATH_REENABLED    = $null
  }
  # Mode 1: default (no flags)
  $defaultRun = Invoke-ExeToFile -ExePath $loopExe -InvocationList @() -Env $baseEnv -OutFile $defaultOut -TimeoutSeconds 180 -StepName 'loop_default'
  # Mode 2: override-only (P91_2 override present but no P92_1 reenabler)
  $overrideRun = Invoke-ExeToFile -ExePath $loopExe -InvocationList @('--legacy-fallback', '--legacy-fallback-override') -Env $baseEnv -OutFile $overrideOut -TimeoutSeconds 180 -StepName 'loop_override_only'
  # Mode 3: fully re-enabled (all three explicit signals)
  $reenabledRun = Invoke-ExeToFile -ExePath $loopExe -InvocationList @('--legacy-fallback', '--legacy-fallback-override', '--legacy-path-reenabled') -Env $baseEnv -OutFile $reenabledOut -TimeoutSeconds 180 -StepName 'loop_reenabled'
  # Mode 4: re-enabled but slice wins
  $sliceRun = Invoke-ExeToFile -ExePath $loopExe -InvocationList @('--legacy-fallback', '--legacy-fallback-override', '--legacy-path-reenabled', '--migration-slice') -Env $baseEnv -OutFile $sliceOut -TimeoutSeconds 180 -StepName 'loop_reenabled_slice_wins'
  # Mode 5: re-enabled but disable wins
  $disableRun = Invoke-ExeToFile -ExePath $loopExe -InvocationList @('--legacy-fallback', '--legacy-fallback-override', '--legacy-path-reenabled', '--disable-legacy-fallback') -Env $baseEnv -OutFile $disableOut -TimeoutSeconds 180 -StepName 'loop_reenabled_disable_wins'
}

# --- CHECK 1: scope ---
$checkResults['check_scope_stays_in_loop_tests_only'] = @{ Result = $false; Reason = 'phase92_1 evidence appears outside apps/loop_tests' }
if ($loopContent -match 'phase92_1_legacy_disable_available=1' -and
    $sandboxContent -notmatch 'phase92_1_' -and
    $win32Content   -notmatch 'phase92_1_' -and
    $widgetContent  -notmatch 'phase92_1_') {
  $checkResults['check_scope_stays_in_loop_tests_only'].Result = $true
  $checkResults['check_scope_stays_in_loop_tests_only'].Reason = 'phase92_1 changes stay confined to apps/loop_tests'
}

# --- CHECK 2: source markers ---
$checkResults['check_phase92_1_source_markers_present'] = @{ Result = $false; Reason = 'phase92_1 legacy disable markers missing from loop_tests source' }
if ($loopContent -match 'phase92_1_legacy_disable_contract=legacy_path_disabled_at_startup_and_requires_all_three_explicit_signals_to_reenable' -and
    $loopContent -match 'is_phase92_1_legacy_path_reenabled' -and
    $loopContent -match 'phase92_1_legacy_path_globally_disabled' -and
    $loopContent -match 'phase92_1_legacy_path_disabled_for_this_run' -and
    $loopContent -match 'phase92_1_legacy_execution_state') {
  $checkResults['check_phase92_1_source_markers_present'].Result = $true
  $checkResults['check_phase92_1_source_markers_present'].Reason = 'phase92_1 source markers express globally-disabled legacy path with explicit three-signal reenable mechanism'
}

# --- CHECK 3: build ---
$checkResults['check_build_materialized'] = @{ Result = $false; Reason = 'build did not materialize' }
if (-not $buildBlocked -and (Test-Path -LiteralPath $loopExe) -and
    (Get-FileContains -Path $buildOut -Needle 'BUILD_STEP=compile') -and
    (Get-FileContains -Path $buildOut -Needle 'BUILD_STEP=link')) {
  $checkResults['check_build_materialized'].Result = $true
  $checkResults['check_build_materialized'].Reason = 'real build materialized for loop_tests via compile/link plan nodes'
} elseif ($buildBlocked) { $checkResults['check_build_materialized'].Reason = 'blocked_by_build_materialization=' + $buildBlockerReason }

# --- CHECK 4: legacy never runs by default ---
$checkResults['check_legacy_never_runs_by_default'] = @{ Result = $false; Reason = 'legacy path still executes during normal startup' }
if (-not $buildBlocked -and
    ($defaultRun.TimedOut -eq $false) -and ($defaultRun.ExitCode -eq 0) -and
    (Test-LinePresent -Path $defaultOut -Pattern '^phase89_2_policy_mode_selected=native_default$') -and
    (Test-LinePresent -Path $defaultOut -Pattern '^phase90_2_policy_mode_reason=native_default_policy$') -and
    (Test-LinePresent -Path $defaultOut -Pattern '^phase92_1_legacy_path_disabled_at_startup=1$') -and
    (Test-LinePresent -Path $defaultOut -Pattern '^phase92_1_legacy_path_reenabler_supplied=0$') -and
    (Test-LinePresent -Path $defaultOut -Pattern '^phase92_1_legacy_path_disabled_for_this_run=1$') -and
    (Test-LinePresent -Path $defaultOut -Pattern '^phase92_1_legacy_execution_state=legacy_disabled_at_startup$')) {
  $checkResults['check_legacy_never_runs_by_default'].Result = $true
  $checkResults['check_legacy_never_runs_by_default'].Reason = 'default startup stays on native path and emits legacy_disabled_at_startup state'
} elseif ($buildBlocked) { $checkResults['check_legacy_never_runs_by_default'].Reason = 'blocked_by_build_materialization=' + $buildBlockerReason }

# --- CHECK 5: P91_2 override alone cannot reach legacy under P92_1 disable ---
$checkResults['check_override_alone_cannot_reach_legacy'] = @{ Result = $false; Reason = 'p91_2 override alone still reaches legacy path despite p92_1 disable' }
if (-not $buildBlocked -and
    ($overrideRun.TimedOut -eq $false) -and ($overrideRun.ExitCode -eq 0) -and
    (Test-LinePresent -Path $overrideOut -Pattern '^phase89_2_policy_mode_selected=native_default$') -and
    (Test-LinePresent -Path $overrideOut -Pattern '^phase90_2_policy_mode_reason=legacy_path_disabled_at_startup$') -and
    (Test-LinePresent -Path $overrideOut -Pattern '^phase90_2_legacy_fallback_usage_observed=0$') -and
    (Test-LinePresent -Path $overrideOut -Pattern '^phase92_1_legacy_path_disabled_at_startup=1$') -and
    (Test-LinePresent -Path $overrideOut -Pattern '^phase92_1_legacy_path_reenabler_supplied=0$') -and
    (Test-LinePresent -Path $overrideOut -Pattern '^phase92_1_legacy_path_disabled_for_this_run=1$') -and
    (Test-LinePresent -Path $overrideOut -Pattern '^phase92_1_legacy_execution_state=legacy_disabled_override_present_but_path_disabled$')) {
  $checkResults['check_override_alone_cannot_reach_legacy'].Result = $true
  $checkResults['check_override_alone_cannot_reach_legacy'].Reason = 'p91_2 override without p92_1 reenabler is blocked by legacy_path_disabled_at_startup'
} elseif ($buildBlocked) { $checkResults['check_override_alone_cannot_reach_legacy'].Reason = 'blocked_by_build_materialization=' + $buildBlockerReason }

# --- CHECK 6: explicit reenable works (all three signals) ---
$checkResults['check_explicit_reenable_works'] = @{ Result = $false; Reason = 'explicit three-signal reenable does not restore legacy path' }
if (-not $buildBlocked -and
    ($reenabledRun.TimedOut -eq $false) -and ($reenabledRun.ExitCode -eq 0) -and
    (Test-LinePresent -Path $reenabledOut -Pattern '^phase89_2_policy_mode_selected=legacy_fallback$') -and
    (Test-LinePresent -Path $reenabledOut -Pattern '^phase90_2_policy_mode_reason=legacy_fallback_explicit_override$') -and
    (Test-LinePresent -Path $reenabledOut -Pattern '^phase90_2_legacy_fallback_usage_observed=1$') -and
    (Test-LinePresent -Path $reenabledOut -Pattern '^phase92_1_legacy_path_disabled_at_startup=1$') -and
    (Test-LinePresent -Path $reenabledOut -Pattern '^phase92_1_legacy_path_reenabler_supplied=1$') -and
    (Test-LinePresent -Path $reenabledOut -Pattern '^phase92_1_legacy_path_disabled_for_this_run=0$') -and
    (Test-LinePresent -Path $reenabledOut -Pattern '^phase92_1_legacy_execution_state=legacy_reenabled_explicit$') -and
    (Test-LinePresent -Path $reenabledOut -Pattern '^SUMMARY: PASS$')) {
  $checkResults['check_explicit_reenable_works'].Result = $true
  $checkResults['check_explicit_reenable_works'].Reason = 'all three explicit signals together restore legacy path and emit legacy_reenabled_explicit state'
} elseif ($buildBlocked) { $checkResults['check_explicit_reenable_works'].Reason = 'blocked_by_build_materialization=' + $buildBlockerReason }

# --- CHECK 7: slice and disable controls still supersede reenable ---
$checkResults['check_higher_order_controls_still_win'] = @{ Result = $false; Reason = 'explicit_slice or disable_legacy do not supersede the reenable path' }
if (-not $buildBlocked -and
    ($sliceRun.TimedOut -eq $false) -and ($sliceRun.ExitCode -eq 0) -and
    (Test-LinePresent -Path $sliceOut -Pattern '^phase89_2_policy_mode_selected=native_default$') -and
    (Test-LinePresent -Path $sliceOut -Pattern '^phase90_2_policy_mode_reason=explicit_slice_override$') -and
    (Test-LinePresent -Path $sliceOut -Pattern '^phase90_2_legacy_fallback_usage_observed=0$') -and
    (Test-LinePresent -Path $sliceOut -Pattern '^phase92_1_legacy_execution_state=native_default_enforced$') -and
    ($disableRun.TimedOut -eq $false) -and ($disableRun.ExitCode -eq 0) -and
    (Test-LinePresent -Path $disableOut -Pattern '^phase89_2_policy_mode_selected=native_default$') -and
    (Test-LinePresent -Path $disableOut -Pattern '^phase90_2_policy_mode_reason=legacy_fallback_disable_requested$') -and
    (Test-LinePresent -Path $disableOut -Pattern '^phase90_2_legacy_fallback_usage_observed=0$') -and
    (Test-LinePresent -Path $disableOut -Pattern '^phase92_1_legacy_execution_state=native_default_enforced$')) {
  $checkResults['check_higher_order_controls_still_win'].Result = $true
  $checkResults['check_higher_order_controls_still_win'].Reason = 'explicit_slice and disable_legacy both supersede the reenable signal and keep execution native'
} elseif ($buildBlocked) { $checkResults['check_higher_order_controls_still_win'].Reason = 'blocked_by_build_materialization=' + $buildBlockerReason }

# --- CHECK 8: runtime clearly reports disabled state ---
$checkResults['check_runtime_reports_disabled_state'] = @{ Result = $false; Reason = 'runtime does not clearly report legacy disabled state in output' }
if (-not $buildBlocked -and
    (Test-LinePresent -Path $defaultOut  -Pattern '^phase92_1_legacy_disable_available=1$') -and
    (Test-LinePresent -Path $defaultOut  -Pattern '^phase92_1_legacy_disable_contract=legacy_path_disabled_at_startup_and_requires_all_three_explicit_signals_to_reenable$') -and
    (Test-LinePresent -Path $defaultOut  -Pattern '^phase92_1_legacy_execution_state=legacy_disabled_at_startup$') -and
    (Test-LinePresent -Path $overrideOut -Pattern '^phase92_1_legacy_execution_state=legacy_disabled_override_present_but_path_disabled$') -and
    (Test-LinePresent -Path $reenabledOut -Pattern '^phase92_1_legacy_execution_state=legacy_reenabled_explicit$') -and
    (Test-LinePresent -Path $sliceOut    -Pattern '^phase92_1_legacy_execution_state=native_default_enforced$') -and
    (Test-LinePresent -Path $disableOut  -Pattern '^phase92_1_legacy_execution_state=native_default_enforced$')) {
  $checkResults['check_runtime_reports_disabled_state'].Result = $true
  $checkResults['check_runtime_reports_disabled_state'].Reason = 'runtime emits phase92_1 availability contract and execution state across all five modes'
} elseif ($buildBlocked) { $checkResults['check_runtime_reports_disabled_state'].Reason = 'blocked_by_build_materialization=' + $buildBlockerReason }

# --- CHECK 9: no regressions ---
$checkResults['check_no_build_or_run_regression'] = @{ Result = $false; Reason = 'build or run regression detected while applying phase92_1' }
if (-not $buildBlocked -and
    ($defaultRun.ExitCode   -eq 0) -and ($defaultRun.TimedOut   -eq $false) -and
    ($overrideRun.ExitCode  -eq 0) -and ($overrideRun.TimedOut  -eq $false) -and
    ($reenabledRun.ExitCode -eq 0) -and ($reenabledRun.TimedOut -eq $false) -and
    ($sliceRun.ExitCode     -eq 0) -and ($sliceRun.TimedOut     -eq $false) -and
    ($disableRun.ExitCode   -eq 0) -and ($disableRun.TimedOut   -eq $false) -and
    (Test-LinePresent -Path $defaultOut   -Pattern '^runtime_process_summary\s+phase=termination\s+target=loop_tests\s+context=runtime_init\s+enforcement=PASS\s+') -and
    (Test-LinePresent -Path $overrideOut  -Pattern '^runtime_process_summary\s+phase=termination\s+target=loop_tests\s+context=runtime_init\s+enforcement=PASS\s+') -and
    (Test-LinePresent -Path $reenabledOut -Pattern '^runtime_process_summary\s+phase=termination\s+target=loop_tests\s+context=runtime_init\s+enforcement=PASS\s+') -and
    (Test-LinePresent -Path $sliceOut     -Pattern '^runtime_process_summary\s+phase=termination\s+target=loop_tests\s+context=runtime_init\s+enforcement=PASS\s+') -and
    (Test-LinePresent -Path $disableOut   -Pattern '^runtime_process_summary\s+phase=termination\s+target=loop_tests\s+context=runtime_init\s+enforcement=PASS\s+')) {
  $checkResults['check_no_build_or_run_regression'].Result = $true
  $checkResults['check_no_build_or_run_regression'].Reason = 'build and all five execution modes complete without regression across compile, link, and runtime'
} elseif ($buildBlocked) { $checkResults['check_no_build_or_run_regression'].Reason = 'blocked_by_build_materialization=' + $buildBlockerReason }

$failedChecks = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result })
if ($failedChecks.Count -gt 0) { $phaseStatus = 'FAIL' }

# --- Write checks file ---
$checksFile = Join-Path $stageRoot '92_legacy_disable_checks.txt'
$checkLines = @()
$checkLines += 'phase=phase92_1_legacy_disable'
$checkLines += 'target=apps/loop_tests'
$checkLines += 'scope=disable_legacy_execution_path_from_normal_startup_and_require_three_explicit_signals_to_reenable_on_apps_loop_tests_only'
$checkLines += 'build_blocked=' + $(if ($buildBlocked) { 'YES' } else { 'NO' })
$checkLines += 'build_blocker_reason=' + $buildBlockerReason
$checkLines += 'default_exit_code=' + $defaultRun.ExitCode
$checkLines += 'override_only_exit_code=' + $overrideRun.ExitCode
$checkLines += 'reenabled_exit_code=' + $reenabledRun.ExitCode
$checkLines += 'reenabled_slice_wins_exit_code=' + $sliceRun.ExitCode
$checkLines += 'reenabled_disable_wins_exit_code=' + $disableRun.ExitCode
$checkLines += 'total_checks=' + $checkResults.Count
$checkLines += 'passed_checks=' + ($checkResults.Count - $failedChecks.Count)
$checkLines += 'failed_checks=' + $failedChecks.Count
$checkLines += 'phase_status=' + $phaseStatus
$checkLines += ''
$checkLines += '# Legacy disable checks'
foreach ($checkName in $checkResults.Keys) {
  $result = if ($checkResults[$checkName].Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $checkResults[$checkName].Reason)
}
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

# --- Write contract file ---
$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=phase92_1_legacy_disable'
$contract += 'objective=Disable_legacy_execution_path_from_normal_startup_with_explicit_three_signal_reenable_mechanism_for_apps_loop_tests'
$contract += 'changes_introduced=Added_phase92_1_globally_disabled_flag_and_is_phase92_1_legacy_path_reenabled_helper_disabling_legacy_by_default_and_requiring_all_three_explicit_signals_to_reenable'
$contract += 'runtime_behavior_changes=Legacy_path_is_disabled_at_startup_P91_2_override_alone_is_insufficient_and_all_three_signals_required_legacy_fallback_override_legacy_path_reenabled_must_be_present_simultaneously'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_or_blocked_see_92_legacy_disable_checks' }))
$contract += 'phase_status=' + $phaseStatus
$contract += 'proof_folder=' + $proofPathRelative
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile))   { Write-Host 'FATAL: 92_legacy_disable_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

[void](Remove-FileWithRetry -Path $planOut)
[void](Remove-FileWithRetry -Path $buildOut)
[void](Remove-FileWithRetry -Path $defaultOut)
[void](Remove-FileWithRetry -Path $overrideOut)
[void](Remove-FileWithRetry -Path $reenabledOut)
[void](Remove-FileWithRetry -Path $sliceOut)
[void](Remove-FileWithRetry -Path $disableOut)

$expectedEntries = @('92_legacy_disable_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase92_1_legacy_disable_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host ('GATE=' + $(if ($phaseStatus -eq 'PASS') { 'PASS' } else { 'FAIL' }))
Write-Host ('phase92_1_status=' + $phaseStatus)
if ($buildBlocked) { Write-Host ('build_blocker_reason=' + $buildBlockerReason) }
exit 0
