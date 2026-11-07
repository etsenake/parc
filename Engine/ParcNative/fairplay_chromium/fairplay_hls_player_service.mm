// Installed by the reviewed overlay at
// //third_party/parc_fairplay/chromium/fairplay_hls_player_service.mm.
// See fairplay_hls_player_service.h.
#include "third_party/parc_fairplay/chromium/fairplay_hls_player_service.h"

#import <AVFoundation/AVFoundation.h>

#include <cmath>
#include <utility>

#include "base/check.h"
#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/logging.h"
#include "base/memory/raw_ptr.h"
#include "media/base/audio_codecs.h"
#include "media/base/buffering_state.h"
#include "media/base/cdm_context.h"
#include "media/base/pipeline_status.h"
#include "media/base/timestamp_constants.h"
#include "media/base/video_codecs.h"
#include "media/base/waiting.h"
#include "mojo/public/cpp/bindings/message.h"
#include "mojo/public/cpp/bindings/receiver.h"
#include "mojo/public/cpp/system/data_pipe.h"
#include "mojo/public/cpp/system/simple_watcher.h"
#include "net/base/net_errors.h"
#include "third_party/parc_fairplay/chromium/fairplay_hls_track_bridge.h"
#include "third_party/parc_fairplay/chromium/fairplay_task_runner.h"
#include "third_party/parc_fairplay/core/fairplay_hls_keys.h"
#include "third_party/parc_fairplay/core/fairplay_hls_player_internal.h"
#include "ui/accelerated_widget_mac/protected_layer_registry.h"
#include "url/gurl.h"

