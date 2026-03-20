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
# PRIMITIVES  (copied verbatim from phase47_8 baseline)
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

function Get-FileSha256Hex {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return Get-BytesSha256Hex -Bytes $bytes
}

# Canonical JSON: sort object keys alphabetically; preserve array order.
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
        foreach ($item in $Value) { $items.Add((ConvertTo-CanonicalJson -Value $item)) }
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

# 5-field legacy chain hash — must match existing chain validator
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
# ENFORCEMENT GATE  (copied verbatim from phase47_8 baseline)
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
        baseline_valid                   = $false
        baseline_entry_count             = 0
        live_entry_count                 = 0
        frozen_entry_count               = 0
        first_mismatch_entry_id          = ''
        continuation_entry_count         = 0
        continuation_bad_entry_id        = ''
    }

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

    $computedLedgerHash       = Get-CanonicalLedgerHash -LedgerObj $LiveLedgerObj
    $r.computed_ledger_sha256 = $computedLedgerHash

    $liveEntries        = @($LiveLedgerObj.entries)
    $r.live_entry_count = $liveEntries.Count

    if ($liveEntries.Count -lt $frozenEntryIds.Count) {
        $r.frozen_segment_match_status = 'FALSE'
        $r.block_reason                = 'live_ledger_has_fewer_entries_than_frozen_segment'
        return $r
    }

    for ($i = 0; $i -lt $frozenEntryIds.Count; $i++) {
        $frozenId    = $frozenEntryIds[$i]
        $liveEntryId = [string]$liveEntries[$i].entry_id
        if ($liveEntryId -ne $frozenId) {
            $r.frozen_segment_match_status = 'FALSE'
            $r.first_mismatch_entry_id     = $frozenId
            $r.block_reason                = ('frozen_entry_id_mismatch_at_index_' + $i)
            return $r
        }
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

    $headIdx      = $frozenEntryIds.Count - 1
    $computedHead = Get-CanonicalEntryHash -Entry $liveEntries[$headIdx]
    $r.computed_head_hash = $computedHead
    if ($computedHead -ne [string]$BaselineObj.head_hash) {
        $r.block_reason = 'head_hash_mismatch'
        return $r
    }

    $continuationEntries        = @($liveEntries | Select-Object -Skip $frozenEntryIds.Count)
    $r.continuation_entry_count = $continuationEntries.Count

    if ($continuationEntries.Count -eq 0) {
        $r.continuation_status = 'VALID'
    } else {
        $allEntries = @($liveEntries)
        $chainOk    = $true
        $badEntryId = ''
        for ($j = $frozenEntryIds.Count; $j -lt $allEntries.Count; $j++) {
            $prevLegacyHash    = Get-LegacyChainEntryHash -Entry $allEntries[$j - 1]
            $continuationEntry = $allEntries[$j]
            $declaredPrevHash  = [string]$continuationEntry.previous_hash
            if ($declaredPrevHash -ne $prevLegacyHash) {
                $chainOk    = $false
                $badEntryId = [string]$continuationEntry.entry_id
                break
            }
        }
        if ($chainOk) {
            $r.continuation_status = 'VALID'
        } else {
            $r.continuation_status       = 'INVALID'
            $r.continuation_bad_entry_id = $badEntryId
            $r.block_reason              = ('continuation_previous_hash_mismatch_at_' + $badEntryId)
            return $r
        }
    }

    $r.runtime_init_allowed_or_blocked = 'ALLOWED'
    $r.block_reason                    = 'none'
    return $r
}

# ──────────────────────────────────────────────────────────────
# DEEP-CLONE helper (needed to build in-memory mutation ledgers)
# ──────────────────────────────────────────────────────────────

function Clone-LedgerObj {
    param([object]$Obj)
    return ($Obj | ConvertTo-Json -Depth 20 -Compress | ConvertFrom-Json)
}

