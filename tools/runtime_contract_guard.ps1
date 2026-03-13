param(
  [string]$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime',
  [switch]$WriteReports = $true
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Set-Location $Root

$validationDir = Join-Path $Root 'tools/validation'
if (-not (Test-Path -LiteralPath $validationDir)) {
  New-Item -ItemType Directory -Path $validationDir | Out-Null
}

$sourceReport = Join-Path $validationDir 'source_tree_contract_report.txt'
$graphReport = Join-Path $validationDir 'build_graph_integrity.txt'
$apiReport = Join-Path $validationDir 'renderer_api_contract.txt'

$sourceFiles = Get-ChildItem -Path (Join-Path $Root 'engine') -Recurse -File -Include *.cpp,*.hpp
$cppFiles = $sourceFiles | Where-Object { $_.Extension -eq '.cpp' }
$headerFiles = $sourceFiles | Where-Object { $_.Extension -eq '.hpp' }

$globalHeaderLookup = @{}
foreach ($hdr in $headerFiles) {
  $globalHeaderLookup[$hdr.Name.ToLowerInvariant()] = $true
}

function Resolve-Include {
  param(
    [string]$IncludeText,
    [string]$FromDir,
    [string[]]$IncludeDirs
  )

  $candidates = @()
  $candidates += (Join-Path $FromDir $IncludeText)
  foreach ($inc in $IncludeDirs) {
    $candidates += (Join-Path $Root (Join-Path $inc $IncludeText))
  }

  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }
  return $null
}

$includeDirs = @(
  'engine/core/include',
  'engine/gfx/include',
  'engine/gfx/win32/include',
  'engine/platform/win32/include',
  'engine/ui',
  'engine/ui/include'
)

$missingIncludes = New-Object System.Collections.Generic.List[string]
$cppHeaderWarnings = New-Object System.Collections.Generic.List[string]

foreach ($cpp in $cppFiles) {
  $cppDir = Split-Path -Parent $cpp.FullName
  $stem = [System.IO.Path]::GetFileNameWithoutExtension($cpp.Name)
  $neighborHeader = Join-Path $cppDir ($stem + '.hpp')
  if (-not (Test-Path -LiteralPath $neighborHeader) -and -not $globalHeaderLookup.ContainsKey(($stem + '.hpp').ToLowerInvariant())) {
    $cppHeaderWarnings.Add("WARN no obvious matching header for $($cpp.FullName.Substring($Root.Length + 1))")
  }

  $lines = Get-Content -LiteralPath $cpp.FullName
  foreach ($line in $lines) {
    $m = [regex]::Match($line, '^\s*#include\s*"([^"]+)"')
    if (-not $m.Success) { continue }
    $incText = $m.Groups[1].Value
    $resolved = Resolve-Include -IncludeText $incText -FromDir $cppDir -IncludeDirs $includeDirs
    if (-not $resolved) {
      $missingIncludes.Add("MISSING include '$incText' referenced by $($cpp.FullName.Substring($Root.Length + 1))")
    }
  }
}

$planPath = Join-Path $Root 'build_graph/debug/ngksbuildcore_plan.json'
if (-not (Test-Path -LiteralPath $planPath)) {
  throw "Missing build graph plan: $planPath"
}

$plan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json
$graphMissingSources = New-Object System.Collections.Generic.List[string]
$graphCppRefs = New-Object System.Collections.Generic.List[string]
foreach ($node in $plan.nodes) {
  foreach ($input in $node.inputs) {
    $inputText = [string]$input
    if ($inputText -like '*.cpp') {
      $graphCppRefs.Add($inputText)
      $full = Join-Path $Root $inputText
      if (-not (Test-Path -LiteralPath $full)) {
        $graphMissingSources.Add("MISSING source '$inputText' referenced by node '$($node.id)'")
      }
    }
  }
}

