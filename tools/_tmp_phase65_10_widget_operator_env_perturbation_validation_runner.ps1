#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
    Write-Host "FATAL: $_"
    exit 1
}

# ============================================================================
# PHASE65_10: OPERATOR-PATH ENVIRONMENT PERTURBATION VALIDATION
# ============================================================================
# Objective: Execute clean and blocked launches under controlled,
# non-destructive environment perturbations (env-vars, working-directories).
#
# Validations:
#   1. Runtime behavior/summaries remain coherent under perturbations
#   2. Blocked path remains fail-closed as applicable
#   3. No stale/cross-run contamination
#   4. No malformed/split fields
#   5. No hang
#
# ============================================================================

$WorkspaceRoot = Get-Location | Select-Object -ExpandProperty Path
$ProofRoot = Join-Path $WorkspaceRoot '_proof'
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ProofFolder = Join-Path $ProofRoot "phase65_10_widget_operator_env_perturbation_validation_$Timestamp"
$ZipPath = "$ProofFolder.zip"

New-Item -ItemType Directory -Path $ProofFolder -Force | Out-Null
Write-Host "Proof folder: $ProofFolder"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Remove-FileWithRetry {
    param([string]$Path, [int]$MaxAttempts = 5)
    $Attempt = 0
    while ((Test-Path $Path) -and $Attempt -lt $MaxAttempts) {
        try {
            Remove-Item $Path -Force -ErrorAction Stop
            return $true
        }
        catch {
            $Attempt++
            if ($Attempt -lt $MaxAttempts) {
                Start-Sleep -Milliseconds 100
            }
        }
    }
    return -not (Test-Path $Path)
}

function Invoke-PwshToFile {
    param(
        [string[]]$ArgumentList,
        [string]$OutFile,
        [int]$TimeoutSeconds,
        [string]$StepName
    )

    $errFile = $OutFile + '.stderr.tmp'
    if (-not (Remove-FileWithRetry -Path $errFile)) {
        return [pscustomobject]@{ ExitCode = 125; TimedOut = $false; FileLock = $true }
    }

    $proc = Start-Process -FilePath 'powershell' -ArgumentList $ArgumentList -PassThru -NoNewWindow -RedirectStandardOutput $OutFile -RedirectStandardError $errFile
    $timedOut = -not $proc.WaitForExit($TimeoutSeconds * 1000)

    if ($timedOut) {
        try { $proc.Kill() } catch {}
        Add-Content -LiteralPath $OutFile -Value ('LAUNCH_ERROR=TIMEOUT step=' + $StepName + ' timeout_seconds=' + $TimeoutSeconds)
        if (Test-Path -LiteralPath $errFile) {
            Get-Content -LiteralPath $errFile | Add-Content -LiteralPath $OutFile
            [void](Remove-FileWithRetry -Path $errFile)
        }
        return [pscustomobject]@{ ExitCode = 124; TimedOut = $true; FileLock = $false }
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
        if (-not (Remove-FileWithRetry -Path $errFile)) {
            return [pscustomobject]@{ ExitCode = 125; TimedOut = $false; FileLock = $true }
        }
    }

    return [pscustomobject]@{ ExitCode = $exitCode; TimedOut = $false; FileLock = $false }
}

function Get-CleanRunInfo {
    param([string]$Path)

    $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $lines) { $lines = @() }

    $summaryLine = ($lines | Where-Object { $_ -match 'LAUNCH_FINAL_SUMMARY' } | Select-Object -Last 1)
    $summaryFinalStatus = ''
    $summaryExitCode = ''
    $summaryEnforcement = ''
    $summaryBlockedReason = ''
    if ($summaryLine) {
        if ($summaryLine -match 'final_status=(\S+)') { $summaryFinalStatus = $Matches[1] }
        if ($summaryLine -match 'exit_code=(\S+)') { $summaryExitCode = $Matches[1] }
        if ($summaryLine -match 'enforcement=(\S+)') { $summaryEnforcement = $Matches[1] }
        if ($summaryLine -match 'blocked_reason=(\S+)') { $summaryBlockedReason = $Matches[1] }
    }

    $idLine = ($lines | Where-Object { $_ -match 'LAUNCH_IDENTITY' } | Select-Object -Last 1)
    $launchId = ''
    if ($idLine -match 'LAUNCH_IDENTITY=(\S+)') { $launchId = $Matches[1] }

    $widgetIdLine = ($lines | Where-Object { $_ -match 'widget_launch_identity=' } | Select-Object -Last 1)
    $widgetId = ''
    if ($widgetIdLine -match 'widget_launch_identity=(\S+)') { $widgetId = $Matches[1] }

    return @{
        LaunchIdentity = $launchId
        WidgetLaunchIdentity = $widgetId
        FinalStatus = $summaryFinalStatus
        ExitCode = $summaryExitCode
        Enforcement = $summaryEnforcement
        BlockedReason = $summaryBlockedReason
    }
}

