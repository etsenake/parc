// Native HLS playback through AVPlayer, Safari's second FairPlay route
// (fairplay_chromium/NATIVE_HLS.md). Engine-independent like the rest of the
// core: plain C++ header, ObjC++ implementation over AVFoundation.
//
// AVFoundation never touches the network itself. The asset is created with
// client URL loading only, and every load it makes (playlists, segments,
// certificates) goes to the embedder's HlsLoader, which in Parc fetches
// through the page's loader in the render process. skd:// key requests go to
// the client instead (OnKeyRequest), for the CDM to answer, and clearkey://
// requests for the page's legacy clear key (WebKit's CDMSessionClearKey).
#pragma once

#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "fairplay_types.h"

namespace parc::fairplay {

struct HlsTimeRange {
  double start = 0;  // Seconds.
  double end = 0;
};

using HlsHeaders = std::vector<std::pair<std::string, std::string>>;

struct HlsLoadRequest {
  std::string url;
  std::string method = "GET";
  HlsHeaders headers;  // As AVFoundation set them (Range, X-Playback-Session-Id…).
};

struct HlsLoadResponse {
  int http_status = 200;
  std::string mime_type;       // The server's Content-Type, without parameters.
  int64_t content_length = -1;  // -1 when unknown.
  std::string final_url;       // After redirects. Empty means the request URL.
  HlsHeaders headers;
};

// One load's results, called on the player's owner sequence: OnResponse once,
// OnData any number of times, then OnComplete. Never called again after
// OnComplete or after the HlsLoad is destroyed.
class HlsLoadClient {
 public:
  virtual void OnResponse(const HlsLoadResponse& response) = 0;
  virtual void OnData(const uint8_t* data, size_t size) = 0;
  // 0 when the body is complete, otherwise a negative net error code
  // (net::ERR_*). A failure before OnResponse is a failed request.
  virtual void OnComplete(int net_error) = 0;

