// Installed by the reviewed overlay at
// //media/filters/parc_native_hls_routing_unittest.cc (media_unittests, macOS).
// Safari's native HLS route (NATIVE_HLS.md): DemuxerManager's HLS branch asks
// its client for the route's demuxer only with the route on
// (parc::fairplay::kNativeHlsEnabled, which the fixture overrides) and
// Safari's identity presented, and keeps Chromium's ManifestDemuxer otherwise.

#include <memory>
#include <optional>
#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/run_loop.h"
#include "base/task/sequenced_task_runner.h"
#include "base/test/task_environment.h"
#include "media/base/media_util.h"
#include "media/base/mock_filters.h"
#include "media/base/renderer_factory.h"
#include "media/filters/demuxer_manager.h"
#include "media/filters/hls_test_helpers.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "url/gurl.h"
#include "url/origin.h"

namespace media {
namespace {

constexpr char kPlaylist[] = "https://media.example/stream/master.m3u8";

class FakeClient : public DemuxerManager::Client {
 public:
  explicit FakeClient(scoped_refptr<base::SequencedTaskRunner> task_runner)
      : task_runner_(std::move(task_runner)) {}

  // DemuxerManager::Client.
  void OnEncryptedMediaInitData(EmeInitDataType,
                                const std::vector<uint8_t>&) override {}
  void OnChunkDemuxerOpened(ChunkDemuxer*) override {}
  void OnProgress() override {}
  void OnError(PipelineStatus) override {}
  void StopForDemuxerReset() override {}
  void RestartForHls() override {}
  base::SequenceBound<HlsDataSourceProvider> GetHlsDataSourceProvider()
      override {
    return base::SequenceBound<MockHlsDataSourceProvider>(task_runner_);
  }
  bool CouldPlayIfEnoughData() override { return false; }
  void MakeDemuxerThreadDumper(Demuxer*) override {}
  double CurrentTime() const override { return 0; }
  void UpdateLoadedUrl(const GURL&) override {}
  void DemuxerRequestsSeek(base::TimeDelta) override {}
  void AddTrack(const MediaTrack&) override {}
  void RemoveTrack(const MediaTrack&) override {}
  void SetTrackState(const MediaTrack&, MediaTrack::State) override {}
  bool PresentsParcSafariIdentity() override { return safari_identity; }
  std::unique_ptr<Demuxer> CreateParcNativeHlsDemuxer(
      ParcNativeHlsDemuxerParams params) override {
    asked = true;
    last_params = std::move(params);
    return std::move(native_demuxer);
  }

  bool safari_identity = false;
  std::unique_ptr<Demuxer> native_demuxer;
  bool asked = false;
  std::optional<ParcNativeHlsDemuxerParams> last_params;

 private:
  scoped_refptr<base::SequencedTaskRunner> task_runner_;
};

}  // namespace

// A friend of DemuxerManager, so it can turn the route on.
class ParcNativeHlsRoutingTest : public testing::Test {
 protected:
  // Runs the HLS branch for `kPlaylist` with the route `on` and returns the
  // demuxer it chose.
  Demuxer* CreateDemuxer(FakeClient& client, bool on) {
    manager_ = std::make_unique<DemuxerManager>(
        &client, url::Origin::Create(GURL(kPlaylist)),
        task_environment_.GetMainThreadTaskRunner(), &media_log_,
        /*demuxer_override=*/nullptr);
    manager_->parc_native_hls_enabled_ = on;
    manager_->SetLoadedUrl(GURL(kPlaylist));
    Demuxer* chosen = nullptr;
    PipelineStatus status = manager_->CreateDemuxer(
        /*load_media_source=*/false, DataSource::AUTO,
        /*needs_first_frame=*/true,
        base::BindOnce(
            [](Demuxer** out, Demuxer* demuxer, Pipeline::StartType,
               bool /*is_streaming*/, bool /*is_static*/) -> PipelineStatus {
              *out = demuxer;
              return OkStatus();
            },
            &chosen));
    EXPECT_TRUE(status.is_ok());
    return chosen;
  }

  void TearDown() override {
    if (manager_) {
      manager_->StopAndResetClient();
      manager_.reset();
    }
    task_environment_.RunUntilIdle();
  }

  base::test::TaskEnvironment task_environment_;
  NullMediaLog media_log_;
  std::unique_ptr<DemuxerManager> manager_;
};

namespace {

TEST_F(ParcNativeHlsRoutingTest, OffKeepsManifestDemuxer) {
  FakeClient client(task_environment_.GetMainThreadTaskRunner());
  client.safari_identity = true;
  client.native_demuxer = std::make_unique<testing::NiceMock<MockDemuxer>>();

  Demuxer* chosen = CreateDemuxer(client, /*on=*/false);
  ASSERT_TRUE(chosen);
  EXPECT_EQ(chosen->GetDemuxerType(), DemuxerType::kManifestDemuxer);
  EXPECT_FALSE(client.asked);
}

TEST_F(ParcNativeHlsRoutingTest, ChromeIdentityKeepsManifestDemuxer) {
  FakeClient client(task_environment_.GetMainThreadTaskRunner());
  client.native_demuxer = std::make_unique<testing::NiceMock<MockDemuxer>>();

  Demuxer* chosen = CreateDemuxer(client, /*on=*/true);
  ASSERT_TRUE(chosen);
  EXPECT_EQ(chosen->GetDemuxerType(), DemuxerType::kManifestDemuxer);
  EXPECT_FALSE(client.asked);
}

TEST_F(ParcNativeHlsRoutingTest, SafariIdentityTakesNativeDemuxer) {
  FakeClient client(task_environment_.GetMainThreadTaskRunner());
  client.safari_identity = true;
  auto native = std::make_unique<testing::NiceMock<MockDemuxer>>();
  Demuxer* native_ptr = native.get();
  client.native_demuxer = std::move(native);

  EXPECT_EQ(CreateDemuxer(client, /*on=*/true), native_ptr);
  ASSERT_TRUE(client.asked);
  ASSERT_TRUE(client.last_params);
  EXPECT_EQ(client.last_params->url, GURL(kPlaylist));
  // The type came from the path, so AVFoundation infers it as in WebKit.
  EXPECT_TRUE(client.last_params->mime_type.empty());
  EXPECT_TRUE(client.last_params->media_task_runner);
  EXPECT_TRUE(client.last_params->media_log);
  EXPECT_TRUE(client.last_params->encrypted_media_init_data_cb);
  // There is no data source: AVPlayer loads everything itself.
  EXPECT_FALSE(manager_->HasDataSource());
  EXPECT_FALSE(manager_->WouldTaintOrigin());
}

TEST_F(ParcNativeHlsRoutingTest, NoNativeDemuxerFallsBackToManifestDemuxer) {
  FakeClient client(task_environment_.GetMainThreadTaskRunner());
  client.safari_identity = true;

  Demuxer* chosen = CreateDemuxer(client, /*on=*/true);
  ASSERT_TRUE(chosen);
  EXPECT_TRUE(client.asked);
  EXPECT_EQ(chosen->GetDemuxerType(), DemuxerType::kManifestDemuxer);
}

}  // namespace
}  // namespace media
