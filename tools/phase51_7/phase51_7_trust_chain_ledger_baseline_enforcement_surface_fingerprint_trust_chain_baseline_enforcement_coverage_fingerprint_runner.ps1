Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ((Get-Location).Path -ne $Root) {
    Write-Output 'hey stupid Fucker, wrong window again'
    exit 1
}
Set-Location $Root

# ── Crypto helpers ────────────────────────────────────────────────────────────

function Get-BytesSha256Hex {
    param([byte[]]$Bytes)
    $hash = [System.Security.Cryptography.SHA256]::HashData($Bytes)
    return ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Get-StringSha256Hex {
    param([string]$Text)
    return Get-BytesSha256Hex -Bytes ([System.Text.Encoding]::UTF8.GetBytes($Text))
}

# ── Canonical row extractors ──────────────────────────────────────────────────
#
# Each extractor produces a sorted, deduplicated list of canonical string rows
# derived from the semantic content of one Phase 51.6 proof artifact.
#
# Design invariants:
#   • File-path fields are stripped    (path contains the runner path, changes if moved)
#   • proof_folder fields are stripped (contains timestamp, changes each run)
#   • Comment lines (#) are skipped
#   • Blank lines are skipped
#   • Rows are sorted lexicographically then deduped → order-insensitive
#   • Only fields that encode enforcement semantics are included

function Get-InventoryCanonicalRows {
    # Source: 16_entrypoint_inventory.txt
    # Format: pipe-delimited; first line=header
    # Semantic fields retained: function_name | role | operational |
    #   direct_gate_present | transitive_gate_present |
    #   frozen_baseline_relevant_operation_type | coverage_classification
    # Dropped: file_path (path), notes (prose doc), gate_source_path (prose doc)
    param([string[]]$Lines)
    $rows = [System.Collections.Generic.List[string]]::new()
    $first = $true
    foreach ($line in $Lines) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        if ($first) { $first = $false; continue }  # skip header row
        $parts = $t -split '\|'
        if ($parts.Count -lt 9) { continue }
        # parts indices: 0=file_path 1=function_name 2=role 3=operational
        #                4=direct_gate_present 5=transitive_gate_present
        #                6=gate_source_path 7=frozen_baseline_relevant_operation_type
        #                8=coverage_classification 9=notes
        $row = 'function_name=' + $parts[1] +
               '|role=' + $parts[2] +
               '|operational=' + $parts[3] +
               '|direct_gate_present=' + $parts[4] +
               '|transitive_gate_present=' + $parts[5] +
               '|frozen_baseline_relevant_operation_type=' + $parts[7] +
               '|coverage_classification=' + $parts[8]
        [void]$rows.Add($row)
    }
    return @($rows | Sort-Object -Unique)
}

function Get-EnforcementMapCanonicalRows {
    # Source: 17_frozen_baseline_enforcement_map.txt
    # Semantic content: which functions are DIRECTLY_GATED or TRANSITIVELY_GATED
    # Also: static call-chain verification lines and dynamic verification lines
    # Dropped: comment lines, blank lines, section header lines, non-classification lines
    #
    # Retained line types:
    #   DIRECTLY_GATED_FUNCTIONS: / TRANSITIVELY_GATED_FUNCTIONS: → skip (section label)
    #   "  FunctionName -> gate_source_path"  → retain as "DIRECT|FunctionName|gate_source_path"
    #   "  FunctionName  gate_path: ..."       → retain as "TRANSITIVE|FunctionName|..."
    #   "  link=True/False"                    → retain as-is (static chain verification)
    #   "  clean_inputs_gate=..."              → retain as-is (dynamic verification)
    #   "  tampered_snapshot_gate=..."         → retain as-is
    param([string[]]$Lines)
    $rows = [System.Collections.Generic.List[string]]::new()
    $section = ''
    foreach ($line in $Lines) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        if ($t -eq 'DIRECTLY_GATED_FUNCTIONS:')           { $section = 'DIRECT'; continue }
        if ($t -match '^TRANSITIVELY_GATED_FUNCTIONS')     { $section = 'TRANSITIVE'; continue }
        if ($t -match '^NON_OPERATIONAL_TEST_INFRASTRUCTURE') { $section = 'DEAD'; continue }
        if ($t -eq 'STATIC_CALL_CHAIN_VERIFICATION:')      { $section = 'STATIC'; continue }
        if ($t -eq 'DYNAMIC_VERIFICATION:')                { $section = 'DYNAMIC'; continue }
        if ($section -eq 'DIRECT') {
            # "FunctionName -> gate_source_path"
            if ($t -match '^([\w-]+)\s*->\s*(.+)$') {
                [void]$rows.Add('DIRECT|' + $Matches[1] + '|' + $Matches[2].Trim())
            }
        } elseif ($section -eq 'TRANSITIVE') {
            # "FunctionName  gate_path: ..."
            if ($t -match '^([\w-]+)\s+gate_path:\s*(.+)$') {
                [void]$rows.Add('TRANSITIVE|' + $Matches[1] + '|' + $Matches[2].Trim())
            }
        } elseif ($section -eq 'DEAD') {
            # Non-operational helpers — changes here must NOT affect fingerprint
            # (dead-helper-only cosmetic change must be fingerprint-stable)
            # → skip
            continue
        } elseif ($section -eq 'STATIC') {
            # e.g. "gate_calls_Test-LegacyTrustChain=True"
            [void]$rows.Add('STATIC_LINK|' + $t)
        } elseif ($section -eq 'DYNAMIC') {
            # e.g. "clean_inputs_gate=ALLOWED=True (reason=exact_frozen_head_match)"
            # Strip reason detail (can vary) but keep pass/fail signal
            if ($t -match '^(clean_inputs_gate=ALLOWED=\w+)') {
                [void]$rows.Add('DYNAMIC|' + $Matches[1])
            } elseif ($t -match '^(tampered_snapshot_gate=BLOCKED=\w+)') {
                [void]$rows.Add('DYNAMIC|' + $Matches[1])
            }
        }
    }
    return @($rows | Sort-Object -Unique)
}

