Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'

function Remove-FileWithRetry {
  param([string]$Path, [int]$MaxAttempts = 5, [int]$SleepMs = 120)
  if (-not (Test-Path -LiteralPath $Path)) { return $true }
  for ($a = 1; $a -le $MaxAttempts; $a++) {
    try { Remove-Item -LiteralPath $Path -Force -ErrorAction Stop; return $true }
    catch { if ($a -lt $MaxAttempts) { Start-Sleep -Milliseconds $SleepMs } }
  }
  return (-not (Test-Path -LiteralPath $Path))
}

function Invoke-PwshToFile {
  param(
    [string[]]$ArgumentList,
    [string]$OutFile,
    [int]$TimeoutSeconds,
    [string]$StepName
  )
  $errFile = $OutFile + '.stderr.tmp'
  if (-not (Remove-FileWithRetry -Path $errFile)) {
    return [pscustomobject]@{ ExitCode=125; TimedOut=$false; FileLock=$true }
  }
  $proc = Start-Process -FilePath 'powershell' -ArgumentList $ArgumentList -PassThru -NoNewWindow -RedirectStandardOutput $OutFile -RedirectStandardError $errFile
  $timedOut = -not $proc.WaitForExit($TimeoutSeconds * 1000)
  if ($timedOut) {
    try { $proc.Kill() } catch {}
    Add-Content -LiteralPath $OutFile -Value ('LAUNCH_ERROR=TIMEOUT step=' + $StepName)
    if (Test-Path -LiteralPath $errFile) {
      Get-Content -LiteralPath $errFile | Add-Content -LiteralPath $OutFile
      [void](Remove-FileWithRetry -Path $errFile)
    }
    return [pscustomobject]@{ ExitCode=124; TimedOut=$true; FileLock=$false }
  }
  $proc.WaitForExit(); $exitCode = $proc.ExitCode
  try { $proc.Close() } catch {}; $proc.Dispose()
  if (Test-Path -LiteralPath $errFile) {
    $stderr = Get-Content -LiteralPath $errFile -Raw
    if (-not [string]::IsNullOrWhiteSpace($stderr)) { Add-Content -LiteralPath $OutFile -Value $stderr }
    if (-not (Remove-FileWithRetry -Path $errFile)) {
      return [pscustomobject]@{ ExitCode=125; TimedOut=$false; FileLock=$true }
    }
  }
  return [pscustomobject]@{ ExitCode=$exitCode; TimedOut=$false; FileLock=$false }
}

function Get-FieldValue {
  # Returns the part after the first '=' on the first matching line, or '' if absent
  param([string[]]$Lines, [string]$Key)
  foreach ($line in $Lines) {
    if ($line -match ('^' + [regex]::Escape($Key) + '=(.*)$')) {
      return $Matches[1].Trim()
    }
  }
  return ''
}

