// Copyright 2026 Parc contributors.
// Hang decision adapted from Chromium Embedded Framework's hang_monitor.cc.
// Copyright 2024 The Chromium Embedded Framework Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found
// in the LICENSE file.
#include "native_page_observers.h"

#include <memory>
#include <utility>
#include <vector>
#include "base/callback_list.h"
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/hang_monitor/hang_crash_dump.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/hung_renderer/hung_renderer_core.h"
#include "chrome/grit/generated_resources.h"
#include "components/input/native_web_keyboard_event.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_process_host.h"
#include "content/public/browser/render_widget_host.h"
#include "content/public/browser/render_widget_host_observer.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#include "content/public/common/result_codes.h"
#import "dialog_style.h"
#include "native_appkit_page.h"
#include "native_engine_entry.h"
#include "native_history_swipe.h"
#include "native_internal_urls.h"
#include "native_link_routing.h"
#include "native_page_retirement.h"
#include "native_shortcuts.h"
#include "net/base/net_errors.h"
#include "ui/base/l10n/l10n_util.h"
#include "url/gurl.h"
#import "window_security_reservation.h"

namespace parc {
namespace {
// The widget observer retires the timer closure before its raw owner dies.
class HangDecision final : public content::RenderWidgetHostObserver {
 public:
  HangDecision(content::RenderWidgetHost& widget, base::RepeatingClosure restart)
      : widget_(&widget), restart_(std::move(restart)) { widget_->AddObserver(this); }
  ~HangDecision() override { Detach(); }
  content::RenderProcessHost* process() const {
    return widget_ ? widget_->GetProcess() : nullptr;
  }
  void Detach() {
    if (widget_) widget_->RemoveObserver(this);
    widget_ = nullptr;
    restart_.Reset();
  }
  void Wait() {
    auto restart = std::move(restart_);
    Detach();
    if (restart) restart.Run();
  }
  void Terminate() {
    auto* host = process();
    Detach();
    if (host) {
      CrashDumpHungChildProcess(host->GetProcess().Handle());
      host->Shutdown(content::RESULT_CODE_HUNG);
    }
  }
 private:
  void RenderWidgetHostDestroyed(content::RenderWidgetHost*) override { Detach(); }
  raw_ptr<content::RenderWidgetHost> widget_;
  base::RepeatingClosure restart_;
};
class NativeHungRenderer final
    : public content::WebContentsObserver,
      public content::WebContentsUserData<NativeHungRenderer> {
 public:
  ~NativeHungRenderer() override { Finish(false, false); }

  void Show(std::unique_ptr<HangDecision> callback) {
    // Retire the previous decision before replacing its presentation.
    const auto alive = weak_factory_.GetWeakPtr();
    const uint64_t replacement = generation_ + 1;
    if (callback_) callback_->Detach();
    Finish(false, false);
    if (!alive || alive->generation_ != replacement) {
      callback->Detach();
      return;
    }
    callback_ = std::move(callback);
    auto* contents = web_contents();
    auto* tab = tabs::TabInterface::MaybeGetFromContents(contents);
    PCNativePage* page = ExistingNativePage(contents);
    auto* frame = contents->GetPrimaryMainFrame();
    auto* browser = tab ? tab->GetBrowserWindowInterface() : nullptr;
    NSWindow* window = page.nativeView.window;
    if (!tab || !tab->IsActivated() || !frame || !frame->IsActive() ||
        !browser || browser->IsDeleteScheduled() || !window ||
        !window.isKeyWindow || !window.visible || window.miniaturized ||
        page.nativeView.hiddenOrHasHiddenAncestor || IsNativePageRetiring(page) ||
        window.attachedSheet || PCNativeWindowHasSecurityReservation(window)) {
      // Background/obscured pages keep their real timer. They never steal a
      // different page's window or silently terminate a shared process.
      Finish(true, false);
      return;
    }
    browser_ = browser->GetWeakPtr();
    document_ = frame->GetWeakDocumentPtr();
    window_ = window;
    const auto weak = weak_factory_.GetWeakPtr();
    deactivate_ = tab->RegisterWillDeactivate(base::BindRepeating(
        [](base::WeakPtr<NativeHungRenderer> self, tabs::TabInterface*) {
          if (self) self->Finish(true, false);
        }, weak));
    detach_ = tab->RegisterWillDetach(base::BindRepeating(
        [](base::WeakPtr<NativeHungRenderer> self, tabs::TabInterface*,
           tabs::TabInterface::DetachReason) {
          if (self) self->Responsive();
        }, weak));
    discard_ = tab->RegisterWillDiscardContents(base::BindRepeating(
        [](base::WeakPtr<NativeHungRenderer> self, tabs::TabInterface*,
           content::WebContents*, content::WebContents*) {
          if (self) self->Responsive();
        }, weak));
    // Acquiring a reservation can synchronously dismiss another native owner.
    auto reservation = [PCNativeWindowSecurityReservation acquireForWindow:window];
    if (!weak || !OwnerCurrent() || !reservation.isOnlyReservation) {
      [reservation invalidate];
      if (weak) Finish(true, false);
      return;
    }
    reservation_ = reservation;
    observations_ = [NSMutableArray array];
    for (NSNotificationName name in @[NSWindowWillCloseNotification,
                                      NSWindowDidMiniaturizeNotification,
                                      PCNativeWindowSecurityStateChanged]) {
      [observations_ addObject:[NSNotificationCenter.defaultCenter
          addObserverForName:name object:window queue:nil
          usingBlock:^(NSNotification*) {
            if (weak && (name != PCNativeWindowSecurityStateChanged ||
                         !weak->OwnerCurrent() ||
                         !weak->reservation_.isOnlyReservation)) {
              weak->Finish(true, false);
            }
          }]];
    }
    // List the pages sharing the actual unresponsive widget's process.
    content::RenderProcessHost* process = callback_->process();
    if (!process) { Responsive(); return; }
    const std::vector<content::WebContents*> hung =
        GetHungWebContentsList(contents, process);
    const int count = static_cast<int>(hung.size());
    NSMutableString* info = [base::SysUTF16ToNSString(
        l10n_util::GetPluralStringFUTF16(IDS_BROWSER_HANGMONITOR_RENDERER, count))
        mutableCopy];
    [info appendString:@"\n"];
    for (content::WebContents* affected : hung) {
      [info appendFormat:@"\n%@", base::SysUTF16ToNSString(
          GetHungWebContentsTitle(affected, process))];
    }
    alert_ = [[PCDialogPrompt alloc]
        initWithTitle:base::SysUTF16ToNSString(l10n_util::GetPluralStringFUTF16(
                          IDS_BROWSER_HANGMONITOR_RENDERER_TITLE, count))
              message:info];
    // Wait answers Return and Escape; ending the pages is never a key's default.
    alert_.escapeButton = [alert_
        addButtonWithTitle:base::SysUTF16ToNSString(l10n_util::GetStringUTF16(
                               IDS_BROWSER_HANGMONITOR_RENDERER_WAIT))
                      role:PCDialogPromptPrimary
                  response:NSAlertFirstButtonReturn];
    [alert_ addButtonWithTitle:base::SysUTF16ToNSString(l10n_util::GetPluralStringFUTF16(
                                   IDS_BROWSER_HANGMONITOR_RENDERER_END, count))
                          role:PCDialogPromptAuxiliary
                      response:NSAlertSecondButtonReturn];
    const uint64_t generation = generation_;
    [alert_ beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
      if (!weak || weak->generation_ != generation) return;
      const bool terminate = response == NSAlertSecondButtonReturn &&
          weak->OwnerCurrent() && weak->reservation_.isOnlyReservation;
      weak->Finish(true, terminate);
    }];
  }

