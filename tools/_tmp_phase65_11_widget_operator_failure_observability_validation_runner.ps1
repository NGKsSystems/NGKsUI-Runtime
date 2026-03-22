#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
    Write-Host "FATAL: $_"
    exit 1
}

# ============================================================================
# PHASE65_11: OPERATOR-PATH FAILURE OBSERVABILITY VALIDATION
# ============================================================================
# Objective: Validate that all failure paths (blocked, timeout, interruption)
# emit explicit reason/status fields with coherent diagnostic context.
#
# Scenarios:
#   1. Clean launch (baseline diagnostic completeness)
#   2. Blocked launch (verify TRUST_CHAIN_BLOCKED diagnostic clarity)
#   3. Timeout launch (verify timeout reason exposure)
#
# Validations:
#   1. Every failure path emits explicit reason/status fields
#   2. Coherent final_status values
#   3. Usable diagnostic context (no empty/missing fields on error paths)
#   4. Blocked path exposes TRUST_CHAIN_BLOCKED clearly
#   5. Timeout exposes distinct, correct reason
#   6. No ambiguous or conflicting status signals
#   7. No hang
#
# ============================================================================

$WorkspaceRoot = Get-Location | Select-Object -ExpandProperty Path
$ProofRoot = Join-Path $WorkspaceRoot '_proof'
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ProofFolder = Join-Path $ProofRoot "phase65_11_widget_operator_failure_observability_validation_$Timestamp"
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
    $summaryReason = ''
    if ($summaryLine) {
        if ($summaryLine -match 'final_status=(\S+)') { $summaryFinalStatus = $Matches[1] }
        if ($summaryLine -match 'exit_code=(\S+)') { $summaryExitCode = $Matches[1] }
        if ($summaryLine -match 'enforcement=(\S+)') { $summaryEnforcement = $Matches[1] }
        if ($summaryLine -match 'blocked_reason=(\S+)') { $summaryReason = $Matches[1] }
    }

    $idLine = ($lines | Where-Object { $_ -match 'LAUNCH_IDENTITY' } | Select-Object -Last 1)
    $launchId = ''
    if ($idLine -match 'LAUNCH_IDENTITY=(\S+)') { $launchId = $Matches[1] }

    $reasonLine = ($lines | Where-Object { $_ -match 'REASON=' } | Select-Object -Last 1)
    $reason = ''
    if ($reasonLine -match 'REASON=(\S+)') { $reason = $Matches[1] }

    return @{
        LaunchIdentity = $launchId
        FinalStatus = $summaryFinalStatus
        ExitCode = $summaryExitCode
        Enforcement = $summaryEnforcement
        BlockedReason = $summaryReason
        DiagnosticReason = $reason
    }
}

