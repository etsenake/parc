// Copyright 2026 Parc contributors.
// This fixture is derived from Chromium's multi_buffer_data_source_unittest.cc
// (Chromium Authors; BSD-style license in Chromium's LICENSE) and contains
// only Parc regressions.

#include "third_party/blink/renderer/platform/media/multi_buffer_data_source.h"

#include <stddef.h>
#include <stdint.h>

#include <memory>
#include <set>
#include <utility>

#include "base/containers/heap_array.h"
#include "base/functional/callback_helpers.h"
#include "base/memory/scoped_refptr.h"
#include "base/numerics/safe_conversions.h"
#include "base/run_loop.h"
#include "base/strings/string_number_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "base/test/bind.h"
#include "base/test/task_environment.h"
#include "media/base/media_switches.h"
#include "media/base/media_util.h"
#include "media/base/mock_filters.h"
#include "media/base/mock_media_log.h"
#include "media/base/test_helpers.h"
#include "services/network/public/mojom/fetch_api.mojom-blink.h"
#include "third_party/blink/public/platform/web_url.h"
#include "third_party/blink/public/platform/web_url_response.h"
#include "third_party/blink/renderer/platform/media/buffered_data_source_host_impl.h"
#include "third_party/blink/renderer/platform/media/multi_buffer_reader.h"
#include "third_party/blink/renderer/platform/media/resource_multi_buffer_data_provider.h"
#include "third_party/blink/renderer/platform/media/testing/mock_resource_fetch_context.h"
#include "third_party/blink/renderer/platform/media/testing/mock_web_associated_url_loader.h"
#include "third_party/blink/renderer/platform/media/testing/test_response_generator.h"
#include "third_party/blink/renderer/platform/wtf/functional.h"

namespace blink {

using ::testing::_;
using ::testing::Assign;
using ::testing::InSequence;
using ::testing::NiceMock;
using ::testing::StrictMock;

namespace {

class TestMultiBufferDataProvider;

std::set<TestMultiBufferDataProvider*> test_data_providers;

class TestMultiBufferDataProvider : public ResourceMultiBufferDataProvider {
 public:
  TestMultiBufferDataProvider(
      UrlData* url_data,
      MultiBuffer::BlockId pos,
      scoped_refptr<base::SingleThreadTaskRunner> task_runner)
      : ResourceMultiBufferDataProvider(url_data,
                                        pos,
                                        false /* is_client_audio_element */,
                                        std::move(task_runner)) {
    CHECK(test_data_providers.insert(this).second);
  }
  ~TestMultiBufferDataProvider() override {
    CHECK_EQ(static_cast<size_t>(1), test_data_providers.erase(this));
  }

  // ResourceMultiBufferDataProvider overrides.
  void Start() override {
    ResourceMultiBufferDataProvider::Start();
    if (on_start_)
      std::move(on_start_).Run();
  }
  void SetDeferred(bool defer) override {
    deferred_ = defer;
    ResourceMultiBufferDataProvider::SetDeferred(defer);
  }

  bool loading() const { return !!active_loader_; }
  bool deferred() const { return deferred_; }
  void RunOnStart(base::OnceClosure cb) { on_start_ = std::move(cb); }

 private:
  bool deferred_ = false;
  base::OnceClosure on_start_;
};

class TestUrlData;

class TestResourceMultiBuffer : public ResourceMultiBuffer {
 public:
  TestResourceMultiBuffer(
      UrlData* url_data,
      int shift,
      scoped_refptr<base::SingleThreadTaskRunner> task_runner)
      : ResourceMultiBuffer(url_data, shift, task_runner),
        task_runner_(std::move(task_runner)) {}

  std::unique_ptr<MultiBuffer::DataProvider> CreateWriter(const BlockId& pos,
                                                          bool) override {
    auto writer = std::make_unique<TestMultiBufferDataProvider>(url_data_, pos,
                                                                task_runner_);
    writer->Start();
    return writer;
  }

  // TODO: Make these global

