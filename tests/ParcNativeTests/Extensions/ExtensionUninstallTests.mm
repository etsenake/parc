#import <AppKit/AppKit.h>
#import "ParcNativeTest.h"
#import "ParcNativeClock.h"

#include <cstdio>
#include <cstdlib>

#import "extension_uninstall_presenter.h"
#import "window_security_reservation.h"
#define EXPECT(condition) PARC_CHECK(condition)
static void Pump(double seconds = .12) {
  ParcNativeAdvance(seconds);
}
static NSWindow* Window() {
  NSWindow* window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(50, 50, 500, 300)
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                  backing:NSBackingStoreBuffered
                    defer:NO];
  window.releasedWhenClosed = NO;
  [window orderFront:nil];
  return window;
}
static NSButton* Button(NSView* root, NSString* title) {
  if ([root isKindOfClass:NSButton.class] &&
      [((NSButton*)root).title isEqualToString:title]) {
    return (NSButton*)root;
  }
  for (NSView* view in root.subviews) {
    if (NSButton* button = Button(view, title)) {
      return button;
    }
  }
  return nil;
}
static PCNativeUninstallPresenter* Presenter(
    NSWindow* window,
    BOOL (^valid)(void),
    void (^changed)(BOOL),
    void (^result)(PCUninstallChoice)) {
  return
      [[PCNativeUninstallPresenter alloc] initWithWindow:window
                                                   title:@"Remove example?"
                                                 message:@"Requested by example"
                                                    icon:nil
                                             acceptLabel:@"Remove"
                                             cancelLabel:@"Cancel"
                                           checkboxLabel:@"Report abuse"
                                                 checked:NO
                                                validate:valid
                                                 changed:changed
                                                  result:result];
}
static NSEvent* KeyIn(NSWindow* window, NSString* characters, unsigned short code) {
  return [NSEvent keyEventWithType:NSEventTypeKeyDown
                          location:NSZeroPoint
                     modifierFlags:0
                         timestamp:0
                      windowNumber:window.windowNumber
                           context:nil
                        characters:characters
       charactersIgnoringModifiers:characters
                         isARepeat:NO
                           keyCode:code];
}

@interface ExtensionUninstallTests : ParcNativeTestCase
@end

@implementation ExtensionUninstallTests {
  NSWindow* _a;
  NSWindow* _b;
  int _results;
  PCUninstallChoice _choice;
  NSMutableArray<id>* _observers;
}

+ (NSApplicationActivationPolicy)activationPolicy {
  return NSApplicationActivationPolicyAccessory;
}

- (void)setUp {
  [super setUp];
  _a = Window();
  _b = Window();
  _choice = PCUninstallInterrupted;
  _observers = [NSMutableArray array];
}

- (void)tearDown {
  for (id observer in _observers) [NSNotificationCenter.defaultCenter removeObserver:observer];
  [_a close];
  [_b close];
  Pump();
  [super tearDown];
}

- (void)observe:(NSWindow*)window with:(void (^)(void))block {
  [_observers addObject:[NSNotificationCenter.defaultCenter addObserverForName:PCNativeWindowSecurityStateChanged
                                                                        object:window
                                                                         queue:nil
                                                                    usingBlock:^(NSNotification*) {
                                                                      block();
                                                                    }]];
}

- (PCNativeUninstallPresenter*)presenterValidating:(BOOL (^)(void))valid changed:(void (^)(BOOL))changed {
  int* results = &_results;
  PCUninstallChoice* choice = &_choice;
  return Presenter(_a, valid, changed ?: ^(BOOL) {
  }, ^(PCUninstallChoice c) {
    ++*results;
    *choice = c;
  });
}

- (PCNativeUninstallPresenter*)presenter {
  return [self presenterValidating:^BOOL {
    return YES;
  } changed:nil];
}

- (void)testReservationsAreSharedPerWindowAndNotifyEachChange {
  EXPECT(_a.visible && _b.visible);
  __block int notifications = 0;
  [self observe:_a with:^{
    ++notifications;
  }];
  auto* first = [PCNativeWindowSecurityReservation acquireForWindow:_a];
  EXPECT(first.isOnlyReservation);
  auto* second = [PCNativeWindowSecurityReservation acquireForWindow:_a];
  EXPECT(first.active && second.active);
  EXPECT(!first.isOnlyReservation && !second.isOnlyReservation);
  EXPECT(PCNativeWindowHasSecurityReservation(_a));
  EXPECT(!PCNativeWindowHasSecurityReservation(_b));
  EXPECT(notifications == 2);
  [first invalidate];
  EXPECT(!first.active && second.active);
  EXPECT(!first.isOnlyReservation && second.isOnlyReservation);
  EXPECT(PCNativeWindowHasSecurityReservation(_a));
  EXPECT(notifications == 3);
  [first invalidate];
  EXPECT(notifications == 3);
  [second invalidate];
  EXPECT(!second.isOnlyReservation);
  EXPECT(!PCNativeWindowHasSecurityReservation(_a));
  EXPECT(notifications == 4);
}

