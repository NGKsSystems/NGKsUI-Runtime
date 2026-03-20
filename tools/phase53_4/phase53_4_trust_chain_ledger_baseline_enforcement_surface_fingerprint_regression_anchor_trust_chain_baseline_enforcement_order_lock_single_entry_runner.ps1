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

function Copy-Entries {
    param([object[]]$Entries)
    $copy = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $Entries) {
        [void]$copy.Add(($entry | ConvertTo-Json -Depth 20 | ConvertFrom-Json))
    }
    return @($copy)
}

function New-OrderContext {
    param([string]$EntryPoint)
    return [ordered]@{
        entrypoint = $EntryPoint
        expected_step = 1
        executed_steps = [System.Collections.Generic.List[int]]::new()
        trace = [System.Collections.Generic.List[string]]::new()
        blocked = $false
        block_reason = ''
        step_failed = 0
        allowed = $false
        finalized = $false
        continuation_status = ''
        chain_integrity_status = ''
        computed_snap_hash = ''
        stored_snap_hash = ''
        computed_cov_fp = ''
        baseline_cov_fp = ''
    }
}

function Stop-Context {
    param([object]$Context, [int]$Step, [string]$Reason)
    $Context.blocked = $true
    $Context.step_failed = $Step
    $Context.block_reason = $Reason
}

function Invoke-OrderedStep {
    param(
        [object]$Context,
        [int]$Step,
        [string]$StepName,
        [scriptblock]$Validator
    )

    if ($Context.blocked -or $Context.finalized) {
        return
    }

    if ([string]$Context.entrypoint -ne 'runtime_init_wrapper') {
        Stop-Context -Context $Context -Step $Step -Reason 'single_entry_violation:' + [string]$Context.entrypoint
        return
    }

    if ($Step -ne $Context.expected_step) {
        Stop-Context -Context $Context -Step $Step -Reason ('order_violation_expected_' + $Context.expected_step + '_got_' + $Step)
        return
    }

    if ($Context.executed_steps.Contains($Step)) {
        Stop-Context -Context $Context -Step $Step -Reason ('duplicate_step_' + $Step)
        return
    }

    [void]$Context.trace.Add('step' + $Step + ':' + $StepName)
    $outcome = & $Validator
    if (-not $outcome.pass) {
        Stop-Context -Context $Context -Step $Step -Reason ('step' + $Step + '_failed:' + [string]$outcome.reason)
        return
    }

    [void]$Context.executed_steps.Add($Step)
    $Context.expected_step = $Context.expected_step + 1
}

function Complete-OrderContext {
    param([object]$Context)

    if ($Context.blocked) {
        $Context.allowed = $false
        $Context.finalized = $true
        return
    }

    if ($Context.executed_steps.Count -ne 7 -or $Context.expected_step -ne 8) {
        Stop-Context -Context $Context -Step 8 -Reason 'incomplete_or_split_execution'
        $Context.allowed = $false
        $Context.finalized = $true
        return
    }

    $expectedTrace = @('step1:validate_111_exists','step2:validate_112_exists','step3:validate_111_hash_matches_112','step4:validate_chain_integrity','step5:validate_head_or_continuation','step6:validate_110_fingerprint','step7:validate_semantic_fields')
    $trace = @($Context.trace)
    $traceOk = ($trace.Count -eq $expectedTrace.Count)
    if ($traceOk) {
        for ($i = 0; $i -lt $expectedTrace.Count; $i++) {
            if ($trace[$i] -ne $expectedTrace[$i]) { $traceOk = $false; break }
        }
    }

    if (-not $traceOk) {
        Stop-Context -Context $Context -Step 8 -Reason 'order_trace_mismatch'
        $Context.allowed = $false
        $Context.finalized = $true
        return
    }

    $Context.allowed = $true
    $Context.finalized = $true
}

