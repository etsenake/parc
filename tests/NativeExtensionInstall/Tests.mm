#import <AppKit/AppKit.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>

#import "extension_install_presenter.h"
#import "window_security_reservation.h"
static int assertions;
#define EXPECT(x)                                    \
  do {                                               \
    ++assertions;                                    \
    if (!(x)) {                                      \
      fprintf(stderr, "FAIL %d %s\n", __LINE__, #x); \
      abort();                                       \
    }                                                \
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
  auto* w = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(-20000, -20000, 600, 500)
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                  backing:NSBackingStoreBuffered
                    defer:NO];
  w.releasedWhenClosed = NO;
  [w orderFront:nil];
  return w;
}
static NSButton* Button(NSView* root, NSString* title) {
  if ([root isKindOfClass:NSButton.class] &&
      [((NSButton*)root).title isEqual:title]) {
    return (NSButton*)root;
  }
  for (NSView* child in root.subviews) {
    if (auto* b = Button(child, title)) {
      return b;
    }
  }
  return nil;
}
static NSScrollView* Scroll(NSView* root) {
  if ([root isKindOfClass:NSScrollView.class]) {
    return (NSScrollView*)root;
  }
  for (NSView* child in root.subviews) {
    if (auto* scroll = Scroll(child)) {
      return scroll;
    }
  }
  return nil;
}
static BOOL Text(NSView* root, NSString* expected) {
  if ([root isKindOfClass:NSTextField.class] &&
      [((NSTextField*)root).stringValue isEqual:expected]) {
    return YES;
  }
  for (NSView* child in root.subviews) {
    if (Text(child, expected)) {
      return YES;
    }
  }
  return NO;
}
static NSView* View(NSView* root, NSString* className) {
  if ([root.className isEqual:className]) {
    return root;
  }
  for (NSView* child in root.subviews) {
    if (auto* view = View(child, className)) {
      return view;
    }
  }
  return nil;
}
static BOOL Near(CGFloat a, CGFloat b) {
  return std::abs(a - b) < .01;
}
//
// content-sized up to 113 points, and 28 points above the panel's bottom.
static void ExpectDialogFrame(NSWindow* sheet, NSScrollView* scroll) {
  NSView* root = sheet.contentView;
  NSButton* add = Button(root, @"Add Extension");
  EXPECT(Near(NSHeight(scroll.frame),
              std::min<CGFloat>(NSHeight(scroll.documentView.frame), 113)));
  EXPECT(Near(NSMinY(add.frame) + .5, NSMaxY(scroll.frame) + 8));
  // The window rounds the content height to a whole point.
  EXPECT(std::abs(NSHeight(root.frame) - (NSMinY(add.frame) + .5 + 36 + 28)) < 1);
  EXPECT(NSEqualSizes(sheet.frame.size, root.frame.size));
}
// The content view itself paints the panel; an attached sheet's own material
// would otherwise show through.
static BOOL Fill(NSWindow* sheet, CGFloat x, CGFloat y, int r, int g, int b) {
  NSView* root = sheet.contentView;
  NSBitmapImageRep* rep = [root bitmapImageRepForCachingDisplayInRect:root.bounds];
  [root cacheDisplayInRect:root.bounds toBitmapImageRep:rep];
  NSColor* c = [rep colorAtX:(NSInteger)(x * rep.pixelsWide / NSWidth(root.bounds))
                           y:(NSInteger)(y * rep.pixelsHigh / NSHeight(root.bounds))];
  NSColor* expected = [[NSColor colorWithSRGBRed:r / 255. green:g / 255. blue:b / 255. alpha:1]
      colorUsingColorSpace:rep.colorSpace];
  return root.opaque && c.alphaComponent > .99 &&
         std::abs(c.redComponent - expected.redComponent) < 1.5 / 255 &&
         std::abs(c.greenComponent - expected.greenComponent) < 1.5 / 255 &&
         std::abs(c.blueComponent - expected.blueComponent) < 1.5 / 255;
}
static NSTimeInterval Uptime() {
  return NSProcessInfo.processInfo.systemUptime;
}
static BOOL Key(NSWindow* sheet, NSString* key, unsigned short code,
                NSTimeInterval timestamp, BOOL repeat = NO) {
  return [sheet performKeyEquivalent:[NSEvent keyEventWithType:NSEventTypeKeyDown
                                                       location:NSZeroPoint
                                                  modifierFlags:0
                                                      timestamp:timestamp
                                                   windowNumber:sheet.windowNumber
                                                        context:nil
                                                     characters:key
                                    charactersIgnoringModifiers:key
                                                      isARepeat:repeat
                                                        keyCode:code]];
}
static PCExtensionInstallPresenter* Make(
    NSWindow* w,
    BOOL (^valid)(),
    BOOL (^input)(NSWindow*),
    void (^result)(PCExtensionInstallChoice, BOOL)) {
  return [[PCExtensionInstallPresenter alloc]
      initWithWindow:w
               title:@"Add example?"
                icon:nil
             heading:@"It can:"
         permissions:@[
           @"Read and change data on example.test", @"Read browsing history"
         ]
             details:@[ @"example.test", @"" ]
         acceptLabel:@"Add"
         cancelLabel:@"Cancel"
       checkboxLabel:@"Grant host permissions"
            validate:valid
        inputAllowed:input
              result:result];
}
int main() {
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSWindow* w = Window();
    auto* first = [PCNativeWindowSecurityReservation acquireForWindow:w];
    EXPECT(first.active && first.isOnlyReservation);
    auto* second = [PCNativeWindowSecurityReservation acquireForWindow:w];
    EXPECT(second.active && !first.isOnlyReservation &&
           !second.isOnlyReservation);
    [second invalidate];
    EXPECT(first.isOnlyReservation && !second.isOnlyReservation);
    [first invalidate];
    EXPECT(!first.isOnlyReservation);
    __block BOOL soleInside = NO;
    id observer = [NSNotificationCenter.defaultCenter
        addObserverForName:PCNativeWindowSecurityStateChanged
                    object:w
                     queue:nil
                usingBlock:^(NSNotification*) {
                  soleInside = first.isOnlyReservation;
                }];
    first = [PCNativeWindowSecurityReservation acquireForWindow:w];
    EXPECT(first.isOnlyReservation);
    [first invalidate];
    EXPECT(!soleInside && !first.isOnlyReservation);
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    auto* closing = Window();
    first = [PCNativeWindowSecurityReservation acquireForWindow:closing];
    EXPECT(first.isOnlyReservation);
    [closing close];
    EXPECT(!first.active && !first.isOnlyReservation);

    __block int results = 0;
    __block PCExtensionInstallChoice choice = PCExtensionInstallInterrupted;
    __block BOOL grants = NO;
    auto result = ^(PCExtensionInstallChoice c, BOOL g) {
      ++results;
      choice = c;
      grants = g;
    };
    auto* p = Make(
        w,
        ^BOOL {
          return YES;
        },
        ^BOOL(NSWindow*) {
          return YES;
        },
        result);
    [p start];
    EXPECT(!p.sheet);
    Pump();
    EXPECT(p.sheet && w.attachedSheet == p.sheet && p.sheet.visible);
    NSButton* add = Button(p.sheet.contentView, @"Add");
    NSButton* cancel = Button(p.sheet.contentView, @"Cancel");
    EXPECT(add && cancel);
    EXPECT(
        Text(p.sheet.contentView, @"• Read and change data on example.test"));
    EXPECT(Text(p.sheet.contentView, @"example.test"));
    EXPECT(Text(p.sheet.contentView, @"• Read browsing history"));
    auto* scroll = Scroll(p.sheet.contentView);
    EXPECT(scroll);
    EXPECT(scroll.documentView.frame.size.width > 0 &&
           scroll.documentView.frame.size.height > 0);
    EXPECT(scroll.frame.size.height == 220);
    EXPECT(!add.enabled);
    EXPECT(add.keyEquivalent.length == 0);
    EXPECT([cancel.keyEquivalent isEqual:@"\033"]);
    [NSApp sendAction:add.action to:add.target from:add];
    EXPECT(results == 0);
    Pump(.5);
    EXPECT(add.enabled);
    NSButton* checkbox = Button(p.sheet.contentView, @"Grant host permissions");
    EXPECT(checkbox && checkbox.state == NSControlStateValueOff);
    [checkbox performClick:nil];
    EXPECT(checkbox.state == NSControlStateValueOn);
    [add performClick:nil];
    EXPECT(results == 0);
    Pump();
    EXPECT(results == 1 && choice == PCExtensionInstallAccept && grants);
    EXPECT(!p.sheet && !w.attachedSheet);
    [p invalidate];
    Pump();
    EXPECT(results == 1);
    // Escape is cancellation, never acceptance; no repeat callback.
    p = Make(
        w,
        ^BOOL {
          return YES;
        },
        ^BOOL(NSWindow*) {
          return YES;
        },
        result);
    [p start];
    Pump();
    [p.sheet cancelOperation:nil];
    Pump();
    EXPECT(results == 2 && choice == PCExtensionInstallCancel);
    [p invalidate];
    Pump();
    EXPECT(results == 2);
    // Closing, navigation/identity changes, and hidden parents interrupt.
    __block BOOL valid = YES;
    p = Make(
        w,
        ^BOOL {
          return valid;
        },
        ^BOOL(NSWindow*) {
          return YES;
        },
        result);
    [p start];
    Pump();
    EXPECT(p.sheet != nil);
    valid = NO;
    Pump();
    EXPECT(results == 3 && choice == PCExtensionInstallInterrupted && !p.sheet);
    [w orderOut:nil];
    p = Make(
        w,
        ^BOOL {
          return YES;
        },
        ^BOOL(NSWindow*) {
          return YES;
        },
        result);
    [p start];
    Pump();
    EXPECT(results == 4 && choice == PCExtensionInstallInterrupted && !p.sheet);
    [w orderFront:nil];
    // Actual native close cancels pending consent exactly once.
    p = Make(
        w,
        ^BOOL {
          return YES;
        },
        ^BOOL(NSWindow*) {
          return YES;
        },
        result);
    [p start];
    Pump();
    [w close];
    Pump();
    EXPECT(results == 5 && choice == PCExtensionInstallInterrupted);
    w = Window();
    // Occlusion prevents both button activation and direct action dispatch,
    // then starts a fresh 500ms delay after unobstructed visibility.
    __block BOOL input = NO;
    p = Make(
        w,
        ^BOOL {
          return YES;
        },
        ^BOOL(NSWindow*) {
          return input;
        },
        result);
    [p start];
    Pump(.65);
    add = Button(p.sheet.contentView, @"Add");
    EXPECT(!add.enabled);
    [NSApp sendAction:add.action to:add.target from:add];
    EXPECT(results == 5);
    input = YES;
    Pump(.12);
    EXPECT(!add.enabled);
    Pump(.5);
    EXPECT(add.enabled);
    // Recheck between click and deferred callback; don't grant a stale
    // decision.
    [add performClick:nil];
    input = NO;
    Pump();
    EXPECT(results == 6 && choice == PCExtensionInstallInterrupted);
    // Close before scheduled attachment, including repeated invalidation.
    p = Make(
        w,
        ^BOOL {
          return YES;
        },
        ^BOOL(NSWindow*) {
          return YES;
        },
        result);
    [p start];
    [p invalidate];
    [p invalidate];
    Pump();
    EXPECT(results == 7 && choice == PCExtensionInstallInterrupted &&
           !w.attachedSheet);
    // Reentrant validation cannot attach after invalidation.
    __block PCExtensionInstallPresenter* reentrant = nil;
    reentrant = Make(
        w,
        ^BOOL {
          [reentrant invalidate];
          return YES;
        },
        ^BOOL(NSWindow*) {
          return YES;
        },
        result);
    [reentrant start];
    Pump();
    EXPECT(results == 8 && !reentrant.sheet && !w.attachedSheet);
    reentrant = nil;
    // An unrelated attached sheet is never displaced.
    NSWindow* other =
        [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100)
                                    styleMask:NSWindowStyleMaskTitled
                                      backing:NSBackingStoreBuffered
                                        defer:NO];
    [w beginSheet:other completionHandler:nil];
    p = Make(
        w,
        ^BOOL {
          return YES;
        },
        ^BOOL(NSWindow*) {
          return YES;
        },
        result);
    [p start];
    Pump();
    EXPECT(results == 9 && choice == PCExtensionInstallInterrupted &&
           w.attachedSheet == other);
    [w endSheet:other];
    [other orderOut:nil];
    Pump();
    // Ordinary education is configured from actual install inputs. Missing
    // artwork still explains the destination; an empty permission set is not
    // represented as a blank permission list or a successful installation.
    p = [[PCExtensionInstallPresenter alloc] initWithWindow:w
        title:@"Upstream install" icon:nil heading:@"Upstream permissions"
        permissions:@[] details:@[] acceptLabel:@"Add" cancelLabel:@"Cancel"
        checkboxLabel:nil validate:^BOOL { return YES; }
        inputAllowed:^BOOL(NSWindow*) { return YES; } result:result];
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
    EXPECT(results == 10 && choice == PCExtensionInstallCancel);
    input = YES;
    w.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    p = Make(w, ^BOOL { return YES; }, ^BOOL(NSWindow*) { return input; }, result);
    [p configureInstallationEducationWithName:@"Example"];
    [p start];
    Pump();
    EXPECT(Text(p.sheet.contentView, @"It can:"));
    EXPECT(Text(p.sheet.contentView, @"Read browsing history"));
    EXPECT(Text(p.sheet.contentView, @"example.test"));
    //
    scroll = Scroll(p.sheet.contentView);
    EXPECT(scroll.frame.size.height > 0 && scroll.frame.size.height < 113);
    EXPECT(View(p.sheet.contentView, @"PCDialogFade").hidden);
    ExpectDialogFrame(p.sheet, scroll);
    // PopoverBackground follows the window's appearance, edge to edge.
    const NSSize panel = p.sheet.contentView.bounds.size;
    EXPECT(Fill(p.sheet, 2, 2, 21, 28, 48));
    EXPECT(Fill(p.sheet, panel.width - 2, panel.height - 2, 21, 28, 48));
    w.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    EXPECT(Fill(p.sheet, 2, panel.height - 2, 250, 251, 255));
    w.appearance = nil;
    add = Button(p.sheet.contentView, @"Add Extension");
    EXPECT(!add.enabled && [add.keyEquivalent isEqual:@"\r"]);
    // Return, like the button, is inert during Chromium's input delay.
    EXPECT(!Key(p.sheet, @"\r", 36, Uptime()));
    Pump();
    EXPECT(results == 10);
    Pump(.5);
    EXPECT(add.enabled);
    // Obstruction refuses Return before the button's state catches up, then
    // restarts the delay.
    input = NO;
    EXPECT(Key(p.sheet, @"\r", 36, Uptime()));
    Pump();
    EXPECT(results == 10 && !add.enabled);
    input = YES;
    Pump(.2);
    const NSTimeInterval earlyPress = Uptime();
    Pump(.45);
    EXPECT(add.enabled);
    // Neither a held Return's repeat nor a Return pressed during the delay
    // accepts once the delay ends.
    EXPECT(Key(p.sheet, @"\r", 36, Uptime(), YES));
    EXPECT(Key(p.sheet, @"\r", 36, earlyPress));
    Pump();
    EXPECT(results == 10 && p.sheet);
    EXPECT(Key(p.sheet, @"\r", 36, Uptime()));
    Pump();
    EXPECT(results == 11 && choice == PCExtensionInstallAccept && !p.sheet);
    [p invalidate];
    Pump();
    EXPECT(results == 11);
    NSString* longDetail = [@"The extension can access this explicitly requested site. "
        stringByPaddingToLength:600 withString:@"Additional permission details wrap here. " startingAtIndex:0];
    p = [[PCExtensionInstallPresenter alloc] initWithWindow:w
        title:@"Install" icon:nil heading:@"Permissions"
        permissions:@[@"Read and change site data"] details:@[longDetail]
        acceptLabel:@"Add" cancelLabel:@"Cancel" checkboxLabel:nil
        validate:^BOOL { return YES; }
        inputAllowed:^BOOL(NSWindow*) { return YES; } result:result];
    [p configureInstallationEducationWithName:@"Example with detailed permissions"];
    [p start];
    Pump();
    scroll = Scroll(p.sheet.contentView);
    scroll.scrollerStyle = NSScrollerStyleLegacy;
    [p.sheet.contentView layoutSubtreeIfNeeded];
    Pump();
    EXPECT(scroll.documentView.frame.size.width == scroll.contentView.bounds.size.width);
    EXPECT(Text(p.sheet.contentView, longDetail));
    EXPECT(scroll.frame.size.height == 113);
    ExpectDialogFrame(p.sheet, scroll);
    NSView* fade = View(p.sheet.contentView, @"PCDialogFade");
    EXPECT(fade && !fade.hidden);
    [scroll.documentView scrollPoint:NSMakePoint(0, NSMaxY(scroll.documentView.bounds))];
    Pump();
    EXPECT(fade.hidden);
    for (NSView* label in scroll.documentView.subviews) {
      // NSTextField's drawing frame includes its native alignment insets.
      EXPECT([label alignmentRectForFrame:label.frame].size.width <=
             scroll.contentView.bounds.size.width);
    }
    EXPECT(scroll.documentView.frame.size.height > 100);
    [p invalidate];
    Pump();
    EXPECT(results == 12 && choice == PCExtensionInstallInterrupted);
    //
    NSImage* artwork = [NSImage imageWithSystemSymbolName:@"star.fill" accessibilityDescription:nil];
    NSArray<PCExtensionInstallItem*>* items = @[
      [[PCExtensionInstallItem alloc] initWithName:@"uBlock Origin" icon:artwork
          permissions:@[ @"Read and change all your data on all websites" ] details:@[ @"" ]],
      [[PCExtensionInstallItem alloc] initWithName:@"Dark Reader" icon:nil permissions:@[] details:@[]],
      [[PCExtensionInstallItem alloc] initWithName:@"1Password" icon:artwork
          permissions:@[ @"Read and change all your data on all websites", @"Display notifications" ]
              details:@[ @"", @"" ]],
    ];
    auto imported = ^(NSArray<PCExtensionInstallItem*>* list) {
      auto* presenter = [[PCExtensionInstallPresenter alloc] initWithWindow:w
          title:@"Extensions" icon:nil heading:@"" permissions:@[] details:@[]
          acceptLabel:@"Add All" cancelLabel:@"Skip" checkboxLabel:nil
          validate:^BOOL { return YES; }
          inputAllowed:^BOOL(NSWindow*) { return YES; } result:result];
      [presenter configureImportedExtensions:list];
      [presenter start];
      Pump();
      return presenter;
    };
    p = imported(items);
    EXPECT(Text(p.sheet.contentView, @"Add 3 extensions to Parc?"));
    for (PCExtensionInstallItem* item in items) EXPECT(Text(p.sheet.contentView, item.name));
    EXPECT(Text(p.sheet.contentView, @"Display notifications") && !Text(p.sheet.contentView, @"It can:"));
    EXPECT(Button(p.sheet.contentView, @"Add All") && Button(p.sheet.contentView, @"Skip"));
    scroll = Scroll(p.sheet.contentView);
    EXPECT(scroll.frame.size.height > 113 && scroll.frame.size.height <= 260);
    [p.sheet cancelOperation:nil];
    Pump();
    EXPECT(results == 13 && choice == PCExtensionInstallCancel);
    //
    p = imported(@[ items[0] ]);
    EXPECT(Text(p.sheet.contentView, @"Add the “uBlock Origin” extension to Parc?"));
    EXPECT(Text(p.sheet.contentView, @"It can:") && Button(p.sheet.contentView, @"Skip"));
    add = Button(p.sheet.contentView, @"Add Extension");
    Pump(.5);
    EXPECT(add.enabled);
    [add performClick:nil];
    Pump();
    EXPECT(results == 14 && choice == PCExtensionInstallAccept && !p.sheet);
    [w close];
    printf("PASS %d native extension-install AppKit assertions\n", assertions);
  }
}
