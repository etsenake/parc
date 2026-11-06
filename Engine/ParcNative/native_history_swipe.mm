// Copyright 2026 Parc contributors.
#import "native_history_swipe.h"

#include <memory>
#include <utility>

#include "base/callback_list.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "chrome/browser/profiles/profile.h"
#import "chrome/browser/renderer_host/chrome_render_widget_host_view_mac_delegate.h"
#import "chrome/browser/renderer_host/chrome_render_widget_host_view_mac_history_swiper.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_process_host.h"
#include "content/public/browser/render_view_host.h"
#include "content/public/browser/render_widget_host.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#import "native_appkit_page.h"
#include "native_host_route.h"
#import "window_security_reservation.h"

// These are the existing superclass implementations; the recognizer remains
// owned by ChromeRenderWidgetHostViewMacDelegate, never recreated by the shell.
@interface ChromeRenderWidgetHostViewMacDelegate (NativeHistory)
    <HistorySwiperDelegate>
@end

namespace parc {
namespace {
class SwipeSession final : public content::WebContentsObserver {
 public:
  SwipeSession(content::WebContents& contents, PCNativePage* page,
               history_swiper::NavigationDirection direction,
               base::RepeatingClosure cancel)
      : content::WebContentsObserver(&contents), page_(page),
        window_(page.nativeView.window), direction_(direction),
        history_([page navigationHistoryBack:direction == history_swiper::kBackwards]),
        cancel_(std::move(cancel)) {
    auto weak = weak_factory_.GetWeakPtr();
    auto* tab = tabs::TabInterface::MaybeGetFromContents(&contents);
    if (tab) {
      deactivate_ = tab->RegisterWillDeactivate(base::BindRepeating(
          [](base::WeakPtr<SwipeSession> self, tabs::TabInterface*) {
            if (self) self->Cancel();
          }, weak));
      detach_ = tab->RegisterWillDetach(base::BindRepeating(
          [](base::WeakPtr<SwipeSession> self, tabs::TabInterface*,
             tabs::TabInterface::DetachReason) { if (self) self->Cancel(); }, weak));
    }
    auto cancel_block = ^(NSNotification*) { if (weak) weak->Cancel(); };
    for (NSNotificationName name in @[NSWindowWillCloseNotification,
        NSWindowDidResignKeyNotification, NSWindowDidMiniaturizeNotification,
        NSWindowWillBeginSheetNotification, PCNativeWindowSecurityStateChanged]) {
      [notifications_ addObject:[NSNotificationCenter.defaultCenter
          addObserverForName:name object:window_ queue:nil usingBlock:cancel_block]];
    }
    [notifications_ addObject:[NSNotificationCenter.defaultCenter
        addObserverForName:NSApplicationDidResignActiveNotification
        object:NSApp queue:nil usingBlock:cancel_block]];
  }
  ~SwipeSession() override {
    weak_factory_.InvalidateWeakPtrs();
    [history_ invalidate];
    for (id token in notifications_)
      [NSNotificationCenter.defaultCenter removeObserver:token];
  }
  bool Current() const {
    return !cancelled_ && !consumed_ && history_.valid && page_ &&
        page_.nativeView.window == window_ &&
        ContentsForNativePage(page_) == web_contents() &&
        CanNativePageHistorySwipe(page_);
  }
  bool Matches(history_swiper::NavigationDirection direction,
               NSWindow* window) const {
    return direction == direction_ && window == window_ && Current();
  }
  void Navigate(history_swiper::NavigationDirection direction, NSWindow* window) {
    if (!Matches(direction, window)) { Cancel(); return; }
    // The snapshot proves the original history is unchanged; the real command
    // still determines its skippable-entry destination and preserves POST state.
    PCNativePage* page = page_;
    consumed_ = true;
    [history_ invalidate];
    [page performNavigationAction:direction == history_swiper::kForwards
        ? PCNativeNavigationActionForward : PCNativeNavigationActionBack inNewTab:NO];
  }
  void Cancel() {
    if (cancelled_) return;
    cancelled_ = true;
    [history_ invalidate];
    // The delegate retains this object through the callback. It does not reset
    // it from an observer or AppKit tracking callback executing on this stack.
    cancel_.Run();
  }
 private:
  void DidStartNavigation(content::NavigationHandle* navigation) override {
    if (navigation->IsInPrimaryMainFrame()) Cancel();
  }
  void PrimaryPageChanged(content::Page&) override { Cancel(); }
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (visibility != content::Visibility::VISIBLE) Cancel();
  }
  void WebContentsDestroyed() override { Cancel(); }
  PCNativePage* __weak page_ = nil;
  NSWindow* __weak window_ = nil;
  history_swiper::NavigationDirection direction_;
  PCNativeNavigationHistory* __strong history_ = nil;
  base::RepeatingClosure cancel_;
  bool cancelled_ = false;
  bool consumed_ = false;
  base::CallbackListSubscription deactivate_, detach_;
  NSMutableArray* __strong notifications_ = [[NSMutableArray alloc] init];
  base::WeakPtrFactory<SwipeSession> weak_factory_{this};
};
}  // namespace
}  // namespace parc

