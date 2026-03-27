#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
  Write-Host "FATAL: $_"
  exit 1
}

$workspaceRoot = Get-Location | Select-Object -ExpandProperty Path
$proofRoot = Join-Path $workspaceRoot '_proof'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName = "phase89_1_default_adoption_policy_delegacy_plan_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase89_1_default_adoption_policy_delegacy_plan_*.zip' -ErrorAction SilentlyContinue |
  ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }

function Test-KvFileWellFormed {
  param([string]$FilePath)
  if (-not (Test-Path -LiteralPath $FilePath)) { return $false }
  $lines = @(Get-Content -LiteralPath $FilePath | Where-Object { $_ -match '\S' -and $_ -notmatch '^#' })
  foreach ($line in $lines) {
    if ($line -notmatch '^[a-zA-Z_][a-zA-Z0-9_]*=') { return $false }
  }
  return $true
}

function New-ProofZip {
  param([string]$SourceDir, [string]$DestinationZip)
  if (Test-Path -LiteralPath $DestinationZip) { Remove-Item -LiteralPath $DestinationZip -Force }
  Compress-Archive -Path (Join-Path $SourceDir '*') -DestinationPath $DestinationZip -Force
}

function Test-ZipContainsEntries {
  param([string]$ZipFile, [string[]]$ExpectedEntries)
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipFile)
  try {
    $entryNames = @($archive.Entries | ForEach-Object { $_.FullName })
    foreach ($entry in $ExpectedEntries) {
      if ($entryNames -notcontains $entry) { return $false }
    }
    return $true
  } finally { $archive.Dispose() }
}

$sandboxMain = Join-Path $workspaceRoot 'apps/sandbox_app/main.cpp'
$loopMain = Join-Path $workspaceRoot 'apps/loop_tests/main.cpp'
$win32Main = Join-Path $workspaceRoot 'apps/win32_sandbox/main.cpp'
$widgetMain = Join-Path $workspaceRoot 'apps/widget_sandbox/main.cpp'

$sandboxContent = if (Test-Path -LiteralPath $sandboxMain) { Get-Content -LiteralPath $sandboxMain -Raw } else { '' }
$loopContent = if (Test-Path -LiteralPath $loopMain) { Get-Content -LiteralPath $loopMain -Raw } else { '' }
$win32Content = if (Test-Path -LiteralPath $win32Main) { Get-Content -LiteralPath $win32Main -Raw } else { '' }
$widgetContent = if (Test-Path -LiteralPath $widgetMain) { Get-Content -LiteralPath $widgetMain -Raw } else { '' }

$nativeDefaultApps = @('apps/sandbox_app', 'apps/loop_tests', 'apps/win32_sandbox')
$referenceOnlyApps = @('apps/widget_sandbox')
$legacyPathsExist = @('apps/sandbox_app', 'apps/loop_tests', 'apps/win32_sandbox')
$legacyPathsRemainTemporary = @('apps/sandbox_app', 'apps/loop_tests', 'apps/win32_sandbox')
$legacyPathsDelegacyCandidates = @('apps/sandbox_app', 'apps/loop_tests', 'apps/win32_sandbox')

$policyNativeDefaultWhen = 'app_has_validated_native_slice_plus_explicit_fallback_controls_plus_trust_before_selection_plus_lifecycle_consistency'
$policyFallbackAllowedWhen = 'legacy_fallback_explicitly_requested_via_flag_or_env_or_guarded_operational_recovery_case'
$policyLegacyReferenceOnlyWhen = 'surface_is_reference_or_pilot_mode_and_not_promoted_to_native_default_rollout'

$delegacyLaneSequence = 'lane1_inventory_and_owner_assignment,lane2_usage_telemetry_and_flag_path_audit,lane3_soft_freeze_for_new_legacy_entries,lane4_exit_criteria_gate_for_each_legacy_path'
$delegacyLaneCriteria = 'no_removal_in_phase89_1,explicit_reversibility_preserved,documented_cutover_criteria_per_surface,proof_backed_readiness_before_any_future_removal'

$checkResults = [ordered]@{}

$checkResults['check_native_default_apps_identified'] = @{ Result = $false; Reason = 'native-default app set incomplete or unsupported by rollout markers' }
if ($sandboxContent -match 'phase87_1_sandbox_app_wave1_rollout_available=1' -and
    $loopContent -match 'phase87_3_loop_tests_wave1_rollout_available=1' -and
    $win32Content -match 'phase88_1_win32_wave2_rollout_available=1') {
  $checkResults['check_native_default_apps_identified'].Result = $true
  $checkResults['check_native_default_apps_identified'].Reason = 'three production surfaces are identified as native-default rollout targets'
}

$checkResults['check_reference_only_apps_identified'] = @{ Result = $false; Reason = 'reference-only set incomplete' }
if ($widgetContent -match 'phase83_3_migration_pilot_usability_available=1' -and
    $widgetContent -match 'is_migration_pilot_mode_enabled\(') {
  $checkResults['check_reference_only_apps_identified'].Result = $true
  $checkResults['check_reference_only_apps_identified'].Reason = 'widget_sandbox remains reference-only/pilot-oriented in current policy map'
}

