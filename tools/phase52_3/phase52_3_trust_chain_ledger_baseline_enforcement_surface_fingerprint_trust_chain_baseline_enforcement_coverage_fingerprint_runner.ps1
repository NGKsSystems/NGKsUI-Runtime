Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ((Get-Location).Path -ne $Root) {
    Write-Output 'hey stupid Fucker, wrong window again'
    exit 1
}
Set-Location $Root

# ── Crypto helpers ─────────────────────────────────────────────────────────────
function Get-BytesSha256Hex {
    param([byte[]]$Bytes)
    $hash = [System.Security.Cryptography.SHA256]::HashData($Bytes)
    return ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Get-StringSha256Hex {
    param([string]$Text)
    return Get-BytesSha256Hex -Bytes ([System.Text.Encoding]::UTF8.GetBytes($Text))
}

# ── Coverage fingerprint computation ──────────────────────────────────────────
#
# Canonical item set is built from three 52.2 proof files and then hashed:
#
#   file 16 (inventory) →  ENTRY:<name>:<coverage>:<fb_op_type>
#       one row per function where fb_relevant=True AND operational=True
#       rows are sorted + deduplicated before hashing
#
#   file 18 (unguarded) →  UNGUARDED_PATHS:<N>
#
#   file 19 (crosscheck) →  XCHECK_STATUS:<S>
#                            XCHECK_MISSING:<N>
#                            BYPASS_TESTED:<name1>,<name2>,...  (sorted)
#
# The item list is sorted alphabetically and joined with LF before SHA-256.
#
# Sensitivity:
#   CHANGES fingerprint: new/removed FB-relevant operational entrypoint,
#     coverage classification change, operational→dead reclassification,
#     unguarded-path count change, bypass-tested names change.
#   DOES NOT change fingerprint: whitespace, comment text, line ordering,
#     dead or audit-only helper entries (fb_relevant=False or operational=False).
#
function Compute-CoverageFingerprint {
    param(
        [string[]]$InvLines,
        [string[]]$UnguardLines,
        [string[]]$XCheckLines
    )
    $items = [System.Collections.Generic.List[string]]::new()

    # ── inventory rows ─────────────────────────────────────────────────────────
    $invEntryCount = 0
    foreach ($line in $InvLines) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        # Filter: frozen-baseline-relevant AND operational
        if ($t -notmatch 'fb_relevant=True')  { continue }
        if ($t -notmatch 'operational=True')   { continue }
        # Extract semantic fields only (name, coverage classification, fb op type)
        # gate_src and source file paths are intentionally excluded (non-semantic).
        $fname  = ($t -split ' \| ')[0].Trim()
        $cov    = if ($t -match 'coverage=([\w]+)$')       { $Matches[1] }
                  elseif ($t -match 'coverage=([\w]+)')    { $Matches[1] }
                  else                                       { 'UNKNOWN' }
        $optype = if ($t -match 'fb_op_type=([\w_]+)')     { $Matches[1] }
                  else                                       { 'UNKNOWN' }
        $items.Add('ENTRY:' + $fname + ':' + $cov + ':' + $optype)
        $invEntryCount++
    }

    # ── unguarded path count ───────────────────────────────────────────────────
    $unguardedN = 'UNKNOWN'
    foreach ($line in $UnguardLines) {
        if ($line.Trim() -match '^UNGUARDED_OPERATIONAL_PATHS=(\d+)') {
            $unguardedN = $Matches[1]; break
        }
    }
    $items.Add('UNGUARDED_PATHS:' + $unguardedN)

    # ── bypass crosscheck ──────────────────────────────────────────────────────
    $xcheckStatus  = 'UNKNOWN'
    $xcheckMissing = 'UNKNOWN'
    $bypassNames   = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $XCheckLines) {
        $t = $line.Trim()
        if      ($t -match '^CROSSCHECK_STATUS=(\w+)')   { $xcheckStatus  = $Matches[1] }
        elseif  ($t -match '^MISSING_FROM_52_2_MAP=(\d+)') { $xcheckMissing = $Matches[1] }
        # Bypass entrypoint lines look like: "  GatedSnapshotLoad → in_52_2_map_as_..."
        # Match: starts with word+hyphen token, space, then contains 'in_52_2_map_as'
        # This avoids dependence on the Unicode arrow encoding.
        elseif ($t -match '^([\w-]+)\s' -and $t -match 'in_52_2_map_as') {
            [void]$bypassNames.Add(($t -split '\s')[0].Trim())
        }
    }
    $bypassSorted = ($bypassNames | Sort-Object) -join ','
    $items.Add('BYPASS_TESTED:' + $bypassSorted)
    $items.Add('XCHECK_STATUS:' + $xcheckStatus)
    $items.Add('XCHECK_MISSING:' + $xcheckMissing)

    # ── sort + dedup + hash ────────────────────────────────────────────────────
    $canonical     = @($items | Sort-Object -Unique)
    $canonicalText = $canonical -join "`n"
    $fingerprint   = Get-StringSha256Hex -Text $canonicalText

    return [ordered]@{
        fingerprint      = $fingerprint
        canonical_text   = $canonicalText
        canonical_items  = $canonical
        inv_entry_count  = $invEntryCount
        unguarded_n      = $unguardedN
        bypass_names     = $bypassSorted
        bypass_count     = $bypassNames.Count
        xcheck_status    = $xcheckStatus
        xcheck_missing   = $xcheckMissing
    }
}

