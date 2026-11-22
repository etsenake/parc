#import "VideoPiPWindowTestsSupport.h"

__attribute__((objc_runtime_name("ParcNativeTests_VideoPiPWindowTestsSizingTests")))
@interface VideoPiPWindowTestsSizingTests : VideoPiPWindowTestsSupport
@end

@implementation VideoPiPWindowTestsSizingTests

- (PCVideoPiPPresenter*)fittingPresenterFor:(NSView*)fitted resized:(int*)resized {
  return VideoPiPWindowTestsOffscreen([[PCVideoPiPPresenter alloc] initWithVideoView:fitted
      sourceFrame:NSZeroRect
      action:^(PCVideoPiPAction a, double v) {
      }
      changed:^{
        if (resized) ++*resized;
      }
      environment:_pointer]);
}

- (void)testThePanelTakesEachVideoAspectAndKeepsItsCorner {
  NSView* fitted = [NSView new];
  PCVideoPiPPresenter* fitting = [self fittingPresenterFor:fitted resized:NULL];
  NSPanel* fitPanel = fitting.panel;
  [fitting setNaturalSize:NSMakeSize(1920, 1080)];
  EXPECT(VideoPiPWindowTestsAspect(fitPanel.frame, 16.0 / 9.0));
  EXPECT(VideoPiPWindowTestsNear(fitted.frame, fitPanel.contentView.bounds));
  const NSRect corner = fitPanel.frame;
  [fitting setNaturalSize:NSMakeSize(1920, 804)];
  EXPECT(VideoPiPWindowTestsAspect(fitPanel.frame, 1920.0 / 804.0));
  EXPECT(NSWidth(fitPanel.frame) == NSWidth(corner));
  EXPECT(fabs(NSMaxX(fitPanel.frame) - NSMaxX(corner)) < 1);
  EXPECT(fabs(NSMinY(fitPanel.frame) - NSMinY(corner)) < 1);
  EXPECT(VideoPiPWindowTestsNear(fitted.frame, fitPanel.contentView.bounds));
  [fitting setNaturalSize:NSMakeSize(1440, 1080)];
  EXPECT(VideoPiPWindowTestsAspect(fitPanel.frame, 4.0 / 3.0));
  EXPECT(VideoPiPWindowTestsNear(fitted.frame, fitPanel.contentView.bounds));
  [fitting invalidate];
}

- (void)testAForcedPanelSizeLetterboxesTheVideoAndItsCaptions {
  NSView* fitted = [NSView new];
  PCVideoPiPPresenter* fitting = [self fittingPresenterFor:fitted resized:NULL];
  NSPanel* fitPanel = fitting.panel;
  [fitting setNaturalSize:NSMakeSize(1440, 1080)];
  [fitPanel setContentSize:NSMakeSize(640, 360)];
  EXPECT(VideoPiPWindowTestsNear(fitted.frame, NSMakeRect(80, 0, 480, 360)));
  EXPECT(fitted.layer.cornerRadius == 0);
  [fitting setCaptions:VideoPiPWindowTestsCue() bounds:NSMakeRect(0.1, 0.8, 0.8, 0.1)];
  EXPECT(VideoPiPWindowTestsNear(VideoPiPWindowTestsCaptions(fitPanel.contentView).frame, NSMakeRect(128, 36, 384, 36)));
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
  EXPECT(VideoPiPWindowTestsAspect(fitPanel.frame, 2.4));
  EXPECT(NSWidth(fitPanel.frame) == 640);
  EXPECT(VideoPiPWindowTestsNear(fitted.frame, fitPanel.contentView.bounds));
  EXPECT(resized > 0);
  EXPECT(fitted.layer.cornerRadius == 16);
  [fitPanel setContentSize:NSMakeSize(640, 266.4)];
  EXPECT(VideoPiPWindowTestsNear(fitted.frame, fitPanel.contentView.bounds));
  [fitting invalidate];
}

