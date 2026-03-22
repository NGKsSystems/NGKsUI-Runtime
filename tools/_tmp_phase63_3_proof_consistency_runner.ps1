Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'

function Parse-KeyValueFile {
  param([string]$Path)

  $map = @{}
  $dups = New-Object System.Collections.Generic.List[string]
  $pendingKey = ''
  foreach ($line in (Get-Content -LiteralPath $Path)) {
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
      continue
    }

    $idx = $trimmed.IndexOf('=')
    if ($idx -lt 1) {
      if (-not [string]::IsNullOrWhiteSpace($pendingKey)) {
        $map[$pendingKey] = $trimmed
        $pendingKey = ''
      }
      continue
    }

    $k = $trimmed.Substring(0, $idx).Trim()
    $v = $trimmed.Substring($idx + 1).Trim()
    if ($map.ContainsKey($k)) {
      $dups.Add($k)
    }
    $map[$k] = $v
    $pendingKey = if ([string]::IsNullOrWhiteSpace($v)) { $k } else { '' }
  }

  return [pscustomobject]@{
    Values = $map
    DuplicateKeys = @($dups)
  }
}

function Normalize-ProofFolder {
  param([string]$RawValue)

  if ([string]::IsNullOrWhiteSpace($RawValue)) {
    return ''
  }

  $v = $RawValue.Trim().Replace('\', '/')
  if ($v.StartsWith('./', [System.StringComparison]::Ordinal)) {
    $v = $v.Substring(2)
  }

  if ($v.StartsWith('_proof/', [System.StringComparison]::Ordinal)) {
    return $v
  }

  if ($v.StartsWith('phase63_2_', [System.StringComparison]::Ordinal)) {
    return '_proof/' + $v
  }

  return $v
}

$runStart = Get-Date
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pfRel = '_proof/phase63_3_proof_consistency_audit_' + $ts
$pf = Join-Path '_proof' ('phase63_3_proof_consistency_audit_' + $ts)
New-Item -ItemType Directory -Force -Path $pf | Out-Null

$preflight = Join-Path $pf '00_preflight_snapshot.txt'
$checksPath = Join-Path $pf '90_phase63_3_proof_consistency_checks.txt'
$contractPath = Join-Path $pf '99_phase63_3_contract_summary.txt'

$src = Get-ChildItem -LiteralPath '_proof' -Directory |
  Where-Object { $_.Name -like 'phase63_2_operator_prepostflight_audit_*' } |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if ($null -eq $src) {
  @(
    'next_phase_selected=PHASE63_3_PROOF_CONSISTENCY_AUDIT',
    'objective=Audit proof/reporting consistency only for latest Phase63_2 bundle, without runtime or launcher changes.',
    'changes_introduced=tools/_tmp_phase63_3_proof_consistency_runner.ps1 (proof consistency checks only).',
    'runtime_behavior_changes=NONE',
    'new_regressions_detected=YES',
    'phase_status=FAIL',
    'proof_folder=' + $pfRel
  ) | Set-Content -LiteralPath $contractPath -Encoding UTF8
  Write-Output ('phase63_3_folder=' + $pfRel)
  Write-Output 'phase63_3_status=FAIL'
  exit 1
}

$srcRel = '_proof/' + $src.Name
$srcContract = Join-Path $src.FullName '99_phase63_2_contract_summary.txt'
$srcChecks = Join-Path $src.FullName '90_phase63_2_operator_prepostflight_checks.txt'
$srcPre = Join-Path $src.FullName '00_preflight_snapshot.txt'
$srcPost = Join-Path $src.FullName '92_postflight_snapshot.txt'

@(
  'phase=PHASE63_3_PROOF_CONSISTENCY_AUDIT',
  'run_start_utc=' + $runStart.ToUniversalTime().ToString('o'),
  'source_phase63_2_folder=' + $srcRel,
  'proof_folder=' + $pfRel
) | Set-Content -LiteralPath $preflight -Encoding UTF8

$requiredSourceFiles = @($srcContract, $srcChecks, $srcPre, $srcPost)
$sourceFilesExist = $true
foreach ($f in $requiredSourceFiles) {
  if (-not (Test-Path -LiteralPath $f)) {
    $sourceFilesExist = $false
    break
  }
}

$requiredContractKeys = @(
  'next_phase_selected',
  'objective',
  'changes_introduced',
  'runtime_behavior_changes',
  'new_regressions_detected',
  'phase_status',
  'proof_folder'
)

$contractHasAllKeys = $false
$contractValuesNonEmpty = $false
$contractNoDuplicateKeys = $false
$sourceProofFieldRelative = $false
$checksGeneratedInRun = $false
$checksContainCoreFlags = $false
$sourceProofRawValue = ''
$sourceProofNormalizedValue = ''
$sourceProofExpectedValue = $srcRel

if ($sourceFilesExist) {
  $parsed = Parse-KeyValueFile -Path $srcContract
  $kv = $parsed.Values
  $dups = @($parsed.DuplicateKeys)

  $hasAll = $true
  $allNonEmpty = $true
  foreach ($k in $requiredContractKeys) {
    if (-not $kv.ContainsKey($k)) {
      $hasAll = $false
      $allNonEmpty = $false
      continue
    }
    if ([string]::IsNullOrWhiteSpace([string]$kv[$k])) {
      $allNonEmpty = $false
    }
  }

  $contractHasAllKeys = $hasAll
  $contractValuesNonEmpty = $allNonEmpty
  $contractNoDuplicateKeys = ($dups.Count -eq 0)
  if ($kv.ContainsKey('proof_folder')) {
    $sourceProofRawValue = [string]$kv['proof_folder']
    $sourceProofNormalizedValue = Normalize-ProofFolder -RawValue $sourceProofRawValue
    $sourceProofFieldRelative = ($sourceProofNormalizedValue -eq $sourceProofExpectedValue)
  }

  $checksText = Get-Content -LiteralPath $srcChecks -Raw
  $checksContainCoreFlags =
    ($checksText -match 'check_widget_clean_summary=YES') -and
    ($checksText -match 'check_widget_blocked_error=YES') -and
    ($checksText -match 'check_widget_blocked_summary=YES') -and
    ($checksText -match 'check_preflight_exists=YES') -and
    ($checksText -match 'check_postflight_exists=YES') -and
    ($checksText -match 'check_hashes_stable=YES')
}

@(
  'proof_folder=' + $pfRel,
  'source_phase63_2_folder=' + $srcRel,
  'check_source_files_exist=' + $(if ($sourceFilesExist) { 'YES' } else { 'NO' }),
  'check_contract_has_all_keys=' + $(if ($contractHasAllKeys) { 'YES' } else { 'NO' }),
  'check_contract_values_non_empty=' + $(if ($contractValuesNonEmpty) { 'YES' } else { 'NO' }),
  'check_contract_no_duplicate_keys=' + $(if ($contractNoDuplicateKeys) { 'YES' } else { 'NO' }),
  'check_source_proof_field_repo_relative=' + $(if ($sourceProofFieldRelative) { 'YES' } else { 'NO' }),
  'source_proof_folder_raw=' + $sourceProofRawValue,
  'source_proof_folder_normalized=' + $sourceProofNormalizedValue,
  'source_proof_folder_expected=' + $sourceProofExpectedValue,
  'check_phase63_2_core_flags_yes=' + $(if ($checksContainCoreFlags) { 'YES' } else { 'NO' }),
  'check_checks_generated_in_run=PENDING'
) | Set-Content -LiteralPath $checksPath -Encoding UTF8

$checksGeneratedInRun = (Get-Item -LiteralPath $checksPath).LastWriteTime -ge $runStart
(Get-Content -LiteralPath $checksPath) -replace 'check_checks_generated_in_run=PENDING', ('check_checks_generated_in_run=' + $(if ($checksGeneratedInRun) { 'YES' } else { 'NO' })) | Set-Content -LiteralPath $checksPath -Encoding UTF8

$allOk = $sourceFilesExist -and $contractHasAllKeys -and $contractValuesNonEmpty -and $contractNoDuplicateKeys -and $sourceProofFieldRelative -and $checksContainCoreFlags -and $checksGeneratedInRun

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) {
  Remove-Item -LiteralPath $zip -Force
}
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

@(
  'next_phase_selected=PHASE63_3_PROOF_CONSISTENCY_AUDIT',
  'objective=Audit proof/reporting consistency only for latest Phase63_2 bundle, without runtime or launcher changes.',
  'changes_introduced=tools/_tmp_phase63_3_proof_consistency_runner.ps1 (proof consistency checks only).',
  'runtime_behavior_changes=NONE',
  'new_regressions_detected=' + $(if ($allOk) { 'NO' } else { 'YES' }),
  'phase_status=' + $(if ($allOk) { 'PASS' } else { 'FAIL' }),
  'proof_folder=' + $pfRel
) | Set-Content -LiteralPath $contractPath -Encoding UTF8

Write-Output ('phase63_3_folder=' + $pfRel)
Write-Output ('phase63_3_status=' + $(if ($allOk) { 'PASS' } else { 'FAIL' }))
Write-Output ('phase63_3_zip=' + $pfRel + '.zip')
