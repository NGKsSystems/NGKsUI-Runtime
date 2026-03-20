#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Phase 53.14: Trust-Anchor Compromise Resistance + Unauthorized Anchor Rotation Rejection

$Phase = '53.14'
$Title = 'Trust-Anchor Compromise Resistance and Unauthorized Anchor Rotation Rejection'
$PF = Join-Path $PSScriptRoot '..\..\' '_proof' "phase53_14_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_enforcement_trust_anchor_compromise_resistance_unauthorized_anchor_rotation_rejection_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $PF -Force | Out-Null

$script:CaseMatrix = [System.Collections.Generic.List[object]]::new()
$script:DetectionVectors = [System.Collections.Generic.List[object]]::new()
$script:TrustAnchorLineageMap = [System.Collections.Generic.List[string]]::new()

$script:passCount = 0
$script:failCount = 0
$script:unauthorized_anchor_rejected_count = 0
$script:unauthorized_rotation_rejected_count = 0
$script:undetected_anchor_compromise_count = 0
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

function Build-ChainSignature {
    param($Entries)
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in @($Entries)) {
        [void]$parts.Add(([string]$entry.entry_id + '|' + [string]$entry.previous_hash + '|' + [string]$entry.fingerprint_hash))
    }
    return (Get-StringHash -InputString ($parts -join ';'))
}

function Build-Anchor {
    param(
        [hashtable]$Trusted,
        [int]$RotationCounter,
        [string]$AuthorizedBy,
        [string]$ProofSeed
    )

    $continuity = Get-StringHash -InputString ($Trusted.current_chain_signature + '|' + $Trusted.current_ledger_snapshot_hash)
    $anchorCore = ($Trusted.current_ledger_snapshot_hash + '|' + $Trusted.current_chain_signature + '|' + $Trusted.current_art111_head_hash_anchor + '|' + $Trusted.current_art112_head_hash_anchor + '|' + $RotationCounter)
    $anchorId = Get-StringHash -InputString $anchorCore
    $authProof = Get-StringHash -InputString ($anchorId + '|' + $AuthorizedBy + '|' + $ProofSeed)

    return @{
        anchor_id = $anchorId
        rotation_counter = $RotationCounter
        authorized_by = $AuthorizedBy
        authorization_proof = $authProof
        chain_continuity_hash = $continuity
    }
}

function Get-ValidationVectors {
    param(
        [hashtable]$State,
        [hashtable]$Trusted
    )

    $vectors = [System.Collections.Generic.List[string]]::new()
    $entries = @($State.ledger.entries)
    if ($entries.Count -eq 0) {
        [void]$vectors.Add('ledger_empty')
        return ,$vectors
    }

    $ledgerLen = $entries.Count
    $ledgerLatest = [string]$entries[$entries.Count - 1].entry_id
    $ledgerHash = Get-LedgerSnapshotHash -Ledger $State.ledger
    $chainSig = Build-ChainSignature -Entries $entries

    $a111Len = [int]$State.art111.ledger_length
    $a111Latest = [string]$State.art111.latest_entry_id
    $a111Head = [string]$State.art111.ledger_head_hash
    $a111Phase = [string]$State.art111.phase_locked

    $a112Head = [string]$State.art112.ledger_head_hash
    $a112Phase = [string]$State.art112.phase_locked
    $a112Source = [string]$State.art112.source_artifact

    # Cross-artifact checks
    if ($a111Len -ne $ledgerLen) { [void]$vectors.Add('cross_artifact_length_mismatch') }
    if ($a111Latest -ne $ledgerLatest) { [void]$vectors.Add('cross_artifact_latest_id_mismatch') }
    if ($a111Head -ne $a112Head) { [void]$vectors.Add('cross_artifact_head_mismatch') }

    # Identity and lineage checks
    if ($ledgerHash -ne $Trusted.current_ledger_snapshot_hash) { [void]$vectors.Add('identity_mismatch') }
    if ($chainSig -ne $Trusted.current_chain_signature) { [void]$vectors.Add('trust_chain_continuity_failure') }
    if ($a111Head -ne $Trusted.current_art111_head_hash_anchor) { [void]$vectors.Add('anchor_mismatch') }
    if ($a112Head -ne $Trusted.current_art112_head_hash_anchor) { [void]$vectors.Add('anchor_mismatch') }

    # Provenance checks
    if ($a111Phase -ne $Trusted.current_art111_phase_locked) { [void]$vectors.Add('provenance_break') }
    if ($a112Phase -ne $Trusted.current_art112_phase_locked) { [void]$vectors.Add('provenance_break') }
    if ($a112Source -ne $Trusted.current_art112_source_artifact) { [void]$vectors.Add('provenance_break') }

    # Trust anchor checks
    $anchor = $State.anchor
    if ([string]$anchor.anchor_id -ne $Trusted.anchor.anchor_id) { [void]$vectors.Add('anchor_mismatch') }
    if ([int]$anchor.rotation_counter -ne [int]$Trusted.anchor.rotation_counter) { [void]$vectors.Add('unauthorized_rotation') }
    if ([string]$anchor.authorized_by -ne [string]$Trusted.anchor.authorized_by) { [void]$vectors.Add('provenance_break') }
    if ([string]$anchor.authorization_proof -ne [string]$Trusted.anchor.authorization_proof) { [void]$vectors.Add('unauthorized_rotation') }
    if ([string]$anchor.chain_continuity_hash -ne [string]$Trusted.anchor.chain_continuity_hash) { [void]$vectors.Add('trust_chain_continuity_failure') }

    return ,$vectors
}

