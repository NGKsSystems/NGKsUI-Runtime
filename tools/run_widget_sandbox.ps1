param(
  [ValidateSet('Debug', 'Release')]
  [string]$Config = 'Debug',
  [string[]]$PassArgs = @(),
  [string]$ExePath = '',
  [switch]$NoLaunch,
  [switch]$InheritModeEnv
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'widget_sandbox_launch_common.ps1')

function Convert-ToIsoUtc {
  param([datetime]$Value)
  return $Value.ToUniversalTime().ToString('o')
}

function Write-TimingBoundary {
  param(
    [string]$Name,
    [string]$TimestampUtc,
    [string]$Source,
    [string]$Quality
  )

  Write-Output ('TIMING_BOUNDARY name=' + $Name + ' ts_utc=' + $TimestampUtc + ' source=' + $Source + ' quality=' + $Quality)
}

function Get-LastPrefixedValue {
  param(
    [string[]]$Lines,
    [string]$Prefix,
    [string]$Default = 'unknown'
  )

  for ($i = $Lines.Count - 1; $i -ge 0; --$i) {
    if ($Lines[$i].StartsWith($Prefix, [System.StringComparison]::Ordinal)) {
      return $Lines[$i].Substring($Prefix.Length).Trim()
    }
  }

  return $Default
}

