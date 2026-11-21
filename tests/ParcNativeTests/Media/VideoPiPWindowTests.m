#import <Cocoa/Cocoa.h>
#import "ParcNativeTest.h"
#import "ParcNativeClock.h"
#import "ParcNativePointer.h"
#include <objc/runtime.h>
#include <stdio.h>

#import "VideoPiPWindow.h"
#define EXPECT(condition) PARC_CHECK(condition)
static PCVideoPiPPresenter* Offscreen(PCVideoPiPPresenter* presenter) NS_RETURNS_RETAINED {
  presenter.presentation = ParcNativePresentation();
  presenter.scheduler = ParcNativeScheduler();
  return presenter;
}
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
  NSPoint mouse = ParcNativePointerLocation();
  NSRect frame = panel.frame;
  frame.origin = NSMakePoint(mouse.x - frame.size.width * 0.5,
                             mouse.y - frame.size.height * 0.5);
  [panel setFrame:frame display:YES];
}
static void Hover(PCVideoPiPPresenter* presenter) {
  PlaceUnderCursor(presenter.panel);
  [presenter.panel.contentView mouseEntered:[NSEvent new]];
  ParcNativeAdvance(0.05);
  [presenter.panel.contentView mouseMoved:[NSEvent new]];
  ParcNativeAdvance(0.02);
}
static NSView* Captions(NSView* content) {
  NSView* captions = nil;
  for (NSView* child in content.subviews) {
    if ([NSStringFromClass(child.class) isEqual:@"PCVideoPiPCaptions"]) captions = child;
  }
  return captions;
}
static NSImage* Cue(void) {
  return [NSImage imageWithSize:NSMakeSize(512, 36)
                        flipped:NO
                 drawingHandler:^BOOL(NSRect rect) {
                   return YES;
                 }];
}

@interface ParcNativeTests_VideoPiPWindowTests : ParcNativeTestCase
@end

@implementation ParcNativeTests_VideoPiPWindowTests {
  NSView* _video;
  PCVideoPiPPresenter* _presenter;
  int _actions;
  int _changes;
  PCVideoPiPAction _last;
}

- (void)setUp {
  [super setUp];
  ParcNativeResetPointer();
  _video = [NSView new];
  _last = PCVideoPiPClose;
  __weak ParcNativeTests_VideoPiPWindowTests* weak = self;
  _presenter = Offscreen([[PCVideoPiPPresenter alloc] initWithVideoView:_video
      sourceFrame:NSMakeRect(20, 20, 640, 360)
      action:^(PCVideoPiPAction action, double value) {
        ParcNativeTests_VideoPiPWindowTests* test = weak;
        if (!test) return;
        ++test->_actions;
        test->_last = action;
      }
      changed:^{
        ParcNativeTests_VideoPiPWindowTests* test = weak;
        if (test) ++test->_changes;
      }]);
}

- (void)tearDown {
  [_presenter invalidate];
  PCPictureInPicturePointAtControl(NO);
  [super tearDown];
}

- (NSView*)content {
  return _presenter.panel.contentView;
}

- (void)showHovering {
  [_presenter setControlsVisible:YES];
  [_presenter showInactive];
  [_presenter.panel setContentSize:NSMakeSize(640, 360)];
  ParcNativeSettle();
  Hover(_presenter);
}

- (NSButton*)hoveredPlayButton {
  [_presenter setAction:PCVideoPiPPlayPause visible:YES];
  NSButton* play = Button(self.content, PCVideoPiPPlayPause);
  NSView* host = Host(play);
  host.wantsLayer = YES;
  if (!host.layer) host.layer = [CALayer layer];
  [self showHovering];
  return play;
}

- (NSView*)captionsShownAt640 {
  [_presenter showInactive];
  [_presenter.panel setContentSize:NSMakeSize(640, 360)];
  [_presenter setControlsVisible:NO];
  [_presenter setCaptions:Cue() bounds:NSMakeRect(0.1, 0.8, 0.8, 0.1)];
  return Captions(self.content);
}

