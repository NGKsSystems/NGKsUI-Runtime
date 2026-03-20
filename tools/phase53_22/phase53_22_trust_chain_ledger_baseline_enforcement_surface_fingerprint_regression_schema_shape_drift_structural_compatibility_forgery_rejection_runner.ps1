#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Phase 53.22: Schema-Shape Drift Resistance + Structural Compatibility Forgery Rejection

$Phase = '53.22'
$Title = 'Schema-Shape Drift Resistance and Structural Compatibility Forgery Rejection'
$PF = Join-Path $PSScriptRoot '..\..\' '_proof' "phase53_22_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_schema_shape_drift_structural_compatibility_forgery_rejection_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $PF -Force | Out-Null

$script:CaseMatrix = [System.Collections.Generic.List[object]]::new()
$script:DetectionVectors = [System.Collections.Generic.List[object]]::new()
$script:StructuralInvariantMap = [System.Collections.Generic.List[string]]::new()

$script:passCount = 0
$script:failCount = 0
$script:schema_drift_rejected_count = 0
$script:structural_forgery_rejected_count = 0
$script:undetected_schema_drift_count = 0
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

function Get-ValueKind {
    param($Value)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [string]) { return 'string' }
    if ($Value -is [bool]) { return 'boolean' }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [float] -or $Value -is [decimal]) { return 'number' }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string]) -and -not ($Value -is [pscustomobject])) { return 'array' }
    if ($Value -is [pscustomobject] -or $Value -is [hashtable]) { return 'object' }
    return 'scalar'
}

