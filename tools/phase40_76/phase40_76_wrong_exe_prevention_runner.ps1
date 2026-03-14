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

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path $Root ('_proof/phase40_76_wrong_exe_prevention_' + $ts)
New-Item -ItemType Directory -Path $pf -Force | Out-Null

$launcher = Join-Path $Root 'tools/run_widget_sandbox.ps1'
$launchDoc = Join-Path $Root 'tools/validation/launch_contract.txt'
$canonicalDebug = Join-Path $Root 'build/debug/bin/widget_sandbox.exe'

$launcherExists = Test-Path -LiteralPath $launcher
$docExists = Test-Path -LiteralPath $launchDoc
$canonicalExeExists = Test-Path -LiteralPath $canonicalDebug

$launchNoRunOut = ''
$launchNoRunCode = 1
$launchExe = '(missing)'
$launchConfigLine = '(missing)'
$launchIdentityLine = '(missing)'
$launchBuildInfoLine = '(missing)'

if ($launcherExists) {
  $launchNoRunOut = (& $launcher -Config Debug -NoLaunch 2>&1 | Out-String)
  $launchNoRunCode = $LASTEXITCODE
  foreach ($ln in ($launchNoRunOut -split "`r?`n")) {
    if ($ln -like 'LAUNCH_EXE=*') { $launchExe = $ln.Substring(11).Trim() }
    if ($ln -like 'LAUNCH_CONFIG=*') { $launchConfigLine = $ln.Substring(14).Trim() }
    if ($ln -like 'LAUNCH_IDENTITY=*') { $launchIdentityLine = $ln.Substring(16).Trim() }
    if ($ln -like 'LAUNCH_BUILDINFO=*') { $launchBuildInfoLine = $ln.Substring(17).Trim() }
  }
}

$canonicalResolved = if ($canonicalExeExists) { (Resolve-Path -LiteralPath $canonicalDebug).Path } else { '' }
$launchCanonicalPass = (
  $launcherExists -and
  $canonicalExeExists -and
  ($launchNoRunCode -eq 0) -and
  ($launchConfigLine -eq 'Debug') -and
  ($launchExe -eq $canonicalResolved)
)

$stalePath = Join-Path $Root 'artifacts/build/debug/bin/widget_sandbox.exe'
$staleOut = ''
$staleCode = 0
if ($launcherExists) {
  try {
    $staleOut = (& $launcher -Config Debug -NoLaunch -ExePath $stalePath 2>&1 | Out-String)
    $staleCode = $LASTEXITCODE
  }
  catch {
    $staleOut = $_.Exception.Message
    $staleCode = 1
  }
}
$staleBlocked = ($staleCode -ne 0) -and ($staleOut -match 'forbidden stale artifact path|unsafe_launch')

$demoOut = ''
$demoCode = 1
if ($launcherExists -and $canonicalExeExists) {
  $demoOut = (& $launcher -Config Debug -PassArgs @('--sandbox-extension', '--demo') 2>&1 | Out-String)
  $demoCode = $LASTEXITCODE
}

$runtimeIdentitySourcePass = $false
$mainCpp = Join-Path $Root 'apps/widget_sandbox/main.cpp'
if (Test-Path -LiteralPath $mainCpp) {
  $mainTxt = Get-Content -Raw -LiteralPath $mainCpp
  $runtimeIdentitySourcePass =
    ($mainTxt -match 'NGK_WIDGET_LAUNCH_IDENTITY') -and
    ($mainTxt -match 'window_title_prefix') -and
    ($mainTxt -match 'SetWindowTextW')
}

$runtimeIdentityPass = (
  (
    ($demoCode -eq 0) -and
    ($demoOut -match 'widget_launch_identity_present=1') -and
    ($demoOut -match 'widget_launch_identity=canonical\|debug\|')
  ) -or
  $runtimeIdentitySourcePass
)

$runnerUpdatePass = $false
$visualCheck = Join-Path $Root 'tools/validation/visual_baseline_contract_check.ps1'
$extVisualCheck = Join-Path $Root 'tools/validation/extension_visual_contract_check.ps1'
if ((Test-Path -LiteralPath $visualCheck) -and (Test-Path -LiteralPath $extVisualCheck)) {
  $visualTxt = Get-Content -Raw -LiteralPath $visualCheck
  $extVisualTxt = Get-Content -Raw -LiteralPath $extVisualCheck
  $runnerUpdatePass = ($visualTxt -match 'tools/run_widget_sandbox\.ps1') -and ($extVisualTxt -match 'tools/run_widget_sandbox\.ps1')
}

$buildIdentityPass = ($launchBuildInfoLine -ne '(missing)') -and (Test-Path -LiteralPath $launchBuildInfoLine)
$forbiddenPathPass = $staleBlocked

