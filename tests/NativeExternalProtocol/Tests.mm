#import <AppKit/AppKit.h>
#include "../Support/TestFailure.h"

#include <cstdio>
#include <cstdlib>

#import "external_protocol_presenter.h"
static int checks;
static void Check(bool value, const char* message) {
  ++checks;
  if (!value) {
    fprintf(stderr, "FAIL: %s\n", message);
    exit(1);
  }
}
static void Pump() {
  NSDate* end = [NSDate dateWithTimeIntervalSinceNow:.08];
  while (end.timeIntervalSinceNow > 0) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, .005, true);
  }
}
static NSWindow* Window(bool visible = true) {
  NSWindow* w = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(-2300, -2300, 640, 480)
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                  backing:NSBackingStoreBuffered
                    defer:NO];
  w.releasedWhenClosed = NO;
  if (visible) {
    [w orderFront:nil];
  }
  return w;
}
static NSView* Page(NSWindow* w) {
  NSView* p = [[NSView alloc] initWithFrame:w.contentView.bounds];
  [w.contentView addSubview:p];
  return p;
}
static NSView* Find(NSView* v, NSString* name) {
  if ([v.identifier isEqual:name] ||
      ([v isKindOfClass:NSButton.class] &&
       [static_cast<NSButton*>(v).title isEqual:name])) {
    return v;
  }
  for (NSView* child in v.subviews) {
    if (auto f = Find(child, name)) {
      return f;
    }
  }
  return nil;
}
static PCExternalProtocolPresenter* Make(NSView* p,
                                         NSWindow* w,
                                         NSString* remember,
                                         BOOL (^valid)(void),
                                         BOOL (^input)(NSEvent*),
                                         void (^result)(BOOL, BOOL)) {
  return [[PCExternalProtocolPresenter alloc]
       initWithPage:p
             window:w
              title:@"“example.test” wants to open “Example”."
            message:@""
               icon:[NSImage imageNamed:NSImageNameComputer]
        acceptLabel:@"Open “Example”"
        cancelLabel:@"Cancel"
      rememberLabel:remember
           validate:valid
       inputAllowed:input
       stateChanged:^{
       }
             result:result];
}
static void Decisions() {
  auto* w = Window();
  auto* p = Page(w);
  __block int results = 0;
  __block BOOL accepted = NO, remembered = NO, input = NO;
  auto* r = Make(
      p, w, @"Always open “Example”",
      ^{
        return YES;
      },
      ^(NSEvent*) {
        return input;
      },
      ^(BOOL a, BOOL m) {
        ++results;
        accepted = a;
        remembered = m;
        Check(!w.attachedSheet, "presentation ends before decision");
      });
  Check(r.sheet && !r.sheet.visible, "unpresented native sheet exists");
  [r show];
  [r show];
  Check(results == 0, "show is deferred");
  Pump();
  Check(r.sheet.visible && r.sheet.sheetParent == w,
        "actual originating window owns sheet");
  auto* open = static_cast<NSButton*>(
      Find(r.sheet.contentView, @"external-protocol-open"));
  auto* cancel = static_cast<NSButton*>(
      Find(r.sheet.contentView, @"external-protocol-cancel"));
  auto* box = static_cast<NSButton*>(
      Find(r.sheet.contentView, @"external-protocol-remember"));
  Check([open.keyEquivalent isEqual:@"\r"] &&
            r.sheet.accessibilityDefaultButton == open &&
            [cancel.keyEquivalent isEqual:@"\033"] &&
            !box.keyEquivalent.length,
        "Open is the default and Cancel answers Escape");
  const BOOL boxFirst = NSMidY(box.frame) == NSMidY(open.frame)
                           ? NSMinX(box.frame) < NSMinX(cancel.frame)
                           : NSMaxY(box.frame) <= NSMinY(open.frame);
  Check(open.superview == box.superview && box.superview == cancel.superview &&
            NSMidY(cancel.frame) == NSMidY(open.frame) &&
            NSMinX(cancel.frame) < NSMinX(open.frame) && boxFirst,
        "Cancel sits left of Open; Always open is left of Cancel or wraps above");
  Check(NSContainsRect(r.sheet.contentView.bounds, open.frame) &&
            NSContainsRect(r.sheet.contentView.bounds, cancel.frame) &&
            NSContainsRect(r.sheet.contentView.bounds, box.frame),
        "every button stays inside the sheet");
  Check([box.title isEqual:@"Always open “Example”"],
        "remember is the Always open button");
  [box performClick:nil];
  Check(results == 0 && r.sheet.visible,
        "input protection refusal keeps request pending");
  NSEvent* enter = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                    location:NSZeroPoint
                               modifierFlags:0
                                   timestamp:NSProcessInfo.processInfo.systemUptime
                                windowNumber:r.sheet.windowNumber
                                     context:nil
                                  characters:@"\003"
                 charactersIgnoringModifiers:@"\003"
                                   isARepeat:NO
                                     keyCode:76];
  Check([r.sheet performKeyEquivalent:enter] && results == 0 && r.sheet.visible,
        "keypad Enter is held by the same input protection");
  input = YES;
  [open performClick:nil];
  Pump();
  Check(results == 1 && accepted && !remembered,
        "Open accepts without remembering");
  r = Make(
      p, w, @"Always open “Example”",
      ^{
        return YES;
      },
      ^(NSEvent*) {
        return YES;
      },
      ^(BOOL a, BOOL m) {
        ++results;
        accepted = a;
        remembered = m;
      });
  [r show];
  Pump();
  [static_cast<NSButton*>(
      Find(r.sheet.contentView, @"external-protocol-remember")) performClick:nil];
  Pump();
  Check(results == 2 && accepted && remembered,
        "Always open accepts and remembers once");
  results = 1;
  [r invalidate];
  [open performClick:nil];
  [r show];
  Pump();
  Check(results == 1, "terminal cannot replay");
  r = Make(
      p, w, @"",
      ^{
        return YES;
      },
      ^(NSEvent*) {
        return YES;
      },
      ^(BOOL a, BOOL m) {
        ++results;
        Check(!a && !m, "cancel never remembers");
      });
  [r show];
  Pump();
  Check(!Find(r.sheet.contentView, @"external-protocol-remember"),
        "unsupported remember absent");
  [static_cast<NSButton*>(Find(r.sheet.contentView, @"external-protocol-cancel"))
      performClick:nil];
  Pump();
  Check(results == 2, "Cancel cancels once");
  [w close];
}
static void Invalidations() {
  for (int mode = 0; mode < 6; ++mode) {
    auto* w = Window(mode != 0);
    auto* p = Page(w);
    __block int count = 0;
    auto* r = Make(
        p, w, @"",
        ^{
          return mode != 1;
        },
        ^(NSEvent*) {
          return YES;
        },
        ^(BOOL a, BOOL m) {
          ++count;
          Check(!a && !m, "invalid request does not authorize");
        });
    [r show];
    if (mode == 2) {
      [p removeFromSuperview];
    }
    if (mode == 3) {
      [r invalidate];
    }
    if (mode == 4) {
      [w close];
    }
    if (mode == 5) {
      p.hidden = YES;
    }
    Pump();
    Check(count == 1 && !w.attachedSheet,
          "invalid owner interrupts actual sheet");
    [r invalidate];
    Pump();
    Check(count == 1, "interruption remains once only");
    [w close];
  }
}
static void Reentry() {
  auto* w = Window();
  auto* p = Page(w);
  __block PCExternalProtocolPresenter* r;
  __block int calls = 0;
  __block BOOL reenter = NO;
  r = Make(
      p, w, @"",
      ^{
        if (reenter) {
          [r invalidate];
        }
        return YES;
      },
      ^(NSEvent*) {
        return YES;
      },
      ^(BOOL a, BOOL) {
        ++calls;
        Check(!a, "validation reentry cancels");
      });
  reenter = YES;
  [r show];
  Pump();
  Check(calls == 1 && !w.attachedSheet, "no resurrection after validation");
  __block PCExternalProtocolPresenter* replacement;
  r = Make(
      p, w, @"",
      ^{
        return YES;
      },
      ^(NSEvent*) {
        [r invalidate];
        return YES;
      },
      ^(BOOL a, BOOL) {
        ++calls;
        Check(!a, "input reentry cannot authorize");
        replacement = Make(
            p, w, @"",
            ^{
              return YES;
            },
            ^(NSEvent*) {
              return YES;
            },
            ^(BOOL, BOOL) {
              ++calls;
            });
        [replacement show];
      });
  [r show];
  Pump();
  [static_cast<NSButton*>(Find(r.sheet.contentView, @"external-protocol-open"))
      performClick:nil];
  Pump();
  Check(calls == 2 && w.attachedSheet == replacement.sheet,
        "old input frame preserves replacement");
  [replacement invalidate];
  Pump();
  Check(calls == 3, "replacement owns own result");
  r = nil;
  replacement = nil;
  [w close];
}
int main() {
  ParcExitOnUncaughtExceptions();
  @autoreleasepool {
    [NSApplication sharedApplication];
    Decisions();
    Invalidations();
    Reentry();
    printf("PASS: %d native external-protocol presenter assertions\n", checks);
  }
  return 0;
}
