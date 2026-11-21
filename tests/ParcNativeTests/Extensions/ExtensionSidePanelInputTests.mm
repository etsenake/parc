#import "extension_side_panel_input.h"
#import "ParcNativeTest.h"
#include <cstdio>
#include <cstdlib>
#include <initializer_list>
@interface PanelInputWindow : NSWindow
@property BOOL keyForTest;
@end
@implementation PanelInputWindow
- (BOOL)isKeyWindow { return self.keyForTest; }
@end
#define EXPECT(condition) PARC_CHECK(condition)
static NSEvent* Key(NSWindow* window, unsigned short code,
                    NSEventModifierFlags modifiers = 0,
                    NSEventType type = NSEventTypeKeyDown) {
  return [NSEvent keyEventWithType:type location:NSZeroPoint
      modifierFlags:modifiers timestamp:0 windowNumber:window.windowNumber
      context:nil characters:@"\033" charactersIgnoringModifiers:@"\033"
      isARepeat:NO keyCode:code];
}
@interface ExtensionSidePanelInputTests : ParcNativeTestCase
@end

static PanelInputWindow* MakeWindow() {
  auto* window = [[PanelInputWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 400)
                                                     styleMask:NSWindowStyleMaskBorderless
                                                       backing:NSBackingStoreBuffered
                                                         defer:NO];
  window.releasedWhenClosed = NO;
  return window;
}

@implementation ExtensionSidePanelInputTests {
  PanelInputWindow* _original;
  PanelInputWindow* _other;
  NSView* _scope;
  NSView* _page;
  NSButton* _close;
  NSTextField* _field;
  NSTextField* _outside;
}

- (void)setUp {
  [super setUp];
  _original = MakeWindow();
  _other = MakeWindow();
  _original.keyForTest = YES;
  _scope = [[NSView alloc] initWithFrame:NSMakeRect(200, 0, 300, 400)];
  _page = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 368)];
  _close = [[NSButton alloc] initWithFrame:NSMakeRect(260, 370, 32, 24)];
  _field = [[NSTextField alloc] initWithFrame:NSMakeRect(5, 5, 100, 24)];
  _outside = [[NSTextField alloc] initWithFrame:NSMakeRect(5, 5, 100, 24)];
  [_original.contentView addSubview:_scope];
  [_scope addSubview:_page];
  [_scope addSubview:_close];
  [_page addSubview:_field];
  [_original.contentView addSubview:_outside];
}

- (void)tearDown {
  [_original close];
  [_other close];
  [super tearDown];
}

- (void)testEscapeInTheKeyPanelWindowDismisses {
  NSEvent* escape = Key(_original, 53);
  EXPECT(escape.window == _original);
  EXPECT(NativeExtensionSidePanelDismissesForKey(escape, _original));
}

- (void)testEscapeFromAnotherWindowOrAnotherKeyDoesNotDismiss {
  EXPECT(!NativeExtensionSidePanelDismissesForKey(Key(_original, 53), _other));
  EXPECT(!NativeExtensionSidePanelDismissesForKey(Key(_other, 53), _original));
  EXPECT(!NativeExtensionSidePanelDismissesForKey(Key(_original, 36), _original));
  EXPECT(!NativeExtensionSidePanelDismissesForKey(Key(_original, 53, 0, NSEventTypeKeyUp), _original));
}

- (void)testCommandEscapeKeepsThePanelOpen {
  EXPECT(!NativeExtensionSidePanelDismissesForKey(Key(_original, 53, NSEventModifierFlagCommand), _original));
}

- (void)testControlEscapeKeepsThePanelOpen {
  EXPECT(!NativeExtensionSidePanelDismissesForKey(Key(_original, 53, NSEventModifierFlagControl), _original));
}

- (void)testOptionEscapeKeepsThePanelOpen {
  EXPECT(!NativeExtensionSidePanelDismissesForKey(Key(_original, 53, NSEventModifierFlagOption), _original));
}

- (void)testShiftEscapeKeepsThePanelOpen {
  EXPECT(!NativeExtensionSidePanelDismissesForKey(Key(_original, 53, NSEventModifierFlagShift), _original));
}

- (void)testCapsLockEscapeDismissesThePanel {
  EXPECT(NativeExtensionSidePanelDismissesForKey(Key(_original, 53, NSEventModifierFlagCapsLock), _original));
}

- (void)testANonKeyWindowOrMissingInputDoesNotDismiss {
  NSEvent* escape = Key(_original, 53);
  _original.keyForTest = NO;
  EXPECT(!NativeExtensionSidePanelDismissesForKey(escape, _original));
  EXPECT(!NativeExtensionSidePanelDismissesForKey(nil, _original));
  EXPECT(!NativeExtensionSidePanelDismissesForKey(escape, nil));
}

- (void)testThePanelOwnsFocusInsideItsPageAndChrome {
  EXPECT(NativeExtensionSidePanelOwnsFocus(_page, _scope, _field, _original));
  EXPECT(NativeExtensionSidePanelOwnsFocus(_page, _scope, _close, _original));
}

- (void)testThePanelDoesNotOwnFocusOutsideItsScopeOrWindow {
  EXPECT(!NativeExtensionSidePanelOwnsFocus(_page, _scope, _outside, _original));
  EXPECT(!NativeExtensionSidePanelOwnsFocus(_page, _page, _close, _original));
  EXPECT(!NativeExtensionSidePanelOwnsFocus(_page, _scope, _close, _other));
  EXPECT(!NativeExtensionSidePanelOwnsFocus(_page, _scope, nil, _original));
  EXPECT(!NativeExtensionSidePanelOwnsFocus(_page, nil, _close, _original));
  EXPECT(!NativeExtensionSidePanelOwnsFocus(_page, _scope, _close, nil));
}

- (void)testADetachedPageOwnsNoFocus {
  [_page removeFromSuperview];
  EXPECT(!NativeExtensionSidePanelOwnsFocus(_page, _scope, _close, _original));
}

@end
