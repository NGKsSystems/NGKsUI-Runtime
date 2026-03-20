#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Phase 53.23: Canonical Serialization Drift Resistance + Hash-Normalization Forgery Rejection

$Phase = '53.23'
$Title = 'Canonical Serialization Drift Resistance and Hash-Normalization Forgery Rejection'
$PF = Join-Path $PSScriptRoot '..\..\' '_proof' "phase53_23_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_canonical_serialization_drift_hash_normalization_forgery_rejection_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $PF -Force | Out-Null

$script:CaseMatrix = [System.Collections.Generic.List[object]]::new()
$script:DetectionVectors = [System.Collections.Generic.List[object]]::new()
$script:CanonicalSerializationMap = [System.Collections.Generic.List[string]]::new()

$script:passCount = 0
$script:failCount = 0
$script:serialization_drift_rejected_count = 0
$script:hash_normalization_forgery_rejected_count = 0
$script:undetected_serialization_drift_count = 0
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

function Get-WhitespaceAgnosticHash {
    param([string]$Text)
    $collapsed = [regex]::Replace($Text, '\s+', '')
    return (Get-StringHash -InputString $collapsed)
}

function Get-NewlineNormalizedHash {
    param([string]$Text)
    $normalized = $Text -replace "`r`n", "`n"
    $normalized = $normalized -replace "`r", "`n"
    return (Get-StringHash -InputString $normalized)
}

function Get-UnicodeFormCHash {
    param([string]$Text)
    $formC = $Text.Normalize([System.Text.NormalizationForm]::FormC)
    return (Get-StringHash -InputString $formC)
}

function ConvertTo-ReorderedObject {
    param(
        $Object,
        [bool]$Descending
    )

    if ($null -eq $Object) { return $null }

    if ($Object -is [System.Collections.IEnumerable] -and -not ($Object -is [string]) -and -not ($Object -is [pscustomobject]) -and -not ($Object -is [hashtable])) {
        $arr = @()
        foreach ($item in @($Object)) {
            $arr += ,(ConvertTo-ReorderedObject -Object $item -Descending $Descending)
        }
        return ,$arr
    }

    if ($Object -is [pscustomobject] -or $Object -is [hashtable]) {
        $propNames = @($Object.PSObject.Properties | ForEach-Object { $_.Name })
        if ($Descending) {
            $propNames = @($propNames | Sort-Object -Descending)
        }
        else {
            $propNames = @($propNames | Sort-Object)
        }

        $ordered = [ordered]@{}
        foreach ($name in $propNames) {
            $ordered[$name] = ConvertTo-ReorderedObject -Object $Object.$name -Descending $Descending
        }
        return [pscustomobject]$ordered
    }

    return $Object
}

function ConvertTo-NonCanonicalJson {
    param(
        $Object,
        [bool]$Descending = $true,
        [bool]$Compress = $false
    )

    $reordered = ConvertTo-ReorderedObject -Object $Object -Descending $Descending
    if ($Compress) {
        return ($reordered | ConvertTo-Json -Depth 99 -Compress)
    }

    return ($reordered | ConvertTo-Json -Depth 99)
}

