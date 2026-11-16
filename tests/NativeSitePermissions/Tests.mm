#import <AppKit/AppKit.h>
#include "../Support/TestFailure.h"

#include <cstdio>
#include <cstdlib>

#import "site_permission_presenter.h"
static int checks = 0;
static void Check(BOOL ok, const char* message) {
  ++checks;
  if (!ok) {
    fprintf(stderr, "FAIL: %s\n", message);
    std::exit(1);
  }
}
static void Drain() {
  NSDate* until = [NSDate dateWithTimeIntervalSinceNow:0.08];
  while (until.timeIntervalSinceNow > 0) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.005, true);
  }
}
static NSWindow* Window(BOOL visible = YES) {
  NSWindow* w = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(-2200, -2200, 640, 480)
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
  NSView* v = [[NSView alloc] initWithFrame:w.contentView.bounds];
  [w.contentView addSubview:v];
  return v;
}
static NSButton* Button(NSView* v, NSString* label) {
  if ([v isKindOfClass:NSButton.class] &&
      [((NSButton*)v).title isEqual:label]) {
    return (NSButton*)v;
  }
  for (NSView* child in v.subviews) {
    if (auto b = Button(child, label)) {
      return b;
    }
  }
  return nil;
}
static BOOL Contains(NSView* v, NSString* text) {
  if ([v isKindOfClass:NSTextField.class] &&
      [((NSTextField*)v).stringValue containsString:text]) {
    return YES;
  }
  for (NSView* child in v.subviews) {
    if (Contains(child, text)) {
      return YES;
    }
  }
  return NO;
}
static PCSitePermissionPresenter* Request(
    NSView* page,
    NSWindow* w,
    BOOL (^valid)(void),
    void (^result)(PCSitePermissionChoice)) {
  auto* r = [[PCSitePermissionPresenter alloc] initWithPage:page
      window:w
      title:@"Allow frame.example:8443 to access your camera, microphone?"
      locationMode:PCSiteLocationNone
      initialPrecise:NO
      validate:valid
      presented:^{
      }
      result:^(PCSitePermissionChoice choice, BOOL) {
        result(choice);
      }];
  [r configureSymbol:@"camera.fill" pointSize:14 bold:NO offsetY:-1];
  return r;
}
static void Click(PCSitePermissionPresenter* r, NSString* label) {
  auto button = Button(r.sheet.contentView, label);
  Check(button && button.enabled, "actual native decision button exists");
  [button performClick:nil];
}
static void Decisions() {
  NSWindow* w = Window();
  NSView* page = Page(w);
  __block int count = 0;
  __block PCSitePermissionChoice choice = PCSitePermissionInterrupted;
  for (NSString* title in @[ @"Allow", @"Not Now" ]) {
    int before = count;
    auto r = Request(
        page, w,
        ^{
          return YES;
        },
        ^(PCSitePermissionChoice c) {
          ++count;
          choice = c;
          Check(!w.attachedSheet, "no sheet is ever attached");
        });
    [r start];
    [r start];
    Check(!r.sheet && count == before, "presentation and result are deferred");
    Drain();
    Check(r.sheet.visible && !w.attachedSheet && r.sheet != w,
          "a visible popover window, not a sheet");
    Check(Contains(r.sheet.contentView,
                   @"Allow frame.example:8443 to access your camera, microphone?"),
          "the title names the site and the permissions");
    Check(Button(r.sheet.contentView, @"Not Now") &&
              Button(r.sheet.contentView, @"Allow") &&
              !Button(r.sheet.contentView, @"Block") &&
              !Button(r.sheet.contentView, @"Allow This Time"),
          "two actions only");
    Check(Button(r.sheet.contentView, @"Allow").keyEquivalent.length == 0,
          "Return does not silently grant");
    Click(r, title);
    Check(count == before, "decision deferred off button callback");
    Drain();
    Check(count == before + 1, "exactly one result");
    Check(choice == ([title isEqual:@"Allow"] ? PCSitePermissionAllow
                                              : PCSitePermissionDismiss),
          "Allow grants and Not Now dismisses");
    [r invalidate];
    [r start];
    Drain();
    Check(count == before + 1, "cannot replay terminal request");
  }
  auto r = Request(
      page, w,
      ^{
        return YES;
      },
      ^(PCSitePermissionChoice c) {
        ++count;
        choice = c;
      });
  [r start];
  Drain();
  [r.sheet cancelOperation:nil];
  Drain();
  Check(choice == PCSitePermissionDismiss,
        "Escape closes the popover as a dismissal");
  [w close];
}
static void Interruptions() {
  for (int mode = 0; mode < 6; ++mode) {
    NSWindow* w = Window(mode != 0);
    NSView* page = Page(w);
    __block BOOL valid = YES;
    __block int count = 0;
    __block PCSitePermissionChoice result = PCSitePermissionAllow;
    auto r = Request(
        page, w,
        ^{
          return valid;
        },
        ^(PCSitePermissionChoice c) {
          ++count;
          result = c;
        });
    if (mode == 1) {
      valid = NO;
    }
    [r start];
    Drain();
    if (mode == 2) {
      Click(r, @"Allow");
      valid = NO;
    }
    if (mode == 3) {
      Click(r, @"Allow");
      [page removeFromSuperview];
    }
    if (mode == 4) {
      Click(r, @"Allow");
      [r invalidate];
    }
    if (mode == 5) {
      [w close];
    }
    Drain();
    Check(count == 1 && result == PCSitePermissionInterrupted,
          "hidden/stale/detached/invalidated/closed request cannot grant");
    [r invalidate];
    [w close];
  }
}
static void ConcurrentAndReentrant() {
  NSWindow* w = Window();
  NSView* page = Page(w);
  __block int first = 0, second = 0;
  __block PCSitePermissionChoice secondResult = PCSitePermissionAllow;
  auto a = Request(
      page, w,
      ^{
        return YES;
      },
      ^(PCSitePermissionChoice) {
        ++first;
      });
  auto b = Request(
      page, w,
      ^{
        return YES;
      },
      ^(PCSitePermissionChoice c) {
        ++second;
        secondResult = c;
      });
  [a start];
  Drain();
  [b start];
  Drain();
  Check(
      first == 0 && second == 1 && secondResult == PCSitePermissionInterrupted,
      "a second prompt in the window refuses instead of stacking");
  Check(a.sheet.visible,
        "unavailable prompt does not dismiss the existing popover");
  [a invalidate];
  Drain();
  Check(first == 1, "old prompt retires once");
  __block PCSitePermissionPresenter* replacement = nil;
  a = Request(
      page, w,
      ^{
        return YES;
      },
      ^(PCSitePermissionChoice c) {
        Check(c == PCSitePermissionAllow, "first genuine decision arrives");
        replacement = Request(
            page, w,
            ^{
              return YES;
            },
            ^(PCSitePermissionChoice) {
              ++second;
            });
        [replacement start];
      });
  [a start];
  Drain();
  Click(a, @"Allow");
  Drain();
  Check(replacement.sheet.visible,
        "callback can replace old prompt after it closes");
  [a invalidate];
  Check(replacement.sheet.visible,
        "stale invalidation cannot close replacement");
  [replacement invalidate];
  Drain();
  [w close];
}
static void WindowIdentityAndOwnerRelease() {
  NSWindow* a = Window();
  NSWindow* b = Window();
  NSView* page = Page(a);
  __block int count = 0;
  auto r = Request(
      page, a,
      ^{
        return YES;
      },
      ^(PCSitePermissionChoice c) {
        Check(c == PCSitePermissionInterrupted,
              "cross-window move cancels old decision");
        ++count;
      });
  [r start];
  Drain();
  Click(r, @"Allow");
  [page removeFromSuperview];
  [b.contentView addSubview:page];
  Drain();
  Check(count == 1 && !a.attachedSheet && !b.attachedSheet,
        "no current-window fallback");
  __weak PCSitePermissionPresenter* weak = nil;
  @autoreleasepool {
    __block PCSitePermissionPresenter* owned = Request(
        page, b,
        ^{
          return YES;
        },
        ^(PCSitePermissionChoice) {
          ++count;
          owned = nil;
        });
    weak = owned;
    [owned start];
    Drain();
    Click(owned, @"Not Now");
    Drain();
    Check(owned == nil && count == 2,
          "completion can release last owner safely");
  }
  Drain();
  Check(weak == nil,
        "terminal native request is released after AppKit autoreleases");
  [a close];
  [b close];
}
static void TypedChoices() {
  NSWindow* w = Window();
  NSView* page = Page(w);
  for (int mode = 0; mode < 4; ++mode) {
    __block int presented = 0, results = 0;
    __block BOOL precise = NO;
    __block PCSitePermissionChoice choice = PCSitePermissionInterrupted;
    auto r = [[PCSitePermissionPresenter alloc] initWithPage:page
        window:w
        title:@"Allow location.example to access your location?"
        locationMode:static_cast<PCSiteLocationMode>(mode)
        initialPrecise:YES
        validate:^{
          return YES;
        }
        presented:^{
          ++presented;
        }
        result:^(PCSitePermissionChoice c, BOOL accuracy) {
          choice = c;
          precise = accuracy;
          ++results;
        }];
    [r configureSymbol:@"location.fill" pointSize:14 bold:NO offsetY:0];
    [r start];
    Check(presented == 0, "no presentation acknowledgment before display");
    Drain();
    Check(presented == 1 && r.sheet.visible,
          "presentation acknowledgment follows the visible popover");
    Click(r, @"Allow");
    Drain();
    Check(results == 1 && choice == PCSitePermissionAllow, "Allow grants");
    Check(precise == (mode == PCSiteLocationApproximateOrPrecise ||
                      mode == PCSiteLocationUpgradeToPrecise),
          "accuracy is the engine's own selection for each mode");
    [r invalidate];
    Drain();
    Check(results == 1 && presented == 1, "typed request remains exactly once");
  }
  __block int shown = 0, completed = 0;
  auto unavailable = [[PCSitePermissionPresenter alloc] initWithPage:page
      window:w
      title:@"Allow location.example to access your location?"
      locationMode:PCSiteLocationApproximateOrPrecise
      initialPrecise:NO
      validate:^{
        return NO;
      }
      presented:^{
        ++shown;
      }
      result:^(PCSitePermissionChoice c, BOOL) {
        Check(c == PCSitePermissionInterrupted,
              "typed unavailable request is neutral");
        ++completed;
      }];
  [unavailable start];
  Drain();
  Check(shown == 0 && completed == 1,
        "failed native presentation is never acknowledged");
  __block PCSitePermissionChoice staged = PCSitePermissionInterrupted;
  __block int system = 0;
  auto followUp = Request(page, w,
                          ^{
                            return YES;
                          },
                          ^(PCSitePermissionChoice c) {
                            staged = c;
                          });
  [followUp configureFollowUpWithTitle:@"You previously allowed camera"
                                labels:@[ @"Continue allowing", @"Stop allowing" ]
                               choices:@[ @(PCSitePermissionDismiss),
                                          @(PCSitePermissionBlock) ]
                          systemAction:^(PCSitePermissionChoice) {
                            ++system;
                          }];
  [followUp start];
  Drain();
  Check(Contains(followUp.sheet.contentView, @"You previously allowed camera") &&
            Button(followUp.sheet.contentView, @"Continue allowing") &&
            !Button(followUp.sheet.contentView, @"Allow"),
        "a permission-element stage shows Chromium's title and labels");
  Click(followUp, @"Stop allowing");
  Drain();
  Check(staged == PCSitePermissionBlock && system == 0,
        "the stage's own choice is delivered");
  [followUp invalidate];
  Drain();
  [w close];
}
static void SheetInterrupts() {
  NSWindow* w = Window();
  NSView* page = Page(w);
  __block PCSitePermissionChoice choice = PCSitePermissionAllow;
  __block int count = 0;
  auto r = Request(page, w,
                   ^{
                     return YES;
                   },
                   ^(PCSitePermissionChoice c) {
                     choice = c;
                     ++count;
                   });
  [r start];
  Drain();
  NSWindow* sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100)
                                                styleMask:NSWindowStyleMaskTitled
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
  sheet.releasedWhenClosed = NO;
  [w beginSheet:sheet completionHandler:nil];
  Drain();
  Check(count == 1 && choice == PCSitePermissionInterrupted && !r.shown,
        "another sheet on the window ends the prompt neutrally");
  [w endSheet:sheet];
  [r invalidate];
  Drain();
  [w close];
}
static void Anchor() {
  NSWindow* w = Window();
  NSView* page = Page(w);
  NSWindowController* plain = [[NSWindowController alloc] initWithWindow:w];
  (void)plain;
  auto r = Request(page, w,
                   ^{
                     return YES;
                   },
                   ^(PCSitePermissionChoice) {
                   });
  [r start];
  Drain();
  NSRect frame = r.sheet.frame;
  NSRect corner = [page convertRect:NSMakeRect(0, NSMaxY(page.bounds) - 1, 1, 1)
                             toView:nil];
  corner = [w convertRectToScreen:corner];
  Check(r.sheet.visible && NSMaxY(frame) <= NSMinY(corner) + 20,
        "without an anchor the popover hangs below the page's top corner");
  [r invalidate];
  Drain();
  [w close];
}
static double DrawnAlpha(NSButton* button) {
  NSShadow* shadow = button.shadow;
  button.shadow = nil;
  NSBitmapImageRep* rep =
      [button bitmapImageRepForCachingDisplayInRect:button.bounds];
  [button cacheDisplayInRect:button.bounds toBitmapImageRep:rep];
  button.shadow = shadow;
  double sum = 0;
  for (NSInteger y = 0; y < rep.pixelsHigh; ++y) {
    for (NSInteger x = 0; x < rep.pixelsWide; ++x) {
      sum += [rep colorAtX:x y:y].alphaComponent;
    }
  }
  return sum;
}
static void PressFeedback() {
  NSWindow* w = Window();
  NSView* page = Page(w);
  auto r = Request(
      page, w,
      ^{
        return YES;
      },
      ^(PCSitePermissionChoice) {
      });
  [r start];
  Drain();
  for (NSAppearanceName name in @[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]) {
    r.sheet.appearance = [NSAppearance appearanceNamed:name];
    for (NSString* title in @[ @"Allow", @"Not Now" ]) {
      NSButton* button = Button(r.sheet.contentView, title);
      [button viewDidChangeEffectiveAppearance];
      const double rest = DrawnAlpha(button);
      [button.cell highlight:YES withFrame:button.bounds inView:button];
      const double pressed = DrawnAlpha(button);
      [button.cell highlight:NO withFrame:button.bounds inView:button];
      Check(rest > 0 && fabs(pressed / rest - 0.75) < 0.01,
            "a pressed action draws at 75% of its resting content");
      Check(fabs(DrawnAlpha(button) - rest) < 0.5,
            "releasing restores the resting content");
    }
  }
  [r invalidate];
  Drain();
  [w close];
}
int main() {
  ParcExitOnUncaughtExceptions();
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    Decisions();
    Interruptions();
    ConcurrentAndReentrant();
    WindowIdentityAndOwnerRelease();
    TypedChoices();
    Anchor();
    SheetInterrupts();
    PressFeedback();
    printf("PASS: %d native site-permission assertions / 8 groups\n", checks);
  }
}
