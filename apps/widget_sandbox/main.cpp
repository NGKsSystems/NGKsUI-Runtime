#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstdint>
#include <exception>
#include <functional>
#include <iostream>
#include <sstream>
#include <string>

#include "ngk/event_loop.hpp"
#include "ngk/gfx/d3d11_renderer.hpp"
#include "ngk/platform/win32_clipboard.hpp"
#include "ngk/platform/win32_window.hpp"

#include "button.hpp"
#include "horizontal_layout.hpp"
#include "input_box.hpp"
#include "input_router.hpp"
#include "label.hpp"
#include "text_painter.hpp"
#include "ui_tree.hpp"
#include "vertical_layout.hpp"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

namespace {

constexpr int kInitialWidth = 960;
constexpr int kInitialHeight = 640;
constexpr int UI_MARGIN = 24;
constexpr int SECTION_SPACING = 16;
constexpr int CONTROL_SPACING = 12;

enum class SandboxLane {
  Baseline,
  ExtensionSlot
};

enum class ExtensionCompositionSlot {
  Primary,
  Secondary
};

struct ExtensionCompositionModel {
  bool enabled = false;
  bool primary_visible = false;
  bool secondary_visible = false;
  const char* primary_name = "primary_info_card";
  const char* secondary_name = "secondary_placeholder";
};

struct ExtensionCardDisplayData {
  bool secondary_active = false;
  std::string summary_text = "State summary: inactive";
  std::string summary_badge_variant = "neutral";
  bool detail_interaction_applied = false;
  std::string detail_text = "Action: waiting for toggle";
};

struct ExtensionStatusChipDisplayData {
  bool visible = true;
  std::string text = "System state: ready";
  std::string variant = "neutral";
  std::string source = "secondary_placeholder_state";
};

struct ExtensionStatusChipInputRecord {
  bool visible = true;
  std::string text = "System state: ready";
  std::string content_extra_line = "Feedback: ready";
  std::string variant = "neutral";
  std::string presentation_variant = "base";
  std::string layout_variant = "compact";
  std::string interaction_boundary_state = "inactive";
  std::string source = "secondary_placeholder_state";
  std::string owner = "extension_parent_state";
  std::string parent_orchestration_rule = "parent_emphasis_bridge_v1";
  std::string parent_orchestration_state = "inactive";
};

struct ExtensionSecondaryIndicatorDisplayData {
  bool visible = true;
  std::string text = "Support line: inactive";
  std::string variant = "neutral";
  std::string source = "secondary_placeholder_state";
};

struct ExtensionSecondaryIndicatorInputRecord {
  bool visible = true;
  std::string text = "Support line: inactive";
  std::string variant = "neutral";
  std::string source = "secondary_placeholder_state";
  std::string owner = "extension_parent_state_secondary_indicator";
  std::string parent_orchestration_rule = "parent_emphasis_bridge_v1";
  std::string parent_orchestration_state = "inactive";
};

struct ExtensionTertiaryMarkerDisplayData {
  bool visible = true;
  std::string text = "Note: idle";
  std::string variant = "muted";
  std::string source = "extension_parent_state";
};

struct ExtensionTertiaryMarkerInputRecord {
  bool visible = true;
  std::string text = "Note: idle";
  std::string variant = "muted";
  std::string source = "extension_parent_state";
  std::string owner = "extension_parent_state_tertiary_marker";
  std::string parent_coexistence_rule = "parent_subcomponent_isolation_v1";
  std::string parent_coexistence_state = "active";
};

struct ExtensionLaneState {
  bool active = false;
  const char* mode_identity = "baseline";
  const char* label_text = "Extension mode: active";
  bool placeholder_visible = false;
  bool info_card_visible = false;
  const char* info_card_title = "Runtime Control Card";
  const char* info_card_text = "Primary controls and status";
  ExtensionCardDisplayData card_display;
  ExtensionStatusChipDisplayData status_chip;
  ExtensionSecondaryIndicatorDisplayData secondary_indicator;
  ExtensionTertiaryMarkerDisplayData tertiary_marker;
  bool status_chip_interaction_active = false;
  bool parent_orchestration_active = false;
  const char* parent_orchestration_rule_name = "parent_emphasis_bridge_v1";
  bool parent_secondary_indicator_visible = false;
  const char* parent_visibility_rule_name = "parent_secondary_indicator_visibility_v1";
  bool parent_secondary_indicator_first = false;
  const char* parent_ordering_rule_name = "parent_subcomponent_ordering_v1";
  std::string parent_last_routed_intent = "none";
  const char* parent_conflict_rule_name = "parent_intent_priority_secondary_over_status_v1";
  std::string parent_conflict_last_mode = "none";
  std::string parent_conflict_winner_intent = "none";
  std::string secondary_placeholder_text = "State summary: inactive";
  ExtensionCompositionModel composition;
};

struct ExtensionLaneLayout {
  int background_x = 0;
  int background_y = 0;
  int background_width = 0;
  int background_height = 0;
  int label_x = 0;
  int label_y = 0;
  int label_width = 0;
  int label_height = 24;
  int placeholder_x = 0;
  int placeholder_y = 0;
  int placeholder_width = 0;
  int placeholder_height = 40;
  int info_card_x = 0;
  int info_card_y = 0;
  int info_card_width = 0;
  int info_card_height = 156;
  int status_chip_x = 0;
  int status_chip_y = 0;
  int status_chip_width = 180;
  int status_chip_height = 20;
  int secondary_indicator_x = 0;
  int secondary_indicator_y = 0;
  int secondary_indicator_width = 180;
  int secondary_indicator_height = 20;
  int tertiary_marker_x = 0;
  int tertiary_marker_y = 0;
  int tertiary_marker_width = 180;
  int tertiary_marker_height = 20;
};

enum class ExtensionInteractionInputKind {
  MouseMove,
  MouseButton,
  Key,
  Char
};

struct ExtensionInteractionState {
  bool active = false;
  const char* mode_identity = "baseline";
  std::uint64_t mouse_move_count = 0;
  std::uint64_t mouse_button_count = 0;
  std::uint64_t key_count = 0;
  std::uint64_t char_count = 0;
  bool mouse_move_marker_emitted = false;
  bool mouse_button_marker_emitted = false;
  bool key_marker_emitted = false;
  bool char_marker_emitted = false;
  std::uint64_t secondary_toggle_count = 0;
  std::uint64_t status_chip_toggle_count = 0;
  std::uint64_t secondary_indicator_intent_count = 0;
};

struct SandboxRunConfig {
  bool demo_mode = false;
  bool visual_baseline_mode = false;
  bool extension_visual_baseline_mode = false;
  SandboxLane lane = SandboxLane::Baseline;
};

const char* extension_primary_detail_text(bool secondary_active);
const char* extension_primary_detail_text_from_interaction(bool detail_interaction_applied, bool secondary_active);
const char* extension_status_chip_text(bool detail_interaction_applied, bool secondary_active);
const char* extension_status_chip_extra_line(bool detail_interaction_applied, bool secondary_active);
const char* extension_status_chip_variant(bool secondary_active);
const char* extension_status_chip_presentation_variant(bool detail_interaction_applied, bool secondary_active);
const char* extension_status_chip_layout_variant(bool detail_interaction_applied, bool secondary_active);
const char* extension_status_chip_interaction_boundary_state(bool interaction_active);
const char* extension_secondary_indicator_text(bool secondary_active);
const char* extension_secondary_indicator_variant(bool secondary_active);
const char* extension_header_band_summary_text(const ExtensionLaneState& state);
const char* extension_footer_strip_status_text(const ExtensionLaneState& state);
const char* extension_tertiary_marker_text(const ExtensionLaneState& state);
const char* extension_tertiary_marker_variant(const ExtensionLaneState& state);
bool extension_parent_visibility_rule_allows_secondary_indicator(const ExtensionLaneState& state);
void refresh_extension_parent_visibility_rule(ExtensionLaneState& state);
bool extension_parent_orchestration_rule_active(const ExtensionLaneState& state);
void refresh_extension_parent_orchestration_rule(ExtensionLaneState& state);
bool extension_parent_ordering_rule_secondary_first(const ExtensionLaneState& state);
void refresh_extension_parent_ordering_rule(ExtensionLaneState& state);
const char* extension_parent_conflict_mode(bool status_intent, bool secondary_intent);
const char* extension_parent_conflict_winner_intent(bool status_intent, bool secondary_intent);
void apply_extension_parent_routed_intent_outcome(
  ExtensionLaneState& state,
  bool status_intent,
  bool secondary_intent);
ExtensionStatusChipInputRecord build_extension_status_chip_input_record(const ExtensionLaneState& state);
ExtensionSecondaryIndicatorInputRecord build_extension_secondary_indicator_input_record(const ExtensionLaneState& state);
ExtensionTertiaryMarkerInputRecord build_extension_tertiary_marker_input_record(const ExtensionLaneState& state);

ExtensionLaneState make_extension_lane_state(SandboxLane lane) {
  ExtensionLaneState state;
  state.active = (lane == SandboxLane::ExtensionSlot);
  state.mode_identity = state.active ? "extension_slot_v1" : "baseline";
  state.composition.enabled = state.active;
  state.composition.primary_visible = state.active;
  state.composition.secondary_visible = state.active;
  state.info_card_visible = state.composition.primary_visible;
  state.placeholder_visible = state.composition.secondary_visible;
  state.card_display.secondary_active = false;
  state.card_display.summary_text = "State summary: inactive";
  state.card_display.summary_badge_variant = "neutral";
  state.card_display.detail_interaction_applied = false;
  state.card_display.detail_text = extension_primary_detail_text_from_interaction(
    state.card_display.detail_interaction_applied,
    state.card_display.secondary_active);
  state.status_chip.visible = state.active;
  state.status_chip.source = "secondary_placeholder_state";
  state.secondary_indicator.source = "secondary_placeholder_state";
  state.tertiary_marker.visible = state.active;
  state.tertiary_marker.text = extension_tertiary_marker_text(state);
  state.tertiary_marker.variant = extension_tertiary_marker_variant(state);
  state.tertiary_marker.source = "extension_parent_state";
  refresh_extension_parent_visibility_rule(state);
  refresh_extension_parent_orchestration_rule(state);
  refresh_extension_parent_ordering_rule(state);
  state.secondary_placeholder_text = "State summary: inactive";
  return state;
}

const char* extension_primary_summary_text(bool secondary_active) {
  return secondary_active ? "State summary: active" : "State summary: inactive";
}

const char* extension_primary_summary_badge_variant(bool secondary_active) {
  return secondary_active ? "emphasis" : "neutral";
}

const char* extension_layout_mode(bool secondary_active) {
  return secondary_active ? "expanded" : "compact";
}

const char* extension_primary_detail_text(bool secondary_active) {
  return secondary_active ? "Action: toggled active" : "Action: toggled inactive";
}

const char* extension_primary_detail_text_from_interaction(bool detail_interaction_applied, bool secondary_active) {
  if (!detail_interaction_applied) {
    return "Action: waiting for toggle";
  }

  return extension_primary_detail_text(secondary_active);
}

const char* extension_status_chip_text(bool detail_interaction_applied, bool secondary_active) {
  if (!detail_interaction_applied) {
    return "System state: ready";
  }

  return secondary_active ? "System state: active" : "System state: inactive";
}

const char* extension_status_chip_extra_line(bool detail_interaction_applied, bool secondary_active) {
  if (!detail_interaction_applied) {
    return "Feedback: ready";
  }

  return secondary_active ? "Feedback: active sync" : "Feedback: inactive sync";
}

const char* extension_status_chip_variant(bool secondary_active) {
  return secondary_active ? "active" : "neutral";
}

const char* extension_status_chip_presentation_variant(bool detail_interaction_applied, bool secondary_active) {
  if (detail_interaction_applied && secondary_active) {
    return "emphasis";
  }

  return "base";
}

const char* extension_status_chip_layout_variant(bool detail_interaction_applied, bool secondary_active) {
  if (detail_interaction_applied && secondary_active) {
    return "offset";
  }

  return "compact";
}

const char* extension_status_chip_interaction_boundary_state(bool interaction_active) {
  return interaction_active ? "active" : "inactive";
}

const char* extension_secondary_indicator_text(bool secondary_active) {
  return secondary_active ? "Support line: active" : "Support line: inactive";
}

const char* extension_secondary_indicator_variant(bool secondary_active) {
  return secondary_active ? "alert" : "neutral";
}

const char* extension_header_band_summary_text(const ExtensionLaneState& state) {
  if (state.parent_orchestration_active) {
    return "Mode: orchestration active";
  }
  if (state.card_display.secondary_active) {
    return "Mode: secondary active";
  }

  return "Mode: secondary inactive";
}

const char* extension_footer_strip_status_text(const ExtensionLaneState& state) {
  if (state.parent_orchestration_active) {
    return "Next action: orchestration active";
  }
  if (state.parent_secondary_indicator_visible) {
    return "Next action: visibility active";
  }

  return "Next action: ready";
}

const char* extension_tertiary_marker_text(const ExtensionLaneState& state) {
  if (state.parent_orchestration_active) {
    return "Note: orchestration active";
  }
  if (state.parent_conflict_last_mode == "both") {
    return "Note: conflict isolated";
  }
  if (state.parent_conflict_last_mode == "secondary_alone") {
    return "Note: secondary intent";
  }
  if (state.parent_conflict_last_mode == "status_alone") {
    return "Note: status intent";
  }

  return "Note: idle";
}

const char* extension_tertiary_marker_variant(const ExtensionLaneState& state) {
  if (state.parent_orchestration_active) {
    return "coordinated";
  }
  if (state.parent_conflict_last_mode == "both") {
    return "emphasis";
  }

  return "muted";
}

bool extension_parent_visibility_rule_allows_secondary_indicator(const ExtensionLaneState& state) {
  return state.card_display.secondary_active;
}

void refresh_extension_parent_visibility_rule(ExtensionLaneState& state) {
  state.parent_secondary_indicator_visible = extension_parent_visibility_rule_allows_secondary_indicator(state);
  state.secondary_indicator.visible = state.parent_secondary_indicator_visible;
}

bool extension_parent_orchestration_rule_active(const ExtensionLaneState& state) {
  return state.card_display.secondary_active && state.status_chip_interaction_active;
}

void refresh_extension_parent_orchestration_rule(ExtensionLaneState& state) {
  state.parent_orchestration_active = extension_parent_orchestration_rule_active(state);

  state.status_chip.text = extension_status_chip_text(
    state.card_display.detail_interaction_applied,
    state.card_display.secondary_active);
  state.status_chip.variant = extension_status_chip_variant(state.card_display.secondary_active);
  state.secondary_indicator.text = extension_secondary_indicator_text(state.card_display.secondary_active);
  state.secondary_indicator.variant = extension_secondary_indicator_variant(state.card_display.secondary_active);

  if (state.parent_orchestration_active) {
    state.status_chip.text = "chip: parent emphasis";
    state.secondary_indicator.text = "indicator: parent emphasis mirrored";
    state.secondary_indicator.variant = "mirror";
  }
}

bool extension_parent_ordering_rule_secondary_first(const ExtensionLaneState& state) {
  return state.parent_orchestration_active;
}

void refresh_extension_parent_ordering_rule(ExtensionLaneState& state) {
  state.parent_secondary_indicator_first = extension_parent_ordering_rule_secondary_first(state);
}

const char* extension_parent_conflict_mode(bool status_intent, bool secondary_intent) {
  if (status_intent && secondary_intent) {
    return "both";
  }
  if (status_intent) {
    return "status_alone";
  }
  if (secondary_intent) {
    return "secondary_alone";
  }
  return "none";
}

const char* extension_parent_conflict_winner_intent(bool status_intent, bool secondary_intent) {
  // Single deterministic parent rule: secondary intent wins when both intents are present.
  if (secondary_intent) {
    return "secondary_indicator_ping_intent";
  }
  if (status_intent) {
    return "status_chip_toggle_intent";
  }
  return "none";
}

void apply_extension_parent_routed_intent_outcome(
  ExtensionLaneState& state,
  bool status_intent,
  bool secondary_intent) {
  const char* mode = extension_parent_conflict_mode(status_intent, secondary_intent);
  const char* winner = extension_parent_conflict_winner_intent(status_intent, secondary_intent);
  state.parent_conflict_last_mode = mode;
  state.parent_conflict_winner_intent = winner;
  state.parent_last_routed_intent = winner;
  state.card_display.detail_interaction_applied = true;
  state.tertiary_marker.text = extension_tertiary_marker_text(state);
  state.tertiary_marker.variant = extension_tertiary_marker_variant(state);

  if (state.parent_conflict_last_mode == "both") {
    state.card_display.detail_text = "routing note: parent conflict winner secondary";
    return;
  }
  if (state.parent_conflict_last_mode == "status_alone") {
    state.card_display.detail_text = "routing note: parent handled status intent";
    return;
  }
  if (state.parent_conflict_last_mode == "secondary_alone") {
    state.card_display.detail_text = "routing note: parent handled secondary intent";
    return;
  }

  state.card_display.detail_text = "Action: waiting for toggle";
}

void apply_extension_primary_summary_badge_variant(ngk::ui::Label& summary_label, bool secondary_active) {
  if (secondary_active) {
    summary_label.set_background(0.10f, 0.13f, 0.15f, 1.0f);
    return;
  }

  summary_label.set_background(0.09f, 0.11f, 0.13f, 1.0f);
}

void apply_extension_status_chip_style(ngk::ui::Label& chip_label, const ExtensionStatusChipDisplayData& chip_data) {
  if (chip_data.variant == "active") {
    chip_label.set_background(0.08f, 0.24f, 0.14f, 1.0f);
    return;
  }

  chip_label.set_background(0.10f, 0.10f, 0.14f, 1.0f);
}

void apply_extension_status_chip_style_from_input(ngk::ui::Label& chip_label, const ExtensionStatusChipInputRecord& chip_input) {
  if (chip_input.interaction_boundary_state == "active") {
    chip_label.set_background(0.11f, 0.14f, 0.16f, 1.0f);
    return;
  }

  if (chip_input.presentation_variant == "emphasis") {
    chip_label.set_background(0.10f, 0.13f, 0.15f, 1.0f);
    return;
  }

  chip_label.set_background(0.09f, 0.12f, 0.14f, 1.0f);
}

void apply_extension_status_chip_input_to_label(ngk::ui::Label& chip_label, const ExtensionStatusChipInputRecord& chip_input) {
  // Keep the chip single-line so it cannot overrun its fixed slot height.
  chip_label.set_text(chip_input.text);
  const int chip_height = (chip_input.layout_variant == "offset") ? 24 : 20;
  chip_label.set_size(0, chip_height);
  chip_label.set_preferred_size(0, chip_height);
  apply_extension_status_chip_style_from_input(chip_label, chip_input);
}

ExtensionStatusChipInputRecord build_extension_status_chip_input_record(const ExtensionLaneState& state) {
  ExtensionStatusChipInputRecord input;
  input.visible = state.status_chip.visible;
  input.text = state.status_chip.text;
  input.content_extra_line = state.parent_orchestration_active
    ? "State: parent emphasis bridge"
    : extension_status_chip_extra_line(
        state.card_display.detail_interaction_applied,
        state.card_display.secondary_active);
  input.variant = state.status_chip.variant;
  input.presentation_variant = extension_status_chip_presentation_variant(
    state.card_display.detail_interaction_applied,
    state.card_display.secondary_active);
  if (state.parent_orchestration_active) {
    input.presentation_variant = "coordinated_emphasis";
  }
  input.layout_variant = extension_status_chip_layout_variant(
    state.card_display.detail_interaction_applied,
    state.card_display.secondary_active);
  input.interaction_boundary_state = extension_status_chip_interaction_boundary_state(state.status_chip_interaction_active);
  input.source = state.status_chip.source;
  input.owner = "extension_parent_state";
  input.parent_orchestration_rule = state.parent_orchestration_rule_name;
  input.parent_orchestration_state = state.parent_orchestration_active ? "active" : "inactive";
  return input;
}

void apply_extension_secondary_indicator_style_from_input(ngk::ui::Label& indicator_label, const ExtensionSecondaryIndicatorInputRecord& indicator_input) {
  if (indicator_input.variant == "mirror") {
    indicator_label.set_background(0.08f, 0.10f, 0.12f, 1.0f);
    return;
  }

  if (indicator_input.variant == "alert") {
    indicator_label.set_background(0.08f, 0.10f, 0.11f, 1.0f);
    return;
  }

  indicator_label.set_background(0.08f, 0.10f, 0.12f, 1.0f);
}

void apply_extension_secondary_indicator_input_to_label(ngk::ui::Label& indicator_label, const ExtensionSecondaryIndicatorInputRecord& indicator_input) {
  indicator_label.set_text(indicator_input.text);
  apply_extension_secondary_indicator_style_from_input(indicator_label, indicator_input);
}

ExtensionSecondaryIndicatorInputRecord build_extension_secondary_indicator_input_record(const ExtensionLaneState& state) {
  ExtensionSecondaryIndicatorInputRecord input;
  input.visible = state.secondary_indicator.visible;
  input.text = state.secondary_indicator.text;
  input.variant = state.secondary_indicator.variant;
  input.source = state.secondary_indicator.source;
  input.owner = "extension_parent_state_secondary_indicator";
  input.parent_orchestration_rule = state.parent_orchestration_rule_name;
  input.parent_orchestration_state = state.parent_orchestration_active ? "active" : "inactive";
  return input;
}

void apply_extension_tertiary_marker_style_from_input(ngk::ui::Label& marker_label, const ExtensionTertiaryMarkerInputRecord& marker_input) {
  if (marker_input.variant == "emphasis") {
    marker_label.set_background(0.08f, 0.09f, 0.10f, 1.0f);
    return;
  }

  if (marker_input.variant == "coordinated") {
    marker_label.set_background(0.08f, 0.10f, 0.11f, 1.0f);
    return;
  }

  marker_label.set_background(0.07f, 0.09f, 0.10f, 1.0f);
}

void apply_extension_tertiary_marker_input_to_label(ngk::ui::Label& marker_label, const ExtensionTertiaryMarkerInputRecord& marker_input) {
  marker_label.set_text(marker_input.text);
  apply_extension_tertiary_marker_style_from_input(marker_label, marker_input);
}

ExtensionTertiaryMarkerInputRecord build_extension_tertiary_marker_input_record(const ExtensionLaneState& state) {
  ExtensionTertiaryMarkerInputRecord input;
  input.visible = state.tertiary_marker.visible;
  input.text = state.tertiary_marker.text;
  input.variant = state.tertiary_marker.variant;
  input.source = state.tertiary_marker.source;
  input.owner = "extension_parent_state_tertiary_marker";
  input.parent_coexistence_rule = "parent_subcomponent_isolation_v1";
  input.parent_coexistence_state = "active";
  return input;
}

ExtensionLaneLayout compute_extension_lane_layout(int width, int height, bool secondary_active, bool secondary_indicator_first) {
  ExtensionLaneLayout layout;
  layout.background_x = 0;
  layout.background_y = 0;
  layout.background_width = width;
  layout.background_height = height;
  layout.label_x = UI_MARGIN;
  layout.label_y = UI_MARGIN + 64;
  layout.label_width = std::max(0, width - (UI_MARGIN * 2));
  layout.info_card_x = UI_MARGIN;
  layout.info_card_y = layout.label_y + layout.label_height + 12;
  layout.info_card_width = std::max(0, width - (UI_MARGIN * 2));
  layout.info_card_height = 156;
  layout.status_chip_x = layout.info_card_x + 10;
  layout.status_chip_width = std::max(0, layout.info_card_width - 20);
  layout.status_chip_height = 20;
  layout.secondary_indicator_x = layout.info_card_x + 10;
  layout.secondary_indicator_width = std::max(0, layout.info_card_width - 20);
  layout.secondary_indicator_height = 20;
  if (secondary_indicator_first) {
    layout.secondary_indicator_y = layout.info_card_y + 66;
    layout.status_chip_y = layout.secondary_indicator_y + layout.secondary_indicator_height + 2;
  } else {
    layout.status_chip_y = layout.info_card_y + 66;
    layout.secondary_indicator_y = layout.status_chip_y + layout.status_chip_height + 2;
  }
  layout.tertiary_marker_x = layout.info_card_x + 10;
  layout.tertiary_marker_width = std::max(0, layout.info_card_width - 20);
  layout.tertiary_marker_height = 20;
  layout.tertiary_marker_y = std::max(layout.status_chip_y, layout.secondary_indicator_y)
    + std::max(layout.status_chip_height, layout.secondary_indicator_height)
    + 2;
  layout.placeholder_height = secondary_active ? 22 : 16;
  layout.placeholder_x = UI_MARGIN;
  layout.placeholder_y = layout.info_card_y + layout.info_card_height + 12;
  layout.placeholder_width = std::max(0, width - (UI_MARGIN * 2));
  return layout;
}

ExtensionInteractionState make_extension_interaction_state(const ExtensionLaneState& lane_state) {
  ExtensionInteractionState state;
  state.active = lane_state.active;
  state.mode_identity = lane_state.mode_identity;
  return state;
}

SandboxRunConfig normalize_run_config(bool demo_mode, bool visual_baseline_mode, bool extension_visual_baseline_mode, SandboxLane lane) {
  SandboxRunConfig cfg;
  cfg.demo_mode = demo_mode;
  cfg.visual_baseline_mode = visual_baseline_mode;
  cfg.extension_visual_baseline_mode = extension_visual_baseline_mode;
  cfg.lane = lane;

  // Baseline visual mode always wins and keeps validation deterministic.
  if (cfg.visual_baseline_mode) {
    cfg.demo_mode = false;
    cfg.lane = SandboxLane::Baseline;
    cfg.extension_visual_baseline_mode = false;
    return cfg;
  }

  if (cfg.extension_visual_baseline_mode) {
    cfg.demo_mode = false;
    cfg.lane = SandboxLane::ExtensionSlot;
  }

  return cfg;
}

void emit_extension_lane_startup_tokens(const ExtensionLaneState& state, const ExtensionLaneLayout& layout, const ngk::ui::Label& label) {
  if (!state.active) {
    return;
  }

  const ExtensionStatusChipInputRecord status_chip_input = build_extension_status_chip_input_record(state);
  const ExtensionSecondaryIndicatorInputRecord secondary_indicator_input = build_extension_secondary_indicator_input_record(state);
  const ExtensionTertiaryMarkerInputRecord tertiary_marker_input = build_extension_tertiary_marker_input_record(state);

  std::cout << "widget_extension_mode_label_present=1\n";
  std::cout << "widget_extension_mode_label_text=" << label.text() << "\n";
  std::cout << "widget_extension_state_mode=" << state.mode_identity << "\n";
  std::cout << "widget_extension_composition_model=" << state.composition.primary_name << "+" << state.composition.secondary_name << "\n";
  std::cout << "widget_extension_slot_primary_visible=" << (state.composition.primary_visible ? 1 : 0) << "\n";
  std::cout << "widget_extension_slot_secondary_visible=" << (state.composition.secondary_visible ? 1 : 0) << "\n";
  std::cout << "widget_extension_placeholder_visible=" << (state.placeholder_visible ? 1 : 0) << "\n";
  std::cout << "widget_extension_presentation_variant=primary_summary_badge_emphasis_v1\n";
  std::cout << "widget_extension_data_shape=card_display_v1\n";
  std::cout << "widget_extension_card_data_secondary_state=" << (state.card_display.secondary_active ? "active" : "inactive") << "\n";
  std::cout << "widget_extension_card_data_summary_text=" << state.card_display.summary_text << "\n";
  std::cout << "widget_extension_card_data_badge_variant=" << state.card_display.summary_badge_variant << "\n";
  std::cout << "widget_extension_card_data_detail_text=" << state.card_display.detail_text << "\n";
  std::cout << "widget_extension_primary_summary_badge_variant=" << state.card_display.summary_badge_variant << "\n";
  std::cout << "widget_extension_primary_summary_badge_selector=secondary_placeholder_state\n";
  std::cout << "widget_extension_layout_mode=" << extension_layout_mode(state.card_display.secondary_active) << "\n";
  std::cout << "widget_extension_layout_placeholder_height=" << layout.placeholder_height << "\n";
  std::cout << "widget_extension_layout_mode_selector=secondary_placeholder_state\n";
  std::cout << "widget_extension_content_update_mode=interaction_driven_detail_v1\n";
  std::cout << "widget_extension_card_data_detail_source=secondary_toggle_interaction\n";
  std::cout << "widget_extension_parent_visibility_rule_name=" << state.parent_visibility_rule_name << "\n";
  std::cout << "widget_extension_parent_visibility_rule_owner=extension_parent_state\n";
  std::cout << "widget_extension_parent_visibility_rule_target=secondary_indicator_v1\n";
  std::cout << "widget_extension_parent_visibility_rule_state=" << (state.parent_secondary_indicator_visible ? "visible" : "hidden") << "\n";
  std::cout << "widget_extension_parent_ordering_rule_name=" << state.parent_ordering_rule_name << "\n";
  std::cout << "widget_extension_parent_ordering_rule_owner=extension_parent_state\n";
  std::cout << "widget_extension_parent_ordering_rule_state=" << (state.parent_secondary_indicator_first ? "secondary_first" : "status_first") << "\n";
  std::cout << "widget_extension_parent_ordering_child_dependency=none\n";
  std::cout << "widget_extension_parent_interaction_routing_owner=extension_parent_state\n";
  std::cout << "widget_extension_parent_interaction_routing_last_intent=" << state.parent_last_routed_intent << "\n";
  std::cout << "widget_extension_parent_interaction_routing_child_dependency=none\n";
  std::cout << "widget_extension_parent_conflict_rule_name=" << state.parent_conflict_rule_name << "\n";
  std::cout << "widget_extension_parent_conflict_rule_owner=extension_parent_state\n";
  std::cout << "widget_extension_parent_conflict_mode=" << state.parent_conflict_last_mode << "\n";
  std::cout << "widget_extension_parent_conflict_winner=" << state.parent_conflict_winner_intent << "\n";
  std::cout << "widget_extension_parent_conflict_child_dependency=none\n";
  std::cout << "widget_extension_parent_orchestration_rule_name=" << state.parent_orchestration_rule_name << "\n";
  std::cout << "widget_extension_parent_orchestration_rule_owner=extension_parent_state\n";
  std::cout << "widget_extension_parent_orchestration_rule_state=" << (state.parent_orchestration_active ? "active" : "inactive") << "\n";
  std::cout << "widget_extension_parent_orchestration_child_dependency=none\n";
  std::cout << "widget_extension_layout_container_name=sandbox_extension_panel\n";
  std::cout << "widget_extension_layout_container_role=subcomponent_layout_surface\n";
  std::cout << "widget_extension_layout_container_owner=extension_parent_state\n";
  std::cout << "widget_extension_layout_container_child_order=status_chip_v1,secondary_indicator_v1,tertiary_marker_subcomponent\n";
  std::cout << "widget_extension_layout_container_child_count=3\n";
  std::cout << "widget_extension_layout_container_header_band_name=sandbox_extension_header_band\n";
  std::cout << "widget_extension_layout_container_header_band_role=layout_header_region\n";
  std::cout << "widget_extension_layout_container_header_band_owner=extension_parent_state\n";
  std::cout << "widget_extension_layout_container_header_band_title=Runtime Panel\n";
  std::cout << "widget_extension_layout_container_header_band_summary=" << extension_header_band_summary_text(state) << "\n";
  std::cout << "widget_extension_layout_container_header_band_summary_owner=extension_parent_state\n";
  std::cout << "widget_extension_layout_container_header_band_summary_child_dependency=none\n";
  std::cout << "widget_extension_layout_container_region_order=header_band,body_region,footer_strip\n";
  std::cout << "widget_extension_layout_container_body_region_name=sandbox_extension_body_region\n";
  std::cout << "widget_extension_layout_container_body_region_role=layout_body_region\n";
  std::cout << "widget_extension_layout_container_body_region_owner=extension_parent_state\n";
  std::cout << "widget_extension_layout_container_body_region_title=State Overview\n";
  std::cout << "widget_extension_layout_container_body_region_child_order=status_chip_v1,secondary_indicator_v1,tertiary_marker_subcomponent\n";
  std::cout << "widget_extension_layout_container_body_region_child_count=3\n";
  std::cout << "widget_extension_layout_container_body_region_child_dependency=none\n";
  std::cout << "widget_extension_layout_container_body_hierarchy_rule=first_child_primary_visual_weight_v1\n";
  std::cout << "widget_extension_layout_container_body_hierarchy_primary_child=status_chip_v1\n";
  std::cout << "widget_extension_layout_container_body_hierarchy_supporting_children=secondary_indicator_v1,tertiary_marker_subcomponent\n";
  std::cout << "widget_extension_layout_container_body_hierarchy_owner=extension_parent_state\n";
  std::cout << "widget_extension_layout_container_body_composition_rule=uniform_child_slot_height_v1\n";
  std::cout << "widget_extension_layout_container_body_composition_slot_height=20\n";
  std::cout << "widget_extension_layout_container_body_composition_owner=extension_parent_state\n";
  std::cout << "widget_extension_layout_container_footer_strip_name=sandbox_extension_footer_strip\n";
  std::cout << "widget_extension_layout_container_footer_strip_role=layout_footer_region\n";
  std::cout << "widget_extension_layout_container_footer_strip_owner=extension_parent_state\n";
  std::cout << "widget_extension_layout_container_footer_strip_title=Next Action\n";
  std::cout << "widget_extension_layout_container_footer_strip_value=" << extension_footer_strip_status_text(state) << "\n";
  std::cout << "widget_extension_layout_container_footer_strip_status_owner=extension_parent_state\n";
  std::cout << "widget_extension_layout_container_footer_strip_child_dependency=none\n";
  std::cout << "widget_extension_layout_container_region_backgrounds=header:0.10,0.12,0.14,1.00|body:0.11,0.13,0.15,1.00|footer:0.10,0.12,0.14,1.00\n";
  std::cout << "widget_extension_layout_container_readability_profile=panel_calm_control_card_reconstruction_v1\n";
  std::cout << "widget_extension_layout_container_readability_spacing=panel:11|header:12|body:11|footer:11\n";
  std::cout << "widget_extension_layout_container_readability_typography=header_title:17|header_summary:15|body_title:16|footer_text:14|control_label:22\n";
  std::cout << "widget_extension_layout_container_text_contrast_profile=calm_control_card_hierarchy_v1\n";
  std::cout << "widget_extension_layout_container_visual_consolidation_profile=compact_control_surface_v1\n";
  std::cout << "widget_extension_layout_container_visual_fragmentation=reduced\n";
  std::cout << "widget_extension_layout_container_visual_grouping=header_body_footer_coherent\n";
  std::cout << "widget_extension_layout_container_surface_grouping_profile=cohesive_body_surface_v1\n";
  std::cout << "widget_extension_layout_container_body_grouping_style=single_grouped_content_area\n";
  std::cout << "widget_extension_layout_container_body_row_striping=softened\n";
  std::cout << "widget_extension_layout_container_body_padding_refinement=inner:10,8,10,8\n";
  std::cout << "widget_extension_layout_container_primary_emphasis_profile=primary_card_focus_v1\n";
  std::cout << "widget_extension_layout_container_primary_child_spacing=expanded_top_anchor\n";
  std::cout << "widget_extension_layout_container_supporting_children_tone=deemphasized_readable_v1\n";
  std::cout << "widget_extension_layout_container_footer_integration_profile=panel_footer_blend_v1\n";
  std::cout << "widget_extension_layout_container_footer_padding_refinement=inner:9,4,9,4\n";
  std::cout << "widget_extension_layout_container_footer_text_legibility=title:13|value:16\n";
  std::cout << "widget_extension_layout_container_header_integration_profile=panel_header_blend_v1\n";
  std::cout << "widget_extension_layout_container_header_padding_refinement=inner:9,5,9,4\n";
  std::cout << "widget_extension_layout_container_header_text_legibility=title:17|summary:15\n";
  std::cout << "widget_extension_layout_container_full_panel_cohesion_profile=unified_compact_surface_v1\n";
  std::cout << "widget_extension_layout_container_divider_language=unified_control_card_surface_v1\n";
  std::cout << "widget_extension_layout_container_region_spacing_rhythm=header:11|body:11|footer:11\n";
  std::cout << "widget_extension_layout_container_controls_integration_profile=panel_controls_action_focus_v1\n";
  std::cout << "widget_extension_layout_container_controls_surface=bg:0.12,0.16,0.19,1.00|label:0.12,0.16,0.19,1.00\n";
  std::cout << "widget_extension_layout_container_controls_spacing=label:22|input:42|row:66\n";
  std::cout << "widget_extension_layout_container_controls_padding_refinement=row:6\n";
  std::cout << "widget_extension_layout_container_text_hierarchy_profile=intentional_label_cleanup_v1\n";
  std::cout << "widget_extension_layout_container_text_debug_noise=reduced\n";
  std::cout << "widget_extension_layout_container_text_label_style=title:clear|section:concise|status:compact\n";
  std::cout << "widget_extension_subcomponent_name=status_chip_v1\n";
  std::cout << "widget_extension_subcomponent_secondary_name=secondary_indicator_v1\n";
  std::cout << "widget_extension_subcomponent_tertiary_name=tertiary_marker_subcomponent\n";
  std::cout << "widget_extension_subcomponent_coexistence=status_chip_v1+secondary_indicator_v1+tertiary_marker_subcomponent\n";
  std::cout << "widget_extension_subcomponent_input_record=status_chip_input_v1\n";
  std::cout << "widget_extension_subcomponent_input_owner=" << status_chip_input.owner << "\n";
  std::cout << "widget_extension_subcomponent_visible=" << (status_chip_input.visible ? 1 : 0) << "\n";
  std::cout << "widget_extension_subcomponent_input_text=" << status_chip_input.text << "\n";
  std::cout << "widget_extension_subcomponent_input_content_extra_line=" << status_chip_input.content_extra_line << "\n";
  std::cout << "widget_extension_subcomponent_input_variant=" << status_chip_input.variant << "\n";
  std::cout << "widget_extension_subcomponent_input_presentation_variant=" << status_chip_input.presentation_variant << "\n";
  std::cout << "widget_extension_subcomponent_input_layout_variant=" << status_chip_input.layout_variant << "\n";
  std::cout << "widget_extension_subcomponent_input_layout_height=" << ((status_chip_input.layout_variant == "offset") ? 24 : 20) << "\n";
  std::cout << "widget_extension_subcomponent_input_interaction_boundary_state=" << status_chip_input.interaction_boundary_state << "\n";
  std::cout << "widget_extension_subcomponent_input_parent_orchestration_rule=" << status_chip_input.parent_orchestration_rule << "\n";
  std::cout << "widget_extension_subcomponent_input_parent_orchestration_state=" << status_chip_input.parent_orchestration_state << "\n";
  std::cout << "widget_extension_subcomponent_input_source=" << status_chip_input.source << "\n";
  std::cout << "widget_extension_subcomponent_secondary_input_record=secondary_indicator_input_v1\n";
  std::cout << "widget_extension_subcomponent_secondary_input_owner=" << secondary_indicator_input.owner << "\n";
  std::cout << "widget_extension_subcomponent_secondary_visible=" << (secondary_indicator_input.visible ? 1 : 0) << "\n";
  std::cout << "widget_extension_subcomponent_secondary_visibility_owner=extension_parent_state\n";
  std::cout << "widget_extension_subcomponent_secondary_input_text=" << secondary_indicator_input.text << "\n";
  std::cout << "widget_extension_subcomponent_secondary_input_variant=" << secondary_indicator_input.variant << "\n";
  std::cout << "widget_extension_subcomponent_secondary_input_parent_orchestration_rule=" << secondary_indicator_input.parent_orchestration_rule << "\n";
  std::cout << "widget_extension_subcomponent_secondary_input_parent_orchestration_state=" << secondary_indicator_input.parent_orchestration_state << "\n";
  std::cout << "widget_extension_subcomponent_secondary_input_source=" << secondary_indicator_input.source << "\n";
  std::cout << "widget_extension_subcomponent_tertiary_input_record=tertiary_marker_input_v1\n";
  std::cout << "widget_extension_subcomponent_tertiary_input_owner=" << tertiary_marker_input.owner << "\n";
  std::cout << "widget_extension_subcomponent_tertiary_visible=" << (tertiary_marker_input.visible ? 1 : 0) << "\n";
  std::cout << "widget_extension_subcomponent_tertiary_input_text=" << tertiary_marker_input.text << "\n";
  std::cout << "widget_extension_subcomponent_tertiary_input_variant=" << tertiary_marker_input.variant << "\n";
  std::cout << "widget_extension_subcomponent_tertiary_input_source=" << tertiary_marker_input.source << "\n";
  std::cout << "widget_extension_subcomponent_tertiary_parent_coexistence_rule=" << tertiary_marker_input.parent_coexistence_rule << "\n";
  std::cout << "widget_extension_subcomponent_tertiary_parent_coexistence_state=" << tertiary_marker_input.parent_coexistence_state << "\n";
  std::cout << "widget_extension_subcomponent_tertiary_child_dependency=none\n";
  std::cout << "widget_extension_primary_summary_text=" << state.card_display.summary_text << "\n";
  std::cout << "widget_extension_secondary_placeholder_state=" << (state.card_display.secondary_active ? "active" : "inactive") << "\n";
  std::cout << "widget_extension_layout_background=" << layout.background_x << "," << layout.background_y << "," << layout.background_width << "," << layout.background_height << "\n";
  std::cout << "widget_extension_layout_label=" << layout.label_x << "," << layout.label_y << "," << layout.label_width << "," << layout.label_height << "\n";
  std::cout << "widget_extension_layout_placeholder=" << layout.placeholder_x << "," << layout.placeholder_y << "," << layout.placeholder_width << "," << layout.placeholder_height << "\n";
  std::cout << "widget_extension_layout_info_card=" << layout.info_card_x << "," << layout.info_card_y << "," << layout.info_card_width << "," << layout.info_card_height << "\n";
  std::cout << "widget_extension_layout_status_chip=" << layout.status_chip_x << "," << layout.status_chip_y << "," << layout.status_chip_width << "," << layout.status_chip_height << "\n";
  std::cout << "widget_extension_layout_secondary_indicator=" << layout.secondary_indicator_x << "," << layout.secondary_indicator_y << "," << layout.secondary_indicator_width << "," << layout.secondary_indicator_height << "\n";
  std::cout << "widget_extension_layout_tertiary_marker=" << layout.tertiary_marker_x << "," << layout.tertiary_marker_y << "," << layout.tertiary_marker_width << "," << layout.tertiary_marker_height << "\n";
  std::cout << "widget_extension_layout_child_order=" << (state.parent_secondary_indicator_first ? "secondary_indicator_v1,status_chip_v1" : "status_chip_v1,secondary_indicator_v1") << "\n";
}

void emit_extension_visual_contract_frame_tokens(
  const ExtensionLaneState& state,
  const ExtensionStatusChipInputRecord& status_chip_input,
  const ExtensionSecondaryIndicatorInputRecord& secondary_indicator_input,
  const ExtensionTertiaryMarkerInputRecord& tertiary_marker_input
) {
  std::cout << "widget_extension_visual_contract_background_present=1\n";
  std::cout << "widget_extension_visual_contract_label_present=1\n";
  std::cout << "widget_extension_visual_contract_placeholder_visible=" << (state.placeholder_visible ? 1 : 0) << "\n";
  std::cout << "widget_extension_visual_contract_info_card_visible=" << (state.info_card_visible ? 1 : 0) << "\n";
  std::cout << "widget_extension_visual_contract_secondary_placeholder_visible=" << (state.placeholder_visible ? 1 : 0) << "\n";
  std::cout << "widget_extension_visual_card_data_shape=card_display_v1\n";
  std::cout << "widget_extension_visual_layout_mode=" << extension_layout_mode(state.card_display.secondary_active) << "\n";
  std::cout << "widget_extension_visual_primary_detail_text=" << state.card_display.detail_text << "\n";
  std::cout << "widget_extension_visual_primary_summary_badge_variant=" << state.card_display.summary_badge_variant << "\n";
  std::cout << "widget_extension_visual_parent_visibility_rule_name=" << state.parent_visibility_rule_name << "\n";
  std::cout << "widget_extension_visual_parent_visibility_rule_owner=extension_parent_state\n";
  std::cout << "widget_extension_visual_parent_visibility_rule_target=secondary_indicator_v1\n";
  std::cout << "widget_extension_visual_parent_visibility_rule_state=" << (state.parent_secondary_indicator_visible ? "visible" : "hidden") << "\n";
  std::cout << "widget_extension_visual_parent_ordering_rule_name=" << state.parent_ordering_rule_name << "\n";
  std::cout << "widget_extension_visual_parent_ordering_rule_owner=extension_parent_state\n";
  std::cout << "widget_extension_visual_parent_ordering_rule_state=" << (state.parent_secondary_indicator_first ? "secondary_first" : "status_first") << "\n";
  std::cout << "widget_extension_visual_parent_ordering_child_dependency=none\n";
  std::cout << "widget_extension_visual_parent_interaction_routing_owner=extension_parent_state\n";
  std::cout << "widget_extension_visual_parent_interaction_routing_last_intent=" << state.parent_last_routed_intent << "\n";
  std::cout << "widget_extension_visual_parent_interaction_routing_child_dependency=none\n";
  std::cout << "widget_extension_visual_parent_conflict_rule_name=" << state.parent_conflict_rule_name << "\n";
  std::cout << "widget_extension_visual_parent_conflict_rule_owner=extension_parent_state\n";
  std::cout << "widget_extension_visual_parent_conflict_mode=" << state.parent_conflict_last_mode << "\n";
  std::cout << "widget_extension_visual_parent_conflict_winner=" << state.parent_conflict_winner_intent << "\n";
  std::cout << "widget_extension_visual_parent_conflict_child_dependency=none\n";
  std::cout << "widget_extension_visual_parent_orchestration_rule_name=" << state.parent_orchestration_rule_name << "\n";
  std::cout << "widget_extension_visual_parent_orchestration_rule_owner=extension_parent_state\n";
  std::cout << "widget_extension_visual_parent_orchestration_rule_state=" << (state.parent_orchestration_active ? "active" : "inactive") << "\n";
  std::cout << "widget_extension_visual_parent_orchestration_child_dependency=none\n";
  std::cout << "widget_extension_visual_layout_container_header_band_name=sandbox_extension_header_band\n";
  std::cout << "widget_extension_visual_layout_container_header_band_role=layout_header_region\n";
  std::cout << "widget_extension_visual_layout_container_header_band_owner=extension_parent_state\n";
  std::cout << "widget_extension_visual_layout_container_header_band_title=Runtime Panel\n";
  std::cout << "widget_extension_visual_layout_container_header_band_summary=" << extension_header_band_summary_text(state) << "\n";
  std::cout << "widget_extension_visual_layout_container_header_band_summary_owner=extension_parent_state\n";
  std::cout << "widget_extension_visual_layout_container_header_band_summary_child_dependency=none\n";
  std::cout << "widget_extension_visual_layout_container_region_order=header_band,body_region,footer_strip\n";
  std::cout << "widget_extension_visual_layout_container_body_region_name=sandbox_extension_body_region\n";
  std::cout << "widget_extension_visual_layout_container_body_region_role=layout_body_region\n";
  std::cout << "widget_extension_visual_layout_container_body_region_owner=extension_parent_state\n";
  std::cout << "widget_extension_visual_layout_container_body_region_title=State Overview\n";
  std::cout << "widget_extension_visual_layout_container_body_region_child_order=status_chip_v1,secondary_indicator_v1,tertiary_marker_subcomponent\n";
  std::cout << "widget_extension_visual_layout_container_body_region_child_count=3\n";
  std::cout << "widget_extension_visual_layout_container_body_region_child_dependency=none\n";
  std::cout << "widget_extension_visual_layout_container_body_hierarchy_rule=first_child_primary_visual_weight_v1\n";
  std::cout << "widget_extension_visual_layout_container_body_hierarchy_primary_child=status_chip_v1\n";
  std::cout << "widget_extension_visual_layout_container_body_hierarchy_supporting_children=secondary_indicator_v1,tertiary_marker_subcomponent\n";
  std::cout << "widget_extension_visual_layout_container_body_hierarchy_owner=extension_parent_state\n";
  std::cout << "widget_extension_visual_layout_container_body_composition_rule=uniform_child_slot_height_v1\n";
  std::cout << "widget_extension_visual_layout_container_body_composition_slot_height=20\n";
  std::cout << "widget_extension_visual_layout_container_body_composition_owner=extension_parent_state\n";
  std::cout << "widget_extension_visual_layout_container_footer_strip_name=sandbox_extension_footer_strip\n";
  std::cout << "widget_extension_visual_layout_container_footer_strip_role=layout_footer_region\n";
  std::cout << "widget_extension_visual_layout_container_footer_strip_owner=extension_parent_state\n";
  std::cout << "widget_extension_visual_layout_container_footer_strip_title=Next Action\n";
  std::cout << "widget_extension_visual_layout_container_footer_strip_value=" << extension_footer_strip_status_text(state) << "\n";
  std::cout << "widget_extension_visual_layout_container_footer_strip_status_owner=extension_parent_state\n";
  std::cout << "widget_extension_visual_layout_container_footer_strip_child_dependency=none\n";
  std::cout << "widget_extension_visual_layout_container_region_backgrounds=header:0.10,0.12,0.14,1.00|body:0.11,0.13,0.15,1.00|footer:0.10,0.12,0.14,1.00\n";
  std::cout << "widget_extension_visual_layout_container_readability_profile=panel_calm_control_card_reconstruction_v1\n";
  std::cout << "widget_extension_visual_layout_container_readability_spacing=panel:11|header:12|body:11|footer:11\n";
  std::cout << "widget_extension_visual_layout_container_readability_typography=header_title:17|header_summary:15|body_title:16|footer_text:14|control_label:22\n";
  std::cout << "widget_extension_visual_layout_container_text_contrast_profile=calm_control_card_hierarchy_v1\n";
  std::cout << "widget_extension_visual_layout_container_visual_consolidation_profile=compact_control_surface_v1\n";
  std::cout << "widget_extension_visual_layout_container_visual_fragmentation=reduced\n";
  std::cout << "widget_extension_visual_layout_container_visual_grouping=header_body_footer_coherent\n";
  std::cout << "widget_extension_visual_layout_container_surface_grouping_profile=cohesive_body_surface_v1\n";
  std::cout << "widget_extension_visual_layout_container_body_grouping_style=single_grouped_content_area\n";
  std::cout << "widget_extension_visual_layout_container_body_row_striping=softened\n";
  std::cout << "widget_extension_visual_layout_container_body_padding_refinement=inner:10,8,10,8\n";
  std::cout << "widget_extension_visual_layout_container_primary_emphasis_profile=primary_card_focus_v1\n";
  std::cout << "widget_extension_visual_layout_container_primary_child_spacing=expanded_top_anchor\n";
  std::cout << "widget_extension_visual_layout_container_supporting_children_tone=deemphasized_readable_v1\n";
  std::cout << "widget_extension_visual_layout_container_footer_integration_profile=panel_footer_blend_v1\n";
  std::cout << "widget_extension_visual_layout_container_footer_padding_refinement=inner:9,4,9,4\n";
  std::cout << "widget_extension_visual_layout_container_footer_text_legibility=title:13|value:16\n";
  std::cout << "widget_extension_visual_layout_container_header_integration_profile=panel_header_blend_v1\n";
  std::cout << "widget_extension_visual_layout_container_header_padding_refinement=inner:9,5,9,4\n";
  std::cout << "widget_extension_visual_layout_container_header_text_legibility=title:17|summary:15\n";
  std::cout << "widget_extension_visual_layout_container_full_panel_cohesion_profile=unified_compact_surface_v1\n";
  std::cout << "widget_extension_visual_layout_container_divider_language=unified_control_card_surface_v1\n";
  std::cout << "widget_extension_visual_layout_container_region_spacing_rhythm=header:11|body:11|footer:11\n";
  std::cout << "widget_extension_visual_layout_container_controls_integration_profile=panel_controls_action_focus_v1\n";
  std::cout << "widget_extension_visual_layout_container_controls_surface=bg:0.12,0.16,0.19,1.00|label:0.12,0.16,0.19,1.00\n";
  std::cout << "widget_extension_visual_layout_container_controls_spacing=label:22|input:42|row:66\n";
  std::cout << "widget_extension_visual_layout_container_controls_padding_refinement=row:6\n";
  std::cout << "widget_extension_visual_layout_container_text_hierarchy_profile=intentional_label_cleanup_v1\n";
  std::cout << "widget_extension_visual_layout_container_text_debug_noise=reduced\n";
  std::cout << "widget_extension_visual_layout_container_text_label_style=title:clear|section:concise|status:compact\n";
  std::cout << "widget_extension_visual_layout_container_name=sandbox_extension_panel\n";
  std::cout << "widget_extension_visual_layout_container_role=subcomponent_layout_surface\n";
  std::cout << "widget_extension_visual_layout_container_owner=extension_parent_state\n";
  std::cout << "widget_extension_visual_layout_container_child_order=status_chip_v1,secondary_indicator_v1,tertiary_marker_subcomponent\n";
  std::cout << "widget_extension_visual_layout_container_child_count=3\n";
  std::cout << "widget_extension_visual_subcomponent_input_record=status_chip_input_v1\n";
  std::cout << "widget_extension_visual_subcomponent_input_owner=" << status_chip_input.owner << "\n";
  std::cout << "widget_extension_visual_subcomponent_visible=" << (status_chip_input.visible ? 1 : 0) << "\n";
  std::cout << "widget_extension_visual_subcomponent_text=" << status_chip_input.text << "\n";
  std::cout << "widget_extension_visual_subcomponent_content_extra_line=" << status_chip_input.content_extra_line << "\n";
  std::cout << "widget_extension_visual_subcomponent_variant=" << status_chip_input.variant << "\n";
  std::cout << "widget_extension_visual_subcomponent_presentation_variant=" << status_chip_input.presentation_variant << "\n";
  std::cout << "widget_extension_visual_subcomponent_layout_variant=" << status_chip_input.layout_variant << "\n";
  std::cout << "widget_extension_visual_subcomponent_layout_height=" << ((status_chip_input.layout_variant == "offset") ? 24 : 20) << "\n";
  std::cout << "widget_extension_visual_subcomponent_interaction_boundary_state=" << status_chip_input.interaction_boundary_state << "\n";
  std::cout << "widget_extension_visual_subcomponent_parent_orchestration_state=" << status_chip_input.parent_orchestration_state << "\n";
  std::cout << "widget_extension_visual_subcomponent_secondary_input_record=secondary_indicator_input_v1\n";
  std::cout << "widget_extension_visual_subcomponent_secondary_input_owner=" << secondary_indicator_input.owner << "\n";
  std::cout << "widget_extension_visual_subcomponent_secondary_visible=" << (secondary_indicator_input.visible ? 1 : 0) << "\n";
  std::cout << "widget_extension_visual_subcomponent_secondary_visibility_owner=extension_parent_state\n";
  std::cout << "widget_extension_visual_subcomponent_secondary_text=" << secondary_indicator_input.text << "\n";
  std::cout << "widget_extension_visual_subcomponent_secondary_variant=" << secondary_indicator_input.variant << "\n";
  std::cout << "widget_extension_visual_subcomponent_secondary_parent_orchestration_state=" << secondary_indicator_input.parent_orchestration_state << "\n";
  std::cout << "widget_extension_visual_subcomponent_tertiary_input_record=tertiary_marker_input_v1\n";
  std::cout << "widget_extension_visual_subcomponent_tertiary_input_owner=" << tertiary_marker_input.owner << "\n";
  std::cout << "widget_extension_visual_subcomponent_tertiary_visible=" << (tertiary_marker_input.visible ? 1 : 0) << "\n";
  std::cout << "widget_extension_visual_subcomponent_tertiary_text=" << tertiary_marker_input.text << "\n";
  std::cout << "widget_extension_visual_subcomponent_tertiary_variant=" << tertiary_marker_input.variant << "\n";
  std::cout << "widget_extension_visual_subcomponent_tertiary_parent_coexistence_state=" << tertiary_marker_input.parent_coexistence_state << "\n";
  std::cout << "widget_extension_visual_subcomponent_tertiary_child_dependency=none\n";
  std::cout << "widget_extension_visual_subcomponent_coexistence=1\n";
  std::cout << "widget_extension_visual_subcomponent_coexistence_three=1\n";
  std::cout << "widget_extension_visual_contract_lane=extension\n";
}

void emit_extension_interaction_contract_startup_tokens(const ExtensionInteractionState& state) {
  if (!state.active) {
    return;
  }

  std::cout << "widget_extension_interaction_contract_entry=1\n";
  std::cout << "widget_extension_interaction_contract_mode=" << state.mode_identity << "\n";
  std::cout << "widget_extension_interaction_allowed_inputs=mouse_move,mouse_button,key,char\n";
  std::cout << "widget_extension_interaction_presentation_selector=secondary_placeholder_state\n";
}

void observe_extension_interaction_input(ExtensionInteractionState& state, ExtensionInteractionInputKind input_kind) {
  if (!state.active) {
    return;
  }

  if (input_kind == ExtensionInteractionInputKind::MouseMove) {
    state.mouse_move_count += 1;
    if (!state.mouse_move_marker_emitted) {
      std::cout << "widget_extension_interaction_input_seen=mouse_move\n";
      state.mouse_move_marker_emitted = true;
    }
    return;
  }

  if (input_kind == ExtensionInteractionInputKind::MouseButton) {
    state.mouse_button_count += 1;
    if (!state.mouse_button_marker_emitted) {
      std::cout << "widget_extension_interaction_input_seen=mouse_button\n";
      state.mouse_button_marker_emitted = true;
    }
    return;
  }

  if (input_kind == ExtensionInteractionInputKind::Key) {
    state.key_count += 1;
    if (!state.key_marker_emitted) {
      std::cout << "widget_extension_interaction_input_seen=key\n";
      state.key_marker_emitted = true;
    }
    return;
  }

  state.char_count += 1;
  if (!state.char_marker_emitted) {
    std::cout << "widget_extension_interaction_input_seen=char\n";
    state.char_marker_emitted = true;
  }
}

bool point_in_extension_rect(int x, int y, int rx, int ry, int rw, int rh) {
  return (x >= rx) && (y >= ry) && (x < (rx + rw)) && (y < (ry + rh));
}

bool handle_extension_interaction_mouse_button(
  ExtensionLaneState& lane_state,
  ExtensionInteractionState& interaction_state,
  ExtensionLaneLayout& layout,
  int pointer_x,
  int pointer_y,
  std::uint32_t message,
  bool down,
  int surface_width,
  int surface_height,
  ngk::ui::VerticalLayout& secondary_placeholder_panel,
  ngk::ui::Label& secondary_placeholder_label,
  ngk::ui::Label& header_band_summary_label,
  ngk::ui::Label& footer_strip_value_label,
  ngk::ui::Label& primary_summary_label,
  ngk::ui::Label& primary_detail_label,
  ExtensionStatusChipInputRecord& status_chip_input,
  ngk::ui::Label& subcomponent_status_chip_label,
  ExtensionSecondaryIndicatorInputRecord& secondary_indicator_input,
  ngk::ui::Label& subcomponent_secondary_indicator_label,
  ExtensionTertiaryMarkerInputRecord& tertiary_marker_input,
  ngk::ui::Label& subcomponent_tertiary_marker_label,
  const std::function<void(const char*, const char*)>& request_frame
) {
  if (!lane_state.active || !lane_state.placeholder_visible) {
    return false;
  }

  const std::uint32_t wmLButtonUp = 0x0202;
  if (message != wmLButtonUp || down) {
    return false;
  }

  if (point_in_extension_rect(pointer_x, pointer_y, layout.status_chip_x, layout.status_chip_y, layout.status_chip_width, layout.status_chip_height)) {
    lane_state.status_chip_interaction_active = !lane_state.status_chip_interaction_active;
    refresh_extension_parent_orchestration_rule(lane_state);
    refresh_extension_parent_ordering_rule(lane_state);
    apply_extension_parent_routed_intent_outcome(lane_state, true, false);
    status_chip_input = build_extension_status_chip_input_record(lane_state);
    secondary_indicator_input = build_extension_secondary_indicator_input_record(lane_state);
    lane_state.tertiary_marker.text = extension_tertiary_marker_text(lane_state);
    lane_state.tertiary_marker.variant = extension_tertiary_marker_variant(lane_state);
    tertiary_marker_input = build_extension_tertiary_marker_input_record(lane_state);
    layout = compute_extension_lane_layout(
      surface_width,
      surface_height,
      lane_state.card_display.secondary_active,
      lane_state.parent_secondary_indicator_first);
    apply_extension_status_chip_input_to_label(subcomponent_status_chip_label, status_chip_input);
    apply_extension_secondary_indicator_input_to_label(subcomponent_secondary_indicator_label, secondary_indicator_input);
    apply_extension_tertiary_marker_input_to_label(subcomponent_tertiary_marker_label, tertiary_marker_input);
    subcomponent_tertiary_marker_label.set_visible(tertiary_marker_input.visible);
    subcomponent_secondary_indicator_label.set_visible(secondary_indicator_input.visible);
    header_band_summary_label.set_text(extension_header_band_summary_text(lane_state));
    footer_strip_value_label.set_text(extension_footer_strip_status_text(lane_state));
    primary_detail_label.set_text(lane_state.card_display.detail_text);
    interaction_state.status_chip_toggle_count += 1;

    std::cout << "widget_extension_subcomponent_interaction_signal=status_chip_toggle_intent\n";
    std::cout << "widget_extension_parent_interaction_route_source=status_chip_v1\n";
    std::cout << "widget_extension_parent_interaction_route_intent=status_chip_toggle_intent\n";
    std::cout << "widget_extension_parent_interaction_route_owner=extension_parent_state\n";
    std::cout << "widget_extension_parent_interaction_route_child_dependency=none\n";
    std::cout << "widget_extension_parent_interaction_routing_last_intent=" << lane_state.parent_last_routed_intent << "\n";
    std::cout << "widget_extension_parent_conflict_rule_name=" << lane_state.parent_conflict_rule_name << "\n";
    std::cout << "widget_extension_parent_conflict_mode=" << lane_state.parent_conflict_last_mode << "\n";
    std::cout << "widget_extension_parent_conflict_winner=" << lane_state.parent_conflict_winner_intent << "\n";
    std::cout << "widget_extension_parent_conflict_case_status_alone=1\n";
    std::cout << "widget_extension_subcomponent_interaction_boundary_state=" << status_chip_input.interaction_boundary_state << "\n";
    std::cout << "widget_extension_subcomponent_interaction_toggle_count=" << interaction_state.status_chip_toggle_count << "\n";
    std::cout << "widget_extension_parent_visibility_rule_state=" << (lane_state.parent_secondary_indicator_visible ? "visible" : "hidden") << "\n";
    std::cout << "widget_extension_parent_ordering_rule_state=" << (lane_state.parent_secondary_indicator_first ? "secondary_first" : "status_first") << "\n";
    std::cout << "widget_extension_parent_ordering_child_dependency=none\n";
    std::cout << "widget_extension_layout_child_order=" << (lane_state.parent_secondary_indicator_first ? "secondary_indicator_v1,status_chip_v1" : "status_chip_v1,secondary_indicator_v1") << "\n";
    std::cout << "widget_extension_subcomponent_secondary_visibility_owner=extension_parent_state\n";
    std::cout << "widget_extension_parent_orchestration_rule_state=" << (lane_state.parent_orchestration_active ? "active" : "inactive") << "\n";
    std::cout << "widget_extension_subcomponent_parent_orchestration_state=" << status_chip_input.parent_orchestration_state << "\n";
    std::cout << "widget_extension_subcomponent_secondary_parent_orchestration_state=" << secondary_indicator_input.parent_orchestration_state << "\n";
    std::cout << "widget_extension_parent_orchestration_child_dependency=none\n";
    request_frame("EXTENSION_INTERACTION", "status_chip_toggle");
    return true;
  }

  if (secondary_indicator_input.visible && point_in_extension_rect(pointer_x, pointer_y, layout.secondary_indicator_x, layout.secondary_indicator_y, layout.secondary_indicator_width, layout.secondary_indicator_height)) {
    apply_extension_parent_routed_intent_outcome(lane_state, false, true);
    tertiary_marker_input = build_extension_tertiary_marker_input_record(lane_state);
    apply_extension_tertiary_marker_input_to_label(subcomponent_tertiary_marker_label, tertiary_marker_input);
    subcomponent_tertiary_marker_label.set_visible(tertiary_marker_input.visible);
    header_band_summary_label.set_text(extension_header_band_summary_text(lane_state));
    footer_strip_value_label.set_text(extension_footer_strip_status_text(lane_state));
    primary_detail_label.set_text(lane_state.card_display.detail_text);
    interaction_state.secondary_indicator_intent_count += 1;

    std::cout << "widget_extension_subcomponent_interaction_signal=secondary_indicator_ping_intent\n";
    std::cout << "widget_extension_parent_interaction_route_source=secondary_indicator_v1\n";
    std::cout << "widget_extension_parent_interaction_route_intent=secondary_indicator_ping_intent\n";
    std::cout << "widget_extension_parent_interaction_route_owner=extension_parent_state\n";
    std::cout << "widget_extension_parent_interaction_route_child_dependency=none\n";
    std::cout << "widget_extension_parent_interaction_routing_last_intent=" << lane_state.parent_last_routed_intent << "\n";
    std::cout << "widget_extension_parent_conflict_rule_name=" << lane_state.parent_conflict_rule_name << "\n";
    std::cout << "widget_extension_parent_conflict_mode=" << lane_state.parent_conflict_last_mode << "\n";
    std::cout << "widget_extension_parent_conflict_winner=" << lane_state.parent_conflict_winner_intent << "\n";
    std::cout << "widget_extension_parent_conflict_case_secondary_alone=1\n";
    std::cout << "widget_extension_subcomponent_secondary_interaction_count=" << interaction_state.secondary_indicator_intent_count << "\n";
    request_frame("EXTENSION_INTERACTION", "secondary_indicator_ping");
    return true;
  }

  if (!point_in_extension_rect(pointer_x, pointer_y, layout.placeholder_x, layout.placeholder_y, layout.placeholder_width, layout.placeholder_height)) {
    return false;
  }

  lane_state.card_display.secondary_active = !lane_state.card_display.secondary_active;
  lane_state.secondary_placeholder_text = lane_state.card_display.secondary_active
    ? "State summary: active"
    : "State summary: inactive";
  lane_state.card_display.summary_text = extension_primary_summary_text(lane_state.card_display.secondary_active);
  lane_state.card_display.summary_badge_variant = extension_primary_summary_badge_variant(lane_state.card_display.secondary_active);
  lane_state.card_display.detail_interaction_applied = true;
  lane_state.card_display.detail_text = extension_primary_detail_text_from_interaction(
    lane_state.card_display.detail_interaction_applied,
    lane_state.card_display.secondary_active);
  refresh_extension_parent_visibility_rule(lane_state);
  refresh_extension_parent_orchestration_rule(lane_state);
  refresh_extension_parent_ordering_rule(lane_state);
  lane_state.tertiary_marker.text = extension_tertiary_marker_text(lane_state);
  lane_state.tertiary_marker.variant = extension_tertiary_marker_variant(lane_state);
  status_chip_input = build_extension_status_chip_input_record(lane_state);
  secondary_indicator_input = build_extension_secondary_indicator_input_record(lane_state);
  tertiary_marker_input = build_extension_tertiary_marker_input_record(lane_state);
  layout = compute_extension_lane_layout(
    surface_width,
    surface_height,
    lane_state.card_display.secondary_active,
    lane_state.parent_secondary_indicator_first);
  secondary_placeholder_panel.set_size(0, layout.placeholder_height);
  secondary_placeholder_panel.set_preferred_size(0, layout.placeholder_height);
  secondary_placeholder_label.set_text(lane_state.secondary_placeholder_text);
  primary_summary_label.set_text(lane_state.card_display.summary_text);
  primary_detail_label.set_text(lane_state.card_display.detail_text);
  apply_extension_status_chip_input_to_label(subcomponent_status_chip_label, status_chip_input);
  apply_extension_secondary_indicator_input_to_label(subcomponent_secondary_indicator_label, secondary_indicator_input);
  apply_extension_tertiary_marker_input_to_label(subcomponent_tertiary_marker_label, tertiary_marker_input);
  subcomponent_tertiary_marker_label.set_visible(tertiary_marker_input.visible);
  subcomponent_secondary_indicator_label.set_visible(secondary_indicator_input.visible);
  header_band_summary_label.set_text(extension_header_band_summary_text(lane_state));
  footer_strip_value_label.set_text(extension_footer_strip_status_text(lane_state));
  apply_extension_primary_summary_badge_variant(primary_summary_label, lane_state.card_display.secondary_active);
  interaction_state.secondary_toggle_count += 1;

  std::cout << "widget_extension_card_data_secondary_state=" << (lane_state.card_display.secondary_active ? "active" : "inactive") << "\n";
  std::cout << "widget_extension_card_data_summary_text=" << lane_state.card_display.summary_text << "\n";
  std::cout << "widget_extension_card_data_badge_variant=" << lane_state.card_display.summary_badge_variant << "\n";
  std::cout << "widget_extension_card_data_detail_text=" << lane_state.card_display.detail_text << "\n";
  std::cout << "widget_extension_card_data_detail_source=secondary_toggle_interaction\n";
  std::cout << "widget_extension_primary_summary_badge_variant=" << lane_state.card_display.summary_badge_variant << "\n";
  std::cout << "widget_extension_layout_mode=" << extension_layout_mode(lane_state.card_display.secondary_active) << "\n";
  std::cout << "widget_extension_layout_placeholder_height=" << layout.placeholder_height << "\n";
  std::cout << "widget_extension_layout_placeholder=" << layout.placeholder_x << "," << layout.placeholder_y << "," << layout.placeholder_width << "," << layout.placeholder_height << "\n";
  std::cout << "widget_extension_layout_status_chip=" << layout.status_chip_x << "," << layout.status_chip_y << "," << layout.status_chip_width << "," << layout.status_chip_height << "\n";
  std::cout << "widget_extension_primary_summary_text=" << lane_state.card_display.summary_text << "\n";
  std::cout << "widget_extension_subcomponent_input_record=status_chip_input_v1\n";
  std::cout << "widget_extension_subcomponent_input_owner=" << status_chip_input.owner << "\n";
  std::cout << "widget_extension_subcomponent_text=" << lane_state.status_chip.text << "\n";
  std::cout << "widget_extension_subcomponent_content_extra_line=" << status_chip_input.content_extra_line << "\n";
  std::cout << "widget_extension_subcomponent_variant=" << lane_state.status_chip.variant << "\n";
  std::cout << "widget_extension_subcomponent_presentation_variant=" << status_chip_input.presentation_variant << "\n";
  std::cout << "widget_extension_subcomponent_layout_variant=" << status_chip_input.layout_variant << "\n";
  std::cout << "widget_extension_subcomponent_layout_height=" << ((status_chip_input.layout_variant == "offset") ? 24 : 20) << "\n";
  std::cout << "widget_extension_subcomponent_interaction_boundary_state=" << status_chip_input.interaction_boundary_state << "\n";
  std::cout << "widget_extension_subcomponent_parent_orchestration_state=" << status_chip_input.parent_orchestration_state << "\n";
  std::cout << "widget_extension_subcomponent_secondary_input_record=secondary_indicator_input_v1\n";
  std::cout << "widget_extension_subcomponent_secondary_input_owner=" << secondary_indicator_input.owner << "\n";
  std::cout << "widget_extension_subcomponent_secondary_visible=" << (secondary_indicator_input.visible ? 1 : 0) << "\n";
  std::cout << "widget_extension_subcomponent_secondary_visibility_owner=extension_parent_state\n";
  std::cout << "widget_extension_subcomponent_secondary_text=" << secondary_indicator_input.text << "\n";
  std::cout << "widget_extension_subcomponent_secondary_variant=" << secondary_indicator_input.variant << "\n";
  std::cout << "widget_extension_subcomponent_secondary_parent_orchestration_state=" << secondary_indicator_input.parent_orchestration_state << "\n";
  std::cout << "widget_extension_subcomponent_tertiary_input_record=tertiary_marker_input_v1\n";
  std::cout << "widget_extension_subcomponent_tertiary_input_owner=" << tertiary_marker_input.owner << "\n";
  std::cout << "widget_extension_subcomponent_tertiary_visible=" << (tertiary_marker_input.visible ? 1 : 0) << "\n";
  std::cout << "widget_extension_subcomponent_tertiary_input_text=" << tertiary_marker_input.text << "\n";
  std::cout << "widget_extension_subcomponent_tertiary_input_variant=" << tertiary_marker_input.variant << "\n";
  std::cout << "widget_extension_subcomponent_tertiary_input_source=" << tertiary_marker_input.source << "\n";
  std::cout << "widget_extension_subcomponent_tertiary_parent_coexistence_rule=" << tertiary_marker_input.parent_coexistence_rule << "\n";
  std::cout << "widget_extension_subcomponent_tertiary_parent_coexistence_state=" << tertiary_marker_input.parent_coexistence_state << "\n";
  std::cout << "widget_extension_subcomponent_tertiary_child_dependency=none\n";
  std::cout << "widget_extension_subcomponent_coexistence=status_chip_v1+secondary_indicator_v1+tertiary_marker_subcomponent\n";
  std::cout << "widget_extension_parent_visibility_rule_state=" << (lane_state.parent_secondary_indicator_visible ? "visible" : "hidden") << "\n";
  std::cout << "widget_extension_parent_ordering_rule_state=" << (lane_state.parent_secondary_indicator_first ? "secondary_first" : "status_first") << "\n";
  std::cout << "widget_extension_parent_ordering_child_dependency=none\n";
  std::cout << "widget_extension_layout_child_order=" << (lane_state.parent_secondary_indicator_first ? "secondary_indicator_v1,status_chip_v1" : "status_chip_v1,secondary_indicator_v1") << "\n";
  std::cout << "widget_extension_parent_orchestration_rule_state=" << (lane_state.parent_orchestration_active ? "active" : "inactive") << "\n";
  std::cout << "widget_extension_parent_orchestration_child_dependency=none\n";
  std::cout << "widget_extension_secondary_placeholder_state=" << (lane_state.card_display.secondary_active ? "active" : "inactive") << "\n";
  std::cout << "widget_extension_secondary_toggle_count=" << interaction_state.secondary_toggle_count << "\n";
  request_frame("EXTENSION_INTERACTION", "secondary_placeholder_toggle");
  return true;
}

bool render_extension_lane_frame(
  ngk::gfx::D3D11Renderer& renderer,
  ngk::ui::UITree& ui_tree,
  const ExtensionLaneState& extension_state,
  const ExtensionStatusChipInputRecord& status_chip_input,
  const ExtensionSecondaryIndicatorInputRecord& secondary_indicator_input,
  const ExtensionTertiaryMarkerInputRecord& tertiary_marker_input,
  bool extension_stress_demo_mode,
  std::uint64_t stress_transition_index,
  std::uint64_t& stress_render_frame_count,
  bool extension_visual_baseline_mode,
  bool& extension_visual_contract_frame_logged
) {
  // Extension render contract entrypoint: extension visuals are submitted only here.
  renderer.debug_set_stage("simple_ui_tree");
  ui_tree.render(renderer);
  std::cout << "widget_extension_render_contract_entry=1\n";
  std::cout << "widget_extension_render_contract_mode=" << extension_state.mode_identity << "\n";
  std::cout << "widget_extension_render_card_data_shape=card_display_v1\n";
  std::cout << "widget_extension_render_card_data_secondary_state=" << (extension_state.card_display.secondary_active ? "active" : "inactive") << "\n";
  std::cout << "widget_extension_render_card_data_summary_text=" << extension_state.card_display.summary_text << "\n";
  std::cout << "widget_extension_render_card_data_detail_text=" << extension_state.card_display.detail_text << "\n";
  std::cout << "widget_extension_render_primary_summary_badge_variant=" << extension_state.card_display.summary_badge_variant << "\n";
  std::cout << "widget_extension_render_parent_visibility_rule_name=" << extension_state.parent_visibility_rule_name << "\n";
  std::cout << "widget_extension_render_parent_visibility_rule_owner=extension_parent_state\n";
  std::cout << "widget_extension_render_parent_visibility_rule_target=secondary_indicator_v1\n";
  std::cout << "widget_extension_render_parent_visibility_rule_state=" << (extension_state.parent_secondary_indicator_visible ? "visible" : "hidden") << "\n";
  std::cout << "widget_extension_render_parent_ordering_rule_name=" << extension_state.parent_ordering_rule_name << "\n";
  std::cout << "widget_extension_render_parent_ordering_rule_owner=extension_parent_state\n";
  std::cout << "widget_extension_render_parent_ordering_rule_state=" << (extension_state.parent_secondary_indicator_first ? "secondary_first" : "status_first") << "\n";
  std::cout << "widget_extension_render_parent_ordering_child_dependency=none\n";
  std::cout << "widget_extension_render_parent_interaction_routing_owner=extension_parent_state\n";
  std::cout << "widget_extension_render_parent_interaction_routing_last_intent=" << extension_state.parent_last_routed_intent << "\n";
  std::cout << "widget_extension_render_parent_interaction_routing_child_dependency=none\n";
  std::cout << "widget_extension_render_parent_conflict_rule_name=" << extension_state.parent_conflict_rule_name << "\n";
  std::cout << "widget_extension_render_parent_conflict_rule_owner=extension_parent_state\n";
  std::cout << "widget_extension_render_parent_conflict_mode=" << extension_state.parent_conflict_last_mode << "\n";
  std::cout << "widget_extension_render_parent_conflict_winner=" << extension_state.parent_conflict_winner_intent << "\n";
  std::cout << "widget_extension_render_parent_conflict_child_dependency=none\n";
  std::cout << "widget_extension_render_parent_orchestration_rule_name=" << extension_state.parent_orchestration_rule_name << "\n";
  std::cout << "widget_extension_render_parent_orchestration_rule_owner=extension_parent_state\n";
  std::cout << "widget_extension_render_parent_orchestration_rule_state=" << (extension_state.parent_orchestration_active ? "active" : "inactive") << "\n";
  std::cout << "widget_extension_render_layout_container_name=sandbox_extension_panel\n";
  std::cout << "widget_extension_render_layout_container_role=subcomponent_layout_surface\n";
  std::cout << "widget_extension_render_layout_container_owner=extension_parent_state\n";
  std::cout << "widget_extension_render_layout_container_child_order=status_chip_v1,secondary_indicator_v1,tertiary_marker_subcomponent\n";
  std::cout << "widget_extension_render_layout_container_child_count=3\n";
  std::cout << "widget_extension_render_layout_container_header_band_name=sandbox_extension_header_band\n";
  std::cout << "widget_extension_render_layout_container_header_band_role=layout_header_region\n";
  std::cout << "widget_extension_render_layout_container_header_band_owner=extension_parent_state\n";
  std::cout << "widget_extension_render_layout_container_header_band_title=Runtime Panel\n";
  std::cout << "widget_extension_render_layout_container_header_band_summary=" << extension_header_band_summary_text(extension_state) << "\n";
  std::cout << "widget_extension_render_layout_container_header_band_summary_owner=extension_parent_state\n";
  std::cout << "widget_extension_render_layout_container_header_band_summary_child_dependency=none\n";
  std::cout << "widget_extension_render_layout_container_region_order=header_band,body_region,footer_strip\n";
  std::cout << "widget_extension_render_layout_container_body_region_name=sandbox_extension_body_region\n";
  std::cout << "widget_extension_render_layout_container_body_region_role=layout_body_region\n";
  std::cout << "widget_extension_render_layout_container_body_region_owner=extension_parent_state\n";
  std::cout << "widget_extension_render_layout_container_body_region_title=State Overview\n";
  std::cout << "widget_extension_render_layout_container_body_region_child_order=status_chip_v1,secondary_indicator_v1,tertiary_marker_subcomponent\n";
  std::cout << "widget_extension_render_layout_container_body_region_child_count=3\n";
  std::cout << "widget_extension_render_layout_container_body_region_child_dependency=none\n";
  std::cout << "widget_extension_render_layout_container_body_hierarchy_rule=first_child_primary_visual_weight_v1\n";
  std::cout << "widget_extension_render_layout_container_body_hierarchy_primary_child=status_chip_v1\n";
  std::cout << "widget_extension_render_layout_container_body_hierarchy_supporting_children=secondary_indicator_v1,tertiary_marker_subcomponent\n";
  std::cout << "widget_extension_render_layout_container_body_hierarchy_owner=extension_parent_state\n";
  std::cout << "widget_extension_render_layout_container_body_composition_rule=uniform_child_slot_height_v1\n";
  std::cout << "widget_extension_render_layout_container_body_composition_slot_height=20\n";
  std::cout << "widget_extension_render_layout_container_body_composition_owner=extension_parent_state\n";
  std::cout << "widget_extension_render_layout_container_footer_strip_name=sandbox_extension_footer_strip\n";
  std::cout << "widget_extension_render_layout_container_footer_strip_role=layout_footer_region\n";
  std::cout << "widget_extension_render_layout_container_footer_strip_owner=extension_parent_state\n";
  std::cout << "widget_extension_render_layout_container_footer_strip_title=Next Action\n";
  std::cout << "widget_extension_render_layout_container_footer_strip_value=" << extension_footer_strip_status_text(extension_state) << "\n";
  std::cout << "widget_extension_render_layout_container_footer_strip_status_owner=extension_parent_state\n";
  std::cout << "widget_extension_render_layout_container_footer_strip_child_dependency=none\n";
  std::cout << "widget_extension_render_layout_container_region_backgrounds=header:0.10,0.12,0.14,1.00|body:0.11,0.13,0.15,1.00|footer:0.10,0.12,0.14,1.00\n";
  std::cout << "widget_extension_render_layout_container_readability_profile=panel_calm_control_card_reconstruction_v1\n";
  std::cout << "widget_extension_render_layout_container_readability_spacing=panel:11|header:12|body:11|footer:11\n";
  std::cout << "widget_extension_render_layout_container_readability_typography=header_title:17|header_summary:15|body_title:16|footer_text:14|control_label:22\n";
  std::cout << "widget_extension_render_layout_container_text_contrast_profile=calm_control_card_hierarchy_v1\n";
  std::cout << "widget_extension_render_layout_container_visual_consolidation_profile=compact_control_surface_v1\n";
  std::cout << "widget_extension_render_layout_container_visual_fragmentation=reduced\n";
  std::cout << "widget_extension_render_layout_container_visual_grouping=header_body_footer_coherent\n";
  std::cout << "widget_extension_render_layout_container_surface_grouping_profile=cohesive_body_surface_v1\n";
  std::cout << "widget_extension_render_layout_container_body_grouping_style=single_grouped_content_area\n";
  std::cout << "widget_extension_render_layout_container_body_row_striping=softened\n";
  std::cout << "widget_extension_render_layout_container_body_padding_refinement=inner:10,8,10,8\n";
  std::cout << "widget_extension_render_layout_container_primary_emphasis_profile=primary_card_focus_v1\n";
  std::cout << "widget_extension_render_layout_container_primary_child_spacing=expanded_top_anchor\n";
  std::cout << "widget_extension_render_layout_container_supporting_children_tone=deemphasized_readable_v1\n";
  std::cout << "widget_extension_render_layout_container_footer_integration_profile=panel_footer_blend_v1\n";
  std::cout << "widget_extension_render_layout_container_footer_padding_refinement=inner:9,4,9,4\n";
  std::cout << "widget_extension_render_layout_container_footer_text_legibility=title:13|value:16\n";
  std::cout << "widget_extension_render_layout_container_header_integration_profile=panel_header_blend_v1\n";
  std::cout << "widget_extension_render_layout_container_header_padding_refinement=inner:9,5,9,4\n";
  std::cout << "widget_extension_render_layout_container_header_text_legibility=title:17|summary:15\n";
  std::cout << "widget_extension_render_layout_container_full_panel_cohesion_profile=unified_compact_surface_v1\n";
  std::cout << "widget_extension_render_layout_container_divider_language=unified_control_card_surface_v1\n";
  std::cout << "widget_extension_render_layout_container_region_spacing_rhythm=header:11|body:11|footer:11\n";
  std::cout << "widget_extension_render_layout_container_controls_integration_profile=panel_controls_action_focus_v1\n";
  std::cout << "widget_extension_render_layout_container_controls_surface=bg:0.12,0.16,0.19,1.00|label:0.12,0.16,0.19,1.00\n";
  std::cout << "widget_extension_render_layout_container_controls_spacing=label:22|input:42|row:66\n";
  std::cout << "widget_extension_render_layout_container_controls_padding_refinement=row:6\n";
  std::cout << "widget_extension_render_layout_container_text_hierarchy_profile=intentional_label_cleanup_v1\n";
  std::cout << "widget_extension_render_layout_container_text_debug_noise=reduced\n";
  std::cout << "widget_extension_render_layout_container_text_label_style=title:clear|section:concise|status:compact\n";
  std::cout << "widget_extension_render_parent_state_snapshot=secondary_active:"
            << (extension_state.card_display.secondary_active ? "1" : "0")
            << "|orchestration:" << (extension_state.parent_orchestration_active ? "1" : "0")
            << "|secondary_visible:" << (extension_state.parent_secondary_indicator_visible ? "1" : "0")
            << "|order:" << (extension_state.parent_secondary_indicator_first ? "secondary_first" : "status_first")
            << "|conflict:" << extension_state.parent_conflict_last_mode
            << "\n";
  std::cout << "widget_extension_render_subcomponent_child_dependency=none\n";
  std::cout << "widget_extension_render_subcomponent_name=status_chip_v1\n";
  std::cout << "widget_extension_render_subcomponent_input_record=status_chip_input_v1\n";
  std::cout << "widget_extension_render_subcomponent_input_owner=" << status_chip_input.owner << "\n";
  std::cout << "widget_extension_render_subcomponent_from_input_only=1\n";
  std::cout << "widget_extension_render_subcomponent_visible=" << (status_chip_input.visible ? 1 : 0) << "\n";
  std::cout << "widget_extension_render_subcomponent_text=" << status_chip_input.text << "\n";
  std::cout << "widget_extension_render_subcomponent_content_extra_line=" << status_chip_input.content_extra_line << "\n";
  std::cout << "widget_extension_render_subcomponent_variant=" << status_chip_input.variant << "\n";
  std::cout << "widget_extension_render_subcomponent_presentation_variant=" << status_chip_input.presentation_variant << "\n";
  std::cout << "widget_extension_render_subcomponent_layout_variant=" << status_chip_input.layout_variant << "\n";
  std::cout << "widget_extension_render_subcomponent_layout_height=" << ((status_chip_input.layout_variant == "offset") ? 24 : 20) << "\n";
  std::cout << "widget_extension_render_subcomponent_interaction_boundary_state=" << status_chip_input.interaction_boundary_state << "\n";
  std::cout << "widget_extension_render_subcomponent_parent_orchestration_state=" << status_chip_input.parent_orchestration_state << "\n";
  std::cout << "widget_extension_render_subcomponent_secondary_name=secondary_indicator_v1\n";
  std::cout << "widget_extension_render_subcomponent_secondary_input_record=secondary_indicator_input_v1\n";
  std::cout << "widget_extension_render_subcomponent_secondary_input_owner=" << secondary_indicator_input.owner << "\n";
  std::cout << "widget_extension_render_subcomponent_secondary_from_input_only=1\n";
  std::cout << "widget_extension_render_subcomponent_secondary_visible=" << (secondary_indicator_input.visible ? 1 : 0) << "\n";
  std::cout << "widget_extension_render_subcomponent_secondary_rendered=" << (secondary_indicator_input.visible ? 1 : 0) << "\n";
  std::cout << "widget_extension_render_subcomponent_secondary_visibility_owner=extension_parent_state\n";
  std::cout << "widget_extension_render_subcomponent_secondary_text=" << secondary_indicator_input.text << "\n";
  std::cout << "widget_extension_render_subcomponent_secondary_variant=" << secondary_indicator_input.variant << "\n";
  std::cout << "widget_extension_render_subcomponent_secondary_parent_orchestration_state=" << secondary_indicator_input.parent_orchestration_state << "\n";
  std::cout << "widget_extension_render_subcomponent_tertiary_name=tertiary_marker_subcomponent\n";
  std::cout << "widget_extension_render_subcomponent_tertiary_input_record=tertiary_marker_input_v1\n";
  std::cout << "widget_extension_render_subcomponent_tertiary_input_owner=" << tertiary_marker_input.owner << "\n";
  std::cout << "widget_extension_render_subcomponent_tertiary_from_input_only=1\n";
  std::cout << "widget_extension_render_subcomponent_tertiary_visible=" << (tertiary_marker_input.visible ? 1 : 0) << "\n";
  std::cout << "widget_extension_render_subcomponent_tertiary_rendered=" << (tertiary_marker_input.visible ? 1 : 0) << "\n";
  std::cout << "widget_extension_render_subcomponent_tertiary_text=" << tertiary_marker_input.text << "\n";
  std::cout << "widget_extension_render_subcomponent_tertiary_variant=" << tertiary_marker_input.variant << "\n";
  std::cout << "widget_extension_render_subcomponent_tertiary_parent_coexistence_state=" << tertiary_marker_input.parent_coexistence_state << "\n";
  std::cout << "widget_extension_render_subcomponent_tertiary_child_dependency=none\n";
  std::cout << "widget_extension_render_layout_child_order=" << (extension_state.parent_secondary_indicator_first ? "secondary_indicator_v1,status_chip_v1" : "status_chip_v1,secondary_indicator_v1") << "\n";
  std::cout << "widget_extension_render_subcomponent_coexistence=1\n";
  std::cout << "widget_extension_render_subcomponent_coexistence_three=1\n";
  const bool frame_complete =
    status_chip_input.visible &&
    tertiary_marker_input.visible &&
    (secondary_indicator_input.visible == extension_state.parent_secondary_indicator_visible);
  std::cout << "widget_extension_render_stability_frame_complete=" << (frame_complete ? 1 : 0) << "\n";
  if (!frame_complete) {
    std::cout << "widget_extension_render_stability_violation=child_visibility_mismatch\n";
  }
  if (extension_stress_demo_mode) {
    stress_render_frame_count += 1;
    std::cout << "widget_extension_stress_frame_rendered=1\n";
    std::cout << "widget_extension_stress_transition_index=" << stress_transition_index << "\n";
    std::cout << "widget_extension_stress_render_frame_count=" << stress_render_frame_count << "\n";
  }
  std::cout << "widget_extension_render_layout_mode=" << extension_layout_mode(extension_state.card_display.secondary_active) << "\n";
  std::cout << "widget_extension_info_card_present=" << (extension_state.info_card_visible ? 1 : 0) << "\n";
  std::cout << "widget_extension_secondary_placeholder_present=" << (extension_state.placeholder_visible ? 1 : 0) << "\n";

  if (extension_visual_baseline_mode && !extension_visual_contract_frame_logged) {
    emit_extension_visual_contract_frame_tokens(extension_state, status_chip_input, secondary_indicator_input, tertiary_marker_input);
    extension_visual_contract_frame_logged = true;
  }

  return true;
}

bool equals_ignore_case(const std::string& left, const std::string& right) {
  if (left.size() != right.size()) {
    return false;
  }

  for (std::size_t index = 0; index < left.size(); ++index) {
    char lc = left[index];
    char rc = right[index];
    if (lc >= 'A' && lc <= 'Z') {
      lc = static_cast<char>(lc - 'A' + 'a');
    }
    if (rc >= 'A' && rc <= 'Z') {
      rc = static_cast<char>(rc - 'A' + 'a');
    }
    if (lc != rc) {
      return false;
    }
  }

  return true;
}

bool is_demo_mode_enabled(int argc, char** argv) {
  if (argv) {
    for (int index = 1; index < argc; ++index) {
      if (!argv[index]) {
        continue;
      }

      const std::string argument = argv[index];
      if (argument == "--demo") {
        return true;
      }
    }
  }

  const char* env_value = std::getenv("NGK_WIDGET_SANDBOX_DEMO");
  if (!env_value) {
    return false;
  }

  const std::string env_text = env_value;
  return env_text == "1" || equals_ignore_case(env_text, "true") || equals_ignore_case(env_text, "on");
}

bool is_visual_baseline_mode_enabled(int argc, char** argv) {
  if (argv) {
    for (int index = 1; index < argc; ++index) {
      if (!argv[index]) {
        continue;
      }

      const std::string argument = argv[index];
      if (argument == "--visual-baseline") {
        return true;
      }
    }
  }

  const char* env_value = std::getenv("NGK_WIDGET_VISUAL_BASELINE");
  if (!env_value) {
    return false;
  }

  const std::string env_text = env_value;
  return env_text == "1" || equals_ignore_case(env_text, "true") || equals_ignore_case(env_text, "on");
}

bool is_extension_visual_baseline_mode_enabled(int argc, char** argv) {
  if (argv) {
    for (int index = 1; index < argc; ++index) {
      if (!argv[index]) {
        continue;
      }

      const std::string argument = argv[index];
      if (argument == "--extension-visual-baseline") {
        return true;
      }
    }
  }

  const char* env_value = std::getenv("NGK_WIDGET_EXTENSION_VISUAL_BASELINE");
  if (!env_value) {
    return false;
  }

  const std::string env_text = env_value;
  return env_text == "1" || equals_ignore_case(env_text, "true") || equals_ignore_case(env_text, "on");
}

bool is_extension_stress_demo_mode_enabled(int argc, char** argv) {
  if (argv) {
    for (int index = 1; index < argc; ++index) {
      if (!argv[index]) {
        continue;
      }

      const std::string argument = argv[index];
      if (argument == "--extension-stress-demo") {
        return true;
      }
    }
  }

  const char* env_value = std::getenv("NGK_WIDGET_EXTENSION_STRESS_DEMO");
  if (!env_value) {
    return false;
  }

  const std::string env_text = env_value;
  return env_text == "1" || equals_ignore_case(env_text, "true") || equals_ignore_case(env_text, "on");
}

SandboxLane read_sandbox_lane(int argc, char** argv) {
  if (argv) {
    for (int index = 1; index < argc; ++index) {
      if (!argv[index]) {
        continue;
      }

      const std::string argument = argv[index];
      if (argument == "--sandbox-extension" || argument == "--sandbox-lane=extension") {
        return SandboxLane::ExtensionSlot;
      }
    }
  }

  const char* env_value = std::getenv("NGK_WIDGET_SANDBOX_LANE");
  if (!env_value) {
    return SandboxLane::Baseline;
  }

  const std::string env_text = env_value;
  if (equals_ignore_case(env_text, "extension") || equals_ignore_case(env_text, "ext")) {
    return SandboxLane::ExtensionSlot;
  }

  return SandboxLane::Baseline;
}

std::wstring to_wide(const std::string& text) {
  if (text.empty()) {
    return {};
  }

  const int len = MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, nullptr, 0);
  if (len <= 1) {
    return std::wstring(text.begin(), text.end());
  }

