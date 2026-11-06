// Copyright 2026 Parc contributors.

#ifndef THIRD_PARTY_BLINK_RENDERER_MODULES_WEBAUDIO_PLATFORM_AUDIO_FILE_DECODER_H_
#define THIRD_PARTY_BLINK_RENDERER_MODULES_WEBAUDIO_PLATFORM_AUDIO_FILE_DECODER_H_

#include <memory>
#include <optional>
#include <vector>

#include "base/containers/span.h"
#include "base/functional/callback.h"
#include "base/memory/scoped_refptr.h"
#include "base/time/time.h"
#include "third_party/blink/renderer/platform/allow_discouraged_type.h"

namespace base {
class SequencedTaskRunner;
}  // namespace base

namespace media {
class AudioBus;
class AudioDecoder;
class MediaLog;
}  // namespace media

namespace blink {

// decodeAudioData() for audio the renderer's FFmpeg demuxes but can't decode:
// Parc builds FFmpeg without its AAC decoder, and AudioToolbox, which decodes
// AAC, runs only under the GPU process's sandbox. FFmpeg demuxes in the
// renderer and media::AudioFileReader keeps its timestamps and trimming; each
// packet goes to the platform decoder, which decodeAudioData() binds to the
// GPU process through MojoAudioDecoder.
class PlatformAudioFileDecoder {
 public:
  struct Output {
    Output();
    Output(Output&&);
    Output& operator=(Output&&);
    ~Output();

    int sample_rate = 0;
    int channels = 0;
    size_t frames = 0;
    // As media::AudioFileReader produces them.
    std::vector<std::unique_ptr<media::AudioBus>> packets
        ALLOW_DISCOURAGED_TYPE("media::AudioFileReader's output");
  };

  // Called once, on the decoding sequence, when the input is AAC.
  using CreateDecoderCB =
      base::OnceCallback<std::unique_ptr<media::AudioDecoder>(
          scoped_refptr<base::SequencedTaskRunner>,
          media::MediaLog*)>;
  using DoneCB = base::OnceCallback<void(std::optional<Output>)>;

  // Decodes `data` on `task_runner` and runs `done` exactly once: there, or
  // before returning if `task_runner` no longer accepts tasks. Only a shutdown
  // that drops the posted task drops `done` unrun. `done` gets
  // nullopt when `data` isn't AAC, the decoder refuses it or disconnects (the
  // GPU process crashed), `is_cancelled` returns true, or the decoder leaves
  // calls unanswered for `timeout`. A decode error part way through returns the
  // audio before it, as media::AudioFileReader::Read() does for damaged files.
  // Up to `decodes_in_flight` decodes are outstanding at once, which the
  // decoder must accept (MojoAudioDecoder does; other audio decoders take one).
  // `data` must stay valid until `done` runs.
  static void Decode(base::span<const uint8_t> data,
                     scoped_refptr<base::SequencedTaskRunner> task_runner,
                     CreateDecoderCB create_decoder,
                     base::RepeatingCallback<bool()> is_cancelled,
                     int decodes_in_flight,
                     base::TimeDelta timeout,
                     DoneCB done);
};

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_MODULES_WEBAUDIO_PLATFORM_AUDIO_FILE_DECODER_H_
