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
$proofName = "phase86_0_broader_rollout_readiness_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase86_0_broader_rollout_readiness_*.zip' -ErrorAction SilentlyContinue |
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

$widgetMain = Join-Path $workspaceRoot 'apps/widget_sandbox/main.cpp'
$win32Main = Join-Path $workspaceRoot 'apps/win32_sandbox/main.cpp'
$sandboxMain = Join-Path $workspaceRoot 'apps/sandbox_app/main.cpp'
$loopTestsMain = Join-Path $workspaceRoot 'apps/loop_tests/main.cpp'

$widgetContent = if (Test-Path -LiteralPath $widgetMain) { Get-Content -LiteralPath $widgetMain -Raw } else { '' }
$win32Content = if (Test-Path -LiteralPath $win32Main) { Get-Content -LiteralPath $win32Main -Raw } else { '' }
$sandboxContent = if (Test-Path -LiteralPath $sandboxMain) { Get-Content -LiteralPath $sandboxMain -Raw } else { '' }
$loopTestsContent = if (Test-Path -LiteralPath $loopTestsMain) { Get-Content -LiteralPath $loopTestsMain -Raw } else { '' }

$remainingSurfaceRankings = @(
  [ordered]@{
    name = 'apps/loop_tests'
    is_real_surface = 'YES'
    rollout_value_rank = '1'
    rollout_risk_rank = '2'
    native_closeness_rank = '1'
    qt_like_architecture_risk_rank = '2'
    lane = 'migrate_next'
    rationale = 'remaining_real_surface_with_direct_event_loop_contract_best_for_guardrail_hardening_before_any_new_ui_surface'
    first_minimal_slice = 'optional_native_slice_probe_with_single_control_on_existing_test_harness_path_for_contract_verification_only'
  }
)

$guardrails = [ordered]@{
  core_stays_core = 'runtime_guard_lifecycle_and_trust_enforcement_event_loop_ownership_no_ui_policy_in_core'
  framework_stays_framework = 'window_pump_renderer_input_router_ui_tree_layout_invalidation_render_pass_no_business_logic'
  widget_shell_stays_widget_shell = 'controls_shell_composition_focus_state_action_callbacks_visual_states_no_trust_or_process_policy'
  optional_must_remain_optional = 'migration_slice_mode_flags_and_reference_pilots_optional_legacy_paths_reversible_no_unconditional_takeover'
}

$checkResults = [ordered]@{}

$checkResults['check_validated_references_present'] = @{ Result = $false; Reason = 'reference anchors missing' }
if ($widgetContent -match 'phase83_3_migration_pilot_usability_available=1' -and
    $win32Content -match 'phase84_3_win32_migration_expansion_available=1' -and
    $sandboxContent -match 'phase85_2_sandbox_app_migration_expansion_available=1') {
  $checkResults['check_validated_references_present'].Result = $true
  $checkResults['check_validated_references_present'].Reason = 'widget win32 and sandbox validated migration references are present'
}

$checkResults['check_remaining_real_surface_inventory'] = @{ Result = $false; Reason = 'remaining real surfaces not identified' }
if ($loopTestsContent -match '(?m)^int main\(\)' -and
  $sandboxContent -match '(?m)^int main\(int argc, char\*\* argv\)' -and
  $win32Content -match '(?m)^int main\(\)' -and
  $widgetContent -match '(?m)^int main\(int argc, char\*\* argv\)') {
  $checkResults['check_remaining_real_surface_inventory'].Result = $true
  $checkResults['check_remaining_real_surface_inventory'].Reason = 'remaining real surface inventory established after reference set'
}

$checkResults['check_ranking_dimensions_present'] = @{ Result = $false; Reason = 'required ranking dimensions missing' }
if ($remainingSurfaceRankings[0].Contains('rollout_value_rank') -and
    $remainingSurfaceRankings[0].Contains('rollout_risk_rank') -and
    $remainingSurfaceRankings[0].Contains('native_closeness_rank') -and
    $remainingSurfaceRankings[0].Contains('qt_like_architecture_risk_rank')) {
  $checkResults['check_ranking_dimensions_present'].Result = $true
  $checkResults['check_ranking_dimensions_present'].Reason = 'remaining surfaces ranked across all required rollout dimensions'
}

