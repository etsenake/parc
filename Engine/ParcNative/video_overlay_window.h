// Copyright 2026 Parc contributors.
#ifndef CEF_LIBCEF_BROWSER_PARC_NATIVE_VIDEO_OVERLAY_WINDOW_H_
#define CEF_LIBCEF_BROWSER_PARC_NATIVE_VIDEO_OVERLAY_WINDOW_H_
#include <memory>
#ifdef __OBJC__
#import "parc/native/native_appkit_bridge.h"
#endif
namespace content {
class WebContents;
class VideoOverlayWindow;
class VideoPictureInPictureWindowController;
}  // namespace content
namespace parc {
bool CanCreateNativeVideoPiPWindow();
#ifdef __OBJC__
// Retain the creating application client until its exact window is released;
// replacing the process application client cannot redirect old-window cleanup.
id<PCNativeVideoPiPWindow> CreateAppKitVideoPiPWindow(
    NSView*,
    NSRect,
    void (^)(PCVideoPiPAction, double),
    dispatch_block_t,
    id<PCNativeBrowserApplicationClient> __strong* owner);
void ReleaseAppKitVideoPiPWindow(id<PCNativeVideoPiPWindow>,
                                 id<PCNativeBrowserApplicationClient> owner);
#endif
// Exact real native Browser/tab ownership; never inferred from profile alone.
bool UsesNativeVideoPictureInPicture(content::WebContents* contents);
std::unique_ptr<content::VideoOverlayWindow> CreateNativeVideoOverlayWindow(
    content::VideoPictureInPictureWindowController* controller);
}  // namespace parc
#endif