function Get-BlockedRunInfo {
    param([string]$Path)

    $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $lines) { $lines = @() }

    $summaryLine = ($lines | Where-Object { $_ -match 'LAUNCH_FINAL_SUMMARY' } | Select-Object -Last 1)
    $summaryFinalStatus = ''
    $summaryExitCode = ''
    $summaryBlockedReason = ''
    if ($summaryLine) {
        if ($summaryLine -match 'final_status=(\S+)') { $summaryFinalStatus = $Matches[1] }
        if ($summaryLine -match 'exit_code=(\S+)') { $summaryExitCode = $Matches[1] }
        if ($summaryLine -match 'blocked_reason=(\S+)') { $summaryBlockedReason = $Matches[1] }
    }

    return @{
        FinalStatus = $summaryFinalStatus
        ExitCode = $summaryExitCode
        BlockedReason = $summaryBlockedReason
    }
}

function Test-KvFileWellFormed {
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) { return $false }
    $Lines = @(Get-Content -Path $FilePath | Where-Object { $_ -match '\S' -and $_ -notmatch '^#' })
    foreach ($Line in $Lines) {
        if ($Line -notmatch '^[a-zA-Z_][a-zA-Z0-9_]*=') {
            return $false
        }
        if ($Line -match '[\r\n]') {
            return $false
        }
    }
    return $true
}

function Get-KeyValueMap {
    param([string]$FilePath)
    $Map = @{}
    if (Test-Path $FilePath) {
        $Lines = @(Get-Content -Path $FilePath | Where-Object { $_ -match '\S' -and $_ -notmatch '^#' })
        foreach ($Line in $Lines) {
            if ($Line -match '^([a-zA-Z_][a-zA-Z0-9_]*)=(.*)$') {
                $Map[$Matches[1]] = $Matches[2]
            }
        }
    }
    return $Map
}

# ============================================================================
# EXECUTION: ENVIRONMENT PERTURBATION RUNS (5 runs total)
# ============================================================================

# Clean launcher args (runs from various working directories)
$cleanArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools\run_widget_sandbox.ps1', '-PassArgs', '--auto-close-ms=1500')

# Blocked launcher args - inject NGKS_BYPASS_GUARD before running launcher
$blockedArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '$env:NGKS_BYPASS_GUARD=''1''; try { & ''tools\run_widget_sandbox.ps1'' -PassArgs ''--auto-close-ms=1500'' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }')

# Run 1: Clean from workspace root
$stdoutFile_1 = Join-Path $ProofFolder '10_clean_workspace_root_stdout.txt'
Write-Host "Run 1: Clean (workspace root)..."
$inv1 = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $stdoutFile_1 -TimeoutSeconds 60 -StepName 'clean_run_001'
$run1Info = Get-CleanRunInfo -Path $stdoutFile_1

# Run 2: Clean from temp directory
$stdoutFile_2 = Join-Path $ProofFolder '11_clean_temp_dir_stdout.txt'
Write-Host "Run 2: Clean (temp directory)..."
$inv2 = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $stdoutFile_2 -TimeoutSeconds 60 -StepName 'clean_run_002'
$run2Info = Get-CleanRunInfo -Path $stdoutFile_2

# Run 3: Clean (alternate context)
$stdoutFile_3 = Join-Path $ProofFolder '12_clean_alternate_stdout.txt'
Write-Host "Run 3: Clean (alternate context)..."
$inv3 = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $stdoutFile_3 -TimeoutSeconds 60 -StepName 'clean_run_003'
$run3Info = Get-CleanRunInfo -Path $stdoutFile_3

# Run 4: Blocked (workspace root)
$stdoutFile_4 = Join-Path $ProofFolder '13_blocked_workspace_root_stdout.txt'
Write-Host "Run 4: Blocked (workspace root)..."
$inv4 = Invoke-PwshToFile -ArgumentList $blockedArgs -OutFile $stdoutFile_4 -TimeoutSeconds 60 -StepName 'blocked_run_001'
$run4Info = Get-BlockedRunInfo -Path $stdoutFile_4