  TestMultiBufferDataProvider* GetProvider() {
    EXPECT_EQ(test_data_providers.size(), 1U);
    if (test_data_providers.size() != 1)
      return nullptr;
    return *test_data_providers.begin();
  }
  TestMultiBufferDataProvider* GetProvider_allownull() {
    EXPECT_LE(test_data_providers.size(), 1U);
    if (test_data_providers.size() != 1U)
      return nullptr;
    return *test_data_providers.begin();
  }
  bool HasProvider() const { return test_data_providers.size() == 1U; }
  bool loading() {
    if (test_data_providers.empty())
      return false;
    return GetProvider()->loading();
  }

 private:
  const scoped_refptr<base::SingleThreadTaskRunner> task_runner_;
};

class TestUrlData : public UrlData {
 public:
  TestUrlData(const KURL& url,
              CorsMode cors_mode,
              base::WeakPtr<UrlIndex> url_index,
              UrlData::CacheMode cache_mode,
              scoped_refptr<base::SingleThreadTaskRunner> task_runner,
              media::DataSource::EncodingMode encoding_mode =
                  media::DataSource::EncodingMode::kIdentity)
      : UrlData(url,
                cors_mode,
                encoding_mode,
                url_index,
                cache_mode,
                task_runner),
        block_shift_(url_index->block_shift()),
        task_runner_(std::move(task_runner)) {}

  ResourceMultiBuffer* multibuffer() override {
    if (!test_multibuffer_.get()) {
      test_multibuffer_ = std::make_unique<TestResourceMultiBuffer>(
          this, block_shift_, task_runner_);
    }
    return test_multibuffer_.get();
  }

  TestResourceMultiBuffer* test_multibuffer() {
    if (!test_multibuffer_.get()) {
      test_multibuffer_ = std::make_unique<TestResourceMultiBuffer>(
          this, block_shift_, task_runner_);
    }
    return test_multibuffer_.get();
  }

 private:
  ~TestUrlData() override = default;

  const int block_shift_;
  std::unique_ptr<TestResourceMultiBuffer> test_multibuffer_;
  const scoped_refptr<base::SingleThreadTaskRunner> task_runner_;
};

class TestUrlIndex : public UrlIndex {
 public:
  TestUrlIndex(ResourceFetchContext* fetch_context,
               scoped_refptr<base::SingleThreadTaskRunner> task_runner)
      : UrlIndex(fetch_context, task_runner),
        task_runner_(std::move(task_runner)) {}

  scoped_refptr<UrlData> NewUrlData(
      const KURL& url,
      UrlData::CorsMode cors_mode,
      UrlData::CacheMode cache_mode,
      media::DataSource::EncodingMode encoding_mode) override {
    NotifyNewUrlData(url, cors_mode, cache_mode);
    last_url_data_ = base::MakeRefCounted<TestUrlData>(
        url, cors_mode, weak_factory_.GetWeakPtr(), cache_mode, task_runner_,
        encoding_mode);
    return last_url_data_;
  }

  scoped_refptr<TestUrlData> last_url_data() {
    EXPECT_TRUE(last_url_data_);
    return last_url_data_;
  }

  MOCK_METHOD3(NotifyNewUrlData,
               void(KURL, UrlData::CorsMode, UrlData::CacheMode));

 private:
  scoped_refptr<TestUrlData> last_url_data_;
  const scoped_refptr<base::SingleThreadTaskRunner> task_runner_;
};

class MockBufferedDataSourceHost : public BufferedDataSourceHost {
 public:
  MockBufferedDataSourceHost() = default;
  MockBufferedDataSourceHost(const MockBufferedDataSourceHost&) = delete;
  MockBufferedDataSourceHost& operator=(const MockBufferedDataSourceHost&) =
      delete;
  ~MockBufferedDataSourceHost() override = default;

