Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Get-Location
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$pfBase = Join-Path $root ('_proof\phase54b_target_coverage_validation_' + $timestamp)
New-Item -ItemType Directory -Path $pfBase -Force | Out-Null

Write-Output "=== Phase 54B Target Coverage Closure ==="
Write-Output "TIMESTAMP: $timestamp"
Write-Output "PROOF_BASE: $pfBase"
Write-Output ""

$targets = @('widget_sandbox', 'win32_sandbox', 'sandbox_app', 'loop_tests')
$buildResults = @{}
$validationResults = @{}

Write-Output "[PHASE 1] Rebuild all 4 targets"
foreach ($target in $targets) {
    Write-Output "  Building $target..."
    
    try {
        $pythonExe = Join-Path (Get-Location) ".venv\Scripts\python.exe"
        $buildOutput = & "$pythonExe" -m ngksgraph build --profile debug --msvc-auto --target $target 2>&1
        if ($LASTEXITCODE -eq 0) {
            $buildResults[$target] = 'SUCCESS'
            Write-Output "    [OK] $target built"
        }
        else {
            $buildResults[$target] = 'FAILED'
            Write-Output "    [FAIL] $target build failed"
            $buildOutput | Set-Content -LiteralPath (Join-Path $pfBase "${target}_build_error.txt") -Encoding UTF8
        }
    }
    catch {
        $buildResults[$target] = 'ERROR'
        $_.Exception.Message | Set-Content -LiteralPath (Join-Path $pfBase "${target}_build_exception.txt") -Encoding UTF8
    }
}

Write-Output ""
Write-Output "[PHASE 2] Validate enforcement hooks on each target"
$enforcementCheckResults = @(
    @{ target='widget_sandbox'; expectedCalls=5; contexts=@('execution_pipeline', 'plugin_load', 'file_load', 'save_export', 'runtime_init') },
    @{ target='win32_sandbox'; expectedCalls=3; contexts=@('file_load', 'execution_pipeline', 'runtime_init') },
    @{ target='sandbox_app'; expectedCalls=1; contexts=@('runtime_init') },
    @{ target='loop_tests'; expectedCalls=1; contexts=@('runtime_init') }
)

$enforcementVerified = $true
foreach ($check in $enforcementCheckResults) {
    $targetName = $check.target
    $targetFile = "apps\$targetName\main.cpp"
    
    if (-not (Test-Path -LiteralPath $targetFile)) {
        Write-Output "  [FAIL] $targetName source not found"
        $enforcementVerified = $false
        continue
    }
    
    $source = Get-Content -LiteralPath $targetFile -Raw
    $callCount = ([regex]::Matches($source, 'enforce_runtime_trust|require_runtime_trust|enforce_phase53_2')).Count
    
    if ($callCount -eq $check.expectedCalls) {
        Write-Output "  [OK] $targetName has $callCount enforcement call(s)"
    }
    else {
        Write-Output "  [FAIL] $targetName has $callCount call(s), expected $($check.expectedCalls)"
        $enforcementVerified = $false
    }
}

