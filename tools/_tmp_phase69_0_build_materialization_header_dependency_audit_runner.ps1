#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
  Write-Host "FATAL: $_"
  exit 1
}

# ============================================================================
# PHASE69_0: BUILD MATERIALIZATION + HEADER-DEPENDENCY REBUILD AUDIT
# ============================================================================
# Audit-only phase.
# - no runtime behavior changes
# - no new guard integrations
# - compare proof-oriented orchestration path vs native compile/link path
# - prove diagnosis with fresh evidence
# ============================================================================

$WorkspaceRoot = Get-Location | Select-Object -ExpandProperty Path
$ProofRoot = Join-Path $WorkspaceRoot '_proof'
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ProofName = "phase69_0_build_materialization_header_dependency_audit_$Timestamp"
$StageRoot = Join-Path $WorkspaceRoot ("_artifacts/runtime/" + $ProofName)
$ZipPath = Join-Path $ProofRoot ($ProofName + '.zip')
$ProofPathRelative = "_proof/$ProofName.zip"

$HeaderPath = Join-Path $WorkspaceRoot 'apps/runtime_phase53_guard.hpp'
$TargetMain = Join-Path $WorkspaceRoot 'apps/sandbox_app/main.cpp'
$TargetObj = Join-Path $WorkspaceRoot 'build/debug/obj/sandbox_app/apps/sandbox_app/main.obj'
$TargetExe = Join-Path $WorkspaceRoot 'build/debug/bin/sandbox_app.exe'

$PlanOut = Join-Path $StageRoot '__plan_stdout.txt'
$ProofBuildOut1 = Join-Path $StageRoot '__proof_build_materialization_stdout.txt'
$ProofBuildOut2 = Join-Path $StageRoot '__proof_build_header_rebuild_stdout.txt'
$NativeBuildOut = Join-Path $StageRoot '__native_build_stdout.txt'

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
    Add-Content -LiteralPath $OutFile -Value ('BUILD_ERROR=TIMEOUT step=' + $StepName + ' timeout_seconds=' + $TimeoutSeconds)
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
    Add-Content -LiteralPath $OutFile -Value ('BUILD_ERROR=TIMEOUT step=' + $StepName + ' timeout_seconds=' + $TimeoutSeconds)
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

if (-not (Test-Path -LiteralPath $HeaderPath) -or -not (Test-Path -LiteralPath $TargetMain)) {
  Write-Host 'FATAL: required audit source files missing'
  exit 1
}

# Enforce one-zip-per-phase-output going forward: remove older phase69_0 zips.
Get-ChildItem -LiteralPath $ProofRoot -Filter 'phase69_0_build_materialization_header_dependency_audit_*.zip' -ErrorAction SilentlyContinue |
  ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }

# 1) Build plan generation for sandbox_app.
$plan = Invoke-PythonToFile -PythonExe $pythonExe -ArgumentList @('-m', 'ngksgraph', 'build', '--profile', 'debug', '--msvc-auto', '--target', 'sandbox_app') -OutFile $PlanOut -TimeoutSeconds 180 -StepName 'plan_sandbox_app'
if ($plan.TimedOut -or $plan.ExitCode -ne 0) {
  Write-Host 'FATAL: sandbox_app build plan failed'
  exit 1
}

$planText = Get-Content -LiteralPath $PlanOut -Raw
$planMatch = [regex]::Match($planText, 'BuildCore plan:\s+(.+)')
$planPath = if ($planMatch.Success) { $planMatch.Groups[1].Value.Trim() } else { Join-Path $WorkspaceRoot 'build_graph/debug/ngksbuildcore_plan.json' }
$planJson = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
$compileNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Compile apps/sandbox_app/main.cpp for sandbox_app' })[0]
$linkNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Link sandbox_app' })[0]
if ($null -eq $compileNode -or $null -eq $linkNode) {
  Write-Host 'FATAL: compile/link plan nodes missing'
  exit 1
}

$compileInputs = @($compileNode.inputs)
$headerTrackedInCompileInputs = $compileInputs -contains 'apps/runtime_phase53_guard.hpp'

# 2) Native materialization path (authoritative compile/link execution from generated plan).
$msvcEnvScript = Join-Path $WorkspaceRoot 'tools/enter_msvc_env.ps1'
if (-not (Test-Path -LiteralPath $msvcEnvScript)) {
  Write-Host 'FATAL: MSVC environment import script missing'
  exit 1
}

