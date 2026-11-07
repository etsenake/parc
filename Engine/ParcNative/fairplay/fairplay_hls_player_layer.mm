#import "fairplay_hls_player_layer.h"

#import <QuartzCore/QuartzCore.h>

#include <cstdint>

// QuartzCore's window server contexts (as ui/base/cocoa/remote_layer_api.h
// declares them for the GPU process's own layer trees).
@interface CAContext : NSObject
+ (instancetype)contextWithCGSConnection:(uint32_t)connection options:(NSDictionary*)options;
@property(retain) CALayer* layer;
@end
extern "C" uint32_t CGSMainConnectionID(void);

@implementation PCHlsPlayerLayer {
  // Guarded by @synchronized(self): the player's thread sets them, the
  // compositor's thread sizes the layer.
  AVPlayer* _pendingPlayer;
  CAContext* _stagingContext;
  CALayer* _stagingRoot;
}

- (void)parcAttachPlayerWhenSized:(AVPlayer*)player {
  @synchronized(self) {
    _pendingPlayer = player;
    [self parcAttachPendingPlayerIfSized:self.bounds];
  }
}

- (void)parcStageWithSize:(CGSize)size scale:(CGFloat)scale {
  if (!(size.width > 0) || !(size.height > 0) || !(scale > 0)) {
    return;
  }
  @synchronized(self) {
    if (_stagingContext || self.superlayer) {
      return;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _stagingRoot = [CALayer layer];
    _stagingRoot.anchorPoint = CGPointZero;
    _stagingRoot.bounds = CGRectMake(0, 0, size.width, size.height);
    _stagingContext = [CAContext contextWithCGSConnection:CGSMainConnectionID() options:@{}];
    _stagingContext.layer = _stagingRoot;
    self.contentsScale = scale;
    self.anchorPoint = CGPointZero;
    self.position = CGPointZero;
    [_stagingRoot addSublayer:self];
    [CATransaction commit];
  }
  // Outside the lock: setBounds: takes it to hand over the waiting player.
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.bounds = CGRectMake(0, 0, size.width, size.height);
  [CATransaction commit];
}

- (void)parcDetachPlayer {
  @synchronized(self) {
    _pendingPlayer = nil;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.player = nil;
    if (_stagingRoot && self.superlayer == _stagingRoot) {
      [self removeFromSuperlayer];
    }
    _stagingContext.layer = nil;
    _stagingContext = nil;
    _stagingRoot = nil;
    [CATransaction commit];
  }
}

- (void)setBounds:(CGRect)bounds {
  [super setBounds:bounds];
  @synchronized(self) {
    [self parcAttachPendingPlayerIfSized:bounds];
  }
}

- (void)parcAttachPendingPlayerIfSized:(CGRect)bounds {
  if (!_pendingPlayer || CGRectIsEmpty(bounds)) {
    return;
  }
  AVPlayer* player = _pendingPlayer;
  _pendingPlayer = nil;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.player = player;
  [CATransaction commit];
}

@end
