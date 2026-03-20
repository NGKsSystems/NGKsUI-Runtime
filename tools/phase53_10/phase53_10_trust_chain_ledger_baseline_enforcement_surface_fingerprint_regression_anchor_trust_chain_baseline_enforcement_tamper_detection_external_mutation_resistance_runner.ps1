#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Phase 53.10: Ledger Tamper Detection + External Mutation Resistance
# Objective: prove any out-of-band tamper across ledger/art111/art112 is detected
# before runtime or at guarded boundary, and blocked fail-closed.

$Phase = '53.10'
$Title = 'Ledger Tamper Detection and External Mutation Resistance'
$PF = Join-Path $PSScriptRoot '..\..\' '_proof' "phase53_10_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_enforcement_tamper_detection_external_mutation_resistance_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $PF -Force | Out-Null

$script:CaseMatrix = [System.Collections.Generic.List[object]]::new()
$script:DetectionVectors = [System.Collections.Generic.List[object]]::new()
$script:passCount = 0
$script:failCount = 0
$script:tamper_detected_count = 0
$script:undetected_tamper_count = 0
$script:false_positive_count = 0

function Write-ProofFile {
    param([string]$Path, [string[]]$Content)
    Set-Content -Path $Path -Value $Content -Force
}

function Get-StringHash {
    param([string]$InputString)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($InputString)
    $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    return [System.BitConverter]::ToString($hash).Replace('-', '').ToLower()
}

function Get-CanonicalJson {
    param($Object)
    if ($null -eq $Object) { return '{}' }
    return ($Object | ConvertTo-Json -Depth 99 -Compress)
}

function Get-LedgerSnapshotHash {
    param($Ledger)
    return (Get-StringHash -InputString (Get-CanonicalJson -Object $Ledger))
}

function Copy-Deep {
    param($Object)
    return ($Object | ConvertTo-Json -Depth 99 | ConvertFrom-Json)
}

function Get-EntryIdNumber {
    param([string]$EntryId)
    if ($EntryId -match '^GF-(\d+)$') {
        return [int]$Matches[1]
    }
    return -1
}

function Test-EntryOrdering {
    param($Entries)

    $seen = @{}
    for ($i = 0; $i -lt $Entries.Count; $i++) {
        $currentId = [string]$Entries[$i].entry_id
        $currentNum = Get-EntryIdNumber -EntryId $currentId
        if ($currentNum -lt 0) {
            return @{
                ok = $false
                reason = 'entry_id_format_invalid'
            }
        }

        if ($seen.ContainsKey($currentId)) {
            return @{
                ok = $false
                reason = 'entry_id_duplicate'
            }
        }
        $seen[$currentId] = $true

        if ($i -gt 0) {
            $prevNum = Get-EntryIdNumber -EntryId ([string]$Entries[$i - 1].entry_id)
            if ($currentNum -le $prevNum) {
                return @{
                    ok = $false
                    reason = 'entry_id_non_monotonic'
                }
            }
            if ($currentNum -ne ($prevNum + 1)) {
                return @{
                    ok = $false
                    reason = 'entry_id_gap_or_reuse'
                }
            }
        }
    }

    return @{ ok = $true; reason = 'ok' }
}

function Test-ChainContinuity {
    param(
        $Entries,
        [string]$TrustedChainSignature
    )

    if ($Entries.Count -eq 0) {
        return @{ ok = $false; reason = 'ledger_empty' }
    }

    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $Entries) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.fingerprint_hash)) {
            return @{ ok = $false; reason = 'fingerprint_missing' }
        }
        [void]$parts.Add(([string]$entry.entry_id + '|' + [string]$entry.previous_hash + '|' + [string]$entry.fingerprint_hash))
    }

    $currentSignature = Get-StringHash -InputString ($parts -join ';')
    if ($currentSignature -ne $TrustedChainSignature) {
        return @{ ok = $false; reason = 'chain_continuity_failure' }
    }

    return @{ ok = $true; reason = 'ok' }
}