 protected:
  virtual ~HlsLoadClient() = default;
};

// A load in flight. Destroying it cancels the load.
class HlsLoad {
 public:
  virtual ~HlsLoad() = default;
};

// The embedder's network access. Called on the owner sequence.
class HlsLoader {
 public:
  virtual ~HlsLoader() = default;
  virtual std::unique_ptr<HlsLoad> StartLoad(const HlsLoadRequest& request,
                                             HlsLoadClient* client) = 0;
};

// How HTMLMediaElement reports a failure, mapped the way WebKit does.
enum class HlsError {
  kNetwork,       // MEDIA_ERR_NETWORK
  kDecode,        // MEDIA_ERR_DECODE
  kNotSupported,  // MEDIA_ERR_SRC_NOT_SUPPORTED (before metadata)
};

// The element's readyState as WebKit's AVFoundation player reports it
// (MediaPlayerPrivateAVFoundation::updateStates).
enum class HlsReadyState { kHaveMetadata, kHaveCurrentData, kHaveFutureData, kHaveEnoughData };

struct HlsMetadata {
  bool has_audio = false;
  bool has_video = false;
  int32_t natural_width = 0;
  int32_t natural_height = 0;
  // Media subtypes of the first audio and video format descriptions
  // ('avc1', 'hvc1', 'mp4a', 'ec-3', protected 'qavc'…), 0 when unknown.
  uint32_t video_fourcc = 0;
  uint32_t audio_fourcc = 0;
  // Seconds; +infinity for live (indefinite) streams. Duration, seekable
  // and start date follow WebKit's rules (fairplay_hls_timeline.h).
  double duration = 0;
  bool is_live = false;
  // getStartDate(): milliseconds since the epoch at media time 0, from
  // EXT-X-PROGRAM-DATE-TIME (AVPlayerItem.currentDate), a whole number of
  // seconds. nullopt without one.
  std::optional<double> start_date_ms;
  // The element's seekable attribute: one range or none.
  std::vector<HlsTimeRange> seekable;
  std::vector<HlsTimeRange> loaded;
};

// Callbacks, posted to the owner sequence, never run inside a call into the
// player.
class HlsPlayerClient {
 public:
  // Once, when the asset's metadata has loaded and it is playable, before
  // the item exists, as WebKit reports HAVE_METADATA: from the asset alone
  // (duration, the seekable window up to it, media types). The item's own
  // duration, seekable window, natural size and start date follow as
  // changes once it is ready to play. Errors before it are the asset's.
  virtual void OnMetadata(const HlsMetadata& metadata) = 0;
  // Enough is buffered to play on (playbackLikelyToKeepUp or a full buffer),
  // or not (an empty buffer while playing).
  virtual void OnBufferingStateChange(bool have_enough) = 0;
  // WebKit's readyState for the item changed (it is kHaveMetadata at
  // OnMetadata): kHaveCurrentData once the layer has the first video frame
  // (readyForDisplay) or the buffer is empty, kHaveFutureData once the item is
  // ready to play with media loaded past the current time (and, with video,
  // its first frame), kHaveEnoughData when playbackLikelyToKeepUp or the
  // buffer is full.
  virtual void OnReadyStateChange(HlsReadyState /*state*/) {}
  virtual void OnLoadedRangesChange(const std::vector<HlsTimeRange>& loaded) = 0;
  // The element's seekable attribute changed (one range or none).
  virtual void OnSeekableRangesChange(const std::vector<HlsTimeRange>& seekable) = 0;
  // The element's duration changed, so it fires durationchange.
  virtual void OnDurationChange(double seconds) = 0;  // +infinity for live.
  // What getStartDate() answers changed, as HlsMetadata::start_date_ms. Comes
  // only with a buffering state change, just before OnBufferingStateChange.
  virtual void OnStartDateChange(std::optional<double> start_date_ms) = 0;
  virtual void OnNaturalSizeChange(int32_t width, int32_t height) = 0;
  // The item's enabled tracks (hasEnabledAudio, hasEnabledVideo) differ from
  // the media types last reported (the metadata's, assumed when the variants
  // didn't say), once it is ready to play and whenever they change after:
  // WebKit's characteristicsChanged.
  virtual void OnMediaTypesChange(bool /*has_audio*/, bool /*has_video*/) {}
  // The item's time jumped (AVPlayerItemTimeJumpedNotification), playing or
  // paused, when AVPlayer also runs WebKit's periodic time observer.
  virtual void OnTimeJumped() {}
  virtual void OnEnded() = 0;
  virtual void OnError(HlsError error, const std::string& message) = 0;
  // AVFoundation asks for the key behind a clearkey:// URI, or an skd:// one
  // when no key request handler is installed (fairplay_hls_player_internal.h),
  // for every request, repeats of a URI included (each raises webkitneedkey,
  // as WebKit's keyNeeded). A clearkey:// URI whose key FulfillKeyRequests
  // already gave is answered without asking. The requests stay pending until
  // FulfillKeyRequests (clearkey) or FailKeyRequests names the URI.
  virtual void OnKeyRequest(const std::string& uri) = 0;
  // AVPlayer's outputObscuredDueToInsufficientExternalProtection changed
  // (WebKit reports it to the CDM, which marks keys output-restricted).
  virtual void OnOutputObscuredChange(bool /*obscured*/) {}
  // Video frames decoded and dropped since the previous call: deltas for
  // getVideoPlaybackQuality() (PipelineStatistics), from the player layer's
  // counts (fairplay_hls_frame_stats.h). They come every 250 ms while
  // playing and once more on stopping, from when the layer exists
  // (HlsPlayerLayer) on.
  virtual void OnVideoFrameCounts(uint32_t /*decoded*/, uint32_t /*dropped*/) {}

 protected:
  virtual ~HlsPlayerClient() = default;
};

// The key ID WebKit's player names a clearkey:// request by
// (MediaPlayerPrivateAVFoundationObjC::shouldWaitForLoadingOfResource): the
// URL's resource specifier, what follows "clearkey:". The legacy clear key
// session matches it against JWK "kid"s, and webkitneedkey carries it as UTF-8.
std::string HlsClearKeyId(const std::string& clearkey_uri);

class FairPlayHlsPlayer {
 public:
  // |client| and |loader| must outlive the player. Every public method runs
  // on one owner sequence; |post_task| reaches it from any thread.
  FairPlayHlsPlayer(HlsPlayerClient* client, HlsLoader* loader, PostTask post_task);
  ~FairPlayHlsPlayer();

  FairPlayHlsPlayer(const FairPlayHlsPlayer&) = delete;
  FairPlayHlsPlayer& operator=(const FairPlayHlsPlayer&) = delete;

  // Whether this macOS lets the asset load only through the client
  // (AVURLAssetUseClientURLLoadingExclusively and AVAssetResourceLoader's
  // URL session). Without it Load fails rather than let AVFoundation fetch.
  static bool IsSupported();

