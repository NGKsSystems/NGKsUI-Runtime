param(
  [string]$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Set-Location $Root
if ((Get-Location).Path -ne $Root) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

function Get-FileSha256Hex {
  param([Parameter(Mandatory = $true)][string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
  return ([System.BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
}

function Convert-RepoPathToAbsolute {
  param(
    [Parameter(Mandatory = $true)][string]$RootPath,
    [Parameter(Mandatory = $true)][string]$RepoPath
  )

  if ([string]::IsNullOrWhiteSpace($RepoPath)) {
    return ''
  }

  if ([System.IO.Path]::IsPathRooted($RepoPath)) {
    return $RepoPath
  }

  return Join-Path $RootPath $RepoPath.Replace('/', '\')
}

function Convert-AbsoluteToRepoPath {
  param(
    [Parameter(Mandatory = $true)][string]$RootPath,
    [Parameter(Mandatory = $true)][string]$AbsolutePath
  )

  $normalizedRoot = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\')
  $normalizedPath = [System.IO.Path]::GetFullPath($AbsolutePath)
  if (-not $normalizedPath.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Path '$AbsolutePath' is outside root '$RootPath'"
  }

  return $normalizedPath.Substring($normalizedRoot.Length).TrimStart('\').Replace('\', '/')
}

function Get-OptionalObjectPropertyValue {
  param(
    [Parameter(Mandatory = $true)]$Object,
    [Parameter(Mandatory = $true)][string]$PropertyName,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$DefaultValue
  )

  $property = $Object.PSObject.Properties[$PropertyName]
  if ($null -eq $property) {
    return $DefaultValue
  }

  return [string]$property.Value
}

function Get-HistoricalPolicyVersionsFromChain {
  param([Parameter(Mandatory = $true)]$ChainObject)

  $historical = @($ChainObject.chain | Where-Object { [string]$_.status -eq 'historical' } | ForEach-Object { [string]$_.version })
  if ($historical.Count -eq 0) {
    return ''
  }

  return ($historical -join ',')
}

function Get-ChainMaterialVersion {
  param([Parameter(Mandatory = $true)]$ChainObject)
  return Get-OptionalObjectPropertyValue -Object $ChainObject -PropertyName 'chain_material_version' -DefaultValue '1'
}

function Resolve-ChainVersionSelection {
  param(
    [Parameter(Mandatory = $true)][string]$RequestedChainVersion,
    [Parameter(Mandatory = $true)][string]$CatalogPath,
    [Parameter(Mandatory = $true)][string]$RootPath
  )

  $catalog = Get-Content -Raw -LiteralPath $CatalogPath | ConvertFrom-Json
  $match = $null
  foreach ($entry in $catalog.versions) {
    if ([string]$entry.chain_version -eq $RequestedChainVersion.Trim()) {
      $match = $entry
      break
    }
  }

  if ($null -eq $match) {
    return [pscustomobject]@{
      pass = $false
      reason = 'chain_version_not_registered:' + $RequestedChainVersion
      requested_chain_version = $RequestedChainVersion
      selected_chain_version = ''
      selected_chain_file_rel = ''
      selected_chain_file_abs = ''
      selected_integrity_file_rel = ''
      selected_integrity_file_abs = ''
      chain_state = ''
      fallback_occurred = $false
    }
  }

  return [pscustomobject]@{
    pass = $true
    reason = 'chain_version_selected'
    requested_chain_version = $RequestedChainVersion
    selected_chain_version = [string]$match.chain_version
    selected_chain_file_rel = [string]$match.chain_file
    selected_chain_file_abs = Convert-RepoPathToAbsolute -RootPath $RootPath -RepoPath ([string]$match.chain_file)
    selected_integrity_file_rel = [string]$match.integrity_reference_file
    selected_integrity_file_abs = Convert-RepoPathToAbsolute -RootPath $RootPath -RepoPath ([string]$match.integrity_reference_file)
    chain_state = [string]$match.chain_state
    fallback_occurred = $false
  }
}

function Test-ActiveChainIntegrity {
  param(
    [Parameter(Mandatory = $true)]$Selection,
    [Parameter(Mandatory = $true)][string]$CaseName,
    [Parameter(Mandatory = $true)][string]$RootPath
  )

  if (-not $Selection.pass) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = $Selection.reason
      requested_chain_version = $Selection.requested_chain_version
      selected_chain_version = $Selection.selected_chain_version
      selected_chain_file = $Selection.selected_chain_file_rel
      selected_integrity_file = $Selection.selected_integrity_file_rel
      stored_chain_hash = ''
      stored_chain_integrity_hash = ''
      computed_chain_hash = ''
      integrity_verification_result = 'FAIL'
      mismatch_fields = 'requested_chain_version'
      resolved_active_policy_version = ''
      resolved_historical_policy_versions = ''
      comparison_allowed = $false
      fallback_occurred = $Selection.fallback_occurred
      chain_loaded = $false
      chain_obj = $null
    }
  }

  if (-not (Test-Path -LiteralPath $Selection.selected_integrity_file_abs)) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'chain_integrity_reference_missing'
      requested_chain_version = $Selection.requested_chain_version
      selected_chain_version = $Selection.selected_chain_version
      selected_chain_file = $Selection.selected_chain_file_rel
      selected_integrity_file = $Selection.selected_integrity_file_rel
      stored_chain_hash = ''
      stored_chain_integrity_hash = ''
      computed_chain_hash = ''
      integrity_verification_result = 'FAIL'
      mismatch_fields = 'integrity_reference_file_missing'
      resolved_active_policy_version = ''
      resolved_historical_policy_versions = ''
      comparison_allowed = $false
      fallback_occurred = $Selection.fallback_occurred
      chain_loaded = $false
      chain_obj = $null
    }
  }

  $integrityReferenceHash = Get-FileSha256Hex -Path $Selection.selected_integrity_file_abs
  $integrityObject = Get-Content -Raw -LiteralPath $Selection.selected_integrity_file_abs | ConvertFrom-Json
  $expectedChainHash = [string]$integrityObject.expected_chain_sha256
  $protectedChainRepoPath = Get-OptionalObjectPropertyValue -Object $integrityObject -PropertyName 'protected_chain_file' -DefaultValue ''
  $protectedChainAbs = if ([string]::IsNullOrWhiteSpace($protectedChainRepoPath)) { '' } else { Convert-RepoPathToAbsolute -RootPath $RootPath -RepoPath $protectedChainRepoPath }

  if (-not (Test-Path -LiteralPath $Selection.selected_chain_file_abs)) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'chain_source_missing'
      requested_chain_version = $Selection.requested_chain_version
      selected_chain_version = $Selection.selected_chain_version
      selected_chain_file = $Selection.selected_chain_file_rel
      selected_integrity_file = $Selection.selected_integrity_file_rel
      stored_chain_hash = $expectedChainHash
      stored_chain_integrity_hash = $integrityReferenceHash
      computed_chain_hash = ''
      integrity_verification_result = 'FAIL'
      mismatch_fields = 'chain_file_missing'
      resolved_active_policy_version = ''
      resolved_historical_policy_versions = ''
      comparison_allowed = $false
      fallback_occurred = $Selection.fallback_occurred
      chain_loaded = $false
      chain_obj = $null
    }
  }

  $computedChainHash = Get-FileSha256Hex -Path $Selection.selected_chain_file_abs
  if (-not [string]::IsNullOrWhiteSpace($protectedChainAbs) -and ($protectedChainAbs -ne $Selection.selected_chain_file_abs)) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'chain_reference_target_mismatch'
      requested_chain_version = $Selection.requested_chain_version
      selected_chain_version = $Selection.selected_chain_version
      selected_chain_file = $Selection.selected_chain_file_rel
      selected_integrity_file = $Selection.selected_integrity_file_rel
      stored_chain_hash = $expectedChainHash
      stored_chain_integrity_hash = $integrityReferenceHash
      computed_chain_hash = $computedChainHash
      integrity_verification_result = 'FAIL'
      mismatch_fields = 'protected_chain_file'
      resolved_active_policy_version = ''
      resolved_historical_policy_versions = ''
      comparison_allowed = $false
      fallback_occurred = $Selection.fallback_occurred
      chain_loaded = $false
      chain_obj = $null
    }
  }

  if ($computedChainHash -ne $expectedChainHash) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'chain_hash_mismatch'
      requested_chain_version = $Selection.requested_chain_version
      selected_chain_version = $Selection.selected_chain_version
      selected_chain_file = $Selection.selected_chain_file_rel
      selected_integrity_file = $Selection.selected_integrity_file_rel
      stored_chain_hash = $expectedChainHash
      stored_chain_integrity_hash = $integrityReferenceHash
      computed_chain_hash = $computedChainHash
      integrity_verification_result = 'FAIL'
      mismatch_fields = 'expected_chain_sha256'
      resolved_active_policy_version = ''
      resolved_historical_policy_versions = ''
      comparison_allowed = $false
      fallback_occurred = $Selection.fallback_occurred
      chain_loaded = $false
      chain_obj = $null
    }
  }

  $chainObject = Get-Content -Raw -LiteralPath $Selection.selected_chain_file_abs | ConvertFrom-Json
  $defaultSelection = Resolve-DefaultFromChain -Chain $chainObject -RootPath $RootPath
  $resolvedHistorical = Get-HistoricalPolicyVersionsFromChain -ChainObject $chainObject

  return [pscustomobject]@{
    case_name = $CaseName
    pass = $true
    reason = 'chain_integrity_verified'
    requested_chain_version = $Selection.requested_chain_version
    selected_chain_version = $Selection.selected_chain_version
    selected_chain_file = $Selection.selected_chain_file_rel
    selected_integrity_file = $Selection.selected_integrity_file_rel
    stored_chain_hash = $expectedChainHash
    stored_chain_integrity_hash = $integrityReferenceHash
    computed_chain_hash = $computedChainHash
    integrity_verification_result = 'PASS'
    mismatch_fields = ''
    resolved_active_policy_version = $defaultSelection.resolved_version
    resolved_historical_policy_versions = $resolvedHistorical
    comparison_allowed = $true
    fallback_occurred = $Selection.fallback_occurred
    chain_loaded = $true
    chain_obj = $chainObject
  }
}