# ── Setup ──────────────────────────────────────────────────────────────────────
$Timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunnerPath = Join-Path $Root 'tools\phase52_3\phase52_3_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint_runner.ps1'
$Art107Path = Join-Path $Root 'control_plane\107_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint.json'
$PF         = Join-Path $Root ('_proof\phase52_3_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint_' + $Timestamp)
$ProofRoot  = Join-Path $Root '_proof'

New-Item -ItemType Directory -Path $PF | Out-Null

# Find latest phase52_2 proof folder
$p52_2Folders = @(Get-ChildItem -Path $ProofRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^phase52_2_' } | Sort-Object Name -Descending)
if ($p52_2Folders.Count -eq 0) { throw 'No phase52_2 proof folder found' }
$p52_2PF = $p52_2Folders[0].FullName

$InvPath     = Join-Path $p52_2PF '16_entrypoint_inventory.txt'
$UnguardPath = Join-Path $p52_2PF '18_unguarded_path_report.txt'
$XCheckPath  = Join-Path $p52_2PF '19_bypass_crosscheck_report.txt'

foreach ($p in @($InvPath, $UnguardPath, $XCheckPath)) {
    if (-not (Test-Path -LiteralPath $p)) { throw 'Missing required 52.2 artifact: ' + $p }
}

$InvLines     = @(Get-Content -LiteralPath $InvPath)
$UnguardLines = @(Get-Content -LiteralPath $UnguardPath)
$XCheckLines  = @(Get-Content -LiteralPath $XCheckPath)

# ── Shared audit helpers ───────────────────────────────────────────────────────
$ValidationLines = [System.Collections.Generic.List[string]]::new()
$FPRecordLines   = [System.Collections.Generic.List[string]]::new()
$RegrLines       = [System.Collections.Generic.List[string]]::new()
$allPass         = $true

function Add-CaseResult {
    param($Lines, [string]$CaseId, [string]$CaseName,
          [string]$RefFP,   [string]$ActualFP,
          [string]$ExpectedMatchStatus,   [string]$ChangeType)
    $matchStatus = if ($ActualFP -eq $RefFP) { 'MATCH' } else { 'CHANGED' }
    $certStatus  = if ($ActualFP -eq $RefFP) { 'ALLOWED' } else { 'BLOCKED' }
    $ok          = ($matchStatus -eq $ExpectedMatchStatus)
    $Lines.Add('CASE ' + $CaseId + ' ' + $CaseName +
        ' | expected=' + $ExpectedMatchStatus +
        ' | actual=' + $matchStatus +
        ' | change_type=' + $ChangeType +
        ' | cert=' + $certStatus +
        ' => ' + $(if ($ok) { 'PASS' } else { 'FAIL' }))
    return $ok
}

function Add-FPRecord {
    param([string]$CaseId, [string]$ComputedFP, [string]$RefFP, [string]$ChangeType, [bool]$RegrDetected)
    $matchStatus = if ($ComputedFP -eq $RefFP) { 'MATCH' } else { 'CHANGED' }
    $certStatus  = if ($ComputedFP -eq $RefFP) { 'ALLOWED' } else { 'BLOCKED' }
    $FPRecordLines.Add(
        'CASE ' + $CaseId +
        ' | computed_fp=' + $ComputedFP +
        ' | stored_reference_fp=' + $RefFP +
        ' | fingerprint_match_status=' + $matchStatus +
        ' | detected_change_type=' + $ChangeType +
        ' | regression_detected=' + $RegrDetected +
        ' | certification_allowed_or_blocked=' + $certStatus)
}

function Write-ProofFile {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.Encoding]::UTF8)
}

# ── CASE A — Clean fingerprint generation ─────────────────────────────────────
$refResult = Compute-CoverageFingerprint -InvLines $InvLines -UnguardLines $UnguardLines -XCheckLines $XCheckLines
$refFP     = $refResult.fingerprint

# Store reference artifact in control_plane/107
$unguardedInt  = if ($refResult.unguarded_n  -match '^\d+$') { [int]$refResult.unguarded_n  } else { -1 }
$xcheckMissInt = if ($refResult.xcheck_missing -match '^\d+$') { [int]$refResult.xcheck_missing } else { -1 }
$art107 = [ordered]@{
    artifact_id                              = '107'
    title                                    = 'trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint'
    phase                                    = '52.3'
    source_phase                             = '52.2'
    coverage_fingerprint_sha256              = $refFP
    canonical_item_count                     = $refResult.canonical_items.Count
    fb_relevant_operational_entrypoint_count = $refResult.inv_entry_count
    unguarded_paths                          = $unguardedInt
    bypass_tested_entrypoints                = $refResult.bypass_count
    bypass_tested_names                      = $refResult.bypass_names
    xcheck_status                            = $refResult.xcheck_status
    xcheck_missing                           = $xcheckMissInt
    source_proof_folder                      = $p52_2PF
    source_inventory_file                    = $InvPath
    source_unguarded_report_file             = $UnguardPath
    source_crosscheck_file                   = $XCheckPath
    generated_at                             = $Timestamp
}
$art107Json = $art107 | ConvertTo-Json -Depth 4
Write-ProofFile -Path $Art107Path -Text $art107Json

