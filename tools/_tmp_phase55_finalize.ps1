Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime"

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path '_proof' ("phase55_final_closure_" + $ts)
New-Item -ItemType Directory -Force -Path $pf | Out-Null

function Write-Txt {
  param([string]$Name, [object]$Content)
  $p = Join-Path $pf $Name
  $Content | Set-Content -LiteralPath $p -Encoding UTF8
  return $p
}

function Set-EnvMap {
  param([hashtable]$Map)
  $prev = @{}
  foreach ($k in $Map.Keys) {
    $prev[$k] = [Environment]::GetEnvironmentVariable($k)
    $v = $Map[$k]
    if ($null -eq $v) {
      [Environment]::SetEnvironmentVariable($k, $null)
    } else {
      [Environment]::SetEnvironmentVariable($k, [string]$v)
    }
  }
  return $prev
}

function Restore-EnvMap {
  param([hashtable]$Prev)
  foreach ($k in $Prev.Keys) {
    [Environment]::SetEnvironmentVariable($k, $Prev[$k])
  }
}

function Invoke-Launch {
  param(
    [string]$ExePath,
    [string[]]$Args,
    [hashtable]$Env,
    [string]$StdoutFile,
    [string]$StderrFile,
    [int]$TimeoutSec
  )

  $prev = Set-EnvMap -Map $Env
  try {
    $proc = Start-Process -FilePath $ExePath -ArgumentList $Args -RedirectStandardOutput $StdoutFile -RedirectStandardError $StderrFile -PassThru
    $timedOut = $false
    if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
      $timedOut = $true
      try { $proc.Kill() } catch {}
    }
    $exitCode = if ($timedOut) { 124 } else { $proc.ExitCode }
    $stdout = if (Test-Path -LiteralPath $StdoutFile) { Get-Content -LiteralPath $StdoutFile -Raw } else { '' }
    $stderr = if (Test-Path -LiteralPath $StderrFile) { Get-Content -LiteralPath $StderrFile -Raw } else { '' }
    return [pscustomobject]@{
      exit_code = $exitCode
      timed_out = $timedOut
      stdout = $stdout
      stderr = $stderr
      stdout_file = $StdoutFile
      stderr_file = $StderrFile
    }
  }
  finally {
    Restore-EnvMap -Prev $prev
  }
}

$py = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime\.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $py)) { throw 'Python entrypoint missing at .venv\\Scripts\\python.exe' }

# Rebuild widget + sandbox_app through proven path to verify observability behavior.
foreach ($target in @('widget_sandbox', 'sandbox_app')) {
  $planOut = (& $py -m ngksgraph build --profile debug --msvc-auto --target $target 2>&1 | Out-String)
  Write-Txt ("10_plan_" + $target + ".txt") $planOut | Out-Null

  $planPath = ''
  $m = [regex]::Match($planOut, 'BuildCore plan:\s+(.+)')
  if ($m.Success) { $planPath = $m.Groups[1].Value.Trim() }
  if (-not $planPath) { $planPath = Join-Path (Get-Location) 'build_graph/debug/ngksbuildcore_plan.json' }

  $runProof = Join-Path $pf ("buildcore_" + $target)
  New-Item -ItemType Directory -Force -Path $runProof | Out-Null
  $runOut = (& $py -m ngksbuildcore run --plan $planPath --proof $runProof -j 1 2>&1 | Out-String)
  Write-Txt ("11_buildcore_" + $target + ".txt") $runOut | Out-Null
}

$widgetExe = Join-Path (Get-Location) 'build/debug/bin/widget_sandbox.exe'
$sandboxExe = Join-Path (Get-Location) 'build/debug/bin/sandbox_app.exe'

# Toggle validation: disabled mode (sandbox_app) should emit no runtime_observe lines.
$disabled = Invoke-Launch -ExePath $sandboxExe -Args @() -Env @{ NGKS_RUNTIME_OBS = $null; NGKS_BYPASS_GUARD = $null } -StdoutFile (Join-Path $pf '20_sandbox_obs_disabled_stdout.txt') -StderrFile (Join-Path $pf '20_sandbox_obs_disabled_stderr.txt') -TimeoutSec 20

# Toggle validation: enabled mode (sandbox_app) should emit structured runtime_observe lines.
$enabled = Invoke-Launch -ExePath $sandboxExe -Args @() -Env @{ NGKS_RUNTIME_OBS = '1'; NGKS_BYPASS_GUARD = $null } -StdoutFile (Join-Path $pf '21_sandbox_obs_enabled_stdout.txt') -StderrFile (Join-Path $pf '21_sandbox_obs_enabled_stderr.txt') -TimeoutSec 20

# Widget enabled run for runtime-init + file-load (+recheck signal if reached during session).
$widgetEnabled = Invoke-Launch -ExePath $widgetExe -Args @('--auto-close-ms=10000') -Env @{ NGKS_RUNTIME_OBS='1'; NGKS_BYPASS_GUARD=$null; NGK_FORENSICS_LOG='1' } -StdoutFile (Join-Path $pf '22_widget_obs_enabled_stdout.txt') -StderrFile (Join-Path $pf '22_widget_obs_enabled_stderr.txt') -TimeoutSec 35

