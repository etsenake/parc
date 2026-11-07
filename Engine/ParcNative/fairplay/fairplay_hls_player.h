// Native HLS playback through AVPlayer, Safari's second FairPlay route
// (fairplay_chromium/NATIVE_HLS.md). Engine-independent like the rest of the
// core: plain C++ header, ObjC++ implementation over AVFoundation.
//
// AVFoundation never touches the network itself. The asset is created with
// client URL loading only, and every load it makes (playlists, segments,
// certificates) goes to the embedder's HlsLoader, which in Parc fetches
// through the page's loader in the render process. skd:// key requests go to
// the client instead (OnKeyRequest), for the CDM to answer.
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

struct HlsMetadata {
  bool has_audio = false;
  bool has_video = false;
  int32_t natural_width = 0;
  int32_t natural_height = 0;
  // Media subtypes of the first audio and video format descriptions
  // ('avc1', 'hvc1', 'mp4a', 'ec-3', protected 'qavc'…), 0 when unknown.
  uint32_t video_fourcc = 0;
  uint32_t audio_fourcc = 0;
  double duration = 0;  // Seconds; +infinity for live (indefinite) streams.
  bool is_live = false;
  // getStartDate(): milliseconds since the epoch at media time 0, from
  // EXT-X-PROGRAM-DATE-TIME (AVPlayerItem.currentDate). nullopt without one.
  std::optional<double> start_date_ms;
  std::vector<HlsTimeRange> seekable;
  std::vector<HlsTimeRange> loaded;
};

// Callbacks, posted to the owner sequence, never run inside a call into the
// player.
class HlsPlayerClient {
 public:
  // Once, when the item is ready to play.
  virtual void OnMetadata(const HlsMetadata& metadata) = 0;
  // Enough is buffered to play on (playbackLikelyToKeepUp or a full buffer),
  // or not (an empty buffer while playing).
  virtual void OnBufferingStateChange(bool have_enough) = 0;
  virtual void OnLoadedRangesChange(const std::vector<HlsTimeRange>& loaded) = 0;
  virtual void OnSeekableRangesChange(const std::vector<HlsTimeRange>& seekable) = 0;
  virtual void OnDurationChange(double seconds) = 0;  // +infinity for live.
  virtual void OnNaturalSizeChange(int32_t width, int32_t height) = 0;
  virtual void OnEnded() = 0;
  virtual void OnError(HlsError error, const std::string& message) = 0;
  // AVFoundation asks for the key behind an skd:// URI. The request stays
  // pending until CompleteKeyRequests or FailKeyRequests names the URI.
  virtual void OnKeyRequest(const std::string& skd_uri) = 0;

 protected:
  virtual ~HlsPlayerClient() = default;
};

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
  // <source type>, or empty. OnMetadata or OnError follows.
  Result Load(const std::string& url, const std::string& mime_type);

  // 0 pauses. AVPlayer waits to minimize stalling, as in Safari.
  void SetRate(double rate);
  // Seeks exactly (zero tolerance). |done| runs on the owner sequence with
  // whether the seek finished (false when a later seek interrupted it).
  void Seek(double seconds, std::function<void(bool finished)> done);
  void SetVolume(float volume);
  void SetMuted(bool muted);

  // The media time of the item's timebase. Callable from any thread.
  double CurrentTime() const;
  double Rate() const;

  // Finishes the pending skd:// requests for |skd_uri| so AVFoundation takes
  // the key from the AVContentKeySession the asset is a recipient of
  // (AVStreamingKeyDeliveryContentKeyType, as WebKit does). Empty finishes
  // every pending request. Later requests for a completed URI finish at once.
  void CompleteKeyRequests(const std::string& skd_uri);
  // Fails the pending requests for |skd_uri|. AVFoundation asks for the key
  // again (OnKeyRequest fires anew) rather than failing the item, so the
  // element keeps waiting for a key, as in Safari.
  void FailKeyRequests(const std::string& skd_uri, const std::string& message);

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
