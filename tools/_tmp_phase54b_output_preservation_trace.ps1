$ErrorActionPreference = 'Stop'
Set-Location "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime"

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path '_proof' ("phase54b_output_preservation_trace_" + $ts)
New-Item -ItemType Directory -Force -Path $pf | Out-Null

function Write-Txt {
    param([string]$Name, [object]$Content)
    $p = Join-Path $pf $Name
    $Content | Set-Content -LiteralPath $p -Encoding UTF8
    return $p
}

function Get-PeValidity {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 'NO' }
    $dump = (& dumpbin /headers $Path 2>&1 | Out-String)
    $llvm = (& llvm-readobj --file-headers --sections $Path 2>&1 | Out-String)
    $bad = ($dump -match 'LNK1106|fatal error') -or ($llvm -match 'unexpectedly encountered')
    Write-Txt '50_widget_pe_dumpbin_after_restore.txt' $dump | Out-Null
    Write-Txt '51_widget_pe_llvm_after_restore.txt' $llvm | Out-Null
    if ($bad) { return 'NO' }
    return 'YES'
}

function Get-NgksPython {
    $venvPy = Join-Path (Get-Location) '.venv\\Scripts\\python.exe'
    if (Test-Path -LiteralPath $venvPy) { return $venvPy }
    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) { return 'py' }
    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) { return 'python' }
    throw 'Python entrypoint not found'
}

$target = 'widget_sandbox'
$cmdBuild = 'ngksgraph build --profile debug --msvc-auto --target widget_sandbox'
$cmdBuildcore = 'ngksbuildcore run --plan build_graph/debug/ngksbuildcore_plan.json -j 1'
$widgetExeRel = 'build/debug/bin/widget_sandbox.exe'
$widgetExe = Join-Path (Get-Location) $widgetExeRel

$pyExe = Get-NgksPython
Write-Txt '00_runtime_entrypoint.txt' @("python_entrypoint=$pyExe", "ngksgraph_build_command=$cmdBuild", "ngksbuildcore_run_command=$cmdBuildcore") | Out-Null

# Step 1+2: ngksgraph build (active path) and plan trace
$buildOut = (& $pyExe -m ngksgraph build --profile debug --msvc-auto --target widget_sandbox 2>&1 | Out-String)
Write-Txt '10_ngksgraph_build_stdout_stderr.txt' $buildOut | Out-Null

$planPath = ''
$planMatch = [regex]::Match($buildOut, 'BuildCore plan:\s+(.+)')
if ($planMatch.Success) { $planPath = $planMatch.Groups[1].Value.Trim() }
if (-not $planPath) {
    $planPath = Join-Path (Get-Location) 'build_graph/debug/ngksbuildcore_plan.json'
}

$planJson = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
$compileNode = $null
$linkNode = $null
foreach ($n in $planJson.nodes) {
    if ($n.id -like 'cl:widget_sandbox:*') { $compileNode = $n }
    if ($n.id -like 'link:widget_sandbox:*') { $linkNode = $n }
}

if (-not $compileNode -or -not $linkNode) {
    throw 'Failed to locate compile/link nodes for widget_sandbox in active plan'
}

$linkCmd = [string]$linkNode.cmd
$outRel = ''
$mOut = [regex]::Match($linkCmd, '/OUT:([^\s]+)')
if ($mOut.Success) { $outRel = $mOut.Groups[1].Value.Trim() }
$outAbs = if ($outRel) { (Join-Path (Get-Location) $outRel) } else { '' }

$copyStageNodes = @()
foreach ($n in $planJson.nodes) {
    $cmd = [string]$n.cmd
    if ($cmd -match 'copy|xcopy|robocopy|move|stage|finalize') {
        if ($cmd -match 'widget_sandbox|build/debug/bin') {
            $copyStageNodes += ("id=" + $n.id + " cmd=" + $cmd)
        }
    }
}

$pathChain = @(
    "selected_target=$target",
    "active_ngksgraph_command=$cmdBuild",
    "generated_plan_path=$planPath",
    "compile_node_id=$($compileNode.id)",
    "compile_cmd=$($compileNode.cmd)",
    "compile_outputs=" + (($compileNode.outputs -join ';')),
    "link_node_id=$($linkNode.id)",
    "link_cmd=$linkCmd",
    "link_out_relative=$outRel",
    "link_out_absolute=$outAbs",
    "link_outputs=" + (($linkNode.outputs -join ';')),
    "copy_stage_nodes_found=" + ($copyStageNodes.Count),
    "copy_stage_nodes=" + ($(if($copyStageNodes.Count -gt 0){$copyStageNodes -join ' || '} else {'NONE'})),
    "final_expected_artifact=$widgetExe"
)
$pathChainFile = Write-Txt '20_widget_path_chain_evidence.txt' $pathChain

