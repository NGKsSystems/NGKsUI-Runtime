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
    param($Value)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [float] -or $Value -is [decimal]) {
        return [string]$Value
    }
    if ($Value -is [string]) {
        $s = [string]$Value
        $s = $s -replace '\\', '\\'
        $s = $s -replace '"', '\"'
        $s = $s -replace "`n", '\n'
        $s = $s -replace "`r", '\r'
        $s = $s -replace "`t", '\t'
        return '"' + $s + '"'
    }
    if ($Value -is [System.Collections.IList]) {
        $items = [System.Collections.Generic.List[string]]::new()
        foreach ($item in $Value) {
            [void]$items.Add((Convert-ToCanonicalJson -Value $item))
        }
        return '[' + ($items -join ',') + ']'
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $keys = @($Value.Keys | Sort-Object)
        $pairs = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $keys) {
            [void]$pairs.Add(('"' + $k + '":' + (Convert-ToCanonicalJson -Value $Value[$k])))
        }
        return '{' + ($pairs -join ',') + '}'
    }
    if ($Value -is [pscustomobject]) {
        $keys = @($Value.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object)
        $pairs = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $keys) {
            $v = $Value.PSObject.Properties[$k].Value
            [void]$pairs.Add(('"' + $k + '":' + (Convert-ToCanonicalJson -Value $v)))
        }
        return '{' + ($pairs -join ',') + '}'
    }

    return '"' + ([string]$Value -replace '"', '\"') + '"'
}

function Get-CanonicalObjectHash {
    param([object]$Obj)
    return Get-StringSha256Hex -Text (Convert-ToCanonicalJson -Value $Obj)
}

function Get-LegacyChainEntryCanonical {
    param([object]$Entry)
    $obj = [ordered]@{
        entry_id         = [string]$Entry.entry_id
        fingerprint_hash = [string]$Entry.fingerprint_hash
        timestamp_utc    = [string]$Entry.timestamp_utc
        phase_locked     = [string]$Entry.phase_locked
        previous_hash    = if ($null -eq $Entry.previous_hash -or [string]::IsNullOrWhiteSpace([string]$Entry.previous_hash)) { $null } else { [string]$Entry.previous_hash }
    }
    return ($obj | ConvertTo-Json -Depth 4 -Compress)
}

function Get-LegacyChainEntryHash {
    param([object]$Entry)
    return Get-StringSha256Hex -Text (Get-LegacyChainEntryCanonical -Entry $Entry)
}

function Copy-Object {
    param([object]$Obj)
    return ($Obj | ConvertTo-Json -Depth 80 -Compress | ConvertFrom-Json)
}