function Get-CleanRunInfo {
  param([string]$Path)

  $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $lines) { $lines = @() }

  # Identity lines
  $launchIdentityValue = Get-FieldValue -Lines $lines -Key 'LAUNCH_IDENTITY'
  $widgetIdentityPresent = Get-FieldValue -Lines $lines -Key 'widget_launch_identity_present'
  $widgetIdentityValue = Get-FieldValue -Lines $lines -Key 'widget_launch_identity'

  # Summary line fields - parse from LAUNCH_FINAL_SUMMARY line
  $summaryLine = ($lines | Where-Object { $_ -match 'LAUNCH_FINAL_SUMMARY' } | Select-Object -Last 1)
  $summaryFinalStatus = ''; $summaryExitCode = ''; $summaryEnforcement = ''; $summaryBlocked = ''
  if ($summaryLine) {
    if ($summaryLine -match 'final_status=(\S+)') { $summaryFinalStatus = $Matches[1] }
    if ($summaryLine -match 'exit_code=(\S+)') { $summaryExitCode = $Matches[1] }
    if ($summaryLine -match 'enforcement=(\S+)') { $summaryEnforcement = $Matches[1] }
    if ($summaryLine -match 'blocked_reason=(\S+)') { $summaryBlocked = $Matches[1] }
  }

  # Gate/enforcement indicators
  $failClosedCount = @($lines | Where-Object { $_ -match '^FAIL_CLOSED=ENABLED' }).Count
  $gatePassCount   = @($lines | Where-Object { $_ -match '^GATE=PASS' }).Count
  $reasonNoneCount = @($lines | Where-Object { $_ -match '^REASON=NONE' }).Count
  $hasRuntimeOk   = [bool]($lines | Where-Object { $_ -match '^runtime_final_status=RUN_OK' })
  $hasLaunchError  = [bool]($lines | Where-Object { $_ -match '^LAUNCH_ERROR=' })

  # No-malformed check: look for lines that are just '=something' (key missing)
  # or a critical key followed by '=' then nothing (empty value for key that must be non-empty)
  $malformedLines = @($lines | Where-Object { $_ -match '^\s*=' })
  $emptyCriticalFields = @(
    @('LAUNCH_IDENTITY', 'LAUNCH_FINAL_SUMMARY', 'widget_launch_identity') | Where-Object {
      $key = $_
      @($lines | Where-Object { $_ -match ('^' + [regex]::Escape($key) + '=\s*$') }).Count -gt 0
    }
  )
  $hasMalformed = ($malformedLines.Count -gt 0) -or ($emptyCriticalFields.Count -gt 0)

  # Identity format validity: canonical|<config>|<date>
  $identityFormatOk = $launchIdentityValue -match '^canonical\|[^|]+\|20\d{2}-\d{2}-\d{2}T'
  $widgetIdentityFormatOk = $widgetIdentityValue -match '^canonical\|[^|]+\|20\d{2}-\d{2}-\d{2}T'
  $identitiesMatch = ($launchIdentityValue -ne '' -and $launchIdentityValue -eq $widgetIdentityValue)

  return [pscustomobject]@{
    LaunchIdentityValue    = $launchIdentityValue
    WidgetIdentityPresent  = ($widgetIdentityPresent -eq '1')
    WidgetIdentityValue    = $widgetIdentityValue
    IdentityFormatOk       = $identityFormatOk
    WidgetIdentityFormatOk = $widgetIdentityFormatOk
    IdentitiesMatch        = $identitiesMatch
    SummaryFinalStatus     = $summaryFinalStatus
    SummaryExitCode        = $summaryExitCode
    SummaryEnforcement     = $summaryEnforcement
    SummaryBlockedReason   = $summaryBlocked
    FailClosedCount        = $failClosedCount
    GatePassCount          = $gatePassCount
    ReasonNoneCount        = $reasonNoneCount
    HasRuntimeOk           = $hasRuntimeOk
    HasLaunchError         = $hasLaunchError
    HasMalformed           = $hasMalformed
    MalformedLines         = ($malformedLines -join '; ')
    EmptyCriticalFields    = ($emptyCriticalFields -join '; ')
  }
}

function Get-BlockedRunInfo {
  param([string]$Path)

  $lines = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $lines) { $lines = @() }

  $hasLaunchError = [bool]($lines | Where-Object { $_ -match '^LAUNCH_ERROR=' })
  $summaryLine = ($lines | Where-Object { $_ -match 'LAUNCH_FINAL_SUMMARY' } | Select-Object -Last 1)
  $summaryFinalStatus = ''; $summaryExitCode = 0; $summaryEnforcement = ''; $summaryBlocked = ''
  if ($summaryLine) {
    if ($summaryLine -match 'final_status=(\S+)') { $summaryFinalStatus = $Matches[1] }
    if ($summaryLine -match 'exit_code=(\d+)') { $summaryExitCode = [int]$Matches[1] }
    if ($summaryLine -match 'enforcement=(\S+)') { $summaryEnforcement = $Matches[1] }
    if ($summaryLine -match 'blocked_reason=(\S+)') { $summaryBlocked = $Matches[1] }
  }

  # fail-closed inside the LAUNCH_ERROR detail field
  $errLine = ($lines | Where-Object { $_ -match '^LAUNCH_ERROR=' } | Select-Object -First 1)
  $failClosedInDetail = ($errLine -match 'FAIL_CLOSED=ENABLED')
  $reasonInDetail     = ($errLine -match 'REASON=env_injection_detected')
  $gateFailInDetail   = ($errLine -match 'GATE=FAIL')

  $malformedLines = @($lines | Where-Object { $_ -match '^\s*=' })
  $hasMalformed = ($malformedLines.Count -gt 0)

  return [pscustomobject]@{
    HasLaunchError      = $hasLaunchError
    SummaryFinalStatus  = $summaryFinalStatus
    SummaryExitCode     = $summaryExitCode
    SummaryEnforcement  = $summaryEnforcement
    SummaryBlockedReason= $summaryBlocked
    FailClosedInDetail  = $failClosedInDetail
    ReasonInDetail      = $reasonInDetail
    GateFailInDetail    = $gateFailInDetail
    HasMalformed        = $hasMalformed
    MalformedLines      = ($malformedLines -join '; ')
  }
}

