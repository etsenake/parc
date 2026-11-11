// Copyright 2026 Parc contributors.
#include "client_certificates.h"

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
#include "chrome/browser/ui/views/ssl_client_certificate_selector.h"
#include "components/tabs/public/tab_interface.h"
#include "components/web_modal/single_web_contents_dialog_manager.h"
#include "components/web_modal/web_contents_modal_dialog_host.h"
#include "components/web_modal/web_contents_modal_dialog_manager.h"
#include "components/web_modal/web_contents_modal_dialog_manager_delegate.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/client_certificate_delegate.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "native_auxiliary_page.h"
#include "net/cert/x509_certificate.h"
#include "net/ssl/ssl_cert_request_info.h"
#include "net/ssl/ssl_private_key.h"
#include "ui/base/base_window.h"
#include "ui/views/widget/native_widget_mac.h"
#include "ui/views/widget/widget.h"
#include "ui/views/widget/widget_observer.h"
#import "window_security_reservation.h"

namespace parc {
namespace {
class Request;
constexpr char kPageState[] = "parc-native-client-certificates";
class PageState final : public base::SupportsUserData::Data {
 public:
  bool attached = false;
  std::vector<std::weak_ptr<Request>> requests;
};
PageState* State(content::WebContents* contents) {
  return contents ? static_cast<PageState*>(contents->GetUserData(kPageState))
                  : nullptr;
}

// Only this real certificate dialog uses an externally owned AppKit parent.
// The standard Mac implementation's kChild DCHECK requires a Views browser
// parent. Here the real WebContentsModalDialogManager owns page modality and
// the native adapter attaches the genuine dialog NSWindow to the supplied host.
class CertificateWidget final : public views::NativeWidgetMac {
 public:
  explicit CertificateWidget(views::Widget* widget) : NativeWidgetMac(widget) {}
  void InitModalType(ui::mojom::ModalType type) override {
    CHECK_EQ(type, ui::mojom::ModalType::kChild);
  }
};

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

class ForwardingDelegate final : public content::ClientCertificateDelegate {
 public:
  explicit ForwardingDelegate(std::shared_ptr<Request> request)
      : request_(std::move(request)) {}
  ~ForwardingDelegate() override;
  void ContinueWithCertificate(scoped_refptr<net::X509Certificate>,
                               scoped_refptr<net::SSLPrivateKey>) override;

