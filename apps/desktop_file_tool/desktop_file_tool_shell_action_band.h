#pragma once

#include <algorithm>
#include <cstddef>
#include <filesystem>
#include <functional>
#include <iostream>
#include <sstream>
#include <string>

#include "builder_document.hpp"
#include "button.hpp"
#include "input_box.hpp"
#include "label.hpp"
#include "panel.hpp"
#include "ui_element.hpp"
#include "ui_tree.hpp"
#include "vertical_layout.hpp"

namespace desktop_file_tool {

struct DesktopFileToolShellActionBandBinding {
  ngk::ui::UIElement& root;
  ngk::ui::Panel& shell;
  ngk::ui::VerticalLayout& builder_shell_panel;
  ngk::ui::UITree& tree;
  int& client_w;
  int& client_h;
  int& redraw_invalidate_total_count;
  int& redraw_invalidate_input_count;
  int& redraw_input_redraw_requests;
  int& redraw_invalidate_layout_count;
  int& redraw_invalidate_steady_count;
  std::string& last_action_feedback;
  std::string& preview_visual_feedback_message;
  std::string& preview_visual_feedback_node_id;
  std::string& tree_visual_feedback_node_id;
  ngk::ui::Label& builder_action_feedback_label;
  ngk::ui::Label& builder_preview_interaction_hint_label;
  ngk::ui::Label& builder_export_status_label;
  ngk::ui::Label& path_label;
  ngk::ui::Label& status_label;
  ngk::ui::Label& selected_label;
  ngk::ui::Label& detail_label;
  const std::filesystem::path& scan_root;
  std::string& model_status;
  std::string& model_filter;
  bool& builder_doc_dirty;
  std::size_t& model_selected_index;
  int& model_refresh_count;
  int& model_prev_count;
  int& model_next_count;
  int& model_apply_filter_count;
  bool& model_undefined_state_detected;
  std::function<std::size_t()> entries_size;
  std::function<std::string()> selected_file_name;
  std::function<std::string()> selected_file_size;
  std::function<bool()> reload_entries;
  ngk::ui::InputBox& filter_box;
  std::string& builder_projection_filter_query;
  std::string& last_export_status_code;
  std::string& last_export_reason;
  std::string& last_export_artifact_path;
  const char* export_rule;
  bool& has_last_export_snapshot;
  ngk::ui::builder::BuilderDocument& builder_doc;
  std::string& last_export_snapshot;
  bool& export_snapshot_matches_current_doc;
  ngk::ui::Button& refresh_button;
  ngk::ui::Button& prev_button;
  ngk::ui::Button& next_button;
  ngk::ui::Button& apply_button;
};

inline void sync_desktop_file_tool_label_preferred_height(ngk::ui::Label& label, int extra_padding) {
  int line_count = 1;
  for (char ch : label.text()) {
    if (ch == '\n') {
      line_count += 1;
    }
  }
  label.set_preferred_size(0, std::max(label.min_height(), (line_count * 16) + extra_padding));
}

inline void set_desktop_file_tool_last_action_feedback(
  DesktopFileToolShellActionBandBinding& binding,
  const std::string& message) {
  binding.last_action_feedback = std::string("Action: ") + message;
  binding.builder_action_feedback_label.set_text(binding.last_action_feedback);
  sync_desktop_file_tool_label_preferred_height(binding.builder_action_feedback_label, 18);
}

inline void set_desktop_file_tool_preview_visual_feedback(
  DesktopFileToolShellActionBandBinding& binding,
  const std::string& message,
  const std::string& node_id) {
  binding.preview_visual_feedback_message = message;
  binding.preview_visual_feedback_node_id = node_id;
  binding.builder_preview_interaction_hint_label.set_text(message);
  sync_desktop_file_tool_label_preferred_height(binding.builder_preview_interaction_hint_label, 18);
}

inline void set_desktop_file_tool_tree_visual_feedback(
  DesktopFileToolShellActionBandBinding& binding,
  const std::string& node_id) {
  binding.tree_visual_feedback_node_id = node_id;
}

inline void layout_desktop_file_tool_shell(
  DesktopFileToolShellActionBandBinding& binding,
  int width,
  int height) {
  binding.root.set_position(0, 0);
  binding.root.set_size(width, height);
  binding.shell.set_position(0, 0);
  binding.shell.set_size(width, height);
  binding.builder_shell_panel.set_position(0, 0);
  binding.builder_shell_panel.set_size(width, height);
}

inline void refresh_desktop_file_tool_export_status_surface_label(
  DesktopFileToolShellActionBandBinding& binding) {
  std::ostringstream oss;
  oss << "EXPORT STATUS\n";
  oss << "result=" << binding.last_export_status_code;
  if (!binding.last_export_reason.empty() && binding.last_export_reason != "none") {
    oss << " reason=" << binding.last_export_reason;
  }
  oss << "\n";
  oss << "artifact="
      << (binding.last_export_artifact_path.empty() ? std::string("<none>") : binding.last_export_artifact_path)
      << "\n";
  oss << "rule=" << binding.export_rule << "\n";

  std::string state_text = "no_export_baseline";
  if (binding.has_last_export_snapshot) {
    const std::string serialized_now =
      ngk::ui::builder::serialize_builder_document_deterministic(binding.builder_doc);
    if (serialized_now.empty()) {
      binding.export_snapshot_matches_current_doc = false;
      state_text = "unknown_serialize_failed";
    } else {
      binding.export_snapshot_matches_current_doc = (serialized_now == binding.last_export_snapshot);
      state_text = binding.export_snapshot_matches_current_doc ? "up_to_date" : "stale_since_last_export";
    }
  } else {
    binding.export_snapshot_matches_current_doc = false;
  }

  oss << "state=" << state_text;
  binding.builder_export_status_label.set_text(oss.str());
  sync_desktop_file_tool_label_preferred_height(binding.builder_export_status_label, 18);
}

inline void update_desktop_file_tool_shell_labels(DesktopFileToolShellActionBandBinding& binding) {
  binding.path_label.set_text(std::string("PATH ") + binding.scan_root.string());
  binding.status_label.set_text(
    std::string("STATUS ") + binding.model_status +
    " FILES " + std::to_string(binding.entries_size()) +
    " DOC_DIRTY " + (binding.builder_doc_dirty ? std::string("YES") : std::string("NO")));
  binding.selected_label.set_text(std::string("SELECTED ") + binding.selected_file_name());
  binding.detail_label.set_text(
    std::string("DETAIL BYTES ") + binding.selected_file_size() + " FILTER " + binding.model_filter);
  sync_desktop_file_tool_label_preferred_height(binding.detail_label, 18);
  refresh_desktop_file_tool_export_status_surface_label(binding);
}

inline void request_desktop_file_tool_redraw(
  DesktopFileToolShellActionBandBinding& binding,
  const char* reason,
  bool input_triggered,
  bool layout_triggered) {
  binding.redraw_invalidate_total_count += 1;
  if (input_triggered) {
    binding.redraw_invalidate_input_count += 1;
    binding.redraw_input_redraw_requests += 1;
  }
  if (layout_triggered) {
    binding.redraw_invalidate_layout_count += 1;
  }
  if (!input_triggered && !layout_triggered) {
    binding.redraw_invalidate_steady_count += 1;
  }
  std::cout << "phase101_4_invalidate_request reason=" << reason
            << " input=" << (input_triggered ? 1 : 0)
            << " layout=" << (layout_triggered ? 1 : 0)
            << " total=" << binding.redraw_invalidate_total_count << "\n";
  if (binding.client_w > 0 && binding.client_h > 0) {
    layout_desktop_file_tool_shell(binding, binding.client_w, binding.client_h);
    binding.tree.on_resize(binding.client_w, binding.client_h);
  }
  binding.tree.invalidate();
}

inline void refresh_desktop_file_tool_entries(DesktopFileToolShellActionBandBinding& binding) {
  binding.model_refresh_count += 1;
  binding.model_filter = binding.filter_box.value();
  binding.builder_projection_filter_query = binding.model_filter;
  if (!binding.reload_entries()) {
    binding.model_undefined_state_detected = true;
  }
  update_desktop_file_tool_shell_labels(binding);
  request_desktop_file_tool_redraw(binding, "refresh_entries", false, false);
}

inline void select_desktop_file_tool_prev(DesktopFileToolShellActionBandBinding& binding) {
  binding.model_prev_count += 1;
  const std::size_t count = binding.entries_size();
  if (count > 0) {
    if (binding.model_selected_index == 0) {
      binding.model_selected_index = count - 1;
    } else {
      binding.model_selected_index -= 1;
    }
  }
  update_desktop_file_tool_shell_labels(binding);
  request_desktop_file_tool_redraw(binding, "select_prev", false, false);
}

inline void select_desktop_file_tool_next(DesktopFileToolShellActionBandBinding& binding) {
  binding.model_next_count += 1;
  const std::size_t count = binding.entries_size();
  if (count > 0) {
    binding.model_selected_index = (binding.model_selected_index + 1) % count;
  }
  update_desktop_file_tool_shell_labels(binding);
  request_desktop_file_tool_redraw(binding, "select_next", false, false);
}

inline void apply_desktop_file_tool_filter(DesktopFileToolShellActionBandBinding& binding) {
  binding.model_apply_filter_count += 1;
  binding.model_filter = binding.filter_box.value();
  binding.builder_projection_filter_query = binding.model_filter;
  if (!binding.reload_entries()) {
    binding.model_undefined_state_detected = true;
  }
  update_desktop_file_tool_shell_labels(binding);
  request_desktop_file_tool_redraw(binding, "apply_filter", false, false);
}

inline void wire_desktop_file_tool_shell_action_band(DesktopFileToolShellActionBandBinding& binding) {
  binding.refresh_button.set_on_click([&binding] { refresh_desktop_file_tool_entries(binding); });
  binding.prev_button.set_on_click([&binding] { select_desktop_file_tool_prev(binding); });
  binding.next_button.set_on_click([&binding] { select_desktop_file_tool_next(binding); });
  binding.apply_button.set_on_click([&binding] { apply_desktop_file_tool_filter(binding); });
}

}  // namespace desktop_file_tool