Set-Content -LiteralPath $NativeBuildOut -Value 'build_mode=plan_native_compile_link' -Encoding UTF8
try {
  & $msvcEnvScript *>&1 | Out-File -LiteralPath $NativeBuildOut -Append -Encoding UTF8
} catch {
  Add-Content -LiteralPath $NativeBuildOut -Value ('BUILD_ERROR=MSVC_ENV_IMPORT_FAILED detail=' + $_.Exception.Message)
  Write-Host 'FATAL: MSVC environment import failed'
  exit 1
}

if (Test-Path -LiteralPath $TargetExe) { Remove-Item -LiteralPath $TargetExe -Force }

$compileOut = Join-Path $StageRoot '__compile_stdout.txt'
$linkOut = Join-Path $StageRoot '__link_stdout.txt'

Add-Content -LiteralPath $NativeBuildOut -Value ('BUILD_STEP=compile command=' + $compileNode.cmd)
$nativeCompile = Invoke-CmdToFile -CommandLine $compileNode.cmd -OutFile $compileOut -TimeoutSeconds 240 -StepName 'native_compile'
if (Test-Path -LiteralPath $compileOut) { Get-Content -LiteralPath $compileOut | Add-Content -LiteralPath $NativeBuildOut }
if ($nativeCompile.TimedOut -or $nativeCompile.ExitCode -ne 0) {
  Add-Content -LiteralPath $NativeBuildOut -Value ('BUILD_ERROR=COMPILE_FAILED exit_code=' + $nativeCompile.ExitCode)
  Write-Host 'FATAL: native compile failed'
  exit 1
}

Add-Content -LiteralPath $NativeBuildOut -Value ('BUILD_STEP=link command=' + $linkNode.cmd)
$nativeLink = Invoke-CmdToFile -CommandLine $linkNode.cmd -OutFile $linkOut -TimeoutSeconds 240 -StepName 'native_link'
if (Test-Path -LiteralPath $linkOut) { Get-Content -LiteralPath $linkOut | Add-Content -LiteralPath $NativeBuildOut }
if ($nativeLink.TimedOut -or $nativeLink.ExitCode -ne 0) {
  Add-Content -LiteralPath $NativeBuildOut -Value ('BUILD_ERROR=LINK_FAILED exit_code=' + $nativeLink.ExitCode)
  Write-Host 'FATAL: native link failed'
  exit 1
}

$nativeMaterializedCanonicalExe = Test-Path -LiteralPath $TargetExe
$nativeObjTimestampBeforeHeaderTouch = if (Test-Path -LiteralPath $TargetObj) { (Get-Item -LiteralPath $TargetObj).LastWriteTimeUtc } else { [datetime]::MinValue }

# 3) Proof-oriented path: run ngksbuildcore and verify canonical exe materialization reliability.
if (Test-Path -LiteralPath $TargetExe) { Remove-Item -LiteralPath $TargetExe -Force }
$proofRunDir1 = Join-Path $StageRoot '__proof_build_run_1'
New-Item -ItemType Directory -Path $proofRunDir1 -Force | Out-Null
$proofBuild1 = Invoke-PythonToFile -PythonExe $pythonExe -ArgumentList @('-m', 'ngksbuildcore', 'run', '--plan', $planPath, '--proof', $proofRunDir1, '-j', '1') -OutFile $ProofBuildOut1 -TimeoutSeconds 240 -StepName 'proof_build_materialization_check'
$proofPathExitCodeOk = ($proofBuild1.TimedOut -eq $false) -and ($proofBuild1.ExitCode -eq 0)
$proofPathMaterializedCanonicalExe = Test-Path -LiteralPath $TargetExe
$proofDelegationMarkerPresent = (Get-Content -LiteralPath $ProofBuildOut1 -Raw) -match 'BuildCore direct run intercepted: delegating to DevFabEco orchestrator'

# 4) Header-triggered rebuild behavior on proof path.
$headerItem = Get-Item -LiteralPath $HeaderPath
$headerTimestampOriginal = $headerItem.LastWriteTimeUtc
$headerTouchedTime = [datetime]::UtcNow.AddSeconds(2)
$headerItem.LastWriteTimeUtc = $headerTouchedTime

