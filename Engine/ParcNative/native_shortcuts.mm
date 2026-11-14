// Copyright 2026 Parc contributors.
#include "native_shortcuts.h"
#include <utility>
#include "base/functional/bind.h"
#include "parc/frame_focus.h"
#include "base/task/single_thread_task_runner.h"
#include "native_escape_state.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "base/timer/timer.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_manager.h"
#include "chrome/browser/ui/exclusive_access/keyboard_lock_controller.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_widget_host.h"
#include "content/public/browser/render_widget_host_observer.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#include "components/input/native_web_keyboard_event.h"
#include "native_appkit_host.h"
#include "native_appkit_page.h"
#import "window_security_reservation.h"

namespace {
NSString* const kBindingsChanged = @"ParcNativeShortcutBindingsChanged";
}
@implementation PCNativeShortcutCommand
@synthesize item = _item, revision = _revision, priority = _priority;
- (instancetype)initWithItem:(NSMenuItem*)item revision:(uint64_t)revision
                   priority:(PCNativeShortcutPriority)priority {
  if ((self = [super init])) {
    _item = item; _revision = revision; _priority = priority;
  }
  return self;
}
+ (void)bindingsDidChange {
  [[NSNotificationCenter defaultCenter] postNotificationName:kBindingsChanged
                                                     object:nil];
}
@end
namespace parc {
namespace {
using Result = content::KeyboardEventProcessingResult;
constexpr base::TimeDelta kRepeatCueLifetime = base::Seconds(5);
// Escape is a page-owned input outcome, not a configurable menu shortcut.
// Native macOS cancel/Exit is a separate responder-chain route in PeekHostView.
class EscapeRouter final : public content::WebContentsObserver,
                           public content::WebContentsUserData<EscapeRouter>,
                           public content::RenderWidgetHost::InputEventObserver,
                           public content::RenderWidgetHostObserver {
 public:
  ~EscapeRouter() override {
    Invalidate();
    input_.Reset();
    widget_.Reset();
    for (id token in notifications_)
      [[NSNotificationCenter defaultCenter] removeObserver:token];
  }

  void Pre(BrowserWindowInterface& browser,
           const input::NativeWebKeyboardEvent& event) {
    if (event.GetType() != blink::WebInputEvent::Type::kRawKeyDown)
      return;
    NSEvent* native = event.os_event.Get();
    auto* binding = AppKitBindingForBrowser(&browser);
    auto* page = ExistingNativePage(web_contents());
    auto* frame = web_contents()->GetFocusedFrame();
    if (!native || native.keyCode != 53 || event.windows_key_code != 27 ||
        events_.IsIgnored(native.timestamp, native.keyCode, native.modifierFlags) ||
        (native.modifierFlags &
         (NSEventModifierFlagCommand | NSEventModifierFlagOption |
          NSEventModifierFlagControl | NSEventModifierFlagShift)) ||
        event.skip_if_unhandled || !Ready(browser, binding, page, frame)) {
      if (native && native.keyCode == 53)
        events_.IgnoreNative(native.timestamp, native.keyCode, native.modifierFlags);
      Invalidate();
      return;
    }
    // Configured native shortcuts retain their existing priority and renderer
    // ACK owner; an Escape binding must never execute two command paths.
    if ([binding.client respondsToSelector:@selector
                        (nativeBrowser:shortcutForEvent:page:editable:)] &&
        [binding.client
               nativeBrowser:binding
            shortcutForEvent:native
                        page:page
                    editable:web_contents()->IsFocusedElementEditable()]) {
      Invalidate();
      return;
    }
    // A different document/focused element starts a different heuristic owner.
    if (!Current()) {
      Invalidate();
      browser_ = browser.GetWeakPtr();
      binding_ = binding;
      page_ = page;
      window_ = binding.window;
      document_ = web_contents()->GetPrimaryMainFrame()->GetWeakDocumentPtr();
      focused_document_ = frame->GetWeakDocumentPtr();
      node_ = frame->GetFocusedDOMNodeId();
    }
    if (!Current())
      return;
    if (widget_.GetSource() != frame->GetRenderWidgetHost()) {
      input_.Reset();
      widget_.Reset();
      widget_.Observe(frame->GetRenderWidgetHost());
      input_.Observe(frame->GetRenderWidgetHost());
    }
    events_.Begin({event.TimeStamp().since_origin().InMicroseconds(),
                   event.native_key_code, native.timestamp,
                   native.modifierFlags});
  }

  bool OwnsUnhandled(NSEvent* event) const {
    return event && event.type == NSEventTypeKeyDown &&
           events_.OwnsUnhandled(event.timestamp, event.keyCode,
                                 event.modifierFlags);
  }

 private:
  friend class content::WebContentsUserData<EscapeRouter>;
  explicit EscapeRouter(content::WebContents* contents)
      : content::WebContentsObserver(contents),
        content::WebContentsUserData<EscapeRouter>(*contents) {
    auto weak = weak_factory_.GetWeakPtr();
    focus_subscription_ = SubscribeFrameFocus(*contents, base::BindRepeating(
        &EscapeRouter::Invalidate, weak));
    NSMutableArray* tokens = [NSMutableArray array];
    for (NSString* name in @[
           NSWindowDidResignKeyNotification, NSWindowWillCloseNotification,
           NSApplicationDidResignActiveNotification
         ]) {
      [tokens
          addObject:
              [[NSNotificationCenter defaultCenter]
                  addObserverForName:name
                              object:nil
                               queue:nil
                          usingBlock:^(NSNotification* note) {
                            if (weak &&
                                ([note.name
                                     isEqualToString:
                                         NSApplicationDidResignActiveNotification] ||
                                 note.object == weak->window_))
                              weak->Invalidate();
                          }]];
    }
    notifications_ = [tokens copy];
  }
  bool Ready(BrowserWindowInterface& browser,
             PCNativeBrowserWindow* binding,
             PCNativePage* page,
             content::RenderFrameHost* frame) const {
    auto* contents = web_contents();
    NSWindow* window = binding.window;
    NSView* responder = [window.firstResponder isKindOfClass:[NSView class]]
                            ? (NSView*)window.firstResponder
                            : nil;
    auto* exclusive = ExclusiveAccessManager::From(&browser);
    if ([responder respondsToSelector:@selector(hasMarkedText)] &&
        [(id<NSTextInputClient>)responder hasMarkedText])
      return false;
    return contents && !contents->IsBeingDestroyed() && page && !page.closed &&
           frame && frame->IsActive() && !browser.IsDeleteScheduled() &&
           GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(
               contents) == &browser &&
           browser.GetTabStripModel()->GetActiveWebContents() == contents &&
           AppKitBrowserAcceptsNewPages(browser) && binding.client &&
           [binding.client selectedNativePage] == page && NSApp.active &&
           window.keyWindow && window.visible && !window.miniaturized &&
           !window.attachedSheet &&
           !PCNativeWindowHasSecurityReservation(window) &&
           page.nativeView.window == window &&
           !page.nativeView.hiddenOrHasHiddenAncestor && responder &&
           (responder == page.nativeView ||
            [responder isDescendantOf:page.nativeView]) &&
           contents->GetVisibility() == content::Visibility::VISIBLE &&
           !contents->IsShowingContextMenu() &&
           !(exclusive &&
             exclusive->keyboard_lock_controller()->IsKeyboardLockActive()) &&
           [binding.client respondsToSelector:@selector(nativeBrowser:
                                                  canHandlePeekEscapeFrom:)] &&
           [binding.client nativeBrowser:binding canHandlePeekEscapeFrom:page];
  }
  bool Current() const {
    auto* contents = web_contents();
    auto* frame = focused_document_.AsRenderFrameHostIfValid();
    return contents && browser_ && binding_ && page_ && window_ &&
           document_.AsRenderFrameHostIfValid() ==
               contents->GetPrimaryMainFrame() &&
           contents->GetFocusedFrame() == frame && frame &&
           frame->GetFocusedDOMNodeId() == node_ &&
           AppKitBindingForBrowser(browser_.get()) == binding_ &&
           Ready(*browser_, binding_, page_, frame);
  }
  void Invalidate() {
    events_.Invalidate();
    browser_.reset();
    binding_ = nil;
    page_ = nil;
    window_ = nil;
  }
  void Deliver(uint64_t sequence) {
    const auto outcome = events_.Take(sequence);  // Consume before reentry.
    if (!outcome)
      return;
    if (!Current()) {
      Invalidate();
      return;
    }
    auto* binding = binding_;
    auto* page = page_;
    if ([binding.client
            respondsToSelector:@selector(nativeBrowser:
                                   handlePeekEscapeFrom:prefersConfirmation:)])
      [binding.client nativeBrowser:binding
               handlePeekEscapeFrom:page
                prefersConfirmation:outcome->prefers_confirmation()];
  }
  void OnInputEventAck(const content::RenderWidgetHost& host,
                       blink::mojom::InputEventResultSource source,
                       blink::mojom::InputEventResultState result,
                       const blink::WebInputEvent& event) override {
    if (&host != widget_.GetSource() ||
        event.GetType() != blink::WebInputEvent::Type::kRawKeyDown)
      return;
    const auto timestamp = event.TimeStamp().since_origin().InMicroseconds();
    const auto key =
        static_cast<const blink::WebKeyboardEvent&>(event).native_key_code;
    if (!events_.HasAckKey(timestamp, key))
      return;
    if (source != blink::mojom::InputEventResultSource::kMainThread ||
        (result != blink::mojom::InputEventResultState::kConsumed &&
         result != blink::mojom::InputEventResultState::kNotConsumed) ||
        !Current()) {
      Invalidate();
      return;
    }
    const auto sequence = events_.Acknowledge(
        timestamp, key,
        result == blink::mojom::InputEventResultState::kConsumed,
        web_contents()->IsFocusedElementEditable(),
        base::TimeTicks::Now().since_origin().InSecondsF(),
        NSEvent.keyRepeatDelay);
    if (!sequence)
      return;
    // Closing during InputEventObserver iteration can destroy its host. The
    // posted action revalidates the original owner and consumes its token once.
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&EscapeRouter::Deliver,
                                  weak_factory_.GetWeakPtr(), *sequence));
  }
  void OnInputEvent(const content::RenderWidgetHost&,
                    const blink::WebInputEvent& event,
                    InputEventSource) override {
    if (event.GetType() == blink::WebInputEvent::Type::kMouseDown ||
        event.GetType() == blink::WebInputEvent::Type::kMouseWheel ||
        event.GetType() == blink::WebInputEvent::Type::kTouchStart ||
        event.GetType() == blink::WebInputEvent::Type::kGestureTapDown)
      Invalidate();
  }
  void OnFocusChangedInPage(const content::FocusedNodeDetails&) override {
    Invalidate();
  }
  void OnWebContentsLostFocus(content::RenderWidgetHost*) override {
    Invalidate();
  }
  void DidStartNavigation(content::NavigationHandle*) override { Invalidate(); }
  void PrimaryPageChanged(content::Page&) override { Invalidate(); }
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (visibility != content::Visibility::VISIBLE)
      Invalidate();
  }
  void RenderWidgetHostDestroyed(content::RenderWidgetHost*) override {
    Invalidate();
    input_.Reset();
    widget_.Reset();
  }
  void WebContentsDestroyed() override {
    Invalidate();
    input_.Reset();
    widget_.Reset();
    Observe(nullptr);
  }
  NativeEscapeEvents events_;
  __weak PCNativeBrowserWindow* binding_ = nil;
  __weak PCNativePage* page_ = nil;
  __weak NSWindow* window_ = nil;
  base::WeakPtr<BrowserWindowInterface> browser_;
  content::WeakDocumentPtr document_, focused_document_;
  blink::DOMNodeIdType node_{};
  NSArray* notifications_;
  base::ScopedObservation<content::RenderWidgetHost,
                          content::RenderWidgetHost::InputEventObserver>
      input_{this};
  base::ScopedObservation<content::RenderWidgetHost,
                          content::RenderWidgetHostObserver>
      widget_{this};
  base::CallbackListSubscription focus_subscription_;
  base::WeakPtrFactory<EscapeRouter> weak_factory_{this};
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};
WEB_CONTENTS_USER_DATA_KEY_IMPL(EscapeRouter);