function Resolve-DefaultFromChain {
  param(
    [Parameter(Mandatory = $true)]$Chain,
    [Parameter(Mandatory = $true)][string]$RootPath
  )

  $activeEntries = @($Chain.chain | Where-Object { [string]$_.status -eq 'active' })
  if ($activeEntries.Count -ne 1) {
    return [pscustomobject]@{
      found = $false
      failure_reason = 'invalid_active_entry_count:' + $activeEntries.Count
      declared_active_version = ''
      resolved_version = ''
      policy_file_rel = ''
      integrity_file_rel = ''
      policy_file_abs = ''
      integrity_file_abs = ''
      fallback_occurred = $false
    }
  }

  $entry = $activeEntries[0]
  return [pscustomobject]@{
    found = $true
    failure_reason = ''
    declared_active_version = [string]$entry.version
    resolved_version = [string]$entry.version
    policy_file_rel = [string]$entry.policy_file
    integrity_file_rel = [string]$entry.integrity_reference_file
    policy_file_abs = Convert-RepoPathToAbsolute -RootPath $RootPath -RepoPath ([string]$entry.policy_file)
    integrity_file_abs = Convert-RepoPathToAbsolute -RootPath $RootPath -RepoPath ([string]$entry.integrity_reference_file)
    fallback_occurred = $false
  }
}

