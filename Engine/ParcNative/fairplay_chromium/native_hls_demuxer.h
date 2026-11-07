// Installed by the reviewed overlay at //content/renderer/media/fairplay/.
// Render-process side of Safari's native HLS route (NATIVE_HLS.md beside this
// file's source in the Parc repository). Safari plays <video src="….m3u8">
// through AVPlayer; Parc's AVPlayer lives in the GPU process next to the
// FairPlay CDM (media.mojom.FairPlayHlsPlayer). NativeHlsDemuxer owns the
// connection to it: Initialize() opens the asset and waits for AVFoundation's
// metadata, then exposes one placeholder stream per kind that carries the
// codec and size AVFoundation reports and never delivers a buffer. The
// pipeline then asks for RendererType::kFairPlayHls, whose NativeHlsRenderer
// drives this player through the NativeHlsSource interface.
#ifndef CONTENT_RENDERER_MEDIA_FAIRPLAY_NATIVE_HLS_DEMUXER_H_
#define CONTENT_RENDERER_MEDIA_FAIRPLAY_NATIVE_HLS_DEMUXER_H_

#include <stdint.h>

#include <map>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/sequence_checker.h"
#include "base/synchronization/lock.h"
#include "base/task/sequenced_task_runner.h"
#include "base/thread_annotations.h"
#include "base/time/time.h"
#include "base/unguessable_token.h"
#include "media/base/buffering_state.h"
#include "media/base/demuxer.h"
#include "media/base/pipeline_status.h"
#include "media/base/ranges.h"
#include "media/base/renderer_factory.h"
#include "media/base/waiting.h"
#include "media/mojo/mojom/renderer_extensions.mojom.h"
#include "mojo/public/cpp/bindings/pending_receiver.h"
#include "mojo/public/cpp/bindings/pending_remote.h"
#include "mojo/public/cpp/bindings/receiver.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "ui/gfx/geometry/size.h"
#include "ui/gfx/geometry/size_f.h"
#include "url/gurl.h"

namespace media {
class CdmContext;
class MediaLog;
}  // namespace media

namespace parc::fairplay {

// The GPU player behind a NativeHlsDemuxer, as its renderer facade sees it
// (MediaResource::GetParcNativeHlsSource()). Media thread, except
// GetMediaTime().
class NativeHlsSource {
 public:
  // The facade's side of the player's reports. Calls arrive on the media
  // thread while a client is set.
  class Client {
   public:
    virtual void OnSourceBufferingStateChange(media::BufferingState state) = 0;
    virtual void OnSourceEnded() = 0;
    virtual void OnSourceError(media::PipelineStatus status) = 0;
    virtual void OnSourceStatisticsUpdate(
        const media::PipelineStatistics& delta) = 0;
    virtual void OnSourceWaiting(media::WaitingReason reason) = 0;
    virtual void OnSourceNaturalSizeChange(const gfx::Size& size) = 0;
    virtual void OnSourceLayerRegistered(
        const base::UnguessableToken& layer_token,
        const gfx::Size& natural_size) = 0;

   protected:
    virtual ~Client() = default;
  };

  // Sets the facade that hears the player, or clears it with null. A new
  // client first hears the display layer and natural size already known, and
  // that the player waits for a key if it does.
  virtual void SetClient(Client* client) = 0;

  // AVPlayer's rate: Play() with `rate` > 0, Pause() for 0.
  virtual void Play(double rate) = 0;
  virtual void Pause() = 0;
  virtual void SetVolume(float volume) = 0;
  virtual void SetPreservesPitch(bool preserves_pitch) = 0;
  // Hands the player the frame's CDM `cdm_context` names (its CDM ID).
  // `cdm_attached_cb` answers whether the player took it.
  using CdmAttachedCB = base::OnceCallback<void(bool)>;
  virtual void SetCdm(media::CdmContext* cdm_context,
                      CdmAttachedCB cdm_attached_cb) = 0;

  // The item's buffering state as AVFoundation last reported it.
  virtual media::BufferingState GetBufferingState() const = 0;

  // The media time the GPU player last reported, advanced at its rate since
  // then and kept within [0, duration]. During a seek, the seek target. Any
  // thread.
  virtual base::TimeDelta GetMediaTime() = 0;

  virtual base::WeakPtr<NativeHlsSource> GetWeakPtr() = 0;

