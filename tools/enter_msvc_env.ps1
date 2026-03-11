# NGKsSystems
# NGKsUI Runtime
#
# tools/enter_msvc_env.ps1
#
# Purpose:
#   Import MSVC build environment into the CURRENT PowerShell session in a robust, auditable way.
#
# Why:
#   Running VsDevCmd.bat with a long inline "cmd /c ..." can hit:
#     "The input line is too long. The syntax of the command is incorrect."
#   This script avoids that by writing a short temporary .cmd that dumps env to a file,
#   then importing that file into PowerShell.
#
# Option 4 / Auditability:
#   - This script prints clear status lines.
#   - Callers should redirect output to _proof when required.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Status([string]$msg) {
  Write-Host $msg
}

function Get-VsWherePath {
  $p = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
  if (Test-Path $p) { return $p }
  return $null
}

function Require-File([string]$path, [string]$label) {
  if (-not (Test-Path $path)) {
    throw "$label not found: $path"
  }
}

function Test-IsAllowedEnvKey([string]$key) {
  $exactAllow = @(
    "PATH",
    "INCLUDE",
    "LIB",
    "LIBPATH",
    "VSINSTALLDIR",
    "VisualStudioVersion",
    "WindowsSdkDir",
    "WindowsSDKVersion",
    "UCRTVersion",
    "UniversalCRTSdkDir"
  )

  foreach ($name in $exactAllow) {
    if ([string]::Equals($key, $name, [System.StringComparison]::OrdinalIgnoreCase)) {
      return $true
    }
  }

  $prefixAllow = @(
    "VSCMD_",
    "VS",
    "Windows",
    "UCRT",
    "NGK_",
    "NGKSUI_"
  )

  foreach ($prefix in $prefixAllow) {
    if ($key.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
      return $true
    }
  }

  return $false
}

function Write-AuditedEnvSnapshot([string[]]$lines, [string]$proofDir, [string]$stamp) {
  $envDumpPath = Join-Path $proofDir "__ngk_vsenv_$stamp.txt"

  $filteredLines = foreach ($line in $lines) {
    if ($line.Length -eq 0) {
      continue
    }

    $idx = $line.IndexOf("=")
    if ($idx -le 0) {
      continue
    }

    $k = $line.Substring(0, $idx)
    $v = $line.Substring($idx + 1)

    if ($k -match '(?i)(SECRET|TOKEN|KEY|PASS|CLIENT|COOKIE|OAUTH|BEARER|ASKPASS)') {
      continue
    }

    if (Test-IsAllowedEnvKey $k) {
      if ([string]::Equals($k, "PATH", [System.StringComparison]::OrdinalIgnoreCase)) {
        $safeSegments = @()
        foreach ($segment in ($v -split ';')) {
          if ([string]::IsNullOrWhiteSpace($segment)) { continue }
          if ($segment -match '(?i)(SECRET|TOKEN|KEY|PASS|CLIENT|COOKIE|OAUTH|BEARER|ASKPASS)') { continue }
          $safeSegments += $segment
        }
        if ($safeSegments.Count -gt 0) {
          "PATH=" + ($safeSegments -join ';')
        }
        continue
      }

      "$k=$v"
    }
  }

  $secretPattern = '(?i)(SECRET|TOKEN|KEY|PASS|CLIENT|COOKIE|OAUTH|BEARER|ASKPASS)'
  $snapshotMatches = $filteredLines | Select-String -Pattern $secretPattern -AllMatches -ErrorAction SilentlyContinue
  if ($snapshotMatches) {
    $securityFailPath = Join-Path $proofDir "__ngk_vsenv_security_fail_$stamp.txt"
    "FAIL: secret-scan matched in allowlist snapshot" | Set-Content -Path $securityFailPath -Encoding UTF8
    $snapshotMatches | Select-Object -First 80 | Out-File -FilePath $securityFailPath -Append -Encoding UTF8
    throw "Secret-scan gate failed for env snapshot. See: $securityFailPath"
  }

  $filteredLines | Set-Content -Path $envDumpPath -Encoding ASCII
  return $envDumpPath
}

$root = (Get-Location).Path

# Ensure a predictable place for temporary artifacts.
$proofDir = Join-Path $root "_proof"
if (-not (Test-Path $proofDir)) {
  New-Item -ItemType Directory -Force $proofDir | Out-Null
}

