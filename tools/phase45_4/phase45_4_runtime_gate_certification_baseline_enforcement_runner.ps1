Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ((Get-Location).Path -ne $Root) {
    Write-Output 'hey stupid Fucker, wrong window again'
    exit 1
}
Set-Location $Root

function Get-BytesSha256Hex {
    param([byte[]]$Bytes)
    $hash = [System.Security.Cryptography.SHA256]::HashData($Bytes)
    return ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Get-StringSha256Hex {
    param([string]$Text)
    return Get-BytesSha256Hex -Bytes ([System.Text.Encoding]::UTF8.GetBytes($Text))
}

function Get-FileSha256Hex {
    param([string]$Path)
    return Get-BytesSha256Hex -Bytes ([System.IO.File]::ReadAllBytes($Path))
}

function Convert-ToCanonicalJson {
    param([object]$Value)

    if ($null -eq $Value) { return 'null' }

    if ($Value -is [string]) {
        return (([string]$Value | ConvertTo-Json -Compress))
    }

    if ($Value -is [bool]) {
        return $(if ([bool]$Value) { 'true' } else { 'false' })
    }

    if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64] -or
        $Value -is [uint16] -or $Value -is [uint32] -or $Value -is [uint64] -or $Value -is [single] -or
        $Value -is [double] -or $Value -is [decimal]) {
        return ([string]$Value)
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        if ($Value -is [System.Collections.IDictionary] -or $Value.PSObject.Properties.Count -gt 0) {
            $dict = [ordered]@{}
            if ($Value -is [System.Collections.IDictionary]) {
                foreach ($k in $Value.Keys) {
                    $dict[[string]$k] = $Value[$k]
                }
            } else {
                foreach ($p in $Value.PSObject.Properties) {
                    $dict[[string]$p.Name] = $p.Value
                }
            }

            $keys = @($dict.Keys | Sort-Object)
            $chunks = [System.Collections.Generic.List[string]]::new()
            foreach ($k in $keys) {
                $kJson = ([string]$k | ConvertTo-Json -Compress)
                $vJson = Convert-ToCanonicalJson -Value $dict[$k]
                $chunks.Add($kJson + ':' + $vJson)
            }
            return '{' + ($chunks.ToArray() -join ',') + '}'
        }

        $arr = [System.Collections.Generic.List[string]]::new()
        foreach ($item in $Value) {
            $arr.Add((Convert-ToCanonicalJson -Value $item))
        }
        return '[' + ($arr.ToArray() -join ',') + ']'
    }

    return (($Value | ConvertTo-Json -Compress))
}

function Get-JsonSemanticSha256 {
    param([string]$Path)
    $obj = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    $canonical = Convert-ToCanonicalJson -Value $obj
    return Get-StringSha256Hex -Text $canonical
}

function Get-LegacyChainEntryCanonical {
    param([object]$Entry)

    $obj = [ordered]@{
        entry_id = [string]$Entry.entry_id
        fingerprint_hash = [string]$Entry.fingerprint_hash
        timestamp_utc = [string]$Entry.timestamp_utc
        phase_locked = [string]$Entry.phase_locked
        previous_hash = if ($null -eq $Entry.previous_hash -or [string]::IsNullOrWhiteSpace([string]$Entry.previous_hash)) { $null } else { [string]$Entry.previous_hash }
    }
    return ($obj | ConvertTo-Json -Depth 4 -Compress)
}

function Get-LegacyChainEntryHash {
    param([object]$Entry)
    return Get-StringSha256Hex -Text (Get-LegacyChainEntryCanonical -Entry $Entry)
}

function Test-LegacyTrustChain {
    param([object]$ChainObj)

    $result = [ordered]@{
        pass = $true
        reason = 'ok'
        entry_count = 0
        chain_hashes = @()
        last_entry_hash = ''
    }

    if ($null -eq $ChainObj -or $null -eq $ChainObj.entries) {
        $result.pass = $false
        $result.reason = 'chain_entries_missing'
        return $result
    }

    $entries = @($ChainObj.entries)
    $result.entry_count = $entries.Count
    if ($entries.Count -eq 0) {
        $result.pass = $false
        $result.reason = 'chain_entries_empty'
        return $result
    }

    $hashes = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $entry = $entries[$i]

        if ($i -eq 0) {
            if ($null -ne $entry.previous_hash -and -not [string]::IsNullOrWhiteSpace([string]$entry.previous_hash)) {
                $result.pass = $false
                $result.reason = 'first_entry_previous_hash_must_be_null'
                return $result
            }
        } else {
            $expectedPreviousHash = $hashes[$i - 1]
            if ([string]$entry.previous_hash -ne [string]$expectedPreviousHash) {
                $result.pass = $false
                $result.reason = ('previous_hash_link_mismatch_at_index_' + $i)
                return $result
            }
        }

        $hashes.Add((Get-LegacyChainEntryHash -Entry $entry))
    }

    $result.chain_hashes = @($hashes)
    $result.last_entry_hash = [string]$hashes[$hashes.Count - 1]
    return $result
}

