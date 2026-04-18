param(
    [string]$RepoRoot = "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime",
    [int]$AliveSeconds = 10
)

$ErrorActionPreference = "Stop"

function Ensure-Dir($path) {
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

$proofDir = Join-Path $RepoRoot "_proof\run_smoke"
Ensure-Dir $proofDir

$stdoutFile = Join-Path $proofDir "runner_stdout.txt"
$stderrFile = Join-Path $proofDir "runner_stderr.txt"

"" | Set-Content $stdoutFile
"" | Set-Content $stderrFile

try {
    Set-Location $RepoRoot

    $exe = Join-Path $RepoRoot "build\debug\bin\desktop_file_tool.exe"
    if (-not (Test-Path $exe)) {
        throw "Missing exe: $exe"
    }

    $proc = Start-Process -FilePath $exe `
        -WorkingDirectory $RepoRoot `
        -RedirectStandardOutput $stdoutFile `
        -RedirectStandardError $stderrFile `
        -PassThru

    Start-Sleep -Seconds $AliveSeconds

    if ($proc.HasExited) {
        throw "App exited too early with code $($proc.ExitCode)"
    }

    $null = $proc.CloseMainWindow()
    Start-Sleep -Seconds 3

    if (-not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }

    Write-Host "PASS"
    exit 0
}
catch {
    $_ | Out-String | Add-Content $stderrFile
    Write-Host "FAIL"
    exit 1
}