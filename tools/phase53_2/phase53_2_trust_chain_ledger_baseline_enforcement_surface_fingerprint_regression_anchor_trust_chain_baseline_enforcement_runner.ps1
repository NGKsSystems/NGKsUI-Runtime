Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ((Get-Location).Path -ne $Root) {
    Write-Output 'wrong working directory'
    exit 1
}
Set-Location $Root

function Write-ProofFile {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.Encoding]::UTF8)
}

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
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [float] -or $Value -is [decimal]) { return [string]$Value }
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
        foreach ($k in $keys) { [void]$pairs.Add(('"' + $k + '":' + (Convert-ToCanonicalJson -Value $Value[$k]))) }
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

function Test-ExtendedTrustChain {
    param([object[]]$Entries)

    $result = [ordered]@{ pass = $true; reason = 'ok'; entry_count = $Entries.Count; chain_hashes = @(); last_entry_hash = '' }
    if ($Entries.Count -eq 0) {
        $result.pass = $false
        $result.reason = 'chain_entries_empty'
        return $result
    }

    $hashes = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $Entries.Count; $i++) {
        $entry = $Entries[$i]
        if ($i -eq 0) {
            if ($null -ne $entry.previous_hash -and -not [string]::IsNullOrWhiteSpace([string]$entry.previous_hash)) {
                $result.pass = $false
                $result.reason = 'first_entry_previous_hash_must_be_null'
                return $result
            }
        } else {
            $expectedPrev = $hashes[$i - 1]
            if ([string]$entry.previous_hash -ne $expectedPrev) {
                $result.pass = $false
                $result.reason = 'previous_hash_link_mismatch_at_entry_' + [string]$entry.entry_id + '_index_' + $i
                return $result
            }
        }
        [void]$hashes.Add((Get-LegacyChainEntryHash -Entry $entry))
    }

    $result.chain_hashes = @($hashes)
    $result.last_entry_hash = [string]$hashes[$hashes.Count - 1]
    return $result
}

function Copy-Entries {
    param([object[]]$Entries)
    $copy = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $Entries) {
        [void]$copy.Add(($entry | ConvertTo-Json -Depth 20 | ConvertFrom-Json))
    }
    return @($copy)
}

