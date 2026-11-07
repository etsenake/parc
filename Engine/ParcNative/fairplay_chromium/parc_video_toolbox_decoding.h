// Installed by the reviewed overlay at
// //content/browser/media/parc_video_toolbox_decoding.h.
//
// Parc: the VideoToolbox decoder facts behind WebKit's MediaCapabilities
// answers on macOS (PlatformMediaEngineConfigurationFactoryCocoa.cpp,
// HEVCUtilitiesCocoa.mm), which documents presenting Safari's identity get
// (docs/fairplay-identity.md). Renderers can't ask VideoToolbox from their
// sandbox, so the browser reads the facts once, on a thread pool sequence,
// and hands them to frames and dedicated workers through
// media.mojom.ParcVideoToolboxDecoding, which also reads AudioToolbox's spatial
// audio preferences for the output device at each call (WebKit's
// SpatialAudioPlaybackHelperMac, for spatialRendering).
#ifndef CONTENT_BROWSER_MEDIA_PARC_VIDEO_TOOLBOX_DECODING_H_
#define CONTENT_BROWSER_MEDIA_PARC_VIDEO_TOOLBOX_DECODING_H_

#include "media/mojo/mojom/video_decode_perf_history.mojom.h"
#include "mojo/public/cpp/bindings/pending_receiver.h"

namespace content {

void BindParcVideoToolboxDecoding(
    mojo::PendingReceiver<media::mojom::ParcVideoToolboxDecoding> receiver);

}  // namespace content

#endif  // CONTENT_BROWSER_MEDIA_PARC_VIDEO_TOOLBOX_DECODING_H_
