#include <cmath>
#import "ParcNativeTest.h"
#import "ParcNativeClock.h"
#include <cstdio>
#include <cstdlib>

#import "extension_popup_presenter.h"
#import "page_host.h"
#define EXPECT(condition) PARC_CHECK(condition)
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
                styleMask:NSWindowStyleMaskBorderless
                  backing:NSBackingStoreBuffered
                    defer:NO];
  result.releasedWhenClosed = NO;
  return result;
}
static PCNativePageHost* Page(PageObserver* observer) {
  PCNativePageHost* host = [PCNativePageHost
      hostWithContentView:[[NSView alloc]
                              initWithFrame:NSMakeRect(0, 0, 80, 80)]
                 observer:observer];
  host.presentation = ParcNativePresentation();
  host.scheduler = ParcNativeScheduler();
  return host;
}
static BOOL Near(CGFloat a, CGFloat b) {
  return std::abs(a - b) < .01;
}
static void Pump() {
  ParcNativeAdvance(.02);
}
@interface ParcNativeTests_ExtensionPopupTests : ParcNativeTestCase
@end

@implementation ParcNativeTests_ExtensionPopupTests {
  NSWindow* _parent;
  NSMutableArray<NSWindow*>* _windows;
  NSMutableArray<PCNativePageHost*>* _pages;
}

- (void)setUp {
  [super setUp];
  _windows = [NSMutableArray array];
  _pages = [NSMutableArray array];
  _parent = [self window];
}

- (void)tearDown {
  for (PCNativePageHost* page in _pages) [page invalidate];
  for (NSWindow* window in _windows) ParcNativeClose(window);
  [super tearDown];
}

- (NSWindow*)window {
  NSWindow* window = Window();
  [_windows addObject:window];
  return window;
}

- (PCNativePageHost*)page:(PageObserver*)observer {
  PCNativePageHost* page = Page(observer);
  [_pages addObject:page];
  return page;
}

- (PCExtensionPopupPresenter*)presenterFor:(PCNativePageHost*)page
                                    parent:(NSWindow*)parent
                                    anchor:(PCExtensionPopupAnchor* (^)(void))anchor
                                mayDismiss:(BOOL (^)(void))mayDismiss
                                 onDismiss:(void (^)(void))onDismiss {
  PCExtensionPopupPresenter* presenter = [[PCExtensionPopupPresenter alloc] initWithParentWindow:parent
                                                        pageHost:page
                                                          anchor:anchor
                                          mayDismissForParentKey:mayDismiss
                                                       onDismiss:onDismiss];
  presenter.presentation = ParcNativePresentation();
  presenter.scheduler = ParcNativeScheduler();
  return presenter;
}

- (PCExtensionPopupPresenter*)windowAnchoredPresenterFor:(PCNativePageHost*)page onDismiss:(void (^)(void))onDismiss {
  return [self presenterFor:page
                     parent:_parent
                     anchor:^{
                       return [PCExtensionPopupAnchor windowAnchor];
                     }
                 mayDismiss:^{
                   return YES;
                 }
                  onDismiss:onDismiss ?: ^{
                  }];
}

- (void)testPreparingHostsThePageInAnUnparentedPopup {
  PCNativePageHost* page = [self page:[[PageObserver alloc] init]];
  NSView* original = page.contentView;
  PCExtensionPopupPresenter* presenter = [self windowAnchoredPresenterFor:page onDismiss:nil];
  EXPECT([presenter prepare]);
  EXPECT(!presenter.presenting);
  NSWindow* popup = presenter.popupWindow;
  EXPECT(ParcNativeParentWindow(popup) == nil);
  EXPECT(page.window == popup);
  EXPECT(page.contentView == original);
  EXPECT(page.superview == popup.contentView && popup.contentViewController.view == popup.contentView);
  EXPECT(Near(page.bounds.size.width, 300));
  EXPECT(popup.styleMask == (NSWindowStyleMaskTitled | NSWindowStyleMaskClosable));
  EXPECT(popup.tabbingMode == NSWindowTabbingModeDisallowed);
  EXPECT((popup.collectionBehavior & NSWindowCollectionBehaviorFullScreenAuxiliary) != 0);
  [presenter invalidate];
}