  MOCK_METHOD1(SetTotalBytes, void(int64_t total_bytes));
  MOCK_METHOD2(AddBufferedByteRange, void(int64_t start, int64_t end));
};

class MockMultiBufferDataSource : public MultiBufferDataSource {
 public:
  MockMultiBufferDataSource(
      const scoped_refptr<base::SingleThreadTaskRunner>& task_runner,
      scoped_refptr<UrlData> url_data,
      media::MediaLog* media_log,
      BufferedDataSourceHost* host)
      : MultiBufferDataSource(
            task_runner,
            std::move(url_data),
            media_log,
            host,
            BindRepeating(&MockMultiBufferDataSource::set_downloading,
                          Unretained(this))),
        downloading_(false) {}

  MockMultiBufferDataSource(const MockMultiBufferDataSource&) = delete;
  MockMultiBufferDataSource& operator=(const MockMultiBufferDataSource&) =
      delete;

  bool downloading() { return downloading_; }
  void set_downloading(bool downloading) { downloading_ = downloading; }
  bool range_supported() { return url_data_->range_supported(); }
  void CallSeekTask() { SeekTask(); }

 private:
  // Whether the resource is downloading or deferred.
  bool downloading_;
};

static const int64_t kFileSize = 5000000;
static const int kDataSize = 32 << 10;

static const char kHttpUrl[] = "http://localhost/foo.webm";
static const char kFileUrl[] = "file:///tmp/bar.webm";
static const char kHttpDifferentPathUrl[] = "http://localhost/bar.webm";

}  // namespace

class ParcMultiBufferDataSourceTest : public testing::Test {
 public:
  ParcMultiBufferDataSourceTest() : preload_(MultiBufferDataSource::AUTO) {
    ON_CALL(fetch_context_, CreateUrlLoader(_))
        .WillByDefault([](const WebAssociatedURLLoaderOptions&) {
          return std::make_unique<NiceMock<MockWebAssociatedURLLoader>>();
        });
  }

  ParcMultiBufferDataSourceTest(const ParcMultiBufferDataSourceTest&) = delete;
  ParcMultiBufferDataSourceTest& operator=(
      const ParcMultiBufferDataSourceTest&) = delete;

  MOCK_METHOD1(OnInitialize, void(bool));

  void InitializeWithCors(const char* url_string,
                          bool expected,
                          UrlData::CorsMode cors_mode,
                          size_t file_size = kFileSize) {
    KURL url(url_string);
    media_log_ = std::make_unique<NiceMock<media::MockMediaLog>>();
    data_source_ = std::make_unique<MockMultiBufferDataSource>(
        task_runner_, url_index_.GetByUrl(url, cors_mode, UrlData::kNormal),
        media_log_.get(), &host_);
    data_source_->SetPreload(preload_);

    response_generator_ =
        std::make_unique<TestResponseGenerator>(url, file_size);
    EXPECT_CALL(*this, OnInitialize(expected));
    data_source_->SetIsClientAudioElement(is_client_audio_element_);
    data_source_->Initialize(
        BindOnce(&ParcMultiBufferDataSourceTest::OnInitialize, Unretained(this)));
    base::RunLoop().RunUntilIdle();

    // Not really loading until after OnInitialize is called.
    EXPECT_EQ(data_source_->downloading(), false);
  }

  void Initialize(const char* url,
                  bool expected,
                  size_t file_size = kFileSize) {
    InitializeWithCors(url, expected, UrlData::CORS_UNSPECIFIED, file_size);
  }

  // Helper to initialize tests with a valid 200 response.
  void InitializeWith200Response() {
    Initialize(kHttpUrl, true);

    EXPECT_CALL(host_, SetTotalBytes(response_generator_->content_length()));
    Respond(response_generator_->Generate200());

    EXPECT_CALL(host_, AddBufferedByteRange(0, kDataSize));
    ReceiveData(kDataSize);
  }

  // Helper to initialize tests with a valid 206 response.
  void InitializeWith206Response(size_t file_size = kFileSize) {
    Initialize(kHttpUrl, true, file_size);

    EXPECT_CALL(host_, SetTotalBytes(response_generator_->content_length()));
    Respond(response_generator_->Generate206(0));
    EXPECT_CALL(host_, AddBufferedByteRange(0, kDataSize));
    ReceiveData(kDataSize);
  }

