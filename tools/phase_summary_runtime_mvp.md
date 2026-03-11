# NGKsUI Runtime — Internal MVP Summary

## Current Scope

NGKsUI Runtime currently provides a Win32 + D3D11 runtime loop with a lightweight UI layer and auditable phase runners under `tools/phase*`.

## Implemented Widgets

- `Panel`
- `VerticalLayout`
- `Label`
- `Button`
- `InputBox`
- `ListPanel`
- `ScrollContainer`
- `FocusManager`
- `Checkbox`
- `Toolbar`
- `StatusBar`

## App Slices

- `apps/widget_sandbox/main.cpp`: interaction-focused widget validation surface.
- `apps/port_probe/main.cpp`: app-like slice with input/add/select/remove/scroll/status/filter flow.

## Build + Run

Primary integrated runner:

- `pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\phase22\phase22_internal_mvp_runner.ps1`

Runner outputs PF/ZIP/GATE under real `_proof` root and writes `98_gate_22.txt`.

## What Is Still Missing for Full Qt Replacement

- Full text rendering stack (shaping, fonts, complex scripts)
- Rich widget ecosystem (menus, trees, tables, dialogs)
- Advanced layout systems and docking persistence
- Accessibility, IME, i18n maturity
- Broader platform backend parity beyond current Win32-first implementation

## Known Limitations

- Rendering remains intentionally minimal for deterministic interaction verification.
- Widget visuals are state-color based; no comprehensive style/theme engine yet.
- App slices are MVP-focused and do not yet represent full production UX parity.

## Next Milestones

1. Harden text rendering and input method behavior.
2. Add richer controls (table/tree/dialog/menu) with deterministic tests.
3. Extend layout/docking capabilities.
4. Increase app-port surface area beyond `port_probe`.
5. Keep runners as single-source-of-truth for proof-path discipline.
