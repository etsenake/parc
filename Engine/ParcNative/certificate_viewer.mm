// Copyright 2026 Parc contributors.
#include "certificate_viewer.h"

#include <memory>
#include <utility>

#include "base/apple/bridging.h"
#include "base/check.h"
#include "base/memory/weak_ptr.h"
#import "certificate_viewer_presenter.h"
#include "chrome/browser/native_server_certificate_viewer.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/ssl_status.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents_observer.h"
#include "net/cert/x509_certificate.h"
#include "net/cert/x509_util_apple.h"
#include "ui/base/base_window.h"
#import "window_security_reservation.h"

namespace parc {
namespace {
class Request;
class Context final : public NativeServerCertificateViewer {
 public:
  ~Context() override;
  void Show(content::WebContents&,
            gfx::NativeWindow,
            net::X509Certificate*) override;
  bool attached = false;
  uint64_t epoch = 0;
  std::shared_ptr<Request> request;
};
Context* GetContext(content::WebContents* contents) {
  return static_cast<Context*>(NativeServerCertificateViewer::Get(contents));
}
class Request final : public content::WebContentsObserver,
                      public std::enable_shared_from_this<Request> {
 public:
  Request(content::WebContents& contents,
          gfx::NativeWindow supplied,
          scoped_refptr<net::X509Certificate> certificate,
          uint64_t epoch)
      : WebContentsObserver(&contents),
        certificate_(std::move(certificate)),
        epoch_(epoch),
        window_(supplied.GetNativeNSWindow()),
        page_(contents.GetNativeView().GetNativeNSView()),
        document_(contents.GetPrimaryMainFrame()->GetWeakDocumentPtr()) {
    auto* tab = tabs::TabInterface::MaybeGetFromContents(&contents);
    auto* browser = tab ? tab->GetBrowserWindowInterface() : nullptr;
    if (browser) {
      browser_ = browser->GetWeakPtr();
      profile_ = browser->GetProfile()->GetWeakPtr();
    }
    if (auto* entry = contents.GetController().GetVisibleEntry()) {
      entry_id_ = entry->GetUniqueID();
    }
  }
  ~Request() override { CHECK(finished_); }
  bool Valid() const {
    auto* contents = web_contents();
    auto* context = GetContext(contents);
    auto* frame = document_.AsRenderFrameHostIfValid();
    if (finished_ || !contents || !context || !context->attached ||
        context->epoch != epoch_ || context->request.get() != this || !frame ||
        !frame->IsActive() || contents->GetPrimaryMainFrame() != frame ||
        !browser_ || !profile_ || browser_->IsDeleteScheduled() ||
        browser_->GetProfile() != profile_.get() ||
        contents->GetBrowserContext() != profile_.get() ||
        !browser_->GetWindow() || !window_ || !page_ ||
        browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow() !=
            window_ ||
        page_.window != window_ || !window_.visible || window_.miniaturized ||
        page_.hiddenOrHasHiddenAncestor ||
        contents->GetVisibility() == content::Visibility::HIDDEN ||
        (reservation_ ? !reservation_.isOnlyReservation
                      : PCNativeWindowHasSecurityReservation(window_))) {
      return false;
    }
    auto* tab = tabs::TabInterface::MaybeGetFromContents(contents);
    auto* entry = contents->GetController().GetVisibleEntry();
    return tab && tab->IsActivated() &&
           tab->GetBrowserWindowInterface() == browser_.get() && entry &&
           entry->GetUniqueID() == entry_id_ && entry->GetSSL().certificate &&
           certificate_ &&
           certificate_->EqualsIncludingChain(
               entry->GetSSL().certificate.get());
  }
  void Start() {
    auto keep = shared_from_this();
    if (!Valid() || window_.attachedSheet) {
      Finish();
      return;
    }
    NSArray* certificates = base::apple::CFToNSOwnershipCast(
        net::x509_util::CreateSecCertificateArrayForX509Certificate(
            certificate_.get())
            .release());
    if (!certificates.count) {
      Finish();
      return;
    }
    std::weak_ptr<Request> weak = keep;
    security_observer_ = [NSNotificationCenter.defaultCenter
        addObserverForName:PCNativeWindowSecurityStateChanged
                    object:window_
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (auto self = weak.lock(); self && !self->acquiring_ &&
                                               !self->finished_ &&
                                               !self->Valid()) {
                    self->Finish();
                  }
                }];
    acquiring_ = true;
    auto* lease = [PCNativeWindowSecurityReservation acquireForWindow:window_];
    acquiring_ = false;
    if (finished_) {
      [lease invalidate];
      return;
    }
    reservation_ = lease;
    if (!reservation_ || !Valid()) {
      Finish();
      return;
    }
    presenter_ = [[PCServerCertificatePresenter alloc] initWithPage:page_
        window:window_
        certificates:certificates
        validate:^BOOL {
          auto self = weak.lock();
          return self && self->Valid();
        }
        finished:^{
          if (auto self = weak.lock()) {
            self->Finish();
          }
        }];
    [presenter_ show];
  }
  void Finish() {
    auto keep = shared_from_this();
    if (finished_) {
      return;
    }
    finished_ = true;
    if (security_observer_) {
      [NSNotificationCenter.defaultCenter removeObserver:security_observer_];
      security_observer_ = nil;
    }
    if (auto* context = GetContext(web_contents());
        context && context->request.get() == this) {
      context->request.reset();
    }
    auto* presenter = presenter_;
    presenter_ = nil;
    [presenter invalidate];
    [reservation_ invalidate];
    reservation_ = nil;
  }
  void DidStartNavigation(content::NavigationHandle* navigation) override {
    if (navigation->IsInPrimaryMainFrame() && !navigation->IsSameDocument()) {
      Finish();
    }
  }
  void DidFinishNavigation(content::NavigationHandle*) override {
    if (!Valid()) {
      Finish();
    }
  }
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (visibility == content::Visibility::HIDDEN) {
      Finish();
    }
  }
  void WebContentsDestroyed() override {
    Observe(nullptr);
    Finish();
  }

