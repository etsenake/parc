#include <cmath>
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
  @autoreleasepool {
    [NSApplication sharedApplication];
    NSApp.activationPolicy = NSApplicationActivationPolicyAccessory;
    // 1. Actual child window and existing native page identity, not a URL copy.
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
    EXPECT(popup.contentViewController.view == page);
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
    // 2. Sidebar/focused anchor, content size versus frame size, user-move
    // lock.
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
    // 3. Only actual parent activation dismisses; owned-dialog policy can hold.
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
    // 4. Actual close plus reentrant owner release is exactly once.
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
        weak.invalidated);  // AppKit may autorelease its close delegate later.
    EXPECT(page.window == nil && page.contentView != nil);
    EXPECT(observer.detachCount >= 1);
    [popup close];
    EXPECT(closes == 1);
    [page invalidate];
    // 5. Native detach reentry must not close or remove a replacement popup.
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
    // 6. Invalid parent/attached page and anchor-callback invalidation fail
    // safely.
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
    // 7. A visible parent must not expose an opening popup before loaded/show.
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
    [other close];
    [parent close];
    printf("NativeExtensionPopup AppKit: %d assertions passed in 7 groups\n",
           assertions);
  }
}