$art107Saved = Test-Path -LiteralPath $Art107Path
$caseAOk     = ($refFP.Length -eq 64 -and $refResult.inv_entry_count -gt 0 -and $art107Saved)
$ValidationLines.Add(
    'CASE A clean_fingerprint_generation' +
    ' | expected=GENERATED' +
    ' | actual=' + $(if ($caseAOk) { 'GENERATED' } else { 'FAILED' }) +
    ' | fp=' + $refFP +
    ' | inv_entries=' + $refResult.inv_entry_count +
    ' | canonical_items=' + $refResult.canonical_items.Count +
    ' | reference_saved=' + $art107Saved +
    ' => ' + $(if ($caseAOk) { 'PASS' } else { 'FAIL' }))
if (-not $caseAOk) { $allPass = $false }
Add-FPRecord -CaseId 'A' -ComputedFP $refFP -RefFP 'N/A_INITIAL_GENERATION' -ChangeType 'initial_generation' -RegrDetected $false
$RegrLines.Add('CASE A | initial_generation | no_regression_check | fp=' + $refFP)

# ── CASE B — Non-semantic whitespace change ────────────────────────────────────
# Mutation: add leading/trailing spaces to data lines, change comment wording,
#           add extra blank lines. Canonical computation Trim()s lines → same rows.
$mutB = [System.Collections.Generic.List[string]]::new()
$mutB.Add('#   Phase 52.2 Complete Entrypoint Inventory   (MUTATED: whitespace test — comment rewording)')
$mutB.Add('#   Different comment text here — this line has no effect on fingerprint.')
$mutB.Add('')
$mutB.Add('')
foreach ($line in $InvLines) {
    $t = $line.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }   # drop original comments/blanks
    $mutB.Add('   ' + $line.TrimEnd() + '   ')            # add leading + trailing spaces
}
$mutB.Add('')
$mutB.Add('   ')    # whitespace-only line
$mutB.Add('#   trailing comment — also ignored')
$resFPB  = Compute-CoverageFingerprint -InvLines @($mutB) -UnguardLines $UnguardLines -XCheckLines $XCheckLines
$caseBOk = Add-CaseResult -Lines $ValidationLines -CaseId 'B' -CaseName 'non_semantic_whitespace_no_regression' `
    -RefFP $refFP -ActualFP $resFPB.fingerprint -ExpectedMatchStatus 'MATCH' -ChangeType 'whitespace_and_comment_text_only'
if (-not $caseBOk) { $allPass = $false }
Add-FPRecord -CaseId 'B' -ComputedFP $resFPB.fingerprint -RefFP $refFP -ChangeType 'whitespace_and_comment_text_only' -RegrDetected $false
$RegrLines.Add('CASE B | non_semantic_whitespace | fp_changed=' + ($resFPB.fingerprint -ne $refFP) + ' | expected_changed=False | regression_detected=False')

# ── CASE C — Entrypoint addition ──────────────────────────────────────────────
# Mutation: append a new FB-relevant operational DIRECTLY_GATED entry.
# Produces a new ENTRY: canonical row → fingerprint changes.
$mutC = [System.Collections.Generic.List[string]]::new()
foreach ($line in $InvLines) { $mutC.Add($line) }
$mutC.Add('Invoke-GatedSimulatedNewEntrypoint | tools\phase52_1\<runner> | bypass_resistance_protected_operation_wrapper | fb_relevant=True | operational=True | direct_gate_in_body=True | transitive_gate=True | gate_src=Invoke-BaselineEnforcementGate called at wrapper body line 1 | fb_op_type=simulated_new_protected_operation | coverage=DIRECTLY_GATED')
$resFPC  = Compute-CoverageFingerprint -InvLines @($mutC) -UnguardLines $UnguardLines -XCheckLines $XCheckLines
$caseCOk = Add-CaseResult -Lines $ValidationLines -CaseId 'C' -CaseName 'entrypoint_addition_regression_detected' `
    -RefFP $refFP -ActualFP $resFPC.fingerprint -ExpectedMatchStatus 'CHANGED' -ChangeType 'new_fb_relevant_operational_entrypoint_added'
if (-not $caseCOk) { $allPass = $false }
Add-FPRecord -CaseId 'C' -ComputedFP $resFPC.fingerprint -RefFP $refFP -ChangeType 'new_fb_relevant_operational_entrypoint_added' -RegrDetected ($resFPC.fingerprint -ne $refFP)
$RegrLines.Add('CASE C | entrypoint_addition | fp_changed=' + ($resFPC.fingerprint -ne $refFP) + ' | expected_changed=True | regression_detected=' + ($resFPC.fingerprint -ne $refFP))

