#pragma once

#include <ngk/ui/builder/ngk_ui_builder_document.h>
#include <string>
#include <vector>
#include <filesystem>

namespace desktop_file_tool {

bool write_text_file(const std::filesystem::path& path, const std::string& text);
bool read_text_file(const std::filesystem::path& path, std::string& out_text);
bool read_text_file_exact(const std::filesystem::path& path, std::string& out_text);

bool validate_serialized_builder_document_payload(
    const std::string& serialized,
    ngk::ui::builder::BuilderDocument* doc_out_opt = nullptr,
    std::vector<std::string>* duplicate_ids_out_opt = nullptr,
    std::string* failure_reason_out_opt = nullptr);

std::filesystem::path build_atomic_save_temp_path(const std::filesystem::path& final_path);
std::filesystem::path build_atomic_save_backup_path(const std::filesystem::path& final_path);
void remove_file_if_exists(const std::filesystem::path& path);
bool write_persistence_temp_file(const std::filesystem::path& path, const std::string& text);
bool replace_file_atomically(const std::filesystem::path& temp_path, const std::filesystem::path& final_path, const std::filesystem::path& backup_path, bool final_exists);
void restore_atomic_replace_backup(const std::filesystem::path& final_path, const std::filesystem::path& backup_path, bool final_exists);

bool atomic_save_builder_document(const std::filesystem::path& path, const ngk::ui::builder::BuilderDocument& builder_doc, bool& builder_persistence_io_in_progress);

bool create_default_builder_document(ngk::ui::builder::BuilderDocument& out_doc, std::string& out_selected);

} // namespace desktop_file_tool
