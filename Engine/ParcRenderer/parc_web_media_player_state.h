// Copyright 2026 Parc contributors.
#ifndef THIRD_PARTY_BLINK_RENDERER_PLATFORM_MEDIA_PARC_WEB_MEDIA_PLAYER_STATE_H_
#define THIRD_PARTY_BLINK_RENDERER_PLATFORM_MEDIA_PARC_WEB_MEDIA_PLAYER_STATE_H_

#include <stdint.h>

#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "base/memory/raw_ref.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/time/time.h"
#include "build/build_config.h"
#include "components/viz/common/surfaces/frame_sink_id.h"
#include "media/base/callback_registry.h"
#include "media/base/cdm_context.h"
#include "media/base/eme_constants.h"
#include "media/base/media_track.h"
#include "media/base/parc_native_hls_demuxer_params.h"
#include "media/base/parc_native_hls_source.h"
#include "media/base/pipeline_metadata.h"
#include "media/filters/chunk_demuxer.h"
#include "third_party/blink/public/platform/parc_web_media_player_extension.h"
#include "third_party/blink/public/platform/web_content_decryption_module_result.h"
#include "third_party/blink/public/platform/web_media_player.h"
#include "third_party/blink/renderer/platform/media/multi_buffer_data_source.h"
#include "third_party/blink/renderer/platform/media/parc_media_task_runners.h"
#include "third_party/blink/renderer/platform/platform_export.h"