class ShortcutRouter final : public content::WebContentsObserver,
                             public content::WebContentsUserData<ShortcutRouter>,
                             public content::RenderWidgetHost::InputEventObserver,
                             public content::RenderWidgetHostObserver {
 public:
  static bool CanUseWindowUndo(PCNativePage* page) {
    auto* contents = ContentsForNativePage(page);
    auto* browser = contents ? GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents) : nullptr;
    if (!browser || contents->IsFocusedElementEditable()) return false;
    // Window Undo is a reserved editing route, not a registered priority
    // shortcut. Keep its existing keyboard-lock refusal separate from Ready.
    auto* exclusive = ExclusiveAccessManager::From(browser);
    if (exclusive &&
        exclusive->keyboard_lock_controller()->IsKeyboardLockActive()) return false;
    ShortcutRouter::CreateForWebContents(contents);
    return ShortcutRouter::FromWebContents(contents)->Ready(*browser,
        AppKitBindingForBrowser(browser), page, contents->GetFocusedFrame());
  }
  static bool ConsumeHint(PCNativePage* page, PCNativeShortcutCommand* command) {
    auto* contents = ContentsForNativePage(page);
    auto* router = contents ? ShortcutRouter::FromWebContents(contents) : nullptr;
    if (!router || !router->queued_ || router->command_ != command ||
        router->page_ != page || !router->Current()) return false;
    // Consume the original cue before Settings takes focus. This never invokes
    // the menu command and a stale accessory cannot dismiss a replacement cue.
    router->Clear();
    return true;
  }
  ~ShortcutRouter() override {
    Clear();
    input_.Reset(); widget_.Reset();
    for (id token in notification_tokens_)
      [[NSNotificationCenter defaultCenter] removeObserver:token];
  }
  Result Pre(BrowserWindowInterface& browser,
             const input::NativeWebKeyboardEvent& event) {
    NSEvent* native = event.os_event.Get();
    if (event.GetType() != blink::WebInputEvent::Type::kRawKeyDown)
      return Result::NOT_HANDLED;
    auto* contents = web_contents();
    PCNativeBrowserWindow* binding = AppKitBindingForBrowser(&browser);
    PCNativePage* page = ExistingNativePage(contents);
    auto* frame = contents->GetFocusedFrame();
    if (!native || event.skip_if_unhandled || !Ready(browser, binding, page, frame) ||
        ![binding.client respondsToSelector:@selector(nativeBrowser:shortcutForEvent:page:editable:)]) {
      Clear(); return Result::NOT_HANDLED;
    }
    // Snapshot the actual native menu item after current menu validation.
    PCNativeShortcutCommand* command = [binding.client nativeBrowser:binding
        shortcutForEvent:native page:page editable:contents->IsFocusedElementEditable()];
    if (!command || !command.item || native.isARepeat) {
      Clear(); return Result::NOT_HANDLED;
    }
    bool repeat = queued_ && Current() && Same(command, command_) &&
                  native.keyCode == native_.keyCode &&
                  native.modifierFlags == native_.modifierFlags;
    Clear();
    binding_ = binding; page_ = page; window_ = binding.window;
    browser_ = browser.GetWeakPtr();
    document_ = contents->GetPrimaryMainFrame()->GetWeakDocumentPtr();
    focused_document_ = frame->GetWeakDocumentPtr();
    node_ = frame->GetFocusedDOMNodeId();
    editable_ = contents->IsFocusedElementEditable();
    command_ = command; native_ = native; timestamp_ = event.TimeStamp();
    native_timestamp_ = native.timestamp;
    native_key_ = native.keyCode; native_flags_ = native.modifierFlags;
    has_native_event_ = true;
    key_ = event.native_key_code;
    if (!Current()) { Clear(); return Result::NOT_HANDLED; }
    BindWidget(frame->GetRenderWidgetHost());
    if (command.priority == PCNativeShortcutPriorityPreferParc || repeat) {
      // Consume the queue before invoking the real target. Reentrancy cannot
      // execute it twice or authorize a newly selected page.
      const bool handled = Dispatch();
      return handled ? Result::HANDLED : Result::NOT_HANDLED;
    }
    pending_ = true;
    return Result::NOT_HANDLED;
  }
  std::optional<bool> Unhandled(NSEvent* event) {
    if (event.type != NSEventTypeKeyDown) return std::nullopt;
    if (!MatchesNative(event)) {
      // An earlier queued renderer event may arrive after a later keydown.
      // Never replay a registered command against the current menu. Unknown
      // native editing/system keys retain the ordinary fallback.
      auto* contents = web_contents();
      auto* browser = contents ? GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents) : nullptr;
      auto* binding = browser ? AppKitBindingForBrowser(browser) : nil;
      auto* page = ExistingNativePage(contents);
      auto* frame = contents ? contents->GetFocusedFrame() : nullptr;
      if (!browser || !Ready(*browser, binding, page, frame)) return false;
      if ([binding.client respondsToSelector:@selector(nativeBrowser:shortcutForEvent:page:editable:)] &&
          [binding.client nativeBrowser:binding shortcutForEvent:event page:page
              editable:contents->IsFocusedElementEditable()]) return false;
      return std::nullopt;
    }
    // An event whose original owner or binding changed must not fall through
    // to the application's now-current menu target.
    if (!pending_ || !Current()) { Clear(); return false; }
    return Dispatch();
  }
 private:
  friend class content::WebContentsUserData<ShortcutRouter>;
  explicit ShortcutRouter(content::WebContents* contents)
      : content::WebContentsObserver(contents),
        content::WebContentsUserData<ShortcutRouter>(*contents) {
    auto weak = weak_factory_.GetWeakPtr();
    focus_subscription_ = SubscribeFrameFocus(*contents, base::BindRepeating(
        &ShortcutRouter::Clear, weak));
    NSMutableArray* tokens = [NSMutableArray array];
    for (NSString* name in @[NSWindowDidResignKeyNotification,
                            NSWindowWillCloseNotification,
                            NSApplicationDidResignActiveNotification,
                            kBindingsChanged]) {
      id token = [[NSNotificationCenter defaultCenter] addObserverForName:name
          object:nil queue:nil usingBlock:^(NSNotification* note) {
            if (weak && ([note.name isEqualToString:kBindingsChanged] ||
                [note.name isEqualToString:NSApplicationDidResignActiveNotification] ||
                note.object == weak->window_)) weak->Clear();
          }];
      [tokens addObject:token];
    }
    notification_tokens_ = [tokens copy];
  }
  static bool Same(PCNativeShortcutCommand* a, PCNativeShortcutCommand* b) {
    return a && b && a.item && a.item == b.item && a.revision == b.revision &&
           a.priority == b.priority;
  }
  bool Ready(BrowserWindowInterface& browser, PCNativeBrowserWindow* binding,
             PCNativePage* page, content::RenderFrameHost* frame) const {
    auto* contents = web_contents();
    NSWindow* window = binding.window;
    NSView* responder = [window.firstResponder isKindOfClass:[NSView class]]
                           ? (NSView*)window.firstResponder : nil;
    if ([responder respondsToSelector:@selector(hasMarkedText)] &&
        [(id<NSTextInputClient>)responder hasMarkedText]) return false;
    return contents && !contents->IsBeingDestroyed() && page && !page.closed &&
        frame && frame->IsActive() && !browser.IsDeleteScheduled() &&
        GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents) == &browser &&
        browser.GetTabStripModel()->GetActiveWebContents() == contents &&
        AppKitBrowserAcceptsNewPages(browser) && binding.client &&
        [binding.client selectedNativePage] == page && NSApp.active && window.keyWindow &&
        window.visible && !window.miniaturized && !window.attachedSheet &&
        !PCNativeWindowHasSecurityReservation(window) &&
        page.nativeView.window == window && !page.nativeView.hiddenOrHasHiddenAncestor &&
        responder && (responder == page.nativeView || [responder isDescendantOf:page.nativeView]) &&
        contents->GetVisibility() == content::Visibility::VISIBLE &&
        !contents->IsShowingContextMenu();
  }
  bool Current() const {
    auto* contents = web_contents();
    auto* frame = focused_document_.AsRenderFrameHostIfValid();
    return contents && browser_ && binding_ && page_ && window_ &&
        Ready(*browser_, binding_, page_, frame) &&
        AppKitBindingForBrowser(browser_.get()) == binding_ &&
        document_.AsRenderFrameHostIfValid() == contents->GetPrimaryMainFrame() &&
        contents->GetFocusedFrame() == frame && frame->GetFocusedDOMNodeId() == node_ &&
        contents->IsFocusedElementEditable() == editable_ &&
        command_ && command_.item;
  }
  bool MatchesNative(NSEvent* event) const {
    return has_native_event_ && event.timestamp == native_timestamp_ &&
        event.keyCode == native_key_ && event.modifierFlags == native_flags_;
  }
  void BindWidget(content::RenderWidgetHost* widget) {
    if (widget_.GetSource() == widget) return;
    input_.Reset(); widget_.Reset();
    if (widget) { widget_.Observe(widget); input_.Observe(widget); }
  }
  bool Dispatch() {
    if (!Current()) { Clear(); return false; }
    PCNativeBrowserWindow* binding = binding_;
    PCNativePage* page = page_;
    PCNativeShortcutCommand* command = command_;
    NSEvent* event = native_;
    if (![binding.client respondsToSelector:@selector(nativeBrowser:performShortcut:event:page:editable:)]) {
      Clear(); return false;
    }
    const bool editable = editable_;
    Clear();
    return [binding.client nativeBrowser:binding performShortcut:command
          event:event page:page editable:editable];
  }
  void Clear() {
    const bool had_hint = queued_;
    PCNativeShortcutCommand* command = command_;
    PCNativeBrowserWindow* binding = binding_;
    PCNativePage* page = page_;
    queued_ = false; pending_ = false; timer_.Stop();
    command_ = nil; native_ = nil; binding_ = nil; page_ = nil; browser_.reset();
    // Keep only the last physical event as a rejection tombstone. A delayed
    // unhandled callback after focus/navigation cannot hit a new menu target.
    if (had_hint && [binding.client respondsToSelector:@selector(nativeBrowser:dismissShortcutHint:page:)])
      [binding.client nativeBrowser:binding dismissShortcutHint:command page:page];
    else if (had_hint && [binding.client respondsToSelector:@selector(nativeBrowser:showShortcutHint:page:)])
      [binding.client nativeBrowser:binding showShortcutHint:nil page:page];
  }
  void CueTimerTick() {
    if (!queued_ || !Current()) { Clear(); return; }
    PCNativeShortcutCommand* command = command_;
    const bool hovered = [binding_.client respondsToSelector:@selector(nativeBrowser:isShortcutHintHovered:page:)] &&
        [binding_.client nativeBrowser:binding_ isShortcutHintHovered:command page:page_];
    // The synchronous client may reenter. An old tick never clears a new cue.
    if (command_ == command && queued_ && (!hovered || !Current())) Clear();
  }
  void OnInputEvent(const content::RenderWidgetHost&,
                    const blink::WebInputEvent& event, InputEventSource) override {
    if (event.GetType() == blink::WebInputEvent::Type::kMouseDown ||
        event.GetType() == blink::WebInputEvent::Type::kMouseWheel ||
        event.GetType() == blink::WebInputEvent::Type::kTouchStart ||
        event.GetType() == blink::WebInputEvent::Type::kGestureTapDown) Clear();
  }
  void OnInputEventAck(const content::RenderWidgetHost& host,
      blink::mojom::InputEventResultSource source,
      blink::mojom::InputEventResultState state,
      const blink::WebInputEvent& event) override {
    if (!pending_ || &host != widget_.GetSource() ||
        event.GetType() != blink::WebInputEvent::Type::kRawKeyDown ||
        event.TimeStamp() != timestamp_ ||
        static_cast<const blink::WebKeyboardEvent&>(event).native_key_code != key_) return;
    if (state != blink::mojom::InputEventResultState::kConsumed) return;
    pending_ = false;
    if (source != blink::mojom::InputEventResultSource::kMainThread || !Current() ||
        command_.priority != PCNativeShortcutPriorityUseBoth) { Clear(); return; }
    PCNativeShortcutCommand* current = [binding_.client nativeBrowser:binding_
        shortcutForEvent:native_ page:page_ editable:editable_];
    if (!Same(current, command_) || !Current()) { Clear(); return; }
    queued_ = true;
    const bool shown = [binding_.client respondsToSelector:@selector(nativeBrowser:showShortcutHint:page:)] &&
        [binding_.client nativeBrowser:binding_ showShortcutHint:command_ page:page_];
    if (!shown || !queued_ || !Current()) { Clear(); return; }
    timer_.Start(FROM_HERE, kRepeatCueLifetime, this, &ShortcutRouter::CueTimerTick);
  }
  void OnFocusChangedInPage(const content::FocusedNodeDetails&) override { Clear(); }
  void OnWebContentsLostFocus(content::RenderWidgetHost*) override { Clear(); }
  void DidStartNavigation(content::NavigationHandle*) override { Clear(); }
  void PrimaryPageChanged(content::Page&) override { Clear(); }
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (visibility != content::Visibility::VISIBLE) Clear();
  }
  void RenderWidgetHostDestroyed(content::RenderWidgetHost*) override {
    Clear(); input_.Reset(); widget_.Reset();
  }
  void WebContentsDestroyed() override {
    Clear(); input_.Reset(); widget_.Reset(); Observe(nullptr);
  }
  __weak PCNativeBrowserWindow* binding_ = nil;
  __weak PCNativePage* page_ = nil;
  __weak NSWindow* window_ = nil;
  base::WeakPtr<BrowserWindowInterface> browser_;
  content::WeakDocumentPtr document_, focused_document_;
  blink::DOMNodeIdType node_{};
  PCNativeShortcutCommand* command_ = nil;
  NSEvent* native_ = nil;
  NSArray* notification_tokens_;
  base::TimeTicks timestamp_;
  int key_ = 0;
  NSTimeInterval native_timestamp_ = 0;
  unsigned short native_key_ = 0;
  NSEventModifierFlags native_flags_ = 0;
  bool has_native_event_ = false;
  bool pending_ = false, queued_ = false, editable_ = false;
  base::RepeatingTimer timer_;
  base::ScopedObservation<content::RenderWidgetHost, content::RenderWidgetHost::InputEventObserver> input_{this};
  base::ScopedObservation<content::RenderWidgetHost, content::RenderWidgetHostObserver> widget_{this};
  base::CallbackListSubscription focus_subscription_;
  base::WeakPtrFactory<ShortcutRouter> weak_factory_{this};
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};
WEB_CONTENTS_USER_DATA_KEY_IMPL(ShortcutRouter);
}  // namespace
content::KeyboardEventProcessingResult PreHandleNativeShortcut(
    BrowserWindowInterface& browser, const input::NativeWebKeyboardEvent& event) {
  auto* contents = browser.GetTabStripModel()->GetActiveWebContents();
  PCNativeBrowserWindow* binding = AppKitBindingForBrowser(&browser);
  if (contents && ExistingNativePage(contents)) {
    EscapeRouter::CreateForWebContents(contents);
    EscapeRouter::FromWebContents(contents)->Pre(browser, event);
  }
  if (!contents || !ExistingNativePage(contents) ||
      ![binding.client respondsToSelector:@selector(nativeBrowser:shortcutForEvent:page:editable:)])
    return Result::NOT_HANDLED;
  ShortcutRouter::CreateForWebContents(contents);
  return ShortcutRouter::FromWebContents(contents)->Pre(browser, event);
}
std::optional<bool> HandleUnhandledNativeShortcut(content::WebContents& contents,
                                                 NSEvent* event) {
  auto* escape = EscapeRouter::FromWebContents(&contents);
  if (escape && escape->OwnsUnhandled(event)) return true;
  auto* router = ShortcutRouter::FromWebContents(&contents);
  return router ? router->Unhandled(event) : std::nullopt;
}
bool ConsumeNativeShortcutHint(PCNativePage* page, PCNativeShortcutCommand* command) {
  return ShortcutRouter::ConsumeHint(page, command);
}
bool CanUseNativeWindowUndo(PCNativePage* page) {
  return ShortcutRouter::CanUseWindowUndo(page);
}
}  // namespace parc

@implementation PCNativePage (ShortcutHint)
- (BOOL)consumeShortcutHint:(PCNativeShortcutCommand*)command {
  return parc::ConsumeNativeShortcutHint(self, command);
}
@end

@implementation PCNativePage (WindowUndo)
- (BOOL)canUseWindowUndo {
  return parc::CanUseNativeWindowUndo(self);
}
@end

@implementation PCNativeBrowserApplication (WindowUndo)
+ (BOOL)canUseWindowUndoInWindow:(NSWindow*)window {
  return window && window.visible && window.keyWindow && !window.miniaturized &&
      NSApp.active && !window.attachedSheet &&
      !PCNativeWindowHasSecurityReservation(window);
}
@end
