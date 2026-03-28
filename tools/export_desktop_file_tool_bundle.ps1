#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
  Write-Host "EXPORT_STATUS=FAIL"
  Write-Host "EXPORT_RESULT_MESSAGE=$($_.Exception.Message)"
  exit 1
}

$expectedWorkspace = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
$workspaceRoot = (Get-Location).Path
if ($workspaceRoot -ne $expectedWorkspace) {
  Write-Host 'hey stupid Fucker, wrong window again'
  exit 1
}

$sourceExe = Join-Path $workspaceRoot 'build/debug/bin/desktop_file_tool.exe'
$exportRoot = Join-Path $workspaceRoot '_artifacts/export/desktop_file_tool_bundle'
$launchScript = Join-Path $exportRoot 'run_desktop_file_tool.cmd'
$manifestPath = Join-Path $exportRoot 'export_manifest.txt'
$copiedExe = Join-Path $exportRoot 'desktop_file_tool.exe'

if (-not (Test-Path -LiteralPath $sourceExe)) {
  Write-Host 'EXPORT_STATUS=FAIL'
  Write-Host 'EXPORT_RESULT_MESSAGE=desktop_file_tool.exe not found; build target before export'
  exit 2
}

if (Test-Path -LiteralPath $exportRoot) {
  Remove-Item -LiteralPath $exportRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $exportRoot -Force | Out-Null

Copy-Item -LiteralPath $sourceExe -Destination $copiedExe -Force

$launchBody = @(
  '@echo off',
  'setlocal',
  'set SCRIPT_DIR=%~dp0',
  '"%SCRIPT_DIR%desktop_file_tool.exe" %*',
  'exit /b %ERRORLEVEL%'
)
$launchBody | Out-File -FilePath $launchScript -Encoding ASCII -Force

$manifestBody = @(
  'bundle_name=desktop_file_tool_bundle',
  'bundle_root=_artifacts/export/desktop_file_tool_bundle',
  'entry_executable=desktop_file_tool.exe',
  'launch_script=run_desktop_file_tool.cmd',
  'profile=debug',
  ('export_utc=' + (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
)
$manifestBody | Out-File -FilePath $manifestPath -Encoding UTF8 -Force

if ((-not (Test-Path -LiteralPath $copiedExe)) -or
    (-not (Test-Path -LiteralPath $launchScript)) -or
    (-not (Test-Path -LiteralPath $manifestPath))) {
  Write-Host 'EXPORT_STATUS=FAIL'
  Write-Host 'EXPORT_RESULT_MESSAGE=export artifacts missing after copy'
  exit 3
}

Write-Host 'EXPORT_STATUS=PASS'
Write-Host 'EXPORT_RESULT_MESSAGE=desktop_file_tool bundle created'
Write-Host ('EXPORT_BUNDLE_PATH=' + $exportRoot)
Write-Host ('EXPORT_ENTRY_EXE=' + $copiedExe)
Write-Host ('EXPORT_LAUNCH_SCRIPT=' + $launchScript)
