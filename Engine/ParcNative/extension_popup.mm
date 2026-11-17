// Copyright 2026 Parc contributors.
#include "extension_popup.h"

#include <atomic>
#include <cstdio>
#include <optional>

#include "base/check.h"
#include "base/command_line.h"
#include "base/functional/bind.h"
#include "base/message_loop/message_pump_apple.h"
#include "base/task/sequenced_task_runner.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/extensions/extension_view.h"
#include "chrome/browser/extensions/extension_view_host.h"
#include "components/input/native_web_keyboard_event.h"
#include "components/javascript_dialogs/app_modal_dialog_queue.h"
#include "components/web_modal/web_modal_utils.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "native_auxiliary_page.h"
#import "page_host.h"
#import "window_security_reservation.h"

@interface PCExtensionPageObserver : NSObject <PCNativePageHostObserver>
@property(copy) void (^detached)(void);
@end
@implementation PCExtensionPageObserver
@synthesize detached = _detached;
- (void)pageHost:(PCNativePageHost*)host didMoveToWindow:(NSWindow*)window {
  if (!window && _detached) {
    _detached();
  }
}
- (void)pageHostDidAttemptDeferredFocus:(PCNativePageHost*)host {
}
@end

namespace parc {
namespace {
bool PopupDiagnosticsEnabled() {
  if (!base::CommandLine::InitializedForCurrentProcess()) {
    return false;
  }
  const auto* command = base::CommandLine::ForCurrentProcess();
  return command->HasSwitch("parc-diagnostics") ||
         command->HasSwitch("parc-smoke") ||
         command->HasSwitch("parc-native-runtime-controller-tests");
}
std::atomic<uint64_t> next_diagnostic_session{0};
}

class NativeExtensionPopup::Operation {
 public:
  explicit Operation(NativeExtensionPopup& owner, bool external = false)
      : owner_(owner), previous_deferred_(owner.deferred_close_) {
    ++owner_.engine_calls_;
    if (external) {
      owner_.deferred_close_ = true;
    }
  }
  ~Operation() {
    --owner_.engine_calls_;
    if (!owner_.closing_) {
      owner_.deferred_close_ = previous_deferred_;
    }
    owner_.MaybeFinalizeClose();
  }

