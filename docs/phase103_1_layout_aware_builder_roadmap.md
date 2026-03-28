# PHASE103_1 - Layout-Aware Builder Roadmap and First Slice

## Goal
Start the CAD-like layout-aware builder track with a minimal, product-facing foundation slice that prevents overlap/missizing regressions while preserving existing runtime behavior.

## Ordered Roadmap
1. Builder Layout Audit Pass (first slice)
- Dependency: layout foundation (`VerticalLayout`, `HorizontalLayout`, min-size, weighted fill)
- Output: structural overlap/min-size audit of composed UI tree
- Why first: catches overlap/misalignment/missizing immediately and creates measurable quality gates for later builder operations.

2. Builder Node Model and Container Semantics
- Dependency: declarative composition layer
- Output: explicit builder node metadata (container, section, widget identity, capability flags)
- Why second: visual tooling must manipulate semantic nodes, not raw pointers.

3. Guided Placement Rules
- Dependency: shell widgets + scroll container
- Output: guided insertion points, sibling ordering, spacing rules
- Why third: enables predictable placement in nested, scrollable shells.

4. Constraint Editing Surface (non-visual minimal)
- Dependency: list/table foundations
- Output: list/table-backed inspector for min size, fill policy, weight, padding, spacing
- Why fourth: integrates with existing runtime controls before full canvas editing.

5. Alignment/Snap and Anti-overlap Enforcement
- Dependency: node model + placement rules + audit pass
- Output: deterministic placement constraints and hard overlap prevention
- Why fifth: core CAD-like behavior built on proven structure checks.

6. Builder Project Save/Load and Composition Round-Trip
- Dependency: native dialogs + declarative composition + packaging/export
- Output: save/load builder composition and regenerate runtime shell graph
- Why sixth: persists builder intent and validates runtime parity.

7. Builder-to-Package Flow
- Dependency: packaging/export command
- Output: one-command export of builder-authored app shells
- Why seventh: closes the loop from composition to runnable artifact.

## Dependency Notes
- layout foundation: required for measurable no-overlap/min-size validation.
- scroll container: required to validate nested content sizing in clipped regions.
- list/table: required for future inspector/editor surfaces.
- shell widgets: required as builder composition primitives.
- native dialogs: required for save/load later phases.
- declarative composition: required as composition target/runtime mapping layer.
- packaging/export: required to ship builder-authored outputs.

## First Builder-Facing Target (Selected)
Builder Layout Audit Pass.

### Implemented in PHASE103_1
- Added `engine/ui/layout_audit.hpp`.
- Added tree audit for:
  - sibling overlap detection
  - min-size violation detection
  - checked-node counts
- Integrated audit into `desktop_file_tool` validation output with PHASE103_1 markers.

## Runtime Behavior Changes
- No visual/interaction redesign.
- Added audit signals and validation gating only.
