// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_SHORTCUTS_H_
#define PARC_NATIVE_NATIVE_SHORTCUTS_H_
#include <optional>
#import <AppKit/AppKit.h>
#include "content/public/browser/keyboard_event_processing_result.h"
class BrowserWindowInterface;
namespace content { class WebContents; }
namespace input { struct NativeWebKeyboardEvent; }
namespace parc {
// Called after Chromium's exclusive-access pre-handler. Only the actual
// selected, focused page can choose a registered shell command before Blink.
content::KeyboardEventProcessingResult PreHandleNativeShortcut(
    BrowserWindowInterface&, const input::NativeWebKeyboardEvent&);
// nullopt preserves the ordinary menu fallback. false declines a known but
// stale/protected transaction without executing its menu item; the original
// delegate still receives the event for DevTools and extension commands.
std::optional<bool> HandleUnhandledNativeShortcut(content::WebContents&, NSEvent*);
}  // namespace parc
#endif
