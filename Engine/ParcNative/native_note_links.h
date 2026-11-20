#ifndef PARC_NATIVE_NATIVE_NOTE_LINKS_H_
#define PARC_NATIVE_NATIVE_NOTE_LINKS_H_
class BrowserWindowInterface;
namespace content {
class NavigationThrottleRegistry;
class WebContents;
struct OpenURLParams;
}
namespace parc {
void AddNativeNoteLinkThrottle(content::NavigationThrottleRegistry& registry);
bool OpenNativeNoteLink(BrowserWindowInterface& browser, content::WebContents& source,
                        const content::OpenURLParams& params);
}
#endif
