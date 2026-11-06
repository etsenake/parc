// Copyright 2026 Parc contributors.
#ifndef CEF_LIBCEF_BROWSER_PARC_NATIVE_SAD_TAB_H_
#define CEF_LIBCEF_BROWSER_PARC_NATIVE_SAD_TAB_H_
#include "base/functional/callback.h"
#import "native_appkit_bridge.h"
namespace content {
class WebContents;
}
namespace parc {
// Installed before tab insertion. Real SadTabHelper remains the only producer
// and reset authority. State belongs to contents, even before a page wrapper.
// is_attached is the exact platform attachment predicate, weakly bound. It is
// read-only and does not pump callbacks; hidden crash renderers remain
// eligible.
void InstallNativeSadTab(content::WebContents& contents,
                         base::RepeatingCallback<bool()> is_attached);
PCNativeRendererCrash* NativeRendererCrash(content::WebContents* contents);
bool NativeRendererCrashDidPresent(content::WebContents* contents,
                                   PCNativeRendererCrash* crash);
bool PerformNativeRendererCrashAction(content::WebContents* contents,
                                      PCNativeRendererCrash* crash);
// True consumes focus while an actual native SadTab exists, even if its shell
// observer is absent. Never falls through to the hidden renderer.
bool FocusNativeRendererCrash(content::WebContents* contents);
}  // namespace parc
#endif
