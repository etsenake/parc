// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //third_party/blink/public/platform/parc_web_media_player_extension.h.
// Parc's operations on a blink::WebMediaPlayer, reached through
// WebMediaPlayer::GetParcExtension(), which is null for a player without
// them. Kept out of web_media_player.h so that changing them rebuilds only
// what uses them.
#ifndef THIRD_PARTY_BLINK_PUBLIC_PLATFORM_PARC_WEB_MEDIA_PLAYER_EXTENSION_H_
#define THIRD_PARTY_BLINK_PUBLIC_PLATFORM_PARC_WEB_MEDIA_PLAYER_EXTENSION_H_

#include <limits>
#include <optional>
#include <string_view>
#include <vector>

#include "base/containers/span.h"
#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/scoped_refptr.h"
#include "third_party/blink/public/platform/web_common.h"
#include "third_party/blink/public/platform/web_media_player.h"

namespace media {
class MediaLog;
class RendererFactorySelector;
class SwitchableAudioRendererSink;
}  // namespace media

namespace blink {

class UrlIndex;
class WebLocalFrame;
class WebMediaPlayerDelegate;

class ParcWebMediaPlayerExtension {
 public:
  // Remote Playback's prompt for this element is waiting for its connection
  // (RemotePlayback::PromptInternal()). Its loads keep feeding the cast while
  // the page is frozen, as RequestMediaRemoting()'s do.
  virtual void ParcSetCastPrompted(bool prompted) {}

  // Instead of OnFrozen() when the back/forward cache freezes a
  // Safari-identity page. The paused player keeps its pipeline and position,
  // as WebKit's stopWithoutDestroyingMediaPlayer keeps its player.
  virtual void ParcOnFrozenInBackForwardCache() {}

  // Whether the page of a Safari-identity element is hidden, while that
  // element is on another page than the frame that made this player. The
  // player follows it instead of that frame's page, as WebKit's player follows
  // its element's document (HTMLMediaElement::visibilityStateChanged);
  // std::nullopt follows that frame's page again.
  virtual void ParcSetPageHidden(std::optional<bool> is_page_hidden) {}

  // What the frame a Safari-identity element took this player to gives it to
  // belong to that frame (MediaFactory::ParcAdoptMediaPlayer).
  struct BLINK_PLATFORM_EXPORT ParcFrameServices {
    ParcFrameServices();
    ParcFrameServices(ParcFrameServices&&);
    ~ParcFrameServices();

    raw_ptr<WebLocalFrame> frame = nullptr;
    raw_ptr<WebMediaPlayerDelegate> delegate = nullptr;
    raw_ptr<UrlIndex> url_index = nullptr;
    scoped_refptr<media::SwitchableAudioRendererSink> audio_sink;
    // Points what the player's renderer factories and media log take from
    // their frame at the new one.
    base::OnceCallback<void(media::RendererFactorySelector&)> move_factories;
    base::OnceCallback<void(media::MediaLog&)> move_media_log;
  };

  // Makes this player |services|'s frame's from now on, keeping its pipeline.
  // Returns false if it can't, leaving it as it is.
  virtual bool ParcMoveToFrame(ParcFrameServices services) { return false; }

  // Reports the player's state to its client again, after the client
  // registered it with the new frame's browser side.
  virtual void ParcReportStateToClient() {}

  // What HTMLMediaElement.getStartDate() answers on a Safari-identity page,
  // in milliseconds since the epoch, NaN for none. Safari's players other
  // than AVPlayer have no start date.
  virtual double ParcStartDate() const {
    return std::numeric_limits<double>::quiet_NaN();
  }

  // HTMLMediaElement.fastSeek on a Safari-identity page: a seek to |seconds|
  // that may land up to |tolerance_before| seconds earlier (+inf: anywhere
  // earlier), never later, as WebKit's seekWithTolerance does. A player that
  // can't land early seeks exactly, as a player without this extension does.
  virtual void ParcFastSeek(double seconds, double tolerance_before) = 0;

  // A legacy clear key (org.w3c.clearkey) the page's WebKitMediaKeys hold for
  // one of the player's clearkey:// key requests: |key_id| is WebKit's key ID
  // (the URL after "clearkey:"), |key| the raw key
  // (MediaPlayerPrivateAVFoundationObjC::keyAdded, fulfillRequestWithKeyData).
  // Only the native HLS player takes it.
  virtual void ParcProvideClearKey(std::string_view key_id,
                                   base::span<const uint8_t> key) {}

  // AirPlay, as WebKit's MediaPlayer::setWirelessPlaybackTarget and
  // setShouldPlayToPlaybackTarget: |output_context_id| names the browser's
  // route picker AVOutputContext (empty for none); the player plays to it
  // while |should_play|. Kept for the player the load makes. Only the native
  // HLS player plays to a target (ParcSupportsPlaybackTarget); WebKit's Media
  // Source player supports none either.
  virtual void ParcSetPlaybackTarget(std::string_view output_context_id,
                                     bool should_play) {}
  // x-webkit-airplay="deny" or disableRemotePlayback
  // (setWirelessVideoPlaybackDisabled).
  virtual void ParcSetWirelessVideoPlaybackDisabled(bool disabled) {}
  virtual bool ParcSupportsPlaybackTarget() const { return false; }

  // Every audio track a Safari-identity element has enabled, for a player
  // that plays them all, as Safari's Media Source does. Others play the
  // first, as a player without this extension does.
  virtual void ParcEnabledAudioTracksChanged(
      const std::vector<WebMediaPlayer::TrackId>& enabled_track_ids) = 0;

 protected:
  virtual ~ParcWebMediaPlayerExtension() = default;
};

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_PUBLIC_PLATFORM_PARC_WEB_MEDIA_PLAYER_EXTENSION_H_
