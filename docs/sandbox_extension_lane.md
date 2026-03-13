# Sandbox Extension Lane

This file defines the permanent safe extension boundary for the stable widget sandbox.

## Activation Contract

Extension mode is opt-in only through one of:
- `--sandbox-extension`
- `--sandbox-lane=extension`
- `NGK_WIDGET_SANDBOX_LANE=extension`

Without those inputs, the sandbox runs baseline lane by default.

## Phase 40.36 First Safe Slot

The first active extension target is intentionally tiny:
- same black background and stable redraw model as baseline,
- one static label: `extension mode: minimal slot active`,
- no dashboard, no gauges, no live telemetry paths, no timer-driven frame producers.

## Phase 40.37 State/Layout Contract

Extension lane now has explicit tiny internal contracts:
- state contract: extension-only mode identity, extension label text, inert placeholder visibility flag,
- layout contract: deterministic background region, extension label bounds, inert placeholder bounds.

These contracts are extension-lane only and must not be consumed by baseline logic.

## Baseline Protection Rules

1. Visual baseline mode always forces baseline lane.
2. Baseline lane remains the default validation target.
3. Extension lane must not alter baseline visual contract tokens.
4. Extension lane must reuse request_frame -> request_repaint -> WM_PAINT ownership.
5. Any future extension growth must pass runtime contract guard, visual baseline contract, and baseline lock runner before promotion.

## Future Extension Rules

1. Extension state must remain separate from baseline state.
2. Extension layout must remain deterministic until explicitly expanded by a dedicated phase.
3. No extension may introduce a new frame producer.
4. Extension visuals must stay on the stable render path (`begin_frame -> clear -> ui_tree.render -> end_frame`).
5. Baseline validation gates must remain green after any extension-lane change.

## Phase 40.38 Extension Visual Contract

The extension lane has its own tiny visual baseline and validation path:
- black background,
- extension label (`extension mode: minimal slot active`),
- inert placeholder contract marker (currently visibility `0`, with deterministic bounds).

Validation separation:
- baseline visual contract remains in `tools/validation/visual_baseline_contract_check.ps1`,
- extension visual contract is independent in `tools/validation/extension_visual_contract_check.ps1`.

Future extension changes must update extension visual validation only, unless baseline visuals are intentionally changed by a dedicated baseline phase.

## Phase 40.39 Code-Health Boundary Hardening

Extension lane runtime boundaries are kept explicit:
- run-mode normalization is centralized before runtime wiring,
- extension startup contract tokens are emitted from extension-only helpers,
- extension visual contract frame tokens are emitted from extension-only helpers.

This keeps baseline runtime flow uncluttered while preserving stable contract signals used by validation tooling.

## Phase 40.40 Render Contract

Extension lane now has a tiny permanent render contract:
- entrypoint: `render_extension_lane_frame(...)`,
- inputs: renderer, UI tree, extension state, extension visual-baseline mode, extension visual-contract frame marker latch,
- output expectation: returns `true` when extension frame submission is completed through the stable UI tree path.

Allowed permanent extension render markers:
- `widget_extension_render_contract_entry=1`
- `widget_extension_render_contract_mode=...`
- existing extension visual contract markers emitted only in extension visual-baseline mode.

Baseline render isolation remains strict: baseline lane continues direct baseline rendering path and remains the default validation target.

## Render Rules

1. Extension visuals must enter through `render_extension_lane_frame(...)` only.
2. No extension render path may introduce a new frame producer or timer.
3. Extension render logic must not bypass `request_frame -> request_repaint -> WM_PAINT` ownership.
4. Baseline render path must stay unchanged unless a dedicated baseline phase explicitly updates it.
5. Any extension render evolution must keep baseline and extension validation contracts passing.

## Phase 40.41 Interaction Contract

Extension lane now has a tiny permanent interaction contract:
- entrypoint: `observe_extension_interaction_input(...)`,
- inputs: `mouse_move`, `mouse_button`, `key`, `char`,
- extension-local state: input counters and one-time input-seen markers,
- startup contract markers: interaction contract entry, mode identity, allowed input list.

Baseline interaction isolation remains strict: baseline input routing path remains unchanged and is still the default validation target.

## Interaction Rules

1. Extension interaction intake must route through `observe_extension_interaction_input(...)`.
2. No extension interaction change may introduce timers or new frame producers.
3. Extension interaction logic must not bypass stable redraw ownership (`request_frame -> request_repaint -> WM_PAINT`).
4. No ad-hoc extension event handling should be added inline in main flow; use extension contract helpers.
5. Baseline and extension validation contracts must remain green after interaction changes.