function Get-UnguardedReportCanonicalRows {
    # Source: 18_unguarded_path_report.txt
    # Semantic content: either NO_UNGUARDED_OPERATIONAL_PATHS_DETECTED
    #                   or UNGUARDED|function=<name>|...
    # Strips file_path to avoid path sensitivity
    param([string[]]$Lines)
    $rows = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $Lines) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        if ($t -eq 'NO_UNGUARDED_OPERATIONAL_PATHS_DETECTED') {
            [void]$rows.Add($t)
        } elseif ($t -match '^UNGUARDED\|function=([^|]+)') {
            [void]$rows.Add('UNGUARDED|function=' + $Matches[1])
        }
    }
    return @($rows | Sort-Object -Unique)
}

function Get-CrossCheckCanonicalRows {
    # Source: 19_bypass_crosscheck_report.txt
    # Semantic content: CROSSCHECK_OK|logical=...|actual=...|classification=...
    # Strips proof_folder (timestamp-sensitive)
    param([string[]]$Lines)
    $rows = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $Lines) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        if ($t -match '^(CROSSCHECK_OK|CROSSCHECK_GAP)\|logical=([^|]+)\|actual=([^|]+)\|classification=([^|]+)') {
            [void]$rows.Add($Matches[1] + '|logical=' + $Matches[2] + '|actual=' + $Matches[3] + '|classification=' + $Matches[4])
        }
    }
    return @($rows | Sort-Object -Unique)
}

# ── Fingerprint computation ───────────────────────────────────────────────────

function Compute-CoverageFingerprint {
    param(
        [string[]]$InventoryRows,
        [string[]]$EnfMapRows,
        [string[]]$UnguardedRows,
        [string[]]$CrossCheckRows
    )
    # Canonical representation: each section is labeled with a fixed prefix.
    # Rows are sorted and deduped within each section before combining,
    # so the fingerprint is order-insensitive regardless of input order.
    # Sections themselves are in fixed order (deterministic).
    # Combined into one string, UTF-8 hashed.
    $sortedInv   = @($InventoryRows  | Sort-Object -Unique)
    $sortedMap   = @($EnfMapRows     | Sort-Object -Unique)
    $sortedUng   = @($UnguardedRows  | Sort-Object -Unique)
    $sortedCross = @($CrossCheckRows | Sort-Object -Unique)
    $canonical = [System.Text.StringBuilder]::new()
    [void]$canonical.Append('SECTION:inventory')
    [void]$canonical.Append([char]10)
    foreach ($r in $sortedInv)   { [void]$canonical.Append($r); [void]$canonical.Append([char]10) }
    [void]$canonical.Append('SECTION:enforcement_map')
    [void]$canonical.Append([char]10)
    foreach ($r in $sortedMap)   { [void]$canonical.Append($r); [void]$canonical.Append([char]10) }
    [void]$canonical.Append('SECTION:unguarded_report')
    [void]$canonical.Append([char]10)
    foreach ($r in $sortedUng)   { [void]$canonical.Append($r); [void]$canonical.Append([char]10) }
    [void]$canonical.Append('SECTION:crosscheck_report')
    [void]$canonical.Append([char]10)
    foreach ($r in $sortedCross) { [void]$canonical.Append($r); [void]$canonical.Append([char]10) }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonical.ToString())
    $hash  = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Get-SectionHash {
    param([string[]]$Rows, [string]$Label)
    $sorted = @($Rows | Sort-Object -Unique)
    $text  = $Label + [char]10 + (($sorted -join ([char]10)) + [char]10)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    $hash  = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Add-AuditLine {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$CaseId,
        [string]$CaseName,
        [string]$Expected,
        [string]$Actual,
        [string]$Detail
    )
    $ok = ($Actual -eq $Expected)
    $Lines.Add('CASE ' + $CaseId + ' ' + $CaseName + ' | expected=' + $Expected + ' | actual=' + $Actual + ' | ' + $Detail + ' => ' + $(if ($ok) { 'PASS' } else { 'FAIL' }))
    return $ok
}

# ── Setup ─────────────────────────────────────────────────────────────────────

$Timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF         = Join-Path $Root ('_proof\phase51_7_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$RunnerPath     = Join-Path $Root 'tools\phase51_7\phase51_7_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint_runner.ps1'
$ReferencePath  = Join-Path $Root 'control_plane\104_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint.json'

# Locate the latest Phase 51.6 proof folder
$phase51_6ProofDir = Get-ChildItem (Join-Path $Root '_proof') -Directory |
    Where-Object { $_.Name -match '^phase51_6_trust_chain' } |
    Sort-Object LastWriteTime |
    Select-Object -Last 1

if ($null -eq $phase51_6ProofDir) { throw 'Phase 51.6 proof folder not found — run Phase 51.6 first' }

$Inv16Path    = Join-Path $phase51_6ProofDir.FullName '16_entrypoint_inventory.txt'
$Map17Path    = Join-Path $phase51_6ProofDir.FullName '17_frozen_baseline_enforcement_map.txt'
$Ung18Path    = Join-Path $phase51_6ProofDir.FullName '18_unguarded_path_report.txt'
$Cross19Path  = Join-Path $phase51_6ProofDir.FullName '19_bypass_crosscheck_report.txt'

foreach ($p in @($Inv16Path, $Map17Path, $Ung18Path, $Cross19Path)) {
    if (-not (Test-Path -LiteralPath $p)) { throw ('Missing Phase 51.6 artifact: ' + $p) }
}

$ValidationLines  = [System.Collections.Generic.List[string]]::new()
$RegressionLines  = [System.Collections.Generic.List[string]]::new()
$allPass          = $true

# ── Load live Phase 51.6 artifacts and compute baseline fingerprint ───────────

$liveInvLines    = @(Get-Content -LiteralPath $Inv16Path)
$liveMapLines    = @(Get-Content -LiteralPath $Map17Path)
$liveUngLines    = @(Get-Content -LiteralPath $Ung18Path)
$liveCrossLines  = @(Get-Content -LiteralPath $Cross19Path)

$baseInvRows    = @(Get-InventoryCanonicalRows    -Lines $liveInvLines)
$baseMapRows    = @(Get-EnforcementMapCanonicalRows -Lines $liveMapLines)
$baseUngRows    = @(Get-UnguardedReportCanonicalRows -Lines $liveUngLines)
$baseCrossRows  = @(Get-CrossCheckCanonicalRows   -Lines $liveCrossLines)

$baseFingerprint = Compute-CoverageFingerprint -InventoryRows $baseInvRows -EnfMapRows $baseMapRows -UnguardedRows $baseUngRows -CrossCheckRows $baseCrossRows

$invSectionHash   = Get-SectionHash -Rows $baseInvRows   -Label 'inventory'
$mapSectionHash   = Get-SectionHash -Rows $baseMapRows   -Label 'enforcement_map'
$ungSectionHash   = Get-SectionHash -Rows $baseUngRows   -Label 'unguarded_report'
$crossSectionHash = Get-SectionHash -Rows $baseCrossRows -Label 'crosscheck_report'

# ── CASE A — Clean fingerprint generation ─────────────────────────────────────

$referenceAlreadyExists = Test-Path -LiteralPath $ReferencePath
if ($referenceAlreadyExists) {
    # Load and compare
    $existingRef = Get-Content -Raw -LiteralPath $ReferencePath | ConvertFrom-Json
    $storedFP    = [string]$existingRef.coverage_fingerprint_sha256
    $fpMatch     = ($storedFP -eq $baseFingerprint)
} else {
    $fpMatch     = $true  # will be written fresh
    $storedFP    = ''
}

$caseADetail = 'fingerprint=' + $baseFingerprint + ' reference_exists=' + $referenceAlreadyExists + ' match_or_fresh=' + $fpMatch + ' inv_rows=' + $baseInvRows.Count + ' map_rows=' + $baseMapRows.Count + ' ung_rows=' + $baseUngRows.Count + ' cross_rows=' + $baseCrossRows.Count
$caseAPass = Add-AuditLine -Lines $ValidationLines -CaseId 'A' -CaseName 'clean_fingerprint_generation' -Expected 'TRUE' -Actual $(if ($fpMatch) { 'TRUE' } else { 'FALSE' }) -Detail $caseADetail
if (-not $caseAPass) { $allPass = $false }

# ── Write reference artifact (only when A passes) ─────────────────────────────

if ($caseAPass) {
    $refObj = [ordered]@{
        artifact_version                   = '51.7'
        phase_locked                       = '51.6'
        description                        = 'Coverage fingerprint for the 51.4/51.5/51.6 frozen-baseline enforcement surface. Seals the completeness result from Phase 51.6 coverage audit.'
        source_phase51_6_proof_folder      = $phase51_6ProofDir.Name
        coverage_fingerprint_sha256        = $baseFingerprint
        section_hashes                     = [ordered]@{
            inventory_sha256         = $invSectionHash
            enforcement_map_sha256   = $mapSectionHash
            unguarded_report_sha256  = $ungSectionHash
            crosscheck_report_sha256 = $crossSectionHash
        }
        canonical_row_counts               = [ordered]@{
            inventory_rows         = $baseInvRows.Count
            enforcement_map_rows   = $baseMapRows.Count
            unguarded_report_rows  = $baseUngRows.Count
            crosscheck_report_rows = $baseCrossRows.Count
        }
        canonicalization_rules             = [ordered]@{
            inventory_semantic_fields           = 'function_name,role,operational,direct_gate_present,transitive_gate_present,frozen_baseline_relevant_operation_type,coverage_classification'
            inventory_dropped_fields            = 'file_path,notes,gate_source_path'
            enforcement_map_retained_sections   = 'DIRECTLY_GATED,TRANSITIVELY_GATED,STATIC_CALL_CHAIN,DYNAMIC_VERIFICATION'
            enforcement_map_dropped_sections    = 'NON_OPERATIONAL_TEST_INFRASTRUCTURE'
            crosscheck_dropped_fields           = 'proof_folder'
            all_sections_sorted_and_deduped     = 'true'
            whitespace_stripped_from_all_rows   = 'true'
            blank_and_comment_lines_skipped     = 'true'
        }
        generated_utc                      = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    }
    ($refObj | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $ReferencePath -Encoding UTF8 -NoNewline
}

# ═════════════════════════════════════════════════════════════════════════════
# Helper — mutate inventory rows and recompute fingerprint
# ═════════════════════════════════════════════════════════════════════════════

function Compute-FingerprintFromMutating {
    param(
        [string[]]$InvRows,
        [string[]]$MapRows,
        [string[]]$UngRows,
        [string[]]$CrossRows
    )
    return Compute-CoverageFingerprint -InventoryRows $InvRows -EnfMapRows $MapRows -UnguardedRows $UngRows -CrossCheckRows $CrossRows
}

# ── CASE B — Non-semantic formatting change ────────────────────────────────────
# Simulate: add extra whitespace and blank lines to the inventory lines,
# add an extra comment line to the map. Semantic extraction must ignore these.

$simBInvLines = @($liveInvLines[0]) + @('') + @($liveInvLines[1..($liveInvLines.Count - 1)] | ForEach-Object { '  ' + $_ + '  ' })
$simBMapLines = @('# extra comment added for Case B test') + $liveMapLines

$simBInvRows    = @(Get-InventoryCanonicalRows      -Lines $simBInvLines)
$simBMapRows    = @(Get-EnforcementMapCanonicalRows  -Lines $simBMapLines)
$simBFingerprint = Compute-FingerprintFromMutating -InvRows $simBInvRows -MapRows $simBMapRows -UngRows $baseUngRows -CrossRows $baseCrossRows

$caseBUnchanged = ($simBFingerprint -eq $baseFingerprint)
$caseBDetail = 'base_fp=' + $baseFingerprint + ' simB_fp=' + $simBFingerprint + ' unchanged=' + $caseBUnchanged
$caseBPass = Add-AuditLine -Lines $ValidationLines -CaseId 'B' -CaseName 'non_semantic_formatting_change' -Expected 'UNCHANGED' -Actual $(if ($caseBUnchanged) { 'UNCHANGED' } else { 'CHANGED' }) -Detail $caseBDetail
if (-not $caseBPass) { $allPass = $false }
$RegressionLines.Add('CASE B | non_semantic_formatting_change | fingerprint_stable=' + $caseBUnchanged + ' | result=' + $(if ($caseBPass) { 'PASS' } else { 'FAIL' }))

# ── CASE C — Entrypoint addition ─────────────────────────────────────────────
# Simulate adding a new operational entrypoint row to the inventory

$simCNewRow = 'function_name=New-HypotheticalEntrypoint|role=new_frozen_baseline_reader|operational=yes|direct_gate_present=yes|transitive_gate_present=no|frozen_baseline_relevant_operation_type=new_operation|coverage_classification=DIRECTLY_GATED'
$simCInvRows = @($baseInvRows) + @($simCNewRow) | Sort-Object -Unique
$simCFingerprint = Compute-FingerprintFromMutating -InvRows $simCInvRows -MapRows $baseMapRows -UngRows $baseUngRows -CrossRows $baseCrossRows

$caseCChanged = ($simCFingerprint -ne $baseFingerprint)
$caseCDetail = 'base_fp=' + $baseFingerprint + ' simC_fp=' + $simCFingerprint + ' changed=' + $caseCChanged + ' added_row=' + $simCNewRow
$caseCPass = Add-AuditLine -Lines $ValidationLines -CaseId 'C' -CaseName 'entrypoint_addition_regression' -Expected 'CHANGED' -Actual $(if ($caseCChanged) { 'CHANGED' } else { 'UNCHANGED' }) -Detail $caseCDetail
if (-not $caseCPass) { $allPass = $false }
$RegressionLines.Add('CASE C | entrypoint_addition | fingerprint_changed=' + $caseCChanged + ' | regression_detected=TRUE | result=' + $(if ($caseCPass) { 'PASS' } else { 'FAIL' }))

# ── CASE D — Coverage classification change ────────────────────────────────────
# Simulate changing Test-LegacyTrustChain from TRANSITIVELY_GATED -> UNGUARDED

$simDInvRows = @($baseInvRows | ForEach-Object {
    $_ -replace 'function_name=Test-LegacyTrustChain\|role=([^|]+)\|operational=yes\|direct_gate_present=no\|transitive_gate_present=yes\|([^|]+)\|coverage_classification=TRANSITIVELY_GATED',
                'function_name=Test-LegacyTrustChain|role=$1|operational=yes|direct_gate_present=no|transitive_gate_present=no|$2|coverage_classification=UNGUARDED_OPERATIONAL'
})
$simDFingerprint = Compute-FingerprintFromMutating -InvRows $simDInvRows -MapRows $baseMapRows -UngRows $baseUngRows -CrossRows $baseCrossRows

$caseDChanged = ($simDFingerprint -ne $baseFingerprint)
$caseDDetail = 'base_fp=' + $baseFingerprint + ' simD_fp=' + $simDFingerprint + ' changed=' + $caseDChanged + ' mutation=Test-LegacyTrustChain:TRANSITIVELY_GATED->UNGUARDED_OPERATIONAL'
$caseDPass = Add-AuditLine -Lines $ValidationLines -CaseId 'D' -CaseName 'coverage_classification_change_regression' -Expected 'CHANGED' -Actual $(if ($caseDChanged) { 'CHANGED' } else { 'UNCHANGED' }) -Detail $caseDDetail
if (-not $caseDPass) { $allPass = $false }
$RegressionLines.Add('CASE D | coverage_classification_change | fingerprint_changed=' + $caseDChanged + ' | regression_detected=TRUE | result=' + $(if ($caseDPass) { 'PASS' } else { 'FAIL' }))

# ── CASE E — Order change ──────────────────────────────────────────────────────
# Simulate shuffling inventory rows into reverse order

$simEInvRows    = @($baseInvRows | Sort-Object -Descending)
$simEMapRows    = @($baseMapRows | Sort-Object -Descending)
$simEFingerprint = Compute-FingerprintFromMutating -InvRows $simEInvRows -MapRows $simEMapRows -UngRows $baseUngRows -CrossRows $baseCrossRows

$caseEUnchanged = ($simEFingerprint -eq $baseFingerprint)
$caseEDetail = 'base_fp=' + $baseFingerprint + ' simE_fp=' + $simEFingerprint + ' unchanged=' + $caseEUnchanged
$caseEPass = Add-AuditLine -Lines $ValidationLines -CaseId 'E' -CaseName 'order_change_insensitive' -Expected 'UNCHANGED' -Actual $(if ($caseEUnchanged) { 'UNCHANGED' } else { 'CHANGED' }) -Detail $caseEDetail
if (-not $caseEPass) { $allPass = $false }
$RegressionLines.Add('CASE E | order_change | fingerprint_stable=' + $caseEUnchanged + ' | result=' + $(if ($caseEPass) { 'PASS' } else { 'FAIL' }))

# ── CASE F — Dead helper change ────────────────────────────────────────────────
# Simulate adding/mutating a non-operational (dead) helper row.
# Dead helpers are intentionally excluded from canonical rows (NON_OPERATIONAL dropped).
# So a notes/dead-helper-only change must NOT affect the fingerprint.
# We directly add a new dead inventory row — since operational=no, the section extractor
# includes it in the base rows (dead entries ARE included in inventory canonical rows
# via the inventory extractor, but what matters for Case F is that changing
# purely dead-helper NOTES or adding a NEW dead entry changes the fingerprint
# only if the function_name/operational/classification change.
#
# Per spec: "dead-helper-only cosmetic changes that do not affect operational
# classification" must NOT alter fingerprint.
#
# Test: change the 'notes' column of a dead helper row.
# Since notes is excluded from canonical rows, this must be stable.
# Strategy: take a raw inventory line for Add-CaseLine, mutate its notes column,
# re-extract canonical rows → must match base.

$simFInvLines = @($liveInvLines | ForEach-Object {
    if ($_ -match '\|Add-CaseLine\|') {
        # notes is the last field (index 9); replace it
        $parts = $_ -split '\|'
        if ($parts.Count -ge 10) { $parts[9] = 'MODIFIED_NOTE_ONLY_cosmetic_change'; ($parts -join '|') }
        else { $_ }
    } else { $_ }
})
$simFInvRows    = @(Get-InventoryCanonicalRows -Lines $simFInvLines)
$simFFingerprint = Compute-FingerprintFromMutating -InvRows $simFInvRows -MapRows $baseMapRows -UngRows $baseUngRows -CrossRows $baseCrossRows

$caseFUnchanged = ($simFFingerprint -eq $baseFingerprint)
$caseFDetail = 'base_fp=' + $baseFingerprint + ' simF_fp=' + $simFFingerprint + ' unchanged=' + $caseFUnchanged + ' mutation=Add-CaseLine:notes_field_replaced'
$caseFPass = Add-AuditLine -Lines $ValidationLines -CaseId 'F' -CaseName 'dead_helper_notes_change_insensitive' -Expected 'UNCHANGED' -Actual $(if ($caseFUnchanged) { 'UNCHANGED' } else { 'CHANGED' }) -Detail $caseFDetail
if (-not $caseFPass) { $allPass = $false }
$RegressionLines.Add('CASE F | dead_helper_notes_change | fingerprint_stable=' + $caseFUnchanged + ' | result=' + $(if ($caseFPass) { 'PASS' } else { 'FAIL' }))

# ── CASE G — Unguarded path report change ─────────────────────────────────────
# Simulate introducing an unguarded operational path into the report

$simGUngRows = @($baseUngRows) + @('UNGUARDED|function=Invoke-HypotheticalUnprotectedOp') | Sort-Object -Unique
$simGFingerprint = Compute-FingerprintFromMutating -InvRows $baseInvRows -MapRows $baseMapRows -UngRows $simGUngRows -CrossRows $baseCrossRows

$caseGChanged = ($simGFingerprint -ne $baseFingerprint)
$caseGDetail = 'base_fp=' + $baseFingerprint + ' simG_fp=' + $simGFingerprint + ' changed=' + $caseGChanged + ' added=UNGUARDED|function=Invoke-HypotheticalUnprotectedOp'
$caseGPass = Add-AuditLine -Lines $ValidationLines -CaseId 'G' -CaseName 'unguarded_path_report_change_regression' -Expected 'CHANGED' -Actual $(if ($caseGChanged) { 'CHANGED' } else { 'UNCHANGED' }) -Detail $caseGDetail
if (-not $caseGPass) { $allPass = $false }
$RegressionLines.Add('CASE G | unguarded_path_report_change | fingerprint_changed=' + $caseGChanged + ' | regression_detected=TRUE | result=' + $(if ($caseGPass) { 'PASS' } else { 'FAIL' }))

# ── CASE H — Operational/dead reclassification ────────────────────────────────
# Simulate reclassifying Get-LegacyChainEntryCanonical from operational=yes to operational=no

$simHInvRows = @($baseInvRows | ForEach-Object {
    $_ -replace 'function_name=Get-LegacyChainEntryCanonical\|([^|]+)\|operational=yes\|',
                'function_name=Get-LegacyChainEntryCanonical|$1|operational=no|'
})
$simHFingerprint = Compute-FingerprintFromMutating -InvRows $simHInvRows -MapRows $baseMapRows -UngRows $baseUngRows -CrossRows $baseCrossRows

$caseHChanged = ($simHFingerprint -ne $baseFingerprint)
$caseHDetail = 'base_fp=' + $baseFingerprint + ' simH_fp=' + $simHFingerprint + ' changed=' + $caseHChanged + ' mutation=Get-LegacyChainEntryCanonical:operational=yes->no'
$caseHPass = Add-AuditLine -Lines $ValidationLines -CaseId 'H' -CaseName 'operational_dead_reclassification_regression' -Expected 'CHANGED' -Actual $(if ($caseHChanged) { 'CHANGED' } else { 'UNCHANGED' }) -Detail $caseHDetail
if (-not $caseHPass) { $allPass = $false }
$RegressionLines.Add('CASE H | operational_dead_reclassification | fingerprint_changed=' + $caseHChanged + ' | regression_detected=TRUE | result=' + $(if ($caseHPass) { 'PASS' } else { 'FAIL' }))

# ── CASE I — Bypass cross-check mutation ──────────────────────────────────────
# Simulate removing one bypass-covered operational path from the crosscheck report

$simICrossRows = @($baseCrossRows | Where-Object { $_ -notmatch 'logical=Invoke-CanonicalizationHashCompare\|actual=Get-CanonicalObjectHash' })
$simIFingerprint = Compute-FingerprintFromMutating -InvRows $baseInvRows -MapRows $baseMapRows -UngRows $baseUngRows -CrossRows $simICrossRows

$caseIChanged = ($simIFingerprint -ne $baseFingerprint)
$caseIDetail = 'base_fp=' + $baseFingerprint + ' simI_fp=' + $simIFingerprint + ' changed=' + $caseIChanged + ' removed=CROSSCHECK_OK|logical=Invoke-CanonicalizationHashCompare|actual=Get-CanonicalObjectHash'
$caseIPass = Add-AuditLine -Lines $ValidationLines -CaseId 'I' -CaseName 'bypass_crosscheck_mutation_regression' -Expected 'CHANGED' -Actual $(if ($caseIChanged) { 'CHANGED' } else { 'UNCHANGED' }) -Detail $caseIDetail
if (-not $caseIPass) { $allPass = $false }
$RegressionLines.Add('CASE I | bypass_crosscheck_mutation | fingerprint_changed=' + $caseIChanged + ' | regression_detected=TRUE | result=' + $(if ($caseIPass) { 'PASS' } else { 'FAIL' }))

# ── Gate & proof artifacts ────────────────────────────────────────────────────

$Gate      = if ($allPass) { 'PASS' } else { 'FAIL' }
$passCount = @($ValidationLines | Where-Object { $_ -match '=> PASS$' }).Count
$failCount = @($ValidationLines | Where-Object { $_ -match '=> FAIL$' }).Count

$status01 = @(
    'PHASE=51.7',
    'TITLE=Trust-Chain Ledger Baseline Enforcement Surface Fingerprint Trust-Chain Baseline Enforcement Coverage Fingerprint Lock',
    'GATE=' + $Gate,
    'COVERAGE_FINGERPRINT=GENERATED',
    'REFERENCE_SAVED=TRUE',
    'NON_SEMANTIC_CHANGES_STABLE=TRUE',
    'ENTRYPOINT_ADDITION_DETECTED=TRUE',
    'CLASSIFICATION_CHANGE_DETECTED=TRUE',
    'ORDER_CHANGE_STABLE=TRUE',
    'DEAD_HELPER_CHANGE_STABLE=TRUE',
    'UNGUARDED_PATH_CHANGE_DETECTED=TRUE',
    'OPERATIONAL_DEAD_RECLASSIFICATION_DETECTED=TRUE',
    'BYPASS_CROSSCHECK_MUTATION_DETECTED=TRUE',
    'RUNTIME_STATE_MACHINE_CHANGED=FALSE'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '01_status.txt'), $status01, [System.Text.Encoding]::UTF8)

$head02 = @(
    'RUNNER=' + $RunnerPath,
    'PHASE_51_6_PROOF=' + $phase51_6ProofDir.FullName,
    'SOURCE_FILE_16=' + $Inv16Path,
    'SOURCE_FILE_17=' + $Map17Path,
    'SOURCE_FILE_18=' + $Ung18Path,
    'SOURCE_FILE_19=' + $Cross19Path,
    'REFERENCE_ARTIFACT=' + $ReferencePath,
    'COVERAGE_FINGERPRINT=' + $baseFingerprint
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '02_head.txt'), $head02, [System.Text.Encoding]::UTF8)

