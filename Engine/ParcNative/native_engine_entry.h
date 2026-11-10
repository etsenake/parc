// Copyright 2026 Parc contributors.
// Stable C ABI for the Swift/AppKit executable and real sandboxed helper.
#ifndef PARC_NATIVE_ENGINE_ENTRY_H_
#define PARC_NATIVE_ENGINE_ENTRY_H_
#ifdef __cplusplus
extern "C" {
#endif
#define PARC_ENGINE_EXPORT __attribute__((visibility("default")))

// Invoke from every helper entry before application UI. -1 means browser
// process, otherwise return that child process exit status from main.
// The helper initializes the macOS sandbox before loading this framework.
PARC_ENGINE_EXPORT int parc_engine_execute_process(int argc, char** argv);
typedef enum parc_engine_start_result {
  PARC_ENGINE_START_FAILED = 0,
  PARC_ENGINE_START_READY = 1,
  PARC_ENGINE_START_EARLY_EXIT = 2,
} parc_engine_start_result;
// Browser process/main thread only, once. A normal early exit includes the
// process-singleton handoff and is not an initialization error. exit_code is
// the unmodified Chromium code (64 for invalid arguments or a framework that
// isn't this application's). After any result other than READY, return that
// code from main; do not run or shut down the engine. Paths are absolute
// UTF-8. root_cache_path is Parc's versioned data root; framework, bundle and
// helper must match the packaged layout the framework was loaded from.
PARC_ENGINE_EXPORT parc_engine_start_result
parc_engine_initialize(int argc,
                       char** argv,
                       const char* root_cache_path,
                       const char* framework_path,
                       const char* bundle_path,
                       const char* helper_executable_path,
                       int* exit_code);
PARC_ENGINE_EXPORT void parc_engine_run_message_loop(void);
// Call only after genuine close consent for every window. The caller retains
// context until ready. Accepted once; ready runs after the engine loop
// returns, before parc_engine_run_message_loop returns, so the application
// can shut the engine down before approving final AppKit termination.
PARC_ENGINE_EXPORT int parc_engine_request_quit_when_idle(
    void (*ready)(void* context),
    void* context);
// Only succeeds once all genuine Browsers and native pages are closed. It
// neither approves beforeunload nor force destroys a window/page.
PARC_ENGINE_EXPORT int parc_engine_quit_message_loop_if_idle(void);
// After run returns, on the initialization thread, and only after real close.
PARC_ENGINE_EXPORT int parc_engine_shutdown_if_idle(void);
#ifdef __cplusplus
}
namespace parc {
// Called when a native page binding or Browser goes away, or profile work
// ends; the idle check is posted so the owner finishes its own teardown.
void NotifyNativeEngineOwnershipChanged();
}  // namespace parc
#endif
#endif
