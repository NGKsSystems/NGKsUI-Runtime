#include "desktop_file_tool_document_io.h"
#include <ngk/ui/builder/ngk_ui_builder_document_instantiator.h>
#include <ngk/system/ngk_system_os.h>
#include <iostream>
#include <fstream>
#include <sstream>

#include "desktop_file_tool_string_helpers.h"

namespace desktop_file_tool {

// Local helper required down the chain
struct ScopedBusyFlag {
    bool& flag;
    ScopedBusyFlag(bool& f) : flag(f) { flag = true; }
    ~ScopedBusyFlag() { flag = false; }
};

auto write_text_file = [&](const std::filesystem::path& path, const std::string& text) -> bool {
    try {
      const std::filesystem::path parent = path.parent_path();
      if (!parent.empty()) {
        std::filesystem::create_directories(parent);
      }
      std::ofstream out(path, std::ios::binary | std::ios::trunc);
      if (!out.is_open()) {
        return false;
      }
      out.write(text.data(), static_cast<std::streamsize>(text.size()));
      out.flush();
      return out.good();
    } catch (...) {
      return false;
    }
  };

  bool  read_text_file(const std::filesystem::path& path, std::string& out_text) {
    out_text.clear();
    try {
      std::ifstream in(path, std::ios::binary);
      if (!in.is_open()) {
        return false;
      }
      out_text.assign(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
      return in.good() || in.eof();
    } catch (...) {
      return false;
    }
  };

  bool  read_text_file_exact(const std::filesystem::path& path, std::string& out_text) {
    out_text.clear();
    try {
      std::error_code size_error;
      const std::uintmax_t expected_size = std::filesystem::file_size(path, size_error);
      if (size_error) {
        return false;
      }
      std::ifstream in(path, std::ios::binary);
      if (!in.is_open()) {
        return false;
      }
      out_text.assign(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
      if (in.bad()) {
        return false;
      }
      if (!(in.good() || in.eof())) {
        return false;
      }
      return expected_size == static_cast<std::uintmax_t>(out_text.size());
    } catch (...) {
      return false;
    }
  };

  bool  validate_serialized_builder_document_payload(const std::string& serialized,
                                                          ngk::ui::builder::BuilderDocument* loaded_doc_out,
                                                          std::string* canonical_serialized_out,
                                                          std::string* reason_out) {
    if (reason_out != nullptr) {
      reason_out->clear();
    }
    if (serialized.empty()) {
      if (reason_out != nullptr) {
        *reason_out = "empty_payload";
      }
      return false;
    }

    ngk::ui::builder::BuilderDocument parsed_doc{};
    std::string deserialize_error;
    if (!ngk::ui::builder::deserialize_builder_document_deterministic(serialized, parsed_doc, &deserialize_error)) {
      if (reason_out != nullptr) {
        *reason_out = "deserialize_failed_" + deserialize_error;
      }
      return false;
    }

    std::string validate_error;
    if (!ngk::ui::builder::validate_builder_document(parsed_doc, &validate_error)) {
      if (reason_out != nullptr) {
        *reason_out = "document_invalid_" + validate_error;
      }
      return false;
    }

    ngk::ui::builder::InstantiatedBuilderDocument runtime_loaded{};
    std::string instantiate_error;
    if (!ngk::ui::builder::instantiate_builder_document(parsed_doc, runtime_loaded, &instantiate_error)) {
      if (reason_out != nullptr) {
        *reason_out = "instantiate_failed_" + instantiate_error;
      }
      return false;
    }

    const std::string canonical_serialized = ngk::ui::builder::serialize_builder_document_deterministic(parsed_doc);
    if (canonical_serialized.empty()) {
      if (reason_out != nullptr) {
        *reason_out = "canonical_serialize_failed";
      }
      return false;
    }
    if (canonical_serialized != serialized) {
      if (reason_out != nullptr) {
        *reason_out = "canonical_signature_mismatch";
      }
      return false;
    }

    if (loaded_doc_out != nullptr) {
      *loaded_doc_out = std::move(parsed_doc);
    }
    if (canonical_serialized_out != nullptr) {
      *canonical_serialized_out = canonical_serialized;
    }
    return true;
  };

  std::filesystem::path  build_atomic_save_temp_path(const std::filesystem::path& final_path) {
    return std::filesystem::path(final_path.string() + ".phase103_72_tmp");
  };

  std::filesystem::path  build_atomic_save_backup_path(const std::filesystem::path& final_path) {
    return std::filesystem::path(final_path.string() + ".phase103_72_bak");
  }

  void remove_file_if_exists(const std::filesystem::path& path) {
    std::error_code remove_error;
    std::filesystem::remove(path, remove_error);
  };

  bool  write_persistence_temp_file(const std::filesystem::path& path, const std::string& text) {
    try {
      const std::filesystem::path parent = path.parent_path();
      if (!parent.empty()) {
        std::filesystem::create_directories(parent);
      }
      std::ofstream out(path, std::ios::binary | std::ios::trunc);
      if (!out.is_open()) {
        return false;
      }
      std::size_t bytes_to_write = text.size();
      if (builder_persistence_force_next_temp_write_truncation && !text.empty()) {
        builder_persistence_force_next_temp_write_truncation = false;
        bytes_to_write = std::max<std::size_t>(1, text.size() / 2);
      }
      out.write(text.data(), static_cast<std::streamsize>(bytes_to_write));
      out.flush();
      return out.good();
    } catch (...) {
      return false;
    }
  };

  bool  replace_file_atomically(const std::filesystem::path& temp_path,
                                     const std::filesystem::path& final_path,
                                     const std::filesystem::path& backup_path,
                                     bool final_exists) {
    if (builder_persistence_force_next_atomic_replace_failure) {
      builder_persistence_force_next_atomic_replace_failure = false;
      return false;
    }
    if (final_exists) {
      return ReplaceFileW(final_path.c_str(),
                          temp_path.c_str(),
                          backup_path.c_str(),
                          REPLACEFILE_WRITE_THROUGH,
                          nullptr,
                          nullptr) != 0;
    }
    return MoveFileExW(temp_path.c_str(),
                       final_path.c_str(),
                       MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0;
  };

  bool  restore_atomic_replace_backup(const std::filesystem::path& final_path,
                                           const std::filesystem::path& backup_path,
                                           bool final_existed_before_replace) {
    std::error_code exists_error;
    const bool backup_exists = std::filesystem::exists(backup_path, exists_error);
    if (exists_error || !backup_exists) {
      return !final_existed_before_replace;
    }
    if (final_existed_before_replace) {
      return ReplaceFileW(final_path.c_str(),
                          backup_path.c_str(),
                          nullptr,
                          REPLACEFILE_WRITE_THROUGH,
                          nullptr,
                          nullptr) != 0;
    }
    remove_file_if_exists(final_path);
    return MoveFileExW(backup_path.c_str(),
                       final_path.c_str(),
                       MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0;
  }

  bool atomic_save_builder_document(const std::filesystem::path& path, const ngk::ui::builder::BuilderDocument& builder_doc, bool& builder_persistence_io_in_progress) {
    if (builder_persistence_io_in_progress) {
      return false;
    }
    ScopedBusyFlag io_guard(builder_persistence_io_in_progress);

    const std::string serialized = ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
    if (serialized.empty()) {
      return false;
    }

    std::string payload_reason;
    if (!validate_serialized_builder_document_payload(serialized, nullptr, nullptr, &payload_reason)) {
      return false;
    }

    const std::filesystem::path temp_path = build_atomic_save_temp_path(path);
    const std::filesystem::path backup_path = build_atomic_save_backup_path(path);
    remove_file_if_exists(temp_path);
    remove_file_if_exists(backup_path);

    std::error_code exists_error;
    const bool final_exists = std::filesystem::exists(path, exists_error) && !exists_error;
    if (exists_error) {
      return false;
    }

    if (!write_persistence_temp_file(temp_path, serialized)) {
      remove_file_if_exists(temp_path);
      return false;
    }

    std::string temp_roundtrip{};
    if (!read_text_file_exact(temp_path, temp_roundtrip) || temp_roundtrip != serialized) {
      remove_file_if_exists(temp_path);
      return false;
    }
    if (!validate_serialized_builder_document_payload(temp_roundtrip, nullptr, nullptr, &payload_reason)) {
      remove_file_if_exists(temp_path);
      return false;
    }

    if (!replace_file_atomically(temp_path, path, backup_path, final_exists)) {
      remove_file_if_exists(temp_path);
      remove_file_if_exists(backup_path);
      return false;
    }

    std::string final_roundtrip{};
    const bool final_ok =
      read_text_file_exact(path, final_roundtrip) &&
      final_roundtrip == serialized &&
      validate_serialized_builder_document_payload(final_roundtrip, nullptr, nullptr, &payload_reason);
    if (!final_ok) {
      restore_atomic_replace_backup(path, backup_path, final_exists);
      if (!final_exists) {
        remove_file_if_exists(path);
      }
      remove_file_if_exists(temp_path);
      remove_file_if_exists(backup_path);
      return false;
    }

    remove_file_if_exists(backup_path);
    return true;
  }

  

auto create_default_builder_document = [&](ngk::ui::builder::BuilderDocument& out_doc, std::string& out_selected) -> bool {
    ngk::ui::builder::BuilderDocument doc{};
    doc.schema_version = ngk::ui::builder::kBuilderSchemaVersion;

    ngk::ui::builder::BuilderNode root_node{};
    root_node.node_id = "root-001";
    root_node.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
    root_node.container_type = ngk::ui::builder::BuilderContainerType::Shell;

    ngk::ui::builder::BuilderNode child_node{};
    child_node.node_id = "label-001";
    child_node.parent_id = "root-001";
    child_node.widget_type = ngk::ui::builder::BuilderWidgetType::Label;
    child_node.text = "Builder Label";

    root_node.child_ids.push_back("label-001");
    doc.root_node_id = "root-001";
    doc.nodes.push_back(root_node);
    doc.nodes.push_back(child_node);

    std::string validation_error;
    if (!ngk::ui::builder::validate_builder_document(doc, &validation_error)) {
      return false;
    }

    ngk::ui::builder::InstantiatedBuilderDocument runtime_doc{};
    std::string instantiate_error;
    if (!ngk::ui::builder::instantiate_builder_document(doc, runtime_doc, &instantiate_error)) {
      return false;
    }

    out_doc = std::move(doc);
    out_selected = out_doc.root_node_id;
    return true;
  }

  

} // namespace desktop_file_tool
