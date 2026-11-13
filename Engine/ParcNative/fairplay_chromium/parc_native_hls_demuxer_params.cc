#include "media/base/parc_native_hls_demuxer_params.h"

#include <string_view>
#include <utility>

#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/raw_ptr.h"
#include "base/strings/string_util.h"
#include "base/task/sequenced_task_runner.h"
#include "build/build_config.h"
#include "media/base/parc_inband_tracks.h"
#include "media/media_buildflags.h"
#include "net/base/data_url.h"

namespace media {

#if BUILDFLAG(IS_MAC)
ParcNativeHlsDemuxerParams::ParcNativeHlsDemuxerParams() = default;
ParcNativeHlsDemuxerParams::ParcNativeHlsDemuxerParams(
    ParcNativeHlsDemuxerParams&&) = default;
ParcNativeHlsDemuxerParams& ParcNativeHlsDemuxerParams::operator=(
    ParcNativeHlsDemuxerParams&&) = default;
ParcNativeHlsDemuxerParams::~ParcNativeHlsDemuxerParams() = default;
#endif

std::string ParcHlsDataUrlMimeType(const GURL& url) {
#if BUILDFLAG(ENABLE_HLS_DEMUXER)
  std::string mime_type;
  std::string charset;
  if (!net::DataURL::Parse(url, &mime_type, &charset, /*data=*/nullptr)) {
    return std::string();
  }
  std::string_view type = base::TrimWhitespaceASCII(
      std::string_view(mime_type).substr(0, mime_type.find(';')),
      base::TRIM_ALL);
  for (std::string_view hls :
       {"application/vnd.apple.mpegurl", "application/x-mpegurl",
        "audio/mpegurl", "audio/x-mpegurl"}) {
    if (type == hls) {
      return std::string(type);
    }
  }
#endif
  return std::string();
}

std::optional<parc::fairplay::NativeHlsSource::Timeline> ParcNativeHlsTimeline(
    Demuxer* demuxer) {
#if BUILDFLAG(IS_MAC)
  if (demuxer && demuxer->GetParcNativeHlsSource()) {
    return demuxer->GetParcNativeHlsSource()->GetTimeline();
  }
#endif
  return std::nullopt;
}

#if BUILDFLAG(IS_MAC)
void ParcPostNativeHlsClearKey(Demuxer* demuxer,
                               base::SequencedTaskRunner& runner,
                               std::string key_id,
                               std::vector<uint8_t> key) {
  if (!demuxer || !demuxer->GetParcNativeHlsSource()) {
    return;
  }
  runner.PostTask(
      FROM_HERE,
      base::BindOnce(&parc::fairplay::NativeHlsSource::ProvideClearKey,
                     base::Unretained(demuxer->GetParcNativeHlsSource()),
                     std::move(key_id), std::move(key)));
}

void ParcPostNativeHlsPlaybackTarget(Demuxer* demuxer,
                                     base::SequencedTaskRunner& runner,
                                     std::string output_context_id,
                                     bool should_play) {
  if (!demuxer || !demuxer->GetParcNativeHlsSource()) {
    return;
  }
  runner.PostTask(
      FROM_HERE,
      base::BindOnce(&parc::fairplay::NativeHlsSource::SetPlaybackTarget,
                     base::Unretained(demuxer->GetParcNativeHlsSource()),
                     std::move(output_context_id), should_play));
}

void ParcPostNativeHlsWirelessVideoPlaybackDisabled(
    Demuxer* demuxer,
    base::SequencedTaskRunner& runner,
    bool disabled) {
  if (!demuxer || !demuxer->GetParcNativeHlsSource()) {
    return;
  }
  runner.PostTask(
      FROM_HERE,
      base::BindOnce(
          &parc::fairplay::NativeHlsSource::SetWirelessVideoPlaybackDisabled,
          base::Unretained(demuxer->GetParcNativeHlsSource()), disabled));
}

void ParcPostNativeHlsFileTracks(
    Demuxer* demuxer,
    base::SequencedTaskRunner& runner,
    parc::fairplay::NativeHlsSource::FileTracks tracks) {
  if (!demuxer || !demuxer->GetParcNativeHlsSource()) {
    return;
  }
  runner.PostTask(
      FROM_HERE,
      base::BindOnce(&parc::fairplay::NativeHlsSource::SelectFileTracks,
                     base::Unretained(demuxer->GetParcNativeHlsSource()),
                     std::move(tracks)));
}
#endif

}