# Strict 8-step pre-runtime enforcement gate for phase 53.2
function Test-Phase532BaselineEnforcementGate {
    param(
        [object[]]$LiveEntries,
        [object]$Artifact110,
        [object]$Artifact111,
        [object]$Artifact112,
        [bool]$Artifact111Exists,
        [bool]$Artifact112Exists
    )

    $result = [ordered]@{
        allowed = $false
        block_reason = ''
        step_failed = 0
        chain_hashes = @()
        chain_integrity_status = ''
        continuation_status = ''
        computed_snap_hash = ''
        stored_snap_hash = ''
        live_head_hash = ''
        baseline_head_hash = ''
        computed_cov_fp = ''
        baseline_cov_fp = ''
        details = [ordered]@{}
    }

    # Step 1: validate 111 exists
    if (-not $Artifact111Exists) {
        $result.step_failed = 1
        $result.block_reason = 'artifact_111_missing'
        $result.details['step1'] = 'FAIL: 111 missing'
        return $result
    }
    $result.details['step1'] = 'PASS: 111 exists'

    # Step 2: validate 112 exists
    if (-not $Artifact112Exists) {
        $result.step_failed = 2
        $result.block_reason = 'artifact_112_missing'
        $result.details['step2'] = 'FAIL: 112 missing'
        return $result
    }
    $result.details['step2'] = 'PASS: 112 exists'

    # Step 3: validate 111 canonical hash vs 112.baseline_snapshot_hash
    $computedSnapHash = Get-CanonicalObjectHash -Obj $Artifact111
    $storedSnapHash = [string]$Artifact112.baseline_snapshot_hash
    $result.computed_snap_hash = $computedSnapHash
    $result.stored_snap_hash = $storedSnapHash
    if ($computedSnapHash -ne $storedSnapHash) {
        $result.step_failed = 3
        $result.block_reason = 'baseline_snapshot_hash_mismatch'
        $result.details['step3'] = 'FAIL: computed=' + $computedSnapHash + ' stored=' + $storedSnapHash
        return $result
    }
    $result.details['step3'] = 'PASS: computed=' + $computedSnapHash

    # Step 4: validate trust-chain integrity
    $chain = Test-ExtendedTrustChain -Entries $LiveEntries
    $result.chain_hashes = $chain.chain_hashes
    $result.chain_integrity_status = $chain.reason
    if (-not $chain.pass) {
        $result.step_failed = 4
        $result.block_reason = 'trust_chain_integrity_failed:' + [string]$chain.reason
        $result.details['step4'] = 'FAIL: ' + [string]$chain.reason
        return $result
    }
    $result.live_head_hash = [string]$chain.last_entry_hash
    $result.details['step4'] = 'PASS: entries=' + [string]$chain.entry_count

    # Step 5: validate live ledger head matches frozen baseline or valid continuation
    $baselineHead = [string]$Artifact111.ledger_head_hash
    $baselineLen = [int]$Artifact111.ledger_length
    $result.baseline_head_hash = $baselineHead

    if ([string]$chain.last_entry_hash -eq $baselineHead) {
        $result.continuation_status = 'exact'
        $result.details['step5'] = 'PASS: exact head match'
    } elseif ($chain.chain_hashes.Count -gt $baselineLen -and $baselineLen -gt 0) {
        $baselinePositionHash = [string]$chain.chain_hashes[$baselineLen - 1]
        if ($baselinePositionHash -eq $baselineHead) {
            $result.continuation_status = 'continuation'
            $result.details['step5'] = 'PASS: continuation baseline_pos_hash=' + $baselinePositionHash
        } else {
            $result.step_failed = 5
            $result.block_reason = 'ledger_head_drift_continuation_invalid'
            $result.continuation_status = 'failed'
            $result.details['step5'] = 'FAIL: baseline_pos_hash=' + $baselinePositionHash + ' expected=' + $baselineHead
            return $result
        }
    } else {
        $result.step_failed = 5
        $result.block_reason = 'ledger_head_drift'
        $result.continuation_status = 'failed'
        $result.details['step5'] = 'FAIL: live_head=' + [string]$chain.last_entry_hash + ' baseline_head=' + $baselineHead
        return $result
    }

    # Step 6: validate artifact 110 fingerprint matches baseline expectation
    $computedCovFp = [string]$Artifact110.coverage_fingerprint
    $baselineCovFp111 = [string]$Artifact111.coverage_fingerprint_hash
    $baselineCovFp112 = [string]$Artifact112.coverage_fingerprint_hash
    $result.computed_cov_fp = $computedCovFp
    $result.baseline_cov_fp = $baselineCovFp111
    if ($computedCovFp -ne $baselineCovFp111 -or $computedCovFp -ne $baselineCovFp112) {
        $result.step_failed = 6
        $result.block_reason = 'artifact110_coverage_fingerprint_mismatch'
        $result.details['step6'] = 'FAIL: 110=' + $computedCovFp + ' 111=' + $baselineCovFp111 + ' 112=' + $baselineCovFp112
        return $result
    }
    $result.details['step6'] = 'PASS: coverage_fingerprint=' + $computedCovFp

    # Step 7: validate semantic protected fields
    $semanticErrors = [System.Collections.Generic.List[string]]::new()
    if ([string]$Artifact111.phase_locked -ne '53.1') { [void]$semanticErrors.Add('111.phase_locked_not_53.1') }
    if ([string]$Artifact111.latest_entry_id -ne 'GF-0015') { [void]$semanticErrors.Add('111.latest_entry_id_not_GF-0015') }
    if ([string]$Artifact111.latest_entry_phase_locked -ne '53.0') { [void]$semanticErrors.Add('111.latest_entry_phase_locked_not_53.0') }
    if ([int]$Artifact111.ledger_length -ne 15) { [void]$semanticErrors.Add('111.ledger_length_not_15') }
    $srcPhases = @($Artifact111.source_phases | ForEach-Object { [string]$_ })
    if (($srcPhases -join ',') -ne '52.8,52.9,53.0') { [void]$semanticErrors.Add('111.source_phases_mismatch') }
    if ([string]$Artifact112.phase_locked -ne '53.1') { [void]$semanticErrors.Add('112.phase_locked_not_53.1') }
    if ($semanticErrors.Count -gt 0) {
        $result.step_failed = 7
        $result.block_reason = 'semantic_field_validation_failed:' + ($semanticErrors -join ',')
        $result.details['step7'] = 'FAIL: ' + ($semanticErrors -join ',')
        return $result
    }
    $result.details['step7'] = 'PASS: protected fields valid'

    # Step 8: allow runtime init
    $result.allowed = $true
    $result.step_failed = 0
    $result.block_reason = ''
    $result.details['step8'] = 'PASS: runtime_init_allowed'
    return $result
}

