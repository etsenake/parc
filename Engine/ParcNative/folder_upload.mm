// Copyright 2026 Parc contributors.
#include "folder_upload.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <memory>
#include <utility>
#include <vector>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/supports_user_data.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/dialogs/browser_dialogs.h"
#include "components/tabs/public/tab_interface.h"
#include "components/web_modal/single_web_contents_dialog_manager.h"
#include "components/web_modal/web_contents_modal_dialog_host.h"
#include "components/web_modal/web_contents_modal_dialog_manager.h"
#include "components/web_modal/web_contents_modal_dialog_manager_delegate.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "native_auxiliary_page.h"
#include "ui/base/base_window.h"
#include "ui/base/models/dialog_model.h"
#include "ui/views/bubble/bubble_dialog_model_host.h"
#include "ui/views/widget/native_widget_mac.h"
#include "ui/views/widget/widget.h"
#include "ui/views/widget/widget_observer.h"
#import "window_security_reservation.h"

namespace parc {
namespace {
class Request;
constexpr char kState[] = "parc-native-folder-upload";
class PageState final : public base::SupportsUserData::Data {
 public:
  bool attached = false;
  std::vector<std::weak_ptr<Request>> requests;
};
PageState* State(content::WebContents* contents) {
  return contents ? static_cast<PageState*>(contents->GetUserData(kState))
                  : nullptr;
}

class FolderWidget final : public views::NativeWidgetMac {
 public:
  explicit FolderWidget(views::Widget* widget) : NativeWidgetMac(widget) {}
  void InitModalType(ui::mojom::ModalType type) override {
    CHECK_EQ(type, ui::mojom::ModalType::kChild);
  }
};
class NativeModal final : public web_modal::SingleWebContentsDialogManager {
 public:
  explicit NativeModal(std::shared_ptr<Request> request)
      : request_(std::move(request)) {}
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
                      public views::WidgetObserver,
                      public web_modal::ModalDialogHostObserver,
                      public std::enable_shared_from_this<Request> {
 public:
  Request(content::WebContents* contents, content::RenderFrameHost* frame)
      : content::WebContentsObserver(contents) {
    if (!contents || !frame ||
        content::WebContents::FromRenderFrameHost(frame) != contents) {
      return;
    }
    document_ = frame->GetWeakDocumentPtr();
    auto* tab = tabs::TabInterface::MaybeGetFromContents(contents);
    auxiliary_ = tab ? nullptr : GetNativeAuxiliaryPage(*contents);
    extension_page_ =
        tab || auxiliary_ ? nullptr : GetNativeExtensionPage(*contents);
    if (extension_page_) {
      window_ = extension_page_->window();
      page_ = contents->GetNativeView().GetNativeNSView();
      return;
    }
    auto* browser = tab          ? tab->GetBrowserWindowInterface()
                    : auxiliary_ ? auxiliary_->browser()
                                 : nullptr;
    if (browser && browser->GetWindow()) {
      browser_ = browser->GetWeakPtr();
      profile_ = browser->GetProfile()->GetWeakPtr();
      window_ = browser->GetWindow()->GetNativeWindow().GetNativeNSWindow();
      page_ = contents->GetNativeView().GetNativeNSView();
    }
  }
  ~Request() override {
    CHECK(!registered_);
    CHECK(!widget_);
    ClearHost();
    RemoveObservers();
    [reservation_ invalidate];
  }
  void Build(std::unique_ptr<ui::DialogModel> model) {
    auto keep = shared_from_this();
    auto host = views::BubbleDialogModelHost::CreateModal(
        std::move(model), ui::mojom::ModalType::kChild);
    std::weak_ptr<Request> weak = keep;
    host->SetNativeAcceptanceValidation(base::BindRepeating(
        [](std::weak_ptr<Request> weak) {
          auto self = weak.lock();
          return self && self->Accept();
        },
        weak));
    auto* widget = new views::Widget;
    auto params = views::DialogDelegate::GetDialogWidgetInitParams(
        host.release(), gfx::NativeWindow(), gfx::NativeView(), gfx::Rect());
    params.native_widget = new FolderWidget(widget);
    widget->Init(std::move(params));
    widget_ = widget->GetWeakPtr();
    dialog_ = widget->GetNativeWindow();
    keep_alive_ = keep;
    widget->AddObserver(this);
    if (!Valid()) {
      CancelSoon();
      return;
    }
    const auto cancel = base::BindRepeating(
        [](std::weak_ptr<Request> weak) {
          if (auto self = weak.lock())
            self->CancelSoon();
        },
        weak);
    if (auxiliary_)
      auxiliary_cancel_ = auxiliary_->OnInvalidated(cancel);
    if (extension_page_)
      extension_page_cancel_ = extension_page_->OnInvalidated(cancel);
    window_observer_ = [NSNotificationCenter.defaultCenter
        addObserverForName:NSWindowWillCloseNotification
                    object:window_
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (auto self = weak.lock())
                    self->CancelSoon();
                }];
    security_observer_ = [NSNotificationCenter.defaultCenter
        addObserverForName:PCNativeWindowSecurityStateChanged
                    object:window_
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (auto self = weak.lock(); self && !self->acquiring_ &&
                                               !self->releasing_ &&
                                               !self->Valid())
                    self->CancelSoon();
                }];
    acquiring_ = true;
    auto* reservation =
        [PCNativeWindowSecurityReservation acquireForWindow:window_];
    acquiring_ = false;
    reservation_ = reservation;
    auto* contents = web_contents();
    auto* manager =
        contents ? web_modal::WebContentsModalDialogManager::FromWebContents(
                       contents)
                 : nullptr;
    if (!Valid() || !manager || !manager->delegate() ||
        manager->IsDialogActive()) {
      CancelSoon();
      return;
    }
    registered_ = registering_ = true;
    manager->ShowDialogWithManager(dialog_,
                                   std::make_unique<NativeModal>(keep));
    registering_ = false;
    if (cancelled_)
      RemoveModal();
  }
  bool Valid() const {
    auto* contents = web_contents();
    auto* state = State(contents);
    auto* frame = document_.AsRenderFrameHostIfValid();
    if (cancelled_ || !contents || !state ||
        (!auxiliary_ && !extension_page_ && !state->attached) || !frame ||
        !frame->IsActive() || !frame->IsRenderFrameLive() ||
        content::WebContents::FromRenderFrameHost(frame) != contents ||
        !window_ || !page_ || page_.window != window_ || !window_.visible ||
        window_.miniaturized || page_.hiddenOrHasHiddenAncestor ||
        contents->GetVisibility() == content::Visibility::HIDDEN ||
        window_.attachedSheet ||
        (reservation_ ? !reservation_.isOnlyReservation
                      : PCNativeWindowHasSecurityReservation(window_)))
      return false;
    if (extension_page_)
      return extension_page_->IsValid() && extension_page_->window() == window_;
    if (!browser_ || !profile_ || browser_->IsDeleteScheduled() ||
        !browser_->GetWindow() ||
        contents->GetBrowserContext() != profile_.get() ||
        browser_->GetProfile() != profile_.get() ||
        browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow() != window_)
      return false;
    if (auxiliary_)
      return auxiliary_->IsActive() && auxiliary_->browser() == browser_.get();
    auto* tab = tabs::TabInterface::MaybeGetFromContents(contents);
    return tab && tab->IsActivated() &&
           tab->GetBrowserWindowInterface() == browser_.get();
  }
  bool Accept() {
    auto keep = shared_from_this();
    if (decided_ || !Valid() || !widget_ || !widget_->IsVisible() ||
        dialog_.GetNativeNSWindow().parentWindow != window_) {
      CancelSoon();
      return false;
    }
    EndPresentation();
    if (!Valid()) {
      CancelSoon();
      return false;
    }
    decided_ = true;
    return true;
  }
  void Show() {
    auto keep = shared_from_this();
    __attribute__((objc_precise_lifetime)) NSWindow* parent = window_;
    __attribute__((objc_precise_lifetime)) NSWindow* child =
        dialog_.GetNativeNSWindow();
    if (!Valid() || !host_ || !widget_ || !parent || !child) {
      CancelSoon();
      return;
    }
    Position();
    if (!Valid() || !widget_) {
      CancelSoon();
      return;
    }
    [parent addChildWindow:child ordered:NSWindowAbove];
    if (!Valid() || !widget_ || child.parentWindow != parent) {
      CancelSoon();
      return;
    }
    widget_->Show();
    if (!Valid() || !widget_ || !child.visible || child.parentWindow != parent)
      CancelSoon();
  }
  void Focus() {
    if (Valid() && widget_)
      widget_->Activate();
  }
  bool IsActive() const { return widget_ && widget_->IsActive(); }
  gfx::NativeWindow Window() const { return dialog_; }
  void ChangeHost(web_modal::WebContentsModalDialogHost* host) {
    auto keep = shared_from_this();
    ClearHost();
    if (!host || !Valid() ||
        host->GetHostView().GetNativeNSView().window != window_) {
      CancelSoon();
      return;
    }
    host_ = host;
    host_->AddObserver(this);
    Position();
  }
  void OnPositionRequiresUpdate() override {
    if (Valid())
      Position();
    else
      CancelSoon();
  }
  void OnHostDestroying() override {
    ClearHost();
    CancelSoon();
  }
  void ModalDestroyed() { registered_ = false; }
  void Inserted() {
    registering_ = false;
  }
  void CancelSoon() {
    if (decided_ || cancelled_)
      return;
    cancelled_ = true;
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE, base::BindOnce(&Request::Cancel, shared_from_this()));
  }
  void Cancel() {
    auto keep = shared_from_this();
    cancelled_ = true;
    EndPresentation();
    if (widget_ && !widget_->IsClosed())
      widget_->Close();
  }
  void OnWidgetClosing(views::Widget*) override {
    auto keep = shared_from_this();
    decided_ = true;
    EndPresentation();
  }
  void OnWidgetDestroying(views::Widget* widget) override {
    auto keep = shared_from_this();
    widget->RemoveObserver(this);
    widget_.reset();
    EndPresentation();
    RemoveObservers();
    keep_alive_.reset();
  }
  void DidStartNavigation(content::NavigationHandle* handle) override {
    if (!handle->IsSameDocument() &&
        (handle->IsInPrimaryMainFrame() ||
         (document_.AsRenderFrameHostIfValid() &&
          handle->GetFrameTreeNodeId() ==
              document_.AsRenderFrameHostIfValid()->GetFrameTreeNodeId())))
      CancelSoon();
  }
  void RenderFrameDeleted(content::RenderFrameHost* frame) override {
    if (!document_.AsRenderFrameHostIfValid() ||
        document_.AsRenderFrameHostIfValid() == frame)
      CancelSoon();
  }
  void PrimaryPageChanged(content::Page&) override { CancelSoon(); }
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (visibility == content::Visibility::HIDDEN)
      CancelSoon();
  }
  void WebContentsDestroyed() override { CancelSoon(); }

 private:
  void Position() {
    if (!host_ || !widget_)
      return;
    NSView* view = host_->GetHostView().GetNativeNSView();
    if (!view || view.window != window_) {
      CancelSoon();
      return;
    }
    const auto size = widget_->GetWindowBoundsInScreen().size();
    const auto origin = host_->GetDialogPosition(size);
    const CGFloat y = view.flipped
                          ? origin.y()
                          : NSHeight(view.bounds) - origin.y() - size.height();
    NSRect rect =
        [window_ convertRectToScreen:[view convertRect:NSMakeRect(origin.x(), y,
                                                                  size.width(),
                                                                  size.height())
                                                toView:nil]];
    if (NSScreen* screen = window_.screen) {
      const NSRect visible = screen.visibleFrame;
      rect.origin.x = std::clamp(
          rect.origin.x, NSMinX(visible),
          std::max(NSMinX(visible), NSMaxX(visible) - NSWidth(rect)));
      rect.origin.y = std::clamp(
          rect.origin.y, NSMinY(visible),
          std::max(NSMinY(visible), NSMaxY(visible) - NSHeight(rect)));
    }
    [dialog_.GetNativeNSWindow() setFrame:rect display:NO];
  }
  void ClearHost() {
    auto* host = host_.get();
    host_ = nullptr;
    if (host)
      host->RemoveObserver(this);
  }
  void RemoveModal() {
    if (!registered_ || registering_)
      return;
    registered_ = false;
    if (auto* contents = web_contents()) {
      if (auto* manager =
              web_modal::WebContentsModalDialogManager::FromWebContents(
                  contents))
        manager->WillClose(dialog_);
    }
  }
  void EndPresentation() {
    ClearHost();
    NSWindow* child = dialog_.GetNativeNSWindow();
    [child.parentWindow removeChildWindow:child];
    RemoveModal();
    releasing_ = true;
    [reservation_ invalidate];
    reservation_ = nil;
    releasing_ = false;
  }
  void RemoveObservers() {
    if (window_observer_)
      [NSNotificationCenter.defaultCenter removeObserver:window_observer_];
    if (security_observer_)
      [NSNotificationCenter.defaultCenter removeObserver:security_observer_];
    window_observer_ = security_observer_ = nil;
  }
  std::shared_ptr<Request> keep_alive_;
  std::shared_ptr<NativeAuxiliaryPage> auxiliary_;
  base::CallbackListSubscription auxiliary_cancel_;
  std::shared_ptr<NativeExtensionPage> extension_page_;
  base::CallbackListSubscription extension_page_cancel_;
  base::WeakPtr<BrowserWindowInterface> browser_;
  base::WeakPtr<Profile> profile_;
  content::WeakDocumentPtr document_;
  __weak NSWindow* window_;
  __weak NSView* page_;
  PCNativeWindowSecurityReservation* reservation_;
  id window_observer_, security_observer_;
  base::WeakPtr<views::Widget> widget_;
  gfx::NativeWindow dialog_;
  raw_ptr<web_modal::WebContentsModalDialogHost> host_ = nullptr;
  bool acquiring_ = false, releasing_ = false, cancelled_ = false;
  bool decided_ = false, registered_ = false, registering_ = false;
};
NativeModal::~NativeModal() {
  request_->ModalDestroyed();
}
void NativeModal::Show() {
  auto keep = request_;
  keep->Inserted();
  keep->Show();
}
void NativeModal::Hide() {
  auto keep = request_;
  keep->CancelSoon();
}
void NativeModal::Close() {
  auto keep = request_;
  keep->Inserted();
  keep->Cancel();
}
void NativeModal::Focus() {
  auto keep = request_;
  keep->Focus();
}
void NativeModal::Pulse() {}
void NativeModal::HostChanged(web_modal::WebContentsModalDialogHost* host) {
  auto keep = request_;
  keep->ChangeHost(host);
}
gfx::NativeWindow NativeModal::dialog() {
  return request_->Window();
}
bool NativeModal::IsActive() const {
  return request_->IsActive();
}
}
void ShowFolderUploadConfirmation(std::unique_ptr<ui::DialogModel> model,
                                  content::WebContents* contents,
                                  content::RenderFrameHost* frame) {
  auto* state = State(contents);
  if (!state && contents && HasNativeExtensionRoute(*contents)) {
    InstallNativeFolderUpload(*contents);
    state = State(contents);
  }
  if (!state) {
    chrome::ShowTabModal(std::move(model), contents);
    return;
  }
  auto request = std::make_shared<Request>(contents, frame);
  std::erase_if(state->requests,
                [](const auto& weak) { return weak.expired(); });
  state->requests.push_back(request);
  request->Build(std::move(model));
}
void InstallNativeFolderUpload(content::WebContents& contents) {
  if (State(&contents))
    return;
  contents.SetUserData(kState, std::make_unique<PageState>());
}
void SetNativeFolderUploadAttached(content::WebContents& contents,
                                   bool attached) {
  auto* state = State(&contents);
  if (!state)
    return;
  state->attached = attached;
  if (attached)
    return;
  const auto requests = state->requests;
  for (const auto& weak : requests)
    if (auto request = weak.lock())
      request->CancelSoon();
}
}