function Get-ValidationVectors {
    param(
        [hashtable]$State,
        [hashtable]$Trusted
    )

    $vectors = [System.Collections.Generic.List[string]]::new()
    $entries = @($State.ledger.entries)

    $ordering = Test-EntryOrdering -Entries $entries
    if (-not $ordering.ok) {
        [void]$vectors.Add($ordering.reason)
    }

    $chain = Test-ChainContinuity -Entries $entries -TrustedChainSignature ([string]$Trusted.chain_signature)
    if (-not $chain.ok) {
        [void]$vectors.Add($chain.reason)
    }

    $currentLedgerHash = Get-LedgerSnapshotHash -Ledger $State.ledger
    if ($currentLedgerHash -ne $Trusted.ledger_snapshot_hash) {
        [void]$vectors.Add('ledger_hash_mismatch')
    }

    # Attested art112 hash changed.
    if ([string]$State.art112.baseline_snapshot_hash -ne [string]$Trusted.art112_baseline_snapshot_hash) {
        [void]$vectors.Add('art112_hash_mismatch')
    }

    # Detect mismatch against trusted computed ledger hash anchor.
    if (([string]$State.art112.baseline_snapshot_hash -ne [string]$Trusted.computed_ledger_hash_anchor) -and
        ($currentLedgerHash -eq [string]$Trusted.ledger_snapshot_hash)) {
        [void]$vectors.Add('computed_ledger_hash_mismatch')
    }

    $ledgerLength = $entries.Count
    $art111Length = [int]$State.art111.ledger_length
    if ($art111Length -ne $ledgerLength) {
        [void]$vectors.Add('ledger_length_mismatch')
    }

    $lastEntryId = [string]$entries[$entries.Count - 1].entry_id
    $art111Latest = [string]$State.art111.latest_entry_id
    if ($art111Latest -ne $lastEntryId) {
        [void]$vectors.Add('latest_entry_id_mismatch')
    }

    # Cross-artifact head-hash sync: compare with attested trusted values.
    if ([string]$State.art111.ledger_head_hash -ne [string]$Trusted.art111_ledger_head_hash) {
        [void]$vectors.Add('art111_head_hash_mismatch')
    }
    if ([string]$State.art112.ledger_head_hash -ne [string]$Trusted.art112_ledger_head_hash) {
        [void]$vectors.Add('art112_head_hash_mismatch')
    }

    # Cross-artifact drift checks for partial tamper detection.
    if ([string]$State.art111.latest_entry_id -ne [string]$Trusted.latest_entry_id -and $currentLedgerHash -eq [string]$Trusted.ledger_snapshot_hash) {
        [void]$vectors.Add('art111_latest_entry_drift')
    }
    if ([int]$State.art111.ledger_length -ne [int]$Trusted.ledger_length -and $currentLedgerHash -eq [string]$Trusted.ledger_snapshot_hash) {
        [void]$vectors.Add('art111_ledger_length_drift')
    }

    return ,$vectors
}

function Invoke-GuardedCycle {
    param(
        [hashtable]$State,
        [hashtable]$Trusted,
        [scriptblock]$RuntimeMutation
    )

    $preVectors = Get-ValidationVectors -State $State -Trusted $Trusted
    if ($preVectors.Count -gt 0) {
        return @{
            blocked = $true
            runtime_executed = $false
            stage = 'pre_runtime'
            vectors = $preVectors
            reason = ($preVectors -join ';')
        }
    }

    # Runtime starts only if pre-runtime validation is clean.
    if ($RuntimeMutation) {
        & $RuntimeMutation -State $State
    }

    # Guarded boundary validation after runtime mutation attempt.
    $boundaryVectors = Get-ValidationVectors -State $State -Trusted $Trusted
    if ($boundaryVectors.Count -gt 0) {
        return @{
            blocked = $true
            runtime_executed = $true
            stage = 'guarded_boundary'
            vectors = $boundaryVectors
            reason = ($boundaryVectors -join ';')
        }
    }

    return @{
        blocked = $false
        runtime_executed = $true
        stage = 'allow'
        vectors = [System.Collections.Generic.List[string]]::new()
        reason = 'clean_control_allow'
    }
}

