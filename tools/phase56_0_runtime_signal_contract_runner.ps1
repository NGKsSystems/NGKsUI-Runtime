Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime"

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path '_proof' ("phase56_0_runtime_signal_contract_" + $ts)
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
if (-not (Test-Path -LiteralPath $py)) {
  throw 'Python entrypoint missing at .venv\\Scripts\\python.exe'
}

# Build/emit explicit target set for deterministic baseline.
$targets = @('widget_sandbox', 'win32_sandbox', 'sandbox_app', 'loop_tests')
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

$rows = @()

# Observability OFF/ON contract on sandbox_app (short lifecycle, deterministic exit).
$sandboxExe = Join-Path (Get-Location) 'build/debug/bin/sandbox_app.exe'
$off = Invoke-Run -ExePath $sandboxExe -Args @() -Env @{ NGKS_RUNTIME_OBS = $null; NGKS_BYPASS_GUARD = $null } -StdoutFile (Join-Path $pf '20_sandbox_obs_off_stdout.txt') -StderrFile (Join-Path $pf '20_sandbox_obs_off_stderr.txt') -TimeoutSec 20
$on  = Invoke-Run -ExePath $sandboxExe -Args @() -Env @{ NGKS_RUNTIME_OBS = '1'; NGKS_BYPASS_GUARD = $null } -StdoutFile (Join-Path $pf '21_sandbox_obs_on_stdout.txt')  -StderrFile (Join-Path $pf '21_sandbox_obs_on_stderr.txt')  -TimeoutSec 20

$offObserveCount = @((($off.stdout -split "`r?`n") | Where-Object { $_ -match '^runtime_observe ' })).Count
$onObserveCount = @((($on.stdout -split "`r?`n") | Where-Object { $_ -match '^runtime_observe ' })).Count

# Fail-closed contract check on all targets.
foreach ($t in $targets) {
  $exe = Join-Path (Get-Location) ("build/debug/bin/" + $t + '.exe')
  $clean = Invoke-Run -ExePath $exe -Args @('--auto-close-ms=1500') -Env @{ NGKS_BYPASS_GUARD = $null; NGKS_RUNTIME_OBS='1'; NGK_FORENSICS_LOG='1' } -StdoutFile (Join-Path $pf ("30_" + $t + '_clean_stdout.txt')) -StderrFile (Join-Path $pf ("30_" + $t + '_clean_stderr.txt')) -TimeoutSec 25
  $invalid = Invoke-Run -ExePath $exe -Args @('--auto-close-ms=1500') -Env @{ NGKS_BYPASS_GUARD = '1'; NGKS_RUNTIME_OBS='1' } -StdoutFile (Join-Path $pf ("31_" + $t + '_invalid_stdout.txt')) -StderrFile (Join-Path $pf ("31_" + $t + '_invalid_stderr.txt')) -TimeoutSec 15

  $cleanGuard = if($clean.stdout -match 'runtime_trust_guard=PASS context=runtime_init'){'YES'}else{'NO'}
  $invalidBlocked = if(($invalid.exit_code -ne 0) -or ($invalid.stdout -match 'runtime_trust_guard=FAIL|runtime_trust_blocked|GATE=FAIL')){'YES'}else{'NO'}

  $rows += [pscustomobject]@{
    target = $t
    clean_guard_pass = $cleanGuard
    invalid_fail_closed = $invalidBlocked
    clean_exit = $clean.exit_code
    invalid_exit = $invalid.exit_code
  }
}

$matrix = Join-Path $pf '40_phase56_0_signal_contract_matrix.csv'
$rows | ConvertTo-Csv -NoTypeInformation | Set-Content -LiteralPath $matrix -Encoding UTF8

# Missing observability points (from source presence, not old investigations).
$missing = @()
$guardSrc = Get-Content -LiteralPath 'apps/runtime_phase53_guard.hpp' -Raw
$widgetSrc = Get-Content -LiteralPath 'apps/widget_sandbox/main.cpp' -Raw
if ($guardSrc -notmatch 'runtime_observe_event\("enforce_begin"') { $missing += 'runtime_init' }
if ($widgetSrc -notmatch 'require_runtime_trust\("file_load"\)') { $missing += 'file_load' }
if ($widgetSrc -notmatch 'require_runtime_trust\("save_export"\)') { $missing += 'recheck_trigger' }