 private:
  const std::shared_ptr<Request> request_;
  bool continued_ = false;
};

class Request final : public content::WebContentsObserver,
                      public views::WidgetObserver,
                      public web_modal::ModalDialogHostObserver,
                      public std::enable_shared_from_this<Request> {
 public:
  Request(content::WebContents& contents,
          std::unique_ptr<content::ClientCertificateDelegate> delegate)
      : content::WebContentsObserver(&contents),
        delegate_(std::move(delegate)) {
    auto* tab = tabs::TabInterface::MaybeGetFromContents(&contents);
    auxiliary_ = tab ? nullptr : GetNativeAuxiliaryPage(contents);
    auto* browser = tab          ? tab->GetBrowserWindowInterface()
                    : auxiliary_ ? auxiliary_->browser()
                                 : nullptr;
    if (browser && browser->GetWindow()) {
      browser_ = browser->GetWeakPtr();
      profile_ = browser->GetProfile()->GetWeakPtr();
      window_ = browser->GetWindow()->GetNativeWindow().GetNativeNSWindow();
      page_ = contents.GetNativeView().GetNativeNSView();
      document_ = contents.GetPrimaryMainFrame()->GetWeakDocumentPtr();
    }
  }
  ~Request() override {
    CHECK(!registered_);
    if (widget_) {
      widget_->RemoveObserver(this);
    }
    ClearHost();
    RemoveObservers();
    [reservation_ invalidate];
  }
  bool Build(net::SSLCertRequestInfo* info,
             net::ClientCertIdentityList identities) {
    auto keep = shared_from_this();
    if (auxiliary_) {
      if (!auxiliary_->IsValid()) {
        return false;
      }
      std::weak_ptr<Request> weak = keep;
      auxiliary_cancel_ = auxiliary_->OnInvalidated(base::BindRepeating(
          [](std::weak_ptr<Request> weak) {
            if (auto self = weak.lock()) {
              self->Abort();
            }
          },
          weak));
    }
    auto* contents = web_contents();
    auto* manager =
        contents ? web_modal::WebContentsModalDialogManager::FromWebContents(
                       contents)
                 : nullptr;
    if (!Valid() || !manager || !manager->delegate() ||
        manager->IsDialogActive()) {
      return false;
    }
    std::weak_ptr<Request> weak = keep;
    window_observer_ = [NSNotificationCenter.defaultCenter
        addObserverForName:NSWindowWillCloseNotification
                    object:window_
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (auto self = weak.lock()) {
                    self->AbortSoon();
                  }
                }];
    security_observer_ = [NSNotificationCenter.defaultCenter
        addObserverForName:PCNativeWindowSecurityStateChanged
                    object:window_
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (auto self = weak.lock(); self && !self->acquiring_ &&
                                               !self->releasing_ &&
                                               !self->Valid()) {
                    self->AbortSoon();
                  }
                }];
    acquiring_ = true;
    auto* lease = [PCNativeWindowSecurityReservation acquireForWindow:window_];
    acquiring_ = false;
    if (aborted_) {
      [lease invalidate];
      return false;
    }
    reservation_ = lease;
    if (!Valid()) {
      return false;
    }
    auto* selector = new SSLClientCertificateSelector(
        contents, info, std::move(identities),
        std::make_unique<ForwardingDelegate>(keep),
        base::BindRepeating(
            [](std::weak_ptr<Request> weak) {
              auto self = weak.lock();
              return self && self->Valid();
            },
            weak));
    selector->Init();
    auto* widget = new views::Widget;
    auto params = views::DialogDelegate::GetDialogWidgetInitParams(
        selector, gfx::NativeWindow(), gfx::NativeView(), gfx::Rect(),
        gfx::kNullAcceleratedWidget);
    params.native_widget = new CertificateWidget(widget);
    widget->Init(std::move(params));
    widget_ = widget->GetWeakPtr();
    dialog_ = widget->GetNativeWindow();
    widget->AddObserver(this);
    if (!selector->InitializeSelectionForPresentation() || !Valid()) {
      Abort();
      return false;
    }
    registered_ = registering_ = true;
    manager->ShowDialogWithManager(dialog_,
                                   std::make_unique<NativeModal>(keep));
    registering_ = false;
    if (aborted_) {
      RemoveModal();
    }
    return !aborted_;
  }
  bool Valid() const {
    auto* contents = web_contents();
    auto* state = State(contents);
    if (aborted_ || !delegate_ || !contents || !state || !state->attached ||
        !browser_ || !profile_ || browser_->IsDeleteScheduled() ||
        !browser_->GetWindow() || !document_.AsRenderFrameHostIfValid() ||
        contents->GetBrowserContext() != profile_.get() ||
        browser_->GetProfile() != profile_.get() || !window_ || !page_ ||
        page_.window != window_ || !window_.visible || window_.miniaturized ||
        page_.hiddenOrHasHiddenAncestor ||
        contents->GetVisibility() == content::Visibility::HIDDEN ||
        browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow() !=
            window_ ||
        window_.attachedSheet ||
        (reservation_ ? !reservation_.isOnlyReservation
                      : PCNativeWindowHasSecurityReservation(window_))) {
      return false;
    }
    if (auxiliary_) {
      return auxiliary_->IsActive() && auxiliary_->browser() == browser_.get();
    }
    auto* tab = tabs::TabInterface::MaybeGetFromContents(contents);
    return tab && tab->IsActivated() &&
           tab->GetBrowserWindowInterface() == browser_.get();
  }
  void Show() {
    auto keep = shared_from_this();
    __attribute__((objc_precise_lifetime)) NSWindow* parent = window_;
    __attribute__((objc_precise_lifetime)) NSWindow* dialog =
        dialog_.GetNativeNSWindow();
    if (!Valid() || !host_ || !widget_ || !parent || !dialog) {
      AbortSoon();
      return;
    }
    Position();
    if (!Valid() || !widget_) {
      AbortSoon();
      return;
    }
    [parent addChildWindow:dialog ordered:NSWindowAbove];
    if (!Valid() || !widget_ || dialog.parentWindow != parent) {
      AbortSoon();
      return;
    }
    widget_->Show();
    if (!Valid() || !widget_ || !dialog.visible ||
        dialog.parentWindow != parent) {
      AbortSoon();
    }
  }
  void Focus() {
    if (Valid() && widget_) {
      widget_->Activate();
    }
  }
  bool IsActive() const { return widget_ && widget_->IsActive(); }
  gfx::NativeWindow Window() const { return dialog_; }
  void ChangeHost(web_modal::WebContentsModalDialogHost* host) {
    auto keep = shared_from_this();
    ClearHost();
    if (!host || !Valid() ||
        host->GetHostView().GetNativeNSView().window != window_) {
      AbortSoon();
      return;
    }
    host_ = host;
    host_->AddObserver(this);
    Position();
  }
  void OnPositionRequiresUpdate() override {
    if (!Valid()) {
      AbortSoon();
      return;
    }
    Position();
  }
  void OnHostDestroying() override {
    ClearHost();
    AbortSoon();
  }
  void ModalDestroyed() { registered_ = false; }
  void AbortSoon() {
    aborted_ = true;  // No late key callback may authorize during the deferral.
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE, base::BindOnce(&Request::Abort, shared_from_this()));
  }
  void Abort() {
    auto keep = shared_from_this();
    aborted_ = true;
    EndPresentation();
    if (widget_ && !widget_->IsClosed()) {
      widget_->Close();
    }
    // Delegate destruction is the real network-abort operation. Leave native
    // and observer callbacks first; no fabricated null-certificate consent.
    if (delegate_) {
      base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
          FROM_HERE,
          base::BindOnce(
              [](std::unique_ptr<content::ClientCertificateDelegate>) {},
              std::move(delegate_)));
    }
  }
  void Continue(scoped_refptr<net::X509Certificate> certificate,
                scoped_refptr<net::SSLPrivateKey> key) {
    if (response_pending_) {
      return;
    }
    response_pending_ = true;
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE,
        base::BindOnce(
            [](std::shared_ptr<Request> self,
               scoped_refptr<net::X509Certificate> cert,
               scoped_refptr<net::SSLPrivateKey> key) {
              if (!self->Valid()) {
                self->Abort();
                return;
              }
              self->EndPresentation();
              if (!self->Valid()) {
                self->Abort();
                return;
              }
              auto delegate = std::move(self->delegate_);
              self->RemoveObservers();
              delegate->ContinueWithCertificate(std::move(cert),
                                                std::move(key));
            },
            shared_from_this(), std::move(certificate), std::move(key)));
  }
  void CancelIfHidden() {
    if (widget_ && !widget_->IsVisible()) {
      Abort();
    }
  }
  void OnWidgetClosing(views::Widget*) override {
    auto keep = shared_from_this();
    EndPresentation();
  }
  void OnWidgetDestroying(views::Widget* widget) override {
    auto keep = shared_from_this();
    widget->RemoveObserver(this);
    widget_.reset();
    EndPresentation();
  }
  void DidStartNavigation(content::NavigationHandle* handle) override {
    if (handle->IsInPrimaryMainFrame() && !handle->IsSameDocument()) {
      AbortSoon();
    }
  }
  void PrimaryPageChanged(content::Page&) override { AbortSoon(); }
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (visibility == content::Visibility::HIDDEN) {
      AbortSoon();
    }
  }
  void WebContentsDestroyed() override { Abort(); }

 private:
  void Position() {
    if (!host_ || !widget_) {
      return;
    }
    NSView* host_view = host_->GetHostView().GetNativeNSView();
    if (!host_view || host_view.window != window_) {
      AbortSoon();
      return;
    }
    const auto size = widget_->GetWindowBoundsInScreen().size();
    const auto origin = host_->GetDialogPosition(size);
    // ModalDialogHost is top-left DIP based; AppKit's window/screen are
    // bottom-left.
    const CGFloat y = host_view.flipped ? origin.y()
                                        : NSHeight(host_view.bounds) -
                                              origin.y() - size.height();
    NSRect local = NSMakeRect(origin.x(), y, size.width(), size.height());
    NSRect screen = [window_ convertRectToScreen:[host_view convertRect:local
                                                                 toView:nil]];
    [dialog_.GetNativeNSWindow() setFrame:screen display:NO];
  }
  void ClearHost() {
    auto* host = host_.get();
    host_ = nullptr;
    if (host) {
      host->RemoveObserver(this);
    }
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
        manager->WillClose(dialog_);
      }
    }
  }
  void EndPresentation() {
    ClearHost();
    NSWindow* dialog = dialog_.GetNativeNSWindow();
    [dialog.parentWindow removeChildWindow:dialog];
    RemoveModal();
    releasing_ = true;
    [reservation_ invalidate];
    reservation_ = nil;
    releasing_ = false;
    // A notification observer can replace our lease during its release.
    // Record the invalidation now, including while key acquisition is pending.
    if (!aborted_ && delegate_ && !Valid()) {
      AbortSoon();
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
  std::unique_ptr<content::ClientCertificateDelegate> delegate_;
  std::shared_ptr<NativeAuxiliaryPage> auxiliary_;
  base::CallbackListSubscription auxiliary_cancel_;
  base::WeakPtr<BrowserWindowInterface> browser_;
  base::WeakPtr<Profile> profile_;
  content::WeakDocumentPtr document_;
  __weak NSWindow* window_;
  __weak NSView* page_;
  PCNativeWindowSecurityReservation* reservation_;
  id window_observer_;
  id security_observer_;
  base::WeakPtr<views::Widget> widget_;
  gfx::NativeWindow dialog_;
  raw_ptr<web_modal::WebContentsModalDialogHost> host_ = nullptr;
  bool acquiring_ = false;
  bool releasing_ = false;
  bool aborted_ = false;
  bool response_pending_ = false;
  bool registered_ = false;
  bool registering_ = false;
};

ForwardingDelegate::~ForwardingDelegate() {
  if (!continued_) {
    request_->AbortSoon();
  }
}
void ForwardingDelegate::ContinueWithCertificate(
    scoped_refptr<net::X509Certificate> cert,
    scoped_refptr<net::SSLPrivateKey> key) {
  continued_ = true;
  request_->Continue(std::move(cert), std::move(key));
}
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
  request_->AbortSoon();
}
void NativeModal::Close() {
  auto keep = request_;
  keep->Abort();
}
void NativeModal::Focus() {
  request_->Focus();
}
void NativeModal::Pulse() {
  request_->Focus();
}
void NativeModal::HostChanged(web_modal::WebContentsModalDialogHost* host) {
  request_->ChangeHost(host);
}
gfx::NativeWindow NativeModal::dialog() {
  return request_->Window();
}
bool NativeModal::IsActive() const {
  return request_->IsActive();
}
}  // namespace

