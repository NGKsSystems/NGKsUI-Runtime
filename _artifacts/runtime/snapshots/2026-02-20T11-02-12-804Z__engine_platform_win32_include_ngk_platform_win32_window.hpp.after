#pragma once

#include <cstdint>
#include <functional>

struct HWND__;
struct HINSTANCE__;

namespace ngk::platform {

class Win32Window {
public:
  using CloseCallback = std::function<void()>;
  using QuitCallback = std::function<void()>;
  using ResizeCallback = std::function<void(int, int)>;
  using DpiChangedCallback = std::function<void(int /*dpi_x*/, int /*dpi_y*/)>;

  using KeyCallback = std::function<void(std::uint32_t, bool, bool)>;
  using CharCallback = std::function<void(std::uint32_t)>;
  using MouseMoveCallback = std::function<void(int, int)>;
  using MouseButtonCallback = std::function<void(std::uint32_t, bool)>;
  using MouseWheelCallback = std::function<void(int)>;

  enum class DpiAwareness : std::uint32_t {
    Unknown = 0,
    PerMonitorV2 = 1,
    PerMonitor = 2,
    System = 3,
    Unaware = 4
  };

  Win32Window();
  ~Win32Window();

  // width/height are desired CLIENT size.
  bool create(const wchar_t* title, int width, int height);
  void destroy();

  void poll_events_once();
  void request_close();
  bool close_requested() const;

  // Native HWND for renderer backends (D3D11 swapchain).
  void* native_handle() const;

  DpiAwareness dpi_awareness() const;

  void set_close_callback(CloseCallback callback);
  void set_quit_callback(QuitCallback callback);
  void set_resize_callback(ResizeCallback callback);
  void set_dpi_changed_callback(DpiChangedCallback callback);
  void set_key_callback(KeyCallback callback);
  void set_char_callback(CharCallback callback);
  void set_mouse_move_callback(MouseMoveCallback callback);
  void set_mouse_button_callback(MouseButtonCallback callback);
  void set_mouse_wheel_callback(MouseWheelCallback callback);

private:
  using Hwnd = HWND__*;
  using Hinstance = HINSTANCE__*;

  static long long __stdcall wnd_proc(Hwnd hwnd, unsigned int message, unsigned long long wparam, long long lparam);
  long long handle_message(unsigned int message, unsigned long long wparam, long long lparam);

  Hinstance instance_;
  Hwnd hwnd_;
  bool class_registered_;
  bool close_requested_;

  DpiAwareness dpi_awareness_;

  CloseCallback close_callback_;
  QuitCallback quit_callback_;
  ResizeCallback resize_callback_;
  DpiChangedCallback dpi_changed_callback_;

  KeyCallback key_callback_;
  CharCallback char_callback_;
  MouseMoveCallback mouse_move_callback_;
  MouseButtonCallback mouse_button_callback_;
  MouseWheelCallback mouse_wheel_callback_;
};

} // namespace ngk::platform
