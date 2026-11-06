// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_HISTORY_SWIPE_H_
#define PARC_NATIVE_NATIVE_HISTORY_SWIPE_H_
#import "content/public/browser/render_widget_host_view_mac_delegate.h"
namespace content {
class RenderWidgetHost;
}
namespace parc {
// One upstream recognizer, with exact native page ownership when native-routed.
NSObject<RenderWidgetHostViewMacDelegate>* CreateNativeHistorySwipeDelegate(
    content::RenderWidgetHost* host);
}  // namespace parc
#endif
