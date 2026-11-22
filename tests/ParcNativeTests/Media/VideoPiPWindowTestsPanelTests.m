#import "VideoPiPWindowTestsSupport.h"

__attribute__((objc_runtime_name("ParcNativeTests_VideoPiPWindowTestsPanelTests")))
@interface VideoPiPWindowTestsPanelTests : VideoPiPWindowTestsSupport
@end

@implementation VideoPiPWindowTestsPanelTests

- (void)testThePanelHostsTheSuppliedVideo {
  EXPECT(_presenter.videoView == _video);
  EXPECT(_video.superview == self.content);
}

- (void)testThePanelStartsHidden {
  EXPECT(!ParcNativeVisible(_presenter.panel));
}

- (void)testThePanelDoesNotTakeKeyFocus {
  EXPECT(!_presenter.panel.keyWindow);
  EXPECT(!_presenter.panel.canBecomeKeyWindow);
  EXPECT(_presenter.panel.styleMask & NSWindowStyleMaskNonactivatingPanel);
}

- (void)testThePanelIsResizable {
  EXPECT(_presenter.panel.styleMask & NSWindowStyleMaskResizable);
}

- (void)testThePanelFloatsOverAllSpacesWhenParcIsInactive {
  EXPECT(_presenter.panel.level == NSFloatingWindowLevel);
  EXPECT(!_presenter.panel.hidesOnDeactivate);
  EXPECT(_presenter.panel.collectionBehavior & NSWindowCollectionBehaviorCanJoinAllSpaces);
}

- (void)testThePanelContentHasRoundedCorners {
  EXPECT(self.content.layer.cornerRadius == 16);
}

- (void)testMediaActionsAreAbsentByDefault {
  EXPECT(VideoPiPWindowTestsButton(self.content, PCVideoPiPSkipAd) == nil);
  EXPECT(VideoPiPWindowTestsButton(self.content, PCVideoPiPNextTrack) == nil);
  EXPECT(VideoPiPWindowTestsButton(self.content, PCVideoPiPPreviousTrack) == nil);
}

- (void)testTheCloseChipIsRoundAndBorderless {
  NSButton* closeButton = VideoPiPWindowTestsButton(self.content, PCVideoPiPClose);
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
  NSSlider* slider = VideoPiPWindowTestsSlider(self.content);
  EXPECT(slider != nil);
  EXPECT(slider.hidden);
  [_presenter setPosition:5 duration:20];
  EXPECT(slider.hidden);
  [_presenter showInactive];
  VideoPiPWindowTestsHover(_presenter);
  EXPECT(!slider.hidden);
  EXPECT(slider.doubleValue == 5);
  [_presenter setPosition:0 duration:0];
  EXPECT(slider.hidden);
}

- (void)testTheSliderAdvancesWhilePlayingAndHoldsWhilePaused {
  [self showHovering];
  NSSlider* slider = VideoPiPWindowTestsSlider(self.content);
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

- (void)testThePanelRefusesToBecomeKeyWhenAsked {
  [_presenter showInactive];
  ParcNativeMakeKey(_presenter.panel);
  EXPECT(!_presenter.panel.canBecomeKeyWindow);
  EXPECT(!_presenter.panel.keyWindow);
  EXPECT(_presenter.panel.styleMask & NSWindowStyleMaskNonactivatingPanel);
}

- (void)testResizingThePanelResizesTheVideo {
  [_presenter showInactive];
  [_presenter.panel setContentSize:NSMakeSize(640, 360)];
  EXPECT(NSWidth(_video.bounds) == 640);
  EXPECT(_changes > 0);
}

- (void)testAHiddenPanelCanShowAgainWithoutTakingFocus {
  [self showHovering];
  [_presenter hide];
  EXPECT(!ParcNativeVisible(_presenter.panel));
  EXPECT(_actions == 0);
  [_presenter showInactive];
  EXPECT(ParcNativeVisible(_presenter.panel));
  EXPECT(!_presenter.panel.canBecomeKeyWindow);
  EXPECT(!_presenter.panel.keyWindow);
}

- (void)testAnInvalidatedPanelCannotShowAgain {
  [self showHovering];
  [_presenter hide];
  [_presenter showInactive];
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
  closing = VideoPiPWindowTestsOffscreen([[PCVideoPiPPresenter alloc] initWithVideoView:[NSView new]
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
  reentrant = VideoPiPWindowTestsOffscreen([[PCVideoPiPPresenter alloc] initWithVideoView:[NSView new]
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

@end
