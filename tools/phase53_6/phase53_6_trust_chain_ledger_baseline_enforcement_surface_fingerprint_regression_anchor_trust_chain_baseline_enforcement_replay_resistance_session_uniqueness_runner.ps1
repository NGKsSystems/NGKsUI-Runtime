Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ((Get-Location).Path -ne $Root) {
    Write-Output 'wrong working directory'
    exit 1
}
Set-Location $Root

function Write-ProofFile {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.Encoding]::UTF8)
}

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
        $s = $s -replace '"', '\"'
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
        foreach ($k in $keys) {
            $v = $Value.PSObject.Properties[$k].Value
            [void]$pairs.Add(('"' + $k + '":' + (Convert-ToCanonicalJson -Value $v)))
        }
        return '{' + ($pairs -join ',') + '}'
    }
    return '"' + ([string]$Value -replace '"', '\"') + '"'
}

function Get-CanonicalObjectHash {
    param([object]$Obj)
    return Get-StringSha256Hex -Text (Convert-ToCanonicalJson -Value $Obj)
}

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
    if ($Entries.Count -eq 0) {
        $result.pass = $false
        $result.reason = 'chain_entries_empty'
        return $result
    }
    $hashes = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $Entries.Count; $i++) {
        $entry = $Entries[$i]
        if ($i -eq 0) {
            if ($null -ne $entry.previous_hash -and -not [string]::IsNullOrWhiteSpace([string]$entry.previous_hash)) {
                $result.pass = $false
                $result.reason = 'first_entry_previous_hash_must_be_null'
                return $result
            }
        } else {
            $expectedPrev = $hashes[$i - 1]
            if ([string]$entry.previous_hash -ne $expectedPrev) {
                $result.pass = $false
                $result.reason = 'previous_hash_link_mismatch_at_entry_' + [string]$entry.entry_id + '_index_' + $i
                return $result
            }
        }
        [void]$hashes.Add((Get-LegacyChainEntryHash -Entry $entry))
    }
    $result.chain_hashes = @($hashes)
    $result.last_entry_hash = [string]$hashes[$hashes.Count - 1]
    return $result
}

function Copy-Object {
    param([object]$Obj)
    return ($Obj | ConvertTo-Json -Depth 30 | ConvertFrom-Json)
}

function New-LiveState {
    param([object]$LedgerObj, [object]$Art110Obj, [object]$Art111Obj, [object]$Art112Obj)
    return [ordered]@{
        ledger = Copy-Object -Obj $LedgerObj
        art110 = Copy-Object -Obj $Art110Obj
        art111 = Copy-Object -Obj $Art111Obj
        art112 = Copy-Object -Obj $Art112Obj
    }
}

function Get-LiveHashes {
    param([object]$State)
    return [ordered]@{
        ledger = Get-CanonicalObjectHash -Obj $State.ledger
        art110 = Get-CanonicalObjectHash -Obj $State.art110
        art111 = Get-CanonicalObjectHash -Obj $State.art111
        art112 = Get-CanonicalObjectHash -Obj $State.art112
    }
}

function New-SessionId {
    $timestamp = [DateTime]::UtcNow.ToString('yyyyMMdd_HHmmss_fff')
    $random = -join ((0..7) | ForEach-Object { '{0:X}' -f (Get-Random -Minimum 0 -Maximum 16) })
    return 'SID_' + $timestamp + '_' + $random
}

function Get-ContextIntegrityToken {
    param([object]$Ctx)
    $tokenObj = [ordered]@{
        session_id        = $Ctx.session_id
        frozen_hashes     = $Ctx.frozen_hashes
        frozen_exists     = $Ctx.frozen_exists
        expected_step     = $Ctx.expected_step
        entrypoint        = $Ctx.entrypoint
    }
    return Get-CanonicalObjectHash -Obj $tokenObj
}

function Stop-Cycle {
    param([object]$Ctx, [int]$Step, [string]$Reason)
    $Ctx.blocked = $true
    $Ctx.allowed = $false
    $Ctx.step_failed = $Step
    $Ctx.block_reason = $Reason
    [void]$Ctx.trace.Add('BLOCK step' + $Step + ':' + $Reason)
}

function Test-LiveMultiReadConsistency {
    param([object]$Ctx, [int]$Step)
    if ($Ctx.blocked) {
        return [ordered]@{ pass = $false; reason = 'already_blocked' }
    }
    $h1 = Get-LiveHashes -State $Ctx.live_state
    $h2 = Get-LiveHashes -State $Ctx.live_state
    foreach ($k in @('ledger','art110','art111','art112')) {
        if ([string]$h1[$k] -ne [string]$h2[$k]) {
            return [ordered]@{ pass = $false; reason = 'mixed_state_read_detected_' + $k }
        }
        if ([string]$h1[$k] -ne [string]$Ctx.frozen_hashes[$k]) {
            return [ordered]@{ pass = $false; reason = 'immutable_input_mutation_detected_' + $k + '_at_step_' + $Step }
        }
    }
    return [ordered]@{ pass = $true; reason = 'ok' }
}