namespace media {

namespace fp = parc::fairplay;

namespace {

// As MojoRendererService sends the media time while playing.
constexpr auto kTimeUpdateInterval = base::Milliseconds(125);

constexpr uint32_t FourCC(const char (&code)[5]) {
  return (static_cast<uint32_t>(static_cast<uint8_t>(code[0])) << 24) |
         (static_cast<uint32_t>(static_cast<uint8_t>(code[1])) << 16) |
         (static_cast<uint32_t>(static_cast<uint8_t>(code[2])) << 8) |
         static_cast<uint32_t>(static_cast<uint8_t>(code[3]));
}

// The media subtype of the item's first audio format description: Core
// Audio's format IDs for HLS (TS and fMP4), their FairPlay-protected forms,
// and the MP4 sample entry names.
AudioCodec ToAudioCodec(uint32_t fourcc) {
  switch (fourcc) {
    case FourCC("aac "):
    case FourCC("aach"):
    case FourCC("aacp"):
    case FourCC("mp4a"):
    case FourCC("paac"):
    case FourCC("qaac"):
    case FourCC("qach"):
    case FourCC("qacp"):
      return AudioCodec::kAAC;
    case FourCC("ac-3"):
    case FourCC("qac3"):
      return AudioCodec::kAC3;
    case FourCC("ec-3"):
    case FourCC("qec3"):
      return AudioCodec::kEAC3;
    case FourCC("ac-4"):
      return AudioCodec::kAC4;
    case FourCC(".mp3"):
      return AudioCodec::kMP3;
    case FourCC("alac"):
      return AudioCodec::kALAC;
    case FourCC("flac"):
    case FourCC("fLaC"):
      return AudioCodec::kFLAC;
    case FourCC("opus"):
    case FourCC("Opus"):
      return AudioCodec::kOpus;
    default:
      return AudioCodec::kUnknown;
  }
}

VideoCodec ToVideoCodec(uint32_t fourcc) {
  switch (fourcc) {
    case FourCC("avc1"):
    case FourCC("avc3"):
    case FourCC("qavc"):
      return VideoCodec::kH264;
    case FourCC("hvc1"):
    case FourCC("hev1"):
    case FourCC("qhvc"):
    case FourCC("qhev"):
      return VideoCodec::kHEVC;
    case FourCC("dvh1"):
    case FourCC("dvhe"):
    case FourCC("dva1"):
    case FourCC("dvav"):
      return VideoCodec::kDolbyVision;
    case FourCC("av01"):
      return VideoCodec::kAV1;
    case FourCC("vp09"):
      return VideoCodec::kVP9;
    default:
      return VideoCodec::kUnknown;
  }
}

// Seconds as the element sees them: +infinity is media::kInfiniteDuration;
// NaN and -infinity are 0.
base::TimeDelta ToTimeDelta(double seconds) {
  if (std::isnan(seconds) || seconds == -INFINITY) {
    return base::TimeDelta();
  }
  if (seconds == INFINITY) {
    return kInfiniteDuration;
  }
  return base::Seconds(seconds);
}

std::vector<mojom::FairPlayHlsTimeRangePtr> ToRanges(
    const std::vector<fp::HlsTimeRange>& ranges) {
  std::vector<mojom::FairPlayHlsTimeRangePtr> out;
  out.reserve(ranges.size());
  for (const fp::HlsTimeRange& range : ranges) {
    out.push_back(mojom::FairPlayHlsTimeRange::New(ToTimeDelta(range.start),
                                                   ToTimeDelta(range.end)));
  }
  return out;
}

std::optional<base::Time> ToStartDate(std::optional<double> start_date_ms) {
  if (!start_date_ms || !std::isfinite(*start_date_ms)) {
    return std::nullopt;
  }
  return base::Time::FromMillisecondsSinceUnixEpoch(*start_date_ms);
}

// How the element reports the failure, as WebKit maps it: network errors,
// decode errors, and before metadata a source it can't play.
PipelineStatus ToPipelineStatus(fp::HlsError error) {
  switch (error) {
    case fp::HlsError::kNetwork:
      return PIPELINE_ERROR_NETWORK;
    case fp::HlsError::kDecode:
      return PIPELINE_ERROR_DECODE;
    case fp::HlsError::kNotSupported:
      return DEMUXER_ERROR_COULD_NOT_OPEN;
  }
  return PIPELINE_ERROR_NETWORK;
}

bool HasScheme(const std::string& uri, const char* scheme) {
  GURL url(uri);
  return url.is_valid() && url.SchemeIs(scheme);
}

}  // namespace

// One load: the core's HlsLoad, the GPU end of its FairPlayHlsLoad and
// FairPlayHlsLoadClient pipes, and the body pipe's reader. The core owns it;
// destroying it cancels the load. Every core call is the last thing a path
// does, or is followed by a check that the core didn't destroy it.
class FairPlayHlsPlayerService::Load final
    : public fp::HlsLoad,
      public mojom::FairPlayHlsLoadClient {
 public:
  Load(fp::HlsLoadClient* client,
       scoped_refptr<base::SequencedTaskRunner> task_runner)
      : client_(client),
        watcher_(FROM_HERE,
                 mojo::SimpleWatcher::ArmingPolicy::MANUAL,
                 std::move(task_runner)) {}

  Load(const Load&) = delete;
  Load& operator=(const Load&) = delete;

  ~Load() override {
    if (!done_ && load_.is_bound()) {
      load_->Cancel();
    }
  }

  // The render process's ends of the two pipes.
  void Bind(mojo::PendingReceiver<mojom::FairPlayHlsLoad>& load,
            mojo::PendingRemote<mojom::FairPlayHlsLoadClient>& client) {
    load = load_.BindNewPipeAndPassReceiver();
    client = receiver_.BindNewPipeAndPassRemote();
    // Only this pipe's closing counts: it comes after OnComplete on the same
    // pipe, while the FairPlayHlsLoad pipe's closing is unordered with it.
    // Unretained: |this| owns the receiver.
    receiver_.set_disconnect_handler(
        base::BindOnce(&Load::OnClientDisconnected, base::Unretained(this)));
  }

  // mojom::FairPlayHlsLoadClient:
  void OnResponse(mojom::FairPlayHlsResponsePtr response,
                  mojo::ScopedDataPipeConsumerHandle body) override {
    if (done_ || responded_ || !body.is_valid()) {
      receiver_.ReportBadMessage("FairPlayHlsLoadClient.OnResponse");
      Finish(net::ERR_INVALID_RESPONSE);
      return;
    }
    responded_ = true;
    fp::HlsLoadResponse head;
    head.http_status = response->http_status;
    head.mime_type = response->mime_type;
    head.content_length = response->content_length;
    if (response->final_url.is_valid()) {
      head.final_url = response->final_url.spec();
    }
    for (const auto& [name, value] : response->headers) {
      head.headers.emplace_back(name, value);
    }
    body_ = std::move(body);
    // Unretained: |this| owns the watcher.
    watcher_.Watch(body_.get(),
                   MOJO_HANDLE_SIGNAL_READABLE | MOJO_HANDLE_SIGNAL_PEER_CLOSED,
                   MOJO_WATCH_CONDITION_SATISFIED,
                   base::BindRepeating(&Load::OnBodyReady,
                                       base::Unretained(this)));
    base::WeakPtr<Load> weak = weak_factory_.GetWeakPtr();
    client_->OnResponse(head);
    if (weak) {
      watcher_.ArmOrNotify();
    }
  }

  void OnComplete(int32_t net_error) override {
    if (done_ || got_complete_) {
      receiver_.ReportBadMessage("FairPlayHlsLoadClient.OnComplete");
      Finish(net::ERR_INVALID_RESPONSE);
      return;
    }
    got_complete_ = true;
    complete_error_ = net_error > 0 ? net::ERR_FAILED : net_error;
    if (!responded_) {
      Finish(complete_error_ == net::OK ? net::ERR_EMPTY_RESPONSE
                                        : complete_error_);
      return;
    }
    // OnComplete can overtake the body (another pipe): the load ends once the
    // pipe is drained and closed, a failure's partial body delivered first
    // too, so AVFoundation never takes a truncated body as complete.
    if (body_closed_) {
      Finish(complete_error_);
    }
  }

 private:
  void OnBodyReady(MojoResult result, const mojo::HandleSignalsState& state) {
    if (done_) {
      return;
    }
    base::WeakPtr<Load> weak = weak_factory_.GetWeakPtr();
    while (true) {
      base::span<const uint8_t> buffer;
      MojoResult rv =
          body_->BeginReadData(MOJO_BEGIN_READ_DATA_FLAG_NONE, buffer);
      if (rv == MOJO_RESULT_SHOULD_WAIT) {
        watcher_.ArmOrNotify();
        return;
      }
      if (rv != MOJO_RESULT_OK) {
        // Drained, and the render process closed it after the last byte.
        body_closed_ = true;
        watcher_.Cancel();
        body_.reset();
        if (got_complete_) {
          Finish(complete_error_);
        }
        // Otherwise OnComplete finishes the load (or the pipe's closing,
        // with an error).
        return;
      }
      client_->OnData(buffer.data(), buffer.size());
      if (!weak) {
        return;  // The core cancelled the load.
      }
      body_->EndReadData(buffer.size());
    }
  }

  // The render process closes the pipe right after OnComplete, before the
  // body may be drained: then the drain ends the load. Without OnComplete the
  // load was dropped there.
  void OnClientDisconnected() {
    if (!got_complete_) {
      Finish(net::ERR_ABORTED);
    }
  }

  // Reports |net_error| to the core as the load's end; nothing follows.
  void Finish(int net_error) {
    if (done_) {
      return;
    }
    done_ = true;
    watcher_.Cancel();
    body_.reset();
    receiver_.reset();
    load_.reset();
    client_->OnComplete(net_error);
  }

  const raw_ptr<fp::HlsLoadClient> client_;
  mojo::Remote<mojom::FairPlayHlsLoad> load_;
  mojo::Receiver<mojom::FairPlayHlsLoadClient> receiver_{this};
  mojo::ScopedDataPipeConsumerHandle body_;
  mojo::SimpleWatcher watcher_;
  bool responded_ = false;
  bool got_complete_ = false;
  int complete_error_ = net::OK;  // OnComplete's, once it came.
  bool body_closed_ = false;
  bool done_ = false;
  base::WeakPtrFactory<Load> weak_factory_{this};
};

// Forwards the key loader's callbacks, which it posts to the owner sequence,
// to the service that owns both.
class FairPlayHlsPlayerService::KeyLoaderClient final
    : public fp::FairPlayHlsKeyLoaderClient {
 public:
  explicit KeyLoaderClient(FairPlayHlsPlayerService* service)
      : service_(service) {}

  void OnKeyNeeded(const std::string& uri) override {
    service_->OnKeyNeeded(uri);
  }
  void OnKeyLoadingRequest(const std::string& url) override {
    service_->OnKeyLoadingRequest(url);
  }

 private:
  const raw_ptr<FairPlayHlsPlayerService> service_;
};

FairPlayHlsPlayerService::FairPlayHlsPlayerService(
    scoped_refptr<base::SequencedTaskRunner> task_runner,
    CdmContextGetter get_cdm_context,
    mojo::PendingRemote<mojom::FairPlayHlsPlayerClient> client,
    mojo::PendingRemote<mojom::FairPlayHlsPlayerLifetime> lifetime)
    : task_runner_(std::move(task_runner)),
      get_cdm_context_(std::move(get_cdm_context)),
      client_(std::move(client)) {
  if (lifetime.is_valid()) {
    lifetime_.Bind(std::move(lifetime));
  }
}

FairPlayHlsPlayerService::~FairPlayHlsPlayerService() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  weak_factory_.InvalidateWeakPtrs();
  time_update_timer_.Stop();
  if (!layer_token_.is_empty()) {
    // The compositor drops the layer at its next commit.
    ui::ProtectedLayerRegistry::Unregister(layer_token_);
  }
  // The tracks' selection detaches from the item first; the player's shutdown
  // then cancels every load and detaches its layer; the key loader goes once
  // the player hands it nothing more. None calls this object afterwards. The
  // CDM reference goes last.
  tracks_.reset();
  player_.reset();
  key_loader_.reset();
  key_loader_client_.reset();
}

