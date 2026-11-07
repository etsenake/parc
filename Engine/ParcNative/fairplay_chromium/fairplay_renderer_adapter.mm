#include "third_party/parc_fairplay/chromium/fairplay_renderer_adapter.h"

#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

#include <utility>
#include <vector>

#include "base/check.h"
#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/logging.h"
#include "base/numerics/safe_conversions.h"
#include "media/base/buffering_state.h"
#include "media/base/cdm_context.h"
#include "media/base/decoder_buffer.h"
#include "media/base/decrypt_config.h"
#include "media/base/encryption_scheme.h"
#include "media/base/media_resource.h"
#include "media/base/renderer_client.h"
#include "media/base/timestamp_constants.h"
#include "media/base/video_codecs.h"
#include "media/base/waiting.h"
#include "third_party/parc_fairplay/chromium/fairplay_task_runner.h"
#include "third_party/parc_fairplay/core/fairplay_key_session.h"
#include "ui/accelerated_widget_mac/protected_layer_registry.h"

namespace media {

namespace {

namespace fp = parc::fairplay;

constexpr fp::StreamType kStreamTypes[] = {fp::StreamType::kVideo,
                                           fp::StreamType::kAudio};

// RendererImpl reports with every frame; pages sample the counts, and Netflix
// gives up after 10 s without a new frame.
constexpr base::TimeDelta kStatisticsInterval = base::Milliseconds(250);
// A metrics request AVFoundation hasn't answered by then is given up, so a
// lost answer can't stop the counts.
constexpr base::TimeDelta kVideoMetricsTimeout = base::Seconds(1);

// How far |total| moved past |*reported|, which follows it. Totals never go
// back, and a smaller one (the other source, or a late answer) adds nothing.
uint32_t AdvanceTotal(int64_t total, int64_t* reported) {
  if (total <= *reported) {
    return 0;
  }
  const int64_t delta = total - *reported;
  *reported = total;
  return base::saturated_cast<uint32_t>(delta);
}

fp::MediaTime ToMediaTime(base::TimeDelta time) {
  return fp::MediaTime::FromMicroseconds(time.InMicroseconds());
}

std::vector<uint8_t> ToBytes(const std::string& bytes) {
  return std::vector<uint8_t>(bytes.begin(), bytes.end());
}

fp::EncryptionScheme ToScheme(EncryptionScheme scheme) {
  switch (scheme) {
    case EncryptionScheme::kUnencrypted:
      return fp::EncryptionScheme::kUnencrypted;
    case EncryptionScheme::kCenc:
      return fp::EncryptionScheme::kCenc;
    case EncryptionScheme::kCbcs:
      return fp::EncryptionScheme::kCbcs;
  }
  return fp::EncryptionScheme::kUnencrypted;
}

std::optional<fp::VideoCodec> ToVideoCodec(VideoCodec codec) {
  switch (codec) {
    case VideoCodec::kH264:
      return fp::VideoCodec::kH264;
    case VideoCodec::kHEVC:
      return fp::VideoCodec::kHEVC;
    case VideoCodec::kDolbyVision:
      return fp::VideoCodec::kDolbyVision;
    case VideoCodec::kAV1:
      return fp::VideoCodec::kAV1;
    default:
      return std::nullopt;
  }
}

std::optional<fp::AudioCodec> ToAudioCodec(AudioCodec codec) {
  switch (codec) {
    case AudioCodec::kAAC:
      return fp::AudioCodec::kAAC;
    case AudioCodec::kAC3:
      return fp::AudioCodec::kAC3;
    case AudioCodec::kEAC3:
      return fp::AudioCodec::kEAC3;
    default:
      return std::nullopt;
  }
}

// The single-layer HEVC-based profiles the core plays (dvh1/dvhe with an
// hvcC base layer); -1 for the rest (AVC-based 0 and 9, dual-layer 7, AV1-based
// 10).
int DolbyVisionProfileNumber(VideoCodecProfile profile) {
  switch (profile) {
    case DOLBYVISION_PROFILE5:
      return 5;
    case DOLBYVISION_PROFILE8:
      return 8;
    default:
      return -1;
  }
}

// Chromium's configs as they are. MP4StreamParser leaves video extra_data
// empty and hands H.264, HEVC and Dolby Vision over as Annex B with parameter
// sets before keyframes, AV1 as stored, and AAC with ADTS headers; it keeps
// only the profile and level of Dolby Vision's dvcC/dvvC and no dac3/dec3.
// Encryption is the scheme only: the core takes key IDs, patterns and IVs
// from each sample's DecryptInfo.
fp::VideoConfig ToCoreConfig(const VideoDecoderConfig& config) {
  fp::VideoConfig video;
  video.codec = *ToVideoCodec(config.codec());
  video.extra_data = config.extra_data();
  if (video.codec == fp::VideoCodec::kDolbyVision) {
    video.dolby_vision_profile = DolbyVisionProfileNumber(config.profile());
    video.dolby_vision_level = static_cast<int>(config.level());
  }
  video.format = video.codec == fp::VideoCodec::kAV1
                     ? fp::BitstreamFormat::kLengthPrefixed
                     : fp::BitstreamFormat::kAnnexB;
  video.coded_width = config.coded_size().width();
  video.coded_height = config.coded_size().height();
  video.natural_width = config.natural_size().width();
  video.natural_height = config.natural_size().height();
  video.encryption.scheme = ToScheme(config.encryption_scheme());
  return video;
}

fp::AudioConfig ToCoreConfig(const AudioDecoderConfig& config) {
  fp::AudioConfig audio;
  audio.codec = *ToAudioCodec(config.codec());
  audio.extra_data = config.extra_data();
  // The core strips an ADTS header when one is present.
  audio.framing = audio.codec == fp::AudioCodec::kAAC ? fp::AudioFraming::kADTS
                                                      : fp::AudioFraming::kRaw;
  audio.sample_rate = config.samples_per_second();
  audio.channels = config.channels();
  audio.encryption.scheme = ToScheme(config.encryption_scheme());
  return audio;
}

}  // namespace

FairPlayRendererAdapter::FairPlayRendererAdapter(
    scoped_refptr<base::SequencedTaskRunner> task_runner,
    LayerRegisteredCB layer_registered_cb)
    : task_runner_(std::move(task_runner)),
      layer_registered_cb_(std::move(layer_registered_cb)),
      core_(std::make_unique<fp::FairPlayRenderer>(
          this,
          fp::PostTaskTo(task_runner_))) {}

FairPlayRendererAdapter::~FairPlayRendererAdapter() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  weak_factory_.InvalidateWeakPtrs();
  if (!layer_token_.is_empty()) {
    // The compositor may still hold the layer until its next commit: remove
    // the displayed image first so nothing stale shows, then unregister.
    AVSampleBufferDisplayLayer* layer =
        (__bridge AVSampleBufferDisplayLayer*)core_->display_layer();
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (@available(macOS 14.0, *)) {
      [layer.sampleBufferRenderer flushWithRemovalOfDisplayedImage:YES
                                                 completionHandler:nil];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
      [layer flushAndRemoveImage];
#pragma clang diagnostic pop
    }
    [CATransaction commit];
    ui::ProtectedLayerRegistry::Unregister(layer_token_);
  }
  // Detaches the CDM, which MojoRendererService keeps alive until after this.
  core_.reset();
}

