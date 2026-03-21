$ErrorActionPreference = 'Stop'
Set-Location "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime"

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path '_proof' ("phase54b_emission_audit_" + $ts)
New-Item -ItemType Directory -Force -Path $pf | Out-Null

function Write-Txt {
    param([string]$Name, [object]$Content)
    $p = Join-Path $pf $Name
    $Content | Set-Content -LiteralPath $p -Encoding UTF8
    return $p
}

function Invoke-NgksgraphBuild {
    param([string]$Target)
    $args = @('build', '--profile', 'debug', '--msvc-auto', '--target', $Target)

    $ngksCmd = Get-Command ngksgraph -ErrorAction SilentlyContinue
    if ($ngksCmd) {
        return (& ngksgraph @args 2>&1 | Out-String)
    }

    $venvPy = Join-Path (Get-Location) '.venv\Scripts\python.exe'
    if (Test-Path -LiteralPath $venvPy) {
        return (& $venvPy -m ngksgraph @args 2>&1 | Out-String)
    }

    $pyCmd = Get-Command py -ErrorAction SilentlyContinue
    if ($pyCmd) {
        return (& py -m ngksgraph @args 2>&1 | Out-String)
    }

    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCmd) {
        return (& python -m ngksgraph @args 2>&1 | Out-String)
    }

    throw 'Unable to locate ngksgraph command or python module entrypoint.'
}

function Get-FileState {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            exists = 'NO'
            path = $Path
            size = ''
            sha256 = ''
            mtime_utc = ''
        }
    }
    $it = Get-Item -LiteralPath $Path
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
    return [pscustomobject]@{
        exists = 'YES'
        path = $Path
        size = [string]$it.Length
        sha256 = $hash
        mtime_utc = $it.LastWriteTimeUtc.ToString('o')
    }
}

function Get-PeValidity {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 'NO' }
    $dump = (& dumpbin /headers $Path 2>&1 | Out-String)
    $llvm = (& llvm-readobj --file-headers --sections $Path 2>&1 | Out-String)
    $bad = ($dump -match 'LNK1106|fatal error') -or ($llvm -match 'unexpectedly encountered')
    if ($bad) { return 'NO' }
    return 'YES'
}

function Parse-ProofZipPath {
    param([string]$BuildOutput)
    $m = [regex]::Match($BuildOutput, 'PROOF_ZIP=(.+)')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ''
}

function Extract-ProofZipEvidence {
    param([string]$ZipPath, [string]$Target)
    $out = @("target=$Target", "proof_zip=$ZipPath")
    if (-not $ZipPath) {
        $out += 'PROOF_ZIP_NOT_DECLARED'
        return $out
    }
    if (-not (Test-Path -LiteralPath $ZipPath)) {
        $out += 'PROOF_ZIP_MISSING_ON_DISK'
        return $out
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $out += '---zip_entries---'
        foreach ($e in $zip.Entries) {
            $out += ("{0} | {1}" -f $e.FullName, $e.Length)
        }

        foreach ($name in @('RUN_SUMMARY.md', 'stdout.txt', 'stderr.txt', 'command_line.txt')) {
            $entry = $zip.Entries | Where-Object { $_.FullName -eq $name } | Select-Object -First 1
            if ($entry) {
                $out += ("---" + $name + "---")
                $sr = New-Object IO.StreamReader($entry.Open())
                try {
                    $out += $sr.ReadToEnd()
                }
                finally {
                    $sr.Dispose()
                }
            }
        }
    }
    finally {
        $zip.Dispose()
    }

    return $out
}

$targets = @('widget_sandbox', 'win32_sandbox', 'sandbox_app', 'loop_tests')
$rows = @()

