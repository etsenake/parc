// Copyright 2026 Parc contributors.
#include "external_protocol.h"

#include <algorithm>
#include <memory>
#include <utility>
#include <vector>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/supports_user_data.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/external_protocol/native_external_protocol_dialog.h"
#include "chrome/browser/picture_in_picture/picture_in_picture_occlusion_tracker.h"
#include "chrome/browser/picture_in_picture/picture_in_picture_window_manager.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "components/tabs/public/tab_interface.h"
#include "components/url_formatter/elide_url.h"
#include "components/web_modal/single_web_contents_dialog_manager.h"
#include "components/web_modal/web_contents_modal_dialog_manager.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#import "external_protocol_presenter.h"
#include "ui/base/base_window.h"
#include "ui/events/event.h"
#include "ui/events/event_utils.h"
#include "ui/gfx/mac/coordinate_conversion.h"
#include "ui/views/input_event_activation_protector.h"
#import "window_security_reservation.h"

namespace parc {
namespace {
class Request;
constexpr char kPageState[] = "parc-native-external-protocol-page";
class PageState final : public base::SupportsUserData::Data {
 public:
  bool attached = false;
  uint64_t generation = 0;
  std::vector<std::weak_ptr<Request>> requests;
};
PageState* State(content::WebContents* contents) {
  return contents ? static_cast<PageState*>(contents->GetUserData(kPageState))
                  : nullptr;
}
class NativeModal final : public web_modal::SingleWebContentsDialogManager {
 public:
  explicit NativeModal(std::shared_ptr<Request> request);
  ~NativeModal() override;
  void Show() override;
  void Hide() override;
  void Close() override;
  void Focus() override;
  void Pulse() override;
  void HostChanged(web_modal::WebContentsModalDialogHost*) override;
  gfx::NativeWindow dialog() override;
  bool IsActive() const override;