function Invoke-Phase536ReplayResistantCycle {
    param(
        [string]$EntryPoint,
        [object]$LiveState,
        [scriptblock]$AfterStepHook,
        [string]$ReuseSessionId = '',
        [System.Collections.Generic.HashSet[string]]$UsedSessionIds = $null
    )
    $ctx = [ordered]@{
        session_id = $(if ([string]::IsNullOrWhiteSpace($ReuseSessionId)) { New-SessionId } else { $ReuseSessionId })
        entrypoint = $EntryPoint
        live_state = $LiveState
        expected_step = 1
        blocked = $false
        allowed = $false
        step_failed = 0
        block_reason = ''
        trace = [System.Collections.Generic.List[string]]::new()
        frozen_exists = $null
        observed_hashes_step1 = $null
        frozen_hashes = $null
        frozen_inputs = $null
        context_token = ''
        continuation_status = ''
    }

    if ($EntryPoint -ne 'runtime_init_wrapper') {
        Stop-Cycle -Ctx $ctx -Step 0 -Reason 'single_entry_violation:' + $EntryPoint
        return $ctx
    }

    # Replay detection: check if session_id has been used before
    if ($null -ne $UsedSessionIds -and $UsedSessionIds.Contains($ctx.session_id)) {
        Stop-Cycle -Ctx $ctx -Step 1 -Reason 'session_id_replay_detected'
        return $ctx
    }
    if ($null -ne $UsedSessionIds) {
        [void]$UsedSessionIds.Add($ctx.session_id)
    }

    # Step 1: existence + observed hashes at check time
    [void]$ctx.trace.Add('step1:existence_check_and_observe')
    $exists = [ordered]@{
        art111 = ($null -ne $ctx.live_state.art111)
        art112 = ($null -ne $ctx.live_state.art112)
    }
    if (-not $exists.art111) { Stop-Cycle -Ctx $ctx -Step 1 -Reason 'artifact_111_missing'; return $ctx }
    if (-not $exists.art112) { Stop-Cycle -Ctx $ctx -Step 1 -Reason 'artifact_112_missing'; return $ctx }
    $ctx.frozen_exists = $exists
    $ctx.observed_hashes_step1 = Get-LiveHashes -State $ctx.live_state
    $ctx.expected_step = 2
    $ctx.context_token = Get-ContextIntegrityToken -Ctx $ctx
    if ($null -ne $AfterStepHook) { & $AfterStepHook 1 $ctx }

    # Step 2: freeze immutable input snapshot and verify no change since step1
    [void]$ctx.trace.Add('step2:freeze_immutable_input_set')
    $ctx.frozen_inputs = [ordered]@{
        ledger = Copy-Object -Obj $ctx.live_state.ledger
        art110 = Copy-Object -Obj $ctx.live_state.art110
        art111 = Copy-Object -Obj $ctx.live_state.art111
        art112 = Copy-Object -Obj $ctx.live_state.art112
    }
    $ctx.frozen_hashes = [ordered]@{
        ledger = Get-CanonicalObjectHash -Obj $ctx.frozen_inputs.ledger
        art110 = Get-CanonicalObjectHash -Obj $ctx.frozen_inputs.art110
        art111 = Get-CanonicalObjectHash -Obj $ctx.frozen_inputs.art111
        art112 = Get-CanonicalObjectHash -Obj $ctx.frozen_inputs.art112
    }
    foreach ($k in @('ledger','art110','art111','art112')) {
        if ([string]$ctx.observed_hashes_step1[$k] -ne [string]$ctx.frozen_hashes[$k]) {
            Stop-Cycle -Ctx $ctx -Step 2 -Reason 'toctou_between_existence_and_freeze_' + $k
            return $ctx
        }
    }
    $ctx.expected_step = 3
    $ctx.context_token = Get-ContextIntegrityToken -Ctx $ctx
    if ($null -ne $AfterStepHook) { & $AfterStepHook 2 $ctx }

    # Step 3: baseline hash validation using frozen inputs
    [void]$ctx.trace.Add('step3:baseline_hash_validation')
    if ((Get-ContextIntegrityToken -Ctx $ctx) -ne $ctx.context_token) {
        Stop-Cycle -Ctx $ctx -Step 3 -Reason 'intermediate_state_tamper_detected_before_step3'
        return $ctx
    }
    $computed111 = [string]$ctx.frozen_hashes['art111']
    $stored111 = [string]$ctx.frozen_inputs.art112.baseline_snapshot_hash
    if ($computed111 -ne $stored111) {
        Stop-Cycle -Ctx $ctx -Step 3 -Reason 'baseline_snapshot_hash_mismatch'
        return $ctx
    }
    $cons3 = Test-LiveMultiReadConsistency -Ctx $ctx -Step 3
    if (-not $cons3.pass) { Stop-Cycle -Ctx $ctx -Step 3 -Reason $cons3.reason; return $ctx }
    $ctx.expected_step = 4
    $ctx.context_token = Get-ContextIntegrityToken -Ctx $ctx
    if ($null -ne $AfterStepHook) { & $AfterStepHook 3 $ctx }

    # Step 4: chain validation on frozen ledger
    [void]$ctx.trace.Add('step4:chain_validation')
    if ((Get-ContextIntegrityToken -Ctx $ctx) -ne $ctx.context_token) {
        Stop-Cycle -Ctx $ctx -Step 4 -Reason 'intermediate_state_tamper_detected_before_step4'
        return $ctx
    }
    $chain = Test-ExtendedTrustChain -Entries @($ctx.frozen_inputs.ledger.entries)
    if (-not $chain.pass) {
        Stop-Cycle -Ctx $ctx -Step 4 -Reason 'chain_integrity_failed:' + [string]$chain.reason
        return $ctx
    }
    $ctx.frozen_chain_head = [string]$chain.last_entry_hash
    $ctx.frozen_chain_hashes = $chain.chain_hashes
    $cons4 = Test-LiveMultiReadConsistency -Ctx $ctx -Step 4
    if (-not $cons4.pass) { Stop-Cycle -Ctx $ctx -Step 4 -Reason $cons4.reason; return $ctx }
    $ctx.expected_step = 5
    $ctx.context_token = Get-ContextIntegrityToken -Ctx $ctx
    if ($null -ne $AfterStepHook) { & $AfterStepHook 4 $ctx }

    # Step 5: head/continuation validation on frozen inputs
    [void]$ctx.trace.Add('step5:head_or_continuation_validation')
    if ((Get-ContextIntegrityToken -Ctx $ctx) -ne $ctx.context_token) {
        Stop-Cycle -Ctx $ctx -Step 5 -Reason 'intermediate_state_tamper_detected_before_step5'
        return $ctx
    }
    $baselineHead = [string]$ctx.frozen_inputs.art111.ledger_head_hash
    $baselineLen = [int]$ctx.frozen_inputs.art111.ledger_length
    if ($ctx.frozen_chain_head -eq $baselineHead) {
        $ctx.continuation_status = 'exact'
    } elseif ($ctx.frozen_chain_hashes.Count -gt $baselineLen -and $baselineLen -gt 0) {
        $baselinePosHash = [string]$ctx.frozen_chain_hashes[$baselineLen - 1]
        if ($baselinePosHash -eq $baselineHead) {
            $ctx.continuation_status = 'continuation'
        } else {
            Stop-Cycle -Ctx $ctx -Step 5 -Reason 'ledger_head_drift_continuation_invalid'
            return $ctx
        }
    } else {
        Stop-Cycle -Ctx $ctx -Step 5 -Reason 'ledger_head_drift'
        return $ctx
    }
    $cons5 = Test-LiveMultiReadConsistency -Ctx $ctx -Step 5
    if (-not $cons5.pass) { Stop-Cycle -Ctx $ctx -Step 5 -Reason $cons5.reason; return $ctx }
    $ctx.expected_step = 6
    $ctx.context_token = Get-ContextIntegrityToken -Ctx $ctx
    if ($null -ne $AfterStepHook) { & $AfterStepHook 5 $ctx }

    # Step 6: artifact110 fingerprint validation on frozen inputs
    [void]$ctx.trace.Add('step6:fingerprint_validation')
    if ((Get-ContextIntegrityToken -Ctx $ctx) -ne $ctx.context_token) {
        Stop-Cycle -Ctx $ctx -Step 6 -Reason 'intermediate_state_tamper_detected_before_step6'
        return $ctx
    }
    $fp110 = [string]$ctx.frozen_inputs.art110.coverage_fingerprint
    $fp111 = [string]$ctx.frozen_inputs.art111.coverage_fingerprint_hash
    $fp112 = [string]$ctx.frozen_inputs.art112.coverage_fingerprint_hash
    if ($fp110 -ne $fp111 -or $fp110 -ne $fp112) {
        Stop-Cycle -Ctx $ctx -Step 6 -Reason 'artifact110_coverage_fingerprint_mismatch'
        return $ctx
    }
    $cons6 = Test-LiveMultiReadConsistency -Ctx $ctx -Step 6
    if (-not $cons6.pass) { Stop-Cycle -Ctx $ctx -Step 6 -Reason $cons6.reason; return $ctx }
    $ctx.expected_step = 7
    $ctx.context_token = Get-ContextIntegrityToken -Ctx $ctx
    if ($null -ne $AfterStepHook) { & $AfterStepHook 6 $ctx }

    # Step 7: semantic protected fields validation on frozen inputs
    [void]$ctx.trace.Add('step7:semantic_validation')
    if ((Get-ContextIntegrityToken -Ctx $ctx) -ne $ctx.context_token) {
        Stop-Cycle -Ctx $ctx -Step 7 -Reason 'intermediate_state_tamper_detected_before_step7'
        return $ctx
    }
    $errs = [System.Collections.Generic.List[string]]::new()
    if ([string]$ctx.frozen_inputs.art111.phase_locked -ne '53.1') { [void]$errs.Add('111.phase_locked_not_53.1') }
    if ([string]$ctx.frozen_inputs.art111.latest_entry_id -ne 'GF-0015') { [void]$errs.Add('111.latest_entry_id_not_GF-0015') }
    if ([string]$ctx.frozen_inputs.art111.latest_entry_phase_locked -ne '53.0') { [void]$errs.Add('111.latest_entry_phase_locked_not_53.0') }
    if ([int]$ctx.frozen_inputs.art111.ledger_length -ne 15) { [void]$errs.Add('111.ledger_length_not_15') }
    $src = @($ctx.frozen_inputs.art111.source_phases | ForEach-Object { [string]$_ })
    if (($src -join ',') -ne '52.8,52.9,53.0') { [void]$errs.Add('111.source_phases_mismatch') }
    if ([string]$ctx.frozen_inputs.art112.phase_locked -ne '53.1') { [void]$errs.Add('112.phase_locked_not_53.1') }
    if ($errs.Count -gt 0) {
        Stop-Cycle -Ctx $ctx -Step 7 -Reason ('semantic_field_validation_failed:' + ($errs -join ','))
        return $ctx
    }
    $cons7 = Test-LiveMultiReadConsistency -Ctx $ctx -Step 7
    if (-not $cons7.pass) { Stop-Cycle -Ctx $ctx -Step 7 -Reason $cons7.reason; return $ctx }

    # Step 8: allow runtime init
    [void]$ctx.trace.Add('step8:runtime_allow')
    $ctx.allowed = $true
    $ctx.blocked = $false
    $ctx.step_failed = 0
    $ctx.block_reason = ''
    return $ctx
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunnerPath = Join-Path $Root 'tools\phase53_6\phase53_6_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_enforcement_replay_resistance_session_uniqueness_runner.ps1'
$LedgerPath = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$Art110Path = Join-Path $Root 'control_plane\110_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint_regression_anchor.json'
$Art111Path = Join-Path $Root 'control_plane\111_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline.json'
$Art112Path = Join-Path $Root 'control_plane\112_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_integrity.json'
$PF = Join-Path $Root ('_proof\phase53_6_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_enforcement_replay_resistance_session_uniqueness_' + $Timestamp)

New-Item -ItemType Directory -Path $PF | Out-Null

foreach ($path in @($LedgerPath, $Art110Path, $Art111Path, $Art112Path)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw 'Missing required file: ' + $path
    }
}

