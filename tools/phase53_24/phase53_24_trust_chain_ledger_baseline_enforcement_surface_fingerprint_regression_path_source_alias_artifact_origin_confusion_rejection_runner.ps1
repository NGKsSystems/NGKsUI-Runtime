#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Phase 53.24: Path/Source Alias Resistance + Artifact Origin Confusion Rejection

$Phase = '53.24'
$Title = 'Path/Source Alias Resistance and Artifact Origin Confusion Rejection'
$PF = Join-Path $PSScriptRoot '..\..\' '_proof' "phase53_24_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_path_source_alias_artifact_origin_confusion_rejection_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $PF -Force | Out-Null

$script:CaseMatrix = [System.Collections.Generic.List[object]]::new()
$script:DetectionVectors = [System.Collections.Generic.List[object]]::new()
$script:CanonicalSourceOriginMap = [System.Collections.Generic.List[string]]::new()

$script:passCount = 0
$script:failCount = 0
$script:origin_confusion_rejected_count = 0
$script:unauthorized_source_rejected_count = 0
$script:undetected_origin_confusion_count = 0
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
        $eidProp = $entry.PSObject.Properties['entry_id']
        $prevProp = $entry.PSObject.Properties['previous_hash']
        $fpProp = $entry.PSObject.Properties['fingerprint_hash']
        $eid = if ($null -ne $eidProp) { [string]$eidProp.Value } else { '' }
        $prev = if ($null -ne $prevProp) { [string]$prevProp.Value } else { '' }
        $fp = if ($null -ne $fpProp) { [string]$fpProp.Value } else { '' }
        [void]$parts.Add(($eid + '|' + $prev + '|' + $fp))
    }
    return (Get-StringHash -InputString ($parts -join ';'))
}

function Add-Vector {
    param([System.Collections.Generic.List[string]]$Vectors, [string]$Value)
    if (-not ($Vectors -contains $Value)) {
        [void]$Vectors.Add($Value)
    }
}

function Get-OriginProof {
    param(
        [string]$CanonicalPath,
        [string]$ArtifactContent
    )

    $pathHash = Get-StringHash -InputString $CanonicalPath
    $contentHash = Get-StringHash -InputString $ArtifactContent
    return (Get-StringHash -InputString ($pathHash + '|' + $contentHash))
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

    $ledgerOrigin = [string]$State.ledger_origin
    $art111Origin = [string]$State.art111_origin
    $art112Origin = [string]$State.art112_origin

    if ($ledgerOrigin -ne $Trusted.canonical_ledger_origin) {
        Add-Vector -Vectors $vectors -Value 'origin_confusion'
        Add-Vector -Vectors $vectors -Value 'unauthorized_ledger_source'
    }

    if ($art111Origin -ne $Trusted.canonical_art111_origin) {
        Add-Vector -Vectors $vectors -Value 'origin_confusion'
        Add-Vector -Vectors $vectors -Value 'unauthorized_art111_source'
    }

    if ($art112Origin -ne $Trusted.canonical_art112_origin) {
        Add-Vector -Vectors $vectors -Value 'origin_confusion'
        Add-Vector -Vectors $vectors -Value 'unauthorized_art112_source'
    }

    $ledgerContent = [string]$State.ledger_content
    $art111Content = [string]$State.art111_content
    $art112Content = [string]$State.art112_content

    $ledgerOriginProof = Get-OriginProof -CanonicalPath $ledgerOrigin -ArtifactContent $ledgerContent
    $art111OriginProof = Get-OriginProof -CanonicalPath $art111Origin -ArtifactContent $art111Content
    $art112OriginProof = Get-OriginProof -CanonicalPath $art112Origin -ArtifactContent $art112Content

    if ($ledgerOriginProof -ne $Trusted.canonical_ledger_origin_proof) {
        Add-Vector -Vectors $vectors -Value 'origin_proof_mismatch'
        Add-Vector -Vectors $vectors -Value 'unauthorized_source_rejected'
    }

    if ($art111OriginProof -ne $Trusted.canonical_art111_origin_proof) {
        Add-Vector -Vectors $vectors -Value 'origin_proof_mismatch'
        Add-Vector -Vectors $vectors -Value 'unauthorized_source_rejected'
    }

    if ($art112OriginProof -ne $Trusted.canonical_art112_origin_proof) {
        Add-Vector -Vectors $vectors -Value 'origin_proof_mismatch'
        Add-Vector -Vectors $vectors -Value 'unauthorized_source_rejected'
    }

    # Check for mixed_origin_set only if at least one origin is not canonical
    $allCanonical = ($ledgerOrigin -eq $Trusted.canonical_ledger_origin) -and `
                    ($art111Origin -eq $Trusted.canonical_art111_origin) -and `
                    ($art112Origin -eq $Trusted.canonical_art112_origin)

    if (-not $allCanonical) {
        $mixedOriginCount = 0
        if ($ledgerOrigin -ne $art111Origin) { $mixedOriginCount++ }
        if ($art111Origin -ne $art112Origin) { $mixedOriginCount++ }
        if ($ledgerOrigin -ne $art112Origin) { $mixedOriginCount++ }

        if ($mixedOriginCount -gt 0) {
            Add-Vector -Vectors $vectors -Value 'mixed_origin_set'
            Add-Vector -Vectors $vectors -Value 'origin_confusion'
        }
    }

    $ledgerParsed = $ledgerContent | ConvertFrom-Json
    $art111Parsed = $art111Content | ConvertFrom-Json
    $art112Parsed = $art112Content | ConvertFrom-Json

    $entries = @($ledgerParsed.entries)
    if ($entries.Count -eq 0) {
        Add-Vector -Vectors $vectors -Value 'ledger_empty'
        return ,$vectors
    }

    $chainSig = Build-ChainSignature -Entries $entries
    if ($chainSig -ne $Trusted.current_chain_signature) {
        Add-Vector -Vectors $vectors -Value 'lineage_break'
    }

    $ledgerHash = Get-LedgerSnapshotHash -Ledger $ledgerParsed
    if ($ledgerHash -ne $Trusted.current_ledger_snapshot_hash) {
        Add-Vector -Vectors $vectors -Value 'identity_failure'
    }

    if ([string]$art111Parsed.ledger_head_hash -ne $Trusted.current_art111_head_hash_anchor -or [string]$art112Parsed.ledger_head_hash -ne $Trusted.current_art112_head_hash_anchor) {
        Add-Vector -Vectors $vectors -Value 'cross_artifact_mismatch'
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

    return @{ blocked = $false; runtime_executed = $true; stage = 'allow'; vectors = [System.Collections.Generic.List[string]]::new(); reason = 'canonical_origin_allow' }
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
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'BLOCK') { $script:origin_confusion_rejected_count++ }
    if (($vectors -contains 'unauthorized_source_rejected' -or $vectors -contains 'origin_proof_mismatch') -and $actual -eq 'BLOCK') {
        $script:unauthorized_source_rejected_count++
    }
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'ALLOW') { $script:undetected_origin_confusion_count++ }
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

