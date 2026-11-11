// Copyright 2026 Parc contributors.

#include "components/global_media_controls/media_item_manager_impl.h"

#include <memory>

#include "components/global_media_controls/public/test/mock_media_dialog_delegate.h"
#include "components/global_media_controls/public/test/mock_media_item_manager_observer.h"
#include "components/global_media_controls/public/test/mock_media_item_producer.h"
#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"

namespace global_media_controls {

namespace {

using testing::_;
using testing::NiceMock;

class ParcMediaItemManagerImplTest : public testing::Test {
 public:
  void SetUp() override {
    item_manager_ = std::make_unique<MediaItemManagerImpl>();
    item_manager_->AddObserver(&observer_);
  }

  void TearDown() override { item_manager_.reset(); }

 protected:
  test::MockMediaItemManagerObserver& observer() { return observer_; }
  MediaItemManagerImpl* item_manager() { return item_manager_.get(); }

 private:
  NiceMock<test::MockMediaItemManagerObserver> observer_;
  std::unique_ptr<MediaItemManagerImpl> item_manager_;
};

TEST_F(ParcMediaItemManagerImplTest,
       ReentrantClosePreservesReplacementSingleItem) {
  test::MockMediaItemProducer producer;
  item_manager()->AddItemProducer(&producer);
  producer.AddItem("foo", true, false, false);
  producer.AddItem("bar", true, false, false);
  NiceMock<test::MockMediaDialogDelegate> original;
  NiceMock<test::MockMediaDialogDelegate> replacement;
  item_manager()->SetDialogDelegate(&original);

  EXPECT_CALL(replacement, ShowMediaItem("foo", _)).Times(1);
  EXPECT_CALL(replacement, ShowMediaItem("bar", _)).Times(0);
  EXPECT_CALL(observer(), OnMediaDialogClosed()).WillOnce([&] {
    item_manager()->SetDialogDelegateForId(&replacement, "foo");
  });
  item_manager()->SetDialogDelegate(nullptr);
  testing::Mock::VerifyAndClearExpectations(&observer());
  item_manager()->SetDialogDelegate(nullptr);
}

}  // namespace

}  // namespace global_media_controls