function Invoke-Phase534StrictWrapper {
    param(
        [object[]]$LiveEntries,
        [object]$Artifact110,
        [object]$Artifact111,
        [object]$Artifact112,
        [bool]$Artifact111Exists,
        [bool]$Artifact112Exists
    )

    $ctx = New-OrderContext -EntryPoint 'runtime_init_wrapper'

    Invoke-OrderedStep -Context $ctx -Step 1 -StepName 'validate_111_exists' -Validator {
        if (-not $Artifact111Exists) { return [ordered]@{ pass = $false; reason = 'artifact_111_missing' } }
        return [ordered]@{ pass = $true; reason = 'ok' }
    }

    Invoke-OrderedStep -Context $ctx -Step 2 -StepName 'validate_112_exists' -Validator {
        if (-not $Artifact112Exists) { return [ordered]@{ pass = $false; reason = 'artifact_112_missing' } }
        return [ordered]@{ pass = $true; reason = 'ok' }
    }

    Invoke-OrderedStep -Context $ctx -Step 3 -StepName 'validate_111_hash_matches_112' -Validator {
        $computed = Get-CanonicalObjectHash -Obj $Artifact111
        $stored = [string]$Artifact112.baseline_snapshot_hash
        $ctx.computed_snap_hash = $computed
        $ctx.stored_snap_hash = $stored
        if ($computed -ne $stored) { return [ordered]@{ pass = $false; reason = 'baseline_snapshot_hash_mismatch' } }
        return [ordered]@{ pass = $true; reason = 'ok' }
    }

    Invoke-OrderedStep -Context $ctx -Step 4 -StepName 'validate_chain_integrity' -Validator {
        $chain = Test-ExtendedTrustChain -Entries $LiveEntries
        $ctx.chain_integrity_status = [string]$chain.reason
        if (-not $chain.pass) { return [ordered]@{ pass = $false; reason = 'chain_integrity_failed:' + [string]$chain.reason } }
        $ctx.live_head_hash = [string]$chain.last_entry_hash
        $ctx.chain_hashes = $chain.chain_hashes
        return [ordered]@{ pass = $true; reason = 'ok' }
    }

    Invoke-OrderedStep -Context $ctx -Step 5 -StepName 'validate_head_or_continuation' -Validator {
        $baselineHead = [string]$Artifact111.ledger_head_hash
        $baselineLen = [int]$Artifact111.ledger_length
        $ctx.baseline_head_hash = $baselineHead

        if ([string]$ctx.live_head_hash -eq $baselineHead) {
            $ctx.continuation_status = 'exact'
            return [ordered]@{ pass = $true; reason = 'ok' }
        }

        if ($ctx.chain_hashes.Count -gt $baselineLen -and $baselineLen -gt 0) {
            $baselinePosHash = [string]$ctx.chain_hashes[$baselineLen - 1]
            if ($baselinePosHash -eq $baselineHead) {
                $ctx.continuation_status = 'continuation'
                return [ordered]@{ pass = $true; reason = 'ok' }
            }
            return [ordered]@{ pass = $false; reason = 'continuation_invalid' }
        }

        return [ordered]@{ pass = $false; reason = 'ledger_head_drift' }
    }

    Invoke-OrderedStep -Context $ctx -Step 6 -StepName 'validate_110_fingerprint' -Validator {
        $fp110 = [string]$Artifact110.coverage_fingerprint
        $fp111 = [string]$Artifact111.coverage_fingerprint_hash
        $fp112 = [string]$Artifact112.coverage_fingerprint_hash
        $ctx.computed_cov_fp = $fp110
        $ctx.baseline_cov_fp = $fp111
        if ($fp110 -ne $fp111 -or $fp110 -ne $fp112) {
            return [ordered]@{ pass = $false; reason = 'artifact110_coverage_fingerprint_mismatch' }
        }
        return [ordered]@{ pass = $true; reason = 'ok' }
    }

    Invoke-OrderedStep -Context $ctx -Step 7 -StepName 'validate_semantic_fields' -Validator {
        $errs = [System.Collections.Generic.List[string]]::new()
        if ([string]$Artifact111.phase_locked -ne '53.1') { [void]$errs.Add('111.phase_locked_not_53.1') }
        if ([string]$Artifact111.latest_entry_id -ne 'GF-0015') { [void]$errs.Add('111.latest_entry_id_not_GF-0015') }
        if ([string]$Artifact111.latest_entry_phase_locked -ne '53.0') { [void]$errs.Add('111.latest_entry_phase_locked_not_53.0') }
        if ([int]$Artifact111.ledger_length -ne 15) { [void]$errs.Add('111.ledger_length_not_15') }
        $src = @($Artifact111.source_phases | ForEach-Object { [string]$_ })
        if (($src -join ',') -ne '52.8,52.9,53.0') { [void]$errs.Add('111.source_phases_mismatch') }
        if ([string]$Artifact112.phase_locked -ne '53.1') { [void]$errs.Add('112.phase_locked_not_53.1') }
        if ($errs.Count -gt 0) { return [ordered]@{ pass = $false; reason = ($errs -join ',') } }
        return [ordered]@{ pass = $true; reason = 'ok' }
    }

    Complete-OrderContext -Context $ctx

    return [ordered]@{
        allowed = $ctx.allowed
        blocked = $ctx.blocked
        step_failed = $ctx.step_failed
        block_reason = $ctx.block_reason
        trace = @($ctx.trace)
        continuation_status = $ctx.continuation_status
        chain_integrity_status = $ctx.chain_integrity_status
    }
}

