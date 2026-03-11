#pragma once

#include <algorithm>
#include <vector>
#include <string>

#ifndef NOMINMAX
#define NOMINMAX
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include "ui_element.hpp"

namespace ngk::ui::text_painter {

inline int content_padding_left() {
  return 8;
}

inline int text_origin_x(const UIElement& element) {
  return element.x() + content_padding_left();
}

inline int text_line_height() {
  HDC dc = GetDC(nullptr);
  if (!dc) {
    return 16;
  }

  TEXTMETRICA metrics{};
  const bool ok = GetTextMetricsA(dc, &metrics) != 0;
  ReleaseDC(nullptr, dc);
  return ok ? metrics.tmHeight : 16;
}

inline int measure_text_width(const std::string& text) {
  if (text.empty()) {
    return 0;
  }

  HDC dc = GetDC(nullptr);
  if (!dc) {
    return static_cast<int>(text.size()) * 8;
  }

  SIZE size{};
  const bool ok = GetTextExtentPoint32A(dc, text.c_str(), static_cast<int>(text.size()), &size) != 0;
  ReleaseDC(nullptr, dc);
  if (!ok) {
    return static_cast<int>(text.size()) * 8;
  }

  return size.cx;
}

inline int measure_prefix_width(const std::string& text, int index) {
  if (index <= 0 || text.empty()) {
    return 0;
  }

  const int clamped = std::min(index, static_cast<int>(text.size()));
  return measure_text_width(text.substr(0, static_cast<std::size_t>(clamped)));
}

inline int caret_index_from_x(const std::string& text, int local_x) {
  if (local_x <= 0 || text.empty()) {
    return 0;
  }

  const int count = static_cast<int>(text.size());
  int prev_width = 0;
  for (int index = 1; index <= count; ++index) {
    const int width = measure_prefix_width(text, index);
    const int midpoint = prev_width + ((width - prev_width) / 2);
    if (local_x < midpoint) {
      return index - 1;
    }
    if (local_x < width) {
      return index;
    }
    prev_width = width;
  }

  return count;
}

inline int baseline_y(const UIElement& element) {
  const int paddingY = 7;
  if (element.height() <= 0) {
    return element.y() + paddingY;
  }

  const int centered = element.y() + std::max(0, (element.height() - 18) / 2);
  return centered;
}

inline void draw(
  UIElement& element,
  UIElement::Renderer& renderer,
  const std::string& text,
  float r = 0.95f,
  float g = 0.95f,
  float b = 0.95f,
  float a = 1.0f)
{
  if (!element.visible() || text.empty()) {
    return;
  }

  const int x = text_origin_x(element);
  const int y = baseline_y(element);
  renderer.queue_text(x, y, text, r, g, b, a);
}

inline void draw_at(
  UIElement::Renderer& renderer,
  int x,
  int y,
  const std::string& text,
  float r,
  float g,
  float b,
  float a = 1.0f)
{
  if (text.empty()) {
    return;
  }

  renderer.queue_text(x, y, text, r, g, b, a);
}

inline void draw_text_title(UIElement::Renderer& renderer, int x, int y, const std::string& text) {
  draw_at(renderer, x + 1, y + 1, text, 0.10f, 0.12f, 0.16f, 0.95f);
  draw_at(renderer, x, y, text, 0.96f, 0.97f, 0.99f, 1.0f);
}

inline void draw_text_label(UIElement::Renderer& renderer, int x, int y, const std::string& text) {
  draw_at(renderer, x, y, text, 0.74f, 0.80f, 0.88f, 1.0f);
}

inline void draw_text_body(UIElement::Renderer& renderer, int x, int y, const std::string& text) {
  draw_at(renderer, x, y, text, 0.90f, 0.92f, 0.96f, 1.0f);
}

inline void draw_text_status(UIElement::Renderer& renderer, int x, int y, const std::string& text) {
  draw_at(renderer, x, y, text, 0.64f, 0.90f, 0.78f, 1.0f);
}

inline void draw_text_numeric(UIElement::Renderer& renderer, int x, int y, const std::string& text) {
  draw_at(renderer, x + 1, y + 1, text, 0.08f, 0.10f, 0.14f, 0.90f);
  draw_at(renderer, x, y, text, 0.98f, 0.88f, 0.26f, 1.0f);
}

} // namespace ngk::ui::text_painter
