// ObjC++-only access to the HLS player's AVFoundation objects, for the CDM
// (the asset joins its AVContentKeySession) and the display (the player
// layer goes into ui::ProtectedLayerRegistry). Owner sequence.
#pragma once

#import <AVFoundation/AVFoundation.h>

#include "fairplay_hls_player.h"

namespace parc::fairplay {

// The asset, nil before CreateAsset. The CDM's key loader for it
// (FairPlayHlsKeyLoader) answers its skd resource loader requests; it never
// becomes a content key recipient.
AVURLAsset* HlsPlayerAsset(FairPlayHlsPlayer::Impl* player);

// The AVPlayer and its item, nil until the asset's metadata loaded (they are
// made just before OnMetadata; the item goes on the player just after it).
AVPlayer* HlsPlayerAVPlayer(FairPlayHlsPlayer::Impl* player);
AVPlayerItem* HlsPlayerItem(FairPlayHlsPlayer::Impl* player);

// One AVPlayerLayer showing the player, made on first use (in an explicit
// CATransaction: the owner sequence has no run loop). nil before the player.
// Shutdown detaches it from the player.
AVPlayerLayer* HlsPlayerLayer(FairPlayHlsPlayer::Impl* player);

// Takes the asset's skd:// loading requests: the CDM's key loader for the
// asset (FairPlayHlsKeyLoader), which answers them itself. Called on the
// owner sequence.
class HlsKeyRequestHandler {
 public:
  virtual void HandleLoadingRequest(AVAssetResourceLoadingRequest* request) = 0;
  virtual void HandleCancelledLoadingRequest(AVAssetResourceLoadingRequest* request) = 0;

 protected:
  virtual ~HlsKeyRequestHandler() = default;
};

// Hands every skd:// loading request and its cancellation to |handler|
// instead of HlsPlayerClient::OnKeyRequest. Install it between CreateAsset and
// Start, since the key loader must exist before the item routes any request;
// null removes it. The player never calls it after shutdown; |handler| must
// otherwise outlive the player or be removed first.
void SetHlsKeyRequestHandler(FairPlayHlsPlayer::Impl* player, HlsKeyRequestHandler* handler);

// For the harness: delivers a KVO notification for the item's |key_path| to
// the player's observer as AVFoundation would, on the calling thread, with
// |new_value| (and as the prior notification when |prior|). Nothing once the
// item doesn't exist or the player shut down.
void HlsPlayerDeliverItemChangeForTesting(FairPlayHlsPlayer::Impl* player,
                                          NSString* key_path,
                                          id new_value,
                                          bool prior);

}  // namespace parc::fairplay