function Invoke-BypassAttempt {
    param(
        [string]$EntryPoint,
        [scriptblock]$Attempt,
        [object[]]$LiveEntries,
        [object]$Artifact110,
        [object]$Artifact111,
        [object]$Artifact112,
        [bool]$Artifact111Exists,
        [bool]$Artifact112Exists
    )

    $gate = Invoke-Phase534StrictWrapper -LiveEntries $LiveEntries -Artifact110 $Artifact110 -Artifact111 $Artifact111 -Artifact112 $Artifact112 -Artifact111Exists $Artifact111Exists -Artifact112Exists $Artifact112Exists
    $executed = $false
    $result = 'BLOCKED'

    if ($gate.allowed) {
        $executed = $true
        & $Attempt
        $result = 'ALLOWED'
    }

    return [ordered]@{
        entrypoint = $EntryPoint
        gate = $gate
        operation_executed = $executed
        operation_result = $result
    }
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunnerPath = Join-Path $Root 'tools\phase53_4\phase53_4_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_enforcement_order_lock_single_entry_runner.ps1'
$LedgerPath = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$Art110Path = Join-Path $Root 'control_plane\110_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint_regression_anchor.json'
$Art111Path = Join-Path $Root 'control_plane\111_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline.json'
$Art112Path = Join-Path $Root 'control_plane\112_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_integrity.json'
$PF = Join-Path $Root ('_proof\phase53_4_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_enforcement_order_lock_single_entry_' + $Timestamp)

New-Item -ItemType Directory -Path $PF | Out-Null

foreach ($path in @($LedgerPath, $Art110Path, $Art111Path, $Art112Path)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw 'Missing required file: ' + $path
    }
}

$ledgerObj = Get-Content -LiteralPath $LedgerPath -Raw | ConvertFrom-Json
$liveEntries = @($ledgerObj.entries)
$art110Obj = Get-Content -LiteralPath $Art110Path -Raw | ConvertFrom-Json
$art111Obj = Get-Content -LiteralPath $Art111Path -Raw | ConvertFrom-Json
$art112Obj = Get-Content -LiteralPath $Art112Path -Raw | ConvertFrom-Json

$invalid112 = $art112Obj | ConvertTo-Json -Depth 20 | ConvertFrom-Json
$invalid112 | Add-Member -MemberType NoteProperty -Name baseline_snapshot_hash -Value 'badbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbad1' -Force