void FairPlayRendererAdapter::Initialize(MediaResource* media_resource,
                                         RendererClient* client,
                                         PipelineStatusCallback init_cb) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  DCHECK(client);
  client_ = client;
  video_.demuxer_stream = media_resource->GetFirstStream(DemuxerStream::VIDEO);
  audio_.demuxer_stream = media_resource->GetFirstStream(DemuxerStream::AUDIO);

  PipelineStatus status = PIPELINE_OK;
  std::optional<fp::VideoConfig> video;
  std::optional<fp::AudioConfig> audio;
  if (!video_.demuxer_stream && !audio_.demuxer_stream) {
    status = PIPELINE_ERROR_COULD_NOT_RENDER;
  }
  if (video_.demuxer_stream) {
    video_config_ = video_.demuxer_stream->video_decoder_config();
    // Dolby Vision only in the profiles the core plays.
    const bool dolby_vision_ok =
        video_config_.codec() != VideoCodec::kDolbyVision ||
        DolbyVisionProfileNumber(video_config_.profile()) >= 0;
    if (ToVideoCodec(video_config_.codec()) && dolby_vision_ok) {
      video = ToCoreConfig(video_config_);
    } else {
      status = DECODER_ERROR_NOT_SUPPORTED;
    }
  }
  if (audio_.demuxer_stream) {
    audio_config_ = audio_.demuxer_stream->audio_decoder_config();
    if (ToAudioCodec(audio_config_.codec())) {
      audio = ToCoreConfig(audio_config_);
    } else {
      status = DECODER_ERROR_NOT_SUPPORTED;
    }
  }

  if (status.is_ok()) {
    // The display layer is created on this thread, which has no run loop, so
    // commit its creation explicitly.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    fp::Result result = core_->Initialize(video, audio);
    [CATransaction commit];
    if (!result.ok()) {
      LOG(ERROR) << "FairPlay renderer initialization failed: "
                 << result.message;
      status = PIPELINE_ERROR_INITIALIZATION_FAILED;
    }
  } else {
    LOG(ERROR) << "FairPlay renderer can't play this media: video "
               << (video_.demuxer_stream ? video_config_.AsHumanReadableString()
                                         : "none")
               << ", audio "
               << (audio_.demuxer_stream ? audio_config_.AsHumanReadableString()
                                         : "none");
  }

  if (status.is_ok()) {
    core_initialized_ = true;
    core_->SetVolume(volume_);
    core_->SetMuted(muted_ || awaiting_mute_state_);
    if (video) {
      CALayer* layer = (__bridge CALayer*)core_->display_layer();
      layer_token_ = base::UnguessableToken::Create();
      if (ui::ProtectedLayerRegistry::Register(layer_token_, layer)) {
        natural_size_ = video_config_.natural_size();
        layer_registered_cb_.Run(layer_token_, natural_size_);
      } else {
        layer_token_ = base::UnguessableToken();
        LOG(ERROR) << "FairPlay display layer registration failed";
        status = PIPELINE_ERROR_INITIALIZATION_FAILED;
      }
    }
  }
  // |init_cb| must not run before this method returns.
  task_runner_->PostTask(FROM_HERE,
                         base::BindOnce(std::move(init_cb), std::move(status)));
}

