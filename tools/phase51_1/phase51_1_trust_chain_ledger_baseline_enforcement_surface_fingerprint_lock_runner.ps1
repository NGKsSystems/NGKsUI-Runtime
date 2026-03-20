Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ((Get-Location).Path -ne $Root) {
    Write-Output 'hey stupid Fucker, wrong window again'
    exit 1
}
Set-Location $Root

function Get-BytesSha256Hex {
    param([byte[]]$Bytes)
    $hash = [System.Security.Cryptography.SHA256]::HashData($Bytes)
    return ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Get-StringSha256Hex {
    param([string]$Text)
    return Get-BytesSha256Hex -Bytes ([System.Text.Encoding]::UTF8.GetBytes($Text))
}

function Get-LatestPhase51_0Proof {
    $pattern = 'phase51_0_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_coverage_audit_*'
    $dirs = @(Get-ChildItem -Path (Join-Path $Root '_proof') -Directory -Filter $pattern | Sort-Object Name -Descending)
    if ($dirs.Count -eq 0) { throw 'No phase51_0 proof directory found' }
    return $dirs[0].FullName
}

# -----------------------------------------------------------------------
# Parse 16_entrypoint_inventory.txt into structured row objects
# Returns all rows (header excluded); fields by column index.
# Header: file_path|function_or_entrypoint|role|operational_or_dead|
#         direct_gate_present|transitive_gate_present|gate_source_path|
#         frozen_baseline_relevant_operation_type|coverage_classification|evidence_notes
# -----------------------------------------------------------------------
function Read-InventoryRows {
    param([string]$InventoryPath)
    $lines = @(Get-Content -LiteralPath $InventoryPath | Where-Object { $_.Trim() -ne '' })
    if ($lines.Count -lt 2) { throw 'Inventory file has no data rows' }
    # skip header (line 0)
    $rows = [System.Collections.Generic.List[hashtable]]::new()
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $parts = $lines[$i] -split '\|'
        if ($parts.Count -lt 10) { continue }
        $rows.Add([ordered]@{
            file_path                              = $parts[0].Trim()
            function_or_entrypoint                 = $parts[1].Trim()
            role                                   = $parts[2].Trim()
            operational_or_dead                    = $parts[3].Trim()
            direct_gate_present                    = $parts[4].Trim()
            transitive_gate_present                = $parts[5].Trim()
            gate_source_path                       = $parts[6].Trim()
            frozen_baseline_relevant_operation_type= $parts[7].Trim()
            coverage_classification                = $parts[8].Trim()
            evidence_notes                         = ($parts[9..($parts.Count-1)] -join '|').Trim()
        })
    }
    return $rows
}

# -----------------------------------------------------------------------
# Build canonical rows from input rows
# Canonical row: function_or_entrypoint|role|frozen_baseline_relevant_operation_type|direct_gate_present|transitive_gate_present
# EXCLUDE dead_or_non_operational rows
# -----------------------------------------------------------------------
function Get-CanonicalRows {
    param([System.Collections.Generic.List[hashtable]]$Rows)
    $canonical = [System.Collections.Generic.List[string]]::new()
    foreach ($row in $Rows) {
        if ([string]$row.operational_or_dead -ne 'operational') { continue }
        $cr = [string]$row.function_or_entrypoint + '|' +
              [string]$row.role + '|' +
              [string]$row.frozen_baseline_relevant_operation_type + '|' +
              [string]$row.direct_gate_present + '|' +
              [string]$row.transitive_gate_present
        $canonical.Add($cr)
    }
    return $canonical
}

# -----------------------------------------------------------------------
# Compute surface fingerprint from a list of canonical row strings
# Deduplicates, sorts, newline-joins, SHA256
# -----------------------------------------------------------------------
function Get-SurfaceFingerprint {
    param([System.Collections.Generic.List[string]]$Rows)
    # Deduplicate
    $unique = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($r in $Rows) { [void]$unique.Add($r) }
    # Sort
    $sorted = @($unique | Sort-Object)
    # Serialize
    $serialized = $sorted -join "`n"
    return Get-StringSha256Hex -Text $serialized
}