# ── Setup ─────────────────────────────────────────────────────────────────────
$runStart = Get-Date
$ts       = Get-Date -Format 'yyyyMMdd_HHmmss'
$pfRel    = '_proof/phase65_8_widget_operator_identity_consistency_validation_' + $ts
$pf       = Join-Path '_proof' ('phase65_8_widget_operator_identity_consistency_validation_' + $ts)
New-Item -ItemType Directory -Force -Path $pf | Out-Null

$checksPath  = Join-Path $pf '90_identity_consistency_checks.txt'
$contractPath= Join-Path $pf '99_contract_summary.txt'

$cleanArgs   = @('-NoProfile','-ExecutionPolicy','Bypass','-File','tools\run_widget_sandbox.ps1','-PassArgs','--auto-close-ms=1500')
$blockedArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-Command',
  '$env:NGKS_BYPASS_GUARD=''1''; try { & ''tools\run_widget_sandbox.ps1'' } finally { Remove-Item Env:NGKS_BYPASS_GUARD -ErrorAction SilentlyContinue }')

# ── Run scenarios ──────────────────────────────────────────────────────────────
# Scenario 1: initial clean (cold)
$out1 = Join-Path $pf '10_clean_run01_stdout.txt'
$inv1 = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $out1 -TimeoutSeconds 60 -StepName 'clean_run01'
$gen1 = (Get-Item -LiteralPath $out1).LastWriteTime -ge $runStart
$p1   = Get-CleanRunInfo -Path $out1

# Scenario 2: second clean
$out2 = Join-Path $pf '11_clean_run02_stdout.txt'
$inv2 = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $out2 -TimeoutSeconds 60 -StepName 'clean_run02'
$gen2 = (Get-Item -LiteralPath $out2).LastWriteTime -ge $runStart
$p2   = Get-CleanRunInfo -Path $out2
Start-Sleep -Milliseconds 100

# Scenario 3: third clean
$out3 = Join-Path $pf '12_clean_run03_stdout.txt'
$inv3 = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $out3 -TimeoutSeconds 60 -StepName 'clean_run03'
$gen3 = (Get-Item -LiteralPath $out3).LastWriteTime -ge $runStart
$p3   = Get-CleanRunInfo -Path $out3
Start-Sleep -Milliseconds 100

# Scenario 4: blocked
$out4 = Join-Path $pf '13_blocked_run01_stdout.txt'
$inv4 = Invoke-PwshToFile -ArgumentList $blockedArgs -OutFile $out4 -TimeoutSeconds 60 -StepName 'blocked_run01'
$gen4 = (Get-Item -LiteralPath $out4).LastWriteTime -ge $runStart
$p4   = Get-BlockedRunInfo -Path $out4

# Scenario 5: second blocked
$out5 = Join-Path $pf '14_blocked_run02_stdout.txt'
$inv5 = Invoke-PwshToFile -ArgumentList $blockedArgs -OutFile $out5 -TimeoutSeconds 60 -StepName 'blocked_run02'
$gen5 = (Get-Item -LiteralPath $out5).LastWriteTime -ge $runStart
$p5   = Get-BlockedRunInfo -Path $out5

# Scenario 6: final recovery clean
$out6 = Join-Path $pf '15_clean_recovery_stdout.txt'
$inv6 = Invoke-PwshToFile -ArgumentList $cleanArgs -OutFile $out6 -TimeoutSeconds 60 -StepName 'clean_recovery'
$gen6 = (Get-Item -LiteralPath $out6).LastWriteTime -ge $runStart
$p6   = Get-CleanRunInfo -Path $out6

# ── Cross-run consistency checks ───────────────────────────────────────────────
$cleanParsed = @($p1, $p2, $p3, $p6)
$cleanInvs   = @($inv1, $inv2, $inv3, $inv6)
$cleanGens   = @($gen1, $gen2, $gen3, $gen6)