 protected:
  virtual ~NativeHlsSource() = default;
};

// The media time a player reported as `time` at `capture_time`, advancing at
// `rate`, seen at `now`: never below zero nor past a known `duration`
// (media::kInfiniteDuration for live).
base::TimeDelta InterpolateNativeHlsTime(base::TimeDelta time,
                                         double rate,
                                         base::TimeTicks capture_time,
                                         base::TimeTicks now,
                                         base::TimeDelta duration);

class NativeHlsDemuxer final : public media::Demuxer,
                               public NativeHlsSource,
                               public media::mojom::FairPlayHlsPlayerClient {
 public:
  // Answers AVFoundation's loads (FairPlayHlsPlayerClient.StartLoad) through
  // the element's loader (blink::FairPlayHlsLoader); run on the media thread.
  using StartLoadCallback = media::ParcNativeHlsDemuxerParams::StartLoadCB;

  // Made on the main thread with the player's endpoints, already connected
  // through the frame's InterfaceFactory; everything else runs on
  // `params.media_task_runner`. Without `params.start_load_cb` every load
  // fails.
  NativeHlsDemuxer(
      media::ParcNativeHlsDemuxerParams params,
      mojo::PendingRemote<media::mojom::FairPlayHlsPlayer> player,
      mojo::PendingReceiver<media::mojom::FairPlayHlsPlayerClient> client);
  NativeHlsDemuxer(const NativeHlsDemuxer&) = delete;
  NativeHlsDemuxer& operator=(const NativeHlsDemuxer&) = delete;
  ~NativeHlsDemuxer() override;

  // media::MediaResource.
  std::vector<raw_ptr<media::DemuxerStream>> GetAllStreams() override;
  NativeHlsSource* GetParcNativeHlsSource() override;

  // media::Demuxer.
  std::string GetDisplayName() const override;
  media::DemuxerType GetDemuxerType() const override;
  void Initialize(media::DemuxerHost* host,
                  media::PipelineStatusCallback status_cb) override;
  void AbortPendingReads() override;
  void StartWaitingForSeek(base::TimeDelta seek_time) override;
  void CancelPendingSeek(base::TimeDelta seek_time) override;
  void Seek(base::TimeDelta time,
            media::PipelineStatusCallback status_cb) override;
  // HTMLMediaElement.fastSeek: AVPlayer lands within the tolerance.
  void ParcSetFastSeek(base::TimeDelta target,
                       base::TimeDelta tolerance_before) override;
  std::optional<base::TimeDelta> ParcTakeFastSeekLanding() override;
  // Main thread: posts the player's PrepareToPlay to the media thread.
  void ParcPrepareToPlay() override;
  bool IsSeekable() const override;
  void Stop() override;
  base::TimeDelta GetStartTime() const override;
  base::Time GetTimelineOffset() const override;
  int64_t GetMemoryUsage() const override;
  std::optional<media::container_names::MediaContainerName>
  GetContainerForMetrics() const override;
  void OnTracksChanged(media::DemuxerStream::Type track_type,
                       std::optional<media::MediaTrack::Id> track_id,
                       base::TimeDelta curr_time,
                       TrackChangeCB change_completed_cb) override;
  void SetPlaybackRate(double rate) override;
  void SetCdmForNativePlayer(media::CdmContext* cdm_context) override;
  std::optional<ParcNativeTimeline> GetParcNativeTimeline() const override;
  void ParcProvideClearKey(const std::string& key_id,
                           const std::vector<uint8_t>& key) override;

  // NativeHlsSource.
  void SetClient(NativeHlsSource::Client* client) override;
  void Play(double rate) override;
  void Pause() override;
  void SetVolume(float volume) override;
  void SetPreservesPitch(bool preserves_pitch) override;
  void SetCdm(media::CdmContext* cdm_context,
              NativeHlsSource::CdmAttachedCB cdm_attached_cb) override;
  media::BufferingState GetBufferingState() const override;
  base::TimeDelta GetMediaTime() override;
  base::WeakPtr<NativeHlsSource> GetWeakPtr() override;

  // media::mojom::FairPlayHlsPlayerClient.
  void StartLoad(
      media::mojom::FairPlayHlsRequestPtr request,
      mojo::PendingReceiver<media::mojom::FairPlayHlsLoad> load,
      mojo::PendingRemote<media::mojom::FairPlayHlsLoadClient> client)
      override;
  void OnInitialized(media::mojom::FairPlayHlsMetadataPtr metadata) override;
  void OnTimeUpdate(base::TimeDelta time,
                    double rate,
                    base::TimeTicks capture_time) override;
  void OnTimeJumpedBackward(uint32_t seeks_received) override;
  void OnBufferingStateChange(media::BufferingState state) override;
  void OnReadyStateChanged(media::mojom::FairPlayHlsReadyState state) override;
  void OnMediaTypesChanged(bool has_audio, bool has_video) override;
  void OnBufferedRangesChanged(
      std::vector<media::mojom::FairPlayHlsTimeRangePtr> buffered) override;
  void OnSeekableRangesChanged(
      std::vector<media::mojom::FairPlayHlsTimeRangePtr> seekable) override;
  void OnDurationChange(base::TimeDelta duration) override;
  void OnStartDateChanged(std::optional<base::Time> start_date) override;
  void OnTracksChanged(
      std::vector<media::mojom::FairPlayHlsTrackPtr> tracks) override;
  void OnTextCues(const std::string& track_key,
                  std::vector<media::mojom::FairPlayHlsCuePtr> cues) override;
  void OnDataCues(const std::string& track_key,
                  std::vector<media::mojom::FairPlayHlsDataCuePtr> cues) override;
  void OnNaturalSizeChange(const gfx::Size& size) override;
  void OnLayerRegistered(const base::UnguessableToken& layer_token,
                         const gfx::Size& natural_size) override;
  void OnStatisticsUpdate(const media::PipelineStatistics& delta) override;
  void OnEncrypted(const std::string& init_data_type,
                   const std::vector<uint8_t>& init_data) override;
  void OnKeyRequest(const std::string& key_uri) override;
  void OnWaiting(media::WaitingReason reason) override;
  void OnEnded() override;
  void OnError(const media::PipelineStatus& status,
               const std::string& message) override;

  // The status a failed Initialize() reports: the error the player sent
  // first (its item failed: a network, decode or format error as Safari maps
  // them), or DEMUXER_ERROR_COULD_NOT_OPEN when it sent none.
  static media::PipelineStatus InitializeFailureStatus(
      std::optional<media::PipelineStatus> reported_error);

 private:
  class PlaceholderStream;

  void OnPlayerInitialized(bool success,
                           media::mojom::FairPlayHlsMetadataPtr metadata);
  void OnPlayerSeeked(base::TimeDelta time,
                      bool fast,
                      media::PipelineStatusCallback status_cb,
                      bool success,
                      base::TimeDelta current_time);
  void OnPlayerDisconnected();
  // The player's track list to the element: its audio tracks and its text
  // tracks as in-band text tracks (NATIVE_HLS.md Tracks).
  void ApplyTracks(
      const std::vector<media::mojom::FairPlayHlsTrackPtr>& tracks);
  void ForwardTextCues(
      const std::string& track_key,
      const std::vector<media::mojom::FairPlayHlsCuePtr>& cues);
  void ForwardDataCues(
      const std::string& track_key,
      const std::vector<media::mojom::FairPlayHlsDataCuePtr>& cues);
  // TextTrack.mode and AudioTrack.enabled from the element, on to the
  // player.
  void SetTextTrackMode(const std::string& key,
                        media::ParcInbandTextTrackMode mode);
  void SetAudioTrackEnabled(const std::string& key, bool enabled);
  // Sends the player the CDM ID `cdm_context` names unless it was the last one
  // sent; an offer of that one waits for the player's answer to it.
  void SendCdm(media::CdmContext* cdm_context,
               NativeHlsSource::CdmAttachedCB cdm_attached_cb);
  // Sends `cdm_id` (null detaches) as the next SetCdm.
  void SendCdmId(const std::optional<base::UnguessableToken>& cdm_id,
                 NativeHlsSource::CdmAttachedCB cdm_attached_cb);
  // The player's answer to the `cdm_set`th SetCdm.
  void OnCdmSet(uint64_t cdm_set, bool success);
  // A fatal error: to the renderer facade when one listens, otherwise to the
  // pipeline through the demuxer host.
  void ReportError(media::PipelineStatus status);

  const GURL url_;
  const std::string mime_type_;
  // The element's size in points and its display's scale when the demuxer
  // was made, for the player's layer (WebKit's initial video layer size).
  const gfx::SizeF video_layer_size_;
  const float video_layer_scale_;
  // The element prepares to play (WebKit's prepareToPlay): sent with
  // Initialize, or as PrepareToPlay once the player is bound.
  bool prepare_to_play_;
  const scoped_refptr<base::SequencedTaskRunner> media_task_runner_;
  const std::unique_ptr<media::MediaLog> media_log_;
  const EncryptedMediaInitDataCB encrypted_media_init_data_cb_;
  const base::RepeatingCallback<void(const std::string&)> key_request_cb_;
  const base::RepeatingCallback<void(media::ParcNativeHlsReadyState)>
      ready_state_cb_;
  const base::RepeatingCallback<void(bool, bool)> media_types_cb_;
  const base::RepeatingClosure time_jumped_cb_;
  const StartLoadCallback start_load_cb_;
  // The element's tracks; posts to the main thread. Null in unit tests.
  const std::unique_ptr<media::TrackManager> track_manager_;
  // The client pipe can overtake the Initialize reply: track lists and cues
  // that arrive first wait for it, the newest list replacing the reply's.
  bool tracks_ready_ = false;
  std::optional<std::vector<media::mojom::FairPlayHlsTrackPtr>> pending_tracks_;
  std::vector<
      std::pair<std::string, std::vector<media::mojom::FairPlayHlsCuePtr>>>
      pending_cues_;
  // Data cues for the metadata track, likewise.
  std::vector<std::pair<std::string,
                        std::vector<media::mojom::FairPlayHlsDataCuePtr>>>
      pending_data_cues_;

  // Bound on the media thread in Initialize().
  mojo::PendingRemote<media::mojom::FairPlayHlsPlayer> pending_player_;
  mojo::PendingReceiver<media::mojom::FairPlayHlsPlayerClient>
      pending_client_receiver_;
  mojo::Remote<media::mojom::FairPlayHlsPlayer> player_;
  mojo::Receiver<media::mojom::FairPlayHlsPlayerClient> client_receiver_{
      this};

  raw_ptr<media::DemuxerHost> host_ = nullptr;
  media::PipelineStatusCallback init_cb_;
  // The first error the player reported before its metadata.
  std::optional<media::PipelineStatus> init_error_;
  bool stopped_ = false;

  std::vector<std::unique_ptr<PlaceholderStream>> streams_;

  raw_ptr<NativeHlsSource::Client> client_ = nullptr;
  media::BufferingState buffering_state_ = media::BUFFERING_HAVE_NOTHING;
  bool waiting_for_key_ = false;
  std::optional<base::UnguessableToken> layer_token_;
  gfx::Size natural_size_;
  // The CDM the player was given, by ID, and a CDM handed over before the
  // player was bound.
  std::optional<base::UnguessableToken> cdm_id_;
  raw_ptr<media::CdmContext> pending_cdm_context_ = nullptr;
  // SetCdm calls sent so far, detaches included (`cdm_id_` went with the
  // last unless it was one), and the offers of each one the player hasn't
  // answered.
  uint64_t cdm_sets_ = 0;
  std::map<uint64_t, std::vector<NativeHlsSource::CdmAttachedCB>>
      unanswered_cdm_offers_;

  // GetMediaTime() may be called from any thread.
  mutable base::Lock time_lock_;
  base::TimeDelta time_ GUARDED_BY(time_lock_);
  double rate_ GUARDED_BY(time_lock_) = 0;
  base::TimeTicks capture_time_ GUARDED_BY(time_lock_);
  base::TimeDelta duration_ GUARDED_BY(time_lock_) = media::kInfiniteDuration;
  std::optional<base::TimeDelta> seek_time_ GUARDED_BY(time_lock_);
  // A fast seek (target, tolerance) set for the next Seek() to its target,
  // and where the last fast seek landed (ParcSetFastSeek and
  // ParcTakeFastSeekLanding).
  std::optional<std::pair<base::TimeDelta, base::TimeDelta>>
      requested_fast_seek_ GUARDED_BY(time_lock_);
  std::optional<base::TimeDelta> fast_seek_landing_ GUARDED_BY(time_lock_);
  // Seeks sent to the player, and whether it jumped back after finishing the
  // one in flight here, so that seek keeps the time it jumped to.
  uint32_t seeks_sent_ = 0;
  bool jumped_after_seek_ GUARDED_BY(time_lock_) = false;
  // The element's seekable window and getStartDate() as the player computed
  // them (one range or none; GetParcNativeTimeline()).
  media::Ranges<base::TimeDelta> seekable_ GUARDED_BY(time_lock_);
  std::optional<base::Time> start_date_ GUARDED_BY(time_lock_);

  SEQUENCE_CHECKER(sequence_checker_);
  base::WeakPtrFactory<NativeHlsDemuxer> weak_factory_{this};
  // Made at construction, for tasks other threads post to the media thread.
  base::WeakPtr<NativeHlsDemuxer> weak_this_ = weak_factory_.GetWeakPtr();
};

}  // namespace parc::fairplay

#endif  // CONTENT_RENDERER_MEDIA_FAIRPLAY_NATIVE_HLS_DEMUXER_H_
