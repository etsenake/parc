// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_EXTENSION_SIDE_PANEL_INPUT_H_
#define PARC_NATIVE_EXTENSION_SIDE_PANEL_INPUT_H_
#import <AppKit/AppKit.h>

// Called only after the real extension host declined this key and the panel
// session validated its original Browser/Profile/page/container identities.
inline bool NativeExtensionSidePanelDismissesForKey(NSEvent* event,
                                                   NSWindow* window) {
  const NSEventModifierFlags modifiers = NSEventModifierFlagCommand |
      NSEventModifierFlagControl | NSEventModifierFlagOption |
      NSEventModifierFlagShift;
  return event && window && window.keyWindow && event.window == window &&
         event.type == NSEventTypeKeyDown && event.keyCode == 53 &&
         !(event.modifierFlags & modifiers);
}

inline bool NativeExtensionSidePanelOwnsFocus(NSView* page, NSView* scope,
                                              NSResponder* responder,
                                              NSWindow* window) {
  return page && scope && window && scope.window == window &&
         page.window == window && [page isDescendantOf:scope] &&
         [responder isKindOfClass:NSView.class] &&
         [(NSView*)responder isDescendantOf:scope];
}
#endif