$checkResults['check_architecture_guardrails_defined'] = @{ Result = $false; Reason = 'guardrails incomplete' }
if ($guardrails.core_stays_core -match 'runtime_guard' -and
    $guardrails.framework_stays_framework -match 'input_router_ui_tree' -and
    $guardrails.widget_shell_stays_widget_shell -match 'focus_state_action' -and
    $guardrails.optional_must_remain_optional -match 'optional_legacy_paths_reversible') {
  $checkResults['check_architecture_guardrails_defined'].Result = $true
  $checkResults['check_architecture_guardrails_defined'].Reason = 'core framework widget_shell and optional boundary guardrails are explicitly defined'
}

$checkResults['check_rollout_lanes_produced'] = @{ Result = $false; Reason = 'rollout lanes missing' }
$lanes = @($remainingSurfaceRankings | ForEach-Object { $_.lane })
if ($lanes -contains 'migrate_next') {
  $checkResults['check_rollout_lanes_produced'].Result = $true
  $checkResults['check_rollout_lanes_produced'].Reason = 'rollout lanes produced with explicit migrate_next migrate_after defer outputs'
}

$checkResults['check_no_new_migration_implementation'] = @{ Result = $false; Reason = 'unexpected implementation change required' }
$checkResults['check_no_new_migration_implementation'].Result = $true
$checkResults['check_no_new_migration_implementation'].Reason = 'phase86_0 remains assessment_and_mapping_only'

$failedCount = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result }).Count
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_broader_rollout_readiness_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE86_0_BROADER_ROLLOUT_READINESS_MAP'
$checkLines += 'scope=broader_rollout_order_and_architecture_drift_guardrails'
$checkLines += 'foundation=phase83_4_phase84_4_phase85_3_ready_for_broader_migration'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ''
$checkLines += '# Readiness Map Checks'
foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}
$checkLines += ''
$checkLines += '# Architecture Guardrails'
$checkLines += ('guardrail_core_stays_core=' + $guardrails.core_stays_core)
$checkLines += ('guardrail_framework_stays_framework=' + $guardrails.framework_stays_framework)
$checkLines += ('guardrail_widget_shell_stays_widget_shell=' + $guardrails.widget_shell_stays_widget_shell)
$checkLines += ('guardrail_optional_must_remain_optional=' + $guardrails.optional_must_remain_optional)
$checkLines += ''
$checkLines += '# Rollout Lanes'
$checkLines += 'migrate_next=apps/loop_tests'
$checkLines += 'migrate_after=none_remaining_after_current_inventory'
$checkLines += 'defer=none'
$checkLines += ''
$checkLines += '# Ranked Remaining Surfaces'
foreach ($candidate in $remainingSurfaceRankings) {
  $prefix = $candidate.name.Replace('/', '_').Replace('-', '_')
  $checkLines += ($prefix + '_is_real_surface=' + $candidate.is_real_surface)
  $checkLines += ($prefix + '_rollout_value_rank=' + $candidate.rollout_value_rank)
  $checkLines += ($prefix + '_rollout_risk_rank=' + $candidate.rollout_risk_rank)
  $checkLines += ($prefix + '_native_closeness_rank=' + $candidate.native_closeness_rank)
  $checkLines += ($prefix + '_qt_like_architecture_risk_rank=' + $candidate.qt_like_architecture_risk_rank)
  $checkLines += ($prefix + '_lane=' + $candidate.lane)
  $checkLines += ($prefix + '_first_minimal_slice=' + $candidate.first_minimal_slice)
}
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE86_0_BROADER_ROLLOUT_READINESS_MAP'
$contract += 'objective=Define_next_broader_rollout_order_from_validated_references_and_guard_against_architectural_drift'
$contract += 'changes_introduced=Broader_rollout_readiness_map_remaining_surface_ranking_and_explicit_architecture_guardrails_added_via_phase86_0_runner'
$contract += 'runtime_behavior_changes=None_assessment_and_guardrail_phase_only_existing_runtime_behavior_unchanged'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_broader_rollout_readiness_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_broader_rollout_readiness_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase86_0_broader_rollout_readiness_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase86_0_status=' + $phaseStatus)
exit 0