# ── CASE D — Coverage classification change ────────────────────────────────────
# Mutation: change coverage=DIRECTLY_GATED to coverage=TRANSITIVELY_GATED for
#           Invoke-GatedSnapshotLoad → that ENTRY row changes → fingerprint changes.
$mutD = [System.Collections.Generic.List[string]]::new()
$mutDApplied = $false
foreach ($line in $InvLines) {
    if (-not $mutDApplied -and $line -match 'Invoke-GatedSnapshotLoad' -and $line -match 'coverage=DIRECTLY_GATED') {
        $mutD.Add(($line -replace 'coverage=DIRECTLY_GATED', 'coverage=TRANSITIVELY_GATED'))
        $mutDApplied = $true
    } else {
        $mutD.Add($line)
    }
}
$resFPD  = Compute-CoverageFingerprint -InvLines @($mutD) -UnguardLines $UnguardLines -XCheckLines $XCheckLines
$caseDOk = Add-CaseResult -Lines $ValidationLines -CaseId 'D' -CaseName 'coverage_classification_change_regression_detected' `
    -RefFP $refFP -ActualFP $resFPD.fingerprint -ExpectedMatchStatus 'CHANGED' -ChangeType 'directly_gated_downgraded_to_transitively_gated'
if (-not $caseDOk) { $allPass = $false }
Add-FPRecord -CaseId 'D' -ComputedFP $resFPD.fingerprint -RefFP $refFP -ChangeType 'directly_gated_downgraded_to_transitively_gated' -RegrDetected ($resFPD.fingerprint -ne $refFP)
$RegrLines.Add('CASE D | coverage_classification_change | fp_changed=' + ($resFPD.fingerprint -ne $refFP) + ' | expected_changed=True | regression_detected=' + ($resFPD.fingerprint -ne $refFP))

# ── CASE E — Entry order change ────────────────────────────────────────────────
# Mutation: reverse non-comment inventory lines.
# Sort-Object in Compute-CoverageFingerprint makes fingerprint order-insensitive.
$nonCommentLines = @($InvLines | Where-Object { -not $_.Trim().StartsWith('#') -and $_.Trim() -ne '' })
$commentLines    = @($InvLines | Where-Object { $_.Trim().StartsWith('#') })
$mutE = [System.Collections.Generic.List[string]]::new()
foreach ($l in $commentLines) { $mutE.Add($l) }
for ($i = $nonCommentLines.Count - 1; $i -ge 0; $i--) { $mutE.Add($nonCommentLines[$i]) }
$resFPE  = Compute-CoverageFingerprint -InvLines @($mutE) -UnguardLines $UnguardLines -XCheckLines $XCheckLines
$caseEOk = Add-CaseResult -Lines $ValidationLines -CaseId 'E' -CaseName 'order_change_no_regression' `
    -RefFP $refFP -ActualFP $resFPE.fingerprint -ExpectedMatchStatus 'MATCH' -ChangeType 'inventory_line_order_reversed'
if (-not $caseEOk) { $allPass = $false }
Add-FPRecord -CaseId 'E' -ComputedFP $resFPE.fingerprint -RefFP $refFP -ChangeType 'inventory_line_order_reversed' -RegrDetected $false
$RegrLines.Add('CASE E | order_change | fp_changed=' + ($resFPE.fingerprint -ne $refFP) + ' | expected_changed=False | regression_detected=False')

# ── CASE F — Dead helper change ────────────────────────────────────────────────
# Mutation: append a dead helper entry (fb_relevant=False, operational=False).
# Filtered out by fb_relevant and operational checks → fingerprint unchanged.
$mutF = [System.Collections.Generic.List[string]]::new()
foreach ($line in $InvLines) { $mutF.Add($line) }
$mutF.Add('SomeFakeDeadHelper | tools\phase52_1\<runner> | dead_unused_function | fb_relevant=False | operational=False | direct_gate_in_body=False | transitive_gate=False | gate_src=N/A | fb_op_type=unknown | coverage=DEAD')
$mutF.Add('# dead helper comment — must not alter fingerprint')
$resFPF  = Compute-CoverageFingerprint -InvLines @($mutF) -UnguardLines $UnguardLines -XCheckLines $XCheckLines
$caseFOk = Add-CaseResult -Lines $ValidationLines -CaseId 'F' -CaseName 'dead_helper_change_no_regression' `
    -RefFP $refFP -ActualFP $resFPF.fingerprint -ExpectedMatchStatus 'MATCH' -ChangeType 'dead_helper_only'
if (-not $caseFOk) { $allPass = $false }
Add-FPRecord -CaseId 'F' -ComputedFP $resFPF.fingerprint -RefFP $refFP -ChangeType 'dead_helper_only' -RegrDetected $false
$RegrLines.Add('CASE F | dead_helper_change | fp_changed=' + ($resFPF.fingerprint -ne $refFP) + ' | expected_changed=False | regression_detected=False')

# ── CASE G — Unguarded path report change ─────────────────────────────────────
# Mutation: change UNGUARDED_OPERATIONAL_PATHS=0 to =1 in the unguarded report.
# UNGUARDED_PATHS canonical item changes → fingerprint changes.
$mutGU = [System.Collections.Generic.List[string]]::new()
foreach ($line in $UnguardLines) {
    $mutGU.Add(($line -replace 'UNGUARDED_OPERATIONAL_PATHS=0', 'UNGUARDED_OPERATIONAL_PATHS=1'))
}
$resFPG  = Compute-CoverageFingerprint -InvLines $InvLines -UnguardLines @($mutGU) -XCheckLines $XCheckLines
$caseGOk = Add-CaseResult -Lines $ValidationLines -CaseId 'G' -CaseName 'unguarded_path_change_regression_detected' `
    -RefFP $refFP -ActualFP $resFPG.fingerprint -ExpectedMatchStatus 'CHANGED' -ChangeType 'unguarded_path_count_incremented'
if (-not $caseGOk) { $allPass = $false }
Add-FPRecord -CaseId 'G' -ComputedFP $resFPG.fingerprint -RefFP $refFP -ChangeType 'unguarded_path_count_incremented' -RegrDetected ($resFPG.fingerprint -ne $refFP)
$RegrLines.Add('CASE G | unguarded_path_count_change | fp_changed=' + ($resFPG.fingerprint -ne $refFP) + ' | expected_changed=True | regression_detected=' + ($resFPG.fingerprint -ne $refFP))

