#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Phase 53.21: Field-Level Metadata Tamper Resistance + Semantic Invariant Forgery Rejection

$Phase = '53.21'
$Title = 'Field-Level Metadata Tamper Resistance and Semantic Invariant Forgery Rejection'
$PF = Join-Path $PSScriptRoot '..\..\' '_proof' "phase53_21_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_metadata_tamper_semantic_invariant_forgery_rejection_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $PF -Force | Out-Null

$script:CaseMatrix = [System.Collections.Generic.List[object]]::new()
$script:DetectionVectors = [System.Collections.Generic.List[object]]::new()
$script:SemanticInvariantMap = [System.Collections.Generic.List[string]]::new()

$script:passCount = 0
$script:failCount = 0
$script:metadata_forgery_rejected_count = 0
$script:semantic_invariant_rejected_count = 0
$script:undetected_metadata_forgery_count = 0
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

function Add-Vector {
    param([System.Collections.Generic.List[string]]$Vectors, [string]$Value)
    if (-not ($Vectors -contains $Value)) {
        [void]$Vectors.Add($Value)
    }
}

function Get-FieldValue {
    param(
        $Object,
        [string]$Name,
        $Default = ''
    )

    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $Default }
    return $prop.Value
}

function Set-FieldValue {
    param(
        $Object,
        [string]$Name,
        $Value
    )

    if ($null -eq $Object) { return }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    }
    else {
        $Object.$Name = $Value
    }
}

function Build-TrustAnchor {
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
        Add-Vector -Vectors $vectors -Value 'ledger_empty'
        return ,$vectors
    }

    $ledgerLen = $entries.Count
    $ledgerLatest = [string]$entries[-1].entry_id
    $ledgerHeadHash = Get-LedgerSnapshotHash -Ledger $State.ledger
    $chainSig = Build-ChainSignature -Entries $entries

    $a111Len = [int](Get-FieldValue -Object $State.art111 -Name 'ledger_length' -Default -1)
    $a111Latest = [string](Get-FieldValue -Object $State.art111 -Name 'latest_entry_id' -Default '')
    $a111Head = [string](Get-FieldValue -Object $State.art111 -Name 'ledger_head_hash' -Default '')
    $a111Phase = [string](Get-FieldValue -Object $State.art111 -Name 'phase_locked' -Default '')
    $a111BaselineSnapshot = [string](Get-FieldValue -Object $State.art111 -Name 'baseline_snapshot_hash' -Default '')

    $a112Head = [string](Get-FieldValue -Object $State.art112 -Name 'ledger_head_hash' -Default '')
    $a112Phase = [string](Get-FieldValue -Object $State.art112 -Name 'phase_locked' -Default '')
    $a112Source = [string](Get-FieldValue -Object $State.art112 -Name 'source_artifact' -Default '')
    $a112BaselineSnapshot = [string](Get-FieldValue -Object $State.art112 -Name 'baseline_snapshot_hash' -Default '')

    if ($a111Len -ne $ledgerLen) {
        Add-Vector -Vectors $vectors -Value 'semantic_invariant_violation'
        Add-Vector -Vectors $vectors -Value 'cross_field_invariant_violation'
    }
    if ($a111Latest -ne $ledgerLatest) {
        Add-Vector -Vectors $vectors -Value 'semantic_invariant_violation'
        Add-Vector -Vectors $vectors -Value 'cross_field_invariant_violation'
    }
    if ($a111Head -ne $Trusted.current_art111_head_hash_anchor) {
        Add-Vector -Vectors $vectors -Value 'semantic_invariant_violation'
        Add-Vector -Vectors $vectors -Value 'cross_field_invariant_violation'
    }
    if (($a111BaselineSnapshot -ne '') -and ($a111BaselineSnapshot -ne $Trusted.current_art111_baseline_snapshot_hash)) {
        Add-Vector -Vectors $vectors -Value 'semantic_invariant_violation'
        Add-Vector -Vectors $vectors -Value 'cross_field_invariant_violation'
    }

    if ($a111Len -ne $ledgerLen) { Add-Vector -Vectors $vectors -Value 'cross_artifact_mismatch' }
    if ($a111Latest -ne $ledgerLatest) { Add-Vector -Vectors $vectors -Value 'cross_artifact_mismatch' }
    if ($a111Head -ne $a112Head) { Add-Vector -Vectors $vectors -Value 'cross_artifact_mismatch' }

    if ($a111Phase -ne $Trusted.current_art111_phase_locked) {
        Add-Vector -Vectors $vectors -Value 'art111_field_forgery'
        Add-Vector -Vectors $vectors -Value 'semantic_value_forgery'
    }
    if ($a112Phase -ne $Trusted.current_art112_phase_locked) {
        Add-Vector -Vectors $vectors -Value 'art112_field_forgery'
        Add-Vector -Vectors $vectors -Value 'semantic_value_forgery'
    }
    if ($a112Source -ne $Trusted.current_art112_source_artifact) {
        Add-Vector -Vectors $vectors -Value 'art112_field_forgery'
        Add-Vector -Vectors $vectors -Value 'semantic_value_forgery'
    }

    if ($a111Head -ne $Trusted.current_art111_head_hash_anchor) {
        Add-Vector -Vectors $vectors -Value 'art111_field_forgery'
        Add-Vector -Vectors $vectors -Value 'semantic_value_forgery'
    }
    if ($a112Head -ne $Trusted.current_art112_head_hash_anchor) {
        Add-Vector -Vectors $vectors -Value 'art112_field_forgery'
        Add-Vector -Vectors $vectors -Value 'semantic_value_forgery'
    }

    if (($a111BaselineSnapshot -ne '') -and ($a111BaselineSnapshot -ne $Trusted.current_art111_baseline_snapshot_hash)) {
        Add-Vector -Vectors $vectors -Value 'semantic_value_forgery'
    }
    if (($a112BaselineSnapshot -ne '') -and ($a112BaselineSnapshot -ne $Trusted.current_art112_baseline_snapshot_hash)) {
        Add-Vector -Vectors $vectors -Value 'semantic_value_forgery'
    }

    if ($chainSig -ne $Trusted.current_chain_signature) {
        Add-Vector -Vectors $vectors -Value 'lineage_break'
        Add-Vector -Vectors $vectors -Value 'continuity_break'
    }

    if ($ledgerHeadHash -ne $Trusted.current_ledger_snapshot_hash) {
        Add-Vector -Vectors $vectors -Value 'identity_failure'
    }

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

    return @{ blocked = $false; runtime_executed = $true; stage = 'allow'; vectors = [System.Collections.Generic.List[string]]::new(); reason = 'canonical_metadata_allow' }
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
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'BLOCK') { $script:metadata_forgery_rejected_count++ }
    if (($vectors -contains 'semantic_invariant_violation' -or $vectors -contains 'cross_field_invariant_violation' -or $vectors -contains 'semantic_value_forgery') -and $actual -eq 'BLOCK') {
        $script:semantic_invariant_rejected_count++
    }
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'ALLOW') { $script:undetected_metadata_forgery_count++ }
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
$trustedLen = $entries.Count
$trustedLatestId = [string]$entries[-1].entry_id
$trustedHeadHash = Get-LedgerSnapshotHash -Ledger $baselineLedger
$trustedChainSig = Build-ChainSignature -Entries $entries

