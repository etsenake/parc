// Copyright 2026 Parc contributors.
// This fixture is derived from Chromium's resource_loader_test.cc
// (Chromium Authors; BSD-style license in Chromium's LICENSE) and contains
// only Parc regressions.

#include "third_party/blink/renderer/platform/loader/fetch/resource_loader.h"

#include <utility>

#include "base/task/single_thread_task_runner.h"
#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "third_party/blink/public/mojom/fetch/fetch_api_request.mojom-blink.h"
#include "third_party/blink/public/mojom/use_counter/metrics/web_feature.mojom-blink.h"
#include "third_party/blink/public/platform/resource_load_info_notifier_wrapper.h"
#include "third_party/blink/public/platform/web_url.h"
#include "third_party/blink/renderer/platform/heap/garbage_collected.h"
#include "third_party/blink/renderer/platform/instrumentation/use_counter.h"
#include "third_party/blink/renderer/platform/loader/fetch/console_logger.h"
#include "third_party/blink/renderer/platform/loader/fetch/detachable_use_counter.h"
#include "third_party/blink/renderer/platform/loader/fetch/raw_resource.h"
#include "third_party/blink/renderer/platform/loader/fetch/resource_fetcher.h"
#include "third_party/blink/renderer/platform/loader/fetch/resource_load_scheduler.h"
#include "third_party/blink/renderer/platform/loader/fetch/resource_response.h"
#include "third_party/blink/renderer/platform/loader/fetch/url_loader/url_loader.h"
#include "third_party/blink/renderer/platform/loader/fetch/url_loader/url_loader_factory.h"
#include "third_party/blink/renderer/platform/loader/testing/mock_fetch_context.h"
#include "third_party/blink/renderer/platform/loader/testing/test_resource_fetcher_properties.h"
#include "third_party/blink/renderer/platform/scheduler/test/task_environment.h"
#include "third_party/blink/renderer/platform/testing/mock_context_lifecycle_notifier.h"
#include "third_party/blink/renderer/platform/testing/noop_url_loader.h"
#include "third_party/blink/renderer/platform/testing/testing_platform_support.h"

namespace blink {

namespace {

class MockUseCounter : public GarbageCollected<MockUseCounter>,
                       public UseCounter {
 public:
  MOCK_METHOD1(CountUse, void(mojom::WebFeature));
  MOCK_METHOD1(CountWebDXFeature, void(mojom::blink::WebDXFeature));
  MOCK_METHOD1(CountDeprecation, void(mojom::WebFeature));
};

}  // namespace

class ParcResourceLoaderTest : public testing::Test {
 public:
  ParcResourceLoaderTest() = default;
  ParcResourceLoaderTest(const ParcResourceLoaderTest&) = delete;
  ParcResourceLoaderTest& operator=(const ParcResourceLoaderTest&) = delete;

 protected:
  test::TaskEnvironmentWithMainThreadScheduler task_environment_;
  ScopedTestingPlatformSupport<TestingPlatformSupport> platform_;

  class NoopLoaderFactory final : public ResourceFetcher::LoaderFactory {
    std::unique_ptr<URLLoader> CreateURLLoader(
        const network::ResourceRequest& request,
        const ResourceLoaderOptions& options,
        scoped_refptr<base::SingleThreadTaskRunner> freezable_task_runner,
        scoped_refptr<base::SingleThreadTaskRunner> unfreezable_task_runner,
        BackForwardCacheLoaderHelper* back_forward_cache_loader_helper,
        const std::optional<base::UnguessableToken>&
            service_worker_race_network_request_token,
        bool is_from_origin_dirty_style_sheet) override {
      return std::make_unique<NoopURLLoader>(std::move(freezable_task_runner));
    }
    CodeCacheHost* GetCodeCacheHost() override { return nullptr; }
  };

  scoped_refptr<base::SingleThreadTaskRunner> CreateTaskRunner() {
    return task_environment_.GetMainThreadTaskRunner();
  }

