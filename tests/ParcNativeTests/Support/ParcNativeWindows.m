#import "ParcNativeWindows.h"
#import "ParcNativePresentation.h"

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

#undef NSPopover

@interface ParcNativeWindowState : NSObject
@property BOOL visible;
@property(weak) NSWindow* sheetOwner;
@property(weak) NSWindow* parent;
@property(strong) NSWindow* sheet;
@property(copy) void (^completion)(NSModalResponse);
@property(strong) NSMutableArray<NSWindow*>* children;
@end
@implementation ParcNativeWindowState
@end

static ParcNativeWindowState* State(NSWindow* window) {
  ParcNativeWindowState* state = objc_getAssociatedObject(window, @selector(parcAttachedSheet));
  if (!state && window) {
    state = [ParcNativeWindowState new];
    objc_setAssociatedObject(window, @selector(parcAttachedSheet), state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  }
  return state;
}

static BOOL (*realIsVisible)(id, SEL);

BOOL ParcNativeWindowOrderedForReal(NSWindow* window) {
  return realIsVisible(window, @selector(isVisible));
}

void ParcNativeMarkVisible(NSWindow* window) {
  State(window).visible = YES;
}

NSWindow* ParcNativeOffscreenWindow(NSRect frame, NSWindowStyleMask style) {
  NSWindow* window = [[NSWindow alloc] initWithContentRect:frame styleMask:style
                                                   backing:NSBackingStoreBuffered defer:YES];
  window.releasedWhenClosed = NO;
  return window;
}

@implementation NSWindow (ParcNativePresentation)
- (NSWindow*)parcAttachedSheet { return State(self).sheet; }
- (NSWindow*)parcSheetParent { return State(self).sheetOwner; }
- (NSWindow*)parcParentWindow { return State(self).parent; }
- (NSArray<NSWindow*>*)parcChildWindows { return [State(self).children copy]; }

- (void)parcBeginSheet:(NSWindow*)sheet completionHandler:(void (^)(NSModalResponse))completion {
  ParcNativeWindowState* state = State(self);
  NSAssert(!state.sheet, @"A sheet is already attached");
  state.sheet = sheet;
  state.completion = completion;
  State(sheet).sheetOwner = self;
  State(sheet).visible = state.visible;
  [NSNotificationCenter.defaultCenter postNotificationName:NSWindowWillBeginSheetNotification object:self];
  [sheet.contentView layoutSubtreeIfNeeded];
  if (sheet.initialFirstResponder) [sheet makeFirstResponder:sheet.initialFirstResponder];
}
- (void)parcEndSheet:(NSWindow*)sheet {
  [self parcEndSheet:sheet returnCode:NSModalResponseStop];
}
- (void)parcEndSheet:(NSWindow*)sheet returnCode:(NSModalResponse)code {
  ParcNativeWindowState* state = State(self);
  if (!sheet || state.sheet != sheet) return;
  void (^completion)(NSModalResponse) = state.completion;
  state.completion = nil;
  state.sheet = nil;
  State(sheet).sheetOwner = nil;
  State(sheet).visible = NO;
  [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidEndSheetNotification object:self];
  if (completion) completion(code);
}
- (void)parcAddChildWindow:(NSWindow*)child ordered:(NSWindowOrderingMode)place {
  ParcNativeWindowState* state = State(self);
  if (!state.children) state.children = [NSMutableArray array];
  [state.children addObject:child];
  State(child).parent = self;
}
- (void)parcRemoveChildWindow:(NSWindow*)child {
  [State(self).children removeObject:child];
  State(child).parent = nil;
}
- (void)parcOrderFront:(id)sender { ParcNativeMarkVisible(self); }
- (void)parcMakeKeyAndOrderFront:(id)sender {
  ParcNativeMarkVisible(self);
  [self parcMakeKeyWindow];
}
- (void)parcMakeKeyWindow {
  if (self.canBecomeKeyWindow) {
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidBecomeKeyNotification object:self];
  }
}
- (void)parcOrderOut:(id)sender { State(self).visible = NO; }
@end

@implementation NSApplication (ParcNativePresentation)
- (void)parcEndSheet:(NSWindow*)sheet {
  [sheet.parcSheetParent parcEndSheet:sheet];
}
@end

@implementation SFCertificatePanel (ParcNativePresentation)
- (void)parcBeginSheetForWindow:(NSWindow*)window modalDelegate:(id)delegate didEndSelector:(SEL)end
                    contextInfo:(void*)context certificates:(NSArray*)certificates showGroup:(BOOL)group {
  SFCertificatePanel* sheet = [SFCertificatePanel new];
  __weak id target = delegate;
  [window parcBeginSheet:sheet completionHandler:^(NSModalResponse code) {
    ((void (*)(id, SEL, NSWindow*, NSInteger, void*))objc_msgSend)(target, end, sheet, code, context);
  }];
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
  ParcNativeMarkVisible(_host);
}
- (BOOL)isShown { return _host != nil; }
- (void)close {
  if (!_host) return;
  [_host close];
  _host = nil;
  if ([self.delegate respondsToSelector:@selector(popoverDidClose:)]) {
    [self.delegate popoverDidClose:[NSNotification notificationWithName:NSPopoverDidCloseNotification object:self]];
  }
}
@end

__attribute__((constructor)) static void InstallParcNativeVisibility(void) {
  Dl_info bundle;
  dladdr((void*)&InstallParcNativeVisibility, &bundle);
  Method visible = class_getInstanceMethod(NSWindow.class, @selector(isVisible));
  realIsVisible = (BOOL (*)(id, SEL))method_getImplementation(visible);
  method_setImplementation(visible, imp_implementationWithBlock(^BOOL(NSWindow* window) {
    ParcNativeWindowState* state = objc_getAssociatedObject(window, @selector(parcAttachedSheet));
    Dl_info caller;
    if (state && dladdr(__builtin_return_address(0), &caller) && caller.dli_fbase == bundle.dli_fbase) {
      return state.visible;
    }
    return realIsVisible(window, @selector(isVisible));
  }));
  Method close = class_getInstanceMethod(NSWindow.class, @selector(close));
  IMP original = method_getImplementation(close);
  method_setImplementation(close, imp_implementationWithBlock(^(NSWindow* window) {
    ParcNativeWindowState* state = objc_getAssociatedObject(window, @selector(parcAttachedSheet));
    state.visible = NO;
    ((void (*)(id, SEL))original)(window, @selector(close));
    if (state.sheet) [window parcEndSheet:state.sheet returnCode:NSModalResponseAbort];
  }));
}