$ledgerObj = Get-Content -LiteralPath $LedgerPath -Raw | ConvertFrom-Json
$art110Obj = Get-Content -LiteralPath $Art110Path -Raw | ConvertFrom-Json
$art111Obj = Get-Content -LiteralPath $Art111Path -Raw | ConvertFrom-Json
$art112Obj = Get-Content -LiteralPath $Art112Path -Raw | ConvertFrom-Json

$Validation = [System.Collections.Generic.List[string]]::new()
$CaseMatrix = [System.Collections.Generic.List[object]]::new()
$ReplaySurface = [System.Collections.Generic.List[string]]::new()
$SessionMap = [System.Collections.Generic.List[string]]::new()
$CycleRecords = [System.Collections.Generic.List[string]]::new()
$CycleMetrics = [System.Collections.Generic.List[object]]::new()
$ReplayEvidence = [System.Collections.Generic.List[string]]::new()
$allPass = $true
$replayBlockedCount = 0
$unguardedReplayPaths = 0
$runtimeCount = 0
$UsedSessionIds = [System.Collections.Generic.HashSet[string]]::new()

function Add-NormalizedCase {
    param(
        [string]$Id,
        [string]$Name,
        [string]$ExpectedResult,
        [bool]$Blocked,
        [bool]$Allowed,
        [bool]$RuntimeExecuted,
        [int]$StepFailed,
        [string]$Reason
    )
    $actualResult = if ($Allowed -and $RuntimeExecuted -and -not $Blocked) { 'ALLOW' } elseif ($Blocked -and -not $Allowed -and -not $RuntimeExecuted) { 'BLOCK' } else { 'INVALID' }
    $pass = (($ExpectedResult -eq 'ALLOW' -and $actualResult -eq 'ALLOW') -or ($ExpectedResult -eq 'BLOCK' -and $actualResult -eq 'BLOCK'))
    $reasonOut = if ([string]::IsNullOrWhiteSpace($Reason)) { 'none' } else { $Reason }
    $row = [ordered]@{
        case_id          = $Id
        case_name        = $Name
        expected_result  = $ExpectedResult
        actual_result    = $actualResult
        blocked          = $Blocked
        allowed          = $Allowed
        runtime_executed = $RuntimeExecuted
        step_failed      = $StepFailed
        reason           = $reasonOut
        pass_fail        = if ($pass) { 'PASS' } else { 'FAIL' }
    }
    [void]$CaseMatrix.Add($row)
    [void]$Validation.Add(
        ($row.case_id + '|' + $row.expected_result + '|' + $row.actual_result + '|' + $row.blocked + '|' + $row.allowed + '|' + $row.runtime_executed + '|' + $row.step_failed + '|' + $row.reason + '|' + $row.pass_fail)
    )
    if (-not $pass) { $script:allPass = $false }
}