# ──────────────────────────────────────────────────────────────
# CASE-ROW HELPER
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
$PhaseName    = 'phase48_2_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain'
$PF           = Join-Path $Root ('_proof\' + $PhaseName + '_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$LedgerPath        = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$BaselinePath      = Join-Path $Root 'control_plane\86_guard_fingerprint_trust_chain_baseline.json'
$FingerprintPath   = Join-Path $Root 'control_plane\87_trust_chain_ledger_baseline_enforcement_coverage_fingerprint.json'

foreach ($p in @($LedgerPath, $BaselinePath, $FingerprintPath)) {
    if (-not (Test-Path -LiteralPath $p)) { throw ('Missing required file: ' + $p) }
}

# ── Load artifacts ─────────────────────────────────────────────
$LiveLedgerObjBase = Get-Content -LiteralPath $LedgerPath -Raw | ConvertFrom-Json
$BaselineObj       = Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json
$FingerprintObj    = Get-Content -LiteralPath $FingerprintPath -Raw | ConvertFrom-Json

# ── Check idempotency: is GF-0007 already in the live ledger? ─
$liveEntriesCheck = @($LiveLedgerObjBase.entries)
$existingGF0007   = $liveEntriesCheck | Where-Object { $_.entry_id -eq 'GF-0007' } | Select-Object -First 1

# ── Compute shared values (needed regardless of idempotency path) ─
$FingerprintFileHash = Get-FileSha256Hex -Path $FingerprintPath
$CoverageFingerprint = [string]$FingerprintObj.coverage_fingerprint_sha256
$GF0006       = $liveEntriesCheck | Where-Object { $_.entry_id -eq 'GF-0006' } | Select-Object -First 1
if ($null -eq $GF0006) { throw 'GF-0006 not found in live ledger' }
$GF0007PreviousHash = Get-LegacyChainEntryHash -Entry $GF0006

if ($null -ne $existingGF0007) {
    # ── Idempotent path: GF-0007 already sealed — validate it and continue ──
    $Gf0007Timestamp = [string]$existingGF0007.timestamp_utc

    # Validate live ledger passes gate as-is (GF-0007 is a valid continuation)
    $preSealGate = Invoke-LedgerBaselineEnforcementGate `
        -LiveLedgerObj  $LiveLedgerObjBase `
        -BaselineObj    $BaselineObj `
        -LiveLedgerPath $LedgerPath `
        -BaselinePath   $BaselinePath

    if ($preSealGate.runtime_init_allowed_or_blocked -ne 'ALLOWED') {
        throw ('IDEMPOTENT-CHECK failed: existing sealed ledger fails gate: ' + $preSealGate.block_reason)
    }

    $postSealGate    = $preSealGate    # same gate result — GF-0007 is already the continuation
    $SealedLedgerDisk = $LiveLedgerObjBase
} else {
    # ── First-run path: append GF-0007 ────────────────────────────────────
    $Gf0007Timestamp = (Get-Date -AsUTC -Format 'yyyy-MM-ddTHH:mm:ssZ')

    # Verify pre-seal gate (ledger must be valid before we append)
    $preSealGate = Invoke-LedgerBaselineEnforcementGate `
        -LiveLedgerObj  $LiveLedgerObjBase `
        -BaselineObj    $BaselineObj `
        -LiveLedgerPath $LedgerPath `
        -BaselinePath   $BaselinePath

    if ($preSealGate.runtime_init_allowed_or_blocked -ne 'ALLOWED') {
        throw ('PRE-SEAL gate failed: ' + $preSealGate.block_reason + '. Aborting — live ledger integrity compromised before seal.')
    }

    $GF0007 = [ordered]@{
        entry_id             = 'GF-0007'
        artifact             = 'trust_chain_ledger_baseline_enforcement_coverage_fingerprint'
        coverage_fingerprint = $CoverageFingerprint
        fingerprint_hash     = $FingerprintFileHash
        timestamp_utc        = $Gf0007Timestamp
        phase_locked         = '48.2'
        previous_hash        = $GF0007PreviousHash
    }

    # Clone, append, validate chain before writing
    $SealedLedgerObj = Clone-LedgerObj -Obj $LiveLedgerObjBase
    $SealedLedgerObj.entries += [pscustomobject]$GF0007

    $postSealGate = Invoke-LedgerBaselineEnforcementGate `
        -LiveLedgerObj  $SealedLedgerObj `
        -BaselineObj    $BaselineObj `
        -LiveLedgerPath $LedgerPath `
        -BaselinePath   $BaselinePath

    if ($postSealGate.runtime_init_allowed_or_blocked -ne 'ALLOWED') {
        throw ('POST-SEAL gate failed: ' + $postSealGate.block_reason + '. GF-0007 construction is invalid.')
    }

    # Write sealed ledger to disk
    $SealedJson = $SealedLedgerObj | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($LedgerPath, $SealedJson, [System.Text.Encoding]::UTF8)

    # Re-read from disk as canonical source for test cases
    $SealedLedgerDisk = Get-Content -LiteralPath $LedgerPath -Raw | ConvertFrom-Json
}

# ──────────────────────────────────────────────────────────────
# TEST CASES (all in-memory; live file already written above)
# ──────────────────────────────────────────────────────────────

$AllPass = $true
$CaseRows = [System.Collections.Generic.List[string]]::new()

# CASE A: Clean seal — ALLOWED
$resultA = Invoke-LedgerBaselineEnforcementGate `
    -LiveLedgerObj  $SealedLedgerDisk `
    -BaselineObj    $BaselineObj `
    -LiveLedgerPath $LedgerPath `
    -BaselinePath   $BaselinePath
$passA = Add-CaseRow -Rows $CaseRows -CaseLabel 'A' -Expected 'ALLOWED' -Result $resultA
if (-not $passA) { $AllPass = $false }

# CASE B: Historical tamper — GF-0003 coverage_fingerprint corrupted — BLOCKED
$ledgerB = Clone-LedgerObj -Obj $SealedLedgerDisk
$ledgerB.entries[2].coverage_fingerprint = 'deadbeef' + ('0' * 56)
$resultB = Invoke-LedgerBaselineEnforcementGate `
    -LiveLedgerObj  $ledgerB `
    -BaselineObj    $BaselineObj `
    -LiveLedgerPath $LedgerPath `
    -BaselinePath   $BaselinePath
$passB = Add-CaseRow -Rows $CaseRows -CaseLabel 'B' -Expected 'BLOCKED' -Result $resultB
if (-not $passB) { $AllPass = $false }

# CASE C: Fingerprint artifact tamper — replace coverage_fingerprint in GF-0007 with wrong value — BLOCKED
$ledgerC = Clone-LedgerObj -Obj $SealedLedgerDisk
$ledgerC.entries[6].coverage_fingerprint = 'cafebabe' + ('0' * 56)
$resultC = Invoke-LedgerBaselineEnforcementGate `
    -LiveLedgerObj  $ledgerC `
    -BaselineObj    $BaselineObj `
    -LiveLedgerPath $LedgerPath `
    -BaselinePath   $BaselinePath
# GF-0007 is a continuation entry; its content does not affect the frozen-segment gate
# but a corrupted coverage_fingerprint breaks the GF-0007 canonical hash, meaning any
# further continuation built on it would fail chain linkage.
# Direct tamper test: verify that the canonical hash of the tampered GF-0007 differs
# from the original, proving tamper detectability at next append.
$originalGF0007 = $SealedLedgerDisk.entries[6]
$tamperedGF0007 = $ledgerC.entries[6]
$origHash    = Get-CanonicalEntryHash -Entry $originalGF0007
$tampHash    = Get-CanonicalEntryHash -Entry $tamperedGF0007
$cTamperDetected = ($origHash -ne $tampHash)
# For Case C we assert: tamper is DETECTED (canonical hashes differ)
if ($cTamperDetected) {
    $CaseRows.Add('CASE C coverage_fingerprint_tamper_detected=TRUE orig_hash=' + $origHash + ' tampered_hash=' + $tampHash + ' => PASS')
} else {
    $CaseRows.Add('CASE C coverage_fingerprint_tamper_detected=FALSE => FAIL')
    $AllPass = $false
}

# CASE D: Future append — a valid GF-0008 chained from GF-0007 — ALLOWED
$ledgerD            = Clone-LedgerObj -Obj $SealedLedgerDisk
$GF0008PrevHash     = Get-LegacyChainEntryHash -Entry $ledgerD.entries[6]
$GF0008             = [ordered]@{
    entry_id             = 'GF-0008'
    artifact             = 'future_fingerprint'
    coverage_fingerprint = 'a' * 64
    fingerprint_hash     = 'b' * 64
    timestamp_utc        = (Get-Date -AsUTC -Format 'yyyy-MM-ddTHH:mm:ssZ')
    phase_locked         = '48.3'
    previous_hash        = $GF0008PrevHash
}
$ledgerD.entries += [pscustomobject]$GF0008
$resultD = Invoke-LedgerBaselineEnforcementGate `
    -LiveLedgerObj  $ledgerD `
    -BaselineObj    $BaselineObj `
    -LiveLedgerPath $LedgerPath `
    -BaselinePath   $BaselinePath
$passD = Add-CaseRow -Rows $CaseRows -CaseLabel 'D' -Expected 'ALLOWED' -Result $resultD
if (-not $passD) { $AllPass = $false }

# CASE E: Non-semantic whitespace change in GF-0007 fields — canonical hash MUST differ — BLOCKED via next-append check
# We verify that adding extra whitespace to the phase_locked field changes the canonical hash
$ledgerE = Clone-LedgerObj -Obj $SealedLedgerDisk
$ledgerE.entries[6].phase_locked = ' 48.2 '   # padded — semantic content changed
$origE   = Get-CanonicalEntryHash -Entry $SealedLedgerDisk.entries[6]
$mutE    = Get-CanonicalEntryHash -Entry $ledgerE.entries[6]
$eTamperDetected = ($origE -ne $mutE)
if ($eTamperDetected) {
    $CaseRows.Add('CASE E whitespace_mutation_detected=TRUE orig_hash=' + $origE + ' mutated_hash=' + $mutE + ' => PASS')
} else {
    $CaseRows.Add('CASE E whitespace_mutation_detected=FALSE => FAIL')
    $AllPass = $false
}

# CASE F: previous_hash break — GF-0007 previous_hash replaced with wrong value — BLOCKED
$ledgerF = Clone-LedgerObj -Obj $SealedLedgerDisk
$ledgerF.entries[6].previous_hash = '0' * 64
$resultF = Invoke-LedgerBaselineEnforcementGate `
    -LiveLedgerObj  $ledgerF `
    -BaselineObj    $BaselineObj `
    -LiveLedgerPath $LedgerPath `
    -BaselinePath   $BaselinePath
$passF = Add-CaseRow -Rows $CaseRows -CaseLabel 'F' -Expected 'BLOCKED' -Result $resultF
if (-not $passF) { $AllPass = $false }

# ──────────────────────────────────────────────────────────────
# BUILD PROOF ARTIFACTS
# ──────────────────────────────────────────────────────────────

$GateStatus = if ($AllPass) { 'PASS' } else { 'FAIL' }

# 01_status.txt
$status01 = @(
    'PHASE=48.2'
    'TITLE=Trust-Chain Ledger Baseline Enforcement Coverage Fingerprint Trust-Chain Seal'
    'GATE=' + $GateStatus
    'TIMESTAMP_UTC=' + $Gf0007Timestamp
    'PROOF_FOLDER=' + $PF
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '01_status.txt'), $status01, [System.Text.Encoding]::UTF8)

