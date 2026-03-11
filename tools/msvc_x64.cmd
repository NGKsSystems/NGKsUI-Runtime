@echo off
setlocal

set "VSW=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSW%" (
  echo vswhere not found: "%VSW%"
  exit /b 1
)

for /f "usebackq delims=" %%I in (`"%VSW%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSINST=%%I"

if not defined VSINST (
  echo No VS install with VC Tools found.
  exit /b 1
)

call "%VSINST%\Common7\Tools\VsDevCmd.bat" -arch=x64
echo [MSVC ENV] OK: %VSCMD_ARG_TGT_ARCH%
where cl