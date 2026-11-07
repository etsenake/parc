// Installed by the reviewed overlay at
// //media/filters/parc_native_hls_routing_unittest.cc (media_unittests, macOS).
// Safari's native HLS route (NATIVE_HLS.md): DemuxerManager's HLS branch asks
// its client for the route's demuxer when Safari's identity is presented, and
// keeps Chromium's ManifestDemuxer otherwise.

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
// A playlist in a data: URL, the way Spotify's player hands its generated
// ones to the element (this one is empty).
constexpr char kDataPlaylist[] =
    "data:application/vnd.apple.mpegurl;base64,"
    "I0VYVE0zVQojRVhULVgtRU5ETElTVAo=";

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

class ParcNativeHlsRoutingTest : public testing::Test {
 protected:
  DemuxerManager& MakeManager(FakeClient& client, const char* url) {
    manager_ = std::make_unique<DemuxerManager>(
        &client, url::Origin::Create(GURL(kPlaylist)),
        task_environment_.GetMainThreadTaskRunner(), &media_log_,
        /*demuxer_override=*/nullptr);
    manager_->SetLoadedUrl(GURL(url));
    return *manager_;
  }

  // Runs the HLS branch for `url` and returns the demuxer it chose.
  Demuxer* CreateDemuxer(FakeClient& client,
                         DataSource::Preload preload = DataSource::AUTO,
                         bool needs_first_frame = true,
                         const char* url = kPlaylist) {
    MakeManager(client, url);
    Demuxer* chosen = nullptr;
    PipelineStatus status = manager_->CreateDemuxer(
        /*load_media_source=*/false, preload, needs_first_frame,
        base::BindOnce(
            [](Demuxer** out, Pipeline::StartType* type_out, Demuxer* demuxer,
               Pipeline::StartType start_type, bool /*is_streaming*/,
               bool /*is_static*/) -> PipelineStatus {
              *out = demuxer;
              *type_out = start_type;
              return OkStatus();
            },
            &chosen, &start_type_));
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
  // The start type CreateDemuxer chose last.
  Pipeline::StartType start_type_ = Pipeline::StartType::kNormal;
};

namespace {

TEST_F(ParcNativeHlsRoutingTest, ChromeIdentityKeepsManifestDemuxer) {
  FakeClient client(task_environment_.GetMainThreadTaskRunner());
  client.native_demuxer = std::make_unique<testing::NiceMock<MockDemuxer>>();

  Demuxer* chosen = CreateDemuxer(client);
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

  EXPECT_EQ(CreateDemuxer(client), native_ptr);
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

// A preload="metadata" element without a poster would take Chromium's
// suspended start (suspend after metadata). Safari's native HLS player never
// does: WebKit's preload rules live in the GPU player, and a seek issued then
// (the page's start position) must complete instead of being lost across the
// suspend and resume. WebMediaPlayerImpl keeps it from every later suspend by
// HasParcNativeHlsDemuxer(), before the renderer type is known.
TEST_F(ParcNativeHlsRoutingTest, NativeDemuxerNeverTakesSuspendedStart) {
  FakeClient client(task_environment_.GetMainThreadTaskRunner());
  client.safari_identity = true;
  auto native = std::make_unique<testing::NiceMock<MockDemuxer>>();
  Demuxer* native_ptr = native.get();
  client.native_demuxer = std::move(native);

  EXPECT_EQ(CreateDemuxer(client, DataSource::METADATA,
                          /*needs_first_frame=*/false),
            native_ptr);
  EXPECT_EQ(start_type_, Pipeline::StartType::kNormal);
  EXPECT_TRUE(manager_->HasParcNativeHlsDemuxer());
}

// Chromium's own HLS demuxer keeps Chromium's suspended start.
TEST_F(ParcNativeHlsRoutingTest, ManifestDemuxerKeepsSuspendedStart) {
  FakeClient client(task_environment_.GetMainThreadTaskRunner());

  Demuxer* chosen = CreateDemuxer(client, DataSource::METADATA,
                                  /*needs_first_frame=*/false);
  ASSERT_TRUE(chosen);
  EXPECT_EQ(chosen->GetDemuxerType(), DemuxerType::kManifestDemuxer);
  EXPECT_EQ(start_type_, Pipeline::StartType::kSuspendAfterMetadata);
  EXPECT_FALSE(manager_->HasParcNativeHlsDemuxer());
}

TEST_F(ParcNativeHlsRoutingTest, NoNativeDemuxerFallsBackToManifestDemuxer) {
  FakeClient client(task_environment_.GetMainThreadTaskRunner());
  client.safari_identity = true;

  Demuxer* chosen = CreateDemuxer(client);
  ASSERT_TRUE(chosen);
  EXPECT_TRUE(client.asked);
  EXPECT_EQ(chosen->GetDemuxerType(), DemuxerType::kManifestDemuxer);
  EXPECT_FALSE(manager_->HasParcNativeHlsDemuxer());
}

// Safari takes a data: URL's type from the URL and AVFoundation decodes the
// playlist itself: the route gets the URL as it is, with that type.
TEST_F(ParcNativeHlsRoutingTest, SafariIdentityPlaysHlsDataUrlNatively) {
  FakeClient client(task_environment_.GetMainThreadTaskRunner());
  client.safari_identity = true;
  auto native = std::make_unique<testing::NiceMock<MockDemuxer>>();
  Demuxer* native_ptr = native.get();
  client.native_demuxer = std::move(native);

  EXPECT_EQ(CreateDemuxer(client, DataSource::AUTO, /*needs_first_frame=*/true,
                          kDataPlaylist),
            native_ptr);
  ASSERT_TRUE(client.last_params);
  EXPECT_EQ(client.last_params->url, GURL(kDataPlaylist));
  EXPECT_EQ(client.last_params->mime_type, "application/vnd.apple.mpegurl");
  EXPECT_FALSE(manager_->HasDataSource());
}

TEST_F(ParcNativeHlsRoutingTest, OnlySafariIdentityHlsDataUrlsTakeTheRoute) {
  FakeClient client(task_environment_.GetMainThreadTaskRunner());
  EXPECT_EQ(MakeManager(client, kDataPlaylist).ParcNativeHlsDataUrlMimeType(),
            "");
  client.safari_identity = true;
  EXPECT_EQ(MakeManager(client, kDataPlaylist).ParcNativeHlsDataUrlMimeType(),
            "application/vnd.apple.mpegurl");
  EXPECT_EQ(MakeManager(client, "data:Audio/X-MpegURL,%23EXTM3U")
                .ParcNativeHlsDataUrlMimeType(),
            "audio/x-mpegurl");
  EXPECT_EQ(MakeManager(client,
                        "data:application/vnd.apple.mpegurl;foo=bar;base64,"
                        "I0VYVE0zVQo=")
                .ParcNativeHlsDataUrlMimeType(),
            "application/vnd.apple.mpegurl");
  EXPECT_EQ(MakeManager(client, "data:audio/mp4;base64,AAAA")
                .ParcNativeHlsDataUrlMimeType(),
            "");
  EXPECT_EQ(MakeManager(client, kPlaylist).ParcNativeHlsDataUrlMimeType(), "");
}

}  // namespace
}  // namespace media
