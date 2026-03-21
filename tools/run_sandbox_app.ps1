param(
  [ValidateSet('Debug', 'Release')]
  [string]$Config = 'Debug',
  [string[]]$PassArgs = @(),
  [string]$ExePath = '',
  [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-MandatoryRuntimeGuard {
  param(
    [string]$RepoRoot
  )

  $runner = Join-Path $RepoRoot 'tools\TrustChainRuntime.ps1'
  if (-not (Test-Path -LiteralPath $runner)) {
    throw ('runtime_trust_guard_missing_runner: ' + $runner)
  }

  Push-Location $RepoRoot
  try {
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Context runtime_init 2>&1
    if ($LASTEXITCODE -ne 0) {
      $snippet = ($out | Select-Object -First 8) -join '; '
      throw ('runtime_trust_guard_failed exit=' + $LASTEXITCODE + ' detail=' + $snippet)
    }
  }
  finally {
    Pop-Location
  }
}

function Get-CanonicalSandboxAppExePath {
  param(
    [string]$RepoRoot,
    [ValidateSet('Debug', 'Release')]
    [string]$Config
  )

  $cfgLower = $Config.ToLowerInvariant()
  return (Join-Path $RepoRoot ("build\$cfgLower\bin\sandbox_app.exe"))
}

function Resolve-CanonicalSandboxAppExe {
  param(
    [string]$RepoRoot,
    [ValidateSet('Debug', 'Release')]
    [string]$Config,
    [string]$RequestedExePath
  )

  $canonical = Get-CanonicalSandboxAppExePath -RepoRoot $RepoRoot -Config $Config
  if (-not (Test-Path -LiteralPath $canonical)) {
    throw ('unsafe_launch: canonical exe missing: ' + $canonical)
  }

  $canonicalResolved = (Resolve-Path -LiteralPath $canonical).Path
  if (-not [string]::IsNullOrWhiteSpace($RequestedExePath)) {
    if (-not (Test-Path -LiteralPath $RequestedExePath)) {
      throw ('unsafe_launch: requested exe not found: ' + $RequestedExePath)
    }
    $requestedResolved = (Resolve-Path -LiteralPath $RequestedExePath).Path
    if (-not $requestedResolved.Equals($canonicalResolved, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw ('unsafe_launch: requested exe is not canonical: ' + $requestedResolved)
    }
  }

  return $canonicalResolved
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

try {
  if ([string]::IsNullOrWhiteSpace($repoRoot)) {
    throw 'unsafe_launch: launcher root resolution failed'
  }
  if (-not (Test-Path -LiteralPath (Join-Path $repoRoot '.git')) -or
      -not (Test-Path -LiteralPath (Join-Path $repoRoot 'apps/sandbox_app/main.cpp'))) {
    throw ('unsafe_launch: launcher is not under NGKsUI Runtime repo root: ' + $repoRoot)
  }
  $cwd = (Resolve-Path '.').Path
  if (-not $cwd.Equals($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw ('unsafe_launch: repo root mismatch, expected cwd=' + $repoRoot + ', actual cwd=' + $cwd)
  }

  Invoke-MandatoryRuntimeGuard -RepoRoot $repoRoot

  $exe = Resolve-CanonicalSandboxAppExe -RepoRoot $repoRoot -Config $Config -RequestedExePath $ExePath

  Write-Output ('LAUNCH_TARGET=sandbox_app')
  Write-Output ('LAUNCH_CONFIG=' + $Config)
  Write-Output ('LAUNCH_EXE=' + $exe)
  Write-Output ('LAUNCH_ARGS=' + ($(if ($PassArgs.Count -gt 0) { $PassArgs -join ' ' } else { '(none)' })))

  if ($NoLaunch) {
    exit 0
  }

  $captured = New-Object System.Collections.Generic.List[string]
  & $exe @PassArgs 2>&1 | ForEach-Object {
    $line = [string]$_
    $captured.Add($line)
    $line
  }
  $launchExitCode = $LASTEXITCODE

  $lines = $captured.ToArray()
  $finalStatus = Get-LastPrefixedValue -Lines $lines -Prefix 'runtime_final_status=' -Default 'unknown'
  $context = Get-LastProcessSummaryField -Lines $lines -Field 'context' -Default 'unknown'
  $enforcement = Get-LastProcessSummaryField -Lines $lines -Field 'enforcement' -Default 'unknown'
  $obs = Get-LastProcessSummaryField -Lines $lines -Field 'obs' -Default 'unknown'
  $reasonCode = Get-LastPrefixedValue -Lines $lines -Prefix 'runtime_trust_guard_reason_code=' -Default 'NONE'

  Write-Output ('LAUNCH_FINAL_SUMMARY target=sandbox_app final_status=' + $finalStatus + ' context=' + $context + ' enforcement=' + $enforcement + ' obs=' + $obs + ' blocked_reason=' + $reasonCode + ' exit_code=' + $launchExitCode)
  exit $launchExitCode
}
catch {
  $msg = $_.Exception.Message
  $blocked = $msg -like 'runtime_trust_guard_failed*'
  $finalStatus = if ($blocked) { 'BLOCKED' } else { 'EXCEPTION_EXIT' }
  $enforcement = if ($blocked) { 'FAIL' } else { 'unknown' }
  $reasonCode = if ($blocked) { 'TRUST_CHAIN_BLOCKED' } else { 'LAUNCHER_EXCEPTION' }
  $launchExitCode = if ($blocked) { 120 } else { 1 }
  Write-Output ('LAUNCH_ERROR=' + $msg)
  Write-Output ('LAUNCH_FINAL_SUMMARY target=sandbox_app final_status=' + $finalStatus + ' context=runtime_init enforcement=' + $enforcement + ' obs=unknown blocked_reason=' + $reasonCode + ' exit_code=' + $launchExitCode)
  exit $launchExitCode
}