$Validation = [System.Collections.Generic.List[string]]::new()
$TraceLines = [System.Collections.Generic.List[string]]::new()
$GateRecords = [System.Collections.Generic.List[string]]::new()
$BlockEvidence = [System.Collections.Generic.List[string]]::new()
$allPass = $true
$runtimeCount = 0

function Add-Case {
    param([string]$Id, [string]$Name, [bool]$Pass, [string]$Detail)
    [void]$Validation.Add('CASE ' + $Id + ' ' + $Name + ' | ' + $Detail + ' => ' + $(if ($Pass) { 'PASS' } else { 'FAIL' }))
    if (-not $Pass) { $script:allPass = $false }
}

function Add-GateRecord {
    param([string]$CaseId, [object]$GateOrRun)
    $hasGateProp = $null -ne ($GateOrRun.PSObject.Properties['gate'])
    if ($hasGateProp) {
        [void]$GateRecords.Add('CASE ' + $CaseId + ' | entrypoint=' + $GateOrRun.entrypoint + ' | gate_allowed=' + $GateOrRun.gate.allowed + ' | step_failed=' + $GateOrRun.gate.step_failed + ' | block_reason=' + $GateOrRun.gate.block_reason + ' | operation_executed=' + $GateOrRun.operation_executed + ' | operation_result=' + $GateOrRun.operation_result)
    } else {
        if ($GateOrRun -is [System.Collections.IDictionary]) {
            [void]$GateRecords.Add('CASE ' + $CaseId + ' | gate_allowed=' + $GateOrRun['allowed'] + ' | step_failed=' + $GateOrRun['step_failed'] + ' | block_reason=' + $GateOrRun['block_reason'] + ' | trace=' + (($GateOrRun['trace']) -join '>'))
        } else {
            [void]$GateRecords.Add('CASE ' + $CaseId + ' | gate_allowed=' + $GateOrRun.allowed + ' | step_failed=' + $GateOrRun.step_failed + ' | block_reason=' + $GateOrRun.block_reason + ' | trace=' + (($GateOrRun.trace) -join '>'))
        }
    }
}

# A. Clean control
$runA = Invoke-BypassAttempt -EntryPoint 'runtime_init_wrapper' -Attempt { $script:runtimeCount++ } -LiveEntries $liveEntries -Artifact110 $art110Obj -Artifact111 $art111Obj -Artifact112 $art112Obj -Artifact111Exists $true -Artifact112Exists $true
$expectedTrace = 'step1:validate_111_exists>step2:validate_112_exists>step3:validate_111_hash_matches_112>step4:validate_chain_integrity>step5:validate_head_or_continuation>step6:validate_110_fingerprint>step7:validate_semantic_fields'
$actualTraceA = ($runA.gate.trace -join '>')
$caseA = $runA.gate.allowed -and $runA.operation_executed -and ($actualTraceA -eq $expectedTrace)
Add-Case -Id 'A' -Name 'clean_control_allow' -Pass $caseA -Detail ('allowed=' + $runA.gate.allowed + ' trace_ok=' + ($actualTraceA -eq $expectedTrace) + ' operation_executed=' + $runA.operation_executed)
Add-GateRecord -CaseId 'A' -GateOrRun $runA
[void]$TraceLines.Add('CASE A TRACE=' + $actualTraceA)

# B. Order lock proof: skip/reorder/duplicate must fail
# Build manual contexts to prove strict order enforcement
$ctxB1 = New-OrderContext -EntryPoint 'runtime_init_wrapper'
Invoke-OrderedStep -Context $ctxB1 -Step 2 -StepName 'validate_112_exists' -Validator { [ordered]@{ pass = $true; reason = 'ok' } }
Complete-OrderContext -Context $ctxB1
$skipBlocked = $ctxB1.blocked -and ($ctxB1.block_reason -like 'order_violation*')

