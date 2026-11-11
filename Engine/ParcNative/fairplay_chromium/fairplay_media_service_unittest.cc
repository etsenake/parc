#include "third_party/parc_fairplay/chromium/fairplay_media_service.h"

#include <optional>
#include <string>
#include <vector>

#include "base/files/file_path.h"
#include "base/functional/bind.h"
#include "base/test/bind.h"
#include "base/test/task_environment.h"
#include "media/base/cdm_config.h"
#include "media/cdm/clear_key_cdm_common.h"
#include "media/cdm/default_cdm_factory.h"
#include "media/mojo/services/mojo_cdm_service.h"
#include "mojo/public/cpp/bindings/receiver.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "testing/gtest/include/gtest/gtest.h"

namespace media {
namespace {

// The browser's answers for a document, and the tab mute observers the GPU
// process registers with it.
class FakeFrameHost final : public mojom::FairPlayFrameHost {
 public:
  void GetStorageDirectory(GetStorageDirectoryCallback callback) final {
    std::move(callback).Run(base::FilePath());
  }
  void GetDeviceIdSalt(GetDeviceIdSaltCallback callback) final {
    std::move(callback).Run(std::string());
  }
  void IsEphemeralSession(IsEphemeralSessionCallback callback) final {
    std::move(callback).Run(false);
  }
  void GetAudioOutputDeviceUid(
      const std::string& hashed_device_id,
      GetAudioOutputDeviceUidCallback callback) final {
    std::move(callback).Run(std::nullopt);
  }
  void RegisterMuteStateObserver(
      mojo::PendingRemote<mojom::FairPlayMuteStateObserver> observer) final {
    observers_.emplace_back(std::move(observer));
  }

  std::vector<mojo::Remote<mojom::FairPlayMuteStateObserver>> observers_;
};

class PlayerMute final : public mojom::FairPlayMuteStateObserver {
 public:
  void OnMuteStateChange(bool muted) final { states_.push_back(muted); }

  std::vector<bool> states_;
};

}  // namespace

// A CDM ID resolves for every document of the render process that made the
// CDM, as WebKit's CDM instance belongs to its MediaKeys, not to a frame. Not
// in another render process, nor an unknown ID.
TEST(FairPlayMediaServiceTest, ResolvesCdmIdsOnlyInTheirRenderProcess) {
  base::test::TaskEnvironment task_environment;
  scoped_refptr<FairPlayProcessMedia> creating = FairPlayProcessMedia::Get(7);
  scoped_refptr<FairPlayProcessMedia> other_document =
      FairPlayProcessMedia::Get(7);
  scoped_refptr<FairPlayProcessMedia> other_process =
      FairPlayProcessMedia::Get(8);
  EXPECT_EQ(creating.get(), other_document.get());

  DefaultCdmFactory cdm_factory;
  MojoCdmService cdm_service(&creating->cdm_service_context());
  std::optional<base::UnguessableToken> cdm_id;
  cdm_service.Initialize(
      &cdm_factory, CdmConfig{kClearKeyKeySystem, false, false, false},
      base::BindLambdaForTesting(
          [&](mojom::CdmContextPtr cdm_context, CreateCdmStatus) {
            ASSERT_TRUE(cdm_context);
            cdm_id = cdm_context->cdm_id;
          }));
  task_environment.RunUntilIdle();
  ASSERT_TRUE(cdm_id);

  EXPECT_TRUE(other_document->cdm_service_context().GetCdmContextRef(*cdm_id));
  EXPECT_FALSE(other_process->cdm_service_context().GetCdmContextRef(*cdm_id));
  EXPECT_FALSE(other_document->cdm_service_context().GetCdmContextRef(
      base::UnguessableToken::Create()));
}

// A handoff watches the tab mute of the document that made it, and only a
// player of the same render process takes it, once.
TEST(FairPlayMediaServiceTest, MuteStateHandoffStaysInItsRenderProcess) {
  base::test::TaskEnvironment task_environment;
  FairPlayMediaService service;
  mojo::Remote<mojom::FairPlayMediaService> service_remote;
  service.Bind(service_remote.BindNewPipeAndPassReceiver());
  FakeFrameHost tab_mute;
  mojo::Receiver<mojom::FairPlayFrameHost> frame_host(&tab_mute);
  mojo::Remote<mojom::FairPlayFrameMedia> frame_media;
  service_remote->CreateFrameMedia(/*render_process_id=*/7,
                                   frame_host.BindNewPipeAndPassRemote(),
                                   frame_media.BindNewPipeAndPassReceiver());

  std::optional<base::UnguessableToken> handoff;
  frame_media->CreateMuteStateHandoff(base::BindLambdaForTesting(
      [&](const std::optional<base::UnguessableToken>& answer) {
        handoff = answer;
      }));
  task_environment.RunUntilIdle();
  ASSERT_TRUE(handoff);
  ASSERT_EQ(1u, tab_mute.observers_.size());

  EXPECT_FALSE(FairPlayProcessMedia::Get(8)->TakeMuteStateHandoff(*handoff));
  scoped_refptr<FairPlayProcessMedia> process = FairPlayProcessMedia::Get(7);
  mojo::PendingReceiver<mojom::FairPlayMuteStateObserver> observer =
      process->TakeMuteStateHandoff(*handoff);
  ASSERT_TRUE(observer);
  EXPECT_FALSE(process->TakeMuteStateHandoff(*handoff));

  PlayerMute player;
  mojo::Receiver<mojom::FairPlayMuteStateObserver> player_receiver(&player,
                                                           std::move(observer));
  tab_mute.observers_[0]->OnMuteStateChange(true);
  task_environment.RunUntilIdle();
  EXPECT_EQ(std::vector<bool>({true}), player.states_);
}

}  // namespace media
