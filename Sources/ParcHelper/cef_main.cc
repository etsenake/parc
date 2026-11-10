// Copyright 2026 Parc contributors.
// The pinned CEF macOS helper initializes libcef_sandbox before loading libcef.
// Do not link this executable to the engine framework: dyld would load it
// before main, before SeatbeltExecServer consumes the child's sandbox
// arguments.
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

class Sandbox {
 public:
  using Initialize = void* (*)(int, char**);
  using Destroy = void (*)(void*);
  Sandbox(const std::string& path, int argc, char** argv) : library_(path) {
    auto initialize = library_.Symbol<Initialize>("cef_sandbox_initialize");
    destroy_ = library_.Symbol<Destroy>("cef_sandbox_destroy");
    // Both functions must exist before creating a context we must destroy.
    if (initialize && destroy_) {
      context_ = initialize(argc, argv);
    }
  }
  ~Sandbox() {
    if (context_) {
      destroy_(context_);
    }
  }
  bool ready() const { return context_ != nullptr; }

 private:
  Library library_;
  Destroy destroy_ = nullptr;
  void* context_ = nullptr;
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
  // Same relative layout for Default, Renderer, GPU and Alerts helpers.
  std::string framework = path.substr(0, slash) +
                          "/../../../Chromium Embedded Framework.framework/";
  Sandbox sandbox(framework + "Libraries/libcef_sandbox.dylib", argc, argv);
  if (!sandbox.ready()) {
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