void FairPlayRendererAdapter::SetCdm(CdmContext* cdm_context,
                                     CdmAttachedCB cdm_attached_cb) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  bool success = false;
  fp::FairPlayCdm* cdm = cdm_context ? cdm_context->GetFairPlayCdm() : nullptr;
  if (cdm && !cdm_attached_) {
    // The core accepts the CDM before Initialize and joins its key session
    // once the renderers exist, before any sample is enqueued.
    fp::Result result = core_->SetCdm(cdm);
    success = result.ok();
    LOG_IF(ERROR, !success) << "FairPlay SetCdm: " << result.message;
  }
  cdm_attached_ = cdm_attached_ || success;
  task_runner_->PostTask(FROM_HERE,
                         base::BindOnce(std::move(cdm_attached_cb), success));
}

void FairPlayRendererAdapter::SetLatencyHint(
    std::optional<base::TimeDelta> latency_hint) {
  // The synchronizer decides its own preroll.
}

void FairPlayRendererAdapter::Flush(base::OnceClosure flush_cb) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  DCHECK(!flush_cb_);
  ++generation_;
  playing_ = false;
  UpdateStatisticsTimer();
  flush_cb_ = std::move(flush_cb);
  video_.end_of_stream = false;
  audio_.end_of_stream = false;
  if (core_initialized_) {
    core_flush_pending_ = true;
    base::WeakPtr<FairPlayRendererAdapter> weak = weak_factory_.GetWeakPtr();
    core_->Flush([weak] {
      if (weak) {
        weak->core_flush_pending_ = false;
        weak->MaybeFinishFlush();
      }
    });
    return;
  }
  // Reads outstanding when the pipeline flushes have been aborted by the
  // demuxer; finish once they have returned.
  MaybeFinishFlush();
}

void FairPlayRendererAdapter::StartPlayingFrom(base::TimeDelta time) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  playing_ = true;
  start_time_ = time;
  if (errored_ || !core_initialized_) {
    return;
  }
  // The pipeline has reported metadata by now, so the player accepts sizes.
  // Report the config's size once, before any HAVE_ENOUGH.
  if (!natural_size_reported_ && !natural_size_.IsEmpty()) {
    natural_size_reported_ = true;
    client_->OnVideoNaturalSizeChange(natural_size_);
  }
  core_->StartPlayingFrom(ToMediaTime(time));
  UpdateStatisticsTimer();
  for (fp::StreamType type : kStreamTypes) {
    OnNeedData(type);
  }
}

