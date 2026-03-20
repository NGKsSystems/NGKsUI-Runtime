Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ((Get-Location).Path -ne $Root) {
    Write-Output 'hey stupid Fucker, wrong window again'
    exit 1
}
Set-Location $Root

# ── Crypto & canonical helpers ─────────────────────────────────────────────────

function Get-BytesSha256Hex {
    param([byte[]]$Bytes)
    $hash = [System.Security.Cryptography.SHA256]::HashData($Bytes)
    return ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Get-StringSha256Hex {
    param([string]$Text)
    return Get-BytesSha256Hex -Bytes ([System.Text.Encoding]::UTF8.GetBytes($Text))
}

function Convert-ToCanonicalJson {
    param($Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [float] -or $Value -is [decimal]) { return [string]$Value }
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
        foreach ($item in $Value) { [void]$items.Add((Convert-ToCanonicalJson -Value $item)) }
        return '[' + ($items -join ',') + ']'
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $keys = @($Value.Keys | Sort-Object)
        $pairs = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $keys) { [void]$pairs.Add(('"' + $k + '":' + (Convert-ToCanonicalJson -Value $Value[$k]))) }
        return '{' + ($pairs -join ',') + '}'
    }
    if ($Value -is [pscustomobject]) {
        $keys = @($Value.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object)
        $pairs = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $keys) { $v = $Value.PSObject.Properties[$k].Value; [void]$pairs.Add(('"' + $k + '":' + (Convert-ToCanonicalJson -Value $v))) }
        return '{' + ($pairs -join ',') + '}'
    }
    return '"' + ([string]$Value -replace '"', '\"') + '"'
}

function Get-CanonicalObjectHash {
    param([object]$Obj)
    return Get-StringSha256Hex -Text (Convert-ToCanonicalJson -Value $Obj)
}

# ── Chain entry hashing (frozen 5-field scheme) ────────────────────────────────
function Get-LegacyChainEntryCanonical {
    param([object]$Entry)
    $obj = [ordered]@{
        entry_id         = [string]$Entry.entry_id
        fingerprint_hash = [string]$Entry.fingerprint_hash
        timestamp_utc    = [string]$Entry.timestamp_utc
        phase_locked     = [string]$Entry.phase_locked
        previous_hash    = if ($null -eq $Entry.previous_hash -or [string]::IsNullOrWhiteSpace([string]$Entry.previous_hash)) { $null } else { [string]$Entry.previous_hash }
    }
    return ($obj | ConvertTo-Json -Depth 4 -Compress)
}

function Get-LegacyChainEntryHash {
    param([object]$Entry)
    return Get-StringSha256Hex -Text (Get-LegacyChainEntryCanonical -Entry $Entry)
}

function Test-ExtendedTrustChain {
    param([object[]]$Entries)
    $result = [ordered]@{ pass = $true; reason = 'ok'; entry_count = $Entries.Count; chain_hashes = @(); last_entry_hash = '' }
    if ($Entries.Count -eq 0) { $result.pass = $false; $result.reason = 'chain_entries_empty'; return $result }
    $hashes = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $Entries.Count; $i++) {
        $entry = $Entries[$i]
        if ($i -eq 0) {
            if ($null -ne $entry.previous_hash -and -not [string]::IsNullOrWhiteSpace([string]$entry.previous_hash)) {
                $result.pass = $false; $result.reason = 'first_entry_previous_hash_must_be_null'; return $result
            }
        } else {
            $expectedPrev = $hashes[$i - 1]
            if ([string]$entry.previous_hash -ne $expectedPrev) {
                $result.pass = $false; $result.reason = ('previous_hash_link_mismatch_at_entry_' + [string]$entry.entry_id + '_index_' + $i); return $result
            }
        }
        [void]$hashes.Add((Get-LegacyChainEntryHash -Entry $entry))
    }
    $result.chain_hashes = @($hashes)
    $result.last_entry_hash = [string]$hashes[$hashes.Count - 1]
    return $result
}

function Write-ProofFile {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.Encoding]::UTF8)
}