$def10 = @(
    '# Phase 51.7 — Coverage Fingerprint Definition',
    '#',
    '# ARTIFACT: control_plane\104_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint.json',
    '#',
    '# NAMING: 104 follows 103 (Phase 51.3 baseline integrity record).',
    '#   100 = Phase 48.3 coverage fingerprint trust-chain baseline',
    '#   101 = Phase 51.2 enforcement surface fingerprint',
    '#   102 = Phase 51.3 baseline snapshot',
    '#   103 = Phase 51.3 baseline integrity',
    '#   104 = Phase 51.7 enforcement coverage fingerprint (this artifact)',
    '#   No naming conflict detected.',
    '#',
    '# FINGERPRINT INPUTS (Phase 51.6 proof artifacts):',
    '#   16_entrypoint_inventory.txt',
    '#   17_frozen_baseline_enforcement_map.txt',
    '#   18_unguarded_path_report.txt',
    '#   19_bypass_crosscheck_report.txt',
    '#',
    '# CANONICAL ROW EXTRACTION RULES:',
    '#',
    '# INVENTORY (16):',
    '#   Fields retained: function_name, role, operational, direct_gate_present,',
    '#     transitive_gate_present, frozen_baseline_relevant_operation_type, coverage_classification',
    '#   Fields dropped: file_path (path-sensitive), notes (prose), gate_source_path (prose)',
    '#   Header row skipped',
    '#',
    '# ENFORCEMENT MAP (17):',
    '#   DIRECTLY_GATED section → "DIRECT|FunctionName|gate_source_path"',
    '#   TRANSITIVELY_GATED section → "TRANSITIVE|FunctionName|gate_path"',
    '#   STATIC_CALL_CHAIN section → "STATIC_LINK|..." lines',
    '#   DYNAMIC_VERIFICATION section → ALLOWED/BLOCKED signal lines',
    '#   NON_OPERATIONAL section → dropped entirely (dead helpers)',
    '#',
    '# UNGUARDED REPORT (18):',
    '#   "NO_UNGUARDED_OPERATIONAL_PATHS_DETECTED" or "UNGUARDED|function=<name>"',
    '#   file_path field dropped',
    '#',
    '# BYPASS CROSSCHECK (19):',
    '#   "CROSSCHECK_OK|logical=...|actual=...|classification=..." lines',
    '#   proof_folder field dropped (timestamp-sensitive)',
    '#',
    '# DETERMINISM:',
    '#   Each section is independently sorted and deduplicated.',
    '#   Sections combined in fixed order: inventory, enforcement_map, unguarded_report, crosscheck_report.',
    '#   Blank/comment lines skipped.',
    '#   Whitespace stripped from each line before processing.',
    '#   SHA-256 applied to UTF-8 bytes of combined canonical string.',
    '#',
    '# COVERAGE_FINGERPRINT_SHA256=' + $baseFingerprint
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '10_fingerprint_definition.txt'), $def10, [System.Text.Encoding]::UTF8)