void FairPlayRendererAdapter::SetPlaybackRate(double playback_rate) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  playback_rate_ = playback_rate;
  if (core_initialized_) {
    core_->SetPlaybackRate(playback_rate);
  }
  UpdateStatisticsTimer();
}

void FairPlayRendererAdapter::SetVolume(float volume) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  // The pipeline sets the volume before Initialize, when the core has no
  // audio renderer yet; Initialize applies the kept value.
  volume_ = volume;
  if (core_initialized_) {
    core_->SetVolume(volume);
  }
}

base::TimeDelta FairPlayRendererAdapter::GetMediaTime() {
  // MojoRendererService polls this on the media service sequence.
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!core_initialized_) {
    return start_time_;
  }
  return base::Microseconds(core_->GetMediaTime().InMicroseconds());
}

RendererType FairPlayRendererAdapter::GetRendererType() {
  return RendererType::kFairPlay;
}

base::RepeatingCallback<void(bool)>
FairPlayRendererAdapter::GetMuteStateCallback() {
  return base::BindRepeating(&FairPlayRendererAdapter::SetMuted,
                             weak_factory_.GetWeakPtr());
}

void FairPlayRendererAdapter::SetMuteStateObserverCloser(
    base::ScopedClosureRunner closer) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  mute_state_observer_closer_ = std::move(closer);
  awaiting_mute_state_ = true;
  if (core_initialized_) {
    core_->SetMuted(true);
  }
}

void FairPlayRendererAdapter::SetMuted(bool muted) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  muted_ = muted;
  awaiting_mute_state_ = false;
  if (core_initialized_) {
    core_->SetMuted(muted);
  }
}

void FairPlayRendererAdapter::OnNeedData(fp::StreamType type) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!playing_ || errored_ || !core_initialized_) {
    return;
  }
  Stream& stream = StreamFor(type);
  if (!stream.demuxer_stream || stream.read_pending || stream.end_of_stream ||
      !core_->IsReadyForMoreData(type)) {
    return;
  }
  ReadFromStream(type);
}

void FairPlayRendererAdapter::OnWaitingForKey() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  client_->OnWaiting(WaitingReason::kNoDecryptionKey);
}

void FairPlayRendererAdapter::OnEnded() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  client_->OnEnded();
}

void FairPlayRendererAdapter::OnError(fp::RendererError error,
                                      const std::string& description) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  LOG(ERROR) << "FairPlay renderer error: " << description;
  ReportError(PIPELINE_ERROR_DECODE);
}

void FairPlayRendererAdapter::OnVideoNaturalSizeChange(int32_t width,
                                                       int32_t height) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  // The core reports the natural size of the config it was given.
  const gfx::Size size(width, height);
  if (size.IsEmpty() || size == natural_size_) {
    return;
  }
  natural_size_ = size;
  if (natural_size_reported_) {
    client_->OnVideoNaturalSizeChange(size);
  }
}

void FairPlayRendererAdapter::OnBufferingStateChange(bool have_enough) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  client_->OnBufferingStateChange(
      have_enough ? BUFFERING_HAVE_ENOUGH : BUFFERING_HAVE_NOTHING,
      have_enough ? BUFFERING_CHANGE_REASON_UNKNOWN : DEMUXER_UNDERFLOW);
}

FairPlayRendererAdapter::Stream& FairPlayRendererAdapter::StreamFor(
    fp::StreamType type) {
  return type == fp::StreamType::kVideo ? video_ : audio_;
}

void FairPlayRendererAdapter::ReadFromStream(fp::StreamType type) {
  Stream& stream = StreamFor(type);
  DCHECK(stream.demuxer_stream);
  DCHECK(!stream.read_pending);
  stream.read_pending = true;
  stream.demuxer_stream->Read(
      1, base::BindOnce(&FairPlayRendererAdapter::OnBuffersRead,
                        weak_factory_.GetWeakPtr(), type, generation_));
}