  // Starts loading |url| (http or https). |mime_type| is the element's
  // <source type>, or empty. OnMetadata or OnError follows. Same as
  // CreateAsset then Start.
  Result Load(const std::string& url, const std::string& mime_type);
  // The two halves of Load. CreateAsset makes the AVURLAsset and its loaders
  // without loading anything; what must exist before the AVPlayerItem (the
  // CDM's key loader for the asset) is set up between the two. Start loads
  // the asset's metadata; once it is playable the player makes the item and
  // player and reports OnMetadata, and the item goes on the player and starts
  // loading once the element prepares to play (PrepareToPlay, SetRate, Seek)
  // or at once for a live stream (WebKit's order, so the page has
  // HAVE_METADATA before any key request). A seek before the item is ready to
  // play waits for it.
  Result CreateAsset(const std::string& url, const std::string& mime_type);
  Result Start();

  // WebKit's ephemeral session (Page::usesEphemeralSession: Safari's private
  // browsing, an off-the-record profile here), before CreateAsset: the asset
  // then keeps no persistent cache and AVFoundation logs no URLs, as
  // WebKit's createAVAssetForURL asks.
  void SetEphemeralSession(bool ephemeral);

  // HTMLMediaElement::prepareToPlay: the element's preload is auto or the
  // page called load(). WebKit makes the item only then (or at HAVE_METADATA
  // for a live stream, or on play or seek, which SetRate and Seek do here);
  // until then the item made at OnMetadata stays off the player, so nothing
  // past the playlists loads and no key is asked for. Any time, also before
  // Start.
  void PrepareToPlay();

  // WebKit's initial video layer size: the element's size in points and the
  // display's scale, from the render process, before Start. The player's
  // layer then waits at that size in a CAContext of its own and has the
  // player before the item does, so AVFoundation picks the first HLS variant
  // for the element (fairplay_hls_player_layer.h). Without one (an element
  // not laid out yet), the layer takes the player at the compositor's size.
  void SetVideoLayerSize(double width, double height, double scale);

  // 0 pauses. AVPlayer waits to minimize stalling, as in Safari. Like
  // volume, mute and pitch, a rate set before Start applies when it starts.
  void SetRate(double rate);
  // Seeks exactly (zero tolerance). |done| runs on the owner sequence with
  // whether the seek finished (false when a later seek interrupted it).
  void Seek(double seconds, std::function<void(bool finished)> done);
  // As Seek(), landing up to |tolerance_before| seconds earlier (infinity:
  // anywhere earlier), never later, as WebKit's fastSeek asks AVFoundation
  // (MediaPlayerPrivateAVFoundationObjC::seekToTargetInternal). CurrentTime()
  // says where it landed.
  void Seek(double seconds,
            double tolerance_before,
            std::function<void(bool finished)> done);
  void SetVolume(float volume);
  void SetMuted(bool muted);
  // HTMLMediaElement.preservesPitch (default true): at rates other than 0 and
  // 1, true keeps pitch (Spectral), false lets it follow the rate
  // (Varispeed), WebKit's choice of audioTimePitchAlgorithm.
  void SetPreservesPitch(bool preserves_pitch);

  // The media time of the item's timebase. Callable from any thread.
  double CurrentTime() const;
  double Rate() const;

  // Answers the pending clearkey:// requests for |clearkey_uri| with the raw
  // key, as WebKit's fulfillRequestWithKeyData (the requested byte range of
  // it). Later requests for the URI are answered with the same key.
  void FulfillKeyRequests(const std::string& clearkey_uri, const std::vector<uint8_t>& key);
  // Fails the pending requests for |uri|. AVFoundation asks for the key
  // again (OnKeyRequest fires anew) rather than failing the item, so the
  // element keeps waiting for a key, as in Safari.
  void FailKeyRequests(const std::string& uri, const std::string& message);

  struct Status {
    int loads_started = 0;
    int loads_completed = 0;
    int loads_failed = 0;
    int loads_cancelled = 0;
    int64_t bytes_received = 0;
    int key_requests = 0;
  };
  Status GetStatus() const;

  class Impl;
  // For fairplay_hls_player_internal.h.
  Impl* impl() const { return impl_.get(); }

 private:
  std::shared_ptr<Impl> impl_;
};

}  // namespace parc::fairplay
