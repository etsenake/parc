// Inert AppKit event-admission checks. No renderer, Browser or activation.
#import "extension_side_panel_input.h"
#include <cstdio>
#include <cstdlib>
#include <initializer_list>
@interface PanelInputWindow : NSWindow
@property BOOL keyForTest;
@end
@implementation PanelInputWindow
- (BOOL)isKeyWindow { return self.keyForTest; }
@end
static int assertions = 0;
#define EXPECT(x) do { ++assertions; if (!(x)) { \
  fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); exit(1); } } while (0)
static NSEvent* Key(NSWindow* window, unsigned short code,
                    NSEventModifierFlags modifiers = 0,
                    NSEventType type = NSEventTypeKeyDown) {
  return [NSEvent keyEventWithType:type location:NSZeroPoint
      modifierFlags:modifiers timestamp:0 windowNumber:window.windowNumber
      context:nil characters:@"\033" charactersIgnoringModifiers:@"\033"
      isARepeat:NO keyCode:code];
}
int main() {
  @autoreleasepool {
    [NSApplication sharedApplication];
    auto make = [] {
      auto* window = [[PanelInputWindow alloc]
          initWithContentRect:NSMakeRect(0, 0, 500, 400)
          styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered
          defer:NO];
      window.releasedWhenClosed = NO;
      return window;
    };
    PanelInputWindow* original = make();
    PanelInputWindow* other = make();
    original.keyForTest = YES;
    NSEvent* escape = Key(original, 53);
    EXPECT(escape.window == original);
    EXPECT(NativeExtensionSidePanelDismissesForKey(escape, original));
    EXPECT(!NativeExtensionSidePanelDismissesForKey(escape, other));
    EXPECT(!NativeExtensionSidePanelDismissesForKey(Key(other, 53), original));
    EXPECT(!NativeExtensionSidePanelDismissesForKey(Key(original, 36), original));
    EXPECT(!NativeExtensionSidePanelDismissesForKey(
        Key(original, 53, 0, NSEventTypeKeyUp), original));
    for (auto modifier : {NSEventModifierFlagCommand, NSEventModifierFlagControl,
                          NSEventModifierFlagOption, NSEventModifierFlagShift})
      EXPECT(!NativeExtensionSidePanelDismissesForKey(
          Key(original, 53, modifier), original));
    // Caps Lock does not turn plain Escape into a shell shortcut.
    EXPECT(NativeExtensionSidePanelDismissesForKey(
        Key(original, 53, NSEventModifierFlagCapsLock), original));
    original.keyForTest = NO;
    EXPECT(!NativeExtensionSidePanelDismissesForKey(escape, original));
    EXPECT(!NativeExtensionSidePanelDismissesForKey(nil, original));
    EXPECT(!NativeExtensionSidePanelDismissesForKey(escape, nil));
    NSView* scope = [[NSView alloc] initWithFrame:NSMakeRect(200, 0, 300, 400)];
    NSView* page = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 368)];
    NSButton* close = [[NSButton alloc] initWithFrame:NSMakeRect(260, 370, 32, 24)];
    NSTextField* field = [[NSTextField alloc] initWithFrame:NSMakeRect(5, 5, 100, 24)];
    NSTextField* outside = [[NSTextField alloc] initWithFrame:NSMakeRect(5, 5, 100, 24)];
    [original.contentView addSubview:scope];
    [scope addSubview:page];
    [scope addSubview:close];
    [page addSubview:field];
    [original.contentView addSubview:outside];
    EXPECT(NativeExtensionSidePanelOwnsFocus(page, scope, field, original));
    EXPECT(NativeExtensionSidePanelOwnsFocus(page, scope, close, original));
    EXPECT(!NativeExtensionSidePanelOwnsFocus(page, scope, outside, original));
    EXPECT(!NativeExtensionSidePanelOwnsFocus(page, page, close, original));
    EXPECT(!NativeExtensionSidePanelOwnsFocus(page, scope, close, other));
    EXPECT(!NativeExtensionSidePanelOwnsFocus(page, scope, nil, original));
    EXPECT(!NativeExtensionSidePanelOwnsFocus(page, nil, close, original));
    EXPECT(!NativeExtensionSidePanelOwnsFocus(page, scope, close, nil));
    [page removeFromSuperview];
    EXPECT(!NativeExtensionSidePanelOwnsFocus(page, scope, close, original));
    [original close];
    [other close];
    printf("PASS %d side-panel input assertions\n", assertions);
  }
}
