// Installed by the reviewed overlay at
// //content/browser/media/parc_fairplay_hooks.h. Defined in
// media_interface_proxy.cc (content component, hence CONTENT_EXPORT).
//
// Lets Parc keep a frame from creating a Widevine CDM, e.g. while it decides
// whether the site belongs on FairPlay instead, and tell which documents
// present Safari's identity. The observer runs on the UI
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

// Whether |frame|'s current document presents Safari's identity. Such a
// document may create FairPlay Renderers without a FairPlay CDM: Safari plays
// Dolby Vision in Media Source with keys or without, and in Parc only that
// renderer decodes it. Asked on the UI thread from
// MediaInterfaceProxy::CreateFairPlayRenderer; without a query, no document
// presents it.
using SafariIdentityQuery =
    base::RepeatingCallback<bool(content::RenderFrameHost* frame)>;

// Installs |query|, replacing any earlier one; a null callback removes it.
// Call on the UI thread, or before the browser threads start.
CONTENT_EXPORT void SetSafariIdentityQuery(SafariIdentityQuery query);

}  // namespace parc::fairplay

#endif  // CONTENT_BROWSER_MEDIA_PARC_FAIRPLAY_HOOKS_H_