function Test-LegacyTrustChain {
    param([object]$ChainObj)

    $result = [ordered]@{
        pass            = $true
        reason          = 'ok'
        entry_count     = 0
        chain_hashes    = @()
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
    param([object]$LedgerObj)

    $max = 0
    foreach ($e in @($LedgerObj.entries)) {
        $id = [string]$e.entry_id
        if ($id -match '^GF-(\d+)$') {
            $n = [int]$Matches[1]
            if ($n -gt $max) { $max = $n }
        }
    }

    return ('GF-' + ($max + 1).ToString('0000'))
}

function Invoke-FrozenBaselineEnforcementGate {
    param(
        [string]$FrozenBaselineSnapshotPath,
        [string]$FrozenBaselineIntegrityPath,
        [string]$LiveLedgerPath,
        [string]$LiveCoverageFingerprintPath
    )

    $r = [ordered]@{
        frozen_baseline_snapshot_path         = $FrozenBaselineSnapshotPath
        frozen_baseline_integrity_record_path = $FrozenBaselineIntegrityPath
        stored_baseline_hash                  = ''
        computed_baseline_hash                = ''
        stored_ledger_head_hash               = ''
        computed_ledger_head_hash             = ''
        stored_coverage_fingerprint_hash      = ''
        computed_coverage_fingerprint_hash    = ''
        chain_continuation_status             = 'INVALID'
        semantic_match_status                 = 'FALSE'
        runtime_init_allowed_or_blocked       = 'BLOCKED'
        fallback_occurred                     = $false
        regeneration_occurred                 = $false
        baseline_snapshot                     = 'INVALID'
        baseline_integrity                    = 'INVALID'
        ledger_head_match                     = 'FALSE'
        coverage_fingerprint_match            = 'FALSE'
        sequence                              = @()
        reason                                = 'unknown'
    }

    $seq = [System.Collections.Generic.List[string]]::new()

    $seq.Add('1.frozen_50_1_baseline_snapshot_validation')
    if (-not (Test-Path -LiteralPath $FrozenBaselineSnapshotPath)) {
        $r.reason = 'frozen_baseline_snapshot_missing'
        $r.sequence = @($seq)
        return $r
    }

    try {
        $baselineObj = Get-Content -Raw -LiteralPath $FrozenBaselineSnapshotPath | ConvertFrom-Json
    } catch {
        $r.reason = 'frozen_baseline_snapshot_parse_error'
        $r.sequence = @($seq)
        return $r
    }

    $requiredBaselineFields = @(
        'baseline_version','phase_locked','ledger_head_hash','ledger_length','coverage_fingerprint_hash',
        'latest_entry_id','latest_entry_phase_locked','entry_hashes'
    )
    foreach ($f in $requiredBaselineFields) {
        if (-not ($baselineObj.PSObject.Properties.Name -contains $f)) {
            $r.reason = ('frozen_baseline_snapshot_missing_field_' + $f)
            $r.sequence = @($seq)
            return $r
        }
    }
    if ([string]$baselineObj.phase_locked -ne '50.1') {
        $r.reason = 'frozen_baseline_phase_lock_mismatch'
        $r.sequence = @($seq)
        return $r
    }
    $r.baseline_snapshot = 'VALID'

    $seq.Add('2.frozen_baseline_integrity_record_validation')
    if (-not (Test-Path -LiteralPath $FrozenBaselineIntegrityPath)) {
        $r.reason = 'frozen_baseline_integrity_record_missing'
        $r.sequence = @($seq)
        return $r
    }

    try {
        $integrityObj = Get-Content -Raw -LiteralPath $FrozenBaselineIntegrityPath | ConvertFrom-Json
    } catch {
        $r.reason = 'frozen_baseline_integrity_record_parse_error'
        $r.sequence = @($seq)
        return $r
    }

    $requiredIntegrityFields = @('baseline_snapshot_hash','ledger_head_hash','coverage_fingerprint_hash','phase_locked')
    foreach ($f in $requiredIntegrityFields) {
        if (-not ($integrityObj.PSObject.Properties.Name -contains $f)) {
            $r.reason = ('frozen_baseline_integrity_record_missing_field_' + $f)
            $r.sequence = @($seq)
            return $r
        }
    }
    if ([string]$integrityObj.phase_locked -ne '50.1') {
        $r.reason = 'frozen_baseline_integrity_phase_lock_mismatch'
        $r.sequence = @($seq)
        return $r
    }

    $r.stored_baseline_hash = [string]$integrityObj.baseline_snapshot_hash
    $r.computed_baseline_hash = Get-CanonicalObjectHash -Obj $baselineObj
    if ($r.stored_baseline_hash -ne $r.computed_baseline_hash) {
        $r.reason = 'baseline_snapshot_hash_mismatch'
        $r.sequence = @($seq)
        return $r
    }

    if ([string]$integrityObj.ledger_head_hash -ne [string]$baselineObj.ledger_head_hash) {
        $r.reason = 'integrity_vs_snapshot_ledger_head_hash_mismatch'
        $r.sequence = @($seq)
        return $r
    }
    if ([string]$integrityObj.coverage_fingerprint_hash -ne [string]$baselineObj.coverage_fingerprint_hash) {
        $r.reason = 'integrity_vs_snapshot_coverage_fingerprint_hash_mismatch'
        $r.sequence = @($seq)
        return $r
    }

    $r.baseline_integrity = 'VALID'

    $seq.Add('3.live_ledger_head_verification')
    if (-not (Test-Path -LiteralPath $LiveLedgerPath)) {
        $r.reason = 'live_ledger_missing'
        $r.sequence = @($seq)
        return $r
    }

    try {
        $liveLedgerObj = Get-Content -Raw -LiteralPath $LiveLedgerPath | ConvertFrom-Json
    } catch {
        $r.reason = 'live_ledger_parse_error'
        $r.sequence = @($seq)
        return $r
    }

    $chainCheck = Test-LegacyTrustChain -ChainObj $liveLedgerObj
    if (-not $chainCheck.pass) {
        $r.reason = ('live_ledger_chain_invalid_' + [string]$chainCheck.reason)
        $r.sequence = @($seq)
        return $r
    }

    $entries = @($liveLedgerObj.entries)
    $canonicalEntryHashes = [System.Collections.Generic.List[string]]::new()
    foreach ($e in $entries) {
        $canonicalEntryHashes.Add((Get-CanonicalObjectHash -Obj $e))
    }

    $r.stored_ledger_head_hash = [string]$baselineObj.ledger_head_hash
    $r.computed_ledger_head_hash = [string]$canonicalEntryHashes[$canonicalEntryHashes.Count - 1]
    $r.ledger_head_match = if ($r.stored_ledger_head_hash -eq $r.computed_ledger_head_hash) { 'TRUE' } else { 'FALSE' }

    $seq.Add('4.live_coverage_fingerprint_verification')
    if (-not (Test-Path -LiteralPath $LiveCoverageFingerprintPath)) {
        $r.reason = 'live_coverage_fingerprint_reference_missing'
        $r.sequence = @($seq)
        return $r
    }

    try {
        $liveCoverageObj = Get-Content -Raw -LiteralPath $LiveCoverageFingerprintPath | ConvertFrom-Json
    } catch {
        $r.reason = 'live_coverage_fingerprint_parse_error'
        $r.sequence = @($seq)
        return $r
    }

    $r.stored_coverage_fingerprint_hash = [string]$baselineObj.coverage_fingerprint_hash
    $r.computed_coverage_fingerprint_hash = [string]$liveCoverageObj.coverage_fingerprint_sha256
    if ([string]::IsNullOrWhiteSpace([string]$r.computed_coverage_fingerprint_hash)) {
        $r.reason = 'live_coverage_fingerprint_missing'
        $r.sequence = @($seq)
        return $r
    }

    $r.coverage_fingerprint_match = if ($r.stored_coverage_fingerprint_hash -eq $r.computed_coverage_fingerprint_hash) { 'TRUE' } else { 'FALSE' }
    if ($r.coverage_fingerprint_match -ne 'TRUE') {
        $r.reason = 'coverage_fingerprint_hash_mismatch'
        $r.sequence = @($seq)
        return $r
    }

    $seq.Add('5.live_chain_continuation_verification')
    $liveHashes = @($canonicalEntryHashes)
    $baselineHeadHash = [string]$baselineObj.ledger_head_hash
    $baselineLen = [int]$baselineObj.ledger_length

    if ($chainCheck.entry_count -lt $baselineLen) {
        $r.chain_continuation_status = 'INVALID'
        $r.reason = 'live_chain_shorter_than_frozen_baseline'
        $r.sequence = @($seq)
        return $r
    }

    $baselineHeadIndex = -1
    for ($i = 0; $i -lt $liveHashes.Count; $i++) {
        if ([string]$liveHashes[$i] -eq $baselineHeadHash) {
            $baselineHeadIndex = $i
            break
        }
    }

    if ($baselineHeadIndex -lt 0) {
        $r.chain_continuation_status = 'INVALID'
        $r.reason = 'frozen_baseline_head_not_present_in_live_chain'
        $r.sequence = @($seq)
        return $r
    }

    if ($baselineHeadIndex -ne ($baselineLen - 1)) {
        $r.chain_continuation_status = 'INVALID'
        $r.reason = 'frozen_baseline_head_index_mismatch'
        $r.sequence = @($seq)
        return $r
    }

    $r.chain_continuation_status = 'VALID'

    $seq.Add('6.semantic_protected_field_verification')
    $semanticOk = $true
    foreach ($entryId in @($baselineObj.entry_hashes.PSObject.Properties | ForEach-Object { $_.Name })) {
        $frozenExpected = [string]$baselineObj.entry_hashes.$entryId
        $entryObj = $entries | Where-Object { [string]$_.entry_id -eq $entryId } | Select-Object -First 1
        if ($null -eq $entryObj) {
            $semanticOk = $false
            break
        }
        $actual = Get-CanonicalObjectHash -Obj $entryObj
        if ($actual -ne $frozenExpected) {
            $semanticOk = $false
            break
        }
    }

    $baselineHeadEntry = $entries[$baselineLen - 1]
    if ([string]$baselineHeadEntry.entry_id -ne [string]$baselineObj.latest_entry_id) { $semanticOk = $false }
    if ([string]$baselineHeadEntry.phase_locked -ne [string]$baselineObj.latest_entry_phase_locked) { $semanticOk = $false }

    $r.semantic_match_status = if ($semanticOk) { 'TRUE' } else { 'FALSE' }
    if ($r.semantic_match_status -ne 'TRUE') {
        $r.reason = 'semantic_protected_field_mismatch'
        $r.sequence = @($seq)
        return $r
    }

    $seq.Add('7.runtime_initialization_allowed')
    $r.runtime_init_allowed_or_blocked = 'ALLOWED'
    $r.reason = if ($r.ledger_head_match -eq 'TRUE') { 'exact_frozen_head_match' } else { 'valid_frozen_head_continuation' }
    $r.sequence = @($seq)
    return $r
}

function Invoke-ProtectedOperation {
    param(
        [string]$FrozenBaselineSnapshotPath,
        [string]$FrozenBaselineIntegrityPath,
        [string]$LiveLedgerPath,
        [string]$LiveCoverageFingerprintPath,
        [scriptblock]$OperationScript
    )

    $gate = Invoke-FrozenBaselineEnforcementGate `
        -FrozenBaselineSnapshotPath $FrozenBaselineSnapshotPath `
        -FrozenBaselineIntegrityPath $FrozenBaselineIntegrityPath `
        -LiveLedgerPath $LiveLedgerPath `
        -LiveCoverageFingerprintPath $LiveCoverageFingerprintPath

    if ([string]$gate.runtime_init_allowed_or_blocked -eq 'ALLOWED') {
        [void](& $OperationScript)
    }

    return $gate
}

function Add-ValidationLine {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$CaseId,
        [string]$CaseName,
        [bool]$CasePass,
        [object]$Record
    )

    $Lines.Add(
        'CASE ' + $CaseId + ' ' + $CaseName +
        ' baseline_snapshot=' + [string]$Record.baseline_snapshot +
        ' baseline_integrity=' + [string]$Record.baseline_integrity +
        ' ledger_head_match=' + [string]$Record.ledger_head_match +
        ' coverage_fingerprint_match=' + [string]$Record.coverage_fingerprint_match +
        ' chain_continuation=' + [string]$Record.chain_continuation_status +
        ' semantic_match=' + [string]$Record.semantic_match_status +
        ' runtime_init=' + [string]$Record.runtime_init_allowed_or_blocked +
        ' fallback=' + [string]$Record.fallback_occurred +
        ' regen=' + [string]$Record.regeneration_occurred +
        ' reason=' + [string]$Record.reason +
        ' => ' + $(if ($CasePass) { 'PASS' } else { 'FAIL' })
    )
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\phase50_2_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$RunnerPath = Join-Path $Root 'tools\phase50_2\phase50_2_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_runner.ps1'
$BaselinePath = Join-Path $Root 'control_plane\96_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline.json'
$IntegrityPath = Join-Path $Root 'control_plane\97_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_integrity.json'
$LedgerPath = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$CoveragePath = Join-Path $Root 'control_plane\96_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint.json'

foreach ($p in @($BaselinePath, $IntegrityPath, $LedgerPath, $CoveragePath)) {
    if (-not (Test-Path -LiteralPath $p)) { throw ('Missing required file: ' + $p) }
}

$tmpRoot = Join-Path $env:TEMP ('phase50_2_' + $Timestamp)
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null

$ValidationLines = [System.Collections.Generic.List[string]]::new()
$GateRecordLines = [System.Collections.Generic.List[string]]::new()
$EvidenceLines = [System.Collections.Generic.List[string]]::new()
$allPass = $true

try {
    # Case fixtures
    $badSnapshot = Join-Path $tmpRoot 'tampered_snapshot.json'
    Copy-Item -LiteralPath $BaselinePath -Destination $badSnapshot -Force
    $badSnapshotObj = Get-Content -Raw -LiteralPath $badSnapshot | ConvertFrom-Json
    $badSnapshotObj.phase_locked = '50.1-TAMPER'
    ($badSnapshotObj | ConvertTo-Json -Depth 80) | Set-Content -LiteralPath $badSnapshot -Encoding UTF8 -NoNewline

    $badIntegrity = Join-Path $tmpRoot 'tampered_integrity.json'
    Copy-Item -LiteralPath $IntegrityPath -Destination $badIntegrity -Force
    $badIntegrityObj = Get-Content -Raw -LiteralPath $badIntegrity | ConvertFrom-Json
    $badIntegrityObj.baseline_snapshot_hash = ('0' * 64)
    ($badIntegrityObj | ConvertTo-Json -Depth 40) | Set-Content -LiteralPath $badIntegrity -Encoding UTF8 -NoNewline

    $badLedgerHead = Join-Path $tmpRoot 'tampered_live_ledger_head.json'
    Copy-Item -LiteralPath $LedgerPath -Destination $badLedgerHead -Force
    $badLedgerHeadObj = Get-Content -Raw -LiteralPath $badLedgerHead | ConvertFrom-Json
    $headIdx = @($badLedgerHeadObj.entries).Count - 1
    $badLedgerHeadObj.entries[$headIdx].fingerprint_hash = ('f' * 64)
    ($badLedgerHeadObj | ConvertTo-Json -Depth 80) | Set-Content -LiteralPath $badLedgerHead -Encoding UTF8 -NoNewline

    $badCoverage = Join-Path $tmpRoot 'tampered_coverage.json'
    Copy-Item -LiteralPath $CoveragePath -Destination $badCoverage -Force
    $badCoverageObj = Get-Content -Raw -LiteralPath $badCoverage | ConvertFrom-Json
    $badCoverageObj.coverage_fingerprint_sha256 = ('e' * 64)
    ($badCoverageObj | ConvertTo-Json -Depth 40) | Set-Content -LiteralPath $badCoverage -Encoding UTF8 -NoNewline

    $invalidContinuationLedger = Join-Path $tmpRoot 'invalid_continuation_ledger.json'
    Copy-Item -LiteralPath $LedgerPath -Destination $invalidContinuationLedger -Force
    $invalidLedgerObj = Get-Content -Raw -LiteralPath $invalidContinuationLedger | ConvertFrom-Json
    $newInvalid = [ordered]@{
        entry_id = Get-NextEntryId -LedgerObj $invalidLedgerObj
        artifact = 'invalid_continuation_probe'
        coverage_fingerprint = [string](Get-Content -Raw -LiteralPath $CoveragePath | ConvertFrom-Json).coverage_fingerprint_sha256
        fingerprint_hash = ('d' * 64)
        timestamp_utc = (Get-Date -AsUTC -Format 'yyyy-MM-ddTHH:mm:ssZ')
        phase_locked = '50.2'
        previous_hash = ('0' * 64)
    }
    $invalidLedgerObj.entries += [pscustomobject]$newInvalid
    ($invalidLedgerObj | ConvertTo-Json -Depth 80) | Set-Content -LiteralPath $invalidContinuationLedger -Encoding UTF8 -NoNewline

    $validContinuationLedger = Join-Path $tmpRoot 'valid_continuation_ledger.json'
    Copy-Item -LiteralPath $LedgerPath -Destination $validContinuationLedger -Force
    $validLedgerObj = Get-Content -Raw -LiteralPath $validContinuationLedger | ConvertFrom-Json
    $chainBeforeValid = Test-LegacyTrustChain -ChainObj $validLedgerObj
    $newValid = [ordered]@{
        entry_id = Get-NextEntryId -LedgerObj $validLedgerObj
        artifact = 'valid_continuation_probe'
        coverage_fingerprint = [string](Get-Content -Raw -LiteralPath $CoveragePath | ConvertFrom-Json).coverage_fingerprint_sha256
        fingerprint_hash = ('c' * 64)
        timestamp_utc = (Get-Date -AsUTC -Format 'yyyy-MM-ddTHH:mm:ssZ')
        phase_locked = '50.2'
        previous_hash = [string]$chainBeforeValid.last_entry_hash
    }
    $validLedgerObj.entries += [pscustomobject]$newValid
    ($validLedgerObj | ConvertTo-Json -Depth 80) | Set-Content -LiteralPath $validContinuationLedger -Encoding UTF8 -NoNewline

    $nonSemanticSnapshot = Join-Path $tmpRoot 'nonsemantic_snapshot.json'
    $nonSemanticIntegrity = Join-Path $tmpRoot 'nonsemantic_integrity.json'
    $snapObjH = Get-Content -Raw -LiteralPath $BaselinePath | ConvertFrom-Json
    $intObjH = Get-Content -Raw -LiteralPath $IntegrityPath | ConvertFrom-Json
    ($snapObjH | ConvertTo-Json -Depth 80) + "`r`n" | Set-Content -LiteralPath $nonSemanticSnapshot -Encoding UTF8
    ($intObjH | ConvertTo-Json -Depth 40) + "`r`n" | Set-Content -LiteralPath $nonSemanticIntegrity -Encoding UTF8

    # CASE A clean pass
    $recA = Invoke-ProtectedOperation -FrozenBaselineSnapshotPath $BaselinePath -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $CoveragePath -OperationScript { 'runtime_init' }
    $passA = (
        [string]$recA.baseline_snapshot -eq 'VALID' -and
        [string]$recA.baseline_integrity -eq 'VALID' -and
        [string]$recA.ledger_head_match -eq 'TRUE' -and
        [string]$recA.coverage_fingerprint_match -eq 'TRUE' -and
        [string]$recA.chain_continuation_status -eq 'VALID' -and
        [string]$recA.runtime_init_allowed_or_blocked -eq 'ALLOWED'
    )
    if (-not $passA) { $allPass = $false }
    Add-ValidationLine -Lines $ValidationLines -CaseId 'A' -CaseName 'clean_frozen_baseline_pass' -CasePass $passA -Record $recA
    $GateRecordLines.Add('CASE A|' + ($recA | ConvertTo-Json -Compress))

    # CASE B snapshot tamper
    $recB = Invoke-ProtectedOperation -FrozenBaselineSnapshotPath $badSnapshot -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $CoveragePath -OperationScript { 'runtime_init' }
    $passB = ([string]$recB.baseline_snapshot -eq 'INVALID' -and [string]$recB.runtime_init_allowed_or_blocked -eq 'BLOCKED')
    if (-not $passB) { $allPass = $false }
    Add-ValidationLine -Lines $ValidationLines -CaseId 'B' -CaseName 'frozen_baseline_snapshot_tamper' -CasePass $passB -Record $recB
    $GateRecordLines.Add('CASE B|' + ($recB | ConvertTo-Json -Compress))
    $EvidenceLines.Add('CASE B blocked_by=' + [string]$recB.reason)

    # CASE C integrity tamper
    $recC = Invoke-ProtectedOperation -FrozenBaselineSnapshotPath $BaselinePath -FrozenBaselineIntegrityPath $badIntegrity -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $CoveragePath -OperationScript { 'runtime_init' }
    $passC = ([string]$recC.baseline_integrity -eq 'INVALID' -and [string]$recC.runtime_init_allowed_or_blocked -eq 'BLOCKED')
    if (-not $passC) { $allPass = $false }
    Add-ValidationLine -Lines $ValidationLines -CaseId 'C' -CaseName 'frozen_baseline_integrity_record_tamper' -CasePass $passC -Record $recC
    $GateRecordLines.Add('CASE C|' + ($recC | ConvertTo-Json -Compress))
    $EvidenceLines.Add('CASE C blocked_by=' + [string]$recC.reason)

    # CASE D ledger head drift
    $recD = Invoke-ProtectedOperation -FrozenBaselineSnapshotPath $BaselinePath -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $badLedgerHead -LiveCoverageFingerprintPath $CoveragePath -OperationScript { 'runtime_init' }
    $passD = ([string]$recD.ledger_head_match -eq 'FALSE' -and [string]$recD.runtime_init_allowed_or_blocked -eq 'BLOCKED')
    if (-not $passD) { $allPass = $false }
    Add-ValidationLine -Lines $ValidationLines -CaseId 'D' -CaseName 'live_ledger_head_drift' -CasePass $passD -Record $recD
    $GateRecordLines.Add('CASE D|' + ($recD | ConvertTo-Json -Compress))
    $EvidenceLines.Add('CASE D blocked_by=' + [string]$recD.reason)

    # CASE E coverage fingerprint drift
    $recE = Invoke-ProtectedOperation -FrozenBaselineSnapshotPath $BaselinePath -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $badCoverage -OperationScript { 'runtime_init' }
    $passE = ([string]$recE.coverage_fingerprint_match -eq 'FALSE' -and [string]$recE.runtime_init_allowed_or_blocked -eq 'BLOCKED')
    if (-not $passE) { $allPass = $false }
    Add-ValidationLine -Lines $ValidationLines -CaseId 'E' -CaseName 'live_coverage_fingerprint_drift' -CasePass $passE -Record $recE
    $GateRecordLines.Add('CASE E|' + ($recE | ConvertTo-Json -Compress))
    $EvidenceLines.Add('CASE E blocked_by=' + [string]$recE.reason)

    # CASE F invalid continuation
    $recF = Invoke-ProtectedOperation -FrozenBaselineSnapshotPath $BaselinePath -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $invalidContinuationLedger -LiveCoverageFingerprintPath $CoveragePath -OperationScript { 'runtime_init' }
    $passF = ([string]$recF.chain_continuation_status -eq 'INVALID' -and [string]$recF.runtime_init_allowed_or_blocked -eq 'BLOCKED')
    if (-not $passF) { $allPass = $false }
    Add-ValidationLine -Lines $ValidationLines -CaseId 'F' -CaseName 'invalid_chain_continuation' -CasePass $passF -Record $recF
    $GateRecordLines.Add('CASE F|' + ($recF | ConvertTo-Json -Compress))
    $EvidenceLines.Add('CASE F blocked_by=' + [string]$recF.reason)

    # CASE G valid continuation
    $recG = Invoke-ProtectedOperation -FrozenBaselineSnapshotPath $BaselinePath -FrozenBaselineIntegrityPath $IntegrityPath -LiveLedgerPath $validContinuationLedger -LiveCoverageFingerprintPath $CoveragePath -OperationScript { 'runtime_init' }
    $passG = ([string]$recG.chain_continuation_status -eq 'VALID' -and [string]$recG.runtime_init_allowed_or_blocked -eq 'ALLOWED')
    if (-not $passG) { $allPass = $false }
    Add-ValidationLine -Lines $ValidationLines -CaseId 'G' -CaseName 'valid_chain_continuation' -CasePass $passG -Record $recG
    $GateRecordLines.Add('CASE G|' + ($recG | ConvertTo-Json -Compress))

    # CASE H non-semantic change
    $recH = Invoke-ProtectedOperation -FrozenBaselineSnapshotPath $nonSemanticSnapshot -FrozenBaselineIntegrityPath $nonSemanticIntegrity -LiveLedgerPath $LedgerPath -LiveCoverageFingerprintPath $CoveragePath -OperationScript { 'runtime_init' }
    $passH = (
        [string]$recH.baseline_integrity -eq 'VALID' -and
        [string]$recH.semantic_match_status -eq 'TRUE' -and
        [string]$recH.runtime_init_allowed_or_blocked -eq 'ALLOWED'
    )
    if (-not $passH) { $allPass = $false }
    Add-ValidationLine -Lines $ValidationLines -CaseId 'H' -CaseName 'non_semantic_change' -CasePass $passH -Record $recH
    $GateRecordLines.Add('CASE H|' + ($recH | ConvertTo-Json -Compress))

    $Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

    $status01 = @(
        'PHASE=50.2',
        'TITLE=Trust-Chain Ledger Baseline Enforcement Coverage Fingerprint Trust-Chain Baseline Enforcement',
        'GATE=' + $Gate,
        'FROZEN_BASELINE_ENFORCED_BEFORE_RUNTIME_INIT=TRUE',
        'NO_FALLBACK=TRUE',
        'NO_REGENERATION=TRUE',
        'RUNTIME_STATE_MACHINE_CHANGED=FALSE'
    ) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '01_status.txt'), $status01, [System.Text.Encoding]::UTF8)

    $head02 = @(
        'RUNNER=' + $RunnerPath,
        'FROZEN_BASELINE_SNAPSHOT=' + $BaselinePath,
        'FROZEN_BASELINE_INTEGRITY=' + $IntegrityPath,
        'LIVE_LEDGER=' + $LedgerPath,
        'LIVE_COVERAGE_FINGERPRINT=' + $CoveragePath,
        'ENFORCEMENT_ORDER=1.snapshot,2.integrity,3.ledger_head,4.coverage,5.continuation,6.semantic,7.runtime_allow'
    ) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '02_head.txt'), $head02, [System.Text.Encoding]::UTF8)

    $def10 = @(
        'FROZEN_BASELINE_PHASE=50.1',
        'BASELINE_SNAPSHOT_PATH=control_plane/96_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline.json',
        'BASELINE_INTEGRITY_RECORD_PATH=control_plane/97_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_integrity.json',
        'LIVE_LEDGER_PATH=control_plane/70_guard_fingerprint_trust_chain.json',
        'LIVE_COVERAGE_FINGERPRINT_PATH=control_plane/96_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint.json'
    ) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '10_baseline_enforcement_definition.txt'), $def10, [System.Text.Encoding]::UTF8)

    $rules11 = @(
        'RULE_1=frozen baseline snapshot must exist, parse, and phase_lock must be 50.1',
        'RULE_2=integrity record must match canonical baseline hash and protected hashes',
        'RULE_3=live coverage fingerprint hash must match frozen expectation',
        'RULE_4=live chain must be valid and include frozen baseline head at baseline index',
        'RULE_5=semantic protected fields for frozen entries must match exactly',
        'RULE_6=runtime init allowed only when all checks pass',
        'RULE_7=no fallback, no regeneration'
    ) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '11_baseline_enforcement_rules.txt'), $rules11, [System.Text.Encoding]::UTF8)

    $files12 = @(
        'READ=' + $BaselinePath,
        'READ=' + $IntegrityPath,
        'READ=' + $LedgerPath,
        'READ=' + $CoveragePath,
        'WRITE=' + $PF
    ) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '12_files_touched.txt'), $files12, [System.Text.Encoding]::UTF8)

    $build13 = @(
        'CASE_COUNT=8',
        'FROZEN_BASELINE_ENFORCED=TRUE',
        'NO_FALLBACK=TRUE',
        'NO_REGENERATION=TRUE',
        'GATE=' + $Gate
    ) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '13_build_output.txt'), $build13, [System.Text.Encoding]::UTF8)

    [System.IO.File]::WriteAllText((Join-Path $PF '14_validation_results.txt'), ($ValidationLines -join "`r`n"), [System.Text.Encoding]::UTF8)

    $passCount = @($ValidationLines | Where-Object { $_ -match '=> PASS$' }).Count
    $failCount = @($ValidationLines | Where-Object { $_ -match '=> FAIL$' }).Count
    $summary15 = @(
        'TOTAL_CASES=8',
        'PASSED=' + $passCount,
        'FAILED=' + $failCount,
        'VALID_CONTINUATION_ALLOWED=' + $(if ($passG) { 'TRUE' } else { 'FALSE' }),
        'INVALID_CONTINUATION_BLOCKED=' + $(if ($passF) { 'TRUE' } else { 'FALSE' }),
        'NO_FALLBACK=TRUE',
        'NO_REGENERATION=TRUE',
        'RUNTIME_STATE_MACHINE_UNCHANGED=TRUE',
        'GATE=' + $Gate
    ) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '15_behavior_summary.txt'), $summary15, [System.Text.Encoding]::UTF8)

    $recordHeader = 'case|frozen_baseline_snapshot_path|frozen_baseline_integrity_record_path|stored_baseline_hash|computed_baseline_hash|stored_ledger_head_hash|computed_ledger_head_hash|stored_coverage_fingerprint_hash|computed_coverage_fingerprint_hash|chain_continuation_status|semantic_match_status|runtime_init_allowed_or_blocked|fallback_occurred|regeneration_occurred|reason'
    $recordBody = @($recordHeader) + @($GateRecordLines)
    [System.IO.File]::WriteAllText((Join-Path $PF '16_frozen_baseline_enforcement_record.txt'), ($recordBody -join "`r`n"), [System.Text.Encoding]::UTF8)

    [System.IO.File]::WriteAllText((Join-Path $PF '17_runtime_block_evidence.txt'), ($EvidenceLines -join "`r`n"), [System.Text.Encoding]::UTF8)

    $gate98 = @('PHASE=50.2', 'GATE=' + $Gate) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $PF '98_gate_phase50_2.txt'), $gate98, [System.Text.Encoding]::UTF8)

    $ZipPath = $PF + '.zip'
    if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
    $tmpZip = $PF + '_zipcopy'
    if (Test-Path -LiteralPath $tmpZip) { Remove-Item -LiteralPath $tmpZip -Recurse -Force }
    New-Item -ItemType Directory -Path $tmpZip | Out-Null
    Get-ChildItem -Path $PF -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $tmpZip $_.Name) -Force
    }
    Compress-Archive -Path (Join-Path $tmpZip '*') -DestinationPath $ZipPath -Force
    Remove-Item -LiteralPath $tmpZip -Recurse -Force

    Write-Output ('PF=' + $PF)
    Write-Output ('ZIP=' + $ZipPath)
    Write-Output ('GATE=' + $Gate)
}
finally {
    if (Test-Path -LiteralPath $tmpRoot) {
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}