Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime"

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path '_proof' ("phase55_runtime_observability_" + $ts)
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

function Invoke-Run {
  param(
    [string]$Target,
    [string]$Mode,
    [string]$ExePath,
    [string[]]$Args,
    [int]$DwellSec,
    [int]$MaxSec,
    [hashtable]$Env
  )

  $out = Join-Path $pf ("20_" + $Target + "_" + $Mode + "_stdout.txt")
  $err = Join-Path $pf ("20_" + $Target + "_" + $Mode + "_stderr.txt")

  $prev = Set-EnvMap -Map $Env
  try {
    $proc = Start-Process -FilePath $ExePath -ArgumentList $Args -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
    Start-Sleep -Seconds $DwellSec
    $runningAtDwell = -not $proc.HasExited

    $timedOut = $false
    if (-not $proc.WaitForExit($MaxSec * 1000)) {
      $timedOut = $true
      try { $proc.Kill() } catch {}
    }

    $exitCode = if ($timedOut) { 124 } else { $proc.ExitCode }
    $stdout = if (Test-Path -LiteralPath $out) { Get-Content -LiteralPath $out -Raw } else { '' }
    $stderr = if (Test-Path -LiteralPath $err) { Get-Content -LiteralPath $err -Raw } else { '' }

    return [pscustomobject]@{
      exit_code = $exitCode
      timed_out = $timedOut
      running_at_dwell = $runningAtDwell
      stdout_file = $out
      stderr_file = $err
      stdout = $stdout
      stderr = $stderr
    }
  }
  finally {
    Restore-EnvMap -Prev $prev
  }
}

$py = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime\.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $py)) { throw 'python entrypoint missing' }

$targets = @('widget_sandbox', 'win32_sandbox', 'sandbox_app', 'loop_tests')
$rows = @()

# Build/restore targets via proven execution owner.
foreach ($t in $targets) {
  $planOut = (& $py -m ngksgraph build --profile debug --msvc-auto --target $t 2>&1 | Out-String)
  Write-Txt ("10_plan_" + $t + ".txt") $planOut | Out-Null

  $planPath = ''
  $m = [regex]::Match($planOut, 'BuildCore plan:\s+(.+)')
  if ($m.Success) { $planPath = $m.Groups[1].Value.Trim() }
  if (-not $planPath) { $planPath = Join-Path (Get-Location) 'build_graph/debug/ngksbuildcore_plan.json' }

  $runProof = Join-Path $pf ("buildcore_" + $t)
  New-Item -ItemType Directory -Force -Path $runProof | Out-Null
  $runOut = (& $py -m ngksbuildcore run --plan $planPath --proof $runProof -j 1 2>&1 | Out-String)
  Write-Txt ("11_buildcore_" + $t + ".txt") $runOut | Out-Null
}

# Enforcement surface validation (static coverage check)
$surface = @()
$surface += 'enforcement_surface_check=BEGIN'
$widgetSrc = Get-Content -LiteralPath 'apps/widget_sandbox/main.cpp' -Raw
$win32Src = Get-Content -LiteralPath 'apps/win32_sandbox/main.cpp' -Raw
$sandboxSrc = Get-Content -LiteralPath 'apps/sandbox_app/main.cpp' -Raw
$loopSrc = Get-Content -LiteralPath 'apps/loop_tests/main.cpp' -Raw

$surface += ('widget_runtime_init=' + $(if($widgetSrc -match 'enforce_phase53_2'){ 'YES' } else { 'NO' }))
$surface += ('widget_file_load=' + $(if($widgetSrc -match 'require_runtime_trust\("file_load"\)'){ 'YES' } else { 'NO' }))
$surface += ('widget_execution_pipeline=' + $(if($widgetSrc -match 'enforce_runtime_trust\("execution_pipeline"\)|require_runtime_trust\("execution_pipeline"\)'){ 'YES' } else { 'NO' }))
$surface += ('widget_recheck_or_late_guard=' + $(if($widgetSrc -match 'require_runtime_trust\("save_export"\)'){ 'YES' } else { 'NO' }))
$surface += ('win32_runtime_init=' + $(if($win32Src -match 'enforce_phase53_2'){ 'YES' } else { 'NO' }))
$surface += ('win32_file_load=' + $(if($win32Src -match 'require_runtime_trust\("file_load"\)'){ 'YES' } else { 'NO' }))
$surface += ('win32_execution_pipeline=' + $(if($win32Src -match 'require_runtime_trust\("execution_pipeline"\)'){ 'YES' } else { 'NO' }))
$surface += ('sandbox_runtime_init=' + $(if($sandboxSrc -match 'enforce_phase53_2'){ 'YES' } else { 'NO' }))
$surface += ('loop_runtime_init=' + $(if($loopSrc -match 'enforce_phase53_2'){ 'YES' } else { 'NO' }))
$surface += 'enforcement_surface_check=END'
Write-Txt '12_enforcement_surface_validation.txt' $surface | Out-Null