$proofRunDir2 = Join-Path $StageRoot '__proof_build_run_2'
New-Item -ItemType Directory -Path $proofRunDir2 -Force | Out-Null
$proofBuild2 = Invoke-PythonToFile -PythonExe $pythonExe -ArgumentList @('-m', 'ngksbuildcore', 'run', '--plan', $planPath, '--proof', $proofRunDir2, '-j', '1') -OutFile $ProofBuildOut2 -TimeoutSeconds 240 -StepName 'proof_build_header_rebuild_check'
$proofHeaderCheckExitCodeOk = ($proofBuild2.TimedOut -eq $false) -and ($proofBuild2.ExitCode -eq 0)
$nativeObjTimestampAfterProofHeaderTouch = if (Test-Path -LiteralPath $TargetObj) { (Get-Item -LiteralPath $TargetObj).LastWriteTimeUtc } else { [datetime]::MinValue }
$objChangedAfterHeaderTouchOnProofPath = $nativeObjTimestampAfterProofHeaderTouch -gt $nativeObjTimestampBeforeHeaderTouch

# Restore original header timestamp to avoid filesystem drift.
(Get-Item -LiteralPath $HeaderPath).LastWriteTimeUtc = $headerTimestampOriginal

# Diagnosis synthesis.
$diagnosisProofPathNoCanonicalMaterialization = $proofPathExitCodeOk -and (-not $proofPathMaterializedCanonicalExe)
$diagnosisHeaderDependencyGap = (-not $headerTrackedInCompileInputs) -and (-not $objChangedAfterHeaderTouchOnProofPath)
$smallestFixTarget = 'Add deterministic C/C++ include dependency tracking in plan generation for compile nodes (first shared-header proof target: apps/runtime_phase53_guard.hpp) and add canonical-output materialization check after proof-oriented run.'

$checkRows = @()
$checkRows += ('check_plan_generated=' + $(if ($plan.ExitCode -eq 0 -and $plan.TimedOut -eq $false) { 'YES' } else { 'NO' }))
$checkRows += ('check_compile_node_found=' + $(if ($compileNode) { 'YES' } else { 'NO' }))
$checkRows += ('check_link_node_found=' + $(if ($linkNode) { 'YES' } else { 'NO' }))
$checkRows += ('check_header_tracked_in_compile_inputs=' + $(if ($headerTrackedInCompileInputs) { 'YES' } else { 'NO' }))
$checkRows += ('check_native_path_materializes_canonical_exe=' + $(if ($nativeMaterializedCanonicalExe) { 'YES' } else { 'NO' }))
$checkRows += ('check_proof_path_exit_success=' + $(if ($proofPathExitCodeOk) { 'YES' } else { 'NO' }))
$checkRows += ('check_proof_path_materializes_canonical_exe=' + $(if ($proofPathMaterializedCanonicalExe) { 'YES' } else { 'NO' }))
$checkRows += ('check_proof_path_delegation_marker_present=' + $(if ($proofDelegationMarkerPresent) { 'YES' } else { 'NO' }))
$checkRows += ('check_proof_header_touch_exit_success=' + $(if ($proofHeaderCheckExitCodeOk) { 'YES' } else { 'NO' }))
$checkRows += ('check_obj_changed_after_header_touch_on_proof_path=' + $(if ($objChangedAfterHeaderTouchOnProofPath) { 'YES' } else { 'NO' }))
$checkRows += ('check_diagnosis_proof_path_no_materialization=' + $(if ($diagnosisProofPathNoCanonicalMaterialization) { 'YES' } else { 'NO' }))
$checkRows += ('check_diagnosis_header_dependency_gap=' + $(if ($diagnosisHeaderDependencyGap) { 'YES' } else { 'NO' }))

