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
// Native macOS helper sandbox initialization remains the helper's entry duty.
PARC_ENGINE_EXPORT int parc_engine_execute_process(int argc, char** argv);
typedef enum parc_engine_start_result {
  PARC_ENGINE_START_FAILED = 0,
  PARC_ENGINE_START_READY = 1,
  PARC_ENGINE_START_EARLY_EXIT = 2,
} parc_engine_start_result;
// Browser process/main thread only, once. A normal early exit includes CEF's
// process-singleton handoff and is not an initialization error. exit_code is
// the unmodified CEF code (64 for invalid arguments). After any result other
// than READY, return that code from main; do not run or shut down CEF.
// Paths are absolute UTF-8. root_cache_path is Parc's versioned data root;
// helpers/framework belong to the separately packaged independent engine.
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
// context until ready. Accepted once; ready runs after the CEF loop returns,
// before this function's RunMessageLoop wrapper returns, so the application
// can shut down CEF before approving final AppKit termination. No polling.
PARC_ENGINE_EXPORT int parc_engine_request_quit_when_idle(
    void (*ready)(void* context),
    void* context);
// Only succeeds once all genuine Browser and CEF page hosts are closed. It
// neither approves beforeunload nor force destroys a window/page.
PARC_ENGINE_EXPORT int parc_engine_quit_message_loop_if_idle(void);
// After run returns, on the initialization thread, and only after real close.
PARC_ENGINE_EXPORT int parc_engine_shutdown_if_idle(void);
#ifdef __cplusplus
}
namespace parc {
// Source-owned CEF client calls after OnBeforeClose and shell unregistration;
// the check is posted so CEF finishes removing its host from the real list.
void NotifyNativeEngineOwnershipChanged();
}  // namespace parc
#endif
#endif
