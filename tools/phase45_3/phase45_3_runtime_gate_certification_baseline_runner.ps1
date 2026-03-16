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

function Get-LatestPhase45_0Proof {
    param([string]$ProofRoot)

    return Get-ChildItem -LiteralPath $ProofRoot -Directory |
        Where-Object { $_.Name -like 'phase45_0_trust_chain_runtime_gate_coverage_audit_*' } |
        Sort-Object Name -Descending |
        Select-Object -First 1
}

function Test-BaselineIntegrity {
    param(
        [string]$BaselinePath,
        [string]$IntegrityPath,
        [string]$LedgerPath
    )

    $res = [ordered]@{
        pass = $false
        reason = 'not_checked'
        expected_baseline_semantic_sha256 = ''
        actual_baseline_semantic_sha256 = ''
        expected_ledger_head_hash = ''
        actual_ledger_head_hash = ''
        phase_locked = ''
    }

    if (-not (Test-Path -LiteralPath $BaselinePath)) {
        $res.reason = 'baseline_missing'
        return $res
    }
    if (-not (Test-Path -LiteralPath $IntegrityPath)) {
        $res.reason = 'integrity_missing'
        return $res
    }
    if (-not (Test-Path -LiteralPath $LedgerPath)) {
        $res.reason = 'ledger_missing'
        return $res
    }

    $integrityObj = Get-Content -Raw -LiteralPath $IntegrityPath | ConvertFrom-Json
    $res.phase_locked = [string]$integrityObj.phase_locked
    $res.expected_baseline_semantic_sha256 = [string]$integrityObj.baseline_snapshot_semantic_sha256
    $res.expected_ledger_head_hash = [string]$integrityObj.ledger_head_hash

    $res.actual_baseline_semantic_sha256 = Get-JsonSemanticSha256 -Path $BaselinePath

    $ledgerObj = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
    $ledgerCheck = Test-LegacyTrustChain -ChainObj $ledgerObj
    if (-not $ledgerCheck.pass) {
        $res.reason = ('ledger_invalid_' + [string]$ledgerCheck.reason)
        return $res
    }

    $res.actual_ledger_head_hash = [string]$ledgerCheck.last_entry_hash

    if ($res.expected_baseline_semantic_sha256 -ne $res.actual_baseline_semantic_sha256) {
        $res.reason = 'baseline_semantic_hash_mismatch'
        return $res
    }
    if ($res.expected_ledger_head_hash -ne $res.actual_ledger_head_hash) {
        $res.reason = 'ledger_head_hash_mismatch'
        return $res
    }

    $res.pass = $true
    $res.reason = 'ok'
    return $res
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\phase45_3_runtime_gate_certification_baseline_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$ProofRoot = Join-Path $Root '_proof'
$LedgerPath = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$FingerprintPath = Join-Path $Root 'control_plane\73_runtime_gate_coverage_fingerprint.json'
$BaselinePath = Join-Path $Root 'control_plane\74_runtime_gate_certification_baseline.json'
$IntegrityPath = Join-Path $Root 'control_plane\75_runtime_gate_certification_baseline_integrity.json'

if (-not (Test-Path -LiteralPath $LedgerPath)) { throw 'Missing control_plane/70_guard_fingerprint_trust_chain.json' }
if (-not (Test-Path -LiteralPath $FingerprintPath)) { throw 'Missing control_plane/73_runtime_gate_coverage_fingerprint.json' }

$phase45_0Proof = Get-LatestPhase45_0Proof -ProofRoot $ProofRoot
if ($null -eq $phase45_0Proof) { throw 'Missing phase45_0 proof packet.' }

$InventoryPath = Join-Path $phase45_0Proof.FullName '16_entrypoint_inventory.txt'
$MapPath = Join-Path $phase45_0Proof.FullName '17_runtime_gate_enforcement_map.txt'
if (-not (Test-Path -LiteralPath $InventoryPath)) { throw 'Missing phase45_0 inventory artifact.' }
if (-not (Test-Path -LiteralPath $MapPath)) { throw 'Missing phase45_0 map artifact.' }

$fingerprintObj = Get-Content -Raw -LiteralPath $FingerprintPath | ConvertFrom-Json
$coverageFingerprintHash = [string]$fingerprintObj.coverage_fingerprint_sha256
if ([string]::IsNullOrWhiteSpace($coverageFingerprintHash)) {
    throw 'coverage_fingerprint_sha256 missing in control_plane/73 file'
}

$ledgerObj = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
$ledgerCheck = Test-LegacyTrustChain -ChainObj $ledgerObj
if (-not $ledgerCheck.pass) {
    throw ('Current ledger invalid: ' + [string]$ledgerCheck.reason)
}
$ledgerHeadHash = [string]$ledgerCheck.last_entry_hash

$inventoryHash = Get-FileSha256Hex -Path $InventoryPath
$mapHash = Get-FileSha256Hex -Path $MapPath

$baselineObj = [ordered]@{
    baseline_version = 1
    phase_locked = '45.3'
    coverage_fingerprint_hash = $coverageFingerprintHash
    ledger_head_hash = $ledgerHeadHash
    entrypoint_inventory_hash = $inventoryHash
    enforcement_map_hash = $mapHash
    timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
    source_phases = @('44.8','44.9','45.0','45.1','45.2')
    source_phase45_0_proof = $phase45_0Proof.FullName
    source_inventory_path = $InventoryPath
    source_enforcement_map_path = $MapPath
    trust_chain_ledger_path = $LedgerPath
    trust_chain_ledger_entry_count = [int]$ledgerCheck.entry_count
}

if (-not (Test-Path -LiteralPath $BaselinePath)) {
    ($baselineObj | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $BaselinePath -Encoding UTF8 -NoNewline
}

$baselineSemanticHash = Get-JsonSemanticSha256 -Path $BaselinePath

$integrityObj = [ordered]@{
    baseline_snapshot_file = 'control_plane/74_runtime_gate_certification_baseline.json'
    baseline_snapshot_semantic_sha256 = $baselineSemanticHash
    ledger_head_hash = $ledgerHeadHash
    timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
    phase_locked = '45.3'
    hash_method = 'sha256_semantic_json_v1'
}
($integrityObj | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $IntegrityPath -Encoding UTF8 -NoNewline

# CASE A
$caseARes = Test-BaselineIntegrity -BaselinePath $BaselinePath -IntegrityPath $IntegrityPath -LedgerPath $LedgerPath
$caseA = ((Test-Path -LiteralPath $BaselinePath) -and (Test-Path -LiteralPath $IntegrityPath) -and $caseARes.pass)

# CASE B
$caseBRes = Test-BaselineIntegrity -BaselinePath $BaselinePath -IntegrityPath $IntegrityPath -LedgerPath $LedgerPath
$caseB = $caseBRes.pass

# CASE C: tamper snapshot
$tempBaselineC = Join-Path $env:TEMP ('phase45_3_caseC_' + $Timestamp + '.json')
$baselineRaw = Get-Content -Raw -LiteralPath $BaselinePath
$tamperedBaseline = $baselineRaw -replace '"phase_locked"\s*:\s*"45\.3"', '"phase_locked":"45.3-TAMPER"'
if ($tamperedBaseline -eq $baselineRaw) { $tamperedBaseline = ($baselineRaw + ' ') }
[System.IO.File]::WriteAllText($tempBaselineC, $tamperedBaseline, [System.Text.Encoding]::UTF8)
$caseCRes = Test-BaselineIntegrity -BaselinePath $tempBaselineC -IntegrityPath $IntegrityPath -LedgerPath $LedgerPath
Remove-Item -Force -LiteralPath $tempBaselineC
$caseC = (-not $caseCRes.pass)

# CASE D: ledger head change tamper
$tempLedgerD = Join-Path $env:TEMP ('phase45_3_caseD_' + $Timestamp + '.json')
$ledgerTamper = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
$entriesD = [System.Collections.Generic.List[object]]::new()
foreach ($e in @($ledgerTamper.entries)) { $entriesD.Add($e) }
$lastIdx = $entriesD.Count - 1
$entriesD[$lastIdx].fingerprint_hash = ([string]$entriesD[$lastIdx].fingerprint_hash + 'tamper')
$ledgerTamperedObj = [ordered]@{ chain_version = [int]$ledgerTamper.chain_version; entries = @($entriesD) }
($ledgerTamperedObj | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $tempLedgerD -Encoding UTF8 -NoNewline
$caseDRes = Test-BaselineIntegrity -BaselinePath $BaselinePath -IntegrityPath $IntegrityPath -LedgerPath $tempLedgerD
Remove-Item -Force -LiteralPath $tempLedgerD
$caseD = (-not $caseDRes.pass)

# CASE E: non-semantic baseline formatting change
$tempBaselineE = Join-Path $env:TEMP ('phase45_3_caseE_' + $Timestamp + '.json')
$baselineObjE = Get-Content -Raw -LiteralPath $BaselinePath | ConvertFrom-Json
($baselineObjE | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $tempBaselineE -Encoding UTF8 -NoNewline
$caseERes = Test-BaselineIntegrity -BaselinePath $tempBaselineE -IntegrityPath $IntegrityPath -LedgerPath $LedgerPath
Remove-Item -Force -LiteralPath $tempBaselineE
$caseE = $caseERes.pass

$allPass = ($caseA -and $caseB -and $caseC -and $caseD -and $caseE)
$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status = @(
    'phase=45.3',
    'title=Runtime Gate Certification Baseline Snapshot',
    ('gate=' + $Gate),
    ('baseline_created=' + $(if (Test-Path -LiteralPath $BaselinePath) { 'TRUE' } else { 'FALSE' })),
    ('baseline_integrity=' + $(if ($caseBRes.pass) { 'VALID' } else { 'FAIL' })),
    'runtime_behavior_changed=NO'
)
Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value ($status -join "`r`n") -Encoding UTF8 -NoNewline

$head = @(
    'runner=tools/phase45_3/phase45_3_runtime_gate_certification_baseline_runner.ps1',
    ('baseline_path=' + $BaselinePath),
    ('integrity_path=' + $IntegrityPath),
    ('ledger_path=' + $LedgerPath),
    ('fingerprint_path=' + $FingerprintPath),
    ('phase45_0_proof=' + $phase45_0Proof.FullName)
)
Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value ($head -join "`r`n") -Encoding UTF8 -NoNewline

$def = @(
    'BASELINE SNAPSHOT DEFINITION (PHASE 45.3)',
    '',
    'Creates a locked certification baseline snapshot for runtime gate model after phase45_2.',
    'Snapshot captures coverage fingerprint hash, trust-chain ledger head hash, inventory hash, enforcement map hash, and source phase markers.',
    'Integrity record binds baseline semantic hash and ledger head hash under phase lock 45.3.'
)
Set-Content -LiteralPath (Join-Path $PF '10_baseline_definition.txt') -Value ($def -join "`r`n") -Encoding UTF8 -NoNewline

$rules = @(
    'INTEGRITY RULES',
    '1) baseline_snapshot_semantic_sha256 must match semantic canonical hash of control_plane/74 snapshot.',
    '2) ledger_head_hash must match current trust-chain head hash from control_plane/70.',
    '3) snapshot or ledger semantic tamper must fail integrity validation.',
    '4) formatting-only snapshot changes must not fail semantic integrity validation.'
)
Set-Content -LiteralPath (Join-Path $PF '11_integrity_rules.txt') -Value ($rules -join "`r`n") -Encoding UTF8 -NoNewline

$filesTouched = @(
    ('READ  ' + $LedgerPath),
    ('READ  ' + $FingerprintPath),
    ('READ  ' + $InventoryPath),
    ('READ  ' + $MapPath),
    ('WRITE ' + $BaselinePath),
    ('WRITE ' + $IntegrityPath),
    ('WRITE ' + (Join-Path $PF '*'))
)
Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Value ($filesTouched -join "`r`n") -Encoding UTF8 -NoNewline

$build = @(
    'build_type=PowerShell certification baseline snapshot runner',
    'compile_required=no',
    'runtime_behavior_changed=no',
    'operation=snapshot materialization + semantic integrity lock + tamper simulation'
)
Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Value ($build -join "`r`n") -Encoding UTF8 -NoNewline

$validation = @(
    ('CASE A baseline_snapshot_creation=' + $(if ($caseA) { 'PASS' } else { 'FAIL' })),
    ('CASE B baseline_verification=' + $(if ($caseB) { 'PASS' } else { 'FAIL' })),
    ('CASE C baseline_snapshot_tamper=' + $(if ($caseC) { 'PASS' } else { 'FAIL' })),
    ('CASE D ledger_head_change=' + $(if ($caseD) { 'PASS' } else { 'FAIL' })),
    ('CASE E non_semantic_file_change=' + $(if ($caseE) { 'PASS' } else { 'FAIL' }))
)
Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Value ($validation -join "`r`n") -Encoding UTF8 -NoNewline

$summary = @(
    'Phase 45.3 freezes runtime-gate certification model into control_plane baseline snapshot files.',
    'Integrity uses semantic JSON hashing so formatting-only changes are ignored.',
    'Snapshot tamper and ledger-head tamper are detected by integrity verification.',
    'Baseline is now available as permanent reference for future certification phases.',
    'No runtime state-machine behavior was modified.'
)
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value ($summary -join "`r`n") -Encoding UTF8 -NoNewline

$baselineRecord = @(
    ('baseline_path=' + $BaselinePath),
    ('integrity_path=' + $IntegrityPath),
    ('baseline_semantic_sha256=' + $caseBRes.actual_baseline_semantic_sha256),
    ('ledger_head_hash=' + $caseBRes.actual_ledger_head_hash),
    ('coverage_fingerprint_hash=' + $coverageFingerprintHash),
    ('entrypoint_inventory_hash=' + $inventoryHash),
    ('enforcement_map_hash=' + $mapHash)
)
Set-Content -LiteralPath (Join-Path $PF '16_baseline_record.txt') -Value ($baselineRecord -join "`r`n") -Encoding UTF8 -NoNewline

$tamperEvidence = @(
    ('caseC_pass=' + $(if ($caseC) { 'TRUE' } else { 'FALSE' })),
    ('caseC_reason=' + [string]$caseCRes.reason),
    ('caseD_pass=' + $(if ($caseD) { 'TRUE' } else { 'FALSE' })),
    ('caseD_reason=' + [string]$caseDRes.reason),
    ('caseE_pass=' + $(if ($caseE) { 'TRUE' } else { 'FALSE' })),
    ('caseE_reason=' + [string]$caseERes.reason)
)
Set-Content -LiteralPath (Join-Path $PF '17_baseline_tamper_evidence.txt') -Value ($tamperEvidence -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '98_gate_phase45_3.txt') -Value $Gate -Encoding UTF8 -NoNewline

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
