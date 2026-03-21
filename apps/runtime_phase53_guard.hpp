#pragma once

#include <cstdlib>
#include <chrono>
#include <iostream>
#include <stdexcept>
#include <string>

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

inline int enforce_runtime_trust(const char* context) {
  runtime_observe_event("enforce_begin", context, 0);
#ifdef _WIN32
  std::wstring command = L"powershell -NoProfile -ExecutionPolicy Bypass -File \"tools\\TrustChainRuntime.ps1\" -Context \"";
  if (context && *context) {
    for (const char* cursor = context; *cursor; ++cursor) {
      command.push_back(static_cast<wchar_t>(*cursor));
    }
  } else {
    command += L"runtime_init";
  }
  command += L"\"";
#else
  std::string command = "pwsh -NoProfile -ExecutionPolicy Bypass -File \"tools/TrustChainRuntime.ps1\" -Context \"";
  command += (context && *context) ? context : "runtime_init";
  command += "\"";
#endif
  const auto _ngk_t0 = std::chrono::steady_clock::now();
#ifdef _WIN32
  const int rc = _wsystem(command.c_str());
#else
  const int rc = std::system(command.c_str());
#endif
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