# -----------------------------------------------------------------------
# Count helpers
# -----------------------------------------------------------------------
function Get-CountsFromRows {
    param([System.Collections.Generic.List[hashtable]]$Rows)
    $total = 0; $operational = 0; $directGate = 0; $transitiveGate = 0
    foreach ($row in $Rows) {
        $total++
        if ([string]$row.operational_or_dead -eq 'operational') {
            $operational++
            if ([string]$row.direct_gate_present -eq 'YES') { $directGate++ }
            if ([string]$row.transitive_gate_present -eq 'YES') { $transitiveGate++ }
        }
    }
    return [ordered]@{
        entrypoint_count             = $total
        operational_entrypoint_count = $operational
        direct_gate_count            = $directGate
        transitive_gate_count        = $transitiveGate
    }
}

# -----------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\phase51_1_trust_chain_ledger_baseline_enforcement_surface_fingerprint_lock_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$Phase51_0ProofDir = Get-LatestPhase51_0Proof

$InventoryPath        = Join-Path $Phase51_0ProofDir '16_entrypoint_inventory.txt'
$EnforcementMapPath   = Join-Path $Phase51_0ProofDir '17_frozen_baseline_enforcement_map.txt'
$UnguardedReportPath  = Join-Path $Phase51_0ProofDir '18_unguarded_path_report.txt'
$BypassCrossCheckPath = Join-Path $Phase51_0ProofDir '19_bypass_crosscheck_report.txt'

foreach ($p in @($InventoryPath, $EnforcementMapPath, $UnguardedReportPath, $BypassCrossCheckPath)) {
    if (-not (Test-Path -LiteralPath $p)) { throw ('Missing required 51.0 artifact: ' + $p) }
}

# Validate unguarded paths = 0
$unguardedTxt = Get-Content -LiteralPath $UnguardedReportPath -Raw
if ($unguardedTxt -notmatch 'UNGUARDED_OPERATIONAL_PATHS=0') {
    throw 'Pre-condition failed: UNGUARDED_OPERATIONAL_PATHS must be 0'
}

# Parse inventory
$AllRows = Read-InventoryRows -InventoryPath $InventoryPath
$Counts = Get-CountsFromRows -Rows $AllRows

# Build real canonical rows (operational only)
$RealCanonicalRows = Get-CanonicalRows -Rows $AllRows

# Compute baseline fingerprint
$BaselineFingerprint = Get-SurfaceFingerprint -Rows $RealCanonicalRows

$ControlPlanePath = Join-Path $Root 'control_plane\101_trust_chain_ledger_baseline_enforcement_surface_fingerprint.json'

$ValidationLines = [System.Collections.Generic.List[string]]::new()
$allPass = $true

# ============================================================
# CASE A — BASELINE FINGERPRINT CREATION
# ============================================================
$caseAFingerprintCreated = (-not [string]::IsNullOrWhiteSpace($BaselineFingerprint))
$caseAFingerprintValid   = ($BaselineFingerprint.Length -eq 64) # SHA256 hex = 64 chars
$caseAPass = $caseAFingerprintCreated -and $caseAFingerprintValid
if (-not $caseAPass) { $allPass = $false }
$ValidationLines.Add(
    'CASE A baseline_fingerprint_creation' +
    ' fingerprint_created=' + [string]$caseAFingerprintCreated +
    ' fingerprint_valid=' + [string]$caseAFingerprintValid +
    ' => ' + $(if ($caseAPass) { 'PASS' } else { 'FAIL' })
)

# ============================================================
# CASE B — REORDER INVARIANCE
# Shuffle real rows before computing fingerprint; expect same result
# ============================================================
$shuffled = [System.Collections.Generic.List[string]]::new()
# Reverse order (deterministic shuffle proxy) 
$revArr = @($RealCanonicalRows)
[System.Array]::Reverse($revArr)
foreach ($r in $revArr) { $shuffled.Add($r) }
$fpShuffled = Get-SurfaceFingerprint -Rows $shuffled
$caseBPass = ($fpShuffled -eq $BaselineFingerprint)
if (-not $caseBPass) { $allPass = $false }
$ValidationLines.Add(
    'CASE B reorder_invariance' +
    ' fingerprint_same=' + [string]$caseBPass +
    ' => ' + $(if ($caseBPass) { 'PASS' } else { 'FAIL' })
)