$trusted = @{
    current_ledger_length = $trustedLen
    current_latest_entry_id = $trustedLatestId
    current_ledger_snapshot_hash = $trustedHeadHash
    current_chain_signature = $trustedChainSig
    current_art111_head_hash_anchor = [string](Get-FieldValue -Object $baselineArt111 -Name 'ledger_head_hash' -Default '')
    current_art112_head_hash_anchor = [string](Get-FieldValue -Object $baselineArt112 -Name 'ledger_head_hash' -Default '')
    current_art111_phase_locked = [string](Get-FieldValue -Object $baselineArt111 -Name 'phase_locked' -Default '')
    current_art111_baseline_snapshot_hash = [string](Get-FieldValue -Object $baselineArt111 -Name 'baseline_snapshot_hash' -Default '')
    current_art112_phase_locked = [string](Get-FieldValue -Object $baselineArt112 -Name 'phase_locked' -Default '')
    current_art112_source_artifact = [string](Get-FieldValue -Object $baselineArt112 -Name 'source_artifact' -Default '')
    current_art112_baseline_snapshot_hash = [string](Get-FieldValue -Object $baselineArt112 -Name 'baseline_snapshot_hash' -Default '')
}

$trusted.anchor = Build-TrustAnchor -Trusted $trusted -RotationCounter 0 -AuthorizedBy 'CANONICAL_CHAIN' -ProofSeed 'ROOT_AUTH'

function New-LiveState {
    return @{
        ledger = Copy-Deep -Object $baselineLedger
        art111 = Copy-Deep -Object $baselineArt111
        art112 = Copy-Deep -Object $baselineArt112
        anchor = Copy-Deep -Object $trusted.anchor
    }
}

