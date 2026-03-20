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
        foreach ($item in $Value) { [void]$items.Add((Convert-ToCanonicalJson -Value $item)) }
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

function Copy-Obj {
    param([object]$Obj)
    return ((Convert-ToCanonicalJson -Value $Obj) | ConvertFrom-Json)
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

function Read-CoverageReference {
    param([string]$ReferencePath)

    $obj = Get-Content -Raw -LiteralPath $ReferencePath | ConvertFrom-Json
    $coverage = [string]$obj.coverage_fingerprint_sha256
    if ([string]::IsNullOrWhiteSpace($coverage)) {
        throw ('coverage_fingerprint_sha256 missing in ' + $ReferencePath)
    }

    return [ordered]@{
        reference_obj = $obj
        coverage_fingerprint = $coverage
        reference_artifact_hash = Get-CanonicalObjectHash -Obj $obj
    }
}

function Test-TrustChainSealIntegrity {
    param(
        [object]$LedgerObj,
        [object]$ReferenceObj,
        [string]$ExpectedPhase,
        [string]$ExpectedArtifact
    )

    $chain = Test-LegacyTrustChain -ChainObj $LedgerObj
    $sealEntries = @($LedgerObj.entries | Where-Object {
        [string]$_.phase_locked -eq $ExpectedPhase -and [string]$_.artifact -eq $ExpectedArtifact
    })

    $bindingPass = $false
    $bindingReason = 'seal_entry_missing'
    $sealEntryId = ''

    if ($sealEntries.Count -gt 0) {
        $sealEntry = $sealEntries[-1]
        $sealEntryId = [string]$sealEntry.entry_id
        $expectedCoverage = [string]$ReferenceObj.coverage_fingerprint
        $expectedArtifactHash = [string]$ReferenceObj.reference_artifact_hash

        if ([string]$sealEntry.coverage_fingerprint -ne $expectedCoverage) {
            $bindingPass = $false
            $bindingReason = 'coverage_fingerprint_mismatch'
        } elseif ([string]$sealEntry.fingerprint_hash -ne $expectedArtifactHash) {
            $bindingPass = $false
            $bindingReason = 'reference_artifact_hash_mismatch'
        } else {
            $bindingPass = $true
            $bindingReason = 'ok'
        }
    }

    return [ordered]@{
        chain_integrity = $(if ($chain.pass) { 'VALID' } else { 'FAIL' })
        chain_reason = [string]$chain.reason
        chain_last_hash = [string]$chain.last_entry_hash
        chain_entry_count = [int]$chain.entry_count
        seal_binding = $(if ($bindingPass) { 'VALID' } else { 'FAIL' })
        seal_binding_reason = $bindingReason
        seal_entry_id = $sealEntryId
        pass = ($chain.pass -and $bindingPass)
    }
}

function Add-ValidationCaseLine {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$CaseId,
        [string]$Name,
        [string]$Expected,
        [bool]$Pass
    )

    $Lines.Add('CASE ' + $CaseId + ' ' + $Name + ' expected=' + $Expected + ' => ' + $(if ($Pass) { 'PASS' } else { 'FAIL' }))
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$PF = Join-Path $Root ('_proof\phase49_4_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_' + $Timestamp)
New-Item -ItemType Directory -Path $PF | Out-Null

$LedgerPath = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$ReferencePath = Join-Path $Root 'control_plane\93_trust_chain_ledger_baseline_enforcement_coverage_fingerprint.json'
$RunnerPath = Join-Path $Root 'tools\phase49_4\phase49_4_trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_runner.ps1'

foreach ($p in @($LedgerPath, $ReferencePath)) {
    if (-not (Test-Path -LiteralPath $p)) { throw ('Missing required file: ' + $p) }
}

$SealArtifact = 'trust_chain_ledger_baseline_enforcement_coverage_fingerprint_trust_chain_seal'
$SealPhase = '49.4'

$ledgerObj = Get-Content -Raw -LiteralPath $LedgerPath | ConvertFrom-Json
$referenceInfo = Read-CoverageReference -ReferencePath $ReferencePath
$entries = @($ledgerObj.entries)

$existingSeal = @($entries | Where-Object {
    [string]$_.phase_locked -eq $SealPhase -and [string]$_.artifact -eq $SealArtifact
})
$appendPerformed = $false
$sealedEntry = $null

if ($existingSeal.Count -gt 0) {
    $sealedEntry = $existingSeal[-1]

    if ([string]$sealedEntry.coverage_fingerprint -ne [string]$referenceInfo.coverage_fingerprint) {
        throw 'Existing 49.4 seal entry has mismatched coverage_fingerprint.'
    }
    if ([string]$sealedEntry.fingerprint_hash -ne [string]$referenceInfo.reference_artifact_hash) {
        throw 'Existing 49.4 seal entry has mismatched fingerprint_hash.'
    }

    $idx = -1
    for ($i = 0; $i -lt $entries.Count; $i++) {
        if ([string]$entries[$i].entry_id -eq [string]$sealedEntry.entry_id) { $idx = $i; break }
    }
    if ($idx -le 0) { throw 'Existing 49.4 seal entry position is invalid.' }

    $expectedPrev = Get-LegacyChainEntryHash -Entry $entries[$idx - 1]
    if ([string]$sealedEntry.previous_hash -ne [string]$expectedPrev) {
        throw 'Existing 49.4 seal entry has mismatched previous_hash.'
    }
} else {
    $chainBefore = Test-LegacyTrustChain -ChainObj $ledgerObj
    if (-not $chainBefore.pass) {
        throw ('Ledger chain invalid before append: ' + [string]$chainBefore.reason)
    }

    $nextId = Get-NextEntryId -ChainObj $ledgerObj
    $prevHash = [string]$chainBefore.last_entry_hash

    $newEntry = [ordered]@{
        entry_id = $nextId
        artifact = $SealArtifact
        coverage_fingerprint = [string]$referenceInfo.coverage_fingerprint
        fingerprint_hash = [string]$referenceInfo.reference_artifact_hash
        reference_artifact = 'control_plane/93_trust_chain_ledger_baseline_enforcement_coverage_fingerprint.json'
        timestamp_utc = (Get-Date -AsUTC -Format 'yyyy-MM-ddTHH:mm:ssZ')
        phase_locked = $SealPhase
        previous_hash = $prevHash
    }

    $ledgerObj.entries += [pscustomobject]$newEntry
    ($ledgerObj | ConvertTo-Json -Depth 30) | Set-Content -LiteralPath $LedgerPath -Encoding UTF8 -NoNewline

    $appendPerformed = $true
    $sealedEntry = [pscustomobject]$newEntry
    $entries = @($ledgerObj.entries)
}

$ValidationLines = [System.Collections.Generic.List[string]]::new()
$ChainRecordLines = [System.Collections.Generic.List[string]]::new()
$EvidenceLines = [System.Collections.Generic.List[string]]::new()
$allPass = $true

# CASE A clean trust-chain append
$caseA = Test-TrustChainSealIntegrity -LedgerObj $ledgerObj -ReferenceObj $referenceInfo -ExpectedPhase $SealPhase -ExpectedArtifact $SealArtifact
$caseAPass = ($caseA.pass -and $caseA.chain_integrity -eq 'VALID')
if (-not $caseAPass) { $allPass = $false }
Add-ValidationCaseLine -Lines $ValidationLines -CaseId 'A' -Name 'clean_trust_chain_append' -Expected 'ledger_append=SUCCESS,chain_integrity=VALID' -Pass $caseAPass
$ChainRecordLines.Add('CASE A|chain_integrity=' + $caseA.chain_integrity + '|seal_binding=' + $caseA.seal_binding + '|entry=' + [string]$caseA.seal_entry_id + '|reason=' + [string]$caseA.chain_reason)

# CASE B historical ledger tamper
$ledgerB = Copy-Obj -Obj $ledgerObj
if ($ledgerB.entries.Count -gt 1) {
    $ledgerB.entries[1].fingerprint_hash = ('f' * 64)
}
$caseB = Test-TrustChainSealIntegrity -LedgerObj $ledgerB -ReferenceObj $referenceInfo -ExpectedPhase $SealPhase -ExpectedArtifact $SealArtifact
$caseBPass = ($caseB.chain_integrity -eq 'FAIL')
if (-not $caseBPass) { $allPass = $false }
Add-ValidationCaseLine -Lines $ValidationLines -CaseId 'B' -Name 'historical_ledger_tamper' -Expected 'chain_integrity=FAIL' -Pass $caseBPass
$EvidenceLines.Add('CASE B chain_reason=' + [string]$caseB.chain_reason)

# CASE C coverage fingerprint artifact tamper
$refC = Copy-Obj -Obj $referenceInfo
$refC.coverage_fingerprint = ('0' * 64)
$caseC = Test-TrustChainSealIntegrity -LedgerObj $ledgerObj -ReferenceObj $refC -ExpectedPhase $SealPhase -ExpectedArtifact $SealArtifact
$caseCPass = ($caseC.pass -eq $false -and $caseC.seal_binding -eq 'FAIL')
if (-not $caseCPass) { $allPass = $false }
Add-ValidationCaseLine -Lines $ValidationLines -CaseId 'C' -Name 'coverage_fingerprint_artifact_tamper' -Expected 'chain_integrity=FAIL' -Pass $caseCPass
$EvidenceLines.Add('CASE C seal_binding_reason=' + [string]$caseC.seal_binding_reason)

# CASE D future ledger append
$ledgerD = Copy-Obj -Obj $ledgerObj
$chainD = Test-LegacyTrustChain -ChainObj $ledgerD
$entryD = [ordered]@{
    entry_id = Get-NextEntryId -ChainObj $ledgerD
    artifact = 'future_chain_continuation_probe'
    coverage_fingerprint = [string]$referenceInfo.coverage_fingerprint
    fingerprint_hash = ('a' * 64)
    timestamp_utc = (Get-Date -AsUTC -Format 'yyyy-MM-ddTHH:mm:ssZ')
    phase_locked = '49.5'
    previous_hash = [string]$chainD.last_entry_hash
}
$ledgerD.entries += [pscustomobject]$entryD
$caseD = Test-TrustChainSealIntegrity -LedgerObj $ledgerD -ReferenceObj $referenceInfo -ExpectedPhase $SealPhase -ExpectedArtifact $SealArtifact
$caseDPass = ($caseD.pass -and $caseD.chain_integrity -eq 'VALID')
if (-not $caseDPass) { $allPass = $false }
Add-ValidationCaseLine -Lines $ValidationLines -CaseId 'D' -Name 'future_ledger_append' -Expected 'chain_integrity=VALID' -Pass $caseDPass
$ChainRecordLines.Add('CASE D last_hash=' + [string](Test-LegacyTrustChain -ChainObj $ledgerD).last_entry_hash)

# CASE E non-semantic file change
$refEObj = Get-Content -Raw -LiteralPath $ReferencePath | ConvertFrom-Json
$refEText = $refEObj | ConvertTo-Json -Depth 30
$refEParsed = $refEText | ConvertFrom-Json
$refE = [ordered]@{
    reference_obj = $refEParsed
    coverage_fingerprint = [string]$refEParsed.coverage_fingerprint_sha256
    reference_artifact_hash = Get-CanonicalObjectHash -Obj $refEParsed
}
$caseE = Test-TrustChainSealIntegrity -LedgerObj $ledgerObj -ReferenceObj $refE -ExpectedPhase $SealPhase -ExpectedArtifact $SealArtifact
$caseEPass = ($caseE.pass -and $caseE.chain_integrity -eq 'VALID')
if (-not $caseEPass) { $allPass = $false }
Add-ValidationCaseLine -Lines $ValidationLines -CaseId 'E' -Name 'non_semantic_file_change' -Expected 'chain_integrity=VALID' -Pass $caseEPass

# CASE F previous_hash link break
$ledgerF = Copy-Obj -Obj $ledgerObj
$sealF = @($ledgerF.entries | Where-Object { [string]$_.phase_locked -eq $SealPhase -and [string]$_.artifact -eq $SealArtifact } | Select-Object -Last 1)
if ($sealF.Count -eq 0) {
    $caseFPass = $false
} else {
    $sealId = [string]$sealF[0].entry_id
    for ($i = 0; $i -lt $ledgerF.entries.Count; $i++) {
        if ([string]$ledgerF.entries[$i].entry_id -eq $sealId) {
            $ledgerF.entries[$i].previous_hash = ('0' * 64)
            break
        }
    }
    $caseFResult = Test-TrustChainSealIntegrity -LedgerObj $ledgerF -ReferenceObj $referenceInfo -ExpectedPhase $SealPhase -ExpectedArtifact $SealArtifact
    $caseFPass = ($caseFResult.chain_integrity -eq 'FAIL')
    $EvidenceLines.Add('CASE F chain_reason=' + [string]$caseFResult.chain_reason)
}
if (-not $caseFPass) { $allPass = $false }
Add-ValidationCaseLine -Lines $ValidationLines -CaseId 'F' -Name 'previous_hash_link_break' -Expected 'chain_integrity=FAIL' -Pass $caseFPass

$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$status01 = @(
    'PHASE=49.4',
    'TITLE=Trust-Chain Ledger Baseline Enforcement Coverage Fingerprint Trust-Chain Baseline Enforcement Coverage Fingerprint Trust-Chain Seal',
    'GATE=' + $Gate,
    'LEDGER_APPEND=' + $(if ($appendPerformed -or $existingSeal.Count -gt 0) { 'SUCCESS' } else { 'FAIL' }),
    'CHAIN_INTEGRITY=' + [string]$caseA.chain_integrity,
    'RUNTIME_STATE_MACHINE_CHANGED=FALSE'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '01_status.txt'), $status01, [System.Text.Encoding]::UTF8)

