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

// For the harness: names every later SPC |content_identifier| instead of the
// request's own. Axinom's license service wants a key GUID there, where an
// mpts request's SPC is named "TransportStreamIdentifier" as in WebKit.
void SetSpcContentIdentifierForTesting(FairPlayCdm::Impl* cdm, std::vector<uint8_t> content_identifier);

// An HLS asset's key source (FairPlayHlsKeyLoader), as the key session sees it:
// the asset's skd resource loader requests, each answered with a CKC from its
// own SPC. Everything runs on the owner sequence; the key session calls it
// directly, never from inside a call the asset made into it.
class AssetKeyClient {
 public:
  virtual ~AssetKeyClient() = default;
  // Hands over the oldest skd loading request held for |uri| (nil if none).
  // The session then answers it, or fails it if it can't (AVFoundation then
  // asks for the key again): a loading request gives one SPC only, so it
  // can't pass to another session.
  virtual AVAssetResourceLoadingRequest* TakeLoadingRequest(const std::string& uri) = 0;
};

// Registers an asset with the key system. skd sessions are then named by
// their URI and take the asset's loading requests.
Result AttachAsset(FairPlayCdm::Impl* cdm, AssetKeyClient* client, AVURLAsset* asset);

// Loading requests a session took from |client| and hasn't answered fail.
void DetachAsset(FairPlayCdm::Impl* cdm, AssetKeyClient* client);

// A new skd loading request. True if a session took it: one waiting for that
// URI (generateRequest came first), one whose key for it was already answered
// (AVFoundation asking again: a renewal), one whose earlier request
// AVFoundation cancelled (a new license request), or one made for that URI
// before the asset was attached. False: the client holds it and reports the
// key as needed.
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
// served through loading requests, and every key before macOS 14.4) report
// output-restricted, as WebKit's CDMInstanceFairPlayStreamingAVFObjC does.
void SetAssetOutputObscured(FairPlayCdm::Impl* cdm, AssetKeyClient* client, bool obscured);

}  // namespace parc::fairplay