function Parse-JsonSafe {
    param([string]$Raw)

    try {
        return @{ ok = $true; value = ($Raw | ConvertFrom-Json) }
    }
    catch {
        return @{ ok = $false; value = $null; error = $_.Exception.Message }
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

    $parseLedger = Parse-JsonSafe -Raw ([string]$State.ledger_raw)
    $parseArt111 = Parse-JsonSafe -Raw ([string]$State.art111_raw)
    $parseArt112 = Parse-JsonSafe -Raw ([string]$State.art112_raw)

    if (-not $parseLedger.ok -or -not $parseArt111.ok -or -not $parseArt112.ok) {
        Add-Vector -Vectors $vectors -Value 'serialization_parse_failure'
        Add-Vector -Vectors $vectors -Value 'serialization_drift'
        return ,$vectors
    }

    $ledger = $parseLedger.value
    $art111 = $parseArt111.value
    $art112 = $parseArt112.value

    $rawMismatchCount = 0
    foreach ($name in @('ledger', 'art111', 'art112')) {
        $raw = [string]$State[($name + '_raw')]
        $rawHash = Get-StringHash -InputString $raw
        if ($rawHash -ne [string]$Trusted[($name + '_raw_hash')]) {
            $rawMismatchCount++
            Add-Vector -Vectors $vectors -Value 'serialization_drift'
            Add-Vector -Vectors $vectors -Value 'canonical_serialization_contract_violation'

            $whitespaceHash = Get-WhitespaceAgnosticHash -Text $raw
            if ($whitespaceHash -eq [string]$Trusted[($name + '_whitespace_hash')]) {
                Add-Vector -Vectors $vectors -Value 'normalization_drift'
            }

            $newlineHash = Get-NewlineNormalizedHash -Text $raw
            if ($newlineHash -eq [string]$Trusted[($name + '_newline_hash')]) {
                Add-Vector -Vectors $vectors -Value 'newline_style_drift'
            }

            $formCHash = Get-UnicodeFormCHash -Text $raw
            if ($formCHash -eq [string]$Trusted[($name + '_unicode_formc_hash')]) {
                Add-Vector -Vectors $vectors -Value 'unicode_normalization_drift'
            }
        }
    }

    if ($rawMismatchCount -gt 0) {
        if ($rawMismatchCount -lt 3) {
            Add-Vector -Vectors $vectors -Value 'partial_serialization_drift_mismatch'
        }
    }

    $entries = @($ledger.entries)
    if ($entries.Count -eq 0) {
        Add-Vector -Vectors $vectors -Value 'ledger_empty'
        return ,$vectors
    }

    $ledgerLen = $entries.Count
    $trustedLen = [int]$Trusted.current_ledger_length
    if ($ledgerLen -ne $trustedLen) {
        Add-Vector -Vectors $vectors -Value 'length_mismatch'
    }

    $ledgerLatest = [string]$entries[-1].entry_id
    if ([string]$art111.latest_entry_id -ne $ledgerLatest) {
        Add-Vector -Vectors $vectors -Value 'cross_artifact_canonicalization_mismatch'
    }

    if ([int]$art111.ledger_length -ne $ledgerLen) {
        Add-Vector -Vectors $vectors -Value 'cross_artifact_canonicalization_mismatch'
    }

    if ([string]$art111.ledger_head_hash -ne [string]$art112.ledger_head_hash) {
        Add-Vector -Vectors $vectors -Value 'cross_artifact_canonicalization_mismatch'
    }

    $chainSig = Build-ChainSignature -Entries $entries
    if ($chainSig -ne $Trusted.current_chain_signature) {
        Add-Vector -Vectors $vectors -Value 'lineage_break'
        Add-Vector -Vectors $vectors -Value 'continuity_break'
    }

    $ledgerSnapshotHash = Get-LedgerSnapshotHash -Ledger $ledger
    if ($ledgerSnapshotHash -ne $Trusted.current_ledger_snapshot_hash) {
        Add-Vector -Vectors $vectors -Value 'identity_failure'
    }

    if ([string]$art111.ledger_head_hash -ne $Trusted.current_art111_head_hash_anchor -or [string]$art112.ledger_head_hash -ne $Trusted.current_art112_head_hash_anchor) {
        Add-Vector -Vectors $vectors -Value 'hash_normalization_forgery'
    }

    if ([string]$art112.baseline_snapshot_hash -ne $Trusted.current_art112_baseline_snapshot_hash) {
        Add-Vector -Vectors $vectors -Value 'hash_normalization_forgery'
    }

    if ($rawMismatchCount -gt 0 -and [string]$art111.ledger_head_hash -eq [string]$art112.ledger_head_hash -and [string]$art111.ledger_head_hash -ne $Trusted.current_art111_head_hash_anchor) {
        Add-Vector -Vectors $vectors -Value 'self_consistent_non_canonical_reseal'
        Add-Vector -Vectors $vectors -Value 'hash_normalization_forgery'
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

    return @{ blocked = $false; runtime_executed = $true; stage = 'allow'; vectors = [System.Collections.Generic.List[string]]::new(); reason = 'canonical_serialization_allow' }
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
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'BLOCK') { $script:serialization_drift_rejected_count++ }
    if (($vectors -contains 'hash_normalization_forgery' -or $vectors -contains 'self_consistent_non_canonical_reseal') -and $actual -eq 'BLOCK') {
        $script:hash_normalization_forgery_rejected_count++
    }
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'ALLOW') { $script:undetected_serialization_drift_count++ }
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

$baselineLedgerRaw = Get-Content $ledgerPath -Raw
$baselineArt111Raw = Get-Content $art111Path -Raw
$baselineArt112Raw = Get-Content $art112Path -Raw

$baselineLedger = $baselineLedgerRaw | ConvertFrom-Json
$baselineArt111 = $baselineArt111Raw | ConvertFrom-Json
$baselineArt112 = $baselineArt112Raw | ConvertFrom-Json

$entries = @($baselineLedger.entries)
if ($entries.Count -eq 0) { throw 'Baseline ledger has no entries.' }

$trusted = @{
    current_ledger_length = $entries.Count
    current_latest_entry_id = [string]$entries[-1].entry_id
    current_ledger_snapshot_hash = Get-LedgerSnapshotHash -Ledger $baselineLedger
    current_chain_signature = Build-ChainSignature -Entries $entries
    current_art111_head_hash_anchor = [string]$baselineArt111.ledger_head_hash
    current_art112_head_hash_anchor = [string]$baselineArt112.ledger_head_hash
    current_art112_baseline_snapshot_hash = [string]$baselineArt112.baseline_snapshot_hash

    ledger_raw_hash = Get-StringHash -InputString $baselineLedgerRaw
    art111_raw_hash = Get-StringHash -InputString $baselineArt111Raw
    art112_raw_hash = Get-StringHash -InputString $baselineArt112Raw

    ledger_whitespace_hash = Get-WhitespaceAgnosticHash -Text $baselineLedgerRaw
    art111_whitespace_hash = Get-WhitespaceAgnosticHash -Text $baselineArt111Raw
    art112_whitespace_hash = Get-WhitespaceAgnosticHash -Text $baselineArt112Raw

    ledger_newline_hash = Get-NewlineNormalizedHash -Text $baselineLedgerRaw
    art111_newline_hash = Get-NewlineNormalizedHash -Text $baselineArt111Raw
    art112_newline_hash = Get-NewlineNormalizedHash -Text $baselineArt112Raw

    ledger_unicode_formc_hash = Get-UnicodeFormCHash -Text $baselineLedgerRaw
    art111_unicode_formc_hash = Get-UnicodeFormCHash -Text $baselineArt111Raw
    art112_unicode_formc_hash = Get-UnicodeFormCHash -Text $baselineArt112Raw
}

$trusted.anchor = Build-TrustAnchor -Trusted $trusted -RotationCounter 0 -AuthorizedBy 'CANONICAL_CHAIN' -ProofSeed 'ROOT_AUTH'

function New-LiveState {
    return @{
        ledger_raw = [string]$baselineLedgerRaw
        art111_raw = [string]$baselineArt111Raw
        art112_raw = [string]$baselineArt112Raw
        anchor = Copy-Deep -Object $trusted.anchor
    }
}

[void]$script:CanonicalSerializationMap.Add('TRUSTED_CHAIN_LENGTH=' + $trusted.current_ledger_length)
[void]$script:CanonicalSerializationMap.Add('TRUSTED_LATEST_ENTRY_ID=' + $trusted.current_latest_entry_id)
[void]$script:CanonicalSerializationMap.Add('CANONICAL_SERIALIZATION_RULE=exact_artifact_raw_bytes_must_match_trusted_contract')
[void]$script:CanonicalSerializationMap.Add('NORMALIZATION_RULE_1=no newline_style_drift')
[void]$script:CanonicalSerializationMap.Add('NORMALIZATION_RULE_2=no unicode_normalization_drift')
[void]$script:CanonicalSerializationMap.Add('NORMALIZATION_RULE_3=no whitespace_normalization_forgery')
[void]$script:CanonicalSerializationMap.Add('REPRESENTATION_RULE_1=number_boolean_null_forms_must_match_canonical_contract')
[void]$script:CanonicalSerializationMap.Add('RESEAL_RULE=self_consistent_non_canonical_state_is_invalid')
[void]$script:CanonicalSerializationMap.Add('DETECTION_VECTOR_SERIALIZATION_DRIFT=enabled')
[void]$script:CanonicalSerializationMap.Add('DETECTION_VECTOR_HASH_NORMALIZATION_FORGERY=enabled')
[void]$script:CanonicalSerializationMap.Add('DETECTION_VECTOR_PARTIAL_SERIALIZATION_DRIFT_MISMATCH=enabled')
[void]$script:CanonicalSerializationMap.Add('DETECTION_VECTOR_GUARDED_BOUNDARY_SWAP=enabled')

# A) Key-order / property-order drift block
$stateA = New-LiveState
$stateA.ledger_raw = ConvertTo-NonCanonicalJson -Object ($stateA.ledger_raw | ConvertFrom-Json) -Descending $true -Compress $false
$stateA.art111_raw = ConvertTo-NonCanonicalJson -Object ($stateA.art111_raw | ConvertFrom-Json) -Descending $true -Compress $false
$stateA.art112_raw = ConvertTo-NonCanonicalJson -Object ($stateA.art112_raw | ConvertFrom-Json) -Descending $true -Compress $false
$resultA = Invoke-GuardedCycle -State $stateA -Trusted $trusted
Add-CaseResult -Id 'A' -Name 'key_order_property_order_drift_block' -ExpectedResult 'BLOCK' -CycleResult $resultA

# B) Whitespace / encoding / text-normalization forgery
$stateB = New-LiveState
$stateB.art111_raw = $stateB.art111_raw -replace ': ', ' :    '
$stateB.art112_raw = $stateB.art112_raw -replace "`r`n", "`n"
$stateB.ledger_raw = $stateB.ledger_raw -replace '"GF-0001"', '"GF-\u0030\u0030\u0030\u0031"'
$resultB = Invoke-GuardedCycle -State $stateB -Trusted $trusted
Add-CaseResult -Id 'B' -Name 'whitespace_encoding_text_normalization_forgery' -ExpectedResult 'BLOCK' -CycleResult $resultB

# C) Number / boolean / null representation drift
$stateC = New-LiveState
$stateC.art111_raw = [regex]::Replace($stateC.art111_raw, '"ledger_length"\s*:\s*15', '"ledger_length": 1.5e1', 1)
$stateC.art112_raw = $stateC.art112_raw -replace '"artifact_id": "112"', '"artifact_id": "\u0031\u0031\u0032"'
$stateC.ledger_raw = [regex]::Replace($stateC.ledger_raw, '"previous_hash"\s*:\s*null', '"previous_hash":     null', 1)
$resultC = Invoke-GuardedCycle -State $stateC -Trusted $trusted
Add-CaseResult -Id 'C' -Name 'number_boolean_null_representation_drift' -ExpectedResult 'BLOCK' -CycleResult $resultC

# D) Same-value non-canonical reseal
$stateD = New-LiveState
$ledgerD = $stateD.ledger_raw | ConvertFrom-Json
$art111D = $stateD.art111_raw | ConvertFrom-Json
$art112D = $stateD.art112_raw | ConvertFrom-Json
$stateD.ledger_raw = ConvertTo-NonCanonicalJson -Object $ledgerD -Descending $true -Compress $true
$art111D.ledger_head_hash = Get-StringHash -InputString $stateD.ledger_raw
$art112D.ledger_head_hash = [string]$art111D.ledger_head_hash
$stateD.art111_raw = ConvertTo-NonCanonicalJson -Object $art111D -Descending $true -Compress $true
$art112D.baseline_snapshot_hash = Get-StringHash -InputString $stateD.art111_raw
$stateD.art112_raw = ConvertTo-NonCanonicalJson -Object $art112D -Descending $true -Compress $true
$resultD = Invoke-GuardedCycle -State $stateD -Trusted $trusted
Add-CaseResult -Id 'D' -Name 'same_value_non_canonical_reseal' -ExpectedResult 'BLOCK' -CycleResult $resultD

# E) Partial serialization drift mismatch (ledger only)
$stateE = New-LiveState
$stateE.ledger_raw = ConvertTo-NonCanonicalJson -Object ($stateE.ledger_raw | ConvertFrom-Json) -Descending $true -Compress $true
$resultE = Invoke-GuardedCycle -State $stateE -Trusted $trusted
Add-CaseResult -Id 'E' -Name 'partial_serialization_drift_mismatch_ledger_only' -ExpectedResult 'BLOCK' -CycleResult $resultE

# F) Hash-normalization forgery
$stateF = New-LiveState
$ledgerF = $stateF.ledger_raw | ConvertFrom-Json
$art111F = $stateF.art111_raw | ConvertFrom-Json
$art112F = $stateF.art112_raw | ConvertFrom-Json
$stateF.ledger_raw = ConvertTo-NonCanonicalJson -Object $ledgerF -Descending $false -Compress $false
$altHeadHash = Get-WhitespaceAgnosticHash -Text $stateF.ledger_raw
$art111F.ledger_head_hash = $altHeadHash
$art112F.ledger_head_hash = $altHeadHash
$stateF.art111_raw = ConvertTo-NonCanonicalJson -Object $art111F -Descending $false -Compress $true
$art112F.baseline_snapshot_hash = Get-WhitespaceAgnosticHash -Text $stateF.art111_raw
$stateF.art112_raw = ConvertTo-NonCanonicalJson -Object $art112F -Descending $false -Compress $true
$resultF = Invoke-GuardedCycle -State $stateF -Trusted $trusted
Add-CaseResult -Id 'F' -Name 'hash_normalization_forgery' -ExpectedResult 'BLOCK' -CycleResult $resultF

# G) Guarded-boundary serialization swap
$stateG = New-LiveState
$resultG = Invoke-GuardedCycle -State $stateG -Trusted $trusted -RuntimeMutation {
    param([hashtable]$State, [hashtable]$Trusted)
    $obj = $State.art112_raw | ConvertFrom-Json
    $State.art112_raw = ConvertTo-NonCanonicalJson -Object $obj -Descending $true -Compress $true
}
Add-CaseResult -Id 'G' -Name 'guarded_boundary_serialization_swap' -ExpectedResult 'BLOCK' -CycleResult $resultG

# H) Clean control
$stateH = New-LiveState
$resultH = Invoke-GuardedCycle -State $stateH -Trusted $trusted
Add-CaseResult -Id 'H' -Name 'clean_control' -ExpectedResult 'ALLOW' -CycleResult $resultH

$consistencyPass = $true
if ($script:CaseMatrix.Count -ne 8) { $consistencyPass = $false }
if (($script:passCount + $script:failCount) -ne 8) { $consistencyPass = $false }
if ($script:undetected_serialization_drift_count -ne 0) { $consistencyPass = $false }
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

$serializationMatrix = @(
    'SERIALIZATION_DRIFT_MATRIX',
    'A: key_order_property_order_drift_block => expect BLOCK',
    'B: whitespace_encoding_text_normalization_forgery => expect BLOCK',
    'C: number_boolean_null_representation_drift => expect BLOCK',
    'D: same_value_non_canonical_reseal => expect BLOCK',
    'E: partial_serialization_drift_mismatch_ledger_only => expect BLOCK',
    'F: hash_normalization_forgery => expect BLOCK',
    'G: guarded_boundary_serialization_swap => expect BLOCK',
    'H: clean_control => expect ALLOW'
)

Write-ProofFile -Path (Join-Path $PF '01_status.txt') -Content @(
    'PHASE=53.23',
    ('TITLE={0}' -f $Title),
    ('GATE={0}' -f $gate),
    ('PASS_COUNT={0}/8' -f $script:passCount),
    ('FAIL_COUNT={0}' -f $script:failCount),
    ('serialization_drift_rejected_count={0}' -f $script:serialization_drift_rejected_count),
    ('hash_normalization_forgery_rejected_count={0}' -f $script:hash_normalization_forgery_rejected_count),
    ('undetected_serialization_drift_count={0}' -f $script:undetected_serialization_drift_count),
    ('false_positive_count={0}' -f $script:false_positive_count),
    ('consistency_check={0}' -f $(if ($consistencyPass) { 'PASS' } else { 'FAIL' })),
    'FAIL_CLOSED=TRUE',
    'NO_FALLBACK=TRUE',
    'NO_SILENT_ACCEPTANCE=TRUE'
)

Write-ProofFile -Path (Join-Path $PF '14_validation_results.txt') -Content $matrixLines
Write-ProofFile -Path (Join-Path $PF '15_serialization_drift_matrix.txt') -Content $serializationMatrix
Write-ProofFile -Path (Join-Path $PF '15_canonical_serialization_normalization_map.txt') -Content $script:CanonicalSerializationMap.ToArray()
Write-ProofFile -Path (Join-Path $PF '15_detection_vectors.txt') -Content $vectorLines

Write-ProofFile -Path (Join-Path $PF '98_gate_phase53_23.txt') -Content @(
    ('GATE={0}' -f $gate),
    ('PASS_COUNT={0}/8' -f $script:passCount),
    ('FAIL_COUNT={0}' -f $script:failCount),
    ('serialization_drift_rejected_count={0}' -f $script:serialization_drift_rejected_count),
    ('hash_normalization_forgery_rejected_count={0}' -f $script:hash_normalization_forgery_rejected_count),
    ('undetected_serialization_drift_count={0}' -f $script:undetected_serialization_drift_count),
    ('false_positive_count={0}' -f $script:false_positive_count)
)

$zipPath = $PF + '.zip'
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path $PF -DestinationPath $zipPath -Force

Write-Output ('PF=' + $PF)
Write-Output ('ZIP=' + $zipPath)
Write-Output ('GATE=' + $gate)
