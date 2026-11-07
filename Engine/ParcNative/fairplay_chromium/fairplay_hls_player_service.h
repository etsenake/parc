// Installed by the reviewed overlay at
// //third_party/parc_fairplay/chromium/fairplay_hls_player_service.h.
//
// The GPU process's end of Safari's native HLS route (NATIVE_HLS.md beside
// this file's source in the Parc repository): media.mojom.FairPlayHlsPlayer
// over the core's parc::fairplay::FairPlayHlsPlayer (an AVPlayer), with its
// audio and text tracks through FairPlayHlsTrackBridge (fp-hls-tracks), on the
// media service thread next to the frame's FairPlay CDMs. InterfaceFactoryImpl
// owns it.
//
//  - Network: the core's HlsLoader. Every load AVFoundation makes becomes a
//    FairPlayHlsPlayerClient.StartLoad, which the render process fetches
//    through the element's loader; the body comes back over a data pipe.
//    Destroying the core's HlsLoad cancels the load (FairPlayHlsLoad.Cancel).
//  - State: the core's callbacks become the client's calls of the same
//    meaning; the media time goes out every 125 ms while playing and at
//    every play, pause and seek, as MojoRendererService sends it.
//  - Display: the AVPlayerLayer is registered in ui::ProtectedLayerRegistry
//    under a fresh token before the token leaves the process
//    (OnLayerRegistered); unregistered when the service goes.
//  - Keys: the asset's skd:// requests go to the CDM's key loader
//    (parc::fairplay::FairPlayHlsKeyLoader), installed between CreateAsset
//    and Start with the frame's CDM once SetCdm names one. Every skd:// and
//    clearkey:// request is reported first as OnKeyRequest(URL)
//    (webkitneedkey); a key no session asked for as OnEncrypted("skd", URI)
//    with OnWaiting(kNoDecryptionKey). clearkey:// requests are answered by
//    ProvideClearKey with their key ID (HlsClearKeyId).
//  - Audio: muted while the page or the tab mutes it; the tab's state comes
//    from the browser's MuteStateObserver, and audio stays muted until its
//    first answer.
#ifndef THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_HLS_PLAYER_SERVICE_H_
#define THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_HLS_PLAYER_SERVICE_H_

#include <stdint.h>

#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "base/functional/callback.h"
#include "base/functional/callback_helpers.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/sequence_checker.h"
#include "base/task/sequenced_task_runner.h"
#include "base/timer/timer.h"
#include "base/unguessable_token.h"
#include "media/mojo/mojom/renderer_extensions.mojom.h"
#include "mojo/public/cpp/bindings/pending_remote.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "third_party/parc_fairplay/core/fairplay_hls_player.h"

namespace parc::fairplay {
class FairPlayHlsKeyLoader;
}  // namespace parc::fairplay
#include "ui/gfx/geometry/size.h"