- (void)testTheWindowAnchorPlacesThePopupAtTheTopTrailingCorner {
  PCExtensionPopupPresenter* presenter = [self windowAnchoredPresenterFor:[self page:nil] onDismiss:nil];
  EXPECT([presenter prepare]);
  NSWindow* popup = presenter.popupWindow;
  NSPoint expected = [_parent convertPointToScreen:NSMakePoint(_parent.frame.size.width - popup.frame.size.width - 40,
                                                               _parent.frame.size.height - popup.frame.size.height - 10)];
  EXPECT(Near(popup.frame.origin.x, expected.x));
  EXPECT(Near(popup.frame.origin.y, expected.y));
  [presenter invalidate];
}

- (void)testShowingParentsThePopupAndInvalidationReturnsThePage {
  __block int closes = 0;
  PCNativePageHost* page = [self page:[[PageObserver alloc] init]];
  NSView* original = page.contentView;
  PCExtensionPopupPresenter* presenter = [self windowAnchoredPresenterFor:page
                                                                onDismiss:^{
                                                                  ++closes;
                                                                }];
  EXPECT([presenter prepare]);
  NSWindow* popup = presenter.popupWindow;
  EXPECT([presenter show]);
  EXPECT(presenter.presenting && ParcNativeVisible(popup));
  EXPECT(ParcNativeParentWindow(popup) == _parent);
  [presenter invalidate];
  EXPECT(presenter.invalidated && !presenter.presenting);
  EXPECT(!page.window && page.contentView == original);
  EXPECT(ParcNativeParentWindow(popup) == nil);
  EXPECT(closes == 0);
  EXPECT(![presenter show]);
  EXPECT(![presenter resizeContent:NSMakeSize(50, 50)]);
  [presenter invalidate];
  EXPECT(closes == 0);
}

- (void)testTheSidebarAnchorPlacesThePopupBesideTheSidebar {
  PCExtensionPopupPresenter* presenter = [self presenterFor:[self page:nil]
      parent:_parent
      anchor:^{
        return [PCExtensionPopupAnchor sidebarAnchorWithWidth:200];
      }
      mayDismiss:^{
        return YES;
      }
      onDismiss:^{
      }];
  EXPECT([presenter prepare]);
  NSWindow* popup = presenter.popupWindow;
  NSPoint expected =
      [_parent convertPointToScreen:NSMakePoint(40, _parent.frame.size.height - popup.frame.size.height - 10)];
  EXPECT(Near(popup.frame.origin.x, expected.x));
  [presenter invalidate];
}

- (PCExtensionPopupPresenter*)paneAnchoredPresenterFor:(PCNativePageHost*)page pane:(NSView**)paneOut {
  __block PCExtensionPopupAnchor* anchor = [PCExtensionPopupAnchor sidebarAnchorWithWidth:200];
  PCExtensionPopupPresenter* presenter = [self presenterFor:page
      parent:_parent
      anchor:^{
        return anchor;
      }
      mayDismiss:^{
        return YES;
      }
      onDismiss:^{
      }];
  EXPECT([presenter prepare]);
  NSView* pane = [[NSView alloc] initWithFrame:NSMakeRect(200, 50, 500, 450)];
  [_parent.contentView addSubview:pane];
  anchor = [PCExtensionPopupAnchor focusedViewAnchor:pane];
  *paneOut = pane;
  return presenter;
}

- (void)testAFocusedPaneAnchorFollowsResizes {
  PCNativePageHost* page = [self page:nil];
  NSView* pane;
  PCExtensionPopupPresenter* presenter = [self paneAnchoredPresenterFor:page pane:&pane];
  NSWindow* popup = presenter.popupWindow;
  EXPECT([presenter resizeContent:NSMakeSize(180, 160)]);
  NSPoint expected = [_parent convertPointToScreen:NSMakePoint(NSMaxX(pane.frame) - popup.frame.size.width - 40,
                                                               NSMaxY(pane.frame) - popup.frame.size.height - 10)];
  EXPECT(Near(popup.frame.origin.x, expected.x));
  EXPECT(Near(popup.frame.origin.y, expected.y));
  EXPECT(Near(page.bounds.size.width, 180));
  EXPECT(NSEqualRects(page.frame, page.superview.bounds));
  EXPECT(![presenter resizeContent:NSMakeSize(NAN, 10)]);
  [presenter invalidate];
}

- (void)testAPopupTheUserMovedKeepsItsPlaceOnResize {
  NSView* pane;
  PCExtensionPopupPresenter* presenter = [self paneAnchoredPresenterFor:[self page:nil] pane:&pane];
  NSWindow* popup = presenter.popupWindow;
  EXPECT([presenter resizeContent:NSMakeSize(180, 160)]);
  [NSNotificationCenter.defaultCenter postNotificationName:NSWindowWillMoveNotification object:popup];
  EXPECT(presenter.userHasMovedWindow);
  NSPoint origin = popup.frame.origin;
  EXPECT([presenter resizeContent:NSMakeSize(220, 160)]);
  EXPECT(Near(popup.frame.origin.x, origin.x));
  [presenter invalidate];
}

