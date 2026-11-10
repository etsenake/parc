// Copyright 2026 Parc contributors.
// OpenURLFromTab's early returns and the fullscreen-exit resize follow
// Chromium Embedded Framework's chrome_browser_web_contents_delegate.cc,
// Copyright 2026 The Chromium Embedded Framework Authors. All rights reserved.
// BSD-style license: see LICENSE.
#include "native_browser_web_contents_delegate.h"

#include <utility>

#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "components/input/native_web_keyboard_event.h"
#include "components/tabs/public/split_tab_data.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/render_widget_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/web_contents.h"
#include "javascript_dialog_manager.h"
#include "native_link_routing.h"
#include "native_page_binding.h"
#include "native_page_observers.h"

namespace parc {

NativeBrowserWebContentsDelegate::NativeBrowserWebContentsDelegate(
    BrowserWindowInterface* browser,
    ExclusiveAccessManager& exclusive_access_manager,
    chrome::BrowserCommandController& command_controller,
    UnloadController& unload_controller,
    web_app::AppBrowserController* app_browser_controller,
    BrowserWindow& window,
    DesktopBrowserWindowCapabilities& capabilities,
    BrowserUiController& browser_ui_controller)
    : BrowserWebContentsDelegate(browser,
                                 exclusive_access_manager,
                                 command_controller,
                                 unload_controller,
                                 app_browser_controller,
                                 window,
                                 capabilities,
                                 browser_ui_controller),
      browser_(*browser) {}

NativeBrowserWebContentsDelegate::~NativeBrowserWebContentsDelegate() = default;

bool NativeBrowserWebContentsDelegate::HandleKeyboardEvent(
    content::WebContents* source,
    const input::NativeWebKeyboardEvent& event) {
  if (event.skip_if_unhandled) {
    return false;
  }
  if (source && NativePageBinding::FromWebContents(source) &&
      HandleNativePageUnhandledKey(*source, event)) {
    return true;
  }
  return BrowserWebContentsDelegate::HandleKeyboardEvent(source, event);
}

content::PreloadingEligibility
NativeBrowserWebContentsDelegate::IsPrerender2Supported(
    content::WebContents& web_contents,
    content::PreloadingTriggerType trigger_type) {
  // CEF never allowed prerendering (CEF issue #3664), so Parc pages never
  // have. Keep it off until it is enabled deliberately.
  return content::PreloadingEligibility::kPreloadingDisabled;
}

std::optional<base::UnguessableToken>
NativeBrowserWebContentsDelegate::PrepareNativeMainFrameLink(
    content::RenderFrameHost* source,
    const GURL& url,
    WindowOpenDisposition disposition,
    std::optional<uint32_t> input_modifiers) {
  return PrepareNativeCurrentLink(browser_.get(), source, url, disposition,
                                  input_modifiers);
}

content::WebContents* NativeBrowserWebContentsDelegate::OpenURLFromTab(
    content::WebContents* source,
    const content::OpenURLParams& params,
    base::OnceCallback<void(content::NavigationHandle&)>
        navigation_handle_callback) {
  // Chrome itself navigates DevTools frontends.
  if (browser_->GetType() == BrowserWindowInterface::Type::TYPE_DEVTOOLS) {
    return BrowserWebContentsDelegate::OpenURLFromTab(
        source, params, std::move(navigation_handle_callback));
  }
  const auto early_browser_weak = browser_->GetWeakPtr();
  const auto early_source_weak =
      source ? source->GetWeakPtr() : base::WeakPtr<content::WebContents>();
  const bool native_split_owner =
      params.disposition == WindowOpenDisposition::NEW_SPLIT_VIEW && source &&
      HasNativeSplitOwner(browser_.get(), *source);
  if (!early_browser_weak || (source && !early_source_weak)) {
    return nullptr;
  }
  auto native_split =
      native_split_owner
          ? PrepareNativeSplitNavigation(browser_.get(), source, params)
          : nullptr;
  if (!early_browser_weak || (source && !early_source_weak)) {
    return nullptr;
  }
  // A source already in a Chromium split opens into it, unless Parc owns it.
  if (!native_split_owner &&
      params.disposition == WindowOpenDisposition::NEW_SPLIT_VIEW && source) {
    tabs::TabInterface* const source_tab =
        tabs::TabInterface::MaybeGetFromContents(source);
    if (source_tab && source_tab->IsSplit()) {
      const split_tabs::SplitTabId split_id = source_tab->GetSplit().value();
      for (tabs::TabInterface* tab :
           browser_->GetTabStripModel()->GetSplitData(split_id)->ListTabs()) {
        if (tab != source_tab) {
          return BrowserWebContentsDelegate::OpenURLFromTab(
              source, params, std::move(navigation_handle_callback));
        }
      }
    }
  }
  const auto browser_weak = browser_->GetWeakPtr();
  const bool had_source = source != nullptr;
  const base::WeakPtr<content::WebContents> source_weak =
      source ? source->GetWeakPtr() : base::WeakPtr<content::WebContents>();
  if (HandleNativeMatchedLink(browser_.get(), source, params,
                              navigation_handle_callback)) {
    return nullptr;
  }
  if (!browser_weak || (had_source && !source_weak)) {
    return nullptr;
  }
  const auto split_decision = ClassifyNativeSplit(
      native_split_owner, native_split && native_split->SplitStillValid());
  if (!browser_weak || (had_source && !source_weak)) {
    return nullptr;
  }
  if (native_split_owner && !HasNativeSplitOwner(browser_.get(), *source)) {
    return nullptr;
  }
  if (split_decision == NativeSplitDecision::kAdmitted) {
    auto* created = BrowserWebContentsDelegate::OpenURLFromTab(
        source, native_split->params(), std::move(navigation_handle_callback));
    native_split->DidNavigate(created);
    return created;
  }
  if (split_decision == NativeSplitDecision::kOrdinary) {
    // Never turn a stale one-use ATC admission into an unrelated request.
    if (params.native_route_token) {
      return nullptr;
    }
    // Keep the original disposition through Chromium popup checks, but avoid
    // its native two-pane path when Parc could not admit this presentation.
    content::OpenURLParams ordinary(params);
    ordinary.native_route_split = true;
    return BrowserWebContentsDelegate::OpenURLFromTab(
        source, ordinary, std::move(navigation_handle_callback));
  }
  auto peek = PrepareNativePeekNavigation(browser_.get(), source, params);
  if (!browser_weak || (had_source && !source_weak)) {
    return nullptr;
  }
  // A stale/consumed admission token cannot become an unrelated new tab.
  if (params.native_route_token && !peek) {
    return nullptr;
  }
  if (peek) {
    auto* created = BrowserWebContentsDelegate::OpenURLFromTab(
        source, peek->params(), std::move(navigation_handle_callback));
    peek->DidNavigate(created);
    return created;
  }
  return BrowserWebContentsDelegate::OpenURLFromTab(
      source, params, std::move(navigation_handle_callback));
}

content::WebContents* NativeBrowserWebContentsDelegate::AddNewContents(
    content::WebContents* source,
    std::unique_ptr<content::WebContents> new_contents,
    const GURL& target_url,
    WindowOpenDisposition disposition,
    const blink::mojom::WindowFeatures& window_features,
    bool user_gesture,
    bool* was_blocked) {
  if (new_contents) {
    const auto browser_weak = browser_->GetWeakPtr();
    const auto source_weak =
        source ? source->GetWeakPtr() : base::WeakPtr<content::WebContents>();
    const auto child_weak = new_contents->GetWeakPtr();
    const bool native_owner =
        source && HasNativeSplitOwner(browser_.get(), *source);
    PrepareNativeCreatedPage(browser_.get(), source, *new_contents, target_url,
                             disposition, user_gesture);
    if (!child_weak) {
      // A nested callback destroyed the exact child; do not delete it twice.
      new_contents.release();
      return nullptr;
    }
    if (!browser_weak || (source && !source_weak) ||
        (native_owner &&
         !HasNativeSplitOwner(*browser_weak, *source_weak))) {
      return nullptr;
    }
  }
  return BrowserWebContentsDelegate::AddNewContents(
      source, std::move(new_contents), target_url, disposition,
      window_features, user_gesture, was_blocked);
}

void NativeBrowserWebContentsDelegate::UpdateTargetURL(
    content::WebContents* source,
    const GURL& url) {
  if (source && NativePageBinding::FromWebContents(source)) {
    NativePageTargetURLChanged(*source, url);
  }
  BrowserWebContentsDelegate::UpdateTargetURL(source, url);
}

void NativeBrowserWebContentsDelegate::WebContentsCreated(
    content::WebContents* source_contents,
    const content::GlobalRenderFrameHostId& opener_id,
    const std::string& frame_name,
    const GURL& target_url,
    content::WebContents* new_contents) {
  CaptureNativeCreatedPage(source_contents, opener_id, new_contents);
  // SessionTabHelper must exist before the popup's native binding.
  BrowserWebContentsDelegate::WebContentsCreated(
      source_contents, opener_id, frame_name, target_url, new_contents);
  // Bind before the popup's first navigation; its Browser comes later, from
  // AddNewContents.
  if (source_contents && NativePageBinding::FromWebContents(source_contents)) {
    NativePageBinding::CreateForWebContents(new_contents);
  }
}

void NativeBrowserWebContentsDelegate::RendererUnresponsive(
    content::WebContents* source,
    content::RenderWidgetHost* render_widget_host,
    base::RepeatingClosure hang_monitor_restarter) {
  NativePageRendererUnresponsive(*source, *render_widget_host,
                                 std::move(hang_monitor_restarter));
}

void NativeBrowserWebContentsDelegate::RendererResponsive(
    content::WebContents* source,
    content::RenderWidgetHost* render_widget_host) {
  NativePageRendererResponsive(*source);
}

content::JavaScriptDialogManager*
NativeBrowserWebContentsDelegate::GetJavaScriptDialogManager(
    content::WebContents* source) {
  // Null means not installed, and content then cancels the dialog. Chrome's
  // tab-modal manager has no native window to present in.
  return NativeJavaScriptDialogManager(*source);
}

void NativeBrowserWebContentsDelegate::ExitFullscreenModeForTab(
    content::WebContents* web_contents) {
  BrowserWebContentsDelegate::ExitFullscreenModeForTab(web_contents);
  // Workaround for https://crbug.com/1500371: make the page leave its
  // fullscreen size with an explicit resize.
  if (auto* view = web_contents->GetRenderWidgetHostView()) {
    if (auto* widget = view->GetRenderWidgetHost()) {
      widget->SynchronizeVisualProperties();
    }
  }
}

}  // namespace parc
