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

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($repoRoot)) {
  throw 'unsafe_launch: launcher root resolution failed'
}
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot 'CMakeLists.txt')) -or
    -not (Test-Path -LiteralPath (Join-Path $repoRoot 'apps/widget_sandbox/main.cpp'))) {
  throw ("unsafe_launch: launcher is not under NGKsUI Runtime repo root: " + $repoRoot)
}
$cwd = (Resolve-Path '.').Path
if (-not $cwd.Equals($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw ("unsafe_launch: repo root mismatch, expected cwd=" + $repoRoot + ", actual cwd=" + $cwd)
}

$exe = Resolve-CanonicalWidgetSandboxExe -RepoRoot $repoRoot -Config $Config -RequestedExePath $ExePath
$buildInfo = Get-WidgetSandboxBuildInfo -ExePath $exe -Config $Config -RepoRoot $repoRoot

$identity = "canonical|" + $Config.ToLowerInvariant() + "|" + $buildInfo.exe_write_time_utc
$env:NGK_WIDGET_LAUNCH_IDENTITY = $identity
$env:NGK_WIDGET_CANONICAL_EXE = $exe

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

$modeEnvRestore = @{}
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

if ($NoLaunch) {
  foreach ($key in $modeEnvRestore.Keys) {
    [Environment]::SetEnvironmentVariable($key, $modeEnvRestore[$key], 'Process')
  }
  exit 0
}

$out = $null
try {
  $out = & $exe @PassArgs
  if ($null -ne $out) {
    $out
  }
  exit $LASTEXITCODE
}
finally {
  foreach ($key in $modeEnvRestore.Keys) {
    [Environment]::SetEnvironmentVariable($key, $modeEnvRestore[$key], 'Process')
  }
}
