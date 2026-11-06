// Installed by the reviewed overlay at
// //content/browser/media/parc_fairplay_hooks.h. Defined in
// media_interface_proxy.cc (content component, hence CONTENT_EXPORT).
//
// Lets Parc keep a frame from creating a Widevine CDM, e.g. while it decides
// whether the site belongs on FairPlay instead. The observer runs on the UI
// thread from MediaInterfaceProxy::CreateCdm for "com.widevine.alpha" and its
// sub key systems only. Returning true holds that CDM creation pending: the
// request is never answered and is dropped with the frame's document.
// Returning false lets it continue unchanged.
#ifndef CONTENT_BROWSER_MEDIA_PARC_FAIRPLAY_HOOKS_H_
#define CONTENT_BROWSER_MEDIA_PARC_FAIRPLAY_HOOKS_H_

#include <string>

#include "base/functional/callback.h"
#include "content/common/content_export.h"

namespace content {
class RenderFrameHost;
}  // namespace content

namespace parc::fairplay {

using WidevineCdmRequestObserver =
    base::RepeatingCallback<bool(content::RenderFrameHost* frame,
                                 const std::string& key_system)>;

// Installs |observer|, replacing any earlier one; a null callback removes it.
// Call on the UI thread, or before the browser threads start.
CONTENT_EXPORT void SetWidevineCdmRequestObserver(
    WidevineCdmRequestObserver observer);

}  // namespace parc::fairplay

#endif  // CONTENT_BROWSER_MEDIA_PARC_FAIRPLAY_HOOKS_H_
