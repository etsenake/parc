// The native HLS player's AVPlayerLayer (fairplay_chromium/NATIVE_HLS.md).
//
// WebKit gives its AVPlayerLayer the element's size and the page's contents
// scale, in a CAContext of its own (LayerHostingContext), before it gives it
// the player, and does that in the same turn as it makes the AVPlayerItem
// (MediaPlayerPrivateAVFoundationObjC::createAVPlayerLayer, then
// updateLayerAttachment). AVFoundation picks the item's first HLS variant for
// the layer's size on screen only then: a layer that is unsized, or sized but
// in no context, when the item arrives leaves it at the variant its bandwidth
// estimate starts with (1080p for a 640x360 pt element on a 2x display after
// earlier playback, tests/FairPlay/hls_presentation). So the layer waits for
// a size before it takes its player: the render process's size for the
// element (parcStageWithSize:scale:) or, without one, the compositor's when
// it first draws the layer (FillProtectedLayer sets the contents scale, then
// the bounds).
//
// Objective-C++ only.
#pragma once

#import <AVFoundation/AVFoundation.h>

@interface PCHlsPlayerLayer : AVPlayerLayer
// The player to attach once the layer has a size, at once if it has one.
// Any thread.
- (void)parcAttachPlayerWhenSized:(AVPlayer*)player;
// Puts the layer at |size| (points) and |scale| in a CAContext of its own,
// hosted nowhere, as WebKit's LayerHostingContext holds its layer, which
// hands it a waiting player. The compositor's tree takes it from there when
// it draws it. Call before the player gets its item.
- (void)parcStageWithSize:(CGSize)size scale:(CGFloat)scale;
// Lets go of the player, attached or still waiting, and of the staging
// context. Any thread.
- (void)parcDetachPlayer;
@end