 private:
  NativeExtensionPopup& owner_;
  bool previous_deferred_;
};
class NativeExtensionPopup::View final : public extensions::ExtensionView {
 public:
  View(std::weak_ptr<NativeExtensionPopup> owner,
       content::WebContents& contents)
      : owner_(std::move(owner)), contents_(&contents) {
    native_ = contents.GetNativeView().GetNativeNSView();
    CHECK(native_);
    observer_ = [[PCExtensionPageObserver alloc] init];
    std::weak_ptr<NativeExtensionPopup> weak = owner_;
    observer_.detached = ^{
      if (auto popup = weak.lock()) {
        popup->RequestHide("page-detached");
      }
    };
    CHECK(![native_.superview isMemberOfClass:PCNativePageHost.class]);
    page_ = [PCNativePageHost hostWithContentView:native_ observer:observer_];
  }
  ~View() override {
    observer_.detached = nil;
    [page_ invalidate];
  }
  PCNativePageHost* page() const { return page_; }
  void HostWillClose() { contents_ = nullptr; }
  void BindPage(NSWindow* owner, base::RepeatingCallback<bool()> valid) {
    if (contents_ && !lease_) {
      lease_ = NativeExtensionPage::Bind(*contents_, page_, owner,
                                         std::move(valid));
    }
  }
  void RevokePage() {
    if (auto lease = std::move(lease_)) {
      lease->Revoke();
    }
  }
  gfx::NativeView GetNativeView() override { return gfx::NativeView(native_); }
  void ResizeDueToAutoResize(content::WebContents* source,
                             const gfx::Size& size) override {
    if (!contents_ || source != contents_) {
      return;
    }
    if (auto owner = owner_.lock()) {
      std::weak_ptr<NativeExtensionPopup> weak = owner;
      base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE,
          base::BindOnce(
              [](std::weak_ptr<NativeExtensionPopup> weak, gfx::Size size) {
                if (auto self = weak.lock()) {
                  self->Resize(size);
                }
              },
              weak, size));
    }
  }
  void RenderFrameCreated(content::RenderFrameHost* frame) override {
    if (!frame || frame->GetParent()) {
      return;
    }
    if (auto owner = owner_.lock(); owner && !owner->closing_) {
      Operation call(*owner, true);
      owner->Trace("frame-created", "auto-resize-entry");
      if (owner->diagnostic_id_) {
        const auto token = frame->GetGlobalFrameToken();
        std::fprintf(stderr,
                     "PARC_POPUP_FRAME session=%llu process=%d token=%s\n",
                     static_cast<unsigned long long>(owner->diagnostic_id_),
                     token.child_id, token.frame_token.ToString().c_str());
      }
      if (auto* view = frame->GetView()) {
        view->EnableAutoResize(extensions::kExtensionPopupMinSize,
                               extensions::kExtensionPopupMaxSize);
      }
    }
  }
  bool HandleKeyboardEvent(
      content::WebContents* source,
      const input::NativeWebKeyboardEvent& event) override {
    if (!contents_ || source != contents_ || event.skip_if_unhandled) {
      return false;
    }
    auto owner = owner_.lock();
    if (!owner || owner->closing_ || owner->hide_queued_) {
      return false;
    }
    Operation call(*owner, true);
    return owner->callbacks_.menu_key.Run(source, event);
  }
  void OnLoaded() override {
    if (auto owner = owner_.lock()) {
      owner->Trace("load-callback", "did-stop-first-load");
    }
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(
                       [](std::weak_ptr<NativeExtensionPopup> weak) {
                         if (auto self = weak.lock()) {
                           self->Loaded();
                         }
                       },
                       owner_));
  }

 private:
  std::weak_ptr<NativeExtensionPopup> owner_;
  content::WebContents* contents_;
  NSView* __strong native_ = nil;
  PCNativePageHost* __strong page_ = nil;
  PCExtensionPageObserver* __strong observer_ = nil;
  std::shared_ptr<NativeExtensionPage> lease_;
};

class NativeExtensionPopup::PaintObserver final
    : public content::WebContentsObserver {
 public:
  PaintObserver(content::WebContents& contents,
                std::weak_ptr<NativeExtensionPopup> owner)
      : content::WebContentsObserver(&contents), owner_(std::move(owner)) {}
  void DidFirstVisuallyNonEmptyPaint() override {
    if (auto owner = owner_.lock(); owner && !owner->closing_) {
      [owner->presenter_ contentDidPaint];
    }
  }

 private:
  std::weak_ptr<NativeExtensionPopup> owner_;
};

