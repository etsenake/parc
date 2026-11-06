// Copyright 2026 Parc contributors.
#include "native_fullscreen_window.h"

#import <objc/runtime.h>

#include <memory>
#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/functional/callback.h"
#include "base/notreached.h"
#include "base/task/single_thread_task_runner.h"
#include "components/remote_cocoa/app_shim/native_widget_ns_window_fullscreen_controller.h"
#include "ui/display/display.h"
#include "ui/display/screen.h"
#include "ui/display/types/display_constants.h"
#include "ui/gfx/mac/coordinate_conversion.h"
#include "ui/gfx/native_ui_types.h"

namespace parc {
class NativeFullscreenWindow;
}

@interface PCNativeFullscreenWindowOwner : NSObject {
 @public
  std::shared_ptr<parc::NativeFullscreenWindow> state;
}
- (void)receiveWindowNotification:(NSNotification*)notification;
@end

namespace parc {
NSNotificationName const kNativeFullscreenSettledNotification =
    @"PCNativeFullscreenSettledNotification";

//
// ownership model. This current-engine adapter supplies the Cocoa controller's
// Client directly; it creates no Views window, bridge process or second window.
class NativeFullscreenWindow final
    : public remote_cocoa::NativeWidgetNSWindowFullscreenController::Client,
      public std::enable_shared_from_this<NativeFullscreenWindow> {
 public:
  explicit NativeFullscreenWindow(NSWindow* window)
      : window_(window),
        original_frame_(window.frame),
        consumed_notifications_([NSHashTable
            hashTableWithOptions:NSPointerFunctionsWeakMemory |
                                 NSPointerFunctionsObjectPointerPersonality]),
        controller_(this) {}

  void Initialize() {
    // Attachment may happen after the shell's window is already fullscreen.
    // Seed the controller from that actual state without announcing a new
    // completion to Browsers that are still being registered.
    if (window_.styleMask & NSWindowStyleMaskFullScreen) {
      initializing_ = true;
      controller_.OnWindowWillEnterFullscreen();
      controller_.OnWindowDidEnterFullscreen();
      initializing_ = false;
    }
  }

  bool Request(bool enter, int64_t display_id) {
    auto keep_alive = shared_from_this();
    NSWindow* window = window_;
    if (closed_ || !window || window.attachedSheet) return false;
    if (enter && display_id != display::kInvalidDisplayId) {
      display::Display target;
      auto* screen = display::Screen::Get();
      if (!screen || !screen->GetDisplayWithDisplayId(display_id, &target))
        return false;
    }
    if (enter)
      controller_.EnterFullscreen(display_id);
    else
      controller_.ExitFullscreen();
    // A no-op request does not supersede a genuine queued completion or
    // manufacture an AppKit event. The existing engine handles nested modes.
    return !closed_;
  }

  bool transitioning() const {
    return !closed_ &&
           (controller_.IsInFullscreenTransition() || settlement_pending_);
  }
  NSRect restored_frame() const {
    return has_original_frame_ ? original_frame_ : window_.frame;
  }

  void Notification(NSNotification* notification) {
    auto keep_alive = shared_from_this();
    if (closed_ || [consumed_notifications_ containsObject:notification]) return;
    [consumed_notifications_ addObject:notification];
    if ([notification.name isEqualToString:NSWindowWillCloseNotification]) {
      closed_ = true;
      settlement_pending_ = false;
      ++settlement_revision_;
      controller_.OnWindowWillClose();
      // Do not delete the controller in a reentrant AppKit toggle stack. Its
      // remaining tasks cannot mutate a closed window; destruction cancels them.
    } else if ([notification.name
                   isEqualToString:NSWindowWillEnterFullScreenNotification]) {
      phase_ = Phase::kEntering;
      controller_.OnWindowWillEnterFullscreen();
    } else if ([notification.name
                   isEqualToString:NSWindowWillExitFullScreenNotification]) {
      phase_ = Phase::kExiting;
      controller_.OnWindowWillExitFullscreen();
    } else if ([notification.name
                   isEqualToString:NSWindowDidEnterFullScreenNotification]) {
      phase_ = Phase::kNone;
      controller_.OnWindowDidEnterFullscreen();
    } else if ([notification.name
                   isEqualToString:NSWindowDidExitFullScreenNotification]) {
      phase_ = Phase::kNone;
      controller_.OnWindowDidExitFullscreen();
    }
  }

  void FailedToEnter() {
    auto keep_alive = shared_from_this();
    NSWindow* window = window_;
    // Actual did-exit clears this phase if AppKit delivered it before the
    // failure callback. Do not gate on a newer *requested* target: a queued
    // exit must still receive completion of this actual failed entry.
    if (closed_ || !window || phase_ != Phase::kEntering) return;
    phase_ = Phase::kNone;
    controller_.OnWindowDidFailToEnterFullscreen(
        /*resume_pending_state=*/true);
  }

  bool IsCurrentSettlement(NSNotification* notification) const {
    return !closed_ && !transitioning() &&
           [notification.userInfo[@"revision"] unsignedLongLongValue] ==
               settlement_revision_;
  }

 private:
  enum class Phase { kNone, kEntering, kExiting };

  void FullscreenControllerTransitionStart(bool target_fullscreen) override {
    if (closed_) return;
    ++settlement_revision_;
    settlement_pending_ = false;
    if (target_fullscreen && !has_original_frame_) {
      original_frame_ = window_.frame;
      has_original_frame_ = true;
    }
  }

  void FullscreenControllerTransitionComplete(bool is_fullscreen) override {
    auto keep_alive = shared_from_this();
    if (closed_) return;
    if (!is_fullscreen) {
      has_original_frame_ = false;
    }
    if (!initializing_) QueueSettlement();
  }

  void QueueSettlement() {
    const uint64_t revision = ++settlement_revision_;
    settlement_pending_ = true;
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE,
        base::BindOnce(
            [](std::weak_ptr<NativeFullscreenWindow> weak, uint64_t revision) {
              auto state = weak.lock();
              if (!state || state->closed_ || !state->window_ ||
                  revision != state->settlement_revision_ ||
                  state->controller_.IsInFullscreenTransition()) return;
              state->settlement_pending_ = false;
              // Broadcast to every exact Profile association on this window.
              // Each receiver rechecks revision: a reentrant new transition
              // supersedes this settlement and will provide its own completion.
              [[NSNotificationCenter defaultCenter]
                  postNotificationName:kNativeFullscreenSettledNotification
                  object:state->window_
                  userInfo:@{@"revision" : @(revision)}];
            },
            weak_from_this(), revision));
  }

