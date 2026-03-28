#pragma once

#include <cstdint>

struct IDXGISwapChain;
struct ID3D11Device;
struct ID3D11DeviceContext;
struct ID3D11RenderTargetView;

namespace ngk::gfx {

class D3D11Renderer {
public:
  D3D11Renderer();
  ~D3D11Renderer();

  // hwnd is Win32 HWND (passed as void* to avoid windows.h in headers)
  bool init(void* hwnd, int client_w, int client_h);

  // Resize swapchain buffers (ignore w/h == 0). Returns true if successful.
  bool resize(int client_w, int client_h);

  void begin_frame();
  void clear(float r, float g, float b, float a);
  void queue_rect(int x, int y, int w, int h, float r, float g, float b, float a);
  void queue_rect_outline(int x, int y, int w, int h, float r, float g, float b, float a);
  void set_clip_rect(int x, int y, int w, int h);
  void reset_clip_rect();
  void debug_set_stage(const char* stage);
  void debug_set_forensic_log_path(const char* path);
  void end_frame();
  void shutdown();

  bool is_ready() const;
  bool is_device_lost() const;
  std::uint32_t last_present_hr() const;

private:
  bool create_render_target();
  void release_render_target();
  void mark_device_lost(std::uint32_t hr);

  // Debug injection: if NGK_PRESENT_FAIL_EVERY is set >0, simulate device loss every N presents.
  int present_fail_every_;
  int present_interval_;
  std::uint64_t present_counter_;

  IDXGISwapChain* swapchain_;
  ID3D11Device* device_;
  ID3D11DeviceContext* context_;
  ID3D11RenderTargetView* rtv_;

  int width_;
  int height_;
  bool ready_;
  bool device_lost_;
  std::uint32_t last_present_hr_;
};

} // namespace ngk::gfx
