// Copyright 2026 Parc contributors.
//
// while Core retains DevToolsWindow/contents (0x683eedc). Current156's real
//
#include "devtools_pane.h"

#include <dispatch/dispatch.h>
#include <utility>

#include "base/auto_reset.h"
#include "base/functional/bind.h"
#include "base/supports_user_data.h"
#include "chrome/browser/devtools/devtools_ui_controller.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/browser/ui/web_modal/browser_window_modal_dialog_delegate.h"  // nogncheck
#include "client_certificates.h"
#include "components/web_modal/web_contents_modal_dialog_manager.h"
#include "content/public/browser/web_contents.h"
#include "http_auth.h"
#include "native_auxiliary_page.h"
#include "native_auxiliary_services.h"
#import "page_host.h"
#include "pane_compositor.h"
#include "ui/gfx/geometry/rect_conversions.h"
namespace parc {
namespace {
// Each binding takes the next generation, so a binding released late never
// clears a newer one. The tools' own contents carry it.
const int kModalHostKey = 0;
struct GenerationData : base::SupportsUserData::Data {
  uint64_t value = 0;
};
uint64_t& ModalHostGeneration(content::WebContents& tools) {
  auto* data = static_cast<GenerationData*>(tools.GetUserData(&kModalHostKey));
  if (!data) {
    auto created = std::make_unique<GenerationData>();
    data = created.get();
    tools.SetUserData(&kModalHostKey, std::move(created));
  }
  return data->value;
}
bool IsDockedMain(content::WebContents* tools) {
  auto* window = DevToolsWindow::AsDevToolsWindow(tools);
  return window && window->IsDocked();
}
void ReleaseModalHost(base::WeakPtr<content::WebContents> tools,
                      base::WeakPtr<BrowserWindowInterface> owner,
                      uint64_t generation) {
  if (!tools || !owner || !IsDockedMain(tools.get()) ||
      ModalHostGeneration(*tools) != generation) {
    return;
  }
  ++ModalHostGeneration(*tools);
  auto* manager =
      web_modal::WebContentsModalDialogManager::FromWebContents(tools.get());
  if (manager && manager->delegate() ==
                     BrowserWindowModalDialogDelegate::From(owner.get())) {
    manager->SetDelegate(nullptr);  // Last call: may notify native hosts.
  }
}
}  // namespace
base::ScopedClosureRunner BindDockedModalHost(content::WebContents* inspected,
                                              content::WebContents* tools) {
  auto* window = DevToolsWindow::GetInstanceForInspectedWebContents(inspected);
  if (!window || !window->IsDocked() ||
      window->GetDevToolsWebContents() != tools) {
    return {};
  }
  auto* browser =
      GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(inspected);
  if (!browser) {
    return {};
  }
  auto owner = browser->GetWeakPtr();
  auto page = inspected->GetWeakPtr();
  auto contents = tools->GetWeakPtr();
  const uint64_t generation = ++ModalHostGeneration(*tools);
  web_modal::WebContentsModalDialogManager::CreateForWebContents(tools);
  web_modal::WebContentsModalDialogManager::FromWebContents(tools)->SetDelegate(
      BrowserWindowModalDialogDelegate::From(browser));
  base::ScopedClosureRunner binding(
      base::BindOnce(&ReleaseModalHost, contents, owner, generation));
  // SetDelegate can notify native hosts and reenter; drop the lease if the
  // page, the tools or the Browser changed meanwhile.
  if (!owner || !page || !contents ||
      ModalHostGeneration(*contents) != generation ||
      !IsDockedMain(contents.get()) ||
      GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(page.get()) !=
          owner.get()) {
    return {};
  }
  // SetDelegate skips an identical owner. Replay the real blocked state after
  // the new pane is registered, including deferred first attachment and a new
  // pane in the same Browser. No synthetic input or dialog manager is created.
  auto* manager =
      web_modal::WebContentsModalDialogManager::FromWebContents(contents.get());
  if (auto* current = DevtoolsUIController::From(owner.get())) {
    current->SetDevtoolsScrimVisibility(contents.get(),
                                        manager->IsDialogActive());
  }
  return binding;
}
class NativeDevToolsPane::ToolsObserver : public content::WebContentsObserver {
 public:
  ToolsObserver(content::WebContents* tools,
                base::WeakPtr<NativeDevToolsPane> owner)
      : WebContentsObserver(tools), owner_(owner) {}
  void WebContentsDestroyed() override {
    if (owner_) {
      owner_->ToolsDestroyed();
    }
  }

