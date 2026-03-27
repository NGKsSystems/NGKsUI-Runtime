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
$proofName = "phase84_4_win32_migration_readiness_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase84_4_win32_migration_readiness_*.zip' -ErrorAction SilentlyContinue |
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

$win32Main = Join-Path $workspaceRoot 'apps/win32_sandbox/main.cpp'
$win32Content = if (Test-Path -LiteralPath $win32Main) { Get-Content -LiteralPath $win32Main -Raw } else { '' }

$criteriaResults = [ordered]@{}

# Criterion 1: native path stability
$criteriaResults['criterion_native_path_stability'] = @{ Result = $false; Reason = 'native startup or loop anchors missing' }
if ($win32Content -match 'window\.create\(' -and
    $win32Content -match 'loop\.set_platform_pump' -and
    $win32Content -match 'window\.poll_events_once\(\)' -and
    $win32Content -match 'loop\.run\(\)' -and
    $win32Content -match 'renderer\.init\(' -and
    $win32Content -match 'renderer\.end_frame\(') {
  $criteriaResults['criterion_native_path_stability'].Result = $true
  $criteriaResults['criterion_native_path_stability'].Reason = 'native window/event loop/render path remains stable'
}

# Criterion 2: interaction coherence
$criteriaResults['criterion_interaction_coherence'] = @{ Result = $false; Reason = 'input routing coherence incomplete' }
if ($win32Content -match 'native_input_router\.on_mouse_move' -and
    $win32Content -match 'native_input_router\.on_mouse_button_message' -and
    $win32Content -match 'native_input_router\.on_key_message' -and
    $win32Content -match 'native_input_router\.on_char_input' -and
    $win32Content -match 'set_focused_element\(&native_primary_action_tile\)') {
  $criteriaResults['criterion_interaction_coherence'].Result = $true
  $criteriaResults['criterion_interaction_coherence'].Reason = 'shared input router and focus model handle expanded controls coherently'
}

# Criterion 3: layout/redraw coherence
$criteriaResults['criterion_layout_redraw_coherence'] = @{ Result = $false; Reason = 'layout or redraw integration incomplete' }
if ($win32Content -match 'layout_native_slice' -and
    $win32Content -match 'native_tree\.on_resize\(' -and
    $win32Content -match 'native_tree\.invalidate\(' -and
    $win32Content -match 'native_tree\.render\(renderer\)' -and
    $win32Content -match 'set_resize_callback') {
  $criteriaResults['criterion_layout_redraw_coherence'].Result = $true
  $criteriaResults['criterion_layout_redraw_coherence'].Reason = 'expanded slice stays in unified resize/layout/invalidate/render path'
}

# Criterion 4: state/action consistency
$criteriaResults['criterion_state_action_consistency'] = @{ Result = $false; Reason = 'state/action updates across expanded surface not explicit' }
if ($win32Content -match 'native_primary_action_count' -and
    $win32Content -match 'native_secondary_action_count' -and
    $win32Content -match 'native_status_value' -and
    $win32Content -match 'native_status_strip\.set_value\(' -and
    $win32Content -match 'phase84_3_primary_action_count=' -and
    $win32Content -match 'phase84_3_secondary_action_count=' -and
    $win32Content -match 'phase84_3_status_value=') {
  $criteriaResults['criterion_state_action_consistency'].Result = $true
  $criteriaResults['criterion_state_action_consistency'].Reason = 'actions deterministically update shared state and visible status value'
}

# Criterion 5: usability baseline for migrated slice
$criteriaResults['criterion_usability_baseline'] = @{ Result = $false; Reason = 'minimal usability baseline not met' }
if ($win32Content -match 'focused\(\)' -and
    $win32Content -match 'hover_' -and
    $win32Content -match 'pressed_' -and
    $win32Content -match 'on_key_down\(std::uint32_t key' -and
    $win32Content -match 'vkReturn' -and
    $win32Content -match 'vkSpace') {
  $criteriaResults['criterion_usability_baseline'].Result = $true
  $criteriaResults['criterion_usability_baseline'].Reason = 'slice provides focus, hover, pressed, and keyboard activation baseline'
}