$newReg = 'NO'
if (($offObserveCount -ne 0) -or ($onObserveCount -le 0)) { $newReg = 'YES' }
if ((@($rows | Where-Object { $_.clean_guard_pass -ne 'YES' -or $_.invalid_fail_closed -ne 'YES' }).Count) -gt 0) { $newReg = 'YES' }

$scope = 'phase56_runtime_signal_contract_baseline'
$objective = 'Establish deterministic runtime signal contract checks (obs OFF/ON + fail-closed guard regression) as post-Phase-55 baseline.'
$changes = 'tools/phase56_0_runtime_signal_contract_runner.ps1 (auditable baseline runner + contract matrix + proof packaging)'

# PASS requires both regression-free signals and complete proof artifacts.
$requiredFiles = @(
  '40_phase56_0_signal_contract_matrix.csv',
  '20_sandbox_obs_off_stdout.txt',
  '20_sandbox_obs_off_stderr.txt',
  '21_sandbox_obs_on_stdout.txt',
  '21_sandbox_obs_on_stderr.txt'
)
foreach ($t in $targets) {
  $requiredFiles += @(
    ('10_plan_' + $t + '.txt'),
    ('11_buildcore_' + $t + '.txt'),
    ('30_' + $t + '_clean_stdout.txt'),
    ('30_' + $t + '_clean_stderr.txt'),
    ('31_' + $t + '_invalid_stdout.txt'),
    ('31_' + $t + '_invalid_stderr.txt')
  )
}

$missingArtifacts = @()
foreach ($f in $requiredFiles) {
  $p = Join-Path $pf $f
  if (-not (Test-Path -LiteralPath $p)) {
    $missingArtifacts += $f
  }
}

$matrixRows = @()
if (Test-Path -LiteralPath $matrix) {
  try {
    $matrixRows = Import-Csv -LiteralPath $matrix
  }
  catch {
    $matrixRows = @()
  }
}

$matrixTargets = @($matrixRows | ForEach-Object { $_.target })
$matrixComplete = ($matrixRows.Count -eq $targets.Count)
foreach ($t in $targets) {
  if (-not ($matrixTargets -contains $t)) {
    $matrixComplete = $false
    break
  }
}

$artifactsComplete = ($missingArtifacts.Count -eq 0) -and $matrixComplete

if ($newReg -eq 'NO' -and $artifactsComplete) {
  $status = 'PASS'
}
elseif ($newReg -eq 'NO') {
  $status = 'IN_PROGRESS'
}
else {
  $status = 'PARTIAL'
}

$summary = @(
  'next_phase_selected=PHASE56_RUNTIME_SIGNAL_CONTRACT_BASELINE',
  'objective=' + $objective,
  'changes_introduced=' + $changes,
  'runtime_behavior_changes=NONE',
  'new_regressions_detected=' + $newReg,
  'phase_status=' + $status,
  'proof_folder=' + $pf
)
Write-Txt '99_phase56_contract_summary.txt' $summary | Out-Null
Write-Txt '99_contract_summary.txt' $summary | Out-Null

if ($missingArtifacts.Count -gt 0 -or -not $matrixComplete) {
  $diag = @(
    'artifacts_complete=' + $(if ($artifactsComplete) { 'YES' } else { 'NO' }),
    'matrix_complete=' + $(if ($matrixComplete) { 'YES' } else { 'NO' }),
    'missing_artifact_count=' + $missingArtifacts.Count,
    'missing_artifacts=' + $(if ($missingArtifacts.Count -gt 0) { ($missingArtifacts -join ',') } else { 'none' })
  )
  Write-Txt '98_phase56_contract_completeness.txt' $diag | Out-Null
}

$zip = "$pf.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

$summary -join "`n"
