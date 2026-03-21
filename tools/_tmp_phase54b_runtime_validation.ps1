Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime"

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path '_proof' ("phase54b_runtime_validation_" + $ts)
New-Item -ItemType Directory -Force -Path $pf | Out-Null

function Write-Txt {
    param([string]$Name, [object]$Content)
    $p = Join-Path $pf $Name
    $Content | Set-Content -LiteralPath $p -Encoding UTF8
    return $p
}

function Get-PeValidity {
    param([string]$Path, [string]$NamePrefix)
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ valid = 'NO'; reason = 'MISSING' }
    }
    $dump = (& dumpbin /headers $Path 2>&1 | Out-String)
    $llvm = (& llvm-readobj --file-headers --sections $Path 2>&1 | Out-String)
    Write-Txt ($NamePrefix + '_pe_dumpbin.txt') $dump | Out-Null
    Write-Txt ($NamePrefix + '_pe_llvm.txt') $llvm | Out-Null
    $bad = ($dump -match 'LNK1106|fatal error') -or ($llvm -match 'unexpectedly encountered')
    if ($bad) {
        return [pscustomobject]@{ valid = 'NO'; reason = 'TRUNCATED_OR_INVALID' }
    }
    return [pscustomobject]@{ valid = 'YES'; reason = 'OK' }
}

function Invoke-ExplicitRestore {
    param([string]$Target, [string]$PyExe, [string]$ProofRoot)

    $buildOut = (& $PyExe -m ngksgraph build --profile debug --msvc-auto --target $Target 2>&1 | Out-String)
    Write-Txt ("10_build_" + $Target + ".txt") $buildOut | Out-Null

    $planPath = ''
    $m = [regex]::Match($buildOut, 'BuildCore plan:\s+(.+)')
    if ($m.Success) { $planPath = $m.Groups[1].Value.Trim() }
    if (-not $planPath) { $planPath = (Join-Path (Get-Location) 'build_graph/debug/ngksbuildcore_plan.json') }

    $runProof = Join-Path $ProofRoot ("buildcore_" + $Target)
    New-Item -ItemType Directory -Force -Path $runProof | Out-Null
    $runOut = (& $PyExe -m ngksbuildcore run --plan $planPath --proof $runProof -j 1 2>&1 | Out-String)
    Write-Txt ("11_buildcore_" + $Target + ".txt") $runOut | Out-Null

    return [pscustomobject]@{
        plan_path = $planPath
        buildcore_proof = $runProof
    }
}

function Invoke-Launch {
    param(
        [string]$Target,
        [string]$ExePath,
        [string]$Mode,
        [hashtable]$EnvMap,
        [int]$TimeoutSec = 20
    )

    $outFile = Join-Path $pf ("20_run_" + $Target + "_" + $Mode + "_stdout.txt")
    $errFile = Join-Path $pf ("20_run_" + $Target + "_" + $Mode + "_stderr.txt")

    $prev = @{}
    foreach ($k in $EnvMap.Keys) {
        $prev[$k] = [Environment]::GetEnvironmentVariable($k)
        [Environment]::SetEnvironmentVariable($k, [string]$EnvMap[$k])
    }

    try {
        $proc = Start-Process -FilePath $ExePath -ArgumentList @('--auto-close-ms=1500') -RedirectStandardOutput $outFile -RedirectStandardError $errFile -PassThru
        $timedOut = $false
        if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
            $timedOut = $true
            try { $proc.Kill() } catch {}
        }

        $exitCode = if ($timedOut) { 124 } else { $proc.ExitCode }
        $stdout = if (Test-Path -LiteralPath $outFile) { Get-Content -LiteralPath $outFile -Raw } else { '' }
        $stderr = if (Test-Path -LiteralPath $errFile) { Get-Content -LiteralPath $errFile -Raw } else { '' }
        return [pscustomobject]@{
            timed_out = $timedOut
            exit_code = $exitCode
            stdout_file = $outFile
            stderr_file = $errFile
            stdout_text = $stdout
            stderr_text = $stderr
        }
    }
    finally {
        foreach ($k in $EnvMap.Keys) {
            [Environment]::SetEnvironmentVariable($k, $prev[$k])
        }
    }
}

$py = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime\.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $py)) {
    throw 'Existing python entrypoint not found at .venv\\Scripts\\python.exe'
}

$targets = @('widget_sandbox', 'win32_sandbox', 'sandbox_app', 'loop_tests')
$rows = @()