- (void)testTheParentBecomingKeyDismissesOnlyWhenAllowed {
  __block BOOL allow = NO;
  __block int closes = 0;
  PCNativePageHost* page = [self page:nil];
  PCExtensionPopupPresenter* presenter = [self presenterFor:page
      parent:_parent
      anchor:^{
        return [PCExtensionPopupAnchor windowAnchor];
      }
      mayDismiss:^{
        return allow;
      }
      onDismiss:^{
        ++closes;
      }];
  EXPECT([presenter show]);
  NSWindow* other = [self window];
  [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidBecomeKeyNotification object:other];
  EXPECT(closes == 0);
  [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidBecomeKeyNotification object:_parent];
  EXPECT(closes == 0 && presenter.presenting);
  allow = YES;
  [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidBecomeKeyNotification object:_parent];
  EXPECT(closes == 1 && presenter.invalidated);
  EXPECT(page.window == nil);
  [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidBecomeKeyNotification object:_parent];
  EXPECT(closes == 1);
}

- (void)testClosingThePopupDismissesItAndReleasesItsOwner {
  __block int closes = 0;
  PageObserver* observer = [[PageObserver alloc] init];
  PCNativePageHost* page = [self page:observer];
  __block PCExtensionPopupPresenter* owned;
  owned = [self windowAnchoredPresenterFor:page
                                 onDismiss:^{
                                   ++closes;
                                   [owned invalidate];
                                   owned = nil;
                                 }];
  EXPECT([owned show]);
  NSWindow* popup = owned.popupWindow;
  __weak PCExtensionPopupPresenter* weak = owned;
  @autoreleasepool {
    [popup performClose:nil];
    Pump();
  }
  EXPECT(closes == 1);
  EXPECT(owned == nil);
  EXPECT(!weak || weak.invalidated);
  EXPECT(page.window == nil && page.contentView != nil);
  EXPECT(observer.detachCount >= 1);
  ParcNativeClose(popup);
  EXPECT(closes == 1);
}

- (void)testAReplacementShownWhileThePageDetachesSurvives {
  __block int closes = 0;
  PageObserver* observer = [[PageObserver alloc] init];
  PCNativePageHost* page = [self page:observer];
  __block PCExtensionPopupPresenter* replacement;
  PCNativePageHost* replacementPage = [self page:nil];
  __weak ParcNativeTests_ExtensionPopupTests* test = self;
  observer.onDetach = ^{
    replacement = [test windowAnchoredPresenterFor:replacementPage onDismiss:nil];
    EXPECT([replacement show]);
  };
  PCExtensionPopupPresenter* presenter = [self windowAnchoredPresenterFor:page
                                                                onDismiss:^{
                                                                  ++closes;
                                                                }];
  EXPECT([presenter show]);
  [presenter.popupWindow performClose:nil];
  EXPECT(closes == 1 && presenter.invalidated);
  EXPECT(replacement.presenting && replacementPage.window == replacement.popupWindow);
  observer.onDetach = nil;
  [replacement invalidate];
}

- (void)testAPageAlreadyInAWindowIsRefused {
  PCNativePageHost* page = [self page:nil];
  [_parent.contentView addSubview:page];
  PCExtensionPopupPresenter* presenter = [self windowAnchoredPresenterFor:page onDismiss:nil];
  EXPECT(![presenter prepare]);
  [presenter invalidate];
}

- (void)testAnAnchorThatInvalidatesThePresenterRefusesPreparation {
  PCNativePageHost* page = [self page:nil];
  __block PCExtensionPopupPresenter* reentrant;
  reentrant = [self presenterFor:page
      parent:_parent
      anchor:^{
        [reentrant invalidate];
        return [PCExtensionPopupAnchor windowAnchor];
      }
      mayDismiss:^{
        return YES;
      }
      onDismiss:^{
      }];
  EXPECT(![reentrant prepare]);
  EXPECT(reentrant.invalidated && page.window == nil);
  reentrant = nil;
}

- (void)testPreparingNeitherShowsNorFocusesThePopup {
  PCExtensionPopupPresenter* presenter = [self windowAnchoredPresenterFor:[self page:nil] onDismiss:nil];
  EXPECT([presenter prepare]);
  EXPECT(!presenter.presenting);
  EXPECT(!ParcNativeVisible(presenter.popupWindow));
  EXPECT(!presenter.popupWindow.keyWindow);
  [presenter invalidate];
}

