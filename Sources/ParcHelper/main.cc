// Copyright 2026 Parc contributors.
#include "content/public/app/aperitif_mac.h"

#include <dlfcn.h>
#include <mach-o/dyld.h>

#include <cstdio>
#include <string>
#include <vector>

__attribute__((constructor)) static void CheckAperitif() {
  AperitifCheckInitialized();
}

namespace {
class Library {
 public:
  explicit Library(const std::string& path)
      : handle_(dlopen(path.c_str(), RTLD_LAZY | RTLD_LOCAL | RTLD_FIRST)) {
    if (!handle_) {
      std::fprintf(stderr, "Parc Helper: %s\n", dlerror());
    }
  }
  ~Library() {
    if (handle_) {
      dlclose(handle_);
    }
  }
  Library(const Library&) = delete;
  Library& operator=(const Library&) = delete;
  template <typename T>
  T Symbol(const char* name) const {
    if (!handle_) {
      return nullptr;
    }
    dlerror();
    void* value = dlsym(handle_, name);
    if (const char* error = dlerror()) {
      std::fprintf(stderr, "Parc Helper: %s\n", error);
      return nullptr;
    }
    return reinterpret_cast<T>(value);
  }

 private:
  void* handle_;
};

}  // namespace

int main(int argc, char** argv) {
  uint32_t size = 0;
  if (_NSGetExecutablePath(nullptr, &size) != -1 || size == 0) {
    return 1;
  }
  std::vector<char> executable(size);
  if (_NSGetExecutablePath(executable.data(), &size) != 0) {
    return 1;
  }
  std::string path(executable.data());
  auto slash = path.rfind('/');
  if (slash == std::string::npos) {
    return 1;
  }
  std::string framework = path.substr(0, slash) +
                          "/../../../Chromium Embedded Framework.framework/";
  Library engine(framework + "Chromium Embedded Framework");
  auto execute =
      engine.Symbol<int (*)(int, char**)>("parc_engine_execute_process");
  if (!execute) {
    return 1;
  }
  int result = execute(argc, argv);
  return result < 0 ? 1 : result;
}
