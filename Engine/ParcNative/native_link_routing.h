// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_LINK_ROUTING_H_
#define PARC_NATIVE_NATIVE_LINK_ROUTING_H_
#include <cstdint>
#include <memory>
#include <optional>
#include "native_split_link_api.h"
#include "base/unguessable_token.h"
#include "base/functional/callback.h"

#include "content/public/browser/global_routing_id.h"
#include "ui/base/window_open_disposition.h"
class BrowserWindowInterface;
class GURL;
namespace content { class WebContents; class RenderFrameHost; class NavigationHandle; struct OpenURLParams; }
namespace parc {
void EnableNativeLinkNavigation(content::WebContents&);
// Exact CEF main-frame OnAddressChange, including same-document URL updates.
void UpdateNativeLinkURL(content::WebContents&, const GURL&);
std::optional<base::UnguessableToken> PrepareNativeCurrentLink(
    BrowserWindowInterface&, content::RenderFrameHost*, const GURL&,
    WindowOpenDisposition, std::optional<uint32_t> input_modifiers);
// Returns true only when this exact token is a matched ATC admission and the
// original callback was consumed. The created page may arrive asynchronously.
bool HandleNativeMatchedLink(BrowserWindowInterface&, content::WebContents*,
    const content::OpenURLParams&,
    base::OnceCallback<void(content::NavigationHandle&)>& callback);
// A synchronous request handoff. The original OpenURLParams copy and source
// document remain together until the base navigator returns its actual page.
class NativePeekNavigation {
 public:
  ~NativePeekNavigation();
  const content::OpenURLParams& params() const;
  bool SplitStillValid() const;
  void DidNavigate(content::WebContents* created);
 private:
  struct State;
  explicit NativePeekNavigation(std::unique_ptr<State> state);
  std::unique_ptr<State> state_;
  friend std::unique_ptr<NativePeekNavigation> PrepareNativePeekNavigation(
      BrowserWindowInterface&, content::WebContents*, const content::OpenURLParams&);
  friend std::unique_ptr<NativePeekNavigation> PrepareNativeSplitNavigation(
      BrowserWindowInterface&, content::WebContents*, const content::OpenURLParams&);
};
std::unique_ptr<NativePeekNavigation> PrepareNativePeekNavigation(
    BrowserWindowInterface& browser, content::WebContents* source,
    const content::OpenURLParams& params);
std::unique_ptr<NativePeekNavigation> PrepareNativeSplitNavigation(
    BrowserWindowInterface& browser, content::WebContents* source,
    const content::OpenURLParams& params);
// Capture the original creator, before CEF attaches its host. This is a lease on
// the actual source document, never a URL-to-parent lookup or last-opened slot.
void CaptureNativeCreatedPage(content::WebContents* source,
    content::GlobalRenderFrameHostId opener, content::WebContents* created);
// Called while the caller owns the exact newly-created WebContents. Chromium's
// normal popup blocker and adoption continue afterward; this only records a
// presentation request, including a matched same-profile destination Space.
// The exact source document/Space and destination are revalidated once at
// adoption. Does not navigate, move profiles or consume the WebContents.
void PrepareNativeCreatedPage(BrowserWindowInterface& browser,
    content::WebContents* source, content::WebContents& created,
    const GURL& target, WindowOpenDisposition disposition, bool user_gesture);
}  // namespace parc
#ifdef __OBJC__
#import "native_appkit_bridge.h"
namespace parc {
PCNativePageDisposition NativeCreatedPageDisposition(
    content::WebContents&, PCNativePageDisposition ordinary);
void AbandonNativeCreatedPagePresentation(content::WebContents&);
}
#endif
#endif