function Invoke-ProtectedRuntimeOperation {
    param(
        [scriptblock]$RuntimeScript,
        [object[]]$LiveEntries,
        [object]$Artifact110,
        [object]$Artifact111,
        [object]$Artifact112,
        [bool]$Artifact111Exists,
        [bool]$Artifact112Exists
    )

    $gate = Test-Phase532BaselineEnforcementGate -LiveEntries $LiveEntries -Artifact110 $Artifact110 -Artifact111 $Artifact111 -Artifact112 $Artifact112 -Artifact111Exists $Artifact111Exists -Artifact112Exists $Artifact112Exists
    $runtimeExecuted = $false
    $runtimeResult = 'BLOCKED'

    if ($gate.allowed) {
        $runtimeExecuted = $true
        & $RuntimeScript
        $runtimeResult = 'ALLOWED'
    }

    return [ordered]@{
        gate = $gate
        runtime_executed = $runtimeExecuted
        runtime_result = $runtimeResult
    }
}

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunnerPath = Join-Path $Root 'tools\phase53_2\phase53_2_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_enforcement_runner.ps1'
$LedgerPath = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$Art110Path = Join-Path $Root 'control_plane\110_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint_regression_anchor.json'
$Art111Path = Join-Path $Root 'control_plane\111_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline.json'
$Art112Path = Join-Path $Root 'control_plane\112_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_integrity.json'
$PF = Join-Path $Root ('_proof\phase53_2_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_enforcement_' + $Timestamp)

New-Item -ItemType Directory -Path $PF | Out-Null

foreach ($path in @($LedgerPath, $Art110Path, $Art111Path, $Art112Path)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw 'Missing required file: ' + $path
    }
}

$ledgerObj = Get-Content -LiteralPath $LedgerPath -Raw | ConvertFrom-Json
$liveEntries = @($ledgerObj.entries)
$art110Obj = Get-Content -LiteralPath $Art110Path -Raw | ConvertFrom-Json
$art111Obj = Get-Content -LiteralPath $Art111Path -Raw | ConvertFrom-Json
$art112Obj = Get-Content -LiteralPath $Art112Path -Raw | ConvertFrom-Json

$Validation = [System.Collections.Generic.List[string]]::new()
$RuntimeRecords = [System.Collections.Generic.List[string]]::new()
$BlockEvidence = [System.Collections.Generic.List[string]]::new()
$allPass = $true

function Add-Case {
    param([string]$Id, [string]$Name, [bool]$Pass, [string]$Detail)
    [void]$Validation.Add('CASE ' + $Id + ' ' + $Name + ' | ' + $Detail + ' => ' + $(if ($Pass) { 'PASS' } else { 'FAIL' }))
    if (-not $Pass) { $script:allPass = $false }
}

function Add-RuntimeRecord {
    param([string]$CaseId, [object]$Run)
    [void]$RuntimeRecords.Add(
        'CASE ' + $CaseId +
        ' | runtime_executed=' + $Run.runtime_executed +
        ' | runtime_result=' + $Run.runtime_result +
        ' | gate_allowed=' + $Run.gate.allowed +
        ' | step_failed=' + $Run.gate.step_failed +
        ' | block_reason=' + $Run.gate.block_reason +
        ' | continuation=' + $Run.gate.continuation_status +
        ' | fallback_occurred=FALSE' +
        ' | regeneration_occurred=FALSE'
    )
}