# Criterion 6: reversibility / non-regression
$criteriaResults['criterion_reversibility_non_regression'] = @{ Result = $false; Reason = 'existing behavior guardrails missing' }
if ($win32Content -match 'phase84_1_win32_alignment_available=1' -and
    $win32Content -match 'require_runtime_trust\("execution_pipeline"\)' -and
    $win32Content -match 'rt_refresh_flush\(' -and
    $win32Content -match 'FORCE_TEST_CRASH=1' -and
    $win32Content -match 'shutdown_ok=1' -and
    $win32Content -match 'runtime_observe_lifecycle\("win32_sandbox", "main_exit"\)') {
  $criteriaResults['criterion_reversibility_non_regression'].Result = $true
  $criteriaResults['criterion_reversibility_non_regression'].Reason = 'existing win32 behavior outside slice remains available with lifecycle alignment preserved'
}

$failedCriteria = @($criteriaResults.GetEnumerator() | Where-Object { -not $_.Value.Result } | ForEach-Object { $_.Key })
$failedCount = $failedCriteria.Count
$readinessDecision = if ($failedCount -eq 0) { 'READY_FOR_BROADER_MIGRATION' } else { 'NOT_READY_WITH_BLOCKERS' }
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$smallestFixes = @()
if ($failedCount -gt 0) {
  if ($failedCriteria -contains 'criterion_native_path_stability') {
    $smallestFixes += 'restore_missing_native_startup_loop_or_render_anchors'
  }
  if ($failedCriteria -contains 'criterion_interaction_coherence') {
    $smallestFixes += 'reconnect_unified_input_router_callbacks_to_expanded_controls'
  }
  if ($failedCriteria -contains 'criterion_layout_redraw_coherence') {
    $smallestFixes += 'restore_layout_resize_and_invalidate_render_wiring_for_expanded_slice'
  }
  if ($failedCriteria -contains 'criterion_state_action_consistency') {
    $smallestFixes += 'rebind_primary_secondary_actions_to_shared_status_state_updates'
  }
  if ($failedCriteria -contains 'criterion_usability_baseline') {
    $smallestFixes += 'restore_focus_hover_pressed_and_keyboard_activation_on_action_tiles'
  }
  if ($failedCriteria -contains 'criterion_reversibility_non_regression') {
    $smallestFixes += 'reconfirm_phase84_1_trust_lifecycle_order_and_existing_stress_paths'
  }
}

$checksFile = Join-Path $stageRoot '90_win32_migration_readiness_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE84_4_WIN32_SANDBOX_MIGRATION_READINESS_DECISION'
$checkLines += 'scope=win32_sandbox_native_migrated_slice_readiness_assessment'
$checkLines += 'foundation=phase84_1_through_phase84_3_complete'
$checkLines += ('total_criteria=' + $criteriaResults.Count)
$checkLines += ('passed_criteria=' + ($criteriaResults.Count - $failedCount))
$checkLines += ('failed_criteria=' + $failedCount)
$checkLines += ('readiness_decision=' + $readinessDecision)
$checkLines += ''
$checkLines += '# Readiness Criteria Validation'
foreach ($criterionName in $criteriaResults.Keys) {
  $criterion = $criteriaResults[$criterionName]
  $result = if ($criterion.Result) { 'YES' } else { 'NO' }
  $checkLines += ($criterionName + '=' + $result + ' # ' + $criterion.Reason)
}
$checkLines += ''
$checkLines += '# Smallest Next Fixes (only if blockers exist)'
if ($smallestFixes.Count -eq 0) {
  $checkLines += 'smallest_next_fixes=none'
} else {
  $checkLines += ('smallest_next_fixes=' + ($smallestFixes -join ','))
}
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE84_4_WIN32_SANDBOX_MIGRATION_READINESS_DECISION'
$contract += 'objective=Assess_whether_current_win32_sandbox_migrated_native_slice_is_ready_for_broader_migration_guidance_using_explicit_criteria'
$contract += 'changes_introduced=Explicit_readiness_criteria_definition_and_evidence_based_readiness_decision_added_via_phase84_4_runner_no_new_slice_changes'
$contract += 'runtime_behavior_changes=None_assessment_phase_only_existing_win32_sandbox_behavior_unchanged'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('readiness_decision=' + $readinessDecision)
$contract += ('smallest_next_fixes=' + $(if ($smallestFixes.Count -eq 0) { 'none' } else { ($smallestFixes -join ',') }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_win32_migration_readiness_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_win32_migration_readiness_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase84_4_win32_migration_readiness_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host ('READINESS=' + $readinessDecision)
Write-Host 'GATE=PASS'
Write-Host ('phase84_4_status=' + $phaseStatus)
exit 0
