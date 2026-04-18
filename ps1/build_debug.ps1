param(
    [string]$RepoRoot = "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Run-Step {
    param(
        [string]$Name,
        [scriptblock]$Action
    )
    Write-Host "[build_debug] $Name"
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE"
    }
}

try {
    if (-not (Test-Path -LiteralPath $RepoRoot)) {
        throw "Repo root not found: $RepoRoot"
    }

    Set-Location -LiteralPath $RepoRoot

    $proofDir   = Join-Path $RepoRoot "_proof\build_debug"
    $stdoutFile = Join-Path $proofDir "build_stdout.txt"
    $stderrFile = Join-Path $proofDir "build_stderr.txt"

    Ensure-Dir $proofDir
    "" | Set-Content -LiteralPath $stdoutFile
    "" | Set-Content -LiteralPath $stderrFile

    $pythonExe = Join-Path $RepoRoot ".venv\Scripts\python.exe"
    if (-not (Test-Path -LiteralPath $pythonExe)) {
        throw "Missing .venv python: $pythonExe"
    }

    $enterMsvc = Join-Path $RepoRoot "tools\enter_msvc_env.ps1"
    if (-not (Test-Path -LiteralPath $enterMsvc)) {
        throw "Missing MSVC env script: $enterMsvc"
    }

    if (-not (Test-Path -LiteralPath "apps\desktop_file_tool\main.cpp")) {
        throw "Missing apps\desktop_file_tool\main.cpp"
    }

    Run-Step "Generate debug build plan" {
        & $pythonExe -m ngksgraph build --profile debug --msvc-auto --target desktop_file_tool `
            1>> $stdoutFile 2>> $stderrFile
    }

    $planPath = Join-Path $RepoRoot "build_graph\debug\ngksbuildcore_plan.json"
    if (-not (Test-Path -LiteralPath $planPath)) {
        throw "Missing build plan: $planPath"
    }

    . $enterMsvc *> $null

    $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json

    $engineCompileNodes = @($plan.nodes | Where-Object { $_.desc -like "Compile engine/* for engine" })
    $appCompileNode     = @($plan.nodes | Where-Object { $_.desc -eq "Compile apps/desktop_file_tool/main.cpp for desktop_file_tool" })[0]
    $engineLinkNode     = @($plan.nodes | Where-Object { $_.desc -eq "Link engine" })[0]
    $appLinkNode        = @($plan.nodes | Where-Object { $_.desc -eq "Link desktop_file_tool" })[0]

    if (-not $appCompileNode) { throw "App compile node not found in build plan." }
    if (-not $engineLinkNode) { throw "Engine link node not found in build plan." }
    if (-not $appLinkNode)    { throw "App link node not found in build plan." }

    foreach ($node in $engineCompileNodes) {
        Run-Step $node.desc {
            cmd /c $node.cmd 1>> $stdoutFile 2>> $stderrFile
        }
    }

    Run-Step $appCompileNode.desc {
        cmd /c $appCompileNode.cmd 1>> $stdoutFile 2>> $stderrFile
    }

    Run-Step $engineLinkNode.desc {
        cmd /c $engineLinkNode.cmd 1>> $stdoutFile 2>> $stderrFile
    }

    Run-Step $appLinkNode.desc {
        cmd /c $appLinkNode.cmd 1>> $stdoutFile 2>> $stderrFile
    }

    $exePath = Join-Path $RepoRoot "build\debug\bin\desktop_file_tool.exe"
    if (-not (Test-Path -LiteralPath $exePath)) {
        throw "Build finished but exe missing: $exePath"
    }

    Write-Host "PASS"
    exit 0
}
catch {
    $msg = $_ | Out-String
    Add-Content -LiteralPath (Join-Path $RepoRoot "_proof\build_debug\build_stderr.txt") -Value $msg
    Write-Host "FAIL"
    Write-Host $msg
    exit 1
}