function Resolve-ExplicitFromChain {
  param(
    [Parameter(Mandatory = $true)][string]$RequestedVersion,
    [Parameter(Mandatory = $true)]$Chain,
    [Parameter(Mandatory = $true)][string]$RootPath
  )

  $entry = $null
  foreach ($candidate in $Chain.chain) {
    if ([string]$candidate.version -eq $RequestedVersion.Trim()) {
      $entry = $candidate
      break
    }
  }

  if ($null -eq $entry) {
    return [pscustomobject]@{
      found = $false
      failure_reason = 'version_not_in_chain:' + $RequestedVersion
      declared_active_version = ''
      resolved_version = ''
      policy_file_rel = ''
      integrity_file_rel = ''
      policy_file_abs = ''
      integrity_file_abs = ''
      fallback_occurred = $false
    }
  }

  $activeEntry = @($Chain.chain | Where-Object { [string]$_.status -eq 'active' }) | Select-Object -First 1
  return [pscustomobject]@{
    found = $true
    failure_reason = ''
    declared_active_version = if ($null -ne $activeEntry) { [string]$activeEntry.version } else { '' }
    resolved_version = [string]$entry.version
    policy_file_rel = [string]$entry.policy_file
    integrity_file_rel = [string]$entry.integrity_reference_file
    policy_file_abs = Convert-RepoPathToAbsolute -RootPath $RootPath -RepoPath ([string]$entry.policy_file)
    integrity_file_abs = Convert-RepoPathToAbsolute -RootPath $RootPath -RepoPath ([string]$entry.integrity_reference_file)
    fallback_occurred = ($RequestedVersion.Trim() -ne [string]$entry.version)
  }
}