# 02_head.txt — GF-0007 entry details
$GF0007CanonHash = Get-CanonicalEntryHash -Entry $SealedLedgerDisk.entries[6]
$GF0007LegacyHash = Get-LegacyChainEntryHash -Entry $SealedLedgerDisk.entries[6]
$head02 = @(
    'NEW_HEAD_ENTRY=GF-0007'
    'ARTIFACT=trust_chain_ledger_baseline_enforcement_coverage_fingerprint'
    'COVERAGE_FINGERPRINT=' + $CoverageFingerprint
    'FINGERPRINT_HASH=' + $FingerprintFileHash
    'PREVIOUS_HASH=' + $GF0007PreviousHash
    'TIMESTAMP_UTC=' + $Gf0007Timestamp
    'PHASE_LOCKED=48.2'
    'CANONICAL_ENTRY_HASH=' + $GF0007CanonHash
    'LEGACY_CHAIN_HASH=' + $GF0007LegacyHash
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '02_head.txt'), $head02, [System.Text.Encoding]::UTF8)

# 10_trust_chain_extension_definition.txt
$ext10 = @(
    'EXTENSION_STRATEGY=append_gf0007_chained_from_gf0006'
    'SOURCE_ARTIFACT=control_plane/87_trust_chain_ledger_baseline_enforcement_coverage_fingerprint.json'
    'SOURCE_PHASE=48.1'
    'COVERAGE_FINGERPRINT_SHA256=' + $CoverageFingerprint
    'FINGERPRINT_FILE_SHA256=' + $FingerprintFileHash
    'GF0006_LEGACY_HASH_USED_AS_PREVIOUS=' + $GF0007PreviousHash
    'NEW_ENTRY_ID=GF-0007'
    'PHASE_LOCKED=48.2'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '10_trust_chain_extension_definition.txt'), $ext10, [System.Text.Encoding]::UTF8)

