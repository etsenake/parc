// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_PAGE_OBSERVERS_H_
#define PARC_NATIVE_NATIVE_PAGE_OBSERVERS_H_
#include "base/functional/callback.h"
#import "content/public/browser/render_widget_host_view_mac_delegate.h"
class GURL;
namespace content { class WebContents; class RenderWidgetHost; }
namespace input { struct NativeWebKeyboardEvent; }
namespace parc {
void InstallNativePageObservers(content::WebContents&);
void NativePageTargetURLChanged(content::WebContents&, const GURL&);
// Caller must return false immediately for skip_if_unhandled before calling
// this hook or Chrome. False here otherwise continues genuine Chrome handling.
bool HandleNativePageUnhandledKey(content::WebContents&,
                                  const input::NativeWebKeyboardEvent&);
void NativePageRendererUnresponsive(content::WebContents&,
                                    content::RenderWidgetHost&,
                                    base::RepeatingClosure);
void NativePageRendererResponsive(content::WebContents&);
// Retire the outstanding renderer decision before page detach/replacement.
void DetachNativePageObservers(content::WebContents&);
NSObject<RenderWidgetHostViewMacDelegate>* NativePageHistorySwipeDelegate(
    content::RenderWidgetHost*, bool is_popup);
}  // namespace parc
#endif