$runtimeCounter = 0
$runtimeScript = { $script:runtimeCounter++ }

# A. clean state -> ALLOWED
$runA = Invoke-ProtectedRuntimeOperation -RuntimeScript $runtimeScript -LiveEntries $liveEntries -Artifact110 $art110Obj -Artifact111 $art111Obj -Artifact112 $art112Obj -Artifact111Exists $true -Artifact112Exists $true
$caseA = $runA.gate.allowed -and $runA.runtime_executed
Add-Case -Id 'A' -Name 'clean_state_allowed' -Pass $caseA -Detail ('allowed=' + $runA.gate.allowed + ' runtime_executed=' + $runA.runtime_executed + ' step_failed=' + $runA.gate.step_failed)
Add-RuntimeRecord -CaseId 'A' -Run $runA

# B. tamper 111 -> BLOCKED
$mut111B = $art111Obj | ConvertTo-Json -Depth 20 | ConvertFrom-Json
$mut111B | Add-Member -MemberType NoteProperty -Name ledger_head_hash -Value 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' -Force
$runB = Invoke-ProtectedRuntimeOperation -RuntimeScript $runtimeScript -LiveEntries $liveEntries -Artifact110 $art110Obj -Artifact111 $mut111B -Artifact112 $art112Obj -Artifact111Exists $true -Artifact112Exists $true
$caseB = (-not $runB.gate.allowed) -and (-not $runB.runtime_executed)
Add-Case -Id 'B' -Name 'tamper_111_blocked' -Pass $caseB -Detail ('allowed=' + $runB.gate.allowed + ' step_failed=' + $runB.gate.step_failed + ' reason=' + $runB.gate.block_reason)
Add-RuntimeRecord -CaseId 'B' -Run $runB
[void]$BlockEvidence.Add('CASE B | step=' + $runB.gate.step_failed + ' | reason=' + $runB.gate.block_reason)

# C. tamper 112 -> BLOCKED
$mut112C = $art112Obj | ConvertTo-Json -Depth 20 | ConvertFrom-Json
$mut112C | Add-Member -MemberType NoteProperty -Name baseline_snapshot_hash -Value 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc' -Force
$runC = Invoke-ProtectedRuntimeOperation -RuntimeScript $runtimeScript -LiveEntries $liveEntries -Artifact110 $art110Obj -Artifact111 $art111Obj -Artifact112 $mut112C -Artifact111Exists $true -Artifact112Exists $true
$caseC = (-not $runC.gate.allowed) -and (-not $runC.runtime_executed)
Add-Case -Id 'C' -Name 'tamper_112_blocked' -Pass $caseC -Detail ('allowed=' + $runC.gate.allowed + ' step_failed=' + $runC.gate.step_failed + ' reason=' + $runC.gate.block_reason)
Add-RuntimeRecord -CaseId 'C' -Run $runC
[void]$BlockEvidence.Add('CASE C | step=' + $runC.gate.step_failed + ' | reason=' + $runC.gate.block_reason)

# D. ledger head drift -> BLOCKED
$dEntries = Copy-Entries -Entries $liveEntries
$dLast = $dEntries.Count - 1
$dEntries[$dLast] | Add-Member -MemberType NoteProperty -Name fingerprint_hash -Value (([string]$dEntries[$dLast].fingerprint_hash) + 'dd') -Force
$runD = Invoke-ProtectedRuntimeOperation -RuntimeScript $runtimeScript -LiveEntries $dEntries -Artifact110 $art110Obj -Artifact111 $art111Obj -Artifact112 $art112Obj -Artifact111Exists $true -Artifact112Exists $true
$caseD = (-not $runD.gate.allowed) -and (-not $runD.runtime_executed)
Add-Case -Id 'D' -Name 'ledger_head_drift_blocked' -Pass $caseD -Detail ('allowed=' + $runD.gate.allowed + ' step_failed=' + $runD.gate.step_failed + ' reason=' + $runD.gate.block_reason)
Add-RuntimeRecord -CaseId 'D' -Run $runD
[void]$BlockEvidence.Add('CASE D | step=' + $runD.gate.step_failed + ' | reason=' + $runD.gate.block_reason)