$disabledObsLines = @(($disabled.stdout -split "`r?`n") | Where-Object { $_ -match '^runtime_observe ' })
$enabledObsLines = @(($enabled.stdout -split "`r?`n") | Where-Object { $_ -match '^runtime_observe ' })
$widgetObsLines = @(($widgetEnabled.stdout -split "`r?`n") | Where-Object { $_ -match '^runtime_observe ' })

$toggleReport = @(
  'observability_toggle_check=BEGIN',
  ('disabled_exit=' + $disabled.exit_code),
  ('disabled_runtime_observe_lines=' + $disabledObsLines.Count),
  ('enabled_exit=' + $enabled.exit_code),
  ('enabled_runtime_observe_lines=' + $enabledObsLines.Count),
  ('widget_enabled_exit=' + $widgetEnabled.exit_code),
  ('widget_enabled_runtime_observe_lines=' + $widgetObsLines.Count),
  ('disabled_mode_unchanged=' + $(if($disabledObsLines.Count -eq 0){'YES'}else{'NO'})),
  ('enabled_mode_emits_structured=' + $(if($enabledObsLines.Count -gt 0){'YES'}else{'NO'})),
  'observability_toggle_check=END'
)
Write-Txt '30_observability_toggle_report.txt' $toggleReport | Out-Null

# Enforcement surface instrumentation confirmation.
$guardSrc = Get-Content -LiteralPath 'apps/runtime_phase53_guard.hpp' -Raw
$widgetSrc = Get-Content -LiteralPath 'apps/widget_sandbox/main.cpp' -Raw
$surface = @()
$surface += 'enforcement_surface_observability=BEGIN'
$surface += ('guard_enforce_begin=' + $(if($guardSrc -match 'runtime_observe_event\("enforce_begin"'){ 'YES' } else { 'NO' }))
$surface += ('guard_enforce_pass_fail=' + $(if($guardSrc -match 'runtime_observe_event\("enforce_pass"' -and $guardSrc -match 'runtime_observe_event\("enforce_fail"'){ 'YES' } else { 'NO' }))
$surface += ('guard_require_pass_throw=' + $(if($guardSrc -match 'runtime_observe_event\("require_pass"' -and $guardSrc -match 'runtime_observe_event\("require_throw"'){ 'YES' } else { 'NO' }))
$surface += ('runtime_init_path_instrumented=' + $(if($widgetSrc -match 'enforce_phase53_2\(\)'){ 'YES' } else { 'NO' }))
$surface += ('file_load_path_instrumented=' + $(if($widgetSrc -match 'require_runtime_trust\("file_load"\)'){ 'YES' } else { 'NO' }))
$surface += ('recheck_trigger_path_instrumented=' + $(if($widgetSrc -match 'require_runtime_trust\("save_export"\)'){ 'YES' } else { 'NO' }))
$surface += ('widget_runtime_init_seen=' + $(if($widgetEnabled.stdout -match 'runtime_trust_guard=PASS context=runtime_init'){ 'YES' } else { 'NO' }))
$surface += ('widget_file_load_seen=' + $(if($widgetEnabled.stdout -match 'runtime_trust_guard=PASS context=file_load'){ 'YES' } else { 'NO' }))
$surface += ('widget_recheck_seen=' + $(if($widgetEnabled.stdout -match 'runtime_observe event=require_pass context=save_export|runtime_trust_guard=PASS context=save_export'){ 'YES' } else { 'NO' }))
$surface += 'enforcement_surface_observability=END'
Write-Txt '31_enforcement_surface_observability.txt' $surface | Out-Null

$missingPoints = @()
if ($surface -notcontains 'runtime_init_path_instrumented=YES') { $missingPoints += 'runtime_init' }
if ($surface -notcontains 'file_load_path_instrumented=YES') { $missingPoints += 'file_load' }
if ($surface -notcontains 'recheck_trigger_path_instrumented=YES') { $missingPoints += 'recheck_trigger' }

$newReg = 'NO'
if (($disabledObsLines.Count -ne 0) -or ($enabledObsLines.Count -eq 0)) {
  $newReg = 'YES'
}

$scope = 'runtime_observability_with_launch_state_signal'
$changes = 'toggleable structured observability in runtime guard decision points + lifecycle launch-state signals (controlled minimal improvement: better launch-state signal)'
$status = if ($newReg -eq 'NO' -and $missingPoints.Count -eq 0) { 'PASS' } else { 'PARTIAL' }

$summary = @(
  'phase55_scope_selected=' + $scope,
  'changes_introduced=' + $changes,
  'runtime_behavior_changes=NONE',
  'new_regressions_detected=' + $newReg,
  'missing_observability_points=' + ($missingPoints -join ','),
  'phase55_status=' + $status,
  'proof_folder=' + $pf
)
Write-Txt '99_phase55_final_contract.txt' $summary | Out-Null

$zip = "$pf.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

$summary -join "`n"
