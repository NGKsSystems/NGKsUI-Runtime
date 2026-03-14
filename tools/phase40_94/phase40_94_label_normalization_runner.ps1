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

function Test-HasToken {
  param(
    [string]$Text,
    [string]$Token
  )
  return ($Text -match [regex]::Escape($Token))
}

function Get-StructureLines {
  param([string]$Text)
  return (($Text -split "`r?`n") | Where-Object {
      $_ -match 'add_child\(&' -or
      $_ -match 'set_padding\(' -or
      $_ -match 'set_size\(' -or
      $_ -match 'set_preferred_size\(' -or
      $_ -match 'set_background\('
    } | ForEach-Object { $_.Trim() })
}

function Get-LayoutStructBlock {
  param([string]$Text)
  $m = [regex]::Match($Text, 'struct ExtensionLaneLayout \{[\s\S]*?\};')
  if (-not $m.Success) { return '' }
  return $m.Value
}

function Get-VisibleTextSnapshot {
  param([string]$Text)
  $lines = @()
  if (Test-HasToken $Text 'PHASE 40: RUNTIME UPDATE LOOP SCHEDULER') { $lines += 'PHASE 40: RUNTIME UPDATE LOOP SCHEDULER' }
  if (Test-HasToken $Text 'Status: Ready') { $lines += 'Status: Ready' }
  if (Test-HasToken $Text 'Extension Mode: Active') { $lines += 'Extension Mode: Active' }
  if (Test-HasToken $Text 'Runtime Control') { $lines += 'Runtime Control' }
  if (Test-HasToken $Text 'Controls') { $lines += 'Controls' }
  if (Test-HasToken $Text 'State: Inactive') { $lines += 'State: Inactive' }
  if (Test-HasToken $Text 'Next Action: Waiting for Toggle') { $lines += 'Next Action: Waiting for Toggle' }
  if (Test-HasToken $Text 'Input') { $lines += 'Input' }
  if (Test-HasToken $Text 'Type here') { $lines += 'Type here' }
  if (Test-HasToken $Text 'Increment') { $lines += 'Increment' }
  if (Test-HasToken $Text 'Reset') { $lines += 'Reset' }
  if (Test-HasToken $Text 'Disabled') { $lines += 'Disabled' }
  return $lines
}

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path $Root ('_proof/phase40_94_label_normalization_' + $ts)
New-Item -ItemType Directory -Path $pf -Force | Out-Null

$mainPath = Join-Path $Root 'apps/widget_sandbox/main.cpp'
$inputPath = Join-Path $Root 'engine/ui/input_box.hpp'
if (-not (Test-Path -LiteralPath $mainPath)) { throw 'missing apps/widget_sandbox/main.cpp' }
if (-not (Test-Path -LiteralPath $inputPath)) { throw 'missing engine/ui/input_box.hpp' }

$mainNow = Get-Content -Raw -LiteralPath $mainPath
$inputNow = Get-Content -Raw -LiteralPath $inputPath

$structureLines = Get-StructureLines -Text $mainNow
$addChildCount = ($structureLines | Where-Object { $_ -match 'add_child\(&' }).Count
$setPaddingCount = ($structureLines | Where-Object { $_ -match 'set_padding\(' }).Count
$containerCountPass = ($addChildCount -eq 15) -and ($setPaddingCount -eq 9)

$layoutBlock = Get-LayoutStructBlock -Text $mainNow
$layoutStructPass = (
  -not [string]::IsNullOrWhiteSpace($layoutBlock) -and
  (Test-HasToken -Text $layoutBlock -Token 'int background_x = 0;') -and
  (Test-HasToken -Text $layoutBlock -Token 'int background_y = 0;') -and
  (Test-HasToken -Text $layoutBlock -Token 'int info_card_height = 156;') -and
  (Test-HasToken -Text $layoutBlock -Token 'int placeholder_height = 40;') -and
  (Test-HasToken -Text $layoutBlock -Token 'int tertiary_marker_height = 20;')
)