[void]$script:SemanticInvariantMap.Add('TRUSTED_CHAIN_LENGTH=' + $trusted.current_ledger_length)
[void]$script:SemanticInvariantMap.Add('TRUSTED_LATEST_ENTRY_ID=' + $trusted.current_latest_entry_id)
[void]$script:SemanticInvariantMap.Add('TRUSTED_LEDGER_HEAD_HASH=' + $trusted.current_ledger_snapshot_hash)
[void]$script:SemanticInvariantMap.Add('INVARIANT_1=art111.ledger_length == ledger.entries.count')
[void]$script:SemanticInvariantMap.Add('INVARIANT_2=art111.latest_entry_id == ledger.latest_entry_id')
[void]$script:SemanticInvariantMap.Add('INVARIANT_3=art111.ledger_head_hash == trusted_art111_head_anchor')
[void]$script:SemanticInvariantMap.Add('INVARIANT_4=art112.ledger_head_hash == trusted_art112_head_anchor and art112.head == art111.head')
[void]$script:SemanticInvariantMap.Add('INVARIANT_5=phase_locked/source_artifact anchored to trusted baseline')
[void]$script:SemanticInvariantMap.Add('DETECTION_VECTOR_ART111_FIELD_FORGERY=enabled')
[void]$script:SemanticInvariantMap.Add('DETECTION_VECTOR_ART112_FIELD_FORGERY=enabled')
[void]$script:SemanticInvariantMap.Add('DETECTION_VECTOR_SEMANTIC_INVARIANT_VIOLATION=enabled')
[void]$script:SemanticInvariantMap.Add('DETECTION_VECTOR_CROSS_FIELD_INVARIANT_VIOLATION=enabled')

# A) art111 field forgery block
$stateA = New-LiveState
$stateA.art111.latest_entry_id = 'GF-0001'
$resultA = Invoke-GuardedCycle -State $stateA -Trusted $trusted
Add-CaseResult -Id 'A' -Name 'art111_field_forgery_block' -ExpectedResult 'BLOCK' -CycleResult $resultA

# B) art112 field forgery block
$stateB = New-LiveState
$stateB.art112.source_artifact = 'forged_semantic_source.json'
$resultB = Invoke-GuardedCycle -State $stateB -Trusted $trusted
Add-CaseResult -Id 'B' -Name 'art112_field_forgery_block' -ExpectedResult 'BLOCK' -CycleResult $resultB

# C) same-shape semantic forgery
$stateC = New-LiveState
$stateC.art111.ledger_length = [int]$stateC.art111.ledger_length
$stateC.art111.latest_entry_id = 'GF-0014'
$stateC.art111.ledger_head_hash = [string]$stateC.art111.ledger_head_hash
$resultC = Invoke-GuardedCycle -State $stateC -Trusted $trusted
Add-CaseResult -Id 'C' -Name 'same_shape_semantic_forgery' -ExpectedResult 'BLOCK' -CycleResult $resultC

# D) cross-field invariant violation
$stateD = New-LiveState
$stateD.art111.latest_entry_id = 'GF-0008'
$stateD.art111.ledger_length = 8
$stateD.art111.ledger_head_hash = Get-StringHash -InputString 'forged_head_hash'
Set-FieldValue -Object $stateD.art111 -Name 'baseline_snapshot_hash' -Value (Get-StringHash -InputString 'forged_baseline_snapshot')
$resultD = Invoke-GuardedCycle -State $stateD -Trusted $trusted
Add-CaseResult -Id 'D' -Name 'cross_field_invariant_violation' -ExpectedResult 'BLOCK' -CycleResult $resultD

# E) partial field forgery mismatch (ledger + art111 forged, art112 left inconsistent)
$stateE = New-LiveState
$tmpE = $stateE.ledger.entries[2]
$stateE.ledger.entries[2] = $stateE.ledger.entries[3]
$stateE.ledger.entries[3] = $tmpE
$newHeadE = Get-LedgerSnapshotHash -Ledger $stateE.ledger
$stateE.art111.ledger_head_hash = $newHeadE
$stateE.art111.latest_entry_id = [string]$stateE.ledger.entries[-1].entry_id
$stateE.art111.ledger_length = $stateE.ledger.entries.Count
# art112 intentionally not updated
$resultE = Invoke-GuardedCycle -State $stateE -Trusted $trusted
Add-CaseResult -Id 'E' -Name 'partial_field_forgery_mismatch' -ExpectedResult 'BLOCK' -CycleResult $resultE