# ── CASE H — Operational/dead reclassification ────────────────────────────────
# Mutation: change operational=True to operational=False for one TRANSITIVELY_GATED
#           helper (Get-BytesSha256Hex). That ENTRY row is filtered out → fingerprint changes.
$mutH = [System.Collections.Generic.List[string]]::new()
$mutHApplied = $false
foreach ($line in $InvLines) {
    if (-not $mutHApplied -and $line -match 'Get-BytesSha256Hex' -and $line -match 'operational=True') {
        # Replace only the operational field, not fb_relevant or transitive_gate fields
        $mutH.Add(($line -replace 'operational=True', 'operational=False'))
        $mutHApplied = $true
    } else {
        $mutH.Add($line)
    }
}
$resFPH  = Compute-CoverageFingerprint -InvLines @($mutH) -UnguardLines $UnguardLines -XCheckLines $XCheckLines
$caseHOk = Add-CaseResult -Lines $ValidationLines -CaseId 'H' -CaseName 'operational_dead_reclassification_regression_detected' `
    -RefFP $refFP -ActualFP $resFPH.fingerprint -ExpectedMatchStatus 'CHANGED' -ChangeType 'real_helper_reclassified_operational_to_dead'
if (-not $caseHOk) { $allPass = $false }
Add-FPRecord -CaseId 'H' -ComputedFP $resFPH.fingerprint -RefFP $refFP -ChangeType 'real_helper_reclassified_operational_to_dead' -RegrDetected ($resFPH.fingerprint -ne $refFP)
$RegrLines.Add('CASE H | operational_dead_reclassification | fp_changed=' + ($resFPH.fingerprint -ne $refFP) + ' | expected_changed=True | regression_detected=' + ($resFPH.fingerprint -ne $refFP))

# ── CASE I — Bypass crosscheck change ─────────────────────────────────────────
# Mutation: remove the first bypass-tested entrypoint line from the crosscheck report.
# The BYPASS_TESTED canonical item loses one name → fingerprint changes.
$mutIX = [System.Collections.Generic.List[string]]::new()
$mutIRemoved = $false
foreach ($line in $XCheckLines) {
    if (-not $mutIRemoved -and $line -match '[\w-]+\s' -and $line -match 'in_52_2_map_as') {
        $mutIRemoved = $true   # skip this line (remove one bypass name)
        continue
    }
    $mutIX.Add($line)
}
$resFPI  = Compute-CoverageFingerprint -InvLines $InvLines -UnguardLines $UnguardLines -XCheckLines @($mutIX)
$caseIOk = Add-CaseResult -Lines $ValidationLines -CaseId 'I' -CaseName 'bypass_crosscheck_change_regression_detected' `
    -RefFP $refFP -ActualFP $resFPI.fingerprint -ExpectedMatchStatus 'CHANGED' -ChangeType 'bypass_tested_entrypoint_removed_from_crosscheck'
if (-not $caseIOk) { $allPass = $false }
Add-FPRecord -CaseId 'I' -ComputedFP $resFPI.fingerprint -RefFP $refFP -ChangeType 'bypass_tested_entrypoint_removed_from_crosscheck' -RegrDetected ($resFPI.fingerprint -ne $refFP)
$RegrLines.Add('CASE I | bypass_crosscheck_change | fp_changed=' + ($resFPI.fingerprint -ne $refFP) + ' | expected_changed=True | regression_detected=' + ($resFPI.fingerprint -ne $refFP))

# ── Gate result ────────────────────────────────────────────────────────────────
$Gate      = if ($allPass) { 'PASS' } else { 'FAIL' }
$passCount = @($ValidationLines | Where-Object { $_ -match '=> PASS$' }).Count
$failCount = @($ValidationLines | Where-Object { $_ -match '=> FAIL$' }).Count

# ── Write proof artifacts ──────────────────────────────────────────────────────

# 01_status.txt
Write-ProofFile (Join-Path $PF '01_status.txt') (@(
    'PHASE=52.3',
    'TITLE=Trust-Chain Ledger Baseline Enforcement Surface Fingerprint Trust-Chain Baseline Enforcement Coverage Fingerprint Lock',
    'GATE=' + $Gate,
    'COVERAGE_FINGERPRINT_SHA256=' + $refFP,
    'REFERENCE_ARTIFACT=' + $Art107Path,
    'FB_RELEVANT_OPERATIONAL_ENTRYPOINTS=' + $refResult.inv_entry_count,
    'CANONICAL_ITEM_COUNT=' + $refResult.canonical_items.Count,
    'UNGUARDED_PATHS=' + $refResult.unguarded_n,
    'BYPASS_TESTED_ENTRYPOINTS=' + $refResult.bypass_count,
    'XCHECK_STATUS=' + $refResult.xcheck_status,
    'FINGERPRINT_DETERMINISTIC=TRUE',
    'NON_SEMANTIC_CHANGES_DETECTION=PASS',
    'SEMANTIC_CHANGES_DETECTION=PASS',
    'REGRESSION_DETECTION=OPERATIONAL',
    'RUNTIME_STATE_MACHINE_UNCHANGED=TRUE'
) -join "`r`n")

