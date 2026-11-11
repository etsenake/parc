// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_BROWSER_WEB_CONTENTS_DELEGATE_H_
#define PARC_NATIVE_NATIVE_BROWSER_WEB_CONTENTS_DELEGATE_H_

#include "base/memory/raw_ref.h"
#include "chrome/browser/ui/browser_web_contents_delegate/browser_web_contents_delegate.h"

namespace parc {

// Chrome's WebContentsDelegate for a native Browser, with Parc's link, Peek,
// split, key, hang and dialog routes. Owned by BrowserWindowFeatures.
class NativeBrowserWebContentsDelegate final
    : public BrowserWebContentsDelegate {
 public:
  NativeBrowserWebContentsDelegate(
      BrowserWindowInterface* browser,
      ExclusiveAccessManager& exclusive_access_manager,
      chrome::BrowserCommandController& command_controller,
      UnloadController& unload_controller,
      web_app::AppBrowserController* app_browser_controller,
      BrowserWindow& window,
      DesktopBrowserWindowCapabilities& capabilities,
      BrowserUiController& browser_ui_controller);
  NativeBrowserWebContentsDelegate(const NativeBrowserWebContentsDelegate&) =
      delete;
  NativeBrowserWebContentsDelegate& operator=(
      const NativeBrowserWebContentsDelegate&) = delete;
  ~NativeBrowserWebContentsDelegate() override;

  // content::WebContentsDelegate:
  bool HandleKeyboardEvent(content::WebContents* source,
                           const input::NativeWebKeyboardEvent& event) override;
  content::PreloadingEligibility IsPrerender2Supported(
      content::WebContents& web_contents,
      content::PreloadingTriggerType trigger_type) override;
  std::optional<base::UnguessableToken> PrepareNativeMainFrameLink(
      content::RenderFrameHost* source,
      const GURL& url,
      WindowOpenDisposition disposition,
      std::optional<uint32_t> input_modifiers) override;
  content::WebContents* OpenURLFromTab(
      content::WebContents* source,
      const content::OpenURLParams& params,
      base::OnceCallback<void(content::NavigationHandle&)>
          navigation_handle_callback) override;
  content::WebContents* AddNewContents(
      content::WebContents* source,
      std::unique_ptr<content::WebContents> new_contents,
      const GURL& target_url,
      WindowOpenDisposition disposition,
      const blink::mojom::WindowFeatures& window_features,
      bool user_gesture,
      bool* was_blocked) override;
  void UpdateTargetURL(content::WebContents* source, const GURL& url) override;
  void WebContentsCreated(content::WebContents* source_contents,
                          const content::GlobalRenderFrameHostId& opener_id,
                          const std::string& frame_name,
                          const GURL& target_url,
                          content::WebContents* new_contents) override;
  void RendererUnresponsive(
      content::WebContents* source,
      content::RenderWidgetHost* render_widget_host,
      base::RepeatingClosure hang_monitor_restarter) override;
  void RendererResponsive(
      content::WebContents* source,
      content::RenderWidgetHost* render_widget_host) override;
  content::JavaScriptDialogManager* GetJavaScriptDialogManager(
      content::WebContents* source) override;
  void ExitFullscreenModeForTab(content::WebContents* web_contents) override;

 private:
  const raw_ref<BrowserWindowInterface> browser_;
};

}  // namespace parc
#endif  // PARC_NATIVE_NATIVE_BROWSER_WEB_CONTENTS_DELEGATE_H_
