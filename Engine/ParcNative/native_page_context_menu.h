// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_PAGE_CONTEXT_MENU_H_
#define PARC_NATIVE_PAGE_CONTEXT_MENU_H_
#include <memory>
class RenderViewContextMenu;
class RenderViewContextMenuObserver;
namespace parc {
// Installs the Cocoa presenter's implementation-only hook.
void RegisterNativePageContextMenu();
// No observer is returned for non-native pages. The real context menu owns it.
std::unique_ptr<RenderViewContextMenuObserver> CreateNativePageContextMenuObserver(
    RenderViewContextMenu* menu);
}
#ifdef __OBJC__
#import <AppKit/AppKit.h>
@class MenuControllerCocoa;
namespace parc {
// True consumes the native route, including stale-page refusal. The actual
// RenderViewContextMenu retains the controller for normal cancel/update APIs.
bool ShowNativePageContextMenu(RenderViewContextMenu& menu, NSView* parent,
                              MenuControllerCocoa* __strong* controller);
}
#endif
#endif
