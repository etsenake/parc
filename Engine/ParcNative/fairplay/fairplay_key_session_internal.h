// ObjC++-only access from FairPlayRenderer and FairPlayHlsKeyLoader to the key
// session.
#pragma once

#import <AVFoundation/AVFoundation.h>

#include <string>
#include <vector>

#include "fairplay_key_session.h"

namespace parc::fairplay {

// Makes |recipient| (an AVSampleBufferDisplayLayer or AVSampleBufferAudioRenderer)
// a content key recipient of the key system's AVContentKeySession, so it
// decrypts protected samples with the session's keys, matched by the key ID in
// each sample's format description. Must happen before the recipient processes
// media; a recipient belongs to one session for its lifetime. Owner sequence.
Result AttachContentKeyRecipient(FairPlayCdm::Impl* cdm, id<AVContentKeyRecipient> recipient);

// After this the recipient is inoperable (AVContentKeySession semantics).
void DetachContentKeyRecipient(FairPlayCdm::Impl* cdm, id<AVContentKeyRecipient> recipient);

// An HLS asset's key source (FairPlayHlsKeyLoader), as the key session sees it.
// Everything runs on the owner sequence; the key session calls these directly,
// never from inside a call the asset made into it.
class AssetKeyClient {
 public:
  virtual ~AssetKeyClient() = default;
  // Resource loader route: hands over the oldest skd loading request held for
  // |uri| (nil if none). The session then answers it, or fails it if it
  // can't (AVFoundation then asks for the key again): a loading request gives
  // one SPC only, so it can't pass to another session.
  virtual AVAssetResourceLoadingRequest* TakeLoadingRequest(const std::string& uri) = 0;
  // Content key session route: AVFoundation asked the session for the key
  // named |uri| and no EME session has asked for it; the request is parked
  // until a session generates a request with that URI.
  virtual void OnUnrequestedKey(const std::string& uri) = 0;
};

// Registers an asset with the key system. With |recipient|, the asset becomes
// a content key recipient of the session: AVFoundation asks the session for
// its keys, which must happen before its AVPlayerItem loads (an skd request
// already routed to the resource loader can't be satisfied once the asset is a
// recipient). Without, its keys are served from its resource loader requests.
Result AttachAsset(FairPlayCdm::Impl* cdm, AssetKeyClient* client, AVURLAsset* asset, bool recipient);

// Loading requests a session took from |client| and hasn't answered fail.
// A recipient asset is removed from the session and is inoperable afterwards.
void DetachAsset(FairPlayCdm::Impl* cdm, AssetKeyClient* client);

// Resource loader route: a new skd loading request. True if a session took it:
// one waiting for that URI (generateRequest came first), one whose key for it
// was already answered (AVFoundation asking again: a renewal), or one made for
// that URI before the asset was attached. False: the client holds it and
// reports the key as needed.
bool OfferLoadingRequest(FairPlayCdm::Impl* cdm,
                         AssetKeyClient* client,
                         const std::string& uri,
                         AVAssetResourceLoadingRequest* request);

// AVFoundation cancelled a loading request a session took.
void CancelLoadingRequest(FairPlayCdm::Impl* cdm,
                          AssetKeyClient* client,
                          AVAssetResourceLoadingRequest* request);

// AVPlayer's outputObscuredDueToInsufficientExternalProtection. While any
// attached client reports it, keys without their own protection status (those
// served through the resource loader, and every key before macOS 14.4) report
// output-restricted, as WebKit's CDMInstanceFairPlayStreamingAVFObjC does.
void SetAssetOutputObscured(FairPlayCdm::Impl* cdm, AssetKeyClient* client, bool obscured);

}  // namespace parc::fairplay
