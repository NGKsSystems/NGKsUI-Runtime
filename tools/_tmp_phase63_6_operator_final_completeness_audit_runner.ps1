Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'

function Parse-KeyValueFile {
  param([string]$Path)

  $map = @{}
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
    $map[$k] = $v
    $pendingKey = if ([string]::IsNullOrWhiteSpace($v)) { $k } else { '' }
  }

  return $map
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
  if ($v.StartsWith('phase63_', [System.StringComparison]::Ordinal)) {
    return '_proof/' + $v
  }
  return $v
}

function Get-LatestProofFolder {
  param([string]$Pattern)

  return Get-ChildItem -LiteralPath '_proof' -Directory |
    Where-Object { $_.Name -like $Pattern } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pfRel = '_proof/phase63_6_operator_final_completeness_audit_' + $ts
$pf = Join-Path '_proof' ('phase63_6_operator_final_completeness_audit_' + $ts)
New-Item -ItemType Directory -Force -Path $pf | Out-Null

$checksPath = Join-Path $pf '90_phase63_6_operator_final_completeness_checks.txt'
$contractPath = Join-Path $pf '99_phase63_6_contract_summary.txt'

$phaseSpecs = @(
  @{ Name = 'phase63_1'; Pattern = 'phase63_1_operator_summary_integrity_isolated_*'; Contract = '99_phase63_1_contract_summary.txt'; Checks = '90_phase63_1_operator_summary_checks.txt' },
  @{ Name = 'phase63_2'; Pattern = 'phase63_2_operator_prepostflight_audit_*'; Contract = '99_phase63_2_contract_summary.txt'; Checks = '90_phase63_2_operator_prepostflight_checks.txt' },
  @{ Name = 'phase63_3'; Pattern = 'phase63_3_proof_consistency_audit_*'; Contract = '99_phase63_3_contract_summary.txt'; Checks = '90_phase63_3_proof_consistency_checks.txt' },
  @{ Name = 'phase63_4'; Pattern = 'phase63_4_operator_cert_pack_consistency_*'; Contract = '99_phase63_4_contract_summary.txt'; Checks = '90_phase63_4_operator_cert_pack_checks.txt' },
  @{ Name = 'phase63_5'; Pattern = 'phase63_5_operator_closure_chain_audit_*'; Contract = '99_phase63_5_contract_summary.txt'; Checks = '90_phase63_5_operator_closure_chain_checks.txt' }
)

$rows = New-Object System.Collections.Generic.List[string]
$failed = New-Object System.Collections.Generic.List[string]

foreach ($spec in $phaseSpecs) {
  $folder = Get-LatestProofFolder -Pattern $spec.Pattern
  $folderExists = ($null -ne $folder)

  $contractExists = $false
  $checksExists = $false
  $zipExists = $false
  $phaseStatusPass = $false
  $regNo = $false
  $proofMatch = $false

  $rawProof = ''
  $normalizedProof = ''
  $expectedProof = ''

  if ($folderExists) {
    $expectedProof = '_proof/' + $folder.Name
    $contractSrc = Join-Path $folder.FullName $spec.Contract
    $checksSrc = Join-Path $folder.FullName $spec.Checks
    $zipSrc = $folder.FullName + '.zip'

    $contractExists = Test-Path -LiteralPath $contractSrc
    $checksExists = Test-Path -LiteralPath $checksSrc
    $zipExists = Test-Path -LiteralPath $zipSrc

    if ($contractExists) {
      $kv = Parse-KeyValueFile -Path $contractSrc
      $phaseStatusPass = ($kv['phase_status'] -eq 'PASS')
      $regNo = ($kv['new_regressions_detected'] -eq 'NO')
      $rawProof = [string]$kv['proof_folder']
      $normalizedProof = Normalize-ProofFolder -RawValue $rawProof
      $proofMatch = ($normalizedProof -eq $expectedProof)
    }
  }

  $rows.Add(($spec.Name + '_check_folder_exists=' + $(if ($folderExists) { 'YES' } else { 'NO' })))
  $rows.Add(($spec.Name + '_check_contract_exists=' + $(if ($contractExists) { 'YES' } else { 'NO' })))
  $rows.Add(($spec.Name + '_check_checks_exists=' + $(if ($checksExists) { 'YES' } else { 'NO' })))
  $rows.Add(($spec.Name + '_check_zip_exists=' + $(if ($zipExists) { 'YES' } else { 'NO' })))
  $rows.Add(($spec.Name + '_check_phase_status_pass=' + $(if ($phaseStatusPass) { 'YES' } else { 'NO' })))
  $rows.Add(($spec.Name + '_check_new_regressions_no=' + $(if ($regNo) { 'YES' } else { 'NO' })))
  $rows.Add(($spec.Name + '_check_proof_folder_match=' + $(if ($proofMatch) { 'YES' } else { 'NO' })))
  $rows.Add(($spec.Name + '_proof_folder_raw=' + $rawProof))
  $rows.Add(($spec.Name + '_proof_folder_normalized=' + $normalizedProof))
  $rows.Add(($spec.Name + '_proof_folder_expected=' + $expectedProof))

  if (-not $folderExists) { $failed.Add($spec.Name + '_check_folder_exists=NO') }
  if (-not $contractExists) { $failed.Add($spec.Name + '_check_contract_exists=NO') }
  if (-not $checksExists) { $failed.Add($spec.Name + '_check_checks_exists=NO') }
  if (-not $zipExists) { $failed.Add($spec.Name + '_check_zip_exists=NO') }
  if (-not $phaseStatusPass) { $failed.Add($spec.Name + '_check_phase_status_pass=NO') }
  if (-not $regNo) { $failed.Add($spec.Name + '_check_new_regressions_no=NO') }
  if (-not $proofMatch) { $failed.Add($spec.Name + '_check_proof_folder_match=NO') }
}

$allOk = ($failed.Count -eq 0)
$rows.Add('failed_check_count=' + $failed.Count)
$rows.Add('failed_checks=' + $(if ($failed.Count -gt 0) { ($failed -join ';') } else { 'NONE' }))
$rows | Set-Content -LiteralPath $checksPath -Encoding UTF8

$zipOut = $pf + '.zip'
if (Test-Path -LiteralPath $zipOut) {
  Remove-Item -LiteralPath $zipOut -Force
}
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zipOut -Force

@(
  'next_phase_selected=PHASE63_6_OPERATOR_FINAL_COMPLETENESS_AUDIT',
  'objective=Audit final operator-path certification completeness by validating closure artifacts (contract, checks, zip) and PASS contract integrity across Phase63_1..Phase63_5.',
  'changes_introduced=tools/_tmp_phase63_6_operator_final_completeness_audit_runner.ps1 (final completeness audit only).',
  'runtime_behavior_changes=NONE',
  'new_regressions_detected=' + $(if ($allOk) { 'NO' } else { 'YES' }),
  'phase_status=' + $(if ($allOk) { 'PASS' } else { 'FAIL' }),
  'proof_folder=' + $pfRel
) | Set-Content -LiteralPath $contractPath -Encoding UTF8

Write-Output ('phase63_6_folder=' + $pfRel)
Write-Output ('phase63_6_status=' + $(if ($allOk) { 'PASS' } else { 'FAIL' }))
Write-Output ('phase63_6_zip=' + $pfRel + '.zip')
