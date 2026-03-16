# NGKsUI Runtime Capability Inventory (Code-Read, Current State)

Date: 2026-03-15
Method: This inventory was produced by directly reading source files and scripts in this repository and by extracting inventories from code, not from memory.

## 1) What This Repository Builds and Runs

Entrypoints found in code:
- apps\loop_tests\main.cpp
- apps\sandbox_app\main.cpp
- apps\widget_sandbox\main.cpp
- apps\win32_sandbox\main.cpp

Runtime focus today is apps/widget_sandbox/main.cpp plus apps/win32_sandbox/main.cpp.

## 2) Widget Sandbox Runtime Capabilities

Source basis: apps/widget_sandbox/main.cpp, engine/ui/*, engine/core/src/event_loop.cpp, engine/platform/win32/src/win32_window.cpp, engine/gfx/win32/src/d3d11_renderer.cpp.

### 2.1 UI Controls and Interaction
- Textbox with caret, selection, drag-selection, word select (double click), Home/End, Left/Right, Backspace/Delete.
- Clipboard integration for Copy/Cut/Paste and Ctrl+A/C/X/V through Win32 clipboard hooks.
- Increment button (default action) and Reset button (cancel action) with mouse and keyboard activation.
- Disabled button is explicitly non-interactive for mouse and keyboard.
- Focus navigation with Tab and Shift+Tab across focusable controls.
- Enter activates default action when textbox is focused; Escape activates cancel action.

### 2.2 Runtime State Machine
- Runtime lifecycle states: Idle, Ready, Active, Resetting.
- Explicit legal transitions are enforced; illegal transitions are rejected and logged.
- Last valid state/value snapshots are preserved for rejection handling.
- Input domain for runtime step is integer range 1..9; invalid inputs are rejected deterministically.
- Increment applies pending step only when in legal state; reset returns to canonical baseline value/state.

### 2.3 Modes and Lanes
- Baseline lane (default).
- Extension lane (explicitly selected).
- Demo mode with scripted interaction timeline.
- Visual baseline mode and extension visual baseline mode (deterministic capture behavior).
- Extension stress demo mode for rapid deterministic state transitions.

### 2.4 Extension-Lane Functional Surface
- Extension mode label and extension info card.
- Secondary placeholder toggle active/inactive.
- Status chip, secondary indicator, and tertiary marker subcomponents.
- Parent orchestration, visibility, ordering, and conflict-routing rules.
- Deterministic layout recomputation and child ordering output.
- Mouse-driven interaction handling for placeholder/status/secondary indicator hit regions.

### 2.5 Rendering and Frame Scheduling
- Stable frame path: begin_frame -> clear -> ui_tree.render -> end_frame.
- Event-driven repaint ownership via request_frame/request_repaint/WM_PAINT.
- Dirty-frame model with startup baseline frame request.
- 1-second heartbeat interval emits cadence and idle metrics.

### 2.6 Built-in Validation/Audit Emission
- Code emits a large observability contract surface using widget_* tokens.
- Measured token emission sites in apps/widget_sandbox/main.cpp: 1024 lines.
- Major token namespaces (counted from source lines):
  - extension: 705
  - phase41: 83
  - runtime: 50
  - textbox: 37
  - phase42: 29
  - phase40: 29

## 3) Win32 Sandbox Runtime Capabilities

Source basis: apps/win32_sandbox/main.cpp.

- Win32 window + D3D11 renderer bootstrap and resize handling.
- DPI awareness detection and DPI change callback handling.
- Configurable frame pacing with target FPS controls and policy guardrails.
- Present interval control and anti-double-regulation override logic.
- Resize spam stress mode, CPU-stall injection, and frame stats telemetry.
- Jitter CSV capture to proof paths with configurable warmup/sampling/max frames.
- Crash capture pipeline with VEH + SEH, filtered exception capture, and minidump writing.
- Auto-close and scripted resize timers for deterministic scenario runs.

## 4) Core Engine Capabilities

### 4.1 Event Loop
- Thread-safe post queue.
- set_timeout and set_interval timers with cancellation by id.
- Cross-thread stop and wake signaling.
- Bounded callback budgets per turn (timer/post/global caps).
- Anti-catchup interval scheduling (next_due = now + period).

### 4.2 Windowing
- Win32 message pump.
- Keyboard, char, mouse move/button/wheel callbacks.
- Paint callback routing.
- Close/quit/resize callbacks.
- DPI-awareness setup and WM_DPICHANGED suggested-rect application.

### 4.3 Graphics
- D3D11 swapchain initialization and resize.
- Frame begin/clear/rect/outline/present primitives.
- Device-lost detection and last HRESULT reporting.
- Debug failure injection via NGK_PRESENT_FAIL_EVERY.

### 4.4 UI Primitives
- Panel/Label/Button/InputBox/HorizontalLayout/VerticalLayout/UITree/InputRouter.
- Focusable-element traversal and focused-element key routing.
- Default action and cancel action wiring in UITree.

## 5) Launch and Mode Control Surface

### 5.1 Canonical Launcher Behavior
Source basis: tools/run_widget_sandbox.ps1.
- Enforces repository-root and expected executable safety checks.
- Resolves canonical widget sandbox executable for Debug/Release.
- Stamps launch identity and canonical exe environment markers.
- Controls mode env inheritance policy unless explicit mode args are passed.

### 5.2 Runtime CLI Args Found in Code
- apps/widget_sandbox/main.cpp:--demo
- apps/widget_sandbox/main.cpp:--extension-stress-demo
- apps/widget_sandbox/main.cpp:--extension-visual-baseline
- apps/widget_sandbox/main.cpp:--sandbox-extension
- apps/widget_sandbox/main.cpp:--sandbox-lane=extension
- apps/widget_sandbox/main.cpp:--visual-baseline
- tools/run_widget_sandbox.ps1:--demo
- tools/run_widget_sandbox.ps1:--extension-stress-demo
- tools/run_widget_sandbox.ps1:--extension-visual-baseline
- tools/run_widget_sandbox.ps1:--visual-baseline

### 5.3 Environment Variables Found in Code
- apps/widget_sandbox/main.cpp:NGK_FORENSICS_LOG
- apps/widget_sandbox/main.cpp:NGK_WIDGET_EXTENSION_STRESS_DEMO
- apps/widget_sandbox/main.cpp:NGK_WIDGET_EXTENSION_VISUAL_BASELINE
- apps/widget_sandbox/main.cpp:NGK_WIDGET_LAUNCH_IDENTITY
- apps/widget_sandbox/main.cpp:NGK_WIDGET_SANDBOX_DEMO
- apps/widget_sandbox/main.cpp:NGK_WIDGET_SANDBOX_LANE
- apps/widget_sandbox/main.cpp:NGK_WIDGET_VISUAL_BASELINE
- apps/win32_sandbox/main.cpp:NGK_AUTOCLOSE_MS
- apps/win32_sandbox/main.cpp:NGK_CPU_STALL_EVERY
- apps/win32_sandbox/main.cpp:NGK_CPU_STALL_MS
- apps/win32_sandbox/main.cpp:NGK_FRAME_STATS_EVERY
- apps/win32_sandbox/main.cpp:NGK_FRAME_STATS_WINDOW
- apps/win32_sandbox/main.cpp:NGK_JITTER_CSV
- apps/win32_sandbox/main.cpp:NGK_JITTER_CSV_PATH
- apps/win32_sandbox/main.cpp:NGK_JITTER_MAX_FRAMES
- apps/win32_sandbox/main.cpp:NGK_JITTER_SAMPLE_EVERY
- apps/win32_sandbox/main.cpp:NGK_JITTER_WARMUP_FRAMES
- apps/win32_sandbox/main.cpp:NGK_PACING_BEHIND_RESET_MS
- apps/win32_sandbox/main.cpp:NGK_PACING_FORCE_PRESENT_INTERVAL
- apps/win32_sandbox/main.cpp:NGK_PACING_LOG
- apps/win32_sandbox/main.cpp:NGK_PACING_MIN_SLEEP_US
- apps/win32_sandbox/main.cpp:NGK_PACING_MODE
- apps/win32_sandbox/main.cpp:NGK_PACING_SPIN_US
- apps/win32_sandbox/main.cpp:NGK_PRESENT_INTERVAL
- apps/win32_sandbox/main.cpp:NGK_RESIZE_SPAM
- apps/win32_sandbox/main.cpp:NGK_SCRIPTED_RESIZE_MS
- apps/win32_sandbox/main.cpp:NGK_TARGET_FPS
- apps/win32_sandbox/main.cpp:NGK_TIMER_RES_MS
- engine/gfx/win32/src/d3d11_renderer.cpp:NGK_PRESENT_FAIL_EVERY
- engine/gfx/win32/src/d3d11_renderer.cpp:NGK_PRESENT_INTERVAL
- tools/run_widget_sandbox.ps1:NGK_WIDGET_CANONICAL_EXE
- tools/run_widget_sandbox.ps1:NGK_WIDGET_EXTENSION_STRESS_DEMO
- tools/run_widget_sandbox.ps1:NGK_WIDGET_EXTENSION_VISUAL_BASELINE
- tools/run_widget_sandbox.ps1:NGK_WIDGET_LAUNCH_IDENTITY
- tools/run_widget_sandbox.ps1:NGK_WIDGET_SANDBOX_DEMO
- tools/run_widget_sandbox.ps1:NGK_WIDGET_VISUAL_BASELINE

## 6) Validation and Certification Tooling Capabilities

### 6.1 Permanent Validation Scripts
- tools/validation\build_graph_integrity.txt
- tools/validation\extension_visual_contract_check.ps1
- tools/validation\extension_visual_contract.txt
- tools/validation\launch_contract.txt
- tools/validation\renderer_api_contract.txt
- tools/validation\run_permanent_validation_suite.ps1
- tools/validation\source_tree_contract_report.txt
- tools/validation\visual_baseline_contract_check.ps1
- tools/validation\visual_baseline_contract.txt

### 6.2 Phase Runner Surface
Total phase runner scripts discovered: 72
- tools\phase40_28\phase40_28_baseline_lock_runner.ps1
- tools\phase40_28r\phase40_28r_ui_header_restoration_runner.ps1
- tools\phase40_47\phase40_47_extension_presentation_variant_runner.ps1
- tools\phase40_48\phase40_48_extension_data_shape_expansion_runner.ps1
- tools\phase40_49\phase40_49_extension_layout_variation_runner.ps1
- tools\phase40_50\phase40_50_extension_content_density_runner.ps1
- tools\phase40_51\phase40_51_extension_interaction_driven_content_update_runner.ps1
- tools\phase40_52\phase40_52_extension_subcomponent_boundary_runner.ps1
- tools\phase40_53\phase40_53_extension_subcomponent_state_ownership_runner.ps1
- tools\phase40_54\phase40_54_extension_subcomponent_presentation_variant_runner.ps1
- tools\phase40_55\phase40_55_extension_subcomponent_layout_variation_runner.ps1
- tools\phase40_56\phase40_56_extension_subcomponent_content_density_runner.ps1
- tools\phase40_57\phase40_57_extension_subcomponent_interaction_boundary_runner.ps1
- tools\phase40_58\phase40_58_extension_multi_subcomponent_coexistence_runner.ps1
- tools\phase40_59\phase40_59_extension_parent_orchestration_rule_runner.ps1
- tools\phase40_60\phase40_60_extension_parent_visibility_rule_runner.ps1
- tools\phase40_61\phase40_61_extension_parent_ordering_rule_runner.ps1
- tools\phase40_62\phase40_62_extension_multi_child_interaction_routing_runner.ps1
- tools\phase40_63\phase40_63_extension_parent_intent_conflict_rule_runner.ps1
- tools\phase40_64\phase40_64_extension_third_subcomponent_isolation_runner.ps1
- tools\phase40_65\phase40_65_render_stability_under_state_change_runner.ps1
- tools\phase40_66\phase40_66_extension_layout_container_runner.ps1
- tools\phase40_67\phase40_67_extension_header_band_proof_runner.ps1
- tools\phase40_68\phase40_68_extension_body_region_proof_runner.ps1
- tools\phase40_70\phase40_70_human_visible_extension_structure_runner.ps1
- tools\phase40_71\phase40_71_sandbox_render_primitives_runner.ps1
- tools\phase40_72\phase40_72_visible_extension_panel_reconstruction_runner.ps1
- tools\phase40_73\phase40_73_extension_panel_readability_polish_runner.ps1
- tools\phase40_74\phase40_74_extension_body_composition_rule_runner.ps1
- tools\phase40_75\phase40_75_extension_body_hierarchy_proof_runner.ps1
- tools\phase40_76\phase40_76_wrong_exe_prevention_runner.ps1
- tools\phase40_77\phase40_77_extension_panel_visual_consolidation_runner.ps1
- tools\phase40_78\phase40_78_extension_text_hierarchy_cleanup_runner.ps1
- tools\phase40_79\phase40_79_extension_surface_grouping_refinement_runner.ps1
- tools\phase40_80\phase40_80_extension_primary_card_emphasis_refinement_runner.ps1
- tools\phase40_81\phase40_81_extension_footer_integration_refinement_runner.ps1
- tools\phase40_82\phase40_82_extension_header_integration_refinement_runner.ps1
- tools\phase40_83\phase40_83_extension_full_panel_cohesion_refinement_runner.ps1
- tools\phase40_84\phase40_84_control_area_integration_refinement_runner.ps1
- tools\phase40_85\phase40_85_visual_readability_refinement_runner.ps1
- tools\phase40_86\phase40_86_interaction_clarity_refinement_runner.ps1
- tools\phase40_87\phase40_87_status_feedback_clarity_refinement_runner.ps1
- tools\phase40_88\phase40_88_minimal_ui_calmness_refinement_runner.ps1
- tools\phase40_89\phase40_89_panel_spacing_surface_standardization_runner.ps1
- tools\phase40_90\phase40_90_calm_control_card_reconstruction_runner.ps1
- tools\phase40_91\phase40_91_primary_control_card_architecture_runner.ps1
- tools\phase40_92\phase40_92_panel_meaning_clarity_refinement_runner.ps1
- tools\phase40_93\phase40_93_panel_layout_stabilization_runner.ps1
- tools\phase40_94\phase40_94_label_normalization_runner.ps1
- tools\phase41_0\phase41_0_real_control_path_activation_runner.ps1
- tools\phase41_1\phase41_1_runtime_state_transition_proof_runner.ps1
- tools\phase41_2\phase41_2_invalid_transition_handling_proof_runner.ps1
- tools\phase41_3\phase41_3_recovery_after_rejection_proof_runner.ps1
- tools\phase41_4\phase41_4_repeated_rejection_recovery_stability_runner.ps1
- tools\phase41_5\phase41_5_input_validation_value_domain_proof_runner.ps1
- tools\phase41_6\phase41_6_post_validation_action_continuity_runner.ps1
- tools\phase41_7\phase41_7_state_value_persistence_boundary_runner.ps1
- tools\phase41_8\phase41_8_runtime_action_trace_audit_runner.ps1
- tools\phase41_9\phase41_9_runtime_trace_completeness_no_gap_runner.ps1
- tools\phase42_0\phase42_0_runtime_trace_replay_reconstruction_runner.ps1
- tools\phase42_1\phase42_1_trace_divergence_detection_runner.ps1
- tools\phase42_2\phase42_2_replay_invariance_identical_trace_runner.ps1
- tools\phase42_3\phase42_3_trace_certification_fingerprint_runner.ps1
- tools\phase42_4\phase42_4_fingerprint_enforcement_baseline_compare_runner.ps1
- tools\phase42_5\phase42_5_baseline_integrity_tamper_detection_runner.ps1
- tools\phase42_6\phase42_6_baseline_rotation_trust_chain_runner.ps1
- tools\phase42_7\phase42_7_baseline_version_selection_historical_validation_runner.ps1
- tools\phase42_8\phase42_8_active_version_policy_deprecation_runner.ps1
- tools\phase42_9\phase42_9_policy_integrity_tamper_detection_runner.ps1
- tools\phase43_0\phase43_0_policy_rotation_trust_chain_runner.ps1
- tools\phase43_1\phase43_1_policy_version_selection_historical_validation_runner.ps1
- tools\phase43_2\phase43_2_active_policy_default_resolution_enforcement_runner.ps1

## 7) Policy/Baseline Enforcement Surface (Current)

Source basis: tools/phase42_5 through tools/phase43_2 plus generated policy/baseline references.
- Baseline integrity references and tamper checks.
- Baseline history chain and controlled baseline rotation path.
- Policy integrity references and tamper checks.
- Policy history chain and controlled policy rotation path.
- Explicit policy-version selection for historical validation.
- Default active-policy resolution enforcement with integrity-first gating.

## 8) Explicit Non-Capabilities Seen in Current Code
- No network stack or HTTP client/server behavior discovered in runtime app code scanned.
- No audio/media playback pipeline discovered in scanned runtime code.
- No plugin loading or dynamic scripting engine discovered in scanned runtime code.

## 9) Evidence Artifacts Generated for This Inventory
- _artifacts/runtime/phase_runner_inventory.txt
- _artifacts/runtime/validation_script_inventory.txt
- _artifacts/runtime/widget_token_lines.txt

This inventory is intentionally code-derived and limited to capabilities present in current repository source and scripts at scan time.
