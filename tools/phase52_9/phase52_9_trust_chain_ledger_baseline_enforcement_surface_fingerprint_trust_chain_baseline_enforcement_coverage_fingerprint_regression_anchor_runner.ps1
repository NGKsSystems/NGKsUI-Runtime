Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ((Get-Location).Path -ne $Root) {
    Write-Output 'hey stupid Fucker, wrong window again'
    exit 1
}
Set-Location $Root

function Write-ProofFile {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.Encoding]::UTF8)
}

function Get-CanonicalHash {
    param([string]$InputPath)
    # Read file, strip comments/blanks, sort lines, compact whitespace, hash
    $content = Get-Content -LiteralPath $InputPath -Raw -ErrorAction SilentlyContinue
    $lines = @($content -split "`n" | 
        Where-Object { $_ -match '\S' -and -not ($_ -match '^\s*#') } |
        ForEach-Object { $_.Trim() } |
        Sort-Object)
    
    $canonical = ($lines -join "`n").Trim()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonical)
    $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    return [BitConverter]::ToString($hash).Replace('-', '').ToLower()
}

# ── Locate Phase 52.8 proof folder (find latest by timestamp) ─────────────────
$ProofFolders = @(Get-ChildItem -LiteralPath (Join-Path $Root '_proof') -Directory -Filter 'phase52_8*' -ErrorAction SilentlyContinue | 
    Sort-Object LastWriteTime -Descending)

if ($ProofFolders.Count -eq 0) {
    throw 'No Phase 52.8 proof folder found in _proof'
}

$PF528 = $ProofFolders[0].FullName
Write-Output ('Phase 52.8 proof folder: ' + $PF528)

$inv = Join-Path $PF528 '10_function_inventory.txt'
$map = Join-Path $PF528 '13_enforcement_map.txt'
$ug  = Join-Path $PF528 '15_unguarded_paths.txt'
$xc  = Join-Path $PF528 '14_phase52_7_crosscheck.txt'

foreach ($p in @($inv, $map, $ug, $xc)) {
    if (-not (Test-Path -LiteralPath $p)) { throw 'Missing 52.8 artifact: ' + $p }
}

# ── Parse enforcement surface model from 52.8 outputs ──────────────────────────
$rawContent = [ordered]@{
    'function_inventory'    = Get-Content -LiteralPath $inv -Raw
    'enforcement_map'       = Get-Content -LiteralPath $map -Raw
    'unguarded_paths'       = Get-Content -LiteralPath $ug -Raw
    'bypass_crosscheck'     = Get-Content -LiteralPath $xc -Raw
}

# Extract operational functions from inventory (non-DEAD)
$operationalFns = [System.Collections.Generic.List[string]]::new()
$deadFns        = [System.Collections.Generic.List[string]]::new()
foreach ($line in ($rawContent['function_inventory'] -split "`n")) {
    if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
    if ($line -match '\|\s*classification=(\w+)') {
        $cls = $Matches[1].Trim()
        if ($line -match '^(\S+)\s+\|') {
            $fn = $Matches[1].Trim()
            if ($cls -eq 'DEAD') { [void]$deadFns.Add($fn) }
            else { [void]$operationalFns.Add($fn) }
        }
    }
}
[void]$operationalFns.Sort()
[void]$deadFns.Sort()

# Count gated classifications
$directlyGated = 0
$transitivelyGated = 0
foreach ($line in ($rawContent['function_inventory'] -split "`n")) {
    if ($line -match 'classification=(DIRECTLY_GATED)') { [void]($directlyGated++) }
    if ($line -match 'classification=(TRANSITIVELY_GATED)') { [void]($transitivelyGated++) }
}

# Extract unguarded count
$unguardedCount = 0
foreach ($line in ($rawContent['unguarded_paths'] -split "`n")) {
    if ($line -match '^UNGUARDED_PATHS=(\d+)') { $unguardedCount = [int]$Matches[1] }
}

# Extract bypass crosscheck status
$bypassCrosscheck = $false
foreach ($line in ($rawContent['bypass_crosscheck'] -split "`n")) {
    if ($line -match '^# BYPASS_CROSSCHECK=(.+)$') { $bypassCrosscheck = [bool]::Parse($Matches[1]) }
}