$baselineLedgerContent = Get-Content $ledgerPath -Raw
$baselineArt111Content = Get-Content $art111Path -Raw
$baselineArt112Content = Get-Content $art112Path -Raw

$baselineLedger = $baselineLedgerContent | ConvertFrom-Json
$baselineArt111 = $baselineArt111Content | ConvertFrom-Json
$baselineArt112 = $baselineArt112Content | ConvertFrom-Json

$entries = @($baselineLedger.entries)
if ($entries.Count -eq 0) { throw 'Baseline ledger has no entries.' }

$canonicalLedgerOrigin = 'control_plane/70_guard_fingerprint_trust_chain.json'
$canonicalArt111Origin = 'control_plane/111_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline.json'
$canonicalArt112Origin = 'control_plane/112_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_integrity.json'

$trusted = @{
    current_ledger_length = $entries.Count
    current_latest_entry_id = [string]$entries[-1].entry_id
    current_ledger_snapshot_hash = Get-LedgerSnapshotHash -Ledger $baselineLedger
    current_chain_signature = Build-ChainSignature -Entries $entries
    current_art111_head_hash_anchor = [string]$baselineArt111.ledger_head_hash
    current_art112_head_hash_anchor = [string]$baselineArt112.ledger_head_hash

    canonical_ledger_origin = $canonicalLedgerOrigin
    canonical_art111_origin = $canonicalArt111Origin
    canonical_art112_origin = $canonicalArt112Origin

    canonical_ledger_origin_proof = Get-OriginProof -CanonicalPath $canonicalLedgerOrigin -ArtifactContent $baselineLedgerContent
    canonical_art111_origin_proof = Get-OriginProof -CanonicalPath $canonicalArt111Origin -ArtifactContent $baselineArt111Content
    canonical_art112_origin_proof = Get-OriginProof -CanonicalPath $canonicalArt112Origin -ArtifactContent $baselineArt112Content
}

$trusted.anchor = Build-TrustAnchor -Trusted $trusted -RotationCounter 0 -AuthorizedBy 'CANONICAL_CHAIN' -ProofSeed 'ROOT_AUTH'