- (void)testThePanelFloatsOverSpacesWithoutTakingKeyFocus {
  EXPECT(_presenter.videoView == _video);
  EXPECT(_video.superview == self.content);
  EXPECT(!ParcNativeVisible(_presenter.panel));
  EXPECT(!_presenter.panel.keyWindow);
  EXPECT(!_presenter.panel.canBecomeKeyWindow);
  EXPECT(_presenter.panel.styleMask & NSWindowStyleMaskNonactivatingPanel);
  EXPECT(_presenter.panel.styleMask & NSWindowStyleMaskResizable);
  EXPECT(_presenter.panel.level == NSFloatingWindowLevel);
  EXPECT(!_presenter.panel.hidesOnDeactivate);
  EXPECT(_presenter.panel.collectionBehavior & NSWindowCollectionBehaviorCanJoinAllSpaces);
  EXPECT(self.content.layer.cornerRadius == 16);
}

- (void)testOnlyARoundCloseChipShowsByDefault {
  EXPECT(Button(self.content, PCVideoPiPSkipAd) == nil);
  EXPECT(Button(self.content, PCVideoPiPNextTrack) == nil);
  EXPECT(Button(self.content, PCVideoPiPPreviousTrack) == nil);
  NSButton* closeButton = Button(self.content, PCVideoPiPClose);
  EXPECT(closeButton != nil);
  EXPECT(!closeButton.bordered);
  if (@available(macOS 26.0, *)) {
    NSView* closeHost = closeButton;
    while (closeHost.superview && ![closeHost isKindOfClass:NSGlassEffectView.class] && closeHost != self.content) {
      closeHost = closeHost.superview;
    }
    EXPECT([closeHost isKindOfClass:NSGlassEffectView.class]);
    EXPECT(fabs(closeHost.bounds.size.width - closeHost.bounds.size.height) < 0.5);
    EXPECT(((NSGlassEffectView*)closeHost).cornerRadius >= closeHost.bounds.size.width * 0.45);
  } else {
    EXPECT(fabs(closeButton.bounds.size.width - closeButton.bounds.size.height) < 0.5);
  }
}

- (void)testTheProgressSliderShowsAKnownDurationWhileHovered {
  [_presenter setControlsVisible:YES];
  NSSlider* slider = Slider(self.content);
  EXPECT(slider != nil);
  EXPECT(slider.hidden);
  [_presenter setPosition:5 duration:20];
  EXPECT(slider.hidden);
  [_presenter showInactive];
  Hover(_presenter);
  EXPECT(!slider.hidden);
  EXPECT(slider.doubleValue == 5);
  [_presenter setPosition:0 duration:0];
  EXPECT(slider.hidden);
}

- (void)testTheSliderAdvancesWhilePlayingAndHoldsWhilePaused {
  [self showHovering];
  NSSlider* slider = Slider(self.content);
  [_presenter setPosition:5 duration:20 playbackRate:1];
  ParcNativeAdvance(0.12);
  EXPECT(slider.doubleValue > 5);
  [_presenter setPosition:8 duration:20 playbackRate:0];
  EXPECT(slider.doubleValue == 8);
}

- (void)testANaturalSizeFitsThePanelInsideTheWorkArea {
  [_presenter showInactive];
  [_presenter.panel setFrameOrigin:NSMakePoint(-2000, -2000)];
  ParcNativeAdvance(0.05);
  [_presenter setNaturalSize:NSMakeSize(1920, 1080)];
  NSRect frame = _presenter.panel.frame;
  NSRect work = NSScreen.mainScreen.visibleFrame;
  EXPECT(NSWidth(frame) >= 480);
  EXPECT(fabs(NSWidth(frame) / NSHeight(frame) - 16.0 / 9.0) < 0.05);
  EXPECT(NSMaxX(frame) <= NSMaxX(work) + 1);
  EXPECT(NSMinY(frame) >= NSMinY(work) - 1);
  EXPECT(ParcNativeVisible(_presenter.panel));
  EXPECT(!_presenter.panel.keyWindow);
}