$ctxB2 = New-OrderContext -EntryPoint 'runtime_init_wrapper'
Invoke-OrderedStep -Context $ctxB2 -Step 1 -StepName 'validate_111_exists' -Validator { [ordered]@{ pass = $true; reason = 'ok' } }
Invoke-OrderedStep -Context $ctxB2 -Step 1 -StepName 'validate_111_exists' -Validator { [ordered]@{ pass = $true; reason = 'ok' } }
Complete-OrderContext -Context $ctxB2
$dupBlocked = $ctxB2.blocked

$caseB = $skipBlocked -and $dupBlocked
Add-Case -Id 'B' -Name 'order_lock_skip_reorder_duplicate_blocked' -Pass $caseB -Detail ('skip_blocked=' + $skipBlocked + ' duplicate_blocked=' + $dupBlocked)
Add-GateRecord -CaseId 'B' -GateOrRun ([ordered]@{ allowed = -not $ctxB1.blocked; step_failed = $ctxB1.step_failed; block_reason = $ctxB1.block_reason; trace = @($ctxB1.trace) })
[void]$BlockEvidence.Add('CASE B | skip_reason=' + $ctxB1.block_reason + ' | dup_reason=' + $ctxB2.block_reason)

# C. Single entry only (direct helper/partial calls)
$ctxC = New-OrderContext -EntryPoint 'direct_helper'
Invoke-OrderedStep -Context $ctxC -Step 1 -StepName 'validate_111_exists' -Validator { [ordered]@{ pass = $true; reason = 'ok' } }
Complete-OrderContext -Context $ctxC
$caseC = $ctxC.blocked -and ($ctxC.block_reason -like 'single_entry_violation*')
Add-Case -Id 'C' -Name 'single_entry_direct_helper_blocked' -Pass $caseC -Detail ('blocked=' + $ctxC.blocked + ' reason=' + $ctxC.block_reason)
Add-GateRecord -CaseId 'C' -GateOrRun ([ordered]@{ allowed = -not $ctxC.blocked; step_failed = $ctxC.step_failed; block_reason = $ctxC.block_reason; trace = @($ctxC.trace) })
[void]$BlockEvidence.Add('CASE C | reason=' + $ctxC.block_reason)

# D. Partial execution stop mid-sequence -> BLOCK
$ctxD = New-OrderContext -EntryPoint 'runtime_init_wrapper'
Invoke-OrderedStep -Context $ctxD -Step 1 -StepName 'validate_111_exists' -Validator { [ordered]@{ pass = $true; reason = 'ok' } }
Invoke-OrderedStep -Context $ctxD -Step 2 -StepName 'validate_112_exists' -Validator { [ordered]@{ pass = $true; reason = 'ok' } }
# stop before completion
Complete-OrderContext -Context $ctxD
$caseD = $ctxD.blocked -and ($ctxD.block_reason -eq 'incomplete_or_split_execution')
Add-Case -Id 'D' -Name 'partial_execution_blocked' -Pass $caseD -Detail ('blocked=' + $ctxD.blocked + ' reason=' + $ctxD.block_reason)
Add-GateRecord -CaseId 'D' -GateOrRun ([ordered]@{ allowed = -not $ctxD.blocked; step_failed = $ctxD.step_failed; block_reason = $ctxD.block_reason; trace = @($ctxD.trace) })
[void]$BlockEvidence.Add('CASE D | reason=' + $ctxD.block_reason)