$failedCount = (@($checkRows | Where-Object { $_ -match '=NO$' -and $_ -notmatch '^check_proof_path_materializes_canonical_exe=NO$' -and $_ -notmatch '^check_header_tracked_in_compile_inputs=NO$' -and $_ -notmatch '^check_obj_changed_after_header_touch_on_proof_path=NO$' })).Count
$phaseStatus = if (($diagnosisProofPathNoCanonicalMaterialization -and $diagnosisHeaderDependencyGap) -and $failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $StageRoot '90_build_materialization_checks.txt'
$checkLines = @()
$checkLines += 'audit_target=sandbox_app'
$checkLines += 'scope=build_materialization_and_shared_header_rebuild_correctness'
$checkLines += 'proof_orchestration_path=python_-m_ngksbuildcore_run_with_plan_and_proof'
$checkLines += 'native_materialization_path=plan_driven_native_compile_plus_link_via_msvc'
$checkLines += ('header_path=' + (Resolve-Path -LiteralPath $HeaderPath).Path)
$checkLines += ('target_main=' + (Resolve-Path -LiteralPath $TargetMain).Path)
$checkLines += ('target_obj=' + $TargetObj)
$checkLines += ('target_exe=' + $TargetExe)
$checkLines += ('compile_node_inputs_count=' + $compileInputs.Count)
$checkLines += ('header_tracked_in_compile_inputs=' + $(if ($headerTrackedInCompileInputs) { 'YES' } else { 'NO' }))
$checkLines += ('native_obj_timestamp_before_header_touch_utc=' + $nativeObjTimestampBeforeHeaderTouch.ToString('o'))
$checkLines += ('native_obj_timestamp_after_proof_header_touch_utc=' + $nativeObjTimestampAfterProofHeaderTouch.ToString('o'))
$checkLines += ('proof_path_exit_code=' + $proofBuild1.ExitCode)
$checkLines += ('proof_path_materialized_canonical_exe=' + $(if ($proofPathMaterializedCanonicalExe) { 'YES' } else { 'NO' }))
$checkLines += ('proof_path_delegation_marker_present=' + $(if ($proofDelegationMarkerPresent) { 'YES' } else { 'NO' }))
$checkLines += ('proof_header_touch_exit_code=' + $proofBuild2.ExitCode)
$checkLines += ('obj_changed_after_header_touch_on_proof_path=' + $(if ($objChangedAfterHeaderTouchOnProofPath) { 'YES' } else { 'NO' }))
$checkLines += ('diagnosis_proof_orchestration_materialization_gap=' + $(if ($diagnosisProofPathNoCanonicalMaterialization) { 'YES' } else { 'NO' }))
$checkLines += ('diagnosis_shared_header_rebuild_gap=' + $(if ($diagnosisHeaderDependencyGap) { 'YES' } else { 'NO' }))
$checkLines += ('smallest_first_fix_target=' + $smallestFixTarget)
$checkLines += $checkRows
$checkLines += ('failed_check_count=' + $failedCount)
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $StageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE69_0_BUILD_MATERIALIZATION_AND_HEADER_DEPENDENCY_REBUILD_AUDIT'
$contract += 'objective=Diagnose proof-path materialization gaps and shared-header rebuild correctness gaps against native compile/link path with real evidence'
$contract += 'changes_introduced=Added audit-only phase runner and produced evidence-backed diagnosis plus smallest first fix target'
$contract += 'runtime_behavior_changes=None'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $ProofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) {
  Write-Host 'FATAL: 90_build_materialization_checks.txt is not well-formed'
  exit 1
}
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) {
  Write-Host 'FATAL: 99_contract_summary.txt is not well-formed'
  exit 1
}

# Keep only required output artifacts in final zip.
[void](Remove-FileWithRetry -Path $PlanOut)
[void](Remove-FileWithRetry -Path $ProofBuildOut1)
[void](Remove-FileWithRetry -Path $ProofBuildOut2)
[void](Remove-FileWithRetry -Path $NativeBuildOut)
[void](Remove-FileWithRetry -Path $compileOut)
[void](Remove-FileWithRetry -Path $linkOut)
if (Test-Path -LiteralPath $proofRunDir1) { Remove-Item -LiteralPath $proofRunDir1 -Recurse -Force }
if (Test-Path -LiteralPath $proofRunDir2) { Remove-Item -LiteralPath $proofRunDir2 -Recurse -Force }

$expectedEntries = @(
  '90_build_materialization_checks.txt',
  '99_contract_summary.txt'
)

New-ProofZip -SourceDir $StageRoot -DestinationZip $ZipPath
if (-not (Test-Path -LiteralPath $ZipPath)) {
  Write-Host 'FATAL: final proof zip was not created'
  exit 1
}
if (-not (Test-ZipContainsEntries -ZipFile $ZipPath -ExpectedEntries $expectedEntries)) {
  Write-Host 'FATAL: final proof zip is missing expected artifacts'
  exit 1
}

Remove-Item -LiteralPath $StageRoot -Recurse -Force

$phaseArtifactsInProof = @(Get-ChildItem -LiteralPath $ProofRoot | Where-Object { $_.Name -like 'phase69_0_build_materialization_header_dependency_audit_*' })
if ($phaseArtifactsInProof.Count -ne 1 -or $phaseArtifactsInProof[0].Name -ne ($ProofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase-specific proof output'
  exit 1
}

Write-Host ('PF=' + $ProofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase69_0_status=' + $phaseStatus)
exit 0
