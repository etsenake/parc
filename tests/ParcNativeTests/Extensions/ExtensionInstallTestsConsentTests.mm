#import "ExtensionInstallTestsSupport.h"

using namespace ExtensionInstallTestsSupportFunctions;

__attribute__((objc_runtime_name("ParcNativeTests_ExtensionInstallTestsConsentTests")))
@interface ExtensionInstallTestsConsentTests : ExtensionInstallTestsSupport
@end

@implementation ExtensionInstallTestsConsentTests

- (void)testTheInstallSheetAttachesAfterStart {
  PCExtensionInstallPresenter* p = [self make];
  [p start];
  EXPECT(!p.sheet);
  Pump();
  EXPECT(p.sheet && ParcNativeAttachedSheet(_w) == p.sheet && ParcNativeVisible(p.sheet));
  [p invalidate];
}

- (void)testTheInstallSheetListsPermissions {
  PCExtensionInstallPresenter* p = [self shownPresenter];
  EXPECT(Text(p.sheet.contentView, @"• Read and change data on example.test"));
  EXPECT(Text(p.sheet.contentView, @"example.test"));
  EXPECT(Text(p.sheet.contentView, @"• Read browsing history"));
  auto* scroll = Scroll(p.sheet.contentView);
  EXPECT(scroll);
  EXPECT(scroll.documentView.frame.size.width > 0 && scroll.documentView.frame.size.height > 0);
  EXPECT(scroll.frame.size.height == 220);
  [p invalidate];
}

- (void)testInstallProtectsAddButLeavesTheCancelShortcutAvailable {
  PCExtensionInstallPresenter* p = [self make];
  [p start];
  Pump();
  NSButton* add = Button(p.sheet.contentView, @"Add");
  NSButton* cancel = Button(p.sheet.contentView, @"Cancel");
  EXPECT(add && cancel);
  EXPECT(!add.enabled);
  EXPECT(add.keyEquivalent.length == 0);
  EXPECT([cancel.keyEquivalent isEqual:@"\033"]);
  [NSApp sendAction:add.action to:add.target from:add];
  EXPECT(_results == 0);
  Pump(.5);
  EXPECT(add.enabled);
  [p invalidate];
}

- (void)testAddingReportsTheHostPermissionChoiceOnce {
  PCExtensionInstallPresenter* p = [self shownPresenter];
  Pump(.5);
  NSButton* checkbox = Button(p.sheet.contentView, @"Grant host permissions");
  EXPECT(checkbox && checkbox.state == NSControlStateValueOff);
  SendClick(checkbox);
  EXPECT(checkbox.state == NSControlStateValueOn);
  SendClick(Button(p.sheet.contentView, @"Add"));
  EXPECT(_results == 0);
  Pump();
  EXPECT(_results == 1 && _choice == PCExtensionInstallAccept && _grants);
  EXPECT(!p.sheet && !ParcNativeAttachedSheet(_w));
  [p invalidate];
  Pump();
  EXPECT(_results == 1);
}

- (void)testCancellingReportsCancelOnce {
  PCExtensionInstallPresenter* p = [self shownPresenter];
  [p.sheet cancelOperation:nil];
  Pump();
  EXPECT(_results == 1 && _choice == PCExtensionInstallCancel);
  [p invalidate];
  Pump();
  EXPECT(_results == 1);
}

- (void)testLosingValidityInterrupts {
  __block BOOL valid = YES;
  PCExtensionInstallPresenter* p = [self makeValidating:^BOOL {
    return valid;
  }];
  [p start];
  Pump();
  EXPECT(p.sheet != nil);
  valid = NO;
  Pump();
  EXPECT(_results == 1 && _choice == PCExtensionInstallInterrupted && !p.sheet);
}

- (void)testAHiddenWindowInterrupts {
  ParcNativeOrderOut(_w);
  PCExtensionInstallPresenter* p = [self make];
  [p start];
  Pump();
  EXPECT(_results == 1 && _choice == PCExtensionInstallInterrupted && !p.sheet);
}

- (void)testClosingTheWindowInterrupts {
  [self shownPresenter];
  ParcNativeClose(_w);
  Pump();
  EXPECT(_results == 1 && _choice == PCExtensionInstallInterrupted);
}

- (void)testObstructedInputRestartsTheProtectionDelay {
  _input = NO;
  PCExtensionInstallPresenter* p = [self make];
  [p start];
  Pump(.65);
  NSButton* add = Button(p.sheet.contentView, @"Add");
  EXPECT(!add.enabled);
  [NSApp sendAction:add.action to:add.target from:add];
  EXPECT(_results == 0);
  _input = YES;
  Pump(.12);
  EXPECT(!add.enabled);
  Pump(.5);
  EXPECT(add.enabled);
  SendClick(add);
  _input = NO;
  Pump();
  EXPECT(_results == 1 && _choice == PCExtensionInstallInterrupted);
}

- (void)testInvalidatingBeforeTheSheetAppearsInterruptsOnce {
  PCExtensionInstallPresenter* p = [self make];
  [p start];
  [p invalidate];
  [p invalidate];
  Pump();
  EXPECT(_results == 1 && _choice == PCExtensionInstallInterrupted && !ParcNativeAttachedSheet(_w));
}

- (void)testAValidationThatInvalidatesThePresenterInterrupts {
  __block PCExtensionInstallPresenter* reentrant = nil;
  reentrant = [self makeValidating:^BOOL {
    [reentrant invalidate];
    return YES;
  }];
  [reentrant start];
  Pump();
  EXPECT(_results == 1 && !reentrant.sheet && !ParcNativeAttachedSheet(_w));
  reentrant = nil;
}

- (void)testAnotherSheetOnTheWindowInterrupts {
  NSWindow* other = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100)
                                                styleMask:NSWindowStyleMaskBorderless
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
  ParcNativeBeginSheet(_w, other, nil);
  PCExtensionInstallPresenter* p = [self make];
  [p start];
  Pump();
  EXPECT(_results == 1 && _choice == PCExtensionInstallInterrupted && ParcNativeAttachedSheet(_w) == other);
  ParcNativeEndSheet(_w, other);
  ParcNativeOrderOut(other);
}

@end