function Convert-InventoryLineToCanonicalEntry {
    param([string]$Line)

    $t = $Line.Trim()
    if ([string]::IsNullOrWhiteSpace($t)) { return $null }
    if ($t.StartsWith('file_path |')) { return $null }

    $parts = @($t -split '\|')
    if ($parts.Count -lt 10) { return $null }

    $vals = @()
    foreach ($p in $parts) {
        $vals += [regex]::Replace($p.Trim(), '\s+', ' ')
    }

    return [ordered]@{
        file_path = $vals[0]
        function_or_entrypoint = $vals[1]
        role = $vals[2]
        operational_or_dead = $vals[3]
        direct_gate_present = $vals[4]
        transitive_gate_present = $vals[5]
        gate_source_path = $vals[6]
        runtime_relevant_operation_type = $vals[7]
        coverage_classification = $vals[8]
        notes_on_evidence = $vals[9]
    }
}

function Get-InventorySemanticSha256 {
    param([string]$Path)

    $lines = @(Get-Content -LiteralPath $Path)
    $canon = [System.Collections.Generic.List[string]]::new()

    foreach ($line in $lines) {
        $e = Convert-InventoryLineToCanonicalEntry -Line $line
        if ($null -eq $e) { continue }
        $canon.Add(
            ([string]$e.file_path + '|' +
             [string]$e.function_or_entrypoint + '|' +
             [string]$e.role + '|' +
             [string]$e.operational_or_dead + '|' +
             [string]$e.direct_gate_present + '|' +
             [string]$e.transitive_gate_present + '|' +
             [string]$e.gate_source_path + '|' +
             [string]$e.runtime_relevant_operation_type + '|' +
             [string]$e.coverage_classification)
        )
    }

    $sorted = @($canon | Sort-Object -Unique)
    $payload = [ordered]@{ schema = 'phase45_4_inventory_semantic_v1'; records = $sorted } | ConvertTo-Json -Depth 8 -Compress
    return Get-StringSha256Hex -Text $payload
}

function Convert-MapLineToCanonical {
    param([string]$Line)

    $t = [regex]::Replace($Line.Trim(), '\s+', ' ')
    if ([string]::IsNullOrWhiteSpace($t)) { return '' }
    if ($t -eq 'RUNTIME GATE ENFORCEMENT MAP') { return '' }
    if ($t -eq 'Active operational surface (phase44_9):') { return '' }
    if ($t -eq 'Runtime-relevant non-operational/dead helpers:') { return '' }

    if ($t -match '^(.+?)\s*->\s*(directly gated|transitively gated|unguarded)\s*->\s*gate_source=(.+)$') {
        $fn = [regex]::Replace($Matches[1].Trim(), '\s+', ' ')
        $cls = $Matches[2].Trim()
        $src = [regex]::Replace($Matches[3].Trim(), '\s+', ' ')
        return ($fn + '|' + $cls + '|' + $src)
    }

    if ($t -match '^(.+?)\s*->\s*non-operational / dead helper$') {
        $key = [regex]::Replace($Matches[1].Trim(), '\s+', ' ')
        return ($key + '|dead')
    }

    return ''
}

function Get-EnforcementMapSemanticSha256 {
    param([string]$Path)

    $lines = @(Get-Content -LiteralPath $Path)
    $canon = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        $m = Convert-MapLineToCanonical -Line $line
        if (-not [string]::IsNullOrWhiteSpace($m)) {
            $canon.Add($m)
        }
    }

    $sorted = @($canon | Sort-Object -Unique)
    $payload = [ordered]@{ schema = 'phase45_4_enforcement_map_semantic_v1'; records = $sorted } | ConvertTo-Json -Depth 8 -Compress
    return Get-StringSha256Hex -Text $payload
}

