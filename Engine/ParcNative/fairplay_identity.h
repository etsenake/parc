// Copyright 2026 Parc contributors.
// Safari's identity for the sites that need Apple FairPlay, Chrome's
// everywhere else (docs/fairplay-identity.md). Each native page's contents
// carry Safari's user agent as their override; every navigation then decides,
// from its frame's site and the Profile's site lists, whether the new
// document uses it. Under that override Chromium sends Safari's User-Agent and
// no UA client hints, and the renderer reports Safari's user agent, vendor,
// no navigator.userAgentData and no Widevine
// (third_party/blink/renderer/core/frame/parc_safari_identity.h). Service and
// shared workers of a Safari site start with the same user agent.
#ifndef CEF_LIBCEF_BROWSER_PARC_NATIVE_FAIRPLAY_IDENTITY_H_
#define CEF_LIBCEF_BROWSER_PARC_NATIVE_FAIRPLAY_IDENTITY_H_

#import <Foundation/Foundation.h>

namespace content {
class WebContents;
}

namespace parc {

// Reads the installed Safari's version for the user agent and installs the
// worker hook. Once, on the main thread, before CefInitialize.
void InstallFairPlayIdentity();

// Gives a native page's contents their per-site identity. Idempotent; call
// before the contents load anything the identity should apply to.
void AttachFairPlayIdentity(content::WebContents& contents);

// Tells the shell's application client that the engine learned `site` for the
// browsing context of the Profile at `profile_path` (its private context with
// `off_the_record`). Defined in native_appkit_application.mm, which owns the
// client. Main thread only.
void NotifyNativeApplicationLearnedSafariIdentity(NSString* site,
                                                  NSString* profile_path,
                                                  bool off_the_record);

}  // namespace parc

#endif  // CEF_LIBCEF_BROWSER_PARC_NATIVE_FAIRPLAY_IDENTITY_H_
