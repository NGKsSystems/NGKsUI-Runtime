#include "ngk/gfx/d3d11_renderer.hpp"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <d3d11.h>
#include <d3d11_1.h>
#include <dxgi.h>

#include <cstdlib>

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
    last_present_hr_(0) {}

D3D11Renderer::~D3D11Renderer() {
  shutdown();
}

bool D3D11Renderer::is_ready() const { return ready_; }
bool D3D11Renderer::is_device_lost() const { return device_lost_; }
std::uint32_t D3D11Renderer::last_present_hr() const { return last_present_hr_; }

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

  if (!hwnd) return false;

  width_ = client_w;
  height_ = client_h;

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
  present_counter_ = 0;
  present_fail_every_ = 0;
  present_interval_ = 1;
}

bool D3D11Renderer::create_render_target() {
  release_render_target();
  if (!swapchain_ || !device_) return false;

  ID3D11Texture2D* backbuffer = nullptr;
  HRESULT hr = swapchain_->GetBuffer(0, __uuidof(ID3D11Texture2D), reinterpret_cast<void**>(&backbuffer));
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

  HRESULT hr = swapchain_->ResizeBuffers(0, static_cast<UINT>(client_w), static_cast<UINT>(client_h), DXGI_FORMAT_UNKNOWN, 0);
  if (FAILED(hr)) return false;

  return create_render_target();
}

void D3D11Renderer::begin_frame() {
  if (!ready_ || device_lost_ || !context_ || !rtv_) return;

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
}

void D3D11Renderer::queue_rect(int x, int y, int w, int h, float r, float g, float b, float a) {
  if (!ready_ || device_lost_ || !context_ || !rtv_) return;
  if (w <= 0 || h <= 0) return;

  const int max_w = (width_ > 0) ? width_ : 1;
  const int max_h = (height_ > 0) ? height_ : 1;

  int left = x;
  int top = y;
  int right = x + w;
  int bottom = y + h;

  if (left < 0) left = 0;
  if (top < 0) top = 0;
  if (right > max_w) right = max_w;
  if (bottom > max_h) bottom = max_h;
  if (right <= left || bottom <= top) return;

  ID3D11DeviceContext1* context1 = nullptr;
  HRESULT qhr = context_->QueryInterface(__uuidof(ID3D11DeviceContext1), reinterpret_cast<void**>(&context1));
  if (FAILED(qhr) || !context1) {
    return;
  }

  const float color[4] = { r, g, b, a };
  D3D11_RECT rect{};
  rect.left = left;
  rect.top = top;
  rect.right = right;
  rect.bottom = bottom;
  context1->ClearView(rtv_, color, &rect, 1);
  context1->Release();
}

void D3D11Renderer::queue_rect_outline(int x, int y, int w, int h, float r, float g, float b, float a) {
  if (w <= 0 || h <= 0) return;

  const int thickness = 1;
  queue_rect(x, y, w, thickness, r, g, b, a);
  queue_rect(x, y + h - thickness, w, thickness, r, g, b, a);
  queue_rect(x, y, thickness, h, r, g, b, a);
  queue_rect(x + w - thickness, y, thickness, h, r, g, b, a);
}

void D3D11Renderer::debug_set_stage(const char* stage) {
  (void)stage;
}

void D3D11Renderer::debug_set_forensic_log_path(const char* path) {
  (void)path;
}

void D3D11Renderer::end_frame() {
  if (!ready_ || device_lost_ || !swapchain_) return;

  present_counter_++;

  // Debug injection: simulate a present failure without relying on actual GPU/device faults.
  if (present_fail_every_ > 0 && (present_counter_ % static_cast<std::uint64_t>(present_fail_every_)) == 0) {
    // 0x887A0005 = DXGI_ERROR_DEVICE_REMOVED (common "device lost" code)
    mark_device_lost(0x887A0005u);
    return;
  }

  HRESULT hr = swapchain_->Present(present_interval_, 0);
  if (FAILED(hr)) {
    mark_device_lost(static_cast<std::uint32_t>(hr));
  }
}

} // namespace ngk::gfx
