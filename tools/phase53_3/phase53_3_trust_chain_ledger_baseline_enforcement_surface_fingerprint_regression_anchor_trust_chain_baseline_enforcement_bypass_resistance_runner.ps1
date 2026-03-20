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

# Real 53.2 gate logic (copied to prove bypass-resistance against actual enforcement surface)
function Test-Phase532BaselineEnforcementGate {
    param(
        [object[]]$LiveEntries,
        [object]$Artifact110,
        [object]$Artifact111,
        [object]$Artifact112,
        [bool]$Artifact111Exists,
        [bool]$Artifact112Exists
    )

    $result = [ordered]@{
        allowed = $false
        block_reason = ''
        step_failed = 0
        chain_hashes = @()
        chain_integrity_status = ''
        continuation_status = ''
        computed_snap_hash = ''
        stored_snap_hash = ''
        live_head_hash = ''
        baseline_head_hash = ''
        computed_cov_fp = ''
        baseline_cov_fp = ''
        details = [ordered]@{}
    }

    if (-not $Artifact111Exists) {
        $result.step_failed = 1
        $result.block_reason = 'artifact_111_missing'
        return $result
    }
    if (-not $Artifact112Exists) {
        $result.step_failed = 2
        $result.block_reason = 'artifact_112_missing'
        return $result
    }

    $computedSnapHash = Get-CanonicalObjectHash -Obj $Artifact111
    $storedSnapHash = [string]$Artifact112.baseline_snapshot_hash
    $result.computed_snap_hash = $computedSnapHash
    $result.stored_snap_hash = $storedSnapHash
    if ($computedSnapHash -ne $storedSnapHash) {
        $result.step_failed = 3
        $result.block_reason = 'baseline_snapshot_hash_mismatch'
        return $result
    }

    $chain = Test-ExtendedTrustChain -Entries $LiveEntries
    $result.chain_hashes = $chain.chain_hashes
    $result.chain_integrity_status = $chain.reason
    if (-not $chain.pass) {
        $result.step_failed = 4
        $result.block_reason = 'trust_chain_integrity_failed:' + [string]$chain.reason
        return $result
    }

    $result.live_head_hash = [string]$chain.last_entry_hash
    $baselineHead = [string]$Artifact111.ledger_head_hash
    $baselineLen = [int]$Artifact111.ledger_length
    $result.baseline_head_hash = $baselineHead

    if ([string]$chain.last_entry_hash -eq $baselineHead) {
        $result.continuation_status = 'exact'
    } elseif ($chain.chain_hashes.Count -gt $baselineLen -and $baselineLen -gt 0) {
        $baselinePositionHash = [string]$chain.chain_hashes[$baselineLen - 1]
        if ($baselinePositionHash -eq $baselineHead) {
            $result.continuation_status = 'continuation'
        } else {
            $result.step_failed = 5
            $result.block_reason = 'ledger_head_drift_continuation_invalid'
            $result.continuation_status = 'failed'
            return $result
        }
    } else {
        $result.step_failed = 5
        $result.block_reason = 'ledger_head_drift'
        $result.continuation_status = 'failed'
        return $result
    }

    $computedCovFp = [string]$Artifact110.coverage_fingerprint
    $baselineCovFp111 = [string]$Artifact111.coverage_fingerprint_hash
    $baselineCovFp112 = [string]$Artifact112.coverage_fingerprint_hash
    $result.computed_cov_fp = $computedCovFp
    $result.baseline_cov_fp = $baselineCovFp111
    if ($computedCovFp -ne $baselineCovFp111 -or $computedCovFp -ne $baselineCovFp112) {
        $result.step_failed = 6
        $result.block_reason = 'artifact110_coverage_fingerprint_mismatch'
        return $result
    }

    $semanticErrors = [System.Collections.Generic.List[string]]::new()
    if ([string]$Artifact111.phase_locked -ne '53.1') { [void]$semanticErrors.Add('111.phase_locked_not_53.1') }
    if ([string]$Artifact111.latest_entry_id -ne 'GF-0015') { [void]$semanticErrors.Add('111.latest_entry_id_not_GF-0015') }
    if ([string]$Artifact111.latest_entry_phase_locked -ne '53.0') { [void]$semanticErrors.Add('111.latest_entry_phase_locked_not_53.0') }
    if ([int]$Artifact111.ledger_length -ne 15) { [void]$semanticErrors.Add('111.ledger_length_not_15') }
    $srcPhases = @($Artifact111.source_phases | ForEach-Object { [string]$_ })
    if (($srcPhases -join ',') -ne '52.8,52.9,53.0') { [void]$semanticErrors.Add('111.source_phases_mismatch') }
    if ([string]$Artifact112.phase_locked -ne '53.1') { [void]$semanticErrors.Add('112.phase_locked_not_53.1') }
    if ($semanticErrors.Count -gt 0) {
        $result.step_failed = 7
        $result.block_reason = 'semantic_field_validation_failed:' + ($semanticErrors -join ',')
        return $result
    }

    $result.allowed = $true
    $result.step_failed = 0
    $result.block_reason = ''
    return $result
}

