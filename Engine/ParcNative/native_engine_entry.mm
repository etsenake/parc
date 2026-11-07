// Copyright 2026 Parc contributors.
#include "native_engine_entry.h"

#import <AppKit/AppKit.h>
#import <Security/Security.h>

#include <string>
#include <vector>

#include "base/check.h"
#include "base/files/file_path.h"
#include "base/files/file_enumerator.h"
#include "base/files/file_util.h"
#include "base/files/important_file_writer.h"
#include "base/functional/bind.h"
#import "base/mac/scoped_sending_event.h"
#include "base/no_destructor.h"
#include "base/task/single_thread_task_runner.h"
#include "cef/include/cef_app.h"
#include "cef/libcef/browser/browser_info_manager.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "components/os_crypt/common/keychain_password_mac.h"
#include "fairplay_identity.h"
#include "native_airplay.h"
#include "native_appkit_host.h"
#include "native_host_route.h"
#include "native_keychain_namespace.h"

namespace {
enum class State {
  kFresh,
  kReady,
  kRunning,
  kReturned,
  kEarlyExit,
  kFailed,
  kStopped
};
State state = State::kFresh;
CefRefPtr<CefApp>& Application() {
  static base::NoDestructor<CefRefPtr<CefApp>> application;
  return *application;
}
// ContentMainParams contains borrowed argv. Retain both its strings and the
// null-terminated pointer array through CefShutdown, regardless of which
// startup/early-exit path consumes those pointers.
struct MainArguments {
  std::vector<std::string> strings;
  std::vector<char*> pointers;
};
MainArguments& Arguments() {
  static base::NoDestructor<MainArguments> arguments;
  return *arguments;
}
void (*idle_ready)(void*) = nullptr;
void* idle_context = nullptr;
bool idle_check_posted = false;
bool idle_quit_armed = false;
bool IsNormalEarlyExit(int code) {
  switch (code) {
    case CEF_RESULT_CODE_NORMAL_EXIT:
    case CEF_RESULT_CODE_NORMAL_EXIT_PROCESS_NOTIFIED:
    case CEF_RESULT_CODE_NORMAL_EXIT_PACK_EXTENSION_SUCCESS:
    case CEF_RESULT_CODE_NORMAL_EXIT_AUTO_DE_ELEVATED:
    case CEF_RESULT_CODE_NORMAL_EXIT_RELAUNCH_REQUESTED:
    case CEF_RESULT_CODE_NORMAL_EXIT_RELAUNCH_BACKGROUND:
      return true;
    default:
      return false;
  }
}
bool IsAbsolute(const char* path) {
  return path && *path && base::FilePath(path).IsAbsolute();
}
parc::StorageKey ReadStorageKey(const char* service, const char* account) {
  NSDictionary* query = @{
    (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService : @(service),
    (__bridge id)kSecAttrAccount : @(account),
    (__bridge id)kSecReturnData : @YES,
    (__bridge id)kSecMatchLimit : (__bridge id)kSecMatchLimitOne
  };
  CFTypeRef value = nullptr;
  OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &value);
  if (status != errSecSuccess || !value) {
    if (value) CFRelease(value);
    return {status == errSecItemNotFound ? parc::StorageKeyStatus::kMissing
                                        : parc::StorageKeyStatus::kError, {}};
  }
  if (CFGetTypeID(value) != CFDataGetTypeID()) {
    CFRelease(value);
    return {parc::StorageKeyStatus::kError, {}};
  }
  auto data = static_cast<CFDataRef>(value);
  if (CFDataGetLength(data) == 0) {
    CFRelease(value);
    return {parc::StorageKeyStatus::kError, {}};
  }
  std::vector<unsigned char> bytes(CFDataGetBytePtr(data),
                                 CFDataGetBytePtr(data) + CFDataGetLength(data));
  CFRelease(value);
  return {parc::StorageKeyStatus::kFound, std::move(bytes)};
}
parc::StorageKeyStatus AddStorageKey(const char* service, const char* account,
                                   const std::vector<unsigned char>& bytes) {
  NSDictionary* attributes = @{
    (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService : @(service),
    (__bridge id)kSecAttrAccount : @(account),
    (__bridge id)kSecAttrLabel : @"Parc Safe Storage",
    (__bridge id)kSecValueData : [NSData dataWithBytes:bytes.data() length:bytes.size()]
  };
  // Ordinary create-only Keychain operation. Never change the old item's ACL,
  // update a different key, suppress user approval, or export key material.
  OSStatus status = SecItemAdd((__bridge CFDictionaryRef)attributes, nullptr);
  return status == errSecSuccess ? parc::StorageKeyStatus::kFound
       : status == errSecDuplicateItem ? parc::StorageKeyStatus::kDuplicate
                                      : parc::StorageKeyStatus::kError;
}
parc::StorageNamespace ConfigureStorageNamespace(const char* root_cache_path,
                                               const std::vector<std::string>& arguments) {
  // The existing disposable runtime harness uses Chromium's own mock provider;
  // it must not read or migrate the user's real Keychain or write a marker.
  for (const auto& argument : arguments)
    if (argument == "--use-mock-keychain" ||
        argument.starts_with("--use-mock-keychain="))
      return parc::StorageNamespace::kParc;
  const base::FilePath root(root_cache_path);
  const auto marker = root.AppendASCII(".parc-keychain-namespace");
  auto recorded = parc::StorageNamespace::kUnset;
  if (base::PathExists(marker)) {
    std::string contents;
    if (!base::ReadFileToStringWithMaxSize(marker, &contents, 64))
      return parc::StorageNamespace::kInvalid;
    recorded = parc::ParseStorageMarker(contents);
  }
  bool existing_profile = base::PathExists(root.AppendASCII("Local State"));
  if (!existing_profile && recorded == parc::StorageNamespace::kUnset) {
    // Also preserve Profiles restored without their root's Local State. Only
    // inspect immediate Profile database paths, never walk the browser cache.
    base::FileEnumerator profiles(root, false, base::FileEnumerator::DIRECTORIES);
    for (auto path = profiles.Next(); !path.empty(); path = profiles.Next()) {
      if (base::PathExists(path.AppendASCII("Login Data")) ||
          base::PathExists(path.AppendASCII("Cookies")) ||
          base::PathExists(path.AppendASCII("Network").AppendASCII("Cookies"))) {
        existing_profile = true;
        break;
      }
    }
  }
  return parc::PrepareStorageNamespace(
      recorded, existing_profile,
      ReadStorageKey, AddStorageKey, [&](std::string_view contents) {
        return base::CreateDirectory(root) &&
               base::ImportantFileWriter::WriteFileAtomically(marker, contents);
      });
}
bool IsIdle() {
  return !parc::HasPendingNativeApplicationWork() && !parc::HasLoadingNativeProfiles() &&
         parc::NativeBrowsersAlive() == 0 &&
         GlobalBrowserCollection::GetInstance()->GetSize() == 0 &&
         CefBrowserInfoManager::GetInstance()->GetBrowserInfoList().empty();
}
void CheckPendingIdleQuit() {
  idle_check_posted = false;
  if (state == State::kRunning && idle_ready && !idle_quit_armed && IsIdle()) {
    idle_quit_armed = true;
    CefQuitMessageLoop();
  }
}
}  // namespace
namespace parc {
void NotifyNativeEngineOwnershipChanged() {
  CHECK([NSThread isMainThread]);
  if (state != State::kRunning || !idle_ready || idle_check_posted) {
    return;
  }
  idle_check_posted = true;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&CheckPendingIdleQuit));
}
}  // namespace parc
extern "C" PARC_ENGINE_EXPORT int parc_engine_execute_process(int argc,
                                                              char** argv) {
  CHECK(state == State::kFresh);
  CefMainArgs args(argc, argv);
  // CefApp's renderer/utility hooks are supplied by the same source-owned app.
  return CefExecuteProcess(args, parc::CreateNativeApplication(), nullptr);
}
extern "C" PARC_ENGINE_EXPORT parc_engine_start_result
parc_engine_initialize(int argc,
                       char** argv,
                       const char* root_cache_path,
                       const char* framework_path,
                       const char* bundle_path,
                       const char* helper_executable_path,
                       int* exit_code) {
  CHECK([NSThread isMainThread]);
  CHECK(state == State::kFresh);
  CHECK(exit_code);
  CHECK([NSApp conformsToProtocol:@protocol(CrAppControlProtocol)])
      << "Native application must implement the real CEF sendEvent protocol";
  if (!IsAbsolute(root_cache_path) || !IsAbsolute(framework_path) ||
      !IsAbsolute(bundle_path) || !IsAbsolute(helper_executable_path)) {
    *exit_code = 64;
    state = State::kFailed;
    return PARC_ENGINE_START_FAILED;
  }
  // Chromium's CommandLine groups switches before positional arguments. Bind
  // Parc's two valued switches before that parsing, so a second-process
  // handoff cannot mistake the profile directory for an open destination.
  auto& arguments = Arguments().strings;
  arguments.reserve(argc);
  bool positional_only = false;
  for (int i = 0; i < argc; ++i) {
    std::string argument(argv[i]);
    if (i > 0 && argument == "--") {
      positional_only = true;
    }
    if (i > 0 && !positional_only &&
        (argument == "--parc-profile" || argument == "--parc-open") &&
        i + 1 < argc) {
      argument += "=";
      argument += argv[++i];
    }
    arguments.push_back(std::move(argument));
  }
  auto& native_arguments = Arguments().pointers;
  native_arguments.reserve(arguments.size() + 1);
  for (auto& argument : arguments) {
    native_arguments.push_back(argument.data());
  }
  native_arguments.push_back(nullptr);
  CefMainArgs args(static_cast<int>(arguments.size()), native_arguments.data());
  CefSettings settings;
  settings.no_sandbox = false;
  settings.multi_threaded_message_loop = false;
  settings.external_message_pump = false;
  settings.windowless_rendering_enabled = false;
  CefString(&settings.root_cache_path) = root_cache_path;
  CefString(&settings.framework_dir_path) = framework_path;
  CefString(&settings.main_bundle_path) = bundle_path;
  // Keep the standard per-process macOS helper selection. An explicit
  // browser_subprocess_path becomes a global command-line override and makes
  // ChildProcessHost::GetChildPath return the default helper before selecting
  // Renderer/GPU entitlements or the Alerts helper. CEF derives the base path
  // from the actual executable (Parc or the native runtime test app).
  // The supplied helper path remains subject to our startup validation above.
  const auto storage = ConfigureStorageNamespace(root_cache_path, arguments);
  if (storage == parc::StorageNamespace::kInvalid) {
    LOG(ERROR) << "Parc Safe Storage preparation failed; existing encrypted data was preserved. "
                  "Allow normal Keychain access and retry; no encryption key was replaced.";
    *exit_code = 78;
    state = State::kFailed;
    return PARC_ENGINE_START_FAILED;
  }
  // Our direct internal C++ startup does not run libcef_dll_wrapper's API hash
  // setup. Its runtime version stays unset, so CEF's version-guarded settings
  // assignment is skipped. Configure the shared OSCrypt names explicitly before
  // any profile/provider starts; retain matching settings for wrapper callers.
  KeychainPassword::GetServiceName() = parc::kParcStorageService;
  KeychainPassword::GetAccountName() = parc::StorageAccount(storage);
  CefString(&settings.keychain_service_name) = parc::kParcStorageService;
  CefString(&settings.keychain_account_name) = parc::StorageAccount(storage);
  // Profiles use explicit request-context cache paths below this root; the
  // global context is not silently bound to a different user's Chrome data.
  Application() = parc::CreateNativeApplication();
  CHECK(Application());
  // Before any page or worker exists: Safari's identity for FairPlay sites.
  parc::InstallFairPlayIdentity();
  parc::InstallNativeAirPlay();
  bool initialized = CefInitialize(args, settings, Application(), nullptr);
  *exit_code = CefGetExitCode();
  if (initialized) {
    CHECK_EQ(*exit_code, CEF_RESULT_CODE_NORMAL_EXIT);
    state = State::kReady;
    return PARC_ENGINE_START_READY;
  }
  Application() = nullptr;
  // CefGetExitCode explicitly distinguishes normal singleton/command exits
  // from failures. Like cefsimple, the executable preserves the actual code.
  const bool normal_exit = IsNormalEarlyExit(*exit_code);
  state = normal_exit ? State::kEarlyExit : State::kFailed;
  return normal_exit ? PARC_ENGINE_START_EARLY_EXIT : PARC_ENGINE_START_FAILED;
}
extern "C" PARC_ENGINE_EXPORT void parc_engine_run_message_loop() {
  CHECK([NSThread isMainThread]);
  CHECK(state == State::kReady);
  state = State::kRunning;
  CefRunMessageLoop();
  state = State::kReturned;
  if (idle_quit_armed) {
    CHECK(IsIdle());
    auto callback = idle_ready;
    void* context = idle_context;
    idle_ready = nullptr;
    idle_context = nullptr;
    // No subsequent CEF access: callback may perform real CefShutdown.
    callback(context);
  }
}
extern "C" PARC_ENGINE_EXPORT int parc_engine_request_quit_when_idle(
    void (*ready)(void*),
    void* context) {
  CHECK([NSThread isMainThread]);
  if (state != State::kRunning || !ready || idle_ready) {
    return 0;
  }
  idle_ready = ready;
  idle_context = context;
  parc::NotifyNativeEngineOwnershipChanged();
  return 1;
}
extern "C" PARC_ENGINE_EXPORT int parc_engine_quit_message_loop_if_idle() {
  CHECK([NSThread isMainThread]);
  if (state != State::kRunning || !IsIdle()) {
    return 0;
  }
  CefQuitMessageLoop();
  return 1;
}
extern "C" PARC_ENGINE_EXPORT int parc_engine_shutdown_if_idle() {
  CHECK([NSThread isMainThread]);
  if ((state != State::kReturned && state != State::kReady) || !IsIdle()) {
    return 0;
  }
  state = State::kStopped;
  parc::PrepareNativeApplicationShutdown();
  CefShutdown();
  Application() = nullptr;
  Arguments().pointers.clear();
  Arguments().strings.clear();
  return 1;
}