base::RepeatingCallback<void(bool)>
FairPlayHlsPlayerService::GetMuteStateCallback() {
  return base::BindRepeating(
      [](base::WeakPtr<FairPlayHlsPlayerService> service, bool muted) {
        if (service) {
          service->tab_muted_ = muted;
          service->awaiting_mute_state_ = false;
          service->ApplyMuted();
        }
      },
      weak_factory_.GetWeakPtr());
}

void FairPlayHlsPlayerService::SetMuteStateObserverCloser(
    base::ScopedClosureRunner closer) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  mute_state_observer_closer_ = std::move(closer);
  awaiting_mute_state_ = true;
  ApplyMuted();
}

void FairPlayHlsPlayerService::Initialize(const GURL& url,
                                          const std::string& mime_type) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (player_ || errored_) {
    mojo::ReportBadMessage("FairPlayHlsPlayer.Initialize called twice");
    return;
  }
  if (!url.is_valid() || !url.SchemeIsHTTPOrHTTPS() ||
      !fp::FairPlayHlsPlayer::IsSupported()) {
    errored_ = true;
    client_->OnInitialized(nullptr);
    return;
  }
  init_pending_ = true;
  fp::PostTask post_task = fp::PostTaskTo(task_runner_);
  tracks_ = std::make_unique<FairPlayHlsTrackBridge>(client_.get(), post_task);
  player_ = std::make_unique<fp::FairPlayHlsPlayer>(this, this, post_task);
  player_->SetVolume(volume_);
  player_->SetPreservesPitch(preserves_pitch_);
  if (rate_ > 0) {
    player_->SetRate(rate_);
  }
  ApplyMuted();

  fp::Result result = player_->CreateAsset(url.spec(), mime_type);
  if (result.ok()) {
    // The CDM's key loader takes every skd:// request; it must exist before
    // the item routes any (NATIVE_HLS.md "Keys").
    CdmContext* cdm_context =
        cdm_context_ref_ ? cdm_context_ref_->GetCdmContext() : nullptr;
    key_loader_client_ = std::make_unique<KeyLoaderClient>(this);
    key_loader_ = std::make_unique<fp::FairPlayHlsKeyLoader>(
        fp::HlsPlayerAsset(player_->impl()),
        cdm_context ? cdm_context->GetFairPlayCdm() : nullptr,
        key_loader_client_.get(), post_task);
    fp::SetHlsKeyRequestHandler(player_->impl(), key_loader_.get());
    result = player_->Start();
  }
  if (!result.ok()) {
    DLOG(ERROR) << "FairPlay HLS player failed to load: " << result.message;
    errored_ = true;
    FinishInitialize(nullptr);
    return;
  }
  tracks_->Attach(player_->impl());
}