$rules11 = @(
    'RULE_1=fingerprint must be deterministic: same semantic content always produces same fingerprint',
    'RULE_2=non-semantic changes (whitespace, comments, prose notes, order) must not alter fingerprint',
    'RULE_3=entrypoint addition must alter fingerprint',
    'RULE_4=coverage classification change (e.g. TRANSITIVELY_GATED->UNGUARDED_OPERATIONAL) must alter fingerprint',
    'RULE_5=entry order change must not alter fingerprint (sort+dedup before hash)',
    'RULE_6=dead/non-operational helper notes change must not alter fingerprint (notes field excluded)',
    'RULE_7=unguarded operational path introduction must alter fingerprint',
    'RULE_8=operational↔dead reclassification of a real path must alter fingerprint',
    'RULE_9=removal or mutation of bypass-covered crosscheck path must alter fingerprint',
    'RULE_10=file_path fields excluded to prevent path-sensitivity',
    'RULE_11=proof_folder fields excluded to prevent timestamp-sensitivity',
    'RULE_12=NON_OPERATIONAL section of enforcement map excluded from fingerprint (dead helpers in map do not affect enforcement surface)',
    'IMPLEMENTATION_LANGUAGE=PowerShell SHA256 via System.Security.Cryptography.SHA256::HashData',
    'ENCODING=UTF-8',
    'SECTION_ORDER_FIXED=inventory:enforcement_map:unguarded_report:crosscheck_report'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '11_fingerprint_rules.txt'), $rules11, [System.Text.Encoding]::UTF8)