foreach ($t in $targets) {
    $cmd = "ngksgraph build --profile debug --msvc-auto --target $t"
    $objPath = Join-Path (Get-Location) ("build/debug/obj/$t/apps/$t/main.obj")
    $exePath = Join-Path (Get-Location) ("build/debug/bin/$t.exe")

    $preObj = Get-FileState -Path $objPath
    $preExe = Get-FileState -Path $exePath
    $runStart = (Get-Date).ToUniversalTime()

    $buildOutput = Invoke-NgksgraphBuild -Target $t

    $runEnd = (Get-Date).ToUniversalTime()
    $postObj = Get-FileState -Path $objPath
    $postExe = Get-FileState -Path $exePath

    $planPath = Join-Path (Get-Location) 'build_graph/debug/ngksbuildcore_plan.json'
    $planCompileNode = 'NO'
    $planLinkNode = 'NO'
    $planOutPaths = @()
    if (Test-Path -LiteralPath $planPath) {
        $planRaw = Get-Content -LiteralPath $planPath -Raw
        if ($planRaw -match ('cl:' + [regex]::Escape($t) + ':compile')) { $planCompileNode = 'YES' }
        if ($planRaw -match ('link:' + [regex]::Escape($t) + ':link')) { $planLinkNode = 'YES' }
        $outMatches = [regex]::Matches($planRaw, '/OUT:build/debug/bin/[^\s"]+')
        foreach ($m in $outMatches) { $planOutPaths += $m.Value }
    }

    Write-Txt ("10_build_output_" + $t + ".txt") $buildOutput

    $proofZip = Parse-ProofZipPath -BuildOutput $buildOutput
    $zipEvidence = Extract-ProofZipEvidence -ZipPath $proofZip -Target $t
    Write-Txt ("11_zip_evidence_" + $t + ".txt") $zipEvidence

    $compileOccurred = if ($preObj.exists -eq 'NO' -and $postObj.exists -eq 'YES') { 'YES' } elseif ($preObj.mtime_utc -ne $postObj.mtime_utc -and $postObj.mtime_utc) { 'YES' } else { 'NO' }
    $linkOccurred = if ($preExe.exists -eq 'NO' -and $postExe.exists -eq 'YES') { 'YES' } elseif ($preExe.mtime_utc -ne $postExe.mtime_utc -and $postExe.mtime_utc) { 'YES' } else { 'NO' }

    $peValid = Get-PeValidity -Path $exePath

    $linkStatus = 'LINK_NOT_REACHED'
    $stderrText = ($zipEvidence -join "`n")
    if ($stderrText -match 'LNK[0-9]{4}|fatal error LNK') {
        $linkStatus = 'LINK_FAILED'
    }
    elseif ($linkOccurred -eq 'YES' -and $postExe.exists -eq 'YES') {
        $linkStatus = 'LINK_SUCCEEDED_AND_BINARY_EMITTED'
    }
    elseif ($linkOccurred -eq 'YES' -and $postExe.exists -ne 'YES') {
        $linkStatus = 'LINK_SUCCEEDED_BUT_BINARY_NOT_PRESERVED'
    }
    elseif ($linkOccurred -eq 'NO' -and $postExe.exists -eq 'YES') {
        $linkStatus = 'LINK_NOT_REACHED'
    }

    $rows += [pscustomobject]@{
        target = $t
        exact_command_invoked = $cmd
        proof_zip_created = $(if ($proofZip) { $proofZip } else { '' })
        compile_node_present_in_plan = $planCompileNode
        link_node_present_in_plan = $planLinkNode
        plan_output_paths = ($planOutPaths -join ';')
        compile_step_occurred = $compileOccurred
        link_step_occurred = $linkOccurred
        output_artifact_path = ("build/debug/bin/" + $t + ".exe")
        binary_exists_after_build = $postExe.exists
        size = $postExe.size
        sha256 = $postExe.sha256
        pe_valid = $peValid
        timestamp_utc = $postExe.mtime_utc
        link_status = $linkStatus
        pre_obj_mtime_utc = $preObj.mtime_utc
        post_obj_mtime_utc = $postObj.mtime_utc
        pre_exe_mtime_utc = $preExe.mtime_utc
        post_exe_mtime_utc = $postExe.mtime_utc
    }
}