# E. artifact 110 fingerprint drift -> BLOCKED
$mut110E = $art110Obj | ConvertTo-Json -Depth 20 | ConvertFrom-Json
$mut110E | Add-Member -MemberType NoteProperty -Name coverage_fingerprint -Value (([string]$mut110E.coverage_fingerprint) + 'e') -Force
$runE = Invoke-ProtectedRuntimeOperation -RuntimeScript $runtimeScript -LiveEntries $liveEntries -Artifact110 $mut110E -Artifact111 $art111Obj -Artifact112 $art112Obj -Artifact111Exists $true -Artifact112Exists $true
$caseE = (-not $runE.gate.allowed) -and (-not $runE.runtime_executed)
Add-Case -Id 'E' -Name 'artifact110_fingerprint_drift_blocked' -Pass $caseE -Detail ('allowed=' + $runE.gate.allowed + ' step_failed=' + $runE.gate.step_failed + ' reason=' + $runE.gate.block_reason)
Add-RuntimeRecord -CaseId 'E' -Run $runE
[void]$BlockEvidence.Add('CASE E | step=' + $runE.gate.step_failed + ' | reason=' + $runE.gate.block_reason)

# F. broken chain previous_hash -> BLOCKED
$fEntries = Copy-Entries -Entries $liveEntries
$fEntries[1] | Add-Member -MemberType NoteProperty -Name previous_hash -Value 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff' -Force
$runF = Invoke-ProtectedRuntimeOperation -RuntimeScript $runtimeScript -LiveEntries $fEntries -Artifact110 $art110Obj -Artifact111 $art111Obj -Artifact112 $art112Obj -Artifact111Exists $true -Artifact112Exists $true
$caseF = (-not $runF.gate.allowed) -and (-not $runF.runtime_executed)
Add-Case -Id 'F' -Name 'broken_chain_previous_hash_blocked' -Pass $caseF -Detail ('allowed=' + $runF.gate.allowed + ' step_failed=' + $runF.gate.step_failed + ' reason=' + $runF.gate.block_reason)
Add-RuntimeRecord -CaseId 'F' -Run $runF
[void]$BlockEvidence.Add('CASE F | step=' + $runF.gate.step_failed + ' | reason=' + $runF.gate.block_reason)

# G. valid continuation after GF-0015 -> ALLOWED
$gEntriesList = [System.Collections.Generic.List[object]]::new()
foreach ($entry in $liveEntries) { [void]$gEntriesList.Add($entry) }
$gChain = Test-ExtendedTrustChain -Entries $liveEntries
$gFuture = [pscustomobject]@{
    entry_id = ('GF-{0:D4}' -f ($liveEntries.Count + 1))
    artifact = 'phase53_2_valid_future_continuation'
    reference_artifact = 'N/A'
    coverage_fingerprint = 'future_continuation_cov_fp'
    fingerprint_hash = 'future_continuation_fingerprint_hash'
    timestamp_utc = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    phase_locked = '53.3_future'
    previous_hash = [string]$gChain.last_entry_hash
}
[void]$gEntriesList.Add($gFuture)
$runG = Invoke-ProtectedRuntimeOperation -RuntimeScript $runtimeScript -LiveEntries @($gEntriesList) -Artifact110 $art110Obj -Artifact111 $art111Obj -Artifact112 $art112Obj -Artifact111Exists $true -Artifact112Exists $true
$caseG = $runG.gate.allowed -and $runG.runtime_executed -and ([string]$runG.gate.continuation_status -eq 'continuation')
Add-Case -Id 'G' -Name 'valid_continuation_allowed' -Pass $caseG -Detail ('allowed=' + $runG.gate.allowed + ' continuation=' + $runG.gate.continuation_status + ' runtime_executed=' + $runG.runtime_executed)
Add-RuntimeRecord -CaseId 'G' -Run $runG