# Step 3: materialization watch during explicit ngksgraph build
$candidateDirs = @(
    (Join-Path (Get-Location) 'build/debug/obj/widget_sandbox'),
    (Join-Path (Get-Location) 'build/debug/lib'),
    (Join-Path (Get-Location) 'build/debug/bin')
)

$watchScript = {
    param($Dirs, $OutFile)
    $ErrorActionPreference = 'SilentlyContinue'
    $seen = @{}
    $events = New-Object System.Collections.Generic.List[string]
    $events.Add('utc,event,path,size,mtime_utc') | Out-Null

    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt 20) {
        foreach ($d in $Dirs) {
            if (-not (Test-Path -LiteralPath $d)) { continue }
            $files = Get-ChildItem -LiteralPath $d -Recurse -File | Where-Object { $_.Extension -in '.obj', '.lib', '.exe', '.pdb' }
            foreach ($f in $files) {
                $k = $f.FullName
                $sig = "$($f.Length)|$($f.LastWriteTimeUtc.ToString('o'))"
                if (-not $seen.ContainsKey($k)) {
                    $seen[$k] = $sig
                    $events.Add(("{0},CREATE,{1},{2},{3}" -f (Get-Date).ToUniversalTime().ToString('o'), $k, $f.Length, $f.LastWriteTimeUtc.ToString('o'))) | Out-Null
                }
                elseif ($seen[$k] -ne $sig) {
                    $seen[$k] = $sig
                    $events.Add(("{0},MODIFY,{1},{2},{3}" -f (Get-Date).ToUniversalTime().ToString('o'), $k, $f.Length, $f.LastWriteTimeUtc.ToString('o'))) | Out-Null
                }
            }
        }
        Start-Sleep -Milliseconds 200
    }
    $events | Set-Content -LiteralPath $OutFile -Encoding UTF8
}

$watchOut = Join-Path $pf '30_materialization_watch_ngksgraph_build.csv'
$job = Start-Job -ScriptBlock $watchScript -ArgumentList @($candidateDirs, $watchOut)
Start-Sleep -Milliseconds 300
$buildOutWatch = (& $pyExe -m ngksgraph build --profile debug --msvc-auto --target widget_sandbox 2>&1 | Out-String)
Write-Txt '31_ngksgraph_build_during_watch.txt' $buildOutWatch | Out-Null
Wait-Job $job | Out-Null
Receive-Job $job | Out-Null
Remove-Job $job | Out-Null
if (-not (Test-Path -LiteralPath $watchOut)) { Write-Txt '30_materialization_watch_ngksgraph_build.csv' 'NO_WATCH_OUTPUT' | Out-Null }

# Step 4+5: preservation/finalize + boundary evidence from source
$cliPath = Join-Path (Get-Location) '.venv/Lib/site-packages/ngksgraph/cli.py'
$buildcoreAdapterPath = Join-Path (Get-Location) '.venv/Lib/site-packages/ngksbuildcore/adapters/graph_adapter.py'
$buildcoreRunnerPath = Join-Path (Get-Location) '.venv/Lib/site-packages/ngksbuildcore/runner.py'

$boundaryEvidence = @()
$boundaryEvidence += 'ngksgraph cmd_build evidence:'
$boundaryEvidence += (Get-Content -LiteralPath $cliPath | Select-String -Pattern 'def cmd_build|emit_buildcore_plan|BuildCore plan:|return 0|freeze skipped: runtime build execution removed' | ForEach-Object { "L$($_.LineNumber): $($_.Line.Trim())" })
$boundaryEvidence += ''
$boundaryEvidence += 'ngksbuildcore adapter/runner evidence:'
$boundaryEvidence += (Get-Content -LiteralPath $buildcoreAdapterPath | Select-String -Pattern 'run_graph_plan|run_build' | ForEach-Object { "graph_adapter:L$($_.LineNumber): $($_.Line.Trim())" })
$boundaryEvidence += (Get-Content -LiteralPath $buildcoreRunnerPath | Select-String -Pattern 'def run_build|execute_node|commands.jsonl|BUILD_START|BUILD_END' | ForEach-Object { "runner:L$($_.LineNumber): $($_.Line.Trim())" })
Write-Txt '40_executor_boundary_evidence.txt' $boundaryEvidence | Out-Null

