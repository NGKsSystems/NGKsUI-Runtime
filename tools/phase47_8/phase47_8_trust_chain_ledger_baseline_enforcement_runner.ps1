Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ((Get-Location).Path -ne $Root) {
    Write-Output 'hey stupid Fucker, wrong window again'
    exit 1
}
Set-Location $Root

# ──────────────────────────────────────────────────────────────
# PRIMITIVES
# ──────────────────────────────────────────────────────────────

function Get-BytesSha256Hex {
    param([byte[]]$Bytes)
    $hash = [System.Security.Cryptography.SHA256]::HashData($Bytes)
    return ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Get-StringSha256Hex {
    param([string]$Text)
    return Get-BytesSha256Hex -Bytes ([System.Text.Encoding]::UTF8.GetBytes($Text))
}

# Canonical JSON: sort object keys alphabetically; preserve array order.
# Derived from parsed object so whitespace changes have no effect.
function ConvertTo-CanonicalJson {
    param($Value)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool])    { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or
        $Value -is [float]    -or $Value -is [decimal]) {
        return [string]$Value
    }
    if ($Value -is [string]) {
        $s = [string]$Value
        $s = $s -replace '\\', '\\'
        $s = $s -replace '"',  '\"'
        $s = $s -replace "`n", '\n'
        $s = $s -replace "`r", '\r'
        $s = $s -replace "`t", '\t'
        return '"' + $s + '"'
    }
    if ($Value -is [System.Collections.IList]) {
        $items = [System.Collections.Generic.List[string]]::new()
        foreach ($item in $Value) {
            $items.Add((ConvertTo-CanonicalJson -Value $item))
        }
        return '[' + ($items -join ',') + ']'
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $keys  = @($Value.Keys | Sort-Object)
        $pairs = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $keys) {
            $pairs.Add(('"' + $k + '":' + (ConvertTo-CanonicalJson -Value $Value[$k])))
        }
        return '{' + ($pairs -join ',') + '}'
    }
    if ($Value -is [pscustomobject]) {
        $keys  = @($Value.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object)
        $pairs = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $keys) {
            $v = $Value.PSObject.Properties[$k].Value
            $pairs.Add(('"' + $k + '":' + (ConvertTo-CanonicalJson -Value $v)))
        }
        return '{' + ($pairs -join ',') + '}'
    }
    return '"' + ([string]$Value -replace '"', '\"') + '"'
}

function Get-CanonicalEntryHash {
    param([object]$Entry)
    return Get-StringSha256Hex -Text (ConvertTo-CanonicalJson -Value $Entry)
}

function Get-CanonicalLedgerHash {
    param([object]$LedgerObj)
    return Get-StringSha256Hex -Text (ConvertTo-CanonicalJson -Value $LedgerObj)
}

# ──────────────────────────────────────────────────────────────
# LEDGER CHAIN HASH — backward-compatible with existing chain validator
# (covers only: entry_id, fingerprint_hash, timestamp_utc, phase_locked, previous_hash)
# Used to validate continuation previous_hash linkage.
# ──────────────────────────────────────────────────────────────
function Get-LegacyChainEntryCanonical {
    param([object]$Entry)
    $obj = [ordered]@{
        entry_id         = [string]$Entry.entry_id
        fingerprint_hash = [string]$Entry.fingerprint_hash
        timestamp_utc    = [string]$Entry.timestamp_utc
        phase_locked     = [string]$Entry.phase_locked
        previous_hash    = if ($null -eq $Entry.previous_hash -or
                               [string]::IsNullOrWhiteSpace([string]$Entry.previous_hash)) { $null } else { [string]$Entry.previous_hash }
    }
    return ($obj | ConvertTo-Json -Depth 4 -Compress)
}

function Get-LegacyChainEntryHash {
    param([object]$Entry)
    return Get-StringSha256Hex -Text (Get-LegacyChainEntryCanonical -Entry $Entry)
}