- (PCExtensionPopupPresenter*)stackedPresenter:(NSWindow**)stackedOut
                                         upper:(NSRect*)upperOut
                                         lower:(NSRect*)lowerOut
                                         focus:(void (^*)(BOOL lower))focusOut {
  NSWindow* stacked = [self window];
  stacked.contentView = [[FlippedContentView alloc] initWithFrame:stacked.contentView.frame];
  NSView* upper = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 900, 350)];
  NSView* lower = [[NSView alloc] initWithFrame:NSMakeRect(0, 350, 900, 350)];
  [stacked.contentView addSubview:upper];
  [stacked.contentView addSubview:lower];
  *upperOut = [stacked convertRectToScreen:[upper convertRect:upper.bounds toView:nil]];
  *lowerOut = [stacked convertRectToScreen:[lower convertRect:lower.bounds toView:nil]];
  __block NSView* focused = upper;
  *focusOut = ^(BOOL toLower) {
    focused = toLower ? lower : upper;
  };
  *stackedOut = stacked;
  PCExtensionPopupPresenter* presenter = [self presenterFor:[self page:nil]
      parent:stacked
      anchor:^{
        return [PCExtensionPopupAnchor focusedViewAnchor:focused];
      }
      mayDismiss:^{
        return YES;
      }
      onDismiss:^{
      }];
  EXPECT([presenter prepare]);
  return presenter;
}

- (void)testTheFocusedViewAnchorFollowsFocusBetweenStackedPanes {
  NSWindow* stacked;
  NSRect upper, lower;
  void (^focus)(BOOL);
  PCExtensionPopupPresenter* presenter = [self stackedPresenter:&stacked upper:&upper lower:&lower focus:&focus];
  EXPECT(NSMinY(upper) > NSMinY(lower));
  NSWindow* popup = presenter.popupWindow;
  EXPECT(Near(NSMaxY(popup.frame), NSMaxY(upper) - 10));
  focus(YES);
  EXPECT([presenter resizeContent:NSMakeSize(200, 120)]);
  EXPECT(Near(NSMaxY(popup.frame), NSMaxY(lower) - 10));
  [presenter invalidate];
}

- (void)testAWindowControllerPlacesOnlyAnIdentifiedExtensionsPopup {
  NSWindow* stacked;
  NSRect upper, lower;
  void (^focus)(BOOL);
  PCExtensionPopupPresenter* presenter = [self stackedPresenter:&stacked upper:&upper lower:&lower focus:&focus];
  NSWindow* popup = presenter.popupWindow;
  focus(YES);
  EXPECT([presenter resizeContent:NSMakeSize(200, 120)]);
  PlacingController* placing = [[PlacingController alloc] initWithWindow:stacked];
  placing.origin = [NSValue valueWithPoint:NSMakePoint(123, 456)];
  EXPECT([presenter resizeContent:NSMakeSize(220, 140)]);
  EXPECT(placing.calls == 0);
  presenter.extensionIdentifier = @"abcdefghijklmnopabcdefghijklmnop";
  EXPECT([presenter resizeContent:NSMakeSize(240, 160)]);
  EXPECT(placing.calls == 1);
  EXPECT([placing.extension isEqualToString:@"abcdefghijklmnopabcdefghijklmnop"]);
  EXPECT(placing.popup == popup);
  EXPECT(Near(placing.size.width, popup.frame.size.width));
  EXPECT(Near(placing.size.height, popup.frame.size.height));
  EXPECT(Near(popup.frame.origin.x, 123));
  EXPECT(Near(popup.frame.origin.y, 456));
  for (NSValue* refused in @[ [NSValue valueWithRect:NSMakeRect(1, 2, 3, 4)], [NSValue valueWithPoint:NSMakePoint(NAN, 0)] ]) {
    placing.origin = refused;
    EXPECT([presenter resizeContent:NSMakeSize(260, 160)]);
    EXPECT(Near(NSMaxY(popup.frame), NSMaxY(lower) - 10));
  }
  placing.origin = nil;
  focus(NO);
  EXPECT([presenter resizeContent:NSMakeSize(280, 160)]);
  EXPECT(Near(NSMaxY(popup.frame), NSMaxY(upper) - 10));
  EXPECT(placing.calls == 4);
  [presenter invalidate];
}

@end
