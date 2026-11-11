// Copyright 2026 Parc contributors.
// Portions copyright 2020 The Chromium Embedded Framework Authors
// (cef/libcef/browser/chrome/chrome_content_browser_client_cef.cc,
// chrome_browser_main_extra_parts_cef.cc).
#include "parc/parc_content_clients.h"

#include <utility>

#include "base/apple/foundation_util.h"
#include "base/command_line.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "chrome/browser/child_process_host_flags.h"
#include "chrome/browser/ui/login/http_auth_coordinator.h"
#include "chrome/browser/chrome_browser_main.h"
#include "chrome/common/chrome_constants.h"
#include "chrome/renderer/process_state.h"
#include "content/public/browser/browser_url_handler.h"
#include "content/public/common/content_switches.h"
#include "parc/chromium_hooks.h"
#include "parc/native/file_dialog.h"
#include "parc/native/http_auth.h"
#include "parc/native/native_appkit_host.h"
#include "parc/native/native_internal_urls.h"
#include "parc/native/native_web_contents_view_delegate.h"
#include "parc/native/site_permissions.h"
#include "parc/parc_bundle_mac.h"
#include "parc/parc_branding.h"
#include "parc/renderer/website_theme_agent.h"
#include "third_party/parc_fairplay/chromium/fairplay_cdm_info.h"

namespace parc {
namespace {
// Only this helper is signed without library validation, because the
// component-updated Widevine CDM carries Google's code signature.
constexpr char kMacHelperSuffixCdm[] = " (CDM)";
// The flag after Chrome's own helper flags.
constexpr int kChildProcessHelperCdm =
    std::to_underlying(ChildProcessHostFlags::kChildProcessHelperAlerts) + 1;
constexpr char kInputDiagnostics[] = "parc-input-diagnostics";
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
    parc_hooks::SetAlreadyRunningCommandLineHandler(
        [](const base::CommandLine& command_line, const base::FilePath& cwd,
           void* context) {
          static_cast<NativeApplication*>(context)->AlreadyRunningRelaunch(
              command_line, cwd);
        },
        &*client_->application_);
  }
  void PreMainMessageLoopRun() override {
    // Before any page exists.
    parc_hooks::SetPermissionPromptFactory(&CreateSitePermissionPrompt);
    parc_hooks::SetLoginHandlerAuthValidator(&ValidateNativeLoginHandlerAuth);
    RegisterNativeFileDialogs();
    RegisterLicenseWebUI();
  }
  void PostMainMessageLoopRun() override {
    parc_hooks::SetAlreadyRunningCommandLineHandler(nullptr, nullptr);
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

void ParcContentClient::AddContentDecryptionModules(
    std::vector<content::CdmInfo>* cdms,
    std::vector<media::CdmHostFilePath>* cdm_host_file_paths) {
  ChromeContentClient::AddContentDecryptionModules(cdms, cdm_host_file_paths);
  if (cdms) {
    cdms->push_back(fairplay::GetFairPlayCdmInfo());
  }
}

ParcContentBrowserClient::ParcContentBrowserClient(
    NativeApplication& application)
    : application_(application) {}

ParcContentBrowserClient::~ParcContentBrowserClient() = default;

std::unique_ptr<content::BrowserMainParts>
ParcContentBrowserClient::CreateBrowserMainParts(bool is_integration_test) {
  // A bundle without the CDM helper keeps the CDM in the default helper. This
  // runs before the UI thread disallows blocking work.
  if (base::apple::AmIBundled() &&
      base::PathExists(HelperExecutablePath(kMacHelperSuffixCdm))) {
    parc_hooks::SetCdmServiceChildFlags(kChildProcessHelperCdm);
  }
  auto parts =
      ChromeContentBrowserClient::CreateBrowserMainParts(is_integration_test);
  static_cast<ChromeBrowserMainParts*>(parts.get())
      ->AddParts(std::make_unique<ParcBrowserMainExtraParts>(*this));
  return parts;
}

std::unique_ptr<HttpAuthCoordinator>
ParcContentBrowserClient::CreateHttpAuthCoordinator() {
  return CreateNativeHttpAuthCoordinator();
}

base::FilePath ParcContentBrowserClient::GetChildProcessPath(int flags) {
  if (flags == kChildProcessHelperCdm) {
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

std::unique_ptr<media::KeySystemSupportRegistration>
ParcContentRendererClient::GetSupportedKeySystems(
    content::RenderFrame* render_frame,
    media::GetSupportedKeySystemsCB cb) {
  // Chrome builds its key systems from the browser's capabilities and skips
  // FairPlay's, so FairPlay joins each update. Persistence follows Chrome's
  // rule for its own key systems.
  return ChromeContentRendererClient::GetSupportedKeySystems(
      render_frame,
      base::BindRepeating(
          [](bool can_persist_data, const media::GetSupportedKeySystemsCB& cb,
             media::KeySystemInfos key_systems) {
            key_systems.push_back(
                fairplay::CreateFairPlayKeySystemInfo(can_persist_data));
            cb.Run(std::move(key_systems));
          },
          !process_state::IsIncognitoProcess(), std::move(cb)));
}
}  // namespace parc
