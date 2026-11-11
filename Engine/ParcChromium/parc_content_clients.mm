// Copyright 2026 Parc contributors.
// Portions copyright 2020 The Chromium Embedded Framework Authors
// (cef/libcef/browser/chrome/chrome_content_browser_client_cef.cc,
// chrome_browser_main_extra_parts_cef.cc).
#include "parc/parc_content_clients.h"

#include <utility>

#include "base/apple/foundation_util.h"
#include "base/check.h"
#include "base/command_line.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "chrome/browser/child_process_host_flags.h"
#include "chrome/browser/chrome_browser_main.h"
#include "chrome/browser/ui/startup/startup_browser_creator.h"
#include "chrome/common/chrome_constants.h"
#include "content/browser/media/service_factory.h"
#include "content/public/browser/browser_url_handler.h"
#include "content/public/browser/web_contents_view_delegate.h"
#include "content/public/common/content_switches.h"
#include "parc/native/file_dialog.h"
#include "parc/native/native_appkit_host.h"
#include "parc/native/native_internal_urls.h"
#include "parc/native/native_web_contents_view_delegate.h"
#include "parc/native/site_permissions.h"
#include "parc/parc_bundle_mac.h"
#include "parc/renderer/website_theme_agent.h"

namespace parc {
namespace {
// Only this helper is signed without library validation, because the
// component-updated Widevine CDM carries Google's code signature.
constexpr char kMacHelperSuffixCdm[] = " (CDM)";
constexpr char kInputDiagnostics[] = "parc-input-diagnostics";
ParcContentBrowserClient* g_browser_client = nullptr;
}  // namespace

class ParcBrowserMainExtraParts final : public ChromeBrowserMainExtraParts {
 public:
  explicit ParcBrowserMainExtraParts(ParcContentBrowserClient& client)
      : client_(client) {}

  void PostProfileInit(Profile* profile, bool is_initial_profile) override {
    if (is_initial_profile) {
      client_->initial_profile_ = profile;
    }
  }
  void PostBrowserStart() override {
    // Chrome's own PostBrowserStart, which follows, lets ProcessSingleton
    // deliver second launches; the native handoff must be in place first.
    StartupBrowserCreator::RegisterProcessCommandLineCallback(
        base::BindRepeating(&NativeApplication::AlreadyRunningRelaunch,
                            base::Unretained(&*client_->application_)));
  }
  void PreMainMessageLoopRun() override {
    // Before any page exists.
    RegisterNativeSitePermissionPrompts();
    RegisterNativeFileDialogs();
  }
  void PostMainMessageLoopRun() override {
    StartupBrowserCreator::RegisterProcessCommandLineCallback({});
    client_->initial_profile_ = nullptr;
  }

 private:
  const raw_ref<ParcContentBrowserClient> client_;
};

void ParcContentClient::AddAdditionalSchemes(Schemes* schemes) {
  ChromeContentClient::AddAdditionalSchemes(schemes);
  schemes->standard_schemes.push_back(kInternalScheme);
  schemes->secure_schemes.push_back(kInternalScheme);
  schemes->cors_enabled_schemes.push_back(kInternalScheme);
  schemes->savable_schemes.push_back(kInternalScheme);
}

ParcContentBrowserClient::ParcContentBrowserClient(
    NativeApplication& application)
    : application_(application) {
  CHECK(!g_browser_client);
  g_browser_client = this;
}

ParcContentBrowserClient::~ParcContentBrowserClient() {
  g_browser_client = nullptr;
}

// static
ParcContentBrowserClient& ParcContentBrowserClient::Get() {
  CHECK(g_browser_client);
  return *g_browser_client;
}

std::unique_ptr<content::BrowserMainParts>
ParcContentBrowserClient::CreateBrowserMainParts(bool is_integration_test) {
  // A bundle without the CDM helper keeps the CDM in the default helper. This
  // runs before the UI thread disallows blocking work.
  if (base::apple::AmIBundled() &&
      base::PathExists(HelperExecutablePath(kMacHelperSuffixCdm))) {
    content::SetCdmServiceChildFlags(
        std::to_underlying(ChildProcessHostFlags::kChildProcessHelperCdm));
  }
  auto parts =
      ChromeContentBrowserClient::CreateBrowserMainParts(is_integration_test);
  static_cast<ChromeBrowserMainParts*>(parts.get())
      ->AddParts(std::make_unique<ParcBrowserMainExtraParts>(*this));
  return parts;
}

base::FilePath ParcContentBrowserClient::GetChildProcessPath(int flags) {
  if (flags ==
      std::to_underlying(ChildProcessHostFlags::kChildProcessHelperCdm)) {
    return base::apple::AmIBundled() ? HelperExecutablePath(kMacHelperSuffixCdm)
                                     : base::FilePath();
  }
  // Chrome's Alerts helper lives inside its framework; Parc's sits beside the
  // other helpers.
  if (flags ==
      std::to_underlying(ChildProcessHostFlags::kChildProcessHelperAlerts)) {
    return base::apple::AmIBundled()
               ? HelperExecutablePath(chrome::kMacHelperSuffixAlerts)
               : base::FilePath();
  }
  return ChromeContentBrowserClient::GetChildProcessPath(flags);
}

void ParcContentBrowserClient::AppendExtraCommandLineSwitches(
    base::CommandLine* command_line,
    int child_process_id) {
  ChromeContentBrowserClient::AppendExtraCommandLineSwitches(command_line,
                                                             child_process_id);
  // The input-diagnostics opt-in follows only the renderer receiving the
  // observed input.
  if (command_line->GetSwitchValueASCII(switches::kProcessType) ==
          switches::kRendererProcess &&
      base::CommandLine::ForCurrentProcess()->HasSwitch(kInputDiagnostics)) {
    command_line->AppendSwitch(kInputDiagnostics);
  }
}

bool ParcContentBrowserClient::IsHandledURL(const GURL& url) {
  return ChromeContentBrowserClient::IsHandledURL(CanonicalInternalURL(url));
}

void ParcContentBrowserClient::BrowserURLHandlerCreated(
    content::BrowserURLHandler* handler) {
  // Rewrite parc: to its Chrome page and return false, so the genuine Profile,
  // about: aliases, policy and WebUI handlers still run.
  handler->AddHandlerPair(
      [](GURL* url, content::BrowserContext*) {
        *url = CanonicalInternalURL(*url);
        return false;
      },
      nullptr);
  ChromeContentBrowserClient::BrowserURLHandlerCreated(handler);
}

std::unique_ptr<content::WebContentsViewDelegate>
ParcContentBrowserClient::GetWebContentsViewDelegate(
    content::WebContents* web_contents) {
  return CreateNativeWebContentsViewDelegate(web_contents);
}

void ParcContentRendererClient::RenderFrameCreated(
    content::RenderFrame* render_frame) {
  ChromeContentRendererClient::RenderFrameCreated(render_frame);
  // Owned by the frame it observes.
  new WebsiteThemeAgent(render_frame);
}
}  // namespace parc