 private:
  const scoped_refptr<net::X509Certificate> certificate_;
  const uint64_t epoch_;
  __weak NSWindow* window_;
  __weak NSView* page_;
  content::WeakDocumentPtr document_;
  base::WeakPtr<BrowserWindowInterface> browser_;
  base::WeakPtr<Profile> profile_;
  int entry_id_ = 0;
  PCServerCertificatePresenter* presenter_;
  PCNativeWindowSecurityReservation* reservation_;
  id security_observer_;
  bool acquiring_ = false;
  bool finished_ = false;
};
Context::~Context() {
  auto old = std::move(request);
  if (old) {
    old->Finish();
  }
}
void Context::Show(content::WebContents& contents,
                   gfx::NativeWindow parent,
                   net::X509Certificate* certificate) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  // A second click does not replace a valid OS sheet or its exact certificate.
  if (request || !attached || !certificate) {
    return;
  }
  auto next = std::make_shared<Request>(
      contents, parent, base::WrapRefCounted(certificate), epoch);
  request = next;
  next->Start();
}
}  // namespace
void InstallNativeServerCertificateViewer(content::WebContents& contents) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!NativeServerCertificateViewer::Get(&contents)) {
    NativeServerCertificateViewer::Set(contents, std::make_unique<Context>());
  }
}
void SetNativeServerCertificateViewerAttached(content::WebContents& contents,
                                              bool attached) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto* context = GetContext(&contents);
  if (!context) {
    return;
  }
  context->attached = attached;
  if (!attached) {
    ++context->epoch;
    auto old = context->request;
    if (old) {
      old->Finish();
    }
  }
}
}  // namespace parc