- (void)testALiveResizeDefersRefittingUntilItEnds {
  NSView* fitted = [NSView new];
  PCVideoPiPPresenter* fitting = [self fittingPresenterFor:fitted resized:NULL];
  NSPanel* fitPanel = fitting.panel;
  [fitting setNaturalSize:NSMakeSize(1920, 800)];
  [fitting showInactive];
  [fitPanel setContentSize:NSMakeSize(640, 266.4)];
  const NSRect dragged = fitPanel.frame;
  _pointer.liveResize = YES;
  [fitting setNaturalSize:NSMakeSize(1920, 1080)];
  EXPECT(VideoPiPWindowTestsNear(fitPanel.frame, dragged));
  EXPECT(VideoPiPWindowTestsAspect(fitted.frame, 2.4));
  [[NSNotificationCenter defaultCenter] postNotificationName:NSWindowDidEndLiveResizeNotification object:fitPanel];
  _pointer.liveResize = NO;
  EXPECT(VideoPiPWindowTestsAspect(fitPanel.frame, 16.0 / 9.0));
  EXPECT(NSWidth(fitPanel.frame) == NSWidth(dragged));
  EXPECT(VideoPiPWindowTestsNear(fitted.frame, fitPanel.contentView.bounds));
  [fitting invalidate];
}

- (void)testEmptyOrInvalidNaturalSizesAreIgnored {
  NSView* fitted = [NSView new];
  PCVideoPiPPresenter* fitting = [self fittingPresenterFor:fitted resized:NULL];
  [fitting setNaturalSize:NSMakeSize(1920, 800)];
  [fitting setNaturalSize:NSMakeSize(0, 0)];
  [fitting setNaturalSize:NSMakeSize(NAN, 1)];
  EXPECT(VideoPiPWindowTestsAspect(fitted.frame, 2.4));
  [fitting invalidate];
}

- (void)testInvalidatingDuringARefitIsSafe {
  __block PCVideoPiPPresenter* releasing;
  releasing = VideoPiPWindowTestsOffscreen([[PCVideoPiPPresenter alloc] initWithVideoView:[NSView new]
      sourceFrame:NSZeroRect
      action:^(PCVideoPiPAction action, double value) {
      }
      changed:^{
        if (releasing.panel.frame.size.width / releasing.panel.frame.size.height > 2) {
          [releasing invalidate];
          releasing = nil;
        }
      }
      environment:_pointer]);
  [releasing setNaturalSize:NSMakeSize(1920, 1080)];
  [releasing setNaturalSize:NSMakeSize(1920, 804)];
  EXPECT(releasing == nil);
}

- (NSView*)captionsShownAt640 {
  [_presenter showInactive];
  [_presenter.panel setContentSize:NSMakeSize(640, 360)];
  [_presenter setControlsVisible:NO];
  [_presenter setCaptions:VideoPiPWindowTestsCue() bounds:NSMakeRect(0.1, 0.8, 0.8, 0.1)];
  return VideoPiPWindowTestsCaptions(self.content);
}

- (void)testTheCaptionsViewStartsHidden {
  NSView* captions = VideoPiPWindowTestsCaptions(self.content);
  EXPECT(captions != nil);
  EXPECT(captions.hidden);
}

- (void)testCaptionsDrawAboveTheVideo {
  NSView* captions = VideoPiPWindowTestsCaptions(self.content);
  NSImage* cue = VideoPiPWindowTestsCue();
  [_presenter showInactive];
  [_presenter.panel setContentSize:NSMakeSize(640, 360)];
  [_presenter setControlsVisible:NO];
  [_presenter setCaptions:cue bounds:NSMakeRect(0.1, 0.8, 0.8, 0.1)];
  EXPECT(!captions.hidden);
  EXPECT(VideoPiPWindowTestsNear(captions.frame, NSMakeRect(64, 36, 512, 36)));
  NSUInteger captionsIndex = [self.content.subviews indexOfObject:captions];
  EXPECT(captionsIndex > [self.content.subviews indexOfObject:_video]);
  EXPECT(captionsIndex == self.content.subviews.count - 2);
  [captions displayIfNeeded];
  EXPECT(captions.layer.contents == cue);
}

