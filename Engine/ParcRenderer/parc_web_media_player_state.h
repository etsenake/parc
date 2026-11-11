// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //third_party/blink/renderer/platform/media/parc_web_media_player_state.h.
// Parc's state for one WebMediaPlayerImpl, the player's only Parc member, and
// the Parc behaviour that runs on it. It lives on the player's main thread
// and reaches the player as its friend; the player keeps every call site,
// so each runs where and when it did.
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
#include "media/base/pipeline_metadata.h"
#include "media/filters/chunk_demuxer.h"
#include "third_party/blink/public/platform/web_media_player.h"
#include "third_party/blink/renderer/platform/media/multi_buffer_data_source.h"
#include "third_party/blink/renderer/platform/media/parc_media_task_runners.h"
#include "third_party/blink/renderer/platform/platform_export.h"

namespace blink {

#if BUILDFLAG(IS_MAC)
class FairPlayHlsLoader;
#endif  // BUILDFLAG(IS_MAC)
class WebMediaPlayerImpl;

class PLATFORM_EXPORT ParcWebMediaPlayerState {
 public:
  // `frame_task_runner`: the player's main-thread task runner on a
  // Safari-identity page, else null.
  ParcWebMediaPlayerState(
      WebMediaPlayerImpl& player,
      scoped_refptr<ParcFrameTaskRunner> frame_task_runner);
  ParcWebMediaPlayerState(const ParcWebMediaPlayerState&) = delete;
  ParcWebMediaPlayerState& operator=(const ParcWebMediaPlayerState&) = delete;
  ~ParcWebMediaPlayerState();

  // WebKit's SourceBufferPrivateAVFObjC::setWaitingForKey for a
  // Safari-identity Media Source element: waiting once its init data finds no
  // session (waitingforkey, once), not waiting once a later one finds one.
  // Other Safari-identity players wait from OnWaiting until OnCdmEvent.
  void SetWaitingForKey(bool waiting);
  void SourceKeyChanged(const std::string& id,
                        media::EmeInitDataType init_data_type,
                        const std::vector<uint8_t>& init_data);
  void RecheckSourceKeys();
#if BUILDFLAG(IS_MAC)
  // A Safari-identity player other than Media Source stops waiting for a key
  // once a session of the attached CDM has a request for the key its stall
  // named, as WebKit's native HLS player
  // (MediaPlayerPrivateAVFoundationObjC::attemptToDecryptWithInstance, which
  // setMediaKeys and key status changes run).
  void OnCdmEvent(media::CdmContext::Event event);
  // OnWaiting for such a player: waits, then asks a CDM attached since
  // whether that ends it (CheckWaitedKey).
  void WaitForStalledKey();
  // Asks the attached CDM whether a session has a request for `waited_key_`
  // (WebKit's sessionForKeyIDs(m_keyID)) and waits while none has.
  void CheckWaitedKey();
#endif  // BUILDFLAG(IS_MAC)

 private:
  friend class WebMediaPlayerImpl;
  friend class WebMediaPlayerImplTest;

  void CheckSourceKey(const std::string& id);

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
  // SetWaitingForKey's state.
  bool waiting_for_key_ = false;
#if BUILDFLAG(IS_MAC)
  // OnCdmEvent's registration with the player's `cdm_context_ref_`'s CDM,
  // reset before that reference goes.
  std::unique_ptr<media::CallbackRegistration> cdm_event_registration_;
  // The "skd" init data (key URI) native HLS last reported, and the one its
  // latest stall waits for; empty for a stall that names no key (one not
  // through native HLS).
  std::vector<uint8_t> last_skd_init_data_;
  std::vector<uint8_t> waited_key_;
  // CheckWaitedKey's latest check, also advanced by SetWaitingForKey's
  // changes and stop requests, and whether its answer is still to come.
  uint64_t key_check_ = 0;
  bool key_check_pending_ = false;
#endif  // BUILDFLAG(IS_MAC)
  // A Safari-identity page set its FairPlay MediaKeys to null; the pipeline
  // keeps the player's `cdm_context_ref_`'s CDM for the renderer joined to
  // it, and nothing decrypts with it (SetContentDecryptionModule).
  bool cdm_detached_ = false;

  // On a Safari-identity page, the player's `main_task_runner_`: the frame's
  // task runner, replaced by the frame the element moves the player to
  // (WebMediaPlayerImpl::ParcMoveToFrame()).
  const scoped_refptr<ParcFrameTaskRunner> frame_task_runner_;
  // The pipeline's, which casting keeps running in a frozen frame.
  scoped_refptr<ParcCastingTaskRunner> pipeline_task_runner_;

  // Whether the last seek kept the readyState
  // (WebMediaPlayerImpl::ParcUrlSeekKeepsReadyState()), and that seek's
  // number, which a frame the compositor reports for it carries.
  bool url_seek_keeps_ready_state_ = false;
  uint64_t url_seek_id_ = 0;

