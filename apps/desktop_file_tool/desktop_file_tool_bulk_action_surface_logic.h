#pragma once

#include <algorithm>
#include <cstddef>
#include <functional>
#include <sstream>
#include <string>
#include <vector>

#include "builder_document.hpp"
#include "desktop_file_tool_diagnostics.h"

namespace desktop_file_tool {

struct BulkActionSurfaceLogicBinding {
  ngk::ui::builder::BuilderDocument& builder_doc;
  std::string& selected_builder_node_id;
  std::vector<std::string>& multi_selected_node_ids;
  bool& builder_doc_dirty;
  std::vector<CommandHistoryEntry>& undo_history;
  std::vector<CommandHistoryEntry>& redo_stack;
  bool validation_mode;
  bool& builder_debug_mode;
  std::function<void()> sync_multi_selection_with_primary;
  std::function<ngk::ui::builder::BuilderNode*(const std::string&)> find_node_by_id;
  std::function<bool(const std::string&)> node_exists;
  std::function<bool(ngk::ui::builder::BuilderWidgetType)> is_container_widget_type;
  std::function<std::string()> selected_file_name;
  std::function<std::string()> selected_file_size;
  std::function<std::string()> model_status;
  std::function<std::string()> model_filter;
  std::function<std::size_t()> model_entry_count;
  std::function<void(const std::string&)> set_status_label_text;
  std::function<void(const std::string&)> set_selected_label_text;
  std::function<void(const std::string&)> set_detail_label_text;
  std::function<void(bool, bool, const std::string&)> set_delete_button_state;
  std::function<void(bool, bool, const std::string&)> set_insert_container_button_state;
  std::function<void(bool, bool, const std::string&)> set_insert_leaf_button_state;
  std::function<void(bool, bool, const std::string&)> set_reparent_button_state;
  std::function<void(bool, bool, const std::string&)> set_undo_button_state;
  std::function<void(bool, bool, const std::string&)> set_redo_button_state;
  std::function<void(bool, bool, const std::string&)> set_export_button_state;
};

class BulkActionSurfaceLogic {
 public:
  explicit BulkActionSurfaceLogic(BulkActionSurfaceLogicBinding& binding) : binding_(binding) {}

  BulkTextSuffixSelectionCompatibility compute_bulk_text_suffix_selection_compatibility() const {
    BulkTextSuffixSelectionCompatibility state{};
    binding_.sync_multi_selection_with_primary();

    state.selected_count = binding_.multi_selected_node_ids.size();
    state.selection_active = state.selected_count > 1;
    if (!state.selection_active) {
      state.mode = "single_selection";
      state.reason = "requires_multi_selection";
      return state;
    }

    ngk::ui::builder::BuilderWidgetType homogeneous_type = ngk::ui::builder::BuilderWidgetType::Label;
    bool homogeneous_type_set = false;

    for (const auto& node_id : binding_.multi_selected_node_ids) {
      auto* node = binding_.find_node_by_id(node_id);
      if (!node) {
        state.mode = "invalid";
        state.reason = "selected_node_missing_" + node_id;
        return state;
      }
      if (node_id == binding_.builder_doc.root_node_id || node->parent_id.empty()) {
        state.mode = "incompatible";
        state.reason = "protected_source_root_" + node_id;
        return state;
      }
      if (node->container_type == ngk::ui::builder::BuilderContainerType::Shell) {
        state.mode = "incompatible";
        state.reason = "protected_source_shell_" + node_id;
        return state;
      }
      if (!ngk::ui::builder::widget_supports_text_property(node->widget_type)) {
        state.mode = "incompatible";
        state.reason = "non_text_capable_type_" + std::string(ngk::ui::builder::to_string(node->widget_type));
        return state;
      }

      if (!homogeneous_type_set) {
        homogeneous_type = node->widget_type;
        homogeneous_type_set = true;
      } else if (node->widget_type != homogeneous_type) {
        state.mixed = true;
        state.mode = "mixed";
        state.reason = "mixed_widget_types";
        state.widget_type = std::string(ngk::ui::builder::to_string(homogeneous_type));
        return state;
      }
    }

    state.homogeneous = true;
    state.eligible = true;
    state.mode = "homogeneous";
    state.reason = "eligible_for_bulk_text_suffix";
    state.widget_type = std::string(ngk::ui::builder::to_string(homogeneous_type));
    return state;
  }

