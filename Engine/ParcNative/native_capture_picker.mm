// Copyright 2026 Parc contributors.
#include "native_capture_picker.h"

#import <AppKit/AppKit.h>

#include <map>
#include <set>
#include <utility>
#include <vector>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/no_destructor.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/browser_task_traits.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/desktop_capture.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "native_auxiliary_page.h"
#import "window_security_reservation.h"

namespace parc {
namespace {
using ID = content::DesktopMediaID;
using Result = DesktopMediaPicker::DoneCallbackArgumentType;
using Error = blink::mojom::MediaStreamRequestResult;
class CaptureSession;
auto& Route() {
  static base::NoDestructor<base::RepeatingCallback<bool(content::WebContents&)>> route;
  return *route;
}
auto& Sessions() {
  static base::NoDestructor<std::map<content::WebContents*,
                                    std::set<CaptureSession*>>> sessions;
  return *sessions;
}
class CaptureSession final : public content::WebContentsObserver,
                             public std::enable_shared_from_this<CaptureSession> {
 public:
  CaptureSession(const DesktopMediaPicker::Params& params,
                 std::vector<std::unique_ptr<DesktopMediaList>> sources,
                 DesktopMediaPicker::DoneCallback callback,
                 content::WeakDocumentPtr document, bool exact_request,
                 bool current_tab_only,
                 std::unique_ptr<DesktopMediaPicker> fallback)
      : WebContentsObserver(params.web_contents), params_(params),
        lists_(std::move(sources)), callback_(std::move(callback)),
        request_document_(document), current_tab_only_(current_tab_only),
        identity_(params.web_contents), fallback_(std::move(fallback)) {
    auto* contents = web_contents();
    if (!contents) return;
    contents_ = contents->GetWeakPtr();
    main_document_ = contents->GetPrimaryMainFrame()->GetWeakDocumentPtr();
    if (!exact_request) request_document_ = main_document_;
    auto* tab = tabs::TabInterface::MaybeGetFromContents(contents);
    auxiliary_ = tab ? nullptr : GetNativeAuxiliaryPage(*contents);
    auto* browser = tab ? tab->GetBrowserWindowInterface()
                        : auxiliary_ ? auxiliary_->browser() : nullptr;
    if (tab) tab_ = tab->GetWeakPtr();
    if (browser) {
      browser_ = browser->GetWeakPtr();
      profile_ = browser->GetProfile()->GetWeakPtr();
    }
    parent_ = params.parent.GetNativeNSWindow();
    page_ = contents->GetNativeView().GetNativeNSView();
    Sessions()[contents].insert(this);
  }
  ~CaptureSession() override { CHECK(finished_); }
  bool ValidOwner() const {
    auto* frame = request_document_.AsRenderFrameHostIfValid();
    auto* main = main_document_.AsRenderFrameHostIfValid();
    auto* contents = contents_.get();
    return contents && frame && frame->IsActive() && main &&
           contents->GetPrimaryMainFrame() == main &&
           content::WebContents::FromRenderFrameHost(frame) == contents &&
           browser_ && profile_ && !browser_->IsDeleteScheduled() &&
           browser_->GetProfile() == profile_.get() &&
           contents->GetBrowserContext() == profile_.get() &&
           browser_->GetWindow() && parent_ && page_ &&
           browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow() == parent_ &&
           page_.window == parent_ && !page_.hiddenOrHasHiddenAncestor &&
           parent_.visible && !parent_.miniaturized &&
           (auxiliary_ ? auxiliary_->IsActive() && auxiliary_->browser() == browser_.get()
                       : tab_ && tab_->IsActivated() && tab_->GetContents() == contents &&
                             tab_->GetBrowserWindowInterface() == browser_.get());
  }
  bool Valid() const {
    return !finished_ && !revoked_ && ValidOwner() &&
           (!reservation_ || reservation_.isOnlyReservation);
  }
  bool ValidForDelivery() const {
    return ValidOwner() && (reservation_ ? reservation_.isOnlyReservation
                                        : !PCNativeWindowHasSecurityReservation(parent_));
  }
  bool MatchesCurrentTab(const ID& id) const {
    if (!current_tab_only_) return true;
    auto* frame = main_document_.AsRenderFrameHostIfValid();
    return frame && id.type == ID::TYPE_WEB_CONTENTS &&
           id.web_contents_id.render_process_id == frame->GetGlobalId().child_id.GetUnsafeValue() &&
           id.web_contents_id.main_render_frame_id == frame->GetGlobalId().frame_routing_id;
  }
  void Start() {
    auto keep = shared_from_this();
    if (!Valid() || (!current_tab_only_ && lists_.empty()) || parent_.attachedSheet ||
        PCNativeWindowHasSecurityReservation(parent_)) { Cancel(); return; }
    auto weak = weak_factory_.GetWeakPtr();
    if (tab_) {
      deactivate_ = tab_->RegisterWillDeactivate(base::BindRepeating(
          [](base::WeakPtr<CaptureSession> self, tabs::TabInterface*) {
            if (self) self->Cancel();
          }, weak));
      detach_ = tab_->RegisterWillDetach(base::BindRepeating(
          [](base::WeakPtr<CaptureSession> self, tabs::TabInterface*,
             tabs::TabInterface::DetachReason) { if (self) self->Cancel(); }, weak));
      discard_ = tab_->RegisterWillDiscardContents(base::BindRepeating(
          [](base::WeakPtr<CaptureSession> self, tabs::TabInterface*,
             content::WebContents*, content::WebContents*) {
            if (self) self->Cancel();
          }, weak));
    } else if (auxiliary_) {
      auxiliary_cancel_ = auxiliary_->OnInvalidated(
          base::BindRepeating(&CaptureSession::Cancel, weak));
    }
    auto reservation = [PCNativeWindowSecurityReservation acquireForWindow:parent_];
    if (!weak || !Valid() || !reservation.isOnlyReservation) {
      [reservation invalidate]; Cancel(); return;
    }
    reservation_ = reservation;
    notifications_ = [NSMutableArray array];
    for (NSNotificationName name in @[NSWindowWillCloseNotification,
                                      NSWindowDidMiniaturizeNotification,
                                      PCNativeWindowSecurityStateChanged]) {
      [notifications_ addObject:[NSNotificationCenter.defaultCenter
          addObserverForName:name object:parent_ queue:nil usingBlock:^(NSNotification*) {
            if (weak && !weak->Valid()) weak->Cancel();
            else if (weak && name == NSWindowWillCloseNotification) weak->Cancel();
          }]];
    }
    [notifications_ addObject:[NSNotificationCenter.defaultCenter
        addObserverForName:NSApplicationDidBecomeActiveNotification object:nil
        queue:nil usingBlock:^(NSNotification*) {
          if (weak && !weak->Valid()) weak->Cancel();
        }]];
    {
      // Keep Chromium's actual desktop picker and its source controls. The
      // surrounding session still owns the original request's security lease.
      // Show can reenter through native widget construction, so cancellation
      // revokes immediately but defers picker destruction until it returns.
      stock_mode_ = true;
      auto forwarded = params_;
      auto destroying = std::move(params_.on_picker_destroying);
      forwarded.on_picker_destroying = base::BindRepeating(
          [](std::shared_ptr<CaptureSession> session,
             base::RepeatingClosure destroying) {
            // Close() can be asynchronous. Keep the native window reservation
            // until the actual view is gone, even after the picker is reset.
            session->stock_view_destroyed_ = true;
            session->in_destroying_callback_ = true;
            if (destroying) destroying.Run();
            session->in_destroying_callback_ = false;
            session->ScheduleStockReservationRelease();
          }, shared_from_this(), std::move(destroying));
      ++dispatch_depth_;
      // Hold the session through Chromium's posted result even if the outer
      // picker is abandoned first; the result must then be discarded safely.
      fallback_->Show(forwarded, std::move(lists_), base::BindOnce(
          [](std::shared_ptr<CaptureSession> session, Result result) {
            session->StockResult(std::move(result));
          }, shared_from_this()));
      --dispatch_depth_;
      if (revoked_) ScheduleCancel();
      else if (!Valid()) Cancel();
      return;
    }
  }
  void ScheduleStockReservationRelease() {
    if (!stock_view_destroyed_ || !finished_ || !reservation_ ||
        in_destroying_callback_ || reservation_release_scheduled_) return;
    reservation_release_scheduled_ = true;
    auto keep = shared_from_this();
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce([](std::shared_ptr<CaptureSession> self) {
          self->reservation_release_scheduled_ = false;
          [self->reservation_ invalidate];
          self->reservation_ = nil;
        }, std::move(keep)));
  }
  void Cancel() {
    if (finished_) return;
    revoked_ = true;
    // Native view callbacks can invalidate this request while the picker is
    // still using its controller. Revoke now and tear down on the next turn.
    if (stock_mode_ || dispatch_depth_) { ScheduleCancel(); return; }
    Finish(base::unexpected(Error::PERMISSION_DENIED_BY_USER));
  }
  void ScheduleCancel() {
    if (cancel_scheduled_) return;
    cancel_scheduled_ = true;
    auto keep = shared_from_this();
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce([](std::shared_ptr<CaptureSession> self) {
          self->cancel_scheduled_ = false;
          if (self->finished_) return;
          if (self->dispatch_depth_) { self->ScheduleCancel(); return; }
          self->Finish(base::unexpected(Error::PERMISSION_DENIED_BY_USER));
        }, std::move(keep)));
  }
  void StockResult(Result result) {
    // A picker is allowed to complete while Show or a widget callback is on
    // its stack. Never destroy it on that stack.
    auto keep = shared_from_this();
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(
            [](std::shared_ptr<CaptureSession> self, Result result) {
              self->ProcessStockResult(std::move(result));
            }, std::move(keep), std::move(result)));
  }
  void ProcessStockResult(Result result) {
    if (finished_ || !Valid()) {
      if (result.has_value()) ReleaseNativeSelection(result.value());
      Cancel();
      return;
    }
    Finish(std::move(result));
  }
  void Abandon() {
    // The outer request may be erased even after the picker has posted its
    // result. Until delivery begins, do not let that result reach a later
    // request in Chromium's per-WebContents queue.
    if (delivered_ || abandoned_) return;
    abandoned_ = true;
    callback_.Reset();
    if (!finished_) Cancel();
  }
  void WebContentsDestroyed() override { Cancel(); }
  void DidFinishNavigation(content::NavigationHandle*) override {
    if (!Valid()) Cancel();
  }
  void RenderFrameDeleted(content::RenderFrameHost* frame) override {
    if (frame == request_document_.AsRenderFrameHostIfValid() ||
        frame == main_document_.AsRenderFrameHostIfValid() || !Valid()) Cancel();
  }
 private:
  static void ReleaseNativeSelection(const ID& id) {
    if (id.id_type == ID::IdType::kNativePickerSession)
      content::GetIOThreadTaskRunner({})->PostTask(FROM_HERE,
          base::BindOnce(&content::desktop_capture::CloseNativeScreenCapturePicker, id));
  }
  void Finish(Result result) {
    if (finished_) return;
    auto keep = shared_from_this();
    finished_ = true;
    weak_factory_.InvalidateWeakPtrs();
    Observe(nullptr);
    params_.web_contents = nullptr;
    auto it = Sessions().find(identity_);
    if (it != Sessions().end()) { it->second.erase(this); if (it->second.empty()) Sessions().erase(it); }
    identity_ = nullptr;
    deactivate_ = {}; detach_ = {}; discard_ = {}; auxiliary_cancel_ = {};
    for (id observer in notifications_) [NSNotificationCenter.defaultCenter removeObserver:observer];
    notifications_ = nil;
    // A picker not yet shown still owns its offered models. Once shown,
    // Chromium owns them and their delegated-session leases.
    lists_.clear();
    fallback_.reset();
    if (stock_mode_) ScheduleStockReservationRelease();
    else { [reservation_ invalidate]; reservation_ = nil; }
    auto callback = std::move(callback_);
    auto destroying = std::move(params_.on_picker_destroying);
    if (destroying) destroying.Run();
    // Mirrors Chromium's picker ownership contract: completion may destroy
    // the DesktopMediaPicker, so invoke after the native UI is detached.
    if (callback) base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(
            [](std::shared_ptr<CaptureSession> self,
               DesktopMediaPicker::DoneCallback callback, Result result) {
              if (self->abandoned_) {
                if (result.has_value()) ReleaseNativeSelection(result.value());
                return;
              }
              // A new document or parent can arrive during the task boundary.
              if (result.has_value() &&
                  (!self->ValidForDelivery() || !self->MatchesCurrentTab(result.value()))) {
                ReleaseNativeSelection(result.value());
                result = base::unexpected(Error::PERMISSION_DENIED_BY_USER);
              }
              self->delivered_ = true;
              std::move(callback).Run(std::move(result));
            }, keep, std::move(callback), std::move(result)));
  }
  DesktopMediaPicker::Params params_;
  std::vector<std::unique_ptr<DesktopMediaList>> lists_;
  DesktopMediaPicker::DoneCallback callback_;
  content::WeakDocumentPtr request_document_, main_document_;
  base::WeakPtr<content::WebContents> contents_;
  base::WeakPtr<BrowserWindowInterface> browser_;
  base::WeakPtr<Profile> profile_;
  base::WeakPtr<tabs::TabInterface> tab_;
  std::shared_ptr<NativeAuxiliaryPage> auxiliary_;
  base::CallbackListSubscription deactivate_, detach_, discard_, auxiliary_cancel_;
  bool current_tab_only_ = false, finished_ = false;
  bool revoked_ = false, cancel_scheduled_ = false, in_destroying_callback_ = false;
  bool stock_mode_ = false, stock_view_destroyed_ = false;
  bool reservation_release_scheduled_ = false;
  unsigned dispatch_depth_ = 0;
  bool abandoned_ = false, delivered_ = false;
  raw_ptr<content::WebContents> identity_;
  std::unique_ptr<DesktopMediaPicker> fallback_;
  NSWindow* __weak parent_;
  NSView* __weak page_;
  PCNativeWindowSecurityReservation* __strong reservation_;
  NSMutableArray* __strong notifications_;
  base::WeakPtrFactory<CaptureSession> weak_factory_{this};
};

