// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //media/base/parc_native_hls_demuxer_params.h.
#ifndef MEDIA_BASE_PARC_NATIVE_HLS_DEMUXER_PARAMS_H_
#define MEDIA_BASE_PARC_NATIVE_HLS_DEMUXER_PARAMS_H_

#include <memory>
#include <string>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/scoped_refptr.h"
#include "media/base/demuxer.h"
#include "media/base/media_export.h"
#include "ui/gfx/geometry/size_f.h"
#include "url/gurl.h"

namespace base {
class SequencedTaskRunner;
}

// The native HLS loader's types (media/mojo/mojom, which //media can't
// include), named here only.
namespace mojo {
template <typename S>
class StructPtr;
template <typename Interface>
class PendingReceiver;
template <typename Interface>
class PendingRemote;
}  // namespace mojo

namespace media::mojom {
class FairPlayHlsRequest;
class FairPlayHlsLoad;
class FairPlayHlsLoadClient;
}  // namespace media::mojom

namespace media {

class MediaLog;
class ParcInbandTrackForwarder;

// The element's readyState as Safari's native HLS player reports it
// (WebKit's MediaPlayerPrivateAVFoundation::updateStates).
enum class ParcNativeHlsReadyState {
  kHaveMetadata,
  kHaveCurrentData,
  kHaveFutureData,
  kHaveEnoughData,
};

// What the demuxer of Safari's native HLS route is made from
// (third_party/parc_fairplay NATIVE_HLS.md). DemuxerManager's HLS branch fills
// it; WebMediaPlayerImpl hands it to the factory registered for
// RendererType::kFairPlayHls.
struct MEDIA_EXPORT ParcNativeHlsDemuxerParams {
  ParcNativeHlsDemuxerParams();
  ParcNativeHlsDemuxerParams(ParcNativeHlsDemuxerParams&&);
  ParcNativeHlsDemuxerParams& operator=(ParcNativeHlsDemuxerParams&&);
  ~ParcNativeHlsDemuxerParams();

  // The playlist URL, after the redirects a sniffed load followed.
  GURL url;
  // The type AVFoundation is told (AVURLAssetOutOfBandMIMETypeKey). As in
  // WebKit, only a type not inferred from the URL's extension is passed:
  // HLS's when FFmpeg's sniffing found a playlist, empty for a ".m3u8" path.
  std::string mime_type;
  scoped_refptr<base::SequencedTaskRunner> media_task_runner;
  // Valid while the demuxer is made; the demuxer keeps its own clone.
  raw_ptr<MediaLog> media_log = nullptr;
  // Raises `encrypted` on the element; posts to the main thread.
  Demuxer::EncryptedMediaInitDataCB encrypted_media_init_data_cb;
  // The element's in-band audio and text tracks and cues; callable on the
  // media thread, posts to the main thread.
  std::unique_ptr<ParcInbandTrackForwarder> inband_tracks;
  // Raises webkitneedkey for a key request of the player's resource loader
  // (WebMediaPlayerEncryptedMediaClient::ParcWebKitKeyRequest), before any
  // `encrypted` for it; posts to the main thread.
  base::RepeatingCallback<void(const std::string& key_uri)> key_request_cb;
  // Serves one load AVFoundation makes (FairPlayHlsPlayerClient.StartLoad)
  // through the element's loader (blink::FairPlayHlsLoader); callable on the
  // media thread. Without it every load fails.
  using StartLoadCB = base::RepeatingCallback<void(
      mojo::StructPtr<mojom::FairPlayHlsRequest> request,
      mojo::PendingReceiver<mojom::FairPlayHlsLoad> load,
      mojo::PendingRemote<mojom::FairPlayHlsLoadClient> client)>;
  StartLoadCB start_load_cb;
  // The video element's size in points and its display's scale when the
  // demuxer is made (WebKit's initial video layer size); empty and 0 before
  // it has a layout box, and for an audio element.
  gfx::SizeF video_layer_size;
  float video_layer_scale = 0;
  // The player's readyState changes (WebMediaPlayerImpl raises the element to
  // HAVE_CURRENT_DATA and HAVE_FUTURE_DATA with them; HAVE_ENOUGH_DATA and
  // underflow come through buffering); posts to the main thread.
  base::RepeatingCallback<void(ParcNativeHlsReadyState)> ready_state_cb;
  // The player's media types changed after the metadata (WebKit's
  // characteristicsChanged); posts to the main thread.
  base::RepeatingCallback<void(bool has_audio, bool has_video)> media_types_cb;
  // The player's time went back outside a seek (WebKit's
  // MediaPlayerPrivateRemote::currentTimeChanged reverse jump); posts to the
  // main thread.
  base::RepeatingClosure time_jumped_cb;
  // AirPlay: the element's playback target when the demuxer is made
  // (WebMediaPlayer::ParcSetPlaybackTarget, NativeHlsSource::SetPlaybackTarget
  // after), and whether the element disables external playback.
  std::string playback_target_id;
  bool should_play_to_playback_target = false;
  bool wireless_video_playback_disabled = false;
  // Whether the player plays to the AirPlay device now; posts to the main
  // thread.
  base::RepeatingCallback<void(bool wireless)> wireless_cb;
  // The element prepares to play from the start (WebKit's prepareToPlay): its
  // effective preload is auto or the page called load().
  bool prepare_to_play = false;
};

}  // namespace media

#endif  // MEDIA_BASE_PARC_NATIVE_HLS_DEMUXER_PARAMS_H_
