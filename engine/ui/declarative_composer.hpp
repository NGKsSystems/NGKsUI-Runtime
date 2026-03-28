#pragma once

#include <functional>
#include <string>
#include <utility>
#include <vector>

#include "button.hpp"
#include "label.hpp"
#include "ui_element.hpp"

namespace ngk::ui::declarative {

struct Node {
  UIElement* element = nullptr;
  std::vector<Node> children{};
  std::vector<std::function<void()>> bindings{};
};

inline Node compose(UIElement& element,
                    std::vector<Node> children = {},
                    std::vector<std::function<void()>> bindings = {}) {
  Node node{};
  node.element = &element;
  node.children = std::move(children);
  node.bindings = std::move(bindings);
  return node;
}

inline std::function<void()> bind_label_text(Label& label, std::string text) {
  return [&label, text = std::move(text)]() {
    label.set_text(text);
  };
}

inline std::function<void()> bind_button_text(Button& button, std::string text) {
  return [&button, text = std::move(text)]() {
    button.set_text(text);
  };
}

inline std::function<void()> bind_button_action(Button& button, std::function<void()> action) {
  return [&button, action = std::move(action)]() mutable {
    button.set_on_click(std::move(action));
  };
}

inline void apply(const Node& node) {
  if (!node.element) {
    return;
  }

  for (const auto& binding : node.bindings) {
    if (binding) {
      binding();
    }
  }

  for (const auto& child : node.children) {
    if (!child.element) {
      continue;
    }
    node.element->add_child(child.element);
    apply(child);
  }
}

} // namespace ngk::ui::declarative
