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

#include <memory>
#include <optional>
#include <string>
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
  void OnTimeUpdate(base::TimeDelta time,
                    double rate,
                    base::TimeTicks capture_time) override;
  void OnBufferingStateChange(media::BufferingState state) override;
  void OnBufferedRangesChanged(
      std::vector<media::mojom::FairPlayHlsTimeRangePtr> buffered) override;
  void OnSeekableRangesChanged(
      std::vector<media::mojom::FairPlayHlsTimeRangePtr> seekable) override;
  void OnDurationChange(base::TimeDelta duration) override;
  void OnStartDateChanged(std::optional<base::Time> start_date) override;
  void OnTracksChanged(
      std::vector<media::mojom::FairPlayHlsTrackPtr> tracks) override;
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
                      media::PipelineStatusCallback status_cb,
                      bool success);
  void OnPlayerDisconnected();
  // Sends the player the CDM ID `cdm_context` names, once per ID.
  void SendCdm(media::CdmContext* cdm_context,
               NativeHlsSource::CdmAttachedCB cdm_attached_cb);
  // A fatal error: to the renderer facade when one listens, otherwise to the
  // pipeline through the demuxer host.
  void ReportError(media::PipelineStatus status);

  const GURL url_;
  const std::string mime_type_;
  const scoped_refptr<base::SequencedTaskRunner> media_task_runner_;
  const std::unique_ptr<media::MediaLog> media_log_;
  const EncryptedMediaInitDataCB encrypted_media_init_data_cb_;
  const base::RepeatingCallback<void(const std::string&)> key_request_cb_;
  const StartLoadCallback start_load_cb_;

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

  // GetMediaTime() may be called from any thread.
  mutable base::Lock time_lock_;
  base::TimeDelta time_ GUARDED_BY(time_lock_);
  double rate_ GUARDED_BY(time_lock_) = 0;
  base::TimeTicks capture_time_ GUARDED_BY(time_lock_);
  base::TimeDelta duration_ GUARDED_BY(time_lock_) = media::kInfiniteDuration;
  std::optional<base::TimeDelta> seek_time_ GUARDED_BY(time_lock_);
  // The element's seekable window and getStartDate() as the player computed
  // them (one range or none; GetParcNativeTimeline()).
  media::Ranges<base::TimeDelta> seekable_ GUARDED_BY(time_lock_);
  std::optional<base::Time> start_date_ GUARDED_BY(time_lock_);

  SEQUENCE_CHECKER(sequence_checker_);
  base::WeakPtrFactory<NativeHlsDemuxer> weak_factory_{this};
};

}  // namespace parc::fairplay

#endif  // CONTENT_RENDERER_MEDIA_FAIRPLAY_NATIVE_HLS_DEMUXER_H_