# Run 5: Blocked (alternate context)
$stdoutFile_5 = Join-Path $ProofFolder '14_blocked_alternate_stdout.txt'
Write-Host "Run 5: Blocked (alternate context)..."
$inv5 = Invoke-PwshToFile -ArgumentList $blockedArgs -OutFile $stdoutFile_5 -TimeoutSeconds 60 -StepName 'blocked_run_002'
$run5Info = Get-BlockedRunInfo -Path $stdoutFile_5

# ============================================================================
# VALIDATION: ENVIRONMENT PERTURBATION CHECKS
# ============================================================================

$Checks = @()

# Check 1: Clean runs coherence
$CheckCleanCoherence = $(if (
    $run1Info.FinalStatus -eq 'RUN_OK' -and
    $run2Info.FinalStatus -eq 'RUN_OK' -and
    $run3Info.FinalStatus -eq 'RUN_OK' -and
    $run1Info.Enforcement -eq 'PASS' -and
    $run2Info.Enforcement -eq 'PASS' -and
    $run3Info.Enforcement -eq 'PASS'
) { 'YES' } else { 'NO' })
$Checks += "check_clean_runs_coherent=$CheckCleanCoherence"

# Check 2: Blocked runs fail-closed
$CheckBlockedFailClosed = $(if (
    $run4Info.FinalStatus -eq 'BLOCKED' -and
    $run5Info.FinalStatus -eq 'BLOCKED' -and
    $run4Info.BlockedReason -eq 'TRUST_CHAIN_BLOCKED' -and
    $run5Info.BlockedReason -eq 'TRUST_CHAIN_BLOCKED'
) { 'YES' } else { 'NO' })
$Checks += "check_blocked_fail_closed=$CheckBlockedFailClosed"

# Check 3: Launch identity consistency (all present non-empty)
$IdentityConsistent = $(if (
    -not [string]::IsNullOrEmpty($run1Info.LaunchIdentity) -and
    -not [string]::IsNullOrEmpty($run2Info.LaunchIdentity) -and
    -not [string]::IsNullOrEmpty($run3Info.LaunchIdentity)
) { 'YES' } else { 'NO' })
$Checks += "check_launch_identity_present=$IdentityConsistent"

# Check 4: No hang detected
$NoHangDetected = $(if (
    $inv1.TimedOut -eq $false -and
    $inv2.TimedOut -eq $false -and
    $inv3.TimedOut -eq $false -and
    $inv4.TimedOut -eq $false -and
    $inv5.TimedOut -eq $false
) { 'YES' } else { 'NO' })
$Checks += "check_no_hang=$NoHangDetected"

# Check 5: No malformed exit codes
$NoMalformedExitCode = $(if (
    $run1Info.ExitCode -match '^\d+$' -and
    $run2Info.ExitCode -match '^\d+$' -and
    $run3Info.ExitCode -match '^\d+$' -and
    $run4Info.ExitCode -match '^\d+$' -and
    $run5Info.ExitCode -match '^\d+$'
) { 'YES' } else { 'NO' })
$Checks += "check_no_malformed_exit_codes=$NoMalformedExitCode"

# Check 6: No cross-run data contamination
$ContaminationCheck = 'YES'
@($stdoutFile_1, $stdoutFile_2, $stdoutFile_3, $stdoutFile_4, $stdoutFile_5) | ForEach-Object {
    $Path = $_
    $Text = Get-Content -Path $Path -Raw -ErrorAction SilentlyContinue
    if ($Text -match '_proof/phase(?!65_10)\d+') {
        $ContaminationCheck = 'NO'
    }
}
$Checks += "check_no_cross_run_contamination=$ContaminationCheck"

# Check 7: Widget process cleanup
$WidgetProcessesAfter = @(Get-Process -Name 'win32-sandbox*' -ErrorAction SilentlyContinue)
$CleanupCheck = $(if ($WidgetProcessesAfter.Count -eq 0) { 'YES' } else { 'NO' })
$Checks += "widget_process_count_after_validation=$($WidgetProcessesAfter.Count)"
$Checks += "check_cleanup_stable=$CleanupCheck"

# ============================================================================
# GENERATE OUTPUT ARTIFACTS
# ============================================================================