- (void)testCaptionsLetClicksThrough {
  NSView* captions = VideoPiPWindowTestsCaptions(self.content);
  NSImage* cue = VideoPiPWindowTestsCue();
  [_presenter showInactive];
  [_presenter.panel setContentSize:NSMakeSize(640, 360)];
  [_presenter setControlsVisible:NO];
  [_presenter setCaptions:cue bounds:NSMakeRect(0.1, 0.8, 0.8, 0.1)];
  NSView* hit = [self.content hitTest:NSMakePoint(100, 40)];
  EXPECT(hit != nil && hit != captions);
}

- (void)testCaptionsScaleWithThePanel {
  NSView* captions = [self captionsShownAt640];
  [_presenter.panel setContentSize:NSMakeSize(320, 180)];
  EXPECT(VideoPiPWindowTestsNear(captions.frame, NSMakeRect(32, 18, 256, 18)));
}

- (void)testCaptionsRiseAboveTheSliderOnlyWhileItShows {
  NSView* captions = [self captionsShownAt640];
  [_presenter.panel setContentSize:NSMakeSize(320, 180)];
  [_presenter setControlsVisible:YES];
  VideoPiPWindowTestsHover(_presenter, _pointer);
  NSSlider* slider = VideoPiPWindowTestsSlider(self.content);
  EXPECT(slider.hidden);
  EXPECT(VideoPiPWindowTestsNear(captions.frame, NSMakeRect(32, 18, 256, 18)));
  [_presenter setPosition:5 duration:20];
  EXPECT(!slider.hidden);
  EXPECT(NSMinY(captions.frame) >= NSMaxY(slider.frame));
  EXPECT(NSWidth(captions.frame) == 256);
  [_presenter setControlsVisible:NO];
  EXPECT(VideoPiPWindowTestsNear(captions.frame, NSMakeRect(32, 18, 256, 18)));
}

- (void)testCaptionsClampToThePanel {
  NSView* captions = [self captionsShownAt640];
  NSImage* cue = VideoPiPWindowTestsCue();
  [_presenter.panel setContentSize:NSMakeSize(320, 180)];
  [_presenter setControlsVisible:YES];
  [_presenter setPosition:0 duration:0];
  [_presenter setCaptions:cue bounds:NSMakeRect(0.5, 0.9, 0.8, 0.2)];
  EXPECT(VideoPiPWindowTestsNear(captions.frame, NSMakeRect(160, 0, 160, 18)));
}

- (void)testHugeCaptionBoundsHideTheCue {
  NSView* captions = [self captionsShownAt640];
  NSImage* cue = VideoPiPWindowTestsCue();
  [_presenter.panel setContentSize:NSMakeSize(320, 180)];
  [_presenter setControlsVisible:YES];
  [_presenter setPosition:0 duration:0];
  [_presenter setCaptions:cue bounds:NSMakeRect(1e308, -1e308, 1e308, 1e308)];
  EXPECT(captions.hidden);
}

- (void)testNonfiniteCaptionBoundsHideTheCue {
  NSView* captions = [self captionsShownAt640];
  NSImage* cue = VideoPiPWindowTestsCue();
  [_presenter.panel setContentSize:NSMakeSize(320, 180)];
  [_presenter setControlsVisible:YES];
  [_presenter setPosition:0 duration:0];
  [_presenter setCaptions:cue bounds:NSMakeRect(NAN, 0.8, 0.8, 0.1)];
  EXPECT(captions.hidden);
}

- (void)testClearingTheCueHidesCaptions {
  NSView* captions = [self captionsShownAt640];
  NSImage* cue = VideoPiPWindowTestsCue();
  [_presenter.panel setContentSize:NSMakeSize(320, 180)];
  [_presenter setControlsVisible:YES];
  [_presenter setPosition:0 duration:0];
  [_presenter setCaptions:cue bounds:NSMakeRect(0.1, 0.8, 0.8, 0.1)];
  [_presenter setCaptions:nil bounds:NSZeroRect];
  EXPECT(captions.hidden);
}

@end