- (void)testThePanelRefusesKeyStatusAndResizesTheVideo {
  [_presenter showInactive];
  ParcNativeMakeKey(_presenter.panel);
  EXPECT(!_presenter.panel.canBecomeKeyWindow);
  EXPECT(!_presenter.panel.keyWindow);
  EXPECT(_presenter.panel.styleMask & NSWindowStyleMaskNonactivatingPanel);
  [_presenter.panel setContentSize:NSMakeSize(640, 360)];
  EXPECT(NSWidth(_video.bounds) == 640);
  EXPECT(_changes > 0);
}

- (void)testCaptionsDrawAboveTheVideoWithoutTakingClicks {
  NSView* captions = Captions(self.content);
  EXPECT(captions != nil);
  EXPECT(captions.hidden);
  NSImage* cue = Cue();
  [_presenter showInactive];
  [_presenter.panel setContentSize:NSMakeSize(640, 360)];
  [_presenter setControlsVisible:NO];
  [_presenter setCaptions:cue bounds:NSMakeRect(0.1, 0.8, 0.8, 0.1)];
  EXPECT(!captions.hidden);
  EXPECT(Near(captions.frame, NSMakeRect(64, 36, 512, 36)));
  NSUInteger captionsIndex = [self.content.subviews indexOfObject:captions];
  EXPECT(captionsIndex > [self.content.subviews indexOfObject:_video]);
  EXPECT(captionsIndex == self.content.subviews.count - 2);
  NSView* hit = [self.content hitTest:NSMakePoint(100, 40)];
  EXPECT(hit != nil && hit != captions);
  [captions displayIfNeeded];
  EXPECT(captions.layer.contents == cue);
}

- (void)testCaptionsScaleWithThePanel {
  NSView* captions = [self captionsShownAt640];
  [_presenter.panel setContentSize:NSMakeSize(320, 180)];
  EXPECT(Near(captions.frame, NSMakeRect(32, 18, 256, 18)));
}

- (void)testCaptionsRiseAboveTheSliderOnlyWhileItShows {
  NSView* captions = [self captionsShownAt640];
  [_presenter.panel setContentSize:NSMakeSize(320, 180)];
  [_presenter setControlsVisible:YES];
  Hover(_presenter);
  NSSlider* slider = Slider(self.content);
  EXPECT(slider.hidden);
  EXPECT(Near(captions.frame, NSMakeRect(32, 18, 256, 18)));
  [_presenter setPosition:5 duration:20];
  EXPECT(!slider.hidden);
  EXPECT(NSMinY(captions.frame) >= NSMaxY(slider.frame));
  EXPECT(NSWidth(captions.frame) == 256);
  [_presenter setControlsVisible:NO];
  EXPECT(Near(captions.frame, NSMakeRect(32, 18, 256, 18)));
}

- (void)testCaptionsClampToThePanelAndHideForInvalidBounds {
  NSView* captions = [self captionsShownAt640];
  NSImage* cue = Cue();
  [_presenter.panel setContentSize:NSMakeSize(320, 180)];
  [_presenter setControlsVisible:YES];
  [_presenter setPosition:0 duration:0];
  [_presenter setCaptions:cue bounds:NSMakeRect(0.5, 0.9, 0.8, 0.2)];
  EXPECT(Near(captions.frame, NSMakeRect(160, 0, 160, 18)));
  [_presenter setCaptions:cue bounds:NSMakeRect(1e308, -1e308, 1e308, 1e308)];
  EXPECT(captions.hidden);
  [_presenter setCaptions:cue bounds:NSMakeRect(NAN, 0.8, 0.8, 0.1)];
  EXPECT(captions.hidden);
  [_presenter setCaptions:cue bounds:NSMakeRect(0.1, 0.8, 0.8, 0.1)];
  [_presenter setCaptions:nil bounds:NSZeroRect];
  EXPECT(captions.hidden);
}

