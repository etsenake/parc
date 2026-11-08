#include "third_party/parc_fairplay/chromium/fairplay_renderer_adapter.h"

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

// Safari's GPU process refreshes the counts a page reads at the interval the
// page reads them, checked every 250 ms while playing
// (RemoteAudioVideoRendererProxyManager::setVideoPlaybackMetricsUpdateInterval,
// RemoteMediaPlayerProxy::maybeUpdateCachedVideoMetrics); a 250 ms poll is as
// fresh.
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
    case AudioCodec::kFLAC:
      return fp::AudioCodec::kFLAC;
    case AudioCodec::kOpus:
      return fp::AudioCodec::kOpus;
    case AudioCodec::kALAC:
      return fp::AudioCodec::kALAC;
    default:
      return std::nullopt;
  }
}

// The single-layer profiles the core plays: HEVC-based 5 and 8 (dvh1 with an
// hvcC base layer) and AV1-based 10 (dav1 with av1C); -1 for the rest
// (AVC-based 0 and 9, dual-layer 7).
int DolbyVisionProfileNumber(VideoCodecProfile profile) {
  switch (profile) {
    case DOLBYVISION_PROFILE5:
      return 5;
    case DOLBYVISION_PROFILE8:
      return 8;
    case DOLBYVISION_PROFILE10:
      return 10;
    default:
      return -1;
  }
}