  // The parent frame sink of the frame a Safari-identity element moved the
  // player to before it had a surface layer bridge.
  std::optional<viz::FrameSinkId> parent_frame_sink_id_;
  // The data source DoLoad() gave the player's `demuxer_manager_`, which owns
  // it.
  raw_ptr<MultiBufferDataSource> mb_data_source_ = nullptr;
  // Makes the data sources of Chromium's HLS player
  // (WebMediaPlayerImpl::GetHlsDataSourceProvider()).
  base::WeakPtr<MultiBufferDataSource::Factory> hls_source_factory_;
#if BUILDFLAG(IS_MAC)
  // Fetches the loads of Safari's native HLS player (its demuxer's
  // FairPlayHlsPlayerClient.StartLoad) through the player's `url_index_`'s
  // fetch context; destroying it cancels them.
  std::unique_ptr<FairPlayHlsLoader> hls_loader_;
  // The native HLS player's last readyState (WebKit's).
  media::ParcNativeHlsReadyState native_hls_ready_state_ =
      media::ParcNativeHlsReadyState::kHaveMetadata;
  // The element's AirPlay target and disabled flag, for the native HLS
  // demuxer this load makes (ParcSetPlaybackTarget).
  std::string playback_target_id_;
  bool should_play_to_playback_target_ = false;
  bool wireless_video_playback_disabled_ = false;
  // The type AVFoundation is told for a clear file Safari's AVPlayer would
  // play, from the container Chromium's demuxer found; nullopt for anything
  // else, which never plays to a target (WebKit's WebM and Media Source
  // players refuse one), and once the native route couldn't open it.
  std::optional<std::string> file_native_mime_type_;
  bool file_streaming_ = false;
  // The tracks the element chose, for the pipeline a route switch makes.
  std::optional<std::optional<media::MediaTrack::Id>> audio_track_choice_;
  std::optional<std::optional<media::MediaTrack::Id>> video_track_choice_;
  // The element's audio and video tracks in Chromium's order, with
  // AudioTrack.enabled and VideoTrack.selected, which the native route
  // matches by position.
  struct FileTrack {
    media::MediaTrack::Id id;
    bool on;
  };
  std::vector<FileTrack> file_audio_tracks_;
  std::vector<FileTrack> file_video_tracks_;
  // The file plays through the native route.
  bool file_on_native_route_ = false;
  // The native route last said it plays to the device.
  bool native_wireless_ = false;
  // While the pipeline moves route the element keeps its duration and
  // readyState; `ready_state` is the latest the new route reported.
  struct RouteSwitch {
    double duration;
    std::optional<WebMediaPlayer::ReadyState> ready_state;
    base::TimeDelta time;
  };
  std::optional<RouteSwitch> route_switch_;

  // See WebMediaPlayerImpl::ParcSwitchToFairPlayIfNeeded(). Whether a
  // renderer was created.
  bool renderer_created_ = false;
  // A hand-off to the FairPlay Renderer is on its way
  // (WebMediaPlayerImpl::ParcHandOffOrRestart()).
  bool handing_off_ = false;
  // One asked for during a seek, which starts once it's done.
  bool handoff_after_seek_ = false;
  // The FairPlay CDM the current renderer has (only compared, never used), so
  // a page that replaces the FairPlay MediaKeys of a renderer that can't take
  // others restarts into one with the new MediaKeys, as WebKit's setMediaKeys
  // switches CDMs during playback. The replaced CDM is kept until the next
  // renderer.
  raw_ptr<media::CdmContext> renderer_cdm_context_ = nullptr;
  std::unique_ptr<media::CdmContextRef> replaced_cdm_context_ref_;
  // See WebMediaPlayerImpl::ParcOnSourceBufferStreamsAdded(). The pipeline
  // isn't suspended again until the renderer that plays the added streams
  // (the one they joined, or the one it resumes or restarts into) has enough
  // data; and streams added before OnMetadata().
  bool awaits_added_streams_renderer_ = false;
  std::optional<media::PipelineMetadata> streams_added_before_metadata_;
#endif  // BUILDFLAG(IS_MAC)
  // The tolerance ParcFastSeek() hands the Seek() it makes.
  base::TimeDelta fast_seek_tolerance_;
  // A live stream's new connection after a route switch starts its own
  // timeline; the element's continues from where it was, as on Safari's
  // single connection. Added to the pipeline's times, taken off seeks.
  base::TimeDelta live_time_offset_;
  // See WebMediaPlayerImpl::ParcMonitorSourceBuffers(). The media source's
  // demuxer, set when it opens; whether the renderer has had HAVE_ENOUGH since
  // the start or the last seek (its samples, a video frame, are available);
  // and whether its buffering is HAVE_ENOUGH now.
  raw_ptr<media::ChunkDemuxer, DanglingUntriaged> chunk_demuxer_ = nullptr;
  bool renderer_ready_ = false;
  bool renderer_has_enough_ = false;

  // See WebMediaPlayerImpl::ParcUpdateLoadsForCast().
  bool cast_prompted_ = false;
  bool cast_requested_ = false;
  bool loads_for_cast_ = false;

  // ParcSetPageHidden()'s state; when set, the player's IsPageHidden()
  // reports it instead of the delegate's page.
  std::optional<bool> page_hidden_;
};

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_PLATFORM_MEDIA_PARC_WEB_MEDIA_PLAYER_STATE_H_
