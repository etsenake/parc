// Copyright 2026 Parc contributors.
#include "native_page_binding.h"

#import <AppKit/AppKit.h>

#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "certificate_viewer.h"
#include "chrome/browser/extensions/extension_install_native_host.h"
#include "chrome/browser/extensions/extension_uninstall_native_host.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "client_certificates.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/web_contents.h"
#include "external_protocol.h"
#include "fairplay_identity.h"
#include "file_dialog.h"
#include "folder_upload.h"
#include "http_auth.h"
#include "javascript_dialog_manager.h"
#include "native_appkit_host.h"
#include "native_appkit_page.h"
#include "native_auxiliary_page.h"
#include "native_engine_entry.h"
#include "native_repost_form_warning_api.h"
#import "page_host.h"
#include "sad_tab.h"
#include "site_permissions.h"
#include "webauthn.h"

// The page wrapper holds this observer weakly. Its callback holds only a weak
// binding: native reparenting or a cancelled dialog may synchronously tear
// down the owning browser, and must not call into released C++ storage.
@interface PCNativePageBindingObserver : NSObject <PCNativePageHostObserver> {
 @public
  base::RepeatingClosure window_changed;
}
@end

@implementation PCNativePageBindingObserver
- (void)pageHost:(PCNativePageHost*)host didMoveToWindow:(NSWindow*)window {
  if (window_changed) {
    auto callback = window_changed;
    callback.Run();
  }
}
- (void)pageHostDidAttemptDeferredFocus:(PCNativePageHost*)host {
  // Actual firstResponder KVO belongs to the shell's NativeFocusManager. An
  // attempted deferred send is not a successful-focus acknowledgement.
}
@end

namespace parc {
namespace {
size_t native_pages_alive = 0;
}  // namespace

struct NativePageBinding::Impl {
  PCNativePageHost* __strong page;
  PCNativePageBindingObserver* __strong observer;
  NSWindow* __weak attached_window;
  bool attached = false;
};

NativePageBinding::NativePageBinding(content::WebContents* contents)
    : content::WebContentsObserver(contents),
      content::WebContentsUserData<NativePageBinding>(*contents),
      impl_(std::make_unique<Impl>()) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  ++native_pages_alive;
  InstallNativeSadTab(*contents,
                      base::BindRepeating(
                          [](base::WeakPtr<NativePageBinding> weak) {
                            return weak && weak->HasAttachedPage();
                          },
                          weak_factory_.GetWeakPtr()));
  InstallNativeFolderUpload(*contents);
  InstallNativeJavaScriptDialogs(*contents);
  InstallNativeSitePermissions(*contents);
  InstallNativeHTTPAuth(*contents);
  InstallNativeClientCertificates(*contents);
  InstallNativeServerCertificateViewer(*contents);
  InstallNativeExternalProtocol(*contents);
  InstallNativeWebAuthn(*contents);
  // Before the first navigation: Chromium starts a popup's or new tab's load
  // before the tab reaches the tab strip.
  AttachFairPlayIdentity(*contents);
  NSView* native_view = contents->GetNativeView().GetNativeNSView();
  CHECK(native_view);
  impl_->observer = [PCNativePageBindingObserver new];
  impl_->observer->window_changed =
      base::BindRepeating(&NativePageBinding::NativeWindowChanged,
                          weak_factory_.GetWeakPtr());
  //
  // Retain that view and its renderer hierarchy, never reload into another tab.
  impl_->page = [PCNativePageHost hostWithContentView:native_view
                                             observer:impl_->observer];
  auxiliary_subscription_ = ObserveNativeAuxiliaryPage(
      *contents,
      base::BindRepeating(&NativePageBinding::AuxiliaryAttachmentChanged,
                          weak_factory_.GetWeakPtr()));
}

NativePageBinding::~NativePageBinding() {
  weak_factory_.InvalidateWeakPtrs();
  // WebContentsDestroyed already cancelled while page services were alive.
  // This fallback cannot send into the dying contents.
  if (impl_->observer) {
    impl_->observer->window_changed.Reset();
  }
  [impl_->page invalidate];
  CHECK(native_pages_alive);
  --native_pages_alive;
  NotifyNativeEngineOwnershipChanged();
}

