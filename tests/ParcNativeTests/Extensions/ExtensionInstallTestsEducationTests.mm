#import "ExtensionInstallTestsSupport.h"

using namespace ExtensionInstallTestsSupportFunctions;

__attribute__((objc_runtime_name("ParcNativeTests_ExtensionInstallTestsEducationTests")))
@interface ExtensionInstallTestsEducationTests : ExtensionInstallTestsSupport
@end

@implementation ExtensionInstallTestsEducationTests

- (void)testReservationsShareAWindowUntilTheLastIsReleased {
  auto* first = [PCNativeWindowSecurityReservation acquireForWindow:_w];
  EXPECT(first.active && first.isOnlyReservation);
  auto* second = [PCNativeWindowSecurityReservation acquireForWindow:_w];
  EXPECT(second.active && !first.isOnlyReservation && !second.isOnlyReservation);
  [second invalidate];
  EXPECT(first.isOnlyReservation && !second.isOnlyReservation);
  [first invalidate];
  EXPECT(!first.isOnlyReservation);
}

- (void)testAReleasedReservationIsNoLongerSoleDuringItsNotification {
  __block BOOL soleInside = NO;
  __block PCNativeWindowSecurityReservation* first;
  id observer = [NSNotificationCenter.defaultCenter addObserverForName:PCNativeWindowSecurityStateChanged
                                                                object:_w
                                                                 queue:nil
                                                            usingBlock:^(NSNotification*) {
                                                              soleInside = first.isOnlyReservation;
                                                            }];
  first = [PCNativeWindowSecurityReservation acquireForWindow:_w];
  EXPECT(first.isOnlyReservation);
  [first invalidate];
  EXPECT(!soleInside && !first.isOnlyReservation);
  [NSNotificationCenter.defaultCenter removeObserver:observer];
}

- (void)testClosingTheWindowEndsItsReservation {
  auto* closing = Window();
  auto* first = [PCNativeWindowSecurityReservation acquireForWindow:closing];
  EXPECT(first.isOnlyReservation);
  ParcNativeClose(closing);
  EXPECT(!first.active && !first.isOnlyReservation);
}

- (PCExtensionInstallPresenter*)shownEducation {
  PCExtensionInstallPresenter* p = [self make];
  [p configureInstallationEducationWithName:@"Example"];
  [p start];
  Pump();
  return p;
}

- (void)testEducationWithoutPermissionsSaysItNeedsNone {
  PCExtensionInstallPresenter* p = [self upstreamPresenterWithPermissions:@[] details:@[]];
  [p configureInstallationEducationWithName:@"Example"];
  [p start];
  Pump();
  EXPECT(p.sheet.contentView.bounds.size.width == 450);
  EXPECT(Text(p.sheet.contentView, @"Add the “Example” extension to Parc?"));
  EXPECT(Text(p.sheet.contentView, @"This extension requires no special permissions."));
  EXPECT(!Text(p.sheet.contentView, @"Upstream permissions"));
  EXPECT(Button(p.sheet.contentView, @"Add Extension") != nil);
  EXPECT(!Scroll(p.sheet.contentView));
  [p.sheet cancelOperation:nil];
  Pump();
  EXPECT(_results == 1 && _choice == PCExtensionInstallCancel);
}

- (void)testAnExtensionWithABlankDisplayNameStillAsksToBeAdded {
  PCExtensionInstallPresenter* p = [self make];
  [p configureInstallationEducationWithName:@""];
  [p start];
  Pump();
  EXPECT(Text(p.sheet.contentView, @"Add this extension to Parc?"));
  EXPECT(Button(p.sheet.contentView, @"Add Extension") != nil);
  [p.sheet cancelOperation:nil];
  Pump();
  EXPECT(_results == 1 && _choice == PCExtensionInstallCancel);
}

- (void)testEducationListsTheRequestedPermissions {
  PCExtensionInstallPresenter* p = [self shownEducation];
  EXPECT(Text(p.sheet.contentView, @"It can:"));
  EXPECT(Text(p.sheet.contentView, @"Read browsing history"));
  EXPECT(Text(p.sheet.contentView, @"example.test"));
  NSScrollView* scroll = Scroll(p.sheet.contentView);
  EXPECT(scroll.frame.size.height > 0 && scroll.frame.size.height < 113);
  EXPECT(View(p.sheet.contentView, @"PCDialogFade").hidden);
  ExpectDialogFrame(p.sheet, scroll);
  [p invalidate];
}

- (void)testTheEducationSheetFillsItsDarkBackground {
  PCExtensionInstallPresenter* p = [self shownEducation];
  p.sheet.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
  NSSize panel = p.sheet.contentView.bounds.size;
  EXPECT(Fill(p.sheet, 2, 2, 21, 28, 48));
  EXPECT(Fill(p.sheet, panel.width - 2, panel.height - 2, 21, 28, 48));
  [p invalidate];
}

- (void)testTheEducationSheetFillsItsLightBackground {
  PCExtensionInstallPresenter* p = [self shownEducation];
  p.sheet.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
  EXPECT(Fill(p.sheet, 2, NSHeight(p.sheet.contentView.bounds) - 2, 250, 251, 255));
  [p invalidate];
}