function Invoke-GuardedCycle {
    param(
        [hashtable]$State,
        [hashtable]$Trusted,
        [scriptblock]$RuntimeMutation
    )

    $pre = Get-ValidationVectors -State $State -Trusted $Trusted
    if ($pre.Count -gt 0) {
        return @{ blocked = $true; runtime_executed = $false; stage = 'pre_runtime'; vectors = $pre; reason = ($pre -join ';') }
    }

    if ($RuntimeMutation) {
        & $RuntimeMutation -State $State -Trusted $Trusted
    }

    $boundary = Get-ValidationVectors -State $State -Trusted $Trusted
    if ($boundary.Count -gt 0) {
        return @{ blocked = $true; runtime_executed = $true; stage = 'guarded_boundary'; vectors = $boundary; reason = ($boundary -join ';') }
    }

    return @{ blocked = $false; runtime_executed = $true; stage = 'allow'; vectors = [System.Collections.Generic.List[string]]::new(); reason = 'authorized_anchor_allow' }
}

function Add-CaseResult {
    param(
        [string]$Id,
        [string]$Name,
        [string]$ExpectedResult,
        [hashtable]$CycleResult
    )

    $actual = if ($CycleResult.blocked) { 'BLOCK' } else { 'ALLOW' }
    $passFail = if ($actual -eq $ExpectedResult) { 'PASS' } else { 'FAIL' }

    if ($passFail -eq 'PASS') { $script:passCount++ } else { $script:failCount++ }

    $vectors = @($CycleResult.vectors)
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'BLOCK') { $script:unauthorized_anchor_rejected_count++ }
    if (($vectors -contains 'unauthorized_rotation') -and $actual -eq 'BLOCK') { $script:unauthorized_rotation_rejected_count++ }
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'ALLOW') { $script:undetected_anchor_compromise_count++ }
    if ($ExpectedResult -eq 'ALLOW' -and $actual -eq 'BLOCK') { $script:false_positive_count++ }

    $stepFailed = if ($CycleResult.stage -eq 'pre_runtime') { 2 } elseif ($CycleResult.stage -eq 'guarded_boundary') { 7 } else { 0 }

    [void]$script:CaseMatrix.Add(@{
        case_id = $Id
        name = $Name
        expected_result = $ExpectedResult
        actual_result = $actual
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
        vectors = $vectors
    })
}

$workspaceRoot = (Split-Path $PSScriptRoot -Parent) | Split-Path -Parent
$controlPlaneDir = Join-Path $workspaceRoot 'control_plane'
$ledgerPath = Join-Path $controlPlaneDir '70_guard_fingerprint_trust_chain.json'
$art111Path = Join-Path $controlPlaneDir '111_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline.json'
$art112Path = Join-Path $controlPlaneDir '112_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_integrity.json'

if (-not (Test-Path $ledgerPath)) { throw "Missing ledger: $ledgerPath" }
if (-not (Test-Path $art111Path)) { throw "Missing art111: $art111Path" }
if (-not (Test-Path $art112Path)) { throw "Missing art112: $art112Path" }

$baselineLedger = Get-Content $ledgerPath -Raw | ConvertFrom-Json
$baselineArt111 = Get-Content $art111Path -Raw | ConvertFrom-Json
$baselineArt112 = Get-Content $art112Path -Raw | ConvertFrom-Json

$entries = @($baselineLedger.entries)
$trusted = @{
    current_ledger_snapshot_hash = Get-LedgerSnapshotHash -Ledger $baselineLedger
    current_chain_signature = Build-ChainSignature -Entries $entries
    current_art111_head_hash_anchor = [string]$baselineArt111.ledger_head_hash
    current_art112_head_hash_anchor = [string]$baselineArt112.ledger_head_hash
    current_art111_phase_locked = [string]$baselineArt111.phase_locked
    current_art112_phase_locked = [string]$baselineArt112.phase_locked
    current_art112_source_artifact = [string]$baselineArt112.source_artifact
}

