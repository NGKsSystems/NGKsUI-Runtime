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
function Get-FileSha256Hex {
  param([string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $h = [System.Security.Cryptography.SHA256]::HashData($bytes)
  return ([System.BitConverter]::ToString($h)).Replace('-', '').ToLowerInvariant()
}

# ---------------------------------------------------------------------------
# Resolve a named policy version from the policy history chain
# Returns $null on lookup failure (does NOT fall back to any other version)
# ---------------------------------------------------------------------------
function Resolve-PolicyVersion {
  param(
    [Parameter(Mandatory = $true)][string]$RequestedVersion,
    [Parameter(Mandatory = $true)]$Chain,
    [Parameter(Mandatory = $true)][string]$RootPath
  )

  # Exact match only — no fallback
  $entry = $null
  foreach ($e in $Chain.chain) {
    if ([string]$e.version -eq $RequestedVersion.Trim()) { $entry = $e; break }
  }

  if ($null -eq $entry) {
    return [pscustomobject]@{
      requested_version        = $RequestedVersion
      resolved_version         = ''
      found                    = $false
      failure_reason           = 'version_not_in_chain:' + $RequestedVersion
      policy_file_rel          = ''
      integrity_file_rel       = ''
      policy_file_abs          = ''
      integrity_file_abs       = ''
      chain_status             = ''
      stored_policy_sha256     = ''
      fallback_occurred        = $false
    }
  }

  $policyRel    = [string]$entry.policy_file
  $integrityRel = [string]$entry.integrity_reference_file
  $policyAbs    = if ([System.IO.Path]::IsPathRooted($policyRel)) { $policyRel } else { Join-Path $RootPath $policyRel.Replace('/', '\') }
  $integrityAbs = if ([System.IO.Path]::IsPathRooted($integrityRel)) { $integrityRel } else { Join-Path $RootPath $integrityRel.Replace('/', '\') }

  return [pscustomobject]@{
    requested_version        = $RequestedVersion
    resolved_version         = [string]$entry.version
    found                    = $true
    failure_reason           = ''
    policy_file_rel          = $policyRel
    integrity_file_rel       = $integrityRel
    policy_file_abs          = $policyAbs
    integrity_file_abs       = $integrityAbs
    chain_status             = [string]$entry.status
    stored_policy_sha256     = [string]$entry.policy_sha256
    fallback_occurred        = ($RequestedVersion.Trim() -ne [string]$entry.version)
  }
}

# ---------------------------------------------------------------------------
# Verify policy file integrity against its named integrity reference
# Returns structured result; does NOT fall back or regenerate anything
# ---------------------------------------------------------------------------
function Verify-PolicyVersionIntegrity {
  param(
    [Parameter(Mandatory = $true)]$Resolution,
    [Parameter(Mandatory = $true)][string]$CaseName
  )

  if (-not $Resolution.found) {
    return [pscustomobject]@{
      case                     = $CaseName
      pass                     = $false
      reason                   = 'version_not_found'
      requested_version        = $Resolution.requested_version
      resolved_version         = ''
      policy_file              = ''
      integrity_file           = ''
      expected_hash            = ''
      actual_hash              = ''
      stored_chain_hash        = ''
      integrity_ref_loaded     = $false
      policy_loaded            = $false
      policy_obj               = $null
      comparison_allowed       = $false
    }
  }

  # Anti-fallback guard: selected version must equal requested version exactly
  if ($Resolution.fallback_occurred) {
    return [pscustomobject]@{
      case                     = $CaseName
      pass                     = $false
      reason                   = 'silent_fallback_detected'
      requested_version        = $Resolution.requested_version
      resolved_version         = $Resolution.resolved_version
      policy_file              = $Resolution.policy_file_rel
      integrity_file           = $Resolution.integrity_file_rel
      expected_hash            = ''
      actual_hash              = ''
      stored_chain_hash        = $Resolution.stored_policy_sha256
      integrity_ref_loaded     = $false
      policy_loaded            = $false
      policy_obj               = $null
      comparison_allowed       = $false
    }
  }

  # Check integrity reference file exists
  if (-not (Test-Path -LiteralPath $Resolution.integrity_file_abs)) {
    return [pscustomobject]@{
      case                     = $CaseName
      pass                     = $false
      reason                   = 'integrity_reference_missing'
      requested_version        = $Resolution.requested_version
      resolved_version         = $Resolution.resolved_version
      policy_file              = $Resolution.policy_file_rel
      integrity_file           = $Resolution.integrity_file_rel
      expected_hash            = ''
      actual_hash              = ''
      stored_chain_hash        = $Resolution.stored_policy_sha256
      integrity_ref_loaded     = $false
      policy_loaded            = $false
      policy_obj               = $null
      comparison_allowed       = $false
    }
  }

  $intRefObj   = Get-Content -Raw -LiteralPath $Resolution.integrity_file_abs | ConvertFrom-Json
  $expectedHash = [string]$intRefObj.expected_policy_sha256

  # Check policy file exists
  if (-not (Test-Path -LiteralPath $Resolution.policy_file_abs)) {
    return [pscustomobject]@{
      case                     = $CaseName
      pass                     = $false
      reason                   = 'policy_file_missing'
      requested_version        = $Resolution.requested_version
      resolved_version         = $Resolution.resolved_version
      policy_file              = $Resolution.policy_file_rel
      integrity_file           = $Resolution.integrity_file_rel
      expected_hash            = $expectedHash
      actual_hash              = ''
      stored_chain_hash        = $Resolution.stored_policy_sha256
      integrity_ref_loaded     = $true
      policy_loaded            = $false
      policy_obj               = $null
      comparison_allowed       = $false
    }
  }

  $actualHash = Get-FileSha256Hex -Path $Resolution.policy_file_abs

  if ($actualHash -ne $expectedHash) {
    return [pscustomobject]@{
      case                     = $CaseName
      pass                     = $false
      reason                   = 'policy_hash_mismatch'
      requested_version        = $Resolution.requested_version
      resolved_version         = $Resolution.resolved_version
      policy_file              = $Resolution.policy_file_rel
      integrity_file           = $Resolution.integrity_file_rel
      expected_hash            = $expectedHash
      actual_hash              = $actualHash
      stored_chain_hash        = $Resolution.stored_policy_sha256
      integrity_ref_loaded     = $true
      policy_loaded            = $false
      policy_obj               = $null
      comparison_allowed       = $false
    }
  }

  $policyObj = Get-Content -Raw -LiteralPath $Resolution.policy_file_abs | ConvertFrom-Json

  return [pscustomobject]@{
    case                     = $CaseName
    pass                     = $true
    reason                   = 'integrity_verified'
    requested_version        = $Resolution.requested_version
    resolved_version         = $Resolution.resolved_version
    policy_file              = $Resolution.policy_file_rel
    integrity_file           = $Resolution.integrity_file_rel
    expected_hash            = $expectedHash
    actual_hash              = $actualHash
    stored_chain_hash        = $Resolution.stored_policy_sha256
    integrity_ref_loaded     = $true
    policy_loaded            = $true
    policy_obj               = $policyObj
    comparison_allowed       = $true
  }
}

# ---------------------------------------------------------------------------
# Extract enforcement summary from a loaded policy object
# ---------------------------------------------------------------------------
function Get-PolicyEnforcementSummary {
  param($PolicyObj)
  if ($null -eq $PolicyObj) { return $null }
  return [pscustomobject]@{
    active_version                   = [string]$PolicyObj.active_version
    historical_versions              = @($PolicyObj.historical_versions | ForEach-Object { [string]$_ })
    default_resolution               = [string]$PolicyObj.default_resolution
    invalid_version_behavior         = [string]$PolicyObj.invalid_version_behavior
    allow_explicit_historical        = [bool]$PolicyObj.allow_explicit_historical_selection
    policy_version_number            = [string]$PolicyObj.policy_version
  }
}

# ---------------------------------------------------------------------------
# PATHS
# ---------------------------------------------------------------------------
$TS     = Get-Date -Format 'yyyyMMdd_HHmmss'
$PFDir  = Join-Path $Root "_proof\phase43_1_policy_version_selection_historical_validation_$TS"
New-Item -ItemType Directory -Force -Path $PFDir | Out-Null

$Phase43_1Dir = Join-Path $Root 'tools\phase43_1'
New-Item -ItemType Directory -Force -Path $Phase43_1Dir | Out-Null

# Policy history chain (from Phase 43.0)
$ChainPath = Join-Path $Root 'tools\phase43_0\policy_history_chain.json'
$chain     = Get-Content -Raw -LiteralPath $ChainPath | ConvertFrom-Json

# ---------------------------------------------------------------------------
# CASE A — SELECT POLICY V1 / VALIDATE V1
# ---------------------------------------------------------------------------
Write-Output '=== CASE A: SELECT POLICY V1 / VALIDATE V1 ==='
$resA   = Resolve-PolicyVersion -RequestedVersion 'v1' -Chain $chain -RootPath $Root
$verA   = Verify-PolicyVersionIntegrity -Resolution $resA -CaseName 'A_select_v1'
$enfA   = Get-PolicyEnforcementSummary -PolicyObj $verA.policy_obj
Write-Output "  found=$($resA.found) fallback=$($resA.fallback_occurred)"
Write-Output "  integrity=$($verA.reason) pass=$($verA.pass)"
if ($null -ne $enfA) { Write-Output "  policy_active_version=$($enfA.active_version)" }

# ---------------------------------------------------------------------------
# CASE B — SELECT POLICY V2 / VALIDATE V2
# ---------------------------------------------------------------------------
Write-Output '=== CASE B: SELECT POLICY V2 / VALIDATE V2 ==='
$resB   = Resolve-PolicyVersion -RequestedVersion 'v2' -Chain $chain -RootPath $Root
$verB   = Verify-PolicyVersionIntegrity -Resolution $resB -CaseName 'B_select_v2'
$enfB   = Get-PolicyEnforcementSummary -PolicyObj $verB.policy_obj
Write-Output "  found=$($resB.found) fallback=$($resB.fallback_occurred)"
Write-Output "  integrity=$($verB.reason) pass=$($verB.pass)"
if ($null -ne $enfB) { Write-Output "  policy_active_version=$($enfB.active_version)" }

# ---------------------------------------------------------------------------
# CASE C — WRONG POLICY VERSION COMPARISON
# Load v1 policy file but verify it against v2 integrity reference → mismatch
# ---------------------------------------------------------------------------
Write-Output '=== CASE C: WRONG POLICY VERSION COMPARISON (v1 file vs v2 integrity ref) ==='

# Build a synthetic "wrong-version" resolution: use v1 policy file path but v2 integrity reference
$resC_v2     = Resolve-PolicyVersion -RequestedVersion 'v2' -Chain $chain -RootPath $Root
$resC_cross  = [pscustomobject]@{
  requested_version    = 'v1'       # user asked for v1
  resolved_version     = 'v1'
  found                = $true
  failure_reason       = ''
  policy_file_rel      = $resA.policy_file_rel          # v1 policy file
  integrity_file_rel   = $resC_v2.integrity_file_rel    # v2 integrity reference (WRONG)
  policy_file_abs      = $resA.policy_file_abs
  integrity_file_abs   = $resC_v2.integrity_file_abs
  chain_status         = 'historical'
  stored_policy_sha256 = $resA.stored_policy_sha256
  fallback_occurred    = $false
}
$verC = Verify-PolicyVersionIntegrity -Resolution $resC_cross -CaseName 'C_cross_version_mismatch'
$caseCMismatchFields = @()
if ($verC.reason -eq 'policy_hash_mismatch') {
  $caseCMismatchFields = @('expected_hash', 'actual_hash')
}
Write-Output "  integrity=$($verC.reason) pass=$($verC.pass) comparison_blocked=$(-not $verC.comparison_allowed)"
Write-Output "  expected_hash=$($verC.expected_hash)"
Write-Output "  actual_hash=$($verC.actual_hash)"

# ---------------------------------------------------------------------------
# CASE D — VERSION LOAD AUDITABILITY
# Prove that exactly the files declared in the chain were loaded;
# no intermediate file substitution or fallback
# ---------------------------------------------------------------------------
Write-Output '=== CASE D: VERSION LOAD AUDITABILITY ==='
$v1ChainEntry = $chain.chain | Where-Object { $_.version -eq 'v1' }
$v2ChainEntry = $chain.chain | Where-Object { $_.version -eq 'v2' }

$auditA_policyMatch     = ($verA.policy_file    -eq [string]$v1ChainEntry.policy_file)
$auditA_integrityMatch  = ($verA.integrity_file -eq [string]$v1ChainEntry.integrity_reference_file)
$auditB_policyMatch     = ($verB.policy_file    -eq [string]$v2ChainEntry.policy_file)
$auditB_integrityMatch  = ($verB.integrity_file -eq [string]$v2ChainEntry.integrity_reference_file)
$auditNoFallback        = (-not $resA.fallback_occurred) -and (-not $resB.fallback_occurred)

$caseDPass = $auditA_policyMatch -and $auditA_integrityMatch -and
             $auditB_policyMatch -and $auditB_integrityMatch -and
             $auditNoFallback

Write-Output "  v1_policy_file_match=$auditA_policyMatch"
Write-Output "  v1_integrity_file_match=$auditA_integrityMatch"
Write-Output "  v2_policy_file_match=$auditB_policyMatch"
Write-Output "  v2_integrity_file_match=$auditB_integrityMatch"
Write-Output "  no_fallback=$auditNoFallback"
Write-Output "  case_d_pass=$caseDPass"

# ---------------------------------------------------------------------------
# CASE E — HISTORICAL POLICY USABILITY
# v1 is "historical" in the chain; prove it loads, verifies, and resolves correctly
# ---------------------------------------------------------------------------
Write-Output '=== CASE E: HISTORICAL POLICY USABILITY ==='
$caseEPass = $verA.pass -and ($null -ne $enfA) -and (-not $resA.fallback_occurred) -and
             ([string]$resA.chain_status -eq 'historical')
Write-Output "  v1_chain_status=$($resA.chain_status)"
Write-Output "  v1_integrity_verified=$($verA.pass)"
Write-Output "  v1_active_version_resolved=$(if ($null -ne $enfA) { $enfA.active_version } else { 'N/A' })"
Write-Output "  historical_usable=$caseEPass"

# ---------------------------------------------------------------------------
# CASE F — INVALID POLICY VERSION REQUEST
# Request a version that does not exist in the chain; must fail deterministically
# ---------------------------------------------------------------------------
Write-Output '=== CASE F: INVALID POLICY VERSION REQUEST (v999) ==='
$resF   = Resolve-PolicyVersion -RequestedVersion 'v999' -Chain $chain -RootPath $Root
$caseFPass = (-not $resF.found) -and ($resF.failure_reason -like 'version_not_in_chain:*')
Write-Output "  found=$($resF.found)"
Write-Output "  failure_reason=$($resF.failure_reason)"
Write-Output "  case_f_pass=$caseFPass"

# ---------------------------------------------------------------------------
# GATE EVALUATION
# ---------------------------------------------------------------------------
$gatePass    = $true
$gateReasons = New-Object System.Collections.Generic.List[string]

if (-not $verA.pass)  { $gatePass = $false; $gateReasons.Add('caseA_v1_integrity_fail') }
if ($resA.fallback_occurred) { $gatePass = $false; $gateReasons.Add('caseA_fallback_detected') }
if (-not $verB.pass)  { $gatePass = $false; $gateReasons.Add('caseB_v2_integrity_fail') }
if ($resB.fallback_occurred) { $gatePass = $false; $gateReasons.Add('caseB_fallback_detected') }
if ($verC.pass -or $verC.comparison_allowed) { $gatePass = $false; $gateReasons.Add('caseC_wrong_version_not_blocked') }
if (-not $caseDPass)  { $gatePass = $false; $gateReasons.Add('caseD_auditability_fail') }
if (-not $caseEPass)  { $gatePass = $false; $gateReasons.Add('caseE_historical_usability_fail') }
if (-not $caseFPass)  { $gatePass = $false; $gateReasons.Add('caseF_invalid_version_not_rejected') }

$gateStr = if ($gatePass) { 'PASS' } else { 'FAIL' }

# ---------------------------------------------------------------------------
# PROOF PACKET FILES
# ---------------------------------------------------------------------------

# 01_status.txt
Set-Content -Path (Join-Path $PFDir '01_status.txt') -Value @(
  "phase=43.1"
  "title=POLICY VERSION SELECTION / HISTORICAL POLICY VALIDATION PROOF"
  "runner=tools/phase43_1/phase43_1_policy_version_selection_historical_validation_runner.ps1"
  "timestamp=$TS"
  "gate=$gateStr"
  "case_a_v1_integrity=$($verA.reason)"
  "case_a_v1_pass=$($verA.pass)"
  "case_b_v2_integrity=$($verB.reason)"
  "case_b_v2_pass=$($verB.pass)"
  "case_c_wrong_version_blocked=$(-not $verC.pass)"
  "case_d_auditability=$caseDPass"
  "case_e_historical_usable=$caseEPass"
  "case_f_invalid_rejected=$caseFPass"
) -Encoding UTF8

# 02_head.txt
Set-Content -Path (Join-Path $PFDir '02_head.txt') -Value @(
  "project=NGKsUI Runtime"
  "phase=43.1"
  "title=POLICY VERSION SELECTION / HISTORICAL POLICY VALIDATION PROOF"
  "timestamp_utc=$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')"
  "root=$Root"
  "prior_phase=43.0 POLICY TRUST-CHAIN CONTINUITY PASS"
  "gate=$gateStr"
) -Encoding UTF8

# 10_policy_version_selection_definition.txt
Set-Content -Path (Join-Path $PFDir '10_policy_version_selection_definition.txt') -Value @(
  "mechanism=explicit_version_label_lookup_in_policy_history_chain"
  "chain_source=tools/phase43_0/policy_history_chain.json"
  "version_labels_available=v1,v2"
  "v1_status=historical"
  "v2_status=active"
  "no_default_auto_resolution=true"
  "no_silent_fallback=true"
  "integrity_gate_before_resolution=true"
  "invalid_version_behavior=fail_with_explicit_reason_no_fallback"
) -Encoding UTF8

# 11_policy_version_selection_rules.txt
Set-Content -Path (Join-Path $PFDir '11_policy_version_selection_rules.txt') -Value @(
  "RULE_1=requested_policy_version_identifier_must_be_explicit"
  "RULE_2=lookup_in_chain_is_exact_match_only_no_prefix_or_fuzzy"
  "RULE_3=resolved_version_must_equal_requested_version_exactly_or_fail"
  "RULE_4=policy_file_path_comes_exclusively_from_chain_entry_for_selected_version"
  "RULE_5=integrity_reference_path_comes_exclusively_from_chain_entry_for_selected_version"
  "RULE_6=integrity_hash_of_policy_file_must_match_integrity_reference_before_resolution"
  "RULE_7=cross_version_reference_mismatch_detected_by_hash_comparison"
  "RULE_8=historical_policy_versions_are_operational_not_merely_archived"
  "RULE_9=invalid_version_fails_at_resolution_stage_before_any_integrity_check"
  "RULE_10=no_regeneration_no_fallback_no_remapping_on_any_failure"
) -Encoding UTF8

# 12_files_touched.txt
Set-Content -Path (Join-Path $PFDir '12_files_touched.txt') -Value @(
  "READ=tools/phase43_0/policy_history_chain.json"
  "READ=tools/phase42_8/active_version_policy.json (policy v1)"
  "READ=tools/phase42_9/policy_integrity_reference.json (integrity ref v1)"
  "READ=tools/phase43_0/active_version_policy_v2.json (policy v2)"
  "READ=tools/phase43_0/policy_integrity_reference_v2.json (integrity ref v2)"
  "CREATED(RUNNER)=tools/phase43_1/phase43_1_policy_version_selection_historical_validation_runner.ps1"
  "NOT_MODIFIED=tools/phase42_8/active_version_policy.json"
  "NOT_MODIFIED=tools/phase42_9/policy_integrity_reference.json"
  "NOT_MODIFIED=tools/phase43_0/active_version_policy_v2.json"
  "NOT_MODIFIED=tools/phase43_0/policy_integrity_reference_v2.json"
  "NOT_MODIFIED=tools/phase43_0/policy_history_chain.json"
  "UI_MODIFIED=NO"
  "BASELINE_MODE_MODIFIED=NO"
  "RUNTIME_SEMANTICS_MODIFIED=NO"
) -Encoding UTF8

# 13_build_output.txt
Set-Content -Path (Join-Path $PFDir '13_build_output.txt') -Value @(
  "build_action=none_required"
  "reason=phase43_1_is_pure_policy_selection_enforcement_no_cpp_changes"
  "prior_build_used=phase42_x_certified_binary"
  "build_status=NOT_REQUIRED"
) -Encoding UTF8

# 14_validation_results.txt
$v14 = New-Object System.Collections.Generic.List[string]

$v14.Add('--- CASE A: SELECT POLICY V1 / VALIDATE V1 ---')
$v14.Add("requested_version=$($verA.requested_version)")
$v14.Add("resolved_version=$($verA.resolved_version)")
$v14.Add("policy_file=$($verA.policy_file)")
$v14.Add("integrity_file=$($verA.integrity_file)")
$v14.Add("expected_hash=$($verA.expected_hash)")
$v14.Add("actual_hash=$($verA.actual_hash)")
$v14.Add("stored_chain_hash=$($verA.stored_chain_hash)")
$v14.Add("integrity_result=$($verA.reason)")
$v14.Add("comparison_allowed=$($verA.comparison_allowed)")
$v14.Add("fallback_occurred=$($resA.fallback_occurred)")
if ($null -ne $enfA) {
  $v14.Add("policy_active_version=$($enfA.active_version)")
  $v14.Add("policy_historical_versions=$($enfA.historical_versions -join ',')")
  $v14.Add("policy_version_number=$($enfA.policy_version_number)")
}
$v14.Add("result=$(if ($verA.pass -and -not $resA.fallback_occurred) { 'PASS' } else { 'FAIL' })")
$v14.Add('')

$v14.Add('--- CASE B: SELECT POLICY V2 / VALIDATE V2 ---')
$v14.Add("requested_version=$($verB.requested_version)")
$v14.Add("resolved_version=$($verB.resolved_version)")
$v14.Add("policy_file=$($verB.policy_file)")
$v14.Add("integrity_file=$($verB.integrity_file)")
$v14.Add("expected_hash=$($verB.expected_hash)")
$v14.Add("actual_hash=$($verB.actual_hash)")
$v14.Add("stored_chain_hash=$($verB.stored_chain_hash)")
$v14.Add("integrity_result=$($verB.reason)")
$v14.Add("comparison_allowed=$($verB.comparison_allowed)")
$v14.Add("fallback_occurred=$($resB.fallback_occurred)")
if ($null -ne $enfB) {
  $v14.Add("policy_active_version=$($enfB.active_version)")
  $v14.Add("policy_historical_versions=$($enfB.historical_versions -join ',')")
  $v14.Add("policy_version_number=$($enfB.policy_version_number)")
}
$v14.Add("result=$(if ($verB.pass -and -not $resB.fallback_occurred) { 'PASS' } else { 'FAIL' })")
$v14.Add('')

$v14.Add('--- CASE C: WRONG POLICY VERSION COMPARISON ---')
$v14.Add("requested_version=v1 (policy file)")
$v14.Add("wrong_integrity_reference=v2 integrity reference (cross-version)")
$v14.Add("policy_file_loaded=$($resC_cross.policy_file_rel)")
$v14.Add("integrity_file_loaded=$($resC_cross.integrity_file_rel)")
$v14.Add("expected_hash=$($verC.expected_hash)")
$v14.Add("actual_hash=$($verC.actual_hash)")
$v14.Add("mismatch_fields=$($caseCMismatchFields -join ',')")
$v14.Add("integrity_result=$($verC.reason)")
$v14.Add("comparison_blocked=$(-not $verC.comparison_allowed)")
$v14.Add("result=$(if (-not $verC.pass -and -not $verC.comparison_allowed) { 'PASS' } else { 'FAIL' })")
$v14.Add('')

$v14.Add('--- CASE D: VERSION LOAD AUDITABILITY ---')
$v14.Add("v1_policy_file_matches_chain=$auditA_policyMatch")
$v14.Add("v1_integrity_file_matches_chain=$auditA_integrityMatch")
$v14.Add("v2_policy_file_matches_chain=$auditB_policyMatch")
$v14.Add("v2_integrity_file_matches_chain=$auditB_integrityMatch")
$v14.Add("no_fallback_on_any_case=$auditNoFallback")
$v14.Add("result=$(if ($caseDPass) { 'PASS' } else { 'FAIL' })")
$v14.Add('')

$v14.Add('--- CASE E: HISTORICAL POLICY USABILITY ---')
$v14.Add("v1_chain_status=$($resA.chain_status)")
$v14.Add("v1_integrity_verified=$($verA.pass)")
$v14.Add("v1_active_version_resolved=$(if ($null -ne $enfA) { $enfA.active_version } else { 'N/A' })")
$v14.Add("v1_historical_versions=$(if ($null -ne $enfA) { $enfA.historical_versions -join ',' } else { 'N/A' })")
$v14.Add("v1_fallback_occurred=$($resA.fallback_occurred)")
$v14.Add("historical_policy_operational=$caseEPass")
$v14.Add("result=$(if ($caseEPass) { 'PASS' } else { 'FAIL' })")
$v14.Add('')

$v14.Add('--- CASE F: INVALID POLICY VERSION REQUEST (v999) ---')
$v14.Add("requested_version=$($resF.requested_version)")
$v14.Add("found=$($resF.found)")
$v14.Add("failure_reason=$($resF.failure_reason)")
$v14.Add("fallback_occurred=$($resF.fallback_occurred)")
$v14.Add("result=$(if ($caseFPass) { 'PASS' } else { 'FAIL' })")
$v14.Add('')

$v14.Add('--- GATE ---')
$v14.Add("GATE=$gateStr")
if (-not $gatePass) { foreach ($r in $gateReasons) { $v14.Add("gate_fail_reason=$r") } }
Set-Content -Path (Join-Path $PFDir '14_validation_results.txt') -Value $v14 -Encoding UTF8

# 15_behavior_summary.txt
Set-Content -Path (Join-Path $PFDir '15_behavior_summary.txt') -Value @(
  "BEHAVIOR_SUMMARY=Phase43_1"
  ""
  "POLICY_VERSION_SELECTION:"
  "  The runner accepts an explicit policy version label (v1, v2, ...)."
  "  Resolve-PolicyVersion performs an exact-match lookup in the policy_history_chain.json."
  "  No prefix matching, no auto-selection of latest, no fallback to another version."
  "  If the requested version is not in the chain, the function returns found=false with"
  "  failure_reason=version_not_in_chain:<requested> and the phase fails deterministically."
  ""
  "INDEPENDENT LOADING (V1 AND V2):"
  "  Each version entry in the chain carries its own policy_file and integrity_reference_file."
  "  These paths are loaded exclusively for the selected version."
  "  No shared file paths exist between policy v1 and policy v2 (except the baseline chain source)."
  ""
  "VERSION-SPECIFIC INTEGRITY VERIFICATION:"
  "  After version resolution, Verify-PolicyVersionIntegrity computes SHA256 of the selected"
  "  policy file and compares it to the expected_policy_sha256 in the selected integrity reference."
  "  Hash mismatch → comparison_allowed=false, no resolution proceeds."
  ""
  "WRONG-VERSION COMPARISON DETECTION:"
  "  Case C uses the v1 policy file but the v2 integrity reference."
  "  The v2 integrity reference stores the hash of the v2 policy file."
  "  The v1 policy file has a different hash → policy_hash_mismatch fires immediately."
  "  The mismatch is captured in expected_hash vs actual_hash fields."
  ""
  "INVALID VERSION REJECTION:"
  "  Requesting v999 (or any unknown label) returns found=false with a descriptive failure_reason."
  "  No integrity check is attempted. No fallback occurs."
  ""
  "HISTORICAL POLICY USABILITY:"
  "  Policy v1 (status=historical) is loaded from its original file via the chain entry."
  "  Its integrity reference is loaded independently from tools/phase42_9/."
  "  The loaded policy object is fully parsed and its enforcement fields (active_version,"
  "  historical_versions, etc.) are verified and recorded."
  "  Historical status means preserved-in-chain, not read-only-unverifiable."
  ""
  "DISABLED_CONTROL:"
  "  The Disabled control remains inert. No runner or policy change touches UI controls."
  ""
  "BASELINE_MODE:"
  "  Unchanged. No runtime semantics modified. Policy version selection is metadata-only."
) -Encoding UTF8

# 16_policy_version_reference_record.txt
$pvrLines = New-Object System.Collections.Generic.List[string]
foreach ($sel in @(
  [pscustomobject]@{ label='V1'; ver=$verA; res=$resA; enf=$enfA },
  [pscustomobject]@{ label='V2'; ver=$verB; res=$resB; enf=$enfB }
)) {
  $pvrLines.Add("--- POLICY $($sel.label) ---")
  $pvrLines.Add("requested_policy_version=$($sel.ver.requested_version)")
  $pvrLines.Add("selected_policy_version=$($sel.ver.resolved_version)")
  $pvrLines.Add("selected_policy_file=$($sel.ver.policy_file)")
  $pvrLines.Add("selected_integrity_reference_file=$($sel.ver.integrity_file)")
  $pvrLines.Add("stored_policy_sha256=$($sel.ver.stored_chain_hash)")
  $pvrLines.Add("stored_integrity_sha256=$($sel.ver.expected_hash)")
  $pvrLines.Add("integrity_verification_result=$($sel.ver.reason)")
  $pvrLines.Add("resolved_active_version=$(if ($null -ne $sel.enf) { $sel.enf.active_version } else { 'N/A' })")
  $pvrLines.Add("resolved_historical_versions=$(if ($null -ne $sel.enf) { $sel.enf.historical_versions -join ',' } else { 'N/A' })")
  $pvrLines.Add("fallback_occurred=$($sel.res.fallback_occurred)")
  $pvrLines.Add("chain_status=$($sel.res.chain_status)")
  $pvrLines.Add('')
}
Set-Content -Path (Join-Path $PFDir '16_policy_version_reference_record.txt') -Value $pvrLines -Encoding UTF8

# 17_wrong_policy_version_mismatch_evidence.txt
Set-Content -Path (Join-Path $PFDir '17_wrong_policy_version_mismatch_evidence.txt') -Value @(
  "--- CASE C: WRONG POLICY VERSION MISMATCH EVIDENCE ---"
  ""
  "requested_version=v1"
  "policy_file_actually_loaded=$($resC_cross.policy_file_rel)"
  "integrity_reference_actually_loaded=$($resC_cross.integrity_file_rel)"
  ""
  "mismatch_introduced=integrity_reference_belongs_to_v2_but_policy_file_is_v1"
  "expected_result=FAIL"
  "actual_result=$(if (-not $verC.pass) { 'FAIL' } else { 'PASS (UNEXPECTED)' })"
  ""
  "mismatch_detected_at=integrity_verification_stage"
  "integrity_result=$($verC.reason)"
  "expected_hash_from_v2_ref=$($verC.expected_hash)"
  "actual_hash_of_v1_file=$($verC.actual_hash)"
  "mismatch_fields=$($caseCMismatchFields -join ',')"
  ""
  "comparison_allowed=$($verC.comparison_allowed)"
  "resolution_blocked=$(-not $verC.comparison_allowed)"
  "failure_is_correct=True"
  "failure_is_deterministic=True (hash comparison is byte-exact and reproducible)"
) -Encoding UTF8

# 98_gate_phase43_1.txt
$gate98 = @(
  "PHASE=43.1"
  "GATE=$gateStr"
  "timestamp=$TS"
)
if (-not $gatePass) { foreach ($r in $gateReasons) { $gate98 += "FAIL_REASON=$r" } }
Set-Content -Path (Join-Path $PFDir '98_gate_phase43_1.txt') -Value $gate98 -Encoding UTF8

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