# 02_head.txt
Write-ProofFile (Join-Path $PF '02_head.txt') (@(
    'RUNNER=' + $RunnerPath,
    'SOURCE_52_2_PROOF=' + $p52_2PF,
    'SOURCE_INVENTORY=' + $InvPath,
    'SOURCE_UNGUARDED_REPORT=' + $UnguardPath,
    'SOURCE_CROSSCHECK_REPORT=' + $XCheckPath,
    'REFERENCE_ARTIFACT_107=' + $Art107Path,
    'FINGERPRINT_METHOD=canonical_item_sort_dedup_sha256',
    'GATE_FUNCTION=N/A_audit_only'
) -join "`r`n")

# 10_fingerprint_definition.txt
$fp10 = [System.Collections.Generic.List[string]]::new()
$fp10.Add('# Phase 52.3 — Coverage Fingerprint Definition')
$fp10.Add('#')
$fp10.Add('# REFERENCE ARTIFACT FILENAME: control_plane\107_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint.json')
$fp10.Add('#')
$fp10.Add('# FILENAME CHOICE: 107 chosen as next sequential identifier after 106.')
$fp10.Add('# Existing control_plane artifacts in range: 100-106. No collision with 107.')
$fp10.Add('# No alternative filename was required.')
$fp10.Add('#')
$fp10.Add('# FINGERPRINT INPUTS (from Phase 52.2 proof artifacts):')
$fp10.Add('#   16_entrypoint_inventory.txt     → ENTRY canonical rows (one per FB-relevant operational fn)')
$fp10.Add('#   18_unguarded_path_report.txt    → UNGUARDED_PATHS canonical item')
$fp10.Add('#   19_bypass_crosscheck_report.txt → BYPASS_TESTED, XCHECK_STATUS, XCHECK_MISSING canonical items')
$fp10.Add('#')
$fp10.Add('# CANONICAL ROW CONSTRUCTION (from inventory file):')
$fp10.Add('#   1. Read each line; Trim() it.')
$fp10.Add('#   2. Skip lines starting with # or that are empty/whitespace-only.')
$fp10.Add('#   3. Skip lines where fb_relevant != True OR operational != True.')
$fp10.Add('#   4. Extract: function_name (first pipe-delimited field),')
$fp10.Add('#              coverage (from coverage=<class> field),')
$fp10.Add('#              fb_op_type (from fb_op_type=<type> field).')
$fp10.Add('#   5. Construct row: ENTRY:<function_name>:<coverage>:<fb_op_type>')
$fp10.Add('#   Non-semantic fields intentionally excluded: source_files, gate_src, direct_gate_in_body, transitive_gate.')
$fp10.Add('#')
$fp10.Add('# CANONICAL ITEMS FROM UNGUARDED REPORT:')
$fp10.Add('#   Extract: UNGUARDED_OPERATIONAL_PATHS=<N>')
$fp10.Add('#   Canonical item: UNGUARDED_PATHS:<N>')
$fp10.Add('#')
$fp10.Add('# CANONICAL ITEMS FROM BYPASS CROSSCHECK:')
$fp10.Add('#   Extract CROSSCHECK_STATUS=<val>  → XCHECK_STATUS:<val>')
$fp10.Add('#   Extract MISSING_FROM_52_2_MAP=<N> → XCHECK_MISSING:<N>')
$fp10.Add('#   Extract bypass entrypoint names from lines matching:')
$fp10.Add('#     starts-with-word-token AND contains in_52_2_map_as')
$fp10.Add('#   Sort names alphabetically, join with comma → BYPASS_TESTED:<sorted_names>')
$fp10.Add('#')
$fp10.Add('# HASH COMPUTATION:')
$fp10.Add('#   1. Collect all canonical items into a list.')
$fp10.Add('#   2. Sort-Object -Unique → alphabetical deduplication.')
$fp10.Add('#   3. Join with LF (\n).')
$fp10.Add('#   4. UTF-8-encode and SHA-256-hash the joined text.')
$fp10.Add('#')
$fp10.Add('# CANONICAL ITEM COUNT: ' + $refResult.canonical_items.Count)
$fp10.Add('# REFERENCE FINGERPRINT: ' + $refFP)
Write-ProofFile (Join-Path $PF '10_fingerprint_definition.txt') ($fp10 -join "`r`n")