$existingCl = (Get-Command cl.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
$existingLink = (Get-Command link.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
if ($env:VSCMD_VER -and $existingCl -and $existingLink) {
  $stampActive = Get-Date -Format "yyyyMMdd_HHmmss"
  $activeLines = Get-ChildItem Env: | ForEach-Object { "$($_.Name)=$($_.Value)" }
  $activeSnapshot = Write-AuditedEnvSnapshot -lines $activeLines -proofDir $proofDir -stamp $stampActive
  Write-Status "MSVC environment already active (VSCMD_VER=$($env:VSCMD_VER))."
  Write-Status "cl.exe: $existingCl"
  Write-Status "link.exe: $existingLink"
  Write-Status "Audited env snapshot: $activeSnapshot"
  Write-Status "MSVC env import OK."
  return
}

if ($env:VSCMD_PREINIT_PATH) {
  [System.Environment]::SetEnvironmentVariable("PATH", $env:VSCMD_PREINIT_PATH, "Process")
  try {
    Set-Item -Path "Env:PATH" -Value $env:VSCMD_PREINIT_PATH -ErrorAction SilentlyContinue | Out-Null
  } catch {
  }
}

$vswhere = Get-VsWherePath
if (-not $vswhere) {
  throw "vswhere.exe not found under Program Files (x86). Install Visual Studio / Build Tools first."
}

# Find latest VS install that has VC tools.
$vsInstallPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ([string]::IsNullOrWhiteSpace($vsInstallPath)) {
  throw "No Visual Studio installation with VC.Tools.x86.x64 found."
}

$vsDevCmd = Join-Path $vsInstallPath "Common7\Tools\VsDevCmd.bat"
Require-File $vsDevCmd "VsDevCmd.bat"

# Temp files (kept inside _proof for auditability)
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$cmdPath = Join-Path $proofDir "__ngk_vsdevcmd_$stamp.cmd"
$envRawPath = Join-Path ([System.IO.Path]::GetTempPath()) "__ngk_vsenv_raw_$stamp.txt"
$envDumpPath = Join-Path $proofDir "__ngk_vsenv_$stamp.txt"
$cmdOutPath = Join-Path $proofDir "__ngk_vsdevcmd_out_$stamp.txt"

# Write a short .cmd to avoid command-line length issues.
# Important: "set" dumps the environment after VsDevCmd modifies it.
@"
@echo off
call "$vsDevCmd" -arch=x64 -host_arch=x64
if errorlevel 1 (
  echo VsDevCmd failed with errorlevel %errorlevel%
  exit /b %errorlevel%
)
set > "$envRawPath"
exit /b 0
"@ | Set-Content -Path $cmdPath -Encoding ASCII

Write-Status "MSVC env import starting..."
Write-Status "VS install: $vsInstallPath"
Write-Status "VsDevCmd: $vsDevCmd"
Write-Status "Audited env snapshot: $envDumpPath"

# Run the cmd and capture stdout/stderr
cmd.exe /c "`"$cmdPath`"" > $cmdOutPath 2>&1

if (-not (Test-Path $envRawPath)) {
  Write-Status "ERROR: Env dump file not created. See: $cmdOutPath"
  throw "MSVC env dump missing"
}

# Import env dump into current PowerShell session.
# Lines are KEY=VALUE; values can include '=' so split only on first '='.
$lines = Get-Content -Path $envRawPath -Encoding ASCII
foreach ($line in $lines) {
  if ($line.Length -eq 0) { continue }
  $idx = $line.IndexOf("=")
  if ($idx -le 0) { continue }

  $k = $line.Substring(0, $idx)
  $v = $line.Substring($idx + 1)

  # Set both process-level env and PS drive Env:
  [System.Environment]::SetEnvironmentVariable($k, $v, "Process")
  try {
    Set-Item -Path "Env:$k" -Value $v -ErrorAction SilentlyContinue | Out-Null
  } catch {
    # Ignore any weird keys that PowerShell won't accept
  }
}

$envDumpPath = Write-AuditedEnvSnapshot -lines $lines -proofDir $proofDir -stamp $stamp

try {
  if (Test-Path $envRawPath) {
    Remove-Item -Path $envRawPath -Force -ErrorAction SilentlyContinue
  }
} catch {
}

# Sanity checks (do not fail hard unless explicitly missing)
$clPath = (Get-Command cl.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
$linkPath = (Get-Command link.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)

if (-not $clPath) {
  Write-Status "ERROR: cl.exe not found after import. See: $envDumpPath"
  throw "cl.exe not found"
}
if (-not $linkPath) {
  Write-Status "ERROR: link.exe not found after import. See: $envDumpPath"
  throw "link.exe not found"
}

Write-Status "MSVC environment imported from: $vsDevCmd"
Write-Status "cl.exe: $clPath"
Write-Status "link.exe: $linkPath"
Write-Status "MSVC env import OK."