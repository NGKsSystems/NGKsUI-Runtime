#pragma once

#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>

#ifdef _WIN32
#include <windows.h>
#endif

namespace ngk {
namespace runtime_guard {

inline int enforce_runtime_trust(const char* context) {
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
  const int rc = _wsystem(command.c_str());
#else
  std::string command = "pwsh -NoProfile -ExecutionPolicy Bypass -File \"tools/TrustChainRuntime.ps1\" -Context \"";
  command += (context && *context) ? context : "runtime_init";
  command += "\"";
  const int rc = std::system(command.c_str());
#endif
  if (rc != 0) {
    std::cout << "runtime_trust_guard=FAIL context=" << ((context && *context) ? context : "runtime_init") << " exit=" << rc << "\n";
    return 120;
  }
  std::cout << "runtime_trust_guard=PASS context=" << ((context && *context) ? context : "runtime_init") << "\n";
  return 0;
}

inline int enforce_phase53_2() {
  return enforce_runtime_trust("runtime_init");
}

inline void require_runtime_trust(const char* context) {
  const int rc = enforce_runtime_trust(context);
  if (rc != 0) {
    throw std::runtime_error(std::string("runtime_trust_blocked:") + ((context && *context) ? context : "runtime_init"));
  }
}

}  // namespace runtime_guard
}  // namespace ngk