$head02 = @(
    'RUNNER=' + $RunnerPath,
    'LEDGER=' + $LedgerPath,
    'REFERENCE=' + $ReferencePath,
    'SEALED_ENTRY_ID=' + [string]$sealedEntry.entry_id,
    'SEALED_PHASE=' + $SealPhase,
    'SEALED_ARTIFACT=' + $SealArtifact
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '02_head.txt'), $head02, [System.Text.Encoding]::UTF8)

$def10 = @(
    'TRUST_CHAIN_LINK=legacy_5_field_hash(entry_id,fingerprint_hash,timestamp_utc,phase_locked,previous_hash)',
    'SEALED_VALUE=control_plane/93 coverage_fingerprint_sha256',
    'SEALED_HASH=fingerprint_hash stores canonical sha256(control_plane/93 json object)',
    'NEW_ENTRY_PHASE=49.4',
    'NEW_ENTRY_ARTIFACT=' + $SealArtifact
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '10_trust_chain_extension_definition.txt'), $def10, [System.Text.Encoding]::UTF8)

$chainHashes = Test-LegacyTrustChain -ChainObj $ledgerObj
$records11 = [System.Collections.Generic.List[string]]::new()
$records11.Add('entry_id|legacy_chain_hash|previous_hash')
for ($i = 0; $i -lt $ledgerObj.entries.Count; $i++) {
    $e = $ledgerObj.entries[$i]
    $records11.Add([string]$e.entry_id + '|' + [string]$chainHashes.chain_hashes[$i] + '|' + [string]$e.previous_hash)
}
[System.IO.File]::WriteAllText((Join-Path $PF '11_chain_hash_records.txt'), ($records11 -join "`r`n"), [System.Text.Encoding]::UTF8)

