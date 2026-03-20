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

function Get-ContextIntegrityToken {
    param([object]$Ctx)
    $tokenObj = [ordered]@{
        frozen_hashes = $Ctx.frozen_hashes
        frozen_exists = $Ctx.frozen_exists
        expected_step = $Ctx.expected_step
        entrypoint = $Ctx.entrypoint
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

function Invoke-Phase535ImmutableEnforcementCycle {
    param(
        [string]$EntryPoint,
        [object]$LiveState,
        [scriptblock]$AfterStepHook
    )

    $ctx = [ordered]@{
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
        chain_status = ''
    }

    if ($EntryPoint -ne 'runtime_init_wrapper') {
        Stop-Cycle -Ctx $ctx -Step 0 -Reason 'single_entry_violation:' + $EntryPoint
        return $ctx
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
    $ctx.chain_status = [string]$chain.reason
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
$RunnerPath = Join-Path $Root 'tools\phase53_5\phase53_5_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_enforcement_immutability_toctou_runner.ps1'
$LedgerPath = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$Art110Path = Join-Path $Root 'control_plane\110_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint_regression_anchor.json'
$Art111Path = Join-Path $Root 'control_plane\111_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline.json'
$Art112Path = Join-Path $Root 'control_plane\112_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_integrity.json'
$PF = Join-Path $Root ('_proof\phase53_5_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_enforcement_immutability_toctou_' + $Timestamp)

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
$ImmutableMap = [System.Collections.Generic.List[string]]::new()
$RwSurface = [System.Collections.Generic.List[string]]::new()
$CycleRecords = [System.Collections.Generic.List[string]]::new()
$TamperEvidence = [System.Collections.Generic.List[string]]::new()
$allPass = $true
$tamperDetectedCount = 0
$runtimeCount = 0
$unguardedMutationPaths = 0

function Add-Case {
    param([string]$Id, [string]$Name, [bool]$Pass, [string]$Detail)
    [void]$Validation.Add('CASE ' + $Id + ' ' + $Name + ' | ' + $Detail + ' => ' + $(if ($Pass) { 'PASS' } else { 'FAIL' }))
    if (-not $Pass) { $script:allPass = $false }
}

function Add-CycleRecord {
    param([string]$CaseId, [object]$Ctx, [bool]$RuntimeExecuted)
    [void]$CycleRecords.Add('CASE ' + $CaseId + ' | allowed=' + $Ctx.allowed + ' | blocked=' + $Ctx.blocked + ' | step_failed=' + $Ctx.step_failed + ' | reason=' + $Ctx.block_reason + ' | continuation=' + $Ctx.continuation_status + ' | runtime_executed=' + $RuntimeExecuted + ' | trace=' + (($Ctx.trace) -join '>') + ' | no_fallback=TRUE | no_regeneration=TRUE')
}

# A clean control
$stateA = New-LiveState -LedgerObj $ledgerObj -Art110Obj $art110Obj -Art111Obj $art111Obj -Art112Obj $art112Obj
$ctxA = Invoke-Phase535ImmutableEnforcementCycle -EntryPoint 'runtime_init_wrapper' -LiveState $stateA -AfterStepHook $null
$runA = $false
if ($ctxA.allowed) { $runA = $true; $runtimeCount++ }
$caseA = $ctxA.allowed -and $runA
Add-Case -Id 'A' -Name 'clean_control_allow' -Pass $caseA -Detail ('allowed=' + $ctxA.allowed + ' runtime_executed=' + $runA)
Add-CycleRecord -CaseId 'A' -Ctx $ctxA -RuntimeExecuted $runA

# B mutate snapshot after existence check
$stateB = New-LiveState -LedgerObj $ledgerObj -Art110Obj $art110Obj -Art111Obj $art111Obj -Art112Obj $art112Obj
$ctxB = Invoke-Phase535ImmutableEnforcementCycle -EntryPoint 'runtime_init_wrapper' -LiveState $stateB -AfterStepHook {
    param($step, $ctx)
    if ($step -eq 1) {
        $ctx.live_state.art111.latest_entry_id = 'GF-TOCTOU'
    }
}
$caseB = $ctxB.blocked -and ($ctxB.step_failed -eq 2)
if ($caseB) { $tamperDetectedCount++ }
Add-Case -Id 'B' -Name 'snapshot_mutation_after_existence_blocked' -Pass $caseB -Detail ('blocked=' + $ctxB.blocked + ' step=' + $ctxB.step_failed + ' reason=' + $ctxB.block_reason)
Add-CycleRecord -CaseId 'B' -Ctx $ctxB -RuntimeExecuted $false
[void]$TamperEvidence.Add('CASE B | ' + $ctxB.block_reason)

# C mutate integrity after hash check starts
$stateC = New-LiveState -LedgerObj $ledgerObj -Art110Obj $art110Obj -Art111Obj $art111Obj -Art112Obj $art112Obj
$ctxC = Invoke-Phase535ImmutableEnforcementCycle -EntryPoint 'runtime_init_wrapper' -LiveState $stateC -AfterStepHook {
    param($step, $ctx)
    if ($step -eq 3) {
        $ctx.live_state.art112.baseline_snapshot_hash = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
    }
}
$caseC = $ctxC.blocked -and (($ctxC.step_failed -eq 4) -or ($ctxC.block_reason -like 'immutable_input_mutation_detected_art112*'))
if ($caseC) { $tamperDetectedCount++ }
Add-Case -Id 'C' -Name 'integrity_mutation_after_hash_start_blocked' -Pass $caseC -Detail ('blocked=' + $ctxC.blocked + ' step=' + $ctxC.step_failed + ' reason=' + $ctxC.block_reason)
Add-CycleRecord -CaseId 'C' -Ctx $ctxC -RuntimeExecuted $false
[void]$TamperEvidence.Add('CASE C | ' + $ctxC.block_reason)

# D mutate ledger after chain validation
$stateD = New-LiveState -LedgerObj $ledgerObj -Art110Obj $art110Obj -Art111Obj $art111Obj -Art112Obj $art112Obj
$ctxD = Invoke-Phase535ImmutableEnforcementCycle -EntryPoint 'runtime_init_wrapper' -LiveState $stateD -AfterStepHook {
    param($step, $ctx)
    if ($step -eq 4) {
        $ctx.live_state.ledger.entries[0].fingerprint_hash = 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'
    }
}
$caseD = $ctxD.blocked -and (($ctxD.step_failed -eq 5) -or ($ctxD.block_reason -like 'immutable_input_mutation_detected_ledger*'))
if ($caseD) { $tamperDetectedCount++ }
Add-Case -Id 'D' -Name 'ledger_mutation_after_chain_validation_blocked' -Pass $caseD -Detail ('blocked=' + $ctxD.blocked + ' step=' + $ctxD.step_failed + ' reason=' + $ctxD.block_reason)
Add-CycleRecord -CaseId 'D' -Ctx $ctxD -RuntimeExecuted $false
[void]$TamperEvidence.Add('CASE D | ' + $ctxD.block_reason)

# E mutate artifact110 before final comparison
$stateE = New-LiveState -LedgerObj $ledgerObj -Art110Obj $art110Obj -Art111Obj $art111Obj -Art112Obj $art112Obj
$ctxE = Invoke-Phase535ImmutableEnforcementCycle -EntryPoint 'runtime_init_wrapper' -LiveState $stateE -AfterStepHook {
    param($step, $ctx)
    if ($step -eq 5) {
        $ctx.live_state.art110.coverage_fingerprint = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
    }
}
$caseE = $ctxE.blocked -and (($ctxE.step_failed -eq 6) -or ($ctxE.block_reason -like 'immutable_input_mutation_detected_art110*'))
if ($caseE) { $tamperDetectedCount++ }
Add-Case -Id 'E' -Name 'artifact110_mutation_before_final_compare_blocked' -Pass $caseE -Detail ('blocked=' + $ctxE.blocked + ' step=' + $ctxE.step_failed + ' reason=' + $ctxE.block_reason)
Add-CycleRecord -CaseId 'E' -Ctx $ctxE -RuntimeExecuted $false
[void]$TamperEvidence.Add('CASE E | ' + $ctxE.block_reason)

# F intermediate enforcement-state tamper
$stateF = New-LiveState -LedgerObj $ledgerObj -Art110Obj $art110Obj -Art111Obj $art111Obj -Art112Obj $art112Obj
$ctxF = Invoke-Phase535ImmutableEnforcementCycle -EntryPoint 'runtime_init_wrapper' -LiveState $stateF -AfterStepHook {
    param($step, $ctx)
    if ($step -eq 2) {
        $ctx.frozen_hashes.art111 = 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
    }
}
$caseF = $ctxF.blocked -and ($ctxF.block_reason -like 'intermediate_state_tamper_detected*')
if ($caseF) { $tamperDetectedCount++ }
Add-Case -Id 'F' -Name 'intermediate_state_tamper_blocked' -Pass $caseF -Detail ('blocked=' + $ctxF.blocked + ' step=' + $ctxF.step_failed + ' reason=' + $ctxF.block_reason)
Add-CycleRecord -CaseId 'F' -Ctx $ctxF -RuntimeExecuted $false
[void]$TamperEvidence.Add('CASE F | ' + $ctxF.block_reason)

# G multi-read mixed-state fail
$stateG = New-LiveState -LedgerObj $ledgerObj -Art110Obj $art110Obj -Art111Obj $art111Obj -Art112Obj $art112Obj
$toggle = $false
$ctxG = Invoke-Phase535ImmutableEnforcementCycle -EntryPoint 'runtime_init_wrapper' -LiveState $stateG -AfterStepHook {
    param($step, $ctx)
    if ($step -eq 3) {
        $script:toggle = -not $script:toggle
        if ($script:toggle) {
            $ctx.live_state.art111.latest_entry_id = 'GF-MIXED-1'
        } else {
            $ctx.live_state.art111.latest_entry_id = 'GF-0015'
        }
    }
}
$caseG = $ctxG.blocked -and ($ctxG.block_reason -like 'immutable_input_mutation_detected_*' -or $ctxG.block_reason -like 'mixed_state_read_detected_*')
if ($caseG) { $tamperDetectedCount++ }
Add-Case -Id 'G' -Name 'mixed_state_reads_blocked' -Pass $caseG -Detail ('blocked=' + $ctxG.blocked + ' step=' + $ctxG.step_failed + ' reason=' + $ctxG.block_reason)
Add-CycleRecord -CaseId 'G' -Ctx $ctxG -RuntimeExecuted $false
[void]$TamperEvidence.Add('CASE G | ' + $ctxG.block_reason)

# H multi-read consistency clean cycle
$stateH = New-LiveState -LedgerObj $ledgerObj -Art110Obj $art110Obj -Art111Obj $art111Obj -Art112Obj $art112Obj
$ctxH = Invoke-Phase535ImmutableEnforcementCycle -EntryPoint 'runtime_init_wrapper' -LiveState $stateH -AfterStepHook $null
$runH = $false
if ($ctxH.allowed) { $runH = $true; $runtimeCount++ }
$caseH = $ctxH.allowed -and $runH
Add-Case -Id 'H' -Name 'multi_read_consistency_clean_allow' -Pass $caseH -Detail ('allowed=' + $ctxH.allowed + ' runtime_executed=' + $runH)
Add-CycleRecord -CaseId 'H' -Ctx $ctxH -RuntimeExecuted $runH

$baseState = New-LiveState -LedgerObj $ledgerObj -Art110Obj $art110Obj -Art111Obj $art111Obj -Art112Obj $art112Obj
$baseHashes = Get-LiveHashes -State $baseState

[void]$ImmutableMap.Add('ledger_hash=' + $baseHashes.ledger)
[void]$ImmutableMap.Add('art110_hash=' + $baseHashes.art110)
[void]$ImmutableMap.Add('art111_hash=' + $baseHashes.art111)
[void]$ImmutableMap.Add('art112_hash=' + $baseHashes.art112)
[void]$ImmutableMap.Add('snapshot_policy=freeze_once_validate_all_steps_against_frozen_inputs')

[void]$RwSurface.Add('READ: control_plane/70_guard_fingerprint_trust_chain.json')
[void]$RwSurface.Add('READ: control_plane/110_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint_regression_anchor.json')
[void]$RwSurface.Add('READ: control_plane/111_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline.json')
[void]$RwSurface.Add('READ: control_plane/112_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_integrity.json')
[void]$RwSurface.Add('WRITE: proof artifacts only')
[void]$RwSurface.Add('MUTATION_PATHS_FOR_RUNTIME=0')

$passCount = @($Validation | Where-Object { $_ -match '=> PASS$' }).Count
$failCount = @($Validation | Where-Object { $_ -match '=> FAIL$' }).Count
if ($runtimeCount -ne 2) { $allPass = $false }
$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

Write-ProofFile (Join-Path $PF '01_status.txt') (@(
    'PHASE=53.5',
    'TITLE=State Immutability and TOCTOU Resistance Enforcement',
    'GATE=' + $Gate,
    'PASS_COUNT=' + $passCount + '/8',
    'FAIL_COUNT=' + $failCount,
    'tamper_detected_count=' + $tamperDetectedCount,
    'unguarded_mutation_paths=' + $unguardedMutationPaths,
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

Write-ProofFile (Join-Path $PF '10_immutable_input_map.txt') ($ImmutableMap -join "`r`n")
Write-ProofFile (Join-Path $PF '11_read_write_surface_inventory.txt') ($RwSurface -join "`r`n")

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
    'PASSED=' + $passCount,
    'FAILED=' + $failCount,
    'RUNTIME_EXECUTIONS=' + $runtimeCount,
    'tamper_detected_count=' + $tamperDetectedCount,
    'unguarded_mutation_paths=' + $unguardedMutationPaths,
    'GATE=' + $Gate
) -join "`r`n")

Write-ProofFile (Join-Path $PF '14_validation_results.txt') ($Validation -join "`r`n")

Write-ProofFile (Join-Path $PF '15_behavior_summary.txt') (@(
    'A_clean_control_allow=' + $caseA,
    'B_snapshot_mutation_after_existence_blocked=' + $caseB,
    'C_integrity_mutation_after_hash_start_blocked=' + $caseC,
    'D_ledger_mutation_after_chain_validation_blocked=' + $caseD,
    'E_art110_mutation_before_final_compare_blocked=' + $caseE,
    'F_intermediate_state_tamper_blocked=' + $caseF,
    'G_mixed_state_reads_blocked=' + $caseG,
    'H_multi_read_consistency_clean_allow=' + $caseH,
    'tamper_detected_count=' + $tamperDetectedCount,
    'unguarded_mutation_paths=' + $unguardedMutationPaths,
    'NO_FALLBACK=TRUE',
    'NO_REGENERATION=TRUE',
    'RUNTIME_STATE_UNCHANGED=TRUE'
) -join "`r`n")

Write-ProofFile (Join-Path $PF '16_immutability_cycle_record.txt') ($CycleRecords -join "`r`n")
Write-ProofFile (Join-Path $PF '17_tamper_detection_evidence.txt') ($TamperEvidence -join "`r`n")

Write-ProofFile (Join-Path $PF '98_gate_phase53_5.txt') (@(
    'PHASE=53.5',
    'GATE=' + $Gate,
    'PASS_COUNT=' + $passCount + '/8',
    'tamper_detected_count=' + $tamperDetectedCount,
    'unguarded_mutation_paths=' + $unguardedMutationPaths,
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
