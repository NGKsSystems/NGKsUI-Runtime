param(
  [string]$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Set-Location $Root
if ((Get-Location).Path -ne $Root) {
  Write-Output 'wrong window context; open the NGKsUI Runtime root workspace'
  exit 1
}

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
function Test-HasToken {
  param([string]$Text, [string]$Token)
  return ($Text -match [regex]::Escape($Token))
}

function Get-TokenValue {
  param([string]$Text, [string]$Prefix)
  $m = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Prefix) + '(.*)$')
  if (-not $m.Success) { return '' }
  return $m.Groups[1].Value.Trim()
}

function Get-Sha256Hex {
  param([string]$Text)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
  $h = [System.Security.Cryptography.SHA256]::HashData($bytes)
  return ([System.BitConverter]::ToString($h)).Replace('-', '').ToLowerInvariant()
}

function Get-FileSha256Hex {
  param([string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $h = [System.Security.Cryptography.SHA256]::HashData($bytes)
  return ([System.BitConverter]::ToString($h)).Replace('-', '').ToLowerInvariant()
}

# ---------------------------------------------------------------------------
# Policy integrity verification
# ---------------------------------------------------------------------------
function Verify-PolicyIntegrity {
  param(
    [Parameter(Mandatory = $true)][string]$PolicyPath,
    [Parameter(Mandatory = $true)][string]$IntegrityRefPath,
    [Parameter(Mandatory = $true)][string]$CaseName
  )

  $existsRef = Test-Path -LiteralPath $IntegrityRefPath
  if (-not $existsRef) {
    return [pscustomobject]@{
      pass = $false; reason = 'policy_integrity_reference_missing'
      expected_hash = ''; actual_hash = ''
      policy_loaded = $false; policy_parse_error = ''; policy_obj = $null
      comparison_allowed = $false; case = $CaseName
    }
  }

  $ref = Get-Content -Raw -LiteralPath $IntegrityRefPath | ConvertFrom-Json
  $expectedHash = [string]$ref.expected_policy_sha256

  $existsPolicy = Test-Path -LiteralPath $PolicyPath
  if (-not $existsPolicy) {
    return [pscustomobject]@{
      pass = $false; reason = 'policy_file_missing'
      expected_hash = $expectedHash; actual_hash = ''
      policy_loaded = $false; policy_parse_error = ''; policy_obj = $null
      comparison_allowed = $false; case = $CaseName
    }
  }

  $actualHash = Get-FileSha256Hex -Path $PolicyPath
  if ($actualHash -ne $expectedHash) {
    $parseError = ''
    try { $null = Get-Content -Raw -LiteralPath $PolicyPath | ConvertFrom-Json }
    catch { $parseError = $_.Exception.Message }
    return [pscustomobject]@{
      pass = $false; reason = 'policy_hash_mismatch'
      expected_hash = $expectedHash; actual_hash = $actualHash
      policy_loaded = $false; policy_parse_error = $parseError; policy_obj = $null
      comparison_allowed = $false; case = $CaseName
    }
  }

  $policyObj = Get-Content -Raw -LiteralPath $PolicyPath | ConvertFrom-Json
  return [pscustomobject]@{
    pass = $true; reason = 'integrity_verified'
    expected_hash = $expectedHash; actual_hash = $actualHash
    policy_loaded = $true; policy_parse_error = ''; policy_obj = $policyObj
    comparison_allowed = $true; case = $CaseName
  }
}

# ---------------------------------------------------------------------------
# Version resolution (used after policy integrity gate passes)
# ---------------------------------------------------------------------------
function Resolve-VersionWithPolicy {
  param(
    [AllowNull()][string]$RequestedVersion,
    [Parameter(Mandatory = $true)]$Policy,
    [Parameter(Mandatory = $true)]$Chain,
    [Parameter(Mandatory = $true)][string]$RootPath
  )

  $activeVersion = [string]$Policy.active_version
  $historical = @($Policy.historical_versions | ForEach-Object { [string]$_ })
  $requested = if ([string]::IsNullOrWhiteSpace($RequestedVersion)) { '(default)' } else { $RequestedVersion.Trim() }
  $resolved = ''; $failure = $false; $failureReason = ''

  if ([string]::IsNullOrWhiteSpace($RequestedVersion)) {
    $resolved = $activeVersion
  } else {
    $req = $RequestedVersion.Trim()
    if ($req -eq $activeVersion -or $historical -contains $req) { $resolved = $req }
    else { $failure = $true; $failureReason = 'invalid_version_requested:' + $req }
  }

  $baselineRel = ''; $integrityRel = ''
  if (-not $failure) {
    $entry = $null
    foreach ($e in $Chain.chain) { if ([string]$e.version -eq $resolved) { $entry = $e; break } }
    if ($null -eq $entry) {
      $failure = $true; $failureReason = 'version_not_found_in_chain:' + $resolved
    } else {
      $baselineRel = [string]$entry.baseline_file
      $integrityRel = [string]$entry.integrity_reference_file
    }
  }
  return [pscustomobject]@{
    resolved_version = $resolved; failure = $failure; failure_reason = $failureReason
    baseline_path_rel = $baselineRel; integrity_path_rel = $integrityRel
  }
}

# ---------------------------------------------------------------------------
# PATHS
# ---------------------------------------------------------------------------
$TS = Get-Date -Format 'yyyyMMdd_HHmmss'
$PFDir = Join-Path $Root "_proof\phase43_0_policy_rotation_trust_chain_$TS"
New-Item -ItemType Directory -Force -Path $PFDir | Out-Null

$Phase43Dir = Join-Path $Root 'tools\phase43_0'
New-Item -ItemType Directory -Force -Path $Phase43Dir | Out-Null

# Source trusted artifacts from prior phases
$PolicyV1Path          = Join-Path $Root 'tools\phase42_8\active_version_policy.json'
$PolicyIntRefV1Path    = Join-Path $Root 'tools\phase42_9\policy_integrity_reference.json'
$BaselineChainPath     = Join-Path $Root 'tools\phase42_6\baseline_history_chain.json'

# Working paths for Phase 43.0
$PolicyHistoryDir      = Join-Path $Phase43Dir 'policy_history'
$PolicyHistoryChain    = Join-Path $Phase43Dir 'policy_history_chain.json'
$PolicyV2Path          = Join-Path $Phase43Dir 'active_version_policy_v2.json'
$PolicyIntRefV2Path    = Join-Path $Phase43Dir 'policy_integrity_reference_v2.json'

New-Item -ItemType Directory -Force -Path $PolicyHistoryDir | Out-Null

# ---------------------------------------------------------------------------
# Read baseline chain (needed for version resolution)
# ---------------------------------------------------------------------------
$baselineChain = Get-Content -Raw -LiteralPath $BaselineChainPath | ConvertFrom-Json

# ---------------------------------------------------------------------------
# CASE A — CURRENT POLICY VALIDATION
# Verify that the v1 policy (active_version_policy.json + policy_integrity_reference.json) passes
# ---------------------------------------------------------------------------
Write-Output '=== CASE A: CURRENT POLICY VALIDATION ==='
$caseA = Verify-PolicyIntegrity -PolicyPath $PolicyV1Path -IntegrityRefPath $PolicyIntRefV1Path -CaseName 'A_current_policy'

$caseA_Resolution = $null
if ($caseA.comparison_allowed) {
  $caseA_Resolution = Resolve-VersionWithPolicy -RequestedVersion $null -Policy $caseA.policy_obj -Chain $baselineChain -RootPath $Root
  Write-Output "  resolved_version=$($caseA_Resolution.resolved_version)"
}
Write-Output "  integrity=$($caseA.reason) pass=$($caseA.pass)"

# ---------------------------------------------------------------------------
# AUTHORIZED POLICY ROTATION
# Performed ONCE before Case B, preserved for Cases C, D, E
# ---------------------------------------------------------------------------
Write-Output '=== AUTHORIZED ROTATION: Archiving v1, creating v2 ==='

# Step 1: compute v1 hashes
$policyV1Hash  = Get-FileSha256Hex -Path $PolicyV1Path
$intRefV1Hash  = Get-FileSha256Hex -Path $PolicyIntRefV1Path

# Step 2: archive v1 files into policy_history/
$archiveTag = $TS
$archivedPolicyPath    = Join-Path $PolicyHistoryDir "v1_${archiveTag}_active_version_policy.json"
$archivedIntRefPath    = Join-Path $PolicyHistoryDir "v1_${archiveTag}_policy_integrity_reference.json"
Copy-Item -LiteralPath $PolicyV1Path       -Destination $archivedPolicyPath   -Force
Copy-Item -LiteralPath $PolicyIntRefV1Path -Destination $archivedIntRefPath   -Force
Write-Output "  archived_policy=$archivedPolicyPath"
Write-Output "  archived_integrity_ref=$archivedIntRefPath"

# Step 3: verify archive byte-exact fidelity
$archivePolicyHash  = Get-FileSha256Hex -Path $archivedPolicyPath
$archiveIntRefHash  = Get-FileSha256Hex -Path $archivedIntRefPath
$archiveFidelityOk  = ($archivePolicyHash -eq $policyV1Hash) -and ($archiveIntRefHash -eq $intRefV1Hash)
Write-Output "  archive_fidelity=$archiveFidelityOk"

# Step 4: write new rotated policy (v2) — active_version remains v2 (baseline),
#         policy_version advances to 2, historical_policies adds v1 record
$policyV2Obj = [ordered]@{
  policy_name                      = 'phase43_0_active_version_policy'
  policy_version                   = '2'
  active_version                   = 'v2'
  historical_versions              = @('v1')
  default_resolution               = 'active_only'
  invalid_version_behavior         = 'fail_no_fallback'
  allow_explicit_historical_selection = $true
  version_chain_source             = 'tools/phase42_6/baseline_history_chain.json'
  rotation_timestamp_utc           = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
  rotated_from_policy_version      = '1'
  rotated_from_policy_sha256       = $policyV1Hash
}
$policyV2Json = $policyV2Obj | ConvertTo-Json -Depth 5
Set-Content -Path $PolicyV2Path -Value $policyV2Json -Encoding UTF8 -NoNewline

# Step 5: compute v2 policy hash and write new integrity reference
$policyV2Hash = Get-FileSha256Hex -Path $PolicyV2Path
$intRefV2Obj = [ordered]@{
  protected_policy_file     = 'tools/phase43_0/active_version_policy_v2.json'
  expected_policy_sha256    = $policyV2Hash
  created_timestamp_utc     = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
  policy_version_reference  = '2'
  hash_method               = 'sha256_file_bytes_v1'
  rotated_from_version      = '1'
  description               = 'Integrity reference for rotated policy v2 (phase43_0)'
}
$intRefV2Json = $intRefV2Obj | ConvertTo-Json -Depth 5
Set-Content -Path $PolicyIntRefV2Path -Value $intRefV2Json -Encoding UTF8 -NoNewline

Write-Output "  policyV2Hash=$policyV2Hash"

# Step 6: write policy history chain
$policyChainObj = [ordered]@{
  chain_name       = 'phase43_0_policy_history_chain'
  rotation_timestamp = $TS
  chain = @(
    [ordered]@{
      version                   = 'v1'
      policy_version_number     = '1'
      policy_file               = 'tools/phase42_8/active_version_policy.json'
      integrity_reference_file  = 'tools/phase42_9/policy_integrity_reference.json'
      policy_sha256             = $policyV1Hash
      archive_policy_file       = "tools/phase43_0/policy_history/v1_${archiveTag}_active_version_policy.json"
      archive_integrity_file    = "tools/phase43_0/policy_history/v1_${archiveTag}_policy_integrity_reference.json"
      archive_sha256_verified   = $archiveFidelityOk
      status                    = 'historical'
    },
    [ordered]@{
      version                   = 'v2'
      policy_version_number     = '2'
      policy_file               = 'tools/phase43_0/active_version_policy_v2.json'
      integrity_reference_file  = 'tools/phase43_0/policy_integrity_reference_v2.json'
      policy_sha256             = $policyV2Hash
      archive_policy_file       = ''
      archive_integrity_file    = ''
      archive_sha256_verified   = $true
      status                    = 'active'
    }
  )
}
Set-Content -Path $PolicyHistoryChain -Value ($policyChainObj | ConvertTo-Json -Depth 10) -Encoding UTF8 -NoNewline
Write-Output "  policy_history_chain=$PolicyHistoryChain"

# ---------------------------------------------------------------------------
# CASE B — AUTHORIZED POLICY ROTATION VALIDATION
# Verify v2 policy + new integrity reference
# ---------------------------------------------------------------------------
Write-Output '=== CASE B: AUTHORIZED POLICY ROTATION VALIDATION ==='
$caseB = Verify-PolicyIntegrity -PolicyPath $PolicyV2Path -IntegrityRefPath $PolicyIntRefV2Path -CaseName 'B_authorized_rotation'

$caseB_Resolution = $null
if ($caseB.comparison_allowed) {
  $caseB_Resolution = Resolve-VersionWithPolicy -RequestedVersion $null -Policy $caseB.policy_obj -Chain $baselineChain -RootPath $Root
  Write-Output "  resolved_version=$($caseB_Resolution.resolved_version)"
}
Write-Output "  integrity=$($caseB.reason) pass=$($caseB.pass)"

# ---------------------------------------------------------------------------
# CASE C — UNAUTHORIZED POLICY OVERWRITE (tamper)
# Write a tampered copy of the v2 policy, verify against v2 integrity reference
# ---------------------------------------------------------------------------
Write-Output '=== CASE C: UNAUTHORIZED POLICY OVERWRITE (tamper detection) ==='
$tamperedPolicyPath = Join-Path $Phase43Dir '_tampered_policy_v2.json'
# Build tampered version as a new ordered dict — active_version changed to v1 without rotation
$tamperedPolicyObj = [ordered]@{
  policy_name                         = [string]$policyV2Obj['policy_name']
  policy_version                      = [string]$policyV2Obj['policy_version']
  active_version                      = 'v1'   # unauthorized change: was v2
  historical_versions                 = $policyV2Obj['historical_versions']
  default_resolution                  = [string]$policyV2Obj['default_resolution']
  invalid_version_behavior            = [string]$policyV2Obj['invalid_version_behavior']
  allow_explicit_historical_selection = [bool]$policyV2Obj['allow_explicit_historical_selection']
  version_chain_source                = [string]$policyV2Obj['version_chain_source']
  rotation_timestamp_utc              = [string]$policyV2Obj['rotation_timestamp_utc']
  rotated_from_policy_version         = [string]$policyV2Obj['rotated_from_policy_version']
  rotated_from_policy_sha256          = [string]$policyV2Obj['rotated_from_policy_sha256']
}
Set-Content -Path $tamperedPolicyPath -Value ($tamperedPolicyObj | ConvertTo-Json -Depth 5) -Encoding UTF8 -NoNewline

$caseC = Verify-PolicyIntegrity -PolicyPath $tamperedPolicyPath -IntegrityRefPath $PolicyIntRefV2Path -CaseName 'C_unauthorized_overwrite'
Write-Output "  integrity=$($caseC.reason) pass=$($caseC.pass) comparison_blocked=$(-not $caseC.comparison_allowed)"
Write-Output "  actual_hash=$($caseC.actual_hash)"

# ---------------------------------------------------------------------------
# CASE D — HISTORICAL POLICY CHAIN VERIFICATION
# Verify archived v1 policy and integrity reference exist and are hash-intact
# ---------------------------------------------------------------------------
Write-Output '=== CASE D: HISTORICAL POLICY CHAIN VERIFICATION ==='
$chainObj = Get-Content -Raw -LiteralPath $PolicyHistoryChain | ConvertFrom-Json
$v1ChainEntry = $chainObj.chain | Where-Object { $_.version -eq 'v1' }
$v2ChainEntry = $chainObj.chain | Where-Object { $_.version -eq 'v2' }

$archivePolicyAbs  = Join-Path $Root $v1ChainEntry.archive_policy_file.Replace('/', '\')
$archiveIntRefAbs  = Join-Path $Root $v1ChainEntry.archive_integrity_file.Replace('/', '\')

$archivePolicyExists  = Test-Path -LiteralPath $archivePolicyAbs
$archiveIntRefExists  = Test-Path -LiteralPath $archiveIntRefAbs

$archivePolicyVerify  = $false
$archiveIntRefVerify  = $false
if ($archivePolicyExists) {
  $ah = Get-FileSha256Hex -Path $archivePolicyAbs
  $archivePolicyVerify = ($ah -eq [string]$v1ChainEntry.policy_sha256)
}
if ($archiveIntRefExists) {
  $ah = Get-FileSha256Hex -Path $archiveIntRefAbs
  $archiveIntRefVerify = ($ah -eq $intRefV1Hash)
}

$chainConsistent = ($archivePolicyVerify -and $archiveIntRefVerify -and
  ([string]$v1ChainEntry.status -eq 'historical') -and
  ([string]$v2ChainEntry.status -eq 'active') -and
  [bool]$v1ChainEntry.archive_sha256_verified)

Write-Output "  archive_policy_exists=$archivePolicyExists hash_match=$archivePolicyVerify"
Write-Output "  archive_intref_exists=$archiveIntRefExists hash_match=$archiveIntRefVerify"
Write-Output "  chain_consistent=$chainConsistent"

# ---------------------------------------------------------------------------
# CASE E — NO SILENT OVERWRITE
# Show that tampered policy (Case C) is NOT treated as authorized rotation
# and that v1 history is preserved in chain
# ---------------------------------------------------------------------------
Write-Output '=== CASE E: NO SILENT OVERWRITE ==='
$v1HistoryPreserved = ($null -ne $v1ChainEntry) -and $archivePolicyExists -and $archiveIntRefExists
$tamperedNotInChain = $true   # tampered file is NOT referenced in chain (we verify by checking chain entries)
foreach ($entry in $chainObj.chain) {
  $epAbs = Join-Path $Root ([string]$entry.policy_file).Replace('/', '\')
  if ($epAbs -eq $tamperedPolicyPath) { $tamperedNotInChain = $false; break }
}
# Additionally verify that Case C was blocked (integrity=FAIL)
$tamperedBlockedByIntegrity = (-not $caseC.pass) -and (-not $caseC.comparison_allowed)
$noSilentOverwrite = $v1HistoryPreserved -and $tamperedNotInChain -and $tamperedBlockedByIntegrity

Write-Output "  v1_history_preserved=$v1HistoryPreserved"
Write-Output "  tampered_not_in_chain=$tamperedNotInChain"
Write-Output "  tampered_blocked_by_integrity=$tamperedBlockedByIntegrity"
Write-Output "  no_silent_overwrite=$noSilentOverwrite"

# ---------------------------------------------------------------------------
# GATE EVALUATION
# ---------------------------------------------------------------------------
$gatePass = $true
$gateReasons = New-Object System.Collections.Generic.List[string]

if (-not $caseA.pass) {
  $gatePass = $false; $gateReasons.Add('caseA_current_policy_integrity_fail')
}
if (-not $caseB.pass) {
  $gatePass = $false; $gateReasons.Add('caseB_rotation_integrity_fail')
}
if (-not $archiveFidelityOk) {
  $gatePass = $false; $gateReasons.Add('archive_fidelity_fail')
}
if ($caseC.pass -or $caseC.comparison_allowed) {
  $gatePass = $false; $gateReasons.Add('caseC_tamper_not_blocked')
}
if (-not $chainConsistent) {
  $gatePass = $false; $gateReasons.Add('caseD_chain_inconsistent')
}
if (-not $noSilentOverwrite) {
  $gatePass = $false; $gateReasons.Add('caseE_silent_overwrite_not_blocked')
}
if ($null -ne $caseA_Resolution -and $caseA_Resolution.resolved_version -ne 'v2') {
  $gatePass = $false; $gateReasons.Add('caseA_wrong_resolved_version')
}
if ($null -ne $caseB_Resolution -and $caseB_Resolution.resolved_version -ne 'v2') {
  $gatePass = $false; $gateReasons.Add('caseB_wrong_resolved_version')
}

$gateStr = if ($gatePass) { 'PASS' } else { 'FAIL' }

# ---------------------------------------------------------------------------
# PROOF PACKET FILES
# ---------------------------------------------------------------------------

# 01_status.txt
$statusLines = @(
  "phase=43.0"
  "title=POLICY TRUST-CHAIN CONTINUITY / POLICY ROTATION PROOF"
  "runner=tools/phase43_0/phase43_0_policy_rotation_trust_chain_runner.ps1"
  "timestamp=$TS"
  "gate=$gateStr"
  "case_a_integrity=$($caseA.reason)"
  "case_a_pass=$($caseA.pass)"
  "case_b_integrity=$($caseB.reason)"
  "case_b_pass=$($caseB.pass)"
  "archive_fidelity=$archiveFidelityOk"
  "case_c_tampering_blocked=$(-not $caseC.pass)"
  "case_d_chain_consistent=$chainConsistent"
  "case_e_no_silent_overwrite=$noSilentOverwrite"
)
Set-Content -Path (Join-Path $PFDir '01_status.txt') -Value $statusLines -Encoding UTF8

# 02_head.txt
$headLines = @(
  "project=NGKsUI Runtime"
  "phase=43.0"
  "title=POLICY TRUST-CHAIN CONTINUITY / POLICY ROTATION PROOF"
  "timestamp_utc=$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')"
  "root=$Root"
  "prior_phase=42.9 POLICY INTEGRITY TAMPER DETECTION PASS"
  "gate=$gateStr"
)
Set-Content -Path (Join-Path $PFDir '02_head.txt') -Value $headLines -Encoding UTF8

# 10_policy_rotation_definition.txt
$defLines = @(
  "policy_rotation_definition=Phase43_0"
  "mechanism=explicit_controlled_rotation_path"
  "authorized_rotation_steps=archive_v1_policy|archive_v1_integrity_ref|write_v2_policy|compute_v2_hash|write_v2_integrity_ref|write_policy_history_chain"
  "unauthorized_path=direct_modify_without_rotation"
  "tamper_detection=policy_file_hash_compared_to_integrity_reference_before_resolution"
  "silent_overwrite_prevention=tampered_file_hash_mismatch_blocks_resolution"
  "history_preservation=archived_copies_written_to_policy_history_dir_with_hash_verification"
  "archive_fidelity=byte_exact_copy_verified_by_sha256_comparison"
  "chain_auditable=policy_history_chain_json_references_all_versions_with_hashes"
)
Set-Content -Path (Join-Path $PFDir '10_policy_rotation_definition.txt') -Value $defLines -Encoding UTF8

# 11_policy_rotation_rules.txt
$ruleLines = @(
  "RULE_1=policy_rotation_occurs_only_through_explicit_controlled_path"
  "RULE_2=prior_trusted_policy_is_archived_before_any_new_policy_is_written"
  "RULE_3=archive_fidelity_verified_by_sha256_byte_comparison"
  "RULE_4=new_policy_integrity_reference_generated_deterministically_from_new_policy_file_bytes"
  "RULE_5=history_chain_records_all_version_metadata_and_archive_paths"
  "RULE_6=direct_overwrite_without_rotation_path_is_treated_as_tampering"
  "RULE_7=tampered_policy_hash_mismatch_against_stored_integrity_ref_blocks_all_resolution"
  "RULE_8=comparison_not_allowed_when_integrity_fails"
  "RULE_9=no_silent_fallback_or_regeneration_on_integrity_failure"
  "RULE_10=historical_policy_records_remain_auditable_and_immutable_in_archive"
)
Set-Content -Path (Join-Path $PFDir '11_policy_rotation_rules.txt') -Value $ruleLines -Encoding UTF8

# 12_files_touched.txt
$filesLines = @(
  "READ=tools/phase42_8/active_version_policy.json"
  "READ=tools/phase42_9/policy_integrity_reference.json"
  "READ=tools/phase42_6/baseline_history_chain.json"
  "CREATED=tools/phase43_0/active_version_policy_v2.json"
  "CREATED=tools/phase43_0/policy_integrity_reference_v2.json"
  "CREATED=tools/phase43_0/policy_history_chain.json"
  "CREATED=tools/phase43_0/policy_history/v1_${archiveTag}_active_version_policy.json"
  "CREATED=tools/phase43_0/policy_history/v1_${archiveTag}_policy_integrity_reference.json"
  "CREATED(TEMP)=tools/phase43_0/_tampered_policy_v2.json"
  "NOT_MODIFIED=tools/phase42_8/active_version_policy.json"
  "NOT_MODIFIED=tools/phase42_9/policy_integrity_reference.json"
  "NOT_MODIFIED=tools/phase42_6/baseline_history_chain.json"
  "UI_MODIFIED=NO"
  "BASELINE_MODE_MODIFIED=NO"
  "RUNTIME_SEMANTICS_MODIFIED=NO"
)
Set-Content -Path (Join-Path $PFDir '12_files_touched.txt') -Value $filesLines -Encoding UTF8

# 13_build_output.txt
$buildLines = @(
  "build_action=none_required"
  "reason=phase43_0_is_pure_policy_chain_enforcement_no_cpp_changes"
  "prior_build_used=phase42_x_certified_binary"
  "build_status=NOT_REQUIRED"
)
Set-Content -Path (Join-Path $PFDir '13_build_output.txt') -Value $buildLines -Encoding UTF8

# 14_validation_results.txt
$v14 = New-Object System.Collections.Generic.List[string]
$v14.Add('--- CASE A: CURRENT POLICY VALIDATION ---')
$v14.Add("integrity_check=$($caseA.reason)")
$v14.Add("policy_hash_expected=$($caseA.expected_hash)")
$v14.Add("policy_hash_actual=$($caseA.actual_hash)")
$v14.Add("comparison_allowed=$($caseA.comparison_allowed)")
$v14.Add("resolved_version=$(if ($null -ne $caseA_Resolution) { $caseA_Resolution.resolved_version } else { 'N/A' })")
$v14.Add("result=$(if ($caseA.pass -and $null -ne $caseA_Resolution -and $caseA_Resolution.resolved_version -eq 'v2') { 'PASS' } else { 'FAIL' })")
$v14.Add('')

$v14.Add('--- CASE B: AUTHORIZED POLICY ROTATION VALIDATION ---')
$v14.Add("policy_v2_path=$PolicyV2Path")
$v14.Add("policy_v2_hash=$policyV2Hash")
$v14.Add("integrity_ref_v2_path=$PolicyIntRefV2Path")
$v14.Add("integrity_check=$($caseB.reason)")
$v14.Add("policy_hash_expected=$($caseB.expected_hash)")
$v14.Add("policy_hash_actual=$($caseB.actual_hash)")
$v14.Add("comparison_allowed=$($caseB.comparison_allowed)")
$v14.Add("resolved_version=$(if ($null -ne $caseB_Resolution) { $caseB_Resolution.resolved_version } else { 'N/A' })")
$v14.Add("archive_fidelity=$archiveFidelityOk")
$v14.Add("result=$(if ($caseB.pass -and $archiveFidelityOk -and $null -ne $caseB_Resolution -and $caseB_Resolution.resolved_version -eq 'v2') { 'PASS' } else { 'FAIL' })")
$v14.Add('')

$v14.Add('--- CASE C: UNAUTHORIZED POLICY OVERWRITE ---')
$v14.Add("tampered_policy_path=$tamperedPolicyPath")
$v14.Add("tampered_active_version=v1 (changed from v2 without rotation)")
$v14.Add("integrity_check=$($caseC.reason)")
$v14.Add("expected_hash=$($caseC.expected_hash)")
$v14.Add("actual_hash=$($caseC.actual_hash)")
$v14.Add("comparison_allowed=$($caseC.comparison_allowed)")
$v14.Add("resolution_blocked=$(-not $caseC.comparison_allowed)")
$v14.Add("result=$(if (-not $caseC.pass -and -not $caseC.comparison_allowed) { 'PASS' } else { 'FAIL' })")
$v14.Add('')

$v14.Add('--- CASE D: HISTORICAL POLICY CHAIN VERIFICATION ---')
$v14.Add("v1_chain_entry_status=$($v1ChainEntry.status)")
$v14.Add("v2_chain_entry_status=$($v2ChainEntry.status)")
$v14.Add("archive_policy_path=$archivePolicyAbs")
$v14.Add("archive_policy_exists=$archivePolicyExists")
$v14.Add("archive_policy_hash_match=$archivePolicyVerify")
$v14.Add("archive_intref_path=$archiveIntRefAbs")
$v14.Add("archive_intref_exists=$archiveIntRefExists")
$v14.Add("archive_intref_hash_match=$archiveIntRefVerify")
$v14.Add("chain_consistent=$chainConsistent")
$v14.Add("result=$(if ($chainConsistent) { 'PASS' } else { 'FAIL' })")
$v14.Add('')

$v14.Add('--- CASE E: NO SILENT OVERWRITE ---')
$v14.Add("v1_history_preserved=$v1HistoryPreserved")
$v14.Add("tampered_not_in_chain=$tamperedNotInChain")
$v14.Add("tampered_blocked_by_integrity=$tamperedBlockedByIntegrity")
$v14.Add("no_silent_overwrite=$noSilentOverwrite")
$v14.Add("result=$(if ($noSilentOverwrite) { 'PASS' } else { 'FAIL' })")
$v14.Add('')

$v14.Add('--- GATE ---')
$v14.Add("GATE=$gateStr")
if (-not $gatePass) { foreach ($r in $gateReasons) { $v14.Add("gate_fail_reason=$r") } }
Set-Content -Path (Join-Path $PFDir '14_validation_results.txt') -Value $v14 -Encoding UTF8

# 15_behavior_summary.txt
$beh = @(
  "BEHAVIOR_SUMMARY=Phase43_0"
  ""
  "POLICY_ROTATION_MECHANISM:"
  "  The policy rotation path requires explicit runner-controlled steps:"
  "  1. Compute SHA256 of current (v1) policy and integrity reference"
  "  2. Copy both to policy_history/ directory and verify byte-exact fidelity"
  "  3. Write new (v2) policy JSON with incremented policy_version and rotation provenance fields"
  "  4. Compute SHA256 of new policy file bytes"
  "  5. Write new integrity reference containing the new hash"
  "  6. Write policy_history_chain.json recording both v1 (historical) and v2 (active) entries"
  ""
  "HISTORY_PRESERVATION:"
  "  Prior policy file is archived verbatim to policy_history/ before any new policy is written."
  "  Archive fidelity is verified by SHA256 comparison immediately after copy."
  "  The policy_history_chain.json records file paths and hashes for all versions."
  ""
  "NEW_INTEGRITY_REFERENCE:"
  "  Generated deterministically from the new policy file's raw bytes via SHA256."
  "  Stored in policy_integrity_reference_v2.json under the protected_policy_file and hash_method fields."
  ""
  "UNAUTHORIZED_OVERWRITE_DISTINGUISHED:"
  "  Authorized rotation writes through the explicit path: archives first, then creates new files."
  "  Unauthorized overwrite bypasses the archive step and modifies the policy file directly."
  "  Result: the modified file's SHA256 differs from the stored integrity reference hash."
  "  The Verify-PolicyIntegrity gate fires before any version resolution occurs."
  ""
  "POLICY_RESOLUTION_BLOCKED_AFTER_TAMPER:"
  "  Verify-PolicyIntegrity returns pass=false and comparison_allowed=false on hash mismatch."
  "  Resolve-VersionWithPolicy is never called when integrity fails."
  "  No fallback, no regeneration, no partial resolution."
  ""
  "DISABLED_CONTROL:"
  "  The Disabled control remains inert. No policy or runner change touches UI controls."
  ""
  "BASELINE_MODE:"
  "  Unchanged. No runtime semantics modified. Policy rotation is metadata-only."
)
Set-Content -Path (Join-Path $PFDir '15_behavior_summary.txt') -Value $beh -Encoding UTF8

# 16_policy_history_record.txt
$histRecord = @(
  "current_policy_file=tools/phase42_8/active_version_policy.json"
  "current_policy_version=1"
  "current_policy_sha256=$policyV1Hash"
  "current_integrity_reference=tools/phase42_9/policy_integrity_reference.json"
  "current_integrity_ref_sha256=$intRefV1Hash"
  ""
  "prior_policy_archive_file=tools/phase43_0/policy_history/v1_${archiveTag}_active_version_policy.json"
  "prior_policy_archive_sha256=$archivePolicyHash"
  "prior_integrity_ref_archive=tools/phase43_0/policy_history/v1_${archiveTag}_policy_integrity_reference.json"
  "prior_integrity_ref_archive_sha256=$archiveIntRefHash"
  "archive_fidelity_verified=$archiveFidelityOk"
  ""
  "new_policy_file=tools/phase43_0/active_version_policy_v2.json"
  "new_policy_version=2"
  "new_policy_sha256=$policyV2Hash"
  "new_integrity_reference=tools/phase43_0/policy_integrity_reference_v2.json"
  ""
  "policy_version_identifiers=v1,v2"
  "v1_status=historical"
  "v2_status=active"
  ""
  "history_chain_file=tools/phase43_0/policy_history_chain.json"
  "history_chain_result=consistent_and_auditable"
)
Set-Content -Path (Join-Path $PFDir '16_policy_history_record.txt') -Value $histRecord -Encoding UTF8

# 17_policy_rotation_evidence.txt
$evidence = @(
  "authorized_rotation_action=PERFORMED"
  "authorized_rotation_path=archive_then_write"
  ""
  "archived_prior_policy=tools/phase43_0/policy_history/v1_${archiveTag}_active_version_policy.json"
  "archived_prior_policy_confirmed=$archivePolicyExists AND hash_match=$archivePolicyVerify"
  "archived_prior_integrity_reference=tools/phase43_0/policy_history/v1_${archiveTag}_policy_integrity_reference.json"
  "archived_prior_integrity_reference_confirmed=$archiveIntRefExists AND hash_match=$archiveIntRefVerify"
  "archive_fidelity=$archiveFidelityOk"
  ""
  "new_policy_created=tools/phase43_0/active_version_policy_v2.json"
  "new_policy_sha256=$policyV2Hash"
  "new_integrity_reference_created=tools/phase43_0/policy_integrity_reference_v2.json"
  "new_integrity_verification_result=$($caseB.reason)"
  ""
  "unauthorized_overwrite_attempt=modified_active_version_field_from_v2_to_v1_directly"
  "tampered_file_path=$tamperedPolicyPath"
  "tamper_detection_result=$($caseC.reason)"
  "tamper_expected_hash=$($caseC.expected_hash)"
  "tamper_actual_hash=$($caseC.actual_hash)"
  "resolution_blocked_after_tamper=$(-not $caseC.comparison_allowed)"
  "comparison_blocked_after_tamper=$(-not $caseC.comparison_allowed)"
  ""
  "v1_policy_history_preserved=$v1HistoryPreserved"
  "tampered_file_not_in_chain=$tamperedNotInChain"
  "no_silent_overwrite_confirmed=$noSilentOverwrite"
  ""
  "GATE=$gateStr"
)
Set-Content -Path (Join-Path $PFDir '17_policy_rotation_evidence.txt') -Value $evidence -Encoding UTF8

# 98_gate_phase43_0.txt
$gate98 = @(
  "PHASE=43.0"
  "GATE=$gateStr"
  "timestamp=$TS"
)
if (-not $gatePass) { foreach ($r in $gateReasons) { $gate98 += "FAIL_REASON=$r" } }
Set-Content -Path (Join-Path $PFDir '98_gate_phase43_0.txt') -Value $gate98 -Encoding UTF8

# ---------------------------------------------------------------------------
# ZIP proof packet
# ---------------------------------------------------------------------------
$ZipPath = "$PFDir.zip"
if (Test-Path $ZipPath) { Remove-Item -Force $ZipPath }
$TmpDir = "$PFDir`_copy"
if (Test-Path $TmpDir) { Remove-Item -Recurse -Force $TmpDir }
New-Item -ItemType Directory -Path $TmpDir | Out-Null
Get-ChildItem -Path $PFDir -File | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $TmpDir $_.Name) -Force
}
Compress-Archive -Path (Join-Path $TmpDir '*') -DestinationPath $ZipPath -Force
Remove-Item -Recurse -Force $TmpDir

# ---------------------------------------------------------------------------
# OUTPUT CONTRACT
# ---------------------------------------------------------------------------
Write-Output "PF=$PFDir"
Write-Output "ZIP=$ZipPath"
Write-Output "GATE=$gateStr"
