// desktop_file_tool_row_state_helpers.h
// Row-state query helpers: visible-row index lookup and row bounds computation.
// Included inside namespace{} in main.cpp, after widget headers are in scope.
// Must NOT be included anywhere else.

template <std::size_t N>
std::size_t find_visible_row_index(
    const std::string&                    node_id,
    const std::array<ngk::ui::Button, N>& buttons,
    const std::array<std::string, N>&     row_ids)
{
  if (node_id.empty()) { return N; }
  for (std::size_t idx = 0; idx < N; ++idx) {
    if (!buttons[idx].visible()) { continue; }
    if (row_ids[idx] == node_id) { return idx; }
  }
  return N;
}

template <std::size_t N>
bool compute_row_bounds(
    std::size_t                           target_index,
    const std::array<ngk::ui::Button, N>& buttons,
    int                                   spacing,
    int                                   padding_top,
    int&                                  top_out,
    int&                                  bottom_out)
{
  int cursor_y = padding_top;
  for (std::size_t idx = 0; idx < N; ++idx) {
    const auto& row = buttons[idx];
    if (!row.visible()) { continue; }
    const int row_height = row.preferred_height() > 0 ? row.preferred_height() : row.height();
    if (idx == target_index) {
      top_out    = cursor_y;
      bottom_out = cursor_y + row_height;
      return true;
    }
    cursor_y += row_height + spacing;
  }
  return false;
}

template <std::size_t N>
std::string find_first_visible_row_node_id(
    const std::array<ngk::ui::Button, N>& buttons,
    const std::array<std::string, N>&     row_ids,
    int                                   spacing,
    int                                   padding_top,
    int                                   viewport_top)
{
  for (std::size_t idx = 0; idx < N; ++idx) {
    if (!buttons[idx].visible() || row_ids[idx].empty()) { continue; }
    int row_top = 0;
    int row_bottom = 0;
    if (!compute_row_bounds(idx, buttons, spacing, padding_top, row_top, row_bottom)) { continue; }
    if (row_bottom > viewport_top) { return row_ids[idx]; }
  }
  return std::string{};
}

inline int compute_scroll_offset_to_reveal(int row_top, int row_bottom, int current_offset, int viewport_height)
{
  int desired_offset = current_offset;
  if (row_top < current_offset) {
    desired_offset = row_top;
  } else if (row_bottom > current_offset + viewport_height) {
    desired_offset = row_bottom - viewport_height;
  }
  return desired_offset;
}

template <std::size_t N>
bool row_fully_visible_in_viewport(
    const std::string&                    node_id,
    const std::array<ngk::ui::Button, N>& buttons,
    const std::array<std::string, N>&     row_ids,
    int                                   spacing,
    int                                   padding_top,
    int                                   viewport_top,
    int                                   viewport_height)
{
  const std::size_t row_index = find_visible_row_index(node_id, buttons, row_ids);
  if (row_index >= N) { return false; }
  int row_top = 0;
  int row_bottom = 0;
  if (!compute_row_bounds(row_index, buttons, spacing, padding_top, row_top, row_bottom)) { return false; }
  return row_top >= viewport_top && row_bottom <= viewport_top + viewport_height;
}

template <std::size_t N>
std::string resolve_scroll_target_id(
    const std::string&                    priority_id,
    const std::string&                    fallback_id,
    const std::array<ngk::ui::Button, N>& buttons,
    const std::array<std::string, N>&     row_ids)
{
  if (!priority_id.empty() && find_visible_row_index(priority_id, buttons, row_ids) < N) {
    return priority_id;
  }
  if (!fallback_id.empty() && find_visible_row_index(fallback_id, buttons, row_ids) < N) {
    return fallback_id;
  }
  return std::string{};
}

template <std::size_t N>
bool compute_target_row_bounds(
    const std::string&                    target_id,
    const std::array<ngk::ui::Button, N>& buttons,
    const std::array<std::string, N>&     row_ids,
    int                                   spacing,
    int                                   padding_top,
    int&                                  top_out,
    int&                                  bottom_out)
{
  const std::size_t row_index = find_visible_row_index(target_id, buttons, row_ids);
  if (row_index >= N) { return false; }
  return compute_row_bounds(row_index, buttons, spacing, padding_top, top_out, bottom_out);
}

template <std::size_t N>
bool is_row_visible(
    const std::string&                    node_id,
    const std::array<ngk::ui::Button, N>& buttons,
    const std::array<std::string, N>&     row_ids)
{
  return find_visible_row_index(node_id, buttons, row_ids) < N;
}

template <std::size_t N>
inline std::vector<std::string> collect_visible_row_ids(
    const std::array<ngk::ui::Button, N>& buttons,
    const std::array<std::string, N>&     row_ids)
{
  std::vector<std::string> ids{};
  for (std::size_t idx = 0; idx < N; ++idx) {
    if (!buttons[idx].visible() || row_ids[idx].empty()) { continue; }
    ids.push_back(row_ids[idx]);
  }
  return ids;
}

template <std::size_t TRows, std::size_t PRows>
inline bool visible_rows_nodes_all_exist(
    const std::array<ngk::ui::Button, TRows>&        tree_buttons,
    const std::array<std::string, TRows>&            tree_ids,
    const std::array<ngk::ui::Button, PRows>&        preview_buttons,
    const std::array<std::string, PRows>&            preview_ids,
    const ngk::ui::builder::BuilderDocument&         doc)
{
  for (std::size_t idx = 0; idx < TRows; ++idx) {
    if (!tree_buttons[idx].visible() || tree_ids[idx].empty()) { continue; }
    bool found = false;
    for (const auto& n : doc.nodes) {
      if (n.node_id == tree_ids[idx]) { found = true; break; }
    }
    if (!found) { return false; }
  }
  for (std::size_t idx = 0; idx < PRows; ++idx) {
    if (!preview_buttons[idx].visible() || preview_ids[idx].empty()) { continue; }
    bool found = false;
    for (const auto& n : doc.nodes) {
      if (n.node_id == preview_ids[idx]) { found = true; break; }
    }
    if (!found) { return false; }
  }
  return true;
}