Write-Output ""
Write-Output "[PHASE 3] Run clean-state validation on each target"
foreach ($target in $targets) {
    $exePath = Join-Path (Get-Location) "build\debug\bin\${target}.exe"
    
    if (-not (Test-Path -LiteralPath $exePath)) {
        Write-Output "  [FAIL] $target exe not found: $exePath"
        $validationResults["${target}_clean"] = 'MISSING_EXE'
        continue
    }
    
    Write-Output "  Running $target (clean state)..."
    $outFile = Join-Path $pfBase "${target}_clean_output.txt"
    $exeDir = Split-Path $exePath
    $exeName = Split-Path $exePath -Leaf
    $cmdLine = "cd /d `"$exeDir`" && $exeName --auto-close-ms=2000"
    $output = & cmd /c $cmdLine 2>&1
    $cleanCode = $LASTEXITCODE
    $output | Set-Content -LiteralPath $outFile -Encoding UTF8
    
    $validationResults["${target}_clean"] = if ($cleanCode -eq 0) { 'PASS' } else { 'FAIL' }
    
    $detail = if ($cleanCode -eq 0) { '[OK]' } else { "[FAIL exit=$cleanCode]" }
    Write-Output "    $detail $target clean: exit=$cleanCode"
}

Write-Output ""
Write-Output "[PHASE 4] Run invalid-state validation on each target"
foreach ($target in $targets) {
    $exePath = Join-Path (Get-Location) "build\debug\bin\${target}.exe"
    
    if (-not (Test-Path -LiteralPath $exePath)) {
        $validationResults["${target}_invalid"] = 'MISSING_EXE'
        continue
    }
    
    Write-Output "  Running $target (invalid state: NGKS_BYPASS_GUARD=1)..."
    
    $env:NGKS_BYPASS_GUARD = '1'
    try {
        $outFile = Join-Path $pfBase "${target}_invalid_output.txt"
        $exeDir = Split-Path $exePath
        $exeName = Split-Path $exePath -Leaf
        $cmdLine = "cd /d `"$exeDir`" && $exeName --auto-close-ms=2000"
        $output = & cmd /c $cmdLine 2>&1
        $invalidCode = $LASTEXITCODE
        $output | Set-Content -LiteralPath $outFile -Encoding UTF8
        
        $isFail = ($invalidCode -ne 0)
        $validationResults["${target}_invalid"] = if ($isFail) { 'FAIL_CLOSED' } else { 'UNEXPECTED_PASS' }
        
        $detail = if ($isFail) { '[OK blocked]' } else { '[FAIL allowed]' }
        Write-Output "    $detail $target invalid: exit=$invalidCode"
    }
    finally {
        [Environment]::SetEnvironmentVariable('NGKS_BYPASS_GUARD', $null)
    }
}

Write-Output ""
Write-Output "[PHASE 5] Generate contract summary"
$buildStatus = if (($buildResults.Values | Where-Object {$_ -eq 'SUCCESS'}).Count -eq 4) { 'PASS' } else { 'PARTIAL' }
$validationStatus = if (($validationResults.Values | Where-Object {$_ -in @('PASS', 'FAIL_CLOSED')}).Count -eq 8) { 'PASS' } else { 'PARTIAL' }
$phase54bStatus = if (($buildStatus -eq 'PASS') -and ($validationStatus -eq 'PASS')) { 'PASS' } else { 'PARTIAL' }

$summary = @(
    "PHASE54B_STATUS=$phase54bStatus",
    "BUILD_STATUS=$buildStatus",
    "VALIDATION_STATUS=$validationStatus",
    "ENFORCEMENT_VERIFIED=$enforcementVerified",
    ("TARGETS_BUILT=" + (@($buildResults.Keys | Where-Object {$buildResults[$_] -eq 'SUCCESS'}) -join ',')),
    ("TARGETS_VALIDATED_CLEAN=" + (@($validationResults.Keys | Where-Object {($_ -match '_clean') -and ($validationResults[$_] -eq 'PASS')}) -replace '_clean' -join ',')),
    ("TARGETS_BLOCKED_INVALID=" + (@($validationResults.Keys | Where-Object {($_ -match '_invalid') -and ($validationResults[$_] -eq 'FAIL_CLOSED')}) -replace '_invalid' -join ','))
)

$summary | Set-Content -LiteralPath (Join-Path $pfBase '99_contract_summary.txt') -Encoding UTF8

Write-Output ""
Write-Output "=== FINAL RESULTS ==="
$summary | ForEach-Object { Write-Output $_ }

Write-Output ""
Write-Output "PROOF_FOLDER: $pfBase"

$zip = $pfBase + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $pfBase '*') -DestinationPath $zip -CompressionLevel Optimal
Write-Output "PROOF_ZIP: $zip"