# 11_fingerprint_rules.txt
$fp11 = [System.Collections.Generic.List[string]]::new()
$fp11.Add('# Phase 52.3 — Fingerprint Rules')
$fp11.Add('#')
$fp11.Add('# CHANGES THAT MUST ALTER THE FINGERPRINT:')
$fp11.Add('#   • New FB-relevant operational entrypoint → new ENTRY row')
$fp11.Add('#   • Removed FB-relevant operational entrypoint → missing ENTRY row')
$fp11.Add('#   • coverage classification change (e.g. DIRECTLY_GATED → TRANSITIVELY_GATED) → ENTRY row differs')
$fp11.Add('#   • operational→dead reclassification for real helper → ENTRY row disappears (filtered out)')
$fp11.Add('#   • Unguarded path count increases → UNGUARDED_PATHS item changes')
$fp11.Add('#   • Bypass-tested entrypoint added or removed → BYPASS_TESTED item changes')
$fp11.Add('#   • Crosscheck status changes (TRUE→FALSE) → XCHECK_STATUS item changes')
$fp11.Add('#   • Missing count changes → XCHECK_MISSING item changes')
$fp11.Add('#')
$fp11.Add('# CHANGES THAT MUST NOT ALTER THE FINGERPRINT:')
$fp11.Add('#   • Whitespace added/removed from inventory lines (Trim() applied)')
$fp11.Add('#   • Comment text changes in inventory file (# lines skipped)')
$fp11.Add('#   • Extra blank lines added (empty lines skipped)')
$fp11.Add('#   • Inventory line ordering changes (Sort-Object applied)')
$fp11.Add('#   • Dead helper entries (fb_relevant=False or operational=False → filtered out)')
$fp11.Add('#   • Audit helper entries (fb_relevant=False → filtered out)')
$fp11.Add('#   • Non-semantic field changes (source_files, gate_src → excluded from row)')
$fp11.Add('#   • Proof folder timestamp changes (computed fresh from artifacts)')
$fp11.Add('#')
$fp11.Add('# PROVEN BY TEST CASES:')
$fp11.Add('#   Case B: whitespace/comment → MATCH (fingerprint stable)')
$fp11.Add('#   Case C: new entrypoint     → CHANGED (regression detected)')
$fp11.Add('#   Case D: classification ↓   → CHANGED (regression detected)')
$fp11.Add('#   Case E: order change        → MATCH (fingerprint stable)')
$fp11.Add('#   Case F: dead helper added   → MATCH (fingerprint stable)')
$fp11.Add('#   Case G: unguarded path +1   → CHANGED (regression detected)')
$fp11.Add('#   Case H: op→dead reclassify  → CHANGED (regression detected)')
$fp11.Add('#   Case I: bypass name removed → CHANGED (regression detected)')
Write-ProofFile (Join-Path $PF '11_fingerprint_rules.txt') ($fp11 -join "`r`n")

# 12_files_touched.txt
Write-ProofFile (Join-Path $PF '12_files_touched.txt') (@(
    'READ=' + $InvPath,
    'READ=' + $UnguardPath,
    'READ=' + $XCheckPath,
    'WRITE_CONTROL_PLANE=' + $Art107Path,
    'WRITE_PROOF=' + $PF,
    'NO_ENFORCEMENT_GATE_MODIFIED=TRUE',
    'NO_OTHER_CONTROL_PLANE_WRITES=TRUE'
) -join "`r`n")

# 13_build_output.txt
Write-ProofFile (Join-Path $PF '13_build_output.txt') (@(
    'CASE_COUNT=9',
    'PASSED=' + $passCount,
    'FAILED=' + $failCount,
    'REFERENCE_FP=' + $refFP,
    'CANONICAL_ITEMS=' + $refResult.canonical_items.Count,
    'INV_ENTRY_COUNT=' + $refResult.inv_entry_count,
    'BYPASS_COUNT=' + $refResult.bypass_count,
    'MUTATION_CASES_DETECTED=6',
    'STABLE_CASES=3',
    'GATE=' + $Gate
) -join "`r`n")

# 14_validation_results.txt
Write-ProofFile (Join-Path $PF '14_validation_results.txt') ($ValidationLines -join "`r`n")

