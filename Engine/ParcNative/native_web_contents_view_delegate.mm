// Copyright 2026 Parc contributors.
#include "native_web_contents_view_delegate.h"

#include "base/memory/raw_ptr.h"
#include "chrome/browser/ui/views/tab_contents/chrome_web_contents_view_delegate_views_mac.h"
#include "native_page_observers.h"
#include "sad_tab.h"

namespace parc {
namespace {
class NativeWebContentsViewDelegate final
    : public ChromeWebContentsViewDelegateViewsMac {
 public:
  explicit NativeWebContentsViewDelegate(content::WebContents* web_contents)
      : ChromeWebContentsViewDelegateViewsMac(web_contents),
        web_contents_(web_contents) {}

  // Chrome's focus helper assumes its own Views sad tab.
  bool Focus() override {
    return FocusNativeRendererCrash(web_contents_) ||
           ChromeWebContentsViewDelegateViewsMac::Focus();
  }

  NSObject<RenderWidgetHostViewMacDelegate>* GetDelegateForHost(
      content::RenderWidgetHost* render_widget_host,
      bool is_popup) override {
    return NativePageHistorySwipeDelegate(render_widget_host, is_popup);
  }

 private:
  const raw_ptr<content::WebContents> web_contents_;
};
}  // namespace

std::unique_ptr<content::WebContentsViewDelegate>
CreateNativeWebContentsViewDelegate(content::WebContents* web_contents) {
  return std::make_unique<NativeWebContentsViewDelegate>(web_contents);
}
}  // namespace parc