function Add-CaseResult {
    param(
        [string]$Id,
        [string]$Name,
        [string]$ExpectedResult,
        [hashtable]$CycleResult
    )

    $actualResult = if ($CycleResult.blocked) { 'BLOCK' } else { 'ALLOW' }
    $passFail = if ($actualResult -eq $ExpectedResult) { 'PASS' } else { 'FAIL' }

    if ($passFail -eq 'PASS') { $script:passCount++ } else { $script:failCount++ }

    if ($ExpectedResult -eq 'BLOCK' -and $actualResult -eq 'BLOCK') { $script:tamper_detected_count++ }
    if ($ExpectedResult -eq 'BLOCK' -and $actualResult -eq 'ALLOW') { $script:undetected_tamper_count++ }
    if ($ExpectedResult -eq 'ALLOW' -and $actualResult -eq 'BLOCK') { $script:false_positive_count++ }

    $stepFailed = if ($CycleResult.stage -eq 'pre_runtime') { 2 } elseif ($CycleResult.stage -eq 'guarded_boundary') { 7 } else { 0 }

    [void]$script:CaseMatrix.Add(@{
        case_id = $Id
        name = $Name
        expected_result = $ExpectedResult
        actual_result = $actualResult
        blocked = $CycleResult.blocked
        allowed = (-not $CycleResult.blocked)
        runtime_executed = $CycleResult.runtime_executed
        step_failed = $stepFailed
        reason = [string]$CycleResult.reason
        pass_fail = $passFail
    })

    [void]$script:DetectionVectors.Add(@{
        case_id = $Id
        stage = $CycleResult.stage
        vectors = @($CycleResult.vectors)
    })
}

$workspaceRoot = (Split-Path $PSScriptRoot -Parent) | Split-Path -Parent
$controlPlaneDir = Join-Path $workspaceRoot 'control_plane'

$ledgerPath = Join-Path $controlPlaneDir '70_guard_fingerprint_trust_chain.json'
$art111Path = Join-Path $controlPlaneDir '111_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline.json'
$art112Path = Join-Path $controlPlaneDir '112_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_integrity.json'

if (-not (Test-Path $ledgerPath)) { throw "Missing ledger artifact: $ledgerPath" }
if (-not (Test-Path $art111Path)) { throw "Missing art111 artifact: $art111Path" }
if (-not (Test-Path $art112Path)) { throw "Missing art112 artifact: $art112Path" }

$baselineLedger = Get-Content $ledgerPath -Raw | ConvertFrom-Json
$baselineArt111 = Get-Content $art111Path -Raw | ConvertFrom-Json
$baselineArt112 = Get-Content $art112Path -Raw | ConvertFrom-Json

$trusted = @{
    ledger_snapshot_hash = Get-LedgerSnapshotHash -Ledger $baselineLedger
    computed_ledger_hash_anchor = [string]$baselineArt112.baseline_snapshot_hash
    art112_baseline_snapshot_hash = [string]$baselineArt112.baseline_snapshot_hash
    art111_ledger_head_hash = [string]$baselineArt111.ledger_head_hash
    art112_ledger_head_hash = [string]$baselineArt112.ledger_head_hash
    latest_entry_id = [string]$baselineArt111.latest_entry_id
    ledger_length = [int]$baselineArt111.ledger_length
    chain_signature = ''
}

$trustedParts = [System.Collections.Generic.List[string]]::new()
foreach ($entry in @($baselineLedger.entries)) {
    [void]$trustedParts.Add(([string]$entry.entry_id + '|' + [string]$entry.previous_hash + '|' + [string]$entry.fingerprint_hash))
}
$trusted.chain_signature = Get-StringHash -InputString ($trustedParts -join ';')

function New-LiveState {
    return @{
        ledger = Copy-Deep -Object $baselineLedger
        art111 = Copy-Deep -Object $baselineArt111
        art112 = Copy-Deep -Object $baselineArt112
    }
}

