#pragma once

#include <cstdlib>
#include <chrono>
#include <ctime>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#endif

namespace ngk {
namespace runtime_guard {

inline const char* normalize_runtime_context(const char* context) {
  return (context && *context) ? context : "runtime_init";
}

inline bool runtime_observe_enabled() {
  const char* value = std::getenv("NGKS_RUNTIME_OBS");
  if (value == nullptr || value[0] == '\0') {
    return false;
  }
  return !(value[0] == '0' && value[1] == '\0');
}

inline void runtime_observe_event(const char* event, const char* context, int rc) {
  if (!runtime_observe_enabled()) {
    return;
  }
  std::cout << "runtime_observe event=" << ((event && *event) ? event : "unknown")
            << " context=" << normalize_runtime_context(context)
            << " rc=" << rc << "\n";
}

inline void runtime_observe_lifecycle(const char* app, const char* stage) {
  if (!runtime_observe_enabled()) {
    return;
  }
  std::cout << "runtime_observe lifecycle app=" << ((app && *app) ? app : "unknown")
            << " stage=" << ((stage && *stage) ? stage : "unknown") << "\n";
}

inline void runtime_emit_startup_summary(const char* target, const char* context, int enforce_rc) {
  std::cout << "runtime_process_summary"
            << " phase=startup"
            << " target=" << ((target && *target) ? target : "unknown")
            << " context=" << normalize_runtime_context(context)
            << " enforcement=" << (enforce_rc == 0 ? "PASS" : "FAIL")
            << " obs=" << (runtime_observe_enabled() ? "ON" : "OFF")
            << " elapsed_timing=present"
            << "\n";
}

inline void runtime_emit_termination_summary(const char* target, const char* context, int enforce_rc) {
  std::cout << "runtime_process_summary"
            << " phase=termination"
            << " target=" << ((target && *target) ? target : "unknown")
            << " context=" << normalize_runtime_context(context)
            << " enforcement=" << (enforce_rc == 0 ? "PASS" : "FAIL")
            << " obs=" << (runtime_observe_enabled() ? "ON" : "OFF")
            << " elapsed_timing=present"
            << "\n";
}

inline void runtime_emit_final_status(const char* status) {
  std::cout << "runtime_final_status=" << ((status && *status) ? status : "unknown") << "\n";
}

inline std::string runtime_guard_current_utc_timestamp() {
  const auto now = std::chrono::system_clock::now();
  const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
      now.time_since_epoch()) % 1000;
  const std::time_t now_time = std::chrono::system_clock::to_time_t(now);
  std::tm utc_tm{};
#ifdef _WIN32
  gmtime_s(&utc_tm, &now_time);
#else
  gmtime_r(&now_time, &utc_tm);
#endif

