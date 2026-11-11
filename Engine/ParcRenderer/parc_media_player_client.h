// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //third_party/blink/renderer/platform/media/parc_media_player_client.h.
// Parc's side of a blink::MediaPlayerClient (the media element), which the
// player reaches through MediaPlayerClient::ParcClient(), null for a client
// without it. Kept out of media_player_client.h so that changing it rebuilds
// only what uses it.
#ifndef THIRD_PARTY_BLINK_RENDERER_PLATFORM_MEDIA_PARC_MEDIA_PLAYER_CLIENT_H_
#define THIRD_PARTY_BLINK_RENDERER_PLATFORM_MEDIA_PARC_MEDIA_PLAYER_CLIENT_H_

#include <stdint.h>

#include <string_view>

#include "base/containers/span.h"
#include "media/base/parc_inband_tracks.h"
#include "third_party/blink/renderer/platform/media/media_player_client.h"
#include "ui/gfx/geometry/size_f.h"

namespace media {
enum class MediaContentType;
}  // namespace media

namespace blink {

// The in-band track calls of Safari's native HLS route come here too
// (media::ParcInbandTrackSink).
class ParcMediaPlayerClient : public media::ParcInbandTrackSink {
 public:
  // Whether the element's document presents Safari's identity
  // (third_party/blink/renderer/core/frame/parc_safari_identity.h), for what
  // the player offers only there.
  virtual bool PresentsParcSafariIdentity() const { return false; }

  // The video element's size in points and its display's scale, for the
  // native HLS player's layer (WebKit's initial video layer size). Leaves both
  // alone when there's none (an audio element, no layout box yet).
  virtual void ParcVideoLayerSize(gfx::SizeF* /*size*/,
                                  float* /*scale*/) const {}

  // Whether the element prepares Safari's native HLS player to play from the
  // start (WebKit's HTMLMediaElement::prepareToPlay and preload).
  virtual bool ParcPreparesToPlay() const { return false; }

  // The player's time moved outside a seek, other than by playing on
  // (WebKit's MediaPlayerClient::mediaPlayerTimeChanged from
  // MediaPlayerPrivateRemote::currentTimeChanged).
  virtual void ParcPlayerTimeChanged() {}

  // Whether the player plays to the AirPlay device now (WebKit's
  // MediaPlayerClient::mediaPlayerCurrentPlaybackTargetIsWirelessChanged).
  virtual void ParcPlaybackTargetIsWirelessChanged(bool wireless) {}

  // The media metadata the player last reported, for the browser alone,
  // after the client registered the player again with another frame.
  virtual void ParcReportMediaMetadata(
      bool has_audio,
      bool has_video,
      media::MediaContentType media_content_type) {}

  // WebKit's legacy key-needed signal, HTMLMediaElement::mediaPlayerKeyNeeded.
  // On a Safari-identity page the media element queues webkitneedkey;
  // elsewhere these do nothing.
  // A Safari-identity Media Source's sinf ({"sinf":[base64]}) for a protected
  // track, raised for every one before `encrypted` is decided on, whether or
  // not it follows (SourceBufferPrivateAVFObjC::
  // didProvideContentKeyRequestInitializationDataForTrackID calls keyNeeded
  // before the renderer's setInitData).
  virtual void ParcWebKitMediaSourceKeyNeeded(base::span<const uint8_t> sinf) {}
  // A key request of the native HLS player's resource loader: every skd://
  // and clearkey:// loading request it sees, whether or not a CDM is
  // attached, before any `encrypted` for it, with the request URL's absolute
  // string unchanged, as UTF-8 (MediaPlayerPrivateAVFoundationObjC::
  // shouldWaitForLoadingOfResource; Engine/ParcNative/fairplay_chromium/
  // NATIVE_HLS.md, "Keys").
  virtual void ParcWebKitKeyRequest(std::string_view key_uri) {}

 protected:
  virtual ~ParcMediaPlayerClient() = default;
};

// `client`'s answer, false for a client without Parc's side.
inline bool ClientPresentsParcSafariIdentity(MediaPlayerClient& client) {
  ParcMediaPlayerClient* parc = client.ParcClient();
  return parc && parc->PresentsParcSafariIdentity();
}

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_PLATFORM_MEDIA_PARC_MEDIA_PLAYER_CLIENT_H_