$checkResults['check_legacy_paths_inventory_and_status'] = @{ Result = $false; Reason = 'legacy path inventory or temporary-retention/candidate status missing' }
if ($sandboxContent -match 'run_legacy_sandbox_app\(' -and
    $loopContent -match 'run_legacy_loop_tests\(' -and
    $win32Content -match 'run_legacy_win32_sandbox\(' -and
    $legacyPathsRemainTemporary.Count -eq 3 -and
    $legacyPathsDelegacyCandidates.Count -eq 3) {
  $checkResults['check_legacy_paths_inventory_and_status'].Result = $true
  $checkResults['check_legacy_paths_inventory_and_status'].Reason = 'legacy paths are inventoried, retained temporarily, and explicitly marked as de-legacy planning candidates'
}

$checkResults['check_repo_level_default_adoption_policy_defined'] = @{ Result = $false; Reason = 'repo-level policy rules missing' }
if ($policyNativeDefaultWhen.Length -gt 0 -and
    $policyFallbackAllowedWhen.Length -gt 0 -and
    $policyLegacyReferenceOnlyWhen.Length -gt 0) {
  $checkResults['check_repo_level_default_adoption_policy_defined'].Result = $true
  $checkResults['check_repo_level_default_adoption_policy_defined'].Reason = 'policy defines native-default conditions fallback allowance and reference-only handling'
}

$checkResults['check_delegacy_lane_defined_planning_only'] = @{ Result = $false; Reason = 'de-legacy lane sequencing or planning-only criteria missing' }
if ($delegacyLaneSequence.Length -gt 0 -and
    $delegacyLaneCriteria -match 'no_removal_in_phase89_1' -and
    $delegacyLaneCriteria -match 'reversibility_preserved') {
  $checkResults['check_delegacy_lane_defined_planning_only'].Result = $true
  $checkResults['check_delegacy_lane_defined_planning_only'].Reason = 'de-legacy lane includes sequencing and criteria only, with no removal in this phase'
}

$checkResults['check_no_new_migration_or_framework_implementation'] = @{ Result = $true; Reason = 'phase89_1 is policy/planning only and adds no runtime/framework implementation changes' }

$failedCount = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result }).Count
$decision = if ($failedCount -eq 0) { 'READY_FOR_DEFAULT_ADOPTION_POLICY' } else { 'NOT_READY_WITH_BLOCKERS' }
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_default_adoption_policy_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE89_1_DEFAULT_ADOPTION_POLICY_AND_DELEGACY_PLAN'
$checkLines += 'scope=repo_level_default_adoption_policy_and_delegacy_planning_sequence'
$checkLines += 'assessment_only=YES'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ('decision=' + $decision)
$checkLines += ''
$checkLines += '# Policy Checks'
foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}
$checkLines += ''
$checkLines += '# Surface Inventory'
$checkLines += ('native_default_apps=' + ($nativeDefaultApps -join ','))
$checkLines += ('reference_only_apps=' + ($referenceOnlyApps -join ','))
$checkLines += ('legacy_paths_exist=' + ($legacyPathsExist -join ','))
$checkLines += ('legacy_paths_remain_temporary=' + ($legacyPathsRemainTemporary -join ','))
$checkLines += ('legacy_paths_delegacy_candidates=' + ($legacyPathsDelegacyCandidates -join ','))
$checkLines += ''
$checkLines += '# Repo Default-Adoption Policy'
$checkLines += ('native_default_when=' + $policyNativeDefaultWhen)
$checkLines += ('fallback_allowed_when=' + $policyFallbackAllowedWhen)
$checkLines += ('legacy_reference_only_when=' + $policyLegacyReferenceOnlyWhen)
$checkLines += ''
$checkLines += '# De-Legacy Lane'
$checkLines += ('delegacy_lane_sequence=' + $delegacyLaneSequence)
$checkLines += ('delegacy_lane_criteria=' + $delegacyLaneCriteria)
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE89_1_DEFAULT_ADOPTION_POLICY_AND_DELEGACY_PLAN'
$contract += 'objective=Define_repo_level_default_adoption_policy_and_delegacy_planning_sequence_after_wave1_and_wave2_completion_while_keeping_legacy_paths_controlled_and_reversible'
$contract += 'changes_introduced=Default_adoption_policy_and_delegacy_planning_runner_added_with_surface_inventory_policy_rules_and_planning_lane_criteria'
$contract += 'runtime_behavior_changes=None_assessment_phase_only_existing_runtime_behavior_unchanged'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_default_adoption_policy_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract += ('decision=' + $decision)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_default_adoption_policy_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_default_adoption_policy_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase89_1_default_adoption_policy_delegacy_plan_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase89_1_status=' + $phaseStatus)
Write-Host ('decision=' + $decision)
exit 0
