#pragma once

#include <cstddef>
#include <functional>
#include <sstream>
#include <string>
#include <vector>

#include "desktop_file_tool_diagnostics.h"
#include "label.hpp"

namespace desktop_file_tool {

struct PreviewClickSelectBinding {
  std::string& selected_builder_node_id;
  std::string& last_preview_click_select_status_code;
  std::string& last_preview_click_select_reason;
  BuilderPreviewClickSelectDiagnostics& preview_click_select_diag;
  ngk::ui::Label& builder_preview_label;
  std::function<bool(std::vector<PreviewExportParityEntry>&, std::string&)> build_preview_click_hit_entries;
  std::function<bool(const std::string&)> node_exists;
  std::function<bool(const std::string&)> apply_preview_inline_action_commit;
  std::function<void(const std::string&)> set_last_action_feedback;
  std::function<bool()> remap_selection_or_fail;
  std::function<bool()> sync_focus_with_selection_or_fail;
  std::function<bool()> refresh_inspector_or_fail;
  std::function<bool()> refresh_preview_or_fail;
  std::function<bool()> check_cross_surface_sync;
  std::function<void()> refresh_preview_surface_label;
};

class PreviewClickSelectLogic {
 public:
  explicit PreviewClickSelectLogic(PreviewClickSelectBinding& binding) : binding_(binding) {}

  bool apply(int x, int y) {
    binding_.preview_click_select_diag.preview_click_select_present = true;

    (void)x;

    std::vector<PreviewExportParityEntry> entries{};
    std::string map_reason;
    if (!binding_.build_preview_click_hit_entries(entries, map_reason)) {
      binding_.preview_click_select_diag.deterministic_hit_mapping_present = false;
      return fail_click("hit_map_unavailable_" + map_reason);
    }

    binding_.preview_click_select_diag.deterministic_hit_mapping_present = true;

    const std::string preview_text = binding_.builder_preview_label.text();
    const std::string outline_token = "runtime_outline:\n";
    const auto outline_pos = preview_text.find(outline_token);
    if (outline_pos == std::string::npos) {
      return fail_click("runtime_outline_missing");
    }

    int outline_first_line_index = 0;
    for (std::size_t i = 0; i < outline_pos + outline_token.size(); ++i) {
      if (preview_text[i] == '\n') {
        outline_first_line_index += 1;
      }
    }

    constexpr int kPreviewLineHeightPx = 16;
    const int rel_y = y - binding_.builder_preview_label.y();
    if (rel_y < 0) {
      return fail_click("invalid_relative_y");
    }
    const int clicked_line_index = rel_y / kPreviewLineHeightPx;

    std::vector<std::string> preview_lines{};
    {
      std::istringstream line_stream(preview_text);
      std::string line;
      while (std::getline(line_stream, line)) {
        preview_lines.push_back(line);
      }
    }
    if (clicked_line_index >= 0 && static_cast<std::size_t>(clicked_line_index) < preview_lines.size()) {
      const std::string& clicked_line = preview_lines[static_cast<std::size_t>(clicked_line_index)];
      const std::string commit_prefix = "ACTION_COMMIT: ";
      if (clicked_line.rfind(commit_prefix, 0) == 0) {
        const auto action_end = clicked_line.find(' ', commit_prefix.size());
        const std::string action_id = clicked_line.substr(
          commit_prefix.size(),
          (action_end == std::string::npos) ? std::string::npos : action_end - commit_prefix.size());
        if (action_id.empty()) {
          return fail_click("action_commit_missing_id");
        }
        if (!binding_.apply_preview_inline_action_commit || !binding_.apply_preview_inline_action_commit(action_id)) {
          return fail_click("action_commit_failed_" + action_id);
        }
        binding_.last_preview_click_select_status_code = "action_commit";
        binding_.last_preview_click_select_reason = action_id;
        binding_.set_last_action_feedback(std::string("Committed ") + action_id);
        binding_.refresh_preview_surface_label();
        return true;
      }
    }

    const int entry_index = clicked_line_index - outline_first_line_index;
    if (entry_index < 0 || static_cast<std::size_t>(entry_index) >= entries.size()) {
      return fail_click("invalid_hit_area_no_entry");
    }

    const auto& clicked_entry = entries[static_cast<std::size_t>(entry_index)];
    if (clicked_entry.node_id.empty() || !binding_.node_exists(clicked_entry.node_id)) {
      return fail_click("hit_entry_not_resolvable");
    }

    binding_.selected_builder_node_id = clicked_entry.node_id;
    const bool remap_ok = binding_.remap_selection_or_fail();
    const bool focus_ok = binding_.sync_focus_with_selection_or_fail();
    const bool insp_ok = binding_.refresh_inspector_or_fail();
    const bool prev_ok = binding_.refresh_preview_or_fail();
    const bool sync_ok = binding_.check_cross_surface_sync();
    if (!(remap_ok && focus_ok && insp_ok && prev_ok && sync_ok)) {
      return fail_click("selection_coherence_failed_after_click");
    }

    binding_.last_preview_click_select_status_code = "success";
    binding_.last_preview_click_select_reason = "none";
    binding_.set_last_action_feedback(std::string("Selected ") + binding_.selected_builder_node_id);
    binding_.refresh_preview_surface_label();
    return true;
  }

 private:
  bool fail_click(const std::string& reason) {
    binding_.last_preview_click_select_status_code = "rejected";
    binding_.last_preview_click_select_reason = reason.empty() ? std::string("unknown") : reason;
    binding_.refresh_preview_surface_label();
    return false;
  }

  PreviewClickSelectBinding& binding_;
};

}  // namespace desktop_file_tool