@interface PCNativeHistorySwipeDelegate : ChromeRenderWidgetHostViewMacDelegate
- (void)cancelNativeGesture;
@end

@implementation PCNativeHistorySwipeDelegate {
  int _process;
  int _routing;
  BOOL _native;
  std::unique_ptr<parc::SwipeSession> _session;
}
- (instancetype)initWithRenderWidgetHost:(content::RenderWidgetHost*)host {
  self = [super initWithRenderWidgetHost:host];
  if (self) {
    _process = host->GetProcess()->GetDeprecatedID();
    _routing = host->GetRoutingID();
    Profile* profile = Profile::FromBrowserContext(host->GetProcess()->GetBrowserContext());
    _native = !!parc::GetNativeRoute(*profile) ||
        (profile->IsOffTheRecord() && !!parc::GetNativeRoute(*profile->GetOriginalProfile()));
  }
  return self;
}
- (PCNativePage*)originalPage {
  auto* host = content::RenderWidgetHost::FromID(_process, _routing);
  auto* view = host ? content::RenderViewHost::From(host) : nullptr;
  auto* contents = view ? content::WebContents::FromRenderViewHost(view) : nullptr;
  auto* frame = contents ? contents->GetPrimaryMainFrame() : nullptr;
  if (!frame || frame->GetRenderWidgetHost() != host) return nil;
  return parc::ExistingNativePage(contents);
}
- (void)cancelNativeGesture {
  [super cancelHistorySwiping];
}
- (void)cancelSession {
  if (_session) _session->Cancel();
  else [super cancelHistorySwiping];
}
- (BOOL)currentOwner {
  return NSEvent.swipeTrackingFromScrollEventsEnabled &&
      parc::CanNativePageHistorySwipe([self originalPage]) &&
      (!_session || _session->Current());
}
- (BOOL)handleEvent:(NSEvent*)event {
  if (!_native) return [super handleEvent:event];
  if (event.type == NSEventTypeScrollWheel && event.phase == NSEventPhaseBegan) {
    [self cancelSession];
    _session.reset();
  }
  if (![self currentOwner]) { [self cancelSession]; return NO; }
  return [super handleEvent:event];
}
- (void)touchesBeganWithEvent:(NSEvent*)event {
  if (_native) {
    [self cancelSession];
    _session.reset();
  }
  [super touchesBeganWithEvent:event];
}
- (void)touchesMovedWithEvent:(NSEvent*)event {
  if (_native && ![self currentOwner]) { [self cancelSession]; return; }
  [super touchesMovedWithEvent:event];
}
- (void)touchesCancelledWithEvent:(NSEvent*)event {
  [super touchesCancelledWithEvent:event];
  if (_native) [self cancelSession];
}
- (void)touchesEndedWithEvent:(NSEvent*)event {
  if (_native && ![self currentOwner]) { [self cancelSession]; return; }
  [super touchesEndedWithEvent:event];
}
- (BOOL)shouldAllowHistorySwiping {
  return [super shouldAllowHistorySwiping] && (!_native || [self currentOwner]);
}
- (BOOL)canNavigateInDirection:(history_swiper::NavigationDirection)direction
                      onWindow:(NSWindow*)window {
  if (!_native) return [super canNavigateInDirection:direction onWindow:window];
  PCNativePage* page = [self originalPage];
  if (!parc::CanNativePageHistorySwipe(page) || page.nativeView.window != window ||
      ![super canNavigateInDirection:direction onWindow:window]) return NO;
  if (!_session) {
    auto* contents = parc::ContentsForNativePage(page);
    __weak PCNativeHistorySwipeDelegate* weakSelf = self;
    _session = std::make_unique<parc::SwipeSession>(*contents, page, direction,
        base::BindRepeating([](PCNativeHistorySwipeDelegate* owner) {
          [owner cancelNativeGesture];
        }, weakSelf));
  }
  return _session->Matches(direction, window);
}
- (void)navigateInDirection:(history_swiper::NavigationDirection)direction
                   onWindow:(NSWindow*)window {
  if (!_native) { [super navigateInDirection:direction onWindow:window]; return; }
  if (_session) _session->Navigate(direction, window);
}
- (void)backwardsSwipeNavigationLikely {
  if (!_native || [self currentOwner]) [super backwardsSwipeNavigationLikely];
}
@end

namespace parc {
NSObject<RenderWidgetHostViewMacDelegate>* CreateNativeHistorySwipeDelegate(
    content::RenderWidgetHost* host) {
  return [[PCNativeHistorySwipeDelegate alloc] initWithRenderWidgetHost:host];
}
}  // namespace parc
