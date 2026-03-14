#pragma once

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <string>

#include "ui_element.hpp"

namespace ngk::ui::text_painter {

inline int text_origin_x(const UIElement& element) {
  return element.x() + 8;
}

inline int baseline_y(const UIElement& element) {
  return element.y() + 10;
}

inline int text_line_height() {
  return 16;
}

inline int measure_prefix_width(const std::string& text, int index) {
  if (index < 0) {
    index = 0;
  }
  if (index > static_cast<int>(text.size())) {
    index = static_cast<int>(text.size());
  }
  return index * 8;
}

inline int caret_index_from_x(const std::string& text, int x) {
  if (x <= 0) {
    return 0;
  }
  const int idx = x / 8;
  return std::clamp(idx, 0, static_cast<int>(text.size()));
}

inline std::uint8_t glyph_row_5x7(char ch, int row) {
  const unsigned char uch = static_cast<unsigned char>(ch);
  const char c = static_cast<char>(std::toupper(uch));

  switch (c) {
    case 'A': { static constexpr std::uint8_t g[7] = {0x0E,0x11,0x11,0x1F,0x11,0x11,0x11}; return g[row]; }
    case 'B': { static constexpr std::uint8_t g[7] = {0x1E,0x11,0x11,0x1E,0x11,0x11,0x1E}; return g[row]; }
    case 'C': { static constexpr std::uint8_t g[7] = {0x0E,0x11,0x10,0x10,0x10,0x11,0x0E}; return g[row]; }
    case 'D': { static constexpr std::uint8_t g[7] = {0x1C,0x12,0x11,0x11,0x11,0x12,0x1C}; return g[row]; }
    case 'E': { static constexpr std::uint8_t g[7] = {0x1F,0x10,0x10,0x1E,0x10,0x10,0x1F}; return g[row]; }
    case 'F': { static constexpr std::uint8_t g[7] = {0x1F,0x10,0x10,0x1E,0x10,0x10,0x10}; return g[row]; }
    case 'G': { static constexpr std::uint8_t g[7] = {0x0E,0x11,0x10,0x10,0x13,0x11,0x0F}; return g[row]; }
    case 'H': { static constexpr std::uint8_t g[7] = {0x11,0x11,0x11,0x1F,0x11,0x11,0x11}; return g[row]; }
    case 'I': { static constexpr std::uint8_t g[7] = {0x1F,0x04,0x04,0x04,0x04,0x04,0x1F}; return g[row]; }
    case 'J': { static constexpr std::uint8_t g[7] = {0x1F,0x02,0x02,0x02,0x12,0x12,0x0C}; return g[row]; }
    case 'K': { static constexpr std::uint8_t g[7] = {0x11,0x12,0x14,0x18,0x14,0x12,0x11}; return g[row]; }
    case 'L': { static constexpr std::uint8_t g[7] = {0x10,0x10,0x10,0x10,0x10,0x10,0x1F}; return g[row]; }
    case 'M': { static constexpr std::uint8_t g[7] = {0x11,0x1B,0x15,0x15,0x11,0x11,0x11}; return g[row]; }
    case 'N': { static constexpr std::uint8_t g[7] = {0x11,0x19,0x15,0x13,0x11,0x11,0x11}; return g[row]; }
    case 'O': { static constexpr std::uint8_t g[7] = {0x0E,0x11,0x11,0x11,0x11,0x11,0x0E}; return g[row]; }
    case 'P': { static constexpr std::uint8_t g[7] = {0x1E,0x11,0x11,0x1E,0x10,0x10,0x10}; return g[row]; }
    case 'Q': { static constexpr std::uint8_t g[7] = {0x0E,0x11,0x11,0x11,0x15,0x12,0x0D}; return g[row]; }
    case 'R': { static constexpr std::uint8_t g[7] = {0x1E,0x11,0x11,0x1E,0x14,0x12,0x11}; return g[row]; }
    case 'S': { static constexpr std::uint8_t g[7] = {0x0F,0x10,0x10,0x0E,0x01,0x01,0x1E}; return g[row]; }
    case 'T': { static constexpr std::uint8_t g[7] = {0x1F,0x04,0x04,0x04,0x04,0x04,0x04}; return g[row]; }
    case 'U': { static constexpr std::uint8_t g[7] = {0x11,0x11,0x11,0x11,0x11,0x11,0x0E}; return g[row]; }
    case 'V': { static constexpr std::uint8_t g[7] = {0x11,0x11,0x11,0x11,0x11,0x0A,0x04}; return g[row]; }
    case 'W': { static constexpr std::uint8_t g[7] = {0x11,0x11,0x11,0x15,0x15,0x15,0x0A}; return g[row]; }
    case 'X': { static constexpr std::uint8_t g[7] = {0x11,0x11,0x0A,0x04,0x0A,0x11,0x11}; return g[row]; }
    case 'Y': { static constexpr std::uint8_t g[7] = {0x11,0x11,0x0A,0x04,0x04,0x04,0x04}; return g[row]; }
    case 'Z': { static constexpr std::uint8_t g[7] = {0x1F,0x01,0x02,0x04,0x08,0x10,0x1F}; return g[row]; }
    case '0': { static constexpr std::uint8_t g[7] = {0x0E,0x11,0x13,0x15,0x19,0x11,0x0E}; return g[row]; }
    case '1': { static constexpr std::uint8_t g[7] = {0x04,0x0C,0x04,0x04,0x04,0x04,0x0E}; return g[row]; }
    case '2': { static constexpr std::uint8_t g[7] = {0x0E,0x11,0x01,0x02,0x04,0x08,0x1F}; return g[row]; }
    case '3': { static constexpr std::uint8_t g[7] = {0x1E,0x01,0x01,0x0E,0x01,0x01,0x1E}; return g[row]; }
    case '4': { static constexpr std::uint8_t g[7] = {0x02,0x06,0x0A,0x12,0x1F,0x02,0x02}; return g[row]; }
    case '5': { static constexpr std::uint8_t g[7] = {0x1F,0x10,0x10,0x1E,0x01,0x01,0x1E}; return g[row]; }
    case '6': { static constexpr std::uint8_t g[7] = {0x0E,0x10,0x10,0x1E,0x11,0x11,0x0E}; return g[row]; }
    case '7': { static constexpr std::uint8_t g[7] = {0x1F,0x01,0x02,0x04,0x08,0x08,0x08}; return g[row]; }
    case '8': { static constexpr std::uint8_t g[7] = {0x0E,0x11,0x11,0x0E,0x11,0x11,0x0E}; return g[row]; }
    case '9': { static constexpr std::uint8_t g[7] = {0x0E,0x11,0x11,0x0F,0x01,0x01,0x0E}; return g[row]; }
    case ':': { static constexpr std::uint8_t g[7] = {0x00,0x04,0x04,0x00,0x04,0x04,0x00}; return g[row]; }
    case '.': { static constexpr std::uint8_t g[7] = {0x00,0x00,0x00,0x00,0x00,0x04,0x04}; return g[row]; }
    case '-': { static constexpr std::uint8_t g[7] = {0x00,0x00,0x00,0x1F,0x00,0x00,0x00}; return g[row]; }
    case '_': { static constexpr std::uint8_t g[7] = {0x00,0x00,0x00,0x00,0x00,0x00,0x1F}; return g[row]; }
    case '/': { static constexpr std::uint8_t g[7] = {0x01,0x02,0x02,0x04,0x08,0x08,0x10}; return g[row]; }
    default: {
      static constexpr std::uint8_t g[7] = {0x1F,0x11,0x01,0x06,0x08,0x00,0x08};
      return g[row];
    }
  }
}

inline void draw(const UIElement& element, UIElement::Renderer& renderer, const std::string& text, float r, float g, float b, float a) {
  if (text.empty() || element.width() <= 0 || element.height() <= 0) {
    return;
  }

  const int glyph_w = 5;
  const int glyph_h = 7;
  const int glyph_gap = 2;
  const int line_h = text_line_height();

  int cursor_x = text_origin_x(element);
  int cursor_y = baseline_y(element);
  const int min_x = element.x() + 2;
  const int max_x = element.x() + std::max(0, element.width() - 2);
  const int max_y = element.y() + std::max(0, element.height() - 2);

  for (char ch : text) {
    if (ch == '\n') {
      cursor_x = text_origin_x(element);
      cursor_y += line_h;
      if (cursor_y + glyph_h > max_y) {
        break;
      }
      continue;
    }

    if (cursor_x < min_x) {
      cursor_x = min_x;
    }

    if (cursor_x + glyph_w > max_x) {
      cursor_x = text_origin_x(element);
      cursor_y += line_h;
      if (cursor_y + glyph_h > max_y) {
        break;
      }
    }

    if (ch != ' ' && ch != '\t') {
      for (int row = 0; row < glyph_h; ++row) {
        const std::uint8_t mask = glyph_row_5x7(ch, row);
        for (int col = 0; col < glyph_w; ++col) {
          if ((mask & (1u << (glyph_w - 1 - col))) != 0u) {
            renderer.queue_rect(cursor_x + col, cursor_y + row, 1, 1, r, g, b, a);
          }
        }
      }
    }

    cursor_x += glyph_w + glyph_gap;
  }
}

} // namespace ngk::ui::text_painter