  BulkActionEligibilityReport compute_bulk_action_eligibility_report() const {
    BulkActionEligibilityReport report{};
    binding_.sync_multi_selection_with_primary();

    const bool multi_selection_active = binding_.multi_selected_node_ids.size() > 1;

    auto add_entry = [&](const std::string& action_id,
                         bool available,
                         const std::string& reason,
                         const std::string& detail) {
      BulkActionEligibilityEntry entry{};
      entry.action_id = action_id;
      entry.available = available;
      entry.reason = reason;
      entry.detail = detail;
      report.entries.push_back(std::move(entry));
    };

    if (!multi_selection_active) {
      add_entry("BULK_DELETE", false, "requires_multi_selection", "selected_count=" + std::to_string(binding_.multi_selected_node_ids.size()));
      add_entry("BULK_MOVE_REPARENT", false, "requires_multi_selection", "selected_count=" + std::to_string(binding_.multi_selected_node_ids.size()));
      add_entry("BULK_PROPERTY_EDIT", false, "requires_multi_selection", "selected_count=" + std::to_string(binding_.multi_selected_node_ids.size()));
      return report;
    }

    {
      auto local_delete_rejection_reason_for_node = [&](const std::string& node_id) -> std::string {
        if (node_id.empty()) {
          return "no_selected_node";
        }

        auto* target = binding_.find_node_by_id(node_id);
        if (!target) {
          return "selected_node_lookup_failed";
        }

        const bool is_root = (node_id == binding_.builder_doc.root_node_id) || target->parent_id.empty();
        const bool shell_critical = target->container_type == ngk::ui::builder::BuilderContainerType::Shell;
        if (is_root) {
          return "protected_root";
        }
        if (shell_critical) {
          return "protected_shell";
        }
        if (target->parent_id.empty() || !binding_.node_exists(target->parent_id)) {
          return "parent_missing_for_delete";
        }
        return "";
      };

      std::string rejection_reason;
      std::vector<std::string> unique_ids{};
      for (const auto& node_id : binding_.multi_selected_node_ids) {
        if (node_id.empty()) {
          continue;
        }
        if (std::find(unique_ids.begin(), unique_ids.end(), node_id) == unique_ids.end()) {
          unique_ids.push_back(node_id);
        }
      }

      std::vector<std::string> delete_targets{};
      if (unique_ids.empty()) {
        rejection_reason = "no_selected_nodes";
      } else {
        for (const auto& node_id : unique_ids) {
          const std::string reason = local_delete_rejection_reason_for_node(node_id);
          if (!reason.empty()) {
            rejection_reason = reason + "_" + node_id;
            break;
          }
        }
      }

      if (rejection_reason.empty()) {
        for (const auto& node_id : unique_ids) {
          bool covered_by_ancestor = false;
          auto* current = binding_.find_node_by_id(node_id);
          while (current && !current->parent_id.empty()) {
            if (std::find(unique_ids.begin(), unique_ids.end(), current->parent_id) != unique_ids.end()) {
              covered_by_ancestor = true;
              break;
            }
            current = binding_.find_node_by_id(current->parent_id);
          }
          if (!covered_by_ancestor) {
            delete_targets.push_back(node_id);
          }
        }
      }

      if (delete_targets.empty()) {
        add_entry("BULK_DELETE", false,
                  rejection_reason.empty() ? std::string("no_eligible_delete_targets") : rejection_reason,
                  "selected_count=" + std::to_string(binding_.multi_selected_node_ids.size()));
      } else {
        add_entry("BULK_DELETE", true, "none", "eligible_targets=" + std::to_string(delete_targets.size()));
      }
    }

    {
      const auto text_state = compute_bulk_text_suffix_selection_compatibility();
      if (text_state.eligible) {
        add_entry("BULK_PROPERTY_EDIT", true, "none",
                  text_state.widget_type.empty() ? std::string("eligible") : std::string("widget_type=") + text_state.widget_type);
      } else {
        add_entry("BULK_PROPERTY_EDIT", false,
                  text_state.reason.empty() ? std::string("ineligible") : text_state.reason,
                  text_state.mode.empty() ? std::string("mode=unknown") : std::string("mode=") + text_state.mode);
      }
    }

    {
      std::string move_reason;
      auto local_is_in_subtree_of = [&](const std::string& node_id, const std::string& ancestor_id) -> bool {
        if (node_id.empty() || ancestor_id.empty()) {
          return false;
        }
        if (node_id == ancestor_id) {
          return true;
        }
        std::vector<std::string> to_visit{ancestor_id};
        for (std::size_t idx = 0; idx < to_visit.size(); ++idx) {
          auto* node = binding_.find_node_by_id(to_visit[idx]);
          if (!node) {
            continue;
          }
          for (const auto& child_id : node->child_ids) {
            if (child_id == node_id) {
              return true;
            }
            to_visit.push_back(child_id);
          }
        }
        return false;
      };

      std::vector<std::string> unique_ids{};
      for (const auto& node_id : binding_.multi_selected_node_ids) {
        if (node_id.empty()) {
          continue;
        }
        if (std::find(unique_ids.begin(), unique_ids.end(), node_id) == unique_ids.end()) {
          unique_ids.push_back(node_id);
        }
      }

      if (unique_ids.empty()) {
        move_reason = "no_selected_nodes";
      }

      for (const auto& node_id : unique_ids) {
        if (!move_reason.empty()) {
          break;
        }
        auto* source_node = binding_.find_node_by_id(node_id);
        if (!source_node) {
          move_reason = "selected_node_lookup_failed_" + node_id;
          break;
        }
        if (node_id == binding_.builder_doc.root_node_id || source_node->parent_id.empty()) {
          move_reason = "protected_source_root_" + node_id;
          break;
        }
        if (source_node->container_type == ngk::ui::builder::BuilderContainerType::Shell) {
          move_reason = "protected_source_shell_" + node_id;
          break;
        }
        if (!binding_.node_exists(source_node->parent_id)) {
          move_reason = "source_parent_missing_" + node_id;
          break;
        }
      }

      std::vector<std::string> normalized_sources{};
      if (move_reason.empty()) {
        for (const auto& node_id : unique_ids) {
          bool covered_by_ancestor = false;
          auto* current = binding_.find_node_by_id(node_id);
          while (current && !current->parent_id.empty()) {
            if (std::find(unique_ids.begin(), unique_ids.end(), current->parent_id) != unique_ids.end()) {
              covered_by_ancestor = true;
              break;
            }
            current = binding_.find_node_by_id(current->parent_id);
          }
          if (!covered_by_ancestor) {
            normalized_sources.push_back(node_id);
          }
        }
        if (normalized_sources.empty()) {
          move_reason = "no_eligible_move_sources";
        }
      }

      std::string candidate_target_id{};
      if (move_reason.empty()) {
        for (const auto& candidate : binding_.builder_doc.nodes) {
          if (candidate.node_id.empty()) {
            continue;
          }
          if (candidate.node_id == binding_.builder_doc.root_node_id) {
            continue;
          }
          if (candidate.container_type == ngk::ui::builder::BuilderContainerType::Shell) {
            continue;
          }
          if (candidate.widget_type != ngk::ui::builder::BuilderWidgetType::VerticalLayout) {
            continue;
          }
          if (std::find(normalized_sources.begin(), normalized_sources.end(), candidate.node_id) != normalized_sources.end()) {
            continue;
          }

          bool candidate_valid = true;
          for (const auto& source_id : normalized_sources) {
            auto* source_node = binding_.find_node_by_id(source_id);
            if (!source_node) {
              candidate_valid = false;
              move_reason = "selected_node_lookup_failed_" + source_id;
              break;
            }
            if (source_node->parent_id == candidate.node_id) {
              candidate_valid = false;
              continue;
            }
            if (local_is_in_subtree_of(candidate.node_id, source_id)) {
              candidate_valid = false;
              continue;
            }
          }

          if (candidate_valid) {
            candidate_target_id = candidate.node_id;
            break;
          }
        }
      }

      if (!candidate_target_id.empty()) {
        add_entry("BULK_MOVE_REPARENT", true, "none", "candidate_target=" + candidate_target_id);
      } else {
        if (move_reason.empty()) {
          move_reason = "no_valid_vertical_layout_target";
        }
        add_entry("BULK_MOVE_REPARENT", false, move_reason,
                  "selected_count=" + std::to_string(binding_.multi_selected_node_ids.size()));
      }
    }

    return report;
  }

