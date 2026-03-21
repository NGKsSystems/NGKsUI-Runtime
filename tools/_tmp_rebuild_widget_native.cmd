@echo off
call "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\Tools\VsDevCmd.bat"
if not exist build\debug\obj\widget_sandbox\apps\widget_sandbox mkdir build\debug\obj\widget_sandbox\apps\widget_sandbox
if not exist build\debug\bin mkdir build\debug\bin
cl /nologo /EHsc /std:c++20 /MD /showIncludes /FS /c apps/widget_sandbox/main.cpp /Fobuild/debug/obj/widget_sandbox/apps/widget_sandbox/main.obj /Iengine/core/include /Iengine/gfx/include /Iengine/gfx/win32/include /Iengine/platform/win32/include /Iengine/ui /Iengine/ui/include /DDEBUG /DUNICODE /D_UNICODE /Od /Zi
if errorlevel 1 exit /b 1
link /nologo build/debug/obj/widget_sandbox/apps/widget_sandbox/main.obj build/debug/lib/engine.lib /OUT:build/debug/bin/widget_sandbox.exe d3d11.lib dxgi.lib gdi32.lib user32.lib