- (void)testReturnAddsOnlyAfterTheProtectionDelayWithUnobstructedInput {
  PCExtensionInstallPresenter* p = [self shownEducation];
  NSButton* add = Button(p.sheet.contentView, @"Add Extension");
  EXPECT(!add.enabled && [add.keyEquivalent isEqual:@"\r"]);
  EXPECT(!Key(p.sheet, @"\r", 36, Uptime()));
  Pump();
  EXPECT(_results == 0);
  Pump(.5);
  EXPECT(add.enabled);
  _input = NO;
  EXPECT(Key(p.sheet, @"\r", 36, Uptime()));
  Pump();
  EXPECT(_results == 0 && !add.enabled);
  _input = YES;
  Pump(.2);
  const NSTimeInterval earlyPress = Uptime();
  Pump(.45);
  EXPECT(add.enabled);
  EXPECT(Key(p.sheet, @"\r", 36, Uptime(), YES));
  EXPECT(Key(p.sheet, @"\r", 36, earlyPress));
  Pump();
  EXPECT(_results == 0 && p.sheet);
  EXPECT(Key(p.sheet, @"\r", 36, Uptime()));
  Pump();
  EXPECT(_results == 1 && _choice == PCExtensionInstallAccept && !p.sheet);
  [p invalidate];
  Pump();
  EXPECT(_results == 1);
}

- (void)testLongPermissionDetailsWrapInsideTheScrollView {
  NSString* longDetail = [@"The extension can access this explicitly requested site. "
      stringByPaddingToLength:600
                   withString:@"Additional permission details wrap here. "
              startingAtIndex:0];
  PCExtensionInstallPresenter* p = [[PCExtensionInstallPresenter alloc] initWithWindow:_w
                                                                                 title:@"Install"
                                                                                  icon:nil
                                                                               heading:@"Permissions"
                                                                           permissions:@[ @"Read and change site data" ]
                                                                               details:@[ longDetail ]
                                                                           acceptLabel:@"Add"
                                                                           cancelLabel:@"Cancel"
                                                                         checkboxLabel:nil
                                                                              validate:^BOOL {
                                                                                return YES;
                                                                              }
                                                                          inputAllowed:self.inputAllowed
                                                                                result:self.result];
  p.presentation = ParcNativePresentation();
  p.scheduler = ParcNativeScheduler();
  [p configureInstallationEducationWithName:@"Example with detailed permissions"];
  [p start];
  Pump();
  NSScrollView* scroll = Scroll(p.sheet.contentView);
  scroll.scrollerStyle = NSScrollerStyleLegacy;
  [p.sheet.contentView layoutSubtreeIfNeeded];
  Pump();
  EXPECT(scroll.documentView.frame.size.width == scroll.contentView.bounds.size.width);
  EXPECT(Text(p.sheet.contentView, longDetail));
  EXPECT(scroll.frame.size.height == 113);
  ExpectDialogFrame(p.sheet, scroll);
  for (NSView* label in scroll.documentView.subviews) {
    EXPECT([label alignmentRectForFrame:label.frame].size.width <= scroll.contentView.bounds.size.width);
  }
  EXPECT(scroll.documentView.frame.size.height > 100);
  [p invalidate];
}

- (void)testThePermissionFadeDisappearsAtTheBottomOfTheScrollView {
  NSString* longDetail = [@"The extension can access this explicitly requested site. "
      stringByPaddingToLength:600
                   withString:@"Additional permission details wrap here. "
              startingAtIndex:0];
  PCExtensionInstallPresenter* p = [[PCExtensionInstallPresenter alloc] initWithWindow:_w
                                                                                 title:@"Install"
                                                                                  icon:nil
                                                                               heading:@"Permissions"
                                                                           permissions:@[ @"Read and change site data" ]
                                                                               details:@[ longDetail ]
                                                                           acceptLabel:@"Add"
                                                                           cancelLabel:@"Cancel"
                                                                         checkboxLabel:nil
                                                                              validate:^BOOL {
                                                                                return YES;
                                                                              }
                                                                          inputAllowed:self.inputAllowed
                                                                                result:self.result];
  p.presentation = ParcNativePresentation();
  p.scheduler = ParcNativeScheduler();
  [p configureInstallationEducationWithName:@"Example with detailed permissions"];
  [p start];
  Pump();
  NSScrollView* scroll = Scroll(p.sheet.contentView);
  scroll.scrollerStyle = NSScrollerStyleLegacy;
  [p.sheet.contentView layoutSubtreeIfNeeded];
  Pump();
  NSView* fade = View(p.sheet.contentView, @"PCDialogFade");
  EXPECT(fade && !fade.hidden);
  [scroll.documentView scrollPoint:NSMakePoint(0, NSMaxY(scroll.documentView.bounds))];
  Pump();
  EXPECT(fade.hidden);
  [p invalidate];
  Pump();
  EXPECT(_results == 1 && _choice == PCExtensionInstallInterrupted);
}

@end