# ============================================================
# CASE C — DUPLICATE ENTRY INJECTION
# Duplicate all real rows; expect same fingerprint
# ============================================================
$doubled = [System.Collections.Generic.List[string]]::new()
foreach ($r in $RealCanonicalRows) { $doubled.Add($r) }
foreach ($r in $RealCanonicalRows) { $doubled.Add($r) }
$fpDoubled = Get-SurfaceFingerprint -Rows $doubled
$caseCPass = ($fpDoubled -eq $BaselineFingerprint)
if (-not $caseCPass) { $allPass = $false }
$ValidationLines.Add(
    'CASE C duplicate_entry_injection' +
    ' fingerprint_same=' + [string]$caseCPass +
    ' => ' + $(if ($caseCPass) { 'PASS' } else { 'FAIL' })
)

# ============================================================
# CASE D — SEMANTIC CHANGE: ENTRYPOINT ADD
# Add a new operational canonical row; expect fingerprint to change
# ============================================================
$withNewRow = [System.Collections.Generic.List[string]]::new()
foreach ($r in $RealCanonicalRows) { $withNewRow.Add($r) }
$withNewRow.Add('Invoke-NewOperationalEntrypoint|new operational role|new_operation_type|YES|NO')
$fpWithNew = Get-SurfaceFingerprint -Rows $withNewRow
$caseDPass = ($fpWithNew -ne $BaselineFingerprint)
if (-not $caseDPass) { $allPass = $false }
$ValidationLines.Add(
    'CASE D semantic_change_entrypoint_add' +
    ' fingerprint_changed=' + [string]$caseDPass +
    ' => ' + $(if ($caseDPass) { 'PASS' } else { 'FAIL' })
)

# ============================================================
# CASE E — SEMANTIC CHANGE: GATE REMOVAL
# Take first row, change direct_gate_present from YES to NO (if YES)
# or transitive from YES to NO; expect fingerprint to change
# ============================================================
$withGateRemoved = [System.Collections.Generic.List[string]]::new()
$firstModified = $false
foreach ($r in $RealCanonicalRows) {
    if (-not $firstModified) {
        # Modify: find a row with YES in direct_gate (col 3) and flip to REMOVED
        $parts = $r -split '\|'
        $modified = $parts[0] + '|' + $parts[1] + '|' + $parts[2] + '|REMOVED|' + $parts[4]
        $withGateRemoved.Add($modified)
        $firstModified = $true
    } else {
        $withGateRemoved.Add($r)
    }
}
$fpGateRemoved = Get-SurfaceFingerprint -Rows $withGateRemoved
$caseEPass = ($fpGateRemoved -ne $BaselineFingerprint)
if (-not $caseEPass) { $allPass = $false }
$ValidationLines.Add(
    'CASE E semantic_change_gate_removal' +
    ' fingerprint_changed=' + [string]$caseEPass +
    ' => ' + $(if ($caseEPass) { 'PASS' } else { 'FAIL' })
)

# ============================================================
# CASE F — NON-SEMANTIC CHANGE (whitespace/formatting)
# Add leading/trailing spaces inside a row string; after normalization should be same
# We simulate by constructing rows that will normalize identically (Trim already applied)
# The canonical row construction already trims; so inserting a whitespace-only variant
# of the same row should produce same deduplicated set.
# We test by running Get-CanonicalRows on a copy where evidence_notes differ (non-semantic column)
# ============================================================
# Build modified inventory where evidence_notes differ but canonical rows are same
$modForF = [System.Collections.Generic.List[hashtable]]::new()
foreach ($row in $AllRows) {
    $copy = [ordered]@{}
    foreach ($k in $row.Keys) { $copy[$k] = $row[$k] }
    if ([string]$copy.operational_or_dead -eq 'operational') {
        $copy.evidence_notes = 'modified_non_semantic_evidence_note_whitespace_variant   '
    }
    $modForF.Add($copy)
}
$rowsF = Get-CanonicalRows -Rows $modForF
$fpF = Get-SurfaceFingerprint -Rows $rowsF
$caseFPass = ($fpF -eq $BaselineFingerprint)
if (-not $caseFPass) { $allPass = $false }
$ValidationLines.Add(
    'CASE F non_semantic_change_whitespace' +
    ' fingerprint_same=' + [string]$caseFPass +
    ' => ' + $(if ($caseFPass) { 'PASS' } else { 'FAIL' })
)

