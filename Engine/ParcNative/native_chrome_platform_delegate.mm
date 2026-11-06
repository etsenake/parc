// Copyright 2026 Parc contributors.
#include "native_chrome_platform_delegate.h"

#import <AppKit/AppKit.h>

#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "cef/include/internal/cef_types_mac.h"
#include "cef/libcef/browser/parc_native/native_host_route.h"
#include "cef/libcef/browser/thread_util.h"
#include "certificate_viewer.h"
#include "chrome/browser/extensions/extension_install_native_host.h"
#include "chrome/browser/extensions/extension_uninstall_native_host.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "client_certificates.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/web_contents.h"
#include "external_protocol.h"
#include "file_dialog.h"
#include "folder_upload.h"
#include "http_auth.h"
#include "javascript_dialog_runner.h"
#include "native_appkit_page.h"
#include "native_auxiliary_page.h"
#include "native_repost_form_warning_api.h"
#import "page_host.h"
#include "sad_tab.h"
#include "site_permissions.h"
#include "webauthn.h"

// The page wrapper holds this observer weakly. Its callback holds only a weak
// delegate: native reparenting or a cancelled dialog may synchronously tear
// down the owning browser, and must not call into released C++ storage.
@interface PCNativePlatformPageObserver : NSObject <PCNativePageHostObserver> {
 @public
  base::RepeatingClosure window_changed;
}
@end

@implementation PCNativePlatformPageObserver
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

struct NativeChromePlatformDelegate::Impl {
  PCNativePageHost* __strong page;
  PCNativePlatformPageObserver* __strong observer;
  NSWindow* __weak attached_window;
  bool attached = false;
};

NativeChromePlatformDelegate::NativeChromePlatformDelegate(
    std::unique_ptr<CefBrowserPlatformDelegateNative> native_delegate,
    std::shared_ptr<NativeRoute> route,
    std::shared_ptr<PreparedNativeWindow> reservation)
    : CefBrowserPlatformDelegateChrome(std::move(native_delegate)),
      impl_(std::make_unique<Impl>()),
      route_(std::move(route)),
      reservation_(std::move(reservation)) {
  CHECK(route_);
}
std::shared_ptr<NativeRoute> NativeChromePlatformDelegate::native_route()
    const {
  CEF_REQUIRE_UIT();
  return route_;
}
std::shared_ptr<PreparedNativeWindow>
NativeChromePlatformDelegate::TakeNativeReservation() {
  CEF_REQUIRE_UIT();
  return std::exchange(reservation_, {});
}

NativeChromePlatformDelegate::~NativeChromePlatformDelegate() {
  weak_factory_.InvalidateWeakPtrs();
  // Normal WebContentsDestroyed already performed cancellation while CEF's
  // real manager was alive. This fallback cannot send into the dying delegate.
  if (impl_->observer) {
    impl_->observer->window_changed.Reset();
  }
  [impl_->page invalidate];
}

void NativeChromePlatformDelegate::WebContentsCreated(
    content::WebContents* contents,
    bool owned) {
  CEF_REQUIRE_UIT();
  CHECK(contents);
  CHECK(!closed_);
  CHECK(!impl_->page);
  CefBrowserPlatformDelegateChrome::WebContentsCreated(contents, owned);
  InstallNativeSadTab(*contents,
                      base::BindRepeating(
                          [](base::WeakPtr<NativeChromePlatformDelegate> weak) {
                            return weak && weak->HasAttachedPage();
                          },
                          weak_factory_.GetWeakPtr()));
  InstallNativeFolderUpload(*contents);
  InstallNativeHTTPAuth(*contents);
  InstallNativeClientCertificates(*contents);
  InstallNativeServerCertificateViewer(*contents);
  InstallNativeExternalProtocol(*contents);
  InstallNativeWebAuthn(*contents);
  NSView* native_view = contents->GetNativeView().GetNativeNSView();
  CHECK(native_view);
  impl_->observer = [PCNativePlatformPageObserver new];
  impl_->observer->window_changed =
      base::BindRepeating(&NativeChromePlatformDelegate::NativeWindowChanged,
                          weak_factory_.GetWeakPtr());
  //
  // Retain that view and its renderer hierarchy, never reload into another tab.
  impl_->page = [PCNativePageHost hostWithContentView:native_view
                                             observer:impl_->observer];
  auxiliary_subscription_ = ObserveNativeAuxiliaryPage(
      *contents, base::BindRepeating(
                     &NativeChromePlatformDelegate::AuxiliaryAttachmentChanged,
                     weak_factory_.GetWeakPtr()));
  base::AutoLock lock(handle_lock_);
  host_window_handle_ = CAST_NSVIEW_TO_CEF_WINDOW_HANDLE(impl_->page);
}

void NativeChromePlatformDelegate::WebContentsDestroyed(
    content::WebContents* contents) {
  CEF_REQUIRE_UIT();
  CHECK_EQ(contents, web_contents_);
  auto weak_this = weak_factory_.GetWeakPtr();
  DestroyPageHost();
  if (weak_this) {
    CefBrowserPlatformDelegateChrome::WebContentsDestroyed(contents);
  }
}

