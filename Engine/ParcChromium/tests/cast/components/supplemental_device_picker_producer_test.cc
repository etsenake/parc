// Copyright 2026 Parc contributors.

#include "components/global_media_controls/public/supplemental_device_picker_producer.h"

#include <memory>
#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/unguessable_token.h"
#include "components/global_media_controls/public/mojom/device_service.mojom.h"
#include "components/global_media_controls/public/test/mock_device_service.h"
#include "components/global_media_controls/public/test/mock_media_item_manager.h"
#include "content/public/test/browser_task_environment.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"

namespace global_media_controls {

namespace {

using test::MockDevicePickerObserver;

class ParcSupplementalDevicePickerProducerTest : public testing::Test {
 protected:
  std::unique_ptr<MockDevicePickerObserver> CreateObserver() {
    auto observer = std::make_unique<MockDevicePickerObserver>();
    provider_remote_->AddObserver(observer->PassRemote());
    provider_remote_.FlushForTesting();
    return observer;
  }

  content::BrowserTaskEnvironment task_environment_;
  test::MockMediaItemManager item_manager_;
  SupplementalDevicePickerProducer notification_producer_{&item_manager_};
  mojo::Remote<mojom::DevicePickerProvider> provider_remote_{
      notification_producer_.PassRemote()};
};

TEST_F(ParcSupplementalDevicePickerProducerTest,
       NativeReentrantCloseDoesNotClearReplacementLifecycle) {
  using Event = SupplementalDevicePickerProducer::NativeLifecycleEvent;
  const auto first = base::UnguessableToken::Create();
  const auto second = base::UnguessableToken::Create();
  std::vector<std::pair<int, Event>> events;
  auto second_callback = base::BindRepeating(
      [](std::vector<std::pair<int, Event>>* events, Event event) {
        events->emplace_back(2, event);
      }, &events);
  auto first_callback = base::BindRepeating(
      [](SupplementalDevicePickerProducer* producer,
         base::UnguessableToken second,
         SupplementalDevicePickerProducer::NativeLifecycleCallback second_callback,
         std::vector<std::pair<int, Event>>* events, Event event) {
        events->emplace_back(1, event);
        if (event == Event::kClosed) {
          producer->PrepareNativeLifecycle(second, second_callback);
          producer->OnMediaDialogOpened();
        }
      }, &notification_producer_, second, second_callback, &events);
  notification_producer_.PrepareNativeLifecycle(first, first_callback);
  notification_producer_.OnMediaDialogOpened();
  notification_producer_.OnMediaDialogClosed();
  notification_producer_.ClearNativeLifecycle(first);
  notification_producer_.OnMediaDialogClosed();
  EXPECT_THAT(events, testing::ElementsAre(
      std::make_pair(1, Event::kOpened), std::make_pair(1, Event::kClosed),
      std::make_pair(2, Event::kOpened), std::make_pair(2, Event::kClosed)));
}

TEST_F(ParcSupplementalDevicePickerProducerTest,
       OrdinaryDialogCancelsPendingNativeWithoutConsumingItsLifecycle) {
  auto observer = CreateObserver();
  bool canceled = false;
  auto token = base::UnguessableToken::Create();
  notification_producer_.WatchPendingNativeLifecycle(
      token, base::BindOnce([](bool* canceled) { *canceled = true; }, &canceled));
  EXPECT_CALL(*observer, OnMediaUIOpened);
  EXPECT_CALL(*observer, OnMediaUIClosed);
  notification_producer_.OnMediaDialogOpened();
  notification_producer_.OnMediaDialogClosed();
  observer->FlushForTesting();
  EXPECT_TRUE(canceled);
  EXPECT_FALSE(notification_producer_.HasPendingNativeLifecycle(token));
}

}  // namespace

}  // namespace global_media_controls
