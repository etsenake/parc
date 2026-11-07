// The native HLS player's audio and text tracks for the GPU service
// (media::FairPlayHlsPlayerService, NATIVE_HLS.md Tracks): owns the core's
// HlsMediaSelection on the player's AVPlayer and speaks the mojo side of it.
//
// Service wiring:
//   bridge_ = std::make_unique<FairPlayHlsTrackBridge>(client, PostTaskTo(..));
//   after FairPlayHlsPlayer::Load succeeds: bridge_->Attach(player.impl());
//   Initialize reply: metadata->tracks = bridge_->TakeTracksForInitialize();
//   SetAudioTrackEnabled / SetTextTrackMode: forward to the bridge;
//   around each FairPlayHlsPlayer::Seek: WillSeek() before, DidSeek() in its
//   done callback, whatever the result.
// Lists the selection reports before the Initialize reply are folded into
// it; later ones go out as OnTracksChanged, so the render process never sees
// a list older than the one it already has (the reply and the client calls
// travel on different pipes).
#ifndef THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_HLS_TRACK_BRIDGE_H_
#define THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_HLS_TRACK_BRIDGE_H_

#include <string>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "media/mojo/mojom/renderer_extensions.mojom.h"
#include "third_party/parc_fairplay/core/fairplay_hls_media_selection.h"
#include "third_party/parc_fairplay/core/fairplay_hls_player.h"

namespace media {

class FairPlayHlsTrackBridge final
    : public parc::fairplay::HlsMediaSelectionClient {
 public:
  // `client` must outlive the bridge. Runs on the player's sequence;
  // `post_task` reaches it from any thread.
  FairPlayHlsTrackBridge(mojom::FairPlayHlsPlayerClient* client,
                         parc::fairplay::PostTask post_task);
  ~FairPlayHlsTrackBridge() override;

  FairPlayHlsTrackBridge(const FairPlayHlsTrackBridge&) = delete;
  FairPlayHlsTrackBridge& operator=(const FairPlayHlsTrackBridge&) = delete;

  // Starts following `player`'s item, right after its Load succeeded.
  void Attach(parc::fairplay::FairPlayHlsPlayer::Impl* player);

  // The list for the Initialize reply; from now on changes are sent.
  std::vector<mojom::FairPlayHlsTrackPtr> TakeTracksForInitialize();

  void SetAudioTrackEnabled(const std::string& key, bool enabled);
  void SetTextTrackMode(const std::string& key,
                        mojom::FairPlayHlsTextTrackMode mode);

  void WillSeek();
  void DidSeek();

  // parc::fairplay::HlsMediaSelectionClient:
  void OnTracksChanged(
      const std::vector<parc::fairplay::HlsTrack>& tracks) override;
  void OnTextCues(const std::string& track_key,
                  const std::vector<parc::fairplay::HlsCue>& cues) override;

 private:
  const raw_ptr<mojom::FairPlayHlsPlayerClient> client_;
  parc::fairplay::HlsMediaSelection selection_;
  // The last list the render process got (reply or OnTracksChanged): queued
  // reports older than the reply, or repeating it, are not sent.
  std::vector<parc::fairplay::HlsTrack> last_sent_;
  bool attached_ = false;
  bool initialized_ = false;
  int pending_seeks_ = 0;
};

}  // namespace media

#endif  // THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_HLS_TRACK_BRIDGE_H_