void FairPlayHlsPlayerService::SetCdm(const base::UnguessableToken& cdm_id,
                                      SetCdmCallback callback) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  std::unique_ptr<CdmContextRef> ref = get_cdm_context_.Run(cdm_id);
  CdmContext* cdm_context = ref ? ref->GetCdmContext() : nullptr;
  fp::FairPlayCdm* cdm = cdm_context ? cdm_context->GetFairPlayCdm() : nullptr;
  if (!cdm) {
    std::move(callback).Run(false);
    return;
  }
  if (key_loader_) {
    // The loader keeps the old CDM if the new one can't take the asset.
    fp::Result result = key_loader_->SetCdm(cdm);
    if (!result.ok()) {
      DLOG(ERROR) << "FairPlay HLS key loader refused the CDM: "
                  << result.message;
      std::move(callback).Run(false);
      return;
    }
  }
  // Before Initialize, the key loader is made with it.
  cdm_context_ref_ = std::move(ref);
  std::move(callback).Run(true);
}

void FairPlayHlsPlayerService::Play(double rate) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!(rate > 0)) {
    Pause();
    return;
  }
  rate_ = rate;
  if (player_) {
    player_->SetRate(rate);
  }
  SendTimeUpdate();
  UpdateTimeUpdateTimer();
}

