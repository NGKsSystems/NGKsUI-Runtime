#pragma once

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <cstdint>
#include <functional>
#include <iomanip>
#include <memory>
#include <set>
#include <sstream>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "app_shell_widgets.hpp"
#include "button.hpp"
#include "horizontal_layout.hpp"
#include "input_box.hpp"
#include "label.hpp"
#include "list_view.hpp"
#include "scroll_container.hpp"
#include "table_view.hpp"
#include "ui_element.hpp"
#include "vertical_layout.hpp"

namespace ngk::ui::builder {

inline constexpr const char* kBuilderSchemaVersion = "ngk.builder.v1";
inline constexpr const char* kBuilderTextFormatMagic = "NGK_BUILDER_DOCUMENT_V1";

enum class BuilderWidgetType {
  VerticalLayout,
  HorizontalLayout,
  Label,
  Button,
  InputBox,
  ListView,
  TableView,
  ScrollContainer,
  ToolbarContainer,
  SidebarContainer,
  ContentPanel,
  StatusBarContainer,
  SectionHeader,
};

enum class BuilderContainerType {
  None,
  Generic,
  Shell,
  Toolbar,
  Sidebar,
  Content,
  StatusBar,
  Scroll,
};

enum class BuilderAxis {
  None,
  Vertical,
  Horizontal,
};

enum class BuilderSizePolicy {
  Fixed,
  Fill,
};

enum class BuilderAlignment {
  Start,
  Center,
  End,
  Stretch,
};

struct BuilderInsets {
  int left = 0;
  int top = 0;
  int right = 0;
  int bottom = 0;
};

struct BuilderLayoutMetadata {
  BuilderSizePolicy width_policy = BuilderSizePolicy::Fixed;
  BuilderSizePolicy height_policy = BuilderSizePolicy::Fixed;
  int layout_weight = 1;
  int min_width = 0;
  int min_height = 0;
  int preferred_width = 0;
  int preferred_height = 0;
  int spacing = 0;
  BuilderInsets margin{};
  BuilderInsets padding{};
  BuilderAlignment horizontal_alignment = BuilderAlignment::Stretch;
  BuilderAlignment vertical_alignment = BuilderAlignment::Stretch;
};

struct BuilderNode {
  std::string node_id{};
  std::string parent_id{};
  std::vector<std::string> child_ids{};
  BuilderWidgetType widget_type = BuilderWidgetType::VerticalLayout;
  BuilderContainerType container_type = BuilderContainerType::Generic;
  BuilderAxis layout_axis = BuilderAxis::Vertical;
  BuilderLayoutMetadata layout{};
  std::string text{};
  bool visible = true;
};

struct BuilderDocument {
  std::string schema_version = kBuilderSchemaVersion;
  std::string root_node_id{};
  std::vector<BuilderNode> nodes{};
};

struct InstantiatedBuilderDocument {
  std::vector<std::unique_ptr<UIElement>> storage{};
  std::unordered_map<std::string, UIElement*> nodes_by_id{};
  UIElement* root = nullptr;
};

inline bool is_valid_node_id(const std::string& value) {
  if (value.empty()) {
    return false;
  }
  for (unsigned char c : value) {
    if (!(std::isalnum(c) != 0 || c == '_' || c == '-')) {
      return false;
    }
  }
  return true;
}

inline std::string make_stable_node_id(int ordinal) {
  std::ostringstream oss;
  oss << "node-" << std::setw(4) << std::setfill('0') << std::max(1, ordinal);
  return oss.str();
}

inline const char* to_string(BuilderWidgetType value) {
  switch (value) {
    case BuilderWidgetType::VerticalLayout:
      return "vertical_layout";
    case BuilderWidgetType::HorizontalLayout:
      return "horizontal_layout";
    case BuilderWidgetType::Label:
      return "label";
    case BuilderWidgetType::Button:
      return "button";
    case BuilderWidgetType::InputBox:
      return "input_box";
    case BuilderWidgetType::ListView:
      return "list_view";
    case BuilderWidgetType::TableView:
      return "table_view";
    case BuilderWidgetType::ScrollContainer:
      return "scroll_container";
    case BuilderWidgetType::ToolbarContainer:
      return "toolbar_container";
    case BuilderWidgetType::SidebarContainer:
      return "sidebar_container";
    case BuilderWidgetType::ContentPanel:
      return "content_panel";
    case BuilderWidgetType::StatusBarContainer:
      return "status_bar_container";
    case BuilderWidgetType::SectionHeader:
      return "section_header";
  }
  return "vertical_layout";
}

inline const char* to_string(BuilderContainerType value) {
  switch (value) {
    case BuilderContainerType::None:
      return "none";
    case BuilderContainerType::Generic:
      return "generic";
    case BuilderContainerType::Shell:
      return "shell";
    case BuilderContainerType::Toolbar:
      return "toolbar";
    case BuilderContainerType::Sidebar:
      return "sidebar";
    case BuilderContainerType::Content:
      return "content";
    case BuilderContainerType::StatusBar:
      return "status_bar";
    case BuilderContainerType::Scroll:
      return "scroll";
  }
  return "none";
}

inline const char* to_string(BuilderAxis value) {
  switch (value) {
    case BuilderAxis::None:
      return "none";
    case BuilderAxis::Vertical:
      return "vertical";
    case BuilderAxis::Horizontal:
      return "horizontal";
  }
  return "none";
}

inline const char* to_string(BuilderSizePolicy value) {
  switch (value) {
    case BuilderSizePolicy::Fixed:
      return "fixed";
    case BuilderSizePolicy::Fill:
      return "fill";
  }
  return "fixed";
}

inline const char* to_string(BuilderAlignment value) {
  switch (value) {
    case BuilderAlignment::Start:
      return "start";
    case BuilderAlignment::Center:
      return "center";
    case BuilderAlignment::End:
      return "end";
    case BuilderAlignment::Stretch:
      return "stretch";
  }
  return "stretch";
}

inline bool parse_widget_type(const std::string& text, BuilderWidgetType& out) {
  if (text == "vertical_layout") {
    out = BuilderWidgetType::VerticalLayout;
  } else if (text == "horizontal_layout") {
    out = BuilderWidgetType::HorizontalLayout;
  } else if (text == "label") {
    out = BuilderWidgetType::Label;
  } else if (text == "button") {
    out = BuilderWidgetType::Button;
  } else if (text == "input_box") {
    out = BuilderWidgetType::InputBox;
  } else if (text == "list_view") {
    out = BuilderWidgetType::ListView;
  } else if (text == "table_view") {
    out = BuilderWidgetType::TableView;
  } else if (text == "scroll_container") {
    out = BuilderWidgetType::ScrollContainer;
  } else if (text == "toolbar_container") {
    out = BuilderWidgetType::ToolbarContainer;
  } else if (text == "sidebar_container") {
    out = BuilderWidgetType::SidebarContainer;
  } else if (text == "content_panel") {
    out = BuilderWidgetType::ContentPanel;
  } else if (text == "status_bar_container") {
    out = BuilderWidgetType::StatusBarContainer;
  } else if (text == "section_header") {
    out = BuilderWidgetType::SectionHeader;
  } else {
    return false;
  }
  return true;
}

inline bool parse_container_type(const std::string& text, BuilderContainerType& out) {
  if (text == "none") {
    out = BuilderContainerType::None;
  } else if (text == "generic") {
    out = BuilderContainerType::Generic;
  } else if (text == "shell") {
    out = BuilderContainerType::Shell;
  } else if (text == "toolbar") {
    out = BuilderContainerType::Toolbar;
  } else if (text == "sidebar") {
    out = BuilderContainerType::Sidebar;
  } else if (text == "content") {
    out = BuilderContainerType::Content;
  } else if (text == "status_bar") {
    out = BuilderContainerType::StatusBar;
  } else if (text == "scroll") {
    out = BuilderContainerType::Scroll;
  } else {
    return false;
  }
  return true;
}

inline bool parse_axis(const std::string& text, BuilderAxis& out) {
  if (text == "none") {
    out = BuilderAxis::None;
  } else if (text == "vertical") {
    out = BuilderAxis::Vertical;
  } else if (text == "horizontal") {
    out = BuilderAxis::Horizontal;
  } else {
    return false;
  }
  return true;
}

inline bool parse_size_policy(const std::string& text, BuilderSizePolicy& out) {
  if (text == "fixed") {
    out = BuilderSizePolicy::Fixed;
  } else if (text == "fill") {
    out = BuilderSizePolicy::Fill;
  } else {
    return false;
  }
  return true;
}

inline bool parse_alignment(const std::string& text, BuilderAlignment& out) {
  if (text == "start") {
    out = BuilderAlignment::Start;
  } else if (text == "center") {
    out = BuilderAlignment::Center;
  } else if (text == "end") {
    out = BuilderAlignment::End;
  } else if (text == "stretch") {
    out = BuilderAlignment::Stretch;
  } else {
    return false;
  }
  return true;
}

inline bool widget_allows_children(BuilderWidgetType type) {
  switch (type) {
    case BuilderWidgetType::VerticalLayout:
    case BuilderWidgetType::HorizontalLayout:
    case BuilderWidgetType::ScrollContainer:
    case BuilderWidgetType::ToolbarContainer:
    case BuilderWidgetType::SidebarContainer:
    case BuilderWidgetType::ContentPanel:
    case BuilderWidgetType::StatusBarContainer:
      return true;
    case BuilderWidgetType::Label:
    case BuilderWidgetType::Button:
    case BuilderWidgetType::InputBox:
    case BuilderWidgetType::ListView:
    case BuilderWidgetType::TableView:
    case BuilderWidgetType::SectionHeader:
      return false;
  }
  return false;
}

inline bool parse_int32(const std::string& value, int& out) {
  if (value.empty()) {
    return false;
  }
  char* end_ptr = nullptr;
  const long parsed = std::strtol(value.c_str(), &end_ptr, 10);
  if (end_ptr == nullptr || *end_ptr != '\0') {
    return false;
  }
  out = static_cast<int>(parsed);
  return true;
}

inline bool parse_bool01(const std::string& value, bool& out) {
  if (value == "1") {
    out = true;
    return true;
  }
  if (value == "0") {
    out = false;
    return true;
  }
  return false;
}

inline std::string escape_field(const std::string& value) {
  std::ostringstream oss;
  for (unsigned char c : value) {
    if (c == '%' || c == '\n' || c == '\r' || c == '=') {
      oss << '%' << std::uppercase << std::hex << std::setw(2) << std::setfill('0') << static_cast<int>(c)
          << std::nouppercase << std::dec;
    } else {
      oss << static_cast<char>(c);
    }
  }
  return oss.str();
}

inline bool unescape_field(const std::string& value, std::string& out) {
  out.clear();
  for (std::size_t i = 0; i < value.size(); ++i) {
    const char c = value[i];
    if (c != '%') {
      out.push_back(c);
      continue;
    }
    if (i + 2 >= value.size()) {
      return false;
    }
    const char hi = value[i + 1];
    const char lo = value[i + 2];
    auto hex_to_int = [](char h) -> int {
      if (h >= '0' && h <= '9') {
        return h - '0';
      }
      if (h >= 'A' && h <= 'F') {
        return 10 + (h - 'A');
      }
      if (h >= 'a' && h <= 'f') {
        return 10 + (h - 'a');
      }
      return -1;
    };
    const int high = hex_to_int(hi);
    const int low = hex_to_int(lo);
    if (high < 0 || low < 0) {
      return false;
    }
    out.push_back(static_cast<char>((high << 4) | low));
    i += 2;
  }
  return true;
}

inline bool validate_builder_document(const BuilderDocument& doc, std::string* error_out = nullptr) {
  auto fail = [&](const std::string& error) {
    if (error_out != nullptr) {
      *error_out = error;
    }
    return false;
  };

  if (doc.schema_version != kBuilderSchemaVersion) {
    return fail("unsupported schema version");
  }
  if (!is_valid_node_id(doc.root_node_id)) {
    return fail("invalid or missing root_node_id");
  }
  if (doc.nodes.empty()) {
    return fail("nodes must not be empty");
  }

  std::unordered_map<std::string, const BuilderNode*> by_id;
  by_id.reserve(doc.nodes.size());

  for (const BuilderNode& node : doc.nodes) {
    if (!is_valid_node_id(node.node_id)) {
      return fail("node has invalid id");
    }
    if (by_id.find(node.node_id) != by_id.end()) {
      return fail("duplicate node id");
    }
    if (!node.parent_id.empty() && !is_valid_node_id(node.parent_id)) {
      return fail("node has invalid parent id");
    }
    if (node.layout.layout_weight <= 0) {
      return fail("layout_weight must be > 0");
    }
    if (node.layout.min_width < 0 || node.layout.min_height < 0) {
      return fail("min size must be >= 0");
    }
    if (node.layout.preferred_width < 0 || node.layout.preferred_height < 0) {
      return fail("preferred size must be >= 0");
    }
    if (node.layout.spacing < 0) {
      return fail("spacing must be >= 0");
    }
    if (!widget_allows_children(node.widget_type) && !node.child_ids.empty()) {
      return fail("leaf widget cannot own children");
    }
    by_id.emplace(node.node_id, &node);
  }

  auto root_it = by_id.find(doc.root_node_id);
  if (root_it == by_id.end()) {
    return fail("root_node_id does not exist");
  }

  for (const BuilderNode& node : doc.nodes) {
    const bool is_root = (node.node_id == doc.root_node_id);
    if (is_root) {
      if (!node.parent_id.empty()) {
        return fail("root node parent_id must be empty");
      }
    } else if (node.parent_id.empty()) {
      return fail("non-root node missing parent_id");
    }

    std::unordered_set<std::string> local_children;
    for (const std::string& child_id : node.child_ids) {
      if (!is_valid_node_id(child_id)) {
        return fail("invalid child id");
      }
      if (child_id == node.node_id) {
        return fail("node cannot be child of itself");
      }
      if (!local_children.insert(child_id).second) {
        return fail("duplicate child id in ordered list");
      }

      auto child_it = by_id.find(child_id);
      if (child_it == by_id.end()) {
        return fail("child id references missing node");
      }
      if (child_it->second->parent_id != node.node_id) {
        return fail("child parent_id mismatch");
      }
    }
  }

  std::unordered_set<std::string> visited;
  std::unordered_set<std::string> stack;

  std::function<bool(const std::string&)> dfs = [&](const std::string& node_id) {
    if (stack.find(node_id) != stack.end()) {
      return false;
    }
    if (visited.find(node_id) != visited.end()) {
      return true;
    }

    visited.insert(node_id);
    stack.insert(node_id);
    const BuilderNode* node = by_id[node_id];
    for (const std::string& child_id : node->child_ids) {
      if (!dfs(child_id)) {
        return false;
      }
    }
    stack.erase(node_id);
    return true;
  };

  if (!dfs(doc.root_node_id)) {
    return fail("cycle detected");
  }
  if (visited.size() != doc.nodes.size()) {
    return fail("unreachable or orphaned node detected");
  }

  return true;
}

inline std::vector<const BuilderNode*> canonical_node_order(const BuilderDocument& doc) {
  std::unordered_map<std::string, const BuilderNode*> by_id;
  by_id.reserve(doc.nodes.size());
  for (const BuilderNode& node : doc.nodes) {
    by_id.emplace(node.node_id, &node);
  }

  std::vector<const BuilderNode*> ordered;
  ordered.reserve(doc.nodes.size());
  std::unordered_set<std::string> visited;
  std::function<void(const std::string&)> walk = [&](const std::string& node_id) {
    if (visited.find(node_id) != visited.end()) {
      return;
    }
    auto it = by_id.find(node_id);
    if (it == by_id.end()) {
      return;
    }
    visited.insert(node_id);
    ordered.push_back(it->second);
    for (const std::string& child_id : it->second->child_ids) {
      walk(child_id);
    }
  };

  walk(doc.root_node_id);

  if (ordered.size() != doc.nodes.size()) {
    std::vector<const BuilderNode*> remainder;
    remainder.reserve(doc.nodes.size() - ordered.size());
    for (const BuilderNode& node : doc.nodes) {
      if (visited.find(node.node_id) == visited.end()) {
        remainder.push_back(&node);
      }
    }
    std::sort(remainder.begin(), remainder.end(), [](const BuilderNode* lhs, const BuilderNode* rhs) {
      return lhs->node_id < rhs->node_id;
    });
    ordered.insert(ordered.end(), remainder.begin(), remainder.end());
  }

  return ordered;
}

inline std::string serialize_builder_document_deterministic(const BuilderDocument& doc) {
  std::string validation_error;
  if (!validate_builder_document(doc, &validation_error)) {
    return std::string();
  }

  const std::vector<const BuilderNode*> ordered = canonical_node_order(doc);
  std::string out;
  out.reserve(128 + ordered.size() * 768);

  auto append_text = [&](const std::string& text) {
    out.append(text);
  };

  auto append_line = [&](const std::string& key, const std::string& value) {
    out.append(key);
    out.push_back('=');
    out.append(value);
    out.push_back('\n');
  };

  auto append_int_line = [&](const std::string& key, int value) {
    out.append(key);
    out.push_back('=');
    out.append(std::to_string(value));
    out.push_back('\n');
  };

  auto append_size_line = [&](const std::string& key, std::size_t value) {
    out.append(key);
    out.push_back('=');
    out.append(std::to_string(value));
    out.push_back('\n');
  };

  append_text(kBuilderTextFormatMagic);
  out.push_back('\n');
  append_line("schema_version", escape_field(doc.schema_version));
  append_line("root_node_id", escape_field(doc.root_node_id));
  append_size_line("node_count", ordered.size());

  for (std::size_t index = 0; index < ordered.size(); ++index) {
    const BuilderNode& node = *ordered[index];
    const std::string prefix = "node." + std::to_string(index) + ".";

    append_line(prefix + "id", escape_field(node.node_id));
    append_line(prefix + "parent_id", escape_field(node.parent_id));
    append_line(prefix + "widget_type", to_string(node.widget_type));
    append_line(prefix + "container_type", to_string(node.container_type));
    append_line(prefix + "layout_axis", to_string(node.layout_axis));
    append_int_line(prefix + "visible", node.visible ? 1 : 0);
    append_line(prefix + "text", escape_field(node.text));

    append_line(prefix + "layout.width_policy", to_string(node.layout.width_policy));
    append_line(prefix + "layout.height_policy", to_string(node.layout.height_policy));
    append_int_line(prefix + "layout.weight", node.layout.layout_weight);
    append_int_line(prefix + "layout.min_width", node.layout.min_width);
    append_int_line(prefix + "layout.min_height", node.layout.min_height);
    append_int_line(prefix + "layout.preferred_width", node.layout.preferred_width);
    append_int_line(prefix + "layout.preferred_height", node.layout.preferred_height);
    append_int_line(prefix + "layout.spacing", node.layout.spacing);

    append_int_line(prefix + "layout.margin.left", node.layout.margin.left);
    append_int_line(prefix + "layout.margin.top", node.layout.margin.top);
    append_int_line(prefix + "layout.margin.right", node.layout.margin.right);
    append_int_line(prefix + "layout.margin.bottom", node.layout.margin.bottom);

    append_int_line(prefix + "layout.padding.left", node.layout.padding.left);
    append_int_line(prefix + "layout.padding.top", node.layout.padding.top);
    append_int_line(prefix + "layout.padding.right", node.layout.padding.right);
    append_int_line(prefix + "layout.padding.bottom", node.layout.padding.bottom);

    append_line(prefix + "layout.align.horizontal", to_string(node.layout.horizontal_alignment));
    append_line(prefix + "layout.align.vertical", to_string(node.layout.vertical_alignment));

    append_size_line(prefix + "child_count", node.child_ids.size());
    for (std::size_t child_index = 0; child_index < node.child_ids.size(); ++child_index) {
      append_line(prefix + "child." + std::to_string(child_index), escape_field(node.child_ids[child_index]));
    }
  }

  return out;
}

inline bool parse_prefixed_key(const std::string& line, const std::string& key_prefix, std::string& value_out) {
  const std::string prefix = key_prefix + "=";
  if (line.rfind(prefix, 0) != 0) {
    return false;
  }
  value_out = line.substr(prefix.size());
  return true;
}

inline bool deserialize_builder_document_deterministic(
  const std::string& text,
  BuilderDocument& out_doc,
  std::string* error_out = nullptr) {

  auto fail = [&](const std::string& error) {
    if (error_out != nullptr) {
      *error_out = error;
    }
    return false;
  };

  std::vector<std::string> lines;
  {
    std::istringstream input(text);
    std::string line;
    while (std::getline(input, line)) {
      if (!line.empty() && line.back() == '\r') {
        line.pop_back();
      }
      if (!line.empty()) {
        lines.push_back(line);
      }
    }
  }

  if (lines.size() < 4) {
    return fail("document too small");
  }
  std::size_t cursor = 0;

  if (lines[cursor++] != kBuilderTextFormatMagic) {
    return fail("missing or invalid format magic");
  }

  std::string encoded_schema;
  if (!parse_prefixed_key(lines[cursor++], "schema_version", encoded_schema)) {
    return fail("schema_version missing");
  }
  std::string schema_version;
  if (!unescape_field(encoded_schema, schema_version)) {
    return fail("schema_version decode failed");
  }

  std::string encoded_root;
  if (!parse_prefixed_key(lines[cursor++], "root_node_id", encoded_root)) {
    return fail("root_node_id missing");
  }
  std::string root_node_id;
  if (!unescape_field(encoded_root, root_node_id)) {
    return fail("root_node_id decode failed");
  }

  std::string node_count_text;
  if (!parse_prefixed_key(lines[cursor++], "node_count", node_count_text)) {
    return fail("node_count missing");
  }

  int node_count = 0;
  if (!parse_int32(node_count_text, node_count) || node_count <= 0) {
    return fail("node_count invalid");
  }

  BuilderDocument doc{};
  doc.schema_version = schema_version;
  doc.root_node_id = root_node_id;
  doc.nodes.reserve(static_cast<std::size_t>(node_count));

  for (int node_index = 0; node_index < node_count; ++node_index) {
    BuilderNode node{};
    const std::string prefix = "node." + std::to_string(node_index) + ".";

    auto read_string = [&](const std::string& key, std::string& out_value) -> bool {
      if (cursor >= lines.size()) {
        return false;
      }
      std::string encoded;
      if (!parse_prefixed_key(lines[cursor], prefix + key, encoded)) {
        return false;
      }
      ++cursor;
      return unescape_field(encoded, out_value);
    };

    auto read_int = [&](const std::string& key, int& out_value) -> bool {
      if (cursor >= lines.size()) {
        return false;
      }
      std::string raw;
      if (!parse_prefixed_key(lines[cursor], prefix + key, raw)) {
        return false;
      }
      ++cursor;
      return parse_int32(raw, out_value);
    };

    auto read_bool = [&](const std::string& key, bool& out_value) -> bool {
      if (cursor >= lines.size()) {
        return false;
      }
      std::string raw;
      if (!parse_prefixed_key(lines[cursor], prefix + key, raw)) {
        return false;
      }
      ++cursor;
      return parse_bool01(raw, out_value);
    };

    std::string widget_type_text;
    std::string container_type_text;
    std::string layout_axis_text;
    std::string width_policy_text;
    std::string height_policy_text;
    std::string horizontal_align_text;
    std::string vertical_align_text;

    if (!read_string("id", node.node_id)) {
      return fail("node.id missing");
    }
    if (!read_string("parent_id", node.parent_id)) {
      return fail("node.parent_id missing");
    }
    if (!read_string("widget_type", widget_type_text)) {
      return fail("node.widget_type missing");
    }
    if (!read_string("container_type", container_type_text)) {
      return fail("node.container_type missing");
    }
    if (!read_string("layout_axis", layout_axis_text)) {
      return fail("node.layout_axis missing");
    }
    if (!read_bool("visible", node.visible)) {
      return fail("node.visible missing");
    }
    if (!read_string("text", node.text)) {
      return fail("node.text missing");
    }

    if (!read_string("layout.width_policy", width_policy_text)) {
      return fail("node.layout.width_policy missing");
    }
    if (!read_string("layout.height_policy", height_policy_text)) {
      return fail("node.layout.height_policy missing");
    }
    if (!read_int("layout.weight", node.layout.layout_weight)) {
      return fail("node.layout.weight missing");
    }
    if (!read_int("layout.min_width", node.layout.min_width)) {
      return fail("node.layout.min_width missing");
    }
    if (!read_int("layout.min_height", node.layout.min_height)) {
      return fail("node.layout.min_height missing");
    }
    if (!read_int("layout.preferred_width", node.layout.preferred_width)) {
      return fail("node.layout.preferred_width missing");
    }
    if (!read_int("layout.preferred_height", node.layout.preferred_height)) {
      return fail("node.layout.preferred_height missing");
    }
    if (!read_int("layout.spacing", node.layout.spacing)) {
      return fail("node.layout.spacing missing");
    }

    if (!read_int("layout.margin.left", node.layout.margin.left)) {
      return fail("node.layout.margin.left missing");
    }
    if (!read_int("layout.margin.top", node.layout.margin.top)) {
      return fail("node.layout.margin.top missing");
    }
    if (!read_int("layout.margin.right", node.layout.margin.right)) {
      return fail("node.layout.margin.right missing");
    }
    if (!read_int("layout.margin.bottom", node.layout.margin.bottom)) {
      return fail("node.layout.margin.bottom missing");
    }

    if (!read_int("layout.padding.left", node.layout.padding.left)) {
      return fail("node.layout.padding.left missing");
    }
    if (!read_int("layout.padding.top", node.layout.padding.top)) {
      return fail("node.layout.padding.top missing");
    }
    if (!read_int("layout.padding.right", node.layout.padding.right)) {
      return fail("node.layout.padding.right missing");
    }
    if (!read_int("layout.padding.bottom", node.layout.padding.bottom)) {
      return fail("node.layout.padding.bottom missing");
    }

    if (!read_string("layout.align.horizontal", horizontal_align_text)) {
      return fail("node.layout.align.horizontal missing");
    }
    if (!read_string("layout.align.vertical", vertical_align_text)) {
      return fail("node.layout.align.vertical missing");
    }

    int child_count = 0;
    if (!read_int("child_count", child_count) || child_count < 0) {
      return fail("node.child_count invalid");
    }

    node.child_ids.reserve(static_cast<std::size_t>(child_count));
    for (int child_index = 0; child_index < child_count; ++child_index) {
      std::string child_id;
      if (!read_string("child." + std::to_string(child_index), child_id)) {
        return fail("node.child entry missing");
      }
      node.child_ids.push_back(std::move(child_id));
    }

    if (!parse_widget_type(widget_type_text, node.widget_type)) {
      return fail("invalid widget_type value");
    }
    if (!parse_container_type(container_type_text, node.container_type)) {
      return fail("invalid container_type value");
    }
    if (!parse_axis(layout_axis_text, node.layout_axis)) {
      return fail("invalid layout_axis value");
    }
    if (!parse_size_policy(width_policy_text, node.layout.width_policy)) {
      return fail("invalid layout.width_policy value");
    }
    if (!parse_size_policy(height_policy_text, node.layout.height_policy)) {
      return fail("invalid layout.height_policy value");
    }
    if (!parse_alignment(horizontal_align_text, node.layout.horizontal_alignment)) {
      return fail("invalid horizontal alignment value");
    }
    if (!parse_alignment(vertical_align_text, node.layout.vertical_alignment)) {
      return fail("invalid vertical alignment value");
    }

    doc.nodes.push_back(std::move(node));
  }

  if (cursor != lines.size()) {
    return fail("unexpected trailing fields");
  }

  std::string validation_error;
  if (!validate_builder_document(doc, &validation_error)) {
    return fail(validation_error);
  }

  out_doc = std::move(doc);
  return true;
}

inline UIElement::LayoutSizePolicy map_policy(BuilderSizePolicy policy) {
  return policy == BuilderSizePolicy::Fill
    ? UIElement::LayoutSizePolicy::Fill
    : UIElement::LayoutSizePolicy::Fixed;
}

inline void apply_layout_properties(UIElement& element, const BuilderNode& node) {
  element.set_visible(node.visible);
  element.set_min_size(node.layout.min_width, node.layout.min_height);
  if (node.layout.preferred_width > 0 || node.layout.preferred_height > 0) {
    element.set_preferred_size(node.layout.preferred_width, node.layout.preferred_height);
  }
  element.set_layout_width_policy(map_policy(node.layout.width_policy));
  element.set_layout_height_policy(map_policy(node.layout.height_policy));
  element.set_layout_weight(node.layout.layout_weight);

  if (auto* vertical = dynamic_cast<VerticalLayout*>(&element)) {
    vertical->set_spacing(node.layout.spacing);
    vertical->set_padding(
      node.layout.padding.left,
      node.layout.padding.top,
      node.layout.padding.right,
      node.layout.padding.bottom);
  }
  if (auto* horizontal = dynamic_cast<HorizontalLayout*>(&element)) {
    horizontal->set_spacing(node.layout.spacing);
    horizontal->set_padding(
      node.layout.padding.left,
      node.layout.padding.top,
      node.layout.padding.right,
      node.layout.padding.bottom);
  }
}

inline std::unique_ptr<UIElement> create_runtime_element(const BuilderNode& node) {
  std::unique_ptr<UIElement> element;

  switch (node.widget_type) {
    case BuilderWidgetType::VerticalLayout:
      element = std::make_unique<VerticalLayout>(node.layout.spacing);
      break;
    case BuilderWidgetType::HorizontalLayout:
      element = std::make_unique<HorizontalLayout>(node.layout.spacing);
      break;
    case BuilderWidgetType::Label: {
      auto widget = std::make_unique<Label>();
      widget->set_text(node.text);
      element = std::move(widget);
      break;
    }
    case BuilderWidgetType::Button: {
      auto widget = std::make_unique<Button>();
      widget->set_text(node.text);
      element = std::move(widget);
      break;
    }
    case BuilderWidgetType::InputBox: {
      auto widget = std::make_unique<InputBox>();
      widget->set_value(node.text);
      element = std::move(widget);
      break;
    }
    case BuilderWidgetType::ListView:
      element = std::make_unique<ListView>();
      break;
    case BuilderWidgetType::TableView:
      element = std::make_unique<TableView>();
      break;
    case BuilderWidgetType::ScrollContainer:
      element = std::make_unique<ScrollContainer>();
      break;
    case BuilderWidgetType::ToolbarContainer:
      element = std::make_unique<ToolbarContainer>(node.layout.spacing);
      break;
    case BuilderWidgetType::SidebarContainer:
      element = std::make_unique<SidebarContainer>(node.layout.spacing);
      break;
    case BuilderWidgetType::ContentPanel:
      element = std::make_unique<ContentPanel>(node.layout.spacing);
      break;
    case BuilderWidgetType::StatusBarContainer:
      element = std::make_unique<StatusBarContainer>(node.layout.spacing);
      break;
    case BuilderWidgetType::SectionHeader: {
      auto widget = std::make_unique<SectionHeader>();
      widget->set_text(node.text);
      element = std::move(widget);
      break;
    }
  }

  if (element) {
    apply_layout_properties(*element, node);
  }
  return element;
}

inline bool instantiate_builder_document(
  const BuilderDocument& doc,
  InstantiatedBuilderDocument& out,
  std::string* error_out = nullptr) {

  std::string validation_error;
  if (!validate_builder_document(doc, &validation_error)) {
    if (error_out != nullptr) {
      *error_out = validation_error;
    }
    return false;
  }

  out = InstantiatedBuilderDocument{};
  out.storage.reserve(doc.nodes.size());
  out.nodes_by_id.reserve(doc.nodes.size());

  std::unordered_map<std::string, const BuilderNode*> by_id;
  by_id.reserve(doc.nodes.size());
  for (const BuilderNode& node : doc.nodes) {
    by_id.emplace(node.node_id, &node);
  }

  for (const BuilderNode& node : doc.nodes) {
    std::unique_ptr<UIElement> element = create_runtime_element(node);
    if (!element) {
      if (error_out != nullptr) {
        *error_out = "failed to instantiate runtime element";
      }
      return false;
    }

    UIElement* raw = element.get();
    out.nodes_by_id.emplace(node.node_id, raw);
    out.storage.push_back(std::move(element));
  }

  for (const BuilderNode& node : doc.nodes) {
    UIElement* parent = out.nodes_by_id[node.node_id];
    for (const std::string& child_id : node.child_ids) {
      auto child_it = out.nodes_by_id.find(child_id);
      if (child_it == out.nodes_by_id.end()) {
        if (error_out != nullptr) {
          *error_out = "child id missing during instantiation";
        }
        return false;
      }
      parent->add_child(child_it->second);
    }
  }

  auto root_it = out.nodes_by_id.find(doc.root_node_id);
  if (root_it == out.nodes_by_id.end()) {
    if (error_out != nullptr) {
      *error_out = "root missing during instantiation";
    }
    return false;
  }

  out.root = root_it->second;
  return true;
}

inline bool schema_is_runtime_aligned(const BuilderDocument& doc) {
  bool has_vertical_or_horizontal = false;
  bool has_weighted_fill = false;
  bool has_min_size = false;
  bool has_padding = false;
  bool has_alignment = false;
  bool has_shell_or_container = false;

  for (const BuilderNode& node : doc.nodes) {
    if (node.layout_axis == BuilderAxis::Vertical || node.layout_axis == BuilderAxis::Horizontal) {
      has_vertical_or_horizontal = true;
    }
    if (node.layout.width_policy == BuilderSizePolicy::Fill || node.layout.height_policy == BuilderSizePolicy::Fill) {
      if (node.layout.layout_weight > 0) {
        has_weighted_fill = true;
      }
    }
    if (node.layout.min_width > 0 || node.layout.min_height > 0) {
      has_min_size = true;
    }
    if (node.layout.padding.left > 0 || node.layout.padding.top > 0 ||
        node.layout.padding.right > 0 || node.layout.padding.bottom > 0) {
      has_padding = true;
    }
    if (node.layout.horizontal_alignment != BuilderAlignment::Stretch ||
        node.layout.vertical_alignment != BuilderAlignment::Stretch) {
      has_alignment = true;
    }
    if (node.container_type != BuilderContainerType::None) {
      has_shell_or_container = true;
    }
  }

  return has_vertical_or_horizontal && has_weighted_fill && has_min_size &&
         has_padding && has_alignment && has_shell_or_container;
}

enum class BuilderPropertyValueType {
  Integer,
  Boolean,
  String,
  Enum,
};

struct BuilderPropertyDescriptor {
  std::string key{};
  BuilderPropertyValueType value_type = BuilderPropertyValueType::String;
  bool editable = false;
};

struct BuilderPropertyEntry {
  BuilderPropertyDescriptor descriptor{};
  std::string value{};
};

struct BuilderInspectionResult {
  std::string node_id{};
  std::vector<BuilderPropertyEntry> properties{};
};

struct BuilderSelectionState {
  std::string selected_node_id{};

