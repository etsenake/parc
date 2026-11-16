// Copyright 2026 Parc contributors.

// Copyright 2026 The Chromium Embedded Framework Authors. All rights reserved.
#include "native_browser_web_contents_delegate.h"

#include <utility>

#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/unload_controller.h"
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
#include "native_popup_blocking.h"
#include "video_overlay_window.h"
#include "content/public/browser/video_picture_in_picture_window_controller.h"
#include "unload_transactions.h"

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

content::PictureInPictureResult
NativeBrowserWebContentsDelegate::EnterPictureInPicture(
    content::WebContents* web_contents) {
  if (UsesNativeVideoPictureInPicture(web_contents) &&
      (!CanCreateNativeVideoPiPWindow() ||
       content::PictureInPictureWindowController::
           GetOrCreateVideoPictureInPictureController(web_contents)
               ->IsImmersive())) {
    return content::PictureInPictureResult::kNotSupported;
  }
  return BrowserWebContentsDelegate::EnterPictureInPicture(web_contents);
}

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

  return content::PreloadingEligibility::kPreloadingDisabled;
}

std::optional<base::UnguessableToken>
NativeBrowserWebContentsDelegate::PrepareNativeMainFrameLink(
    content::RenderFrameHost* source,
    const GURL& url,
    WindowOpenDisposition disposition,
    std::optional<uint32_t> input_modifiers) {
  if (disposition == WindowOpenDisposition::SAVE_TO_DISK) {
    return PrepareNativeOptionLink(browser_.get(), source, url);
  }
  return PrepareNativeCurrentLink(browser_.get(), source, url, disposition,
                                  input_modifiers);
}

content::WebContents* NativeBrowserWebContentsDelegate::OpenURLFromTab(
    content::WebContents* source,
    const content::OpenURLParams& params,
    base::OnceCallback<void(content::NavigationHandle&)>
        navigation_handle_callback) {

  if (browser_->GetType() == BrowserWindowInterface::Type::TYPE_DEVTOOLS) {
    return BrowserWebContentsDelegate::OpenURLFromTab(
        source, params, std::move(navigation_handle_callback));
  }
  if (BlockNativeLinkPopup(source, params)) {
    return nullptr;
  }
  const auto early_browser_weak = browser_->GetWeakPtr();
  const auto early_source_weak =
      source ? source->GetWeakPtr() : base::WeakPtr<content::WebContents>();
  if (params.disposition == WindowOpenDisposition::SAVE_TO_DISK &&
      params.native_route_token) {
    auto split = TakeNativeOptionLink(source, params);
    if (!split) {
      return nullptr;
    }
    return OpenURLFromTab(source, *split, std::move(navigation_handle_callback));
  }
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

    if (params.native_route_token) {
      return nullptr;
    }

    content::OpenURLParams ordinary(params);
    ordinary.native_route_split = true;
    return BrowserWebContentsDelegate::OpenURLFromTab(
        source, ordinary, std::move(navigation_handle_callback));
  }
  auto peek = PrepareNativePeekNavigation(browser_.get(), source, params);
  if (!browser_weak || (had_source && !source_weak)) {
    return nullptr;
  }

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

void NativeBrowserWebContentsDelegate::CloseContents(
    content::WebContents* source) {
  auto* controller = UnloadController::From(&browser_.get());
  if (controller && parc::HoldsContents(*controller, source)) {
    return;
  }
  BrowserWebContentsDelegate::CloseContents(source);
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

  BrowserWebContentsDelegate::WebContentsCreated(
      source_contents, opener_id, frame_name, target_url, new_contents);

  if (source_contents && NativePageBinding::FromWebContents(source_contents)) {
    NativePageBinding::CreateForWebContents(new_contents);
  }
}

void NativeBrowserWebContentsDelegate::OnDidBlockNavigation(
    content::WebContents* web_contents,
    const GURL& blocked_url,
    const GURL& initiator_url,
    const url::Origin& initiator_origin,
    scoped_refptr<content::InitiatorNavigationState> initiator_navigation_state,
    blink::mojom::NavigationBlockedReason reason) {
  const auto contents =
      web_contents ? web_contents->GetWeakPtr() : base::WeakPtr<content::WebContents>();
  BrowserWebContentsDelegate::OnDidBlockNavigation(
      web_contents, blocked_url, initiator_url, initiator_origin,
      std::move(initiator_navigation_state), reason);
  if (contents && reason == blink::mojom::NavigationBlockedReason::
                                kRedirectWithNoUserGesture) {
    NativeNavigationBlocked(*contents);
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

  return NativeJavaScriptDialogManager(*source);
}

void NativeBrowserWebContentsDelegate::ExitFullscreenModeForTab(
    content::WebContents* web_contents) {
  BrowserWebContentsDelegate::ExitFullscreenModeForTab(web_contents);

  if (auto* view = web_contents->GetRenderWidgetHostView()) {
    if (auto* widget = view->GetRenderWidgetHost()) {
      widget->SynchronizeVisualProperties();
    }
  }
}

}
