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

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pfRel = '_proof/phase63_4_operator_cert_pack_consistency_' + $ts
$pf = Join-Path '_proof' ('phase63_4_operator_cert_pack_consistency_' + $ts)
New-Item -ItemType Directory -Force -Path $pf | Out-Null

$checksPath = Join-Path $pf '90_phase63_4_operator_cert_pack_checks.txt'
$contractPath = Join-Path $pf '99_phase63_4_contract_summary.txt'

$src = Get-ChildItem -LiteralPath '_proof' -Directory |
  Where-Object { $_.Name -like 'phase63_3_proof_consistency_audit_*' } |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

$allOk = $false
$srcRel = ''
$zipRel = ''

if ($null -ne $src) {
  $srcRel = '_proof/' + $src.Name
  $srcContractPath = Join-Path $src.FullName '99_phase63_3_contract_summary.txt'
  $srcChecksPath = Join-Path $src.FullName '90_phase63_3_proof_consistency_checks.txt'
  $srcZipPath = $src.FullName + '.zip'
  $zipRel = '_proof/' + $src.Name + '.zip'

  $requiredFilesPresent =
    (Test-Path -LiteralPath $srcContractPath) -and
    (Test-Path -LiteralPath $srcChecksPath) -and
    (Test-Path -LiteralPath $srcZipPath)

  $zipHasRequiredEntries = $false
  $contractShapeOk = $false
  $contractPass = $false
  $proofFolderMatches = $false

  if ($requiredFilesPresent) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($srcZipPath)
    try {
      $entryNames = @($zip.Entries | ForEach-Object { $_.FullName })
      $entryLeafNames = @($entryNames | ForEach-Object { [System.IO.Path]::GetFileName($_) })
      $zipHasRequiredEntries =
        (@($entryLeafNames | Where-Object { $_ -eq '90_phase63_3_proof_consistency_checks.txt' }).Count -ge 1)
    }
    finally {
      $zip.Dispose()
    }

    $kv = Parse-KeyValueFile -Path $srcContractPath
    $requiredKeys = @(
      'next_phase_selected',
      'objective',
      'changes_introduced',
      'runtime_behavior_changes',
      'new_regressions_detected',
      'phase_status',
      'proof_folder'
    )

    $hasAll = $true
    $nonEmpty = $true
    foreach ($k in $requiredKeys) {
      if (-not $kv.ContainsKey($k)) {
        $hasAll = $false
        $nonEmpty = $false
        continue
      }
      if ([string]::IsNullOrWhiteSpace([string]$kv[$k])) {
        $nonEmpty = $false
      }
    }
    $contractShapeOk = $hasAll -and $nonEmpty
    $contractPass = ($kv['phase_status'] -eq 'PASS') -and ($kv['new_regressions_detected'] -eq 'NO')
    $proofFolderMatches = ($kv['proof_folder'] -eq $srcRel)
  }

  @(
    'proof_folder=' + $pfRel,
    'source_phase63_3_folder=' + $srcRel,
    'source_phase63_3_zip=' + $zipRel,
    'check_required_files_present=' + $(if ($requiredFilesPresent) { 'YES' } else { 'NO' }),
    'check_zip_has_required_entries=' + $(if ($zipHasRequiredEntries) { 'YES' } else { 'NO' }),
    'check_contract_shape=' + $(if ($contractShapeOk) { 'YES' } else { 'NO' }),
    'check_contract_pass=' + $(if ($contractPass) { 'YES' } else { 'NO' }),
    'check_contract_proof_folder_matches_source=' + $(if ($proofFolderMatches) { 'YES' } else { 'NO' })
  ) | Set-Content -LiteralPath $checksPath -Encoding UTF8

  $allOk = $requiredFilesPresent -and $zipHasRequiredEntries -and $contractShapeOk -and $contractPass -and $proofFolderMatches
}
else {
  @(
    'proof_folder=' + $pfRel,
    'source_phase63_3_folder=NONE',
    'source_phase63_3_zip=NONE',
    'check_required_files_present=NO',
    'check_zip_has_required_entries=NO',
    'check_contract_shape=NO',
    'check_contract_pass=NO',
    'check_contract_proof_folder_matches_source=NO'
  ) | Set-Content -LiteralPath $checksPath -Encoding UTF8
}

$zipOut = $pf + '.zip'
if (Test-Path -LiteralPath $zipOut) {
  Remove-Item -LiteralPath $zipOut -Force
}
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zipOut -Force

@(
  'next_phase_selected=PHASE63_4_OPERATOR_CERT_PACK_CONSISTENCY',
  'objective=Audit operator-path certification package consistency by verifying latest Phase63_3 proof files, zip entries, and contract fields without runtime execution changes.',
  'changes_introduced=tools/_tmp_phase63_4_operator_cert_pack_consistency_runner.ps1 (proof/package consistency checks only).',
  'runtime_behavior_changes=NONE',
  'new_regressions_detected=' + $(if ($allOk) { 'NO' } else { 'YES' }),
  'phase_status=' + $(if ($allOk) { 'PASS' } else { 'FAIL' }),
  'proof_folder=' + $pfRel
) | Set-Content -LiteralPath $contractPath -Encoding UTF8

Write-Output ('phase63_4_folder=' + $pfRel)
Write-Output ('phase63_4_status=' + $(if ($allOk) { 'PASS' } else { 'FAIL' }))
Write-Output ('phase63_4_zip=' + $pfRel + '.zip')