NativeExtensionPopup::NativeExtensionPopup(
    std::unique_ptr<extensions::ExtensionViewHost> host,
    NSWindow* parent,
    PopupShowAction action,
    ShowPopupCallback callback,
    Callbacks callbacks)
    : host_(std::move(host)),
      parent_(parent),
      action_(action),
      callback_(std::move(callback)),
      callbacks_(std::move(callbacks)) {
  CHECK(host_);
  if (PopupDiagnosticsEnabled()) {
    diagnostic_id_ = next_diagnostic_session.fetch_add(1) + 1;
    diagnostic_extension_id_ = host_->extension_id();
    Trace("constructed", "real-extension-host");
  }
  CHECK(callbacks_.anchor && callbacks_.security_ui_visible &&
        callbacks_.menu_key && callbacks_.inspect && callbacks_.request_hide &&
        callbacks_.closed);
}
NativeExtensionPopup::~NativeExtensionPopup() {
  CHECK(closing_);
  CHECK(!host_);
  Trace("destroyed", "session-release");
}
void NativeExtensionPopup::Trace(const char* phase, const char* reason) const {
  if (!diagnostic_id_) {
    return;
  }
  std::fprintf(stderr,
               "PARC_POPUP session=%llu extension=%s phase=%s reason=%s "
               "started=%d closing=%d hide=%d shown=%d calls=%d "
               "host=%d deferred=%d\n",
               static_cast<unsigned long long>(diagnostic_id_),
               diagnostic_extension_id_.c_str(), phase, reason, started_,
               closing_, hide_queued_, shown_, engine_calls_, !!host_,
               deferred_close_);
}
bool NativeExtensionPopup::Start() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto alive = shared_from_this();
  Trace("start", "entry");
  if (started_ || closing_ || hide_queued_) {
    return false;
  }
  started_ = true;
  Operation call(*this);
  if (!parent_ || callbacks_.security_ui_visible.Run() || closing_ ||
      hide_queued_ || !host_->host_contents()->GetNativeView() ||
      host_->view()) {
    Trace("start-refused", "parent-security-view-or-terminal");
    Close();
    return false;
  }
  NSView* native = host_->host_contents()->GetNativeView().GetNativeNSView();
  if (native.window ||
      [native.superview isMemberOfClass:PCNativePageHost.class]) {
    Trace("start-refused", "native-view-already-owned");
    Close();
    return false;
  }
  std::weak_ptr<NativeExtensionPopup> weak = alive;
  host_->SetCloseHandler(base::BindOnce(
      [](std::weak_ptr<NativeExtensionPopup> weak, extensions::ExtensionHost*) {
        if (auto self = weak.lock()) {
          self->Trace("close-request", "extension-host-close");
          self->Close();
        }
      },
      weak));
  view_ = std::make_unique<View>(weak, *host_->host_contents());
  host_->set_view(view_.get());
  paint_observer_ =
      std::make_unique<PaintObserver>(*host_->host_contents(), weak);
  presenter_ = [[PCExtensionPopupPresenter alloc] initWithParentWindow:parent_
      pageHost:view_->page()
      anchor:^{
        auto self = weak.lock();
        return self && !self->closing_ ? self->callbacks_.anchor.Run() : nil;
      }
      mayDismissForParentKey:^{
        auto self = weak.lock();
        return self && !self->closing_ && self->MayDismissForParentKey();
      }
      onDismiss:^{
        if (auto self = weak.lock()) {
          self->RequestHide("presenter-dismiss");
        }
      }];
  presenter_.extensionIdentifier = @(host_->extension_id().c_str());
  if (![presenter_ prepare] || closing_ || hide_queued_) {
    Trace("start-refused", "prepare-or-terminal");
    Close();
    return false;
  }
  Trace("prepared", "visible-before-show");
  view_->RenderFrameCreated(host_->host_contents()->GetPrimaryMainFrame());
  if (closing_ || hide_queued_ || !host_) {
    return false;
  }
  if (host_->has_loaded_once()) {
    Trace("renderer", "already-loaded");
    Loaded();
  } else {
    Trace("renderer", "create-soon");
    host_->CreateRendererSoon();
  }
  Trace("start-return", "after-renderer-request");
  return !closing_;
}
void NativeExtensionPopup::Loaded() {
  auto alive = shared_from_this();
  Trace("loaded", "posted-delivery");
  if (closing_ || hide_queued_ || shown_) {
    return;
  }
  Operation call(*this);
  if (callbacks_.security_ui_visible.Run() || closing_) {
    Trace("show-refused", "security-or-terminal");
    Close();
    return;
  }
  if (![presenter_ show] || closing_ || hide_queued_) {
    Trace("show-refused", "presenter-or-terminal");
    Close();
    return;
  }
  shown_ = true;
  Trace("shown", "presenter-visible");
  view_->BindPage(
      parent_,
      base::BindRepeating(
          [](std::weak_ptr<NativeExtensionPopup> weak) {
            auto self = weak.lock();
            return self && !self->closing_ && !self->hide_queued_ &&
                   self->shown_ && self->host_ &&
                   self->presenter_.presenting &&
                   !self->callbacks_.security_ui_visible.Run();
          },
          std::weak_ptr<NativeExtensionPopup>(alive)));
  host_->host_contents()->WasShown();
  if (closing_ || hide_queued_ || !host_) {
    return;
  }
  if (host_->host_contents()->CompletedFirstVisuallyNonEmptyPaint()) {
    [presenter_ contentDidPaint];
  }
  if (callbacks_.security_ui_visible.Run() || closing_ || hide_queued_) {
    RequestHide("security-after-show");
    return;
  }
  host_->host_contents()->Focus();
  if (closing_ || hide_queued_) {
    return;
  }
  if (callbacks_.security_ui_visible.Run() || closing_ || hide_queued_) {
    RequestHide("security-after-focus");
    return;
  }
  if (action_ == PopupShowAction::kShowAndInspect &&
      !callbacks_.inspect.Run(host_->host_contents())) {
    Close();
    return;
  }
  if (!closing_ && !hide_queued_) {
    FinishCallback(host_.get());
  }
}
void NativeExtensionPopup::Resize(const gfx::Size& requested) {
  auto alive = shared_from_this();
  if (closing_ || hide_queued_) {
    return;
  }
  Operation call(*this);
  gfx::Size size = requested;
  size.SetToMax(extensions::kExtensionPopupMinSize);
  size.SetToMin(extensions::kExtensionPopupMaxSize);
  content::WebContents* contents = host_->host_contents();
  std::optional<SkColor> backdrop = contents->GetBackgroundColor();
  if (auto* view = contents->GetRenderWidgetHostView();
      view && (!backdrop || !SkColorGetA(*backdrop))) {
    backdrop = view->GetBackgroundColor();
  }
  presenter_.backdropColor =
      backdrop && SkColorGetA(*backdrop)
          ? [NSColor colorWithSRGBRed:SkColorGetR(*backdrop) / 255.0
                                green:SkColorGetG(*backdrop) / 255.0
                                 blue:SkColorGetB(*backdrop) / 255.0
                                alpha:SkColorGetA(*backdrop) / 255.0]
          : nil;
  [presenter_ resizeContent:NSMakeSize(size.width(), size.height())];
}
void NativeExtensionPopup::RequestHide(const char* reason) {
  auto alive = shared_from_this();
  Trace("hide-request", reason);
  if (closing_ || hide_queued_) {
    return;
  }
  hide_queued_ = true;
  if (view_) {
    view_->RevokePage();
  }
  std::weak_ptr<NativeExtensionPopup> weak = alive;
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](std::weak_ptr<NativeExtensionPopup> weak) {
                       if (auto self = weak.lock(); self && !self->closing_) {
                         self->callbacks_.request_hide.Run();
                       }
                     },
                     weak));
}
bool NativeExtensionPopup::MayDismissForParentKey() {
  auto alive = shared_from_this();
  if (closing_) {
    return false;
  }
  if (callbacks_.security_ui_visible.Run()) {
    RequestHide("parent-key-security");
    return false;
  }
  if (closing_) {
    return false;
  }
  NSWindow* popup = presenter_.popupWindow;
  return !javascript_dialogs::AppModalDialogQueue::GetInstance()
              ->HasActiveDialog() &&
         !web_modal::WebContentsHasActiveWebModal(host_->host_contents()) &&
         !DevToolsWindow::GetInstanceForInspectedWebContents(
             host_->host_contents()) &&
         !popup.attachedSheet && !PCNativeWindowHasSecurityReservation(popup);
}
void NativeExtensionPopup::SecurityUIChanged() {
  auto alive = shared_from_this();
  if (!closing_ && callbacks_.security_ui_visible.Run()) {
    RequestHide("security-state-change");
  } else if (fading_ && callbacks_.security_ui_visible.Run()) {
    FinishFade();
  }
}
void NativeExtensionPopup::FinishCallback(extensions::ExtensionHost* result) {
  Trace("show-result", result ? "shown-host" : "cancelled");
  if (callback_) {
    std::move(callback_).Run(result);
  }
}
void NativeExtensionPopup::Close(base::OnceClosure completion) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto alive = shared_from_this();
  if (close_complete_) {
    if (completion) {
      base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE, std::move(completion));
    }
    return;
  }
  if (completion) {
    close_completions_.push_back(std::move(completion));
  }
  BeginClose(false);
}
void NativeExtensionPopup::Close() {
  BeginClose(true);
}
void NativeExtensionPopup::BeginClose(bool animate) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto alive = shared_from_this();
  Trace("close", "entry");
  if (closing_ && engine_calls_ == 0 &&
      !base::message_pump_apple::IsHandlingSendEvent()) {
    deferred_close_ = false;
  }
  if (!closing_) {
    closing_ = true;
    callbacks_.request_hide.Reset();
    if (view_) {
      view_->RevokePage();
    }
    if (animate && MayFadeOut()) {
      fading_ = true;
      if (![presenter_ dismissWithMotion:^{
            if (alive->fading_) {
              alive->fading_ = false;
              alive->deferred_close_ = true;
              alive->MaybeFinalizeClose();
            }
          }]) {
        fading_ = false;
      }
    }
  }
  if (fading_ && !animate) {
    FinishFade();
    return;
  }
  if (!fading_) {
    [presenter_ invalidate];
  }
  MaybeFinalizeClose();
}
bool NativeExtensionPopup::MayFadeOut() {
  NSWindow* popup = presenter_.popupWindow;
  return shown_ && host_ && host_->extension() && popup &&
         !callbacks_.security_ui_visible.Run() &&
         !PCNativeWindowHasSecurityReservation(popup);
}
void NativeExtensionPopup::FinishFade() {
  auto alive = shared_from_this();
  fading_ = false;
  [presenter_ invalidate];
  MaybeFinalizeClose();
}
void NativeExtensionPopup::MaybeFinalizeClose() {
  if (!closing_ || !host_ || engine_calls_ != 0 || fading_) {
    return;
  }
  if (deferred_close_ || base::message_pump_apple::IsHandlingSendEvent()) {
    if (diagnostic_id_ && !diagnostic_deferred_logged_) {
      diagnostic_deferred_logged_ = true;
      Trace("close-deferred", "native-event-or-engine-callback");
    }
    if (close_task_queued_) {
      return;
    }
    close_task_queued_ = true;
    auto self = shared_from_this();
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopDefaultMode, ^{
      self->deferred_close_ = false;
      self->close_task_queued_ = false;
      self->MaybeFinalizeClose();
    });
    CFRunLoopWakeUp(CFRunLoopGetMain());
    return;
  }
  FinalizeClose();
}
void NativeExtensionPopup::FinalizeClose() {
  auto alive = shared_from_this();
  CHECK(closing_ && engine_calls_ == 0);
  if (!host_) {
    return;
  }
  Trace("finalize", "before-host-destruction");
  if (view_) {
    view_->HostWillClose();
  }
  paint_observer_.reset();
  host_.reset();
  Trace("finalize", "after-host-destruction");
  presenter_ = nil;
  auto closed = std::move(callbacks_.closed);
  if (closed) {
    std::move(closed).Run();
  }
  FinishCallback(nullptr);
  close_complete_ = true;
  Trace("close-complete", "callbacks-returned");
  auto completions = std::move(close_completions_);
  for (auto& completion : completions) {
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, std::move(completion));
  }
}
bool NativeExtensionPopup::closing() const {
  return closing_;
}
extensions::ExtensionViewHost* NativeExtensionPopup::host() const {
  return closing_ ? nullptr : host_.get();
}
gfx::NativeView NativeExtensionPopup::native_view() const {
  return !closing_ && view_ ? view_->GetNativeView() : gfx::NativeView();
}
}
