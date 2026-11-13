#ifndef CONTENT_RENDERER_PARC_NATIVE_LINK_POLICY_H_
#define CONTENT_RENDERER_PARC_NATIVE_LINK_POLICY_H_

class GURL;
namespace blink {
class WebLocalFrame;
struct WebNavigationInfo;
}
namespace content::parc {
bool MayPrepareNativeMainFrameLink(blink::WebLocalFrame& frame,
                                   const blink::WebNavigationInfo& info,
                                   bool use_archive,
                                   const GURL& url);
}
#endif
