// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_AUXILIARY_PAGE_H_
#define PARC_NATIVE_AUXILIARY_PAGE_H_

#import <AppKit/AppKit.h>

#include <memory>

#include "base/callback_list.h"
#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "content/public/browser/web_contents_observer.h"

@class PCNativePageHost;
class BrowserWindowInterface;
namespace tabs {
class TabInterface;
}
namespace parc {
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
class NativeExtensionPage final
    : public content::WebContentsObserver,
      public std::enable_shared_from_this<NativeExtensionPage> {
 public:
  static std::shared_ptr<NativeExtensionPage> Bind(
      content::WebContents& contents,
      PCNativePageHost* hosted,
      NSWindow* owner,
      base::RepeatingCallback<bool()> owner_valid);
  ~NativeExtensionPage() override;
  bool IsValid() const;
  NSWindow* window() const;
  void Revoke();
  base::CallbackListSubscription OnInvalidated(base::RepeatingClosure);

 private:
  NativeExtensionPage(content::WebContents&,
                      PCNativePageHost*,
                      NSWindow*,
                      base::RepeatingCallback<bool()>);
  void WebContentsDestroyed() override;
  PCNativePageHost* __weak hosted_;
  NSWindow* __weak window_;
  NSWindow* __weak owner_;
  base::RepeatingCallback<bool()> owner_valid_;
  id __strong window_close_;
  base::RepeatingClosureList invalidated_;
  bool revoked_ = false;
};
void MarkNativeAuxiliaryRoute(content::WebContents&);
bool HasNativeAuxiliaryRoute(content::WebContents&);
std::shared_ptr<NativeAuxiliaryPage> GetNativeAuxiliaryPage(
    content::WebContents&);
base::CallbackListSubscription ObserveNativeAuxiliaryPage(
    content::WebContents&,
    base::RepeatingClosure);
std::shared_ptr<NativeExtensionPage> GetNativeExtensionPage(
    content::WebContents&);
bool HasNativeExtensionRoute(content::WebContents&);
}
#endif