namespace media {

class CdmContextRef;
class FairPlayHlsTrackBridge;

class FairPlayHlsPlayerService final
    : public mojom::FairPlayHlsPlayer,
      public parc::fairplay::HlsPlayerClient,
      public parc::fairplay::HlsLoader {
 public:
  // Resolves SetCdm()'s ID among the frame's CDMs (MojoCdmServiceContext).
  using CdmContextGetter = base::RepeatingCallback<std::unique_ptr<
      CdmContextRef>(const base::UnguessableToken& cdm_id)>;

  // Runs on |task_runner|, the media service thread. Keeps |lifetime| (may
  // be unbound) until it is destroyed.
  FairPlayHlsPlayerService(
      scoped_refptr<base::SequencedTaskRunner> task_runner,
      CdmContextGetter get_cdm_context,
      mojo::PendingRemote<mojom::FairPlayHlsPlayerClient> client,
      mojo::PendingRemote<mojom::FairPlayHlsPlayerLifetime> lifetime);
  FairPlayHlsPlayerService(const FairPlayHlsPlayerService&) = delete;
  FairPlayHlsPlayerService& operator=(const FairPlayHlsPlayerService&) =
      delete;
  ~FairPlayHlsPlayerService() override;

  // The tab's mute state (MuteStateObserver). Bound to a weak pointer; may
  // outlive the service.
  base::RepeatingCallback<void(bool)> GetMuteStateCallback();
  // Called once the browser was asked for the tab's mute state: audio stays
  // muted until its first answer. |closer| closes the observer when the
  // service goes.
  void SetMuteStateObserverCloser(base::ScopedClosureRunner closer);

  // mojom::FairPlayHlsPlayer:
  void Initialize(const GURL& url, const std::string& mime_type) override;
  void SetCdm(const base::UnguessableToken& cdm_id,
              SetCdmCallback callback) override;
  void Play(double rate) override;
  void Pause() override;
  void Seek(base::TimeDelta time,
            base::TimeDelta tolerance_before,
            SeekCallback callback) override;
  void SetVolume(float volume) override;
  void SetMuted(bool muted) override;
  void SetPreservesPitch(bool preserves_pitch) override;
  void ProvideClearKey(const std::string& key_id,
                       const std::vector<uint8_t>& key) override;
  void SetAudioTrackEnabled(const std::string& key, bool enabled) override;
  void SetTextTrackMode(const std::string& key,
                        mojom::FairPlayHlsTextTrackMode mode) override;
  void Suspend() override;
  void Resume() override;

  // parc::fairplay::HlsPlayerClient:
  void OnMetadata(const parc::fairplay::HlsMetadata& metadata) override;
  void OnBufferingStateChange(bool have_enough) override;
  void OnLoadedRangesChange(
      const std::vector<parc::fairplay::HlsTimeRange>& loaded) override;
  void OnSeekableRangesChange(
      const std::vector<parc::fairplay::HlsTimeRange>& seekable) override;
  void OnDurationChange(double seconds) override;
  void OnStartDateChange(std::optional<double> start_date_ms) override;
  void OnNaturalSizeChange(int32_t width, int32_t height) override;
  void OnEnded() override;
  void OnError(parc::fairplay::HlsError error,
               const std::string& message) override;
  void OnKeyRequest(const std::string& uri) override;
  void OnOutputObscuredChange(bool obscured) override;
  void OnVideoFrameCounts(uint32_t decoded, uint32_t dropped) override;

  // parc::fairplay::HlsLoader:
  std::unique_ptr<parc::fairplay::HlsLoad> StartLoad(
      const parc::fairplay::HlsLoadRequest& request,
      parc::fairplay::HlsLoadClient* client) override;


 private:
  class Load;
  // The key loader's client (fairplay_hls_keys.h is Objective-C++ only).
  class KeyLoaderClient;

  // From the key loader.
  void OnKeyNeeded(const std::string& uri);
  void OnKeyLoadingRequest(const std::string& url);

  // Sends OnInitialized: |metadata|, or null for a failure.
  void FinishInitialize(mojom::FairPlayHlsMetadataPtr metadata);
  void OnSeekDone(SeekCallback callback, bool finished);
  void RegisterLayer();
  void ApplyMuted();
  void SendTimeUpdate();
  void UpdateTimeUpdateTimer();

  const scoped_refptr<base::SequencedTaskRunner> task_runner_;
  const CdmContextGetter get_cdm_context_;
  mojo::Remote<mojom::FairPlayHlsPlayerClient> client_;
  mojo::Remote<mojom::FairPlayHlsPlayerLifetime> lifetime_;

  // The frame's CDM after SetCdm(), held while the key loader may use it.
  std::unique_ptr<CdmContextRef> cdm_context_ref_;

  // Created by Initialize(). The destructor resets them tracks, player, key
  // loader: the player hands the loader requests until it is gone.
  std::unique_ptr<KeyLoaderClient> key_loader_client_;
  std::unique_ptr<parc::fairplay::FairPlayHlsKeyLoader> key_loader_;
  std::unique_ptr<FairPlayHlsTrackBridge> tracks_;
  std::unique_ptr<parc::fairplay::FairPlayHlsPlayer> player_;

  bool init_pending_ = false;  // Initialize ran; no OnInitialized yet.
  bool initialized_ = false;   // OnInitialized went out with metadata.
  bool errored_ = false;
  // Client calls the element can't take before OnInitialized (buffering
  // state), sent in order right after it.
  std::vector<base::OnceClosure> pending_client_calls_;

  bool has_video_ = false;
  gfx::Size natural_size_;
  base::UnguessableToken layer_token_;

  double rate_ = 0;  // The page's rate while playing, else 0.
  base::RepeatingTimer time_update_timer_;

  float volume_ = 1;
  bool preserves_pitch_ = true;
  bool page_muted_ = false;
  bool tab_muted_ = false;
  bool awaiting_mute_state_ = false;
  base::ScopedClosureRunner mute_state_observer_closer_;

  // clearkey:// key ID (HlsClearKeyId) → URI, for ProvideClearKey.
  std::map<std::string, std::string> clear_key_uris_;

  SEQUENCE_CHECKER(sequence_checker_);
  base::WeakPtrFactory<FairPlayHlsPlayerService> weak_factory_{this};
};

}  // namespace media

#endif  // THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_HLS_PLAYER_SERVICE_H_