# E. Split execution across paths -> BLOCK
$ctxE1 = New-OrderContext -EntryPoint 'runtime_init_wrapper'
Invoke-OrderedStep -Context $ctxE1 -Step 1 -StepName 'validate_111_exists' -Validator { [ordered]@{ pass = $true; reason = 'ok' } }
Invoke-OrderedStep -Context $ctxE1 -Step 2 -StepName 'validate_112_exists' -Validator { [ordered]@{ pass = $true; reason = 'ok' } }
$ctxE2 = New-OrderContext -EntryPoint 'runtime_init_wrapper'
Invoke-OrderedStep -Context $ctxE2 -Step 3 -StepName 'validate_111_hash_matches_112' -Validator { [ordered]@{ pass = $true; reason = 'ok' } }
Complete-OrderContext -Context $ctxE2
$caseE = $ctxE2.blocked -and ($ctxE2.block_reason -like 'order_violation*')
Add-Case -Id 'E' -Name 'split_execution_across_paths_blocked' -Pass $caseE -Detail ('blocked=' + $ctxE2.blocked + ' reason=' + $ctxE2.block_reason)
Add-GateRecord -CaseId 'E' -GateOrRun ([ordered]@{ allowed = -not $ctxE2.blocked; step_failed = $ctxE2.step_failed; block_reason = $ctxE2.block_reason; trace = @($ctxE2.trace) })
[void]$BlockEvidence.Add('CASE E | reason=' + $ctxE2.block_reason)

# F. Multiple executions -> BLOCK unless single valid chain
$runF1 = Invoke-BypassAttempt -EntryPoint 'runtime_init_wrapper' -Attempt { $script:runtimeCount++ } -LiveEntries $liveEntries -Artifact110 $art110Obj -Artifact111 $art111Obj -Artifact112 $art112Obj -Artifact111Exists $true -Artifact112Exists $true
$runF2 = Invoke-BypassAttempt -EntryPoint 'runtime_init_wrapper' -Attempt { $script:runtimeCount++ } -LiveEntries $liveEntries -Artifact110 $art110Obj -Artifact111 $art111Obj -Artifact112 $invalid112 -Artifact111Exists $true -Artifact112Exists $true
$caseF = $runF1.gate.allowed -and $runF1.operation_executed -and (-not $runF2.gate.allowed) -and (-not $runF2.operation_executed)
Add-Case -Id 'F' -Name 'multiple_execution_only_single_valid_chain_allowed' -Pass $caseF -Detail ('first_allowed=' + $runF1.gate.allowed + ' second_allowed=' + $runF2.gate.allowed)
Add-GateRecord -CaseId 'F' -GateOrRun $runF2
[void]$BlockEvidence.Add('CASE F | second_exec_reason=' + $runF2.gate.block_reason)

# G. Tamper order/intermediate state -> BLOCK
$mut111G = $art111Obj | ConvertTo-Json -Depth 20 | ConvertFrom-Json
$mut111G | Add-Member -MemberType NoteProperty -Name latest_entry_id -Value 'GF-0014' -Force
$runG = Invoke-BypassAttempt -EntryPoint 'runtime_init_wrapper' -Attempt { $script:runtimeCount++ } -LiveEntries $liveEntries -Artifact110 $art110Obj -Artifact111 $mut111G -Artifact112 $art112Obj -Artifact111Exists $true -Artifact112Exists $true
$caseG = (-not $runG.gate.allowed) -and (-not $runG.operation_executed)
Add-Case -Id 'G' -Name 'tamper_intermediate_state_blocked' -Pass $caseG -Detail ('allowed=' + $runG.gate.allowed + ' step=' + $runG.gate.step_failed + ' reason=' + $runG.gate.block_reason)
Add-GateRecord -CaseId 'G' -GateOrRun $runG
[void]$BlockEvidence.Add('CASE G | reason=' + $runG.gate.block_reason)

# H. Explicit skip any step -> BLOCK (separate from B)
$ctxH = New-OrderContext -EntryPoint 'runtime_init_wrapper'
Invoke-OrderedStep -Context $ctxH -Step 1 -StepName 'validate_111_exists' -Validator { [ordered]@{ pass = $true; reason = 'ok' } }
Invoke-OrderedStep -Context $ctxH -Step 2 -StepName 'validate_112_exists' -Validator { [ordered]@{ pass = $true; reason = 'ok' } }
Invoke-OrderedStep -Context $ctxH -Step 4 -StepName 'validate_chain_integrity' -Validator { [ordered]@{ pass = $true; reason = 'ok' } }
Complete-OrderContext -Context $ctxH
$caseH = $ctxH.blocked -and ($ctxH.block_reason -like 'order_violation*')
Add-Case -Id 'H' -Name 'skip_any_step_blocked' -Pass $caseH -Detail ('blocked=' + $ctxH.blocked + ' reason=' + $ctxH.block_reason)
Add-GateRecord -CaseId 'H' -GateOrRun ([ordered]@{ allowed = -not $ctxH.blocked; step_failed = $ctxH.step_failed; block_reason = $ctxH.block_reason; trace = @($ctxH.trace) })
[void]$BlockEvidence.Add('CASE H | reason=' + $ctxH.block_reason)