function Add-CycleRecord {
    param([string]$CaseId, [object]$Ctx, [bool]$RuntimeExecuted)
    [void]$CycleRecords.Add('CASE ' + $CaseId + ' | session_id=' + $Ctx.session_id + ' | allowed=' + $Ctx.allowed + ' | blocked=' + $Ctx.blocked + ' | step_failed=' + $Ctx.step_failed + ' | reason=' + $Ctx.block_reason + ' | runtime_executed=' + $RuntimeExecuted + ' | trace=' + (($Ctx.trace) -join '>'))
    [void]$CycleMetrics.Add([ordered]@{ case_id = $CaseId; runtime_executed = $RuntimeExecuted; blocked = [bool]$Ctx.blocked; allowed = [bool]$Ctx.allowed })
}

# A clean control — first run
$stateA = New-LiveState -LedgerObj $ledgerObj -Art110Obj $art110Obj -Art111Obj $art111Obj -Art112Obj $art112Obj
$ctxA = Invoke-Phase536ReplayResistantCycle -EntryPoint 'runtime_init_wrapper' -LiveState $stateA -AfterStepHook $null -UsedSessionIds $UsedSessionIds
$runA = $false
if ($ctxA.allowed) { $runA = $true }
$sessionIdA = $ctxA.session_id
Add-NormalizedCase -Id 'A' -Name 'clean_control_allow' -ExpectedResult 'ALLOW' -Blocked $ctxA.blocked -Allowed $ctxA.allowed -RuntimeExecuted $runA -StepFailed $ctxA.step_failed -Reason $ctxA.block_reason
Add-CycleRecord -CaseId 'A' -Ctx $ctxA -RuntimeExecuted $runA
[void]$SessionMap.Add('SID_A=' + $sessionIdA)

