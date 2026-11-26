#import "native_history_swipe.h"

#include <memory>
#include <utility>
#include <vector>

#include "base/callback_list.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/profiles/profile.h"
#import "chrome/browser/renderer_host/chrome_render_widget_host_view_mac_delegate.h"
#include "chrome/browser/renderer_host/chrome_render_widget_host_view_mac_history_swiping_control.h"
#include "chrome/browser/ui/browser_commands.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/favicon_status.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/preloading.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_process_host.h"
#include "content/public/browser/render_view_host.h"
#include "content/public/browser/render_widget_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "third_party/blink/public/common/input/web_gesture_event.h"
#include "ui/base/window_open_disposition.h"
#include "ui/events/blink/did_overscroll_params.h"
#include "ui/gfx/image/image.h"
#import "native_appkit_page.h"
#include "native_host_route.h"
#include "native_internal_urls.h"
#import "page_host.h"
#import "window_security_reservation.h"

@interface PCNativeHistorySwipeEntry ()
- (instancetype)initWithEntry:(content::NavigationEntry*)entry;
@end

@implementation PCNativeHistorySwipeEntry
@synthesize title = _title;
@synthesize URL = _URL;
@synthesize favicon = _favicon;
- (instancetype)initWithEntry:(content::NavigationEntry*)entry {
  self = [super init];
  if (self) {
    _title = base::SysUTF16ToNSString(entry->GetTitleForDisplay());
    _URL = [NSURL URLWithString:base::SysUTF8ToNSString(
        parc::PublicInternalURL(entry->GetVirtualURL()).spec())];
    const auto& icon = entry->GetFavicon();
    if (icon.valid && !icon.image.IsEmpty()) {
      _favicon = [icon.image.ToNSImage() copy];
    }
  }
  return self;
}
@end

@interface PCNativeHistorySwipeHistory ()
- (instancetype)initWithEntries:(NSArray<PCNativeHistorySwipeEntry*>*)entries
                   currentIndex:(NSInteger)currentIndex;
@end

@implementation PCNativeHistorySwipeHistory
@synthesize entries = _entries;
@synthesize currentIndex = _currentIndex;
- (instancetype)initWithEntries:(NSArray<PCNativeHistorySwipeEntry*>*)entries
                   currentIndex:(NSInteger)currentIndex {
  self = [super init];
  if (self) {
    _entries = [entries copy];
    _currentIndex = currentIndex;
  }
  return self;
}
@end