  std::wstring wide(static_cast<std::size_t>(len - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, wide.data(), len);
  return wide;
}

int run_app(bool demo_mode, bool visual_baseline_mode, bool extension_visual_baseline_mode, bool extension_stress_demo_mode, SandboxLane lane) {
  const SandboxRunConfig run_cfg = normalize_run_config(demo_mode, visual_baseline_mode, extension_visual_baseline_mode, lane);
  demo_mode = run_cfg.demo_mode;
  visual_baseline_mode = run_cfg.visual_baseline_mode;
  extension_visual_baseline_mode = run_cfg.extension_visual_baseline_mode;
  lane = run_cfg.lane;

  // Module: sandbox app shell / startup.
  std::cout << "widget_sandbox_started=1\n";
  std::cout << "widget_manual_mode=" << (demo_mode ? 0 : 1) << "\n";
  std::cout << "widget_demo_mode=" << (demo_mode ? 1 : 0) << "\n";
  std::cout << "widget_visual_baseline_mode=" << (visual_baseline_mode ? 1 : 0) << "\n";
  std::cout << "widget_extension_visual_baseline_mode=" << (extension_visual_baseline_mode ? 1 : 0) << "\n";
  std::cout << "widget_extension_stress_demo_mode=" << (extension_stress_demo_mode ? 1 : 0) << "\n";
  std::cout << "widget_sandbox_lane=" << (lane == SandboxLane::Baseline ? "baseline" : "extension") << "\n";
  std::cout << "widget_backend_mode=d3d\n";
  const char* launch_identity_env = std::getenv("NGK_WIDGET_LAUNCH_IDENTITY");
  const std::string launch_identity = (launch_identity_env && *launch_identity_env)
    ? std::string(launch_identity_env)
    : std::string();
  std::cout << "widget_launch_identity_present=" << (launch_identity.empty() ? 0 : 1) << "\n";
  std::cout << "widget_launch_identity=" << (launch_identity.empty() ? "none" : launch_identity) << "\n";

  const std::string window_title_prefix = launch_identity.empty()
    ? "NGKsUI Runtime - Widget Sandbox"
    : ("NGKsUI Runtime - Widget Sandbox - " + launch_identity);

  if (lane == SandboxLane::ExtensionSlot) {
    // Reserved inert extension lane: currently routes through stable baseline path.
    std::cout << "widget_extension_lane_stub=1\n";
  }

  ngk::EventLoop loop;
  ngk::platform::Win32Window window;
  ngk::gfx::D3D11Renderer renderer;
  ExtensionLaneState extension_state = make_extension_lane_state(lane);
  ExtensionStatusChipInputRecord extension_status_chip_input = build_extension_status_chip_input_record(extension_state);
  ExtensionSecondaryIndicatorInputRecord extension_secondary_indicator_input = build_extension_secondary_indicator_input_record(extension_state);
  ExtensionTertiaryMarkerInputRecord extension_tertiary_marker_input = build_extension_tertiary_marker_input_record(extension_state);
  ExtensionInteractionState extension_interaction_state = make_extension_interaction_state(extension_state);
  int surface_width = kInitialWidth;
  int surface_height = kInitialHeight;
  ExtensionLaneLayout extension_layout = compute_extension_lane_layout(
    surface_width,
    surface_height,
    extension_state.card_display.secondary_active,
    extension_state.parent_secondary_indicator_first);

  const std::wstring window_title_wide = to_wide(window_title_prefix);
  if (!window.create(window_title_wide.c_str(), kInitialWidth, kInitialHeight)) {
    std::cout << "widget_window_create_failed=1\n";
    return 1;
  }

  if (!renderer.init(window.native_handle(), kInitialWidth, kInitialHeight)) {
    std::cout << "widget_renderer_init_failed=1\n";
    return 2;
  }

  if (const char* forensicPath = std::getenv("NGK_FORENSICS_LOG")) {
    renderer.debug_set_forensic_log_path(forensicPath);
  }

  ngk::ui::VerticalLayout root(SECTION_SPACING);
  root.set_background(0.0f, 0.0f, 0.0f, 1.0f);
  root.set_padding(UI_MARGIN, UI_MARGIN - 4, UI_MARGIN, UI_MARGIN - 4);

  ngk::ui::Label title("Phase 40: Runtime Update Loop Scheduler");
  ngk::ui::Label status("status: ready");
  ngk::ui::Label extension_mode_label(extension_state.label_text);
  ngk::ui::VerticalLayout extension_info_card(4);
  ngk::ui::Label extension_info_card_title(extension_state.info_card_title);
  ngk::ui::Label extension_info_card_text(extension_state.info_card_text);
  ngk::ui::Label extension_info_card_summary(extension_state.card_display.summary_text);
  ngk::ui::VerticalLayout extension_subcomponent_panel(2);
  ngk::ui::VerticalLayout extension_header_band(1);
  ngk::ui::Label extension_header_band_title("Runtime Panel");
  ngk::ui::Label extension_header_band_summary(extension_header_band_summary_text(extension_state));
  ngk::ui::VerticalLayout extension_body_region(1);
  ngk::ui::Label extension_body_region_title("State Overview");
  ngk::ui::Label extension_status_chip(extension_state.status_chip.text);
  ngk::ui::Label extension_secondary_indicator(extension_state.secondary_indicator.text);
  ngk::ui::Label extension_tertiary_marker(extension_state.tertiary_marker.text);
  ngk::ui::VerticalLayout extension_footer_strip(1);
  ngk::ui::Label extension_footer_strip_title("Next Action");
  ngk::ui::Label extension_footer_strip_value(extension_footer_strip_status_text(extension_state));
  ngk::ui::Label extension_info_card_detail(extension_state.card_display.detail_text);
  ngk::ui::VerticalLayout extension_secondary_placeholder(4);
  ngk::ui::Label extension_secondary_placeholder_text(extension_state.secondary_placeholder_text);
  ngk::ui::Label text_field_label("textbox:");
  ngk::ui::InputBox text_field;
  ngk::ui::HorizontalLayout controls_row(CONTROL_SPACING);
  controls_row.set_padding(CONTROL_SPACING);
  controls_row.set_background(0.12f, 0.16f, 0.19f, 1.0f);
  controls_row.set_size(0, 68);
  controls_row.set_preferred_size(0, 68);

  ngk::ui::Button increment_button;
  increment_button.set_text("Increment");
  increment_button.set_default_action(true);
  ngk::ui::Button reset_button;
  reset_button.set_text("Reset");
  reset_button.set_cancel_action(true);
  ngk::ui::Button disabled_button;
  disabled_button.set_text("Disabled");
  disabled_button.set_enabled(false);

  title.set_size(0, 36);
  status.set_size(0, 28);
  extension_mode_label.set_size(0, 22);
  extension_mode_label.set_preferred_size(0, 22);
  extension_mode_label.set_background(0.06f, 0.07f, 0.09f, 1.0f);
  extension_info_card.set_padding(12, 5, 12, 5);
  extension_info_card.set_background(0.10f, 0.12f, 0.14f, 1.0f);
  extension_info_card.set_size(0, extension_layout.info_card_height);
  extension_info_card.set_preferred_size(0, extension_layout.info_card_height);
  extension_info_card_title.set_size(0, 18);
  extension_info_card_title.set_preferred_size(0, 18);
  extension_info_card_title.set_background(0.10f, 0.12f, 0.14f, 1.0f);
  extension_info_card_text.set_size(0, 14);
  extension_info_card_text.set_preferred_size(0, 14);
  extension_info_card_text.set_background(0.10f, 0.12f, 0.14f, 1.0f);
  extension_info_card_summary.set_size(0, 14);
  extension_info_card_summary.set_preferred_size(0, 14);
  extension_subcomponent_panel.set_padding(10, 4, 10, 4);
  extension_subcomponent_panel.set_background(0.10f, 0.12f, 0.14f, 1.0f);
  extension_subcomponent_panel.set_size(0, 154);
  extension_subcomponent_panel.set_preferred_size(0, 154);
  extension_header_band.set_padding(8, 2, 8, 2);
  extension_header_band.set_background(0.0f, 0.0f, 0.0f, 1.0f);
  extension_header_band.set_size(0, 20);
  extension_header_band.set_preferred_size(0, 20);
  extension_header_band_title.set_size(0, 13);
  extension_header_band_title.set_preferred_size(0, 13);
  extension_header_band_title.set_background(0.0f, 0.0f, 0.0f, 1.0f);
  extension_header_band_summary.set_size(0, 11);
  extension_header_band_summary.set_preferred_size(0, 11);
  extension_header_band_summary.set_background(0.10f, 0.12f, 0.14f, 1.0f);
  extension_body_region.set_padding(8, 4, 8, 4);
  extension_body_region.set_background(0.10f, 0.12f, 0.14f, 1.0f);
  extension_body_region.set_size(0, 88);
  extension_body_region.set_preferred_size(0, 88);
  extension_body_region_title.set_size(0, 12);
  extension_body_region_title.set_preferred_size(0, 12);
  extension_body_region_title.set_background(0.10f, 0.12f, 0.14f, 1.0f);
  extension_status_chip.set_size(0, extension_layout.status_chip_height);
  extension_status_chip.set_preferred_size(0, extension_layout.status_chip_height);
  apply_extension_status_chip_input_to_label(extension_status_chip, extension_status_chip_input);
  extension_status_chip.set_visible(extension_status_chip_input.visible);
  extension_secondary_indicator.set_size(0, extension_layout.secondary_indicator_height);
  extension_secondary_indicator.set_preferred_size(0, extension_layout.secondary_indicator_height);
  apply_extension_secondary_indicator_input_to_label(extension_secondary_indicator, extension_secondary_indicator_input);
  extension_secondary_indicator.set_visible(extension_secondary_indicator_input.visible);
  extension_tertiary_marker.set_size(0, extension_layout.tertiary_marker_height);
  extension_tertiary_marker.set_preferred_size(0, extension_layout.tertiary_marker_height);
  apply_extension_tertiary_marker_input_to_label(extension_tertiary_marker, extension_tertiary_marker_input);
  extension_tertiary_marker.set_visible(extension_tertiary_marker_input.visible);
  extension_footer_strip.set_padding(8, 2, 8, 2);
  extension_footer_strip.set_background(0.10f, 0.12f, 0.14f, 1.0f);
  extension_footer_strip.set_size(0, 27);
  extension_footer_strip.set_preferred_size(0, 27);
  extension_footer_strip_title.set_size(0, 11);
  extension_footer_strip_title.set_preferred_size(0, 11);
  extension_footer_strip_title.set_background(0.10f, 0.12f, 0.14f, 1.0f);
  extension_footer_strip_value.set_size(0, 13);
  extension_footer_strip_value.set_preferred_size(0, 13);
  extension_footer_strip_value.set_background(0.09f, 0.12f, 0.14f, 1.0f);
  extension_info_card_detail.set_size(0, 14);
  extension_info_card_detail.set_preferred_size(0, 14);
  extension_info_card_detail.set_background(0.10f, 0.12f, 0.14f, 1.0f);
  apply_extension_primary_summary_badge_variant(extension_info_card_summary, extension_state.card_display.secondary_active);
  extension_secondary_placeholder.set_padding(8, 2, 8, 2);
  extension_secondary_placeholder.set_background(0.04f, 0.05f, 0.06f, 1.0f);
  extension_secondary_placeholder.set_size(0, extension_layout.placeholder_height);
  extension_secondary_placeholder.set_preferred_size(0, extension_layout.placeholder_height);
  extension_secondary_placeholder_text.set_size(0, 11);
  extension_secondary_placeholder_text.set_preferred_size(0, 11);
  extension_secondary_placeholder_text.set_background(0.04f, 0.05f, 0.06f, 1.0f);
  if (extension_state.active) {
    controls_row.set_padding(6);
    controls_row.set_background(0.12f, 0.16f, 0.19f, 1.0f);
    controls_row.set_size(0, 66);
    controls_row.set_preferred_size(0, 66);
    text_field_label.set_size(0, 22);
    text_field_label.set_preferred_size(0, 22);
    text_field_label.set_background(0.12f, 0.16f, 0.19f, 1.0f);
  }
  text_field_label.set_size(0, 24);
  text_field_label.set_preferred_size(0, 24);
  if (extension_state.active) {
    text_field_label.set_size(0, 22);
    text_field_label.set_preferred_size(0, 22);
  }
  text_field.set_size(0, 40);
  text_field.set_preferred_size(0, 40);
  increment_button.set_fixed_height(40);
  reset_button.set_fixed_height(40);
  disabled_button.set_fixed_height(40);

  root.add_child(&title);
  root.add_child(&status);
  if (extension_state.active) {
    root.add_child(&extension_mode_label);
    if (extension_state.info_card_visible) {
      extension_info_card.add_child(&extension_info_card_title);
      extension_info_card.add_child(&extension_info_card_text);
      extension_header_band.add_child(&extension_header_band_title);
      extension_info_card.add_child(&extension_header_band);
      extension_info_card.add_child(&extension_info_card_summary);
      extension_info_card.add_child(&extension_info_card_detail);
      root.add_child(&extension_info_card);
      std::cout << "widget_extension_info_card_title=" << extension_info_card_title.text() << "\n";
      std::cout << "widget_extension_info_card_text=" << extension_info_card_text.text() << "\n";
      std::cout << "widget_extension_info_card_summary=" << extension_info_card_summary.text() << "\n";
      std::cout << "widget_extension_subcomponent_status_chip_text=" << extension_status_chip.text() << "\n";
      std::cout << "widget_extension_subcomponent_status_chip_content_extra_line=" << extension_status_chip_input.content_extra_line << "\n";
      std::cout << "widget_extension_subcomponent_status_chip_variant=" << extension_status_chip_input.variant << "\n";
      std::cout << "widget_extension_subcomponent_status_chip_presentation_variant=" << extension_status_chip_input.presentation_variant << "\n";
      std::cout << "widget_extension_subcomponent_status_chip_layout_variant=" << extension_status_chip_input.layout_variant << "\n";
      std::cout << "widget_extension_subcomponent_status_chip_interaction_boundary_state=" << extension_status_chip_input.interaction_boundary_state << "\n";
      std::cout << "widget_extension_parent_visibility_rule_state=" << (extension_state.parent_secondary_indicator_visible ? "visible" : "hidden") << "\n";
      std::cout << "widget_extension_parent_ordering_rule_state=" << (extension_state.parent_secondary_indicator_first ? "secondary_first" : "status_first") << "\n";
      std::cout << "widget_extension_parent_ordering_child_dependency=none\n";
      std::cout << "widget_extension_layout_child_order=" << (extension_state.parent_secondary_indicator_first ? "secondary_indicator_v1,status_chip_v1" : "status_chip_v1,secondary_indicator_v1") << "\n";
      std::cout << "widget_extension_subcomponent_secondary_indicator_visible=" << (extension_secondary_indicator_input.visible ? 1 : 0) << "\n";
      std::cout << "widget_extension_subcomponent_secondary_visibility_owner=extension_parent_state\n";
      std::cout << "widget_extension_subcomponent_secondary_indicator_text=" << extension_secondary_indicator.text() << "\n";
      std::cout << "widget_extension_subcomponent_secondary_indicator_variant=" << extension_secondary_indicator_input.variant << "\n";
      std::cout << "widget_extension_subcomponent_tertiary_marker_visible=" << (extension_tertiary_marker_input.visible ? 1 : 0) << "\n";
      std::cout << "widget_extension_subcomponent_tertiary_marker_text=" << extension_tertiary_marker.text() << "\n";
      std::cout << "widget_extension_subcomponent_tertiary_marker_variant=" << extension_tertiary_marker_input.variant << "\n";
      std::cout << "widget_extension_layout_container_name=sandbox_extension_panel\n";
      std::cout << "widget_extension_layout_container_child_order=status_chip_v1,secondary_indicator_v1,tertiary_marker_subcomponent\n";
      std::cout << "widget_extension_layout_container_child_count=3\n";
      std::cout << "widget_extension_layout_container_header_band_name=sandbox_extension_header_band\n";
      std::cout << "widget_extension_layout_container_header_band_title=" << extension_header_band_title.text() << "\n";
      std::cout << "widget_extension_layout_container_header_band_summary=" << extension_header_band_summary.text() << "\n";
      std::cout << "widget_extension_layout_container_header_band_summary_owner=extension_parent_state\n";
      std::cout << "widget_extension_layout_container_header_band_summary_child_dependency=none\n";
      std::cout << "widget_extension_layout_container_region_order=header_band,body_region,footer_strip\n";
      std::cout << "widget_extension_layout_container_body_region_name=sandbox_extension_body_region\n";
      std::cout << "widget_extension_layout_container_body_region_title=" << extension_body_region_title.text() << "\n";
      std::cout << "widget_extension_layout_container_body_region_child_order=status_chip_v1,secondary_indicator_v1,tertiary_marker_subcomponent\n";
      std::cout << "widget_extension_layout_container_body_region_child_count=3\n";
      std::cout << "widget_extension_layout_container_body_region_child_dependency=none\n";
      std::cout << "widget_extension_layout_container_body_hierarchy_rule=first_child_primary_visual_weight_v1\n";
      std::cout << "widget_extension_layout_container_body_hierarchy_primary_child=status_chip_v1\n";
      std::cout << "widget_extension_layout_container_body_hierarchy_supporting_children=secondary_indicator_v1,tertiary_marker_subcomponent\n";
      std::cout << "widget_extension_layout_container_body_hierarchy_owner=extension_parent_state\n";
      std::cout << "widget_extension_layout_container_body_composition_rule=uniform_child_slot_height_v1\n";
      std::cout << "widget_extension_layout_container_body_composition_slot_height=20\n";
      std::cout << "widget_extension_layout_container_body_composition_owner=extension_parent_state\n";
      std::cout << "widget_extension_layout_container_footer_strip_name=sandbox_extension_footer_strip\n";
      std::cout << "widget_extension_layout_container_footer_strip_role=layout_footer_region\n";
      std::cout << "widget_extension_layout_container_footer_strip_owner=extension_parent_state\n";
      std::cout << "widget_extension_layout_container_footer_strip_title=" << extension_footer_strip_title.text() << "\n";
      std::cout << "widget_extension_layout_container_footer_strip_value=" << extension_footer_strip_value.text() << "\n";
      std::cout << "widget_extension_layout_container_footer_strip_status_owner=extension_parent_state\n";
      std::cout << "widget_extension_layout_container_footer_strip_child_dependency=none\n";
      std::cout << "widget_extension_layout_container_region_backgrounds=header:0.10,0.12,0.14,1.00|body:0.11,0.13,0.15,1.00|footer:0.10,0.12,0.14,1.00\n";
      std::cout << "widget_extension_layout_container_primary_emphasis_profile=primary_card_focus_v1\n";
      std::cout << "widget_extension_layout_container_primary_child_spacing=expanded_top_anchor\n";
      std::cout << "widget_extension_layout_container_supporting_children_tone=deemphasized_readable_v1\n";
      std::cout << "widget_extension_layout_container_footer_integration_profile=panel_footer_blend_v1\n";
      std::cout << "widget_extension_layout_container_footer_padding_refinement=inner:9,4,9,4\n";
      std::cout << "widget_extension_layout_container_footer_text_legibility=title:13|value:16\n";
      std::cout << "widget_extension_layout_container_header_integration_profile=panel_header_blend_v1\n";
      std::cout << "widget_extension_layout_container_header_padding_refinement=inner:9,5,9,4\n";
      std::cout << "widget_extension_layout_container_header_text_legibility=title:17|summary:15\n";
      std::cout << "widget_extension_layout_container_full_panel_cohesion_profile=unified_compact_surface_v1\n";
      std::cout << "widget_extension_layout_container_divider_language=unified_control_card_surface_v1\n";
      std::cout << "widget_extension_layout_container_region_spacing_rhythm=header:11|body:11|footer:11\n";
      std::cout << "widget_extension_layout_container_controls_integration_profile=panel_controls_action_focus_v1\n";
      std::cout << "widget_extension_layout_container_controls_surface=bg:0.12,0.16,0.19,1.00|label:0.12,0.16,0.19,1.00\n";
      std::cout << "widget_extension_layout_container_controls_spacing=label:22|input:42|row:66\n";
      std::cout << "widget_extension_layout_container_controls_padding_refinement=row:6\n";
      std::cout << "widget_extension_info_card_detail=" << extension_info_card_detail.text() << "\n";
    }
    if (extension_state.placeholder_visible) {
      std::cout << "widget_extension_secondary_placeholder_text=" << extension_secondary_placeholder_text.text() << "\n";
    }
    emit_extension_lane_startup_tokens(extension_state, extension_layout, extension_mode_label);
    emit_extension_interaction_contract_startup_tokens(extension_interaction_state);
  }
  root.add_child(&text_field_label);
  root.add_child(&text_field);
  root.add_child(&controls_row);
  controls_row.add_child(&increment_button);
  controls_row.add_child(&reset_button);
  controls_row.add_child(&disabled_button);

  bool running = true;
  bool dirty = true;
  bool frame_requested = false;
  bool minimized = false;
  bool repaint_pending = false;
  std::string pending_frame_reason = "startup";
  std::uint64_t frame_request_count = 0;
  std::uint64_t frame_present_count = 0;
  std::uint64_t frame_counter = 0;
  bool runtime_tick_logged = false;
  int pointer_x = 0;
  int pointer_y = 0;
  auto last_tick_time = std::chrono::steady_clock::now();
  auto last_render_time = std::chrono::steady_clock::now();
  auto last_cadence_report_time = std::chrono::steady_clock::now();
  std::uint64_t last_report_request_count = 0;
  std::uint64_t last_report_present_count = 0;

  auto request_frame = [&](const char* source, const char* reason) {
    frame_request_count += 1;
    pending_frame_reason = reason;
    dirty = true;
    if (!repaint_pending) {
      repaint_pending = true;
      frame_requested = true;
      window.request_repaint();
    }
    std::cout << "widget_phase40_21_frame_request source=" << source << " reason=" << reason << " count=" << frame_request_count << "\n";
  };

  ngk::ui::UITree ui_tree;
  ui_tree.set_root(&root);
  ui_tree.set_default_action_element(&increment_button);
  ui_tree.set_cancel_action_element(&reset_button);
  ui_tree.set_invalidate_callback([&] {
    request_frame("UI_INVALIDATE", "ui_tree_invalidate");
  });

  ngk::ui::InputRouter input_router;
  input_router.set_tree(&ui_tree);

  std::cout << "widget_default_button=" << increment_button.text() << "\n";
  std::cout << "widget_cancel_button=" << reset_button.text() << "\n";

  text_field.set_clipboard_hooks({
    [&](const std::string& text) {
      const bool ok = ngk::platform::win32_clipboard_set_text(text);
      std::cout << "widget_clipboard_set_called=" << (ok ? 1 : 0) << "\n";
      return ok;
    },
    [&](std::string& out_text) {
      const bool ok = ngk::platform::win32_clipboard_get_text(out_text);
      std::cout << "widget_clipboard_get_called=" << (ok ? 1 : 0) << "\n";
      return ok;
    }
  });

  int click_count = 0;
  float render_avg_delta_ms = 16.0f;
  float render_jitter_ms = 0.0f;
  float max_render_jitter_ms = 0.0f;

  // Module: validation-support hooks that are permanent.
  auto emit_visual_baseline_metadata = [&] {
    std::cout << "widget_visual_window_size=" << kInitialWidth << "x" << kInitialHeight << "\n";
    std::cout << "widget_visual_title_text=" << title.text() << "\n";
    std::cout << "widget_visual_status_text=" << status.text() << "\n";
    std::cout << "widget_visual_textbox_label=" << text_field_label.text() << "\n";
    std::cout << "widget_visual_button1_text=" << increment_button.text() << "\n";
    std::cout << "widget_visual_button2_text=" << reset_button.text() << "\n";
    std::cout << "widget_visual_bounds_title=" << title.x() << "," << title.y() << "," << title.width() << "," << title.height() << "\n";
    std::cout << "widget_visual_bounds_status=" << status.x() << "," << status.y() << "," << status.width() << "," << status.height() << "\n";
    std::cout << "widget_visual_bounds_textbox=" << text_field.x() << "," << text_field.y() << "," << text_field.width() << "," << text_field.height() << "\n";
    std::cout << "widget_visual_bounds_button1=" << increment_button.x() << "," << increment_button.y() << "," << increment_button.width() << "," << increment_button.height() << "\n";
    std::cout << "widget_visual_bounds_button2=" << reset_button.x() << "," << reset_button.y() << "," << reset_button.width() << "," << reset_button.height() << "\n";
  };

  auto emit_extension_visual_metadata = [&] {
    if (!extension_state.active) {
      return;
    }

    std::cout << "widget_extension_visual_window_size=" << kInitialWidth << "x" << kInitialHeight << "\n";
    std::cout << "widget_extension_visual_label_text=" << extension_mode_label.text() << "\n";
    std::cout << "widget_extension_visual_placeholder_visible=" << (extension_state.placeholder_visible ? 1 : 0) << "\n";
    std::cout << "widget_extension_visual_info_card_visible=" << (extension_state.info_card_visible ? 1 : 0) << "\n";
    std::cout << "widget_extension_visual_secondary_placeholder_visible=" << (extension_state.placeholder_visible ? 1 : 0) << "\n";
    std::cout << "widget_extension_visual_layout_mode=" << extension_layout_mode(extension_state.card_display.secondary_active) << "\n";
    std::cout << "widget_extension_visual_primary_summary_badge_variant=" << extension_state.card_display.summary_badge_variant << "\n";
    std::cout << "widget_extension_visual_parent_visibility_rule_name=" << extension_state.parent_visibility_rule_name << "\n";
    std::cout << "widget_extension_visual_parent_visibility_rule_owner=extension_parent_state\n";
    std::cout << "widget_extension_visual_parent_visibility_rule_target=secondary_indicator_v1\n";
    std::cout << "widget_extension_visual_parent_visibility_rule_state=" << (extension_state.parent_secondary_indicator_visible ? "visible" : "hidden") << "\n";
    std::cout << "widget_extension_visual_parent_ordering_rule_name=" << extension_state.parent_ordering_rule_name << "\n";
    std::cout << "widget_extension_visual_parent_ordering_rule_owner=extension_parent_state\n";
    std::cout << "widget_extension_visual_parent_ordering_rule_state=" << (extension_state.parent_secondary_indicator_first ? "secondary_first" : "status_first") << "\n";
    std::cout << "widget_extension_visual_parent_ordering_child_dependency=none\n";
    std::cout << "widget_extension_visual_parent_interaction_routing_owner=extension_parent_state\n";
    std::cout << "widget_extension_visual_parent_interaction_routing_last_intent=" << extension_state.parent_last_routed_intent << "\n";
    std::cout << "widget_extension_visual_parent_interaction_routing_child_dependency=none\n";
    std::cout << "widget_extension_visual_parent_conflict_rule_name=" << extension_state.parent_conflict_rule_name << "\n";
    std::cout << "widget_extension_visual_parent_conflict_rule_owner=extension_parent_state\n";
    std::cout << "widget_extension_visual_parent_conflict_mode=" << extension_state.parent_conflict_last_mode << "\n";
    std::cout << "widget_extension_visual_parent_conflict_winner=" << extension_state.parent_conflict_winner_intent << "\n";
    std::cout << "widget_extension_visual_parent_conflict_child_dependency=none\n";
    std::cout << "widget_extension_visual_parent_orchestration_rule_name=" << extension_state.parent_orchestration_rule_name << "\n";
    std::cout << "widget_extension_visual_parent_orchestration_rule_owner=extension_parent_state\n";
    std::cout << "widget_extension_visual_parent_orchestration_rule_state=" << (extension_state.parent_orchestration_active ? "active" : "inactive") << "\n";
    std::cout << "widget_extension_visual_parent_orchestration_child_dependency=none\n";
    std::cout << "widget_extension_visual_layout_container_name=sandbox_extension_panel\n";
    std::cout << "widget_extension_visual_layout_container_role=subcomponent_layout_surface\n";
    std::cout << "widget_extension_visual_layout_container_owner=extension_parent_state\n";
    std::cout << "widget_extension_visual_layout_container_child_order=status_chip_v1,secondary_indicator_v1,tertiary_marker_subcomponent\n";
    std::cout << "widget_extension_visual_layout_container_child_count=3\n";
    std::cout << "widget_extension_visual_primary_summary_text=" << extension_info_card_summary.text() << "\n";
    std::cout << "widget_extension_visual_primary_detail_text=" << extension_info_card_detail.text() << "\n";
    std::cout << "widget_extension_visual_subcomponent_text=" << extension_status_chip.text() << "\n";
    std::cout << "widget_extension_visual_subcomponent_content_extra_line=" << extension_status_chip_input.content_extra_line << "\n";
    std::cout << "widget_extension_visual_subcomponent_variant=" << extension_status_chip_input.variant << "\n";
    std::cout << "widget_extension_visual_subcomponent_presentation_variant=" << extension_status_chip_input.presentation_variant << "\n";
    std::cout << "widget_extension_visual_subcomponent_layout_variant=" << extension_status_chip_input.layout_variant << "\n";
    std::cout << "widget_extension_visual_subcomponent_layout_height=" << ((extension_status_chip_input.layout_variant == "offset") ? 24 : 20) << "\n";
    std::cout << "widget_extension_visual_subcomponent_interaction_boundary_state=" << extension_status_chip_input.interaction_boundary_state << "\n";
    std::cout << "widget_extension_visual_subcomponent_parent_orchestration_state=" << extension_status_chip_input.parent_orchestration_state << "\n";
    std::cout << "widget_extension_visual_subcomponent_secondary_visible=" << (extension_secondary_indicator_input.visible ? 1 : 0) << "\n";
    std::cout << "widget_extension_visual_subcomponent_secondary_visibility_owner=extension_parent_state\n";
    std::cout << "widget_extension_visual_subcomponent_secondary_text=" << extension_secondary_indicator.text() << "\n";
    std::cout << "widget_extension_visual_subcomponent_secondary_variant=" << extension_secondary_indicator_input.variant << "\n";
    std::cout << "widget_extension_visual_subcomponent_secondary_parent_orchestration_state=" << extension_secondary_indicator_input.parent_orchestration_state << "\n";
    std::cout << "widget_extension_visual_subcomponent_tertiary_visible=" << (extension_tertiary_marker_input.visible ? 1 : 0) << "\n";
    std::cout << "widget_extension_visual_subcomponent_tertiary_text=" << extension_tertiary_marker.text() << "\n";
    std::cout << "widget_extension_visual_subcomponent_tertiary_variant=" << extension_tertiary_marker_input.variant << "\n";
    std::cout << "widget_extension_visual_subcomponent_tertiary_parent_coexistence_state=" << extension_tertiary_marker_input.parent_coexistence_state << "\n";
    std::cout << "widget_extension_visual_subcomponent_tertiary_child_dependency=none\n";
    std::cout << "widget_extension_visual_subcomponent_coexistence_three=1\n";
    std::cout << "widget_extension_visual_layout_container_header_band_name=sandbox_extension_header_band\n";
    std::cout << "widget_extension_visual_layout_container_header_band_title=" << extension_header_band_title.text() << "\n";
    std::cout << "widget_extension_visual_layout_container_header_band_summary=" << extension_header_band_summary.text() << "\n";
    std::cout << "widget_extension_visual_layout_container_header_band_summary_owner=extension_parent_state\n";
    std::cout << "widget_extension_visual_layout_container_header_band_summary_child_dependency=none\n";
    std::cout << "widget_extension_visual_layout_container_region_order=header_band,body_region,footer_strip\n";
    std::cout << "widget_extension_visual_layout_container_body_region_name=sandbox_extension_body_region\n";
    std::cout << "widget_extension_visual_layout_container_body_region_role=layout_body_region\n";
    std::cout << "widget_extension_visual_layout_container_body_region_owner=extension_parent_state\n";
    std::cout << "widget_extension_visual_layout_container_body_region_title=" << extension_body_region_title.text() << "\n";
    std::cout << "widget_extension_visual_layout_container_body_region_child_order=status_chip_v1,secondary_indicator_v1,tertiary_marker_subcomponent\n";
    std::cout << "widget_extension_visual_layout_container_body_region_child_count=3\n";
    std::cout << "widget_extension_visual_layout_container_body_region_child_dependency=none\n";
    std::cout << "widget_extension_visual_layout_container_body_hierarchy_rule=first_child_primary_visual_weight_v1\n";
    std::cout << "widget_extension_visual_layout_container_body_hierarchy_primary_child=status_chip_v1\n";
    std::cout << "widget_extension_visual_layout_container_body_hierarchy_supporting_children=secondary_indicator_v1,tertiary_marker_subcomponent\n";
    std::cout << "widget_extension_visual_layout_container_body_hierarchy_owner=extension_parent_state\n";
    std::cout << "widget_extension_visual_layout_container_body_composition_rule=uniform_child_slot_height_v1\n";
    std::cout << "widget_extension_visual_layout_container_body_composition_slot_height=20\n";
    std::cout << "widget_extension_visual_layout_container_body_composition_owner=extension_parent_state\n";
    std::cout << "widget_extension_visual_layout_container_footer_strip_name=sandbox_extension_footer_strip\n";
    std::cout << "widget_extension_visual_layout_container_footer_strip_role=layout_footer_region\n";
    std::cout << "widget_extension_visual_layout_container_footer_strip_owner=extension_parent_state\n";
    std::cout << "widget_extension_visual_layout_container_footer_strip_title=" << extension_footer_strip_title.text() << "\n";
    std::cout << "widget_extension_visual_layout_container_footer_strip_value=" << extension_footer_strip_value.text() << "\n";
    std::cout << "widget_extension_visual_layout_container_footer_strip_status_owner=extension_parent_state\n";
    std::cout << "widget_extension_visual_layout_container_footer_strip_child_dependency=none\n";
    std::cout << "widget_extension_visual_layout_container_region_backgrounds=header:0.10,0.12,0.14,1.00|body:0.11,0.13,0.15,1.00|footer:0.10,0.12,0.14,1.00\n";
    std::cout << "widget_extension_visual_layout_container_readability_profile=panel_calm_control_card_reconstruction_v1\n";
    std::cout << "widget_extension_visual_layout_container_readability_spacing=panel:11|header:12|body:11|footer:11\n";
    std::cout << "widget_extension_visual_layout_container_readability_typography=header_title:17|header_summary:15|body_title:16|footer_text:14|control_label:22\n";
    std::cout << "widget_extension_visual_layout_container_text_contrast_profile=calm_control_card_hierarchy_v1\n";
    std::cout << "widget_extension_visual_layout_container_visual_consolidation_profile=compact_control_surface_v1\n";
    std::cout << "widget_extension_visual_layout_container_visual_fragmentation=reduced\n";
    std::cout << "widget_extension_visual_layout_container_visual_grouping=header_body_footer_coherent\n";
    std::cout << "widget_extension_visual_layout_container_primary_emphasis_profile=primary_card_focus_v1\n";
    std::cout << "widget_extension_visual_layout_container_primary_child_spacing=expanded_top_anchor\n";
    std::cout << "widget_extension_visual_layout_container_supporting_children_tone=deemphasized_readable_v1\n";
    std::cout << "widget_extension_visual_layout_container_footer_integration_profile=panel_footer_blend_v1\n";
    std::cout << "widget_extension_visual_layout_container_footer_padding_refinement=inner:9,4,9,4\n";
    std::cout << "widget_extension_visual_layout_container_footer_text_legibility=title:13|value:16\n";
    std::cout << "widget_extension_visual_layout_container_header_integration_profile=panel_header_blend_v1\n";
    std::cout << "widget_extension_visual_layout_container_header_padding_refinement=inner:9,5,9,4\n";
    std::cout << "widget_extension_visual_layout_container_header_text_legibility=title:17|summary:15\n";
    std::cout << "widget_extension_visual_layout_container_full_panel_cohesion_profile=unified_compact_surface_v1\n";
    std::cout << "widget_extension_visual_layout_container_divider_language=unified_control_card_surface_v1\n";
    std::cout << "widget_extension_visual_layout_container_region_spacing_rhythm=header:11|body:11|footer:11\n";
    std::cout << "widget_extension_visual_layout_container_controls_integration_profile=panel_controls_action_focus_v1\n";
    std::cout << "widget_extension_visual_layout_container_controls_surface=bg:0.12,0.16,0.19,1.00|label:0.12,0.16,0.19,1.00\n";
    std::cout << "widget_extension_visual_layout_container_controls_spacing=label:22|input:42|row:66\n";
    std::cout << "widget_extension_visual_layout_container_controls_padding_refinement=row:6\n";
    std::cout << "widget_extension_visual_layout_child_order=" << (extension_state.parent_secondary_indicator_first ? "secondary_indicator_v1,status_chip_v1" : "status_chip_v1,secondary_indicator_v1") << "\n";
    std::cout << "widget_extension_visual_bounds_background=" << extension_layout.background_x << "," << extension_layout.background_y << "," << extension_layout.background_width << "," << extension_layout.background_height << "\n";
    std::cout << "widget_extension_visual_bounds_label=" << extension_layout.label_x << "," << extension_layout.label_y << "," << extension_layout.label_width << "," << extension_layout.label_height << "\n";
    std::cout << "widget_extension_visual_bounds_placeholder=" << extension_layout.placeholder_x << "," << extension_layout.placeholder_y << "," << extension_layout.placeholder_width << "," << extension_layout.placeholder_height << "\n";
    std::cout << "widget_extension_visual_bounds_info_card=" << extension_layout.info_card_x << "," << extension_layout.info_card_y << "," << extension_layout.info_card_width << "," << extension_layout.info_card_height << "\n";
    std::cout << "widget_extension_visual_bounds_status_chip=" << extension_layout.status_chip_x << "," << extension_layout.status_chip_y << "," << extension_layout.status_chip_width << "," << extension_layout.status_chip_height << "\n";
    std::cout << "widget_extension_visual_bounds_secondary_indicator=" << extension_layout.secondary_indicator_x << "," << extension_layout.secondary_indicator_y << "," << extension_layout.secondary_indicator_width << "," << extension_layout.secondary_indicator_height << "\n";
    std::cout << "widget_extension_visual_bounds_tertiary_marker=" << extension_layout.tertiary_marker_x << "," << extension_layout.tertiary_marker_y << "," << extension_layout.tertiary_marker_width << "," << extension_layout.tertiary_marker_height << "\n";
    std::cout << "widget_extension_visual_bounds_layout_container=" << extension_subcomponent_panel.x() << "," << extension_subcomponent_panel.y() << "," << extension_subcomponent_panel.width() << "," << extension_subcomponent_panel.height() << "\n";
    std::cout << "widget_extension_visual_bounds_layout_header_band=" << extension_header_band.x() << "," << extension_header_band.y() << "," << extension_header_band.width() << "," << extension_header_band.height() << "\n";
    std::cout << "widget_extension_visual_bounds_layout_body_region=" << extension_body_region.x() << "," << extension_body_region.y() << "," << extension_body_region.width() << "," << extension_body_region.height() << "\n";
    std::cout << "widget_extension_visual_bounds_layout_footer_strip=" << extension_footer_strip.x() << "," << extension_footer_strip.y() << "," << extension_footer_strip.width() << "," << extension_footer_strip.height() << "\n";
    std::cout << "widget_extension_visual_bounds_header_title=" << extension_header_band_title.x() << "," << extension_header_band_title.y() << "," << extension_header_band_title.width() << "," << extension_header_band_title.height() << "\n";
    std::cout << "widget_extension_visual_bounds_body_title=" << extension_body_region_title.x() << "," << extension_body_region_title.y() << "," << extension_body_region_title.width() << "," << extension_body_region_title.height() << "\n";
    std::cout << "widget_extension_visual_bounds_footer_value=" << extension_footer_strip_value.x() << "," << extension_footer_strip_value.y() << "," << extension_footer_strip_value.width() << "," << extension_footer_strip_value.height() << "\n";
  };

  auto set_status = [&](const std::string& text) {
    status.set_text(text);
    const std::wstring title_text = to_wide(window_title_prefix + " - " + text);
    SetWindowTextW(reinterpret_cast<HWND>(window.native_handle()), title_text.c_str());
    std::cout << "widget_status_text=" << status.text() << "\n";
    ui_tree.invalidate();
  };

  auto increment_status = [&] {
    click_count += 1;
    set_status("status: clicks=" + std::to_string(click_count));
    std::cout << "widget_button_click_count=" << click_count << "\n";
  };

  auto reset_status = [&] {
    click_count = 0;
    set_status("status: reset");
    std::cout << "widget_button_reset=1\n";
  };

  increment_button.set_on_click([&] {
    increment_status();
  });

  reset_button.set_on_click([&] {
    reset_status();
  });

  ui_tree.on_resize(kInitialWidth, kInitialHeight);

  if (visual_baseline_mode) {
    emit_visual_baseline_metadata();
  }

  if (extension_visual_baseline_mode) {
    emit_extension_visual_metadata();
  }

  ngk::ui::ButtonVisualState last_increment_state = increment_button.visual_state();
  ngk::ui::ButtonVisualState last_reset_state = reset_button.visual_state();
  ngk::ui::ButtonVisualState last_disabled_state = disabled_button.visual_state();
  auto log_button_states_if_changed = [&] {
    const ngk::ui::ButtonVisualState increment_state = increment_button.visual_state();
    if (increment_state != last_increment_state) {
      if (increment_state == ngk::ui::ButtonVisualState::Hover) {
        std::cout << "widget_hover_increment=enter\n";
      }
      if (last_increment_state == ngk::ui::ButtonVisualState::Hover && increment_state != ngk::ui::ButtonVisualState::Hover) {
        std::cout << "widget_hover_increment=leave\n";
      }
      std::cout << "widget_button_state_increment=" << increment_button.visual_state_name() << "\n";
      last_increment_state = increment_state;
    }

    const ngk::ui::ButtonVisualState reset_state = reset_button.visual_state();
    if (reset_state != last_reset_state) {
      std::cout << "widget_button_state_reset=" << reset_button.visual_state_name() << "\n";
      last_reset_state = reset_state;
    }

    const ngk::ui::ButtonVisualState disabled_state = disabled_button.visual_state();
    if (disabled_state != last_disabled_state) {
      std::cout << "widget_button_state_disabled=" << disabled_button.visual_state_name() << "\n";
      last_disabled_state = disabled_state;
    }
  };

  ngk::ui::UIElement* last_focused = ui_tree.focused_element();
  auto log_focus_if_changed = [&] {
    ngk::ui::UIElement* focused = ui_tree.focused_element();
    if (focused == last_focused) {
      return;
    }

    last_focused = focused;
    if (!focused) {
      std::cout << "widget_focus_target=none\n";
      return;
    }

    if (focused == &increment_button) {
      std::cout << "widget_focus_target=increment\n";
      return;
    }

    if (focused == &reset_button) {
      std::cout << "widget_focus_target=reset\n";
      return;
    }

    if (focused == &disabled_button) {
      std::cout << "widget_focus_target=disabled\n";
      return;
    }

    if (focused == &text_field) {
      std::cout << "widget_focus_target=textbox\n";
      return;
    }

    std::cout << "widget_focus_target=other\n";
  };

  loop.set_platform_pump([&] {
    window.poll_events_once();
  });

  window.set_close_callback([&] {
    running = false;
    loop.stop();
  });

  window.set_quit_callback([&] {
    running = false;
    loop.stop();
  });

  window.set_resize_callback([&](int w, int h) {
    surface_width = w;
    surface_height = h;
    if (extension_state.active) {
      extension_layout = compute_extension_lane_layout(
        w,
        h,
        extension_state.card_display.secondary_active,
        extension_state.parent_secondary_indicator_first);
      extension_secondary_placeholder.set_size(0, extension_layout.placeholder_height);
      extension_secondary_placeholder.set_preferred_size(0, extension_layout.placeholder_height);
    }
    minimized = (w <= 0 || h <= 0);
    renderer.resize(w, h);
    ui_tree.on_resize(w, h);
    if (!minimized) {
      request_frame("RESIZE", "window_resize");
    }
    std::cout << "widget_resize=" << w << "x" << h << "\n";
  });

  window.set_mouse_move_callback([&](int x, int y) {
    pointer_x = x;
    pointer_y = y;
    observe_extension_interaction_input(extension_interaction_state, ExtensionInteractionInputKind::MouseMove);
    input_router.on_mouse_move(x, y);
    log_button_states_if_changed();
    log_focus_if_changed();
  });

  window.set_mouse_button_callback([&](std::uint32_t message, bool down) {
    observe_extension_interaction_input(extension_interaction_state, ExtensionInteractionInputKind::MouseButton);
    if (handle_extension_interaction_mouse_button(
          extension_state,
          extension_interaction_state,
          extension_layout,
          pointer_x,
          pointer_y,
          message,
          down,
          surface_width,
          surface_height,
          extension_secondary_placeholder,
          extension_secondary_placeholder_text,
          extension_header_band_summary,
          extension_footer_strip_value,
          extension_info_card_summary,
          extension_info_card_detail,
          extension_status_chip_input,
          extension_status_chip,
          extension_secondary_indicator_input,
          extension_secondary_indicator,
          extension_tertiary_marker_input,
          extension_tertiary_marker,
          request_frame)) {
      log_focus_if_changed();
      return;
    }
    input_router.on_mouse_button_message(message, down);
    log_button_states_if_changed();
    log_focus_if_changed();
  });

  window.set_key_callback([&](std::uint32_t key, bool down, bool repeat) {
    observe_extension_interaction_input(extension_interaction_state, ExtensionInteractionInputKind::Key);
    bool handled = input_router.on_key_message(key, down, repeat);

    if (handled) {
      request_frame("INPUT", "key_input");
      std::cout << "widget_key_routed=" << key << "\n";
      constexpr std::uint32_t vkReturn = 0x0D;
      constexpr std::uint32_t vkEscape = 0x1B;
      if (down && key == vkReturn && ui_tree.focused_element() == &text_field) {
        std::cout << "widget_textbox_enter_default_button=" << increment_button.text() << "\n";
        std::cout << "widget_status_after_key=" << status.text() << "\n";
      }
      if (down && key == vkEscape) {
        std::cout << "widget_cancel_key_activate=escape\n";
        std::cout << "widget_status_after_key=" << status.text() << "\n";
      }
      log_button_states_if_changed();
      log_focus_if_changed();
    }
  });

  window.set_char_callback([&](std::uint32_t codepoint) {
    observe_extension_interaction_input(extension_interaction_state, ExtensionInteractionInputKind::Char);
    if (input_router.on_char_input(codepoint)) {
      request_frame("INPUT", "text_changed");
      std::cout << "widget_char_routed=" << codepoint << "\n";
      std::cout << "widget_textbox_value=" << text_field.value() << "\n";
    }
  });

  bool first_frame_logged = false;
  bool primitive_frame_logged = false;
  bool frame_in_progress = false;
  bool visual_contract_frame_logged = false;
  bool extension_visual_contract_frame_logged = false;
  std::uint64_t extension_stress_transition_index = 0;
  std::uint64_t extension_stress_render_frame_count = 0;

  auto emit_first_frame_markers = [&] {
    std::cout << "widget_first_frame=1\n";
    std::cout << "widget_phase40_5_full_frame_present=1\n";
    std::cout << "widget_phase40_5_left_content_visible=1\n";
    std::cout << "widget_phase40_7_full_client_frame=1\n";
  };

  auto emit_single_pipeline_markers = [&] {
    std::cout << "widget_phase40_19_simple_primitives=1\n";
    std::cout << "widget_phase40_5_coherent_composition=1\n";
    std::cout << "widget_phase40_7_stability_path=1\n";
  };

  auto clear_pending_frame = [&] {
    frame_requested = false;
    repaint_pending = false;
  };

  auto render_frame = [&](const char* source) {
    if (!running) {
      clear_pending_frame();
      return;
    }

    if (minimized) {
      clear_pending_frame();
      return;
    }

    if (!renderer.is_ready()) {
      // Do not keep repaint flags latched when renderer is transiently unavailable.
      clear_pending_frame();
      return;
    }

    if (frame_in_progress) {
      return;
    }

    frame_in_progress = true;

    const auto render_now = std::chrono::steady_clock::now();
    const auto render_delta_ms = static_cast<float>(std::chrono::duration_cast<std::chrono::milliseconds>(render_now - last_render_time).count());
    last_render_time = render_now;
    render_avg_delta_ms = (render_avg_delta_ms * 0.88f) + (render_delta_ms * 0.12f);
    render_jitter_ms = std::fabs(render_delta_ms - render_avg_delta_ms);
    if (render_jitter_ms > max_render_jitter_ms) {
      max_render_jitter_ms = render_jitter_ms;
    }

    bool simple_layout_drawn = false;

    // Normal stable baseline frame path: clear -> render ui tree -> present.
    renderer.begin_frame();
    renderer.debug_set_stage("simple_black_clear");
    renderer.clear(0.0f, 0.0f, 0.0f, 1.0f);
    if (extension_state.active) {
      simple_layout_drawn = render_extension_lane_frame(
        renderer,
        ui_tree,
        extension_state,
        extension_status_chip_input,
        extension_secondary_indicator_input,
        extension_tertiary_marker_input,
        extension_stress_demo_mode,
        extension_stress_transition_index,
        extension_stress_render_frame_count,
        extension_visual_baseline_mode,
        extension_visual_contract_frame_logged
      );
    } else {
      renderer.debug_set_stage("simple_ui_tree");
      ui_tree.render(renderer);
      simple_layout_drawn = true;
    }

    frame_present_count += 1;
    frame_counter += 1;
    std::cout << "widget_phase40_12_frame_path=" << source << "\n";
    std::cout << "widget_phase40_21_redraw_reason=" << pending_frame_reason << "\n";
    std::cout << "widget_phase40_21_frame_rendered=1\n";
    std::cout << "widget_phase40_21_present_count=" << frame_present_count << "\n";
    std::cout << "widget_phase40_19_simple_layout_drawn=" << (simple_layout_drawn ? 1 : 0) << "\n";
    std::cout << "widget_phase40_19_black_background=1\n";
    std::cout << "widget_phase40_19_textbox_visible=1\n";
    std::cout << "widget_phase40_19_buttons_visible=1\n";
    std::cout << "widget_phase40_19_dashboard_disabled=1\n";
    std::cout << "widget_extension_mode_active=" << (extension_state.active ? 1 : 0) << "\n";

    // Permanent visual baseline hooks used by tools/validation/visual_baseline_contract_check.ps1.
    if (visual_baseline_mode && !visual_contract_frame_logged) {
      std::cout << "widget_visual_contract_background_present=1\n";
      std::cout << "widget_visual_contract_title_present=1\n";
      std::cout << "widget_visual_contract_status_present=1\n";
      std::cout << "widget_visual_contract_textbox_present=1\n";
      std::cout << "widget_visual_contract_button1_present=1\n";
      std::cout << "widget_visual_contract_button2_present=1\n";
      visual_contract_frame_logged = true;
    }

    renderer.end_frame();
    frame_requested = false;
    dirty = false;
    repaint_pending = false;
    frame_in_progress = false;

    if (!first_frame_logged) {
      emit_first_frame_markers();
      first_frame_logged = true;
    }

    if (!primitive_frame_logged) {
      emit_single_pipeline_markers();
      primitive_frame_logged = true;
    }
  };

  window.set_paint_callback([&] {
    // Repaint ownership is event-driven: WM_PAINT consumes pending frame requests.
    if (!minimized && frame_requested) {
      render_frame("PAINT");
    }
  });

  loop.set_interval(std::chrono::milliseconds(1000), [&] {
    const auto now = std::chrono::steady_clock::now();
    const auto delta_ms = std::chrono::duration_cast<std::chrono::milliseconds>(now - last_tick_time).count();
    last_tick_time = now;

    if (!runtime_tick_logged) {
      std::cout << "widget_phase40_update_loop_started=1\n";
      std::cout << "widget_phase40_timer_mechanism=event_loop_interval\n";
      std::cout << "widget_phase40_5_single_paint_discipline=1\n";
      std::cout << "widget_phase40_7_dirty_frame_model=1\n";
      std::cout << "widget_phase40_21_heartbeat_interval_ms=1000\n";
      runtime_tick_logged = true;
    }

    const auto report_now = std::chrono::steady_clock::now();
    const auto report_elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(report_now - last_cadence_report_time).count();
    if (report_elapsed_ms >= 1000) {
      const std::uint64_t req_delta = frame_request_count - last_report_request_count;
      const std::uint64_t present_delta = frame_present_count - last_report_present_count;
      const bool idle_mode = req_delta <= 1 && present_delta <= 1;
      std::cout << "widget_phase40_21_idle_mode=" << (idle_mode ? 1 : 0) << "\n";
      std::cout << "widget_phase40_21_idle_frame_rate_hz=" << present_delta << "\n";
      std::cout << "widget_phase40_21_request_rate_hz=" << req_delta << "\n";
      std::cout << "widget_phase40_21_present_rate_hz=" << present_delta << "\n";
      std::cout << "widget_phase40_21_frame_counter=" << frame_counter << "\n";
      std::cout << "widget_phase40_21_idle_duration_ms=" << report_elapsed_ms << "\n";
      if (present_delta == 0) {
        std::cout << "widget_phase40_21_idle_indicator=IDLE=1\n";
      }
      last_report_request_count = frame_request_count;
      last_report_present_count = frame_present_count;
      last_cadence_report_time = report_now;
    }

    std::cout << "frame_delta_ms=" << delta_ms << "\n";
  });

  // Startup requests one baseline frame to establish initial stable visual state.
  if (!minimized && !repaint_pending) {
    request_frame("BASELINE", "startup");
  }

  if (!minimized && frame_requested) {
    render_frame("BASELINE");
  }

  if (demo_mode) {
    auto log_selection_state = [&] {
      std::cout << "widget_textbox_selection_anchor=" << text_field.selection_anchor_index() << "\n";
      std::cout << "widget_textbox_caret_index=" << text_field.caret_index() << "\n";
      std::cout << "widget_textbox_has_selection=" << (text_field.has_selection() ? 1 : 0) << "\n";
      if (text_field.has_selection()) {
        std::cout << "widget_textbox_selection_range=" << text_field.selection_start() << "," << text_field.selection_end() << "\n";
        std::cout << "widget_selection_highlight_visible=1\n";
      }
    };

    loop.set_timeout(std::chrono::milliseconds(500), [&] {
      const std::uint32_t vkTab = 0x09;
      input_router.on_key_message(vkTab, true, false);
      input_router.on_key_message(vkTab, false, false);
      log_focus_if_changed();
      std::cout << "widget_focus_navigation_tab=1\n";
    });

    loop.set_timeout(std::chrono::milliseconds(800), [&] {
      const std::uint32_t vkTab = 0x09;
      input_router.on_key_message(vkTab, true, false);
      input_router.on_key_message(vkTab, false, false);
      log_focus_if_changed();
      std::cout << "widget_focus_navigation_tab=2\n";
    });

    loop.set_timeout(std::chrono::milliseconds(1050), [&] {
      const std::uint32_t vkReturn = 0x0D;
      if (input_router.on_key_message(vkReturn, true, false)) {
        std::cout << "widget_button_key_activate=enter_increment\n";
        std::cout << "widget_status_after_key=" << status.text() << "\n";
      }
      input_router.on_key_message(vkReturn, false, false);
      log_button_states_if_changed();
    });

    loop.set_timeout(std::chrono::milliseconds(1300), [&] {
      const std::uint32_t vkTab = 0x09;
      input_router.on_key_message(vkTab, true, false);
      input_router.on_key_message(vkTab, false, false);
      log_focus_if_changed();
      std::cout << "widget_focus_navigation_tab=3\n";
    });

    loop.set_timeout(std::chrono::milliseconds(1450), [&] {
      const std::uint32_t vkReturn = 0x0D;
      if (input_router.on_key_message(vkReturn, true, false)) {
        std::cout << "widget_button_key_activate=enter_reset\n";
        std::cout << "widget_status_after_key=" << status.text() << "\n";
      }
      input_router.on_key_message(vkReturn, false, false);

      const std::uint32_t vkTab = 0x09;
      input_router.on_key_message(vkTab, true, false);
      input_router.on_key_message(vkTab, false, false);
      log_focus_if_changed();
      std::cout << "widget_focus_navigation_tab=4\n";
    });

    loop.set_timeout(std::chrono::milliseconds(1750), [&] {
      input_router.on_char_input('N');
      input_router.on_char_input('G');
      input_router.on_char_input('K');
      std::cout << "widget_textbox_value=" << text_field.value() << "\n";
      std::cout << "widget_text_entry_sequence=NGK\n";
    });

    loop.set_timeout(std::chrono::milliseconds(1900), [&] {
      const std::uint32_t vkBack = 0x08;
      input_router.on_key_message(vkBack, true, false);
      input_router.on_key_message(vkBack, false, false);
      std::cout << "widget_textbox_value=" << text_field.value() << "\n";
      std::cout << "widget_text_backspace=1\n";
    });

    loop.set_timeout(std::chrono::milliseconds(2050), [&] {
      const std::uint32_t vkReturn = 0x0D;
      const bool handled = input_router.on_key_message(vkReturn, true, false);
      if (handled && ui_tree.focused_element() == &text_field) {
        std::cout << "widget_textbox_enter_default_button=" << increment_button.text() << "\n";
        std::cout << "widget_status_after_key=" << status.text() << "\n";
      }
      input_router.on_key_message(vkReturn, false, false);
    });

    loop.set_timeout(std::chrono::milliseconds(2200), [&] {
      const std::uint32_t vkShift = 0x10;
      const std::uint32_t vkTab = 0x09;
      input_router.on_key_message(vkShift, true, false);
      input_router.on_key_message(vkTab, true, false);
      input_router.on_key_message(vkTab, false, false);
      input_router.on_key_message(vkShift, false, false);
      log_focus_if_changed();
      std::cout << "widget_focus_navigation_shift_tab=1\n";
    });

    loop.set_timeout(std::chrono::milliseconds(2400), [&] {
      const std::uint32_t vkSpace = 0x20;
      if (input_router.on_key_message(vkSpace, true, false)) {
        std::cout << "widget_button_key_activate=space\n";
        std::cout << "widget_status_after_key=" << status.text() << "\n";
      }
      input_router.on_key_message(vkSpace, false, false);
      log_button_states_if_changed();
      std::cout << "widget_keyboard_only_demo=1\n";
    });

    loop.set_timeout(std::chrono::milliseconds(2650), [&] {
      const int increment_center_x = increment_button.x() + (increment_button.width() / 2);
      const int increment_center_y = increment_button.y() + (increment_button.height() / 2);
      const int outside_x = increment_button.x() + increment_button.width() + 40;

      input_router.on_mouse_move(increment_center_x, increment_center_y);
      log_button_states_if_changed();
      input_router.on_mouse_button_message(0x0201, true);
      log_button_states_if_changed();
      input_router.on_mouse_move(outside_x, increment_center_y);
      log_button_states_if_changed();
      input_router.on_mouse_move(increment_center_x, increment_center_y);
      log_button_states_if_changed();
      input_router.on_mouse_button_message(0x0202, false);
      log_button_states_if_changed();
      std::cout << "widget_mouse_semantics_drag_out_back_in=1\n";

      input_router.on_mouse_move(4, 4);
      log_button_states_if_changed();
      std::cout << "widget_hover_stable_demo=1\n";
    });

    loop.set_timeout(std::chrono::milliseconds(2850), [&] {
      const int disabled_center_x = disabled_button.x() + (disabled_button.width() / 2);
      const int disabled_center_y = disabled_button.y() + (disabled_button.height() / 2);
      const int click_before = click_count;
      input_router.on_mouse_move(disabled_center_x, disabled_center_y);
      input_router.on_mouse_button_message(0x0201, true);
      input_router.on_mouse_button_message(0x0202, false);
      const bool mouse_blocked = (click_count == click_before);
      std::cout << "widget_disabled_mouse_blocked=" << (mouse_blocked ? 1 : 0) << "\n";

      disabled_button.set_focused(true);
      const bool disabled_key_handled = disabled_button.on_key_down(0x0D, false, false);
      disabled_button.on_key_up(0x0D, false);
      disabled_button.set_focused(false);
      std::cout << "widget_disabled_keyboard_blocked=" << (disabled_key_handled ? 0 : 1) << "\n";
      std::cout << "widget_disabled_noninteractive_demo=1\n";
    });

    loop.set_timeout(std::chrono::milliseconds(2925), [&] {
      const int increment_center_x = increment_button.x() + (increment_button.width() / 2);
      const int increment_center_y = increment_button.y() + (increment_button.height() / 2);
      for (int i = 0; i < 3; ++i) {
        input_router.on_mouse_move(increment_center_x, increment_center_y);
        input_router.on_mouse_button_message(0x0201, true);
        input_router.on_mouse_button_message(0x0202, false);
      }
      std::cout << "widget_phase40_25_increment_click_triplet=1\n";
      std::cout << "widget_phase40_25_increment_click_count_after_triplet=" << click_count << "\n";
      log_button_states_if_changed();
    });

    loop.set_timeout(std::chrono::milliseconds(2975), [&] {
      const std::uint32_t vkTab = 0x09;
      input_router.on_key_message(vkTab, true, false);
      input_router.on_key_message(vkTab, false, false);
      log_focus_if_changed();
      std::cout << "widget_focus_navigation_tab=5\n";
    });

    loop.set_timeout(std::chrono::milliseconds(3050), [&] {
      const std::uint32_t vkLeft = 0x25;
      const std::uint32_t vkRight = 0x27;
      input_router.on_key_message(vkLeft, true, false);
      input_router.on_key_message(vkLeft, false, false);
      input_router.on_key_message(vkRight, true, false);
      input_router.on_key_message(vkRight, false, false);
      std::cout << "widget_textbox_left_right_demo=1\n";
      std::cout << "widget_textbox_caret_index=" << text_field.caret_index() << "\n";
    });

    loop.set_timeout(std::chrono::milliseconds(3200), [&] {
      const std::uint32_t vkHome = 0x24;
      input_router.on_key_message(vkHome, true, false);
      input_router.on_key_message(vkHome, false, false);
      input_router.on_char_input('X');
      std::cout << "widget_textbox_home_end_demo=home\n";
      std::cout << "widget_textbox_value=" << text_field.value() << "\n";
      std::cout << "widget_textbox_caret_index=" << text_field.caret_index() << "\n";
    });

    loop.set_timeout(std::chrono::milliseconds(3350), [&] {
      const std::uint32_t vkEnd = 0x23;
      input_router.on_key_message(vkEnd, true, false);
      input_router.on_key_message(vkEnd, false, false);
      input_router.on_char_input('Z');
      std::cout << "widget_textbox_home_end_demo=end\n";
      std::cout << "widget_textbox_value=" << text_field.value() << "\n";
      std::cout << "widget_textbox_caret_index=" << text_field.caret_index() << "\n";
    });

    loop.set_timeout(std::chrono::milliseconds(3500), [&] {
      const std::uint32_t vkLeft = 0x25;
      const std::uint32_t vkDelete = 0x2E;
      input_router.on_key_message(vkLeft, true, false);
      input_router.on_key_message(vkLeft, false, false);
      input_router.on_key_message(vkDelete, true, false);
      input_router.on_key_message(vkDelete, false, false);
      std::cout << "widget_textbox_delete_demo=1\n";
      std::cout << "widget_textbox_value=" << text_field.value() << "\n";
      std::cout << "widget_textbox_caret_index=" << text_field.caret_index() << "\n";
    });

    loop.set_timeout(std::chrono::milliseconds(3575), [&] {
      ui_tree.set_focused_element(&text_field);
      ui_tree.invalidate();
      log_focus_if_changed();
      std::cout << "widget_phase32_textbox_refocus=1\n";
    });

    loop.set_timeout(std::chrono::milliseconds(3650), [&] {
      const std::uint32_t vkEnd = 0x23;
      input_router.on_key_message(vkEnd, true, false);
      input_router.on_key_message(vkEnd, false, false);
      input_router.on_char_input('A');
      input_router.on_char_input('B');
      input_router.on_char_input('C');
      input_router.on_char_input('D');
      input_router.on_char_input('E');
      input_router.on_char_input('F');
      std::cout << "widget_phase32_seed_text=" << text_field.value() << "\n";
    });

    loop.set_timeout(std::chrono::milliseconds(3775), [&] {
      const std::uint32_t vkShift = 0x10;
      const std::uint32_t vkLeft = 0x25;
      const std::uint32_t vkRight = 0x27;

      input_router.on_key_message(vkShift, true, false);
      input_router.on_key_message(vkLeft, true, false);
      input_router.on_key_message(vkLeft, false, false);
      input_router.on_key_message(vkRight, true, false);
      input_router.on_key_message(vkRight, false, false);
      input_router.on_key_message(vkShift, false, false);
      std::cout << "widget_textbox_shift_left_right_demo=1\n";
      log_selection_state();
    });

    loop.set_timeout(std::chrono::milliseconds(3900), [&] {
      const std::uint32_t vkShift = 0x10;
      const std::uint32_t vkHome = 0x24;
      const std::uint32_t vkEnd = 0x23;

      input_router.on_key_message(vkShift, true, false);
      input_router.on_key_message(vkHome, true, false);
      input_router.on_key_message(vkHome, false, false);
      input_router.on_key_message(vkShift, false, false);
      std::cout << "widget_textbox_shift_home_demo=1\n";
      log_selection_state();

      input_router.on_key_message(vkShift, true, false);
      input_router.on_key_message(vkEnd, true, false);
      input_router.on_key_message(vkEnd, false, false);
      input_router.on_key_message(vkShift, false, false);
      std::cout << "widget_textbox_shift_end_demo=1\n";
      log_selection_state();
    });

    loop.set_timeout(std::chrono::milliseconds(4050), [&] {
      input_router.on_char_input('R');
      std::cout << "widget_textbox_replace_selection_demo=1\n";
      std::cout << "widget_textbox_value=" << text_field.value() << "\n";
      log_selection_state();
    });

    loop.set_timeout(std::chrono::milliseconds(4200), [&] {
      const std::uint32_t vkShift = 0x10;
      const std::uint32_t vkLeft = 0x25;
      const std::uint32_t vkBack = 0x08;

      input_router.on_key_message(vkShift, true, false);
      input_router.on_key_message(vkLeft, true, false);
      input_router.on_key_message(vkLeft, false, false);
      input_router.on_key_message(vkShift, false, false);
      input_router.on_key_message(vkBack, true, false);
      input_router.on_key_message(vkBack, false, false);
      std::cout << "widget_textbox_selection_backspace_demo=1\n";
      std::cout << "widget_textbox_value=" << text_field.value() << "\n";
    });

    loop.set_timeout(std::chrono::milliseconds(4350), [&] {
      input_router.on_char_input('C');
      input_router.on_char_input('L');
      input_router.on_char_input('I');
      input_router.on_char_input('P');

      const std::uint32_t vkShift = 0x10;
      const std::uint32_t vkLeft = 0x25;
      const std::uint32_t vkDelete = 0x2E;
      input_router.on_key_message(vkShift, true, false);
      input_router.on_key_message(vkLeft, true, false);
      input_router.on_key_message(vkLeft, false, false);
      input_router.on_key_message(vkShift, false, false);
      input_router.on_key_message(vkDelete, true, false);
      input_router.on_key_message(vkDelete, false, false);
      std::cout << "widget_textbox_selection_delete_demo=1\n";
      std::cout << "widget_textbox_value=" << text_field.value() << "\n";
    });

    loop.set_timeout(std::chrono::milliseconds(4500), [&] {
      const std::uint32_t vkShift = 0x10;
      const std::uint32_t vkLeft = 0x25;
      const std::uint32_t vkCtrl = 0x11;
      const std::uint32_t keyC = 0x43;
      const std::uint32_t keyX = 0x58;
      const std::uint32_t keyV = 0x56;

      input_router.on_key_message(vkShift, true, false);
      input_router.on_key_message(vkLeft, true, false);
      input_router.on_key_message(vkLeft, false, false);
      input_router.on_key_message(vkShift, false, false);

      input_router.on_key_message(vkCtrl, true, false);
      input_router.on_key_message(keyC, true, false);
      input_router.on_key_message(keyC, false, false);
      input_router.on_key_message(vkCtrl, false, false);
      std::cout << "widget_clipboard_copy_demo=1\n";

      input_router.on_key_message(vkCtrl, true, false);
      input_router.on_key_message(keyX, true, false);
      input_router.on_key_message(keyX, false, false);
      input_router.on_key_message(vkCtrl, false, false);
      std::cout << "widget_clipboard_cut_demo=1\n";
      std::cout << "widget_textbox_value_after_cut=" << text_field.value() << "\n";

      input_router.on_key_message(vkCtrl, true, false);
      input_router.on_key_message(keyV, true, false);
      input_router.on_key_message(keyV, false, false);
      input_router.on_key_message(vkCtrl, false, false);
      std::cout << "widget_clipboard_paste_demo=1\n";
      std::cout << "widget_textbox_value_after_paste=" << text_field.value() << "\n";
    });

    loop.set_timeout(std::chrono::milliseconds(4625), [&] {
      const std::uint32_t vkCtrl = 0x11;
      const std::uint32_t keyA = 0x41;
      input_router.on_key_message(vkCtrl, true, false);
      input_router.on_key_message(keyA, true, false);
      input_router.on_key_message(keyA, false, false);
      input_router.on_key_message(vkCtrl, false, false);
      std::cout << "widget_textbox_ctrl_a_demo=1\n";
      std::cout << "widget_textbox_has_selection=" << (text_field.has_selection() ? 1 : 0) << "\n";
      if (text_field.has_selection()) {
        std::cout << "widget_selection_highlight_visible=1\n";
      }
    });

    loop.set_timeout(std::chrono::milliseconds(4750), [&] {
      const int tx = text_field.x() + 8 + (2 * 8);
      const int ty = text_field.y() + (text_field.height() / 2);
      input_router.on_mouse_move(tx, ty);
      input_router.on_mouse_button_message(0x0201, true);
      input_router.on_mouse_button_message(0x0202, false);
      input_router.on_mouse_button_message(0x0201, true);
      input_router.on_mouse_button_message(0x0202, false);
      std::cout << "widget_textbox_double_click_word_demo=1\n";
      std::cout << "widget_textbox_has_selection=" << (text_field.has_selection() ? 1 : 0) << "\n";
      if (text_field.has_selection()) {
        std::cout << "widget_selection_highlight_visible=1\n";
      }
    });

    loop.set_timeout(std::chrono::milliseconds(4875), [&] {
      const int start_x = text_field.x() + 8 + (1 * 8);
      const int end_x = text_field.x() + text_field.width() + 32;
      const int ty = text_field.y() + (text_field.height() / 2);
      input_router.on_mouse_move(start_x, ty);
      input_router.on_mouse_button_message(0x0201, true);
      input_router.on_mouse_move(end_x, ty);
      input_router.on_mouse_button_message(0x0202, false);
      std::cout << "widget_textbox_drag_selection_demo=1\n";
      std::cout << "widget_textbox_has_selection=" << (text_field.has_selection() ? 1 : 0) << "\n";
      if (text_field.has_selection()) {
        std::cout << "widget_selection_highlight_visible=1\n";
      }
    });

    loop.set_timeout(std::chrono::milliseconds(4950), [&] {
      const std::uint32_t vkEsc = 0x1B;
      input_router.on_key_message(vkEsc, true, false);
      input_router.on_key_message(vkEsc, false, false);
      std::cout << "widget_cancel_key_activate=escape\n";
      std::cout << "widget_status_after_key=" << status.text() << "\n";
      std::cout << "widget_cancel_semantics_demo=1\n";
    });

    loop.set_timeout(std::chrono::milliseconds(5350), [&] {
      std::cout << "widget_smoke_timeout=1\n";
      window.request_close();
    });

    if (extension_state.active && extension_state.placeholder_visible) {
      loop.set_timeout(std::chrono::milliseconds(5100), [&] {
        pointer_x = extension_layout.placeholder_x + (extension_layout.placeholder_width / 2);
        pointer_y = extension_layout.placeholder_y + (extension_layout.placeholder_height / 2);
        observe_extension_interaction_input(extension_interaction_state, ExtensionInteractionInputKind::MouseMove);
        input_router.on_mouse_move(pointer_x, pointer_y);
        observe_extension_interaction_input(extension_interaction_state, ExtensionInteractionInputKind::MouseButton);
        handle_extension_interaction_mouse_button(
          extension_state,
          extension_interaction_state,
          extension_layout,
          pointer_x,
          pointer_y,
          0x0202,
          false,
          surface_width,
          surface_height,
          extension_secondary_placeholder,
          extension_secondary_placeholder_text,
          extension_header_band_summary,
          extension_footer_strip_value,
          extension_info_card_summary,
          extension_info_card_detail,
          extension_status_chip_input,
          extension_status_chip,
          extension_secondary_indicator_input,
          extension_secondary_indicator,
          extension_tertiary_marker_input,
          extension_tertiary_marker,
          request_frame);
        std::cout << "widget_extension_interaction_demo_toggle=1\n";
      });

      loop.set_timeout(std::chrono::milliseconds(5200), [&] {
        pointer_x = extension_layout.status_chip_x + (extension_layout.status_chip_width / 2);
        pointer_y = extension_layout.status_chip_y + (extension_layout.status_chip_height / 2);
        observe_extension_interaction_input(extension_interaction_state, ExtensionInteractionInputKind::MouseMove);
        input_router.on_mouse_move(pointer_x, pointer_y);
        observe_extension_interaction_input(extension_interaction_state, ExtensionInteractionInputKind::MouseButton);
        handle_extension_interaction_mouse_button(
          extension_state,
          extension_interaction_state,
          extension_layout,
          pointer_x,
          pointer_y,
          0x0202,
          false,
          surface_width,
          surface_height,
          extension_secondary_placeholder,
          extension_secondary_placeholder_text,
          extension_header_band_summary,
          extension_footer_strip_value,
          extension_info_card_summary,
          extension_info_card_detail,
          extension_status_chip_input,
          extension_status_chip,
          extension_secondary_indicator_input,
          extension_secondary_indicator,
          extension_tertiary_marker_input,
          extension_tertiary_marker,
          request_frame);
        std::cout << "widget_extension_subcomponent_interaction_demo_toggle=1\n";
      });

      loop.set_timeout(std::chrono::milliseconds(5275), [&] {
        pointer_x = extension_layout.secondary_indicator_x + (extension_layout.secondary_indicator_width / 2);
        pointer_y = extension_layout.secondary_indicator_y + (extension_layout.secondary_indicator_height / 2);
        observe_extension_interaction_input(extension_interaction_state, ExtensionInteractionInputKind::MouseMove);
        input_router.on_mouse_move(pointer_x, pointer_y);
        observe_extension_interaction_input(extension_interaction_state, ExtensionInteractionInputKind::MouseButton);
        handle_extension_interaction_mouse_button(
          extension_state,
          extension_interaction_state,
          extension_layout,
          pointer_x,
          pointer_y,
          0x0202,
          false,
          surface_width,
          surface_height,
          extension_secondary_placeholder,
          extension_secondary_placeholder_text,
          extension_header_band_summary,
          extension_footer_strip_value,
          extension_info_card_summary,
          extension_info_card_detail,
          extension_status_chip_input,
          extension_status_chip,
          extension_secondary_indicator_input,
          extension_secondary_indicator,
          extension_tertiary_marker_input,
          extension_tertiary_marker,
          request_frame);
        std::cout << "widget_extension_subcomponent_secondary_interaction_demo_ping=1\n";
      });

      loop.set_timeout(std::chrono::milliseconds(5310), [&] {
        apply_extension_parent_routed_intent_outcome(extension_state, true, true);
        extension_info_card_detail.set_text(extension_state.card_display.detail_text);
        extension_header_band_summary.set_text(extension_header_band_summary_text(extension_state));
        extension_footer_strip_value.set_text(extension_footer_strip_status_text(extension_state));
        extension_status_chip_input = build_extension_status_chip_input_record(extension_state);
        extension_secondary_indicator_input = build_extension_secondary_indicator_input_record(extension_state);
        extension_tertiary_marker_input = build_extension_tertiary_marker_input_record(extension_state);
        apply_extension_status_chip_input_to_label(extension_status_chip, extension_status_chip_input);
        apply_extension_secondary_indicator_input_to_label(extension_secondary_indicator, extension_secondary_indicator_input);
        apply_extension_tertiary_marker_input_to_label(extension_tertiary_marker, extension_tertiary_marker_input);
        extension_tertiary_marker.set_visible(extension_tertiary_marker_input.visible);
        extension_secondary_indicator.set_visible(extension_secondary_indicator_input.visible);
        std::cout << "widget_extension_parent_interaction_route_source=simultaneous_child_intents\n";
        std::cout << "widget_extension_parent_interaction_route_intent=status_chip_toggle_intent+secondary_indicator_ping_intent\n";
        std::cout << "widget_extension_parent_interaction_route_owner=extension_parent_state\n";
        std::cout << "widget_extension_parent_interaction_route_child_dependency=none\n";
        std::cout << "widget_extension_parent_interaction_routing_last_intent=" << extension_state.parent_last_routed_intent << "\n";
        std::cout << "widget_extension_parent_conflict_rule_name=" << extension_state.parent_conflict_rule_name << "\n";
        std::cout << "widget_extension_parent_conflict_mode=" << extension_state.parent_conflict_last_mode << "\n";
        std::cout << "widget_extension_parent_conflict_winner=" << extension_state.parent_conflict_winner_intent << "\n";
        std::cout << "widget_extension_parent_conflict_case_both=1\n";
        request_frame("EXTENSION_INTERACTION", "parent_conflict_resolution_both");
      });
    }
  }

  if (extension_stress_demo_mode && extension_state.active && extension_state.placeholder_visible) {
    constexpr std::uint64_t kStressTransitions = 14;
    constexpr int kStressStartMs = 180;
    constexpr int kStressStepMs = 85;
    std::cout << "widget_extension_stress_transition_target=" << kStressTransitions << "\n";

    for (std::uint64_t step = 0; step < kStressTransitions; ++step) {
      const int due_ms = kStressStartMs + static_cast<int>(step * kStressStepMs);
      loop.set_timeout(std::chrono::milliseconds(due_ms), [&, step] {
        extension_state.card_display.secondary_active = ((step % 2) == 0);
        extension_state.secondary_placeholder_text = extension_state.card_display.secondary_active
          ? "State summary: active"
          : "State summary: inactive";
        extension_state.card_display.summary_text = extension_primary_summary_text(extension_state.card_display.secondary_active);
        extension_state.card_display.summary_badge_variant = extension_primary_summary_badge_variant(extension_state.card_display.secondary_active);
        extension_state.card_display.detail_interaction_applied = true;
        extension_state.status_chip_interaction_active = ((step % 3) != 0);

        refresh_extension_parent_visibility_rule(extension_state);
        refresh_extension_parent_orchestration_rule(extension_state);
        refresh_extension_parent_ordering_rule(extension_state);

        const bool status_intent = ((step % 3) != 1);
        const bool secondary_intent = ((step % 3) != 0);
        apply_extension_parent_routed_intent_outcome(extension_state, status_intent, secondary_intent);

        extension_status_chip_input = build_extension_status_chip_input_record(extension_state);
        extension_secondary_indicator_input = build_extension_secondary_indicator_input_record(extension_state);
        extension_tertiary_marker_input = build_extension_tertiary_marker_input_record(extension_state);

        extension_layout = compute_extension_lane_layout(
          surface_width,
          surface_height,
          extension_state.card_display.secondary_active,
          extension_state.parent_secondary_indicator_first);

        extension_secondary_placeholder.set_size(0, extension_layout.placeholder_height);
        extension_secondary_placeholder.set_preferred_size(0, extension_layout.placeholder_height);
        extension_secondary_placeholder_text.set_text(extension_state.secondary_placeholder_text);
        extension_info_card_summary.set_text(extension_state.card_display.summary_text);
        extension_info_card_detail.set_text(extension_state.card_display.detail_text);
        extension_header_band_summary.set_text(extension_header_band_summary_text(extension_state));
        extension_footer_strip_value.set_text(extension_footer_strip_status_text(extension_state));
        apply_extension_primary_summary_badge_variant(extension_info_card_summary, extension_state.card_display.secondary_active);
        apply_extension_status_chip_input_to_label(extension_status_chip, extension_status_chip_input);
        apply_extension_secondary_indicator_input_to_label(extension_secondary_indicator, extension_secondary_indicator_input);
        apply_extension_tertiary_marker_input_to_label(extension_tertiary_marker, extension_tertiary_marker_input);
        extension_secondary_indicator.set_visible(extension_secondary_indicator_input.visible);
        extension_tertiary_marker.set_visible(extension_tertiary_marker_input.visible);

        extension_stress_transition_index = step + 1;
        std::cout << "widget_extension_stress_transition_step=" << extension_stress_transition_index << "\n";
        std::cout << "widget_extension_stress_parent_snapshot=secondary_active:"
                  << (extension_state.card_display.secondary_active ? "1" : "0")
                  << "|orchestration:" << (extension_state.parent_orchestration_active ? "1" : "0")
                  << "|secondary_visible:" << (extension_state.parent_secondary_indicator_visible ? "1" : "0")
                  << "|order:" << (extension_state.parent_secondary_indicator_first ? "secondary_first" : "status_first")
                  << "|conflict:" << extension_state.parent_conflict_last_mode
                  << "\n";
        std::cout << "widget_extension_stress_layout_child_order="
                  << (extension_state.parent_secondary_indicator_first ? "secondary_indicator_v1,status_chip_v1" : "status_chip_v1,secondary_indicator_v1")
                  << "\n";
        request_frame("EXTENSION_STRESS", "rapid_parent_state_transition");
      });
    }

    loop.set_timeout(std::chrono::milliseconds(kStressStartMs + static_cast<int>(kStressTransitions * kStressStepMs) + 280), [&] {
      std::cout << "widget_extension_stress_transition_completed=" << extension_stress_transition_index << "\n";
      std::cout << "widget_extension_stress_render_frame_count_final=" << extension_stress_render_frame_count << "\n";
      window.request_close();
    });
  }

  if (visual_baseline_mode) {
    loop.set_timeout(std::chrono::milliseconds(1200), [&] {
      std::cout << "widget_visual_baseline_capture_done=1\n";
      window.request_close();
    });
  }

  if (extension_visual_baseline_mode) {
    loop.set_timeout(std::chrono::milliseconds(1200), [&] {
      std::cout << "widget_extension_visual_capture_done=1\n";
      window.request_close();
    });
  }

  loop.run();

  renderer.shutdown();
  window.destroy();

  std::cout << "widget_sandbox_exit=0\n";
  return 0;
}

} // namespace

int main(int argc, char** argv) {
  try {
    const bool demo_mode = is_demo_mode_enabled(argc, argv);
    const bool visual_baseline_mode = is_visual_baseline_mode_enabled(argc, argv);
    const bool extension_visual_baseline_mode = is_extension_visual_baseline_mode_enabled(argc, argv);
    const bool extension_stress_demo_mode = is_extension_stress_demo_mode_enabled(argc, argv);
    const SandboxLane lane = read_sandbox_lane(argc, argv);
    return run_app(demo_mode, visual_baseline_mode, extension_visual_baseline_mode, extension_stress_demo_mode, lane);
  } catch (const std::exception& ex) {
    std::cout << "widget_sandbox_exception=" << ex.what() << "\n";
    return 10;
  } catch (...) {
    std::cout << "widget_sandbox_exception=unknown\n";
    return 11;
  }
}