  void clear_selection() {
    selected_node_id.clear();
  }

  bool has_selection() const {
    return !selected_node_id.empty();
  }
};

struct BuilderPropertyUpdateCommand {
  std::string node_id{};
  std::string property_key{};
  std::string property_value{};
};

inline const BuilderNode* find_node_by_id(const BuilderDocument& doc, const std::string& node_id) {
  for (const BuilderNode& node : doc.nodes) {
    if (node.node_id == node_id) {
      return &node;
    }
  }
  return nullptr;
}

inline BuilderNode* find_node_by_id_mutable(BuilderDocument& doc, const std::string& node_id) {
  for (BuilderNode& node : doc.nodes) {
    if (node.node_id == node_id) {
      return &node;
    }
  }
  return nullptr;
}

inline bool node_reachable_from_root(const BuilderDocument& doc, const std::string& node_id) {
  if (doc.root_node_id.empty() || node_id.empty()) {
    return false;
  }

  std::unordered_set<std::string> visited;
  std::vector<std::string> stack;
  stack.push_back(doc.root_node_id);

  while (!stack.empty()) {
    const std::string current_id = stack.back();
    stack.pop_back();

    if (!visited.insert(current_id).second) {
      continue;
    }

    if (current_id == node_id) {
      return true;
    }

    const BuilderNode* current = find_node_by_id(doc, current_id);
    if (!current) {
      continue;
    }

    for (const std::string& child_id : current->child_ids) {
      stack.push_back(child_id);
    }
  }

  return false;
}

inline bool select_node_by_id(
  BuilderSelectionState& selection,
  const BuilderDocument& doc,
  const std::string& node_id) {

  if (!validate_builder_document(doc, nullptr)) {
    selection.clear_selection();
    return false;
  }

  if (!is_valid_node_id(node_id)) {
    return false;
  }

  const BuilderNode* node = find_node_by_id(doc, node_id);
  if (!node) {
    return false;
  }

  if (!node_reachable_from_root(doc, node_id)) {
    return false;
  }

  selection.selected_node_id = node_id;
  return true;
}

inline bool widget_supports_text_property(BuilderWidgetType type) {
  switch (type) {
    case BuilderWidgetType::Label:
    case BuilderWidgetType::Button:
    case BuilderWidgetType::InputBox:
    case BuilderWidgetType::SectionHeader:
      return true;
    case BuilderWidgetType::VerticalLayout:
    case BuilderWidgetType::HorizontalLayout:
    case BuilderWidgetType::ListView:
    case BuilderWidgetType::TableView:
    case BuilderWidgetType::ScrollContainer:
    case BuilderWidgetType::ToolbarContainer:
    case BuilderWidgetType::SidebarContainer:
    case BuilderWidgetType::ContentPanel:
    case BuilderWidgetType::StatusBarContainer:
      return false;
  }
  return false;
}

inline bool widget_supports_spacing_and_padding(BuilderWidgetType type) {
  switch (type) {
    case BuilderWidgetType::VerticalLayout:
    case BuilderWidgetType::HorizontalLayout:
    case BuilderWidgetType::ToolbarContainer:
    case BuilderWidgetType::SidebarContainer:
    case BuilderWidgetType::ContentPanel:
    case BuilderWidgetType::StatusBarContainer:
      return true;
    case BuilderWidgetType::Label:
    case BuilderWidgetType::Button:
    case BuilderWidgetType::InputBox:
    case BuilderWidgetType::ListView:
    case BuilderWidgetType::TableView:
    case BuilderWidgetType::ScrollContainer:
    case BuilderWidgetType::SectionHeader:
      return false;
  }
  return false;
}

inline void append_common_layout_schema(std::vector<BuilderPropertyDescriptor>& schema) {
  schema.push_back({"visible", BuilderPropertyValueType::Boolean, true});
  schema.push_back({"layout.width_policy", BuilderPropertyValueType::Enum, true});
  schema.push_back({"layout.height_policy", BuilderPropertyValueType::Enum, true});
  schema.push_back({"layout.weight", BuilderPropertyValueType::Integer, true});
  schema.push_back({"layout.min_width", BuilderPropertyValueType::Integer, true});
  schema.push_back({"layout.min_height", BuilderPropertyValueType::Integer, true});
  schema.push_back({"layout.preferred_width", BuilderPropertyValueType::Integer, true});
  schema.push_back({"layout.preferred_height", BuilderPropertyValueType::Integer, true});
  schema.push_back({"layout.margin.left", BuilderPropertyValueType::Integer, true});
  schema.push_back({"layout.margin.top", BuilderPropertyValueType::Integer, true});
  schema.push_back({"layout.margin.right", BuilderPropertyValueType::Integer, true});
  schema.push_back({"layout.margin.bottom", BuilderPropertyValueType::Integer, true});
  schema.push_back({"layout.align.horizontal", BuilderPropertyValueType::Enum, true});
  schema.push_back({"layout.align.vertical", BuilderPropertyValueType::Enum, true});
}

inline std::vector<BuilderPropertyDescriptor> property_schema_for_node(const BuilderNode& node) {
  std::vector<BuilderPropertyDescriptor> schema;
  schema.reserve(32);

  schema.push_back({"node.id", BuilderPropertyValueType::String, false});
  schema.push_back({"node.parent_id", BuilderPropertyValueType::String, false});
  schema.push_back({"node.widget_type", BuilderPropertyValueType::Enum, false});
  schema.push_back({"node.container_type", BuilderPropertyValueType::Enum, false});
  schema.push_back({"node.layout_axis", BuilderPropertyValueType::Enum, false});

  append_common_layout_schema(schema);

  if (widget_supports_spacing_and_padding(node.widget_type)) {
    schema.push_back({"layout.spacing", BuilderPropertyValueType::Integer, true});
    schema.push_back({"layout.padding.left", BuilderPropertyValueType::Integer, true});
    schema.push_back({"layout.padding.top", BuilderPropertyValueType::Integer, true});
    schema.push_back({"layout.padding.right", BuilderPropertyValueType::Integer, true});
    schema.push_back({"layout.padding.bottom", BuilderPropertyValueType::Integer, true});
  } else {
    schema.push_back({"layout.spacing", BuilderPropertyValueType::Integer, false});
    schema.push_back({"layout.padding.left", BuilderPropertyValueType::Integer, false});
    schema.push_back({"layout.padding.top", BuilderPropertyValueType::Integer, false});
    schema.push_back({"layout.padding.right", BuilderPropertyValueType::Integer, false});
    schema.push_back({"layout.padding.bottom", BuilderPropertyValueType::Integer, false});
  }

  if (widget_supports_text_property(node.widget_type)) {
    schema.push_back({"text", BuilderPropertyValueType::String, true});
  } else {
    schema.push_back({"text", BuilderPropertyValueType::String, false});
  }

  return schema;
}

inline bool read_node_property_value(
  const BuilderNode& node,
  const std::string& key,
  std::string& value_out) {

  if (key == "node.id") {
    value_out = node.node_id;
  } else if (key == "node.parent_id") {
    value_out = node.parent_id;
  } else if (key == "node.widget_type") {
    value_out = to_string(node.widget_type);
  } else if (key == "node.container_type") {
    value_out = to_string(node.container_type);
  } else if (key == "node.layout_axis") {
    value_out = to_string(node.layout_axis);
  } else if (key == "visible") {
    value_out = node.visible ? "1" : "0";
  } else if (key == "layout.width_policy") {
    value_out = to_string(node.layout.width_policy);
  } else if (key == "layout.height_policy") {
    value_out = to_string(node.layout.height_policy);
  } else if (key == "layout.weight") {
    value_out = std::to_string(node.layout.layout_weight);
  } else if (key == "layout.min_width") {
    value_out = std::to_string(node.layout.min_width);
  } else if (key == "layout.min_height") {
    value_out = std::to_string(node.layout.min_height);
  } else if (key == "layout.preferred_width") {
    value_out = std::to_string(node.layout.preferred_width);
  } else if (key == "layout.preferred_height") {
    value_out = std::to_string(node.layout.preferred_height);
  } else if (key == "layout.spacing") {
    value_out = std::to_string(node.layout.spacing);
  } else if (key == "layout.margin.left") {
    value_out = std::to_string(node.layout.margin.left);
  } else if (key == "layout.margin.top") {
    value_out = std::to_string(node.layout.margin.top);
  } else if (key == "layout.margin.right") {
    value_out = std::to_string(node.layout.margin.right);
  } else if (key == "layout.margin.bottom") {
    value_out = std::to_string(node.layout.margin.bottom);
  } else if (key == "layout.padding.left") {
    value_out = std::to_string(node.layout.padding.left);
  } else if (key == "layout.padding.top") {
    value_out = std::to_string(node.layout.padding.top);
  } else if (key == "layout.padding.right") {
    value_out = std::to_string(node.layout.padding.right);
  } else if (key == "layout.padding.bottom") {
    value_out = std::to_string(node.layout.padding.bottom);
  } else if (key == "layout.align.horizontal") {
    value_out = to_string(node.layout.horizontal_alignment);
  } else if (key == "layout.align.vertical") {
    value_out = to_string(node.layout.vertical_alignment);
  } else if (key == "text") {
    value_out = node.text;
  } else {
    return false;
  }

  return true;
}

inline bool inspect_selected_node_properties(
  const BuilderDocument& doc,
  const BuilderSelectionState& selection,
  BuilderInspectionResult& out,
  std::string* error_out = nullptr) {

  auto fail = [&](const std::string& error) {
    if (error_out != nullptr) {
      *error_out = error;
    }
    return false;
  };

  if (!validate_builder_document(doc, nullptr)) {
    return fail("document invalid");
  }
  if (!selection.has_selection()) {
    return fail("selection is empty");
  }
  if (!node_reachable_from_root(doc, selection.selected_node_id)) {
    return fail("selection references orphan or unknown node");
  }

  const BuilderNode* node = find_node_by_id(doc, selection.selected_node_id);
  if (!node) {
    return fail("selected node missing");
  }

  out = BuilderInspectionResult{};
  out.node_id = node->node_id;

  const std::vector<BuilderPropertyDescriptor> schema = property_schema_for_node(*node);
  out.properties.reserve(schema.size());
  for (const BuilderPropertyDescriptor& descriptor : schema) {
    std::string value;
    if (!read_node_property_value(*node, descriptor.key, value)) {
      return fail("failed to read property value");
    }
    out.properties.push_back({descriptor, std::move(value)});
  }

  return true;
}

inline bool schema_contains_editable_property(
  const std::vector<BuilderPropertyDescriptor>& schema,
  const std::string& key,
  BuilderPropertyValueType* type_out = nullptr) {

  for (const BuilderPropertyDescriptor& descriptor : schema) {
    if (descriptor.key != key) {
      continue;
    }
    if (!descriptor.editable) {
      return false;
    }
    if (type_out != nullptr) {
      *type_out = descriptor.value_type;
    }
    return true;
  }

  return false;
}

inline bool mutate_node_property(BuilderNode& node, const std::string& key, const std::string& value, std::string* error_out = nullptr) {
  auto fail = [&](const std::string& error) {
    if (error_out != nullptr) {
      *error_out = error;
    }
    return false;
  };

  int parsed_int = 0;
  bool parsed_bool = false;

  if (key == "visible") {
    if (!parse_bool01(value, parsed_bool)) {
      return fail("visible must be 0 or 1");
    }
    node.visible = parsed_bool;
    return true;
  }
  if (key == "layout.width_policy") {
    if (!parse_size_policy(value, node.layout.width_policy)) {
      return fail("invalid width policy");
    }
    return true;
  }
  if (key == "layout.height_policy") {
    if (!parse_size_policy(value, node.layout.height_policy)) {
      return fail("invalid height policy");
    }
    return true;
  }
  if (key == "layout.weight") {
    if (!parse_int32(value, parsed_int) || parsed_int <= 0) {
      return fail("layout.weight must be > 0");
    }
    node.layout.layout_weight = parsed_int;
    return true;
  }
  if (key == "layout.min_width") {
    if (!parse_int32(value, parsed_int) || parsed_int < 0) {
      return fail("layout.min_width must be >= 0");
    }
    node.layout.min_width = parsed_int;
    return true;
  }
  if (key == "layout.min_height") {
    if (!parse_int32(value, parsed_int) || parsed_int < 0) {
      return fail("layout.min_height must be >= 0");
    }
    node.layout.min_height = parsed_int;
    return true;
  }
  if (key == "layout.preferred_width") {
    if (!parse_int32(value, parsed_int) || parsed_int < 0) {
      return fail("layout.preferred_width must be >= 0");
    }
    node.layout.preferred_width = parsed_int;
    return true;
  }
  if (key == "layout.preferred_height") {
    if (!parse_int32(value, parsed_int) || parsed_int < 0) {
      return fail("layout.preferred_height must be >= 0");
    }
    node.layout.preferred_height = parsed_int;
    return true;
  }
  if (key == "layout.spacing") {
    if (!parse_int32(value, parsed_int) || parsed_int < 0) {
      return fail("layout.spacing must be >= 0");
    }
    node.layout.spacing = parsed_int;
    return true;
  }
  if (key == "layout.margin.left") {
    if (!parse_int32(value, parsed_int) || parsed_int < 0) {
      return fail("layout.margin.left must be >= 0");
    }
    node.layout.margin.left = parsed_int;
    return true;
  }
  if (key == "layout.margin.top") {
    if (!parse_int32(value, parsed_int) || parsed_int < 0) {
      return fail("layout.margin.top must be >= 0");
    }
    node.layout.margin.top = parsed_int;
    return true;
  }
  if (key == "layout.margin.right") {
    if (!parse_int32(value, parsed_int) || parsed_int < 0) {
      return fail("layout.margin.right must be >= 0");
    }
    node.layout.margin.right = parsed_int;
    return true;
  }
  if (key == "layout.margin.bottom") {
    if (!parse_int32(value, parsed_int) || parsed_int < 0) {
      return fail("layout.margin.bottom must be >= 0");
    }
    node.layout.margin.bottom = parsed_int;
    return true;
  }
  if (key == "layout.padding.left") {
    if (!parse_int32(value, parsed_int) || parsed_int < 0) {
      return fail("layout.padding.left must be >= 0");
    }
    node.layout.padding.left = parsed_int;
    return true;
  }
  if (key == "layout.padding.top") {
    if (!parse_int32(value, parsed_int) || parsed_int < 0) {
      return fail("layout.padding.top must be >= 0");
    }
    node.layout.padding.top = parsed_int;
    return true;
  }
  if (key == "layout.padding.right") {
    if (!parse_int32(value, parsed_int) || parsed_int < 0) {
      return fail("layout.padding.right must be >= 0");
    }
    node.layout.padding.right = parsed_int;
    return true;
  }
  if (key == "layout.padding.bottom") {
    if (!parse_int32(value, parsed_int) || parsed_int < 0) {
      return fail("layout.padding.bottom must be >= 0");
    }
    node.layout.padding.bottom = parsed_int;
    return true;
  }
  if (key == "layout.align.horizontal") {
    if (!parse_alignment(value, node.layout.horizontal_alignment)) {
      return fail("invalid horizontal alignment");
    }
    return true;
  }
  if (key == "layout.align.vertical") {
    if (!parse_alignment(value, node.layout.vertical_alignment)) {
      return fail("invalid vertical alignment");
    }
    return true;
  }
  if (key == "text") {
    node.text = value;
    return true;
  }

  return fail("unsupported property key");
}

inline bool apply_property_update_command(
  BuilderDocument& doc,
  const BuilderPropertyUpdateCommand& command,
  std::string* error_out = nullptr) {

  auto fail = [&](const std::string& error) {
    if (error_out != nullptr) {
      *error_out = error;
    }
    return false;
  };

  if (!validate_builder_document(doc, nullptr)) {
    return fail("document invalid before update");
  }
  if (!is_valid_node_id(command.node_id)) {
    return fail("invalid command node id");
  }

  const BuilderNode* source_node = find_node_by_id(doc, command.node_id);
  if (!source_node) {
    return fail("node not found");
  }
  if (!node_reachable_from_root(doc, command.node_id)) {
    return fail("node is orphaned");
  }

  const std::vector<BuilderPropertyDescriptor> schema = property_schema_for_node(*source_node);
  BuilderPropertyValueType value_type = BuilderPropertyValueType::String;
  if (!schema_contains_editable_property(schema, command.property_key, &value_type)) {
    (void)value_type;
    return fail("property is read-only or unsupported for this node type");
  }

  BuilderDocument candidate = doc;
  BuilderNode* mutable_node = find_node_by_id_mutable(candidate, command.node_id);
  if (!mutable_node) {
    return fail("mutable node lookup failed");
  }

  std::string mutate_error;
  if (!mutate_node_property(*mutable_node, command.property_key, command.property_value, &mutate_error)) {
    return fail(mutate_error);
  }

  std::string validation_error;
  if (!validate_builder_document(candidate, &validation_error)) {
    return fail(validation_error);
  }

  doc = std::move(candidate);
  return true;
}

struct BuilderTreeNodeInfo {
  std::string node_id{};
  std::string parent_id{};
  int sibling_index = -1;
  int child_count = 0;
};

struct BuilderTreeInspectionResult {
  std::vector<BuilderTreeNodeInfo> nodes{};
};

struct BuilderAddChildCommand {
  std::string parent_id{};
  BuilderNode child{};
  int insert_index = -1;
};

struct BuilderRemoveNodeCommand {
  std::string node_id{};
};

struct BuilderMoveSiblingCommand {
  std::string node_id{};
  bool move_up = true;
};

struct BuilderReparentNodeCommand {
  std::string node_id{};
  std::string new_parent_id{};
  int insert_index = -1;
};

inline bool is_leaf_widget_type(BuilderWidgetType type) {
  return !widget_allows_children(type);
}

inline bool allows_child_widget_type(BuilderWidgetType parent, BuilderWidgetType child) {
  if (!widget_allows_children(parent)) {
    return false;
  }

  switch (parent) {
    case BuilderWidgetType::ScrollContainer:
      return child == BuilderWidgetType::VerticalLayout ||
             child == BuilderWidgetType::HorizontalLayout ||
             child == BuilderWidgetType::ContentPanel ||
             child == BuilderWidgetType::SidebarContainer;
    case BuilderWidgetType::ToolbarContainer:
      return child == BuilderWidgetType::Button ||
             child == BuilderWidgetType::InputBox ||
             child == BuilderWidgetType::Label ||
             child == BuilderWidgetType::SectionHeader;
    case BuilderWidgetType::StatusBarContainer:
      return child == BuilderWidgetType::Label ||
             child == BuilderWidgetType::Button ||
             child == BuilderWidgetType::InputBox;
    case BuilderWidgetType::VerticalLayout:
    case BuilderWidgetType::HorizontalLayout:
    case BuilderWidgetType::SidebarContainer:
    case BuilderWidgetType::ContentPanel:
      return true;
    case BuilderWidgetType::Label:
    case BuilderWidgetType::Button:
    case BuilderWidgetType::InputBox:
    case BuilderWidgetType::ListView:
    case BuilderWidgetType::TableView:
    case BuilderWidgetType::SectionHeader:
      return false;
  }

  return false;
}

inline bool parent_child_combination_is_valid(
  const BuilderDocument& doc,
  const std::string& parent_id,
  const std::string& child_id,
  std::string* error_out = nullptr) {

  auto fail = [&](const std::string& error) {
    if (error_out != nullptr) {
      *error_out = error;
    }
    return false;
  };

  const BuilderNode* parent = find_node_by_id(doc, parent_id);
  const BuilderNode* child = find_node_by_id(doc, child_id);
  if (!parent || !child) {
    return fail("parent or child missing");
  }

  if (!widget_allows_children(parent->widget_type)) {
    return fail("parent widget type is leaf-only");
  }
  if (!allows_child_widget_type(parent->widget_type, child->widget_type)) {
    return fail("invalid parent-child widget type combination");
  }

  if (parent->widget_type == BuilderWidgetType::ScrollContainer && parent->child_ids.size() >= 1) {
    return fail("scroll container accepts exactly one child");
  }

  return true;
}

inline std::string generate_next_stable_node_id(const BuilderDocument& doc) {
  int max_suffix = 0;
  for (const BuilderNode& node : doc.nodes) {
    const std::string& id = node.node_id;
    const std::string prefix = "node-";
    if (id.rfind(prefix, 0) != 0 || id.size() <= prefix.size()) {
      continue;
    }
    const std::string suffix = id.substr(prefix.size());
    int parsed = 0;
    if (!parse_int32(suffix, parsed) || parsed <= 0) {
      continue;
    }
    max_suffix = std::max(max_suffix, parsed);
  }
  return make_stable_node_id(max_suffix + 1);
}

inline void collect_subtree_node_ids(
  const BuilderDocument& doc,
  const std::string& root_id,
  std::unordered_set<std::string>& ids_out) {

  if (ids_out.find(root_id) != ids_out.end()) {
    return;
  }
  ids_out.insert(root_id);

  const BuilderNode* node = find_node_by_id(doc, root_id);
  if (!node) {
    return;
  }

  for (const std::string& child_id : node->child_ids) {
    collect_subtree_node_ids(doc, child_id, ids_out);
  }
}

inline bool inspect_tree_structure(
  const BuilderDocument& doc,
  BuilderTreeInspectionResult& out,
  std::string* error_out = nullptr) {

  auto fail = [&](const std::string& error) {
    if (error_out != nullptr) {
      *error_out = error;
    }
    return false;
  };

  if (!validate_builder_document(doc, nullptr)) {
    return fail("document invalid");
  }

  out = BuilderTreeInspectionResult{};
  out.nodes.reserve(doc.nodes.size());

  for (const BuilderNode& node : doc.nodes) {
    BuilderTreeNodeInfo info{};
    info.node_id = node.node_id;
    info.parent_id = node.parent_id;
    info.child_count = static_cast<int>(node.child_ids.size());
    info.sibling_index = 0;

    if (!node.parent_id.empty()) {
      const BuilderNode* parent = find_node_by_id(doc, node.parent_id);
      if (!parent) {
        return fail("parent missing while inspecting tree");
      }

      bool found = false;
      for (std::size_t i = 0; i < parent->child_ids.size(); ++i) {
        if (parent->child_ids[i] == node.node_id) {
          info.sibling_index = static_cast<int>(i);
          found = true;
          break;
        }
      }
      if (!found) {
        return fail("node not present in parent child list");
      }
    }

    out.nodes.push_back(std::move(info));
  }

  std::sort(out.nodes.begin(), out.nodes.end(), [](const BuilderTreeNodeInfo& lhs, const BuilderTreeNodeInfo& rhs) {
    if (lhs.parent_id == rhs.parent_id) {
      if (lhs.sibling_index == rhs.sibling_index) {
        return lhs.node_id < rhs.node_id;
      }
      return lhs.sibling_index < rhs.sibling_index;
    }
    if (lhs.parent_id.empty() != rhs.parent_id.empty()) {
      return lhs.parent_id.empty();
    }
    return lhs.parent_id < rhs.parent_id;
  });

  return true;
}

inline bool apply_add_child_command(
  BuilderDocument& doc,
  const BuilderAddChildCommand& command,
  std::string* added_node_id_out = nullptr,
  std::string* error_out = nullptr) {

  auto fail = [&](const std::string& error) {
    if (error_out != nullptr) {
      *error_out = error;
    }
    return false;
  };

  if (!validate_builder_document(doc, nullptr)) {
    return fail("document invalid before add child");
  }
  if (!is_valid_node_id(command.parent_id)) {
    return fail("invalid parent id");
  }

  const BuilderNode* parent_original = find_node_by_id(doc, command.parent_id);
  if (!parent_original) {
    return fail("parent not found");
  }

  if (!widget_allows_children(parent_original->widget_type)) {
    return fail("parent is leaf-only");
  }

  BuilderDocument candidate = doc;
  BuilderNode* parent = find_node_by_id_mutable(candidate, command.parent_id);
  if (!parent) {
    return fail("mutable parent not found");
  }

  BuilderNode child = command.child;
  child.parent_id = command.parent_id;
  child.child_ids.clear();

  if (child.node_id.empty()) {
    child.node_id = generate_next_stable_node_id(candidate);
  }
  if (!is_valid_node_id(child.node_id)) {
    return fail("child node id invalid");
  }
  if (find_node_by_id(candidate, child.node_id) != nullptr) {
    return fail("child node id already exists");
  }

  if (!allows_child_widget_type(parent->widget_type, child.widget_type)) {
    return fail("invalid parent-child widget type combination");
  }
  if (parent->widget_type == BuilderWidgetType::ScrollContainer && !parent->child_ids.empty()) {
    return fail("scroll container accepts exactly one child");
  }

  const int insert_index =
    (command.insert_index < 0 || command.insert_index > static_cast<int>(parent->child_ids.size()))
      ? static_cast<int>(parent->child_ids.size())
      : command.insert_index;

  const std::string inserted_id = child.node_id;

  parent->child_ids.insert(parent->child_ids.begin() + insert_index, child.node_id);
  candidate.nodes.push_back(std::move(child));

  std::string validation_error;
  if (!validate_builder_document(candidate, &validation_error)) {
    return fail(validation_error);
  }

  if (added_node_id_out != nullptr) {
    *added_node_id_out = inserted_id;
  }
  doc = std::move(candidate);
  return true;
}

inline bool apply_remove_node_command(
  BuilderDocument& doc,
  const BuilderRemoveNodeCommand& command,
  std::string* error_out = nullptr) {

  auto fail = [&](const std::string& error) {
    if (error_out != nullptr) {
      *error_out = error;
    }
    return false;
  };

  if (!validate_builder_document(doc, nullptr)) {
    return fail("document invalid before remove node");
  }
  if (!is_valid_node_id(command.node_id)) {
    return fail("invalid node id");
  }
  if (command.node_id == doc.root_node_id) {
    return fail("root node cannot be removed");
  }

  const BuilderNode* target = find_node_by_id(doc, command.node_id);
  if (!target) {
    return fail("target node missing");
  }

  BuilderDocument candidate = doc;

  BuilderNode* parent = find_node_by_id_mutable(candidate, target->parent_id);
  if (!parent) {
    return fail("target parent missing");
  }

  auto remove_from_parent_it = std::find(parent->child_ids.begin(), parent->child_ids.end(), command.node_id);
  if (remove_from_parent_it == parent->child_ids.end()) {
    return fail("target not found in parent children");
  }
  parent->child_ids.erase(remove_from_parent_it);

  std::unordered_set<std::string> remove_ids;
  collect_subtree_node_ids(candidate, command.node_id, remove_ids);

  std::vector<BuilderNode> kept;
  kept.reserve(candidate.nodes.size());
  for (BuilderNode& node : candidate.nodes) {
    if (remove_ids.find(node.node_id) == remove_ids.end()) {
      kept.push_back(std::move(node));
    }
  }
  candidate.nodes = std::move(kept);

  std::string validation_error;
  if (!validate_builder_document(candidate, &validation_error)) {
    return fail(validation_error);
  }

  doc = std::move(candidate);
  return true;
}

inline bool apply_move_sibling_command(
  BuilderDocument& doc,
  const BuilderMoveSiblingCommand& command,
  std::string* error_out = nullptr) {

  auto fail = [&](const std::string& error) {
    if (error_out != nullptr) {
      *error_out = error;
    }
    return false;
  };

  if (!validate_builder_document(doc, nullptr)) {
    return fail("document invalid before move sibling");
  }
  if (!is_valid_node_id(command.node_id)) {
    return fail("invalid node id");
  }

  const BuilderNode* node = find_node_by_id(doc, command.node_id);
  if (!node) {
    return fail("node not found");
  }
  if (node->parent_id.empty()) {
    return fail("root node cannot be reordered");
  }

  BuilderDocument candidate = doc;
  BuilderNode* parent = find_node_by_id_mutable(candidate, node->parent_id);
  if (!parent) {
    return fail("parent missing");
  }

  auto it = std::find(parent->child_ids.begin(), parent->child_ids.end(), command.node_id);
  if (it == parent->child_ids.end()) {
    return fail("node missing from parent child list");
  }

  const std::size_t index = static_cast<std::size_t>(std::distance(parent->child_ids.begin(), it));
  if (command.move_up) {
    if (index == 0) {
      return fail("node already at first sibling position");
    }
    std::swap(parent->child_ids[index], parent->child_ids[index - 1]);
  } else {
    if (index + 1 >= parent->child_ids.size()) {
      return fail("node already at last sibling position");
    }
    std::swap(parent->child_ids[index], parent->child_ids[index + 1]);
  }

  std::string validation_error;
  if (!validate_builder_document(candidate, &validation_error)) {
    return fail(validation_error);
  }

  doc = std::move(candidate);
  return true;
}

inline bool apply_reparent_node_command(
  BuilderDocument& doc,
  const BuilderReparentNodeCommand& command,
  std::string* error_out = nullptr) {

  auto fail = [&](const std::string& error) {
    if (error_out != nullptr) {
      *error_out = error;
    }
    return false;
  };

  if (!validate_builder_document(doc, nullptr)) {
    return fail("document invalid before reparent");
  }
  if (!is_valid_node_id(command.node_id) || !is_valid_node_id(command.new_parent_id)) {
    return fail("invalid node id in reparent command");
  }
  if (command.node_id == doc.root_node_id) {
    return fail("root node cannot be reparented");
  }
  if (command.node_id == command.new_parent_id) {
    return fail("node cannot be reparented to itself");
  }

  const BuilderNode* node = find_node_by_id(doc, command.node_id);
  const BuilderNode* new_parent = find_node_by_id(doc, command.new_parent_id);
  if (!node || !new_parent) {
    return fail("node or new parent missing");
  }

  if (!widget_allows_children(new_parent->widget_type)) {
    return fail("new parent is leaf-only");
  }
  if (!allows_child_widget_type(new_parent->widget_type, node->widget_type)) {
    return fail("invalid parent-child combination for reparent");
  }

  std::unordered_set<std::string> subtree;
  collect_subtree_node_ids(doc, command.node_id, subtree);
  if (subtree.find(command.new_parent_id) != subtree.end()) {
    return fail("cannot reparent node under its own subtree");
  }

  if (new_parent->widget_type == BuilderWidgetType::ScrollContainer && !new_parent->child_ids.empty()) {
    return fail("scroll container accepts exactly one child");
  }

  BuilderDocument candidate = doc;
  BuilderNode* mutable_node = find_node_by_id_mutable(candidate, command.node_id);
  if (!mutable_node) {
    return fail("mutable node missing");
  }

  BuilderNode* old_parent = find_node_by_id_mutable(candidate, mutable_node->parent_id);
  BuilderNode* mutable_new_parent = find_node_by_id_mutable(candidate, command.new_parent_id);
  if (!old_parent || !mutable_new_parent) {
    return fail("old or new parent missing");
  }

  auto old_it = std::find(old_parent->child_ids.begin(), old_parent->child_ids.end(), command.node_id);
  if (old_it == old_parent->child_ids.end()) {
    return fail("node not listed in old parent children");
  }
  old_parent->child_ids.erase(old_it);

  const int insert_index =
    (command.insert_index < 0 || command.insert_index > static_cast<int>(mutable_new_parent->child_ids.size()))
      ? static_cast<int>(mutable_new_parent->child_ids.size())
      : command.insert_index;
  mutable_new_parent->child_ids.insert(mutable_new_parent->child_ids.begin() + insert_index, command.node_id);
  mutable_node->parent_id = command.new_parent_id;

  std::string validation_error;
  if (!validate_builder_document(candidate, &validation_error)) {
    return fail(validation_error);
  }

  doc = std::move(candidate);
  return true;
}

inline BuilderDocument make_phase103_2_sample_document() {
  BuilderDocument doc{};
  doc.schema_version = kBuilderSchemaVersion;
  doc.root_node_id = make_stable_node_id(1);

  BuilderNode root{};
  root.node_id = make_stable_node_id(1);
  root.parent_id = "";
  root.widget_type = BuilderWidgetType::VerticalLayout;
  root.container_type = BuilderContainerType::Shell;
  root.layout_axis = BuilderAxis::Vertical;
  root.layout.width_policy = BuilderSizePolicy::Fill;
  root.layout.height_policy = BuilderSizePolicy::Fill;
  root.layout.layout_weight = 1;
  root.layout.min_width = 320;
  root.layout.min_height = 220;
  root.layout.padding = BuilderInsets{12, 12, 12, 12};
  root.layout.spacing = 8;
  root.layout.horizontal_alignment = BuilderAlignment::Stretch;
  root.layout.vertical_alignment = BuilderAlignment::Stretch;
  root.child_ids = {make_stable_node_id(2), make_stable_node_id(3), make_stable_node_id(4)};

  BuilderNode toolbar{};
  toolbar.node_id = make_stable_node_id(2);
  toolbar.parent_id = root.node_id;
  toolbar.widget_type = BuilderWidgetType::ToolbarContainer;
  toolbar.container_type = BuilderContainerType::Toolbar;
  toolbar.layout_axis = BuilderAxis::Horizontal;
  toolbar.layout.width_policy = BuilderSizePolicy::Fill;
  toolbar.layout.height_policy = BuilderSizePolicy::Fixed;
  toolbar.layout.layout_weight = 1;
  toolbar.layout.min_height = 42;
  toolbar.layout.preferred_height = 42;
  toolbar.layout.padding = BuilderInsets{8, 6, 8, 6};
  toolbar.layout.spacing = 8;
  toolbar.layout.horizontal_alignment = BuilderAlignment::Stretch;
  toolbar.layout.vertical_alignment = BuilderAlignment::Center;
  toolbar.child_ids = {make_stable_node_id(5), make_stable_node_id(6)};

  BuilderNode content_row{};
  content_row.node_id = make_stable_node_id(3);
  content_row.parent_id = root.node_id;
  content_row.widget_type = BuilderWidgetType::HorizontalLayout;
  content_row.container_type = BuilderContainerType::Content;
  content_row.layout_axis = BuilderAxis::Horizontal;
  content_row.layout.width_policy = BuilderSizePolicy::Fill;
  content_row.layout.height_policy = BuilderSizePolicy::Fill;
  content_row.layout.layout_weight = 1;
  content_row.layout.min_height = 120;
  content_row.layout.padding = BuilderInsets{0, 0, 0, 0};
  content_row.layout.spacing = 10;
  content_row.layout.horizontal_alignment = BuilderAlignment::Stretch;
  content_row.layout.vertical_alignment = BuilderAlignment::Stretch;
  content_row.child_ids = {make_stable_node_id(7), make_stable_node_id(8)};

  BuilderNode status_bar{};
  status_bar.node_id = make_stable_node_id(4);
  status_bar.parent_id = root.node_id;
  status_bar.widget_type = BuilderWidgetType::StatusBarContainer;
  status_bar.container_type = BuilderContainerType::StatusBar;
  status_bar.layout_axis = BuilderAxis::Horizontal;
  status_bar.layout.width_policy = BuilderSizePolicy::Fill;
  status_bar.layout.height_policy = BuilderSizePolicy::Fixed;
  status_bar.layout.layout_weight = 1;
  status_bar.layout.min_height = 28;
  status_bar.layout.preferred_height = 28;
  status_bar.layout.padding = BuilderInsets{8, 4, 8, 4};
  status_bar.layout.horizontal_alignment = BuilderAlignment::Stretch;
  status_bar.layout.vertical_alignment = BuilderAlignment::End;
  status_bar.child_ids = {make_stable_node_id(9)};

  BuilderNode title{};
  title.node_id = make_stable_node_id(5);
  title.parent_id = toolbar.node_id;
  title.widget_type = BuilderWidgetType::SectionHeader;
  title.container_type = BuilderContainerType::None;
  title.layout_axis = BuilderAxis::None;
  title.layout.width_policy = BuilderSizePolicy::Fixed;
  title.layout.height_policy = BuilderSizePolicy::Fixed;
  title.layout.layout_weight = 1;
  title.layout.min_height = 28;
  title.layout.preferred_height = 28;
  title.layout.horizontal_alignment = BuilderAlignment::Start;
  title.layout.vertical_alignment = BuilderAlignment::Center;
  title.text = "Builder Sample";

  BuilderNode open_button{};
  open_button.node_id = make_stable_node_id(6);
  open_button.parent_id = toolbar.node_id;
  open_button.widget_type = BuilderWidgetType::Button;
  open_button.container_type = BuilderContainerType::None;
  open_button.layout_axis = BuilderAxis::None;
  open_button.layout.width_policy = BuilderSizePolicy::Fixed;
  open_button.layout.height_policy = BuilderSizePolicy::Fixed;
  open_button.layout.layout_weight = 1;
  open_button.layout.min_width = 90;
  open_button.layout.min_height = 32;
  open_button.layout.horizontal_alignment = BuilderAlignment::Start;
  open_button.layout.vertical_alignment = BuilderAlignment::Center;
  open_button.text = "Open";

  BuilderNode sidebar{};
  sidebar.node_id = make_stable_node_id(7);
  sidebar.parent_id = content_row.node_id;
  sidebar.widget_type = BuilderWidgetType::SidebarContainer;
  sidebar.container_type = BuilderContainerType::Sidebar;
  sidebar.layout_axis = BuilderAxis::Vertical;
  sidebar.layout.width_policy = BuilderSizePolicy::Fill;
  sidebar.layout.height_policy = BuilderSizePolicy::Fill;
  sidebar.layout.layout_weight = 2;
  sidebar.layout.min_width = 180;
  sidebar.layout.padding = BuilderInsets{8, 8, 8, 8};
  sidebar.layout.horizontal_alignment = BuilderAlignment::Stretch;
  sidebar.layout.vertical_alignment = BuilderAlignment::Stretch;

  BuilderNode detail{};
  detail.node_id = make_stable_node_id(8);
  detail.parent_id = content_row.node_id;
  detail.widget_type = BuilderWidgetType::ContentPanel;
  detail.container_type = BuilderContainerType::Content;
  detail.layout_axis = BuilderAxis::Vertical;
  detail.layout.width_policy = BuilderSizePolicy::Fill;
  detail.layout.height_policy = BuilderSizePolicy::Fill;
  detail.layout.layout_weight = 3;
  detail.layout.min_width = 240;
  detail.layout.padding = BuilderInsets{8, 8, 8, 8};
  detail.layout.horizontal_alignment = BuilderAlignment::Stretch;
  detail.layout.vertical_alignment = BuilderAlignment::Stretch;

  BuilderNode status_text{};
  status_text.node_id = make_stable_node_id(9);
  status_text.parent_id = status_bar.node_id;
  status_text.widget_type = BuilderWidgetType::Label;
  status_text.container_type = BuilderContainerType::None;
  status_text.layout_axis = BuilderAxis::None;
  status_text.layout.width_policy = BuilderSizePolicy::Fill;
  status_text.layout.height_policy = BuilderSizePolicy::Fixed;
  status_text.layout.layout_weight = 1;
  status_text.layout.min_height = 20;
  status_text.layout.horizontal_alignment = BuilderAlignment::Stretch;
  status_text.layout.vertical_alignment = BuilderAlignment::Center;
  status_text.text = "Ready";

  doc.nodes = {
    root,
    toolbar,
    content_row,
    status_bar,
    title,
    open_button,
    sidebar,
    detail,
    status_text,
  };

  return doc;
}

} // namespace ngk::ui::builder
