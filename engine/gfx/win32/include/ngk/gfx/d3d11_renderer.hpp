#pragma once
#ifndef NGK_GFX_WIN32_D3D11_RENDERER_HPP
#define NGK_GFX_WIN32_D3D11_RENDERER_HPP

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

struct IDXGISwapChain;
struct ID3D11Device;
struct ID3D11DeviceContext;
struct ID3D11RenderTargetView;

namespace ngk::gfx {

class D3D11Renderer {
public:
  D3D11Renderer();
  ~D3D11Renderer();

  bool is_ready() const;
  bool is_device_lost() const;
  std::uint32_t last_present_hr() const;

  bool init(void* hwnd, int client_w, int client_h);
  void shutdown();

  bool resize(int client_w, int client_h);

  void begin_frame();
  void clear(float r, float g, float b, float a);
  void queue_rect(int x, int y, int width, int height, float r, float g, float b, float a = 1.0f);
  void queue_rect_outline(int x, int y, int width, int height, float r, float g, float b, float a = 1.0f);
  void queue_rounded_rect(int x, int y, int width, int height, int radius, float r, float g, float b, float a = 1.0f);
  void queue_rounded_rect_outline(int x, int y, int width, int height, int radius, int thickness, float r, float g, float b, float a = 1.0f);
  void queue_circle(int cx, int cy, int radius, float r, float g, float b, float a = 1.0f);
  void queue_circle_outline(int cx, int cy, int radius, int thickness, float r, float g, float b, float a = 1.0f);
  void queue_arc(int cx, int cy, int radius, float start_degrees, float sweep_degrees, int thickness, float r, float g, float b, float a = 1.0f);
  void queue_ring_segment(int cx, int cy, int inner_radius, int outer_radius, float start_degrees, float sweep_degrees, float r, float g, float b, float a = 1.0f);
  void queue_clip_rect(int x, int y, int width, int height);
  void queue_clip_reset();
  void queue_text(int x, int y, std::string text, float r = 1.0f, float g = 1.0f, float b = 1.0f, float a = 1.0f);
  std::size_t debug_command_count() const;
  int debug_viewport_width() const;
  int debug_viewport_height() const;
  std::size_t debug_clip_command_count() const;
  std::uint64_t debug_last_submit_seq() const;
  void debug_set_stage(std::string stage);
  void debug_set_left_forensic_region(int x, int y, int width, int height);
  void debug_mark_left_forensic_submitted();
  void debug_set_forensic_log_path(std::string path);
  void end_frame();

private:
  struct TextCommand {
    std::uint64_t seq;
    int x;
    int y;
    std::string text;
    float r;
    float g;
    float b;
    float a;
  };

  struct RectCommand {
    std::uint64_t seq;
    int x;
    int y;
    int width;
    int height;
    float r;
    float g;
    float b;
    float a;
  };

  struct RoundedRectCommand {
    std::uint64_t seq;
    int x;
    int y;
    int width;
    int height;
    int radius;
    int thickness;
    float r;
    float g;
    float b;
    float a;
    bool filled;
  };

  struct CircleCommand {
    std::uint64_t seq;
    int cx;
    int cy;
    int radius;
    int thickness;
    float r;
    float g;
    float b;
    float a;
    bool filled;
  };

  struct ArcCommand {
    std::uint64_t seq;
    int cx;
    int cy;
    int radius;
    float start_degrees;
    float sweep_degrees;
    int thickness;
    float r;
    float g;
    float b;
    float a;
  };

  struct RingSegmentCommand {
    std::uint64_t seq;
    int cx;
    int cy;
    int inner_radius;
    int outer_radius;
    float start_degrees;
    float sweep_degrees;
    float r;
    float g;
    float b;
    float a;
  };

  struct ClipCommand {
    std::uint64_t seq;
    int x;
    int y;
    int width;
    int height;
    bool reset;
  };

  void flush_text_overlay();
  void forensic_log_command(const char* phase, const char* type, const char* stage, std::uint64_t seq,
                            int x, int y, int width, int height, bool full_screen,
                            bool intersects_left, bool covers_left) const;
  void forensic_log_present(const char* event) const;

  bool create_render_target();
  void release_render_target();

  void mark_device_lost(std::uint32_t hr);

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
  void* hwnd_;
  std::vector<RectCommand> filled_rect_commands_;
  std::vector<RectCommand> outline_rect_commands_;
  std::vector<RoundedRectCommand> rounded_rect_commands_;
  std::vector<CircleCommand> circle_commands_;
  std::vector<ArcCommand> arc_commands_;
  std::vector<RingSegmentCommand> ring_segment_commands_;
  std::vector<ClipCommand> clip_commands_;
  std::vector<TextCommand> text_commands_;
  std::uint64_t submit_seq_counter_;
  std::uint64_t left_forensic_seq_;
  std::optional<RectCommand> left_forensic_region_;
  std::string forensic_log_path_;
  std::uint64_t forensic_exec_index_;
  std::string debug_stage_;
};

} // namespace ngk::gfx

#endif // NGK_GFX_WIN32_D3D11_RENDERER_HPP