  ResourceFetcher* MakeResourceFetcher(
      TestResourceFetcherProperties* properties,
      FetchContext* context) {
    ResourceFetcherInit init(
        properties->MakeDetachable(), context, CreateTaskRunner(),
        CreateTaskRunner(), MakeGarbageCollected<NoopLoaderFactory>(),
        MakeGarbageCollected<MockContextLifecycleNotifier>(),
        /*back_forward_cache_loader_helper=*/nullptr);
    use_counter_ = MakeGarbageCollected<testing::StrictMock<MockUseCounter>>();
    init.use_counter = MakeGarbageCollected<DetachableUseCounter>(use_counter_);
    return MakeGarbageCollected<ResourceFetcher>(std::move(init));
  }

 private:
  Persistent<MockUseCounter> use_counter_;
};

// Parc: a casting player's load (ResourceLoader::ParcSetRunsWhileFrozen()).
TEST_F(ParcResourceLoaderTest, ParcLoadRunsWhileFrozen) {
  auto* properties = MakeGarbageCollected<TestResourceFetcherProperties>();
  FetchContext* context = MakeGarbageCollected<MockFetchContext>();
  auto* fetcher = MakeResourceFetcher(properties, context);

  KURL url("data:text/plain,Hello%20World!");
  ResourceRequest request(url);
  request.SetRequestContext(mojom::blink::RequestContextType::FETCH);
  FetchParameters params = FetchParameters::CreateForTest(std::move(request));
  Resource* resource = RawResource::Fetch(params, fetcher, nullptr);
  properties->SetFreezeMode(LoaderFreezeMode::kStrict);
  fetcher->SetDefersLoading(LoaderFreezeMode::kStrict);
  task_environment_.RunUntilIdle();
  EXPECT_EQ(resource->GetStatus(), ResourceStatus::kPending);

  // Its frame freezing again leaves it running.
  resource->Loader()->ParcSetRunsWhileFrozen(true);
  fetcher->SetDefersLoading(LoaderFreezeMode::kStrict);
  task_environment_.RunUntilIdle();
  EXPECT_EQ(resource->GetStatus(), ResourceStatus::kCached);
}

// A load that stops running while frozen is frozen with its frame again.
TEST_F(ParcResourceLoaderTest, ParcLoadFrozenAgainWhenItStopsRunning) {
  auto* properties = MakeGarbageCollected<TestResourceFetcherProperties>();
  FetchContext* context = MakeGarbageCollected<MockFetchContext>();
  auto* fetcher = MakeResourceFetcher(properties, context);

  KURL url("data:text/plain,Hello%20World!");
  ResourceRequest request(url);
  request.SetRequestContext(mojom::blink::RequestContextType::FETCH);
  FetchParameters params = FetchParameters::CreateForTest(std::move(request));
  Resource* resource = RawResource::Fetch(params, fetcher, nullptr);
  properties->SetFreezeMode(LoaderFreezeMode::kStrict);
  fetcher->SetDefersLoading(LoaderFreezeMode::kStrict);
  task_environment_.RunUntilIdle();

  resource->Loader()->ParcSetRunsWhileFrozen(true);
  resource->Loader()->ParcSetRunsWhileFrozen(false);
  task_environment_.RunUntilIdle();
  EXPECT_EQ(resource->GetStatus(), ResourceStatus::kPending);

  properties->SetFreezeMode(LoaderFreezeMode::kNone);
  fetcher->SetDefersLoading(LoaderFreezeMode::kNone);
  task_environment_.RunUntilIdle();
  EXPECT_EQ(resource->GetStatus(), ResourceStatus::kCached);
}

namespace {

class ParcStartRecordingURLLoader final : public URLLoader {
 public:
  ParcStartRecordingURLLoader(
      scoped_refptr<base::SingleThreadTaskRunner> task_runner,
      bool& started)
      : task_runner_(std::move(task_runner)), started_(started) {}

