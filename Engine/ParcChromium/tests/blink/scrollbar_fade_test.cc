// Copyright 2026 Parc contributors.

#include "third_party/blink/renderer/core/scroll/scrollable_area.h"

#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "third_party/blink/renderer/core/scroll/scroll_types.h"
#include "third_party/blink/renderer/core/scroll/scrollbar_test_suite.h"
#include "third_party/blink/renderer/core/scroll/scrollbar_theme_overlay_mock.h"
#include "third_party/blink/renderer/platform/heap/thread_state.h"
#include "third_party/blink/renderer/platform/testing/paint_test_configurations.h"
#include "third_party/blink/renderer/platform/testing/task_environment.h"
#include "third_party/blink/renderer/platform/testing/testing_platform_support.h"
#include "third_party/blink/renderer/platform/testing/unit_test_helpers.h"

namespace blink {
namespace {

using testing::Return;

class ParcScrollbarThemeOverlayMockWithVisibilityOwner
    : public ScrollbarThemeOverlayMock {
 public:
  bool BlinkControlsOverlayVisibility() const override {
    return blink_controls_overlay_visibility_;
  }
  void SetBlinkControlsOverlayVisibility(bool value) {
    blink_controls_overlay_visibility_ = value;
  }

 private:
  bool blink_controls_overlay_visibility_ = true;
};

class ParcMockScrollableAreaWithPageTheme : public MockScrollableArea {
 public:
  explicit ParcMockScrollableAreaWithPageTheme(ScrollbarTheme* theme)
      : MockScrollableArea(ScrollOffset(0, 100)), theme_(theme) {}

  ScrollbarTheme& GetPageScrollbarTheme() const override { return *theme_; }
  bool ScrollbarsHiddenIfOverlay() const override {
    return ScrollableArea::ScrollbarsHiddenIfOverlay();
  }
  void ScrollbarVisibilityChanged() override { ++visibility_changes_; }
  int visibility_changes() const { return visibility_changes_; }

 private:
  bool MayCompositeScrollbar(const Scrollbar&) const override { return false; }

  ScrollbarTheme* theme_;
  int visibility_changes_ = 0;
};

class ParcScrollableAreaTest : public testing::Test,
                               public PaintTestConfigurations {
 protected:
  test::TaskEnvironment task_environment_;
};

INSTANTIATE_PAINT_TEST_SUITE_P(ParcScrollableAreaTest);

// Turning off device emulation on Mac can switch the page to a theme that does
// not let Blink control overlay visibility while the fade timer is pending.
// The fade must not use Blink's DCHECKed visibility path, but must still leave
// the scrollbar hidden for the new theme's animator.
TEST_P(ParcScrollableAreaTest, OverlayScrollbarFadeAfterThemeChange) {
  ScopedTestingPlatformSupport<TestingPlatformSupport> platform;

  ParcScrollbarThemeOverlayMockWithVisibilityOwner theme;
  theme.SetOverlayScrollbarFadeOutDelay(base::Milliseconds(1));
  ParcMockScrollableAreaWithPageTheme* scrollable_area =
      MakeGarbageCollected<ParcMockScrollableAreaWithPageTheme>(&theme);
  EXPECT_CALL(*scrollable_area, UsesCompositedScrolling())
      .WillRepeatedly(Return(false));
  Scrollbar* scrollbar = Scrollbar::CreateForTesting(
      scrollable_area, kHorizontalScrollbar, &theme);
  EXPECT_CALL(*scrollable_area, HorizontalScrollbar())
      .WillRepeatedly(Return(scrollbar));

  scrollable_area->ShowNonMacOverlayScrollbars();
  EXPECT_EQ(1, scrollable_area->visibility_changes());
  EXPECT_FALSE(scrollable_area->ScrollbarsHiddenIfOverlay());

  // The new theme's animator starts hidden, so the pending fade still hides
  // the scrollbar and takes it out of hit testing.
  theme.SetBlinkControlsOverlayVisibility(false);
  test::RunDelayedTasks(base::Milliseconds(10));
  EXPECT_EQ(2, scrollable_area->visibility_changes());
  EXPECT_TRUE(scrollable_area->ScrollbarsHiddenIfOverlay());
  EXPECT_FALSE(scrollbar->ShouldParticipateInHitTesting());

  // A theme that lets Blink control visibility still shows and fades out.
  theme.SetBlinkControlsOverlayVisibility(true);
  scrollable_area->ShowNonMacOverlayScrollbars();
  EXPECT_EQ(3, scrollable_area->visibility_changes());
  test::RunDelayedTasks(base::Milliseconds(10));
  EXPECT_EQ(4, scrollable_area->visibility_changes());
  EXPECT_TRUE(scrollable_area->ScrollbarsHiddenIfOverlay());

  // Forced GC in order to finalize objects depending on the mock object.
  ThreadState::Current()->CollectAllGarbageForTesting();
}

}  // namespace
}  // namespace blink
