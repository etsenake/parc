// Copyright 2026 Parc contributors.
// Portions copyright 2020 The Chromium Embedded Framework Authors
// (cef/libcef/common/chrome/chrome_main_delegate_cef.cc,
// cef/libcef/common/resource_util.cc).
#include "parc/parc_main_delegate.h"

#include <utility>
#include <variant>

#include "base/check.h"
#include "base/command_line.h"
#include "base/path_service.h"
#include "base/time/time.h"
#include "chrome/browser/metrics/chrome_feature_list_creator.h"
#include "chrome/browser/startup_data.h"
#include "chrome/common/chrome_paths.h"
#include "chrome/common/chrome_switches.h"
#include "chrome/common/pref_names.h"
#include "chrome/common/profiler/main_thread_stack_sampling_profiler.h"
#include "components/prefs/pref_service.h"
#include "content/public/browser/browser_main_runner.h"
#include "content/public/common/content_switches.h"
#include "parc/native/native_appkit_host.h"

namespace parc {

ParcMainDelegate::ParcMainDelegate(NativeApplication* application)
    : ChromeMainDelegate({.exe_entry_point_ticks = base::TimeTicks::Now()}),
      application_(application) {}

ParcMainDelegate::~ParcMainDelegate() = default;

void ParcMainDelegate::ShutdownBrowser() {
  // Null after an early exit, before browser startup created it.
  if (browser_runner_) {
    browser_runner_->Shutdown();
    browser_runner_.reset();
  }
}

void ParcMainDelegate::PreSandboxStartup() {
  const auto& command_line = *base::CommandLine::ForCurrentProcess();
  // The browser starts with its exact root on --user-data-dir and Chrome
  // copies it to every child. Chrome's own lookup would also honour a
  // UserDataDir policy and fall back to a fresh default root.
  const base::FilePath root =
      command_line.GetSwitchValuePath(switches::kUserDataDir);
  if (!root.empty()) {
    const bool browser =
        command_line.GetSwitchValueASCII(switches::kProcessType).empty();
    CHECK(base::PathService::OverrideAndCreateIfNeeded(
        chrome::DIR_USER_DATA, root, /*is_absolute=*/true, /*create=*/false));
    base::PathService::Override(chrome::DIR_CRASH_DUMPS, root);
    base::PathService::OverrideAndCreateIfNeeded(
        chrome::DIR_APP_DICTIONARIES, root.Append("Dictionaries"),
        /*is_absolute=*/true, /*create=*/browser);
  }
  ChromeMainDelegate::PreSandboxStartup();
}

std::optional<int> ParcMainDelegate::PreBrowserMain() {
  // Chrome's would register its own NSApplication subclass and switch
  // Chromium's strings to the macOS language. Parc keeps its application and,
  // as under CEF, Chromium's US English strings.
  return content::ContentMainDelegate::PreBrowserMain();
}

std::optional<int> ParcMainDelegate::PostEarlyInitialization(
    InvokedIn invoked_in) {
  auto result = ChromeMainDelegate::PostEarlyInitialization(invoked_in);
  if (!result && std::holds_alternative<InvokedInBrowserProcess>(invoked_in)) {
    // Local State exists but BrowserProcess doesn't own it yet. Parc opens
    // its own windows, never Chrome's profile picker.
    chrome_content_browser_client_->startup_data()
        ->chrome_feature_list_creator()
        ->local_state()
        ->SetBoolean(prefs::kBrowserShowProfilePickerOnStartup, false);
  }
  return result;
}

std::variant<int, content::MainFunctionParams> ParcMainDelegate::RunProcess(
    const std::string& process_type,
    content::MainFunctionParams main_function_params) {
  if (!process_type.empty()) {
    return ChromeMainDelegate::RunProcess(process_type,
                                          std::move(main_function_params));
  }
  browser_runner_ = content::BrowserMainRunner::Create();
  // -1 means initialized: the caller now runs the main loop.
  const int exit_code =
      browser_runner_->Initialize(std::move(main_function_params));
  return exit_code >= 0 ? exit_code : 0;
}

content::ContentClient* ParcMainDelegate::CreateContentClient() {
  return &content_client_;
}

content::ContentBrowserClient* ParcMainDelegate::CreateContentBrowserClient() {
  CHECK(application_);
  // As ChromeMainDelegate's own, with Parc's client type.
  chrome_content_browser_client_ =
      std::make_unique<ParcContentBrowserClient>(*application_);
  CHECK(sampling_profiler_);
  chrome_content_browser_client_->SetSamplingProfiler(
      std::move(sampling_profiler_));
  return chrome_content_browser_client_.get();
}

content::ContentRendererClient*
ParcMainDelegate::CreateContentRendererClient() {
  renderer_client_ = std::make_unique<ParcContentRendererClient>();
  return renderer_client_.get();
}

ui::ResourceBundle::Delegate* ParcMainDelegate::GetResourceBundleDelegate() {
  return application_ ? application_->ResourceBundleDelegate() : nullptr;
}
}  // namespace parc