  void append_compact_bulk_action_surface(std::ostringstream& oss) const {
    const auto report = compute_bulk_action_eligibility_report();
    std::vector<std::string> available_actions{};
    std::vector<BulkActionEligibilityEntry> blocked_actions{};

    for (const auto& entry : report.entries) {
      if (entry.available) {
        available_actions.push_back(entry.action_id);
      } else {
        blocked_actions.push_back(entry);
      }
    }

    oss << "ACTION_SURFACE: available=" << available_actions.size()
        << " blocked=" << blocked_actions.size() << "\n";

    oss << "AVAILABLE_ACTIONS: ";
    if (available_actions.empty()) {
      oss << "<none>\n";
    } else {
      for (std::size_t idx = 0; idx < available_actions.size(); ++idx) {
        if (idx > 0) {
          oss << ",";
        }
        oss << available_actions[idx];
      }
      oss << "\n";
    }

    oss << "BLOCKED_ACTIONS: ";
    if (blocked_actions.empty()) {
      oss << "<none>\n";
    } else {
      for (std::size_t idx = 0; idx < blocked_actions.size(); ++idx) {
        if (idx > 0) {
          oss << ",";
        }
        oss << blocked_actions[idx].action_id;
      }
      oss << "\n";
    }

    if (blocked_actions.empty()) {
      oss << "BLOCKED_REASONS: <none>\n";
      return;
    }

    oss << "BLOCKED_REASONS:\n";
    for (const auto& blocked : blocked_actions) {
      oss << "  " << blocked.action_id << " -> ";
      if (blocked.reason.empty()) {
        oss << "unspecified";
      } else {
        oss << blocked.reason;
      }
      if (!blocked.detail.empty()) {
        oss << " [" << blocked.detail << "]";
      }
      oss << "\n";
    }
  }