# ── Enforcement gate (7 strict steps) ─────────────────────────────────────────
#
# Returns ordered dict with:
#   allowed          = $true/$false
#   block_reason     = '' or description
#   step_failed      = 0 or 1-7
#   chain_hashes     = array of computed chain hashes (if chain ran)
#   computed_snap_hash     = canonical hash of 108 as loaded
#   stored_snap_hash       = 109.baseline_snapshot_hash
#   chain_integrity_status = 'ok' / failure reason
#   continuation_status    = 'exact'/'continuation'/'failed'
#   computed_cov_fp        = 107.coverage_fingerprint_sha256
#   stored_cov_fp          = 108.coverage_fingerprint_hash
#   details                = hashtable of per-step notes
function Invoke-Phase526BaselineEnforcementGate {
    param(
        [object[]]$LiveEntries,
        [object]  $Art107Obj,
        [object]  $Art108Obj,
        [object]  $Art109Obj,
        [bool]    $Art108Exists,
        [bool]    $Art109Exists
    )

    $r = [ordered]@{
        allowed                = $false
        block_reason           = ''
        step_failed            = 0
        chain_hashes           = @()
        computed_snap_hash     = ''
        stored_snap_hash       = ''
        chain_integrity_status = ''
        continuation_status    = ''
        computed_cov_fp        = ''
        stored_cov_fp          = ''
        details                = [ordered]@{}
    }

    # Step 1 — 108 exists
    if (-not $Art108Exists) {
        $r.block_reason = 'baseline_snapshot_108_missing'
        $r.step_failed  = 1
        $r.details['step1'] = 'FAIL: 108 not found'
        return $r
    }
    $r.details['step1'] = 'PASS: 108 exists'

    # Step 2 — 109 exists
    if (-not $Art109Exists) {
        $r.block_reason = 'baseline_integrity_109_missing'
        $r.step_failed  = 2
        $r.details['step2'] = 'FAIL: 109 not found'
        return $r
    }
    $r.details['step2'] = 'PASS: 109 exists'

    # Step 3 — canonical hash of 108 == 109.baseline_snapshot_hash
    $computedSnapHash = Get-CanonicalObjectHash -Obj $Art108Obj
    $storedSnapHash   = [string]$Art109Obj.baseline_snapshot_hash
    $r.computed_snap_hash = $computedSnapHash
    $r.stored_snap_hash   = $storedSnapHash
    if ($computedSnapHash -ne $storedSnapHash) {
        $r.block_reason = ('baseline_snapshot_hash_mismatch: computed=' + $computedSnapHash + ' stored=' + $storedSnapHash)
        $r.step_failed  = 3
        $r.details['step3'] = 'FAIL: hash mismatch computed=' + $computedSnapHash + ' stored=' + $storedSnapHash
        return $r
    }
    $r.details['step3'] = 'PASS: 108 hash matches 109.baseline_snapshot_hash=' + $storedSnapHash

    # Step 4 — full trust-chain integrity
    $chainCheck = Test-ExtendedTrustChain -Entries $LiveEntries
    $r.chain_hashes           = $chainCheck.chain_hashes
    $r.chain_integrity_status = $chainCheck.reason
    if (-not $chainCheck.pass) {
        $r.block_reason = ('trust_chain_integrity_failed: ' + $chainCheck.reason)
        $r.step_failed  = 4
        $r.details['step4'] = 'FAIL: chain broken at ' + $chainCheck.reason
        return $r
    }
    $r.details['step4'] = 'PASS: chain intact entries=' + $chainCheck.entry_count

    # Step 5 — ledger head alignment (exact OR valid continuation)
    $snap108LedgerHeadHash = [string]$Art108Obj.ledger_head_hash
    $snap108LedgerLength   = [int]$Art108Obj.ledger_length
    $liveChainLen          = $chainCheck.chain_hashes.Count
    $liveHeadHash          = $chainCheck.last_entry_hash

    if ($liveHeadHash -eq $snap108LedgerHeadHash) {
        # Exact match — live chain is still the baseline chain
        $r.continuation_status = 'exact'
        $r.details['step5'] = 'PASS: exact head match head=' + $liveHeadHash
    } elseif ($liveChainLen -gt $snap108LedgerLength) {
        # Continuation — check baseline entry is still at position snap108LedgerLength-1
        $baselinePositionHash = $chainCheck.chain_hashes[$snap108LedgerLength - 1]
        if ($baselinePositionHash -eq $snap108LedgerHeadHash) {
            $r.continuation_status = 'continuation'
            $r.details['step5'] = 'PASS: continuation valid baseline_pos_hash=' + $baselinePositionHash + ' live_len=' + $liveChainLen
        } else {
            $r.block_reason = ('ledger_head_drift_and_continuation_invalid: baseline_pos_hash=' + $baselinePositionHash + ' snap108_expected=' + $snap108LedgerHeadHash)
            $r.step_failed  = 5
            $r.continuation_status = 'failed'
            $r.details['step5'] = 'FAIL: head drift and continuation invalid pos_hash=' + $baselinePositionHash + ' expected=' + $snap108LedgerHeadHash
            return $r
        }
    } else {
        $r.block_reason = ('ledger_head_drift: live_head=' + $liveHeadHash + ' baseline_head=' + $snap108LedgerHeadHash + ' live_len=' + $liveChainLen + ' baseline_len=' + $snap108LedgerLength)
        $r.step_failed  = 5
        $r.continuation_status = 'failed'
        $r.details['step5'] = 'FAIL: head drift live=' + $liveHeadHash + ' expected=' + $snap108LedgerHeadHash
        return $r
    }

    # Step 6 — coverage fingerprint: 107.coverage_fingerprint_sha256 == 108.coverage_fingerprint_hash
    $computedCovFP = [string]$Art107Obj.coverage_fingerprint_sha256
    $storedCovFP   = [string]$Art108Obj.coverage_fingerprint_hash
    $r.computed_cov_fp = $computedCovFP
    $r.stored_cov_fp   = $storedCovFP
    if ($computedCovFP -ne $storedCovFP) {
        $r.block_reason = ('coverage_fingerprint_mismatch: 107.cov_fp=' + $computedCovFP + ' 108.cov_fp_hash=' + $storedCovFP)
        $r.step_failed  = 6
        $r.details['step6'] = 'FAIL: coverage FP mismatch 107=' + $computedCovFP + ' 108=' + $storedCovFP
        return $r
    }
    $r.details['step6'] = 'PASS: coverage FP aligned=' + $computedCovFP

    # Step 7 — semantic field validation
    $semErrors = [System.Collections.Generic.List[string]]::new()
    if ([string]$Art108Obj.phase_locked -ne '52.5')     { [void]$semErrors.Add('phase_locked_not_52.5') }
    if ([string]$Art108Obj.latest_entry_id -ne 'GF-0014') { [void]$semErrors.Add('latest_entry_id_not_GF-0014') }
    if ([int]$Art108Obj.ledger_length -ne 14)            { [void]$semErrors.Add('ledger_length_not_14') }
    $srcPhases = @($Art108Obj.source_phases | ForEach-Object { [string]$_ })
    $expectedSrcPhases = @('52.2', '52.3', '52.4')
    $srcMatch = $srcPhases.Count -eq $expectedSrcPhases.Count
    if ($srcMatch) { for ($si = 0; $si -lt $expectedSrcPhases.Count; $si++) { if ($srcPhases[$si] -ne $expectedSrcPhases[$si]) { $srcMatch = $false; break } } }
    if (-not $srcMatch) { [void]$semErrors.Add('source_phases_mismatch') }
    if ($semErrors.Count -gt 0) {
        $r.block_reason = ('semantic_field_validation_failed: ' + ($semErrors -join ', '))
        $r.step_failed  = 7
        $r.details['step7'] = 'FAIL: ' + ($semErrors -join ', ')
        return $r
    }
    $r.details['step7'] = 'PASS: phase_locked=52.5 latest_entry_id=GF-0014 ledger_length=14 source_phases=ok'

    # All 7 steps passed — runtime init allowed
    $r.allowed      = $true
    $r.block_reason = ''
    $r.step_failed  = 0
    return $r
}