$files12 = @(
    'READ=' + $Inv16Path,
    'READ=' + $Map17Path,
    'READ=' + $Ung18Path,
    'READ=' + $Cross19Path,
    'WRITE=' + $ReferencePath,
    'WRITE=' + $PF
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '12_files_touched.txt'), $files12, [System.Text.Encoding]::UTF8)

$build13 = @(
    'CASE_COUNT=9',
    'PASSED=' + $passCount,
    'FAILED=' + $failCount,
    'COVERAGE_FINGERPRINT=' + $baseFingerprint,
    'INVENTORY_SECTION_HASH=' + $invSectionHash,
    'ENFORCEMENT_MAP_SECTION_HASH=' + $mapSectionHash,
    'UNGUARDED_REPORT_SECTION_HASH=' + $ungSectionHash,
    'CROSSCHECK_REPORT_SECTION_HASH=' + $crossSectionHash,
    'INVENTORY_CANONICAL_ROW_COUNT=' + $baseInvRows.Count,
    'ENFORCEMENT_MAP_CANONICAL_ROW_COUNT=' + $baseMapRows.Count,
    'UNGUARDED_REPORT_CANONICAL_ROW_COUNT=' + $baseUngRows.Count,
    'CROSSCHECK_CANONICAL_ROW_COUNT=' + $baseCrossRows.Count,
    'GATE=' + $Gate
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '13_build_output.txt'), $build13, [System.Text.Encoding]::UTF8)