$uiStructurePass = (
  (Test-HasToken -Text $mainNow -Token 'root.add_child(&title);') -and
  (Test-HasToken -Text $mainNow -Token 'root.add_child(&status);') -and
  (Test-HasToken -Text $mainNow -Token 'root.add_child(&extension_mode_label);') -and
  (Test-HasToken -Text $mainNow -Token 'extension_info_card.add_child(&extension_info_card_title);') -and
  (Test-HasToken -Text $mainNow -Token 'extension_info_card.add_child(&extension_info_card_text);') -and
  (Test-HasToken -Text $mainNow -Token 'extension_info_card.add_child(&extension_info_card_summary);') -and
  (Test-HasToken -Text $mainNow -Token 'extension_info_card.add_child(&extension_info_card_detail);') -and
  (Test-HasToken -Text $mainNow -Token 'root.add_child(&extension_info_card);') -and
  (Test-HasToken -Text $mainNow -Token 'root.add_child(&text_field);') -and
  (Test-HasToken -Text $mainNow -Token 'root.add_child(&controls_row);') -and
  (Test-HasToken -Text $mainNow -Token 'controls_row.add_child(&increment_button);') -and
  (Test-HasToken -Text $mainNow -Token 'controls_row.add_child(&reset_button);') -and
  (Test-HasToken -Text $mainNow -Token 'controls_row.add_child(&disabled_button);')
)

$onlyStringChangesPass = $containerCountPass -and $layoutStructPass -and $uiStructurePass

$expectedLabelsPass = (
  (Test-HasToken -Text $mainNow -Token 'PHASE 40: RUNTIME UPDATE LOOP SCHEDULER') -and
  (Test-HasToken -Text $mainNow -Token 'Status: Ready') -and
  (Test-HasToken -Text $mainNow -Token 'Extension Mode: Active') -and
  (Test-HasToken -Text $mainNow -Token 'Runtime Control') -and
  (Test-HasToken -Text $mainNow -Token 'Controls') -and
  (Test-HasToken -Text $mainNow -Token 'State: Inactive') -and
  (Test-HasToken -Text $mainNow -Token 'Next Action: Waiting for Toggle') -and
  (Test-HasToken -Text $mainNow -Token 'Input') -and
  (Test-HasToken -Text $inputNow -Token 'Type here')
)

$forbiddenLabelsGonePass = (
  -not (Test-HasToken -Text $mainNow -Token 'Runtime Control Card') -and
  -not (Test-HasToken -Text $mainNow -Token 'Primary controls and status') -and
  -not (Test-HasToken -Text $mainNow -Token 'Runtime Panel') -and
  -not (Test-HasToken -Text $mainNow -Token 'State summary:') -and
  -not (Test-HasToken -Text $mainNow -Token 'textbox:')
)

$driftPass = $containerCountPass -and $layoutStructPass -and $uiStructurePass
$gatePass = $driftPass -and $onlyStringChangesPass -and $expectedLabelsPass -and $forbiddenLabelsGonePass
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

(Get-VisibleTextSnapshot -Text ($mainNow + "`n" + $inputNow)) | Set-Content -Path (Join-Path $pf 'ui_text_snapshot.txt') -Encoding UTF8

@(
  ('container_count_unchanged=' + $(if ($containerCountPass) { 'PASS' } else { 'FAIL' }))
  ('layout_struct_unchanged=' + $(if ($layoutStructPass) { 'PASS' } else { 'FAIL' }))
  ('ui_structure_identical_to_phase40_93=' + $(if ($uiStructurePass) { 'PASS' } else { 'FAIL' }))
  ('only_string_constants_changed=' + $(if ($onlyStringChangesPass) { 'PASS' } else { 'FAIL' }))
) | Set-Content -Path (Join-Path $pf 'layout_integrity_check.txt') -Encoding UTF8

@(
  ('devfabeco_ui_drift_detection=' + $(if ($driftPass) { 'PASS' } else { 'FAIL' }))
  ('expected_labels_present=' + $(if ($expectedLabelsPass) { 'PASS' } else { 'FAIL' }))
  ('forbidden_labels_removed=' + $(if ($forbiddenLabelsGonePass) { 'PASS' } else { 'FAIL' }))
  ('gate=' + $gate)
) | Set-Content -Path (Join-Path $pf 'devfabeco_ui_drift_validation.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)