  void FullscreenControllerSetFrame(
      const gfx::Rect& frame,
      bool animate,
      base::OnceCallback<void()> completion) override {
    auto keep_alive = shared_from_this();
    NSWindow* window = window_;
    if (closed_ || !window) return;
    const NSRect native_frame = gfx::ScreenRectToNSRect(frame);
    const NSTimeInterval duration =
        animate ? [window animationResizeTime:native_frame] : 0;
    __block base::OnceCallback<void()> done = std::move(completion);
    std::weak_ptr<NativeFullscreenWindow> weak = weak_from_this();
    [NSAnimationContext
        runAnimationGroup:^(NSAnimationContext* context) {
          context.duration = duration;
          [[window animator] setFrame:native_frame display:YES animate:animate];
        }
        completionHandler:^{
          auto state = weak.lock();
          if (state && !state->closed_ && done) std::move(done).Run();
        }];
  }

  void FullscreenControllerToggleFullscreen() override {
    auto keep_alive = shared_from_this();
    NSWindow* window = window_;
    if (closed_ || !window) return;
    const bool was_key = window.isKeyWindow;
    // A failed native entry need not emit will-enter first. Pair its delegate
    // failure with the actual toggle being issued, not a later desired target.
    phase_ = (window.styleMask & NSWindowStyleMaskFullScreen)
                 ? Phase::kExiting : Phase::kEntering;
    [window toggleFullScreen:nil];
    // Match the pinned macOS focus repair only while entering; changing order
    // during exit would interfere with AppKit's real transition animation.
    if (!closed_ && was_key &&
        (window.styleMask & NSWindowStyleMaskFullScreen))
      [window makeKeyAndOrderFront:nil];
  }

  void FullscreenControllerCloseWindow() override {
    // Never arm OnWindowWantsToClose: Parc's existing coordinator obtains
    // beforeunload consent and owns actual close. This controller only moves.
    NOTREACHED();
  }