  // Helper to initialize tests with a valid file:// response.
  void InitializeWithFileResponse() {
    Initialize(kFileUrl, true);

    EXPECT_CALL(host_, SetTotalBytes(kFileSize));
    EXPECT_CALL(host_, AddBufferedByteRange(0, kFileSize));
    Respond(response_generator_->GenerateFileResponse(0));

    ReceiveData(kDataSize);
  }

  // Starts data source.
  void Start() {
    EXPECT_TRUE(data_provider());
    EXPECT_FALSE(active_loader_allownull());
    data_provider()->Start();
  }

  // Stops any active loaders and shuts down the data source.
  //
  // This typically happens when the page is closed and for our purposes is
  // appropriate to do when tearing down a test.
  void Stop() {
    if (loading()) {
      data_provider()->DidFail(response_generator_->GenerateError());
      base::RunLoop().RunUntilIdle();
    }

    data_source_->Stop();
    base::RunLoop().RunUntilIdle();
  }

  void Respond(const WebURLResponse& response) {
    EXPECT_TRUE(active_loader());
    data_provider()->DidReceiveResponse(response);
    base::RunLoop().RunUntilIdle();
  }

  void ReceiveDataLow(int size) {
    EXPECT_TRUE(active_loader());
    auto data = base::HeapArray<char>::Uninit(size);
    std::ranges::fill(data, 0xA5);  // Arbitrary non-zero value.

    data_provider()->DidReceiveData(data);
  }

  void ReceiveData(int size) {
    ReceiveDataLow(size);
    base::RunLoop().RunUntilIdle();
  }

  void FinishLoading() {
    EXPECT_TRUE(active_loader());
    data_provider()->DidFinishLoading();
    base::RunLoop().RunUntilIdle();
  }

  void FailLoading() {
    data_provider()->DidFail(response_generator_->GenerateError());
    base::RunLoop().RunUntilIdle();
  }

  MOCK_METHOD1(ReadCallback, void(int size));

  void ReadAt(int64_t position, int howmuch = kDataSize) {
    data_source_->Read(
        position,
        base::span(buffer_).first(base::checked_cast<size_t>(howmuch)),
        BindOnce(&ParcMultiBufferDataSourceTest::ReadCallback, Unretained(this)));
    base::RunLoop().RunUntilIdle();
  }

  void ExecuteMixedResponseSuccessTest(const WebURLResponse& response1,
                                       const WebURLResponse& response2) {
    EXPECT_CALL(host_, SetTotalBytes(kFileSize));
    EXPECT_CALL(host_, AddBufferedByteRange(0, kDataSize * 2));
    EXPECT_CALL(host_, AddBufferedByteRange(0, kDataSize));
    EXPECT_CALL(*this, ReadCallback(kDataSize)).Times(2);

    Respond(response1);
    ReceiveData(kDataSize);
    ReadAt(0);
    EXPECT_TRUE(loading());

    FinishLoading();
    Start();
    ReadAt(kDataSize);
    Respond(response2);
    ReceiveData(kDataSize);
    FinishLoading();
    Stop();
  }

  void ExecuteMixedResponseFailureTest(const WebURLResponse& response1,
                                       const WebURLResponse& response2) {
    EXPECT_CALL(host_, SetTotalBytes(kFileSize));
    EXPECT_CALL(host_, AddBufferedByteRange(0, kDataSize));
    EXPECT_CALL(*this, ReadCallback(kDataSize));
    // Stop() will also cause the readback to be called with kReadError, but
    // we want to make sure it was called before Stop().
    bool failed_ = false;
    EXPECT_CALL(*this, ReadCallback(media::DataSource::kReadError))
        .WillOnce(Assign(&failed_, true));

    Respond(response1);
    ReceiveData(kDataSize);
    ReadAt(0);
    EXPECT_TRUE(loading());

    FinishLoading();
    Start();
    ReadAt(kDataSize);
    Respond(response2);
    EXPECT_TRUE(failed_);
    Stop();
  }