## Phase 40.42 First Controlled Extension UI Element

Exactly one small extension-only real UI element is active:
- a static info card titled `Extension Info Card` with one static text line.

Contract usage:
- state contract: card visibility/title/text are extension-only state,
- layout contract: deterministic info-card bounds,
- render contract: info-card visibility marker emitted from extension render entrypoint,
- interaction contract: extension input intake remains routed through extension interaction entrypoint.

Baseline lane remains visually unchanged and default.

## Phase 40.43 Composition Slot Expansion

Extension lane now supports a tiny deterministic two-slot composition model:
- Primary slot: existing static info card.
- Secondary slot: one inert placeholder region (`secondary slot: inert placeholder`).

This remains intentionally small:
- no timers,
- no telemetry,
- no dashboard logic,
- no baseline lane visual changes.

Validation now asserts composition model and both slot markers in extension mode only.

## Phase 40.44 First Controlled Extension Interaction

Extension lane now includes exactly one tiny real interaction:
- click target: secondary placeholder slot,
- state change: `inactive` <-> `active`,
- visible update: secondary placeholder label text switches between `secondary slot: inactive` and `secondary slot: active`.

Interaction remains extension-only and deterministic:
- no timers,
- no new frame producers,
- no baseline interaction changes.

## Phase 40.45 Extension Slot State Coordination

Extension lane now has one tiny coordinated state relationship:
- owner interaction: secondary slot click toggle,
- shared state: secondary active/inactive boolean,
- reflected state: primary card summary line (`secondary state: inactive|active`).

This is still deterministic and extension-only:
- no new interaction types,
- no layout expansion,
- no baseline behavior changes.

## Phase 40.47 Extension Presentation Variant

Extension lane now supports one tiny presentation-style variant without structural changes:
- variant target: primary summary badge treatment,
- selector source: existing secondary placeholder active/inactive state,
- variants: `neutral` (inactive) and `emphasis` (active).

Scope is intentionally narrow:
- no new interactions,
- no slot/layout expansion,
- no timers or telemetry,
- baseline visuals and behavior unchanged.

## Phase 40.48 Extension Data Shape Expansion

Extension lane now includes one tiny structured data shape for card display state:
- data shape: `card_display_v1`,
- grouped fields: secondary active/inactive flag, derived summary text, summary badge variant,
- consumption: existing primary summary label render path and extension contract markers.

This remains intentionally constrained:
- no new interaction types,
- no additional layout regions,
- no baseline mode behavior changes.

## Phase 40.49 Extension Layout Variation

Extension lane now supports one tiny deterministic layout variation:
- layout mode: `compact` vs `expanded`,
- selector source: existing secondary active/inactive extension state,
- applied region: existing secondary placeholder slot height only.

This remains intentionally bounded:
- no new widgets,
- no new interaction types,
- no baseline layout or behavior changes.

## Phase 40.50 Extension Content Density

Extension lane now includes one tiny content-density expansion:
- added one extra read-only detail row inside the existing primary info card,
- detail text is derived from existing extension state (`layout mode: compact|expanded`),
- rendered only in extension mode with deterministic contract markers.

This remains intentionally bounded:
- one extra row only,
- no new interaction types,
- no baseline visual or behavior changes.

## Phase 40.51 Extension Interaction-Driven Content Update

Extension lane now proves one tiny interaction-driven content update:
- updated field: existing primary card detail row,
- driver: existing secondary toggle interaction,
- behavior: detail row starts as `interaction note: waiting for toggle`, then updates to `interaction note: toggled active|inactive` after interaction.

This remains intentionally bounded:
- one content field update only,
- no new interaction types,
- no baseline visual or behavior changes.

## Phase 40.52 Extension Subcomponent Boundary

Extension lane now proves one tiny isolated extension-only subcomponent boundary:
- subcomponent: `status_chip_v1` rendered inside the existing primary info card,
- explicit input shape: visible flag, read-only text, presentation variant, and input source marker,
- update driver: existing secondary-placeholder toggle interaction only.

Boundary guarantees:
- state contract: status-chip input shape lives in extension-only state,
- layout contract: deterministic status-chip bounds are emitted with extension layout markers,
- render contract: subcomponent markers are emitted from extension render contract entrypoint,
- interaction contract: existing extension toggle updates the status-chip input values,
- visual contract: extension visual checker validates default status-chip markers in extension visual baseline mode.

This remains intentionally bounded:
- exactly one tiny subcomponent,
- no new interaction types,
- no baseline visual or behavior changes.

## Phase 40.53 Extension Subcomponent State Ownership