  void Responsive() {
    if (callback_) callback_->Detach();
    Finish(false, false);
  }

 private:
  friend class content::WebContentsUserData<NativeHungRenderer>;
  explicit NativeHungRenderer(content::WebContents* contents)
      : content::WebContentsObserver(contents),
        content::WebContentsUserData<NativeHungRenderer>(*contents) {}

  bool OwnerCurrent() const {
    auto* contents = web_contents();
    auto* frame = document_.AsRenderFrameHostIfValid();
    auto* tab = contents ? tabs::TabInterface::MaybeGetFromContents(contents) : nullptr;
    PCNativePage* page = ExistingNativePage(contents);
    return callback_ && contents && !contents->IsBeingDestroyed() &&
        frame && frame->IsActive() && frame == contents->GetPrimaryMainFrame() &&
        browser_ && !browser_->IsDeleteScheduled() && browser_->GetWindow() &&
        tab && tab->IsActivated() && tab->GetBrowserWindowInterface() == browser_.get() &&
        window_ && window_.visible && !window_.miniaturized &&
        browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow() == window_ &&
        page.nativeView.window == window_ && !page.nativeView.hiddenOrHasHiddenAncestor &&
        !IsNativePageRetiring(page);
  }

  void Finish(bool restart_timer, bool terminate) {
    const auto alive = weak_factory_.GetWeakPtr();
    const uint64_t generation = ++generation_;
    auto callback = std::move(callback_);
    callback_ = nullptr;
    auto browser = browser_;
    auto document = document_;
    auto contents = web_contents() ? web_contents()->GetWeakPtr()
                                  : base::WeakPtr<content::WebContents>();
    NSWindow* __weak window = window_;
    PCDialogPrompt* alert = alert_;
    auto reservation = reservation_;
    alert_ = nil;
    reservation_ = nil;
    browser_.reset();
    document_ = {};
    window_ = nil;
    deactivate_ = {};
    detach_ = {};
    discard_ = {};
    for (id observer in observations_) {
      [NSNotificationCenter.defaultCenter removeObserver:observer];
    }
    observations_ = nil;
    // All state is retired before AppKit/reservation callbacks can reenter or
    // destroy this object. Only local values are used after these operations.
    if (alert.window.sheetParent) {
      [alert.window.sheetParent endSheet:alert.window returnCode:NSModalResponseCancel];
    }
    [alert.window orderOut:nil];
    [reservation invalidate];
    if (!callback || !restart_timer) return;
    if (!alive || alive->generation_ != generation) {
      callback->Detach();
      return;
    }
    auto* tab = contents ? tabs::TabInterface::MaybeGetFromContents(contents.get()) : nullptr;
    auto* frame = document.AsRenderFrameHostIfValid();
    PCNativePage* page = ExistingNativePage(contents.get());
    const bool current = contents && !contents->IsBeingDestroyed() && frame &&
        frame->IsActive() && frame == contents->GetPrimaryMainFrame() && browser &&
        !browser->IsDeleteScheduled() && browser->GetWindow() && tab &&
        tab->IsActivated() && tab->GetBrowserWindowInterface() == browser.get() &&
        window && window.visible && !window.miniaturized &&
        browser->GetWindow()->GetNativeWindow().GetNativeNSWindow() == window &&
        page.nativeView.window == window && !IsNativePageRetiring(page);
    if (terminate && current) callback->Terminate();
    else callback->Wait();
  }

