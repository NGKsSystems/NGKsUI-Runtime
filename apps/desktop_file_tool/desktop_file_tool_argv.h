#pragma once

#include <cstdlib>
#include <string>

int parse_auto_close_ms(int argc, char** argv) {
  const std::string prefix = "--auto-close-ms=";
  for (int index = 1; index < argc; ++index) {
    if (argv[index] == nullptr) {
      continue;
    }
    const std::string arg = argv[index];
    if (arg.rfind(prefix, 0) == 0) {
      const std::string value = arg.substr(prefix.size());
      char* end_ptr = nullptr;
      const long parsed = std::strtol(value.c_str(), &end_ptr, 10);
      if (end_ptr != nullptr && *end_ptr == '\0' && parsed > 0 && parsed <= 600000) {
        return static_cast<int>(parsed);
      }
    }
  }
  return 0;
}

bool parse_validation_mode(int argc, char** argv) {
  const std::string flag = "--validation-mode";
  for (int index = 1; index < argc; ++index) {
    if (argv[index] == nullptr) {
      continue;
    }
    if (flag == argv[index]) {
      return true;
    }
  }
  return false;
}