Extension lane now proves parent-owned state handoff for the existing tiny subcomponent:
- parent-owned source: extension lane state,
- child input shape: `status_chip_input_v1` record,
- child consumption: status chip render/style path reads only the explicit input record.

Ownership guarantees:
- state contract: parent extension state builds `status_chip_input_v1` (visible, text, variant, source, owner),
- layout contract: status-chip bounds remain deterministic and unchanged,
- render contract: status-chip render markers declare input record usage and input-only consumption,
- interaction contract: existing secondary toggle updates parent state first, then rebuilds the child input record,
- visual contract: extension visual checker validates input-record ownership markers and default values.

This remains intentionally bounded:
- one ownership refinement only,
- no new interaction types,
- no baseline visual or behavior changes.

## Phase 40.54 Extension Subcomponent Presentation Variant

Extension lane now proves one tiny subcomponent-level presentation variant:
- target subcomponent: existing `status_chip_v1`,
- selector field: parent-built `status_chip_input_v1.presentation_variant`,
- variants: `base` (default) and `emphasis` (after existing secondary-toggle active state).

Variant guarantees:
- state contract: parent extension state still owns status data and builds `status_chip_input_v1`,
- layout contract: status-chip bounds remain deterministic and unchanged,
- render contract: status-chip style/render markers include presentation variant from input record,
- interaction contract: existing secondary toggle updates parent state and therefore input-record variant,
- visual contract: extension visual checker validates default presentation variant markers.

This remains intentionally bounded:
- one tiny presentation variant only,
- no new interaction types,
- no baseline visual or behavior changes.

## Phase 40.55 Extension Subcomponent Layout Variation

Extension lane now proves one tiny subcomponent-level layout variation:
- target subcomponent: existing `status_chip_v1`,
- selector field: parent-built `status_chip_input_v1.layout_variant`,
- variants: `compact` (default) and `offset` (after existing secondary-toggle active state).

Layout guarantees:
- state contract: parent extension state remains the owner and builds `status_chip_input_v1`,
- layout contract: subcomponent row height is selected deterministically from input record (`20` for compact, `24` for offset),
- render contract: render markers emit subcomponent layout variant and applied height from input record,
- interaction contract: existing secondary toggle updates parent state and therefore input-record layout variant,
- visual contract: extension visual checker validates default layout-variant markers.

This remains intentionally bounded:
- one tiny layout variant only,
- no new interaction types,
- no baseline visual or behavior changes.

## Phase 40.56 Extension Subcomponent Content Density

Extension lane now proves one tiny subcomponent-level content-density increase:
- target subcomponent: existing `status_chip_v1`,
- selector/feeding field: parent-built `status_chip_input_v1.content_extra_line`,
- behavior: one extra deterministic metadata line rendered from the input record.

Content guarantees:
- state contract: parent extension state builds `status_chip_input_v1` including `content_extra_line`,
- layout contract: existing deterministic bounds and layout-variant behavior remain intact,
- render contract: render markers emit extra-line content from input record only,
- interaction contract: existing secondary toggle updates parent state and recomputes `content_extra_line`,
- visual contract: extension visual checker validates default extra-line content markers.

This remains intentionally bounded:
- one tiny extra content line only,
- no new interaction types,
- no baseline visual or behavior changes.

## Phase 40.57 Extension Subcomponent Interaction Boundary

Extension lane now proves one tiny subcomponent-level interaction boundary:
- target subcomponent: existing `status_chip_v1`,
- interaction: one click on chip bounds,
- mutation owner: parent extension state toggles `status_chip_interaction_active`.

Boundary guarantees:
- child boundary: chip click emits one tiny intent signal (`status_chip_toggle_intent`) through extension interaction path,
- state contract: parent state remains source of truth and rebuilds `status_chip_input_v1`,
- render contract: interaction boundary state is emitted from input-record-driven render markers,
- visual contract: extension checker validates default interaction boundary state in extension visual baseline mode,
- baseline isolation: baseline lane paths remain untouched and default.

This remains intentionally bounded:
- one click behavior only,
- no new interaction types,
- no baseline visual or behavior changes.

## Phase 40.58 Extension Multi-Subcomponent Coexistence

Extension lane now proves two isolated subcomponents can coexist safely:
- primary subcomponent: `status_chip_v1`,
- secondary subcomponent: `secondary_indicator_v1`,
- both render simultaneously inside the existing extension info card.

Coexistence guarantees:
- parent ownership: each subcomponent consumes its own parent-built input record,
- input separation: `status_chip_input_v1` and `secondary_indicator_input_v1` are independent records,
- render discipline: both render through extension render contract without shared child mutable state,
- interaction boundary: existing interaction path mutates parent state only, then parent rebuilds both inputs,
- baseline isolation: baseline lane remains default, unchanged, and separately validated.