  void refresh_top_action_surface_from_builder_state() const {
    binding_.sync_multi_selection_with_primary();
    const auto report = compute_bulk_action_eligibility_report();

    std::vector<std::string> available_actions{};
    std::vector<std::string> blocked_actions{};
    for (const auto& entry : report.entries) {
      if (entry.available) {
        available_actions.push_back(entry.action_id);
      } else {
        blocked_actions.push_back(entry.action_id);
      }
    }

    auto join_csv = [&](const std::vector<std::string>& values) -> std::string {
      if (values.empty()) {
        return "<none>";
      }
      std::ostringstream joined;
      for (std::size_t idx = 0; idx < values.size(); ++idx) {
        if (idx > 0) {
          joined << ",";
        }
        joined << values[idx];
      }
      return joined.str();
    };

    std::string selected_type_name = "none";
    if (!binding_.selected_builder_node_id.empty()) {
      if (auto* selected_node = binding_.find_node_by_id(binding_.selected_builder_node_id)) {
        selected_type_name = ngk::ui::builder::to_string(selected_node->widget_type);
      }
    }

    if (binding_.validation_mode || binding_.builder_debug_mode) {
      binding_.set_status_label_text(
        std::string("STATUS ") + binding_.model_status() +
        " FILES " + std::to_string(binding_.model_entry_count()) +
        " DOC_DIRTY " + (binding_.builder_doc_dirty ? std::string("YES") : std::string("NO")) +
        "\nTOP_ACTION_SURFACE mode=" + (binding_.multi_selected_node_ids.size() > 1 ? std::string("multi") : std::string("single")) +
        " selected_count=" + std::to_string(binding_.multi_selected_node_ids.size()) +
        " available=" + std::to_string(available_actions.size()) +
        " blocked=" + std::to_string(blocked_actions.size()));
    } else {
      binding_.set_status_label_text(
        std::string("Status: ") + binding_.model_status() +
        " | Document: " + (binding_.builder_doc_dirty ? std::string("Modified") : std::string("Saved")) +
        " | Nodes: " + std::to_string(binding_.builder_doc.nodes.size()));
    }

    if (binding_.validation_mode || binding_.builder_debug_mode) {
      binding_.set_selected_label_text(
        std::string("SELECTED ") + binding_.selected_file_name() +
        "\nNODE " + (binding_.selected_builder_node_id.empty() ? std::string("none") : binding_.selected_builder_node_id) +
        " type=" + selected_type_name);
    } else {
      binding_.set_selected_label_text(
        std::string("Node: ") + (binding_.selected_builder_node_id.empty() ? std::string("none") : binding_.selected_builder_node_id) +
        " (" + selected_type_name + ")");
    }

    if (binding_.validation_mode || binding_.builder_debug_mode) {
      binding_.set_detail_label_text(
        std::string("DETAIL BYTES ") + binding_.selected_file_size() +
        " FILTER " + binding_.model_filter() +
        "\nTOP_AVAILABLE " + join_csv(available_actions) +
        "\nTOP_BLOCKED " + join_csv(blocked_actions));
    } else {
      binding_.set_detail_label_text(
        std::string("Hint: Click a tree row, then use Add Container or Add Item."));
    }
  }

