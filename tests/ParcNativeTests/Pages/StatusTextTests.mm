#import <AppKit/AppKit.h>
#import "ParcNativeTest.h"
#import "ParcNativeClock.h"
#import "ParcNativeWindows.h"
#import "native_appkit_bridge.h"
#import "status_text.h"
#include <cstdio>
#include <cstdlib>

@interface PCNativeStatusTextController (PointerChecks)
- (void)updatePointerInOverlay:(NSPoint)point;
- (void)updateModifierFlags:(NSEventModifierFlags)flags;
- (BOOL)hasMouseMovedMonitor;
- (BOOL)pointerAvoidanceWouldLayoutAt:(NSPoint)point;
@end
@interface StatusTheme : NSObject <NSWindowDelegate>
@property(nonatomic, strong) NSColor* background;
@property(nonatomic, strong) NSAppearance* appearance;
@end
@implementation StatusTheme
- (NSColor*)statusTextThemeBackgroundColor { return self.background; }
- (NSAppearance*)statusTextThemeAppearance { return self.appearance; }
@end
#define Check(...) ParcNativeCheckMessage(__FILE__, __LINE__, __VA_ARGS__)
static void Pump(double seconds) {
  ParcNativeAdvance(seconds);
}
static NSView* Find(NSView* view, NSString* name) {
  if ([view.identifier isEqual:name]) { return view; }
  for (NSView* child in view.subviews) {
    if (NSView* match = Find(child, name)) { return match; }
  }
  return nil;
}
static NSWindow* Window() {
  NSWindow* window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(-2400, -2400, 920, 500)
                styleMask:NSWindowStyleMaskBorderless
                  backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  ParcNativeMarkVisible(window);
  return window;
}
static NSView* Page(NSWindow* window) {
  NSView* page = [[NSView alloc] initWithFrame:window.contentView.bounds];
  [window.contentView addSubview:page];
  return page;
}
static PCNativeStatusTextController* Controller(NSView* page) {
  auto controller = [[PCNativeStatusTextController alloc]
      initWithPage:page validate:^BOOL { return YES; }];
  [controller setAttached:YES];
  return controller;
}
static NSString* LongText() {
  return [@"https://example.test/" stringByPaddingToLength:250
      withString:@"a-very-long-path/" startingAtIndex:0];
}
static void TimingAndPointer() {
  NSWindow* window = Window();
  NSView* page = Page(window);
  auto controller = Controller(page);
  NSView* overlay = Find(page, @"parc-status-overlay");
  NSView* pill = Find(page, @"parc-status-pill");
  NSTextField* label = static_cast<NSTextField*>(Find(page, @"parc-status-label"));
  Check(pill.hidden && pill.alphaValue == 0, "initially hidden and transparent");
  Check([overlay hitTest:NSMakePoint(30, 30)] == nil, "overlay is click-through");
  [controller updateText:@"https://first.test"];
  Pump(.3);
  Check(pill.hidden, "visibility delay is not an immediate show");
  [controller updateText:LongText()];
  Pump(.3);
  Check(pill.hidden, "changed text restarts visibility delay");
  Pump(.3);
  Check(!pill.hidden, "latest nonempty text shows after debounce");
  Check([label.stringValue isEqual:[LongText() substringFromIndex:8]],
        "latest text keeps everything after the removed https:// prefix");
  Check(NSWidth(pill.frame) == 400 && NSHeight(pill.frame) == 24,
        "compact width and recovered height");
  Check(NSMaxY(pill.frame) == NSHeight(overlay.bounds) - 10,
        "page-local bottom inset in flipped overlay");
  Check(label.lineBreakMode == NSLineBreakByTruncatingMiddle, "compact truncation");
  [controller updatePointerInOverlay:NSMakePoint(12, NSMinY(pill.frame) + 12)];
  Check(NSMaxX(pill.frame) == NSWidth(overlay.bounds) - 10, "left-zone avoidance");
  [controller updatePointerInOverlay:NSMakePoint(20, 20)];
  Check(NSMinX(pill.frame) == 10, "outside left zone restores leading");
  [controller updatePointerInOverlay:NSMakePoint(12, NSMinY(pill.frame) + 12)];
  page.frame = NSMakeRect(0, 0, 500, 500);
  [overlay layoutSubtreeIfNeeded];
  [controller updatePointerInOverlay:NSMakePoint(200, NSMinY(pill.frame) + 12)];
  Check(NSMaxX(pill.frame) == 490, "overlapping zones retain the previous side");
  page.frame = NSMakeRect(0, 0, 920, 500);
  [overlay layoutSubtreeIfNeeded];
  [controller updateText:LongText()];
  Pump(1.0);
  Check(NSWidth(pill.frame) == 900, "duplicate text does not restart expansion dwell");
  Check(label.lineBreakMode == NSLineBreakByTruncatingTail, "expanded truncation");
  [controller updateText:@""];
  Pump(.2);
  Check(!pill.hidden && [label.stringValue isEqual:[LongText() substringFromIndex:8]],
        "empty input preserves content until delayed hide");
  Pump(.7);
  Check(pill.hidden && pill.alphaValue == 0, "empty input finishes native fade");
  Check(label.lineBreakMode == NSLineBreakByTruncatingMiddle, "hide resets expansion");
  [controller updateText:@"https://cancelled.test"];
  Pump(.1);
  [controller reset];
  Pump(.7);
  Check(pill.hidden && label.stringValue.length == 0, "reset cancels pending show");
  [controller invalidate];
  Check(overlay.superview == nil, "terminal teardown removes only owned overlay");
  Check(page.superview == window.contentView, "teardown preserves real page");
  [window close];
}
static void OwnershipAndVisibility() {
  NSWindow* one = Window();
  NSWindow* two = Window();
  NSView* first = Page(one);
  NSView* second = Page(two);
  auto a = Controller(first);
  auto b = Controller(second);
  NSView* pillA = Find(first, @"parc-status-pill");
  NSView* pillB = Find(second, @"parc-status-pill");
  [a updateText:@"https://a.test"];
  [b updateText:@"https://b.test"];
  [a setAttached:NO];
  Pump(.85);
  Check(pillA.hidden && !pillB.hidden, "detaching one page leaves the other independent");
  Check([static_cast<NSTextField*>(Find(second, @"parc-status-label")).stringValue
      isEqual:@"b.test"], "second window retains its own source");
  [two.contentView addSubview:first];
  [a updateText:@"https://unattached.test"];
  Pump(.6);
  Check(pillA.hidden, "reparenting does not implicitly authorize new attachment");
  [a setAttached:YES];
  [a updateText:@"https://attached.test"];
  Pump(.85);
  Check(!pillA.hidden, "explicit matching attachment permits new status");
  first.hidden = YES;
  Pump(.1);
  Check(pillA.hidden, "hidden ancestor immediately clears old presentation");
  first.hidden = NO;
  Pump(.6);
  Check(pillA.hidden, "unhiding does not replay a stale URL");
  [a updateText:LongText()];
  Pump(.55);
  [one.contentView addSubview:first];
  Pump(.1);
  Check(pillA.hidden, "unexpected window change clears a displayed URL");
  [a updateText:@"https://not-reattached.test"];
  Pump(.6);
  Check(pillA.hidden, "unexpected reparent closes the attachment gate");
  [a setAttached:YES];
  [a updateText:LongText()];
  Pump(.55);
  [a invalidate];
  [a updateText:@"https://after-close.test"];
  Pump(.9);
  Check(pillA.hidden && Find(first, @"parc-status-overlay") == nil,
        "invalidation cancels an active fade and cannot resurrect the overlay");
  Check(!pillB.hidden, "other page survives callback teardown");
  [b invalidate];
  [one close];
  [two close];
}
static void ValidationAndRelease() {
  NSWindow* window = Window();
  NSView* page = Page(window);
  __block BOOL allowed = YES;
  auto controller = [[PCNativeStatusTextController alloc]
      initWithPage:page validate:^BOOL { return allowed; }];
  [controller setAttached:YES];
  [controller updateText:@"https://stale-document.test"];
  allowed = NO;
  Pump(.7);
  Check(Find(page, @"parc-status-pill").hidden, "validity rechecked at delayed delivery");
  [controller invalidate];
  __weak PCNativeStatusTextController* weak;
  @autoreleasepool {
    auto pending = Controller(page);
    weak = pending;
    [pending updateText:LongText()];
  }
  Check(weak == nil, "pending timer blocks do not retain the controller");
  Check(Find(page, @"parc-status-overlay") == nil, "deallocation removes the overlay");
  @autoreleasepool {
    auto visible = Controller(page);
    weak = visible;
    [visible updateText:@"https://visible.test"];
    Pump(.85);
    Check(!Find(page, @"parc-status-pill").hidden, "active-monitor lifetime exercised");
  }
  Check(weak == nil, "active mouse monitor does not retain its controller");
  [window close];
}
static void MouseMonitorIdleStopAndAvoidanceSkip() {
  NSWindow* window = Window();
  NSView* page = Page(window);
  auto controller = Controller(page);
  NSView* pill = Find(page, @"parc-status-pill");
  [controller updateText:LongText()];
  Pump(.55);
  Check(!pill.hidden && [controller hasMouseMovedMonitor],
        "visible pill installs the local mouseMoved monitor");
  const NSPoint left = NSMakePoint(12, NSMinY(pill.frame) + 12);
  const NSPoint outside = NSMakePoint(20, 20);
  Check([controller pointerAvoidanceWouldLayoutAt:left],
        "entering the left avoidance zone needs layout");
  [controller updatePointerInOverlay:left];
  Check(NSMaxX(pill.frame) == NSWidth(Find(page, @"parc-status-overlay").bounds) - 10,
        "left-zone flips trailing");
  Check(![controller pointerAvoidanceWouldLayoutAt:left],
        "same left-zone point under unchanged overlay/pill fingerprint skips layout");
  const NSRect trailing = pill.frame;
  for (int i = 0; i < 8; ++i) {
    [controller updatePointerInOverlay:NSMakePoint(14 + i, NSMinY(trailing) + 10)];
  }
  Check(NSEqualRects(pill.frame, trailing),
        "repeated left-zone moves keep the trailing frame (true no-op)");
  Check([controller pointerAvoidanceWouldLayoutAt:outside],
        "leaving the left zone needs layout to restore leading");
  [controller updatePointerInOverlay:outside];
  Check(NSMinX(pill.frame) == 10, "outside left zone restores leading");
  Check(![controller pointerAvoidanceWouldLayoutAt:outside],
        "stable outside-zone fingerprint skips layout");
  [controller updateText:@""];
  Pump(.9);
  Check(pill.hidden && ![controller hasMouseMovedMonitor],
        "hidden pill idle-stops the mouseMoved monitor");
  Check(![controller pointerAvoidanceWouldLayoutAt:left],
        "hidden pill cannot schedule avoidance layout");
  [controller invalidate];
  [window close];
}
static void PresentationAndContent() {
  NSWindow* window = Window();
  NSView* page = Page(window);
  auto controller = Controller(page);
  __block int asked = 0;
  controller.linkOutcome = ^PCNativeStatusLinkOutcome(NSEventModifierFlags flags, NSURL*) {
    ++asked;
    return flags == NSEventModifierFlagCommand ? PCNativeStatusLinkOutcomeNewBackgroundTab
                                               : PCNativeStatusLinkOutcomeNone;
  };
  NSView* pill = Find(page, @"parc-status-pill");
  NSImageView* icon = static_cast<NSImageView*>(Find(page, @"parc-status-icon"));
  NSTextField* label = static_cast<NSTextField*>(Find(page, @"parc-status-label"));
  [controller updateText:@"http://plain.test/"];
  Pump(.6);
  Check([label.stringValue isEqual:@"plain.test"], "http prefix and one trailing slash removed");
  Check(!icon.hidden && icon.image, "http shows the lock-slash symbol");
  Check(label.font.pointSize == 12, "12 pt status text");
  Check(NSIsEmptyRect([label.cell expansionFrameWithFrame:label.bounds inView:label]),
        "an uncapped pill fits its whole text");
  Check(NSHeight(pill.frame) == 24 && NSMinX(pill.frame) == 10, "24 pt capsule at the 10 pt inset");
  Check(NSMinX(label.frame) == 9 + NSWidth(icon.frame) + 6, "9 pt padding and 6 pt icon gap");
  NSView* background = Find(page, @"parc-status-background");
  [background layoutSubtreeIfNeeded];
  Check(background.layer.cornerRadius == 12, "capsule radius is half the height");
  [controller updateText:@"mailto:someone@example.test"];
  Pump(.1);
  Check([label.stringValue isEqual:@"someone@example.test"] && !icon.hidden, "mailto keeps an envelope");
  [controller updateText:@"https://secure.test/path"];
  Pump(.1);
  Check([label.stringValue isEqual:@"secure.test/path"] && icon.hidden, "https has no icon");
  const int before = asked;
  [controller updateModifierFlags:NSEventModifierFlagCommand];
  Check(asked > before, "a modifier change asks the shell for the link outcome");
  Check([label.stringValue isEqual:@"Open https://secure.test/path in a new tab"],
        "Command explains a background tab over the full URL");
  Check(label.lineBreakMode == NSLineBreakByTruncatingMiddle && icon.hidden,
        "explained text truncates in the middle; https keeps no icon");
  [controller updateModifierFlags:0];
  Check([label.stringValue isEqual:@"secure.test/path"], "releasing the modifier restores the URL");
  controller.linkOutcome = ^PCNativeStatusLinkOutcome(NSEventModifierFlags flags, NSURL*) {
    ++asked;
    return flags == NSEventModifierFlagOption ? PCNativeStatusLinkOutcomeSplitView
                                              : PCNativeStatusLinkOutcomeNone;
  };
  [controller updateModifierFlags:NSEventModifierFlagOption];
  Check([label.stringValue isEqual:@"Open https://secure.test/path in Split View"],
        "an admitted Option split explains Split View over the full URL");
  [controller updateModifierFlags:NSEventModifierFlagOption | NSEventModifierFlagCommand];
  Check([label.stringValue isEqual:@"secure.test/path"],
        "a modifier the shell cannot split keeps the plain URL");
  [controller updateModifierFlags:0];
  controller.linkOutcome = ^PCNativeStatusLinkOutcome(NSEventModifierFlags flags, NSURL*) {
    ++asked;
    return flags == NSEventModifierFlagShift ? PCNativeStatusLinkOutcomeThisPeek
                                             : PCNativeStatusLinkOutcomeNone;
  };
  [controller updateModifierFlags:NSEventModifierFlagShift];
  Check([label.stringValue isEqual:@"Open https://secure.test/path in this Peek"],
        "Shift inside a Peek explains the link opening in that same Peek");
  [controller updateModifierFlags:0];
  [controller updateText:@"Preparing Reader…"];
  [controller updateModifierFlags:NSEventModifierFlagCommand];
  Check([label.stringValue isEqual:@"Preparing Reader…"], "non-link status text is never explained");
  [controller updateModifierFlags:0];
  [controller updateText:@""];
  [window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];
  Check([label.stringValue isEqual:@"Preparing Reader…"], "an appearance change keeps fading content");
  [controller invalidate];
  [window close];
}
static void LiveThemeColors() {
  NSWindow* window = Window();
  NSWindow* other = Window();
  StatusTheme* theme = [[StatusTheme alloc] init];
  theme.background = NSColor.systemRedColor;
  theme.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
  window.delegate = theme;
  NSView* page = Page(window);
  auto controller = Controller(page);
  NSView* pill = Find(page, @"parc-status-pill");
  NSView* background = Find(page, @"parc-status-background");
  NSTextField* label = static_cast<NSTextField*>(Find(page, @"parc-status-label"));
  NSNotificationName name = PCNativeAirPlayThemeDidChangeNotification;
  [controller updateText:@"https://theme.test/page"];
  Pump(.8);
  Check(!pill.hidden && [[background valueForKey:@"overlayColor"] isEqual:NSColor.systemRedColor],
        "the pill shows the Space's colours");
  const NSRect frame = pill.frame;
  const NSRect labelFrame = label.frame;
  const CGFloat alpha = pill.alphaValue;
  theme.background = NSColor.systemBlueColor;
  theme.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
  [NSNotificationCenter.defaultCenter postNotificationName:name object:other];
  Check([[background valueForKey:@"overlayColor"] isEqual:NSColor.systemRedColor],
        "another window's theme change leaves this pill alone");
  [NSNotificationCenter.defaultCenter postNotificationName:name object:window];
  Check([[background valueForKey:@"overlayColor"] isEqual:NSColor.systemBlueColor] &&
        [pill.appearance.name isEqual:NSAppearanceNameDarkAqua],
        "a theme change while showing repaints the pill's colours");
  Check(NSEqualRects(pill.frame, frame) && NSEqualRects(label.frame, labelFrame) &&
        pill.alphaValue == alpha && !pill.hidden &&
        [label.stringValue isEqual:@"theme.test/page"],
        "a theme repaint keeps layout, visibility and text");
  [controller updateText:@""];
  Pump(.9);
  theme.background = NSColor.systemGreenColor;
  [NSNotificationCenter.defaultCenter postNotificationName:name object:window];
  Check(pill.hidden && [[background valueForKey:@"overlayColor"] isEqual:NSColor.systemBlueColor],
        "a hidden pill leaves the theme for its next show");
  [controller updateText:@"https://theme.test/next"];
  Pump(.8);
  Check(!pill.hidden && [[background valueForKey:@"overlayColor"] isEqual:NSColor.systemGreenColor],
        "the next show reads the current theme");
  [controller invalidate];
  theme.background = NSColor.systemYellowColor;
  [NSNotificationCenter.defaultCenter postNotificationName:name object:window];
  Check([[background valueForKey:@"overlayColor"] isEqual:NSColor.systemGreenColor],
        "an invalidated controller ignores later theme changes");
  window.delegate = nil;
  [window close];
  [other close];
}
static void LiveLinkOutcomeRefresh() {
  NSWindow* window = Window();
  NSWindow* other = Window();
  NSView* page = Page(window);
  auto controller = Controller(page);
  NSTextField* label = static_cast<NSTextField*>(Find(page, @"parc-status-label"));
  __block bool splits = true;
  __block int asked = 0;
  controller.linkOutcome = ^PCNativeStatusLinkOutcome(NSEventModifierFlags flags, NSURL*) {
    ++asked;
    return flags == NSEventModifierFlagOption && splits ? PCNativeStatusLinkOutcomeSplitView
                                                        : PCNativeStatusLinkOutcomeNone;
  };
  NSNotificationName name = PCNativeLinkOutcomeInputsDidChangeNotification;
  NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
  [controller updateText:@"https://split.test/page"];
  [controller updateModifierFlags:NSEventModifierFlagOption];
  Pump(.1);
  Check([label.stringValue isEqual:@"Open https://split.test/page in Split View"],
        "a held Option explains the split");
  splits = false;
  [center postNotificationName:name object:other];
  Pump(.05);
  Check([label.stringValue isEqual:@"Open https://split.test/page in Split View"],
        "another window's state change leaves this pill alone");
  int before = asked;
  [center postNotificationName:name object:window];
  [center postNotificationName:name object:window];
  Check(asked == before, "the refresh waits for the current event to finish");
  Pump(.05);
  Check(asked == before + 1, "repeated changes in one turn ask once");
  Check([label.stringValue isEqual:@"split.test/page"],
        "a window change that stops the split drops the promise while Option stays held");
  splits = true;
  [center postNotificationName:NSWindowDidResignKeyNotification object:window];
  Pump(.05);
  Check([label.stringValue isEqual:@"Open https://split.test/page in Split View"],
        "a focus change re-asks and restores the promise");
  splits = false;
  [center postNotificationName:NSWindowDidEndSheetNotification object:window];
  Pump(.05);
  Check([label.stringValue isEqual:@"split.test/page"], "a closed sheet re-asks");
  splits = true;
  [controller setNeedsLinkOutcomeRefresh];
  Pump(.05);
  Check([label.stringValue isEqual:@"Open https://split.test/page in Split View"],
        "an engine refresh request re-asks");
  const NSRect frame = label.frame;
  before = asked;
  [controller setNeedsLinkOutcomeRefresh];
  Pump(.05);
  Check(asked == before + 1 && NSEqualRects(label.frame, frame),
        "an unchanged answer keeps the pill as it is");
  [controller updateModifierFlags:0];
  [controller updateText:@""];
  Pump(.9);
  before = asked;
  [center postNotificationName:name object:window];
  [controller setNeedsLinkOutcomeRefresh];
  Pump(.05);
  Check(asked == before, "an empty pill never asks");
  [controller invalidate];
  [window close];
  [other close];
}
@interface StatusTextTests : ParcNativeTestCase
@end

@implementation StatusTextTests

- (void)testTimingAndPointer {
  TimingAndPointer();
}

- (void)testOwnershipAndVisibility {
  OwnershipAndVisibility();
}

- (void)testValidationAndRelease {
  ValidationAndRelease();
}

- (void)testMouseMonitorIdleStopAndAvoidanceSkip {
  MouseMonitorIdleStopAndAvoidanceSkip();
}

- (void)testPresentationAndContent {
  PresentationAndContent();
}

- (void)testLiveThemeColors {
  LiveThemeColors();
}

- (void)testLiveLinkOutcomeRefresh {
  LiveLinkOutcomeRefresh();
}

@end