# Step 6: single-target restoration via BuildCore run
$preState = if (Test-Path -LiteralPath $widgetExe) { Get-Item -LiteralPath $widgetExe } else { $null }
$preHash = if ($preState) { (Get-FileHash -Algorithm SHA256 -LiteralPath $widgetExe).Hash } else { '' }

# Keep stale binary backup for custody, then remove to force fresh materialization evidence.
if (Test-Path -LiteralPath $widgetExe) {
    Copy-Item -LiteralPath $widgetExe -Destination (Join-Path $pf '41_widget_pre_restore_backup.exe') -Force
    Remove-Item -LiteralPath $widgetExe -Force
}

$buildcoreProof = Join-Path $pf 'buildcore_run_proof'
New-Item -ItemType Directory -Force -Path $buildcoreProof | Out-Null
$buildcoreOut = (& $pyExe -m ngksbuildcore run --plan $planPath --proof $buildcoreProof -j 1 2>&1 | Out-String)
Write-Txt '42_ngksbuildcore_run_output.txt' $buildcoreOut | Out-Null

$cmdJsonl = Join-Path $buildcoreProof 'commands.jsonl'
if (Test-Path -LiteralPath $cmdJsonl) {
    Copy-Item -LiteralPath $cmdJsonl -Destination (Join-Path $pf '43_buildcore_commands.jsonl') -Force
}
$summaryJson = Join-Path $buildcoreProof 'summary.json'
if (Test-Path -LiteralPath $summaryJson) {
    Copy-Item -LiteralPath $summaryJson -Destination (Join-Path $pf '44_buildcore_summary.json') -Force
}

$postState = if (Test-Path -LiteralPath $widgetExe) { Get-Item -LiteralPath $widgetExe } else { $null }
$postHash = if ($postState) { (Get-FileHash -Algorithm SHA256 -LiteralPath $widgetExe).Hash } else { '' }
$peValid = Get-PeValidity -Path $widgetExe

$freshRestored = 'NO'
if ($postState -and $preState) {
    if ($postState.LastWriteTimeUtc -gt $preState.LastWriteTimeUtc -and $peValid -eq 'YES') { $freshRestored = 'YES' }
}
elseif ($postState -and -not $preState -and $peValid -eq 'YES') {
    $freshRestored = 'YES'
}

# first materialized path from commands.jsonl or watch fallback
$firstMat = ''
if (Test-Path -LiteralPath $cmdJsonl) {
    $lines = Get-Content -LiteralPath $cmdJsonl
    $widgetLinkStart = $lines | Select-String -Pattern '"node_id":\s*"link:widget_sandbox:.*"stage":\s*"start"' | Select-Object -First 1
    if ($widgetLinkStart) { $firstMat = $outAbs }
}
if (-not $firstMat -and (Test-Path -LiteralPath $widgetExe)) { $firstMat = $widgetExe }

$preserveStatus = 'UNKNOWN'
if ($copyStageNodes.Count -eq 0) { $preserveStatus = 'SKIPPED' }
if ($freshRestored -eq 'YES') { $preserveStatus = 'SUCCESS' }
if ($freshRestored -eq 'NO' -and (Test-Path -LiteralPath $cmdJsonl)) {
    $cmdText = Get-Content -LiteralPath $cmdJsonl -Raw
    if ($cmdText -match '"node_id":\s*"link:widget_sandbox:.*"stage":\s*"end"' -and -not (Test-Path -LiteralPath $widgetExe)) {
        $preserveStatus = 'FAILED'
    }
}

$handoffOwner = 'ngksgraph.cmd_build (plan emission only); executable artifact handoff owner is ngksbuildcore.runner.run_build'
$ready = if ($freshRestored -eq 'YES') { 'YES' } else { 'NO' }
$blocker = if ($freshRestored -eq 'YES') { 'NONE' } else { 'BUILDCORE_EXECUTION_DID_NOT_PRODUCE_FRESH_VALID_WIDGET_BINARY' }

$contract = @(
    "widget_path_chain_file=$pathChainFile",
    "widget_exact_link_out_path=$outAbs",
    "widget_first_materialized_path=$firstMat",
    "widget_preservation_stage_status=$preserveStatus",
    "executor_final_handoff_owner=$handoffOwner",
    "fresh_widget_binary_restored=$freshRestored",
    "fresh_widget_binary_path=" + ($(if($postState){$widgetExe}else{''})),
    "fresh_widget_binary_hash=$postHash",
    "fresh_widget_binary_pe_valid=$peValid",
    "phase54b_ready_for_runtime_validation=$ready",
    "single_next_blocker=$blocker",
    "proof_folder=$pf"
)
Write-Txt '99_required_output_contract.txt' $contract | Out-Null

$zip = "$pf.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

$contract -join "`n"