void FairPlayRendererAdapter::OnBuffersRead(
    fp::StreamType type,
    uint64_t generation,
    DemuxerStream::Status status,
    DemuxerStream::DecoderBufferVector buffers) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  Stream& stream = StreamFor(type);
  stream.read_pending = false;
  if (generation != generation_ || flush_cb_) {
    // The stream reports a config change once; apply it even to a read the
    // Flush made stale, or later buffers would run on the old config.
    if (status == DemuxerStream::kConfigChanged && !errored_) {
      HandleConfigChange(type);
    }
    MaybeFinishFlush();
    return;
  }
  if (errored_) {
    return;
  }
  switch (status) {
    case DemuxerStream::kAborted:
      // The demuxer aborts reads ahead of a seek; the Flush follows.
      return;
    case DemuxerStream::kError:
      ReportError(PIPELINE_ERROR_READ);
      return;
    case DemuxerStream::kConfigChanged:
      HandleConfigChange(type);
      OnNeedData(type);
      return;
    case DemuxerStream::kOk:
      break;
  }
  for (const scoped_refptr<DecoderBuffer>& buffer : buffers) {
    if (buffer->end_of_stream()) {
      stream.end_of_stream = true;
      core_->SetEndOfStream(type);
      return;
    }
    EnqueueToCore(type, *buffer);
    if (errored_) {
      return;
    }
  }
  OnNeedData(type);
}

void FairPlayRendererAdapter::HandleConfigChange(fp::StreamType type) {
  Stream& stream = StreamFor(type);
  fp::Result result;
  // A new config, possibly a new codec (MSE changeType, e.g. an audio
  // language switch from E-AC-3 to AAC): the core builds formats for the
  // samples that follow, protected ones per key ID as they arrive.
  if (type == fp::StreamType::kVideo) {
    VideoDecoderConfig config = stream.demuxer_stream->video_decoder_config();
    const bool dolby_vision_ok =
        config.codec() != VideoCodec::kDolbyVision ||
        DolbyVisionProfileNumber(config.profile()) >= 0;
    if (!ToVideoCodec(config.codec()) || !dolby_vision_ok) {
      LOG(ERROR) << "FairPlay renderer can't play "
                 << config.AsHumanReadableString();
      ReportError(DECODER_ERROR_NOT_SUPPORTED);
      return;
    }
    result = core_->Reconfigure(ToCoreConfig(config));
    video_config_ = config;
    client_->OnVideoConfigChange(config);
  } else {
    AudioDecoderConfig config = stream.demuxer_stream->audio_decoder_config();
    if (!ToAudioCodec(config.codec())) {
      LOG(ERROR) << "FairPlay renderer can't play "
                 << config.AsHumanReadableString();
      ReportError(DECODER_ERROR_NOT_SUPPORTED);
      return;
    }
    result = core_->Reconfigure(ToCoreConfig(config));
    audio_config_ = config;
    client_->OnAudioConfigChange(config);
  }
  if (!result.ok()) {
    LOG(ERROR) << "FairPlay renderer config change failed: " << result.message;
    ReportError(DECODER_ERROR_NOT_SUPPORTED);
  }
}

void FairPlayRendererAdapter::EnqueueToCore(fp::StreamType type,
                                            const DecoderBuffer& buffer) {
  const base::span<const uint8_t> data(buffer);
  fp::EncodedSample sample;
  sample.data = data.data();
  sample.size = data.size();
  sample.pts = ToMediaTime(buffer.timestamp());
  // DecoderBuffers carry presentation times only; invalid means "as pts".
  sample.dts = fp::MediaTime::Invalid();
  sample.duration = (buffer.duration() == kNoTimestamp ||
                     buffer.duration() <= base::TimeDelta())
                        ? fp::MediaTime::Invalid()
                        : ToMediaTime(buffer.duration());
  sample.is_keyframe = buffer.is_key_frame();
  if (const DecryptConfig* config = buffer.decrypt_config()) {
    // MP4's track run iterator gives every sample a 16-byte IV (a constant IV
    // copied in, 8-byte IVs zero-padded), as the core expects.
    fp::DecryptInfo decrypt;
    decrypt.scheme = ToScheme(config->encryption_scheme());
    decrypt.key_id = ToBytes(config->key_id());
    decrypt.iv = ToBytes(config->iv());
    decrypt.subsamples.reserve(config->subsamples().size());
    for (const SubsampleEntry& entry : config->subsamples()) {
      decrypt.subsamples.push_back({entry.clear_bytes, entry.cypher_bytes});
    }
    if (config->encryption_pattern()) {
      decrypt.pattern = fp::EncryptionPattern{
          uint8_t(config->encryption_pattern()->crypt_byte_block()),
          uint8_t(config->encryption_pattern()->skip_byte_block())};
    }
    sample.decrypt = std::move(decrypt);
  }
  if (core_->Enqueue(type, sample) == fp::EnqueueResult::kRejected) {
    LOG(ERROR) << "FairPlay renderer rejected a sample";
    ReportError(PIPELINE_ERROR_DECODE);
    return;
  }
  // A sample held for its key is decoded once the key arrives.
  (type == fp::StreamType::kVideo ? unreported_video_bytes_
                                  : unreported_audio_bytes_) += data.size();
}