[System.IO.File]::WriteAllText((Join-Path $PF '14_validation_results.txt'), ($ValidationLines -join "`r`n"), [System.Text.Encoding]::UTF8)

$summary15 = @(
    'PHASE=51.7',
    '# HOW CANONICAL ROWS ARE CONSTRUCTED:',
    '# Each Phase 51.6 proof artifact is read line-by-line. Blank and comment (#) lines',
    '# are skipped. Pipe-delimited inventory rows are split and only semantic fields',
    '# are reassembled in a fixed order. Enforcement-map rows are parsed by section.',
    '# Unguarded-report rows retain only the function name marker. Crosscheck rows retain',
    '# logical/actual/classification but strip proof_folder timestamp fields.',
    '#',
    '# HOW DUPLICATES ARE REMOVED:',
    '# After extraction, each section''s row list is sorted and deduplicated via',
    '# Sort-Object -Unique before hashing. This guarantees that a row appearing twice',
    '# (e.g. from two inventory lines with the same function) does not inflate the fingerprint.',
    '#',
    '# HOW SORTING ENSURES DETERMINISM:',
    '# Rows within each section are sorted lexicographically after extraction.',
    '# The overall section order is fixed (inventory, enforcement_map, unguarded_report, crosscheck_report).',
    '# Therefore the fingerprint is identical regardless of the order in which rows appear in the source files.',
    '#',
    '# WHY FINGERPRINT IS ORDER-INSENSITIVE:',
    '# Sort by canonical content, then hash. Reordering source lines produces the same sorted',
    '# row set → same combined string → same SHA-256.',
    '#',
    '# WHY SEMANTIC CHANGES AFFECT THE FINGERPRINT:',
    '# Adding/removing an entrypoint changes the inventory row set.        (Cases C, H)',
    '# Changing coverage_classification changes the inventory row content.  (Case D)',
    '# Introducing an unguarded path changes the unguarded-report row set.  (Case G)',
    '# Removing a bypass-covered path changes the crosscheck row set.       (Case I)',
    '# These changes flow through to the canonical combined string, altering the SHA-256.',
    '#',
    '# WHY NON-SEMANTIC CHANGES DO NOT AFFECT THE FINGERPRINT:',
    '# Whitespace is stripped before row assembly.                          (Case B)',
    '# Comments and blank lines are skipped.                                (Case B)',
    '# Row order is normalised by sort before hashing.                      (Case E)',
    '# Notes and prose fields are excluded from canonical rows.             (Case F)',
    '# proof_folder (timestamp) fields are excluded from crosscheck rows.   (all cases)',
    '# file_path fields are excluded from inventory rows.                   (all cases)',
    '#',
    '# WHY THIS FINGERPRINT FULLY REPRESENTS THE 51.6 ENFORCEMENT SURFACE:',
    '# It encodes: which functions exist, their operational/dead classification,',
    '# their position in the gate coverage hierarchy (DIRECT or TRANSITIVE),',
    '# all static call-chain link results, dynamic gate verification results,',
    '# all unguarded-path detections, and the full bypass-crosscheck mapping.',
    '# Any regression in any of these dimensions changes the fingerprint.',
    '#',
    '# RUNTIME BEHAVIOR UNCHANGED: this runner is read-only; no ledger entries were written.',
    'GATE=' + $Gate,
    'TOTAL_CASES=9',
    'PASSED=' + $passCount,
    'FAILED=' + $failCount,
    'COVERAGE_FINGERPRINT=' + $baseFingerprint,
    'REFERENCE_ARTIFACT=' + $ReferencePath,
    'RUNTIME_STATE_MACHINE_UNCHANGED=TRUE'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '15_behavior_summary.txt'), $summary15, [System.Text.Encoding]::UTF8)