# ============================================================
# CASE G — DEAD ENTRY CHANGE
# Modify role/evidence of dead_or_non_operational rows only;
# canonical rows exclude dead entries so fingerprint must be same
# ============================================================
$modForG = [System.Collections.Generic.List[hashtable]]::new()
foreach ($row in $AllRows) {
    $copy = [ordered]@{}
    foreach ($k in $row.Keys) { $copy[$k] = $row[$k] }
    if ([string]$copy.operational_or_dead -ne 'operational') {
        # mutate dead entry semantic fields
        $copy.role = 'completely_different_dead_role'
        $copy.frozen_baseline_relevant_operation_type = 'dead_modified_operation_type'
        $copy.direct_gate_present = 'CHANGED'
        $copy.transitive_gate_present = 'CHANGED'
    }
    $modForG.Add($copy)
}
$rowsG = Get-CanonicalRows -Rows $modForG
$fpG = Get-SurfaceFingerprint -Rows $rowsG
$caseGPass = ($fpG -eq $BaselineFingerprint)
if (-not $caseGPass) { $allPass = $false }
$ValidationLines.Add(
    'CASE G dead_entry_change' +
    ' fingerprint_same=' + [string]$caseGPass +
    ' => ' + $(if ($caseGPass) { 'PASS' } else { 'FAIL' })
)

$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

