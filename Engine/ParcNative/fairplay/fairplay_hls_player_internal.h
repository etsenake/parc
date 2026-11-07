// ObjC++-only access to the HLS player's AVFoundation objects, for the CDM
// (the asset joins its AVContentKeySession) and the display (the player
// layer goes into ui::ProtectedLayerRegistry). Owner sequence.
#pragma once

#import <AVFoundation/AVFoundation.h>

#include "fairplay_hls_player.h"

namespace parc::fairplay {

// The asset, nil before Load. A content key recipient
// (addContentKeyRecipient:) like the MSE renderer's layer and audio renderer.
AVURLAsset* HlsPlayerAsset(FairPlayHlsPlayer::Impl* player);

// The AVPlayer, nil before Load.
AVPlayer* HlsPlayerAVPlayer(FairPlayHlsPlayer::Impl* player);

// One AVPlayerLayer showing the player, made on first use (in an explicit
// CATransaction: the owner sequence has no run loop). nil before Load.
// Shutdown detaches it from the player.
AVPlayerLayer* HlsPlayerLayer(FairPlayHlsPlayer::Impl* player);

}  // namespace parc::fairplay
