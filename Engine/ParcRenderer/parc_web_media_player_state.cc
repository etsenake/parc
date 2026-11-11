// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //third_party/blink/renderer/platform/media/parc_web_media_player_state.cc.
#include "third_party/blink/renderer/platform/media/parc_web_media_player_state.h"

#include <algorithm>
#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "third_party/blink/public/platform/web_media_player.h"
#include "third_party/blink/public/platform/web_media_player_encrypted_media_client.h"
#include "third_party/blink/renderer/platform/media/parc_media_player_client.h"
#if BUILDFLAG(IS_MAC)
#include "third_party/blink/renderer/platform/media/fairplay_hls_loader.h"
#endif  // BUILDFLAG(IS_MAC)
#include "third_party/blink/renderer/platform/media/web_media_player_impl.h"

namespace blink {

ParcWebMediaPlayerState::ParcWebMediaPlayerState(
    WebMediaPlayerImpl& player,
    scoped_refptr<ParcFrameTaskRunner> frame_task_runner)
    : player_(player), frame_task_runner_(std::move(frame_task_runner)) {}

ParcWebMediaPlayerState::~ParcWebMediaPlayerState() = default;

void ParcWebMediaPlayerState::SourceKeyChanged(
    const std::string& id,
    media::EmeInitDataType init_data_type,
    const std::vector<uint8_t>& init_data) {
  if (init_data.empty()) {
    source_keys_.erase(id);
    SetWaitingForKey(std::ranges::any_of(source_keys_,
        [](const auto& entry) { return entry.second.waiting; }));
    return;
  }
  if (auto* parc = player_->client_->ParcClient()) {
    parc->ParcWebKitMediaSourceKeyNeeded(init_data);
  }
  source_keys_[id].init_data_type = init_data_type;
  source_keys_[id].init_data = init_data;
  source_keys_[id].deliver_encrypted = true;
  CheckSourceKey(id);
}

void ParcWebMediaPlayerState::RecheckSourceKeys() {
  for (const auto& [id, key] : source_keys_)
    CheckSourceKey(id);
}

void ParcWebMediaPlayerState::CheckSourceKey(const std::string& id) {
  auto& key = source_keys_.at(id);
  const uint64_t check = key.check = ++source_key_check_;
  auto done = base::BindOnce(
      [](base::WeakPtr<WebMediaPlayerImpl> player, std::string id,
         uint64_t check, bool has_session) {
        if (!player)
          return;
        auto it = player->parc_->source_keys_.find(id);
        if (it == player->parc_->source_keys_.end() ||
            it->second.check != check)
          return;
        auto& key = it->second;
        const bool deliver_encrypted = std::exchange(key.deliver_encrypted, false);
        if (deliver_encrypted || has_session)
          key.waiting = !has_session;
        if (!has_session && deliver_encrypted)
          player->ParcDeliverEncryptedMediaInitData(key.init_data_type,
                                                    key.init_data);
        // WebKit's MediaSourcePrivateAVFObjC::waitingForKey aggregates every
        // SourceBuffer, so another buffer's session cannot end this wait.
        player->parc_->SetWaitingForKey(std::ranges::any_of(
            player->parc_->source_keys_,
            [](const auto& entry) { return entry.second.waiting; }));
      }, player_->weak_this_, id, check);
  auto* ref = player_->pending_cdm_context_ref_
                  ? player_->pending_cdm_context_ref_.get()
              : cdm_detached_ ? nullptr
                              : player_->cdm_context_ref_.get();
  if (!ref) {
    std::move(done).Run(false);
    return;
  }
  ref->GetCdmContext()->ParcHasSessionForInitData(
      key.init_data_type, key.init_data, std::move(done));
}

void ParcWebMediaPlayerState::SetWaitingForKey(bool waiting) {
#if BUILDFLAG(IS_MAC)
  // A change, or a request to stop, overtakes the CDM answer
  // CheckWaitedKey() awaits.
  if (!waiting || waiting != waiting_for_key_) {
    ++key_check_;
    key_check_pending_ = false;
  }
#endif  // BUILDFLAG(IS_MAC)
  if (waiting == waiting_for_key_) {
    return;
  }
  waiting_for_key_ = waiting;
  if (waiting) {
    player_->has_waiting_for_key_ = true;
    player_->media_metrics_provider_->SetHasWaitingForKey();
    player_->encrypted_client_->DidBlockPlaybackWaitingForKey();
  } else {
    player_->encrypted_client_->DidResumePlaybackBlockedForKey();
  }
}

#if BUILDFLAG(IS_MAC)
void ParcWebMediaPlayerState::OnCdmEvent(media::CdmContext::Event event) {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  if (event != media::CdmContext::Event::kHasAdditionalUsableKey &&
      event != media::CdmContext::Event::kParcKeyStatusesChanged) {
    return;
  }
  if (player_->load_type_ == WebMediaPlayer::kLoadTypeMediaSource) {
    RecheckSourceKeys();
    return;
  }
  // A stall that names no key (Chromium's decryptors and the FairPlay
  // Renderer report none) ends with any newly usable key.
  if (waited_key_.empty()) {
    SetWaitingForKey(false);
    return;
  }
  if (waiting_for_key_ || key_check_pending_) {
    CheckWaitedKey();
  }
}

void ParcWebMediaPlayerState::WaitForStalledKey() {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  // WebKit's native HLS player waits for the key its last request made with
  // no CDM attached named (MediaPlayerPrivateAVFoundationObjC's m_keyID).
  if (!player_->ParcPlaysNativeHls()) {
    // WebKit's src= player never enters waiting-for-key with a CDM attached
    // (MediaPlayerPrivateAVFoundationObjC::shouldWaitForLoadingOfResource).
    if (player_->cdm_context_ref_ && !cdm_detached_) {
      SetWaitingForKey(false);
      return;
    }
    waited_key_.clear();
  } else if (!last_skd_init_data_.empty()) {
    waited_key_ = last_skd_init_data_;
  }
  SetWaitingForKey(true);
  // The player sends a stall only for a request made while it held no CDM.
  // One attached here since ends the wait if a session has a request for the
  // key, as WebKit's setMediaKeys runs attemptToResumePlaybackIfNecessary.
  CheckWaitedKey();
}

void ParcWebMediaPlayerState::CheckWaitedKey() {
  DCHECK(player_->main_task_runner_->BelongsToCurrentThread());
  if (waited_key_.empty() || !player_->cdm_context_ref_ || cdm_detached_) {
    return;
  }
  // Only the latest check decides: it asked the current CDM after every
  // earlier one.
  const uint64_t check = ++key_check_;
  key_check_pending_ = true;
  player_->cdm_context_ref_->GetCdmContext()->ParcHasSessionForInitData(
      media::EmeInitDataType::SKD, waited_key_,
      base::BindOnce(
          [](base::WeakPtr<WebMediaPlayerImpl> player, uint64_t check,
             std::vector<uint8_t> key, bool has_session) {
            if (!player || check != player->parc_->key_check_ ||
                key != player->parc_->waited_key_) {
              return;
            }
            player->parc_->key_check_pending_ = false;
            player->parc_->SetWaitingForKey(!has_session);
          },
          player_->weak_this_, check, waited_key_));
}
#endif  // BUILDFLAG(IS_MAC)

}  // namespace blink
