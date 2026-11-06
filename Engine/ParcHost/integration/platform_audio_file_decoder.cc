// Copyright 2026 Parc contributors.

#include "third_party/blink/renderer/modules/webaudio/platform_audio_file_decoder.h"

#include <algorithm>
#include <utility>

#include "base/functional/callback_helpers.h"
#include "base/location.h"
#include "base/memory/weak_ptr.h"
#include "base/sequence_checker.h"
#include "base/task/bind_post_task.h"
#include "base/task/sequenced_task_runner.h"
#include "base/timer/timer.h"
#include "media/base/audio_buffer.h"
#include "media/base/audio_bus.h"
#include "media/base/audio_codecs.h"
#include "media/base/audio_decoder.h"
#include "media/base/decoder_buffer.h"
#include "media/base/decoder_status.h"
#include "media/base/limits.h"
#include "media/base/media_util.h"
#include "media/filters/audio_file_reader.h"
#include "media/filters/in_memory_url_protocol.h"
#include "third_party/blink/renderer/platform/wtf/cross_thread_functional.h"
#include "third_party/blink/renderer/platform/wtf/functional.h"

namespace blink {

namespace {

// How often a decode checks for cancellation and a stalled decoder.
constexpr base::TimeDelta kWatchdogPeriod = base::Seconds(1);

// Errors in the stream itself. Decoding stops and keeps the audio so far, as
// AudioFileReader::Read() does. Any other error, such as a lost connection,
// fails the decode.
bool IsStreamError(const media::DecoderStatus& status) {
  return status.code() == media::DecoderStatus::Codes::kPlatformDecodeFailure ||
         status.code() == media::DecoderStatus::Codes::kMalformedBitstream;
}

// Lives on its task runner and deletes itself in Finish(). Decoder outputs and
// answers are posted back to the task runner in the order they arrive, so
// Finish() never destroys the decoder from inside one of its own calls, and
// output after a failed decode is never added.
class DecodeJob {
 public:
  DecodeJob(base::span<const uint8_t> data,
            scoped_refptr<base::SequencedTaskRunner> task_runner,
            PlatformAudioFileDecoder::CreateDecoderCB create_decoder,
            base::RepeatingCallback<bool()> is_cancelled,
            int decodes_in_flight,
            base::TimeDelta timeout,
            PlatformAudioFileDecoder::DoneCB done)
      : task_runner_(std::move(task_runner)),
        protocol_(data, /*streaming=*/false),
        create_decoder_(std::move(create_decoder)),
        is_cancelled_(std::move(is_cancelled)),
        max_decodes_(std::max(decodes_in_flight, 1)),
        timeout_(timeout),
        done_(std::move(done)) {}

  DecodeJob(const DecodeJob&) = delete;
  DecodeJob& operator=(const DecodeJob&) = delete;

  ~DecodeJob() { DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_); }

  void Start() {
    DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
    if (is_cancelled_.Run()) {
      Finish(std::nullopt);
      return;
    }
    reader_ = std::make_unique<media::AudioFileReader>(&protocol_);
    if (!reader_->OpenWithoutDecoder() ||
        reader_->config().codec() != media::AudioCodec::kAAC) {
      Finish(std::nullopt);
      return;
    }
    decoder_ = std::move(create_decoder_).Run(task_runner_, &media_log_);
    if (!decoder_) {
      Finish(std::nullopt);
      return;
    }
    watchdog_.Start(FROM_HERE, kWatchdogPeriod, this,
                    &DecodeJob::CheckProgress);
    waiting_since_ = base::TimeTicks::Now();
    decoder_->Initialize(
        reader_->config(), /*cdm_context=*/nullptr,
        base::BindPostTask(task_runner_,
                           blink::BindOnce(&DecodeJob::OnInitialized,
                                           weak_factory_.GetWeakPtr())),
        base::BindPostTask(task_runner_,
                           blink::BindRepeating(&DecodeJob::OnOutput,
                                                weak_factory_.GetWeakPtr())),
        base::DoNothing());
  }

 private:
  void OnInitialized(media::DecoderStatus status) {
    DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
    waiting_since_ = base::TimeTicks();
    if (!status.is_ok()) {
      Finish(std::nullopt);
      return;
    }
    DecodeMore();
  }

  // Sends packets until `max_decodes_` are outstanding or the end of stream
  // has been sent.
  void DecodeMore() {
    DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
    while (!end_of_stream_sent_ && decodes_ < max_decodes_) {
      if (is_cancelled_.Run()) {
        Finish(std::nullopt);
        return;
      }
      if (reader_->has_output_error()) {
        Complete(/*all_packets_decoded=*/false);
        return;
      }
      scoped_refptr<media::DecoderBuffer> buffer = reader_->ReadNextBuffer();
      end_of_stream_sent_ = !buffer;
      if (end_of_stream_sent_) {
        buffer = media::DecoderBuffer::CreateEOSBuffer();
      }
      if (!decodes_++) {
        waiting_since_ = base::TimeTicks::Now();
      }
      decoder_->Decode(
          std::move(buffer),
          base::BindPostTask(task_runner_,
                             blink::BindOnce(&DecodeJob::OnDecoded,
                                             weak_factory_.GetWeakPtr(),
                                             end_of_stream_sent_)));
    }
  }