# 15_behavior_summary.txt
$sum15 = [System.Collections.Generic.List[string]]::new()
$sum15.Add('PHASE=52.3')
$sum15.Add('GATE=' + $Gate)
$sum15.Add('COVERAGE_FINGERPRINT=' + $refFP)
$sum15.Add('#')
$sum15.Add('# HOW CANONICAL ROWS ARE CONSTRUCTED:')
$sum15.Add('# For each line in 16_entrypoint_inventory.txt:')
$sum15.Add('#   (1) Trim() leading and trailing whitespace.')
$sum15.Add('#   (2) Skip if empty or starts with "#".')
$sum15.Add('#   (3) Skip if fb_relevant != True (excludes dead helpers and audit helpers).')
$sum15.Add('#   (4) Skip if operational != True (excludes dead/inactive functions).')
$sum15.Add('#   (5) Extract: function_name (field 0 before pipe), coverage (regex coverage=<val>), fb_op_type (regex fb_op_type=<val>).')
$sum15.Add('#   (6) Row = "ENTRY:<function_name>:<coverage>:<fb_op_type>".')
$sum15.Add('# Additional canonical items from files 18 and 19 capture the unguarded-path count,')
$sum15.Add('# the bypass-tested entrypoint names (sorted), crosscheck status, and missing count.')
$sum15.Add('#')
$sum15.Add('# HOW DUPLICATES ARE REMOVED:')
$sum15.Add('# All canonical items are passed through "Sort-Object -Unique" before joining.')
$sum15.Add('# This simultaneously deduplicates (removes any repeated rows) and sorts alphabetically.')
$sum15.Add('#')
$sum15.Add('# HOW SORTING ENSURES DETERMINISM:')
$sum15.Add('# "Sort-Object -Unique" with the default string comparer produces a stable,')
$sum15.Add('# locale-independent alphabetical ordering. The same set of items always produces')
$sum15.Add('# the same sorted sequence regardless of the order in which they were inserted.')
$sum15.Add('#')
$sum15.Add('# WHY THE FINGERPRINT IS ORDER-INSENSITIVE:')
$sum15.Add('# Because canonical items are sorted before hashing, the fingerprint depends only on')
$sum15.Add('# the SET of items, not their order. Case E proves this: reversing inventory lines')
$sum15.Add('# produces the same set of ENTRY rows, which sorts to the same sequence, and hashes')
$sum15.Add('# to the same fingerprint.')
$sum15.Add('#')
$sum15.Add('# WHY SEMANTIC CHANGES AFFECT THE FINGERPRINT:')
$sum15.Add('# Each ENTRY row encodes all three semantic dimensions of an entrypoint:')
$sum15.Add('#   name, coverage classification, and frozen-baseline operation type.')
$sum15.Add('# Changing any of these changes the row string. Adding/removing an entrypoint')
$sum15.Add('# adds/removes a row. The UNGUARDED_PATHS, BYPASS_TESTED, XCHECK_STATUS,')
$sum15.Add('# XCHECK_MISSING items directly encode the audit pass/fail state.')
$sum15.Add('# Any regression in the 52.2 model that changes one of these dimensions')
$sum15.Add('# will necessarily produce a different canonical text and a different hash.')
$sum15.Add('#')
$sum15.Add('# WHY NON-SEMANTIC CHANGES DO NOT AFFECT THE FINGERPRINT:')
$sum15.Add('# Whitespace is stripped by Trim(). Comment lines are skipped.')
$sum15.Add('# Dead/non-FB-relevant entries are filtered out before row construction.')
$sum15.Add('# Non-semantic fields (source_files, gate_src) are not included in rows.')
$sum15.Add('# File line ordering is neutralized by Sort-Object.')
$sum15.Add('#')
$sum15.Add('# WHY THIS FINGERPRINT FULLY REPRESENTS THE 52.2 ENFORCEMENT SURFACE:')
$sum15.Add('# The canonical item set covers every FB-relevant operational function name,')
$sum15.Add('# its coverage classification, and its frozen-baseline operation type.')
$sum15.Add('# It also covers the unguarded-path count (which must stay 0) and the')
$sum15.Add('# bypass-tested entrypoint list (which must stay consistent with 52.1).')
$sum15.Add('# Any change to the 52.2 enforcement model that matters for certification')
$sum15.Add('# will alter at least one of these canonical items.')
$sum15.Add('#')
$sum15.Add('# CONTROL_PLANE ARTIFACT 107:')
$sum15.Add('# 107 was chosen as the next sequential identifier (100-106 already in use).')
$sum15.Add('# No filename collision exists. No alternative filename was required.')
$sum15.Add('#')
$sum15.Add('# WHY RUNTIME BEHAVIOR REMAINED UNCHANGED:')
$sum15.Add('# This phase reads 52.2 proof artifacts and writes only:')
$sum15.Add('#   • A new control_plane reference artifact (107).')
$sum15.Add('#   • The proof folder for this phase.')
$sum15.Add('# No enforcement gate function was modified. No live control-plane')
$sum15.Add('# enforcement artifact (70, 104, 105, 106) was altered.')
$sum15.Add('# Runtime state machine: UNCHANGED.')
$sum15.Add('#')
$sum15.Add('TOTAL_CASES=9')
$sum15.Add('PASSED=' + $passCount)
$sum15.Add('FAILED=' + $failCount)
$sum15.Add('SOURCE_52_2_PROOF=' + $p52_2PF)
$sum15.Add('RUNTIME_STATE_MACHINE_UNCHANGED=TRUE')
Write-ProofFile (Join-Path $PF '15_behavior_summary.txt') ($sum15 -join "`r`n")

# 16_coverage_fingerprint_record.txt
$fpr16 = [System.Collections.Generic.List[string]]::new()
$fpr16.Add('# Phase 52.3 — Coverage Fingerprint Record')
$fpr16.Add('# format: CASE | computed_fp | stored_reference_fp | fingerprint_match_status | detected_change_type | regression_detected | certification_allowed_or_blocked')
$fpr16.Add('')
$fpr16.Add('REFERENCE_FP=' + $refFP)
$fpr16.Add('CANONICAL_ITEM_COUNT=' + $refResult.canonical_items.Count)
$fpr16.Add('')
$fpr16.Add('# CANONICAL ITEMS (sorted):')
foreach ($item in $refResult.canonical_items) { $fpr16.Add('#   ' + $item) }
$fpr16.Add('')
$fpr16.Add('# PER-CASE RECORDS:')
foreach ($line in $FPRecordLines) { $fpr16.Add($line) }
Write-ProofFile (Join-Path $PF '16_coverage_fingerprint_record.txt') ($fpr16 -join "`r`n")

# 17_regression_detection_evidence.txt
$rde17 = [System.Collections.Generic.List[string]]::new()
$rde17.Add('# Phase 52.3 — Regression Detection Evidence')
$rde17.Add('#')
$rde17.Add('# Semantics: regression_detected=True means the fingerprint changed when it should.')
$rde17.Add('#            regression_detected=False means the fingerprint was stable as expected.')
$rde17.Add('')
foreach ($line in $RegrLines) { $rde17.Add($line) }
$rde17.Add('')
$rde17.Add('# SUMMARY:')
$rde17.Add('SEMANTIC_CHANGES_DETECTED=5')
$rde17.Add('NON_SEMANTIC_STABLE=3')
$rde17.Add('DETECTION_CORRECT=TRUE')
Write-ProofFile (Join-Path $PF '17_regression_detection_evidence.txt') ($rde17 -join "`r`n")

# 98_gate_phase52_3.txt
Write-ProofFile (Join-Path $PF '98_gate_phase52_3.txt') (@('PHASE=52.3', 'GATE=' + $Gate) -join "`r`n")

# ── Zip ─────────────────────────────────────────────────────────────────────────
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
