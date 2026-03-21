Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $root

$startUtc = (Get-Date).ToUniversalTime()
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path $root ("_proof\phase54a_runtime_enforcement_validation_final_" + $stamp)
New-Item -ItemType Directory -Path $pf -Force | Out-Null

function Invoke-LaunchCapture {
    param(
        [string]$Label,
        [string[]]$EnvPairs,
        [int]$TimeoutSec = 40
    )

    $stdoutPath = Join-Path $pf ("${Label}_stdout.txt")
    $stderrPath = Join-Path $pf ("${Label}_stderr.txt")

    $argList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', '.\\tools\\run_widget_sandbox.ps1',
        '-Config', 'Debug',
        '-PassArgs', '--sandbox-extension', '--extension-visual-baseline'
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = ($argList -join ' ')
    $psi.WorkingDirectory = $root
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    foreach ($pair in $EnvPairs) {
        $idx = $pair.IndexOf('=')
        if ($idx -gt 0) {
            $k = $pair.Substring(0, $idx)
            $v = $pair.Substring($idx + 1)
            $psi.Environment[$k] = $v
        }
    }

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()

    $stdout = $proc.StandardOutput.ReadToEndAsync()
    $stderr = $proc.StandardError.ReadToEndAsync()

    if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
        try { $proc.Kill() } catch {}
        $code = 124
    }
    else {
        $code = $proc.ExitCode
    }

    $stdout.Result | Set-Content -LiteralPath $stdoutPath -Encoding UTF8
    $stderr.Result | Set-Content -LiteralPath $stderrPath -Encoding UTF8

    return [pscustomobject]@{
        label = $Label
        exit_code = $code
        stdout = $stdoutPath
        stderr = $stderrPath
    }
}

$forensicsPath = Join-Path $pf 'forensics_runtime.log'
$valid = Invoke-LaunchCapture -Label '10_valid_launch' -EnvPairs @("NGK_FORENSICS_LOG=$forensicsPath")
$invalid = Invoke-LaunchCapture -Label '20_invalid_launch' -EnvPairs @('NGKS_BYPASS_GUARD=1')

$runtimeDirs = Get-ChildItem -LiteralPath (Join-Path $root '_proof') -Directory -Filter 'runtime_validation_*' |
    Where-Object { $_.LastWriteTimeUtc -ge $startUtc } |
    Sort-Object LastWriteTimeUtc

$runtimeDirs.FullName | Set-Content -LiteralPath (Join-Path $pf '30_runtime_validation_dirs.txt') -Encoding UTF8

foreach ($d in $runtimeDirs) {
    $name = $d.Name
    $status = Join-Path $d.FullName '01_status.txt'
    $vectors = Join-Path $d.FullName '04_detection_vectors.txt'
    if (Test-Path -LiteralPath $status) {
        Copy-Item -LiteralPath $status -Destination (Join-Path $pf ("${name}_01_status.txt")) -Force
    }
    if (Test-Path -LiteralPath $vectors) {
        Copy-Item -LiteralPath $vectors -Destination (Join-Path $pf ("${name}_04_detection_vectors.txt")) -Force
    }
}

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) {
    Remove-Item -LiteralPath $zip -Force
}
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -CompressionLevel Optimal

@(
    ('PF=' + $pf),
    ('ZIP=' + $zip),
    ('VALID_EXIT=' + $valid.exit_code),
    ('INVALID_EXIT=' + $invalid.exit_code),
    ('FORENSICS_LOG=' + $forensicsPath),
    ('RUNTIME_DIR_COUNT=' + @($runtimeDirs).Count)
) | Set-Content -LiteralPath (Join-Path $pf '99_summary.txt') -Encoding UTF8

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('VALID_EXIT=' + $valid.exit_code)
Write-Output ('INVALID_EXIT=' + $invalid.exit_code)
Write-Output ('RUNTIME_DIR_COUNT=' + @($runtimeDirs).Count)
