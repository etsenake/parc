// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_AUXILIARY_PAGE_H_
#define PARC_NATIVE_AUXILIARY_PAGE_H_

#import <AppKit/AppKit.h>

#include <memory>

#include "base/callback_list.h"
#include "base/memory/weak_ptr.h"
#include "content/public/browser/web_contents_observer.h"

class BrowserWindowInterface;
namespace tabs {
class TabInterface;
}
namespace parc {
//
// 0x683eedc wraps the actual main tools via 0x685424c without inserting a tab.
// Current156 adaptation: bind that exact main frontend to the inspected tab's
// actual Browser and supplied native pane. Toolbox is deliberately excluded.
class NativeAuxiliaryPage final
    : public content::WebContentsObserver,
      public std::enable_shared_from_this<NativeAuxiliaryPage> {
 public:
  static std::shared_ptr<NativeAuxiliaryPage> BindDevTools(
      content::WebContents& inspected,
      content::WebContents& tools,
      NSView* hosted,
      NSView* container);
  ~NativeAuxiliaryPage() override;
  bool IsValid() const;
  bool IsActive() const;
  BrowserWindowInterface* browser() const;
  NSWindow* window() const;
  // Revoke BEFORE hierarchy/modal-owner changes. Requests retain this lease;
  // acquiring a later lease cannot make an old request valid again.
  void Revoke();
  base::CallbackListSubscription OnInvalidated(base::RepeatingClosure);

 private:
  class InspectedObserver;
  NativeAuxiliaryPage(content::WebContents&,
                      content::WebContents&,
                      BrowserWindowInterface&,
                      NSView*,
                      NSView*);
  void WebContentsDestroyed() override;
  base::WeakPtr<content::WebContents> inspected_;
  base::WeakPtr<BrowserWindowInterface> browser_;
  base::WeakPtr<tabs::TabInterface> tab_;
  NSView* __weak hosted_;
  NSView* __weak container_;
  NSWindow* __weak window_;
  id __strong window_close_;
  std::unique_ptr<InspectedObserver> inspected_observer_;
  base::CallbackListSubscription tab_detach_;
  base::CallbackListSubscription tab_discard_;
  base::RepeatingClosureList invalidated_;
  bool revoked_ = false;
};
// The route marker survives a temporary detach. Factories must cancel a routed
// but currently unbound page rather than choose another window/focused browser.
void MarkNativeAuxiliaryRoute(content::WebContents&);
bool HasNativeAuxiliaryRoute(content::WebContents&);
std::shared_ptr<NativeAuxiliaryPage> GetNativeAuxiliaryPage(
    content::WebContents&);
base::CallbackListSubscription ObserveNativeAuxiliaryPage(
    content::WebContents&,
    base::RepeatingClosure);
}  // namespace parc
#endif