$trusted.anchor = Build-Anchor -Trusted $trusted -RotationCounter 0 -AuthorizedBy 'CANONICAL_CHAIN' -ProofSeed 'ROOT_AUTH'

function New-LiveState {
    return @{
        ledger = Copy-Deep -Object $baselineLedger
        art111 = Copy-Deep -Object $baselineArt111
        art112 = Copy-Deep -Object $baselineArt112
        anchor = Copy-Deep -Object $trusted.anchor
    }
}

# Build unauthorized candidate anchors
$unauthorizedAnchor = Build-Anchor -Trusted $trusted -RotationCounter 0 -AuthorizedBy 'UNAUTHORIZED_SOURCE' -ProofSeed 'FOREIGN_AUTH'
$rotatedUnauthorizedAnchor = Build-Anchor -Trusted $trusted -RotationCounter 1 -AuthorizedBy 'CANONICAL_CHAIN' -ProofSeed 'UNAPPROVED_ROTATION'
$forgedAuthAnchor = Build-Anchor -Trusted $trusted -RotationCounter 1 -AuthorizedBy 'FAKE_TRUST_CHAIN' -ProofSeed 'FORGED_PROOF'
$sameStateNewAnchor = Build-Anchor -Trusted $trusted -RotationCounter 0 -AuthorizedBy 'CANONICAL_CHAIN' -ProofSeed 'ALTERED_ANCHOR_ID'
$sameStateNewAnchor.anchor_id = Get-StringHash -InputString ($sameStateNewAnchor.anchor_id + '|ALTER')

[void]$script:TrustAnchorLineageMap.Add('AUTHORIZED_ANCHOR_ID=' + [string]$trusted.anchor.anchor_id)
[void]$script:TrustAnchorLineageMap.Add('AUTHORIZED_ROTATION_COUNTER=' + [string]$trusted.anchor.rotation_counter)
[void]$script:TrustAnchorLineageMap.Add('AUTHORIZED_BY=' + [string]$trusted.anchor.authorized_by)
[void]$script:TrustAnchorLineageMap.Add('AUTHORIZED_CHAIN_CONTINUITY_HASH=' + [string]$trusted.anchor.chain_continuity_hash)
[void]$script:TrustAnchorLineageMap.Add('UNAUTHORIZED_ANCHOR_ID=' + [string]$unauthorizedAnchor.anchor_id)
[void]$script:TrustAnchorLineageMap.Add('UNAUTHORIZED_ROTATED_ANCHOR_ID=' + [string]$rotatedUnauthorizedAnchor.anchor_id)
[void]$script:TrustAnchorLineageMap.Add('FORGED_AUTH_ANCHOR_ID=' + [string]$forgedAuthAnchor.anchor_id)
[void]$script:TrustAnchorLineageMap.Add('SAME_STATE_NEW_ANCHOR_ID=' + [string]$sameStateNewAnchor.anchor_id)

# A) Trust-anchor swap block
$stateA = New-LiveState
$stateA.anchor = Copy-Deep -Object $unauthorizedAnchor
$resultA = Invoke-GuardedCycle -State $stateA -Trusted $trusted
Add-CaseResult -Id 'A' -Name 'trust_anchor_swap_block' -ExpectedResult 'BLOCK' -CycleResult $resultA

# B) Anchor rotation without authority
$stateB = New-LiveState
$stateB.anchor = Copy-Deep -Object $rotatedUnauthorizedAnchor
$resultB = Invoke-GuardedCycle -State $stateB -Trusted $trusted
Add-CaseResult -Id 'B' -Name 'anchor_rotation_without_authority' -ExpectedResult 'BLOCK' -CycleResult $resultB

# C) Partial anchor tamper (anchor-related field only)
$stateC = New-LiveState
$stateC.anchor.chain_continuity_hash = Get-StringHash -InputString 'tampered_continuity'
$resultC = Invoke-GuardedCycle -State $stateC -Trusted $trusted
Add-CaseResult -Id 'C' -Name 'partial_anchor_tamper' -ExpectedResult 'BLOCK' -CycleResult $resultC

# D) Forged authorization attempt
$stateD = New-LiveState
$stateD.anchor = Copy-Deep -Object $forgedAuthAnchor
$stateD.art111.phase_locked = '53.14-claimed-rotation'
$stateD.art112.phase_locked = '53.14-claimed-rotation'
$stateD.art112.source_artifact = 'forged_anchor_source.json'
$resultD = Invoke-GuardedCycle -State $stateD -Trusted $trusted
Add-CaseResult -Id 'D' -Name 'forged_authorization_attempt' -ExpectedResult 'BLOCK' -CycleResult $resultD

