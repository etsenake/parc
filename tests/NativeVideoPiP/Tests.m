#import <Cocoa/Cocoa.h>
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
    printf("NativeVideoPiP: %d assertions passed in 3 groups\n", count);
  }
  return 0;
}