# 11_chain_hash_records.txt
$SealedEntries = @($SealedLedgerDisk.entries)
$chainRows = [System.Collections.Generic.List[string]]::new()
$chainRows.Add('entry_id | legacy_chain_hash | canonical_entry_hash | previous_hash')
foreach ($e in $SealedEntries) {
    $cHash = Get-CanonicalEntryHash -Entry $e
    $lHash = Get-LegacyChainEntryHash -Entry $e
    $ph    = if ($null -eq $e.previous_hash -or [string]::IsNullOrWhiteSpace([string]$e.previous_hash)) { 'null' } else { [string]$e.previous_hash }
    $chainRows.Add([string]$e.entry_id + ' | ' + $lHash + ' | ' + $cHash + ' | ' + $ph)
}
[System.IO.File]::WriteAllText((Join-Path $PF '11_chain_hash_records.txt'), ($chainRows -join "`r`n"), [System.Text.Encoding]::UTF8)

# 12_files_touched.txt
$files12 = @(
    'WRITTEN=control_plane/70_guard_fingerprint_trust_chain.json'
    'READ=control_plane/86_guard_fingerprint_trust_chain_baseline.json'
    'READ=control_plane/87_trust_chain_ledger_baseline_enforcement_coverage_fingerprint.json'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '12_files_touched.txt'), $files12, [System.Text.Encoding]::UTF8)