$cleanAllRunOk          = @($cleanParsed | Where-Object { $_.SummaryFinalStatus -ne 'RUN_OK' }).Count -eq 0
$cleanAllNoLaunchError  = @($cleanParsed | Where-Object { $_.HasLaunchError }).Count -eq 0
$cleanAllFailClosed     = @($cleanParsed | Where-Object { $_.FailClosedCount -lt 1 }).Count -eq 0
$cleanAllGatePass       = @($cleanParsed | Where-Object { $_.GatePassCount -lt 1 }).Count -eq 0
$cleanAllReasonNone     = @($cleanParsed | Where-Object { $_.ReasonNoneCount -lt 1 }).Count -eq 0
$cleanAllRuntimeOk      = @($cleanParsed | Where-Object { -not $_.HasRuntimeOk }).Count -eq 0
$cleanAllNoHang         = @($cleanInvs  | Where-Object { $_.TimedOut }).Count -eq 0
$cleanAllNoFileLock     = @($cleanInvs  | Where-Object { $_.FileLock }).Count -eq 0
$cleanAllGenerated      = @($cleanGens  | Where-Object { -not $_ }).Count -eq 0
$cleanAllExitZero       = @($cleanInvs  | Where-Object { $_.ExitCode -ne 0 }).Count -eq 0
$cleanAllNoMalformed    = @($cleanParsed | Where-Object { $_.HasMalformed }).Count -eq 0
$cleanAllIdentityPresent= @($cleanParsed | Where-Object { $_.LaunchIdentityValue -eq '' }).Count -eq 0
$cleanAllWidgetIdentity = @($cleanParsed | Where-Object { -not $_.WidgetIdentityPresent }).Count -eq 0
$cleanAllIdentitiesMatch= @($cleanParsed | Where-Object { -not $_.IdentitiesMatch }).Count -eq 0
$cleanAllIdentityFormat = @($cleanParsed | Where-Object { -not $_.IdentityFormatOk }).Count -eq 0
$cleanAllWidgetIdFormat = @($cleanParsed | Where-Object { -not $_.WidgetIdentityFormatOk }).Count -eq 0

# Identity value cross-run consistency: all clean runs should have identical LAUNCH_IDENTITY
# (same binary = same exe write timestamp embedded in identity)
$uniqueIdentities = @($cleanParsed | ForEach-Object { $_.LaunchIdentityValue } | Select-Object -Unique)
$identityConsistentAcrossRuns = ($uniqueIdentities.Count -eq 1)

# Exit-code consistency across clean runs
$uniqueCleanExits = @($cleanParsed | ForEach-Object { $_.SummaryExitCode } | Select-Object -Unique)
$cleanExitConsistent = ($uniqueCleanExits.Count -eq 1 -and $uniqueCleanExits[0] -eq '0')

# enforcement=PASS consistent
$uniqueCleanEnf = @($cleanParsed | ForEach-Object { $_.SummaryEnforcement } | Select-Object -Unique)
$cleanEnforcementConsistent = ($uniqueCleanEnf.Count -eq 1 -and $uniqueCleanEnf[0] -eq 'PASS')

# blocked_reason=NONE consistent for cleans
$uniqueCleanBlocked = @($cleanParsed | ForEach-Object { $_.SummaryBlockedReason } | Select-Object -Unique)
$cleanBlockedNoneConsistent = ($uniqueCleanBlocked.Count -eq 1 -and $uniqueCleanBlocked[0] -eq 'NONE')