void InstallNativeClientCertificates(content::WebContents& contents) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!State(&contents)) {
    contents.SetUserData(kPageState, std::make_unique<PageState>());
  }
}
base::OnceClosure ShowClientCertificateSelector(
    content::WebContents* contents,
    net::SSLCertRequestInfo* info,
    net::ClientCertIdentityList identities,
    std::unique_ptr<content::ClientCertificateDelegate> delegate) {
  auto* state = State(contents);
  if (!state) {
    auto* selector = new SSLClientCertificateSelector(
        contents, info, std::move(identities), std::move(delegate));
    selector->Init();
    selector->Show();
    return selector->GetCancellationCallback();
  }
  auto request = std::make_shared<Request>(*contents, std::move(delegate));
  std::erase_if(state->requests,
                [](const auto& weak) { return weak.expired(); });
  state->requests.push_back(request);
  if (!request->Build(info, std::move(identities))) {
    request->Abort();
  }
  return base::BindOnce(
      [](std::weak_ptr<Request> weak) {
        if (auto request = weak.lock()) {
          request->CancelIfHidden();
        }
      },
      std::weak_ptr<Request>(request));
}
void SetNativeClientCertificatesAttached(content::WebContents& contents,
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
  auto requests = std::move(state->requests);
  for (auto& weak : requests) {
    if (auto request = weak.lock()) {
      request->Abort();
    }
  }
}
}  // namespace parc
