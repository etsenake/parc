// Copyright 2026 Parc contributors.
// Portions copyright 2020 The Chromium Embedded Framework Authors
// (cef/libcef/browser/main_runner.cc).
#include "native_engine_entry.h"

#import <AppKit/AppKit.h>
#import <Security/Security.h>

#include <memory>
#include <string>
#include <vector>

#include "base/apple/bundle_locations.h"
#include "base/check.h"
#include "base/command_line.h"
#include "base/files/file_enumerator.h"
#include "base/files/file_path.h"
#include "base/files/file_util.h"
#include "base/files/important_file_writer.h"
#include "base/functional/bind.h"
#include "base/no_destructor.h"
#include "base/run_loop.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/browser_process_impl.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/common/chrome_result_codes.h"
#include "chrome/common/chrome_switches.h"
#include "components/keep_alive_registry/keep_alive_types.h"
#include "components/keep_alive_registry/scoped_keep_alive.h"
#include "components/os_crypt/common/keychain_password_mac.h"
#include "content/public/app/content_main.h"
#include "content/public/app/content_main_runner.h"
#include "content/public/common/content_switches.h"
#include "content/public/common/result_codes.h"
#include "fairplay_identity.h"
#include "native_airplay.h"
#include "native_appkit_host.h"
#include "native_browser.h"
#include "native_keychain_namespace.h"
#include "native_page_binding.h"
#include "native_profiles.h"
#include "native_startup_policy.h"
#include "parc/parc_bundle_mac.h"
#include "parc/parc_main_delegate.h"

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
// The browser session, created by parc_engine_initialize and destroyed in
// reverse order by parc_engine_shutdown_if_idle. ContentMainParams borrows
// argv, so the strings and the null-terminated pointer array live as long.
struct Session {
  std::vector<std::string> arguments;
  std::vector<char*> argv;
  std::unique_ptr<parc::NativeApplication> application;
  std::unique_ptr<parc::ParcMainDelegate> delegate;
  std::unique_ptr<content::ContentMainRunner> runner;
  // Keeps the browser alive with no windows open; released to quit.
  std::unique_ptr<ScopedKeepAlive> keep_alive;
};
Session& CurrentSession() {
  static base::NoDestructor<Session> session;
  return *session;
}
void (*idle_ready)(void*) = nullptr;
void* idle_context = nullptr;
bool idle_check_posted = false;
bool idle_quit_armed = false;
bool IsNormalEarlyExit(int code) {
  switch (code) {
    case content::RESULT_CODE_NORMAL_EXIT:
    case CHROME_RESULT_CODE_NORMAL_EXIT_PROCESS_NOTIFIED:
    case CHROME_RESULT_CODE_NORMAL_EXIT_PACK_EXTENSION_SUCCESS:
    case CHROME_RESULT_CODE_NORMAL_EXIT_AUTO_DE_ELEVATED:
    case CHROME_RESULT_CODE_NORMAL_EXIT_RELAUNCH_REQUESTED:
    case CHROME_RESULT_CODE_NORMAL_EXIT_RELAUNCH_BACKGROUND:
      return true;
    default:
      return false;
  }
}
bool IsAbsolute(const char* path) {
  return path && *path && base::FilePath(path).IsAbsolute();
}
// Both must exist; symlinks and relative components are resolved.
bool SamePath(const base::FilePath& actual, const char* expected) {
  const base::FilePath resolved = base::MakeAbsoluteFilePath(actual);
  return !resolved.empty() &&
         resolved == base::MakeAbsoluteFilePath(base::FilePath(expected));
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
  return !parc::HasPendingNativeApplicationWork() &&
         !parc::NativeProfilesLoading() &&
         !parc::NativeProfilesHaveOperations() &&
         parc::NativeBrowsersAlive() == 0 && parc::NativePagesAlive() == 0 &&
         GlobalBrowserCollection::GetInstance()->GetSize() == 0;
}
// Releasing the last keepalive starts Chrome's browser shutdown, which runs
// the loop's quit closure once nothing else keeps the browser alive.
void QuitMessageLoop() {
  CurrentSession().keep_alive.reset();
}
void CheckPendingIdleQuit() {
  idle_check_posted = false;
  if (state == State::kRunning && idle_ready && !idle_quit_armed && IsIdle()) {
    idle_quit_armed = true;
    QuitMessageLoop();
  }
}
parc_engine_start_result Fail(int code, int* exit_code) {
  *exit_code = code;
  state = State::kFailed;
  return PARC_ENGINE_START_FAILED;
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
  const base::CommandLine command_line(argc, argv);
  if (!command_line.HasSwitch(switches::kProcessType)) {
    return -1;
  }
  if (command_line.GetSwitchValueASCII(switches::kProcessType).empty()) {
    return 64;
  }
  // A helper outside its application bundle is a packaging defect.
  CHECK(parc::InstallBundleOverrides());
  parc::ParcMainDelegate delegate(nullptr);
  content::ContentMainParams params(&delegate);
  params.argc = argc;
  params.argv = const_cast<const char**>(argv);
  return content::ContentMain(std::move(params));
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
      << "Native application must implement Chromium's sendEvent protocol";
  if (!IsAbsolute(root_cache_path) || !IsAbsolute(framework_path) ||
      !IsAbsolute(bundle_path) || !IsAbsolute(helper_executable_path)) {
    return Fail(64, exit_code);
  }
  // Paths come from the framework's own location. The caller's must agree,
  // or the shell and engine would be using different installations.
  if (!parc::InstallBundleOverrides() ||
      !SamePath(base::apple::FrameworkBundlePath(), framework_path) ||
      !SamePath(base::apple::OuterBundlePath(), bundle_path) ||
      !SamePath(parc::HelperExecutablePath(""), helper_executable_path)) {
    LOG(ERROR) << "The engine framework is not the one this application packages.";
    return Fail(64, exit_code);
  }
  auto& session = CurrentSession();
  // Chromium's CommandLine groups switches before positional arguments. Bind
  // Parc's two valued switches before that parsing, so a second-process
  // handoff cannot mistake the profile directory for an open destination.
  auto& arguments = session.arguments;
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
  session.argv.reserve(arguments.size() + 1);
  for (auto& argument : arguments) {
    session.argv.push_back(argument.data());
  }
  session.argv.push_back(nullptr);
  const auto storage = ConfigureStorageNamespace(root_cache_path, arguments);
  if (storage == parc::StorageNamespace::kInvalid) {
    LOG(ERROR) << "Parc Safe Storage preparation failed; existing encrypted data was preserved. "
                  "Allow normal Keychain access and retry; no encryption key was replaced.";
    return Fail(78, exit_code);
  }
  // Before any profile or OSCrypt provider starts.
  KeychainPassword::GetServiceName() = parc::kParcStorageService;
  KeychainPassword::GetAccountName() = parc::StorageAccount(storage);
  // Before any page or worker exists: Safari's identity for FairPlay sites.
  parc::InstallFairPlayIdentity();
  parc::InstallNativeAirPlay();

  base::CommandLine::Init(static_cast<int>(arguments.size()),
                          session.argv.data());
  auto& command_line = *base::CommandLine::ForCurrentProcess();
  // The exact root, which Chrome also hands every child process.
  command_line.RemoveSwitch(switches::kUserDataDir);
  command_line.AppendSwitchPath(switches::kUserDataDir,
                                base::FilePath(root_cache_path));
  parc::ApplyNativeStartupPolicy(command_line);

  session.application = parc::CreateNativeApplication();
  CHECK(session.application);
  session.delegate =
      std::make_unique<parc::ParcMainDelegate>(session.application.get());
  session.runner = content::ContentMainRunner::Create();
  content::ContentMainParams params(session.delegate.get());
  params.argc = static_cast<int>(arguments.size());
  params.argv = const_cast<const char**>(session.argv.data());
  int code = content::ContentMainInitialize(std::move(params),
                                            session.runner.get());
  if (code < 0) {
    // Runs Chrome's browser startup up to its main loop, which Parc runs.
    code = session.runner->Run();
  }
  *exit_code = code;
  if (code != content::RESULT_CODE_NORMAL_EXIT) {
    // A normal singleton handoff or startup command, or a failure. Like Chrome,
    // the process exits from here without shutting the engine down.
    const bool normal_exit = IsNormalEarlyExit(code);
    state = normal_exit ? State::kEarlyExit : State::kFailed;
    return normal_exit ? PARC_ENGINE_START_EARLY_EXIT : PARC_ENGINE_START_FAILED;
  }
  Profile* initial_profile = session.delegate->browser_client().initial_profile();
  CHECK(initial_profile);
  auto* application = session.application.get();
  parc::ConfigureNativeProfiles(
      base::FilePath(root_cache_path),
      base::BindRepeating(&parc::NativeApplication::ProfileInitializer,
                          base::Unretained(application)),
      base::BindRepeating(&parc::NativeApplication::ProfilesChanged,
                          base::Unretained(application)));
  application->BrowserReady(*initial_profile);
  parc::SetNativeProfilesReady();
  state = State::kReady;
  return PARC_ENGINE_START_READY;
}
extern "C" PARC_ENGINE_EXPORT void parc_engine_run_message_loop() {
  CHECK([NSThread isMainThread]);
  CHECK(state == State::kReady);
  state = State::kRunning;
  auto& session = CurrentSession();
  base::RunLoop run_loop;
  session.keep_alive = std::make_unique<ScopedKeepAlive>(
      KeepAliveOrigin::APP_CONTROLLER, KeepAliveRestartOption::DISABLED);
  // As ChromeBrowserMainParts would: the browser process now owns the
  // loop's lifetime.
  static_cast<BrowserProcessImpl*>(g_browser_process)
      ->SetQuitClosure(run_loop.QuitWhenIdleClosure());
  run_loop.Run();
  state = State::kReturned;
  if (idle_quit_armed) {
    CHECK(IsIdle());
    auto callback = idle_ready;
    void* context = idle_context;
    idle_ready = nullptr;
    idle_context = nullptr;
    // No subsequent engine access: callback may perform the real shutdown.
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
  QuitMessageLoop();
  return 1;
}
extern "C" PARC_ENGINE_EXPORT int parc_engine_shutdown_if_idle() {
  CHECK([NSThread isMainThread]);
  if ((state != State::kReturned && state != State::kReady) || !IsIdle()) {
    return 0;
  }
  state = State::kStopped;
  auto& session = CurrentSession();
  session.keep_alive.reset();
  parc::PrepareNativeApplicationShutdown();
  parc::ShutdownNativeProfiles();
  session.delegate->ShutdownBrowser();
  session.runner->Shutdown();
  session.runner.reset();
  session.delegate.reset();
  session.application.reset();
  session.argv.clear();
  session.arguments.clear();
  return 1;
}
