Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime"

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path '_proof' ("phase54c_runtime_stability_" + $ts)
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

function Invoke-LaunchCapture {
    param(
        [string]$Target,
        [string]$Mode,
        [string]$ExePath,
        [string[]]$Args,
        [int]$DwellSeconds,
        [int]$MaxSeconds,
        [hashtable]$EnvMap
    )

    $stdoutFile = Join-Path $pf ("10_" + $Target + "_" + $Mode + "_stdout.txt")
    $stderrFile = Join-Path $pf ("10_" + $Target + "_" + $Mode + "_stderr.txt")

    $prev = Set-EnvMap -Map $EnvMap
    try {
        $proc = Start-Process -FilePath $ExePath -ArgumentList $Args -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile -PassThru
        $startUtc = (Get-Date).ToUniversalTime()

        Start-Sleep -Seconds $DwellSeconds
        $runningAtDwell = -not $proc.HasExited

        $timedOut = $false
        if (-not $proc.WaitForExit($MaxSeconds * 1000)) {
            $timedOut = $true
            try { $proc.Kill() } catch {}
        }

        $exitCode = if ($timedOut) { 124 } else { $proc.ExitCode }
        $endUtc = (Get-Date).ToUniversalTime()
        $stdoutText = if (Test-Path -LiteralPath $stdoutFile) { Get-Content -LiteralPath $stdoutFile -Raw } else { '' }
        $stderrText = if (Test-Path -LiteralPath $stderrFile) { Get-Content -LiteralPath $stderrFile -Raw } else { '' }

        return [pscustomobject]@{
            start_utc = $startUtc.ToString('o')
            end_utc = $endUtc.ToString('o')
            running_at_dwell = $runningAtDwell
            timed_out = $timedOut
            exit_code = $exitCode
            stdout_file = $stdoutFile
            stderr_file = $stderrFile
            stdout_text = $stdoutText
            stderr_text = $stderrText
        }
    }
    finally {
        Restore-EnvMap -Prev $prev
    }
}

$targets = @('widget_sandbox', 'win32_sandbox', 'sandbox_app', 'loop_tests')
$liveRecheckApplicable = @('widget_sandbox')
$shortLifecycleTargets = @('sandbox_app', 'loop_tests')
$rows = @()

