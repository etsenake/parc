// Copyright 2026 Parc contributors.
#ifndef CEF_LIBCEF_BROWSER_PARC_NATIVE_SAD_TAB_H_
#define CEF_LIBCEF_BROWSER_PARC_NATIVE_SAD_TAB_H_
#include <memory>

#include "base/functional/callback.h"
#include "chrome/browser/ui/sad_tab_types.h"
class SadTab;
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
// SadTab::Create for every page: installed pages get the native sad tab, any
// other page Chromium's Views one. It must not pump callbacks: SadTabHelper
// has not assigned the returned instance yet.
std::unique_ptr<SadTab> CreateSadTab(content::WebContents* contents,
                                     SadTabKind kind);
// True consumes focus while an actual native SadTab exists, even if its shell
// observer is absent. Never falls through to the hidden renderer.
bool FocusNativeRendererCrash(content::WebContents* contents);
}  // namespace parc
#ifdef __OBJC__
#import "native_appkit_bridge.h"
namespace parc {
PCNativeRendererCrash* NativeRendererCrash(content::WebContents* contents);
bool NativeRendererCrashDidPresent(content::WebContents* contents,
                                   PCNativeRendererCrash* crash);
bool PerformNativeRendererCrashAction(content::WebContents* contents,
                                      PCNativeRendererCrash* crash);
}  // namespace parc
#endif
#endif