function Get-LastProcessSummaryField {
  param(
    [string[]]$Lines,
    [string]$Field,
    [string]$Default = 'unknown'
  )

  $pattern = '(?:^|\s)' + [regex]::Escape($Field) + '=([^\s]+)'
  for ($i = $Lines.Count - 1; $i -ge 0; --$i) {
    $line = $Lines[$i]
    if (-not $line.StartsWith('runtime_process_summary ', [System.StringComparison]::Ordinal)) {
      continue
    }
    $match = [regex]::Match($line, $pattern)
    if ($match.Success) {
      return $match.Groups[1].Value
    }
  }

  return $Default
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$launchExitCode = 0
$launcherInvocationStartUtc = Convert-ToIsoUtc -Value (Get-Date).ToUniversalTime()
$widgetProcessSpawnUtc = 'unavailable'
$runtimeInitGuardStartUtc = 'unavailable'
$runtimeInitGuardEndUtc = 'unavailable'
$firstFramePresentUtc = 'unavailable'
$autocloseTriggerUtc = 'unavailable'
$terminationGuardStartUtc = 'unavailable'
$terminationGuardEndUtc = 'unavailable'
$modeEnvKeys = @(
  'NGK_WIDGET_SANDBOX_DEMO',
  'NGK_WIDGET_VISUAL_BASELINE',
  'NGK_WIDGET_EXTENSION_VISUAL_BASELINE',
  'NGK_WIDGET_EXTENSION_STRESS_DEMO'
)

$explicitModeArgRegex = '^(--demo|--visual-baseline|--extension-visual-baseline|--extension-stress-demo)$'
$hasExplicitModeArg = $false
foreach ($arg in $PassArgs) {
  if ($arg -match $explicitModeArgRegex) {
    $hasExplicitModeArg = $true
    break
  }
}

$effectivePassArgs = New-Object System.Collections.Generic.List[string]
$autoCloseRequested = $false
$autoCloseRequestMs = ''
$hasSelfClosingModeArg = $false
$extensionLaneRequested = $false
foreach ($arg in $PassArgs) {
  if ($arg -match '^--auto-close-ms=(\d+)$') {
    $autoCloseRequested = $true
    $autoCloseRequestMs = $Matches[1]
    continue
  }

  if ($arg -eq '--visual-baseline' -or $arg -eq '--extension-visual-baseline' -or $arg -eq '--extension-stress-demo') {
    $hasSelfClosingModeArg = $true
  }

  if ($arg -eq '--sandbox-extension' -or $arg -eq '--sandbox-lane=extension') {
    $extensionLaneRequested = $true
  }

  $effectivePassArgs.Add($arg)
}

$laneEnv = [Environment]::GetEnvironmentVariable('NGK_WIDGET_SANDBOX_LANE', 'Process')
if (-not $extensionLaneRequested -and -not [string]::IsNullOrWhiteSpace($laneEnv)) {
  if ($laneEnv.Equals('extension', [System.StringComparison]::OrdinalIgnoreCase) -or
      $laneEnv.Equals('ext', [System.StringComparison]::OrdinalIgnoreCase)) {
    $extensionLaneRequested = $true
  }
}

$autoCloseShim = 'none'
if ($autoCloseRequested -and -not $hasSelfClosingModeArg) {
  $shimArg = if ($extensionLaneRequested) { '--extension-visual-baseline' } else { '--visual-baseline' }
  $effectivePassArgs.Add($shimArg)
  $autoCloseShim = $shimArg
}

$modeEnvRestore = @{}

try {
  if ([string]::IsNullOrWhiteSpace($repoRoot)) {
    throw 'unsafe_launch: launcher root resolution failed'
  }
  if (-not (Test-Path -LiteralPath (Join-Path $repoRoot '.git')) -or
      -not (Test-Path -LiteralPath (Join-Path $repoRoot 'apps/widget_sandbox/main.cpp'))) {
    throw ("unsafe_launch: launcher is not under NGKsUI Runtime repo root: " + $repoRoot)
  }
  $cwd = (Resolve-Path '.').Path
  if (-not $cwd.Equals($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw ("unsafe_launch: repo root mismatch, expected cwd=" + $repoRoot + ", actual cwd=" + $cwd)
  }

  Invoke-Phase532MandatoryGuard -RepoRoot $repoRoot

  $exe = Resolve-CanonicalWidgetSandboxExe -RepoRoot $repoRoot -Config $Config -RequestedExePath $ExePath
  $buildInfo = Get-WidgetSandboxBuildInfo -ExePath $exe -Config $Config -RepoRoot $repoRoot

  $identity = "canonical|" + $Config.ToLowerInvariant() + "|" + $buildInfo.exe_write_time_utc
  $env:NGK_WIDGET_LAUNCH_IDENTITY = $identity
  $env:NGK_WIDGET_CANONICAL_EXE = $exe

  if (-not $InheritModeEnv -and -not $hasExplicitModeArg) {
    foreach ($key in $modeEnvKeys) {
      $modeEnvRestore[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
      [Environment]::SetEnvironmentVariable($key, '0', 'Process')
    }
  }

  Write-Output ("LAUNCH_REPO=" + $repoRoot)
  Write-Output ("LAUNCH_CONFIG=" + $Config)
  Write-Output ("LAUNCH_EXE=" + $exe)
  Write-Output ("LAUNCH_BUILDINFO=" + $buildInfo.info_path)
  Write-Output ("LAUNCH_EXE_WRITE_UTC=" + $buildInfo.exe_write_time_utc)
  Write-Output ("LAUNCH_IDENTITY=" + $identity)
  Write-Output ("LAUNCH_MODE_ENV_POLICY=" + $(if ($InheritModeEnv -or $hasExplicitModeArg) { 'inherited_or_explicit' } else { 'forced-default' }))
  Write-Output ('LAUNCH_ARGS=' + $(if ($effectivePassArgs.Count -gt 0) { ($effectivePassArgs.ToArray() -join ' ') } else { '(none)' }))
  Write-Output ('LAUNCH_AUTOCLOSE_REQUEST_MS=' + $(if ($autoCloseRequested) { $autoCloseRequestMs } else { 'none' }))
  Write-Output ('LAUNCH_AUTOCLOSE_SHIM=' + $autoCloseShim)

  if ($NoLaunch) {
    exit 0
  }

  $captured = New-Object System.Collections.Generic.List[string]
  $capturedEvents = New-Object System.Collections.Generic.List[object]
  $widgetProcessSpawnUtc = Convert-ToIsoUtc -Value (Get-Date).ToUniversalTime()
  Write-TimingBoundary -Name 'launcher_invocation_start_timestamp' -TimestampUtc $launcherInvocationStartUtc -Source 'launcher' -Quality 'exact'
  Write-TimingBoundary -Name 'widget_process_spawn_timestamp' -TimestampUtc $widgetProcessSpawnUtc -Source 'launcher' -Quality 'exact'

  & $exe @($effectivePassArgs.ToArray()) 2>&1 | ForEach-Object {
    $line = [string]$_
    $captured.Add($line)
    $capturedEvents.Add([pscustomobject]@{ Text = $line; ObservedUtc = (Get-Date).ToUniversalTime() })
    $line
  }
  $launchExitCode = $LASTEXITCODE

  foreach ($evt in $capturedEvents) {
    $line = [string]$evt.Text
    $observedUtc = [datetime]$evt.ObservedUtc

    if ($firstFramePresentUtc -eq 'unavailable' -and $line -match '^widget_first_frame=1$') {
      $firstFramePresentUtc = Convert-ToIsoUtc -Value $observedUtc
    }

    if ($line -match '^runtime_trust_guard_elapsed_ms=(\d+)\s+context=(\S+)$') {
      $elapsedMs = [int]$Matches[1]
      $contextName = $Matches[2]
      $end = $observedUtc
      $start = $observedUtc.AddMilliseconds(-1 * $elapsedMs)

      if ($contextName -eq 'runtime_init') {
        $runtimeInitGuardEndUtc = Convert-ToIsoUtc -Value $end
        $runtimeInitGuardStartUtc = Convert-ToIsoUtc -Value $start
      }
      elseif ($contextName -eq 'save_export') {
        $terminationGuardEndUtc = Convert-ToIsoUtc -Value $end
        $terminationGuardStartUtc = Convert-ToIsoUtc -Value $start
      }
    }

    if ($autocloseTriggerUtc -eq 'unavailable' -and $line -match '^widget_visual_baseline_capture_done=1$') {
      $autocloseTriggerUtc = Convert-ToIsoUtc -Value $observedUtc
    }
  }

  if ($autocloseTriggerUtc -eq 'unavailable' -and $autoCloseRequested) {
    $autocloseTriggerUtc = 'unavailable'
  }

  $lines = $captured.ToArray()
  $finalStatus = Get-LastPrefixedValue -Lines $lines -Prefix 'runtime_final_status=' -Default 'unknown'
  $context = Get-LastProcessSummaryField -Lines $lines -Field 'context' -Default 'unknown'
  $enforcement = Get-LastProcessSummaryField -Lines $lines -Field 'enforcement' -Default 'unknown'
  $obs = Get-LastProcessSummaryField -Lines $lines -Field 'obs' -Default 'unknown'
  $reasonCode = Get-LastPrefixedValue -Lines $lines -Prefix 'runtime_trust_guard_reason_code=' -Default 'NONE'

  Write-TimingBoundary -Name 'runtime_init_guard_start_timestamp' -TimestampUtc $runtimeInitGuardStartUtc -Source $(if ($runtimeInitGuardStartUtc -eq 'unavailable') { 'missing_boundary' } else { 'derived_from_runtime_elapsed' }) -Quality $(if ($runtimeInitGuardStartUtc -eq 'unavailable') { 'unavailable' } else { 'derived' })
  Write-TimingBoundary -Name 'runtime_init_guard_end_timestamp' -TimestampUtc $runtimeInitGuardEndUtc -Source $(if ($runtimeInitGuardEndUtc -eq 'unavailable') { 'missing_boundary' } else { 'derived_from_runtime_elapsed' }) -Quality $(if ($runtimeInitGuardEndUtc -eq 'unavailable') { 'unavailable' } else { 'derived' })
  Write-TimingBoundary -Name 'first_frame_present_timestamp' -TimestampUtc $firstFramePresentUtc -Source $(if ($firstFramePresentUtc -eq 'unavailable') { 'missing_boundary' } else { 'observed_runtime_line' }) -Quality $(if ($firstFramePresentUtc -eq 'unavailable') { 'unavailable' } else { 'observed' })
  Write-TimingBoundary -Name 'autoclose_trigger_timestamp' -TimestampUtc $autocloseTriggerUtc -Source $(if ($autocloseTriggerUtc -eq 'unavailable') { 'missing_boundary' } else { 'observed_runtime_line' }) -Quality $(if ($autocloseTriggerUtc -eq 'unavailable') { 'unavailable' } else { 'observed' })
  Write-TimingBoundary -Name 'termination_guard_start_timestamp' -TimestampUtc $terminationGuardStartUtc -Source $(if ($terminationGuardStartUtc -eq 'unavailable') { 'missing_boundary' } else { 'derived_from_runtime_elapsed' }) -Quality $(if ($terminationGuardStartUtc -eq 'unavailable') { 'unavailable' } else { 'derived' })
  Write-TimingBoundary -Name 'termination_guard_end_timestamp' -TimestampUtc $terminationGuardEndUtc -Source $(if ($terminationGuardEndUtc -eq 'unavailable') { 'missing_boundary' } else { 'derived_from_runtime_elapsed' }) -Quality $(if ($terminationGuardEndUtc -eq 'unavailable') { 'unavailable' } else { 'derived' })

  $launcherFinalSummaryEmitUtc = Convert-ToIsoUtc -Value (Get-Date).ToUniversalTime()
  Write-TimingBoundary -Name 'launcher_final_summary_emit_timestamp' -TimestampUtc $launcherFinalSummaryEmitUtc -Source 'launcher' -Quality 'exact'

  Write-Output ('LAUNCH_FINAL_SUMMARY target=widget_sandbox final_status=' + $finalStatus + ' context=' + $context + ' enforcement=' + $enforcement + ' obs=' + $obs + ' blocked_reason=' + $reasonCode + ' exit_code=' + $launchExitCode)
  exit $launchExitCode
}
catch {
  $msg = $_.Exception.Message
  $blocked = $msg -like 'runtime_trust_guard_failed*'
  $finalStatus = if ($blocked) { 'BLOCKED' } else { 'EXCEPTION_EXIT' }
  $enforcement = if ($blocked) { 'FAIL' } else { 'unknown' }
  $reasonCode = if ($blocked) { 'TRUST_CHAIN_BLOCKED' } else { 'LAUNCHER_EXCEPTION' }
  $launchExitCode = if ($blocked) { 120 } else { 1 }
  Write-TimingBoundary -Name 'launcher_invocation_start_timestamp' -TimestampUtc $launcherInvocationStartUtc -Source 'launcher' -Quality 'exact'
  Write-TimingBoundary -Name 'widget_process_spawn_timestamp' -TimestampUtc $widgetProcessSpawnUtc -Source $(if ($widgetProcessSpawnUtc -eq 'unavailable') { 'missing_boundary' } else { 'launcher' }) -Quality $(if ($widgetProcessSpawnUtc -eq 'unavailable') { 'unavailable' } else { 'exact' })
  Write-TimingBoundary -Name 'runtime_init_guard_start_timestamp' -TimestampUtc $runtimeInitGuardStartUtc -Source 'missing_boundary' -Quality 'unavailable'
  Write-TimingBoundary -Name 'runtime_init_guard_end_timestamp' -TimestampUtc $runtimeInitGuardEndUtc -Source 'missing_boundary' -Quality 'unavailable'
  Write-TimingBoundary -Name 'first_frame_present_timestamp' -TimestampUtc $firstFramePresentUtc -Source 'missing_boundary' -Quality 'unavailable'
  Write-TimingBoundary -Name 'autoclose_trigger_timestamp' -TimestampUtc $autocloseTriggerUtc -Source 'missing_boundary' -Quality 'unavailable'
  Write-TimingBoundary -Name 'termination_guard_start_timestamp' -TimestampUtc $terminationGuardStartUtc -Source 'missing_boundary' -Quality 'unavailable'
  Write-TimingBoundary -Name 'termination_guard_end_timestamp' -TimestampUtc $terminationGuardEndUtc -Source 'missing_boundary' -Quality 'unavailable'
  $launcherFinalSummaryEmitUtc = Convert-ToIsoUtc -Value (Get-Date).ToUniversalTime()
  Write-TimingBoundary -Name 'launcher_final_summary_emit_timestamp' -TimestampUtc $launcherFinalSummaryEmitUtc -Source 'launcher' -Quality 'exact'
  Write-Output ('LAUNCH_ERROR=' + $msg)
  Write-Output ('LAUNCH_FINAL_SUMMARY target=widget_sandbox final_status=' + $finalStatus + ' context=runtime_init enforcement=' + $enforcement + ' obs=unknown blocked_reason=' + $reasonCode + ' exit_code=' + $launchExitCode)
  exit $launchExitCode
}
finally {
  foreach ($key in $modeEnvRestore.Keys) {
    [Environment]::SetEnvironmentVariable($key, $modeEnvRestore[$key], 'Process')
  }
}
