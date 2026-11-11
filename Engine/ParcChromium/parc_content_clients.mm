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
#include "chrome/browser/extensions/component_loader.h"
#include "chrome/browser/ui/autofill/autofill_bubble_handler.h"
#include "chrome/browser/ui/login/http_auth_coordinator.h"
#include "chrome/browser/chrome_browser_main.h"
#include "chrome/browser/webauthn/chrome_authenticator_request_delegate.h"
#include "chrome/common/chrome_constants.h"
#include "chrome/renderer/process_state.h"
#include "components/autofill/content/browser/content_autofill_client.h"
#include "components/autofill/core/browser/ui/autofill_ui_presentation.h"
#include "content/browser/media/parc_video_toolbox_decoding.h"
#include "content/public/browser/browser_url_handler.h"
#include "content/public/browser/overlay_window.h"
#include "content/public/browser/video_picture_in_picture_window_controller.h"
#include "content/public/browser/web_contents_view_delegate.h"
#include "content/public/common/content_switches.h"
#include "media/base/audio_codecs.h"
#include "media/base/media_types.h"
#include "media/base/parc_av1_support.h"
#include "media/mojo/mojom/parc_video_toolbox_decoding.mojom.h"
#include "mojo/public/cpp/bindings/binder_map.h"
#include "parc/chromium_hooks.h"
#include "parc/frame_focus.h"
#include "parc/internal_extension_manifest.h"
#include "parc/page_preferences.h"
#include "parc/web_push.h"
#include "parc/native/certificate_viewer.h"
#include "parc/native/client_certificates.h"
#include "parc/native/extension_uninstall.h"
#include "parc/native/external_protocol.h"
#include "parc/native/fairplay_media_host.h"
#include "parc/native/file_dialog.h"
#include "parc/native/folder_upload.h"
#include "parc/native/http_auth.h"
#include "parc/native/native_appkit_host.h"
#include "parc/native/native_internal_urls.h"
#include "parc/native/native_page_context_menu.h"
#include "parc/native/native_tab_sharing.h"
#include "parc/native/native_web_contents_view_delegate.h"
#include "parc/native/password_prompt.h"
#include "parc/native/sad_tab.h"
#include "parc/native/site_permissions.h"
#include "parc/native/video_overlay_window.h"
#include "parc/native/video_picture_in_picture_captions.h"
#include "parc/native/webauthn.h"
#include "parc/parc_bundle_mac.h"
#include "parc/parc_branding.h"
#include "parc/renderer/website_theme_agent.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_registry.h"
#include "third_party/blink/public/mojom/parc/picture_in_picture_captions.mojom.h"
#include "third_party/parc_fairplay/chromium/fairplay_cdm_info.h"
#include "third_party/parc_fairplay/chromium/fairplay_media.mojom.h"
#include "third_party/parc_fairplay/chromium/fairplay_media_service.h"