void FairPlayHlsPlayerService::Pause() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  rate_ = 0;
  if (player_) {
    player_->SetRate(0);
  }
  SendTimeUpdate();
  UpdateTimeUpdateTimer();
}

void FairPlayHlsPlayerService::Seek(base::TimeDelta time,
                                    base::TimeDelta tolerance_before,
                                    SeekCallback callback) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!player_ || errored_) {
    std::move(callback).Run(false, time);
    return;
  }
  tracks_->WillSeek();
  auto shared_callback = std::make_shared<SeekCallback>(std::move(callback));
  base::WeakPtr<FairPlayHlsPlayerService> weak = weak_factory_.GetWeakPtr();
  // TimeDelta::Max() (a fast seek backward) reads as infinity.
  player_->Seek(time.InSecondsF(), tolerance_before.InSecondsF(),
                [weak, shared_callback](bool finished) {
    if (weak) {
      weak->OnSeekDone(std::move(*shared_callback), finished);
    }
  });
}

void FairPlayHlsPlayerService::OnSeekDone(SeekCallback callback,
                                          bool finished) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  tracks_->DidSeek();
  SendTimeUpdate();
  std::move(callback).Run(
      finished, player_ ? ToTimeDelta(player_->CurrentTime()) : base::TimeDelta());
}

void FairPlayHlsPlayerService::SetVolume(float volume) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  volume_ = volume;
  if (player_) {
    player_->SetVolume(volume);
  }
}

void FairPlayHlsPlayerService::SetMuted(bool muted) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  page_muted_ = muted;
  ApplyMuted();
}

void FairPlayHlsPlayerService::SetPreservesPitch(bool preserves_pitch) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  preserves_pitch_ = preserves_pitch;
  if (player_) {
    player_->SetPreservesPitch(preserves_pitch);
  }
}

void FairPlayHlsPlayerService::ProvideClearKey(
    const std::string& key_id,
    const std::vector<uint8_t>& key) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  auto it = clear_key_uris_.find(key_id);
  if (it == clear_key_uris_.end() || !player_) {
    return;
  }
  player_->FulfillKeyRequests(it->second, key);
}

void FairPlayHlsPlayerService::SetAudioTrackEnabled(const std::string& key,
                                                    bool enabled) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (tracks_) {
    tracks_->SetAudioTrackEnabled(key, enabled);
  }
}

void FairPlayHlsPlayerService::SetTextTrackMode(
    const std::string& key,
    mojom::FairPlayHlsTextTrackMode mode) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (tracks_) {
    tracks_->SetTextTrackMode(key, mode);
  }
}

// WebKit's AVFoundation player has no suspended-loading state: AVPlayer
// keeps managing its own buffer, as in Safari.
void FairPlayHlsPlayerService::Suspend() {}
void FairPlayHlsPlayerService::Resume() {}