Browser* NativePageBinding::browser() const {
  return static_cast<Browser*>(browser_.get());
}

void NativePageBinding::SetBrowser(Browser* browser) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (browser == this->browser()) {
    return;
  }
  auto weak_this = weak_factory_.GetWeakPtr();
  const auto target = browser ? browser->GetWeakPtr()
                              : base::WeakPtr<BrowserWindowInterface>();
  if (Browser* const original = this->browser()) {
    PageHostWillDetach();
    if (!weak_this || (browser && !target) || this->browser() != original ||
        !web_contents()) {
      return;
    }
  }
  const auto previous = std::exchange(browser_, target);
  auto* contents = web_contents();
  if (!contents) {
    return;
  }
  // The old host sees the loss before the new host attaches. No new
  // WebContents.
  if (previous) {
    AppKitPageOwnerChanged(previous.get(), *contents);
    if (!weak_this || (browser && !target) || web_contents() != contents ||
        this->browser() != browser) {
      return;
    }
  }
  AppKitPageOwnerChanged(browser, *contents);
}

void NativePageBinding::WebContentsDestroyed() {
  DestroyPageHost();
}

void NativePageBinding::DestroyPageHost() {
  if (closed_) {
    return;
  }
  closed_ = true;
  auto weak_this = weak_factory_.GetWeakPtr();
  PageHostWillDetach();
  if (!weak_this) {
    return;
  }
  if (impl_->observer) {
    impl_->observer->window_changed.Reset();
  }
  [impl_->page invalidate];
  if (!weak_this) {
    return;
  }
  // Retain the invalidated wrapper until destruction so a view fetched just
  // before close cannot observe an already-freed NSView.
  impl_->observer = nil;
}

gfx::NativeView NativePageBinding::GetNativePageView() const {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  return gfx::NativeView(closed_ ? nil : impl_->page);
}

bool NativePageBinding::HasAttachedPage() const {
  auto* contents = web_contents();
  // An auxiliary lease is granted only by the actual DevTools pane. It is
  // independent of the ordinary Browser/TabStrip attachment gate below.
  if (!closed_ && contents && !delivering_detach_) {
    if (auto auxiliary = GetNativeAuxiliaryPage(*contents)) {
      return impl_->page.contentView ==
                 contents->GetNativeView().GetNativeNSView() &&
             impl_->page.window == auxiliary->window();
    }
  }
  Browser* owner = browser();
  if (closed_ || !impl_->attached || !contents || !owner ||
      !owner->GetWindow() ||
      owner->tab_strip_model()->GetIndexOfWebContents(contents) ==
          TabStripModel::kNoTab) {
    return false;
  }
  NSWindow* window = impl_->page.window;
  return window && window == impl_->attached_window &&
         owner->GetWindow()->GetNativeWindow().GetNativeNSWindow() == window &&
         impl_->page.contentView ==
             contents->GetNativeView().GetNativeNSView();
}

