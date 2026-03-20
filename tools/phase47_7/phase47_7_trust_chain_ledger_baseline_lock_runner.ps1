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

# Canonical JSON: sort object keys alphabetically; preserve array order.
# Hash is derived from parsed object, not raw file bytes — so whitespace changes are ignored.
function ConvertTo-CanonicalJson {
    param($Value)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool])   { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or
        $Value -is [float]   -or $Value -is [decimal]) {
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
    # Fallback
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

function New-BaselineArtifact {
    param(
        [object]$LedgerObj,
        [string]$LedgerSha256,
        [string]$HeadEntryId,
        [string]$HeadHash
    )

    $entries     = @($LedgerObj.entries)
    $entryIds    = @($entries | ForEach-Object { [string]$_.entry_id })
    $entryHashes = [ordered]@{}
    foreach ($e in $entries) {
        $entryHashes[[string]$e.entry_id] = Get-CanonicalEntryHash -Entry $e
    }

    return [ordered]@{
        baseline_version = 1
        ledger_file      = '70_guard_fingerprint_trust_chain.json'
        entry_count      = $entries.Count
        entry_ids        = $entryIds
        ledger_sha256    = $LedgerSha256
        entry_hashes     = $entryHashes
        head_entry       = $HeadEntryId
        head_hash        = $HeadHash
        phase_locked     = '47.7'
    }
}

function Compare-LedgerBaseline {
    param([object]$LedgerObj, [object]$Baseline)

    $r = [ordered]@{
        mismatch              = $false
        reason                = 'ok'
        current_ledger_sha256 = ''
        baseline_ledger_sha256 = ''
    }

    $currentHash              = Get-CanonicalLedgerHash -LedgerObj $LedgerObj
    $r.current_ledger_sha256  = $currentHash
    $r.baseline_ledger_sha256 = [string]$Baseline.ledger_sha256

    if ($currentHash -ne [string]$Baseline.ledger_sha256) {
        $r.mismatch = $true
        $r.reason   = 'ledger_sha256_changed'
    }
    return $r
}

# ──────────────────────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────────────────────

$Timestamp    = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF           = Join-Path $Root ('_proof\phase47_7_trust_chain_ledger_baseline_lock_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$LedgerPath   = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$BaselinePath = Join-Path $Root 'control_plane\86_guard_fingerprint_trust_chain_baseline.json'

if (-not (Test-Path -LiteralPath $LedgerPath)) {
    throw 'Missing ledger: control_plane/70_guard_fingerprint_trust_chain.json'
}

$ledgerObj   = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
$ledgerHash  = Get-CanonicalLedgerHash -LedgerObj $ledgerObj
$entries     = @($ledgerObj.entries)
$entryCount  = $entries.Count

$entryHashMap = [ordered]@{}
foreach ($e in $entries) {
    $entryHashMap[[string]$e.entry_id] = Get-CanonicalEntryHash -Entry $e
}

$headEntryId   = [string]$entries[$entryCount - 1].entry_id
$headEntryHash = $entryHashMap[$headEntryId]

$appendMode = 'unknown'
if (Test-Path -LiteralPath $BaselinePath) {
    $existingBaseline = Get-Content -Raw -LiteralPath $BaselinePath | ConvertFrom-Json
    if ([string]$existingBaseline.ledger_sha256 -eq $ledgerHash -and
        [string]$existingBaseline.phase_locked  -eq '47.7') {
        $appendMode = 'already_locked'
    } else {
        throw 'Existing baseline at control_plane/86 does not match current ledger. Ledger has changed after baseline was locked.'
    }
} else {
    $baselineObj = New-BaselineArtifact `
        -LedgerObj    $ledgerObj `
        -LedgerSha256 $ledgerHash `
        -HeadEntryId  $headEntryId `
        -HeadHash     $headEntryHash

    ($baselineObj | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $BaselinePath -Encoding UTF8 -NoNewline
    $appendMode = 'created'
}

# Reload stored baseline so all comparisons use the certified artifact on disk
$storedBaseline = Get-Content -Raw -LiteralPath $BaselinePath | ConvertFrom-Json

# ──────────────────────────────────────────────────────────────
# CASE A — Clean baseline generation
# Expected: baseline_created=TRUE, ledger_sha256_recorded=TRUE, mismatch=FALSE
# ──────────────────────────────────────────────────────────────
$caseAResult = Compare-LedgerBaseline -LedgerObj $ledgerObj -Baseline $storedBaseline
$caseA = (-not $caseAResult.mismatch) -and
         ($appendMode -in @('created', 'already_locked')) -and
         (-not [string]::IsNullOrWhiteSpace([string]$storedBaseline.ledger_sha256))

# ──────────────────────────────────────────────────────────────
# CASE B — Ledger entry addition (simulate appending GF-0007)
# Expected: baseline_mismatch=TRUE
# ──────────────────────────────────────────────────────────────
$caseBEntries = [System.Collections.Generic.List[object]]::new()
foreach ($e in $entries) { $caseBEntries.Add($e) }
$caseBNew = [ordered]@{
    entry_id             = 'GF-0007'
    artifact             = 'probe_entry_case_b'
    coverage_fingerprint = 'aaaa0000'
    fingerprint_hash     = 'bbbb0000'
    timestamp_utc        = '2026-03-99T00:00:00Z'
    phase_locked         = '47.8'
    previous_hash        = $headEntryHash
}
$caseBEntries.Add($caseBNew)
$caseBLedger = [ordered]@{ chain_version = [int]$ledgerObj.chain_version; entries = @($caseBEntries) }
$caseBResult = Compare-LedgerBaseline -LedgerObj $caseBLedger -Baseline $storedBaseline
$caseB       = $caseBResult.mismatch

# ──────────────────────────────────────────────────────────────
# CASE C — Ledger entry removal (remove last entry GF-0006)
# Expected: baseline_mismatch=TRUE
# ──────────────────────────────────────────────────────────────
$caseCEntries = [System.Collections.Generic.List[object]]::new()
for ($i = 0; $i -lt ($entryCount - 1); $i++) { $caseCEntries.Add($entries[$i]) }
$caseCLedger = [ordered]@{ chain_version = [int]$ledgerObj.chain_version; entries = @($caseCEntries) }
$caseCResult = Compare-LedgerBaseline -LedgerObj $caseCLedger -Baseline $storedBaseline
$caseC       = $caseCResult.mismatch

# ──────────────────────────────────────────────────────────────
# CASE D — Entry order change (reverse all entries)
# Expected: baseline_mismatch=TRUE
# ──────────────────────────────────────────────────────────────
$caseDEntries = [System.Collections.Generic.List[object]]::new()
for ($i = $entryCount - 1; $i -ge 0; $i--) { $caseDEntries.Add($entries[$i]) }
$caseDLedger = [ordered]@{ chain_version = [int]$ledgerObj.chain_version; entries = @($caseDEntries) }
$caseDResult = Compare-LedgerBaseline -LedgerObj $caseDLedger -Baseline $storedBaseline
$caseD       = $caseDResult.mismatch

# ──────────────────────────────────────────────────────────────
# CASE E — Non-semantic whitespace change
# Simulate: re-serialize with different formatting then re-parse.
# Canonical hash must be identical → mismatch=FALSE
# ──────────────────────────────────────────────────────────────
$caseECompressed = ($ledgerObj | ConvertTo-Json -Depth 20 -Compress)
$caseEObj        = $caseECompressed | ConvertFrom-Json
$caseEResult     = Compare-LedgerBaseline -LedgerObj $caseEObj -Baseline $storedBaseline
$caseE           = (-not $caseEResult.mismatch)

# ──────────────────────────────────────────────────────────────
# CASE F — Entry field mutation (tamper fingerprint_hash in GF-0005)
# Expected: baseline_mismatch=TRUE
# ──────────────────────────────────────────────────────────────
$caseFEntries = [System.Collections.Generic.List[object]]::new()
foreach ($e in $entries) {
    if ([string]$e.entry_id -eq 'GF-0005') {
        $mutated = [ordered]@{}
        foreach ($prop in $e.PSObject.Properties) {
            if ($prop.Name -eq 'fingerprint_hash') {
                $mutated[$prop.Name] = ([string]$prop.Value + 'tampered')
            } else {
                $mutated[$prop.Name] = $prop.Value
            }
        }
        $caseFEntries.Add($mutated)
    } else {
        $caseFEntries.Add($e)
    }
}
$caseFLedger = [ordered]@{ chain_version = [int]$ledgerObj.chain_version; entries = @($caseFEntries) }
$caseFResult = Compare-LedgerBaseline -LedgerObj $caseFLedger -Baseline $storedBaseline
$caseF       = $caseFResult.mismatch

# ──────────────────────────────────────────────────────────────
# GATE
# ──────────────────────────────────────────────────────────────
$allPass = ($caseA -and $caseB -and $caseC -and $caseD -and $caseE -and $caseF)
$Gate    = if ($allPass) { 'PASS' } else { 'FAIL' }

# ──────────────────────────────────────────────────────────────
# PROOF PACKET
# ──────────────────────────────────────────────────────────────
$status = @(
    'phase=47.7',
    'title=Trust-Chain Ledger Baseline Lock',
    ('gate='                  + $Gate),
    ('baseline_mode='         + $appendMode),
    ('ledger_sha256_recorded=' + $(if (-not [string]::IsNullOrWhiteSpace([string]$storedBaseline.ledger_sha256)) { 'TRUE' } else { 'FALSE' })),
    ('entry_count='           + [string]$entryCount),
    'runtime_state_machine_changed=NO'
)
Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value ($status -join "`r`n") -Encoding UTF8 -NoNewline

$head = @(
    'runner=tools/phase47_7/phase47_7_trust_chain_ledger_baseline_lock_runner.ps1',
    ('ledger_path='   + $LedgerPath),
    ('baseline_path=' + $BaselinePath),
    ('append_mode='   + $appendMode),
    ('entry_count='   + [string]$entryCount),
    ('head_entry_id=' + $headEntryId)
)
Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value ($head -join "`r`n") -Encoding UTF8 -NoNewline

$def = @(
    'BASELINE DEFINITION (PHASE 47.7)',
    '',
    'A canonical SHA256 digest of the full trust-chain ledger (control_plane/70) is derived by',
    'parsing the JSON and re-serializing with all object keys sorted alphabetically and array order',
    'preserved. Per-entry SHA256 digests are computed the same way for each individual entry.',
    'The head hash is the canonical hash of the last entry (GF-0006) in the current ledger.',
    'All hashes are stored as certification reference artifact 86 (control_plane/86_...).',
    '',
    'Detection guarantees:',
    '  - Entry addition:   canonical ledger hash changes (different array length)',
    '  - Entry removal:    canonical ledger hash changes (different array length)',
    '  - Entry reorder:    canonical ledger hash changes (array order preserved in canonical form)',
    '  - Field mutation:   canonical ledger hash changes (field value differs)',
    '  - Whitespace only:  canonical ledger hash unchanged (derived from parsed object, not raw bytes)'
)
Set-Content -LiteralPath (Join-Path $PF '10_baseline_definition.txt') -Value ($def -join "`r`n") -Encoding UTF8 -NoNewline

$modelLines = [System.Collections.Generic.List[string]]::new()
$modelLines.Add(('entry_count=' + [string]$entryCount))
$modelLines.Add(('ledger_sha256=' + $ledgerHash))
$modelLines.Add(('head_entry=' + $headEntryId))
$modelLines.Add(('head_hash=' + $headEntryHash))
$modelLines.Add('')
foreach ($eid in $entryHashMap.Keys) {
    $modelLines.Add(('entry_hash.' + $eid + '=' + $entryHashMap[$eid]))
}
Set-Content -LiteralPath (Join-Path $PF '11_ledger_canonical_model.txt') -Value ($modelLines -join "`r`n") -Encoding UTF8 -NoNewline

$filesTouched = @(
    ('READ  ' + $LedgerPath),
    ('WRITE ' + $BaselinePath),
    ('WRITE ' + (Join-Path $PF '*'))
)
Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Value ($filesTouched -join "`r`n") -Encoding UTF8 -NoNewline

$build = @(
    'build_type=PowerShell ledger baseline lock runner',
    'compile_required=no',
    'runtime_behavior_changed=no',
    'operation=canonical ledger hash + per-entry hashes + baseline artifact creation + mismatch detection tests'
)
Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Value ($build -join "`r`n") -Encoding UTF8 -NoNewline

$validation = @(
    ('CASE A clean_baseline_generation='      + $(if ($caseA) { 'PASS' } else { 'FAIL' })),
    ('CASE B ledger_entry_addition='          + $(if ($caseB) { 'PASS' } else { 'FAIL' })),
    ('CASE C ledger_entry_removal='           + $(if ($caseC) { 'PASS' } else { 'FAIL' })),
    ('CASE D entry_order_change='             + $(if ($caseD) { 'PASS' } else { 'FAIL' })),
    ('CASE E non_semantic_whitespace_change=' + $(if ($caseE) { 'PASS' } else { 'FAIL' })),
    ('CASE F entry_field_mutation='           + $(if ($caseF) { 'PASS' } else { 'FAIL' }))
)
Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Value ($validation -join "`r`n") -Encoding UTF8 -NoNewline

$summary = @(
    'Phase 47.7 freezes the current trust-chain ledger (control_plane/70) as a certified baseline in control_plane/86.',
    'The baseline records the canonical SHA256 of the full ledger plus individual entry hashes, ordered entry IDs, head entry and hash, and entry count.',
    'Entry addition is detected because the canonical ledger hash changes when the entries array length changes.',
    'Entry removal is detected because the canonical ledger hash changes when an entry is absent.',
    'Entry reordering is detected because canonical serialization preserves array order.',
    'Field mutations are detected because all fields of every entry participate in the canonical hash.',
    'Whitespace-only changes are not flagged as mismatches because hashes are derived from the parsed object, not raw file bytes.',
    'Runtime behavior remained unchanged; this phase only creates a reference artifact and writes proof files.'
)
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value ($summary -join "`r`n") -Encoding UTF8 -NoNewline

$storedEntryIds = @($storedBaseline.entry_ids | ForEach-Object { [string]$_ })
$baselineRecord = @(
    ('baseline_version=' + [string]$storedBaseline.baseline_version),
    ('ledger_file='      + [string]$storedBaseline.ledger_file),
    ('entry_count='      + [string]$storedBaseline.entry_count),
    ('entry_ids='        + ($storedEntryIds -join ',')),
    ('ledger_sha256='    + [string]$storedBaseline.ledger_sha256),
    ('head_entry='       + [string]$storedBaseline.head_entry),
    ('head_hash='        + [string]$storedBaseline.head_hash),
    ('phase_locked='     + [string]$storedBaseline.phase_locked)
)
Set-Content -LiteralPath (Join-Path $PF '16_baseline_record.txt') -Value ($baselineRecord -join "`r`n") -Encoding UTF8 -NoNewline

$mismatchEvidence = @(
    ('caseA mismatch_expected=FALSE actual=' + [string]$caseAResult.mismatch + ' reason=' + [string]$caseAResult.reason),
    ('caseB mismatch_expected=TRUE  actual=' + [string]$caseBResult.mismatch + ' reason=' + [string]$caseBResult.reason),
    ('caseC mismatch_expected=TRUE  actual=' + [string]$caseCResult.mismatch + ' reason=' + [string]$caseCResult.reason),
    ('caseD mismatch_expected=TRUE  actual=' + [string]$caseDResult.mismatch + ' reason=' + [string]$caseDResult.reason),
    ('caseE mismatch_expected=FALSE actual=' + [string]$caseEResult.mismatch + ' reason=' + [string]$caseEResult.reason),
    ('caseF mismatch_expected=TRUE  actual=' + [string]$caseFResult.mismatch + ' reason=' + [string]$caseFResult.reason)
)
Set-Content -LiteralPath (Join-Path $PF '17_ledger_mismatch_detection.txt') -Value ($mismatchEvidence -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '98_gate_phase47_7.txt') -Value $Gate -Encoding UTF8 -NoNewline

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