This remains intentionally bounded:
- one additional tiny subcomponent only,
- no dashboard-style expansion,
- no baseline visual or behavior changes.

## Phase 40.59 Extension Parent Orchestration Rule

Extension lane now proves one tiny parent-owned orchestration rule can coordinate both isolated subcomponents:
- orchestration rule: `parent_emphasis_bridge_v1`,
- child inputs: `status_chip_input_v1` and `secondary_indicator_input_v1`, each derived independently by parent,
- child outputs: status chip uses coordinated emphasis while secondary indicator mirrors orchestration state as read-only text/variant.

Orchestration guarantees:
- strict parent ownership: the orchestration flag is computed in extension parent state only,
- independent child inputs: each child receives its own input record with explicit parent orchestration state markers,
- no child coupling: children do not read each other and dependency marker remains `none`,
- deterministic render: both children render from parent-built inputs only,
- baseline isolation: baseline lane remains untouched, default, and validation-backed.

This remains intentionally bounded:
- one parent-level orchestration rule only,
- no new interaction types, widgets, timers, or telemetry,
- no baseline visual or behavior changes.

## Phase 40.60 Extension Parent Visibility Rule

Extension lane now proves one tiny parent-owned visibility rule can control one child subcomponent presence:
- visibility rule: `parent_secondary_indicator_visibility_v1`,
- controlled child: `secondary_indicator_v1`,
- parent still derives separate child input records for both children.

Visibility guarantees:
- strict parent ownership: parent decides child visibility state in extension lane state,
- deterministic render presence: secondary indicator render markers emit visible/hidden states from parent input,
- child isolation: visibility ownership remains parent-only, with no child-owned visibility mutation,
- baseline isolation: baseline lane remains default, unchanged, and separately validated.

This remains intentionally bounded:
- one parent visibility rule only,
- no new interaction types, widgets, timers, or telemetry,
- no baseline visual or behavior changes.

## Phase 40.61 Extension Parent Ordering Rule

Extension lane now proves one tiny parent-owned ordering rule can control child order/priority:
- ordering rule: `parent_subcomponent_ordering_v1`,
- affected children: `status_chip_v1` and `secondary_indicator_v1`,
- parent still builds separate child input records and derives deterministic order markers.

Ordering guarantees:
- strict parent ownership: ordering mode is computed in extension parent state only,
- deterministic ordering: parent emits stable child-order tokens for both startup and render paths,
- child isolation: ordering dependency marker remains `none`, with no child-owned order logic,
- baseline isolation: baseline lane remains default, unchanged, and separately validated.

This remains intentionally bounded:
- one parent ordering rule only,
- no new interaction types, widgets, timers, or telemetry,
- no baseline visual or behavior changes.

## Phase 40.62 Extension Multi-Child Interaction Routing

Extension lane now proves two child intents can be routed through parent-only interaction ownership:
- child A intent: `status_chip_toggle_intent` from `status_chip_v1`,
- child B intent: `secondary_indicator_ping_intent` from `secondary_indicator_v1`,
- parent routing owner: `extension_parent_state`.

Routing guarantees:
- strict parent ownership: parent receives both intent sources and applies all resulting state updates,
- intent isolation: children emit explicit tiny intents only and do not read or mutate each other,
- deterministic render confirmation: parent emits routed-intent markers and updates read-only detail text deterministically,
- baseline isolation: baseline lane remains unchanged, default, and independently validated.

This remains intentionally bounded:
- one new child-B intent only,
- no new widgets, timers, animation, or telemetry,
- no baseline visual or behavior changes.

## Phase 40.63 Extension Parent Intent Conflict Rule

Extension lane now proves one deterministic parent-owned conflict rule across two child intents:
- conflict rule: `parent_intent_priority_secondary_over_status_v1`,
- child A intent: `status_chip_toggle_intent`,
- child B intent: `secondary_indicator_ping_intent`.

Conflict-resolution guarantees:
- parent-only resolution: parent receives both intents and selects one winner deterministically,
- single-intent behavior: status alone routes to status winner; secondary alone routes to secondary winner,
- simultaneous behavior: both intents resolve to secondary winner by one parent rule,
- child isolation: children emit intents only and do not negotiate or resolve conflicts,
- baseline isolation: baseline lane remains default, unchanged, and independently validated.

This remains intentionally bounded:
- one conflict rule only,
- no new widgets, timers, animation, or telemetry,
- no baseline visual or behavior changes.
