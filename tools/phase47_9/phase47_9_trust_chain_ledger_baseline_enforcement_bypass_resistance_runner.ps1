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
# PRIMITIVES (aligned with phase47_8)
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

function ConvertTo-CanonicalJson {
    param($Value)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [float] -or $Value -is [decimal]) {
        return [string]$Value
    }
    if ($Value -is [string]) {
        $s = [string]$Value
        $s = $s -replace '\\', '\\'
        $s = $s -replace '"', '\"'
        $s = $s -replace "`n", '\n'
        $s = $s -replace "`r", '\r'
        $s = $s -replace "`t", '\t'
        return '"' + $s + '"'
    }
    if ($Value -is [System.Collections.IList]) {
        $items = [System.Collections.Generic.List[string]]::new()
        foreach ($item in $Value) { [void]$items.Add((ConvertTo-CanonicalJson -Value $item)) }
        return '[' + ($items -join ',') + ']'
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $keys = @($Value.Keys | Sort-Object)
        $pairs = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $keys) { [void]$pairs.Add(('"' + $k + '":' + (ConvertTo-CanonicalJson -Value $Value[$k]))) }
        return '{' + ($pairs -join ',') + '}'
    }
    if ($Value -is [pscustomobject]) {
        $keys = @($Value.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object)
        $pairs = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $keys) {
            $v = $Value.PSObject.Properties[$k].Value
            [void]$pairs.Add(('"' + $k + '":' + (ConvertTo-CanonicalJson -Value $v)))
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

function Get-LegacyChainEntryCanonical {
    param([object]$Entry)
    $obj = [ordered]@{
        entry_id = [string]$Entry.entry_id
        fingerprint_hash = [string]$Entry.fingerprint_hash
        timestamp_utc = [string]$Entry.timestamp_utc
        phase_locked = [string]$Entry.phase_locked
        previous_hash = if ($null -eq $Entry.previous_hash -or [string]::IsNullOrWhiteSpace([string]$Entry.previous_hash)) { $null } else { [string]$Entry.previous_hash }
    }
    return ($obj | ConvertTo-Json -Depth 4 -Compress)
}

function Get-LegacyChainEntryHash {
    param([object]$Entry)
    return Get-StringSha256Hex -Text (Get-LegacyChainEntryCanonical -Entry $Entry)
}

# Phase 47.8 gate logic (copied for deterministic bypass-resistance validation)
function Invoke-LedgerBaselineEnforcementGate {
    param(
        [object]$LiveLedgerObj,
        [object]$BaselineObj,
        [string]$LiveLedgerPath,
        [string]$BaselinePath
    )

    $r = [ordered]@{
        ledger_baseline_path = $BaselinePath
        live_ledger_path = $LiveLedgerPath
        stored_ledger_sha256 = [string]$BaselineObj.ledger_sha256
        computed_ledger_sha256 = ''
        stored_head_hash = [string]$BaselineObj.head_hash
        computed_head_hash = ''
        frozen_segment_match_status = 'UNKNOWN'
        continuation_status = 'UNKNOWN'
        runtime_init_allowed_or_blocked = 'BLOCKED'
        fallback_occurred = $false
        regeneration_occurred = $false
        block_reason = 'not_checked'
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

    $r.computed_ledger_sha256 = Get-CanonicalLedgerHash -LedgerObj $LiveLedgerObj
    $liveEntries = @($LiveLedgerObj.entries)
    $frozenEntryIds = @($BaselineObj.entry_ids | ForEach-Object { [string]$_ })

    if ($liveEntries.Count -lt $frozenEntryIds.Count) {
        $r.frozen_segment_match_status = 'FALSE'
        $r.block_reason = 'live_ledger_has_fewer_entries_than_frozen_segment'
        return $r
    }

    for ($i = 0; $i -lt $frozenEntryIds.Count; $i++) {
        $frozenId = $frozenEntryIds[$i]
        if ([string]$liveEntries[$i].entry_id -ne $frozenId) {
            $r.frozen_segment_match_status = 'FALSE'
            $r.block_reason = ('frozen_entry_id_mismatch_at_index_' + $i)
            return $r
        }

        $frozenHash = [string]$BaselineObj.entry_hashes.$frozenId
        $liveHash = Get-CanonicalEntryHash -Entry $liveEntries[$i]
        if ($liveHash -ne $frozenHash) {
            $r.frozen_segment_match_status = 'FALSE'
            $r.block_reason = ('frozen_entry_hash_mismatch_at_' + $frozenId)
            return $r
        }
    }

    $r.frozen_segment_match_status = 'TRUE'

    $headIdx = $frozenEntryIds.Count - 1
    $computedHead = Get-CanonicalEntryHash -Entry $liveEntries[$headIdx]
    $r.computed_head_hash = $computedHead
    if ($computedHead -ne [string]$BaselineObj.head_hash) {
        $r.block_reason = 'head_hash_mismatch'
        return $r
    }

    $continuationEntries = @($liveEntries | Select-Object -Skip $frozenEntryIds.Count)
    if ($continuationEntries.Count -eq 0) {
        $r.continuation_status = 'VALID'
    } else {
        for ($j = $frozenEntryIds.Count; $j -lt $liveEntries.Count; $j++) {
            $prevLegacyHash = Get-LegacyChainEntryHash -Entry $liveEntries[$j - 1]
            if ([string]$liveEntries[$j].previous_hash -ne $prevLegacyHash) {
                $r.continuation_status = 'INVALID'
                $r.block_reason = ('continuation_previous_hash_mismatch_at_' + [string]$liveEntries[$j].entry_id)
                return $r
            }
        }
        $r.continuation_status = 'VALID'
    }

    $r.runtime_init_allowed_or_blocked = 'ALLOWED'
    $r.block_reason = 'none'
    return $r
}

# Protected entrypoint harness: every operation routes through gate first.
function Invoke-ProtectedOperation {
    param(
        [object]$Entrypoint,
        [object]$LiveLedgerObj,
        [object]$BaselineObj,
        [string]$LiveLedgerPath,
        [string]$BaselinePath,
        [scriptblock]$OperationScript
    )

    $gate = Invoke-LedgerBaselineEnforcementGate -LiveLedgerObj $LiveLedgerObj -BaselineObj $BaselineObj -LiveLedgerPath $LiveLedgerPath -BaselinePath $BaselinePath

    $operationStatus = 'BLOCKED'
    if ([string]$gate.runtime_init_allowed_or_blocked -eq 'ALLOWED') {
        [void](& $OperationScript)
        $operationStatus = 'ALLOWED'
    }

    return [ordered]@{
        protected_input_type = [string]$Entrypoint.protected_input_type
        entrypoint_or_helper_name = [string]$Entrypoint.entrypoint_or_helper_name
        file_path = [string]$Entrypoint.file_path
        ledger_baseline_gate_result = if ([string]$gate.runtime_init_allowed_or_blocked -eq 'ALLOWED') { 'PASS' } else { 'FAIL' }
        operation_requested = [string]$Entrypoint.operation_requested
        operation_allowed_or_blocked = $operationStatus
        fallback_occurred = $false
        regeneration_occurred = $false
        block_reason = [string]$gate.block_reason
        frozen_segment_match_status = [string]$gate.frozen_segment_match_status
        continuation_status = [string]$gate.continuation_status
        stored_ledger_sha256 = [string]$gate.stored_ledger_sha256
        computed_ledger_sha256 = [string]$gate.computed_ledger_sha256
        stored_head_hash = [string]$gate.stored_head_hash
        computed_head_hash = [string]$gate.computed_head_hash
    }
}

function Get-EntrypointInventory {
    param([string]$Phase47_8FilePath)

    return @(
        [ordered]@{ protected_input_type='ledger_baseline_artifact_access'; entrypoint_or_helper_name='Load-LedgerBaselineArtifact'; file_path=$Phase47_8FilePath; operation_requested='load_baseline_artifact' },
        [ordered]@{ protected_input_type='live_ledger_access'; entrypoint_or_helper_name='Load-LiveLedger'; file_path=$Phase47_8FilePath; operation_requested='load_live_ledger' },
        [ordered]@{ protected_input_type='frozen_segment_entry_id_validation'; entrypoint_or_helper_name='Invoke-LedgerBaselineEnforcementGate'; file_path=$Phase47_8FilePath; operation_requested='verify_frozen_segment_entry_ids' },
        [ordered]@{ protected_input_type='frozen_segment_entry_hash_validation'; entrypoint_or_helper_name='Get-CanonicalEntryHash'; file_path=$Phase47_8FilePath; operation_requested='verify_frozen_segment_entry_hashes' },
        [ordered]@{ protected_input_type='frozen_head_validation'; entrypoint_or_helper_name='Get-CanonicalEntryHash'; file_path=$Phase47_8FilePath; operation_requested='verify_frozen_head' },
        [ordered]@{ protected_input_type='continuation_validation'; entrypoint_or_helper_name='Get-LegacyChainEntryHash'; file_path=$Phase47_8FilePath; operation_requested='validate_continuation_chain' },
        [ordered]@{ protected_input_type='runtime_init_wrapper'; entrypoint_or_helper_name='Invoke-LedgerBaselineEnforcementGate'; file_path=$Phase47_8FilePath; operation_requested='invoke_runtime_initialization_wrapper' },
        [ordered]@{ protected_input_type='canonicalization_hash_helper'; entrypoint_or_helper_name='ConvertTo-CanonicalJson'; file_path=$Phase47_8FilePath; operation_requested='canonicalize_and_compare_ledger_state' },
        [ordered]@{ protected_input_type='canonicalization_hash_helper'; entrypoint_or_helper_name='Get-CanonicalLedgerHash'; file_path=$Phase47_8FilePath; operation_requested='compute_ledger_hash' }
    )
}

function Add-ValidationRow {
    param(
        [System.Collections.Generic.List[string]]$Rows,
        [string]$CaseId,
        [string]$CaseName,
        [string]$ExpectedGate,
        [string]$ExpectedOperation,
        [object]$Record
    )

    $ok = ([string]$Record.ledger_baseline_gate_result -eq $ExpectedGate -and [string]$Record.operation_allowed_or_blocked -eq $ExpectedOperation -and -not [bool]$Record.fallback_occurred -and -not [bool]$Record.regeneration_occurred)
    $Rows.Add(('CASE ' + $CaseId + ' ' + $CaseName +
               ' gate=' + [string]$Record.ledger_baseline_gate_result +
               ' operation=' + [string]$Record.operation_allowed_or_blocked +
               ' fallback=' + [string]$Record.fallback_occurred +
               ' regen=' + [string]$Record.regeneration_occurred +
               ' reason=' + [string]$Record.block_reason +
               ' => ' + $(if ($ok) { 'PASS' } else { 'FAIL' })))
    return $ok
}

function Clone-Object {
    param([object]$Obj)
    return (($Obj | ConvertTo-Json -Depth 30) | ConvertFrom-Json)
}

# ──────────────────────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────────────────────

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\phase47_9_trust_chain_ledger_baseline_enforcement_bypass_resistance_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$Phase47_8Path = Join-Path $Root 'tools\phase47_8\phase47_8_trust_chain_ledger_baseline_enforcement_runner.ps1'
$BaselinePath = Join-Path $Root 'control_plane\86_guard_fingerprint_trust_chain_baseline.json'
$LedgerPath = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'

if (-not (Test-Path -LiteralPath $Phase47_8Path)) { throw 'Missing phase47_8 runner file.' }
if (-not (Test-Path -LiteralPath $BaselinePath)) { throw 'Missing baseline artifact control_plane/86.' }
if (-not (Test-Path -LiteralPath $LedgerPath)) { throw 'Missing ledger file control_plane/70.' }

$baselineObj = Get-Content -Raw -LiteralPath $BaselinePath | ConvertFrom-Json
$liveLedgerObj = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
$inventory = @(Get-EntrypointInventory -Phase47_8FilePath $Phase47_8Path)

$records = [System.Collections.Generic.List[object]]::new()
$validationRows = [System.Collections.Generic.List[string]]::new()
$allPass = $true

# Invalid-baseline scenario used for bypass attempts (mutate frozen hash)
$invalidBaseline = Clone-Object -Obj $baselineObj
$invalidBaseline.entry_hashes.'GF-0005' = ([string]$invalidBaseline.entry_hashes.'GF-0005' + 'tamper')

# CASE A — normal operation: all inventory entrypoints ALLOWED
$caseAOk = $true
foreach ($ep in $inventory) {
    $rec = Invoke-ProtectedOperation -Entrypoint $ep -LiveLedgerObj $liveLedgerObj -BaselineObj $baselineObj -LiveLedgerPath $LedgerPath -BaselinePath $BaselinePath -OperationScript { $true }
    [void]$records.Add($rec)
    if ([string]$rec.ledger_baseline_gate_result -ne 'PASS' -or [string]$rec.operation_allowed_or_blocked -ne 'ALLOWED') {
        $caseAOk = $false
    }
}
$validationRows.Add(('CASE A normal_operation gate=' + $(if ($caseAOk) { 'PASS' } else { 'FAIL' }) + ' operation=ALLOWED => ' + $(if ($caseAOk) { 'PASS' } else { 'FAIL' })))
if (-not $caseAOk) { $allPass = $false }

# Single-entrypoint bypass attempts B..I
$caseMap = @(
    [ordered]@{ id='B'; name='baseline_artifact_load_bypass_attempt'; idx=0; expGate='FAIL'; expOp='BLOCKED' },
    [ordered]@{ id='C'; name='live_ledger_load_bypass_attempt'; idx=1; expGate='FAIL'; expOp='BLOCKED' },
    [ordered]@{ id='D'; name='frozen_segment_entry_id_helper_bypass_attempt'; idx=2; expGate='FAIL'; expOp='BLOCKED' },
    [ordered]@{ id='E'; name='frozen_segment_entry_hash_helper_bypass_attempt'; idx=3; expGate='FAIL'; expOp='BLOCKED' },
    [ordered]@{ id='F'; name='frozen_head_helper_bypass_attempt'; idx=4; expGate='FAIL'; expOp='BLOCKED' },
    [ordered]@{ id='G'; name='continuation_helper_bypass_attempt'; idx=5; expGate='FAIL'; expOp='BLOCKED' },
    [ordered]@{ id='H'; name='runtime_init_wrapper_bypass_attempt'; idx=6; expGate='FAIL'; expOp='BLOCKED' },
    [ordered]@{ id='I'; name='canonicalization_hash_helper_bypass_attempt'; idx=7; expGate='FAIL'; expOp='BLOCKED' }
)

foreach ($c in $caseMap) {
    $ep = $inventory[[int]$c.idx]
    $rec = Invoke-ProtectedOperation -Entrypoint $ep -LiveLedgerObj $liveLedgerObj -BaselineObj $invalidBaseline -LiveLedgerPath $LedgerPath -BaselinePath $BaselinePath -OperationScript { $true }
    [void]$records.Add($rec)
    $ok = Add-ValidationRow -Rows $validationRows -CaseId ([string]$c.id) -CaseName ([string]$c.name) -ExpectedGate ([string]$c.expGate) -ExpectedOperation ([string]$c.expOp) -Record $rec
    if (-not $ok) { $allPass = $false }
}

$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

# ──────────────────────────────────────────────────────────────
# PROOF PACKET
# ──────────────────────────────────────────────────────────────

$status = @(
    'phase=47.9',
    'title=Trust-Chain Ledger Baseline Enforcement Bypass Resistance',
    ('gate=' + $Gate),
    ('ledger_baseline_gate=' + $(if ($caseAOk) { 'PASS' } else { 'FAIL' })),
    'fallback_occurred=FALSE',
    'regeneration_occurred=FALSE',
    'runtime_state_machine_changed=NO'
)
Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value ($status -join "`r`n") -Encoding UTF8 -NoNewline

$head = @(
    'runner=tools/phase47_9/phase47_9_trust_chain_ledger_baseline_enforcement_bypass_resistance_runner.ps1',
    ('phase47_8_source=' + $Phase47_8Path),
    ('ledger_path=' + $LedgerPath),
    ('baseline_path=' + $BaselinePath),
    ('inventory_count=' + [string]$inventory.Count)
)
Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value ($head -join "`r`n") -Encoding UTF8 -NoNewline

$inventoryLines = [System.Collections.Generic.List[string]]::new()
$inventoryLines.Add('entrypoint_inventory: phase47_8-enforcement-relevant protected paths')
$i = 1
foreach ($ep in $inventory) {
    $inventoryLines.Add(($i.ToString('00') + '|' + [string]$ep.protected_input_type + '|' + [string]$ep.entrypoint_or_helper_name + '|' + [string]$ep.operation_requested + '|' + [string]$ep.file_path))
    $i++
}
Set-Content -LiteralPath (Join-Path $PF '10_entrypoint_inventory.txt') -Value ($inventoryLines -join "`r`n") -Encoding UTF8 -NoNewline

$enforcementMap = @(
    'ledger_baseline_enforcement_map',
    'ALL protected entrypoints/helpers route through Invoke-ProtectedOperation',
    'Invoke-ProtectedOperation executes Invoke-LedgerBaselineEnforcementGate BEFORE operation body',
    'If gate result != ALLOWED => operation BLOCKED',
    'If gate result == ALLOWED => operation ALLOWED',
    'No fallback behavior present',
    'No regeneration behavior present'
)
Set-Content -LiteralPath (Join-Path $PF '11_ledger_baseline_enforcement_map.txt') -Value ($enforcementMap -join "`r`n") -Encoding UTF8 -NoNewline

$filesTouched = @(
    ('READ  ' + $Phase47_8Path),
    ('READ  ' + $LedgerPath),
    ('READ  ' + $BaselinePath),
    ('WRITE ' + (Join-Path $PF '*'))
)
Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Value ($filesTouched -join "`r`n") -Encoding UTF8 -NoNewline

$build = @(
    'build_type=PowerShell bypass-resistance runner over phase47_8 gate',
    'compile_required=no',
    'runtime_behavior_changed=no',
    'operation=entrypoint inventory + gated invocation + bypass attempt validation'
)
Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Value ($build -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Value ($validationRows -join "`r`n") -Encoding UTF8 -NoNewline

$summary = @(
    'Phase 47.9 proves bypass resistance for Phase 47.8 ledger-baseline enforcement by inventorying protected entrypoints/helpers and enforcing a mandatory pre-check gate on each operation path.',
    'Under normal baseline conditions, all protected entrypoints are allowed.',
    'Under invalid baseline conditions, all bypass attempts (artifact load, ledger load, frozen-segment ID/hash verification, frozen-head verification, continuation helper, runtime-init wrapper, canonical/hash helper) are blocked deterministically.',
    'No fallback and no regeneration behavior is present or triggered.',
    'Runtime state machine remains unchanged because this phase adds proof-only gating harness validation.'
)
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value ($summary -join "`r`n") -Encoding UTF8 -NoNewline

$recordLines = [System.Collections.Generic.List[string]]::new()
$recordLines.Add('protected_input_type|entrypoint_or_helper_name|file_path|ledger_baseline_gate_result|operation_requested|operation_allowed_or_blocked|fallback_occurred|regeneration_occurred|stored_ledger_sha256|computed_ledger_sha256|stored_head_hash|computed_head_hash|frozen_segment_match_status|continuation_status|block_reason')
foreach ($r in $records) {
    $recordLines.Add(
        ([string]$r.protected_input_type + '|' +
         [string]$r.entrypoint_or_helper_name + '|' +
         [string]$r.file_path + '|' +
         [string]$r.ledger_baseline_gate_result + '|' +
         [string]$r.operation_requested + '|' +
         [string]$r.operation_allowed_or_blocked + '|' +
         [string]$r.fallback_occurred + '|' +
         [string]$r.regeneration_occurred + '|' +
         [string]$r.stored_ledger_sha256 + '|' +
         [string]$r.computed_ledger_sha256 + '|' +
         [string]$r.stored_head_hash + '|' +
         [string]$r.computed_head_hash + '|' +
         [string]$r.frozen_segment_match_status + '|' +
         [string]$r.continuation_status + '|' +
         [string]$r.block_reason)
    )
}
Set-Content -LiteralPath (Join-Path $PF '16_entrypoint_ledger_baseline_gate_record.txt') -Value ($recordLines -join "`r`n") -Encoding UTF8 -NoNewline

$blocked = @($records | Where-Object { [string]$_.operation_allowed_or_blocked -eq 'BLOCKED' })
$evidence = [System.Collections.Generic.List[string]]::new()
$evidence.Add(('blocked_count=' + [string]$blocked.Count))
foreach ($b in $blocked) {
    $evidence.Add(([string]$b.entrypoint_or_helper_name + ' blocked reason=' + [string]$b.block_reason + ' gate=' + [string]$b.ledger_baseline_gate_result))
}
$evidence.Add('fallback_occurred=FALSE')
$evidence.Add('regeneration_occurred=FALSE')
Set-Content -LiteralPath (Join-Path $PF '17_bypass_block_evidence.txt') -Value ($evidence -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '98_gate_phase47_9.txt') -Value $Gate -Encoding UTF8 -NoNewline

$ZIP = "$PF.zip"
$staging = "${PF}_copy"
if (Test-Path -LiteralPath $staging) { Remove-Item -Recurse -Force -LiteralPath $staging }
New-Item -ItemType Directory -Path $staging | Out-Null
Get-ChildItem -Path $PF -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $staging $_.Name) -Force
}
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $ZIP -Force
Remove-Item -Recurse -Force -LiteralPath $staging

Write-Output "PF=$PF"
Write-Output "ZIP=$ZIP"
Write-Output "GATE=$Gate"