void NativeChromePlatformDelegate::CloseHostWindow() {
  CEF_REQUIRE_UIT();
  // ChromeBrowserHostImpl calls this for a departing Browser. The shell's
  // BrowserWindow host owns native window close consent and shared-window
  // coordination. Closing one logical browser must not performClose a shared
  // NSWindow or manually delete Browser/WebContents.
  DestroyPageHost();
}

void NativeChromePlatformDelegate::DestroyPageHost() {
  if (closed_) {
    return;
  }
  closed_ = true;
  {
    base::AutoLock lock(handle_lock_);
    host_window_handle_ = kNullWindowHandle;
  }
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
  // Retain the invalidated wrapper through delegate destruction so a handle
  // fetched immediately before close cannot observe an already-freed NSView.
  impl_->observer = nil;
  dialog_runner_.reset();
}

CefWindowHandle NativeChromePlatformDelegate::GetHostWindowHandle() const {
  // CEF publishes/caches this stable page-parent handle after Browser binding.
  // Reading it does not query mutable AppKit geometry off the UI thread.
  base::AutoLock lock(handle_lock_);
  return host_window_handle_;
}

views::Widget* NativeChromePlatformDelegate::GetWindowWidget() const {
  // The native window has no Views Widget or BrowserView.
  return nullptr;
}

gfx::NativeView NativeChromePlatformDelegate::GetNativePageView() const {
  CEF_REQUIRE_UIT();
  return gfx::NativeView(closed_ ? nil : impl_->page);
}

bool NativeChromePlatformDelegate::HasAttachedPage() const {
  // An auxiliary lease is granted only by the actual DevTools pane. It is
  // independent of the ordinary Browser/TabStrip attachment gate below.
  if (!closed_ && web_contents_ && !delivering_detach_) {
    if (auto auxiliary = GetNativeAuxiliaryPage(*web_contents_)) {
      return impl_->page.contentView ==
                 web_contents_->GetNativeView().GetNativeNSView() &&
             impl_->page.window == auxiliary->window();
    }
  }
  if (closed_ || !impl_->attached || !web_contents_ || !chrome_browser_ ||
      !chrome_browser_->GetWindow() ||
      chrome_browser_->tab_strip_model()->GetIndexOfWebContents(
          web_contents_) == TabStripModel::kNoTab) {
    return false;
  }
  NSWindow* window = impl_->page.window;
  return window && window == impl_->attached_window &&
         chrome_browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow() ==
             window &&
         impl_->page.contentView ==
             web_contents_->GetNativeView().GetNativeNSView();
}

void NativeChromePlatformDelegate::PageHostWillDetach() {
  CEF_REQUIRE_UIT();
  // Set the gate before cancellation: its callback may immediately request a
  // second dialog while the page still belongs to the old native hierarchy.
  impl_->attached = false;
  impl_->attached_window = nil;
  if (delivering_detach_) {
    return;
  }
  delivering_detach_ = true;
  auto weak_this = weak_factory_.GetWeakPtr();
  if (web_contents_) {
    SetNativePageStatusAttached(*web_contents_, false);
    SetNativeHTTPAuthAttached(*web_contents_, false);
  }
  if (!weak_this) {
    return;
  }
  if (web_contents_) {
    SetNativeClientCertificatesAttached(*web_contents_, false);
  }
  if (!weak_this) {
    return;
  }
  if (web_contents_) {
    SetNativeServerCertificateViewerAttached(*web_contents_, false);
  }
  if (!weak_this) {
    return;
  }
  if (web_contents_) {
    SetNativeExternalProtocolAttached(*web_contents_, false);
  }
  if (!weak_this) {
    return;
  }
  if (web_contents_) {
    SetNativeWebAuthnAttached(*web_contents_, false);
  }
  if (!weak_this) {
    return;
  }
  if (web_contents_) {
    SetNativeFolderUploadAttached(*web_contents_, false);
  }
  if (!weak_this) {
    return;
  }
  if (web_contents_) {
    CancelNativeFileDialogs(*web_contents_);
  }
  if (!weak_this) {
    return;
  }
  auto detach_permission = std::move(permission_prompt_detach_);
  if (detach_permission) {
    detach_permission.Run();
  }
  if (!weak_this) {
    return;
  }
  if (chrome_browser_) {
    if (auto* install = extensions::ExtensionInstallNativeHost::Get(
            chrome_browser_->GetUnownedUserDataHost())) {
      install->PageHostWillDetach(web_contents_);
    }
    if (!weak_this) {
      return;
    }
    if (auto* uninstall = extensions::ExtensionUninstallNativeHost::Get(
            chrome_browser_->GetUnownedUserDataHost())) {
      uninstall->PageHostWillDetach(web_contents_);
    }
    if (!weak_this) {
      return;
    }
  }
  if (dialog_runner_) {
    dialog_runner_->PageHostWillDetach();
  }
  if (weak_this && web_contents_) {
    DismissNativeRepostFormWarning(*web_contents_);
  }
  if (weak_this) {
    delivering_detach_ = false;
  }
}

