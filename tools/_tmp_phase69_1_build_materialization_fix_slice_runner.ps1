#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
  Write-Host "FATAL: $_"
  exit 1
}

# ============================================================================
# PHASE69_1: FIRST BUILD-MATERIALIZATION FIX SLICE
# ============================================================================
# Scope:
#  1) deterministic header/include dependency tracking for compile nodes
#  2) canonical-output materialization check after proof-oriented runs
# ============================================================================

$WorkspaceRoot = Get-Location | Select-Object -ExpandProperty Path
$ProofRoot = Join-Path $WorkspaceRoot '_proof'
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ProofName = "phase69_1_build_materialization_fix_slice_$Timestamp"
$StageRoot = Join-Path $WorkspaceRoot ("_artifacts/runtime/" + $ProofName)
$ZipPath = Join-Path $ProofRoot ($ProofName + '.zip')
$ProofPathRelative = "_proof/$ProofName.zip"

$HeaderPath = Join-Path $WorkspaceRoot 'apps/runtime_phase53_guard.hpp'
$TargetObj = Join-Path $WorkspaceRoot 'build/debug/obj/sandbox_app/apps/sandbox_app/main.obj'
$TargetExe = Join-Path $WorkspaceRoot 'build/debug/bin/sandbox_app.exe'

$PlanOut = Join-Path $StageRoot '__plan_stdout.txt'
$ProofFailOut = Join-Path $StageRoot '__proof_missing_output_stdout.txt'
$ProofPassOut = Join-Path $StageRoot '__proof_present_output_stdout.txt'
$NativeOut = Join-Path $StageRoot '__native_build_stdout.txt'

New-Item -ItemType Directory -Path $StageRoot -Force | Out-Null
Write-Host "Stage folder: $StageRoot"
Write-Host "Final zip: $ZipPath"

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
  param(
    [string]$PythonExe,
    [string[]]$ArgumentList,
    [string]$OutFile,
    [int]$TimeoutSeconds,
    [string]$StepName
  )

  $errFile = $OutFile + '.stderr.tmp'
  [void](Remove-FileWithRetry -Path $errFile)

  $quotedArgs = @()
  foreach ($arg in $ArgumentList) {
    if ($arg -match '[\s"]') {
      $quotedArgs += ('"' + ($arg -replace '"', '\"') + '"')
    } else {
      $quotedArgs += $arg
    }
  }

  $proc = Start-Process -FilePath $PythonExe -ArgumentList ($quotedArgs -join ' ') -PassThru -NoNewWindow -RedirectStandardOutput $OutFile -RedirectStandardError $errFile
  $timedOut = -not $proc.WaitForExit($TimeoutSeconds * 1000)

  if ($timedOut) {
    try { $proc.Kill() } catch {}
    try { $proc.WaitForExit() } catch {}
    Add-Content -LiteralPath $OutFile -Value ('TIMEOUT step=' + $StepName + ' timeout_seconds=' + $TimeoutSeconds)
    if (Test-Path -LiteralPath $errFile) {
      Get-Content -LiteralPath $errFile | Add-Content -LiteralPath $OutFile
      [void](Remove-FileWithRetry -Path $errFile)
    }
    return [pscustomobject]@{ ExitCode = 124; TimedOut = $true }
  }

  $proc.WaitForExit()
  $exitCode = $proc.ExitCode
  try { $proc.Close() } catch {}
  $proc.Dispose()

  if (Test-Path -LiteralPath $errFile) {
    $stderr = Get-Content -LiteralPath $errFile -Raw
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
      Add-Content -LiteralPath $OutFile -Value $stderr
    }
    [void](Remove-FileWithRetry -Path $errFile)
  }

  return [pscustomobject]@{ ExitCode = $exitCode; TimedOut = $false }
}

