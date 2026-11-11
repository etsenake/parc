// Copyright 2026 Parc contributors.
#ifndef CEF_LIBCEF_BROWSER_PARC_NATIVE_DEVTOOLS_PANE_H_
#define CEF_LIBCEF_BROWSER_PARC_NATIVE_DEVTOOLS_PANE_H_
#include <memory>

#include "base/functional/callback_helpers.h"
#include "base/memory/weak_ptr.h"
#include "chrome/browser/devtools/devtools_contents_resizing_strategy.h"
#include "content/public/browser/web_contents_observer.h"
#import "devtools_pane_view.h"
namespace content {
class WebContents;
}
namespace parc {
class NativeAuxiliaryPage;
// Makes `inspected`'s Browser the modal host of its docked tools, once the
// docked view is registered with its presenter. The returned lease clears that
// host on release, unless a later binding or the undocked window's own Browser
// replaced it. Existing docked tools keep this when the inspected tab moves
// into another Browser, a popup included. Empty when the tools aren't docked.
base::ScopedClosureRunner BindDockedModalHost(content::WebContents* inspected,
                                              content::WebContents* tools);
// One real inspected page's presentation, owned by its exact native
// PageBinding. DevToolsWindow retains the actual tools/toolbox WebContents;
// this never navigates, clones, adopts a tab, or deletes engine contents.
class NativeDevToolsPane final
    : public content::WebContentsObserver,
      public std::enable_shared_from_this<NativeDevToolsPane> {
 public:
  static std::shared_ptr<NativeDevToolsPane> Create(content::WebContents&,
                                                    NSView* inspected_view);
  ~NativeDevToolsPane() override;
  PCNativeDevToolsPaneView* view() const { return view_; }
  NSView* find_anchor() const { return view_.inspectedOverlay; }
  content::WebContents* tools() const { return tools_.get(); }
  bool Refresh(bool update_contents);
  void Layout();
  void SetBlocked(bool blocked);
  // Before actual page/window ownership changes. Idempotent; terminal for this
  // binding, not for the still-live WebContents or reusable page wrapper.
  void Detach();

 private:
  class ToolsObserver;
  NativeDevToolsPane(content::WebContents&, NSView*);
  void WebContentsDestroyed() override;
  void ToolsDestroyed();
  void UpdateVisibility();
  void RequestToolsFocus();
  bool OwnsViews() const;
  PCNativeDevToolsPaneView* __strong view_;
  base::WeakPtr<content::WebContents> tools_;
  std::unique_ptr<ToolsObserver> tools_observer_;
  DevToolsContentsResizingStrategy strategy_;
  base::ScopedClosureRunner modal_binding_;
  std::shared_ptr<NativeAuxiliaryPage> auxiliary_;
  uint64_t presentation_generation_ = 0;
  bool show_tools_ = false;
  // Whether the last UpdateVisibility showed tools_.
  bool tools_shown_ = false;
  bool detached_ = false;
  bool refreshing_ = false;
  base::WeakPtrFactory<NativeDevToolsPane> weak_factory_{this};
};
}  // namespace parc
#endif