  // Answers arrive in the order their decodes were sent.
  void OnDecoded(bool end_of_stream, media::DecoderStatus status) {
    DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
    waiting_since_ = --decodes_ ? base::TimeTicks::Now() : base::TimeTicks();
    if (!status.is_ok()) {
      if (IsStreamError(status)) {
        // Every packet decoded when only the end of stream failed.
        Complete(/*all_packets_decoded=*/end_of_stream);
      } else {
        Finish(std::nullopt);
      }
      return;
    }
    if (end_of_stream) {
      Complete(/*all_packets_decoded=*/true);
      return;
    }
    DecodeMore();
  }

  void OnOutput(scoped_refptr<media::AudioBuffer> buffer) {
    DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
    reader_->AddDecodedOutput(std::move(buffer));
  }

  void CheckProgress() {
    DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
    if (is_cancelled_.Run() ||
        (!waiting_since_.is_null() &&
         base::TimeTicks::Now() - waiting_since_ > timeout_)) {
      Finish(std::nullopt);
    }
  }

  void Complete(bool all_packets_decoded) {
    PlatformAudioFileDecoder::Output output;
    output.packets = reader_->TakeDecodedOutput(all_packets_decoded);
    for (const auto& packet : output.packets) {
      output.frames += packet->frames();
    }
    if (!output.frames) {
      Finish(std::nullopt);
      return;
    }
    output.sample_rate = reader_->output_sample_rate();
    output.channels = reader_->output_channels();
    if (output.channels > media::limits::kMaxChannels ||
        output.sample_rate < media::limits::kMinSampleRate ||
        output.sample_rate > media::limits::kMaxSampleRate) {
      Finish(std::nullopt);
      return;
    }
    Finish(std::move(output));
  }

  // Deletes `this`, releasing the decoder and demuxer before `done_` runs, so
  // that `done_` may free the input.
  void Finish(std::optional<PlatformAudioFileDecoder::Output> output) {
    DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
    watchdog_.Stop();
    decoder_.reset();
    reader_.reset();
    PlatformAudioFileDecoder::DoneCB done = std::move(done_);
    delete this;
    std::move(done).Run(std::move(output));
  }

  const scoped_refptr<base::SequencedTaskRunner> task_runner_;
  media::InMemoryUrlProtocol protocol_;
  PlatformAudioFileDecoder::CreateDecoderCB create_decoder_;
  const base::RepeatingCallback<bool()> is_cancelled_;
  const int max_decodes_;
  const base::TimeDelta timeout_;
  PlatformAudioFileDecoder::DoneCB done_;

  std::unique_ptr<media::AudioFileReader> reader_;
  media::NullMediaLog media_log_;
  std::unique_ptr<media::AudioDecoder> decoder_;
  int decodes_ = 0;
  bool end_of_stream_sent_ = false;
  // When the decoder last answered while calls were outstanding, or when the
  // first of them was sent; null when none is outstanding.
  base::TimeTicks waiting_since_;
  base::RepeatingTimer watchdog_;

  SEQUENCE_CHECKER(sequence_checker_);
  base::WeakPtrFactory<DecodeJob> weak_factory_{this};
};

void StartDecodeJob(base::span<const uint8_t> data,
                    scoped_refptr<base::SequencedTaskRunner> task_runner,
                    PlatformAudioFileDecoder::CreateDecoderCB create_decoder,
                    base::RepeatingCallback<bool()> is_cancelled,
                    int decodes_in_flight,
                    base::TimeDelta timeout,
                    PlatformAudioFileDecoder::DoneCB done) {
  (new DecodeJob(data, std::move(task_runner), std::move(create_decoder),
                 std::move(is_cancelled), decodes_in_flight, timeout,
                 std::move(done)))
      ->Start();
}

}  // namespace

PlatformAudioFileDecoder::Output::Output() = default;
PlatformAudioFileDecoder::Output::Output(Output&&) = default;
PlatformAudioFileDecoder::Output& PlatformAudioFileDecoder::Output::operator=(
    Output&&) = default;
PlatformAudioFileDecoder::Output::~Output() = default;

// static
void PlatformAudioFileDecoder::Decode(
    base::span<const uint8_t> data,
    scoped_refptr<base::SequencedTaskRunner> task_runner,
    CreateDecoderCB create_decoder,
    base::RepeatingCallback<bool()> is_cancelled,
    int decodes_in_flight,
    base::TimeDelta timeout,
    DoneCB done) {
  auto [posted_done, unposted_done] = base::SplitOnceCallback(std::move(done));
  const bool posted = task_runner->PostTask(
      FROM_HERE, ConvertToBaseOnceCallback(CrossThreadBindOnce(
                     &StartDecodeJob, data, task_runner,
                     std::move(create_decoder), std::move(is_cancelled),
                     decodes_in_flight, timeout, std::move(posted_done))));
  if (!posted) {
    std::move(unposted_done).Run(std::nullopt);
  }
}

}  // namespace blink
