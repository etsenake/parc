#include <cmath>
#include "../Support/TestFailure.h"
#include <cstdio>
#include <cstdlib>

#import "extension_popup_presenter.h"
#import "page_host.h"
static int assertions = 0;
#define EXPECT(x)                                                 \
  do {                                                            \
    ++assertions;                                                 \
    if (!(x)) {                                                   \
      fprintf(stderr, "FAIL %s:%d %s\n", __FILE__, __LINE__, #x); \
      exit(1);                                                    \
    }                                                             \
  } while (0)
@interface PageObserver : NSObject <PCNativePageHostObserver>
@property NSInteger detachCount;
@property(copy) void (^onDetach)(void);
@end
@implementation PageObserver
- (void)pageHost:(PCNativePageHost*)host didMoveToWindow:(NSWindow*)window {
  if (!window) {
    ++_detachCount;
    if (_onDetach) {
      _onDetach();
    }
  }
}
- (void)pageHostDidAttemptDeferredFocus:(PCNativePageHost*)host {
}
@end
@interface FlippedContentView : NSView
@end
@implementation FlippedContentView
- (BOOL)isFlipped {
  return YES;
}
@end
@interface PlacingController : NSWindowController <PCExtensionPopupPlacing>
@property(copy) NSString* extension;
@property(weak) NSWindow* popup;
@property NSSize size;
@property(strong) NSValue* origin;
@property NSInteger calls;
@end
@implementation PlacingController
- (NSValue*)parcExtensionPopupOriginForExtension:(NSString*)extensionID
                                           popup:(NSWindow*)popup
                                            size:(NSSize)size {
  ++_calls;
  _extension = [extensionID copy];
  _popup = popup;
  _size = size;
  return _origin;
}
@end
static NSWindow* Window() {
  NSWindow* result = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(100, 100, 900, 700)
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                  backing:NSBackingStoreBuffered
                    defer:NO];
  result.releasedWhenClosed = NO;
  return result;
}
static PCNativePageHost* Page(PageObserver* observer) {
  return [PCNativePageHost
      hostWithContentView:[[NSView alloc]
                              initWithFrame:NSMakeRect(0, 0, 80, 80)]
                 observer:observer];
}
static BOOL Near(CGFloat a, CGFloat b) {
  return std::abs(a - b) < .01;
}
static void Pump() {
  NSDate* end = [NSDate dateWithTimeIntervalSinceNow:.02];
  while (end.timeIntervalSinceNow > 0) {
    [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:end];
  }
}
int main() {
  ParcExitOnUncaughtExceptions();
  @autoreleasepool {
    [NSApplication sharedApplication];
    NSApp.activationPolicy = NSApplicationActivationPolicyAccessory;
    NSWindow* parent = Window();
    PageObserver* observer = [[PageObserver alloc] init];
    PCNativePageHost* page = Page(observer);
    NSView* original = page.contentView;
    __block int closes = 0;
    PCExtensionPopupPresenter* presenter =
        [[PCExtensionPopupPresenter alloc] initWithParentWindow:parent
            pageHost:page
            anchor:^{
              return [PCExtensionPopupAnchor windowAnchor];
            }
            mayDismissForParentKey:^{
              return YES;
            }
            onDismiss:^{
              ++closes;
            }];
    EXPECT([presenter prepare]);
    EXPECT(!presenter.presenting);
    NSWindow* popup = presenter.popupWindow;
    EXPECT(popup.parentWindow == nil);
    EXPECT(page.window == popup);
    EXPECT(page.contentView == original);
    EXPECT(page.superview == popup.contentView &&
           popup.contentViewController.view == popup.contentView);
    EXPECT(Near(page.bounds.size.width, 300));
    EXPECT(popup.styleMask ==
           (NSWindowStyleMaskTitled | NSWindowStyleMaskClosable));
    EXPECT(popup.tabbingMode == NSWindowTabbingModeDisallowed);
    EXPECT((popup.collectionBehavior &
            NSWindowCollectionBehaviorFullScreenAuxiliary) != 0);
    NSPoint expected = [parent
        convertPointToScreen:NSMakePoint(parent.frame.size.width -
                                             popup.frame.size.width - 40,
                                         parent.frame.size.height -
                                             popup.frame.size.height - 10)];
    EXPECT(Near(popup.frame.origin.x, expected.x));
    EXPECT(Near(popup.frame.origin.y, expected.y));
    EXPECT([presenter show]);
    EXPECT(presenter.presenting && popup.isVisible);
    EXPECT(popup.parentWindow == parent);
    [presenter invalidate];
    EXPECT(presenter.invalidated && !presenter.presenting);
    EXPECT(!page.window && page.contentView == original);
    EXPECT(popup.parentWindow == nil);
    EXPECT(closes == 0);
    EXPECT(![presenter show]);
    EXPECT(![presenter resizeContent:NSMakeSize(50, 50)]);
    [presenter invalidate];
    EXPECT(closes == 0);
    [page invalidate];
    page = Page(nil);
    __block PCExtensionPopupAnchor* anchor =
        [PCExtensionPopupAnchor sidebarAnchorWithWidth:200];
    presenter = [[PCExtensionPopupPresenter alloc] initWithParentWindow:parent
        pageHost:page
        anchor:^{
          return anchor;
        }
        mayDismissForParentKey:^{
          return YES;
        }
        onDismiss:^{
        }];
    EXPECT([presenter prepare]);
    popup = presenter.popupWindow;
    expected = [parent
        convertPointToScreen:NSMakePoint(40, parent.frame.size.height -
                                                 popup.frame.size.height - 10)];
    EXPECT(Near(popup.frame.origin.x, expected.x));
    NSView* pane = [[NSView alloc] initWithFrame:NSMakeRect(200, 50, 500, 450)];
    [parent.contentView addSubview:pane];
    anchor = [PCExtensionPopupAnchor focusedViewAnchor:pane];
    EXPECT([presenter resizeContent:NSMakeSize(180, 160)]);
    expected = [parent
        convertPointToScreen:NSMakePoint(NSMaxX(pane.frame) -
                                             popup.frame.size.width - 40,
                                         NSMaxY(pane.frame) -
                                             popup.frame.size.height - 10)];
    EXPECT(Near(popup.frame.origin.x, expected.x));
    EXPECT(Near(popup.frame.origin.y, expected.y));
    EXPECT(Near(page.bounds.size.width, 180));
    EXPECT(NSEqualRects(page.frame, page.superview.bounds));
    EXPECT(![presenter resizeContent:NSMakeSize(NAN, 10)]);
    [NSNotificationCenter.defaultCenter
        postNotificationName:NSWindowWillMoveNotification
                      object:popup];
    EXPECT(presenter.userHasMovedWindow);
    NSPoint origin = popup.frame.origin;
    EXPECT([presenter resizeContent:NSMakeSize(220, 160)]);
    EXPECT(Near(popup.frame.origin.x, origin.x));
    [presenter invalidate];
    [page invalidate];
    __block BOOL allow = NO;
    closes = 0;
    page = Page(nil);
    presenter = [[PCExtensionPopupPresenter alloc] initWithParentWindow:parent
        pageHost:page
        anchor:^{
          return [PCExtensionPopupAnchor windowAnchor];
        }
        mayDismissForParentKey:^{
          return allow;
        }
        onDismiss:^{
          ++closes;
        }];
    EXPECT([presenter show]);
    NSWindow* other = Window();
    [NSNotificationCenter.defaultCenter
        postNotificationName:NSWindowDidBecomeKeyNotification
                      object:other];
    EXPECT(closes == 0);
    [NSNotificationCenter.defaultCenter
        postNotificationName:NSWindowDidBecomeKeyNotification
                      object:parent];
    EXPECT(closes == 0 && presenter.presenting);
    allow = YES;
    [NSNotificationCenter.defaultCenter
        postNotificationName:NSWindowDidBecomeKeyNotification
                      object:parent];
    EXPECT(closes == 1 && presenter.invalidated);
    EXPECT(page.window == nil);
    [NSNotificationCenter.defaultCenter
        postNotificationName:NSWindowDidBecomeKeyNotification
                      object:parent];
    EXPECT(closes == 1);
    [page invalidate];
    closes = 0;
    observer = [[PageObserver alloc] init];
    page = Page(observer);
    __block PCExtensionPopupPresenter* owned;
    owned = [[PCExtensionPopupPresenter alloc] initWithParentWindow:parent
        pageHost:page
        anchor:^{
          return [PCExtensionPopupAnchor windowAnchor];
        }
        mayDismissForParentKey:^{
          return YES;
        }
        onDismiss:^{
          ++closes;
          [owned invalidate];
          owned = nil;
        }];
    EXPECT([owned show]);
    popup = owned.popupWindow;
    __weak PCExtensionPopupPresenter* weak = owned;
    @autoreleasepool {
      [popup performClose:nil];
      Pump();
    }
    EXPECT(closes == 1);
    EXPECT(owned == nil);
    EXPECT(
        !weak ||
        weak.invalidated);
    EXPECT(page.window == nil && page.contentView != nil);
    EXPECT(observer.detachCount >= 1);
    [popup close];
    EXPECT(closes == 1);
    [page invalidate];
    closes = 0;
    observer = [[PageObserver alloc] init];
    page = Page(observer);
    __block PCExtensionPopupPresenter* replacement;
    PCNativePageHost* replacementPage = Page(nil);
    observer.onDetach = ^{
      replacement =
          [[PCExtensionPopupPresenter alloc] initWithParentWindow:parent
              pageHost:replacementPage
              anchor:^{
                return [PCExtensionPopupAnchor windowAnchor];
              }
              mayDismissForParentKey:^{
                return YES;
              }
              onDismiss:^{
              }];
      EXPECT([replacement show]);
    };
    presenter = [[PCExtensionPopupPresenter alloc] initWithParentWindow:parent
        pageHost:page
        anchor:^{
          return [PCExtensionPopupAnchor windowAnchor];
        }
        mayDismissForParentKey:^{
          return YES;
        }
        onDismiss:^{
          ++closes;
        }];
    EXPECT([presenter show]);
    [presenter.popupWindow performClose:nil];
    EXPECT(closes == 1 && presenter.invalidated);
    EXPECT(replacement.presenting &&
           replacementPage.window == replacement.popupWindow);
    observer.onDetach = nil;
    [replacement invalidate];
    replacement = nil;
    [replacementPage invalidate];
    [page invalidate];
    page = Page(nil);
    [parent.contentView addSubview:page];
    presenter = [[PCExtensionPopupPresenter alloc] initWithParentWindow:parent
        pageHost:page
        anchor:^{
          return [PCExtensionPopupAnchor windowAnchor];
        }
        mayDismissForParentKey:^{
          return YES;
        }
        onDismiss:^{
        }];
    EXPECT(![presenter prepare]);
    [presenter invalidate];
    [page invalidate];
    page = Page(nil);
    __block PCExtensionPopupPresenter* reentrant;
    reentrant = [[PCExtensionPopupPresenter alloc] initWithParentWindow:parent
        pageHost:page
        anchor:^{
          [reentrant invalidate];
          return [PCExtensionPopupAnchor windowAnchor];
        }
        mayDismissForParentKey:^{
          return YES;
        }
        onDismiss:^{
        }];
    EXPECT(![reentrant prepare]);
    EXPECT(reentrant.invalidated && page.window == nil);
    reentrant = nil;
    [page invalidate];
    [parent orderFront:nil];
    EXPECT(parent.visible);
    page = Page(nil);
    presenter = [[PCExtensionPopupPresenter alloc] initWithParentWindow:parent
        pageHost:page
        anchor:^{
          return [PCExtensionPopupAnchor windowAnchor];
        }
        mayDismissForParentKey:^{
          return YES;
        }
        onDismiss:^{
        }];
    EXPECT([presenter prepare]);
    EXPECT(!presenter.presenting);
    EXPECT(!presenter.popupWindow.visible);
    EXPECT(!presenter.popupWindow.keyWindow);
    [presenter invalidate];
    [page invalidate];
    NSWindow* stacked = Window();
    stacked.contentView =
        [[FlippedContentView alloc] initWithFrame:stacked.contentView.frame];
    NSView* upper = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 900, 350)];
    NSView* lower =
        [[NSView alloc] initWithFrame:NSMakeRect(0, 350, 900, 350)];
    [stacked.contentView addSubview:upper];
    [stacked.contentView addSubview:lower];
    NSRect upperOnScreen =
        [stacked convertRectToScreen:[upper convertRect:upper.bounds
                                                 toView:nil]];
    NSRect lowerOnScreen =
        [stacked convertRectToScreen:[lower convertRect:lower.bounds
                                                 toView:nil]];
    EXPECT(NSMinY(upperOnScreen) > NSMinY(lowerOnScreen));
    __block NSView* focused = upper;
    page = Page(nil);
    presenter = [[PCExtensionPopupPresenter alloc] initWithParentWindow:stacked
        pageHost:page
        anchor:^{
          return [PCExtensionPopupAnchor focusedViewAnchor:focused];
        }
        mayDismissForParentKey:^{
          return YES;
        }
        onDismiss:^{
        }];
    EXPECT([presenter prepare]);
    popup = presenter.popupWindow;
    EXPECT(Near(NSMaxY(popup.frame), NSMaxY(upperOnScreen) - 10));
    focused = lower;
    EXPECT([presenter resizeContent:NSMakeSize(200, 120)]);
    EXPECT(Near(NSMaxY(popup.frame), NSMaxY(lowerOnScreen) - 10));
    PlacingController* placing =
        [[PlacingController alloc] initWithWindow:stacked];
    placing.origin = [NSValue valueWithPoint:NSMakePoint(123, 456)];
    EXPECT([presenter resizeContent:NSMakeSize(220, 140)]);
    EXPECT(placing.calls == 0);
    presenter.extensionIdentifier = @"abcdefghijklmnopabcdefghijklmnop";
    EXPECT([presenter resizeContent:NSMakeSize(240, 160)]);
    EXPECT(placing.calls == 1);
    EXPECT([placing.extension
        isEqualToString:@"abcdefghijklmnopabcdefghijklmnop"]);
    EXPECT(placing.popup == popup);
    EXPECT(Near(placing.size.width, popup.frame.size.width));
    EXPECT(Near(placing.size.height, popup.frame.size.height));
    EXPECT(Near(popup.frame.origin.x, 123));
    EXPECT(Near(popup.frame.origin.y, 456));
    for (NSValue* refused in @[
           [NSValue valueWithRect:NSMakeRect(1, 2, 3, 4)],
           [NSValue valueWithPoint:NSMakePoint(NAN, 0)],
         ]) {
      placing.origin = refused;
      EXPECT([presenter resizeContent:NSMakeSize(260, 160)]);
      EXPECT(Near(NSMaxY(popup.frame), NSMaxY(lowerOnScreen) - 10));
    }
    placing.origin = nil;
    focused = upper;
    EXPECT([presenter resizeContent:NSMakeSize(280, 160)]);
    EXPECT(Near(NSMaxY(popup.frame), NSMaxY(upperOnScreen) - 10));
    EXPECT(placing.calls == 4);
    [presenter invalidate];
    [page invalidate];
    [stacked close];
    [other close];
    [parent close];
    printf("NativeExtensionPopup AppKit: %d assertions passed in 8 groups\n",
           assertions);
  }
}
