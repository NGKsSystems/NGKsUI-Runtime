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

function Convert-ToCanonicalJson {
    param([object]$Value)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [string]) { return (([string]$Value | ConvertTo-Json -Compress)) }
    if ($Value -is [bool]) { return $(if ([bool]$Value) { 'true' } else { 'false' }) }

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

function Get-NextEntryId {
    param([object]$ChainObj)

    $entries = @($ChainObj.entries)
    $max = 0
    foreach ($e in $entries) {
        $id = [string]$e.entry_id
        if ($id -match '^GF-(\d+)$') {
            $n = [int]$Matches[1]
            if ($n -gt $max) { $max = $n }
        }
    }
    return ('GF-' + ($max + 1).ToString('0000'))
}

function Invoke-FrozenBaselineTrustChainEnforcementGate {
    param(
        [string]$FrozenBaselineSnapshotPath,
        [string]$FrozenBaselineIntegrityPath,
        [string]$LiveLedgerPath,
        [string]$LiveCoverageFingerprintPath
    )

    $seq = [System.Collections.Generic.List[string]]::new()

    $r = [ordered]@{
        frozen_baseline_snapshot_path = $FrozenBaselineSnapshotPath
        frozen_baseline_integrity_record_path = $FrozenBaselineIntegrityPath
        stored_baseline_hash = ''
        computed_baseline_hash = ''
        stored_ledger_head_hash = ''
        computed_ledger_head_hash = ''
        stored_coverage_fingerprint_hash = ''
        computed_coverage_fingerprint_hash = ''
        chain_continuation_status = 'INVALID'
        semantic_match_status = 'FALSE'
        runtime_init_allowed_or_blocked = 'BLOCKED'
        fallback_occurred = $false
        regeneration_occurred = $false
        baseline_snapshot = 'INVALID'
        baseline_integrity = 'INVALID'
        ledger_head_match = $false
        coverage_fingerprint_match = $false
        sequence = @()
        reason = 'unknown'
    }

    # 1) frozen 45.9 baseline snapshot validation
    $seq.Add('1.frozen_baseline_snapshot_validation')
    if (-not (Test-Path -LiteralPath $FrozenBaselineSnapshotPath)) {
        $r.reason = 'frozen_baseline_snapshot_missing'
        $r.sequence = @($seq)
        return $r
    }

    $baselineObj = $null
    try {
        $baselineObj = Get-Content -Raw -LiteralPath $FrozenBaselineSnapshotPath | ConvertFrom-Json
    } catch {
        $r.reason = 'frozen_baseline_snapshot_parse_error'
        $r.sequence = @($seq)
        return $r
    }

    $reqBase = @('baseline_version','phase_locked','ledger_head_hash','ledger_length','coverage_fingerprint_hash','latest_entry_id','latest_entry_phase_locked')
    foreach ($f in $reqBase) {
        if (-not ($baselineObj.PSObject.Properties.Name -contains $f)) {
            $r.reason = ('frozen_baseline_snapshot_missing_field_' + $f)
            $r.sequence = @($seq)
            return $r
        }
    }
    if ([string]$baselineObj.phase_locked -ne '45.9') {
        $r.reason = 'frozen_baseline_phase_lock_mismatch'
        $r.sequence = @($seq)
        return $r
    }
    $r.baseline_snapshot = 'VALID'

    # 2) frozen baseline integrity-record validation
    $seq.Add('2.frozen_baseline_integrity_validation')
    if (-not (Test-Path -LiteralPath $FrozenBaselineIntegrityPath)) {
        $r.reason = 'frozen_baseline_integrity_missing'
        $r.sequence = @($seq)
        return $r
    }

    $integrityObj = $null
    try {
        $integrityObj = Get-Content -Raw -LiteralPath $FrozenBaselineIntegrityPath | ConvertFrom-Json
    } catch {
        $r.reason = 'frozen_baseline_integrity_parse_error'
        $r.sequence = @($seq)
        return $r
    }

    $reqInt = @('baseline_snapshot_semantic_sha256','ledger_head_hash','coverage_fingerprint_hash','phase_locked')
    foreach ($f in $reqInt) {
        if (-not ($integrityObj.PSObject.Properties.Name -contains $f)) {
            $r.reason = ('frozen_baseline_integrity_missing_field_' + $f)
            $r.sequence = @($seq)
            return $r
        }
    }
    if ([string]$integrityObj.phase_locked -ne '45.9') {
        $r.reason = 'frozen_baseline_integrity_phase_lock_mismatch'
        $r.sequence = @($seq)
        return $r
    }

    $r.stored_baseline_hash = [string]$integrityObj.baseline_snapshot_semantic_sha256
    $r.computed_baseline_hash = Get-JsonSemanticSha256 -Path $FrozenBaselineSnapshotPath

    if ($r.stored_baseline_hash -ne $r.computed_baseline_hash) {
        $r.reason = 'frozen_baseline_snapshot_semantic_hash_mismatch'
        $r.sequence = @($seq)
        return $r
    }

    $r.baseline_integrity = 'VALID'

    # 3) live ledger-head verification
    $seq.Add('3.live_ledger_head_verification')
    if (-not (Test-Path -LiteralPath $LiveLedgerPath)) {
        $r.reason = 'live_ledger_missing'
        $r.sequence = @($seq)
        return $r
    }

    $ledgerObj = Get-Content -Raw -LiteralPath $LiveLedgerPath | ConvertFrom-Json
    $ledgerCheck = Test-LegacyTrustChain -ChainObj $ledgerObj
    if (-not $ledgerCheck.pass) {
        $r.reason = ('live_ledger_invalid_' + [string]$ledgerCheck.reason)
        $r.sequence = @($seq)
        return $r
    }

    $r.stored_ledger_head_hash = [string]$baselineObj.ledger_head_hash
    $r.computed_ledger_head_hash = [string]$ledgerCheck.last_entry_hash
    $r.ledger_head_match = ($r.stored_ledger_head_hash -eq $r.computed_ledger_head_hash)

    # 4) live coverage-fingerprint verification
    $seq.Add('4.live_coverage_fingerprint_verification')
    if (-not (Test-Path -LiteralPath $LiveCoverageFingerprintPath)) {
        $r.reason = 'live_coverage_fingerprint_reference_missing'
        $r.sequence = @($seq)
        return $r
    }

    $fpObj = Get-Content -Raw -LiteralPath $LiveCoverageFingerprintPath | ConvertFrom-Json
    $r.stored_coverage_fingerprint_hash = [string]$baselineObj.coverage_fingerprint_hash
    $r.computed_coverage_fingerprint_hash = [string]$fpObj.coverage_fingerprint_sha256
    $r.coverage_fingerprint_match = ($r.stored_coverage_fingerprint_hash -eq $r.computed_coverage_fingerprint_hash)
    if (-not $r.coverage_fingerprint_match) {
        $r.reason = 'live_coverage_fingerprint_drift_detected'
        $r.sequence = @($seq)
        return $r
    }

    # 5) live chain-continuation verification
    $seq.Add('5.live_chain_continuation_verification')
    $hashes = @($ledgerCheck.chain_hashes)
    $baselineHeadExistsInChain = ($hashes -contains $r.stored_ledger_head_hash)
    $baselineLength = [int]$baselineObj.ledger_length
    $liveLength = [int]$ledgerCheck.entry_count

    if (-not $baselineHeadExistsInChain -or $liveLength -lt $baselineLength) {
        $r.chain_continuation_status = 'INVALID'
        $r.reason = 'live_chain_not_valid_continuation_of_frozen_baseline'
        $r.sequence = @($seq)
        return $r
    }
    $r.chain_continuation_status = 'VALID'

    # 6) semantic protected-field verification
    $seq.Add('6.semantic_protected_field_verification')
    if ([string]$integrityObj.ledger_head_hash -ne [string]$baselineObj.ledger_head_hash) {
        $r.reason = 'integrity_vs_baseline_ledger_head_mismatch'
        $r.sequence = @($seq)
        return $r
    }
    if ([string]$integrityObj.coverage_fingerprint_hash -ne [string]$baselineObj.coverage_fingerprint_hash) {
        $r.reason = 'integrity_vs_baseline_coverage_fingerprint_mismatch'
        $r.sequence = @($seq)
        return $r
    }

    $baselineHeadIndex = -1
    for ($i = 0; $i -lt $hashes.Count; $i++) {
        if ($hashes[$i] -eq $r.stored_ledger_head_hash) {
            $baselineHeadIndex = $i
            break
        }
    }
    if ($baselineHeadIndex -lt 0) {
        $r.reason = 'frozen_head_not_indexable_in_live_chain'
        $r.sequence = @($seq)
        return $r
    }

    $expectedHeadIndex = [int]$baselineObj.ledger_length - 1
    if ($baselineHeadIndex -ne $expectedHeadIndex) {
        $r.reason = 'frozen_head_index_mismatch_with_frozen_length'
        $r.sequence = @($seq)
        return $r
    }

    $headEntry = @($ledgerObj.entries)[$baselineHeadIndex]
    if ([string]$headEntry.entry_id -ne [string]$baselineObj.latest_entry_id) {
        $r.reason = 'frozen_latest_entry_id_mismatch'
        $r.sequence = @($seq)
        return $r
    }
    if ([string]$headEntry.phase_locked -ne [string]$baselineObj.latest_entry_phase_locked) {
        $r.reason = 'frozen_latest_entry_phase_locked_mismatch'
        $r.sequence = @($seq)
        return $r
    }

    $r.semantic_match_status = 'TRUE'

    # 7) runtime initialization allowed
    $seq.Add('7.runtime_initialization_allowed')
    $r.runtime_init_allowed_or_blocked = 'ALLOWED'
    $r.reason = $(if ($r.ledger_head_match) { 'exact_frozen_head_match' } else { 'valid_frozen_head_continuation' })
    $r.sequence = @($seq)
    return $r
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\phase46_0_certification_baseline_coverage_trust_chain_baseline_enforcement_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$BaselinePath = Join-Path $Root 'control_plane\77_certification_baseline_coverage_trust_chain_baseline.json'
$IntegrityPath = Join-Path $Root 'control_plane\78_certification_baseline_coverage_trust_chain_baseline_integrity.json'
$LedgerPath = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$CoverageFingerprintRefPath = Join-Path $Root 'control_plane\76_certification_baseline_coverage_fingerprint.json'

if (-not (Test-Path -LiteralPath $BaselinePath)) { throw 'Missing control_plane/77_certification_baseline_coverage_trust_chain_baseline.json' }
if (-not (Test-Path -LiteralPath $IntegrityPath)) { throw 'Missing control_plane/78_certification_baseline_coverage_trust_chain_baseline_integrity.json' }
if (-not (Test-Path -LiteralPath $LedgerPath)) { throw 'Missing control_plane/70_guard_fingerprint_trust_chain.json' }
if (-not (Test-Path -LiteralPath $CoverageFingerprintRefPath)) { throw 'Missing control_plane/76_certification_baseline_coverage_fingerprint.json' }

$records = [System.Collections.Generic.List[object]]::new()

# CASE A clean frozen baseline pass
$caseARes = Invoke-FrozenBaselineTrustChainEnforcementGate -FrozenBaselineSnapshotPath $BaselinePath -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $CoverageFingerprintRefPath
$caseA = (
    $caseARes.baseline_snapshot -eq 'VALID' -and
    $caseARes.baseline_integrity -eq 'VALID' -and
    $caseARes.ledger_head_match -and
    $caseARes.coverage_fingerprint_match -and
    $caseARes.chain_continuation_status -eq 'VALID' -and
    $caseARes.runtime_init_allowed_or_blocked -eq 'ALLOWED'
)
$records.Add([ordered]@{ case='A'; result=$caseARes })

# CASE B frozen baseline snapshot tamper
$tmpBaselineB = Join-Path $env:TEMP ('phase46_0_caseB_' + $Timestamp + '.json')
$baselineRaw = Get-Content -Raw -LiteralPath $BaselinePath
$tamperedBaselineB = $baselineRaw -replace '"phase_locked"\s*:\s*"45\.9"', '"phase_locked":"45.9-TAMPER"'
if ($tamperedBaselineB -eq $baselineRaw) { $tamperedBaselineB = ($baselineRaw + ' ') }
[System.IO.File]::WriteAllText($tmpBaselineB, $tamperedBaselineB, [System.Text.Encoding]::UTF8)
$caseBRes = Invoke-FrozenBaselineTrustChainEnforcementGate -FrozenBaselineSnapshotPath $tmpBaselineB -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $CoverageFingerprintRefPath
Remove-Item -Force -LiteralPath $tmpBaselineB
$caseB = ($caseBRes.baseline_snapshot -eq 'INVALID' -and $caseBRes.runtime_init_allowed_or_blocked -eq 'BLOCKED')
$records.Add([ordered]@{ case='B'; result=$caseBRes })

# CASE C frozen baseline integrity record tamper
$tmpIntegrityC = Join-Path $env:TEMP ('phase46_0_caseC_' + $Timestamp + '.json')
$intObjC = Get-Content -Raw -LiteralPath $IntegrityPath | ConvertFrom-Json
$intObjC.baseline_snapshot_semantic_sha256 = ([string]$intObjC.baseline_snapshot_semantic_sha256 + '00')
($intObjC | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $tmpIntegrityC -Encoding UTF8 -NoNewline
$caseCRes = Invoke-FrozenBaselineTrustChainEnforcementGate -FrozenBaselineSnapshotPath $BaselinePath -FrozenBaselineIntegrityPath $tmpIntegrityC -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $CoverageFingerprintRefPath
Remove-Item -Force -LiteralPath $tmpIntegrityC
$caseC = ($caseCRes.baseline_integrity -eq 'INVALID' -and $caseCRes.runtime_init_allowed_or_blocked -eq 'BLOCKED')
$records.Add([ordered]@{ case='C'; result=$caseCRes })

# CASE D live ledger head drift (invalid continuation)
$tmpLedgerD = Join-Path $env:TEMP ('phase46_0_caseD_' + $Timestamp + '.json')
$ledgerObjD = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
$entriesD = [System.Collections.Generic.List[object]]::new()
foreach ($e in @($ledgerObjD.entries)) { $entriesD.Add($e) }
$entriesD[$entriesD.Count - 1].fingerprint_hash = ([string]$entriesD[$entriesD.Count - 1].fingerprint_hash + 'drift')
$ledgerTamperedD = [ordered]@{ chain_version = [int]$ledgerObjD.chain_version; entries = @($entriesD) }
($ledgerTamperedD | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $tmpLedgerD -Encoding UTF8 -NoNewline
$caseDRes = Invoke-FrozenBaselineTrustChainEnforcementGate -FrozenBaselineSnapshotPath $BaselinePath -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $tmpLedgerD -LiveCoverageFingerprintPath $CoverageFingerprintRefPath
Remove-Item -Force -LiteralPath $tmpLedgerD
$caseD = ((-not $caseDRes.ledger_head_match) -and $caseDRes.runtime_init_allowed_or_blocked -eq 'BLOCKED')
$records.Add([ordered]@{ case='D'; result=$caseDRes })

# CASE E live coverage fingerprint drift
$tmpFingerprintE = Join-Path $env:TEMP ('phase46_0_caseE_' + $Timestamp + '.json')
$fpObjE = Get-Content -Raw -LiteralPath $CoverageFingerprintRefPath | ConvertFrom-Json
$fpObjE.coverage_fingerprint_sha256 = ([string]$fpObjE.coverage_fingerprint_sha256 + '00')
($fpObjE | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $tmpFingerprintE -Encoding UTF8 -NoNewline
$caseERes = Invoke-FrozenBaselineTrustChainEnforcementGate -FrozenBaselineSnapshotPath $BaselinePath -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $tmpFingerprintE
Remove-Item -Force -LiteralPath $tmpFingerprintE
$caseE = ((-not $caseERes.coverage_fingerprint_match) -and $caseERes.runtime_init_allowed_or_blocked -eq 'BLOCKED')
$records.Add([ordered]@{ case='E'; result=$caseERes })

# CASE F invalid chain continuation
$tmpLedgerF = Join-Path $env:TEMP ('phase46_0_caseF_' + $Timestamp + '.json')
$ledgerObjF = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
$chainF = Test-LegacyTrustChain -ChainObj $ledgerObjF
$entriesF = [System.Collections.Generic.List[object]]::new()
foreach ($e in @($ledgerObjF.entries)) { $entriesF.Add($e) }
$nextIdF = Get-NextEntryId -ChainObj $ledgerObjF
$invalidAppendF = [ordered]@{
    entry_id = $nextIdF
    artifact = 'phase46_0_invalid_probe'
    coverage_fingerprint = ([string](Get-Content -Raw -LiteralPath $CoverageFingerprintRefPath | ConvertFrom-Json).coverage_fingerprint_sha256)
    fingerprint_hash = (Get-BytesSha256Hex -Bytes ([System.Text.Encoding]::UTF8.GetBytes('invalid_append_' + $Timestamp)))
    timestamp_utc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    phase_locked = '46.1'
    previous_hash = ([string]$chainF.last_entry_hash + 'broken')
}
$entriesF.Add($invalidAppendF)
$ledgerInvalidF = [ordered]@{ chain_version = [int]$ledgerObjF.chain_version; entries = @($entriesF) }
($ledgerInvalidF | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $tmpLedgerF -Encoding UTF8 -NoNewline
$caseFRes = Invoke-FrozenBaselineTrustChainEnforcementGate -FrozenBaselineSnapshotPath $BaselinePath -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $tmpLedgerF -LiveCoverageFingerprintPath $CoverageFingerprintRefPath
Remove-Item -Force -LiteralPath $tmpLedgerF
$caseF = ($caseFRes.chain_continuation_status -eq 'INVALID' -and $caseFRes.runtime_init_allowed_or_blocked -eq 'BLOCKED')
$records.Add([ordered]@{ case='F'; result=$caseFRes })

# CASE G valid chain continuation
$tmpLedgerG = Join-Path $env:TEMP ('phase46_0_caseG_' + $Timestamp + '.json')
$ledgerObjG = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
$chainG = Test-LegacyTrustChain -ChainObj $ledgerObjG
$entriesG = [System.Collections.Generic.List[object]]::new()
foreach ($e in @($ledgerObjG.entries)) { $entriesG.Add($e) }
$nextIdG = Get-NextEntryId -ChainObj $ledgerObjG
$validAppendG = [ordered]@{
    entry_id = $nextIdG
    artifact = 'phase46_0_valid_probe'
    coverage_fingerprint = ([string](Get-Content -Raw -LiteralPath $CoverageFingerprintRefPath | ConvertFrom-Json).coverage_fingerprint_sha256)
    fingerprint_hash = (Get-BytesSha256Hex -Bytes ([System.Text.Encoding]::UTF8.GetBytes('valid_append_' + $Timestamp)))
    timestamp_utc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    phase_locked = '46.1'
    previous_hash = [string]$chainG.last_entry_hash
}
$entriesG.Add($validAppendG)
$ledgerValidG = [ordered]@{ chain_version = [int]$ledgerObjG.chain_version; entries = @($entriesG) }
($ledgerValidG | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $tmpLedgerG -Encoding UTF8 -NoNewline
$caseGRes = Invoke-FrozenBaselineTrustChainEnforcementGate -FrozenBaselineSnapshotPath $BaselinePath -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $tmpLedgerG -LiveCoverageFingerprintPath $CoverageFingerprintRefPath
Remove-Item -Force -LiteralPath $tmpLedgerG
$caseG = ($caseGRes.chain_continuation_status -eq 'VALID' -and $caseGRes.runtime_init_allowed_or_blocked -eq 'ALLOWED')
$records.Add([ordered]@{ case='G'; result=$caseGRes })

# CASE H non-semantic change
$tmpBaselineH = Join-Path $env:TEMP ('phase46_0_caseH_baseline_' + $Timestamp + '.json')
$tmpIntegrityH = Join-Path $env:TEMP ('phase46_0_caseH_integrity_' + $Timestamp + '.json')
$tmpLedgerH = Join-Path $env:TEMP ('phase46_0_caseH_ledger_' + $Timestamp + '.json')
(Get-Content -Raw -LiteralPath $BaselinePath | ConvertFrom-Json | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $tmpBaselineH -Encoding UTF8 -NoNewline
(Get-Content -Raw -LiteralPath $IntegrityPath | ConvertFrom-Json | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $tmpIntegrityH -Encoding UTF8 -NoNewline
(Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json | ConvertTo-Json -Depth 30) | Set-Content -LiteralPath $tmpLedgerH -Encoding UTF8 -NoNewline
$caseHRes = Invoke-FrozenBaselineTrustChainEnforcementGate -FrozenBaselineSnapshotPath $tmpBaselineH -FrozenBaselineIntegrityPath $tmpIntegrityH -LiveLedgerPath $tmpLedgerH -LiveCoverageFingerprintPath $CoverageFingerprintRefPath
Remove-Item -Force -LiteralPath $tmpBaselineH
Remove-Item -Force -LiteralPath $tmpIntegrityH
Remove-Item -Force -LiteralPath $tmpLedgerH
$caseH = ($caseHRes.baseline_integrity -eq 'VALID' -and $caseHRes.semantic_match_status -eq 'TRUE' -and $caseHRes.runtime_init_allowed_or_blocked -eq 'ALLOWED')
$records.Add([ordered]@{ case='H'; result=$caseHRes })

$allPass = ($caseA -and $caseB -and $caseC -and $caseD -and $caseE -and $caseF -and $caseG -and $caseH)
$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status = @(
    'phase=46.0',
    'title=Certification Baseline Coverage Trust-Chain Baseline Enforcement',
    ('gate=' + $Gate),
    ('frozen_baseline_preinit_enforced=' + $(if ($caseARes.sequence[0] -eq '1.frozen_baseline_snapshot_validation') { 'TRUE' } else { 'FALSE' })),
    'fallback_occurred=FALSE',
    'regeneration_occurred=FALSE',
    'runtime_state_machine_changed=NO'
)
Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value ($status -join "`r`n") -Encoding UTF8 -NoNewline

$head = @(
    'runner=tools/phase46_0/phase46_0_certification_baseline_coverage_trust_chain_baseline_enforcement_runner.ps1',
    ('frozen_baseline_snapshot=' + $BaselinePath),
    ('frozen_baseline_integrity=' + $IntegrityPath),
    ('live_ledger=' + $LedgerPath),
    ('live_coverage_fingerprint=' + $CoverageFingerprintRefPath)
)
Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value ($head -join "`r`n") -Encoding UTF8 -NoNewline

$definition = @(
    'FROZEN BASELINE ENFORCEMENT DEFINITION (PHASE 46.0)',
    '',
    'Phase45_9 frozen baseline is now a mandatory pre-runtime-init gate.',
    'Runtime initialization is allowed only after baseline snapshot/integrity verification, live ledger and coverage verification, continuation verification, and protected-field semantic checks.',
    'Enforcement accepts exact frozen-head match or valid continuation anchored to frozen head.'
)
Set-Content -LiteralPath (Join-Path $PF '10_baseline_enforcement_definition.txt') -Value ($definition -join "`r`n") -Encoding UTF8 -NoNewline

$rules = @(
    'BASELINE ENFORCEMENT RULES',
    '1) Validate frozen 45.9 baseline snapshot exists and schema/phase lock are valid.',
    '2) Validate frozen baseline integrity record and semantic baseline hash.',
    '3) Validate live ledger chain integrity and compute live head hash.',
    '4) Validate live coverage-fingerprint hash matches frozen baseline expectation.',
    '5) Validate live chain is a continuation anchored to the frozen baseline head.',
    '6) Validate protected semantic fields (head hash, coverage hash, baseline head index, latest entry id/phase).',
    '7) Allow runtime initialization only when all rules pass.',
    '8) Never fallback and never regenerate baseline during enforcement.'
)
Set-Content -LiteralPath (Join-Path $PF '11_baseline_enforcement_rules.txt') -Value ($rules -join "`r`n") -Encoding UTF8 -NoNewline

$filesTouched = @(
    ('READ  ' + $BaselinePath),
    ('READ  ' + $IntegrityPath),
    ('READ  ' + $LedgerPath),
    ('READ  ' + $CoverageFingerprintRefPath),
    ('WRITE ' + (Join-Path $PF '*'))
)
Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Value ($filesTouched -join "`r`n") -Encoding UTF8 -NoNewline

$build = @(
    'build_type=PowerShell frozen baseline enforcement runner',
    'compile_required=no',
    'runtime_state_machine_changed=no',
    'operation=pre-init frozen-baseline gate + deterministic tamper/continuation validation'
)
Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Value ($build -join "`r`n") -Encoding UTF8 -NoNewline

$validation = @(
    ('CASE A clean_frozen_baseline_pass=' + $(if ($caseA) { 'PASS' } else { 'FAIL' })),
    ('CASE B frozen_baseline_snapshot_tamper=' + $(if ($caseB) { 'PASS' } else { 'FAIL' })),
    ('CASE C frozen_baseline_integrity_record_tamper=' + $(if ($caseC) { 'PASS' } else { 'FAIL' })),
    ('CASE D live_ledger_head_drift=' + $(if ($caseD) { 'PASS' } else { 'FAIL' })),
    ('CASE E live_coverage_fingerprint_drift=' + $(if ($caseE) { 'PASS' } else { 'FAIL' })),
    ('CASE F invalid_chain_continuation=' + $(if ($caseF) { 'PASS' } else { 'FAIL' })),
    ('CASE G valid_chain_continuation=' + $(if ($caseG) { 'PASS' } else { 'FAIL' })),
    ('CASE H non_semantic_change=' + $(if ($caseH) { 'PASS' } else { 'FAIL' }))
)
Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Value ($validation -join "`r`n") -Encoding UTF8 -NoNewline

$summary = @(
    'Phase 46.0 activates frozen trust-chain baseline enforcement as a strict pre-runtime-initialization gate.',
    'The gate enforces frozen baseline snapshot/integrity, live ledger validity, live coverage-fingerprint match, and continuation anchoring against the frozen head.',
    'Invalid continuation or protected-field mismatch blocks runtime initialization deterministically.',
    'Valid continuation remains allowed as long as frozen baseline head remains anchored in live chain history.',
    'No fallback and no regeneration paths are used.',
    'Formatting-only changes do not trigger false blocks.',
    'Runtime behavior is otherwise unchanged.'
)
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value ($summary -join "`r`n") -Encoding UTF8 -NoNewline

$recordLines = [System.Collections.Generic.List[string]]::new()
$recordLines.Add('case|frozen_baseline_snapshot_path|frozen_baseline_integrity_record_path|stored_baseline_hash|computed_baseline_hash|stored_ledger_head_hash|computed_ledger_head_hash|stored_coverage_fingerprint_hash|computed_coverage_fingerprint_hash|chain_continuation_status|semantic_match_status|runtime_init_allowed_or_blocked|fallback_occurred|regeneration_occurred|reason|sequence')
foreach ($x in $records) {
    $o = $x.result
    $recordLines.Add(
        [string]$x.case + '|' +
        [string]$o.frozen_baseline_snapshot_path + '|' +
        [string]$o.frozen_baseline_integrity_record_path + '|' +
        [string]$o.stored_baseline_hash + '|' +
        [string]$o.computed_baseline_hash + '|' +
        [string]$o.stored_ledger_head_hash + '|' +
        [string]$o.computed_ledger_head_hash + '|' +
        [string]$o.stored_coverage_fingerprint_hash + '|' +
        [string]$o.computed_coverage_fingerprint_hash + '|' +
        [string]$o.chain_continuation_status + '|' +
        [string]$o.semantic_match_status + '|' +
        [string]$o.runtime_init_allowed_or_blocked + '|' +
        [string]$o.fallback_occurred + '|' +
        [string]$o.regeneration_occurred + '|' +
        [string]$o.reason + '|' +
        ([string[]]$o.sequence -join '>')
    )
}
Set-Content -LiteralPath (Join-Path $PF '16_frozen_baseline_enforcement_record.txt') -Value (($recordLines.ToArray()) -join "`r`n") -Encoding UTF8 -NoNewline

$blockEvidence = @(
    ('caseB_reason=' + [string]$caseBRes.reason),
    ('caseC_reason=' + [string]$caseCRes.reason),
    ('caseD_reason=' + [string]$caseDRes.reason),
    ('caseE_reason=' + [string]$caseERes.reason),
    ('caseF_reason=' + [string]$caseFRes.reason),
    ('caseG_reason=' + [string]$caseGRes.reason),
    ('caseH_reason=' + [string]$caseHRes.reason),
    ('caseA_sequence=' + ([string[]]$caseARes.sequence -join '>')),
    ('fallback_occurred=false'),
    ('regeneration_occurred=false')
)
Set-Content -LiteralPath (Join-Path $PF '17_runtime_block_evidence.txt') -Value ($blockEvidence -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '98_gate_phase46_0.txt') -Value $Gate -Encoding UTF8 -NoNewline

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