# ──────────────────────────────────────────────────────────────
# CORE ENFORCEMENT GATE
#
# Returns a result record describing every check.
# runtime_init_allowed = TRUE only if all mandatory checks pass.
#
# Continuation rule:
#   Entries AFTER the frozen head are allowed IFF they form a valid
#   hash chain anchored to the frozen head's legacy chain hash.
#   Otherwise continuation_status = INVALID and init is blocked.
# ──────────────────────────────────────────────────────────────
function Invoke-LedgerBaselineEnforcementGate {
    param(
        [object]$LiveLedgerObj,
        [object]$BaselineObj,
        [string]$LiveLedgerPath,
        [string]$BaselinePath
    )

    $r = [ordered]@{
        ledger_baseline_path             = $BaselinePath
        live_ledger_path                 = $LiveLedgerPath
        stored_ledger_sha256             = [string]$BaselineObj.ledger_sha256
        computed_ledger_sha256           = ''
        stored_head_hash                 = [string]$BaselineObj.head_hash
        computed_head_hash               = ''
        frozen_segment_match_status      = 'UNKNOWN'
        continuation_status              = 'UNKNOWN'
        runtime_init_allowed_or_blocked  = 'BLOCKED'
        fallback_occurred                = $false
        regeneration_occurred            = $false
        block_reason                     = 'not_checked'
        # detailed diagnostic fields
        baseline_valid                   = $false
        baseline_entry_count             = 0
        live_entry_count                 = 0
        frozen_entry_count               = 0
        first_mismatch_entry_id          = ''
        continuation_entry_count         = 0
        continuation_bad_entry_id        = ''
    }

    # ── STEP 1: Baseline structural validation ──────────────────
    if ($null -eq $BaselineObj -or
        [string]::IsNullOrWhiteSpace([string]$BaselineObj.ledger_sha256) -or
        [string]::IsNullOrWhiteSpace([string]$BaselineObj.head_entry) -or
        [string]::IsNullOrWhiteSpace([string]$BaselineObj.head_hash) -or
        $null -eq $BaselineObj.entry_ids -or
        $null -eq $BaselineObj.entry_hashes) {
        $r.block_reason = 'baseline_structurally_invalid'
        return $r
    }
    $r.baseline_valid = $true

    $frozenEntryIds = @($BaselineObj.entry_ids | ForEach-Object { [string]$_ })
    $r.baseline_entry_count = $frozenEntryIds.Count
    $r.frozen_entry_count   = $frozenEntryIds.Count

    # ── STEP 2: Live ledger canonicalization ────────────────────
    $computedLedgerHash      = Get-CanonicalLedgerHash -LedgerObj $LiveLedgerObj
    $r.computed_ledger_sha256 = $computedLedgerHash

    $liveEntries = @($LiveLedgerObj.entries)
    $r.live_entry_count = $liveEntries.Count

    # ── STEP 3 & 4: Frozen-segment entry-ID and entry-hash check ─
    # The live ledger must contain all frozen entries in order at the same positions.
    if ($liveEntries.Count -lt $frozenEntryIds.Count) {
        $r.frozen_segment_match_status = 'FALSE'
        $r.block_reason                = 'live_ledger_has_fewer_entries_than_frozen_segment'
        return $r
    }

    for ($i = 0; $i -lt $frozenEntryIds.Count; $i++) {
        $frozenId    = $frozenEntryIds[$i]
        $liveEntryId = [string]$liveEntries[$i].entry_id

        # ID check
        if ($liveEntryId -ne $frozenId) {
            $r.frozen_segment_match_status = 'FALSE'
            $r.first_mismatch_entry_id     = $frozenId
            $r.block_reason                = ('frozen_entry_id_mismatch_at_index_' + $i)
            return $r
        }

        # Hash check
        $frozenHash = [string]$BaselineObj.entry_hashes.$frozenId
        $liveHash   = Get-CanonicalEntryHash -Entry $liveEntries[$i]
        if ($liveHash -ne $frozenHash) {
            $r.frozen_segment_match_status = 'FALSE'
            $r.first_mismatch_entry_id     = $frozenId
            $r.block_reason                = ('frozen_entry_hash_mismatch_at_' + $frozenId)
            return $r
        }
    }

    $r.frozen_segment_match_status = 'TRUE'

    # ── STEP 5: Frozen head verification ───────────────────────
    $headId       = [string]$BaselineObj.head_entry
    $headIdx      = $frozenEntryIds.Count - 1
    $computedHead = Get-CanonicalEntryHash -Entry $liveEntries[$headIdx]
    $r.computed_head_hash = $computedHead
    if ($computedHead -ne [string]$BaselineObj.head_hash) {
        $r.block_reason = 'head_hash_mismatch'
        return $r
    }

    # ── STEP 6: Continuation verification ──────────────────────
    $continuationEntries = @($liveEntries | Select-Object -Skip $frozenEntryIds.Count)
    $r.continuation_entry_count = $continuationEntries.Count

    if ($continuationEntries.Count -eq 0) {
        # No continuation — live ledger exactly matches frozen baseline
        $r.continuation_status = 'VALID'
    } else {
        # Validate each continuation entry is properly hash-chained from the preceding entry.
        # Use legacy chain hash (5-field canonical) matching the existing chain validator.
        $allEntries = @($liveEntries)
        $chainOk    = $true
        $badEntryId = ''

        for ($j = $frozenEntryIds.Count; $j -lt $allEntries.Count; $j++) {
            $prevLegacyHash     = Get-LegacyChainEntryHash -Entry $allEntries[$j - 1]
            $continuationEntry  = $allEntries[$j]
            $declaredPrevHash   = [string]$continuationEntry.previous_hash

            if ($declaredPrevHash -ne $prevLegacyHash) {
                $chainOk    = $false
                $badEntryId = [string]$continuationEntry.entry_id
                break
            }
        }

        if ($chainOk) {
            $r.continuation_status = 'VALID'
        } else {
            $r.continuation_status           = 'INVALID'
            $r.continuation_bad_entry_id     = $badEntryId
            $r.block_reason                  = ('continuation_previous_hash_mismatch_at_' + $badEntryId)
            return $r
        }
    }

    # ── STEP 7: Allow runtime init ──────────────────────────────
    $r.runtime_init_allowed_or_blocked = 'ALLOWED'
    $r.block_reason                    = 'none'
    return $r
}

