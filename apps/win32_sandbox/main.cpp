#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <string>
#include <thread>

#include "../runtime_phase53_guard.hpp"
#include "ngk/event_loop.hpp"
#include "ngk/platform/win32_window.hpp"
#include "ngk/gfx/d3d11_renderer.hpp"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <dbghelp.h>
#include <mmsystem.h>

#pragma comment(lib, "winmm.lib")

static const char* dpi_awareness_to_string(ngk::platform::Win32Window::DpiAwareness a) {
  using A = ngk::platform::Win32Window::DpiAwareness;
  switch (a) {
    case A::PerMonitorV2: return "per_monitor_v2";
    case A::PerMonitor: return "per_monitor";
    case A::System: return "system";
    case A::Unaware: return "unaware";
    case A::Unknown:
    default: return "unknown";
  }
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

static bool is_env_set(const char* key) {
  const char* v = std::getenv(key);
  return v != nullptr;
}

static int clamp_int(int value, int min_value, int max_value) {
  if (value < min_value) return min_value;
  if (value > max_value) return max_value;
  return value;
}

static void busy_stall_ms(int ms) {
  if (ms <= 0) return;
  const auto start = std::chrono::steady_clock::now();
  while (true) {
    auto now = std::chrono::steady_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - start).count();
    if (elapsed >= ms) break;
  }
}

static bool write_minidump(EXCEPTION_POINTERS* exception_ptrs, std::string& out_path) {
  CreateDirectoryA(".\\_proof", nullptr);
  CreateDirectoryA(".\\_proof\\al10_1", nullptr);

  SYSTEMTIME st{};
  GetLocalTime(&st);

  char path[MAX_PATH] = {};
  sprintf_s(path,
            ".\\_proof\\al10_1\\minidump_%04u%02u%02u_%02u%02u%02u_%lu.dmp",
            (unsigned)st.wYear,
            (unsigned)st.wMonth,
            (unsigned)st.wDay,
            (unsigned)st.wHour,
            (unsigned)st.wMinute,
            (unsigned)st.wSecond,
            (unsigned long)GetCurrentProcessId());
  out_path = path;

  HMODULE dbghelp = LoadLibraryA("dbghelp.dll");
  if (!dbghelp) {
    return false;
  }

  using MiniDumpWriteDumpFn = BOOL(WINAPI*)(
    HANDLE,
    DWORD,
    HANDLE,
    MINIDUMP_TYPE,
    PMINIDUMP_EXCEPTION_INFORMATION,
    PMINIDUMP_USER_STREAM_INFORMATION,
    PMINIDUMP_CALLBACK_INFORMATION);

  auto mini_dump_write_dump = reinterpret_cast<MiniDumpWriteDumpFn>(GetProcAddress(dbghelp, "MiniDumpWriteDump"));
  if (!mini_dump_write_dump) {
    FreeLibrary(dbghelp);
    return false;
  }

  HANDLE file = CreateFileA(path, GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    FreeLibrary(dbghelp);
    return false;
  }

  MINIDUMP_EXCEPTION_INFORMATION mei{};
  mei.ThreadId = GetCurrentThreadId();
  mei.ExceptionPointers = exception_ptrs;
  mei.ClientPointers = FALSE;

  const BOOL ok = mini_dump_write_dump(
    GetCurrentProcess(),
    GetCurrentProcessId(),
    file,
    (MINIDUMP_TYPE)(MiniDumpWithThreadInfo | MiniDumpWithIndirectlyReferencedMemory),
    exception_ptrs ? &mei : nullptr,
    nullptr,
    nullptr);

  CloseHandle(file);
  FreeLibrary(dbghelp);
  return ok == TRUE;
}

static bool should_capture_exception(DWORD code) {
  switch (code) {
    case 0xE000DEAD:
    case EXCEPTION_ACCESS_VIOLATION:
    case EXCEPTION_ILLEGAL_INSTRUCTION:
    case EXCEPTION_STACK_OVERFLOW:
    case EXCEPTION_IN_PAGE_ERROR:
    case EXCEPTION_ARRAY_BOUNDS_EXCEEDED:
    case EXCEPTION_DATATYPE_MISALIGNMENT:
    case EXCEPTION_FLT_DIVIDE_BY_ZERO:
    case EXCEPTION_INT_DIVIDE_BY_ZERO:
    case EXCEPTION_PRIV_INSTRUCTION:
      return true;
    default:
      return false;
  }
}