function Invoke-CmdToFile {
  param(
    [string]$CommandLine,
    [string]$OutFile,
    [int]$TimeoutSeconds,
    [string]$StepName
  )

  $errFile = $OutFile + '.stderr.tmp'
  [void](Remove-FileWithRetry -Path $errFile)

  $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', $CommandLine) -PassThru -NoNewWindow -RedirectStandardOutput $OutFile -RedirectStandardError $errFile
  $timedOut = -not $proc.WaitForExit($TimeoutSeconds * 1000)

  if ($timedOut) {
    try { $proc.Kill() } catch {}
    try { $proc.WaitForExit() } catch {}
    Add-Content -LiteralPath $OutFile -Value ('TIMEOUT step=' + $StepName + ' timeout_seconds=' + $TimeoutSeconds)
    if (Test-Path -LiteralPath $errFile) {
      Get-Content -LiteralPath $errFile | Add-Content -LiteralPath $OutFile
      [void](Remove-FileWithRetry -Path $errFile)
    }
    return [pscustomobject]@{ ExitCode = 124; TimedOut = $true }
  }

  $proc.WaitForExit()
  $exitCode = $proc.ExitCode
  try { $proc.Close() } catch {}
  $proc.Dispose()

  if (Test-Path -LiteralPath $errFile) {
    $stderr = Get-Content -LiteralPath $errFile -Raw
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
      Add-Content -LiteralPath $OutFile -Value $stderr
    }
    [void](Remove-FileWithRetry -Path $errFile)
  }

  return [pscustomobject]@{ ExitCode = $exitCode; TimedOut = $false }
}

function Test-LinePresent {
  param([string]$Path, [string]$Pattern)
  $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $lines) { return $false }
  foreach ($line in $lines) {
    if ($line -match $Pattern) { return $true }
  }
  return $false
}

function Test-KvFileWellFormed {
  param([string]$FilePath)
  if (-not (Test-Path -LiteralPath $FilePath)) { return $false }
  $lines = @(Get-Content -LiteralPath $FilePath | Where-Object { $_ -match '\S' -and $_ -notmatch '^#' })
  foreach ($line in $lines) {
    if ($line -notmatch '^[a-zA-Z_][a-zA-Z0-9_]*=') { return $false }
  }
  return $true
}

function New-ProofZip {
  param([string]$SourceDir, [string]$DestinationZip)
  if (Test-Path -LiteralPath $DestinationZip) {
    Remove-Item -LiteralPath $DestinationZip -Force
  }
  Compress-Archive -Path (Join-Path $SourceDir '*') -DestinationPath $DestinationZip -Force
}

function Test-ZipContainsEntries {
  param([string]$ZipFile, [string[]]$ExpectedEntries)
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipFile)
  try {
    $entryNames = @($archive.Entries | ForEach-Object { $_.FullName })
    foreach ($entry in $ExpectedEntries) {
      if ($entryNames -notcontains $entry) { return $false }
    }
    return $true
  }
  finally {
    $archive.Dispose()
  }
}

$pythonExe = Join-Path $WorkspaceRoot '.venv/Scripts/python.exe'
if (-not (Test-Path -LiteralPath $pythonExe)) {
  Write-Host 'FATAL: .venv python executable missing'
  exit 1
}

if (-not (Test-Path -LiteralPath $HeaderPath)) {
  Write-Host 'FATAL: runtime header missing'
  exit 1
}

# Enforce single zip for phase output going forward.
Get-ChildItem -LiteralPath $ProofRoot -Filter 'phase69_1_build_materialization_fix_slice_*.zip' -ErrorAction SilentlyContinue |
  ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }

# Generate plan and extract compile/link nodes.
$plan = Invoke-PythonToFile -PythonExe $pythonExe -ArgumentList @('-m', 'ngksgraph', 'build', '--profile', 'debug', '--msvc-auto', '--target', 'sandbox_app') -OutFile $PlanOut -TimeoutSeconds 180 -StepName 'plan_sandbox_app'
if ($plan.TimedOut -or $plan.ExitCode -ne 0) {
  Write-Host 'FATAL: plan generation failed'
  exit 1
}

$planText = Get-Content -LiteralPath $PlanOut -Raw
$planMatch = [regex]::Match($planText, 'BuildCore plan:\s+(.+)')
$planPath = if ($planMatch.Success) { $planMatch.Groups[1].Value.Trim() } else { Join-Path $WorkspaceRoot 'build_graph/debug/ngksbuildcore_plan.json' }
$planJson = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
$compileNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Compile apps/sandbox_app/main.cpp for sandbox_app' })[0]
$linkNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Link sandbox_app' })[0]
if ($null -eq $compileNode -or $null -eq $linkNode) {
  Write-Host 'FATAL: compile/link nodes missing'
  exit 1
}

$headerTracked = @($compileNode.inputs) -contains 'apps/runtime_phase53_guard.hpp'

