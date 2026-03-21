$ErrorActionPreference = 'Stop'
Set-Location "C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime"

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path '_proof' ("phase54b_integrity_custody_" + $ts)
New-Item -ItemType Directory -Force -Path $pf | Out-Null

function Write-Txt {
    param([string]$Name, [object]$Content)
    $p = Join-Path $pf $Name
    $Content | Set-Content -LiteralPath $p -Encoding UTF8
    return $p
}

function Get-PeSectionMath {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @('MISSING') }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $len = $bytes.Length
    $e_lfanew = [BitConverter]::ToInt32($bytes, 0x3C)
    $fileHdr = $e_lfanew + 4
    $numSections = [BitConverter]::ToInt16($bytes, $fileHdr + 2)
    $sizeOpt = [BitConverter]::ToInt16($bytes, $fileHdr + 16)
    $secTable = $fileHdr + 20 + $sizeOpt
    $o = @()
    $o += "file_length=$len"
    $o += "e_lfanew=$e_lfanew"
    $o += "num_sections=$numSections"
    for ($i = 0; $i -lt $numSections; $i++) {
        $s = $secTable + ($i * 40)
        if ($s + 39 -ge $len) { $o += "section[$i]=TABLE_TRUNCATED"; break }
        $nameBytes = $bytes[$s..($s + 7)]
        $name = ([Text.Encoding]::ASCII.GetString($nameBytes)).Trim([char]0)
        $szRaw = [BitConverter]::ToUInt32($bytes, $s + 16)
        $ptrRaw = [BitConverter]::ToUInt32($bytes, $s + 20)
        $endRaw = [uint64]$ptrRaw + [uint64]$szRaw
        $state = if ($endRaw -le [uint64]$len) { 'OK' } else { 'TRUNCATED' }
        $o += ("{0}: ptr_raw={1} size_raw={2} end_raw={3} state={4}" -f $name, $ptrRaw, $szRaw, $endRaw, $state)
    }
    return $o
}

function Get-PeValidity {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Valid = 'NO'; Reason = 'MISSING'; Dumpbin = 'MISSING'; Llvm = 'MISSING' }
    }
    $dump = (& dumpbin /headers $Path 2>&1 | Out-String)
    $llvm = (& llvm-readobj --file-headers --sections $Path 2>&1 | Out-String)
    $bad = ($dump -match 'LNK1106|fatal error') -or ($llvm -match 'unexpectedly encountered')
    [pscustomobject]@{
        Valid = if ($bad) { 'NO' } else { 'YES' }
        Dumpbin = $dump
        Llvm = $llvm
    }
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

$exeRel = 'build/debug/bin/widget_sandbox.exe'
$exe = Join-Path (Get-Location) $exeRel
$cmdLog = Join-Path (Get-Location) 'proofs/latest_ngksbuildcore_run/commands.jsonl'

# 1) Writer inventory
$invA = rg -n --no-heading --glob '!_proof/**' --glob '!_artifacts/**' "widget_sandbox\\.exe|build[/\\]debug[/\\]bin[/\\]widget_sandbox\\.exe|/OUT:build/debug/bin/widget_sandbox\\.exe" . 2>&1
$invB = rg -n --no-heading --glob '!_proof/**' --glob '!_artifacts/**' "Copy-Item|Move-Item|Set-Content|Out-File|New-Item|link /nologo|/OUT:build/debug/bin" tools build_graph proofs 2>&1
Write-Txt '01_writer_inventory_raw_refs.txt' @('=== RAW REFS A ===', $invA, '', '=== RAW REFS B ===', $invB)