# ──────────────────────────────────────────────────────────────
# HELPERS FOR TEST CASE CONSTRUCTION
# ──────────────────────────────────────────────────────────────

function Add-CaseRow {
    param(
        [System.Collections.Generic.List[string]]$Rows,
        [string]$CaseLabel,
        [string]$Expected,
        [object]$Result
    )
    $initStatus = [string]$Result.runtime_init_allowed_or_blocked
    $pass = ($initStatus -eq $Expected)
    $Rows.Add(('CASE ' + $CaseLabel + ' runtime_init=' + $initStatus +
               ' frozen_segment=' + [string]$Result.frozen_segment_match_status +
               ' cont=' + [string]$Result.continuation_status +
               ' reason=' + [string]$Result.block_reason +
               ' => ' + $(if ($pass) { 'PASS' } else { 'FAIL' })))
    return $pass
}

# ──────────────────────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────────────────────

$Timestamp    = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF           = Join-Path $Root ('_proof\phase47_8_trust_chain_ledger_baseline_enforcement_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$LedgerPath   = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$BaselinePath = Join-Path $Root 'control_plane\86_guard_fingerprint_trust_chain_baseline.json'

if (-not (Test-Path -LiteralPath $LedgerPath))   { throw 'Missing ledger: control_plane/70_guard_fingerprint_trust_chain.json' }
if (-not (Test-Path -LiteralPath $BaselinePath)) { throw 'Missing baseline: control_plane/86_guard_fingerprint_trust_chain_baseline.json' }

$liveLedger = Get-Content -Raw -LiteralPath $LedgerPath   | ConvertFrom-Json
$baseline   = Get-Content -Raw -LiteralPath $BaselinePath | ConvertFrom-Json
$liveEntries = @($liveLedger.entries)

$caseRows = [System.Collections.Generic.List[string]]::new()
$allCasesPass = $true

# ──────────────────────────────────────────────────────────────
# CASE A — Clean ledger baseline pass
# Expected: runtime_init = ALLOWED
# ──────────────────────────────────────────────────────────────
$caseAResult = Invoke-LedgerBaselineEnforcementGate `
    -LiveLedgerObj $liveLedger -BaselineObj $baseline `
    -LiveLedgerPath $LedgerPath -BaselinePath $BaselinePath
$caseAPass = Add-CaseRow -Rows $caseRows -CaseLabel 'A clean_ledger_baseline_pass' `
    -Expected 'ALLOWED' -Result $caseAResult
if (-not $caseAPass) { $allCasesPass = $false }

# ──────────────────────────────────────────────────────────────
# CASE B — Ledger entry addition without valid continuation (broken previous_hash)
# Expected: runtime_init = BLOCKED
# ──────────────────────────────────────────────────────────────
$caseBEntries = [System.Collections.Generic.List[object]]::new()
foreach ($e in $liveEntries) { [void]$caseBEntries.Add($e) }
$caseBInvalid = [ordered]@{
    entry_id         = 'GF-0007'
    artifact         = 'probe_entry_case_b'
    coverage_fingerprint = 'aaaa0000'
    fingerprint_hash = 'bbbb0000'
    timestamp_utc    = '2026-03-99T00:00:00Z'
    phase_locked     = '47.9'
    previous_hash    = 'WRONG_HASH_DOES_NOT_CHAIN'
}
$caseBEntries.Add($caseBInvalid)
$caseBLedger = [ordered]@{ chain_version = [int]$liveLedger.chain_version; entries = @($caseBEntries) }
$caseBResult = Invoke-LedgerBaselineEnforcementGate `
    -LiveLedgerObj $caseBLedger -BaselineObj $baseline `
    -LiveLedgerPath $LedgerPath -BaselinePath $BaselinePath
$caseBPass = Add-CaseRow -Rows $caseRows -CaseLabel 'B entry_addition_invalid_continuation' `
    -Expected 'BLOCKED' -Result $caseBResult
if (-not $caseBPass) { $allCasesPass = $false }

# ──────────────────────────────────────────────────────────────
# CASE C — Ledger entry removal (remove last frozen entry GF-0006)
# Expected: runtime_init = BLOCKED
# ──────────────────────────────────────────────────────────────
$caseCEntries = [System.Collections.Generic.List[object]]::new()
foreach ($e in $liveEntries) { [void]$caseCEntries.Add($e) }
$caseCEntries.RemoveAt($caseCEntries.Count - 1)
$caseCLedger = [ordered]@{ chain_version = [int]$liveLedger.chain_version; entries = @($caseCEntries) }
$caseCResult = Invoke-LedgerBaselineEnforcementGate `
    -LiveLedgerObj $caseCLedger -BaselineObj $baseline `
    -LiveLedgerPath $LedgerPath -BaselinePath $BaselinePath
$caseCPass = Add-CaseRow -Rows $caseRows -CaseLabel 'C entry_removal' `
    -Expected 'BLOCKED' -Result $caseCResult
if (-not $caseCPass) { $allCasesPass = $false }

# ──────────────────────────────────────────────────────────────
# CASE D — Entry order change (swap first two entries)
# Expected: runtime_init = BLOCKED
# ──────────────────────────────────────────────────────────────
$caseDEntries = [System.Collections.Generic.List[object]]::new()
foreach ($e in $liveEntries) { [void]$caseDEntries.Add($e) }
$tmp = $caseDEntries[0]
$caseDEntries[0] = $caseDEntries[1]
$caseDEntries[1] = $tmp
$caseDLedger = [ordered]@{ chain_version = [int]$liveLedger.chain_version; entries = @($caseDEntries) }
$caseDResult = Invoke-LedgerBaselineEnforcementGate `
    -LiveLedgerObj $caseDLedger -BaselineObj $baseline `
    -LiveLedgerPath $LedgerPath -BaselinePath $BaselinePath
$caseDPass = Add-CaseRow -Rows $caseRows -CaseLabel 'D entry_order_change' `
    -Expected 'BLOCKED' -Result $caseDResult
if (-not $caseDPass) { $allCasesPass = $false }

# ──────────────────────────────────────────────────────────────
# CASE E — Entry field mutation (tamper fingerprint_hash of GF-0005)
# Expected: runtime_init = BLOCKED
# ──────────────────────────────────────────────────────────────
$caseEEntries = [System.Collections.Generic.List[object]]::new()
foreach ($e in $liveEntries) {
    if ([string]$e.entry_id -eq 'GF-0005') {
        $mutated = [ordered]@{}
        foreach ($prop in $e.PSObject.Properties) {
            if ($prop.Name -eq 'fingerprint_hash') {
                $mutated[$prop.Name] = ([string]$prop.Value + 'tampered')
            } else {
                $mutated[$prop.Name] = $prop.Value
            }
        }
        $caseEEntries.Add($mutated)
    } else {
        $caseEEntries.Add($e)
    }
}
$caseELedger = [ordered]@{ chain_version = [int]$liveLedger.chain_version; entries = @($caseEEntries) }
$caseEResult = Invoke-LedgerBaselineEnforcementGate `
    -LiveLedgerObj $caseELedger -BaselineObj $baseline `
    -LiveLedgerPath $LedgerPath -BaselinePath $BaselinePath
$caseEPass = Add-CaseRow -Rows $caseRows -CaseLabel 'E entry_field_mutation' `
    -Expected 'BLOCKED' -Result $caseEResult
if (-not $caseEPass) { $allCasesPass = $false }

# ──────────────────────────────────────────────────────────────
# CASE F — Valid continuation
# Append a new entry whose previous_hash correctly chains from GF-0006's legacy hash.
# Expected: runtime_init = ALLOWED
# ──────────────────────────────────────────────────────────────
$caseFEntries = [System.Collections.Generic.List[object]]::new()
foreach ($e in $liveEntries) { [void]$caseFEntries.Add($e) }
$headLegacyHash = Get-LegacyChainEntryHash -Entry $liveEntries[$liveEntries.Count - 1]
$caseFNew = [ordered]@{
    entry_id         = 'GF-0007'
    artifact         = 'probe_valid_continuation_case_f'
    coverage_fingerprint = 'cccc0001'
    fingerprint_hash = 'dddd0001'
    timestamp_utc    = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    phase_locked     = '47.9'
    previous_hash    = $headLegacyHash
}
$caseFEntries.Add($caseFNew)
$caseFLedger = [ordered]@{ chain_version = [int]$liveLedger.chain_version; entries = @($caseFEntries) }
$caseFResult = Invoke-LedgerBaselineEnforcementGate `
    -LiveLedgerObj $caseFLedger -BaselineObj $baseline `
    -LiveLedgerPath $LedgerPath -BaselinePath $BaselinePath
$caseFPass = Add-CaseRow -Rows $caseRows -CaseLabel 'F valid_continuation' `
    -Expected 'ALLOWED' -Result $caseFResult
if (-not $caseFPass) { $allCasesPass = $false }

# ──────────────────────────────────────────────────────────────
# CASE G — Non-semantic whitespace change
# Re-serialize then re-parse the ledger (different whitespace) and enforce.
# Expected: runtime_init = ALLOWED
# ──────────────────────────────────────────────────────────────
$caseGJson   = $liveLedger | ConvertTo-Json -Depth 20 -Compress
$caseGLedger = $caseGJson | ConvertFrom-Json
$caseGResult = Invoke-LedgerBaselineEnforcementGate `
    -LiveLedgerObj $caseGLedger -BaselineObj $baseline `
    -LiveLedgerPath $LedgerPath -BaselinePath $BaselinePath
$caseGPass = Add-CaseRow -Rows $caseRows -CaseLabel 'G non_semantic_whitespace_change' `
    -Expected 'ALLOWED' -Result $caseGResult
if (-not $caseGPass) { $allCasesPass = $false }

# ──────────────────────────────────────────────────────────────
# GATE
# ──────────────────────────────────────────────────────────────
$Gate = if ($allCasesPass) { 'PASS' } else { 'FAIL' }

# ──────────────────────────────────────────────────────────────
# PROOF PACKET
# ──────────────────────────────────────────────────────────────
$status = @(
    'phase=47.8',
    'title=Trust-Chain Ledger Baseline Enforcement',
    ('gate=' + $Gate),
    ('baseline_path=' + $BaselinePath),
    ('live_ledger_path=' + $LedgerPath),
    ('clean_gate_status=' + [string]$caseAResult.runtime_init_allowed_or_blocked),
    ('frozen_segment_match=' + [string]$caseAResult.frozen_segment_match_status),
    ('continuation_status=' + [string]$caseAResult.continuation_status),
    ('fallback_occurred=FALSE'),
    ('regeneration_occurred=FALSE'),
    'runtime_state_machine_changed=NO'
)
Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value ($status -join "`r`n") -Encoding UTF8 -NoNewline

$head = @(
    'runner=tools/phase47_8/phase47_8_trust_chain_ledger_baseline_enforcement_runner.ps1',
    ('ledger_path=' + $LedgerPath),
    ('baseline_path=' + $BaselinePath),
    ('live_entry_count=' + [string]$caseAResult.live_entry_count),
    ('frozen_entry_count=' + [string]$caseAResult.frozen_entry_count),
    ('computed_ledger_sha256=' + [string]$caseAResult.computed_ledger_sha256),
    ('stored_ledger_sha256=' + [string]$caseAResult.stored_ledger_sha256)
)
Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value ($head -join "`r`n") -Encoding UTF8 -NoNewline

$def = @(
    'LEDGER BASELINE ENFORCEMENT DEFINITION (PHASE 47.8)',
    '',
    'Runtime initialization is blocked unless the live ledger passes all of the following checks:',
    '',
    '  STEP 1: Baseline artifact (control_plane/86) must exist and be structurally valid.',
    '  STEP 2: Live ledger is parsed and canonicalized (object key sort, array order preserved).',
    '  STEP 3: For each frozen entry ID (in order), the live entry ID at the same position must match.',
    '  STEP 4: For each frozen entry, the canonical hash of the live entry must match the stored entry hash.',
    '  STEP 5: The canonical hash of the live entry at the frozen head position must match stored head_hash.',
    '  STEP 6: If the live ledger has entries beyond the frozen head, each must carry a previous_hash that',
    '          correctly matches the legacy chain hash of the preceding entry (5-field canonical model).',
    '          If any continuation entry fails this check, continuation_status=INVALID and init is blocked.',
    '  STEP 7: If all checks pass, runtime_init = ALLOWED.',
    '',
    'No fallback is performed. No regeneration is performed. Failures halt initialization immediately.'
)
Set-Content -LiteralPath (Join-Path $PF '10_ledger_baseline_enforcement_definition.txt') -Value ($def -join "`r`n") -Encoding UTF8 -NoNewline

$rules = @(
    'ENFORCEMENT RULES (PHASE 47.8)',
    '',
    '1. ledger_baseline_artifact_must_exist                 — block if control_plane/86 absent',
    '2. ledger_baseline_must_be_structurally_valid          — block if required fields missing',
    '3. live_frozen_segment_entry_ids_must_match_in_order   — block on ID mismatch at any position',
    '4. live_frozen_segment_entry_hashes_must_match         — block on canonical hash mismatch',
    '5. frozen_head_hash_must_match                         — block if head entry hash differs',
    '6. continuation_entries_must_be_validly_chained        — block if any continuation previous_hash broken',
    '7. no_fallback                                         — never generate or substitute baseline',
    '8. no_regeneration                                     — never overwrite control_plane/86',
    '9. whitespace_insensitive                              — canonical hash derived from parsed object only'
)
Set-Content -LiteralPath (Join-Path $PF '11_ledger_baseline_enforcement_rules.txt') -Value ($rules -join "`r`n") -Encoding UTF8 -NoNewline

$filesTouched = @(
    ('READ  ' + $LedgerPath),
    ('READ  ' + $BaselinePath),
    ('WRITE ' + (Join-Path $PF '*'))
)
Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Value ($filesTouched -join "`r`n") -Encoding UTF8 -NoNewline

$build = @(
    'build_type=PowerShell ledger baseline enforcement gate runner',
    'compile_required=no',
    'runtime_behavior_changed=no',
    'operation=deterministic enforcement gate with 7-step ledger baseline verification and 7 test cases'
)
Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Value ($build -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Value ($caseRows -join "`r`n") -Encoding UTF8 -NoNewline

$summary = @(
    'Phase 47.8 implements a mandatory 7-step runtime enforcement gate over the Phase 47.7 ledger baseline.',
    'The gate checks the frozen segment (all 6 entries GF-0001..GF-0006) by canonical hash before runtime init.',
    'Entry ID mismatch, hash mismatch, head hash mismatch, or invalid continuation all block initialization.',
    'A valid continuation (entries after GF-0006 with correct previous_hash linkage) is explicitly allowed.',
    'Non-semantic whitespace changes do not block because hashes are derived from the parsed object, not raw bytes.',
    'No fallback or regeneration is ever performed; if the baseline is missing or corrupt the gate fails hard.',
    'Runtime behavior remained unchanged; the state machine is unmodified.'
)
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value ($summary -join "`r`n") -Encoding UTF8 -NoNewline

$enfRecord = @(
    # Case A (clean) — full detailed record
    'case=A (clean)',
    ('  ledger_baseline_path='            + [string]$caseAResult.ledger_baseline_path),
    ('  live_ledger_path='                + [string]$caseAResult.live_ledger_path),
    ('  stored_ledger_sha256='            + [string]$caseAResult.stored_ledger_sha256),
    ('  computed_ledger_sha256='          + [string]$caseAResult.computed_ledger_sha256),
    ('  stored_head_hash='                + [string]$caseAResult.stored_head_hash),
    ('  computed_head_hash='              + [string]$caseAResult.computed_head_hash),
    ('  frozen_segment_match_status='     + [string]$caseAResult.frozen_segment_match_status),
    ('  continuation_status='             + [string]$caseAResult.continuation_status),
    ('  runtime_init_allowed_or_blocked=' + [string]$caseAResult.runtime_init_allowed_or_blocked),
    ('  fallback_occurred='               + [string]$caseAResult.fallback_occurred),
    ('  regeneration_occurred='           + [string]$caseAResult.regeneration_occurred),
    ('  block_reason='                    + [string]$caseAResult.block_reason)
)
Set-Content -LiteralPath (Join-Path $PF '16_ledger_baseline_enforcement_record.txt') -Value ($enfRecord -join "`r`n") -Encoding UTF8 -NoNewline

$blockEvidence = @(
    ('caseB continuation_status='    + [string]$caseBResult.continuation_status    + ' block_reason=' + [string]$caseBResult.block_reason),
    ('caseC frozen_segment_match='   + [string]$caseCResult.frozen_segment_match_status + ' block_reason=' + [string]$caseCResult.block_reason),
    ('caseD frozen_segment_match='   + [string]$caseDResult.frozen_segment_match_status + ' block_reason=' + [string]$caseDResult.block_reason),
    ('caseE frozen_segment_match='   + [string]$caseEResult.frozen_segment_match_status + ' block_reason=' + [string]$caseEResult.block_reason),
    ('caseF continuation_status='    + [string]$caseFResult.continuation_status    + ' runtime_init=' + [string]$caseFResult.runtime_init_allowed_or_blocked),
    ('caseG computed_sha256='        + [string]$caseGResult.computed_ledger_sha256 + ' runtime_init=' + [string]$caseGResult.runtime_init_allowed_or_blocked),
    'fallback_occurred=FALSE',
    'regeneration_occurred=FALSE'
)
Set-Content -LiteralPath (Join-Path $PF '17_runtime_block_evidence.txt') -Value ($blockEvidence -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '98_gate_phase47_8.txt') -Value $Gate -Encoding UTF8 -NoNewline

# ZIP
$ZIP     = "$PF.zip"
$staging = "${PF}_copy"
if (Test-Path -LiteralPath $staging) {
    Remove-Item -Recurse -Force -LiteralPath $staging
}
New-Item -ItemType Directory -Path $staging | Out-Null
Get-ChildItem -Path $PF -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $staging $_.Name) -Force
}
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $ZIP -Force
Remove-Item -Recurse -Force -LiteralPath $staging

Write-Output "PF=$PF"
Write-Output "ZIP=$ZIP"
Write-Output "GATE=$Gate"
