#pragma once

#include "panel.hpp"

namespace ngk::ui {

class VerticalLayout : public Panel {
public:
  explicit VerticalLayout(int spacing = 8);

  void set_spacing(int spacing);
  int spacing() const;

  void set_padding(int all);
  void set_padding(int left, int top, int right, int bottom);
  int padding_left() const;
  int padding_top() const;
  int padding_right() const;
  int padding_bottom() const;

  void measure(int available_width, int available_height) override;

  void layout() override;

private:
  int padding_left_ = 0;
  int padding_top_ = 0;
  int padding_right_ = 0;
  int padding_bottom_ = 0;
  int spacing_ = 8;
};

} // namespace ngk::ui