namespace parc {
namespace {
// Only this helper is signed without library validation, because the
// component-updated Widevine CDM carries Google's code signature.
constexpr char kMacHelperSuffixCdm[] = " (CDM)";
// The flag after Chrome's own helper flags.
constexpr int kChildProcessHelperCdm =
    std::to_underlying(ChildProcessHostFlags::kChildProcessHelperAlerts) + 1;
constexpr char kInputDiagnostics[] = "parc-input-diagnostics";
ParcContentBrowserClient* g_browser_client = nullptr;
bool SupportsAutofillUiPresentation(
    const autofill::AutofillClient& client,
    autofill::AutofillUiPresentation presentation) {
  const auto& content_client =
      static_cast<const autofill::ContentAutofillClient&>(client);
  return autofill::AutofillBubbleHandler::IsPresentationSupported(
      content_client.web_contents(), presentation);
}
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
    parc_hooks::SetAutofillUiPresentationSupport(
        &SupportsAutofillUiPresentation);
    parc_hooks::SetPermissionPromptFactory(&CreateSitePermissionPrompt);
    parc_hooks::SetLoginHandlerAuthValidator(&ValidateNativeLoginHandlerAuth);
    parc_hooks::SetExtensionUninstallHandler(&BeginExtensionUninstall);
    parc_hooks::SetFolderUploadConfirmation(&ShowFolderUploadConfirmation);
    parc_hooks::SetSadTabFactory(&CreateSadTab);
    parc_hooks::SetExternalProtocolPrompt(&RunExternalProtocolPrompt);
    parc_hooks::SetCertificateViewer(&ShowServerCertificateViewer);
    parc_hooks::SetClientCertificateSelector(&ShowClientCertificateSelector);
    parc_hooks::SetPasswordPrompt(
        &UsesNativePasswordPrompt, &ShowNativePasswordPrompt,
        &HideNativePasswordPrompt, &HasNativePasswordPrompt,
        &IsNativePasswordPromptHovered);
    parc_hooks::SetTabSharingPageInfo(&ShowTabSharingPageInfo);
    parc_hooks::SetTabSharingInfoBarFactory(&CreateNativeTabSharingInfoBar);
    parc_hooks::SetTabSharingProfile(&TabSharingCapturerProfile);
    parc_hooks::SetPaneFocusRotation(&RotateAppKitPaneFocus);
    parc_hooks::SetFairPlayCdmCreator(&FairPlayDocumentHost::CreateCdm);
    parc_hooks::SetVideoPictureInPictureSessionStarted(
        &StartPictureInPictureCaptionsSession);
    RegisterNativePageContextMenu();
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
    : application_(application) {
  parc_hooks::SetFrameFocusNotifier(&NotifyFrameFocus);
  parc_hooks::SetWebPushFactory(&CreateWebPushClient);
  parc_hooks::SetInternalExtensionInstaller([](extensions::ComponentLoader* loader) {
    loader->Add(kInternalExtensionManifest,
                base::FilePath(FILE_PATH_LITERAL("parc_internal_extension")));
  });
  CHECK(!g_browser_client);
  g_browser_client = this;
}

void ParcContentBrowserClient::OverrideWebPreferences(
    content::WebContents* contents, content::SiteInstance& site,
    blink::web_pref::WebPreferences* prefs) {
  ChromeContentBrowserClient::OverrideWebPreferences(contents, site, prefs);
  ApplyPagePreferences(*contents, *prefs);
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
  if (command_line->GetSwitchValueASCII(switches::kProcessType) !=
      switches::kRendererProcess) {
    return;
  }
  // Renderers can't ask VideoToolbox from their sandbox.
  command_line->AppendSwitchASCII(
      media::kParcAV1HardwareDecoder,
      content::ParcAV1HardwareDecoderAvailable() ? "1" : "0");
  // The input-diagnostics opt-in follows only the renderer receiving the
  // observed input.
  if (base::CommandLine::ForCurrentProcess()->HasSwitch(kInputDiagnostics)) {
    command_line->AppendSwitch(kInputDiagnostics);
  }
}

void ParcContentBrowserClient::RegisterBrowserInterfaceBindersForFrame(
    content::RenderFrameHost* render_frame_host,
    mojo::BinderMapWithContext<content::RenderFrameHost*>* map) {
  ChromeContentBrowserClient::RegisterBrowserInterfaceBindersForFrame(
      render_frame_host, map);
  // VideoToolbox's decoder facts for Safari-identity documents.
  map->Add<media::mojom::ParcVideoToolboxDecoding>(base::BindRepeating(
      [](content::RenderFrameHost*,
         mojo::PendingReceiver<media::mojom::ParcVideoToolboxDecoding>
             receiver) {
        content::BindParcVideoToolboxDecoding(std::move(receiver));
      }));
  // The document's FairPlay Renderers and native HLS players.
  map->Add<media::mojom::FairPlayMediaHost>(
      base::BindRepeating(&FairPlayDocumentHost::BindMediaHost));
}

void ParcContentBrowserClient::
    RegisterAssociatedInterfaceBindersForRenderFrameHost(
        content::RenderFrameHost& render_frame_host,
        blink::AssociatedInterfaceRegistry& associated_registry) {
  ChromeContentBrowserClient::
      RegisterAssociatedInterfaceBindersForRenderFrameHost(render_frame_host,
                                                           associated_registry);
  associated_registry.AddInterface<mojom::PictureInPictureCaptionsHost>(
      base::BindRepeating(&BindPictureInPictureCaptionsHost,
                          &render_frame_host));
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

std::unique_ptr<content::VideoOverlayWindow>
ParcContentBrowserClient::CreateWindowForVideoPictureInPicture(
    content::VideoPictureInPictureWindowController* controller) {
  if (UsesNativeVideoPictureInPicture(controller->GetWebContents())) {
    return CreateNativeVideoOverlayWindow(controller);
  }
  return ChromeContentBrowserClient::CreateWindowForVideoPictureInPicture(
      controller);
}

std::unique_ptr<content::AuthenticatorRequestClientDelegate>
ParcContentBrowserClient::GetWebAuthenticationRequestDelegate(
    content::RenderFrameHost* render_frame_host) {
  return CreateWebAuthenticationRequestDelegate(render_frame_host);
}

void ParcContentGpuClient::ExposeInterfacesToBrowser(
    viz::GpuServiceImpl* gpu_service,
    const gpu::GpuPreferences& gpu_preferences,
    const gpu::GpuDriverBugWorkarounds& gpu_workarounds,
    mojo::BinderMap* binders) {
  ChromeContentGpuClient::ExposeInterfacesToBrowser(
      gpu_service, gpu_preferences, gpu_workarounds, binders);
  // FairPlay's CDMs, renderers and native HLS players, on the kind of thread
  // the GPU media service runs on.
  binders->Add<media::mojom::FairPlayMediaService>(
      base::BindRepeating(&media::BindFairPlayMediaService),
      media::CreateFairPlayMediaServiceTaskRunner());
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

bool ParcContentRendererClient::IsDecoderSupportedAudioType(
    const media::AudioType& type) {
  // AudioToolbox decodes Apple Lossless; Chromium's default list has no
  // decoder for it.
  if (type.codec == media::AudioCodec::kALAC) {
    return !type.spatial_rendering;
  }
  return ChromeContentRendererClient::IsDecoderSupportedAudioType(type);
}
}  // namespace parc