$matrixCsv = Join-Path $pf '20_per_target_emission_audit.csv'
$rows | ConvertTo-Csv -NoTypeInformation | Set-Content -LiteralPath $matrixCsv -Encoding UTF8

# Output path truth: plan outputs + discovered target exe locations across workspace
$planOut = @()
foreach ($r in $rows) {
    $planOut += ("per_target_plan_output target=" + $r.target + " paths=" + $r.plan_output_paths)
    $planOut += ("per_target_plan_nodes target=" + $r.target + " compile_node=" + $r.compile_node_present_in_plan + " link_node=" + $r.link_node_present_in_plan)
}

$found = @()
foreach ($t in $targets) {
    $hits = Get-ChildItem -Path (Get-Location) -Recurse -Filter ($t + '.exe') -File -ErrorAction SilentlyContinue
    foreach ($h in $hits) {
        $found += ("found_exe target=" + $t + " path=" + $h.FullName + " size=" + $h.Length + " mtime_utc=" + $h.LastWriteTimeUtc.ToString('o'))
    }
}

$truePathsFile = Write-Txt '21_true_output_paths.txt' @($planOut + '' + $found)

# widget canonical path integrity
$widget = $rows | Where-Object { $_.target -eq 'widget_sandbox' } | Select-Object -First 1
$widgetStatus = 'untouched_from_prior_run'
if ($widget.pre_exe_mtime_utc -eq '' -and $widget.post_exe_mtime_utc -ne '') { $widgetStatus = 'fresh_valid_output' }
elseif ($widget.pre_exe_mtime_utc -ne $widget.post_exe_mtime_utc -and $widget.pe_valid -eq 'YES') { $widgetStatus = 'fresh_valid_output' }
elseif ($widget.pre_exe_mtime_utc -ne $widget.post_exe_mtime_utc -and $widget.pe_valid -eq 'NO') { $widgetStatus = 'copied_or_truncated_replacement' }
elseif ($widget.pre_exe_mtime_utc -eq $widget.post_exe_mtime_utc -and $widget.pe_valid -eq 'NO') { $widgetStatus = 'stale_older_output' }

$linkMatrix = Join-Path $pf '22_link_success_matrix.csv'
$rows | Select-Object target,link_status,compile_step_occurred,link_step_occurred,binary_exists_after_build,size,sha256,pe_valid,timestamp_utc | ConvertTo-Csv -NoTypeInformation | Set-Content -LiteralPath $linkMatrix -Encoding UTF8

$cleanRunnable = @($rows | Where-Object { $_.binary_exists_after_build -eq 'YES' -and $_.pe_valid -eq 'YES' } | Select-Object -ExpandProperty target)
$ready = if ($cleanRunnable.Count -gt 0) { 'YES' } else { 'NO' }

$singleBlocker = 'EMIT_COPY_PRESERVE_STAGE_UNRESOLVED'
if ($rows | Where-Object { $_.compile_step_occurred -eq 'NO' -and $_.link_step_occurred -eq 'NO' -and $_.binary_exists_after_build -eq 'NO' }) {
    $singleBlocker = 'PATH_RESOLUTION_OR_EXECUTION_STAGE_NOT_EMITTING_TARGET_BINARIES'
}
elseif (($rows | Where-Object { $_.binary_exists_after_build -eq 'YES' -and $_.pe_valid -eq 'NO' }).Count -gt 0) {
    $singleBlocker = 'PE_INTEGRITY'
}

$contract = @(
    "per_target_emission_audit=$matrixCsv",
    "true_output_paths=$truePathsFile",
    "widget_canonical_path_status=$widgetStatus",
    "link_success_matrix=$linkMatrix",
    "clean_runnable_targets=" + ($cleanRunnable -join ','),
    "phase54b_ready_for_runtime_validation=$ready",
    "single_next_blocker=$singleBlocker",
    "proof_folder=$pf"
)

Write-Txt '99_required_output_contract.txt' $contract

$zip = "$pf.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

$contract -join "`n"
