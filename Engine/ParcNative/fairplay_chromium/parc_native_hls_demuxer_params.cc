#include "media/base/parc_native_hls_demuxer_params.h"

#include "base/task/sequenced_task_runner.h"
#include "build/build_config.h"
#include "media/base/parc_inband_tracks.h"

namespace media {

#if BUILDFLAG(IS_MAC)
ParcNativeHlsDemuxerParams::ParcNativeHlsDemuxerParams() = default;
ParcNativeHlsDemuxerParams::ParcNativeHlsDemuxerParams(
    ParcNativeHlsDemuxerParams&&) = default;
ParcNativeHlsDemuxerParams& ParcNativeHlsDemuxerParams::operator=(
    ParcNativeHlsDemuxerParams&&) = default;
ParcNativeHlsDemuxerParams::~ParcNativeHlsDemuxerParams() = default;
#endif

}