- (void)testActionButtonsActOnlyWhileShownAndEnabled {
  [self hoveredPlayButton];
  [Button(self.content, PCVideoPiPPlayPause) performClick:nil];
  EXPECT(_actions == 1);
  EXPECT(_last == PCVideoPiPPlayPause);
  EXPECT(!_presenter.panel.keyWindow);
  [_presenter setControlsVisible:NO];
  [Button(self.content, PCVideoPiPPlayPause) performClick:nil];
  EXPECT(_actions == 1);
  [_presenter setControlsVisible:YES];
  Hover(_presenter);
  [_presenter setAction:PCVideoPiPPlayPause visible:NO];
  [Button(self.content, PCVideoPiPPlayPause) performClick:nil];
  EXPECT(_actions == 1);
  NSButton* play = Button(self.content, PCVideoPiPPlayPause);
  EXPECT(play.alphaValue < 1);
  [_presenter setAction:PCVideoPiPPlayPause visible:YES];
  EXPECT(play.alphaValue == 1);
}

- (void)testHoveredControlsShowThePointingHandWithoutActivatingParc {
  NSButton* play = [self hoveredPlayButton];
  EXPECT(Host(play).layer.transform.m11 > 1.09);
  EXPECT(ParcNativeCursor() == NSCursor.pointingHandCursor);
  EXPECT(!NSApp.active);
  EXPECT(ParcNativeBackgroundCursorEnabled());
  EXPECT(!_presenter.panel.keyWindow);
}

- (void)testHidingTheControlsRestoresTheArrow {
  NSButton* play = [self hoveredPlayButton];
  [_presenter setControlsVisible:NO];
  EXPECT(ParcNativeCursor() == NSCursor.arrowCursor);
  EXPECT(!ParcNativeBackgroundCursorEnabled());
  EXPECT(play.alphaValue < 1);
  EXPECT(Host(play).layer.transform.m11 == 1);
  [_presenter setControlsVisible:YES];
  EXPECT(ParcNativeCursor() == NSCursor.pointingHandCursor);
  EXPECT(play.alphaValue == 1);
  EXPECT(ParcNativeBackgroundCursorEnabled());
}

- (void)testMovingThePanelFromUnderThePointerRestoresTheArrow {
  NSButton* play = [self hoveredPlayButton];
  NSRect off = _presenter.panel.frame;
  off.origin.x += 60;
  [_presenter.panel setFrame:off display:YES];
  [self.content mouseMoved:[NSEvent new]];
  EXPECT(ParcNativeCursor() == NSCursor.arrowCursor);
  EXPECT(play.alphaValue < 1);
  Hover(_presenter);
  EXPECT(ParcNativeCursor() == NSCursor.pointingHandCursor);
}

- (void)testPointingAtAControlKeepsTheHandWhileControlsAreHidden {
  [self hoveredPlayButton];
  PCPictureInPicturePointAtControl(YES);
  [_presenter setControlsVisible:NO];
  EXPECT(ParcNativeBackgroundCursorEnabled());
  PCPictureInPicturePointAtControl(NO);
  EXPECT(!ParcNativeBackgroundCursorEnabled());
  [_presenter setControlsVisible:YES];
  EXPECT(ParcNativeBackgroundCursorEnabled());
}

- (void)testWindowChipsAreRoundAndActionsTakeTheirTitles {
  [self showHovering];
  for (NSNumber* tag in @[ @(PCVideoPiPReturn), @(PCVideoPiPMinimize), @(PCVideoPiPClose) ]) {
    NSButton* chip = Button(self.content, tag.integerValue);
    EXPECT(Near(chip.frame, NSMakeRect(0, 0, 28, 28)));
    if (@available(macOS 26.0, *)) {
      EXPECT(((NSGlassEffectView*)Host(chip)).cornerRadius == 14);
    }
  }
  [_presenter setAction:PCVideoPiPMute title:@"Unmute"];
  EXPECT([Button(self.content, PCVideoPiPMute).accessibilityLabel isEqual:@"Unmute"]);
}