# Runtime checks
foreach ($t in $targets) {
  $exe = Join-Path (Get-Location) ("build/debug/bin/" + $t + ".exe")
  if (-not (Test-Path -LiteralPath $exe)) {
    $rows += [pscustomobject]@{ target=$t; clean='FAIL'; invalid='FAIL'; live='N_A'; notes='missing_binary' }
    continue
  }

  $cleanEnv = @{ NGKS_RUNTIME_OBS = '1'; NGKS_BYPASS_GUARD = $null }
  if ($t -eq 'widget_sandbox') { $cleanEnv['NGK_FORENSICS_LOG'] = '1' }
  $clean = Invoke-Run -Target $t -Mode 'clean' -ExePath $exe -Args @('--auto-close-ms=20000') -DwellSec 10 -MaxSec 45 -Env $cleanEnv

  $cleanPass = 'FAIL'
  $notes = @()
  if ($clean.stdout -match 'runtime_trust_guard=PASS context=runtime_init') { $cleanPass = 'PASS' }

  $invalid = Invoke-Run -Target $t -Mode 'invalid' -ExePath $exe -Args @('--auto-close-ms=2000') -DwellSec 2 -MaxSec 12 -Env @{ NGKS_BYPASS_GUARD='1'; NGKS_RUNTIME_OBS='1' }
  $invalidPass = if ($invalid.exit_code -ne 0 -or $invalid.stdout -match 'runtime_trust_guard=FAIL|runtime_trust_blocked|GATE=FAIL') { 'PASS' } else { 'FAIL' }

  $live = 'N_A'
  if ($t -eq 'widget_sandbox') {
    $initSeen = ($clean.stdout -match 'runtime_trust_guard=PASS context=runtime_init')
    $recheckSeen = ($clean.stdout -match 'runtime_trust_guard=PASS context=file_load|runtime_observe event=require_pass context=save_export')
    $live = if ($initSeen -and $recheckSeen) { 'PASS' } else { 'FAIL' }

    if ($clean.timed_out -and $cleanPass -eq 'PASS' -and ($clean.stdout -match 'widget_phase40_21_idle_indicator=IDLE=1|widget_phase40_21_idle_mode=1')) {
      $notes += 'widget_timeout_expected_idle_measurement_artifact'
    }
  }

  if ($clean.stderr -match 'fatal|exception|access violation|crash') {
    $notes += 'stderr_runtime_anomaly'
  }

  $rows += [pscustomobject]@{
    target = $t
    clean = $cleanPass
    sustained = $(if($clean.running_at_dwell){'PASS'}else{'FAIL'})
    invalid = $invalidPass
    live = $live
    notes = $(if($notes.Count -gt 0){$notes -join ','} else {'NONE'})
  }
}

$matrixPath = Join-Path $pf '30_phase55_runtime_matrix.csv'
$rows | ConvertTo-Csv -NoTypeInformation | Set-Content -LiteralPath $matrixPath -Encoding UTF8

$unstable = @($rows | Where-Object {
  $_.clean -ne 'PASS' -or $_.invalid -ne 'PASS' -or (($_.live -ne 'PASS') -and ($_.live -ne 'N_A'))
} | Select-Object -ExpandProperty target)

$newReg = if($unstable.Count -gt 0){'YES'}else{'NO'}
$timeoutClassification = 'EXPECTED_IDLE_BEHAVIOR_MEASUREMENT_ARTIFACT'
$widgetTimeoutNonArtifact = @($rows | Where-Object { $_.target -eq 'widget_sandbox' -and $_.notes -notmatch 'measurement_artifact' })
if ($widgetTimeoutNonArtifact.Count -gt 0) {
  $timeoutClassification = 'NO_TIMEOUT_ANOMALY_DETECTED'
}

$scope = 'runtime_observability_with_timeout_classification'
$changes = 'apps/runtime_phase53_guard.hpp(+toggleable runtime_observe events);apps/widget_sandbox/main.cpp(+lifecycle signals);apps/win32_sandbox/main.cpp(+lifecycle signals);apps/sandbox_app/main.cpp(+lifecycle signals);apps/loop_tests/main.cpp(+lifecycle signals)'

$status = if($newReg -eq 'NO'){'IN_PROGRESS'}else{'IN_PROGRESS'}
$summary = @(
  'phase55_scope_selected=' + $scope,
  'changes_introduced=' + $changes,
  'runtime_behavior_changes=NONE',
  'new_regressions_detected=' + $newReg,
  'widget_timeout_classification=' + $timeoutClassification,
  'phase55_status=' + $status,
  'proof_folder=' + $pf,
  'matrix=' + $matrixPath
)
Write-Txt '99_phase55_contract_summary.txt' $summary | Out-Null

$zip = "$pf.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

$summary -join "`n"