bool NativeChromePlatformDelegate::PageHostDidAttach() {
  CEF_REQUIRE_UIT();
  NSWindow* window = impl_->page.window;
  if (closed_ || delivering_detach_ || !window || !web_contents_ ||
      !chrome_browser_ || !chrome_browser_->GetWindow() ||
      chrome_browser_->tab_strip_model()->GetIndexOfWebContents(
          web_contents_) == TabStripModel::kNoTab ||
      chrome_browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow() !=
          window ||
      impl_->page.contentView !=
          web_contents_->GetNativeView().GetNativeNSView()) {
    return false;
  }
  impl_->attached_window = window;
  impl_->attached = true;
  SetNativePageStatusAttached(*web_contents_, true);
  SetNativeFolderUploadAttached(*web_contents_, true);
  SetNativeHTTPAuthAttached(*web_contents_, true);
  SetNativeClientCertificatesAttached(*web_contents_, true);
  SetNativeServerCertificateViewerAttached(*web_contents_, true);
  SetNativeExternalProtocolAttached(*web_contents_, true);
  SetNativeWebAuthnAttached(*web_contents_, true);
  if (dialog_runner_) {
    dialog_runner_->PageHostDidAttach();
  }
  return true;
}

void NativeChromePlatformDelegate::AuxiliaryAttachmentChanged() {
  CEF_REQUIRE_UIT();
  if (!closed_ && web_contents_ && GetNativeAuxiliaryPage(*web_contents_)) {
    // The pane has completed exact containment. Do not invent a Browser or
    // alter the ordinary tab's attached flag to authorize this separate route.
    SetNativeFolderUploadAttached(*web_contents_, true);
    SetNativeHTTPAuthAttached(*web_contents_, true);
    SetNativeClientCertificatesAttached(*web_contents_, true);
    if (dialog_runner_) {
      dialog_runner_->PageHostDidAttach();
    }
  } else if (dialog_runner_) {
    // Other services subscribe to their captured auxiliary lease. Do not run
    // broad page cancellation here: one result callback can establish a newer
    // lease, whose requests the older notification must not cancel.
    dialog_runner_->PageHostWillDetach();
  }
}

void NativeChromePlatformDelegate::NativeWindowChanged() {
  CEF_REQUIRE_UIT();
  // Unexpected hierarchy changes also cancel old-window requests. Re-enable
  // only through explicit DidAttach after real browser/window association.
  if (!HasAttachedPage()) {
    PageHostWillDetach();
  }
}

void NativeChromePlatformDelegate::SetFocus(bool focus) {
  CEF_REQUIRE_UIT();
  if (!web_contents_ || closed_) {
    return;
  }
  if (focus && HasAttachedPage() && FocusNativeRendererCrash(web_contents_)) {
    return;
  }
  auto weak_this = weak_factory_.GetWeakPtr();
  if (auto* renderer = web_contents_->GetRenderWidgetHostView()) {
    renderer->SetActive(focus && HasAttachedPage());
  }
  if (weak_this && focus && HasAttachedPage()) {
    PCNativePageHost* page = impl_->page;
    //
    // delivery. Do not bypass it with the native CEF delegate's direct focus.
    [page.window makeFirstResponder:page];
  }
}

gfx::Point NativeChromePlatformDelegate::GetScreenPoint(
    const gfx::Point& point,
    bool want_dip_coords) const {
  CEF_REQUIRE_UIT();
  if (!HasAttachedPage()) {
    return gfx::Point();
  }
  // CEF's Mac input contract always uses DIP. Convert from the actual page,
  // including its layout offset inside split/native chrome, not window origin.
  NSView* page = impl_->page.contentView;
  NSPoint local = NSMakePoint(NSMinX(page.bounds) + point.x(),
                              page.isFlipped ? NSMinY(page.bounds) + point.y()
                                             : NSMaxY(page.bounds) - point.y());
  NSPoint in_window = [page convertPoint:local toView:nil];
  NSPoint on_screen = [page.window convertPointToScreen:in_window];
  return gfx::Point(on_screen.x, on_screen.y);
}

std::unique_ptr<CefJavaScriptDialogRunner>
NativeChromePlatformDelegate::CreateJavaScriptDialogRunner() {
  CEF_REQUIRE_UIT();
  CHECK(web_contents_);
  auto runner = std::make_unique<NativeJavaScriptDialogRunner>(*web_contents_);
  dialog_runner_ = runner->GetWeakPtr();
  if (!HasAttachedPage()) {
    runner->PageHostWillDetach();
  }
  return runner;
}

std::unique_ptr<permissions::PermissionPrompt>
NativeChromePlatformDelegate::CreatePermissionPrompt(
    permissions::PermissionPrompt::Delegate* delegate) {
  CEF_REQUIRE_UIT();
  CHECK(web_contents_);
  auto prompt = CreateNativeSitePermissionPrompt(*web_contents_, delegate,
                                                 &permission_prompt_detach_);
  if (!HasAttachedPage()) {
    permission_prompt_detach_.Run();
  }
  return prompt;
}

}  // namespace parc