void FairPlayHlsPlayerService::OnMetadata(const fp::HlsMetadata& metadata) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!init_pending_ || errored_) {
    return;
  }
  auto out = mojom::FairPlayHlsMetadata::New();
  out->has_audio = metadata.has_audio;
  out->has_video = metadata.has_video;
  out->natural_size =
      gfx::Size(metadata.natural_width, metadata.natural_height);
  out->audio_codec = ToAudioCodec(metadata.audio_fourcc);
  out->video_codec = ToVideoCodec(metadata.video_fourcc);
  out->duration = ToTimeDelta(metadata.duration);
  out->start_date = ToStartDate(metadata.start_date_ms);
  out->seekable = ToRanges(metadata.seekable);
  out->buffered = ToRanges(metadata.loaded);
  // The selection's list now; earlier lists fold into it, later ones go out
  // as OnTracksChanged (FairPlayHlsTrackBridge).
  out->tracks = tracks_->TakeTracksForInitialize();

  has_video_ = metadata.has_video;
  natural_size_ = out->natural_size;
  if (has_video_) {
    // Before OnInitialized: the token must name a registered layer when the
    // render process paints it.
    RegisterLayer();
  }
  FinishInitialize(std::move(out));
}

void FairPlayHlsPlayerService::FinishInitialize(
    mojom::FairPlayHlsMetadataPtr metadata) {
  init_pending_ = false;
  initialized_ = !metadata.is_null();
  client_->OnInitialized(std::move(metadata));
  if (!initialized_) {
    return;
  }
  // State the item reported before OnInitialized, in order.
  std::vector<base::OnceClosure> pending = std::move(pending_client_calls_);
  for (base::OnceClosure& call : pending) {
    std::move(call).Run();
  }
  SendTimeUpdate();
  UpdateTimeUpdateTimer();
}

void FairPlayHlsPlayerService::OnBufferingStateChange(bool have_enough) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  BufferingState state =
      have_enough ? BUFFERING_HAVE_ENOUGH : BUFFERING_HAVE_NOTHING;
  if (!initialized_) {
    // Sent right after OnInitialized (the element can't use it before).
    pending_client_calls_.push_back(base::BindOnce(
        [](base::WeakPtr<FairPlayHlsPlayerService> service,
           BufferingState state) {
          if (service) {
            service->client_->OnBufferingStateChange(state);
          }
        },
        weak_factory_.GetWeakPtr(), state));
    return;
  }
  SendTimeUpdate();
  client_->OnBufferingStateChange(state);
}

void FairPlayHlsPlayerService::OnLoadedRangesChange(
    const std::vector<fp::HlsTimeRange>& loaded) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  // Before OnInitialized the metadata carries the newer value.
  if (initialized_) {
    client_->OnBufferedRangesChanged(ToRanges(loaded));
  }
}

void FairPlayHlsPlayerService::OnSeekableRangesChange(
    const std::vector<fp::HlsTimeRange>& seekable) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (initialized_) {
    client_->OnSeekableRangesChanged(ToRanges(seekable));
  }
}

void FairPlayHlsPlayerService::OnDurationChange(double seconds) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (initialized_) {
    client_->OnDurationChange(ToTimeDelta(seconds));
  }
}

void FairPlayHlsPlayerService::OnStartDateChange(
    std::optional<double> start_date_ms) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (initialized_) {
    client_->OnStartDateChanged(ToStartDate(start_date_ms));
  }
}

void FairPlayHlsPlayerService::OnNaturalSizeChange(int32_t width,
                                                   int32_t height) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  gfx::Size size(width, height);
  if (!initialized_ || size == natural_size_) {
    return;
  }
  natural_size_ = size;
  client_->OnNaturalSizeChange(size);
}

void FairPlayHlsPlayerService::OnEnded() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!initialized_ || errored_) {
    return;
  }
  SendTimeUpdate();
  client_->OnEnded();
}

void FairPlayHlsPlayerService::OnError(fp::HlsError error,
                                       const std::string& message) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (errored_) {
    return;
  }
  errored_ = true;
  time_update_timer_.Stop();
  // Before metadata the demuxer's initialization fails with this status:
  // OnError comes first, then OnInitialized(null), on the same pipe.
  client_->OnError(ToPipelineStatus(error), message);
  if (init_pending_) {
    FinishInitialize(nullptr);
  }
}