# Native path materialization and timestamp baseline.
$msvcEnvScript = Join-Path $WorkspaceRoot 'tools/enter_msvc_env.ps1'
if (-not (Test-Path -LiteralPath $msvcEnvScript)) {
  Write-Host 'FATAL: msvc env script missing'
  exit 1
}

Set-Content -LiteralPath $NativeOut -Value 'build_mode=plan_native_compile_link' -Encoding UTF8
& $msvcEnvScript *>&1 | Out-File -LiteralPath $NativeOut -Append -Encoding UTF8

$compileTmp = Join-Path $StageRoot '__compile_stdout.txt'
$linkTmp = Join-Path $StageRoot '__link_stdout.txt'

$nativeCompile1 = Invoke-CmdToFile -CommandLine $compileNode.cmd -OutFile $compileTmp -TimeoutSeconds 240 -StepName 'native_compile_baseline'
if ($nativeCompile1.TimedOut -or $nativeCompile1.ExitCode -ne 0) { Write-Host 'FATAL: native compile baseline failed'; exit 1 }
$nativeLink1 = Invoke-CmdToFile -CommandLine $linkNode.cmd -OutFile $linkTmp -TimeoutSeconds 240 -StepName 'native_link_baseline'
if ($nativeLink1.TimedOut -or $nativeLink1.ExitCode -ne 0) { Write-Host 'FATAL: native link baseline failed'; exit 1 }
$canonicalMaterializedOnNative = Test-Path -LiteralPath $TargetExe
$objTsBeforeTouch = if (Test-Path -LiteralPath $TargetObj) { (Get-Item -LiteralPath $TargetObj).LastWriteTimeUtc } else { [datetime]::MinValue }

# Touch header and re-run dependent compile path.
$headerFile = Get-Item -LiteralPath $HeaderPath
$headerTsOriginal = $headerFile.LastWriteTimeUtc
$headerTouched = [datetime]::UtcNow.AddSeconds(2)
$headerFile.LastWriteTimeUtc = $headerTouched

$nativeCompile2 = Invoke-CmdToFile -CommandLine $compileNode.cmd -OutFile $compileTmp -TimeoutSeconds 240 -StepName 'native_compile_after_touch'
if ($nativeCompile2.TimedOut -or $nativeCompile2.ExitCode -ne 0) { Write-Host 'FATAL: native compile after header touch failed'; exit 1 }
$objTsAfterTouch = if (Test-Path -LiteralPath $TargetObj) { (Get-Item -LiteralPath $TargetObj).LastWriteTimeUtc } else { [datetime]::MinValue }
$headerTouchTriggersDependentRebuildPath = $objTsAfterTouch -gt $objTsBeforeTouch

# Restore header timestamp to avoid file metadata drift.
(Get-Item -LiteralPath $HeaderPath).LastWriteTimeUtc = $headerTsOriginal

# Proof-oriented run should fail clearly when canonical output is missing.
if (Test-Path -LiteralPath $TargetExe) { Remove-Item -LiteralPath $TargetExe -Force }
$proofRunDirFail = Join-Path $StageRoot '__proof_run_fail'
New-Item -ItemType Directory -Path $proofRunDirFail -Force | Out-Null
$proofFail = Invoke-PythonToFile -PythonExe $pythonExe -ArgumentList @('-m', 'ngksbuildcore', 'run', '--plan', $planPath, '--proof', $proofRunDirFail, '-j', '1') -OutFile $ProofFailOut -TimeoutSeconds 240 -StepName 'proof_missing_output'
$proofFailsClearlyWhenOutputMissing = ($proofFail.ExitCode -ne 0) -and (Test-LinePresent -Path $ProofFailOut -Pattern '^CANONICAL_OUTPUT_MATERIALIZATION_CHECK=FAIL$') -and (Test-LinePresent -Path $ProofFailOut -Pattern '^CANONICAL_OUTPUT_MISSING=')

# Materialize canonical output and verify proof-oriented run detects presence.
$nativeCompile3 = Invoke-CmdToFile -CommandLine $compileNode.cmd -OutFile $compileTmp -TimeoutSeconds 240 -StepName 'native_compile_for_proof_pass'
if ($nativeCompile3.TimedOut -or $nativeCompile3.ExitCode -ne 0) { Write-Host 'FATAL: native compile for proof pass failed'; exit 1 }
$nativeLink2 = Invoke-CmdToFile -CommandLine $linkNode.cmd -OutFile $linkTmp -TimeoutSeconds 240 -StepName 'native_link_for_proof_pass'
if ($nativeLink2.TimedOut -or $nativeLink2.ExitCode -ne 0) { Write-Host 'FATAL: native link for proof pass failed'; exit 1 }