# Blocked runs cross-run consistency
$blockedParsed = @($p4, $p5)
$blockedBothBlocked      = @($blockedParsed | Where-Object { $_.SummaryFinalStatus -ne 'BLOCKED' }).Count -eq 0
$blockedBothHasError     = @($blockedParsed | Where-Object { -not $_.HasLaunchError }).Count -eq 0
$blockedBothFailClosed   = @($blockedParsed | Where-Object { -not $_.FailClosedInDetail }).Count -eq 0
$blockedBothReason       = @($blockedParsed | Where-Object { -not $_.ReasonInDetail }).Count -eq 0
$blockedBothGateFail     = @($blockedParsed | Where-Object { -not $_.GateFailInDetail }).Count -eq 0
$blockedBothExitNonZero  = @($blockedParsed | Where-Object { $_.SummaryExitCode -le 0 }).Count -eq 0
$blockedBothNoHang       = (-not $inv4.TimedOut) -and (-not $inv5.TimedOut)
$blockedBothNoMalformed  = @($blockedParsed | Where-Object { $_.HasMalformed }).Count -eq 0
$uniqueBlockedEnf        = @($blockedParsed | ForEach-Object { $_.SummaryEnforcement } | Select-Object -Unique)
$blockedEnfConsistent    = ($uniqueBlockedEnf.Count -eq 1 -and $uniqueBlockedEnf[0] -eq 'FAIL')
$uniqueBlockedReason     = @($blockedParsed | ForEach-Object { $_.SummaryBlockedReason } | Select-Object -Unique)
$blockedReasonConsistent = ($uniqueBlockedReason.Count -eq 1 -and $uniqueBlockedReason[0] -eq 'TRUST_CHAIN_BLOCKED')
$uniqueBlockedExit       = @($blockedParsed | ForEach-Object { [string]$_.SummaryExitCode } | Select-Object -Unique)
$blockedExitConsistent   = ($uniqueBlockedExit.Count -eq 1)

Start-Sleep -Milliseconds 300
$widgetProcCount = @(Get-Process -Name 'widget_sandbox' -ErrorAction SilentlyContinue).Count
$cleanupStable = ($widgetProcCount -eq 0)

# ── Build failed-check list ────────────────────────────────────────────────────
$failed = [System.Collections.Generic.List[string]]::new()

if (-not $cleanAllGenerated)         { $failed.Add('check_clean_all_generated_in_run=NO') }
if (-not $cleanAllRunOk)             { $failed.Add('check_clean_all_run_ok=NO') }
if (-not $cleanAllNoLaunchError)     { $failed.Add('check_clean_all_no_launch_error=NO') }
if (-not $cleanAllFailClosed)        { $failed.Add('check_clean_all_fail_closed=NO') }
if (-not $cleanAllGatePass)          { $failed.Add('check_clean_all_gate_pass=NO') }
if (-not $cleanAllReasonNone)        { $failed.Add('check_clean_all_reason_none=NO') }
if (-not $cleanAllRuntimeOk)         { $failed.Add('check_clean_all_runtime_ok=NO') }
if (-not $cleanAllNoHang)            { $failed.Add('check_clean_all_no_hang=NO') }
if (-not $cleanAllNoFileLock)        { $failed.Add('check_clean_all_no_file_lock=NO') }
if (-not $cleanAllExitZero)          { $failed.Add('check_clean_all_wrapper_exit_zero=NO') }
if (-not $cleanAllNoMalformed)       { $failed.Add('check_clean_all_no_malformed_fields=NO') }
if (-not $cleanAllIdentityPresent)   { $failed.Add('check_clean_all_launch_identity_present=NO') }
if (-not $cleanAllWidgetIdentity)    { $failed.Add('check_clean_all_widget_identity_present=NO') }
if (-not $cleanAllIdentitiesMatch)   { $failed.Add('check_clean_all_identities_match=NO') }
if (-not $cleanAllIdentityFormat)    { $failed.Add('check_clean_all_launch_identity_format=NO') }
if (-not $cleanAllWidgetIdFormat)    { $failed.Add('check_clean_all_widget_identity_format=NO') }
if (-not $identityConsistentAcrossRuns) { $failed.Add('check_launch_identity_consistent_across_runs=NO') }
if (-not $cleanExitConsistent)       { $failed.Add('check_clean_summary_exit_code_consistent=NO') }
if (-not $cleanEnforcementConsistent){ $failed.Add('check_clean_enforcement_consistent=NO') }
if (-not $cleanBlockedNoneConsistent){ $failed.Add('check_clean_blocked_reason_none_consistent=NO') }
if (-not $blockedBothBlocked)        { $failed.Add('check_blocked_all_final_status_blocked=NO') }
if (-not $blockedBothHasError)       { $failed.Add('check_blocked_all_launch_error_present=NO') }
if (-not $blockedBothFailClosed)     { $failed.Add('check_blocked_all_fail_closed_in_detail=NO') }
if (-not $blockedBothReason)         { $failed.Add('check_blocked_all_reason_coherent=NO') }
if (-not $blockedBothGateFail)       { $failed.Add('check_blocked_all_gate_fail_in_detail=NO') }
if (-not $blockedBothExitNonZero)    { $failed.Add('check_blocked_all_exit_nonzero=NO') }
if (-not $blockedBothNoHang)         { $failed.Add('check_blocked_all_no_hang=NO') }
if (-not $blockedBothNoMalformed)    { $failed.Add('check_blocked_all_no_malformed_fields=NO') }
if (-not $blockedEnfConsistent)      { $failed.Add('check_blocked_enforcement_fail_consistent=NO') }
if (-not $blockedReasonConsistent)   { $failed.Add('check_blocked_reason_trust_chain_consistent=NO') }
if (-not $blockedExitConsistent)     { $failed.Add('check_blocked_summary_exit_code_consistent=NO') }
if ($gen4 -eq $false)               { $failed.Add('check_blocked_run01_generated_in_run=NO') }
if ($gen5 -eq $false)               { $failed.Add('check_blocked_run02_generated_in_run=NO') }
if (-not $cleanupStable)             { $failed.Add('check_cleanup_stable=NO') }

