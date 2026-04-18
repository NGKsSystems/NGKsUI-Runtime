$RepoRoot = "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime"
$TimeoutSeconds = 3600
$ErrorActionPreference = "Stop"

function Ensure-Dir($path) {
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

function Ensure-ParentDirForCommandOutput {
    param([string]$CommandLine)

    if ($CommandLine -match '/Fo"([^"]+)"') {
        $objPath = $matches[1]
        $objDir = Split-Path $objPath -Parent
        if ($objDir) { Ensure-Dir $objDir }
    }

    if ($CommandLine -match '/OUT:"([^"]+)"') {
        $outPath = $matches[1]
        $outDir = Split-Path $outPath -Parent
        if ($outDir) { Ensure-Dir $outDir }
    }
}

$proofDir = Join-Path $RepoRoot "_proof\run_gate"
Ensure-Dir $proofDir

$stdoutFile = Join-Path $proofDir "runner_stdout.txt"
$stderrFile = Join-Path $proofDir "runner_stderr.txt"

"" | Set-Content -LiteralPath $stdoutFile
"" | Set-Content -LiteralPath $stderrFile

try {
    Set-Location -LiteralPath $RepoRoot

    $exe = Join-Path $RepoRoot "_artifacts\export\desktop_file_tool_bundle\desktop_file_tool.exe"

    if (-not (Test-Path -LiteralPath $exe)) {
        $pythonExe = Join-Path $RepoRoot ".venv\Scripts\python.exe"
        if (-not (Test-Path -LiteralPath $pythonExe)) {
            throw "Missing .venv python: $pythonExe"
        }

        $enterMsvc = Join-Path $RepoRoot "tools\enter_msvc_env.ps1"
        if (-not (Test-Path -LiteralPath $enterMsvc)) {
            throw "Missing MSVC env script: $enterMsvc"
        }

        & $pythonExe -m ngksgraph build --profile debug --msvc-auto --target desktop_file_tool `
            1>> $stdoutFile 2>> $stderrFile

        if ($LASTEXITCODE -ne 0) {
            throw "ngksgraph build plan generation failed with exit code $LASTEXITCODE"
        }

        $planPath = Join-Path $RepoRoot "build_graph\debug\ngksbuildcore_plan.json"
        if (-not (Test-Path -LiteralPath $planPath)) {
            throw "Missing build plan: $planPath"
        }

        . $enterMsvc *> $null

        $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
        foreach ($node in $plan.nodes) {
            if (-not $node.cmd) { continue }
            Ensure-ParentDirForCommandOutput $node.cmd
            cmd /c $node.cmd 1>> $stdoutFile 2>> $stderrFile
            if ($LASTEXITCODE -ne 0) {
                throw "Build step failed: $($node.desc) (exit $LASTEXITCODE)"
            }
        }

        if (-not (Test-Path -LiteralPath $exe)) {
            throw "Missing exe after build: $exe"
        }
    }

    $proc = Start-Process -FilePath $exe `
        -ArgumentList @("--validation-mode", "--auto-close-ms=9800") `
        -WorkingDirectory $RepoRoot `
        -RedirectStandardOutput $stdoutFile `
        -RedirectStandardError $stderrFile `
        -PassThru

    if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
        Stop-Process -Id $proc.Id -Force
        throw "Gate run timed out after $TimeoutSeconds seconds"
    }

    $out = if (Test-Path -LiteralPath $stdoutFile) {
        Get-Content -LiteralPath $stdoutFile -Raw
    } else {
        ""
    }

    $runOk = $out -match "runtime_final_status=RUN_OK"
    $summaryPass = $out -match "SUMMARY:\s+PASS"

    Write-Host "ExitCode: $($proc.ExitCode)"
    Write-Host "runtime_final_status=RUN_OK: $runOk"
    Write-Host "SUMMARY: PASS: $summaryPass"

    if ($proc.ExitCode -eq 0 -and $runOk -and $summaryPass) {
        Write-Host "PASS"
    }
    else {
        Write-Host "FAIL"
    }
}
catch {
    $_ | Out-String | Add-Content -LiteralPath $stderrFile
    Write-Host "FAIL"
    Write-Host $_.Exception.Message
}

Read-Host "Press Enter to exit"