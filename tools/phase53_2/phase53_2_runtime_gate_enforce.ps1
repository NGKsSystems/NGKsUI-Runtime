Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
if ((Get-Location).Path -ne $Root) {
    Write-Output 'hey stupid Fucker, wrong window again'
    exit 1
}

$Art70 = Join-Path $Root 'control_plane\70_guard_fingerprint_trust_chain.json'
$Art110 = Join-Path $Root 'control_plane\110_trust_chain_ledger_baseline_enforcement_surface_fingerprint_trust_chain_baseline_enforcement_coverage_fingerprint_regression_anchor.json'
$Art111 = Join-Path $Root 'control_plane\111_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline.json'
$Art112 = Join-Path $Root 'control_plane\112_trust_chain_ledger_baseline_enforcement_surface_fingerprint_regression_anchor_trust_chain_baseline_integrity.json'

$Expected111RawHash = '8ee2a7e9ecff6553e8fa6ee2f31a2d495b4e080196dba222ad6ad0ffcb42ff43'
$ExpectedLedgerHead = 'c17e6b6ee0acd7905dedc1355e8bd2f070867250d0bfdb88f689e4ef15c67e22'
$ExpectedCoverageFingerprint = '234451637df78f4e655919bf671a4aee1ace2f3c03dfcd86706e6ce52a8215fe'

foreach ($path in @($Art70, $Art110, $Art111, $Art112)) {
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Output ('GATE=FAIL')
        Write-Output ('BLOCK=missing_artifact:' + $path)
        exit 1
    }
}

function Get-BytesSha256Hex {
    param([byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($Bytes)
    }
    finally {
        $sha.Dispose()
    }
    return ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
}

$raw111 = [System.IO.File]::ReadAllBytes($Art111)
$hash111 = Get-BytesSha256Hex -Bytes $raw111
if ($hash111 -ne $Expected111RawHash) {
    Write-Output 'GATE=FAIL'
    Write-Output ('BLOCK=baseline_snapshot_hash_mismatch live=' + $hash111 + ' expected=' + $Expected111RawHash)
    exit 1
}

$obj110 = Get-Content -LiteralPath $Art110 -Raw | ConvertFrom-Json
$obj111 = Get-Content -LiteralPath $Art111 -Raw | ConvertFrom-Json
$obj112 = Get-Content -LiteralPath $Art112 -Raw | ConvertFrom-Json

if ([string]$obj112.ledger_head_hash -ne $ExpectedLedgerHead) {
    Write-Output 'GATE=FAIL'
    Write-Output ('BLOCK=ledger_head_mismatch live=' + [string]$obj112.ledger_head_hash + ' expected=' + $ExpectedLedgerHead)
    exit 1
}

if ([string]$obj110.coverage_fingerprint -ne $ExpectedCoverageFingerprint) {
    Write-Output 'GATE=FAIL'
    Write-Output ('BLOCK=coverage_fingerprint_mismatch live=' + [string]$obj110.coverage_fingerprint + ' expected=' + $ExpectedCoverageFingerprint)
    exit 1
}

if ([string]$obj111.phase_locked -ne '53.1' -or [int]$obj111.baseline_version -ne 1) {
    Write-Output 'GATE=FAIL'
    Write-Output ('BLOCK=semantic_mismatch phase_locked=' + [string]$obj111.phase_locked + ' baseline_version=' + [string]$obj111.baseline_version)
    exit 1
}

$src = @($obj111.source_phases | ForEach-Object { [string]$_ }) -join ','
if ($src -ne '52.8,52.9,53.0') {
    Write-Output 'GATE=FAIL'
    Write-Output ('BLOCK=source_phase_mismatch live=' + $src)
    exit 1
}

Write-Output 'GATE=PASS'
Write-Output 'BLOCK=none'
exit 0