function Test-PolicyIntegrityFromSelection {
  param(
    [Parameter(Mandatory = $true)]$Selection,
    [Parameter(Mandatory = $true)][string]$RequestedMode,
    [Parameter(Mandatory = $true)][string]$RequestedVersion
  )

  if (-not $Selection.found) {
    return [pscustomobject]@{
      pass = $false
      reason = 'selection_not_found'
      requested_mode = $RequestedMode
      requested_version = $RequestedVersion
      selected_policy_file = ''
      selected_integrity_file = ''
      expected_policy_hash = ''
      actual_policy_hash = ''
      comparison_allowed = $false
      fallback_occurred = $Selection.fallback_occurred
      policy_obj = $null
    }
  }

  if ($Selection.fallback_occurred) {
    return [pscustomobject]@{
      pass = $false
      reason = 'silent_fallback_detected'
      requested_mode = $RequestedMode
      requested_version = $RequestedVersion
      selected_policy_file = $Selection.policy_file_rel
      selected_integrity_file = $Selection.integrity_file_rel
      expected_policy_hash = ''
      actual_policy_hash = ''
      comparison_allowed = $false
      fallback_occurred = $true
      policy_obj = $null
    }
  }

  if (-not (Test-Path -LiteralPath $Selection.integrity_file_abs)) {
    return [pscustomobject]@{
      pass = $false
      reason = 'policy_integrity_reference_missing'
      requested_mode = $RequestedMode
      requested_version = $RequestedVersion
      selected_policy_file = $Selection.policy_file_rel
      selected_integrity_file = $Selection.integrity_file_rel
      expected_policy_hash = ''
      actual_policy_hash = ''
      comparison_allowed = $false
      fallback_occurred = $false
      policy_obj = $null
    }
  }

  $integrityObject = Get-Content -Raw -LiteralPath $Selection.integrity_file_abs | ConvertFrom-Json
  $expected = [string]$integrityObject.expected_policy_sha256

  if (-not (Test-Path -LiteralPath $Selection.policy_file_abs)) {
    return [pscustomobject]@{
      pass = $false
      reason = 'policy_file_missing'
      requested_mode = $RequestedMode
      requested_version = $RequestedVersion
      selected_policy_file = $Selection.policy_file_rel
      selected_integrity_file = $Selection.integrity_file_rel
      expected_policy_hash = $expected
      actual_policy_hash = ''
      comparison_allowed = $false
      fallback_occurred = $false
      policy_obj = $null
    }
  }

  $actual = Get-FileSha256Hex -Path $Selection.policy_file_abs
  if ($actual -ne $expected) {
    return [pscustomobject]@{
      pass = $false
      reason = 'policy_hash_mismatch'
      requested_mode = $RequestedMode
      requested_version = $RequestedVersion
      selected_policy_file = $Selection.policy_file_rel
      selected_integrity_file = $Selection.integrity_file_rel
      expected_policy_hash = $expected
      actual_policy_hash = $actual
      comparison_allowed = $false
      fallback_occurred = $false
      policy_obj = $null
    }
  }

  return [pscustomobject]@{
    pass = $true
    reason = 'policy_integrity_verified'
    requested_mode = $RequestedMode
    requested_version = $RequestedVersion
    selected_policy_file = $Selection.policy_file_rel
    selected_integrity_file = $Selection.integrity_file_rel
    expected_policy_hash = $expected
    actual_policy_hash = $actual
    comparison_allowed = $true
    fallback_occurred = $false
    policy_obj = (Get-Content -Raw -LiteralPath $Selection.policy_file_abs | ConvertFrom-Json)
  }
}

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pfDir = Join-Path $Root "_proof\phase43_5_active_chain_version_selection_historical_validation_$ts"
New-Item -ItemType Directory -Force -Path $pfDir | Out-Null

$phaseDir = Join-Path $Root 'tools\phase43_5'
New-Item -ItemType Directory -Force -Path $phaseDir | Out-Null
$catalogPath = Join-Path $phaseDir 'active_chain_version_catalog.json'

$launcherStdOut = Join-Path $pfDir 'launcher_stdout.txt'
$launcherStdErr = Join-Path $pfDir 'launcher_stderr.txt'
$launcherArgString = '-NoProfile -ExecutionPolicy Bypass -File ".\\tools\\run_widget_sandbox.ps1" -Config Debug -PassArgs --sandbox-extension --auto-close-ms=1200'
$launcherProc = Start-Process -FilePath 'pwsh' -ArgumentList $launcherArgString -WorkingDirectory $Root -NoNewWindow -PassThru -RedirectStandardOutput $launcherStdOut -RedirectStandardError $launcherStdErr
$launcherExited = $launcherProc.WaitForExit(25000)
if (-not $launcherExited) {
  Stop-Process -Id $launcherProc.Id -Force
  $launcherExit = 124
} else {
  $launcherExit = $launcherProc.ExitCode
}
$launcherText = if (Test-Path -LiteralPath $launcherStdOut) { Get-Content -Raw -LiteralPath $launcherStdOut } else { '' }
$launcherErrText = if (Test-Path -LiteralPath $launcherStdErr) { Get-Content -Raw -LiteralPath $launcherStdErr } else { '' }
$canonicalLaunchUsed = ($launcherText -match 'LAUNCH_EXE=')
$launcherOutput = @($launcherText, $launcherErrText)

Write-Output '=== CASE A: SELECT ACTIVE-CHAIN V1 / VALIDATE V1 ==='
$selectionA = Resolve-ChainVersionSelection -RequestedChainVersion 'v1' -CatalogPath $catalogPath -RootPath $Root
$chainA = Test-ActiveChainIntegrity -Selection $selectionA -CaseName 'A_select_v1' -RootPath $Root
$defaultA = $null
$policyA = $null
if ($chainA.comparison_allowed) {
  $defaultA = Resolve-DefaultFromChain -Chain $chainA.chain_obj -RootPath $Root
  $policyA = Test-PolicyIntegrityFromSelection -Selection $defaultA -RequestedMode 'default' -RequestedVersion '(default)'
}
$caseAPass = $selectionA.pass -and $chainA.pass -and $null -ne $defaultA -and $defaultA.found -and $null -ne $policyA -and $policyA.pass