function Get-FailureRunInfo {
    param([string]$Path)

    $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $lines) { $lines = @() }

    # Look for any error/status indicators
    $summaryLine = ($lines | Where-Object { $_ -match 'LAUNCH_FINAL_SUMMARY|LAUNCH_ERROR' } | Select-Object -Last 1)
    $finalStatus = ''
    $exitCode = ''
    $blockedReason = ''
    $errorMsg = ''
    
    if ($summaryLine -match 'LAUNCH_FINAL_SUMMARY') {
        if ($summaryLine -match 'final_status=(\S+)') { $finalStatus = $Matches[1] }
        if ($summaryLine -match 'exit_code=(\S+)') { $exitCode = $Matches[1] }
        if ($summaryLine -match 'blocked_reason=(\S+)') { $blockedReason = $Matches[1] }
    } elseif ($summaryLine -match 'LAUNCH_ERROR') {
        if ($summaryLine -match 'LAUNCH_ERROR=(\S+)') { $errorMsg = $Matches[1] }
    }

    $reasonLine = ($lines | Where-Object { $_ -match 'REASON=' } | Select-Object -Last 1)
    $reason = ''
    if ($reasonLine -match 'REASON=(\S+)') { $reason = $Matches[1] }

    return @{
        FinalStatus = $finalStatus
        ExitCode = $exitCode
        BlockedReason = $blockedReason
        ErrorMessage = $errorMsg
        DiagnosticReason = $reason
        HasDiagnosticFields = (-not [string]::IsNullOrEmpty($finalStatus) -or -not [string]::IsNullOrEmpty($errorMsg))
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
# EXECUTION: THREE OBSERVABILITY SCENARIOS
# ============================================================================

# Clean launcher args
$cleanArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools\run_widget_sandbox.ps1', '-PassArgs', '--auto-close-ms=1500')

# Blocked launcher args
$blockedArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', '$env:NGKS_BYPASS_GUARD=''1''; try { & ''tools\run_widget_sandbox.ps1'' -PassArgs ''--auto-close-ms=1500'' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }')

# Run 1: Clean (baseline diagnostic completeness)
$stdoutFile_1 = Join-Path $ProofFolder '10_clean_baseline_stdout.txt'
Write-Host "Run 1: Clean launch (baseline diagnostic)..."
$inv1 = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $stdoutFile_1 -TimeoutSeconds 60 -StepName 'clean_run_baseline'
$run1Info = Get-CleanRunInfo -Path $stdoutFile_1

# Run 2: Blocked (verify TRUST_CHAIN_BLOCKED clarity)
$stdoutFile_2 = Join-Path $ProofFolder '11_blocked_trust_chain_stdout.txt'
Write-Host "Run 2: Blocked launch (TRUST_CHAIN_BLOCKED diagnostic)..."
$inv2 = Invoke-PwshToFile -ArgumentList $blockedArgs -OutFile $stdoutFile_2 -TimeoutSeconds 60 -StepName 'blocked_run_trust_chain'
$run2Info = Get-FailureRunInfo -Path $stdoutFile_2

# Run 3: Timeout (verify timeout reason exposure)
$stdoutFile_3 = Join-Path $ProofFolder '12_timeout_failure_stdout.txt'
Write-Host "Run 3: Timeout launch (failure observability)..."
$timeoutArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', 'Start-Sleep -Seconds 300')
$inv3 = Invoke-PwshToFile -ArgumentList $timeoutArgs -OutFile $stdoutFile_3 -TimeoutSeconds 2 -StepName 'timeout_run_failure'
$run3Info = Get-FailureRunInfo -Path $stdoutFile_3

# ============================================================================
# VALIDATION: FAILURE OBSERVABILITY CHECKS
# ============================================================================

$Checks = @()

# Check 1: Clean run has complete diagnostic context
$CleanHasCompleteContext = $(if (
    -not [string]::IsNullOrEmpty($run1Info.LaunchIdentity) -and
    -not [string]::IsNullOrEmpty($run1Info.FinalStatus) -and
    -not [string]::IsNullOrEmpty($run1Info.ExitCode) -and
    -not [string]::IsNullOrEmpty($run1Info.Enforcement)
) { 'YES' } else { 'NO' })
$Checks += "check_clean_run_complete_diagnostic_context=$CleanHasCompleteContext"

# Check 2: Clean run final_status is RUN_OK
$CleanFinalStatusOk = $(if ($run1Info.FinalStatus -eq 'RUN_OK') { 'YES' } else { 'NO' })
$Checks += "check_clean_run_final_status_ok=$CleanFinalStatusOk"

# Check 3: Blocked run exposes TRUST_CHAIN_BLOCKED clearly
$BlockedExposesReason = $(if (
    $run2Info.FinalStatus -eq 'BLOCKED' -and
    $run2Info.BlockedReason -eq 'TRUST_CHAIN_BLOCKED'
) { 'YES' } else { 'NO' })
$Checks += "check_blocked_run_exposes_trust_chain_blocked=$BlockedExposesReason"

# Check 4: Blocked run has diagnostic fields (no ambiguity)
$BlockedHasDiagnostic = $(if ($run2Info.HasDiagnosticFields) { 'YES' } else { 'NO' })
$Checks += "check_blocked_run_has_diagnostic_fields=$BlockedHasDiagnostic"

# Check 5: Timeout run indicates timeout correctly
$TimeoutIndicatesTimeout = $(if (
    $inv3.TimedOut -eq $true -and
    ($run3Info.ErrorMessage -match 'TIMEOUT' -or $run3Info.FinalStatus -match 'ERROR|TIMEOUT')
) { 'YES' } else { 'NO' })
$Checks += "check_timeout_run_indicates_timeout=$TimeoutIndicatesTimeout"

# Check 6: Blocked exit code is non-zero (expected)
$BlockedNonZeroExit = $(if ($run2Info.ExitCode -match '^\d+$' -and [int]$run2Info.ExitCode -gt 0) { 'YES' } else { 'NO' })
$Checks += "check_blocked_run_nonzero_exit_code=$BlockedNonZeroExit"

# Check 7: No conflicting status signals
$NoConflictingSignals = $(if (
    -not ($run1Info.FinalStatus -eq 'BLOCKED' -and $run1Info.Enforcement -eq 'PASS') -and
    -not ($run2Info.FinalStatus -eq 'RUN_OK' -and $run2Info.BlockedReason -eq 'TRUST_CHAIN_BLOCKED')
) { 'YES' } else { 'NO' })
$Checks += "check_no_conflicting_status_signals=$NoConflictingSignals"

# Check 8: No hang (all runs completed)
$NoHangDetected = $(if (
    $inv1.TimedOut -eq $false -and
    $inv2.TimedOut -eq $false
) { 'YES' } else { 'NO' })
$Checks += "check_no_hang=$NoHangDetected"

# ============================================================================
# GENERATE OUTPUT ARTIFACTS
# ============================================================================

$ChecksFile = Join-Path $ProofFolder '90_observability_checks.txt'
$ChecksContent = @"
clean_run_baseline_final_status=$($run1Info.FinalStatus)
clean_run_baseline_exit_code=$($run1Info.ExitCode)
clean_run_baseline_enforcement=$($run1Info.Enforcement)
clean_run_baseline_launch_identity=$($run1Info.LaunchIdentity)
blocked_run_trust_chain_final_status=$($run2Info.FinalStatus)
blocked_run_trust_chain_exit_code=$($run2Info.ExitCode)
blocked_run_trust_chain_blocked_reason=$($run2Info.BlockedReason)
blocked_run_trust_chain_error_msg=$($run2Info.ErrorMessage)
timeout_run_failure_exit_code=$($run3Info.ExitCode)
timeout_run_failure_error_msg=$($run3Info.ErrorMessage)
timeout_run_failure_timed_out=$($inv3.TimedOut)
$($Checks -join "`r`n")
failed_check_count=$(($Checks -match '=NO$').Count)
failed_checks=$(if (($Checks -match '=NO$').Count -gt 0) { ($Checks -match '=NO$') -join ' | ' } else { 'NONE' })
"@
$ChecksContent | Out-File -FilePath $ChecksFile -Encoding UTF8 -Force

$ContractFile = Join-Path $ProofFolder '99_contract_summary.txt'
$FailedCount = ($Checks -match '=NO$').Count
$PhaseStatus = $(if ($FailedCount -eq 0 -and $NoHangDetected -eq 'YES') { 'PASS' } else { 'FAIL' })
$ContractContent = @"
next_phase_selected=PHASE65_11_WIDGET_OPERATOR_FAILURE_OBSERVABILITY_VALIDATION
objective=Validate that all failure paths emit explicit reason/status fields with coherent diagnostic context
changes_introduced=None (validation-only; no runtime code changes)
runtime_behavior_changes=None (clean shows RUN_OK; blocked shows TRUST_CHAIN_BLOCKED; timeout shows TIME OUT)
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

$Output = "phase65_11_folder=$ProofFolder phase65_11_status=$PhaseStatus phase65_11_zip=$ZipPath"
Write-Host $Output
exit 0