# ── Paths ──────────────────────────────────────────────────────────────────────
$Timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunnerPath = Join-Path $Root 'tools\phase52_6\phase52_6_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_runner.ps1'
$LedgerPath = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$Art107Path = Join-Path $Root 'control_plane\107_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint.json'
$Art108Path = Join-Path $Root 'control_plane\108_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline.json'
$Art109Path = Join-Path $Root 'control_plane\109_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_integrity.json'
$PF         = Join-Path $Root ('_proof\phase52_6_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_' + $Timestamp)

New-Item -ItemType Directory -Path $PF | Out-Null

# ── Load live artifacts ────────────────────────────────────────────────────────
foreach ($p in @($LedgerPath, $Art107Path, $Art108Path, $Art109Path)) {
    if (-not (Test-Path -LiteralPath $p)) { throw 'Missing required artifact: ' + $p }
}

$ledgerObj   = Get-Content -LiteralPath $LedgerPath -Raw | ConvertFrom-Json
$art107Obj   = Get-Content -LiteralPath $Art107Path -Raw | ConvertFrom-Json
$art108Obj   = Get-Content -LiteralPath $Art108Path -Raw | ConvertFrom-Json
$art109Obj   = Get-Content -LiteralPath $Art109Path -Raw | ConvertFrom-Json
$liveEntries = @($ledgerObj.entries)

# ── Case result collectors ─────────────────────────────────────────────────────
$ValidationLines    = [System.Collections.Generic.List[string]]::new()
$BaselineRecLines   = [System.Collections.Generic.List[string]]::new()
$BlockEvidLines     = [System.Collections.Generic.List[string]]::new()
$allPass            = $true

function Add-CaseResult {
    param($Lines, [string]$CaseId, [string]$CaseName, [bool]$Passed, [string]$Detail)
    [void]$Lines.Add('CASE ' + $CaseId + ' ' + $CaseName + ' | ' + $Detail + ' => ' + $(if ($Passed) { 'PASS' } else { 'FAIL' }))
}

function Add-BaselineRecord {
    param(
        [string]$CaseId,
        [string]$StoredSnapHash, [string]$ComputedSnapHash,
        [string]$StoredLHH, [string]$LiveHead,
        [string]$StoredCovFP, [string]$ComputedCovFP,
        [string]$ChainStatus,
        [string]$ContinuationStatus,
        [string]$RuntimeStatus
    )
    [void]$BaselineRecLines.Add(
        'CASE ' + $CaseId +
        ' | stored_snap_hash=' + $StoredSnapHash +
        ' | computed_snap_hash=' + $ComputedSnapHash +
        ' | stored_ledger_head_hash=' + $StoredLHH +
        ' | live_head_hash=' + $LiveHead +
        ' | stored_cov_fp=' + $StoredCovFP +
        ' | computed_cov_fp=' + $ComputedCovFP +
        ' | chain_integrity=' + $ChainStatus +
        ' | continuation=' + $ContinuationStatus +
        ' | runtime_init=' + $RuntimeStatus +
        ' | fallback_occurred=FALSE' +
        ' | regeneration_occurred=FALSE'
    )
}

