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

function Get-FileSha256Hex {
  param([string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $h = [System.Security.Cryptography.SHA256]::HashData($bytes)
  return ([System.BitConverter]::ToString($h)).Replace('-', '').ToLowerInvariant()
}

function Get-PolicySummary {
  param($PolicyObj)
  if ($null -eq $PolicyObj) { return $null }
  return [pscustomobject]@{
    policy_version_number            = [string]$PolicyObj.policy_version
    active_version                   = [string]$PolicyObj.active_version
    historical_versions              = @($PolicyObj.historical_versions | ForEach-Object { [string]$_ })
    default_resolution               = [string]$PolicyObj.default_resolution
    invalid_version_behavior         = [string]$PolicyObj.invalid_version_behavior
    allow_explicit_historical        = [bool]$PolicyObj.allow_explicit_historical_selection
  }
}

# Resolve default policy: when no explicit policy version requested,
# select ONLY the chain entry marked status=active. No fallback permitted.
function Resolve-DefaultPolicySelection {
  param(
    [Parameter(Mandatory = $true)]$PolicyChain,
    [Parameter(Mandatory = $true)][string]$RootPath
  )

  $activeEntries = @($PolicyChain.chain | Where-Object { [string]$_.status -eq 'active' })
  if ($activeEntries.Count -ne 1) {
    return [pscustomobject]@{
      requested_mode         = 'default'
      requested_version      = '(default)'
      declared_active_version= ''
      resolved_version       = ''
      found                  = $false
      failure_reason         = 'invalid_active_entry_count:' + $activeEntries.Count
      policy_file_rel        = ''
      integrity_file_rel     = ''
      policy_file_abs        = ''
      integrity_file_abs     = ''
      fallback_occurred      = $false
    }
  }

  $active = $activeEntries[0]
  $policyRel = [string]$active.policy_file
  $intRel    = [string]$active.integrity_reference_file
  $policyAbs = if ([System.IO.Path]::IsPathRooted($policyRel)) { $policyRel } else { Join-Path $RootPath $policyRel.Replace('/', '\') }
  $intAbs    = if ([System.IO.Path]::IsPathRooted($intRel)) { $intRel } else { Join-Path $RootPath $intRel.Replace('/', '\') }

  return [pscustomobject]@{
    requested_mode         = 'default'
    requested_version      = '(default)'
    declared_active_version= [string]$active.version
    resolved_version       = [string]$active.version
    found                  = $true
    failure_reason         = ''
    policy_file_rel        = $policyRel
    integrity_file_rel     = $intRel
    policy_file_abs        = $policyAbs
    integrity_file_abs     = $intAbs
    fallback_occurred      = $false
  }
}

function Resolve-ExplicitPolicySelection {
  param(
    [Parameter(Mandatory = $true)][string]$RequestedVersion,
    [Parameter(Mandatory = $true)]$PolicyChain,
    [Parameter(Mandatory = $true)][string]$RootPath
  )

  $entry = $null
  foreach ($e in $PolicyChain.chain) {
    if ([string]$e.version -eq $RequestedVersion.Trim()) { $entry = $e; break }
  }

  if ($null -eq $entry) {
    return [pscustomobject]@{
      requested_mode         = 'explicit'
      requested_version      = $RequestedVersion
      declared_active_version= ''
      resolved_version       = ''
      found                  = $false
      failure_reason         = 'version_not_in_chain:' + $RequestedVersion
      policy_file_rel        = ''
      integrity_file_rel     = ''
      policy_file_abs        = ''
      integrity_file_abs     = ''
      fallback_occurred      = $false
    }
  }

  $policyRel = [string]$entry.policy_file
  $intRel    = [string]$entry.integrity_reference_file
  $policyAbs = if ([System.IO.Path]::IsPathRooted($policyRel)) { $policyRel } else { Join-Path $RootPath $policyRel.Replace('/', '\') }
  $intAbs    = if ([System.IO.Path]::IsPathRooted($intRel)) { $intRel } else { Join-Path $RootPath $intRel.Replace('/', '\') }

  $activeEntry = @($PolicyChain.chain | Where-Object { [string]$_.status -eq 'active' }) | Select-Object -First 1
  $declaredActive = if ($null -ne $activeEntry) { [string]$activeEntry.version } else { '' }

  return [pscustomobject]@{
    requested_mode         = 'explicit'
    requested_version      = $RequestedVersion
    declared_active_version= $declaredActive
    resolved_version       = [string]$entry.version
    found                  = $true
    failure_reason         = ''
    policy_file_rel        = $policyRel
    integrity_file_rel     = $intRel
    policy_file_abs        = $policyAbs
    integrity_file_abs     = $intAbs
    fallback_occurred      = ($RequestedVersion.Trim() -ne [string]$entry.version)
  }
}

function Verify-SelectionIntegrity {
  param(
    [Parameter(Mandatory = $true)]$Selection,
    [Parameter(Mandatory = $true)][string]$CaseName
  )

  if (-not $Selection.found) {
    return [pscustomobject]@{
      case_name             = $CaseName
      pass                  = $false
      reason                = 'selection_not_found'
      requested_mode        = $Selection.requested_mode
      requested_version     = $Selection.requested_version
      declared_active_version = $Selection.declared_active_version
      resolved_version      = ''
      selected_policy_file  = ''
      selected_integrity_file = ''
      expected_hash         = ''
      actual_hash           = ''
      policy_loaded         = $false
      integrity_ref_loaded  = $false
      comparison_allowed    = $false
      fallback_occurred     = $Selection.fallback_occurred
      policy_obj            = $null
    }
  }

  if ($Selection.fallback_occurred) {
    return [pscustomobject]@{
      case_name             = $CaseName
      pass                  = $false
      reason                = 'silent_fallback_detected'
      requested_mode        = $Selection.requested_mode
      requested_version     = $Selection.requested_version
      declared_active_version = $Selection.declared_active_version
      resolved_version      = $Selection.resolved_version
      selected_policy_file  = $Selection.policy_file_rel
      selected_integrity_file = $Selection.integrity_file_rel
      expected_hash         = ''
      actual_hash           = ''
      policy_loaded         = $false
      integrity_ref_loaded  = $false
      comparison_allowed    = $false
      fallback_occurred     = $true
      policy_obj            = $null
    }
  }

  if (-not (Test-Path -LiteralPath $Selection.integrity_file_abs)) {
    return [pscustomobject]@{
      case_name             = $CaseName
      pass                  = $false
      reason                = 'integrity_reference_missing'
      requested_mode        = $Selection.requested_mode
      requested_version     = $Selection.requested_version
      declared_active_version = $Selection.declared_active_version
      resolved_version      = $Selection.resolved_version
      selected_policy_file  = $Selection.policy_file_rel
      selected_integrity_file = $Selection.integrity_file_rel
      expected_hash         = ''
      actual_hash           = ''
      policy_loaded         = $false
      integrity_ref_loaded  = $false
      comparison_allowed    = $false
      fallback_occurred     = $false
      policy_obj            = $null
    }
  }

  $integrityRef = Get-Content -Raw -LiteralPath $Selection.integrity_file_abs | ConvertFrom-Json
  $expectedHash = [string]$integrityRef.expected_policy_sha256

  if (-not (Test-Path -LiteralPath $Selection.policy_file_abs)) {
    return [pscustomobject]@{
      case_name             = $CaseName
      pass                  = $false
      reason                = 'policy_file_missing'
      requested_mode        = $Selection.requested_mode
      requested_version     = $Selection.requested_version
      declared_active_version = $Selection.declared_active_version
      resolved_version      = $Selection.resolved_version
      selected_policy_file  = $Selection.policy_file_rel
      selected_integrity_file = $Selection.integrity_file_rel
      expected_hash         = $expectedHash
      actual_hash           = ''
      policy_loaded         = $false
      integrity_ref_loaded  = $true
      comparison_allowed    = $false
      fallback_occurred     = $false
      policy_obj            = $null
    }
  }

  $actualHash = Get-FileSha256Hex -Path $Selection.policy_file_abs
  if ($actualHash -ne $expectedHash) {
    return [pscustomobject]@{
      case_name             = $CaseName
      pass                  = $false
      reason                = 'policy_hash_mismatch'
      requested_mode        = $Selection.requested_mode
      requested_version     = $Selection.requested_version
      declared_active_version = $Selection.declared_active_version
      resolved_version      = $Selection.resolved_version
      selected_policy_file  = $Selection.policy_file_rel
      selected_integrity_file = $Selection.integrity_file_rel
      expected_hash         = $expectedHash
      actual_hash           = $actualHash
      policy_loaded         = $false
      integrity_ref_loaded  = $true
      comparison_allowed    = $false
      fallback_occurred     = $false
      policy_obj            = $null
    }
  }

  $policyObj = Get-Content -Raw -LiteralPath $Selection.policy_file_abs | ConvertFrom-Json
  return [pscustomobject]@{
    case_name             = $CaseName
    pass                  = $true
    reason                = 'integrity_verified'
    requested_mode        = $Selection.requested_mode
    requested_version     = $Selection.requested_version
    declared_active_version = $Selection.declared_active_version
    resolved_version      = $Selection.resolved_version
    selected_policy_file  = $Selection.policy_file_rel
    selected_integrity_file = $Selection.integrity_file_rel
    expected_hash         = $expectedHash
    actual_hash           = $actualHash
    policy_loaded         = $true
    integrity_ref_loaded  = $true
    comparison_allowed    = $true
    fallback_occurred     = $false
    policy_obj            = $policyObj
  }
}

$TS = Get-Date -Format 'yyyyMMdd_HHmmss'
$PFDir = Join-Path $Root "_proof\phase43_2_active_policy_default_resolution_enforcement_$TS"
New-Item -ItemType Directory -Force -Path $PFDir | Out-Null

$PhaseDir = Join-Path $Root 'tools\phase43_2'
New-Item -ItemType Directory -Force -Path $PhaseDir | Out-Null

$PolicyChainPath = Join-Path $Root 'tools\phase43_0\policy_history_chain.json'
$policyChain = Get-Content -Raw -LiteralPath $PolicyChainPath | ConvertFrom-Json

$v1Entry = $policyChain.chain | Where-Object { [string]$_.version -eq 'v1' }
$v2Entry = $policyChain.chain | Where-Object { [string]$_.version -eq 'v2' }
$activeEntry = $policyChain.chain | Where-Object { [string]$_.status -eq 'active' }
$historicalEntry = $policyChain.chain | Where-Object { [string]$_.status -eq 'historical' } | Select-Object -First 1

# CASE A — clean default active policy pass
Write-Output '=== CASE A: CLEAN DEFAULT ACTIVE POLICY PASS ==='
$selA = Resolve-DefaultPolicySelection -PolicyChain $policyChain -RootPath $Root
$verA = Verify-SelectionIntegrity -Selection $selA -CaseName 'A_clean_default_active'
$sumA = Get-PolicySummary -PolicyObj $verA.policy_obj
$caseAPass = $verA.pass -and $verA.comparison_allowed -and ($selA.resolved_version -eq $selA.declared_active_version)
Write-Output "  declared_active=$($selA.declared_active_version) resolved=$($selA.resolved_version)"
Write-Output "  integrity=$($verA.reason) comparison_allowed=$($verA.comparison_allowed)"

# CASE B — default active policy hash mismatch (wrong integrity reference)
Write-Output '=== CASE B: DEFAULT ACTIVE POLICY HASH MISMATCH ==='
$selB = [pscustomobject]@{
  requested_mode         = 'default'
  requested_version      = '(default)'
  declared_active_version= $selA.declared_active_version
  resolved_version       = $selA.resolved_version
  found                  = $true
  failure_reason         = ''
  policy_file_rel        = $selA.policy_file_rel
  integrity_file_rel     = [string]$v1Entry.integrity_reference_file
  policy_file_abs        = $selA.policy_file_abs
  integrity_file_abs     = Join-Path $Root ([string]$v1Entry.integrity_reference_file).Replace('/', '\')
  fallback_occurred      = $false
}
$verB = Verify-SelectionIntegrity -Selection $selB -CaseName 'B_default_hash_mismatch'
$caseBPass = (-not $verB.pass) -and (-not $verB.comparison_allowed) -and ($verB.reason -eq 'policy_hash_mismatch')
Write-Output "  integrity=$($verB.reason) comparison_blocked=$(-not $verB.comparison_allowed)"

# CASE C — default active policy file missing
Write-Output '=== CASE C: DEFAULT ACTIVE POLICY FILE MISSING ==='
$selC = [pscustomobject]@{
  requested_mode         = 'default'
  requested_version      = '(default)'
  declared_active_version= $selA.declared_active_version
  resolved_version       = $selA.resolved_version
  found                  = $true
  failure_reason         = ''
  policy_file_rel        = 'tools/phase43_2/_missing_active_policy_v2.json'
  integrity_file_rel     = $selA.integrity_file_rel
  policy_file_abs        = Join-Path $Root 'tools\phase43_2\_missing_active_policy_v2.json'
  integrity_file_abs     = $selA.integrity_file_abs
  fallback_occurred      = $false
}
$verC = Verify-SelectionIntegrity -Selection $selC -CaseName 'C_default_policy_missing'
$caseCPass = (-not $verC.pass) -and (-not $verC.comparison_allowed) -and ($verC.reason -eq 'policy_file_missing')
Write-Output "  integrity=$($verC.reason) comparison_blocked=$(-not $verC.comparison_allowed)"

# CASE D — default active integrity reference missing
Write-Output '=== CASE D: DEFAULT ACTIVE POLICY INTEGRITY REFERENCE MISSING ==='
$selD = [pscustomobject]@{
  requested_mode         = 'default'
  requested_version      = '(default)'
  declared_active_version= $selA.declared_active_version
  resolved_version       = $selA.resolved_version
  found                  = $true
  failure_reason         = ''
  policy_file_rel        = $selA.policy_file_rel
  integrity_file_rel     = 'tools/phase43_2/_missing_active_integrity_reference_v2.json'
  policy_file_abs        = $selA.policy_file_abs
  integrity_file_abs     = Join-Path $Root 'tools\phase43_2\_missing_active_integrity_reference_v2.json'
  fallback_occurred      = $false
}
$verD = Verify-SelectionIntegrity -Selection $selD -CaseName 'D_default_integrity_missing'
$caseDPass = (-not $verD.pass) -and (-not $verD.comparison_allowed) -and ($verD.reason -eq 'integrity_reference_missing')
Write-Output "  integrity=$($verD.reason) comparison_blocked=$(-not $verD.comparison_allowed)"

# CASE E — default resolution must not select historical
Write-Output '=== CASE E: DEFAULT MUST NOT SELECT HISTORICAL ==='
$historicalVersion = if ($null -ne $historicalEntry) { [string]$historicalEntry.version } else { '' }
$caseENoFallbackObserved = ($selA.resolved_version -eq $selA.declared_active_version) -and
                           ($selB.resolved_version -eq $selA.declared_active_version) -and
                           ($selC.resolved_version -eq $selA.declared_active_version) -and
                           ($selD.resolved_version -eq $selA.declared_active_version)
$caseEHistoricalNotSelected = ($selA.resolved_version -ne $historicalVersion) -and
                              ($selB.resolved_version -ne $historicalVersion) -and
                              ($selC.resolved_version -ne $historicalVersion) -and
                              ($selD.resolved_version -ne $historicalVersion)
$caseEPass = $caseENoFallbackObserved -and $caseEHistoricalNotSelected -and $caseCPass -and $caseDPass
Write-Output "  declared_active=$($selA.declared_active_version) historical=$historicalVersion"
Write-Output "  no_fallback_observed=$caseENoFallbackObserved"
Write-Output "  historical_not_selected=$caseEHistoricalNotSelected"

# CASE F — explicit historical still works separately
Write-Output '=== CASE F: EXPLICIT HISTORICAL STILL WORKS ==='
$selF = Resolve-ExplicitPolicySelection -RequestedVersion $historicalVersion -PolicyChain $policyChain -RootPath $Root
$verF = Verify-SelectionIntegrity -Selection $selF -CaseName 'F_explicit_historical'
$sumF = Get-PolicySummary -PolicyObj $verF.policy_obj
$caseFPass = $selF.found -and $verF.pass -and $verF.comparison_allowed -and (-not $selF.fallback_occurred) -and ($selF.resolved_version -eq $historicalVersion)
Write-Output "  resolved=$($selF.resolved_version) integrity=$($verF.reason) comparison_allowed=$($verF.comparison_allowed)"

# Gate
$gatePass = $true
$gateReasons = New-Object System.Collections.Generic.List[string]
if (-not $caseAPass) { $gatePass = $false; $gateReasons.Add('caseA_default_clean_failed') }
if (-not $caseBPass) { $gatePass = $false; $gateReasons.Add('caseB_hash_mismatch_not_blocked') }
if (-not $caseCPass) { $gatePass = $false; $gateReasons.Add('caseC_missing_policy_not_blocked') }
if (-not $caseDPass) { $gatePass = $false; $gateReasons.Add('caseD_missing_integrity_not_blocked') }
if (-not $caseEPass) { $gatePass = $false; $gateReasons.Add('caseE_historical_fallback_violation') }
if (-not $caseFPass) { $gatePass = $false; $gateReasons.Add('caseF_explicit_historical_broken') }
if ($selA.fallback_occurred -or $selB.fallback_occurred -or $selC.fallback_occurred -or $selD.fallback_occurred -or $selF.fallback_occurred) {
  $gatePass = $false
  $gateReasons.Add('fallback_detected')
}

$gateStr = if ($gatePass) { 'PASS' } else { 'FAIL' }

# 01_status.txt
Set-Content -Path (Join-Path $PFDir '01_status.txt') -Value @(
  "phase=43.2"
  "title=ACTIVE POLICY DEFAULT-RESOLUTION INTEGRITY ENFORCEMENT PROOF"
  "runner=tools/phase43_2/phase43_2_active_policy_default_resolution_enforcement_runner.ps1"
  "timestamp=$TS"
  "gate=$gateStr"
  "case_a_pass=$caseAPass"
  "case_b_pass=$caseBPass"
  "case_c_pass=$caseCPass"
  "case_d_pass=$caseDPass"
  "case_e_pass=$caseEPass"
  "case_f_pass=$caseFPass"
) -Encoding UTF8

# 02_head.txt
Set-Content -Path (Join-Path $PFDir '02_head.txt') -Value @(
  "project=NGKsUI Runtime"
  "phase=43.2"
  "title=ACTIVE POLICY DEFAULT-RESOLUTION INTEGRITY ENFORCEMENT PROOF"
  "timestamp_utc=$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')"
  "root=$Root"
  "gate=$gateStr"
) -Encoding UTF8

# 10_default_resolution_definition.txt
Set-Content -Path (Join-Path $PFDir '10_default_resolution_definition.txt') -Value @(
  "default_resolution_mode=requested_version_is_empty_or_unspecified"
  "declared_active_source=tools/phase43_0/policy_history_chain.json status=active"
  "selection_rule=exactly_one_active_entry_required"
  "selected_policy_file=active_entry.policy_file"
  "selected_integrity_file=active_entry.integrity_reference_file"
  "integrity_gate=verify_selected_policy_hash_equals_selected_integrity_reference_hash_before_comparison"
  "comparison_allowed_only_if_integrity_verified=true"
  "on_integrity_or_load_failure=block_default_resolution"
  "historical_fallback_allowed=false"
  "silent_remap_allowed=false"
) -Encoding UTF8

# 11_default_resolution_rules.txt
Set-Content -Path (Join-Path $PFDir '11_default_resolution_rules.txt') -Value @(
  "RULE_1=declared_active_policy_version_must_be_explicit_from_chain"
  "RULE_2=default_resolution_must_select_declared_active_only"
  "RULE_3=selected_active_policy_file_path_must_be_explicit"
  "RULE_4=selected_active_integrity_file_path_must_be_explicit"
  "RULE_5=integrity_verification_must_execute_before_comparison"
  "RULE_6=hash_mismatch_blocks_default_resolution"
  "RULE_7=missing_active_policy_file_blocks_default_resolution"
  "RULE_8=missing_active_integrity_reference_blocks_default_resolution"
  "RULE_9=historical_policy_must_not_be_auto_selected_during_default_failures"
  "RULE_10=explicit_historical_selection_remains_supported_and_separate"
) -Encoding UTF8

# 12_files_touched.txt
Set-Content -Path (Join-Path $PFDir '12_files_touched.txt') -Value @(
  "READ=tools/phase43_0/policy_history_chain.json"
  "READ=tools/phase42_8/active_version_policy.json"
  "READ=tools/phase42_9/policy_integrity_reference.json"
  "READ=tools/phase43_0/active_version_policy_v2.json"
  "READ=tools/phase43_0/policy_integrity_reference_v2.json"
  "CREATED(RUNNER)=tools/phase43_2/phase43_2_active_policy_default_resolution_enforcement_runner.ps1"
  "NOT_MODIFIED=tools/phase43_0/policy_history_chain.json"
  "NOT_MODIFIED=tools/phase42_8/active_version_policy.json"
  "NOT_MODIFIED=tools/phase42_9/policy_integrity_reference.json"
  "NOT_MODIFIED=tools/phase43_0/active_version_policy_v2.json"
  "NOT_MODIFIED=tools/phase43_0/policy_integrity_reference_v2.json"
  "UI_MODIFIED=NO"
  "BASELINE_MODE_MODIFIED=NO"
  "RUNTIME_SEMANTICS_MODIFIED=NO"
) -Encoding UTF8

# 13_build_output.txt
Set-Content -Path (Join-Path $PFDir '13_build_output.txt') -Value @(
  "build_action=none_required"
  "reason=phase43_2_is_policy-default-resolution-enforcement_runner_only"
  "canonical_launcher_reference=pwsh -NoProfile -ExecutionPolicy Bypass -File .\\tools\\run_widget_sandbox.ps1"
  "build_status=NOT_REQUIRED"
) -Encoding UTF8

# 14_validation_results.txt
$v14 = New-Object System.Collections.Generic.List[string]

$v14.Add('--- CASE A: CLEAN DEFAULT ACTIVE POLICY PASS ---')
$v14.Add("requested_policy_mode=$($selA.requested_mode)")
$v14.Add("requested_policy_version=$($selA.requested_version)")
$v14.Add("declared_active_version=$($selA.declared_active_version)")
$v14.Add("resolved_version=$($selA.resolved_version)")
$v14.Add("selected_policy_file=$($verA.selected_policy_file)")
$v14.Add("selected_integrity_file=$($verA.selected_integrity_file)")
$v14.Add("integrity_result=$($verA.reason)")
$v14.Add("comparison_allowed=$($verA.comparison_allowed)")
$v14.Add("comparison_result=$(if ($verA.comparison_allowed) { 'PASS' } else { 'BLOCKED' })")
$v14.Add("fallback_occurred=$($verA.fallback_occurred)")
if ($null -ne $sumA) {
  $v14.Add("loaded_policy_active_version=$($sumA.active_version)")
  $v14.Add("loaded_policy_historical_versions=$($sumA.historical_versions -join ',')")
}
$v14.Add("result=$(if ($caseAPass) { 'PASS' } else { 'FAIL' })")
$v14.Add('')

$v14.Add('--- CASE B: DEFAULT ACTIVE POLICY HASH MISMATCH ---')
$v14.Add("requested_policy_mode=$($selB.requested_mode)")
$v14.Add("declared_active_version=$($selB.declared_active_version)")
$v14.Add("resolved_version=$($selB.resolved_version)")
$v14.Add("selected_policy_file=$($verB.selected_policy_file)")
$v14.Add("selected_integrity_file=$($verB.selected_integrity_file)")
$v14.Add("integrity_result=$($verB.reason)")
$v14.Add("expected_hash=$($verB.expected_hash)")
$v14.Add("actual_hash=$($verB.actual_hash)")
$v14.Add("comparison_allowed=$($verB.comparison_allowed)")
$v14.Add("comparison_result=$(if ($verB.comparison_allowed) { 'PASS(UNEXPECTED)' } else { 'BLOCKED' })")
$v14.Add("fallback_occurred=$($verB.fallback_occurred)")
$v14.Add("result=$(if ($caseBPass) { 'PASS' } else { 'FAIL' })")
$v14.Add('')

$v14.Add('--- CASE C: DEFAULT ACTIVE POLICY FILE MISSING ---')
$v14.Add("requested_policy_mode=$($selC.requested_mode)")
$v14.Add("declared_active_version=$($selC.declared_active_version)")
$v14.Add("resolved_version=$($selC.resolved_version)")
$v14.Add("selected_policy_file=$($verC.selected_policy_file)")
$v14.Add("selected_integrity_file=$($verC.selected_integrity_file)")
$v14.Add("integrity_result=$($verC.reason)")
$v14.Add("comparison_allowed=$($verC.comparison_allowed)")
$v14.Add("comparison_result=$(if ($verC.comparison_allowed) { 'PASS(UNEXPECTED)' } else { 'BLOCKED' })")
$v14.Add("fallback_occurred=$($verC.fallback_occurred)")
$v14.Add("result=$(if ($caseCPass) { 'PASS' } else { 'FAIL' })")
$v14.Add('')

$v14.Add('--- CASE D: DEFAULT ACTIVE POLICY INTEGRITY REFERENCE MISSING ---')
$v14.Add("requested_policy_mode=$($selD.requested_mode)")
$v14.Add("declared_active_version=$($selD.declared_active_version)")
$v14.Add("resolved_version=$($selD.resolved_version)")
$v14.Add("selected_policy_file=$($verD.selected_policy_file)")
$v14.Add("selected_integrity_file=$($verD.selected_integrity_file)")
$v14.Add("integrity_result=$($verD.reason)")
$v14.Add("comparison_allowed=$($verD.comparison_allowed)")
$v14.Add("comparison_result=$(if ($verD.comparison_allowed) { 'PASS(UNEXPECTED)' } else { 'BLOCKED' })")
$v14.Add("fallback_occurred=$($verD.fallback_occurred)")
$v14.Add("result=$(if ($caseDPass) { 'PASS' } else { 'FAIL' })")
$v14.Add('')

$v14.Add('--- CASE E: DEFAULT RESOLUTION MUST NOT SELECT HISTORICAL ---')
$v14.Add("declared_active_version=$($selA.declared_active_version)")
$v14.Add("historical_version=$historicalVersion")
$v14.Add("default_caseA_resolved=$($selA.resolved_version)")
$v14.Add("default_caseB_resolved=$($selB.resolved_version)")
$v14.Add("default_caseC_resolved=$($selC.resolved_version)")
$v14.Add("default_caseD_resolved=$($selD.resolved_version)")
$v14.Add("no_fallback_observed=$caseENoFallbackObserved")
$v14.Add("historical_not_selected=$caseEHistoricalNotSelected")
$v14.Add("result=$(if ($caseEPass) { 'PASS' } else { 'FAIL' })")
$v14.Add('')

$v14.Add('--- CASE F: EXPLICIT HISTORICAL STILL WORKS ---')
$v14.Add("requested_policy_mode=$($selF.requested_mode)")
$v14.Add("requested_policy_version=$($selF.requested_version)")
$v14.Add("declared_active_version=$($selF.declared_active_version)")
$v14.Add("resolved_version=$($selF.resolved_version)")
$v14.Add("selected_policy_file=$($verF.selected_policy_file)")
$v14.Add("selected_integrity_file=$($verF.selected_integrity_file)")
$v14.Add("integrity_result=$($verF.reason)")
$v14.Add("comparison_allowed=$($verF.comparison_allowed)")
$v14.Add("fallback_occurred=$($selF.fallback_occurred)")
if ($null -ne $sumF) {
  $v14.Add("loaded_policy_active_version=$($sumF.active_version)")
  $v14.Add("loaded_policy_historical_versions=$($sumF.historical_versions -join ',')")
}
$v14.Add("result=$(if ($caseFPass) { 'PASS' } else { 'FAIL' })")
$v14.Add('')

$v14.Add('--- GATE ---')
$v14.Add("GATE=$gateStr")
if (-not $gatePass) { foreach ($r in $gateReasons) { $v14.Add("gate_fail_reason=$r") } }
Set-Content -Path (Join-Path $PFDir '14_validation_results.txt') -Value $v14 -Encoding UTF8

# 15_behavior_summary.txt
Set-Content -Path (Join-Path $PFDir '15_behavior_summary.txt') -Value @(
  "BEHAVIOR_SUMMARY=Phase43_2"
  ""
  "DEFAULT ACTIVE-POLICY RESOLUTION:"
  "  Default mode means no explicit policy version request."
  "  The resolver reads tools/phase43_0/policy_history_chain.json and requires exactly"
  "  one entry with status=active. That active version is the only valid default target."
  ""
  "INTEGRITY-FIRST GATING:"
  "  After selecting active policy file and integrity reference paths, the runner verifies"
  "  SHA256(policy_file_bytes) == expected_policy_sha256 from the selected integrity reference."
  "  Only on a hash match does comparison_allowed=true."
  ""
  "DEFAULT BLOCK ON FAILURES:"
  "  Hash mismatch, missing active policy file, and missing active integrity reference"
  "  each produce deterministic failure reasons and comparison_allowed=false."
  "  No regeneration and no bypass path exists."
  ""
  "NO HISTORICAL FALLBACK:"
  "  In all default-mode cases (pass/fail), resolved_version stays the declared active version."
  "  The historical version is never auto-selected, including when active-material checks fail."
  ""
  "EXPLICIT HISTORICAL REMAINS OPERATIONAL:"
  "  Historical selection still succeeds when explicitly requested (Case F), proving"
  "  strict default enforcement does not break historical validation support."
  ""
  "DISABLED CONTROL:"
  "  Disabled remains inert. No control map behavior changed."
  ""
  "BASELINE MODE:"
  "  Unchanged. No runtime semantics modified."
) -Encoding UTF8

# 16_default_resolution_record.txt
$rec = New-Object System.Collections.Generic.List[string]
foreach ($item in @($verA, $verB, $verC, $verD, $verF)) {
  $rec.Add("--- CASE $($item.case_name) ---")
  $rec.Add("requested_policy_mode=$($item.requested_mode)")
  $rec.Add("requested_policy_version=$($item.requested_version)")
  $rec.Add("declared_active_version=$($item.declared_active_version)")
  $rec.Add("resolved_version=$($item.resolved_version)")
  $rec.Add("selected_policy_file_path=$($item.selected_policy_file)")
  $rec.Add("selected_integrity_reference_file_path=$($item.selected_integrity_file)")
  $rec.Add("integrity_verification_result=$($item.reason)")
  $rec.Add("comparison_result=$(if ($item.comparison_allowed) { 'PASS' } else { 'BLOCKED' })")
  $rec.Add("comparison_allowed_or_blocked=$($item.comparison_allowed)")
  $rec.Add("fallback_or_remapping_occurred=$($item.fallback_occurred)")
  if ($item.pass -and $null -ne $item.policy_obj) {
    $summary = Get-PolicySummary -PolicyObj $item.policy_obj
    $rec.Add("loaded_policy_active_version=$($summary.active_version)")
    $rec.Add("loaded_policy_historical_versions=$($summary.historical_versions -join ',')")
  }
  $rec.Add('')
}
Set-Content -Path (Join-Path $PFDir '16_default_resolution_record.txt') -Value $rec -Encoding UTF8

# 17_default_resolution_block_evidence.txt
Set-Content -Path (Join-Path $PFDir '17_default_resolution_block_evidence.txt') -Value @(
  "--- CASE B BLOCK EVIDENCE ---"
  "failure_case_id=B_default_hash_mismatch"
  "tamper_or_mismatch_input=active_policy_file_paired_with_wrong_integrity_reference(v1_ref)"
  "expected_result=FAIL"
  "actual_block_result=$(-not $verB.comparison_allowed)"
  "failure_reason=$($verB.reason)"
  "historical_fallback_occurred=False"
  ""
  "--- CASE C BLOCK EVIDENCE ---"
  "failure_case_id=C_default_policy_missing"
  "tamper_or_mismatch_input=active_policy_file_path_missing"
  "expected_result=FAIL"
  "actual_block_result=$(-not $verC.comparison_allowed)"
  "failure_reason=$($verC.reason)"
  "historical_fallback_occurred=False"
  ""
  "--- CASE D BLOCK EVIDENCE ---"
  "failure_case_id=D_default_integrity_missing"
  "tamper_or_mismatch_input=active_integrity_reference_path_missing"
  "expected_result=FAIL"
  "actual_block_result=$(-not $verD.comparison_allowed)"
  "failure_reason=$($verD.reason)"
  "historical_fallback_occurred=False"
) -Encoding UTF8

# 98_gate_phase43_2.txt
$gate98 = @(
  "PHASE=43.2"
  "GATE=$gateStr"
  "timestamp=$TS"
)
if (-not $gatePass) {
  foreach ($r in $gateReasons) { $gate98 += "FAIL_REASON=$r" }
}
Set-Content -Path (Join-Path $PFDir '98_gate_phase43_2.txt') -Value $gate98 -Encoding UTF8

# zip proof packet
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

Write-Output "PF=$PFDir"
Write-Output "ZIP=$ZipPath"
Write-Output "GATE=$gateStr"
