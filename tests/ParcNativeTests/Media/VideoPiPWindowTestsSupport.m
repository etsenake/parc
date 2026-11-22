#import "VideoPiPWindowTestsSupport.h"

@implementation VideoPiPWindowTestsSupport

- (void)setUp {
  [super setUp];
  _pointer = [ParcNativePointerEnvironment new];
  _video = [NSView new];
  _last = PCVideoPiPClose;
  __weak VideoPiPWindowTestsSupport* weak = self;
  _presenter = VideoPiPWindowTestsOffscreen([[PCVideoPiPPresenter alloc] initWithVideoView:_video
      sourceFrame:NSMakeRect(20, 20, 640, 360)
      action:^(PCVideoPiPAction action, double value) {
        VideoPiPWindowTestsSupport* test = weak;
        if (!test) return;
        ++test->_actions;
        test->_last = action;
      }
      changed:^{
        VideoPiPWindowTestsSupport* test = weak;
        if (test) ++test->_changes;
      }
      environment:_pointer]);
}

- (void)tearDown {
  [_presenter invalidate];
  PCPictureInPicturePointAtControlInEnvironment(NO, _pointer);
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
  VideoPiPWindowTestsHover(_presenter, _pointer);
}

- (NSButton*)hoveredPlayButton {
  [_presenter setAction:PCVideoPiPPlayPause visible:YES];
  NSButton* play = VideoPiPWindowTestsButton(self.content, PCVideoPiPPlayPause);
  NSView* host = VideoPiPWindowTestsHost(play);
  host.wantsLayer = YES;
  if (!host.layer) host.layer = [CALayer layer];
  [self showHovering];
  return play;
}

@end