$allOk           = ($failed.Count -eq 0)
$regressionsVal  = if ($allOk) { 'NO' } else { 'YES' }
$phaseStatusVal  = if ($allOk) { 'PASS' } else { 'FAIL' }

# ── Write checks file ──────────────────────────────────────────────────────────
$rows = [System.Collections.Generic.List[string]]::new()
$rows.Add('proof_folder=' + $pfRel)
$rows.Add('clean_run_count=4')
$rows.Add('blocked_run_count=2')

# Per clean-run detail
$cleanNames = @('clean_run01','clean_run02','clean_run03','clean_recovery')
$cleanOuts  = @($out1,$out2,$out3,$out6)
for ($ci = 0; $ci -lt $cleanParsed.Count; $ci++) {
  $cp   = $cleanParsed[$ci]
  $cinv = $cleanInvs[$ci]
  $cg   = $cleanGens[$ci]
  $cn   = $cleanNames[$ci]
  $cf   = $pfRel + '/' + [System.IO.Path]::GetFileName($cleanOuts[$ci])
  $rows.Add($cn + '_file=' + $cf)
  $rows.Add($cn + '_generated_in_run=' + $(if ($cg) { 'YES' } else { 'NO' }))
  $rows.Add($cn + '_launch_identity=' + $cp.LaunchIdentityValue)
  $rows.Add($cn + '_launch_identity_format_ok=' + $(if ($cp.IdentityFormatOk) { 'YES' } else { 'NO' }))
  $rows.Add($cn + '_widget_identity_present=' + $(if ($cp.WidgetIdentityPresent) { 'YES' } else { 'NO' }))
  $rows.Add($cn + '_widget_identity=' + $cp.WidgetIdentityValue)
  $rows.Add($cn + '_widget_identity_format_ok=' + $(if ($cp.WidgetIdentityFormatOk) { 'YES' } else { 'NO' }))
  $rows.Add($cn + '_identities_match=' + $(if ($cp.IdentitiesMatch) { 'YES' } else { 'NO' }))
  $rows.Add($cn + '_final_status=' + $cp.SummaryFinalStatus)
  $rows.Add($cn + '_summary_exit_code=' + $cp.SummaryExitCode)
  $rows.Add($cn + '_summary_enforcement=' + $cp.SummaryEnforcement)
  $rows.Add($cn + '_summary_blocked_reason=' + $cp.SummaryBlockedReason)
  $rows.Add($cn + '_fail_closed_count=' + $cp.FailClosedCount)
  $rows.Add($cn + '_gate_pass_count=' + $cp.GatePassCount)
  $rows.Add($cn + '_reason_none_count=' + $cp.ReasonNoneCount)
  $rows.Add($cn + '_runtime_ok=' + $(if ($cp.HasRuntimeOk) { 'YES' } else { 'NO' }))
  $rows.Add($cn + '_no_hang=' + $(if (-not $cinv.TimedOut) { 'YES' } else { 'NO' }))
  $rows.Add($cn + '_wrapper_exit=' + $cinv.ExitCode)
  $rows.Add($cn + '_no_malformed_fields=' + $(if (-not $cp.HasMalformed) { 'YES' } else { 'NO' }))
}