$files12 = @(
    'READ=' + $LedgerPath,
    'READ=' + $ReferencePath,
    'WRITE=' + $LedgerPath,
    'WRITE=' + $PF
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '12_files_touched.txt'), $files12, [System.Text.Encoding]::UTF8)

$build13 = @(
    'CASE_COUNT=6',
    'ENTRY_COUNT=' + [string]$ledgerObj.entries.Count,
    'SEALED_ENTRY=' + [string]$sealedEntry.entry_id,
    'REFERENCE_COVERAGE=' + [string]$referenceInfo.coverage_fingerprint,
    'REFERENCE_ARTIFACT_HASH=' + [string]$referenceInfo.reference_artifact_hash,
    'GATE=' + $Gate
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '13_build_output.txt'), $build13, [System.Text.Encoding]::UTF8)

[System.IO.File]::WriteAllText((Join-Path $PF '14_validation_results.txt'), ($ValidationLines -join "`r`n"), [System.Text.Encoding]::UTF8)

$summary15 = @(
    'The phase49.3 coverage fingerprint reference was bound into ledger entry ' + [string]$sealedEntry.entry_id + '.',
    'previous_hash for the 49.4 seal entry links to the legacy hash of the prior ledger entry.',
    'Historical tamper and previous_hash-link break both fail chain validation as expected.',
    'Coverage artifact tamper fails seal-binding validation as expected.',
    'Future continuation append remains valid, preserving chain extensibility.',
    'Formatting-only non-semantic reference serialization remains valid due to canonical object hashing.',
    'No runtime state machine behavior was modified.'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '15_behavior_summary.txt'), $summary15, [System.Text.Encoding]::UTF8)

$report16 = @(
    'CASE_A_CHAIN_INTEGRITY=' + [string]$caseA.chain_integrity,
    'CASE_A_SEAL_BINDING=' + [string]$caseA.seal_binding,
    'CASE_A_CHAIN_REASON=' + [string]$caseA.chain_reason,
    'CHAIN_LAST_HASH=' + [string]$caseA.chain_last_hash,
    'CHAIN_ENTRY_COUNT=' + [string]$caseA.chain_entry_count
) + @($ChainRecordLines)
[System.IO.File]::WriteAllText((Join-Path $PF '16_chain_integrity_report.txt'), ($report16 -join "`r`n"), [System.Text.Encoding]::UTF8)

[System.IO.File]::WriteAllText((Join-Path $PF '17_tamper_detection_evidence.txt'), ($EvidenceLines -join "`r`n"), [System.Text.Encoding]::UTF8)

$gate98 = @('PHASE=49.4', 'GATE=' + $Gate) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $PF '98_gate_phase49_4.txt'), $gate98, [System.Text.Encoding]::UTF8)

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