function Get-PropertyNames {
    param($Object)
    if ($null -eq $Object) { return @() }
    return @($Object.PSObject.Properties | ForEach-Object { $_.Name })
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

function Remove-Field {
    param(
        $Object,
        [string]$Name
    )

    if ($null -eq $Object) { return }
    [void]$Object.PSObject.Properties.Remove($Name)
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

function Test-StructuralObject {
    param(
        $Object,
        [string[]]$RequiredFields,
        [string[]]$AllowedFields,
        [hashtable]$ExpectedTypes,
        [string[]]$HashLikeFields,
        [string[]]$NonEmptyRequiredFields,
        [System.Collections.Generic.List[string]]$Vectors,
        [string]$ForgeryVector,
        [string]$ContextName
    )

    $contextInvalid = $false
    $actualFields = Get-PropertyNames -Object $Object

    foreach ($f in $actualFields) {
        if ($AllowedFields -notcontains $f) {
            Add-Vector -Vectors $Vectors -Value 'extra_field_injection'
            Add-Vector -Vectors $Vectors -Value $ForgeryVector
            Add-Vector -Vectors $Vectors -Value 'schema_drift'
            $contextInvalid = $true
        }
    }

    foreach ($f in $RequiredFields) {
        if ($actualFields -notcontains $f) {
            Add-Vector -Vectors $Vectors -Value 'missing_required_field'
            Add-Vector -Vectors $Vectors -Value $ForgeryVector
            Add-Vector -Vectors $Vectors -Value 'schema_drift'
            $contextInvalid = $true
            continue
        }

        $value = $Object.$f
        $kind = Get-ValueKind -Value $value
        $expectedKinds = @($ExpectedTypes[$f])

        if ($expectedKinds -notcontains $kind) {
            Add-Vector -Vectors $Vectors -Value 'field_type_drift'
            Add-Vector -Vectors $Vectors -Value $ForgeryVector
            Add-Vector -Vectors $Vectors -Value 'schema_drift'
            $contextInvalid = $true
        }
    }

    foreach ($f in $actualFields) {
        if (-not $ExpectedTypes.ContainsKey($f)) { continue }
        $isRequired = ($RequiredFields -contains $f)
        $isNonEmptyRequired = ($NonEmptyRequiredFields -contains $f)

        $value = $Object.$f
        $kind = Get-ValueKind -Value $value
        $expectedKinds = @($ExpectedTypes[$f])

        if ($isRequired -and ($expectedKinds -notcontains $kind)) {
            Add-Vector -Vectors $Vectors -Value 'field_type_drift'
            Add-Vector -Vectors $Vectors -Value $ForgeryVector
            Add-Vector -Vectors $Vectors -Value 'schema_drift'
            $contextInvalid = $true
        }

        if ($kind -eq 'string') {
            $trimmed = [string]$value
            if ($isNonEmptyRequired -and ($trimmed -eq '')) {
                Add-Vector -Vectors $Vectors -Value 'same_shape_compatibility_forgery'
                Add-Vector -Vectors $Vectors -Value $ForgeryVector
                $contextInvalid = $true
            }

            if ($HashLikeFields -contains $f) {
                if ($trimmed -notmatch '^[a-f0-9]{64}$') {
                    Add-Vector -Vectors $Vectors -Value 'field_type_drift'
                    Add-Vector -Vectors $Vectors -Value $ForgeryVector
                    Add-Vector -Vectors $Vectors -Value 'schema_drift'
                    $contextInvalid = $true
                }
            }
        }

        if ($isNonEmptyRequired -and $kind -eq 'string' -and ([string]$value -eq '')) {
            Add-Vector -Vectors $Vectors -Value 'same_shape_compatibility_forgery'
            Add-Vector -Vectors $Vectors -Value $ForgeryVector
            $contextInvalid = $true
        }
    }

    return $contextInvalid
}

function Get-ValidationVectors {
    param(
        [hashtable]$State,
        [hashtable]$Trusted
    )

    $vectors = [System.Collections.Generic.List[string]]::new()

    $ledgerInvalid = $false
    $art111Invalid = $false
    $art112Invalid = $false

    $entries = @($State.ledger.entries)
    if ($entries.Count -eq 0) {
        Add-Vector -Vectors $vectors -Value 'ledger_empty'
        return ,$vectors
    }

    $entriesKind = Get-ValueKind -Value $State.ledger.entries
    if ($entriesKind -ne 'array') {
        Add-Vector -Vectors $vectors -Value 'field_type_drift'
        Add-Vector -Vectors $vectors -Value 'schema_drift'
        Add-Vector -Vectors $vectors -Value 'structural_forgery'
        $ledgerInvalid = $true
    }

    for ($i = 0; $i -lt $entries.Count; $i++) {
        $entry = $entries[$i]
        $entryKind = Get-ValueKind -Value $entry
        if ($entryKind -ne 'object') {
            Add-Vector -Vectors $vectors -Value 'field_type_drift'
            Add-Vector -Vectors $vectors -Value 'schema_drift'
            Add-Vector -Vectors $vectors -Value 'structural_forgery'
            $ledgerInvalid = $true
            continue
        }

        $entryInvalid = Test-StructuralObject -Object $entry -RequiredFields $Trusted.entry_required_fields -AllowedFields $Trusted.entry_allowed_fields -ExpectedTypes $Trusted.entry_expected_types -HashLikeFields $Trusted.entry_hash_like_fields -NonEmptyRequiredFields $Trusted.entry_non_empty_required_fields -Vectors $vectors -ForgeryVector 'structural_forgery' -ContextName ('ledger.entry[' + $i + ']')
        if ($entryInvalid) { $ledgerInvalid = $true }

        if ($entry.PSObject.Properties['entry_id_alias']) {
            Add-Vector -Vectors $vectors -Value 'same_shape_compatibility_forgery'
            Add-Vector -Vectors $vectors -Value 'structural_forgery'
            $ledgerInvalid = $true
        }
    }

    $a111Kind = Get-ValueKind -Value $State.art111
    if ($a111Kind -ne 'object') {
        Add-Vector -Vectors $vectors -Value 'field_type_drift'
        Add-Vector -Vectors $vectors -Value 'schema_drift'
        Add-Vector -Vectors $vectors -Value 'structural_forgery'
        $art111Invalid = $true
    }
    else {
        $art111Invalid = Test-StructuralObject -Object $State.art111 -RequiredFields $Trusted.art111_expected_fields -AllowedFields $Trusted.art111_expected_fields -ExpectedTypes $Trusted.art111_expected_types -HashLikeFields $Trusted.art111_hash_like_fields -NonEmptyRequiredFields $Trusted.art111_non_empty_required_fields -Vectors $vectors -ForgeryVector 'structural_forgery' -ContextName 'art111'
        if ($State.art111.PSObject.Properties['latest_entry_alias']) {
            Add-Vector -Vectors $vectors -Value 'same_shape_compatibility_forgery'
            Add-Vector -Vectors $vectors -Value 'structural_forgery'
            $art111Invalid = $true
        }
    }

    $a112Kind = Get-ValueKind -Value $State.art112
    if ($a112Kind -ne 'object') {
        Add-Vector -Vectors $vectors -Value 'field_type_drift'
        Add-Vector -Vectors $vectors -Value 'schema_drift'
        Add-Vector -Vectors $vectors -Value 'structural_forgery'
        $art112Invalid = $true
    }
    else {
        $art112Invalid = Test-StructuralObject -Object $State.art112 -RequiredFields $Trusted.art112_expected_fields -AllowedFields $Trusted.art112_expected_fields -ExpectedTypes $Trusted.art112_expected_types -HashLikeFields $Trusted.art112_hash_like_fields -NonEmptyRequiredFields $Trusted.art112_non_empty_required_fields -Vectors $vectors -ForgeryVector 'structural_forgery' -ContextName 'art112'
    }

    if ((($ledgerInvalid -and (-not $art111Invalid -or -not $art112Invalid)) -or
         ($art111Invalid -and (-not $ledgerInvalid -or -not $art112Invalid)) -or
         ($art112Invalid -and (-not $ledgerInvalid -or -not $art111Invalid)))) {
        Add-Vector -Vectors $vectors -Value 'cross_artifact_structural_mismatch'
    }

    $chainSig = Build-ChainSignature -Entries $entries
    if ($chainSig -ne $Trusted.current_chain_signature) {
        Add-Vector -Vectors $vectors -Value 'lineage_break'
        Add-Vector -Vectors $vectors -Value 'continuity_break'
    }

    $ledgerHash = Get-LedgerSnapshotHash -Ledger $State.ledger
    if ($ledgerHash -ne $Trusted.current_ledger_snapshot_hash) {
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

    return @{ blocked = $false; runtime_executed = $true; stage = 'allow'; vectors = [System.Collections.Generic.List[string]]::new(); reason = 'canonical_structure_allow' }
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
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'BLOCK') { $script:schema_drift_rejected_count++ }
    if (($vectors -contains 'structural_forgery' -or $vectors -contains 'same_shape_compatibility_forgery' -or $vectors -contains 'field_type_drift') -and $actual -eq 'BLOCK') {
        $script:structural_forgery_rejected_count++
    }
    if ($ExpectedResult -eq 'BLOCK' -and $actual -eq 'ALLOW') { $script:undetected_schema_drift_count++ }
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
if ($entries.Count -eq 0) { throw 'Baseline ledger has no entries.' }

$entryExpectedFields = [System.Collections.Generic.List[string]]::new()
$entryRequiredFieldsSet = @{}
$entryExpectedTypes = @{}
$entryHashLikeFields = [System.Collections.Generic.List[string]]::new()
foreach ($f in (Get-PropertyNames -Object $entries[0])) { $entryRequiredFieldsSet[$f] = $true }
foreach ($entry in $entries) {
    $thisFields = @(Get-PropertyNames -Object $entry)
    $thisFieldSet = @{}
    foreach ($f2 in $thisFields) { $thisFieldSet[$f2] = $true }
    foreach ($rf in @($entryRequiredFieldsSet.Keys)) {
        if (-not $thisFieldSet.ContainsKey($rf)) {
            [void]$entryRequiredFieldsSet.Remove($rf)
        }
    }
    foreach ($f in $thisFields) {
        if (-not ($entryExpectedFields -contains $f)) { [void]$entryExpectedFields.Add($f) }
        $kind = Get-ValueKind -Value $entry.$f
        if (-not $entryExpectedTypes.ContainsKey($f)) {
            $entryExpectedTypes[$f] = [System.Collections.Generic.List[string]]::new()
        }
        if (-not ($entryExpectedTypes[$f] -contains $kind)) {
            [void]$entryExpectedTypes[$f].Add($kind)
        }
        if (($f -match 'hash') -and (-not ($entryHashLikeFields -contains $f))) {
            [void]$entryHashLikeFields.Add($f)
        }
    }
}

$art111ExpectedFields = @(Get-PropertyNames -Object $baselineArt111)
$art111ExpectedTypes = @{}
$art111HashLikeFields = [System.Collections.Generic.List[string]]::new()
foreach ($f in $art111ExpectedFields) {
    $v = $baselineArt111.$f
    $art111ExpectedTypes[$f] = Get-ValueKind -Value $v
    if ($f -match 'hash') { [void]$art111HashLikeFields.Add($f) }
}

$art112ExpectedFields = @(Get-PropertyNames -Object $baselineArt112)
$art112ExpectedTypes = @{}
$art112HashLikeFields = [System.Collections.Generic.List[string]]::new()
foreach ($f in $art112ExpectedFields) {
    $v = $baselineArt112.$f
    $art112ExpectedTypes[$f] = Get-ValueKind -Value $v
    if ($f -match 'hash') { [void]$art112HashLikeFields.Add($f) }
}

$trusted = @{
    current_ledger_length = $entries.Count
    current_latest_entry_id = [string]$entries[-1].entry_id
    current_ledger_snapshot_hash = Get-LedgerSnapshotHash -Ledger $baselineLedger
    current_chain_signature = Build-ChainSignature -Entries $entries
    current_art111_head_hash_anchor = [string]$baselineArt111.ledger_head_hash
    current_art112_head_hash_anchor = [string]$baselineArt112.ledger_head_hash
    entry_allowed_fields = $entryExpectedFields.ToArray()
    entry_required_fields = @($entryRequiredFieldsSet.Keys)
    entry_expected_types = $entryExpectedTypes
    entry_hash_like_fields = $entryHashLikeFields.ToArray()
    entry_non_empty_required_fields = @('entry_id', 'fingerprint_hash')
    art111_expected_fields = $art111ExpectedFields
    art111_expected_types = $art111ExpectedTypes
    art111_hash_like_fields = $art111HashLikeFields.ToArray()
    art111_non_empty_required_fields = @('latest_entry_id', 'ledger_head_hash')
    art112_expected_fields = $art112ExpectedFields
    art112_expected_types = $art112ExpectedTypes
    art112_hash_like_fields = $art112HashLikeFields.ToArray()
    art112_non_empty_required_fields = @('ledger_head_hash')
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

[void]$script:StructuralInvariantMap.Add('TRUSTED_CHAIN_LENGTH=' + $trusted.current_ledger_length)
[void]$script:StructuralInvariantMap.Add('TRUSTED_LATEST_ENTRY_ID=' + $trusted.current_latest_entry_id)
[void]$script:StructuralInvariantMap.Add('TRUSTED_LEDGER_HEAD_HASH=' + $trusted.current_ledger_snapshot_hash)
[void]$script:StructuralInvariantMap.Add('SCHEMA_RULE_1=no unauthorized fields allowed')
[void]$script:StructuralInvariantMap.Add('SCHEMA_RULE_2=all required fields must exist')
[void]$script:StructuralInvariantMap.Add('SCHEMA_RULE_3=field value kinds must match canonical kinds')
[void]$script:StructuralInvariantMap.Add('SCHEMA_RULE_4=hash-like fields must remain hash-shaped')
[void]$script:StructuralInvariantMap.Add('DETECTION_VECTOR_EXTRA_FIELD_INJECTION=enabled')
[void]$script:StructuralInvariantMap.Add('DETECTION_VECTOR_MISSING_REQUIRED_FIELD=enabled')
[void]$script:StructuralInvariantMap.Add('DETECTION_VECTOR_SAME_SHAPE_COMPATIBILITY_FORGERY=enabled')
[void]$script:StructuralInvariantMap.Add('DETECTION_VECTOR_FIELD_TYPE_DRIFT=enabled')
[void]$script:StructuralInvariantMap.Add('DETECTION_VECTOR_CROSS_ARTIFACT_STRUCTURAL_MISMATCH=enabled')

# A) Extra-field injection block
$stateA = New-LiveState
Set-FieldValue -Object $stateA.ledger.entries[0] -Name 'unauthorized_extra_field' -Value 'injected'
Set-FieldValue -Object $stateA.art111 -Name 'unauthorized_metadata_field' -Value 123
Set-FieldValue -Object $stateA.art112 -Name 'unauthorized_integrity_field' -Value 'x'
$resultA = Invoke-GuardedCycle -State $stateA -Trusted $trusted
Add-CaseResult -Id 'A' -Name 'extra_field_injection_block' -ExpectedResult 'BLOCK' -CycleResult $resultA

# B) Missing-field block
$stateB = New-LiveState
Remove-Field -Object $stateB.ledger.entries[1] -Name 'fingerprint_hash'
Remove-Field -Object $stateB.art111 -Name 'latest_entry_id'
Remove-Field -Object $stateB.art112 -Name 'ledger_head_hash'
$resultB = Invoke-GuardedCycle -State $stateB -Trusted $trusted
Add-CaseResult -Id 'B' -Name 'missing_field_block' -ExpectedResult 'BLOCK' -CycleResult $resultB

# C) Same-shape compatibility forgery
$stateC = New-LiveState
Set-FieldValue -Object $stateC.ledger.entries[0] -Name 'entry_id_alias' -Value ([string]$stateC.ledger.entries[0].entry_id)
Set-FieldValue -Object $stateC.ledger.entries[0] -Name 'entry_id' -Value ''
Set-FieldValue -Object $stateC.art111 -Name 'latest_entry_alias' -Value ([string]$stateC.art111.latest_entry_id)
Set-FieldValue -Object $stateC.art111 -Name 'latest_entry_id' -Value ''
Set-FieldValue -Object $stateC.art112 -Name 'source_artifact' -Value ''
$resultC = Invoke-GuardedCycle -State $stateC -Trusted $trusted
Add-CaseResult -Id 'C' -Name 'same_shape_compatibility_forgery' -ExpectedResult 'BLOCK' -CycleResult $resultC

# D) Field-type drift
$stateD = New-LiveState
Set-FieldValue -Object $stateD.ledger.entries[0] -Name 'entry_id' -Value 42
Set-FieldValue -Object $stateD.art111 -Name 'ledger_length' -Value '15'
Set-FieldValue -Object $stateD.art112 -Name 'source_artifact' -Value @('not', 'a', 'string')
Set-FieldValue -Object $stateD.art111 -Name 'ledger_head_hash' -Value 'non_hash_string'
$resultD = Invoke-GuardedCycle -State $stateD -Trusted $trusted
Add-CaseResult -Id 'D' -Name 'field_type_drift' -ExpectedResult 'BLOCK' -CycleResult $resultD

# E) Partial structural drift mismatch (ledger only)
$stateE = New-LiveState
Remove-Field -Object $stateE.ledger.entries[2] -Name 'previous_hash'
$resultE = Invoke-GuardedCycle -State $stateE -Trusted $trusted
Add-CaseResult -Id 'E' -Name 'partial_structural_drift_mismatch' -ExpectedResult 'BLOCK' -CycleResult $resultE

# F) Resealed structural forgery
$stateF = New-LiveState
Set-FieldValue -Object $stateF.ledger.entries[3] -Name 'forged_structural_marker' -Value 'resealed'
$stateF.art111.ledger_head_hash = Get-LedgerSnapshotHash -Ledger $stateF.ledger
$stateF.art112.ledger_head_hash = [string]$stateF.art111.ledger_head_hash
$stateF.art111.latest_entry_id = [string]$stateF.ledger.entries[-1].entry_id
$stateF.art111.ledger_length = $stateF.ledger.entries.Count
$resultF = Invoke-GuardedCycle -State $stateF -Trusted $trusted
Add-CaseResult -Id 'F' -Name 'resealed_structural_forgery' -ExpectedResult 'BLOCK' -CycleResult $resultF

# G) Guarded-boundary structural swap
$stateG = New-LiveState
$resultG = Invoke-GuardedCycle -State $stateG -Trusted $trusted -RuntimeMutation {
    param([hashtable]$State, [hashtable]$Trusted)
    Remove-Field -Object $State.art112 -Name 'source_artifact'
    Set-FieldValue -Object $State.art111 -Name 'schema_drift_placeholder' -Value 'boundary'
}
Add-CaseResult -Id 'G' -Name 'guarded_boundary_structural_swap' -ExpectedResult 'BLOCK' -CycleResult $resultG

# H) Clean control
$stateH = New-LiveState
$resultH = Invoke-GuardedCycle -State $stateH -Trusted $trusted
Add-CaseResult -Id 'H' -Name 'clean_control' -ExpectedResult 'ALLOW' -CycleResult $resultH

$consistencyPass = $true
if ($script:CaseMatrix.Count -ne 8) { $consistencyPass = $false }
if (($script:passCount + $script:failCount) -ne 8) { $consistencyPass = $false }
if ($script:undetected_schema_drift_count -ne 0) { $consistencyPass = $false }
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

$driftMatrix = @(
    'SCHEMA_DRIFT_MATRIX',
    'A: extra_field_injection_block => expect BLOCK',
    'B: missing_field_block => expect BLOCK',
    'C: same_shape_compatibility_forgery => expect BLOCK',
    'D: field_type_drift => expect BLOCK',
    'E: partial_structural_drift_mismatch => expect BLOCK',
    'F: resealed_structural_forgery => expect BLOCK',
    'G: guarded_boundary_structural_swap => expect BLOCK',
    'H: clean_control => expect ALLOW'
)

Write-ProofFile -Path (Join-Path $PF '01_status.txt') -Content @(
    'PHASE=53.22',
    'TITLE=' + $Title,
    'GATE=' + $gate,
    'PASS_COUNT=' + $script:passCount + '/8',
    'FAIL_COUNT=' + $script:failCount,
    'schema_drift_rejected_count=' + $script:schema_drift_rejected_count,
    'structural_forgery_rejected_count=' + $script:structural_forgery_rejected_count,
    'undetected_schema_drift_count=' + $script:undetected_schema_drift_count,
    'false_positive_count=' + $script:false_positive_count,
    'consistency_check=' + $(if ($consistencyPass) { 'PASS' } else { 'FAIL' }),
    'FAIL_CLOSED=TRUE',
    'NO_FALLBACK=TRUE',
    'NO_SILENT_ACCEPTANCE=TRUE'
)

Write-ProofFile -Path (Join-Path $PF '14_validation_results.txt') -Content $matrixLines
Write-ProofFile -Path (Join-Path $PF '15_schema_drift_matrix.txt') -Content $driftMatrix
Write-ProofFile -Path (Join-Path $PF '15_structural_invariant_map.txt') -Content $script:StructuralInvariantMap.ToArray()
Write-ProofFile -Path (Join-Path $PF '15_detection_vectors.txt') -Content $vectorLines

Write-ProofFile -Path (Join-Path $PF '98_gate_phase53_22.txt') -Content @(
    'GATE=' + $gate,
    'PASS_COUNT=' + $script:passCount + '/8',
    'FAIL_COUNT=' + $script:failCount,
    'schema_drift_rejected_count=' + $script:schema_drift_rejected_count,
    'structural_forgery_rejected_count=' + $script:structural_forgery_rejected_count,
    'undetected_schema_drift_count=' + $script:undetected_schema_drift_count,
    'false_positive_count=' + $script:false_positive_count
)

$zipPath = $PF + '.zip'
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path $PF -DestinationPath $zipPath -Force

Write-Output ('PF=' + $PF)
Write-Output ('ZIP=' + $zipPath)
Write-Output ('GATE=' + $gate)