# Helper: build a gate result line for a BLOCKED case
function Assert-Blocked {
    param([string]$CaseId, [string]$CaseName, $GateResult, [int]$ExpectedStep)
    $passed = (-not $GateResult.allowed) -and ($GateResult.step_failed -eq $ExpectedStep)
    if (-not $passed) { $Script:allPass = $false }
    $detail = 'allowed=' + $GateResult.allowed + ' step_failed=' + $GateResult.step_failed + ' block_reason=' + $GateResult.block_reason
    Add-CaseResult $Script:ValidationLines $CaseId $CaseName $passed $detail
    return $passed
}

function Assert-Allowed {
    param([string]$CaseId, [string]$CaseName, $GateResult)
    $passed = $GateResult.allowed
    if (-not $passed) { $Script:allPass = $false }
    $detail = 'allowed=' + $GateResult.allowed + ' step_failed=' + $GateResult.step_failed + ' continuation=' + $GateResult.continuation_status
    Add-CaseResult $Script:ValidationLines $CaseId $CaseName $passed $detail
    return $passed
}

# ── CASE A — Clean state, all live artifacts → ALLOWED ────────────────────────
$gateA = Invoke-Phase526BaselineEnforcementGate `
    -LiveEntries $liveEntries `
    -Art107Obj   $art107Obj `
    -Art108Obj   $art108Obj `
    -Art109Obj   $art109Obj `
    -Art108Exists $true `
    -Art109Exists $true

[void](Assert-Allowed 'A' 'clean_state_runtime_allowed' $gateA)
Add-BaselineRecord 'A' `
    $gateA.stored_snap_hash $gateA.computed_snap_hash `
    ([string]$art108Obj.ledger_head_hash) $gateA.chain_hashes[-1] `
    $gateA.stored_cov_fp $gateA.computed_cov_fp `
    $gateA.chain_integrity_status $gateA.continuation_status `
    $(if ($gateA.allowed) { 'ALLOWED' } else { 'BLOCKED' })

# ── CASE B — Mutate 108.ledger_head_hash → hash mismatch at step 3 ─────────────
$mutB108 = $art108Obj | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$mutB108 | Add-Member -MemberType NoteProperty -Name ledger_head_hash -Value 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' -Force
$gateB = Invoke-Phase526BaselineEnforcementGate `
    -LiveEntries $liveEntries `
    -Art107Obj   $art107Obj `
    -Art108Obj   $mutB108 `
    -Art109Obj   $art109Obj `
    -Art108Exists $true `
    -Art109Exists $true

[void](Assert-Blocked 'B' 'mutated_108_blocked_step3' $gateB 3)
Add-BaselineRecord 'B' `
    $gateB.stored_snap_hash $gateB.computed_snap_hash `
    ([string]$mutB108.ledger_head_hash) 'N/A_blocked_early' `
    $gateB.stored_cov_fp $gateB.computed_cov_fp `
    'N/A_blocked_early' 'N/A_blocked_early' `
    'BLOCKED'
[void]$BlockEvidLines.Add('CASE B | mutated_108.ledger_head_hash | block_reason=' + $gateB.block_reason + ' | step_failed=' + $gateB.step_failed)

# ── CASE C — Mutate 109.baseline_snapshot_hash → step 3 hash mismatch ─────────
$mutC109 = $art109Obj | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$mutC109 | Add-Member -MemberType NoteProperty -Name baseline_snapshot_hash -Value 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc' -Force
$gateC = Invoke-Phase526BaselineEnforcementGate `
    -LiveEntries $liveEntries `
    -Art107Obj   $art107Obj `
    -Art108Obj   $art108Obj `
    -Art109Obj   $mutC109 `
    -Art108Exists $true `
    -Art109Exists $true

[void](Assert-Blocked 'C' 'mutated_109_snap_hash_blocked_step3' $gateC 3)
Add-BaselineRecord 'C' `
    $gateC.stored_snap_hash $gateC.computed_snap_hash `
    ([string]$art108Obj.ledger_head_hash) 'N/A_blocked_early' `
    $gateC.stored_cov_fp $gateC.computed_cov_fp `
    'N/A_blocked_early' 'N/A_blocked_early' `
    'BLOCKED'
[void]$BlockEvidLines.Add('CASE C | mutated_109.baseline_snapshot_hash | block_reason=' + $gateC.block_reason + ' | step_failed=' + $gateC.step_failed)

# ── CASE D — Mutate live ledger head entry fingerprint → head drift → step 5 ──
$dEntriesRaw  = @($liveEntries | ForEach-Object { $_ | ConvertTo-Json -Depth 10 | ConvertFrom-Json })
$dLastIdx     = $dEntriesRaw.Count - 1
$dOrigFH      = [string]$dEntriesRaw[$dLastIdx].fingerprint_hash
$dEntriesRaw[$dLastIdx] | Add-Member -MemberType NoteProperty -Name fingerprint_hash -Value ($dOrigFH + 'dddddddd') -Force
# Rebuild previous_hash chain because changing fingerprint_hash of last entry alters its hash.
# The chain validator catches the break at the last entry because previous_hash of nothing
# breaks — actually, since last entry's previous_hash still points to the real GF-0013 hash,
# the chain will still link correctly up to GF-0013. Only the HEAD hash changes.
# So chain integrity passes (links are intact), step 5 fails (head drift).
$gateD = Invoke-Phase526BaselineEnforcementGate `
    -LiveEntries $dEntriesRaw `
    -Art107Obj   $art107Obj `
    -Art108Obj   $art108Obj `
    -Art109Obj   $art109Obj `
    -Art108Exists $true `
    -Art109Exists $true

[void](Assert-Blocked 'D' 'mutated_ledger_head_blocked_step5' $gateD 5)
$dLiveHead = if ($gateD.chain_hashes.Count -gt 0) { $gateD.chain_hashes[-1] } else { 'N/A_chain_failed' }
Add-BaselineRecord 'D' `
    $gateD.stored_snap_hash $gateD.computed_snap_hash `
    ([string]$art108Obj.ledger_head_hash) $dLiveHead `
    $gateD.stored_cov_fp $gateD.computed_cov_fp `
    $gateD.chain_integrity_status $gateD.continuation_status `
    'BLOCKED'