# F) forged-semantics resealed state
$stateF = New-LiveState
$stateF.art111.phase_locked = '53.21-unauthorized-reseal'
$stateF.art112.phase_locked = '53.21-unauthorized-reseal'
$stateF.art112.source_artifact = 'forged_semantic_reseal.json'
$stateF.art111.ledger_length = $stateF.ledger.entries.Count
$stateF.art111.latest_entry_id = [string]$stateF.ledger.entries[-1].entry_id
$stateF.art111.ledger_head_hash = Get-LedgerSnapshotHash -Ledger $stateF.ledger
$stateF.art112.ledger_head_hash = [string]$stateF.art111.ledger_head_hash
$resultF = Invoke-GuardedCycle -State $stateF -Trusted $trusted
Add-CaseResult -Id 'F' -Name 'forged_semantics_resealed_state' -ExpectedResult 'BLOCK' -CycleResult $resultF

# G) guarded-boundary metadata swap
$stateG = New-LiveState
$resultG = Invoke-GuardedCycle -State $stateG -Trusted $trusted -RuntimeMutation {
    param([hashtable]$State, [hashtable]$Trusted)
    $State.art111.latest_entry_id = 'GF-0004'
    $State.art112.source_artifact = 'guarded_boundary_forged.json'
}
Add-CaseResult -Id 'G' -Name 'guarded_boundary_metadata_swap' -ExpectedResult 'BLOCK' -CycleResult $resultG

# H) clean control
$stateH = New-LiveState
$resultH = Invoke-GuardedCycle -State $stateH -Trusted $trusted
Add-CaseResult -Id 'H' -Name 'clean_control' -ExpectedResult 'ALLOW' -CycleResult $resultH

$consistencyPass = $true
if ($script:CaseMatrix.Count -ne 8) { $consistencyPass = $false }
if (($script:passCount + $script:failCount) -ne 8) { $consistencyPass = $false }
if ($script:undetected_metadata_forgery_count -ne 0) { $consistencyPass = $false }
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

$metadataMatrix = @(
    'METADATA_FORGERY_MATRIX',
    'A: art111_field_forgery_block => expect BLOCK',
    'B: art112_field_forgery_block => expect BLOCK',
    'C: same_shape_semantic_forgery => expect BLOCK',
    'D: cross_field_invariant_violation => expect BLOCK',
    'E: partial_field_forgery_mismatch => expect BLOCK',
    'F: forged_semantics_resealed_state => expect BLOCK',
    'G: guarded_boundary_metadata_swap => expect BLOCK',
    'H: clean_control => expect ALLOW'
)

Write-ProofFile -Path (Join-Path $PF '01_status.txt') -Content @(
    'PHASE=53.21',
    'TITLE=' + $Title,
    'GATE=' + $gate,
    'PASS_COUNT=' + $script:passCount + '/8',
    'FAIL_COUNT=' + $script:failCount,
    'metadata_forgery_rejected_count=' + $script:metadata_forgery_rejected_count,
    'semantic_invariant_rejected_count=' + $script:semantic_invariant_rejected_count,
    'undetected_metadata_forgery_count=' + $script:undetected_metadata_forgery_count,
    'false_positive_count=' + $script:false_positive_count,
    'consistency_check=' + $(if ($consistencyPass) { 'PASS' } else { 'FAIL' }),
    'FAIL_CLOSED=TRUE',
    'NO_FALLBACK=TRUE',
    'NO_SILENT_ACCEPTANCE=TRUE'
)

Write-ProofFile -Path (Join-Path $PF '14_validation_results.txt') -Content $matrixLines
Write-ProofFile -Path (Join-Path $PF '15_metadata_forgery_matrix.txt') -Content $metadataMatrix
Write-ProofFile -Path (Join-Path $PF '15_semantic_invariant_map.txt') -Content $script:SemanticInvariantMap.ToArray()
Write-ProofFile -Path (Join-Path $PF '15_detection_vectors.txt') -Content $vectorLines

Write-ProofFile -Path (Join-Path $PF '98_gate_phase53_21.txt') -Content @(
    'GATE=' + $gate,
    'PASS_COUNT=' + $script:passCount + '/8',
    'FAIL_COUNT=' + $script:failCount,
    'metadata_forgery_rejected_count=' + $script:metadata_forgery_rejected_count,
    'semantic_invariant_rejected_count=' + $script:semantic_invariant_rejected_count,
    'undetected_metadata_forgery_count=' + $script:undetected_metadata_forgery_count,
    'false_positive_count=' + $script:false_positive_count
)

$zipPath = $PF + '.zip'
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path $PF -DestinationPath $zipPath -Force

Write-Output ('PF=' + $PF)
Write-Output ('ZIP=' + $zipPath)
Write-Output ('GATE=' + $gate)
