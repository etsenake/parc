#import <AppKit/AppKit.h>

#include <cstdio>
#include <cstdlib>

#import "extension_uninstall_presenter.h"
#import "window_security_reservation.h"
static int assertions = 0;
#define EXPECT(x)                                                 \
  do {                                                            \
    ++assertions;                                                 \
    if (!(x)) {                                                   \
      fprintf(stderr, "FAIL %s:%d %s\n", __FILE__, __LINE__, #x); \
      abort();                                                    \
    }                                                             \
  } while (0)
static void Pump(double seconds = .12) {
  NSDate* until = [NSDate dateWithTimeIntervalSinceNow:seconds];
  while (until.timeIntervalSinceNow > 0) {
    [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode
                        beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    NSEvent* event;
    while ((event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                       untilDate:NSDate.distantPast
                                          inMode:NSDefaultRunLoopMode
                                         dequeue:YES])) {
      [NSApp sendEvent:event];
    }
  }
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
int main() {
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSWindow* a = Window();
    NSWindow* b = Window();
    EXPECT(a.visible && b.visible);
    __block int notifications = 0;
    id observation = [NSNotificationCenter.defaultCenter
        addObserverForName:PCNativeWindowSecurityStateChanged
                    object:a
                     queue:nil
                usingBlock:^(NSNotification*) {
                  ++notifications;
                }];
    auto* first = [PCNativeWindowSecurityReservation acquireForWindow:a];
    EXPECT(first.isOnlyReservation);
    auto* second = [PCNativeWindowSecurityReservation acquireForWindow:a];
    EXPECT(first.active && second.active);
    EXPECT(!first.isOnlyReservation && !second.isOnlyReservation);
    EXPECT(PCNativeWindowHasSecurityReservation(a));
    EXPECT(!PCNativeWindowHasSecurityReservation(b));
    EXPECT(notifications == 2);
    [first invalidate];
    EXPECT(!first.active && second.active);
    EXPECT(!first.isOnlyReservation && second.isOnlyReservation);
    EXPECT(PCNativeWindowHasSecurityReservation(a));
    EXPECT(notifications == 3);
    [first invalidate];
    EXPECT(notifications == 3);
    [second invalidate];
    EXPECT(!second.isOnlyReservation);
    EXPECT(!PCNativeWindowHasSecurityReservation(a));
    EXPECT(notifications == 4);
    [NSNotificationCenter.defaultCenter removeObserver:observation];
    __block PCNativeWindowSecurityReservation* replacement = nil;
    first = [PCNativeWindowSecurityReservation acquireForWindow:a];
    observation = [NSNotificationCenter.defaultCenter
        addObserverForName:PCNativeWindowSecurityStateChanged
                    object:a
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (!PCNativeWindowHasSecurityReservation(a)) {
                    replacement =
                        [PCNativeWindowSecurityReservation acquireForWindow:a];
                  }
                }];
    [first invalidate];
    EXPECT(replacement.active);
    EXPECT(replacement.isOnlyReservation && !first.isOnlyReservation);
    EXPECT(!first.active);
    [NSNotificationCenter.defaultCenter removeObserver:observation];
    [replacement invalidate];
    replacement = nil;
    observation = [NSNotificationCenter.defaultCenter
        addObserverForName:PCNativeWindowSecurityStateChanged
                    object:b
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (PCNativeWindowHasSecurityReservation(b)) {
                    [b close];
                  }
                }];
    auto* closed = [PCNativeWindowSecurityReservation acquireForWindow:b];
    EXPECT(!closed.active);
    EXPECT(!closed.isOnlyReservation);
    EXPECT(!PCNativeWindowHasSecurityReservation(b));
    EXPECT([PCNativeWindowSecurityReservation acquireForWindow:b] == nil);
    [NSNotificationCenter.defaultCenter removeObserver:observation];
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
    __block int results = 0, changes = 0;
    __block PCUninstallChoice choice = PCUninstallInterrupted;
    auto* presenter = Presenter(
        a,
        ^BOOL {
          return YES;
        },
        ^(BOOL checked) {
          EXPECT(checked);
          ++changes;
        },
        ^(PCUninstallChoice c) {
          ++results;
          choice = c;
        });
    [presenter start];
    Pump();
    EXPECT(presenter.presenting);
    EXPECT(presenter.sheet.sheetParent == a);
    EXPECT(results == 0);
    auto* check = Button(presenter.sheet.contentView, @"Report abuse");
    EXPECT(check);
    [check performClick:nil];
    EXPECT(changes == 1);
    auto* accept = Button(presenter.sheet.contentView, @"Remove");
    EXPECT(accept);
    [accept performClick:nil];
    Pump(.3);
    EXPECT(results == 1 && choice == PCUninstallAccept);
    EXPECT(!presenter.presenting);
    [presenter invalidate];
    EXPECT(results == 1);
    results = 0;
    presenter = Presenter(
        a,
        ^BOOL {
          return YES;
        },
        ^(BOOL){
        },
        ^(PCUninstallChoice c) {
          ++results;
          choice = c;
        });
    [presenter start];
    Pump();
    EXPECT(presenter.presenting);
    NSWindow* sheet = presenter.sheet;
    NSEvent* escape = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                       location:NSZeroPoint
                                  modifierFlags:0
                                      timestamp:0
                                   windowNumber:sheet.windowNumber
                                        context:nil
                                     characters:@"\033"
                    charactersIgnoringModifiers:@"\033"
                                      isARepeat:NO
                                        keyCode:53];
    EXPECT([sheet performKeyEquivalent:escape]);
    Pump(.3);
    EXPECT(results == 1 && choice == PCUninstallCancel);
    results = 0;
    presenter = Presenter(
        a,
        ^BOOL {
          return YES;
        },
        ^(BOOL){
        },
        ^(PCUninstallChoice c) {
          ++results;
          choice = c;
        });
    [presenter start];
    [presenter invalidate];
    Pump();
    EXPECT(results == 1 && choice == PCUninstallInterrupted);
    EXPECT(!presenter.presenting && a.attachedSheet == nil);
    __block PCNativeUninstallPresenter* reentrant;
    results = 0;
    reentrant = Presenter(
        a,
        ^BOOL {
          [reentrant invalidate];
          return YES;
        },
        ^(BOOL){
        },
        ^(PCUninstallChoice c) {
          ++results;
          choice = c;
        });
    [reentrant start];
    Pump();
    EXPECT(results == 1 && choice == PCUninstallInterrupted);
    EXPECT(!reentrant.presenting);
    reentrant = nil;
    results = 0;
    presenter = Presenter(
        a,
        ^BOOL {
          return YES;
        },
        ^(BOOL){
        },
        ^(PCUninstallChoice c) {
          ++results;
          choice = c;
        });
    EXPECT([presenter.sheet isKindOfClass:NSPanel.class]);
    EXPECT(!presenter.sheet.visible);
    [presenter setAcceptEnabled:NO cancelEnabled:YES];
    [presenter start];
    Pump();
    NSWindow* custom = presenter.sheet;
    [custom insertNewline:nil];
    EXPECT(results == 0);
    EXPECT([Button(custom.contentView, @"Remove").accessibilityLabel
        isEqualToString:@"Remove"]);
    [presenter setAcceptEnabled:YES cancelEnabled:YES];
    NSEvent* enter = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                      location:NSZeroPoint
                                 modifierFlags:0
                                     timestamp:0
                                  windowNumber:custom.windowNumber
                                       context:nil
                                    characters:@"\r"
                   charactersIgnoringModifiers:@"\r"
                                     isARepeat:NO
                                       keyCode:36];
    [custom makeKeyWindow];
    [custom sendEvent:enter];
    Pump(.3);
    EXPECT(results == 1 && choice == PCUninstallAccept);
    NSWindow* foreign = Window();
    [a beginSheet:foreign completionHandler:nil];
    results = 0;
    presenter = Presenter(
        a,
        ^BOOL {
          return YES;
        },
        ^(BOOL){
        },
        ^(PCUninstallChoice c) {
          ++results;
          choice = c;
        });
    [presenter start];
    Pump();
    EXPECT(results == 1 && choice == PCUninstallInterrupted);
    EXPECT(a.attachedSheet == foreign);
    [a endSheet:foreign];
    [foreign close];
    Pump();
    results = 0;
    presenter = Presenter(
        a,
        ^BOOL {
          return YES;
        },
        ^(BOOL){
        },
        ^(PCUninstallChoice c) {
          ++results;
          choice = c;
        });
    [presenter start];
    Pump();
    EXPECT(presenter.presenting);
    [a close];
    Pump();
    EXPECT(results == 1 && choice == PCUninstallInterrupted);
    EXPECT(!presenter.presenting);
    printf("PASS %d assertions / 9 groups\n", assertions);
  }
}