# Per blocked-run detail
$blockedNames = @('blocked_run01','blocked_run02')
$blockedOuts  = @($out4,$out5)
$blockedInvs  = @($inv4,$inv5)
$blockedGens  = @($gen4,$gen5)
for ($bi = 0; $bi -lt $blockedParsed.Count; $bi++) {
  $bp  = $blockedParsed[$bi]
  $bn  = $blockedNames[$bi]
  $biv = $blockedInvs[$bi]
  $bg  = $blockedGens[$bi]
  $bf  = $pfRel + '/' + [System.IO.Path]::GetFileName($blockedOuts[$bi])
  $rows.Add($bn + '_file=' + $bf)
  $rows.Add($bn + '_generated_in_run=' + $(if ($bg) { 'YES' } else { 'NO' }))
  $rows.Add($bn + '_launch_error_present=' + $(if ($bp.HasLaunchError) { 'YES' } else { 'NO' }))
  $rows.Add($bn + '_final_status=' + $bp.SummaryFinalStatus)
  $rows.Add($bn + '_summary_exit_code=' + $bp.SummaryExitCode)
  $rows.Add($bn + '_summary_enforcement=' + $bp.SummaryEnforcement)
  $rows.Add($bn + '_summary_blocked_reason=' + $bp.SummaryBlockedReason)
  $rows.Add($bn + '_fail_closed_in_detail=' + $(if ($bp.FailClosedInDetail) { 'YES' } else { 'NO' }))
  $rows.Add($bn + '_gate_fail_in_detail=' + $(if ($bp.GateFailInDetail) { 'YES' } else { 'NO' }))
  $rows.Add($bn + '_reason_in_detail=' + $(if ($bp.ReasonInDetail) { 'YES' } else { 'NO' }))
  $rows.Add($bn + '_no_hang=' + $(if (-not $biv.TimedOut) { 'YES' } else { 'NO' }))
  $rows.Add($bn + '_no_malformed_fields=' + $(if (-not $bp.HasMalformed) { 'YES' } else { 'NO' }))
}

