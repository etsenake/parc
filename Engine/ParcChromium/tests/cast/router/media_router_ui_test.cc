// Copyright 2026 Parc contributors.

#include "chrome/browser/ui/media_router/media_router_ui.h"

#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/test/bind.h"
#include "build/build_config.h"
#include "chrome/browser/media/router/chrome_media_router_factory.h"
#include "chrome/browser/media/router/providers/wired_display/wired_display_media_route_provider.h"
#include "chrome/browser/sessions/session_tab_helper_factory.h"
#include "chrome/browser/ui/media_router/media_cast_mode.h"
#include "chrome/test/base/chrome_render_view_host_test_harness.h"
#include "components/media_router/browser/logger_impl.h"
#include "components/media_router/browser/media_router_factory.h"
#include "components/media_router/browser/media_sinks_observer.h"
#include "components/media_router/browser/test/mock_media_router.h"
#include "components/media_router/common/media_route.h"
#include "components/media_router/common/media_source.h"
#include "components/media_router/common/route_request_result.h"
#include "components/media_router/common/test/test_helper.h"
#include "components/sessions/content/session_tab_helper.h"
#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "url/origin.h"

using testing::_;
using testing::Mock;
using testing::Return;

namespace media_router {

namespace {

constexpr char kSinkId[] = "sink1";
constexpr char kSinkName[] = "sink name";

ACTION_TEMPLATE(SaveArgWithMove,
                HAS_1_TEMPLATE_PARAMS(int, k),
                AND_1_VALUE_PARAMS(pointer)) {
  *pointer = std::move(::testing::get<k>(args));
}

}  // namespace

class ParcMediaRouterViewsUITest : public ChromeRenderViewHostTestHarness {
 public:
  void SetUp() override {
    ChromeRenderViewHostTestHarness::SetUp();

    SetMediaRouterFactory();
    mock_router_ = static_cast<MockMediaRouter*>(
        MediaRouterFactory::GetApiForBrowserContext(GetBrowserContext()));
    logger_ = std::make_unique<LoggerImpl>();

    // Store sink observers so that they can be notified in tests.
    ON_CALL(*mock_router_, RegisterMediaSinksObserver(_))
        .WillByDefault([this](MediaSinksObserver* observer) {
          media_sinks_observers_.push_back(observer);
          return true;
        });
    ON_CALL(*mock_router_, GetLogger()).WillByDefault(Return(logger_.get()));

    CreateSessionServiceTabHelper(web_contents());
    ui_ =
        MediaRouterUI::CreateWithDefaultMediaSourceAndMirroring(web_contents());
  }

  void TearDown() override {
#if BUILDFLAG(IS_MAC)
    clear_screen_capture_allowed_for_testing();
#endif
    ui_.reset();
    ChromeRenderViewHostTestHarness::TearDown();
  }

  void SetMediaRouterFactory() {
    ChromeMediaRouterFactory::GetInstance()->SetTestingFactory(
        GetBrowserContext(), base::BindRepeating(&MockMediaRouter::Create));
  }

 protected:
  std::vector<raw_ptr<MediaSinksObserver, VectorExperimental>>
      media_sinks_observers_;
  raw_ptr<MockMediaRouter, DanglingUntriaged> mock_router_ = nullptr;
  std::unique_ptr<MediaRouterUI> ui_;
  std::unique_ptr<LoggerImpl> logger_;
};

// Parc: a cast's result callback learns whether its route was created, even
// after the dialog closed.
TEST_F(ParcMediaRouterViewsUITest, ParcStartCastingRunsResultCallback) {
  MediaSource media_source = MediaSource::ForTab(
      sessions::SessionTabHelper::IdForTab(web_contents()).id());
  MediaSink sink{CreateCastSink(kSinkId, kSinkName)};
  for (MediaSinksObserver* sinks_observer : media_sinks_observers_) {
    sinks_observer->OnSinksUpdated({sink}, std::vector<url::Origin>());
  }
  MediaRouteResponseCallback launched_callback;
  MediaRouteResponseCallback failed_callback;
  EXPECT_CALL(*mock_router_, CreateRouteInternal(media_source.id(), kSinkId, _,
                                                 web_contents(), _, _))
      .WillOnce(SaveArgWithMove<4>(&launched_callback))
      .WillOnce(SaveArgWithMove<4>(&failed_callback));
  std::optional<bool> launched;
  ui_->ParcStartCasting(
      kSinkId, MediaCastMode::TAB_MIRROR,
      base::BindLambdaForTesting([&](bool result) { launched = result; }));
  std::optional<bool> failed_launched;
  ui_->ParcStartCasting(
      kSinkId, MediaCastMode::TAB_MIRROR,
      base::BindLambdaForTesting([&](bool result) { failed_launched = result; }));
  Mock::VerifyAndClearExpectations(mock_router_);
  ui_.reset();

  std::move(failed_callback)
      .Run(nullptr,
           *RouteRequestResult::FromError(
               "failed", mojom::RouteRequestResultCode::ROUTE_NOT_FOUND));
  EXPECT_EQ(false, failed_launched);

  MediaRoute route(MediaRoute::GetMediaRouteId("id", kSinkId, media_source),
                   media_source, kSinkId, /* description */ std::string(),
                   /* is_local */ true);
  std::move(launched_callback)
      .Run(nullptr, *RouteRequestResult::FromSuccess(route, "id"));
  EXPECT_EQ(true, launched);
}

}  // namespace media_router
