#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
  Write-Host "FATAL: $_"
  exit 1
}

$workspaceRoot = Get-Location | Select-Object -ExpandProperty Path
$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ($workspaceRoot -ne $expectedRoot) {
  Write-Host 'hey stupid Fucker, wrong window again'
  exit 1
}

$proofRoot = Join-Path $workspaceRoot '_proof'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName = "phase101_4_steady_state_redraw_present_fix_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase101_4_steady_state_redraw_present_fix_*.zip' -ErrorAction SilentlyContinue |
  ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }

$pythonExe = Join-Path $workspaceRoot '.venv/Scripts/python.exe'
if (-not (Test-Path -LiteralPath $pythonExe)) {
  Write-Host 'FATAL: python executable missing at .venv/Scripts/python.exe'
  exit 1
}

$buildOut = Join-Path $stageRoot '__build_stdout.txt'
$runOut = Join-Path $stageRoot '__run_stdout.txt'

$loopObjDir = Join-Path $workspaceRoot 'build/debug/obj/desktop_file_tool'
$exePath = Join-Path $workspaceRoot 'build/debug/bin/desktop_file_tool.exe'

if (Test-Path -LiteralPath $loopObjDir) {
  Get-ChildItem -LiteralPath $loopObjDir -Recurse -Filter *.obj -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
}
if (Test-Path -LiteralPath $exePath) {
  Remove-Item -LiteralPath $exePath -Force -ErrorAction SilentlyContinue
}

& $pythonExe -m ngksgraph build --profile debug --msvc-auto --target desktop_file_tool *>&1 | Out-File -LiteralPath $buildOut -Encoding UTF8
if ($LASTEXITCODE -ne 0) {
  Write-Host 'FATAL: desktop_file_tool build-plan generation failed'
  exit 1
}

$planPath = Join-Path $workspaceRoot 'build_graph/debug/ngksbuildcore_plan.json'
if (-not (Test-Path -LiteralPath $planPath)) {
  Write-Host 'FATAL: build plan missing for desktop_file_tool'
  exit 1
}

$planJson = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
$compileNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Compile apps/desktop_file_tool/main.cpp for desktop_file_tool' })[0]
$linkNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Link desktop_file_tool' })[0]
if ($null -eq $compileNode -or $null -eq $linkNode) {
  Write-Host 'FATAL: desktop_file_tool compile/link nodes missing in plan'
  exit 1
}

& (Join-Path $workspaceRoot 'tools/enter_msvc_env.ps1') *>&1 | Out-File -LiteralPath $buildOut -Append -Encoding UTF8

cmd /c $compileNode.cmd *>&1 | Out-File -LiteralPath $buildOut -Append -Encoding UTF8
if ($LASTEXITCODE -ne 0) {
  Write-Host 'FATAL: desktop_file_tool compile step failed'
  exit 1
}

cmd /c $linkNode.cmd *>&1 | Out-File -LiteralPath $buildOut -Append -Encoding UTF8
if ($LASTEXITCODE -ne 0) {
  Write-Host 'FATAL: desktop_file_tool link step failed'
  exit 1
}

if (-not (Test-Path -LiteralPath $exePath)) {
  Write-Host 'FATAL: desktop_file_tool executable missing after compile/link'
  exit 1
}

& $exePath --auto-close-ms=10000 *>&1 | Out-File -LiteralPath $runOut -Encoding UTF8
if ($LASTEXITCODE -ne 0) {
  Write-Host 'FATAL: desktop_file_tool run failed'
  exit 1
}

$runText = (Get-Content -LiteralPath $runOut -Raw) -replace "`r", ''

function Get-IntMetric {
  param([string]$Text, [string]$Key)
  $m = [regex]::Match($Text, "(?m)^$([regex]::Escape($Key))=(\d+)$")
  if (-not $m.Success) { return -1 }
  return [int]$m.Groups[1].Value
}

