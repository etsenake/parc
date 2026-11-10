// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_PAGE_BINDING_H_
#define PARC_NATIVE_NATIVE_PAGE_BINDING_H_

#include <memory>

#include "base/callback_list.h"
#include "base/memory/weak_ptr.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#include "ui/gfx/native_ui_types.h"

class Browser;
class BrowserWindowInterface;

namespace parc {

// The native presentation of one WebContents: the stable AppKit wrapper around
// its view, its page-bound security services and the native Browser that owns
// it now. Browser/TabStripModel own the WebContents; this lives exactly as long
// and never constructs a Chrome window or a second tab.
// See tests/NativePlatformDelegate/README.md.
class NativePageBinding final
    : public content::WebContentsObserver,
      public content::WebContentsUserData<NativePageBinding> {
 public:
  ~NativePageBinding() override;

  // The native Browser whose TabStripModel owns the page. Null while popup or
  // new contents wait for insertion, between a move's detach and attach, and
  // while DevTools docks its frontend.
  Browser* browser() const;
  // From the native Browser's SetAsDelegate. The old owner sees the page leave
  // before the new owner sees it arrive.
  void SetBrowser(Browser* browser);

  // UI thread only. The shell embeds this stable view in its page container.
  // Before moving it, call PageHostWillDetach. After changing the real Browser
  // owner and completing containment, call PageHostDidAttach. Validation
  // requires the page's actual NSWindow to equal BrowserWindow's actual window;
  // no inherited parent/popup handle is accepted as evidence of attachment.
  gfx::NativeView GetNativePageView() const;
  void PageHostWillDetach();
  bool PageHostDidAttach();
  // Read-only check of the current exact native ownership gate. In particular,
  // PageHostWillDetach clears it before cancellation callbacks run.
  bool HasAttachedPage() const;

 private:
  friend class content::WebContentsUserData<NativePageBinding>;
  struct Impl;

  explicit NativePageBinding(content::WebContents* contents);

  // content::WebContentsObserver:
  void WebContentsDestroyed() override;

  void NativeWindowChanged();
  void AuxiliaryAttachmentChanged();
  void DestroyPageHost();

  std::unique_ptr<Impl> impl_;
  // A Browser's weak pointers die before its TabStripModel, so a tab still
  // held at ~Browser never reaches a half-destroyed owner.
  base::WeakPtr<BrowserWindowInterface> browser_;
  base::CallbackListSubscription auxiliary_subscription_;
  bool closed_ = false;
  bool delivering_detach_ = false;
  base::WeakPtrFactory<NativePageBinding> weak_factory_{this};

  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

// NativePageBinding::FromWebContents(contents)->browser(), null-safe.
Browser* NativeBrowserForContents(content::WebContents* contents);
// Live bindings, for the idle-quit gate.
size_t NativePagesAlive();

}  // namespace parc
#endif  // PARC_NATIVE_NATIVE_PAGE_BINDING_H_