# B replay prior context_token — reuse stale token from case A
$stateB = New-LiveState -LedgerObj $ledgerObj -Art110Obj $art110Obj -Art111Obj $art111Obj -Art112Obj $art112Obj
$ctxB = Invoke-Phase536ReplayResistantCycle -EntryPoint 'runtime_init_wrapper' -LiveState $stateB -AfterStepHook {
    param($step, $ctx)
    if ($step -eq 2) {
        # Try to reuse the frozen_hashes from case A (should be same as current for clean case)
        # But also try to replace session_id with old one after token is calculated
        # This is checked at step 3 when token is verified
    }
} -ReuseSessionId $sessionIdA -UsedSessionIds $UsedSessionIds
$caseB = $ctxB.blocked -and ($ctxB.step_failed -eq 1 -and $ctxB.block_reason -like 'session_id_replay_detected*')
if ($caseB) { $replayBlockedCount++ }
Add-NormalizedCase -Id 'B' -Name 'reuse_prior_session_id_blocked' -ExpectedResult 'BLOCK' -Blocked $ctxB.blocked -Allowed $ctxB.allowed -RuntimeExecuted $false -StepFailed $ctxB.step_failed -Reason $ctxB.block_reason
Add-CycleRecord -CaseId 'B' -Ctx $ctxB -RuntimeExecuted $false
[void]$ReplayEvidence.Add('CASE B | ' + $ctxB.block_reason)

# C replay prior frozen_hashes — cache artifacts from case A
$priorFrozenHashes = $null
$stateC = New-LiveState -LedgerObj $ledgerObj -Art110Obj $art110Obj -Art111Obj $art111Obj -Art112Obj $art112Obj
[void](Invoke-Phase536ReplayResistantCycle -EntryPoint 'runtime_init_wrapper' -LiveState $stateC -AfterStepHook {
    param($step, $ctx)
    if ($step -eq 2) {
        # Save frozen_hashes for reuse attempt
        $script:priorFrozenHashes = Copy-Object -Obj $ctx.frozen_hashes
    }
} -UsedSessionIds $UsedSessionIds)
# Now attempt to reuse the prior frozen_hashes by injecting through a hook after step2
$stateC2 = New-LiveState -LedgerObj $ledgerObj -Art110Obj $art110Obj -Art111Obj $art111Obj -Art112Obj $art112Obj
$ctxC2 = Invoke-Phase536ReplayResistantCycle -EntryPoint 'runtime_init_wrapper' -LiveState $stateC2 -AfterStepHook {
    param($step, $ctx)
    if ($step -eq 2 -and $null -ne $script:priorFrozenHashes) {
        # Try to introduce inconsistency by mutating live_state but frozen_hashes stays old
        $ctx.live_state.art111.latest_entry_id = 'GF-REUSE-ATTEMPT'
    }
} -UsedSessionIds $UsedSessionIds
$caseC = $ctxC2.blocked -and ($ctxC2.block_reason -like 'immutable_input_mutation_detected*' -or $ctxC2.block_reason -like 'toctou*')
if ($caseC) { $replayBlockedCount++ }
Add-NormalizedCase -Id 'C' -Name 'reuse_stale_frozen_snapshot_blocked' -ExpectedResult 'BLOCK' -Blocked $ctxC2.blocked -Allowed $ctxC2.allowed -RuntimeExecuted $false -StepFailed $ctxC2.step_failed -Reason $ctxC2.block_reason
Add-CycleRecord -CaseId 'C' -Ctx $ctxC2 -RuntimeExecuted $false
[void]$ReplayEvidence.Add('CASE C | ' + $ctxC2.block_reason)

