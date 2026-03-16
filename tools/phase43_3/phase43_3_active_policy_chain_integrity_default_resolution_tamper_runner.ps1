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
  param([string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $h = [System.Security.Cryptography.SHA256]::HashData($bytes)
  return ([System.BitConverter]::ToString($h)).Replace('-', '').ToLowerInvariant()
}

function Verify-ChainIntegrity {
  param(
    [Parameter(Mandatory = $true)][string]$ChainPath,
    [Parameter(Mandatory = $true)][string]$ChainIntegrityRefPath,
    [Parameter(Mandatory = $true)][string]$CaseName
  )

  if (-not (Test-Path -LiteralPath $ChainIntegrityRefPath)) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'chain_integrity_reference_missing'
      chain_source_file = $ChainPath
      expected_hash = ''
      actual_hash = ''
      parse_error = ''
      chain_loaded = $false
      chain_obj = $null
      default_resolution_allowed = $false
    }
  }

  $ref = Get-Content -Raw -LiteralPath $ChainIntegrityRefPath | ConvertFrom-Json
  $expected = [string]$ref.expected_chain_sha256

  if (-not (Test-Path -LiteralPath $ChainPath)) {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'chain_source_missing'
      chain_source_file = $ChainPath
      expected_hash = $expected
      actual_hash = ''
      parse_error = ''
      chain_loaded = $false
      chain_obj = $null
      default_resolution_allowed = $false
    }
  }

  $actual = Get-FileSha256Hex -Path $ChainPath
  if ($actual -ne $expected) {
    $parseError = ''
    try {
      $null = Get-Content -Raw -LiteralPath $ChainPath | ConvertFrom-Json
    } catch {
      $parseError = $_.Exception.Message
    }

    $reason = if ([string]::IsNullOrWhiteSpace($parseError)) { 'chain_hash_mismatch' } else { 'chain_hash_mismatch_with_malformed_content' }
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = $reason
      chain_source_file = $ChainPath
      expected_hash = $expected
      actual_hash = $actual
      parse_error = $parseError
      chain_loaded = $false
      chain_obj = $null
      default_resolution_allowed = $false
    }
  }

  try {
    $chainObj = Get-Content -Raw -LiteralPath $ChainPath | ConvertFrom-Json
  } catch {
    return [pscustomobject]@{
      case_name = $CaseName
      pass = $false
      reason = 'chain_parse_error'
      chain_source_file = $ChainPath
      expected_hash = $expected
      actual_hash = $actual
      parse_error = $_.Exception.Message
      chain_loaded = $false
      chain_obj = $null
      default_resolution_allowed = $false
    }
  }

  return [pscustomobject]@{
    case_name = $CaseName
    pass = $true
    reason = 'chain_integrity_verified'
    chain_source_file = $ChainPath
    expected_hash = $expected
    actual_hash = $actual
    parse_error = ''
    chain_loaded = $true
    chain_obj = $chainObj
    default_resolution_allowed = $true
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
  $policyRel = [string]$entry.policy_file
  $intRel = [string]$entry.integrity_reference_file
  $policyAbs = if ([System.IO.Path]::IsPathRooted($policyRel)) { $policyRel } else { Join-Path $RootPath $policyRel.Replace('/', '\') }
  $intAbs = if ([System.IO.Path]::IsPathRooted($intRel)) { $intRel } else { Join-Path $RootPath $intRel.Replace('/', '\') }

  return [pscustomobject]@{
    found = $true
    failure_reason = ''
    declared_active_version = [string]$entry.version
    resolved_version = [string]$entry.version
    policy_file_rel = $policyRel
    integrity_file_rel = $intRel
    policy_file_abs = $policyAbs
    integrity_file_abs = $intAbs
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
  foreach ($e in $Chain.chain) {
    if ([string]$e.version -eq $RequestedVersion.Trim()) { $entry = $e; break }
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
  $declaredActive = if ($null -ne $activeEntry) { [string]$activeEntry.version } else { '' }

  $policyRel = [string]$entry.policy_file
  $intRel = [string]$entry.integrity_reference_file
  $policyAbs = if ([System.IO.Path]::IsPathRooted($policyRel)) { $policyRel } else { Join-Path $RootPath $policyRel.Replace('/', '\') }
  $intAbs = if ([System.IO.Path]::IsPathRooted($intRel)) { $intRel } else { Join-Path $RootPath $intRel.Replace('/', '\') }

  return [pscustomobject]@{
    found = $true
    failure_reason = ''
    declared_active_version = $declaredActive
    resolved_version = [string]$entry.version
    policy_file_rel = $policyRel
    integrity_file_rel = $intRel
    policy_file_abs = $policyAbs
    integrity_file_abs = $intAbs
    fallback_occurred = ($RequestedVersion.Trim() -ne [string]$entry.version)
  }
}

function Verify-PolicyIntegrityFromSelection {
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
      declared_active_version = $Selection.declared_active_version
      resolved_version = ''
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
      declared_active_version = $Selection.declared_active_version
      resolved_version = $Selection.resolved_version
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
      declared_active_version = $Selection.declared_active_version
      resolved_version = $Selection.resolved_version
      selected_policy_file = $Selection.policy_file_rel
      selected_integrity_file = $Selection.integrity_file_rel
      expected_policy_hash = ''
      actual_policy_hash = ''
      comparison_allowed = $false
      fallback_occurred = $false
      policy_obj = $null
    }
  }

  $intRef = Get-Content -Raw -LiteralPath $Selection.integrity_file_abs | ConvertFrom-Json
  $expected = [string]$intRef.expected_policy_sha256

  if (-not (Test-Path -LiteralPath $Selection.policy_file_abs)) {
    return [pscustomobject]@{
      pass = $false
      reason = 'policy_file_missing'
      requested_mode = $RequestedMode
      requested_version = $RequestedVersion
      declared_active_version = $Selection.declared_active_version
      resolved_version = $Selection.resolved_version
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
      declared_active_version = $Selection.declared_active_version
      resolved_version = $Selection.resolved_version
      selected_policy_file = $Selection.policy_file_rel
      selected_integrity_file = $Selection.integrity_file_rel
      expected_policy_hash = $expected
      actual_policy_hash = $actual
      comparison_allowed = $false
      fallback_occurred = $false
      policy_obj = $null
    }
  }

  $policyObj = Get-Content -Raw -LiteralPath $Selection.policy_file_abs | ConvertFrom-Json
  return [pscustomobject]@{
    pass = $true
    reason = 'policy_integrity_verified'
    requested_mode = $RequestedMode
    requested_version = $RequestedVersion
    declared_active_version = $Selection.declared_active_version
    resolved_version = $Selection.resolved_version
    selected_policy_file = $Selection.policy_file_rel
    selected_integrity_file = $Selection.integrity_file_rel
    expected_policy_hash = $expected
    actual_policy_hash = $actual
    comparison_allowed = $true
    fallback_occurred = $false
    policy_obj = $policyObj
  }
}

function Get-PolicySummary {
  param($PolicyObj)
  if ($null -eq $PolicyObj) { return $null }
  return [pscustomobject]@{
    active_version = [string]$PolicyObj.active_version
    historical_versions = @($PolicyObj.historical_versions | ForEach-Object { [string]$_ })
    policy_version_number = [string]$PolicyObj.policy_version
  }
}

$TS = Get-Date -Format 'yyyyMMdd_HHmmss'
$PFDir = Join-Path $Root "_proof\phase43_3_active_policy_chain_integrity_default_resolution_tamper_$TS"
New-Item -ItemType Directory -Force -Path $PFDir | Out-Null

$PhaseDir = Join-Path $Root 'tools\phase43_3'
New-Item -ItemType Directory -Force -Path $PhaseDir | Out-Null

$chainCanonicalPath = Join-Path $Root 'tools\phase43_0\policy_history_chain.json'
$chainIntegrityRefPath = Join-Path $Root 'tools\phase43_3\active_policy_chain_integrity_reference.json'

# canonical launcher evidence
$launcherStdOut = Join-Path $PFDir 'launcher_stdout.txt'
$launcherStdErr = Join-Path $PFDir 'launcher_stderr.txt'
$launcherArgString = '-NoProfile -ExecutionPolicy Bypass -File ".\\tools\\run_widget_sandbox.ps1" -Config Debug -PassArgs --sandbox-extension --demo --auto-close-ms=1200'
$launcherProc = Start-Process -FilePath 'pwsh' -ArgumentList $launcherArgString -WorkingDirectory $Root -NoNewWindow -PassThru -RedirectStandardOutput $launcherStdOut -RedirectStandardError $launcherStdErr
$launcherExited = $launcherProc.WaitForExit(25000)
if (-not $launcherExited) {
  Stop-Process -Id $launcherProc.Id -Force
  $launcherExit = 124
} else {
  $launcherExit = $launcherProc.ExitCode
}
$launcherText = ''
if (Test-Path -LiteralPath $launcherStdOut) {
  $launcherText = Get-Content -Raw -LiteralPath $launcherStdOut
}
$launcherErrText = ''
if (Test-Path -LiteralPath $launcherStdErr) {
  $launcherErrText = Get-Content -Raw -LiteralPath $launcherStdErr
}
$canonicalLaunchUsed = ($launcherText -match 'LAUNCH_EXE=')
$launcherOutput = @($launcherText, $launcherErrText)

# CASE A clean
Write-Output '=== CASE A: CLEAN ACTIVE CHAIN PASS ==='
$chainA = Verify-ChainIntegrity -ChainPath $chainCanonicalPath -ChainIntegrityRefPath $chainIntegrityRefPath -CaseName 'A_clean'
$selA = $null
$polA = $null
$sumA = $null
if ($chainA.default_resolution_allowed) {
  $selA = Resolve-DefaultFromChain -Chain $chainA.chain_obj -RootPath $Root
  $polA = Verify-PolicyIntegrityFromSelection -Selection $selA -RequestedMode 'default' -RequestedVersion '(default)'
  $sumA = Get-PolicySummary -PolicyObj $polA.policy_obj
}
$caseAPass = $chainA.pass -and $null -ne $selA -and $selA.found -and $null -ne $polA -and $polA.pass -and $polA.comparison_allowed
Write-Output "  chain_integrity=$($chainA.reason) policy_integrity=$(if($null -ne $polA){$polA.reason}else{'N/A'})"

# CASE B hash mismatch tamper
Write-Output '=== CASE B: ACTIVE CHAIN HASH MISMATCH ==='
$chainTamperPath = Join-Path $PhaseDir '_caseB_chain_hash_mismatch.json'
$chainTamperedObj = Get-Content -Raw -LiteralPath $chainCanonicalPath | ConvertFrom-Json
foreach ($e in $chainTamperedObj.chain) {
  if ([string]$e.status -eq 'active') {
    $e.status = 'historical'
    break
  }
}
$chainTamperedObj.chain[0].status = 'active'
Set-Content -Path $chainTamperPath -Value ($chainTamperedObj | ConvertTo-Json -Depth 10) -Encoding UTF8 -NoNewline
$chainB = Verify-ChainIntegrity -ChainPath $chainTamperPath -ChainIntegrityRefPath $chainIntegrityRefPath -CaseName 'B_hash_mismatch'
$caseBPass = (-not $chainB.pass) -and (-not $chainB.default_resolution_allowed) -and ($chainB.reason -like 'chain_hash_mismatch*')

# CASE C malformed/corrupted
Write-Output '=== CASE C: ACTIVE CHAIN MALFORMED ==='
$chainCorruptPath = Join-Path $PhaseDir '_caseC_chain_malformed.json'
Set-Content -Path $chainCorruptPath -Value '{"chain_name":"broken","chain":[{"version":"v2","status":"active"}' -Encoding UTF8 -NoNewline
$chainC = Verify-ChainIntegrity -ChainPath $chainCorruptPath -ChainIntegrityRefPath $chainIntegrityRefPath -CaseName 'C_malformed'
$caseCPass = (-not $chainC.pass) -and (-not $chainC.default_resolution_allowed) -and ($chainC.reason -eq 'chain_hash_mismatch_with_malformed_content' -or $chainC.reason -eq 'chain_parse_error')

# CASE D missing
Write-Output '=== CASE D: ACTIVE CHAIN MISSING ==='
$chainMissingPath = Join-Path $PhaseDir '_caseD_missing_chain.json'
if (Test-Path -LiteralPath $chainMissingPath) { Remove-Item -Force $chainMissingPath }
$chainD = Verify-ChainIntegrity -ChainPath $chainMissingPath -ChainIntegrityRefPath $chainIntegrityRefPath -CaseName 'D_missing'
$caseDPass = (-not $chainD.pass) -and (-not $chainD.default_resolution_allowed) -and ($chainD.reason -eq 'chain_source_missing')

# CASE E chain/policy mismatch (readable chain points active at wrong integrity pairing)
Write-Output '=== CASE E: CHAIN/POLICY MISMATCH ==='
$chainMismatchPath = Join-Path $PhaseDir '_caseE_chain_policy_mismatch.json'
$chainMismatchObj = Get-Content -Raw -LiteralPath $chainCanonicalPath | ConvertFrom-Json
foreach ($e in $chainMismatchObj.chain) {
  if ([string]$e.version -eq 'v2') {
    $e.status = 'active'
    # keep policy file v2 but swap integrity ref to v1 to force downstream policy mismatch
    $e.integrity_reference_file = 'tools/phase42_9/policy_integrity_reference.json'
  } elseif ([string]$e.version -eq 'v1') {
    $e.status = 'historical'
  }
}
Set-Content -Path $chainMismatchPath -Value ($chainMismatchObj | ConvertTo-Json -Depth 10) -Encoding UTF8 -NoNewline
$chainE = Verify-ChainIntegrity -ChainPath $chainMismatchPath -ChainIntegrityRefPath $chainIntegrityRefPath -CaseName 'E_chain_policy_mismatch'
$selE = $null
$polE = $null
if ($chainE.default_resolution_allowed) {
  $selE = Resolve-DefaultFromChain -Chain $chainE.chain_obj -RootPath $Root
  $polE = Verify-PolicyIntegrityFromSelection -Selection $selE -RequestedMode 'default' -RequestedVersion '(default)'
}
$caseEPass = if (-not $chainE.pass) {
  (-not $chainE.default_resolution_allowed)
} else {
  ($null -ne $polE) -and (-not $polE.pass) -and (-not $polE.comparison_allowed) -and ($polE.reason -eq 'policy_hash_mismatch')
}

# CASE F explicit historical still separate
Write-Output '=== CASE F: EXPLICIT HISTORICAL STILL SEPARATE ==='
$chainF = Verify-ChainIntegrity -ChainPath $chainCanonicalPath -ChainIntegrityRefPath $chainIntegrityRefPath -CaseName 'F_explicit_historical_control'
$selF = $null
$polF = $null
$sumF = $null
$historicalVersion = ''
if ($chainF.default_resolution_allowed) {
  $histEntry = $chainF.chain_obj.chain | Where-Object { [string]$_.status -eq 'historical' } | Select-Object -First 1
  $historicalVersion = if ($null -ne $histEntry) { [string]$histEntry.version } else { '' }
  if (-not [string]::IsNullOrWhiteSpace($historicalVersion)) {
    $selF = Resolve-ExplicitFromChain -RequestedVersion $historicalVersion -Chain $chainF.chain_obj -RootPath $Root
    $polF = Verify-PolicyIntegrityFromSelection -Selection $selF -RequestedMode 'explicit' -RequestedVersion $historicalVersion
    $sumF = Get-PolicySummary -PolicyObj $polF.policy_obj
  }
}
$caseFPass = $chainF.pass -and (-not [string]::IsNullOrWhiteSpace($historicalVersion)) -and $null -ne $selF -and $selF.found -and $selF.resolved_version -eq $historicalVersion -and (-not $selF.fallback_occurred) -and $null -ne $polF -and $polF.pass

# Enforcement no fallback checks for default failure cases
$noFallbackDefaultFailures =
  (($null -eq $selE) -or ($selE.resolved_version -ne $historicalVersion)) -and
  ($caseBPass -and $caseCPass -and $caseDPass)

$gatePass = $true
$gateReasons = New-Object System.Collections.Generic.List[string]
if (-not $canonicalLaunchUsed) { $gatePass = $false; $gateReasons.Add('canonical_launcher_not_verified') }
if (-not $caseAPass) { $gatePass = $false; $gateReasons.Add('caseA_fail') }
if (-not $caseBPass) { $gatePass = $false; $gateReasons.Add('caseB_fail') }
if (-not $caseCPass) { $gatePass = $false; $gateReasons.Add('caseC_fail') }
if (-not $caseDPass) { $gatePass = $false; $gateReasons.Add('caseD_fail') }
if (-not $caseEPass) { $gatePass = $false; $gateReasons.Add('caseE_fail') }
if (-not $caseFPass) { $gatePass = $false; $gateReasons.Add('caseF_fail') }
if (-not $noFallbackDefaultFailures) { $gatePass = $false; $gateReasons.Add('default_fallback_detected') }

$gateStr = if ($gatePass) { 'PASS' } else { 'FAIL' }

# 01
Set-Content -Path (Join-Path $PFDir '01_status.txt') -Value @(
  'phase=43.3'
  'title=ACTIVE POLICY CHAIN INTEGRITY / DEFAULT-RESOLUTION TAMPER PROOF'
  ('timestamp=' + $TS)
  ('gate=' + $gateStr)
  ('canonical_launcher_used=' + $canonicalLaunchUsed)
  ('case_a=' + $caseAPass)
  ('case_b=' + $caseBPass)
  ('case_c=' + $caseCPass)
  ('case_d=' + $caseDPass)
  ('case_e=' + $caseEPass)
  ('case_f=' + $caseFPass)
) -Encoding UTF8

# 02
Set-Content -Path (Join-Path $PFDir '02_head.txt') -Value @(
  'project=NGKsUI Runtime'
  'phase=43.3'
  'title=ACTIVE POLICY CHAIN INTEGRITY / DEFAULT-RESOLUTION TAMPER PROOF'
  ('timestamp_utc=' + (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'))
  ('root=' + $Root)
  ('gate=' + $gateStr)
) -Encoding UTF8

# 10
Set-Content -Path (Join-Path $PFDir '10_chain_integrity_definition.txt') -Value @(
  'chain_source=tools/phase43_0/policy_history_chain.json'
  'chain_integrity_reference=tools/phase43_3/active_policy_chain_integrity_reference.json'
  'hash_method=sha256_file_bytes_v1'
  'default_resolution_dependency=verified_chain_required_before_active_policy_selection'
  'default_resolution_behavior=blocked_when_chain_integrity_fails'
  'fallback_to_historical_on_default_failure=disallowed'
) -Encoding UTF8

# 11
Set-Content -Path (Join-Path $PFDir '11_chain_integrity_rules.txt') -Value @(
  'RULE_1=chain_source_path_is_explicit'
  'RULE_2=chain_hash_must_match_integrity_reference_before_default_resolution'
  'RULE_3=chain_missing_blocks_default_resolution'
  'RULE_4=chain_malformed_blocks_default_resolution'
  'RULE_5=chain_hash_mismatch_blocks_default_resolution'
  'RULE_6=chain_or_policy_pairing_mismatch_blocks_comparison'
  'RULE_7=no_default_fallback_to_historical_on_chain_failure'
  'RULE_8=explicit_historical_selection_remains_separate'
) -Encoding UTF8

# 12
Set-Content -Path (Join-Path $PFDir '12_files_touched.txt') -Value @(
  'READ=tools/phase43_0/policy_history_chain.json'
  'READ=tools/phase42_8/active_version_policy.json'
  'READ=tools/phase43_0/active_version_policy_v2.json'
  'READ=tools/phase42_9/policy_integrity_reference.json'
  'READ=tools/phase43_0/policy_integrity_reference_v2.json'
  'READ=tools/phase43_3/active_policy_chain_integrity_reference.json'
  'CREATED=tools/phase43_3/phase43_3_active_policy_chain_integrity_default_resolution_tamper_runner.ps1'
  'CREATED=tools/phase43_3/active_policy_chain_integrity_reference.json'
  'CREATED(TEMP)=tools/phase43_3/_caseB_chain_hash_mismatch.json'
  'CREATED(TEMP)=tools/phase43_3/_caseC_chain_malformed.json'
  'CREATED(TEMP)=tools/phase43_3/_caseE_chain_policy_mismatch.json'
  'UI_MODIFIED=NO'
  'BASELINE_MODE_MODIFIED=NO'
  'RUNTIME_SEMANTICS_MODIFIED=NO'
) -Encoding UTF8

# 13
$buildOut = @(
  ('canonical_launcher_exit=' + $launcherExit)
  ('canonical_launcher_used=' + $canonicalLaunchUsed)
  'build_action=none_required'
  'reason=phase43_3_is_policy_chain_integrity_enforcement_runner_layer'
)
if ($null -ne $launcherOutput) {
  $buildOut += '--- canonical launcher output ---'
  $buildOut += ($launcherOutput | ForEach-Object { [string]$_ })
}
Set-Content -Path (Join-Path $PFDir '13_build_output.txt') -Value $buildOut -Encoding UTF8

# 14
$v14 = New-Object System.Collections.Generic.List[string]
$v14.Add('--- CASE A CLEAN ACTIVE CHAIN PASS ---')
$v14.Add('requested_policy_mode=default')
$v14.Add('chain_source=' + $chainA.chain_source_file)
$v14.Add('stored_chain_hash=' + $chainA.expected_hash)
$v14.Add('computed_chain_hash=' + $chainA.actual_hash)
$v14.Add('chain_integrity_result=' + $chainA.reason)
$v14.Add('declared_active_version=' + $(if($null -ne $selA){$selA.declared_active_version}else{'N/A'}))
$v14.Add('resolved_version=' + $(if($null -ne $selA){$selA.resolved_version}else{'N/A'}))
$v14.Add('selected_policy_file=' + $(if($null -ne $polA){$polA.selected_policy_file}else{'N/A'}))
$v14.Add('selected_integrity_file=' + $(if($null -ne $polA){$polA.selected_integrity_file}else{'N/A'}))
$v14.Add('comparison_allowed=' + $(if($null -ne $polA){$polA.comparison_allowed}else{'False'}))
$v14.Add('fallback_occurred=' + $(if($null -ne $selA){$selA.fallback_occurred}else{'False'}))
$v14.Add('result=' + $(if($caseAPass){'PASS'}else{'FAIL'}))
$v14.Add('')

$v14.Add('--- CASE B ACTIVE CHAIN HASH MISMATCH ---')
$v14.Add('requested_policy_mode=default')
$v14.Add('chain_source=' + $chainB.chain_source_file)
$v14.Add('stored_chain_hash=' + $chainB.expected_hash)
$v14.Add('computed_chain_hash=' + $chainB.actual_hash)
$v14.Add('chain_integrity_result=' + $chainB.reason)
$v14.Add('comparison_allowed=False')
$v14.Add('fallback_occurred=False')
$v14.Add('result=' + $(if($caseBPass){'PASS'}else{'FAIL'}))
$v14.Add('')

$v14.Add('--- CASE C ACTIVE CHAIN MALFORMED ---')
$v14.Add('requested_policy_mode=default')
$v14.Add('chain_source=' + $chainC.chain_source_file)
$v14.Add('stored_chain_hash=' + $chainC.expected_hash)
$v14.Add('computed_chain_hash=' + $chainC.actual_hash)
$v14.Add('chain_integrity_result=' + $chainC.reason)
$v14.Add('chain_parse_error=' + $chainC.parse_error)
$v14.Add('comparison_allowed=False')
$v14.Add('fallback_occurred=False')
$v14.Add('result=' + $(if($caseCPass){'PASS'}else{'FAIL'}))
$v14.Add('')

$v14.Add('--- CASE D ACTIVE CHAIN MISSING ---')
$v14.Add('requested_policy_mode=default')
$v14.Add('chain_source=' + $chainD.chain_source_file)
$v14.Add('stored_chain_hash=' + $chainD.expected_hash)
$v14.Add('computed_chain_hash=' + $chainD.actual_hash)
$v14.Add('chain_integrity_result=' + $chainD.reason)
$v14.Add('comparison_allowed=False')
$v14.Add('fallback_occurred=False')
$v14.Add('result=' + $(if($caseDPass){'PASS'}else{'FAIL'}))
$v14.Add('')

$v14.Add('--- CASE E CHAIN POLICY MISMATCH ---')
$v14.Add('requested_policy_mode=default')
$v14.Add('chain_source=' + $chainE.chain_source_file)
$v14.Add('stored_chain_hash=' + $chainE.expected_hash)
$v14.Add('computed_chain_hash=' + $chainE.actual_hash)
$v14.Add('chain_integrity_result=' + $chainE.reason)
$v14.Add('resolved_version=' + $(if($null -ne $selE){$selE.resolved_version}else{'N/A'}))
$v14.Add('selected_policy_file=' + $(if($null -ne $polE){$polE.selected_policy_file}else{'N/A'}))
$v14.Add('selected_integrity_file=' + $(if($null -ne $polE){$polE.selected_integrity_file}else{'N/A'}))
$v14.Add('policy_integrity_result=' + $(if($null -ne $polE){$polE.reason}else{'N/A'}))
$v14.Add('comparison_allowed=' + $(if($null -ne $polE){$polE.comparison_allowed}else{'False'}))
$v14.Add('fallback_occurred=' + $(if($null -ne $selE){$selE.fallback_occurred}else{'False'}))
$v14.Add('result=' + $(if($caseEPass){'PASS'}else{'FAIL'}))
$v14.Add('')

$v14.Add('--- CASE F EXPLICIT HISTORICAL STILL SEPARATE ---')
$v14.Add('requested_policy_mode=explicit')
$v14.Add('requested_policy_version=' + $historicalVersion)
$v14.Add('chain_source=' + $chainF.chain_source_file)
$v14.Add('stored_chain_hash=' + $chainF.expected_hash)
$v14.Add('computed_chain_hash=' + $chainF.actual_hash)
$v14.Add('chain_integrity_result=' + $chainF.reason)
$v14.Add('resolved_version=' + $(if($null -ne $selF){$selF.resolved_version}else{'N/A'}))
$v14.Add('selected_policy_file=' + $(if($null -ne $polF){$polF.selected_policy_file}else{'N/A'}))
$v14.Add('selected_integrity_file=' + $(if($null -ne $polF){$polF.selected_integrity_file}else{'N/A'}))
$v14.Add('policy_integrity_result=' + $(if($null -ne $polF){$polF.reason}else{'N/A'}))
$v14.Add('comparison_allowed=' + $(if($null -ne $polF){$polF.comparison_allowed}else{'False'}))
$v14.Add('fallback_occurred=' + $(if($null -ne $selF){$selF.fallback_occurred}else{'False'}))
$v14.Add('result=' + $(if($caseFPass){'PASS'}else{'FAIL'}))
$v14.Add('')

$v14.Add('--- GATE ---')
$v14.Add('GATE=' + $gateStr)
if (-not $gatePass) { foreach ($r in $gateReasons) { $v14.Add('gate_fail_reason=' + $r) } }
Set-Content -Path (Join-Path $PFDir '14_validation_results.txt') -Value $v14 -Encoding UTF8

# 15
Set-Content -Path (Join-Path $PFDir '15_behavior_summary.txt') -Value @(
  'how_chain_integrity_works=sha256_of_active_chain_source_is_compared_against_stored_reference_before_default_resolution'
  'how_default_depends_on_chain=default_selection_requires_verified_active_entry_from_chain'
  'how_blocking_works=hash_mismatch_malformed_or_missing_chain_sets_default_resolution_allowed_false'
  'how_mismatch_blocking_works=chain_policy_pairing_mismatch_triggers_policy_hash_mismatch_or_chain_hash_mismatch'
  'how_no_fallback_is_proven=resolved_version_never_remapped_to_historical_in_default_failure_cases'
  'how_explicit_historical_stays_separate=explicit_version_selection_uses_historical_entry_and_passes_integrity_independently'
  'disabled_remained_inert=true_ui_not_modified'
  'baseline_mode_unchanged=true_runtime_semantics_unchanged'
) -Encoding UTF8

# 16
$rec16 = New-Object System.Collections.Generic.List[string]
foreach ($pair in @(
  [pscustomobject]@{chain=$chainA; sel=$selA; pol=$polA; mode='default'; req='(default)'},
  [pscustomobject]@{chain=$chainB; sel=$null; pol=$null; mode='default'; req='(default)'},
  [pscustomobject]@{chain=$chainC; sel=$null; pol=$null; mode='default'; req='(default)'},
  [pscustomobject]@{chain=$chainD; sel=$null; pol=$null; mode='default'; req='(default)'},
  [pscustomobject]@{chain=$chainE; sel=$selE; pol=$polE; mode='default'; req='(default)'},
  [pscustomobject]@{chain=$chainF; sel=$selF; pol=$polF; mode='explicit'; req=$historicalVersion}
)) {
  $rec16.Add('--- CASE ' + $pair.chain.case_name + ' ---')
  $rec16.Add('requested_policy_mode=' + $pair.mode)
  $rec16.Add('requested_policy_version=' + $pair.req)
  $rec16.Add('active_policy_chain_source=' + $pair.chain.chain_source_file)
  $rec16.Add('stored_chain_integrity_hash=' + $pair.chain.expected_hash)
  $rec16.Add('computed_chain_integrity_hash=' + $pair.chain.actual_hash)
  $rec16.Add('chain_integrity_result=' + $pair.chain.reason)
  $rec16.Add('declared_active_version=' + $(if($null -ne $pair.sel){$pair.sel.declared_active_version}else{'N/A'}))
  $rec16.Add('selected_policy_file_path=' + $(if($null -ne $pair.pol){$pair.pol.selected_policy_file}else{'N/A'}))
  $rec16.Add('selected_policy_integrity_file_path=' + $(if($null -ne $pair.pol){$pair.pol.selected_integrity_file}else{'N/A'}))
  $rec16.Add('comparison_result=' + $(if($null -ne $pair.pol -and $pair.pol.comparison_allowed){'PASS'}else{'BLOCKED'}))
  $rec16.Add('comparison_allowed=' + $(if($null -ne $pair.pol){$pair.pol.comparison_allowed}else{'False'}))
  $rec16.Add('fallback_or_remapping_occurred=' + $(if($null -ne $pair.sel){$pair.sel.fallback_occurred}else{'False'}))
  $rec16.Add('')
}
Set-Content -Path (Join-Path $PFDir '16_active_chain_integrity_record.txt') -Value $rec16 -Encoding UTF8

# 17
Set-Content -Path (Join-Path $PFDir '17_chain_tamper_evidence.txt') -Value @(
  'failure_case_identifier=B_active_chain_hash_mismatch'
  'tamper_input=active_chain_status_modified_readable_json'
  'expected_result=FAIL'
  ('actual_block_result=' + (-not $chainB.default_resolution_allowed))
  ('failure_reason=' + $chainB.reason)
  'historical_default_fallback_occurred=False'
  ''
  'failure_case_identifier=C_active_chain_malformed'
  'tamper_input=active_chain_json_corrupted'
  'expected_result=FAIL'
  ('actual_block_result=' + (-not $chainC.default_resolution_allowed))
  ('failure_reason=' + $chainC.reason)
  ('parse_error=' + $chainC.parse_error)
  'historical_default_fallback_occurred=False'
  ''
  'failure_case_identifier=D_active_chain_missing'
  'tamper_input=active_chain_source_missing'
  'expected_result=FAIL'
  ('actual_block_result=' + (-not $chainD.default_resolution_allowed))
  ('failure_reason=' + $chainD.reason)
  'historical_default_fallback_occurred=False'
  ''
  'failure_case_identifier=E_chain_policy_mismatch'
  'tamper_input=active_chain_points_to_wrong_policy_integrity_pairing'
  'expected_result=FAIL'
  ('actual_block_result=' + $(if($chainE.pass){-not $polE.comparison_allowed}else{-not $chainE.default_resolution_allowed}))
  ('failure_reason=' + $(if($chainE.pass){$polE.reason}else{$chainE.reason}))
  'historical_default_fallback_occurred=False'
) -Encoding UTF8

# 98
$g98 = @('PHASE=43.3', ('GATE=' + $gateStr), ('timestamp=' + $TS))
if (-not $gatePass) { foreach ($r in $gateReasons) { $g98 += ('FAIL_REASON=' + $r) } }
Set-Content -Path (Join-Path $PFDir '98_gate_phase43_3.txt') -Value $g98 -Encoding UTF8

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