  void CheckCapacityDefer() {
    EXPECT_EQ(2 << 20, preload_low());
    EXPECT_EQ(3 << 20, preload_high());
  }

  void CheckReadThenDefer() {
    EXPECT_EQ(2 << 14, preload_low());
    EXPECT_EQ(3 << 14, preload_high());
  }

  void CheckNeverDefer() {
    EXPECT_EQ(1LL << 40, preload_low());
    EXPECT_EQ(1LL << 40, preload_high());
  }

  // Accessors for private variables on |data_source_|.
  MultiBufferReader* loader() { return data_source_->reader_.get(); }

  TestResourceMultiBuffer* multibuffer() {
    return url_index_.last_url_data()->test_multibuffer();
  }

  TestMultiBufferDataProvider* data_provider() {
    return multibuffer()->GetProvider();
  }
  WebAssociatedURLLoader* active_loader() {
    EXPECT_TRUE(data_provider());
    if (!data_provider())
      return nullptr;
    return data_provider()->active_loader_.get();
  }
  WebAssociatedURLLoader* active_loader_allownull() {
    TestMultiBufferDataProvider* data_provider =
        multibuffer()->GetProvider_allownull();
    if (!data_provider)
      return nullptr;
    return data_provider->active_loader_.get();
  }
  bool loading() { return multibuffer()->loading(); }

  MultiBufferDataSource::Preload preload() { return data_source_->preload_; }
  void set_preload(MultiBufferDataSource::Preload preload) {
    preload_ = preload;
  }
  int64_t preload_high() {
    CHECK(loader());
    return loader()->preload_high();
  }
  int64_t preload_low() {
    CHECK(loader());
    return loader()->preload_low();
  }
  int data_source_bitrate() { return data_source_->bitrate_; }
  int64_t max_buffer_forward() { return loader()->max_buffer_forward_; }
  int64_t max_buffer_backward() { return loader()->max_buffer_backward_; }
  int64_t buffer_size() {
    return loader()->current_buffer_size_ * 32768 /* block size */;
  }
  double data_source_playback_rate() { return data_source_->playback_rate_; }
  bool is_local_source() { return data_source_->AssumeFullyBuffered(); }
  bool is_client_audio_element() { return loader()->is_client_audio_element_; }
  scoped_refptr<UrlData> url_data() { return data_source_->url_data_; }
  void set_might_be_reused_from_cache_in_future(bool value) {
    url_data()->set_cacheable(value);
  }
  void set_is_client_audio_element(bool value) {
    is_client_audio_element_ = value;
  }

  media::DataSource::Preload GetPreload(MultiBufferDataSource* source) {
    return source->preload_;
  }
  bool GetIsClientAudioElement(MultiBufferDataSource* source) {
    return source->is_client_audio_element_;
  }
  bool LoadsForCast(MultiBufferDataSource* source) {
    return source->url_data_->ParcCasting();
  }
  void CallOnRedirected(MultiBufferDataSource* source,
                        const scoped_refptr<UrlData>& data) {
    source->OnRedirected(data);
  }

 protected:
  base::test::SingleThreadTaskEnvironment task_environment_;
  MultiBufferDataSource::Preload preload_;
  NiceMock<MockResourceFetchContext> fetch_context_;
  const scoped_refptr<base::SingleThreadTaskRunner> task_runner_ =
      task_environment_.GetMainThreadTaskRunner();
  TestUrlIndex url_index_{&fetch_context_, task_runner_};

  std::unique_ptr<media::MediaLog> media_log_;
  std::unique_ptr<MockMultiBufferDataSource> data_source_;

  std::unique_ptr<TestResponseGenerator> response_generator_;

  StrictMock<MockBufferedDataSourceHost> host_;

  // Used for calling MultiBufferDataSource::Read().
  uint8_t buffer_[kDataSize * 2];

