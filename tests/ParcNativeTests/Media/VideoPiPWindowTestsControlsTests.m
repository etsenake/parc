#import "VideoPiPWindowTestsSupport.h"

__attribute__((objc_runtime_name("ParcNativeTests_VideoPiPWindowTestsControlsTests")))
@interface VideoPiPWindowTestsControlsTests : VideoPiPWindowTestsSupport
@end

@implementation VideoPiPWindowTestsControlsTests

- (void)testClickingTheVisiblePlayButtonDeliversItsAction {
  [self hoveredPlayButton];
  VideoPiPWindowTestsSendClick(VideoPiPWindowTestsButton(self.content, PCVideoPiPPlayPause));
  EXPECT(_actions == 1);
  EXPECT(_last == PCVideoPiPPlayPause);
  EXPECT(!_presenter.panel.keyWindow);
}

- (void)testHiddenControlsIgnoreThePlayButton {
  [self hoveredPlayButton];
  VideoPiPWindowTestsSendClick(VideoPiPWindowTestsButton(self.content, PCVideoPiPPlayPause));
  EXPECT(_actions == 1);
  EXPECT(_last == PCVideoPiPPlayPause);
  EXPECT(!_presenter.panel.keyWindow);
  [_presenter setControlsVisible:NO];
  VideoPiPWindowTestsSendClick(VideoPiPWindowTestsButton(self.content, PCVideoPiPPlayPause));
  EXPECT(_actions == 1);
}

- (void)testDisablingPlayIgnoresClicksUntilTheActionReturns {
  [self hoveredPlayButton];
  VideoPiPWindowTestsSendClick(VideoPiPWindowTestsButton(self.content, PCVideoPiPPlayPause));
  EXPECT(_actions == 1);
  EXPECT(_last == PCVideoPiPPlayPause);
  EXPECT(!_presenter.panel.keyWindow);
  [_presenter setControlsVisible:NO];
  VideoPiPWindowTestsSendClick(VideoPiPWindowTestsButton(self.content, PCVideoPiPPlayPause));
  EXPECT(_actions == 1);
  [_presenter setControlsVisible:YES];
  VideoPiPWindowTestsHover(_presenter);
  [_presenter setAction:PCVideoPiPPlayPause visible:NO];
  VideoPiPWindowTestsSendClick(VideoPiPWindowTestsButton(self.content, PCVideoPiPPlayPause));
  EXPECT(_actions == 1);
  NSButton* play = VideoPiPWindowTestsButton(self.content, PCVideoPiPPlayPause);
  EXPECT(play.alphaValue < 1);
  [_presenter setAction:PCVideoPiPPlayPause visible:YES];
  EXPECT(play.alphaValue == 1);
}

- (void)testHoveredControlsShowThePointingHandWithoutActivatingParc {
  NSButton* play = [self hoveredPlayButton];
  EXPECT(VideoPiPWindowTestsHost(play).layer.transform.m11 > 1.09);
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
  EXPECT(VideoPiPWindowTestsHost(play).layer.transform.m11 == 1);
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
  VideoPiPWindowTestsHover(_presenter);
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

- (void)testTheWindowChipsAreRound {
  [self showHovering];
  for (NSNumber* tag in @[ @(PCVideoPiPReturn), @(PCVideoPiPMinimize), @(PCVideoPiPClose) ]) {
    NSButton* chip = VideoPiPWindowTestsButton(self.content, tag.integerValue);
    EXPECT(VideoPiPWindowTestsNear(chip.frame, NSMakeRect(0, 0, 28, 28)));
    if (@available(macOS 26.0, *)) {
      EXPECT(((NSGlassEffectView*)VideoPiPWindowTestsHost(chip)).cornerRadius == 14);
    }
  }
}

- (void)testTheMuteActionUsesItsSuppliedTitle {
  [self showHovering];
  [_presenter setAction:PCVideoPiPMute title:@"Unmute"];
  EXPECT([VideoPiPWindowTestsButton(self.content, PCVideoPiPMute).accessibilityLabel isEqual:@"Unmute"]);
}

@end