  std::ostringstream out;
  out << std::put_time(&utc_tm, "%Y-%m-%dT%H:%M:%S")
      << '.' << std::setw(3) << std::setfill('0') << ms.count() << 'Z';
  return out.str();
}

inline void runtime_emit_guard_boundary(const char* context, const char* stage) {
  std::cout << "TIMING_BOUNDARY name=runtime_guard_"
            << normalize_runtime_context(context)
            << "_" << ((stage && *stage) ? stage : "unknown")
            << "_timestamp ts_utc=" << runtime_guard_current_utc_timestamp()
            << " source=runtime_guard quality=exact\n";
}

#ifdef _WIN32
inline bool runtime_guard_hardening_disabled() {
  const char* value = std::getenv("NGKS_RUNTIME_TRUST_GUARD_DISABLE_HARDENED_PATH");
  if (value == nullptr || value[0] == '\0') {
    return false;
  }
  return !(value[0] == '0' && value[1] == '\0');
}

inline DWORD runtime_guard_wait_timeout_ms() {
  const char* value = std::getenv("NGKS_RUNTIME_TRUST_GUARD_TIMEOUT_MS");
  if (value == nullptr || value[0] == '\0') {
    return 60000U;
  }

  char* end = nullptr;
  const unsigned long parsed = std::strtoul(value, &end, 10);
  if (end == value || (end && *end != '\0') || parsed == 0UL || parsed > 300000UL) {
    return 60000U;
  }

  return static_cast<DWORD>(parsed);
}

inline bool runtime_guard_script_exists_windows() {
  const DWORD attrs = GetFileAttributesW(L"tools\\TrustChainRuntime.ps1");
  if (attrs == INVALID_FILE_ATTRIBUTES) {
    return false;
  }
  return (attrs & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

inline int execute_runtime_trust_command_windows(const std::wstring& command) {
  if (!runtime_guard_script_exists_windows()) {
    return -1;
  }

  std::wstring command_line = command;
  command_line.push_back(L'\0');

  STARTUPINFOW startup_info{};
  startup_info.cb = sizeof(startup_info);
  PROCESS_INFORMATION process_info{};

  const BOOL created = CreateProcessW(
      nullptr,
      command_line.data(),
      nullptr,
      nullptr,
      FALSE,
      0,
      nullptr,
      nullptr,
      &startup_info,
      &process_info);

  if (!created) {
    return -1;
  }

  const DWORD wait_rc = WaitForSingleObject(process_info.hProcess, runtime_guard_wait_timeout_ms());
  if (wait_rc != WAIT_OBJECT_0) {
    TerminateProcess(process_info.hProcess, 1);
    WaitForSingleObject(process_info.hProcess, 2000U);
    CloseHandle(process_info.hThread);
    CloseHandle(process_info.hProcess);
    return -1;
  }

  DWORD child_exit_code = 0;
  if (!GetExitCodeProcess(process_info.hProcess, &child_exit_code)) {
    CloseHandle(process_info.hThread);
    CloseHandle(process_info.hProcess);
    return -1;
  }

  CloseHandle(process_info.hThread);
  CloseHandle(process_info.hProcess);
  return static_cast<int>(child_exit_code);
}
#endif

inline int enforce_runtime_trust(const char* context) {
  const auto highres_invoke_start = std::chrono::steady_clock::now();
  runtime_observe_event("enforce_begin", context, 0);
  runtime_emit_guard_boundary(context, "command_build_start");
  const auto highres_command_build_start = std::chrono::steady_clock::now();
#ifdef _WIN32
  const bool hardening_disabled = runtime_guard_hardening_disabled();
  std::cout << "runtime_trust_guard_hardening_mode=" << (hardening_disabled ? "LEGACY_SYSTEM_ROLLBACK" : "DIRECT_PROCESS_HARDENED")
            << " context=" << normalize_runtime_context(context) << "\n";
  std::wstring command = L"powershell -NoProfile -ExecutionPolicy Bypass -File \"tools\\TrustChainRuntime.ps1\" -Context \"";
  const char* resolved = normalize_runtime_context(context);
  for (const char* cursor = resolved; *cursor; ++cursor) {
    command.push_back(static_cast<wchar_t>(*cursor));
  }
  command += L"\"";
#else
  std::string command = "pwsh -NoProfile -ExecutionPolicy Bypass -File \"tools/TrustChainRuntime.ps1\" -Context \"";
  command += normalize_runtime_context(context);
  command += "\"";
#endif
  const auto highres_command_build_end = std::chrono::steady_clock::now();
  runtime_emit_guard_boundary(context, "command_build_end");
  runtime_emit_guard_boundary(context, "execute_call_start");
  const auto highres_execute_call_start = std::chrono::steady_clock::now();
  const auto _ngk_t0 = std::chrono::steady_clock::now();
#ifdef _WIN32
  int rc = -1;
  if (hardening_disabled) {
    rc = _wsystem(command.c_str());
  } else {
    rc = execute_runtime_trust_command_windows(command);
  }
#else
  const int rc = std::system(command.c_str());
#endif
  const auto highres_execute_call_end = std::chrono::steady_clock::now();
  runtime_emit_guard_boundary(context, "execute_call_end");
  const auto highres_pre_command_overhead_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(
      highres_command_build_start - highres_invoke_start).count();
  const auto highres_command_construction_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(
      highres_command_build_end - highres_command_build_start).count();
  const auto highres_pre_execution_overhead_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(
      highres_execute_call_start - highres_command_build_end).count();
  const auto highres_process_spawn_execution_window_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(
      highres_execute_call_end - highres_execute_call_start).count();
  const auto highres_invoke_to_execute_start_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(
      highres_execute_call_start - highres_invoke_start).count();
  const long long highres_pre_execute_split_total_ns =
      highres_pre_command_overhead_ns +
      highres_command_construction_ns +
      highres_pre_execution_overhead_ns;
  std::cout << "runtime_guard_highres_pre_command_overhead_ns=" << highres_pre_command_overhead_ns
            << " context=" << normalize_runtime_context(context) << "\n";
  std::cout << "runtime_guard_highres_command_construction_ns=" << highres_command_construction_ns
            << " context=" << normalize_runtime_context(context) << "\n";
  std::cout << "runtime_guard_highres_pre_execution_overhead_ns=" << highres_pre_execution_overhead_ns
            << " context=" << normalize_runtime_context(context) << "\n";
  std::cout << "runtime_guard_highres_process_spawn_execution_window_ns=" << highres_process_spawn_execution_window_ns
            << " context=" << normalize_runtime_context(context) << "\n";
  std::cout << "runtime_guard_highres_invoke_to_execute_start_ns=" << highres_invoke_to_execute_start_ns
            << " context=" << normalize_runtime_context(context) << "\n";
  std::cout << "runtime_guard_highres_pre_execute_split_total_ns=" << highres_pre_execute_split_total_ns
            << " context=" << normalize_runtime_context(context) << "\n";
  const long long elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::steady_clock::now() - _ngk_t0).count();
  if (rc != 0) {
    runtime_observe_event("enforce_fail", context, rc);
    std::cout << "runtime_trust_guard=FAIL context=" << normalize_runtime_context(context) << " exit=" << rc << "\n";
    std::cout << "runtime_trust_guard_elapsed_ms=" << elapsed_ms << " context=" << normalize_runtime_context(context) << "\n";
    std::cout << "runtime_trust_guard_reason_code=TRUST_CHAIN_BLOCKED context=" << normalize_runtime_context(context) << "\n";
    std::cout << "runtime_trust_guard_action=BLOCK_EXECUTION context=" << normalize_runtime_context(context) << "\n";
    return 120;
  }
  runtime_observe_event("enforce_pass", context, rc);
  std::cout << "runtime_trust_guard=PASS context=" << normalize_runtime_context(context) << "\n";
  std::cout << "runtime_trust_guard_elapsed_ms=" << elapsed_ms << " context=" << normalize_runtime_context(context) << "\n";
  return 0;
}

inline int enforce_phase53_2() {
  return enforce_runtime_trust("runtime_init");
}

inline void require_runtime_trust(const char* context) {
  const int rc = enforce_runtime_trust(context);
  if (rc != 0) {
    runtime_observe_event("require_throw", context, rc);
    std::cout << "runtime_trust_guard_action=RAISE_EXCEPTION context=" << normalize_runtime_context(context) << "\n";
    throw std::runtime_error(std::string("runtime_trust_blocked:") + normalize_runtime_context(context));
  }
  runtime_observe_event("require_pass", context, rc);
}

}  // namespace runtime_guard
}  // namespace ngk
