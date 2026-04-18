#pragma once

#include <algorithm>
#include <string>

#include "builder_document.hpp"

bool builder_node_matches_projection_query(const ngk::ui::builder::BuilderNode& node,
                                          const std::string& query) {
  if (query.empty()) {
    return true;
  }

  std::string lowered_query = query;
  std::transform(lowered_query.begin(), lowered_query.end(), lowered_query.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });

  std::string lowered_id = node.node_id;
  std::string lowered_type = std::string(ngk::ui::builder::to_string(node.widget_type));
  std::string lowered_text = node.text;
  std::transform(lowered_id.begin(), lowered_id.end(), lowered_id.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });
  std::transform(lowered_type.begin(), lowered_type.end(), lowered_type.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });
  std::transform(lowered_text.begin(), lowered_text.end(), lowered_text.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });

  return lowered_id.find(lowered_query) != std::string::npos ||
         lowered_type.find(lowered_query) != std::string::npos ||
         lowered_text.find(lowered_query) != std::string::npos;
}