static volatile LONG g_crash_logged = 0;

static void log_crash_details(EXCEPTION_POINTERS* exception_ptrs) {
  DWORD code = 0;
  void* address = nullptr;
  if (exception_ptrs && exception_ptrs->ExceptionRecord) {
    code = exception_ptrs->ExceptionRecord->ExceptionCode;
    address = exception_ptrs->ExceptionRecord->ExceptionAddress;
  }

  if (!should_capture_exception(code)) {
    return;
  }

  if (InterlockedCompareExchange(&g_crash_logged, 1, 0) != 0) {
    return;
  }

  HMODULE module = nullptr;
  char module_path[MAX_PATH] = "unknown";
  std::uintptr_t offset = 0;
  if (address && GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                                    static_cast<LPCSTR>(address),
                                    &module)) {
    if (GetModuleFileNameA(module, module_path, MAX_PATH) == 0) {
      strcpy_s(module_path, "unknown");
    }
    offset = (std::uintptr_t)address - (std::uintptr_t)module;
  }

  std::cout << "Crash=EXCEPTION code=0x" << std::hex << std::uppercase << code << std::dec
            << " module=" << module_path
            << " offset=0x" << std::hex << std::uppercase << offset << std::dec
            << " addr=" << address << "\n";

  std::string dump_path;
  const bool dumped = write_minidump(exception_ptrs, dump_path);
  std::cout << "Minidump=" << (dumped ? "WRITTEN" : "FAIL") << " path=" << dump_path << "\n";
}

static LONG CALLBACK ngks_veh_handler(EXCEPTION_POINTERS* exception_ptrs) {
  log_crash_details(exception_ptrs);
  return EXCEPTION_CONTINUE_SEARCH;
}

static int ngks_seh_filter(EXCEPTION_POINTERS* exception_ptrs) {
  log_crash_details(exception_ptrs);
  return EXCEPTION_EXECUTE_HANDLER;
}

static void rt_refresh_flush(HWND hwnd, int enabled, const char* step) {
  const DWORD tid = GetCurrentThreadId();
  std::cout << "RT_REFRESH_FLUSH step=" << step << " tid=" << tid << " enabled=" << enabled << "\n";

  if (enabled == 0) {
    std::cout << "RT_REFRESH_FLUSH step=" << step << " action=SKIP tid=" << tid << "\n";
    return;
  }

  BOOL redraw_ok = FALSE;
  DWORD redraw_gle = 0;
  if (hwnd && IsWindow(hwnd)) {
    redraw_ok = RedrawWindow(hwnd, nullptr, nullptr, RDW_INVALIDATE | RDW_UPDATENOW | RDW_ERASE);
    if (!redraw_ok) {
      redraw_gle = GetLastError();
    }
  }
  std::cout << "RT_REFRESH_FLUSH step=" << step
            << " action=REDRAW ok=" << (redraw_ok ? 1 : 0)
            << " gle=" << redraw_gle
            << " tid=" << tid << "\n";

  HRESULT hr = E_FAIL;
  HMODULE dwm = LoadLibraryA("dwmapi.dll");
  if (dwm) {
    using DwmFlushFn = HRESULT(WINAPI*)();
    auto dwm_flush = reinterpret_cast<DwmFlushFn>(GetProcAddress(dwm, "DwmFlush"));
    if (dwm_flush) {
      hr = dwm_flush();
    }
    FreeLibrary(dwm);
  }

  std::cout << "RT_REFRESH_FLUSH step=" << step
            << " action=DWM_FLUSH hr=0x" << std::hex << std::uppercase << hr << std::dec
            << " tid=" << tid << "\n";
}

static bool is_force_test_crash_enabled(const char* forceCrash) {
  return forceCrash && std::string(forceCrash) == "1";
}