$writerIntent = @(
    'WRITER INVENTORY (evidence-backed)',
    '1) NGKSGRAPH PLAN/EXECUTOR LINK OUTPUT',
    '   - build_graph/debug/ngksbuildcore_plan.json : link cmd /OUT:build/debug/bin/widget_sandbox.exe (writer intent: linker emits canonical exe).',
    '   - build_graph/debug/ngksgraph_plan.json : output_path build/debug/bin/widget_sandbox.exe (writer intent: graph-declared artifact output).',
    '   - proofs/latest_ngksbuildcore_run/commands.jsonl : executed link node for widget_sandbox (writer intent: actual write event by link.exe).',
    '2) DIRECT REBUILD SCRIPTS (manual/tooling path)',
    '   - tools/_tmp_rebuild_widget_native.cmd : link ... /OUT:build/debug/bin/widget_sandbox.exe',
    '   - tools/_tmp_rebuild_widget_native_x64.cmd : link ... /OUT:build/debug/bin/widget_sandbox.exe',
    '   - tools/_tmp_rebuild_widget_native_x86.cmd : link ... /OUT:build/debug/bin/widget_sandbox.exe',
    '3) PHASE ORCHESTRATION REFERENCES (read/execute against canonical exe; no direct write to exe path detected in those scripts)',
    '   - tools/phase40_* runner scripts reference launch/read path build/debug/bin/widget_sandbox.exe.',
    '   - tools/_phase54b_coverage_closure.ps1 references target exe paths for launch/validation.'
)
Write-Txt '02_writer_inventory_curated.txt' $writerIntent

# Helper for builds
function Get-NewLogWindow {
    param([int]$PreCount)
    if (-not (Test-Path -LiteralPath $cmdLog)) { return @() }
    $all = Get-Content -LiteralPath $cmdLog
    if ($PreCount -lt $all.Count) { return $all[$PreCount..($all.Count - 1)] }
    return @()
}

# 2) Controlled explicit widget rebuild with immediate capture and watch
$widgetCmd = 'ngksgraph build --profile debug --msvc-auto --target widget_sandbox'
$preLogCount = if (Test-Path -LiteralPath $cmdLog) { (Get-Content -LiteralPath $cmdLog).Count } else { 0 }
$buildStart = (Get-Date).ToUniversalTime()
$widgetOut = Invoke-NgksgraphBuild -Target 'widget_sandbox'
$buildEnd = (Get-Date).ToUniversalTime()
Write-Txt '10_widget_explicit_build_output.txt' $widgetOut

$post = if (Test-Path -LiteralPath $exe) { Get-Item -LiteralPath $exe } else { $null }
$hash = if ($post) { (Get-FileHash -Algorithm SHA256 -LiteralPath $exe).Hash } else { '' }
$size = if ($post) { [string]$post.Length } else { '' }
$mtime = if ($post) { $post.LastWriteTimeUtc.ToString('o') } else { '' }

$linkEnd = ''
$newWindow = Get-NewLogWindow -PreCount $preLogCount
$newWindow | Set-Content -LiteralPath (Join-Path $pf '11_widget_new_commandlog_window.jsonl') -Encoding UTF8
$linkEndLine = $newWindow | Select-String -Pattern '"node_id": "link:widget_sandbox:.*"stage": "end"' | Select-Object -Last 1
if ($linkEndLine) {
    try {
        $obj = $linkEndLine.Line | ConvertFrom-Json
        $linkEnd = [string]$obj.ts
    }
    catch {
        $linkEnd = ''
    }
}

$pe = Get-PeValidity -Path $exe
Write-Txt '12_widget_immediate_pe_dumpbin.txt' $pe.Dumpbin
Write-Txt '13_widget_immediate_pe_llvm.txt' $pe.Llvm
Write-Txt '14_widget_immediate_section_math.txt' (Get-PeSectionMath -Path $exe)

$watch = @('idx,utc,size,sha256,mtime_utc,changed')
$baselineSize = $size
$baselineHash = $hash
$baselineMtime = $mtime
$changed = $false
$firstChange = ''
for ($i = 1; $i -le 8; $i++) {
    Start-Sleep -Seconds 5
    if (Test-Path -LiteralPath $exe) {
        $it = Get-Item -LiteralPath $exe
        $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $exe).Hash
        $sz = [string]$it.Length
        $mt = $it.LastWriteTimeUtc.ToString('o')
        $chg = if ($sz -ne $baselineSize -or $h -ne $baselineHash -or $mt -ne $baselineMtime) { 'YES' } else { 'NO' }
        if ($chg -eq 'YES' -and -not $changed) { $changed = $true; $firstChange = (Get-Date).ToUniversalTime().ToString('o') }
        $watch += ("{0},{1},{2},{3},{4},{5}" -f $i, (Get-Date).ToUniversalTime().ToString('o'), $sz, $h, $mt, $chg)
    }
    else {
        $watch += ("{0},{1},MISSING,MISSING,MISSING,YES" -f $i, (Get-Date).ToUniversalTime().ToString('o'))
        if (-not $changed) { $changed = $true; $firstChange = (Get-Date).ToUniversalTime().ToString('o') }
    }
}
Write-Txt '15_widget_mutation_watch.csv' $watch
$mutationWindow = if ($changed) { "after immediate capture and before/at $firstChange" } else { 'NO_CHANGE_IN_40S_WINDOW' }

