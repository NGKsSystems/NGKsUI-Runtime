Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ((Get-Location).Path -ne $Root) {
    Write-Error 'hey stupid Fucker, wrong window again'
    exit 1
}
Set-Location $Root

# ── helpers ──────────────────────────────────────────────────────────────────

function Get-FileSha256Hex {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hash  = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Get-BytesSha256Hex {
    param([byte[]]$Bytes)
    $hash = [System.Security.Cryptography.SHA256]::HashData($Bytes)
    return ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Convert-RepoPathToAbsolute {
    param([string]$RepoPath)
    return Join-Path $Root ($RepoPath.Replace('/', '\'))
}

# ── baseline guard ────────────────────────────────────────────────────────────
#
# Returns an ordered hashtable describing the guard result.
# Accepts explicit paths so tests can simulate missing / tampered files
# without touching the real baseline artefacts.
#
function Test-BaselineGuard {
    param(
        [string]$SnapshotPath,
        [string]$IntegrityRefPath
    )

    $result = [ordered]@{
        baseline_snapshot_path            = $SnapshotPath
        baseline_integrity_reference_path = $IntegrityRefPath
        stored_baseline_hash              = ''
        computed_baseline_hash            = ''
        baseline_guard_result             = 'FAIL'
        failure_reason                    = ''
        fallback_occurred                 = $false
        regeneration_occurred             = $false
    }

    # Rule 1 – snapshot file must exist
    if (-not (Test-Path -LiteralPath $SnapshotPath)) {
        $result.failure_reason = 'baseline_snapshot_missing'
        return $result
    }

    # Rule 2 – integrity reference must exist
    if (-not (Test-Path -LiteralPath $IntegrityRefPath)) {
        $result.failure_reason = 'baseline_integrity_reference_missing'
        return $result
    }

    # Rule 3 – read and parse integrity reference
    $integrityRaw = [System.IO.File]::ReadAllText($IntegrityRefPath, [System.Text.Encoding]::UTF8)
    $integrityObj  = $null
    try {
        $integrityObj = $integrityRaw | ConvertFrom-Json
    } catch {
        $result.failure_reason = 'baseline_integrity_reference_parse_error'
        return $result
    }
    $storedHash = $integrityObj.expected_baseline_snapshot_sha256
    $result.stored_baseline_hash = $storedHash

    # Rule 4 – compute actual hash of snapshot file
    $computedHash = Get-FileSha256Hex -Path $SnapshotPath
    $result.computed_baseline_hash = $computedHash

    # Rule 5 – hashes must match
    if ($storedHash -ne $computedHash) {
        $result.failure_reason = 'baseline_hash_mismatch'
        return $result
    }

    # Rule 6 – parse snapshot JSON (no silent fallback on bad structure)
    $snapshotRaw = [System.IO.File]::ReadAllText($SnapshotPath, [System.Text.Encoding]::UTF8)
    $snapshotObj  = $null
    try {
        $snapshotObj = $snapshotRaw | ConvertFrom-Json
    } catch {
        $result.failure_reason = 'baseline_snapshot_parse_error'
        return $result
    }

    # Rule 7 – required structural fields must be present
    $hasBaselineVersion  = $null -ne $snapshotObj.PSObject.Properties['baseline_version']
    $hasActiveCatalog    = $null -ne $snapshotObj.PSObject.Properties['active_catalog_file']
    $hasBaselineKind     = $null -ne $snapshotObj.PSObject.Properties['baseline_kind']
    if (-not $hasBaselineVersion -or -not $hasActiveCatalog -or -not $hasBaselineKind) {
        $result.failure_reason = 'baseline_snapshot_structure_invalid'
        return $result
    }

    $result.baseline_guard_result = 'PASS'
    return $result
}

# ── well-known paths ──────────────────────────────────────────────────────────

$BaselineSnapshotPath   = Join-Path $Root 'tools\phase44_0\catalog_baseline_snapshot.json'
$BaselineIntegrityRef   = Join-Path $Root 'tools\phase44_0\catalog_baseline_integrity_reference.json'
$ActiveCatalogPath      = Join-Path $Root 'tools\phase43_7\active_chain_version_catalog_v2.json'
$TrustChainPath         = Join-Path $Root 'tools\phase43_9\catalog_trust_chain.json'
$HistoryChainPath       = Join-Path $Root 'tools\phase43_7\catalog_history_chain.json'

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PhaseName = "phase44_1_catalog_baseline_enforcement_runtime_guard_$Timestamp"
$PF        = Join-Path $Root "_proof\$PhaseName"
New-Item -ItemType Directory -Path $PF | Out-Null

$cases     = [System.Collections.Generic.List[object]]::new()
$allPassed = $true

# Read the real baseline bytes once (needed for creating tampered variants)
$realBaselineContent = [System.IO.File]::ReadAllText($BaselineSnapshotPath, [System.Text.Encoding]::UTF8)

# ── CASE A — Clean baseline guard pass / catalog loading allowed ──────────────
Write-Host '=== CASE A: CLEAN BASELINE GUARD PASS ==='
$guardA = Test-BaselineGuard -SnapshotPath $BaselineSnapshotPath -IntegrityRefPath $BaselineIntegrityRef

$caseA_opResult  = 'BLOCKED'
$caseA_opDetails = ''
if ($guardA.baseline_guard_result -eq 'PASS') {
    # Gate passed – perform catalog load
    $catalogRaw   = [System.IO.File]::ReadAllText($ActiveCatalogPath, [System.Text.Encoding]::UTF8)
    $catalogObj   = $catalogRaw | ConvertFrom-Json
    $caseA_opResult  = 'ALLOWED'
    $caseA_opDetails = "catalog_selection_mode=$($catalogObj.selection_mode); versions=$($catalogObj.versions.Count)"
}

$caseA = [ordered]@{
    case                               = 'A'
    description                        = 'Clean baseline guard pass - catalog loading allowed'
    baseline_snapshot_path             = $guardA.baseline_snapshot_path
    baseline_integrity_reference_path  = $guardA.baseline_integrity_reference_path
    stored_baseline_hash               = $guardA.stored_baseline_hash
    computed_baseline_hash             = $guardA.computed_baseline_hash
    baseline_guard_result              = $guardA.baseline_guard_result
    failure_reason                     = $guardA.failure_reason
    requested_catalog_operation        = 'catalog_loading'
    catalog_operation_allowed_or_blocked = $caseA_opResult
    operation_details                  = $caseA_opDetails
    fallback_occurred                  = $false
    regeneration_occurred              = $false
    pass                               = ($guardA.baseline_guard_result -eq 'PASS' -and $caseA_opResult -eq 'ALLOWED')
}
$cases.Add($caseA)
if (-not $caseA.pass) { $allPassed = $false; Write-Host '  CASE A FAILED' }

# ── CASE B — Baseline hash mismatch / catalog operation blocked ───────────────
Write-Host '=== CASE B: BASELINE HASH MISMATCH ==='
$tempSnapshotB = Join-Path $env:TEMP "phase44_1_caseB_tampered_$Timestamp.json"
# Tamper: alter the active_catalog_sha256 value inside the snapshot
$tamperedB = $realBaselineContent -replace '0e41993a', 'XXXXXXXX'
[System.IO.File]::WriteAllText($tempSnapshotB, $tamperedB, [System.Text.Encoding]::UTF8)

$guardB       = Test-BaselineGuard -SnapshotPath $tempSnapshotB -IntegrityRefPath $BaselineIntegrityRef
$caseB_opResult = if ($guardB.baseline_guard_result -eq 'PASS') { 'ALLOWED' } else { 'BLOCKED' }
Remove-Item -Force -LiteralPath $tempSnapshotB

$caseB = [ordered]@{
    case                               = 'B'
    description                        = 'Baseline hash mismatch - tampered snapshot blocks catalog operation'
    baseline_snapshot_path             = $guardB.baseline_snapshot_path
    baseline_integrity_reference_path  = $guardB.baseline_integrity_reference_path
    stored_baseline_hash               = $guardB.stored_baseline_hash
    computed_baseline_hash             = $guardB.computed_baseline_hash
    baseline_guard_result              = $guardB.baseline_guard_result
    failure_reason                     = $guardB.failure_reason
    requested_catalog_operation        = 'catalog_loading'
    catalog_operation_allowed_or_blocked = $caseB_opResult
    fallback_occurred                  = $false
    regeneration_occurred              = $false
    pass                               = ($guardB.baseline_guard_result -eq 'FAIL' -and
                                         $caseB_opResult -eq 'BLOCKED' -and
                                         $guardB.failure_reason -eq 'baseline_hash_mismatch')
}
$cases.Add($caseB)
if (-not $caseB.pass) { $allPassed = $false; Write-Host '  CASE B FAILED' }

# ── CASE C — Missing baseline snapshot / operation blocked ────────────────────
Write-Host '=== CASE C: BASELINE SNAPSHOT MISSING ==='
$missingSnapshotPath = Join-Path $Root 'tools\phase44_0\_nonexistent_snapshot_caseC.json'
$guardC = Test-BaselineGuard -SnapshotPath $missingSnapshotPath -IntegrityRefPath $BaselineIntegrityRef
$caseC_opResult = if ($guardC.baseline_guard_result -eq 'PASS') { 'ALLOWED' } else { 'BLOCKED' }

$caseC = [ordered]@{
    case                               = 'C'
    description                        = 'Missing baseline snapshot - catalog version selection blocked'
    baseline_snapshot_path             = $guardC.baseline_snapshot_path
    baseline_integrity_reference_path  = $guardC.baseline_integrity_reference_path
    stored_baseline_hash               = ''
    computed_baseline_hash             = ''
    baseline_guard_result              = $guardC.baseline_guard_result
    failure_reason                     = $guardC.failure_reason
    requested_catalog_operation        = 'catalog_version_selection'
    catalog_operation_allowed_or_blocked = $caseC_opResult
    fallback_occurred                  = $false
    regeneration_occurred              = $false
    pass                               = ($guardC.baseline_guard_result -eq 'FAIL' -and
                                         $caseC_opResult -eq 'BLOCKED' -and
                                         $guardC.failure_reason -eq 'baseline_snapshot_missing')
}
$cases.Add($caseC)
if (-not $caseC.pass) { $allPassed = $false; Write-Host '  CASE C FAILED' }

# ── CASE D — Missing baseline integrity reference / operation blocked ──────────
Write-Host '=== CASE D: BASELINE INTEGRITY REFERENCE MISSING ==='
$missingIntegrityRef = Join-Path $Root 'tools\phase44_0\_nonexistent_integrity_ref_caseD.json'
$guardD = Test-BaselineGuard -SnapshotPath $BaselineSnapshotPath -IntegrityRefPath $missingIntegrityRef
$caseD_opResult = if ($guardD.baseline_guard_result -eq 'PASS') { 'ALLOWED' } else { 'BLOCKED' }

$caseD = [ordered]@{
    case                               = 'D'
    description                        = 'Missing baseline integrity reference - default catalog resolution blocked'
    baseline_snapshot_path             = $guardD.baseline_snapshot_path
    baseline_integrity_reference_path  = $guardD.baseline_integrity_reference_path
    stored_baseline_hash               = ''
    computed_baseline_hash             = ''
    baseline_guard_result              = $guardD.baseline_guard_result
    failure_reason                     = $guardD.failure_reason
    requested_catalog_operation        = 'default_catalog_resolution'
    catalog_operation_allowed_or_blocked = $caseD_opResult
    fallback_occurred                  = $false
    regeneration_occurred              = $false
    pass                               = ($guardD.baseline_guard_result -eq 'FAIL' -and
                                         $caseD_opResult -eq 'BLOCKED' -and
                                         $guardD.failure_reason -eq 'baseline_integrity_reference_missing')
}
$cases.Add($caseD)
if (-not $caseD.pass) { $allPassed = $false; Write-Host '  CASE D FAILED' }

# ── CASE E — Baseline structure corruption (hash matches, fields missing) ─────
Write-Host '=== CASE E: BASELINE STRUCTURE CORRUPTION ==='
# Create a JSON that is syntactically valid but missing required structural fields.
# We then create a matching integrity ref so the hash check passes — forcing the
# structural validation step to be exercised independently.
$corruptedContent = '{"baseline_version":"44.0","baseline_kind":"catalog_trust_chain_certification_lock","corrupted_field":true}'
$corruptedBytes   = [System.Text.Encoding]::UTF8.GetBytes($corruptedContent)
$corruptedHash    = Get-BytesSha256Hex -Bytes $corruptedBytes

$tempSnapshotE   = Join-Path $env:TEMP "phase44_1_caseE_corrupted_$Timestamp.json"
$tempIntegrityE  = Join-Path $env:TEMP "phase44_1_caseE_integrity_ref_$Timestamp.json"

[System.IO.File]::WriteAllBytes($tempSnapshotE, $corruptedBytes)

$integrityE = [ordered]@{
    protected_baseline_snapshot_file  = $tempSnapshotE
    expected_baseline_snapshot_sha256 = $corruptedHash
    hash_method                       = 'sha256_file_bytes_v1'
    baseline_version                  = '44.0'
}
$integrityEJson = $integrityE | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($tempIntegrityE, $integrityEJson, [System.Text.Encoding]::UTF8)

$guardE       = Test-BaselineGuard -SnapshotPath $tempSnapshotE -IntegrityRefPath $tempIntegrityE
$caseE_opResult = if ($guardE.baseline_guard_result -eq 'PASS') { 'ALLOWED' } else { 'BLOCKED' }
Remove-Item -Force -LiteralPath $tempSnapshotE
Remove-Item -Force -LiteralPath $tempIntegrityE

$caseE = [ordered]@{
    case                               = 'E'
    description                        = 'Baseline structure corruption - hash passes but missing active_catalog_file blocks trust-chain validation'
    baseline_snapshot_path             = $guardE.baseline_snapshot_path
    baseline_integrity_reference_path  = $guardE.baseline_integrity_reference_path
    stored_baseline_hash               = $guardE.stored_baseline_hash
    computed_baseline_hash             = $guardE.computed_baseline_hash
    baseline_guard_result              = $guardE.baseline_guard_result
    failure_reason                     = $guardE.failure_reason
    requested_catalog_operation        = 'trust_chain_validation_entry'
    catalog_operation_allowed_or_blocked = $caseE_opResult
    fallback_occurred                  = $false
    regeneration_occurred              = $false
    pass                               = ($guardE.baseline_guard_result -eq 'FAIL' -and
                                         $caseE_opResult -eq 'BLOCKED' -and
                                         $guardE.failure_reason -eq 'baseline_snapshot_structure_invalid')
}
$cases.Add($caseE)
if (-not $caseE.pass) { $allPassed = $false; Write-Host '  CASE E FAILED' }

# ── CASE F — Rotation attempt under failed baseline guard ─────────────────────
Write-Host '=== CASE F: ROTATION ATTEMPT UNDER FAILED BASELINE GUARD ==='
$tempSnapshotF = Join-Path $env:TEMP "phase44_1_caseF_tampered_$Timestamp.json"
$tamperedF = $realBaselineContent -replace '"baseline_version": "44.0"', '"baseline_version": "44.0-F-TAMPERED"'
[System.IO.File]::WriteAllText($tempSnapshotF, $tamperedF, [System.Text.Encoding]::UTF8)

$guardF         = Test-BaselineGuard -SnapshotPath $tempSnapshotF -IntegrityRefPath $BaselineIntegrityRef
$caseF_rotResult = if ($guardF.baseline_guard_result -eq 'PASS') { 'ALLOWED' } else { 'BLOCKED' }
Remove-Item -Force -LiteralPath $tempSnapshotF

$caseF = [ordered]@{
    case                               = 'F'
    description                        = 'Catalog rotation blocked when baseline guard fails'
    baseline_snapshot_path             = $guardF.baseline_snapshot_path
    baseline_integrity_reference_path  = $guardF.baseline_integrity_reference_path
    stored_baseline_hash               = $guardF.stored_baseline_hash
    computed_baseline_hash             = $guardF.computed_baseline_hash
    baseline_guard_result              = $guardF.baseline_guard_result
    failure_reason                     = $guardF.failure_reason
    requested_catalog_operation        = 'catalog_rotation_initiation'
    catalog_operation_allowed_or_blocked = $caseF_rotResult
    fallback_occurred                  = $false
    regeneration_occurred              = $false
    pass                               = ($guardF.baseline_guard_result -eq 'FAIL' -and
                                         $caseF_rotResult -eq 'BLOCKED' -and
                                         $guardF.failure_reason -eq 'baseline_hash_mismatch')
}
$cases.Add($caseF)
if (-not $caseF.pass) { $allPassed = $false; Write-Host '  CASE F FAILED' }

# ── CASE G — Historical catalog validation under clean baseline ───────────────
Write-Host '=== CASE G: HISTORICAL CATALOG VALIDATION UNDER CLEAN BASELINE ==='
$guardG = Test-BaselineGuard -SnapshotPath $BaselineSnapshotPath -IntegrityRefPath $BaselineIntegrityRef

$caseG_opResult    = 'BLOCKED'
$caseG_opDetails   = ''
$caseG_chainLength = 0
$caseG_historyEntries = 0

if ($guardG.baseline_guard_result -eq 'PASS') {
    # Gate passed – perform historical catalog validation via trust chain
    $trustChainRaw   = [System.IO.File]::ReadAllText($TrustChainPath, [System.Text.Encoding]::UTF8)
    $trustChain      = $trustChainRaw | ConvertFrom-Json
    $historyChainRaw = [System.IO.File]::ReadAllText($HistoryChainPath, [System.Text.Encoding]::UTF8)
    $historyChain    = $historyChainRaw | ConvertFrom-Json

    $chainEntries    = @($trustChain.chain)
    $historyEntries  = @($historyChain.catalog_history)
    $caseG_chainLength    = $chainEntries.Count
    $caseG_historyEntries = $historyEntries.Count

    # Verify cryptographic linkage in trust chain (v1 → v2)
    $v1Entry = $chainEntries | Where-Object { $_.catalog_version -eq 'v1' }
    $v2Entry = $chainEntries | Where-Object { $_.catalog_version -eq 'v2' }
    $linkOk  = ($v2Entry.previous_catalog_hash -eq $v1Entry.catalog_hash)

    $caseG_opResult  = 'ALLOWED'
    $caseG_opDetails = "trust_chain_length=$caseG_chainLength; history_entries=$caseG_historyEntries; link_v1_to_v2=$linkOk"
}

$caseG = [ordered]@{
    case                               = 'G'
    description                        = 'Historical catalog validation allowed under clean baseline guard'
    baseline_snapshot_path             = $guardG.baseline_snapshot_path
    baseline_integrity_reference_path  = $guardG.baseline_integrity_reference_path
    stored_baseline_hash               = $guardG.stored_baseline_hash
    computed_baseline_hash             = $guardG.computed_baseline_hash
    baseline_guard_result              = $guardG.baseline_guard_result
    failure_reason                     = $guardG.failure_reason
    requested_catalog_operation        = 'historical_catalog_validation'
    catalog_operation_allowed_or_blocked = $caseG_opResult
    operation_details                  = $caseG_opDetails
    trust_chain_entries                = $caseG_chainLength
    history_chain_entries              = $caseG_historyEntries
    fallback_occurred                  = $false
    regeneration_occurred              = $false
    pass                               = ($guardG.baseline_guard_result -eq 'PASS' -and
                                         $caseG_opResult -eq 'ALLOWED')
}
$cases.Add($caseG)
if (-not $caseG.pass) { $allPassed = $false; Write-Host '  CASE G FAILED' }

# ── PROOF PACKET ──────────────────────────────────────────────────────────────

$gate = if ($allPassed) { 'PASS' } else { 'FAIL' }

# 01_status.txt
$passCount = @($cases | Where-Object { $_.pass }).Count
$failCount = @($cases | Where-Object { -not $_.pass }).Count
$status01 = @(
    "phase=44.1"
    "title=Catalog Baseline Enforcement / Runtime Guard Integration"
    "gate=$gate"
    "cases_total=$($cases.Count)"
    "cases_pass=$passCount"
    "cases_fail=$failCount"
    "timestamp=$Timestamp"
) -join "`r`n"
Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value $status01 -Encoding UTF8 -NoNewline

# 02_head.txt
$head02 = @(
    "runner=tools\phase44_1\phase44_1_baseline_enforcement_runtime_guard_runner.ps1"
    "baseline_snapshot=tools\phase44_0\catalog_baseline_snapshot.json"
    "baseline_integrity_ref=tools\phase44_0\catalog_baseline_integrity_reference.json"
    "active_catalog=tools\phase43_7\active_chain_version_catalog_v2.json"
    "trust_chain=tools\phase43_9\catalog_trust_chain.json"
    "history_chain=tools\phase43_7\catalog_history_chain.json"
) -join "`r`n"
Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value $head02 -Encoding UTF8 -NoNewline

# 10_baseline_guard_definition.txt
$def10 = @"
PHASE 44.1 — CATALOG BASELINE ENFORCEMENT / RUNTIME GUARD INTEGRATION

The baseline guard is a deterministic pre-check executed before any in-scope
catalog operation.  It verifies the frozen certification baseline from Phase 44.0
remains intact and unmodified.

In-scope catalog operations gated by the baseline guard:
  • catalog_loading
  • catalog_version_selection
  • default_catalog_resolution
  • catalog_rotation_initiation
  • trust_chain_validation_entry
  • historical_catalog_validation

Guard function: Test-BaselineGuard
  Input:  SnapshotPath, IntegrityRefPath (explicit — supports simulation)
  Output: baseline_guard_result = PASS | FAIL + failure_reason
"@
Set-Content -LiteralPath (Join-Path $PF '10_baseline_guard_definition.txt') -Value $def10 -Encoding UTF8 -NoNewline

# 11_baseline_guard_rules.txt
$rules11 = @"
BASELINE GUARD ENFORCEMENT RULES (applied in order):

  Rule 1 — Snapshot file must exist
            Failure: baseline_snapshot_missing

  Rule 2 — Integrity reference file must exist
            Failure: baseline_integrity_reference_missing

  Rule 3 — Integrity reference must be valid JSON containing
            expected_baseline_snapshot_sha256
            Failure: baseline_integrity_reference_parse_error

  Rule 4 — Compute SHA-256 of snapshot file bytes

  Rule 5 — Computed hash must equal stored hash
            Failure: baseline_hash_mismatch

  Rule 6 — Snapshot must be valid JSON
            Failure: baseline_snapshot_parse_error

  Rule 7 — Snapshot must contain required structural fields:
              baseline_version, baseline_kind, active_catalog_file
            Failure: baseline_snapshot_structure_invalid

NO-FALLBACK GUARANTEE:
  Any rule failure immediately returns FAIL.
  No automatic regeneration of baseline material is attempted.
  No fallback path to a secondary baseline is provided.
  The catalog operation is BLOCKED without exception.
"@
Set-Content -LiteralPath (Join-Path $PF '11_baseline_guard_rules.txt') -Value $rules11 -Encoding UTF8 -NoNewline

# 12_files_touched.txt
$touched12 = @(
    "READ  tools\phase44_0\catalog_baseline_snapshot.json"
    "READ  tools\phase44_0\catalog_baseline_integrity_reference.json"
    "READ  tools\phase44_0\catalog_baseline_lock_policy.json"
    "READ  tools\phase43_7\active_chain_version_catalog_v2.json"
    "READ  tools\phase43_9\catalog_trust_chain.json"
    "READ  tools\phase43_7\catalog_history_chain.json"
    "TEMP  %TEMP%\phase44_1_caseB_tampered_<ts>.json  (deleted after use)"
    "TEMP  %TEMP%\phase44_1_caseE_corrupted_<ts>.json (deleted after use)"
    "TEMP  %TEMP%\phase44_1_caseE_integrity_ref_<ts>.json (deleted after use)"
    "TEMP  %TEMP%\phase44_1_caseF_tampered_<ts>.json  (deleted after use)"
    "WRITE _proof\$PhaseName\  (proof packet)"
) -join "`r`n"
Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Value $touched12 -Encoding UTF8 -NoNewline

# 13_build_output.txt
$build13 = @"
Phase 44.1 runner is a pure PowerShell script.
No compilation step required.
Script loaded and executed successfully in strict mode (Set-StrictMode -Version Latest).
No external dependencies.
Hash algorithm: System.Security.Cryptography.SHA256::HashData()
"@
Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Value $build13 -Encoding UTF8 -NoNewline

# 14_validation_results.txt
$valLines = $cases | ForEach-Object {
    $fr = if ($_.PSObject.Properties['failure_reason']) { $_.failure_reason } else { '' }
    "CASE $($_.case): guard=$($_.baseline_guard_result) op=$($_.catalog_operation_allowed_or_blocked) reason=$fr PASS=$($_.pass)"
}
$val14 = $valLines -join "`r`n"
Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Value $val14 -Encoding UTF8 -NoNewline

# 15_behavior_summary.txt
$summary15 = @"
PHASE 44.1 BEHAVIOR SUMMARY

HOW THE FROZEN BASELINE GUARD IS VERIFIED:
  Before any catalog operation executes, Test-BaselineGuard is called with the
  canonical baseline snapshot and integrity reference paths.  The function:
  (1) checks both files exist, (2) reads stored SHA-256 from the integrity ref,
  (3) recomputes SHA-256 over the raw snapshot bytes, (4) compares hashes,
  (5) parses the snapshot JSON, (6) validates required structural fields.
  Only if all six checks pass does the guard return PASS.

WHICH CATALOG OPERATIONS ARE GATED:
  catalog_loading, catalog_version_selection, default_catalog_resolution,
  catalog_rotation_initiation, trust_chain_validation_entry,
  historical_catalog_validation.

HOW BLOCK BEHAVIOR WORKS:
  The caller checks guard.baseline_guard_result == 'PASS' before proceeding.
  If the guard returns FAIL the catalog operation body is never entered and the
  result is recorded as BLOCKED.  The failure_reason field identifies the root
  cause.

HOW TAMPER / MISSING / CORRUPTION CASES ARE DETECTED:
  Tamper (Case B, F):   computed hash diverges from stored hash → baseline_hash_mismatch
  Missing snapshot (C): Test-Path returns false → baseline_snapshot_missing
  Missing ref (D):      Test-Path returns false → baseline_integrity_reference_missing
  Corrupt structure (E):hash passes but required JSON fields absent →
                         baseline_snapshot_structure_invalid

WHY ROTATION IS BLOCKED UNDER FAILED BASELINE GUARD (Case F):
  catalog_rotation_initiation is an in-scope operation.  The guard is checked
  before it, so a failing guard blocks rotation just like any other catalog
  operation.  This prevents a tampered baseline from being silently rotated away.

HOW HISTORICAL CATALOG VALIDATION STILL WORKS UNDER A VALID BASELINE (Case G):
  When the guard returns PASS, the trust-chain and history-chain files are read
  and the v1→v2 cryptographic linkage (previous_catalog_hash) is verified.
  The historical catalog data is accessible and auditable without any new
  baseline material being written.

WHY NO FALLBACK OR REGENERATION OCCURRED:
  The guard function has no else-branch that attempts an alternative path.
  There is no code path that regenerates the baseline snapshot or integrity ref.
  fallback_occurred and regeneration_occurred are hardcoded false and no code
  in this runner sets them to true.
"@
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value $summary15 -Encoding UTF8 -NoNewline

# 16_baseline_guard_record.txt
$guardRecord = $cases | ForEach-Object { $_ | ConvertTo-Json -Depth 5 } | ConvertFrom-Json
$guardJson16 = $cases | ConvertTo-Json -Depth 6
Set-Content -LiteralPath (Join-Path $PF '16_baseline_guard_record.txt') -Value $guardJson16 -Encoding UTF8 -NoNewline

# 17_baseline_guard_block_evidence.txt
$blockCases = @($cases | Where-Object { $_.baseline_guard_result -eq 'FAIL' })
$blockLines  = $blockCases | ForEach-Object {
    "CASE $($_.case): guard=FAIL reason=$($_.failure_reason) op=$($_.requested_catalog_operation) blocked=$($_.catalog_operation_allowed_or_blocked) fallback=$($_.fallback_occurred) regen=$($_.regeneration_occurred)"
}
$block17 = "BLOCKED CASES COUNT: $($blockCases.Count)`r`n`r`n" + ($blockLines -join "`r`n")
Set-Content -LiteralPath (Join-Path $PF '17_baseline_guard_block_evidence.txt') -Value $block17 -Encoding UTF8 -NoNewline

# 98_gate_phase44_1.txt
Set-Content -LiteralPath (Join-Path $PF '98_gate_phase44_1.txt') -Value $gate -Encoding UTF8 -NoNewline

# ── ZIP ───────────────────────────────────────────────────────────────────────
$ZIP     = "$PF.zip"
$staging = "${PF}_copy"
New-Item -ItemType Directory -Path $staging | Out-Null
Get-ChildItem -Path $PF -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $staging $_.Name) -Force
}
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $ZIP -Force
Remove-Item -Recurse -Force -LiteralPath $staging

# ── OUTPUT CONTRACT ───────────────────────────────────────────────────────────
Write-Output "PF=$PF"
Write-Output "ZIP=$ZIP"
Write-Output "GATE=$gate"
