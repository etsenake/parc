#import <Cocoa/Cocoa.h>
#include <objc/runtime.h>
#include <stdio.h>

#import "VideoPiPWindow.h"
static int count;
#define EXPECT(v)                                          \
  do {                                                     \
    ++count;                                               \
    if (!(v)) {                                            \
      fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #v); \
      exit(1);                                             \
    }                                                      \
  } while (0)
static NSButton* Button(NSView* view, NSInteger tag) {
  for (NSView* child in view.subviews) {
    if ([child isKindOfClass:NSButton.class] && child.tag == tag) {
      return (NSButton*)child;
    }
    NSButton* result = Button(child, tag);
    if (result) {
      return result;
    }
  }
  return nil;
}
static NSSlider* Slider(NSView* view) {
  for (NSView* child in view.subviews) {
    if ([child isKindOfClass:NSSlider.class]) {
      return (NSSlider*)child;
    }
    NSSlider* nested = Slider(child);
    if (nested) {
      return nested;
    }
  }
  return nil;
}
static BOOL Near(NSRect a, NSRect b) {
  return fabs(NSMinX(a) - NSMinX(b)) < 0.01 && fabs(NSMinY(a) - NSMinY(b)) < 0.01 &&
         fabs(NSWidth(a) - NSWidth(b)) < 0.01 &&
         fabs(NSHeight(a) - NSHeight(b)) < 0.01;
}
static BOOL Aspect(NSRect rect, CGFloat aspect) {
  return fabs(NSWidth(rect) / NSHeight(rect) - aspect) / aspect < 0.01;
}
static BOOL gLiveResize;
static BOOL LiveResize(id self, SEL _cmd) {
  return gLiveResize;
}
static NSView* Host(NSButton* button) {
  if (@available(macOS 26.0, *)) {
    for (NSView* host = button; host; host = host.superview) {
      if ([host isKindOfClass:NSGlassEffectView.class]) {
        return host;
      }
    }
  }
  return button;
}
static void PlaceUnderCursor(NSPanel* panel) {
  NSPoint mouse = [NSEvent mouseLocation];
  NSRect frame = panel.frame;
  frame.origin = NSMakePoint(mouse.x - frame.size.width * 0.5,
                             mouse.y - frame.size.height * 0.5);
  [panel setFrame:frame display:YES];
}
static void Hover(PCVideoPiPPresenter* presenter) {
  PlaceUnderCursor(presenter.panel);
  [presenter.panel.contentView mouseEntered:[NSEvent new]];
  // Screen monitors also drive hover; give them a tick after re-placing.
  [[NSRunLoop currentRunLoop]
      runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
  [presenter.panel.contentView mouseMoved:[NSEvent new]];
  [[NSRunLoop currentRunLoop]
      runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
}
int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    __block int actions = 0, changes = 0;
    __block PCVideoPiPAction last = PCVideoPiPClose;
    NSView* video = [NSView new];
    PCVideoPiPPresenter* presenter =
        [[PCVideoPiPPresenter alloc] initWithVideoView:video
            sourceFrame:NSMakeRect(20, 20, 640, 360)
            action:^(PCVideoPiPAction action, double value) {
              ++actions;
              last = action;
            }
            changed:^{
              ++changes;
            }];
    EXPECT(presenter.videoView == video);
    EXPECT(video.superview == presenter.panel.contentView);
    EXPECT(!presenter.panel.visible);
    EXPECT(!presenter.panel.keyWindow);
    EXPECT(!presenter.panel.canBecomeKeyWindow);
    EXPECT(presenter.panel.styleMask & NSWindowStyleMaskNonactivatingPanel);
    EXPECT(presenter.panel.styleMask & NSWindowStyleMaskResizable);
    EXPECT(presenter.panel.level == NSFloatingWindowLevel);
    EXPECT(!presenter.panel.hidesOnDeactivate);
    EXPECT(presenter.panel.collectionBehavior &
           NSWindowCollectionBehaviorCanJoinAllSpaces);
    EXPECT(presenter.panel.contentView.layer.cornerRadius == 16);
    //
    EXPECT(Button(presenter.panel.contentView, PCVideoPiPSkipAd) == nil);
    EXPECT(Button(presenter.panel.contentView, PCVideoPiPNextTrack) == nil);
    EXPECT(Button(presenter.panel.contentView, PCVideoPiPPreviousTrack) == nil);
    NSButton* closeButton =
        Button(presenter.panel.contentView, PCVideoPiPClose);
    EXPECT(closeButton != nil);
    EXPECT(!closeButton.bordered);
    if (@available(macOS 26.0, *)) {
      NSView* closeHost = closeButton;
      while (closeHost.superview &&
             ![closeHost isKindOfClass:NSGlassEffectView.class] &&
             closeHost != presenter.panel.contentView) {
        closeHost = closeHost.superview;
      }
      EXPECT([closeHost isKindOfClass:NSGlassEffectView.class]);
      EXPECT(fabs(closeHost.bounds.size.width - closeHost.bounds.size.height) <
             0.5);
      EXPECT(((NSGlassEffectView*)closeHost).cornerRadius >=
             closeHost.bounds.size.width * 0.45);
    } else {
      EXPECT(fabs(closeButton.bounds.size.width - closeButton.bounds.size.height) <
             0.5);
    }
    [presenter setControlsVisible:YES];
    NSSlider* slider = Slider(presenter.panel.contentView);
    EXPECT(slider != nil);
    EXPECT(slider.hidden);
    [presenter setPosition:5 duration:20];
    EXPECT(slider.hidden);
    [presenter showInactive];
    Hover(presenter);
    EXPECT(!slider.hidden);
    EXPECT(slider.doubleValue == 5);
    [presenter setPosition:5 duration:20 playbackRate:1];
    [[NSRunLoop currentRunLoop]
        runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.12]];
    EXPECT(slider.doubleValue > 5);
    [presenter setPosition:8 duration:20 playbackRate:0];
    EXPECT(slider.doubleValue == 8);
    [presenter setPosition:0 duration:0];
    EXPECT(slider.hidden);
    [presenter.panel.contentView mouseExited:[NSEvent new]];
    NSPoint away = NSMakePoint(-2000, -2000);
    [presenter.panel setFrameOrigin:away];
    [[NSRunLoop currentRunLoop]
        runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    [presenter setNaturalSize:NSMakeSize(1920, 1080)];
    NSRect frame = presenter.panel.frame;
    NSRect work = NSScreen.mainScreen.visibleFrame;
    EXPECT(NSWidth(frame) >= 480);
    EXPECT(fabs(NSWidth(frame) / NSHeight(frame) - 16.0 / 9.0) < 0.05);
    EXPECT(NSMaxX(frame) <= NSMaxX(work) + 1);
    EXPECT(NSMinY(frame) >= NSMinY(work) - 1);
    EXPECT(presenter.panel.visible);
    EXPECT(!presenter.panel.keyWindow);
    [presenter.panel makeKeyAndOrderFront:nil];
    EXPECT(!presenter.panel.canBecomeKeyWindow);
    EXPECT(!presenter.panel.keyWindow);
    EXPECT(presenter.panel.styleMask & NSWindowStyleMaskNonactivatingPanel);
    [presenter.panel setContentSize:NSMakeSize(640, 360)];
    EXPECT(NSWidth(video.bounds) == 640);
    EXPECT(changes > 0);
    // Captions sit over the video, under the chrome, at their page bounds
    // (top-left origin), follow resizes and never take the pointer.
    NSView* content = presenter.panel.contentView;
    NSView* captions = nil;
    for (NSView* child in content.subviews) {
      if ([NSStringFromClass(child.class) isEqual:@"PCVideoPiPCaptions"]) {
        captions = child;
      }
    }
    EXPECT(captions != nil);
    EXPECT(captions.hidden);
    NSImage* cue = [NSImage imageWithSize:NSMakeSize(512, 36)
                                  flipped:NO
                           drawingHandler:^BOOL(NSRect rect) {
                             return YES;
                           }];
    [presenter setControlsVisible:NO];
    [presenter setCaptions:cue bounds:NSMakeRect(0.1, 0.8, 0.8, 0.1)];
    EXPECT(!captions.hidden);
    EXPECT(Near(captions.frame, NSMakeRect(64, 36, 512, 36)));
    NSUInteger captionsIndex = [content.subviews indexOfObject:captions];
    EXPECT(captionsIndex > [content.subviews indexOfObject:video]);
    EXPECT(captionsIndex == content.subviews.count - 2);
    NSView* hit = [content hitTest:NSMakePoint(100, 40)];
    EXPECT(hit != nil && hit != captions);
    [captions displayIfNeeded];
    EXPECT(captions.layer.contents == cue);
    [presenter.panel setContentSize:NSMakeSize(320, 180)];
    EXPECT(Near(captions.frame, NSMakeRect(32, 18, 256, 18)));
    // Chrome without a scrubber (no duration) leaves cues in place; a shown
    // scrubber lifts them clear, and they drop back when it hides.
    [presenter setControlsVisible:YES];
    Hover(presenter);
    EXPECT(slider.hidden);
    EXPECT(Near(captions.frame, NSMakeRect(32, 18, 256, 18)));
    [presenter setPosition:5 duration:20];
    EXPECT(!slider.hidden);
    EXPECT(NSMinY(captions.frame) >= NSMaxY(slider.frame));
    EXPECT(NSWidth(captions.frame) == 256);
    [presenter setControlsVisible:NO];
    EXPECT(Near(captions.frame, NSMakeRect(32, 18, 256, 18)));
    [presenter setControlsVisible:YES];
    [presenter setPosition:0 duration:0];
    // Page bounds outside the window are clipped to it; huge ones too.
    [presenter setCaptions:cue bounds:NSMakeRect(0.5, 0.9, 0.8, 0.2)];
    EXPECT(Near(captions.frame, NSMakeRect(160, 0, 160, 18)));
    [presenter setCaptions:cue bounds:NSMakeRect(1e308, -1e308, 1e308, 1e308)];
    EXPECT(captions.hidden);
    [presenter setCaptions:cue bounds:NSMakeRect(NAN, 0.8, 0.8, 0.1)];
    EXPECT(captions.hidden);
    [presenter setCaptions:cue bounds:NSMakeRect(0.1, 0.8, 0.8, 0.1)];
    [presenter setCaptions:nil bounds:NSZeroRect];
    EXPECT(captions.hidden);
    [presenter.panel setContentSize:NSMakeSize(640, 360)];
    Hover(presenter);
    [presenter setAction:PCVideoPiPPlayPause visible:YES];
    [Button(presenter.panel.contentView, PCVideoPiPPlayPause) performClick:nil];
    EXPECT(actions == 1);
    EXPECT(last == PCVideoPiPPlayPause);
    EXPECT(!presenter.panel.keyWindow);
    [presenter setControlsVisible:NO];
    [Button(presenter.panel.contentView, PCVideoPiPPlayPause) performClick:nil];
    EXPECT(actions == 1);
    [presenter setControlsVisible:YES];
    Hover(presenter);
    [presenter setAction:PCVideoPiPPlayPause visible:NO];
    [Button(presenter.panel.contentView, PCVideoPiPPlayPause) performClick:nil];
    EXPECT(actions == 1);
    // The play button sits under the pointer at the panel's centre: it is
    // hovered and shows the hand without the panel ever becoming key, the
    // arrow comes back when the chrome hides, and the hand again as soon as
    // the chrome shows under a still pointer.
    NSButton* play = Button(presenter.panel.contentView, PCVideoPiPPlayPause);
    EXPECT(play.alphaValue < 1);
    [presenter setAction:PCVideoPiPPlayPause visible:YES];
    EXPECT(play.alphaValue == 1);
    EXPECT(Host(play).layer.transform.m11 > 1.09);
    EXPECT([NSCursor currentCursor] == NSCursor.pointingHandCursor);
    EXPECT(!presenter.panel.keyWindow);
    [presenter setControlsVisible:NO];
    EXPECT([NSCursor currentCursor] == NSCursor.arrowCursor);
    EXPECT(play.alphaValue < 1);
    EXPECT(Host(play).layer.transform.m11 == 1);
    [presenter setControlsVisible:YES];
    EXPECT([NSCursor currentCursor] == NSCursor.pointingHandCursor);
    EXPECT(play.alphaValue == 1);
    // Off every button: the arrow, and no button hovered.
    NSRect off = presenter.panel.frame;
    off.origin.x += 60;
    [presenter.panel setFrame:off display:YES];
    [presenter.panel.contentView mouseMoved:[NSEvent new]];
    EXPECT([NSCursor currentCursor] == NSCursor.arrowCursor);
    EXPECT(play.alphaValue < 1);
    Hover(presenter);
    EXPECT([NSCursor currentCursor] == NSCursor.pointingHandCursor);
    // Every top chip is a full disc of the same size, minus included.
    for (NSNumber* tag in @[ @(PCVideoPiPReturn), @(PCVideoPiPMinimize),
                             @(PCVideoPiPClose) ]) {
      NSButton* chip = Button(presenter.panel.contentView, tag.integerValue);
      EXPECT(Near(chip.frame, NSMakeRect(0, 0, 28, 28)));
      if (@available(macOS 26.0, *)) {
        EXPECT(((NSGlassEffectView*)Host(chip)).cornerRadius == 14);
      }
    }
    [presenter setAction:PCVideoPiPMute title:@"Unmute"];
    EXPECT(
        [Button(presenter.panel.contentView, PCVideoPiPMute).accessibilityLabel
            isEqual:@"Unmute"]);
    [presenter hide];
    EXPECT(!presenter.panel.visible);
    EXPECT(actions == 1);
    [presenter showInactive];
    EXPECT(presenter.panel.visible);
    EXPECT(!presenter.panel.canBecomeKeyWindow);
    EXPECT(!presenter.panel.keyWindow);
    [presenter invalidate];
    EXPECT(presenter.invalidated);
    EXPECT(!presenter.panel.visible);
    EXPECT(video.superview == nil);
    [presenter showInactive];
    EXPECT(!presenter.panel.visible);
    [presenter invalidate];
    EXPECT(actions == 1);
    __block PCVideoPiPPresenter* closing;
    closing = [[PCVideoPiPPresenter alloc]
        initWithVideoView:[NSView new]
              sourceFrame:NSZeroRect
                   action:^(PCVideoPiPAction action, double value) {
                     ++actions;
                     last = action;
                     [closing invalidate];
                     closing = nil;
                   }
                  changed:^{
                  }];
    NSPanel* panel = closing.panel;
    [closing showInactive];
    [panel close];
    EXPECT(closing == nil);
    EXPECT(last == PCVideoPiPSystemClose);
    EXPECT(actions == 2);
    EXPECT(!panel.visible);
    __block PCVideoPiPPresenter* reentrant;
    reentrant = [[PCVideoPiPPresenter alloc] initWithVideoView:[NSView new]
        sourceFrame:NSZeroRect
        action:^(PCVideoPiPAction action, double value) {
        }
        changed:^{
          [reentrant invalidate];
          reentrant = nil;
        }];
    [reentrant showInactive];
    EXPECT(reentrant == nil);
    // The window follows every natural size, and the video keeps its own
    // aspect inside whatever window it is in, letterboxed or pillarboxed.
    __block int resized = 0;
    NSView* fitted = [NSView new];
    PCVideoPiPPresenter* fitting =
        [[PCVideoPiPPresenter alloc] initWithVideoView:fitted
                                           sourceFrame:NSZeroRect
                                                action:^(PCVideoPiPAction a,
                                                         double v) {
                                                }
                                               changed:^{
                                                 ++resized;
                                               }];
    NSPanel* fitPanel = fitting.panel;
    [fitting setNaturalSize:NSMakeSize(1920, 1080)];
    EXPECT(Aspect(fitPanel.frame, 16.0 / 9.0));
    EXPECT(Near(fitted.frame, fitPanel.contentView.bounds));
    const NSRect corner = fitPanel.frame;
    // A 2.39:1 film after a 16:9 intro: same width, same bottom-right corner.
    [fitting setNaturalSize:NSMakeSize(1920, 804)];
    EXPECT(Aspect(fitPanel.frame, 1920.0 / 804.0));
    EXPECT(NSWidth(fitPanel.frame) == NSWidth(corner));
    EXPECT(fabs(NSMaxX(fitPanel.frame) - NSMaxX(corner)) < 1);
    EXPECT(fabs(NSMinY(fitPanel.frame) - NSMinY(corner)) < 1);
    EXPECT(Near(fitted.frame, fitPanel.contentView.bounds));
    [fitting setNaturalSize:NSMakeSize(1440, 1080)];
    EXPECT(Aspect(fitPanel.frame, 4.0 / 3.0));
    EXPECT(Near(fitted.frame, fitPanel.contentView.bounds));
    // A window of another shape letterboxes or pillarboxes the video.
    [fitPanel setContentSize:NSMakeSize(640, 360)];
    EXPECT(Near(fitted.frame, NSMakeRect(80, 0, 480, 360)));
    EXPECT(fitted.layer.cornerRadius == 0);
    [fitting setCaptions:cue bounds:NSMakeRect(0.1, 0.8, 0.8, 0.1)];
    NSView* fitCaptions = nil;
    for (NSView* child in fitPanel.contentView.subviews) {
      if ([NSStringFromClass(child.class) isEqual:@"PCVideoPiPCaptions"]) {
        fitCaptions = child;
      }
    }
    EXPECT(Near(fitCaptions.frame, NSMakeRect(128, 36, 384, 36)));
    [fitting setCaptions:nil bounds:NSZeroRect];
    // A reused window (the next session) takes the next video's aspect.
    [fitting hide];
    [fitPanel setContentSize:NSMakeSize(640, 360)];
    resized = 0;
    [fitting setNaturalSize:NSMakeSize(1920, 800)];
    [fitting showInactive];
    EXPECT(Aspect(fitPanel.frame, 2.4));
    EXPECT(NSWidth(fitPanel.frame) == 640);
    EXPECT(Near(fitted.frame, fitPanel.contentView.bounds));
    EXPECT(resized > 0);
    EXPECT(fitted.layer.cornerRadius == 16);
    // Under a point of difference fills the window, with no hairline.
    [fitPanel setContentSize:NSMakeSize(640, 266.4)];
    EXPECT(Near(fitted.frame, fitPanel.contentView.bounds));
    // A size change during the user's live resize waits for its end.
    class_addMethod(object_getClass(fitPanel), @selector(inLiveResize),
                    (IMP)LiveResize, "c@:");
    const NSRect dragged = fitPanel.frame;
    gLiveResize = YES;
    [fitting setNaturalSize:NSMakeSize(1920, 1080)];
    EXPECT(Near(fitPanel.frame, dragged));
    EXPECT(Aspect(fitted.frame, 2.4));
    // AppKit may still report the live resize while it posts its end.
    [[NSNotificationCenter defaultCenter]
        postNotificationName:NSWindowDidEndLiveResizeNotification
                      object:fitPanel];
    gLiveResize = NO;
    EXPECT(Aspect(fitPanel.frame, 16.0 / 9.0));
    EXPECT(NSWidth(fitPanel.frame) == NSWidth(dragged));
    EXPECT(Near(fitted.frame, fitPanel.contentView.bounds));
    [fitting setNaturalSize:NSMakeSize(1920, 800)];
    // Invalid natural sizes are ignored.
    [fitting setNaturalSize:NSMakeSize(0, 0)];
    [fitting setNaturalSize:NSMakeSize(NAN, 1)];
    EXPECT(Aspect(fitted.frame, 2.4));
    [fitting invalidate];
    // A refit whose resize releases the owner leaves nothing touched after.
    __block PCVideoPiPPresenter* releasing;
    releasing = [[PCVideoPiPPresenter alloc] initWithVideoView:[NSView new]
        sourceFrame:NSZeroRect
        action:^(PCVideoPiPAction action, double value) {
        }
        changed:^{
          if (releasing.panel.frame.size.width / releasing.panel.frame.size.height > 2) {
            [releasing invalidate];
            releasing = nil;
          }
        }];
    [releasing setNaturalSize:NSMakeSize(1920, 1080)];
    [releasing setNaturalSize:NSMakeSize(1920, 804)];
    EXPECT(releasing == nil);
    printf("NativeVideoPiP: %d assertions passed in 4 groups\n", count);
  }
  return 0;
}