void FairPlayHlsPlayerService::OnKeyRequest(const std::string& uri) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  // skd:// requests go to the key loader; the core reports clearkey:// ones
  // here. webkitneedkey first, for every request, repeats included.
  if (HasScheme(uri, "clearkey")) {
    clear_key_uris_[fp::HlsClearKeyId(uri)] = uri;
    client_->OnKeyRequest(uri);
    return;
  }
  player_->FailKeyRequests(uri, "no key source for this scheme");
}

void FairPlayHlsPlayerService::OnOutputObscuredChange(bool obscured) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (key_loader_) {
    key_loader_->SetOutputObscured(obscured);
  }
}

void FairPlayHlsPlayerService::OnKeyNeeded(const std::string& uri) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  // No session asked for this key yet: encrypted and waitingforkey, after
  // the request's webkitneedkey (OnKeyLoadingRequest).
  client_->OnEncrypted("skd", std::vector<uint8_t>(uri.begin(), uri.end()));
  client_->OnWaiting(WaitingReason::kNoDecryptionKey);
}

void FairPlayHlsPlayerService::OnKeyLoadingRequest(const std::string& url) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  client_->OnKeyRequest(url);
}

void FairPlayHlsPlayerService::OnVideoFrameCounts(uint32_t decoded,
                                                  uint32_t dropped) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!initialized_) {
    return;
  }
  PipelineStatistics delta;
  delta.video_frames_decoded = decoded;
  delta.video_frames_dropped = dropped;
  client_->OnStatisticsUpdate(delta);
}

std::unique_ptr<fp::HlsLoad> FairPlayHlsPlayerService::StartLoad(
    const fp::HlsLoadRequest& request,
    fp::HlsLoadClient* load_client) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  auto load = std::make_unique<Load>(load_client, task_runner_);
  auto mojo_request = mojom::FairPlayHlsRequest::New();
  mojo_request->url = GURL(request.url);
  mojo_request->method = request.method;
  for (const auto& [name, value] : request.headers) {
    mojo_request->headers.insert_or_assign(name, value);
  }
  mojo::PendingReceiver<mojom::FairPlayHlsLoad> load_receiver;
  mojo::PendingRemote<mojom::FairPlayHlsLoadClient> load_client_remote;
  load->Bind(load_receiver, load_client_remote);
  // A render process that is gone closes both pipes: the load then ends
  // with an error from its disconnect handler, never inside this call.
  client_->StartLoad(std::move(mojo_request), std::move(load_receiver),
                     std::move(load_client_remote));
  return load;
}

void FairPlayHlsPlayerService::RegisterLayer() {
  AVPlayerLayer* layer = fp::HlsPlayerLayer(player_->impl());
  if (!layer) {
    return;
  }
  base::UnguessableToken token = base::UnguessableToken::Create();
  if (!ui::ProtectedLayerRegistry::Register(token, layer)) {
    LOG(ERROR) << "FairPlay HLS player layer registration failed";
    return;
  }
  layer_token_ = token;
  client_->OnLayerRegistered(layer_token_, natural_size_);
}

void FairPlayHlsPlayerService::ApplyMuted() {
  if (player_) {
    player_->SetMuted(page_muted_ || tab_muted_ || awaiting_mute_state_);
  }
}

void FairPlayHlsPlayerService::SendTimeUpdate() {
  if (!initialized_ || errored_ || !player_) {
    return;
  }
  client_->OnTimeUpdate(ToTimeDelta(player_->CurrentTime()), player_->Rate(),
                        base::TimeTicks::Now());
}

void FairPlayHlsPlayerService::UpdateTimeUpdateTimer() {
  if (initialized_ && !errored_ && rate_ > 0) {
    if (!time_update_timer_.IsRunning()) {
      // Unretained: |this| owns the timer.
      time_update_timer_.Start(
          FROM_HERE, kTimeUpdateInterval,
          base::BindRepeating(&FairPlayHlsPlayerService::SendTimeUpdate,
                              base::Unretained(this)));
    }
  } else {
    time_update_timer_.Stop();
  }
}

}  // namespace media
