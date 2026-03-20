# NGKsUI Runtime

> **C++/Qt projects now run directly (no env var needed). Node.js/web projects still use the orchestrator.**

## Build

Activate MSVC (x64 Native Tools Command Prompt or run VsDevCmd.bat), then:

```powershell
.venv\Scripts\python.exe -m ngksbuildcore run --plan build_graph/debug/ngksbuildcore_plan.json
```

Or using ngksgraph end-to-end:

```powershell
.venv\Scripts\python.exe -m ngksgraph configure --profile debug --msvc-auto
.venv\Scripts\python.exe -m ngksgraph build --profile debug --msvc-auto
```