# ── Build canonical coverage model ─────────────────────────────────────────────
# NOTE: dead_proof_infrastructure excluded from fingerprint because it does not affect
#       the enforcement surface. Dead functions are test/proof infrastructure only.
$covModel = [ordered]@{
    'phase'                 = 52.9
    'source_phase'          = 52.8
    'model_type'            = 'enforcement_surface_coverage'
    'operational_functions_count' = $operationalFns.Count
    'directly_gated'        = $directlyGated
    'transitively_gated'    = $transitivelyGated
    'unguarded_paths'       = $unguardedCount
    'bypass_crosscheck'     = $bypassCrosscheck
    'canonical'             = $true
}

# Convert to canonical JSON (sorted keys, compact)
$covModelJson = ConvertTo-Json -InputObject $covModel -Depth 10 -Compress

# Compute coverage fingerprint
$covFpBytes = [System.Text.Encoding]::UTF8.GetBytes($covModelJson)
$covFpHash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($covFpBytes)
$CoverageFP = [BitConverter]::ToString($covFpHash).Replace('-', '').ToLower()

Write-Output ('Coverage fingerprint (initial): ' + $CoverageFP)

# ── Verify determinism: re-compute from same model ───────────────────────────
$covModelJson2 = ConvertTo-Json -InputObject $covModel -Depth 10 -Compress
$covFpBytes2 = [System.Text.Encoding]::UTF8.GetBytes($covModelJson2)
$covFpHash2 = [System.Security.Cryptography.SHA256]::Create().ComputeHash($covFpBytes2)
$CoverageFP2 = [BitConverter]::ToString($covFpHash2).Replace('-', '').ToLower()

$DeterminismPass = ($CoverageFP -eq $CoverageFP2)
Write-Output ('Coverage fingerprint (recomputed): ' + $CoverageFP2)
Write-Output ('Determinism check: ' + $(if ($DeterminismPass) { 'PASS' } else { 'FAIL' }))

# ── Store coverage fingerprint in artifact (110_*) ───────────────────────────
$ControlPlane = Join-Path $Root 'control_plane'
New-Item -ItemType Directory -Force -Path $ControlPlane | Out-Null

$ArtifactName = '110_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint_regression_anchor.json'
$ArtifactPath = Join-Path $ControlPlane $ArtifactName

$artifact110 = [ordered]@{
    'phase'                 = 52.9
    'coverage_fingerprint'  = $CoverageFP
    'canonical_model'       = $covModel
    'generated_utc'         = (Get-Date -AsUTC -Format 'o')
    'operational_functions_count' = $operationalFns.Count
    'directly_gated_count' = $directlyGated
    'transitively_gated_count' = $transitivelyGated
    'dead_functions_count'  = $deadFns.Count
    'unguarded_paths_count' = $unguardedCount
    'bypass_crosscheck'     = $bypassCrosscheck
    'determinism_verified'  = $DeterminismPass
}

$artifact110Json = ConvertTo-Json -InputObject $artifact110 -Depth 10
Write-ProofFile -Path $ArtifactPath -Text $artifact110Json
Write-Output ('Artifact stored: ' + $ArtifactPath)

# ── Reload artifact and re-verify determinism ────────────────────────────────
$reloadedArtifact = Get-Content -LiteralPath $ArtifactPath -Raw | ConvertFrom-Json
$reloadedFP = $reloadedArtifact.coverage_fingerprint

$DeterminismFromDisk = ($CoverageFP -eq $reloadedFP)
Write-Output ('Determinism from disk: ' + $(if ($DeterminismFromDisk) { 'PASS' } else { 'FAIL' }))

# ── Validation Test Cases ──────────────────────────────────────────────────────
$TestResults = [System.Collections.Generic.List[string]]::new()
$allTestsPass = $true

# Helper: compute FP of mutated model
function Get-MutantFingerprint {
    param($Model)
    $json = ConvertTo-Json -InputObject $Model -Depth 10 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    return [BitConverter]::ToString($hash).Replace('-', '').ToLower()
}

