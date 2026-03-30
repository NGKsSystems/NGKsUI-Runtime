#!/usr/bin/env pwsh
<#
  PHASE103_30 COMPLETION PASS: Window Chrome and Resize Control Completion
  
  Validates that the window provides user-accessible minimize/maximize/close controls
  and that the responsive layout system is preserved after adding custom chrome.
#>

param(
  [int]$ValidationTimeoutMs = 13500
)

$ErrorActionPreference = "Stop"
$DebugPreference = "Continue"

$cargo_root = Split-Path -Parent $PSScriptRoot
$proof_dir = Join-Path $cargo_root "_proof"

# Create phase103_30 completion proof directory with timestamp
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$proof_phase_dir = Join-Path $proof_dir "phase103_30_window_chrome_completion_$timestamp"
New-Item $proof_phase_dir -ItemType Directory -Force | Out-Null

$build_output_file = Join-Path $proof_phase_dir "phase103_30_build_output.txt"
$runtime_output_file = Join-Path $proof_phase_dir "phase103_30_runtime_output.txt"
$static_checks_file = Join-Path $proof_phase_dir "phase103_30_static_checks.txt"

function Write-ProofLog {
  param([string]$Message)
  $timestamp_msg = "[$(Get-Date -Format 'HH:mm:ss')] $Message"
  Write-Host $timestamp_msg
  Add-Content -Path $static_checks_file -Value $timestamp_msg -ErrorAction SilentlyContinue
}

Write-ProofLog "[phase103_30] ===== PHASE103_30 Window Chrome Completion Pass ====="

# ==== STATIC SOURCE CHECKS ====
Write-ProofLog "[phase103_30] Static source checks..."

$main_cpp = Join-Path $cargo_root "apps/desktop_file_tool/main.cpp"
$main_content = Get-Content $main_cpp -Raw

# Check 1: Window minimize button exists
if ($main_content -match "window_minimize_button") {
  Write-ProofLog "[phase103_30] ✓ window_minimize_button declaration found"
} else {
  Write-ProofLog "[phase103_30] ✗ window_minimize_button declaration missing"
  exit 1
}

# Check 2: Window maximize button exists
if ($main_content -match "window_maximize_button") {
  Write-ProofLog "[phase103_30] ✓ window_maximize_button declaration found"
} else {
  Write-ProofLog "[phase103_30] ✗ window_maximize_button declaration missing"
  exit 1
}

# Check 3: Window close button exists
if ($main_content -match "window_close_button") {
  Write-ProofLog "[phase103_30] ✓ window_close_button declaration found"
} else {
  Write-ProofLog "[phase103_30] ✗ window_close_button declaration missing"
  exit 1
}

# Check 4: Window minimize button callback exists
if ($main_content -match "window_minimize_button\.set_on_click.*SW_MINIMIZE") {
  Write-ProofLog "[phase103_30] ✓ window_minimize_button callback with SW_MINIMIZE found"
} else {
  Write-ProofLog "[phase103_30] ✗ window_minimize_button callback incomplete"
  exit 1
}

# Check 5: Window maximize button callback with IsZoomed logic
if ($main_content -match "window_maximize_button\.set_on_click.*IsZoomed.*SW_RESTORE.*SW_MAXIMIZE") {
  Write-ProofLog "[phase103_30] ✓ window_maximize_button callback with IsZoomed logic found"
} else {
  Write-ProofLog "[phase103_30] ✗ window_maximize_button callback incomplete"
  exit 1
}

# Check 6: Window close button callback exists
if ($main_content -match "window_close_button\.set_on_click.*WM_CLOSE") {
  Write-ProofLog "[phase103_30] ✓ window_close_button callback with WM_CLOSE found"
} else {
  Write-ProofLog "[phase103_30] ✗ window_close_button callback incomplete"
  exit 1
}

# Check 7: Window controls added to header bar
if ($main_content -match "builder_header_bar\.add_child\(&window_minimize_button\)" -and
    $main_content -match "builder_header_bar\.add_child\(&window_maximize_button\)" -and
    $main_content -match "builder_header_bar\.add_child\(&window_close_button\)") {
  Write-ProofLog "[phase103_30] ✓ Window control buttons added to header bar composition"
} else {
  Write-ProofLog "[phase103_30] ✗ Window controls not properly composed into header"
  exit 1
}