- (void)testHidingShowsAgainAndInvalidationIsFinal {
  [self showHovering];
  [_presenter hide];
  EXPECT(!ParcNativeVisible(_presenter.panel));
  EXPECT(_actions == 0);
  [_presenter showInactive];
  EXPECT(ParcNativeVisible(_presenter.panel));
  EXPECT(!_presenter.panel.canBecomeKeyWindow);
  EXPECT(!_presenter.panel.keyWindow);
  [_presenter invalidate];
  EXPECT(_presenter.invalidated);
  EXPECT(!ParcNativeVisible(_presenter.panel));
  EXPECT(_video.superview == nil);
  [_presenter showInactive];
  EXPECT(!ParcNativeVisible(_presenter.panel));
  [_presenter invalidate];
  EXPECT(_actions == 0);
}

- (void)testClosingThePanelReportsASystemClose {
  __block int actions = 0;
  __block PCVideoPiPAction last = PCVideoPiPClose;
  __block PCVideoPiPPresenter* closing;
  closing = Offscreen([[PCVideoPiPPresenter alloc] initWithVideoView:[NSView new]
      sourceFrame:NSZeroRect
      action:^(PCVideoPiPAction action, double value) {
        ++actions;
        last = action;
        [closing invalidate];
        closing = nil;
      }
      changed:^{
      }]);
  NSPanel* panel = closing.panel;
  [closing showInactive];
  ParcNativeClose(panel);
  EXPECT(closing == nil);
  EXPECT(last == PCVideoPiPSystemClose);
  EXPECT(actions == 1);
  EXPECT(!ParcNativeVisible(panel));
}

- (void)testInvalidatingFromAChangeCallbackIsSafe {
  __block PCVideoPiPPresenter* reentrant;
  reentrant = Offscreen([[PCVideoPiPPresenter alloc] initWithVideoView:[NSView new]
      sourceFrame:NSZeroRect
      action:^(PCVideoPiPAction action, double value) {
      }
      changed:^{
        [reentrant invalidate];
        reentrant = nil;
      }]);
  [reentrant showInactive];
  EXPECT(reentrant == nil);
}

- (PCVideoPiPPresenter*)fittingPresenterFor:(NSView*)fitted resized:(int*)resized {
  return Offscreen([[PCVideoPiPPresenter alloc] initWithVideoView:fitted
      sourceFrame:NSZeroRect
      action:^(PCVideoPiPAction a, double v) {
      }
      changed:^{
        if (resized) ++*resized;
      }]);
}

- (void)testThePanelTakesEachVideoAspectAndKeepsItsCorner {
  NSView* fitted = [NSView new];
  PCVideoPiPPresenter* fitting = [self fittingPresenterFor:fitted resized:NULL];
  NSPanel* fitPanel = fitting.panel;
  [fitting setNaturalSize:NSMakeSize(1920, 1080)];
  EXPECT(Aspect(fitPanel.frame, 16.0 / 9.0));
  EXPECT(Near(fitted.frame, fitPanel.contentView.bounds));
  const NSRect corner = fitPanel.frame;
  [fitting setNaturalSize:NSMakeSize(1920, 804)];
  EXPECT(Aspect(fitPanel.frame, 1920.0 / 804.0));
  EXPECT(NSWidth(fitPanel.frame) == NSWidth(corner));
  EXPECT(fabs(NSMaxX(fitPanel.frame) - NSMaxX(corner)) < 1);
  EXPECT(fabs(NSMinY(fitPanel.frame) - NSMinY(corner)) < 1);
  EXPECT(Near(fitted.frame, fitPanel.contentView.bounds));
  [fitting setNaturalSize:NSMakeSize(1440, 1080)];
  EXPECT(Aspect(fitPanel.frame, 4.0 / 3.0));
  EXPECT(Near(fitted.frame, fitPanel.contentView.bounds));
  [fitting invalidate];
}

