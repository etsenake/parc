#import "ParcNativeWindows.h"

#import <objc/runtime.h>

@interface ParcNativeWindowState : NSObject
@property(weak) ParcNativeTestPresentation* owner;
@property BOOL visible;
@property(weak) NSWindow* sheetOwner;
@property(weak) NSWindow* parent;
@property(strong) NSWindow* sheet;
@property(copy) void (^completion)(NSModalResponse);
@property(strong) NSMutableArray<NSWindow*>* children;
@end
@implementation ParcNativeWindowState
@end

@interface ParcNativePopover : NSPopover
@property(weak) ParcNativeTestPresentation* presentation;
@end

static char kParcNativeWindowState;

@implementation ParcNativeTestPresentation
@synthesize willBeginSheet = _willBeginSheet;
@synthesize didBeginSheet = _didBeginSheet;

- (ParcNativeWindowState*)existingState:(NSWindow*)window {
  ParcNativeWindowState* state = window ? objc_getAssociatedObject(window, &kParcNativeWindowState) : nil;
  return state.owner == self ? state : nil;
}

- (ParcNativeWindowState*)state:(NSWindow*)window {
  if (!window) return nil;
  ParcNativeWindowState* state = [self existingState:window];
  if (!state) {
    state = [ParcNativeWindowState new];
    state.owner = self;
    objc_setAssociatedObject(window, &kParcNativeWindowState, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  }
  return state;
}

- (void)markVisible:(NSWindow*)window {
  [self state:window].visible = YES;
}

- (NSWindow*)attachedSheetOfWindow:(NSWindow*)window {
  return [self state:window].sheet;
}

- (NSWindow*)sheetParentOfWindow:(NSWindow*)window {
  return [self state:window].sheetOwner;
}

- (NSWindow*)parentWindowOfWindow:(NSWindow*)window {
  return [self state:window].parent;
}

- (NSArray<NSWindow*>*)childWindowsOfWindow:(NSWindow*)window {
  return [[self state:window].children copy];
}

- (BOOL)isWindowVisible:(NSWindow*)window {
  ParcNativeWindowState* state = [self existingState:window];
  return state ? state.visible : window.visible;
}

- (void)window:(NSWindow*)window
           beginSheet:(NSWindow*)sheet
    completionHandler:(void (^)(NSModalResponse))completion {
  if (window && self.willBeginSheet) self.willBeginSheet(window, sheet);
  ParcNativeWindowState* state = [self state:window];
  if (!state) return;
  NSAssert(!state.sheet, @"A sheet is already attached");
  state.sheet = sheet;
  state.completion = completion;
  [self state:sheet].sheetOwner = window;
  [self state:sheet].visible = state.visible;
  [NSNotificationCenter.defaultCenter postNotificationName:NSWindowWillBeginSheetNotification object:window];
  [sheet.contentView layoutSubtreeIfNeeded];
  if (sheet.initialFirstResponder) [sheet makeFirstResponder:sheet.initialFirstResponder];
  if (self.didBeginSheet) self.didBeginSheet(window, sheet);
}

- (void)window:(NSWindow*)window endSheet:(NSWindow*)sheet {
  [self window:window endSheet:sheet returnCode:NSModalResponseStop];
}

- (void)window:(NSWindow*)window endSheet:(NSWindow*)sheet returnCode:(NSModalResponse)code {
  ParcNativeWindowState* state = [self state:window];
  if (!sheet || state.sheet != sheet) return;
  void (^completion)(NSModalResponse) = state.completion;
  state.completion = nil;
  state.sheet = nil;
  [self state:sheet].sheetOwner = nil;
  [self state:sheet].visible = NO;
  [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidEndSheetNotification object:window];
  if (completion) completion(code);
}

- (void)endApplicationSheet:(NSWindow*)sheet {
  [self window:[self sheetParentOfWindow:sheet] endSheet:sheet];
}

- (void)window:(NSWindow*)window
    addChildWindow:(NSWindow*)child
           ordered:(NSWindowOrderingMode)place {
  ParcNativeWindowState* state = [self state:window];
  if (!state) return;
  if (!state.children) state.children = [NSMutableArray array];
  [state.children addObject:child];
  [self state:child].parent = window;
}

- (void)window:(NSWindow*)window removeChildWindow:(NSWindow*)child {
  if (!window) return;
  [[self state:window].children removeObject:child];
  [self state:child].parent = nil;
}

- (void)orderFrontWindow:(NSWindow*)window {
  [self markVisible:window];
}

- (void)makeKeyAndOrderFrontWindow:(NSWindow*)window {
  [self markVisible:window];
  [self makeKeyWindow:window];
}

- (void)makeKeyWindow:(NSWindow*)window {
  if (window.canBecomeKeyWindow) {
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidBecomeKeyNotification object:window];
  }
}

