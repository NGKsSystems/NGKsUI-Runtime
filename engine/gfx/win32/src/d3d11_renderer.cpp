#include "ngk/gfx/d3d11_renderer.hpp"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <d3d11.h>
#include <dxgi.h>

#include <cstdlib>
#include <cstdio>
#include <cstdint>
#include <cmath>
#include <algorithm>
#include <fstream>
#include <functional>
#include <mutex>
#include <unordered_map>

namespace ngk::gfx {

static void safe_release(IUnknown* p) {
  if (p) p->Release();
}

static int read_env_int(const char* key, int def_value) {
  const char* v = std::getenv(key);
  if (!v || !*v) return def_value;
  int out = 0;
  bool neg = false;
  if (*v == '-') { neg = true; ++v; }
  while (*v) {
    if (*v < '0' || *v > '9') break;
    out = (out * 10) + (*v - '0');
    ++v;
  }
  return neg ? -out : out;
}

static std::string json_escape(const std::string& text) {
  std::string out;
  out.reserve(text.size() + 8);
  for (char c : text) {
    switch (c) {
      case '\\': out += "\\\\"; break;
      case '"': out += "\\\""; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default: out += c; break;
    }
  }
  return out;
}

static bool rect_intersects(int ax, int ay, int aw, int ah, int bx, int by, int bw, int bh) {
  return !(ax + aw <= bx || bx + bw <= ax || ay + ah <= by || by + bh <= ay);
}

static bool rect_covers(int ax, int ay, int aw, int ah, int bx, int by, int bw, int bh) {
  return ax <= bx && ay <= by && (ax + aw) >= (bx + bw) && (ay + ah) >= (by + bh);
}

// Fail-policy:
// 0 = QUIT      (any present failure marks device_lost immediately)
// 1 = CONTINUE  (soft faults; only mark device_lost after NGK_PRESENT_FAIL_MAX_CONSEC)
// 2 = RECOVER   (try lightweight recovery for non-device-removed style failures; still respects MAX_CONSEC)
struct PresentFailState {
  int policy = 0;
  std::uint32_t injected_hr = 0x887A0005u; // DXGI_ERROR_DEVICE_REMOVED default
  std::uint64_t consec = 0;
  std::uint64_t total = 0;
  std::uint64_t max_consec = 1;
};

static std::mutex g_pf_mu;
static std::unordered_map<const D3D11Renderer*, PresentFailState> g_pf;

static PresentFailState& pf_state(const D3D11Renderer* self) {
  std::lock_guard<std::mutex> lock(g_pf_mu);
  return g_pf[self]; // default-construct if missing
}

static void pf_erase(const D3D11Renderer* self) {
  std::lock_guard<std::mutex> lock(g_pf_mu);
  g_pf.erase(self);
}

static bool is_device_removed_hr(std::uint32_t hr) {
  switch (hr) {
    case 0x887A0005u: // DXGI_ERROR_DEVICE_REMOVED
    case 0x887A0006u: // DXGI_ERROR_DEVICE_HUNG
    case 0x887A0007u: // DXGI_ERROR_DEVICE_RESET
    case 0x887A0020u: // DXGI_ERROR_DRIVER_INTERNAL_ERROR
      return true;
    default:
      return false;
  }
}

using AlphaBlendFn = BOOL(WINAPI*)(HDC, int, int, int, int, HDC, int, int, int, int, BLENDFUNCTION);

  AlphaBlendFn resolve_alpha_blend_fn() {
    static AlphaBlendFn fn = nullptr;
    static bool loaded = false;
    if (loaded) {
      return fn;
    }

    loaded = true;
    HMODULE module = LoadLibraryW(L"msimg32.dll");
    if (!module) {
      return nullptr;
    }

    fn = reinterpret_cast<AlphaBlendFn>(GetProcAddress(module, "AlphaBlend"));
    return fn;
  }

  COLORREF to_color(float r, float g, float b) {
    const float cr = std::clamp(r, 0.0f, 1.0f);
    const float cg = std::clamp(g, 0.0f, 1.0f);
    const float cb = std::clamp(b, 0.0f, 1.0f);
    return RGB(
      static_cast<int>(cr * 255.0f),
      static_cast<int>(cg * 255.0f),
      static_cast<int>(cb * 255.0f));
  }