namespace parc {
namespace {
class SwipeSession final : public content::WebContentsObserver {
 public:
  SwipeSession(content::WebContents& contents, PCNativePage* page, bool back,
               base::RepeatingClosure cancel)
      : content::WebContentsObserver(&contents), page_(page),
        window_(page.nativeView.window), back_(back),
        cancel_(std::move(cancel)) {
    auto& controller = contents.GetController();
    current_index_ = controller.GetCurrentEntryIndex();
    auto* pending = controller.GetPendingEntry();
    pending_id_ = pending ? pending->GetUniqueID() : 0;
    for (int i = 0; i < controller.GetEntryCount(); ++i)
      entry_ids_.push_back(controller.GetEntryAtIndex(i)->GetUniqueID());
    if (auto* frame = contents.GetPrimaryMainFrame())
      document_ = frame->GetWeakDocumentPtr();
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
        NSWindowDidMiniaturizeNotification, NSWindowWillBeginSheetNotification,
        PCNativeWindowSecurityStateChanged]) {
      [notifications_ addObject:[NSNotificationCenter.defaultCenter
          addObserverForName:name object:window_ queue:nil usingBlock:cancel_block]];
    }
  }
  ~SwipeSession() override {
    weak_factory_.InvalidateWeakPtrs();
    for (id token in notifications_)
      [NSNotificationCenter.defaultCenter removeObserver:token];
  }
  bool Current() const {
    return !cancelled_ && !consumed_ && page_ &&
        page_.nativeView.window == window_ &&
        ContentsForNativePage(page_) == web_contents() && HistoryUnchanged() &&
        CanNativePageHistorySwipe(page_);
  }
  PCNativeHistorySwipeHistory* History() {
    auto& controller = web_contents()->GetController();
    NSMutableArray<PCNativeHistorySwipeEntry*>* entries = [NSMutableArray array];
    for (int i = 0; i < controller.GetEntryCount(); ++i) {
      [entries addObject:[[PCNativeHistorySwipeEntry alloc]
          initWithEntry:controller.GetEntryAtIndex(i)]];
    }
    return [[PCNativeHistorySwipeHistory alloc] initWithEntries:entries
                                                   currentIndex:current_index_];
  }
  bool NavigateAdjacent(bool back) {
    if (back != back_ || !Current()) { Close(); return false; }
    consumed_ = true;
    if (back) chrome::GoBack(web_contents());
    else chrome::GoForward(web_contents());
    return true;
  }
  bool NavigateToEntry(bool back, int distance) {
    const int index = current_index_ + (back ? -distance : distance);
    if (back != back_ || distance < 1 || index < 0 ||
        index >= static_cast<int>(entry_ids_.size()) || !Current()) {
      Close();
      return false;
    }
    consumed_ = true;
    web_contents()->GetController().GoToIndex(index);
    return true;
  }
  void Close() { cancelled_ = true; }
  void Cancel() {
    if (cancelled_) return;
    cancelled_ = true;
    cancel_.Run();
  }
 private:
  bool HistoryUnchanged() const {
    auto* contents = web_contents();
    auto* document = document_.AsRenderFrameHostIfValid();
    if (!contents || !document || document != contents->GetPrimaryMainFrame())
      return false;
    auto& controller = contents->GetController();
    auto* pending = controller.GetPendingEntry();
    if (controller.GetCurrentEntryIndex() != current_index_ ||
        (pending ? pending->GetUniqueID() : 0) != pending_id_ ||
        controller.GetEntryCount() != static_cast<int>(entry_ids_.size())) return false;
    for (int i = 0; i < controller.GetEntryCount(); ++i)
      if (controller.GetEntryAtIndex(i)->GetUniqueID() != entry_ids_[i]) return false;
    return back_ ? controller.CanGoBack() : controller.CanGoForward();
  }
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
  bool back_;
  int current_index_ = -1;
  int pending_id_ = 0;
  std::vector<int> entry_ids_;
  content::WeakDocumentPtr document_;
  base::RepeatingClosure cancel_;
  bool cancelled_ = false;
  bool consumed_ = false;
  base::CallbackListSubscription deactivate_, detach_;
  NSMutableArray* __strong notifications_ = [[NSMutableArray alloc] init];
  base::WeakPtrFactory<SwipeSession> weak_factory_{this};
};

__weak id<PCNativeHistorySwipeClient> history_swipe_client;
}
}

@class PCNativeHistorySwipeDelegate;

@interface PCNativeHistorySwipeSource ()
- (instancetype)initWithDelegate:(PCNativeHistorySwipeDelegate*)delegate;
@end

@interface PCNativeHistorySwipeDelegate : ChromeRenderWidgetHostViewMacDelegate
- (PCNativePage*)originalPage;
- (NSView*)overlayContainer;
- (BOOL)allowsHistorySwipe;
- (NSInteger)historyEntriesBack:(BOOL)back;
- (PCNativeHistorySwipeHistory*)beginSwipeBack:(BOOL)back;
- (BOOL)navigateBack:(BOOL)back;
- (BOOL)navigateBack:(BOOL)back distance:(NSInteger)distance;
- (void)endSwipe;
- (void)preloadBack;
- (void)sessionDidCancel;
@end