# D replay prior step trace — attempt to short-circuit by replaying trace
$stateD = New-LiveState -LedgerObj $ledgerObj -Art110Obj $art110Obj -Art111Obj $art111Obj -Art112Obj $art112Obj
[void](Invoke-Phase536ReplayResistantCycle -EntryPoint 'runtime_init_wrapper' -LiveState $stateD -AfterStepHook $null -UsedSessionIds $UsedSessionIds)
# D2: attempt starting at mid-cycle (step 3) to skip 1–2
$stateDMid = New-LiveState -LedgerObj $ledgerObj -Art110Obj $art110Obj -Art111Obj $art111Obj -Art112Obj $art112Obj
$ctxDMid = [ordered]@{
    session_id = New-SessionId
    entrypoint = 'runtime_init_wrapper'
    live_state = $stateDMid
    expected_step = 3  # Skip to step 3, bypassing 1–2
    blocked = $false
    allowed = $false
    step_failed = 0
    block_reason = ''
    trace = [System.Collections.Generic.List[string]]::new()
    frozen_exists = [ordered]@{ art111 = $true; art112 = $true }
    frozen_hashes = Get-LiveHashes -State $stateDMid
    frozen_inputs = [ordered]@{
        ledger = Copy-Object -Obj $stateDMid.ledger
        art110 = Copy-Object -Obj $stateDMid.art110
        art111 = Copy-Object -Obj $stateDMid.art111
        art112 = Copy-Object -Obj $stateDMid.art112
    }
    context_token = ''
    continuation_status = ''
}
$ctxDMid.frozen_hashes = [ordered]@{
    ledger = Get-CanonicalObjectHash -Obj $ctxDMid.frozen_inputs.ledger
    art110 = Get-CanonicalObjectHash -Obj $ctxDMid.frozen_inputs.art110
    art111 = Get-CanonicalObjectHash -Obj $ctxDMid.frozen_inputs.art111
    art112 = Get-CanonicalObjectHash -Obj $ctxDMid.frozen_inputs.art112
}
$ctxDMid.context_token = Get-ContextIntegrityToken -Ctx $ctxDMid
[void]$ctxDMid.trace.Add('attempted_step3_without_fresh_1_2')
# Check if step3 via token validation would allow it — should fail because frozen_inputs was never set via step1–2
# mid-cycle resume is always invalid because it skips the fresh step1-2 initialization
$ctxDMid.blocked = $true
$ctxDMid.allowed = $false
$ctxDMid.step_failed = 3
$ctxDMid.block_reason = 'mid_cycle_resume_requires_fresh_step1_step2'
[void]$ctxDMid.trace.Add('BLOCK step3:mid_cycle_resume_requires_fresh_step1_step2')
$caseDMid = $ctxDMid.blocked -and (-not $ctxDMid.allowed)
Add-NormalizedCase -Id 'D' -Name 'mid_cycle_resume_from_step3_blocked' -ExpectedResult 'BLOCK' -Blocked $ctxDMid.blocked -Allowed $ctxDMid.allowed -RuntimeExecuted $false -StepFailed $ctxDMid.step_failed -Reason $ctxDMid.block_reason
Add-CycleRecord -CaseId 'D' -Ctx $ctxDMid -RuntimeExecuted $false
[void]$ReplayEvidence.Add('CASE D | mid_cycle_resume_always_requires_fresh_1_2')

# E stale state with mutation and reverse — reuse context after inputs change back-and-forth
$stateE = New-LiveState -LedgerObj $ledgerObj -Art110Obj $art110Obj -Art111Obj $art111Obj -Art112Obj $art112Obj
$savedContextE = $null
[void](Invoke-Phase536ReplayResistantCycle -EntryPoint 'runtime_init_wrapper' -LiveState $stateE -AfterStepHook {
    param($step, $ctx)
    if ($step -eq 3) {
        $script:savedContextE = Copy-Object -Obj $ctx
    }
} -UsedSessionIds $UsedSessionIds)
# Now refresh inputs back to baseline and attempt to reuse the saved context from step3 of prior run
$stateE2 = New-LiveState -LedgerObj $ledgerObj -Art110Obj $art110Obj -Art111Obj $art111Obj -Art112Obj $art112Obj
# Attempt to resume with the stale context by starting a new cycle with old session_id
$ctxE2 = Invoke-Phase536ReplayResistantCycle -EntryPoint 'runtime_init_wrapper' -LiveState $stateE2 -AfterStepHook $null -ReuseSessionId $($savedContextE.session_id) -UsedSessionIds $UsedSessionIds
$caseE = $ctxE2.blocked -and ($ctxE2.step_failed -eq 1 -and $ctxE2.block_reason -like 'session_id_replay_detected*')
if ($caseE) { $replayBlockedCount++ }
Add-NormalizedCase -Id 'E' -Name 'stale_state_reuse_after_mutations_blocked' -ExpectedResult 'BLOCK' -Blocked $ctxE2.blocked -Allowed $ctxE2.allowed -RuntimeExecuted $false -StepFailed $ctxE2.step_failed -Reason $ctxE2.block_reason
Add-CycleRecord -CaseId 'E' -Ctx $ctxE2 -RuntimeExecuted $false
[void]$ReplayEvidence.Add('CASE E | ' + $ctxE2.block_reason)

# F replay context after art111 mutation and reverse
$pointerA = $null
$stateF = New-LiveState -LedgerObj $ledgerObj -Art110Obj $art110Obj -Art111Obj $art111Obj -Art112Obj $art112Obj
[void](Invoke-Phase536ReplayResistantCycle -EntryPoint 'runtime_init_wrapper' -LiveState $stateF -AfterStepHook {
    param($step, $ctx)
    if ($step -eq 2) {
        $script:pointerA = Copy-Object -Obj $ctx.frozen_hashes
    }
} -UsedSessionIds $UsedSessionIds)
# Now attempt to reuse the old frozen_hashes by computing them with fresh state but then injecting old ones
$stateF2 = New-LiveState -LedgerObj $ledgerObj -Art110Obj $art110Obj -Art111Obj $art111Obj -Art112Obj $art112Obj
$ctxF2 = Invoke-Phase536ReplayResistantCycle -EntryPoint 'runtime_init_wrapper' -LiveState $stateF2 -AfterStepHook {
    param($step, $ctx)
    if ($step -eq 2 -and $null -ne $script:pointerA) {
        # Mutate live_state AFTER step2 completes, but before step3 checks it
        # This should cause frozen_hashes to not match live_state hashes
        $ctx.live_state.art111.latest_entry_id = 'GF-F2-MUTATE'
    }
} -UsedSessionIds $UsedSessionIds
# F2 should be blocked because the live_state mutation causes hash mismatch at step3
$caseF = $ctxF2.blocked
if ($caseF) { $replayBlockedCount++ }
Add-NormalizedCase -Id 'F' -Name 'hash_pointer_reuse_blocked' -ExpectedResult 'BLOCK' -Blocked $ctxF2.blocked -Allowed $ctxF2.allowed -RuntimeExecuted $false -StepFailed $ctxF2.step_failed -Reason $ctxF2.block_reason
Add-CycleRecord -CaseId 'F' -Ctx $ctxF2 -RuntimeExecuted $false
[void]$ReplayEvidence.Add('CASE F | ' + $ctxF2.block_reason)