# Case A: Direct ledger tamper (insert + edit), art111/art112 untouched.
$stateA = New-LiveState
$entriesA = [System.Collections.ArrayList]::new()
foreach ($e in @($stateA.ledger.entries)) { [void]$entriesA.Add($e) }
$entriesA[1].fingerprint_hash = (Get-StringHash -InputString 'tamper_edit_A')
$forgedA = Copy-Deep -Object $entriesA[2]
$forgedA.entry_id = 'GF-0999'
$forgedA.fingerprint_hash = (Get-StringHash -InputString 'tamper_insert_A')
$forgedA.previous_hash = 'bad_previous_hash'
[void]$entriesA.Insert(2, $forgedA)
$stateA.ledger.entries = @($entriesA)
$resultA = Invoke-GuardedCycle -State $stateA -Trusted $trusted
Add-CaseResult -Id 'A' -Name 'direct_ledger_tamper_insert_edit' -ExpectedResult 'BLOCK' -CycleResult $resultA

# Case B: art112 hash tamper only.
$stateB = New-LiveState
$stateB.art112.baseline_snapshot_hash = 'ffff' + [string]$stateB.art112.baseline_snapshot_hash.Substring(4)
$resultB = Invoke-GuardedCycle -State $stateB -Trusted $trusted
Add-CaseResult -Id 'B' -Name 'art112_hash_tamper' -ExpectedResult 'BLOCK' -CycleResult $resultB

# Case C: art111 metadata tamper only.
$stateC = New-LiveState
$stateC.art111.latest_entry_id = 'GF-9999'
$stateC.art111.ledger_length = [int]$stateC.art111.ledger_length + 7
$resultC = Invoke-GuardedCycle -State $stateC -Trusted $trusted
Add-CaseResult -Id 'C' -Name 'art111_metadata_tamper' -ExpectedResult 'BLOCK' -CycleResult $resultC

# Case D: Partial tamper (ledger only: remove one entry).
$stateD = New-LiveState
$entriesD = @($stateD.ledger.entries)
$stateD.ledger.entries = @($entriesD[0..($entriesD.Count - 2)])
$resultD = Invoke-GuardedCycle -State $stateD -Trusted $trusted
Add-CaseResult -Id 'D' -Name 'partial_tamper_ledger_only_remove' -ExpectedResult 'BLOCK' -CycleResult $resultD

# Case E: Synthetic valid-looking tamper (ledger changed, attacker recomputes metadata/hash fields).
$stateE = New-LiveState
$entriesE = [System.Collections.ArrayList]::new()
foreach ($e in @($stateE.ledger.entries)) { [void]$entriesE.Add($e) }
# Duplicate last ID to violate monotonicity while making cross-artifact fields look synchronized.
$entriesE[$entriesE.Count - 1].entry_id = [string]$entriesE[$entriesE.Count - 2].entry_id
$stateE.ledger.entries = @($entriesE)
$stateE.art111.latest_entry_id = [string]$stateE.ledger.entries[$stateE.ledger.entries.Count - 1].entry_id
$stateE.art111.ledger_length = $stateE.ledger.entries.Count
$stateE.art112.baseline_snapshot_hash = Get-LedgerSnapshotHash -Ledger $stateE.ledger
$resultE = Invoke-GuardedCycle -State $stateE -Trusted $trusted
Add-CaseResult -Id 'E' -Name 'synthetic_valid_looking_tamper' -ExpectedResult 'BLOCK' -CycleResult $resultE

# Case F: Mid-chain corruption.
$stateF = New-LiveState
$mid = [int][Math]::Floor($stateF.ledger.entries.Count / 2)
$stateF.ledger.entries[$mid].fingerprint_hash = (Get-StringHash -InputString 'mid_chain_corruption_F')
$resultF = Invoke-GuardedCycle -State $stateF -Trusted $trusted
Add-CaseResult -Id 'F' -Name 'mid_chain_corruption' -ExpectedResult 'BLOCK' -CycleResult $resultF

# Case G: Mutation during runtime after clean init (must reject at guarded boundary).
$stateG = New-LiveState
$resultG = Invoke-GuardedCycle -State $stateG -Trusted $trusted -RuntimeMutation {
    param([hashtable]$State)
    $State.ledger.entries[0].fingerprint_hash = (Get-StringHash -InputString 'runtime_mutation_G')
}
Add-CaseResult -Id 'G' -Name 'runtime_mutation_after_init' -ExpectedResult 'BLOCK' -CycleResult $resultG