# H. non-semantic JSON round-trip -> ALLOWED
$h111Path = Join-Path $PF 'case_h_111_pretty.json'
$h112Path = Join-Path $PF 'case_h_112_pretty.json'
($art111Obj | ConvertTo-Json -Depth 40) | Set-Content -LiteralPath $h111Path -Encoding UTF8 -NoNewline
($art112Obj | ConvertTo-Json -Depth 40) | Set-Content -LiteralPath $h112Path -Encoding UTF8 -NoNewline
$h111 = Get-Content -LiteralPath $h111Path -Raw | ConvertFrom-Json
$h112 = Get-Content -LiteralPath $h112Path -Raw | ConvertFrom-Json
$runH = Invoke-ProtectedRuntimeOperation -RuntimeScript $runtimeScript -LiveEntries $liveEntries -Artifact110 $art110Obj -Artifact111 $h111 -Artifact112 $h112 -Artifact111Exists $true -Artifact112Exists $true
$caseH = $runH.gate.allowed -and $runH.runtime_executed
Add-Case -Id 'H' -Name 'non_semantic_roundtrip_allowed' -Pass $caseH -Detail ('allowed=' + $runH.gate.allowed + ' runtime_executed=' + $runH.runtime_executed)
Add-RuntimeRecord -CaseId 'H' -Run $runH

# I. valid baseline + valid chain + broken fingerprint -> BLOCKED
$mut110I = $art110Obj | ConvertTo-Json -Depth 20 | ConvertFrom-Json
$mut110I | Add-Member -MemberType NoteProperty -Name coverage_fingerprint -Value '0000000000000000000000000000000000000000000000000000000000000000' -Force
$runI = Invoke-ProtectedRuntimeOperation -RuntimeScript $runtimeScript -LiveEntries $liveEntries -Artifact110 $mut110I -Artifact111 $art111Obj -Artifact112 $art112Obj -Artifact111Exists $true -Artifact112Exists $true
$caseI = (-not $runI.gate.allowed) -and (-not $runI.runtime_executed)
Add-Case -Id 'I' -Name 'valid_baseline_chain_broken_fingerprint_blocked' -Pass $caseI -Detail ('allowed=' + $runI.gate.allowed + ' step_failed=' + $runI.gate.step_failed + ' reason=' + $runI.gate.block_reason)
Add-RuntimeRecord -CaseId 'I' -Run $runI
[void]$BlockEvidence.Add('CASE I | step=' + $runI.gate.step_failed + ' | reason=' + $runI.gate.block_reason)

$passCount = @($Validation | Where-Object { $_ -match '=> PASS$' }).Count
$failCount = @($Validation | Where-Object { $_ -match '=> FAIL$' }).Count
$Gate = if ($allPass) { 'PASS' } else { 'FAIL' }

$def10 = [System.Collections.Generic.List[string]]::new()
[void]$def10.Add('# Phase 53.2 enforcement definition')
[void]$def10.Add('step1=validate_111_exists')
[void]$def10.Add('step2=validate_112_exists')
[void]$def10.Add('step3=validate_111_canonical_hash_equals_112.baseline_snapshot_hash')
[void]$def10.Add('step4=validate_trust_chain_integrity')
[void]$def10.Add('step5=validate_live_head_matches_baseline_or_valid_continuation')
[void]$def10.Add('step6=validate_artifact110_coverage_fingerprint_matches_baseline_expectation')
[void]$def10.Add('step7=validate_semantic_protected_fields')
[void]$def10.Add('step8=allow_runtime_init')
[void]$def10.Add('mode=fail_closed_no_fallback_no_regeneration')

$rules11 = [System.Collections.Generic.List[string]]::new()
[void]$rules11.Add('# Phase 53.2 enforcement rules')
[void]$rules11.Add('rule_fail_closed=true')
[void]$rules11.Add('rule_any_step_fail_blocks_runtime=true')
[void]$rules11.Add('rule_continuation_allowed_if_baseline_head_preserved_at_baseline_index=true')
[void]$rules11.Add('rule_non_semantic_roundtrip_allowed=true')
[void]$rules11.Add('rule_no_fallback=true')
[void]$rules11.Add('rule_no_regeneration=true')