- (void)testAForcedPanelSizeLetterboxesTheVideoAndItsCaptions {
  NSView* fitted = [NSView new];
  PCVideoPiPPresenter* fitting = [self fittingPresenterFor:fitted resized:NULL];
  NSPanel* fitPanel = fitting.panel;
  [fitting setNaturalSize:NSMakeSize(1440, 1080)];
  [fitPanel setContentSize:NSMakeSize(640, 360)];
  EXPECT(Near(fitted.frame, NSMakeRect(80, 0, 480, 360)));
  EXPECT(fitted.layer.cornerRadius == 0);
  [fitting setCaptions:Cue() bounds:NSMakeRect(0.1, 0.8, 0.8, 0.1)];
  EXPECT(Near(Captions(fitPanel.contentView).frame, NSMakeRect(128, 36, 384, 36)));
  [fitting invalidate];
}

- (void)testAHiddenPanelTakesTheNewAspectWhenShown {
  NSView* fitted = [NSView new];
  int resized = 0;
  PCVideoPiPPresenter* fitting = [self fittingPresenterFor:fitted resized:&resized];
  NSPanel* fitPanel = fitting.panel;
  [fitting setNaturalSize:NSMakeSize(1440, 1080)];
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
  [fitPanel setContentSize:NSMakeSize(640, 266.4)];
  EXPECT(Near(fitted.frame, fitPanel.contentView.bounds));
  [fitting invalidate];
}

- (void)testALiveResizeDefersRefittingUntilItEnds {
  NSView* fitted = [NSView new];
  PCVideoPiPPresenter* fitting = [self fittingPresenterFor:fitted resized:NULL];
  NSPanel* fitPanel = fitting.panel;
  [fitting setNaturalSize:NSMakeSize(1920, 800)];
  [fitting showInactive];
  [fitPanel setContentSize:NSMakeSize(640, 266.4)];
  class_addMethod(object_getClass(fitPanel), @selector(inLiveResize), (IMP)LiveResize, "c@:");
  const NSRect dragged = fitPanel.frame;
  gLiveResize = YES;
  [fitting setNaturalSize:NSMakeSize(1920, 1080)];
  EXPECT(Near(fitPanel.frame, dragged));
  EXPECT(Aspect(fitted.frame, 2.4));
  [[NSNotificationCenter defaultCenter] postNotificationName:NSWindowDidEndLiveResizeNotification object:fitPanel];
  gLiveResize = NO;
  EXPECT(Aspect(fitPanel.frame, 16.0 / 9.0));
  EXPECT(NSWidth(fitPanel.frame) == NSWidth(dragged));
  EXPECT(Near(fitted.frame, fitPanel.contentView.bounds));
  [fitting invalidate];
}

- (void)testEmptyOrInvalidNaturalSizesAreIgnored {
  NSView* fitted = [NSView new];
  PCVideoPiPPresenter* fitting = [self fittingPresenterFor:fitted resized:NULL];
  [fitting setNaturalSize:NSMakeSize(1920, 800)];
  [fitting setNaturalSize:NSMakeSize(0, 0)];
  [fitting setNaturalSize:NSMakeSize(NAN, 1)];
  EXPECT(Aspect(fitted.frame, 2.4));
  [fitting invalidate];
}

- (void)testInvalidatingDuringARefitIsSafe {
  __block PCVideoPiPPresenter* releasing;
  releasing = Offscreen([[PCVideoPiPPresenter alloc] initWithVideoView:[NSView new]
      sourceFrame:NSZeroRect
      action:^(PCVideoPiPAction action, double value) {
      }
      changed:^{
        if (releasing.panel.frame.size.width / releasing.panel.frame.size.height > 2) {
          [releasing invalidate];
          releasing = nil;
        }
      }]);
  [releasing setNaturalSize:NSMakeSize(1920, 1080)];
  [releasing setNaturalSize:NSMakeSize(1920, 804)];
  EXPECT(releasing == nil);
}

@end
