// Copyright 2026 Parc contributors.
#include "native_web_contents_view_delegate.h"

#include "chrome/browser/ui/views/tab_contents/chrome_web_contents_view_delegate_views_mac.h"
#include "native_page_observers.h"

namespace parc {
namespace {
class NativeWebContentsViewDelegate final
    : public ChromeWebContentsViewDelegateViewsMac {
 public:
  using ChromeWebContentsViewDelegateViewsMac::
      ChromeWebContentsViewDelegateViewsMac;

  NSObject<RenderWidgetHostViewMacDelegate>* GetDelegateForHost(
      content::RenderWidgetHost* render_widget_host,
      bool is_popup) override {
    return NativePageHistorySwipeDelegate(render_widget_host, is_popup);
  }
};
}  // namespace

std::unique_ptr<content::WebContentsViewDelegate>
CreateNativeWebContentsViewDelegate(content::WebContents* web_contents) {
  return std::make_unique<NativeWebContentsViewDelegate>(web_contents);
}
}  // namespace parc