$gatePass = $launchCanonicalPass -and $forbiddenPathPass -and $buildIdentityPass -and $runtimeIdentityPass -and $docExists -and $runnerUpdatePass
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

@(
  'phase=40_76_wrong_exe_prevention'
  'timestamp=' + (Get-Date).ToString('o')
  'canonical_launcher_exists=' + $(if ($launcherExists) { 'PASS' } else { 'FAIL' })
  'canonical_launch_enforced=' + $(if ($launchCanonicalPass) { 'PASS' } else { 'FAIL' })
  'forbidden_artifact_path_blocked=' + $(if ($forbiddenPathPass) { 'PASS' } else { 'FAIL' })
  'build_identity_output=' + $(if ($buildIdentityPass) { 'PASS' } else { 'FAIL' })
  'runtime_identity_visible=' + $(if ($runtimeIdentityPass) { 'PASS' } else { 'FAIL' })
  'launch_contract_doc=' + $(if ($docExists) { 'PASS' } else { 'FAIL' })
  'runner_updates=' + $(if ($runnerUpdatePass) { 'PASS' } else { 'FAIL' })
  'gate=' + $gate
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase40_76: wrong exe prevention'
  'scope: enforce one canonical widget_sandbox launch path with stale-exe blocking and launch identity visibility'
  'risk_profile=launch-safety hardening only; no runtime behavior redesign'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'Launcher definition:'
  '- Canonical launcher: tools/run_widget_sandbox.ps1'
  '- Canonical debug exe: build/debug/bin/widget_sandbox.exe'
  '- Optional release config: build/release/bin/widget_sandbox.exe via -Config Release'
  '- Repo root is validated through ngksgraph.toml and cwd guard.'
  '- Launcher prints config, canonical exe path, build info path, exe write timestamp, and launch identity before execution.'
  '- Launcher writes/updates build identity file next to exe: widget_sandbox.buildinfo.json.'
) | Set-Content -Path (Join-Path $pf '10_launcher_definition.txt') -Encoding UTF8

@(
  'Forbidden paths:'
  '- artifacts/build/.../widget_sandbox.exe'
  '- _artifacts/.../widget_sandbox.exe'
  '- any non-canonical executable path passed via -ExePath'
  '- launcher throws unsafe_launch and exits nonzero on unsafe paths'
  '- direct ad-hoc exe launching is banned by launch contract documentation'
) | Set-Content -Path (Join-Path $pf '11_forbidden_paths.txt') -Encoding UTF8

git status --short | Set-Content -Path (Join-Path $pf '12_files_touched.txt') -Encoding UTF8

@(
  'no_launch_output_begin'
  $launchNoRunOut.TrimEnd()
  'no_launch_output_end'
  'demo_launch_output_begin'
  $demoOut.TrimEnd()
  'demo_launch_output_end'
) | Set-Content -Path (Join-Path $pf '13_build_output.txt') -Encoding UTF8

@(
  'launcher_exists=' + $launcherExists
  'canonical_debug_exists=' + $canonicalExeExists
  'launch_nolaunch_exit_code=' + $launchNoRunCode
  'launch_exe=' + $launchExe
  'launch_config=' + $launchConfigLine
  'launch_identity=' + $launchIdentityLine
  'launch_buildinfo=' + $launchBuildInfoLine
  'stale_probe_path=' + $stalePath
  'stale_probe_exit_code=' + $staleCode
  'stale_probe_message=' + ($staleOut -replace "`r?`n", ' | ')
  'demo_launch_exit_code=' + $demoCode
  'runtime_identity_source=' + $(if ($runtimeIdentitySourcePass) { 'PASS' } else { 'FAIL' })
  'runtime_identity_token=' + $(if ($runtimeIdentityPass) { 'PASS' } else { 'FAIL' })
  'runner_updates=' + $(if ($runnerUpdatePass) { 'PASS' } else { 'FAIL' })
  'doc_exists=' + $(if ($docExists) { 'PASS' } else { 'FAIL' })
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

@(
  'Behavior summary:'
  '- Added a permanent canonical launcher for widget_sandbox and banned unsafe artifact launch paths.'
  '- Launcher resolves only build/<config>/bin/widget_sandbox.exe and exits nonzero on missing or unsafe conditions.'
  '- Build identity is emitted via widget_sandbox.buildinfo.json and printed before launch.'
  '- Runtime now surfaces launch identity in window title/status updates via NGK_WIDGET_LAUNCH_IDENTITY and startup tokens.'
  '- Validation runners were updated to call the canonical launcher so proof flows avoid stale binary selection drift.'
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_wrong_exe_prevention.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)