foreach ($t in $targets) {
    $exe = Join-Path (Get-Location) ("build/debug/bin/" + $t + ".exe")
    if (-not (Test-Path -LiteralPath $exe)) {
        $rows += [pscustomobject]@{
            target = $t
            clean_launch = 'FAIL'
            sustained_run = 'FAIL'
            invalid_fail_closed = 'FAIL'
            live_recheck = 'FAIL'
            intermittent_issues = 'MISSING_BINARY'
            final_stability_status = 'UNSTABLE'
        }
        continue
    }

    $cleanEnv = @{
        NGKS_BYPASS_GUARD = $null
    }
    if ($t -eq 'widget_sandbox') {
        $cleanEnv['NGK_FORENSICS_LOG'] = '1'
    }

    $clean = Invoke-LaunchCapture -Target $t -Mode 'clean' -ExePath $exe -Args @('--auto-close-ms=45000') -DwellSeconds 12 -MaxSeconds 70 -EnvMap $cleanEnv

    $cleanLaunchPass = 'FAIL'
    $sustainedPass = 'FAIL'

    $guardPassSeen = ($clean.stdout_text -match 'runtime_trust_guard=PASS context=runtime_init')
    if ($guardPassSeen) {
        $cleanLaunchPass = 'PASS'
    }
    if ($clean.running_at_dwell) {
        $sustainedPass = 'PASS'
    }

    $invalid = Invoke-LaunchCapture -Target $t -Mode 'invalid' -ExePath $exe -Args @('--auto-close-ms=3000') -DwellSeconds 2 -MaxSeconds 15 -EnvMap @{ NGKS_BYPASS_GUARD = '1' }

    $invalidPass = 'FAIL'
    $blockedSignal = ($invalid.stdout_text -match 'runtime_trust_guard=FAIL|runtime_trust_blocked|GATE=FAIL') -or ($invalid.stderr_text -match 'runtime_trust_guard=FAIL|runtime_trust_blocked|GATE=FAIL')
    if (($invalid.exit_code -ne 0) -or $blockedSignal) {
        $invalidPass = 'PASS'
    }

    $liveRecheck = 'N_A'
    if ($liveRecheckApplicable -contains $t) {
        $liveRecheck = 'FAIL'
        $runtimeInitSeen = ($clean.stdout_text -match 'runtime_trust_guard=PASS context=runtime_init')
        $secondContextSeen = ($clean.stdout_text -match 'runtime_trust_guard=PASS context=file_load|runtime_trust_guard=PASS context=execution_pipeline|runtime_trust_guard=PASS context=plugin_load|runtime_trust_guard=PASS context=save_export')
        if ($runtimeInitSeen -and $secondContextSeen) {
            $liveRecheck = 'PASS'
        }
    }

    $issues = @()
    if ($clean.stderr_text -match 'fatal|exception|crash|access violation') {
        $issues += 'stderr_runtime_anomaly'
    }
    if ($clean.timed_out) {
        $issues += 'clean_run_timeout'
    }
    if ($invalid.timed_out) {
        $issues += 'invalid_run_timeout'
    }
    $issueText = if ($issues.Count -gt 0) { ($issues -join ',') } else { 'NONE' }

    $stable = $true
    if ($cleanLaunchPass -ne 'PASS') { $stable = $false }
    if ($sustainedPass -ne 'PASS') {
        # sandbox_app and loop_tests are expected finite-run targets; clean exit=0 is acceptable stability signal.
        $shortLifecycleOkay = (($shortLifecycleTargets -contains $t) -and (-not $clean.timed_out) -and ($clean.exit_code -eq 0))
        if (-not $shortLifecycleOkay) { $stable = $false }
    }
    if ($invalidPass -ne 'PASS') { $stable = $false }
    if (($liveRecheckApplicable -contains $t) -and ($liveRecheck -ne 'PASS')) { $stable = $false }

    $rows += [pscustomobject]@{
        target = $t
        clean_launch = $cleanLaunchPass
        sustained_run = $sustainedPass
        invalid_fail_closed = $invalidPass
        live_recheck = $liveRecheck
        intermittent_issues = $issueText
        final_stability_status = $(if ($stable) { 'STABLE' } else { 'UNSTABLE' })
    }

    $detail = @(
        "target=$t",
        "clean_start_utc=$($clean.start_utc)",
        "clean_end_utc=$($clean.end_utc)",
        "clean_exit_code=$($clean.exit_code)",
        "clean_running_at_dwell=$($clean.running_at_dwell)",
        "invalid_start_utc=$($invalid.start_utc)",
        "invalid_end_utc=$($invalid.end_utc)",
        "invalid_exit_code=$($invalid.exit_code)",
        "invalid_running_at_dwell=$($invalid.running_at_dwell)",
        "clean_stdout=$($clean.stdout_file)",
        "clean_stderr=$($clean.stderr_file)",
        "invalid_stdout=$($invalid.stdout_file)",
        "invalid_stderr=$($invalid.stderr_file)"
    )
    Write-Txt ("20_" + $t + "_timing_and_exit.txt") $detail | Out-Null
}

$matrix = Join-Path $pf '30_phase54c_stability_matrix.csv'
$rows | ConvertTo-Csv -NoTypeInformation | Set-Content -LiteralPath $matrix -Encoding UTF8

$stableTargets = @($rows | Where-Object { $_.final_stability_status -eq 'STABLE' } | Select-Object -ExpandProperty target)
$unstableTargets = @($rows | Where-Object { $_.final_stability_status -eq 'UNSTABLE' } | Select-Object -ExpandProperty target)
$intermittent = @($rows | Where-Object { $_.intermittent_issues -ne 'NONE' } | ForEach-Object { $_.target + ':' + $_.intermittent_issues })
$regressionCount = $unstableTargets.Count

$status = 'PASS'
if ($stableTargets.Count -eq 0) {
    $status = 'FAIL'
} elseif ($unstableTargets.Count -gt 0) {
    $status = 'PARTIAL'
}

$summary = @(
    'stable_targets=' + ($stableTargets -join ','),
    'unstable_targets=' + ($unstableTargets -join ','),
    'intermittent_failures=' + ($intermittent -join ';'),
    'runtime_regression_count=' + $regressionCount,
    'phase54c_status=' + $status,
    'proof_folder=' + $pf,
    'stability_matrix=' + $matrix
)
Write-Txt '99_contract_summary.txt' $summary | Out-Null

$zip = "$pf.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

$summary -join "`n"