static std::string make_default_jitter_csv_path() {
  CreateDirectoryA(".\\_proof", nullptr);
  CreateDirectoryA(".\\_proof\\phase14_5", nullptr);

  SYSTEMTIME st{};
  GetLocalTime(&st);

  char path[MAX_PATH] = {};
  sprintf_s(path,
            ".\\_proof\\phase14_5\\jitter_%04u%02u%02u_%02u%02u%02u.csv",
            (unsigned)st.wYear,
            (unsigned)st.wMonth,
            (unsigned)st.wDay,
            (unsigned)st.wHour,
            (unsigned)st.wMinute,
            (unsigned)st.wSecond);
  return std::string(path);
}

static int run_app() {
  using namespace std::chrono;

  ngk::EventLoop loop;
  ngk::platform::Win32Window window;
  ngk::gfx::D3D11Renderer renderer;

  int client_w = 960;
  int client_h = 640;
  int rt_refresh_flush_enabled = 1;

  if (!window.create(L"NGKsUI Runtime - Win32 Sandbox (D3D11)", client_w, client_h)) {
    std::cout << "create_failed=1\n";
    return 1;
  }

  std::cout << "dpi_awareness=" << dpi_awareness_to_string(window.dpi_awareness()) << "\n";
  std::cout << "window_created=1\n";

  window.set_close_callback([&] {
    std::cout << "close_requested=1\n";
  });

  window.set_quit_callback([&] {
    std::cout << "quit_requested=1\n";
    loop.stop();
  });

  window.set_dpi_changed_callback([](int dpi_x, int dpi_y) {
    std::cout << "dpi_changed dpi_x=" << dpi_x << " dpi_y=" << dpi_y << "\n";
  });

  loop.set_platform_pump([&] { window.poll_events_once(); });

  // ---- Stress knobs ----
  const int auto_close_ms = read_env_int("NGK_AUTOCLOSE_MS", 8000);
  const int scripted_resize_ms = read_env_int("NGK_SCRIPTED_RESIZE_MS", 250);

  const int resize_spam = read_env_int("NGK_RESIZE_SPAM", 0);     // 1 enables
  const int cpu_stall_ms = read_env_int("NGK_CPU_STALL_MS", 0);   // busy-stall inside render callback
  const int cpu_stall_every = read_env_int("NGK_CPU_STALL_EVERY", 60); // frames

  const int target_fps = clamp_int(read_env_int("NGK_TARGET_FPS", 60), 10, 240);
  const int frame_stats_every = clamp_int(read_env_int("NGK_FRAME_STATS_EVERY", 120), 1, 1000000);
  const int frame_stats_window = clamp_int(read_env_int("NGK_FRAME_STATS_WINDOW", 240), 10, 1000000);
  const bool pacing_mode_env_set = is_env_set("NGK_PACING_MODE");
  int pacing_mode = pacing_mode_env_set ? (read_env_int("NGK_PACING_MODE", 0) == 1 ? 1 : 0) : 0;
  const char* source_pacing = pacing_mode_env_set ? "env" : "default";
  const int pacing_spin_us = clamp_int(read_env_int("NGK_PACING_SPIN_US", 2000), 0, 5000);
  const int pacing_min_sleep_us = clamp_int(read_env_int("NGK_PACING_MIN_SLEEP_US", 200), 0, 20000);
  const int pacing_behind_reset_ms = clamp_int(read_env_int("NGK_PACING_BEHIND_RESET_MS", 50), 1, 5000);
  const int pacing_log = read_env_int("NGK_PACING_LOG", 0) == 1 ? 1 : 0;
  const bool present_interval_env_set = is_env_set("NGK_PRESENT_INTERVAL");
  const int present_interval_env = read_env_int("NGK_PRESENT_INTERVAL", -1);
  const bool force_present_interval_set = is_env_set("NGK_PACING_FORCE_PRESENT_INTERVAL");
  const int present_interval_default = force_present_interval_set
    ? (read_env_int("NGK_PACING_FORCE_PRESENT_INTERVAL", 1) == 1 ? 1 : 0)
    : 1;
  int present_interval = (present_interval_env == 0 || present_interval_env == 1)
    ? present_interval_env
    : present_interval_default;
  const char* source_pi = present_interval_env_set ? "env" : "default";
  if (pacing_mode == 1 && present_interval == 1) {
    std::cout << "POLICY_OVERRIDE reason=DOUBLE_REGULATION forcing_pacing=0 present_interval=1\n";
    pacing_mode = 0;
    source_pacing = "default";
  }
  const int timer_res_ms = clamp_int(read_env_int("NGK_TIMER_RES_MS", pacing_mode == 1 ? 1 : 0), 0, 1);
  const char* env_pacing_mode_raw = std::getenv("NGK_PACING_MODE");
  const char* env_present_interval_raw = std::getenv("NGK_PRESENT_INTERVAL");
  const char* env_target_fps_raw = std::getenv("NGK_TARGET_FPS");
  const char* env_timer_res_ms_raw = std::getenv("NGK_TIMER_RES_MS");
  const char* env_pacing_spin_us_raw = std::getenv("NGK_PACING_SPIN_US");
  const char* env_pacing_min_sleep_us_raw = std::getenv("NGK_PACING_MIN_SLEEP_US");
  const char* env_pacing_behind_reset_ms_raw = std::getenv("NGK_PACING_BEHIND_RESET_MS");
  std::cout << "ENV_DUMP"
            << " NGK_PACING_MODE=" << ((env_pacing_mode_raw && *env_pacing_mode_raw) ? env_pacing_mode_raw : "unset")
            << " NGK_PRESENT_INTERVAL=" << ((env_present_interval_raw && *env_present_interval_raw) ? env_present_interval_raw : "unset")
            << " NGK_TARGET_FPS=" << ((env_target_fps_raw && *env_target_fps_raw) ? env_target_fps_raw : "unset")
            << " NGK_TIMER_RES_MS=" << ((env_timer_res_ms_raw && *env_timer_res_ms_raw) ? env_timer_res_ms_raw : "unset")
            << " NGK_PACING_SPIN_US=" << ((env_pacing_spin_us_raw && *env_pacing_spin_us_raw) ? env_pacing_spin_us_raw : "unset")
            << " NGK_PACING_MIN_SLEEP_US=" << ((env_pacing_min_sleep_us_raw && *env_pacing_min_sleep_us_raw) ? env_pacing_min_sleep_us_raw : "unset")
            << " NGK_PACING_BEHIND_RESET_MS=" << ((env_pacing_behind_reset_ms_raw && *env_pacing_behind_reset_ms_raw) ? env_pacing_behind_reset_ms_raw : "unset")
            << "\n";
  std::cout << "POLICY_SELECTED pacing=" << pacing_mode
            << " present_interval=" << present_interval
            << " source_pacing=" << source_pacing
            << " source_pi=" << source_pi << "\n";

  /*
    Phase 14.10 integrity assert:
    This should never happen after 14.6 guardrail.
  */
  if (pacing_mode == 1 && present_interval == 1) {
    printf("FATAL_POLICY_VIOLATION pacing=1 present_interval=1\n");
    fflush(stdout);
    return 0;
  }

  const int jitter_csv_enabled = read_env_int("NGK_JITTER_CSV", 0) == 1 ? 1 : 0;
  const int jitter_warmup_frames = clamp_int(read_env_int("NGK_JITTER_WARMUP_FRAMES", 120), 0, 100000000);
  const int jitter_sample_every = clamp_int(read_env_int("NGK_JITTER_SAMPLE_EVERY", 1), 1, 1000000);
  const int jitter_max_frames = read_env_int("NGK_JITTER_MAX_FRAMES", 0);
  const char* jitter_csv_path_env = std::getenv("NGK_JITTER_CSV_PATH");
  rt_refresh_flush_enabled = read_env_int("NGKS_RT_REFRESH_FLUSH", 1) == 0 ? 0 : 1;

  char present_interval_value[8] = {};
  sprintf_s(present_interval_value, "%d", present_interval);
  SetEnvironmentVariableA("NGK_PRESENT_INTERVAL", present_interval_value);

  bool timer_res_active = false;
  if (timer_res_ms == 1) {
    timer_res_active = (timeBeginPeriod(1) == TIMERR_NOERROR);
  }

  if (!renderer.init(window.native_handle(), client_w, client_h)) {
    if (timer_res_active) {
      timeEndPeriod(1);
    }
    std::cout << "d3d11_init_failed=1\n";
    return 2;
  }
  std::cout << "d3d11_ready=1\n";

  std::ofstream jitter_csv;
  bool jitter_csv_active = false;
  std::string jitter_csv_path;
  if (jitter_csv_enabled == 1) {
    ngk::runtime_guard::require_runtime_trust("file_load");
    jitter_csv_path = (jitter_csv_path_env && *jitter_csv_path_env) ? std::string(jitter_csv_path_env) : make_default_jitter_csv_path();
    jitter_csv.open(jitter_csv_path, std::ios::out | std::ios::trunc);
    if (jitter_csv.is_open()) {
      jitter_csv_active = true;
      jitter_csv << "frame_idx,ts_ms,dt_ms,target_ms,slept_ms,spin_us,drift_ms,present_block_ms,stall_injected_ms,resize_event,present_failed,pacing_active,present_interval,slept_us,spin_us_actual,error_ms,abs_error_ms\n";
      jitter_csv << std::fixed << std::setprecision(6);
    }
  }

  std::cout << "autoclose_ms=" << auto_close_ms << "\n";
  std::cout << "scripted_resize_ms=" << scripted_resize_ms << "\n";
  std::cout << "resize_spam=" << resize_spam << "\n";
  std::cout << "cpu_stall_ms=" << cpu_stall_ms << "\n";
  std::cout << "cpu_stall_every=" << cpu_stall_every << "\n";
  std::cout << "target_fps=" << target_fps << "\n";
  std::cout << "frame_stats_every=" << frame_stats_every << "\n";
  std::cout << "frame_stats_window=" << frame_stats_window << "\n";
  std::cout << "pacing_mode=" << pacing_mode << "\n";
  std::cout << "pacing_spin_us=" << pacing_spin_us << "\n";
  std::cout << "pacing_min_sleep_us=" << pacing_min_sleep_us << "\n";
  std::cout << "pacing_behind_reset_ms=" << pacing_behind_reset_ms << "\n";
  std::cout << "present_interval=" << present_interval << "\n";
  std::cout << "timer_res_ms=" << timer_res_ms << "\n";
  std::cout << "jitter_csv_enabled=" << jitter_csv_enabled << "\n";
  std::cout << "jitter_warmup_frames=" << jitter_warmup_frames << "\n";
  std::cout << "jitter_sample_every=" << jitter_sample_every << "\n";
  std::cout << "jitter_max_frames=" << jitter_max_frames << "\n";
  if (jitter_csv_active) {
    std::cout << "jitter_csv_path=" << jitter_csv_path << "\n";
  }
  std::cout << "rt_refresh_flush_enabled=" << rt_refresh_flush_enabled << "\n";
  if (pacing_log == 1) {
    std::cout << "PRESENT_MODE present_interval=" << present_interval
              << " allow_tearing=unknown composition=unknown\n";
  }
  if (pacing_log == 1) {
    std::cout << "PACING_CONFIG mode=" << pacing_mode
              << " target_fps=" << target_fps
              << " target_ms=" << (1000.0 / (double)target_fps)
              << " present_interval=" << present_interval
              << " timer_res_ms=" << timer_res_ms << "\n";
  }

  if (auto_close_ms > 0) {
    loop.set_timeout(milliseconds(auto_close_ms), [&] {
      std::cout << "autoclose_fired=1\n";
      window.request_close();
    });
  }

  if (scripted_resize_ms > 0) {
    loop.set_timeout(milliseconds(scripted_resize_ms), [&] {
      std::cout << "scripted_resize_fire=1\n";
      HWND hwnd = (HWND)window.native_handle();
      if (hwnd) {
        int new_w = client_w + 80;
        int new_h = client_h + 60;
        SetWindowPos(hwnd, nullptr, 0, 0, new_w, new_h, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
      }
    });
  }

  if (resize_spam == 1) {
    // Spam resizes, then cancel interval to avoid runaway.
    std::uint64_t spam_id = 0;
    // Spam 50 resizes over ~2.5 seconds. Alternates between two sizes.
    int count = 0;
    spam_id = loop.set_interval(milliseconds(50), [&] {
      HWND hwnd = (HWND)window.native_handle();
      if (!hwnd) return;
      int w = (count % 2 == 0) ? 1200 : 800;
      int h = (count % 2 == 0) ? 720  : 520;
      SetWindowPos(hwnd, nullptr, 0, 0, w, h, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
      std::cout << "resize_spam_tick=" << count << "\n";
      count++;
      if (count >= 50) {
        loop.cancel(spam_id);
        std::cout << "resize_spam_done=1\n";
      }
    });
  }

  std::uint64_t frame = 0;
  std::uint64_t rendered_frames = 0;
  std::uint64_t frame_count_total = 0;
  std::uint64_t resize_count = 0;
  std::uint64_t present_fail_count = 0;
  std::uint64_t jitter_logged_frames = 0;
  int resize_events_pending = 0;
  int stall_effect_frames_remaining = 0;
  const auto frame_period = duration<double>(1.0 / (double)target_fps);
  const auto frame_period_dur = duration_cast<std::chrono::steady_clock::duration>(frame_period);
  const double period_ms = 1000.0 / (double)target_fps;

  const auto app_start_tp = std::chrono::steady_clock::now();
  auto last_status_tp = app_start_tp;
  std::uint64_t last_status_frame_count = 0;
  auto last_render_tp = std::chrono::steady_clock::now();
  auto next_frame_tp = last_render_tp + frame_period_dur;
  auto legacy_next_tp = next_frame_tp;
  double drift_accum_ms = 0.0;

  std::deque<double> dt_window_ms;
  std::deque<int> late_window;
  double dt_sum_ms = 0.0;
  int late_count_window = 0;

  auto emit_status = [&](bool force) {
    const auto status_now = std::chrono::steady_clock::now();
    const auto status_elapsed_ms = duration_cast<milliseconds>(status_now - last_status_tp).count();
    if (!force && status_elapsed_ms < 1000) {
      return;
    }
    const std::uint64_t frame_delta = frame_count_total - last_status_frame_count;
    const double fps_est = status_elapsed_ms > 0
      ? ((double)frame_delta * 1000.0) / (double)status_elapsed_ms
      : 0.0;
    std::cout << "STATUS fps=" << fps_est
              << " pacing=" << pacing_mode
              << " present_interval=" << present_interval
              << " size=" << client_w << "x" << client_h
              << " resize=" << resize_count
              << " present_fail=" << present_fail_count << "\n";
    last_status_tp = status_now;
    last_status_frame_count = frame_count_total;
  };

  window.set_resize_callback([&](int w, int h) {
    if (w == 0 || h == 0) {
      std::cout << "resize_ignored_zero=1\n";
      return;
    }
    std::cout << "resize w=" << w << " h=" << h << "\n";
    client_w = w;
    client_h = h;
    resize_count++;

    const bool ok = renderer.resize(w, h);
    std::cout << "renderer_resize_ok=" << (ok ? 1 : 0) << "\n";
    if (ok) {
      resize_events_pending++;
    }
    HWND hwnd = (HWND)window.native_handle();
    rt_refresh_flush(hwnd, rt_refresh_flush_enabled, "after_resize");
  });

  loop.set_interval(milliseconds(1), [&] {
    frame++;

    auto now = std::chrono::steady_clock::now();
    const auto scheduled_frame_tp = (pacing_mode == 1) ? next_frame_tp : legacy_next_tp;
    std::int64_t slept_us_this_frame = 0;
    std::int64_t spin_us_planned_this_frame = 0;
    std::int64_t spin_us_actual_this_frame = 0;
    int stall_injected_ms_this_frame = 0;
    int resize_event_this_frame = 0;
    int present_failed_this_frame = 0;
    int pacing_active_this_frame = 0;
    double present_block_ms_this_frame = 0.0;
    bool drift_reset_this_frame = false;

    bool should_render = false;
    if (pacing_mode == 1) {
      pacing_active_this_frame = 1;

      while (true) {
        now = std::chrono::steady_clock::now();
        const auto remaining_us = duration_cast<microseconds>(next_frame_tp - now).count();
        if (remaining_us <= 0) {
          should_render = true;
          break;
        }

        if (remaining_us > pacing_min_sleep_us) {
          const auto spin_window_us = (std::int64_t)pacing_spin_us;
          auto sleep_target_us = remaining_us - spin_window_us;
          if (sleep_target_us < 1) {
            sleep_target_us = 1;
          }
          slept_us_this_frame += sleep_target_us;
          std::this_thread::sleep_for(microseconds(sleep_target_us));
          continue;
        }

        spin_us_planned_this_frame += remaining_us;
        const auto spin_start = std::chrono::steady_clock::now();
        while (std::chrono::steady_clock::now() < next_frame_tp) {
          std::this_thread::yield();
        }
        const auto spin_end = std::chrono::steady_clock::now();
        spin_us_actual_this_frame += duration_cast<microseconds>(spin_end - spin_start).count();
        should_render = true;
        break;
      }
    } else {
      if (now >= legacy_next_tp) {
        should_render = true;
      } else {
        return;
      }
    }

    if (!should_render) {
      return;
    }

    const auto frame_start_tp = std::chrono::steady_clock::now();
    const double dt_ms = duration<double, std::milli>(frame_start_tp - last_render_tp).count();
    const double ts_ms = duration<double, std::milli>(frame_start_tp - app_start_tp).count();
    last_render_tp = frame_start_tp;
    const double error_ms = duration<double, std::milli>(frame_start_tp - scheduled_frame_tp).count();
    const double abs_error_ms = error_ms < 0.0 ? -error_ms : error_ms;
    if (abs_error_ms > (double)pacing_behind_reset_ms) {
      drift_accum_ms = 0.0;
      drift_reset_this_frame = true;
    } else {
      drift_accum_ms += error_ms;
      if (drift_accum_ms > (double)pacing_behind_reset_ms) {
        drift_accum_ms = (double)pacing_behind_reset_ms;
      } else if (drift_accum_ms < -(double)pacing_behind_reset_ms) {
        drift_accum_ms = -(double)pacing_behind_reset_ms;
      }
    }
    const double drift_ms = drift_accum_ms;
    if (resize_events_pending > 0) {
      resize_event_this_frame = 1;
      resize_events_pending--;
    }
    if (stall_effect_frames_remaining > 0 && cpu_stall_ms > 0) {
      stall_injected_ms_this_frame = cpu_stall_ms;
      stall_effect_frames_remaining--;
    }

    dt_window_ms.push_back(dt_ms);
    dt_sum_ms += dt_ms;
    const int is_late = dt_ms > (period_ms * 1.25) ? 1 : 0;
    late_window.push_back(is_late);
    late_count_window += is_late;
    while ((int)dt_window_ms.size() > frame_stats_window) {
      dt_sum_ms -= dt_window_ms.front();
      dt_window_ms.pop_front();
      late_count_window -= late_window.front();
      late_window.pop_front();
    }

    rendered_frames++;
    frame_count_total++;

    // If device lost injected/real, print once and stop (tests shutdown path).
    if (!renderer.is_ready()) {
      if (renderer.is_device_lost()) {
        present_failed_this_frame = 1;
        present_fail_count++;
        std::cout << "present_failed_hr=0x" << std::hex << std::uppercase
                  << renderer.last_present_hr() << std::dec << "\n";
        emit_status(true);
        loop.stop();
      }
    } else {
      if (cpu_stall_ms > 0 && cpu_stall_every > 0 && (frame % (std::uint64_t)cpu_stall_every) == 0) {
        std::cout << "cpu_stall_fire=1\n";
        stall_injected_ms_this_frame = cpu_stall_ms;
        const int estimated_stall_frames = (int)(cpu_stall_ms / period_ms) + 1;
        stall_effect_frames_remaining = estimated_stall_frames > 1 ? estimated_stall_frames : 1;
        busy_stall_ms(cpu_stall_ms);
      }

      renderer.begin_frame();
      float t = (float)((frame % 300) / 300.0);
      renderer.clear(0.05f + 0.35f * t, 0.07f, 0.12f + 0.25f * (1.0f - t), 1.0f);
      const auto present_start = std::chrono::steady_clock::now();
      renderer.end_frame();
      const auto present_end = std::chrono::steady_clock::now();
      present_block_ms_this_frame = duration<double, std::milli>(present_end - present_start).count();
      if (renderer.is_device_lost()) {
        present_failed_this_frame = 1;
        present_fail_count++;
        std::cout << "present_failed_hr=0x" << std::hex << std::uppercase
                  << renderer.last_present_hr() << std::dec << "\n";
        emit_status(true);
        loop.stop();
      }
    }

    if (jitter_csv_active && rendered_frames > (std::uint64_t)jitter_warmup_frames) {
      const std::uint64_t sample_index = rendered_frames - (std::uint64_t)jitter_warmup_frames;
      if ((sample_index % (std::uint64_t)jitter_sample_every) == 0) {
        jitter_csv << rendered_frames << ","
                   << ts_ms << ","
                   << dt_ms << ","
                   << period_ms << ","
                   << ((double)slept_us_this_frame / 1000.0) << ","
                   << spin_us_planned_this_frame << ","
                   << drift_ms << ","
                   << present_block_ms_this_frame << ","
                   << stall_injected_ms_this_frame << ","
                   << resize_event_this_frame << ","
                   << present_failed_this_frame << ","
                   << pacing_active_this_frame << ","
                   << present_interval << ","
                   << slept_us_this_frame << ","
                   << spin_us_actual_this_frame << ","
                   << error_ms << ","
                   << abs_error_ms << "\n";
        jitter_logged_frames++;
      }
      if (jitter_max_frames > 0 && jitter_logged_frames >= (std::uint64_t)jitter_max_frames) {
        jitter_csv.flush();
        jitter_csv_active = false;
      }
    }

    emit_status(false);

    if (present_failed_this_frame == 1) {
      return;
    }

    if (dt_window_ms.size() >= 2 && (rendered_frames % (std::uint64_t)frame_stats_every) == 0) {
      double min_dt = (std::numeric_limits<double>::max)();
      double max_dt = 0.0;
      for (double v : dt_window_ms) {
        if (v < min_dt) min_dt = v;
        if (v > max_dt) max_dt = v;
      }
      const double avg_dt = dt_sum_ms / (double)dt_window_ms.size();
      const double jitter = max_dt - min_dt;
      std::cout << "frame_stats fps_target=" << target_fps
                << " avg_dt_ms=" << avg_dt
                << " min_dt_ms=" << min_dt
                << " max_dt_ms=" << max_dt
                << " jitter_ms=" << jitter
                << " late=" << late_count_window
                << " frames=" << dt_window_ms.size() << "\n";
    }

    if (pacing_mode == 1) {
      if (drift_reset_this_frame) {
        next_frame_tp = frame_start_tp + frame_period_dur;
      } else {
        next_frame_tp = scheduled_frame_tp + frame_period_dur;
        if (next_frame_tp <= frame_start_tp) {
          next_frame_tp = frame_start_tp + frame_period_dur;
        }
      }
    } else {
      if (drift_reset_this_frame) {
        legacy_next_tp = frame_start_tp + frame_period_dur;
      } else {
        legacy_next_tp = scheduled_frame_tp + frame_period_dur;
        if (legacy_next_tp <= frame_start_tp) {
          legacy_next_tp = frame_start_tp + frame_period_dur;
        }
      }
    }
  });

  loop.run();

  if (jitter_csv.is_open()) {
    jitter_csv.flush();
  }

  if (timer_res_active) {
    timeEndPeriod(1);
  }

  std::cout << "shutdown_ok=1\n";
  return 0;
}

int main() {
  const int guard_rc = ngk::runtime_guard::enforce_phase53_2();
  if (guard_rc != 0) {
    return guard_rc;
  }

  ngk::runtime_guard::require_runtime_trust("execution_pipeline");

  PVOID veh_handle = AddVectoredExceptionHandler(1, ngks_veh_handler);
  std::cout << "crash_capture_veh_installed=" << (veh_handle ? 1 : 0) << "\n";

  const char* forceCrash = getenv("NGKS_FORCE_TEST_CRASH");
  const bool forceCrashEnabled = is_force_test_crash_enabled(forceCrash);

  int rc = 0;
  __try {
    if (forceCrashEnabled) {
      printf("FORCE_TEST_CRASH=1 triggering_fatal_now\n");
      fflush(stdout);
      RaiseException(0xE000DEAD, 0, 0, nullptr);
    }
    rc = run_app();
  }
  __except (ngks_seh_filter(GetExceptionInformation())) {
    rc = 128;
  }

  if (veh_handle) {
    RemoveVectoredExceptionHandler(veh_handle);
    std::cout << "crash_capture_veh_removed=1\n";
  }

  return rc;
}

