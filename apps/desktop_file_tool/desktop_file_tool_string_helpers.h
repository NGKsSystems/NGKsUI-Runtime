// desktop_file_tool_string_helpers.h
// Pure string utility helpers.
// Included at file scope inside the anonymous namespace in main.cpp.
// Must NOT be included anywhere else.

inline std::string join_ids(const std::vector<std::string>& ids) {
  std::ostringstream oss;
  for (std::size_t idx = 0; idx < ids.size(); ++idx) {
    if (idx > 0) {
      oss << ",";
    }
    oss << ids[idx];
  }
  return oss.str();
}

inline std::string pad_int(int value, int width) {
  std::string text = std::to_string(value);
  if (text.size() >= static_cast<std::size_t>(width)) {
    return text;
  }
  return std::string(static_cast<std::size_t>(width) - text.size(), '0') + text;
}