# E) Same-state new-anchor attack
$stateE = New-LiveState
$stateE.anchor = Copy-Deep -Object $sameStateNewAnchor
$resultE = Invoke-GuardedCycle -State $stateE -Trusted $trusted
Add-CaseResult -Id 'E' -Name 'same_state_new_anchor_attack' -ExpectedResult 'BLOCK' -CycleResult $resultE

# F) Partial provenance break with otherwise valid artifacts
$stateF = New-LiveState
$stateF.art111.phase_locked = '53.14-unauthorized'
$resultF = Invoke-GuardedCycle -State $stateF -Trusted $trusted
Add-CaseResult -Id 'F' -Name 'anchor_related_provenance_field_tamper' -ExpectedResult 'BLOCK' -CycleResult $resultF

# G) Guarded-boundary anchor swap
$stateG = New-LiveState
$resultG = Invoke-GuardedCycle -State $stateG -Trusted $trusted -RuntimeMutation {
    param([hashtable]$State, [hashtable]$Trusted)
    $State.anchor = Copy-Deep -Object $forgedAuthAnchor
}
Add-CaseResult -Id 'G' -Name 'guarded_boundary_anchor_swap' -ExpectedResult 'BLOCK' -CycleResult $resultG

# H) Clean control
$stateH = New-LiveState
$resultH = Invoke-GuardedCycle -State $stateH -Trusted $trusted
Add-CaseResult -Id 'H' -Name 'clean_control' -ExpectedResult 'ALLOW' -CycleResult $resultH

$consistencyPass = $true
if ($script:CaseMatrix.Count -ne 8) { $consistencyPass = $false }
if (($script:passCount + $script:failCount) -ne 8) { $consistencyPass = $false }
if ($script:undetected_anchor_compromise_count -ne 0) { $consistencyPass = $false }
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

$testMatrix = @(
    'ANCHOR_ATTACK_MATRIX',
    'A: trust_anchor_swap_block => expect BLOCK',
    'B: anchor_rotation_without_authority => expect BLOCK',
    'C: partial_anchor_tamper => expect BLOCK',
    'D: forged_authorization_attempt => expect BLOCK',
    'E: same_state_new_anchor_attack => expect BLOCK',
    'F: anchor_related_provenance_field_tamper => expect BLOCK',
    'G: guarded_boundary_anchor_swap => expect BLOCK',
    'H: clean_control => expect ALLOW'
)

Write-ProofFile -Path (Join-Path $PF '01_status.txt') -Content @(
    'PHASE=53.14',
    'TITLE=' + $Title,
    'GATE=' + $gate,
    'PASS_COUNT=' + $script:passCount + '/8',
    'FAIL_COUNT=' + $script:failCount,
    'unauthorized_anchor_rejected_count=' + $script:unauthorized_anchor_rejected_count,
    'unauthorized_rotation_rejected_count=' + $script:unauthorized_rotation_rejected_count,
    'undetected_anchor_compromise_count=' + $script:undetected_anchor_compromise_count,
    'false_positive_count=' + $script:false_positive_count,
    'consistency_check=' + $(if ($consistencyPass) { 'PASS' } else { 'FAIL' }),
    'FAIL_CLOSED=TRUE',
    'NO_FALLBACK=TRUE',
    'NO_SILENT_ACCEPTANCE=TRUE'
)

Write-ProofFile -Path (Join-Path $PF '14_validation_results.txt') -Content $matrixLines
Write-ProofFile -Path (Join-Path $PF '15_anchor_attack_matrix.txt') -Content $testMatrix
Write-ProofFile -Path (Join-Path $PF '15_trust_anchor_lineage_map.txt') -Content $script:TrustAnchorLineageMap.ToArray()
Write-ProofFile -Path (Join-Path $PF '15_detection_vectors.txt') -Content $vectorLines

Write-ProofFile -Path (Join-Path $PF '98_gate_phase53_14.txt') -Content @(
    'GATE=' + $gate,
    'PASS_COUNT=' + $script:passCount + '/8',
    'FAIL_COUNT=' + $script:failCount,
    'unauthorized_anchor_rejected_count=' + $script:unauthorized_anchor_rejected_count,
    'unauthorized_rotation_rejected_count=' + $script:unauthorized_rotation_rejected_count,
    'undetected_anchor_compromise_count=' + $script:undetected_anchor_compromise_count,
    'false_positive_count=' + $script:false_positive_count
)

$zipPath = $PF + '.zip'
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path $PF -DestinationPath $zipPath -Force

Write-Output ('PF=' + $PF)
Write-Output ('ZIP=' + $zipPath)
Write-Output ('GATE=' + $gate)