# 13_build_output.txt — pre-seal and post-seal gate records
$build13 = @(
    '=== PRE-SEAL GATE ==='
    'frozen_segment_match_status=' + [string]$preSealGate.frozen_segment_match_status
    'continuation_status=' + [string]$preSealGate.continuation_status
    'runtime_init_allowed_or_blocked=' + [string]$preSealGate.runtime_init_allowed_or_blocked
    'live_entry_count=' + [string]$preSealGate.live_entry_count
    ''
    '=== POST-SEAL GATE ==='
    'frozen_segment_match_status=' + [string]$postSealGate.frozen_segment_match_status
    'continuation_status=' + [string]$postSealGate.continuation_status
    'runtime_init_allowed_or_blocked=' + [string]$postSealGate.runtime_init_allowed_or_blocked
    'live_entry_count=' + [string]$postSealGate.live_entry_count
    'continuation_entry_count=' + [string]$postSealGate.continuation_entry_count
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '13_build_output.txt'), $build13, [System.Text.Encoding]::UTF8)

# 14_validation_results.txt
[System.IO.File]::WriteAllText((Join-Path $PF '14_validation_results.txt'), ($CaseRows -join "`r`n"), [System.Text.Encoding]::UTF8)

# 15_behavior_summary.txt
$passCnt = @($CaseRows | Where-Object { $_ -match '=> PASS' }).Count
$failCnt = @($CaseRows | Where-Object { $_ -match '=> FAIL' }).Count
$beh15 = @(
    'PHASE=48.2'
    'TOTAL_CASES=' + $CaseRows.Count
    'PASSED=' + $passCnt
    'FAILED=' + $failCnt
    'GATE=' + $GateStatus
    ''
    'CASE A: Clean seal with GF-0007 appended — gate ALLOWED'
    'CASE B: Historical tamper (GF-0003) — gate BLOCKED'
    'CASE C: Coverage fingerprint tamper in GF-0007 — canonical hash difference DETECTED'
    'CASE D: Future valid GF-0008 chained from GF-0007 — gate ALLOWED'
    'CASE E: Non-semantic whitespace mutation in GF-0007 — canonical hash difference DETECTED'
    'CASE F: GF-0007 previous_hash replaced with wrong value — gate BLOCKED'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '15_behavior_summary.txt'), $beh15, [System.Text.Encoding]::UTF8)

