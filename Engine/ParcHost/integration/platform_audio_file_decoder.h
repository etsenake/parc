// Copyright 2026 Parc contributors.

#ifndef THIRD_PARTY_BLINK_RENDERER_MODULES_WEBAUDIO_PLATFORM_AUDIO_FILE_DECODER_H_
#define THIRD_PARTY_BLINK_RENDERER_MODULES_WEBAUDIO_PLATFORM_AUDIO_FILE_DECODER_H_

#include <atomic>
#include <memory>
#include <optional>
#include <vector>

#include "base/containers/span.h"
#include "base/functional/callback.h"
#include "base/memory/scoped_refptr.h"
#include "base/time/time.h"
#include "third_party/blink/renderer/platform/allow_discouraged_type.h"
#include "third_party/blink/renderer/platform/wtf/thread_safe_ref_counted.h"

namespace base {
class SequencedTaskRunner;
}

namespace media {
class AudioBus;
class AudioDecoder;
class MediaLog;
}

namespace blink {

class AudioBus;

class DecodeCancellation final
    : public ThreadSafeRefCounted<DecodeCancellation> {
 public:
  void Cancel() { cancelled_.store(true, std::memory_order_relaxed); }
  bool IsCancelled() const {
    return cancelled_.load(std::memory_order_relaxed);
  }

 private:
  friend class ThreadSafeRefCounted<DecodeCancellation>;
  ~DecodeCancellation() = default;

  std::atomic<bool> cancelled_{false};
};

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
    std::vector<std::unique_ptr<media::AudioBus>> packets
        ALLOW_DISCOURAGED_TYPE("media::AudioFileReader's output");
  };

  using CreateDecoderCB =
      base::OnceCallback<std::unique_ptr<media::AudioDecoder>(
          scoped_refptr<base::SequencedTaskRunner>,
          media::MediaLog*)>;
  using DoneCB = base::OnceCallback<void(std::optional<Output>)>;

  static void Decode(base::span<const uint8_t> data,
                     scoped_refptr<base::SequencedTaskRunner> task_runner,
                     CreateDecoderCB create_decoder,
                     base::RepeatingCallback<bool()> is_cancelled,
                     int decodes_in_flight,
                     base::TimeDelta timeout,
                     DoneCB done);

  static constexpr base::TimeDelta kGpuDecoderTimeout = base::Seconds(30);
  static constexpr int kGpuDecodesInFlight = 8;

  static std::unique_ptr<media::AudioDecoder> CreateGpuDecoder(
      scoped_refptr<base::SequencedTaskRunner> task_runner,
      media::MediaLog* media_log);

  static scoped_refptr<AudioBus> ToAudioBus(std::optional<Output> output,
                                            float sample_rate);
};

}

#endif