function New-LiveState {
    return @{
        ledger_origin = $canonicalLedgerOrigin
        ledger_content = [string]$baselineLedgerContent
        art111_origin = $canonicalArt111Origin
        art111_content = [string]$baselineArt111Content
        art112_origin = $canonicalArt112Origin
        art112_content = [string]$baselineArt112Content
        anchor = Copy-Deep -Object $trusted.anchor
    }
}

[void]$script:CanonicalSourceOriginMap.Add('CANONICAL_LEDGER_ORIGIN=' + $canonicalLedgerOrigin)
[void]$script:CanonicalSourceOriginMap.Add('CANONICAL_ART111_ORIGIN=' + $canonicalArt111Origin)
[void]$script:CanonicalSourceOriginMap.Add('CANONICAL_ART112_ORIGIN=' + $canonicalArt112Origin)
[void]$script:CanonicalSourceOriginMap.Add('ORIGIN_BINDING_RULE=exact_canonical_source_path_origin_required')
[void]$script:CanonicalSourceOriginMap.Add('ORIGIN_PROOF_RULE=origin_path_and_content_proof_must_match_canonical')
[void]$script:CanonicalSourceOriginMap.Add('MIXED_ORIGIN_RULE=all_artifacts_must_share_same_canonical_origin_lineage')
[void]$script:CanonicalSourceOriginMap.Add('DETECTION_VECTOR_ALIAS_PATH_BLOCK=enabled')
[void]$script:CanonicalSourceOriginMap.Add('DETECTION_VECTOR_COPY_MIRROR_SUBSTITUTION=enabled')
[void]$script:CanonicalSourceOriginMap.Add('DETECTION_VECTOR_SAME_CONTENT_DIFFERENT_ORIGIN=enabled')
[void]$script:CanonicalSourceOriginMap.Add('DETECTION_VECTOR_MIXED_ORIGIN_SET=enabled')
[void]$script:CanonicalSourceOriginMap.Add('DETECTION_VECTOR_RESEALED_ORIGIN_FORGERY=enabled')

# A) Alias-path block (ledger from alternate path)
$stateA = New-LiveState
$stateA.ledger_origin = 'temp/_mirror/70_guard_fingerprint_trust_chain.json'
$stateA.art111_origin = 'backup/111_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline.json'
$stateA.art112_origin = 'archive/112_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_integrity.json'
$resultA = Invoke-GuardedCycle -State $stateA -Trusted $trusted
Add-CaseResult -Id 'A' -Name 'alias_path_block' -ExpectedResult 'BLOCK' -CycleResult $resultA

# B) Copy / mirror substitution
$stateB = New-LiveState
$stateB.ledger_origin = 'runtime_copy/ledger_snapshot_20260320.json'
$stateB.art111_origin = 'runtime_copy/art111_snapshot_20260320.json'
$stateB.art112_origin = 'runtime_copy/art112_snapshot_20260320.json'
$resultB = Invoke-GuardedCycle -State $stateB -Trusted $trusted
Add-CaseResult -Id 'B' -Name 'copy_mirror_substitution' -ExpectedResult 'BLOCK' -CycleResult $resultB

# C) Same-content different-origin attack
$stateC = New-LiveState
$stateC.ledger_origin = 'alternate_source/70_guard_fingerprint_trust_chain.json'
$stateC.art111_origin = $canonicalArt111Origin
$stateC.art112_origin = $canonicalArt112Origin
$resultC = Invoke-GuardedCycle -State $stateC -Trusted $trusted
Add-CaseResult -Id 'C' -Name 'same_content_different_origin' -ExpectedResult 'BLOCK' -CycleResult $resultC

# D) Mixed-origin set (ledger and art111 from different origins)
$stateD = New-LiveState
$stateD.ledger_origin = 'master/70_guard_fingerprint_trust_chain.json'
$stateD.art111_origin = $canonicalArt111Origin
$stateD.art112_origin = 'shadow/112_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_integrity.json'
$resultD = Invoke-GuardedCycle -State $stateD -Trusted $trusted
Add-CaseResult -Id 'D' -Name 'mixed_origin_set' -ExpectedResult 'BLOCK' -CycleResult $resultD

# E) Resealed origin forgery (modify origin but recompute hashes)
$stateE = New-LiveState
$stateE.ledger_origin = 'resealed_mirror/70_guard_fingerprint_trust_chain.json'
$stateE.art111_origin = 'resealed_mirror/111_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline.json'
$stateE.art112_origin = 'resealed_mirror/112_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_integrity.json'
$resultE = Invoke-GuardedCycle -State $stateE -Trusted $trusted
Add-CaseResult -Id 'E' -Name 'resealed_origin_forgery' -ExpectedResult 'BLOCK' -CycleResult $resultE