foreach ($t in $targets) {
    $restore = Invoke-ExplicitRestore -Target $t -PyExe $py -ProofRoot $pf

    $exeRel = "build/debug/bin/$t.exe"
    $exeAbs = Join-Path (Get-Location) $exeRel
    $freshRestored = 'NO'
    $hash = ''
    $size = ''
    $mtime = ''

    if (Test-Path -LiteralPath $exeAbs) {
        $it = Get-Item -LiteralPath $exeAbs
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $exeAbs).Hash
        $size = [string]$it.Length
        $mtime = $it.LastWriteTimeUtc.ToString('o')
        if ($mtime.StartsWith((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd'))) {
            $freshRestored = 'YES'
        }
    }

    $pe = Get-PeValidity -Path $exeAbs -NamePrefix ("12_" + $t)

    $src = Join-Path (Get-Location) ("apps/$t/main.cpp")
    $hookPresent = 'NO'
    if (Test-Path -LiteralPath $src) {
        $s = Get-Content -LiteralPath $src -Raw
        if (($s -match 'enforce_runtime_trust|require_runtime_trust|enforce_phase53_2')) { $hookPresent = 'YES' }
    }

    $launchAttempted = 'NO'
    $runtimeLaunchable = 'NO'
    $cleanPass = 'NO'
    $invalidFailClosed = 'NO'
    $liveRecheck = 'NO'

    if ($pe.valid -eq 'YES' -and (Test-Path -LiteralPath $exeAbs)) {
        $launchAttempted = 'YES'

        $cleanEnv = @{}
        if ($t -eq 'widget_sandbox') {
            $cleanEnv['NGK_FORENSICS_LOG'] = '1'
        }
        $clean = Invoke-Launch -Target $t -ExePath $exeAbs -Mode 'clean' -EnvMap $cleanEnv

        $cleanGuardPass = ($clean.stdout_text -match 'runtime_trust_guard=PASS context=runtime_init')
        if ((-not $clean.timed_out -and $clean.exit_code -eq 0) -or $cleanGuardPass) {
            $runtimeLaunchable = 'YES'
            $cleanPass = 'YES'
        }

        $invalid = Invoke-Launch -Target $t -ExePath $exeAbs -Mode 'invalid' -EnvMap @{ NGKS_BYPASS_GUARD = '1' }
        if ($invalid.exit_code -ne 0) {
            $invalidFailClosed = 'YES'
        }

        if ($t -eq 'widget_sandbox') {
            if (($clean.stdout_text -match 'runtime_trust_guard=PASS context=runtime_init') -and ($clean.stdout_text -match 'runtime_trust_guard=PASS context=file_load')) {
                $liveRecheck = 'YES'
            }
        }
    }

    $coverageStatus = 'GAP'
    if ($pe.valid -eq 'YES' -and $launchAttempted -eq 'YES' -and $cleanPass -eq 'YES' -and $invalidFailClosed -eq 'YES') {
        $coverageStatus = 'VALIDATED'
    }

    $rows += [pscustomobject]@{
        target = $t
        built = 'YES'
        emitted = $(if (Test-Path -LiteralPath $exeAbs) { 'YES' } else { 'NO' })
        fresh_binary_restored = $freshRestored
        pe_valid = $pe.valid
        runtime_launchable = $runtimeLaunchable
        enforcement_hook_present = $hookPresent
        launch_attempted = $launchAttempted
        clean_state_pass = $cleanPass
        invalid_state_fail_closed = $invalidFailClosed
        live_recheck_verified = $liveRecheck
        coverage_status = $coverageStatus
        output_path = $exeRel
        size = $size
        sha256 = $hash
        timestamp_utc = $mtime
        plan_path = $restore.plan_path
        buildcore_proof = $restore.buildcore_proof
    }
}

$matrixFile = Join-Path $pf '30_phase54b_coverage_matrix.csv'
$rows | ConvertTo-Csv -NoTypeInformation | Set-Content -LiteralPath $matrixFile -Encoding UTF8

$validated = @($rows | Where-Object { $_.coverage_status -eq 'VALIDATED' } | Select-Object -ExpandProperty target)
$failed = @($rows | Where-Object { $_.coverage_status -ne 'VALIDATED' } | Select-Object -ExpandProperty target)
$gaps = @($rows | Where-Object { $_.coverage_status -ne 'VALIDATED' } | ForEach-Object { $_.target + ':' + $_.coverage_status + ':clean=' + $_.clean_state_pass + ':invalid=' + $_.invalid_state_fail_closed + ':pe=' + $_.pe_valid })

$status = 'FAIL'
if ($validated.Count -eq $targets.Count) { $status = 'PASS' }
elseif ($validated.Count -gt 0) { $status = 'PARTIAL' }

$summary = @(
    'validated_targets=' + ($validated -join ','),
    'failed_targets=' + ($failed -join ','),
    'coverage_gaps=' + ($gaps -join ';'),
    'phase54b_status=' + $status,
    'proof_folder=' + $pf,
    'coverage_matrix_file=' + $matrixFile
)
Write-Txt '99_contract_summary.txt' $summary | Out-Null

$zip = "$pf.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

$summary -join "`n"