@implementation PCNativeHistorySwipeSource {
  PCNativeHistorySwipeDelegate* __weak _delegate;
}
+ (id<PCNativeHistorySwipeClient>)client {
  CHECK(NSThread.isMainThread);
  return parc::history_swipe_client;
}
+ (void)setClient:(id<PCNativeHistorySwipeClient>)client {
  CHECK(NSThread.isMainThread);
  parc::history_swipe_client = client;
}
- (instancetype)initWithDelegate:(PCNativeHistorySwipeDelegate*)delegate {
  self = [super init];
  if (self) _delegate = delegate;
  return self;
}
- (NSView*)overlayContainer {
  return [_delegate overlayContainer];
}
- (BOOL)allowsHistorySwipe {
  return [_delegate allowsHistorySwipe];
}
- (NSInteger)historyEntriesBack:(BOOL)back {
  return [_delegate historyEntriesBack:back];
}
- (PCNativeHistorySwipeHistory*)beginSwipeBack:(BOOL)back {
  return [_delegate beginSwipeBack:back];
}
- (BOOL)navigateBack:(BOOL)back {
  return [_delegate navigateBack:back];
}
- (BOOL)navigateBack:(BOOL)back distance:(NSInteger)distance {
  return [_delegate navigateBack:back distance:distance];
}
- (void)endSwipe {
  [_delegate endSwipe];
}
- (void)preloadBack {
  [_delegate preloadBack];
}
@end