- (void)testAReplacementTakenDuringReleaseBecomesTheOnlyReservation {
  __block PCNativeWindowSecurityReservation* replacement = nil;
  auto* first = [PCNativeWindowSecurityReservation acquireForWindow:_a];
  NSWindow* a = _a;
  [self observe:_a with:^{
    if (!PCNativeWindowHasSecurityReservation(a)) replacement = [PCNativeWindowSecurityReservation acquireForWindow:a];
  }];
  [first invalidate];
  EXPECT(replacement.active);
  EXPECT(replacement.isOnlyReservation && !first.isOnlyReservation);
  EXPECT(!first.active);
  [replacement invalidate];
}

- (void)testAWindowClosedWhileReservingRefusesTheReservation {
  NSWindow* b = _b;
  [self observe:_b with:^{
    if (PCNativeWindowHasSecurityReservation(b)) [b close];
  }];
  auto* closed = [PCNativeWindowSecurityReservation acquireForWindow:_b];
  EXPECT(!closed.active);
  EXPECT(!closed.isOnlyReservation);
  EXPECT(!PCNativeWindowHasSecurityReservation(_b));
  EXPECT([PCNativeWindowSecurityReservation acquireForWindow:_b] == nil);
}

- (void)testClosingAWindowEndsItsReservationAndReleasesIt {
  __weak NSWindow* weakWindow;
  PCNativeWindowSecurityReservation* retained;
  @autoreleasepool {
    NSWindow* temp = Window();
    weakWindow = temp;
    retained = [PCNativeWindowSecurityReservation acquireForWindow:temp];
    [temp close];
    temp = nil;
  }
  Pump();
  EXPECT(!retained.active);
  EXPECT(!retained.isOnlyReservation);
  EXPECT(weakWindow == nil);
  [retained invalidate];
}

- (void)testRemoveAcceptsAndReportsTheAbuseChoice {
  __block int changes = 0;
  auto* presenter = [self presenterValidating:^BOOL {
    return YES;
  } changed:^(BOOL checked) {
    EXPECT(checked);
    ++changes;
  }];
  [presenter start];
  Pump();
  EXPECT(presenter.presenting);
  EXPECT(presenter.sheet.sheetParent == _a);
  EXPECT(_results == 0);
  auto* check = Button(presenter.sheet.contentView, @"Report abuse");
  EXPECT(check);
  [check performClick:nil];
  EXPECT(changes == 1);
  auto* accept = Button(presenter.sheet.contentView, @"Remove");
  EXPECT(accept);
  [accept performClick:nil];
  Pump(.3);
  EXPECT(_results == 1 && _choice == PCUninstallAccept);
  EXPECT(!presenter.presenting);
  [presenter invalidate];
  EXPECT(_results == 1);
}

- (void)testEscapeCancels {
  auto* presenter = [self presenter];
  [presenter start];
  Pump();
  EXPECT(presenter.presenting);
  EXPECT([presenter.sheet performKeyEquivalent:KeyIn(presenter.sheet, @"\033", 53)]);
  Pump(.3);
  EXPECT(_results == 1 && _choice == PCUninstallCancel);
}

- (void)testInvalidatingBeforeTheSheetAppearsInterrupts {
  auto* presenter = [self presenter];
  [presenter start];
  [presenter invalidate];
  Pump();
  EXPECT(_results == 1 && _choice == PCUninstallInterrupted);
  EXPECT(!presenter.presenting && _a.attachedSheet == nil);
}

- (void)testAValidationThatInvalidatesThePresenterInterrupts {
  __block PCNativeUninstallPresenter* reentrant;
  reentrant = [self presenterValidating:^BOOL {
    [reentrant invalidate];
    return YES;
  } changed:nil];
  [reentrant start];
  Pump();
  EXPECT(_results == 1 && _choice == PCUninstallInterrupted);
  EXPECT(!reentrant.presenting);
  reentrant = nil;
}

- (void)testReturnRemovesOnlyOnceRemoveIsEnabled {
  auto* presenter = [self presenter];
  EXPECT([presenter.sheet isKindOfClass:NSPanel.class]);
  EXPECT(!presenter.sheet.visible);
  [presenter setAcceptEnabled:NO cancelEnabled:YES];
  [presenter start];
  Pump();
  NSWindow* custom = presenter.sheet;
  [custom insertNewline:nil];
  EXPECT(_results == 0);
  EXPECT([Button(custom.contentView, @"Remove").accessibilityLabel isEqualToString:@"Remove"]);
  [presenter setAcceptEnabled:YES cancelEnabled:YES];
  [custom makeKeyWindow];
  [custom sendEvent:KeyIn(custom, @"\r", 36)];
  Pump(.3);
  EXPECT(_results == 1 && _choice == PCUninstallAccept);
}

- (void)testAnotherSheetOnTheWindowInterrupts {
  NSWindow* foreign = Window();
  [_a beginSheet:foreign completionHandler:nil];
  auto* presenter = [self presenter];
  [presenter start];
  Pump();
  EXPECT(_results == 1 && _choice == PCUninstallInterrupted);
  EXPECT(_a.attachedSheet == foreign);
  [_a endSheet:foreign];
  [foreign close];
}

- (void)testClosingTheWindowInterrupts {
  auto* presenter = [self presenter];
  [presenter start];
  Pump();
  EXPECT(presenter.presenting);
  [_a close];
  Pump();
  EXPECT(_results == 1 && _choice == PCUninstallInterrupted);
  EXPECT(!presenter.presenting);
}

@end
