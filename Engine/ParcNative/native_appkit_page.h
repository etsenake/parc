// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_APPKIT_PAGE_H_
#define PARC_NATIVE_NATIVE_APPKIT_PAGE_H_
#include <memory>

#include "base/functional/callback.h"
#import "native_appkit_bridge.h"
class BrowserWindowInterface;
class Profile;
namespace content {
class WebContents;
}
namespace parc {
class NativeChromePlatformDelegate;
// Call only for a native-routed, initialized CEF host. Same contents returns
// the same Objective-C identity. TabStripModel retains contents, not this API.
PCNativePage* GetOrCreateNativePage(content::WebContents& contents,
                                    NativeChromePlatformDelegate& platform,
                                    NSString* profile_path);
// Set only during native creation, before publishing the original page.
void MarkNativePageEmbedded(PCNativePage* page);
// Only the actual original-page transfer callback may update an auxiliary
// Browser/window lease. Same page/Profile and real TabInterface are required.
bool RebindNativeEmbeddedPageForTransfer(PCNativePage* page,
                                        BrowserWindowInterface& expected_owner,
                                        BrowserWindowInterface& destination);
content::WebContents* ContentsForNativePage(PCNativePage* page);
PCNativePage* ExistingNativePage(content::WebContents* contents);
// Exact attached/selected/live page, native responder and shell presentation.
bool CanNativePageHistorySwipe(PCNativePage* page);
void NotifyNativePageChanged(content::WebContents* contents);
void RequestNativeRendererCrashFocus(content::WebContents* contents,
                                     PCNativeRendererCrash* crash);
void UpdateNativePageStatusText(content::WebContents& contents, NSString* text);
void SetNativePageStatusAttached(content::WebContents& contents, bool attached);
void NotifyNativePageCloseCancelled(content::WebContents* contents);
void SetNativePageClosedCallback(PCNativePage* page,
                                 base::OnceClosure callback);
// New contents holding a -captureNavigationState value's entries, restored
// and ready to insert and load. Null unless `profile` is the Profile they
// were captured from.
std::unique_ptr<content::WebContents> CreateRestoredContents(
    NSObject* state, Profile& profile, bool initially_hidden);
}  // namespace parc
#endif
