// Copyright 2026 Parc contributors.
// Seatbelt must be initialized before loading the engine framework.
// Do not link this executable to the engine framework: dyld would load it
// before main, before SeatbeltExecServer consumes the child's sandbox
// arguments.
#include "base/allocator/early_zone_registration_apple.h"
#include "sandbox/mac/seatbelt_exec.h"

#include <dlfcn.h>
#include <mach-o/dyld.h>

#include <cstdio>
#include <string>
#include <vector>

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
  partition_alloc::EarlyMallocZoneRegistration();
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
  // Same relative layout for Default, Renderer, GPU and Alerts helpers.
  std::string framework = path.substr(0, slash) +
                          "/../../../Chromium Embedded Framework.framework/";
  auto seatbelt = sandbox::SeatbeltExecServer::CreateFromArguments(
      executable.data(), argc, argv);
  if (seatbelt.sandbox_required &&
      (!seatbelt.server || !seatbelt.server->InitializeSandbox())) {
    std::fprintf(stderr, "Parc Helper: sandbox initialization failed\n");
    return 1;
  }
  // Declaration order keeps the sandbox alive until the framework unloads.
  Library engine(framework + "Chromium Embedded Framework");
  auto execute =
      engine.Symbol<int (*)(int, char**)>("parc_engine_execute_process");
  if (!execute) {
    return 1;
  }
  int result = execute(argc, argv);
  // A helper must never become the browser process or create application UI.
  return result < 0 ? 1 : result;
}