 private:
  const std::shared_ptr<Request> request_;
};

class Request final : public content::WebContentsObserver,
                      public std::enable_shared_from_this<Request> {
 public:
  Request(content::WebContents& contents,
          std::unique_ptr<NativeExternalProtocolDialogRequest> decision)
      : content::WebContentsObserver(&contents),
        decision_(std::move(decision)),
        initiator_(decision_->initiator_document),
        generation_(State(&contents)->generation) {
    auto* tab = tabs::TabInterface::MaybeGetFromContents(&contents);
    auto* browser = tab ? tab->GetBrowserWindowInterface() : nullptr;
    if (browser && browser->GetWindow()) {
      browser_ = browser->GetWeakPtr();
      profile_ = browser->GetProfile()->GetWeakPtr();
      window_ = browser->GetWindow()->GetNativeWindow().GetNativeNSWindow();
      page_ = contents.GetNativeView().GetNativeNSView();
      document_ = contents.GetPrimaryMainFrame()->GetWeakDocumentPtr();
    }
  }
  ~Request() override {
    [presenter_ invalidate];
    [reservation_ invalidate];
    RemoveObservers();
  }
  bool Build() {
    auto keep = shared_from_this();
    auto* contents = web_contents();
    auto* manager =
        contents ? web_modal::WebContentsModalDialogManager::FromWebContents(
                       contents)
                 : nullptr;
    if (!Valid() || !manager || !manager->delegate() ||
        manager->IsDialogActive() ||
        PCNativeWindowHasSecurityReservation(window_)) {
      return false;
    }
    std::weak_ptr<Request> weak = keep;
    window_observer_ = [NSNotificationCenter.defaultCenter
        addObserverForName:NSWindowWillCloseNotification
                    object:window_
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (auto self = weak.lock()) {
                    self->CancelSoon();
                  }
                }];
    security_observer_ = [NSNotificationCenter.defaultCenter
        addObserverForName:PCNativeWindowSecurityStateChanged
                    object:window_
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (auto self = weak.lock(); self && !self->acquiring_ &&
                                               !self->finished_ &&
                                               !self->Valid()) {
                    self->CancelSoon();
                  }
                }];
    acquiring_ = true;
    auto* lease = [PCNativeWindowSecurityReservation acquireForWindow:window_];
    acquiring_ = false;
    if (finished_) {
      [lease invalidate];
      return false;
    }
    reservation_ = lease;
    if (!Valid()) {
      return false;
    }
    //
    // title quotes the requesting site and the destination application, the
    // informative text is empty and the buttons name the application. Without
    // an initiating origin or application name Chromium's own text remains.
    NSString* title = base::SysUTF16ToNSString(decision_->Title());
    NSString* message = base::SysUTF16ToNSString(decision_->Message());
    NSString* accept = base::SysUTF16ToNSString(decision_->AcceptLabel());
    NSString* program = base::SysUTF16ToNSString(decision_->program_name);
    //
    // offered only where Chromium may remember this origin's decision.
    NSString* always =
        !decision_->MayRemember() ? @""
        : program.length ? [NSString stringWithFormat:@"Always open “%@”", program]
                         : @"Always open";
    if (program.length && decision_->initiating_origin &&
        !decision_->initiating_origin->opaque()) {
      NSString* source =
          base::SysUTF16ToNSString(url_formatter::FormatOriginForSecurityDisplay(
              *decision_->initiating_origin,
              url_formatter::SchemeDisplay::OMIT_HTTP_AND_HTTPS));
      title = [NSString
          stringWithFormat:@"“%@” wants to open “%@”.", source, program];
      message = @"";
      accept = [NSString stringWithFormat:@"Open “%@”", program];
    }
    //
    NSImage* icon = nil;
    if (NSURL* target = [NSURL
            URLWithString:base::SysUTF8ToNSString(decision_->url.spec())]) {
      if (NSURL* app = [NSWorkspace.sharedWorkspace
              URLForApplicationToOpenURL:target]) {
        icon = [NSWorkspace.sharedWorkspace iconForFile:app.path];
      }
    }
    presenter_ = [[PCExternalProtocolPresenter alloc] initWithPage:page_
        window:window_
        title:title
        message:message
        icon:icon
        acceptLabel:accept
        cancelLabel:@"Cancel"
        rememberLabel:always
        validate:^BOOL {
          auto self = weak.lock();
          return self && !self->finished_ && self->Valid();
        }
        inputAllowed:^BOOL(NSEvent* event) {
          auto self = weak.lock();
          return self && self->InputAllowed(event);
        }
        stateChanged:^{
          if (auto self = weak.lock()) {
            self->PresentationChanged();
          }
        }
        result:^(BOOL accepted, BOOL remember) {
          if (auto self = weak.lock()) {
            self->Finish(accepted, remember);
          }
        }];
    if (auto* tracker = PictureInPictureWindowManager::GetInstance()
                            ->GetOcclusionTracker()) {
      occlusion_subscription_ =
          tracker->ObserveNativeOccluderChanges(base::BindRepeating(
              [](std::weak_ptr<Request> weak) {
                if (auto self = weak.lock()) {
                  self->RefreshOcclusion();
                }
              },
              weak));
    }
    if (finished_ || !Valid()) {
      return false;
    }
    // The supported native manager preserves Chrome's real renderer blocking,
    // fullscreen exit, navigation dismissal and active-dialog bookkeeping.
    registered_ = true;
    registering_ = true;
    manager->ShowDialogWithManager(Window(),
                                   std::make_unique<NativeModal>(keep));
    registering_ = false;
    if (finished_) {
      RemoveModal();
    }
    return !finished_;
  }
  void Show() {
    if (!finished_) {
      [presenter_ show];
    }
  }
  void Focus() {
    if (!finished_) {
      [presenter_ focus];
    }
  }
  gfx::NativeWindow Window() const {
    return gfx::NativeWindow(presenter_.sheet);
  }
  bool IsActive() const { return !finished_ && presenter_.sheet.keyWindow; }
  void CancelSoon() {
    cancelled_ = true;
    // A host-changed callback can occur while the manager iterates its list or
    // before it inserts this adapter. Never erase that list from the callback.
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE,
        base::BindOnce(
            [](std::shared_ptr<Request> self) { self->Finish(false, false); },
            shared_from_this()));
  }
  void HostChanged() {
    if (!Valid()) {
      CancelSoon();
    }
  }
  void ModalDestroyed() {
    registered_ = false;
    if (!finished_) {
      CancelSoon();
    }
  }
  void CloseFromManager() {
    // CloseAllDialogs requires synchronous removal to advance its actual list.
    Finish(false, false);
  }
  void Finish(bool accepted, bool remember) {
    auto keep = shared_from_this();
    if (finished_) {
      return;
    }
    const bool approved = accepted && Valid();
    finished_ = true;
    [presenter_ invalidate];
    RemoveModal();
    [reservation_ invalidate];
    reservation_ = nil;
    occlusion_subscription_ = {};
    RemoveObservers();
    accepted = approved && Valid();
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE,
        base::BindOnce(
            [](std::shared_ptr<Request> self, bool accepted, bool remember) {
              auto decision = std::move(self->decision_);
              if (!decision) {
                return;
              }
              if (accepted && self->Valid()) {
                decision->Accept(remember,
                                 base::BindRepeating(
                                     [](std::shared_ptr<Request> self) {
                                       return self->Valid();
                                     },
                                     self));
              } else {
                decision->Cancel();
              }
            },
            keep, accepted, remember));
  }
  void PresentationChanged() {
    auto keep = shared_from_this();
    if (finished_) {
      return;
    }
    protector_.VisibilityChanged(presenter_.sheet.visible);
    protector_.MaybeUpdateViewProtectedTimeStamp(/*force=*/true);
    RefreshOcclusion();
  }
  void RefreshOcclusion() {
    auto* tracker =
        PictureInPictureWindowManager::GetInstance()->GetOcclusionTracker();
    const bool occluded =
        tracker && presenter_ &&
        tracker->IsNativeRectangleOccluded(
            gfx::ScreenRectFromNSRect(presenter_.sheet.frame));
    if (occluded_ && !occluded) {
      protector_.MaybeUpdateViewProtectedTimeStamp(/*force=*/true);
    }
    occluded_ = occluded;
  }
  bool InputAllowed(NSEvent* native) {
    auto keep = shared_from_this();
    if (finished_ || !Valid()) {
      return false;
    }
    RefreshOcclusion();
    if (occluded_) {
      return false;
    }
    // Accessibility performs a button action without an NSEvent. It still
    // passes the real protector using a fresh activation timestamp.
    auto event =
        native ? ui::EventFromNative(ui::PlatformEvent(native)) : nullptr;
    if (!event || (!event->IsKeyEvent() &&
                   event->type() != ui::EventType::kMousePressed &&
                   event->type() != ui::EventType::kMouseReleased)) {
      event = std::make_unique<ui::KeyEvent>(ui::EventType::kKeyPressed,
                                             ui::VKEY_RETURN, 0,
                                             base::TimeTicks::Now());
    }
    return !protector_.IsPossiblyUnintendedInteraction(
        *event, /*allow_key_events=*/false);
  }
  void DidStartNavigation(content::NavigationHandle* handle) override {
    // A starting navigation has no RenderFrameHost yet (reading it CHECKs);
    // its frame identifies the initiating document's frame.
    auto* frame = initiator_.AsRenderFrameHostIfValid();
    if (!handle->IsSameDocument() &&
        (handle->IsInPrimaryMainFrame() ||
         (frame &&
          handle->GetFrameTreeNodeId() == frame->GetFrameTreeNodeId()))) {
      CancelSoon();
    }
  }
  void RenderFrameDeleted(content::RenderFrameHost* frame) override {
    if (frame == initiator_.AsRenderFrameHostIfValid()) {
      CancelSoon();
    }
  }
  void PrimaryPageChanged(content::Page&) override { CancelSoon(); }
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (visibility == content::Visibility::HIDDEN) {
      CancelSoon();
    }
  }
  void WebContentsDestroyed() override {
    cancelled_ = true;
    Finish(false, false);
  }

 private:
  bool Valid() const {
    auto* contents = web_contents();
    auto* state = State(contents);
    if (cancelled_ || !contents || !state || !state->attached ||
        state->generation != generation_ ||
        !initiator_.AsRenderFrameHostIfValid() || !browser_ || !profile_ ||
        browser_->IsDeleteScheduled() || !browser_->GetWindow() ||
        !document_.AsRenderFrameHostIfValid() ||
        contents->GetBrowserContext() != profile_.get() ||
        browser_->GetProfile() != profile_.get() || !window_ || !page_ ||
        page_.window != window_ || !window_.visible || window_.miniaturized ||
        page_.hiddenOrHasHiddenAncestor ||
        contents->GetVisibility() == content::Visibility::HIDDEN ||
        browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow() !=
            window_ ||
        (window_.attachedSheet && window_.attachedSheet != presenter_.sheet) ||
        (reservation_ ? !reservation_.isOnlyReservation
                      : PCNativeWindowHasSecurityReservation(window_))) {
      return false;
    }
    auto* tab = tabs::TabInterface::MaybeGetFromContents(contents);
    return tab && tab->IsActivated() &&
           tab->GetBrowserWindowInterface() == browser_.get();
  }
  void RemoveModal() {
    if (!registered_ || registering_) {
      return;
    }
    registered_ = false;
    if (auto* contents = web_contents()) {
      if (auto* manager =
              web_modal::WebContentsModalDialogManager::FromWebContents(
                  contents)) {
        manager->WillClose(Window());
      }
    }
  }
  void RemoveObservers() {
    if (window_observer_) {
      [NSNotificationCenter.defaultCenter removeObserver:window_observer_];
    }
    if (security_observer_) {
      [NSNotificationCenter.defaultCenter removeObserver:security_observer_];
    }
    window_observer_ = security_observer_ = nil;
  }
  std::unique_ptr<NativeExternalProtocolDialogRequest> decision_;
  views::InputEventActivationProtector protector_;
  base::CallbackListSubscription occlusion_subscription_;
  bool occluded_ = false;
  bool cancelled_ = false;
  base::WeakPtr<BrowserWindowInterface> browser_;
  base::WeakPtr<Profile> profile_;
  content::WeakDocumentPtr document_;
  const content::WeakDocumentPtr initiator_;
  const uint64_t generation_;
  __weak NSWindow* window_;
  __weak NSView* page_;
  PCExternalProtocolPresenter* presenter_;
  PCNativeWindowSecurityReservation* reservation_;
  id window_observer_;
  id security_observer_;
  bool finished_ = false;
  bool acquiring_ = false;
  bool registered_ = false;
  bool registering_ = false;
};