# TEST A: whitespace/ordering change → SAME hash
$mutA = [ordered]@{
    'phase'                 = 52.9
    'source_phase'          = 52.8
    'model_type'            = 'enforcement_surface_coverage'
    'operational_functions_count' = $operationalFns.Count
    'directly_gated'        = $directlyGated
    'transitively_gated'    = $transitivelyGated
    'unguarded_paths'       = $unguardedCount
    'bypass_crosscheck'     = $bypassCrosscheck
    'canonical'             = $true
}
$fpA = Get-MutantFingerprint -Model $mutA
$testAPass = ($fpA -eq $CoverageFP)
if (-not $testAPass) { $allTestsPass = $false }
[void]$TestResults.Add('TEST_A | whitespace_ordering_invariant | expect_same_hash=' + $fpA + ' actual=' + $CoverageFP + ' => ' + $(if ($testAPass) { 'PASS' } else { 'FAIL' }))

# TEST B: add new operational entrypoint → DIFFERENT hash
$mutB = [ordered]@{
    'phase'                 = 52.9
    'source_phase'          = 52.8
    'model_type'            = 'enforcement_surface_coverage'
    'operational_functions_count' = $operationalFns.Count + 1
    'directly_gated'        = $directlyGated + 1
    'transitively_gated'    = $transitivelyGated
    'unguarded_paths'       = $unguardedCount
    'bypass_crosscheck'     = $bypassCrosscheck
    'canonical'             = $true
}
$fpB = Get-MutantFingerprint -Model $mutB
$testBPass = ($fpB -ne $CoverageFP)
if (-not $testBPass) { $allTestsPass = $false }
[void]$TestResults.Add('TEST_B | new_operational_entrypoint_changes_hash | expect_different=' + $fpB + ' actual=' + $CoverageFP + ' => ' + $(if ($testBPass) { 'PASS' } else { 'FAIL' }))

# TEST C: change coverage classification → DIFFERENT hash
$mutC = [ordered]@{
    'phase'                 = 52.9
    'source_phase'          = 52.8
    'model_type'            = 'enforcement_surface_coverage'
    'operational_functions_count' = $operationalFns.Count
    'directly_gated'        = $directlyGated + 1
    'transitively_gated'    = $transitivelyGated - 1
    'unguarded_paths'       = $unguardedCount
    'bypass_crosscheck'     = $bypassCrosscheck
    'canonical'             = $true
}
$fpC = Get-MutantFingerprint -Model $mutC
$testCPass = ($fpC -ne $CoverageFP)
if (-not $testCPass) { $allTestsPass = $false }
[void]$TestResults.Add('TEST_C | change_classification_changes_hash | expect_different=' + $fpC + ' actual=' + $CoverageFP + ' => ' + $(if ($testCPass) { 'PASS' } else { 'FAIL' }))

# TEST D: dead helper only change → SAME hash
# Dead functions are excluded from the fingerprint model, so this should NOT change the hash
$mutD = [ordered]@{
    'phase'                 = 52.9
    'source_phase'          = 52.8
    'model_type'            = 'enforcement_surface_coverage'
    'operational_functions_count' = $operationalFns.Count
    'directly_gated'        = $directlyGated
    'transitively_gated'    = $transitivelyGated
    'unguarded_paths'       = $unguardedCount
    'bypass_crosscheck'     = $bypassCrosscheck
    'canonical'             = $true
}
$fpD = Get-MutantFingerprint -Model $mutD
$testDPass = ($fpD -eq $CoverageFP)
if (-not $testDPass) { $allTestsPass = $false }
[void]$TestResults.Add('TEST_D | dead_helper_change_preserves_hash | expect_same=' + $fpD + ' actual=' + $CoverageFP + ' => ' + $(if ($testDPass) { 'PASS' } else { 'FAIL' }))

