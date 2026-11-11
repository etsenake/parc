// Copyright 2026 Parc contributors.
// Chrome's content clients with the few Parc behaviours CEF used to carry:
// the parc: scheme, CDM and Alerts helper routing, startup registrations and
// the website-theme agent, plus Parc's FairPlay media service.
#ifndef PARC_PARC_CONTENT_CLIENTS_H_
#define PARC_PARC_CONTENT_CLIENTS_H_

#include <memory>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "base/memory/raw_ref.h"
#include "chrome/browser/chrome_browser_main_extra_parts.h"
#include "chrome/browser/chrome_content_browser_client.h"
#include "chrome/common/chrome_content_client.h"
#include "chrome/gpu/chrome_content_gpu_client.h"
#include "chrome/renderer/chrome_content_renderer_client.h"

class Profile;

namespace parc {
class NativeApplication;

class ParcContentClient final : public ChromeContentClient {
 public:
  void AddAdditionalSchemes(Schemes* schemes) override;
  void AddContentDecryptionModules(
      std::vector<content::CdmInfo>* cdms,
      std::vector<media::CdmHostFilePath>* cdm_host_file_paths) override;
};

class ParcContentBrowserClient final : public ChromeContentBrowserClient {
 public:
  explicit ParcContentBrowserClient(NativeApplication& application);
  ~ParcContentBrowserClient() override;

  // The browser process's client, which outlives every page and window.
  static ParcContentBrowserClient& Get();

  // The profile Chrome's startup loaded; set once browser startup reaches
  // PostProfileInit.
  Profile* initial_profile() const { return initial_profile_; }

  std::unique_ptr<content::BrowserMainParts> CreateBrowserMainParts(
      bool is_integration_test) override;
  std::unique_ptr<HttpAuthCoordinator> CreateHttpAuthCoordinator() override;
  base::FilePath GetChildProcessPath(int flags) override;
  void AppendExtraCommandLineSwitches(base::CommandLine* command_line,
                                      int child_process_id) override;
  void RegisterBrowserInterfaceBindersForFrame(
      content::RenderFrameHost* render_frame_host,
      mojo::BinderMapWithContext<content::RenderFrameHost*>* map) override;
  void OverrideWebPreferences(content::WebContents* web_contents,
                              content::SiteInstance& main_frame_site,
                              blink::web_pref::WebPreferences* prefs) override;
  bool IsHandledURL(const GURL& url) override;
  void BrowserURLHandlerCreated(content::BrowserURLHandler* handler) override;
  std::unique_ptr<content::WebContentsViewDelegate> GetWebContentsViewDelegate(
      content::WebContents* web_contents) override;
  std::unique_ptr<content::VideoOverlayWindow>
  CreateWindowForVideoPictureInPicture(
      content::VideoPictureInPictureWindowController* controller) override;
  std::unique_ptr<content::AuthenticatorRequestClientDelegate>
  GetWebAuthenticationRequestDelegate(
      content::RenderFrameHost* render_frame_host) override;

 private:
  friend class ParcBrowserMainExtraParts;

  const raw_ref<NativeApplication> application_;
  raw_ptr<Profile> initial_profile_ = nullptr;
};

class ParcContentGpuClient final : public ChromeContentGpuClient {
 public:
  void ExposeInterfacesToBrowser(
      viz::GpuServiceImpl* gpu_service,
      const gpu::GpuPreferences& gpu_preferences,
      const gpu::GpuDriverBugWorkarounds& gpu_workarounds,
      mojo::BinderMap* binders) override;
};

class ParcContentRendererClient final : public ChromeContentRendererClient {
 public:
  void RenderFrameCreated(content::RenderFrame* render_frame) override;
  std::unique_ptr<media::KeySystemSupportRegistration> GetSupportedKeySystems(
      content::RenderFrame* render_frame,
      media::GetSupportedKeySystemsCB cb) override;
  bool IsDecoderSupportedAudioType(const media::AudioType& type) override;
};
}  // namespace parc

#endif  // PARC_PARC_CONTENT_CLIENTS_H_
