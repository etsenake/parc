// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //third_party/blink/renderer/platform/media/parc_web_media_player_state.h.
// Parc's state for one WebMediaPlayerImpl, which holds it as a member, and
// the Parc behaviour that runs on it. It lives on the player's main thread
// and reaches the player as its friend; the player keeps every call site,
// so each runs where and when it did.
#ifndef THIRD_PARTY_BLINK_RENDERER_PLATFORM_MEDIA_PARC_WEB_MEDIA_PLAYER_STATE_H_
#define THIRD_PARTY_BLINK_RENDERER_PLATFORM_MEDIA_PARC_WEB_MEDIA_PLAYER_STATE_H_

#include <stdint.h>

#include <map>
#include <memory>
#include <string>
#include <vector>

#include "base/memory/raw_ref.h"
#include "build/build_config.h"
#include "media/base/callback_registry.h"
#include "media/base/cdm_context.h"
#include "media/base/eme_constants.h"
#include "third_party/blink/renderer/platform/platform_export.h"

namespace blink {

class WebMediaPlayerImpl;

class PLATFORM_EXPORT ParcWebMediaPlayerState {
 public:
  explicit ParcWebMediaPlayerState(WebMediaPlayerImpl& player);
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
};

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_PLATFORM_MEDIA_PARC_WEB_MEDIA_PLAYER_STATE_H_
