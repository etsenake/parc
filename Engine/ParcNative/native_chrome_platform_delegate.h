// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_BROWSER_PLATFORM_DELEGATE_H_
#define PARC_NATIVE_BROWSER_PLATFORM_DELEGATE_H_

#include <memory>

#include "base/callback_list.h"
#include "base/memory/weak_ptr.h"
#include "base/synchronization/lock.h"
#include "cef/libcef/browser/chrome/browser_platform_delegate_chrome.h"
#include "ui/gfx/native_ui_types.h"

namespace parc {

class NativeJavaScriptDialogRunner;

// Chrome runtime page adapter. Browser/TabStripModel retain actual WebContents
// ownership; this delegate retains only the native wrapper around that same
// WebContents' NSView. It neither constructs a Chrome window nor a second tab.
// Select it only through the native-host creation path, not window_info's
// Chrome-child-window route. See tests/NativePlatformDelegate/README.md.
class NativeChromePlatformDelegate final
    : public CefBrowserPlatformDelegateChrome {
 public:
  explicit NativeChromePlatformDelegate(
      std::unique_ptr<CefBrowserPlatformDelegateNative> native_delegate,
      std::shared_ptr<NativeRoute> route,
      std::shared_ptr<PreparedNativeWindow> reservation);
  std::shared_ptr<NativeRoute> native_route() const override;
  std::shared_ptr<PreparedNativeWindow> TakeNativeReservation() override;
  ~NativeChromePlatformDelegate() override;

  void WebContentsCreated(content::WebContents* contents, bool owned) override;
  void WebContentsDestroyed(content::WebContents* contents) override;
  void CloseHostWindow() override;
  CefWindowHandle GetHostWindowHandle() const override;
  views::Widget* GetWindowWidget() const override;
  void SetFocus(bool focus) override;
  gfx::Point GetScreenPoint(const gfx::Point& point,
                            bool want_dip_coords) const override;
  std::unique_ptr<CefJavaScriptDialogRunner> CreateJavaScriptDialogRunner()
      override;

  std::unique_ptr<permissions::PermissionPrompt> CreatePermissionPrompt(
      permissions::PermissionPrompt::Delegate* delegate) override;

  // UI thread only. The shell embeds this stable view in its page container.
  // Before moving it, call WillDetach. After changing the real Browser owner
  // and completing containment, call DidAttach. Validation requires the page's
  // actual NSWindow to equal BrowserWindow's actual window; no inherited
  // parent/popup handle is accepted as evidence of attachment.
  gfx::NativeView GetNativePageView() const;
  void PageHostWillDetach();
  bool PageHostDidAttach();
  // Read-only, UI-thread check of the current exact native ownership gate.
  // In particular, WillDetach clears it before cancellation callbacks run.
  bool HasAttachedPage() const;

 private:
  struct Impl;
  void NativeWindowChanged();
  void AuxiliaryAttachmentChanged();
  void DestroyPageHost();

  std::unique_ptr<Impl> impl_;
  std::shared_ptr<NativeRoute> route_;
  std::shared_ptr<PreparedNativeWindow> reservation_;
  base::CallbackListSubscription auxiliary_subscription_;
  base::WeakPtr<NativeJavaScriptDialogRunner> dialog_runner_;
  base::RepeatingClosure permission_prompt_detach_;
  bool closed_ = false;
  bool delivering_detach_ = false;
  mutable base::Lock handle_lock_;
  CefWindowHandle host_window_handle_ GUARDED_BY(handle_lock_) =
      kNullWindowHandle;
  base::WeakPtrFactory<NativeChromePlatformDelegate> weak_factory_{this};
};

}  // namespace parc
#endif  // PARC_NATIVE_BROWSER_PLATFORM_DELEGATE_H_