void FairPlayRendererAdapter::MaybeFinishFlush() {
  if (!flush_cb_ || core_flush_pending_ || video_.read_pending ||
      audio_.read_pending) {
    return;
  }
  task_runner_->PostTask(FROM_HERE, std::move(flush_cb_));
}

void FairPlayRendererAdapter::ReportError(PipelineStatus status) {
  if (errored_) {
    return;
  }
  errored_ = true;
  statistics_timer_.Stop();
  client_->OnError(std::move(status));
}

void FairPlayRendererAdapter::UpdateStatisticsTimer() {
  // Polled while the clock may run. Stopping (pause, seek) counts once more,
  // so the frames decoded until then don't wait for playback to resume.
  const bool run =
      playing_ && playback_rate_ > 0 && core_initialized_ && !errored_;
  if (run == statistics_timer_.IsRunning()) {
    return;
  }
  if (run) {
    statistics_timer_.Start(
        FROM_HERE, kStatisticsInterval,
        base::BindRepeating(&FairPlayRendererAdapter::PollStatistics,
                            base::Unretained(this)));
    return;
  }
  statistics_timer_.Stop();
  // Even with an answer outstanding: before macOS 14.4 that answer carries
  // the core's count from when it was asked.
  RequestVideoMetrics();
}

void FairPlayRendererAdapter::PollStatistics() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!video_metrics_requested_.is_null() &&
      base::TimeTicks::Now() - video_metrics_requested_ <
          kVideoMetricsTimeout) {
    return;
  }
  RequestVideoMetrics();
}

void FairPlayRendererAdapter::RequestVideoMetrics() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!core_initialized_ || errored_) {
    return;
  }
  video_metrics_requested_ = base::TimeTicks::Now();
  base::WeakPtr<FairPlayRendererAdapter> weak = weak_factory_.GetWeakPtr();
  // Answers on this sequence.
  core_->LoadVideoMetrics([weak](const fp::VideoMetrics& metrics) {
    if (weak) {
      weak->OnVideoMetrics(metrics);
    }
  });
}

void FairPlayRendererAdapter::OnVideoMetrics(const fp::VideoMetrics& metrics) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  // Clears the wait even when a newer request is outstanding; a second
  // answer adds only what it counts beyond the first.
  video_metrics_requested_ = base::TimeTicks();
  if (errored_) {
    return;
  }
  // AVFoundation's own counts (macOS 14.4+) are the decoder's: frames decoded
  // ahead of the clock, like RendererImpl's, and real drops. Before them, the
  // core's count of samples the clock has reached, with no drops known.
  if (metrics.available) {
    ReportStatistics(metrics.total_frames, metrics.dropped_frames);
  } else {
    ReportStatistics(metrics.frames_passed, reported_frames_dropped_);
  }
}

void FairPlayRendererAdapter::ReportStatistics(int64_t frames_decoded,
                                               int64_t frames_dropped) {
  // PipelineImpl adds up deltas.
  PipelineStatistics stats;
  stats.video_frames_decoded =
      AdvanceTotal(frames_decoded, &reported_frames_decoded_);
  stats.video_frames_dropped =
      AdvanceTotal(frames_dropped, &reported_frames_dropped_);
  stats.video_bytes_decoded = std::exchange(unreported_video_bytes_, 0);
  stats.audio_bytes_decoded = std::exchange(unreported_audio_bytes_, 0);
  if (!stats.video_frames_decoded && !stats.video_frames_dropped &&
      !stats.video_bytes_decoded && !stats.audio_bytes_decoded) {
    return;
  }
  client_->OnStatisticsUpdate(stats);
}

}  // namespace media