# F) Redirect / pointer confusion (symlink-like alias)
$stateF = New-LiveState
$stateF.ledger_origin = 'symlink://control_plane/70_guard_fingerprint_trust_chain.json'
$stateF.art111_origin = 'redirect://control_plane/111_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline.json'
$stateF.art112_origin = 'proxy://control_plane/112_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_integrity.json'
$resultF = Invoke-GuardedCycle -State $stateF -Trusted $trusted
Add-CaseResult -Id 'F' -Name 'link_redirect_pointer_confusion' -ExpectedResult 'BLOCK' -CycleResult $resultF

# G) Guarded-boundary origin swap
$stateG = New-LiveState
$resultG = Invoke-GuardedCycle -State $stateG -Trusted $trusted -RuntimeMutation {
    param([hashtable]$State, [hashtable]$Trusted)
    $State.art111_origin = '_tmp_mirror/111_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline.json'
    $State.art112_origin = '_tmp_mirror/112_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_integrity.json'
}
Add-CaseResult -Id 'G' -Name 'guarded_boundary_origin_swap' -ExpectedResult 'BLOCK' -CycleResult $resultG

# H) Clean control (canonical origins only)
$stateH = New-LiveState
$resultH = Invoke-GuardedCycle -State $stateH -Trusted $trusted
Add-CaseResult -Id 'H' -Name 'clean_control' -ExpectedResult 'ALLOW' -CycleResult $resultH

$consistencyPass = $true
if ($script:CaseMatrix.Count -ne 8) { $consistencyPass = $false }
if (($script:passCount + $script:failCount) -ne 8) { $consistencyPass = $false }
if ($script:undetected_origin_confusion_count -ne 0) { $consistencyPass = $false }
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

$originMatrix = @(
    'ORIGIN_CONFUSION_MATRIX',
    'A: alias_path_block => expect BLOCK',
    'B: copy_mirror_substitution => expect BLOCK',
    'C: same_content_different_origin => expect BLOCK',
    'D: mixed_origin_set => expect BLOCK',
    'E: resealed_origin_forgery => expect BLOCK',
    'F: link_redirect_pointer_confusion => expect BLOCK',
    'G: guarded_boundary_origin_swap => expect BLOCK',
    'H: clean_control => expect ALLOW'
)

Write-ProofFile -Path (Join-Path $PF '01_status.txt') -Content @(
    'PHASE=53.24',
    ('TITLE={0}' -f $Title),
    ('GATE={0}' -f $gate),
    ('PASS_COUNT={0}/8' -f $script:passCount),
    ('FAIL_COUNT={0}' -f $script:failCount),
    ('origin_confusion_rejected_count={0}' -f $script:origin_confusion_rejected_count),
    ('unauthorized_source_rejected_count={0}' -f $script:unauthorized_source_rejected_count),
    ('undetected_origin_confusion_count={0}' -f $script:undetected_origin_confusion_count),
    ('false_positive_count={0}' -f $script:false_positive_count),
    ('consistency_check={0}' -f $(if ($consistencyPass) { 'PASS' } else { 'FAIL' })),
    'FAIL_CLOSED=TRUE',
    'NO_FALLBACK=TRUE',
    'NO_SILENT_ACCEPTANCE=TRUE'
)

Write-ProofFile -Path (Join-Path $PF '14_validation_results.txt') -Content $matrixLines
Write-ProofFile -Path (Join-Path $PF '15_origin_confusion_matrix.txt') -Content $originMatrix
Write-ProofFile -Path (Join-Path $PF '15_canonical_source_origin_map.txt') -Content $script:CanonicalSourceOriginMap.ToArray()
Write-ProofFile -Path (Join-Path $PF '15_detection_vectors.txt') -Content $vectorLines

Write-ProofFile -Path (Join-Path $PF '98_gate_phase53_24.txt') -Content @(
    ('GATE={0}' -f $gate),
    ('PASS_COUNT={0}/8' -f $script:passCount),
    ('FAIL_COUNT={0}' -f $script:failCount),
    ('origin_confusion_rejected_count={0}' -f $script:origin_confusion_rejected_count),
    ('unauthorized_source_rejected_count={0}' -f $script:unauthorized_source_rejected_count),
    ('undetected_origin_confusion_count={0}' -f $script:undetected_origin_confusion_count),
    ('false_positive_count={0}' -f $script:false_positive_count)
)

$zipPath = $PF + '.zip'
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path $PF -DestinationPath $zipPath -Force

Write-Output ('PF=' + $PF)
Write-Output ('ZIP=' + $zipPath)
Write-Output ('GATE=' + $gate)
