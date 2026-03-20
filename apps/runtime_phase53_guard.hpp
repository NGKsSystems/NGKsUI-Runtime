#pragma once

#include <cstdlib>
#include <iostream>
#include <string>

#ifdef _WIN32
#include <windows.h>
#endif

namespace ngk {
namespace runtime_guard {

inline int enforce_phase53_2() {
#ifdef _WIN32
  const wchar_t* command =
      L"powershell -NoProfile -ExecutionPolicy Bypass -File \"tools\\phase53_2\\phase53_2_runtime_gate_enforce.ps1\" >NUL 2>&1";
  const int rc = _wsystem(command);
#else
  const int rc = std::system("pwsh -NoProfile -ExecutionPolicy Bypass -File \"tools/phase53_2/phase53_2_runtime_gate_enforce.ps1\" >/dev/null 2>&1");
#endif
  if (rc != 0) {
    std::cout << "phase53_2_guard=FAIL exit=" << rc << "\n";
    return 120;
  }
  std::cout << "phase53_2_guard=PASS\n";
  return 0;
}

}  // namespace runtime_guard
}  // namespace ngk