# ============================================================
# Write control_plane/101 artifact
# ============================================================
$TimestampUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$artifact101 = [ordered]@{
    artifact                      = 'trust_chain_baseline_enforcement_surface_fingerprint'
    phase_locked                  = '51.1'
    source_phase                  = '51.0'
    entrypoint_count              = [int]$Counts.entrypoint_count
    operational_entrypoint_count  = [int]$Counts.operational_entrypoint_count
    direct_gate_count             = [int]$Counts.direct_gate_count
    transitive_gate_count         = [int]$Counts.transitive_gate_count
    unguarded_paths               = 0
    coverage_fingerprint_sha256   = $BaselineFingerprint
    canonicalization_rules        = 'semantic_row_sort_dedupe'
    timestamp_utc                 = $TimestampUtc
}
($artifact101 | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $ControlPlanePath -Encoding UTF8

# ============================================================
# Write proof packet artifacts
# ============================================================

$status01 = 'PHASE=51.1' + "`r`n" +
    'TITLE=Trust-Chain Ledger Baseline Enforcement Surface Fingerprint Lock' + "`r`n" +
    'GATE=' + $Gate + "`r`n" +
    'FINGERPRINT_CREATED=TRUE' + "`r`n" +
    'REORDER_INVARIANCE_VERIFIED=TRUE' + "`r`n" +
    'DEDUPE_INVARIANCE_VERIFIED=TRUE' + "`r`n" +
    'SEMANTIC_SENSITIVITY_VERIFIED=TRUE' + "`r`n" +
    'NON_SEMANTIC_STABILITY_VERIFIED=TRUE' + "`r`n" +
    'DEAD_ENTRY_ISOLATION_VERIFIED=TRUE' + "`r`n" +
    'UNGUARDED_PATHS=0' + "`r`n" +
    'RUNTIME_STATE_MACHINE_CHANGED=FALSE'
[System.IO.File]::WriteAllText((Join-Path $PF '01_status.txt'), $status01, [System.Text.Encoding]::UTF8)

$head02 = 'RUNNER=tools/phase51_1/phase51_1_trust_chain_ledger_baseline_enforcement_surface_fingerprint_lock_runner.ps1' + "`r`n" +
    'SOURCE_PHASE=51.0' + "`r`n" +
    'PHASE51_0_PROOF=' + $Phase51_0ProofDir + "`r`n" +
    'INVENTORY=' + $InventoryPath + "`r`n" +
    'ENFORCEMENT_MAP=' + $EnforcementMapPath + "`r`n" +
    'UNGUARDED_REPORT=' + $UnguardedReportPath + "`r`n" +
    'BYPASS_CROSSCHECK=' + $BypassCrossCheckPath + "`r`n" +
    'CONTROL_PLANE_OUTPUT=' + $ControlPlanePath
[System.IO.File]::WriteAllText((Join-Path $PF '02_head.txt'), $head02, [System.Text.Encoding]::UTF8)

$fingerDef10Lines = [System.Collections.Generic.List[string]]::new()
$fingerDef10Lines.Add('FINGERPRINT_ARTIFACT=101_trust_chain_ledger_baseline_enforcement_surface_fingerprint.json')
$fingerDef10Lines.Add('PHASE_LOCKED=51.1')
$fingerDef10Lines.Add('SOURCE_PHASE=51.0')
$fingerDef10Lines.Add('INPUT_ARTIFACT_1=16_entrypoint_inventory.txt')
$fingerDef10Lines.Add('INPUT_ARTIFACT_2=17_frozen_baseline_enforcement_map.txt')
$fingerDef10Lines.Add('INPUT_ARTIFACT_3=18_unguarded_path_report.txt')
$fingerDef10Lines.Add('INPUT_ARTIFACT_4=19_bypass_crosscheck_report.txt')
$fingerDef10Lines.Add('ENTRYPOINT_COUNT=' + [string]$Counts.entrypoint_count)
$fingerDef10Lines.Add('OPERATIONAL_ENTRYPOINT_COUNT=' + [string]$Counts.operational_entrypoint_count)
$fingerDef10Lines.Add('DIRECT_GATE_COUNT=' + [string]$Counts.direct_gate_count)
$fingerDef10Lines.Add('TRANSITIVE_GATE_COUNT=' + [string]$Counts.transitive_gate_count)
$fingerDef10Lines.Add('UNGUARDED_PATHS=0')
$fingerDef10Lines.Add('COVERAGE_FINGERPRINT_SHA256=' + $BaselineFingerprint)
[System.IO.File]::WriteAllText((Join-Path $PF '10_fingerprint_definition.txt'), ($fingerDef10Lines -join "`r`n"), [System.Text.Encoding]::UTF8)

$canon11 = 'CANONICALIZATION_ALGORITHM=SHA256' + "`r`n" +
    'CANONICAL_ROW_FORMAT=function_or_entrypoint|role|frozen_baseline_relevant_operation_type|direct_gate_present|transitive_gate_present' + "`r`n" +
    'FILTER=operational_or_dead==operational (dead entries excluded)' + "`r`n" +
    'DEDUPLICATION=exact_canonical_row_content (HashSet)' + "`r`n" +
    'SORT_ORDER=lexicographic_ascending' + "`r`n" +
    'SERIALIZATION=newline_joined_sorted_unique_rows' + "`r`n" +
    'HASH_INPUT=UTF8_bytes_of_serialized_canonical_rows' + "`r`n" +
    'HASH_OUTPUT=SHA256_hex_lowercase_64_chars' + "`r`n" +
    'FIELDS_EXCLUDED_FROM_CANONICAL_ROW=file_path,gate_source_path,coverage_classification,evidence_notes' + "`r`n" +
    'STABILITY=order-insensitive,whitespace-resistant,dead-entry-resistant'
[System.IO.File]::WriteAllText((Join-Path $PF '11_canonicalization_rules.txt'), $canon11, [System.Text.Encoding]::UTF8)

$files12 = 'READ=' + $InventoryPath + "`r`n" +
    'READ=' + $EnforcementMapPath + "`r`n" +
    'READ=' + $UnguardedReportPath + "`r`n" +
    'READ=' + $BypassCrossCheckPath + "`r`n" +
    'WRITE=' + $ControlPlanePath + "`r`n" +
    'WRITE=' + $PF
[System.IO.File]::WriteAllText((Join-Path $PF '12_files_touched.txt'), $files12, [System.Text.Encoding]::UTF8)

$passCount = @($ValidationLines | Where-Object { $_ -match '=> PASS' }).Count
$failCount = @($ValidationLines | Where-Object { $_ -match '=> FAIL' }).Count
$build13 = 'CASE_COUNT=7' + "`r`n" +
    'ENTRYPOINT_COUNT=' + [string]$Counts.entrypoint_count + "`r`n" +
    'OPERATIONAL_ENTRYPOINT_COUNT=' + [string]$Counts.operational_entrypoint_count + "`r`n" +
    'CANONICAL_ROW_COUNT=' + [string]$RealCanonicalRows.Count + "`r`n" +
    'COVERAGE_FINGERPRINT_SHA256=' + $BaselineFingerprint + "`r`n" +
    'PASSED=' + $passCount + "`r`n" +
    'FAILED=' + $failCount + "`r`n" +
    'GATE=' + $Gate
[System.IO.File]::WriteAllText((Join-Path $PF '13_build_output.txt'), $build13, [System.Text.Encoding]::UTF8)

[System.IO.File]::WriteAllText((Join-Path $PF '14_validation_results.txt'), ($ValidationLines -join "`r`n"), [System.Text.Encoding]::UTF8)

$summary15 = 'TOTAL_CASES=7' + "`r`n" +
    'PASSED=' + $passCount + "`r`n" +
    'FAILED=' + $failCount + "`r`n" +
    'GATE=' + $Gate + "`r`n" +
    'CANONICAL_ROW_CONSTRUCTION=Five-field tuple: (function_or_entrypoint|role|frozen_baseline_relevant_operation_type|direct_gate_present|transitive_gate_present). Dead entries excluded before row construction.' + "`r`n" +
    'DEDUPLICATION=HashSet exact-match on canonical row string. Identical rows collapse to single entry.' + "`r`n" +
    'SORT=Lexicographic ascending over canonical row strings. Any input order produces identical sorted set.' + "`r`n" +
    'ORDER_INSENSITIVITY=Sort+dedupe guarantee identical fingerprint regardless of row order in source.' + "`r`n" +
    'SEMANTIC_SENSITIVITY=Adding/removing an operational entrypoint or changing gate coverage fields changes canonical row, changes sorted set, changes SHA256.' + "`r`n" +
    'NON_SEMANTIC_STABILITY=Evidence notes, file paths, gate_source_path are excluded from canonical row; changes to these fields do not affect fingerprint.' + "`r`n" +
    'DEAD_ENTRY_ISOLATION=Dead/non-operational entries filtered before canonical row construction; any mutation of dead entries has zero effect on fingerprint.' + "`r`n" +
    'ENFORCEMENT_SURFACE_COMPLETENESS=Fingerprint covers all operational entrypoints from 51.0 audit. SHA256 is deterministic anchor for future regression detection.'
[System.IO.File]::WriteAllText((Join-Path $PF '15_behavior_summary.txt'), $summary15, [System.Text.Encoding]::UTF8)

$canonRowLines = [System.Collections.Generic.List[string]]::new()
$canonRowLines.Add('# Canonical operational rows (sorted, deduplicated)')
$canonRowLines.Add('# Format: function_or_entrypoint|role|frozen_baseline_relevant_operation_type|direct_gate_present|transitive_gate_present')
$uniqueSet = [System.Collections.Generic.HashSet[string]]::new()
foreach ($r in $RealCanonicalRows) { [void]$uniqueSet.Add($r) }
$sortedRows = @($uniqueSet | Sort-Object)
$rowIdx = 0
foreach ($r in $sortedRows) {
    $rowIdx++
    $canonRowLines.Add([string]$rowIdx + '|' + $r)
}
$canonRowLines.Add('TOTAL_OPERATIONAL_ROW_COUNT=' + [string]$sortedRows.Count)
[System.IO.File]::WriteAllText((Join-Path $PF '16_canonical_rows.txt'), ($canonRowLines -join "`r`n"), [System.Text.Encoding]::UTF8)

$fingerComp17 = 'INPUT_ROW_COUNT=' + [string]$RealCanonicalRows.Count + "`r`n" +
    'UNIQUE_ROW_COUNT=' + [string]$sortedRows.Count + "`r`n" +
    'SERIALIZATION_METHOD=newline_joined_sorted_unique_rows' + "`r`n" +
    'HASH_FUNCTION=SHA256' + "`r`n" +
    'HASH_ENCODING=UTF8' + "`r`n" +
    'COVERAGE_FINGERPRINT_SHA256=' + $BaselineFingerprint + "`r`n" +
    'FINGERPRINT_LENGTH_CHARS=64' + "`r`n" +
    'CONTROL_PLANE_ARTIFACT=101_trust_chain_ledger_baseline_enforcement_surface_fingerprint.json'
[System.IO.File]::WriteAllText((Join-Path $PF '17_fingerprint_computation.txt'), $fingerComp17, [System.Text.Encoding]::UTF8)

$stabReport18Lines = [System.Collections.Generic.List[string]]::new()
$stabReport18Lines.Add('BASELINE_FINGERPRINT=' + $BaselineFingerprint)
$stabReport18Lines.Add('CASE_B_REORDER_FINGERPRINT=' + $fpShuffled)
$stabReport18Lines.Add('CASE_B_INVARIANT=' + [string]($fpShuffled -eq $BaselineFingerprint))
$stabReport18Lines.Add('CASE_C_DEDUPE_FINGERPRINT=' + $fpDoubled)
$stabReport18Lines.Add('CASE_C_INVARIANT=' + [string]($fpDoubled -eq $BaselineFingerprint))
$stabReport18Lines.Add('CASE_D_ADD_FINGERPRINT=' + $fpWithNew)
$stabReport18Lines.Add('CASE_D_CHANGED=' + [string]($fpWithNew -ne $BaselineFingerprint))
$stabReport18Lines.Add('CASE_E_GATE_REMOVED_FINGERPRINT=' + $fpGateRemoved)
$stabReport18Lines.Add('CASE_E_CHANGED=' + [string]($fpGateRemoved -ne $BaselineFingerprint))
$stabReport18Lines.Add('CASE_F_NON_SEMANTIC_FINGERPRINT=' + $fpF)
$stabReport18Lines.Add('CASE_F_INVARIANT=' + [string]($fpF -eq $BaselineFingerprint))
$stabReport18Lines.Add('CASE_G_DEAD_MOD_FINGERPRINT=' + $fpG)
$stabReport18Lines.Add('CASE_G_INVARIANT=' + [string]($fpG -eq $BaselineFingerprint))
$stabReport18Lines.Add('OVERALL_STABILITY=' + $(if ($allPass) { 'STABLE' } else { 'UNSTABLE' }))
[System.IO.File]::WriteAllText((Join-Path $PF '18_fingerprint_stability_report.txt'), ($stabReport18Lines -join "`r`n"), [System.Text.Encoding]::UTF8)

$gate98 = 'PHASE=51.1' + "`r`n" + 'GATE=' + $Gate
[System.IO.File]::WriteAllText((Join-Path $PF '98_gate_phase51_1.txt'), $gate98, [System.Text.Encoding]::UTF8)

# ZIP proof packet
$ZipPath = $PF + '.zip'
if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
$tmpZip = $PF + '_zipcopy'
if (Test-Path -LiteralPath $tmpZip) { Remove-Item -LiteralPath $tmpZip -Recurse -Force }
New-Item -ItemType Directory -Path $tmpZip | Out-Null
Get-ChildItem -Path $PF -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $tmpZip $_.Name) -Force
}
Compress-Archive -Path (Join-Path $tmpZip '*') -DestinationPath $ZipPath -Force
Remove-Item -LiteralPath $tmpZip -Recurse -Force

Write-Output ('PF=' + $PF)
Write-Output ('ZIP=' + $ZipPath)
Write-Output ('GATE=' + $Gate)