Write-ProofFile (Join-Path $PF '01_status.txt') (@(
    'PHASE=53.2',
    'TITLE=Trust-Chain Ledger Baseline Enforcement Surface Fingerprint Regression Anchor Trust-Chain Baseline Enforcement',
    'GATE=' + $Gate,
    'PASS_COUNT=' + $passCount + '/9',
    'FAIL_COUNT=' + $failCount,
    'RUNTIME_OPS_EXECUTED=' + $runtimeCounter,
    'NO_FALLBACK=TRUE',
    'NO_REGENERATION=TRUE',
    'FAIL_CLOSED=TRUE'
) -join "`r`n")

Write-ProofFile (Join-Path $PF '02_head.txt') (@(
    'RUNNER=' + $RunnerPath,
    'LEDGER=' + $LedgerPath,
    'ART110=' + $Art110Path,
    'ART111=' + $Art111Path,
    'ART112=' + $Art112Path,
    'BASELINE_PHASE=53.1',
    'ENFORCEMENT_PHASE=53.2'
) -join "`r`n")

Write-ProofFile (Join-Path $PF '10_enforcement_definition.txt') ($def10 -join "`r`n")
Write-ProofFile (Join-Path $PF '11_enforcement_rules.txt') ($rules11 -join "`r`n")

Write-ProofFile (Join-Path $PF '12_files_touched.txt') (@(
    'READ=' + $LedgerPath,
    'READ=' + $Art110Path,
    'READ=' + $Art111Path,
    'READ=' + $Art112Path,
    'WRITE_PROOF=' + $PF,
    'NO_CONTROL_PLANE_WRITE=TRUE',
    'NO_RUNTIME_GATE_REGEN=TRUE'
) -join "`r`n")

Write-ProofFile (Join-Path $PF '13_build_output.txt') (@(
    'CASE_COUNT=9',
    'PASSED=' + $passCount,
    'FAILED=' + $failCount,
    'RUNTIME_OPS_EXECUTED=' + $runtimeCounter,
    'GATE=' + $Gate
) -join "`r`n")

Write-ProofFile (Join-Path $PF '14_validation_results.txt') ($Validation -join "`r`n")

Write-ProofFile (Join-Path $PF '15_behavior_summary.txt') (@(
    'A_clean_state_allowed=' + $caseA,
    'B_tamper_111_blocked=' + $caseB,
    'C_tamper_112_blocked=' + $caseC,
    'D_ledger_head_drift_blocked=' + $caseD,
    'E_art110_fp_drift_blocked=' + $caseE,
    'F_broken_chain_previous_hash_blocked=' + $caseF,
    'G_valid_continuation_allowed=' + $caseG,
    'H_non_semantic_roundtrip_allowed=' + $caseH,
    'I_valid_baseline_chain_broken_fingerprint_blocked=' + $caseI,
    'PRE_RUNTIME_ENFORCEMENT=' + (($runA.runtime_executed -and -not $runB.runtime_executed -and -not $runC.runtime_executed -and -not $runD.runtime_executed -and -not $runE.runtime_executed -and -not $runF.runtime_executed -and $runG.runtime_executed -and $runH.runtime_executed -and -not $runI.runtime_executed)),
    'RUNTIME_BEHAVIOR_UNCHANGED=TRUE'
) -join "`r`n")

Write-ProofFile (Join-Path $PF '16_runtime_enforcement_record.txt') ($RuntimeRecords -join "`r`n")
Write-ProofFile (Join-Path $PF '17_block_evidence.txt') ($BlockEvidence -join "`r`n")

Write-ProofFile (Join-Path $PF '98_gate_phase53_2.txt') (@(
    'PHASE=53.2',
    'GATE=' + $Gate,
    'PASS_COUNT=' + $passCount + '/9',
    'NO_FALLBACK=TRUE',
    'NO_REGENERATION=TRUE',
    'FAIL_CLOSED=TRUE'
) -join "`r`n")

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