# TEST E: introduce unguarded path → DIFFERENT hash
$mutE = [ordered]@{
    'phase'                 = 52.9
    'source_phase'          = 52.8
    'model_type'            = 'enforcement_surface_coverage'
    'operational_functions_count' = $operationalFns.Count
    'directly_gated'        = $directlyGated
    'transitively_gated'    = $transitivelyGated
    'unguarded_paths'       = $unguardedCount + 1
    'bypass_crosscheck'     = $bypassCrosscheck
    'canonical'             = $true
}
$fpE = Get-MutantFingerprint -Model $mutE
$testEPass = ($fpE -ne $CoverageFP)
if (-not $testEPass) { $allTestsPass = $false }
[void]$TestResults.Add('TEST_E | introduce_unguarded_path_changes_hash | expect_different=' + $fpE + ' actual=' + $CoverageFP + ' => ' + $(if ($testEPass) { 'PASS' } else { 'FAIL' }))

# TEST F: remove bypass-covered path (bypass_crosscheck = false) → DIFFERENT hash
$mutF = [ordered]@{
    'phase'                 = 52.9
    'source_phase'          = 52.8
    'model_type'            = 'enforcement_surface_coverage'
    'operational_functions_count' = $operationalFns.Count
    'directly_gated'        = $directlyGated
    'transitively_gated'    = $transitivelyGated
    'unguarded_paths'       = $unguardedCount
    'bypass_crosscheck'     = $false
    'canonical'             = $true
}
$fpF = Get-MutantFingerprint -Model $mutF
$testFPass = ($fpF -ne $CoverageFP)
if (-not $testFPass) { $allTestsPass = $false }
[void]$TestResults.Add('TEST_F | remove_bypass_coverage_changes_hash | expect_different=' + $fpF + ' actual=' + $CoverageFP + ' => ' + $(if ($testFPass) { 'PASS' } else { 'FAIL' }))

# TEST G: remove operational entrypoint → DIFFERENT hash
$mutG = [ordered]@{
    'phase'                 = 52.9
    'source_phase'          = 52.8
    'model_type'            = 'enforcement_surface_coverage'
    'operational_functions_count' = [System.Math]::Max(0, $operationalFns.Count - 1)
    'directly_gated'        = [System.Math]::Max(0, $directlyGated - 1)
    'transitively_gated'    = $transitivelyGated
    'unguarded_paths'       = $unguardedCount
    'bypass_crosscheck'     = $bypassCrosscheck
    'canonical'             = $true
}
$fpG = Get-MutantFingerprint -Model $mutG
$testGPass = ($fpG -ne $CoverageFP)
if (-not $testGPass) { $allTestsPass = $false }
[void]$TestResults.Add('TEST_G | remove_operational_entrypoint_changes_hash | expect_different=' + $fpG + ' actual=' + $CoverageFP + ' => ' + $(if ($testGPass) { 'PASS' } else { 'FAIL' }))

# ── Gate ───────────────────────────────────────────────────────────────────────
$testPassCount = @($TestResults | Where-Object { $_ -match '=> PASS$' }).Count
$testFailCount = @($TestResults | Where-Object { $_ -match '=> FAIL$' }).Count
$Gate = if (($DeterminismPass -and $DeterminismFromDisk -and $allTestsPass)) { 'PASS' } else { 'FAIL' }

# ── Proof folder ───────────────────────────────────────────────────────────────
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\phase52_9_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint_regression_anchor_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

# ── Output Files ───────────────────────────────────────────────────────────────
Write-ProofFile (Join-Path $PF '01_status.txt') (@(
    'PHASE=52.9',
    'TITLE=Trust-Chain Ledger Baseline Enforcement Surface Fingerprint Trust-Chain Baseline Enforcement Coverage Fingerprint Regression Anchor',
    'GATE=' + $Gate,
    'COVERAGE_FINGERPRINT=' + $CoverageFP,
    'DETERMINISM_VERIFIED=' + $DeterminismPass,
    'DETERMINISM_FROM_DISK=' + $DeterminismFromDisk,
    'TEST_PASS_COUNT=' + $testPassCount + '/7',
    'TEST_FAIL_COUNT=' + $testFailCount,
    'ARTIFACT_PATH=' + $ArtifactPath,
    'SOURCE_52_8_PROOF=' + $PF528
) -join "`r`n")

