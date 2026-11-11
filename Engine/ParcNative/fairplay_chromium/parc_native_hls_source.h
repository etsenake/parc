// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //media/base/parc_native_hls_source.h.
// The GPU player behind Safari's native HLS route (NATIVE_HLS.md beside this
// file's source in the Parc repository), as the pipeline, DemuxerManager and
// the renderer facade reach it through MediaResource::GetParcNativeHlsSource().
// NativeHlsDemuxer (content/renderer/media/fairplay) implements it.
#ifndef MEDIA_BASE_PARC_NATIVE_HLS_SOURCE_H_
#define MEDIA_BASE_PARC_NATIVE_HLS_SOURCE_H_

#include <stdint.h>

#include <optional>
#include <string>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "base/time/time.h"
#include "base/unguessable_token.h"
#include "media/base/buffering_state.h"
#include "media/base/pipeline_status.h"
#include "media/base/ranges.h"
#include "media/base/waiting.h"
#include "ui/gfx/geometry/size.h"

namespace media {
class CdmContext;
}  // namespace media

namespace parc::fairplay {

// Media thread, except where a method says otherwise.
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
  // HTMLMediaElement.setSinkId's device, as its sink names it (hashed for the
  // frame's origin; empty or "default" for the system default).
  virtual void SetAudioOutputDevice(const std::string& sink_id) = 0;
  // Hands the player the frame's CDM `cdm_context` names (its CDM ID), or
  // detaches it with null. `cdm_attached_cb` answers whether the player took
  // it. The pipeline also hands over a CDM set before its renderer exists,
  // so it reaches the player at once; `cdm_context` stays valid while the
  // pipeline holds it, as for Renderer::SetCdm().
  using CdmAttachedCB = base::OnceCallback<void(bool)>;
  virtual void SetCdm(media::CdmContext* cdm_context,
                      CdmAttachedCB cdm_attached_cb) = 0;

  // The item's buffering state as AVFoundation last reported it.
  virtual media::BufferingState GetBufferingState() const = 0;

  // The media time the GPU player last reported, advanced at its rate since
  // then and kept within [0, duration]. During a seek, the seek target. Any
  // thread.
  virtual base::TimeDelta GetMediaTime() = 0;

  // What the AVPlayer last reported for the media element
  // (NATIVE_HLS.md, Live and DVR): the seekable attribute, one range or none,
  // an end of kInfiniteDuration meaning Infinity; and getStartDate(), none
  // without a program date time.
  struct Timeline {
    media::Ranges<base::TimeDelta> seekable;
    std::optional<base::Time> start_date;
  };
  // Any thread.
  virtual Timeline GetTimeline() const = 0;

  // A legacy clear key (org.w3c.clearkey) for the player's clearkey://
  // requests (WebMediaPlayer::ParcProvideClearKey): `key_id` is WebKit's key
  // ID, `key` the raw key.
  virtual void ProvideClearKey(const std::string& key_id,
                               const std::vector<uint8_t>& key) = 0;

  // The element prepares to play (its preload became auto), which makes the
  // player put its item on the player (WebKit's setPreload(Auto)). Main
  // thread.
  virtual void PrepareToPlay() = 0;

  // AirPlay (WebKit's setWirelessPlaybackTarget,
  // setShouldPlayToPlaybackTarget and setWirelessVideoPlaybackDisabled).
  virtual void SetPlaybackTarget(const std::string& output_context_id,
                                 bool should_play) = 0;
  virtual void SetWirelessVideoPlaybackDisabled(bool disabled) = 0;

  // A clear file on the native route takes the element's track choices
  // (FairPlayHlsPlayer.SelectFileTracks): how many audio and video tracks it
  // lists, the positions of the enabled audio tracks and of the selected
  // video track.
  struct FileTracks {
    uint32_t audio_count = 0;
    std::vector<uint32_t> audio;
    uint32_t video_count = 0;
    std::optional<uint32_t> video;
  };
  virtual void SelectFileTracks(const FileTracks& tracks) = 0;

  virtual base::WeakPtr<NativeHlsSource> GetWeakPtr() = 0;

 protected:
  virtual ~NativeHlsSource() = default;
};

}  // namespace parc::fairplay

#endif  // MEDIA_BASE_PARC_NATIVE_HLS_SOURCE_H_