// MP4StreamParser keeps a Dolby Vision track's
// dv_bl_signal_compatibility_id only as its color space
// (mp4::ParseDolbyVisionColorSpace). Safari MSE also marks SDR (2)
// explicitly, so Chrome-identity pages keep their existing answer.
int DolbyVisionCompatibilityId(const VideoDecoderConfig& config) {
  if (config.parc_dolby_vision_sdr()) {
    return 2;
  }
  if (config.profile() != DOLBYVISION_PROFILE5 &&
      config.color_space_info().transfer() ==
          VideoColorSpace::TransferID::ARIB_STD_B67) {
    return 4;
  }
  return -1;
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
    video.dolby_vision_compatibility_id = DolbyVisionCompatibilityId(config);
    if (config.profile() == DOLBYVISION_PROFILE10) {
      video.codec = fp::VideoCodec::kAV1;
      video.sample_entry = 0x64617631;  // 'dav1'
    }
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

// The core's config for what it plays: H.264, HEVC, AV1 and the Dolby Vision
// profiles above.
std::optional<fp::VideoConfig> CoreConfigIfPlayable(
    const VideoDecoderConfig& config) {
  if (!ToVideoCodec(config.codec()) ||
      (config.codec() == VideoCodec::kDolbyVision &&
       DolbyVisionProfileNumber(config.profile()) < 0)) {
    return std::nullopt;
  }
  return ToCoreConfig(config);
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

std::optional<fp::AudioConfig> CoreConfigIfPlayable(
    const AudioDecoderConfig& config) {
  if (!ToAudioCodec(config.codec())) {
    return std::nullopt;
  }
  return ToCoreConfig(config);
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
    core_->RemoveDisplayedImage();
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

  // FairPlayRendererClient gives the streams to play.
  const std::vector<raw_ptr<DemuxerStream>> given =
      media_resource->GetAllStreams();
  PipelineStatus status = PIPELINE_OK;
  std::optional<fp::VideoConfig> video;
  std::vector<std::pair<uint32_t, fp::AudioConfig>> audio;
  std::string unplayable;
  for (uint32_t id = 0; id < given.size(); ++id) {
    DemuxerStream* stream = given[id];
    if (stream->type() == DemuxerStream::VIDEO && !video) {
      video = CoreConfigIfPlayable(stream->video_decoder_config());
      if (!video) {
        unplayable += " " + stream->video_decoder_config().AsHumanReadableString();
        status = DECODER_ERROR_NOT_SUPPORTED;
        continue;
      }
      streams_[id].demuxer_stream = stream;
    } else if (stream->type() == DemuxerStream::AUDIO) {
      std::optional<fp::AudioConfig> config =
          CoreConfigIfPlayable(stream->audio_decoder_config());
      if (!config) {
        unplayable += " " + stream->audio_decoder_config().AsHumanReadableString();
        status = DECODER_ERROR_NOT_SUPPORTED;
        continue;
      }
      audio.emplace_back(id, *config);
      streams_[id].demuxer_stream = stream;
    }
  }
  if (streams_.empty() && status.is_ok()) {
    status = PIPELINE_ERROR_COULD_NOT_RENDER;
  }

  if (status.is_ok()) {
    // The display layer is created on this thread, which has no run loop, so
    // commit its creation explicitly.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    fp::Result result = core_->Initialize(
        video, audio.empty() ? std::nullopt
                             : std::make_optional(audio.front().second));
    if (result.ok() && !audio.empty()) {
      streams_[audio.front().first].core = {fp::StreamType::kAudio, 0};
    }
    for (size_t i = 1; result.ok() && i < audio.size(); ++i) {
      uint32_t track = 0;
      result = core_->AddAudio(audio[i].second, &track);
      streams_[audio[i].first].core = {fp::StreamType::kAudio, track};
    }
    [CATransaction commit];
    if (!result.ok()) {
      LOG(ERROR) << "FairPlay renderer initialization failed: "
                 << result.message;
      status = PIPELINE_ERROR_INITIALIZATION_FAILED;
    }
  } else if (!unplayable.empty()) {
    LOG(ERROR) << "FairPlay renderer can't play" << unplayable;
  }

  if (status.is_ok()) {
    core_initialized_ = true;
    core_has_video_ = video.has_value();
    core_->SetVolume(volume_);
    core_->SetMuted(muted_ || awaiting_mute_state_);
    if (video) {
      natural_size_ =
          gfx::Size(video->natural_width, video->natural_height);
      if (!RegisterLayer()) {
        status = PIPELINE_ERROR_INITIALIZATION_FAILED;
      }
    }
  }
  // |init_cb| must not run before this method returns.
  task_runner_->PostTask(FROM_HERE,
                         base::BindOnce(std::move(init_cb), std::move(status)));
}

bool FairPlayRendererAdapter::RegisterLayer() {
  CALayer* layer = (__bridge CALayer*)core_->display_layer();
  layer_token_ = base::UnguessableToken::Create();
  if (!ui::ProtectedLayerRegistry::Register(layer_token_, layer)) {
    layer_token_ = base::UnguessableToken();
    LOG(ERROR) << "FairPlay display layer registration failed";
    return false;
  }
  layer_registered_cb_.Run(layer_token_, natural_size_);
  return true;
}

void FairPlayRendererAdapter::SetExtension(
    std::unique_ptr<mojom::FairPlayRendererExtension> extension) {
  extension_ = std::move(extension);
}

void FairPlayRendererAdapter::AddStream(uint32_t id, DemuxerStream* stream) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (errored_ || !core_initialized_ || streams_.contains(id) ||
      (stream->type() != DemuxerStream::AUDIO &&
       stream->type() != DemuxerStream::VIDEO)) {
    return;
  }
  fp::Result result;
  fp::StreamId core{fp::StreamType::kVideo};
  if (stream->type() == DemuxerStream::VIDEO) {
    std::optional<fp::VideoConfig> config =
        CoreConfigIfPlayable(stream->video_decoder_config());
    if (!config) {
      LOG(ERROR) << "FairPlay renderer can't play "
                 << stream->video_decoder_config().AsHumanReadableString();
      ReportError(DECODER_ERROR_NOT_SUPPORTED);
      return;
    }
    // The pipeline enables one video stream at a time: a video track switch,
    // or the track the page turned off coming back. It replaces the one
    // playing in the same display layer, from the current time.
    if (core_has_video_) {
      std::erase_if(streams_, [](const auto& entry) {
        return entry.second.core.type == fp::StreamType::kVideo;
      });
      result = core_->ReplaceVideo(*config);
      if (!result.ok()) {
        LOG(ERROR) << "FairPlay renderer couldn't switch video: "
                   << result.message;
        ReportError(PIPELINE_ERROR_DECODE);
        return;
      }
      streams_[id].demuxer_stream = stream;
      client_->OnVideoConfigChange(stream->video_decoder_config());
      MaybeFinishFlush();
      return;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    result = core_->AddVideo(*config);
    [CATransaction commit];
    if (result.ok()) {
      core_has_video_ = true;
      natural_size_ = gfx::Size(config->natural_width, config->natural_height);
      if (!RegisterLayer()) {
        ReportError(PIPELINE_ERROR_DECODE);
        return;
      }
      // The pipeline reported its metadata long ago.
      if (!natural_size_.IsEmpty()) {
        natural_size_reported_ = true;
        client_->OnVideoNaturalSizeChange(natural_size_);
      }
    }
  } else {
    std::optional<fp::AudioConfig> config =
        CoreConfigIfPlayable(stream->audio_decoder_config());
    if (!config) {
      LOG(ERROR) << "FairPlay renderer can't play "
                 << stream->audio_decoder_config().AsHumanReadableString();
      ReportError(DECODER_ERROR_NOT_SUPPORTED);
      return;
    }
    uint32_t track = 0;
    result = core_->AddAudio(*config, &track);
    core = {fp::StreamType::kAudio, track};
  }
  if (!result.ok()) {
    LOG(ERROR) << "FairPlay renderer couldn't add a stream: "
               << result.message;
    ReportError(PIPELINE_ERROR_DECODE);
    return;
  }
  // The core asks for its data (OnNeedData) once it's playing.
  Stream& added = streams_[id];
  added.demuxer_stream = stream;
  added.core = core;
}

bool FairPlayRendererAdapter::RemoveStream(uint32_t id) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  auto it = streams_.find(id);
  if (it == streams_.end()) {
    return true;
  }
  // Video stops being read at once, before the track that replaces it comes
  // (AddStream); its stream stays, as the display layer does.
  const bool audio = it->second.core.type == fp::StreamType::kAudio;
  if (audio) {
    core_->RemoveAudio(it->second.core.audio_track);
  }
  streams_.erase(it);
  MaybeFinishFlush();
  return audio;
}