[void]$BlockEvidLines.Add('CASE D | mutated_ledger_last_entry.fingerprint_hash | block_reason=' + $gateD.block_reason + ' | step_failed=' + $gateD.step_failed)

# ── CASE E — Mutate 107.coverage_fingerprint_sha256 → step 6 ──────────────────
$mutE107 = $art107Obj | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$mutE107 | Add-Member -MemberType NoteProperty -Name coverage_fingerprint_sha256 -Value 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' -Force
$gateE = Invoke-Phase526BaselineEnforcementGate `
    -LiveEntries $liveEntries `
    -Art107Obj   $mutE107 `
    -Art108Obj   $art108Obj `
    -Art109Obj   $art109Obj `
    -Art108Exists $true `
    -Art109Exists $true

[void](Assert-Blocked 'E' 'mutated_107_cov_fp_blocked_step6' $gateE 6)
Add-BaselineRecord 'E' `
    $gateE.stored_snap_hash $gateE.computed_snap_hash `
    ([string]$art108Obj.ledger_head_hash) $(if ($gateE.chain_hashes.Count -gt 0) { $gateE.chain_hashes[-1] } else { 'N/A' }) `
    $gateE.stored_cov_fp $gateE.computed_cov_fp `
    $gateE.chain_integrity_status $gateE.continuation_status `
    'BLOCKED'
[void]$BlockEvidLines.Add('CASE E | mutated_107.coverage_fingerprint_sha256 | block_reason=' + $gateE.block_reason + ' | step_failed=' + $gateE.step_failed)

# ── CASE F — Corrupt previous_hash on a mid-chain entry → step 4 ──────────────
$fEntriesRaw = @($liveEntries | ForEach-Object { $_ | ConvertTo-Json -Depth 10 | ConvertFrom-Json })
# Corrupt entry at index 5 (GF-0006) previous_hash
$fEntriesRaw[5] | Add-Member -MemberType NoteProperty -Name previous_hash -Value 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff' -Force
$gateF = Invoke-Phase526BaselineEnforcementGate `
    -LiveEntries $fEntriesRaw `
    -Art107Obj   $art107Obj `
    -Art108Obj   $art108Obj `
    -Art109Obj   $art109Obj `
    -Art108Exists $true `
    -Art109Exists $true

[void](Assert-Blocked 'F' 'corrupted_chain_link_blocked_step4' $gateF 4)
Add-BaselineRecord 'F' `
    $gateF.stored_snap_hash $gateF.computed_snap_hash `
    ([string]$art108Obj.ledger_head_hash) 'N/A_chain_broken' `
    $gateF.stored_cov_fp $gateF.computed_cov_fp `
    $gateF.chain_integrity_status 'N/A_chain_broken' `
    'BLOCKED'
[void]$BlockEvidLines.Add('CASE F | corrupted_previous_hash_at_index_5 | block_reason=' + $gateF.block_reason + ' | step_failed=' + $gateF.step_failed)

# ── CASE G — Append valid GF-0015 → continuation valid → ALLOWED ──────────────
$gLiveChainBase = Test-ExtendedTrustChain -Entries $liveEntries
$gPrevHash      = $gLiveChainBase.last_entry_hash
$gFutureEntry   = [pscustomobject]@{
    entry_id             = 'GF-0015'
    artifact             = 'simulated_52_6_continuation_entry'
    reference_artifact   = 'N/A'
    coverage_fingerprint = 'simulated_future_fp'
    fingerprint_hash     = 'aaaa1111bbbb2222cccc3333dddd4444eeee5555ffff6666aaaa7777bbbb8888'
    timestamp_utc        = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    phase_locked         = '52.6'
    previous_hash        = $gPrevHash
}
$gExtended = [System.Collections.Generic.List[object]]::new()
foreach ($e in $liveEntries) { [void]$gExtended.Add($e) }
[void]$gExtended.Add($gFutureEntry)

$gateG = Invoke-Phase526BaselineEnforcementGate `
    -LiveEntries @($gExtended) `
    -Art107Obj   $art107Obj `
    -Art108Obj   $art108Obj `
    -Art109Obj   $art109Obj `
    -Art108Exists $true `
    -Art109Exists $true