  void draw_alpha_shape(HDC target_dc, int x, int y, int width, int height, float alpha, const std::function<void(HDC)>& draw_fn) {
    if (!target_dc || width <= 0 || height <= 0) {
      return;
    }

    const AlphaBlendFn alpha_blend = resolve_alpha_blend_fn();
    if (!alpha_blend || alpha >= 0.999f) {
      draw_fn(target_dc);
      return;
    }

    HDC mem_dc = CreateCompatibleDC(target_dc);
    if (!mem_dc) {
      draw_fn(target_dc);
      return;
    }

    BITMAPINFO bmi{};
    bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = width;
    bmi.bmiHeader.biHeight = -height;
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = BI_RGB;

    void* bits = nullptr;
    HBITMAP dib = CreateDIBSection(target_dc, &bmi, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (!dib) {
      DeleteDC(mem_dc);
      draw_fn(target_dc);
      return;
    }

    HGDIOBJ old_bitmap = SelectObject(mem_dc, dib);
    BitBlt(mem_dc, 0, 0, width, height, target_dc, x, y, SRCCOPY);

    SetBkMode(mem_dc, TRANSPARENT);
    SetViewportOrgEx(mem_dc, -x, -y, nullptr);
    draw_fn(mem_dc);
    SetViewportOrgEx(mem_dc, 0, 0, nullptr);

    BLENDFUNCTION blend{};
    blend.BlendOp = AC_SRC_OVER;
    blend.SourceConstantAlpha = static_cast<BYTE>(std::clamp(alpha, 0.0f, 1.0f) * 255.0f);
    blend.AlphaFormat = 0;
    alpha_blend(target_dc, x, y, width, height, mem_dc, 0, 0, width, height, blend);

    SelectObject(mem_dc, old_bitmap);
    DeleteObject(dib);
    DeleteDC(mem_dc);
  }

D3D11Renderer::D3D11Renderer()
  : present_fail_every_(0),
    present_interval_(1),
    present_counter_(0),
    swapchain_(nullptr),
    device_(nullptr),
    context_(nullptr),
    rtv_(nullptr),
    width_(0),
    height_(0),
    ready_(false),
    device_lost_(false),
    last_present_hr_(0),
    hwnd_(nullptr),
    submit_seq_counter_(0),
    left_forensic_seq_(0),
    forensic_exec_index_(0),
    debug_stage_("unspecified") {}

D3D11Renderer::~D3D11Renderer() {
  shutdown();
}

bool D3D11Renderer::is_ready() const { return ready_; }
bool D3D11Renderer::is_device_lost() const { return device_lost_; }
std::uint32_t D3D11Renderer::last_present_hr() const { return last_present_hr_; }
std::size_t D3D11Renderer::debug_command_count() const {
  return filled_rect_commands_.size() + outline_rect_commands_.size() + rounded_rect_commands_.size() +
         circle_commands_.size() + arc_commands_.size() + ring_segment_commands_.size() +
         clip_commands_.size() + text_commands_.size();
}
int D3D11Renderer::debug_viewport_width() const { return width_; }
int D3D11Renderer::debug_viewport_height() const { return height_; }
std::size_t D3D11Renderer::debug_clip_command_count() const { return clip_commands_.size(); }
std::uint64_t D3D11Renderer::debug_last_submit_seq() const { return submit_seq_counter_; }
void D3D11Renderer::debug_set_stage(std::string stage) { debug_stage_ = std::move(stage); }

void D3D11Renderer::debug_set_left_forensic_region(int x, int y, int width, int height) {
  left_forensic_region_ = RectCommand{ 0, x, y, width, height, 0.0f, 0.0f, 0.0f, 1.0f };
}

void D3D11Renderer::debug_mark_left_forensic_submitted() {
  left_forensic_seq_ = submit_seq_counter_;
}

void D3D11Renderer::debug_set_forensic_log_path(std::string path) {
  forensic_log_path_ = std::move(path);
}

void D3D11Renderer::forensic_log_command(const char* phase, const char* type, const char* stage, std::uint64_t seq,
                                         int x, int y, int width, int height, bool full_screen,
                                         bool intersects_left, bool covers_left) const {
  if (forensic_log_path_.empty()) {
    return;
  }

  std::ofstream out(forensic_log_path_, std::ios::app);
  if (!out) {
    return;
  }

  out << "{\"phase\":\"" << json_escape(phase ? phase : "")
      << "\",\"event\":\"command\",\"type\":\"" << json_escape(type ? type : "")
      << "\",\"stage\":\"" << json_escape(stage ? stage : "")
      << "\",\"seq\":" << seq
      << ",\"exec_index\":" << forensic_exec_index_
      << ",\"x\":" << x
      << ",\"y\":" << y
      << ",\"w\":" << width
      << ",\"h\":" << height
      << ",\"viewport_w\":" << width_
      << ",\"viewport_h\":" << height_
      << ",\"clip_count\":" << clip_commands_.size()
      << ",\"full_screen\":" << (full_screen ? "true" : "false")
      << ",\"intersects_left\":" << (intersects_left ? "true" : "false")
      << ",\"covers_left\":" << (covers_left ? "true" : "false")
      << ",\"left_forensic_seq\":" << left_forensic_seq_
      << ",\"queue\":\"overlay_command_vectors\"}"
      << "\n";
}

void D3D11Renderer::forensic_log_present(const char* event) const {
  if (forensic_log_path_.empty()) {
    return;
  }

  std::ofstream out(forensic_log_path_, std::ios::app);
  if (!out) {
    return;
  }

  out << "{\"phase\":\"present\",\"event\":\"" << json_escape(event ? event : "")
      << "\",\"present_counter\":" << present_counter_
      << ",\"command_count\":" << debug_command_count()
      << ",\"queue\":\"overlay_command_vectors\",\"left_forensic_seq\":" << left_forensic_seq_
      << "}"
      << "\n";
}

void D3D11Renderer::mark_device_lost(std::uint32_t hr) {
  device_lost_ = true;
  ready_ = false;
  last_present_hr_ = hr;
}

bool D3D11Renderer::init(void* hwnd, int client_w, int client_h) {
  shutdown();

  present_fail_every_ = read_env_int("NGK_PRESENT_FAIL_EVERY", 0);
  present_interval_ = read_env_int("NGK_PRESENT_INTERVAL", 1) == 0 ? 0 : 1;
  present_counter_ = 0;

  // Hardened present-fail controls:
  // - NGK_PRESENT_FAIL_POLICY: 0 quit, 1 continue, 2 recover
  // - NGK_PRESENT_FAIL_MAX_CONSEC: default 1
  // - NGK_PRESENT_FAIL_HR: injected HRESULT override (DECIMAL only)
  {
    PresentFailState& st = pf_state(this);
    st.policy = read_env_int("NGK_PRESENT_FAIL_POLICY", 0);
    if (st.policy < 0) st.policy = 0;
    if (st.policy > 2) st.policy = 2;

    int mc = read_env_int("NGK_PRESENT_FAIL_MAX_CONSEC", 1);
    if (mc < 1) mc = 1;
    st.max_consec = static_cast<std::uint64_t>(mc);

    // Default remains 0x887A0005 (DXGI_ERROR_DEVICE_REMOVED).
    // If you override, pass decimal (0x887A0005 == 2289696773).
    int inj = read_env_int("NGK_PRESENT_FAIL_HR", 0); // 0 => keep default
    if (inj != 0) st.injected_hr = static_cast<std::uint32_t>(inj);

    st.consec = 0;
    st.total = 0;
  }

  if (!hwnd) return false;

  width_ = client_w;
  height_ = client_h;
  hwnd_ = hwnd;

  DXGI_SWAP_CHAIN_DESC scd{};
  scd.BufferCount = 2;
  scd.BufferDesc.Width = (client_w > 0) ? static_cast<UINT>(client_w) : 1;
  scd.BufferDesc.Height = (client_h > 0) ? static_cast<UINT>(client_h) : 1;
  scd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
  scd.BufferDesc.RefreshRate.Numerator = 60;
  scd.BufferDesc.RefreshRate.Denominator = 1;
  scd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
  scd.OutputWindow = reinterpret_cast<HWND>(hwnd);
  scd.SampleDesc.Count = 1;
  scd.SampleDesc.Quality = 0;
  scd.Windowed = TRUE;
  scd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

  UINT flags = 0;
#if defined(_DEBUG)
  flags |= D3D11_CREATE_DEVICE_DEBUG;
#endif

  D3D_FEATURE_LEVEL levels[] = { D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0 };
  D3D_FEATURE_LEVEL out_level{};

  HRESULT hr = D3D11CreateDeviceAndSwapChain(
    nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags,
    levels, static_cast<UINT>(sizeof(levels) / sizeof(levels[0])),
    D3D11_SDK_VERSION, &scd, &swapchain_, &device_, &out_level, &context_);

  if (FAILED(hr) || !swapchain_ || !device_ || !context_) {
    shutdown();
    return false;
  }

  if (!create_render_target()) {
    shutdown();
    return false;
  }

  device_lost_ = false;
  last_present_hr_ = 0;
  ready_ = true;
  return true;
}

void D3D11Renderer::shutdown() {
  ready_ = false;
  device_lost_ = false;
  last_present_hr_ = 0;

  release_render_target();

  safe_release(reinterpret_cast<IUnknown*>(context_));
  context_ = nullptr;

  safe_release(reinterpret_cast<IUnknown*>(device_));
  device_ = nullptr;

  safe_release(reinterpret_cast<IUnknown*>(swapchain_));
  swapchain_ = nullptr;

  width_ = 0;
  height_ = 0;
  hwnd_ = nullptr;
  present_counter_ = 0;
  present_fail_every_ = 0;
  present_interval_ = 1;
  filled_rect_commands_.clear();
  outline_rect_commands_.clear();
  rounded_rect_commands_.clear();
  circle_commands_.clear();
  arc_commands_.clear();
  ring_segment_commands_.clear();
  clip_commands_.clear();
  text_commands_.clear();
  submit_seq_counter_ = 0;
  left_forensic_seq_ = 0;
  left_forensic_region_.reset();
  forensic_log_path_.clear();
  forensic_exec_index_ = 0;
  debug_stage_.clear();

  pf_erase(this);
}

bool D3D11Renderer::create_render_target() {
  release_render_target();
  if (!swapchain_ || !device_) return false;

  ID3D11Texture2D* backbuffer = nullptr;
  HRESULT hr = swapchain_->GetBuffer(
    0, __uuidof(ID3D11Texture2D),
    reinterpret_cast<void**>(&backbuffer));

  if (FAILED(hr) || !backbuffer) return false;

  hr = device_->CreateRenderTargetView(backbuffer, nullptr, &rtv_);
  backbuffer->Release();
  backbuffer = nullptr;

  if (FAILED(hr) || !rtv_) return false;
  return true;
}

void D3D11Renderer::release_render_target() {
  if (rtv_) { rtv_->Release(); rtv_ = nullptr; }
}

bool D3D11Renderer::resize(int client_w, int client_h) {
  if (!swapchain_ || !context_) return false;
  if (client_w <= 0 || client_h <= 0) return true;

  width_ = client_w;
  height_ = client_h;

  release_render_target();

  HRESULT hr = swapchain_->ResizeBuffers(
    0,
    static_cast<UINT>(client_w),
    static_cast<UINT>(client_h),
    DXGI_FORMAT_UNKNOWN,
    0);

  if (FAILED(hr)) return false;

  return create_render_target();
}

void D3D11Renderer::begin_frame() {
  if (!ready_ || device_lost_ || !context_ || !rtv_) return;
  filled_rect_commands_.clear();
  outline_rect_commands_.clear();
  rounded_rect_commands_.clear();
  circle_commands_.clear();
  arc_commands_.clear();
  ring_segment_commands_.clear();
  clip_commands_.clear();
  text_commands_.clear();
  forensic_exec_index_ = 0;

  context_->OMSetRenderTargets(1, &rtv_, nullptr);

  D3D11_VIEWPORT vp{};
  vp.TopLeftX = 0.0f;
  vp.TopLeftY = 0.0f;
  vp.Width = static_cast<float>((width_ > 0) ? width_ : 1);
  vp.Height = static_cast<float>((height_ > 0) ? height_ : 1);
  vp.MinDepth = 0.0f;
  vp.MaxDepth = 1.0f;

  context_->RSSetViewports(1, &vp);
}

void D3D11Renderer::clear(float r, float g, float b, float a) {
  if (!ready_ || device_lost_ || !context_ || !rtv_) return;
  const float color[4] = { r, g, b, a };
  context_->ClearRenderTargetView(rtv_, color);

  const std::uint64_t seq = ++submit_seq_counter_;
  bool intersects_left = false;
  bool covers_left = false;
  if (left_forensic_region_.has_value()) {
    intersects_left = rect_intersects(0, 0, width_, height_, left_forensic_region_->x, left_forensic_region_->y, left_forensic_region_->width, left_forensic_region_->height);
    covers_left = rect_covers(0, 0, width_, height_, left_forensic_region_->x, left_forensic_region_->y, left_forensic_region_->width, left_forensic_region_->height);
  }
  forensic_log_command("submit", "clear", debug_stage_.c_str(), seq, 0, 0, width_, height_, true, intersects_left, covers_left);
}

void D3D11Renderer::queue_rect(int x, int y, int width, int height, float r, float g, float b, float a) {
  if (!ready_ || device_lost_ || width <= 0 || height <= 0) {
    return;
  }

  const std::uint64_t seq = ++submit_seq_counter_;
  filled_rect_commands_.push_back(RectCommand{ seq, x, y, width, height, r, g, b, a });
  bool intersects_left = false;
  bool covers_left = false;
  if (left_forensic_region_.has_value()) {
    intersects_left = rect_intersects(x, y, width, height, left_forensic_region_->x, left_forensic_region_->y, left_forensic_region_->width, left_forensic_region_->height);
    covers_left = rect_covers(x, y, width, height, left_forensic_region_->x, left_forensic_region_->y, left_forensic_region_->width, left_forensic_region_->height);
  }
  forensic_log_command("submit", "rect_fill", debug_stage_.c_str(), seq, x, y, width, height,
                       x <= 0 && y <= 0 && width >= width_ && height >= height_, intersects_left, covers_left);
}

void D3D11Renderer::queue_rect_outline(int x, int y, int width, int height, float r, float g, float b, float a) {
  if (!ready_ || device_lost_ || width <= 1 || height <= 1) {
    return;
  }

  const std::uint64_t seq = ++submit_seq_counter_;
  outline_rect_commands_.push_back(RectCommand{ seq, x, y, width, height, r, g, b, a });
  bool intersects_left = false;
  bool covers_left = false;
  if (left_forensic_region_.has_value()) {
    intersects_left = rect_intersects(x, y, width, height, left_forensic_region_->x, left_forensic_region_->y, left_forensic_region_->width, left_forensic_region_->height);
    covers_left = rect_covers(x, y, width, height, left_forensic_region_->x, left_forensic_region_->y, left_forensic_region_->width, left_forensic_region_->height);
  }
  forensic_log_command("submit", "rect_outline", debug_stage_.c_str(), seq, x, y, width, height, false, intersects_left, covers_left);
}

void D3D11Renderer::queue_rounded_rect(int x, int y, int width, int height, int radius, float r, float g, float b, float a) {
  if (!ready_ || device_lost_ || width <= 0 || height <= 0) {
    return;
  }

  const int max_radius = std::max(0, std::min(width, height) / 2);
  const int clamped_radius = std::min(std::max(radius, 0), max_radius);
  const std::uint64_t seq = ++submit_seq_counter_;
  rounded_rect_commands_.push_back(RoundedRectCommand{ seq, x, y, width, height, clamped_radius, 1, r, g, b, a, true });
  bool intersects_left = false;
  bool covers_left = false;
  if (left_forensic_region_.has_value()) {
    intersects_left = rect_intersects(x, y, width, height, left_forensic_region_->x, left_forensic_region_->y, left_forensic_region_->width, left_forensic_region_->height);
    covers_left = rect_covers(x, y, width, height, left_forensic_region_->x, left_forensic_region_->y, left_forensic_region_->width, left_forensic_region_->height);
  }
  forensic_log_command("submit", "rounded_rect_fill", debug_stage_.c_str(), seq, x, y, width, height, false, intersects_left, covers_left);
}

void D3D11Renderer::queue_rounded_rect_outline(int x, int y, int width, int height, int radius, int thickness, float r, float g, float b, float a) {
  if (!ready_ || device_lost_ || width <= 1 || height <= 1) {
    return;
  }

  const int max_radius = std::max(0, std::min(width, height) / 2);
  const int clamped_radius = std::min(std::max(radius, 0), max_radius);
  const int clamped_thickness = std::max(1, thickness);
  const std::uint64_t seq = ++submit_seq_counter_;
  rounded_rect_commands_.push_back(RoundedRectCommand{ seq, x, y, width, height, clamped_radius, clamped_thickness, r, g, b, a, false });
  bool intersects_left = false;
  bool covers_left = false;
  if (left_forensic_region_.has_value()) {
    intersects_left = rect_intersects(x, y, width, height, left_forensic_region_->x, left_forensic_region_->y, left_forensic_region_->width, left_forensic_region_->height);
    covers_left = rect_covers(x, y, width, height, left_forensic_region_->x, left_forensic_region_->y, left_forensic_region_->width, left_forensic_region_->height);
  }
  forensic_log_command("submit", "rounded_rect_outline", debug_stage_.c_str(), seq, x, y, width, height, false, intersects_left, covers_left);
}

void D3D11Renderer::queue_circle(int cx, int cy, int radius, float r, float g, float b, float a) {
  if (!ready_ || device_lost_ || radius <= 0) {
    return;
  }

  const std::uint64_t seq = ++submit_seq_counter_;
  circle_commands_.push_back(CircleCommand{ seq, cx, cy, radius, 1, r, g, b, a, true });
  const int x = cx - radius;
  const int y = cy - radius;
  const int size = radius * 2;
  bool intersects_left = false;
  bool covers_left = false;
  if (left_forensic_region_.has_value()) {
    intersects_left = rect_intersects(x, y, size, size, left_forensic_region_->x, left_forensic_region_->y, left_forensic_region_->width, left_forensic_region_->height);
    covers_left = rect_covers(x, y, size, size, left_forensic_region_->x, left_forensic_region_->y, left_forensic_region_->width, left_forensic_region_->height);
  }
  forensic_log_command("submit", "circle_fill", debug_stage_.c_str(), seq, x, y, size, size, false, intersects_left, covers_left);
}

void D3D11Renderer::queue_circle_outline(int cx, int cy, int radius, int thickness, float r, float g, float b, float a) {
  if (!ready_ || device_lost_ || radius <= 0) {
    return;
  }

  const int clamped_thickness = std::max(1, thickness);
  const std::uint64_t seq = ++submit_seq_counter_;
  circle_commands_.push_back(CircleCommand{ seq, cx, cy, radius, clamped_thickness, r, g, b, a, false });
  const int x = cx - radius;
  const int y = cy - radius;
  const int size = radius * 2;
  bool intersects_left = false;
  bool covers_left = false;
  if (left_forensic_region_.has_value()) {
    intersects_left = rect_intersects(x, y, size, size, left_forensic_region_->x, left_forensic_region_->y, left_forensic_region_->width, left_forensic_region_->height);
    covers_left = rect_covers(x, y, size, size, left_forensic_region_->x, left_forensic_region_->y, left_forensic_region_->width, left_forensic_region_->height);
  }
  forensic_log_command("submit", "circle_outline", debug_stage_.c_str(), seq, x, y, size, size, false, intersects_left, covers_left);
}

void D3D11Renderer::queue_arc(int cx, int cy, int radius, float start_degrees, float sweep_degrees, int thickness, float r, float g, float b, float a) {
  if (!ready_ || device_lost_ || radius <= 0 || std::abs(sweep_degrees) < 0.001f) {
    return;
  }

  const std::uint64_t seq = ++submit_seq_counter_;
  arc_commands_.push_back(ArcCommand{ seq, cx, cy, radius, start_degrees, sweep_degrees, std::max(1, thickness), r, g, b, a });
  const int x = cx - radius;
  const int y = cy - radius;
  const int size = radius * 2;
  bool intersects_left = false;
  bool covers_left = false;
  if (left_forensic_region_.has_value()) {
    intersects_left = rect_intersects(x, y, size, size, left_forensic_region_->x, left_forensic_region_->y, left_forensic_region_->width, left_forensic_region_->height);
    covers_left = rect_covers(x, y, size, size, left_forensic_region_->x, left_forensic_region_->y, left_forensic_region_->width, left_forensic_region_->height);
  }
  forensic_log_command("submit", "arc", debug_stage_.c_str(), seq, x, y, size, size, false, intersects_left, covers_left);
}

void D3D11Renderer::queue_ring_segment(int cx, int cy, int inner_radius, int outer_radius, float start_degrees, float sweep_degrees, float r, float g, float b, float a) {
  if (!ready_ || device_lost_) {
    return;
  }

  const int inner = std::max(0, inner_radius);
  const int outer = std::max(inner + 1, outer_radius);
  if (std::abs(sweep_degrees) < 0.001f) {
    return;
  }

  const std::uint64_t seq = ++submit_seq_counter_;
  ring_segment_commands_.push_back(RingSegmentCommand{ seq, cx, cy, inner, outer, start_degrees, sweep_degrees, r, g, b, a });
  const int x = cx - outer;
  const int y = cy - outer;
  const int size = outer * 2;
  bool intersects_left = false;
  bool covers_left = false;
  if (left_forensic_region_.has_value()) {
    intersects_left = rect_intersects(x, y, size, size, left_forensic_region_->x, left_forensic_region_->y, left_forensic_region_->width, left_forensic_region_->height);
    covers_left = rect_covers(x, y, size, size, left_forensic_region_->x, left_forensic_region_->y, left_forensic_region_->width, left_forensic_region_->height);
  }
  forensic_log_command("submit", "ring_segment", debug_stage_.c_str(), seq, x, y, size, size, false, intersects_left, covers_left);
}

void D3D11Renderer::queue_clip_rect(int x, int y, int width, int height) {
  if (!ready_ || device_lost_ || width <= 0 || height <= 0) {
    return;
  }

  const std::uint64_t seq = ++submit_seq_counter_;
  clip_commands_.push_back(ClipCommand{ seq, x, y, width, height, false });
  forensic_log_command("submit", "clip_rect", debug_stage_.c_str(), seq, x, y, width, height, false, false, false);
}

void D3D11Renderer::queue_clip_reset() {
  if (!ready_ || device_lost_) {
    return;
  }

  const std::uint64_t seq = ++submit_seq_counter_;
  clip_commands_.push_back(ClipCommand{ seq, 0, 0, 0, 0, true });
  forensic_log_command("submit", "clip_reset", debug_stage_.c_str(), seq, 0, 0, 0, 0, false, false, false);
}

void D3D11Renderer::queue_text(int x, int y, std::string text, float r, float g, float b, float a) {
  if (!ready_ || device_lost_ || text.empty()) {
    return;
  }

  const std::uint64_t seq = ++submit_seq_counter_;
  const int text_w = static_cast<int>(text.size()) * 8;
  const int text_h = 16;
  bool intersects_left = false;
  bool covers_left = false;
  if (left_forensic_region_.has_value()) {
    intersects_left = rect_intersects(x, y, text_w, text_h, left_forensic_region_->x, left_forensic_region_->y, left_forensic_region_->width, left_forensic_region_->height);
    covers_left = rect_covers(x, y, text_w, text_h, left_forensic_region_->x, left_forensic_region_->y, left_forensic_region_->width, left_forensic_region_->height);
  }
  text_commands_.push_back(TextCommand{ seq, x, y, std::move(text), r, g, b, a });
  forensic_log_command("submit", "text", debug_stage_.c_str(), seq, x, y, text_w, text_h, false, intersects_left, covers_left);
}

static void handle_present_failure_soft_or_hard(
  D3D11Renderer* self,
  std::uint32_t hr,
  bool injected)
{
  PresentFailState& st = pf_state(self);

  st.total++;
  st.consec++;

  // QUIT: behave like old code: mark device lost immediately.
  if (st.policy == 0) {
    // Use public API only.
    // mark_device_lost is private, so we cannot call it here.
    // Instead: set "device lost" via the existing behavior path by forcing init/shutdown? Not desired.
    // So: we must do QUIT behavior inside end_frame() where we are a member function.
    return;
  }

  // Threshold logic handled by caller (member function) too.
  (void)hr;
  (void)injected;
}

void D3D11Renderer::end_frame() {
  if (!ready_ || device_lost_ || !swapchain_) return;

  present_counter_++;
  forensic_log_present("pre_present");

  PresentFailState& st = pf_state(this);

  auto on_fail = [&](std::uint32_t hr, bool injected) {
    st.total++;
    st.consec++;
    last_present_hr_ = hr;

    // QUIT: immediate device lost (old behavior)
    if (st.policy == 0) {
      mark_device_lost(hr);
      return;
    }

    // If hit threshold -> device lost
    if (st.consec >= st.max_consec) {
      mark_device_lost(hr);
      return;
    }

    // CONTINUE: do nothing (soft fault)
    if (st.policy == 1) {
      return;
    }

    // RECOVER: only on real non-device-removed failures (and not injected)
    if (st.policy == 2) {
      if (injected) return;
      if (is_device_removed_hr(hr)) return;

      // Best-effort recovery: recreate RTV.
      if (create_render_target()) {
        st.consec = 0;
      }
    }
  };

  // Injection path
  if (present_fail_every_ > 0 &&
      (present_counter_ % static_cast<std::uint64_t>(present_fail_every_)) == 0)
  {
        std::fprintf(stderr, "INJECT_PRESENT_FAIL hr=0x%08X policy=%d consec=%llu max_consec=%llu\n", (unsigned)st.injected_hr, st.policy, (unsigned long long)st.consec, (unsigned long long)st.max_consec);
    on_fail(st.injected_hr, /*injected=*/true);
    return; // no Present() this frame
  }

  HRESULT hr = swapchain_->Present(present_interval_, 0);
  if (FAILED(hr)) {
    forensic_log_present("present_failed");
    on_fail(static_cast<std::uint32_t>(hr), /*injected=*/false);
  } else {
    st.consec = 0;
    last_present_hr_ = 0;
    forensic_log_present("present_ok");
    flush_text_overlay();
  }
}

void D3D11Renderer::flush_text_overlay() {
  if (!hwnd_) {
    return;
  }

  if (filled_rect_commands_.empty() && outline_rect_commands_.empty() && rounded_rect_commands_.empty() &&
      circle_commands_.empty() && arc_commands_.empty() && ring_segment_commands_.empty() &&
      clip_commands_.empty() && text_commands_.empty()) {
    return;
  }

  HWND hwnd = reinterpret_cast<HWND>(hwnd_);
  HDC dc = GetDC(hwnd);
  if (!dc) {
    return;
  }

  // Phase 40.10 surgical recovery: clip pre-pass is disabled to avoid partial-frame truncation.
  // In fallback mode this is mandatory; outside fallback we keep the same full-frame behavior until
  // ordered clip command replay is reintroduced safely.
  SelectClipRgn(dc, nullptr);

  auto log_execute = [&](std::uint64_t seq, const char* type, int x, int y, int width, int height, bool full_screen) {
    forensic_exec_index_ += 1;
    bool intersects_left = false;
    bool covers_left = false;
    if (left_forensic_region_.has_value()) {
      intersects_left = rect_intersects(x, y, width, height, left_forensic_region_->x, left_forensic_region_->y, left_forensic_region_->width, left_forensic_region_->height);
      covers_left = rect_covers(x, y, width, height, left_forensic_region_->x, left_forensic_region_->y, left_forensic_region_->width, left_forensic_region_->height);
    }
    forensic_log_command("execute", type, "flush", seq, x, y, width, height, full_screen, intersects_left, covers_left);
  };

  for (const RectCommand& command : filled_rect_commands_) {
    log_execute(command.seq, "rect_fill", command.x, command.y, command.width, command.height,
                command.x <= 0 && command.y <= 0 && command.width >= width_ && command.height >= height_);
    draw_alpha_shape(dc, command.x, command.y, command.width, command.height, command.a, [&](HDC target) {
      RECT rect{ command.x, command.y, command.x + command.width, command.y + command.height };
      HBRUSH brush = CreateSolidBrush(to_color(command.r, command.g, command.b));
      if (brush) {
        FillRect(target, &rect, brush);
        DeleteObject(brush);
      }
    });
  }

  for (const RectCommand& command : outline_rect_commands_) {
    log_execute(command.seq, "rect_outline", command.x, command.y, command.width, command.height, false);
    draw_alpha_shape(dc, command.x, command.y, command.width, command.height, command.a, [&](HDC target) {
      RECT rect{ command.x, command.y, command.x + command.width, command.y + command.height };
      HBRUSH brush = CreateSolidBrush(to_color(command.r, command.g, command.b));
      if (brush) {
        FrameRect(target, &rect, brush);
        DeleteObject(brush);
      }
    });
  }

  for (const RoundedRectCommand& command : rounded_rect_commands_) {
    log_execute(command.seq, command.filled ? "rounded_rect_fill" : "rounded_rect_outline", command.x, command.y, command.width, command.height, false);
    draw_alpha_shape(dc, command.x, command.y, command.width, command.height, command.a, [&](HDC target) {
      HPEN pen = nullptr;
      HBRUSH brush = nullptr;
      HGDIOBJ old_pen = nullptr;
      HGDIOBJ old_brush = nullptr;

      if (command.filled) {
        brush = CreateSolidBrush(to_color(command.r, command.g, command.b));
        pen = CreatePen(PS_SOLID, 1, to_color(command.r, command.g, command.b));
      } else {
        brush = reinterpret_cast<HBRUSH>(GetStockObject(NULL_BRUSH));
        pen = CreatePen(PS_SOLID, std::max(1, command.thickness), to_color(command.r, command.g, command.b));
      }

      if (!pen || !brush) {
        if (pen) {
          DeleteObject(pen);
        }
        return;
      }

      old_pen = SelectObject(target, pen);
      old_brush = SelectObject(target, brush);

      RoundRect(target,
        command.x,
        command.y,
        command.x + command.width,
        command.y + command.height,
        command.radius * 2,
        command.radius * 2);

      SelectObject(target, old_pen);
      SelectObject(target, old_brush);
      DeleteObject(pen);
      if (command.filled) {
        DeleteObject(brush);
      }
    });
  }

  for (const CircleCommand& command : circle_commands_) {
    const int diameter = command.radius * 2;
    log_execute(command.seq, command.filled ? "circle_fill" : "circle_outline", command.cx - command.radius, command.cy - command.radius, diameter, diameter, false);
    draw_alpha_shape(dc, command.cx - command.radius, command.cy - command.radius, diameter, diameter, command.a, [&](HDC target) {
      HPEN pen = nullptr;
      HBRUSH brush = nullptr;
      HGDIOBJ old_pen = nullptr;
      HGDIOBJ old_brush = nullptr;

      if (command.filled) {
        brush = CreateSolidBrush(to_color(command.r, command.g, command.b));
        pen = CreatePen(PS_SOLID, 1, to_color(command.r, command.g, command.b));
      } else {
        brush = reinterpret_cast<HBRUSH>(GetStockObject(NULL_BRUSH));
        pen = CreatePen(PS_SOLID, std::max(1, command.thickness), to_color(command.r, command.g, command.b));
      }

      if (!pen || !brush) {
        if (pen) {
          DeleteObject(pen);
        }
        return;
      }

      old_pen = SelectObject(target, pen);
      old_brush = SelectObject(target, brush);

      Ellipse(target,
        command.cx - command.radius,
        command.cy - command.radius,
        command.cx + command.radius,
        command.cy + command.radius);

      SelectObject(target, old_pen);
      SelectObject(target, old_brush);
      DeleteObject(pen);
      if (command.filled) {
        DeleteObject(brush);
      }
    });
  }

  for (const ArcCommand& command : arc_commands_) {
    const int diameter = command.radius * 2;
    log_execute(command.seq, "arc", command.cx - command.radius, command.cy - command.radius, diameter, diameter, false);
    draw_alpha_shape(dc, command.cx - command.radius, command.cy - command.radius, diameter, diameter, command.a, [&](HDC target) {
      const float start_rad = command.start_degrees * 3.1415926535f / 180.0f;
      const float end_rad = (command.start_degrees + command.sweep_degrees) * 3.1415926535f / 180.0f;
      const int sx = command.cx + static_cast<int>(std::cos(start_rad) * command.radius);
      const int sy = command.cy - static_cast<int>(std::sin(start_rad) * command.radius);
      const int ex = command.cx + static_cast<int>(std::cos(end_rad) * command.radius);
      const int ey = command.cy - static_cast<int>(std::sin(end_rad) * command.radius);

      HPEN pen = CreatePen(PS_SOLID, std::max(1, command.thickness), to_color(command.r, command.g, command.b));
      if (!pen) {
        return;
      }
      HGDIOBJ old_pen = SelectObject(target, pen);
      HGDIOBJ old_brush = SelectObject(target, GetStockObject(NULL_BRUSH));

      Arc(target,
        command.cx - command.radius,
        command.cy - command.radius,
        command.cx + command.radius,
        command.cy + command.radius,
        sx,
        sy,
        ex,
        ey);

      SelectObject(target, old_pen);
      SelectObject(target, old_brush);
      DeleteObject(pen);
    });
  }

  for (const RingSegmentCommand& command : ring_segment_commands_) {
    const int radius = command.outer_radius;
    const int diameter = radius * 2;
    log_execute(command.seq, "ring_segment", command.cx - radius, command.cy - radius, diameter, diameter, false);
    draw_alpha_shape(dc, command.cx - radius, command.cy - radius, diameter, diameter, command.a, [&](HDC target) {
      const float sweep = command.sweep_degrees;
      const int steps = std::max(12, static_cast<int>(std::abs(sweep) / 5.0f));
      std::vector<POINT> points;
      points.reserve(static_cast<std::size_t>(steps * 2 + 2));

      for (int i = 0; i <= steps; ++i) {
        const float t = static_cast<float>(i) / static_cast<float>(steps);
        const float angle = (command.start_degrees + sweep * t) * 3.1415926535f / 180.0f;
        POINT p{};
        p.x = command.cx + static_cast<int>(std::cos(angle) * command.outer_radius);
        p.y = command.cy - static_cast<int>(std::sin(angle) * command.outer_radius);
        points.push_back(p);
      }

      for (int i = steps; i >= 0; --i) {
        const float t = static_cast<float>(i) / static_cast<float>(steps);
        const float angle = (command.start_degrees + sweep * t) * 3.1415926535f / 180.0f;
        POINT p{};
        p.x = command.cx + static_cast<int>(std::cos(angle) * command.inner_radius);
        p.y = command.cy - static_cast<int>(std::sin(angle) * command.inner_radius);
        points.push_back(p);
      }

      HBRUSH brush = CreateSolidBrush(to_color(command.r, command.g, command.b));
      HPEN pen = CreatePen(PS_SOLID, 1, to_color(command.r, command.g, command.b));
      if (!brush || !pen || points.empty()) {
        if (brush) {
          DeleteObject(brush);
        }
        if (pen) {
          DeleteObject(pen);
        }
        return;
      }

      HGDIOBJ old_pen = SelectObject(target, pen);
      HGDIOBJ old_brush = SelectObject(target, brush);
      Polygon(target, points.data(), static_cast<int>(points.size()));
      SelectObject(target, old_pen);
      SelectObject(target, old_brush);
      DeleteObject(pen);
      DeleteObject(brush);
    });
  }

  SetBkMode(dc, TRANSPARENT);
  for (const TextCommand& command : text_commands_) {
    const int text_w = static_cast<int>(command.text.size()) * 8;
    const int text_h = 16;
    log_execute(command.seq, "text", command.x, command.y, text_w, text_h, false);
    const float cr = std::clamp(command.r, 0.0f, 1.0f);
    const float cg = std::clamp(command.g, 0.0f, 1.0f);
    const float cb = std::clamp(command.b, 0.0f, 1.0f);
    SetTextColor(dc, RGB(
      static_cast<int>(cr * 255.0f),
      static_cast<int>(cg * 255.0f),
      static_cast<int>(cb * 255.0f)));

    TextOutA(dc, command.x, command.y, command.text.c_str(), static_cast<int>(command.text.size()));
  }

  ReleaseDC(hwnd, dc);
}

} // namespace ngk::gfx