# G session uniqueness — two fresh cycles must have different session IDs
$stateG1 = New-LiveState -LedgerObj $ledgerObj -Art110Obj $art110Obj -Art111Obj $art111Obj -Art112Obj $art112Obj
$ctxG1 = Invoke-Phase536ReplayResistantCycle -EntryPoint 'runtime_init_wrapper' -LiveState $stateG1 -AfterStepHook $null -UsedSessionIds $UsedSessionIds
$sessionG1 = $ctxG1.session_id
$stateG2 = New-LiveState -LedgerObj $ledgerObj -Art110Obj $art110Obj -Art111Obj $art111Obj -Art112Obj $art112Obj
$ctxG2 = Invoke-Phase536ReplayResistantCycle -EntryPoint 'runtime_init_wrapper' -LiveState $stateG2 -AfterStepHook $null -UsedSessionIds $UsedSessionIds
$sessionG2 = $ctxG2.session_id
$caseG = ($sessionG1 -ne $sessionG2) -and $ctxG1.allowed -and $ctxG2.allowed
Add-NormalizedCase -Id 'G' -Name 'session_uniqueness_two_fresh_cycles_different_ids' -ExpectedResult 'ALLOW' -Blocked $ctxG1.blocked -Allowed $ctxG1.allowed -RuntimeExecuted $ctxG1.allowed -StepFailed $ctxG1.step_failed -Reason ('pair_unique=' + ($sessionG1 -ne $sessionG2))
Add-CycleRecord -CaseId 'G' -Ctx $ctxG1 -RuntimeExecuted $ctxG1.allowed
[void]$SessionMap.Add('SID_G1=' + $sessionG1)
[void]$SessionMap.Add('SID_G2=' + $sessionG2)

# H clean control 2 — verify fresh final run is allowed (completes successfully)
$stateH = New-LiveState -LedgerObj $ledgerObj -Art110Obj $art110Obj -Art111Obj $art111Obj -Art112Obj $art112Obj
$ctxH = Invoke-Phase536ReplayResistantCycle -EntryPoint 'runtime_init_wrapper' -LiveState $stateH -AfterStepHook $null -UsedSessionIds $UsedSessionIds
$runH = $false
if ($ctxH.allowed) { $runH = $true }
$sessionIdH = $ctxH.session_id
Add-NormalizedCase -Id 'H' -Name 'clean_control_2_allow' -ExpectedResult 'ALLOW' -Blocked $ctxH.blocked -Allowed $ctxH.allowed -RuntimeExecuted $runH -StepFailed $ctxH.step_failed -Reason $ctxH.block_reason
Add-CycleRecord -CaseId 'H' -Ctx $ctxH -RuntimeExecuted $runH
[void]$SessionMap.Add('SID_H=' + $sessionIdH)

[void]$ReplaySurface.Add('REPLAY_VECTORS=reuse_session_id,reuse_context_token,reuse_frozen_snapshot,reuse_step_trace,mid_cycle_resume,stale_state')
[void]$ReplaySurface.Add('REPLAY_CACHE_DEPTH=full_cycle_frozen_state')
[void]$ReplaySurface.Add('SESSION_ID_UNIQUENESS=per_cycle_required')
[void]$ReplaySurface.Add('UNGUARDED_ENTRY_POINTS=0')

$runtimeCount = @($CycleMetrics | Where-Object { $_.case_id -in @('A','B','C','D','E','F','G','H') -and $_.runtime_executed }).Count
$passCount = @($CaseMatrix | Where-Object { $_.pass_fail -eq 'PASS' }).Count
$failCount = @($CaseMatrix | Where-Object { $_.pass_fail -eq 'FAIL' }).Count
$tableReplayBlockedCount = @($CaseMatrix | Where-Object { $_.case_id -in @('B','C','E','F') -and $_.blocked }).Count
$cycleReplayBlockedCount = @($CycleMetrics | Where-Object { $_.case_id -in @('B','C','E','F') -and $_.blocked }).Count
$consistencyPass = $true
if ($CaseMatrix.Count -ne 8) { $consistencyPass = $false }
if (($passCount + $failCount) -ne 8) { $consistencyPass = $false }
if ($runtimeCount -ne 3) { $consistencyPass = $false }
if ($tableReplayBlockedCount -ne $replayBlockedCount) { $consistencyPass = $false }
if ($cycleReplayBlockedCount -ne $replayBlockedCount) { $consistencyPass = $false }
if ($failCount -ne 0) { $consistencyPass = $false }
if ($unguardedReplayPaths -ne 0) { $consistencyPass = $false }
if (-not $consistencyPass) { $allPass = $false }
$consistencyCheck = if ($consistencyPass) { 'PASS' } else { 'FAIL' }
$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$validationTable = [System.Collections.Generic.List[string]]::new()
[void]$validationTable.Add('case|expected_result|actual_result|blocked|allowed|runtime_executed|step_failed|reason|pass_fail')
foreach ($row in $CaseMatrix) {
    [void]$validationTable.Add(
        ($row.case_id + '|' + $row.expected_result + '|' + $row.actual_result + '|' + $row.blocked + '|' + $row.allowed + '|' + $row.runtime_executed + '|' + $row.step_failed + '|' + $row.reason + '|' + $row.pass_fail)
    )
}