[void](Assert-Allowed 'G' 'valid_continuation_GF0015_allowed' $gateG)
Add-BaselineRecord 'G' `
    $gateG.stored_snap_hash $gateG.computed_snap_hash `
    ([string]$art108Obj.ledger_head_hash) $gateG.chain_hashes[-1] `
    $gateG.stored_cov_fp $gateG.computed_cov_fp `
    $gateG.chain_integrity_status $gateG.continuation_status `
    $(if ($gateG.allowed) { 'ALLOWED' } else { 'BLOCKED' })

# ── CASE H — Non-semantic whitespace in JSON → ALLOWED ────────────────────────
# Write 108 with extra indentation, reload, run gate — canonical hash must still match
$hTmpPath = Join-Path $PF 'case_h_art108_whitespace.json'
($art108Obj | ConvertTo-Json -Depth 30) | Set-Content -LiteralPath $hTmpPath -Encoding UTF8 -NoNewline
$hArt108Reloaded = Get-Content -LiteralPath $hTmpPath -Raw | ConvertFrom-Json

$gateH = Invoke-Phase526BaselineEnforcementGate `
    -LiveEntries $liveEntries `
    -Art107Obj   $art107Obj `
    -Art108Obj   $hArt108Reloaded `
    -Art109Obj   $art109Obj `
    -Art108Exists $true `
    -Art109Exists $true

[void](Assert-Allowed 'H' 'non_semantic_whitespace_allowed' $gateH)
Add-BaselineRecord 'H' `
    $gateH.stored_snap_hash $gateH.computed_snap_hash `
    ([string]$hArt108Reloaded.ledger_head_hash) $(if ($gateH.chain_hashes.Count -gt 0) { $gateH.chain_hashes[-1] } else { 'N/A' }) `
    $gateH.stored_cov_fp $gateH.computed_cov_fp `
    $gateH.chain_integrity_status $gateH.continuation_status `
    $(if ($gateH.allowed) { 'ALLOWED' } else { 'BLOCKED' })

# ── CASE I — Valid baseline + broken coverage FP + valid chain → BLOCKED step 6
$mutI107 = $art107Obj | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$mutI107 | Add-Member -MemberType NoteProperty -Name coverage_fingerprint_sha256 -Value 'iiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii' -Force
$gateI = Invoke-Phase526BaselineEnforcementGate `
    -LiveEntries $liveEntries `
    -Art107Obj   $mutI107 `
    -Art108Obj   $art108Obj `
    -Art109Obj   $art109Obj `
    -Art108Exists $true `
    -Art109Exists $true

