#pragma once

#include <string>

#include "horizontal_layout.hpp"
#include "label.hpp"
#include "vertical_layout.hpp"

namespace ngk::ui {

class ToolbarContainer : public HorizontalLayout {
public:
  explicit ToolbarContainer(int spacing = 8) : HorizontalLayout(spacing) {
    set_background(0.14f, 0.17f, 0.24f, 1.0f);
    set_padding(8, 6, 8, 6);
    set_min_size(0, 42);
    set_preferred_size(0, 42);
  }
};

class SidebarContainer : public VerticalLayout {
public:
  explicit SidebarContainer(int spacing = 8) : VerticalLayout(spacing) {
    set_background(0.11f, 0.13f, 0.18f, 0.98f);
    set_padding(10);
    set_min_size(240, 0);
  }
};

class StatusBarContainer : public HorizontalLayout {
public:
  explicit StatusBarContainer(int spacing = 6) : HorizontalLayout(spacing) {
    set_background(0.10f, 0.12f, 0.16f, 0.98f);
    set_padding(8, 4, 8, 4);
    set_min_size(0, 28);
    set_preferred_size(0, 28);
  }
};

class SectionHeader : public Label {
public:
  SectionHeader() = default;
  explicit SectionHeader(std::string text) : Label(std::move(text)) {
    set_background(0.16f, 0.18f, 0.24f, 1.0f);
    set_min_size(0, 28);
    set_preferred_size(0, 28);
  }
};

class ContentPanel : public VerticalLayout {
public:
  explicit ContentPanel(int spacing = 8) : VerticalLayout(spacing) {
    set_background(0.11f, 0.13f, 0.18f, 0.98f);
    set_padding(10);
  }
};

} // namespace ngk::ui
