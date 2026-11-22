#import "StatusTextTestsSupport.h"

using namespace StatusTextTestsSupportFunctions;

__attribute__((objc_runtime_name("ParcNativeTests_StatusTextTestsLifecycleTests")))
@interface StatusTextTestsLifecycleTests : StatusTextTestsSupport
@end

@implementation StatusTextTestsLifecycleTests

- (void)testDetachingOnePagePreservesAnotherPagesStatus {
  [self attach];
  NSWindow* two = Window();
  NSView* second = Page(two);
  auto b = Controller(second);
  NSView* pillB = Find(second, @"parc-status-pill");
  [controller updateText:@"https://a.test"];
  [b updateText:@"https://b.test"];
  [controller setAttached:NO];
  Pump(.85);
  XCTAssertTrue(pill.hidden);
  XCTAssertFalse(pillB.hidden);
  Check([static_cast<NSTextField*>(Find(second, @"parc-status-label")).stringValue
      isEqual:@"b.test"], "second window retains its own source");
  [b invalidate];
  ParcNativeClose(two);
}

- (void)testAReparentedPageNeedsAnExplicitAttachment {
  [self attach];
  NSWindow* other = Window();
  [controller setAttached:NO];
  [other.contentView addSubview:page];
  [controller updateText:@"https://unattached.test"];
  Pump(.6);
  Check(pill.hidden, "reparenting does not implicitly authorize new attachment");
  [controller setAttached:YES];
  [controller updateText:@"https://attached.test"];
  Pump(.85);
  Check(!pill.hidden, "explicit matching attachment permits new status");
  ParcNativeClose(other);
}

- (void)testUnhidingAPageDoesNotReplayItsPreviousLink {
  [self show:LongText()];
  page.hidden = YES;
  Pump(.1);
  Check(pill.hidden, "hidden ancestor immediately clears old presentation");
  page.hidden = NO;
  Pump(.6);
  Check(pill.hidden, "unhiding does not replay a stale URL");
}

- (void)testUnexpectedWindowChangesClearTheLinkAndCloseTheGate {
  [self show:LongText()];
  NSWindow* other = Window();
  [other.contentView addSubview:page];
  Pump(.1);
  Check(pill.hidden, "unexpected window change clears a displayed URL");
  [controller updateText:@"https://not-reattached.test"];
  Pump(.6);
  Check(pill.hidden, "unexpected reparent closes the attachment gate");
  ParcNativeClose(other);
}

- (void)testInvalidatedControllersIgnoreLaterLinks {
  [self show:LongText()];
  [controller invalidate];
  [controller updateText:@"https://after-close.test"];
  Pump(.9);
  Check(pill.hidden && Find(page, @"parc-status-overlay") == nil,
        "invalidation cancels an active fade and cannot resurrect the overlay");
}

- (void)testDelayedDeliveryRechecksDocumentValidity {
  __block BOOL allowed = YES;
  controller = [[PCNativeStatusTextController alloc]
      initWithPage:page validate:^BOOL { return allowed; }];
  controller.presentation = ParcNativePresentation();
  controller.scheduler = ParcNativeScheduler();
  [controller setAttached:YES];
  [controller updateText:@"https://stale-document.test"];
  allowed = NO;
  Pump(.7);
  Check(Find(page, @"parc-status-pill").hidden, "validity rechecked at delayed delivery");
}

- (void)testPendingTimersReleaseTheirControllerAndOverlay {
  __weak PCNativeStatusTextController* weak;
  @autoreleasepool {
    auto pending = Controller(page);
    weak = pending;
    [pending updateText:LongText()];
  }
  Check(weak == nil, "pending timer blocks do not retain the controller");
  Check(Find(page, @"parc-status-overlay") == nil, "deallocation removes the overlay");
}

- (void)testAnActivePointerMonitorReleasesItsController {
  __weak PCNativeStatusTextController* weak;
  @autoreleasepool {
    auto visible = Controller(page);
    weak = visible;
    [visible updateText:@"https://visible.test"];
    Pump(.85);
    Check(!Find(page, @"parc-status-pill").hidden, "active-monitor lifetime exercised");
  }
  Check(weak == nil, "active mouse monitor does not retain its controller");
}

