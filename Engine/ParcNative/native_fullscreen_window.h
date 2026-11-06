// Copyright 2026 Parc contributors.
#ifndef CEF_LIBCEF_BROWSER_PARC_NATIVE_NATIVE_FULLSCREEN_WINDOW_H_
#define CEF_LIBCEF_BROWSER_PARC_NATIVE_NATIVE_FULLSCREEN_WINDOW_H_
#import <AppKit/AppKit.h>
#include <stdint.h>

namespace parc {
// One controller per supplied physical window. It owns neither the NSWindow
// nor a Browser/Profile and never replaces the application's NSWindowDelegate.
// All calls and final release are on the AppKit/Chromium UI thread.
extern NSNotificationName const kNativeFullscreenSettledNotification;
void InstallNativeFullscreenWindow(NSWindow* window);
bool HasNativeFullscreenWindow(NSWindow* window);
bool RequestNativeFullscreen(NSWindow* window, bool enter, int64_t display_id);
bool NativeFullscreenTransitioning(NSWindow* window);
NSRect NativeFullscreenRestoredFrame(NSWindow* window);
// Called by the existing association before forwarding a native notification.
// Multiple Profile associations may deliver the same notification; it is
// consumed once by the physical-window controller.
void HandleNativeFullscreenNotification(NSNotification* notification);
bool IsCurrentNativeFullscreenSettlement(NSNotification* notification);
// Actual NSWindowDelegate failure-to-enter only. Failed exits continue through
// AppKit's did-exit notification, matching the pinned macOS delegate contract.
void NativeFullscreenFailedToEnter(NSWindow* window);
}  // namespace parc
#endif