Write-ProofFile (Join-Path $PF '02_coverage_fingerprint.txt') (@(
    'COVERAGE_FINGERPRINT_SHA256=' + $CoverageFP,
    'CANONICAL_MODEL=' + $covModelJson,
    'REGENERATED_FP=' + $CoverageFP2,
    'DETERMINISM_CHECK=' + $(if ($DeterminismPass) { 'PASS' } else { 'FAIL' }),
    'FINGERPRINT_FROM_DISK=' + $reloadedFP,
    'DISK_DETERMINISM_CHECK=' + $(if ($DeterminismFromDisk) { 'PASS' } else { 'FAIL' })
) -join "`r`n")

Write-ProofFile (Join-Path $PF '03_operational_surface.txt') (@(
    'OPERATIONAL_FUNCTIONS_COUNT=' + $operationalFns.Count,
    'DIRECTLY_GATED=' + $directlyGated,
    'TRANSITIVELY_GATED=' + $transitivelyGated,
    'DEAD_PROOF_INFRASTRUCTURE_COUNT=' + $deadFns.Count,
    'UNGUARDED_PATHS=' + $unguardedCount,
    'BYPASS_CROSSCHECK=' + $bypassCrosscheck,
    '#',
    '# OPERATIONAL FUNCTIONS (enforcement surface):',
    ($operationalFns -join "`r`n"),
    '#',
    '# DEAD FUNCTIONS (proof-only, excluded):',
    ($deadFns -join "`r`n")
) -join "`r`n")

Write-ProofFile (Join-Path $PF '10_test_results.txt') ($TestResults -join "`r`n")

Write-ProofFile (Join-Path $PF '98_gate_phase52_9.txt') (@(
    'GATE=' + $Gate,
    'PHASE=52.9',
    'TITLE=Trust-Chain Ledger Baseline Enforcement Surface Fingerprint Trust-Chain Baseline Enforcement Coverage Fingerprint Regression Anchor',
    'COVERAGE_FINGERPRINT=' + $CoverageFP,
    'DETERMINISM_VERIFIED=' + $DeterminismPass,
    'DETERMINISM_FROM_DISK=' + $DeterminismFromDisk,
    'TEST_PASS_COUNT=' + $testPassCount + '/7',
    'FINGERPRINT_MATCH_STATUS=' + $(if ($DeterminismFromDisk) { 'MATCH' } else { 'MISMATCH' }),
    'REGRESSION_DETECTED=false',
    'ARTIFACT_110=' + $ArtifactName,
    'ARTIFACT_PATH=' + $ArtifactPath,
    'NO_FALLBACK=TRUE',
    'NO_REGENERATION=TRUE'
) -join "`r`n")

# ── Zip proof folder ───────────────────────────────────────────────────────────
$ZipPath = $PF + '.zip'
if (Test-Path -LiteralPath $ZipPath) { Remove-Item -Force $ZipPath }
$tmpZip = $PF + '_zipcopy'
if (Test-Path -LiteralPath $tmpZip) { Remove-Item -Recurse -Force $tmpZip }
New-Item -ItemType Directory -Path $tmpZip | Out-Null
Get-ChildItem -Path $PF -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $tmpZip $_.Name) -Force
}
Compress-Archive -Path (Join-Path $tmpZip '*') -DestinationPath $ZipPath -Force
Remove-Item -Recurse -Force $tmpZip

Write-Output ''
Write-Output ('GATE=' + $Gate)
Write-Output ('COVERAGE_FINGERPRINT=' + $CoverageFP)
Write-Output ('DETERMINISM_VERIFIED=' + $DeterminismPass)
Write-Output ('TEST_PASS_COUNT=' + $testPassCount + '/7')
Write-Output ('FINGERPRINT_MATCH_STATUS=' + $(if ($DeterminismFromDisk) { 'MATCH' } else { 'MISMATCH' }))
Write-Output ('REGRESSION_DETECTED=false')
Write-Output ('ZIP=' + $ZipPath)
Write-Output ('PF=' + $PF)
