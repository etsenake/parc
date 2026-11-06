// Copyright 2026 Parc contributors.
// Real BubbleManager callbacks. Controlled boundary controllers supply only
// visibility and callbacks; no queue/preemption/lifetime algorithm is copied.
#include "base/callback_list.h"
#include "base/functional/bind.h"
#include "base/test/bind.h"
#include "base/test/task_environment.h"
#include "chrome/browser/ui/autofill/bubble_manager_impl.h"
#include "components/tabs/public/mock_tab_interface.h"
#include "testing/gtest/include/gtest/gtest.h"
namespace parc {
namespace {
class QueueTab final : public tabs::MockTabInterface {
 public:
  bool IsActivated() const override { return active; }
  base::CallbackListSubscription RegisterDidActivate(
      DidActivateCallback callback) override {
    return activate.Add(std::move(callback));
  }
  base::CallbackListSubscription RegisterWillDeactivate(
      WillDeactivateCallback callback) override {
    return deactivate.Add(std::move(callback));
  }
  void Activate() {
    active = true;
    activate.Notify(this);
  }
  void Deactivate() {
    active = false;
    deactivate.Notify(this);
  }

 private:
  bool active = true;
  base::RepeatingCallbackList<void(tabs::TabInterface*)> activate, deactivate;
};
class QueueBoundary final : public autofill::BubbleControllerBase {
 public:
  explicit QueueBoundary(autofill::BubbleType kind) : kind_(kind) {}
  void ShowBubble() override {
    ++shows;
    visible = true;
  }
  void HideBubble(bool) override {
    ++hides;
    visible = false;
  }
  void OnBubbleDiscarded() override {
    ++discards;
    if (discarded) {
      std::move(discarded).Run();
    }
  }
  bool CanBeReshown() const override { return true; }
  bool ShouldReshowOnTabVisible() const override { return true; }
  autofill::BubbleType GetBubbleType() const override { return kind_; }
  bool IsShowingBubble() const override { return visible; }
  bool IsMouseHovered() const override { return true; }
  base::WeakPtr<autofill::BubbleControllerBase> GetBubbleControllerBaseWeakPtr()
      override {
    return weak_.GetWeakPtr();
  }
  int shows = 0, hides = 0, discards = 0;
  bool visible = false;
  base::OnceClosure discarded;

 private:
  autofill::BubbleType kind_;
  base::WeakPtrFactory<QueueBoundary> weak_{this};
};
class NativeAutofillQueueReentryTest : public testing::Test {
 protected:
  void SetUp() override {
    manager = std::make_unique<autofill::BubbleManagerImpl>(&tab);
    manager->RequestShowController(active, true);
    manager->RequestShowController(queued, false);
    ASSERT_TRUE(manager->HasPendingBubbleOfSameType(
        autofill::BubbleType::kSaveUpdateCard));
    // The production queue's timeout, not a replaced predicate.
    tasks.AdvanceClock(base::Days(1));
  }
  void TearDown() override { manager.reset(); }
  base::test::TaskEnvironment tasks{
      base::test::TaskEnvironment::TimeSource::MOCK_TIME};
  QueueTab tab;
  QueueBoundary active{autofill::BubbleType::kSaveUpdateCard};
  QueueBoundary queued{autofill::BubbleType::kSaveUpdateCard};
  QueueBoundary incoming{autofill::BubbleType::kOfferNotification};
  QueueBoundary replacement{autofill::BubbleType::kPassword};
  std::unique_ptr<autofill::BubbleManagerImpl> manager;
};
TEST_F(NativeAutofillQueueReentryTest,
       PreemptionExpiredCallbackMayDeleteManager) {
  queued.discarded = base::BindLambdaForTesting([this] { manager.reset(); });
  manager->RequestShowController(incoming, true);
  EXPECT_FALSE(manager);
  EXPECT_EQ(queued.discards, 1);
  EXPECT_EQ(active.hides, 0);
  EXPECT_EQ(incoming.shows, 0);
}
TEST_F(NativeAutofillQueueReentryTest,
       BackgroundExpiredCallbackMayDeleteManager) {
  queued.discarded = base::BindLambdaForTesting([this] { manager.reset(); });
  tab.Deactivate();
  EXPECT_FALSE(manager);
  EXPECT_EQ(queued.discards, 1);
  EXPECT_EQ(active.hides, 0);
}
TEST_F(NativeAutofillQueueReentryTest,
       NestedPreemptionMustNotHideOrOverwriteReplacement) {
  queued.discarded = base::BindLambdaForTesting(
      [this] { manager->RequestShowController(replacement, true); });
  manager->RequestShowController(incoming, true);
  EXPECT_EQ(queued.discards, 1);
  EXPECT_EQ(active.hides, 1);
  EXPECT_EQ(replacement.shows, 1);
  EXPECT_EQ(replacement.hides, 0);
  EXPECT_EQ(incoming.shows, 0);
  // The real manager still regards replacement as active: another non-forced
  // request queues behind its hovered view, rather than showing immediately.
  manager->RequestShowController(incoming, false);
  EXPECT_TRUE(manager->HasPendingBubbleOfSameType(
      autofill::BubbleType::kOfferNotification));
  EXPECT_EQ(incoming.shows, 0);
}
TEST_F(NativeAutofillQueueReentryTest,
       ExpiredCallbackCanDestroyAnotherQueuedController) {
  auto other =
      std::make_unique<QueueBoundary>(autofill::BubbleType::kOfferNotification);
  manager->RequestShowController(*other, false);
  ASSERT_TRUE(manager->HasPendingBubbleOfSameType(
      autofill::BubbleType::kOfferNotification));
  queued.discarded = base::BindLambdaForTesting([&other] { other.reset(); });
  active.HideBubble(false);
  manager->OnBubbleHiddenByController(active, true);
  EXPECT_FALSE(other);
  EXPECT_EQ(queued.discards, 1);
  EXPECT_FALSE(manager->HasPendingBubbleOfSameType(
      autofill::BubbleType::kOfferNotification));
  manager->RequestShowController(incoming, false);
  EXPECT_EQ(incoming.shows, 1);
}
TEST_F(NativeAutofillQueueReentryTest,
       DiscardCallbackDeactivatesTabWithoutShowingNextRequest) {
  manager->RequestShowController(incoming, false);
  queued.discarded = base::BindLambdaForTesting([this] { tab.Deactivate(); });
  active.HideBubble(false);
  manager->OnBubbleHiddenByController(active, true);
  EXPECT_EQ(queued.discards, 1);
  EXPECT_EQ(incoming.shows, 0);
  EXPECT_TRUE(manager->HasPendingBubbleOfSameType(
      autofill::BubbleType::kOfferNotification));
  tab.Activate();
  EXPECT_EQ(incoming.shows, 1);
}
}  // namespace
}  // namespace parc
