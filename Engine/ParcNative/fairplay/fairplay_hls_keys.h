// FairPlay keys for the native HLS player's AVURLAsset: Safari's native HLS
// route (WebKit's MediaPlayerPrivateAVFoundationObjC with
// CDMInstanceFairPlayStreamingAVFObjC and CDMSessionAVFoundationObjC). ObjC++
// only.
//
// AVFoundation meets EXT-X-KEY:METHOD=SAMPLE-AES,
// KEYFORMAT="com.apple.streamingkeydelivery",URI="skd://..." and asks for the
// key through the asset's AVAssetResourceLoader, as in Safari, where every
// such request raises webkitneedkey and, when no session asked for the key,
// encrypted. WebKit makes the asset a content key recipient only once a key
// exists; Parc never does, and answers each loading request with a CKC from
// its own SPC (WebKit's legacy CDMSessionAVFoundationObjC), whatever order the
// page attaches MediaKeys (setMediaKeys) and licenses keys in. Legacy
// WebKitMediaKeys sessions are WebKit's: one made before the keys are
// attached to the element (webkitSetMediaKeys) has no player behind it
// (CDMPrivateMediaPlayer::createSession returns none) and never answers, even
// once the keys are attached (parc_webkit_media_keys.h). Legacy pages attach
// at loadedmetadata and make the session at webkitneedkey, which works
// because the player reports HAVE_METADATA from the asset before its item
// exists, so no key request comes first (FairPlayHlsPlayer::Start). Proven
// against Axinom's FairPlay HLS vectors (tests/FairPlay/README.md, "HLS
// assets"):
// - An skd loading request gives one SPC, and only while the asset is no
//   recipient. Finished for the session before the session holds a usable key
//   for its URI it never plays, even after the key arrives, and once the asset
//   is a recipient a held request's URI can't be requested through the session
//   either, so WebKit's late attach stalls a key requested before an earlier
//   one was licensed (two keys held at once).
// - A recipient asset sends no skd request to its resource loader, so it would
//   raise no webkitneedkey, which legacy pages wait for.
#pragma once

#import <AVFoundation/AVFoundation.h>

#include <memory>
#include <string>

#include "fairplay_hls_player_internal.h"
#include "fairplay_key_session.h"
#include "fairplay_types.h"

namespace parc::fairplay {

class FairPlayHlsKeyLoaderClient {
 public:
  virtual ~FairPlayHlsKeyLoaderClient() = default;
  // AVFoundation needs the key named |uri| (the EXT-X-KEY skd URI) and no EME
  // session of the attached CDM has asked for it (or none is attached). The
  // media element raises `encrypted` with initDataType "skd" and the URI's
  // UTF-8 bytes as init data, and `waitingforkey`. The page's
  // generateRequest("skd", uri) then answers it. Called again for a URI when
  // a further request for it is still held once a session took the earlier
  // one (each takes its own session) or AVFoundation cancelled it, or after
  // the earlier one failed and AVFoundation asked again. A need a session met
  // before delivery isn't reported.
  virtual void OnKeyNeeded(const std::string& uri) = 0;
  // Every skd loading request the player hands the loader, before anything
  // else it raises, whether or not a CDM is attached and including repeats of
  // a URI: |url| is the request URL's absoluteString. Legacy pages hear it as
  // `webkitneedkey` (WebKit's keyNeeded in shouldWaitForLoadingOfResource).
  virtual void OnKeyLoadingRequest(const std::string& url) = 0;
};

// One per FairPlayHlsPlayer asset, on the CDM's and player's owner sequence:
// every method is called there, and client callbacks are posted to it through
// |post_task|, never run inside a call into the loader or the CDM.
//
// Wiring (fairplay_chromium/NATIVE_HLS.md, "Keys"): FairPlayHlsPlayer::
// CreateAsset, then this loader for HlsPlayerAsset(...) with the element's CDM
// if it has one, SetHlsKeyRequestHandler(player, &loader), then Start. The
// player hands it every skd loading request; remove it (or destroy the
// player) before destroying the loader.
class FairPlayHlsKeyLoader : public HlsKeyRequestHandler {
 public:
  // |cdm| is the element's MediaKeys if it has them already, or null. The
  // loader keeps only a weak reference. |client| must outlive the loader.
  FairPlayHlsKeyLoader(AVURLAsset* asset,
                       FairPlayCdm* cdm,
                       FairPlayHlsKeyLoaderClient* client,
                       PostTask post_task);
  ~FairPlayHlsKeyLoader() override;
  FairPlayHlsKeyLoader(const FairPlayHlsKeyLoader&) = delete;
  FairPlayHlsKeyLoader& operator=(const FairPlayHlsKeyLoader&) = delete;

  // setMediaKeys: attaches, replaces or (null) detaches the CDM that answers
  // the held requests. Requests a detached CDM took and hadn't answered fail,
  // and AVFoundation asks again. If the new CDM can't take the asset, the old
  // one stays and the result says why (the page's setMediaKeys rejects).
  Result SetCdm(FairPlayCdm* cdm);

  // AVPlayer's outputObscuredDueToInsufficientExternalProtection
  // (HlsPlayerClient::OnOutputObscuredChange): the keys report
  // output-restricted while true, WebKit's fallback when a key has no
  // protection status of its own.
  void SetOutputObscured(bool obscured);

  // HlsKeyRequestHandler, from the player: skd loading requests and their
  // cancellations.
  void HandleLoadingRequest(AVAssetResourceLoadingRequest* request) override;
  void HandleCancelledLoadingRequest(AVAssetResourceLoadingRequest* request) override;

  class Impl;

 private:
  std::shared_ptr<Impl> impl_;
};

}  // namespace parc::fairplay