$uiFiles = Get-ChildItem -Path (Join-Path $Root 'engine/ui') -Recurse -File -Include *.cpp,*.hpp
$rendererHeaderPath = Join-Path $Root 'engine/gfx/win32/include/ngk/gfx/d3d11_renderer.hpp'
$rendererHeaderText = Get-Content -Raw -LiteralPath $rendererHeaderPath
$declMatches = [regex]::Matches($rendererHeaderText, '\b([A-Za-z_][A-Za-z0-9_]*)\s*\([^;{}]*\)\s*;')
$declaredMethods = @{}
foreach ($m in $declMatches) {
  $name = $m.Groups[1].Value
  if ($name -in @('if','for','while','switch','return')) { continue }
  $declaredMethods[$name] = $true
}

$calledMethods = New-Object System.Collections.Generic.HashSet[string]
foreach ($f in $uiFiles) {
  $lines = Get-Content -LiteralPath $f.FullName
  foreach ($line in $lines) {
    foreach ($m in [regex]::Matches($line, '\brenderer\.([A-Za-z_][A-Za-z0-9_]*)\s*\(')) {
      [void]$calledMethods.Add($m.Groups[1].Value)
    }
  }
}

$apiMismatches = New-Object System.Collections.Generic.List[string]
foreach ($name in $calledMethods) {
  if (-not $declaredMethods.ContainsKey($name)) {
    $apiMismatches.Add("MISSING renderer API method '$name' declared in d3d11_renderer.hpp")
  }
}

if ($WriteReports) {
  @(
    'PHASE 40.29 source tree contract scan',
    "timestamp=$(Get-Date -Format o)",
    "root=$Root",
    "scan_roots=engine/,engine/core/,engine/gfx/,engine/ui/",
    "cpp_count=$($cppFiles.Count)",
    "header_count=$($headerFiles.Count)",
    "missing_includes_count=$($missingIncludes.Count)",
    "cpp_header_warning_count=$($cppHeaderWarnings.Count)",
    '--- missing includes ---'
  ) + ($missingIncludes | Sort-Object) + @('--- cpp/header pairing warnings ---') + ($cppHeaderWarnings | Sort-Object) | Set-Content -Path $sourceReport -Encoding UTF8

  @(
    'PHASE 40.29 build graph integrity',
    "timestamp=$(Get-Date -Format o)",
    "plan=$planPath",
    "compile_cpp_refs_count=$($graphCppRefs.Count)",
    "missing_source_refs_count=$($graphMissingSources.Count)",
    '--- compile cpp refs ---'
  ) + (($graphCppRefs | Sort-Object -Unique) | ForEach-Object { "OK $_" }) + @('--- missing source refs ---') + ($graphMissingSources | Sort-Object) | Set-Content -Path $graphReport -Encoding UTF8

  @(
    'PHASE 40.29 renderer API contract',
    "timestamp=$(Get-Date -Format o)",
    "renderer_header=$rendererHeaderPath",
    "declared_method_count=$($declaredMethods.Count)",
    "ui_called_method_count=$($calledMethods.Count)",
    "api_mismatch_count=$($apiMismatches.Count)",
    '--- ui-called methods ---'
  ) + (($calledMethods | Sort-Object) | ForEach-Object { "CALL $_" }) + @('--- api mismatches ---') + ($apiMismatches | Sort-Object) | Set-Content -Path $apiReport -Encoding UTF8
}

$failed = $false
$failReasons = New-Object System.Collections.Generic.List[string]
if ($graphMissingSources.Count -gt 0) {
  $failed = $true
  $failReasons.Add("missing build-graph source refs: $($graphMissingSources.Count)")
}
if ($missingIncludes.Count -gt 0) {
  $failed = $true
  $failReasons.Add("missing source includes: $($missingIncludes.Count)")
}
if ($apiMismatches.Count -gt 0) {
  $failed = $true
  $failReasons.Add("renderer API mismatches: $($apiMismatches.Count)")
}

if ($failed) {
  Write-Output 'runtime_contract_guard=FAIL'
  foreach ($r in $failReasons) { Write-Output "reason=$r" }
  exit 1
}

Write-Output 'runtime_contract_guard=PASS'
Write-Output "reports=$validationDir"
exit 0