  int64_t FullscreenControllerGetDisplayId() const override {
    auto* screen = display::Screen::Get();
    return screen && window_ && !closed_
               ? screen->GetDisplayNearestWindow(gfx::NativeWindow(window_)).id()
               : display::kInvalidDisplayId;
  }

  gfx::Rect FullscreenControllerGetFrameForDisplay(int64_t id) const override {
    auto* screen = display::Screen::Get();
    if (!screen || !window_ || closed_) return gfx::Rect();
    display::Display target;
    if (!screen->GetDisplayWithDisplayId(id, &target)) {
      // A screen may disconnect after an accepted request but before the
      // controller's posted move. Continue on the actual remaining display;
      // an empty frame would strand the pinned controller in its moving state.
      target = screen->GetDisplayNearestWindow(gfx::NativeWindow(window_));
    }
    return gfx::Rect(target.work_area().origin(),
                     FullscreenControllerGetFrame().size());
  }

  gfx::Rect FullscreenControllerGetFrame() const override {
    return !closed_ && window_ ? gfx::ScreenRectFromNSRect(window_.frame)
                               : gfx::Rect();
  }

  __weak NSWindow* window_;
  NSRect original_frame_;
  NSHashTable<NSNotification*>* __strong consumed_notifications_;
  bool has_original_frame_ = false;
  bool closed_ = false;
  bool initializing_ = false;
  bool settlement_pending_ = false;
  uint64_t settlement_revision_ = 0;
  Phase phase_ = Phase::kNone;
  remote_cocoa::NativeWidgetNSWindowFullscreenController controller_;
};

namespace {
char kFullscreenOwner;
std::shared_ptr<NativeFullscreenWindow> State(NSWindow* window) {
  CHECK(NSThread.isMainThread);
  PCNativeFullscreenWindowOwner* owner =
      window ? objc_getAssociatedObject(window, &kFullscreenOwner) : nil;
  return owner ? owner->state : nullptr;
}
}  // namespace

void InstallNativeFullscreenWindow(NSWindow* window) {
  CHECK(NSThread.isMainThread);
  if (!window || State(window)) return;
  PCNativeFullscreenWindowOwner* owner =
      [[PCNativeFullscreenWindowOwner alloc] init];
  owner->state = std::make_shared<NativeFullscreenWindow>(window);
  objc_setAssociatedObject(window, &kFullscreenOwner, owner,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  owner->state->Initialize();
  // Keep actual native state even before the first Profile Browser attaches,
  // or between their lifetimes. Associations also feed these notifications
  // before forwarding; exact notification identity makes observer order safe.
  NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
  for (NSNotificationName name in @[
         NSWindowWillCloseNotification, NSWindowWillEnterFullScreenNotification,
         NSWindowDidEnterFullScreenNotification,
         NSWindowWillExitFullScreenNotification,
         NSWindowDidExitFullScreenNotification
       ]) {
    [center addObserver:owner selector:@selector(receiveWindowNotification:)
                   name:name object:window];
  }
}
bool HasNativeFullscreenWindow(NSWindow* window) { return !!State(window); }
bool RequestNativeFullscreen(NSWindow* window, bool enter, int64_t display_id) {
  auto state = State(window);
  return state && state->Request(enter, display_id);
}
bool NativeFullscreenTransitioning(NSWindow* window) {
  auto state = State(window);
  return state && state->transitioning();
}
NSRect NativeFullscreenRestoredFrame(NSWindow* window) {
  auto state = State(window);
  return state ? state->restored_frame() : window.frame;
}
void HandleNativeFullscreenNotification(NSNotification* notification) {
  auto state = State(notification.object);
  if (state) state->Notification(notification);
}
bool IsCurrentNativeFullscreenSettlement(NSNotification* notification) {
  auto state = State(notification.object);
  return state && state->IsCurrentSettlement(notification);
}
void NativeFullscreenFailedToEnter(NSWindow* window) {
  auto state = State(window);
  if (state) state->FailedToEnter();
}
}  // namespace parc

@implementation PCNativeFullscreenWindowOwner
- (void)dealloc {
  CHECK(NSThread.isMainThread);
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}
- (void)receiveWindowNotification:(NSNotification*)notification {
  CHECK(NSThread.isMainThread);
  auto current = state;
  if (current) current->Notification(notification);
}
@end