class RoutingPicker final : public DesktopMediaPicker {
 public:
  RoutingPicker(std::unique_ptr<DesktopMediaPicker> fallback,
                const content::MediaStreamRequest* request)
      : fallback_(std::move(fallback)), exact_request_(request != nullptr) {
    if (request) {
      if (auto* frame = content::RenderFrameHost::FromID(
              request->render_process_id, request->render_frame_id))
        document_ = frame->GetWeakDocumentPtr();
      current_tab_only_ = request->video_type ==
          blink::mojom::MediaStreamType::DISPLAY_VIDEO_CAPTURE_THIS_TAB;
    }
  }
  ~RoutingPicker() override { if (session_) session_->Abandon(); }
  void Show(const Params& params,
            std::vector<std::unique_ptr<DesktopMediaList>> lists,
            DoneCallback done) override {
    if (!params.web_contents || !Route() || !Route().Run(*params.web_contents)) {
      fallback_->Show(params, std::move(lists), std::move(done));
      return;
    }
    session_ = std::make_shared<CaptureSession>(params, std::move(lists),
        std::move(done), document_, exact_request_, current_tab_only_,
        std::move(fallback_));
    auto session = session_;
    session->Start();
  }
 private:
  std::unique_ptr<DesktopMediaPicker> fallback_;
  std::shared_ptr<CaptureSession> session_;
  content::WeakDocumentPtr document_;
  bool exact_request_, current_tab_only_ = false;
};
}  // namespace
void SetNativeCapturePickerRoute(base::RepeatingCallback<bool(content::WebContents&)> route) {
  Route() = std::move(route);
}
std::unique_ptr<DesktopMediaPicker> WrapNativeCapturePicker(
    std::unique_ptr<DesktopMediaPicker> fallback,
    const content::MediaStreamRequest* request) {
  return std::make_unique<RoutingPicker>(std::move(fallback), request);
}
void CancelNativeCapturePicker(content::WebContents& contents) {
  auto it = Sessions().find(&contents);
  if (it == Sessions().end()) return;
  std::vector<std::shared_ptr<CaptureSession>> sessions;
  for (auto* session : it->second) sessions.push_back(session->shared_from_this());
  for (const auto& session : sessions) session->Cancel();
}
}  // namespace parc
