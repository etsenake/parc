#ifndef MEDIA_BASE_PARC_NATIVE_HLS_DEMUXER_PARAMS_H_
#define MEDIA_BASE_PARC_NATIVE_HLS_DEMUXER_PARAMS_H_

#include <stdint.h>

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/scoped_refptr.h"
#include "build/build_config.h"
#include "media/base/demuxer.h"
#include "media/base/media_export.h"
#include "media/base/parc_native_hls_source.h"
#include "ui/gfx/geometry/size_f.h"
#include "url/gurl.h"

namespace base {
class SequencedTaskRunner;
}

namespace mojo {
template <typename S>
class StructPtr;
template <typename Interface>
class PendingReceiver;
template <typename Interface>
class PendingRemote;
}

namespace media::mojom {
class FairPlayHlsRequest;
class FairPlayHlsLoad;
class FairPlayHlsLoadClient;
}

namespace media {
class MediaLog;
class ParcInbandTrackForwarder;

enum class ParcNativeHlsReadyState {
  kHaveMetadata,
  kHaveCurrentData,
  kHaveFutureData,
  kHaveEnoughData,
};

struct MEDIA_EXPORT ParcNativeHlsDemuxerParams {
  ParcNativeHlsDemuxerParams();
  ParcNativeHlsDemuxerParams(ParcNativeHlsDemuxerParams&&);
  ParcNativeHlsDemuxerParams& operator=(ParcNativeHlsDemuxerParams&&);
  ~ParcNativeHlsDemuxerParams();

  GURL url;
  std::string mime_type;
  scoped_refptr<base::SequencedTaskRunner> media_task_runner;
  raw_ptr<MediaLog> media_log = nullptr;
  Demuxer::EncryptedMediaInitDataCB encrypted_media_init_data_cb;
  std::unique_ptr<ParcInbandTrackForwarder> inband_tracks;
  base::RepeatingCallback<void(const std::string& key_uri)> key_request_cb;
  using StartLoadCB = base::RepeatingCallback<void(
      mojo::StructPtr<mojom::FairPlayHlsRequest> request,
      mojo::PendingReceiver<mojom::FairPlayHlsLoad> load,
      mojo::PendingRemote<mojom::FairPlayHlsLoadClient> client)>;
  StartLoadCB start_load_cb;
  gfx::SizeF video_layer_size;
  float video_layer_scale = 0;
  base::RepeatingCallback<void(ParcNativeHlsReadyState)> ready_state_cb;
  base::RepeatingCallback<void(bool has_audio, bool has_video)> media_types_cb;
  base::RepeatingClosure time_jumped_cb;
  std::string playback_target_id;
  bool should_play_to_playback_target = false;
  bool wireless_video_playback_disabled = false;
  base::RepeatingCallback<void(bool wireless)> wireless_cb;
  bool prepare_to_play = false;
};

MEDIA_EXPORT std::string ParcHlsDataUrlMimeType(const GURL& url);

MEDIA_EXPORT std::optional<parc::fairplay::NativeHlsSource::Timeline>
ParcNativeHlsTimeline(Demuxer* demuxer);

#if BUILDFLAG(IS_MAC)
MEDIA_EXPORT void ParcPostNativeHlsClearKey(Demuxer* demuxer,
                                            base::SequencedTaskRunner& runner,
                                            std::string key_id,
                                            std::vector<uint8_t> key);
MEDIA_EXPORT void ParcPostNativeHlsPlaybackTarget(
    Demuxer* demuxer,
    base::SequencedTaskRunner& runner,
    std::string output_context_id,
    bool should_play);
MEDIA_EXPORT void ParcPostNativeHlsWirelessVideoPlaybackDisabled(
    Demuxer* demuxer,
    base::SequencedTaskRunner& runner,
    bool disabled);
MEDIA_EXPORT void ParcPostNativeHlsFileTracks(
    Demuxer* demuxer,
    base::SequencedTaskRunner& runner,
    parc::fairplay::NativeHlsSource::FileTracks tracks);
#endif

}

#endif