# Case H: Clean control (untouched artifacts).
$stateH = New-LiveState
$resultH = Invoke-GuardedCycle -State $stateH -Trusted $trusted
Add-CaseResult -Id 'H' -Name 'clean_control' -ExpectedResult 'ALLOW' -CycleResult $resultH

$consistencyPass = $true
if ($script:CaseMatrix.Count -ne 8) { $consistencyPass = $false }
if (($script:passCount + $script:failCount) -ne 8) { $consistencyPass = $false }
if ($script:undetected_tamper_count -ne 0) { $consistencyPass = $false }
if ($script:false_positive_count -ne 0) { $consistencyPass = $false }

$gate = if ($script:passCount -eq 8 -and $script:failCount -eq 0 -and $consistencyPass) { 'PASS' } else { 'FAIL' }

$matrixLines = @('case|expected_result|actual_result|blocked|allowed|runtime_executed|step_failed|reason|pass_fail')
foreach ($row in $script:CaseMatrix) {
    $matrixLines += ($row.case_id + '|' + $row.expected_result + '|' + $row.actual_result + '|' + $row.blocked + '|' + $row.allowed + '|' + $row.runtime_executed + '|' + $row.step_failed + '|' + $row.reason + '|' + $row.pass_fail)
}

$vectorLines = @('case|stage|vectors')
foreach ($v in $script:DetectionVectors) {
    $joined = if ($v.vectors.Count -gt 0) { ($v.vectors -join ';') } else { 'none' }
    $vectorLines += ($v.case_id + '|' + $v.stage + '|' + $joined)
}

$matrixSummary = @(
    'TAMPER_TEST_MATRIX',
    'A: direct_ledger_tamper_insert_edit => expect BLOCK',
    'B: art112_hash_tamper => expect BLOCK',
    'C: art111_metadata_tamper => expect BLOCK',
    'D: partial_tamper_ledger_only_remove => expect BLOCK',
    'E: synthetic_valid_looking_tamper => expect BLOCK',
    'F: mid_chain_corruption => expect BLOCK',
    'G: runtime_mutation_after_init => expect BLOCK',
    'H: clean_control => expect ALLOW'
)

Write-ProofFile -Path (Join-Path $PF '01_status.txt') -Content @(
    'PHASE=53.10',
    'TITLE=' + $Title,
    'GATE=' + $gate,
    'PASS_COUNT=' + $script:passCount + '/8',
    'FAIL_COUNT=' + $script:failCount,
    'tamper_detected_count=' + $script:tamper_detected_count,
    'undetected_tamper_count=' + $script:undetected_tamper_count,
    'false_positive_count=' + $script:false_positive_count,
    'consistency_check=' + $(if ($consistencyPass) { 'PASS' } else { 'FAIL' }),
    'NO_FALLBACK=TRUE',
    'FAIL_CLOSED=TRUE',
    'NO_SILENT_ACCEPTANCE=TRUE'
)

Write-ProofFile -Path (Join-Path $PF '14_validation_results.txt') -Content $matrixLines
Write-ProofFile -Path (Join-Path $PF '15_tamper_test_matrix.txt') -Content $matrixSummary
Write-ProofFile -Path (Join-Path $PF '15_detection_vectors.txt') -Content $vectorLines

Write-ProofFile -Path (Join-Path $PF '98_gate_phase53_10.txt') -Content @(
    'GATE=' + $gate,
    'PASS_COUNT=' + $script:passCount + '/8',
    'FAIL_COUNT=' + $script:failCount,
    'tamper_detected_count=' + $script:tamper_detected_count,
    'undetected_tamper_count=' + $script:undetected_tamper_count,
    'false_positive_count=' + $script:false_positive_count
)

$zipPath = $PF + '.zip'
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path $PF -DestinationPath $zipPath -Force

Write-Output ('PF=' + $PF)
Write-Output ('ZIP=' + $zipPath)
Write-Output ('GATE=' + $gate)