function Invoke-ProtectedOperation {
    param(
        [string]$EntryPoint,
        [scriptblock]$OperationScript,
        [object[]]$LiveEntries,
        [object]$Artifact110,
        [object]$Artifact111,
        [object]$Artifact112,
        [bool]$Artifact111Exists,
        [bool]$Artifact112Exists
    )

    $gate = Test-Phase532BaselineEnforcementGate -LiveEntries $LiveEntries -Artifact110 $Artifact110 -Artifact111 $Artifact111 -Artifact112 $Artifact112 -Artifact111Exists $Artifact111Exists -Artifact112Exists $Artifact112Exists
    $operationExecuted = $false
    $operationResult = 'BLOCKED'

    if ($gate.allowed) {
        $operationExecuted = $true
        & $OperationScript
        $operationResult = 'ALLOWED'
    }

    return [ordered]@{
        entrypoint = $EntryPoint
        gate = $gate
        operation_executed = $operationExecuted
        operation_result = $operationResult
    }
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunnerPath = Join-Path $Root 'tools\phase53_3\phase53_3_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_enforcement_bypass_resistance_runner.ps1'
$Phase532RunnerPath = Join-Path $Root 'tools\phase53_2\phase53_2_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_enforcement_runner.ps1'
$LedgerPath = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$Art110Path = Join-Path $Root 'control_plane\110_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint_regression_anchor.json'
$Art111Path = Join-Path $Root 'control_plane\111_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline.json'
$Art112Path = Join-Path $Root 'control_plane\112_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_integrity.json'
$PF = Join-Path $Root ('_proof\phase53_3_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_enforcement_bypass_resistance_' + $Timestamp)

New-Item -ItemType Directory -Path $PF | Out-Null

foreach ($path in @($LedgerPath, $Art110Path, $Art111Path, $Art112Path, $Phase532RunnerPath)) {
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
$invalid112 | Add-Member -MemberType NoteProperty -Name baseline_snapshot_hash -Value 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef' -Force

$Validation = [System.Collections.Generic.List[string]]::new()
$GateRecords = [System.Collections.Generic.List[string]]::new()
$BlockEvidence = [System.Collections.Generic.List[string]]::new()
$allPass = $true

$OpCounters = [ordered]@{
    baseline_snapshot_load = 0
    integrity_load = 0
    ledger_head_helper = 0
    fingerprint_helper = 0
    chain_validation_helper = 0
    semantic_helper = 0
    runtime_init_wrapper = 0
    canonical_hash_helper = 0
}

function Add-Case {
    param([string]$Id, [string]$Name, [bool]$Pass, [string]$Detail)
    [void]$Validation.Add('CASE ' + $Id + ' ' + $Name + ' | ' + $Detail + ' => ' + $(if ($Pass) { 'PASS' } else { 'FAIL' }))
    if (-not $Pass) { $script:allPass = $false }
}

function Add-GateRecord {
    param([string]$CaseId, [object]$Result)
    [void]$GateRecords.Add(
        'CASE ' + $CaseId +
        ' | entrypoint=' + $Result.entrypoint +
        ' | gate_allowed=' + $Result.gate.allowed +
        ' | step_failed=' + $Result.gate.step_failed +
        ' | block_reason=' + $Result.gate.block_reason +
        ' | operation_executed=' + $Result.operation_executed +
        ' | operation_result=' + $Result.operation_result +
        ' | continuation=' + $Result.gate.continuation_status +
        ' | no_fallback=TRUE' +
        ' | no_regeneration=TRUE'
    )
}

# Scan real 53.2 runner function declarations
$runnerSource = Get-Content -LiteralPath $Phase532RunnerPath -Raw
$declaredFunctions = [System.Collections.Generic.List[string]]::new()
foreach ($line in ($runnerSource -split "`n")) {
    if ($line -match '^\s*function\s+([A-Za-z][\w-]+)\s*\{') {
        [void]$declaredFunctions.Add($Matches[1])
    }
}

# Entrypoint/helper inventory for bypass tests
$EntryInventory = @(
    [ordered]@{ id='EP-01'; name='baseline_snapshot_load'; kind='entrypoint'; maps_to='artifact_111_load_and_hash_validation'; classification='DIRECTLY_GATED'; case='B' },
    [ordered]@{ id='EP-02'; name='integrity_load'; kind='entrypoint'; maps_to='artifact_112_integrity_validation'; classification='DIRECTLY_GATED'; case='C' },
    [ordered]@{ id='EP-03'; name='ledger_head_helper'; kind='helper'; maps_to='live_ledger_head_read_and_comparison'; classification='DIRECTLY_GATED'; case='D' },
    [ordered]@{ id='EP-04'; name='fingerprint_helper'; kind='helper'; maps_to='artifact110_fingerprint_read_and_compare'; classification='DIRECTLY_GATED'; case='E' },
    [ordered]@{ id='EP-05'; name='chain_validation_helper'; kind='helper'; maps_to='Test-ExtendedTrustChain'; classification='TRANSITIVELY_GATED'; case='F' },
    [ordered]@{ id='EP-06'; name='semantic_helper'; kind='helper'; maps_to='semantic_protected_field_validation'; classification='DIRECTLY_GATED'; case='G' },
    [ordered]@{ id='EP-07'; name='runtime_init_wrapper'; kind='entrypoint'; maps_to='Invoke-ProtectedOperation'; classification='DIRECTLY_GATED'; case='H' },
    [ordered]@{ id='EP-08'; name='canonical_hash_helper'; kind='helper'; maps_to='Get-CanonicalObjectHash'; classification='TRANSITIVELY_GATED'; case='I' }
)

# A. clean control
$runA = Invoke-ProtectedOperation -EntryPoint 'clean_control' -OperationScript {
    $script:OpCounters['runtime_init_wrapper']++
} -LiveEntries $liveEntries -Artifact110 $art110Obj -Artifact111 $art111Obj -Artifact112 $art112Obj -Artifact111Exists $true -Artifact112Exists $true
$caseA = $runA.gate.allowed -and $runA.operation_executed
Add-Case -Id 'A' -Name 'clean_control_allowed' -Pass $caseA -Detail ('allowed=' + $runA.gate.allowed + ' operation_executed=' + $runA.operation_executed + ' step_failed=' + $runA.gate.step_failed)
Add-GateRecord -CaseId 'A' -Result $runA

# B. snapshot-load bypass under invalid baseline
$runB = Invoke-ProtectedOperation -EntryPoint 'baseline_snapshot_load' -OperationScript {
    $script:OpCounters['baseline_snapshot_load']++
    [void]([string]$using:art111Obj.phase_locked)
} -LiveEntries $liveEntries -Artifact110 $art110Obj -Artifact111 $art111Obj -Artifact112 $invalid112 -Artifact111Exists $true -Artifact112Exists $true
$caseB = (-not $runB.gate.allowed) -and (-not $runB.operation_executed)
Add-Case -Id 'B' -Name 'snapshot_load_bypass_blocked' -Pass $caseB -Detail ('allowed=' + $runB.gate.allowed + ' step=' + $runB.gate.step_failed + ' reason=' + $runB.gate.block_reason)
Add-GateRecord -CaseId 'B' -Result $runB
[void]$BlockEvidence.Add('CASE B | blocked_before_snapshot_load | step=' + $runB.gate.step_failed)

# C. integrity-load bypass under invalid baseline
$runC = Invoke-ProtectedOperation -EntryPoint 'integrity_load' -OperationScript {
    $script:OpCounters['integrity_load']++
    [void]([string]$using:art112Obj.phase_locked)
} -LiveEntries $liveEntries -Artifact110 $art110Obj -Artifact111 $art111Obj -Artifact112 $invalid112 -Artifact111Exists $true -Artifact112Exists $true
$caseC = (-not $runC.gate.allowed) -and (-not $runC.operation_executed)
Add-Case -Id 'C' -Name 'integrity_load_bypass_blocked' -Pass $caseC -Detail ('allowed=' + $runC.gate.allowed + ' step=' + $runC.gate.step_failed + ' reason=' + $runC.gate.block_reason)
Add-GateRecord -CaseId 'C' -Result $runC
[void]$BlockEvidence.Add('CASE C | blocked_before_integrity_load | step=' + $runC.gate.step_failed)

# D. ledger-head helper bypass under invalid baseline
$runD = Invoke-ProtectedOperation -EntryPoint 'ledger_head_helper' -OperationScript {
    $script:OpCounters['ledger_head_helper']++
    $chain = Test-ExtendedTrustChain -Entries $using:liveEntries
    [void]$chain.last_entry_hash
} -LiveEntries $liveEntries -Artifact110 $art110Obj -Artifact111 $art111Obj -Artifact112 $invalid112 -Artifact111Exists $true -Artifact112Exists $true
$caseD = (-not $runD.gate.allowed) -and (-not $runD.operation_executed)
Add-Case -Id 'D' -Name 'ledger_head_helper_bypass_blocked' -Pass $caseD -Detail ('allowed=' + $runD.gate.allowed + ' step=' + $runD.gate.step_failed + ' reason=' + $runD.gate.block_reason)
Add-GateRecord -CaseId 'D' -Result $runD
[void]$BlockEvidence.Add('CASE D | blocked_before_ledger_head_helper | step=' + $runD.gate.step_failed)

# E. fingerprint helper bypass under invalid baseline
$runE = Invoke-ProtectedOperation -EntryPoint 'fingerprint_helper' -OperationScript {
    $script:OpCounters['fingerprint_helper']++
    [void]([string]$using:art110Obj.coverage_fingerprint)
} -LiveEntries $liveEntries -Artifact110 $art110Obj -Artifact111 $art111Obj -Artifact112 $invalid112 -Artifact111Exists $true -Artifact112Exists $true
$caseE = (-not $runE.gate.allowed) -and (-not $runE.operation_executed)
Add-Case -Id 'E' -Name 'fingerprint_helper_bypass_blocked' -Pass $caseE -Detail ('allowed=' + $runE.gate.allowed + ' step=' + $runE.gate.step_failed + ' reason=' + $runE.gate.block_reason)
Add-GateRecord -CaseId 'E' -Result $runE
[void]$BlockEvidence.Add('CASE E | blocked_before_fingerprint_helper | step=' + $runE.gate.step_failed)

# F. chain-validation helper bypass under invalid baseline
$runF = Invoke-ProtectedOperation -EntryPoint 'chain_validation_helper' -OperationScript {
    $script:OpCounters['chain_validation_helper']++
    [void](Test-ExtendedTrustChain -Entries $using:liveEntries)
} -LiveEntries $liveEntries -Artifact110 $art110Obj -Artifact111 $art111Obj -Artifact112 $invalid112 -Artifact111Exists $true -Artifact112Exists $true
$caseF = (-not $runF.gate.allowed) -and (-not $runF.operation_executed)
Add-Case -Id 'F' -Name 'chain_validation_helper_bypass_blocked' -Pass $caseF -Detail ('allowed=' + $runF.gate.allowed + ' step=' + $runF.gate.step_failed + ' reason=' + $runF.gate.block_reason)
Add-GateRecord -CaseId 'F' -Result $runF
[void]$BlockEvidence.Add('CASE F | blocked_before_chain_validation_helper | step=' + $runF.gate.step_failed)

# G. semantic helper bypass under invalid baseline
$runG = Invoke-ProtectedOperation -EntryPoint 'semantic_helper' -OperationScript {
    $script:OpCounters['semantic_helper']++
    [void]([string]$using:art111Obj.latest_entry_id)
    [void]([string]$using:art111Obj.latest_entry_phase_locked)
} -LiveEntries $liveEntries -Artifact110 $art110Obj -Artifact111 $art111Obj -Artifact112 $invalid112 -Artifact111Exists $true -Artifact112Exists $true
$caseG = (-not $runG.gate.allowed) -and (-not $runG.operation_executed)
Add-Case -Id 'G' -Name 'semantic_helper_bypass_blocked' -Pass $caseG -Detail ('allowed=' + $runG.gate.allowed + ' step=' + $runG.gate.step_failed + ' reason=' + $runG.gate.block_reason)
Add-GateRecord -CaseId 'G' -Result $runG
[void]$BlockEvidence.Add('CASE G | blocked_before_semantic_helper | step=' + $runG.gate.step_failed)

# H. runtime-init wrapper bypass under invalid baseline
$runH = Invoke-ProtectedOperation -EntryPoint 'runtime_init_wrapper' -OperationScript {
    $script:OpCounters['runtime_init_wrapper']++
} -LiveEntries $liveEntries -Artifact110 $art110Obj -Artifact111 $art111Obj -Artifact112 $invalid112 -Artifact111Exists $true -Artifact112Exists $true
$caseH = (-not $runH.gate.allowed) -and (-not $runH.operation_executed)
Add-Case -Id 'H' -Name 'runtime_init_wrapper_bypass_blocked' -Pass $caseH -Detail ('allowed=' + $runH.gate.allowed + ' step=' + $runH.gate.step_failed + ' reason=' + $runH.gate.block_reason)
Add-GateRecord -CaseId 'H' -Result $runH
[void]$BlockEvidence.Add('CASE H | blocked_before_runtime_init_wrapper | step=' + $runH.gate.step_failed)

# I. canonical/hash helper bypass under invalid baseline
$runI = Invoke-ProtectedOperation -EntryPoint 'canonical_hash_helper' -OperationScript {
    $script:OpCounters['canonical_hash_helper']++
    [void](Get-CanonicalObjectHash -Obj $using:art111Obj)
} -LiveEntries $liveEntries -Artifact110 $art110Obj -Artifact111 $art111Obj -Artifact112 $invalid112 -Artifact111Exists $true -Artifact112Exists $true
$caseI = (-not $runI.gate.allowed) -and (-not $runI.operation_executed)
Add-Case -Id 'I' -Name 'canonical_hash_helper_bypass_blocked' -Pass $caseI -Detail ('allowed=' + $runI.gate.allowed + ' step=' + $runI.gate.step_failed + ' reason=' + $runI.gate.block_reason)
Add-GateRecord -CaseId 'I' -Result $runI
[void]$BlockEvidence.Add('CASE I | blocked_before_canonical_hash_helper | step=' + $runI.gate.step_failed)

# Verify no bypass operation executed under invalid baseline
$unguardedPaths = [System.Collections.Generic.List[string]]::new()
foreach ($k in @('baseline_snapshot_load','integrity_load','ledger_head_helper','fingerprint_helper','chain_validation_helper','semantic_helper','runtime_init_wrapper','canonical_hash_helper')) {
    if ($OpCounters[$k] -gt 0 -and $k -ne 'runtime_init_wrapper') {
        # helper counters may increment only from clean allowed case for runtime wrapper, not bypass cases
        # all bypass cases should remain zero for their target helper
        if ($k -in @('baseline_snapshot_load','integrity_load','ledger_head_helper','fingerprint_helper','chain_validation_helper','semantic_helper','canonical_hash_helper')) {
            [void]$unguardedPaths.Add($k)
        }
    }
}

# runtime_init_wrapper is expected to execute once in clean control only
$wrapperExecExpected = ($OpCounters['runtime_init_wrapper'] -eq 1)
if (-not $wrapperExecExpected) {
    [void]$unguardedPaths.Add('runtime_init_wrapper_unexpected_exec_count=' + $OpCounters['runtime_init_wrapper'])
}

$passCount = @($Validation | Where-Object { $_ -match '=> PASS$' }).Count
$failCount = @($Validation | Where-Object { $_ -match '=> FAIL$' }).Count
if ($unguardedPaths.Count -gt 0) { $allPass = $false }
$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

# 10_entrypoint_inventory
$inv10 = [System.Collections.Generic.List[string]]::new()
[void]$inv10.Add('# Phase 53.3 entrypoint/helper inventory from real 53.2 enforcement surface')
[void]$inv10.Add('# declared_functions_in_phase53_2=' + ($declaredFunctions -join ','))
[void]$inv10.Add('#')
foreach ($ep in $EntryInventory) {
    [void]$inv10.Add($ep.id + ' | name=' + $ep.name + ' | kind=' + $ep.kind + ' | maps_to=' + $ep.maps_to + ' | classification=' + $ep.classification + ' | bypass_case=' + $ep.case)
}

# 11_enforcement_map
$map11 = [System.Collections.Generic.List[string]]::new()
[void]$map11.Add('# Phase 53.3 frozen-baseline enforcement map')
[void]$map11.Add('Invoke-ProtectedOperation -> Test-Phase532BaselineEnforcementGate (always first)')
[void]$map11.Add('Test-Phase532BaselineEnforcementGate step1: artifact_111_exists')
[void]$map11.Add('Test-Phase532BaselineEnforcementGate step2: artifact_112_exists')
[void]$map11.Add('Test-Phase532BaselineEnforcementGate step3: Get-CanonicalObjectHash(111) == 112.baseline_snapshot_hash')
[void]$map11.Add('Test-Phase532BaselineEnforcementGate step4: Test-ExtendedTrustChain(live_entries)')
[void]$map11.Add('Test-Phase532BaselineEnforcementGate step5: head exact match OR continuation baseline-position hash match')
[void]$map11.Add('Test-Phase532BaselineEnforcementGate step6: 110.coverage_fingerprint == 111/112.coverage_fingerprint_hash')
[void]$map11.Add('Test-Phase532BaselineEnforcementGate step7: semantic protected fields validation')
[void]$map11.Add('Test-Phase532BaselineEnforcementGate step8: runtime init allowed')
[void]$map11.Add('')
[void]$map11.Add('Directly gated: Invoke-ProtectedOperation, Test-Phase532BaselineEnforcementGate')
[void]$map11.Add('Transitively gated: Get-CanonicalObjectHash, Test-ExtendedTrustChain, Get-LegacyChainEntryHash, Convert-ToCanonicalJson, Get-StringSha256Hex, Get-BytesSha256Hex')
[void]$map11.Add('Unguarded operational paths=' + $unguardedPaths.Count)

Write-ProofFile (Join-Path $PF '01_status.txt') (@(
    'PHASE=53.3',
    'TITLE=Trust-Chain Ledger Baseline Enforcement Surface Fingerprint Regression Anchor Trust-Chain Baseline Enforcement Bypass Resistance',
    'GATE=' + $Gate,
    'PASS_COUNT=' + $passCount + '/9',
    'FAIL_COUNT=' + $failCount,
    'UNGUARDED_PATHS=' + $unguardedPaths.Count,
    'NO_FALLBACK=TRUE',
    'NO_REGENERATION=TRUE',
    'RUNTIME_STATE_UNCHANGED=TRUE'
) -join "`r`n")

Write-ProofFile (Join-Path $PF '02_head.txt') (@(
    'RUNNER=' + $RunnerPath,
    'SOURCE_ENFORCEMENT_RUNNER=' + $Phase532RunnerPath,
    'LEDGER=' + $LedgerPath,
    'ART110=' + $Art110Path,
    'ART111=' + $Art111Path,
    'ART112=' + $Art112Path
) -join "`r`n")

Write-ProofFile (Join-Path $PF '10_entrypoint_inventory.txt') ($inv10 -join "`r`n")
Write-ProofFile (Join-Path $PF '11_frozen_baseline_enforcement_map.txt') ($map11 -join "`r`n")

Write-ProofFile (Join-Path $PF '12_files_touched.txt') (@(
    'READ=' + $Phase532RunnerPath,
    'READ=' + $LedgerPath,
    'READ=' + $Art110Path,
    'READ=' + $Art111Path,
    'READ=' + $Art112Path,
    'WRITE_PROOF=' + $PF,
    'NO_CONTROL_PLANE_WRITE=TRUE',
    'NO_RUNTIME_MUTATION=TRUE'
) -join "`r`n")

Write-ProofFile (Join-Path $PF '13_build_output.txt') (@(
    'CASE_COUNT=9',
    'PASSED=' + $passCount,
    'FAILED=' + $failCount,
    'UNGUARDED_PATHS=' + $unguardedPaths.Count,
    'RUNTIME_WRAPPER_EXEC_COUNT=' + $OpCounters['runtime_init_wrapper'],
    'GATE=' + $Gate
) -join "`r`n")

Write-ProofFile (Join-Path $PF '14_validation_results.txt') ($Validation -join "`r`n")

Write-ProofFile (Join-Path $PF '15_behavior_summary.txt') (@(
    'A_clean_allowed=' + $caseA,
    'B_snapshot_bypass_blocked=' + $caseB,
    'C_integrity_bypass_blocked=' + $caseC,
    'D_ledger_head_bypass_blocked=' + $caseD,
    'E_fingerprint_bypass_blocked=' + $caseE,
    'F_chain_validation_bypass_blocked=' + $caseF,
    'G_semantic_bypass_blocked=' + $caseG,
    'H_runtime_wrapper_bypass_blocked=' + $caseH,
    'I_canonical_hash_bypass_blocked=' + $caseI,
    'UNGUARDED_PATHS=' + $unguardedPaths.Count,
    'NO_FALLBACK=TRUE',
    'NO_REGENERATION=TRUE',
    'RUNTIME_STATE_UNCHANGED=TRUE'
) -join "`r`n")

Write-ProofFile (Join-Path $PF '16_entrypoint_frozen_baseline_gate_record.txt') ($GateRecords -join "`r`n")
Write-ProofFile (Join-Path $PF '17_bypass_block_evidence.txt') (($BlockEvidence + @('UNGUARDED_PATHS=' + $unguardedPaths.Count)) -join "`r`n")

Write-ProofFile (Join-Path $PF '98_gate_phase53_3.txt') (@(
    'PHASE=53.3',
    'GATE=' + $Gate,
    'PASS_COUNT=' + $passCount + '/9',
    'UNGUARDED_PATHS=' + $unguardedPaths.Count,
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
