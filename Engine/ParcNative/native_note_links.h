#ifndef PARC_NATIVE_NATIVE_NOTE_LINKS_H_
#define PARC_NATIVE_NATIVE_NOTE_LINKS_H_
#include "ui/base/window_open_disposition.h"
class BrowserWindowInterface;
class GURL;
namespace content {
class NavigationThrottleRegistry;
class WebContents;
struct OpenURLParams;
}
namespace parc {
void AddNativeNoteLinkThrottle(content::NavigationThrottleRegistry& registry);
bool OpenNativeNoteLink(BrowserWindowInterface& browser, content::WebContents& source,
                        const content::OpenURLParams& params);
bool OpenNativeCreatedNoteLink(BrowserWindowInterface& browser, content::WebContents* source,
                               const GURL& url, WindowOpenDisposition disposition,
                               bool user_gesture);
}
#endif