- (StatusTextTestsStatusTheme*)showThemedLink {
  StatusTextTestsStatusTheme* theme = [[StatusTextTestsStatusTheme alloc] init];
  theme.background = NSColor.systemRedColor;
  theme.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
  window.delegate = theme;
  [self show:@"https://theme.test/page"];
  return theme;
}

- (void)testAnAppearanceChangePreservesFadingText {
  [self show:@"Preparing Reader…"];
  [controller updateText:@""];
  [window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];
  Check([label.stringValue isEqual:@"Preparing Reader…"], "an appearance change keeps fading content");
}

- (void)testThePillReadsItsWindowsTheme {
  StatusTextTestsStatusTheme* theme = [self showThemedLink];
  NSView* background = Find(page, @"parc-status-background");
  Check(!pill.hidden && [[background valueForKey:@"overlayColor"] isEqual:NSColor.systemRedColor],
        "the pill shows the Space's colours");
  window.delegate = nil;
  XCTAssertNotNil(theme);
}

- (void)testThemeChangesInOtherWindowsAreIgnored {
  StatusTextTestsStatusTheme* theme = [self showThemedLink];
  NSWindow* other = Window();
  NSView* background = Find(page, @"parc-status-background");
  NSNotificationName name = PCNativeAirPlayThemeDidChangeNotification;
  theme.background = NSColor.systemBlueColor;
  theme.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
  [NSNotificationCenter.defaultCenter postNotificationName:name object:other];
  Check([[background valueForKey:@"overlayColor"] isEqual:NSColor.systemRedColor],
        "another window's theme change leaves this pill alone");
  ParcNativeClose(other);
}

- (void)testAVisibleThemeChangePreservesGeometryAndText {
  StatusTextTestsStatusTheme* theme = [self showThemedLink];
  NSView* background = Find(page, @"parc-status-background");
  NSNotificationName name = PCNativeAirPlayThemeDidChangeNotification;
  const NSRect frame = pill.frame;
  const NSRect labelFrame = label.frame;
  const CGFloat alpha = pill.alphaValue;
  theme.background = NSColor.systemBlueColor;
  theme.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
  [NSNotificationCenter.defaultCenter postNotificationName:name object:window];
  Check([[background valueForKey:@"overlayColor"] isEqual:NSColor.systemBlueColor] &&
        [pill.appearance.name isEqual:NSAppearanceNameDarkAqua],
        "a theme change while showing repaints the pill's colours");
  Check(NSEqualRects(pill.frame, frame) && NSEqualRects(label.frame, labelFrame) &&
        pill.alphaValue == alpha && !pill.hidden &&
        [label.stringValue isEqual:@"theme.test/page"],
        "a theme repaint keeps layout, visibility and text");
}

- (void)testHiddenPillsReadTheNewThemeAtTheirNextShow {
  StatusTextTestsStatusTheme* theme = [self showThemedLink];
  NSView* background = Find(page, @"parc-status-background");
  NSNotificationName name = PCNativeAirPlayThemeDidChangeNotification;
  [controller updateText:@""];
  Pump(.9);
  theme.background = NSColor.systemGreenColor;
  [NSNotificationCenter.defaultCenter postNotificationName:name object:window];
  Check(pill.hidden && [[background valueForKey:@"overlayColor"] isEqual:NSColor.systemRedColor],
        "a hidden pill leaves the theme for its next show");
  [controller updateText:@"https://theme.test/next"];
  Pump(.8);
  Check(!pill.hidden && [[background valueForKey:@"overlayColor"] isEqual:NSColor.systemGreenColor],
        "the next show reads the current theme");
}

- (void)testInvalidationUnregistersThemeObservation {
  StatusTextTestsStatusTheme* theme = [self showThemedLink];
  NSView* background = Find(page, @"parc-status-background");
  NSNotificationName name = PCNativeAirPlayThemeDidChangeNotification;
  [controller invalidate];
  theme.background = NSColor.systemYellowColor;
  [NSNotificationCenter.defaultCenter postNotificationName:name object:window];
  Check([[background valueForKey:@"overlayColor"] isEqual:NSColor.systemRedColor],
        "an invalidated controller ignores later theme changes");
}

@end
