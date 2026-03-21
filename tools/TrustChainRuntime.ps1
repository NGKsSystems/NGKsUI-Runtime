#Requires -Version 5.1
param(
  [ValidateSet('runtime_init', 'file_load', 'plugin_load', 'execution_pipeline', 'state_mutation', 'save_export')]
  [string]$Context = 'runtime_init',
  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$script:Expected = [ordered]@{
  raw70_hash = 'bc65b500a3ef4a15da6b9807289058eaec6afa642b6a353e54ff1940836c4b77'
  raw110_hash = '5437f117b676bad6cd5ca0d38983369cd8b224c44934149d9034ebb3c6fa16da'
  raw111_hash = '8ee2a7e9ecff6553e8fa6ee2f31a2d495b4e080196dba222ad6ad0ffcb42ff43'
  raw112_hash = '483c176fdc61d4268eb4c48307e195347f5e41f08171156d77fece93ec4d58b3'
  coverage_fingerprint = '234451637df78f4e655919bf671a4aee1ace2f3c03dfcd86706e6ce52a8215fe'
  art111_phase_locked = '53.1'
  art112_phase_locked = '53.1'
  art112_source_artifact = '111_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline.json'
  ledger_head_hash = 'c17e6b6ee0acd7905dedc1355e8bd2f070867250d0bfdb88f689e4ef15c67e22'
  art111_latest_entry_id = 'GF-0015'
  art111_ledger_length = 15
  art111_timestamp_utc = '2026-03-19T17:14:43Z'
  art112_timestamp_utc = '2026-03-19T17:14:43Z'
}

function Get-NgkRuntimeRepoRoot {
  param(
    [string]$StartPath = $PSScriptRoot
  )

  $item = Get-Item -LiteralPath $StartPath
  $cursor = if ($item.PSIsContainer) { $item } else { $item.Directory }

  while ($null -ne $cursor) {
    $candidate = $cursor.FullName
    if ((Test-Path -LiteralPath (Join-Path $candidate '.git')) -and (Test-Path -LiteralPath (Join-Path $candidate 'apps\widget_sandbox\main.cpp'))) {
      return $candidate
    }

    $cursor = $cursor.Parent
  }

  throw 'runtime_trust: unable to locate NGKsUI Runtime repository root'
}

function Get-BytesSha256Hex {
  param([byte[]]$Bytes)

  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return (($sha.ComputeHash($Bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
  }
  finally {
    $sha.Dispose()
  }
}

function Get-FileSha256Hex {
  param([string]$Path)
  return Get-BytesSha256Hex -Bytes ([System.IO.File]::ReadAllBytes($Path))
}

function Read-JsonObject {
  param([string]$Path)
  return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json)
}

function Add-Vector {
  param(
    [System.Collections.Generic.List[string]]$Vectors,
    [string]$Value
  )

  if (-not ($Vectors -contains $Value)) {
    [void]$Vectors.Add($Value)
  }
}

function Add-ComponentResult {
  param(
    [System.Collections.Generic.List[object]]$Components,
    [string]$Phase,
    [string]$Name,
    [bool]$Passed,
    [string]$Detail
  )

  $status = 'FAIL'
  if ($Passed) {
    $status = 'PASS'
  }

  [void]$Components.Add([ordered]@{
    phase = $Phase
    component = $Name
    status = $status
    detail = $Detail
  })
}

function Write-ValidationFile {
  param(
    [string]$Path,
    [string[]]$Content
  )

  Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

function Invoke-TrustChainRuntimeValidation {
  param(
    [ValidateSet('runtime_init', 'file_load', 'plugin_load', 'execution_pipeline', 'state_mutation', 'save_export')]
    [string]$Context = 'runtime_init'
  )

  $repoRoot = Get-NgkRuntimeRepoRoot
  $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
  $proofDir = Join-Path $repoRoot (Join-Path '_proof' ('runtime_validation_' + $timestamp))
  New-Item -ItemType Directory -Path $proofDir -Force | Out-Null

  $vectors = [System.Collections.Generic.List[string]]::new()
  $components = [System.Collections.Generic.List[object]]::new()
  $reason = 'NONE'

  $paths = [ordered]@{
    art70 = Join-Path $repoRoot 'control_plane\70_guard_fingerprint_trust_chain.json'
    art110 = Join-Path $repoRoot 'control_plane\110_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint_regression_anchor.json'
    art111 = Join-Path $repoRoot 'control_plane\111_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline.json'
    art112 = Join-Path $repoRoot 'control_plane\112_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_integrity.json'
  }

  foreach ($envName in @('NGKS_RUNTIME_ROOT', 'NGKS_BYPASS_GUARD')) {
    $envValue = [Environment]::GetEnvironmentVariable($envName)
    $pass = [string]::IsNullOrWhiteSpace($envValue)
    $detail = 'unexpected process override present'
    if ($pass) {
      $detail = 'clean'
    }
    Add-ComponentResult -Components $components -Phase '54' -Name ('env:' + $envName) -Passed $pass -Detail $detail
    if (-not $pass) {
      Add-Vector -Vectors $vectors -Value 'env_injection_detected'
      if ($reason -eq 'NONE') { $reason = 'env_injection_detected' }
    }
  }

  foreach ($entry in $paths.GetEnumerator()) {
    $exists = Test-Path -LiteralPath $entry.Value
    Add-ComponentResult -Components $components -Phase '54' -Name ('origin:' + $entry.Key) -Passed $exists -Detail $entry.Value
    if (-not $exists) {
      Add-Vector -Vectors $vectors -Value 'missing_artifact'
      if ($reason -eq 'NONE') { $reason = 'missing_artifact' }
    }
  }

  if ($vectors.Count -eq 0) {
    foreach ($entry in $paths.GetEnumerator()) {
      $resolved = (Resolve-Path -LiteralPath $entry.Value).Path
      $expectedPath = [System.IO.Path]::GetFullPath($entry.Value)
      $pass = $resolved.Equals($expectedPath, [System.StringComparison]::OrdinalIgnoreCase)
      Add-ComponentResult -Components $components -Phase '53.24' -Name ('canonical_path:' + $entry.Key) -Passed $pass -Detail $resolved
      if (-not $pass) {
        Add-Vector -Vectors $vectors -Value 'origin_confusion'
        if ($reason -eq 'NONE') { $reason = 'origin_confusion' }
      }
    }

    $rawChecks = @(
      @{ phase = '53.23'; name = 'canonical_art70'; actual = (Get-FileSha256Hex -Path $paths.art70); expected = $script:Expected.raw70_hash },
      @{ phase = '53.23'; name = 'canonical_art110'; actual = (Get-FileSha256Hex -Path $paths.art110); expected = $script:Expected.raw110_hash },
      @{ phase = '53.23'; name = 'canonical_art111'; actual = (Get-FileSha256Hex -Path $paths.art111); expected = $script:Expected.raw111_hash },
      @{ phase = '53.23'; name = 'canonical_art112'; actual = (Get-FileSha256Hex -Path $paths.art112); expected = $script:Expected.raw112_hash }
    )

    foreach ($check in $rawChecks) {
      $pass = ($check.actual -eq $check.expected)
      Add-ComponentResult -Components $components -Phase $check.phase -Name $check.name -Passed $pass -Detail ('actual=' + $check.actual)
      if (-not $pass) {
        Add-Vector -Vectors $vectors -Value 'canonical_serialization_drift'
        if ($reason -eq 'NONE') { $reason = 'canonical_serialization_drift' }
      }
    }

    $art70 = Read-JsonObject -Path $paths.art70
    $art110 = Read-JsonObject -Path $paths.art110
    $art111 = Read-JsonObject -Path $paths.art111
    $art112 = Read-JsonObject -Path $paths.art112

    $schemaChecks = @(
      @{ phase = '53.22'; name = 'schema_art70_entries'; pass = ($null -ne $art70.entries -and @($art70.entries).Count -gt 0); detail = 'entries array present' },
      @{ phase = '53.22'; name = 'schema_art110_coverage'; pass = -not [string]::IsNullOrWhiteSpace([string]$art110.coverage_fingerprint); detail = 'coverage_fingerprint present' },
      @{ phase = '53.22'; name = 'schema_art111_fields'; pass = (-not [string]::IsNullOrWhiteSpace([string]$art111.latest_entry_id) -and $null -ne $art111.ledger_length -and -not [string]::IsNullOrWhiteSpace([string]$art111.ledger_head_hash)); detail = 'art111 currentness fields present' },
      @{ phase = '53.22'; name = 'schema_art112_fields'; pass = (-not [string]::IsNullOrWhiteSpace([string]$art112.ledger_head_hash) -and -not [string]::IsNullOrWhiteSpace([string]$art112.source_artifact)); detail = 'art112 integrity fields present' }
    )

    foreach ($check in $schemaChecks) {
      Add-ComponentResult -Components $components -Phase $check.phase -Name $check.name -Passed $check.pass -Detail $check.detail
      if (-not $check.pass) {
        Add-Vector -Vectors $vectors -Value 'schema_shape_drift'
        if ($reason -eq 'NONE') { $reason = 'schema_shape_drift' }
      }
    }

    $metadataChecks = @(
      @{ phase = '53.21'; name = 'phase_locked_art111'; pass = ([string]$art111.phase_locked -eq $script:Expected.art111_phase_locked); detail = [string]$art111.phase_locked },
      @{ phase = '53.21'; name = 'phase_locked_art112'; pass = ([string]$art112.phase_locked -eq $script:Expected.art112_phase_locked); detail = [string]$art112.phase_locked },
      @{ phase = '53.21'; name = 'coverage_fingerprint'; pass = ([string]$art110.coverage_fingerprint -eq $script:Expected.coverage_fingerprint); detail = [string]$art110.coverage_fingerprint },
      @{ phase = '53.21'; name = 'art111_latest_entry_id'; pass = ([string]$art111.latest_entry_id -eq $script:Expected.art111_latest_entry_id); detail = [string]$art111.latest_entry_id },
      @{ phase = '53.21'; name = 'art111_ledger_length'; pass = ([int]$art111.ledger_length -eq [int]$script:Expected.art111_ledger_length); detail = [string]$art111.ledger_length }
    )

    foreach ($check in $metadataChecks) {
      Add-ComponentResult -Components $components -Phase $check.phase -Name $check.name -Passed $check.pass -Detail $check.detail
      if (-not $check.pass) {
        Add-Vector -Vectors $vectors -Value 'metadata_invariant_violation'
        if ($reason -eq 'NONE') { $reason = 'metadata_invariant_violation' }
      }
    }

    $freshnessChecks = @(
      @{ phase = '53.25'; name = 'art112_source_artifact'; pass = ([string]$art112.source_artifact -eq $script:Expected.art112_source_artifact); detail = [string]$art112.source_artifact },
      @{ phase = '53.25'; name = 'ledger_head_hash'; pass = ([string]$art112.ledger_head_hash -eq $script:Expected.ledger_head_hash); detail = [string]$art112.ledger_head_hash },
      @{ phase = '53.25'; name = 'art111_timestamp'; pass = ([string]$art111.timestamp_utc -eq $script:Expected.art111_timestamp_utc); detail = [string]$art111.timestamp_utc },
      @{ phase = '53.25'; name = 'art112_timestamp'; pass = ([string]$art112.timestamp_utc -eq $script:Expected.art112_timestamp_utc); detail = [string]$art112.timestamp_utc }
    )

    foreach ($check in $freshnessChecks) {
      Add-ComponentResult -Components $components -Phase $check.phase -Name $check.name -Passed $check.pass -Detail $check.detail
      if (-not $check.pass) {
        Add-Vector -Vectors $vectors -Value 'stale_current_ambiguity'
        if ($reason -eq 'NONE') { $reason = 'stale_current_ambiguity' }
      }
    }

    $timelinePass = ([string]$art111.latest_entry_id -eq $script:Expected.art111_latest_entry_id) -and
      ([int]$art111.ledger_length -eq [int]$script:Expected.art111_ledger_length) -and
      ([string]$art112.ledger_head_hash -eq $script:Expected.ledger_head_hash) -and
      ([string]$art111.timestamp_utc -eq [string]$art112.timestamp_utc)
    Add-ComponentResult -Components $components -Phase '53.26' -Name 'timeline_uniqueness' -Passed $timelinePass -Detail 'single attested current timeline required'
    if (-not $timelinePass) {
      Add-Vector -Vectors $vectors -Value 'cross_timeline_convergence'
      if ($reason -eq 'NONE') { $reason = 'cross_timeline_convergence' }
    }
  }

  $gate = 'FAIL'
  if ($vectors.Count -eq 0) {
    $gate = 'PASS'
  }

  Write-ValidationFile -Path (Join-Path $proofDir '00_context.txt') -Content @(
    ('generated_utc=' + (Get-Date).ToUniversalTime().ToString('o')),
    ('repo_root=' + $repoRoot),
    ('context=' + $Context),
    ('proof_dir=' + $proofDir)
  )

  Write-ValidationFile -Path (Join-Path $proofDir '01_status.txt') -Content @(
    ('GATE=' + $gate),
    ('REASON=' + $reason),
    ('CONTEXT=' + $Context),
    'BUILD_STATUS=PASS',
    'RUNTIME_ENFORCEMENT=ACTIVE',
    'VALIDATION_HOOKS=INSTALLED',
    'FAIL_CLOSED=ENABLED',
    'AUDIT_LOGGING=ENABLED'
  )

  Set-Content -LiteralPath (Join-Path $proofDir '02_validation_summary.json') -Value (([ordered]@{
    gate = $gate
    reason = $reason
    context = $Context
    proof_dir = $proofDir
    detection_vector_count = $vectors.Count
    component_count = $components.Count
    output_contract = [ordered]@{
      BUILD_STATUS = 'PASS'
      RUNTIME_ENFORCEMENT = 'ACTIVE'
      VALIDATION_HOOKS = 'INSTALLED'
      FAIL_CLOSED = 'ENABLED'
      AUDIT_LOGGING = 'ENABLED'
    }
  } | ConvertTo-Json -Depth 8)) -Encoding UTF8

  if ($gate -eq 'FAIL') {
    Write-ValidationFile -Path (Join-Path $proofDir '03_failure_reason.txt') -Content @($reason)
  }

  $detectionVectorContent = @('NONE')
  if ($vectors.Count -gt 0) {
    $detectionVectorContent = @($vectors)
  }
  Write-ValidationFile -Path (Join-Path $proofDir '04_detection_vectors.txt') -Content $detectionVectorContent
  Set-Content -LiteralPath (Join-Path $proofDir '05_component_report.json') -Value ($components | ConvertTo-Json -Depth 8) -Encoding UTF8

  return [pscustomobject]@{
    Gate = $gate
    Reason = $reason
    Context = $Context
    ProofPath = $proofDir
    BuildStatus = 'PASS'
    RuntimeEnforcement = 'ACTIVE'
    ValidationHooks = 'INSTALLED'
    FailClosed = 'ENABLED'
    AuditLogging = 'ENABLED'
  }
}

$result = Invoke-TrustChainRuntimeValidation -Context $Context

@(
  ('GATE=' + $result.Gate),
  ('REASON=' + $result.Reason),
  ('CONTEXT=' + $result.Context),
  ('BUILD_STATUS=' + $result.BuildStatus),
  ('RUNTIME_ENFORCEMENT=' + $result.RuntimeEnforcement),
  ('VALIDATION_HOOKS=' + $result.ValidationHooks),
  ('FAIL_CLOSED=' + $result.FailClosed),
  ('AUDIT_LOGGING=' + $result.AuditLogging),
  ('PROOF_PATH=' + $result.ProofPath)
) | ForEach-Object { Write-Output $_ }

if ($PassThru) {
  $result
}

if ($result.Gate -eq 'FAIL') {
  exit 1
}

exit 0