#import "StatusTextTestsSupport.h"

using namespace StatusTextTestsSupportFunctions;

__attribute__((objc_runtime_name("ParcNativeTests_StatusTextTestsLinkOutcomeTests")))
@interface StatusTextTestsLinkOutcomeTests : StatusTextTestsSupport
@end

@implementation StatusTextTestsLinkOutcomeTests

- (void)testPlainHttpDisplaysItsHostAndLockSlash {
  [self show:@"http://plain.test/"];
  Check([label.stringValue isEqual:@"plain.test"], "http prefix and one trailing slash removed");
  Check(!icon.hidden && icon.image, "http shows the lock-slash symbol");
}

- (void)testShortLinksFitInsideTheCapsule {
  [self show:@"http://plain.test/"];
  Check(label.font.pointSize == 12, "12 pt status text");
  Check(NSIsEmptyRect([label.cell expansionFrameWithFrame:label.bounds inView:label]),
        "an uncapped pill fits its whole text");
  Check(NSHeight(pill.frame) == 24 && NSMinX(pill.frame) == 10, "24 pt capsule at the 10 pt inset");
  Check(NSMinX(label.frame) == 9 + NSWidth(icon.frame) + 6, "9 pt padding and 6 pt icon gap");
  NSView* background = Find(page, @"parc-status-background");
  [background layoutSubtreeIfNeeded];
  Check(background.layer.cornerRadius == 12, "capsule radius is half the height");
}

- (void)testMailLinksShowTheirAddressAndEnvelope {
  [self show:@"mailto:someone@example.test"];
  Check([label.stringValue isEqual:@"someone@example.test"] && !icon.hidden, "mailto keeps an envelope");
}

- (void)testSecureLinksHideTheSchemeAndIcon {
  [self show:@"https://secure.test/path"];
  Check([label.stringValue isEqual:@"secure.test/path"] && icon.hidden, "https has no icon");
}

- (void)testCommandExplainsTheBackgroundTabUntilReleased {
  [self show:@"https://secure.test/path"];
  __block int asked = 0;
  controller.linkOutcome = ^PCNativeStatusLinkOutcome(NSEventModifierFlags flags, NSURL*) {
    ++asked;
    return flags == NSEventModifierFlagCommand ? PCNativeStatusLinkOutcomeNewBackgroundTab
                                               : PCNativeStatusLinkOutcomeNone;
  };
  const int before = asked;
  [controller updateModifierFlags:NSEventModifierFlagCommand];
  Check(asked > before, "a modifier change asks the shell for the link outcome");
  Check([label.stringValue isEqual:@"Open https://secure.test/path in a new tab"],
        "Command explains a background tab over the full URL");
  Check(label.lineBreakMode == NSLineBreakByTruncatingMiddle && icon.hidden,
        "explained text truncates in the middle; https keeps no icon");
  [controller updateModifierFlags:0];
  Check([label.stringValue isEqual:@"secure.test/path"], "releasing the modifier restores the URL");
}

- (void)testOptionExplainsAnAdmittedSplit {
  [self show:@"https://secure.test/path"];
  controller.linkOutcome = ^PCNativeStatusLinkOutcome(NSEventModifierFlags flags, NSURL*) {
    return flags == NSEventModifierFlagOption ? PCNativeStatusLinkOutcomeSplitView
                                              : PCNativeStatusLinkOutcomeNone;
  };
  [controller updateModifierFlags:NSEventModifierFlagOption];
  Check([label.stringValue isEqual:@"Open https://secure.test/path in Split View"],
        "an admitted Option split explains Split View over the full URL");
  [controller updateModifierFlags:NSEventModifierFlagOption | NSEventModifierFlagCommand];
  Check([label.stringValue isEqual:@"secure.test/path"],
        "a modifier the shell cannot split keeps the plain URL");
}

- (void)testShiftExplainsTheCurrentPeek {
  [self show:@"https://secure.test/path"];
  controller.linkOutcome = ^PCNativeStatusLinkOutcome(NSEventModifierFlags flags, NSURL*) {
    return flags == NSEventModifierFlagShift ? PCNativeStatusLinkOutcomeThisPeek
                                             : PCNativeStatusLinkOutcomeNone;
  };
  [controller updateModifierFlags:NSEventModifierFlagShift];
  Check([label.stringValue isEqual:@"Open https://secure.test/path in this Peek"],
        "Shift inside a Peek explains the link opening in that same Peek");
}