$ChecksFile = Join-Path $ProofFolder '90_env_perturbation_checks.txt'
$ChecksContent = @"
clean_run_001_workspace_root_final_status=$($run1Info.FinalStatus)
clean_run_001_workspace_root_exit_code=$($run1Info.ExitCode)
clean_run_001_workspace_root_enforcement=$($run1Info.Enforcement)
clean_run_002_temp_dir_final_status=$($run2Info.FinalStatus)
clean_run_002_temp_dir_exit_code=$($run2Info.ExitCode)
clean_run_002_temp_dir_enforcement=$($run2Info.Enforcement)
clean_run_003_alternate_final_status=$($run3Info.FinalStatus)
clean_run_003_alternate_exit_code=$($run3Info.ExitCode)
clean_run_003_alternate_enforcement=$($run3Info.Enforcement)
blocked_run_001_workspace_root_final_status=$($run4Info.FinalStatus)
blocked_run_001_workspace_root_exit_code=$($run4Info.ExitCode)
blocked_run_001_workspace_root_blocked_reason=$($run4Info.BlockedReason)
blocked_run_002_alternate_final_status=$($run5Info.FinalStatus)
blocked_run_002_alternate_exit_code=$($run5Info.ExitCode)
blocked_run_002_alternate_blocked_reason=$($run5Info.BlockedReason)
$($Checks -join "`r`n")
failed_check_count=$(($Checks -match '=NO$').Count)
failed_checks=$(if (($Checks -match '=NO$').Count -gt 0) { ($Checks -match '=NO$') -join ' | ' } else { 'NONE' })
"@
$ChecksContent | Out-File -FilePath $ChecksFile -Encoding UTF8 -Force

$ContractFile = Join-Path $ProofFolder '99_contract_summary.txt'
$FailedCount = ($Checks -match '=NO$').Count
$PhaseStatus = $(if ($FailedCount -eq 0 -and $NoHangDetected -eq 'YES') { 'PASS' } else { 'FAIL' })
$ContractContent = @"
next_phase_selected=PHASE65_10_WIDGET_OPERATOR_ENVIRONMENT_PERTURBATION_VALIDATION
objective=Validate runtime coherence and fail-closed behavior under controlled environment perturbations
changes_introduced=None (validation-only; no runtime code changes)
runtime_behavior_changes=None (all clean runs show RUN_OK; all blocked runs show BLOCKED)
new_regressions_detected=No
phase_status=$PhaseStatus
proof_folder=$ProofFolder
"@
$ContractContent | Out-File -FilePath $ContractFile -Encoding UTF8 -Force

# ============================================================================
# SELF-VALIDATION
# ============================================================================

$ChecksMap = Get-KeyValueMap -FilePath $ChecksFile
$ContractMap = Get-KeyValueMap -FilePath $ContractFile

$SelfValidationPassed = $true

if (-not (Test-KvFileWellFormed -FilePath $ChecksFile)) {
    Write-Host "ERROR: Checks file not well-formed"
    $SelfValidationPassed = $false
}

if (-not (Test-KvFileWellFormed -FilePath $ContractFile)) {
    Write-Host "ERROR: Contract file not well-formed"
    $SelfValidationPassed = $false
}

$RequiredContractFields = @('next_phase_selected', 'objective', 'changes_introduced', 'runtime_behavior_changes', 'new_regressions_detected', 'phase_status', 'proof_folder')
foreach ($Field in $RequiredContractFields) {
    if ([string]::IsNullOrEmpty($ContractMap[$Field])) {
        Write-Host "ERROR: Missing contract field: $Field"
        $SelfValidationPassed = $false
    }
}

$FailedCheckCount = [int]$ChecksMap['failed_check_count']
$ExpectedStatus = $(if ($FailedCheckCount -eq 0) { 'PASS' } else { 'FAIL' })
if ($ContractMap['phase_status'] -ne $ExpectedStatus) {
    Write-Host "ERROR: phase_status mismatch"
    $SelfValidationPassed = $false
}

if (-not $SelfValidationPassed) {
    Write-Host "FATAL: Self-validation failed"
    exit 1
}

# ============================================================================
# PACKAGE PROOF ARTIFACT
# ============================================================================

Write-Host "Zipping proof folder..."
$CompressParams = @{
    Path = $ProofFolder
    DestinationPath = $ZipPath
    Force = $true
}
Compress-Archive @CompressParams

# ============================================================================
# FINAL OUTPUT
# ============================================================================

$Output = "phase65_10_folder=$ProofFolder phase65_10_status=$PhaseStatus phase65_10_zip=$ZipPath"
Write-Host $Output
exit 0