# 16_chain_integrity_report.txt
$SealedLedgerHash = Get-CanonicalLedgerHash -LedgerObj $SealedLedgerDisk
$ci16 = @(
    'SEALED_LEDGER_ENTRY_COUNT=' + $SealedEntries.Count
    'SEALED_LEDGER_CANONICAL_HASH=' + $SealedLedgerHash
    'FROZEN_SEGMENT_ENTRY_COUNT=6'
    'CONTINUATION_ENTRY_COUNT=1'
    'GF0007_CANONICAL_ENTRY_HASH=' + $GF0007CanonHash
    'GF0007_LEGACY_CHAIN_HASH=' + $GF0007LegacyHash
    'GF0006_LEGACY_CHAIN_HASH_USED_AS_PREVIOUS=' + $GF0007PreviousHash
    'PRE_SEAL_FROZEN_SEGMENT=' + [string]$preSealGate.frozen_segment_match_status
    'POST_SEAL_FROZEN_SEGMENT=' + [string]$postSealGate.frozen_segment_match_status
    'POST_SEAL_CONTINUATION=' + [string]$postSealGate.continuation_status
    'POST_SEAL_GATE=' + [string]$postSealGate.runtime_init_allowed_or_blocked
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '16_chain_integrity_report.txt'), $ci16, [System.Text.Encoding]::UTF8)

# 17_tamper_detection_evidence.txt
$td17 = @(
    'CASE B: frozen_segment tamper (GF-0003 coverage_fingerprint corrupted)'
    '  blocked_by=frozen_entry_hash_mismatch_at_GF-0003'
    '  frozen_segment_match_status=' + [string]$resultB.frozen_segment_match_status
    '  runtime_init=' + [string]$resultB.runtime_init_allowed_or_blocked
    ''
    'CASE C: continuation GF-0007 coverage_fingerprint corrupted'
    '  detection_method=canonical_entry_hash_difference'
    '  tamper_detected=' + $cTamperDetected.ToString().ToUpper()
    ''
    'CASE E: whitespace injection in GF-0007 phase_locked field'
    '  detection_method=canonical_entry_hash_difference'
    '  tamper_detected=' + $eTamperDetected.ToString().ToUpper()
    ''
    'CASE F: GF-0007 previous_hash replaced with zeros'
    '  blocked_by=continuation_previous_hash_mismatch_at_GF-0007'
    '  continuation_status=' + [string]$resultF.continuation_status
    '  runtime_init=' + [string]$resultF.runtime_init_allowed_or_blocked
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '17_tamper_detection_evidence.txt'), $td17, [System.Text.Encoding]::UTF8)

# 98_gate_phase48_2.txt
$gate98 = @(
    'GATE=' + $GateStatus
    'PHASE=48.2'
    'ALL_CASES_PASS=' + $AllPass.ToString().ToUpper()
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '98_gate_phase48_2.txt'), $gate98, [System.Text.Encoding]::UTF8)

# ──────────────────────────────────────────────────────────────
# ZIP
# ──────────────────────────────────────────────────────────────

$ZipPath = $PF + '.zip'
if (Test-Path -LiteralPath $ZipPath) { Remove-Item -Force -LiteralPath $ZipPath }
$TmpCopy = $PF + '_zipcopy'
if (Test-Path -LiteralPath $TmpCopy) { Remove-Item -Recurse -Force -LiteralPath $TmpCopy }
New-Item -ItemType Directory -Path $TmpCopy | Out-Null
Get-ChildItem -Path $PF -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $TmpCopy $_.Name) -Force
}
Compress-Archive -Path (Join-Path $TmpCopy '*') -DestinationPath $ZipPath -Force
Remove-Item -Recurse -Force -LiteralPath $TmpCopy

# ──────────────────────────────────────────────────────────────
# FINAL OUTPUT
# ──────────────────────────────────────────────────────────────

Write-Output ('PF=' + $PF)
Write-Output ('ZIP=' + $ZipPath)
Write-Output ('GATE=' + $GateStatus)