@implementation PCNativeHistorySwipeDelegate {
  int _process;
  int _routing;
  BOOL _native;
  std::unique_ptr<parc::SwipeSession> _session;
  PCNativeHistorySwipeSource* _source;
  id<PCNativeHistorySwipeHandler> _handler;
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
- (void)dealloc {
  [self cancelGesture];
}
- (content::WebContents*)originalContents {
  auto* host = content::RenderWidgetHost::FromID(_process, _routing);
  auto* view = host ? content::RenderViewHost::From(host) : nullptr;
  auto* contents = view ? content::WebContents::FromRenderViewHost(view) : nullptr;
  auto* frame = contents ? contents->GetPrimaryMainFrame() : nullptr;
  return frame && frame->GetRenderWidgetHost() == host ? contents : nullptr;
}
- (PCNativePage*)originalPage {
  auto* contents = [self originalContents];
  return contents ? parc::ExistingNativePage(contents) : nil;
}
- (NSView*)overlayContainer {
  auto* host = content::RenderWidgetHost::FromID(_process, _routing);
  auto* widget = host ? host->GetView() : nullptr;
  NSView* view = widget ? widget->GetNativeView().GetNativeNSView() : nil;
  for (NSView* ancestor = view.superview; ancestor; ancestor = ancestor.superview) {
    if ([ancestor isKindOfClass:PCNativePageHost.class])
      return [(PCNativePageHost*)ancestor historyOverlayContainer] ?: view;
  }
  return view;
}
- (BOOL)allowsHistorySwipe {
  auto* contents = [self originalContents];
  if (!contents) return NO;
  auto* control = history_swiper::HistorySwipingControl::FromWebContents(contents);
  return (!control || control->ShouldAllowHistorySwiping()) &&
      parc::CanNativePageHistorySwipe(parc::ExistingNativePage(contents)) &&
      (!_session || _session->Current());
}
- (NSInteger)historyEntriesBack:(BOOL)back {
  if (![self allowsHistorySwipe]) return 0;
  auto& controller = [self originalContents]->GetController();
  if (!(back ? controller.CanGoBack() : controller.CanGoForward())) return 0;
  const int current = controller.GetCurrentEntryIndex();
  return back ? current : controller.GetEntryCount() - 1 - current;
}
- (PCNativeHistorySwipeHistory*)beginSwipeBack:(BOOL)back {
  PCNativePage* page = [self originalPage];
  if ([self historyEntriesBack:back] < 1) return nil;
  _session.reset();
  __weak PCNativeHistorySwipeDelegate* weakSelf = self;
  _session = std::make_unique<parc::SwipeSession>(
      *parc::ContentsForNativePage(page), page, back,
      base::BindRepeating(^{ [weakSelf sessionDidCancel]; }));
  if (!_session->Current()) {
    _session->Close();
    return nil;
  }
  return _session->History();
}
- (BOOL)navigateBack:(BOOL)back {
  return _session && _session->NavigateAdjacent(back);
}
- (BOOL)navigateBack:(BOOL)back distance:(NSInteger)distance {
  return _session && _session->NavigateToEntry(back, static_cast<int>(distance));
}
- (void)endSwipe {
  if (_session) _session->Close();
}
- (void)preloadBack {
  auto* contents = [self originalContents];
  if (!contents || ![self allowsHistorySwipe]) return;
  contents->BackNavigationLikely(content::preloading_predictor::kBackGestureNavigation,
                                 WindowOpenDisposition::kCurrentTab);
}
- (void)sessionDidCancel {
  [_handler historySwipeSourceDidCancel:_source];
}
- (void)cancelGesture {
  if (_session) _session->Close();
  [_handler historySwipeSourceDidCancel:_source];
}
- (void)startGesture {
  if (!_session) return;
  _session->Cancel();
  _session.reset();
}
- (id<PCNativeHistorySwipeHandler>)swipeHandler {
  if (!_native) return nil;
  if (!_handler) {
    id<PCNativeHistorySwipeClient> client = parc::history_swipe_client;
    if (!client) return nil;
    _source = [[PCNativeHistorySwipeSource alloc] initWithDelegate:self];
    _handler = [client historySwipeHandlerForSource:_source];
  }
  return _handler;
}
- (BOOL)handleEvent:(NSEvent*)event {
  if (event.type != NSEventTypeScrollWheel || !_native) return NO;
  if (event.phase == NSEventPhaseBegan) [self startGesture];
  id<PCNativeHistorySwipeHandler> handler = [self swipeHandler];
  return handler && [handler historySwipeSource:_source scrollEvent:event];
}
- (void)forwardTouches:(NSEvent*)event phase:(PCNativeHistorySwipeTouchPhase)phase {
  [[self swipeHandler] historySwipeSource:_source touchEvent:event phase:phase];
}
- (void)touchesBeganWithEvent:(NSEvent*)event {
  if (!_native) return;
  [self startGesture];
  [self forwardTouches:event phase:PCNativeHistorySwipeTouchPhaseBegan];
}
- (void)touchesMovedWithEvent:(NSEvent*)event {
  if (_native) [self forwardTouches:event phase:PCNativeHistorySwipeTouchPhaseMoved];
}
- (void)touchesCancelledWithEvent:(NSEvent*)event {
  if (_native) [self forwardTouches:event phase:PCNativeHistorySwipeTouchPhaseCancelled];
}
- (void)touchesEndedWithEvent:(NSEvent*)event {
  if (_native) [self forwardTouches:event phase:PCNativeHistorySwipeTouchPhaseEnded];
}
- (void)rendererHandledGestureScrollEvent:(const blink::WebGestureEvent&)event
                                 consumed:(BOOL)consumed {
  id<PCNativeHistorySwipeHandler> handler = [self swipeHandler];
  if (!handler) return;
  switch (event.GetType()) {
    case blink::WebInputEvent::Type::kGestureScrollBegin:
      [handler historySwipeSource:_source
          pageScrollBeganSynthetic:event.data.scroll_begin.synthetic
                          momentum:event.data.scroll_begin.inertial_phase ==
              blink::WebGestureEvent::InertialPhaseState::kMomentum];
      break;
    case blink::WebInputEvent::Type::kGestureScrollUpdate:
      [handler historySwipeSource:_source pageScrollUpdatedConsumed:consumed];
      break;
    default:
      break;
  }
}
- (void)rendererHandledOverscrollEvent:(const ui::DidOverscrollParams&)params {
  [[self swipeHandler] historySwipeSource:_source
               overscrollPropagatesX:params.overscroll_behavior.PropagatesXScroll()];
}
- (void)viewGone:(NSView*)view {
  [self cancelGesture];
}
@end

namespace parc {
NSObject<RenderWidgetHostViewMacDelegate>* CreateNativeHistorySwipeDelegate(
    content::RenderWidgetHost* host) {
  return [[PCNativeHistorySwipeDelegate alloc] initWithRenderWidgetHost:host];
}
}