- (void)testNonLinkStatusIgnoresModifiers {
  [self show:@"Preparing Reader…"];
  [controller updateModifierFlags:NSEventModifierFlagCommand];
  Check([label.stringValue isEqual:@"Preparing Reader…"], "non-link status text is never explained");
}

- (void)showSplitLinkWhen:(BOOL (^)(void))canSplit queried:(void (^)(void))queried {
  [self attach];
  controller.linkOutcome = ^PCNativeStatusLinkOutcome(NSEventModifierFlags flags, NSURL*) {
    queried();
    return flags == NSEventModifierFlagOption && canSplit() ? PCNativeStatusLinkOutcomeSplitView
                                                        : PCNativeStatusLinkOutcomeNone;
  };
  [controller updateText:@"https://split.test/page"];
  [controller updateModifierFlags:NSEventModifierFlagOption];
  Pump(.1);
}

- (void)testLinkOutcomeChangesOnlyAffectTheirWindow {
  __block BOOL splits = YES;
  [self showSplitLinkWhen:^BOOL { return splits; } queried:^{}];
  NSWindow* other = Window();
  NSNotificationName name = PCNativeLinkOutcomeInputsDidChangeNotification;
  NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
  Check([label.stringValue isEqual:@"Open https://split.test/page in Split View"],
        "a held Option explains the split");
  splits = false;
  [center postNotificationName:name object:other];
  Pump(.05);
  Check([label.stringValue isEqual:@"Open https://split.test/page in Split View"],
        "another window's state change leaves this pill alone");
  ParcNativeClose(other);
}

- (void)testRepeatedLinkOutcomeChangesAskOnceAtTheEndOfTheTurn {
  __block BOOL splits = YES;
  __block int asked = 0;
  [self showSplitLinkWhen:^BOOL { return splits; } queried:^{ ++asked; }];
  NSNotificationName name = PCNativeLinkOutcomeInputsDidChangeNotification;
  NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
  splits = false;
  int before = asked;
  [center postNotificationName:name object:window];
  [center postNotificationName:name object:window];
  Check(asked == before, "the refresh waits for the current event to finish");
  Pump(.05);
  Check(asked == before + 1, "repeated changes in one turn ask once");
  Check([label.stringValue isEqual:@"split.test/page"],
        "a window change that stops the split drops the promise while Option stays held");
}

- (void)testLosingFocusRefreshesTheHeldModifier {
  __block BOOL splits = NO;
  [self showSplitLinkWhen:^BOOL { return splits; } queried:^{}];
  NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
  splits = YES;
  [center postNotificationName:NSWindowDidResignKeyNotification object:window];
  Pump(.05);
  Check([label.stringValue isEqual:@"Open https://split.test/page in Split View"],
        "a focus change re-asks and restores the promise");
}

- (void)testClosingASheetRefreshesTheHeldModifier {
  __block BOOL splits = YES;
  [self showSplitLinkWhen:^BOOL { return splits; } queried:^{}];
  NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
  splits = NO;
  [center postNotificationName:NSWindowDidEndSheetNotification object:window];
  Pump(.05);
  Check([label.stringValue isEqual:@"split.test/page"], "a closed sheet re-asks");
}

- (void)testAnEngineRequestRefreshesTheHeldModifier {
  __block BOOL splits = NO;
  [self showSplitLinkWhen:^BOOL { return splits; } queried:^{}];
  splits = YES;
  [controller setNeedsLinkOutcomeRefresh];
  Pump(.05);
  Check([label.stringValue isEqual:@"Open https://split.test/page in Split View"],
        "an engine refresh request re-asks");
}

- (void)testUnchangedOutcomesKeepTheLabelFrame {
  __block int asked = 0;
  [self showSplitLinkWhen:^BOOL { return YES; } queried:^{ ++asked; }];
  const NSRect frame = label.frame;
  int before = asked;
  [controller setNeedsLinkOutcomeRefresh];
  Pump(.05);
  Check(asked == before + 1 && NSEqualRects(label.frame, frame),
        "an unchanged answer keeps the pill as it is");
}

- (void)testEmptyPillsIgnoreOutcomeRefreshRequests {
  __block int asked = 0;
  [self showSplitLinkWhen:^BOOL { return YES; } queried:^{ ++asked; }];
  NSNotificationName name = PCNativeLinkOutcomeInputsDidChangeNotification;
  NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
  [controller updateModifierFlags:0];
  [controller updateText:@""];
  Pump(.9);
  int before = asked;
  [center postNotificationName:name object:window];
  [controller setNeedsLinkOutcomeRefresh];
  Pump(.05);
  Check(asked == before, "an empty pill never asks");
}

@end
