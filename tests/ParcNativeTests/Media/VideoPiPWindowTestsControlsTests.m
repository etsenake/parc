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
  VideoPiPWindowTestsHover(_presenter, _pointer);
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
  EXPECT(_pointer.cursor == NSCursor.pointingHandCursor);
  EXPECT(!NSApp.active);
  EXPECT(_pointer.backgroundCursorEnabled);
  EXPECT(!_presenter.panel.keyWindow);
}

- (void)testHidingTheControlsRestoresTheArrow {
  NSButton* play = [self hoveredPlayButton];
  [_presenter setControlsVisible:NO];
  EXPECT(_pointer.cursor == NSCursor.arrowCursor);
  EXPECT(!_pointer.backgroundCursorEnabled);
  EXPECT(play.alphaValue < 1);
  EXPECT(VideoPiPWindowTestsHost(play).layer.transform.m11 == 1);
  [_presenter setControlsVisible:YES];
  EXPECT(_pointer.cursor == NSCursor.pointingHandCursor);
  EXPECT(play.alphaValue == 1);
  EXPECT(_pointer.backgroundCursorEnabled);
}

- (void)testMovingThePanelFromUnderThePointerRestoresTheArrow {
  NSButton* play = [self hoveredPlayButton];
  NSRect off = _presenter.panel.frame;
  off.origin.x += 60;
  [_presenter.panel setFrame:off display:YES];
  [self.content mouseMoved:[NSEvent new]];
  EXPECT(_pointer.cursor == NSCursor.arrowCursor);
  EXPECT(play.alphaValue < 1);
  VideoPiPWindowTestsHover(_presenter, _pointer);
  EXPECT(_pointer.cursor == NSCursor.pointingHandCursor);
}

- (void)testPointingAtAControlKeepsTheHandWhileControlsAreHidden {
  [self hoveredPlayButton];
  PCPictureInPicturePointAtControlInEnvironment(YES, _pointer);
  [_presenter setControlsVisible:NO];
  EXPECT(_pointer.backgroundCursorEnabled);
  PCPictureInPicturePointAtControlInEnvironment(NO, _pointer);
  EXPECT(!_pointer.backgroundCursorEnabled);
  [_presenter setControlsVisible:YES];
  EXPECT(_pointer.backgroundCursorEnabled);
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