  void LoadSynchronously(
      std::unique_ptr<network::ResourceRequest>,
      scoped_refptr<const SecurityOrigin>,
      bool,
      bool,
      base::TimeDelta,
      URLLoaderClient*,
      WebURLResponse&,
      std::optional<WebURLError>&,
      scoped_refptr<SharedBuffer>&,
      int64_t&,
      uint64_t&,
      scoped_refptr<BlobDataHandle>&,
      std::unique_ptr<blink::ResourceLoadInfoNotifierWrapper>) override {
    NOTREACHED();
  }
  void LoadAsynchronously(
      std::unique_ptr<network::ResourceRequest>,
      scoped_refptr<const SecurityOrigin>,
      bool,
      std::unique_ptr<blink::ResourceLoadInfoNotifierWrapper>,
      CodeCacheHost*,
      URLLoaderClient*) override {
    started_ = true;
  }
  void Freeze(LoaderFreezeMode) override {}
  void DidChangePriority(WebURLRequest::Priority, int) override {}
  scoped_refptr<base::SingleThreadTaskRunner> GetTaskRunnerForBodyLoader()
      override {
    return task_runner_;
  }

 private:
  scoped_refptr<base::SingleThreadTaskRunner> task_runner_;
  bool& started_;
};

class ParcStartRecordingLoaderFactory final
    : public ResourceFetcher::LoaderFactory {
 public:
  explicit ParcStartRecordingLoaderFactory(bool& started) : started_(started) {}

  std::unique_ptr<URLLoader> CreateURLLoader(
      const network::ResourceRequest&,
      const ResourceLoaderOptions&,
      scoped_refptr<base::SingleThreadTaskRunner> freezable_task_runner,
      scoped_refptr<base::SingleThreadTaskRunner>,
      BackForwardCacheLoaderHelper*,
      const std::optional<base::UnguessableToken>&,
      bool) override {
    return std::make_unique<ParcStartRecordingURLLoader>(
        std::move(freezable_task_runner), started_);
  }
  CodeCacheHost* GetCodeCacheHost() override { return nullptr; }

 private:
  bool& started_;
};

}  // namespace

// A load a frozen frame holds back starts once it runs while frozen.
TEST_F(ParcResourceLoaderTest, ParcLoadHeldByFrozenFrameStarts) {
  bool started = false;
  auto* properties = MakeGarbageCollected<TestResourceFetcherProperties>();
  properties->SetFreezeMode(LoaderFreezeMode::kStrict);
  FetchContext* context = MakeGarbageCollected<MockFetchContext>();
  ResourceFetcherInit init(
      properties->MakeDetachable(), context, CreateTaskRunner(),
      CreateTaskRunner(),
      MakeGarbageCollected<ParcStartRecordingLoaderFactory>(started),
      MakeGarbageCollected<MockContextLifecycleNotifier>(),
      /*back_forward_cache_loader_helper=*/nullptr);
  auto* fetcher = MakeGarbageCollected<ResourceFetcher>(std::move(init));
  auto* scheduler = MakeGarbageCollected<ResourceLoadScheduler>(
      ResourceLoadScheduler::ThrottlingPolicy::kNormal,
      ResourceLoadScheduler::ThrottleOptionOverride::kNone,
      properties->MakeDetachable(), /*frame_or_worker_scheduler=*/nullptr,
      *MakeGarbageCollected<DetachableConsoleLogger>(),
      /*loading_behavior_observer=*/nullptr);
  scheduler->OnLifecycleStateChanged(
      scheduler::SchedulingLifecycleState::kStopped);

  ResourceRequest request(KURL("https://foo.test/video.mp4"));
  request.SetRequestContext(mojom::blink::RequestContextType::VIDEO);
  Resource* resource = RawResource::CreateForTest(request, ResourceType::kRaw);
  auto* loader = MakeGarbageCollected<ResourceLoader>(
      fetcher, scheduler, resource,
      MakeGarbageCollected<MockContextLifecycleNotifier>());
  loader->Start();
  task_environment_.RunUntilIdle();
  EXPECT_FALSE(started);

  loader->ParcSetRunsWhileFrozen(true);
  EXPECT_TRUE(started);

}  // namespace blink
