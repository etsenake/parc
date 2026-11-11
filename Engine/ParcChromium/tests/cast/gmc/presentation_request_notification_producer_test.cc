// Copyright 2026 Parc contributors.

#include "chrome/browser/ui/global_media_controls/presentation_request_notification_producer.h"

#include <memory>
#include <utility>

#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/unguessable_token.h"
#include "chrome/browser/media/router/chrome_media_router_factory.h"
#include "chrome/browser/ui/global_media_controls/presentation_request_notification_item.h"
#include "chrome/browser/ui/global_media_controls/test_helper.h"
#include "chrome/test/base/chrome_render_view_host_test_harness.h"
#include "components/global_media_controls/public/test/mock_device_service.h"
#include "components/media_router/browser/presentation/start_presentation_context.h"
#include "components/media_router/browser/test/mock_media_router.h"
#include "content/public/browser/presentation_request.h"
#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "url/gurl.h"
#include "url/origin.h"

namespace {

using global_media_controls::test::MockDevicePickerProvider;
using testing::NiceMock;

class ParcPresentationRequestNotificationProducerTest
    : public ChromeRenderViewHostTestHarness {
 public:
  ParcPresentationRequestNotificationProducerTest()
      : ChromeRenderViewHostTestHarness(
            base::test::TaskEnvironment::TimeSource::MOCK_TIME,
            base::test::TaskEnvironment::MainThreadType::UI) {}

  void SetUp() override {
    ChromeRenderViewHostTestHarness::SetUp();
    media_router::ChromeMediaRouterFactory::GetInstance()->SetTestingFactory(
        profile(), base::BindRepeating(&media_router::MockMediaRouter::Create));

    device_picker_host_ =
        std::make_unique<PresentationRequestNotificationProducer>(
            base::BindRepeating(
                &ParcPresentationRequestNotificationProducerTest::
                    HasActiveNotificationsForWebContents,
                base::Unretained(this)),
            base::UnguessableToken::Create());

    presentation_manager_ =
        std::make_unique<NiceMock<MockWebContentsPresentationManager>>();
    device_picker_host_->SetTestPresentationManager(
        presentation_manager_->GetWeakPtr());
    device_picker_host_->BindProvider(item_provider_.PassRemote());
  }

  void TearDown() override {
    media_router::WebContentsPresentationManager::SetTestInstance(nullptr);
    ChromeRenderViewHostTestHarness::TearDown();
  }

 protected:
  content::PresentationRequest CreatePresentationRequest() {
    return content::PresentationRequest(
        main_rfh()->GetGlobalId(),
        {GURL("http://example.com"), GURL("http://example2.com")},
        url::Origin::Create(GURL("http://google.com")));
  }

  bool HasActiveNotificationsForWebContents(
      content::WebContents* web_contents) {
    return true;
  }

  std::unique_ptr<PresentationRequestNotificationProducer> device_picker_host_;

 private:
  std::unique_ptr<MockWebContentsPresentationManager> presentation_manager_;
  MockDevicePickerProvider item_provider_;
};

// Parc: moving a native request's context into its device host retires the
// notification only after the matching token claims it.
TEST_F(ParcPresentationRequestNotificationProducerTest,
       NativeItemRetiresAfterContextMovesToDeviceHost) {
  const auto token = base::UnguessableToken::Create();
  auto context = std::make_unique<media_router::StartPresentationContext>(
      CreatePresentationRequest(), base::DoNothing(), base::DoNothing());
  context->SetNativeRequestToken(token);
  device_picker_host_->OnStartPresentationContextCreated(std::move(context));
  auto item = device_picker_host_->GetNotificationItem();
  ASSERT_TRUE(item);
  auto moved = item->PassContext();
  ASSERT_TRUE(moved);
  EXPECT_FALSE(device_picker_host_->TakeNativeContext(
      base::UnguessableToken::Create()));
  EXPECT_TRUE(device_picker_host_->GetNotificationItem());
  EXPECT_FALSE(device_picker_host_->TakeNativeContext(token));
  EXPECT_FALSE(device_picker_host_->GetNotificationItem());
}

}  // namespace