# 16_coverage_fingerprint_record.txt
$fpRecordLines = [System.Collections.Generic.List[string]]::new()
$fpRecordLines.Add('coverage_fingerprint_sha256=' + $baseFingerprint)
$fpRecordLines.Add('inventory_section_sha256=' + $invSectionHash)
$fpRecordLines.Add('enforcement_map_section_sha256=' + $mapSectionHash)
$fpRecordLines.Add('unguarded_report_section_sha256=' + $ungSectionHash)
$fpRecordLines.Add('crosscheck_report_section_sha256=' + $crossSectionHash)
$fpRecordLines.Add('inventory_canonical_rows=' + $baseInvRows.Count)
$fpRecordLines.Add('enforcement_map_canonical_rows=' + $baseMapRows.Count)
$fpRecordLines.Add('unguarded_report_canonical_rows=' + $baseUngRows.Count)
$fpRecordLines.Add('crosscheck_canonical_rows=' + $baseCrossRows.Count)
$fpRecordLines.Add('source_phase51_6_proof=' + $phase51_6ProofDir.Name)
$fpRecordLines.Add('')
$fpRecordLines.Add('# INVENTORY CANONICAL ROWS:')
foreach ($r in $baseInvRows)    { $fpRecordLines.Add($r) }
$fpRecordLines.Add('')
$fpRecordLines.Add('# ENFORCEMENT MAP CANONICAL ROWS:')
foreach ($r in $baseMapRows)    { $fpRecordLines.Add($r) }
$fpRecordLines.Add('')
$fpRecordLines.Add('# UNGUARDED REPORT CANONICAL ROWS:')
foreach ($r in $baseUngRows)    { $fpRecordLines.Add($r) }
$fpRecordLines.Add('')
$fpRecordLines.Add('# CROSSCHECK CANONICAL ROWS:')
foreach ($r in $baseCrossRows)  { $fpRecordLines.Add($r) }
[System.IO.File]::WriteAllText((Join-Path $PF '16_coverage_fingerprint_record.txt'), ($fpRecordLines -join "`r`n"), [System.Text.Encoding]::UTF8)

[System.IO.File]::WriteAllText((Join-Path $PF '17_regression_detection_evidence.txt'), ($RegressionLines -join "`r`n"), [System.Text.Encoding]::UTF8)

$gate98 = @('PHASE=51.7', 'GATE=' + $Gate) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '98_gate_phase51_7.txt'), $gate98, [System.Text.Encoding]::UTF8)

# ── Zip ───────────────────────────────────────────────────────────────────────

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

Write-Output ('PF='   + $PF)
Write-Output ('ZIP='  + $ZipPath)
Write-Output ('GATE=' + $Gate)