function Has-Line {
  param([string]$Text, [string]$Pattern)
  return [regex]::IsMatch($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
}

$wmPaintEntry = Get-IntMetric -Text $runText -Key 'phase101_4_wm_paint_entry_count'
$wmPaintExit = Get-IntMetric -Text $runText -Key 'phase101_4_wm_paint_exit_count'
$invTotal = Get-IntMetric -Text $runText -Key 'phase101_4_invalidate_total_count'
$inputRedraw = Get-IntMetric -Text $runText -Key 'phase101_4_input_redraw_requests'
$steadyRedraw = Get-IntMetric -Text $runText -Key 'phase101_4_steady_redraw_requests'
$renderBegin = Get-IntMetric -Text $runText -Key 'phase101_4_render_begin_count'
$renderEnd = Get-IntMetric -Text $runText -Key 'phase101_4_render_end_count'
$presentCalls = Get-IntMetric -Text $runText -Key 'phase101_4_present_call_count'
$steadyLoop = Get-IntMetric -Text $runText -Key 'phase101_4_steady_loop_iterations'
$presentStable = Get-IntMetric -Text $runText -Key 'phase101_4_present_path_stable'

$checkResults = [ordered]@{}
$checkResults['check_runtime_ok'] = @{ Result = (Has-Line -Text $runText -Pattern '^runtime_final_status=RUN_OK$'); Reason = 'runtime_final_status must be RUN_OK' }
$checkResults['check_root_cause_logged'] = @{ Result = (Has-Line -Text $runText -Pattern '^phase101_4_redraw_issue_root_cause='); Reason = 'root cause line must be present' }
$checkResults['check_background_erase_handled'] = @{ Result = (Has-Line -Text $runText -Pattern '^phase101_4_background_erase_handling=wm_erasebkgnd_suppressed$'); Reason = 'background erase suppression must be logged' }
$checkResults['check_wm_paint_path_active'] = @{ Result = ($wmPaintEntry -gt 0 -and $wmPaintEntry -eq $wmPaintExit); Reason = 'WM_PAINT entry/exit must be balanced and active' }
$checkResults['check_render_present_path_active'] = @{ Result = ($renderBegin -gt 0 -and $renderBegin -eq $renderEnd -and $renderEnd -eq $presentCalls -and $presentStable -eq 1); Reason = 'render and present counts must match and stable flag must be 1' }
$checkResults['check_steady_state_without_input'] = @{ Result = ($steadyRedraw -gt 0 -and $inputRedraw -eq 0); Reason = 'steady redraw must happen without input-triggered redraws' }
$checkResults['check_steady_loop_10s_window'] = @{ Result = ($steadyLoop -ge 200 -and $steadyLoop -le 1200); Reason = 'steady loop iterations should indicate active redraw without runaway CPU' }
$checkResults['check_invalidate_logging_present'] = @{ Result = ($invTotal -gt 0 -and (Has-Line -Text $runText -Pattern '^phase101_4_invalidate_request reason=')); Reason = 'invalidate calls must be logged' }

$failed = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result })
$phaseStatus = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_steady_state_redraw_checks.txt'
$checks = @()
$checks += 'phase=phase101_4_steady_state_redraw_present_fix'
$checks += 'target=apps/desktop_file_tool'
$checks += 'wm_paint_entry_count=' + $wmPaintEntry
$checks += 'wm_paint_exit_count=' + $wmPaintExit
$checks += 'invalidate_total_count=' + $invTotal
$checks += 'input_redraw_requests=' + $inputRedraw
$checks += 'steady_redraw_requests=' + $steadyRedraw
$checks += 'render_begin_count=' + $renderBegin
$checks += 'render_end_count=' + $renderEnd
$checks += 'present_call_count=' + $presentCalls
$checks += 'steady_loop_iterations=' + $steadyLoop
$checks += 'present_path_stable=' + $presentStable
$checks += 'phase_status=' + $phaseStatus
$checks += ''
$checks += '# Steady-state redraw checks'
foreach ($name in $checkResults.Keys) {
  $checks += ($name + '=' + $(if ($checkResults[$name].Result) { 'YES' } else { 'NO' }) + ' # ' + $checkResults[$name].Reason)
}
$checks | Out-File -LiteralPath $checksFile -Encoding UTF8

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'redraw_issue_root_cause=render_and_present_were_not_driven_by_an_explicit_steady_state_wm_paint_redraw_path_and_background_erase_was_not_explicitly_suppressed'
$contract += 'present_path_stable=' + $(if ($presentStable -eq 1) { 'Yes' } else { 'No' })
$contract += 'steady_state_visible_without_input=' + $(if ($checkResults['check_steady_state_without_input'].Result) { 'Yes' } else { 'No' })
$contract += 'input_only_rendering_removed=' + $(if ($checkResults['check_steady_state_without_input'].Result) { 'Yes' } else { 'No' })
$contract += 'changes_introduced=desktop_file_tool_now_uses_steady_16ms_redraw_invalidation_with_wm_paint_driven_render_present_diagnostics_and_win32_wm_erasebkgnd_suppression'
$contract += 'new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_or_blocked_see_90_steady_state_redraw_checks' })
$contract += 'phase_status=' + $phaseStatus
$contract += 'proof_folder=' + $proofPathRelative
$contract | Out-File -LiteralPath $contractFile -Encoding UTF8

if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $stageRoot '90_steady_state_redraw_checks.txt'), (Join-Path $stageRoot '99_contract_summary.txt') -DestinationPath $zipPath -Force

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase101_4_steady_state_redraw_present_fix_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host ('GATE=' + $phaseStatus)
exit 0
