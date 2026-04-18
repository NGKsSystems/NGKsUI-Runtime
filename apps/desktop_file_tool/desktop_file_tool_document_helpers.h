// desktop_file_tool_document_helpers.h
// Pure document-level query helpers.
// Included at file scope inside the anonymous namespace in main.cpp.
// Must NOT be included anywhere else.

inline bool document_has_unique_node_ids(const ngk::ui::builder::BuilderDocument& doc) {
  std::vector<std::string> seen{};
  for (const auto& node : doc.nodes) {
    if (node.node_id.empty()) {
      return false;
    }
    if (std::find(seen.begin(), seen.end(), node.node_id) != seen.end()) {
      return false;
    }
    seen.push_back(node.node_id);
  }
  return seen.size() == doc.nodes.size();
}

inline std::string build_document_signature(
    const ngk::ui::builder::BuilderDocument& doc,
    const char* context_name)
{
  std::string error;
  if (!ngk::ui::builder::validate_builder_document(doc, &error)) {
    return std::string("invalid:") + (context_name == nullptr ? "document" : context_name) + ":" + error;
  }
  const std::string serialized = ngk::ui::builder::serialize_builder_document_deterministic(doc);
  if (serialized.empty()) {
    return std::string("invalid:") + (context_name == nullptr ? "document" : context_name) + ":serialize_failed";
  }
  return serialized;
}

inline std::string current_document_signature(
    const ngk::ui::builder::BuilderDocument& doc)
{
  return ngk::ui::builder::serialize_builder_document_deterministic(doc);
}
