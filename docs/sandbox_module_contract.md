# Sandbox Module Contract

This document captures permanent internal boundaries for the stable simple sandbox path.

## Stable Modules

1. App shell and startup:
- `run_app` sets mode flags, initializes window/renderer, and wires loop callbacks.

2. Frame scheduling and redraw requests:
- `request_frame` queues repaint state.
- `window.set_paint_callback` is the only repaint consumption path.
- Startup issues one baseline request (`BASELINE/startup`) to establish initial frame.

3. UI state model and interaction handling:
- Button/textbox/status state lives in local UI state variables and callback lambdas.
- Input routes through `InputRouter` and `UITree` only.

4. Layout and content description:
- Vertical root + horizontal controls row define stable simple layout.
- Fixed labels/buttons/textbox are baseline content.

5. Rendering submission path:
- Stable frame pipeline is `begin_frame -> clear -> ui_tree.render -> end_frame`.
- No alternate frame producer or parallel rendering path is allowed.

6. Permanent validation hooks:
- Visual baseline mode (`--visual-baseline` / `NGK_WIDGET_VISUAL_BASELINE`) is permanent.
- Build and visual validation remain tooling responsibilities in `tools/validation` and `tools/runtime_contract_guard.ps1`.

## Extension Rules

1. New visuals must use existing redraw path (`request_frame` + `WM_PAINT`) only.
2. No feature may introduce a new timer-driven frame producer.
3. Validation hooks may emit deterministic evidence, but must not alter runtime behavior.
4. Build contract guard and visual baseline checks must pass before visual/runtime changes are accepted.
5. Phase-specific proof logic belongs in tools and proof scripts, not in normal runtime control flow.