# 3/4) Explicit target matrix
$targets = @('widget_sandbox', 'win32_sandbox', 'sandbox_app', 'loop_tests')
$rows = @()
foreach ($t in $targets) {
    $cmd = "ngksgraph build --profile debug --msvc-auto --target $t"
    $pre = if (Test-Path -LiteralPath $cmdLog) { (Get-Content -LiteralPath $cmdLog).Count } else { 0 }
    $out = Invoke-NgksgraphBuild -Target $t
    Write-Txt ("20_build_output_" + $t + ".txt") $out

    $new = Get-NewLogWindow -PreCount $pre
    $new | Set-Content -LiteralPath (Join-Path $pf ("21_commandlog_window_" + $t + ".jsonl")) -Encoding UTF8
    $compile = if (($new | Select-String -Pattern ('"node_id": "compile:' + [regex]::Escape($t) + ':')).Count -gt 0) { 'YES' } else { 'NO' }
    $link = if (($new | Select-String -Pattern ('"node_id": "link:' + [regex]::Escape($t) + ':')).Count -gt 0) { 'YES' } else { 'NO' }

    $outPath = "build/debug/bin/$t.exe"
    $full = Join-Path (Get-Location) $outPath
    $emit = 'NO'; $sz = ''; $h = ''; $pv = 'NO'
    if (Test-Path -LiteralPath $full) {
        $emit = 'YES'
        $it = Get-Item -LiteralPath $full
        $sz = [string]$it.Length
        $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $full).Hash
        $pvt = Get-PeValidity -Path $full
        $pv = $pvt.Valid
        Write-Txt ("22_pe_dumpbin_" + $t + ".txt") $pvt.Dumpbin
        Write-Txt ("23_pe_llvm_" + $t + ".txt") $pvt.Llvm
    }

    $rows += [pscustomobject]@{
        target = $t
        build_invoked = 'YES'
        compile_reached = $compile
        link_reached = $link
        binary_emitted = $emit
        output_path = $outPath
        size = $sz
        sha256 = $h
        pe_valid = $pv
    }
}

$matrixCsv = Join-Path $pf '30_explicit_target_matrix.csv'
$rows | ConvertTo-Csv -NoTypeInformation | Set-Content -LiteralPath $matrixCsv -Encoding UTF8

$validTargets = @($rows | Where-Object { $_.binary_emitted -eq 'YES' -and $_.pe_valid -eq 'YES' } | Select-Object -ExpandProperty target)
$failedTargets = @($rows | Where-Object { $_.binary_emitted -ne 'YES' -or $_.pe_valid -ne 'YES' } | Select-Object -ExpandProperty target)

$sourceClass = 'UNKNOWN'
$ready = if (($validTargets.Count -gt 0) -and (-not $changed)) { 'YES' } else { 'NO' }
$blocker = if ($ready -eq 'YES') { 'NONE' } elseif ($changed) { 'POST_LINK_MUTATION_UNRESOLVED' } else { 'TARGET_INTEGRITY_NOT_FULLY_RESTORED' }

$contract = @(
    "widget_post_link_writer_inventory=" + (Join-Path $pf '02_writer_inventory_curated.txt'),
    "widget_immediate_postbuild_hash=$hash",
    "widget_immediate_postbuild_size=$size",
    "widget_mutated_after_build=" + ($(if ($changed) { 'YES' } else { 'NO' })),
    "widget_mutation_window=$mutationWindow",
    "widget_mutation_source_class=$sourceClass",
    "explicit_target_matrix_file=$matrixCsv",
    "valid_emitted_targets=" + ($validTargets -join ','),
    "failed_or_missing_targets=" + ($failedTargets -join ','),
    "phase54b_ready_for_runtime_validation=$ready",
    "single_next_blocker=$blocker",
    "proof_folder=$pf"
)
Write-Txt '99_required_output_contract.txt' $contract

$zip = "$pf.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

$contract -join "`n"