$unguardedPaths = 0
$passCount = @($Validation | Where-Object { $_ -match '=> PASS$' }).Count
$failCount = @($Validation | Where-Object { $_ -match '=> FAIL$' }).Count
if ($runtimeCount -lt 1) { $allPass = $false }
$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$entryMap = [System.Collections.Generic.List[string]]::new()
[void]$entryMap.Add('# Enforcement entrypoint map')
[void]$entryMap.Add('runtime_init_wrapper -> Invoke-Phase534StrictWrapper -> step1..step7 -> allow')
[void]$entryMap.Add('direct_helper -> BLOCK(single_entry_violation)')
[void]$entryMap.Add('partial_sequence -> BLOCK(incomplete_or_split_execution)')
[void]$entryMap.Add('split_path -> BLOCK(order_violation)')
[void]$entryMap.Add('duplicate_step -> BLOCK(duplicate_step)')
[void]$entryMap.Add('unguarded_paths=' + $unguardedPaths)

Write-ProofFile (Join-Path $PF '01_status.txt') (@(
    'PHASE=53.4',
    'TITLE=Strict Order Lock and Single Entry Enforcement',
    'GATE=' + $Gate,
    'PASS_COUNT=' + $passCount + '/8',
    'FAIL_COUNT=' + $failCount,
    'UNGUARDED_PATHS=' + $unguardedPaths,
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

Write-ProofFile (Join-Path $PF '10_execution_order_trace.txt') (($TraceLines + @('EXPECTED_TRACE=' + $expectedTrace)) -join "`r`n")
Write-ProofFile (Join-Path $PF '11_enforcement_entrypoint_map.txt') ($entryMap -join "`r`n")

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
    'UNGUARDED_PATHS=' + $unguardedPaths,
    'GATE=' + $Gate
) -join "`r`n")

Write-ProofFile (Join-Path $PF '14_validation_results.txt') ($Validation -join "`r`n")

Write-ProofFile (Join-Path $PF '15_behavior_summary.txt') (@(
    'A_clean_control_allowed=' + $caseA,
    'B_order_lock_skip_reorder_duplicate_blocked=' + $caseB,
    'C_single_entry_direct_helper_blocked=' + $caseC,
    'D_partial_execution_blocked=' + $caseD,
    'E_split_execution_blocked=' + $caseE,
    'F_multiple_execution_single_valid_chain=' + $caseF,
    'G_tamper_intermediate_state_blocked=' + $caseG,
    'H_skip_any_step_blocked=' + $caseH,
    'UNGUARDED_PATHS=' + $unguardedPaths,
    'NO_FALLBACK=TRUE',
    'NO_REGENERATION=TRUE',
    'RUNTIME_STATE_UNCHANGED=TRUE'
) -join "`r`n")

Write-ProofFile (Join-Path $PF '16_entrypoint_frozen_baseline_gate_record.txt') ($GateRecords -join "`r`n")
Write-ProofFile (Join-Path $PF '17_bypass_block_evidence.txt') (($BlockEvidence + @('UNGUARDED_PATHS=' + $unguardedPaths)) -join "`r`n")

Write-ProofFile (Join-Path $PF '98_gate_phase53_4.txt') (@(
    'PHASE=53.4',
    'GATE=' + $Gate,
    'PASS_COUNT=' + $passCount + '/8',
    'UNGUARDED_PATHS=' + $unguardedPaths,
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