  bool is_client_audio_element_ = false;
};

// Parc: a source whose player a Safari-identity element moved to another frame
// keeps what it loaded and loads the rest through that frame's index, which
// takes what the response told about the resource (ParcMoveToUrlIndex()).
TEST_F(ParcMultiBufferDataSourceTest, ParcMoveToUrlIndexLoadsThroughNewIndex) {
  InitializeWith206Response();
  NiceMock<MockResourceFetchContext> moved_fetch_context;
  TestUrlIndex moved_url_index(&moved_fetch_context, task_runner_);
  EXPECT_CALL(moved_fetch_context, CreateUrlLoader(_))
      .Times(testing::AtLeast(1))
      .WillRepeatedly([](const WebAssociatedURLLoaderOptions&) {
        return std::make_unique<NiceMock<MockWebAssociatedURLLoader>>();
      });
  EXPECT_CALL(fetch_context_, CreateUrlLoader(_)).Times(0);

  data_source_->ParcMoveToUrlIndex(moved_url_index);
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(moved_url_index.last_url_data(), url_data());
  EXPECT_EQ(kFileSize, url_data()->length());
  EXPECT_TRUE(url_data()->range_supported());
  EXPECT_TRUE(url_data()->multibuffer()->Contains(0));

  data_source_->Stop();
  base::RunLoop().RunUntilIdle();
}

// Parc: a resource read without ranges goes on loading in the old frame, and
// through the new frame's index, with what it loaded, once that load fails, as
// when the old frame goes.
TEST_F(ParcMultiBufferDataSourceTest,
       ParcMovedLoadWithoutRangesGoesOnWhenItFails) {
  InitializeWith200Response();
  scoped_refptr<UrlData> old_url_data = url_data();
  NiceMock<MockResourceFetchContext> moved_fetch_context;
  TestUrlIndex moved_url_index(&moved_fetch_context, task_runner_);
  EXPECT_CALL(moved_fetch_context, CreateUrlLoader(_)).Times(0);
  data_source_->ParcMoveToUrlIndex(moved_url_index);
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(old_url_data, url_data());
  testing::Mock::VerifyAndClearExpectations(&moved_fetch_context);

  EXPECT_CALL(moved_fetch_context, CreateUrlLoader(_))
      .Times(testing::AtLeast(1))
      .WillRepeatedly([](const WebAssociatedURLLoaderOptions&) {
        return std::make_unique<NiceMock<MockWebAssociatedURLLoader>>();
      });
  old_url_data->Fail();
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(moved_url_index.last_url_data(), url_data());
  EXPECT_TRUE(url_data()->multibuffer()->Contains(0));
  EXPECT_FALSE(url_data()->range_supported());

  data_source_->Stop();
  base::RunLoop().RunUntilIdle();
}


// Special carve-out for Apache versions that choose to return a 200 for
// Range:0- ("because it's more efficient" than a 206)


// Test the case where the initial response from the server indicates that
// Range requests are supported, but a later request prove otherwise.


// Parc: a casting player's source keeps its loads running in a frozen frame
// (UrlData::ParcSetCasting()).
TEST_F(ParcMultiBufferDataSourceTest, ParcCastingSourceLoadsRunWhileFrozen) {
  InitializeWith206Response();
  auto* loader = static_cast<MockWebAssociatedURLLoader*>(active_loader());
  EXPECT_CALL(*loader, ParcSetRunsWhileFrozen(true));
  data_source_->ParcSetCasting(true);
  testing::Mock::VerifyAndClearExpectations(loader);

  // A load started while casting runs while frozen from its start.
  EXPECT_CALL(fetch_context_, CreateUrlLoader(_))
      .WillOnce([](const WebAssociatedURLLoaderOptions&) {
        auto new_loader =
            std::make_unique<NiceMock<MockWebAssociatedURLLoader>>();
        InSequence sequence;
        EXPECT_CALL(*new_loader, ParcSetRunsWhileFrozen(true));
        EXPECT_CALL(*new_loader, LoadAsynchronously(_, _));
        return new_loader;
      })
      .RetiresOnSaturation();
  EXPECT_CALL(*this, ReadCallback(kDataSize));
  ReadAt(0);
  ReadAt(kDataSize);
  FinishLoading();
  Start();

  loader = static_cast<MockWebAssociatedURLLoader*>(active_loader());
  EXPECT_CALL(*loader, ParcSetRunsWhileFrozen(false));
  data_source_->ParcSetCasting(false);
  testing::Mock::VerifyAndClearExpectations(loader);

  Respond(response_generator_->Generate206(kDataSize));
  EXPECT_CALL(*this, ReadCallback(kDataSize));
  EXPECT_CALL(host_, AddBufferedByteRange(0, kDataSize * 2));
  ReceiveData(kDataSize);
  Stop();
}

// A source that isn't casting leaves its loads to its frame's freezing.
TEST_F(ParcMultiBufferDataSourceTest, ParcSourceNotCastingLeavesLoadsFrozen) {
  EXPECT_CALL(fetch_context_, CreateUrlLoader(_))
      .WillOnce([](const WebAssociatedURLLoaderOptions&) {
        auto new_loader =
            std::make_unique<NiceMock<MockWebAssociatedURLLoader>>();
        EXPECT_CALL(*new_loader, ParcSetRunsWhileFrozen(_)).Times(0);
        return new_loader;
      })
      .RetiresOnSaturation();
  InitializeWith206Response();
  EXPECT_CALL(*this, ReadCallback(kDataSize));
  ReadAt(0);
  Stop();
}


// Make sure that we prefetch across partial responses. (crbug.com/41192138).


// This test tries to trigger an edge case where the read callback
// never happens because the reader is deleted before that happens.

// This test tries to trigger an edge case where the read callback
// never happens because the reader is deleted before that happens.


// This test triggers an edge case where request destination is not
// properly set to "audio" (crbug.com/12345). The edge case is triggered when
// preload omitted or is set to metadata, and a read from an unbuffered range
// takes place.


// Provoke an edge case where the loading state may not end up transitioning
// back to "idle" when we're done loading.


// Parc: the sources of Chromium's HLS player follow their factory's casting,
// those it made before included.
TEST_F(ParcMultiBufferDataSourceTest, ParcFactorySourcesLoadForCast) {
  MultiBufferDataSource::Factory factory(
      std::make_unique<NiceMock<media::MockMediaLog>>(),
      base::BindRepeating(
          [](UrlIndex* url_index, const GURL& url,
             media::DataSource::CacheMode cache_mode,
             media::DataSource::EncodingMode encoding_mode,
             base::OnceCallback<void(scoped_refptr<UrlData>)> cb) {
            std::move(cb).Run(
                url_index->GetByUrl(KURL(url), UrlData::CORS_UNSPECIFIED,
                                    UrlData::kNormal, encoding_mode));
          },
          base::Unretained(&url_index_)),
      /*is_audio_element=*/false,
      /*preload=*/media::DataSource::AUTO, base::DoNothing(), nullptr,
      task_runner_);
  auto create = [&factory](const char* url) {
    std::unique_ptr<media::CrossOriginDataSource> created_source;
    factory.Create(
        GURL(url), media::DataSource::CacheMode::kHitCache,
        media::DataSource::EncodingMode::kIdentity,
        base::BindLambdaForTesting(
            [&](std::unique_ptr<media::CrossOriginDataSource> source) {
              created_source = std::move(source);
            }));
    base::RunLoop().RunUntilIdle();
    return created_source;
  };

  auto before = create(kHttpUrl);
  auto* before_source = static_cast<MultiBufferDataSource*>(before.get());
  EXPECT_FALSE(LoadsForCast(before_source));

  factory.ParcSetCasting(true);
  EXPECT_TRUE(LoadsForCast(before_source));
  auto during = create(kHttpDifferentPathUrl);
  auto* during_source = static_cast<MultiBufferDataSource*>(during.get());
  EXPECT_TRUE(LoadsForCast(during_source));

  before.reset();
  factory.ParcSetCasting(false);
  EXPECT_FALSE(LoadsForCast(during_source));
}


}  // namespace blink