Write-Output '=== CASE B: SELECT ACTIVE-CHAIN V2 / VALIDATE V2 ==='
$selectionB = Resolve-ChainVersionSelection -RequestedChainVersion 'v2' -CatalogPath $catalogPath -RootPath $Root
$chainB = Test-ActiveChainIntegrity -Selection $selectionB -CaseName 'B_select_v2' -RootPath $Root
$defaultB = $null
$policyB = $null
if ($chainB.comparison_allowed) {
  $defaultB = Resolve-DefaultFromChain -Chain $chainB.chain_obj -RootPath $Root
  $policyB = Test-PolicyIntegrityFromSelection -Selection $defaultB -RequestedMode 'default' -RequestedVersion '(default)'
}
$caseBPass = $selectionB.pass -and $chainB.pass -and $null -ne $defaultB -and $defaultB.found -and $null -ne $policyB -and $policyB.pass

Write-Output '=== CASE C: WRONG ACTIVE-CHAIN VERSION COMPARISON ==='
$wrongSelection = [pscustomobject]@{
  pass = $true
  reason = 'chain_version_selected'
  requested_chain_version = 'v1'
  selected_chain_version = 'v1'
  selected_chain_file_rel = $selectionA.selected_chain_file_rel
  selected_chain_file_abs = $selectionA.selected_chain_file_abs
  selected_integrity_file_rel = $selectionB.selected_integrity_file_rel
  selected_integrity_file_abs = $selectionB.selected_integrity_file_abs
  chain_state = $selectionA.chain_state
  fallback_occurred = $false
}
$chainC = Test-ActiveChainIntegrity -Selection $wrongSelection -CaseName 'C_wrong_version_compare' -RootPath $Root
$caseCPass = (-not $chainC.pass) -and (-not $chainC.comparison_allowed) -and ($chainC.reason -eq 'chain_reference_target_mismatch' -or $chainC.reason -eq 'chain_hash_mismatch')

Write-Output '=== CASE D: VERSION LOAD AUDITABILITY ==='
$caseDPass =
  ($selectionA.requested_chain_version -eq $selectionA.selected_chain_version) -and
  ($selectionB.requested_chain_version -eq $selectionB.selected_chain_version) -and
  (-not $selectionA.fallback_occurred) -and
  (-not $selectionB.fallback_occurred) -and
  ($selectionA.selected_chain_file_rel -eq 'tools/phase43_0/policy_history_chain.json') -and
  ($selectionA.selected_integrity_file_rel -eq 'tools/phase43_3/active_policy_chain_integrity_reference.json') -and
  ($selectionB.selected_chain_file_rel -eq 'tools/phase43_4/policy_history_chain_rotated_v2.json') -and
  ($selectionB.selected_integrity_file_rel -eq 'tools/phase43_4/active_policy_chain_integrity_reference_v2.json')

Write-Output '=== CASE E: HISTORICAL ACTIVE-CHAIN USABILITY ==='
$caseEPass = $selectionA.pass -and ($selectionA.chain_state -eq 'historical_operational') -and $chainA.pass -and $null -ne $policyA -and $policyA.pass -and ($chainA.resolved_active_policy_version -eq 'v2')

Write-Output '=== CASE F: INVALID ACTIVE-CHAIN VERSION REQUEST ==='
$selectionF = Resolve-ChainVersionSelection -RequestedChainVersion 'v99' -CatalogPath $catalogPath -RootPath $Root
$chainF = Test-ActiveChainIntegrity -Selection $selectionF -CaseName 'F_invalid_version' -RootPath $Root
$caseFPass = (-not $selectionF.pass) -and (-not $chainF.pass) -and ($chainF.reason -like 'chain_version_not_registered:*') -and (-not $chainF.comparison_allowed) -and (-not $chainF.fallback_occurred)

Write-Output '=== CASE G: EXPLICIT HISTORICAL POLICY SELECTION STILL SEPARATE ==='
$historicalPolicyVersion = 'v1'
$explicitPolicySelection = $null
$explicitPolicyIntegrity = $null
if ($chainB.comparison_allowed) {
  $explicitPolicySelection = Resolve-ExplicitFromChain -RequestedVersion $historicalPolicyVersion -Chain $chainB.chain_obj -RootPath $Root
  $explicitPolicyIntegrity = Test-PolicyIntegrityFromSelection -Selection $explicitPolicySelection -RequestedMode 'explicit' -RequestedVersion $historicalPolicyVersion
}
$caseGPass = $null -ne $explicitPolicySelection -and $explicitPolicySelection.found -and ($explicitPolicySelection.resolved_version -eq $historicalPolicyVersion) -and (-not $explicitPolicySelection.fallback_occurred) -and $null -ne $explicitPolicyIntegrity -and $explicitPolicyIntegrity.pass

$noFallback =
  (-not $selectionA.fallback_occurred) -and
  (-not $selectionB.fallback_occurred) -and
  (-not $wrongSelection.fallback_occurred) -and
  (-not $chainF.fallback_occurred) -and
  (($null -eq $explicitPolicySelection) -or (-not $explicitPolicySelection.fallback_occurred))