# Aggregate checks
$rows.Add('check_clean_all_generated_in_run=' + $(if ($cleanAllGenerated) { 'YES' } else { 'NO' }))
$rows.Add('check_clean_all_run_ok=' + $(if ($cleanAllRunOk) { 'YES' } else { 'NO' }))
$rows.Add('check_clean_all_no_launch_error=' + $(if ($cleanAllNoLaunchError) { 'YES' } else { 'NO' }))
$rows.Add('check_clean_all_fail_closed=' + $(if ($cleanAllFailClosed) { 'YES' } else { 'NO' }))
$rows.Add('check_clean_all_gate_pass=' + $(if ($cleanAllGatePass) { 'YES' } else { 'NO' }))
$rows.Add('check_clean_all_reason_none=' + $(if ($cleanAllReasonNone) { 'YES' } else { 'NO' }))
$rows.Add('check_clean_all_runtime_ok=' + $(if ($cleanAllRuntimeOk) { 'YES' } else { 'NO' }))
$rows.Add('check_clean_all_no_hang=' + $(if ($cleanAllNoHang) { 'YES' } else { 'NO' }))
$rows.Add('check_clean_all_wrapper_exit_zero=' + $(if ($cleanAllExitZero) { 'YES' } else { 'NO' }))
$rows.Add('check_clean_all_no_malformed_fields=' + $(if ($cleanAllNoMalformed) { 'YES' } else { 'NO' }))
$rows.Add('check_clean_all_launch_identity_present=' + $(if ($cleanAllIdentityPresent) { 'YES' } else { 'NO' }))
$rows.Add('check_clean_all_widget_identity_present=' + $(if ($cleanAllWidgetIdentity) { 'YES' } else { 'NO' }))
$rows.Add('check_clean_all_identities_match=' + $(if ($cleanAllIdentitiesMatch) { 'YES' } else { 'NO' }))
$rows.Add('check_clean_all_launch_identity_format=' + $(if ($cleanAllIdentityFormat) { 'YES' } else { 'NO' }))
$rows.Add('check_clean_all_widget_identity_format=' + $(if ($cleanAllWidgetIdFormat) { 'YES' } else { 'NO' }))
$rows.Add('check_launch_identity_consistent_across_runs=' + $(if ($identityConsistentAcrossRuns) { 'YES' } else { 'NO' }))
$rows.Add('check_clean_summary_exit_code_consistent=' + $(if ($cleanExitConsistent) { 'YES' } else { 'NO' }))
$rows.Add('check_clean_enforcement_consistent=' + $(if ($cleanEnforcementConsistent) { 'YES' } else { 'NO' }))
$rows.Add('check_clean_blocked_reason_none_consistent=' + $(if ($cleanBlockedNoneConsistent) { 'YES' } else { 'NO' }))
$rows.Add('check_blocked_all_final_status_blocked=' + $(if ($blockedBothBlocked) { 'YES' } else { 'NO' }))
$rows.Add('check_blocked_all_launch_error_present=' + $(if ($blockedBothHasError) { 'YES' } else { 'NO' }))
$rows.Add('check_blocked_all_fail_closed_in_detail=' + $(if ($blockedBothFailClosed) { 'YES' } else { 'NO' }))
$rows.Add('check_blocked_all_reason_coherent=' + $(if ($blockedBothReason) { 'YES' } else { 'NO' }))
$rows.Add('check_blocked_all_gate_fail_in_detail=' + $(if ($blockedBothGateFail) { 'YES' } else { 'NO' }))
$rows.Add('check_blocked_all_exit_nonzero=' + $(if ($blockedBothExitNonZero) { 'YES' } else { 'NO' }))
$rows.Add('check_blocked_all_no_hang=' + $(if ($blockedBothNoHang) { 'YES' } else { 'NO' }))
$rows.Add('check_blocked_all_no_malformed_fields=' + $(if ($blockedBothNoMalformed) { 'YES' } else { 'NO' }))
$rows.Add('check_blocked_enforcement_fail_consistent=' + $(if ($blockedEnfConsistent) { 'YES' } else { 'NO' }))
$rows.Add('check_blocked_reason_trust_chain_consistent=' + $(if ($blockedReasonConsistent) { 'YES' } else { 'NO' }))
$rows.Add('check_blocked_summary_exit_code_consistent=' + $(if ($blockedExitConsistent) { 'YES' } else { 'NO' }))
$rows.Add('check_cleanup_stable=' + $(if ($cleanupStable) { 'YES' } else { 'NO' }))
$rows.Add('unique_launch_identities=' + ($uniqueIdentities -join ' | '))
$rows.Add('unique_clean_summary_exits=' + ($uniqueCleanExits -join ','))
$rows.Add('unique_blocked_summary_exits=' + ($uniqueBlockedExit -join ','))
$rows.Add('widget_process_count_after_validation=' + $widgetProcCount)
$rows.Add('failed_check_count=' + $failed.Count)
$rows.Add('failed_checks=' + $(if ($failed.Count -gt 0) { ($failed -join ';') } else { 'NONE' }))
$rows | Set-Content -LiteralPath $checksPath -Encoding UTF8

# ── Zip ────────────────────────────────────────────────────────────────────────
$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

# ── Contract ───────────────────────────────────────────────────────────────────
$contractRows = [System.Collections.Generic.List[string]]::new()
$contractRows.Add('next_phase_selected=PHASE65_8_WIDGET_OPERATOR_LAUNCH_IDENTITY_AND_SUMMARY_FIELD_CONSISTENCY_VALIDATION')
$contractRows.Add('objective=Validate that LAUNCH_IDENTITY, widget_launch_identity, final_status, exit_code, enforcement, blocked_reason, and fail-closed indicators are internally coherent, correctly formatted, and consistent across repeated clean and blocked launches with no malformed or split fields.')
$contractRows.Add('changes_introduced=tools/_tmp_phase65_8_widget_operator_identity_consistency_runner.ps1 (identity/summary-field consistency runner only).')
$contractRows.Add('runtime_behavior_changes=NONE')
$contractRows.Add('new_regressions_detected=' + $regressionsVal)
$contractRows.Add('phase_status=' + $phaseStatusVal)
$contractRows.Add('proof_folder=' + $pfRel)
$contractRows | Set-Content -LiteralPath $contractPath -Encoding UTF8

Write-Output ('phase65_8_folder=' + $pfRel)
Write-Output ('phase65_8_status=' + $phaseStatusVal)
Write-Output ('phase65_8_zip=' + $pfRel + '.zip')