void FairPlayRendererAdapter::SetCdm(CdmContext* cdm_context,
                                     CdmAttachedCB cdm_attached_cb) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  bool success = false;
  fp::FairPlayCdm* cdm = cdm_context ? cdm_context->GetFairPlayCdm() : nullptr;
  if (!cdm_context) {
    // setMediaKeys(null) on a Safari-identity page (PipelineImpl's
    // SetCdm(nullptr)): protected samples wait from now on, as WebKit's
    // renderer without a CDM holds them.
    core_->DetachCdm();
    success = true;
  } else if (cdm && cdm == attached_cdm_) {
    // The same MediaKeys again: the held samples go on with its keys.
    success = core_->SetCdm(cdm).ok();
  } else if (cdm) {
    // The core accepts the CDM before Initialize and joins its key session
    // once the renderers exist. After it played without keys (a clear start,
    // or clear Dolby Vision), or with other MediaKeys, new renderers join the
    // key session and take over on the same clock, as Safari takes keys at
    // any time; MojoRendererService keeps a replaced CDM for those they
    // replace.
    fp::Result result = core_->SetCdm(cdm);
    success = result.ok();
    if (success) {
      attached_cdm_ = cdm;
    } else {
      LOG(ERROR) << "FairPlay SetCdm: " << result.message;
      // A failed hand-off leaves renderers that can't decrypt.
      if (core_initialized_) {
        ReportError(PIPELINE_ERROR_DECODE);
      }
    }
  }
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
  for (auto& [id, stream] : streams_) {
    stream.end_of_stream = false;
  }
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
  for (auto& [id, stream] : streams_) {
    OnNeedData(stream.core);
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

base::RepeatingCallback<void(const std::string&)>
FairPlayRendererAdapter::GetAudioOutputDeviceCallback() {
  return base::BindRepeating(&FairPlayRendererAdapter::SetAudioOutputDevice,
                             weak_factory_.GetWeakPtr());
}

void FairPlayRendererAdapter::SetAudioOutputDevice(
    const std::string& unique_id) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  // The core keeps it for audio renderers it makes later, before Initialize
  // too.
  if (fp::Result result = core_->SetAudioOutputDevice(unique_id);
      !result.ok()) {
    LOG(ERROR) << "FairPlay audio output device: " << result.message;
  }
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

void FairPlayRendererAdapter::ReplaceMuteStateObserverCloser(
    base::ScopedClosureRunner closer) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  mute_state_observer_closer_ = std::move(closer);
}

void FairPlayRendererAdapter::SetMuted(bool muted) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  muted_ = muted;
  awaiting_mute_state_ = false;
  if (core_initialized_) {
    core_->SetMuted(muted);
  }
}

