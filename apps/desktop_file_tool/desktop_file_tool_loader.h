#pragma once

#include <algorithm>
#include <filesystem>
#include <string>

#include "desktop_file_tool_diagnostics.h"
#include "desktop_file_tool_filter.h"

bool reload_entries(FileToolModel& model, const std::filesystem::path& root) {
  model.entries.clear();

  try {
    for (const auto& entry : std::filesystem::directory_iterator(root)) {
      if (!entry.is_regular_file()) {
        continue;
      }
      if (!file_matches_filter(entry.path(), model.filter)) {
        continue;
      }
      model.entries.push_back(entry);
      if (model.entries.size() >= 128) {
        break;
      }
    }
  } catch (const std::exception& ex) {
    model.status = std::string("LIST_ERROR ") + ex.what();
    model.crash_detected = true;
    return false;
  }

  std::sort(model.entries.begin(), model.entries.end(), [](const auto& left, const auto& right) {
    return left.path().filename().string() < right.path().filename().string();
  });

  if (model.entries.empty()) {
    model.selected_index = 0;
    model.status = "NO_FILES";
  } else {
    if (model.selected_index >= model.entries.size()) {
      model.selected_index = 0;
    }
    model.status = "FILES_READY";
  }

  return true;
}