  void PrimaryPageChanged(content::Page&) override { Responsive(); }
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus) override {
    Responsive();
  }
  void WebContentsDestroyed() override { Responsive(); }
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (visibility == content::Visibility::HIDDEN) Finish(true, false);
  }
  std::unique_ptr<HangDecision> callback_;
  base::WeakPtr<BrowserWindowInterface> browser_;
  content::WeakDocumentPtr document_;
  NSWindow* __weak window_ = nil;
  PCDialogPrompt* __strong alert_ = nil;
  PCNativeWindowSecurityReservation* __strong reservation_ = nil;
  NSMutableArray* __strong observations_ = nil;
  base::CallbackListSubscription deactivate_, detach_, discard_;
  uint64_t generation_ = 0;
  base::WeakPtrFactory<NativeHungRenderer> weak_factory_{this};
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};
WEB_CONTENTS_USER_DATA_KEY_IMPL(NativeHungRenderer);

class NativePageDisplayObserver final
    : public content::WebContentsObserver,
      public content::WebContentsUserData<NativePageDisplayObserver> {
 public:
  ~NativePageDisplayObserver() override = default;
 private:
  friend class content::WebContentsUserData<NativePageDisplayObserver>;
  explicit NativePageDisplayObserver(content::WebContents* contents)
      : content::WebContentsObserver(contents),
        content::WebContentsUserData<NativePageDisplayObserver>(*contents) {}
  void DidFinishNavigation(content::NavigationHandle* navigation) override {
    if (navigation->HasCommitted() && navigation->IsInPrimaryMainFrame() &&
        navigation->GetNetErrorCode() == net::OK)
      UpdateNativeLinkURL(*web_contents(), navigation->GetURL());
  }
  void WebContentsDestroyed() override { NotifyNativeEngineOwnershipChanged(); }
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};
WEB_CONTENTS_USER_DATA_KEY_IMPL(NativePageDisplayObserver);
}  // namespace

void InstallNativePageObservers(content::WebContents& contents) {
  CHECK(NSThread.isMainThread);
  NativePageDisplayObserver::CreateForWebContents(&contents);
  NativeHungRenderer::CreateForWebContents(&contents);
}
void NativePageTargetURLChanged(content::WebContents& contents, const GURL& target) {
  UpdateNativePageStatusText(contents, base::SysUTF8ToNSString(
      target.SchemeIs("chrome") ? PublicInternalURL(target).spec() : target.spec()));
}
bool HandleNativePageUnhandledKey(content::WebContents& contents,
                                  const input::NativeWebKeyboardEvent& event) {
  if (event.skip_if_unhandled ||
      event.GetType() != blink::WebInputEvent::Type::kRawKeyDown) return false;
  NSEvent* native = event.os_event.Get();
  if (auto result = HandleUnhandledNativeShortcut(contents, native)) return *result;
  return native.type == NSEventTypeKeyDown &&
      (native.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask) &&
      [NSApp.mainMenu performKeyEquivalent:native];
}
void NativePageRendererUnresponsive(content::WebContents& contents,
                                    content::RenderWidgetHost& widget,
                                    base::RepeatingClosure restart) {
  InstallNativePageObservers(contents);
  NativeHungRenderer::FromWebContents(&contents)->Show(
      std::make_unique<HangDecision>(widget, std::move(restart)));
}
void NativePageRendererResponsive(content::WebContents& contents) {
  if (auto* hung = NativeHungRenderer::FromWebContents(&contents)) hung->Responsive();
}
void DetachNativePageObservers(content::WebContents& contents) {
  NativePageRendererResponsive(contents);
}
NSObject<RenderWidgetHostViewMacDelegate>* NativePageHistorySwipeDelegate(
    content::RenderWidgetHost* host, bool is_popup) {
  return host && !is_popup ? CreateNativeHistorySwipeDelegate(host) : nil;
}
}  // namespace parc