void NativePageBinding::PageHostWillDetach() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  // Set the gate before cancellation: its callback may immediately request a
  // second dialog while the page still belongs to the old native hierarchy.
  impl_->attached = false;
  impl_->attached_window = nil;
  if (delivering_detach_) {
    return;
  }
  delivering_detach_ = true;
  auto weak_this = weak_factory_.GetWeakPtr();
  // Every cancellation below may reenter and destroy this binding or its
  // contents, so each step resolves both again.
  auto contents = [&]() -> content::WebContents* {
    return weak_this ? web_contents() : nullptr;
  };
  if (contents()) {
    SetNativePageStatusAttached(*contents(), false);
  }
  if (contents()) {
    SetNativeHTTPAuthAttached(*contents(), false);
  }
  if (contents()) {
    SetNativeClientCertificatesAttached(*contents(), false);
  }
  if (contents()) {
    SetNativeServerCertificateViewerAttached(*contents(), false);
  }
  if (contents()) {
    SetNativeExternalProtocolAttached(*contents(), false);
  }
  if (contents()) {
    SetNativeWebAuthnAttached(*contents(), false);
  }
  if (contents()) {
    SetNativeFolderUploadAttached(*contents(), false);
  }
  if (contents()) {
    CancelNativeFileDialogs(*contents());
  }
  if (contents()) {
    SetNativeSitePermissionsAttached(*contents(), false);
  }
  if (!weak_this) {
    return;
  }
  if (Browser* owner = browser()) {
    if (auto* install = extensions::ExtensionInstallNativeHost::Get(
            owner->GetUnownedUserDataHost())) {
      install->PageHostWillDetach(web_contents());
    }
    if (!weak_this) {
      return;
    }
  }
  if (Browser* owner = browser()) {
    if (auto* uninstall = extensions::ExtensionUninstallNativeHost::Get(
            owner->GetUnownedUserDataHost())) {
      uninstall->PageHostWillDetach(web_contents());
    }
    if (!weak_this) {
      return;
    }
  }
  if (contents()) {
    SetNativeJavaScriptDialogsAttached(*contents(), false);
  }
  if (contents()) {
    DismissNativeRepostFormWarning(*contents());
  }
  if (weak_this) {
    delivering_detach_ = false;
  }
}

bool NativePageBinding::PageHostDidAttach() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto* contents = web_contents();
  Browser* owner = browser();
  NSWindow* window = impl_->page.window;
  if (closed_ || delivering_detach_ || !window || !contents || !owner ||
      !owner->GetWindow() ||
      owner->tab_strip_model()->GetIndexOfWebContents(contents) ==
          TabStripModel::kNoTab ||
      owner->GetWindow()->GetNativeWindow().GetNativeNSWindow() != window ||
      impl_->page.contentView != contents->GetNativeView().GetNativeNSView()) {
    return false;
  }
  impl_->attached_window = window;
  impl_->attached = true;
  SetNativePageStatusAttached(*contents, true);
  SetNativeFolderUploadAttached(*contents, true);
  SetNativeHTTPAuthAttached(*contents, true);
  SetNativeClientCertificatesAttached(*contents, true);
  SetNativeServerCertificateViewerAttached(*contents, true);
  SetNativeExternalProtocolAttached(*contents, true);
  SetNativeWebAuthnAttached(*contents, true);
  SetNativeSitePermissionsAttached(*contents, true);
  SetNativeJavaScriptDialogsAttached(*contents, true);
  return true;
}

void NativePageBinding::AuxiliaryAttachmentChanged() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto* contents = web_contents();
  if (!contents) {
    return;
  }
  if (!closed_ && GetNativeAuxiliaryPage(*contents)) {
    // The pane has completed exact containment. Do not invent a Browser or
    // alter the ordinary tab's attached flag to authorize this separate route.
    SetNativeFolderUploadAttached(*contents, true);
    SetNativeHTTPAuthAttached(*contents, true);
    SetNativeClientCertificatesAttached(*contents, true);
    SetNativeJavaScriptDialogsAttached(*contents, true);
  } else {
    // Other services subscribe to their captured auxiliary lease. Do not run
    // broad page cancellation here: one result callback can establish a newer
    // lease, whose requests the older notification must not cancel.
    SetNativeJavaScriptDialogsAttached(*contents, false);
  }
}

void NativePageBinding::NativeWindowChanged() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  // Unexpected hierarchy changes also cancel old-window requests. Re-enable
  // only through explicit DidAttach after real browser/window association.
  if (!HasAttachedPage()) {
    PageHostWillDetach();
  }
}

Browser* NativeBrowserForContents(content::WebContents* contents) {
  auto* binding =
      contents ? NativePageBinding::FromWebContents(contents) : nullptr;
  return binding ? binding->browser() : nullptr;
}

size_t NativePagesAlive() {
  return native_pages_alive;
}

WEB_CONTENTS_USER_DATA_KEY_IMPL(NativePageBinding);

}  // namespace parc