  void refresh_action_button_visual_state_from_builder_truth() const {
    binding_.sync_multi_selection_with_primary();
    const auto report = compute_bulk_action_eligibility_report();

    auto find_entry = [&](const std::string& action_id) -> const BulkActionEligibilityEntry* {
      for (const auto& entry : report.entries) {
        if (entry.action_id == action_id) {
          return &entry;
        }
      }
      return nullptr;
    };

    const bool multi_mode = binding_.multi_selected_node_ids.size() > 1;
    const auto* bulk_delete = find_entry("BULK_DELETE");
    const auto* bulk_move = find_entry("BULK_MOVE_REPARENT");

    bool single_delete_available = false;
    if (!binding_.selected_builder_node_id.empty()) {
      if (auto* selected = binding_.find_node_by_id(binding_.selected_builder_node_id)) {
        const bool is_root = binding_.selected_builder_node_id == binding_.builder_doc.root_node_id || selected->parent_id.empty();
        const bool is_shell = selected->container_type == ngk::ui::builder::BuilderContainerType::Shell;
        single_delete_available = !is_root && !is_shell && !selected->parent_id.empty() && binding_.node_exists(selected->parent_id);
      }
    }

    bool insert_available = false;
    if (!binding_.selected_builder_node_id.empty()) {
      if (auto* selected = binding_.find_node_by_id(binding_.selected_builder_node_id)) {
        insert_available = binding_.is_container_widget_type(selected->widget_type);
      }
    }

    const bool delete_available = multi_mode
      ? (bulk_delete != nullptr && bulk_delete->available)
      : single_delete_available;
    const bool move_available = multi_mode
      ? (bulk_move != nullptr && bulk_move->available)
      : false;

    const bool delete_relevant = !binding_.selected_builder_node_id.empty();
    const bool insert_relevant = !multi_mode && insert_available;
    const bool export_relevant = binding_.builder_doc_dirty;

    const bool delete_primary = delete_available && delete_relevant;
    const bool insert_primary = !delete_primary && insert_available && insert_relevant;
    const bool export_primary = !delete_primary && !insert_primary && export_relevant;

    binding_.set_delete_button_state(delete_primary, delete_available, "Delete");
    binding_.set_insert_container_button_state(insert_primary, insert_available, "Add Container");
    binding_.set_insert_leaf_button_state(insert_primary, insert_available, "Add Item");
    binding_.set_export_button_state(export_primary, true, "Export");

    binding_.set_reparent_button_state(move_available && multi_mode && !delete_primary,
                                       move_available && multi_mode,
                                       "Reparent");

    const bool undo_ready = !binding_.undo_history.empty();
    const bool redo_ready = !binding_.redo_stack.empty();
    binding_.set_undo_button_state(false, undo_ready, "Undo");
    binding_.set_redo_button_state(false, redo_ready, "Redo");
  }

 private:
  BulkActionSurfaceLogicBinding& binding_;
};

}  // namespace desktop_file_tool

#define DESKTOP_FILE_TOOL_BIND_BULK_ACTION_SURFACE_LOGIC(logic_object) \
  auto compute_bulk_text_suffix_selection_compatibility = [&]() -> BulkTextSuffixSelectionCompatibility { \
    return (logic_object).compute_bulk_text_suffix_selection_compatibility(); \
  }; \
  auto compute_bulk_action_eligibility_report = [&]() -> BulkActionEligibilityReport { \
    return (logic_object).compute_bulk_action_eligibility_report(); \
  }; \
  auto append_compact_bulk_action_surface = [&](std::ostringstream& oss) { \
    (logic_object).append_compact_bulk_action_surface(oss); \
  }; \
  auto refresh_top_action_surface_from_builder_state = [&]() { \
    (logic_object).refresh_top_action_surface_from_builder_state(); \
  }; \
  auto refresh_action_button_visual_state_from_builder_truth = [&]() { \
    (logic_object).refresh_action_button_visual_state_from_builder_truth(); \
  };