$gatePass = $true
$gateReasons = New-Object System.Collections.Generic.List[string]
if (-not $canonicalLaunchUsed) { $gatePass = $false; $gateReasons.Add('canonical_launcher_not_verified') }
if (-not $caseAPass) { $gatePass = $false; $gateReasons.Add('caseA_fail') }
if (-not $caseBPass) { $gatePass = $false; $gateReasons.Add('caseB_fail') }
if (-not $caseCPass) { $gatePass = $false; $gateReasons.Add('caseC_fail') }
if (-not $caseDPass) { $gatePass = $false; $gateReasons.Add('caseD_fail') }
if (-not $caseEPass) { $gatePass = $false; $gateReasons.Add('caseE_fail') }
if (-not $caseFPass) { $gatePass = $false; $gateReasons.Add('caseF_fail') }
if (-not $caseGPass) { $gatePass = $false; $gateReasons.Add('caseG_fail') }
if (-not $noFallback) { $gatePass = $false; $gateReasons.Add('fallback_detected') }

$gateStr = if ($gatePass) { 'PASS' } else { 'FAIL' }

Set-Content -Path (Join-Path $pfDir '01_status.txt') -Value @(
  'phase=43.5'
  'title=ACTIVE POLICY CHAIN VERSION SELECTION / HISTORICAL CHAIN VALIDATION PROOF'
  ('timestamp=' + $ts)
  ('gate=' + $gateStr)
  ('canonical_launcher_used=' + $canonicalLaunchUsed)
  ('case_a=' + $caseAPass)
  ('case_b=' + $caseBPass)
  ('case_c=' + $caseCPass)
  ('case_d=' + $caseDPass)
  ('case_e=' + $caseEPass)
  ('case_f=' + $caseFPass)
  ('case_g=' + $caseGPass)
) -Encoding UTF8