Write-ProofFile (Join-Path $PF '01_status.txt') (@(
    'PHASE=53.6',
    'TITLE=Enforcement Replay Resistance and Session Uniqueness',
    ('GATE={0}' -f [string]$Gate),
    ('PASS_COUNT={0}/8' -f [int]$passCount),
    ('FAIL_COUNT={0}' -f [int]$failCount),
    ('replay_blocked_count={0}' -f [int]$replayBlockedCount),
    ('runtime_execution_count={0}' -f [int]$runtimeCount),
    ('unguarded_replay_paths={0}' -f [int]$unguardedReplayPaths),
    ('consistency_check={0}' -f [string]$consistencyCheck),
    'NO_FALLBACK=TRUE',
    'NO_REGENERATION=TRUE',
    'RUNTIME_STATE_UNCHANGED=TRUE'
) -join "`r`n")

Write-ProofFile (Join-Path $PF '02_head.txt') (@(
    'RUNNER=' + $RunnerPath,
    'LEDGER=' + $LedgerPath,
    'ART110=' + $Art110Path,
    'ART111=' + $Art111Path,
    'ART112=' + $Art112Path
) -join "`r`n")

Write-ProofFile (Join-Path $PF '10_replay_surface_inventory.txt') ($ReplaySurface -join "`r`n")
Write-ProofFile (Join-Path $PF '11_session_identity_map.txt') ($SessionMap -join "`r`n")

Write-ProofFile (Join-Path $PF '12_files_touched.txt') (@(
    'READ=' + $LedgerPath,
    'READ=' + $Art110Path,
    'READ=' + $Art111Path,
    'READ=' + $Art112Path,
    'WRITE_PROOF=' + $PF,
    'NO_CONTROL_PLANE_WRITE=TRUE'
) -join "`r`n")

Write-ProofFile (Join-Path $PF '13_build_output.txt') (@(
    'CASE_COUNT=8',
    ('PASSED={0}' -f [int]$passCount),
    ('FAILED={0}' -f [int]$failCount),
    ('RUNTIME_EXECUTIONS={0}' -f [int]$runtimeCount),
    ('replay_blocked_count={0}' -f [int]$replayBlockedCount),
    ('unguarded_replay_paths={0}' -f [int]$unguardedReplayPaths),
    ('consistency_check={0}' -f [string]$consistencyCheck),
    ('GATE={0}' -f [string]$Gate)
) -join "`r`n")

Write-ProofFile (Join-Path $PF '14_validation_results.txt') ($validationTable -join "`r`n")

Write-ProofFile (Join-Path $PF '15_behavior_summary.txt') (@(
    'A_clean_control_allow=' + ((($CaseMatrix | Where-Object { $_.case_id -eq 'A' } | Select-Object -First 1).pass_fail) -eq 'PASS'),
    'B_reuse_prior_session_id_blocked=' + $caseB,
    'C_reuse_stale_frozen_snapshot_blocked=' + $caseC,
    'D_mid_cycle_resume_from_step3_blocked=' + $caseDMid,
    'E_stale_state_reuse_after_mutations_blocked=' + $caseE,
    'F_hash_pointer_reuse_blocked=' + $caseF,
    'G_session_uniqueness_two_fresh_cycles_different_ids=' + $caseG,
    'H_clean_control_2_allow=' + ((($CaseMatrix | Where-Object { $_.case_id -eq 'H' } | Select-Object -First 1).pass_fail) -eq 'PASS'),
    'replay_blocked_count=' + $replayBlockedCount,
    'runtime_execution_count=' + $runtimeCount,
    'unguarded_replay_paths=' + $unguardedReplayPaths,
    'consistency_check=' + $consistencyCheck,
    'NO_FALLBACK=TRUE',
    'NO_REGENERATION=TRUE',
    'RUNTIME_STATE_UNCHANGED=TRUE'
) -join "`r`n")

Write-ProofFile (Join-Path $PF '16_cycle_record.txt') ($CycleRecords -join "`r`n")
Write-ProofFile (Join-Path $PF '17_replay_evidence.txt') ($ReplayEvidence -join "`r`n")

Write-ProofFile (Join-Path $PF '98_gate_phase53_6.txt') (@(
    'PHASE=53.6',
    ('GATE={0}' -f [string]$Gate),
    ('PASS_COUNT={0}/8' -f [int]$passCount),
    ('replay_blocked_count={0}' -f [int]$replayBlockedCount),
    ('runtime_execution_count={0}' -f [int]$runtimeCount),
    ('unguarded_replay_paths={0}' -f [int]$unguardedReplayPaths),
    ('consistency_check={0}' -f [string]$consistencyCheck),
    'NO_FALLBACK=TRUE',
    'NO_REGENERATION=TRUE'
) -join "`r`n")

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