void FairPlayRendererAdapter::OnNeedData(fp::StreamId core) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!playing_ || errored_ || !core_initialized_) {
    return;
  }
  for (auto& [id, stream] : streams_) {
    if (stream.core == core) {
      if (!stream.read_pending && !stream.end_of_stream &&
          core_->IsReadyForMoreData(core)) {
        ReadFromStream(id);
      }
      return;
    }
  }
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

void FairPlayRendererAdapter::ReadFromStream(uint32_t id) {
  Stream& stream = streams_[id];
  DCHECK(!stream.read_pending);
  stream.read_pending = true;
  stream.demuxer_stream->Read(
      1, base::BindOnce(&FairPlayRendererAdapter::OnBuffersRead,
                        weak_factory_.GetWeakPtr(), id, generation_));
}

void FairPlayRendererAdapter::OnBuffersRead(
    uint32_t id,
    uint64_t generation,
    DemuxerStream::Status status,
    DemuxerStream::DecoderBufferVector buffers) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  auto it = streams_.find(id);
  if (it == streams_.end()) {
    return;  // Removed.
  }
  Stream& stream = it->second;
  stream.read_pending = false;
  if (generation != generation_ || flush_cb_) {
    // The stream reports a config change once; apply it even to a read the
    // Flush made stale, or later buffers would run on the old config.
    if (status == DemuxerStream::kConfigChanged && !errored_) {
      HandleConfigChange(stream);
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
      HandleConfigChange(stream);
      OnNeedData(stream.core);
      return;
    case DemuxerStream::kOk:
      break;
  }
  const fp::StreamId core = stream.core;
  for (const scoped_refptr<DecoderBuffer>& buffer : buffers) {
    if (buffer->end_of_stream()) {
      stream.end_of_stream = true;
      core_->SetEndOfStream(core);
      return;
    }
    EnqueueToCore(core, *buffer);
    if (errored_) {
      return;
    }
  }
  OnNeedData(core);
}

void FairPlayRendererAdapter::HandleConfigChange(Stream& stream) {
  fp::Result result;
  // A new config, possibly a new codec (MSE changeType, e.g. an audio
  // language switch from E-AC-3 to AAC): the core builds formats for the
  // samples that follow, protected ones per key ID as they arrive.
  if (stream.core.type == fp::StreamType::kVideo) {
    VideoDecoderConfig config = stream.demuxer_stream->video_decoder_config();
    std::optional<fp::VideoConfig> core_config = CoreConfigIfPlayable(config);
    if (!core_config) {
      LOG(ERROR) << "FairPlay renderer can't play "
                 << config.AsHumanReadableString();
      ReportError(DECODER_ERROR_NOT_SUPPORTED);
      return;
    }
    result = core_->Reconfigure(*core_config);
    client_->OnVideoConfigChange(config);
  } else {
    AudioDecoderConfig config = stream.demuxer_stream->audio_decoder_config();
    std::optional<fp::AudioConfig> core_config = CoreConfigIfPlayable(config);
    if (!core_config) {
      LOG(ERROR) << "FairPlay renderer can't play "
                 << config.AsHumanReadableString();
      ReportError(DECODER_ERROR_NOT_SUPPORTED);
      return;
    }
    result = core_->Reconfigure(*core_config, stream.core.audio_track);
    client_->OnAudioConfigChange(config);
  }
  if (!result.ok()) {
    LOG(ERROR) << "FairPlay renderer config change failed: " << result.message;
    ReportError(DECODER_ERROR_NOT_SUPPORTED);
  }
}

void FairPlayRendererAdapter::EnqueueToCore(fp::StreamId stream,
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
  if (core_->Enqueue(stream, sample) == fp::EnqueueResult::kRejected) {
    LOG(ERROR) << "FairPlay renderer rejected a sample";
    ReportError(PIPELINE_ERROR_DECODE);
    return;
  }
  // A sample held for its key is decoded once the key arrives.
  (stream.type == fp::StreamType::kVideo ? unreported_video_bytes_
                                         : unreported_audio_bytes_) +=
      data.size();
}

void FairPlayRendererAdapter::MaybeFinishFlush() {
  if (!flush_cb_ || core_flush_pending_) {
    return;
  }
  for (const auto& [id, stream] : streams_) {
    if (stream.read_pending) {
      return;
    }
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