- (void)orderOutWindow:(NSWindow*)window {
  [self state:window].visible = NO;
}

- (void)closeWindow:(NSWindow*)window {
  ParcNativeWindowState* state = [self existingState:window];
  state.visible = NO;
  [window close];
  if (state.sheet) [self window:window endSheet:state.sheet returnCode:NSModalResponseAbort];
}

- (NSPopover*)makePopover {
  ParcNativePopover* popover = [ParcNativePopover new];
  popover.presentation = self;
  return popover;
}

@end

@implementation ParcNativePopoverWindow
- (void)cancelOperation:(id)sender { [self.popover close]; }
@end

@implementation ParcNativePopover {
  ParcNativePopoverWindow* _host;
}
- (void)showRelativeToRect:(NSRect)rect ofView:(NSView*)view preferredEdge:(NSRectEdge)edge {
  _host = [[ParcNativePopoverWindow alloc] initWithContentRect:(NSRect){NSZeroPoint, self.contentSize}
                                                     styleMask:NSWindowStyleMaskBorderless
                                                       backing:NSBackingStoreBuffered defer:YES];
  _host.releasedWhenClosed = NO;
  _host.popover = self;
  _host.anchorView = view;
  _host.anchorRect = rect;
  _host.anchorEdge = edge;
  _host.contentView = self.contentViewController.view;
  [_host.contentView layoutSubtreeIfNeeded];
  [self.presentation markVisible:_host];
}
- (BOOL)isShown { return _host != nil; }
- (void)close {
  if (!_host) return;
  [self.presentation closeWindow:_host];
  _host = nil;
  if ([self.delegate respondsToSelector:@selector(popoverDidClose:)]) {
    [self.delegate popoverDidClose:[NSNotification notificationWithName:NSPopoverDidCloseNotification object:self]];
  }
}
@end

NSWindow* ParcNativeOffscreenWindow(NSRect frame, NSWindowStyleMask style) {
  NSWindow* window = [[NSWindow alloc] initWithContentRect:frame styleMask:style
                                                   backing:NSBackingStoreBuffered defer:YES];
  window.releasedWhenClosed = NO;
  return window;
}

void ParcNativeMarkVisible(NSWindow* window) { [ParcNativePresentation() markVisible:window]; }
BOOL ParcNativeVisible(NSWindow* window) { return [ParcNativePresentation() isWindowVisible:window]; }
NSWindow* ParcNativeAttachedSheet(NSWindow* window) { return [ParcNativePresentation() attachedSheetOfWindow:window]; }
NSWindow* ParcNativeSheetParent(NSWindow* window) { return [ParcNativePresentation() sheetParentOfWindow:window]; }
NSWindow* ParcNativeParentWindow(NSWindow* window) { return [ParcNativePresentation() parentWindowOfWindow:window]; }
NSArray<NSWindow*>* ParcNativeChildWindows(NSWindow* window) {
  return [ParcNativePresentation() childWindowsOfWindow:window];
}
void ParcNativeBeginSheet(NSWindow* window, NSWindow* sheet, void (^completion)(NSModalResponse)) {
  [ParcNativePresentation() window:window beginSheet:sheet completionHandler:completion];
}
void ParcNativeEndSheet(NSWindow* window, NSWindow* sheet) {
  [ParcNativePresentation() window:window endSheet:sheet];
}
void ParcNativeEndSheetWithCode(NSWindow* window, NSWindow* sheet, NSModalResponse code) {
  [ParcNativePresentation() window:window endSheet:sheet returnCode:code];
}
void ParcNativeOrderOut(NSWindow* window) { [ParcNativePresentation() orderOutWindow:window]; }
void ParcNativeMakeKey(NSWindow* window) { [ParcNativePresentation() makeKeyWindow:window]; }
void ParcNativeClose(NSWindow* window) { [ParcNativePresentation() closeWindow:window]; }