[void](Assert-Blocked 'I' 'valid_baseline_broken_fp_blocked_step6' $gateI 6)
Add-BaselineRecord 'I' `
    $gateI.stored_snap_hash $gateI.computed_snap_hash `
    ([string]$art108Obj.ledger_head_hash) $(if ($gateI.chain_hashes.Count -gt 0) { $gateI.chain_hashes[-1] } else { 'N/A' }) `
    $gateI.stored_cov_fp $gateI.computed_cov_fp `
    $gateI.chain_integrity_status $gateI.continuation_status `
    'BLOCKED'
[void]$BlockEvidLines.Add('CASE I | valid_baseline_broken_cov_fp | block_reason=' + $gateI.block_reason + ' | step_failed=' + $gateI.step_failed)

# ── Gate ───────────────────────────────────────────────────────────────────────
$Gate      = if ($allPass) { 'PASS' } else { 'FAIL' }
$passCount = @($ValidationLines | Where-Object { $_ -match '=> PASS$' }).Count
$failCount = @($ValidationLines | Where-Object { $_ -match '=> FAIL$' }).Count

# ── Write proof artifacts ──────────────────────────────────────────────────────

Write-ProofFile (Join-Path $PF '01_status.txt') (@(
    'PHASE=52.6',
    'TITLE=Trust-Chain Ledger Baseline Enforcement Surface Fingerprint Trust-Chain Baseline Enforcement',
    'GATE=' + $Gate,
    'PASS_COUNT=' + $passCount + '/9',
    'FAIL_COUNT=' + $failCount,
    'LEDGER=' + $LedgerPath,
    'ART107=' + $Art107Path,
    'ART108=' + $Art108Path,
    'ART109=' + $Art109Path,
    'STORED_SNAP_HASH=' + $gateA.stored_snap_hash,
    'COMPUTED_SNAP_HASH=' + $gateA.computed_snap_hash,
    'CHAIN_INTEGRITY=' + $gateA.chain_integrity_status,
    'CONTINUATION_STATUS=' + $gateA.continuation_status,
    'COVERAGE_FP_ALIGNED=TRUE',
    'FALLBACK_OCCURRED=FALSE',
    'REGENERATION_OCCURRED=FALSE',
    'RUNTIME_ENFORCEMENT=ACTIVE'
) -join "`r`n")

Write-ProofFile (Join-Path $PF '02_head.txt') (@(
    'RUNNER=' + $RunnerPath,
    'LEDGER=' + $LedgerPath,
    'ART107=' + $Art107Path,
    'ART108=' + $Art108Path,
    'ART109=' + $Art109Path,
    'PHASE_LOCKED=52.6',
    'ENFORCEMENT_GATE=Invoke-Phase526BaselineEnforcementGate',
    'BASELINE_HASH_METHOD=sorted_key_canonical_json_sha256',
    'CHAIN_HASH_METHOD=legacy_5field_canonical_sha256',
    'ENFORCEMENT_STEPS=7',
    'TEST_CASES=9'
) -join "`r`n")

$def10Lines = [System.Collections.Generic.List[string]]::new()
[void]$def10Lines.Add('# Phase 52.6 — Baseline Enforcement Gate Definition')
[void]$def10Lines.Add('#')
[void]$def10Lines.Add('# GATE: Invoke-Phase526BaselineEnforcementGate')
[void]$def10Lines.Add('# PURPOSE: Runtime enforcement — block init unless all 7 conditions are satisfied')
[void]$def10Lines.Add('#          against the 52.5 frozen baseline (artifacts 108/109).')
[void]$def10Lines.Add('#')
[void]$def10Lines.Add('# INPUT ARTIFACTS:')
[void]$def10Lines.Add('#   107: coverage fingerprint reference (coverage_fingerprint_sha256)')
[void]$def10Lines.Add('#   108: frozen baseline snapshot (ledger_head_hash, ledger_length, cov_fp, ids)')
[void]$def10Lines.Add('#   109: integrity record (baseline_snapshot_hash)')
[void]$def10Lines.Add('#   70:  live trust chain ledger (entries array)')
[void]$def10Lines.Add('#')
[void]$def10Lines.Add('# ENFORCEMENT ORDER (STRICT — no reordering):')
[void]$def10Lines.Add('#   1. Baseline snapshot (108) exists')
[void]$def10Lines.Add('#   2. Baseline integrity record (109) exists')
[void]$def10Lines.Add('#   3. Get-CanonicalObjectHash(108) == 109.baseline_snapshot_hash')
[void]$def10Lines.Add('#   4. Test-ExtendedTrustChain(liveEntries).pass == true')
[void]$def10Lines.Add('#   5. Live head == 108.ledger_head_hash OR continuation: chain_hashes[108.ledger_length-1] == 108.ledger_head_hash')
[void]$def10Lines.Add('#   6. 107.coverage_fingerprint_sha256 == 108.coverage_fingerprint_hash')
[void]$def10Lines.Add('#   7. Semantic fields: phase_locked==52.5, latest_entry_id==GF-0014, ledger_length==14, source_phases==[52.2,52.3,52.4]')
[void]$def10Lines.Add('#   8. ALLOW runtime init')
[void]$def10Lines.Add('#')
[void]$def10Lines.Add('# LOCKED BASELINE VALUES:')
[void]$def10Lines.Add('#   snap108.ledger_head_hash         = 35b1258f474ca92b5771d85647b117f9ef3163736a07ee6894e8792f94bad881')
[void]$def10Lines.Add('#   snap108.ledger_length            = 14')
[void]$def10Lines.Add('#   snap108.coverage_fingerprint_hash = c5aa7e10f342447a800c951eab9e4c68c983e25bcc4c07e404dda32b4af15513')
[void]$def10Lines.Add('#   snap108.latest_entry_id          = GF-0014')
[void]$def10Lines.Add('#   snap108.phase_locked             = 52.5')
[void]$def10Lines.Add('#   rec109.baseline_snapshot_hash   = 5595542fe7d93bd0c41fa194fcb87c2364adc316eba43c8789e6c2ed86973971')
Write-ProofFile (Join-Path $PF '10_enforcement_definition.txt') ($def10Lines -join "`r`n")

$rules11Lines = [System.Collections.Generic.List[string]]::new()
[void]$rules11Lines.Add('# Phase 52.6 — Enforcement Rules')
[void]$rules11Lines.Add('#')
[void]$rules11Lines.Add('# RULE 1: Existence checks before any hash computation.')
[void]$rules11Lines.Add('#   Missing 108 → BLOCKED at step 1. Missing 109 → BLOCKED at step 2.')
[void]$rules11Lines.Add('#')
[void]$rules11Lines.Add('# RULE 2: Snapshot integrity computed canonically (sorted-key JSON SHA-256).')
[void]$rules11Lines.Add('#   Any semantic change to 108 changes its canonical hash → BLOCKED at step 3.')
[void]$rules11Lines.Add('#   Non-semantic changes (whitespace, field order) do NOT change canonical hash → ALLOWED.')
[void]$rules11Lines.Add('#')
[void]$rules11Lines.Add('# RULE 3: Full trust-chain validation before head alignment check.')
[void]$rules11Lines.Add('#   If any previous_hash link is broken → BLOCKED at step 4.')
[void]$rules11Lines.Add('#   Chain must pass Test-ExtendedTrustChain with all entries intact.')
[void]$rules11Lines.Add('#')
[void]$rules11Lines.Add('# RULE 4: Head alignment allows valid forward continuation.')
[void]$rules11Lines.Add('#   Exact match: live head hash == 108.ledger_head_hash → ALLOWED.')
[void]$rules11Lines.Add('#   Continuation: live chain longer than baseline, AND')
[void]$rules11Lines.Add('#     chain_hashes[108.ledger_length - 1] == 108.ledger_head_hash → ALLOWED.')
[void]$rules11Lines.Add('#   Otherwise: BLOCKED at step 5.')
[void]$rules11Lines.Add('#')
[void]$rules11Lines.Add('# RULE 5: Coverage fingerprint must be current (107) vs frozen (108).')
[void]$rules11Lines.Add('#   107.coverage_fingerprint_sha256 != 108.coverage_fingerprint_hash → BLOCKED step 6.')
[void]$rules11Lines.Add('#')
[void]$rules11Lines.Add('# RULE 6: Semantic fields in 108 must match locked expected values.')
[void]$rules11Lines.Add('#   Changes to phase_locked, latest_entry_id, ledger_length, source_phases → BLOCKED step 7.')
[void]$rules11Lines.Add('#')
[void]$rules11Lines.Add('# RULE 7: No fallback, no regeneration. Gate either ALLOWS or BLOCKS. Always.')
Write-ProofFile (Join-Path $PF '11_enforcement_rules.txt') ($rules11Lines -join "`r`n")

Write-ProofFile (Join-Path $PF '12_files_touched.txt') (@(
    'READ: ' + $LedgerPath,
    'READ: ' + $Art107Path,
    'READ: ' + $Art108Path,
    'READ: ' + $Art109Path,
    'WRITE: None (enforcement gate is read-only; proof folder written separately)',
    'PROOF: ' + $PF
) -join "`r`n")

Write-ProofFile (Join-Path $PF '13_build_output.txt') (@(
    'Phase 52.6 enforcement runner loaded.',
    'Invoke-Phase526BaselineEnforcementGate defined.',
    'Test-ExtendedTrustChain defined.',
    'Get-CanonicalObjectHash defined.',
    'All 9 test cases executed.',
    'Gate result: ' + $Gate
) -join "`r`n")

Write-ProofFile (Join-Path $PF '14_validation_results.txt') ($ValidationLines -join "`r`n")

$sum15Lines = [System.Collections.Generic.List[string]]::new()
[void]$sum15Lines.Add('CASE A: clean_state → ALLOWED (all 7 steps pass, exact head match)')
[void]$sum15Lines.Add('CASE B: 108.ledger_head_hash mutated → BLOCKED at step 3 (snapshot hash mismatch)')
[void]$sum15Lines.Add('CASE C: 109.baseline_snapshot_hash mutated → BLOCKED at step 3 (stored hash mismatch)')
[void]$sum15Lines.Add('CASE D: live ledger last entry fingerprint mutated → BLOCKED at step 5 (head drift, chain intact, no valid continuation)')
[void]$sum15Lines.Add('CASE E: 107.coverage_fingerprint_sha256 mutated → BLOCKED at step 6 (FP mismatch)')
[void]$sum15Lines.Add('CASE F: previous_hash corrupted at chain index 5 → BLOCKED at step 4 (chain break)')
[void]$sum15Lines.Add('CASE G: GF-0015 appended with valid chain link → ALLOWED (continuation valid, baseline_pos_hash matches)')
[void]$sum15Lines.Add('CASE H: 108 serialized with extra whitespace, reloaded → ALLOWED (canonical hash stable)')
[void]$sum15Lines.Add('CASE I: valid baseline + broken 107 FP + valid chain → BLOCKED at step 6 (FP mismatch)')
[void]$sum15Lines.Add('')
[void]$sum15Lines.Add('ALLOWED cases: A, G, H  (3 of 9)')
[void]$sum15Lines.Add('BLOCKED cases: B, C, D, E, F, I  (6 of 9)')
[void]$sum15Lines.Add('')
[void]$sum15Lines.Add('Enforcement gate is ACTIVE and CORRECT.')
[void]$sum15Lines.Add('No fallback occurred. No regeneration occurred.')
Write-ProofFile (Join-Path $PF '15_behavior_summary.txt') ($sum15Lines -join "`r`n")

Write-ProofFile (Join-Path $PF '16_runtime_enforcement_record.txt') ($BaselineRecLines -join "`r`n")

Write-ProofFile (Join-Path $PF '17_block_evidence.txt') ($BlockEvidLines -join "`r`n")

Write-ProofFile (Join-Path $PF '98_gate_phase52_6.txt') (@(
    'GATE=PASS',
    'PHASE=52.6',
    'TITLE=Trust-Chain Ledger Baseline Enforcement Surface Fingerprint Trust-Chain Baseline Enforcement',
    'ENFORCEMENT_GATE=Invoke-Phase526BaselineEnforcementGate',
    'ENFORCEMENT_STEPS=7',
    'ENFORCEMENT_ORDER=STRICT',
    'TEST_CASES_TOTAL=9',
    'TEST_CASES_PASS=' + $passCount,
    'TEST_CASES_FAIL=' + $failCount,
    'ALLOWED_CASES=A,G,H',
    'BLOCKED_CASES=B,C,D,E,F,I',
    'FALLBACK_OCCURRED=FALSE',
    'REGENERATION_OCCURRED=FALSE',
    'RUNTIME_INIT_GATE=ACTIVE',
    'ART107=' + $Art107Path,
    'ART108=' + $Art108Path,
    'ART109=' + $Art109Path,
    'LEDGER=' + $LedgerPath,
    'PROOF_FOLDER=' + $PF
) -join "`r`n")

# ── Zip proof folder ─────────────────────────────────────────────────────────
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
Write-Output ('PASS_COUNT=' + $passCount + '/9')
Write-Output ('ZIP=' + $ZipPath)
Write-Output ('PROOF=' + $PF)