namespace blink {

#if BUILDFLAG(IS_MAC)
class FairPlayHlsLoader;
#endif
class WebLocalFrame;
class WebMediaPlayerImpl;

class PLATFORM_EXPORT ParcWebMediaPlayerState
    : public ParcWebMediaPlayerExtension {
 public:
  ParcWebMediaPlayerState(
      WebMediaPlayerImpl& player,
      scoped_refptr<ParcFrameTaskRunner> frame_task_runner);
  ParcWebMediaPlayerState(const ParcWebMediaPlayerState&) = delete;
  ParcWebMediaPlayerState& operator=(const ParcWebMediaPlayerState&) = delete;
  ~ParcWebMediaPlayerState() override;

  void ParcSetCastPrompted(bool prompted) override;
  void ParcOnFrozenInBackForwardCache() override;
  void ParcSetPageHidden(std::optional<bool> is_page_hidden) override;
  bool ParcMoveToFrame(ParcFrameServices services) override;
  void ParcReportStateToClient() override;
  double ParcStartDate() const override;
  void ParcFastSeek(double seconds, double tolerance_before) override;
#if BUILDFLAG(IS_MAC)
  void ParcProvideClearKey(std::string_view key_id,
                           base::span<const uint8_t> key) override;
  void ParcSetPlaybackTarget(std::string_view output_context_id,
                             bool should_play) override;
  void ParcSetWirelessVideoPlaybackDisabled(bool disabled) override;
  bool ParcSupportsPlaybackTarget() const override;
#endif
  void ParcEnabledAudioTracksChanged(
      const std::vector<WebMediaPlayer::TrackId>& enabled_track_ids) override;

  void SetWaitingForKey(bool waiting);
  void SourceKeyChanged(const std::string& id,
                        media::EmeInitDataType init_data_type,
                        const std::vector<uint8_t>& init_data);
  void RecheckSourceKeys();
#if BUILDFLAG(IS_MAC)
  void OnCdmEvent(media::CdmContext::Event event);
  void WaitForStalledKey();
  void CheckWaitedKey();
#endif

 private:
  friend class WebMediaPlayerImpl;
  friend class ParcWebMediaPlayerImplTest;

  void CheckSourceKey(const std::string& id);

  bool MoveToFrame(WebLocalFrame& frame);
  base::TimeDelta PipelineMediaTime() const;
  base::TimeDelta PipelineSeekTime(base::TimeDelta time) const;
  bool TakeEncryptedMediaInitData(media::EmeInitDataType init_data_type,
                                  const std::vector<uint8_t>& init_data);
  void OnChunkDemuxerOpened(media::ChunkDemuxer& demuxer);
  bool MonitorsSourceBuffers() const;
  void MonitorSourceBuffers(bool seek_start = false);
  bool UrlSeekKeepsReadyState(base::TimeDelta time) const;
  void FinishUrlSeekAtFrame();
  void OnUrlSeekFrame(uint64_t seek_id);
  void DidFinishSeek();
  void SetRemoteRendering(bool remote_rendering);
  void UpdateLoadsForCast();
  void RestrictDemuxerCanChangeType(
      media::ChunkDemuxer::ChangeTypeFilter filter);
  void SetDemuxerClearDolbyVisionAllowed(bool allowed);
  bool DemuxerPrefersFairPlayRenderer();
  void SetDemuxerFastSeek(base::TimeDelta target,
                          base::TimeDelta tolerance_before);
#if BUILDFLAG(IS_MAC)
  struct RouteSwitch {
    double duration;
    std::optional<WebMediaPlayer::ReadyState> ready_state;
    base::TimeDelta time;
  };

  std::unique_ptr<media::Demuxer> CreateNativeHlsDemuxer(
      media::ParcNativeHlsDemuxerParams params);
  void NativeHlsMediaTypesChanged(bool has_audio, bool has_video);
  void NativeHlsTimeJumped();
  void NativeHlsReadyStateChanged(media::ParcNativeHlsReadyState state);
  void ApplyNativeHlsReadyState();
  bool PlaysNativeHls() const;
  void UpdateRouteForPlaybackTarget();
  void SwitchRoute(bool native);
  void RestartOnRoute();
  void CheckFileTargetSupport();
  void EndRouteSwitchForError();
  parc::fairplay::NativeHlsSource::FileTracks FileTrackChoices() const;
  void SendFileTrackChoices();
  std::optional<RouteSwitch> TakeSeekedRouteSwitch();
  void FinishSeekedRouteSwitch(const std::optional<RouteSwitch>& route_switch);
  bool DetachFairPlayCdm(WebContentDecryptionModuleResult& result);
  void InvalidateSourceKeyChecks();
  void WillAttachCdm();
  void DidAttachCdm();
  void DidFailToAttachCdm();
  bool ClearDolbyVisionAllowed();
  void SwitchToFairPlayIfNeeded();
  void HandOffOrRestart();
  void HandOffAfterSeek();
  void OnHandOff(bool handed_off);
  bool FairPlayPlaysCurrentStreams() const;
  void OnSourceBufferStreamsAdded(
      const media::PipelineMetadata& added,
      const std::vector<media::ChunkDemuxer::ParcAddedTrack>& tracks);
#endif

  const raw_ref<WebMediaPlayerImpl> player_;

  struct SourceKey {
    media::EmeInitDataType init_data_type = media::EmeInitDataType::UNKNOWN;
    std::vector<uint8_t> init_data;
    uint64_t check = 0;
    bool waiting = false;
    bool deliver_encrypted = false;
  };
  std::map<std::string, SourceKey> source_keys_;
  uint64_t source_key_check_ = 0;
  bool waiting_for_key_ = false;
#if BUILDFLAG(IS_MAC)
  std::unique_ptr<media::CallbackRegistration> cdm_event_registration_;
  std::vector<uint8_t> last_skd_init_data_;
  std::vector<uint8_t> waited_key_;
  uint64_t key_check_ = 0;
  bool key_check_pending_ = false;
#endif
  bool cdm_detached_ = false;

  const scoped_refptr<ParcFrameTaskRunner> frame_task_runner_;
  scoped_refptr<ParcCastingTaskRunner> pipeline_task_runner_;

  bool url_seek_keeps_ready_state_ = false;
  uint64_t url_seek_id_ = 0;

  std::optional<viz::FrameSinkId> parent_frame_sink_id_;
  raw_ptr<MultiBufferDataSource> mb_data_source_ = nullptr;
  base::WeakPtr<MultiBufferDataSource::Factory> hls_source_factory_;
#if BUILDFLAG(IS_MAC)
  std::unique_ptr<FairPlayHlsLoader> hls_loader_;
  media::ParcNativeHlsReadyState native_hls_ready_state_ =
      media::ParcNativeHlsReadyState::kHaveMetadata;
  std::string playback_target_id_;
  bool should_play_to_playback_target_ = false;
  bool wireless_video_playback_disabled_ = false;
  std::optional<std::string> file_native_mime_type_;
  bool file_streaming_ = false;
  std::optional<std::optional<media::MediaTrack::Id>> audio_track_choice_;
  std::optional<std::optional<media::MediaTrack::Id>> video_track_choice_;
  struct FileTrack {
    media::MediaTrack::Id id;
    bool on;
  };
  std::vector<FileTrack> file_audio_tracks_;
  std::vector<FileTrack> file_video_tracks_;
  bool file_on_native_route_ = false;
  bool native_wireless_ = false;
  std::optional<RouteSwitch> route_switch_;

  bool renderer_created_ = false;
  bool handing_off_ = false;
  bool handoff_after_seek_ = false;
  raw_ptr<media::CdmContext> renderer_cdm_context_ = nullptr;
  std::unique_ptr<media::CdmContextRef> replaced_cdm_context_ref_;
  bool awaits_added_streams_renderer_ = false;
  std::optional<media::PipelineMetadata> streams_added_before_metadata_;
#endif
  base::TimeDelta fast_seek_tolerance_;
  base::TimeDelta live_time_offset_;
  raw_ptr<media::ChunkDemuxer, DanglingUntriaged> chunk_demuxer_ = nullptr;
  bool renderer_ready_ = false;
  bool renderer_has_enough_ = false;

  bool cast_prompted_ = false;
  bool cast_requested_ = false;
  bool loads_for_cast_ = false;

  std::optional<bool> page_hidden_;
};

}

#endif