 private:
  base::WeakPtr<NativeDevToolsPane> owner_;
};
std::shared_ptr<NativeDevToolsPane> NativeDevToolsPane::Create(
    content::WebContents& inspected,
    NSView* view) {
  auto pane = std::shared_ptr<NativeDevToolsPane>(
      new NativeDevToolsPane(inspected, view));
  auto weak = pane->weak_factory_.GetWeakPtr();
  pane->view_.layoutHandler = ^(NSRect) {
    if (weak) {
      weak->Layout();
    }
  };
  return pane;
}
NativeDevToolsPane::NativeDevToolsPane(content::WebContents& inspected,
                                       NSView* view)
    : WebContentsObserver(&inspected),
      view_([[PCNativeDevToolsPaneView alloc] initWithInspectedView:view]) {}
NativeDevToolsPane::~NativeDevToolsPane() {
  Detach();
}
void NativeDevToolsPane::WebContentsDestroyed() {
  Detach();
}
void NativeDevToolsPane::ToolsDestroyed() {
  auto keep = shared_from_this();
  const uint64_t generation = ++presentation_generation_;
  auto previous = tools_;
  // Do not delete the observer while its destruction notification is running.
  NSView* old = view_.toolsView;
  NSWindow* window = view_.window;
  NSResponder* responder = window.firstResponder;
  const bool restore = old && [responder isKindOfClass:NSView.class] &&
                       [(NSView*)responder isDescendantOf:old];
  if (auxiliary_) {
    auxiliary_->Revoke();
  }
  if (detached_ || presentation_generation_ != generation ||
      tools_.get() != previous.get() || view_.toolsView != old) {
    return;
  }
  auxiliary_.reset();
  tools_.reset();
  show_tools_ = false;
  [view_ setHostedToolsView:nil];
  if (detached_ || presentation_generation_ != generation || view_.toolsView) {
    return;
  }
  if (!detached_ && restore && window && view_.inspectedView.window == window) {
    [window makeFirstResponder:view_.inspectedView];
  }
  if (detached_ || presentation_generation_ != generation) {
    return;
  }
  [view_ setToolsBlocked:NO];
  if (!detached_ && presentation_generation_ == generation) {
    Layout();
  }
}
bool NativeDevToolsPane::Refresh(bool update_contents) {
  auto keep = shared_from_this();
  if (detached_ || refreshing_ || !web_contents() || !OwnsViews()) {
    return false;
  }
  base::AutoReset<bool> refreshing(&refreshing_, true);
  DevToolsContentsResizingStrategy next;
  auto* tools = DevToolsWindow::GetInTabWebContents(web_contents(), &next);
  auto next_tools = tools ? tools->GetWeakPtr() : nullptr;
  const bool was_shown = show_tools_ && view_.toolsView != nil;
  bool changed = !strategy_.Equals(next) || show_tools_ != (tools != nullptr);
  show_tools_ = tools != nullptr;
  strategy_.CopyFrom(next);
  if (update_contents && tools_.get() != tools) {
    changed = true;
    auto old_tools = tools_;
    NSView* old_view = view_.toolsView;
    NSWindow* window = view_.window;
    NSResponder* responder = window.firstResponder;
    const bool restore = old_view && [responder isKindOfClass:NSView.class] &&
                         [(NSView*)responder isDescendantOf:old_view];
    if (auxiliary_) {
      auxiliary_->Revoke();
    }
    auxiliary_.reset();
    // Revocation cancels real dialogs and may run arbitrary shell callbacks.
    // Do not dereference the originally selected tools after it was destroyed
    // or after a newer real docking transition changed the selection.
    DevToolsContentsResizingStrategy current_strategy;
    if (detached_ || !web_contents() || (tools && !next_tools) ||
        DevToolsWindow::GetInTabWebContents(web_contents(),
                                            &current_strategy) != tools) {
      return changed;
    }
    ++presentation_generation_;
    tools_observer_.reset();
    tools_ = tools ? tools->GetWeakPtr() : nullptr;
    tools_shown_ = false;
    if (tools) {
      tools_observer_ =
          std::make_unique<ToolsObserver>(tools, weak_factory_.GetWeakPtr());
    }
    NSView* hosted = tools ? tools->GetNativeView().GetNativeNSView() : nil;
    // A first docked frontend has no CEF page wrapper. Host its actual view;
    // creating a wrapper with no observer would make the later undocked CEF
    // page reuse that observerless host. After a real CEF host exists, retain
    // that exact wrapper and its original platform observer across redocking.
    if ([hosted.superview isMemberOfClass:PCNativePageHost.class] &&
        ((PCNativePageHost*)hosted.superview).contentView == hosted) {
      hosted = hosted.superview;
    }
    if (detached_ || ![view_ setHostedToolsView:hosted]) {
      return changed;
    }
    // Replacement can leave the real toolbox alive. Hide it only if this
    // binding actually detached it and no new native owner has adopted it.
    if (old_tools && old_view && !old_view.superview) {
      HidePaneCompositor(*old_tools);
    }
    if (old_tools && old_view && !old_view.superview &&
        old_tools->GetVisibility() != content::Visibility::HIDDEN) {
      old_tools->WasHidden();
    }
    if (detached_) {
      return changed;
    }
    if (restore && !tools && window && view_.inspectedView.window == window) {
      [window makeFirstResponder:view_.inspectedView];
    }
  }
  if (!detached_ && tools_ && show_tools_) {
    auto binding = BindDockedModalHost(web_contents(), tools_.get());
    if (detached_) {
      return changed;
    }
    // Acquire the newer lease before releasing the old one; its generation
    // prevents an older detach from clearing a reentrant/newer native owner.
    modal_binding_ = std::move(binding);
    if (detached_ || !OwnsViews()) {
      return changed;
    }
    if (!auxiliary_ || !auxiliary_->IsValid()) {
      if (auxiliary_) {
        auxiliary_->Revoke();
      }
      auxiliary_.reset();
      if (detached_ || !tools_ || !OwnsViews()) {
        return changed;
      }
      auto lease = NativeAuxiliaryPage::BindDevTools(*web_contents(), *tools_,
                                                     view_.toolsView, view_);
      if (detached_ || !tools_ || !OwnsViews()) {
        if (lease) {
          lease->Revoke();
        }
        return changed;
      }
      auxiliary_ = std::move(lease);
      if (auxiliary_) {
        PrepareNativeAuxiliaryServices(*tools_);
        SetNativeHTTPAuthAttached(*tools_, true);
        SetNativeClientCertificatesAttached(*tools_, true);
      }
    }
  } else {
    if (auxiliary_) {
      auxiliary_->Revoke();
    }
    auxiliary_.reset();
    modal_binding_.RunAndReset();
  }
  if (!detached_) {
    Layout();
  }
  // Chromium Show focuses tools twice around inspected_window->Show
  // (`SetInitialFocus` at 0-offset Show). First-docked tools have no CEF
  // SetFocus, so the native pane focuses the hosted tools view when they
  // appear, then again after the current runloop so window Show cannot
  // leave the inspected page as first responder.
  if (!detached_ && !was_shown && show_tools_ && OwnsViews()) {
    RequestToolsFocus();
  }
  return changed;
}
bool NativeDevToolsPane::OwnsViews() const {
  return view_.inspectedView.superview == view_ &&
         (!view_.toolsView || view_.toolsView.superview == view_);
}
void NativeDevToolsPane::Layout() {
  auto keep = shared_from_this();
  if (detached_ || !OwnsViews()) {
    return;
  }
  const NSRect bounds = view_.bounds;
  gfx::Rect tools_bounds, inspected_bounds;
  if (tools_ && show_tools_) {
    ApplyDevToolsContentsResizingStrategy(
        strategy_,
        gfx::Rect(bounds.origin.x, bounds.origin.y, bounds.size.width,
                  bounds.size.height),
        &tools_bounds, &inspected_bounds);
  } else {
    inspected_bounds = gfx::Rect(bounds.origin.x, bounds.origin.y,
                                 bounds.size.width, bounds.size.height);
  }
  NSView* const tools = view_.toolsView;
  const BOOL hide_tools = !show_tools_;
  const BOOL hide_inspected =
      tools && show_tools_ && strategy_.hide_inspected_contents();
  const NSRect inspected_rect =
      NSMakeRect(inspected_bounds.x(), inspected_bounds.y(),
                 inspected_bounds.width(), inspected_bounds.height());
  const NSRect tools_rect = NSMakeRect(
      tools_bounds.x(), tools_bounds.y(), tools_bounds.width(),
      tools_bounds.height());
  // Open Elements re-enters layout with unchanged docking geometry. Identical
  // inspected/tools frames and hidden flags are a true no-op of applyInspectedRect;
  // visibility can still change without a geometry move, so UpdateVisibility runs.
  const bool geometry_current =
      NSEqualRects(view_.inspectedView.frame, inspected_rect) &&
      NSEqualRects(view_.inspectedOverlay.frame, inspected_rect) &&
      view_.inspectedView.hidden == hide_inspected &&
      view_.inspectedOverlay.hidden == hide_inspected &&
      (!tools || (NSEqualRects(tools.frame, tools_rect) &&
                  tools.hidden == hide_tools));
  if (!geometry_current) {
    if (tools && tools.hidden != hide_tools) {
      tools.hidden = hide_tools;
    }
    if (detached_ || !OwnsViews()) {
      return;
    }
    [view_ applyInspectedRect:inspected_rect
                    toolsRect:tools_rect
                hideInspected:hide_inspected];
  }
  if (!detached_) {
    UpdateVisibility();
  }
}
void NativeDevToolsPane::RequestToolsFocus() {
  auto keep = shared_from_this();
  if (detached_ || !show_tools_ || !OwnsViews()) {
    return;
  }
  [view_ focusTools];
  const uint64_t generation = presentation_generation_;
  auto weak = weak_factory_.GetWeakPtr();
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!weak || weak->detached_ ||
        weak->presentation_generation_ != generation || !weak->show_tools_ ||
        !weak->OwnsViews()) {
      return;
    }
    [weak->view_ focusTools];
  });
}
void NativeDevToolsPane::UpdateVisibility() {
  auto keep = shared_from_this();
  if (detached_ || !tools_ || !OwnsViews()) {
    return;
  }
  const bool visible =
      show_tools_ && view_.window.visible && !view_.window.miniaturized &&
      !view_.hiddenOrHasHiddenAncestor && view_.toolsView.superview == view_;
  // Docked tools draw through the window's pane compositors like its pages,
  // so switching back to a tab with tools open keeps their last frame.
  if (visible) {
    const auto pane =
        ShowInPaneCompositor(*tools_, view_.window, PaneRole::kDevTools);
    if (detached_ || !tools_ || !OwnsViews()) {
      return;
    }
    // A hand-off was mid-flight in a native callback; lay out, and so come
    // back here, again.
    if (pane == PaneCompositorShow::kBusy) {
      view_.needsLayout = YES;
    }
  } else {
    HidePaneCompositor(*tools_);
  }
  // Tools arriving are shown even when they report VISIBLE, as pages are
  // (AppKitBrowserHost::ApplyVisibility).
  const bool arriving = visible && !tools_shown_;
  tools_shown_ = visible;
  if (visible &&
      (arriving || tools_->GetVisibility() != content::Visibility::VISIBLE)) {
    tools_->WasShown();
  } else if (!visible &&
             tools_->GetVisibility() != content::Visibility::HIDDEN) {
    tools_->WasHidden();
  }
}
void NativeDevToolsPane::SetBlocked(bool blocked) {
  [view_ setToolsBlocked:blocked];
}
void NativeDevToolsPane::Detach() {
  if (detached_) {
    return;
  }
  // Revoke can deliver a genuine dialog result that releases the last external
  // pane owner. The destructor also calls Detach, when weak_from_this is empty.
  auto keep = weak_from_this().lock();
  detached_ = true;
  ++presentation_generation_;
  weak_factory_.InvalidateWeakPtrs();
  Observe(nullptr);
  if (auxiliary_) {
    auxiliary_->Revoke();
  }
  auxiliary_.reset();
  tools_observer_.reset();
  auto previous = std::exchange(tools_, {});
  NSView* previous_view = view_.toolsView;
  const bool owned = previous_view && previous_view.superview == view_;
  modal_binding_.RunAndReset();
  [view_ invalidate];
  // A tab move must not leave an unattached tools renderer marked visible.
  // Do not touch a view already adopted by a newer owner; this is the final
  // operation because visibility observers may reenter native teardown.
  if (owned && previous && previous_view && !previous_view.superview) {
    HidePaneCompositor(*previous);
  }
  if (owned && previous && previous_view && !previous_view.superview &&
      previous->GetVisibility() != content::Visibility::HIDDEN) {
    previous->WasHidden();
  }
}
}  // namespace parc
