// Copyright 2026 Parc contributors.

#include "chrome/browser/media/cast_remoting_connector.h"

#include <memory>
#include <utility>
#include <vector>

#include "base/run_loop.h"
#include "chrome/browser/media/remoting_bridge.h"
#include "components/sessions/core/session_id.h"
#include "components/sync_preferences/testing_pref_service_syncable.h"
#include "content/public/test/browser_task_environment.h"
#include "media/mojo/mojom/remoting.mojom.h"
#include "mojo/public/cpp/bindings/self_owned_receiver.h"
#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"

namespace {

using media::mojom::RemotingSinkMetadata;
using media::mojom::RemotingSinkMetadataPtr;
using media::mojom::RemotingStartFailReason;
using media::mojom::RemotingStopReason;
using testing::_;

constexpr SessionID kRemotingTabId = SessionID::FromSerializedValue(2);

RemotingSinkMetadataPtr GetDefaultSinkMetadata() {
  RemotingSinkMetadataPtr metadata = RemotingSinkMetadata::New();
  metadata->features.push_back(
      media::mojom::RemotingSinkFeature::CONTENT_DECRYPTION);
  metadata->video_capabilities.push_back(
      media::mojom::RemotingSinkVideoCapability::CODEC_VP8);
  metadata->audio_capabilities.push_back(
      media::mojom::RemotingSinkAudioCapability::CODEC_AAC);
  return metadata;
}

class MockRemotingSource final : public media::mojom::RemotingSource {
 public:
  void Bind(mojo::PendingReceiver<media::mojom::RemotingSource> receiver) {
    receiver_.Bind(std::move(receiver));
  }

  MOCK_METHOD0(OnSinkGone, void());
  MOCK_METHOD0(OnStarted, void());
  MOCK_METHOD1(OnStartFailed, void(RemotingStartFailReason));
  MOCK_METHOD1(OnMessageFromSink, void(const std::vector<uint8_t>&));
  MOCK_METHOD1(OnStopped, void(RemotingStopReason));
  MOCK_METHOD1(OnSinkAvailable, void(const RemotingSinkMetadata&));
  void OnSinkAvailable(RemotingSinkMetadataPtr metadata) override {
    OnSinkAvailable(*metadata);
  }

 private:
  mojo::Receiver<media::mojom::RemotingSource> receiver_{this};
};

class MockMediaRemoter final : public media::mojom::Remoter {
 public:
  explicit MockMediaRemoter(CastRemotingConnector* connector) {
    connector->ConnectWithMediaRemoter(receiver_.BindNewPipeAndPassRemote(),
                                       source_.BindNewPipeAndPassReceiver());
  }

  void OnSinkAvailable() {
    EXPECT_TRUE(source_);
    source_->OnSinkAvailable(GetDefaultSinkMetadata());
  }

  MOCK_METHOD0(RequestStart, void());
  MOCK_METHOD0(StartWithPermissionAlreadyGranted, void());
  MOCK_METHOD1(Stop, void(RemotingStopReason));
  MOCK_METHOD1(SendMessageToSink, void(const std::vector<uint8_t>&));
  void Start() override {
    RequestStart();
    if (source_) {
      source_->OnStarted();
    }
  }

  MOCK_METHOD4(
      StartDataStreams,
      void(mojo::ScopedDataPipeConsumerHandle audio_pipe,
           mojo::ScopedDataPipeConsumerHandle video_pipe,
           mojo::PendingReceiver<media::mojom::RemotingDataStreamSender>
               audio_sender_receiver,
           mojo::PendingReceiver<media::mojom::RemotingDataStreamSender>
               video_sender_receiver));

 private:
  mojo::Receiver<media::mojom::Remoter> receiver_{this};
  mojo::Remote<media::mojom::RemotingSource> source_;
};

}  // namespace

class ParcCastRemotingConnectorTest : public testing::Test {
 public:
  ParcCastRemotingConnectorTest() { CreateConnector(true); }

  void TearDown() final { RunUntilIdle(); }

 protected:
  mojo::PendingRemote<media::mojom::Remoter> CreateRemoter(
      MockRemotingSource* source) {
    mojo::PendingRemote<media::mojom::RemotingSource> source_pending_remote;
    source->Bind(source_pending_remote.InitWithNewPipeAndPassReceiver());
    mojo::PendingRemote<media::mojom::Remoter> remoter_pending_remote;
    RemotingBridge::Client* clients[] = {connector_.get()};
    mojo::MakeSelfOwnedReceiver(
        std::make_unique<RemotingBridge>(clients,
                                         std::move(source_pending_remote)),
        remoter_pending_remote.InitWithNewPipeAndPassReceiver());
    return remoter_pending_remote;
  }

  static void RunUntilIdle() { base::RunLoop().RunUntilIdle(); }

  void CreateConnector(bool remoting_allowed) {
    connector_.reset();
    connector_.reset(new CastRemotingConnector(
        &pref_service_, kRemotingTabId,
        std::make_unique<MediaRemotingDialogCoordinator>()));
    connector_->set_remoting_allowed_for_testing(remoting_allowed);
  }

  CastRemotingConnector* GetConnector() const { return connector_.get(); }

  sync_preferences::TestingPrefServiceSyncable pref_service_;

 private:
  content::BrowserTaskEnvironment task_environment_;
  std::unique_ptr<CastRemotingConnector> connector_;
};

// Parc: a cast that failed to launch takes back the remoting request its pick
// sent, from each of the tab's sources while no session runs.
TEST_F(ParcCastRemotingConnectorTest,
       ParcDropsRemotingRequestsWithoutSession) {
  MockRemotingSource source;
  mojo::Remote<media::mojom::Remoter> remoter(CreateRemoter(&source));
  RunUntilIdle();

  EXPECT_CALL(source, OnStartFailed(RemotingStartFailReason::ROUTE_TERMINATED));
  GetConnector()->ParcDropRemotingRequests();
  RunUntilIdle();
  testing::Mock::VerifyAndClearExpectations(&source);

  std::unique_ptr<MockMediaRemoter> media_remoter =
      std::make_unique<MockMediaRemoter>(GetConnector());
  EXPECT_CALL(source, OnSinkAvailable(_));
  media_remoter->OnSinkAvailable();
  RunUntilIdle();
  EXPECT_CALL(source, OnStartFailed(_)).Times(0);
  GetConnector()->ParcDropRemotingRequests();
  RunUntilIdle();
}
