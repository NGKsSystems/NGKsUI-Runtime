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
$pfRel = '_proof/phase64_0_certification_surface_coherence_' + $ts
$pf = Join-Path '_proof' ('phase64_0_certification_surface_coherence_' + $ts)
New-Item -ItemType Directory -Force -Path $pf | Out-Null

$checksPath = Join-Path $pf '90_phase64_0_certification_surface_coherence_checks.txt'
$contractPath = Join-Path $pf '99_phase64_0_contract_summary.txt'

$rootFiles = @(
  'certification_target.json',
  'ngksgraph.toml',
  'README.md'
)

$proofAnchors = @(
  '_proof/bootstrap_execution_report.json',
  '_proof/PHASE53_2_ENFORCEMENT_VERIFICATION_REPORT.md'
)

$rows = New-Object System.Collections.Generic.List[string]
$failed = New-Object System.Collections.Generic.List[string]

foreach ($f in $rootFiles) {
  $ok = Test-Path -LiteralPath $f
  $key = 'check_root_file_' + $f.Replace('/', '_').Replace('.', '_')
  $rows.Add($key + '=' + $(if ($ok) { 'YES' } else { 'NO' }))
  if (-not $ok) { $failed.Add($key + '=NO') }
}

foreach ($f in $proofAnchors) {
  $ok = Test-Path -LiteralPath $f
  $key = 'check_proof_anchor_' + $f.Replace('/', '_').Replace('.', '_')
  $rows.Add($key + '=' + $(if ($ok) { 'YES' } else { 'NO' }))
  if (-not $ok) { $failed.Add($key + '=NO') }
}

$phase63_7 = Get-ChildItem -LiteralPath '_proof' -Directory |
  Where-Object { $_.Name -like 'phase63_7_operator_final_signoff_audit_*' } |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

$phase63_7_exists = ($null -ne $phase63_7)
$phase63_7_rel = if ($phase63_7_exists) { '_proof/' + $phase63_7.Name } else { 'NONE' }
$rows.Add('check_phase63_7_folder_exists=' + $(if ($phase63_7_exists) { 'YES' } else { 'NO' }))
$rows.Add('phase63_7_folder=' + $phase63_7_rel)
if (-not $phase63_7_exists) { $failed.Add('check_phase63_7_folder_exists=NO') }

$phase63_7_contract_ok = $false
$phase63_7_reg_ok = $false
$phase63_7_checks_ok = $false
$phase63_7_signoff_ok = $false
$phase63_7_zip_ok = $false

if ($phase63_7_exists) {
  $contract = Join-Path $phase63_7.FullName '99_phase63_7_contract_summary.txt'
  $checks = Join-Path $phase63_7.FullName '90_phase63_7_operator_final_signoff_checks.txt'
  $signoff = Join-Path $phase63_7.FullName '95_phase63_7_operator_final_signoff.txt'
  $zip = $phase63_7.FullName + '.zip'

  $phase63_7_checks_ok = Test-Path -LiteralPath $checks
  $phase63_7_signoff_ok = Test-Path -LiteralPath $signoff
  $phase63_7_zip_ok = Test-Path -LiteralPath $zip

  if (Test-Path -LiteralPath $contract) {
    $kv = Parse-KeyValueFile -Path $contract
    $phase63_7_contract_ok = ($kv['phase_status'] -eq 'PASS')
    $phase63_7_reg_ok = ($kv['new_regressions_detected'] -eq 'NO')
  }

  $rows.Add('check_phase63_7_contract_pass=' + $(if ($phase63_7_contract_ok) { 'YES' } else { 'NO' }))
  $rows.Add('check_phase63_7_regressions_no=' + $(if ($phase63_7_reg_ok) { 'YES' } else { 'NO' }))
  $rows.Add('check_phase63_7_checks_file=' + $(if ($phase63_7_checks_ok) { 'YES' } else { 'NO' }))
  $rows.Add('check_phase63_7_signoff_file=' + $(if ($phase63_7_signoff_ok) { 'YES' } else { 'NO' }))
  $rows.Add('check_phase63_7_zip=' + $(if ($phase63_7_zip_ok) { 'YES' } else { 'NO' }))

  if (-not $phase63_7_contract_ok) { $failed.Add('check_phase63_7_contract_pass=NO') }
  if (-not $phase63_7_reg_ok) { $failed.Add('check_phase63_7_regressions_no=NO') }
  if (-not $phase63_7_checks_ok) { $failed.Add('check_phase63_7_checks_file=NO') }
  if (-not $phase63_7_signoff_ok) { $failed.Add('check_phase63_7_signoff_file=NO') }
  if (-not $phase63_7_zip_ok) { $failed.Add('check_phase63_7_zip=NO') }
}

# Deterministic hash evidence for certification surface files.
$hashTargets = @('certification_target.json', 'ngksgraph.toml', '_proof/bootstrap_execution_report.json')
foreach ($ht in $hashTargets) {
  if (Test-Path -LiteralPath $ht) {
    $h = Get-FileHash -LiteralPath $ht -Algorithm SHA256
    $rows.Add('sha256_' + $ht.Replace('/', '_').Replace('.', '_') + '=' + $h.Hash)
  }
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
  'next_phase_selected=PHASE64_0_CERTIFICATION_SURFACE_COHERENCE',
  'objective=Validate final certification surface coherence (root manifests, proof anchors, and Phase63_7 signoff artifacts) with deterministic hash evidence only.',
  'changes_introduced=tools/_tmp_phase64_0_certification_surface_coherence_runner.ps1 (certification surface audit only).',
  'runtime_behavior_changes=NONE',
  'new_regressions_detected=' + $(if ($allOk) { 'NO' } else { 'YES' }),
  'phase_status=' + $(if ($allOk) { 'PASS' } else { 'FAIL' }),
  'proof_folder=' + $pfRel
) | Set-Content -LiteralPath $contractPath -Encoding UTF8

Write-Output ('phase64_0_folder=' + $pfRel)
Write-Output ('phase64_0_status=' + $(if ($allOk) { 'PASS' } else { 'FAIL' }))
Write-Output ('phase64_0_zip=' + $pfRel + '.zip')
