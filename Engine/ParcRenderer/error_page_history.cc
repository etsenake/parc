// Copyright 2026 Parc contributors.
#include "parc/renderer/error_page_history.h"

#include "content/public/common/url_constants.h"
#include "content/public/renderer/render_frame.h"
#include "third_party/blink/public/web/web_document.h"
#include "third_party/blink/public/web/web_local_frame.h"
#include "third_party/blink/public/web/web_view.h"
#include "url/gurl.h"

namespace parc {
void TellErrorPageAboutHistory(content::RenderFrame* render_frame) {
  if (!render_frame || !render_frame->IsMainFrame()) {
    return;
  }
  blink::WebLocalFrame* frame = render_frame->GetWebFrame();
  blink::WebView* view = render_frame->GetWebView();
  if (!frame || !view ||
      !GURL(frame->GetDocument().Url()).SchemeIs(content::kChromeErrorScheme)) {
    return;
  }
  render_frame->ExecuteJavaScript(
      view->HistoryBackListCount() > 0
          ? u"if (window.parcSetCanGoBack) parcSetCanGoBack(true);"
          : u"if (window.parcSetCanGoBack) parcSetCanGoBack(false);");
}
}  // namespace parc