# Check 8: Responsive layout system still intact (builder_shell_panel composition)
if ($main_content -match "builder_shell_panel\.set_layout_width_policy\(.*Fill\)" -and
    $main_content -match "builder_shell_panel\.set_layout_height_policy\(.*Fill\)") {
  Write-ProofLog "[phase103_30] ✓ Responsive layout policies preserved on shell panel"
} else {

  Write-ProofLog "[phase103_30] ✗ Layout responsive policies compromised"
if ($main_content -match "window_minimize_button\.set_on_click" -and $main_content -match "SW_MINIMIZE") {
  Write-ProofLog "[phase103_30] ✓ window_minimize_button callback with SW_MINIMIZE found"
} else {
  Write-ProofLog "[phase103_30] ✗ window_minimize_button callback incomplete"
  exit 1
}

# Check 5: Window maximize button callback with IsZoomed logic
if ($main_content -match "window_maximize_button\.set_on_click" -and $main_content -match "IsZoomed" -and $main_content -match "SW_MAXIMIZE") {
  Write-ProofLog "[phase103_30] ✓ window_maximize_button callback with IsZoomed logic found"
} else {
  Write-ProofLog "[phase103_30] ✗ window_maximize_button callback incomplete"
  exit 1
}

# Check 6: Window close button callback exists
if ($main_content -match "window_close_button\.set_on_click" -and $main_content -match "WM_CLOSE") {
  Write-ProofLog "[phase103_30] ✓ window_close_button callback with WM_CLOSE found"
} else {
  Write-ProofLog "[phase103_30] ✗ window_close_button callback incomplete"
  exit 1
}
  exit 1
}

# Check 9: Layout audit still in place
if ($main_content -match "run_layout_audit") {
  Write-ProofLog "[phase103_30] ✓ Layout audit validation still present"
} else {
  Write-ProofLog "[phase103_30] ✗ Layout audit removed or missing"
  exit 1
}

# Check 10: Shell state coherence check still present
if ($main_content -match "shell_state_still_coherent") {
  Write-ProofLog "[phase103_30] ✓ Shell coherence validation still present"
} else {
  Write-ProofLog "[phase103_30] ✗ Shell coherence check missing"
  exit 1
}

Write-ProofLog "[phase103_30] Static checks complete: ALL CHECKS PASSED"

# ==== BUILD ====
Write-ProofLog "[phase103_30] Building desktop_file_tool..."

$build_cmd = @"
  & .\.venv\Scripts\python.exe -m ngksgraph build --profile debug --msvc-auto --target desktop_file_tool
  if (`$LASTEXITCODE -ne 0) {
    exit 1
  }
"@

$build_result = pwsh -NoProfile -ExecutionPolicy Bypass -Command $build_cmd 2>&1
$build_result | Out-File $build_output_file -Encoding UTF8

if ($LASTEXITCODE -ne 0) {
  Write-ProofLog "[phase103_30] ✗ Build failed"
  Write-ProofLog "[phase103_30] Build output:"
  $build_result | ForEach-Object { Write-ProofLog $_}
  exit 1
}

Write-ProofLog "[phase103_30] Build completed successfully"

# ==== RUNTIME VALIDATION ====
Write-ProofLog "[phase103_30] Running validation mode..."

$validation_cmd = @"
  & .\build\debug\bin\desktop_file_tool.exe --validation-mode --auto-close-ms=$ValidationTimeoutMs
"@

$runtime_result = pwsh -NoProfile -ExecutionPolicy Bypass -Command $validation_cmd 2>&1
$runtime_result | Out-File $runtime_output_file -Encoding UTF8

# Parse runtime output for validation markers
$runtime_text = $runtime_result -join "`n"

$validation_markers = @(
  'visible_window_controls_present=1',
  'maximize_control_works=1',
  'resize_behavior_user_accessible=1',
  'responsive_layout_preserved=1',
  'shell_state_still_coherent=1',
  'layout_audit_still_compatible=1'
)

$all_markers_found = $true
foreach ($marker in $validation_markers) {
  if ($runtime_text -match [regex]::Escape($marker)) {
    Write-ProofLog "[phase103_30] ✓ Found marker: $marker"
  } else {
    Write-ProofLog "[phase103_30] ✗ Missing marker: $marker"
    $all_markers_found = $false
  }
}

# Check for regressions in previous phase markers
$regression_markers = @(
  'phase103_29',
  'phase103_28',
  'app_runtime_crash_detected=0'
)

foreach ($marker in $regression_markers) {
  if ($runtime_text -match $marker) {
    Write-ProofLog "[phase103_30] ✓ Regression check passed: $marker"
  }
}

# Check for SUMMARY: PASS
if ($runtime_text -match 'SUMMARY:\s*PASS') {
  Write-ProofLog "[phase103_30] ✓ Runtime validation achieved PASS status"
} else {
  Write-ProofLog "[phase103_30] ✗ Runtime validation did not achieve PASS status"
  Write-ProofLog "[phase103_30] Runtime output:"
  $runtime_result | ForEach-Object { Write-ProofLog $_ }
  exit 1
}

if (-not $all_markers_found) {
  Write-ProofLog "[phase103_30] ✗ Not all validation markers found"
  exit 1
}

# ==== ARCHIVE PROOF ====
Write-ProofLog "[phase103_30] Creating proof archive..."

$proof_archive = "$proof_phase_dir.zip"
try {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::CreateFromDirectory($proof_phase_dir, $proof_archive)
  Write-ProofLog "[phase103_30] Proof archived: $proof_archive"
} catch {
  Write-ProofLog "[phase103_30] Warning: Could not create archive: $_"
}

Write-ProofLog "[phase103_30]"
Write-ProofLog "[phase103_30] PASS"
Write-ProofLog "[phase103_30] Proof directory: $proof_phase_dir"
Write-ProofLog "[phase103_30] Proof archive: $proof_archive"

exit 0
