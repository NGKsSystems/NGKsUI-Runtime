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

function Test-FrozenBaselineReference {
    param(
        [string]$BaselineSnapshotPath,
        [string]$BaselineIntegrityPath,
        [string]$LedgerPath,
        [string]$CoverageFingerprintRefPath
    )

    $r = [ordered]@{
        baseline_snapshot_path = $BaselineSnapshotPath
        baseline_integrity_record_path = $BaselineIntegrityPath
        stored_baseline_hash = ''
        computed_baseline_hash = ''
        stored_ledger_head_hash = ''
        computed_ledger_head_hash = ''
        stored_coverage_fingerprint_hash = ''
        computed_coverage_fingerprint_hash = ''
        baseline_integrity_result = 'FAIL'
        baseline_reference_status = 'INVALID'
        baseline_usage_allowed_or_blocked = 'BLOCKED'
        ledger_head_match = $false
        reason = 'unknown'
    }

    if (-not (Test-Path -LiteralPath $BaselineSnapshotPath)) {
        $r.reason = 'baseline_snapshot_missing'
        return $r
    }
    if (-not (Test-Path -LiteralPath $BaselineIntegrityPath)) {
        $r.reason = 'baseline_integrity_missing'
        return $r
    }
    if (-not (Test-Path -LiteralPath $LedgerPath)) {
        $r.reason = 'ledger_missing'
        return $r
    }
    if (-not (Test-Path -LiteralPath $CoverageFingerprintRefPath)) {
        $r.reason = 'coverage_fingerprint_reference_missing'
        return $r
    }

    $baselineObj = $null
    $integrityObj = $null
    $fingerprintObj = $null
    $ledgerObj = $null

    try {
        $baselineObj = Get-Content -Raw -LiteralPath $BaselineSnapshotPath | ConvertFrom-Json
        $integrityObj = Get-Content -Raw -LiteralPath $BaselineIntegrityPath | ConvertFrom-Json
        $fingerprintObj = Get-Content -Raw -LiteralPath $CoverageFingerprintRefPath | ConvertFrom-Json
        $ledgerObj = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
    } catch {
        $r.reason = 'parse_error'
        return $r
    }

    $reqBase = @('phase_locked','ledger_head_hash','ledger_length','coverage_fingerprint_hash','latest_entry_id','latest_entry_phase_locked')
    foreach ($f in $reqBase) {
        if (-not ($baselineObj.PSObject.Properties.Name -contains $f)) {
            $r.reason = ('baseline_missing_field_' + $f)
            return $r
        }
    }
    if ([string]$baselineObj.phase_locked -ne '45.9') {
        $r.reason = 'baseline_phase_lock_mismatch'
        return $r
    }

    $reqInt = @('baseline_snapshot_semantic_sha256','ledger_head_hash','coverage_fingerprint_hash','phase_locked')
    foreach ($f in $reqInt) {
        if (-not ($integrityObj.PSObject.Properties.Name -contains $f)) {
            $r.reason = ('integrity_missing_field_' + $f)
            return $r
        }
    }
    if ([string]$integrityObj.phase_locked -ne '45.9') {
        $r.reason = 'integrity_phase_lock_mismatch'
        return $r
    }

    $r.stored_baseline_hash = [string]$integrityObj.baseline_snapshot_semantic_sha256
    $r.computed_baseline_hash = Get-JsonSemanticSha256 -Path $BaselineSnapshotPath
    $r.stored_ledger_head_hash = [string]$baselineObj.ledger_head_hash
    $r.stored_coverage_fingerprint_hash = [string]$baselineObj.coverage_fingerprint_hash
    $r.computed_coverage_fingerprint_hash = [string]$fingerprintObj.coverage_fingerprint_sha256

    if ($r.stored_baseline_hash -ne $r.computed_baseline_hash) {
        $r.reason = 'baseline_snapshot_semantic_hash_mismatch'
        return $r
    }

    if ([string]$integrityObj.coverage_fingerprint_hash -ne $r.stored_coverage_fingerprint_hash) {
        $r.reason = 'integrity_vs_baseline_coverage_hash_mismatch'
        return $r
    }

    if ($r.stored_coverage_fingerprint_hash -ne $r.computed_coverage_fingerprint_hash) {
        $r.reason = 'coverage_fingerprint_hash_mismatch'
        return $r
    }

    $ledgerCheck = Test-LegacyTrustChain -ChainObj $ledgerObj
    if (-not $ledgerCheck.pass) {
        $r.reason = ('ledger_invalid_' + [string]$ledgerCheck.reason)
        return $r
    }

    $r.computed_ledger_head_hash = [string]$ledgerCheck.last_entry_hash
    $r.ledger_head_match = ($r.stored_ledger_head_hash -eq $r.computed_ledger_head_hash)

    if ([string]$integrityObj.ledger_head_hash -ne $r.stored_ledger_head_hash) {
        $r.reason = 'integrity_vs_baseline_ledger_head_mismatch'
        return $r
    }

    $hashes = @($ledgerCheck.chain_hashes)
    $baselineHeadExistsInLiveChain = ($hashes -contains $r.stored_ledger_head_hash)

    $baselineLength = [int]$baselineObj.ledger_length
    $liveLength = [int]$ledgerCheck.entry_count
    if ($liveLength -lt $baselineLength) {
        $r.reason = 'live_chain_shorter_than_frozen_baseline'
        return $r
    }

    if (-not $baselineHeadExistsInLiveChain) {
        $r.reason = 'frozen_baseline_head_not_found_in_live_chain'
        return $r
    }

    $r.baseline_integrity_result = 'VALID'
    $r.baseline_reference_status = 'VALID'
    $r.baseline_usage_allowed_or_blocked = 'ALLOWED'
    $r.reason = $(if ($r.ledger_head_match) { 'exact_head_match' } else { 'frozen_head_anchored_with_future_append' })
    return $r
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\phase45_9_certification_baseline_coverage_trust_chain_baseline_lock_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$LedgerPath = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$CoverageFingerprintRefPath = Join-Path $Root 'control_plane\76_certification_baseline_coverage_fingerprint.json'
$BaselinePath = Join-Path $Root 'control_plane\77_certification_baseline_coverage_trust_chain_baseline.json'
$IntegrityPath = Join-Path $Root 'control_plane\78_certification_baseline_coverage_trust_chain_baseline_integrity.json'

if (-not (Test-Path -LiteralPath $LedgerPath)) { throw 'Missing control_plane/70_guard_fingerprint_trust_chain.json' }
if (-not (Test-Path -LiteralPath $CoverageFingerprintRefPath)) { throw 'Missing control_plane/76_certification_baseline_coverage_fingerprint.json' }

$ledgerObj = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
$ledgerCheck = Test-LegacyTrustChain -ChainObj $ledgerObj
if (-not $ledgerCheck.pass) {
    throw ('Current ledger invalid: ' + [string]$ledgerCheck.reason)
}

$fpObj = Get-Content -Raw -LiteralPath $CoverageFingerprintRefPath | ConvertFrom-Json
$coverageFingerprintHash = [string]$fpObj.coverage_fingerprint_sha256
if ([string]::IsNullOrWhiteSpace($coverageFingerprintHash)) {
    throw 'coverage_fingerprint_sha256 missing in control_plane/76 file'
}

$entries = @($ledgerObj.entries)
$latest = $entries[$entries.Count - 1]
$baselineObj = [ordered]@{
    baseline_version = 1
    phase_locked = '45.9'
    ledger_head_hash = [string]$ledgerCheck.last_entry_hash
    ledger_length = [int]$ledgerCheck.entry_count
    coverage_fingerprint_hash = $coverageFingerprintHash
    latest_entry_id = [string]$latest.entry_id
    latest_entry_phase_locked = [string]$latest.phase_locked
    timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
    source_phases = @('45.6','45.7','45.8')
}
($baselineObj | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $BaselinePath -Encoding UTF8 -NoNewline

$baselineSemanticHash = Get-JsonSemanticSha256 -Path $BaselinePath
$integrityObj = [ordered]@{
    baseline_snapshot_file = 'control_plane/77_certification_baseline_coverage_trust_chain_baseline.json'
    baseline_snapshot_semantic_sha256 = $baselineSemanticHash
    ledger_head_hash = [string]$ledgerCheck.last_entry_hash
    coverage_fingerprint_hash = $coverageFingerprintHash
    timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
    phase_locked = '45.9'
    hash_method = 'sha256_semantic_json_v1'
}
($integrityObj | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $IntegrityPath -Encoding UTF8 -NoNewline

$records = [System.Collections.Generic.List[object]]::new()

# CASE A baseline snapshot creation
$caseARes = Test-FrozenBaselineReference -BaselineSnapshotPath $BaselinePath -BaselineIntegrityPath $IntegrityPath -LedgerPath $LedgerPath -CoverageFingerprintRefPath $CoverageFingerprintRefPath
$caseA = ((Test-Path -LiteralPath $BaselinePath) -and (Test-Path -LiteralPath $IntegrityPath) -and $caseARes.baseline_integrity_result -eq 'VALID' -and $caseARes.baseline_reference_status -eq 'VALID')
$records.Add([ordered]@{ case='A'; result=$caseARes })

# CASE B baseline verification (idempotent semantic recompute)
$caseBRes = Test-FrozenBaselineReference -BaselineSnapshotPath $BaselinePath -BaselineIntegrityPath $IntegrityPath -LedgerPath $LedgerPath -CoverageFingerprintRefPath $CoverageFingerprintRefPath
$caseB = ($caseBRes.baseline_integrity_result -eq 'VALID' -and $caseBRes.baseline_reference_status -eq 'VALID')
$records.Add([ordered]@{ case='B'; result=$caseBRes })

# CASE C baseline snapshot tamper
$tmpBaselineC = Join-Path $env:TEMP ('phase45_9_caseC_' + $Timestamp + '.json')
$baselineRaw = Get-Content -Raw -LiteralPath $BaselinePath
$tamperedBaseline = $baselineRaw -replace '"phase_locked"\s*:\s*"45\.9"', '"phase_locked":"45.9-TAMPER"'
if ($tamperedBaseline -eq $baselineRaw) { $tamperedBaseline = ($baselineRaw + ' ') }
[System.IO.File]::WriteAllText($tmpBaselineC, $tamperedBaseline, [System.Text.Encoding]::UTF8)
$caseCRes = Test-FrozenBaselineReference -BaselineSnapshotPath $tmpBaselineC -BaselineIntegrityPath $IntegrityPath -LedgerPath $LedgerPath -CoverageFingerprintRefPath $CoverageFingerprintRefPath
Remove-Item -Force -LiteralPath $tmpBaselineC
$caseC = ($caseCRes.baseline_integrity_result -eq 'FAIL' -and $caseCRes.baseline_usage_allowed_or_blocked -eq 'BLOCKED')
$records.Add([ordered]@{ case='C'; result=$caseCRes })

# CASE D integrity record tamper
$tmpIntegrityD = Join-Path $env:TEMP ('phase45_9_caseD_' + $Timestamp + '.json')
$intObjD = Get-Content -Raw -LiteralPath $IntegrityPath | ConvertFrom-Json
$intObjD.baseline_snapshot_semantic_sha256 = ([string]$intObjD.baseline_snapshot_semantic_sha256 + '00')
($intObjD | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $tmpIntegrityD -Encoding UTF8 -NoNewline
$caseDRes = Test-FrozenBaselineReference -BaselineSnapshotPath $BaselinePath -BaselineIntegrityPath $tmpIntegrityD -LedgerPath $LedgerPath -CoverageFingerprintRefPath $CoverageFingerprintRefPath
Remove-Item -Force -LiteralPath $tmpIntegrityD
$caseD = ($caseDRes.baseline_integrity_result -eq 'FAIL' -and $caseDRes.baseline_usage_allowed_or_blocked -eq 'BLOCKED')
$records.Add([ordered]@{ case='D'; result=$caseDRes })

# CASE E ledger head drift (tamper last entry fingerprint_hash but keep chain structurally valid)
$tmpLedgerE = Join-Path $env:TEMP ('phase45_9_caseE_' + $Timestamp + '.json')
$ledgerObjE = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
$entriesE = [System.Collections.Generic.List[object]]::new()
foreach ($e in @($ledgerObjE.entries)) { $entriesE.Add($e) }
$entriesE[$entriesE.Count - 1].fingerprint_hash = ([string]$entriesE[$entriesE.Count - 1].fingerprint_hash + 'drift')
$ledgerE = [ordered]@{ chain_version = [int]$ledgerObjE.chain_version; entries = @($entriesE) }
($ledgerE | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $tmpLedgerE -Encoding UTF8 -NoNewline
$caseERes = Test-FrozenBaselineReference -BaselineSnapshotPath $BaselinePath -BaselineIntegrityPath $IntegrityPath -LedgerPath $tmpLedgerE -CoverageFingerprintRefPath $CoverageFingerprintRefPath
Remove-Item -Force -LiteralPath $tmpLedgerE
$caseE = ((-not $caseERes.ledger_head_match) -and $caseERes.baseline_reference_status -eq 'INVALID')
$records.Add([ordered]@{ case='E'; result=$caseERes })

# CASE F future append compatibility (valid append after frozen head)
$tmpLedgerF = Join-Path $env:TEMP ('phase45_9_caseF_' + $Timestamp + '.json')
$ledgerObjF = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
$chainF = Test-LegacyTrustChain -ChainObj $ledgerObjF
$entriesF = [System.Collections.Generic.List[object]]::new()
foreach ($e in @($ledgerObjF.entries)) { $entriesF.Add($e) }
$nextIdF = Get-NextEntryId -ChainObj $ledgerObjF
$nextEntryF = [ordered]@{
    entry_id = $nextIdF
    artifact = 'certification_baseline_coverage_future_probe'
    coverage_fingerprint = $coverageFingerprintHash
    fingerprint_hash = (Get-BytesSha256Hex -Bytes ([System.Text.Encoding]::UTF8.GetBytes('phase45_9_future_probe_' + $Timestamp)))
    timestamp_utc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    phase_locked = '46.0'
    previous_hash = [string]$chainF.last_entry_hash
}
$entriesF.Add($nextEntryF)
$ledgerF = [ordered]@{ chain_version = [int]$ledgerObjF.chain_version; entries = @($entriesF) }
($ledgerF | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $tmpLedgerF -Encoding UTF8 -NoNewline

$baselineHashBeforeF = Get-JsonSemanticSha256 -Path $BaselinePath
$caseFRes = Test-FrozenBaselineReference -BaselineSnapshotPath $BaselinePath -BaselineIntegrityPath $IntegrityPath -LedgerPath $tmpLedgerF -CoverageFingerprintRefPath $CoverageFingerprintRefPath
$baselineHashAfterF = Get-JsonSemanticSha256 -Path $BaselinePath
Remove-Item -Force -LiteralPath $tmpLedgerF
$caseF = ($caseFRes.baseline_reference_status -eq 'VALID' -and $caseFRes.baseline_usage_allowed_or_blocked -eq 'ALLOWED' -and $baselineHashBeforeF -eq $baselineHashAfterF)
$records.Add([ordered]@{ case='F'; result=$caseFRes })

# CASE G non-semantic formatting change
$tmpBaselineG = Join-Path $env:TEMP ('phase45_9_caseG_baseline_' + $Timestamp + '.json')
$tmpIntegrityG = Join-Path $env:TEMP ('phase45_9_caseG_integrity_' + $Timestamp + '.json')
$tmpLedgerG = Join-Path $env:TEMP ('phase45_9_caseG_ledger_' + $Timestamp + '.json')
(Get-Content -Raw -LiteralPath $BaselinePath | ConvertFrom-Json | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $tmpBaselineG -Encoding UTF8 -NoNewline
(Get-Content -Raw -LiteralPath $IntegrityPath | ConvertFrom-Json | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $tmpIntegrityG -Encoding UTF8 -NoNewline
(Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json | ConvertTo-Json -Depth 30) | Set-Content -LiteralPath $tmpLedgerG -Encoding UTF8 -NoNewline
$caseGRes = Test-FrozenBaselineReference -BaselineSnapshotPath $tmpBaselineG -BaselineIntegrityPath $tmpIntegrityG -LedgerPath $tmpLedgerG -CoverageFingerprintRefPath $CoverageFingerprintRefPath
Remove-Item -Force -LiteralPath $tmpBaselineG
Remove-Item -Force -LiteralPath $tmpIntegrityG
Remove-Item -Force -LiteralPath $tmpLedgerG
$caseG = ($caseGRes.baseline_integrity_result -eq 'VALID' -and $caseGRes.baseline_reference_status -eq 'VALID')
$records.Add([ordered]@{ case='G'; result=$caseGRes })

$allPass = ($caseA -and $caseB -and $caseC -and $caseD -and $caseE -and $caseF -and $caseG)
$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status = @(
    'phase=45.9',
    'title=Certification Baseline Enforcement Coverage Trust-Chain Baseline Lock',
    ('gate=' + $Gate),
    ('baseline_snapshot=' + $(if ($caseA) { 'CREATED' } else { 'FAIL' })),
    ('baseline_integrity=' + $(if ($caseB) { 'VALID' } else { 'FAIL' })),
    ('runtime_state_machine_changed=NO')
)
Set-Content -LiteralPath (Join-Path $PF '01_status.txt') -Value ($status -join "`r`n") -Encoding UTF8 -NoNewline

$head = @(
    'runner=tools/phase45_9/phase45_9_certification_baseline_coverage_trust_chain_baseline_lock_runner.ps1',
    ('ledger_path=' + $LedgerPath),
    ('coverage_fingerprint_reference=' + $CoverageFingerprintRefPath),
    ('baseline_snapshot=' + $BaselinePath),
    ('baseline_integrity=' + $IntegrityPath)
)
Set-Content -LiteralPath (Join-Path $PF '02_head.txt') -Value ($head -join "`r`n") -Encoding UTF8 -NoNewline

$def = @(
    'BASELINE LOCK DEFINITION (PHASE 45.9)',
    '',
    'Phase45_8 post-append trust-chain state is frozen into a baseline snapshot and integrity record.',
    'The frozen baseline locks ledger head hash, ledger length, and coverage fingerprint hash.',
    'Baseline reference validity requires semantic baseline integrity plus coverage hash equality plus live-chain anchoring.',
    'Live-chain anchoring accepts exact head match or a valid future append where frozen head remains present in chain history.'
)
Set-Content -LiteralPath (Join-Path $PF '10_baseline_definition.txt') -Value ($def -join "`r`n") -Encoding UTF8 -NoNewline

$rules = @(
    'BASELINE HASH RULES',
    '1) Baseline snapshot hash uses semantic canonical JSON SHA-256.',
    '2) Integrity record stores baseline semantic hash, ledger head hash, and coverage fingerprint hash.',
    '3) Baseline integrity fails if baseline semantic hash changes or integrity fields diverge.',
    '4) Baseline reference is valid only when live ledger is structurally valid and contains frozen baseline head hash.',
    '5) Exact head match is valid; valid future append anchored to frozen head is also valid.',
    '6) Head drift that removes frozen head from live chain history invalidates reference.',
    '7) Formatting-only changes must not affect semantic-hash verification.'
)
Set-Content -LiteralPath (Join-Path $PF '11_baseline_hash_rules.txt') -Value ($rules -join "`r`n") -Encoding UTF8 -NoNewline

$filesTouched = @(
    ('READ  ' + $LedgerPath),
    ('READ  ' + $CoverageFingerprintRefPath),
    ('WRITE ' + $BaselinePath),
    ('WRITE ' + $IntegrityPath),
    ('WRITE ' + (Join-Path $PF '*'))
)
Set-Content -LiteralPath (Join-Path $PF '12_files_touched.txt') -Value ($filesTouched -join "`r`n") -Encoding UTF8 -NoNewline

$build = @(
    'build_type=PowerShell frozen trust-chain baseline lock runner',
    'compile_required=no',
    'runtime_behavior_changed=no',
    ('baseline_semantic_sha256=' + $baselineSemanticHash),
    ('frozen_ledger_head_hash=' + [string]$ledgerCheck.last_entry_hash),
    ('frozen_ledger_length=' + [string]$ledgerCheck.entry_count),
    ('frozen_coverage_fingerprint_hash=' + $coverageFingerprintHash)
)
Set-Content -LiteralPath (Join-Path $PF '13_build_output.txt') -Value ($build -join "`r`n") -Encoding UTF8 -NoNewline

$validation = @(
    ('CASE A baseline_snapshot_creation=' + $(if ($caseA) { 'PASS' } else { 'FAIL' })),
    ('CASE B baseline_verification=' + $(if ($caseB) { 'PASS' } else { 'FAIL' })),
    ('CASE C baseline_snapshot_tamper=' + $(if ($caseC) { 'PASS' } else { 'FAIL' })),
    ('CASE D integrity_record_tamper=' + $(if ($caseD) { 'PASS' } else { 'FAIL' })),
    ('CASE E ledger_head_drift=' + $(if ($caseE) { 'PASS' } else { 'FAIL' })),
    ('CASE F future_append_compatibility=' + $(if ($caseF) { 'PASS' } else { 'FAIL' })),
    ('CASE G non_semantic_change=' + $(if ($caseG) { 'PASS' } else { 'FAIL' }))
)
Set-Content -LiteralPath (Join-Path $PF '14_validation_results.txt') -Value ($validation -join "`r`n") -Encoding UTF8 -NoNewline

$summary = @(
    'Phase 45.9 freezes the post-45.8 trust-chain state into control_plane/77 and control_plane/78.',
    'Baseline integrity is semantic-hash based and detects snapshot or integrity-record tampering.',
    'Baseline reference logic distinguishes invalid head drift from valid future append anchoring.',
    'Ledger-head drift that removes frozen head history invalidates baseline reference and blocks usage.',
    'A valid future append keeps the frozen baseline unchanged and still reference-valid because frozen head remains in chain history.',
    'Formatting-only changes preserve semantic integrity and baseline validity.',
    'Runtime behavior is unchanged; this phase only locks and validates certification metadata.'
)
Set-Content -LiteralPath (Join-Path $PF '15_behavior_summary.txt') -Value ($summary -join "`r`n") -Encoding UTF8 -NoNewline

$recordLines = [System.Collections.Generic.List[string]]::new()
$recordLines.Add('case|baseline_snapshot_path|baseline_integrity_record_path|stored_baseline_hash|computed_baseline_hash|stored_ledger_head_hash|computed_ledger_head_hash|stored_coverage_fingerprint_hash|computed_coverage_fingerprint_hash|baseline_integrity_result|baseline_reference_status|baseline_usage_allowed_or_blocked|reason')
foreach ($x in $records) {
    $o = $x.result
    $recordLines.Add(
        [string]$x.case + '|' +
        [string]$o.baseline_snapshot_path + '|' +
        [string]$o.baseline_integrity_record_path + '|' +
        [string]$o.stored_baseline_hash + '|' +
        [string]$o.computed_baseline_hash + '|' +
        [string]$o.stored_ledger_head_hash + '|' +
        [string]$o.computed_ledger_head_hash + '|' +
        [string]$o.stored_coverage_fingerprint_hash + '|' +
        [string]$o.computed_coverage_fingerprint_hash + '|' +
        [string]$o.baseline_integrity_result + '|' +
        [string]$o.baseline_reference_status + '|' +
        [string]$o.baseline_usage_allowed_or_blocked + '|' +
        [string]$o.reason
    )
}
Set-Content -LiteralPath (Join-Path $PF '16_baseline_integrity_record.txt') -Value (($recordLines.ToArray()) -join "`r`n") -Encoding UTF8 -NoNewline

$tamper = @(
    ('caseC_reason=' + [string]$caseCRes.reason),
    ('caseD_reason=' + [string]$caseDRes.reason),
    ('caseE_reason=' + [string]$caseERes.reason),
    ('caseE_ledger_head_match=' + [string]$caseERes.ledger_head_match),
    ('caseF_reason=' + [string]$caseFRes.reason),
    ('caseF_reference_status=' + [string]$caseFRes.baseline_reference_status),
    ('caseG_reason=' + [string]$caseGRes.reason)
)
Set-Content -LiteralPath (Join-Path $PF '17_baseline_tamper_evidence.txt') -Value ($tamper -join "`r`n") -Encoding UTF8 -NoNewline

Set-Content -LiteralPath (Join-Path $PF '98_gate_phase45_9.txt') -Value $Gate -Encoding UTF8 -NoNewline

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