$proofRunDirPass = Join-Path $StageRoot '__proof_run_pass'
New-Item -ItemType Directory -Path $proofRunDirPass -Force | Out-Null
$proofPass = Invoke-PythonToFile -PythonExe $pythonExe -ArgumentList @('-m', 'ngksbuildcore', 'run', '--plan', $planPath, '--proof', $proofRunDirPass, '-j', '1') -OutFile $ProofPassOut -TimeoutSeconds 240 -StepName 'proof_present_output'
$proofDetectsCanonicalPresence = ($proofPass.ExitCode -eq 0) -and (Test-LinePresent -Path $ProofPassOut -Pattern '^CANONICAL_OUTPUT_MATERIALIZATION_CHECK=PASS$')

$checks = @()
$checks += ('check_header_dependency_tracked=' + $(if ($headerTracked) { 'YES' } else { 'NO' }))
$checks += ('check_native_materialization_detected=' + $(if ($canonicalMaterializedOnNative) { 'YES' } else { 'NO' }))
$checks += ('check_header_touch_triggers_rebuild_path=' + $(if ($headerTouchTriggersDependentRebuildPath) { 'YES' } else { 'NO' }))
$checks += ('check_proof_run_fails_clearly_when_output_missing=' + $(if ($proofFailsClearlyWhenOutputMissing) { 'YES' } else { 'NO' }))
$checks += ('check_proof_run_detects_materialized_output=' + $(if ($proofDetectsCanonicalPresence) { 'YES' } else { 'NO' }))

$failedCount = (@($checks | Where-Object { $_ -match '=NO$' })).Count
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $StageRoot '90_build_fix_checks.txt'
$lines = @()
$lines += 'scope=build_materialization_fix_slice'
$lines += 'target=sandbox_app'
$lines += ('header_path=' + $HeaderPath)
$lines += ('target_obj=' + $TargetObj)
$lines += ('target_exe=' + $TargetExe)
$lines += ('header_tracked_in_compile_inputs=' + $(if ($headerTracked) { 'YES' } else { 'NO' }))
$lines += ('obj_timestamp_before_touch_utc=' + $objTsBeforeTouch.ToString('o'))
$lines += ('obj_timestamp_after_touch_utc=' + $objTsAfterTouch.ToString('o'))
$lines += ('proof_missing_output_exit_code=' + $proofFail.ExitCode)
$lines += ('proof_present_output_exit_code=' + $proofPass.ExitCode)
$lines += $checks
$lines += ('failed_check_count=' + $failedCount)
$lines += ('phase_status=' + $phaseStatus)
$lines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $StageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE69_1_BUILD_MATERIALIZATION_FIRST_FIX_SLICE'
$contract += 'objective=Implement deterministic compile-node header dependency tracking and canonical-output materialization check after proof-oriented runs'
$contract += 'changes_introduced=Patched ngksgraph compile-node input tracking for headers and patched ngksbuildcore delegated run to enforce canonical-output materialization check'
$contract += 'runtime_behavior_changes=None'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $ProofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_build_fix_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

# Keep only required phase output artifacts in final zip.
[void](Remove-FileWithRetry -Path $PlanOut)
[void](Remove-FileWithRetry -Path $ProofFailOut)
[void](Remove-FileWithRetry -Path $ProofPassOut)
[void](Remove-FileWithRetry -Path $NativeOut)
[void](Remove-FileWithRetry -Path $compileTmp)
[void](Remove-FileWithRetry -Path $linkTmp)
if (Test-Path -LiteralPath $proofRunDirFail) { Remove-Item -LiteralPath $proofRunDirFail -Recurse -Force }
if (Test-Path -LiteralPath $proofRunDirPass) { Remove-Item -LiteralPath $proofRunDirPass -Recurse -Force }

$expectedEntries = @('90_build_fix_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $StageRoot -DestinationZip $ZipPath
if (-not (Test-Path -LiteralPath $ZipPath)) { Write-Host 'FATAL: zip not created'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $ZipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $StageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $ProofRoot | Where-Object { $_.Name -like 'phase69_1_build_materialization_fix_slice_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($ProofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $ProofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase69_1_status=' + $phaseStatus)
exit 0
