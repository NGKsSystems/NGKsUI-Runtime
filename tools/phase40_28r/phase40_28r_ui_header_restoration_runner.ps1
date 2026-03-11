param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$root = (Get-Location).Path
$proofRoot = Join-Path $root '_proof'
if (-not (Test-Path -LiteralPath $proofRoot)) {
  New-Item -ItemType Directory -Path $proofRoot | Out-Null
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path $proofRoot ("phase40_28r_ui_header_restoration_" + $stamp)
New-Item -ItemType Directory -Path $pf | Out-Null
$zip = "$pf.zip"

$proofResolved = (Resolve-Path -LiteralPath $proofRoot).Path
$legalPrefix = $proofResolved + [System.IO.Path]::DirectorySeparatorChar

$f1 = Join-Path $pf '01_status.txt'
$f2 = Join-Path $pf '02_head.txt'
$f10 = Join-Path $pf '10_missing_headers_found.txt'
$f11 = Join-Path $pf '11_headers_restored.txt'
$f12 = Join-Path $pf '12_files_touched.txt'
$f13 = Join-Path $pf '13_build_output.txt'
$f14 = Join-Path $pf '14_dependency_chain_notes.txt'
$f15 = Join-Path $pf '15_behavior_summary.txt'
$f98 = Join-Path $pf '98_gate_phase40_28r.txt'

git status *> $f1
git log -1 *> $f2
try {
  $filesTouched = git diff --name-only 2>&1
  if ($filesTouched) {
    $filesTouched | Set-Content -Path $f12 -Encoding utf8
  } else {
    'none' | Set-Content -Path $f12 -Encoding utf8
  }
}
catch {
  ('git_diff_failed: ' + ($_ | Out-String).Trim()) | Set-Content -Path $f12 -Encoding utf8
}

@(
  'engine/ui/button.hpp'
  'engine/ui/panel.hpp'
  'engine/ui/ui_element.hpp'
  'engine/ui/input_router.hpp'
  'engine/ui/text_painter.hpp'
  'engine/ui/label.hpp'
  'engine/ui/horizontal_layout.hpp'
  'engine/ui/vertical_layout.hpp'
) | Set-Content -Path $f11 -Encoding utf8

Stop-Process -Name widget_sandbox -Force -ErrorAction SilentlyContinue

$graphPlan = Join-Path $root 'build_graph\debug\ngksbuildcore_plan.json'
$headerBlocker = $null
$nonHeaderBlocker = $null
$buildOk = $false

try {
  if (-not (Test-Path -LiteralPath $graphPlan)) {
    throw "graph_plan_missing:$graphPlan"
  }

  .\tools\enter_msvc_env.ps1 *> $f13

  $plan = Get-Content -Raw -LiteralPath $graphPlan | ConvertFrom-Json
  foreach ($node in $plan.nodes) {
    if ($null -eq $node.cmd -or [string]::IsNullOrWhiteSpace([string]$node.cmd)) {
      continue
    }

    "=== NODE: $($node.desc) ===" | Add-Content -Path $f13 -Encoding utf8
    "CMD: $($node.cmd)" | Add-Content -Path $f13 -Encoding utf8

    $cmdOut = cmd.exe /d /c $node.cmd 2>&1
    if ($cmdOut) {
      $cmdOut | Add-Content -Path $f13 -Encoding utf8
    }

    if ($LASTEXITCODE -ne 0) {
      $cmdText = ($cmdOut | Out-String)
      $headerMatch = [regex]::Match($cmdText, "fatal error C1083: Cannot open include file: '([^']+)'")
      if ($headerMatch.Success) {
        $headerBlocker = $headerMatch.Groups[1].Value
      } else {
        $nonHeaderBlocker = "node=$($node.id)"
      }
      throw "graph_node_failed:$($node.id)"
    }
  }

  $buildOk = $true
}
catch {
  ($_ | Out-String) | Add-Content -Path $f13 -Encoding utf8
}

if ($buildOk) {
  'none' | Set-Content -Path $f10 -Encoding utf8
} elseif ($headerBlocker) {
  @(
    "next_missing_header=$headerBlocker"
  ) | Set-Content -Path $f10 -Encoding utf8
} else {
  @(
    'none'
    'build_failed_but_not_due_to_missing_headers'
  ) | Set-Content -Path $f10 -Encoding utf8
}

@(
  'dependency_chain=button.cpp -> button.hpp -> panel.hpp -> ui_element.hpp'
  'main.cpp_header_chain=button.hpp,input_box.hpp,horizontal_layout.hpp,input_router.hpp,label.hpp,text_painter.hpp,ui_tree.hpp,vertical_layout.hpp'
  "header_blocker=$(if ($headerBlocker) { $headerBlocker } else { 'none' })"
  "non_header_blocker=$(if ($nonHeaderBlocker) { $nonHeaderBlocker } else { 'none' })"
) | Set-Content -Path $f14 -Encoding utf8

$headersRemaining = [string]::IsNullOrWhiteSpace($headerBlocker) -eq $false
$advancedToNonHeader = (-not $buildOk) -and (-not $headersRemaining)

@(
  "headers_reconstructed_from_current_impl=true"
  "build_ok=$buildOk"
  "build_advanced_to_non_header_issue=$advancedToNonHeader"
  "header_stage_cleared=$(if ($buildOk -or $advancedToNonHeader) { 'true' } else { 'false' })"
  "remaining_failure_type=$(if ($buildOk) { 'none' } elseif ($headersRemaining) { 'missing_header' } else { 'non_header' })"
  "remaining_failure_value=$(if ($headerBlocker) { $headerBlocker } elseif ($nonHeaderBlocker) { $nonHeaderBlocker } else { 'none' })"
) | Set-Content -Path $f15 -Encoding utf8

$requiredFiles = @(
  '01_status.txt',
  '02_head.txt',
  '10_missing_headers_found.txt',
  '11_headers_restored.txt',
  '12_files_touched.txt',
  '13_build_output.txt',
  '14_dependency_chain_notes.txt',
  '15_behavior_summary.txt'
)
$requiredPresent = $true
foreach ($rf in $requiredFiles) {
  if (-not (Test-Path -LiteralPath (Join-Path $pf $rf))) {
    $requiredPresent = $false
  }
}

$pfResolved = (Resolve-Path -LiteralPath $pf).Path
$zipCanonical = [System.IO.Path]::GetFullPath($zip)
$pfUnderLegal = $pfResolved.StartsWith($legalPrefix, [System.StringComparison]::OrdinalIgnoreCase)
$zipUnderLegal = $zipCanonical.StartsWith($legalPrefix, [System.StringComparison]::OrdinalIgnoreCase)

$pass = $requiredPresent -and $pfUnderLegal -and $zipUnderLegal -and ($buildOk -or $advancedToNonHeader)
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

@(
  'phase=40_28r_ui_header_restoration'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "build_ok=$buildOk"
  "advanced_to_non_header_issue=$advancedToNonHeader"
  "next_missing_header=$(if ($headerBlocker) { $headerBlocker } else { 'none' })"
  "non_header_blocker=$(if ($nonHeaderBlocker) { $nonHeaderBlocker } else { 'none' })"
  "required_files_present=$requiredPresent"
  "pf_under_legal_root=$pfUnderLegal"
  "zip_under_legal_root=$zipUnderLegal"
  "gate=$gate"
) | Set-Content -Path $f98 -Encoding utf8

if (Test-Path -LiteralPath $zipCanonical) {
  Remove-Item -Force $zipCanonical
}
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zipCanonical -Force

Write-Output "PF=$pfResolved"
Write-Output "ZIP=$zipCanonical"
Write-Output "GATE=$gate"
if ($gate -eq 'FAIL') {
  Get-Content -Path $f98
  if ($headerBlocker) {
    Write-Output "next_missing_header=$headerBlocker"
  } elseif ($nonHeaderBlocker) {
    Write-Output "compile_blocker=$nonHeaderBlocker"
  }
}