Set-Content -Path (Join-Path $pfDir '02_head.txt') -Value @(
  'project=NGKsUI Runtime'
  'phase=43.5'
  'title=ACTIVE POLICY CHAIN VERSION SELECTION / HISTORICAL CHAIN VALIDATION PROOF'
  ('timestamp_utc=' + (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'))
  ('root=' + $Root)
  ('gate=' + $gateStr)
) -Encoding UTF8

Set-Content -Path (Join-Path $pfDir '10_active_chain_version_selection_definition.txt') -Value @(
  ('version_catalog=tools/phase43_5/active_chain_version_catalog.json')
  'selection_mode=explicit_only'
  'default_fallback_allowed=False'
  ('active_chain_v1_file=' + $selectionA.selected_chain_file_rel)
  ('active_chain_v1_integrity_reference=' + $selectionA.selected_integrity_file_rel)
  ('active_chain_v2_file=' + $selectionB.selected_chain_file_rel)
  ('active_chain_v2_integrity_reference=' + $selectionB.selected_integrity_file_rel)
  'selection_runner_input=requested_chain_version'
  'version_resolution_behavior=fail_when_version_not_registered_or_integrity_reference_does_not_match_selected_chain_file'
) -Encoding UTF8

Set-Content -Path (Join-Path $pfDir '11_active_chain_version_selection_rules.txt') -Value @(
  'RULE_1=requested_chain_version_must_be_explicit'
  'RULE_2=selected_chain_file_path_must_come_from_explicit_version_catalog'
  'RULE_3=selected_chain_integrity_reference_path_must_come_from_explicit_version_catalog'
  'RULE_4=selected_chain_integrity_must_pass_before_default_resolution'
  'RULE_5=wrong_version_reference_target_or_hash_mismatch_must_fail'
  'RULE_6=invalid_chain_version_request_must_fail_without_fallback'
  'RULE_7=historical_active_chain_versions_must_remain_operational'
  'RULE_8=explicit_historical_policy_selection_remains_separate'
  'RULE_9=latest_auto_pick_for_proof_is_disallowed'
) -Encoding UTF8

Set-Content -Path (Join-Path $pfDir '12_files_touched.txt') -Value @(
  'READ=tools/phase43_0/policy_history_chain.json'
  'READ=tools/phase43_3/active_policy_chain_integrity_reference.json'
  'READ=tools/phase43_4/policy_history_chain_rotated_v2.json'
  'READ=tools/phase43_4/active_policy_chain_integrity_reference_v2.json'
  'READ=tools/phase43_0/active_version_policy_v2.json'
  'READ=tools/phase43_0/policy_integrity_reference_v2.json'
  'READ=tools/phase42_8/active_version_policy.json'
  'READ=tools/phase42_9/policy_integrity_reference.json'
  'CREATED=tools/phase43_5/active_chain_version_catalog.json'
  'CREATED=tools/phase43_5/phase43_5_active_chain_version_selection_historical_validation_runner.ps1'
  'UI_MODIFIED=NO'
  'BASELINE_MODE_MODIFIED=NO'
  'RUNTIME_SEMANTICS_MODIFIED=NO'
) -Encoding UTF8

$buildLines = @(
  ('canonical_launcher_exit=' + $launcherExit)
  ('canonical_launcher_used=' + $canonicalLaunchUsed)
  'build_action=none_required'
  'reason=phase43_5_validates_explicit_chain_version_selection_only'
)
if ($null -ne $launcherOutput) {
  $buildLines += '--- canonical launcher output ---'
  $buildLines += ($launcherOutput | ForEach-Object { [string]$_ })
}
Set-Content -Path (Join-Path $pfDir '13_build_output.txt') -Value $buildLines -Encoding UTF8

$v14 = New-Object System.Collections.Generic.List[string]
foreach ($record in @($chainA, $chainB, $chainC, $chainF)) {
  $v14.Add('--- CASE ' + $record.case_name + ' ---')
  $v14.Add('requested_chain_version=' + $record.requested_chain_version)
  $v14.Add('selected_chain_version=' + $record.selected_chain_version)
  $v14.Add('selected_chain_file=' + $record.selected_chain_file)
  $v14.Add('selected_chain_integrity_reference_file=' + $record.selected_integrity_file)
  $v14.Add('stored_chain_hash=' + $record.stored_chain_hash)
  $v14.Add('stored_chain_integrity_hash=' + $record.stored_chain_integrity_hash)
  $v14.Add('computed_chain_hash=' + $record.computed_chain_hash)
  $v14.Add('integrity_verification_result=' + $record.integrity_verification_result)
  $v14.Add('resolved_active_policy_version=' + $record.resolved_active_policy_version)
  $v14.Add('resolved_historical_policy_versions=' + $record.resolved_historical_policy_versions)
  $v14.Add('comparison_allowed=' + $record.comparison_allowed)
  $v14.Add('fallback_or_remapping_occurred=' + $record.fallback_occurred)
  if (-not [string]::IsNullOrWhiteSpace($record.mismatch_fields)) {
    $v14.Add('mismatch_fields=' + $record.mismatch_fields)
  }
  $v14.Add('')
}
$v14.Add('--- CASE D VERSION LOAD AUDITABILITY ---')
$v14.Add('requested_chain_version=v1_and_v2')
$v14.Add('selected_chain_version_v1=' + $selectionA.selected_chain_version)
$v14.Add('selected_chain_file_v1=' + $selectionA.selected_chain_file_rel)
$v14.Add('selected_chain_integrity_reference_file_v1=' + $selectionA.selected_integrity_file_rel)
$v14.Add('selected_chain_version_v2=' + $selectionB.selected_chain_version)
$v14.Add('selected_chain_file_v2=' + $selectionB.selected_chain_file_rel)
$v14.Add('selected_chain_integrity_reference_file_v2=' + $selectionB.selected_integrity_file_rel)
$v14.Add('version_load_auditability=' + $caseDPass)
$v14.Add('fallback_or_remapping_occurred=False')
$v14.Add('')
$v14.Add('--- CASE E HISTORICAL ACTIVE-CHAIN USABILITY ---')
$v14.Add('requested_chain_version=' + $selectionA.requested_chain_version)
$v14.Add('selected_chain_version=' + $selectionA.selected_chain_version)
$v14.Add('selected_chain_state=' + $selectionA.chain_state)
$v14.Add('resolved_active_policy_version=' + $chainA.resolved_active_policy_version)
$v14.Add('resolved_historical_policy_versions=' + $chainA.resolved_historical_policy_versions)
$v14.Add('historical_active_chain_usable=' + $caseEPass)
$v14.Add('fallback_or_remapping_occurred=' + $selectionA.fallback_occurred)
$v14.Add('')
$v14.Add('--- CASE G EXPLICIT HISTORICAL POLICY SELECTION STILL SEPARATE ---')
$v14.Add('requested_chain_version=v2')
$v14.Add('requested_policy_mode=explicit')
$v14.Add('requested_policy_version=' + $historicalPolicyVersion)
$v14.Add('selected_policy_file=' + $(if($null -ne $explicitPolicyIntegrity){$explicitPolicyIntegrity.selected_policy_file}else{'N/A'}))
$v14.Add('selected_integrity_file=' + $(if($null -ne $explicitPolicyIntegrity){$explicitPolicyIntegrity.selected_integrity_file}else{'N/A'}))
$v14.Add('policy_integrity_result=' + $(if($null -ne $explicitPolicyIntegrity){$explicitPolicyIntegrity.reason}else{'N/A'}))
$v14.Add('comparison_allowed=' + $(if($null -ne $explicitPolicyIntegrity){$explicitPolicyIntegrity.comparison_allowed}else{'False'}))
$v14.Add('fallback_or_remapping_occurred=' + $(if($null -ne $explicitPolicySelection){$explicitPolicySelection.fallback_occurred}else{'False'}))
$v14.Add('result=' + $(if($caseGPass){'PASS'}else{'FAIL'}))
$v14.Add('')
$v14.Add('--- GATE ---')
$v14.Add('GATE=' + $gateStr)
if (-not $gatePass) {
  foreach ($reason in $gateReasons) {
    $v14.Add('gate_fail_reason=' + $reason)
  }
}
Set-Content -Path (Join-Path $pfDir '14_validation_results.txt') -Value $v14 -Encoding UTF8

Set-Content -Path (Join-Path $pfDir '15_behavior_summary.txt') -Value @(
  'how_active_chain_version_selection_works=the_runner_uses_an_explicit_version_catalog_and_requires_a_requested_chain_version_to_resolve_the_exact_chain_file_and_integrity_reference_file'
  'how_active_chain_v1_and_v2_are_independently_loaded=v1_loads_tools/phase43_0/policy_history_chain.json_with_tools/phase43_3/active_policy_chain_integrity_reference.json_while_v2_loads_tools/phase43_4/policy_history_chain_rotated_v2.json_with_tools/phase43_4/active_policy_chain_integrity_reference_v2.json'
  'how_version_specific_chain_integrity_verification_works=the_selected_integrity_reference_must_target_the_selected_chain_file_and_its_expected_hash_must_match_before_default_resolution_is_allowed'
  'how_wrong_active_chain_version_comparison_is_detected=using_v1_chain_with_v2_integrity_reference_fails_due_to_reference_target_mismatch_or_hash_mismatch_and_the_mismatch_field_is_recorded'
  'how_invalid_active_chain_version_requests_are_rejected=unregistered_requested_versions_fail_deterministically_with_chain_version_not_registered_and_no_fallback'
  'how_historical_active_chain_usability_was_proven=explicit_selection_of_chain_v1_validates_successfully_and_resolves_default_active_policy_behavior_without_using_latest_autopick'
  'how_this_remains_separate_from_explicit_historical_policy_selection=chain_version_selection_chooses_which_chain_material_to_load_while_policy_selection_still_separately_targets_a_historical_policy_version_inside_the_selected_chain'
  'why_disabled_remained_inert=the_phase_only_adds_runner_side_selection_and_validation_logic'
  'why_baseline_mode_remained_unchanged=the_phase_does_not_modify_runtime_semantics_baseline_files_or_ui_layout'
) -Encoding UTF8

$refLines = New-Object System.Collections.Generic.List[string]
foreach ($record in @($chainA, $chainB, $chainF)) {
  $refLines.Add('requested_active_chain_version=' + $record.requested_chain_version)
  $refLines.Add('selected_active_chain_version=' + $record.selected_chain_version)
  $refLines.Add('selected_chain_file_path=' + $record.selected_chain_file)
  $refLines.Add('selected_chain_integrity_reference_file_path=' + $record.selected_integrity_file)
  $refLines.Add('stored_chain_hash=' + $record.stored_chain_hash)
  $refLines.Add('stored_chain_integrity_hash=' + $record.stored_chain_integrity_hash)
  $refLines.Add('integrity_verification_result=' + $record.integrity_verification_result)
  $refLines.Add('resolved_active_policy_version_from_selected_chain=' + $record.resolved_active_policy_version)
  $refLines.Add('resolved_historical_policy_versions_from_selected_chain=' + $record.resolved_historical_policy_versions)
  $refLines.Add('fallback_occurred=' + $record.fallback_occurred)
  $refLines.Add('')
}
Set-Content -Path (Join-Path $pfDir '16_active_chain_version_reference_record.txt') -Value $refLines -Encoding UTF8

Set-Content -Path (Join-Path $pfDir '17_wrong_active_chain_version_mismatch_evidence.txt') -Value @(
  ('requested_chain_version=' + $chainC.requested_chain_version)
  ('files_actually_loaded=' + $chainC.selected_chain_file + ' | ' + $chainC.selected_integrity_file)
  'mismatch_introduced=v1_chain_file_loaded_with_v2_integrity_reference'
  'expected_result=FAIL'
  ('actual_failure_result=' + $chainC.reason)
  ('mismatch_fields_identified=' + $chainC.mismatch_fields)
  ('failure_is_correct_and_deterministic=' + $caseCPass)
  ('fallback_or_remapping_occurred=' + $chainC.fallback_occurred)
) -Encoding UTF8

$gateLines = @('PHASE=43.5', ('GATE=' + $gateStr), ('timestamp=' + $ts))
if (-not $gatePass) {
  foreach ($reason in $gateReasons) {
    $gateLines += ('FAIL_REASON=' + $reason)
  }
}
Set-Content -Path (Join-Path $pfDir '98_gate_phase43_5.txt') -Value $gateLines -Encoding UTF8

$zipPath = "$pfDir.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -Force $zipPath }
$tmpDir = "$pfDir`_copy"
if (Test-Path -LiteralPath $tmpDir) { Remove-Item -Recurse -Force $tmpDir }
New-Item -ItemType Directory -Path $tmpDir | Out-Null
Get-ChildItem -Path $pfDir -File | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $tmpDir $_.Name) -Force
}
Compress-Archive -Path (Join-Path $tmpDir '*') -DestinationPath $zipPath -Force
Remove-Item -Recurse -Force $tmpDir

Write-Output ("PF={0}" -f $pfDir)
Write-Output ("ZIP={0}" -f $zipPath)
Write-Output ("GATE={0}" -f $gateStr)