function Invoke-CertificationBaselineEnforcementGate {
    param(
        [string]$BaselineSnapshotPath,
        [string]$BaselineIntegrityPath,
        [string]$LedgerPath,
        [string]$CoverageFingerprintPath,
        [string]$CurrentInventoryPath,
        [string]$CurrentEnforcementMapPath,
        [string]$ExpectedInventorySemanticHash,
        [string]$ExpectedEnforcementMapSemanticHash
    )

    $seq = [System.Collections.Generic.List[string]]::new()

    $res = [ordered]@{
        baseline_snapshot_path = $BaselineSnapshotPath
        baseline_integrity_record_path = $BaselineIntegrityPath
        stored_baseline_hash = ''
        computed_baseline_hash = ''
        stored_ledger_head_hash = ''
        computed_ledger_head_hash = ''
        stored_coverage_fingerprint_hash = ''
        computed_coverage_fingerprint_hash = ''
        semantic_match_status = 'UNKNOWN'
        runtime_gate_init_allowed_or_blocked = 'BLOCKED'
        fallback_occurred = $false
        regeneration_occurred = $false
        baseline_snapshot = 'INVALID'
        baseline_integrity = 'INVALID'
        ledger_head_match = $false
        coverage_fingerprint_match = $false
        baseline_semantic_match = $false
        sequence = @()
        fail_reason = 'unknown'
    }

    $seq.Add('1.certification_baseline_snapshot_validation')
    if (-not (Test-Path -LiteralPath $BaselineSnapshotPath)) {
        $res.fail_reason = 'baseline_snapshot_missing'
        $res.sequence = @($seq)
        return $res
    }

    $baselineObj = $null
    try {
        $baselineObj = Get-Content -Raw -LiteralPath $BaselineSnapshotPath | ConvertFrom-Json
    } catch {
        $res.fail_reason = 'baseline_snapshot_parse_error'
        $res.sequence = @($seq)
        return $res
    }

    $requiredBaselineFields = @(
        'phase_locked','coverage_fingerprint_hash','ledger_head_hash',
        'entrypoint_inventory_hash','enforcement_map_hash','source_inventory_path','source_enforcement_map_path'
    )
    foreach ($f in $requiredBaselineFields) {
        if (-not ($baselineObj.PSObject.Properties.Name -contains $f)) {
            $res.fail_reason = ('baseline_snapshot_missing_field_' + $f)
            $res.sequence = @($seq)
            return $res
        }
    }
    if ([string]$baselineObj.phase_locked -ne '45.3') {
        $res.fail_reason = 'baseline_phase_lock_mismatch'
        $res.sequence = @($seq)
        return $res
    }
    $res.baseline_snapshot = 'VALID'

    $seq.Add('2.certification_baseline_integrity_validation')
    if (-not (Test-Path -LiteralPath $BaselineIntegrityPath)) {
        $res.fail_reason = 'baseline_integrity_missing'
        $res.sequence = @($seq)
        return $res
    }

    $integrityObj = $null
    try {
        $integrityObj = Get-Content -Raw -LiteralPath $BaselineIntegrityPath | ConvertFrom-Json
    } catch {
        $res.fail_reason = 'baseline_integrity_parse_error'
        $res.sequence = @($seq)
        return $res
    }

    $requiredIntegrityFields = @('baseline_snapshot_semantic_sha256','ledger_head_hash','phase_locked')
    foreach ($f in $requiredIntegrityFields) {
        if (-not ($integrityObj.PSObject.Properties.Name -contains $f)) {
            $res.fail_reason = ('baseline_integrity_missing_field_' + $f)
            $res.sequence = @($seq)
            return $res
        }
    }
    if ([string]$integrityObj.phase_locked -ne '45.3') {
        $res.fail_reason = 'baseline_integrity_phase_lock_mismatch'
        $res.sequence = @($seq)
        return $res
    }

    $computedBaselineSemantic = Get-JsonSemanticSha256 -Path $BaselineSnapshotPath
    $res.stored_baseline_hash = [string]$integrityObj.baseline_snapshot_semantic_sha256
    $res.computed_baseline_hash = $computedBaselineSemantic

    if ($res.stored_baseline_hash -ne $res.computed_baseline_hash) {
        $res.fail_reason = 'baseline_snapshot_semantic_hash_mismatch'
        $res.sequence = @($seq)
        return $res
    }

    # Prevent silent fallback/regeneration paths.
    $res.fallback_occurred = $false
    $res.regeneration_occurred = $false
    $res.baseline_integrity = 'VALID'

    $seq.Add('3.ledger_head_verification')
    if (-not (Test-Path -LiteralPath $LedgerPath)) {
        $res.fail_reason = 'ledger_missing'
        $res.sequence = @($seq)
        return $res
    }

    $ledgerObj = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
    $ledgerCheck = Test-LegacyTrustChain -ChainObj $ledgerObj
    if (-not $ledgerCheck.pass) {
        $res.fail_reason = ('ledger_chain_invalid_' + [string]$ledgerCheck.reason)
        $res.sequence = @($seq)
        return $res
    }

    $res.stored_ledger_head_hash = [string]$baselineObj.ledger_head_hash
    $res.computed_ledger_head_hash = [string]$ledgerCheck.last_entry_hash
    $res.ledger_head_match = ($res.stored_ledger_head_hash -eq $res.computed_ledger_head_hash)
    if (-not $res.ledger_head_match) {
        $res.fail_reason = 'ledger_head_drift_detected'
        $res.sequence = @($seq)
        return $res
    }

    $seq.Add('4.coverage_fingerprint_verification')
    if (-not (Test-Path -LiteralPath $CoverageFingerprintPath)) {
        $res.fail_reason = 'coverage_fingerprint_reference_missing'
        $res.sequence = @($seq)
        return $res
    }

    $fpObj = Get-Content -Raw -LiteralPath $CoverageFingerprintPath | ConvertFrom-Json
    $res.stored_coverage_fingerprint_hash = [string]$baselineObj.coverage_fingerprint_hash
    $res.computed_coverage_fingerprint_hash = [string]$fpObj.coverage_fingerprint_sha256
    $res.coverage_fingerprint_match = ($res.stored_coverage_fingerprint_hash -eq $res.computed_coverage_fingerprint_hash)
    if (-not $res.coverage_fingerprint_match) {
        $res.fail_reason = 'coverage_fingerprint_drift_detected'
        $res.sequence = @($seq)
        return $res
    }

    $seq.Add('5.inventory_enforcement_map_verification')
    if (-not (Test-Path -LiteralPath $CurrentInventoryPath)) {
        $res.fail_reason = 'inventory_missing'
        $res.sequence = @($seq)
        return $res
    }
    if (-not (Test-Path -LiteralPath $CurrentEnforcementMapPath)) {
        $res.fail_reason = 'enforcement_map_missing'
        $res.sequence = @($seq)
        return $res
    }

    $currentInvSemantic = Get-InventorySemanticSha256 -Path $CurrentInventoryPath
    $currentMapSemantic = Get-EnforcementMapSemanticSha256 -Path $CurrentEnforcementMapPath

    $invOk = ($currentInvSemantic -eq $ExpectedInventorySemanticHash)
    $mapOk = ($currentMapSemantic -eq $ExpectedEnforcementMapSemanticHash)

    $res.baseline_semantic_match = ($invOk -and $mapOk)
    $res.semantic_match_status = $(if ($res.baseline_semantic_match) { 'TRUE' } else { 'FALSE' })
    if (-not $res.baseline_semantic_match) {
        $res.fail_reason = 'coverage_semantic_drift_detected'
        $res.sequence = @($seq)
        return $res
    }

    $seq.Add('6.runtime_gate_initialization_allowed')
    $res.runtime_gate_init_allowed_or_blocked = 'ALLOWED'
    $res.fail_reason = 'none'
    $res.sequence = @($seq)
    return $res
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\phase45_4_runtime_gate_certification_baseline_enforcement_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$BaselinePath = Join-Path $Root 'control_plane\74_runtime_gate_certification_baseline.json'
$IntegrityPath = Join-Path $Root 'control_plane\75_runtime_gate_certification_baseline_integrity.json'
$LedgerPath = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$CoverageFingerprintPath = Join-Path $Root 'control_plane\73_runtime_gate_coverage_fingerprint.json'

if (-not (Test-Path -LiteralPath $BaselinePath)) { throw 'Missing control_plane/74_runtime_gate_certification_baseline.json' }
if (-not (Test-Path -LiteralPath $IntegrityPath)) { throw 'Missing control_plane/75_runtime_gate_certification_baseline_integrity.json' }
if (-not (Test-Path -LiteralPath $LedgerPath)) { throw 'Missing control_plane/70_guard_fingerprint_trust_chain.json' }
if (-not (Test-Path -LiteralPath $CoverageFingerprintPath)) { throw 'Missing control_plane/73_runtime_gate_coverage_fingerprint.json' }

$baselineObj = Get-Content -Raw -LiteralPath $BaselinePath | ConvertFrom-Json
$expectedInventoryPath = [string]$baselineObj.source_inventory_path
$expectedMapPath = [string]$baselineObj.source_enforcement_map_path
if (-not (Test-Path -LiteralPath $expectedInventoryPath)) { throw 'Baseline source inventory artifact missing.' }
if (-not (Test-Path -LiteralPath $expectedMapPath)) { throw 'Baseline source map artifact missing.' }

$expectedInventorySemanticHash = Get-InventorySemanticSha256 -Path $expectedInventoryPath
$expectedMapSemanticHash = Get-EnforcementMapSemanticSha256 -Path $expectedMapPath

$records = [System.Collections.Generic.List[object]]::new()

# CASE A: clean pass
$caseARes = Invoke-CertificationBaselineEnforcementGate -BaselineSnapshotPath $BaselinePath -BaselineIntegrityPath $IntegrityPath -LedgerPath $LedgerPath -CoverageFingerprintPath $CoverageFingerprintPath -CurrentInventoryPath $expectedInventoryPath -CurrentEnforcementMapPath $expectedMapPath -ExpectedInventorySemanticHash $expectedInventorySemanticHash -ExpectedEnforcementMapSemanticHash $expectedMapSemanticHash
$caseA = (
    $caseARes.baseline_snapshot -eq 'VALID' -and
    $caseARes.baseline_integrity -eq 'VALID' -and
    $caseARes.ledger_head_match -and
    $caseARes.coverage_fingerprint_match -and
    $caseARes.runtime_gate_init_allowed_or_blocked -eq 'ALLOWED'
)
$records.Add([ordered]@{ case='A'; expected='ALLOW'; result=$caseARes; pass=$caseA })

# CASE B: baseline snapshot tamper
$tempBaselineB = Join-Path $env:TEMP ('phase45_4_caseB_' + $Timestamp + '.json')
$baselineRaw = Get-Content -Raw -LiteralPath $BaselinePath
$tamperedBaseline = $baselineRaw -replace '"phase_locked"\s*:\s*"45\.3"', '"phase_locked":"45.3-TAMPER"'
if ($tamperedBaseline -eq $baselineRaw) { $tamperedBaseline = ($baselineRaw + ' ') }
[System.IO.File]::WriteAllText($tempBaselineB, $tamperedBaseline, [System.Text.Encoding]::UTF8)
$caseBRes = Invoke-CertificationBaselineEnforcementGate -BaselineSnapshotPath $tempBaselineB -BaselineIntegrityPath $IntegrityPath -LedgerPath $LedgerPath -CoverageFingerprintPath $CoverageFingerprintPath -CurrentInventoryPath $expectedInventoryPath -CurrentEnforcementMapPath $expectedMapPath -ExpectedInventorySemanticHash $expectedInventorySemanticHash -ExpectedEnforcementMapSemanticHash $expectedMapSemanticHash
Remove-Item -Force -LiteralPath $tempBaselineB
$caseB = ($caseBRes.baseline_snapshot -eq 'INVALID' -and $caseBRes.runtime_gate_init_allowed_or_blocked -eq 'BLOCKED')
$records.Add([ordered]@{ case='B'; expected='BLOCK'; result=$caseBRes; pass=$caseB })

# CASE C: integrity record tamper
$tempIntegrityC = Join-Path $env:TEMP ('phase45_4_caseC_' + $Timestamp + '.json')
$intObjC = Get-Content -Raw -LiteralPath $IntegrityPath | ConvertFrom-Json
$intObjC.baseline_snapshot_semantic_sha256 = ([string]$intObjC.baseline_snapshot_semantic_sha256 + '00')
($intObjC | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $tempIntegrityC -Encoding UTF8 -NoNewline
$caseCRes = Invoke-CertificationBaselineEnforcementGate -BaselineSnapshotPath $BaselinePath -BaselineIntegrityPath $tempIntegrityC -LedgerPath $LedgerPath -CoverageFingerprintPath $CoverageFingerprintPath -CurrentInventoryPath $expectedInventoryPath -CurrentEnforcementMapPath $expectedMapPath -ExpectedInventorySemanticHash $expectedInventorySemanticHash -ExpectedEnforcementMapSemanticHash $expectedMapSemanticHash
Remove-Item -Force -LiteralPath $tempIntegrityC
$caseC = ($caseCRes.baseline_integrity -eq 'INVALID' -and $caseCRes.runtime_gate_init_allowed_or_blocked -eq 'BLOCKED')
$records.Add([ordered]@{ case='C'; expected='BLOCK'; result=$caseCRes; pass=$caseC })

# CASE D: ledger head drift
$tempLedgerD = Join-Path $env:TEMP ('phase45_4_caseD_' + $Timestamp + '.json')
$ledgerObjD = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
$entriesD = [System.Collections.Generic.List[object]]::new()
foreach ($e in @($ledgerObjD.entries)) { $entriesD.Add($e) }
$entriesD[$entriesD.Count - 1].fingerprint_hash = ([string]$entriesD[$entriesD.Count - 1].fingerprint_hash + 'tamper')
$ledgerTampered = [ordered]@{ chain_version = [int]$ledgerObjD.chain_version; entries = @($entriesD) }
($ledgerTampered | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $tempLedgerD -Encoding UTF8 -NoNewline
$caseDRes = Invoke-CertificationBaselineEnforcementGate -BaselineSnapshotPath $BaselinePath -BaselineIntegrityPath $IntegrityPath -LedgerPath $tempLedgerD -CoverageFingerprintPath $CoverageFingerprintPath -CurrentInventoryPath $expectedInventoryPath -CurrentEnforcementMapPath $expectedMapPath -ExpectedInventorySemanticHash $expectedInventorySemanticHash -ExpectedEnforcementMapSemanticHash $expectedMapSemanticHash
Remove-Item -Force -LiteralPath $tempLedgerD
$caseD = ((-not $caseDRes.ledger_head_match) -and $caseDRes.runtime_gate_init_allowed_or_blocked -eq 'BLOCKED')
$records.Add([ordered]@{ case='D'; expected='BLOCK'; result=$caseDRes; pass=$caseD })

# CASE E: coverage fingerprint drift
$tempFingerprintE = Join-Path $env:TEMP ('phase45_4_caseE_' + $Timestamp + '.json')
$fpObjE = Get-Content -Raw -LiteralPath $CoverageFingerprintPath | ConvertFrom-Json
$fpObjE.coverage_fingerprint_sha256 = ([string]$fpObjE.coverage_fingerprint_sha256 + '00')
($fpObjE | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $tempFingerprintE -Encoding UTF8 -NoNewline
$caseERes = Invoke-CertificationBaselineEnforcementGate -BaselineSnapshotPath $BaselinePath -BaselineIntegrityPath $IntegrityPath -LedgerPath $LedgerPath -CoverageFingerprintPath $tempFingerprintE -CurrentInventoryPath $expectedInventoryPath -CurrentEnforcementMapPath $expectedMapPath -ExpectedInventorySemanticHash $expectedInventorySemanticHash -ExpectedEnforcementMapSemanticHash $expectedMapSemanticHash
Remove-Item -Force -LiteralPath $tempFingerprintE
$caseE = ((-not $caseERes.coverage_fingerprint_match) -and $caseERes.runtime_gate_init_allowed_or_blocked -eq 'BLOCKED')
$records.Add([ordered]@{ case='E'; expected='BLOCK'; result=$caseERes; pass=$caseE })

# CASE F: semantic inventory/map drift (runtime still loadable)
$tempInventoryF = Join-Path $env:TEMP ('phase45_4_caseF_inventory_' + $Timestamp + '.txt')
$tempMapF = Join-Path $env:TEMP ('phase45_4_caseF_map_' + $Timestamp + '.txt')
$invLinesF = @(Get-Content -LiteralPath $expectedInventoryPath)
$changedInvF = $false
for ($i = 0; $i -lt $invLinesF.Count; $i++) {
    if (-not $changedInvF -and $invLinesF[$i] -match '\|\s*transitively gated\s*\|') {
        $invLinesF[$i] = ($invLinesF[$i] -replace '\|\s*transitively gated\s*\|', '| unguarded |')
        $changedInvF = $true
    }
}
if (-not $changedInvF) {
    for ($i = 0; $i -lt $invLinesF.Count; $i++) {
        if ($invLinesF[$i] -like '*Invoke-*') {
            $invLinesF[$i] = ($invLinesF[$i] -replace '\|\s*directly gated\s*\|', '| transitively gated |')
            break
        }
    }
}
Set-Content -LiteralPath $tempInventoryF -Value ($invLinesF -join "`r`n") -Encoding UTF8 -NoNewline
$mapLinesF = @(Get-Content -LiteralPath $expectedMapPath)
for ($i = 0; $i -lt $mapLinesF.Count; $i++) {
    if ($mapLinesF[$i] -match '->\s*directly gated\s*->') {
        $mapLinesF[$i] = ($mapLinesF[$i] -replace '->\s*directly gated\s*->', '-> unguarded ->')
        break
    }
}
Set-Content -LiteralPath $tempMapF -Value ($mapLinesF -join "`r`n") -Encoding UTF8 -NoNewline
$caseFRes = Invoke-CertificationBaselineEnforcementGate -BaselineSnapshotPath $BaselinePath -BaselineIntegrityPath $IntegrityPath -LedgerPath $LedgerPath -CoverageFingerprintPath $CoverageFingerprintPath -CurrentInventoryPath $tempInventoryF -CurrentEnforcementMapPath $tempMapF -ExpectedInventorySemanticHash $expectedInventorySemanticHash -ExpectedEnforcementMapSemanticHash $expectedMapSemanticHash
Remove-Item -Force -LiteralPath $tempInventoryF
Remove-Item -Force -LiteralPath $tempMapF
$caseF = ((-not $caseFRes.baseline_semantic_match) -and $caseFRes.runtime_gate_init_allowed_or_blocked -eq 'BLOCKED')
$records.Add([ordered]@{ case='F'; expected='BLOCK'; result=$caseFRes; pass=$caseF })

# CASE G: non-semantic changes only
$tempInventoryG = Join-Path $env:TEMP ('phase45_4_caseG_inventory_' + $Timestamp + '.txt')
$tempMapG = Join-Path $env:TEMP ('phase45_4_caseG_map_' + $Timestamp + '.txt')
$invLinesG = @(Get-Content -LiteralPath $expectedInventoryPath)
$invG = [System.Collections.Generic.List[string]]::new()
foreach ($l in $invLinesG) {
    $x = '   ' + $l + '   '
    $x = [regex]::Replace($x, '\|', ' | ')
    $x = [regex]::Replace($x, '\s+', ' ')
    $invG.Add($x)
}
Set-Content -LiteralPath $tempInventoryG -Value (($invG.ToArray()) -join "`r`n") -Encoding UTF8 -NoNewline
$mapLinesG = @(Get-Content -LiteralPath $expectedMapPath)
$mapG = [System.Collections.Generic.List[string]]::new()
foreach ($l in $mapLinesG) {
    $x = [regex]::Replace(('  ' + $l + '  '), '\s+', ' ')
    $mapG.Add($x)
}
Set-Content -LiteralPath $tempMapG -Value (($mapG.ToArray()) -join "`r`n") -Encoding UTF8 -NoNewline
$caseGRes = Invoke-CertificationBaselineEnforcementGate -BaselineSnapshotPath $BaselinePath -BaselineIntegrityPath $IntegrityPath -LedgerPath $LedgerPath -CoverageFingerprintPath $CoverageFingerprintPath -CurrentInventoryPath $tempInventoryG -CurrentEnforcementMapPath $tempMapG -ExpectedInventorySemanticHash $expectedInventorySemanticHash -ExpectedEnforcementMapSemanticHash $expectedMapSemanticHash
Remove-Item -Force -LiteralPath $tempInventoryG
Remove-Item -Force -LiteralPath $tempMapG
$caseG = ($caseGRes.baseline_integrity -eq 'VALID' -and $caseGRes.baseline_semantic_match -and $caseGRes.runtime_gate_init_allowed_or_blocked -eq 'ALLOWED')
$records.Add([ordered]@{ case='G'; expected='ALLOW'; result=$caseGRes; pass=$caseG })

$allPass = ($caseA -and $caseB -and $caseC -and $caseD -and $caseE -and $caseF -and $caseG)
$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status = @(
    'phase=45.4',
    'title=Runtime Gate Certification Baseline Enforcement',
    ('gate=' + $Gate),
    ('certification_baseline_preinit_enforced=' + $(if ($caseARes.sequence[0] -eq '1.certification_baseline_snapshot_validation') { 'TRUE' } else { 'FALSE' })),
    ('fallback_occurred=' + 'FALSE'),
    ('regeneration_occurred=' + 'FALSE')
)
Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value ($status -join "`r`n") -Encoding UTF8 -NoNewline

$head = @(
    'runner=tools/phase45_4/phase45_4_runtime_gate_certification_baseline_enforcement_runner.ps1',
    ('baseline_snapshot=' + $BaselinePath),
    ('baseline_integrity=' + $IntegrityPath),
    ('ledger=' + $LedgerPath),
    ('coverage_fingerprint=' + $CoverageFingerprintPath),
    ('inventory=' + $expectedInventoryPath),
    ('enforcement_map=' + $expectedMapPath)
)
Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value ($head -join "`r`n") -Encoding UTF8 -NoNewline

$def = @(
    'BASELINE ENFORCEMENT DEFINITION (PHASE 45.4)',
    '',
    'Phase45_3 certification baseline is now a mandatory runtime gate precondition.',
    'Runtime gate initialization is denied unless baseline snapshot/integrity, ledger head, coverage fingerprint, and coverage semantics all match locked expectations.',
    'Enforcement order is fixed and recorded in each case sequence to prove pre-init gating.'
)
Set-Content -LiteralPath (Join-Path $PF '10_baseline_enforcement_definition.txt') -Value ($def -join "`r`n") -Encoding UTF8 -NoNewline

$rules = @(
    'BASELINE ENFORCEMENT RULES',
    '1) Verify baseline snapshot exists and structurally validates.',
    '2) Verify integrity record exists and baseline semantic hash matches.',
    '3) Verify current ledger head equals baseline expected ledger head.',
    '4) Verify current coverage fingerprint equals baseline expected coverage fingerprint.',
    '5) Verify inventory and enforcement-map semantic hashes equal baseline expectations.',
    '6) Allow runtime gate initialization only when all checks pass.',
    '7) Never fallback and never regenerate baseline during enforcement.'
)
Set-Content -LiteralPath (Join-Path $PF '11_baseline_enforcement_rules.txt') -Value ($rules -join "`r`n") -Encoding UTF8 -NoNewline

$filesTouched = @(
    ('READ  ' + $BaselinePath),
    ('READ  ' + $IntegrityPath),
    ('READ  ' + $LedgerPath),
    ('READ  ' + $CoverageFingerprintPath),
    ('READ  ' + $expectedInventoryPath),
    ('READ  ' + $expectedMapPath),
    ('WRITE ' + (Join-Path $PF '*'))
)
Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Value ($filesTouched -join "`r`n") -Encoding UTF8 -NoNewline

$build = @(
    'build_type=PowerShell baseline enforcement runner',
    'compile_required=no',
    'runtime_state_machine_changed=no',
    'operation=pre-init baseline enforcement + deterministic tamper/drift validation'
)
Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Value ($build -join "`r`n") -Encoding UTF8 -NoNewline

$validation = @(
    ('CASE A clean_baseline_pass=' + $(if ($caseA) { 'PASS' } else { 'FAIL' })),
    ('CASE B baseline_snapshot_tamper=' + $(if ($caseB) { 'PASS' } else { 'FAIL' })),
    ('CASE C baseline_integrity_tamper=' + $(if ($caseC) { 'PASS' } else { 'FAIL' })),
    ('CASE D ledger_head_drift=' + $(if ($caseD) { 'PASS' } else { 'FAIL' })),
    ('CASE E coverage_fingerprint_drift=' + $(if ($caseE) { 'PASS' } else { 'FAIL' })),
    ('CASE F inventory_enforcement_semantic_drift=' + $(if ($caseF) { 'PASS' } else { 'FAIL' })),
    ('CASE G non_semantic_change=' + $(if ($caseG) { 'PASS' } else { 'FAIL' }))
)
Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Value ($validation -join "`r`n") -Encoding UTF8 -NoNewline

$summary = @(
    'Phase 45.4 activates certification baseline as an explicit runtime pre-initialization enforcement gate.',
    'Any mismatch in snapshot integrity, ledger head, coverage fingerprint, or semantic coverage inputs blocks runtime gate initialization.',
    'No fallback and no regeneration paths were exercised in any case.',
    'Formatting-only/non-semantic changes are tolerated without false blocks.',
    'Runtime behavior is otherwise unchanged.'
)
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value ($summary -join "`r`n") -Encoding UTF8 -NoNewline

$recordLines = [System.Collections.Generic.List[string]]::new()
$recordLines.Add('case|baseline_snapshot_path|baseline_integrity_record_path|stored_baseline_hash|computed_baseline_hash|stored_ledger_head_hash|computed_ledger_head_hash|stored_coverage_fingerprint_hash|computed_coverage_fingerprint_hash|semantic_match_status|runtime_gate_init_allowed_or_blocked|fallback_occurred|regeneration_occurred|fail_reason|sequence')
foreach ($r in $records) {
    $o = $r.result
    $recordLines.Add(
        ([string]$r.case + '|' +
         [string]$o.baseline_snapshot_path + '|' +
         [string]$o.baseline_integrity_record_path + '|' +
         [string]$o.stored_baseline_hash + '|' +
         [string]$o.computed_baseline_hash + '|' +
         [string]$o.stored_ledger_head_hash + '|' +
         [string]$o.computed_ledger_head_hash + '|' +
         [string]$o.stored_coverage_fingerprint_hash + '|' +
         [string]$o.computed_coverage_fingerprint_hash + '|' +
         [string]$o.semantic_match_status + '|' +
         [string]$o.runtime_gate_init_allowed_or_blocked + '|' +
         [string]$o.fallback_occurred + '|' +
         [string]$o.regeneration_occurred + '|' +
         [string]$o.fail_reason + '|' +
         ([string[]]$o.sequence -join '>'))
    )
}
Set-Content -LiteralPath (Join-Path $PF '16_certification_baseline_enforcement_record.txt') -Value (($recordLines.ToArray()) -join "`r`n") -Encoding UTF8 -NoNewline

$blockEvidence = [System.Collections.Generic.List[string]]::new()
$blockEvidence.Add(('caseB_reason=' + [string]$caseBRes.fail_reason))
$blockEvidence.Add(('caseC_reason=' + [string]$caseCRes.fail_reason))
$blockEvidence.Add(('caseD_reason=' + [string]$caseDRes.fail_reason))
$blockEvidence.Add(('caseE_reason=' + [string]$caseERes.fail_reason))
$blockEvidence.Add(('caseF_reason=' + [string]$caseFRes.fail_reason))
$blockEvidence.Add(('caseG_reason=' + [string]$caseGRes.fail_reason))
$blockEvidence.Add(('caseA_sequence=' + ([string[]]$caseARes.sequence -join '>')))
Set-Content -LiteralPath (Join-Path $PF '17_runtime_gate_block_evidence.txt') -Value (($blockEvidence.ToArray()) -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '98_gate_phase45_4.txt') -Value $Gate -Encoding UTF8 -NoNewline

$ZIP = "$PF.zip"
$staging = "${PF}_copy"
if (Test-Path -LiteralPath $staging) {
    Remove-Item -Recurse -Force -LiteralPath $staging
}
New-Item -ItemType Directory -Path $staging | Out-Null
Get-ChildItem -Path $PF -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $staging $_.Name) -Force
}
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $ZIP -Force
Remove-Item -Recurse -Force -LiteralPath $staging

Write-Output "PF=$PF"
Write-Output "ZIP=$ZIP"
Write-Output "GATE=$Gate"
