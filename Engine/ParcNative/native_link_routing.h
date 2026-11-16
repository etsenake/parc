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
void UpdateNativeLinkURL(content::WebContents&, const GURL&);
std::optional<base::UnguessableToken> PrepareNativeCurrentLink(
    BrowserWindowInterface&, content::RenderFrameHost*, const GURL&,
    WindowOpenDisposition, std::optional<uint32_t> input_modifiers);
bool HandleNativeMatchedLink(BrowserWindowInterface&, content::WebContents*,
    const content::OpenURLParams&,
    base::OnceCallback<void(content::NavigationHandle&)>& callback);
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
bool NativeSplitLinkAvailable(BrowserWindowInterface&, content::WebContents& source);
std::optional<base::UnguessableToken> PrepareNativeOptionLink(
    BrowserWindowInterface&, content::RenderFrameHost*, const GURL&);
std::unique_ptr<content::OpenURLParams> TakeNativeOptionLink(
    content::WebContents* source, const content::OpenURLParams&);
void CaptureNativeCreatedPage(content::WebContents* source,
    content::GlobalRenderFrameHostId opener, content::WebContents* created);
void PrepareNativeCreatedPage(BrowserWindowInterface& browser,
    content::WebContents* source, content::WebContents& created,
    const GURL& target, WindowOpenDisposition disposition, bool user_gesture);
}
#ifdef __OBJC__
#import "native_appkit_bridge.h"
namespace parc {
PCNativePageDisposition NativeCreatedPageDisposition(
    content::WebContents&, PCNativePageDisposition ordinary);
void AbandonNativeCreatedPagePresentation(content::WebContents&);
}
#endif
#endif
