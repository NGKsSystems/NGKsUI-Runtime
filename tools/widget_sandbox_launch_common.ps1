Set-StrictMode -Version Latest

function Invoke-Phase532MandatoryGuard {
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

function Get-NgkRuntimeRepoRoot {
  param(
    [string]$StartPath = $PSScriptRoot
  )

  $item = Get-Item -LiteralPath $StartPath
  $cursor = if ($item.PSIsContainer) { $item } else { $item.Directory }

  while ($null -ne $cursor) {
    $candidate = $cursor.FullName
    $markerA = Join-Path $candidate '.git'
    $markerB = Join-Path $candidate 'apps/widget_sandbox/main.cpp'
    if ((Test-Path -LiteralPath $markerA) -and (Test-Path -LiteralPath $markerB)) {
      return $candidate
    }

    $cursor = $cursor.Parent
  }

  throw 'unsafe_launch: unable to locate NGKsUI Runtime repository root markers'
}

function Get-CanonicalWidgetSandboxExePath {
  param(
    [string]$RepoRoot,
    [ValidateSet('Debug', 'Release')]
    [string]$Config = 'Debug'
  )

  $cfgLower = $Config.ToLowerInvariant()
  return (Join-Path $RepoRoot ("build\$cfgLower\bin\widget_sandbox.exe"))
}

function Test-IsForbiddenWidgetSandboxPath {
  param(
    [string]$Path,
    [string]$RepoRoot
  )

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return $false
  }

  $normPath = $Path.Replace('/', '\')
  $artifactPrefix = (Join-Path $RepoRoot 'artifacts\build').Replace('/', '\') + '\'
  $proofArtifactPrefix = (Join-Path $RepoRoot '_artifacts').Replace('/', '\') + '\'

  return $normPath.StartsWith($artifactPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
    $normPath.StartsWith($proofArtifactPrefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Resolve-CanonicalWidgetSandboxExe {
  param(
    [string]$RepoRoot,
    [ValidateSet('Debug', 'Release')]
    [string]$Config = 'Debug',
    [string]$RequestedExePath = ''
  )

  $canonical = Get-CanonicalWidgetSandboxExePath -RepoRoot $RepoRoot -Config $Config
  $canonicalResolved = $null
  if (Test-Path -LiteralPath $canonical) {
    $canonicalResolved = (Resolve-Path -LiteralPath $canonical).Path
  }

  if (-not [string]::IsNullOrWhiteSpace($RequestedExePath)) {
    if (Test-IsForbiddenWidgetSandboxPath -Path $RequestedExePath -RepoRoot $RepoRoot) {
      throw ("unsafe_launch: forbidden stale artifact path: " + $RequestedExePath)
    }

    if (-not (Test-Path -LiteralPath $RequestedExePath)) {
      throw ("unsafe_launch: requested exe not found: " + $RequestedExePath)
    }

    $requestedResolved = (Resolve-Path -LiteralPath $RequestedExePath).Path
    if ($null -eq $canonicalResolved) {
      throw ("unsafe_launch: canonical exe missing: " + $canonical)
    }
    if (-not $requestedResolved.Equals($canonicalResolved, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw ("unsafe_launch: requested exe is not canonical: " + $requestedResolved)
    }
  }

  if ($null -eq $canonicalResolved) {
    throw ("unsafe_launch: canonical exe missing: " + $canonical)
  }

  $planPath = Join-Path $RepoRoot ("build_graph\" + $Config.ToLowerInvariant() + "\ngksgraph_plan.json")
  if (Test-Path -LiteralPath $planPath) {
    $plan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json
    if ($plan.targets) {
      foreach ($target in $plan.targets) {
        if ($target.name -eq 'widget_sandbox' -and $target.output_path) {
          $candidate = Join-Path $RepoRoot ([string]$target.output_path)
          if (Test-IsForbiddenWidgetSandboxPath -Path $candidate -RepoRoot $RepoRoot) {
            throw ("unsafe_launch: graph plan points to forbidden artifact path: " + $candidate)
          }
        }
      }
    }
  }

  return $canonicalResolved
}

function Get-WidgetSandboxBuildInfo {
  param(
    [string]$ExePath,
    [string]$Config,
    [string]$RepoRoot
  )

  $exeItem = Get-Item -LiteralPath $ExePath
  $infoPath = Join-Path $exeItem.DirectoryName 'widget_sandbox.buildinfo.json'
  $utcNow = (Get-Date).ToUniversalTime().ToString('o')

  $existing = $null
  if (Test-Path -LiteralPath $infoPath) {
    try {
      $existing = Get-Content -Raw -LiteralPath $infoPath | ConvertFrom-Json
    }
    catch {
      $existing = $null
    }
  }

  $info = [ordered]@{
    build_path = $ExePath
    config = $Config
    repo_root = $RepoRoot
    exe_write_time_utc = $exeItem.LastWriteTimeUtc.ToString('o')
    first_seen_utc = if ($null -ne $existing -and $existing.first_seen_utc) { [string]$existing.first_seen_utc } else { $utcNow }
    last_launch_utc = $utcNow
  }

  $info | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $infoPath -Encoding UTF8

  return [pscustomobject]@{
    info_path = $infoPath
    build_path = $info.build_path
    config = $info.config
    exe_write_time_utc = $info.exe_write_time_utc
    first_seen_utc = $info.first_seen_utc
    last_launch_utc = $info.last_launch_utc
  }
}
