// Copyright 2026 Parc contributors.
// Pages draw through compositors their window keeps across tab switches, as
//
// compositor and a re-shown page shows the pane's white backing until a new
// compositor's first frame. See docs/page-compositing.md.
#ifndef CEF_LIBCEF_BROWSER_PARC_NATIVE_PANE_COMPOSITOR_H_
#define CEF_LIBCEF_BROWSER_PARC_NATIVE_PANE_COMPOSITOR_H_

#import <AppKit/AppKit.h>

#include "base/functional/callback_forward.h"
#include "base/memory/scoped_refptr.h"
#include "pane_compositor_policy.h"

namespace content {
class WebContents;
}

namespace parc {

class NativePaneCompositorPool;

// A browser host's hold on its window's compositors, from window attachment
// to detachment. Without a hold, compositors only outlive their pages long
// enough for a hand-off.
class NativePaneCompositorClaim final {
 public:
  explicit NativePaneCompositorClaim(NSWindow* window);
  NativePaneCompositorClaim(const NativePaneCompositorClaim&) = delete;
  NativePaneCompositorClaim& operator=(const NativePaneCompositorClaim&) =
      delete;
  ~NativePaneCompositorClaim();

 private:
  scoped_refptr<NativePaneCompositorPool> pool_;
};

enum class PaneCompositorShow {
  kShown,
  // A hand-off involving this page was mid-flight in a native callback; try
  // again on a later pass.
  kBusy,
  // Not hostable here: no window, another window, or a page being destroyed.
  kRefused,
};

// Before `contents` becomes visible in `window` as `role`, and on every later
// pass while it stays visible. Attaches it to one of the window's
// compositors: its own, else one whose page has left the screen, else a new
// one. A reused compositor keeps showing its last frame only when that frame
// was the same pane's (PaneHeldFrameFits); otherwise it is cleared first.
// Once a renderer view has drawn through a parent compositor Chromium never
// lets it draw by itself again, so a page Chromium shows outside this call
// (its view unhidden or moved by AppKit before the pass) draws nothing until
// the pass attaches it. May run native visibility callbacks.
PaneCompositorShow ShowInPaneCompositor(content::WebContents& contents,
                                        NSWindow* window,
                                        PaneRole role);

// After `contents` was hidden. Its compositor stops drawing and keeps the
// page until another page in the window needs it or a sweep retires it.
// Ignored while the compositor is still on screen for a newer owner.
void HidePaneCompositor(content::WebContents& contents);

// Runs `presented` once the compositor showing `contents` has put a frame
// drawn after this call on screen, or soon when the page has no compositor.
// Dropped if the page is hidden or leaves that compositor first. False, with
// nothing queued, while a hand-off involving the page is mid-flight.
bool NotifyPaneCompositorPresented(content::WebContents& contents,
                                   base::OnceClosure presented);

// Before CefShutdown, with the message loop returned: detaches every page and
// destroys every compositor while Chromium's ImageTransportFactory still
// exists. Later calls show nothing.
void ShutDownPaneCompositors();

}  // namespace parc

#endif  // CEF_LIBCEF_BROWSER_PARC_NATIVE_PANE_COMPOSITOR_H_