NativeModal::NativeModal(std::shared_ptr<Request> request)
    : request_(std::move(request)) {}
NativeModal::~NativeModal() {
  request_->ModalDestroyed();
}
void NativeModal::Show() {
  auto keep = request_;
  keep->Show();
}
void NativeModal::Hide() {
  auto keep = request_;
  keep->CancelSoon();
}
void NativeModal::Close() {
  auto keep = request_;
  keep->CloseFromManager();
}
void NativeModal::Focus() {
  auto keep = request_;
  keep->Focus();
}
void NativeModal::Pulse() {
  Focus();
}
void NativeModal::HostChanged(web_modal::WebContentsModalDialogHost*) {
  request_->HostChanged();
}
gfx::NativeWindow NativeModal::dialog() {
  return request_->Window();
}
bool NativeModal::IsActive() const {
  return request_->IsActive();
}

}  // namespace

void InstallNativeExternalProtocol(content::WebContents& contents) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!State(&contents)) {
    contents.SetUserData(kPageState, std::make_unique<PageState>());
  }
  SetNativeExternalProtocolDialogFactory(
      contents,
      base::BindRepeating(
          [](content::WebContents* contents,
             std::unique_ptr<NativeExternalProtocolDialogRequest> decision) {
            auto weak_contents = contents->GetWeakPtr();
            auto* state = State(contents);
            const auto generation = ++state->generation;
            //
            // Move the old list first: release notifications may reenter here.
            auto previous = std::move(state->requests);
            for (auto& weak : previous) {
              if (auto old = weak.lock()) {
                old->Finish(false, false);
              }
            }
            if (!weak_contents || !State(contents) ||
                !State(contents)->attached ||
                State(contents)->generation != generation) {
              decision->Cancel();
              return;
            }
            auto request =
                std::make_shared<Request>(*contents, std::move(decision));
            State(contents)->requests.push_back(request);
            if (!request->Build()) {
              request->Finish(false, false);
            }
          }));
}
void SetNativeExternalProtocolAttached(content::WebContents& contents,
                                       bool attached) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto* state = State(&contents);
  if (!state) {
    return;
  }
  state->attached = attached;
  if (attached) {
    return;
  }
  // A decision may already be queued after its sheet has closed. Invalidate
  // that exact attachment before callbacks: reattaching the same page cannot
  // revive consent granted to the previous attachment.
  ++state->generation;
  auto requests = std::move(state->requests);
  for (auto& weak : requests) {
    if (auto request = weak.lock()) {
      request->CloseFromManager();
    }
  }
}
}  // namespace parc
